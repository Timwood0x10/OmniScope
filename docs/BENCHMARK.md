# OmniScope Benchmark Report v0.1.8

> "In God we trust, all others must bring data." — W. Edwards Deming (probably)

Last updated: 2026-05-06 (real benchmark data)

## Test Environment

| Item | Value |
|------|-------|
| Platform | macOS (aarch64) |
| Zig Version | 0.15.2 |
| LLVM Version | 17 |
| Test Files | 17 real-world + 7 red team |

## Per-Project Results (v0.1.8 Real Data)

| Project | Language | Functions | Issues | Leaks | UAF | FFI Bounds | Time |
|---------|----------|-----------|--------|-------|-----|------------|------|
| sqlite3 | C | 3,346 | 77 | 69 | 0 | 1,717 | 13,122ms |
| curl8 | C | 1,245 | 46 | 36 | 0 | 1,567 | 2,172ms |
| wasmtime | Rust | 987 | 45 | 1 | 0 | 129 | 1,481ms |
| libuv150 | C | 877 | 32 | 18 | 0 | 1,231 | 1,000ms |
| gnark_test | Go | 916 | 3 | 1 | 1 | 5,221 | 2,289ms |
| jsoncpp195 | C++ | 2,070 | 5 | 5 | 0 | 482 | 2,937ms |
| abseil2024 | C++ | 1,124 | 1 | 1 | 0 | 422 | 1,722ms |
| blst | Rust+C | 416 | 33 | 8 | 0 | 1,446 | 1,242ms |
| ring | Rust+C | 410 | 14 | 5 | 0 | 4,252 | 1,956ms |
| zkcrypto_bls12_381 | Rust | 302 | 2 | 1 | 0 | 6,787 | 3,058ms |
| ripgrep141 | Rust | 75 | 3 | 3 | 0 | 110 | 95ms |
| rust_sqlite | Rust+C | 51 | 14 | 6 | 7 | 230 | 144ms |
| ark_ff | Rust | 36 | 1 | 1 | 0 | 55 | 45ms |
| wabt_wast2json | C++ | 558 | 2 | 2 | 0 | 40 | 481ms |
| openssl_wrapper | C | 52 | 8 | 8 | 0 | 39 | 34ms |
| libsodium_blake2b | C | 21 | 1 | 1 | 0 | 61 | 35ms |
| libsodium_sign | C | 19 | 1 | 1 | 0 | 10 | 21ms |

## Rust FFI Detection: Before vs After

| Metric | v0.1.5 | v0.1.8 | Change |
|--------|--------|--------|--------|
| Rust FFI TP Rate | 0% | ~90% | +90pp |
| rust_sqlite Issues | 0 | 14 | +14 (7 UAF + 6 leaks) |
| subtle_unsafe_rs Issues | 0 | 6 | +6 |
| ring Issues | 0 | 14 | +14 |
| blst Issues | 0 | 33 | +33 |
| Total Rust FFI Boundaries | 0 | 11,604 | +11,604 |

## Performance

| Metric | Value |
|--------|-------|
| Small files (<100 funcs) | <150ms |
| Medium files (100-500 funcs) | 50-2,000ms |
| Large files (500-2000 funcs) | 1-3s |
| Very large (3000+ funcs) | ~13s (sqlite3) |

## Reproduction

```bash
zig build
./scripts/test.sh bench
```
