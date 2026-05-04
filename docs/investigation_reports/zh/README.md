# OmniScope 调查报告索引 v0.1.7

**最后更新**: 2026-05-04
**版本**: v0.1.7 (Post Phase 1+2+3 Fixes)

---

## 报告列表

所有报告均已更新至 **v0.1.7**，使用最新的 17 文件 benchmark 数据。

### 📊 核心报告 (必读)

| 报告 | 语言 | 内容摘要 |
|------|------|----------|
| [accuracy_validation](./accuracy_validation.md) | 中文 | **准确性验证报告** — 17 文件完整验证，548 issues，27076 ptrs，92% 覆盖率 |
| [accuracy_validation](../en/accuracy_validation.md) | English | Accuracy Validation Report — Full 17-file validation |
| [rust_ffi_restoration_v017](./rust_ffi_restoration_v017.md) | 中文 | **Rust FFI 恢复调查** — Phase 1+2+3 修复详情，TP 0%→20% |
| [rust_ffi_restoration_v017](../en/rust_ffi_restoration_v017.md) | English | Rust FFI Restoration Investigation Report |

### 🔬 项目专项报告

| 报告 | 语言 | 项目 | Issues | FFI Bounds |
|------|------|------|--------|------------|
| [wasmtime](./wasmtime.md) | 中/英 | wasmtime (WebAssembly 运行时) | **44** | **130** |
| [ring](./ring.md) | 中/英 | ring (密码学库) | **19** | **4266** |
| [blst](./blst.md) | 中/英 | blst (BLS12-381) | **35** | **1382** |
| [ffi_dense](./ffi_dense.md) | 中/英 | zlib/openssl/sqlite 绑定 | **7** | **86** |
| [other_projects](./other_projects.md) | 中/英 | curl/sqlite3/openssl | **341** | **3083** |
| [zkcrypto_bls12_381](./zkcrypto_bls12_381.md) | 中/英 | zkcrypto (纯 Rust) | **0** | N/A |
| [real_world_analysis_v016](./real_world_analysis_v016.md) | 中文 | 真实世界综合分析 | **485** | **8961** |

---

## v0.1.7 关键指标汇总

```
╔══════════════════════════════════════════════════════════════╗
║              OmniScope v0.1.7 — Final Summary               ║
╠══════════════════════════════════════════════════════════════╣
║                                                                ║
║  📁 Test Files:        17 (Red Team 8 + FFI-Dense 3 + RW 6)   ║
║  🐛 Total Issues:      548                                     ║
║  👆 Ptrs Tracked:      27076                                   ║
║  ⚠️  Violations:       251                                     ║
║  🔗 FFI Boundaries:    9372                                    ║
║                                                                ║
║  🧪 Test Coverage:     92% (191 tests)                         ║
║  🎯 Rust FFI TP Rate:  20% (4/20 subtle_unsafe_rs)             ║
║  💯 Precision:         ~88% (overall)                          ║
║  📉 FP Rate:           ~14%                                    ║
║                                                                ║
║  🔧 Fixes Applied:     14 (Phase 1+2+3)                        ║
║  🗑️  Dead Code Removed: -700 lines                            ║
║  📝 Reports Updated:    22 files (zh + en)                     ║
║                                                                ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| v0.1.5 | 2026-04-15 | 初始版本 |
| v0.1.6 | 2026-04-27 | FP 抑制 + Zone Classifier |
| **v0.1.7** | **2026-05-04** | **Phase 1+2+3 全面修复 + 死代码清理 + 全量 benchmark** |

---

## 快速导航

- **想了解整体效果?** → [accuracy_validation](./accuracy_validation.md)
- **想了解 Rust FFI 修复细节?** → [rust_ffi_restoration_v017](./rust_ffi_restoration_v017.md)
- **想看具体项目数据?** → 选择上方对应的项目报告
- **想看 benchmark 原始数据?** → `benchmark-output/benchmark-results.json`
