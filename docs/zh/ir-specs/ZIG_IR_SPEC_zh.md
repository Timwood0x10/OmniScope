# Zig LLVM IR 规范：编译器保留符号 vs 用户定义符号

**源码**: `~/code/zigcode/zig/src/` (dev 分支)
**日期**: 2026-05-22
**目的**: 为静态分析工具（如 OmniScope）区分编译器保留的 IR 模式与用户定义的符号

---

## 1. 符号命名规则

### 1.1 用户定义符号

Zig 的 LLVM 后端基于每个导航（Nav）的**完全限定名（FQN）**生成符号名。FQN 通过遍历命名空间层次结构构建。

| 模式 | 示例 IR 符号 | 源码证据 |
|------|-------------|----------|
| 内部函数（默认） | `module.funcName` | `src/codegen/llvm.zig:2709` — 非 extern 使用 `nav.fqn` |
| 内部全局变量 | `module.varName` | `src/codegen/llvm.zig:3016` — 内部链接使用 `nav.fqn` |
| 导出函数（`@export`） | `myFunc`（用户选择的名称） | `src/codegen/llvm.zig:1690` — `first_export.opts.name` |
| 导出变量 | `myGlobal`（用户选择的名称） | `src/codegen/llvm.zig:1654` — 重命名为导出名 |
| 匿名函数（`__anon_N`） | `module.parentFn__anon_3` | `src/InternPool.zig:9815-9820` — 编译期生成的名称 |

**关键命名区分**（`src/codegen/llvm.zig:2703-2709`）：
- **外部符号**使用 `nav.name`（非限定名称）
- **内部符号**使用 `nav.fqn`（包含命名空间路径的完全限定名称）

```
// 内部：使用 FQN → "mymodule.myfunction"
// 外部：使用 name → "write"（仅非限定名称）
```

### 1.2 编译器保留符号

| 前缀/模式 | 示例 | 源码证据 |
|-----------|------|----------|
| `__zig_lt_errors_len` | 错误集长度比较 | `src/codegen/llvm.zig:12925` — 常量函数名 |
| `__zig_probe_stack` | 栈探测函数 | `src/codegen/llvm.zig:1229` — `probe-stack` 属性值 |
| `__zig_tag_name_<Type>` | 枚举标签名查找 | `src/codegen/llvm.zig:4476` — `"__zig_tag_name_{f}"` 格式 |
| `__zig_is_named_enum_value_<Type>` | 命名枚举值检查 | `src/codegen/llvm.zig:10409` — `"__zig_is_named_enum_value_{f}"` 格式 |
| `__zig_err_name_table` | 错误名称表全局变量 | `src/codegen/llvm.zig:11266` — 错误名称表变量 |
| `__sancov_gen_.<N>` | 消毒器覆盖率计数器 | `src/codegen/llvm.zig:1483` — 模糊测试覆盖率 |
| `__float<int><float>i<f>` | 整数转浮点 compiler-rt 调用 | `src/codegen/llvm.zig:6676` — 如 `__floatuntisf` |
| `__fix<sign><float>f<int>i` | 浮点转整数 compiler-rt 调用 | `src/codegen/llvm.zig:6747` — 如 `__fixsfsi` |
| `__<op><float>f2` | 浮点比较 compiler-rt | `src/codegen/llvm.zig:8769` — 如 `__gesf2` |
| `__trunc<f1>f<f2>f2` | 浮点截断 | `src/codegen/llvm.zig:9361` — 如 `__truncdfhf2` |
| `__extend<f1>f<f2>f2` | 浮点扩展 | `src/codegen/llvm.zig:9396` — 如 `__extendhfsf2` |
| `__add<f>f3` | 软浮点加法 | `src/codegen/llvm.zig:10840` — 向量归约回退 |
| `__mul<f>f3` | 软浮点乘法 | `src/codegen/llvm.zig:10843` — 向量归约回退 |

### 1.3 名称修饰约定

Zig **不使用**传统的 C++ 风格名称修饰。取而代之的是：

1. **FQN 构建**（`src/InternPool.zig:9815-9820`）：匿名函数在父函数的 FQN 后附加 `__anon_N` 后缀。
2. **外部名称原样保留**：声明为 `extern` 的符号使用非限定名称（`src/codegen/llvm.zig:2709`）。
3. **`@export` 重命名**：导出的符号名完全替换 FQN（`src/codegen/llvm.zig:1690-1706`）。
4. **多个导出创建别名**：第一个导出名成为主名称；后续导出成为 LLVM 别名（`src/codegen/llvm.zig:1734`）。

### 1.4 @export 和 @extern 内建函数

**`@export` 内建函数**（`src/Zcu.zig:691-709`）：
```zig
// @export(&myFunc, .{ .name = "exported_name", .linkage = .strong, .visibility = .default });
```
- 选项：`name`（NullTerminatedString）、`linkage`（strong/weak/link_once）、`section`、`visibility`（default/hidden/protected）
- 在 `lib/std/start.zig:37-95` 中广泛用于入口点符号（`main`、`_start`、`wWinMainCRTStartup` 等）

**`@extern` 内建函数**（`src/InternPool.zig:2258-2283`）：
```zig
// @extern(*anyopaque, .{ .name = "foo" })  →  external global i8
// extern "c" fn write(...)  →  lib_name = "c"
```
- Extern 键存储：`name`、`ty`、`lib_name`、`linkage`、`visibility`、`is_threadlocal`、`is_dll_import`、`relocation`、`is_const`、`alignment`、`addrspace`
- 来源枚举：`builtin` vs `syntax`（`src/InternPool.zig:5998`）

---

## 2. 编译器内建函数 / 内联函数

### 2.1 Zig 使用的 LLVM 内联函数

这些是 Zig 代码生成通过 `callIntrinsic` 直接发出的 LLVM 内联函数。来源：`lib/std/zig/llvm/Builder.zig:2612-2784` 和 `src/codegen/llvm.zig`。

#### 带溢出的算术运算（安全检查）

| Zig AIR 操作 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `.add_safe` | `@llvm.sadd.with.overflow.*` / `@llvm.uadd.with.overflow.*` | `src/codegen/llvm.zig:4879` |
| `.sub_safe` | `@llvm.ssub.with.overflow.*` / `@llvm.usub.with.overflow.*` | `src/codegen/llvm.zig:4880` |
| `.mul_safe` | `@llvm.smul.with.overflow.*` / `@llvm.umul.with.overflow.*` | `src/codegen/llvm.zig:4881` |
| `.add_with_overflow` | `@llvm.sadd.with.overflow.*` / `@llvm.uadd.with.overflow.*` | `src/codegen/llvm.zig:4907` |
| `.sub_with_overflow` | `@llvm.ssub.with.overflow.*` / `@llvm.usub.with.overflow.*` | `src/codegen/llvm.zig:4908` |
| `.mul_with_overflow` | `@llvm.smul.with.overflow.*` / `@llvm.umul.with.overflow.*` | `src/codegen/llvm.zig:4909` |
| `.shl_with_overflow` | 自定义溢出检查 | `src/codegen/llvm.zig:4910` |

#### 饱和算术

| Zig AIR 操作 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `.add_sat`（有符号） | `@llvm.sadd.sat.*` | `src/codegen/llvm.zig:8328` |
| `.add_sat`（无符号） | `@llvm.uadd.sat.*` | `src/codegen/llvm.zig:8328` |
| `.shl_sat`（有符号） | `@llvm.sshl.sat.*` | `Builder.zig:2691` |
| `.shl_sat`（无符号） | `@llvm.ushl.sat.*` | `Builder.zig:2692` |

#### 位操作

| Zig AIR 操作 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `.clz` | `@llvm.ctlz.*` | `src/codegen/llvm.zig:10270` |
| `.ctz` | `@llvm.cttz.*` | `src/codegen/llvm.zig:10270` |
| `.popcount` | `@llvm.ctpop.*` | `src/codegen/llvm.zig:10289` |
| `.byte_swap` | `@llvm.bswap.*` | `src/codegen/llvm.zig:10339` |
| `.bit_reverse` | `@llvm.bitreverse.*` | `src/codegen/llvm.zig:10289` |

#### 数学内建函数（浮点）

| Zig AIR 操作 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
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

**注意**：当 `disable_intrinsics` 为 true 时（compiler-rt 函数、`no_builtin` 模块选项），数学运算回退到 libc/compiler-rt 调用而非 LLVM 内联函数（`src/codegen/llvm.zig:8854`）。

#### 内存操作

| Zig AIR 操作 | LLVM 内联函数 / 指令 | 源码证据 |
|-------------|---------------------|----------|
| `.memset` | `@llvm.memset.*`（通过 `callMemSet`） | `src/codegen/llvm.zig:10009-10066` |
| `.memcpy` | `@llvm.memcpy.*`（通过 `callMemCpy`） | `src/codegen/llvm.zig:10147-10174` |
| `.memmove` | `@llvm.memmove.*`（通过 `callMemMove`） | `src/codegen/llvm.zig:10176-10200` |

#### 控制流 / 调试

| Zig 内建函数 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `@trap` | `@llvm.trap` | `src/codegen/llvm.zig:9777` |
| `@breakpoint` | `@llvm.debugtrap` | `src/codegen/llvm.zig:9783` |
| `@returnAddress()` | `@llvm.returnaddress` | `src/codegen/llvm.zig:9796` |
| `@frameAddress()` | `@llvm.frameaddress` | `src/codegen/llvm.zig:9804` |
| `@vaStart` | `@llvm.va_start` | `src/codegen/llvm.zig:5753` |
| `@vaEnd` | `@llvm.va_end` | `src/codegen/llvm.zig:5739` |
| `@vaCopy` | `@llvm.va_copy` | `src/codegen/llvm.zig:5728` |
| 分支提示 | `@llvm.assume`（冷路径） | `src/codegen/llvm.zig:9282,9302` |

#### 向量操作

| Zig AIR 操作 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `@splat` | `insertelement` 链 | `src/codegen/llvm.zig:10893-10899` |
| 向量归约（add/and/or 等） | `@llvm.vector.reduce.*` | `src/codegen/llvm.zig:9272,9282` |
| `@shuffle` | `shufflevector` | LLVM 指令 |

#### WebAssembly 特定

| Zig 内建函数 | LLVM 内联函数 | 源码证据 |
|-------------|---------------|----------|
| `@wasmMemorySize` | `@llvm.wasm.memory.size` | `src/codegen/llvm.zig:8144` |
| `@wasmMemoryGrow` | `@llvm.wasm.memory.grow` | `src/codegen/llvm.zig:8155` |

---

## 3. FFI 模式（extern "C" / @extern）

### 3.1 extern 函数声明

Zig 的 FFI 机制在函数声明上使用 `extern "c"`（或其他库名）。

**extern 函数在 LLVM IR 中的表现**（`src/codegen/llvm.zig:2703-2732`）：
- **名称**：使用 `nav.name`（非限定、原样）而非 `nav.fqn`
- **链接**：外部（非内部）——不设置 `.internal` 链接
- **无 `unnamed_addr`**：与内部函数不同，extern 函数不获得 `unnamed_addr`

```zig
// Zig 源码：
extern "c" fn write(fd: i32, buf: [*]const u8, count: usize) usize;

// LLVM IR：
declare i64 @write(i32, ptr, i64)
```

### 3.2 @extern 内建函数用于全局符号

```zig
// Zig 源码：
const stderr = @extern(*FILE, .{ .name = "stderr" });

// LLVM IR：
@stderr = external global ptr
```

来源：`src/codegen/llvm.zig:3007` — extern 全局变量获得 `strong`/`weak` 链接，而非 `internal`。

### 3.3 库名和链接

`Extern` 中的 `lib_name` 字段（`src/InternPool.zig:2264-2267`）控制库关联：
- `extern "c" fn ...` → `lib_name = "c"`（链接 libc）
- `extern "mylib" fn ...` → `lib_name = "mylib"`（链接自定义库）
- 对于 Wasm 目标，`lib_name` 成为 `wasm-import-module` 属性（`src/codegen/llvm.zig:2727-2730`）

### 3.4 C ABI 约定

Zig 为 extern 函数遵守 C ABI。调用约定通过 `toLlvmCallConv` 解析（`src/codegen/llvm.zig:11875-11983`）：
- 使用 `extern "c"` 的函数获得平台的 C 调用约定（LLVM 中的 `.ccc`）
- `cCallingConvention()` 函数返回目标平台的默认 C 调用约定（`src/codegen/llvm.zig:11900`）

### 3.5 DLL 导入/导出

extern 函数可以标记为 DLL 导入（`src/codegen/llvm.zig:3041`）：
- `is_dll_import` → `.dllimport` 存储类
- 导出函数可获得 `.dllexport`（`src/codegen/llvm.zig:1711`）

---

## 4. 内存 / 分配器模式

### 4.1 Zig 分配器接口

Zig 的分配器是一个**类型擦除接口**，定义在 `lib/std/mem/Allocator.zig:1-80`：

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

**在 LLVM IR 中**，分配器调用表现为**通过 vtable 函数指针的间接调用**，而非直接调用命名的运行时函数。这与 Go/TinyGo 有根本区别。

### 4.2 标准库分配器

| 分配器 | 源文件 | 描述 |
|--------|--------|------|
| `PageAllocator` | `lib/std/heap/PageAllocator.zig` | 操作系统页面级分配（mmap/VirtualAlloc） |
| `FixedBufferAllocator` | `lib/std/heap/FixedBufferAllocator.zig` | 栈/固定缓冲区分配 |
| `ArenaAllocator` | `lib/std/heap/arena_allocator.zig` | 碰撞分配器，批量释放 |
| `GeneralPurposeAllocator` | `lib/std/heap/GeneralPurposeAllocator.zig` | 调试安全的通用分配器 |
| `SmpAllocator` | `lib/std/heap/SmpAllocator.zig` | 可扩展的多生产者分配器 |
| `ThreadSafeAllocator` | `lib/std/heap/ThreadSafeAllocator.zig` | 互斥锁包装的分配器 |
| `WasmAllocator` | `lib/std/heap/WasmAllocator.zig` | WASM 特定分配器 |
| `sbrk_allocator` | `lib/std/heap/sbrk_allocator.zig` | 基于 sbrk 的分配器（独立环境） |
| `memory_pool` | `lib/std/heap/memory_pool.zig` | 固定大小对象池 |

### 4.3 LLVM IR 特征

- **无 `malloc`/`free` 调用**：Zig 默认不使用 libc 的 `malloc`/`free`。分配通过 Zig 分配器接口进行。
- **平台调用**：`PageAllocator` 直接调用操作系统原语（如 `mmap`、`NtAllocateVirtualMemory`），表现为 extern C 调用。
- **编译期分配器**：编译期求值的代码使用 `@import("std").heap` 分配器——这些不会出现在最终 IR 中。

---

## 5. 运行时函数 / 安全检查

### 5.1 Panic 函数

Zig 的 panic 函数定义在 `lib/std/debug.zig` 中，通过 `BuiltinDecl` 在 `src/Zcu.zig:438-464` 中引用。编译器通过 `buildSimplePanic`（`src/codegen/llvm.zig:5541-5563`）生成对这些函数的调用。

#### 简单 Panic（编译器直接生成的调用）

这些是 `SimplePanicId` 枚举值（`src/Zcu.zig:599-645`）：

| SimplePanicId | BuiltinDecl 路径 | Panic 函数 | 源码证据 |
|--------------|-------------------|------------|----------|
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

#### 参数化 Panic（Sema 生成的调用）

这些也在 `BuiltinDecl` 中（`src/Zcu.zig:439-446`），但接受参数：

| BuiltinDecl 路径 | 签名 | 来源 |
|-------------------|------|------|
| `panic.call` | `(msg: []const u8, ra: ?usize) noreturn` | `Zcu.zig:439`, `debug.zig:33` |
| `panic.sentinelMismatch` | `(expected, found) noreturn` | `Zcu.zig:440`, `debug.zig:34` |
| `panic.unwrapError` | `(err: anyerror) noreturn` | `Zcu.zig:441`, `debug.zig:40` |
| `panic.outOfBounds` | `(index: usize, len: usize) noreturn` | `Zcu.zig:442`, `debug.zig:44` |
| `panic.startGreaterThanEnd` | `(start: usize, end: usize) noreturn` | `Zcu.zig:443`, `debug.zig:48` |
| `panic.inactiveUnionField` | `(active, accessed) noreturn` | `Zcu.zig:444`, `debug.zig:52` |
| `panic.sliceCastLenRemainder` | `(src_len: usize) noreturn` | `Zcu.zig:445`, `debug.zig:58` |

### 5.2 安全检查 IR 模式

安全检查在 `safety` 为 true 时生成（Debug/ReleaseSafe 模式）：

1. **整数溢出**（`src/codegen/llvm.zig:8260-8304`）：
   - 使用 `@llvm.sadd.with.overflow` / `@llvm.uadd.with.overflow` 等
   - 检查溢出位，分支到 `OverflowFail` 块
   - `OverflowFail` 块调用 `buildSimplePanic(.integer_overflow)`

2. **整数转换边界**（`src/codegen/llvm.zig:9224-9304`）：
   - 用 `icmp` 检查最小/最大边界
   - 分支到 `IntMinFail`/`IntMaxFail` 块
   - 调用 `buildSimplePanic(.integer_out_of_bounds)` 或 `.invalid_enum_value`

3. **空值解包** — `is_non_null` 检查后跟 panic 分支
4. **错误解包** — `is_err` 检查后跟 panic 分支
5. **边界检查** — 与 slice/数组长度的 `icmp`，后跟 `panic.outOfBounds`

### 5.3 栈保护

| 特性 | 属性 | 源码证据 |
|------|------|----------|
| 栈保护器 | `sspstrong` + `stack-protector-buffer-size` | `src/codegen/llvm.zig:1217-1223` |
| 栈探测 | `probe-stack = "__zig_probe_stack"` | `src/codegen/llvm.zig:1226-1230` |
| 禁用内建函数（compiler-rt） | `no-builtins` 属性 | `src/codegen/llvm.zig:1209-1212` |

---

## 6. 变换 / 优化遍

### 6.1 AIR 到 LLVM IR 的降低

Zig 使用自己的中间表示称为 **AIR**（抽象 IR），定义在 `src/Air.zig`。`src/codegen/llvm.zig` 中的 LLVM 后端将 AIR 指令降低为 LLVM IR。

**关键 AIR 指令及其 LLVM IR 降低**（`src/codegen/llvm.zig:4868-5102`）：

| AIR 指令 | LLVM IR 模式 | 行号 |
|---------|-------------|------|
| `.add` / `.sub` / `.mul` | `add nsw`/`nuw`, `fadd`/`fsub`/`fmul` | 8257, 8344, 8384 |
| `.add_safe` / `.sub_safe` / `.mul_safe` | 溢出内联函数 + 分支 + panic | 4879-4881 |
| `.div_float` | `fdiv` 或 `@llvm.*` 内联函数 | 4883 |
| `.alloc` | `alloca` | 4963 |
| `.load` | `load` | 4979 |
| `.store` | `store` | 5005 |
| `.memset` / `.memcpy` / `.memmove` | `@llvm.memset.*` / `@llvm.memcpy.*` / `@llvm.memmove.*` | 5001-5004 |
| `.slice` | `{ptr, len}` 聚合 | 8237-8245 |
| `.trap` | `@llvm.trap` + `unreachable` | 9775-9778 |
| `.breakpoint` | `@llvm.debugtrap` | 9781-9784 |
| `.ret` | `ret` | 5565-5615 |
| `.call` | `call`（带调用约定处理） | 5237-5490 |
| `.try` / `.try_ptr` | 错误联合解包 + 分支 | 4970-4973 |

### 6.2 编译期对 IR 的影响

- **编译期求值的值**被折叠为 IR 中的常量——不生成运行时代码
- **泛型函数实例化**：泛型函数的每个具体实例化获得自己的 LLVM 函数，具有唯一的 FQN（`src/InternPool.zig:9815-9820`）
- **编译期 `@export`**：编译期生成的导出通过 `updateExports` 处理（`src/codegen/llvm.zig:1592-1638`）
- **运行时无编译期代码**：编译期分配器调用、字符串操作等在 IR 生成前完全解析

### 6.3 Debug 与 Release IR 差异

| 特性 | Debug | ReleaseSafe | ReleaseFast/ReleaseSmall |
|------|-------|-------------|--------------------------|
| 安全检查 | 是 | 是 | 否 |
| `no-builtins` 属性 | 否 | 否 | 取决于 `no_builtin` |
| 栈保护器 | 可配置 | 可配置 | 可配置 |
| 帧指针 | 可配置 | 可配置 | 通常省略 |
| 调试信息 | 完整 | 部分 | 通常剥离 |
| `@branchHint` | 遵循 | 遵循 | 遵循 |
| 内联函数 | 允许 | 允许 | 允许（快速数学变体） |
| `disable_intrinsics` | 按函数 | 按函数 | 按函数 |

**`disable_intrinsics`**（`src/codegen/llvm.zig:1202-1213`）：当为 true 时（compiler-rt 函数、`no_builtin` 模块选项），函数获得 `no-builtins` 属性并使用 libc 调用而非 LLVM 内联函数。这防止编译 `memcpy` 等函数时出现无限递归。

---

## 7. ABI 差异

### 7.1 导出函数 vs 内部函数

| 属性 | 导出函数 | 内部函数 |
|------|----------|----------|
| LLVM 名称 | 导出名（用户选择） | FQN（如 `module.func`） |
| 链接 | `external` / `weak_odr` / `linkonce_odr` | `internal` |
| `unnamed_addr` | `.default`（非 unnamed） | `.unnamed_addr` |
| 可见性 | `.default` / `.hidden` / `.protected` | `.default` |
| 来源 | `src/codegen/llvm.zig:1709-1722` | `src/codegen/llvm.zig:2718-2719` |

### 7.2 调用约定

完整的调用约定映射在 `src/codegen/llvm.zig:11899-11983`：

| Zig 调用约定 | LLVM 调用约定 | 备注 |
|-------------|---------------|------|
| `.auto` | `fastcc` | Zig 函数的默认值 |
| `.naked` | `ccc` + `naked` 属性 | 无序言/结尾 |
| `extern "c"` | `ccc` | C 调用约定 |
| `.x86_64_sysv` | `x86_64_sysvcc` | System V AMD64 ABI |
| `.x86_64_win` | `win64cc` | Windows x64 ABI |
| `.x86_stdcall` | `x86_stdcallcc` | Windows stdcall |
| `.x86_fastcall` | `x86_fastcallcc` | Windows fastcall |
| `.x86_thiscall` | `x86_thiscallcc` | Windows thiscall |
| `.x86_vectorcall` | `x86_vectorcallcc` | 向量调用 |
| `.arm_aapcs` | `arm_aapcscc` | ARM AAPCS |
| `.arm_aapcs_vfp` | `arm_aapcs_vfpcc` | 带 VFP 的 ARM AAPCS |
| `.aarch64_vfabi` | `aarch64_vector_pcs` | AArch64 向量调用约定 |
| `.riscv64_lp64_v` | `riscv_vectorcallcc` | RISC-V 向量 |
| `.avr_signal` | `avr_signalcc` | AVR 信号处理 |
| `.avr_interrupt` | `avr_intrcc` | AVR 中断处理 |
| `.m68k_interrupt` | `m68k_intrcc` | M68K 中断处理 |
| `.amdgcn_kernel` | `amdgpu_kernel` | AMD GPU 内核 |
| `.nvptx_kernel` | `ptx_kernel` | NVIDIA PTX 内核 |

### 7.3 参数传递

**SRet（结构体返回）**（`src/codegen/llvm.zig:2736-2744`）：
- 大型返回值通过不可见的第一个参数（sret 指针）传递
- Sret 参数获得 `nonnull`、`noalias`、`sret` 属性

**ByRef 参数传递**（`src/codegen/llvm.zig:4419-4431`）：
- 大型参数可能通过引用传递，带有 `nonnull`、`readonly`、`align` 属性
- 可选的 `byval` 属性用于真正的按值语义

**指针属性**（`src/codegen/llvm.zig:4382-4416`）：
- `noalias` — 来自 `fn_info.noalias_bits`
- `nonnull` — 用于非可选、非 allowzero 指针
- `readonly` — 用于 `const` 指针参数
- `align` — 来自指针对齐或子类型对齐

**整数提升**（`src/codegen/llvm.zig:4413-4416`）：
- `signext` 用于小于寄存器大小的有符号整数
- `zeroext` 用于小于寄存器大小的无符号整数

### 7.4 错误返回追踪

当启用 `any_error_tracing` 时（`src/codegen/llvm.zig:2747-2752`）：
- 为错误返回追踪附加一个额外的 `nonnull` 参数
- 仅适用于 `.auto` 调用约定的函数（不适用于 extern "c"）

---

## 8. 静态分析关键要点

### 需要分析的用户代码

- 具有内部 FQN 模式的函数（如 `module.submodule.function`）
- 具有 `@export` 名称的函数（用户选择，IR 中原样出现）
- 具有多个导出的函数（主名称 + 别名）
- 错误联合类型及其解包模式（`.try`、`.try_ptr`）
- Slice 操作（`.slice`、`.slice_elem_val`、`.slice_elem_ptr`）

### 编译器运行时（过滤/跳过）

- `__zig_lt_errors_len` — 错误集比较辅助函数
- `__zig_probe_stack` — 栈探测函数
- `__zig_tag_name_*` — 枚举标签名查找
- `__zig_is_named_enum_value_*` — 枚举值检查
- `__zig_err_name_table` — 错误名称表
- `__sancov_gen_.*` — 消毒器覆盖率
- `__float*`、`__fix*`、`__*f2`、`__trunc*f*f2`、`__extend*f*f2` — compiler-rt 软浮点函数
- LLVM 内联函数（`@llvm.*`）

### FFI 边界（单独分类）

- 具有外部链接的函数（无 `internal` 链接设置）
- 具有 `wasm-import-name` / `wasm-import-module` 属性的函数
- 具有 `.dllimport` 存储类的函数
- 以 C 库函数命名的函数（`write`、`read`、`mmap` 等）

### 内存安全关注指标

- 溢出检查模式（溢出内联函数 + 分支 + panic）
- 边界检查模式（`icmp` + 分支 + `panic.outOfBounds`）
- 空值检查模式（`icmp eq ptr null` + 分支 + `panic.unwrapNull`）
- 错误解包模式（`is_err` 检查 + 分支）
- `@memcpy` 参数别名检查（`panic.memcpyAlias`）
- 哨兵值不匹配检查
- 联合体字段访问检查（`panic.inactiveUnionField`）

### 分配器检测策略

由于 Zig 分配器是基于 vtable 的间接调用：
1. 查找通过函数指针表的间接调用
2. `PageAllocator` 调用将表现为对操作系统原语的调用（`mmap`、`NtAllocateVirtualMemory`、`sbrk`）
3. 除非明确使用 C 分配器，否则没有标准的 `malloc`/`free` 符号名
4. 编译期分配在 IR 中不可见

---

## 9. 完整 LLVM 内联函数参考

来源：`lib/std/zig/llvm/Builder.zig:2612-2784`

### 可变参数处理
- `@llvm.va_start`、`@llvm.va_end`、`@llvm.va_copy`

### 代码生成器
- `@llvm.returnaddress`、`@llvm.addressofreturnaddress`、`@llvm.sponentry`
- `@llvm.frameaddress`、`@llvm.prefetch`、`@llvm.thread.pointer`

### 标准 C/C++ 库
- `@llvm.abs`、`@llvm.smax`、`@llvm.smin`、`@llvm.umax`、`@llvm.umin`
- `@llvm.memcpy`、`@llvm.memcpy.inline`、`@llvm.memmove`、`@llvm.memset`、`@llvm.memset.inline`
- `@llvm.sqrt`、`@llvm.powi`、`@llvm.sin`、`@llvm.cos`、`@llvm.pow`
- `@llvm.exp`、`@llvm.exp10`、`@llvm.exp2`、`@llvm.ldexp`、`@llvm.frexp`
- `@llvm.log`、`@llvm.log10`、`@llvm.log2`、`@llvm.fma`、`@llvm.fabs`
- `@llvm.minnum`、`@llvm.maxnum`、`@llvm.minimum`、`@llvm.maximum`、`@llvm.copysign`
- `@llvm.floor`、`@llvm.ceil`、`@llvm.trunc`、`@llvm.rint`、`@llvm.nearbyint`
- `@llvm.round`、`@llvm.roundeven`、`@llvm.lround`、`@llvm.llround`、`@llvm.lrint`、`@llvm.llrint`

### 位操作
- `@llvm.bitreverse`、`@llvm.bswap`、`@llvm.ctpop`、`@llvm.ctlz`、`@llvm.cttz`
- `@llvm.fshl`、`@llvm.fshr`

### 带溢出的算术
- `@llvm.sadd.with.overflow`、`@llvm.uadd.with.overflow`
- `@llvm.ssub.with.overflow`、`@llvm.usub.with.overflow`
- `@llvm.smul.with.overflow`、`@llvm.umul.with.overflow`

### 饱和算术
- `@llvm.sadd.sat`、`@llvm.uadd.sat`、`@llvm.ssub.sat`、`@llvm.usub.sat`
- `@llvm.sshl.sat`、`@llvm.ushl.sat`

### 向量归约
- `@llvm.vector.reduce.add`、`@llvm.vector.reduce.fadd`
- `@llvm.vector.reduce.mul`、`@llvm.vector.reduce.fmul`
- `@llvm.vector.reduce.and`、`@llvm.vector.reduce.or`、`@llvm.vector.reduce.xor`
- `@llvm.vector.reduce.smax`、`@llvm.vector.reduce.smin`
- `@llvm.vector.reduce.umax`、`@llvm.vector.reduce.umin`
- `@llvm.vector.reduce.fmax`、`@llvm.vector.reduce.fmin`
- `@llvm.vector.reduce.fmaximum`、`@llvm.vector.reduce.fminimum`
- `@llvm.vector.insert`、`@llvm.vector.extract`

### 通用
- `@llvm.trap`、`@llvm.debugtrap`、`@llvm.ubsantrap`
- `@llvm.stackprotector`、`@llvm.stackguard`
- `@llvm.objectsize`、`@llvm.expect`、`@llvm.expect.with.probability`
- `@llvm.assume`、`@llvm.ssa.copy`
- `@llvm.is.fpclass`、`@llvm.ptrmask`
- `@llvm.vscale`、`@llvm.donothing`

### 平台特定
- AMDGPU：`@llvm.amdgcn.workitem.id.*`、`@llvm.amdgcn.workgroup.id.*`、`@llvm.amdgcn.dispatch.ptr`
- NVPTX：`@llvm.nvvm.read.ptx.sreg.*`
- WebAssembly：`@llvm.wasm.memory.size`、`@llvm.wasm.memory.grow`
