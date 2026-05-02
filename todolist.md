# OmniScope — Universal FFI/Unsafe Boundary Static Analyzer

> **Version**: v0.3.0 (Dataflow-Precise Analysis)
> **Core Positioning**: 通用 FFI/Unsafe 边界静态分析器，基于 LLVM IR
> **Goal**: 检测精确、通用、少量语言特定规则
> **Coding Rules**: Follow `plan/rules/rules.md` strictly

---

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

---

## Coding Standards

| Rule | Requirement | Source |
|------|-------------|--------|
| File size | <= 1000 lines per file | `rules.md` S2.1 |
| Simplicity | Minimal solution, no over-abstraction | `rules.md` S2.2 |
| Comments | English only, code:comment ~ 7:3 | `rules.md` S2.3 |
| Tests | happy + boundary + error, esp. language boundaries | `rules.md` S2.4 |
| Naming | TitleCase type, camelCase fn, snake_case var | `rules.md` S1.1 |
| Surgical | Only change what's necessary | `rules.md` S3.3 |
| Goal-driven | Each task has verifiable success criteria | `rules.md` S3.4 |
| No deletion | Never delete files | `rules.md` S2.5 |
| Public API | All pub functions have doc comments | `rules.md` S9.1 |
| Pre-commit | `zig fmt` + `zig build test` + line count | `rules.md` S10 |

---

## Current Status (2026-05-01)

| Project | Language | Issues | Breakdown |
|---------|----------|--------|-----------|
| wasmtime | Rust | 2 | 2x zig_allocator (threadlocal misclassification) |
| sqlite3 | C | 318 | 97 RETURN-STACK + 88 DOUBLE_FREE + 133 other |

### Completed Work

- [x] Three-layer noise filter (noise_filter/path_filter/behavior_filter)
- [x] `classifyFunctionFull()` unified entry point
- [x] Integration into all issue-producing passes
- [x] `isRustMangledName` _R prefix fix
- [x] `identifyCalleeLanguage` returns .c for C functions (Cross-lang: 0->1885)
- [x] Rust ownership safety rule (skip safe code UAF)
- [x] Debug info C pointer handling + length validation

### Root Cause Analysis: Why 318 sqlite3 Issues?

**RETURN-STACK (97 FP)**: `propagateOrigin` on load propagates the
**slot's own origin** (.stack from alloca), not the **content's origin**
(.heap from stored malloc result). MemoryGraph records contentSource
correctly, but `checkReturnViolation` checks `pointer_map` first and
short-circuits on .stack before consulting MemoryGraph.

**DOUBLE_FREE (88 FP)**: No path sensitivity. Conditional frees
(if-else branches, RC==0 patterns) are reported as double free
because the analyzer doesn't check if the two frees are on
mutually exclusive execution paths.

---

## P0: Dataflow Precision (Universal, No Name Dependency)

### P0-1: Fix propagateOrigin Load Semantics ✅

**Problem**: `load ptr, ptr %retval` where `%retval = alloca ptr` and
`store ptr %heapPtr, ptr %retval` — propagateOrigin gives the load
result `.stack` (the alloca's origin) instead of `.heap` (the content's
origin stored into the alloca).

**Fix**: In `trackInstruction` for LLVMLoad, after propagateOrigin,
check MemoryGraph contentSource. If content is .heap_alloc, override
the pointer_map entry with .heap origin.

**Success Criteria**:
- sqlite3 RETURN-STACK: 97 -> <20
- wasmtime: no regression (still 2)
- No project-specific function name patterns used

### P0-2: Phi Node Tracking ✅

**Problem**: Phi nodes are not tracked in pointer_map. When
`ret ptr %cond` where `%cond = phi [null, bb1], [%heapPtr, bb2]`,
pointer_map.get(%cond) returns null, skipping the check entirely.

**Fix**: In `trackInstruction`, handle LLVMPhi by merging all incoming
values' origins. If any incoming value is .heap, phi is .heap (runtime
may take that branch). If all are .stack, phi is .stack.

**Success Criteria**:
- Phi-returning functions correctly classified
- No new false negatives (if phi has a stack branch, still report)

### P0-3: Path-Sensitive DOUBLE_FREE ✅

**Problem**: Two frees of same pointer reported as DOUBLE_FREE even
when they're on mutually exclusive branches (if-else) or under
reference count guard (RC==0).

**Fix**:
1. Record each free's basic block
2. Check if two frees are in sibling blocks (same predecessor, different
   branches of a conditional branch) — mutual exclusion
3. Detect RC pattern: `load RC -> sub 1 -> cmp 0 -> br` with free in
   the RC==0 branch — conditional free

**Success Criteria**:
- sqlite3 DOUBLE_FREE: 88 -> <30
- wasmtime: no regression

### P0-4: Fix llvm.threadlocal.address Misclassification ✅

**Problem**: `ffi_boundary.zig` classifies `llvm.threadlocal.address.p0`
as `zig_allocator`. It's an LLVM intrinsic, not a Zig allocator.

**Fix**: Add LLVM intrinsic prefix check (`llvm.`) before language
classification in `ffi_boundary.zig`.

**Success Criteria**:
- wasmtime: 2 -> 0 issues

---

## P1: Semantic Classification (Minimal Language-Specific)

### P1-1: FFI Boundary Detection (Cross-Language)

- [x] `identifyCalleeLanguage` returns .c for C functions
- [x] Cross-language count: 0 -> 1885
- [x] Validate cross-language boundaries are real FFI calls (zone_classifier.classifyFunctionFromLLVM + LLVM metadata)
- [x] Support all language pairs (C/C++, Rust, Go, Zig, Python) — Language enum + identifyCalleeLanguage + semantic_registry (jni/python_c_api)

### P1-2: Unsafe Operation Detection

- [x] Rust: identify unsafe blocks in IR — ffi_unsafe.zig + zone_classifier unsafe detection
- [x] Zig: identify @ptrCast, @intToPtr, extern fn calls — ffi_type_mismatch.zig zig_alignment_mismatch + ffi_boundary.zig ptrCast detection
- [ ] C: identify setjmp/longjmp, variadic function abuse
- [x] Go: identify cgo pointer passing, //go:nosplit — callback_escape.zig cgo detection + go.json config

### P1-3: FFI Type Mismatch Detection

- [x] Basic framework in `ffi_type_mismatch.zig`
- [x] Size mismatch detection
- [x] Alignment mismatch detection — detectAlignmentMismatches() (SIMD + alignment-sensitive functions)
- [x] Sign mismatch detection — detectSignednessMismatches() (signed/unsigned integer boundary)
- [x] ABI mismatch detection — cpp_abi_mismatch in TypeMismatchKind enum (framework exists, detection partial)

---

## P2: Issue Report System

### P2-1: Risk Weighting Integration

- [x] `getEffectiveRisk()` implemented in noise_filter.zig
- [x] Integrate into Issue report output — attribution.zig filters by RiskLevel + Issue.confidence field
- [x] Group issues by origin (user/stdlib/compiler/third_party) — attribution.zig AttributionConfig.group_by_origin

### P2-2: Attribution Report

- [x] `groupByOrigin(issues)` — group by source (attribution.zig entire module)
- [x] `formatAttributionReport(groups)` — formatted output (attribution.zig)
- [x] CLI: `--focus-user-code`, `--ffi-only`, `--include-stdlib` (main.zig:129 + attribution.zig:25-32)

---

## P3: Performance

### P3-1: Function Classification Cache

- [ ] Cache classifyFunctionFull results
- [ ] Avoid re-analyzing stdlib functions

### P3-2: Parallel Analysis

- [ ] Function-level parallel analysis
- [ ] Thread-safe Issue collection

---

## Target Metrics

| Metric | Current (v0.2.1) | Target (v0.3.0) |
|--------|-------------------|-------------------|
| sqlite3 RETURN-STACK | 97 | <20 |
| sqlite3 DOUBLE_FREE | 88 | <30 |
| wasmtime issues | 2 | 0 |
| Detection method | name patterns + suppress | dataflow-precise |
| Language-specific rules | many | minimal |
| FP rate (Rust) | ~6% (2/31) | 0% |
| FP rate (C) | high (318/10038) | <5% |

---

## Pre-Commit Checklist

- [ ] File < 1000 lines
- [ ] Comments in English, code:comment ~ 7:3
- [ ] camelCase functions, snake_case variables, TitleCase types
- [ ] 4-space indent
- [ ] Pub API has doc comments
- [ ] Tests: happy + boundary + error
- [ ] `zig fmt` passes
- [ ] `zig build test` passes
- [ ] No file deletion
