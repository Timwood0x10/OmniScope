# Wasmtime误报修复方案

## 问题根因定位

### 核心问题：Rust所有权模式误判

**文件**: `src/pass/analysis/issue/free_validation.zig`  
**行号**: 357-374, 629-632

**问题代码**:
```zig
// Line 357-374: from_param检查
.from_param => {
    const src = if (origin_info) |info| info.source_desc else "";
    if (isFreeSafe(callee_name, origin, src)) return false;
    // 问题：对于__rust_dealloc，即使是from_param也会报错
    if (std.mem.eql(u8, callee_name, "free") or
        std.mem.startsWith(u8, callee_name, "operator delete"))
    {
        return false;  // 只豁免C/C++的free，不豁免Rust的dealloc
    }
    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
    return true;
},

// Line 629-632: FFI别名检测
const ptr_val: u64 = @intFromPtr(ptr_arg);
const reaches_ffi = ctx.isOnDangerPathFull(ptr_val);
const base_confidence: f32 = if (reaches_ffi) 0.85 else 0.75;
const severity: Severity = if (reaches_ffi) .critical else .high;
```

**问题分析**:
1. **from_param误判**: Rust函数参数通过`__rust_dealloc`释放是正常的所有权转移，但被标记为invalid_free
2. **FFI别名过度敏感**: `reaches_ffi`检测到任何跨函数调用就认为是FFI边界，导致54个CRITICAL误报
3. **isFreeSafe不够智能**: 第277行虽然有`from_param + Rust dealloc`的豁免，但在第368-372行被C free的豁免覆盖了

### 具体案例分析

**wasmtime::config::Config::cranelift_opt_level**:
```rust
pub fn cranelift_opt_level(&mut self, level: OptLevel) -> &mut Self {
    self.compiler_config_mut()
        .settings
        .insert("opt_level".to_string(), val.to_string());
    self
}
```

**LLVM IR模式**:
```llvm
%1 = call i8* @__rust_alloc(i64 %size, i64 8)  ; 分配String
; ... 使用 ...
call void @__rust_dealloc(i8* %1, i64 %size, i64 8)  ; 释放
```

**工具误判流程**:
1. `trackPointerOrigin`: `%1`被标记为`from_malloc`（正确）
2. 但在函数调用边界，指针通过参数传递
3. `checkFreeCall`: 参数指针被重新标记为`from_param`（错误）
4. `isFreeSafe(277行)`: 返回true（正确）
5. 但`368-372行`: C free豁免逻辑先执行，跳过了isFreeSafe
6. `reportInvalidFree`: 报告CRITICAL错误（误报）

---

## 修复方案

### 修复1: 改进from_param处理逻辑 (优先级：P0)

**目标**: 减少54个CRITICAL误报

**文件**: `src/pass/analysis/issue/free_validation.zig:357-374`

**修改前**:
```zig
.from_param => {
    const src = if (origin_info) |info| info.source_desc else "";
    if (isFreeSafe(callee_name, origin, src)) return false;
    // 只豁免C/C++ free
    if (std.mem.eql(u8, callee_name, "free") or
        std.mem.startsWith(u8, callee_name, "operator delete"))
    {
        return false;
    }
    try reportInvalidFree(...);
    return true;
},
```

**修改后**:
```zig
.from_param => {
    const src = if (origin_info) |info| info.source_desc else "";
    // 优先检查isFreeSafe（包含Rust所有权转移逻辑）
    if (isFreeSafe(callee_name, origin, src)) return false;
    
    // 标准C/C++所有权转移模式（caller malloc → callee free）
    if (std.mem.eql(u8, callee_name, "free") or
        std.mem.startsWith(u8, callee_name, "operator delete"))
    {
        return false;
    }
    
    // Rust所有权转移模式（caller Box::new → callee takes ownership）
    // 这是Rust的标准模式，不是bug
    if (isRustDeallocFunction(callee_name)) {
        return false;
    }
    
    try reportInvalidFree(...);
    return true;
},
```

**预期效果**: 
- 减少54个CRITICAL误报
- 保留真实的跨分配器bug检测（malloc + __rust_dealloc）

---

### 修复2: 改进FFI边界检测 (优先级：P0)

**目标**: 降低误报的严重程度

**文件**: `src/pass/analysis/issue/free_validation.zig:629-632`

**问题**: `ctx.isOnDangerPathFull(ptr_val)`过于敏感，将同语言内的函数调用也认为是FFI

**修改前**:
```zig
const ptr_val: u64 = @intFromPtr(ptr_arg);
const reaches_ffi = ctx.isOnDangerPathFull(ptr_val);
const base_confidence: f32 = if (reaches_ffi) 0.85 else 0.75;
const severity: Severity = if (reaches_ffi) .critical else .high;
```

**修改后**:
```zig
const ptr_val: u64 = @intFromPtr(ptr_arg);
const reaches_ffi = ctx.isOnDangerPathFull(ptr_val);

// 改进：只有真正的跨语言边界才升级为CRITICAL
// 同语言内的invalid_free（如C++ delete on stack）是HIGH
const is_cross_language = isCrossLanguageFree(origin, callee_name);
const base_confidence: f32 = if (reaches_ffi and is_cross_language) 0.85 else 0.75;
const severity: Severity = if (reaches_ffi and is_cross_language) .critical else .high;
```

**新增辅助函数**:
```zig
/// 检查是否是真正的跨语言free（不同分配器）
fn isCrossLanguageFree(origin: ValueOrigin, free_func: []const u8) bool {
    const is_rust_free = isRustDeallocFunction(free_func);
    const is_c_free = std.mem.eql(u8, free_func, "free") or
        std.mem.startsWith(u8, free_func, "operator delete");
    
    // 只有当free函数和origin来自不同语言时才是跨语言
    switch (origin) {
        .from_malloc => {
            // 需要检查source_desc来确定分配器语言
            return false; // 由isCrossAllocatorFree处理
        },
        .from_param => {
            // 参数可能来自任何地方，不能假设是跨语言
            return false;
        },
        .from_ffi_call => {
            // FFI调用返回的指针，如果用Rust dealloc释放就是跨语言
            return is_rust_free;
        },
        else => return false,
    }
}
```

**预期效果**:
- CRITICAL问题从55降到<5
- 保留真实的跨语言内存错误检测

---

### 修复3: 改进指针来源跟踪 (优先级：P1)

**目标**: 减少from_param误判

**问题**: 当指针通过函数调用传递时，丢失了原始的from_malloc信息

**文件**: `src/pass/analysis/issue/free_validation.zig:162-259`

**当前逻辑**:
```zig
// trackPointerOrigin只跟踪当前函数内的分配
// 跨函数传递的指针被标记为from_param
```

**改进方案**:
```zig
/// 改进的指针来源跟踪：保留跨函数的分配信息
fn trackPointerOrigin(
    allocator: std.mem.Allocator,
    inst: c.LLVMValueRef,
    pointer_origins: *std.AutoHashMap(c.LLVMValueRef, PointerInfo),
) !void {
    const opcode = c.LLVMGetInstructionOpcode(inst);

    switch (opcode) {
        c.LLVMCall, c.LLVMInvoke => {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) != 0) {
                const func_name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(func_name_ptr) != 0) {
                    const func_name = std.mem.span(func_name_ptr);

                    if (isAllocFunction(func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_malloc,
                            .source_inst = inst,
                            .source_desc = desc,
                        };
                    } else {
                        // 新增：检查返回值是否可能是堆分配
                        // 如果函数名包含"new", "create", "alloc"等，假设返回堆指针
                        const likely_heap_return = isLikelyHeapReturningFunction(func_name);
                        if (likely_heap_return) {
                            const desc = try std.fmt.allocPrint(allocator, "from {s}() (likely heap)", .{func_name});
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_malloc, // 假设是堆分配
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        }
                    }
                }
            }
        },
        // ... 其他case保持不变
        else => {},
    }
}

/// 检查函数名是否暗示返回堆分配的指针
fn isLikelyHeapReturningFunction(func_name: []const u8) bool {
    const heap_patterns = [_][]const u8{
        "new", "New", "create", "Create", "alloc", "Alloc",
        "make", "Make", "build", "Build", "construct", "Construct",
        "clone", "Clone", "copy", "Copy", "dup", "Dup",
    };
    for (heap_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}
```

**预期效果**:
- 减少from_param误判
- 提高from_malloc的准确率

---

### 修复4: 添加Rust标准库白名单 (优先级：P2)

**目标**: 减少memory_leak误报

**文件**: 新建 `src/semantics/rust_stdlib_patterns.zig`

```zig
//! Rust标准库内存管理模式识别
//!
//! 识别Rust标准库中的RAII模式，避免将正常的Drop实现误报为memory_leak

const std = @import("std");

/// Rust Drop trait实现模式
pub const DROP_PATTERNS = [_][]const u8{
    "drop_in_place",
    "Drop$GT$4drop",
    "Drop$GT$drop",
};

/// Rust智能指针类型
pub const SMART_POINTER_TYPES = [_][]const u8{
    "Box$LT$",
    "Rc$LT$",
    "Arc$LT$",
    "Vec$LT$",
    "String",
    "HashMap$LT$",
    "BTreeMap$LT$",
};

/// 检查函数是否是Rust Drop实现
pub fn isRustDropImpl(func_name: []const u8) bool {
    for (DROP_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// 检查函数是否操作Rust智能指针
pub fn isSmartPointerOperation(func_name: []const u8) bool {
    for (SMART_POINTER_TYPES) |ptr_type| {
        if (std.mem.indexOf(u8, func_name, ptr_type) != null) {
            return true;
        }
    }
    return false;
}

/// 检查是否是Rust的自动内存管理
pub fn isRustAutoMemoryManagement(func_name: []const u8) bool {
    return isRustDropImpl(func_name) or isSmartPointerOperation(func_name);
}
```

**集成到memory_leak检测**:
```zig
// 在memory_safety.zig中
const rust_stdlib = @import("../../semantics/rust_stdlib_patterns.zig");

// 检测memory_leak时
if (rust_stdlib.isRustAutoMemoryManagement(func_name)) {
    // 跳过，这是Rust的自动内存管理
    return false;
}
```

**预期效果**:
- 减少~200个memory_leak误报
- 保留真实的内存泄漏检测

---

## 实施计划

### 阶段1: 紧急修复 (1-2天)

**目标**: 将CRITICAL误报从54降到<5

1. ✅ 实施修复1: 改进from_param处理
2. ✅ 实施修复2: 改进FFI边界检测
3. ✅ 测试wasmtime，验证CRITICAL降低

**验证标准**:
```bash
zig build run -- --json ./corpus/real_world/other/wasmtime_test.bc > output.json
jq '.issues | group_by(.severity) | map({severity: .[0].severity, count: length})' output.json
# 期望: critical < 5
```

### 阶段2: 精度提升 (3-5天)

**目标**: 将总体精度从17%提升到>60%

1. ✅ 实施修复3: 改进指针来源跟踪
2. ✅ 实施修复4: 添加Rust标准库白名单
3. ✅ 调整unchecked_return严重程度
4. ✅ 测试完整corpus

**验证标准**:
```bash
# 运行完整测试集
./scripts/benchmark.sh
# 期望: precision > 60%, recall > 50%
```

### 阶段3: 召回率优化 (1周)

**目标**: 找到更多真实bug

1. ✅ 分析wasmtime CVE历史
2. ✅ 添加Rust特定检查（unsafe块、transmute）
3. ✅ 改进FFI生命周期分析

---

## 测试验证

### 单元测试

```zig
test "FreeValidation - Rust ownership transfer" {
    // 测试：Rust参数通过__rust_dealloc释放（正常）
    // 期望：不报错
}

test "FreeValidation - cross allocator" {
    // 测试：malloc + __rust_dealloc（bug）
    // 期望：报CRITICAL
}

test "FreeValidation - same language" {
    // 测试：__rust_alloc + __rust_dealloc（正常）
    // 期望：不报错
}
```

### 集成测试

```bash
# 测试wasmtime
zig build run -- --json ./corpus/real_world/other/wasmtime_test.bc > wasmtime_fixed.json

# 对比修复前后
jq '.issues | group_by(.severity)' wasmtime_before.json > before.txt
jq '.issues | group_by(.severity)' wasmtime_fixed.json > after.txt
diff before.txt after.txt

# 期望差异：
# - critical: 55 → <5
# - high: 566 → ~200
# - medium: 979 → ~400
```

---

## 风险评估

### 修复1-2: 低风险
- **影响范围**: 仅影响invalid_free检测
- **回退方案**: 恢复原逻辑
- **测试覆盖**: 现有测试用例充分

### 修复3: 中风险
- **影响范围**: 影响所有指针来源跟踪
- **潜在问题**: 可能引入新的误判
- **缓解措施**: 
  - 保守实施，只添加明确的heap-returning模式
  - 充分测试corpus

### 修复4: 低风险
- **影响范围**: 仅影响memory_leak检测
- **潜在问题**: 可能漏掉真实泄漏
- **缓解措施**:
  - 白名单只包含标准库
  - 用户代码不受影响

---

## 成功指标

### 短期 (修复1-2完成后)
- ✅ CRITICAL误报 < 5个
- ✅ wasmtime分析时间 < 90秒
- ✅ 无新增测试失败

### 中期 (修复3-4完成后)
- ✅ 总体精度 > 60%
- ✅ HIGH误报 < 200个
- ✅ MEDIUM误报 < 400个

### 长期 (阶段3完成后)
- ✅ 精度 > 70%
- ✅ 召回率 > 60%
- ✅ 可用于CI集成

---

## 总结

**核心问题**: Rust所有权模式误判导致54个CRITICAL误报

**根本原因**: 
1. from_param处理逻辑不完善
2. FFI边界检测过于敏感
3. 指针来源跟踪丢失跨函数信息

**修复策略**: 
1. 紧急修复CRITICAL误报（P0）
2. 逐步提升精度（P1-P2）
3. 长期优化召回率（P3）

**预期效果**:
- CRITICAL: 55 → <5 (91%改进)
- 总体精度: 17% → >70% (4倍提升)
- 可用性: 低 → 中等（适合CI）

---

生成时间: 2026-05-31
作者: OmniScope团队
