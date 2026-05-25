# Compiler IR Patterns for Static Analysis

> Based on actual LLVM IR output from Rust, C++, Go (cgo), Java (JNI), Python (CPython API), Swift, and Zig compilers. All patterns verified against real IR files.

## Table of Contents

- [Rust](#rust)
- [C++](#c-1)
- [Go (cgo)](#go-cgo)
- [Java (JNI)](#java-jni)
- [Python (CPython API)](#python-cpython-api)
- [Swift](#swift)
- [Zig](#zig)

---

## Rust

Source: `rust_merkle.ll` (real wasmtime library, 4654 functions), `rust_hash.ll`, `rust_ffi_bugs.ll`

### Allocator Functions (NOT malloc/free)

Rust does **not** use `malloc`/`free`. It uses its own allocator runtime.

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `__rust_alloc` | `declare ptr @__rust_alloc(i64 %size, i64 %align)` | Primary allocation function |
| `__rust_dealloc` | `declare void @__rust_dealloc(ptr %ptr, i64 %size, i64 %align)` | Deallocation — requires size + alignment |
| `__rust_realloc` | `declare ptr @__rust_realloc(ptr, i64, i64, i64)` | Reallocation |
| `__rust_alloc_zeroed` | `declare ptr @__rust_alloc_zeroed(i64, i64)` | Zero-initialized allocation |

**Impact on analysis**: A tool looking for `malloc`/`free` pairs will miss all Rust allocations.

### Box / Raw Pointer Conversions

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `Box::into_raw` | `call ptr @_ZN3std3box8into_rawE(ptr)` | Converts Box to raw pointer, ownership transfers to caller |
| `Box::from_raw` | `call ptr @_ZN3std3box8from_rawE(ptr)` | Reclaims ownership from raw pointer |
| `_ZN3std3string10into_rawEv` | `call ptr @_ZN3std3string10into_rawEv(ptr)` | String::into_raw, leaks if not reclaimed |

### Exception Handling

Rust uses `invoke`/`landingpad` for cleanup (panic unwinding), NOT for try/catch.

```llvm
%result = invoke i64 %func(...) to label %ok unwind label %cleanup

cleanup:
  %lp = landingpad { ptr, i32 } cleanup
  ; ... cleanup code (drop, dealloc) ...
  resume { ptr, i32 } %lp
```

**Impact**: Landing pads are cleanup chains, not error handlers. The tool must track allocations through cleanup paths.

### Struct Decomposition (SROA)

Rust's SROA pass decomposes structs into individual fields:

```llvm
; Vec<u8> becomes {i64, ptr, i64} → three separate values
%vec.sroa.0 = load i64, ptr %vec      ; len
%vec.sroa.2 = load ptr, ptr %vec      ; data pointer
%vec.sroa.3 = load i64, ptr %vec      ; capacity
```

**Impact**: Allocation tracking must follow field-level values, not just struct-level.

### Metadata

| Metadata | Meaning |
|----------|---------|
| `!noalias` | Pointer does not alias with any other in scope |
| `!alias.scope` | Defines aliasing scope boundaries |
| `!invariant.load` | Load value never changes (vtable pointers) |
| `llvm.lifetime.start/end` | Object lifetime boundaries (stack allocations) |
| `nonnull` parameter attr | Pointer guaranteed non-null |
| `dereferenceable(N)` | At least N bytes readable from pointer |

### Memory Safety Annotations

Rust inserts runtime checks in debug builds:

```llvm
; Bounds check
%inbounds = icmp ult i64 %index, %len
br i1 %inbounds, label %ok, label %panic

panic:
  call void @_ZN4core9panicking18panic_bounds_check(...)
```

### Drop Glue (Destructor Calls)

Rust generates `_ZN...4drop...` functions for types with Drop trait:

```llvm
call fastcc void @"_ZN4core3ptr42drop_in_place$LT$alloc..vec..Vec$LT$u8$GT$$GT$"(...)
```

These are the equivalent of C++ destructors. A "missing deinit" bug means the drop glue is never called.

---

## C++

Source: `red_team_cpp_ffi.ll`, `cpp_hash.ll`, `cpp_fft.ll`

### Allocation Functions

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `_Znam` (operator new[]) | `declare ptr @_Znam(i64)` | Array new |
| `_Znwm` (operator new) | `declare ptr @_Znwm(i64)` | Scalar new |
| `_ZdlPvm` (operator delete) | `declare void @_ZdlPvm(ptr, i64)` | Sized delete |
| `_ZdaPv` (operator delete[]) | `declare void @_ZdaPv(ptr)` | Array delete |
| `malloc` / `free` | Standard C allocation | Also present in C++ code |

**Key**: `new[]` paired with `delete` (not `delete[]`) is a mismatch bug.

### Exception Handling

C++ uses `invoke`/`landingpad` with `@__gxx_personality_v0`:

```llvm
%result = invoke ptr @_ZN7DerivedC1Ev(ptr %obj) to label %ok unwind label %lpad

lpad:
  %lp = landingpad { ptr, i32 }
    catch ptr @_ZTISt9bad_alloc    ; type info for catch
    cleanup                        ; destructor cleanup
  ; ...
  invoke void @__cxa_throw(...)
```

**Impact**: Must track allocations across exception paths. Cleanup handlers may free resources.

### Smart Pointers

C++ smart pointers generate complex IR with reference counting:

| Smart Pointer | Destructor Pattern | Notes |
|--------------|-------------------|-------|
| `unique_ptr` | `_ZNSt3__110unique_ptr...D1Ev` | Simple wrapper, calls deleter |
| `shared_ptr` | `_ZNSt3__119__shared_weak_count...` | Reference counted, control block |
| `weak_ptr` | `_ZNSt3__113__weak_count...` | Weak reference to shared_ptr |

### RTTI and VTables

| Pattern | IR | Notes |
|---------|-----|-------|
| Type info | `@_ZTI...` | `external constant ptr` |
| VTable | `@_ZTV...` | Array of function pointers |
| Type name | `@_ZTS...` | String literal for type name |

### Virtual Destructor

```llvm
; vtable entry for virtual destructor
%vtable = load ptr, ptr %obj
%dtor = getelementptr ptr, ptr %vtable, i64 0
call void %dtor(ptr %obj)
```

Missing virtual destructor = derived class destructor never called.

---

## Go (cgo)

Source: `go_cgo_bugs.ll`. Go itself uses its own SSA (not LLVM IR), but cgo generates C-compatible IR.

### Allocation Functions

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `_cgo_allocate` | `declare ptr @_cgo_allocate(i32)` | Go-side allocation via cgo |
| `_cgo_free` | `declare void @_cgo_free(ptr)` | Go-side deallocation |
| `_Cfunc_GoMalloc` | `declare ptr @_Cfunc_GoMalloc(i32)` | C wrapper for Go malloc |
| `_Cfunc_GoFree` | `declare void @_Cfunc_GoFree(ptr)` | C wrapper for Go free |

**Key**: `free()` on `_cgo_allocate`'d memory, or `_cgo_free` on `malloc`'d memory = cross-language free mismatch.

### Go-Specific Types

```llvm
%struct.GoSlice = type { ptr, i32, i32 }   ; {data, len, cap}
%struct.GoString = type { ptr, i32 }        ; {data, len}
```

### Concurrency

Go goroutines are not visible in LLVM IR. Shared state uses `volatile`:

```llvm
@g_shared_counter = internal global i32 0, align 4
; Reads/writes use `load volatile` / `store volatile` (not always emitted)
```

### cgo Calling Convention

cgo-generated functions use standard C calling convention. The `_cgo_` prefix identifies Go runtime functions. `_Cfunc_` prefix identifies C functions called from Go.

---

## Java (JNI)

Source: `java_jni_bugs.ll`. JNI is a C API called from Java — the IR is standard C with JNI naming conventions.

### JNIEnv Functions

All JNI calls take `ptr %env` (JNIEnv*) as first argument.

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `NewGlobalRef` | `call ptr @NewGlobalRef(ptr %env, ptr %obj)` | Creates global reference |
| `DeleteGlobalRef` | `call void @DeleteGlobalRef(ptr %env, ptr %ref)` | Releases global reference |
| `NewStringUTF` | `call ptr @NewStringUTF(ptr %env, ptr %str)` | Creates Java string |
| `GetStringUTFChars` | `call ptr @GetStringUTFChars(ptr %env, ptr %jstr)` | Pins string in native memory |
| `ReleaseStringUTFChars` | `call void @ReleaseStringUTFChars(ptr %env, ptr %jstr, ptr %chars)` | Unpins string |
| `GetByteArrayElements` | `call ptr @GetByteArrayElements(ptr %env, ptr %arr)` | Pins byte array |
| `ReleaseByteArrayElements` | `call void @ReleaseByteArrayElements(ptr %env, ptr %arr, ptr %elems)` | Unpins array |
| `GetPrimitiveArrayCritical` | `call ptr @GetPrimitiveArrayCritical(ptr %env, ptr %arr)` | Pins with GC blocked |
| `ReleasePrimitiveArrayCritical` | `call void @ReleasePrimitiveArrayCritical(ptr %env, ptr %arr, ptr %carray)` | Unpins |

### Bug Patterns

| Bug | Detection Pattern |
|-----|------------------|
| GlobalRef leak | `NewGlobalRef` without matching `DeleteGlobalRef` |
| String pin leak | `GetStringUTFChars` without `ReleaseStringUTFChars` |
| UAF after release | Use of pinned pointer after `Release*` call |
| Critical section violation | JNI call between `GetPrimitiveArrayCritical` and `Release` |
| Type confusion | Cast between array element types (e.g., `jbyteArray` → `jint*`) |

---

## Python (CPython API)

Source: `python_cffi_bugs.ll`. Python C API is standard C with Python naming conventions.

### Reference Counting

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `Py_INCREF` | `call void @Py_INCREF(ptr %obj)` | Increment refcount |
| `Py_DECREF` | `call void @Py_DECREF(ptr %obj)` | Decrement refcount, may free |

### New vs Borrowed References

| Function | Reference Type | Who Frees |
|----------|---------------|-----------|
| `PyList_GetItem` | **Borrowed** | Python owns, C must NOT DECREF |
| `PyBytes_FromStringAndSize` | **New** | C must DECREF |
| `PyLong_FromLong` | **New** | C must DECREF |
| `PyTuple_New` | **New** | C must DECREF |
| `PyObject_GetAttrString` | **New** | C must DECREF |

### Steal Reference Pattern

`PyTuple_SetItem` **steals** the reference — after calling it, C must NOT use or DECREF the item:

```llvm
call i32 @PyTuple_SetItem(ptr %tuple, i32 0, ptr %val1)
; %val1 is now owned by %tuple — using %val1 after this = UAF
```

### Bug Patterns

| Bug | Detection Pattern |
|-----|------------------|
| Borrowed ref DECREF | `PyList_GetItem` → `Py_DECREF` on same ptr |
| New ref leak | `PyBytes_FromStringAndSize` without `Py_DECREF` |
| UAF after DECREF | Use of ptr after `Py_DECREF` (may free) |
| Steal ref misuse | Use after `PyTuple_SetItem` steals it |
| Cache without INCREF | Store to global without `Py_INCREF` |
| Cross-language free | `free()` on Python-managed memory |

---

## Swift

Source: `swift_ffi_test.ll` (438 lines). Swift uses ARC (Automatic Reference Counting).

### ARC Runtime Functions

| Pattern | IR Signature | Notes |
|---------|-------------|-------|
| `swift_allocObject` | `call ptr @swift_allocObject(ptr %metadata, i64 %size, i64 %align)` | Heap allocation for class instances |
| `swift_deallocClassInstance` | `call void @swift_deallocClassInstance(ptr %obj, i64 %size, i64 %align)` | Deallocation |
| `swift_retain` | `call void @swift_retain(ptr %obj)` | Increment reference count |
| `swift_release` | `call void @swift_release(ptr %obj)` | Decrement reference count, may deallocate |

### Exclusivity Enforcement

Swift enforces exclusive access to memory at runtime:

```llvm
%scratch = alloca [24 x i8]
call void @swift_beginAccess(ptr %addr, ptr %scratch, i64 32, ptr null)  ; begin exclusivity
; ... access memory ...
call void @swift_endAccess(ptr %scratch)                                  ; end exclusivity
```

### Swift Calling Convention

Swift uses `swiftcc` calling convention. Methods pass `swiftself`:

```llvm
define hidden swiftcc i64 @method(ptr swiftself %self) #0 {
```

### Object Layout

```llvm
%T14swift_ffi_test10FFIManagerC = type <{ %swift.refcounted, ... }>
%swift.refcounted = type { ptr, i64 }  ; {isa/metadata, refcount}
```

### Metadata Sections

Swift stores type metadata in Mach-O sections:

| Section | Content |
|---------|---------|
| `__TEXT,__swift5_typeref` | Type references |
| `__TEXT,__swift5_fieldmd` | Field metadata |
| `__TEXT,__swift5_types` | Type records |
| `__DATA,__objc_const` | ObjC-compatible class data |

### Method Dispatch

Virtual method calls go through vtable-like metadata:

```llvm
%vtable = load ptr, ptr %self
%method_ptr = getelementptr ptr, ptr %vtable, i64 12
%method = load ptr, ptr %method_ptr, !invariant.load !{}
call swiftcc i64 %method(ptr swiftself %self)
```

---

## Zig

Source: `zig_ffi_test.ll` (12MB, includes stdlib). Zig compiles to LLVM IR via its self-hosted backend.

### Allocator VTable Pattern

Zig's `std.mem.Allocator` is a fat pointer `{ptr, ptr}` — data pointer + vtable pointer.

```llvm
%mem.Allocator = type { ptr, ptr }
%mem.Allocator.VTable = type { ptr, ptr, ptr, ptr }  ; alloc, resize, remap, free
```

Built-in allocators:

| Allocator | VTable Global | Underlying Mechanism |
|-----------|--------------|---------------------|
| `heap.CAllocator` | `@heap.CAllocator.vtable` | Wraps `posix_memalign` / `free` |
| `heap.PageAllocator` | `@heap.PageAllocator.vtable` | Wraps `mmap` / `munmap` |
| `heap.arena_allocator.ArenaAllocator` | Inline vtable | Bump allocator, batch free on `deinit` |

### CAllocator Internals

```llvm
define internal fastcc ptr @heap.CAllocator.alloc(ptr %self, ptr %buf, i64 %size, i6 %align, i64 %ret_addr) {
  ; calls posix_memalign
  %err = call i32 @posix_memalign(ptr %out, i64 %alignment, i64 %size)
  ...
}

define internal fastcc void @heap.CAllocator.free(ptr %self, ptr %buf, ptr %ptr, i64 %size, i6 %align, i64 %ret_addr) {
  call void @free(ptr %ptr)  ; directly calls C free()
}
```

**Impact**: Zig's `c_allocator` maps directly to C's `malloc`/`free`. Cross-language analysis must recognize `heap.CAllocator.free` → `free()` mapping.

### Zig-Specific IR Patterns

| Pattern | Description |
|---------|-------------|
| `fastcc` calling convention | Used for all internal Zig functions |
| `sret` parameter | Struct return via hidden pointer parameter |
| `debug.assert` | Safety checks inserted in debug builds |
| `@llvm.memset.p0.i64(ptr, i8 -86, ...)` | Debug fill with `0xAA` pattern |
| Dot-separated names | `heap.CAllocator.alloc` instead of C++ mangled names |

### Type Naming Convention

Zig uses dot-separated namespace notation:

```
heap.CAllocator.alloc          → std.heap.CAllocator.alloc
mem.Allocator                  → std.mem.Allocator
debug.panicExtra__anon_2450    → generic instantiation with ID
```

Anon suffixes (`__anon_NNNN`) identify monomorphized generic instances.

### Memory Safety Features

Zig inserts runtime checks in safe builds:

```llvm
; Bounds check before array access
%ok = icmp ult i64 %index, %len
br i1 %ok, label %access, label %panic

panic:
  call fastcc void @debug.panicExtra__anon_NNNN(...)
```

---

## Summary: Cross-Language Detection Implications

| Language | Allocator | Destructor | Exception | FFI Marker |
|----------|-----------|-----------|-----------|------------|
| Rust | `__rust_alloc`/`__rust_dealloc` | Drop glue `_ZN...4drop...` | `invoke`/`landingpad` cleanup | `_R` prefix mangling |
| C++ | `_Znam`/`_Znwm`/`_ZdlPvm` | Destructors `_ZN...D1Ev` | `invoke`/`landingpad` + `__gxx_personality_v0` | `_Z` prefix mangling |
| Go (cgo) | `_cgo_allocate`/`_cgo_free` | N/A (no destructor) | N/A | `_cgo_` / `_Cfunc_` prefix |
| Java (JNI) | N/A (managed by JVM) | `DeleteGlobalRef` | JNI exception check | `JNIenv*` first arg |
| Python | N/A (managed by CPython) | `Py_DECREF` refcount | N/A | `Py_`/`PyObject_` prefix |
| Swift | `swift_allocObject` | `swift_release` ARC | N/A | `swiftcc` calling conv, `$s` mangling |
| Zig | `heap.CAllocator` → `free()` | `deinit` method | `debug.assert` panics | `fastcc` conv, dot names |
