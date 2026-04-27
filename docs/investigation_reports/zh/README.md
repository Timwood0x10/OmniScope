# OmniScope 项目调查报告索引 v0.1.5

**测试日期**: 2026-04-25
**测试版本**: v0.1.5 (Zone Classification)

---

## 报告列表

### ZKP 项目

| 项目 | 语言 | 函数数 | Skip % | Issues | 报告 |
|------|------|--------|--------|--------|------|
| blst | Rust + C | 267 | 64.0% | 48 | [查看](./blst.md) |
| ring | Rust + C | 278 | 100% | 0 | [查看](./ring.md) |
| zkcrypto/bls12_381 | Rust | 259 | 66.4% | 0 | [查看](./zkcrypto_bls12_381.md) |

### Rust 项目

| 项目 | 语言 | 函数数 | Skip % | Issues | 报告 |
|------|------|--------|--------|--------|------|
| wasmtime | Rust | 619 | 74.3% | 96 | [查看](./wasmtime.md) |
| ripgrep | Rust | 30 | 46.7% | 0 | [查看](./other_projects.md) |
| rust-sqlite | Rust FFI | 17 | 52.9% | 6 | [查看](./other_projects.md) |

### FFI 密集型项目

| 项目 | 语言 | 函数数 | Skip % | Issues | 报告 |
|------|------|--------|--------|--------|------|
| zlib-binding | Rust FFI | 12 | 0% | 14 | [查看](./ffi_dense.md) |
| openssl-wrapper | Rust FFI | 12 | 0% | 7 | [查看](./ffi_dense.md) |
| sqlite-binding | Rust FFI | 8 | 0% | 4 | [查看](./ffi_dense.md) |

### 其他项目

| 项目 | 语言 | 函数数 | Skip % | Issues | 报告 |
|------|------|--------|--------|--------|------|
| ark-ff | Rust | 16 | 18.8% | 0 | [查看](./other_projects.md) |
| libsodium | C | 10 | 0% | 0 | [查看](./other_projects.md) |
| gnark-crypto | Go | 838 | 29.8% | 1 | [查看](./other_projects.md) |

---

## 核心改进数据

| 指标 | 优化前 | 优化后 | 改进 |
|------|--------|--------|------|
| 平均跳过率 | 0% | **60%** | - |
| 分析时间 | - | - | **最高 73%** |
| 问题精准度 | 185 UAF | 48 issues | **提升 74%** |

---

## 相关报告

- [性能提升报告](../project_exports/zh/PERFORMANCE_IMPROVEMENT.md)
- [综合测试报告](../project_exports/zh/COMPREHENSIVE_REPORT.md)
