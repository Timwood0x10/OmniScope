# OmniSope 项目 Bug 分析报告

## 高严重级别 (High)

### 1. FFIBoundary 缺失错误处理

- **文件:** `src/pass/analysis/ffi_boundary.zig:128`
- **描述:** `createFFIBoundariesFromMatcher()` 调用使用 `try`，失败时会静默跳过边界创建
- **建议:** 添加错误日志但继续分析

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
- **建议:** 确保正确的清理顺序或使用错误恢复

---

### 3. PassManager 中的 Double-Free

- **文件:** `src/pass/manager.zig:79-87`
- **描述:** `invalidateResolvedOrder()` 可能释放相同内存两次 - `execution_names` 和 `resolved_order` 可能指向同一分配的切片
- **建议:** 释放前将两者都设置为 null，或正确跟踪所有权

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
- **建议:** 使用 `std.mem.zeroInit` 初始化数组

---

### 5. ConfigLoader 错误路径内存泄漏

- **文件:** `src/registry/config_loader.zig:165-173`
- **描述:** 第二个 `dupe()` 失败时，JSON解析器的 description 副本会泄漏
- **建议:** 包装嵌套错误处理程序，追踪所有分配

---

### 6. getIssuesBySeverity 静默失败

- **文件:** `src/dataflow/graph.zig:391`
- **描述:** 分配失败时返回空切片，无法与真正的空结果区分
- **建议:** 返回错误或使用哨兵值

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
- **建议:** 检查循环中 put操作的错误返回值

---

## 低严重级别 (Low)

### 8. 已弃用函数仍存在

- **文件:** `src/ir/llvm_safe.zig:223-227`
- **描述:** `parseIR` 函数标记为已弃用但仍存在，是死代码
- **建议:** 删除此函数

---

### 9. 置信度计算错误

- **文件:** `src/pass/analysis/issue/free_validation.zig:325`
- **描述:** `0.75 * 100.0` = 75.0 而非 75%
- **建议:** 改为直接使用 75.0 作为百分比值

---

### 10. Integer Overflow in getRuleIndex

- **文件:** `src/report/sarif.zig:442-451`
- **描述:** 未找到匹配时返回最后一个 idx，即使规则列表为空
- **建议:** 返回错误或使用可选类型

---

## 建议修复优先级

1. **立即修复 (#1-3):** 可能导致崩溃或内存损坏
2. **添加错误处理 (#4-7):** 多个函数静默失败
3. **清理死代码 (#8):** 移除已弃用的 parseIR
4. **增加测试覆盖:** 边界情况如零长度分配、空结果