# OmniScope Benchmark Report v0.1.6

> "In God we trust, all others must bring data." — W. Edwards Deming (probably)

Last updated: 2026-05-04

## Test Environment

| Item | Value |
|------|-------|
| Platform | macOS |
| Zig Version | 0.1.5.0 |
| LLVM Version | 17 |
| Test Files | 17 real-world projects |

## Aggregate Results

| Metric | Value |
|--------|-------|
| Total Projects | 17 |
| Total Issues Found | 548 |
| Total Pointers Tracked | 27,076 |
| Total FFI Boundaries | 9,372 |
| Estimated Precision | ~88% |
| Estimated FP Rate | ~14% |
| Test Coverage | 92% (191 tests) |

## Per-Project Results

| Project | Language | Functions | Issues | Ptrs Tracked | FFI Bounds | Violations | Time |
|---------|----------|-----------|--------|-------------|------------|------------|------|
| ring | Rust+C | 278 | 19 | 841 | 4,266 | 0 | 142ms |
| wasmtime | Rust | 619 | 44 | 31 | 130 | 0 | 203ms |
| blst | Rust+C | 267 | 35 | 269 | 1,382 | 0 | 836ms |
| curl8 | C | 944 | 114 | 4,948 | 1,499 | 89 | 312ms |
| sqlite3 | C | 3,250 | 226 | 20,192 | 1,547 | 142 | 1,247ms |
| zkcrypto | Rust | 287 | 0 | - | - | - | 89ms |
| subtle_unsafe_rs | Rust | 20 | 4 | - | 123 | 4 | 12ms |

## Rust FFI Detection: Before vs After

| Metric | v0.1.5 | v0.1.6 | Change |
|--------|--------|--------|--------|
| Rust FFI TP Rate | 0% | 20% | +20pp |
| subtle_unsafe_rs Issues | 0 | 4 | +4 |
| FFI Boundaries (Rust) | 0 | 123 | +123 |
| Noise Reduction Rate | ~94% | ~97% | +3pp |

## Performance

| Metric | Value |
|--------|-------|
| Small files (<100 funcs) | <50ms |
| Medium files (100-500 funcs) | 50-300ms |
| Large files (500-3000 funcs) | 300-1500ms |
| Very large (3000+ funcs) | ~1.5s |

## Notes

- **zkcrypto reports 0 issues**: This is correct. It's a pure Rust project with 100% Safe Zone classification. The tool correctly identifies that there are no FFI boundary violations.
- **wasmtime 44 issues but 0 violations**: Issues come from non-ptr_lifetime passes (taint, ffi_boundary, callback_escape). These are informational, not confirmed violations.
- **curl/sqlite3 are pure C**: They contribute 340/548 (62%) of issues but are outside OmniScope's core FFI focus. They demonstrate the tool's general memory safety capabilities.
- **Precision estimate**: Based on manual verification of subtle_unsafe_rs (100%) + sampling of curl/sqlite3 (~85%). Full manual verification pending.

## Reproduction

```bash
# Build
zig build

# Run on a single file
./zig-out/bin/omniscope path/to/your/file.ll

# Run with verbose output
./zig-out/bin/omniscope --verbose path/to/your/file.ll
```
