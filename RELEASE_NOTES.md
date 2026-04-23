# OmniScope v0.1.4

## Cross-Language FFI & Memory Safety Static Analyzer — C/C++ Production Release

### What's New

**C++ Support (7-Layer FP Reduction + RC Container Detection)**

- **L1-L7**: Complete C++ false positive elimination system:
  - STL internal function filter (`_ZNSt*`, `__gnu*`)
  - C++ special member function filter (ctor/dtor/copy-assign/move-assign)
  - RAII smart pointer detection (`unique_ptr`/`shared_ptr`)
  - RAII function set tracking (42 funcs in jsoncpp skipped)
  - C++ ABI runtime filter (`__cxa_*` exception/guard/atexit)
  - Meyers singleton detection (`__cxa_guard_acquire`)
  - C++ operator FFI filter + STL caller filter
- **L8**: Reference-counted container detection (NEW):
  - Detects `Ref()`/`Unref()`/`AddRef()`/`Release()` patterns
  - Name-based heuristic for Cord/RC container classes
  - Eliminates FP leaks from `absl::Cord`, `std::shared_ptr`, etc.

**Real-World Project Validation (5 projects, 5,180 functions)**

| Project | Language | Functions | Issues | Leaks | Time |
|---------|----------|-----------|--------|-------|------|
| SQLite 3.47.2 | C | 3,237 | **8** | **0** | 5.8s |
| libcurl 8.14.0 | C | 68 | **1** | **0** | 0.05s |
| libuv 1.50.0 | C | 145 | **1** | **0** | 0.07s |
| jsoncpp 1.9.5 | C++ | 1,537 | **3** | **0** | 1.4s |
| abseil-cpp 2024 | C++ | 193 | **0** | **0** | 0.37s |

**Key Results vs v0.1.3**

| Metric | v0.1.3 | v0.1.4 | Change |
|--------|--------|---------|--------|
| C++ leak detection | N/A | **100% elimination** (jsoncpp 37→0) | New |
| RC container support | N/A | Cord/RC FP eliminated (abseil 9→0) | New |
| Total real-world issues | 42 | **13** (-69%) | Improved |
| Real memory leaks (5 projects) | ? | **0** | ✅ |
| Analysis passes | 9 | **15** (+6 new) | Enhanced |

### Changes

#### C++ Analysis Engine
- Itanium C++ ABI mangled name support (`_Znwm`, `_Znam`, `_ZdlPv`, `_ZdaPv`)
- LLVM `invoke` instruction handling (C++ exception safety)
- GEP+store struct-member ownership detection
- Return-value/output-param ownership transfer (reverse flow graph)

#### Confidence Grading
- 4-level confidence system: HIGH / MEDIUM / HEURISTIC / EXPERIMENTAL
- All output formats: Text, JSON, SARIF include confidence metadata

#### Bug Fixes
- LLVM iteration loop safety (29 occurrences, null-pointer guard)
- Vulnerability ID collision (atomic counter)
- RAII/Meyers error handling (silent `catch {}` → `warn` logging)
- `classifyAllocation()` / `identifyLanguageFromCallee()` now handle `LLVMInvoke`

### Supported Platforms

- **macOS**: LLVM 22 (Apple M-series)
- **Linux**: LLVM 18+
- **Compiler**: Zig 0.15.2+

### Known Limitations

- Reference-counted containers beyond Cord (e.g., Qt's QSharedData) may need additional patterns
- Cross-language FFI enhancement (Python↔C, Rust↔C++, Go↔C) planned for next release
