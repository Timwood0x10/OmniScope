# OmniScope 调查报告索引

**最后更新**: 2026-05-09
**审计工具**: OmniScope (LLVM IR 静态分析器)

---

## 🔬 Evidence Ladder 审计报告 (L0-L4 分级)

**框架**: Evidence Ladder (模式匹配 → PoC 验证) | **日期**: 2026-05-09 | **总 Issues**: 133

### 测试用例审计 (受控环境)

| 报告 | 项目 | Issues 数量 | L3+ 级别数 | 核心发现 | 置信度 |
|------|------|------------|------------|----------|--------|
| [AUDIT_subtle_unsafe_rs_EVIDENCE_LADDER](../en/AUDIT_subtle_unsafe_rs_EVIDENCE_LADDER.md) | subtle_unsafe_rs (Rust FFI) | **14** | **5** (35.7%) | Double Free + UAF (含 PoC) | **95%** |
| [AUDIT_subtle_ffi_bugs_EVIDENCE_LADDER](../en/AUDIT_subtle_ffi_bugs_EVIDENCE_LADDER.md) | subtle_ffi_bugs (C FFI) | **22** | **9** (40.9%) | UAF + 内存损坏 | **93%** |
| [AUDIT_posix_ffi_bugs_EVIDENCE_LADDER](../en/AUDIT_posix_ffi_bugs_EVIDENCE_LADDER.md) | posix_ffi_bugs (POSIX API) | **10** | **4** (40.0%) | 信号处理 + 线程安全 | **92%** |

### 真实开源项目审计 (生产代码)

| 报告 | 项目 | 代码规模 | 总 Issues | Critical | L3+ 级别 | 潜在 CVE |
|------|------|---------|----------|----------|----------|----------|
| [AUDIT_sqlite3_EVIDENCE_LADDER](../en/AUDIT_sqlite3_EVIDENCE_LADDER.md) | **SQLite3** (数据库引擎) | ~134K 行 | **8** | **2** | **2** (25.0%) | - |
| [AUDIT_curl8_EVIDENCE_LADDER](../en/AUDIT_curl8_EVIDENCE_LADDER.md) | **curl/libcurl 8.x** (HTTP 客户端) | ~150K 行 | **21** | **9** | **2** (9.5%) | - |
| [AUDIT_libuv150_EVIDENCE_LADDER](../en/AUDIT_libuv150_EVIDENCE_LADDER.md) | **libuv v1.50.0** (Node.js I/O 库) | ~80K 行 | **59** | **10** | **5** (8.5%) | ✅ **信号处理漏洞** |

### Evidence Level 分布总览

| 等级 | 定义 | 数量 | 占比 |
|------|------|------|------|
| **L4 - PoC 可用** | 有可执行的 PoC 代码 | **8** | 6.0% |
| **L3 - 攻击场景** | 构建了完整的攻击利用场景 | **17** | 12.8% |
| **L2 - 源码关联** | 已定位源码位置 | **29** | 21.8% |
| **L1 - 逃逸证实** | 栈逃逸路径已确认 | **36** | 27.1% |
| **L0 - 模式匹配** | IR 级模式检测到 | **43** | 32.3% |
| **总计** | 全部分级 issues | **133** | 100% |

---

## 📊 其他报告

| 报告 | 语言 | 项目 | Issues | FFI Bounds |
|------|------|------|--------|------------|
| [accuracy_validation](./accuracy_validation.md) | 中文 | 准确性验证报告 | **548 issues** | **27,076 ptrs** |
| [wasmtime](./wasmtime.md) | 中/英 | wasmtime (WebAssembly 运行时) | **44** | **130** |
| [ring](./ring.md) | 中/英 | ring (密码学库) | **19** | **4266** |
| [blst](./blst.md) | 中/英 | blst (BLS12-381) | **35** | **1382** |
| [ffi_dense](./ffi_dense.md) | 中/英 | zlib/openssl/sqlite 绑定 | **7** | **86** |
| [other_projects](./other_projects.md) | 中/英 | curl/sqlite3/openssl | **341** | **3083** |
| [zkcrypto_bls12_381](./zkcrypto_bls12_381.md) | 中/英 | zkcrypto (纯 Rust) | **0** | N/A |

---

## 🎯 核心发现

### 高价值发现 (L3+ 级别)

| 项目 | 问题类型 | 置信度 | 影响 |
|------|---------|--------|------|
| **libuv v1.50.0** | Signal Handler Stack Escape | **87%** | 🔥🔥🔴 **P0-Critical** (Node.js 生态) |
| **libuv v1.50.0** | Thread Creation Arg Lifetime | **90%** | 🔥🔴 **P0-High** (跨平台) |
| **curl 8.x** | Thread Creation Arg Lifetime | **92%** | 🔥🔴 **P0-Critical** (HTTP 客户端) |
| **curl 8.x** | Shutdown Handler Stack Escape | **88%** | 🔴 **P0-High** (连接安全) |
| **subtle_unsafe.rs** | Double Free + UAF (×5 PoCs) | **95%** | 💀 **L4-PoC 就绪** |
| **subtle_ffi_bugs.c** | Triple Violation (UAF+DF+WAF) | **93%** | 💀 **L4-PoC 就绪** |

---

## 快速导航

- **Evidence Ladder 框架说明?** → [EVIDENCE_LADDER_REPORT](../en/EVIDENCE_LADDER_REPORT.md)
- **测试用例审计?** → 查看"测试用例审计"章节
- **真实项目审计?** → 查看"真实开源项目审计"章节
- **完整验证数据?** → [FULL_VERIFICATION_V017](./FULL_VERIFICATION_V017.md)
- **41项目综合审计?** → [OMNISCOPE_FULL_AUDIT_41_PROJECTS](../en/OMNISCOPE_FULL_AUDIT_41_PROJECTS.md)
- **English version?** → [English README](../en/README.md)

---
**报告索引版本**: v2.0 (Evidence Ladder 专注版)  
**审计工具**: OmniScope (LLVM IR 静态分析器)