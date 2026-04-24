# OmniScope Security Audit Report (Round 2)

> **Audit Date**: 2026-04-24 · **Scope**: All 79 Zig source files in `src/` + CI/CD workflows + Build system · **Version**: 0.1.5 · **Method**: Manual code audit with regression verification

---

## 1. Executive Summary

| Item | Detail |
|------|--------|
| **Project** | OmniScope |
| **Description** | LLVM IR-based cross-language FFI static security analysis framework |
| **Primary Language** | Zig (0.15.2+) |
| **External Dependency** | LLVM 21/22 (LLVM-C API) |
| **Files Audited** | 79 Zig source files + 3 CI/CD workflows + build.zig |
| **Issues Found** | 38 new (1 Critical / 8 High / 19 Medium / 10 Low) + 11 unfixed from Round 1 |
| **Overall Score** | 7.5 / 10 (up from 6.5) |

---

## 2. Comparison with Round 1

### Fix Status Overview

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ Fixed | 24 | 46% |
| ⚠️ Partially Fixed | 4 | 8% |
| ❌ Unfixed | 10 | 19% |
| 🆕 New | 38 | — |

### Key Issues Fixed

| Bug ID | Description | File |
|--------|-------------|------|
| BUG-001 | Type error disabling three detectors | `ffi_detector.zig` |
| BUG-002 | memory_pool dangling pointer | `memory_pool.zig` |
| BUG-003 | memory_pool double-free | `memory_pool.zig` |
| BUG-004 | ArenaAllocator integer overflow | `memory_pool.zig` |
| BUG-005 | BFS queue fixed size | `pointer_ownership.zig` |
| BUG-007 | Indirect call integer underflow | `call_graph.zig` |
| BUG-008 | Pointer equality type comparison | `call_graph.zig` |
| BUG-009 | getIssuesBySeverity ownership | `graph.zig` |
| BUG-010 | clear() dangling pointers | `graph.zig` |
| BUG-011 | TOCTOU race condition | `taint_state.zig` |
| BUG-012 | demangleRustName input validation | `ffi_boundary.zig` |
| BUG-015 | SARIF rule description unescaped | `output/sarif.zig` |
| BUG-017 | reason field unescaped | `report/sarif.zig` |
| BUG-020 | catch unreachable | `fact/store.zig` |
| BUG-021 | count()/get() not holding lock | `fact/store.zig` |
| BUG-022 | Empty stubs (partial) | `pointer_ownership.zig` |
| BUG-024 | GEP depth factor truncation | `taint_propagation.zig` |
| BUG-025 | Ownership API | `taint_state.zig` |
| BUG-026 | profiler OOM key pointer | `profiler.zig` |
| BUG-028 | addEdge() memory leak | `graph.zig` |
| BUG-029 | deinit() trace cleanup | `graph.zig` |
| BUG-031 | identifyLanguage misclassification | `ffi_boundary.zig` |
| BUG-032 | Null check constraint inversion | `guard_propagation.zig` |
| BUG-034 | Indirect constraint handling | `steensgaard.zig` |
| BUG-035 | Virtual object ID collision | `steensgaard.zig` |
| BUG-038 | UAF detection logic error | `cpp_fp_reduction.zig` |
| BUG-040 | generate() swallowed OOM | `report/mod.zig` |

### Unfixed Issues

| Bug ID | Description | File | Severity |
|--------|-------------|------|----------|
| BUG-006 | getTypeId pointer truncation | `alias.zig` | High→Medium |
| BUG-016 | formatter.zig partial fields unescaped | `output/formatter.zig` | Medium |
| BUG-018 | Release no binary signing | `release.yml` | High |
| BUG-019 | Security analysis workflow broken | `security-analysis.yml` | High |
| BUG-027 | profiler catch unreachable | `profiler.zig` | Low |
| BUG-030 | Cartesian product false positives | `ffi_analysis.zig` | Medium |
| BUG-033 | guard_propagation pointer truncation | `guard_propagation.zig` | High |
| BUG-039 | formatTimestamp OOM | `report/mod.zig` | Medium |
| BUG-051 | resize shrink stats | `tracking/allocator.zig` | Low |
| BUG-052 | FileMap.add leak | `output/lsp.zig` | Medium |

---

## 3. New Issues

### 3.1 Critical — 1

#### BUG-NEW-001 [Critical] ffi_body_check.zig — LLVMGetNamedFunction receives non-null-terminated string

- **File**: `src/pass/analysis/issue/ffi_body_check.zig` line 515
- **Category**: Memory Safety / Out-of-Bounds Read

**Description**: `c.LLVMGetNamedFunction(module, boundary.function_name.ptr)` passes a Zig `[]const u8` slice's `.ptr` to the LLVM C API, which expects a null-terminated C string. Zig slices are typically not null-terminated, causing LLVM to read out-of-bounds memory until it finds a `\0`.

**Impact**: Out-of-bounds memory read, potentially causing crashes or reading garbage data.

**Fix**: Ensure a null-terminated string is passed, or use a temporary buffer.

---

### 3.2 High — 7

#### BUG-NEW-002 [High] cpp_fp_reduction.zig — detectLoopLeaks arbitrary pointer dereference

- **File**: `src/pass/analysis/cpp_fp_reduction.zig` line 817
- **Category**: Memory Safety / Segfault

**Description**: `const func_name = @as([*]const u8, @ptrFromInt(entry.key_ptr.*))[0..100]` casts an arbitrary `usize` value to a pointer and reads 100 bytes. If the pointer is invalid, this causes a segmentation fault.

**Fix**: Use `alloc_info.func_name` directly to obtain the function name.

---

#### BUG-NEW-003 [High] guard_propagation.zig — Value pointer truncated to u32 (still unfixed)

- **File**: `src/dataflow/guard_propagation.zig` lines 114, 124
- **Category**: Type Safety / Pointer Truncation

**Description**: `@truncate(@intFromPtr(value))` truncates 64-bit LLVM pointers to u32. Different LLVM values may map to the same ID, causing null check protections to be incorrectly applied.

**Fix**: Use `ValueIdMap.getOrPutId()` instead of `@truncate`.

---

#### BUG-NEW-004 [High] lock.zig — detectDeadlocks O(N³) complexity

- **File**: `src/pass/analysis/lock.zig` lines 288-302
- **Category**: Performance / DoS

**Description**: Triple-nested loop for deadlock detection with O(N³) complexity. In modules with many lock operations, this may cause analysis timeouts.

**Fix**: Use interval trees or sorted + binary search optimization.

---

#### BUG-NEW-005 [High] debug_info.zig — buildInlineStack no depth limit (still unfixed)

- **File**: `src/ir/debug_info.zig` lines 242-277
- **Category**: DoS

**Description**: `while (true)` loop following `getInlinedAt()` chain with no depth limit. Malicious IR with circular references causes infinite loops.

**Fix**: Add maximum depth limit (e.g., 256).

---

#### BUG-NEW-006 [High] CI/CD — curl | bash supply chain risk (still unfixed)

- **File**: `.github/workflows/ci.yml` lines 29-35, etc.
- **Category**: CI/CD Security

**Description**: `curl -sSL https://www.zvm.app/install.sh | bash` repeated across all CI jobs without checksum or signature verification.

**Fix**: Use `mlugg/setup-zig@v2` action or pin version with checksum verification.

---

#### BUG-NEW-007 [High] CI/CD — Release no binary signing (still unfixed)

- **File**: `.github/workflows/release.yml` lines 189-201
- **Category**: CI/CD Security

**Description**: Compiled binaries uploaded directly without SHA256 checksums, GPG/cosign signatures, or SBOM.

**Fix**: Add SHA256 checksum generation and cosign signing steps.

---

#### BUG-NEW-008 [High] CI/CD — Security analysis workflow binary name case mismatch

- **File**: `.github/workflows/security-analysis.yml` line 59
- **Category**: CI/CD Functionality

**Description**: Workflow uses `./zig-out/bin/omniscope` (all lowercase), but build.zig names the binary `OmniScope` (CamelCase). On Linux (case-sensitive), the security analysis step always fails, silently masked by `|| echo`.

**Fix**: Correct binary path to `./zig-out/bin/OmniScope`.

---

### 3.3 Medium — 19

| ID | File | Lines | Description |
|----|------|-------|-------------|
| BUG-NEW-009 | `buffer_overflow.zig` | 150, 203 | page_allocator allocation never freed (memory leak) |
| BUG-NEW-010 | `buffer_overflow.zig` | 142 | GEP index vs byte size comparison semantic error, massive false negatives |
| BUG-NEW-011 | `buffer_overflow.zig` | 163-170 | Array type check logic error, most detections don't trigger |
| BUG-NEW-012 | `flow_path.zig` | 170-198 | VulnerabilityReportBuilder.build causes FlowPath double ownership |
| BUG-NEW-013 | `ffi_body_check.zig` | 160-224 | isMallocUnchecked only checks same basic block, massive false positives |
| BUG-NEW-014 | `ffi_body_check.zig` | 209 | Treats any constant as null, misses comparisons with non-zero constants |
| BUG-NEW-015 | `integer_overflow.zig` | 129-131 | Any subtraction flagged as unsafe, extremely high false positive rate |
| BUG-NEW-016 | `integer_overflow.zig` | 143 | Final `return true` causes all arithmetic to be reported |
| BUG-NEW-017 | `memory_safety.zig` | 81 | Only pointer value comparison for double-free detection, misses indirect pointers |
| BUG-NEW-018 | `return_check.zig` | 82 | `\01_` prefix detection uses backslash instead of byte value 1 |
| BUG-NEW-019 | `vulnerability_rules.zig` | 166-168 | Integer Overflow rule substring matching too broad |
| BUG-NEW-020 | `ffi_analysis.zig` | 310-343 | detectOwnershipMismatch still has cartesian product false positives |
| BUG-NEW-021 | `ffi_detector.zig` | 407-433 | analyzeFFIMatch vulnerabilities slice not freed |
| BUG-NEW-022 | `pointer_ownership.zig` | 940-963 | findFreePath/canReachFree still empty stubs |
| BUG-NEW-023 | `alias.zig` | 268 | getTypeId pointer truncation to u32 (BUG-006 residual) |
| BUG-NEW-024 | `call_graph.zig` | 126 | Indirect call parameter index calculation may be inverted vs LLVM operand layout |
| BUG-NEW-025 | `rust_ffi_auditor.zig` | 116-117 | LLVMGetValueName pointer value used as set key, unreliable |
| BUG-NEW-026 | `rust_ffi_auditor.zig` | 373-378 | isExternCCall treats all non-Rust functions as unsafe FFI |
| BUG-NEW-027 | `output/formatter.zig` | 171-172 | vuln_type/severity fields still unescaped (BUG-016 residual) |

### 3.4 Low — 10

| ID | File | Description |
|----|------|-------------|
| BUG-NEW-028 | `flow_path.zig:75` | ArrayList.deinit uses deprecated API |
| BUG-NEW-029 | `ffi_semantics.zig:338` | Test code compilation error (expect parameter mismatch) |
| BUG-NEW-030 | `noise_reduction.zig:554` | total_issues u32 overflow risk |
| BUG-NEW-031 | `noise_reduction.zig:392` | indexOfPath case conversion incomplete |
| BUG-NEW-032 | `memory_pool.zig:113` | stats() in_use potential underflow |
| BUG-NEW-033 | `steensgaard.zig:239` | Indirect constraint doesn't merge points-to set |
| BUG-NEW-034 | `value_id_map.zig:51` | getOrPutId no overflow check |
| BUG-NEW-035 | `profiler.zig:16,21` | Timer catch unreachable (BUG-027 residual) |
| BUG-NEW-036 | `report/mod.zig:300` | formatTimestamp panics on OOM (BUG-039 changed but worse) |
| BUG-NEW-037 | `output/cli.zig:194-198` | Terminal output doesn't filter ANSI control sequences |

---

## 4. Issue Summary

### Severity Distribution

| Severity | New | Unfixed Old | Total |
|----------|-----|-------------|-------|
| 🔴 Critical | 1 | 0 | 1 |
| 🔴 High | 7 | 3 | 10 |
| 🟠 Medium | 19 | 5 | 24 |
| 🟡 Low | 10 | 3 | 13 |
| **Total** | **37** | **11** | **48** |

### Distribution by Category

| Category | Count |
|----------|-------|
| Memory Safety (OOB, UAF, leaks) | 11 |
| Logic Errors (analysis correctness) | 14 |
| CI/CD Security | 4 |
| Output Injection (unescaped JSON) | 3 |
| Type Safety (pointer truncation) | 3 |
| Performance / DoS | 3 |
| Error Handling | 4 |
| Other | 6 |

---

## 5. Fix Priority

| Priority | Count | Description |
|----------|-------|-------------|
| **P0 Immediate** | 3 | OOB read(1) + arbitrary pointer deref(1) + CI workflow broken(1) |
| **P1 Soon** | 7 | Analysis logic errors(4) + pointer truncation(1) + CI/CD security(2) |
| **P2 Planned** | 24 | False positives/negatives, resource management, output escaping |
| **P3 Later** | 14 | Performance, code quality, dead code |

---

## 6. Code Quality Assessment

### Improvements This Round

1. **memory_pool.zig full rewrite**: Dangling pointer, double-free, and integer overflow — all three Critical/High issues fixed
2. **graph.zig ownership model unified**: getIssuesBySeverity, clear(), addEdge(), deinit() — all four issues fixed
3. **taint_state.zig thread safety**: TOCTOU race condition fixed via mutex protection
4. **ffi_boundary.zig input validation**: demangleRustName now has complete bounds checking and overflow protection
5. **fact/store.zig error handling**: catch unreachable replaced with try, read/write methods now locked
6. **output/sarif.zig output safety**: All fields consistently use writeEscapedString
7. **call_graph.zig safety fixes**: Integer underflow and pointer comparison issues both fixed

### Areas Still Needing Improvement

1. **New module quality varies**: buffer_overflow.zig, integer_overflow.zig and other new passes have significant logic errors
2. **Pointer truncation not fully eliminated**: alias.zig and guard_propagation.zig still use @truncate
3. **CI/CD security unchanged**: curl|bash, no signing, broken workflow — all unfixed
4. **Some empty stubs remain**: pointer_ownership.zig's findFreePath/canReachFree still return false

---

## 7. Conclusion

OmniScope has shown significant improvement in this audit round. Of the 52 issues reported in Round 1, **24 have been fully fixed (46%)**, including the most severe memory_pool dangling pointer and ffi_detector type error. The overall score has improved from 6.5 to **7.5/10**.

This round identified 37 new issues, primarily from newly added analysis passes (buffer_overflow, integer_overflow, ffi_body_check, etc.) and CI/CD configuration. The most critical issues are the out-of-bounds read in `ffi_body_check.zig` and the arbitrary pointer dereference in `cpp_fp_reduction.zig`.

**Top Priority Fixes**:
1. `ffi_body_check.zig:515` — LLVMGetNamedFunction out-of-bounds read (Critical)
2. `cpp_fp_reduction.zig:817` — Arbitrary pointer dereference (High)
3. `guard_propagation.zig:114,124` — Pointer truncation (High)
4. CI/CD workflow fixes (binary name, signing, curl|bash)

---

## 8. Design Defect Analysis

> The following examines fundamental architectural trade-offs rather than line-by-line code bugs. Each design defect analyzes the underlying rationale, systemic risk, and improvement direction.

### 8.1 [DESIGN-01] ID Consistency Crisis — Three Mapping Strategies Coexist

**Modules**: `value_id_map.zig`, `guard_propagation.zig`, `alias.zig`, `pass_context`

**Current Design**: Three LLVM-value-to-ID mapping strategies coexist:

| Strategy | Used By | Method |
|----------|---------|--------|
| `ValueIdMap` | `TaintContext`, `Steensgaard`, `NullCheckRecognizer` | HashMap mapping, avoids truncation |
| `PassContext.getNextId()` | `AliasPass`, `TaintPass`, `LockPass` | Global incrementing counter |
| `@truncate(@intFromPtr(...))` | `GuardPropagation`, `AliasPass.getTypeId` | Direct 64→32 bit truncation |

**Root Problem**: When different passes exchange IDs via `FactStore`, **the same LLVM value may map to different IDs in different passes**. For example, a pointer with value_id=0x3A2F in `GuardPropagation` may have a completely different ID in `TaintContext`. This makes cross-pass fact association fundamentally unreliable.

**Trade-off**: `ValueIdMap` has extra HashMap lookup overhead, `@truncate` is zero-cost but may collide, `getNextId()` is in between. The current mix optimizes performance per-scenario.

**Systemic Risk**: All analyses depending on cross-pass fact association (alias→taint→ownership) may produce incorrect results due to ID inconsistency. This is the foundation of the entire analysis framework's correctness.

**Improvement**: Unify on a shared `ValueIdMap` instance in `PassContext`, eliminate all `@truncate` usage.

---

### 8.2 [DESIGN-02] Two Taint Analysis Implementations — Semantic Inconsistency

**Modules**: `taint.zig` (TaintPass), `taint_propagation.zig` (TaintPropagationPass)

**Current Design**:

| Dimension | TaintPass | TaintPropagationPass |
|-----------|-----------|---------------------|
| Taint model | Boolean (tainted/not-tainted) | Four-state enum + f32 confidence |
| Propagation | TaintGraph fixed-point (max 1000 iterations) | Per-instruction flow-sensitive |
| Path-sensitive | No | Partial (PathManager, degradable) |
| Context-sensitive | No | No |
| Dependencies | cfg, dfg, alias | call-graph |
| Fact storage | TaintGraph internal | TaintContext → FactStore |

**Root Problem**: The two systems define "what is tainted" differently with no coordination. `TaintPass`'s boolean model cannot express partial taint, while `TaintPropagationPass`'s four-state model cannot be understood by `TaintPass` consumers.

**Trade-off**: `TaintPass` is designed as a lightweight fast scan; `TaintPropagationPass` as precise analysis for different scenarios.

**Systemic Risk**: Downstream passes may use only one set of results, ignoring the other. The two systems may produce contradictory taint verdicts for the same pointer.

**Improvement**: Unify into a single implementation, or clearly define responsibilities and ensure non-conflicting results.

---

### 8.3 [DESIGN-03] Noise Reduction System — May Hide Real Vulnerabilities

**Modules**: `noise_reduction.zig`

**Current Design**: Three-layer filtering reduces wasmtime's 297 issues to 10-20 (**93% filter rate**):

- **Layer 1**: Function name substring matching (`indexOf`) — matches `std::`, `core::`, `alloc::` patterns → skip
- **Layer 2**: File path matching — matches `/rustc/`, `zig/lib/std/` → mark as stdlib
- **Layer 3**: Behavioral pattern matching (skeleton only, not fully implemented)

**Root Problems**:

1. **Standard library vulnerabilities systematically ignored**: `FunctionOrigin.stdlib` defaults to `shouldReportByDefault = false`. But historically, many critical vulnerabilities exist in standard libraries (glibc malloc, Rust Vec OOB, etc.).
2. **Over-suppression via name matching**: `indexOf` substring matching means user functions like `get_next_token` (contains "next") get caught.
3. **No suppression audit trail**: No logging of which findings were suppressed and why. Users cannot know what the tool hides.
4. **Attackers can evade via naming**: Malicious code named similarly to standard library patterns is automatically filtered.

**Trade-off**: High filter rate trades off against false positive rate for better UX. For CI/CD integration, too many false positives cause "cry wolf" effect.

**Systemic Risk**: A security analysis tool's **primary responsibility is to not miss real vulnerabilities**. A tool that misses real bugs but produces clean reports is more dangerous than one with many false positives but complete coverage — because the former creates **false sense of security**.

**Improvement**: Suppressed findings should output to a separate channel (`--verbose` or separate SARIF file) for user review.

---

### 8.4 [DESIGN-04] FFI Matching Model — No Signature Verification

**Modules**: `ffi/ffi_matcher.zig`

**Current Design**: `FFIMatcher` pairs `declare` with `define` via exact function name matching, completely ignoring parameter types, return types, and calling conventions.

**Root Problems**:

1. **Type-unsafe FFI calls undetected**: Rust `extern "C" fn foo(x: i32)` and C `void foo(double x)` are treated as matched FFI — a type-unsafe cross-language call.
2. **Single-module assumption**: Only detects declare/define pairs within the same compilation unit. Externally linked library functions are completely out of scope.
3. **Name mangling blind spots**: Rust's `#[no_mangle]` or `#[export_name]` breaks matching.

**Trade-off**: Pure name matching is simple and fast. Signature verification requires understanding LLVM's type system.

**Systemic Risk**: This is the system's foundation — if matching is wrong, all downstream analysis (ownership violations, boundary detection, lifetime analysis) builds on incorrect premises.

**Improvement**: At minimum, compare parameter count and basic type categories.

---

### 8.5 [DESIGN-05] Confidence Scoring — Illusion of Precision

**Modules**: `diag/issue.zig`, `rust_ffi_auditor.zig`, `taint_propagation.zig`

**Current Design**: Each Issue has `confidence: f32` (0.0-1.0) and `confidence_level` (HIGH/MEDIUM/HEURISTIC/EXPERIMENTAL). Thresholds hardcoded at 0.9/0.7/0.5.

**Root Problems**:

1. **No calibration basis**: Confidence values are hardcoded magic numbers (0.75, 0.85) with no statistical basis — no benchmarks, no ground truth datasets, no calibration experiments.
2. **Upstream errors don't propagate**: If language identification is wrong (C function misidentified as Rust), downstream analysis still reports 0.85 confidence.
3. **Orthogonal to noise suppression**: High-confidence findings may be filtered, low-confidence findings may be reported. Confidence doesn't participate in filtering decisions.

**Systemic Risk**: Users seeing "confidence: 0.95, level: HIGH" tend to trust it, but actual false positive rate is unknown. In security audit tools, **illusion of precision is itself a security risk**.

**Improvement**: Calibrate thresholds against measurable benchmark datasets, or clearly document "confidence is a heuristic estimate, not a statistical confidence interval."

---

### 8.6 [DESIGN-06] No Pass Isolation — Shared Mutable State

**Modules**: `pipeline/pipeline.zig`, `pass/manager.zig`

**Current Design**: All passes share the same `PassContext` with identical read/write access to `FactStore` and `DataFlowGraph`.

**Root Problems**:

1. **No permission tiers**: Any pass can delete or overwrite another pass's Facts, modify another pass's DataNodes.
2. **Implicit data contracts unverified**: Dependency system only guarantees execution order, not data readiness. Pass B depending on Pass A doesn't verify A actually wrote the FactKind B needs.
3. **Single point of failure**: Any pass error terminates the entire pipeline. No "best-effort" mode.

**Systemic Risk**: A buggy pass can pollute all downstream analysis results with no mechanism to detect contamination.

**Improvement**: Provide read-only FactStore views; implement "best-effort" execution that skips failed passes but continues.

---

### 8.7 [DESIGN-07] Lifetime Engine — Under-Expressive State Machine

**Modules**: `lifetime/engine.zig`, `lifetime/boundary.zig`

**Current Design**: 6 operations (alloc/free/borrow/transfer/reclaim/escape) drive 7 states (unknown/live/moved/borrowed/freed/escaped/invalid).

**Root Problems**:

1. **No path sensitivity**: Control flow merge uses lattice meet. `meet(live, moved) = invalid` produces false positives.
2. **Single resource assumption**: Cannot represent pointer aliases.
3. **Missing critical operations**: `realloc` (pointer value change), `clone` (reference counting), `lock/unlock` not modeled.
4. **Only 2 contract rules**: Only Rust→C and C→Rust defined. Missing Zig→C, Go→C, etc.

**Systemic Risk**: `realloc`-caused pointer invalidation is one of the most common FFI vulnerability types — the current model cannot detect it at all.

**Improvement**: Add `realloc` operation support; introduce path-sensitive state branching.

---

### 8.8 [DESIGN-08] Steensgaard Indirect Constraint Handling Incorrect

**Modules**: `steensgaard.zig`

**Current Design**: `indirect` constraints (`*p = q`) only execute `unite(p, q)`, treated identically to `assign` constraints (`p = q`).

**Root Problem**: Classical Steensgaard requires lambda nodes for indirect constraints. Current implementation simplifies indirect assignment to direct assignment, causing all indirectly-referenced values to be merged into the same equivalence class.

**Systemic Risk**: Taint analysis propagates along spurious alias relationships — if `p` points to `q` and `q` is tainted, all values in `p`'s equivalence class get tainted, producing massive false positives.

**Improvement**: Introduce lambda nodes for correct indirect constraint handling, or switch to a more precise alias analysis algorithm.

---

### 8.9 [DESIGN-09] Language Identification — Deceivable Heuristics

**Modules**: `ffi_analysis.zig`, `ffi_info.zig`

**Current Design**: Two-tier strategy — DWARF first, fallback to function name heuristics. Default to C when unrecognized.

**Root Problems**:

1. **Default-to-C assumption**: Kotlin/Native, D, Nim FFI all treated as C.
2. **Name mangling can be mimicked**: Attackers can name C functions starting with `_ZN...` to be misidentified as Rust.
3. **DWARF dependency fragile**: Production builds typically `strip` debug info, degrading to pure heuristics.
4. **Dual system inconsistency**: `ffi_info.zig` and `ffi_analysis.zig` use different classification rules.

**Improvement**: Unify language detection; mark as `unknown` instead of defaulting to C.

---

### 8.10 [DESIGN-10] FactStore Append-Only — Cannot Correct Erroneous Facts

**Modules**: `fact/store.zig`

**Current Design**: FactStore is append-only — supports insert and query only, no update or delete.

**Root Problem**: If an upstream pass produces incorrect facts, downstream passes cannot correct them. Analysis precision can only monotonically decrease.

**Systemic Risk**: In multi-pass pipelines, early pass misjudgments get "locked" into FactStore, affecting all subsequent analysis.

**Improvement**: Introduce fact versioning or retraction mechanisms.

---

### Design Defect Risk Matrix

| ID | Design Defect | Severity | Root Cause | Impact Scope |
|----|--------------|----------|------------|-------------|
| DESIGN-01 | ID consistency crisis | **Critical** | Three mapping strategies mixed | All cross-pass analysis |
| DESIGN-02 | Two taint analyses coexist | **Critical** | Architecture evolution legacy | Taint analysis globally |
| DESIGN-03 | Noise reduction over-filtering | **High** | SNR prioritized over recall | Systematic false negatives |
| DESIGN-04 | FFI matching no signature check | **High** | Simplicity prioritized | All FFI analysis |
| DESIGN-05 | Confidence illusion of precision | **Medium** | No calibration | User trust |
| DESIGN-06 | No pass isolation | **Medium** | Shared mutable state | Data pollution |
| DESIGN-07 | Lifetime engine under-expressive | **Medium** | Simple state machine | FFI vulnerability coverage |
| DESIGN-08 | Steensgaard indirect constraint error | **Medium** | Algorithm simplification | Alias/taint precision |
| DESIGN-09 | Language identification deceivable | **Low** | Heuristic limitation | FFI boundary misjudgment |
| DESIGN-10 | FactStore cannot correct | **Low** | Append-only design | Analysis refinement |

---

## 9. Architecturally Undetectable Vulnerability Classes

Based on the design analysis, the following vulnerability categories are **fundamentally undetectable** by the current architecture:

| Vulnerability Type | Reason |
|--------------------|--------|
| FFI via indirect calls | Function pointers, vtables, dlsym outside matching scope |
| Data races | No concurrency model |
| Integer overflow → buffer overflow | No numerical analysis capability |
| TOCTOU | No path-sensitive filesystem state modeling |
| Type confusion | Matcher doesn't verify signatures |
| Resource release in callbacks | State machine has no temporal dimension |
| realloc pointer invalidation | Lifetime engine lacks realloc operation |
| Double-free via aliased pointers | No cross-pass consistent alias analysis |

---

## 10. Conclusion (Including Design Perspective)

OmniScope has shown significant improvement at the code level (46% of old issues fixed), but **deeper systemic risks exist at the architectural design level**.

**The core design problem is lack of defense-in-depth**: Multiple critical components (noise reduction, pass dependencies, ID mapping) all use "single-point decision" patterns — one component's misjudgment is never caught and corrected by subsequent components. In security analysis tools, this lack of redundancy and cross-validation means a single component failure directly leads to missed vulnerabilities.

**Improvement Priority**:
1. **[P0]** Unify ID allocation strategy, eliminate `@truncate` usage
2. **[P0]** Unify taint analysis into single implementation
3. **[P0]** Fix Steensgaard indirect constraint handling
4. **[P1]** Add audit logging to noise reduction
5. **[P1]** Add signature verification to FFI matching
6. **[P1]** Add realloc support to lifetime engine
7. **[P2]** Confidence calibration
8. **[P2]** Pass isolation mechanism
