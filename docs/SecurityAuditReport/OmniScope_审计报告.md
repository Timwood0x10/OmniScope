# OmniScope 安全审计报告

> 审计日期：2026-04-20 · 审计范围：src/ 全部 47 个 Zig 源文件 · 审计版本：当前最新

---

## 一、审计概要

| 项目 | 详情 |
|------|------|
| 项目名称 | OmniScope |
| 项目定位 | 基于 LLVM IR 的跨语言 FFI 静态安全分析框架 |
| 实现语言 | Zig |
| 外部依赖 | LLVM 21 (LLVM-C API) |
| 审计文件数 | 47 个 .zig 源文件 |
| 发现 Bug 数 | 12 个（1 Critical / 3 High / 4 Medium / 4 Low） |
| 整体评分 | 7.5 / 10 |

---

## 二、Bug 清单

### BUG-01 [Critical] FactStore::insert() errdefer 导致 SoA 数据错位

- **文件**: `src/fact/store.zig` 第 58-64 行
- **类别**: 数据损坏 / 逻辑错误

**问题**: `insert()` 依次向四个 SoA 数组追加元素，每个追加后注册 `errdefer` 回滚。Zig 的 `errdefer` 是栈式的（后注册先执行），当中间步骤失败时，已成功的数组会被正确 pop，但**未成功的数组也会被 pop**（弹出上一个有效元素），导致 SoA 四列长度不一致。

```zig
try self.kinds.append(self.allocator, kind);    // 成功
errdefer _ = self.kinds.pop();                   // errdefer #3
try self.subj.append(self.allocator, subject);   // 如果这里失败...
errdefer _ = self.subj.pop();                    // subj 没有新元素，pop 弹出上一个！
```

**影响**: 后续所有 `get(index)` 返回错位数据，分析结果完全不可信。

**修复建议**: 在函数入口保存各数组原始长度，失败时直接截断：
```zig
const orig_len = self.kinds.items.len;
try self.kinds.append(self.allocator, kind);
try self.subj.append(self.allocator, subject);
try self.obj.append(self.allocator, object);
try self.ctx.append(self.allocator, context);
// 失败时: 所有数组截断到 orig_len
```

---

### BUG-02 [High] taint_propagation.zig GEP 分支不可达

- **文件**: `src/pass/analysis/taint_propagation.zig` 第 479-508 行
- **类别**: 逻辑错误

**问题**: `c.LLVMGetElementPtr` 分支被放置在 `else => {}` 分支**之后**。Zig 的 `else` 会捕获所有未匹配的情况，GEP 指令永远落入 else 分支，专门的 GEP 深度衰减逻辑永远不会执行。

**影响**: GEP 指令的污点传播缺少深度衰减计算，通过多层指针解引用的污点置信度被高估。

**修复建议**: 将 `c.LLVMGetElementPtr` 分支移到 `else` 之前。

---

### BUG-03 [High] pointer_ownership.zig boundary_id=0 导致数组越界

- **文件**: `src/pass/analysis/pointer_ownership.zig` 第 626-651 行
- **类别**: 内存安全（越界访问）

**问题**: `registerBoundary()` 在 OOM 时返回 `0`（boundary.zig 第 169 行）。调用方使用 `boundary_id - 1` 作为数组索引，当 `boundary_id=0` 时，`0 - 1` 在 `usize` 上下溢为极大值，导致数组越界访问。

```zig
const boundary_id = boundary_analyzer.registerBoundary(...);  // 可能返回 0
boundary_analyzer.boundaries.items[boundary_id - 1]           // 下溢！
```

**影响**: 程序崩溃或未定义行为。

**修复建议**: 检查 `boundary_id == 0` 时跳过后续操作，或让 `registerBoundary` 返回错误码而非 0。

---

### BUG-04 [High] taint_propagation.zig 指针截断导致 Value ID 碰撞

- **文件**: `src/pass/analysis/taint_propagation.zig` 第 444, 458, 476, 483, 485, 492, 504 行
- **类别**: 类型安全 / 逻辑错误

**问题**: 使用 `@truncate(@intFromPtr(inst))` 将 64 位 LLVM 指针截断为 `u32` 作为污点键。项目已有 `ValueIdMap` 专门处理此映射，但此文件未使用。

**影响**: 大型 LLVM IR 分析时，不同值的指针低 32 位相同会导致污点碰撞，产生误报或漏报。

**修复建议**: 统一使用 `ValueIdMap` 替代直接截断。

---

### BUG-05 [Medium] call_graph.zig classifyRisk/isSink 与测试不匹配

- **文件**: `src/pass/analysis/call_graph.zig` 第 330-355 行
- **类别**: 逻辑错误

**问题**:
1. `classifyRisk` 使用精确匹配，但测试期望子串匹配（`"__libc_system"` 应返回 critical）
2. `isSink` 使用精确匹配，但测试期望 `"__strcpy_chk"` 等匹配成功
3. `contains()` 辅助函数已定义但从未使用

**影响**: 相关测试会失败，sink 检测覆盖率不足。

**修复建议**: 统一匹配策略（建议使用 `contains()` 子串匹配），更新测试。

---

### BUG-06 [Medium] profiler.zig summary() 线程不安全

- **文件**: `src/perf/profiler.zig` 第 177-195 行
- **类别**: 并发安全

**问题**: `summary()` 使用 `struct` 级别的 `var` 静态缓冲区，多线程调用会产生数据竞争。代码注释已标注 "not thread-safe"。

**影响**: 当前单线程使用无影响，未来多线程场景会出问题。

**修复建议**: 改为传入调用者提供的缓冲区，或使用互斥锁保护。

---

### BUG-07 [Medium] graph.zig getIssuesBySeverity 返回值所有权不一致

- **文件**: `src/dataflow/graph.zig` 第 379-402 行
- **类别**: API 设计缺陷

**问题**: `getIssuesBySeverity()` 通过 `allocator.alloc()` 分配新内存返回给调用者，但其他 getter 返回借用切片。调用者容易忘记释放导致内存泄漏，且无法区分"无匹配项"和"OOM"。

**修复建议**: 统一 API 约定，或改为返回迭代器/切片视图。

---

### BUG-08 [Low] pipeline.zig 纳秒时间戳截断

- **文件**: `src/pipeline/pipeline.zig` 第 91 行
- **类别**: 类型安全

**问题**: `@intCast` 将 `i128` 纳秒差值截断为 `u64`。超过 584 年才会溢出，实际无影响。

---

### BUG-09 [Low] main.zig 漏洞 ID 静默截断

- **文件**: `src/main.zig` 第 262 行
- **类别**: 类型安全

**问题**: `@intCast` 将 `usize` 截断为漏洞 ID 类型。超过 42 亿个漏洞才会溢出，实际无影响。

---

### BUG-10 [Low] call_graph.zig contains() 死代码

- **文件**: `src/pass/analysis/call_graph.zig` 第 358-360 行
- **类别**: 死代码

**问题**: `contains()` 函数已定义但从未被调用。可能是重构遗留。

**修复建议**: 删除或用于替换 `classifyRisk`/`isSink` 中的精确匹配。

---

### BUG-11 [Medium] ffi_analysis.zig 指针截断

- **文件**: `src/pass/analysis/ffi_analysis.zig` 第 207, 251 行
- **类别**: 类型安全

**问题**: 与 BUG-04 相同模式，`@truncate(@intFromPtr(inst))` 截断为 u64。64 位系统上无影响，32 位系统可能碰撞。

**修复建议**: 统一使用 `ValueIdMap`。

---

### BUG-12 [Low] taint_state.zig initCapacity(0) catch unreachable

- **文件**: `src/pass/analysis/taint_state.zig` 第 121 行
- **类别**: 错误处理

**问题**: `initCapacity(allocator, 0) catch unreachable` — `initCapacity(0)` 几乎不会失败，但 `catch unreachable` 不是最佳实践。

**修复建议**: 改为 `initCapacity(allocator, 0) catch return &[_]u32{};` 或直接使用 `init(allocator)`。

---

## 三、Bug 严重性分布

| 严重性 | 数量 | Bug 编号 |
|--------|------|----------|
| Critical | 1 | BUG-01 |
| High | 3 | BUG-02, BUG-03, BUG-04 |
| Medium | 4 | BUG-05, BUG-06, BUG-07, BUG-11 |
| Low | 4 | BUG-08, BUG-09, BUG-10, BUG-12 |

---

## 四、修复优先级

| 优先级 | Bug | 理由 |
|--------|-----|------|
| P0 立即 | BUG-01 | FactStore 数据损坏，所有分析结果不可信 |
| P1 尽快 | BUG-03 | 数组越界，程序崩溃 |
| P1 尽快 | BUG-02 | GEP 分支不可达，污点分析精度下降 |
| P2 计划 | BUG-04, BUG-11 | 指针截断，大型 IR 分析时碰撞 |
| P2 计划 | BUG-05 | 测试与实现不匹配 |
| P3 择机 | BUG-06 ~ BUG-12 | API 设计、死代码、防御性编程 |

---

## 五、代码质量评估

### 优点

1. **架构设计优秀**: Pass-based 分析架构清晰，拓扑排序管理依赖，模块解耦良好
2. **SoA 数据布局**: FactStore 使用 Structure of Arrays，缓存友好
3. **comptime 类型安全**: Pass 接口编译期验证，零运行时开销
4. **数据驱动设计**: SemanticMapper 使用规则表，易于扩展
5. **测试覆盖全面**: 几乎每个模块都有单元测试
6. **资源管理规范**: 大部分模块正确实现 init/deinit，defer/errdefer 清理
7. **LLVM-C 安全封装**: 通过 llvm_safe.zig 安全包装原始 API
8. **多格式输出**: Text/JSON/SARIF 三种格式，SARIF 符合 v2.1.0 规范
9. **可扩展注册表**: SemanticRegistry 4 层查找机制
10. **路径敏感分析**: path_condition.zig 实现 null check 追踪

### 不足

1. **errdefer 栈式行为理解有误**: BUG-01 是最严重的问题
2. **switch 分支顺序错误**: BUG-02 是典型重构遗留
3. **测试与实现不同步**: BUG-05 多个测试用例与实现不匹配
4. **指针截断系统性存在**: 多个文件重复相同问题，已有 ValueIdMap 但未统一使用
5. **API 所有权约定不一致**: 部分方法返回拥有内存，部分返回借用

---

## 六、总结

OmniScope 整体架构设计优秀，代码质量在同类项目中属于上乘。发现的 12 个 bug 中，BUG-01（FactStore 数据损坏）是唯一需要立即修复的 Critical 问题。BUG-02 和 BUG-03 属于 High 级别，建议尽快处理。其余 Medium/Low 问题可在后续迭代中逐步修复。

项目在内存安全、类型安全和错误处理方面表现良好，主要问题集中在 Zig 语言特性的使用细节上（errdefer 栈式行为、switch 分支顺序）和 API 设计一致性上。
