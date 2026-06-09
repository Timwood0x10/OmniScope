# OmniScope 0.2.0 Release Notes

**Release train**: 0.1.9 -> 0.2.0
**Release date**: 2026-06-09
**Status**: Ready for 0.2.0 release candidate review.

## Summary

OmniScope 0.2.0 is the semantic-analysis and multi-language FFI release. Compared with `master`, this branch replaces the older module-level FFI heuristics with a broader pipeline built around semantic resolution, surface classification, resource contracts, language overrides, Symbol Graph export surfaces, and a larger test/corpus matrix.

The release keeps the public input/output model simple: LLVM IR in, text/JSON/SARIF reports out. Internally, the analyzer now has more context about which runtime owns a pointer, which symbols are true FFI boundaries, and which findings are likely user-code risks versus runtime/compiler noise.

## Highlights

- **Semantic resolution**: adds a Semantic Resolution Tree, pattern detectors, platform/runtime profiles, and an Issue Gate for evidence-based suppression.
- **Surface and Symbol Graph classification**: classifies boundary, linkage, mangled-name, debug-origin, call-graph, ABI, and export-surface evidence per symbol.
- **Resource and ownership analysis**: adds resource families, function summaries, transfer inference, candidate building, and issue verification.
- **Multi-language FFI support**: expands C/C++, Rust, Zig, Go/TinyGo, Java/JNI, Python C API/CFFI, and C#/.NET handling.
- **New FFI checks**: adds ABI compatibility, type mismatch, layout mismatch, string safety, unwind boundary, callback lifecycle, GC safety, JNI leak, and cross-language dataflow passes.
- **CLI and config**: adds JSON config loading/generation, language overrides, surface reporting, focus-user-code filtering, leak thresholds, Zig allocator tracking, and per-pass performance stats.
- **Performance infrastructure**: adds IRStore, instruction cache, traversal indexing, arenas, string interning, prefix tries, Aho-Corasick matching, and parallel pipeline scaffolding.
- **Docs and tests**: reorganizes docs into `docs/en` and `docs/zh`, adds `docs/touser`, and expands inline/cross-language integration tests.

## User-Visible Changes

### CLI

New or expanded flags:

- `--json`, `--sarif`, `-o/--output <file>` for report output.
- `--visualize` / `--viz` for HTML issue graphs.
- `--focus-user-code`, `--no-focus-user-code`, `--include-stdlib` for noise control.
- `--ffi-only`, `--boundary-only`, `--show-surface <boundary|ffi|reachable|internal|runtime>` for report scope.
- `--min-severity <low|medium|high|critical>` for severity filtering.
- `--leak-threshold <0.0-1.0>` and `--no-zig-tracking` for leak tuning.
- `--lang`, `--lang-prefix`, `--lang-suffix`, `--source-lang`, `--default-lang` for language override.
- `--report-surfaces` to include FFI-visible export surfaces in JSON.
- `--perf-stats`, `--perf-json <path>` for pass-level profiling.
- `--config <file>`, `--init-config` for JSON configuration.

### Output

- Text, JSON, and SARIF remain supported.
- JSON can include export-surface details when `--report-surfaces` is enabled.
- Reports now use stronger filtering and deduplication, so issue counts are expected to differ from v0.1.x baselines.

## Major Technical Changes

### Pipeline and Passes

- Adds centralized pass registration in `src/pipeline_registration.zig`.
- Splits large analysis code into focused modules under `src/pass/analysis/{ffi,ptr_lifetime,rust_ffi,noise,resource,taint}`.
- Adds `PassContext` implementation, dependency resolution, graceful pass failure handling, and optional pass profiling.
- Adds foundation and analysis passes for CFG, DFG, alias, call graph, surface classification, semantic resolution, pointer flow, pointer lifetime, FFI boundary, ABI/type/layout/string/unwind checks, memory safety, free validation, callbacks, locks, GC, JNI, and Rust FFI.

### Semantic and Resource Model

- Adds semantic tree/resolution engine and pattern detectors for attributes, heap provenance, interior mutability, drop glue, language detection, ownership transfer, and library allocation pairs.
- Adds platform/runtime normalization, language-specific zone detectors, and allocator knowledge bases.
- Adds resource families, resource contracts, summaries, ownership state, transfer inference, escape modeling, and issue candidate verification.

### Language Support

- Adds adapter framework under `src/lang/` with C++, Go, and Python adapters.
- Adds config files for C, C++, Rust, Zig, Go, Java, and Python language behavior.
- Adds language override registry and config support for ambiguous IR.
- Adds JNI, Go CGo/TinyGo, Zig allocator, Rust FFI, C#/.NET, Python C API/CFFI, C++ allocator/deallocator, and layout/ABI checks.

### Documentation

- README and README_zh now include concise architecture/data-flow diagrams, pass responsibilities, CLI reference, and `docs/touser` links.
- English docs live under `docs/en/`; Chinese docs live under `docs/zh/`.
- `docs/touser/en/ToUser.md` and `docs/touser/zh/ToUser.md` explain the user problem OmniScope targets.

## Compatibility

- **Input**: LLVM `.ll` and `.bc`.
- **Output**: text, JSON, SARIF, optional HTML visualization.
- **Version**: CLI and output code report `0.2.0`.
- **Expected behavior change**: issue volume and classification can change significantly because 0.2.0 uses new semantic, surface, and language-aware gates.

## Upgrade Guidance

1. Rebuild with the project toolchain: Zig >= `0.15.2` and LLVM 22.
2. Re-run JSON/SARIF baselines; do not assume v0.1.x issue counts are comparable.
3. Start with `--focus-user-code --boundary-only --min-severity high` for a precise first pass.
4. Use `--report-surfaces --json` to inspect exported FFI surfaces.
5. Use language overrides when IR lacks reliable source or mangling metadata.

## Verification Pointers

Useful commands before tagging:

```bash
zig build
zig build test
make check
make test
```

The branch also adds inline IR tests, cross-language integration fixtures, golden baseline docs, corpus verification scripts, and CI workflow coverage.

## Known Follow-Ups

- Continue reducing `ffi_unsafe` noise with stronger auxiliary evidence.
- Expand project-specific allocator contract coverage beyond the bundled registry.
- Improve report evidence paths for each issue so findings are easier to audit from source to sink.
- Keep shrinking large analysis modules and generated corpus artifacts where practical.
