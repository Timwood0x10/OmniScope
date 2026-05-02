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

### R7.1-0 Language-First — Known Issues (2026-05-02)

- [ ] **P0**: `LLVMGetProducer` 不存在于 LLVM 15，需禁用 `detectFromProducer` 或升级 LLVM
- [ ] **P1**: `_ZN` 前缀只归 Rust，C++ 也用 `_ZN`（应归 cpp_count）
- [ ] **P1**: `mapDWARFLanguage` 死代码（定义了但未被调用）
- [ ] **P1**: `detectModuleLanguage` 返回值未存入 PassContext（language_cache 未实现）
- [ ] **P1**: pipeline.zig 未调用 `detectModuleLanguage`（预扫描未集成）
- [ ] **P2**: C11 DWARF 值 29 与 GoogleRenderScript 冲突（当前 else→c_count 功能正确但语义不精确）
- [ ] **P2**: Go DWARF 值 22 与 Rust 冲突（TinyGo 用 C99 所以实际不影响）

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

| Metric | Current (v0.2.0-R7.0) | Target (v0.2.0-R7.1) |
| ------ | --------------------- | ------------------- |
| Total Issues (18 projects) | 1,169 | **~800** (↓32%) |
| TP Rate (overall) | ~33% | **~45%** |
| Pure-FP projects zeroed | 5 | 5+ (stable) |
| double_free FP rate | 65% | **<30%** |
| format_string FP rate | 80% | **<30%** |
| borrow_escape FP rate | 90% | **<40%** |
| Detection method | Zone-First + dataflow | Language-First + root-cause precise |
| Language-specific rules | minimal (zone-based) | language × zone channel routing |

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

