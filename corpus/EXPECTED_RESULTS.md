# OmniScope Test Corpus - Expected Results

This document records the expected issues for each test file in the corpus.

## Directory Structure

```
corpus/
├── ffi-dense/           # FFI-heavy test cases
│   ├── sqlite_binding.c
│   ├── openssl_wrapper.c
│   ├── zlib_binding.c
│   └── rust_sqlite_ffi.rs
├── small/               # Quick tests (~100 functions)
│   └── simple_ffi.c
├── medium/              # Realistic projects (~1K functions)
│   └── network_ffi.c
└── large/               # Stress tests (~10K+ functions)
    └── stress_patterns.c
```

---

## small/simple_ffi.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `leak_example` | leak | high | malloc without free |
| 2 | `use_after_free_example` | use_after_free | critical | Use after free |
| 3 | `buffer_overflow_example` | buffer_overflow | critical | strcpy without bounds check |
| 4 | `format_string_example` | format_string | high | printf with user input |

**Total Expected Issues: 4**

---

## medium/network_ffi.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1 | `create_socket_leak` | leak | high | socket without close |
| 2 | `accept_connection_leak` | leak | high | accept without close |
| 3 | `read_and_free` | use_after_free | critical | Potential use after free |
| 4 | `process_data` | use_after_free | critical | Use after free in log |
| 5 | `copy_address` | buffer_overflow | critical | strcpy without bounds |
| 6 | `log_connection` | format_string | high | printf with user input |
| 7 | `execute_user_command` | command_injection | critical | system with user input |
| 8 | `send_data_unchecked` | unchecked_return | medium | send return not checked |

**Total Expected Issues: 8**

---

## large/stress_patterns.c

| Bug # | Function | Issue Type | Severity | Description |
|-------|----------|------------|----------|-------------|
| 1-10 | `leak_func_XX` | leak | high | 10 leak functions |
| 11-20 | `uaf_func_XX` | use_after_free | critical | 10 UAF functions |
| 21-30 | `overflow_func_XX` | buffer_overflow | critical | 10 overflow functions |
| 31-40 | `format_func_XX` | format_string | high | 10 format string functions |
| 41-50 | `double_free_func_XX` | double_free | critical | 10 double free functions |
| 51 | `create_data_struct_leak` | leak | high | Struct allocation leak |
| 52 | `access_after_free` | use_after_free | critical | Access after struct free |
| 53 | `copy_to_struct` | buffer_overflow | critical | Overflow in struct copy |
| 54 | `log_data_struct` | format_string | high | Format string in log |
| 55 | `execute_data_command` | command_injection | critical | Command injection |
| 56 | `recursive_leak` | leak | high | Leak in recursion |
| 57 | `loop_leak` | leak | high | Leak in loop |
| 58 | `conditional_leak` | leak | high | Conditional leak |
| 59 | `error_path_leak` | leak | high | Leak on error path |

**Total Expected Issues: 59**

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

| Corpus File | Expected Issues | Critical | High | Medium | Low |
|-------------|-----------------|----------|------|--------|-----|
| small/simple_ffi.c | 4 | 2 | 2 | 0 | 0 |
| medium/network_ffi.c | 8 | 4 | 3 | 1 | 0 |
| large/stress_patterns.c | 59 | 32 | 27 | 0 | 0 |
| sqlite_binding.c | 6 | 2 | 3 | 1 | 0 |
| openssl_wrapper.c | 10 | 0 | 7 | 3 | 0 |
| zlib_binding.c | 10 | 3 | 1 | 5 | 1 |
| rust_sqlite_ffi.rs | 7 | 3 | 3 | 1 | 0 |
| **Total** | **104** | **46** | **46** | **11** | **1** |

---

## Issue Type Distribution

| Issue Type | Count |
|------------|-------|
| leak | 13 |
| use_after_free | 2 |
| dangling_pointer | 1 |
| double_free | 2 |
| buffer_overflow | 1 |
| unchecked_return | 3 |
| format_string | 1 |
| injection | 1 |
| weak_crypto | 1 |
| sensitive_data | 2 |
| uninit_memory | 1 |
| null_deref | 1 |
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
