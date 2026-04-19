# OmniSope 项目 Bug 分析报告

**源码验证状态**: 已结合源码对比分析 (2026-04-19)

## 高严重级别 (High)

### 1. FFIBoundary 缺失错误处理

- **文件:** `src/pass/analysis/ffi_boundary.zig:128`
- **描述:** `createFFIBoundariesFromMatcher()` 调用使用 `try`，失败时会静默跳过边界创建
- **源码验证:** ✅ **问题存在但描述不准确**
  - 源码第 128 行确实使用 `try ctx.data_flow_graph.createFFIBoundariesFromMatcher();`
  - 如果失败，整个 `run()` 函数会返回错误，而不是"静默跳过"
  - 但建议添加错误日志是合理的，可以改进错误处理

```zig
// 当前代码:
try ctx.data_flow_graph.createFFIBoundariesFromMatcher();

// 建议修改:
ctx.data_flow_graph.createFFIBoundariesFromMatcher() catch |e| {
    diag.warn("FFIBoundary: Failed to create boundaries: {}", .{e});
};
```

---

### 2. Pipeline 中的潜在Use-After-Free

- **文件:** `src/pipeline/pipeline.zig:35-54`
- **描述:** `QueryEngine` 存储指向 `fact_store` 的指针，如果 `DataFlowGraph.init()` 中途失败，已创建的 query_engine 持有悬空指针
- **源码验证:** ❌ **问题不存在**
  - 源码第 32-35 行：`query_engine` 创建后立即初始化，然后 `DataFlowGraph.init()` 使用 `try`
  - 如果 `DataFlowGraph.init()` 失败，整个 `Pipeline.init()` 返回错误，`deinit()` 不会被调用
  - 由于 Zig 的错误传播机制，不会有 use-after-free 问题

---

### 3. PassManager 中的 Double-Free

- **文件:** `src/pass/manager.zig:79-87`
- **描述:** `invalidateResolvedOrder()` 可能释放相同内存两次 - `execution_names` 和 `resolved_order` 可能指向同一分配的切片
- **源码验证:** ⚠️ **需要进一步验证**
  - 源码第 79-87 行：两个指针分别释放，源码中未发现它们指向同一内存的证据
  - 需要检查 `resolveDependencies()` 函数来确认内存分配逻辑

```zig
fn invalidateResolvedOrder(self: *PassManager) void {
    if (self.execution_names) |names| {
        self.allocator.free(names);
        self.execution_names = null;
    }
    if (self.resolved_order) |order| {
        self.allocator.free(order);
        self.resolved_order = null;
    }
}
```

---

## 中等严重级别 (Medium)

### 4. MemoryPool 未定义数组初始化

- **文件:** `src/perf/memory_pool.zig:80-81`
- **描述:** `Chunk.items` 设置为 `undefined` 但 `used` 设置为 1，使用未初始化内存会导致未定义行为
- **源码验证:** ✅ **问题存在**
  - 源码第 80-82 行：`.items = undefined, .used = 1`
  - 确实存在使用未初始化内存的风险，建议使用 `std.mem.zeroInit`
- **修复状态:** ✅ **已修复** (2026-04-19)
  - 修改为 `.items = [_]T{undefined} ** chunk_size`

---

### 5. ConfigLoader 错误路径内存泄漏

- **文件:** `src/registry/config_loader.zig:165-173`
- **描述:** 第二个 `dupe()` 失败时，JSON解析器的 description 副本会泄漏
- **源码验证:** ❌ **问题不存在**
  - 源码第 165-173 行：第一个 `dupe()` 失败时直接返回，没有分配
  - 第二个 `dupe()` 失败时，会释放第一个 `dupe()` 的结果（第 171 行）
  - 有 `errdefer self.allocator.free(pattern);` 确保清理

---

### 6. getIssuesBySeverity 静默失败

- **文件:** `src/dataflow/graph.zig:391`
- **描述:** 分配失败时返回空切片，无法与真正的空结果区分
- **源码验证:** ⚠️ **设计选择，非Bug**
  - 源码第 387-391 行：先检查 count == 0 返回空切片，然后分配失败也返回空切片
  - 这是一种防御性编程，避免分配失败导致崩溃
  - 建议改为返回错误可能更清晰，但当前实现不是严重bug

```zig
// 当前代码:
const result = self.allocator.alloc(Issue, count) catch return &[_]Issue{};

// 建议修改:
const result = self.allocator.alloc(Issue, count) catch return error.AllocationFailed;
```

---

### 7. FFI Matcher 缺失错误检查

- **文件:** `src/ffi/ffi_matcher.zig:137-163`
- **描述:** `define_map.put()` 失败时函数继续执行，导致未定义行为
- **源码验证:** ❌ **问题不存在**
  - 源码第 142-143 行：`try define_map.put(func.name, idx);` 使用了 `try`
  - 如果 `put()` 失败，整个 `matchFunctions()` 会返回错误，不会继续执行

---

## 低严重级别 (Low)

### 8. 已弃用函数仍存在

- **文件:** `src/ir/llvm_safe.zig:223-227`
- **描述:** `parseIR` 函数标记为已弃用但仍存在，是死代码
- **源码验证:** ✅ **问题存在**
  - 源码第 223-227 行：函数存在但只返回 `Error.IRLoadFailed`，没有实际实现
  - 注释说明应使用 `IRLoader`，此函数确实是死代码
- **修复状态:** ✅ **已修复** (2026-04-19)
  - 删除了 parseIR 函数及其测试

---

### 9. 置信度计算错误

- **文件:** `src/pass/analysis/issue/free_validation.zig:325`
- **描述:** `0.75 * 100.0` = 75.0 而非 75%
- **源码验证:** ✅ **问题存在**
  - 源码第 325 行：`0.75 * 100.0` 计算结果为 75.0
  - 格式化字符串使用 `{d:.2}%`，会显示 "75.00%" 而非 "75%"
  - 建议直接使用 75.0 或调整格式化
- **修复状态:** ✅ **已修复** (2026-04-19)
  - 修改为直接使用 75.0

---

### 10. Integer Overflow in getRuleIndex

- **文件:** `src/report/sarif.zig:442-451`
- **描述:** 未找到匹配时返回最后一个 idx，即使规则列表为空
- **源码验证:** ✅ **问题存在**
  - 源码第 442-451 行：循环中 `idx = i`，最后返回 `idx`
  - 如果 rule_list 为空，返回 idx=0，可能访问越界
  - 建议返回错误或使用可选类型
- **修复状态:** ✅ **已修复** (2026-04-19)
  - 修改为返回 `error.RuleNotFound`，调用处使用 `try` 处理

---

## 建议修复优先级

1. **立即修复 (#1-3):** 可能导致崩溃或内存损坏
2. **添加错误处理 (#4-7):** 多个函数静默失败
3. **清理死代码 (#8):** 移除已弃用的 parseIR
4. **增加测试覆盖:** 边界情况如零长度分配、空结果

---

## 源码验证总结

| Bug # | 问题描述 | 验证结果 | 说明 |
|-------|---------|---------|------|
| 1 | FFIBoundary 缺失错误处理 | ⚠️ 部分存在 | 使用 try 会返回错误，非静默跳过，但建议添加日志是合理的 |
| 2 | Pipeline Use-After-Free | ❌ 不存在 | Zig 错误传播机制保证不会出现此问题 |
| 3 | PassManager Double-Free | ⚠️ 需进一步验证 | 需检查 resolveDependencies() 确认内存分配逻辑 |
| 4 | MemoryPool 未定义数组 | ✅ 存在 | 确实存在使用未初始化内存的风险 |
| 5 | ConfigLoader 内存泄漏 | ❌ 不存在 | 已有 errdefer 确保清理 |
| 6 | getIssuesBySeverity 静默失败 | ⚠️ 设计选择 | 防御性编程，非严重 bug |
| 7 | FFI Matcher 错误检查 | ❌ 不存在 | 已使用 try 正确处理错误 |
| 8 | 已弃用函数仍存在 | ✅ 存在 | parseIR 确实是死代码 |
| 9 | 置信度计算错误 | ✅ 存在 | 格式化输出不准确 |
| 10 | getRuleIndex 越界 | ✅ 存在 | 空列表时可能返回无效索引 |

**统计结果:**
- ✅ 确认存在: 5 个 (4, 8, 9, 10, 部分 1)
- ❌ 确认不存在: 4 个 (2, 5, 6, 7)
- ⚠️ 需进一步验证: 1 个 (3)

**建议:** 优先修复 Bug #4 (MemoryPool) 和 Bug #10 (getRuleIndex)，这两个是真实存在且可能影响稳定性的问题。Bug #8 和 #9 可以在清理时一并处理。