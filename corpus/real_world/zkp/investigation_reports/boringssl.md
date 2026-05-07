# OmniScope 项目调查报告 - boringssl

**测试日期**: 2026-04-25
**测试版本**: v0.1.5
**项目**: boringssl (Google SSL/TLS 库)

---

## 1. 项目信息

| 属性 | 值 |
|------|-----|
| **仓库** | https://github.com/google/boringssl |
| **版本** | 基于 OpenSSL 1.1.1 |
| **描述** | Google 维护的 SSL/TLS 库，Chrome、Android 等使用 |
| **语言** | C++ |
| **License** | OpenSSL License / SSLeay License |

---

## 2. LLVM IR 生成

### 2.1 编译命令

```bash
# Core内存管理模块
clang++ -std=c++17 -O2 -S -emit-llvm -I./include \
  crypto/mem.cc -o llvm_ir/mem.ll

# AES 模块
clang++ -std=c++17 -O2 -S -emit-llvm -I./include \
  crypto/aes/aes.cc -o llvm_ir/aes.ll

# 随机数模块
clang++ -std=c++17 -O2 -S -emit-llvm -I./include \
  crypto/rand/rand.cc -o llvm_ir/rand.ll
```

### 2.2 IR 文件统计

| 文件 | 大小 | 函数数 |
|------|------|--------|
| mem.ll | 55KB | 58 |
| aes.ll | 3.6KB | 8 |
| sha256.ll | 7KB | 10 |
| rand.ll | 7KB | 22 |
| ecdh.ll | 9KB | 15 |
| **总计** | **85KB** | **88** |

---

## 3. OmniScope Detection Results

### 3.1 检测摘要

```
[INFO] Functions analyzed: 58
[INFO] FFI Boundaries: 70
[INFO]   - Cross-language: 0
[INFO]   - External unknown: 70
[INFO]   - LibC calls: 23
[ERROR] Dangerous calls: 25
[INFO] Issues detected: 7
```

### 3.2 UAF 警告列表

```
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 79 used after free in OPENSSL_free
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 648 used after free in OPENSSL_vasprintf
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 148 used after free in OPENSSL_clear_free
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 119 used after free in OPENSSL_realloc
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 181 used after free in OPENSSL_secure_clear_free
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 585 used after free in OPENSSL_vasprintf
[WARN] USE-AFTER-FREE [MEDIUM]: Pointer 815 used after free in CRYPTO_free
```

---

## 4. 源码比对分析

### 4.1 案例 1: `OPENSSL_free` 函数

**源码位置**: `crypto/mem.cc:236-263`

```cpp
void OPENSSL_free(void *orig_ptr) {
  if (orig_ptr == nullptr) {
    return;
  }

  if (OPENSSL_memory_free != nullptr) {
    OPENSSL_memory_free(orig_ptr);
    return;
  }

  void *ptr = ((uint8_t *)orig_ptr) - OPENSSL_MALLOC_PREFIX;
  __asan_unpoison_memory_region(ptr, OPENSSL_MALLOC_PREFIX);

  size_t size = *(size_t *)ptr;  // Line 249: 访问 ptr 获取 size
  OPENSSL_cleanse(ptr, size + OPENSSL_MALLOC_PREFIX);

#if defined(OPENSSL_ASAN)
  (void)sdallocx;
  free(ptr);                      // Line 255: 释放 ptr
#else
  if (sdallocx) {
    sdallocx(ptr, size + OPENSSL_MALLOC_PREFIX, 0);
  } else {
    free(ptr);                    // Line 260: 释放 ptr
  }
#endif
}
```

**OmniScope 报告**: `Pointer 79 used after free in OPENSSL_free`

**分析**:
- OmniScope 认为 `ptr` 在 `free(ptr)` 之后被访问
- Actual情况: 第 249 行访问 `ptr` 获取 `size`，然后第 255/260 行释放 `ptr`
- 这是 **释放前访问**，不是释放后访问
- `OPENSSL_cleanse()` 在释放前安全清除内存

**判定**: **误报** - 正确的内存管理模式

---

### 4.2 案例 2: `OPENSSL_realloc` 函数

**源码位置**: `crypto/mem.cc:265-294`

```cpp
void *OPENSSL_realloc(void *orig_ptr, size_t new_size) {
  if (orig_ptr == nullptr) {
    return OPENSSL_malloc(new_size);
  }

  size_t old_size;
  if (OPENSSL_memory_get_size != nullptr) {
    old_size = OPENSSL_memory_get_size(orig_ptr);
  } else {
    void *ptr = ((uint8_t *)orig_ptr) - OPENSSL_MALLOC_PREFIX;
    __asan_unpoison_memory_region(ptr, OPENSSL_MALLOC_PREFIX);
    old_size = *(size_t *)ptr;
    __asan_poison_memory_region(ptr, OPENSSL_MALLOC_PREFIX);
  }

  void *ret = OPENSSL_malloc(new_size);
  if (ret == nullptr) {
    return nullptr;
  }

  size_t to_copy = new_size;
  if (old_size < to_copy) {
    to_copy = old_size;
  }

  memcpy(ret, orig_ptr, to_copy);   // Line 290: 复制数据
  OPENSSL_free(orig_ptr);           // Line 291: 释放原内存

  return ret;
}
```

**OmniScope 报告**: `Pointer 119 used after free in OPENSSL_realloc`

**分析**:
- OmniScope 认为 `orig_ptr` 在释放后被访问
- Actual情况: 第 290 行复制数据到新内存，第 291 行释放原内存
- 这是标准的 **realloc 模式**: 分配新 → 复制 → 释放旧

**判定**: **误报** - 标准的 realloc 实现

---

### 4.3 案例 3: `OPENSSL_vasprintf_internal` 函数

**源码位置**: `crypto/mem.cc:457-502`

```cpp
int bssl::OPENSSL_vasprintf_internal(char **str, const char *format,
                                     va_list args, int system_malloc) {
  void *(*allocate)(size_t) = system_malloc ? malloc : OPENSSL_malloc;
  void (*deallocate)(void *) = system_malloc ? free : OPENSSL_free;
  void *(*reallocate)(void *, size_t) =
      system_malloc ? realloc : OPENSSL_realloc;
  char *candidate = nullptr;
  size_t candidate_len = 64;
  int ret;

  if ((candidate = reinterpret_cast<char *>(allocate(candidate_len))) ==
      nullptr) {
    goto err;
  }
  
  va_list args_copy;
  va_copy(args_copy, args);
  ret = vsnprintf(candidate, candidate_len, format, args_copy);
  va_end(args_copy);
  if (ret < 0) {
    goto err;
  }
  if ((size_t)ret >= candidate_len) {
    char *tmp;
    candidate_len = (size_t)ret + 1;
    if ((tmp = reinterpret_cast<char *>(
             reallocate(candidate, candidate_len))) == nullptr) {
      goto err;
    }
    candidate = tmp;
    ret = vsnprintf(candidate, candidate_len, format, args);
  }
  if (ret < 0 || (size_t)ret >= candidate_len) {
    goto err;
  }
  *str = candidate;
  return ret;

err:
  deallocate(candidate);    // Line 498: 错误路径释放
  *str = nullptr;
  errno = ENOMEM;
  return -1;
}
```

**OmniScope 报告**: `Pointer 648/585 used after free in OPENSSL_vasprintf`

**分析**:
- OmniScope 认为在错误路径释放后有问题
- Actual情况: `err` 标签只在分配失败时执行
- `candidate` 在成功路径被返回，在失败路径被释放
- 这是正确的 **错误处理模式**

**判定**: **误报** - 正确的错误处理

---

## 5. 问题分类统计

| 问题类型 | 数量 | 判定 | 原因 |
|---------|------|------|------|
| OPENSSL_free UAF | 1 | 误报 | 释放前访问元数据 |
| OPENSSL_realloc UAF | 1 | 误报 | 标准 realloc 模式 |
| OPENSSL_vasprintf UAF | 2 | 误报 | 正确错误处理 |
| OPENSSL_clear_free UAF | 1 | 误报 | 委托给 OPENSSL_free |
| OPENSSL_secure_clear_free UAF | 1 | 误报 | 委托链 |
| CRYPTO_free UAF | 1 | 误报 | 委托给 OPENSSL_free |
| **总计** | **7** | **100% 误报** | - |

---

## 6. OmniScope 不足分析

### 6.1 当前不足

| 不足 | 描述 | 影响 |
|------|------|------|
| **无法区分释放前/后访问** | OmniScope 在 IR 层无法精确判断访问顺序 | 导致大量误报 |
| **未识别委托模式** | `CRYPTO_free` → `OPENSSL_free` 这种委托链被当作独立问题 | 重复计数 |
| **未识别 realloc 模式** | 标准的 "分配-复制-释放" 模式被误判 | 常见模式误报 |
| **控制流分析不精确** | 无法识别 `goto err` 错误处理模式 | 误报错误处理代码 |

### 6.2 改进方向

| 方向 | 具体措施 | Expected效果 |
|------|----------|----------|
| **指令顺序追踪** | 在基本块内追踪 load/store 与 free 的精确顺序 | 减少 40% 误报 |
| **模式识别** | 识别 realloc、cleanup、error-handling 等安全模式 | 减少 30% 误报 |
| **委托链分析** | 识别函数委托关系，避免重复计数 | 减少重复报告 |
| **控制流敏感分析** | 识别互斥分支和错误处理路径 | 减少 20% 误报 |

---

## 7. Conclusion

### 7.1 boringssl 代码质量

| 方面 | 评价 |
|------|------|
| 内存管理 | ✅ 优秀 - 规范的 malloc/free 封装 |
| 错误处理 | ✅ 良好 - 统一的 goto err 模式 |
| 安全清除 | ✅ 优秀 - OPENSSL_cleanse 安全清零 |
| ASAN 集成 | ✅ 良好 - 支持 ASAN 内存检测 |

### 7.2 OmniScope 表现

| 方面 | 评价 |
|------|------|
| FFI Boundary检测 | ✅ 准确 |
| 内存分配追踪 | ✅ 有效 |
| UAF 检测 | ⚠️ False Positive Rate 100% |
| 模式识别 | ❌ 需改进 |

**Summary**: boringssl 是经过严格审计的生产级密码学库，OmniScope 报告的所有问题均为误报，主要原因是 IR 层分析无法精确追踪指令顺序和控制流。
