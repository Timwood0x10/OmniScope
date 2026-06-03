# Detector Migration Guide — Event-Driven Architecture

## 📋 概述

本指南说明如何将现有的 SemanticResolver detector 从**独立遍历模式**迁移到**事件驱动模式**。

## 🎯 迁移目标

将剩余的 11 个 detector 从 legacy 接口迁移到 UnifiedDetectorHub 的事件驱动接口：

| 优先级 | Detector | 文件 | 复杂度 | 预计收益 |
|--------|----------|------|--------|----------|
| P0 | `heap_provenance` | patterns/heap_provenance.zig | 高 | ⭐⭐⭐⭐⭐ |
| P0 | `ch06_obrm` | nomicon/ch06_obrm.zig | 中 | ⭐⭐⭐⭐ |
| P1 | `ch08_concurrency` | nomicon/ch08_concurrency.zig | 低 | ⭐⭐⭐ |
| P1 | `ch10_pin_box` | nomicon/ch10_pin_box.zig | 低 | ⭐⭐⭐ |
| P1 | `posix_syscalls` | nomicon/posix_syscalls.zig | 低 | ⭐⭐ |
| P2 | `interior_mut` | patterns/interior_mut.zig | 中 | ⭐⭐ |
| P2 | `into_raw_transfer` | patterns/into_raw_transfer.zig | 低 | ⭐⭐ |
| P2 | `library_alloc_pairs` | patterns/library_alloc_pairs.zig | 低 | ⭐⭐ |

> **注意**: `ch09_vec_box` 和 `lang_detector` 不需要迁移（特殊原因见下文）

## 🔧 迁移步骤（标准模板）

### 步骤 1: 导入依赖

在文件顶部添加：

```zig
const DetectorContext = @import("../detector_interface.zig").DetectorContext;
const DetectorInterface = @import("../detector_interface.zig").DetectorInterface;
```

### 步骤 2: 提取事件处理器

将原来的 `detectFunction()` 内部的遍历逻辑拆分为独立的事件处理函数：

```zig
// Before (legacy)
pub fn detectFunction(func, module, srt, diag) !void {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode == c.LLVMCall) {
                // ... handle call
            }
            if (opcode == c.LLVMLoad) {
                // ... handle load
            }
        }
    }
}

// After (event-driven)
fn onCallHandler(ctx: *DetectorContext, inst: c.LLVMValueRef, callee_name: ?[]const u8) !void {
    // ... handle call instruction
    // Use ctx.module, ctx.srt, ctx.allocator instead of parameters
}

fn onLoadHandler(ctx: *DetectorContext, inst: c.LLVMValueRef) !void {
    // ... handle load instruction
}
```

### 步骤 3: 创建 getInterface() 函数

```zig
/// Get the event-driven detector interface.
pub fn getInterface() DetectorInterface {
    return .{
        .instruction = .{
            .onCall = onCallHandler,
            .onLoad = onLoadHandler,
            // ... other handlers as needed
        },
        // Optional: function-level handlers
        .function = .{
            .onFunctionEnter = onFunctionEnterHandler,
        },
    };
}
```

### 步骤 4: 在 SemanticResolverPass 中注册

在 [semantic_resolver_pass.zig](src/pass/analysis/semantic_resolver_pass.zig) 的 `runWithUnifiedHub()` 中添加：

```zig
hub.registerDetector("your_detector_name", your_detector_module.getInterface());
```

## 📝 完整示例：param_attr detector

### Before (Legacy)

```zig
// param_attr.zig (legacy)
pub fn detectFunction(
    func: c.LLVMValueRef,
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = module;
    _ = diag;
    if (c.LLVMIsDeclaration(func) != 0) return;

    const num_params = c.LLVMCountParams(func);
    var i: c_uint = 0;
    while (i < num_params) : (i += 1) {
        // ... analyze params
    }
}
```

### After (Event-Driven)

```zig
// param_attr.zig (event-driven)

const DetectorContext = @import("../detector_interface.zig").DetectorContext;
const DetectorInterface = @import("../detector_interface.zig").DetectorInterface;

// Legacy interface preserved for backward compatibility
pub fn detectFunction(...) !void { /* ... */ }

// New event-driven handler
fn onFunctionEnterHandler(ctx: *DetectorContext) !void {
    const func = ctx.func;
    if (c.LLVMIsDeclaration(func) != 0) return;

    const num_params = c.LLVMCountParams(func);
    var i: c_uint = 0;
    while (i < num_params) : (i += 1) {
        // Use ctx.srt instead of srt parameter
        // ...
    }
}

// Interface factory
pub fn getInterface() DetectorInterface {
    return .{
        .function = .{
            .onFunctionEnter = onFunctionEnterHandler,
        },
    };
}
```

## 🎨 事件类型参考

### Instruction-Level Events

| 事件名称 | 触发条件 | 签名 | 使用场景 |
|---------|---------|------|---------|
| `onCall` | Call/Invoke 指令 | `(ctx, inst, callee_name)` | FFI 调用检测、分配函数识别 |
| `onBitcast` | BitCast 指令 | `(ctx, inst)` | 类型转换检测、transmute 识别 |
| `onLoad` | Load 指令 | `(ctx, inst)` | 未初始化内存读取、堆访问追踪 |
| `onStore` | Store 指令 | `(ctx, inst)` | 不可变写入、所有权违规 |
| `onAlloca` | Alloca 指令 | `(ctx, inst)` | 栈分配、DI 类型提取 |
| `onGEP` | GEP 指令 | `(ctx, inst)` | 指针算术、堆来源传播 |
| `onRet` | Ret 指令 | `(ctx, inst)` | 所有权返回、资源释放检查 |
| `onPtrIntConversion` | PtrToInt/IntToPtr | `(ctx, inst)` | 指针整数转换检测 |
| `onPHI` | PHI 节点 | `(ctx, inst)` | 堆来源合并、数据流分析 |

### Function-Level Events

| 事件名称 | 触发时机 | 签名 | 使用场景 |
|---------|---------|------|---------|
| `onFunctionEnter` | 进入新函数时 | `(ctx)` | 参数属性分析、函数级设置 |
| `onFunctionExit` | 离开函数时 | `(ctx)` | 清理临时状态、最终验证 |

## ⚠️ 特殊情况

### 不需要迁移的 Detector

#### 1. ch09_vec_box (固定点迭代)

**原因**: 需要**多次完整模块遍历**来实现数据流分析的固定点收敛。这是算法固有限制，无法合并到单次遍历。

**保持方式**: 继续使用独立的 `detect()` 接口，在 Phase 12 执行。

#### 2. lang_detector (只读查询)

**原因**: **不写入 SRT**，只提供查询 API (`detectLanguage()`)。没有副作用，不需要参与统一遍历。

**保持方式**: 继续使用独立的 `detect()` 接口，在 Phase 13 执行。

## ✅ 迁移检查清单

完成每个 detector 的迁移后，验证以下项目：

- [ ] 所有 LLVM API 调用都通过 `ctx.module` 或 `ctx.fir` 访问
- [ ] SRT 写入都通过 `ctx.srt.recordResolution()` 完成
- [ ] 错误使用 `try` 传播（不要吞掉错误）
- [ ] 日志使用 `std.log.scoped(.your_detector)` 
- [ ] `getInterface()` 返回正确的 Handler 组合
- [ ] 旧的 `detectFunction()` 和 `detect()` 接口保留（向后兼容）
- [ ] 在 `semantic_resolver_pass.zig` 中注册新的 detector

## 🧪 测试策略

### 单元测试

为每个事件处理器编写独立的单元测试：

```zig
test "my_detector: onCall handles allocation" {
    // Mock DetectorContext
    // Call onCallHandler with test data
    // Verify SRT contains expected resolution
}
```

### 集成测试

运行完整的 pipeline 并对比新旧输出：

```bash
# Run with legacy mode
zig build run -- --legacy-mode > output_legacy.json

# Run with unified mode
zig build run > output_unified.json

# Compare outputs (should be identical)
diff output_legacy.json output_unified.json
```

### 性能基准测试

测量优化前后的执行时间：

```bash
# Before migration (14 traversals)
time zig build run  # ~11.8s

# After migration (1 traversal + 2 special)
time zig build run  # Expected: ~7.8s (34% faster)
```

## 📊 当前迁移进度

✅ **已完成 (3/14)**:
- param_attr (R-0)
- ch04_conversions (Nomicon Ch4)
- ch05_uninitialized (Nomicon Ch5)

⏳ **待迁移 (11/14)**:
- heap_provenance (R-1) - **高优先级**
- ch06_obrm (Nomicon Ch6) - **高优先级**
- ch08_concurrency (Nomicon Ch8)
- ch10_pin_box (Nomicon Ch10)
- posix_syscalls (POSIX)
- interior_mut (Interior Mutability)
- into_raw_transfer (IntoRaw)
- library_alloc_pairs (Library Alloc)

➖ **不需要迁移 (2/14)**:
- ch09_vec_box (固定点迭代)
- lang_detector (只读查询)

## 🚀 下一步行动

1. 按照**优先级顺序**迁移剩余 detector
2. 每个 detector 迁移后立即运行回归测试
3. 完成所有迁移后，禁用 legacy path
4. 更新性能基准测试数据
5. 清理旧的 `detectFunction()` 接口（标记为 deprecated）

---

**相关文档**:
- [优化设计方案](SEMANTIC_RESOLVER_OPTIMIZATION_PLAN.md)
- [Detector 接口定义](src/semantics/detector_interface.zig)
- [UnifiedDetectorHub 实现](src/semantics/unified_detector_hub.zig)
- [SemanticResolverPass 改造](src/pass/analysis/semantic_resolver_pass.zig)
