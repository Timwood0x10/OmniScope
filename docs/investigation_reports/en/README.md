# OmniScope Project Investigation Reports Index v0.1.5

**Test Date**: 2026-04-25
**Test Version**: v0.1.5 (Zone Classification)

---

## Report List

### ZKP Projects

| Project | Language | Functions | Skip % | Issues | Report |
|---------|----------|-----------|--------|--------|--------|
| blst | Rust + C | 267 | 64.0% | 48 | [View](./blst.md) |
| ring | Rust + C | 278 | 100% | 0 | [View](./ring.md) |
| zkcrypto/bls12_381 | Rust | 259 | 66.4% | 0 | [View](./zkcrypto_bls12_381.md) |

### Rust Projects

| Project | Language | Functions | Skip % | Issues | Report |
|---------|----------|-----------|--------|--------|--------|
| wasmtime | Rust | 619 | 74.3% | 96 | [View](./wasmtime.md) |
| ripgrep | Rust | 30 | 46.7% | 0 | [View](./other_projects.md) |
| rust-sqlite | Rust FFI | 17 | 52.9% | 6 | [View](./other_projects.md) |

### FFI-Dense Projects

| Project | Language | Functions | Skip % | Issues | Report |
|---------|----------|-----------|--------|--------|--------|
| zlib-binding | Rust FFI | 12 | 0% | 14 | [View](./ffi_dense.md) |
| openssl-wrapper | Rust FFI | 12 | 0% | 7 | [View](./ffi_dense.md) |
| sqlite-binding | Rust FFI | 8 | 0% | 4 | [View](./ffi_dense.md) |

### Other Projects

| Project | Language | Functions | Skip % | Issues | Report |
|---------|----------|-----------|--------|--------|--------|
| ark-ff | Rust | 16 | 18.8% | 0 | [View](./other_projects.md) |
| libsodium | C | 10 | 0% | 0 | [View](./other_projects.md) |
| gnark-crypto | Go | 838 | 29.8% | 1 | [View](./other_projects.md) |

---

## Core Improvement Metrics

| Metric | 优化前 | 优化后 | Improvement |
|--------|--------|--------|-------------|
| Average Skip Rate | 0% | **60%** | - |
| Analysis Time | - | - | **Up to 73%** |
| Issue Precision | 185 UAFs | 48 issues | **74% improvement** |

---

## Related Reports

- [Performance Improvement Report](../project_exports/en/PERFORMANCE_IMPROVEMENT.md)
- [Comprehensive Test Report](../project_exports/en/COMPREHENSIVE_REPORT.md)
