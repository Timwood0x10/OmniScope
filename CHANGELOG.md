# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- CLI flags: `--focus-user-code`, `--ffi-only`, `--include-stdlib`
- SARIF output with attribution grouping
- Performance optimization for large IR files (>100MB)
- Go CGO boundary detection
- Swift ARC (`retain`/`release`) integration
- WebAssembly FFI boundary analysis

---

## [0.4.1] - 2026-04-24

### Added — Phase 4: Cross-Language Noise Reduction Engine 🎉

**The biggest single improvement in OmniScope history.**

#### Core Features
- **Three-Layer Noise Filtering System** ([noise_reduction.zig](src/pass/analysis/noise_reduction.zig))
  - Layer 1: Name-based Filter (120+ patterns for Rust/Zig/C++)
  - Layer 2: Path/Debug Metadata Filter (LLVM DebugInfo API integration)
  - Layer 3: Behavior Filter (drop glue / allocator wrapper / STL grow detection)

- **FunctionOrigin Classification System**
  - New enum: `user`, `stdlib`, `compiler_generated`, `third_party`, `unknown`
  - RiskWeight system combining origin + severity (critical/high/medium/low/ignored)

- **Attribution Summary Output**
  - One-line format: `"X issues → Y user code (Z FFI HIGH)"`
  - Category breakdown with origin icons (✅📦📚🔧❓)

#### Zig FFI Support Enhancement
- **`isZigInternalFunction()`** — 40+ safe internal function patterns
- **`isZigSafeCImport()`** — 20+ known-safe libc bindings
- **`isZigFFIWorthReporting()`** — Comprehensive risk assessment
- Expanded pattern database: debug.Dwarf.*, posix.*, fs.File.*, OS abstraction layer

#### LLVM Integration
- Added `@cInclude("llvm-c/DebugInfo.h")` to [llvm_raw.zig](src/ir/llvm_raw.zig)
- New `extractDebugFilePath()` function for precise source file detection
- Safe memory access with bounds checking and null terminator validation

#### Test Infrastructure
- Three new Zig FFI test projects:
  - [zig_video_test.zig](corpus/test_cases/zig/zig_video_test.zig) — Video processing library simulation
  - [zgui_test.zig](corpus/test_cases/zig/zgui_test.zig) — GUI library simulation
  - [mach_core_test.zig](corpus/test_cases/zig/mach_core_test.zig) — Game engine simulation
- Comprehensive bilingual test report: [ZIG_FFI_TEST_REPORT.md](corpus/test_cases/ZIG_FFI_TEST_REPORT.md)

### Changed
- Updated [BASELINE.md](corpus/real_world/BASELINE.md) to v0.1.5 with all test results
- Updated [README.md](README.md) with v0.1.5 highlights and new project table
- Created [RELEASE_NOTES.md](RELEASE_NOTES.md) with detailed release documentation

### Performance Impact
| Project | Before | After | Reduction |
|---------|--------|-------|-----------|
| wasmtime (Rust) | 297 | **9** | **-97%** |
| zig_video (Zig) | 194 | **50** | **-74%** |
| zgui (Zig) | 168 | **24** | **-86%** |
| mach_core (Zig) | 211 | **67** | **-68%** |

### Security
- No security vulnerabilities introduced
- All existing security features maintained

### Fixed
- Fixed potential buffer overread in `indexOfPath()` with proper bounds checking
- Fixed null pointer dereference risk in `extractDebugFilePath()` with validation

---

## [0.4.0] - 2026-04-24 (Internal Release)

### Added — Phase 4 Initial Implementation
- Initial three-layer noise reduction architecture design
- FunctionOrigin and RiskWeight type definitions
- Basic name-based filter for Rust stdlib functions
- First successful test: wasmtime 297 → 9 issues

### Note
This was an internal development milestone, not publicly released.
Merged into v0.1.5 with enhancements.

---

## [0.3.3] - 2026-04-24

### Added — Phase 3 Complete
- **Cross-Language Type Compatibility** ([ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - Pointer/integer confusion detection at FFI boundaries
  - Integer size mismatch warning (i32 vs i64 ABI issues)
  - Type kind description helper (`describeLLVMType()`)

- **Lifetime Annotation Inference** ([ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - Return value lifetime classification (static/owned/borrowed)
  - Dangling pointer detection (alloca passed to FFI)
  - Parameter lifetime validation (NULL safety, inttoptr risk)
  - Nullable parameter recognition per function semantics

- **Rust Drop Glue Filter** ([cpp_fp_reduction.zig](src/pass/analysis/cpp_fp_reduction.zig))
  - `isRustDropGlue()` eliminates UAF reports in destructor glue
  - Covers mangled forms: `_ZN4core3ptr13drop_in_place`, etc.

### Changed
- Updated BASELINE.md to v0.1.5
- wasmtime: 355 → 297 issues (-16%) from drop_in_place filtering

---

## [0.3.2] - 2026-04-24

### Added — Phase 3 #2: Type Compatibility
- Initial implementation of cross-language type mismatch detection
- Fixed LLVM API compatibility errors (`LLVMGetParamType` → `LLVMGetParam` + `LLVMTypeOf`)
- Fixed `LLVMGetType` → `LLVMTypeOf` throughout codebase

---

## [0.3.1] - 2026-04-23

### Added — P1 Phase 2 Complete
- **API Contract Validation** ([ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - NULL guard check via forward BB scanning
  - Unbounded buffer operation warning
  - Ownership chain tracking

- **Sink Context Sensitivity** ([ffi_unsafe.zig](src/pass/analysis/issue/ffi_unsafe.zig) + [ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - Safe caller filtering for fprintf/sprintf
  - Confidence adjustment for diagnostic functions

- **Taint Source Enhancement** ([taint.zig](src/pass/analysis/taint.zig))
  - Expanded from 15 to 35+ taint sources
  - New sources: argv, accept(), dlsym(), mmap(), shmat(), getline(), fgetws()

- **SQLite IR Recompilation**
  - Recompiled with `-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_SESSION`
  - Result: 43MB / 753K lines / 3346 functions (up from 35MB / 2657 functions)

### Changed
- Updated BASELINE.md to v0.1.5
- SQLite: 1 → 0 issues (FTS5/RTREE recompilation)
- libuv: 6 → 3 issues (sink context sensitivity)
- libcurl: 1 → 0 issues (format string FP elimination)

---

## [0.3.0] - 2026-04-23

### Added — P0 Milestone Complete
- **BB-Aware Double-Free Detection** (P0-B)
  - Same-BB = real bug (HIGH confidence)
  - Different-BB = multi-path cleanup path (skip)

- **Rust FFI Relevance Filter** (P0-C)
  - `isRustFFIRelevantFunction()` filters non-extern-calling Rust functions
  - Based on [rust_ffi_filter.md](plan/rust_ffi_filter.md) classification standard

- **B-class Cleanup**
  - Reduced noise from low-confidence detections

### Changed
- wasmtime: 4023 → 357 issues (-91% from initial)
- SQLite/libcurl/libuv: significant FP reduction

---

## [0.2.1] - 2026-04-23

### Added — TP/FP Separation
- Source-level verification framework
- Mangled name filter for Rust compiler-generated symbols
- Ownership transfer recognition (into_raw/from_raw patterns)
- Red Team Test Suite: 17 intentionally injected bugs

### Changed
- wasmtime: 4023 → 357 issues (initial major FP reduction)

---

## [0.2.0] - 2026-04-23

### Added — Enhanced Detection Capabilities
- Double-Free Detection with BFS alias analysis
- Loop-Leak Detection heuristic (≥3 allocs without frees)
- Format String Vulnerability classification
- exec* family coverage (12 dangerous functions)

---

## [0.1.5] - 2026-04-22

### Security Audit Fixes
- Fixed 30+ bugs found during internal audit
- Changed substring matching to exact matching for function names

---

## [0.1.4] - 2026-04-22

### Added — Phase 3 Optimizations
- Ownership transfer inference
- Null guard dominance analysis
- C++ RAII awareness improvements

---

## [0.1.3] - 2026-04-21

### Added — Initial Baseline Creation
- Real-world corpus testing framework
- Baseline metrics for 5 production projects
- Regression guard system

---

## Version History Summary

| Version | Date | Major Feature | Key Metric |
|---------|------|---------------|------------|
| **v0.1.5** | 2026-04-24 | **Phase 4 Noise Reduction** | wasmtime: **9** (-99.8%) |
| v0.1.5 | 2026-04-24 | Phase 3 Complete | wasmtime: 297 |
| v0.1.5 | 2026-04-23 | P1 Phase 2 | wasmtime: 297 |
| v0.1.5 | 2026-04-23 | P0 Milestone | wasmtime: 355 |
| v0.1.5 | 2026-04-23 | TP/FP Separation | wasmtime: 357 |
| v0.1.5 | 2026-04-23 | Enhanced Detection | wasmtime: 4023 |

---

*[CHANGELOG]: https://keepachangelog.com/en/1.0.0/*
*[Semantic Versioning]: https://semver.org/spec/v2.0.0.html*
