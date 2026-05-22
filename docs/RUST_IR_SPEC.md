# Rust LLVM IR Specification: Compiler-Reserved vs User-Defined

**Source**: `/Users/scc/code/rustcode/rust/compiler/` (master branch)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming Rules

### 1.1 Symbol Mangling Schemes

Rust uses two symbol mangling schemes, selectable via `-C symbol-mangling-version`:

| Scheme | Prefix | Example | Source Evidence |
|--------|--------|---------|-----------------|
| **v0** (default) | `_R` | `_RNvCsiatkNdJK2di_7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:35` -- `let prefix = "_R"` |
| **Legacy** | `_ZN` | `_ZN7mycrate3foo17h0123456789abcdefE` | `rustc_symbol_mangling/src/legacy.rs:195` -- `result.push_str("_ZN")` |

The version is selected in `rustc_symbol_mangling/src/lib.rs:272-316`:

```rust
let mangling_version = match mangling_version_crate {
    LOCAL_CRATE => tcx.sess.opts.get_symbol_mangling_version(),
    ...
};
let symbol = match mangling_version {
    SymbolManglingVersion::Legacy => legacy::mangle(...),
    SymbolManglingVersion::V0 => v0::mangle(...),
    SymbolManglingVersion::Hashed => hashed::mangle(...),
};
```

### 1.2 User-Defined Symbols

| Pattern | Example IR Symbol | Source Evidence |
|---------|-------------------|-----------------|
| Default function (v0) | `_RNvC7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:76` -- `p.print_def_path(def_id, args)` |
| Default function (legacy) | `_ZN7mycrate3foo17h<hash>E` | `rustc_symbol_mangling/src/legacy.rs:111` -- `p.path.finish(hash)` |
| `#[no_mangle]` | `foo` (user-chosen) | `rustc_symbol_mangling/src/lib.rs:231-233` -- `attrs.flags.contains(NO_MANGLE)` |
| `#[export_name = "..."]` | `<user-chosen>` | `rustc_symbol_mangling/src/lib.rs:226-229` -- `attrs.symbol_name` |
| `#[linkage = "external"]` | depends on linkage | `rustc_middle/src/middle/codegen_fn_attrs.rs:88-89` |

### 1.3 Compiler-Reserved Symbols

| Prefix/Pattern | Example | Source Evidence |
|----------------|---------|-----------------|
| `_R` + v0 encoded path | `_RNvC7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:35` |
| `_ZN` + legacy encoded path | `_ZN7mycrate3foo17h<hash>E` | `rustc_symbol_mangling/src/legacy.rs:195-209` |
| `_RC<crate_hash>__rustc` | `#[rustc_std_internal_symbol]` items | `rustc_symbol_mangling/src/v0.rs:106-128` |
| `__rust_alloc` | global allocator (alloc) | `library/alloc/src/alloc.rs:16-17` -- `#[rustc_allocator]` |
| `__rust_dealloc` | global allocator (dealloc) | `library/alloc/src/alloc.rs:20-22` -- `#[rustc_deallocator]` |
| `__rust_realloc` | global allocator (realloc) | `library/alloc/src/alloc.rs:23-28` -- `#[rustc_reallocator]` |
| `__rust_alloc_zeroed` | global allocator (zeroed) | `library/alloc/src/alloc.rs:29-31` -- `#[rustc_allocator_zeroed]` |
| `__rust_no_alloc_shim_is_unstable_v2` | allocator shim guard | `library/alloc/src/alloc.rs:33-35` |
| `__rust_try` | catch_unwind helper | `rustc_codegen_llvm/src/intrinsic.rs:1670` |
| `__rust_panic_type_info` | MSVC panic type info | `rustc_codegen_llvm/src/intrinsic.rs:1341` |
| `rust_eh_personality` | exception handling personality | `rustc_symbol_mangling/src/v0.rs:87` -- hardcoded name |
| `__CxxFrameHandler3` | MSVC SEH personality | `rustc_codegen_llvm/src/context.rs:865` |
| `__gxx_wasm_personality_v0` | WASM EH personality | `rustc_codegen_llvm/src/context.rs:870` |
| `llvm.used` | prevent symbol elimination | `rustc_codegen_llvm/src/base.rs:151` |
| `llvm.compiler.used` | prevent compiler elimination | `rustc_codegen_llvm/src/base.rs:158` |

### 1.4 Shim Symbols in Mangling

Shims are compiler-generated wrapper functions that appear in symbol names with special suffixes:

| Shim Kind | v0 Suffix | Legacy Suffix | Source Evidence |
|-----------|-----------|---------------|-----------------|
| `ThreadLocalShim` | `S` + `"tls"` | `{{tls-shim}}` | `v0.rs:49`, `legacy.rs:83-85` |
| `VTableShim` | `S` + `"vtable"` | `{{vtable-shim}}` | `v0.rs:50`, `legacy.rs:86-88` |
| `ReifyShim` | `S` + `"reify"` | `{{reify-shim}}` | `v0.rs:51`, `legacy.rs:89-97` |
| `ReifyShim(FnPtr)` | `S` + `"reify_fnptr"` | `{{reify-shim-fnptr}}` | `v0.rs:52`, `legacy.rs:91` |
| `ReifyShim(Vtable)` | `S` + `"reify_vtable"` | `{{reify-shim-vtable}}` | `v0.rs:53`, `legacy.rs:92` |
| `FutureDropPollShim` | `S` + `"drop"` | `{{drop-shim}}` | `v0.rs:63`, `legacy.rs:107-109` |
| `ConstructCoroutineInClosureShim` (by_move) | `S` + `"by_move"` | `{{by-move-shim}}` | `v0.rs:58`, `legacy.rs:100-103` |
| `ConstructCoroutineInClosureShim` (by_ref) | `S` + `"by_ref"` | `{{by-ref-shim}}` | `v0.rs:60`, `legacy.rs:101` |

### 1.5 v0 Mangling Type Codes

Source: `rustc_symbol_mangling/src/v0.rs:438-467`

| Type | v0 Code | Example |
|------|---------|---------|
| `bool` | `b` | line 439 |
| `char` | `c` | line 440 |
| `str` | `e` | line 441 |
| `i8` | `a` | line 442 |
| `i16` | `s` | line 443 |
| `i32` | `l` | line 444 |
| `i64` | `x` | line 445 |
| `i128` | `n` | line 446 |
| `isize` | `i` | line 447 |
| `u8` | `h` | line 448 |
| `u16` | `t` | line 449 |
| `u32` | `m` | line 450 |
| `u64` | `y` | line 451 |
| `u128` | `o` | line 452 |
| `usize` | `j` | line 453 |
| `f16` | `C3f16` | line 454 |
| `f32` | `f` | line 455 |
| `f64` | `d` | line 456 |
| `f128` | `C4f128` | line 457 |
| `!` (never) | `z` | line 458 |
| `()` (unit) | `u` | line 460 |
| `&T` | `R` + type | line 489 |
| `&mut T` | `Q` + type | line 490 |
| `*const T` | `P` + type | line 501 |
| `*mut T` | `O` + type | line 502 |
| `[T]` (slice) | `S` + type | line 519 |
| `[T; N]` (array) | `A` + type + const | line 513 |
| `(T1, T2, ...)` (tuple) | `T` + types + `E` | line 523-529 |

### 1.6 Legacy Mangling Escapes

Source: `rustc_symbol_mangling/src/legacy.rs:523-558`

| Character | Escape Sequence | Line |
|-----------|-----------------|------|
| `@` | `$SP$` | 524 |
| `*` | `$BP$` | 525 |
| `&` | `$RF$` | 526 |
| `<` | `$LT$` | 527 |
| `>` | `$GT$` | 528 |
| `(` | `$LP$` | 529 |
| `)` | `$RP$` | 530 |
| `,` | `$C$` | 531 |
| `:` | `.` | 540 |
| `-` | `.` | 540 |

The legacy hash suffix format is `17h<16-hex-digits>E` (line 209).

---

## 2. Runtime Functions (Allocator)

### 2.1 Global Allocator Symbols

Source: `library/alloc/src/alloc.rs:13-35`

| IR Symbol | Args | Return | Source Evidence |
|-----------|------|--------|-----------------|
| `__rust_alloc` | `(size: usize, align: Alignment) -> *mut u8` | ptr or null | line 16-17, `#[rustc_allocator]` |
| `__rust_dealloc` | `(ptr: NonNull<u8>, size: usize, align: Alignment)` | void | line 20-22, `#[rustc_deallocator]` |
| `__rust_realloc` | `(ptr: NonNull<u8>, old_size: usize, align: Alignment, new_size: usize) -> *mut u8` | ptr or null | line 23-28, `#[rustc_reallocator]` |
| `__rust_alloc_zeroed` | `(size: usize, align: Alignment) -> *mut u8` | ptr or null | line 29-31, `#[rustc_allocator_zeroed]` |
| `__rust_no_alloc_shim_is_unstable_v2` | `()` | void | line 33-35 |

All allocator symbols are annotated with `#[rustc_nounwind]` and `#[rustc_std_internal_symbol]` (lines 18-19, 21-22, 26-27, 30-31).

### 2.2 Allocator Wrapper Generation

Source: `rustc_codegen_llvm/src/allocator.rs:19-87`

The compiler generates wrapper functions that forward calls from the mangled `__rust_*` symbols to the actual allocator implementations. Each wrapper:
- Uses `CCallConv` calling convention (line 122)
- Has `Global` unnamed address (line 123)
- Generates `__rust_no_alloc_shim_is_unstable_v2` as a guard symbol (lines 89-99)

### 2.3 Allocation in IR

When `Box::new()` or `Vec::new()` are used, the IR will contain:
1. A call to `__rust_alloc` (or `__rust_alloc_zeroed`)
2. A null check on the returned pointer
3. On failure, a call to the allocation error handler (`__rust_alloc_error_handler` or `alloc::alloc::handle_alloc_error`)

---

## 3. Compiler Intrinsics (replaced with LLVM builtins)

### 3.1 Math Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:47-168` (`call_simple_intrinsic`)

| Rust Intrinsic | LLVM IR | Source Line |
|----------------|---------|-------------|
| `sqrtf16/f32/f64/f128` | `@llvm.sqrt.f16/f32/f64/f128` | 53-56 |
| `powif16/f32/f64/f128` | `@llvm.powi.f16/f32/f64/f128.i32` | 58-61 |
| `sinf16/f32/f64/f128` | `@llvm.sin.f16/f32/f64/f128` | 63-66 |
| `cosf16/f32/f64/f128` | `@llvm.cos.f16/f32/f64/f128` | 68-71 |
| `powf16/f32/f64/f128` | `@llvm.pow.f16/f32/f64/f128` | 73-76 |
| `expf16/f32/f64/f128` | `@llvm.exp.f16/f32/f64/f128` | 78-81 |
| `exp2f16/f32/f64/f128` | `@llvm.exp2.f16/f32/f64/f128` | 83-86 |
| `logf16/f32/f64/f128` | `@llvm.log.f16/f32/f64/f128` | 88-91 |
| `log10f16/f32/f64/f128` | `@llvm.log10.f16/f32/f64/f128` | 93-96 |
| `log2f16/f32/f64/f128` | `@llvm.log2.f16/f32/f64/f128` | 98-101 |
| `fmaf16/f32/f64/f128` | `@llvm.fma.f16/f32/f64/f128` | 103-106 |
| `fmuladdf16/f32/f64/f128` | `@llvm.fmuladd.f16/f32/f64/f128` | 108-111 |
| `copysignf16/f32/f64/f128` | `@llvm.copysign.f16/f32/f64/f128` | 127-130 |
| `floorf16/f32/f64/f128` | `@llvm.floor.f16/f32/f64/f128` | 132-135 |
| `ceilf16/f32/f64/f128` | `@llvm.ceil.f16/f32/f64/f128` | 137-140 |
| `truncf16/f32/f64/f128` | `@llvm.trunc.f16/f32/f64/f128` | 142-145 |
| `round_ties_even_f16/f32/f64/f128` | `@llvm.rint.f16/f32/f64/f128` | 151-154 |
| `roundf16/f32/f64/f128` | `@llvm.round.f16/f32/f64/f128` | 156-159 |
| `fabs` | `@llvm.fabs` | 513-525 |
| `minimum_number_nsz_*` | `@llvm.minimumnum` (LLVM 22+) | 197-201 |
| `maximum_number_nsz_*` | `@llvm.maximumnum` (LLVM 22+) | 199 |

### 3.2 Bit Manipulation Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:434-511`

| Rust Intrinsic | LLVM IR | Source Line |
|----------------|---------|-------------|
| `ctlz` / `ctlz_nonzero` | `@llvm.ctlz` | 458-468 |
| `cttz` / `cttz_nonzero` | `@llvm.cttz` | 458-468 |
| `ctpop` | `@llvm.ctpop` | 470-472 |
| `bswap` | `@llvm.bswap` (no-op for i8) | 474-480 |
| `bitreverse` | `@llvm.bitreverse` | 482-484 |
| `unchecked_funnel_shl` | `@llvm.fshl` | 485-496 |
| `unchecked_funnel_shr` | `@llvm.fshr` | 485-496 |
| `saturating_add` | `@llvm.sadd.sat` / `@llvm.uadd.sat` | 498-508 |
| `saturating_sub` | `@llvm.ssub.sat` / `@llvm.usub.sat` | 498-508 |

### 3.3 Pointer/Address Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:212-219`

| Rust Intrinsic | LLVM IR | Source Line |
|----------------|---------|-------------|
| `ptr_mask` | `@llvm.ptrmask` | 214-218 |
| `is_val_statically_known` | `@llvm.is.constant` | 237-245 |
| `select_unpredictable` | `select` + `unpredictable` metadata | 247-275 |
| `prefetch_read_data` | `@llvm.prefetch` (rw=0, cache=1) | 358-381 |
| `prefetch_write_data` | `@llvm.prefetch` (rw=1, cache=1) | 358-381 |
| `prefetch_read_instruction` | `@llvm.prefetch` (rw=0, cache=0) | 358-381 |
| `prefetch_write_instruction` | `@llvm.prefetch` (rw=1, cache=0) | 358-381 |

### 3.4 Memory Operation Intrinsics

Source: `rustc_codegen_ssa/src/mir/intrinsic.rs:17-52`

| Rust Intrinsic | LLVM IR | Source Evidence |
|----------------|---------|-----------------|
| `copy_nonoverlapping<T>` | `@llvm.memcpy` | `intrinsic.rs:34` -- `bx.memcpy(...)` |
| `copy<T>` (overlapping) | `@llvm.memmove` | `intrinsic.rs:32` -- `bx.memmove(...)` |
| `write_bytes<T>` | `@llvm.memset` | `intrinsic.rs:51` -- `bx.memset(...)` |
| `volatile_copy_nonoverlapping_memory` | volatile `@llvm.memcpy` | `intrinsic.rs:223-233` |
| `volatile_copy_memory` | volatile `@llvm.memmove` | `intrinsic.rs:235-245` |
| `volatile_set_memory` | volatile `@llvm.memset` | `intrinsic.rs:247-256` |

### 3.5 Volatile Load/Store Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:332-356`

| Rust Intrinsic | LLVM IR | Source Line |
|----------------|---------|-------------|
| `volatile_load<T>` | `volatile load` | 332-346 |
| `unaligned_volatile_load<T>` | `volatile load` (align=1) | 335 |
| `volatile_store<T>` | `volatile store` | 348-352 |
| `unaligned_volatile_store<T>` | `volatile store` (align=1) | 353-356 |

### 3.6 Atomic Intrinsics

Source: `rustc_codegen_llvm/src/builder.rs:1293-1363`

| Rust Intrinsic | LLVM IR | Source Line |
|----------------|---------|-------------|
| `atomic_load<T>` | `load atomic` | `builder.rs:647` |
| `atomic_store<T>` | `store atomic` | `builder.rs:861` |
| `atomic_fence` | `fence` | `builder.rs:1346-1363` |
| `atomic_cxchg` (compare-exchange) | `cmpxchg` | `builder.rs:1293-1317` |
| `atomic_xadd` (fetch-add) | `atomicrmw add` | `builder.rs:1319-1344` |
| `atomic_xsub` (fetch-sub) | `atomicrmw sub` | `builder.rs:1319-1344` |
| `atomic_xchg` (swap) | `atomicrmw xchg` | `builder.rs:1319-1344` |
| `atomic_or` | `atomicrmw or` | `builder.rs:1319-1344` |
| `atomic_and` | `atomicrmw and` | `builder.rs:1319-1344` |
| `atomic_xor` | `atomicrmw xor` | `builder.rs:1319-1344` |
| `atomic_max` | `atomicrmw max` | `builder.rs:1319-1344` |
| `atomic_min` | `atomicrmw min` | `builder.rs:1319-1344` |
| `atomic_umax` | `atomicrmw umax` | `builder.rs:1319-1344` |
| `atomic_umin` | `atomicrmw umin` | `builder.rs:1319-1344` |

All atomic operations use `SingleThread = false` (CrossThread scope). See `builder.rs:1310` and `builder.rs:1337`.

### 3.7 Other Compiler Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:286-290`, `rustc_codegen_ssa/src/mir/intrinsic.rs:268-292`

| Rust Intrinsic | LLVM IR | Source |
|----------------|---------|--------|
| `breakpoint` | `@llvm.debugtrap` | `intrinsic.rs:286` |
| `black_box` | store + inline asm `"" : "r,~{memory}"` | `intrinsic.rs:577-613` |
| `abort` | `@llvm.trap` | `intrinsic.rs:924` |
| `assume` | `@llvm.assume` | `intrinsic.rs:927-931` |
| `expect` | `@llvm.expect.i1` | `intrinsic.rs:933-943` |
| `va_start` | `@llvm.va_start` | `intrinsic.rs:962-963` |
| `va_end` | `@llvm.va_end` | `intrinsic.rs:966-967` |
| `exact_div` | `udiv exact` / `sdiv exact` | `codegen_ssa/intrinsic.rs:273-292` |
| `disjoint_bitor` | `or disjoint` | `codegen_ssa/intrinsic.rs:268-272` |
| `fadd_fast` / `fsub_fast` etc. | `fadd fast` / `fsub fast` | `codegen_ssa/intrinsic.rs:293-299` |
| `carrying_mul_add` | mul+add+shift pattern | `intrinsic.rs:382-412` |
| `carryless_mul` | `@llvm.clmul` (LLVM 22+) | `intrinsic.rs:415-432` |
| `raw_eq` | `memcmp` or integer `icmp` | `intrinsic.rs:527-564` |
| `compare_bytes` | `memcmp` + `sext` to i32 | `intrinsic.rs:566-575` |
| `type_checked_load` | `@llvm.type.checked.load` | `intrinsic.rs:945-960` |

### 3.8 Transmute

Source: `rustc_codegen_ssa/src/mir/rvalue.rs:209-232`

`transmute` is NOT emitted as a function call. It is lowered to:
- A `store` from source to destination place (for `BackendRepr::Memory` types)
- A `bitcast` between scalar types (for `BackendRepr::Scalar` / `ScalarPair`)
- An `unreachable` terminator for size mismatches or uninhabited types (UB cases)

```rust
fn codegen_transmute(&mut self, bx: &mut Bx, src: OperandRef, dst: PlaceRef) {
    if src.layout.size != dst.layout.size || src.layout.is_uninhabited() || dst.layout.is_uninhabited() {
        bx.unreachable_nonterminator();  // line 225
    } else {
        src.store_with_annotation(bx, dst.val.with_type(src.layout));  // line 230
    }
}
```

### 3.9 SIMD Intrinsics

Source: `rustc_codegen_llvm/src/intrinsic.rs:730-790`

All SIMD intrinsics are prefixed with `simd_` and dispatched through `generic_simd_intrinsic()`. They appear in IR as LLVM vector operations or `@llvm.*` intrinsics.

---

## 4. FFI Patterns (extern "C")

### 4.1 Calling Convention Mapping

Source: `rustc_codegen_llvm/src/abi.rs:713-750`

| Rust ABI | LLVM Calling Convention | Source Line |
|----------|------------------------|-------------|
| `extern "C"` | `CCallConv` (C) | 715 |
| `extern "Rust"` | `CCallConv` (C) | 715 |
| `extern "RustCold"` | `PreserveMost` | 716 |
| `extern "RustPreserveNone"` | `PreserveNone` (x86_64/AArch64) | 717-719 |
| `extern "system"` | platform-dependent (Win64 on MSVC, C otherwise) | 719 |
| `extern "cdecl"` | `CCallConv` | 715 (via CanonAbi::C) |
| `extern "stdcall"` | `X86StdcallCallConv` | 743 |
| `extern "fastcall"` | `X86FastcallCallConv` | 742 |
| `extern "thiscall"` | `X86_ThisCall` | 745 |
| `extern "vectorcall"` | `X86_VectorCall` | 746 |
| `extern "win64"` | `X86_64_Win64` | 747 |
| `extern "sysv64"` | `X86_64_SysV` | 744 |
| `extern "aapcs"` | `ArmAapcsCallConv` | 738 |
| `extern "gpu-kernel"` | `AmdgpuKernel` / `PtxKernel` | 726-728 |

Key finding: **`extern "C"` and `extern "Rust"` use the same LLVM calling convention (`CCallConv`)**. The difference is in the ABI handling (parameter passing, return values), not the LLVM call instruction itself. See line 715.

### 4.2 ABI Function Attributes

Source: `rustc_codegen_llvm/src/abi.rs:431-513`

| Attribute | When Applied | Source Line |
|-----------|-------------|-------------|
| `noreturn` | Return type is uninhabited | 438-439 |
| `nounwind` | `can_unwind = false` | 441-443 |
| `sret(<type>)` | Indirect return (large structs) | 493-497 |
| `byval(<type>)` | Indirect pass-on-stack args | 517-525 |
| `inalloca` | Inalloca pass mode | 526-528 |
| `zeroext` / `signext` | ZExt/SExt arg extension | `abi.rs:71-72` |
| `nonnull` | NonNull pointer args | `abi.rs:79` |
| `dereferenceable(N)` | Known-dereferenceable pointers | `abi.rs:80-83` |
| `align(N)` | Known-aligned pointers | `abi.rs:66-67` |
| `range(type, lo, hi)` | Valid range metadata on scalars | `abi.rs:465-481` |
| `noundef` | NoUndef attribute | `abi.rs:100-103` |
| `writable` | Writable memory attribute | `abi.rs:46` |
| `dead_on_unwind` | SRet arguments | `abi.rs:504` |
| `inreg` | In-register passing | `abi.rs:38-39` |
| `captures(none/address/readonly)` | Capture attributes | `abi.rs:49-53` |

### 4.3 Foreign Function Declarations

Source: `rustc_codegen_llvm/src/callee.rs:18-161`

Foreign functions (`extern "C" { fn ... }`) are declared with:
- `ExternalLinkage` (line 99)
- Default visibility (for foreign crates) or hidden (for monomorphized generics)
- The symbol name comes directly from `#[link_name]` or the Rust item name

### 4.4 `#[repr(C)]` and `#[repr(transparent)]`

Source: `rustc_abi/src/lib.rs:81-104`

| Repr | Layout Property | Source |
|------|----------------|--------|
| `#[repr(C)]` | `ReprFlags::IS_C` -- C-compatible field ordering and padding | `lib.rs:84` |
| `#[repr(transparent)]` | `ReprFlags::IS_TRANSPARENT` -- single non-ZST field, same ABI | `lib.rs:90` |
| `#[repr(packed)]` | `ReprFlags::IS_PACKED` -- no padding between fields | `lib.rs:88` |
| `#[repr(simd)]` | `ReprFlags::IS_SIMD` -- SIMD vector type | `lib.rs:89` |

`#[repr(transparent)]` structs are represented in LLVM IR as their single non-ZST field type -- no wrapping struct.

---

## 5. Panic / Unwind / Exception Handling

### 5.1 Panic Functions

Source: `library/core/src/panicking.rs:57-277`

| Symbol | IR Signature | Source Line |
|--------|-------------|-------------|
| `core::panicking::panic_fmt` | `fn(fmt::Arguments) -> !` | 60 -- `#[lang = "panic_fmt"]` |
| `core::panicking::panic_nounwind_fmt` | `fn(fmt::Arguments, bool) -> !` | 95 |
| `core::panicking::panic` | `fn(&'static str) -> !` | 138 -- `#[lang = "panic"]` |
| `core::panicking::panic_nounwind` | `fn(&'static str) -> !` | 224 -- `#[lang = "panic_nounwind"]` |
| `core::panicking::panic_display` | `fn(&T: Display) -> !` | 258 -- `#[lang = "panic_display"]` |
| `core::panicking::panic_bounds_check` | `fn(usize, usize) -> !` | 265 -- `#[lang = "panic_bounds_check"]` |
| `core::panicking::panic_misaligned_pointer_dereference` | `fn(usize, usize) -> !` | 277 -- `#[lang = "panic_misaligned_pointer_dereference"]` |

### 5.2 Exception Handling Patterns

Source: `rustc_codegen_llvm/src/context.rs:839-878`, `rustc_codegen_llvm/src/intrinsic.rs:1204-1600`

| Platform | Personality Function | Source |
|----------|---------------------|--------|
| Linux/Unix (Dwarf EH) | `rust_eh_personality` (from `#[eh_personality]` lang item) | `context.rs:877` |
| Windows (MSVC SEH) | `__CxxFrameHandler3` | `context.rs:865` |
| WASM | `__gxx_wasm_personality_v0` | `context.rs:870` |

**`__rust_try` function** (for `catch_unwind` intrinsic):

Source: `rustc_codegen_llvm/src/intrinsic.rs:1629-1672`

Generated signature: `fn __rust_try(try_func: fn(*mut u8), data: *mut u8, catch_func: fn(*mut u8, *mut u8)) -> i32`

The function uses `invoke`/`landingpad` (Dwarf), `invoke`/`catchswitch`/`catchpad`/`catchret` (MSVC SEH), or `invoke`/`catchswitch` (WASM).

### 5.3 Landing Pad / Cleanup Patterns

Source: `rustc_codegen_llvm/src/builder.rs:1225-1251`

- `resume` instruction: re-throws an exception (line 1225)
- `cleanuppad`: MSVC SEH cleanup (line 1242)
- `cleanupret`: MSVC SEH cleanup return (line 1250)
- `landingpad`: Dwarf exception landing pad (used in `codegen_gnu_try`, line 1507)

---

## 6. Transform-Pass Introduced Patterns

### 6.1 Drop Elaboration

Source: `rustc_mir_transform/src/elaborate_drops.rs:20-29`

Drop terminators in MIR are elaborated into conditional calls to "drop glue" or "drop shims":
- For types that don't need dropping: eliminated entirely
- For types that need dropping: a drop flag is inserted and checked at runtime
- The drop glue function is `drop_in_place::<T>` -- represented as `InstanceKind::DropGlue`

### 6.2 InstanceKind Variants

Source: `rustc_middle/src/ty/instance.rs:62-182`

| InstanceKind | Description | IR Effect |
|-------------|-------------|-----------|
| `Item(DefId)` | Regular function/static | Normal function symbol |
| `VTableShim(DefId)` | VTable dispatch shim | `{{vtable-shim}}` suffix |
| `ReifyShim(DefId, reason)` | fn item -> fn pointer shim | `{{reify-shim}}` suffix |
| `FnPtrShim(DefId, Ty)` | FnPtr trait shim | Custom symbol |
| `Virtual(DefId, usize)` | dyn Trait vtable call | No direct symbol; vtable index |
| `Intrinsic(DefId)` | Compiler intrinsic | Replaced with LLVM builtin |
| `ClosureOnceShim { call_once }` | `FnOnce::call_once` for closures | Custom symbol |
| `ThreadLocalShim(DefId)` | Thread-local access shim | `{{tls-shim}}` suffix |
| `DropGlue(DefId, Option<Ty>)` | Drop destructor glue | `drop_in_place::<T>` |
| `CloneShim(DefId, Ty)` | Clone implementation shim | Custom symbol |
| `AsyncDropGlue(DefId, Ty)` | Async drop glue | Custom symbol |
| `FutureDropPollShim(DefId, Ty, Ty)` | Future drop poll shim | `{{drop-shim}}` suffix |

### 6.3 Monomorphization

Generic functions are monomorphized at codegen time. Each unique set of type parameters produces a separate symbol with the concrete types encoded in the mangling.

Source: `rustc_middle/src/ty/instance.rs:23-26`

```
// Example: Vec<i32>::push and Vec<f64>::push get different symbols
_ZN5alloc3vec16Vec$LT$i32$GT$4push17h...E
_ZN5alloc3vec16Vec$LT$f64$GT$4push17h...E
```

### 6.4 Linkage Modes

Source: `rustc_codegen_llvm/src/base.rs:189-200`

| Linkage | LLVM Linkage | Use Case |
|---------|-------------|----------|
| `External` | `ExternalLinkage` | Exported symbols |
| `AvailableExternally` | `AvailableExternallyLinkage` | Inline function bodies from other crates |
| `LinkOnceAny` | `LinkOnceAnyLinkage` | Link-once (any) |
| `LinkOnceODR` | `LinkOnceODRLinkage` | Link-once (ODR) -- common for generics |
| `WeakAny` | `WeakAnyLinkage` | Weak symbols |
| `WeakODR` | `WeakODRLinkage` | Weak ODR symbols |
| `Internal` | `InternalLinkage` | Private symbols (e.g., `static` items) |
| `ExternalWeak` | `ExternalWeakLinkage` | Weak external references |
| `Common` | `CommonLinkage` | Common symbols |

### 6.5 Visibility

Source: `rustc_codegen_llvm/src/callee.rs:100-141`

| Visibility | When Applied | Source |
|-----------|-------------|--------|
| `Default` | Exported functions | line 99 |
| `Hidden` | Non-shared generics, internal items, compiler-builtins | lines 102-141 |
| `Protected` | Not commonly used | N/A |

Generic monomorphizations get `Hidden` visibility when:
- Not sharing generics across crates (line 106-109)
- Defined locally but unreachable (line 119)
- Instantiated locally but not re-exported (line 126-128)

---

## 7. Key IR Patterns for Static Analysis

### 7.1 Lifetime Markers

Source: `rustc_codegen_llvm/src/builder.rs:1369-1375`

| LLVM IR | Rust Meaning |
|---------|-------------|
| `@llvm.lifetime.start.p0(size, ptr)` | Start of a local variable's lifetime |
| `@llvm.lifetime.end.p0(size, ptr)` | End of a local variable's lifetime |

### 7.2 Type Metadata

Source: `rustc_codegen_llvm/src/intrinsic.rs:945-960`

| LLVM IR | Rust Meaning |
|---------|-------------|
| `@llvm.type.checked.load(vtable, offset, typeid)` | VTable call with type checking |
| `!type` metadata on global variables | Type identity for CFI/KCFI |

### 7.3 Entry Wrapper

Source: `rustc_codegen_llvm/src/base.rs:123-128`

The main function gets an entry wrapper that:
1. Calls `lang_start` (for std binaries) or the user's `main` directly
2. Applies sanitizer attributes

### 7.4 `llvm.used` and `llvm.compiler.used`

Source: `rustc_codegen_llvm/src/base.rs:149-159`

- `@llvm.used = appending global [...]` -- prevents linker from stripping symbols
- `@llvm.compiler.used = appending global [...]` -- prevents LLVM optimizer from removing symbols

Both contain coverage maps, Objective-C module info, and other compiler-generated data.

---

## 8. Key Takeaways for Static Analysis

### What's user code (analyze these):
- Functions matching `_R<encoded>` (v0 mangling) or `_ZN<encoded>` (legacy mangling)
- Functions with `#[no_mangle]` names (no prefix)
- Functions with `#[export_name = "..."]` names
- Static variables with user-defined names

### What's compiler runtime (filter/skip these):
- `__rust_alloc`, `__rust_dealloc`, `__rust_realloc`, `__rust_alloc_zeroed` (allocator)
- `__rust_no_alloc_shim_is_unstable_v2` (allocator guard)
- `__rust_try` (catch_unwind helper)
- `__rust_panic_type_info` (MSVC panic type info)
- `rust_eh_personality` / `__CxxFrameHandler3` / `__gxx_wasm_personality_v0` (EH personality)
- `core::panicking::*` functions (panic handlers)
- LLVM intrinsics (`@llvm.*`)
- Drop glue functions (`drop_in_place::<T>`)
- Shim symbols (containing `{{...}}` in legacy mangling, or `S` prefix in v0)

### What's FFI boundary (classify as cross-language):
- `extern "C"` function declarations -- same LLVM calling convention as `extern "Rust"` but different ABI rules
- Functions in `extern { }` blocks
- `#[repr(C)]` types -- guaranteed C-compatible layout
- `#[repr(transparent)]` types -- transparent wrapper, same ABI as inner type
- Foreign function imports (`dllimport`, `wasm_import_module`)

### What indicates memory safety concerns:
- `@llvm.memcpy` / `@llvm.memmove` / `@llvm.memset` -- raw memory operations
- `volatile load` / `volatile store` -- volatile memory access
- `load atomic` / `store atomic` / `cmpxchg` / `atomicrmw` / `fence` -- atomic operations
- `unreachable` -- indicates UB was detected
- `@llvm.assume` -- optimization hint that may mask UB
- `@llvm.trap` -- immediate abort
- Null checks before allocator return values

### What indicates control flow:
- `invoke` + `landingpad` / `catchswitch` -- exception handling
- `resume` -- re-throwing exceptions
- `select` -- conditional value selection
- `switch` / `br` -- control flow branches
