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

***

## small/rust\_ffi\_simple.rs·

| Bug # | Function                | Issue Type                  | Severity | Scope      | Description                                   |
| ----- | ----------------------- | --------------------------- | -------- | ---------- | --------------------------------------------- |
| 1     | `box_into_raw_leak`     | leak                        | high     | ✅ in-scope | Box::into\_raw without Box::from\_raw         |
| 2     | `cstring_into_raw_leak` | leak                        | high     | ✅ in-scope | CString::into\_raw without CString::from\_raw |
| 3     | `str_as_ptr_escape`     | borrow\_escape              | critical | ✅ in-scope | \&str.as\_ptr escape                          |
| 4     | `rust_alloc_c_free`     | cross\_lang\_free\_mismatch | high     | ✅ in-scope | Rust alloc, C free                            |

**Total Expected Issues: 4 (all in-scope)**

***

## small/zig\_ffi\_simple.zig

| Bug # | Function           | Issue Type                  | Severity | Scope      | Description                        |
| ----- | ------------------ | --------------------------- | -------- | ---------- | ---------------------------------- |
| 1     | `zig_alloc_c_free` | cross\_lang\_free\_mismatch | high     | ✅ in-scope | Zig allocator, C free              |
| 2     | `allocator_leak`   | leak                        | medium   | ✅ in-scope | Zig allocator without free         |
| 3     | `pointer_escape`   | borrow\_escape              | critical | ✅ in-scope | Pointer escape across FFI boundary |

**Total Expected Issues: 3 (all in-scope)**

***

## small/go\_ffi\_simple.go

| Bug # | Function      | Issue Type | Severity | Scope      | Description              |
| ----- | ------------- | ---------- | -------- | ---------- | ------------------------ |
| 1     | `CStringLeak` | leak       | high     | ✅ in-scope | C.CString without C.free |
| 2     | `CMallocLeak` | leak       | high     | ✅ in-scope | C.malloc without C.free  |
| 3     | `CBytesLeak`  | leak       | high     | ✅ in-scope | C.CBytes without C.free  |

**Total Expected Issues: 3 (all in-scope)**

***

## small/cpp\_ffi\_simple.cpp

| Bug # | Function                | Issue Type                  | Severity | Scope      | Description          |
| ----- | ----------------------- | --------------------------- | -------- | ---------- | -------------------- |
| 1     | `cpp_new_c_free`        | cross\_lang\_free\_mismatch | high     | ✅ in-scope | C++ new, C free      |
| 2     | `cpp_malloc_cpp_delete` | cross\_lang\_free\_mismatch | high     | ✅ in-scope | C malloc, C++ delete |
| 3     | `raii_escape`           | leak                        | high     | ✅ in-scope | RAII object escape   |

**Total Expected Issues: 3 (all in-scope)**

***

## medium/boundary\_test.c

| Bug # | Function                     | Issue Type        | Severity | Scope          | Description                       |
| ----- | ---------------------------- | ----------------- | -------- | -------------- | --------------------------------- |
| 1     | `null_ptr_ffi_boundary`      | null\_dereference | critical | ✅ in-scope     | Null pointer at FFI boundary      |
| 2     | `zero_size_alloc`            | boundary\_error   | medium   | ❌ out-of-scope | Zero-size allocation              |
| 3     | `max_size_alloc`             | boundary\_error   | high     | ❌ out-of-scope | Maximum size allocation           |
| 4     | `negative_size_alloc`        | boundary\_error   | high     | ❌ out-of-scope | Negative size cast                |
| 5     | `buffer_at_overflow`         | buffer\_overflow  | critical | ❌ out-of-scope | Buffer overflow at boundary       |
| 6     | `create_circular_ownership`  | leak              | high     | ✅ in-scope     | Circular ownership reference      |
| 7     | `ffi_double_free`            | double\_free      | critical | ✅ in-scope     | Double free at FFI boundary       |
| 8     | `ffi_use_after_free`         | use\_after\_free  | critical | ✅ in-scope     | Use after free at FFI boundary    |
| 9     | `ownership_transfer_to_null` | null\_dereference | critical | ✅ in-scope     | Transfer to NULL pointer          |
| 10    | `ffi_in_error_path`          | leak              | medium   | ✅ in-scope     | FFI allocation in error path      |
| 11    | `nested_ffi_partial_cleanup` | leak              | high     | ✅ in-scope     | Nested FFI with partial cleanup   |
| 12    | `ffi_loop_early_exit`        | leak              | high     | ✅ in-scope     | FFI loop with early exit          |
| 13    | `mixed_allocation_sources`   | leak              | high     | ✅ in-scope     | Mixed allocation sources          |
| 14    | `ffi_format_string`          | format\_string    | high     | ❌ out-of-scope | FFI with format string            |
| 15    | `ffi_buffer_overflow`        | buffer\_overflow  | critical | ❌ out-of-scope | FFI with buffer overflow          |
| 16    | `allocation_size_overflow`   | boundary\_error   | high     | ❌ out-of-scope | Allocation size overflow          |
| 17    | `ffi_realloc`                | unsafe\_operation | high     | ❌ out-of-scope | Realloc on FFI pointer            |
| 18    | `ffi_ptr_escape`             | leak              | medium   | ✅ in-scope     | FFI pointer escape through return |
| 19    | `store_ffi_ptr_global`       | leak              | medium   | ✅ in-scope     | FFI pointer stored in global      |
| 20    | `concurrent_ffi_allocs`      | leak              | high     | ✅ in-scope     | Concurrent FFI allocations        |

**Total Expected Issues: 20 (14 in-scope, 6 out-of-scope)**

***

## large/stress\_patterns.c

| Bug # | Function                                                                                           | Issue Type                  | Severity | Scope      | Description                                                |
| ----- | -------------------------------------------------------------------------------------------------- | --------------------------- | -------- | ---------- | ---------------------------------------------------------- |
| 1-20  | `ffi_alloc_01` through `ffi_alloc_20`                                                              | leak                        | high     | ✅ in-scope | FFI allocation without free                                |
| 21-40 | `ffi_mismatch_01` through `ffi_mismatch_20`                                                        | cross\_lang\_free\_mismatch | high     | ✅ in-scope | C alloc, Rust free                                         |
| 41-60 | `ffi_chain_01` through `ffi_chain_20`                                                              | leak                        | high     | ✅ in-scope | FFI ownership transfer chains                              |
| 61    | `create_ffi_bundle`                                                                                | leak                        | high     | ✅ in-scope | Complex nested FFI structure                               |
| 62    | `cross_lang_transfer`                                                                              | leak                        | medium   | ✅ in-scope | Cross-language ownership transfer                          |
| 63    | `recursive_ffi_alloc`                                                                              | leak                        | high     | ✅ in-scope | Recursive FFI allocation                                   |
| 64    | `loop_ffi_alloc`                                                                                   | leak                        | high     | ✅ in-scope | Loop FFI allocation                                        |
| 65    | `create_complex_ffi_struct`                                                                        | leak                        | high     | ✅ in-scope | FFI data flow through complex structure                    |
| 66    | `ffi_boundary_stress`                                                                              | leak                        | high     | ✅ in-scope | FFI boundary crossing stress                               |
| 67-70 | `_Z12cpp_rust_mismatchv`, `_RZN12rust_c_mismatch...`, `zig_allocImpl_c_mismatch`, `c_zig_mismatch` | cross\_lang\_free\_mismatch | high     | ✅ in-scope | Manual test functions with proper language naming patterns |

**Total Expected Issues: 70 (all in-scope)**

**Note**: Cross-language ownership violations (cross\_lang\_free\_mismatch) are now detected when functions use realistic language naming patterns (e.g., `_R` prefix for Rust, `_Z` prefix for C++, `allocImpl` for Zig). The PointerOwnershipPass was modified to identify language from callee function names instead of caller function names.

***

## ffi-dense/sqlite\_binding.c

| Bug # | Function                 | Issue Type        | Severity | Scope          | Description                                    |
| ----- | ------------------------ | ----------------- | -------- | -------------- | ---------------------------------------------- |
| 1     | `leak_database_open`     | leak              | high     | ✅ in-scope     | sqlite3\_open without sqlite3\_close           |
| 2     | `leak_statement`         | leak              | high     | ✅ in-scope     | sqlite3\_prepare\_v2 without sqlite3\_finalize |
| 3     | `bind_dangling_pointer`  | use\_after\_free  | critical | ✅ in-scope     | Binding freed memory to statement              |
| 4     | `get_user_name_dangling` | dangling\_pointer | critical | ✅ in-scope     | Returning pointer invalidated by finalize      |
| 5     | `dangerous_exec`         | unchecked\_return | medium   | ❌ out-of-scope | sqlite3\_exec return value not checked         |
| 6     | `sql_injection`          | format\_string    | high     | ❌ out-of-scope | sprintf with user input (injection + overflow) |

**Total Expected Issues: 6 (4 in-scope, 2 out-of-scope)**

***

## ffi-dense/openssl\_wrapper.c

| Bug # | Function             | Issue Type        | Severity | Scope          | Description                                          |
| ----- | -------------------- | ----------------- | -------- | -------------- | ---------------------------------------------------- |
| 1     | `encrypt_leak_ctx`   | leak              | high     | ✅ in-scope     | EVP\_CIPHER\_CTX\_new without EVP\_CIPHER\_CTX\_free |
| 2     | `bio_leak`           | leak              | medium   | ✅ in-scope     | BIO\_new without BIO\_free                           |
| 3     | `rsa_key_leak`       | leak              | high     | ✅ in-scope     | RSA\_new without RSA\_free                           |
| 4     | `encrypt_unchecked`  | unchecked\_return | high     | ❌ out-of-scope | EVP\_EncryptInit\_ex return not checked              |
| 5     | `weak_random`        | weak\_crypto      | high     | ❌ out-of-scope | Predictable random seed                              |
| 6     | `password_handling`  | sensitive\_data   | high     | ❌ out-of-scope | Password not zeroized                                |
| 7     | `ssl_ctx_leak`       | leak              | high     | ✅ in-scope     | SSL\_CTX\_new without SSL\_CTX\_free                 |
| 8     | `x509_leak`          | leak              | medium   | ✅ in-scope     | X509\_new without X509\_free                         |
| 9     | `unprotected_key`    | sensitive\_data   | high     | ❌ out-of-scope | Private key in memory without encryption             |
| 10    | `error_handling_bug` | leak              | medium   | ✅ in-scope     | BIO not freed on error path                          |

**Total Expected Issues: 10 (6 in-scope, 4 out-of-scope)**

***

## ffi-dense/zlib\_binding.c

| Bug # | Function                    | Issue Type        | Severity | Scope          | Description                               |
| ----- | --------------------------- | ----------------- | -------- | -------------- | ----------------------------------------- |
| 1     | `inflate_leak`              | leak              | medium   | ✅ in-scope     | inflateInit without inflateEnd            |
| 2     | `deflate_leak`              | leak              | medium   | ✅ in-scope     | deflateInit without deflateEnd            |
| 3     | `compress_overflow`         | buffer\_overflow  | critical | ❌ out-of-scope | Unchecked output buffer size              |
| 4     | `use_after_free_example`    | use\_after\_free  | critical | ✅ in-scope     | Using freed memory                        |
| 5     | `double_free_example`       | double\_free      | critical | ✅ in-scope     | Potential double free on z\_stream buffer |
| 6     | `uninit_stream_example`     | uninit\_memory    | high     | ❌ out-of-scope | Uninitialized z\_stream                   |
| 7     | `error_path_leak`           | leak              | medium   | ✅ in-scope     | deflateEnd not called on error            |
| 8     | `gzfile_leak`               | leak              | medium   | ✅ in-scope     | gzopen without gzclose                    |
| 9     | `unchecked_gzread`          | unchecked\_return | medium   | ❌ out-of-scope | gzread return not checked                 |
| 10    | `invalid_compression_level` | invalid\_param    | low      | ❌ out-of-scope | Compression level out of range            |

**Total Expected Issues: 10 (6 in-scope, 4 out-of-scope)**

***

## ffi-dense/rust\_sqlite\_ffi.rs

| Bug # | Function             | Issue Type       | Severity | Scope          | Description                                    |
| ----- | -------------------- | ---------------- | -------- | -------------- | ---------------------------------------------- |
| 1     | `leak_database`      | leak             | high     | ✅ in-scope     | sqlite3\_open without sqlite3\_close           |
| 2     | `leak_statement`     | leak             | high     | ✅ in-scope     | sqlite3\_prepare\_v2 without sqlite3\_finalize |
| 3     | `leak_cstring`       | leak             | medium   | ✅ in-scope     | CString::into\_raw without from\_raw           |
| 4     | `use_after_free`     | use\_after\_free | critical | ✅ in-scope     | Dangling pointer after sqlite3\_finalize       |
| 5     | `null_pointer_deref` | null\_deref      | critical | ✅ in-scope     | Using null stmt pointer                        |
| 6     | `double_close`       | double\_free     | critical | ✅ in-scope     | sqlite3\_close called twice                    |
| 7     | `sql_injection`      | injection        | high     | ❌ out-of-scope | SQL injection via format string                |

**Total Expected Issues: 7 (6 in-scope, 1 out-of-scope)**

***

## Summary Statistics

| Corpus Directory | File                 | Expected Issues | In-Scope | Out-of-Scope | Critical | High   | Medium | Low   |
| ---------------- | -------------------- | --------------- | -------- | ------------ | -------- | ------ | ------ | ----- |
| small/           | rust\_ffi\_simple.rs | 4               | 4        | 0            | 1        | 3      | 0      | 0     |
| small/           | zig\_ffi\_simple.zig | 3               | 3        | 0            | 1        | 2      | 0      | 0     |
| small/           | go\_ffi\_simple.go   | 3               | 3        | 0            | 0        | 3      | 0      | 0     |
| small/           | cpp\_ffi\_simple.cpp | 3               | 3        | 0            | 0        | 3      | 0      | 0     |
| medium/          | boundary\_test.c     | 20              | 14       | 6            | 6        | 8      | 3      | 3     |
| large/           | stress\_patterns.c   | 70              | 70       | 0            | 0        | 70     | 0      | 0     |
| ffi-dense/       | sqlite\_binding.c    | 6               | 4        | 2            | 2        | 2      | 1      | 1     |
| ffi-dense/       | openssl\_wrapper.c   | 10              | 6        | 4            | 0        | 4      | 5      | 1     |
| ffi-dense/       | zlib\_binding.c      | 10              | 6        | 4            | 2        | 1      | 5      | 2     |
| ffi-dense/       | rust\_sqlite\_ffi.rs | 7               | 6        | 1            | 3        | 3      | 1      | 0     |
| **Total**        | **10 files**         | **136**         | **115**  | **21**       | **16**   | **99** | **18** | **8** |

***

## OmniScope Analysis Scope

OmniScope is an **FFI/Unsafe Boundary Analyzer**, not a general-purpose bug finder.
Benchmark metrics (Precision, Recall, F1) are calculated **only against in-scope issues**.

### In-Scope Issues (115 total) — What OmniScope Detects

| Category                        | Count | Detection Mechanism                            |
| ------------------------------- | ----- | ---------------------------------------------- |
| leak (resource lifecycle)       | 67    | Ownership tracking: alloc without free/reclaim |
| cross\_lang\_free\_mismatch     | 27    | Cross-language ownership violation detection   |
| use\_after\_free                | 4     | Lifetime state lattice + null check guards     |
| double\_free                    | 2     | Resource ID deduplication + lifetime tracking  |
| borrow\_escape                  | 3     | FFI boundary escape analysis                   |
| null\_dereference / null\_deref | 3     | Null check guard recognition + CFG propagation |
| dangling\_pointer               | 1     | Post-free pointer usage detection              |

### In-Scope Issues by File (current v0.1.8)

| File                 | Issues |
| -------------------- | ------ |
| cpp_ffi_simple.ll    | 6      |
| boundary_test.ll     | 16     |
| stress_patterns.ll   | 49     |
| openssl_wrapper.ll   | 9      |
| sqlite_binding.ll    | 5      |
| zlib_binding.ll      | 12     |
| rust_sqlite_ffi.ll   | 6      |

### Out-of-Scope Issues (21 total) — Not OmniScope's Responsibility

| Category          | Count | Reason                       | Would Require          |
| ----------------- | ----- | ---------------------------- | ---------------------- |
| buffer\_overflow  | 3     | Needs bounds analysis pass   | Value-range analysis   |
| format\_string    | 4     | Needs format string analysis | Taint + format parsing |
| boundary\_error   | 4     | Needs bounds checking        | Interval arithmetic    |
| unsafe\_operation | 1     | Generic unsafe pattern       | Pattern expansion      |
| unchecked\_return | 2     | Return value checking        | Error path analysis    |
| injection         | 1     | SQL injection                | Taint analysis         |
| weak\_crypto      | 1     | Cryptographic weakness       | Crypto pattern DB      |
| sensitive\_data   | 2     | Data exposure                | Data flow tracking     |
| uninit\_memory    | 1     | Uninitialized memory         | Def-use analysis       |
| invalid\_param    | 1     | Parameter validation         | Constraint solving     |

***

## Issue Type Distribution

| Issue Type                  | Count | Scope          |
| --------------------------- | ----- | -------------- |
| leak                        | 67    | ✅ in-scope     |
| cross\_lang\_free\_mismatch | 27    | ✅ in-scope     |
| use\_after\_free            | 4     | ✅ in-scope     |
| double\_free                | 2     | ✅ in-scope     |
| borrow\_escape              | 3     | ✅ in-scope     |
| null\_dereference           | 2     | ✅ in-scope     |
| null\_deref                 | 1     | ✅ in-scope     |
| dangling\_pointer           | 1     | ✅ in-scope     |
| buffer\_overflow            | 3     | ❌ out-of-scope |
| format\_string              | 4     | ❌ out-of-scope |
| boundary\_error             | 4     | ❌ out-of-scope |
| unsafe\_operation           | 1     | ❌ out-of-scope |
| unchecked\_return           | 2     | ❌ out-of-scope |
| injection                   | 1     | ❌ out-of-scope |
| weak\_crypto                | 1     | ❌ out-of-scope |
| sensitive\_data             | 2     | ❌ out-of-scope |
| uninit\_memory              | 1     | ❌ out-of-scope |
| invalid\_param              | 1     | ❌ out-of-scope |

***

## Usage

```bash
# Compile corpus to LLVM IR
make corpus-ir

# Run OmniScope on corpus
make corpus-analyze

# Generate report
make corpus-report
```

***

## Adding New Test Cases

1. Create source file in appropriate corpus directory
2. Add expected issues to this file
3. Update Makefile with build rules
4. Run `make corpus-check` to verify detection rates

