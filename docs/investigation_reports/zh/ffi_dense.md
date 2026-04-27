# FFI 密集型项目调查报告 v0.1.5

**测试日期**: 2026-04-25
**测试版本**: v0.1.5 (Zone Classification)
**测试项目**: zlib-binding, openssl-wrapper, sqlite-binding

---

## 1. 测试概述

### 1.1 项目信息

| 项目 | 语言 | 源码位置 | IR 文件 | Issues |
|------|------|----------|---------|--------|
| zlib-binding | C | `corpus/ffi-dense/zlib_binding.c` | `zlib_binding.ll` | 14 |
| openssl-wrapper | C | `corpus/ffi-dense/openssl_wrapper.c` | `openssl_wrapper.ll` | 7 |
| sqlite-binding | C | `corpus/ffi-dense/sqlite_binding.c` | `sqlite_binding.ll` | 4 |

### 1.2 Zone Classification 结果

**zlib-binding**:
```
  Total functions analyzed:    12
  Safe zone (skipped):         0 (0.0%)
  Unknown zone:                12
  Issues found:                14
```

**openssl-wrapper**:
```
  Total functions analyzed:    12
  Safe zone (skipped):         0 (0.0%)
  Unknown zone:                12
  Issues found:                7
```

**sqlite-binding**:
```
  Total functions analyzed:    8
  Safe zone (skipped):         0 (0.0%)
  Unknown zone:                8
  Issues found:                4
```

---

## 2. zlib-binding 源码审查

**源码位置**: `corpus/ffi-dense/zlib_binding.c`

### 2.1 Bug 1: inflateInit 无 inflateEnd (资源泄漏)

**源码位置**: 第 17-28 行

```c
// Bug 1: inflateInit without inflateEnd
int inflate_leak(const unsigned char* compressed, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    inflateInit(&strm);
    
    strm.next_in = (Bytef*)compressed;
    strm.avail_in = len;
    
    // Missing: inflateEnd(&strm);
    return 0;  // Leak: inflate state not freed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: inflate_leak
[ERROR] [MEDIUM] FFI RISK: inflate_leak -> inflateInit_
[ERROR]   Kind: allocator
[ERROR]   Detail: Zlib inflate stream initialization (allocates state)
[WARN]   CONTRACT VIOLATION: inflateInit returns nullable pointer but no NULL check detected
[WARN]   CONTRACT WARNING: inflateInit transfers ownership but result may be discarded (leak risk)
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in inflate_leak
```

---

### 2.2 Bug 2: deflateInit 无 deflateEnd (资源泄漏)

**源码位置**: 第 30-42 行

```c
// Bug 2: deflateInit without deflateEnd
int deflate_leak(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    deflateInit(&strm, Z_DEFAULT_COMPRESSION);
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    
    // Missing: deflateEnd(&strm);
    return 0;  // Leak: deflate state not freed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: deflate_leak
[ERROR] [MEDIUM] FFI RISK: deflate_leak -> deflateInit_
[ERROR]   Kind: allocator
[WARN]   CONTRACT VIOLATION: deflateInit returns nullable pointer but no NULL check detected
[WARN]   CONTRACT WARNING: deflateInit transfers ownership but result may be discarded (leak risk)
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in deflate_leak
```

---

### 2.3 Bug 3: 缓冲区溢出

**源码位置**: 第 44-53 行

```c
// Bug 3: Buffer overflow - unchecked output buffer size
int compress_overflow(unsigned char* output, const unsigned char* input, int input_len) {
    uLongf output_len = 1024;  // Assume output is large enough
    
    // Bug: No check if output buffer is large enough
    compress(output, &output_len, input, input_len);
    
    return output_len;
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: compress_overflow
(无警告 - 需要增强检测)
```

---

### 2.4 Bug 4: Use After Free

**源码位置**: 第 56-71 行

```c
// Bug 4: Use after free
int use_after_free_example(const char* data) {
    uLong source_len = strlen(data);
    uLong dest_len = compressBound(source_len);
    
    Bytef* dest = malloc(dest_len);
    compress(dest, &dest_len, (const Bytef*)data, source_len);
    
    // Free the compressed data
    free(dest);
    
    // Bug: Using freed memory
    printf("Compressed size: %lu\n", dest_len);
    
    return 0;
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: use_after_free_example
[ERROR] [MEDIUM] RISKY LIBC CALL: use_after_free_example -> malloc
[ERROR]   Kind: allocator
[ERROR] [HIGH] RISKY LIBC CALL: use_after_free_example -> free
[ERROR]   Kind: deallocator
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in use_after_free_example
```

---

### 2.5 Bug 5: Double Free

**源码位置**: 第 74-96 行

```c
// Bug 5: Double free on z_stream internal buffer
int double_free_example(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    inflateInit(&strm);
    
    strm.next_out = malloc(1024);
    strm.avail_out = 1024;
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    
    inflate(&strm, Z_NO_FLUSH);
    
    // Bug: Free the buffer manually
    free(strm.next_out);
    
    // Then inflateEnd tries to free it again
    inflateEnd(&strm);  // Potential double free
    
    return 0;
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: double_free_example
[ERROR] [MEDIUM] FFI RISK: double_free_example -> inflateInit_
[ERROR] [MEDIUM] RISKY LIBC CALL: double_free_example -> malloc
[ERROR] [HIGH] RISKY LIBC CALL: double_free_example -> free
[ERROR]   Kind: deallocator
[ERROR]   Warning: This function CONSUMES ownership
[ERROR] [MEDIUM] FFI RISK: double_free_example -> inflateEnd
[ERROR]   Kind: deallocator
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in double_free_example
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 97 used after free in double_free_example
```

---

### 2.6 Bug 6: gzopen 无 gzclose

**源码位置**: 第 141-150 行

```c
// Bug 8: gzopen without gzclose
int gzfile_leak(const char* path, const char* data) {
    gzFile file = gzopen(path, "wb");
    if (!file) return -1;
    
    gzwrite(file, data, strlen(data));
    
    // Missing: gzclose(file);
    return 0;  // Leak: file not closed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: gzfile_leak
[ERROR] [MEDIUM] FFI RISK: gzfile_leak -> gzopen
[ERROR]   Kind: allocator
[ERROR]   Detail: Zlib gz file open (allocates handle)
[WARN]   CONTRACT VIOLATION: gzopen returns nullable pointer but no NULL check detected
[WARN]   DANGLING RISK: Loading from stack variable and passing to FFI
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in gzfile_leak
```

---

## 3. openssl-wrapper 源码审查

**源码位置**: `corpus/ffi-dense/openssl_wrapper.c`

### 3.1 Bug 1: EVP_CIPHER_CTX 泄漏

**源码位置**: 第 92-99 行

```c
// Bug 1: EVP_CIPHER_CTX leak
int encrypt_leak_ctx(const unsigned char* plaintext, int len) {
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;
    
    // Missing: EVP_CIPHER_CTX_free(ctx);
    return 0;  // Leak: ctx never freed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: encrypt_leak_ctx
[ERROR] [HIGH] FFI RISK: encrypt_leak_ctx -> EVP_CIPHER_CTX_new
[ERROR]   Kind: allocator
[ERROR]   Detail: OpenSSL cipher context allocation
[WARN]   CONTRACT VIOLATION: EVP_CIPHER_CTX_new returns nullable pointer but no NULL check detected
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in encrypt_leak_ctx
```

---

### 3.2 Bug 2: BIO 泄漏

**源码位置**: 第 101-108 行

```c
// Bug 2: BIO chain leak
int bio_leak(const char* data) {
    BIO* bio = BIO_new(BIO_s_mem());
    BIO_write(bio, data, strlen(data));
    
    // Missing: BIO_free(bio);
    return 0;  // Leak: bio never freed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: bio_leak
[ERROR] [HIGH] FFI RISK: bio_leak -> BIO_new
[ERROR]   Kind: allocator
[ERROR]   Detail: OpenSSL BIO allocation
[WARN]   CONTRACT VIOLATION: BIO_new returns nullable pointer but no NULL check detected
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in bio_leak
```

---

### 3.3 Bug 3: RSA 密钥泄漏

**源码位置**: 第 110-121 行

```c
// Bug 3: RSA key leak
int rsa_key_leak() {
    RSA* rsa = RSA_new();
    BIGNUM* bn = BN_new();
    BN_set_word(bn, RSA_F4);
    
    RSA_generate_key_ex(rsa, 2048, bn, NULL);
    
    // Missing: RSA_free(rsa);
    BN_free(bn);
    return 0;  // Leak: rsa never freed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: rsa_key_leak
[ERROR] [HIGH] FFI RISK: rsa_key_leak -> RSA_new
[ERROR]   Kind: allocator
[ERROR]   Detail: OpenSSL RSA key allocation
[WARN]   CONTRACT VIOLATION: RSA_new returns nullable pointer but no NULL check detected
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in rsa_key_leak
```

---

### 3.4 Bug 4: SSL_CTX 泄漏

**源码位置**: 第 165-174 行

```c
// Bug 7: SSL context without proper cleanup
int ssl_ctx_leak() {
    SSL_CTX* ctx = SSL_CTX_new(TLS_method());
    if (!ctx) return -1;
    
    // Missing: SSL_CTX_free(ctx);
    return 0;  // Leak
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: ssl_ctx_leak
[ERROR] [HIGH] FFI RISK: ssl_ctx_leak -> SSL_CTX_new
[ERROR]   Kind: allocator
[ERROR]   Detail: OpenSSL SSL context allocation
[WARN]   CONTRACT VIOLATION: SSL_CTX_new returns nullable pointer but no NULL check detected
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in ssl_ctx_leak
```

---

## 4. sqlite-binding 源码审查

**源码位置**: `corpus/ffi-dense/sqlite_binding.c`

### 4.1 Bug 1: 数据库泄漏

**源码位置**: 第 16-26 行

```c
// Bug 1: Resource leak - sqlite3_open without sqlite3_close
int leak_database_open(const char* path) {
    sqlite3* db;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        // Missing: sqlite3_close(db);
        return -1;
    }
    // Missing: sqlite3_close(db);
    return 0;  // Leak: db never closed
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: leak_database_open
[ERROR] [HIGH] FFI RISK: leak_database_open -> sqlite3_open
[ERROR]   Kind: allocator
[ERROR]   Detail: SQLite3 database connection allocation
[WARN]   CONTRACT VIOLATION: sqlite3_open returns nullable pointer but no NULL check detected
[WARN]   DANGLING RISK: Loading from stack variable and passing to FFI
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in leak_database_open
```

---

### 4.2 Bug 2: 语句泄漏

**源码位置**: 第 28-42 行

```c
// Bug 2: Statement leak - prepare without finalize
int leak_statement(sqlite3* db) {
    sqlite3_stmt* stmt;
    const char* sql = "SELECT * FROM users";
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return -1;
    }
    
    sqlite3_step(stmt);
    
    // Missing: sqlite3_finalize(stmt);
    return 0;  // Leak: stmt never finalized
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: leak_statement
[ERROR] [HIGH] FFI RISK: leak_statement -> sqlite3_prepare_v2
[ERROR]   Kind: allocator
[ERROR]   Detail: SQLite3 prepared statement allocation
[WARN]   CONTRACT VIOLATION: sqlite3_prepare returns nullable pointer but no NULL check detected
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in leak_statement
```

---

### 4.3 Bug 3: 悬空指针绑定

**源码位置**: 第 44-60 行

```c
// Bug 3: Dangling pointer - bind text with freed string
int bind_dangling_pointer(sqlite3* db) {
    sqlite3_stmt* stmt;
    const char* sql = "INSERT INTO users (name) VALUES (?)";
    
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    
    char* name = malloc(20);
    strcpy(name, "test_user");
    free(name);  // Free the string
    
    // Bug: binding freed memory
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT);
    
    sqlite3_finalize(stmt);
    return 0;
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: bind_dangling_pointer
[ERROR] [HIGH] FFI RISK: bind_dangling_pointer -> sqlite3_prepare_v2
[ERROR] [MEDIUM] RISKY LIBC CALL: bind_dangling_pointer -> malloc
[ERROR] [HIGH] RISKY LIBC CALL: bind_dangling_pointer -> free
[ERROR]   Kind: deallocator
[ERROR]   Warning: This function CONSUMES ownership
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in bind_dangling_pointer
```

---

### 4.4 Bug 4: Use After Finalize

**源码位置**: 第 62-77 行

```c
// Bug 4: Use after finalize - column text after step
const char* get_user_name_dangling(sqlite3* db, int user_id) {
    sqlite3_stmt* stmt;
    const char* sql = "SELECT name FROM users WHERE id = ?";
    
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    sqlite3_bind_int(stmt, 1, user_id);
    sqlite3_step(stmt);
    
    const char* name = (const char*)sqlite3_column_text(stmt, 0);
    
    // Bug: returning pointer that becomes invalid after finalize
    sqlite3_finalize(stmt);
    
    return name;  // Dangling pointer!
}
```

**OmniScope 检测日志**:
```
[DEBUG] ANALYZE [USER]: get_user_name_dangling
[ERROR] [HIGH] FFI RISK: get_user_name_dangling -> sqlite3_prepare_v2
[ERROR] [HIGH] FFI RISK: get_user_name_dangling -> sqlite3_finalize
[ERROR]   Kind: deallocator
[WARN]   DANGLING RISK: Loading from stack variable and passing to FFI
[WARN] MEMORY LEAK [MEDIUM]: Memory allocated but never freed in get_user_name_dangling
```

---

## 5. 问题汇总

### 5.1 检测结果

| 项目 | 源码文件 | Issues | OmniScope 检测 |
|------|----------|--------|----------------|
| zlib-binding | `corpus/ffi-dense/zlib_binding.c` | 14 | ✅ 真实检测 |
| openssl-wrapper | `corpus/ffi-dense/openssl_wrapper.c` | 7 | ✅ 真实检测 |
| sqlite-binding | `corpus/ffi-dense/sqlite_binding.c` | 4 | ✅ 真实检测 |

### 5.2 源码验证

✅ **所有代码片段均来自真实源码**
- 源码文件存在于 `corpus/ffi-dense/` 目录
- IR 文件由 clang 生成
- OmniScope 检测日志来自真实运行

---

## 6. 附录

| 项目 | 值 |
|------|------|
| OmniScope 版本 | v0.1.5 |
| 测试日期 | 2026-04-25 |
| 源码位置 | corpus/ffi-dense/*.c |
| IR 文件 | corpus/ffi-dense/*.ll |
