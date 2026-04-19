# OmniScope Test Corpus - Expected Results

This document records the expected issues for each test file in the corpus.

## Directory Structure

```
corpus/
├── ffi-dense/           # FFI-heavy test cases
│   ├── sqlite_binding.c
│   ├── openssl_wrapper.c
│   └── zlib_binding.c
├── small/               # Quick FFI/unsafe tests
│   ├── rust_ffi_simple.rs
│   ├── zig_ffi_simple.zig
│   ├── go_ffi_simple.go
│   └── cpp_ffi_simple.cpp
├── medium/              # Boundary and edge case tests
│   └── boundary_test.c
└── large/               # Stress tests (~10K+ functions)
    └── stress_patterns.c
```

---

## small/rust_ffi_simple.rs

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `box_into_raw_leak` | leak | high | Box::into_raw without Box::from_raw |
| 2 | `cstring_into_raw_leak` | leak | high | CString::into_raw without CString::from_raw |
| 3 | `str_as_ptr_escape` | borrow_escape | critical | &str.as_ptr escape |
| 4 | `rust_alloc_c_free` | cross_lang_free_mismatch | high | Rust alloc, C free |

**Total Expected Issues: 4**

---

## small/zig_ffi_simple.zig

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `zig_alloc_c_free` | cross_lang_free_mismatch | high | Zig allocator, C free |
| 2 | `allocator_leak` | leak | medium | Zig allocator without free |
| 3 | `pointer_escape` | borrow_escape | critical | Pointer escape across FFI boundary |

**Total Expected Issues: 3**

---

## small/go_ffi_simple.go

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `CStringLeak` | leak | high | C.CString without C.free |
| 2 | `CMallocLeak` | leak | high | C.malloc without C.free |
| 3 | `CBytesLeak` | leak | high | C.CBytes without C.free |

**Total Expected Issues: 3**

---

## small/cpp_ffi_simple.cpp

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `cpp_new_c_free` | cross_lang_free_mismatch | high | C++ new, C free |
| 2 | `cpp_malloc_cpp_delete` | cross_lang_free_mismatch | high | C malloc, C++ delete |
| 3 | `raii_escape` | leak | high | RAII object escape |

**Total Expected Issues: 3**

---

## medium/boundary_test.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `null_ptr_ffi_boundary` | null_dereference | critical | Null pointer at FFI boundary |
| 2 | `zero_size_alloc` | boundary_error | medium | Zero-size allocation |
| 3 | `max_size_alloc` | boundary_error | high | Maximum size allocation |
| 4 | `negative_size_alloc` | boundary_error | high | Negative size cast |
| 5 | `buffer_at_overflow` | buffer_overflow | critical | Buffer overflow at boundary |
| 6 | `create_circular_ownership` | leak | high | Circular ownership reference |
| 7 | `ffi_double_free` | double_free | critical | Double free at FFI boundary |
| 8 | `ffi_use_after_free` | use_after_free | critical | Use after free at FFI boundary |
| 9 | `ownership_transfer_to_null` | null_dereference | critical | Transfer to NULL pointer |
| 10 | `ffi_in_error_path` | leak | medium | FFI allocation in error path |
| 11 | `nested_ffi_partial_cleanup` | leak | high | Nested FFI with partial cleanup |
| 12 | `ffi_loop_early_exit` | leak | high | FFI loop with early exit |
| 13 | `mixed_allocation_sources` | leak | high | Mixed allocation sources |
| 14 | `ffi_format_string` | format_string | high | FFI with format string |
| 15 | `ffi_buffer_overflow` | buffer_overflow | critical | FFI with buffer overflow |
| 16 | `allocation_size_overflow` | boundary_error | high | Allocation size overflow |
| 17 | `ffi_realloc` | unsafe_operation | high | Realloc on FFI pointer |
| 18 | `ffi_ptr_escape` | leak | medium | FFI pointer escape through return |
| 19 | `store_ffi_ptr_global` | leak | medium | FFI pointer stored in global |
| 20 | `concurrent_ffi_allocs` | leak | high | Concurrent FFI allocations |

**Total Expected Issues: 20**

---

## large/stress_patterns.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1-20 | `ffi_alloc_01` through `ffi_alloc_20` | leak | high | FFI allocation without free |
| 21-40 | `ffi_mismatch_01` through `ffi_mismatch_20` | cross_lang_free_mismatch | high | C alloc, Rust free |
| 41-60 | `ffi_chain_01` through `ffi_chain_20` | leak | high | FFI ownership transfer chains |
| 61 | `create_ffi_bundle` | leak | high | Complex nested FFI structure |
| 62 | `cross_lang_transfer` | leak | medium | Cross-language ownership transfer |
| 63 | `recursive_ffi_alloc` | leak | high | Recursive FFI allocation |
| 64 | `loop_ffi_alloc` | leak | high | Loop FFI allocation |
| 65 | `create_complex_ffi_struct` | leak | high | FFI data flow through complex structure |
| 66 | `ffi_boundary_stress` | leak | high | FFI boundary crossing stress |
| 67-70 | `_Z12cpp_rust_mismatchv`, `_RZN12rust_c_mismatch...`, `zig_allocImpl_c_mismatch`, `c_zig_mismatch` | cross_lang_free_mismatch | high | Manual test functions with proper language naming patterns |

**Total Expected Issues: 70 (66 + 4 manual cross-language tests)**

**Note**: Cross-language ownership violations (cross_lang_free_mismatch) are now detected when functions use realistic language naming patterns (e.g., `_R` prefix for Rust, `_Z` prefix for C++, `allocImpl` for Zig). The PointerOwnershipPass was modified to identify language from callee function names instead of caller function names.

---

## ffi-dense/sqlite_binding.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `leak_database_open` | leak | high | sqlite3_open without sqlite3_close |
| 2 | `leak_statement` | leak | high | sqlite3_prepare_v2 without sqlite3_finalize |
| 3 | `bind_dangling_pointer` | use_after_free | critical | Binding freed memory to statement |
| 4 | `get_user_name_dangling` | dangling_pointer | critical | Returning pointer invalidated by finalize |
| 5 | `dangerous_exec` | unchecked_return | medium | sqlite3_exec return value not checked |
| 6 | `sql_injection` | format_string | high | sprintf with user input (injection + overflow) |

**Total Expected Issues: 6**

---

## ffi-dense/openssl_wrapper.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `encrypt_leak_ctx` | leak | high | EVP_CIPHER_CTX_new without EVP_CIPHER_CTX_free |
| 2 | `bio_leak` | leak | medium | BIO_new without BIO_free |
| 3 | `rsa_key_leak` | leak | high | RSA_new without RSA_free |
| 4 | `encrypt_unchecked` | unchecked_return | high | EVP_EncryptInit_ex return not checked |
| 5 | `weak_random` | weak_crypto | high | Predictable random seed |
| 6 | `password_handling` | sensitive_data | high | Password not zeroized |
| 7 | `ssl_ctx_leak` | leak | high | SSL_CTX_new without SSL_CTX_free |
| 8 | `x509_leak` | leak | medium | X509_new without X509_free |
| 9 | `unprotected_key` | sensitive_data | high | Private key in memory without encryption |
| 10 | `error_handling_bug` | leak | medium | BIO not freed on error path |

**Total Expected Issues: 10**

---

## ffi-dense/zlib_binding.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `inflate_leak` | leak | medium | inflateInit without inflateEnd |
| 2 | `deflate_leak` | leak | medium | deflateInit without deflateEnd |
| 3 | `compress_overflow` | buffer_overflow | critical | Unchecked output buffer size |
| 4 | `use_after_free_example` | use_after_free | critical | Using freed memory |
| 5 | `double_free_example` | double_free | critical | Potential double free on z_stream buffer |
| 6 | `uninit_stream_example` | uninit_memory | high | Uninitialized z_stream |
| 7 | `error_path_leak` | leak | medium | deflateEnd not called on error |
| 8 | `gzfile_leak` | leak | medium | gzopen without gzclose |
| 9 | `unchecked_gzread` | unchecked_return | medium | gzread return not checked |
| 10 | `invalid_compression_level` | invalid_param | low | Compression level out of range |

**Total Expected Issues: 10**

---

## ffi-dense/rust_sqlite_ffi.rs

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `leak_database` | leak | high | sqlite3_open without sqlite3_close |
| 2 | `leak_statement` | leak | high | sqlite3_prepare_v2 without sqlite3_finalize |
| 3 | `leak_cstring` | leak | medium | CString::into_raw without from_raw |
| 4 | `use_after_free` | use_after_free | critical | Dangling pointer after sqlite3_finalize |
| 5 | `null_pointer_deref` | null_deref | critical | Using null stmt pointer |
| 6 | `double_close` | double_free | critical | sqlite3_close called twice |
| 7 | `sql_injection` | injection | high | SQL injection via format string |

**Total Expected Issues: 7**

---

## Summary Statistics

| Corpus Directory | File | Expected Issues | Critical | High | Medium | Low |
|------------------|------|-----------------|----------|------|--------|-----|
| small/ | rust_ffi_simple.rs | 4 | 1 | 3 | 0 | 0 |
| small/ | zig_ffi_simple.zig | 3 | 1 | 2 | 0 | 0 |
| small/ | go_ffi_simple.go | 3 | 0 | 3 | 0 | 0 |
| small/ | cpp_ffi_simple.cpp | 3 | 0 | 3 | 0 | 0 |
| medium/ | boundary_test.c | 20 | 6 | 11 | 3 | 0 |
| large/ | stress_patterns.c | 70 | 0 | 70 | 0 | 0 |
| ffi-dense/ | sqlite_binding.c | 6 | 2 | 3 | 1 | 0 |
| ffi-dense/ | openssl_wrapper.c | 10 | 0 | 7 | 3 | 0 |
| ffi-dense/ | zlib_binding.c | 10 | 3 | 1 | 5 | 1 |
| ffi-dense/ | rust_sqlite_ffi.rs | 7 | 3 | 3 | 1 | 0 |
| **Total** | **10 files** | **136** | **16** | **106** | **13** | **1** |

---

## Issue Type Distribution

| Issue Type | Count |
|------------|-------|
| leak | 67 |
| cross_lang_free_mismatch | 27 |
| use_after_free | 4 |
| double_free | 2 |
| buffer_overflow | 3 |
| format_string | 4 |
| borrow_escape | 3 |
| null_dereference | 2 |
| boundary_error | 4 |
| unsafe_operation | 1 |
| dangling_pointer | 1 |
| unchecked_return | 1 |
| injection | 1 |
| weak_crypto | 1 |
| sensitive_data | 2 |
| uninit_memory | 1 |
| invalid_param | 1 |

---

## Usage

```bash
# Compile corpus to LLVM IR
make corpus-ir

# Run OmniScope on corpus
make corpus-analyze

# Generate report
make corpus-report
```

---

## Adding New Test Cases

1. Create source file in appropriate corpus directory
2. Add expected issues to this file
3. Update Makefile with build rules
4. Run `make corpus-check` to verify detection rates
