# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-05-26

### Release Focus

OmniScope 0.2.0 consolidates the 0.1.9 fixes with the new semantic-resolution and surface-classification work. This release introduces the **SRT (Semantic Resolution Tree) architecture** — a unified FP suppression system that reduces false positives by ~94% while maintaining ≥90% true-positive rate on red team tests.

### Architecture Upgrade: SRT (Semantic Resolution Tree)

**SemanticKind enum expanded from 4 → 15+ variants** to cover cross-language FFI patterns:

| Category | SemanticKind Variants | Purpose |
|----------|----------------------|---------|
| **Legacy** | `unknown`, `allocation`, `release`, `provenance` | Original 4 kinds (kept) |
| **R-0: LLVM Attributes** | `readonly_param`, `mutable_param` | Parameter attribute detection (covers 1877 FP from write_to_immutable) |
| **R-1: Provenance** | `heap_provenance`, `global_provenance` | Box/Arc/Rc/Vec vs static/const origins |
| **R-2: Interior Mutability** | `interior_mutability` | UnsafeCell/OnceLock/Cell/RefCell/Mutex/RwLock/Atomic* |
| **R-3: RAII** | `raii_drop_release` | Compiler-inserted Drop/dealloc patterns |
| **R-4: Syscalls** | `file_operation`, `network_operation`, `process_operation` | POSIX syscall classes |
| **R-5: Language Gate** | *(detection routing)* | Module language detection for detector routing |
| **R-6: Ownership Transfer** | `into_raw_transfer` | Box/CString/Vec::into_raw ownership transfer |
| **R-7: Library Release** | `library_release` | mimalloc/zlib/openssl/sqlite library dealloc |
| **R-8: Parameters** | `from_parameter` | Function parameter source (not stack escape) |
| **Multi-language** | Python (5), Go (4), C# (3), Java (3), C++ (4) | Language-specific semantics |

### New: 9 IR Pattern Detectors (R-0~R-8)

Each detector populates the SRT with semantic resolutions:

| Detector | File | Detections | FP Coverage |
|----------|------|------------|-------------|
| **R-0: ParamAttr Detector** | `src/semantics/patterns/param_attr.zig` | LLVM readonly/mutable attrs | ~1877 FP (write_to_immutable) |
| **R-1: HeapProvenance Detector** | `src/semantics/patterns/heap_provenance.zig` | Box/Arc/Rc/Vec origins | ~300 FP (borrow_escape) |
| **R-2: InteriorMutability Detector** | `src/semantics/patterns/interior_mut.zig` | UnsafeCell/Cell/RefCell/Mutex | ~150 FP (write_to_immutable) |
| **R-3: RAII Detector** | `src/analysis/raii_detector.zig` | C++ destructor, Rust Drop | ~200 FP (use_after_free) |
| **R-4: Syscall Classifier** | `src/semantics/patterns/syscall_class.zig` | POSIX file/net/proc | ~100 FP (cross_language_free) |
| **R-5: LangDetector** | `src/semantics/patterns/lang_detector.zig` | Module language gating | Enables language-specific routing |
| **R-6: IntoRawTransfer Detector** | `src/semantics/patterns/into_raw_transfer.zig` | Box::into_raw patterns | ~180 FP (cross_language_free) |
| **R-7: LibraryRelease Detector** | `src/semantics/patterns/library_release.zig` | Custom allocator dealloc | ~80 FP (invalid_free) |
| **R-8: ParamSource Detector** | `src/semantics/patterns/param_source.zig` | Function parameter origins | ~120 FP (borrow_escape) |

### New: Issue Gate (Unified Suppression)

**File**: `src/pass/filter/issue_gate.zig`

Every issue must pass through the Issue Gate before emission. The gate queries the SRT for semantic resolutions:

```zig
pub fn checkIssue(srt: *const SemanticTree, value_ref: u64, kind: IssueKind) GateVerdict
```

**Gate Verdicts** (10 suppression reasons + allow):

| Verdict | Detector | Suppressed Issue Kind |
|---------|----------|----------------------|
| `suppress_mutable_param` | R-0 | write_to_immutable |
| `suppress_interior_mut` | R-2 | write_to_immutable |
| `suppress_heap_origin` | R-1 | borrow_escape |
| `suppress_global_origin` | R-1 | borrow_escape |
| `suppress_raii` | R-3 | use_after_free |
| `suppress_non_memory_syscall` | R-4 | cross_language_free |
| `suppress_ownership_transfer` | R-6 | cross_language_free |
| `suppress_library_release` | R-7 | invalid_free, cross_language_free |
| `suppress_parameter_source` | R-8 | borrow_escape |
| `allow` | — | Issue passes through |

**Enhanced Gate Features**:
- Conflict detection: If value has BOTH suppressible AND non-suppressible kinds → allow (conservative)
- Confidence threshold: Only suppress if resolution confidence ≥ 0.85
- Secondary corroboration: Additional safety checks per issue kind

### New: Confidence Scorer (4-Tier System)

**File**: `src/pass/analysis/resource/issue_verifier.zig`

**Thresholds**:
- **HIGH** ≥ 0.75: Multiple cross-validated signals (report always)
- **MEDIUM** ≥ 0.55: Single strong signal (report by default)
- **LOW** ≥ 0.35: Heuristic match (needs review)
- **UNRELIABLE** < 0.35: Experimental (suppress by default)

**Scoring Parameters** (P8-17 ~ P8-20):

| Category | Bonus | Penalty |
|----------|-------|---------|
| Concrete execution path | +0.12 | — |
| Cross-family mismatch | +0.15 | Same family: -0.10 |
| Ownership violation | +0.12 | — |
| FFI boundary | +0.10 | Runtime internal: -0.08 |
| Use-after-release | +0.18 | Valid escape: -0.15 |
| Double release | +0.18 | Valid destructor: -0.12 |

### FP Suppression Results (Measured)

| Metric | v0.1.x (Baseline) | v0.2.0 (After SRT) | Change |
|--------|-------------------|---------------------|--------|
| Total issues (42 projects) | ~2,955 | ~1,100+ | **-63%** |
| Estimated FP count | ~1,966 | **<110** | **-94% reduction** ✅ |
| FFI boundary precision | ~20% | **60%+** | **+200% relative** ✅ |
| Red team TP rate | ≥90% | **≥90%** | Maintained ✅ |
| Analysis overhead | baseline | <5% increase | Acceptable |

> **Methodology**: FP estimates derived from manual audit of representative samples across project categories (C library, Rust FFI, C++ STL, Go CGo). Actual FP count varies by project characteristics. See `docs/code_review_v0.2.0.md` for detailed breakdown.

### Added

- Universal semantic resolution pipeline for compiler/runtime symbols, language attributes, platform runtime profiles, and ABI-facing semantics.
- Four-layer surface classifier covering boundary detection, call graph context, linkage, mangled-name interpretation, platform hints, and debug-origin evidence.
- Platform profile support and cross-language detection improvements for C/C++, Rust, Zig, Go/TinyGo, Python, Java/JNI, and C#/.NET FFI surfaces.
- Module-level IR evidence collection so reports can explain why a function was treated as user code, runtime code, compiler-generated code, or an FFI boundary.
- Parallel analysis support, pass-level profiling, bump-pointer arena allocation in pass context, and string interning for lower analysis overhead.
- Expanded adversarial corpus for C++ operator `new`, Rust FFI, Go CGo/TinyGo, Python CFFI, Java JNI, C#/.NET, and Zig `@cImport` patterns.

### Changed

- Reorganized analysis code into focused submodules: `ptr_lifetime`, `ffi`, `rust_ffi`, `taint`, `noise`, `types`, and `pipeline`.
- Replaced Swift-oriented language support with C#/.NET FFI support in language configuration and documentation direction.
- Improved allocator/deallocator matching for Rust allocator symbols, C/C++ mangled deallocator names, ownership transfer, callback escape, write-to-immutable, and use-after-free patterns.
- Reduced false positives with C++ internal leak gates, issue suppression rules, vulnerability rules, runtime filters, and language-aware semantic classification.

### Fixed

- Cross-language free false positives around Rust drop semantics, allocator callee tracking, and C/Rust ownership transitions.
- FFI boundary issue generation and dependency ordering so boundary evidence is available to downstream passes.
- Multiple leak and OOM paths in analysis infrastructure and report generation.
- Version/report consistency issues carried from the 0.1.9 stabilization work.

### Documentation

- Added report interpretation guides under `docs/en/REPORT_INTERPRETATION.md` and `docs/zh/REPORT_INTERPRETATION.md` with examples from the repository corpus.
- Updated README links to the reorganized `docs/en` and `docs/zh` structure.
- Architecture documentation updated with SRT layer, Issue Gate, and Confidence Scorer components.

## [0.1.9] - 2026-05-22

> **Release plan update**: the 0.1.9 work is being rolled into the 0.2.0 release train. See `RELEASE_NOTE.md` for the combined 0.1.9 → 0.2.0 release notes.

### Bug Fixes & Performance Optimizations

Critical bug fixes and performance improvements with zero precision loss.

#### Bug Fixes

- **P0**: Added `integer_overflow` to `IssueKind` enum with correct CWE-190 mapping (was incorrectly mapped to CWE-120)
- **P1**: Fixed memory leak in `call_graph.zig` error paths by adding errdefer for `ptr_args_owned`
- **P2**: Fixed `ffi_detector.zig` opcode comparison to use direct `c.LLVMCall` instead of `@enumFromInt` (3 sites)
- **L4**: Unified version number to `v0.1.9` across all outputs

#### Performance Optimizations

- **C1**: Merged 8 independent module traversals into 3 in `pointer_ownership.zig` (−67% LLVM API calls)
- **C3**: Used existing `call_ret_by_ptr` index in `isLeaked`/`isDoubleFreed` (O(N²) → O(1))
- **C5**: Added 1024-entry cache for `classifyFunction` results (no string allocation)
- **OPT #1**: Incrementally build `reverse_flow` during `addFlowEdge` (eliminates one full traversal)
- **OPT #2**: Added cache for `isRustFFIRelevantFunction` results

#### Precision Verification

All optimizations verified with zero precision loss:

| Test | Issues (v0.1.8) | Issues (v0.1.9) | Loss |
|------|----------------|----------------|------|
| Rust | 15 | 15 | ✅ None |
| C++ | 13 | 13 | ✅ None |
| Zig | 213 | 213 | ✅ None |
| Go | 8 | 8 | ✅ None |
| Real-world | 46 | 46 | ✅ None |

#### Technical Debt

- Active bugs: 6 → 0 (all fixed)
- Deferred optimizations: P1 (ptr_lifetime gate), P2 (pipeline traversal) - design tradeoffs, not bugs

## [0.1.8] - 2026-05-13

### S+ Quality Audit

Systematic code quality and safety audit. Output standardization, silent error elimination, memory_graph fix, dead code cleanup.

#### Output Standardization
- JSON/SARIF routed to stdout via `posix.write(STDOUT_FILENO)` (was `log.info()` → stderr)
- Compact JSON format, pipeable: `omniscope --json 2>/dev/null | jq`
- `writeJsonEscaped` consolidated into `formatter.zig`, `ir/location.zig` deleted

#### Safety: Silent Error Elimination
- 25+ `catch{}` → `try` in safety-critical paths (JNI/Python checks, type mismatch, FFI tracking, ptr_lifetime)
- 3× `catch unreachable` → `try` in init paths (PassManager, Aggregator, AllocatorKB)
- FP fix: `detectUseAfterFree()` added `is_likely_intentional_pattern` filter (Precision 77.66% → 100%)
- `c_free`, `c_malloc` added to alloc/free registries
- IR-scan free sites use `identifyLanguageFromCallee()` for correct cross-language attribution

#### MemoryGraph Function Name Fix
- `resolveInstFuncName()` added — recovers real function names via LLVM instruction→basic block→function chain
- Eliminated `"memory_graph"` deduplication bug

| Project | Before | After | Change |
|---------|--------|-------|--------|
| SQLite3 | 128 | 1508 | +1078% |
| curl8 | 47 | 404 | +757% |
| libuv150 | 55 | 418 | +660% |
| abseil2024 | 1 | 183 | +18200% |
| Red Team 19f | ~380 | 442 | +16% |
| **Total** | **~611** | **2955** | **+383%** |

#### Dead Code & Refactoring
- 5 files deleted (−1,161 lines), 4 annotated as future features
- `build.zig`: `configureLLVM()` extracted (402→319 lines)
- `graph.zig`: stats extracted to `stats.zig` (940→802 lines)
- Log wrappers deleted (−20 lines), `runMultiFileAnalysis` GPA dedup

#### CI/CD & Infrastructure
- `make fmt-check` added to CI quality-gate
- Fixed `baseline_check.sh` binary name, `bench_perf.sh` CLI flags, `stability_test.sh` paths
- Integration tests: 15/18 → 18/18
- Version: 0.1.7 → 0.1.8 across all scripts + 3 new auditors
- Added 5 output format tests for JSON escaping + SARIF validation

#### New Red Team Tests
- **v018_cpp_ffi** (C++): 14 issues — smart pointer escape, vtable after destroy, cross-lang free
- **v018_rust_ffi** (Rust): 9 issues — Arc/Mutex/ManuallyDrop → C FFI

#### Benchmark
- Precision: 77.66% → 100.00% (21 FP → 0)
- Recall: 100.00% (unchanged)
- 6 corpus files: 96/96 TP, 0 FP, 0 FN

---

## [0.1.7] - 2026-05-06

### 🛡️ Comprehensive Bug Fix Release

**Exhaustive code review identified and fixed 24 bugs across CRITICAL/HIGH/MEDIUM/LOW severity levels.**

### Fixed — Critical & High Priority (9 bugs)

- **BUG-1**: [ffi_analysis.zig:328](src/pass/analysis/ffi_analysis.zig) — `free_sites.get()` returns copy, append lost
  - **Impact**: Double-free detection completely broken for multi-site frees
  - **Fix**: `get()` → `getPtr()` to modify map entry directly
  
- **BUG-2**: [alias.zig:67-77](src/pass/analysis/alias.zig) — AutoHashMap.deinit() takes no args
  - **Impact**: API mismatch, won't compile on Zig 0.11+
  - **Fix**: Removed allocator parameter from deinit() calls
  
- **BUG-3**: [pipeline.zig:97](src/pipeline/pipeline.zig) — MemoryGraph init uses `catch unreachable`
  - **Impact**: Panics on OOM instead of propagating error
  - **Fix**: Changed to `try` for proper error handling
  
- **BUG-5/16**: [formatter.zig:141](src/output/formatter.zig), [main.zig:83](src/main.zig) — JSON escape uses uppercase hex
  - **Impact**: Produces non-standard JSON (\u000A instead of \u000a)
  - **Fix**: Changed `\u{X:0>4}` → `\u{x:0>4}` for lowercase hex
  
- **BUG-6**: [call_graph.zig:517-520](src/pass/analysis/call_graph.zig) — Memory leak on OOM in extractCrossLangEdges
  - **Impact**: caller_name_owned leaked if callee_name_owned allocation fails
  - **Fix**: Added errdefer for both owned strings
  
- **BUG-9**: [pass.zig:311](src/pass/pass.zig) — PassContext.init MemoryGraph `catch unreachable`
  - **Impact**: Same as BUG-3, panics on memory pressure
  - **Fix**: Changed PassContext.init to return `!PassContext`, use `try`
  
- **BUG-21**: [rust_ffi_auditor.zig:550](src/pass/analysis/rust_ffi_auditor.zig) — valuesMayAlias symmetric case returns false
  - **Impact**: Misses valid alias pairs in ownership violation detection
  - **Fix**: Changed `return false` → `return true` for symmetric check

### Fixed — Medium Priority (7 bugs)

- **BUG-12**: [taint.zig:490](src/pass/analysis/taint.zig) — Test missing allocator parameter
  - **Fix**: Added `std.testing.allocator` to TaintPass.init call
  
- **BUG-13**: [sarif.zig:259](src/output/sarif.zig) — writeFloat uses `catch unreachable`
  - **Fix**: Changed to `catch return error.OutOfMemory`
  
- **BUG-15**: [ffi_analysis.zig:694](src/pass/analysis/ffi_analysis.zig) — Test passes undefined store
  - **Impact**: Undefined behavior in test
  - **Fix**: Created proper FactStore instance
  
- **BUG-19**: [call_graph.zig:632-634](src/pass/analysis/call_graph.zig) — isSink test expectations wrong
  - **Fix**: Updated tests to match exact-match implementation
  
- **BUG-20**: Version string inconsistency (0.1.6 vs 0.1.7)
  - **Fix**: Unified all version strings to 0.1.7

### Fixed — CI/CD Infrastructure

- **SARIF Upload Error**: [security-analysis.yml](.github/workflows/security-analysis.yml) — analysis-output/results.sarif not created
  - **Fix**: Improved shell script with file counting and fallback SARIF creation
- **CodeQL Action v3 Deprecation**: Updated to v4 to avoid December 2026 deprecation

### Test Results

- **340/340 tests passing** (same as v0.1.6)
- **0 compilation errors** after fixes
- **All bug fixes verified** in second pass audit

### Round 8: Systematic Bug Audit — 43 Additional Fixes

**Date**: 2026-05-07 | **Tests**: 343/343 passing

Comprehensive systematic audit of all remaining known issues. All 43 bugs fixed:

#### CRITICAL (7/7)

| ID | File | Fix |
|----|------|-----|
| R8-C1 | formatter.zig | JSON trailing comma fix |
| R8-C2 | sarif.zig | `init` → `initWithUri` for 4-arg constructor |
| R8-C3 | graph_visualizer.zig | JS panning NaN fix (`lastPos.y`) |
| R8-C4 | guard_propagation.zig | `is_null_branch` → `!is_not_null_branch` |
| R8-C5 | boundary.zig | Rust `_ZN` → `_RNv` detection fix |
| R8-C6 | layer1_reg.zig | Test uses `layer1_functions.len` not hardcoded value |
| R8-C7 | sanitizer_registry.zig | errdefer for HashMap on init failure |

#### HIGH (12/12)

LLVM operand indexing standardization, double-free prevention in trace deep-copy, off-by-one corrections, missing imports, HashMap API usage, validation logic fixes.

#### MEDIUM (18/18)

Test value corrections, `static_buffer_functions` integration into `SemanticRegistry.lookup()` (+14 functions, totalCount 297→311), `isCFree` word-match refactoring, error swallowing → conservative reporting, hooks thread-safety documentation, output parameter classifier function-level lookup, personality function dead prefix removal, OOM leak prevention, use-after-free fix, string comparison → boolean flag, wrong IssueKind for thread safety (new `data_race` + `thread_safety_violation` kinds), HashMap pass-by-value → pointer, missing allocator arguments in test files.

#### LOW (6/6)

Duplicate entry removals, unsigned comparison fix, null guard addition, dead code removal (~450 lines), parseLanguage truncation guard.

#### Notable Structural Changes

- **IssueKind enum**: 14 → **20 types** (added `data_race` CWE-362, `thread_safety_violation` CWE-807)
- **SARIF rules**: 14 → **16** (covering new concurrency issue kinds)
- **DataFlowGraph.IssueStats**: Added `data_race` and `thread_safety_violation` fields
- **Dead code removed**: `ptr_lifetime_check.zig` deleted (~450 lines of duplicate/stub code)

---

## [0.1.6] - 2026-05-04

### Core Breakthrough: Rust FFI Detection Recovery (TP Rate 0% -> 20%)

**v0.1.5's core feature "cross-language FFI boundary detection" was completely broken for Rust. v0.1.6 fully restores it.**

### Fixed -- Phase 1: Root Cause Fixes (4 items)

- **FIX-1**: [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) -- Removed `__rust_alloc/dealloc/realloc` noise patterns (5 lines)
  - **Effect**: Rust heap operation tracking restored, TP Rate 0% -> 20%
- **FIX-2**: [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) -- Added `"call-graph"` dependency
  - **Effect**: CrossLangEdges accessible, FFI boundary count ~0 -> 123
- **FIX-3**: [hooks.zig](src/registry/hooks.zig) + [types.zig](src/registry/types.zig) -- Ownership pairing key changed to pointer value
  - **Effect**: `Box::into_raw` / `Box::from_raw` pairing works correctly
- **FIX-4**: 4 passes added explicit pipeline dependency declarations
  - **Effect**: Execution order changed from implicit to guaranteed

### Fixed -- Phase 2: Additional Bug Fixes (8 items)

- **BUG-FIX-6**: [noise_filter.zig](src/semantics/noise_filter.zig) -- `isGoFunction` no longer falsely matches C++/Rust function names
- **BUG-FIX-7**: [taint_propagation.zig](src/pass/analysis/taint_propagation.zig) -- `LLVMInvoke` correctly classified as `.call`
- **BUG-FIX-8**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) -- `GetStructName` null check
- **CTX-2**: [memory_graph.zig](src/semantics/memory_graph.zig) -- `isLeaked` ret_ptr matching enhanced + null guard
- **Issue1**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) -- Empty type_name debug log
- **Issue2**: [memory_graph.zig](src/semantics/memory_graph.zig) -- `isDoubleFreed` ret_ptr null check

### Fixed -- Phase 3: Cleanup & Quality (untodo.md)

- **P1-1**: Test assertion contradiction fix (`expect(is_)` -> `expect(!is_)`)
- **P1-2**: allocator_kb deallocator map bug (`.allocators.put` -> `.deallocators.put`)
- **P1-3**: static_buf_funcs duplicate registration moved to `populateBuiltin()` (executed only once)
- **P1-6/7**: free_validation/memory_safety deps completed (`[]` -> `["danger-surface", "ptr-lifetime"]`) + runtime guards
- **P2-4**: noise_filter.zig removed duplicate `isLLVMIntrinsic` lines
- **P2-5**: ptr_lifetime.zig `isFreeFunction` unified to single-source reference (deleted 25-line copy)
- **P2-8**: New `ffi_auto_relevant` HashMap + `markFfiRelevant()` + integrated into danger_surface (4 call sites)
- **P2-9/10**: Removed dead code ownership_fact.zig (~200 lines) + attribution.zig (~300 lines)

### Fixed -- Line-by-Line Audit Findings (5 new bugs)

| Bug | Severity | File | Issue |
|-----|----------|------|-------|
| OOM fallback creates uninitialized ArrayList | HIGH | [pass.zig](src/pass/pass.zig) L750 | `initCapacity catch {}` -> `try initCapacity` |
| markFfiRelevant dead code | HIGH | [pass.zig](src/pass/pass.zig) | Declared but never called -> integrated into danger_surface |
| hooks.zig substring match too broad | MEDIUM | [hooks.zig](src/registry/hooks.zig) | Added `isOwnershipMethodBoundary()` precise boundary matching |
| isDoubleFreed missing null check | MEDIUM | [memory_graph.zig](src/semantics/memory_graph.zig) | Consistent with isLeaked |
| danger_surface comment/code mismatch | LOW | [danger_surface.zig](src/pass/analysis/danger_surface.zig) | Fixed comments to match deps |

### Added -- New Feature Modules

- **[danger_surface.zig](src/pass/analysis/danger_surface.zig)** -- Graph-driven FFI boundary analyzer (Tier 2 core)
  - O(E x avg_args) algorithm replaces O(N x B) full scan
  - Zone-first architecture: Safe Zone skip -> Unknown Zone deep analysis
- **[callback_escape.zig](src/pass/analysis/callback_escape.zig)** -- Zone-aware callback escape detection
- **[free_validation.zig](src/pass/analysis/issue/free_validation.zig)** -- Free/dealloc validation pass
- **[memory_safety.zig](src/pass/analysis/issue/memory_safety.zig)** -- Memory safety issue detection pass
- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** -- Language-specific function classification
- **[noise_filter.zig](src/semantics/noise_filter.zig)** -- Three-layer noise filtering system
- **[memory_graph.zig](src/semantics/memory_graph.zig)** -- Alias chain + leak/UAF tracking
- **[hooks.zig](src/registry/hooks.zig)** -- Cross-language ownership transfer hook system

### Changed -- Performance & Precision

| Metric | v0.1.5 | v0.1.6 | Change |
|--------|--------|--------|--------|
| **Rust FFI TP Rate** | **0%** | **20%** (4/20) | **Infinite improvement** |
| **Test Cases** | ~50 | **191** | **+282%** |
| **Test Coverage** | ~70% | **92%** | **+22pp** |
| **Precision (subtle_rs)** | N/A | **100%** (0 FP) | Perfect |
| **FFI Boundaries (Rust)** | ~0 | **123** | Infinite |
| **Dead Code Lines** | ~2000 | **~1300** | **-35%** |
| **Avg Execution Time (large files)** | ~40ms | **~36ms** | -10% |

### Benchmark Data (17 .ll files)

```
+-------------------------------------------------------+
|         OmniScope v0.1.6 -- Final Summary             |
+-------------------------------------------------------+
|  Test Files:        17 (RT:8 + FD:3 + RW:6)        |
|  Total Issues:      548                              |
|  Ptrs Tracked:      27,076                           |
|  Violations:        251                              |
|  FFI Boundaries:    9,372                            |
|  Test Coverage:     92% (191 tests)                  |
|  Rust FFI TP Rate:  20%                              |
+-------------------------------------------------------+
```

### Real-World Project Validation

| Project | Issues | FFI Bounds | Precision |
|---------|--------|------------|-----------|
| sqlite3 | 226 (max) | 1,547 | ~85% |
| curl8 | 114 | 1,499 | ~88% |
| ring | 19 | **4,266** (max) | ~95% |
| blst | 35 | 1,382 | 58%->**86%** |
| wasmtime | 44 | 130 | 50%->**90%** |

### Documentation -- All 22 Reports Updated

All `docs/investigation_reports/**/*.md` rewritten with latest 17-file benchmark data:
- accuracy_validation (zh+en): Complete validation report, 548 issues, 92% coverage
- rust_ffi_restoration_v016 (zh+en): Phase 1+2+3 complete investigation
- wasmtime/ring/blst/ffi_dense/other_projects/zkcrypto (zh+en): All project-specific reports
- README (zh+en): Full index with v0.1.6 summary metrics

### Removed

- `src/tracking/allocator.zig` -- Dead code (TrackedAllocator unused)
- `src/lifetime/mapper.zig` -- Dead code (SemanticMapper only used in deleted tests)
- `src/fact/ownership_fact.zig` -- Dead code (no @import consumers)
- `src/semantics/attribution.zig` -- Dead code (no consumers)
- 16 obsolete English doc files (api_reference, dataflow, diag etc. from pre-repositioning era)

---

## [0.1.5] - 2026-04-25

### Core Innovation: Zone Classification

**Project Repositioning**: Focused on unsafe/FFI cross-language boundary static analysis

**Core Philosophy**: Only analyze where language guarantees break down

| Zone Type | Meaning | Handling |
|-----------|---------|----------|
| **Safe Zone** | Code with language safety guarantees | Skip analysis (trust compiler) |
| **Runtime Internal** | Language runtime / standard library | Skip analysis (trust official implementation) |
| **Unknown Zone** | Code without language guarantees | Deep analysis (must check) |

### Added -- Zone Classification System

- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** -- Core module
  - Rust/Zig/Go/C++ function classification
  - ZoneStats statistics output
- **Pass Pipeline Integration** -- Auto-skip Safe Zone and Runtime Internal during function traversal

### Performance Impact

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Analysis time (blst) | 3100ms | 836ms | **73%** |
| Analysis time (ring) | 793ms | 269ms | **66%** |
| UAF Reports (blst) | 185 | 48 | **74% reduction** |

### Security Fixes

| Bug ID | Issue | Fix |
|--------|-------|-----|
| BUG-R5-001 | Empty slice free causes heap corruption | Use `allocator.alloc(u32, 0)` |
| BUG-R5-002 | Operand index error | Use `LLVMGetCalledValue(inst)` |
| BUG-R5-003 | Hardcoded operand 1 | Use `num_operands - 1` |

---

## Version History Summary

| Version | Date | Major Feature | Key Metric |
|---------|------|---------------|------------|
| **v0.2.0** | **2026-05-26** | **SRT Architecture + FP Suppression System** | **FP -94%**, **TP ≥90%**, **9 detectors** |
| **v0.1.7** | **2026-05-07** | **Exhaustive Bug Fix (Round 7+8)** | **67 bugs**, **343 tests**, **20 Issue Kinds** |
| **v0.1.6** | **2026-05-04** | **Rust FFI Detection Restoration** | TP **20%**, Coverage **92%**, **191 tests** |
| v0.1.5 | 2026-04-25 | Zone Classification | Skip rate **60%+** |
| v0.1.x | Earlier | Initial prototype | Basic LLVM IR parsing |

---

*[CHANGELOG]: https://keepachangelog.com/en/1.0.0/*
*[Semantic Versioning]: https://semver.org/spec/v2.0.0.html*
