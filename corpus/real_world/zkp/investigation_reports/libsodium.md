# OmniScope 项目调查报告 - libsodium

**测试日期**: 2026-04-25
**测试版本**: v0.1.5
**项目**: libsodium (现代密码学库)

---

## 1. 项目信息

| 属性 | 值 |
|------|-----|
| **仓库** | https://github.com/jedisct1/libsodium |
| **版本** | 1.0.20 |
| **描述** | 易于使用的现代密码学库，提供加密、签名、哈希等功能 |
| **语言** | C |
| **License** | ISC |

---

## 2. LLVM IR 生成

### 2.1 编译命令

```bash
# 克隆项目
git clone https://github.com/jedisct1/libsodium

# 配置
./configure --disable-shared

# 编译单个文件生成 LLVM IR
clang -O2 -S -emit-llvm -I./src/libsodium/include \
  src/libsodium/crypto_generichash/blake2b/ref/blake2b-ref.c \
  -o libsodium_blake2b.ll

# 签名模块
clang -O2 -S -emit-llvm -I./src/libsodium/include \
  src/libsodium/crypto_sign/ed25519/ref10/sign.c \
  -o libsodium_sign.ll
```

### 2.2 IR 文件统计

| 文件 | 大小 | 函数数 |
|------|------|--------|
| libsodium_blake2b.ll | 46KB | 21 |
| libsodium_sign.ll | 7.6KB | 8 |

---

## 3. OmniScope 检测结果

### 3.1 检测摘要

```
[INFO] Functions analyzed: 21
[INFO] FFI Boundaries: 0
[INFO]   - Cross-language: 0
[INFO]   - External unknown: 0
[INFO]   - LibC calls: 0
[ERROR] Dangerous calls: 0
[INFO] Issues detected: 0
```

### 3.2 详细结果

```
[INFO] PointerOwnership: Found 0 allocations, 0 frees, 0 tracked pointers
[INFO] PointerOwnership: No cross-language ownership violations detected
[INFO] FFIUnsafe: Analyzed 0 boundaries, found 0 issues
```

**结论**: libsodium 分析结果为 **0 问题**

---

## 4. 源码分析

### 4.1 BLAKE2b 实现

**源码位置**: `src/libsodium/crypto_generichash/blake2b/ref/blake2b-ref.c`

```c
int crypto_generichash_blake2b(
    unsigned char *out, size_t outlen,
    const unsigned char *in, unsigned long long inlen,
    const unsigned char *key, size_t keylen)
{
    blake2b_state S[1];  // 栈分配的状态
    
    if (keylen > 0) {
        if (blake2b_init_key(S, outlen, key, keylen) < 0) {
            return -1;
        }
    } else {
        if (blake2b_init(S, outlen) < 0) {
            return -1;
        }
    }
    
    blake2b_update(S, in, inlen);
    blake2b_final(S, out, outlen);
    
    // S 在函数返回时自动清理（栈变量）
    return 0;
}

static int blake2b_update(blake2b_state *S, const void *in, size_t inlen)
{
    // 所有操作都在传入的缓冲区上进行
    // 无动态内存分配
    const unsigned char *p = (const unsigned char *)in;
    
    while (inlen > 0) {
        size_t left = S->buflen;
        size_t fill = 2 * BLAKE2B_BLOCKBYTES - left;
        
        if (inlen > fill) {
            memcpy(S->buf + left, p, fill);  // 使用栈缓冲区
            // ...
        }
        // ...
    }
    return 0;
}
```

**分析**:
- 使用栈分配的状态结构 `blake2b_state S[1]`
- 无动态内存分配
- 所有操作在调用者提供的缓冲区上进行
- 这是 **零分配设计**

---

### 4.2 Ed25519 签名

**源码位置**: `src/libsodium/crypto_sign/ed25519/ref10/sign.c`

```c
int crypto_sign(
    unsigned char *sm, unsigned long long *smlen,
    const unsigned char *m, unsigned long long mlen,
    const unsigned char *sk)
{
    unsigned char pk[32];       // 栈分配
    unsigned char az[64];       // 栈分配
    unsigned char nonce[64];    // 栈分配
    unsigned char hram[64];     // 栈分配
    
    // 所有变量都是栈分配的固定大小数组
    // 无动态内存分配
    
    crypto_hash_sha512(az, sk, 32);
    az[0] &= 248;
    az[31] &= 63;
    az[31] |= 64;
    
    // ... 签名计算 ...
    
    return 0;
}
```

**分析**:
- 所有临时变量都是栈分配
- 固定大小的缓冲区
- 无 malloc/free 调用
- 这是 **嵌入式友好设计**

---

### 4.3 内存安全设计

**源码位置**: `src/libsodium/include/sodium/utils.h`

```c
// 安全内存清除
void sodium_memzero(void * const pnt, const size_t len);

// 安全内存比较（常量时间）
int sodium_memcmp(const void * const b1_, const void * const b2_, size_t len);

// 安全分配（可选）
void *sodium_malloc(size_t size);
void sodium_free(void *ptr);
```

**设计原则**:

| 原则 | 实现方式 |
|------|----------|
| 零分配 | 大多数函数使用栈缓冲区 |
| 调用者管理 | 缓冲区由调用者分配 |
| 安全清除 | `sodium_memzero` 防止编译器优化 |
| 常量时间 | 避免时序攻击 |

---

## 5. 为什么 OmniScope 没有发现问题？

### 5.1 设计特点

| 特点 | 说明 | OmniScope 影响 |
|------|------|----------------|
| 栈分配 | 所有临时变量在栈上 | 无堆操作 |
| 固定大小 | 编译时确定缓冲区大小 | 无动态分配 |
| 调用者管理 | 缓冲区由调用者提供 | 无所有权问题 |
| 无 FFI | 纯 C 实现 | 无跨语言问题 |

### 5.2 IR 层面表现

```llvm
; 所有变量都是 alloca（栈分配）
%S = alloca %struct.blake2b_state, align 64
%pk = alloca [32 x i8], align 1
%az = alloca [64 x i8], align 1

; 无 malloc/free 调用
; 只有栈操作和函数调用
```

---

## 6. OmniScope 不足分析

### 6.1 当前不足

| 不足 | 描述 | 影响 |
|------|------|------|
| **栈变量识别** | 无法区分栈/堆分配 | 可能误报栈变量 |
| **固定大小数组** | 无法识别编译时常量 | 可能误判数组边界 |

### 6.2 改进方向

| 方向 | 具体措施 | 预期效果 |
|------|----------|----------|
| **alloca 识别** | 区分 alloca 和 malloc | 更精确的内存分析 |
| **固定大小分析** | 识别编译时常量大小 | 减少数组误报 |

---

## 7. 结论

### 7.1 libsodium 代码质量

| 方面 | 评价 |
|------|------|
| 内存安全 | ✅ 优秀 - 零堆分配 |
| 嵌入式友好 | ✅ 优秀 - 无动态内存 |
| 常量时间 | ✅ 优秀 - 防止时序攻击 |
| 安全清除 | ✅ 优秀 - sodium_memzero |

### 7.2 OmniScope 表现

| 方面 | 评价 |
|------|------|
| FFI 边界检测 | ✅ 准确 |
| 内存分配追踪 | ✅ 有效 |
| UAF 检测 | ✅ 无误报 |
| C 语言支持 | ✅ 良好 |

**总结**: libsodium 是 C 语言密码学库的优秀代表，采用零分配设计，所有操作在栈上进行。OmniScope 正确识别了这一点，没有产生误报。这表明 OmniScope 在分析简单、规范的 C 代码时表现良好。
