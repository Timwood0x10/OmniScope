# OmniScope 0.2.0 Release Note

**Release train**: 0.1.9 → 0.2.0  
**Planned release date**: 2026-05-26  
**Status**: 0.1.9 is folded into 0.2.0 and is not planned as a separate public release.

## Summary

OmniScope 0.2.0 is the semantic-analysis release. It combines the 0.1.9 stabilization work with a larger refactor around semantic resolution, surface classification, platform runtime profiles, evidence collection, and cross-language FFI precision.

The main user-visible improvement is that findings should be easier to trust and explain: the analyzer has more context about why a symbol is a real FFI boundary, which runtime owns an allocation, and whether a report is likely user-code risk or compiler/runtime noise.

## Highlights

- **Semantic resolution**: new language/runtime/platform semantic model for compiler-generated symbols, ABI surfaces, allocator families, and FFI metadata.
- **Surface classification**: layered classification for boundary, call graph, linkage, mangled names, platform clues, and debug-origin evidence.
- **FFI precision**: improved C/Rust allocator matching, Rust Drop semantics, C++ deallocator names, callback escape, ownership transfer, and cross-language free handling.
- **Noise reduction**: stronger runtime filters, C++ internal leak gate, issue suppression, vulnerability rules, and language-aware classification.
- **Performance work**: parallel pipeline support, pass profiling, pass-context arena allocation, string interning, traversal reduction, and caching.
- **Corpus coverage**: expanded red-team cases for C++, Rust, Go/TinyGo, Python CFFI, Java JNI, C#/.NET, and Zig `@cImport`.

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

### Semantic engine

- Adds `semantic_resolver_pass` and semantic tree/profile components.
- Normalizes platform/runtime attributes before downstream analysis.
- Collects IR evidence used to justify boundary and ownership decisions.
- Distinguishes user code, compiler-generated code, runtime internals, and cross-language surfaces more explicitly.

### Surface classifier

- Adds boundary, call graph, debug-origin, linkage, mangled-name, and platform classifiers.
- Improves detection of real FFI surfaces while suppressing runtime/compiler implementation details.
- Provides the foundation for clearer report explanations and lower false positives.

### Analysis pipeline

- Reorganizes pointer lifetime, FFI, Rust FFI, taint, and noise analysis into smaller modules.
- Adds parallel analysis scaffolding and pass-level performance profiling.
- Moves common data structures into `src/types` to reduce coupling across passes.

### Language coverage

- Keeps focus on C/C++, Rust, Zig, Go/TinyGo, Python, and Java/JNI.
- Adds C#/.NET FFI direction and removes the previous Swift-oriented roadmap focus.
- Updates language configuration for runtime and compiler-reserved symbol handling.

## Compatibility

- **Input**: LLVM IR (`.ll`) and bitcode (`.bc`) remain the primary inputs.
- **Output**: text, JSON, and SARIF remain supported.
- **Breaking changes**: no intentional CLI-level breaking change is documented for this release.
- **Behavioral changes**: issue counts may differ from 0.1.8/0.1.9 because semantic classification suppresses more runtime/compiler noise and identifies more FFI-specific evidence.

## How to read reports

New report interpretation guides were added:

- English: `docs/en/REPORT_INTERPRETATION.md`
- 中文: `docs/zh/REPORT_INTERPRETATION.md`

Use these guides when triaging findings. They explain severity, confidence, CWE, function names, FFI boundary evidence, and how to map a report back to source examples in `examples/` and `corpus/red_team_test/`.

## Upgrade guidance

1. Rebuild OmniScope with the same Zig/LLVM toolchain used for 0.1.9 validation.
2. Re-run JSON or SARIF generation for CI baselines because issue counts and classifier explanations may change.
3. Prioritize `critical` and `high` findings with `HIGH` or `MEDIUM` confidence.
4. For FFI ownership findings, verify allocator/deallocator families before changing code.
5. Use SARIF for code scanning and JSON for automated diffing across release baselines.

## Known follow-ups

- Add deeper custom allocator models for project-specific APIs such as `sqlite3_malloc`/`sqlite3_free`.
- Extend TinyGo runtime filtering and JDK Unsafe/Panama FFM modeling.
- Continue improving report evidence so each issue includes a concise source-to-sink explanation.
