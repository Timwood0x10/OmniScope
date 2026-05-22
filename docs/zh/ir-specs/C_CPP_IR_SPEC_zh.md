# C/C++ LLVM IR 规范：编译器保留 vs 用户定义

**来源**: LLVM/Clang 头文件 (`/opt/homebrew/opt/llvm/include/clang/CodeGen/`, `/opt/homebrew/opt/llvm/include/clang/AST/`)、OmniScope 语料库 (`corpus/real_world/`, `corpus/ffi-dense/`, `corpus/red_team_test/`)
**日期**: 2026-05-22
**目的**: 为静态分析工具（如 OmniScope）区分编译器保留的 IR 模式与用户定义的符号

---

## 1. 符号命名 / 名称修饰

### 1.1 C 函数（无修饰）

C 函数在 LLVM IR 中以其原始名称出现，不添加前缀或编码。

| 模式 | 示例 IR 符号 | 来源证据 |
|------|-------------|---------|
| 普通 C 函数 | `@sqlite3_open`、`@sqlite3_exec` | `corpus/real_world/other/sqlite3.ll:2330` |
| C 标准库 | `@malloc`、`@free`、`@printf` | `corpus/real_world/other/sqlite3.ll:2535` |
| C 库（检查版本） | `@__sprintf_chk`、`@__strcpy_chk` | `corpus/ffi-dense/sqlite_binding.ll:180,114` |
| C FFI 函数 | `@inflateInit_`、`@deflate` | `corpus/ffi-dense/zlib_binding.ll:38,237` |
| OpenSSL C API | `@EVP_CIPHER_CTX_new`、`@RSA_new` | `corpus/ffi-dense/openssl_wrapper.ll:42,90` |

**检测规则**：不以 `_Z` 开头且不是已知编译器内置函数的函数名即为 C 函数。

### 1.2 C++ Itanium ABI 名称修饰

Itanium C++ ABI 使用 `_Z` 前缀修饰所有名称。这是 Linux、macOS 和大多数类 Unix 系统的默认方式。

#### 1.2.1 基本编码规则

| 模式 | 示例 IR 符号 | 反修饰后 | 来源证据 |
|------|-------------|---------|---------|
| 自由函数 | `@_Z3fooi` | `foo(int)` | Itanium ABI 规范 |
| 命名空间::函数 | `@_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE` | `absl::Cord::Append(std::__1::basic_string_view<char, ...>)` | `corpus/real_world/other/abseil2024.ll:787` |
| 嵌套类型 | `@_ZN4absl4Cord9InlineRep11EmplaceTreeE...` | `absl::Cord::InlineRep::EmplaceTree(...)` | `corpus/real_world/other/abseil2024.ll:674` |
| 内部链接 | `@_ZN4abslL17CordRepFromStringE...` | `absl::(anonymous)::CordRepFromString(...)` | `corpus/real_world/other/abseil2024.ll:570` |

#### 1.2.2 命名空间/类编码

命名空间和类编码为 `<长度><名称>`：

| 源代码 | 修饰前缀 | 含义 |
|--------|---------|------|
| `std::__1` | `NSt3__1` | `std::__1` 命名空间（libc++） |
| `absl` | `N4absl` | `absl` 命名空间 |
| `absl::Cord` | `N4absl4Cord` | `absl::Cord` 类 |
| `std::__1::vector<int>` | `NSt3__16vectorIiNS_9allocatorIiEEEE` | 带参数的模板类 |

来源：`corpus/real_world/other/abseil2024.ll:6-7` -- `%"class.std::__1::basic_string_view"` 类型在函数名中使用 `NSt3__1` 编码。

#### 1.2.3 构造函数/析构函数后缀

Itanium ABI 为构造函数和析构函数定义了特殊后缀：

| 后缀 | 含义 | 示例 | 来源证据 |
|------|------|------|---------|
| `C1` | 完整构造函数（最派生类） | `@_ZN4absl4CordC1INSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEETnNS2_9enable_ifIXsr3std7is_sameIT_S8_EE5valueEiE4typeELi0EEEOSA_` | `corpus/real_world/other/abseil2024.ll:733` |
| `C2` | 基类构造函数（基类子对象） | `@_ZN4absl4CordC2INSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEETnNS2_9enable_ifIXsr3std7is_sameIT_S8_EE5valueEiE4typeELi0EEEOSA_` | `corpus/real_world/other/abseil2024.ll:431` |
| `D0` | 删除析构函数（释放内存） | `@_ZN7DerivedD0Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:33`（在 vtable 中） |
| `D1` | 完整析构函数（销毁成员） | `@_ZN7DerivedD1Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:33`（在 vtable 中） |
| `D2` | 基类析构函数（基类子对象） | `@_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED2B8ne210108Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:211` |

**检测规则**：如果修饰名称以 `C1`、`C2`、`C3`（委托）、`D0`、`D1` 或 `D2` 结尾（后跟 `E` 和额外模板参数），则为构造函数或析构函数。

#### 1.2.4 特殊符号前缀

| 前缀 | 含义 | 示例 | 来源证据 |
|------|------|------|---------|
| `_ZTV` | 虚函数表 | `@_ZTV7Derived` | `corpus/red_team_test/v018_cpp_ffi.ll:33` |
| `_ZTI` | 类型信息对象 | `@_ZTI7Derived` | `corpus/red_team_test/v018_cpp_ffi.ll:34` |
| `_ZTS` | 类型信息名称字符串 | `@_ZTS7Derived` = `c"7Derived\00"` | `corpus/red_team_test/v018_cpp_ffi.ll:36` |
| `_ZTT` | VTT（虚函数表表） | `@_ZTTNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE` | `corpus/real_world/other/abseil2024.ll:271` |
| `_ZTVN10__cxxabiv1` | C++ ABI 运行时 vtable | `@_ZTVN10__cxxabiv120__si_class_type_infoE` | `corpus/red_team_test/v018_cpp_ffi.ll:35` |
| `_ZGV` | 线程安全静态变量的守卫变量 | （在 libc++ 头文件中可见） | Itanium ABI 规范 |

#### 1.2.5 模板实例化模式

模板产生带有 `I...E` 参数编码的长修饰名称：

```
@_ZNSt3__111make_uniqueB8ne210108IiJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10unique_ptrIS2_NS_14default_deleteIS2_EEEEDpOT0_
```

反修饰后：`std::__1::enable_if<...>::type std::__1::make_unique<int, int>(int&&)`

`B8ne210108` 后缀是 Clang ABI 标签（`__attribute__((abi_tag()))` 的调用者编码）。

来源：`corpus/red_team_test/v018_cpp_ffi.ll:137`

### 1.3 MSVC 名称修饰（参考）

MSVC 使用 `?` 前缀。这主要在 Windows 目标上相关。OmniScope 应将 `?` 前缀的符号检测为 MSVC 修饰的 C++。

| 前缀 | 含义 |
|------|------|
| `?` | MSVC 修饰名称起始 |
| `?0` | 构造函数 |
| `?1` | 析构函数 |

### 1.4 `extern "C"` 链接

使用 `extern "C"` 声明的函数会抑制 C++ 名称修饰，以普通 C 名称出现：

| 模式 | 示例 | 来源证据 |
|------|------|---------|
| `extern "C"` 函数 | `@c_free`、`@c_take_ptr`、`@c_malloc` | `corpus/red_team_test/v018_cpp_ffi.ll:53,66,87` |
| `extern "C"` 回调注册 | `@c_register_callback(ptr %cb, ptr %ctx)` | `corpus/red_team_test/v018_cpp_ffi.ll:75` |

**检测规则**：在 C++ 编译单元（source_filename 以 `.cpp`/`.cc` 结尾）中，没有 `_Z` 前缀且不是 `main` 或编译器内置函数的函数很可能是 `extern "C"`。

---

## 2. FFI 模式

### 2.1 链接说明符

| 属性 | IR 表示 | 示例 | 来源证据 |
|------|---------|------|---------|
| `extern "C"` | 无修饰，普通名称 | `@c_free(ptr noundef %p)` | `corpus/red_team_test/v018_cpp_ffi.ll:53` |
| `__attribute__((visibility("default")))` | `default` 可见性 | （标准导出） | Clang CodeGen |
| `__attribute__((visibility("hidden")))` | `hidden` 可见性 | `linkonce_odr hidden` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `__attribute__((weak))` | `weak` 链接 | `weak_odr` | `corpus/real_world/other/abseil2024.ll:431` |
| `__attribute__((alias(...)))` | `@alias = alias ...` | （别名定义） | LLVM IR 参考 |

### 2.2 C++ IR 中的链接类型

| 链接类型 | 含义 | 示例 | 来源证据 |
|---------|------|------|---------|
| `external` | 外部定义 | `declare i32 @__gxx_personality_v0(...)` | `corpus/real_world/other/abseil2024.ll:1534` |
| `linkonce_odr` | 链接一次 ODR（内联/模板） | `define linkonce_odr void @_ZN4absl4Cord6Append...` | `corpus/real_world/other/abseil2024.ll:787` |
| `weak_odr` | 弱 ODR（显式实例化） | `define weak_odr noundef ptr @_ZN4absl4CordC1...` | `corpus/real_world/other/abseil2024.ll:733` |
| `internal` | 文件局部（static） | `define internal noundef ptr @_ZN4abslL17CordRepFromStringE...` | `corpus/real_world/other/abseil2024.ll:570` |
| `private` | 私有（严格内部） | `@.str = private unnamed_addr constant ...` | `corpus/real_world/other/abseil2024.ll:189` |

**检测规则**：`linkonce_odr` 和 `weak_odr` 函数通常是模板实例化或内联方法。`internal` 和 `private` 是文件作用域。`external` 是声明的默认值。

### 2.3 FFI 边界标记

| 标记 | 模式 | 检测规则 |
|------|------|---------|
| 从 C++ 调用 C 函数 | C++ 编译单元中的普通名称 | 在 `.cpp` 文件中调用 `@free`、`@malloc`、`@sqlite3_open` |
| 从 C 调用 C++ 函数 | `extern "C"` 包装器 | `_Z` 前缀的函数通过普通名称包装器调用 |
| 跨语言调用 | 修饰不匹配 | `_ZN...` 函数调用普通 C 函数，或反之 |

---

## 3. 内存管理

### 3.1 C 分配函数

| IR 符号 | 签名 | 来源证据 |
|---------|------|---------|
| `@malloc` | `(i64) -> ptr` | `corpus/ffi-dense/sqlite_binding.ll:111`、`corpus/ffi-dense/zlib_binding.ll:118` |
| `@calloc` | `(i64, i64) -> ptr` | C 标准库 |
| `@realloc` | `(ptr, i64) -> ptr` | C 标准库 |
| `@free` | `(ptr) -> void` | `corpus/ffi-dense/sqlite_binding.ll:119`、`corpus/ffi-dense/zlib_binding.ll:120` |
| `@aligned_alloc` | `(i64, i64) -> ptr` | C11 标准 |

**检测规则**：`@malloc` 和 `@free` 是主要的 C 分配/释放配对。对来自不同分配器的内存调用 `free` 是跨语言内存错误。

### 3.2 C++ 分配运算符

| IR 符号 | 修饰名称 | 签名 | 来源证据 |
|---------|---------|------|---------|
| `operator new(unsigned long)` | `@_Znwm` | `(i64) -> ptr` | `corpus/red_team_test/v018_cpp_ffi.ll:375` |
| `operator delete(void*)` | `@_ZdlPv` | `(ptr) -> void` | （隐式，通过析构函数调用） |
| `operator delete(void*, unsigned long)` | `@_ZdlPvm` | `(ptr, i64) -> void` | `corpus/red_team_test/v018_cpp_ffi.ll:646` |
| `operator new(unsigned long, std::align_val_t)` | `@_ZnwmSt11align_val_t` | `(i64, i64) -> ptr` | `corpus/red_team_test/v018_cpp_ffi.ll:1487` |
| `operator delete(void*, unsigned long, std::align_val_t)` | `@_ZdlPvmSt11align_val_t` | `(ptr, i64, i64) -> void` | `corpus/red_team_test/v018_cpp_ffi.ll:2678` |
| `operator new[](unsigned long)` | `@_Znam` | `(i64) -> ptr` | Itanium ABI 规范 |
| `operator delete[](void*)` | `@_ZdaPv` | `(ptr) -> void` | Itanium ABI 规范 |

**检测规则**：以 `_Znw` 开头的函数是 `operator new` 变体。以 `_Zdl` 开头的函数是 `operator delete` 变体。混用 C `malloc`/`free` 和 C++ `operator new`/`operator delete` 是内存安全错误。

### 3.3 堆分配属性

Clang 为分配调用标注特殊属性：

```llvm
%call = call noalias noundef nonnull ptr @_Znwm(i64 noundef 4) #15, !heapallocsite !16
```

| 属性 | 含义 | 来源证据 |
|------|------|---------|
| `noalias` | 返回值不与任何现有指针别名 | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `nonnull` | 返回值永不为 null | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `!heapallocsite` | 指向分配位置的调试元数据 | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `allocsize(0)` | 大小是第一个参数 | `corpus/ffi-dense/sqlite_binding.ll:110` |

### 3.4 栈分配

| IR 符号 | 含义 | 来源证据 |
|---------|------|---------|
| `alloca <type>` | 栈分配 | 语料库中每个函数（如 `corpus/ffi-dense/sqlite_binding.ll:20-23`） |
| `@llvm.stacksave` | 保存栈指针 | LLVM 内在函数 |
| `@llvm.stackrestore` | 恢复栈指针 | LLVM 内在函数 |

### 3.5 跨语言内存安全模式

| 错误模式 | 描述 | 来源证据 |
|---------|------|---------|
| C `malloc` + C++ `delete` | 对 `malloc` 分配的内存使用 `operator delete` | `corpus/red_team_test/v018_cpp_ffi.ll:186`（`bug_cpp_02_c_malloc_to_cpp_delete`） |
| C++ `new` + C `free` | 对 `operator new` 分配的内存使用 `free` | `corpus/red_team_test/v018_cpp_ffi.ll:101`（`bug_cpp_01_unique_ptr_to_c_free`） |
| `unique_ptr` 使用 C 分配器 | `unique_ptr` 从 `malloc` 结果构造，析构函数调用 `delete` | `corpus/red_team_test/v018_cpp_ffi.ll:186-196` |

---

## 4. 异常处理

### 4.1 人格函数

| 人格函数 | 语言 | 示例 | 来源证据 |
|---------|------|------|---------|
| `@__gxx_personality_v0` | C++ | `personality ptr @__gxx_personality_v0` | `corpus/real_world/other/abseil2024.ll:1534` |
| `@__gcc_personality_v0` | C（带清理） | `personality ptr @__gcc_personality_v0` | GCC 运行时 |

**检测规则**：带有 `personality ptr @__gxx_personality_v0` 的函数是可能抛出或捕获异常的 C++ 函数。

### 4.2 Invoke / Landing Pad 模式

`invoke` 指令在被调用者可能抛出异常时替代 `call`：

```llvm
; 来自 abseil2024.ll:633-670
%call11 = invoke noundef ptr @_ZN4absl13cord_internal14NewExternalRep...(
    [2 x i64] %9, ptr noundef nonnull align 8 dereferenceable(24) %ref.tmp)
        to label %invoke.cont unwind label %lpad, !dbg !10475

invoke.cont:                          ; 正常继续
  ...

lpad:                                 ; 着陆垫（异常处理器）
  %13 = landingpad { ptr, i32 }
          cleanup, !dbg !10476        ; 清理动作（如析构函数）
  ...

eh.resume:                            ; 恢复异常传播
  resume { ptr, i32 } %lpad.val17
```

来源：`corpus/real_world/other/abseil2024.ll:633-670`

### 4.3 Landing Pad 子句

| 子句 | 含义 | 示例 | 来源证据 |
|------|------|------|---------|
| `cleanup` | 总是运行（RAII 析构函数） | `landingpad { ptr, i32 } cleanup` | `corpus/red_team_test/v018_cpp_ffi.ll:119-120` |
| `catch ptr @_ZTI...` | 捕获特定类型 | `landingpad ... catch ptr @_ZTISt12out_of_range` | `corpus/real_world/other/abseil2024.ll:397` |
| `filter` | 异常规格过滤器 | （现代 C++ 中少见） | LLVM IR 参考 |

### 4.4 异常处理函数

| IR 符号 | 用途 | 来源证据 |
|---------|------|---------|
| `@__cxa_throw` | 抛出异常 | C++ ABI |
| `@__cxa_begin_catch` | 开始 catch 块 | C++ ABI |
| `@__cxa_end_catch` | 结束 catch 块 | C++ ABI |
| `@__cxa_rethrow` | 重新抛出当前异常 | C++ ABI |
| `@_Unwind_Resume` | 恢复展开 | Itanium EH ABI |
| `@__cxa_allocate_exception` | 分配异常对象 | C++ ABI |
| `@__cxa_free_exception` | 释放异常对象 | C++ ABI |

### 4.5 RAII 清理模式

C++ 析构函数在 landing pad 中被调用以进行 RAII 清理：

```llvm
; 来自 v018_cpp_ffi.ll:118-133
lpad:
  %0 = landingpad { ptr, i32 }
          cleanup, !dbg !3044
  %1 = extractvalue { ptr, i32 } %0, 0
  store ptr %1, ptr %exn.slot, align 8
  %2 = extractvalue { ptr, i32 } %0, 1
  store i32 %2, ptr %ehselector.slot, align 4
  %call2 = call noundef ptr @_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED1Ev(...)
  br label %eh.resume

eh.resume:
  %exn = load ptr, ptr %exn.slot, align 8
  %sel = load i32, ptr %ehselector.slot, align 4
  %lpad.val = insertvalue { ptr, i32 } poison, ptr %exn, 0
  %lpad.val3 = insertvalue { ptr, i32 } %lpad.val, i32 %sel, 1
  resume { ptr, i32 } %lpad.val3
```

来源：`corpus/red_team_test/v018_cpp_ffi.ll:118-133`

---

## 5. VTable / RTTI

### 5.1 VTable 布局

VTable 作为 unnamed_addr 常量全局变量发出。布局遵循 Itanium ABI：

| 槽位 | 内容 | 说明 |
|------|------|------|
| -2 | 到顶部的偏移量 | `i64` 从派生类到虚基类的偏移量 |
| -1 | 指向 RTTI（`_ZTI`）的指针 | 指向 typeinfo 对象 |
| 0 | 第一个虚函数 | 通常是 `virtual void f()` 或析构函数 |
| 1 | 第二个虚函数 | 等等 |

```llvm
; 来自 v018_cpp_ffi.ll:33
@_ZTV7Derived = linkonce_odr unnamed_addr constant { [5 x ptr] } {
  [5 x ptr] [
    ptr null,                    ; 到顶部的偏移量（主 vtable 总是 0）
    ptr @_ZTI7Derived,           ; 指向 RTTI 的指针
    ptr @_ZN7Derived1fEv,        ; 虚函数 f()
    ptr @_ZN7DerivedD1Ev,        ; 完整析构函数
    ptr @_ZN7DerivedD0Ev         ; 删除析构函数
  ]
}, align 8
```

来源：`corpus/red_team_test/v018_cpp_ffi.ll:33`

### 5.2 多重继承的 VTable

对于有多个基类的类，vtable 包含调整器 thunk：

```llvm
; 来自 v018_cpp_ffi.ll:45（shared_ptr_emplace 有 7 个槽位）
@_ZTVNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE = linkonce_odr unnamed_addr constant { [7 x ptr] } {
  [7 x ptr] [
    ptr null,                    ; 到顶部的偏移量
    ptr @_ZTINSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE,  ; RTTI
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEED1Ev,  ; 完整析构函数
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEED0Ev,  ; 删除析构函数
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEE16__on_zero_sharedEv,      ; 虚函数 __on_zero_shared
    ptr @_ZNKSt3__119__shared_weak_count13__get_deleterERKSt9type_info,  ; 虚函数 __get_deleter
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEE21__on_zero_shared_weakEv  ; 虚函数 __on_zero_shared_weak
  ]
}, align 8
```

来源：`corpus/red_team_test/v018_cpp_ffi.ll:45`

### 5.3 RTTI 对象结构

RTTI（`_ZTI`）对象包含：

| 字段 | 内容 | 示例 |
|------|------|------|
| 0 | 指向 `__cxxabiv1` 类型信息类的指针 | `@_ZTVN10__cxxabiv120__si_class_type_infoE` |
| 1 | 指向类型信息名称（`_ZTS`）的指针 | `@_ZTS7Derived`（带高位标志） |
| 2（可选） | 指向基类 RTTI 的指针 | `@_ZTI4Base`（单继承） |

```llvm
; 简单类 RTTI（单继承）
@_ZTI7Derived = linkonce_odr hidden constant { ptr, ptr, ptr } {
  ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv120__si_class_type_infoE, i64 2),
  ptr inttoptr (i64 add (i64 ptrtoint (ptr @_ZTS7Derived to i64), i64 -9223372036854775808) to ptr),
  ptr @_ZTI4Base
}, align 8

; 基类 RTTI（无基类）
@_ZTI4Base = linkonce_odr hidden constant { ptr, ptr } {
  ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv117__class_type_infoE, i64 2),
  ptr inttoptr (i64 add (i64 ptrtoint (ptr @_ZTS4Base to i64), i64 -9223372036854775808) to ptr)
}, align 8
```

来源：`corpus/red_team_test/v018_cpp_ffi.ll:34,37`

### 5.4 RTTI 名称字符串

类型信息名称字符串（`_ZTS`）包含裸类名：

| 符号 | 字符串内容 | 含义 |
|------|-----------|------|
| `@_ZTS7Derived` | `c"7Derived\00"` | 类 `Derived` |
| `@_ZTS4Base` | `c"4Base\00"` | 类 `Base` |
| `@_ZTSNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE` | `c"NSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE\00"` | 模板类 |

来源：`corpus/red_team_test/v018_cpp_ffi.ll:36,39,47`

### 5.5 VTT（虚函数表表）

对于有虚继承的类，会发出 VTT：

```llvm
@_ZTTNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE = external unnamed_addr constant [4 x ptr], align 8
```

VTT 是一个指针数组，指向在构造和销毁期间使用的 vtable 条目。

来源：`corpus/real_world/other/abseil2024.ll:271`

### 5.6 `__cxxabiv1` 类型信息类

| 符号 | C++ 类型 | 用途 |
|------|---------|------|
| `@_ZTVN10__cxxabiv117__class_type_infoE` | `__cxxabiv1::__class_type_info` | 无基类的类 |
| `@_ZTVN10__cxxabiv120__si_class_type_infoE` | `__cxxabiv1::__si_class_type_info` | 单继承 |
| `@_ZTVN10__cxxabiv121__vmi_class_type_infoE` | `__cxxabiv1::__vmi_class_type_info` | 多重/虚继承 |

来源：`corpus/red_team_test/v018_cpp_ffi.ll:35,38`

---

## 6. 编译器内置函数到 LLVM 内在函数

### 6.1 内存内在函数

| C/C++ 内置函数 | LLVM IR 内在函数 | 示例 | 来源证据 |
|---------------|-----------------|------|---------|
| `__builtin_memcpy` / `memcpy` | `@llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)` | `call void @llvm.memcpy.p0.p0.i64(ptr align 8 %agg.tmp, ptr align 8 %src, i64 16, i1 false)` | `corpus/real_world/other/abseil2024.ll:628` |
| `__builtin_memset` / `memset` | `@llvm.memset.p0.i64(ptr, i8, i64, i1)` | `call void @llvm.memset.p0.i64(ptr align 8 %agg.result, i8 0, i64 16, i1 false)` | `corpus/real_world/other/abseil2024.ll:3871` |
| `__builtin_objectsize` | `@llvm.objectsize.i64.p0(ptr, i1, i1, i1)` | `%12 = call i64 @llvm.objectsize.i64.p0(ptr %11, i1 false, i1 true, i1 false)` | `corpus/ffi-dense/sqlite_binding.ll:98` |

### 6.2 算术内在函数

| C/C++ 内置函数 | LLVM IR 内在函数 | 说明 |
|---------------|-----------------|------|
| `__builtin_expect` | `@llvm.expect.i64(i64, i64)` | 分支预测提示 |
| `__builtin_ctz` | `@llvm.cttz.i32(i32, i1)` | 计算尾部零的数量 |
| `__builtin_clz` | `@llvm.ctlz.i32(i32, i1)` | 计算前导零的数量 |
| `__builtin_popcount` | `@llvm.ctpop.i32(i32)` | 人口计数 |
| `__builtin_bswap` | `@llvm.bswap.i32(i32)` | 字节交换 |
| `__builtin_add_overflow` | `@llvm.sadd.with.overflow.i32(i32, i32)` | 溢出检查加法 |
| `__builtin_mul_overflow` | `@llvm.smul.with.overflow.i32(i32, i32)` | 溢出检查乘法 |

### 6.3 数学内在函数

| C/C++ 内置函数 | LLVM IR 内在函数 |
|---------------|-----------------|
| `__builtin_sqrt` | `@llvm.sqrt.f64(double)` |
| `__builtin_sin` | `@llvm.sin.f64(double)` |
| `__builtin_cos` | `@llvm.cos.f64(double)` |
| `__builtin_fma` | `@llvm.fma.f64(double, double, double)` |
| `__builtin_fabs` | `@llvm.fabs.f64(double)` |
| `__builtin_copysign` | `@llvm.copysign.f64(double, double)` |
| `__builtin_floor` | `@llvm.floor.f64(double)` |
| `__builtin_ceil` | `@llvm.ceil.f64(double)` |
| `__builtin_round` | `@llvm.round.f64(double)` |

### 6.4 控制流内在函数

| C/C++ 内置函数 | LLVM IR | 示例 |
|---------------|---------|------|
| `__builtin_unreachable` | `unreachable` | LLVM 终止指令 |
| `__builtin_trap` | `@llvm.trap()` | 停止执行 |
| `__builtin_debugtrap` | `@llvm.debugtrap()` | 调试断点 |

### 6.5 可变参数

| C/C++ 构造 | LLVM IR | 来源证据 |
|-----------|---------|---------|
| `va_start` | `@llvm.va_start.p0(ptr %ap)` | `corpus/real_world/other/sqlite3.ll:9609` |
| `va_end` | `@llvm.va_end.p0(ptr %ap)` | `corpus/real_world/other/sqlite3.ll:9614` |
| `va_copy` | `@llvm.va_copy(ptr %dst, ptr %src)` | LLVM IR 参考 |

---

## 7. Clang 的 IR 属性（UB 利用）

Clang 将属性附加到 IR 值，编码语言级别的保证。这些对静态分析至关重要，因为它们代表了编译器所做的假设。

### 7.1 参数/返回值属性

| 属性 | 含义 | 示例 | 来源证据 |
|------|------|------|---------|
| `noundef` | 值永远不是 `undef` 或 `poison` | `ptr noundef %0` | `corpus/ffi-dense/sqlite_binding.ll:19` |
| `nonnull` | 指针永不为 null | `ptr noundef nonnull align 8 dereferenceable(16) %this` | `corpus/real_world/other/abseil2024.ll:1335` |
| `dereferenceable(N)` | 至少 N 字节可解引用 | `ptr noundef nonnull align 8 dereferenceable(16)` | `corpus/real_world/other/abseil2024.ll:1335` |
| `align N` | 指针具有 N 字节对齐 | `ptr align 8 %agg.tmp` | `corpus/real_world/other/abseil2024.ll:628` |
| `returned` | 值原样返回 | `ptr noundef nonnull returned align 8 dereferenceable(16) %this` | `corpus/red_team_test/v018_cpp_ffi.ll:175` |
| `sret(%type)` | 结构体返回（隐藏指针参数） | `ptr dead_on_unwind writable sret(%"class.std::__1::unique_ptr") align 8 %agg.result` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `noalias` | 无别名（TBAA） | `ptr dead_on_unwind noalias writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `writable` | 指向的内存被写入 | `ptr dead_on_unwind writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `dead_on_unwind` | 展开时值已死亡 | `ptr dead_on_unwind writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |

### 7.2 函数属性

| 属性 | 含义 | 示例 | 来源证据 |
|------|------|------|---------|
| `nounwind` | 函数不抛出异常 | `#1 = { nounwind }` | `corpus/ffi-dense/sqlite_binding.ll:63` |
| `noreturn` | 函数不返回 | （如 `abort`、`exit`） | LLVM IR 参考 |
| `readnone` | 函数不读取内存 | （纯函数） | LLVM IR 参考 |
| `readonly` | 函数只读取内存 | （常量函数） | LLVM IR 参考 |
| `mustprogress` | 函数必须取得进展 | `mustprogress noinline optnone ssp uwtable(sync)` | `corpus/red_team_test/v018_cpp_ffi.ll:52` |
| `willreturn` | 函数最终会返回 | （非循环） | LLVM IR 参考 |
| `nosync` | 函数不同步 | （无原子操作/内存屏障） | LLVM IR 参考 |
| `nofree` | 函数不释放内存 | （无释放操作） | LLVM IR 参考 |
| `speculatable` | 函数可以被推测执行 | （安全地推测执行） | `corpus/ffi-dense/sqlite_binding.ll:116` |
| `nocallback` | 函数不回调调用者 | （无回调） | `corpus/ffi-dense/sqlite_binding.ll:116` |
| `allocsize(0)` | 分配大小是第一个参数 | `@malloc` 上的 `allocsize(0)` | `corpus/ffi-dense/sqlite_binding.ll:110` |
| `optnone` | 不优化 | `noinline nounwind optnone ssp uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |
| `ssp` | 栈粉碎保护 | `ssp uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |
| `uwtable(sync)` | 展开表（同步） | `uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |

### 7.3 属性组

属性通常被分组并按编号引用：

```llvm
attributes #0 = { mustprogress noinline optnone ssp uwtable(sync) }
attributes #1 = { nounwind }
attributes #2 = { allocsize(0) }
attributes #3 = { nounwind willreturn memory(none) }
```

来源：`corpus/ffi-dense/sqlite_binding.ll`（属性组在整个文件中被引用）

---

## 8. C++ 语言特性在 IR 中的表示

### 8.1 构造函数/析构函数调用约定

构造函数接收 `this` 作为第一个参数并返回 `this`：

```llvm
; 完整构造函数（C1）
define linkonce_odr noundef ptr @_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEEC1B8ne210108ILb1EvEEPi(
    ptr noundef nonnull returned align 8 dereferenceable(8) %this,
    ptr noundef %__p) unnamed_addr #2
```

析构函数也接收 `this` 并可能返回 `this`：

```llvm
; 完整析构函数（D1）
define linkonce_odr hidden noundef ptr @_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED1B8ne210108Ev(
    ptr noundef nonnull returned align 8 dereferenceable(8) %this) unnamed_addr #2
```

来源：`corpus/red_team_test/v018_cpp_ffi.ll:175,201`

### 8.2 调整器 Thunk

对于多重继承，编译器生成调整 `this` 指针的 thunk：

```llvm
; 当通过 Base* 接口调用 Derived::f() 时的 Thunk
define linkonce_odr void @_ZThn8_N7Derived1fEv(ptr noundef %this) {
  %this.addr = getelementptr inbounds i8, ptr %this, i64 -8  ; 调整 this
  call void @_ZN7Derived1fEv(ptr %this.addr)
  ret void
}
```

`_ZTh` 前缀表示调整器 thunk。`n8` 表示"从 this 中减去 8"。

### 8.3 线程安全静态变量的守卫变量

局部静态变量使用守卫变量确保一次性初始化：

```llvm
; 守卫变量模式
@_ZGVZ3fooEvE1x = internal global i8 0, align 1  ; 守卫变量

define void @_Z3fooEv() {
entry:
  %0 = load i8, ptr @_ZGVZ3fooEvE1x, align 1
  %guard.has.init = icmp eq i8 %0, 0
  br i1 %guard.has.init, label %init.check, label %init.end

init.check:
  %guard.is.valid = call i1 @__cxa_guard_acquire(ptr @_ZGVZ3fooEvE1x)
  br i1 %guard.is.valid, label %init, label %init.end

init:
  ; ... 初始化静态变量 ...
  call void @__cxa_guard_release(ptr @_ZGVZ3fooEvE1x)
  br label %init.end

init.end:
  ; ... 使用静态变量 ...
}
```

`_ZGV` 前缀标记守卫变量。`@__cxa_guard_acquire` 和 `@__cxa_guard_release` 管理初始化。

### 8.4 `this` 指针参数

C++ 成员函数将 `this` 作为隐式第一个参数接收：

```llvm
; 成员函数：absl::Cord::InlineRep::AppendTreeToTree(...)
define void @_ZN4absl4Cord9InlineRep16AppendTreeToTreeEPNS_13cord_internal7CordRepENS2_18CordzUpdateTracker16MethodIdentifierE(
    ptr noundef nonnull align 8 dereferenceable(16) %this,  ; 隐式 this
    ptr noundef %tree,                                        ; 显式参数 1
    i32 noundef %method)                                      ; 显式参数 2
```

来源：`corpus/real_world/other/abseil2024.ll:1335`

### 8.5 结构体返回（sret）

大的返回值使用隐藏指针参数：

```llvm
define linkonce_odr hidden void @_ZNSt3__111make_uniqueB8ne210108IiJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10unique_ptrIS2_NS_14default_deleteIS2_EEEEDpOT0_(
    ptr dead_on_unwind noalias writable sret(%"class.std::__1::unique_ptr") align 8 %agg.result,
    ptr noundef nonnull align 4 dereferenceable(4) %__args)
```

`sret(%type)` 属性表示隐藏的结构体返回参数。

来源：`corpus/red_team_test/v018_cpp_ffi.ll:137`

### 8.6 ABI 标签

Clang 为带有 `__attribute__((abi_tag(...)))` 的函数发出 ABI 标签（如 `B8ne210108`）：

```
_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED1B8ne210108Ev
                                                      ^^^^^^^^
                                                      ABI 标签
```

这在 libc++ 中很常见，用于 ABI 版本控制。

来源：`corpus/red_team_test/v018_cpp_ffi.ll:175`

---

## 9. 静态分析的关键要点

### 9.1 要分析的内容（用户代码）

| 类别 | 检测规则 | 示例 |
|------|---------|------|
| C 函数 | 无 `_Z` 前缀，不是已知内置函数 | `@sqlite3_open`、`@my_function` |
| C++ 用户函数 | `_Z` 前缀 + 用户命名空间（非 `std::__1`、`__cxxabiv1`） | `@_ZN4absl4Cord...` |
| `extern "C"` 函数 | C++ 编译单元中的普通名称 | `@c_free`、`@c_malloc` |
| 用户定义类 | 带用户命名空间的 VTable/RTTI | `@_ZTV7Derived`、`@_ZTI7Derived` |

### 9.2 要过滤的内容（编译器生成 / 标准库）

| 类别 | 检测规则 | 示例 |
|------|---------|------|
| C++ ABI 运行时 | `_ZTVN10__cxxabiv1*`、`_ZTIN10__cxxabiv1*` | `@_ZTVN10__cxxabiv120__si_class_type_infoE` |
| 标准库 | `NSt3__1`（libc++）、`St`（libstdc++） | `@_ZNSt3__110unique_ptr...`、`@_ZNSt3__16vector...` |
| 异常处理 | `@__gxx_personality_v0`、`@__cxa_*`、`@_Unwind_*` | 所有 EH 基础设施 |
| 运算符 new/delete | `_Znwm*`、`_Zdl*`、`_Znam*`、`_Zda*` | `@_Znwm`、`@_ZdlPvm` |
| LLVM 内在函数 | `@llvm.*` | `@llvm.memcpy.*`、`@llvm.expect.*` |
| 守卫变量 | `_ZGV` 前缀 | `@_ZGVZ3fooEvE1x` |
| 类型信息运行时 | `_ZTISt*`、`_ZTVSt*`（标准异常） | `@_ZTISt12out_of_range`、`@_ZTVSt12length_error` |
| Thunk | `_ZTh*`、`_ZTv*` | `@_ZThn8_N7Derived1fEv` |

### 9.3 要检测的内存安全模式

| 模式 | 严重程度 | 检测方法 |
|------|---------|---------|
| `malloc` + `delete` | 高 | `@malloc` 结果流向 `@_ZdlPv*` 调用 |
| `new` + `free` | 高 | `@_Znwm*` 结果流向 `@free` 调用 |
| `new` + `delete[]` | 高 | `@_Znwm` 结果流向 `@_ZdaPv` 调用 |
| `new[]` + `delete` | 高 | `@_Znam` 结果流向 `@_ZdlPv` 调用 |
| 释放后使用 | 高 | `@free`/`@_ZdlPv*` 结果在调用后使用 |
| 双重释放 | 高 | 同一指针两次传递给 `@free`/`@_ZdlPv*` |
| 缺少析构函数 | 中 | `invoke` 没有匹配的 `cleanup` landing pad |

### 9.4 FFI 边界标记

| 标记 | 检测规则 | 操作 |
|------|---------|------|
| 跨语言调用 | 从 C++ 编译单元调用 C 函数（或反之） | 标记为 FFI 边界 |
| `extern "C"` 包装器 | 包装修饰名称的普通名称 | 跟踪跨边界数据流 |
| 回调注册 | 跨语言边界传递函数指针 | 分析回调安全性 |
| 共享库导出 | `default` 可见性 + `external` 链接 | 标记为外部接口 |

### 9.5 基于 IR 属性的分析

| 属性 | 分析含义 |
|------|---------|
| `noundef` | 编译器假设无 undef；传递 undef 是 UB |
| `nonnull` | 编译器假设非 null；传递 null 是 UB |
| `dereferenceable(N)` | 必须指向至少 N 字节 |
| `noalias` | 假设无别名；违反是 UB |
| `nounwind` | 不能抛出异常；调用抛出异常的函数是 UB |
| `noreturn` | 必须不返回；返回是 UB |
| `mustprogress` | 必须取得进展；无限循环是 UB |

---

## 附录 A：修饰名称快速参考

### 反修饰工具

```bash
# macOS
echo "_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE" | c++filt

# LLVM 工具
llvm-cxxfilt "_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE"
```

### 常见修饰前缀

| 前缀 | 反修饰后 | 类别 |
|------|---------|------|
| `_Z3` | `foo`（3 字符名称） | 自由函数 |
| `_ZN` | `namespace::` | 命名空间实体 |
| `_ZNK` | `const` 方法 | 常量成员函数 |
| `_ZNS` | `std::` | 标准库 |
| `_ZTV` | vtable | 虚函数表 |
| `_ZTI` | typeinfo | RTTI 对象 |
| `_ZTS` | typeinfo name | RTTI 名称字符串 |
| `_ZTT` | VTT | 虚函数表表 |
| `_ZTh` | thunk（调整器） | 多重继承 thunk |
| `_ZTv` | thunk（虚拟） | 虚调用 thunk |
| `_Znw` | `operator new` | 分配 |
| `_Zdl` | `operator delete` | 释放 |
| `_Zna` | `operator new[]` | 数组分配 |
| `_Zda` | `operator delete[]` | 数组释放 |
| `_ZGV` | 守卫变量 | 线程安全静态初始化 |

---

## 附录 B：修饰中的类型编码

| 编码 | 类型 |
|------|------|
| `v` | `void` |
| `i` | `int` |
| `l` | `long` |
| `m` | `unsigned long` |
| `x` | `long long` |
| `y` | `unsigned long long` |
| `f` | `float` |
| `d` | `double` |
| `b` | `bool` |
| `c` | `char` |
| `w` | `wchar_t` |
| `a` | `signed char` |
| `h` | `unsigned char` |
| `s` | `short` |
| `t` | `unsigned short` |
| `e` | `long double` |
| `g` | `__float128` |
| `Di` | `char32_t` |
| `Ds` | `char16_t` |
| `Da` | `auto` |
| `Dn` | `std::nullptr_t` |
| `P` | 指针（`*`） |
| `R` | 引用（`&`） |
| `O` | 右值引用（`&&`） |
| `S` | 替换（反向引用） |
| `I...E` | 模板参数 |
| `N...E` | 嵌套名称 |
| `K` | `const` |
| `V` | `volatile` |
