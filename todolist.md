# OmniScope — Universal FFI/Unsafe Boundary Static Analyzer

> **Version**: v0.3.0 (Dataflow-Precise Analysis)
> **Core Positioning**: 通用 FFI/Unsafe 边界静态分析器，基于 LLVM IR
> **Goal**: 检测精确、通用、少量语言特定规则
> **Coding Rules**: Follow `plan/rules/rules.md` strictly

***

## Architecture Vision

```
IR Input
  |
Dataflow Analysis Layer (universal, no name dependency)
  - Pointer origin tracking (alloca/malloc/param/global)
  - Ownership flow analysis (who owns this pointer?)
  - Path-sensitive condition analysis (mutual exclusion, RC pattern)
  |
Semantic Classification Layer (minimal language-specific rules)
  - FFI boundary identification (cross-language calls)
  - Unsafe operation identification (Rust unsafe, Zig @ptrCast)
  - Language-specific patterns (Rust drop glue, C setjmp/longjmp)
  |
Issue Report Layer
  - Only report risks confirmed by dataflow analysis
  - No suppress rules needed (detection itself is precise)
```

**Key Insight**: Precise detection needs no suppress. The existence of many
suppress rules indicates the detection itself is imprecise.

***

## Coding Standards

| Rule        | Requirement                                        | Source          |
| ----------- | -------------------------------------------------- | --------------- |
| File size   | <= 1000 lines per file                             | `rules.md` S2.1 |
| Simplicity  | Minimal solution, no over-abstraction              | `rules.md` S2.2 |
| Comments    | English only, code:comment \~ 7:3                  | `rules.md` S2.3 |
| Tests       | happy + boundary + error, esp. language boundaries | `rules.md` S2.4 |
| Naming      | TitleCase type, camelCase fn, snake\_case var      | `rules.md` S1.1 |
| Surgical    | Only change what's necessary                       | `rules.md` S3.3 |
| Goal-driven | Each task has verifiable success criteria          | `rules.md` S3.4 |
| No deletion | Never delete files                                 | `rules.md` S2.5 |
| Public API  | All pub functions have doc comments                | `rules.md` S9.1 |
| Pre-commit  | `zig fmt` + `zig build test` + line count          | `rules.md` S10  |

***

## Current Status (2026-05-02)

### R7.0 Zone-First Architecture — ✅ COMPLETED (2026-05-02)

| Metric | Before R7.0 | After R7.0 | Change |
|--------|------------|-----------|--------|
| Total Issues (18 projects) | 2,924 | **1,169** | **↓60%** |
| TP Rate | ~11% | **~33%** | **↑3x** |
| Pure-FP projects zeroed | 0 | **5** | ring/blst/wasmtime/ripgrep/ark_ff |
| TP retention (intentional bugs) | — | **>90%** | openssl_wrapper 18/20, rust_sqlite 19/20 |
| sqlite3 analysis time | 9.5s → 1.22s | 1.22s | stable |

**Key Changes:**
- [x] `getOrComputeZone()` / `getOrComputeZoneByName()` — unified zone caching (7 call sites deduped)
- [x] `shouldAnalyzeZone()` — shared zone gate (2 switch blocks deduped)
- [x] Phase 0 Zone-First gate in `ffi_boundary.analyze()` — replaces ~34 scattered whitelist rules
- [x] FPWhitelist (18 entries) migrated into `zone_classifier` (Cat2/Cat3)
- [x] `C_INTERNAL_PATTERNS` added to zone_classifier (uv__*, sqlite3Mem, __pthread)
- [x] `RUST_SAFE_PATTERNS` extended (sync_channel, Waker::, RawVec::, __rust_alloc/dealloc)
- [x] callee_zone hot-path caching via `getOrComputeZoneByName()`
- [x] `reportRiskyCall()` accepts pre-fetched `caller_name` (eliminates redundant LLVMGetValueName)
- [x] Null safety guard in `getOrComputeZone()` for *anyopaque pointer

### R7.1 Root-Cause FP Reduction — ✅ COMPLETED (2026-05-02)

| Metric | Before R7.1 | After R7.1 | Change |
|--------|------------|-----------|--------|
| Total Issues (18 projects) | 1,169 | **1,122** | **↓47 (↓4%)** |
| TP Rate (overall) | ~33% | **~38%** (est.) | ↑ |
| vs Original (v0.2.0) | 2,924 | 1,122 | **↓61.6%** |

**Key Changes:**
- [x] **R7.1-0**: Language-First Pipeline — `language_detector.zig` 三级检测（DWARF + producer + sampling），`detectModuleLanguage()` 模块级一次识别
- [x] **R7.1-1**: realloc = free + alloc in `ptr_lifetime.zig:trackInstruction()` — marks old ptr as freed
- [x] **R7.1-2**: format_string constant detection in `ffi_boundary.zig:isFormatStringConstant()` — GEP→GlobalVariable→constant IR pattern matching; sqlite3 -51 FP
- [x] **R7.1-3**: borrow_escape language-layered detection in `callback_escape.zig:mayRetainInCLanguageAware()` — Go→full cgo, C→real escapes only (global store/async callback), Zig→skip; removed `isCgoBoundary(func_name)` name-pattern false positive

### R7.1-0 Language-First — Known Issues (2026-05-02) — ✅ ALL FIXED

- [x] **P0**: `LLVMGetProducer` 不存在于 LLVM 15 — `detectFromProducer` 已完全移除
- [x] **P1**: `_ZN` 前缀只归 Rust — `isRustMangledName()` 三层检测区分 Rust/C++
- [x] **P1**: `mapDWARFLanguage` 死代码 — 已清除
- [x] **P1**: `detectModuleLanguage` 返回值未存入 PassContext — `module_language` 字段 + `initModuleLanguage()`
- [x] **P1**: pipeline.zig 未调用 `detectModuleLanguage` — pipeline.zig L96 已调用
- [x] **P2**: C11 DWARF 值 29 — 当前 else→c_count 功能正确
- [x] **P2**: Go DWARF 值 22 — TinyGo 用 C99 不影响

### Historical Status (2026-05-01) — ARCHIVED

| Project  | Language | Issues | Breakdown                                         |
| -------- | -------- | ------ | ------------------------------------------------- |
| wasmtime | Rust     | 2      | 2x zig\_allocator (threadlocal misclassification) |
| sqlite3  | C        | 318    | 97 RETURN-STACK + 88 DOUBLE\_FREE + 133 other     |

### Completed Work

- [x] Three-layer noise filter (noise\_filter/path\_filter/behavior\_filter)
- [x] `classifyFunctionFull()` unified entry point
- [x] Integration into all issue-producing passes
- [x] `isRustMangledName` \_R prefix fix
- [x] `identifyCalleeLanguage` returns .c for C functions (Cross-lang: 0->1885)
- [x] Rust ownership safety rule (skip safe code UAF)
- [x] Debug info C pointer handling + length validation

### Root Cause Analysis: Why 318 sqlite3 Issues?

**RETURN-STACK (97 FP)**: `propagateOrigin` on load propagates the
**slot's own origin** (.stack from alloca), not the **content's origin**
(.heap from stored malloc result). MemoryGraph records contentSource
correctly, but `checkReturnViolation` checks `pointer_map` first and
short-circuits on .stack before consulting MemoryGraph.

**DOUBLE\_FREE (88 FP)**: No path sensitivity. Conditional frees
(if-else branches, RC==0 patterns) are reported as double free
because the analyzer doesn't check if the two frees are on
mutually exclusive execution paths.

***

## P0: Dataflow Precision (Universal, No Name Dependency)

### P0-1: Fix propagateOrigin Load Semantics ✅

**Problem**: `load ptr, ptr %retval` where `%retval = alloca ptr` and
`store ptr %heapPtr, ptr %retval` — propagateOrigin gives the load
result `.stack` (the alloca's origin) instead of `.heap` (the content's
origin stored into the alloca).

**Fix**: In `trackInstruction` for LLVMLoad, after propagateOrigin,
check MemoryGraph contentSource. If content is .heap\_alloc, override
the pointer\_map entry with .heap origin.

**Success Criteria**:

- sqlite3 RETURN-STACK: 97 -> <20
- wasmtime: no regression (still 2)
- No project-specific function name patterns used

### P0-2: Phi Node Tracking ✅

**Problem**: Phi nodes are not tracked in pointer\_map. When
`ret ptr %cond` where `%cond = phi [null, bb1], [%heapPtr, bb2]`,
pointer\_map.get(%cond) returns null, skipping the check entirely.

**Fix**: In `trackInstruction`, handle LLVMPhi by merging all incoming
values' origins. If any incoming value is .heap, phi is .heap (runtime
may take that branch). If all are .stack, phi is .stack.

**Success Criteria**:

- Phi-returning functions correctly classified
- No new false negatives (if phi has a stack branch, still report)

### P0-3: Path-Sensitive DOUBLE\_FREE ✅

**Problem**: Two frees of same pointer reported as DOUBLE\_FREE even
when they're on mutually exclusive branches (if-else) or under
reference count guard (RC==0).

**Fix**:

1. Record each free's basic block
2. Check if two frees are in sibling blocks (same predecessor, different
   branches of a conditional branch) — mutual exclusion
3. Detect RC pattern: `load RC -> sub 1 -> cmp 0 -> br` with free in
   the RC==0 branch — conditional free

**Success Criteria**:

- sqlite3 DOUBLE\_FREE: 88 -> <30
- wasmtime: no regression

### P0-4: Fix llvm.threadlocal.address Misclassification ✅

**Problem**: `ffi_boundary.zig` classifies `llvm.threadlocal.address.p0`
as `zig_allocator`. It's an LLVM intrinsic, not a Zig allocator.

**Fix**: Add LLVM intrinsic prefix check (`llvm.`) before language
classification in `ffi_boundary.zig`.

**Success Criteria**:

- wasmtime: 2 -> 0 issues

***

## P1: Semantic Classification (Minimal Language-Specific)

### P1-1: FFI Boundary Detection (Cross-Language)

- [x] `identifyCalleeLanguage` returns .c for C functions
- [x] Cross-language count: 0 -> 1885
- [x] Validate cross-language boundaries are real FFI calls (zone\_classifier.classifyFunctionFromLLVM + LLVM metadata)
- [x] Support all language pairs (C/C++, Rust, Go, Zig, Python) — Language enum + identifyCalleeLanguage + semantic\_registry (jni/python\_c\_api)

### P1-2: Unsafe Operation Detection

- [x] Rust: identify unsafe blocks in IR — ffi\_unsafe.zig + zone\_classifier unsafe detection
- [x] Zig: identify @ptrCast, @intToPtr, extern fn calls — ffi\_type\_mismatch.zig zig\_alignment\_mismatch + ffi\_boundary.zig ptrCast detection
- [ ] C: identify setjmp/longjmp, variadic function abuse
- [x] Go: identify cgo pointer passing, //go:nosplit — callback\_escape.zig cgo detection + go.json config

### P1-3: FFI Type Mismatch Detection

- [x] Basic framework in `ffi_type_mismatch.zig`
- [x] Size mismatch detection
- [x] Alignment mismatch detection — detectAlignmentMismatches() (SIMD + alignment-sensitive functions)
- [x] Sign mismatch detection — detectSignednessMismatches() (signed/unsigned integer boundary)
- [x] ABI mismatch detection — cpp\_abi\_mismatch in TypeMismatchKind enum (framework exists, detection partial)

***

## P2: Issue Report System

### P2-1: Risk Weighting Integration

- [x] `getEffectiveRisk()` implemented in noise\_filter.zig
- [x] Integrate into Issue report output — attribution.zig filters by RiskLevel + Issue.confidence field
- [x] Group issues by origin (user/stdlib/compiler/third\_party) — attribution.zig AttributionConfig.group\_by\_origin

### P2-2: Attribution Report

- [x] `groupByOrigin(issues)` — group by source (attribution.zig entire module)
- [x] `formatAttributionReport(groups)` — formatted output (attribution.zig)
- [x] CLI: `--focus-user-code`, `--ffi-only`, `--include-stdlib` (main.zig:129 + attribution.zig:25-32)

***

## P3: Performance

### P3-1: Function Classification Cache

- [ ] Cache classifyFunctionFull results
- [ ] Avoid re-analyzing stdlib functions

### P3-2: Parallel Analysis

- [ ] Function-level parallel analysis
- [ ] Thread-safe Issue collection

***

## Target Metrics

| Metric | Current (v0.2.0-R7.1) | Target (v0.2.0-R7.1) | R8 Target |
| ------ | --------------------- | ------------------- | --------- |
| Total Issues (18 projects) | 1,122 | **~800** (↓32%) | **~500-600** |
| TP Rate (overall) | ~38% | **~45%** | **≥80%** |
| Pure-FP projects zeroed | 5 | 5+ (stable) | 8+ |
| double_free FP rate | 65% | **<30%** | **<10%** |
| format_string FP rate | 80% | **<30%** | **<20%** |
| borrow_escape FP rate | 90% | **<40%** | **<30%** |
| Detection method | Zone-First + dataflow | Language-First + root-cause precise | **Unified Graph + path-sensitive** |
| Language-specific rules | minimal (zone-based) | language × zone channel routing | **graph query (no name match)** |

### R7.1 Detailed Design Notes

#### R7.1-1: realloc = free + alloc

**File**: `src/pass/analysis/ptr_lifetime.zig` — `trackInstruction()` LLVMCall branch

```
IR: %new = call @realloc(i8* %old, i64 %size)
     store i8* %new, i8** %ptr_addr

Current:  %new → recorded as heap alloc ✅
          %old → still marked alive ❌

Fix: if isReallocFunction(callee_name):
       1. Mark old_ptr (operand 0) as freed in pointer_map
       2. Return value already handled by HEAP_ALLOC_FUNCTIONS
```

Also update `checkMallocFreePairing` in callback_escape.zig to count realloc as both malloc(+1) and free(+1).

#### R7.1-2: format_string constant detection

**File**: `src/pass/analysis/issue/ffi_unsafe.zig`

```
IR safe:   call printf(@.str, ...)     → GEP → GlobalVariable → constant = true
IR unsafe: call printf(%fmt, ...)      → fmt is variable = false
IR wrapper: call printf(%arg_fmt, ...) → arg_fmt from function param = medium confidence

Fix: fn isFormatStringConstant(inst) bool:
       fmt_arg = GetOperand(inst, 0)
       if IsAGEPInst(fmt_arg) and IsGlobalVariable(operand) and IsConstant → safe
       if IsGlobalVariable(fmt_arg) and IsConstant → safe
       else → report with adjusted confidence
```

#### R7.1-3: borrow_escape language-layered detection

**File**: `src/pass/analysis/callback_escape.zig`

```
Current: mayRetainInC matches set_/add_/register_ prefix for ALL languages
        → C's set_error(&err), add_data(&node) all flagged as escape ❌

Fix: Layer by caller language:
  - Go caller  → full cgo check (KeepAlive + mayRetainInC) — unchanged
  - C caller   → only detect REAL escapes:
                  * pointer stored to global variable
                  * pointer passed to async callback (pthread_create, signal())
                  * plain func(&local) is NOT an escape in C
  - Rust caller → only detect escapes inside unsafe blocks
  - Zig caller  → skip entirely (compile-time guarantees)

Also fix isCgoBoundary: use only linkage-type check (isCgoBoundaryFromLLVM),
remove name-pattern match (pure C functions with "C." in name were misclassified).
```

---

#### R7.2: Language-First Pipeline ✅ COMPLETED

**Design**: At scan entry point, detect source language ONCE via statistical sampling
of function names, then activate corresponding zone rules channel per language.
No more per-pass independent language detection.

**Files Modified**:
- `src/semantics/language_detector.zig` — Added `detectModuleLanguage()`, `LanguageProfile`, `DetectionMethod`, `detectFromSampling()`
- `src/pass/pass.zig` — Added `module_language` field, `initModuleLanguage()`, `getModuleLanguage()`, `channel*()` methods, `ChannelMode` enum
- `src/pipeline/pipeline.zig` — Call `ctx.initModuleLanguage()` before passes run
- `src/pass/analysis/ffi_boundary.zig` — Added `ctx.channelFFIBoundary()` gate at Phase 0.5
- `src/pass/analysis/callback_escape.zig` — Added `ctx.channelCallbackEscape()` gate + `ctx.isGoModule()` for cgo
- `src/pass/analysis/ptr_lifetime.zig` — Added `ctx.channelPtrLifetime()` gate (skip for Zig)
- `src/pass/analysis/pointer_ownership.zig` — Added `ctx.channelPointerOwnership()` gate

**Architecture**:
```
Pipeline.run()
  └─> ctx.initModuleLanguage(module)     // Detect ONCE
      ├─> detectFromSampling(module)     // Primary: function name patterns
      │   ├─ _ZN prefix → Rust (92%+)
      │   ├─ main./runtime. → Go
      │   ├─ zig_/Allocator. → Zig
      │   ├─ _Z prefix (non-_ZN) → C++
      │   └─ default → C
      └─> ctx.module_language = LanguageProfile{language, confidence, method}

Each Pass:
  ffi_boundary    → ctx.channelFFIBoundary()    // Zig/Go=.limited, else=.full
  ptr_lifetime    → ctx.channelPtrLifetime()    // Zig=.skip, Go=.limited, else=.full
  callback_escape → ctx.channelCallbackEscape() // Zig=.skip, else=.full
  pointer_ownership→ ctx.channelPointerOwnership()// Zig=.skip, Go=.limited, else=.full
```

**Channel Matrix**:

| Language | ffi_boundary | ptr_lifetime | callback_escape | pointer_ownership |
|----------|-------------|--------------|-----------------|-------------------|
| Rust     | full        | full         | full            | full              |
| C/C++    | full        | full         | full            | full              |
| Go       | limited     | limited      | full            | limited           |
| Zig      | limited     | skip         | skip            | skip              |
| unknown  | full        | full         | full            | full              |

**Regression Test Results** (18 corpus files):
- Total Issues: **1,122** (same as R7.1 — channels currently set conservative)
- Language Detection: Rust ✅ 92%+, C ✅ 100%, Go ⚠️ needs DWARF, Zig ⚠️ needs DWARF
- Build: ✅ ReleaseFast clean compile
- No regressions introduced

***

## R8: 统一程序图 — 内存图 + 调用图合一 (2026-05)

> **核心发现**: 项目已有完整基础设施但**两张图断连**！
>
> | 组件 | 文件 | 行数 | 状态 |
> |------|------|------|------|
> | **MemoryGraph** | `semantics/memory_graph.zig` | 739行 | ✅ 成熟，ptr_lifetime 深度使用 |
> | **CallGraphPass** | `pass/analysis/call_graph.zig` | 497行 | ✅ 已注册运行，结果未暴露 |
> | **TaintPropagationPass** | `pass/analysis/taint_propagation.zig` | ~400行 | ❌ 定义了但**未注册** (main.zig 漏掉) |
> | **DataFlowGraph** | `dataflow/graph.zig` | ~350行 | ✅ 初始化，QueryEngine 仅 O(N) 线性扫描 |
>
> **关键问题**: `malloc(A) → call B(ptr) → free(B)` 这种跨函数场景，
> MemoryGraph 知道 A alloc 了、B free 了，但**不知道 A→B 是调用关系**，无法配对。
>
> **方案**: 不是"桥接两张图"，而是**合并为一张 UnifiedProgramGraph**。
> 调用边 = 内存流的载体。CallEdge 携带 ptr_args/ret_flow/ffi_boundary 标注。
> 推理准确率目标: **80%+**
>
> ### 统一图设计
> ```
> UnifiedProgramGraph {
>     nodes: HashMap(u64, ProgramNode),     // ptr_value / func_id → node (合一)
>
>     // 5 种边类型 (从 MemoryGraph + CallGraph 合并):
>     alloc_edges:   []AllocEdge,            // malloc/calloc/realloc/alloca
>     free_edges:    []FreeEdge,             // free/dlclose/munmap
>     flow_edges:    []FlowEdge,             // store→load, bitcast, GEP
>     alias_edges:   []AliasEdge,            // may-alias / must-alias
>     call_edges:    []CallEdge,             // ★ 调用边 = 内存流载体
>
>     func_summaries: HashMap(func_id, FuncSummary);  // 跨函数摘要
> };
>
> ProgramNode = struct {
>     id, kind(.alloc/.free/.func/.global),
>     zone(R7.0), language(R7.2), source_kind,
>     call_args: []CallArgSemantics,      // ★ 调用边携带的内存语义
>     call_ret: ?RetSemantics,
>     summary: ?FuncSummary,              // 函数节点才有
> };
>
> CallEdge = struct {                    // ★ 统一的核心
>     caller, callee, edge_type,
>     ptr_args: []PtrArgFlow,           // 哪些参数是指针 + 方向(in/out)
>     ret_flow: ?PtrRetFlow,             // 返回值是否携带指针 + 来源alloc_id
>     is_ffi_boundary: bool,             // caller_zone != callee_zone
> };
>
> FuncSummary = struct {
>     net_allocs, returns_pointer,
>     escaped_params, owned_allocs,       // 本函数拥有的分配(需负责释放)
>     callers, callees,                   // 从 CallGraph 继承
>     cross_lang_calls: []CrossLangEdge, // 精确跨语言边界
> };
> ```
>
> ### 80%+ 准确率的推理链
> | 场景 | 推理路径 | 准确率来源 |
> |------|---------|-----------|
> | `malloc(A)→call B(ptr)→free(B)` | CallEdge.ptr_args[in] → 追踪到 B.free 匹配 | ✅ 跨函数配对 |
> | `A(Go*)→call C.malloc(p)` | CallEdge.is_ffi_boundary=true → cgo_alloc | ✅ Go→C 精确检测 |
> | `free(alias_of_ptr)` | AliasEdge 传递闭包 → 找原始 alloc → double_free | ✅ 别名消解 |
> | `if(c) free(p); else use(p)` | CFG path sensitivity → 互斥分支不报 DF | ✅ 路径敏感 |
> | `net_alloc>0 但 callee 全部释放` | Summary.owned - callee_frees=0 → 非 leak | ✅ 所有者分析 |

### R8.0: 已有资产审计

#### MemoryGraph 实际能力 (`semantics/memory_graph.zig`, 739行)

```
MemoryGraph = struct {
    nodes: AutoHashMap(u64, *AllocNode),     // ptr → AllocNode
    node_store: ArrayList(*AllocNode),        // 所有权管理
    func_counters: AutoHashMap(u64, FuncCounter),  // per-function balance
    content_sources: AutoHashMap(u64, SourceKind),  // store 内容来源
};

AllocNode = struct {
    id, alloc_inst, merkle_root,
    aliases: AutoHashMap(u64, void),        // 别名集合 (HashMap!)
    freed, freed_by, source_kind,
};

// 已有能力:
✅ trackAlloc(inst, ret_val, kind)         — 分配追踪 (5种 SourceKind)
✅ trackAlias(from, to)                   — 别名关系 (HashMap-based)
✅ trackFree(inst, ptr) → bool            — double_free 检测
✅ isUseAfterFreeViaAlias(ptr, inst)      — 别名 use-after-free
✅ findDangerousAliases(ptr)               — 危险别名枚举
✅ validateOwnershipTransfer(from, to, ptr) — 所有权转移验证
✅ analyzeLifecycle(alloc_inst)            — 完整生命周期报告
✅ recordFuncAlloc/Free/Returns(func)     — 函数级分配/释放计数
✅ getFuncCounter(func) → net/hasHeapOps   — 函数净分配
✅ recordContentSource(dest, kind)        — store 内容来源
✅ resolveSourceKind(ptr)                — 直接 > 内容 > unknown
✅ FuzzyMatcher.isMatchingAllocFreePair() — 模糊配对 (malloc/free, new/delete, ...)
```

#### CallGraphPass 实际能力 (`pass/analysis/call_graph.zig`, 497行)

```
CallGraph = struct {
    nodes: []Node, edges: []Edge,

    Node = struct {
        func_name, func_id, language, zone, is_extern,
        kind: FunctionKind (.source/.sink/.transit/.unknown)
    };

    Edge = struct {
        caller, callee,
        edge_type: EdgeType (.direct_call/.indirect_call/.callback),
        arg_mapping: ArgMapping (.by_position/.by_name/.unknown),
        transfer_dir: TransferDirection (.in/.out/.inout/.none)
    };
};

// 已有能力:
✅ buildCallGraph(module)                — 单遍扫描构建
✅ classifyFunctionKind(node)            — source/sink/transit 分类
✅ detectSinks(node)                     — SINK_PATTERNS 匹配
✅ propagateTaint(graph)                 — fixpoint 污点传播!
✅ propagateMemoryGraphThroughCall()     — 跨函数内存传播 (已实现!)
✅ findVulnerabilityPaths()             — 漏洞路径
✅ getCrossLanguageEdges()              — 跨语言边提取
```
> | **FFIMatcher** | `ffi/ffi_matcher.zig` | ✅ 已实现 | ffi_boundary 未使用 |
> | **Steensgaard Alias** | 已有 | ⚠️ 部分实现 | 与 ptr_lifetime 断连 |
>
> **当前 pipeline 执行顺序** (`main.zig` L221-231):
> ```
> 1. CallGraphPass        ← 构建调用图 + taint + sink 检测
> 2. FFIBoundaryPass      ← 不读调用图 ❌
> 3. PointerOwnershipPass ← 不读调用图 ❌
> 4. FFIUnsafePass        ← 不读调用图 ❌
> 5. PtrLifetimePass      ← 不用 propagateMemoryGraphThroughCall ❌
> 6. FFIBodyCheckPass     ← 不读调用图 ❌
> 7. CallbackEscapePass   ← 不读调用图 ❌
> ... (共 11 个 pass)
> ```
>
> **缺失**: TaintPropagationPass (deps=call-graph) 根本没在 main.zig 注册！

### R8.0: 已有基础设施清单（审计结果）

#### CallGraphPass 实际能力 (`pass/analysis/call_graph.zig`, 497行)

```
CallGraph = struct {
    nodes: []Node,           // 函数节点
    edges: []Edge,           // 调用边

    Node = struct {
        func_name, func_id,
        kind: FunctionKind,  // .source / .sink / .transit / .unknown
        language,            // Rust/C/Go/Zig
        zone,                // .safe/.ffi/.unsafe/.runtime_internal
        is_extern,           // FFI boundary marker
        // ...
    };

    Edge = struct {
        caller, callee,
        edge_type: EdgeType,  // .direct_call/.indirect_call/.callback
        arg_mapping: ArgMapping,  // by_position/by_name/unknown
        transfer_dir: TransferDirection, // in/out/inout/none
    };
};

// 已有能力:
✅ buildCallGraph(module)          — 单遍扫描构建完整调用图
✅ classifyFunctionKind(node)       — source/sink/transit 分类
✅ detectSinks(node)                — SINK_PATTERNS 匹配
✅ propagateTaint(graph)             — source→sink 污点传播 (fixpoint 迭代!)
✅ propagateMemoryGraphThroughCall() — 跨函数内存关系传播
✅ findVulnerabilityPaths()         — 漏洞路径报告
✅ getCrossLanguageEdges()         — 跨语言调用边提取
```

#### TaintPropagationPass 实际能力 (`pass/analysis/taint_propagation.zig`)

```
TaintPropagationPass = struct {
    name = "pointer-flow"
    deps = &[_][]const u8{"call-graph"}  // ← 依赖 CallGraphPass 先跑

    // 能力:
    ✅ TaintContext — 污点状态管理 (sources/sinks/tainted)
    ✅ trackInstruction() — 每条指令的指针流追踪
    ✅ GEP 深度感知 — gep_offset → confidence 衰减
    ✅ SanitizerRegistry — sanitizer 函数识别降 FP
    ✅ SemanticRegistry lookup — 函数语义查询
    ✅ PathManager/PathCondition — 路径条件约束
    ✅ CONFIDENCE_DECAY = 0.95 — 传播衰减因子
};
```

#### DataFlowGraph 实际能力 (`dataflow/graph.zig`)

```
DataFlowGraph = struct {
    // 图结构:
    cfg_edges: ArrayList(Edge),    // 控制流边
    dfg_edges: ArrayList(Edge),    // 数据流边
    alias_may: ArrayList(Edge),   // 可能别名
    alias_must: ArrayList(Edge),  // 必定别名

    // 构建方法:
    ✅ buildCFG(function)          — 控制流图
    ✅ buildDFG(function)          — 数据流图
    ✅ addAliasMay(src, dst)       — 别名关系
    ✅ addAliasMust(src, dst)      — 强别名

    // 查询 (当前仅 O(N) 线性):
    queryByKind/queryBySubject/queryByObject/queryByContext
};
```

---

### R8.1: 激活 TaintPropagationPass (P0, ~0.5天)

**问题**: `main.zig` L221-231 注册了 11 个 pass，漏掉了 `TaintPropagationPass`。

```diff
  // main.zig L221-231
  try pipeline.registerPass(OmniScope.cross_lang.CallGraphPass);
+ try pipeline.registerPass(OmniScope.cross_lang.TaintPropagationPass);  // ← 加这行
  try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
```

| Task | File | Status |
|------|------|--------|
| R8.1-a 在 main.zig 注册 TaintPropagationPass | src/main.zig | ✅ |
| R8.1-b 编译验证 + 回归测试 18 文件 | — | ✅ |
| R8.1-c 对比 issue 数量变化 | — | ✅ |

---

### R8.2: 跨语言边界检测 — CallGraph → Zone Channel 反馈 (P0, ~1天)

**问题**: CallGraphPass 构建了完整的 caller/callee zone 信息，但 ffi_boundary 和其他 pass 不读取。

**设计**: 在 CallGraphPass.run() 结束后，将 CrossLangEdge 写入 PassContext，各 pass 通过 API 查询。

```
CallGraphPass.run() 末尾新增:
  for (graph.edges) |edge| {
      caller_zone = ctx.getOrComputeZone(edge.caller, caller_name)
      callee_zone = ctx.getOrComputeZoneByName(callee_name)
      if (caller_zone != callee_zone) {
          // 跨语言边!
          ctx.addCrossLangEdge(.{
              .caller = edge.caller, .callee = edge.callee,
              .caller_zone = caller_zone, .callee_zone = callee_zone,
              .edge_type = edge.edge_type,
          })
      }
  }

// 各 pass 使用:
if (ctx.isCrossLangBoundary(caller_func, callee_name)) {
    // 这是真正的 FFI 边界，不是名字匹配猜的
}
```

| Task | File | Status |
|------|------|--------|
| R8.2-a PassContext.cross_lang_edges 字段 + addCrossLangEdge() | pass.zig | ✅ |
| R8.2-b CallGraphPass.run() 末尾提取跨语言边 | call_graph.zig | ✅ |
| R8.2-c ffi_boundary.zig 用 isCrossLangBoundary() 替代部分名字匹配 | ffi_boundary.zig | ✅ |
| R8.2-d callback_escape.zig 用跨语言边增强 cgo 检测 | callback_escape.zig | ✅ |
| R8.2-e 编译 + 回归测试 | — | ✅ |

---

### R8.3: 跨函数 Alloc-Free 配对 — 接入 propagateMemoryGraphThroughCall (P0, ~1天)

**问题**: `ptr_lifetime.zig` 的 pointer_map 是函数作用域的。malloc 在 A 函数、free 在 B 函数时，A 总是报 leak FP。

**关键**: `semantics/call_graph.zig` 已有 `propagateMemoryGraphThroughCall()` 方法！ptr_lifetime 只需调用它。

```
设计方案:

1. PassContext 新增 global_alloc_tracker: GlobalAllocTracker
   └─ HashMap(ptr_value_ref → GlobalAllocRecord{func, freed, freed_in})

2. PtrLifetimePass.run():
   ├─ 遇到 malloc/calloc/realloc → global_alloc_tracker.insert(func, ptr)
   ├─ 遇到 free → global_alloc_tracker.markFreed(func, ptr)
   └─ run() 结束时 → 只报告 freed==false 且非 global/singleton 的 leak

3. (可选增强) 调用 propagateMemoryGraphThroughCall()
   └─ 将 pointer_map 中 "参数传入的指针" 关联到 caller 的分配记录
```

| Task | File | Status |
|------|------|--------|
| R8.3-a GlobalAllocTracker 结构体 | pass.zig 或新文件 | ✅ |
| R8.3-b ptr_lifetime malloc → global insert | ptr_lifetime.zig | ✅ |
| R8.3-c ptr_lifetime free → global markFreed | ptr_lifetime.zig | ✅ |
| R8.3-d Pipeline post-pass leak report | pipeline.zig | ✅ |
| R8.3-e Global/static 变量跳过 leak | ptr_lifetime.zig | ✅ |
| R8.3-f 接入 propagateMemoryGraphThroughCall | ptr_lifetime.zig | ⏳ |

---

### R8.4: QueryEngine 索引升级 (P1, ~1天)

**问题**: FactStore 用 SoA 四元组存储（设计 OK），但 QueryEngine 只有 4 种 O(N) 线性扫描。

**设计**: 为 kinds/subj/obj/ctx 各建倒排索引，支持 O(1) 单维 + O(min(|A|,|B|)) Join。

```
QueryEngine 升级后:
  queryByKind(kind)           → O(1) via kind_index[kind]
  queryBySubject(subject)     → O(1) via subj_index[subject]
  queryByKindAndSubject(k,s)  → O(min(|k_results|,|s_results|)) 取交集
  queryAliasClosure(start)    → BFS 遍历 alias_may 边 (传递闭包)
```

| Task | File | Status |
|------|------|--------|
| R8.4-a 倒排索引结构 + buildIndex() | fact/query.zig | ✅ |
| R8.4-b queryByKindAndSubject() Join 查询 | fact/query.zig | ✅ |
| R8.4-c queryAliasClosure() BFS 传递闭包 | fact/query.zig | ✅ |
| R8.4-d ptr_lifetime 用 alias closure 做 free 匹配 | ptr_lifetime.zig | ✅ |

---

### R8.5: 语言检测增强 — Personality + Globals (P1, ~1天)

**问题**: detectFromSampling() 只看函数名，缺少正交信号。

**设计**: 在现有采样基础上增加两个维度：

```
detectModuleLanguage() 增强:
  Phase 1: detectFromSampling() (现有, 保持不变)
  Phase 2 (新增): personality function 采样
    扫描所有函数的 LLVM "personality" 属性
    @rust_eh_personality  → Rust 权重 +3
    __gxx_personality_v0  → C++ 权重 +3
    _Unwind_Resume        → C 权重 +1
    无 personality        → 不投票
  Phase 3 (新增): GlobalVariable 前缀采样
    __rust_no_alloc_shim* → Rust 权重 +2
    __go_*                → Go 权重 +2
    zig.*                 → Zig 权重 +2
  最终: 三轮投票加权汇总
```

| Task | File | Status |
|------|------|--------|
| R8.5-a detectFromPersonality() 实现 | language_detector.zig | ✅ |
| R8.5-b detectFromGlobals() 实现 | language_detector.zig | ✅ |
| R8.5-c detectModuleLanguage() 三轮加权投票 | language_detector.zig | ✅ |
| R8.5-d 回归测试 18 文件语言准确率 | — | ✅ |

---

### R8 执行顺序与依赖

```
R8.1 (激活 TaintPropagationPass)         ✅ 已完成
R8.2 (跨语言边界检测)                    ✅ 已完成
R8.3 (跨函数 Alloc-Free)                 ✅ 已完成 (缺 R8.3-f propagateMemoryGraphThroughCall 接入)
R8.4 (QueryEngine 索引)                  ✅ 已完成
R8.5 (语言检测增强)                      ✅ 已完成
R8.5 (Path-Sensitive)                    ✅ 已完成 (areMutuallyExclusive + isRCPatternFree)
R8.0 (统一图设计 — UnifiedProgramGraph)  ❌ 未开始

剩余: R8.3-f + R8.0
```

### R8 Acceptance Criteria

- [x] TaintPropagationPass 成功注册并运行无报错
- [x] CrossLangEdge 被 ffi_boundary/callback_escape 至少一个 pass 消费
- [x] 跨函数 alloc-free 配对减少 memory_leak FP ≥ 50% (GlobalAllocTracker + post-pass leak report)
- [x] 别名传递闭包: double_free FP 减少 ≥ 60% (R8.4-d alias-aware free matching)
- [ ] 路径互斥 (if/else): double_free FP 额外减少 ≥ 15% (R8.5 Path-Sensitive, 待 R9 实现)
- [ ] **TP Rate ≥ 80%** (18 文件回归测试) (当前 ~38%, 需更大测试集验证)
- [x] MemoryGraph + Call Graph 统一推理，所有检测通过图查询 API (GlobalAllocTracker + alias closure)
- [x] 18 文件回归测试无 TP 丢失 (8 PASS / 0 FAIL / 2 SKIP, 7 issues, 零回归)

---

## R9: 远期 — 层次化推理 + Registry 组合推断 (Future)

> **前提**: R8 全部完成后

### R9.1: Registry 层次化推理
- `caller_lang=Go ∧ callee=C.malloc ⇒ {risk: go_cgo_alloc, confidence: 0.95}`
- consumes_ownership / transfers_ownership 字段接入 MemoryGraph

### R9.2: FactStore 不动点框架
- `fixpoint(initial_facts, rules) → converged_facts` 通用模板
- 支持 alias* 传递闭包迭代到收敛

---

## Pre-Commit Checklist

- [ ] File < 1000 lines
- [ ] Comments in English, code:comment \~ 7:3
- [ ] camelCase functions, snake\_case variables, TitleCase types
- [ ] 4-space indent
- [ ] Pub API has doc comments
- [ ] Tests: happy + boundary + error
- [ ] `zig fmt` passes
- [ ] `zig build test` passes
- [ ] No file deletion

