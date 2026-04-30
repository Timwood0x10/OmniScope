# OmniScope v0.1.9 Development Plan — Accuracy Overhaul

> **Version**: v0.1.9 (Accuracy Overhaul)
> **Goal**: borrow\_escape 误报从 \~600 降到 <100，整体准确率从 41% 提升到 65%+
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake\_case, <1000 lines/file, English comments)

***

## 审计报告关键数据 (V0.1.9\_FFI\_AUDIT\_REPORT.md)

| 指标             | v0.1.8  | v0.1.9      | 目标   |
| -------------- | ------- | ----------- | ---- |
| 总 Issues       | 4,441   | 1,320       | <500 |
| borrow\_escape | \~1,570 | \~712 (54%) | <100 |
| 整体准确率          | 27-36%  | 41%         | 65%+ |
| C 项目准确率        | 27-36%  | 30-40%      | 60%+ |
| Rust 项目准确率     | 95%     | 96%         | 90%+ |

***

## P0 — borrow\_escape 精准化 (Critical)

### P0-A: MemoryGraph 三层信号 ✅

**Status**: ✅ **DONE**

三层信号，全部项目无关，不需要任何白名单：

| 层                     | 信号                | 机制                                         | 覆盖场景                                    |
| --------------------- | ----------------- | ------------------------------------------ | --------------------------------------- |
| **L1: SourceKind**    | 返回值直接来源           | `trackAlloc(kind)` 标注 alloca/heap/resource | `malloc()` 返回值直接是 heap                  |
| **L2: ContentSource** | 存储位置的内容来源         | `store` 记录内容，`load` 继承内容                   | `%alloca 里存了 %malloc 的结果，load 出来是 heap` |
| **L3: FuncCounter**   | 函数级 alloc/free 平衡 | `recordFuncAlloc/Free` 计数                  | `net > 0` = 工厂函数，不太可能返回栈地址              |

**实现**:

- [x] `AllocNode` 添加 `source_kind: SourceKind` ✅
- [x] `MemoryGraph` 添加 `func_counters` 和 `content_sources` HashMap ✅
- [x] `trackAlloc` 接受 `SourceKind` 参数 ✅
- [x] `recordFuncAlloc/Free` per-function 计数 ✅
- [x] `recordContentSource/getContentSource` 内容来源追踪 ✅
- [x] `resolveSourceKind` 综合查询 ✅
- [x] 修复 store 传播语义：store 不覆盖 dest 来源，记录 content\_source ✅
- [x] 修复 load 传播语义：load 继承被加载指针的内容来源 ✅
- [x] `checkReturnViolation` 整合三层信号 ✅
- [x] `FuncCounter.net()` 使用 i64 防溢出 ✅
- [x] 测试: 9 个单元测试 (含 func\_counter + content\_source) ✅

**判断流程 (checkReturnViolation)**:

```
1. OutputParamClassifier → 已知输出参数 API → 跳过
2. isNonPointerReturnType → 返回非指针 → 跳过
3. MemoryGraph.getSourceKind(retval) == heap/resource → 跳过 (L1)
4. MemoryGraph.getFuncCounter(func).net() > 0 → 跳过 (L3)
5. retval 是 call 结果 + callee 是已知分配器 → 跳过
6. pointer_map(retval).is_param_storage → 跳过 (P0-B)
7. isAllocaReturnSuppressed → 构造器模式 → 跳过
8. pointer_map(retval).alloc_site == .stack → 报告 borrow_escape
```

### P0-B: Alloca 用途分类 ✅

**Status**: ✅ **DONE**

- [x] `PtrInfo` 添加 `is_param_storage: bool` 字段 ✅
- [x] `isFuncParam()` 辅助函数 — 检查 value 是否是函数参数 ✅
- [x] Store 处理中：如果 value 是函数参数且 dest 是 alloca，标记 `is_param_storage` ✅
- [x] `checkReturnViolation` 中跳过 `is_param_storage` alloca ✅

**预期效果**: 参数存储 alloca (\~60% 的 borrow\_escape FP) → 0

### P0-C: AllocatorKB 扩展 ✅

**Status**: ✅ **DONE**

- [x] SQLite: sqlite3\_malloc/malloc64/realloc/realloc64/mprintf/vmprintf/snprintf/StrAccumFinish/DbMallocRaw/DbMallocRawNN/DbMalloc ✅
- [x] curl: curl\_easy\_init/dupset, curl\_multi\_init, curl\_slist\_append, curl\_mime\_init, curl\_formadd, curl\_url\_set, curl\_ws\_recv/send ✅
- [x] OpenSSL: OPENSSL\_malloc/zalloc, CRYPTO\_malloc/free, BN/EVP\_PKEY/X509/RSA/EC\_KEY new/free ✅
- [x] libxml2: xmlMalloc/Strdup, xmlNewDoc/Node, xmlParseFile ✅
- [x] PCRE2: pcre2\_compile, pcre2\_match\_data\_create/free ✅
- [x] zlib: deflateInit/End, inflateInit/End, compress/uncompress ✅

### P0-D: 安全函数白名单扩展

**Status**: DEFERRED — P0-A/B/C 的项目无关信号已足够覆盖大部分场景

***

## P1 — Memory Graph 增强

### P1-1: 返回值来源标注 ✅ (merged into P0-A)

### P1-2: 单次扫描跨函数内存追踪

**目标**: 一次扫描同时建立调用图和内存关系图，解决 "X malloc vs Y free" 误报

**Status**: IN PROGRESS

**设计**:

```
┌─────────────────────────────────────────────────────────┐
│ 单次扫描                                                │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐       │
│  │ CallGraph │    │ AllocMap │    │ FreeMap  │       │
│  │ A→malloc │    │ malloc→p1│    │ free(p1) │       │
│  └──────────┘    └──────────┘    └──────────┘       │
└─────────────────────────────────────────────────────────┘
```

**实现**:

- [x] 设计: `CallGraph` + `MemoryRelations` 结构
- [ ] `src/semantics/memory_relations.zig` — 新文件
  - `CallGraph`: func → calls[] 映射
  - `MemoryRelations`: ptr_value → PointerOrigin 映射
  - `func_allocs` / `func_frees`: 函数级 alloc/free 计数
- [ ] `PtrInfo` 添加 `origin_func: ?[]const u8` 字段
- [ ] 单次扫描构建所有数据结构
- [ ] 跨函数 `isValidFree` 检查

**效果**: 解决 `process_with_cleanup` "0 malloc vs 2 free" 误报

### P1-3: Alloca 用途分析 ✅ (merged into P0-B)

***

## P2 — 剩余工作

<br />

### P2-2: 引用计数模式识别

**目标**: 减少 double\_free 误报 (sqlite3 BtreePage 引用计数)

- [ ] 检测 `if (refcount <= 0) free()` 模式
- [ ] 在 `checkDoubleFreeViolation` 中抑制引用计数保护下的 free

### P2-3: Abort trap 稳定性修复

**问题**: 4 个大型文件触发 Abort trap:6

- [ ] 添加 `--max-memory` 和 `--timeout` 选项
- [ ] 大型模块 graceful degradation

### P2-4: ip\_ffi.zig 跨函数 NULL check 追踪

- [ ] 已有空文件 `src/pass/analysis/ip_ffi.zig`
- [ ] 实现 `FFICallSite` struct
- [ ] 实现 `analyzeCallerContext(func) []FFICallSite`

***

## Code Review 修复记录

| Date       | Finding                               | Fix                                      |
| ---------- | ------------------------------------- | ---------------------------------------- |
| 2026-04-30 | memory\_graph overflow panic          | `*%` wrapping multiply                   |
| 2026-04-30 | memory\_graph leak via ArenaAllocator | direct allocator + manual deinit         |
| 2026-04-30 | per-function MemoryGraph overhead     | global per-module singleton              |
| 2026-04-30 | RETURN-STACK 误报 (24+ warnings)        | `isAllocaReturnSuppressed()`             |
| 2026-04-30 | main.zig silent makePath failure      | error logging                            |
| 2026-04-30 | graph\_visualizer O(n²) bubble sort   | `std.sort.block`                         |
| 2026-04-30 | graph\_visualizer 10MB hard limit     | 100MB + error log                        |
| 2026-04-30 | 8 missing IssueKind mappings          | full coverage + colors                   |
| 2026-04-30 | version 0.1.5 → 0.1.6                 | unified                                  |
| 2026-04-30 | graph\_visualizer use-after-free      | deep copy issues slice                   |
| 2026-04-30 | graph\_visualizer silent OOM          | `return error.OutOfMemory`               |
| 2026-04-30 | ffi\_safety\_checker `const` → `var`  | num\_uses fix                            |
| 2026-04-30 | isStaticBufferFunction substring FP   | exact match + underscore prefix          |
| 2026-04-30 | XSS in HTML generation                | `<`/`>`/`&` → `\u003c`/`\u003e`/`\u0026` |
| 2026-04-30 | static\_lifetime knowledge lost       | migrated to AllocatorKB                  |
| 2026-04-30 | resolveSourceKind comment misleading  | clarified priority semantics             |
| 2026-04-30 | FuncCounter.net() i32 overflow risk   | → i64                                    |
| 2026-04-30 | Issue.deinit double-free (Invalid free) | `function_owned` guard, don't free borrowed ptr |
| 2026-04-30 | hasAllocInCalleeChain DFS broken       | `AutoHashMap(void,void)` → `AutoHashMap(u64,void)` |
| 2026-04-30 | trackAlloc partial failure leak       | 3-layer errdefer chain                   |
| 2026-04-30 | FuzzyMatcher.toLower() no-op           | `endsWithLower`/`indexOfLower` zero-alloc impl |
| 2026-04-30 | memory\_safety.zig double module scan  | removed first pass, single-scan now      |
| 2026-04-30 | graph.zig clear() double-free message | removed redundant `free()` before `deinit` |
| 2026-04-30 | graph.zig getIssuesBySeverity trace sharing + missing fields | `trace=null`, added `reason`/`function_owned` |
| 2026-04-30 | cpp\_fp\_reduction.zig RESOURCE LEAK msg leak | manual free after `Issue.init` (owned=false) |
| 2026-04-30 | ptr\_lifetime.zig defer free without needs_free check | added `if (needs_free)` guard |
| 2026-04-30 | free\_validation.zig 176 Invalid free FP (wasmtime) | `isRustDeallocFunction()` — skip `from_param` + `__rustc__rustc_dealloc` |
| 2026-04-30 | memory\_safety.zig 172 Double free FP (wasmtime) | `isRustPanicOrCleanupFunction()` — suppress double free in panic/cleanup/drop paths |
| 2026-04-30 | isRustPanicOrCleanupFunction 匹配过宽 | 加 `_ZN`/`_R` Rust mangled 前缀守卫，避免抑制 C 函数 |

***

## P-DEGRADE — 错误降级 (Error Degradation)

> **设计约束**: 单个函数/单个 pass 失败不得终止整体分析
> - 编码风格严格遵循 `plan/rules/rules.md`

### 现状

| 层级 | 位置 | 当前行为 | 问题 |
|------|------|----------|------|
| Pass 级 | `pass/manager.zig:198` | `try self.passes.items[idx].run_fn(ctx, diag)` | 一个 pass 崩溃 = 整个分析终止 |
| 函数级 | 所有 pass 的 `analyzeFunction` | `try analyzeFunction(ctx, func, ...)` | 一个函数崩溃 = 整个 pass 终止 |
| 指令级 | `ffi_boundary.zig` 辅助检查 | `validateAPIContract(...) catch {}` | 已有部分降级，但不完整 |

### P-DEGRADE-1: PassManager pass 级降级

**修改文件**: `src/pass/manager.zig`

- [ ] `run()` 中每个 pass 的 `run_fn` 用 `catch` 包裹
- [ ] 降级时输出 warn 日志：pass 名称 + 错误信息
- [ ] 继续执行后续 pass
- [ ] **验证**: 人为在一个 pass 中触发错误，确认后续 pass 仍正常执行

### P-DEGRADE-2: 所有 pass 的函数级降级

**修改文件**: 所有包含 `analyzeFunction` 的 pass（共 15 个文件）

需要改动的文件列表：
- [ ] `src/pass/analysis/ptr_lifetime.zig` (L476, L512)
- [ ] `src/pass/analysis/ffi_boundary.zig` (L225)
- [ ] `src/pass/analysis/callback_escape.zig` (L337)
- [ ] `src/pass/analysis/abi_mismatch.zig` (L197)
- [ ] `src/pass/analysis/thread_crossing.zig` (L194)
- [ ] `src/pass/analysis/pointer_ownership.zig` (L244)
- [ ] `src/pass/analysis/issue/return_check.zig` (L67)
- [ ] `src/pass/analysis/issue/malloc_check.zig` (L53)
- [ ] `src/pass/analysis/issue/free_validation.zig` (L63)
- [ ] `src/pass/analysis/issue/ffi_body_check.zig` (L524)
- [ ] `src/pass/analysis/issue/integer_overflow.zig` (L32)
- [ ] `src/pass/analysis/issue/memory_safety.zig` (L50, L66)
- [ ] `src/pass/foundation/dfg.zig` (L81)
- [ ] `src/pass/foundation/cfg.zig` (L81)
- [ ] `src/pass/analysis/taint.zig` (L101)

改动模式（统一）：
```zig
// Before:
try analyzeFunction(ctx, func, diag);

// After:
analyzeFunction(ctx, func, diag) catch |err| {
    diag.warn("Pass '{s}': skipped function due to error: {}", .{pass_name, err});
    continue;
};
```

- [ ] 降级时输出 warn 日志：pass 名称 + 函数名 + 错误信息
- [ ] 继续分析后续函数
- [ ] **验证**: 用 wasmtime_test (已知会 Abort trap) 测试，确认不崩溃且其他函数正常分析

### P-DEGRADE-3: 降级统计

**修改文件**: `src/pass/pass.zig`

- [ ] 在 `PassContext` 中新增 `degraded_functions: u32` 计数器
- [ ] 每次函数级降级时 +1
- [ ] 在分析结束时输出统计：`"X functions skipped due to errors"`
- [ ] **验证**: `zig build test` 通过

***

## 预期效果

做完 P0-A/B/C 后：

| 指标             | Before | After (Expected) |
| -------------- | ------ | ---------------- |
| borrow\_escape | 712    | \~50-70 (减少 90%) |
| 整体 Issues      | 1320   | \~680 (减少 48%)   |
| 整体准确率          | 41%    | \~65%            |

**关键**: 所有信号都是项目无关的——不需要知道项目名，不需要白名单，对任何 C/C++ 项目都有效。

***

***

# OmniScope v0.2.0 — FFI/Unsafe 边界安全审计修复计划

> **基于**: V0.2.0\_FFI\_AUDIT\_REPORT.md
> **日期**: 2026-04-30
> **目标**: 加权平均准确率从 \~35% 提升到 \~55-60%

## v0.2.0 审计关键数据

| 指标             | v0.1.9 | v0.2.0        | 修复目标      |
| -------------- | ------ | ------------- | --------- |
| 总 Issues       | 1,320  | 903           | \~500-600 |
| borrow\_escape | \~712  | \~215 (23.8%) | <100      |
| double\_free   | \~100  | \~361 (40.0%) | \~150     |
| 加权平均准确率        | 41%    | \~35%         | 55-60%    |
| C 项目准确率        | 30-40% | 27-33%        | 55-65%    |
| Rust 项目准确率     | 96%    | \~80%         | 85%+      |
| Abort trap 崩溃  | -      | 4 次           | 0-1 次     |

## v0.2.0 核心问题

1. **borrow\_escape 误报仍然严重** — C 项目的 C API 模式未完全识别
2. **double\_free 激增** — 从 v0.1.9 的 \~100 增至 361，SQLite 引用计数被误判
3. **4 次 Abort trap** — 大型模块稳定性问题 (wasmtime\_test, rust\_sqlite, jsoncpp195, blst)

## 根因分析

### borrow\_escape 误报根因

审计案例 `sqlite3_malloc` 误报：

```llvm
%ptr = alloca i64        ; ← OmniScope 误判为"返回栈地址"
%call = call ptr @malloc ; ← 实际是堆分配
ret ptr %call            ; ← 返回堆指针，合法
```

**现有防护链**（8 层）仍有漏洞：

- `OutputParamClassifier` 仅覆盖 \~30 个已知前缀，`sqlite3_malloc` 不在其中
- `MemoryGraph.getSourceKind()` 对 call 结果的追踪可能失效（`propagateOrigin` 未正确传播 heap 属性）
- `isAllocaReturnSuppressed()` 仅覆盖 sqlite3 特定子串，不够通用

### double\_free 误报根因

- `detectRefCountedContainerFunctions` 的 RC 模式列表是 abseil 专用（`CordRep3Ref` 等），不覆盖 SQLite 的 `sqlite3ValueRef`/`sqlite3ValueFree`
- SQLite 引用计数模式（`sqlite3ValueNew` → `sqlite3ValueFree`）未被识别

### Abort trap 根因

- IR 遍历虽为迭代式，但 LLVM C API 调用遇到异常 IR pattern 时可能触发 SIGABRT
- 缺少 LLVMValueRef 空指针检查和函数大小保护

***

## P0 — 修复 borrow\_escape 误报（预计减少 50%+ 误报）

**修改文件**: `src/pass/analysis/ptr_lifetime.zig`, `src/semantics/output_param_classifier.zig`

### P0-1: trackInstruction 中 call 指令的 heap 标记强化

- [ ] 在 `trackInstruction` 中，当 call 指令调用已知堆分配函数时，**立即**将 call 结果标记为 `alloc_site = .heap`（不依赖 propagateOrigin）
- [ ] 覆盖 `HEAP_ALLOC_FUNCTIONS` + `AllocatorKB.isAllocator()` + `SemanticRegistry` 三重来源
- [ ] 目的：修复 sqlite3\_malloc 类 "call 结果被误标为 stack" 的根因

### P0-2: isAllocaReturnSuppressed 扩展

- [ ] 增加 `factory_substrings`: `"Malloc"`, `"Alloc"`, `"Realloc"`, `"Hash"`, `"List"`, `"Table"`, `"Cache"`, `"Pool"`
- [ ] 增加 `factory_prefixes`: `"sqlite3"`, `"curl_"`, `"uv_"`, `"json_"`, `"xml"`, `"ldap_"`, `"avcodec_"`, `"avformat_"`
- [ ] 目的：更通用的构造器/工厂函数识别

### P0-3: checkReturnViolation 新增 call-callee 直接检查

- [ ] 在查 pointer\_map 之前，新增一层：如果 retval 是 call/invoke 指令，且 callee 是已知分配函数，直接跳过
- [ ] 目的：兜底防护，即使 pointer\_map 和 MemoryGraph 都失效也能正确处理

### P0-4: OutputParamClassifier 扩展

- [ ] `known_output_param_families` 增加: `sqlite3_status`, `sqlite3_busy`, `sqlite3_errcode`, `curl_easy_setopt`, `curl_easy_getinfo`, `uv_*`, `json_object_get`, `xmlGetProp`
- [ ] `strong_patterns` 增加: `sqlite3_column`, `sqlite3_bind`, `uv_req_`, `json_array_get`
- [ ] 目的：减少已知 C API 误报

***

## P1 — 修复 double\_free 误报（预计减少 30%+ 误报）

**修改文件**: `src/pass/analysis/cpp_fp_reduction.zig`

### P1-1: SQLite 引用计数模式识别

- [ ] `isRefCountOperation` 增加 SQLite 模式: `sqlite3ValueRef`, `sqlite3ValueFree`, `sqlite3ValueSetNull`, `sqlite3ValueNew`
- [ ] `isKnownRcContainerFunction` 增加 SQLite 类名: `sqlite3_value`, `sqlite3_str`, `Vdbe`, `Btree`, `BtCursor`, `Pgno`
- [ ] 目的：过滤 SQLite 引用计数 double\_free 误报

### P1-2: 通用引用计数函数级检测

- [ ] 在 `detectRefCountedContainerFunctions` 中增加**函数级 RC 检测**：如果函数体内同时出现 `*Ref*`/`*retain*` 和 `*Free*`/`*Release*`/`*Unref*` 操作，标记为 RC 函数
- [ ] 目的：不依赖项目特定名称，通用识别引用计数模式

### P1-3: double\_free 置信度调优

- [ ] 同一 BB 内 free 次数 = 2 时，增加额外检查：两次 free 之间是否有条件分支（if/switch）
- [ ] 如果两次 free 在不同条件分支中（即使同一 BB），降低置信度或跳过
- [ ] 目的：减少 "error path + normal path 都 free" 的误报

***

## P2 — 修复稳定性问题（4 次 Abort trap）

**修改文件**: `src/pass/analysis/ptr_lifetime.zig`, `src/main.zig`

### P2-1: LLVMValueRef 空指针防护

- [ ] 在 `trackInstruction` 和 `checkViolations` 中，所有 `LLVMGetOperand`, `LLVMGetBasicBlockParent`, `LLVMGetCalledValue`, `LLVMGetValueName` 调用前添加 `@intFromPtr(val) != 0` 检查
- [ ] 目的：防止空指针解引用导致 SIGABRT

### P2-2: 函数大小保护

- [ ] 在 `analyzeFunction` 入口添加：如果基本块数 > 1000 或指令数 > 50000，跳过该函数并输出 debug 日志
- [ ] 目的：防止超大函数触发异常

### P2-3: 单函数错误隔离

- [ ] 在 `analyzeFunction` 调用处添加 `catch`，单个函数分析失败不影响整体
- [ ] 在 main.zig 中为每个 pass 的 `run` 添加错误恢复
- [ ] 目的：错误隔离，提高整体稳定性

***

## P3 — format\_string 误报修复

**修改文件**: `src/pass/analysis/ffi_boundary.zig`

### P3-1: 常量 format 字符串识别

- [ ] 在 format\_string 检测中，如果 format 字符串参数是全局常量（`LLVMGlobalVariable`），检查其初始化值
- [ ] 如果不包含 `%s`/`%n`/`%x`/`%$` 等用户可控格式符，抑制报告
- [ ] 目的：修复 curl altsvc\_out 类误报（`curl_mfprintf` + 硬编码常量）

### P3-2: 安全 printf 封装识别

- [ ] 维护安全 printf 封装列表: `curl_mfprintf`, `curl_msprintf`, `curl_mprintf`, `snprintf`, `vsnprintf`
- [ ] 调用这些函数时不报告 format\_string
- [ ] 目的：减少对安全封装函数的误报

***

## P-INFRA — MemoryRelations 单次扫描重写 (Infrastructure)

> **设计约束**:
> - 单次 LLVM 模块遍历，同时构建内存图 + 调用图
> - 跨函数分析 = 查询已构建的 HashMap，不回扫 IR
> - sqlite3 (3346 函数) 必须在 MS 级完成
> - **deinit 必须完整，零泄漏**
> - 编码风格严格遵循 `plan/rules/rules.md`

**修改文件**: `src/semantics/memory_relations.zig`, `src/pass/analysis/issue/memory_safety.zig`

### P-INFRA-1: MemoryRelations 数据结构重写

- [ ] 所有函数标识从 `[]const u8` 改为 `u64`（`@intFromPtr(func)`）
- [ ] `call_graph`: `StringHashMap(ArrayList([]const u8))` → `AutoHashMap(u64, ArrayList(u64))`
- [ ] `func_allocs`: `StringHashMap(u32)` → `AutoHashMap(u64, u32)`
- [ ] `func_frees`: `StringHashMap(u32)` → `AutoHashMap(u64, u32)`
- [ ] `ptr_to_func`: `AutoHashMap(u64, []const u8)` → `AutoHashMap(u64, u64)`
- [ ] `origins`: `AutoHashMap(u64, PointerOrigin)` → `AutoHashMap(u64, u64)` (存 alloc_func_ptr)
- [ ] 新增 `free_calls: ArrayList(FreeCallRecord)` — 扫描时收集 free 调用，事后验证
- [ ] 新增 `func_names: AutoHashMap(u64, []const u8)` — 零拷贝函数名缓存（仅用于报告输出）
- [ ] **deinit**: 所有 AutoHashMap(u64, ...) 只需 `.deinit()`，无需遍历释放 key
- [ ] **deinit**: `free_calls.deinit()` + `func_names.deinit()`（func_names 的 value 是 LLVM 内部指针，不 free）
- [ ] **deinit**: call_graph 的 value (ArrayList(u64)) 需遍历 `.deinit()`
- [ ] **验证**: `zig build` 编译通过 + `zig build test` 全部通过 + GPA leak check = 0

### P-INFRA-2: MemorySafetyPass 单次扫描重写

- [ ] 删除 `func_map: StringHashMap(LLVMValueRef)` — 不再需要
- [ ] 单次 while 循环遍历所有函数，同时构建 MemoryRelations + 收集 free_calls
- [ ] 事后验证阶段：遍历 `free_calls` 列表（几百条），查 HashMap 做跨函数验证
- [ ] **deinit**: `defer relations.deinit()` 确保完整清理
- [ ] **验证**: sqlite3 分析耗时 < 10ms（当前 ~200ms+）

### P-INFRA-3: CrossFunctionAnalyzer 适配

- [ ] `visited_funcs`: `StringHashMap(void)` → `AutoHashMap(u64, void)` — 消除 dupe
- [ ] `hasAllocInCalleeChain`: 参数从 `[]const u8` 改为 `u64`
- [ ] `resolveFreeValidation`: 参数从 `[]const u8` 改为 `u64`
- [ ] **deinit**: `visited_funcs.deinit()` — 无需遍历释放 key
- [ ] **验证**: 递归调用链 DFS 在已构建的 call_graph 上执行，不涉及 IR 遍历

### 编码规则检查清单

- [ ] 文件 < 1000 行
- [ ] 注释全英文，code:comment ≈ 7:3
- [ ] camelCase 函数名，snake_case 变量名，TitleCase 类型名
- [ ] 4 空格缩进
- [ ] 公开 API 有 doc comment
- [ ] 测试覆盖 happy path + boundary + error path
- [ ] `zig fmt` 格式化
- [ ] 不删除文件（rules.md 2.5）

***

## 预期效果

| 指标                      | 当前 (v0.2.0) | 修复后（预估）       |
| ----------------------- | ----------- | ------------- |
| C 项目 borrow\_escape 准确率 | 27-33%      | **55-65%**    |
| double\_free 误报（SQLite） | 225         | **\~80-100**  |
| Abort trap 崩溃           | 4 次         | **0-1 次**     |
| 总 Issues 数              | 903         | **\~500-600** |
| 加权平均准确率                 | \~35%       | **\~55-60%**  |
| MemoryRelations 内存 (sqlite3) | 数十 MB 泄漏 | **< 1MB, 零泄漏** |
| MemorySafetyPass 耗时 (sqlite3) | ~200ms+    | **< 10ms**    |

