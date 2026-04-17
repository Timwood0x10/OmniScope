# OmniSope 代码潜在 Bug 分析报告

> 审查日期: 2026-04-16
> 审查范围: `src/` 全部核心模块
> 最后更新: 2026-04-16 (全部验证完成)

---

## 严重程度说明

- 🔴 **Critical** — 可能导致段错误、内存安全违规或数据损坏
- 🟠 **High** — 逻辑错误、资源泄漏或错误结果
- 🟡 **Medium** — 设计缺陷、不一致性或潜在问题
- 🔵 **Low** — 代码质量、风格或可维护性问题

---

## 验证结果汇总

| 状态 | 计数 | Bug ID |
|------|------|--------|
| ✅ **已验证存在** | 10 | 01, 02, 04, 05, 06, 07, 08, 10, 11, 18 |
| ✅ **已验证不存在/已修复** | 1 | 03 (taint.zig 误报) |
| ❌ **已验证不存在/误报** | 6 | 09, 12, 13, 14, 15, 16 |

---

## 🔴 Critical 严重 Bug

### 1. 未初始化指针 - `src/pipeline/runtime_stage.zig` (行 40-45) ✅ **存在**

**严重程度**: 🔴 Critical

```zig
const ring_buffer_ptr: *RingBuffer = undefined;
```

**问题**: `ring_buffer_ptr` 被赋值为 `undefined` 并存储在结构体中。这是未定义行为 - 解引用此指针会导致崩溃或内存损坏。

**修复建议**: 需要在运行时正确初始化 `ring_buffer_ptr`，或者将其改为可选类型 `?*RingBuffer`。

---

### 2. 未定义变量引用 - `src/pass/analysis/alias.zig` (行 152) ✅ **存在**

**严重程度**: 🔴 Critical

```zig
const type_id = try self.getTypeId(type);  // 'type' 未定义
```

**问题**: 变量 `type` 未定义。应该是 `inst_type`（在行 145 定义）。这会导致编译错误或未定义行为。

**修复建议**: 将 `type` 改为 `inst_type`。

---

### 3. 内存泄漏 (page_allocator) - `src/pass/analysis/taint.zig` (行 46-49) ❌ **不存在/已修复**

**严重程度**: 🔴 Critical

**报告描述**:
```zig
.taint_graph = TaintGraph.init(std.heap.page_allocator),
.sources = std.ArrayList(u32).init(std.heap.page_allocator),
.sinks = std.ArrayList(u32).init(std.heap.page_allocator),
```

**验证结果**: ⚠️ **误报**

当前代码（taint.zig:41-52）实际使用的是传入的 `allocator` 参数：
```zig
pub fn init(allocator: std.mem.Allocator, store: *FactStore) TaintPass {
    return .{
        .allocator = allocator,
        .taint_graph = TaintGraph.init(allocator),
        .sources = std.ArrayList(u32).init(allocator),
        .sinks = std.ArrayList(u32).init(allocator),
    };
}
```

---

### 4. 内存泄漏 (page_allocator) - `src/pass/analysis/alias.zig` (行 57-58) ✅ **存在**

**严重程度**: 🔴 Critical

```zig
.type_cache = std.AutoHashMap(c.LLVMTypeRef, u32).init(std.heap.page_allocator),
.ptr_info_map = std.AutoHashMap(c.LLVMValueRef, PointerInfo).init(std.heap.page_allocator),
```

**问题**: 使用废弃的 `page_allocator`。

**修复建议**: 改为接收 allocator 参数。

---

## 🟠 High 高危 Bug

### 5. 内存泄漏 (page_allocator) - `src/pass/foundation/cfg.zig` (行 40) ✅ **存在**

**严重程度**: 🟠 High

```zig
.bb_id_map = std.AutoHashMap(c.LLVMBasicBlockRef, u32).init(std.heap.page_allocator),
```

**修复建议**: 使用传入的 allocator。

---

### 6. 内存泄漏 (page_allocator) - `src/pass/foundation/dfg.zig` (行 40) ✅ **存在**

**严重程度**: 🟠 High

```zig
.inst_id_map = std.AutoHashMap(c.LLVMValueRef, u32).init(std.heap.page_allocator),
```

**修复建议**: 使用传入的 allocator。

---

### 7. 污点传播逻辑错误 - `src/pass/analysis/call_graph.zig` (行 261-262) ✅ **存在**

**严重程度**: 🟠 High

```zig
if (visited.contains(edge.callee)) continue;
visited.put(edge.callee, {}) catch continue;
```

**问题**: 在处理完所有调用者之前就将被调用者标记为"已访问"。这阻止了同一污点源通过多条路径到达汇点，可能遗漏漏洞。

**修复建议**: 应该在完成整个图遍历后再标记为已访问，或使用不同的数据结构来跟踪正在处理中的节点。

---

### 8. 悬空指针 - `src/pass/analysis/ffi_detector.zig` (行 436-442) ✅ **存在**

**严重程度**: 🟠 High

```zig
const func_name = c.LLVMGetValueName(called_func);  // 借用的指针
const func_name_slice = std.mem.span(func_name);
return func_name_slice;  // 返回借用指针
```

**问题**: `func_name` 是来自 `LLVMGetValueName` 的借用的指针。返回的切片在 LLVM 上下文被修改或函数返回后变为悬空指针。

**修复建议**: 在返回前复制字符串到独立内存。

---

## 🟡 Medium 中等 Bug

### 9. 资源泄漏 - `src/pipeline/pipeline.zig` (行 84-85) ❌ **不存在/误报**

**报告描述**:
```zig
self.ir_loader = try self.allocator.create(IRLoader);
self.ir_loader.?.* = loader;
```

**验证结果**: **误报**

代码在第 79-82 行有正确的清理逻辑：
```zig
if (self.ir_loader) |old_loader| {
    old_loader.deinit();
    self.allocator.destroy(old_loader);
}
```

`create` 失败时 `loader` 不会被泄漏（因为赋值还没发生）。

---

### 10. 不可达 panic - `src/plugin/abi.zig` (行 299) ✅ **存在**

**严重程度**: 🟡 Medium

```zig
pub fn factKindFromCABI(kind: u8) FactKind {
    return switch (kind) {
        0 => .cfg_edge,
        // ... cases 0-7
        else => unreachable,
    };
}
```

**问题**: `unreachable` 在无效输入时导致 panic 而不是返回错误。

**修复建议**: 返回 `error.InvalidKind` 或使用可选类型。

---

### 11. 硬编码时间戳 - `src/report/mod.zig` (行 270-274) ✅ **存在**

**严重程度**: 🟡 Medium

```zig
fn formatTimestamp(self: *ReportGenerator, timestamp: i64) []const u8 {
    _ = self;
    _ = timestamp;
    return "2024-01-15 10:30:00";
}
```

**问题**: 时间戳参数被忽略。所有报告都使用相同的硬编码时间戳。

**修复建议**: 实际格式化 timestamp 参数。

---

### 12. 缺少 JSON 转义 - `src/report/sarif.zig` ❌ **不存在/文件不存在**

**验证结果**: `src/report/sarif.zig` 文件不存在，相关代码不存在。

---

### 13. JSON 逗号位置错误 - `src/report/formatter.zig` ❌ **不存在/文件不存在**

**验证结果**: `src/report/formatter.zig` 文件不存在，相关代码不存在。

---

### 14. 不安全的 unwrap - `src/diag/aggregator.zig` (行 123-127) ❌ **不存在/误报**

**报告描述**:
```zig
.message = try std.fmt.allocPrint(
    self.allocator,
    "Runtime event detected at confidence {d:.2}",
    .{ev.confidence},
),
```

**验证结果**: **误报**

这是一个结构体字面量初始化，`allocPrint` 的错误会通过 `try` 传播，不会导致 `ev` 未完全初始化问题。

---

### 15. 静默失败 - `src/log/log.zig` (行 96) ❌ **不存在/可接受**

**报告描述**:
```zig
var msg = std.ArrayList(u8).initCapacity(allocator, 256) catch return;
```

**验证结果**: **设计决策，非 bug**

日志系统使用 `catch return` 是合理的 - 日志记录失败不应该导致程序崩溃。

---

### 16. 竞态条件 - `src/pass/analysis/taint_state.zig` ❌ **不存在/误报**

**报告描述**:
```zig
pub fn clear(self: *TaintContext) void {
    self.mutex.lock();
    defer self.mutex.unlock();
```

**验证结果**: **误报**

检查所有方法发现，`clear()`, `setValueTaint()`, `getValueTaint()`, `mergeTaint()`, `isTainted()` 等**所有方法**都正确使用了 mutex 锁，不存在竞态条件。

---

### 17. 内存生命周期问题 - `src/pass/analysis/ffi_detector.zig` (行 440-444) ✅ **存在**

**严重程度**: 🟡 Medium

**问题**: 返回指向 LLVM 拥有内存的借用指针。（与 BUG-08 重复）

**修复建议**: 返回前复制字符串。

---

### 18. 缺少内存清理 - `src/ffi/ffi_matcher.zig` (行 109-113) ✅ **存在**

**严重程度**: 🟡 Medium

**问题**: 在 `FFIMatcher.deinit()` 中：
- 释放了 `match.name`
- 但没有释放 `match.declare_func.name` 和 `match.define_func.name`

`FFIMatch` 的 `declare_func` 和 `define_func` 是 `FunctionInfo` 类型，其中 `name` 字段是独立分配的内存。

**修复建议**: 在 deinit 中遍历 match 时，也要释放 FunctionInfo 中的 name 字段。

---

## 修复优先级建议（最终版）

| 优先级 | Bug ID | 描述 | 状态 |
|--------|--------|------|------|
| 1 | BUG-01 | 未初始化指针 | ✅ 存在 |
| 1 | BUG-02 | 未定义变量 | ✅ 存在 |
| 1 | ~~BUG-03~~ | ~~taint.zig 内存泄漏~~ | ❌ 误报 |
| 1 | BUG-04 | alias.zig page_allocator | ✅ 存在 |
| 2 | BUG-05 | cfg.zig page_allocator | ✅ 存在 |
| 2 | BUG-06 | dfg.zig page_allocator | ✅ 存在 |
| 2 | BUG-07 | 污点传播逻辑错误 | ✅ 存在 |
| 2 | BUG-08 | 悬空指针 (ffi_detector) | ✅ 存在 |
| 2 | BUG-18 | FFI matcher 内存泄漏 | ✅ 存在 |
| 3 | BUG-10 | 硬编码时间戳 | ✅ 存在 |
| 3 | BUG-17 | 内存生命周期 (同 BUG-08) | ✅ 存在 |
| - | ~~BUG-09~~ | ~~pipeline 资源泄漏~~ | ❌ 误报 |
| - | ~~BUG-12~~ | ~~sarif.zig JSON 转义~~ | ❌ 文件不存在 |
| - | ~~BUG-13~~ | ~~formatter.zig 逗号~~ | ❌ 文件不存在 |
| - | ~~BUG-14~~ | ~~aggregator unwrap~~ | ❌ 误报 |
| - | ~~BUG-15~~ | ~~log 静默失败~~ | ❌ 设计决策 |
| - | ~~BUG-16~~ | ~~taint_state 竞态~~ | ❌ 误报 |

---

**报告结束**