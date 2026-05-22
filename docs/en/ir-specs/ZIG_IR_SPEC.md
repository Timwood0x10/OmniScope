# Zig LLVM IR Specification: Compiler-Reserved vs User-Defined

**Source**: `~/code/zigcode/zig/src/` (dev branch)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming Rules

### 1.1 User-Defined Symbols

Zig's LLVM backend generates symbol names based on the **fully-qualified name (FQN)** of each navigation (Nav). The FQN is constructed by walking the namespace hierarchy.

| Pattern | Example IR Symbol | Source Evidence |
|---------|-------------------|-----------------|
| Internal function (default) | `module.funcName` | `src/codegen/llvm.zig:2709` — `nav.fqn` used for non-extern |
| Internal global variable | `module.varName` | `src/codegen/llvm.zig:3016` — `nav.fqn` for internal linkage |
| Exported function (`@export`) | `myFunc` (user-chosen name) | `src/codegen/llvm.zig:1690` — `first_export.opts.name` |
| Exported variable | `myGlobal` (user-chosen name) | `src/codegen/llvm.zig:1654` — renamed to export name |
| Anonymous function (`__anon_N`) | `module.parentFn__anon_3` | `src/InternPool.zig:9815-9820` — comptime-generated names |

**Key naming distinction** (`src/codegen/llvm.zig:2703-2709`):
- **Extern symbols** use `nav.name` (unqualified name)
- **Internal symbols** use `nav.fqn` (fully-qualified name including namespace path)

```
// Internal: uses FQN → "mymodule.myfunction"
// Extern:   uses name → "write" (just the unqualified name)
```

### 1.2 Compiler-Reserved Symbols

| Prefix/Pattern | Example | Source Evidence |
|----------------|---------|-----------------|
| `__zig_lt_errors_len` | error set length comparison | `src/codegen/llvm.zig:12925` — constant function name |
| `__zig_probe_stack` | stack probe function | `src/codegen/llvm.zig:1229` — `probe-stack` attribute value |
| `__zig_tag_name_<Type>` | enum tag name lookup | `src/codegen/llvm.zig:4476` — `"__zig_tag_name_{f}"` format |
| `__zig_is_named_enum_value_<Type>` | named enum value check | `src/codegen/llvm.zig:10409` — `"__zig_is_named_enum_value_{f}"` format |
| `__zig_err_name_table` | error name table global | `src/codegen/llvm.zig:11266` — error name table variable |
| `__sancov_gen_.<N>` | sanitizer coverage counters | `src/codegen/llvm.zig:1483` — fuzzing coverage |
| `__float<int><float>i<f>` | int-to-float compiler-rt call | `src/codegen/llvm.zig:6676` — e.g. `__floatuntisf` |
| `__fix<sign><float>f<int>i` | float-to-int compiler-rt call | `src/codegen/llvm.zig:6747` — e.g. `__fixsfsi` |
| `__<op><float>f2` | float comparison compiler-rt | `src/codegen/llvm.zig:8769` — e.g. `__gesf2` |
| `__trunc<f1>f<f2>f2` | float truncation | `src/codegen/llvm.zig:9361` — e.g. `__truncdfhf2` |
| `__extend<f1>f<f2>f2` | float extension | `src/codegen/llvm.zig:9396` — e.g. `__extendhfsf2` |
| `__add<f>f3` | soft-float add | `src/codegen/llvm.zig:10840` — vector reduce fallback |
| `__mul<f>f3` | soft-float multiply | `src/codegen/llvm.zig:10843` — vector reduce fallback |

### 1.3 Name Mangling Conventions

Zig does **not** use traditional C++-style name mangling. Instead:

1. **FQN construction** (`src/InternPool.zig:9815-9820`): Anonymous functions get `__anon_N` suffix appended to their parent function's FQN.
2. **Extern names are preserved verbatim**: When a symbol is declared `extern`, the unqualified name is used as-is (`src/codegen/llvm.zig:2709`).
3. **`@export` renames**: The exported symbol name replaces the FQN entirely (`src/codegen/llvm.zig:1690-1706`).
4. **Multiple exports create aliases**: The first export name becomes the primary name; subsequent exports become LLVM aliases (`src/codegen/llvm.zig:1734`).

### 1.4 Export and Extern Builtins

**`@export` builtin** (`src/Zcu.zig:691-709`):
```zig
// @export(&myFunc, .{ .name = "exported_name", .linkage = .strong, .visibility = .default });
```
- Options: `name` (NullTerminatedString), `linkage` (strong/weak/link_once), `section`, `visibility` (default/hidden/protected)
- Used extensively in `lib/std/start.zig:37-95` for entry point symbols (`main`, `_start`, `wWinMainCRTStartup`, etc.)

**`@extern` builtin** (`src/InternPool.zig:2258-2283`):
```zig
// @extern(*anyopaque, .{ .name = "foo" })  →  external global i8
// extern "c" fn write(...)  →  lib_name = "c"
```
- The Extern key stores: `name`, `ty`, `lib_name`, `linkage`, `visibility`, `is_threadlocal`, `is_dll_import`, `relocation`, `is_const`, `alignment`, `addrspace`
- Source enum: `builtin` vs `syntax` (`src/InternPool.zig:5998`)

---

## 2. Compiler Builtins / Intrinsics

### 2.1 LLVM Intrinsics Used by Zig

These are LLVM intrinsics that Zig's codegen emits directly via `callIntrinsic`. Source: `lib/std/zig/llvm/Builder.zig:2612-2784` and `src/codegen/llvm.zig`.

#### Arithmetic with Overflow (Safety Checks)

| Zig AIR Op | LLVM Intrinsic | Source Evidence |
|-----------|----------------|-----------------|
| `.add_safe` | `@llvm.sadd.with.overflow.*` / `@llvm.uadd.with.overflow.*` | `src/codegen/llvm.zig:4879` |
| `.sub_safe` | `@llvm.ssub.with.overflow.*` / `@llvm.usub.with.overflow.*` | `src/codegen/llvm.zig:4880` |
| `.mul_safe` | `@llvm.smul.with.overflow.*` / `@llvm.umul.with.overflow.*` | `src/codegen/llvm.zig:4881` |
| `.add_with_overflow` | `@llvm.sadd.with.overflow.*` / `@llvm.uadd.with.overflow.*` | `src/codegen/llvm.zig:4907` |
| `.sub_with_overflow` | `@llvm.ssub.with.overflow.*` / `@llvm.usub.with.overflow.*` | `src/codegen/llvm.zig:4908` |
| `.mul_with_overflow` | `@llvm.smul.with.overflow.*` / `@llvm.umul.with.overflow.*` | `src/codegen/llvm.zig:4909` |
| `.shl_with_overflow` | custom overflow check | `src/codegen/llvm.zig:4910` |

#### Saturation Arithmetic

| Zig AIR Op | LLVM Intrinsic | Source Evidence |
|-----------|----------------|-----------------|
| `.add_sat` (signed) | `@llvm.sadd.sat.*` | `src/codegen/llvm.zig:8328` |
| `.add_sat` (unsigned) | `@llvm.uadd.sat.*` | `src/codegen/llvm.zig:8328` |
| `.shl_sat` (signed) | `@llvm.sshl.sat.*` | `Builder.zig:2691` |
| `.shl_sat` (unsigned) | `@llvm.ushl.sat.*` | `Builder.zig:2692` |

#### Bit Manipulation

| Zig AIR Op | LLVM Intrinsic | Source Evidence |
|-----------|----------------|-----------------|
| `.clz` | `@llvm.ctlz.*` | `src/codegen/llvm.zig:10270` |
| `.ctz` | `@llvm.cttz.*` | `src/codegen/llvm.zig:10270` |
| `.popcount` | `@llvm.ctpop.*` | `src/codegen/llvm.zig:10289` |
| `.byte_swap` | `@llvm.bswap.*` | `src/codegen/llvm.zig:10339` |
| `.bit_reverse` | `@llvm.bitreverse.*` | `src/codegen/llvm.zig:10289` |

#### Math Builtins (Floating-Point)

| Zig AIR Op | LLVM Intrinsic | Source Evidence |
|-----------|----------------|-----------------|
| `.sqrt` | `@llvm.sqrt.*` | `src/codegen/llvm.zig:8905` |
| `.sin` | `@llvm.sin.*` | `src/codegen/llvm.zig:8904` |
| `.cos` | `@llvm.cos.*` | `src/codegen/llvm.zig:8894` |
| `.exp` | `@llvm.exp.*` | `src/codegen/llvm.zig:8896` |
| `.exp2` | `@llvm.exp2.*` | `src/codegen/llvm.zig:8897` |
| `.log` | `@llvm.log.*` | `src/codegen/llvm.zig:8900` |
| `.log2` | `@llvm.log2.*` | `src/codegen/llvm.zig:8902` |
| `.log10` | `@llvm.log10.*` | `src/codegen/llvm.zig:8901` |
| `.floor` | `@llvm.floor.*` | `src/codegen/llvm.zig:8899` |
| `.ceil` | `@llvm.ceil.*` | `src/codegen/llvm.zig:8893` |
| `.round` | `@llvm.round.*` | `src/codegen/llvm.zig:8903` |
| `.trunc` | `@llvm.trunc.*` | `src/codegen/llvm.zig:8906` |
| `.fma` | `@llvm.fma.*` | `src/codegen/llvm.zig:8907` |
| `.fabs` | `@llvm.fabs.*` | `src/codegen/llvm.zig:8898` |
| `.fmax` | `@llvm.maxnum.*` | `src/codegen/llvm.zig:8892` |
| `.fmin` | `@llvm.minnum.*` | `src/codegen/llvm.zig:8892` |

**Note**: When `disable_intrinsics` is true (compiler-rt functions, `no_builtin` module option), math operations fall back to libc/compiler-rt calls instead of LLVM intrinsics (`src/codegen/llvm.zig:8854`).

#### Memory Operations

| Zig AIR Op | LLVM Intrinsic / Instruction | Source Evidence |
|-----------|-------------------------------|-----------------|
| `.memset` | `@llvm.memset.*` (via `callMemSet`) | `src/codegen/llvm.zig:10009-10066` |
| `.memcpy` | `@llvm.memcpy.*` (via `callMemCpy`) | `src/codegen/llvm.zig:10147-10174` |
| `.memmove` | `@llvm.memmove.*` (via `callMemMove`) | `src/codegen/llvm.zig:10176-10200` |

#### Control Flow / Debug

| Zig Builtin | LLVM Intrinsic | Source Evidence |
|-------------|----------------|-----------------|
| `@trap` | `@llvm.trap` | `src/codegen/llvm.zig:9777` |
| `@breakpoint` | `@llvm.debugtrap` | `src/codegen/llvm.zig:9783` |
| `@returnAddress()` | `@llvm.returnaddress` | `src/codegen/llvm.zig:9796` |
| `@frameAddress()` | `@llvm.frameaddress` | `src/codegen/llvm.zig:9804` |
| `@vaStart` | `@llvm.va_start` | `src/codegen/llvm.zig:5753` |
| `@vaEnd` | `@llvm.va_end` | `src/codegen/llvm.zig:5739` |
| `@vaCopy` | `@llvm.va_copy` | `src/codegen/llvm.zig:5728` |
| branch hints | `@llvm.assume` (cold) | `src/codegen/llvm.zig:9282,9302` |

#### Vector Operations

| Zig AIR Op | LLVM Intrinsic | Source Evidence |
|-----------|----------------|-----------------|
| `@splat` | `insertelement` chain | `src/codegen/llvm.zig:10893-10899` |
| Vector reduce (add/and/or/etc.) | `@llvm.vector.reduce.*` | `src/codegen/llvm.zig:9272,9282` |
| `@shuffle` | `shufflevector` | LLVM instruction |

#### WebAssembly-Specific

| Zig Builtin | LLVM Intrinsic | Source Evidence |
|-------------|----------------|-----------------|
| `@wasmMemorySize` | `@llvm.wasm.memory.size` | `src/codegen/llvm.zig:8144` |
| `@wasmMemoryGrow` | `@llvm.wasm.memory.grow` | `src/codegen/llvm.zig:8155` |

---

## 3. FFI Patterns (extern "C" / @extern)

### 3.1 extern Function Declarations

Zig's FFI mechanism uses `extern "c"` (or other library names) on function declarations.

**How extern functions appear in LLVM IR** (`src/codegen/llvm.zig:2703-2732`):
- **Name**: Uses `nav.name` (unqualified, verbatim) rather than `nav.fqn`
- **Linkage**: External (not internal) — no `.internal` linkage is set
- **No `unnamed_addr`**: Unlike internal functions, extern functions do not get `unnamed_addr`

```zig
// Zig source:
extern "c" fn write(fd: i32, buf: [*]const u8, count: usize) usize;

// LLVM IR:
declare i64 @write(i32, ptr, i64)
```

### 3.2 @extern Builtin for Global Symbols

```zig
// Zig source:
const stderr = @extern(*FILE, .{ .name = "stderr" });

// LLVM IR:
@stderr = external global ptr
```

Source: `src/codegen/llvm.zig:3007` — extern globals get `strong`/`weak` linkage, not `internal`.

### 3.3 Library Name and Linking

The `lib_name` field in `Extern` (`src/InternPool.zig:2264-2267`) controls library association:
- `extern "c" fn ...` → `lib_name = "c"` (links against libc)
- `extern "mylib" fn ...` → `lib_name = "mylib"` (links against custom library)
- For Wasm targets, `lib_name` becomes `wasm-import-module` attribute (`src/codegen/llvm.zig:2727-2730`)

### 3.4 C ABI Conventions

Zig respects C ABI for extern functions. The calling convention is resolved through `toLlvmCallConv` (`src/codegen/llvm.zig:11875-11983`):
- Functions with `extern "c"` get the platform's C calling convention (`.ccc` in LLVM)
- The `cCallingConvention()` function returns the default C CC for the target (`src/codegen/llvm.zig:11900`)

### 3.5 DLL Import/Export

Extern functions can be marked as DLL imports (`src/codegen/llvm.zig:3041`):
- `is_dll_import` → `.dllimport` storage class
- Exported functions can get `.dllexport` (`src/codegen/llvm.zig:1711`)

---

## 4. Memory / Allocator Patterns

### 4.1 Zig Allocator Interface

Zig's allocator is a **type-erased interface** defined in `lib/std/mem/Allocator.zig:1-80`:

```zig
pub const Allocator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        alloc: *const fn (*anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8,
        resize: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool,
        remap: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8,
        free: *const fn (*anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void,
    };
};
```

**In LLVM IR**, allocator calls appear as **indirect calls through vtable function pointers**, not as direct calls to named runtime functions. This is fundamentally different from Go/TinyGo.

### 4.2 Standard Library Allocators

| Allocator | Source File | Description |
|-----------|------------|-------------|
| `PageAllocator` | `lib/std/heap/PageAllocator.zig` | OS page-level allocation (mmap/VirtualAlloc) |
| `FixedBufferAllocator` | `lib/std/heap/FixedBufferAllocator.zig` | Stack/fixed buffer allocation |
| `ArenaAllocator` | `lib/std/heap/arena_allocator.zig` | Bump allocator with bulk free |
| `GeneralPurposeAllocator` | `lib/std/heap/GeneralPurposeAllocator.zig` | Debug-safe general allocator |
| `SmpAllocator` | `lib/std/heap/SmpAllocator.zig` | Scalable multi-producer allocator |
| `ThreadSafeAllocator` | `lib/std/heap/ThreadSafeAllocator.zig` | Mutex-wrapped allocator |
| `WasmAllocator` | `lib/std/heap/WasmAllocator.zig` | WASM-specific allocator |
| `sbrk_allocator` | `lib/std/heap/sbrk_allocator.zig` | sbrk-based allocator (freestanding) |
| `memory_pool` | `lib/std/heap/memory_pool.zig` | Fixed-size object pool |

### 4.3 LLVM IR Characteristics

- **No `malloc`/`free` calls**: Zig does not use libc `malloc`/`free` by default. Allocation goes through the Zig allocator interface.
- **Platform calls**: `PageAllocator` calls OS primitives directly (e.g., `mmap`, `NtAllocateVirtualMemory`) which appear as extern C calls.
- **Comptime allocators**: Comptime-evaluated code uses `@import("std").heap` allocators at compile time — these do not appear in the final IR.

---

## 5. Runtime Functions / Safety Checks

### 5.1 Panic Functions

Zig's panic functions are defined in `lib/std/debug.zig` and referenced via `BuiltinDecl` in `src/Zcu.zig:438-464`. The compiler generates calls to these via `buildSimplePanic` (`src/codegen/llvm.zig:5541-5563`).

#### Simple Panics (Direct Compiler-Generated Calls)

These are the `SimplePanicId` enum values (`src/Zcu.zig:599-645`):

| SimplePanicId | BuiltinDecl Path | Panic Function | Source Evidence |
|--------------|-------------------|----------------|-----------------|
| `.reached_unreachable` | `panic.reachedUnreachable` | `reachedUnreachable()` | `Zcu.zig:623` |
| `.unwrap_null` | `panic.unwrapNull` | `unwrapNull()` | `Zcu.zig:624` |
| `.cast_to_null` | `panic.castToNull` | `castToNull()` | `Zcu.zig:625` |
| `.incorrect_alignment` | `panic.incorrectAlignment` | `incorrectAlignment()` | `Zcu.zig:626` |
| `.invalid_error_code` | `panic.invalidErrorCode` | `invalidErrorCode()` | `Zcu.zig:627` |
| `.integer_out_of_bounds` | `panic.integerOutOfBounds` | `integerOutOfBounds()` | `Zcu.zig:628` |
| `.integer_overflow` | `panic.integerOverflow` | `integerOverflow()` | `Zcu.zig:629` |
| `.shl_overflow` | `panic.shlOverflow` | `shlOverflow()` | `Zcu.zig:630` |
| `.shr_overflow` | `panic.shrOverflow` | `shrOverflow()` | `Zcu.zig:631` |
| `.divide_by_zero` | `panic.divideByZero` | `divideByZero()` | `Zcu.zig:632` |
| `.exact_division_remainder` | `panic.exactDivisionRemainder` | `exactDivisionRemainder()` | `Zcu.zig:633` |
| `.integer_part_out_of_bounds` | `panic.integerPartOutOfBounds` | `integerPartOutOfBounds()` | `Zcu.zig:634` |
| `.corrupt_switch` | `panic.corruptSwitch` | `corruptSwitch()` | `Zcu.zig:635` |
| `.shift_rhs_too_big` | `panic.shiftRhsTooBig` | `shiftRhsTooBig()` | `Zcu.zig:636` |
| `.invalid_enum_value` | `panic.invalidEnumValue` | `invalidEnumValue()` | `Zcu.zig:637` |
| `.for_len_mismatch` | `panic.forLenMismatch` | `forLenMismatch()` | `Zcu.zig:638` |
| `.copy_len_mismatch` | `panic.copyLenMismatch` | `copyLenMismatch()` | `Zcu.zig:639` |
| `.memcpy_alias` | `panic.memcpyAlias` | `memcpyAlias()` | `Zcu.zig:640` |
| `.noreturn_returned` | `panic.noreturnReturned` | `noreturnReturned()` | `Zcu.zig:641` |

#### Parameterized Panics (Sema-Generated Calls)

These are also in `BuiltinDecl` (`src/Zcu.zig:439-446`) but take parameters:

| BuiltinDecl Path | Signature | Source |
|-------------------|-----------|--------|
| `panic.call` | `(msg: []const u8, ra: ?usize) noreturn` | `Zcu.zig:439`, `debug.zig:33` |
| `panic.sentinelMismatch` | `(expected, found) noreturn` | `Zcu.zig:440`, `debug.zig:34` |
| `panic.unwrapError` | `(err: anyerror) noreturn` | `Zcu.zig:441`, `debug.zig:40` |
| `panic.outOfBounds` | `(index: usize, len: usize) noreturn` | `Zcu.zig:442`, `debug.zig:44` |
| `panic.startGreaterThanEnd` | `(start: usize, end: usize) noreturn` | `Zcu.zig:443`, `debug.zig:48` |
| `panic.inactiveUnionField` | `(active, accessed) noreturn` | `Zcu.zig:444`, `debug.zig:52` |
| `panic.sliceCastLenRemainder` | `(src_len: usize) noreturn` | `Zcu.zig:445`, `debug.zig:58` |

### 5.2 Safety Check IR Patterns

Safety checks are generated when `safety` is true (Debug/ReleaseSafe mode):

1. **Integer overflow** (`src/codegen/llvm.zig:8260-8304`):
   - Uses `@llvm.sadd.with.overflow` / `@llvm.uadd.with.overflow` etc.
   - Checks overflow bit, branches to `OverflowFail` block
   - `OverflowFail` block calls `buildSimplePanic(.integer_overflow)`

2. **Integer cast bounds** (`src/codegen/llvm.zig:9224-9304`):
   - Checks min/max bounds with `icmp`
   - Branches to `IntMinFail`/`IntMaxFail` blocks
   - Calls `buildSimplePanic(.integer_out_of_bounds)` or `.invalid_enum_value`

3. **Null unwrap** — `is_non_null` check followed by panic branch
4. **Error unwrap** — `is_err` check followed by panic branch
5. **Bounds checking** — `icmp` against slice/array length, followed by `panic.outOfBounds`

### 5.3 Stack Protection

| Feature | Attribute | Source Evidence |
|---------|-----------|-----------------|
| Stack protector | `sspstrong` + `stack-protector-buffer-size` | `src/codegen/llvm.zig:1217-1223` |
| Stack probing | `probe-stack = "__zig_probe_stack"` | `src/codegen/llvm.zig:1226-1230` |
| No builtins (compiler-rt) | `no-builtins` attribute | `src/codegen/llvm.zig:1209-1212` |

---

## 6. Transform / Optimization Passes

### 6.1 AIR to LLVM IR Lowering

Zig uses its own intermediate representation called **AIR** (Abstract IR) defined in `src/Air.zig`. The LLVM backend in `src/codegen/llvm.zig` lowers AIR instructions to LLVM IR.

**Key AIR instructions and their LLVM IR lowering** (`src/codegen/llvm.zig:4868-5102`):

| AIR Instruction | LLVM IR Pattern | Line |
|----------------|-----------------|------|
| `.add` / `.sub` / `.mul` | `add nsw`/`nuw`, `fadd`/`fsub`/`fmul` | 8257, 8344, 8384 |
| `.add_safe` / `.sub_safe` / `.mul_safe` | overflow intrinsics + branch + panic | 4879-4881 |
| `.div_float` | `fdiv` or `@llvm.*` intrinsic | 4883 |
| `.alloc` | `alloca` | 4963 |
| `.load` | `load` | 4979 |
| `.store` | `store` | 5005 |
| `.memset` / `.memcpy` / `.memmove` | `@llvm.memset.*` / `@llvm.memcpy.*` / `@llvm.memmove.*` | 5001-5004 |
| `.slice` | `{ptr, len}` aggregate | 8237-8245 |
| `.trap` | `@llvm.trap` + `unreachable` | 9775-9778 |
| `.breakpoint` | `@llvm.debugtrap` | 9781-9784 |
| `.ret` | `ret` | 5565-5615 |
| `.call` | `call` with CC handling | 5237-5490 |
| `.try` / `.try_ptr` | error union unwrap + branch | 4970-4973 |

### 6.2 Comptime Effects on IR

- **Comptime-evaluated values** are folded into constants in the IR — no runtime code generated
- **Generic function instantiations**: Each concrete instantiation of a generic function gets its own LLVM function with a unique FQN (`src/InternPool.zig:9815-9820`)
- **Comptime `@export`**: Exports generated at comptime are processed through `updateExports` (`src/codegen/llvm.zig:1592-1638`)
- **No comptime code in runtime**: Comptime allocator calls, string operations, etc. are fully resolved before IR generation

### 6.3 Debug vs Release IR Differences

| Feature | Debug | ReleaseSafe | ReleaseFast/ReleaseSmall |
|---------|-------|-------------|--------------------------|
| Safety checks | Yes | Yes | No |
| `no-builtins` attribute | No | No | Depends on `no_builtin` |
| Stack protector | Configurable | Configurable | Configurable |
| Frame pointer | Configurable | Configurable | Typically omitted |
| Debug info | Full | Partial | Typically stripped |
| `@branchHint` | Honored | Honored | Honored |
| Intrinsics | Allowed | Allowed | Allowed (fast math variants) |
| `disable_intrinsics` | Per-function | Per-function | Per-function |

**`disable_intrinsics`** (`src/codegen/llvm.zig:1202-1213`): When true (compiler-rt functions, `no_builtin` module option), the function gets `no-builtins` attribute and uses libc calls instead of LLVM intrinsics. This prevents infinite recursion when compiling functions like `memcpy`.

---

## 7. ABI Differences

### 7.1 Exported vs Internal Functions

| Property | Exported Function | Internal Function |
|----------|-------------------|-------------------|
| LLVM name | Export name (user-chosen) | FQN (e.g., `module.func`) |
| Linkage | `external` / `weak_odr` / `linkonce_odr` | `internal` |
| `unnamed_addr` | `.default` (not unnamed) | `.unnamed_addr` |
| Visibility | `.default` / `.hidden` / `.protected` | `.default` |
| Source | `src/codegen/llvm.zig:1709-1722` | `src/codegen/llvm.zig:2718-2719` |

### 7.2 Calling Conventions

The full calling convention mapping is in `src/codegen/llvm.zig:11899-11983`:

| Zig CC | LLVM CC | Notes |
|--------|---------|-------|
| `.auto` | `fastcc` | Default for Zig functions |
| `.naked` | `ccc` + `naked` attribute | No prologue/epilogue |
| `extern "c"` | `ccc` | C calling convention |
| `.x86_64_sysv` | `x86_64_sysvcc` | System V AMD64 ABI |
| `.x86_64_win` | `win64cc` | Windows x64 ABI |
| `.x86_stdcall` | `x86_stdcallcc` | Windows stdcall |
| `.x86_fastcall` | `x86_fastcallcc` | Windows fastcall |
| `.x86_thiscall` | `x86_thiscallcc` | Windows thiscall |
| `.x86_vectorcall` | `x86_vectorcallcc` | Vector call |
| `.arm_aapcs` | `arm_aapcscc` | ARM AAPCS |
| `.arm_aapcs_vfp` | `arm_aapcs_vfpcc` | ARM AAPCS with VFP |
| `.aarch64_vfabi` | `aarch64_vector_pcs` | AArch64 vector calling convention |
| `.riscv64_lp64_v` | `riscv_vectorcallcc` | RISC-V vector |
| `.avr_signal` | `avr_signalcc` | AVR signal handler |
| `.avr_interrupt` | `avr_intrcc` | AVR interrupt handler |
| `.m68k_interrupt` | `m68k_intrcc` | M68K interrupt handler |
| `.amdgcn_kernel` | `amdgpu_kernel` | AMD GPU kernel |
| `.nvptx_kernel` | `ptx_kernel` | NVIDIA PTX kernel |

### 7.3 Parameter Passing

**SRet (Struct Return)** (`src/codegen/llvm.zig:2736-2744`):
- Large return values are passed via an invisible first parameter (sret pointer)
- Sret parameter gets `nonnull`, `noalias`, `sret` attributes

**ByRef parameter passing** (`src/codegen/llvm.zig:4419-4431`):
- Large parameters may be passed by reference with `nonnull`, `readonly`, `align` attributes
- Optional `byval` attribute for true by-value semantics

**Pointer attributes** (`src/codegen/llvm.zig:4382-4416`):
- `noalias` — from `fn_info.noalias_bits`
- `nonnull` — for non-optional, non-allowzero pointers
- `readonly` — for `const` pointer parameters
- `align` — from pointer alignment or child type alignment

**Integer promotion** (`src/codegen/llvm.zig:4413-4416`):
- `signext` for signed integers smaller than register size
- `zeroext` for unsigned integers smaller than register size

### 7.4 Error Return Tracing

When `any_error_tracing` is enabled (`src/codegen/llvm.zig:2747-2752`):
- An extra `nonnull` parameter is appended for the error return trace
- Only applies to functions with `.auto` calling convention (not extern "c")

---

## 8. Key Takeaways for Static Analysis

### What's User Code (Analyze These)

- Functions with internal FQN patterns (e.g., `module.submodule.function`)
- Functions with `@export` names (user-chosen, appears as-is in IR)
- Functions with multiple exports (primary name + aliases)
- Error union types and their unwrap patterns (`.try`, `.try_ptr`)
- Slice operations (`.slice`, `.slice_elem_val`, `.slice_elem_ptr`)

### What's Compiler Runtime (Filter/Skip These)

- `__zig_lt_errors_len` — error set comparison helper
- `__zig_probe_stack` — stack probing function
- `__zig_tag_name_*` — enum tag name lookup
- `__zig_is_named_enum_value_*` — enum value check
- `__zig_err_name_table` — error name table
- `__sancov_gen_.*` — sanitizer coverage
- `__float*`, `__fix*`, `__*f2`, `__trunc*f*f2`, `__extend*f*f2` — compiler-rt soft-float functions
- LLVM intrinsics (`@llvm.*`)

### What's FFI Boundary (Classify Separately)

- Functions with external linkage (no `internal` linkage set)
- Functions with `wasm-import-name` / `wasm-import-module` attributes
- Functions with `.dllimport` storage class
- Functions named after C library functions (`write`, `read`, `mmap`, etc.)

### What Indicates Memory Safety Concerns

- Overflow check patterns (overflow intrinsic + branch + panic)
- Bounds check patterns (`icmp` + branch + `panic.outOfBounds`)
- Null check patterns (`icmp eq ptr null` + branch + `panic.unwrapNull`)
- Error unwrap patterns (`is_err` check + branch)
- `@memcpy` arguments alias check (`panic.memcpyAlias`)
- Sentinel mismatch checks
- Union field access checks (`panic.inactiveUnionField`)

### Allocator Detection Strategy

Since Zig allocators are vtable-based indirect calls:
1. Look for indirect calls through function pointer tables
2. `PageAllocator` calls will appear as calls to OS primitives (`mmap`, `NtAllocateVirtualMemory`, `sbrk`)
3. No standard `malloc`/`free` symbol names unless explicitly using C allocator
4. Comptime allocations are invisible in IR

---

## 9. Complete LLVM Intrinsic Reference

Source: `lib/std/zig/llvm/Builder.zig:2612-2784`

### Variable Argument Handling
- `@llvm.va_start`, `@llvm.va_end`, `@llvm.va_copy`

### Code Generator
- `@llvm.returnaddress`, `@llvm.addressofreturnaddress`, `@llvm.sponentry`
- `@llvm.frameaddress`, `@llvm.prefetch`, `@llvm.thread.pointer`

### Standard C/C++ Library
- `@llvm.abs`, `@llvm.smax`, `@llvm.smin`, `@llvm.umax`, `@llvm.umin`
- `@llvm.memcpy`, `@llvm.memcpy.inline`, `@llvm.memmove`, `@llvm.memset`, `@llvm.memset.inline`
- `@llvm.sqrt`, `@llvm.powi`, `@llvm.sin`, `@llvm.cos`, `@llvm.pow`
- `@llvm.exp`, `@llvm.exp10`, `@llvm.exp2`, `@llvm.ldexp`, `@llvm.frexp`
- `@llvm.log`, `@llvm.log10`, `@llvm.log2`, `@llvm.fma`, `@llvm.fabs`
- `@llvm.minnum`, `@llvm.maxnum`, `@llvm.minimum`, `@llvm.maximum`, `@llvm.copysign`
- `@llvm.floor`, `@llvm.ceil`, `@llvm.trunc`, `@llvm.rint`, `@llvm.nearbyint`
- `@llvm.round`, `@llvm.roundeven`, `@llvm.lround`, `@llvm.llround`, `@llvm.lrint`, `@llvm.llrint`

### Bit Manipulation
- `@llvm.bitreverse`, `@llvm.bswap`, `@llvm.ctpop`, `@llvm.ctlz`, `@llvm.cttz`
- `@llvm.fshl`, `@llvm.fshr`

### Arithmetic with Overflow
- `@llvm.sadd.with.overflow`, `@llvm.uadd.with.overflow`
- `@llvm.ssub.with.overflow`, `@llvm.usub.with.overflow`
- `@llvm.smul.with.overflow`, `@llvm.umul.with.overflow`

### Saturation Arithmetic
- `@llvm.sadd.sat`, `@llvm.uadd.sat`, `@llvm.ssub.sat`, `@llvm.usub.sat`
- `@llvm.sshl.sat`, `@llvm.ushl.sat`

### Vector Reduction
- `@llvm.vector.reduce.add`, `@llvm.vector.reduce.fadd`
- `@llvm.vector.reduce.mul`, `@llvm.vector.reduce.fmul`
- `@llvm.vector.reduce.and`, `@llvm.vector.reduce.or`, `@llvm.vector.reduce.xor`
- `@llvm.vector.reduce.smax`, `@llvm.vector.reduce.smin`
- `@llvm.vector.reduce.umax`, `@llvm.vector.reduce.umin`
- `@llvm.vector.reduce.fmax`, `@llvm.vector.reduce.fmin`
- `@llvm.vector.reduce.fmaximum`, `@llvm.vector.reduce.fminimum`
- `@llvm.vector.insert`, `@llvm.vector.extract`

### General
- `@llvm.trap`, `@llvm.debugtrap`, `@llvm.ubsantrap`
- `@llvm.stackprotector`, `@llvm.stackguard`
- `@llvm.objectsize`, `@llvm.expect`, `@llvm.expect.with.probability`
- `@llvm.assume`, `@llvm.ssa.copy`
- `@llvm.is.fpclass`, `@llvm.ptrmask`
- `@llvm.vscale`, `@llvm.donothing`

### Platform-Specific
- AMDGPU: `@llvm.amdgcn.workitem.id.*`, `@llvm.amdgcn.workgroup.id.*`, `@llvm.amdgcn.dispatch.ptr`
- NVPTX: `@llvm.nvvm.read.ptx.sreg.*`
- WebAssembly: `@llvm.wasm.memory.size`, `@llvm.wasm.memory.grow`
