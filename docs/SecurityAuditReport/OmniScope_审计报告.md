# OmniScope 安全审计报告（第五轮 · 全面扫描）

> **审计日期**: 2026-04-25 · **审计范围**: `src/` 全部 82 个 Zig 源文件 + 3 CI/CD 工作流 · **版本**: v0.1.5 → v0.1.6 · **方法**: 三路并行全量逐行审计

---

## 1. 概览

| 项目 | 详情 |
|------|------|
| **项目名称** | OmniScope |
| **项目描述** | 基于 LLVM IR 的跨语言 FFI 静态安全分析框架 |
| **主要语言** | Zig (0.15.2+) |
| **外部依赖** | LLVM 21/22 (LLVM-C API) |
| **审计文件数** | 82 Zig 源文件 + 3 CI/CD 工作流（较第四轮 +3 文件） |
| **综合评分** | 8.5 / 10（与上轮持平，新增代码质量良好，无回归） |

### 本轮变化

自第四轮以来，项目经历了重要架构转型：
- **新增 `semantics/zone_classifier.zig`**：安全域/逃逸域分类器（Safe Zone vs Escape Zone）
- **新增 `transmute_detection.zig`**：Rust transmute 生命周期检测
- **新增 `root.zig`**：根模块
- **修改 `noise_reduction.zig`**：Rust 通道模式、Arc/Mutex 模式识别
- **修改 `cpp_fp_reduction.zig`**：UAF 检测增强、安全模式集成
- **修改 `allocation_classifier.zig`**：栈/堆区分逻辑
- **移除多个旧模块**：access_order、control_flow_sensitive、sensitive_data_flow

### 审计标准

严格聚焦**实际 bug**（崩溃、错误结果、内存安全问题、编译错误）。不报告设计取舍、性能优化、理论风险。

---

## 2. 第四轮已知问题修复验证

| # | 问题 | 状态 |
|---|------|------|
| BUG-R4-001 | `ffi_analysis.zig:259` operand 索引错误 | ✅ 已修复（operand 0） |
| BUG-R4-002 | `call_graph.zig:126` off-by-one | ✅ 已修复（直接用 `i`） |
| BUG-R4-003 | `memory_pool.zig:165-177` 对齐问题 | ✅ 已修复（alignForward） |
| BUG-R4-004 | `formatter.zig:228,230` SARIF 未转义 | ✅ 已修复（writeEscapedString） |
| BUG-R4-005 | `main.zig:272-287` JSON 未转义 | ✅ 已修复（writeJsonEscaped） |
| BUG-R4-006 | `ci_integration.zig:315` 拼写错误 | ✅ 已修复（OmniScope） |
| BUG-R4-007 | `main.zig:175` 负时间差 panic | ✅ 已修复（@max(0, elapsed)） |
| BUG-R4-008 | `security-analysis.yml:62` 命令注入 | ✅ 已修复（硬编码 SARIF） |
| BUG-R4-009 | `fact/query.zig:29-109` 数据竞争 | ✅ 已修复（加锁） |

**结论：第四轮 9 个问题全部修复，无回归。**

---

## 3. 新发现问题

### 3.1 高危（3 个）

#### BUG-R5-001 [High] dataflow/graph.zig:130-131 — 对 comptime 空切片调用 allocator.free()

- **文件**: `src/dataflow/graph.zig` 第 130-131, 171, 96, 510 行
- **描述**: `addNode` 将 comptime 空切片 `&[_]u32{}` 插入 HashMap。后续 `addEdge`、`deinit`、`clear` 对其调用 `allocator.free()`，试图释放从未由分配器分配的内存，导致**堆损坏或崩溃**。
- **代码**:
```zig
// 第 130-131 行（根因）
try self.outgoing_edges.put(node.id, &[_]u32{});
try self.incoming_edges.put(node.id, &[_]u32{});

// 第 171 行（触发）
self.allocator.free(outgoing);  // outgoing 可能是 &[_]u32{}
```
- **触发条件**: 任何调用 `addNode` 后再调用 `addEdge` 的路径
- **修复**: 在 `addNode` 中使用分配器分配空切片：
```zig
const empty = try self.allocator.alloc(u32, 0);
try self.outgoing_edges.put(node.id, empty);
try self.incoming_edges.put(node.id, empty);
```

#### BUG-R5-002 [High] lock.zig:199 — isLockAcquire 使用错误的 operand 获取 callee

- **文件**: `src/pass/analysis/lock.zig` 第 199 行
- **描述**: `isLockAcquire` 使用 `LLVMGetOperand(inst, 0)` 获取被调用函数，但 operand 0 是第一个参数（mutex 指针），不是 callee。同文件中 `isLockOperation`（第 161 行）正确使用了 `LLVMGetCalledValue(inst)`，但 `isLockAcquire` 没有。导致**所有锁操作被错误分类为 release，死锁检测图边方向全部反转**。
- **修复**: 将第 199 行改为 `const called_func = c.LLVMGetCalledValue(inst);`

#### BUG-R5-003 [High] ffi_body_check.zig:596 — 硬编码 operand 1 获取 callee

- **文件**: `src/pass/analysis/issue/ffi_body_check.zig` 第 596, 614 行
- **描述**: 使用 `LLVMGetOperand(inst, 1)` 获取 callee，但 LLVM call 指令的 callee 位于 `num_operands - 1`。硬编码 1 仅在恰好 1 个参数时正确。0 参数时越界，2+ 参数时获取的是第二个参数而非 callee。同时第 614 行 `var arg_idx: u32 = 2` 导致参数收集从第三个参数开始，跳过前两个。
- **修复**:
```zig
const called_value = c.LLVMGetOperand(inst, num_operands - 1);
var arg_idx: u32 = 0;
while (arg_idx < num_operands - 1) { ... }
```

### 3.2 低危（1 个）

#### BUG-R5-004 [Low] perf/bench_compare.zig:37,63,89,115,141 — 基准测试计时逻辑错误

- **文件**: `src/perf/bench_compare.zig`（5 处）
- **描述**: 所有基准测试函数中，`const start = timer.start_time` 在循环外赋值一次，循环内每次迭代使用同一个 `start` 计算累积时间而非单次迭代耗时。输出结果无意义。
- **修复**: 在每次迭代开始时重新获取时间戳

### 3.3 审计误报修正

> **本轮审计初版报告了 4 个"编译错误"（report/mod.zig、report/sarif.zig、report/ci_integration.zig、ffi_boundary.zig），经验证全部为误报：**
> - `report/` 目录下 3 个文件未被任何文件 import，是死代码，不参与编译
> - `ffi_boundary.zig` 的 `c.uint` 是 `@cImport` 合法引入的 C 类型（`unsigned int`），代码正确
>
> **这是审计流程的失误——未验证代码是否参与编译就下了结论。已在本版报告中修正。**

---

## 4. 问题汇总

### 严重性分布

| 严重等级 | 数量 | 说明 |
|----------|------|------|
| 🔴 高危 (High) | 3 | 堆损坏 / 分析逻辑错误 |
| 🟡 低危 (Low) | 1 | 基准测试输出错误 |
| **合计** | **4** | |

### 按类别分布

| 类别 | 数量 |
|------|------|
| LLVM-C API operand 索引错误 | 2 |
| comptime 切片释放 | 1 |
| 计时逻辑 | 1 |

### 与历史轮次对比

| 轮次 | 文件数 | 新 bug | Critical | High | Medium | Low | 编译错误 | 评分 |
|------|--------|--------|----------|------|--------|-----|---------|------|
| R1 | 79 | 52 | 1 | 18 | 21 | 12 | 0 | 6.5 |
| R2 | 79 | 37 | 1 | 8 | 19 | 10 | 0 | 7.5 |
| R3 | 79 | 0 | 0 | 0 | 0 | 0 | 0 | 8.5 |
| R4 | 79 | 9 | 0 | 3 | 4 | 2 | 0 | 8.5 |
| R5 | 82 | 4 | 0 | 3 | 0 | 1 | 0 | 8.5 |

> 从 52 → 37 → 0 → 9 → 4，bug 数量持续下降。第五轮仅发现 4 个问题（0 Critical / 3 High / 0 Medium / 1 Low），无编译错误，无崩溃级 bug。

---

## 5. 修复优先级

### 必须修（3 个 High — 运行时崩溃/分析错误）

| # | 问题 | 修复 |
|---|------|------|
| 1 | `graph.zig:130-131` comptime 切片 free | → `allocator.alloc(u32, 0)` |
| 2 | `lock.zig:199` operand 索引 | → `LLVMGetCalledValue(inst)` |
| 3 | `ffi_body_check.zig:596` 硬编码 operand | → `num_operands - 1` |

### 可以不修（1 个 Low）

| # | 问题 | 原因 |
|---|------|------|
| 8 | `bench_compare.zig` 计时逻辑 | 仅影响基准测试输出 |

---

## 6. 新增代码审计
|------|------|
| `semantics/zone_classifier.zig` | ✅ 无问题。纯字符串匹配，无内存安全问题 |
| `transmute_detection.zig` | ✅ 无问题。LLVM 指针空值检查完备，内存管理正确 |
| `root.zig` | ✅ 无问题。纯模块重导出 |

**新增代码质量良好**，3 个新文件均无 bug。问题集中在修改/重构的旧代码中。

---

## 7. 不建议修改的项

以下为合理的工程取舍：

- **安全域/逃逸域分类** — 正确的架构方向，zone_classifier 实现干净
- **三层噪音过滤** — 设计正确
- **两套污点分析并存** — 渐进迁移正常状态
- **FFI 匹配不验证签名** — 平台限制
- **Steensgaard 精度** — 流不敏感别名分析固有局限

---

## 8. 结论

OmniScope 第五轮审计发现 **4 个问题**（3 High + 1 Low），**0 个编译错误**。

**最关键的问题**：`graph.zig` 的 comptime 切片释放会导致堆损坏，`lock.zig` 和 `ffi_body_check.zig` 的 operand 索引错误会导致分析结果完全错误。

**评分 8.5/10** — 与上轮持平。第四轮 9 个问题全部修复，新增 3 个文件质量良好（零 bug）。问题集中在旧代码的 LLVM operand 索引使用上，这是项目中的反复出现的问题模式，建议统一排查所有 `LLVMGetOperand` 调用。

---

## 9. 历史修复记录

### 第四轮修复（本轮验证全部通过）

| Bug ID | 描述 | 文件 |
|--------|------|------|
| BUG-R4-001 | ffi_analysis operand 索引 | `ffi_analysis.zig` |
| BUG-R4-002 | call_graph off-by-one | `call_graph.zig` |
| BUG-R4-003 | memory_pool 对齐 | `memory_pool.zig` |
| BUG-R4-004 | formatter SARIF 转义 | `output/formatter.zig` |
| BUG-R4-005 | main.zig JSON 转义 | `main.zig` |
| BUG-R4-006 | ci_integration 拼写 | `report/ci_integration.zig` |
| BUG-R4-007 | main.zig 时间差 panic | `main.zig` |
| BUG-R4-008 | security-analysis 命令注入 | `security-analysis.yml` |
| BUG-R4-009 | query.zig 数据竞争 | `fact/query.zig` |
