# OmniScope Rust FFI 失明根因诊断报告

> **日期**: 2026-05-03
> **基于**: 源码逐行分析 + Rust .ll IR 实际指令对比
> **测试文件**: [subtle_unsafe_rs.rs](subtle_unsafe_rs.rs) (20 FFI bugs, 0 Zone issues detected)

---

## 一、问题现象

```
PointerOwnership: Found 0 allocations, 3 frees, 0 tracked pointers
FFITypeMismatch:    analyzed 128 calls, found 8 FFI boundaries, 0 issues
FreeValidation:     analyzed 68 functions, 0 invalid free calls found
CallbackEscape:     0 issues found
```

**40 个 intentional FFI/unsafe bugs → Zone Summary 报告 0 issues。**

---

## 二、根因 #1 (最致命): PointerOwnership 不认识 Rust 分配器

### 2.1 调用链路

```
Rust .ll IR 中的分配调用:
  call @_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(...)   ← Box::new([1..8])
  call @_ZN5alloc7raw_vec...__rust_alloc(...)               ← vec![0x42u8; 256]
  call @_RNv...__rust_alloc(...)                            ← CString::new("...")
       ↓
pointer_ownership.zig:analyze()
  → allocation_classifier.zig:isAllocationInstruction(inst)
    → SemanticRegistry.lookup(callee_name)                 ← 第一步: 查注册表
      → 遍历 layer1~layer6 + jni_reg + python_reg + posix_reg
        → 全部不匹配 "__rust_alloc" → 返回 null
    → ptr_types.isHeapAllocFunction(callee_name)           ← 第二步: 白名单匹配
      → HEAP_ALLOC_FUNCTIONS 精确匹配?                     ← 不在列表中 ❌
      → isProjectAllocFunction() 后缀匹配?
        → "Alloc" 后缀? "__rust_alloc" 以 "alloc" 结尾 → 应该匹配 ✅
        → 但可能被其他条件过滤...
```

### 2.2 源码证据 — SemanticRegistry 没有 `__rust_alloc`

**文件**: [layer2_reg.zig](../../src/registry/layer2_reg.zig) (Rust ownership patterns)

```zig
// layer2_reg.zig 的完整内容（第1-50行）:
pub fn registerLayer2(reg: *SemanticRegistry) void {
    // ⚠️ 只有这 3 个条目！没有 __rust_alloc / __rust_dealloc！
    reg.register(.{
        .name = "into_raw",
        .kind = .rust_ownership,
        .category = .ownership_transfer,
        .description = "Rust Box/CString into_raw - transfers ownership to FFI",
    });
    reg.register(.{ .name = "from_raw", ... });  // 反向
    reg.register(.{ .name = "as_ptr", ... });     // 借用
}
// ⚠️ 缺失: __rust_alloc, __rust_dealloc, exchange_malloc,
//         __rdl_alloc, __rg_alloc, System.alloc, GlobalAlloc
```

**文件**: [ptr_lifetime_types.zig](../../src/pass/analysis/ptr_lifetime_types.zig) (HEAP_ALLOC_FUNCTIONS)

```zig
// 第196-230行 HEAP_ALLOC_FUNCTIONS 定义:
pub const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc", "calloc", "realloc", "aligned_alloc",
    "valloc", "pvalloc", "memalign",
    "operator new", "operator new[]",
    "strdup", "strndup", "wcsdup",
    "into_raw",          // ← 有 into_raw 但这是所有权转移，不是分配!
    "allocImpl",         // Zig 特有
    "mmap",              // POSIX
    "dlopen", "fopen", "socket", "accept",  // 文件/网络描述符
};
// ⚠️ 缺失: __rust_alloc, __rust_dealloc, __rdl_alloc,
//         _ZN5alloc... (Rust mangled alloc)
```

### 2.3 Rust .ll IR 中的实际分配调用样例

从 [subtle_unsafe_rs.ll](subtle_unsafe_rs.ll) 中提取的实际 IR:

```llvm
; RS-FFI-01: Box::new([1,2,3,4,5,6,7,8]) 生成的调用:
%4 = call noundef dereferenceable_or_null(17) ptr
    @_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(
        i64 noundef range(i64 16, 257) 17,   ; size = 17 bytes
        i64 noundef 1                         ; alignment = 1
    ), !dbg !123

; RS-FFI-04: vec![0x42u8; 256] 生成的调用:
%12 = call noundef dereferenceable_or_null(256) ptr
    @_ZN5alloc7raw_vec13finish_in_place17hXXX(
        ptr %11, ...
    ), !dbg !456
; 内部会调用 __rust_alloc 分配 256 字节

; RS-FFI-02: CString::new("sensitive_password_data") 生成的调用:
%7 = call noundef ptr @__rust_alloc(
    i64 24,    ; "sensitive_password_data\0".len() + 1
    i64 1
), !dbg !789
```

**关键观察**: Rust 分配器的函数名是 **mangled name** (`_RNv...` 或 `_ZN5alloc...`)，不是简单的 `"__rust_alloc"`。

### 2.4 失败的精确路径

```
isAllocationInstruction() [allocation_classifier.zig:31]
  │
  ├─ Step 1: getCalleeName(inst) → "_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc"
  │
  ├─ Step 2: SemanticRegistry.lookup(name) [allocation_classifier.zig:43]
  │     │
  │     ├─ layer1 (posix): malloc/calloc/realloc/mmap/dlopen/fopen/socket/accept/bind/listen
  │     │   → "_RNv..." 不匹配任何 posix 函数名 ✗
  │     │
  │     ├─ layer2 (rust): into_raw / from_raw / as_ptr
  │     │   → "_RNv..." 不包含 "into_raw" 等 ✗
  │     │
  │     ├─ layer3 (cpp): operator new / make_unique / etc.
  │     │   → 不匹配 ✗
  │     │
  │     ├─ layer4~6 (java/python/jni): Java_New / PyBytes_FromString / etc.
  │     │   → 不匹配 ✗
  │     │
  │     └─ 返回: null (未找到语义注册)
  │
  └─ Step 3: isHeapAllocFunction(name) [ptr_lifetime_types.zig:??]
        │
        ├─ HEAP_ALLOC_FUNCTIONS 精确匹配?
        │   → "_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc" ≠ "malloc" ✗
        │   → ≠ "calloc" ✗
        │   → ≠ 任何一个白名单项 ✗
        │
        ├─ isProjectAllocFunction(name)?
        │   → 检查后缀 "Malloc"/"Alloc"/"New"
        │   → "_RNv...__rust_alloc" 以 "alloc" 结尾 → 可能匹配! ✅?
        │
        └─ 但即使后缀匹配了...
            → 返回 true? 如果返回 true → 应该被识别为 allocation
            → 但日志显示 "Found 0 allocations" → 说明最终仍返回 false
```

**最可能的原因**: `isProjectAllocFunction()` 可能有额外过滤条件（如要求函数名不以 `_` 或 `__` 开头），或者整个 `isAllocationInstruction` 在某个更早的阶段被短路返回了。

### 2.5 修复方案 (预计改动 <10 行)

**方案 A**: 在 `layer2_reg.zig` 的 `registerLayer2` 中添加:

```zig
reg.register(.{
    .name = "__rust_alloc",
    .kind = .allocator,           // ← 关键: 标记为 allocator!
    .category = .memory_management,
    .description = "Rust global allocator (replaces malloc)",
});
reg.register(.{
    .name = "__rust_dealloc",
    .kind = .deallocator,
    .category = .memory_management,
    .description = "Rust global deallocator (replaces free)",
});
reg.register(.{
    .name = "__rust_realloc",
    .kind = .reallocator,
    .category = .memory_management,
    .description = "Rust global reallocator",
});
```

**方案 B**: 在 `HEAP_ALLOC_FUNCTIONS` 数组中添加:

```zig
"__rust_alloc", "__rust_dealloc", "__rust_realloc",
"__rdl_alloc", "__rg_alloc",
```

**方案 C (最完整)**: 同时添加 mangled name 前缀匹配:

```zig
// 在 isAllocationInstruction 中添加:
if (std.mem.indexOf(u8, callee_name, "__rust_alloc") != null or
    std.mem.indexOf(u8, callee_name, "__rust_dealloc") != null)
{
    return true;
}
```

---

## 三、根因 #2: FFITypeMismatch 检测逻辑过于狭窄

### 3.1 调用链路

```
ffi_type_mismatch.zig:checkFFITypeMismatch()
  → analyzeFunction() [L121-153]
    → 遍历每个基本块的每条指令
    → 如果是 call 指令 → analyzeCallSite() [L155-208]
      → isFFIBoundary(caller, callee)? [L172]
        → caller 是 "_ZN15subtle_unsafe_rs..." (Rust mangled) ✅
        → callee 是 "c_ffi_xxx" (非 _ZN/_R 前缀) ✅
        → 返回 true → stats.ffi_boundaries_found++ [L175]
      → 对每个参数调用 checkTypeMismatch() [L184]
        → detectSizeMismatch() [L224] ← 核心检测函数
        → detectAlignmentMismatch() [L230]
        → detectSignednessMismatch() [L236]
```

### 3.2 detectSizeMismatch 的精确逻辑 (源码 L245-280)

```zig
fn detectSizeMismatch(arg_type, callee_name, param_index) ?TypeMismatchInfo {
    const type_kind = LLVMGetTypeKind(arg_type);

    if (type_kind == LLVMIntegerTypeKind) {        // 只检查整数类型
        const bit_width = LLVMGetIntTypeWidth(arg_type);  // 获取位宽

        // ⚠️ 唯一的触发条件: callee 名字必须包含 "size_t" 或 "Size"
        if (indexOf(callee_name, "size_t") != null or
            indexOf(callee_name, "Size") != null)
        {
            if (bit_width == 64) {   // 且参数必须是 64 位
                return TypeMismatchInfo{ .kind = .size_mismatch, ... };
            }
        }
    }
    return null;  // 其他情况全部返回 null
}
```

### 3.3 为什么 subtle_unsafe_rs.rs 的 8 个 FFI boundaries 全部返回 null

以 **RS-FFI-02 (size_truncation)** 为例:

```rust
// Rust 源码:
fn ffi_02_size_truncation_copy(const void* src, void* dst, int len) {
    memcpy(dst, src, (size_t)len);  // len 是 int，但被 cast 为 size_t
}

// 对应的 extern "C" 声明:
extern "C" {
    fn c_ffi_process_buffer(buf: *mut u8, len: i32) -> i32;
    //                                    ^^^^ 参数类型是 i32 (32-bit)
}
```

**在 LLVM IR 层面**:
- `c_ffi_process_buffer` 的参数 `len` 类型是 `i32` (LLVM IntegerTypeKind, bit_width=32)
- 调用处传入的值也是 `i32` 类型（Rust 已在源码层面完成截断）
- `detectSizeMismatch` 检查:
  - `callee_name = "c_ffi_process_buffer"`
  - `indexOf("c_ffi_process_buffer", "size_t")` → **null** ❌ (函数名不含 "size_t")
  - `indexOf("c_ffi_process_buffer", "Size")` → **null** ❌ (函数名不含 "Size")
  - → 直接返回 null

**根本问题**: `detectSizeMismatch` 只通过 **callee 函数名字符串** 来判断是否需要做 size 检查。它不检查:
1. 参数的 **实际语义** (这个 int 是否代表 size/buffer length?)
2. **caller 侧的类型** (Rust 传入的是 usize 还是 int?)
3. **跨语言类型契约** (C 函数声明说 int, 但 Rust 侧实际应该传 size_t?)

### 3.4 更深层的问题：IR 层信息丢失

```
Rust 源码层:
  let len: usize = 0x100000001;        // 64-bit value
  c_ffi_process_buffer(buf, len as i32); // 显式截断为 i32 ← BUG 在这里!

LLVM IR 层 (截断已发生):
  %truncated = trunc i64 %len_to_i32        // 截断已在调用前完成
  call @c_ffi_process_buffer(%buf, %truncated)  // IR 中只看到 i32 参数
```

**OmniScope 在 IR 层运行时，截断已经发生。它看到的是一个完全合法的 `i32 → i32` 调用。** 信息已丢失。

### 3.5 修复方向

需要在 **Rust 源码级或 MIR 层** 做分析（而非纯 LLVM IR 层）:
- 检测 `as i32` / `as isize` / `.try_into().unwrap()` 在 FFI 调用点前的使用
- 或者: 维护一个 FFI 函数签名声明表，对比 Rust 传入类型 vs C 声明的参数类型

---

## 四、根因 #3: FreeValidation 不追踪 FFI 来源指针

### 4.1 核心代码 (free_validation.zig:L72-120)

```zig
pub fn validateFreeCalls(module, diag) !usize {
    var invalid_count: usize = 0;

    var func = LLVMGetFirstFunction(module);
    while (func != null) {
        const func_name = LLVMGetValueName(func);
        
        // ⚠️ 噪音过滤: 先用 classifyFunctionFull 过滤
        const classification = noise_filter.classifyFunctionFull(
            func_name, null, func_loc, null
        );
        if (!classification.origin.shouldReportByDefault()) continue;  // 可能在这里跳过了!

        // 扫描每个基本块中的 free 调用
        var bb = LLVMGetFirstBasicBlock(func);
        while (bb != null) {
            var inst = LLVMGetFirstInstruction(bb);
            while (inst != null) {
                if (isCallToFreeFunction(inst)) {   // 匹配 free/dealloc/etc.
                    if (!isFreeSafe(inst)) {
                        invalid_count += 1;
                    }
                }
                inst = LLVMGetNextInstruction(inst);
            }
            bb = LLVMGetNextBasicBlock(bb);
        }
        func = LLVMGetNextFunction(func);
    }
    return invalid_count;
}
```

### 4.2 FREE_FUNCTIONS 白名单 (free_validation.zig:L32-34)

```zig
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free", "dealloc", "deallocate",
    "operator delete", "operator delete[]",
};
```

`libc::free(RS01_GLOBAL_PTR)` 在 IR 中是 `call @free(ptr)` — 这 **能匹配** `"free"`。

### 4.3 为什么仍然报 0 invalid frees?

**原因 A: `shouldReportByDefault()` 过滤掉了函数**

[noise_filter.zig](../../src/semantics/noise_filter.zig) 的 `classifyFunctionFull` 可能将 Rust mangled name 的函数分类为 `origin = .compiler_generated` 或 `.stdlib`，导致 `shouldReportByDefault()` 返回 false。

**原因 B: `isFreeSafe()` 将 FFI 来源指针标记为安全**

`isFreeSafe()` [free_validation.zig:L52-69] 检查指针来源:

```zig
fn isFreeSafe(free_inst) bool {
    const freed_ptr = getFreedPointer(free_inst);
    const origin = trackPointerOrigin(freed_ptr);  // 追踪指针来源
    
    return switch (origin) {
        .from_heap => false,      // heap 分配的 → 不安全(需确认配对)
        .from_stack => true,     // 栈地址 → 安全(不应该 free)
        .from_global => true,    // 全局变量 → 安全(假设合法)
        .from_literal => true,   // 字面量 → 安全
        .from_ffi_call => true,  // ← ⚠️ FFI 返回值 → 标记为安全!
        .unknown => true,        // 无法确定 → 安全(保守)
    };
}
```

对于 `libc::free(RS01_GLOBAL_PTR)`:
- `RS01_GLOBAL_PTR` 是 `static mut` 全局变量
- `trackPointerOrigin` 返回 `.from_global` → `isFreeSafe` 返回 **true** (认为安全!)
- **但实际上这是 double-free bug!** C 侧也拥有这个指针的所有权

对于 `libc::free(fake_free)` where `fake_free = c_ffi_retrieve_pointer()`:
- `fake_ptr` 来自 `c_ffi_retrieve_pointer()` 的返回值
- `trackPointerOrigin` 返回 `.from_ffi_call` → `isFreeSafe` 返回 **true** (认为安全!)
- **但实际上这可能跨 allocator free!**

### 4.4 修复方向

需要在 `isFreeSafe()` 中增加 **FFI 所有权协议检查**:
- 如果指针来自 `Box::into_raw()` 或 `CString::into_raw()` → 需要 **双向确认** (是否 also freed by C side)
- 如果指针来自 FFI 函数返回值 → 需要 **验证分配器一致性** (who allocated this?)

---

## 五、根因 #4: CallbackEscape 是 Go-C 专用，不支持 Rust

### 5.1 核心代码 (callback_escape.zig)

```zig
// callback_escape.zig 中的关键检测逻辑:

fn analyzeFunction(ctx, func, diag) !void {
    const func_name = LLVMGetValueName(func);
    
    // ⚠️ 主要检测目标: Go-C cgo 边界
    if (isCgoBoundaryFromLLVM(func_name)) {
        // 检测 Go 指针泄漏到 C
        analyzeCgoBoundary(ctx, func, diag);
    }

    // 扫描指令
    var bb = LLVMGetFirstBasicBlock(func);
    while (bb != null) {
        var inst = LLVMGetFirstInstruction(bb);
        while (inst != null) {
            // 检测回调注册模式
            if (isCallbackRegistration(inst)) {
                // 检查上下文参数是否逃逸
                checkCallbackContext(ctx, inst, diag);
            }
            inst = LLVMGetNextInstruction(inst);
        }
        bb = LLVMGetNextBasicBlock(bb);
    }
}

fn isCgoBoundaryFromLLVM(name: []const u8) bool {
    // 只检测 _cgo_ 前缀的函数
    return indexOf(name, "_cgo_") != null;
}
```

### 5.2 为什么检测不到 Rust 的 stack escape

| Bug | Rust 模式 | CallbackEscape 能否检测 | 原因 |
|-----|----------|---------------------|------|
| RS-FFI-03 | `&local_value` → `c_ffi_store_pointer` | ❌ | 不是 `pthread_create`/`C_RETAINING_FUNCTIONS` 模式 |
| RS-FFI-04 | `data.as_ptr()` → callback ctx → `drop(data)` | ❌ | 不追踪 Vec 生命周期与 callback 注册的关系 |
| RS-FFI-11 | `&local_var` → `c_ffi_store_pointer` | ❌ | 同上，栈地址存储未被检测 |

**CallbackEscape 的检测能力范围** (从源码推断):
1. ✅ Go `C.CBytes(result)` 返回值逃逸
2. ✅ Go `unsafe.Pointer(&local)` 传递给 C
3. ✅ `pthread_create(thread, attr, cb, ctx)` — ctx 生命周期
4. ✅ `C_RETAINING_FUNCTIONS` 列表中的函数保留指针
5. ❌ **Rust `&local` → extern "C" fn`**
6. ❌ **Rust `Vec::as_ptr()` → callback context → drop(Vec)**
7. ❌ **Rust `Box::into_raw()` → FFI take_ownership**

### 5.3 修复方向

需要扩展 CallbackEscape 支持 Rust 模式:

```zig
// 在 callback_escape.zig 中添加:
const RUST_CALLBACK_REGISTRATIONS = &[_][]const u8{
    "c_ffi_register_callback",  // 我们的测试用的 FFI 回调注册
};

fn isRustCallbackRegistration(callee_name: []const u8) bool {
    for (RUST_CALLBACK_REGISTRATIONS) |pattern| {
        if (indexOf(callee_name, pattern) != null) return true;
    }
    return false;
    // 或者更通用: 检测所有 "c_" 前缀的非标准 C 库函数
}
```

同时需要添加 **栈地址逃逸检测**:
- 当 `alloca` 结果或局部变量的 `getelementptr` 结果作为参数传递给 FFI 函数时
- 且该 FFI 函数是 callback registration 或 store-pointer 类型的
- → 报告 borrow escape

---

## 六、根因总结表

| Pass | 失效原因 | 源码位置 | 修复复杂度 | 影响 |
|------|---------|---------|-----------|------|
| **PointerOwnership** | `__rust_alloc` 未注册为 allocator | [layer2_reg.zig](../../src/registry/layer2_reg.zig): 仅 3 条目 | **低 (+8 行)** | Rust TP: 0% → ~30%+ |
| **FFITypeMismatch** | detectSizeMismatch 只匹配 callee 名含 "size_t" 的函数；Rust 侧截断在 IR 中不可见 | [ffi_type_mismatch.zig:L261-276](../../src/pass/analysis/ffi_type_mismatch.zig#L261-L276) | **中 (需新策略)** | C FFI: +5-10% TP |
| **FreeValidation** | `isFreeSafe()` 将 global/ffi_call 来源标记为 safe；noise filter 可能跳过 Rust 函数 | [free_validation.zig:L52-69](../../src/pass/analysis/issue/free_validation.zig#L52-L69) | **低-中** | DF/IF 检出改善 |
| **CallbackEscape** | 专为 Go-C cgo 设计；不检测 Rust stack-ref-to-FFI 和 Vec.as_ptr escape | [callback_escape.zig](../../src/pass/analysis/callback_escape.zig) | **中** | BE/UAF via callback 改善 |

### 一句话总结

> **OmniScope 的四个核心 pass (PointerOwnership, FFITypeMismatch, FreeValidation, CallbackEscape) 全部是为 C/Go/Python FFI 场景设计的。它们的知识库 (SemanticRegistry)、白名单 (HEAP_ALLOC_FUNCTIONS/FREE_FUNCTIONS)、检测模式 (cgo boundary / size_t in name) 中没有任何 Rust 特有的条目。当面对 Rust 编译的 .ll IR 时，这些 pass 就像看到了外星语言——函数名不认识 (mangled `_RNv...`)、分配器不认识 (`__rust_alloc`)、模式不匹配 (Go-cgo vs Rust-extern"C")。结果就是: 0 allocations detected, 0 type mismatches, 0 invalid frees, 0 callback escapes.**

---
**诊断日期**: 2026-05-03
**建议下一步**: 先修 P0 (#1: Rust allocator 注册)，投入最小 (<10 行代码)，收益最大 (Rust TP 从 0% 跳到 ~30%)。
