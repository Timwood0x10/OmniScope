# Red Team Test Corpus Review

**Date**: 2026-05-29
**Reviewer**: Claude Code Agent

## Summary

The red_team_test corpus contains 9 .ll files (6,688 lines total) and 5 .bc-only files with .c sources. The overall quality is **good to excellent** -- these are real compiled LLVM IR from actual C, C++, and Swift compilers (Homebrew clang 21.1.8 and 22.1.5), not hand-written pseudocode. All files have proper module headers, debug info, and realistic instruction sequences. The test cases model genuine FFI bugs that occur in production code.

However, there are significant gaps: 5 test suites exist only as .bc bitcode with no .ll disassembly, some files share the same structural pattern (alloc-with-X, free-with-Y) without testing deeper analysis scenarios, and there is zero negative test coverage (safe code that should NOT trigger alerts).

## File-by-File Review

### cross_lang_free_bugs.ll (468 lines)
- **IR Validity**: PASS. Real clang-compiled C IR with full debug info, proper `target datalayout` and `target triple` (arm64-apple-macosx15.0.0). Functions have real instruction sequences with alloca, load/store, call, branches.
- **Bug Realism**: PASS. Tests 10 scenarios: Rust alloc -> C free, C alloc -> C++ delete, alias chain cross-lang, double cross-lang, realloc cross-lang, null pointer edge case, stack escape + cross-lang, mixed ownership, nested allocation. All are realistic.
- **Naming**: PASS. Functions like `bug_rust_alloc_c_free`, `bug_alias_chain_cross_lang`, `edge_case_null_ptr` clearly describe what they test.
- **Issues**:
  - `edge_case_null_ptr()` frees a null pointer -- this is defined behavior (free(NULL) is a no-op) and does not represent a bug. Flagging this as a "bug" would be a false positive.
  - `bug_mixed_ownership` does a memset then free on a rust_box_new pointer -- the memset is incidental; the real bug is the cross-lang free. The function name implies ownership semantics but the test is just a cross-lang free with extra steps.
- **Comment Quality**: Good. The printf strings serve as inline documentation ("Test 1: Rust alloc -> C free").
- **Verdict**: KEEP. Fix `edge_case_null_ptr` -- either remove it or relabel it as a "should-not-trigger" negative test.

### csharp_ffi_bugs.ll (150 lines)
- **IR Validity**: PASS. Real clang-compiled IR, minimal debug info (no `!dbg` annotations on instructions). Proper module header.
- **Bug Realism**: PASS. Tests .NET NativeAOT patterns: `Marshal_AllocHGlobal` -> `free()`, `malloc` -> `Marshal_FreeHGlobal`, `CoTaskMemAlloc` leak, `CoTaskMemAlloc` -> `free()`, `RhpNewFast` -> `free()`. These are real P/Invoke and COM interop bugs.
- **Naming**: PASS. `cs_01_csharp_alloc_c_free`, `cs_03_com_alloc_leak`, etc.
- **Issues**:
  - Only 150 lines, the smallest file. Only 7 functions (6 bugs + 1 safe).
  - Missing `cs_02_c_alloc_csharp_free` test -- the C source file describes it but the .ll only has `cs_02_c_alloc_csharp_free` which does `malloc -> Marshal_FreeHGlobal`. This is actually present and correct.
  - No test for `CoTaskMemFree` misuse, `LocalAlloc/LocalFree` mismatch, or `HeapAlloc/HeapFree` mismatch.
  - The .c source file (`csharp_ffi_bugs.c`) documents 7 test cases but the .ll has exactly 7 functions. Consistent.
- **Comment Quality**: Minimal -- no inline comments in the .ll file. The .c source has good comments.
- **Verdict**: KEEP. Consider expanding with Win32 API mismatch tests.

### go_cgo_bugs.ll (484 lines)
- **IR Validity**: PASS. Real clang-compiled IR with full debug info. Uses Go-specific types (`%struct.GoSlice`, `%struct.GoString`). Proper module header.
- **Bug Realism**: PASS. Tests CGo patterns: `_cgo_allocate` -> `free()`, `malloc` -> `_cgo_free`, slice escape with dangling pointer, data race on shared counter via pthread, stored callback use-after-free, double free with `_Cfunc_GoMalloc`/`_Cfunc_GoFree`, Go string mutation, C pointer in Go struct.
- **Naming**: PASS. `go_01_go_alloc_c_free` through `go_08_c_ptr_in_go_struct`.
- **Issues**:
  - `go_04_race_test` tests a data race using `volatile` loads/stores and pthreads. This is a real concurrency bug but may be hard for a static analyzer to detect reliably. Worth having but expect low recall.
  - `go_05_register_callback` / `go_05_invoke_stored` test a stored callback pattern. The "bug" is implicit -- if the callback is freed between register and invoke, it's use-after-free. But the test doesn't actually free the callback, so the UAF is not demonstrated in the IR.
  - `go_07_mutate_go_string` mutates a Go string's data pointer directly -- this violates Go's string immutability. Realistic bug.
- **Comment Quality**: Good. Debug info provides source line numbers.
- **Verdict**: KEEP. The callback test (go_05) needs the actual free to demonstrate the bug.

### java_jni_bugs.ll (525 lines)
- **IR Validity**: PASS. Real clang-compiled IR with full debug info. Uses JNI function names (`NewGlobalRef`, `GetStringUTFChars`, `GetPrimitiveArrayCritical`). Proper module header.
- **Bug Realism**: PASS. Tests JNI patterns: global ref leak, GetStringUTFChars without ReleaseStringUTFChars, use-after-ReleaseStringUTFChars, critical section violation (JNI call inside GetPrimitiveArrayCritical), type confusion (byte[] accessed as int*), C struct handle use-after-free, no exception check, wrong free (C free on JNI elements).
- **Naming**: PASS. `jni_01_global_ref_leak` through `jni_08_wrong_free`.
- **Issues**:
  - `jni_06_init_struct` / `jni_06_get_handle` / `jni_06_cleanup_struct` / `jni_06_use_handle` test a handle-based pattern where a C struct is passed to Java as an integer handle. The bug is that `jni_06_use_handle` uses the handle after `jni_06_cleanup_struct` frees it. However, the test doesn't actually call cleanup before use_handle -- the UAF exists only if these are called in sequence, which is not shown in the IR.
  - `jni_05_type_confusion` accesses `GetByteArrayElements` result as `i32*` -- this is a real type confusion but at the IR level it's just pointer arithmetic, which may not trigger type-based analysis.
- **Comment Quality**: Good. Debug info provides source context.
- **Verdict**: KEEP. The handle use-after-free test (jni_06) should call cleanup before use_handle to make the bug explicit.

### python_cffi_bugs.ll (392 lines)
- **IR Validity**: PASS. Real clang-compiled IR with full debug info. Uses Python C API functions (`PyList_GetItem`, `Py_DECREF`, `PyBytes_FromStringAndSize`). Proper module header.
- **Bug Realism**: PASS. Tests Python reference counting bugs: borrowed ref DECREF (PyList_GetItem returns borrowed ref, DECREF corrupts it), new ref leak (PyBytes_FromStringAndSize never DECREFed), use-after-DECREF, steal ref misuse (PyTuple_SetItem steals ref, then use-after-steal), cache without INCREF (global stores borrowed ref without INCREF), free Python memory (C free on Python-managed buffer), callback no GIL, ctypes wrong free.
- **Naming**: PASS. `py_01_borrowed_ref_decref` through `py_08_ctypes_wrong_free`.
- **Issues**:
  - `py_04_steal_ref_misuse` is subtle -- `PyTuple_SetItem` steals the reference to `val1`, then `PyLong_AsLong(val1)` uses the stolen reference. This is a real bug but requires understanding that `PyTuple_SetItem` steals.
  - `py_07_callback_no_gil` tests calling a Python callback without holding the GIL. The IR doesn't show GIL acquisition/release, so this is more of a semantic bug than an IR-level pattern.
- **Comment Quality**: Good. Debug info provides source context.
- **Verdict**: KEEP.

### red_team_cpp_ffi.ll (1864 lines)
- **IR Validity**: PASS. Real clang-compiled C++ IR with full exception handling (`invoke`/`landingpad`/`resume`), C++ name mangling, vtables, shared_ptr internals. Uses clang 22.1.5 (different from other files). Proper module header.
- **Bug Realism**: PASS. Tests C++ FFI bugs: `new[]` -> `delete` (array/scalar mismatch), exception thrown through C callback (C++ exception crosses FFI boundary), wrong deleter (unique_ptr with C-allocated memory), missing virtual destructor (Derived deleted through Base pointer), shared_ptr cycle (memory leak), exception in callback (C callback throws, C++ catches but leaks), placement new leak (C-allocated memory with placement new, then C free), constructor throw leak.
- **Naming**: PASS. Mangled C++ names like `_Z36cpp_bug_01_new_array_delete_mismatchv` (demangled: `cpp_bug_01_new_array_delete_mismatch()`).
- **Issues**:
  - This is the most complex file and tests real C++ patterns that other files don't cover.
  - `cpp_bug_02_throw_through_cv` tests a C++ exception thrown through a C callback boundary -- this is a real and dangerous pattern. The IR shows proper `invoke`/`landingpad` handling.
  - `cpp_bug_05_shared_ptr_cyclev` creates a circular reference between two `shared_ptr<Node>` objects. This is a classic memory leak.
  - The file includes full libc++ implementation details (make_shared, shared_ptr constructors/destructors, swap, etc.). This makes it very realistic but also very large.
- **Comment Quality**: Minimal inline comments. The .c source file has excellent documentation.
- **Verdict**: KEEP. This is the strongest test file in the corpus.

### red_team_swift_ffi.ll (1935 lines)
- **IR Validity**: PASS. Real Swift-compiled IR with Swift runtime calls (`swift_retain`, `swift_release`, `swift_unownedRetain`, `swift_weakInit`), Swift calling convention (`swiftcc`), ObjC interop. Proper module header.
- **Bug Realism**: PASS. Tests Swift FFI bugs: unowned reference use-after-free, weak reference race condition, raw pointer use-after-free (C allocation freed, then Swift UnsafeRawPointer.load), NSString bridge over-release, pointer escape through global, ObjC callback safety, array buffer escape.
- **Naming**: PASS. Swift-mangled names like `$s18red_team_swift_ffi0C19_bug_01_unowned_uafyyF` (demangled: `red_team_swift_ffi.bug_01_unowned_uaf()`).
- **Issues**:
  - This file is extremely large (1935 lines) due to Swift runtime boilerplate. The actual bug test functions are a small fraction of the total IR.
  - The Swift IR is very different from C/C++ IR -- it uses `swiftcc` calling convention, has extensive metadata tables, and calls Swift runtime functions. This is valuable for testing OmniScope's Swift support.
  - `bug_03_raw_ptr_uaf` is the clearest bug: allocates with `c_ffi_alloc`, frees with `c_ffi_free`, then calls `UnsafeRawPointer.load(as: UInt8.self)` on the freed pointer.
  - `bug_04_bridge_over_release` tests NSString/bridging lifecycle issues -- complex but realistic.
- **Comment Quality**: No inline comments. Debug info is present but Swift-mangled names are hard to read.
- **Verdict**: KEEP. Consider adding demangled function names as comments for readability.

### red_team_triple_chain.ll (553 lines)
- **IR Validity**: PASS. Real clang-compiled C IR with Go/Rust runtime function stubs. Proper module header.
- **Bug Realism**: PASS. Tests multi-language chain bugs: Go alloc -> C free -> Go free (double free), Rust Box -> Go free -> Rust drop (double free), Rust &mut ref stored in C global (borrow escape), ownership lost across Go/C/Rust (memory leak), dangling pointer through chain, double free in Go and Rust, data race Go <-> Rust via C (pthread), full Go->C->Rust->C->Go chain with use-after-free.
- **Naming**: PASS. `chain_01_go_alloc_c_free` through `chain_08_full_chain_triple_bug`.
- **Issues**:
  - This is the most architecturally interesting file -- it tests bugs that span 3+ languages.
  - `chain_07_data_race` uses pthreads to create a real data race between a "Rust thread" and the main thread. The Rust thread reads while the main thread writes.
  - `chain_08_full_chain_triple_bug` passes data through Go->C->Rust->C->Go, with Rust keeping a copy that becomes dangling after Go frees. Excellent test.
  - The file includes helper functions (`go_alloc`, `go_free`, `rust_alloc`, `rust_dealloc`, `rust_box_new`, `rust_box_drop`, `c_bridge_process_go_data`, `c_bridge_pass_rust_to_go`) that simulate runtime behavior. These are implemented as simple malloc/free wrappers with printf logging.
- **Comment Quality**: Excellent. Printf strings document each step ("[Go] runtime.alloc(256) -> 0x...", "[C] Received Go slice: data=0x..., len=...").
- **Verdict**: KEEP. Best-documented file in the corpus.

### rust_ffi_bugs.ll (317 lines)
- **IR Validity**: PASS. Real clang-compiled C IR with Rust runtime function stubs. Full debug info. Proper module header.
- **Bug Realism**: PASS. Tests Rust FFI bugs: Rust alloc -> C free, C alloc -> Rust dealloc, Box::into_raw -> C free (should use Box::from_raw), store Rust reference in global then use-after-free, String::into_raw leak, double free (Rust dealloc then C free), mutable alias escape (two pointers to same Rust allocation), realloc on Rust allocation then Rust dealloc.
- **Naming**: PASS. `rust_01_alloc_c_free` through `rust_08_realloc_cross`.
- **Issues**:
  - `rust_05_string_leak` tests `String::into_raw` without `String::from_raw` -- this is a real leak pattern in Rust FFI.
  - `rust_07_mut_alias_escape` creates two pointers to the same Rust allocation and writes through both -- this violates Rust's aliasing rules but at the IR level it's just two stores to the same address.
  - Uses `_RZN4alloc5alloc17h_allocate` and `_RZN4alloc5alloc17h_deallocate` as Rust allocator stubs. These look like mangled Rust names but are simplified.
- **Comment Quality**: Good. Debug info provides source context.
- **Verdict**: KEEP.

## Files Missing .ll (BC-only)

These 5 test suites have .c source files and .bc bitcode but no .ll disassembly:

### cpp_operator_new_ffi_bugs.bc
- **Source quality**: Excellent. Well-documented .c source with 6 test cases covering new/delete mismatches, new[]/delete mismatches, and internal leak detection.
- **Missing .ll**: Should be disassembled with `llvm-dis`.

### csharp_win32_ffi_bugs.bc
- **Source quality**: Excellent. 7 test cases covering Marshal, CoTaskMem, HeapAlloc, LocalAlloc mismatches.
- **Missing .ll**: Should be disassembled.

### go_tinygo_ffi_bugs.bc
- **Source quality**: Excellent. 7 test cases covering TinyGo runtime.alloc/free, CGo bridge patterns.
- **Missing .ll**: Should be disassembled.

### rust_multi_lang_ffi_bugs.bc
- **Source quality**: Excellent. 7 test cases covering Rust <-> C# and Rust <-> Go cross-language bugs.
- **Missing .ll**: Should be disassembled.

### zig_cimport_ffi_bugs.bc
- **Source quality**: Excellent. 7 test cases covering Zig allocator patterns, PageAllocator, ArenaAllocator.
- **Missing .ll**: Should be disassembled.

## Cross-Cutting Issues

### 1. All .ll files are real compiled IR
Every .ll file has proper `target datalayout`, `target triple`, `source_filename`, and real instruction sequences. No stubs, no `ret void`-only functions, no pseudocode. This is a strength.

### 2. Structural repetition
Most test files follow the same pattern: `allocate_with_X, use, free_with_Y` where X and Y are from different language runtimes. While each file tests a different language pair, the bug pattern is identical across files. This means OmniScope's allocator/deallocator pairing analysis is tested repeatedly but other analysis types (data flow, taint, alias analysis) are tested less.

### 3. Missing negative tests
No file contains "safe" test cases that should NOT trigger alerts. The only safe cases are:
- `safe_c_alloc_c_free()` in cross_lang_free_bugs.ll
- `safe_rust_alloc_rust_free()` in cross_lang_free_bugs.ll
- `cs_safe_correct_pair()` in csharp_ffi_bugs.ll

These are insufficient. Every language pair should have a corresponding safe case to measure false positive rates.

### 4. Missing language coverage
- **Ruby**: No test cases for Ruby C extensions (ruby_xmalloc, xfree)
- **Haskell**: No test cases for Haskell FFI (Foreign.Marshal.Alloc)
- **Lua**: No test cases for Lua C API (lua_newuserdata, lua_alloc)
- **Kotlin/Native**: No test cases for Kotlin/Native FFI
- **D**: No test cases for D's @nogc and C interop
- **Nim**: No test cases for Nim's FFI

### 5. Missing bug type coverage
- **Buffer overflow across FFI boundary**: Not tested (e.g., C writes past buffer allocated by another language)
- **Format string bugs**: Not tested
- **Integer overflow in allocation size**: Not tested
- **TOCTOU (time-of-check-time-of-use)**: Not tested
- **Use of uninitialized memory across FFI**: Not tested

### 6. Platform specificity
All files target `arm64-apple-macosx15.0.0`. There are no x86_64, Linux, or Windows test cases. This may miss platform-specific ABI issues.

## Recommendations

### Critical (do immediately)
1. **Disassemble all .bc files to .ll**: Run `llvm-dis` on the 5 .bc-only files. Having .ll makes inspection and debugging much easier.
2. **Fix `edge_case_null_ptr`**: This tests free(NULL) which is defined behavior. Either remove it or relabel as a negative test case.
3. **Add negative test cases**: For each language pair, add a "safe" function that correctly pairs allocators. This is essential for measuring false positive rates.

### High Priority (next sprint)
4. **Fix implicit UAF tests**: In `go_05_register_callback`, `jni_06_*`, and similar tests where the UAF depends on call ordering, make the bug explicit by calling the free/cleanup before the use in the same function.
5. **Add buffer overflow cross-FFI tests**: Test cases where C code writes past a buffer allocated by Go/Rust/etc.
6. **Add x86_64 and Linux targets**: At minimum, recompile one test suite with `x86_64-unknown-linux-gnu` to test ABI differences.

### Medium Priority (backlog)
7. **Reduce Swift IR verbosity**: The swift file is 1935 lines but the actual bugs are ~200 lines of logic. Consider stripping runtime boilerplate or adding section markers.
8. **Add Ruby, Lua, Haskell test cases**: These are common FFI languages with known allocator patterns.
9. **Add format string and integer overflow tests**: These are CWE-134 and CWE-190 respectively -- common in FFI code.
10. **Standardize naming convention**: Some files use `bug_XX_name`, others use `chain_XX_name`, others use `tcN_name`. Pick one convention.

### Low Priority
11. **Add expected-findings metadata**: The triple_chain file prints expected OmniScope findings. Add this to all files as structured comments or a companion JSON.
12. **Add compiler version consistency**: Most files use clang 21.1.8, but red_team_cpp_ffi uses clang 22.1.5. This is fine but worth noting for reproducibility.
