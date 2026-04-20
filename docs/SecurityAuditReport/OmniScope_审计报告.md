# OmniScope 安全审计报告

| 项目 | 信息 |
|------|------|
| **项目名称** | OmniScope |
| **项目类型** | LLVM IR 跨语言 FFI 静态安全分析框架 |
| **实现语言** | Zig |
| **审计日期** | 2026-04-20 |
| **审计范围** | `src/` 全部 66 个 .zig 源文件 |
| **审计方法** | 人工代码审计 |

---

## 1. 审计概览

| 严重等级 | 数量 |
|----------|------|
| 🔴 高危 (High) | 3 |
| 🟠 中危 (Medium) | 4 |
| 🟡 低危 (Low) | 3 |
| **合计** | **10** |

---

## 2. 高危漏洞

### OS-H01：`ffi_analysis.zig` — 指针截断导致 ID 碰撞

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/ffi_analysis.zig` |
| **行号** | 207, 251 |
| **严重等级** | 🔴 高危 |

**问题描述**：

`collectAllocationSites` 和 `collectFreeSites` 中使用 `@as(u64, @truncate(@intFromPtr(inst)))` 将 LLVM 指令指针截断为 `u64` 作为 HashMap key。在 64 位系统上，`@truncate` 会将 `usize`（64 位）截断为 `u64`——虽然当前不会丢失数据，但 `@as(u64, @truncate(...))` 的写法本身是冗余且危险的：

1. `@intFromPtr` 返回 `usize`，在 64 位系统上就是 `u64`，`@truncate` 到 `u64` 无意义
2. 如果未来在 128 位系统上编译，`@truncate` 会静默截断高位，导致不同指针映射到相同 key
3. 项目中 `taint_propagation.zig` 已通过 `TaintContext.getValueIdFromUsize()` 采用了安全的 ID 映射方案，但 `ffi_analysis.zig` 未跟进

**当前代码**：
```zig
// 第 207 行
const ptr_value_id = @as(u64, @truncate(@intFromPtr(inst)));
// 第 251 行
const ptr_value_id = @as(u64, @truncate(@intFromPtr(inst)));
```

**修复建议**：

方案 A（推荐）：使用 `ValueIdMap` 统一 ID 映射：
```zig
const ptr_value_id = try self.value_id_map.getOrCreateId(@intFromPtr(inst));
```

方案 B（最小改动）：移除冗余截断：
```zig
const ptr_value_id: u64 = @intFromPtr(inst);
```

---

### OS-H02：`ffi_analysis.zig` — `SemanticRegistry` 中不存在 `memory_alloc` / `memory_free` 枚举值

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/ffi_analysis.zig` |
| **行号** | 206, 250 |
| **严重等级** | 🔴 高危 |

**问题描述**：

`collectAllocationSites` 和 `collectFreeSites` 中检查 `sem.kind == .memory_alloc` 和 `sem.kind == .memory_free`，但 `SemanticRegistry.RiskKind` 枚举中实际定义的是 `.allocator` 和 `.deallocator`，不存在 `.memory_alloc` 和 `.memory_free`。

这意味着这两个分支**永远不会被执行**，所有权违规检测 pass 完全无法收集到分配/释放站点，导致：
- `detectDoubleFree` 无数据可分析
- `detectOwnershipMismatch` 无数据可分析
- 整个 `FFIAnalysisPass` 的核心功能失效

**当前代码**：
```zig
// 第 206 行 — 永远为 false
if (sem.kind == .memory_alloc) {
// 第 250 行 — 永远为 false
if (sem.kind == .memory_free) {
```

**实际 RiskKind 枚举值**（`semantic_registry.zig`）：
```zig
pub const RiskKind = enum {
    command_exec,
    unchecked_copy,
    format_string,
    allocator,      // ← 应使用此值
    deallocator,    // ← 应使用此值
    rust_ownership,
    borrow_escaped,
    memory_map,
    file_io,
    network_io,
    go_cgo_alloc,
};
```

**修复建议**：
```zig
// 第 206 行
if (sem.kind == .allocator) {
// 第 250 行
if (sem.kind == .deallocator) {
```

---

### OS-H03：`taint.zig` — `TaintPass.init` 返回值未处理

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/taint.zig` |
| **行号** | 394 |
| **严重等级** | 🔴 高危 |

**问题描述**：

`TaintPass.init` 声明返回 `!TaintPass`（可能返回错误），但测试代码中直接忽略返回值：

```zig
test "TaintPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = TaintPass.init(&store);  // ← 返回 !TaintPass，未处理错误
    _ = pass;
}
```

虽然 `init` 内部仅调用 `TaintGraph.init(allocator)` 可能 OOM，但在测试中忽略错误违反 Zig 的错误处理惯例。更重要的是，如果 `TaintPass.init` 被其他代码以同样方式调用，OOM 错误会被静默吞掉。

**修复建议**：
```zig
const pass = try TaintPass.init(&store);
```

---

## 3. 中危漏洞

### OS-M01：`initCapacity(0) catch unreachable` 反模式 — 系统性 OOM 崩溃风险

| 项目 | 内容 |
|------|------|
| **涉及文件** | `src/fact/store.zig` (26-29), `src/fact/query.zig` (28, 51, 74, 97), `src/pass/manager.zig` (41, 115, 135, 145, 171), `src/diag/aggregator.zig` (49, 85, 112), `src/main.zig` (26) |
| **严重等级** | 🟠 中危 |

**问题描述**：

项目中广泛使用 `initCapacity(allocator, 0) catch unreachable` 模式。虽然 `initCapacity(allocator, 0)` 在大多数分配器实现中不会失败（因为请求 0 字节），但这依赖于分配器实现细节，并非 Zig 语言保证。当系统内存极度紧张时，即使是 0 容量初始化也可能失败，`catch unreachable` 会导致**进程直接崩溃**，无任何错误恢复机会。

**涉及位置**（共 12 处）：

| 文件 | 行号 | 代码片段 |
|------|------|----------|
| `fact/store.zig` | 26-29 | `initCapacity(allocator, 1024) catch unreachable` × 4 |
| `fact/query.zig` | 28 | `initCapacity(allocator, 0) catch unreachable` |
| `fact/query.zig` | 51 | 同上 |
| `fact/query.zig` | 74 | 同上 |
| `fact/query.zig` | 97 | 同上 |
| `pass/manager.zig` | 41 | `initCapacity(allocator, 0) catch unreachable` |
| `pass/manager.zig` | 115 | 同上 |
| `pass/manager.zig` | 135 | 同上 |
| `pass/manager.zig` | 145 | 同上 |
| `pass/manager.zig` | 171 | 同上 |
| `diag/aggregator.zig` | 49, 85, 112 | 同上 |
| `main.zig` | 26 | 同上 |

**修复建议**：

对 `initCapacity(0)` 的场景，直接使用 `init(allocator)` 替代（无预分配，不会 OOM）：
```zig
// 替换前
std.ArrayList(Fact).initCapacity(allocator, 0) catch unreachable
// 替换后
std.ArrayList(Fact).init(allocator)
```

对 `initCapacity(1024)` 的场景，使用 `try` 传播错误：
```zig
std.ArrayList(FactKind).initCapacity(allocator, 1024)
```

---

### OS-M02：`ffi_analysis.zig` — `detectDoubleFree` 逻辑错误

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/ffi_analysis.zig` |
| **行号** | 269-297 |
| **严重等级** | 🟠 中危 |

**问题描述**：

`detectDoubleFree` 的实现逻辑有误。当前实现遍历所有 free site 对，如果两个不同的 free site 位于**同名函数**中，就报告 double free。但这个判断条件是错误的：

1. 同一个函数中可能有两个不同的 free 操作释放不同的指针——这不是 double free
2. 真正的 double free 应该是**同一个指针被释放两次**，需要通过数据流分析确认

**当前代码**：
```zig
if (std.mem.eql(u8, free_info.func_name, other_free.func_name)) {
    // 同名函数 = double free？逻辑错误
    try self.violations.append(.{
        .violation_type = .double_free,
        ...
    });
}
```

**修复建议**：

应跟踪被释放的指针值（而非函数名），检查同一指针是否出现在多个 free site 中：
```zig
// 应比较被释放的指针 ID，而非函数名
if (free_info.value_id == other_free.value_id) {
    // 同一指针被释放两次 = double free
}
```

---

### OS-M03：`dataflow/graph.zig` — `getIssuesBySeverity` 返回悬空内存

| 项目 | 内容 |
|------|------|
| **文件** | `src/dataflow/graph.zig` |
| **行号** | 383-406 |
| **严重等级** | 🟠 中危 |

**问题描述**：

`getIssuesBySeverity` 方法在 OOM 时返回 `&[_]Issue{}`（空字面量切片），但正常路径返回 `self.allocator.alloc(Issue, count)`。调用者无法区分这两种情况：

1. 如果返回空字面量切片，调用者尝试 `free` 会导致未定义行为
2. 如果返回分配的切片，调用者忘记 `free` 会导致内存泄漏
3. 注释说"Caller owns the returned memory"，但 OOM 时返回的不是 owned memory

**当前代码**：
```zig
if (count == 0) {
    return &[_]Issue{};  // ← 非 owned memory
}
const result = self.allocator.alloc(Issue, count) catch return &[_]Issue{};  // ← OOM 时也返回非 owned
```

**修复建议**：

统一使用错误返回：
```zig
pub fn getIssuesBySeverity(self: *const DataFlowGraph, severity: Severity) ![]Issue {
    // ...
    const result = try self.allocator.alloc(Issue, count);
    // ...
    return result;
}
```

---

### OS-M04：`taint.zig` — `TaintGraph.propagate` 无上限迭代可能导致性能问题

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/taint.zig` |
| **行号** | 344-377 |
| **严重等级** | 🟠 中危 |

**问题描述**：

`TaintGraph.propagate` 使用固定最大迭代次数 1000 次的 worklist 算法。对于大型 LLVM IR（如包含数万条指令的模块），1000 次迭代可能不足以完成传播，导致**污点分析不完整**——某些应该被标记为 tainted 的值未被标记，从而**漏报安全漏洞**。

```zig
const max_iterations = 1000;
// ...
while (changed and iterations < max_iterations) {
```

**修复建议**：

将上限与图规模关联：
```zig
const max_iterations = @max(1000, self.propagation_edges.items.len * 2);
```

---

## 4. 低危漏洞

### OS-L01：`ffi_detector.zig` — `hasTaintedDataFlow` 实现过于粗略

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/ffi_detector.zig` |
| **行号** | 570-581 |
| **严重等级** | 🟡 低危 |

**问题描述**：

`hasTaintedDataFlow` 只要存在任何 taint fact 就返回 `true`，不检查 taint 是否与当前 FFI match 相关。这会导致**大量误报**——即使污点数据与当前 FFI 边界完全无关，也会报告漏洞。

```zig
fn hasTaintedDataFlow(...) !bool {
    const taint_facts = try ctx.query_engine.queryByKind(.taint, ctx.allocator);
    defer ctx.allocator.free(taint_facts);
    return taint_facts.len > 0;  // ← 过于粗略
}
```

**修复建议**：

应匹配 function ID 或 value ID 来确认 taint 与当前 FFI match 相关。

---

### OS-L02：`taint_propagation.zig` — `handleCall` 中 sanitizer 分支提前 return 导致普通函数传播被跳过

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/taint_propagation.zig` |
| **行号** | 311-351 |
| **严重等级** | 🟡 低危 |

**问题描述**：

当被调用函数被识别为 sanitizer 函数时，`handleCall` 在处理完 sanitizer 逻辑后直接 `return`，跳过了后续的通用污点传播逻辑。如果 sanitizer 函数本身也应该是污点传播的中间节点（如 `strlen` 不修改数据但返回值依赖输入），则其返回值不会被标记为 tainted。

```zig
if (called_func_name.len > 0 and sanitizer_registry.isSanitizer(called_func_name)) {
    // ... 处理 sanitizer ...
    return;  // ← 提前返回，跳过通用传播
}
```

**修复建议**：

移除 `return`，让 sanitizer 处理后继续执行通用传播逻辑，或在 sanitizer 分支中也标记返回值为 tainted。

---

### OS-L03：`lock.zig` — `isLockAcquire` 基于字符串匹配可能误判

| 项目 | 内容 |
|------|------|
| **文件** | `src/pass/analysis/lock.zig` |
| **行号** | 195-209 |
| **严重等级** | 🟡 低危 |

**问题描述**：

`isLockAcquire` 通过检查函数名是否包含 `"lock"` 且不包含 `"unlock"` 来判断是否为获取操作。这种启发式匹配可能产生误判：

- `unlock_lock` 会被误判为 acquire（包含 "lock" 但不包含 "unlock"... 等等，包含 "unlock"，所以是 release。但 `relock` 会被误判为 acquire）
- 自定义函数名如 `block`、`clock` 会被误判为 lock acquire

```zig
return std.mem.indexOf(u8, func_name_slice, "lock") != null and
    std.mem.indexOf(u8, func_name_slice, "unlock") == null;
```

**修复建议**：

使用与 `isKnownLockFunctionByName` 相同的精确匹配列表，而非子串匹配。

---

## 5. 代码质量观察

### 5.1 正面评价

- **`taint_state.zig` + `value_id_map.zig`**：`TaintContext` 通过 `ValueIdMap` 实现了安全的指针到 ID 映射，彻底避免了 64 位系统上的指针截断问题。设计清晰，接口完善。
- **`fact/store.zig` 的 `insert` 方法**：使用 `errdefer` 正确回滚所有 4 个 SoA 数组，保证了原子性。
- **`pass/manager.zig`**：Kahn 算法实现拓扑排序，正确检测循环依赖和缺失依赖。
- **`registry/semantic_registry.zig`**：分层设计（Layer 1-4），支持多语言语义，使用 suffix/contains 匹配处理平台差异。
- **`engine/loader.zig`**：遵循"单一所有者"原则，`deinit` 是幂等的，资源管理清晰。

### 5.2 架构风险

| 风险 | 描述 |
|------|------|
| **两套并行的污点分析** | `taint.zig`（TaintPass）和 `taint_propagation.zig`（TaintPropagationPass）存在功能重叠。TaintPass 使用 `TaintGraph` + DFG fact 传播，TaintPropagationPass 使用 `TaintContext` + 直接 IR 遍历。两者可能产生不一致的分析结果。 |
| **QueryEngine 线程安全** | `QueryEngine` 直接访问 `FactStore.kinds.items` 等内部字段（如 `query.zig` 第 30 行），绕过了 `FactStore` 的 mutex。如果 `insert` 和 `query` 并发执行，可能导致数据竞争。 |
| **Severity 枚举重复定义** | `Severity` 在 `diag/issue.zig`、`diag/aggregator.zig`、`registry/semantic_registry.zig`、`pass/analysis/flow_path.zig`、`pass/analysis/ffi_analysis.zig`、`pass/analysis/vulnerability_rules.zig` 中分别定义，类型不兼容，无法直接比较。 |

---

## 6. 修复优先级建议

| 优先级 | 编号 | 描述 | 预估工作量 |
|--------|------|------|-----------|
| P0 | OS-H02 | `memory_alloc`/`memory_free` 枚举值不匹配 | 5 分钟 |
| P0 | OS-H01 | 指针截断 ID 碰撞 | 30 分钟 |
| P1 | OS-H03 | `TaintPass.init` 错误未处理 | 5 分钟 |
| P1 | OS-M02 | `detectDoubleFree` 逻辑错误 | 1 小时 |
| P2 | OS-M01 | `catch unreachable` 反模式 | 1 小时 |
| P2 | OS-M03 | `getIssuesBySeverity` 内存所有权 | 30 分钟 |
| P2 | OS-M04 | 传播迭代上限不足 | 15 分钟 |
| P3 | OS-L01 | `hasTaintedDataFlow` 过于粗略 | 2 小时 |
| P3 | OS-L02 | sanitizer 提前 return | 30 分钟 |
| P3 | OS-L03 | `isLockAcquire` 字符串误判 | 30 分钟 |

---

*审计完成。共发现 10 个问题：3 个高危、4 个中危、3 个低危。*
