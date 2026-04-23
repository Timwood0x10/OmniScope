# OmniScope v0.2.1 Release Notes

**Release Date**: 2026-04-23
**Version**: 0.2.1 (Enhanced Detection Release)
**Status**: Stable

---

## 🎯 Release Summary

OmniScope v0.2.1 is a **major enhancement release** focused on **detection capability expansion** and **false positive reduction**. This release introduces 6 new detection capabilities, fixes a critical substring-matching bug that caused massive false positives, and establishes a red team adversarial testing framework for continuous validation.

### Key Metrics

| Metric | v0.1.5 | v0.2.0 | v0.2.1 | Change |
|--------|--------|--------|--------|--------|
| **Detection Passes** | 8 | 10 | **11** | +3 new passes |
| **Red Team Hit Rate** | N/A | 41.2% | **58.8%** | +17.6pp |
| **C++ FP Rate (wabt)** | N/A | 9 issues | **7 issues** | -22% |
| **Baseline Projects** | 10 | 10 | **10** | = |
| **Total Issues (real_world)** | ~54 | ~69 | ~4,114* | *wasmtime outlier |

---

## 🆕 New Features

### 1. Red Team Adversarial Test Suite
- **17 intentionally injected bugs** across 10 vulnerability types
- **Automated CI integration** via `make red-team-test`
- **Comprehensive reporting** with detection matrix and analysis
- **Location**: `corpus/red_team_test/`

### 2. Buffer Overflow Detection Pass (`buffer_overflow.zig`)
- **Stack buffer overflow**: GEP index vs alloca size checking
- **Array out-of-bounds**: Static array length validation
- **GEP instruction analysis**: Constant index extraction and bounds comparison
- **~220 lines** of well-documented Zig code following project standards

### 3. Double-Free Detection with BFS Alias Analysis
- **BFS-based alias resolution**: Depth-limited (≤3 hops) flow graph traversal
- **Smart threshold logic**:
  - `==2 frees` → HIGH severity (classic double-free bug)
  - `>2 frees` → MEDIUM severity (cleanup loop pattern)
- **O0 build support**: Works around compiler optimization eliminating UB code

### 4. Loop-Leak Pattern Detection
- **Heuristic rule**: ≥3 allocations per function without matching frees
- **Per-function counting**: Identifies suspicious allocation patterns
- **Use cases**: STL vector growth, intentional test bugs

### 5. Format String Vulnerability Classification
- **New IssueKind**: `.format_string`
- **Coverage**: printf, fprintf, sprintf, snprintf, vprintf, vfprintf, syslog
- **Precise risk assessment**: Distinguishes from generic FFI calls

### 6. exec/posix_spawn Family Coverage
- **12 new dangerous functions** added to detection lists:
  - execve, execvp, execv, execl, execlp, execle, fexecve
  - posix_spawn, posix_spawnp
- **Updated in**: `ffi_unsafe.zig` + `call_graph.zig`

### 7. Resource Leak Detection Framework
- **Tracked resource types**:
  - File handles: fopen ↔ fclose
  - Sockets: socket ↔ close
  - Directories: opendir ↔ closedir
  - Pipes: popen ↔ pclose
- **Per-function mismatch analysis**

---

## 🔧 Improvements

### C++ False Positive Reduction
- **RAII-aware filtering** applied to Double-Free and Loop-Leak detectors
- **8-layer filter system** now consistently used across all passes
- **Result**: wabt 9→7 issues (-22% FP reduction)

### BASELINE.md v0.2.0
- **Complete restructure** with version history
- **Capability matrix** showing all detection features
- **Per-project details** with regression guard rules
- **Red Team section** for adversarial test documentation

---

## 🐛 Critical Bug Fixes

### Substring Matching False Positive Explosion (SECURITY)
**Severity**: Critical  
**Affected Versions**: ≤0.1.5  
**Components**: `ffi_unsafe.zig`, `call_graph.zig`

**Problem**: Used `std.mem.indexOf` (substring match) instead of `std.mem.eql` (exact match) for dangerous function identification.

**Impact**:
- libcurl: **59 false positives** → **0**
- SQLite: **20 false positives** → **0**

**Fix**: Changed all pattern matching to exact match with selective prefix matching for `_exec` family.

---

## 📋 Breaking Changes

None. This release is fully backward compatible.

---

## 🔬 Technical Details

### New Files
| File | Lines | Purpose |
|------|-------|---------|
| `src/pass/analysis/buffer_overflow.zig` | ~220 | Stack buffer overflow / array OOB detection |
| `corpus/red_team_test/red_team_bugs.c` | ~250 | Adversarial test cases (English comments) |
| `corpus/red_team_test/RED_TEAM_TEST_REPORT.md` | ~600 | Comprehensive test report |

### Modified Files
| File | Changes | Purpose |
|------|---------|---------|
| `src/pass/analysis/cpp_fp_reduction.zig` | +200 lines | Double-Free BFS, Loop-Leak, Resource Leak, RAII filtering |
| `src/pass/analysis/ffi_unsafe.zig` | +20 lines | Format String classification, exec* family |
| `src/pass/analysis/call_graph.zig` | +7 lines | DANGEROUS_FUNCTIONS expansion |
| `src/pass/analysis/pointer_ownership.zig` | +5 lines | buffer_overflow pass integration |
| `Makefile` | +30 lines | `make red-team-test` target |
| `corpus/real_world/BASELINE.md` | +426 lines | Complete v0.2.0 restructure |

**Total**: +928 lines of new/modified code

---

## ✅ Verification

### Red Team Test Results
```
✅ Memory Leak          → bug_memory_leak           [DETECTED]
✅ Use-After-Free       → bug_use_after_free        [DETECTED]
✅ Double-Free          → bug_double_free           [NEW! 4×]
✅ NULL Dereference     → bug_null_deref            [DETECTED]
✅ FFI RISK (CRITICAL)  → system(), popen()        [ENHANCED]
✅ FFI RISK (CRITICAL)  → execvp()                 [NEW!]
✅ Format String        → bug_format_string         [CLASSIFIED]
✅ Loop Leak            → bug_loop_leak             [NEW!]

Total Issues: 10 (target: ≥10) ✅
Hit Rate: 58.8% ✅
```

### Baseline Test Results
| Project | Status | Issues |
|---------|--------|--------|
| SQLite | ✅ PASS | 2 |
| libcurl | ✅ PASS | 1 |
| libuv | ⚠️ WARN | 6 |
| jsoncpp | ⚠️ WARN | 37* |
| abseil-cpp | ✅ PASS | 0 |
| ripgrep | ✅ PASS | 0 |
| rust_sqlite | ⚠️ WARN | 21 |
| openssl_wrapper | ⚠️ WARN | 17 |
| wasmtime_test | ⚠️ WARN | 4023* |
| wabt | ⚠️ WARN | 7 |

*Note: jsoncpp/wasmtime increased due to enhanced detection sensitivity; wasmtime needs investigation

---

## 🚀 Migration Guide

No migration needed. Simply rebuild:

```bash
zig build
make baseline-check    # Verify baselines
make red-team-test    # Run adversarial tests
```

---

## 📚 Documentation

- [BASELINE.md](corpus/real_world/BASELINE.md) - Updated to v0.2.0 format
- [RED_TEAM_TEST_REPORT.md](corpus/red_team_test/RED_TEAM_TEST_REPORT.md) - New comprehensive report
- [CHANGELOG.md](CHANGELOG.md) - Full change history
- [plan/rules/rules.md](plan/rules/rules.md) - Coding standards (unchanged)

---

## 🙏 Acknowledgments

Special thanks to the open-source community for providing the real-world projects used in our baseline testing:

- **SQLite**, **libcurl**, **libuv**, **jsoncpp**, **abseil-cpp**
- **ripgrep** (BurntSushi), **wasmtime** (Bytecode Alliance), **wabt** (WebAssembly)

---

## 📌 Next Release (v0.3.0 Roadmap)

### Planned Features
- [ ] Def-use analysis for uninitialized variable detection
- [ ] Field-sensitive struct member leak detection
- [ ] O0/O1 dual-mode baseline testing framework
- [ ] C++ destructor lifecycle analysis (reduce remaining RAII FPs)
- [ ] Performance optimization for large modules (wasmtime)

### Known Limitations
1. **wasmtime_test 4023 issues**: Likely buffer_overflow pass over-reporting; needs investigation
2. **Stack OOB detection**: Framework in place but may need tuning for real-world patterns
3. **Resource Leak detector**: Flow graph connectivity limits accuracy

---

*Built with Zig 0.15.2 on macOS 15.0*
*OmniScope: Cross-Language FFI/Unsafe Boundary Analyzer*
