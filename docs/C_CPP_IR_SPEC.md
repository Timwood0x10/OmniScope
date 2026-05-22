# C/C++ LLVM IR Specification: Compiler-Reserved vs User-Defined

**Source**: LLVM/Clang headers (`/opt/homebrew/opt/llvm/include/clang/CodeGen/`, `/opt/homebrew/opt/llvm/include/clang/AST/`), OmniScope corpus (`corpus/real_world/`, `corpus/ffi-dense/`, `corpus/red_team_test/`)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming / Name Mangling

### 1.1 C Functions (No Mangling)

C functions appear in LLVM IR with their original names. No prefix or encoding is applied.

| Pattern | Example IR Symbol | Source Evidence |
|---------|-------------------|-----------------|
| Plain C function | `@sqlite3_open`, `@sqlite3_exec` | `corpus/real_world/other/sqlite3.ll:2330` |
| C standard library | `@malloc`, `@free`, `@printf` | `corpus/real_world/other/sqlite3.ll:2535` |
| C library (checked) | `@__sprintf_chk`, `@__strcpy_chk` | `corpus/ffi-dense/sqlite_binding.ll:180,114` |
| C FFI function | `@inflateInit_`, `@deflate` | `corpus/ffi-dense/zlib_binding.ll:38,237` |
| OpenSSL C API | `@EVP_CIPHER_CTX_new`, `@RSA_new` | `corpus/ffi-dense/openssl_wrapper.ll:42,90` |

**Detection rule**: A function name that does NOT start with `_Z` and is NOT a known compiler intrinsic is a C function.

### 1.2 C++ Itanium ABI Name Mangling

The Itanium C++ ABI uses the `_Z` prefix for all mangled names. This is the default on Linux, macOS, and most Unix-like systems.

#### 1.2.1 Basic Encoding Rules

| Pattern | Example IR Symbol | Demangled | Source Evidence |
|---------|-------------------|-----------|-----------------|
| Free function | `@_Z3fooi` | `foo(int)` | Itanium ABI spec |
| Namespace::function | `@_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE` | `absl::Cord::Append(std::__1::basic_string_view<char, ...>)` | `corpus/real_world/other/abseil2024.ll:787` |
| Nested type | `@_ZN4absl4Cord9InlineRep11EmplaceTreeE...` | `absl::Cord::InlineRep::EmplaceTree(...)` | `corpus/real_world/other/abseil2024.ll:674` |
| Internal linkage | `@_ZN4abslL17CordRepFromStringE...` | `absl::(anonymous)::CordRepFromString(...)` | `corpus/real_world/other/abseil2024.ll:570` |

#### 1.2.2 Namespace/Class Encoding

Namespaces and classes are encoded as `<length><name>`:

| Source | Mangled Prefix | Meaning |
|--------|---------------|---------|
| `std::__1` | `NSt3__1` | `std::__1` namespace (libc++) |
| `absl` | `N4absl` | `absl` namespace |
| `absl::Cord` | `N4absl4Cord` | `absl::Cord` class |
| `std::__1::vector<int>` | `NSt3__16vectorIiNS_9allocatorIiEEEE` | Template class with parameters |

Source: `corpus/real_world/other/abseil2024.ll:6-7` -- `%"class.std::__1::basic_string_view"` type with `NSt3__1` encoding in function names.

#### 1.2.3 Constructor / Destructor Suffixes

The Itanium ABI defines special suffixes for constructors and destructors:

| Suffix | Meaning | Example | Source Evidence |
|--------|---------|---------|-----------------|
| `C1` | Complete constructor (most-derived) | `@_ZN4absl4CordC1INSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEETnNS2_9enable_ifIXsr3std7is_sameIT_S8_EE5valueEiE4typeELi0EEEOSA_` | `corpus/real_world/other/abseil2024.ll:733` |
| `C2` | Base constructor (for base class subobject) | `@_ZN4absl4CordC2INSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEETnNS2_9enable_ifIXsr3std7is_sameIT_S8_EE5valueEiE4typeELi0EEEOSA_` | `corpus/real_world/other/abseil2024.ll:431` |
| `D0` | Deleting destructor (deallocates) | `@_ZN7DerivedD0Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:33` (in vtable) |
| `D1` | Complete destructor (destroys members) | `@_ZN7DerivedD1Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:33` (in vtable) |
| `D2` | Base destructor (for base class subobject) | `@_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED2B8ne210108Ev` | `corpus/red_team_test/v018_cpp_ffi.ll:211` |

**Detection rule**: If a mangled name ends with `C1`, `C2`, `C3` (delegating), `D0`, `D1`, or `D2` followed by `E` and additional template args, it is a constructor or destructor.

#### 1.2.4 Special Symbol Prefixes

| Prefix | Meaning | Example | Source Evidence |
|--------|---------|---------|-----------------|
| `_ZTV` | Virtual table | `@_ZTV7Derived` | `corpus/red_team_test/v018_cpp_ffi.ll:33` |
| `_ZTI` | Typeinfo object | `@_ZTI7Derived` | `corpus/red_team_test/v018_cpp_ffi.ll:34` |
| `_ZTS` | Typeinfo name string | `@_ZTS7Derived` = `c"7Derived\00"` | `corpus/red_team_test/v018_cpp_ffi.ll:36` |
| `_ZTT` | VTT (Virtual Table Table) | `@_ZTTNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE` | `corpus/real_world/other/abseil2024.ll:271` |
| `_ZTVN10__cxxabiv1` | C++ ABI runtime vtable | `@_ZTVN10__cxxabiv120__si_class_type_infoE` | `corpus/red_team_test/v018_cpp_ffi.ll:35` |
| `_ZGV` | Guard variable for thread-safe statics | (seen in libc++ headers) | Itanium ABI spec |

#### 1.2.5 Template Instantiation Patterns

Templates produce long mangled names with `I...E` parameter encoding:

```
@_ZNSt3__111make_uniqueB8ne210108IiJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10unique_ptrIS2_NS_14default_deleteIS2_EEEEDpOT0_
```

Demangled: `std::__1::enable_if<...>::type std::__1::make_unique<int, int>(int&&)`

The `B8ne210108` suffix is a Clang ABI tag (callee encoding for `__attribute__((abi_tag))`).

Source: `corpus/red_team_test/v018_cpp_ffi.ll:137`

### 1.3 MSVC Name Mangling (Reference)

MSVC uses the `?` prefix. This is primarily relevant on Windows targets. OmniScope should detect `?`-prefixed symbols as MSVC-mangled C++.

| Prefix | Meaning |
|--------|---------|
| `?` | MSVC mangled name start |
| `?0` | Constructor |
| `?1` | Destructor |

### 1.4 `extern "C"` Linkage

Functions declared with `extern "C"` suppress C++ name mangling and appear with plain C names:

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `extern "C"` function | `@c_free`, `@c_take_ptr`, `@c_malloc` | `corpus/red_team_test/v018_cpp_ffi.ll:53,66,87` |
| `extern "C"` callback registration | `@c_register_callback(ptr %cb, ptr %ctx)` | `corpus/red_team_test/v018_cpp_ffi.ll:75` |

**Detection rule**: In a C++ compilation unit (source_filename ends in `.cpp`/`.cc`), functions with plain C names (no `_Z` prefix) that are NOT `main` or compiler builtins are likely `extern "C"`.

---

## 2. FFI Patterns

### 2.1 Linkage Specifiers

| Attribute | IR Representation | Example | Source Evidence |
|-----------|-------------------|---------|-----------------|
| `extern "C"` | No mangling, plain name | `@c_free(ptr noundef %p)` | `corpus/red_team_test/v018_cpp_ffi.ll:53` |
| `__attribute__((visibility("default")))` | `default` visibility | (standard export) | Clang CodeGen |
| `__attribute__((visibility("hidden")))` | `hidden` visibility | `linkonce_odr hidden` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `__attribute__((weak))` | `weak` linkage | `weak_odr` | `corpus/real_world/other/abseil2024.ll:431` |
| `__attribute__((alias(...)))` | `@alias = alias ...` | (alias definition) | LLVM IR Reference |

### 2.2 Linkage Types in C++ IR

| Linkage Type | Meaning | Example | Source Evidence |
|-------------|---------|---------|-----------------|
| `external` | External definition | `declare i32 @__gxx_personality_v0(...)` | `corpus/real_world/other/abseil2024.ll:1534` |
| `linkonce_odr` | Link-once ODR (inline/template) | `define linkonce_odr void @_ZN4absl4Cord6Append...` | `corpus/real_world/other/abseil2024.ll:787` |
| `weak_odr` | Weak ODR (explicit instantiation) | `define weak_odr noundef ptr @_ZN4absl4CordC1...` | `corpus/real_world/other/abseil2024.ll:733` |
| `internal` | File-local (static) | `define internal noundef ptr @_ZN4abslL17CordRepFromStringE...` | `corpus/real_world/other/abseil2024.ll:570` |
| `private` | Private (strictly internal) | `@.str = private unnamed_addr constant ...` | `corpus/real_world/other/abseil2024.ll:189` |

**Detection rule**: `linkonce_odr` and `weak_odr` functions are typically template instantiations or inline methods. `internal` and `private` are file-scoped. `external` is the default for declarations.

### 2.3 FFI Boundary Markers

| Marker | Pattern | Detection Rule |
|--------|---------|----------------|
| C function called from C++ | Plain name in C++ TU | `@free`, `@malloc`, `@sqlite3_open` called from `.cpp` file |
| C++ function called from C | `extern "C"` wrapper | Function with `_Z` prefix is called through plain-name wrapper |
| Cross-language call | Mismatched mangling | `_ZN...` function calls plain C function or vice versa |

---

## 3. Memory Management

### 3.1 C Allocation Functions

| IR Symbol | Signature | Source Evidence |
|-----------|-----------|-----------------|
| `@malloc` | `(i64) -> ptr` | `corpus/ffi-dense/sqlite_binding.ll:111`, `corpus/ffi-dense/zlib_binding.ll:118` |
| `@calloc` | `(i64, i64) -> ptr` | Standard C library |
| `@realloc` | `(ptr, i64) -> ptr` | Standard C library |
| `@free` | `(ptr) -> void` | `corpus/ffi-dense/sqlite_binding.ll:119`, `corpus/ffi-dense/zlib_binding.ll:120` |
| `@aligned_alloc` | `(i64, i64) -> ptr` | C11 standard |

**Detection rule**: `@malloc` and `@free` are the primary C allocation/deallocation pair. A `free` on memory from a different allocator is a cross-language memory bug.

### 3.2 C++ Allocation Operators

| IR Symbol | Mangled Name | Signature | Source Evidence |
|-----------|-------------|-----------|-----------------|
| `operator new(unsigned long)` | `@_Znwm` | `(i64) -> ptr` | `corpus/red_team_test/v018_cpp_ffi.ll:375` |
| `operator delete(void*)` | `@_ZdlPv` | `(ptr) -> void` | (implicit, called through destructor) |
| `operator delete(void*, unsigned long)` | `@_ZdlPvm` | `(ptr, i64) -> void` | `corpus/red_team_test/v018_cpp_ffi.ll:646` |
| `operator new(unsigned long, std::align_val_t)` | `@_ZnwmSt11align_val_t` | `(i64, i64) -> ptr` | `corpus/red_team_test/v018_cpp_ffi.ll:1487` |
| `operator delete(void*, unsigned long, std::align_val_t)` | `@_ZdlPvmSt11align_val_t` | `(ptr, i64, i64) -> void` | `corpus/red_team_test/v018_cpp_ffi.ll:2678` |
| `operator new[](unsigned long)` | `@_Znam` | `(i64) -> ptr` | Itanium ABI spec |
| `operator delete[](void*)` | `@_ZdaPv` | `(ptr) -> void` | Itanium ABI spec |

**Detection rule**: Functions starting with `_Znw` are `operator new` variants. Functions starting with `_Zdl` are `operator delete` variants. Mixing C `malloc`/`free` with C++ `operator new`/`operator delete` is a memory safety bug.

### 3.3 Heap Allocation Attributes

Clang annotates allocation calls with special attributes:

```llvm
%call = call noalias noundef nonnull ptr @_Znwm(i64 noundef 4) #15, !heapallocsite !16
```

| Attribute | Meaning | Source Evidence |
|-----------|---------|-----------------|
| `noalias` | Return value does not alias any existing pointer | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `nonnull` | Return value is never null | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `!heapallocsite` | Debug metadata pointing to the allocation site | `corpus/red_team_test/v018_cpp_ffi.ll:144` |
| `allocsize(0)` | Size is the first argument | `corpus/ffi-dense/sqlite_binding.ll:110` |

### 3.4 Stack Allocation

| IR Symbol | Meaning | Source Evidence |
|-----------|---------|-----------------|
| `alloca <type>` | Stack allocation | Every function in corpus (e.g., `corpus/ffi-dense/sqlite_binding.ll:20-23`) |
| `@llvm.stacksave` | Save stack pointer | LLVM intrinsic |
| `@llvm.stackrestore` | Restore stack pointer | LLVM intrinsic |

### 3.5 Cross-Language Memory Safety Patterns

| Bug Pattern | Description | Source Evidence |
|-------------|-------------|-----------------|
| C `malloc` + C++ `delete` | Using `operator delete` on `malloc`-allocated memory | `corpus/red_team_test/v018_cpp_ffi.ll:186` (`bug_cpp_02_c_malloc_to_cpp_delete`) |
| C++ `new` + C `free` | Using `free` on `operator new`-allocated memory | `corpus/red_team_test/v018_cpp_ffi.ll:101` (`bug_cpp_01_unique_ptr_to_c_free`) |
| `unique_ptr` with C allocator | `unique_ptr` constructed from `malloc` result, destructor calls `delete` | `corpus/red_team_test/v018_cpp_ffi.ll:186-196` |

---

## 4. Exception Handling

### 4.1 Personality Functions

| Personality Function | Language | Example | Source Evidence |
|---------------------|----------|---------|-----------------|
| `@__gxx_personality_v0` | C++ | `personality ptr @__gxx_personality_v0` | `corpus/real_world/other/abseil2024.ll:1534` |
| `@__gcc_personality_v0` | C (with cleanup) | `personality ptr @__gcc_personality_v0` | GCC runtime |
| `@__gxx_personality_v0` | libc++ (same as GCC) | (same as above) | Clang default |

**Detection rule**: A function with `personality ptr @__gxx_personality_v0` is a C++ function that may throw or catch exceptions.

### 4.2 Invoke / Landing Pad Pattern

The `invoke` instruction replaces `call` when the callee may throw:

```llvm
; From abseil2024.ll:633-670
%call11 = invoke noundef ptr @_ZN4absl13cord_internal14NewExternalRep...(
    [2 x i64] %9, ptr noundef nonnull align 8 dereferenceable(24) %ref.tmp)
        to label %invoke.cont unwind label %lpad, !dbg !10475

invoke.cont:                          ; Normal continuation
  ...

lpad:                                 ; Landing pad (exception handler)
  %13 = landingpad { ptr, i32 }
          cleanup, !dbg !10476        ; Cleanup action (e.g., destructor)
  ...

eh.resume:                            ; Resume exception propagation
  resume { ptr, i32 } %lpad.val17
```

Source: `corpus/real_world/other/abseil2024.ll:633-670`

### 4.3 Landing Pad Clauses

| Clause | Meaning | Example | Source Evidence |
|--------|---------|---------|-----------------|
| `cleanup` | Always runs (RAII destructors) | `landingpad { ptr, i32 } cleanup` | `corpus/red_team_test/v018_cpp_ffi.ll:119-120` |
| `catch ptr @_ZTI...` | Catches specific type | `landingpad ... catch ptr @_ZTISt12out_of_range` | `corpus/real_world/other/abseil2024.ll:397` |
| `filter` | Exception specification filter | (rare in modern C++) | LLVM IR Reference |

### 4.4 Exception Handling Functions

| IR Symbol | Purpose | Source Evidence |
|-----------|---------|-----------------|
| `@__cxa_throw` | Throw an exception | C++ ABI |
| `@__cxa_begin_catch` | Begin catch block | C++ ABI |
| `@__cxa_end_catch` | End catch block | C++ ABI |
| `@__cxa_rethrow` | Rethrow current exception | C++ ABI |
| `@_Unwind_Resume` | Resume unwinding | Itanium EH ABI |
| `@__cxa_allocate_exception` | Allocate exception object | C++ ABI |
| `@__cxa_free_exception` | Free exception object | C++ ABI |

### 4.5 RAII Cleanup Pattern

C++ destructors are called in landing pads for RAII cleanup:

```llvm
; From v018_cpp_ffi.ll:118-133
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

Source: `corpus/red_team_test/v018_cpp_ffi.ll:118-133`

---

## 5. VTable / RTTI

### 5.1 VTable Layout

VTables are emitted as unnamed_addr constant globals. The layout follows the Itanium ABI:

| Slot | Content | Notes |
|------|---------|-------|
| -2 | Offset to top | `i64` offset from derived to virtual base |
| -1 | Pointer to RTTI (`_ZTI`) | Points to typeinfo object |
| 0 | First virtual function | Usually `virtual void f()` or destructor |
| 1 | Second virtual function | etc. |

```llvm
; From v018_cpp_ffi.ll:33
@_ZTV7Derived = linkonce_odr unnamed_addr constant { [5 x ptr] } {
  [5 x ptr] [
    ptr null,                    ; offset to top (always 0 for primary vtable)
    ptr @_ZTI7Derived,           ; pointer to RTTI
    ptr @_ZN7Derived1fEv,        ; virtual function f()
    ptr @_ZN7DerivedD1Ev,        ; complete destructor
    ptr @_ZN7DerivedD0Ev         ; deleting destructor
  ]
}, align 8
```

Source: `corpus/red_team_test/v018_cpp_ffi.ll:33`

### 5.2 VTable with Multiple Inheritance

For classes with multiple bases, the vtable contains adjustor thunks:

```llvm
; From v018_cpp_ffi.ll:45 (shared_ptr_emplace has 7 slots)
@_ZTVNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE = linkonce_odr unnamed_addr constant { [7 x ptr] } {
  [7 x ptr] [
    ptr null,                    ; offset to top
    ptr @_ZTINSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE,  ; RTTI
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEED1Ev,  ; complete dtor
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEED0Ev,  ; deleting dtor
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEE16__on_zero_sharedEv,      ; virtual __on_zero_shared
    ptr @_ZNKSt3__119__shared_weak_count13__get_deleterERKSt9type_info,  ; virtual __get_deleter
    ptr @_ZNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEE21__on_zero_shared_weakEv  ; virtual __on_zero_shared_weak
  ]
}, align 8
```

Source: `corpus/red_team_test/v018_cpp_ffi.ll:45`

### 5.3 RTTI Object Structure

The RTTI (`_ZTI`) object contains:

| Field | Content | Example |
|-------|---------|---------|
| 0 | Pointer to `__cxxabiv1` type info class | `@_ZTVN10__cxxabiv120__si_class_type_infoE` |
| 1 | Pointer to typeinfo name (`_ZTS`) | `@_ZTS7Derived` (with high-bit flag) |
| 2 (optional) | Pointer to base class RTTI | `@_ZTI4Base` (for single inheritance) |

```llvm
; Simple class RTTI (single inheritance)
@_ZTI7Derived = linkonce_odr hidden constant { ptr, ptr, ptr } {
  ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv120__si_class_type_infoE, i64 2),
  ptr inttoptr (i64 add (i64 ptrtoint (ptr @_ZTS7Derived to i64), i64 -9223372036854775808) to ptr),
  ptr @_ZTI4Base
}, align 8

; Base class RTTI (no base)
@_ZTI4Base = linkonce_odr hidden constant { ptr, ptr } {
  ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv117__class_type_infoE, i64 2),
  ptr inttoptr (i64 add (i64 ptrtoint (ptr @_ZTS4Base to i64), i64 -9223372036854775808) to ptr)
}, align 8
```

Source: `corpus/red_team_test/v018_cpp_ffi.ll:34,37`

### 5.4 RTTI Name Strings

Typeinfo name strings (`_ZTS`) contain the bare class name:

| Symbol | String Content | Meaning |
|--------|---------------|---------|
| `@_ZTS7Derived` | `c"7Derived\00"` | Class `Derived` |
| `@_ZTS4Base` | `c"4Base\00"` | Class `Base` |
| `@_ZTSNSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE` | `c"NSt3__120__shared_ptr_emplaceIiNS_9allocatorIiEEEE\00"` | Template class |

Source: `corpus/red_team_test/v018_cpp_ffi.ll:36,39,47`

### 5.5 VTT (Virtual Table Table)

For classes with virtual inheritance, a VTT is emitted:

```llvm
@_ZTTNSt3__119basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE = external unnamed_addr constant [4 x ptr], align 8
```

The VTT is an array of pointers to vtable entries used during construction and destruction.

Source: `corpus/real_world/other/abseil2024.ll:271`

### 5.6 `__cxxabiv1` Type Info Classes

| Symbol | C++ Type | Used For |
|--------|----------|----------|
| `@_ZTVN10__cxxabiv117__class_type_infoE` | `__cxxabiv1::__class_type_info` | Classes with no base |
| `@_ZTVN10__cxxabiv120__si_class_type_infoE` | `__cxxabiv1::__si_class_type_info` | Single inheritance |
| `@_ZTVN10__cxxabiv121__vmi_class_type_infoE` | `__cxxabiv1::__vmi_class_type_info` | Multiple/virtual inheritance |

Source: `corpus/red_team_test/v018_cpp_ffi.ll:35,38`

---

## 6. Compiler Builtins to LLVM Intrinsics

### 6.1 Memory Intrinsics

| C/C++ Builtin | LLVM IR Intrinsic | Example | Source Evidence |
|---------------|-------------------|---------|-----------------|
| `__builtin_memcpy` / `memcpy` | `@llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)` | `call void @llvm.memcpy.p0.p0.i64(ptr align 8 %agg.tmp, ptr align 8 %src, i64 16, i1 false)` | `corpus/real_world/other/abseil2024.ll:628` |
| `__builtin_memset` / `memset` | `@llvm.memset.p0.i64(ptr, i8, i64, i1)` | `call void @llvm.memset.p0.i64(ptr align 8 %agg.result, i8 0, i64 16, i1 false)` | `corpus/real_world/other/abseil2024.ll:3871` |
| `__builtin_objectsize` | `@llvm.objectsize.i64.p0(ptr, i1, i1, i1)` | `%12 = call i64 @llvm.objectsize.i64.p0(ptr %11, i1 false, i1 true, i1 false)` | `corpus/ffi-dense/sqlite_binding.ll:98` |

### 6.2 Arithmetic Intrinsics

| C/C++ Builtin | LLVM IR Intrinsic | Notes |
|---------------|-------------------|-------|
| `__builtin_expect` | `@llvm.expect.i64(i64, i64)` | Branch prediction hint |
| `__builtin_ctz` | `@llvm.cttz.i32(i32, i1)` | Count trailing zeros |
| `__builtin_clz` | `@llvm.ctlz.i32(i32, i1)` | Count leading zeros |
| `__builtin_popcount` | `@llvm.ctpop.i32(i32)` | Population count |
| `__builtin_bswap` | `@llvm.bswap.i32(i32)` | Byte swap |
| `__builtin_add_overflow` | `@llvm.sadd.with.overflow.i32(i32, i32)` | Overflow-checked add |
| `__builtin_mul_overflow` | `@llvm.smul.with.overflow.i32(i32, i32)` | Overflow-checked multiply |

### 6.3 Math Intrinsics

| C/C++ Builtin | LLVM IR Intrinsic |
|---------------|-------------------|
| `__builtin_sqrt` | `@llvm.sqrt.f64(double)` |
| `__builtin_sin` | `@llvm.sin.f64(double)` |
| `__builtin_cos` | `@llvm.cos.f64(double)` |
| `__builtin_fma` | `@llvm.fma.f64(double, double, double)` |
| `__builtin_fabs` | `@llvm.fabs.f64(double)` |
| `__builtin_copysign` | `@llvm.copysign.f64(double, double)` |
| `__builtin_floor` | `@llvm.floor.f64(double)` |
| `__builtin_ceil` | `@llvm.ceil.f64(double)` |
| `__builtin_round` | `@llvm.round.f64(double)` |

### 6.4 Control Flow Intrinsics

| C/C++ Builtin | LLVM IR | Example |
|---------------|---------|---------|
| `__builtin_unreachable` | `unreachable` | LLVM terminator instruction |
| `__builtin_trap` | `@llvm.trap()` | Halts execution |
| `__builtin_debugtrap` | `@llvm.debugtrap()` | Debug breakpoint |

### 6.5 Variable Arguments

| C/C++ Construct | LLVM IR | Source Evidence |
|-----------------|---------|-----------------|
| `va_start` | `@llvm.va_start.p0(ptr %ap)` | `corpus/real_world/other/sqlite3.ll:9609` |
| `va_end` | `@llvm.va_end.p0(ptr %ap)` | `corpus/real_world/other/sqlite3.ll:9614` |
| `va_copy` | `@llvm.va_copy(ptr %dst, ptr %src)` | LLVM IR Reference |

---

## 7. IR Attributes from Clang (UB Exploitation)

Clang attaches attributes to IR values that encode language-level guarantees. These are critical for static analysis as they represent assumptions the compiler makes.

### 7.1 Parameter/Return Attributes

| Attribute | Meaning | Example | Source Evidence |
|-----------|---------|---------|-----------------|
| `noundef` | Value is never `undef` or `poison` | `ptr noundef %0` | `corpus/ffi-dense/sqlite_binding.ll:19` |
| `nonnull` | Pointer is never null | `ptr noundef nonnull align 8 dereferenceable(16) %this` | `corpus/real_world/other/abseil2024.ll:1335` |
| `dereferenceable(N)` | At least N bytes are dereferenceable | `ptr noundef nonnull align 8 dereferenceable(16)` | `corpus/real_world/other/abseil2024.ll:1335` |
| `align N` | Pointer has alignment N | `ptr align 8 %agg.tmp` | `corpus/real_world/other/abseil2024.ll:628` |
| `returned` | Value is returned as-is | `ptr noundef nonnull returned align 8 dereferenceable(16) %this` | `corpus/red_team_test/v018_cpp_ffi.ll:175` |
| `sret(%type)` | Struct return (hidden pointer parameter) | `ptr dead_on_unwind writable sret(%"class.std::__1::unique_ptr") align 8 %agg.result` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `noalias` | No aliasing (TBAA) | `ptr dead_on_unwind noalias writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `writable` | Memory pointed to is written | `ptr dead_on_unwind writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |
| `dead_on_unwind` | Value is dead if unwinding | `ptr dead_on_unwind writable sret(...)` | `corpus/red_team_test/v018_cpp_ffi.ll:137` |

### 7.2 Function Attributes

| Attribute | Meaning | Example | Source Evidence |
|-----------|---------|---------|-----------------|
| `nounwind` | Function does not throw | `#1 = { nounwind }` | `corpus/ffi-dense/sqlite_binding.ll:63` |
| `noreturn` | Function does not return | (e.g., `abort`, `exit`) | LLVM IR Reference |
| `readnone` | Function does not read memory | (pure function) | LLVM IR Reference |
| `readonly` | Function only reads memory | (const function) | LLVM IR Reference |
| `mustprogress` | Function must make forward progress | `mustprogress noinline optnone ssp uwtable(sync)` | `corpus/red_team_test/v018_cpp_ffi.ll:52` |
| `willreturn` | Function will eventually return | (non-looping) | LLVM IR Reference |
| `nosync` | Function does not synchronize | (no atomics/fences) | LLVM IR Reference |
| `nofree` | Function does not free memory | (no deallocation) | LLVM IR Reference |
| `speculatable` | Function can be speculated | (safe to execute speculatively) | `corpus/ffi-dense/sqlite_binding.ll:116` |
| `nocallback` | Function does not call back into caller | (no callbacks) | `corpus/ffi-dense/sqlite_binding.ll:116` |
| `allocsize(0)` | Allocation size is first argument | `allocsize(0)` on `@malloc` | `corpus/ffi-dense/sqlite_binding.ll:110` |
| `optnone` | No optimization | `noinline nounwind optnone ssp uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |
| `ssp` | Stack smashing protection | `ssp uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |
| `uwtable(sync)` | Unwinding table (synchronous) | `uwtable(sync)` | `corpus/ffi-dense/sqlite_binding.ll:18` |

### 7.3 Attribute Groups

Attributes are often grouped and referenced by number:

```llvm
attributes #0 = { mustprogress noinline optnone ssp uwtable(sync) }
attributes #1 = { nounwind }
attributes #2 = { allocsize(0) }
attributes #3 = { nounwind willreturn memory(none) }
```

Source: `corpus/ffi-dense/sqlite_binding.ll` (attribute groups referenced throughout)

---

## 8. C++ Language Features in IR

### 8.1 Constructor/Destructor Calling Convention

Constructors receive `this` as the first parameter and return `this`:

```llvm
; Complete constructor (C1)
define linkonce_odr noundef ptr @_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEEC1B8ne210108ILb1EvEEPi(
    ptr noundef nonnull returned align 8 dereferenceable(8) %this,
    ptr noundef %__p) unnamed_addr #2
```

Destructors also receive `this` and may return `this`:

```llvm
; Complete destructor (D1)
define linkonce_odr hidden noundef ptr @_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED1B8ne210108Ev(
    ptr noundef nonnull returned align 8 dereferenceable(8) %this) unnamed_addr #2
```

Source: `corpus/red_team_test/v018_cpp_ffi.ll:175,201`

### 8.2 Adjustor Thunks

For multiple inheritance, the compiler generates thunks that adjust the `this` pointer:

```llvm
; Thunk for Derived::f() when called through Base* interface
define linkonce_odr void @_ZThn8_N7Derived1fEv(ptr noundef %this) {
  %this.addr = getelementptr inbounds i8, ptr %this, i64 -8  ; adjust this
  call void @_ZN7Derived1fEv(ptr %this.addr)
  ret void
}
```

The `_ZTh` prefix indicates an adjustor thunk. The `n8` means "subtract 8 from this".

### 8.3 Guard Variables for Thread-Safe Statics

Local static variables use guard variables to ensure one-time initialization:

```llvm
; Guard variable pattern
@_ZGVZ3fooEvE1x = internal global i8 0, align 1  ; guard variable

define void @_Z3fooEv() {
entry:
  %0 = load i8, ptr @_ZGVZ3fooEvE1x, align 1
  %guard.has.init = icmp eq i8 %0, 0
  br i1 %guard.has.init, label %init.check, label %init.end

init.check:
  %guard.is.valid = call i1 @__cxa_guard_acquire(ptr @_ZGVZ3fooEvE1x)
  br i1 %guard.is.valid, label %init, label %init.end

init:
  ; ... initialize static ...
  call void @__cxa_guard_release(ptr @_ZGVZ3fooEvE1x)
  br label %init.end

init.end:
  ; ... use static ...
}
```

The `_ZGV` prefix marks guard variables. `@__cxa_guard_acquire` and `@__cxa_guard_release` manage the initialization.

### 8.4 `this` Pointer Parameter

C++ member functions receive `this` as an implicit first parameter:

```llvm
; Member function: absl::Cord::InlineRep::AppendTreeToTree(...)
define void @_ZN4absl4Cord9InlineRep16AppendTreeToTreeEPNS_13cord_internal7CordRepENS2_18CordzUpdateTracker16MethodIdentifierE(
    ptr noundef nonnull align 8 dereferenceable(16) %this,  ; implicit this
    ptr noundef %tree,                                        ; explicit param 1
    i32 noundef %method)                                      ; explicit param 2
```

Source: `corpus/real_world/other/abseil2024.ll:1335`

### 8.5 Struct Return (sret)

Large return values use a hidden pointer parameter:

```llvm
define linkonce_odr hidden void @_ZNSt3__111make_uniqueB8ne210108IiJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10unique_ptrIS2_NS_14default_deleteIS2_EEEEDpOT0_(
    ptr dead_on_unwind noalias writable sret(%"class.std::__1::unique_ptr") align 8 %agg.result,
    ptr noundef nonnull align 4 dereferenceable(4) %__args)
```

The `sret(%type)` attribute indicates a hidden struct return parameter.

Source: `corpus/red_team_test/v018_cpp_ffi.ll:137`

### 8.6 ABI Tags

Clang emits ABI tags (e.g., `B8ne210108`) for functions with `__attribute__((abi_tag(...)))`:

```
_ZNSt3__110unique_ptrIiNS_14default_deleteIiEEED1B8ne210108Ev
                                                      ^^^^^^^^
                                                      ABI tag
```

This is common in libc++ for ABI versioning.

Source: `corpus/red_team_test/v018_cpp_ffi.ll:175`

---

## 9. Key Takeaways for Static Analysis

### 9.1 What to Analyze (User Code)

| Category | Detection Rule | Examples |
|----------|---------------|----------|
| C functions | No `_Z` prefix, not a known builtin | `@sqlite3_open`, `@my_function` |
| C++ user functions | `_Z` prefix + user namespace (not `std::__1`, `__cxxabiv1`) | `@_ZN4absl4Cord...` |
| `extern "C"` functions | Plain name in C++ TU | `@c_free`, `@c_malloc` |
| User-defined classes | VTable/RTTI with user namespace | `@_ZTV7Derived`, `@_ZTI7Derived` |

### 9.2 What to Filter (Compiler-Generated / Standard Library)

| Category | Detection Rule | Examples |
|----------|---------------|----------|
| C++ ABI runtime | `_ZTVN10__cxxabiv1*`, `_ZTIN10__cxxabiv1*` | `@_ZTVN10__cxxabiv120__si_class_type_infoE` |
| Standard library | `NSt3__1` (libc++), `St` (libstdc++) | `@_ZNSt3__110unique_ptr...`, `@_ZNSt3__16vector...` |
| Exception handling | `@__gxx_personality_v0`, `@__cxa_*`, `@_Unwind_*` | All EH infrastructure |
| Operator new/delete | `_Znwm*`, `_Zdl*`, `_Znam*`, `_Zda*` | `@_Znwm`, `@_ZdlPvm` |
| LLVM intrinsics | `@llvm.*` | `@llvm.memcpy.*`, `@llvm.expect.*` |
| Guard variables | `_ZGV` prefix | `@_ZGVZ3fooEvE1x` |
| Type info runtime | `_ZTISt*`, `_ZTVSt*` (std exceptions) | `@_ZTISt12out_of_range`, `@_ZTVSt12length_error` |
| Thunks | `_ZTh*`, `_ZTv*` | `@_ZThn8_N7Derived1fEv` |

### 9.3 Memory Safety Patterns to Detect

| Pattern | Severity | Detection |
|---------|----------|-----------|
| `malloc` + `delete` | High | `@malloc` result flows to `@_ZdlPv*` call |
| `new` + `free` | High | `@_Znwm*` result flows to `@free` call |
| `new` + `delete[]` | High | `@_Znwm` result flows to `@_ZdaPv` call |
| `new[]` + `delete` | High | `@_Znam` result flows to `@_ZdlPv` call |
| Use-after-free | High | `@free`/`@_ZdlPv*` result used after call |
| Double free | High | Same pointer passed to `@free`/`@_ZdlPv*` twice |
| Missing destructor | Medium | `invoke` without matching `cleanup` landing pad |

### 9.4 FFI Boundary Markers

| Marker | Detection Rule | Action |
|--------|---------------|--------|
| Cross-language call | C function called from C++ TU (or vice versa) | Flag as FFI boundary |
| `extern "C"` wrapper | Plain name wrapping mangled name | Track data flow across boundary |
| Callback registration | Function pointer passed across language boundary | Analyze callback safety |
| Shared library export | `default` visibility + `external` linkage | Mark as external interface |

### 9.5 IR Attribute-Based Analysis

| Attribute | Analysis Implication |
|-----------|---------------------|
| `noundef` | Compiler assumes no undef; passing undef is UB |
| `nonnull` | Compiler assumes non-null; passing null is UB |
| `dereferenceable(N)` | Must point to at least N bytes |
| `noalias` | No aliasing assumed; violating is UB |
| `nounwind` | Cannot throw; calling throwing function is UB |
| `noreturn` | Must not return; returning is UB |
| `mustprogress` | Must make progress; infinite loop is UB |

---

## Appendix A: Mangled Name Quick Reference

### Demangling Tool

```bash
# macOS
echo "_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE" | c++filt

# LLVM tool
llvm-cxxfilt "_ZN4absl4Cord6AppendENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE"
```

### Common Mangled Prefixes

| Prefix | Demangled | Category |
|--------|-----------|----------|
| `_Z3` | `foo` (3-char name) | Free function |
| `_ZN` | `namespace::` | Namespaced entity |
| `_ZNK` | `const` method | Const member function |
| `_ZNS` | `std::` | Standard library |
| `_ZTV` | vtable | Virtual table |
| `_ZTI` | typeinfo | RTTI object |
| `_ZTS` | typeinfo name | RTTI name string |
| `_ZTT` | VTT | Virtual table table |
| `_ZTh` | thunk (adjustor) | Multiple inheritance thunk |
| `_ZTv` | thunk (virtual) | Virtual call thunk |
| `_Znw` | `operator new` | Allocation |
| `_Zdl` | `operator delete` | Deallocation |
| `_Zna` | `operator new[]` | Array allocation |
| `_Zda` | `operator delete[]` | Array deallocation |
| `_ZGV` | guard variable | Thread-safe static init |

---

## Appendix B: Type Encoding in Mangling

| Encoding | Type |
|----------|------|
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
| `P` | pointer (`*`) |
| `R` | reference (`&`) |
| `O` | rvalue reference (`&&`) |
| `S` | substitution (back-reference) |
| `I...E` | template parameters |
| `N...E` | nested name |
| `K` | `const` |
| `V` | `volatile` |
