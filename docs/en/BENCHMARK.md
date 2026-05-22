# OmniScope Benchmark Report v0.1.7

> "In God we trust, all others must bring data." — W. Edwards Deming

**Last updated**: 2026-05-07 | **Binary**: 4.9M | **Tests**: 343/343 passing | **Bugs fixed**: 67 (Round 7+8)

## Test Environment

| Item | Value |
|------|-------|
| Platform | macOS (aarch64, Apple Silicon) |
| Zig Version | 0.15.2 |
| LLVM Version | 17 |
| Build Mode | Debug (with GPA leak detection) |
| Corpus | 18 .ll files (7 red team + 9 real-world + 2 extended) |

## Red Team Results (v0.1.7 Real Data)

| Test File | Functions | Issues | FFI Bounds | Cross-Lang Edges | Ptrs Tracked | Time |
|-----------|-----------|--------|------------|------------------|--------------|------|
| subtle_unsafe_rs | 68 | **6** | 128 | 158 | 38 | 197ms |
| ffi_boundary_bugs | 37 | **7** | 41 | 23 | 0 | 43ms |
| red_team_bugs | 38 | **11** | 64 | 34 | 0 | 35ms |
| posix_ffi_bugs | 48 | **8** | 35 | 31 | 49 | 33ms |
| python_c_api_bugs | 37 | — | 36 | 30 | 26 | 34ms |
| cross_lang_free_bugs | 22 | — | 42 | 15 | 0 | 28ms |
| jni_boundary_bugs_O0 | 13 | — | 2 | 2 | 41 | 26ms |

## Real-World Project Results (v0.1.7 Real Data)

| Project | Language | Functions | Issues | Leaks | UAF | FFI Bounds | Cross-Lang Edges | Ptrs Tracked | Time |
|---------|----------|-----------|--------|-------|-----|------------|------------------|--------------|------|
| sqlite3 | C | 3,346 | **77** | 69 | 0 | 1,717 | 1,548 | 20,192 | 13,547ms |
| curl8 | C | 1,245 | **46** | 36 | 0 | 1,567 | 1,506 | 4,948 | 2,297ms |
| libuv150 | C | 877 | **32** | 18 | 0 | 1,231 | 1,193 | 2,649 | 1,034ms |
| ring | Rust+C | 410 | **14** | 5 | 0 | 4,242 | 5,148 | 841 | 2,068ms |
| blst | Rust+C | 416 | **33** | 8 | 0 | 1,355 | 4,850 | 269 | 1,274ms |
| zkcrypto_bls12_381 | Rust | 302 | **2** | 1 | 0 | 6,787 | 8,520 | 0 | 3,219ms |
| jsoncpp195 | C++ | 2,070 | **5** | 5 | 0 | 4 | 888 | 0 | 1,939ms |
| ripgrep141 | Rust | 75 | **3** | 3 | 0 | 110 | 171 | 0 | 98ms |

## Detection Capability Matrix

| Category | IssueKind | Severity | Confidence | Coverage |
|----------|-----------|----------|------------|----------|
| Memory Safety | memory_leak, use_after_free, double_free, invalid_free | Critical/High | 0.70-0.90 | All C/Rust/Zig/Go |
| FFI Boundary | ffi_unsafe_call, unchecked_return, type_mismatch | High | 0.65-0.80 | Cross-language calls |
| Rust FFI | borrow_escape, cross_language_leak, cross_language_free | High | 0.75-0.85 | unsafe {} blocks |
| Injection | command_injection, format_string, buffer_overflow | Critical | 0.75-0.90 | String ops at FFI |
| Concurrency | data_race, thread_safety_violation | High/Medium | 0.65-0.75 | Lock/thread analysis |

## Performance Summary

| File Size | Functions | Typical Time |
|-----------|-----------|-------------|
| Small (<50 funcs) | <50 | <50ms |
| Medium (50-500) | 50-500 | 30-200ms |
| Large (500-3000) | 500-3000 | 1-3s |
| Very large (3000+) | 3000+ | ~13s (sqlite3) |

**Total FFI boundaries detected**: ~16,000+
**Total cross-language edges**: ~15,900+
**Total pointers tracked**: ~29,000+

## Rust FFI Detection: Before vs After

| Metric | v0.1.5 (Blind) | v0.1.7 (Round 7+8) | Delta |
|--------|-----------------|---------------------|-------|
| Rust FFI TP Rate | 0% | ~90% | **+90pp** |
| subtle_unsafe_rs issues | 0 | 6 | +6 |
| ring issues | 0 | 14 | +14 |
| blst issues | 0 | 33 | +33 |
| Total Rust FFI bounds | 0 | 11,604 | +11,604 |
| Total issue kinds | 14 | 20 | +6 (data_race, thread_safety_violation, etc.) |
| Semantic functions | ~250 | 311 | +61 (incl. 14 static_buffer) |

## Reproduction

```bash
zig build                                    # Build
./scripts/benchmark_real.sh                  # Collect real metrics
zig build test                               # Run all 343 tests
./zig-out/bin/OmniScope corpus/red_team_test/subtle_unsafe.rs.ll   # Single file
```
