# OmniScope Investigation Report Index

**Last Updated**: 2026-05-09
**Auditor**: OmniScope (LLVM IR Static Analyzer)

---

## 🔬 Evidence Ladder Audit Reports (L0-L4 Classification)

**Framework**: Evidence Ladder (Pattern → PoC) | **Date**: 2026-05-09 | **Total Issues**: 133

### Test Case Audits (Controlled Environment)

| Report | Project | Issues | L3+ Issues | Top Finding | Confidence |
|--------|---------|--------|------------|-------------|------------|
| [AUDIT_subtle_unsafe_rs_EVIDENCE_LADDER](./AUDIT_subtle_unsafe_rs_EVIDENCE_LADDER.md) | subtle_unsafe_rs (Rust FFI) | **14** | **5** (35.7%) | Double Free + UAF with PoCs | **95%** |
| [AUDIT_subtle_ffi_bugs_EVIDENCE_LADDER](./AUDIT_subtle_ffi_bugs_EVIDENCE_LADDER.md) | subtle_ffi_bugs (C FFI) | **22** | **9** (40.9%) | UAF + Memory Corruption | **93%** |
| [AUDIT_posix_ffi_bugs_EVIDENCE_LADDER](./AUDIT_posix_ffi_bugs_EVIDENCE_LADDER.md) | posix_ffi_bugs (POSIX API) | **10** | **4** (40.0%) | Signal Handler + Thread Safety | **92%** |

### Real-World Project Audits (Production Code)

| Report | Project | Scale | Total Issues | Critical | L3+ Issues | Potential CVE |
|--------|---------|-------|--------------|----------|------------|---------------|
| [AUDIT_sqlite3_EVIDENCE_LADDER](./AUDIT_sqlite3_EVIDENCE_LADDER.md) | **SQLite3** (Database Engine) | ~134K LOC | **8** | **2** | **2** (25.0%) | - |
| [AUDIT_curl8_EVIDENCE_LADDER](./AUDIT_curl8_EVIDENCE_LADDER.md) | **curl/libcurl 8.x** (HTTP Client) | ~150K LOC | **21** | **9** | **2** (9.5%) | - |
| [AUDIT_libuv150_EVIDENCE_LADDER](./AUDIT_libuv150_EVIDENCE_LADDER.md) | **libuv v1.50.0** (Node.js I/O) | ~80K LOC | **59** | **10** | **5** (8.5%) | ✅ **Signal Handler** |

### Evidence Level Distribution Summary

| Level | Definition | Count | Percentage |
|-------|-----------|-------|------------|
| **L4 - PoC Available** | Executable proof-of-concept code | **8** | 6.0% |
| **L3 - Exploit Scenario** | Complete attack scenario constructed | **17** | 12.8% |
| **L2 - Source Correlated** | Source code location identified | **29** | 21.8% |
| **L1 - Escape Proven** | Stack escape path confirmed | **36** | 27.1% |
| **L0 - Pattern Match** | IR-level pattern detected | **43** | 32.3% |
| **Total** | All classified issues | **133** | 100% |

---

## 📊 Additional Reports

| Report | Language | Project | Issues | FFI Bounds |
|--------|----------|---------|--------|------------|
| [accuracy_validation](./accuracy_validation.md) | EN | Accuracy Validation | **548 issues** | **27,076 ptrs** |
| [wasmtime](./wasmtime.md) | EN | wasmtime (WebAssembly Runtime) | **44** | **130** |
| [ring](./ring.md) | EN | ring (Crypto Library) | **19** | **4266** |
| [blst](./blst.md) | EN | blst (BLS12-381) | **35** | **1382** |
| [ffi_dense](./ffi_dense.md) | EN | zlib/openssl/sqlite bindings | **7** | **86** |
| [other_projects](./other_projects.md) | EN | curl/sqlite3/openssl | **341** | **3083** |
| [zkcrypto_bls12_381](./zkcrypto_bls12_381.md) | EN | zkcrypto (Pure Rust) | **0** | N/A |

---

## 🎯 Key Findings

### High-Value Discoveries (L3+ Level)

| Project | Issue Type | Confidence | Impact |
|---------|-----------|------------|--------|
| **libuv v1.50.0** | Signal Handler Stack Escape | **87%** | 🔥🔥🔴 **P0-Critical** (Node.js ecosystem) |
| **libuv v1.50.0** | Thread Creation Arg Lifetime | **90%** | 🔥🔴 **P0-High** (Cross-platform) |
| **curl 8.x** | Thread Creation Arg Lifetime | **92%** | 🔥🔴 **P0-Critical** (HTTP client) |
| **curl 8.x** | Shutdown Handler Stack Escape | **88%** | 🔴 **P0-High** (Connection security) |
| **subtle_unsafe.rs** | Double Free + UAF (×5 PoCs) | **95%** | 💀 **L4-PoC Ready** |
| **subtle_ffi_bugs.c** | Triple Violation (UAF+DF+WAF) | **93%** | 💀 **L4-PoC Ready** |

---

## Quick Navigation

- **Evidence Ladder Framework?** → [EVIDENCE_LADDER_REPORT](./EVIDENCE_LADDER_REPORT.md)
- **Test case audits?** → See "Test Case Audits" section above
- **Real-world projects?** → See "Real-World Project Audits" section above
- **Full verification data?** → [FULL_VERIFICATION_V017](./FULL_VERIFICATION_V017.md)
- **41-project audit?** → [OMNISCOPE_FULL_AUDIT_41_PROJECTS](./OMNISCOPE_FULL_AUDIT_41_PROJECTS.md)
- **Chinese version?** → [中文版 README](../zh/README.md)

---
**Report Index Version**: v2.0 (Evidence Ladder Focused)  
**Auditor**: OmniScope (LLVM IR Static Analyzer)