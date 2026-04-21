# Real-World FFI Test Scenarios

This directory contains test cases for real-world FFI scenarios using popular C libraries.

## Test Files

### openssl_ffi.c

Tests OpenSSL EVP API patterns:

| Function | Issue Type | Severity |
|----------|------------|----------|
| `create_cipher_context` | Missing EVP_CIPHER_CTX_free | HIGH |
| `encrypt_data` | Context leak on error | MEDIUM |
| `generate_key` | Unchecked RAND_bytes return | MEDIUM |
| `process_with_cleanup` | Double free | CRITICAL |
| `create_bio_buffer` | Missing BIO_free | HIGH |
| `load_private_key` | BIO leak on error | MEDIUM |
| `compute_hmac` | Static buffer (not thread-safe) | LOW |
| `create_ssl_context` | Missing SSL_CTX_free | HIGH |

### sqlite_ffi.c

Tests SQLite C API patterns:

| Function | Issue Type | Severity |
|----------|------------|----------|
| `open_database` | Missing sqlite3_close | HIGH |
| `query_users` | Statement leak on error | MEDIUM |
| `execute_query` | Correct error handling | - |
| `build_query` | Missing sqlite3_free | MEDIUM |
| `read_blob` | Correct BLOB handling | - |
| `transfer_funds` | Missing ROLLBACK on error | HIGH |
| `backup_database` | Backup finish on error | MEDIUM |
| `build_dynamic_query` | Memory leak | MEDIUM |

### zlib_ffi.c

Tests zlib compression patterns:

| Function | Issue Type | Severity |
|----------|------------|----------|
| `compress_data` | Correct deflateEnd | - |
| `decompress_data` | Correct inflateEnd | - |
| `compress_file` | gzclose on error | MEDIUM |
| `decompress_file` | Resource cleanup | - |
| `compressor_init/process/cleanup` | Struct pattern | - |
| `write_compressed_log` | Format string potential | LOW |

## Running Tests

```bash
# Build and analyze
make real-world-test

# Expected results:
# - OpenSSL: ~8 issues detected
# - SQLite: ~6 issues detected
# - zlib: ~3 issues detected
```

## Issue Categories

1. **Memory Leaks** - Missing free/close/finalize calls
2. **Double Free** - Freeing same pointer twice
3. **Error Handling** - Missing cleanup on error paths
4. **Resource Ownership** - Unclear ownership transfer
5. **Thread Safety** - Static buffers in multi-threaded context

## Lessons Learned

### OpenSSL
- Always pair `EVP_*_new()` with `EVP_*_free()`
- Use `ERR_print_errors_fp()` for debugging
- Check return values of all EVP functions

### SQLite
- Always call `sqlite3_finalize()` for prepared statements
- Use `sqlite3_mprintf()` for safe SQL construction
- Implement proper transaction rollback

### zlib
- Always pair `deflateInit()` with `deflateEnd()`
- Always pair `inflateInit()` with `inflateEnd()`
- Use `deflateBound()` for buffer sizing
