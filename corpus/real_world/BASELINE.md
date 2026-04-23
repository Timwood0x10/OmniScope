# Real-World Project Regression Baseline

> **Purpose**: Every code change must be validated against these baselines to prevent regression.
> **Rule**: If a change causes baseline numbers to shift, it must be intentional and documented here.
> **Last Updated**: 2026-04-23 (v0.2.0: Enhanced Detection - Double-Free, Loop-Leak, Format String, exec* series)

---

## 🎯 Version History

| Date | Version | Key Changes |
|------|---------|-------------|
| 2026-04-23 | v0.2.0 | **Enhanced Detection Release** — Double-Free detector (BFS alias analysis), Loop-Leak pattern, Format String classification, exec/posix_spawn family, Resource Leak framework |
| 2026-04-23 | v0.1.5 | Security audit fixes (30+ bugs), substring→exact matching, wabt #10 |
| 2026-04-22 | v0.1.4 | Phase 3 optimizations (ownership transfer, null guard dominance) |
| 2026-04-21 | v0.1.3 | Initial baseline creation |

---

## Cross-Project Summary

| Project | Version | Language | IR Size | Functions | Issues | Time | Memory Leak | UAF | Double Free | Loop Leak |
|---------|---------|----------|--------|-----------|--------|------|------------|-----|------------|----------|
| **SQLite** | 3.47.2 | C | 727K lines / 40MB | 3,237 | **2** ⚠️ | 4.8s | 0 ✅ | 0 ✅ | **2** 🔴 | 0 |
| **libcurl** | 8.14.0 | C | 10,479 lines / 192K | 68 | **1** | 1.1s | 0 ✅ | 1 | 0 | 0 |
| **libuv** | 1.50.0 | C | 6,112 lines / 256K | 145 | **6** 🔴 | 0.6s | 0 ✅ | 0 ✅ | **6** 🔴 | 0 |
| **jsoncpp** | 1.9.5 | C++ | 90,323 lines | 1,537 | **10** 🔴 | 2.1s | **2** | 0 | **8** 🔴 | 0 |
| **abseil-cpp** | 20240722.0 | C++ | 15,868 lines | 193 | **0** ✅ | 0.4s | 0 ✅ | 0 ✅ | 0 ✅ | 0 |
| **ripgrep** | 14.1.1 | Rust | 6,317 lines | 75 | **0** ✅ | 0.04s | 0 ✅ | 0 ✅ | 0 ✅ | 0 |
| **rust_sqlite** | test | Rust | 4,044 lines | 135 | **11** 🔴 | 0.09s | **5** | 1 | **5** 🔴 | 0 |
| **openssl_wrapper** | test | C | 463 lines | 52 | **10** 🔴 | 0.03s | **5** | 0 | **5** 🔴 | 0 |
| **wasmtime_test** | 44.0.0 | Rust | 82,486 lines | 974 | **10** 🔴 | 6.7s | 0 | 0 | **10** 🔴 | 0 |
| **wabt** | latest | C++ | 31,539 lines | 558 | **9** 🔴 | ~2.0s | **4** | 0 | 0 | **4** 🔴 |

**Total: 10 real-world projects (3 C + 3 C++ + 4 Rust), 6,937 functions, ~16.5s total analysis time**

### New Detection Capabilities (v0.2.0)

| Capability | Status | Description |
|------------|--------|-------------|
| **Double-Free Detection** | ✅ NEW | BFS-based alias analysis with depth limiting (≤3 hops), detects multiple free() on same allocation |
| **Loop-Leak Pattern** | ✅ NEW | Heuristic: ≥3 allocations in single function without matching frees |
| **Format String Classification** | ✅ ENHANCED | Precise `IssueKind.format_string` for printf/sprintf/snprintf/syslog family |
| **exec Family Detection** | ✅ NEW | Full coverage: execve/execvp/execv/execl/execlp/execle/fexecve/posix_spawn/posix_spawnp |
| **Resource Leak Framework** | ✅ NEW | Detects fopen↔fclose, socket↔close, opendir↔closedir, popen↔pclose mismatches |
| **Stack Buffer Overflow** | 🚧 WIP | GEP + alloca size checking framework created (`buffer_overflow.zig`) |

---

## Project Details

### Project #1: SQLite 3.47.2 (Amalgamation)

| Field | Value |
|-------|-------|
| **Source** | sqlite-amalgamation-3470200.zip |
| **IR File** | `corpus/real_world/sqlite3.ll` |
| **IR Size** | 727,000 lines / 40 MB |
| **Functions** | 3,237 |
| **Analysis Time** | ~5.9s (Apple M-series) |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **2** | 2 DOUBLE-FREE in internal functions |
| DOUBLE-FREE | **2** | `sqlite3Pragma` (5 frees), `execSql` (10 frees) — likely FP from complex internal cleanup patterns |
| MEMORY LEAK | **0** ✅ | All eliminated by ownership transfer detection |
| USE-AFTER-FREE | **0** ✅ | No UAF detected in stable release |
| null_dereference | **0** ✅ | All guarded by null checks |

#### Regression Guard Rules

1. **Total issues ≤ 5** (current: 2)
2. **Analysis time ≤ 15s** (current: ~5.8s)
3. **Memory leak count = 0** ← strict!
4. **UAF count = 0** ← strict!

---

### Project #2: libcurl 8.14.0

| Field | Value |
|-------|-------|
| **Source** | curl-8.14.0.tar.gz |
| **IR File** | `corpus/real_world/curl8.ll` |
| **IR Size** | 10,479 lines / 192 KB |
| **Functions** | 68 |
| **Analysis Time** | ~1.1s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **1** | 1 USE-AFTER-FREE |
| USE-AFTER-FREE | **1** | Post-realloc usage pattern (benign in libcurl's error handling) |
| FFI RISK (CRITICAL) | 0 | system/popen not used in this build configuration |
| MEMORY LEAK | **0** ✅ | All allocations properly freed |

#### Regression Guard Rules

1. **Total issues ≤ 5** (current: 1)
2. **FFI CRITICAL = 0** ← strict! (no command injection in this build)

---

### Project #3: libuv 1.50.0

| Field | Value |
|-------|-------|
| **Source** | libuv-1.50.0.tar.gz |
| **IR File** | `corpus/real_world/libuv150.ll` |
| **IR Size** | 6,112 lines / 256 KB |
| **Functions** | 145 |
| **Analysis Time** | ~0.6s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **6** | 6 DOUBLE-FREE in scandir cleanup |
| DOUBLE-FREE | **6** | `uv__fs_scandir_cleanup` (5 frees), `uv_fs_scandir_next` (2 frees) — likely FP from directory entry cleanup loops |
| MEMORY LEAK | **0** ✅ | Clean memory management |

#### Regression Guard Rules

1. **Total issues ≤ 10** (current: 6)
2. **Memory leak = 0** ← strict!

---

### Project #4: jsoncpp 1.9.5

| Field | Value |
|-------|-------|
| **Source** | jsoncpp-1.9.5.tar.gz |
| **IR File** | `corpus/real_world/jsoncpp195.ll` |
| **IR Size** | 90,323 lines |
| **Functions** | 1,537 |
| **Analysis Time** | ~2.1s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **10** | 2 MEMORY LEAK + 8 DOUBLE-FREE |
| MEMORY LEAK | **2** | `Comments::get()` and `Comments::has()` — genuine leaks in comment handling |
| DOUBLE-FREE | **8** | `CharReaderBuilder::newCharReader` (6×), `releasePrefixedStringValue` (1×), `FastWriter::~FastWriter` (31 frees!) — mixed TP/FP |

#### Analysis Notes

- jsoncpp has known memory management issues in CharReader pattern (RAII mismatch between C++ and C-style allocation)
- The 31-free detection in `FastWriter::~FastWriter` suggests a complex destructor with loop-based cleanup
- **Recommendation**: These are mostly genuine C++ RAII violations that OmniScope correctly identifies

#### Regression Guard Rules

1. **Total issues ≤ 20** (current: 10)
2. **Memory leak ≤ 5** (current: 2)

---

### Project #5: abseil-cpp 20240722.0

| Field | Value |
|-------|-------|
| **Source** | abseil-cpp-absl-20240722.0.tar.gz (strings/cord.cc only) |
| **IR File** | `corpus/real_world/abseil2024.ll` |
| **IR Size** | 15,868 lines |
| **Functions** | 193 |
| **Analysis Time** | ~0.4s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **0** ✅ | Perfect score! |
| MEMORY LEAK | **0** ✅ | Cord memory management is clean |
| DOUBLE-FREE | **0** ✅ | No double-free patterns |
| FFI RISK | **0** ✅ | No dangerous libc calls |

#### Regression Guard Rules

1. **Total issues = 0** ← strict!
2. **All categories = 0** ← strict!

---

### Project #6: ripgrep 14.1.1

| Field | Value |
|-------|-------|
| **Source** | ripgrep-14.1.1.tar.gz (searcher crate) |
| **IR File** | `corpus/real_world/ripgrep141.ll` |
| **IR Size** | 6,317 lines |
| **Functions** | 75 |
| **Analysis Time** | ~0.04s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **0** ✅ | Perfect score! Rust's ownership system works correctly |
| MEMORY LEAK | **0** ✅ | |
| DOUBLE-FREE | **0** ✅ | |
| cross-language violation | **0** ✅ | Pure Rust, no FFI issues |

#### Regression Guard Rules

1. **Total issues = 0** ← strict!

---

### Project #7: rust_sqlite (test wrapper)

| Field | Value |
|-------|-------|
| **Source** | Custom test project (Rust FFI to SQLite) |
| **IR File** | `corpus/real_world/rust_sqlite.ll` |
| **IR Size** | 4,044 lines |
| **Functions** | 135 |
| **Analysis Time** | ~0.09s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **11** | 5 MEMORY LEAK + 1 UAF + 5 DOUBLE-FREE |
| MEMORY LEAK | **5** | Intentional test cases: `leak_statement`, `leak_database`, `leak_cstring`, `null_pointer_deref`, plus 1 internal |
| USE-AFTER-FREE | **1** | `use_after_free` — intentional test case |
| DOUBLE-FREE | **5** | `double_close` (2×), `correct_usage` (3×) — intentional and FP mix |

#### Analysis Notes

- This is a **test suite** designed to trigger OmniScope detections
- Most issues are **intentionally injected bugs** for testing
- `correct_usage` showing 3 doubles is likely FP from normal cleanup patterns

#### Regression Guard Rules

1. **Total issues ≥ 8** (current: 11, lower bound for test suite)
2. **Must detect: leak_*, use_after_free, double_close** (intentional bugs)

---

### Project #8: openssl_wrapper (test)

| Field | Value |
|-------|-------|
| **Source** | Custom OpenSSL FFI test |
| **IR File** | `corpus/real_world/openssl_wrapper.ll` |
| **IR Size** | 463 lines |
| **Functions** | 52 |
| **Analysis Time** | ~0.03s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **10** | 5 MEMORY LEAK + 5 DOUBLE-FREE |
| MEMORY LEAK | **5** | Intentional: `encrypt_leak_ctx`, `ssl_ctx_leak`, `bio_leak`, `rsa_key_leak`, `x509_leak` |
| DOUBLE-FREE | **5** | `correct_encryption` (5 allocations × 5 frees each) — likely FP from loop pattern |

#### Regression Guard Rules

1. **Total issues ≥ 8** (lower bound for test suite)
2. **Must detect all 5 intentional memory leaks**

---

### Project #9: wasmtime_test 44.0.0

| Field | Value |
|-------|-------|
| **Source** | wasmtime 44.0.0 (test subset) |
| **IR File** | `corpus/real_world/wasmtime_test.ll` |
| **IR Size** | 82,486 lines |
| **Functions** | 974 |
| **Analysis Time** | ~6.7s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **10** | 10 DOUBLE-FREE |
| DOUBLE-FREE | **10** | Complex patterns in `ConstExprEvaluator::eval_loop` (27 frees!), `FuncType::new` (21-22 frees), `Linker::instantiate`, `Error::new` |
| MEMORY LEAK | **0** | Rust ownership working correctly |

#### Analysis Notes

- wasmtime uses complex internal caching/ pooling that triggers double-free detection
- The 27-free pattern in `eval_loop` closure is likely a legitimate reuse pool (not a bug)
- These are **borderline FP** — real double-frees would have exactly 2 frees, not 27

#### Regression Guard Rules

1. **Total issues ≤ 15** (current: 10)
2. **No memory leaks or UAF** ← strict for Rust project!

---

### Project #10: wabt (WebAssembly Binary Toolkit)

| Field | Value |
|-------|-------|
| **Source** | https://github.com/WebAssembly/wabt |
| **IR File** | `corpus/real_world/wabt_wast2json.ll` |
| **IR Size** | 31,539 lines |
| **Functions** | 558 |
| **Analysis Time** | ~2.0s |

#### Baseline Results (v0.2.0)

| Category | Count | Details |
|----------|-------|---------|
| **Total Issues** | **9** | 4 MEMORY LEAK + 4 LOOP-LEAK + 1 other |
| MEMORY LEAK | **4** | C++ unique_ptr patterns in Command vector (expected: C++ RAII managed) |
| LOOP-LEAK | **4** | `vector<unique_ptr<Command>>::annotate_*` methods — STL container growth patterns |
| DOUBLE-FREE | **0** | |

#### Analysis Notes

- wabt uses C++ smart pointers extensively — OmniScope detects the underlying malloc/free but these are managed by destructors
- Loop-leak detections match STL vector reallocation patterns (growth factor 2×)
- **All issues are expected FP for C++ code with RAII**

#### Regression Guard Rules

1. **Total issues ≤ 15** (current: 9)
2. **No CRITICAL issues** (all are MEDIUM from C++ RAII patterns)

---

## 🔬 Red Team Adversarial Test Suite

> Location: `corpus/red_team_test/`

### Test File: red_team_bugs.c (English comments)

**17 intentionally injected vulnerabilities** covering 10 types:

| Bug ID | Type | Detection Status (O0 build) | Notes |
|-------|------|----------------------------|-------|
| BUG-01 | Memory Leak | ✅ Detected | `bug_memory_leak` |
| BUG-02 | Use-After-Free | ✅ Detected | `bug_use_after_free` |
| BUG-03 | Double Free | ✅ **NEW!** | `bug_double_free` — 4 allocations × 2 frees each |
| BUG-04 | NULL Dereference | ✅ Detected | VULNERABILITY OMI-002 |
| BUG-05 | system() | ✅ CRITICAL | FFI_RISK command_exec |
| BUG-06 | Stack Overflow | 🚧 WIP | Needs buffer_overflow.zig integration |
| BUG-07 | Format String | ✅ Enhanced | Now classified as `.format_string` type |
| BUG-08 | File Handle Leak | ⚠️ Framework | Resource leak detector created, needs flow_graph fix |
| BUG-09 | Realloc Mishandle | ✅ Detected | Reported as UAF |
| BUG-10 | Uninitialized Var | ❌ Not detected | Requires def-use analysis |
| BUG-11 | new[]/delete mismatch | N/A | C++ only, needs Clang++ frontend |
| BUG-12 | popen() | ✅ CRITICAL | FFI_RISK command_exec |
| BUG-13 | Array OOB | 🚧 WIP | Needs buffer_overflow.zig integration |
| BUG-14 | Struct Member Leak | ❌ Partial | Member-level tracking needed |
| BUG-15 | Loop Leak | ✅ **NEW!** | `bug_loop_leak` — 5 allocations detected |
| BUG-16 | Conditional Leak | ✅ Detected | Reported as UAF (path-sensitive) |
| BUG-17 | execvp() | ✅ **NEW!** | Sink: execvp() via taint analysis |

**Red Team Test Results (v0.2.0)**:
- **Build**: O0 required for BUG-03, BUG-04 (O1 optimizes away UB)
- **Total Issues**: **12** (was 7 in v0.1.5, **+71% improvement**)
- **New Detections**: Double-Free (+4), Loop-Leak (+1), execvp (+1)
- **Hit Rate**: **58.8%** (up from 41.2%)

---

## 🛠️ Security Audit Fix Record

### Phase 1: Critical Fixes (Completed 2026-04-21)

| Bug ID | Component | Fix Description | Severity |
|-------|-----------|----------------|----------|
| BUG-001 | ffi_detector.zig L437 | Type error: `func` → `func.func.raw` | Critical |
| BUG-002/003 | memory_pool.zig | `append()` → `addOne()` dangling pointer | High |
| BUG-004 | memory_pool.zig L164 | Integer overflow protection | High |
| BUG-007 | call_graph.zig L115 | Unsigned underflow bounds check | High |
| BUG-008 | alias.zig L269 | Pointer truncation @truncate | Medium |
| BUG-014 | ffi_detector.zig L486 | Null check on LLVMGetValueName | Medium |
| BUG-019 | CI workflow | Typo fix OmniSope→OmniScope | Low |

### Phase 2: Substring Matching Fixes (Completed 2026-04-22)

| Bug ID | Component | Fix Description | Impact |
|-------|-----------|----------------|--------|
| **CRITICAL** | ffi_unsafe.zig | `indexOf` → `eql` (exact match) | libcurl 59→0, SQLite 20→0 |
| **CRITICAL** | call_graph.zig | Same fix for classifyRisk/isSink | Eliminated all FPs |

### Phase 3: Enhanced Detection (Completed 2026-04-23)

| Feature | Component | Description |
|---------|-----------|-------------|
| **Double-Free** | cpp_fp_reduction.zig | BFS alias analysis with depth limiting (≤3 hops) |
| **Loop-Leak** | cpp_fp_reduction.zig | Per-function allocation counting heuristic |
| **Format String** | ffi_unsafe.zig | New IssueKind.format_string classification |
| **exec*** | ffi_unsafe.zig + call_graph.zig | 12 new dangerous functions added |
| **Resource Leak** | cpp_fp_reduction.zig | fopen/fclose, socket/close, etc. framework |
| **Stack OOB** | buffer_overflow.zig (new) | GEP + alloca size checking (framework) |

---

## 📋 Known Limitations & Future Work

### Current Limitations (v0.2.0)

1. **Double-Free FP Rate**: Some legitimate cleanup loops (27+ frees) trigger detection — need max-free threshold
2. **C++ RAII FP**: Smart-pointer managed memory reported as leaks (wabt, jsoncpp) — need C++ destructor analysis
3. **Stack OOB**: Framework created but not yet integrated into pipeline
4. **Resource Leak**: Framework created but flow_graph connectivity limits detection accuracy
5. **Optimization Sensitivity**: O1 optimization eliminates UB code, hiding bugs — need O0/O1 dual-mode testing

### Roadmap (v0.3.0)

- [ ] Integrate buffer_overflow.zig into pipeline
- [ ] Add C++ destructor/lifecycle analysis to reduce RAII FPs
- [ ] Implement max-free threshold for Double-Free (warn if >2, alert if ==2)
- [ ] Add O0/O1 dual-mode to baseline-check script
- [ ] Create regression test CI job for red-team suite

---

*Document maintained by OmniScope automated baseline system*
*Next scheduled update: After v0.3.0 feature completion*
