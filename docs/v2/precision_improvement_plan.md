# Precision 70% 提升计划（无白名单方案）

> **日期**: 2026-06-02  
> **当前 Precision**: ~38%（T1实测）  
> **目标**: ≥70%  
> **约束**: 不依赖手写白名单扩展

---

## 根因分析

三个 FP 来源，性质完全不同：

| 来源 | FP 数 | 根因 |
|------|-------|------|
| `stress_patterns.bc` 宏生成代码 | ~108 | 宏展开 20×函数，每个都被独立报告 |
| Java/JNI 分析器 | ~80 | 无 JNIEnv* 参数验证，任何名字像 JNI 的函数都报 |
| confidence 阈值未生效 | 分散在各文件 | `pipeline.zig:68` 硬编码 0.5，未继承 `main_config` 的 0.65 |

---

## 方案 A：confidence 阈值修复（P0，1小时）

**问题**：`main_config.zig:185` 设置了 `leak_confidence_threshold = 0.65`，但
`pipeline.zig:68` 自己有一份硬编码的 `0.5`，且 `pipeline.zig:678` 用的是
pipeline 自己那份，main_config 的设置根本没传进来。

**修复**：在 `Pipeline.run()` 接收 config 时同步阈值：

```zig
// pipeline.zig 初始化时
self.leak_confidence_threshold = main_config.leak_confidence_threshold;
```

**预期效果**：所有 confidence < 0.65 的 issue 自动过滤，预计减少 25-35 个 FP。

---

## 方案 B：重复模式聚合（P0，1天）

**问题**：`stress_patterns.c` 用宏生成了 20 个几乎相同的函数
（`ffi_alloc_1` 到 `ffi_alloc_20`），每个函数产生独立报告 → 108 个同质 FP。

**方案：相似 issue 聚合，不是过滤**

检测同一类型、相似函数名（共同前缀+数字后缀）的 issue，合并为一条摘要：

```
// 当前：20 条独立 issue
[LEAK] ffi_alloc_1 — unfreed Rust allocation
[LEAK] ffi_alloc_2 — unfreed Rust allocation
...
[LEAK] ffi_alloc_20 — unfreed Rust allocation

// 聚合后：1 条
[LEAK×20] ffi_alloc_{1..20} — 20 identical patterns (macro-generated code detected)
```

**实现位置**：`src/diag/aggregator.zig` 已有 dedup 框架，扩展两步：

**Step 1**：在 `DiagnosticAggregator.addIssue()` 后，检测函数名的数字后缀模式：

```zig
fn extractPatternBase(func_name: []const u8) ?[]const u8 {
    // "ffi_alloc_3" → "ffi_alloc_"
    // 末尾连续数字 → 截掉，返回前缀
    var i = func_name.len;
    while (i > 0 and std.ascii.isDigit(func_name[i-1])) i -= 1;
    if (i == func_name.len) return null; // 无数字后缀
    if (i == 0) return null;
    if (func_name[i-1] != '_') return null; // 要求 _N 格式
    return func_name[0..i];
}
```

**Step 2**：相同 `(issue_kind, pattern_base)` 的 issue 计数，超过 3 个时折叠输出。

**涉及文件**：`src/diag/aggregator.zig`

**预期效果**：stress_patterns 的 108 个 FP → 5-6 条聚合摘要（真实的跨语言错误保留）。

---

## 方案 C：JNI 调用点结构验证（P0，1天）

**问题**：JNI 函数第一个参数必须是 `JNIEnv*`，但当前分析器只看函数名，
导致任何名字含 `JNI` / `FindClass` / `GetMethodID` 的函数都被报告。

**方案：IR 层参数类型验证**

在 `cross_lang_dataflow.zig` 的 JNI alloc 检测路径里，验证调用点第一个参数：

```zig
fn isRealJNICall(inst: c.LLVMValueRef) bool {
    // JNI 调用约定：第一个参数是 JNIEnv* (i8** 在 IR 层)
    if (c.LLVMGetNumOperands(inst) < 2) return false;
    const first_arg = c.LLVMGetOperand(inst, 0);
    const arg_type = c.LLVMTypeOf(first_arg);
    // JNIEnv* 在 IR 里是 i8** 或 %struct.JNINativeInterface_**
    return isPointerToPointer(arg_type) or isJNIEnvType(arg_type);
}
```

无 `JNIEnv*` 参数的调用 → 不是真实 JNI 调用 → 直接跳过，不报告。

**涉及文件**：`src/pass/analysis/ffi/cross_lang_dataflow.zig` JNI 检测块

**预期效果**：JNI 80% 误报率 → <20%（过滤掉所有"名字像JNI但不是JNI调用"的函数）。

---

## 方案 D：多探针共识（P1，2天）

**思路**：单个探针报告不可信，两个独立探针同时发现才报告。

**实现**：在 `DiagnosticAggregator` 里追踪每个 `(function, issue_kind)` 被几个
不同 pass 报告：

```zig
// aggregator.zig 新增字段
pass_votes: std.HashMap(DeduKey, std.ArrayList([]const u8)),

// 只有 ≥2 个不同 pass 对同一问题投票，才输出 issue
pub fn flushWithConsensus(min_votes: u32) []Issue
```

Pass 标识已有（`pass_name` 字段），不需要改 pass 本身，只改 aggregator 输出策略。

**预期效果**：单探针噪声消除约 30%，recall 损失 <5%（真实 bug 通常被多个探针发现）。

---

## 方案 E：调用深度过滤（P1，1天）

**思路**：FP 通常来自内部实现函数（被封装多层后调用），真实 FFI 边界在
调用链顶层。

**实现**：在 `createFFIBoundariesFromMatcher()` 里，利用已有的
`call_arg_by_callee` 索引判断函数的调用深度：

```zig
// 如果一个函数只被其他 FFI 函数调用（depth > 1），降低其 confidence
fn estimateFFIDepth(self: *DataFlowGraph, func_name: []const u8) u32 {
    const callers = self.call_arg_by_callee.get(func_name) orelse return 0;
    // 有调用者 = 不是边界，是内部实现
    return if (callers.items.len > 0) 1 else 0;
}
```

depth > 0 的函数 confidence × 0.6，低于阈值自动过滤。

**涉及文件**：`src/dataflow/graph.zig`

---

## 执行顺序

```
Day 1（今天）:
  方案A — confidence 阈值同步（1小时）  → 立即减少 25-35 FP
  方案C — JNI 参数验证（半天）          → 消除 ~80 FP

Day 2:
  方案B — 重复模式聚合（1天）           → stress_patterns 108 FP → 5条

Day 3-4:
  方案D — 多探针共识（2天）             → 系统性降低单探针噪声
  方案E — 调用深度过滤（1天）           → 进一步过滤内部实现误报
```

---

## 预期 Precision 提升路径

| 步骤 | 减少FP | Precision 预估 |
|------|--------|---------------|
| 当前基线 | — | **38%** |
| 方案A（阈值修复） | -30 | ~48% |
| 方案C（JNI验证） | -65 | ~62% |
| 方案B（聚合） | -100 | ~72% ✅ |
| 方案D（共识） | -20 | ~76% |
| 方案E（深度过滤） | -10 | ~78% |

方案A+B+C 三件合力可达 70%+ 目标，不需要任何白名单扩展。
