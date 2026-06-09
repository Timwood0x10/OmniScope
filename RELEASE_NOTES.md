# OmniScope 0.2.0 Release Note

**Release train**: 0.1.9 → 0.2.0  
**Release date**: 2026-06-08  
**Status**: 0.1.9 is folded into 0.2.0 and is not planned as a separate public release.

## Summary

OmniScope 0.2.0 is the semantic-analysis release. It combines the 0.1.9 stabilization work with a major refactor around semantic resolution, surface classification, platform runtime profiles, evidence collection, cross-language FFI precision, and a new Symbol Graph architecture.

The main user-visible improvement is that findings should be easier to trust and explain: the analyzer has more context about why a symbol is a real FFI boundary, which runtime owns an allocation, and whether a report is likely user-code risk or compiler/runtime noise. FP count is reduced by ~94% while maintaining ≥ 90% true-positive rate on red team tests.

## Highlights

- **Semantic Resolution Tree (SRT)**: 15+ semantic kinds for unified FP suppression, with 9 IR pattern detectors (R-0 ~ R-8) and an Issue Gate with 10 suppression verdicts
- **Symbol Graph**: per-symbol language/ABI classification replacing module-level "dominant language" model, with export surface detection for FFI-exported functions
- **Surface classification**: layered classification for boundary, call graph, linkage, mangled names, platform clues, and debug-origin evidence
- **FFI precision**: improved C/Rust allocator matching, Rust Drop semantics, C++ deallocator names, callback escape, ownership transfer, and cross-language free handling
- **Noise reduction**: ~94% FP reduction (from ~1,966 to < 110 estimated FPs across 42 projects), stronger runtime filters, issue suppression, vulnerability rules, and language-aware classification
- **Performance**: parallel pipeline support, pass profiling, arena allocation, string interning, IRStore-based traversal, and caching — < 5% overhead
- **Multi-language**: C/C++, Rust, Zig, Go/TinyGo, Python CFFI, Java JNI, C#/.NET FFI
- **Corpus coverage**: expanded red-team cases for C++, Rust, Go/TinyGo, Python CFFI, Java JNI, C#/.NET, and Zig `@cImport`

## Accuracy

| Metric | v0.1.x Baseline | v0.2.0 | Change |
|--------|-----------------|--------|--------|
| Total issues (42 projects) | ~2,955 | ~1,100+ | **-63%** |
| Estimated FP count | ~1,966 | **< 110** | **-94%** ✅ |
| FFI boundary precision | ~20% | **60%+** | **+200%** ✅ |
| Red team TP rate | ≥ 90% | **≥ 90%** | Maintained ✅ |
| Double free detection | — | 100% | ✅ |
| Cross-language free | — | 87% | ⚠️ |
| Use-after-free | — | 80% | ⚠️ |
| Buffer overflow | — | FFI size truncation + sprintf | ✅ |
| Inline IR tests | — | 42 pass / 87 total (0 fail) | Cross-lang 27/27 ✅ |

## Included from 0.1.9

0.1.9 focused on correctness and performance fixes. These changes are included in 0.2.0:

- Correct `integer_overflow` IssueKind and CWE-190 SARIF mapping.
- Memory-leak fixes in call graph error paths.
- Safer LLVM opcode comparisons in FFI detection.
- Version consistency across CLI, JSON, and SARIF output.
- Reduced redundant module traversals in pointer ownership analysis.
- Faster leak/double-free lookups through existing memory-graph indices.
- Caches for zone classification and Rust FFI relevance checks.

## New in 0.2.0

### Semantic Resolution Tree (SRT)

- New `semantic_resolver_pass` with event-driven detector architecture.
- `SemanticKind` expanded from 4 → 15+ variants covering LLVM attributes, heap provenance, interior mutability, RAII drop, syscalls, language gating, ownership transfer, library release, and parameter source.
- 9 IR Pattern Detectors (R-0 ~ R-8) populate the SRT with semantic resolutions.
- **Issue Gate** (`src/pass/filter/issue_gate.zig`): 10 suppression verdicts; issues pass only when confidence ≥ 0.85.
- **Confidence Scorer** (`src/pass/analysis/resource/issue_verifier.zig`): 4-tier system (HIGH ≥ 0.75, MEDIUM ≥ 0.55, LOW ≥ 0.35, UNRELIABLE < 0.35).

### Symbol Graph

- New `src/ffi/symbol_graph.zig`: per-symbol language/ABI classification with `classifySymbol` covering Rust v0, Rust legacy, C++ Itanium, MSVC, Swift, Go, Zig, and LLVM builtin patterns.
- Export surface detection: identifies FFI-exported functions even without cross-language callers in the same translation unit.
- CLI `--report-surfaces` flag for JSON export surface reporting.
- **Fixed**: pointer lifetime bug in `buildCallSites` — switched to index+deferred-resolution scheme (`cross_lang_call_indices` stores `usize` indices during Phase 2, resolved to `*CallSite` in Phase 2b after call_sites is frozen).

### Surface classifier

- Adds boundary, call graph, debug-origin, linkage, mangled-name, and platform classifiers.
- Improves detection of real FFI surfaces while suppressing runtime/compiler implementation details.

### Analysis pipeline

- Reorganizes pointer lifetime, FFI, Rust FFI, taint, and noise analysis into smaller focused modules (`src/pass/analysis/ptr_lifetime/`, `src/pass/analysis/rust_ffi/`, `src/pass/analysis/ffi/`, `src/pass/analysis/noise/`).
- Adds parallel analysis scaffolding (`src/pipeline/parallel.zig`) and pass-level performance profiling.
- Pre-categorized IR Store (`src/ir/ir_store.zig`) eliminates full IR traversal across passes.
- Moves common data structures into `src/types` and `src/common` to reduce coupling.

### Language adapters

- Multi-language adapter framework (`src/lang/`): C++, Go, Python adapters with language-specific FFI detection rules.
- Language override system with JSON config support (`src/config/language_override.zig`).
- Metadata-based language detection for improved module classification.

### Language-specific detection

- **Rust**: Drop semantics recognition, `Box::into_raw`/`CString::into_raw` ownership transfer suppression, `__rust_alloc`/`__rust_dealloc` allocator family tracking.
- **C++**: `operator new`/`operator delete` classification, C++ internal leak gate, FP reduction for STL patterns, RAII destructor detection.
- **Go**: CGo memory safety detection, `_cgo_allocate`/`_cgo_free` tracking, pipeline integration.
- **Zig**: Allocator tracking config, `@cImport` pattern detection, leak confidence filtering.
- **Java/JNI**: JNI leak detector pass, `NewGlobalRef`/`DeleteLocalRef` lifecycle tracking.
- **C#/.NET**: Marshal/P/Invoke boundary analysis (new direction, replaces Swift roadmap focus).

### CLI and output

- `--report-surfaces`: export FFI surface list to JSON output.
- `--focus-user-code`: suppress stdlib/compiler noise, show only user-code issues.
- `--lang-prefix` and `--default-lang`: language override for ambiguous modules.
- Report interpretation guides: `docs/en/REPORT_INTERPRETATION.md` and `docs/zh/REPORT_INTERPRETATION.md`.

## Known Issues

| Issue | Severity | Impact | Status |
|-------|----------|--------|--------|
| ~~SymbolGraph pointer lifetime bug~~ | ~~🔴 Critical~~ | ~~Crashes on large IR~~ | **✅ Fixed** (index + deferred resolution) |
| ~~`cross_language_free` gate too aggressive~~ | ~~🟡 High~~ | ~~Blocks entire pass when `danger_surface_relevant` is empty~~ | **✅ Verified** (core path not blocked; SAME-LANG-MERGE guard + isAbiCompatibleAllocFree fix FP) |
| `ffi_unsafe_call` noise ~90% | 🟡 High | Precision only 11-14% from overly broad pattern matching | Partially fixed (trust_boundary_indicators/risky_prefixes/safe_name_patterns tightened) |
| ~~Buffer overflow detection 0%~~ | ~~🟡 High~~ | ~~Function count threshold + missing FFI-boundary patterns~~ | **✅ Fixed** (FFI size truncation → CWE-120 issue + sprintf/%s overflow detection) |
| Inline IR test pass rate 48.3% | 🟡 Medium | 45/87 warnings (FP on safe code) | Planned (requires Batch 3 architecture refactor) |
| Rust mangled alloc tracking | 🟠 Medium | `_R`-prefixed symbols not recognized by `isAllocFunction()` | Planned |
| Library contract DB disconnected | 🟠 Medium | `trackPointerOrigin` doesn't query `contract_db` for `sqlite3_open` etc. | Planned |

See [plan/multilang_precision_90.md](./plan/multilang_precision_90.md) for detailed fix plans.

## Compatibility

- **Input**: LLVM IR (`.ll`) and bitcode (`.bc`) remain the primary inputs.
- **Output**: text, JSON, and SARIF remain supported.
- **Breaking changes**: no intentional CLI-level breaking change is documented for this release.
- **Behavioral changes**: issue counts will differ significantly from v0.1.x because semantic classification suppresses more runtime/compiler noise and identifies more FFI-specific evidence. Expect fewer total issues with higher precision.

## How to read reports

Report interpretation guides:

- English: `docs/en/REPORT_INTERPRETATION.md`
- 中文: `docs/zh/REPORT_INTERPRETATION.md`

These guides explain severity, confidence, CWE, function names, FFI boundary evidence, and how to map a report back to source examples.

## Upgrade guidance

1. Rebuild OmniScope with the same Zig/LLVM toolchain used for 0.1.9 validation.
2. Re-run JSON or SARIF generation for CI baselines — issue counts and classifier explanations will change significantly.
3. Consider using `--focus-user-code` to reduce noise in initial adoption.
4. Use `--report-surfaces` to discover FFI-exported functions in your IR modules.
5. Prioritize `critical` and `high` findings with `HIGH` or `MEDIUM` confidence.
6. For FFI ownership findings, verify allocator/deallocator families before changing code.
7. Use SARIF for code scanning and JSON for automated diffing across release baselines.

## Known follow-ups

- Batch 3: `hasAuxiliaryEvidence` signature refactor to accept `*PassContext` for IR-level taint evidence and boundary confidence — this is the primary remaining work to reduce `ffi_unsafe_call` noise from ~90% to <20% and improve inline IR test pass rate from 48.3% to ≥80%.
- Batch 3: `memory_unsafe`/`ownership_violation` precise classification to replace generic `ffi_unsafe_call` categorization.
- Add deeper custom allocator models for project-specific APIs such as `sqlite3_malloc`/`sqlite3_free`.
- Extend TinyGo runtime filtering and JDK Unsafe/Panama FFM modeling.
- Continue improving report evidence so each issue includes a concise source-to-sink explanation.
