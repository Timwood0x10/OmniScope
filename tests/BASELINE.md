# OmniScope FFI Test Baseline

Date: 2026-05-29

## Test Suites

Three inline-IR test suites covering cross-language FFI bug detection and noise filtering:

- `rust_ffi_inline_ir_test.zig` — 25 tests (14 bug, 11 noise)
- `gopyjava_ffi_inline_ir_test.zig` — 36 tests (27 bug, 7 noise, 2 unknown)
- `cscpp_ffi_inline_ir_test.zig` — 36 tests (17 bug, 12 noise, 7 unknown)

Total: 97 tests

## Current Results (pre-fix)

| Suite | Pass | Fail | Leak | Total |
|-------|------|------|------|-------|
| Rust FFI | 15 | 9 | 1 | 25 |
| Go/Python/Java | 26 | 9 | 1 | 36 |
| C#/C++/Zig | 22 | 8 | 6 | 36 |
| **Total** | **63** | **26** | **8** | **97** |

Pass rate: 64.9%

## Known Issues

### GlobalAllocTracker false positives
GlobalAllocTracker post-pass leak scan reports allocations as leaks even when correctly paired:
- `__rust_alloc` + `__rust_dealloc` → still reports "Found heap alloc: __rust_alloc"
- `malloc` + `free` → reports "Found heap alloc: malloc"

Affected noise tests:
- Rust: panic unwind, safe FFI, Box lifecycle, Arc lifecycle, HashMap, Mutex, Channel
- Go/Python/Java: correct _cgo_allocate/_cgo_free, correct INCREF/DECREF, correct buffer release, correct JNI local/global ref lifecycle
- C#/C++/Zig: correct COM pairing, correct C pair from Zig, __rust_alloc/__rust_dealloc same family

### Undetected bug patterns
- Alias escape with double write (no cross-allocator signal)
- inttoptr to raw pointer then free
- Some Go CGO cross-allocator patterns
- Some C#/Marshal patterns

### IR parse errors
- Test 32 (Java JNI): `constant expression type mismatch: got type '[3 x i8]' but expected '[2 x i8]'`

## Architecture

Tests use `analyzeIR()` helper that:
1. Writes inline IR to temp .ll file
2. Loads via `IRLoader.loadFile()` (auto llvm-as conversion)
3. Creates `Pipeline`, registers all 26 passes via `registerAllPasses()`
4. Sets module, runs pipeline
5. Returns `pipeline.getIssues().len`

Bug tests expect `issue_count > 0`, noise tests expect `issue_count == 0`.
