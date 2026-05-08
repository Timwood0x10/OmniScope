# OmniScope 调查报告索引 v0.1.7

**最后更新**: 2026-05-06
**版本**: v0.1.7 (24 Bugs Fixed)

---

## 报告列表

所有报告均已更新至 **v0.1.7**，修复 24 个 bug，340/340 测试通过。

### 📊 核心报告 (必读)

| 报告 | 语言 | 内容摘要 |
|------|------|----------|
| [accuracy_validation](./accuracy_validation.md) | 中文 | **准确性验证报告** — 17 文件完整验证，548 issues，27076 ptrs，92% 覆盖率 |
| [accuracy_validation](../en/accuracy_validation.md) | English | Accuracy Validation Report — Full 17-file validation |
| [rust_ffi_restoration_v016](./rust_ffi_restoration_v016.md) | 中文 | **Rust FFI 恢复调查** — Phase 1+2+3 修复详情，TP 0%→20% |
| [rust_ffi_restoration_v016](../en/rust_ffi_restoration_v016.md) | English | Rust FFI Restoration Investigation Report |
| [v018_bug_fix_report](./v018_bug_fix_report.md) | 中文 | **v0.1.7 Bug修复报告** — 24 bugs fixed, 340/340 tests pass |
| [v018_bug_fix_report](../en/v018_bug_fix_report.md) | English | v0.1.7 Bug Fix Report |

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

## 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| v0.1.5 | 2026-04-15 | 初始版本 |
| v0.1.6 | 2026-04-27 | FP 抑制 + Zone Classifier |
| v0.1.6 | 2026-05-04 | Phase 1+2+3 全面修复 + 死代码清理 |
| **v0.1.7** | **2026-05-06** | **24 bugs fixed, 340/340 tests pass** |

---

## 快速导航

- **想了解 v0.1.7 修复详情?** → [v018_bug_fix_report](./v018_bug_fix_report.md)
- **想了解整体效果?** → [accuracy_validation](./accuracy_validation.md)
- **想了解 Rust FFI 修复细节?** → [rust_ffi_restoration_v016](./rust_ffi_restoration_v016.md)
- **想看具体项目数据?** → 选择上方对应的项目报告
- **想看 benchmark 原始数据?** → `benchmark-output/benchmark-results.json`
