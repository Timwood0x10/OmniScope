# OmniScope 优化方案

编码风格：./plan/rules/rules.md 

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

---

## 待做优化方案

### 3. isOnDangerPathFull 全局缓存（影响多 pass）

PassContext.isOnDangerPathFull() (pass.zig:898) 不只被 DangerSurfacePass 调用。可以把 ffi_set 缓存到 PassContext 中，首次构建后复用，避免每次重建。

### 4. PointerOwnership init 阶段性能分析（~17s）

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
| isFreeInstruction/classifyFree 每个 call 做 3 次 LLVM C API | 预构建 free 函数名 HashMap，O(1) 查询 |

### 5. PointerOwnership analysis 阶段性能分析（~12s）

C1 优化已合并为单次遍历，但仍然对每个函数 × BB × 指令做：
- `analyzeInstructionForOwnership()`: 分配/释放分类
- 所有权流图构建（`addFlowEdge`）
- `null_check_recognizer.recognizeInFunction()`
- `detectStructMemberStores()`
- RAII 检测 / drop 检测

问题: 这些操作对 Rust 编译器生成函数（Vec 迭代器、drop glue、闭包等）都是白费的。

### 6. Rust 编译器生成代码的通用过滤方案

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
3. **不误杀 FFI producer crate** — `Box::into_raw`、`extern "C" fn create_ctx` 这些无 extern call 但参与所有权传播的必须保留
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

##### Layer 1 — Linkage Heuristic（最便宜，最先跑）

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

##### Layer 2 — Debug Origin（IR metadata 路径分析）

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

##### Layer 3 — CallGraph Reachability（语义最强，最后跑）

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

### 7. OriginClassifierPass — 独立组件

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

| 文件 | 大小 | init (ms) | detect (ms) | analysis (ms) | total (ms) |
|------|------|-----------|-------------|---------------|-----------|
| wasmtime_test.bc | 17MB | 17067 | 7441 | 11831 | 53407 |
| sqlite3.bc | 43MB | 5942 | 3503 | 4647 | 20033 |
