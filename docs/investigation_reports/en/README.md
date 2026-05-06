# OmniScope Investigation Report Index v0.1.7

**Last Updated**: 2026-05-06
**Version**: v0.1.7 (24 Bugs Fixed)

---

## Report List

All reports have been updated to **v0.1.7** with 24 bugs fixed and 340/340 tests passing.

### 📊 Core Reports (Must Read)

| Report | Language | Summary |
|--------|----------|---------|
| [accuracy_validation](./accuracy_validation.md) | EN | **Accuracy Validation** — 17-file full validation, 548 issues, 27076 ptrs, 92% coverage |
| [accuracy_validation](../zh/accuracy_validation.md) | ZH | 准确性验证报告 |
| [rust_ffi_restoration_v016](./rust_ffi_restoration_v016.md) | EN | **Rust FFI Restoration** — Phase 1+2+3 fix details, TP 0%→20% |
| [rust_ffi_restoration_v016](../zh/rust_ffi_restoration_v016.md) | ZH | Rust FFI 恢复调查报告 |
| [v018_bug_fix_report](./v018_bug_fix_report.md) | EN | **v0.1.7 Bug Fix Report** — 24 bugs fixed, 340/340 tests pass |
| [v018_bug_fix_report](../zh/v018_bug_fix_report.md) | ZH | v0.1.7 Bug修复报告 |

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
║              OmniScope v0.1.7 — Bug Fix Summary              ║
╠══════════════════════════════════════════════════════════════╣
║                                                                ║
║  🐛 Bugs Identified:   24                                      ║
║  ✅ Bugs Fixed:        24 (100%)                               ║
║  🧪 Tests Passing:     340/340                                 ║
║                                                                ║
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ║
║  CRITICAL Bugs:        3  →  0  (all fixed)                    ║
║  HIGH Bugs:            5  →  0  (all fixed)                    ║
║  MEDIUM Bugs:          7  →  0  (all fixed)                    ║
║  LOW Bugs:             3  →  0  (all fixed)                    ║
║  NEW in v0.1.7:        4  →  0  (all fixed)                    ║
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ║
║                                                                ║
║  🔧 Memory Safety:     get→getPtr, errdefer patterns           ║
║  🔧 API Correctness:   deinit() fixes                          ║
║  🔧 JSON Compliance:   lowercase hex (\uXXXX)                  ║
║  🔧 Error Handling:    catch unreachable→try                   ║
║                                                                ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Version History

| Version | Date | Main Changes |
|---------|------|--------------|
| v0.1.5 | 2026-04-15 | Initial release |
| v0.1.6 | 2026-04-27 | FP suppression + Zone Classifier |
| v0.1.6 | 2026-05-04 | Phase 1+2+3 comprehensive fixes + dead code cleanup |
| **v0.1.7** | **2026-05-06** | **24 bugs fixed, 340/340 tests pass** |

---

## Quick Navigation

- **v0.1.7 fix details?** → [v018_bug_fix_report](./v018_bug_fix_report.md)
- **Overall effectiveness?** → [accuracy_validation](./accuracy_validation.md)
- **Rust FFI fix details?** → [rust_ffi_restoration_v016](./rust_ffi_restoration_v016.md)
- **Specific project data?** → Select project report above
- **Raw benchmark data?** → `benchmark-output/benchmark-results.json`
