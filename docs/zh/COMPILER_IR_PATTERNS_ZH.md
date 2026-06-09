# 编译器 IR 模式与静态分析

> 基于 Rust、C++、Go (cgo)、Java (JNI)、Python (CPython API)、C# (.NET FFI) 和 Zig 编译器的实际 LLVM IR 输出。所有模式均经过真实 IR 文件验证。

## 目录

- [Rust](#rust)
- [C++](#c-1)
- [Go (cgo)](#go-cgo)
- [Java (JNI)](#java-jni)
- [Python (CPython API)](#python-cpython-api)
- [C# (.NET FFI)](#c-net-ffi)
- [Zig](#zig)

---

## Rust

来源：`rust_merkle.ll`（真实 wasmtime 库，4654 个函数）、`rust_hash.ll`、`rust_ffi_bugs.ll`

### 分配器函数（非 malloc/free）

Rust **不使用** `malloc`/`free`。它使用自己的分配器运行时。

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `__rust_alloc` | `declare ptr @__rust_alloc(i64 %size, i64 %align)` | 主分配函数 |
| `__rust_dealloc` | `declare void @__rust_dealloc(ptr %ptr, i64 %size, i64 %align)` | 释放 — 需要大小和对齐 |
| `__rust_realloc` | `declare ptr @__rust_realloc(ptr, i64, i64, i64)` | 重新分配 |
| `__rust_alloc_zeroed` | `declare ptr @__rust_alloc_zeroed(i64, i64)` | 零初始化分配 |

**对分析的影响**：寻找 `malloc`/`free` 配对的工具会遗漏所有 Rust 分配。

### Box / 原始指针转换

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `Box::into_raw` | `call ptr @_ZN3std3box8into_rawE(ptr)` | Box 转为原始指针，所有权转移给调用者 |
| `Box::from_raw` | `call ptr @_ZN3std3box8from_rawE(ptr)` | 从原始指针回收所有权 |
| `_ZN3std3string10into_rawEv` | `call ptr @_ZN3std3string10into_rawEv(ptr)` | String::into_raw，不回收则泄漏 |

### 异常处理

Rust 使用 `invoke`/`landingpad` 进行清理（panic 展开），**不是** try/catch。

```llvm
%result = invoke i64 %func(...) to label %ok unwind label %cleanup

cleanup:
  %lp = landingpad { ptr, i32 } cleanup
  ; ... 清理代码（drop、dealloc）...
  resume { ptr, i32 } %lp
```

**影响**：Landing pad 是清理链，不是错误处理。工具必须追踪通过清理路径的分配。

### 结构体分解（SROA）

Rust 的 SROA pass 将结构体分解为独立字段：

```llvm
; Vec<u8> 变为 {i64, ptr, i64} → 三个独立值
%vec.sroa.0 = load i64, ptr %vec      ; len（长度）
%vec.sroa.2 = load ptr, ptr %vec      ; data（数据指针）
%vec.sroa.3 = load i64, ptr %vec      ; capacity（容量）
```

**影响**：分配追踪必须跟踪字段级别的值，而不仅仅是结构体级别。

### 元数据

| 元数据 | 含义 |
|--------|------|
| `!noalias` | 指针在作用域内不与其他指针别名 |
| `!alias.scope` | 定义别名作用域边界 |
| `!invariant.load` | 加载的值永不改变（vtable 指针） |
| `llvm.lifetime.start/end` | 对象生命周期边界（栈分配） |
| `nonnull` 参数属性 | 指针保证非空 |
| `dereferenceable(N)` | 从指针至少可读取 N 字节 |

### 内存安全注解

Rust 在调试构建中插入运行时检查：

```llvm
; 边界检查
%inbounds = icmp ult i64 %index, %len
br i1 %inbounds, label %ok, label %panic

panic:
  call void @_ZN4core9panicking18panic_bounds_check(...)
```

### Drop 胶水（析构函数调用）

Rust 为实现了 Drop trait 的类型生成 `_ZN...4drop...` 函数：

```llvm
call fastcc void @"_ZN4core3ptr42drop_in_place$LT$alloc..vec..Vec$LT$u8$GT$$GT$"(...)
```

这些等同于 C++ 析构函数。"缺少 deinit" 的 bug 意味着 drop 胶水从未被调用。

---

## C++

来源：`red_team_cpp_ffi.ll`、`cpp_hash.ll`、`cpp_fft.ll`

### 分配函数

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `_Znam`（operator new[]） | `declare ptr @_Znam(i64)` | 数组 new |
| `_Znwm`（operator new） | `declare ptr @_Znwm(i64)` | 标量 new |
| `_ZdlPvm`（operator delete） | `declare void @_ZdlPvm(ptr, i64)` | 带大小的 delete |
| `_ZdaPv`（operator delete[]） | `declare void @_ZdaPv(ptr)` | 数组 delete |
| `malloc` / `free` | 标准 C 分配 | C++ 代码中也存在 |

**关键**：`new[]` 配对 `delete`（而非 `delete[]`）是类型不匹配 bug。

### 异常处理

C++ 使用 `invoke`/`landingpad` 配合 `@__gxx_personality_v0`：

```llvm
%result = invoke ptr @_ZN7DerivedC1Ev(ptr %obj) to label %ok unwind label %lpad

lpad:
  %lp = landingpad { ptr, i32 }
    catch ptr @_ZTISt9bad_alloc    ; catch 的类型信息
    cleanup                        ; 析构清理
  ; ...
  invoke void @__cxa_throw(...)
```

**影响**：必须追踪跨异常路径的分配。清理处理可能释放资源。

### 智能指针

C++ 智能指针生成包含引用计数的复杂 IR：

| 智能指针 | 析构模式 | 说明 |
|----------|---------|------|
| `unique_ptr` | `_ZNSt3__110unique_ptr...D1Ev` | 简单包装，调用 deleter |
| `shared_ptr` | `_ZNSt3__119__shared_weak_count...` | 引用计数，控制块 |
| `weak_ptr` | `_ZNSt3__113__weak_count...` | shared_ptr 的弱引用 |

### RTTI 和 VTable

| 模式 | IR | 说明 |
|------|-----|------|
| 类型信息 | `@_ZTI...` | `external constant ptr` |
| VTable | `@_ZTV...` | 函数指针数组 |
| 类型名 | `@_ZTS...` | 类型名的字符串字面量 |

### 虚析构函数

```llvm
; vtable 中的虚析构函数条目
%vtable = load ptr, ptr %obj
%dtor = getelementptr ptr, ptr %vtable, i64 0
call void %dtor(ptr %obj)
```

缺少虚析构函数 = 派生类析构函数永远不会被调用。

---

## Go (cgo)

来源：`go_cgo_bugs.ll`。Go 本身使用自己的 SSA（非 LLVM IR），但 cgo 生成 C 兼容的 IR。

### 分配函数

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `_cgo_allocate` | `declare ptr @_cgo_allocate(i32)` | Go 侧通过 cgo 分配 |
| `_cgo_free` | `declare void @_cgo_free(ptr)` | Go 侧释放 |
| `_Cfunc_GoMalloc` | `declare ptr @_Cfunc_GoMalloc(i32)` | Go malloc 的 C 包装 |
| `_Cfunc_GoFree` | `declare void @_Cfunc_GoFree(ptr)` | Go free 的 C 包装 |

**关键**：对 `_cgo_allocate` 分配的内存使用 `free()`，或对 `malloc` 分配的内存使用 `_cgo_free` = 跨语言 free 不匹配。

### Go 特有类型

```llvm
%struct.GoSlice = type { ptr, i32, i32 }   ; {data, len, cap}
%struct.GoString = type { ptr, i32 }        ; {data, len}
```

### 并发

Go 协程在 LLVM IR 中不可见。共享状态使用 `volatile`：

```llvm
@g_shared_counter = internal global i32 0, align 4
; 读写使用 `load volatile` / `store volatile`（不总是发出）
```

### cgo 调用约定

cgo 生成的函数使用标准 C 调用约定。`_cgo_` 前缀标识 Go 运行时函数。`_Cfunc_` 前缀标识从 Go 调用的 C 函数。

---

## Java (JNI)

来源：`java_jni_bugs.ll`。JNI 是从 Java 调用的 C API — IR 是标准 C 配合 JNI 命名约定。

### JNIEnv 函数

所有 JNI 调用以 `ptr %env`（JNIEnv*）作为第一个参数。

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `NewGlobalRef` | `call ptr @NewGlobalRef(ptr %env, ptr %obj)` | 创建全局引用 |
| `DeleteGlobalRef` | `call void @DeleteGlobalRef(ptr %env, ptr %ref)` | 释放全局引用 |
| `NewStringUTF` | `call ptr @NewStringUTF(ptr %env, ptr %str)` | 创建 Java 字符串 |
| `GetStringUTFChars` | `call ptr @GetStringUTFChars(ptr %env, ptr %jstr)` | 在本地内存中固定字符串 |
| `ReleaseStringUTFChars` | `call void @ReleaseStringUTFChars(ptr %env, ptr %jstr, ptr %chars)` | 解除固定 |
| `GetByteArrayElements` | `call ptr @GetByteArrayElements(ptr %env, ptr %arr)` | 固定字节数组 |
| `ReleaseByteArrayElements` | `call void @ReleaseByteArrayElements(ptr %env, ptr %arr, ptr %elems)` | 解除固定 |
| `GetPrimitiveArrayCritical` | `call ptr @GetPrimitiveArrayCritical(ptr %env, ptr %arr)` | 固定（阻塞 GC） |
| `ReleasePrimitiveArrayCritical` | `call void @ReleasePrimitiveArrayCritical(ptr %env, ptr %arr, ptr %carray)` | 解除固定 |

### Bug 模式

| Bug | 检测模式 |
|-----|---------|
| GlobalRef 泄漏 | `NewGlobalRef` 无匹配的 `DeleteGlobalRef` |
| 字符串固定泄漏 | `GetStringUTFChars` 无 `ReleaseStringUTFChars` |
| 释放后使用 | 在 `Release*` 调用后使用固定指针 |
| 临界区违规 | 在 `GetPrimitiveArrayCritical` 和 `Release` 之间调用 JNI |
| 类型混淆 | 数组元素类型间的转换（如 `jbyteArray` → `jint*`） |

---

## Python (CPython API)

来源：`python_cffi_bugs.ll`。Python C API 是标准 C 配合 Python 命名约定。

### 引用计数

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `Py_INCREF` | `call void @Py_INCREF(ptr %obj)` | 增加引用计数 |
| `Py_DECREF` | `call void @Py_DECREF(ptr %obj)` | 减少引用计数，可能释放 |

### 新引用 vs 借用引用

| 函数 | 引用类型 | 谁负责释放 |
|------|---------|-----------|
| `PyList_GetItem` | **借用** | Python 拥有，C **不能** DECREF |
| `PyBytes_FromStringAndSize` | **新引用** | C 必须 DECREF |
| `PyLong_FromLong` | **新引用** | C 必须 DECREF |
| `PyTuple_New` | **新引用** | C 必须 DECREF |
| `PyObject_GetAttrString` | **新引用** | C 必须 DECREF |

### 窃取引用模式

`PyTuple_SetItem` **窃取**引用 — 调用后，C 不能使用或 DECREF 该对象：

```llvm
call i32 @PyTuple_SetItem(ptr %tuple, i32 0, ptr %val1)
; %val1 现在归 %tuple 所有 — 之后使用 %val1 = UAF
```

### Bug 模式

| Bug | 检测模式 |
|-----|---------|
| 借用引用 DECREF | `PyList_GetItem` → 对同一 ptr 的 `Py_DECREF` |
| 新引用泄漏 | `PyBytes_FromStringAndSize` 无 `Py_DECREF` |
| DECREF 后使用 | `Py_DECREF` 后使用 ptr（可能已释放） |
| 窃取引用误用 | `PyTuple_SetItem` 窃取后使用 |
| 缓存无 INCREF | 存储到全局变量时无 `Py_INCREF` |
| 跨语言 free | 对 Python 管理的内存使用 `free()` |

---

## Swift

来源：`swift_ffi_test.ll`（438 行）。Swift 使用 ARC（自动引用计数）。

### ARC 运行时函数

| 模式 | IR 签名 | 说明 |
|------|---------|------|
| `swift_allocObject` | `call ptr @swift_allocObject(ptr %metadata, i64 %size, i64 %align)` | 类实例的堆分配 |
| `swift_deallocClassInstance` | `call void @swift_deallocClassInstance(ptr %obj, i64 %size, i64 %align)` | 释放 |
| `swift_retain` | `call void @swift_retain(ptr %obj)` | 增加引用计数 |
| `swift_release` | `call void @swift_release(ptr %obj)` | 减少引用计数，可能释放 |

### 独占性访问检查

Swift 在运行时强制执行内存的独占访问：

```llvm
%scratch = alloca [24 x i8]
call void @swift_beginAccess(ptr %addr, ptr %scratch, i64 32, ptr null)  ; 开始独占
; ... 访问内存 ...
call void @swift_endAccess(ptr %scratch)                                  ; 结束独占
```

### Swift 调用约定

Swift 使用 `swiftcc` 调用约定。方法传递 `swiftself`：

```llvm
define hidden swiftcc i64 @method(ptr swiftself %self) #0 {
```

### 对象布局

```llvm
%T14swift_ffi_test10FFIManagerC = type <{ %swift.refcounted, ... }>
%swift.refcounted = type { ptr, i64 }  ; {isa/元数据, 引用计数}
```

### 元数据段

Swift 在 Mach-O 段中存储类型元数据：

| 段 | 内容 |
|----|------|
| `__TEXT,__swift5_typeref` | 类型引用 |
| `__TEXT,__swift5_fieldmd` | 字段元数据 |
| `__TEXT,__swift5_types` | 类型记录 |
| `__DATA,__objc_const` | ObjC 兼容的类数据 |

### 方法分派

虚方法调用通过类似 vtable 的元数据：

```llvm
%vtable = load ptr, ptr %self
%method_ptr = getelementptr ptr, ptr %vtable, i64 12
%method = load ptr, ptr %method_ptr, !invariant.load !{}
call swiftcc i64 %method(ptr swiftself %self)
```

---

## Zig

来源：`zig_ffi_test.ll`（12MB，包含标准库）。Zig 通过自举后端编译为 LLVM IR。

### 分配器 VTable 模式

Zig 的 `std.mem.Allocator` 是一个胖指针 `{ptr, ptr}` — 数据指针 + vtable 指针。

```llvm
%mem.Allocator = type { ptr, ptr }
%mem.Allocator.VTable = type { ptr, ptr, ptr, ptr }  ; alloc, resize, remap, free
```

内置分配器：

| 分配器 | VTable 全局变量 | 底层机制 |
|--------|----------------|---------|
| `heap.CAllocator` | `@heap.CAllocator.vtable` | 包装 `posix_memalign` / `free` |
| `heap.PageAllocator` | `@heap.PageAllocator.vtable` | 包装 `mmap` / `munmap` |
| `heap.arena_allocator.ArenaAllocator` | 内联 vtable | 碰撞分配器，`deinit` 时批量释放 |

### CAllocator 内部实现

```llvm
define internal fastcc ptr @heap.CAllocator.alloc(ptr %self, ptr %buf, i64 %size, i6 %align, i64 %ret_addr) {
  ; 调用 posix_memalign
  %err = call i32 @posix_memalign(ptr %out, i64 %alignment, i64 %size)
  ...
}

define internal fastcc void @heap.CAllocator.free(ptr %self, ptr %buf, ptr %ptr, i64 %size, i6 %align, i64 %ret_addr) {
  call void @free(ptr %ptr)  ; 直接调用 C 的 free()
}
```

**影响**：Zig 的 `c_allocator` 直接映射到 C 的 `malloc`/`free`。跨语言分析必须识别 `heap.CAllocator.free` → `free()` 的映射。

### Zig 特有 IR 模式

| 模式 | 描述 |
|------|------|
| `fastcc` 调用约定 | 所有 Zig 内部函数使用 |
| `sret` 参数 | 通过隐藏指针参数返回结构体 |
| `debug.assert` | 安全构建中插入的运行时检查 |
| `@llvm.memset.p0.i64(ptr, i8 -86, ...)` | 用 `0xAA` 模式进行调试填充 |
| 点分隔名称 | `heap.CAllocator.alloc` 而非 C++ 的修饰名 |

### 类型命名约定

Zig 使用点分隔的命名空间表示法：

```
heap.CAllocator.alloc          → std.heap.CAllocator.alloc
mem.Allocator                  → std.mem.Allocator
debug.panicExtra__anon_2450    → 带 ID 的泛型实例化
```

`__anon_NNNN` 后缀标识单态化的泛型实例。

### 内存安全特性

Zig 在安全构建中插入运行时检查：

```llvm
; 数组访问前的边界检查
%ok = icmp ult i64 %index, %len
br i1 %ok, label %access, label %panic

panic:
  call fastcc void @debug.panicExtra__anon_NNNN(...)
```

---

## 总结：跨语言检测影响

| 语言 | 分配器 | 析构器 | 异常 | FFI 标记 |
|------|--------|--------|------|---------|
| Rust | `__rust_alloc`/`__rust_dealloc` | Drop 胶水 `_ZN...4drop...` | `invoke`/`landingpad` 清理 | `_R` 前缀修饰 |
| C++ | `_Znam`/`_Znwm`/`_ZdlPvm` | 析构函数 `_ZN...D1Ev` | `invoke`/`landingpad` + `__gxx_personality_v0` | `_Z` 前缀修饰 |
| Go (cgo) | `_cgo_allocate`/`_cgo_free` | 无（无析构器） | 无 | `_cgo_` / `_Cfunc_` 前缀 |
| Java (JNI) | 无（JVM 管理） | `DeleteGlobalRef` | JNI 异常检查 | `JNIenv*` 首参数 |
| Python | 无（CPython 管理） | `Py_DECREF` 引用计数 | 无 | `Py_`/`PyObject_` 前缀 |
| Swift | `swift_allocObject` | `swift_release` ARC | 无 | `swiftcc` 调用约定，`$s` 修饰 |
| Zig | `heap.CAllocator` → `free()` | `deinit` 方法 | `debug.assert` panic | `fastcc` 约定，点分隔名称 |
