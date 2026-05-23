# OmniScope FFI-Demo TP/FP/FN Analysis Report

Date: 2026-05-23
OmniScope Version: 0.1.9
Test Corpus: ffi-demo (multi-language FFI interoperability test project)

## Ground Truth: Intentional Bugs from Source Code

### Memory Bugs (detectable by OmniScope)

| ID | File | Function | Bug Description | Category |
|----|------|----------|-----------------|----------|
| LEAK-FD | hash_c_bridge.c | seed_prng | fopen("/dev/urandom") never closed | fd leak |
| LEAK-MALLOC | hash_c_bridge.c | c_hash | free() inside if(len>0), empty input leaks | memory leak |
| LEAK-1 | hash.cpp | S0() | rotation_cache new[] never delete[] | memory leak |
| LEAK-2 | hash.cpp | CompressBlock() | ext new[] never delete[] | memory leak |
| LEAK-3 | hash.cpp | Hash() | PadHelper new never delete | memory leak |
| FFT-LEAK-1 | fft.cpp | InitTwiddle() | sin_table potentially leaked by caller | memory leak |
| FFT-LEAK-2 | fft.cpp | BitReverseTable() | error path leak | memory leak |
| FFT-LEAK-3 | fft_c_bridge.c | c_fft_forward() | fragile clone pattern | memory leak |
| FFT-LEAK-4 | fft_c_bridge.c | c_fft_test_signal() | log_fd fopen never fclose | fd leak |
| FFT-LEAK-5 | fft_c_bridge.c | c_fft_test_signal() | temp_buf malloc never free | memory leak |
| GO-LEAK-1 | go_hash_bridge.c | go_hash_bridge() | clone malloc never free | memory leak |
| GO-LEAK-2 | go_hash_bridge.c | go_hash_bridge() | pointless clone (same leak) | memory leak |
| GO-LEAK-3 | go_hash_bridge.c | go_fft_forward() | backup arrays never freed | memory leak |

### Logic/Algorithm Bugs (not in OmniScope scope)

| ID | File | Description |
|----|------|-------------|
| BUG[7-8] | rust_hash/lib.rs | Null pointer accepted, return value ignored |
| BUG[9-14] | rust_merkle/lib.rs | Silent failure, wrong level iteration, uppercase hex |
| BUG[17-20] | merkle_tree.c | Empty input, wrong level_start update |
| BUG[21-24] | go/main.go | Error ignored, wrong odd-leaf handling |
| BUG[25-33] | python/merkle_tree.py | Silent fallback, wrong hex, wrong exit code |

Note: Go and Python source files do not produce LLVM bitcode, so their bugs
cannot be detected by OmniScope regardless. The go_hash_bridge.c is compiled
as part of the Go cgo build and does not produce a standalone .bc file.
We exclude GO-LEAK-1/2/3 and all Go/Python logic bugs from the detectable
ground truth. This reduces the detectable ground truth to 10 bugs.

## OmniScope Detection Results

### Per-File Analysis

| File | Functions | Issues | Time |
|------|-----------|--------|------|
| c_fft_c_bridge.bc | 20 | 1 | 21ms |
| c_hash_c_bridge.bc | 12 | 1 | 6ms |
| c_merkle_tree.bc | 9 | 0 | 7ms |
| cpp_fft.bc | 12 | 0 | 9ms |
| cpp_hash.bc | 12 | 0 | 11ms |
| rust_hash.bc | 4 | 0 | 2ms |
| rust_merkle.bc | 26 | 0 | 35ms |

### Detected Issues

| # | Kind | Function | Message | Verdict |
|---|------|----------|---------|---------|
| 1 | memory_leak | c_fft_test_signal | heap allocation never freed | **TP** (FFT-LEAK-5) |
| 2 | memory_leak | c_hash | heap allocation never freed | **TP** (LEAK-MALLOC) |

## TP/FP/FN Analysis

### Detectable Ground Truth (memory bugs in C/C++/Rust bitcode)

| Bug ID | File | Expected | Detected? | Notes |
|--------|------|----------|-----------|-------|
| LEAK-FD | hash_c_bridge.c | fd leak | NO | OmniScope does not track fd leaks |
| LEAK-MALLOC | hash_c_bridge.c | memory leak | **YES** | TP: c_hash memory_leak |
| LEAK-1 | hash.cpp | static cache leak | NO | Static allocation, no cross-function tracking |
| LEAK-2 | hash.cpp | per-call leak in CompressBlock | NO | Local allocation freed on some paths |
| LEAK-3 | hash.cpp | PadHelper leak | NO | Opaque to IR-level analysis |
| FFT-LEAK-1 | fft.cpp | sin_table leak | NO | Requires inter-procedural ownership tracking |
| FFT-LEAK-2 | fft.cpp | error path leak | NO | No error path in current IR |
| FFT-LEAK-3 | fft_c_bridge.c | fragile clone | NO | Actually freed on success path |
| FFT-LEAK-4 | fft_c_bridge.c | fd leak | NO | OmniScope does not track fd leaks |
| FFT-LEAK-5 | fft_c_bridge.c | temp_buf leak | **YES** | TP: c_fft_test_signal memory_leak |
| GO-LEAK-1 | go_hash_bridge.c | clone leak | NO | No standalone .bc file (compiled via cgo) |
| GO-LEAK-2 | go_hash_bridge.c | pointless clone | NO | Same as GO-LEAK-1 |
| GO-LEAK-3 | go_hash_bridge.c | backup leak | NO | Same as GO-LEAK-1 |

### Summary (excluding Go/Python-only bugs)

| Metric | Value |
|--------|-------|
| True Positives (TP) | 2 |
| False Positives (FP) | 0 |
| False Negatives (FN) | 8 |
| Precision (TP / (TP + FP)) | **100%** (2/2) |
| Recall (TP / (TP + FN)) | **20%** (2/10) |
| F1 Score | **0.333** |

### FN Breakdown by Category

| Category | Count | Examples |
|----------|-------|----------|
| fd leak (not in scope) | 2 | LEAK-FD, FFT-LEAK-4 |
| static allocation leak | 1 | LEAK-1 |
| freed on success path | 1 | FFT-LEAK-3 |
| inter-procedural ownership | 2 | FFT-LEAK-1, FFT-LEAK-2 |
| opaque C++ allocation | 2 | LEAK-2, LEAK-3 |
| no standalone .bc | 3 | GO-LEAK-1, GO-LEAK-2, GO-LEAK-3 |
| conditional free | 0 | (LEAK-MALLOC is detected) |

### Key Observations

1. **Zero false positives**: All reported issues correspond to real bugs. This is
   by design — OmniScope prioritizes high-confidence findings over recall.

2. **fd leaks are out of scope**: OmniScope tracks heap memory allocation/free
   patterns, not file descriptor lifecycle. This is a known limitation.

3. **Separate .bc files break cross-file analysis**: Each .bc file is analyzed
   independently. GO-LEAK-1/2/3 are in go_hash_bridge.bc but the calling
   context is in Go source (no bitcode). Cross-BC linking is not supported.

4. **C++ new/delete is harder to track**: The `new`/`delete` operators map to
   `_Znwm`/`_ZdlPv` in LLVM IR. OmniScope's PointerOwnership currently focuses
   on malloc/free and Rust allocator patterns.

5. **Conditional free paths require path-sensitive analysis**: LEAK-MALLOC is
   detected because the malloc/free are in the same function with a simple
   conditional. More complex patterns (LEAK-2, LEAK-3) require path-sensitive
   data flow.

## Improvement Recommendations

1. **Add C++ new/delete tracking** in PointerOwnership to detect LEAK-1/2/3
2. **Add fd leak detection** for fopen/fclose pairs
3. **Improve inter-procedural ownership tracking** for FFT-LEAK-1/2
4. **Support multi-BC linking** for cross-file analysis
5. **Add path-sensitive conditional free analysis** for FFT-LEAK-3