# OmniScope IR Pattern Atlas — 从 *.ll / *.bc 提取的语义规律

> 本文档由人工逐个读取 `/tmp/`、`~/code/` 下所有 `*.ll` / `*.bc` 文件后总结。
> 每条规律标注来源文件、语言、IR 特征，以及是否能被语义树/内存图自动推导。
> 白名单条目仅保留语义树无法处理的极少量兜底。

---

## 1. C 语言 IR 规律

### 1.1 C 堆分配/释放模式
- **来源**: `simple_ffi.ll`, `boundary_test.ll`, `zlib_binding.ll`, `network_ffi.ll`, `sqlite_binding.ll`, `openssl_wrapper.ll`
- **语言**: C
- **IR 特征**:
  - 分配: `call ptr @malloc(i64 N)` / `call ptr @calloc(i64, i64)` / `call ptr @realloc(ptr, i64)`
  - 释放: `call void @free(ptr %x)`
  - 属性标记: `allockind("alloc,uninitialized")` / `allockind("free")` / `"alloc-family"="malloc"`
- **规律**: C 的 malloc/free 总是成对出现在同一函数或同一调用链上。`malloc` 返回 `ptr`，`free` 接受 `ptr`。realloc 接受旧 ptr 并返回新 ptr。
- **语义树可推导**: 是。`call @malloc → OwnershipTransfer{acquire}`, `call @free → OwnershipTransfer{release}`
- **白名单**: 不需要（已在 FamilyRegistry 的 `C_HEAP` family 中）

### 1.2 C 纯计算函数（无所有权语义）
- **来源**: `simple_ffi.ll` — `strlen`, `puts`, `printf`, `strcpy`
- **语言**: C
- **IR 特征**:
  - `call i64 @strlen(ptr)` → 返回整数，仅用于算术/比较
  - `call i32 @puts(ptr)` → 返回整数，忽略
  - `call i32 @printf(ptr, ...)` → 返回整数，忽略
- **规律**: 返回非 ptr 类型的 C 函数调用是纯计算，无所有权语义
- **语义树可推导**: 是。`PureComputation` 模式：返回值类型不是 ptr，且不被传入 free/dealloc
- **白名单**: 不需要

### 1.3 C 栈分配 + lifetime
- **来源**: 所有 C .ll 文件
- **IR 特征**:
  - `%buf = alloca [16 x i8]`
  - `call void @llvm.lifetime.start.p0(i64 N, ptr %buf)`
  - `call void @llvm.lifetime.end.p0(i64 N, ptr %buf)`
- **规律**: alloca + lifetime.start/end 对是 C 编译器插入的栈分配模式，不会跨 FFI 边界
- **语义树可推导**: 是。`PointerProvenance::Stack`，ffi_safety_score = 0.2
- **白名单**: 不需要

### 1.4 C 库特有分配/释放对
- **来源**: `zlib_binding.ll` — `inflateInit_` / `inflateEnd`, `deflateInit_` / `deflateEnd`
- **来源**: `openssl_wrapper.ll` — `EVP_CIPHER_CTX_new` / `EVP_CIPHER_CTX_free`, `BIO_new` / `BIO_free`, `RSA_new` / `RSA_free`, `BN_new` / `BN_free`
- **来源**: `sqlite_binding.ll` — `sqlite3_open` / `sqlite3_close`, `sqlite3_prepare_v2` / `sqlite3_finalize`
- **语言**: C
- **IR 特征**: `call ptr @XXX_new()` → 返回 ptr; `call void @XXX_free(ptr)` → 接受 ptr
- **规律**: C 库的 `_new`/`_free`, `_open`/`_close`, `_init`/`_end` 是配对的资源管理。命名规律是 `XXX_create` / `XXX_destroy` 或 `XXX_new` / `XXX_free`
- **语义树可推导**: 部分可以。`call 返回 ptr → OwnershipTransfer{acquire}`, `call void @XXX_free(ptr) → OwnershipTransfer{release}`。但 family 归属需要额外信息
- **白名单**: 需要极少量兜底。建议将以下加入 FamilyRegistry:
  - `zlib_family`: `inflateInit_`(acquire) / `inflateEnd`(release) / `deflateInit_`(acquire) / `deflateEnd`(release) — 来自 `zlib_binding.ll`
  - `openssl_family`: `EVP_CIPHER_CTX_new`(acquire) / `EVP_CIPHER_CTX_free`(release) / `BIO_new`(acquire) / `BIO_free`(release) / `RSA_new`(acquire) / `RSA_free`(release) / `BN_new`(acquire) / `BN_free`(release) — 来自 `openssl_wrapper.ll`
  - `sqlite_family`: `sqlite3_open`(acquire) / `sqlite3_close`(release) / `sqlite3_prepare_v2`(acquire) / `sqlite3_finalize`(release) — 来自 `sqlite_binding.ll`

---

## 2. C++ IR 规律

### 2.1 C++ new/delete (Itanium mangling)
- **来源**: `rust_ffi_bugs.ll` — 函数名使用 `_Z` 前缀 (C++ Itanium mangling)
- **语言**: C++
- **IR 特征**:
  - 分配: `call ptr @_Znwm(i64)` (operator new) / `call ptr @_Znam(i64)` (operator new[])
  - 释放: `call void @_ZdlPv(ptr)` (operator delete) / `call void @_ZdaPv(ptr)` (operator delete[])
  - 也可看到: `call void @_ZN8cpp_hash4HashEPKhmPh(...)` — C++ 命名空间函数
- **规律**: C++ 的 new/delete 通过 Itanium mangling 编码。`_Znwm` = `operator new(unsigned long)`, `_Znam` = `operator new[](unsigned long)`
- **语义树可推导**: 是。FamilyRegistry 已有 `CPP_NEW_SCALAR` 和 `CPP_NEW_ARRAY`
- **白名单**: 不需要

### 2.2 C++ 跨语言桥接
- **来源**: `c_hash_c_bridge.ll` — C 桥接层调用 C++
- **语言**: C → C++
- **IR 特征**: C 函数 `@c_hash` 内部 `call void @_ZN8cpp_hash4HashEPKhmPh(...)` — C 代码调用 C++ 函数
- **规律**: C/C++ 桥接层是 by-design FFI，C 函数做 malloc/free，C++ 函数做纯计算
- **语义树可推导**: 是。`InternalBridge` 模式：callee 是同项目内定义的函数
- **白名单**: 不需要

---

## 3. Rust IR 规律

### 3.1 Rust 全局分配器
- **来源**: `bun_alloc-ef7250b81132b4bd.ll`, `rust_hash.ll`
- **语言**: Rust
- **IR 特征**:
  - 分配: `call ptr @_RNvCs...___rust_alloc(i64 size, i64 align)` — Rust v0 mangling
  - 释放: `call void @_RNvCs...___rust_dealloc(ptr, i64 size, i64 align)`
  - 也可看到短名: `call ptr @__rust_alloc(i64, i64)` / `call void @__rust_dealloc(ptr, i64, i64)`
- **规律**: Rust 全局分配器通过 `__rust_alloc` / `__rust_dealloc` 分配。Rust v0 mangling 格式为 `_R` 前缀，包含 crate 名、路径、哈希
- **语义树可推导**: 是。FamilyRegistry 已有 `RUST_GLOBAL` family
- **白名单**: 不需要

### 3.2 Rust refcount 条件释放
- **来源**: `bun_alloc-ef7250b81132b4bd.ll`
- **语言**: Rust
- **IR 特征**:
  - `atomicrmw sub ptr %refcount, i32 1 acquire`
  - `icmp eq i32 %old, 1`
  - `br i1 %cond, label %drop, label %done`
  - `drop: call void @_RNv...drop_in_place(ptr)`
  - `done: ret void`
- **规律**: Arc/Rc 的 Drop 实现：`atomicrmw sub` 减引用计数，如果减到阈值（Arc=1, Rc=1），调用 drop_in_place 然后释放。这是条件释放，不是所有权转移
- **语义树可推导**: 是。`ConditionalRelease` 模式：`atomicrmw sub + icmp eq + br + call`
- **白名单**: 不需要

### 3.3 Rust FFI 导出函数
- **来源**: `rust_hash.ll`
- **语言**: Rust
- **IR 特征**:
  - `define noundef i32 @rust_hash_compute(ptr %data, i64 %len, ptr %out)` — 导出函数
  - 内部: null check + `call i32 @c_hash(...)` — 调用 C 函数
  - Rust 的 `extern "C"` 函数做参数校验后桥接到 C 实现
- **规律**: Rust `extern "C"` 导出函数的模式是: 参数 null check → 调用 C 实现函数 → 返回结果。这是安全的 FFI 桥接
- **语义树可推导**: 是。`PointerProjection` 或 `InternalBridge` 模式
- **白名单**: 不需要

### 3.4 Rust mimalloc 自定义分配器
- **来源**: `bun_alloc-ef7250b81132b4bd.ll`
- **语言**: Rust (Bun 运行时)
- **IR 特征**:
  - `call ptr @mi_realloc(ptr, i64)` — mimalloc realloc
  - `call void @mi_heap_destroy(ptr)` — mimalloc heap 销毁
  - `call void @___rust_dealloc(ptr, i64, i64)` — 回到 Rust 全局分配器释放
  - vtable 模式: `@_RNv...vtable_alloc` / `@_RNv...vtable_free` — Zig allocator vtable
- **规律**: Bun 使用 mimalloc 作为底层分配器，通过 Zig allocator vtable 暴露给 Zig 代码。释放路径是: Zig vtable_free → mi_free / __rust_dealloc
- **语义树可推导**: 部分可以。`mi_realloc` 是 `OwnershipTransfer{release+acquire}`，`mi_heap_destroy` 是条件释放
- **白名单**: 需要少量。建议:
  - `mimalloc_family`: `mi_malloc`(acquire) / `mi_free`(release) / `mi_realloc`(acquire) / `mi_heap_destroy`(conditional_release) — 来自 `bun_alloc-ef7250b81132b4bd.ll`

---

## 4. Go (cgo) IR 规律

### 4.1 Go cgo 分配/释放
- **来源**: `go_cgo_bugs.ll`
- **语言**: Go
- **IR 特征**:
  - `call ptr @_cgo_allocate(i32 N)` — Go 运行时分配
  - `call void @_cgo_free(ptr)` — Go 运行时释放
  - `call ptr @_Cfunc_GoMalloc(i32 N)` — Go C 函数包装
  - `call void @_Cfunc_GoFree(ptr)` — Go C 函数包装
- **规律**: Go 的 cgo 有两种分配器接口:
  1. `_cgo_allocate` / `_cgo_free` — Go runtime 管理的内存
  2. `_Cfunc_GoMalloc` / `_Cfunc_GoFree` — 模拟 C malloc/free 的包装
  Go runtime 分配的内存用 C free 释放是跨语言 bug
- **语义树可推导**: 部分可以。`_cgo_allocate` 返回 ptr → acquire, `_cgo_free` 接受 ptr → release
- **白名单**: 需要少量。建议:
  - `go_cgo_family`: `_cgo_allocate`(acquire) / `_cgo_free`(release) / `_Cfunc_GoMalloc`(acquire) / `_Cfunc_GoFree`(release) — 来自 `go_cgo_bugs.ll`

### 4.2 Go cgo 数据竞争
- **来源**: `go_cgo_bugs.ll` — `go_04_race_test`
- **语言**: Go + C
- **IR 特征**:
  - `call i32 @pthread_create(...)` — C 线程创建
  - `load volatile i32 @g_shared_counter` — volatile 全局变量访问
  - `store volatile i32 %new, @g_shared_counter` — 无同步的写入
- **规律**: Go 通过 cgo 调用 C pthread，但 Go runtime 不知道 C 线程的存在，导致数据竞争
- **语义树可推导**: 否。需要理解 pthread_create 语义
- **白名单**: `pthread_create` 不是内存分配，不需要进 FamilyRegistry，但需要标记为并发问题

---

## 5. Python (CFFI) IR 规律

### 5.1 Python 引用计数
- **来源**: `python_cffi_bugs.ll`
- **语言**: Python C API
- **IR 特征**:
  - `call void @Py_DECREF(ptr)` — 条件释放（引用计数减 1，到 0 时释放）
  - `call void @Py_XDECREF(ptr)` — 同 Py_DECREF 但接受 null
  - `call ptr @PyList_GetItem(ptr, i32)` — 返回 borrowed reference（不增加引用计数）
  - `call ptr @PyBytes_FromStringAndSize(ptr, i32)` — 返回 new reference（引用计数=1）
  - `call ptr @PyBytes_AsString(ptr)` — 返回借用指针
- **规律**: Python C API 的核心是 borrowed reference vs new reference:
  - `PyList_GetItem` 返回 borrowed ref → 不能 Py_DECREF
  - `PyBytes_FromStringAndSize` 返回 new ref → 必须 Py_DECREF
  - `PyBytes_AsString` 返回内部指针 → 释放后悬空
  - 对 borrowed ref 调用 Py_DECREF 是 bug; 对 new ref 不 DECREF 是泄漏
- **语义树可推导**: 部分可以。`Py_DECREF` = `ConditionalRelease`, `Py_INCREF` = `Retain`
- **白名单**: 需要少量（已在 FamilyRegistry 的 PYTHON_OBJECT family 中）:
  - 缺失: `PyList_GetItem` → 返回 borrowed ref (不改变引用计数), `PyBytes_AsString` → 返回借用指针, `PyTuple_New` / `PyTuple_SetItem` → steal reference semantics

### 5.2 Python ctypes 错误释放
- **来源**: `python_cffi_bugs.ll` — `py_06_free_python_memory`, `py_08_ctypes_wrong_free`
- **语言**: Python C API
- **IR 特征**:
  - `call ptr @PyBytes_AsString(ptr)` → 返回内部 buffer 指针
  - `call void @free(ptr)` → 用 C free 释放 Python 内部内存！跨 family bug
  - `call ptr @ctypes_alloc(i32)` → Python ctypes 分配
  - `call void @free(ptr)` → 用 C free 释放 ctypes 内存
- **规律**: Python 内部内存不能用 C free 释放，ctypes 分配的内存可能用 C free 释放也可能不行
- **语义树可推导**: 是。跨 family: `PYTHON_OBJECT` vs `C_HEAP`
- **白名单**: 不需要额外（`ctypes_alloc` 需要标注为 `PYTHON_MEM` family）

---

## 6. Java (JNI) IR 规律

### 6.1 JNI 引用类型
- **来源**: `java_jni_bugs.ll`
- **语言**: Java JNI
- **IR 特征**:
  - `call ptr @NewGlobalRef(ptr, ptr)` — 创建全局引用（acquire）
  - `call void @DeleteGlobalRef(...)` — 删除全局引用（release）— 但本文件未调用！
  - `call ptr @NewStringUTF(ptr, ptr)` — 创建 Java 字符串
  - `call ptr @GetStringUTFChars(ptr, ptr)` — 获取 UTF 字符串（borrowed）
  - `call void @ReleaseStringUTFChars(ptr, ptr, ptr)` — 释放 UTF 字符串
  - `call ptr @GetPrimitiveArrayCritical(ptr, ptr)` — 获取原始数组（critical section）
  - `call void @ReleasePrimitiveArrayCritical(ptr, ptr, ptr)` — 释放原始数组
- **规律**: JNI 有三种引用类型:
  1. Local ref: 自动释放（函数返回时）
  2. Global ref: 必须手动 `DeleteGlobalRef`（常见泄漏）
  3. Critical region: `Get*Critical` 和 `Release*Critical` 之间不能做 JNI 调用
- **语义树可推导**: 部分可以。`NewGlobalRef` = acquire, `DeleteGlobalRef` = release
- **白名单**: 需要补充（已在 FamilyRegistry 的 JAVA_LOCAL_REF/JAVA_GLOBAL_REF 中）:
  - 缺失: `GetStringUTFChars`(borrow) / `ReleaseStringUTFChars`(release) — 来自 `java_jni_bugs.ll`
  - 缺失: `GetPrimitiveArrayCritical`(borrow) / `ReleasePrimitiveArrayCritical`(release)
  - 缺失: `NewByteArray`(acquire) / `GetByteArrayElements`(borrow) / `ReleaseByteArrayElements`(release)

---

## 7. Zig IR 规律

### 7.1 Zig allocator vtable
- **来源**: `boundary_test.ll`, `zig_main.ll`
- **语言**: Zig
- **IR 特征**:
  - `call void @zig_allocator_allocImpl(ptr %out, i64 size)` — 通过输出参数返回分配结果
  - `call void @zig_allocator_freeImpl(ptr %ptr)` — 释放
  - `%mem.Allocator = type { ptr, ptr }` — vtable 指针对
  - `%mem.Allocator.VTable = type { ptr, ptr, ptr, ptr }` — alloc/resize/remap/free
- **规律**: Zig 的分配器通过 vtable dispatch，不是直接函数调用。alloc 结果通过输出参数返回（不是返回值），这与 C/Rust 的 malloc/__rust_alloc 不同
- **语义树可推导**: 部分可以。`zig_allocator_allocImpl` 输出 ptr → acquire, `zig_allocator_freeImpl` 接受 ptr → release
- **白名单**: 需要少量:
  - `zig_allocator_family`: `zig_allocator_allocImpl`(acquire) / `zig_allocator_freeImpl`(release) — 来自 `boundary_test.ll`

### 7.2 Zig 结构体类型系统
- **来源**: `zig_main.ll`
- **语言**: Zig
- **IR 特征**: 大量 `%namespace.TypeName` 类型定义，使用 Zig 的命名空间编码（非 Itanium）
- **规律**: Zig IR 的类型名包含完整路径（如 `%hash_map.HashMap(usize,...)`），与 Rust v0 mangling 类似但有区别
- **语义树可推导**: 否（类型信息不直接影响内存安全分析）
- **白名单**: 不需要

---

## 8. 跨语言 Bug 模式总结

### 8.1 CrossFamilyFree（高置信度）
来源: 所有 red_team_test .ll 文件

| Bug 模式 | 来源 ll | 分配 family | 释放 family | 置信度 |
|----------|---------|------------|------------|--------|
| Rust alloc + C free | `rust_ffi_bugs.ll` rust_01 | RUST_GLOBAL | C_HEAP | 0.90 |
| C malloc + Rust dealloc | `rust_ffi_bugs.ll` rust_02 | C_HEAP | RUST_GLOBAL | 0.90 |
| Go cgo allocate + C free | `go_cgo_bugs.ll` go_01 | GO_GC | C_HEAP | 0.85 |
| C malloc + Go cgo free | `go_cgo_bugs.ll` go_02 | C_HEAP | GO_GC | 0.85 |
| Python PyBytes + C free | `python_cffi_bugs.ll` py_06 | PYTHON_OBJECT | C_HEAP | 0.85 |
| ctypes alloc + C free | `python_cffi_bugs.ll` py_08 | PYTHON_MEM | C_HEAP | 0.80 |
| C alloc + Zig free | `boundary_test.ll` | C_HEAP | ZIG_ALLOCATOR | 0.85 |

### 8.2 UseAfterFree / BorrowEscape（高置信度）
| Bug 模式 | 来源 ll | IR 特征 | 置信度 |
|----------|---------|---------|--------|
| free 后 load | `simple_ffi.ll` use_after_free | `call @free(ptr) → load ptr` | 0.95 |
| Rust dealloc 后 memset | `rust_ffi_bugs.ll` rust_04 | `call @dealloc(ptr) → store global → load → memset` | 0.90 |
| Go cgo free 后 load | `go_cgo_bugs.ll` go_03 | `call @_cgo_free(ptr) → load global → memset` | 0.85 |
| Py_DECREF 后 printf | `python_cffi_bugs.ll` py_03 | `call @Py_DECREF(ptr) → printf(ptr)` | 0.90 |
| JNI ReleaseString 后 printf | `java_jni_bugs.ll` jni_03 | `call @ReleaseStringUTFChars(ptr) → printf(ptr)` | 0.90 |
| sqlite3_finalize 后 return | `sqlite_binding.ll` get_user_name_dangling | `call @sqlite3_finalize(ptr) → ret ptr` | 0.85 |

### 8.3 Leak（中等置信度）
| Bug 模式 | 来源 ll | IR 特征 | 置信度 |
|----------|---------|---------|--------|
| malloc 无 free | `simple_ffi.ll` leak_example | `call @malloc → ret ptr` | 0.80 |
| EVP_CIPHER_CTX_new 无 free | `openssl_wrapper.ll` encrypt_leak_ctx | `call @EVP_CIPHER_CTX_new → ret` | 0.75 |
| BIO_new 无 free | `openssl_wrapper.ll` bio_leak | `call @BIO_new → ret` | 0.75 |
| RSA_new 无 free | `openssl_wrapper.ll` rsa_key_leak | `call @RSA_new + BN_new → ret` | 0.80 |
| sqlite3_open 无 close | `sqlite_binding.ll` leak_database_open | `call @sqlite3_open → ret` | 0.75 |
| NewGlobalRef 无 DeleteGlobalRef | `java_jni_bugs.ll` jni_01 | `call @NewGlobalRef → printf → ret` | 0.85 |
| PyBytes_FromString 无 DECREF | `python_cffi_bugs.ll` py_02 | `call @PyBytes_FromString → AsString → ret` | 0.85 |

---

## 9. 建议的白名单补充（仅语义树无法推导的）

| 符号 | 语言 | 效果 | Family | 来源 | 原因 |
|------|------|------|--------|------|------|
| `inflateInit_` | C | acquire | zlib_family | `zlib_binding.ll` | 库级资源配对，无法从 IR 推导 |
| `inflateEnd` | C | release | zlib_family | `zlib_binding.ll` | 同上 |
| `deflateInit_` | C | acquire | zlib_family | `zlib_binding.ll` | 同上 |
| `deflateEnd` | C | release | zlib_family | `zlib_binding.ll` | 同上 |
| `EVP_CIPHER_CTX_new` | C | acquire | openssl_family | `openssl_wrapper.ll` | 库级资源配对 |
| `EVP_CIPHER_CTX_free` | C | release | openssl_family | `openssl_wrapper.ll` | 同上 |
| `BIO_new` | C | acquire | openssl_family | `openssl_wrapper.ll` | 同上 |
| `BIO_free` | C | release | openssl_family | `openssl_wrapper.ll` | 同上 |
| `RSA_new` | C | acquire | openssl_family | `openssl_wrapper.ll` | 同上 |
| `RSA_free` | C | release | openssl_family | `openssl_wrapper.ll` | 同上 |
| `BN_new` | C | acquire | openssl_family | `openssl_wrapper.ll` | 同上 |
| `BN_free` | C | release | openssl_family | `openssl_wrapper.ll` | 同上 |
| `sqlite3_open` | C | acquire | sqlite_family | `sqlite_binding.ll` | 库级资源配对 |
| `sqlite3_close` | C | release | sqlite_family | `sqlite_binding.ll` | 同上 |
| `sqlite3_prepare_v2` | C | acquire | sqlite_family | `sqlite_binding.ll` | 同上 |
| `sqlite3_finalize` | C | release | sqlite_family | `sqlite_binding.ll` | 同上 |
| `sqlite3_free` | C | release | sqlite_family | `sqlite_binding.ll` | SQLite 内部分配器释放 |
| `_cgo_allocate` | Go | acquire | go_cgo_family | `go_cgo_bugs.ll` | cgo 内部分配 |
| `_cgo_free` | Go | release | go_cgo_family | `go_cgo_bugs.ll` | cgo 内部释放 |
| `_Cfunc_GoMalloc` | Go | acquire | go_cgo_family | `go_cgo_bugs.ll` | cgo C 包装 |
| `_Cfunc_GoFree` | Go | release | go_cgo_family | `go_cgo_bugs.ll` | cgo C 包装 |
| `mi_malloc` | C/Zig | acquire | mimalloc_family | `bun_alloc-ef7250b81132b4bd.ll` | mimalloc 分配 |
| `mi_free` | C/Zig | release | mimalloc_family | `bun_alloc-ef7250b81132b4bd.ll` | mimalloc 释放 |
| `mi_realloc` | C/Zig | acquire | mimalloc_family | `bun_alloc-ef7250b81132b4bd.ll` | mimalloc 重分配 |
| `mi_heap_destroy` | C/Zig | conditional_release | mimalloc_family | `bun_alloc-ef7250b81132b4bd.ll` | mimalloc heap 销毁 |
| `zig_allocator_allocImpl` | Zig | acquire | zig_allocator_family | `boundary_test.ll` | Zig 分配器 vtable |
| `zig_allocator_freeImpl` | Zig | release | zig_allocator_family | `boundary_test.ll` | Zig 分配器 vtable |
| `PyList_GetItem` | Python | borrow | PYTHON_OBJECT | `python_cffi_bugs.ll` | 返回 borrowed ref |
| `PyBytes_AsString` | Python | borrow | PYTHON_OBJECT | `python_cffi_bugs.ll` | 返回内部指针 |
| `GetStringUTFChars` | Java | borrow | JAVA_LOCAL_REF | `java_jni_bugs.ll` | JNI borrowed 指针 |
| `ReleaseStringUTFChars` | Java | release | JAVA_LOCAL_REF | `java_jni_bugs.ll` | JNI 释放 |
| `GetPrimitiveArrayCritical` | Java | borrow | JAVA_LOCAL_REF | `java_jni_bugs.ll` | JNI critical borrow |
| `ReleasePrimitiveArrayCritical` | Java | release | JAVA_LOCAL_REF | `java_jni_bugs.ll` | JNI critical release |
| `ctypes_alloc` | Python | acquire | PYTHON_MEM | `python_cffi_bugs.ll` | ctypes 分配 |

---

## 10. 语义树/内存图能自动推导的模式（不需要白名单）

| 模式 | IR 特征 | 语义规则 | 观察次数 |
|------|---------|---------|---------|
| PureComputation | call 返回非 ptr → 仅算术/store | SafeNoOwnership | 67337× |
| Initialization | store 到 struct 字段 + ret void | SafeInitialization | 9399× |
| InternalBridge | 仅调用同项目函数 | SafeInternalBridge | 4565× |
| ConditionalRelease | atomicrmw sub + icmp eq + br + call | SafeConditionalRelease | 772× |
| PointerProjection | 仅 gep + bitcast + ret | SafePointerProjection | 250× |
| OwnershipTransfer(acquire) | call 返回 ptr → 存储或传递 | ConcernOwnershipTransfer | 342× |
| OwnershipTransfer(release) | call 接受 ptr → 传入 free/dealloc | ConcernOwnershipTransfer | 299× |

---

## 11. 关键发现总结

1. **C 库的资源配对**（zlib/openssl/sqlite）是最需要白名单兜底的，因为 IR 层面只能看到 `call 返回 ptr` / `call 接受 ptr`，无法确定 `_new` 和 `_free` 是配对的
2. **Rust 的 refcount 条件释放**完全可以从 IR 指令模式自动推导，不需要白名单
3. **Python/JNI 的 borrowed reference 语义**需要白名单标注，因为 IR 层面看不到 "borrowed" vs "owned" 的区别
4. **Go cgo 的内部分配器**需要白名单，因为 `_cgo_allocate` 的命名不够通用
5. **Zig 的 vtable dispatch** 模式需要白名单标注 `allocImpl`/`freeImpl`，但其他 Zig 代码的内存操作可从 IR 推导
6. **跨语言 bug** 的核心检测模式是：`alloc_family != free_family` 且不在 `compatible_releases` 中——这完全不需要白名单