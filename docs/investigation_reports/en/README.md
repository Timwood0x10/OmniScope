# OmniScope Investigation Report Index v0.1.7

**Last Updated**: 2026-05-04
**Version**: v0.1.7 (Post Phase 1+2+3 Fixes)

---

## Report List

All reports have been updated to **v0.1.7** with latest 17-file benchmark data.

### 📊 Core Reports (Must Read)

| Report | Language | Summary |
|--------|----------|---------|
| [accuracy_validation](./accuracy_validation.md) | EN | **Accuracy Validation** — 17-file full validation, 548 issues, 27076 ptrs, 92% coverage |
| [accuracy_validation](../zh/accuracy_validation.md) | ZH | 准确性验证报告 |
| [rust_ffi_restoration_v017](./rust_ffi_restoration_v017.md) | EN | **Rust FFI Restoration** — Phase 1+2+3 fix details, TP 0%→20% |
| [rust_ffi_restoration_v017](../zh/rust_ffi_restoration_v017.md) | ZH | Rust FFI 恢复调查报告 |

### 🔬 Project-Specific Reports

| Report | Language | Project | Issues | FFI Bounds |
|--------|----------|---------|--------|------------|
| [wasmtime](./wasmtime.md) | EN/ZH | wasmtime (WebAssembly Runtime) | **44** | **130** |
| [ring](./ring.md) | EN/ZH | ring (Crypto Library) | **19** | **4266** |
| [blst](./blst.md) | EN/ZH | blst (BLS12-381) | **35** | **1382** |
| [ffi_dense](./ffi_dense.md) | EN/ZH | zlib/openssl/sqlite bindings | **7** | **86** |
| [other_projects](./other_projects.md) | EN/ZH | curl/sqlite3/openssl | **341** | **3083** |
| [zkcrypto_bls12_381](./zkcrypto_bls12_381.md) | EN/ZH | zkcrypto (Pure Rust) | **0** | N/A |
| [real_world_analysis_v016](../zh/real_world_analysis_v016.md) | ZH | Real-World Comprehensive Analysis | **485** | **8961** |

---

## v0.1.7 Key Metrics Summary

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

## Version History

| Version | Date | Main Changes |
|---------|------|--------------|
| v0.1.5 | 2026-04-15 | Initial release |
| v0.1.6 | 2026-04-27 | FP suppression + Zone Classifier |
| **v0.1.7** | **2026-05-04** | **Phase 1+2+3 comprehensive fixes + dead code cleanup + full benchmark** |

---

## Quick Navigation

- **Overall effectiveness?** → [accuracy_validation](./accuracy_validation.md)
- **Rust FFI fix details?** → [rust_ffi_restoration_v017](./rust_ffi_restoration_v017.md)
- **Specific project data?** → Select project report above
- **Raw benchmark data?** → `benchmark-output/benchmark-results.json`
