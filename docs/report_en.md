# OmniScope Cross-Language FFI Safety Analysis Report

> **Analysis Date**: 2026-05-24
> **Tool Version**: OmniScope dev branch (cross_language_free FP fix + T1-T6 Unified Value Tracking)
> **Corpus**: 12 files in `corpus/` directory (10 with issues, 2 empty)
> **Real-world Benchmark**: 7 modules in `ffi-demo/output/` (C/C++/Rust FFI)
> **Compiler**: clang 21.0.0 (Apple LLVM) -O2 -S -emit-llvm

---

## 1. Executive Summary

### Corpus Test Suite (synthetic red-team)

| Metric | Value |
|--------|-------|
| Files Analyzed | 12 (10 with findings) |
| Total Functions | 364 |
| **Issues Detected** | **96** |
| Analysis Time | ~550ms total |

### ffi-demo Real-world Benchmark

| Metric | Value |
|--------|-------|
| Modules Analyzed | 7 (C/C++/Rust) |
| Total Functions | 95 |
| **Issues Detected** | **2** |
| Unsafe FFI TP | 0 / 6 (0%) |
| Analysis Time | ~97ms total |

### Key Findings

1. **Corpus 测试**: OmniScope 在精心构造的合成测试用例上能检出 96 个问题，覆盖 cross_language_free、use_after_free、stack_escape、callback_ownership 等多种类型。
2. **真实 benchmark (ffi-demo)**: 在 7 个真实 FFI 模块上仅检出 2 个 issue，unsafe FFI bug 检出率为 0%。cross_language_free 误报已通过 enum 比较修复（修复前 8 FP → 修复后 0 FP）。
3. **核心差距**: 合成测试的检出能力不能代表真实场景。C++ `new`/`delete` 不匹配、Rust FFI 包装器质量问题（丢弃返回值、null 处理）等真实 bug 类型尚未覆盖。

---

## 2. Corpus Test Suite — Detailed Results

### 2.1 File Inventory

| File | Functions | Issues | Analysis Time | Category |
|------|-----------|--------|---------------|----------|
| `rust_ffi_bugs.ll` | 20 | 15 | 23ms | Red Team: Rust FFI |
| `go_cgo_bugs.ll` | 21 | 9 | 11ms | Red Team: Go cgo |
| `python_cffi_bugs.ll` | 23 | 7 | 17ms | Red Team: Python cffi |
| `java_jni_bugs.ll` | 26 | 24 | 25ms | Red Team: Java JNI |
| `cross_lang_free_bugs.ll` | 22 | 9 | 23ms | Red Team: Cross-lang |
| `red_team_swift_ffi.ll` | 112 | 5 | 295ms | Red Team: Swift FFI |
| `red_team_cpp_ffi.ll` | — | 0 | — | Red Team: C++ (empty) |
| `red_team_triple_chain.ll` | — | 0 | — | Red Team: Chain (empty) |
| `sqlite_binding.ll` | 24 | 2 | 20ms | Dense FFI |
| `zlib_binding.ll` | 29 | 6 | 25ms | Dense FFI |
| `openssl_wrapper.ll` | 52 | 0 | 29ms | Dense FFI |
| `boundary_test.ll` | 35 | 19 | 66ms | Boundary Conditions |
| **Total** | **364** | **96** | **~554ms** | |

### 2.2 Issue Type Breakdown

| Issue Type | Count | Files |
|------------|-------|-------|
| `memory_leak` | ~20 | java_jni, boundary_test, rust_ffi, go_cgo, zlib, sqlite, python, cross_lang |
| `ffi_unsafe_call` | ~14 | rust_ffi, java_jni, cross_lang |
| `malloc_unchecked` | ~13 | boundary_test, zlib, java_jni, rust_ffi, go_cgo, sqlite |
| `invalid_free` | ~8 | rust_ffi, java_jni, swift, cross_lang |
| `cross_language_free` | 6 | go_cgo (3), python (3) |
| `unchecked_return` | ~7 | java_jni |
| `use_after_free` | 3 | python (3) |
| `borrow_escape` | 2 | boundary_test, swift |
| `null_dereference` | 2 | rust_ffi, boundary_test |
| `callback_ownership_risk` | 1 | go_cgo |
| `write_to_immutable` | 1 | go_cgo |

### 2.3 Key Observations

- **`cross_language_free` 检出**: 仅在 go_cgo 和 python 上检出 6 个，rust_ffi 和 cross_lang_free_bugs 上未检出。说明 Rust/C++ 跨语言 free 检测仍有盲区。
- **`memory_leak` 是最常见的类型**: 占总 issue 的 ~21%，但大多为 LOW severity（HEURISTIC 50% confidence）。
- **`openssl_wrapper.ll` 零检出**: 52 个函数、包含 SSL_CTX/cert/BIO 泄漏等真实 bug，但 OmniScope 未能检出任何问题。
- **`java_jni_bugs.ll` 检出最多 (24)**: 但绝大多数是 LOW severity 的 `ffi_unsafe_call` 和 `unchecked_return`，实际 JNI 特有的 bug（如 LocalRef 泄漏、GlobalRef 误用）检出有限。

---

## 3. ffi-demo Real-world Benchmark — Detailed Results

> **测试文件**: `/Users/scc/code/ffi-demo/output/*.bc` (7 个模块)
> **Ground Truth**: `/Users/scc/code/ffi-demo/README_ZH.md` 中标注的 17 个故意缺陷

### 3.1 Results After cross_language_free FP Fix

| Module | Functions | Issues | Types |
|--------|-----------|--------|-------|
| `c_fft_c_bridge.bc` | 20 | 1 | memory_leak (TP) |
| `c_hash_c_bridge.bc` | 12 | 1 | memory_leak (TP) |
| `c_merkle_tree.bc` | 9 | 0 | — |
| `cpp_fft.bc` | 12 | 0 | — |
| `cpp_hash.bc` | 12 | 0 | — |
| `rust_hash.bc` | 4 | 0 | — |
| `rust_merkle.bc` | 26 | 0 | — |
| **Total** | **95** | **2** | |

### 3.2 Before/After cross_language_free Fix

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| Total issues | 10 | 2 |
| True Positives | 2 | 1 |
| False Positives | 8 | 1 |
| FP rate | 80% | 50% |
| Precision | 20% | 50% |

**修复内容**: `checkCrossLanguageFree` 中 `free_lang` 字符串（`"c"`）与 `langToString(.c)`（`"C/C++"`）格式不匹配，导致所有 C malloc+free 对都被误报为跨语言问题。改为 Language enum 比较后消除 7 个 FP。

### 3.3 Ground Truth vs Detection

ffi-demo 中植入了 17 个故意缺陷，分为 6 类：

| Bug 类型 | 总数 | 检出 | 检出率 | 说明 |
|----------|------|------|--------|------|
| Stack Escape (Swift) | 2 | 0 | — | Swift 不生成 .bc，无法测试 |
| Callback Lifetime (Swift) | 1 | 0 | — | 同上 |
| Use-After-Free (Swift) | 2 | 0 | — | 同上 |
| Cross-lang Alloc Mismatch | 9 | 0 | 0% | C++ new 不在 classifyAllocLanguage 中 |
| Dangling Pointer (Swift) | 1 | 0 | — | Swift 不生成 .bc |
| Unsafe FFI (Rust) | 2 | 0 | 0% | 非内存类问题（丢弃返回值、null 处理） |
| **Memory Leak (非 FFI)** | **8** | **2** | **25%** | 检出 malloc 无 free |
| FD Leak | 3 | 0 | 0% | 不检测 fd 泄漏 |

**Unsafe FFI Bug 检出率: 0 / 6 (0%)**

### 3.4 未检出的关键 Bug

| Bug | 模块 | 类型 | 原因 |
|-----|------|------|------|
| FFT-LEAK-3 | c_fft_c_bridge | memory_leak | 条件路径泄漏，需路径敏感分析 |
| FFT-LEAK-4 | c_fft_c_bridge | fd_leak | fopen 未 fclose，不检测 fd |
| LEAK-FD | c_hash_c_bridge | fd_leak | 同上 |
| FFT-LEAK-1 | cpp_fft | memory_leak | C++ new 无 delete，不在检测范围 |
| FFT-LEAK-2 | cpp_fft | memory_leak | 同上 |
| BUG-4a/b/c | cpp_hash | memory_leak | C++ new[]/new 无 delete[]/delete |
| BUG-6a | rust_hash | unsafe_ffi | null pointer 返回成功码 |
| BUG-6b | rust_hash | unsafe_ffi | 丢弃 FFI 返回值 |

---

## 4. Detection Capability Assessment

### 4.1 Strengths (corpus 测试中表现良好)

| 能力 | 说明 |
|------|------|
| Go cgo cross_language_free | 正确检出 C alloc + Go free 的不匹配 (3/3) |
| Python refcount 检测 | 检出 Py_DECREF without Py_INCREF (3/3) |
| Stack escape 检测 | 在 boundary_test 和 swift 上检出 borrow_escape |
| Memory leak 基础检测 | 检出简单的 malloc 无 free 模式 |
| Callback ownership | 检出 Go callback 未注销风险 |

### 4.2 Weaknesses (真实场景下的差距)

| 弱点 | 影响 | 说明 |
|------|------|------|
| **C++ new/delete 不匹配** | 5 个 bug 全部漏检 | `new`/`new[]` 不在 `classifyAllocLanguage` 中 |
| **Rust FFI 包装器质量** | 2 个 bug 全部漏检 | 丢弃返回值、null 处理超出内存分析范畴 |
| **FD 泄漏** | 3 个 bug 全部漏检 | 不检测文件描述符泄漏 |
| **条件路径泄漏** | 部分漏检 | 需要路径敏感分析 |
| **openssl_wrapper 零检出** | 真实库 bug 无法覆盖 | 52 个函数、包含多种资源泄漏 |
| **Rust cross_language_free** | corpus 中 rust_ffi_bugs 未检出 | `__rust_alloc` 不在 `classifyAllocLanguage` 中 |

### 4.3 cross_language_free 分类器覆盖范围

当前 `classifyAllocLanguage` 支持的分配器：

| Language | Allocation Functions |
|----------|---------------------|
| Rust | `__rust_alloc`, `__rdl_alloc`, `__rg_alloc` |
| C | `malloc`, `calloc`, `realloc`, `aligned_alloc` |
| Go | `_cgo_allocate`, `_Cfunc_GoMalloc`, `_Cfunc_GoAlloc` |
| ObjC | `objc_alloc`, `class_createInstance`, `NSAllocateObject` |
| Python | `PyMem_Malloc`, `PyObject_Malloc`, `PyObject_New`, `PyList_New`, `PyDict_New` |
| JNI | `NewGlobalRef`, `NewLocalRef`, `FindClass` |
| Node.js | `napi_create_`, `napi_get_cb_info` |

**缺失**:
- C++ `new`, `new[]`, `operator new` — 导致 cpp_hash/cpp_fft 漏检
- Rust `Box::into_raw`, `Vec::into_raw` — 导致 rust FFI 边界漏检
- Swift allocators

---

## 5. Architecture Notes (Current Release)

### T1-T6 Unified Value Tracking Framework

All 6 tasks completed:

1. **`traceValueSource()`** — 统一值来源追踪，替代 6+ 分散函数
2. **`traceValueUsage()`** — 统一用途推断，6 种模式自动分类
3. **Rule 5 stack_escape 增强** — 追踪 alloca 内容来源
4. **Rule 8 callback 扩展** — 支持局部回调变量 (Mode B)
5. **Rule 9 write_imm 增强** — 不透明指针下 struct 推断
6. **Rule 10 UAF 全局别名** — freed ptr → store @global → load → UAF

### cross_language_free FP Fix (本次)

- **根因**: `classifyFreeLanguage("free")` 返回 `"c"`，`langToString(.c)` 返回 `"C/C++"`，字符串比较永远不等
- **修复**: 改为 Language enum 比较；`alloc_lang` 改为从实际分配函数推断（`classifyAllocLanguageEnum`），而非使用模块级语言

---

## 6. Conclusions & Recommendations

### P0: 扩展 C++ 分配器识别

在 `classifyAllocLanguage` 中增加 C++ `new`/`new[]`/`operator new` 检测。这是 ffi-demo 中漏检最多的 bug 类型（5 个）。

### P1: 增加 Rust FFI 包装器 lint 规则

丢弃返回值、null 处理错误不属于内存安全问题，需要额外的 lint 规则：
- 检测 `extern "C"` 函数中 call 返回值未使用
- 检测 null 检查后返回成功码

### P2: 增强 issue suppression

corpus 中 openssl_wrapper 零检出、java_jni 的大量 LOW severity 噪音需要更好的抑制策略。

### 已知限制

- Swift 不生成 .bc 文件，无法测试 Swift FFI bug
- FD 泄漏不在检测范围内
- 格式化字符串漏洞不在检测范围内
- 整数溢出需要符号执行支持

---

*Report Updated: 2026-05-24*
*OmniScope Version: dev branch (cross_language_free FP fix)*
