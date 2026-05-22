# Rust LLVM IR 规范：编译器保留符号 vs 用户定义符号

**来源**: `/Users/scc/code/rustcode/rust/compiler/` (master 分支)
**日期**: 2026-05-22
**用途**: 区分编译器保留的 IR 模式与用户定义符号，供静态分析工具（如 OmniScope）使用

---

## 1. 符号命名规则

### 1.1 符号修饰方案

Rust 使用两种符号修饰方案，可通过 `-C symbol-mangling-version` 选择：

| 方案 | 前缀 | 示例 | 来源证据 |
|------|------|------|----------|
| **v0**（默认） | `_R` | `_RNvCsiatkNdJK2di_7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:35` -- `let prefix = "_R"` |
| **Legacy** | `_ZN` | `_ZN7mycrate3foo17h0123456789abcdefE` | `rustc_symbol_mangling/src/legacy.rs:195` -- `result.push_str("_ZN")` |

版本选择逻辑位于 `rustc_symbol_mangling/src/lib.rs:272-316`：

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

### 1.2 用户定义符号

| 模式 | IR 符号示例 | 来源证据 |
|------|-------------|----------|
| 默认函数（v0） | `_RNvC7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:76` -- `p.print_def_path(def_id, args)` |
| 默认函数（legacy） | `_ZN7mycrate3foo17h<hash>E` | `rustc_symbol_mangling/src/legacy.rs:111` -- `p.path.finish(hash)` |
| `#[no_mangle]` | `foo`（用户选择的名称） | `rustc_symbol_mangling/src/lib.rs:231-233` -- `attrs.flags.contains(NO_MANGLE)` |
| `#[export_name = "..."]` | `<用户选择的名称>` | `rustc_symbol_mangling/src/lib.rs:226-229` -- `attrs.symbol_name` |
| `#[linkage = "external"]` | 取决于链接类型 | `rustc_middle/src/middle/codegen_fn_attrs.rs:88-89` |

### 1.3 编译器保留符号

| 前缀/模式 | 示例 | 来源证据 |
|-----------|------|----------|
| `_R` + v0 编码路径 | `_RNvC7mycrate3foo` | `rustc_symbol_mangling/src/v0.rs:35` |
| `_ZN` + legacy 编码路径 | `_ZN7mycrate3foo17h<hash>E` | `rustc_symbol_mangling/src/legacy.rs:195-209` |
| `_RC<crate_hash>__rustc` | `#[rustc_std_internal_symbol]` 项 | `rustc_symbol_mangling/src/v0.rs:106-128` |
| `__rust_alloc` | 全局分配器（分配） | `library/alloc/src/alloc.rs:16-17` -- `#[rustc_allocator]` |
| `__rust_dealloc` | 全局分配器（释放） | `library/alloc/src/alloc.rs:20-22` -- `#[rustc_deallocator]` |
| `__rust_realloc` | 全局分配器（重分配） | `library/alloc/src/alloc.rs:23-28` -- `#[rustc_reallocator]` |
| `__rust_alloc_zeroed` | 全局分配器（零初始化） | `library/alloc/src/alloc.rs:29-31` -- `#[rustc_allocator_zeroed]` |
| `__rust_no_alloc_shim_is_unstable_v2` | 分配器 shim 守卫 | `library/alloc/src/alloc.rs:33-35` |
| `__rust_try` | catch_unwind 辅助函数 | `rustc_codegen_llvm/src/intrinsic.rs:1670` |
| `__rust_panic_type_info` | MSVC panic 类型信息 | `rustc_codegen_llvm/src/intrinsic.rs:1341` |
| `rust_eh_personality` | 异常处理人格函数 | `rustc_symbol_mangling/src/v0.rs:87` -- 硬编码名称 |
| `__CxxFrameHandler3` | MSVC SEH 人格函数 | `rustc_codegen_llvm/src/context.rs:865` |
| `__gxx_wasm_personality_v0` | WASM EH 人格函数 | `rustc_codegen_llvm/src/context.rs:870` |
| `llvm.used` | 防止符号消除 | `rustc_codegen_llvm/src/base.rs:151` |
| `llvm.compiler.used` | 防止编译器消除 | `rustc_codegen_llvm/src/base.rs:158` |

### 1.4 Shim 符号修饰

Shim 是编译器生成的包装函数，在符号名称中带有特殊后缀：

| Shim 类型 | v0 后缀 | Legacy 后缀 | 来源证据 |
|-----------|---------|-------------|----------|
| `ThreadLocalShim` | `S` + `"tls"` | `{{tls-shim}}` | `v0.rs:49`, `legacy.rs:83-85` |
| `VTableShim` | `S` + `"vtable"` | `{{vtable-shim}}` | `v0.rs:50`, `legacy.rs:86-88` |
| `ReifyShim` | `S` + `"reify"` | `{{reify-shim}}` | `v0.rs:51`, `legacy.rs:89-97` |
| `ReifyShim(FnPtr)` | `S` + `"reify_fnptr"` | `{{reify-shim-fnptr}}` | `v0.rs:52`, `legacy.rs:91` |
| `ReifyShim(Vtable)` | `S` + `"reify_vtable"` | `{{reify-shim-vtable}}` | `v0.rs:53`, `legacy.rs:92` |
| `FutureDropPollShim` | `S` + `"drop"` | `{{drop-shim}}` | `v0.rs:63`, `legacy.rs:107-109` |
| `ConstructCoroutineInClosureShim`（by_move） | `S` + `"by_move"` | `{{by-move-shim}}` | `v0.rs:58`, `legacy.rs:100-103` |
| `ConstructCoroutineInClosureShim`（by_ref） | `S` + `"by_ref"` | `{{by-ref-shim}}` | `v0.rs:60`, `legacy.rs:101` |

### 1.5 v0 修饰类型编码

来源：`rustc_symbol_mangling/src/v0.rs:438-467`

| 类型 | v0 编码 | 示例 |
|------|---------|------|
| `bool` | `b` | 第 439 行 |
| `char` | `c` | 第 440 行 |
| `str` | `e` | 第 441 行 |
| `i8` | `a` | 第 442 行 |
| `i16` | `s` | 第 443 行 |
| `i32` | `l` | 第 444 行 |
| `i64` | `x` | 第 445 行 |
| `i128` | `n` | 第 446 行 |
| `isize` | `i` | 第 447 行 |
| `u8` | `h` | 第 448 行 |
| `u16` | `t` | 第 449 行 |
| `u32` | `m` | 第 450 行 |
| `u64` | `y` | 第 451 行 |
| `u128` | `o` | 第 452 行 |
| `usize` | `j` | 第 453 行 |
| `f16` | `C3f16` | 第 454 行 |
| `f32` | `f` | 第 455 行 |
| `f64` | `d` | 第 456 行 |
| `f128` | `C4f128` | 第 457 行 |
| `!`（never 类型） | `z` | 第 458 行 |
| `()`（单元类型） | `u` | 第 460 行 |
| `&T` | `R` + 类型 | 第 489 行 |
| `&mut T` | `Q` + 类型 | 第 490 行 |
| `*const T` | `P` + 类型 | 第 501 行 |
| `*mut T` | `O` + 类型 | 第 502 行 |
| `[T]`（切片） | `S` + 类型 | 第 519 行 |
| `[T; N]`（数组） | `A` + 类型 + 常量 | 第 513 行 |
| `(T1, T2, ...)`（元组） | `T` + 类型 + `E` | 第 523-529 行 |

### 1.6 Legacy 修饰转义

来源：`rustc_symbol_mangling/src/legacy.rs:523-558`

| 字符 | 转义序列 | 行号 |
|------|----------|------|
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

Legacy 哈希后缀格式为 `17h<16位十六进制>E`（第 209 行）。

---

## 2. 运行时函数（分配器）

### 2.1 全局分配器符号

来源：`library/alloc/src/alloc.rs:13-35`

| IR 符号 | 参数 | 返回值 | 来源证据 |
|---------|------|--------|----------|
| `__rust_alloc` | `(size: usize, align: Alignment) -> *mut u8` | 指针或 null | 第 16-17 行，`#[rustc_allocator]` |
| `__rust_dealloc` | `(ptr: NonNull<u8>, size: usize, align: Alignment)` | void | 第 20-22 行，`#[rustc_deallocator]` |
| `__rust_realloc` | `(ptr: NonNull<u8>, old_size: usize, align: Alignment, new_size: usize) -> *mut u8` | 指针或 null | 第 23-28 行，`#[rustc_reallocator]` |
| `__rust_alloc_zeroed` | `(size: usize, align: Alignment) -> *mut u8` | 指针或 null | 第 29-31 行，`#[rustc_allocator_zeroed]` |
| `__rust_no_alloc_shim_is_unstable_v2` | `()` | void | 第 33-35 行 |

所有分配器符号均标注 `#[rustc_nounwind]` 和 `#[rustc_std_internal_symbol]`（第 18-19、21-22、26-27、30-31 行）。

### 2.2 分配器包装生成

来源：`rustc_codegen_llvm/src/allocator.rs:19-87`

编译器生成包装函数，将修饰后的 `__rust_*` 符号转发到实际的分配器实现。每个包装函数：
- 使用 `CCallConv` 调用约定（第 122 行）
- 具有 `Global` 未命名地址（第 123 行）
- 生成 `__rust_no_alloc_shim_is_unstable_v2` 作为守卫符号（第 89-99 行）

### 2.3 IR 中的分配模式

当使用 `Box::new()` 或 `Vec::new()` 时，IR 将包含：
1. 对 `__rust_alloc`（或 `__rust_alloc_zeroed`）的调用
2. 对返回指针的空值检查
3. 失败时，调用分配错误处理函数（`__rust_alloc_error_handler` 或 `alloc::alloc::handle_alloc_error`）

---

## 3. 编译器内建函数（替换为 LLVM 内建函数）

### 3.1 数学内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:47-168`（`call_simple_intrinsic`）

| Rust 内建函数 | LLVM IR | 来源行号 |
|--------------|---------|----------|
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
| `minimum_number_nsz_*` | `@llvm.minimumnum`（LLVM 22+） | 197-201 |
| `maximum_number_nsz_*` | `@llvm.maximumnum`（LLVM 22+） | 199 |

### 3.2 位操作内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:434-511`

| Rust 内建函数 | LLVM IR | 来源行号 |
|--------------|---------|----------|
| `ctlz` / `ctlz_nonzero` | `@llvm.ctlz` | 458-468 |
| `cttz` / `cttz_nonzero` | `@llvm.cttz` | 458-468 |
| `ctpop` | `@llvm.ctpop` | 470-472 |
| `bswap` | `@llvm.bswap`（i8 时为空操作） | 474-480 |
| `bitreverse` | `@llvm.bitreverse` | 482-484 |
| `unchecked_funnel_shl` | `@llvm.fshl` | 485-496 |
| `unchecked_funnel_shr` | `@llvm.fshr` | 485-496 |
| `saturating_add` | `@llvm.sadd.sat` / `@llvm.uadd.sat` | 498-508 |
| `saturating_sub` | `@llvm.ssub.sat` / `@llvm.usub.sat` | 498-508 |

### 3.3 指针/地址内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:212-219`

| Rust 内建函数 | LLVM IR | 来源行号 |
|--------------|---------|----------|
| `ptr_mask` | `@llvm.ptrmask` | 214-218 |
| `is_val_statically_known` | `@llvm.is.constant` | 237-245 |
| `select_unpredictable` | `select` + `unpredictable` 元数据 | 247-275 |
| `prefetch_read_data` | `@llvm.prefetch`（rw=0, cache=1） | 358-381 |
| `prefetch_write_data` | `@llvm.prefetch`（rw=1, cache=1） | 358-381 |
| `prefetch_read_instruction` | `@llvm.prefetch`（rw=0, cache=0） | 358-381 |
| `prefetch_write_instruction` | `@llvm.prefetch`（rw=1, cache=0） | 358-381 |

### 3.4 内存操作内建函数

来源：`rustc_codegen_ssa/src/mir/intrinsic.rs:17-52`

| Rust 内建函数 | LLVM IR | 来源证据 |
|--------------|---------|----------|
| `copy_nonoverlapping<T>` | `@llvm.memcpy` | `intrinsic.rs:34` -- `bx.memcpy(...)` |
| `copy<T>`（可重叠） | `@llvm.memmove` | `intrinsic.rs:32` -- `bx.memmove(...)` |
| `write_bytes<T>` | `@llvm.memset` | `intrinsic.rs:51` -- `bx.memset(...)` |
| `volatile_copy_nonoverlapping_memory` | volatile `@llvm.memcpy` | `intrinsic.rs:223-233` |
| `volatile_copy_memory` | volatile `@llvm.memmove` | `intrinsic.rs:235-245` |
| `volatile_set_memory` | volatile `@llvm.memset` | `intrinsic.rs:247-256` |

### 3.5 易失性加载/存储内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:332-356`

| Rust 内建函数 | LLVM IR | 来源行号 |
|--------------|---------|----------|
| `volatile_load<T>` | `volatile load` | 332-346 |
| `unaligned_volatile_load<T>` | `volatile load`（align=1） | 335 |
| `volatile_store<T>` | `volatile store` | 348-352 |
| `unaligned_volatile_store<T>` | `volatile store`（align=1） | 353-356 |

### 3.6 原子操作内建函数

来源：`rustc_codegen_llvm/src/builder.rs:1293-1363`

| Rust 内建函数 | LLVM IR | 来源行号 |
|--------------|---------|----------|
| `atomic_load<T>` | `load atomic` | `builder.rs:647` |
| `atomic_store<T>` | `store atomic` | `builder.rs:861` |
| `atomic_fence` | `fence` | `builder.rs:1346-1363` |
| `atomic_cxchg`（比较交换） | `cmpxchg` | `builder.rs:1293-1317` |
| `atomic_xadd`（原子加） | `atomicrmw add` | `builder.rs:1319-1344` |
| `atomic_xsub`（原子减） | `atomicrmw sub` | `builder.rs:1319-1344` |
| `atomic_xchg`（原子交换） | `atomicrmw xchg` | `builder.rs:1319-1344` |
| `atomic_or` | `atomicrmw or` | `builder.rs:1319-1344` |
| `atomic_and` | `atomicrmw and` | `builder.rs:1319-1344` |
| `atomic_xor` | `atomicrmw xor` | `builder.rs:1319-1344` |
| `atomic_max` | `atomicrmw max` | `builder.rs:1319-1344` |
| `atomic_min` | `atomicrmw min` | `builder.rs:1319-1344` |
| `atomic_umax` | `atomicrmw umax` | `builder.rs:1319-1344` |
| `atomic_umin` | `atomicrmw umin` | `builder.rs:1319-1344` |

所有原子操作使用 `SingleThread = false`（跨线程作用域）。参见 `builder.rs:1310` 和 `builder.rs:1337`。

### 3.7 其他编译器内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:286-290`，`rustc_codegen_ssa/src/mir/intrinsic.rs:268-292`

| Rust 内建函数 | LLVM IR | 来源 |
|--------------|---------|------|
| `breakpoint` | `@llvm.debugtrap` | `intrinsic.rs:286` |
| `black_box` | store + 内联汇编 `"" : "r,~{memory}"` | `intrinsic.rs:577-613` |
| `abort` | `@llvm.trap` | `intrinsic.rs:924` |
| `assume` | `@llvm.assume` | `intrinsic.rs:927-931` |
| `expect` | `@llvm.expect.i1` | `intrinsic.rs:933-943` |
| `va_start` | `@llvm.va_start` | `intrinsic.rs:962-963` |
| `va_end` | `@llvm.va_end` | `intrinsic.rs:966-967` |
| `exact_div` | `udiv exact` / `sdiv exact` | `codegen_ssa/intrinsic.rs:273-292` |
| `disjoint_bitor` | `or disjoint` | `codegen_ssa/intrinsic.rs:268-272` |
| `fadd_fast` / `fsub_fast` 等 | `fadd fast` / `fsub fast` | `codegen_ssa/intrinsic.rs:293-299` |
| `carrying_mul_add` | mul+add+shift 模式 | `intrinsic.rs:382-412` |
| `carryless_mul` | `@llvm.clmul`（LLVM 22+） | `intrinsic.rs:415-432` |
| `raw_eq` | `memcmp` 或整数 `icmp` | `intrinsic.rs:527-564` |
| `compare_bytes` | `memcmp` + `sext` 到 i32 | `intrinsic.rs:566-575` |
| `type_checked_load` | `@llvm.type.checked.load` | `intrinsic.rs:945-960` |

### 3.8 Transmute（类型转换）

来源：`rustc_codegen_ssa/src/mir/rvalue.rs:209-232`

`transmute` 不会作为函数调用发出。它被降低为：
- 从源到目标位置的 `store`（用于 `BackendRepr::Memory` 类型）
- 标量类型之间的 `bitcast`（用于 `BackendRepr::Scalar` / `ScalarPair`）
- 对于大小不匹配或未填充类型的情况，发出 `unreachable` 终止符（UB 情况）

```rust
fn codegen_transmute(&mut self, bx: &mut Bx, src: OperandRef, dst: PlaceRef) {
    if src.layout.size != dst.layout.size || src.layout.is_uninhabited() || dst.layout.is_uninhabited() {
        bx.unreachable_nonterminator();  // 第 225 行
    } else {
        src.store_with_annotation(bx, dst.val.with_type(src.layout));  // 第 230 行
    }
}
```

### 3.9 SIMD 内建函数

来源：`rustc_codegen_llvm/src/intrinsic.rs:730-790`

所有 SIMD 内建函数以 `simd_` 为前缀，通过 `generic_simd_intrinsic()` 分发。它们在 IR 中表现为 LLVM 向量操作或 `@llvm.*` 内建函数。

---

## 4. FFI 模式（extern "C"）

### 4.1 调用约定映射

来源：`rustc_codegen_llvm/src/abi.rs:713-750`

| Rust ABI | LLVM 调用约定 | 来源行号 |
|----------|--------------|----------|
| `extern "C"` | `CCallConv`（C） | 715 |
| `extern "Rust"` | `CCallConv`（C） | 715 |
| `extern "RustCold"` | `PreserveMost` | 716 |
| `extern "RustPreserveNone"` | `PreserveNone`（x86_64/AArch64） | 717-719 |
| `extern "system"` | 平台相关（MSVC 上为 Win64，其他为 C） | 719 |
| `extern "cdecl"` | `CCallConv` | 715（通过 CanonAbi::C） |
| `extern "stdcall"` | `X86StdcallCallConv` | 743 |
| `extern "fastcall"` | `X86FastcallCallConv` | 742 |
| `extern "thiscall"` | `X86_ThisCall` | 745 |
| `extern "vectorcall"` | `X86_VectorCall` | 746 |
| `extern "win64"` | `X86_64_Win64` | 747 |
| `extern "sysv64"` | `X86_64_SysV` | 744 |
| `extern "aapcs"` | `ArmAapcsCallConv` | 738 |
| `extern "gpu-kernel"` | `AmdgpuKernel` / `PtxKernel` | 726-728 |

关键发现：**`extern "C"` 和 `extern "Rust"` 使用相同的 LLVM 调用约定（`CCallConv`）**。区别在于 ABI 处理（参数传递、返回值），而非 LLVM 调用指令本身。参见第 715 行。

### 4.2 ABI 函数属性

来源：`rustc_codegen_llvm/src/abi.rs:431-513`

| 属性 | 何时应用 | 来源行号 |
|------|----------|----------|
| `noreturn` | 返回类型为未填充类型 | 438-439 |
| `nounwind` | `can_unwind = false` | 441-443 |
| `sret(<type>)` | 间接返回（大型结构体） | 493-497 |
| `byval(<type>)` | 间接栈上传递参数 | 517-525 |
| `inalloca` | Inalloca 传递模式 | 526-528 |
| `zeroext` / `signext` | ZExt/SExt 参数扩展 | `abi.rs:71-72` |
| `nonnull` | NonNull 指针参数 | `abi.rs:79` |
| `dereferenceable(N)` | 已知可解引用指针 | `abi.rs:80-83` |
| `align(N)` | 已知对齐指针 | `abi.rs:66-67` |
| `range(type, lo, hi)` | 标量上的有效范围元数据 | `abi.rs:465-481` |
| `noundef` | NoUndef 属性 | `abi.rs:100-103` |
| `writable` | 可写内存属性 | `abi.rs:46` |
| `dead_on_unwind` | SRet 参数 | `abi.rs:504` |
| `inreg` | 寄存器内传递 | `abi.rs:38-39` |
| `captures(none/address/readonly)` | 捕获属性 | `abi.rs:49-53` |

### 4.3 外部函数声明

来源：`rustc_codegen_llvm/src/callee.rs:18-161`

外部函数（`extern "C" { fn ... }`）声明时带有：
- `ExternalLinkage`（第 99 行）
- 默认可见性（外部 crate）或隐藏（单态化泛型）
- 符号名称直接来自 `#[link_name]` 或 Rust 项名称

### 4.4 `#[repr(C)]` 和 `#[repr(transparent)]`

来源：`rustc_abi/src/lib.rs:81-104`

| 表示 | 布局属性 | 来源 |
|------|----------|------|
| `#[repr(C)]` | `ReprFlags::IS_C` -- C 兼容的字段排序和填充 | `lib.rs:84` |
| `#[repr(transparent)]` | `ReprFlags::IS_TRANSPARENT` -- 单个非 ZST 字段，相同 ABI | `lib.rs:90` |
| `#[repr(packed)]` | `ReprFlags::IS_PACKED` -- 字段间无填充 | `lib.rs:88` |
| `#[repr(simd)]` | `ReprFlags::IS_SIMD` -- SIMD 向量类型 | `lib.rs:89` |

`#[repr(transparent)]` 结构体在 LLVM IR 中表示为其单个非 ZST 字段类型 -- 无包装结构体。

---

## 5. Panic / 展开 / 异常处理

### 5.1 Panic 函数

来源：`library/core/src/panicking.rs:57-277`

| 符号 | IR 签名 | 来源行号 |
|------|---------|----------|
| `core::panicking::panic_fmt` | `fn(fmt::Arguments) -> !` | 60 -- `#[lang = "panic_fmt"]` |
| `core::panicking::panic_nounwind_fmt` | `fn(fmt::Arguments, bool) -> !` | 95 |
| `core::panicking::panic` | `fn(&'static str) -> !` | 138 -- `#[lang = "panic"]` |
| `core::panicking::panic_nounwind` | `fn(&'static str) -> !` | 224 -- `#[lang = "panic_nounwind"]` |
| `core::panicking::panic_display` | `fn(&T: Display) -> !` | 258 -- `#[lang = "panic_display"]` |
| `core::panicking::panic_bounds_check` | `fn(usize, usize) -> !` | 265 -- `#[lang = "panic_bounds_check"]` |
| `core::panicking::panic_misaligned_pointer_dereference` | `fn(usize, usize) -> !` | 277 -- `#[lang = "panic_misaligned_pointer_dereference"]` |

### 5.2 异常处理模式

来源：`rustc_codegen_llvm/src/context.rs:839-878`，`rustc_codegen_llvm/src/intrinsic.rs:1204-1600`

| 平台 | 人格函数 | 来源 |
|------|----------|------|
| Linux/Unix（Dwarf EH） | `rust_eh_personality`（来自 `#[eh_personality]` lang item） | `context.rs:877` |
| Windows（MSVC SEH） | `__CxxFrameHandler3` | `context.rs:865` |
| WASM | `__gxx_wasm_personality_v0` | `context.rs:870` |

**`__rust_try` 函数**（用于 `catch_unwind` 内建函数）：

来源：`rustc_codegen_llvm/src/intrinsic.rs:1629-1672`

生成的签名：`fn __rust_try(try_func: fn(*mut u8), data: *mut u8, catch_func: fn(*mut u8, *mut u8)) -> i32`

该函数使用 `invoke`/`landingpad`（Dwarf）、`invoke`/`catchswitch`/`catchpad`/`catchret`（MSVC SEH）或 `invoke`/`catchswitch`（WASM）。

### 5.3 Landing Pad / 清理模式

来源：`rustc_codegen_llvm/src/builder.rs:1225-1251`

- `resume` 指令：重新抛出异常（第 1225 行）
- `cleanuppad`：MSVC SEH 清理（第 1242 行）
- `cleanupret`：MSVC SEH 清理返回（第 1250 行）
- `landingpad`：Dwarf 异常着陆垫（在 `codegen_gnu_try` 中使用，第 1507 行）

---

## 6. 变换引入的模式

### 6.1 Drop 精细化

来源：`rustc_mir_transform/src/elaborate_drops.rs:20-29`

MIR 中的 Drop 终止符被精细化为对 "drop glue" 或 "drop shim" 的条件调用：
- 对于不需要 drop 的类型：完全消除
- 对于需要 drop 的类型：插入 drop 标志并在运行时检查
- Drop glue 函数为 `drop_in_place::<T>` -- 表示为 `InstanceKind::DropGlue`

### 6.2 InstanceKind 变体

来源：`rustc_middle/src/ty/instance.rs:62-182`

| InstanceKind | 描述 | IR 效果 |
|-------------|------|---------|
| `Item(DefId)` | 常规函数/静态变量 | 正常函数符号 |
| `VTableShim(DefId)` | VTable 分发 shim | `{{vtable-shim}}` 后缀 |
| `ReifyShim(DefId, reason)` | fn 项 -> fn 指针 shim | `{{reify-shim}}` 后缀 |
| `FnPtrShim(DefId, Ty)` | FnPtr trait shim | 自定义符号 |
| `Virtual(DefId, usize)` | dyn Trait vtable 调用 | 无直接符号；vtable 索引 |
| `Intrinsic(DefId)` | 编译器内建函数 | 替换为 LLVM 内建函数 |
| `ClosureOnceShim { call_once }` | 闭包的 `FnOnce::call_once` | 自定义符号 |
| `ThreadLocalShim(DefId)` | 线程局部访问 shim | `{{tls-shim}}` 后缀 |
| `DropGlue(DefId, Option<Ty>)` | Drop 析构器 glue | `drop_in_place::<T>` |
| `CloneShim(DefId, Ty)` | Clone 实现 shim | 自定义符号 |
| `AsyncDropGlue(DefId, Ty)` | 异步 drop glue | 自定义符号 |
| `FutureDropPollShim(DefId, Ty, Ty)` | Future drop poll shim | `{{drop-shim}}` 后缀 |

### 6.3 单态化

泛型函数在代码生成时被单态化。每组唯一的类型参数产生一个独立的符号，具体类型编码在修饰名称中。

来源：`rustc_middle/src/ty/instance.rs:23-26`

```
// 示例：Vec<i32>::push 和 Vec<f64>::push 获得不同的符号
_ZN5alloc3vec16Vec$LT$i32$GT$4push17h...E
_ZN5alloc3vec16Vec$LT$f64$GT$4push17h...E
```

### 6.4 链接模式

来源：`rustc_codegen_llvm/src/base.rs:189-200`

| 链接类型 | LLVM 链接 | 使用场景 |
|----------|-----------|----------|
| `External` | `ExternalLinkage` | 导出符号 |
| `AvailableExternally` | `AvailableExternallyLinkage` | 来自其他 crate 的内联函数体 |
| `LinkOnceAny` | `LinkOnceAnyLinkage` | 链接一次（任意） |
| `LinkOnceODR` | `LinkOnceODRLinkage` | 链接一次（ODR）-- 泛型常用 |
| `WeakAny` | `WeakAnyLinkage` | 弱符号 |
| `WeakODR` | `WeakODRLinkage` | 弱 ODR 符号 |
| `Internal` | `InternalLinkage` | 私有符号（如 `static` 项） |
| `ExternalWeak` | `ExternalWeakLinkage` | 弱外部引用 |
| `Common` | `CommonLinkage` | Common 符号 |

### 6.5 可见性

来源：`rustc_codegen_llvm/src/callee.rs:100-141`

| 可见性 | 何时应用 | 来源 |
|--------|----------|------|
| `Default` | 导出函数 | 第 99 行 |
| `Hidden` | 非共享泛型、内部项、compiler-builtins | 第 102-141 行 |
| `Protected` | 不常用 | N/A |

泛型单态化在以下情况获得 `Hidden` 可见性：
- 跨 crate 不共享泛型时（第 106-109 行）
- 本地定义但不可达时（第 119 行）
- 本地实例化但不重新导出时（第 126-128 行）

---

## 7. 关键 IR 模式（静态分析用）

### 7.1 生命周期标记

来源：`rustc_codegen_llvm/src/builder.rs:1369-1375`

| LLVM IR | Rust 含义 |
|---------|-----------|
| `@llvm.lifetime.start.p0(size, ptr)` | 局部变量生命周期开始 |
| `@llvm.lifetime.end.p0(size, ptr)` | 局部变量生命周期结束 |

### 7.2 类型元数据

来源：`rustc_codegen_llvm/src/intrinsic.rs:945-960`

| LLVM IR | Rust 含义 |
|---------|-----------|
| `@llvm.type.checked.load(vtable, offset, typeid)` | 带类型检查的 VTable 调用 |
| 全局变量上的 `!type` 元数据 | CFI/KCFI 的类型标识 |

### 7.3 入口包装

来源：`rustc_codegen_llvm/src/base.rs:123-128`

main 函数获得一个入口包装，它：
1. 调用 `lang_start`（对于 std 二进制文件）或直接调用用户的 `main`
2. 应用 sanitizer 属性

### 7.4 `llvm.used` 和 `llvm.compiler.used`

来源：`rustc_codegen_llvm/src/base.rs:149-159`

- `@llvm.used = appending global [...]` -- 防止链接器剥离符号
- `@llvm.compiler.used = appending global [...]` -- 防止 LLVM 优化器移除符号

两者都包含覆盖率映射、Objective-C 模块信息和其他编译器生成的数据。

---

## 8. 静态分析关键要点

### 用户代码（分析这些）：
- 匹配 `_R<encoded>`（v0 修饰）或 `_ZN<encoded>`（legacy 修饰）的函数
- 带有 `#[no_mangle]` 名称的函数（无前缀）
- 带有 `#[export_name = "..."]` 名称的函数
- 具有用户定义名称的静态变量

### 编译器运行时（过滤/跳过这些）：
- `__rust_alloc`、`__rust_dealloc`、`__rust_realloc`、`__rust_alloc_zeroed`（分配器）
- `__rust_no_alloc_shim_is_unstable_v2`（分配器守卫）
- `__rust_try`（catch_unwind 辅助函数）
- `__rust_panic_type_info`（MSVC panic 类型信息）
- `rust_eh_personality` / `__CxxFrameHandler3` / `__gxx_wasm_personality_v0`（EH 人格函数）
- `core::panicking::*` 函数（panic 处理器）
- LLVM 内建函数（`@llvm.*`）
- Drop glue 函数（`drop_in_place::<T>`）
- Shim 符号（legacy 修饰中包含 `{{...}}`，或 v0 中以 `S` 为前缀）

### FFI 边界（分类为跨语言）：
- `extern "C"` 函数声明 -- 与 `extern "Rust"` 使用相同的 LLVM 调用约定，但 ABI 规则不同
- `extern { }` 块中的函数
- `#[repr(C)]` 类型 -- 保证 C 兼容布局
- `#[repr(transparent)]` 类型 -- 透明包装，与内部类型相同 ABI
- 外部函数导入（`dllimport`、`wasm_import_module`）

### 内存安全关注点：
- `@llvm.memcpy` / `@llvm.memmove` / `@llvm.memset` -- 原始内存操作
- `volatile load` / `volatile store` -- 易失性内存访问
- `load atomic` / `store atomic` / `cmpxchg` / `atomicrmw` / `fence` -- 原子操作
- `unreachable` -- 表示检测到 UB
- `@llvm.assume` -- 可能掩盖 UB 的优化提示
- `@llvm.trap` -- 立即中止
- 分配器返回值前的空值检查

### 控制流指示：
- `invoke` + `landingpad` / `catchswitch` -- 异常处理
- `resume` -- 重新抛出异常
- `select` -- 条件值选择
- `switch` / `br` -- 控制流分支
