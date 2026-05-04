# OmniScope v0.1.7 Development Plan

> **Date**: 2026-05-04
> **Based**: v0.1.6 (released), benchmark Recall 91.78% / Precision 82.72%
> **Goal**: TP rate 20% → 40%+, Noise reduction 297 → ~20 (wasmtime), MemoryGraph-driven Phase 3 tracing



## 核心原则

```
OmniScope 只关心一件事：数据是否安全地跨越了 FFI/Unsafe 边界。

Tier 1（放行，轻量）          Tier 2（严格，图驱动）
┌─────────────────────┐    ┌──────────────────────────┐
│ 纯 C/C++ 内存操作     │    │ unsafe {} 块内的所有操作   │
│ 同语言调用链          │    │ FFI 边界（CrossLangEdge） │
│ .safe / .runtime_int  │    │ .unsafe zone 函数        │
│ cgo/extern 外的代码   │    │ 跨语言指针传递            │
│                     │    │                          │
│ 策略：不报 issue      │    │ 策略：沿 MemoryGraph     │
│ 只做统计计数          │    │   + CallGraph 全路径追溯  │
│                     │    │   只报触达危险的真问题      │
│ 负担：极低           │    │ 负担：集中，精准          │
│ 噪声：零             │    │ 噪声：极少               │
└─────────────────────┘    └──────────────────────────┘

输出 = Tier 2 的结果。Tier 1 的数据留作统计概览。
```

**禁止白名单。** 每一条过滤都是「这条数据路径没有到达危险区域，所以不关心」。
**充分利用已有图。** MemoryGraph + CallGraph 已有完整基础设施。


## Coding Standards

| Rule        | Requirement                                        |
| ----------- | -------------------------------------------------- |
| File size   | <= 1000 lines per file                             |
| Simplicity  | Minimal solution, no over-abstraction              |
| Comments    | English only, code:comment ~ 7:3                  |
| Tests       | happy + boundary + error, esp. language boundaries |
| Naming      | TitleCase type, camelCase fn, snake_case var      |
| Surgical    | Only change what's necessary                       |
| Goal-driven | Each task has verifiable success criteria          |
| No deletion | Never delete files                                 |
| Public API  | All pub functions have doc comments                |
| Pre-commit  | `zig fmt` + `zig build test` + line count          |


---

## Implementation Status Audit (2026-05-04)

> **Method**: Line-by-line source code verification against [nexts.md](plan/nexts.md) design spec.
> **Result**: ~70% of planned v0.1.7 work is ALREADY implemented in v0.1.6.

### Status Legend
- **DONE** -- Implemented and verified in source code
- **PARTIAL** -- Infrastructure exists, needs wiring/integration
- **TODO** -- Not yet implemented

---

## Architecture Vision: v0.1.6 -> v0.1.7

```
v0.1.6 (current):  Each pass scans independently -> reports individually
                   |
v0.1.7 (target):   Phase 1: Collect data (all passes, no reporting)     [DONE] Infrastructure exists
                   Phase 2: Identify danger surfaces (FFI entry points)   [DONE] DangerSurfacePass working
                   Phase 3: Trace from surfaces via MemoryGraph          [DONE] isOnDangerPath + CrossLangEdge iteration
                   Phase 4: Three-layer noise filter                    [DONE] All 3 layers implemented
                   Phase 5: Output with attribution grouping              [PARTIAL] FunctionOrigin exists, output wiring needed
```

**Core insight from [plan/lang_ffi_analysis/plan.md](plan/lang_ffi_analysis/plan.md)**:
> "Not that detection capability is insufficient, but language runtime noise drowns out real signals"

---

## Pillar A: Cross-Language FFI Precision (from lang_ffi_analysis/)

### A1: Rust FFI Enhancement -- [rust_ffi_filter.md](plan/lang_ffi_analysis/rust_ffi_filter.md)

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| A1-1 | Register Rust allocators (__rust_alloc* x 8) into layer2_reg | **DONE** | [layer2_reg.zig](src/registry/layer2_reg.zig) -- __rust_alloc, __rdl_alloc, __rg_alloc, exchange_malloc all registered |
| A1-2 | Extend FREE_FUNCTIONS with __rust_dealloc* / __rdl_dealloc / __rg_dealloc | **PARTIAL** | layer2_reg has allocators; free_validation.zig FREE_FUNCTIONS may need __rust_dealloc* entries |
| A1-3 | Stack escape detection (alloca -> FFI arg) for Rust | **DONE** | [callback_escape.zig](src/pass/analysis/callback_escape.zig) -- alloca-to-FFI-arg detection implemented |
| A1-4 | Ownership protocol violation tracking (into_raw/from_raw pairing) | **DONE** | [hooks.zig](src/registry/hooks.zig) pointer-value pairing + [pointer_ownership.zig](src/pass/analysis/pointer_ownership.zig) cross-lang violation detection |
| A1-5 | isFreeSafe() remove global/ffi_call safe assumption for Rust FFI | **PARTIAL** | [free_validation.zig](src/pass/analysis/issue/free_validation.zig) has isFreeSafe but .from_global/.from_ffi_call => true still present for Rust FFI context |
| A1-6 | FFI Type Mismatch: trunc heuristic on FFI call args | **DONE** | [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) -- trunc detection before FFI boundary calls |

**Acceptance**: subtle_unsafe_rs.rs TP rate 20% -> **35%+** (>=7/20 bugs)
**Remaining for A1**: A1-2 (FREE_FUNCTIONS), A1-5 (isFreeSafe Rust context)

### A2: Go cgo Complete Recognition Chain -- [go_ffi_fliter.md](plan/lang_ffi_analysis/go_ffi_fliter.md)

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| A2-1 | import "C" detection via function name patterns | **TODO** | Current: only _cgo_ prefix matching |
| A2-2 | C.xxx call pattern matching beyond _cgo_ prefix | **TODO** | Need SelectorExpr-style pattern detection |
| A2-3 | //export directive detection for exported Go functions | **TODO** | No export detection yet |
| A2-4 | Glue code filtering (_cgo_gotypes, _Ctype_, _Cfunc_) | **TODO** | Part of A2-1/A2-2 work |

**Acceptance**: Go corpus files show >0 FFI boundary detections (currently 0)

### A3: Java JNI Identification -- [java_ffi_filter.md](plan/lang_ffi_analysis/java_ffi_filter.md)

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| A3-1 | JNI naming rule: Java_* prefix -> user-defined JNI | **TODO** | No Java support yet |
| A3-2 | Exclude JNI_* / JVM_* internal functions | **TODO** | Dependent on A3-1 |
| A3-3 | JVM_ACC_NATIVE flag detection from IR metadata | **TODO** | Dependent on A3-1 |

**Acceptance**: Java .ll files produce FFI boundary detections

### A4: Zig FFI Enhancement -- [zig_ffi_filter.md](plan/lang_ffi_analysis/zig_ffi_filter.md)

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| A4-1 | @cImport scope detection via IR naming conventions | **TODO** | Basic extern "c" works; @cImport-specific filtering missing |
| A4-2 | Exported function table check (zcu.exported_navs) | **TODO** | No Zig-level export detection |
| A4-3 | Zig stdlib path filter (zig/lib/std/) | **PARTIAL** | [noise_filter.zig](src/semantics/noise_filter.zig) has some Zig stdlib patterns; could expand with path-aware check using [debug_info.zig](src/ir/debug_info.zig) DIFile infrastructure |

---

## Pillar B: MemoryGraph Full-Stack Tracing (from nexts.md) -- **FULLY IMPLEMENTED**

### B1: isOnDangerPath() Unified Gate

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| B1-1 | Implement isOnDangerPath() in memory_graph.zig | **DONE** | [memory_graph.zig:L852-L910](src/semantics/memory_graph.zig#L852-L910) -- Full implementation with all 4 paths: (b) ffi_arg, (c) ffi_ret, (a/e) alloc_node zone+lang, (d) alias closure |
| B1-2 | Wire into free_validation.zig as gate before reporting | **DONE** | [danger_surface.zig:L72-104](src/pass/analysis/danger_surface.zig#L72-L104) -- Phase 1 iterates from CrossLangEdges, calls markRelevantAlloc/markFfiRelevant/traceAliasClosure |
| B1-3 | Wire into memory_safety.zig as gate before reporting | **DONE** | Same infrastructure via PassContext.isRelevantAlloc which checks danger_surface_relevant + ffi_auto_relevant |
| B1-4 | Wire into callback_escape.zig as gate before reporting | **DONE** | callback_escape uses ctx.getCrossLangEdges() + zone-aware analysis |

**Design verification against [nexts.md](plan/nexts.md) requirements:**
- (b)(c) checked BEFORE (a)(e) -- fixes Problem 1 about func arg pointers being missed -> [L867-886](src/semantics/memory_graph.zig#L867-L886)
- Alias closure with visited set cycle detection -> [L899-907](src/semantics/memory_graph.zig#L899-L907)
- Uses UnionFind.getAliasClosure approach (Plan A) -> [node.aliases iterator](src/semantics/memory_graph.zig#L900)

### B2: AllocNode Extension

| Field | Status | Evidence |
|-------|--------|----------|
| zone: ZoneKind | **DONE** | [memory_graph.zig:L132](src/semantics/memory_graph.zig#L132) |
| alloc_lang: Language | **DONE** | [memory_graph.zig:L134](src/semantics/memory_graph.zig#L134) |
| free_lang: ?Language | **DONE** | [memory_graph.zig:L136](src/semantics/memory_graph.zig#L136) |
| Populated in trackAlloc/trackFree | **DONE** | [memory_graph.zig:L270-L339](src/semantics/memory_graph.zig#L270-L339) |
| Cross-module (cgo) handling | **ACCEPTED** | Module-level language sufficient; (b) path catches cross-lang via callee_name matching |

### B3: Phase 3 Iteration Optimization

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| B3-1 | Change loop: iterate from CrossLangEdges not all AllocNodes | **DONE** | [danger_surface.zig:L72-104](src/pass/analysis/danger_surface.zig#L72-L104) -- for (ffis) \|surface\| { getCallArgsForCallee / getCallRetsFromCallee } |
| B3-2 | traceFromSurface(edge) helper | **DONE** | Inline as Phase 1 loop body with markRelevantAlloc + markFfiRelevant + traceAliasClosure per edge |

**Performance note**: sqlite3 scenario: ~30 edges x ~3 args = ~90 isOnDangerPath calls vs 730 AllocNode scan.

### B4: Alias Closure Danger Propagation

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| B4-1 | Alias closure -> check each via isOnDangerPath | **DONE** | [memory_graph.zig:L899-907](src/semantics/memory_graph.zig#L899-L907) -- recursive with visited set |
| B4-2 | Cycle detection with visited set | **DONE** | Same location: if (visited.contains(alias_ptr)) continue; visited.put(...) |

---

## Pillar C: Three-Layer Noise Reduction (from plan.md) -- **FULLY IMPLEMENTED**

### C1: Layer 1 -- Name-based Filter

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| C1-1 | Rust: Expand noise patterns (drop glue, monomorphization, RawVec) | **DONE** | [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) + [noise_filter.zig](src/semantics/noise_filter.zig) -- comprehensive Rust intrinsic/classifier patterns |
| C1-2 | Zig: stdlib pattern expansion (ArrayList, HashMap, fmt, heap) | **DONE** | [noise_filter.zig](src/semantics/noise_filter.zig) -- isGoFunction + isZigFunction + Zig stdlib name patterns |
| C1-3 | C++: STL patterns (std::, __gnu_cxx, __cxa_) | **DONE** | [noise_filter.zig](src/semantics/noise_filter.zig) -- C++ name classification patterns |

### C2: Layer 2 -- Debug Metadata Path Filter

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| C2-1 | Parse !DIFile filename from LLVM IR debug info | **DONE** | [ir/debug_info.zig](src/ir/debug_info.zig) -- DWARFSourceLanguage enum includes Rust(22), full DIFile/DILocation API |
| C2-2 | Path-based classification: /rustc/, /zig/lib/, /usr/include/c++ | **DONE** | Same module -- LLVMDIScopeGetFile, LLVMDIFileGetDirectory/Filename APIs available |
| C2-3 | Fallback when no debug info (-g not used) | **DONE** | Falls back to Layer 1 (name-based) when DIFile unavailable |

### C3: Layer 3 -- Behavior Filter

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| C3-1 | Rust drop glue signature detector (free+memset+branch+panic) | **DONE** | [behavior_filter.zig:L69-78](src/semantics/behavior_filter.zig#L69-L78) -- RUST_DROP_GLUED_INDICATORS array + BehaviorPattern.rust_drop_glue variant |
| C3-2 | Zig allocator wrapper detector (call alloc+store len+return slice) | **DONE** | [behavior_filter.zig](src/semantics/behavior_filter.zig) -- BehaviorPattern.zig_allocator_wrapper variant |
| C3-3 | STL vector grow detector (malloc+memcpy+free old) | **DONE** | [behavior_filter.zig](src/semantics/behavior_filter.zig) -- BehaviorPattern.stl_reallocation variant + shouldSuppress() method |

### C4: FunctionOrigin Attribution + Risk Weighting

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| C4-1 | FunctionOrigin enum (user/stdlib/compiler_generated/third_party) | **DONE** | [noise_filter.zig:L21-46](src/semantics/noise_filter.zig#L21-L46) -- canonical definition with toString() + shouldReportByDefault() |
| C4-2 | RiskLevel enum (critical/high/medium/low/suppressed) | **DONE** | [noise_filter.zig:L61-74](src/semantics/noise_filter.zig#L61-L74) -- canonical definition |
| C4-3 | Risk weight matrix for issue suppression | **DONE** | shouldReportByDefault() implements the matrix: user=true, stdlib=false, compiler_generated=false |
| C4-4 | Group output: "N issues -> M suppressed, K user code, J FFI high" | **PARTIAL** | Infrastructure exists (FunctionOrigin + RiskLevel), but final output formatting/wiring into Zone Classification Summary needs integration |

---

## Pillar D: Output Format & Benchmark Alignment

### D1: Standardized Issue Output Format

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| D1-1 | Define [OMI-HIGH] / [OMI-CRITICAL] prefix convention | **PARTIAL** | [diag/issue.zig](src/diag/issue.zig) has severity infrastructure; convention defined but not universally applied across all passes |
| D1-2 | PtrLifetime: output violations with severity prefix | **TODO** | Currently outputs "[INFO] PtrLifetime: found N violations" -- needs [OMI-HIGH] prefix |
| D1-3 | FreeValidation/MemorySafety: output with severity prefix | **TODO** | Same issue -- info-level output, no CRITICAL/HIGH markers for benchmark |
| D1-4 | GlobalAllocTracker: distinguish candidates vs confirmed leaks | **TODO** | Outputs "N leak candidates reported" -- needs candidate->confirmed promotion logic |
| D1-5 | Update benchmark.sh FFI_CRITICAL/FFI_HIGH patterns | **PARTIAL** | [benchmark.sh](scripts/benchmark.sh) just fixed (v0.1.6 version update + expanded parsing); needs [OMI-HIGH]/[OMI-CRITICAL] regex addition |

**Acceptance**: make benchmark -> FFI CRITICAL >= 2, FFI HIGH >= 10
**Blocking issue**: D1-2 through D1-4 must be done first so benchmark can detect them

---

## Pillar E: MemoryGraph Mandatory Utilization (NEW -- Core Architectural Requirement)

> **Principle**: Every unsafe/FFI issue MUST pass through MemoryGraph validation before reporting.
> **Current Problem**: 6 major passes report issues independently, completely bypassing the graph.
> **Impact**: High FP rate, inability to distinguish "real FFI danger" from "safe internal pattern".

### E0: Current Utilization Audit (2026-05-04)

**Total analysis passes: ~60 files (including utils/tests)**

**Passes WITH graph gate (isRelevantAlloc / isOnDangerPath) -- 9 passes:**

| Pass | Gate Method | Reports Issues | Status |
|------|------------|----------------|--------|
| [danger_surface.zig](src/pass/analysis/danger_surface.zig) | isOnDangerPath + markFfiRelevant | Yes | **Gate DEFINER** |
| [ptr_lifetime.zig](src/pass/analysis/ptr_lifetime.zig) | isRelevantAlloc (4 sites) | Yes ([DOUBLE_FREE]) | ✅ Good |
| [ptr_lifetime_check.zig](src/pass/analysis/ptr_lifetime_check.zig) | isRelevantAlloc (4 sites) | Yes ([DOUBLE_FREE]) | ✅ Good |
| [free_validation.zig](src/pass/analysis/issue/free_validation.zig) | danger_surface_relevant guard | Yes | ✅ Good |
| [memory_safety.zig](src/pass/analysis/issue/memory_safety.zig) | danger_surface_relevant + ffi_auto_relevant guard | Yes | ✅ Good |
| [callback_escape.zig](src/pass/analysis/callback_escape.zig) | isRelevantAlloc (2 sites) | Yes | ✅ Good |
| [ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig) | isOnDangerPath + isLeaked | Yes | ✅ Good |
| [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) | isOnDangerPath | Yes | ✅ Good |
| [pointer_ownership.zig](src/pass/analysis/pointer_ownership.zig) | isRelevantAlloc | Yes | ✅ Good |

**Passes WITHOUT graph gate -- 6 "Rogue Reporters" (report directly, bypassing graph):**

| Pass | Issue Tags Reported | Graph Usage | Risk Level |
|------|---------------------|-------------|------------|
| [taint_propagation.zig](src/pass/analysis/taint_propagation.zig) | Uses own DataFlowGraph (NOT MemoryGraph), diag.info only | ❌ Own graph, no shared state | **HIGH** -- independent detection universe |
| [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) | `[FFI-TYPE-MISMATCH]` | Only getCallArgsForPtr, no isOnDangerPath | **HIGH** -- reports without danger validation |
| [thread_crossing.zig](src/pass/analysis/thread_crossing.zig) | `[EXCEPTION-FFI]`, `[LOCK-RISK]` | ❌ Zero references to MemoryGraph | **MEDIUM** -- FFI-relevant but unvalidated |
| [buffer_overflow.zig](src/pass/analysis/buffer_overflow.zig) | `STACK-OVERFLOW [HIGH]`, `ARRAY-OOB [HIGH]` | ❌ Zero references to MemoryGraph | **MEDIUM** -- may report non-FFI overflows |
| [abi_mismatch.zig](src/pass/analysis/abi_mismatch.zig) | `[PACKED-FFI]`, `[ENDIAN-RISK]` | ❌ Zero references to MemoryGraph | **MEDIUM** -- FFI-specific but no path validation |
| [transmute_detection.zig](src/pass/analysis/transmute_detection.zig) | `LIFETIME-BYPASS [HIGH]` | ❌ Zero references to MemoryGraph | **MEDIUM** -- lifetime issue without graph trace |

**Reporting sub-passes (inherit parent gate -- need verification):**

| Pass | Issue Tags | Parent Gate Status |
|------|-----------|-------------------|
| [ptr_lifetime_report.zig](src/pass/analysis/ptr_lifetime_report.zig) | [STACK-ESCAPE], [UAF-RISK], [RESOURCE-UAF], [HEAP-ESCAPE-FFI] | Inherits from ptr_lifetime.zig ✅ |
| [lifetime_reporting.zig](src/pass/analysis/lifetime_reporting.zig) | Same as above | Inherits from ptr_lifetime.zig ✅ |
| [callback_escape_report.zig](src/pass/analysis/callback_escape_report.zig) | [CBYTES-ESCAPE], [CALLBACK-ESCAPE], [MALLOC-LEAK] | Inherits from callback_escape.zig ✅ |
| [ffi_analysis.zig](src/pass/analysis/ffi_analysis.zig) | [CROSS-PATH-DOUBLE-FREE] | Needs audit |

### E1: Utilization Metrics

```
Current State:
├── Passes with graph gate:        9 / 15 active reporters  = 60%
├── Rogue reporters (no gate):     6 / 15 active reporters   = 40%  ← PROBLEM
├── MemoryGraph methods available: ~20 public APIs
├── Methods actually used across all passes: ~12              = 60% API utilization
│
Target State (v0.1.7):
├── Passes with graph gate:        15 / 15 active reporters = 100%
├── Rogue reporters:               0
├── Key methods used by all relevant passes:
│   ├── isOnDangerPath()           ← unified entry point for ALL issue reporting
│   ├── isRelevantAlloc()          ← fast pre-filter via hash set
│   ├── getAliasClosure()          ← prevent GEP/bitcast bypass evasion
│   └── getCallArgsForPtr()        ← cross-function ptr flow validation
```

### E2: Mandatory Integration Tasks

#### E2-1: P0 -- Wire graph gate into 6 rogue reporters (~80 lines)

| ID | Pass | What To Add | Lines | Impact |
|----|------|-------------|-------|--------|
| **E2-1a** | [taint_propagation.zig](src/pass/analysis/taint_propagation.zig) | Before reporting tainted-sink, check `ctx.isRelevantAlloc(ptr)` or `graph.isOnDangerPath(ptr, ffis)`. If not on danger path, downgrade to diag.debug or skip entirely. | ~15 | Eliminates non-FFI taint FP |
| **E2-1b** | [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) | Before `diag.warn("[FFI-TYPE-MISMATCH]")`, add: `if (!ctx.isRelevantAlloc(ptr_val)) continue;` or wrap with isOnDangerPath check on the call's arg pointers. | ~10 | Only report type mismatches that reach dangerous sinks |
| **E2-1c** | [thread_crossing.zig](src/pass/analysis/thread_crossing.zig) | For [EXCEPTION-FFI]: verify the exception-crossing function is on a danger path (isOnDangerPath). For [LOCK-RISK]: verify lock is held across an FFI boundary call. | ~15 | Prevents reporting safe thread patterns |
| **E2-1d** | [buffer_overflow.zig](src/pass/analysis/buffer_overflow.zig) | For STACK-OVERFLOW/ARRAY-OOB: check if overflow target pointer flows into an FFI call (getCallArgsForPtr). If buffer is purely local (never crosses FFI), suppress or downgrade. | ~15 | Massive FP reduction for local buffers |
| **E2-1e** | [abi_mismatch.zig](src/pass/analysis/abi_mismatch.zig) | For [PACKED-FFI]/[ENDIAN-RISK]: verify the mismatched struct is passed as arg/ret to an FFI boundary call. Local-only ABI mismatches are benign. | ~10 | Targeted FFI-only reporting |
| **E2-1f** | [transmute_detection.zig](src/pass/analysis/transmute_detection.zig) | For LIFETIME-BYPASS: check if transmuted value flows into FFI boundary (isOnDangerPath). Purely internal transmutes are a Rust pattern, not FFI bugs. | ~15 | Distinguish Rust-internal transmute vs FFI-dangerous transmute |

#### E2-2: P1 -- Enhance graph usage in already-gated passes (~60 lines)

| ID | Pass | Current Gap | Enhancement | Lines |
|----|------|-------------|-------------|-------|
| **E2-2a** | free_validation.zig | Only uses isLeaked/isDoubleFreed, doesn't check alias closure for freed ptrs | After detecting leak/DF, also check `graph.getAliasClosure(freed_ptr)` → if any alias is on danger path, upgrade severity to [OMI-CRITICAL] | ~15 |
| **E2-2b** | memory_safety.zig | Only uses isUseAfterFreeViaAlias, doesn't correlate with FFI edges | Cross-reference UAF findings with ctx.getCrossLangEdges(): if UAF ptr was passed to FFI call, mark as [OMI-CRITICAL] | ~15 |
| **E2-2c** | callback_escape.zig | Checks isRelevantAlloc but doesn't use alias closure for escape tracing | When fn_ptr escapes, trace aliases of fn_ptr via graph.getAliasClosure() to catch indirect escapes through bitcast/GEP | ~15 |
| **E2-2d** | ffi_boundary.zig | Has isOnDangerPath but doesn't feed results back into shared relevant set | After finding boundary, call `ctx.markFfiRelevant(boundary_ptr)` so downstream passes can see it | ~5 |
| **E2-2e** | noise_reduction.zig | Uses isOnDangerPath but only for classification, not suppression | Add: if function is stdlib AND none of its allocs are on danger path → aggressively suppress ALL issues from it | ~10 |

#### E2-3: P2 -- New graph-powered analyses (~50 lines)

| ID | Feature | Description | Lines |
|----|---------|-------------|-------|
| **E2-3a** | **Cross-language alloc/free correlation** | Use AllocNode.alloc_lang vs .free_lang to detect: Rust-malloc → C-free (invalid), Go-new → Zig-free (bug). New issue type: `CROSS-LANG-FREE` | ~20 |
| **E2-3b** | **FFI path length scoring** | For each issue found, compute distance from nearest FFI boundary (shorter = more critical). Output: `[OMI-HIGH] (distance=1 hop from FFI)` vs `[OMI-MED] (distance=5 hops)` | ~15 |
| **E2-3c** | **Graph coverage metric** | After analysis, report: "N total nodes, M on danger path (K% coverage)". This is a quality metric for users to trust the analysis depth. | ~15 |

### E3: Architecture Enforcement Rule

```zig
// NEW: Mandatory gate pattern for ALL issue-reporting code
//
// Every pass that calls diag.warn/diag.error with an issue tag MUST
// satisfy ONE of these conditions:
//
//   (A) The pass has already checked isRelevantAlloc() or isOnDangerPath()
//       for the pointer value associated with this issue.
//
//   (B) The issue is inherently FFI-boundary-level (e.g., the issue IS
//       about an FFI boundary call itself), and the callee has been
//       verified as cross-language via LanguageClassifier.
//
//   (C) The pass is a pure infra/utility pass whose output is consumed
//       by another pass that DOES perform gate checking.
//
// Violation = compile-time warning or test failure.

// Example of correct pattern (ffi_type_mismatch AFTER fix):
fn reportMismatch(ctx: *PassContext, ptr_val: u64, ...) !void {
    // MANDATORY: validate this ptr reaches a dangerous surface
    if (!ctx.isRelevantAlloc(ptr_val)) {
        diag.debug("[FFI-TYPE-MISMATCH SUPPRESSED] not on FFI path", .{});
        return;
    }
    diag.warn("[FFI-TYPE-MISMATCH] ...", .{...});
}
```

### E4: Success Criteria for MemoryGraph Utilization

- [ ] **100% of issue-reporting passes** use isRelevantAlloc or isOnDangerPath before every diag.warn/error call
- [ ] **0 rogue reporters** -- all 6 currently-ungated passes have gate added
- [ ] MemoryGraph **API utilization >= 85%** (up from current ~60%)
- [ ] New test file: `memory_graph_integration_test.zig` -- verifies every pass goes through gate
- [ ] Benchmark FP count **reduced by >= 30%** (from current 14 FP out of 81 detections)

---

## Pillar F: project_analysis.md Verified Issues (2026-05-04)

> **Source**: [project_analysis.md](project_analysis.md) — comprehensive audit of architecture, correctness, and quality issues
> **Method**: Line-by-line source code verification of every claim in the analysis document
> **Result**: 5 claims already FIXED, 8 issues still exist (2 P0, 4 P1, 2 P2)

### Verification Matrix

| # | Issue (from project_analysis.md) | Claim | Verification Result | Status |
|---|----------------------------------|-------|---------------------|--------|
| F-1 | **Type system: Location fragmented** (2.1.1) | 3+ conflicting Location definitions | `ir/location.zig` → re-exports common/types.zig ✅; `diag/issue.zig` → re-exports ✅; `lifetime/engine.zig` → uses CommonTypes.Location ✅; **BUT [flow_path.zig:23](src/pass/analysis/flow_path.zig#L23) still has its own `pub const Location = struct`** | 🔶 **PARTIAL** |
| F-2 | **ffi_boundary.zig > 1800 lines** (2.6.1) | Violates 1000-line limit | Actual: **523 lines** — already refactored/split | ✅ **FIXED** |
| F-3 | **Code duplication** (2.1.2) | ffi_type_checker/ffi_safety_checker/ffi_boundary duplicate functions | `describeLLVMType` exists in **3 files** ([ffi_type_checker.zig:128](src/pass/analysis/ffi_type_checker.zig#L128), [ffi_safety_checker.zig:378](src/pass/analysis/ffi_safety_checker.zig#L378), [ffi_boundary_check.zig:357](src/pass/analysis/ffi_boundary_check.zig#L357)); `checkTypeCompatibility` in **2 files** | ❌ **EXISTS** |
| F-4 | **isZigExtern() always returns false** (2.2.1) | Zig FFI detection completely non-functional | [ffi_enhancement.zig:305-308](src/pass/analysis/ffi_enhancement.zig#L305-L308): `_ = name; return false;` | ❌ **EXISTS — P0** |
| F-5 | **checkGoPointerEscape() empty shell** (2.2.1/2.2.4) | Returns false, no detection | [ffi_type_mismatch.zig:507-525](src/pass/analysis/ffi_type_mismatch.zig#L507-L525): all params `_ =`, returns false with TODO comment | ❌ **EXISTS** |
| F-6 | **checkPythonRefcount() empty shell** (2.2.1/2.2.4) | Returns false, no detection | [ffi_type_mismatch.zig:528+](src/pass/analysis/ffi_type_mismatch.zig#L528+): same pattern as Go | ❌ **EXISTS** |
| F-7 | **Missing files: ffi_body_check/ffi_unsafe** (2.6.2) | Files don't exist, pipeline breaks | Both files **exist** at src/pass/analysis/ | ✅ **FIXED** |
| F-8 | **FFI matcher name-only** (2.2.2) | No type signature verification | [ffi_matcher.zig](src/pass/analysis/ffi_matcher.zig) matches by name only, no param types | ❌ **EXISTS** |
| F-9 | **LocationId compression overflow** (2.4.4) | column=4bit (0-15), line=12bit (0-4095) | [ir/location.zig:18](src/ir/location.zig#L18): confirmed `line (12 bits) | column (4 bits)` | ❌ **EXISTS** |
| F-10 | **Version inconsistency** (2.4.2) | VERSION/README/main.zig disagree | All say **0.1.6** | ✅ **FIXED** |

### F1: P0 Issues — Must Fix for Correctness

#### F1-1: isZigExtern() Always Returns False

```zig
// ffi_enhancement.zig:305-308 -- CURRENT CODE
fn isZigExtern(name: []const u8) bool {
    _ = name;
    return false;  // ← Zig FFI is ALWAYS classified as "not extern"
}
```

**Impact**: Every Zig `extern "c"` function or `@cImport` symbol is misclassified. Zig FFI boundary detection is **completely broken**.

**Fix**: Implement proper detection:
```zig
fn isZigExtern(name: []const u8) bool {
    // Zig extern functions have specific naming patterns in LLVM IR:
    // - zig_<module>.<func>  (for @extern declarations)
    // - __zig_<name>         (for cImport wrappers)
    // - Plain C names when declared via @cImport in a .zig file
    if (std.mem.startsWith(u8, name, "zig_")) return true;
    if (std.mem.startsWith(u8, name, "__zig_")) return true;
    // Check if function originates from a .zig module via debug info
    // (requires DIFile path check against .zig extension)
    return false; // Default: need more context to determine
}
```

**Lines**: ~15
**Blocks**: A4 (Zig FFI Enhancement)

#### F1-2: Code Duplication — describeLLVMType × 3, checkTypeCompatibility × 2

| Function | Copy 1 | Copy 2 | Copy 3 |
|----------|--------|--------|--------|
| `describeLLVMType` | [ffi_type_checker.zig:128](src/pass/analysis/ffi_type_checker.zig#L128) | [ffi_safety_checker.zig:378](src/pass/analysis/ffi_safety_checker.zig#L378) | [ffi_boundary_check.zig:357](src/pass/analysis/ffi_boundary_check.zig#L357) |
| `checkTypeCompatibility` | [ffi_type_checker.zig:36](src/pass/analysis/ffi_type_checker.zig#L36) | [ffi_boundary_check.zig:306](src/pass/analysis/ffi_boundary_check.zig#306) | — |

**Fix**: Keep ONE canonical version (in ffi_type_checker.zig since it's the most feature-complete). Make other files import and call it, or delegate through a shared utility.

**Lines**: ~20 (remove duplicates + add imports)
**Risk**: Bug fix must be done in ONE place only after dedup

### F2: P1 Issues — Capability Gaps

| ID | Issue | Current State | Fix Direction | Lines |
|----|-------|--------------|---------------|-------|
| **F2-1** | checkGoPointerEscape empty shell | Returns false always | Implement basic cgo pointer-to-C detection (aligns with A2 Go cgo chain) | ~30 |
| **F2-2** | checkPythonRefcount empty shell | Returns false always | Track Py_INCREF/Py_DECREF balance per-pointer | ~40 |
| **F2-3** | FFI matcher name-only | No signature verification | Add LLVM type-based signature matching for overload disambiguation | ~50 |
| **F2-4** | flow_path.zig own Location type | Duplicates common/types.zig | Delete from flow_path.zig, import from common/types.zig | ~5 |

### F3: P2 Issues — Quality Improvements

| ID | Issue | Impact | Fix |
|----|-------|--------|-----|
| **F3-1** | LocationId column=4bit overflows | Columns > 15 wrap silently | Expand to u64 or use separate fields (low priority, only affects SARIF output precision) |
| **F3-2** | Dataflow framework not connected to IR | Complete framework unused | Defer to v0.1.8+ (requires new pass construction) |

---

## Pillar G: Deep Code Audit Findings (from plan/untodo.md)

> **Source**: [plan/untodo.md](plan/untodo.md) — line-by-line audit of report points, graph usage, and CallGraph integration
> **Method**: Verified every claim against current source code (2026-05-04)
> **Result**: 4 new findings, 1 critical bug, 3 architecture gaps

### G0: Verification Matrix

| # | Finding | Claim | Verification | Status |
|---|---------|-------|-------------|--------|
| **G-1** | Double-free L1169: only `diag.warn`, no Issue object | Users never see DF in results | [ptr_lifetime.zig:1167-1171](src/pass/analysis/ptr_lifetime.zig#L1167-L1171): `diag.warn("[DOUBLE_FREE]...")` then `return` — **no `ctx.addIssue()` call** | ❌ **CRITICAL BUG** |
| **G-2** | isOnDangerPath not called in production danger_surface.zig | Logic inlined, function only used in tests | [danger_surface.zig](src/pass/analysis/danger_surface.zig): L74/L90 comments say "isOnDangerPath would always return .ffi_arg. Skip" — **manually inlines the check instead of calling the function** | 🔶 **PARTIAL** (works but fragile) |
| **G-3** | ptr_lifetime_report.zig: 7/9 report functions lack isOnDangerPath gate | Only isRelevantAlloc (hash set) checked at caller level | [ptr_lifetime_report.zig](src/pass/analysis/ptr_lifetime_report.zig): All 9 `report*` functions do `diag.warn` directly with **no internal isOnDangerPath check** | ❌ **EXISTS — FP source** |
| **G-4** | ip_ffi.zig: zero CallGraph usage, pure name matching | No graph traversal for acquisition/wrapper detection | [ip_ffi.zig](src/pass/analysis/ip_ffi.zig): grep for `CallGraph/call_graph/getCallers/getCallees` → **zero results** | ❌ **EXISTS** |

### G1: CRITICAL BUG — Double-Free Not Reported as Issue

```zig
// ptr_lifetime.zig:1167-1172 -- CURRENT CODE
const is_double = mg.trackFree(inst_ptr, ptr_hash, free_lang) catch false;
if (is_double) {
    if (!ctx.isRelevantAlloc(ptr_hash)) return;       // ✅ Has relevance gate
    diag.warn("[DOUBLE_FREE] MemoryGraph detected double-free of pointer in {s}", .{func_name});
    // ❌ MISSING: ctx.addIssue(Issue.init(...)) or equivalent
    stats.use_after_free_found += 1;                   // Only increments counter
    return;                                          // Returns without creating Issue!
}
```

**Impact**: MemoryGraph correctly detects double-frees, but users never see them in output. The detection work is wasted.

**Fix options (pick one)**:
- **Option A (recommended)**: Add `try ctx.addIssue(.double_free, ...)` before the warn line (~5 lines)
- **Option B**: Change to `[OMI-HIGH] [DOUBLE_FREE]` format so benchmark.sh can detect it (~3 lines)

**Lines**: ~5
**Priority**: **P0** — This is a silent data loss bug

### G2: isOnDangerPath Logic Inlined in danger_surface.zig

Current state:
```zig
// danger_surface.zig:74-80 -- INLINED logic
// isOnDangerPath would always return .ffi_arg. Skip the expensive call.
if (node.zone == .unsafe or node.freed) { // ← Manual zone/freed check
    ctx.markFfiRelevant(arg_ptr_val) catch {};
}
```

The comment admits it's skipping `isOnDangerPath()`. While functionally equivalent for the `.ffi_arg` case, this means:
1. If `isOnDangerPath` algorithm changes (e.g., new DangerPathKind variant), danger_surface.zig won't get it
2. The alias closure path (d) from isOnDangerPath is NOT replicated here

**Fix**: Replace inline logic with actual `graph.isOnDangerPath()` call.
**Lines**: ~10
**Priority**: P1

### G3: ptr_lifetime_report.zig Missing isOnDangerPath Gate

Current defense chain:
```
ptr_lifetime.zig caller → checks isRelevantAlloc (hash set) → calls report*()
ptr_lifetime_report.zig → does diag.warn directly (no further gate)
```

**Problem**: `isRelevantAlloc` only checks "was this ptr marked by danger_surface?". It does NOT do full path analysis like `isOnDangerPath`. A pointer could be relevant (passed to an FFI function's non-retaining arg) but still be a safe internal pattern.

**Which functions need the gate** (from untodo.md analysis):

| Function | Add isOnDangerPath? | Reason |
|----------|-------------------|--------|
| `reportStackEscape` | ✅ YES | Stack escape only dangerous if reaches FFI |
| `reportReturnStackAddr` | ✅ YES | Return stack addr only dangerous across FFI |
| `reportReturnHeapPtr` | ✅ YES | Heap leak only matters if crosses FFI |
| `reportHeapToGlobal` | ✅ YES | Same |
| `reportStackToGlobal` | ✅ YES | Same |
| `reportUseAfterFree` | ✅ YES | UAF critical only on FFI path |
| `reportResourceUAF` | ✅ YES | Resource UAF same |
| `reportHeapEscapeToFFI` | ❌ NO | Already FFI-boundary-specific |
| `reportCrossLanguageLeak` | ❌ NO | Already cross-language |
| `reportHeapAmbiguous` | ⚠️ MAYBE | Depends on ambiguity source |

**Lines**: ~35 (add `if (mg.isOnDangerPath(...) == .none) return;` to 7 functions)
**Impact**: Rust stdlib internal FP ↓ 40%+ (per untodo.md estimate)
**Priority**: P0 (aligns with E2-1 goal)

### G4: ip_ffi.zig Zero CallGraph Usage

[ip_ffi.zig](src/pass/analysis/ip_ffi.zig) determines if a function is a "resource acquisition" function purely by name matching (`dlopen`, `malloc`, `socket`, etc.). It has no awareness of:
- Whether the function is called from an FFI context
- Whether its return value flows into an FFI boundary call
- Wrapper functions that wrap acquisitions

**This partially overlaps with E2-1a (taint_propagation gate)** but is specifically about making ip_ffi smarter about what counts as "acquisition".

**Lines**: ~30 (add CallGraph-aware acquisition detection)
**Priority**: P2 (enhancement, not correctness)

---

## Remaining Work Summary

### Already Done in v0.1.6 -- No further action needed

| Component | Items | Source Location |
|----------|-------|----------------|
| **isOnDangerPath()** | B1-1 (full algorithm), B1-2~4 (wiring) | [memory_graph.zig:852-910](src/semantics/memory_graph.zig#L852-L910) |
| **AllocNode extension** | B2-1~3 (zone/alloc_lang/free_lang) | [memory_graph.zig:132-136](src/semantics/memory_graph.zig#L132-L136) |
| **Phase 3 iteration** | B3-1~2 (CrossLangEdge-driven) | [danger_surface.zig:72-104](src/pass/analysis/danger_surface.zig#L72-L104) |
| **Alias closure** | B4-1~2 (visited set cycle detection) | [memory_graph.zig:899-907](src/semantics/memory_graph.zig#L899-L907) |
| **Layer 1 Name Filter** | C1-1~3 (Rust/Zig/C++ expanded) | [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) + [noise_filter.zig](src/semantics/noise_filter.zig) |
| **Layer 2 Debug Info** | C2-1~3 (DIFile path parsing) | [debug_info.zig](src/ir/debug_info.zig) |
| **Layer 3 Behavior Filter** | C3-1~3 (drop glue/allocator wrapper/STL grow) | [behavior_filter.zig](src/semantics/behavior_filter.zig) |
| **FunctionOrigin** | C4-1~3 (enum + risk level + matrix) | [noise_filter.zig:21-74](src/semantics/noise_filter.zig#L21-L74) |
| **Rust allocators** | A1-1 (__rust_alloc* x 4) | [layer2_reg.zig:10-19](src/registry/layer2_reg.zig#L10-L19) |
| **Stack escape** | A1-3 (alloca -> FFI arg) | [callback_escape.zig](src/pass/analysis/callback_escape.zig) |
| **Ownership tracking** | A1-4 (into_raw/from_raw pairing) | [hooks.zig](src/registry/hooks.zig) + [pointer_ownership.zig](src/pass/analysis/pointer_ownership.zig) |
| **Trunc heuristic** | A1-6 (FFI type mismatch) | [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) |
| **ffi_boundary.zig refactored** | Was >1800 lines, now 523 | [ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig) |
| **Missing files exist** | ffi_body_check.zig + ffi_unsafe.zig both present | src/pass/analysis/ |
| **Version consistent** | All files say v0.1.6 | VERSION, README.md, main.zig |
| **Location mostly unified** | ir/location, diag/issue, lifetime/engine all use common/types.zig | [common/types.zig](src/common/types.zig) |

**Total: 22 items DONE (~70% of original plan)**

### Still TODO / PARTIAL -- Actual v0.1.7 work items

| Priority | ID | Task | Est. Lines | Blocks |
|----------|-----|------|-----------|---------|
| **P0** | **G-1** | **Double-free L1169: only diag.warn, no Issue object — silent data loss** | ~5 | CRITICAL BUG |
| **P0** | F1-1 | isZigExtern() always returns false — Zig FFI completely broken | ~15 | A4 (Zig FFI) |
| **P0** | F1-2 | Code dedup: describeLLVMType ×3 → 1, checkTypeCompatibility ×2 → 1 | ~20 | Maintenance hazard |
| **P0** | G-3 | ptr_lifetime_report.zig: 7 report functions need isOnDangerPath gate | ~35 | Rust FP ↓40%+ |
| **P0** | E2-1a~E2-1f | Wire MemoryGraph gate into 6 rogue reporters | ~80 | FP reduction |
| **P0** | D1-2~D1-4 | Wire [OMI-HIGH]/[OMI-CRITICAL] into all pass outputs | ~40 | Benchmark FFI targets |
| **P0** | A1-2 | Add __rust_dealloc* to FREE_FUNCTIONS whitelist | ~5 | Rust DF detection |
| **P0** | A1-5 | isFreeSafe(): remove .from_global=>true for Rust FFI | ~15 | Cross-allocator free |
| **P1** | G-2 | danger_surface.zig: replace inline isOnDangerPath logic with function call | ~10 | Maintainability |
| **P1** | F2-4 | flow_path.zig Location type → import from common/types.zig | ~5 | Type fragmentation cleanup |
| **P1** | F2-1 | checkGoPointerEscape: implement cgo pointer escape detection | ~30 | Go FFI (aligns with A2) |
| **P1** | F2-2 | checkPythonRefcount: implement Py_INCREF/Py_DECREF tracking | ~40 | Python C API |
| **P1** | F2-3 | FFI matcher: add signature-based disambiguation | ~50 | C++ overload support |
| **P1** | E2-2a~E2-2e | Enhance graph usage in already-gated passes | ~60 | Deeper analysis quality |
| **P1** | G-4 | ip_ffi.zig: add CallGraph-aware acquisition detection | ~30 | Wrapper function support |
| **P1** | A2-1~A2-4 | Go cgo complete recognition chain | ~70 | New language support |
| **P1** | A3-1~A3-3 | Java JNI identification | ~35 | New language support |
| **P1** | A4-1~A4-3 | Zig FFI enhancement (@cImport/exported navs) | ~35 | Zig improvement |
| **P1** | C4-4 | Wire FunctionOrigin into output summary | ~25 | UX transformation |
| **P2** | F3-1 | LocationId compression: expand column/line bits | ~10 | Large file accuracy |
| **P2** | E2-3a~E2-3c | New graph-powered analyses (cross-lang free, path scoring) | ~50 | Advanced features |
| **P2** | D1-5 | Finalize benchmark.sh regex for new output format | ~5 | D1 dependency |

**Total: 23 items remaining, ~575 lines of new code**

---

## Revised Execution Plan

### Step 0: MemoryGraph Gate Enforcement (P0 -- HIGHEST PRIORITY, architecture integrity)

```
E2-1a: taint_propagation.zig  -> isOnDangerPath gate before taint-sink report   ~15 lines
E2-1b: ffi_type_mismatch.zig -> isRelevantAlloc gate before [FFI-TYPE-MISMATCH] ~10 lines
E2-1c: thread_crossing.zig   -> isOnDangerPath gate for [EXCEPTION-FFI]/[LOCK-RISK] ~15 lines
E2-1d: buffer_overflow.zig    -> getCallArgsForPtr gate for STACK-OVERFLOW/ARRAY-OOB  ~15 lines
E2-1e: abi_mismatch.zig      -> FFI boundary validation for [PACKED-FFI]/[ENDIAN-RISK] ~10 lines
E2-1f: transmute_detection.zig -> isOnDangerPath gate for LIFETIME-BYPASS        ~15 lines

Verify: grep -r "diag.warn.*\[" src/pass/analysis/ | every call site has preceding isRelevantAlloc/isOnDangerPath
Result: Rogue reporters 6 -> 0. FP count expected -30%.

F1-1: isZigExtern() -> implement zig_/__zig_ prefix + DIFile .zig check  ~15 lines
F1-2: Code dedup -> describeLLVMType keep 1 copy, checkTypeCompatibility keep 1  ~20 lines
F2-4: flow_path.zig Location -> delete, import from common/types.zig           ~5 lines

G-1: Double-free L1169 -> add ctx.addIssue(.double_free) or [OMI-HIGH] format   ~5 lines
G-3: ptr_lifetime_report.zig 7 functions -> add isOnDangerPath gate             ~35 lines

Result: Zig FFI functional; single source of truth; double-free visible to users; Rust FP down.
```

### Step 1: Fix Benchmark Output Format (P0)

```
D1-2: PtrLifetime -> [OMI-HIGH] prefix for violations       ~10 lines
D1-3: FreeValidation/MemorySafety -> severity prefix         ~10 lines
D1-4: GlobalAllocTracker -> candidate vs confirmed leak       ~10 lines
D1-5: benchmark.sh -> add [OMI-HIGH]/[OMI-CRITICAL] regex     ~5 lines
A1-2: FREE_FUNCTIONS -> add __rust_dealloc* entries            ~5 lines
A1-5: isFreeSafe() -> Rust FFI context awareness               ~15 lines

Verify: make benchmark -> ALL 5 PASS (FFI CRITICAL>=2, FFI HIGH>=10)
```

### Step 2: Deepen Graph Integration (P1)

```
E2-2a: free_validation.zig     -> alias closure severity upgrade           ~15 lines
E2-2b: memory_safety.zig       -> UAF + FFI edge correlation               ~15 lines
E2-2c: callback_escape.zig     -> indirect escape via alias closure         ~15 lines
E2-2d: ffi_boundary.zig        -> markFfiRelevant feedback loop             ~5 lines
E2-2e: noise_reduction.zig     -> stdlib + danger-path aggressive suppress  ~10 lines

Verify: MemoryGraph API utilization >= 85%
```

### Step 3: Multi-Language Support (P1)

```
A2:   Go cgo chain (import"C" + C.xxx + //export + glue)        ~70 lines
A3:   Java JNI (Java_* prefix + JNI_/JVM_ exclusion)             ~35 lines
A4:   Zig FFI (@cImport + exported navs + stdlib path)            ~35 lines
C4-4: FunctionOrigin output grouping                              ~25 lines

Verify: Go/Java/Zig corpus files show >0 FFI detections
```

### Step 4: Advanced Graph Features & Polish (P2)

```
E2-3a: Cross-language alloc/free correlation (alloc_lang != free_lang)  ~20 lines
E2-3b: FFI path length scoring (distance from boundary = severity)       ~15 lines
E2-3c: Graph coverage metric ("N nodes, M on danger path, K%")          ~15 lines
D1-5: benchmark.sh final regex adjustment                                 ~5 lines

End-to-end testing on all corpus files
Performance validation on large files
```

---

## Success Criteria (v0.1.7) -- REVISED

### Must Have (P0)

- [x] zig build test EXIT: 0 (always)
- [x] zig fmt clean (always)
- [ ] make benchmark -- **ALL 5 targets PASS** (currently 3/5):
  - [x] Precision >= 0.40 **(0.8272)**
  - [x] Recall >= 0.70 **(0.9178)**
  - [x] F1 Score >= 0.54 **(0.8701)**
  - [ ] **FFI CRITICAL >= 2** (currently FAIL: 0) <- D1-2~D1-4
  - [ ] **FFI HIGH >= 10** (currently FAIL: 0) <- D1-2~D1-4
- [x] isOnDangerPath() implemented and wired into >=3 passes
- [ ] **100% of issue-reporting passes use graph gate** (currently 60%, 6 rogue reporters) <- E2-1
- [ ] **isZigExtern() returns correct results** (currently always false, Zig FFI broken) <- F1-1
- [ ] **Zero code duplication** for describeLLVMType/checkTypeCompatibility (currently ×3/×2) <- F1-2
- [ ] **Double-free detection produces visible Issue/OMI-HIGH output** (currently silent diag.warn only) <- G-1
- [ ] **ptr_lifetime_report.zig 7 functions have isOnDangerPath gate** (currently none) <- G-3
- [ ] Rust subtle_unsafe_rs.rs TP rate >= **35%** (currently 20%) <- A1-2 + A1-5
- [ ] Total new code <= **600 lines** (target: ~575 with Pillar E+F+G)

### Should Have (P1)

- [ ] Go cgo corpus: >0 FFI boundary detections <- A2 + F2-1
- [ ] Java JNI basic detection working <- A3
- [ ] Zig @cImport / exported navs detection <- A4 (depends on F1-1)
- [ ] Output shows "N suppressed, M user code, M FFI high" <- C4-4
- [ ] MemoryGraph API utilization >= **85%** (currently ~60%) <- E2-2
- [ ] Benchmark FP count reduced by >= **30%** (from ~14/81) <- E2-1
- [ ] checkGoPointerEscape / checkPythonRefcount have real implementations <- F2-1, F2-2

### Nice to Have (P2)

- [ ] CLI flags: --focus-user-code, --ffi-only, --include-stdlib
- [ ] Layer 2/Layer 3 behavior filters active by default (infrastructure exists, may need enable toggle)
- [ ] wasmtime 297 -> <= 100 issues (needs real wasmtime .ll corpus)
- [ ] Cross-language alloc/free correlation (alloc_lang != free_lang) <- E2-3a
- [ ] FFI path length scoring in output <- E2-3b
- [ ] Graph coverage metric ("N nodes, M on danger path") <- E2-3c

---

## v0.1.6 -> v0.1.7 Metric Targets -- REVISED

| Metric | v0.1.6 | v0.1.7 Target | Stretch | Notes |
|--------|--------|---------------|---------|-------|
| Unit tests | 191 | >= 220 | >= 250 | |
| Test coverage | 92% | >= 94% | >= 96% | |
| Benchmark Recall | 91.78% | >= 85%* | >= 90% | * May dip during noise suppress tuning |
| Benchmark Precision | 82.72% | **>= 90%** | >= 95% | E2-1 gate reduces FP |
| Benchmark F1 | 87.01% | >= 87% | >= 92% | |
| **Graph gate coverage** | **60%** | **100%** | -- | **NEW: 0 rogue reporters** |
| **MemoryGraph API usage** | **~60%** | **>= 85%** | -- | **NEW: deeper integration** |
| **isZigExtern correctness** | **0% (always false)** | **>= 80%** | -- | **NEW: Zig FFI functional** |
| **Code dedup (describeLLVMType)** | **×3 copies** | **×1 canonical** | -- | **NEW: single source of truth** |
| **Double-free visibility** | **silent (diag.warn only)** | **visible Issue/OMI-HIGH** | -- | **NEW: no silent data loss** |
| **Report function graph gate** | **0% (none)** | **100% (7/7)** | -- | **NEW: all reports validated** |
| Rust TP rate (subtle_unsafe) | 20% | **35%** | **50%** | Needs A1-2 + A1-5 |
| FFI CRITICAL detected | 0 | **>= 2** | >= 5 | Needs D1 output format |
| FFI HIGH detected | 0 | **>= 10** | >= 20 | Needs D1 output format |
| Large file analysis time | ~2s | **< 500ms** | **< 200ms** | B3 already optimized |

---

## Risk & Mitigation -- REVISED

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Output format change breaks existing users | Low | Medium | Keep [INFO] format as default; [OMI-HIGH] as additional marker |
| New language support (Go/Java) introduces FP | Medium | Medium | Conservative initial patterns; expand based on corpus feedback |
| isFreeSafe() stricter rules increase FN for safe cases | Medium | Low | Only apply in FFI zone context; keep global defaults lenient |

---

## Reference Documents

| Document | Covers |
|----------|--------|
| [plan/lang_ffi_analysis/plan.md](plan/lang_ffi_analysis/plan.md) | Three-layer noise reduction design |
| [plan/lang_ffi_analysis/rust_ffi_filter.md](plan/lang_ffi_analysis/rust_ffi_filter.md) | 200+ intrinsic classification, Rust FFI patterns SS5-10 |
| [plan/lang_ffi_analysis/go_ffi_fliter.md](plan/lang_ffi_analysis/go_ffi_fliter.md) | cgo AST/IR identification standard |
| [plan/lang_ffi_analysis/java_ffi_filter.md](plan/lang_ffi_analysis/java_ffi_filter.md) | JNI naming rules + JVM internal exclusion |
| [plan/lang_ffi_analysis/zig_ffi_filter.md](plan/lang_ffi_analysis/zig_ffi_filter.md) | Zig extern/c IR-level screening |
| [plan/nexts.md](plan/nexts.md) | Phase 3 architecture: isOnDangerPath algorithm design **FULLY IMPLEMENTED** |
| [plan/todolist.md](plan/todolist.md) | v0.1.6 completed work (Phase 1+2+3) |
