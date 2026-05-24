# OmniScope 优化方案

编码风格：./plan/rules/rules.md 


 一个建议：SemanticKind 的 9 个 variant 可以再精简。allocation、release、provenance 三个是核心，ownership_transfer、borrow、escape 其实是 DFG 层的事，SRT 只需要回答"这个值能不能解释掉"，不需要理解完整的别名/借用语义。过重的 kind 会让 pattern
注册变复杂。

---

## 已完成的优化

### 1. DangerSurfacePass Phase 2 — 已实现

问题: 原先对每个 MemoryGraph 节点调用 isOnDangerPathFull()，每次都分配 72,532 元素数组 + 2 个 HashMap。15K+ 节点 = 上千万次无谓分配。

方案: 内联廉价检查 + 预构建 ffi_set
- (1) 检查 node.zone == .unsafe
- (2) 检查跨语言生命周期（alloc_lang != free_lang）
- (3) 检查 FFI arg（通过 getCallArgsForPtr + ffi_set.contains）
- (4) 检查 FFI ret（通过 getCallRetsForPtr + ffi_set.contains）
- (5) 只有以上都失败且节点有 alias 时才走 isOnDangerPath

状态: 构建通过，小测试用例验证正确。

### 2. 报告函数内存泄漏 — 已修复 14 处

ptr_lifetime_report.zig (13处) + free_validation.zig (1处) 添加了 errdefer issue.deinit(ctx.allocator)。

### 3. cross_language_free 误报修复 — 已实现

问题: `classifyFreeLanguage("free")` 返回 `"c"`，`langToString(.c)` 返回 `"C/C++"`，字符串比较永远不等，导致所有 C 模块内部 malloc+free 对都被误报为跨语言问题。ffi-demo 上 80% FP 率。

方案:
- `ptr_lifetime_classify.zig`: 新增 `classifyAllocLanguageEnum()` — 返回 Language enum 而非字符串
- `ptr_lifetime.zig`: heap_alloc 的 `trackAlloc` 改用 `classifyAllocLanguageEnum(callee_name) orelse lang`，让 alloc_lang 反映实际分配器（如 malloc→.c）而非模块语言
- `ptr_lifetime_violations.zig`: 新增 `freeLangToLanguage()` + generic mismatch 改为 enum 比较

效果: ffi-demo FP 从 8 降到 1（-87.5%），precision 从 20% 提升到 50%。

---

## 待做优化方案

### 3. 实现通用语义解析树 (Universal Semantic Resolution Tree)

基于 improve.md 中的第二种方案，实现一个通用语义解析框架，通过语言适配器注册模式，而不是为每种语言创建专门的图结构。

#### 3.1 核心架构

创建分层架构：
- SemanticTree: 通用语义树
- PatternRegistry: 语义模式注册系统
- Language Adapters: 各语言的模式适配器
- SemanticResolverPass: 语义解析 pass

#### 3.2 具体任务

- [x] 创建通用语义树核心模块 (src/semantics/semantic_tree.zig)
- [x] 实现语义模式注册系统 (src/semantics/semantic_patterns.zig)
- [x] 创建语言适配器目录结构
- [ ] 实现 Rust 模式适配器 (src/adapters/rust/patterns.zig)
- [ ] 实现语义解析引擎 (src/semantics/resolution_engine.zig)
- [ ] 创建语义解析 pass (src/pass/analysis/semantic_resolver_pass.zig)
- [ ] 集成到现有管道中
- [ ] 更新内存图以使用语义解析结果

#### 3.3 优势

- 跨语言通用，避免为每种语言创建专门的图结构
- 通过模式注册系统，易于扩展新语言
- 先让语言"自证安全"，解释不掉的再进入主分析
- 性能更好，减少不必要的分析

### 4. isOnDangerPathFull 全局缓存（影响多 pass）

PassContext.isOnDangerPathFull() (pass.zig:898) 不只被 DangerSurfacePass 调用。可以把 ffi_set 缓存到 PassContext 中，首次构建后复用，避免每次重建。

### 5. PointerOwnership init 阶段性能分析（~17s）

#### 根因：init 阶段做了 3 次全量 IR 扫描

**Source 1 — MemoryGraph 遍历**（`pointer_ownership.zig:300-344`）：
- 遍历 `memory_graph.nodes` 的每个节点
- 每个节点调用 `resolveInstFuncName()` → 3 次 LLVM C API 调用（`LLVMGetInstructionParent` → `LLVMGetBasicBlockParent` → `LLVMGetValueName`）

**Source 2 — GlobalAllocTracker 遍历**（`:366-395`）：
- 线性扫描所有 tracker records，相对轻量

**Source 3 — IR 级 free 指令扫描**（`:409-449`）← 最贵
- 三重循环：所有非声明、非 safe-zone 的函数 → 所有 basic block → 所有指令
- 每个 `LLVMCall` 指令执行：
  - `isFreeInstruction()`：2 次 LLVM C API + `SemanticRegistry.lookup` + 最多 6 次子串匹配
  - 匹配后：`LLVMGetOperand` + `getOrPutId` + `identifyLanguageFromCallee` + `classifyFree`
- for 一个 17MB 的 wasmtime_test.bc：几万指令 × 每次 5-10 次 LLVM C API FFI 调用 = 秒级开销

#### 低垂果实

| 问题 | 优化方向 |
|------|---------|
| `resolveInstFuncName` 每个节点 3 次 LLVM API | 在 `MemoryGraph.Node` 里直接缓存 `func_name` |
| Source 3 扫描所有指令，但 `isFreeInstruction` 只对 call/invoke 生效 | 只遍历 call 指令（LLVM API：`LLVMGetFirstCall` / `LLVMGetNextCall`） |
| Source 1/2 coverage 接近 0，Source 3 在兜底做最重的工作 | 修复 `ptr_lifetime.zig`，真正 populate `MemoryGraph.freed_by` |
| isFreeInstruction/classifyFree 每个 call 做 3 次 LLVM C API | 预构建 free 函数名集合，O(1) 查询 |

### 6. PointerOwnership analysis 阶段性能分析（~12s）

C1 优化已合并为单次遍历，但仍然对每个函数 × BB × 指令做：
- `analyzeInstructionForOwnership()`: 分配/释放分类
- 所有权流图构建（`addFlowEdge`）
- `null_check_recognizer.recognizeInFunction()`
- `detectStructMemberStores()`
- RAII 检测 / drop 检测

问题: 这些操作对 Rust 编译器生成函数（Vec 迭代器、drop glue、闭包等）都是白费的。

### 7. Rust 编译器生成代码的通用过滤方案

#### 当前问题

当前过滤依赖名称模式白名单：
- `_ZN4core` / `_ZN3std` / `_ZN5alloc`（`noise_filter.zig:108-118`）
- `drop_in_place` / `$LT$` / `$GT$`（`noise_filter.zig:145-173`）
- `isRustFFIRelevantFunction`（`pointer_ownership.zig:716`）扫描每条指令找 extern 调用

**致命缺陷**：
1. 每个新 Rust 项目（wasmtime、cranelift、ring 等）的 crate 名不在白名单里 → 漏过滤
2. `isRustFFIRelevantFunction` 对每个函数做 O(指令数) 扫描 → 太慢
3. 白名单要不断维护 → 不可扩展

#### 设计原则

经过多轮 review，最终方案应该满足以下约束：

1. **不依赖 crate 名字** — 不准出现 `_ZN4core`、`_ZN8wasmtime` 类白名单
2. **不依赖 per-function 指令扫描** — 不能为判断"是否 FFI 相关"而遍历函数的 body
3. **不误杀 FFI producer crate** — `Box::into_raw`、`extern \"C\" fn create_ctx` 这些无 extern call 但参与所有权传播的必须保留
4. **不误杀 dependency crate** — `ring`、`libsqlite3-sys` 等 *-sys crate 的 FFI boundary 必须覆盖
5. **语言无关** — C++ STL、Go generated binding 也能复用

#### 推荐方案：三层层叠过滤（不是互斥，是叠加）

单个方案的精度都不足以做 final decision。正确的做法是三层分级过滤，每层解决的粒度不同，且后一层是前一层的补偿：

```
Layer 1 — Linkage Heuristic（O(1) 零 FFI 调用）
Layer 2 — Debug Origin（读取 IR metadata，无指令遍历）
Layer 3 — CallGraph Reachability（O(V+E) 图传播）
```

---

##### Layer 1: Linkage Heuristic（最便宜，最先跑）

**信号**：`LLVMGetLinkage` + debug info 存在性

```
internal + !has_dbg                  → CompilerArtifact (strong)
linkonce_odr + !has_dbg              → CompilerArtifact (strong)
available_externally + !has_dbg      → CompilerArtifact (medium)
internal + has_dbg (remapped path)   → Unknown（降级到 L2）
```

**为什么有效**：Rust 编译器生成的 drop glue、panic 卸载函数、monomorphized 内部函数大多没有 debug info（或被 remap 掉）。用户写的函数几乎总有 debug info。

**精度**：单独用不够（用户的泛型函数也可能 `linkonce_odr`），但能砍掉大量纯内部噪音。

**成本**：`LLVMGetLinkage` 是 O(1) 字段读取，零 FFI 调用链。

**致命缺陷补偿**：→ 误杀的由 L3 的 callgraph reachability 捞回

---

##### Layer 2: Debug Origin（IR metadata 路径分析）

**信号**：`!dbg DISubprogram → DIFile.filename + directory`

```
SourceOrigin:
  USER_CODE       — workspace/src/...
  STDLIB          — /rustc/<hash>/library/...
  DEPENDENCY      — .cargo/registry/... / target/debug/build/...
  BUILD_GENERATED — target/release/build/...
  UNKNOWN         — missing dbg / fully remapped（降级到保留分析）
```

**为什么比 whitelist 好**：不是名字匹配，是 provenance 匹配。Rust 的 stdlib 源代码路径是 `/rustc/<hash>/library/core/src/...`，无论哪个版本、哪个项目，路径结构一样。无需维护 crate 名列表。

**`--remap-path-prefix` 的应对**：
- 当 ALL paths 被 remap 为同一格式（如全是 `/rustc/<hash>/`）→ 标记为 UNKNOWN，不据此做 skip decision
- 降级到 L3 callgraph 判断

**成本**：读取 `!dbg` metadata 需要一次 LLVM metadata 查询，比 linkage 贵但比指令遍历便宜几个数量级。

---

##### Layer 3: CallGraph Reachability（语义最强，最后跑）

**思路**：从分析意义明确的起始点出发，做 forward（或 backward）reachability。

**Root 定义**（不要只取 workspace，否则漏 *-sys）：
```
Roots:
  extern "C" 导出函数（无论哪个 crate）
  CrossLangEdge 涉及函数
  DISubprogram.file 在 workspace 内的函数
  extern declarations 的直接 caller
```

**Forward Walk**：
```
reachable = {roots} 闭包
  每步追踪 call 指令的目标（包括间接调用，若可解析）
  标记 reachable = true
```

**剪枝**：
```
reachable = true  → KEEP（包括依赖 crate 中的 FFI 相关函数）
reachable = false → SKIP（纯内部 islands: alloc::raw_vec, core::fmt, panic_unwind...）
```

**为什么 L3 是补偿**：
- L1 误杀的泛型用户函数，如果它被 workspace root 调用 → L3 捞回
- L2 被 remap 搞成 UNKNOWN 的，如果它 reachable → 保留分析（安全）

**成本**：O(V+E) 图遍历，一次性的，放在 pipeline 早期。

---

#### 总结：三层协同

| Layer | 信号来源 | 成本 | 精度 | 误杀补偿 |
|-------|---------|------|------|---------|
| L1 Linkage | `LLVMGetLinkage` + `has_dbg` | O(1) per func | 低（单独用） | L3 捞回 |
| L2 Debug Origin | `DISubprogram→DIFile` path | O(1) per func | 中 | remap 时降级到保留 |
| L3 CallGraph | CallSiteIndex + forward walk | O(V+E) 一次 | 高 | 无（最终仲裁者） |

**最终 decision**：
```
if L1 == CompilerArtifact && L3 == not_reachable → SKIP
if L2 == STDLIB && L3 == not_reachable → SKIP
if L2 == BUILD_GENERATED && L3 == not_reachable → SKIP
else → KEEP（交给下游 ownership 分析）
```

### 8. FFIAuditor 统一值追踪框架（opcode 粗筛 + def-use 精筛）

#### 背景：不透明指针时代的挑战

LLVM 15+ 把所有指针统一成 `ptr`，`LLVMGetTypeKind()` 只能返回 `LLVMPointerTypeKind`，无法区分函数指针 vs 数据指针。当前各 Rule 各自实现 opcode + 类型检查，重复代码多，且在不透明指针下精度下降。

**核心策略：用行为推断替代类型查询。** 不问"这个指针是什么类型"，而问"这个值被怎么使用"。

#### 8.1 统一值追踪 API

在 `rust_ffi_auditor.zig` 中新增工具层：

```zig
/// 值来源（替代类型查询）
const ValueSource = enum {
    from_parameter,      // 函数参数
    from_alloca,         // 栈分配
    from_call,           // 函数返回值
    from_global,         // 全局变量
    from_constant,       // 常量/全局地址
    from_code_section,   // .text 段地址（函数指针）
    unknown,
};

/// 值用途（行为推断）
const ValueUsage = enum {
    as_call_target,      // 被用作间接调用目标 → 是函数指针
    as_store_dest,       // 被用作 store 目标 → 是可写指针
    as_load_src,         // 被用作 load 来源 → 是可读指针
    as_gep_base,         // 被用作 GEP 基址 → 是聚合类型
    as_arg_to_ffi,       // 被传给 FFI 函数 → 跨边界
    as_free_arg,         // 被传给 free/dealloc → 是堆指针
};
```

#### 8.2 具体任务

- [x] **T1: 实现 `traceValueSource()`** — 统一的值来源追踪 ✅ (2026-05-24)
  - 替代 `isDerivedFromAlloca()`、`isValueFromParameter()`、`ptrOriginatesFromRustAlloc()` 等分散实现
  - 追踪 def-use chain：alloca → store → load → bitcast → GEP → 最终值
  - 追踪 alloca 内容来源（当前最大缺陷：只看 alloca 本身，不看里面存了什么）
  - 返回 `ValueSource` 枚举
  - 位置：`rust_ffi_auditor.zig` 约 80 行（含 traceAllocaContent + isCodeSectionGlobal）

- [x] **T2: 实现 `traceValueUsage()`** — 统一的值用途推断 ✅ (2026-05-24)
  - 替代 `isGlobalUsedForIndirectCall()`、`mayRetainPointer()` 等分散实现
  - 扫描值的所有 use-site，收集用途集合
  - 返回 `UsageSet`（固定 6 槽位 + contains 方法）
  - 位置：`rust_ffi_auditor.zig` 约 70 行

- [x] **T3: 增强 Rule 5 stack_escape — 追踪 alloca 内容** ✅ (2026-05-24)
  - 用 `traceValueSource()` 替代 `isDerivedFromAlloca()`
  - `from_code_section` / `from_constant` → 抑制（非真正栈逃逸）
  - `from_parameter` / `from_alloca` → 保留报告

- [x] **T4: 增强 Rule 8 callback — 扩展函数指针识别** ✅ (2026-05-24)
  - Mode A (原有): store @global + indirect call 验证
  - Mode B (新增): store alloca + traceValueUsage 包含 as_call_target

- [x] **T5: 增强 Rule 9 write_imm — 不透明指针下的 struct 推断** ✅ (2026-05-24)
  - GEP 基址用 `traceValueSource` 推断 (from_call/global/alloca)
  - `hasStructDebugMetadata()` 调试元数据辅助确认

- [x] **T6: 增强 Rule 10 UAF — 全局变量别名追踪** ✅ (2026-05-24)
  - Pass 1.5: 检测 freed ptr → store @global（poisoned global）
  - Pass 2 Mode 2: load @global after poison → UAF
  - Pass 2 Mode 3: use of loaded value from poisoned global → UAF

#### 8.3 集成方式

不新增文件，不新增 pass。所有增强在 `rust_ffi_auditor.zig` 内完成：

```
当前结构：
  detectStackEscapeToFFI()    → 自己实现 isDerivedFromAlloca()
  detectCallbackOwnershipRisk() → 自己实现 isValueFromParameter() + isGlobalUsedForIndirectCall()
  detectWriteToImmutable()     → 自己实现 struct GEP 检测
  detectUseAfterFree()         → 自己实现 freed ptr 追踪

增强后结构：
  traceValueSource()  ← 统一实现，各 Rule 调用
  traceValueUsage()   ← 统一实现，各 Rule 调用
  detectStackEscapeToFFI()    → 调用 traceValueSource() 判断 alloca 内容
  detectCallbackOwnershipRisk() → 调用 traceValueSource() + traceValueUsage()
  detectWriteToImmutable()     → 调用 traceValueSource() 判断 GEP 基址
  detectUseAfterFree()         → 调用 traceValueSource() 追踪全局别名
```

#### 8.4 优先级与预期收益

| 任务 | 优先级 | 预期收益 |
|------|--------|---------|
| T1 traceValueSource | P0 | 基础设施，T3/T4/T5/T6 依赖它 |
| T3 stack_escape 增强 | P0 | 消除 wasmtime 剩余误报 |
| T2 traceValueUsage | P1 | T4/T5 依赖它 |
| T8 callback 扩展 | P1 | 检测局部回调变量 |
| T5 write_imm 增强 | P2 | 不透明指针下精度提升 |
| T6 UAF 全局别名 | P2 | GO-03 检出 |

---

### 9. OriginClassifierPass — 独立组件

improve.md 里提到的"第一公民组件"这个判断非常对。

当前 `noise_filter.zig` 的问题是定位对了（Layer 1 noise reduction）但实现错了（名字匹配）。它的架构太浅：

```
// 现在
noise_filter.zig → 名字匹配 → bool

// 应该
OriginClassifierPass → [Linkage, DebugOrigin, CallGraph] → FunctionOrigin
```

**位置**：pipeline 中 zone_classifier 之后、所有 analysis pass 之前。

```
pipeline 执行顺序（建议）:
  1. LanguageDetector
  2. ZoneClassifier
  3. OriginClassifierPass    ← 新增
  4. MemoryGraph / DangerSurface / PointerOwnership / CrossLangEdge 等
```

**为什么放在 zone_classifier 之后**：zone_classifier 只需要函数名，不需要 instruction-level 分析，是最快的 gate。先过 zone 砍掉 safe 函数，再跑 OriginClassifier 砍掉 compiler noise。

**产出**：`PassContext.function_origin: std.AutoHashMap(u32, FunctionOrigin)`，所有下游 pass 共享。

```
pub const FunctionOrigin = enum {
    user,        // 用户代码 — 高优先级分析
    dependency,  // 依赖 crate — 分析但降低优先级
    stdlib,      // 标准库 — 跳过
    generated,   // 编译器生成（drop glue, panic 等）— 跳过
    runtime,     // 运行时内部 — 跳过
    unknown,     // 无法判断 — 保留分析（安全第一）
};
```

---

## 性能数据参考

| 文件 | init (ms) | detect (ms) | analysis (ms) | total (ms) |
|------|-----------|-------------|---------------|------------|
| wasmtime_test.bc | 17067 | 7441 | 11831 | 53407 |
| sqlite3.bc | 5942 | 3503 | 4647 | 20033 |

---

## 验收清单

- [x] File is under 1000 lines
- [x] Code is simple and straightforward
- [x] All comments are in English
- [x] Code-to-comment ratio is approximately 7:3
- [x] Tests include boundary cases
- [x] No files were deleted without permission
- [x] Naming conventions are followed
- [x] Code is formatted with `zig fmt`
- [x] All tests pass
- [x] Public APIs have doc comments
- [x] Error handling is appropriate
- [x] Memory management is correct
- [x] Changes are surgical and minimal