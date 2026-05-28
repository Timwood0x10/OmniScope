# OmniScope 项目审计报告

**日期**: 2026-05-28
**分支**: dev
**审计范围**: Dead Code、未使用Pass、潜在Bug、架构问题

---

## 一、Dead Code（死代码）

### 1.1 从未被import的模块（~9个文件，约3000+行）

| 文件 | 行数 | 说明 |
|------|------|------|
| `src/dataflow/guard_propagation.zig` | 235 | GuardPropagation 从未使用 |
| `src/dataflow/null_check_guard.zig` | 185 | NullCheckGuard 从未使用 |
| `src/dataflow/function_summary.zig` | 381 | DataFlow FunctionSummary 从未使用 |
| `src/dataflow/stats.zig` | 154 | DataFlow stats 从未使用 |
| `src/pass/analysis/steensgaard.zig` | 393 | Steensgaard指针分析从未使用 |
| `src/pass/analysis/transmute_detection.zig` | 295 | transmute检测从未调用 |
| `src/pass/analysis/alias_analysis.zig` | 129 | 与alias.zig不同，从未使用 |
| `src/diag/confidence_scorer.zig` | ? | 置信度评分器从未使用 |
| `src/diag/rule_engine.zig` | ? | 规则引擎从未使用 |

### 1.2 未使用的import（12处）

| 文件 | 行号 | 未使用的import |
|------|------|----------------|
| `src/dataflow/graph.zig` | 20,26,27 | IssueKind, ValueType, EdgeType |
| `src/pass/analysis/pointer_ownership.zig` | 14 | FactKind |
| `src/pass/analysis/lock.zig` | 20 | ValueRef |
| `src/pass/analysis/ffi/ffi_boundary.zig` | 27 | IssueSeverity |
| `src/pass/analysis/issue/ffi_unsafe.zig` | 16 | TraceEntry |
| `src/pass/analysis/issue/memory_safety.zig` | 36 | noise_filter |
| `src/pass/analysis/issue/free_validation.zig` | 25 | noise_filter |
| `src/pass/analysis/rust_ffi/rust_ffi_auditor.zig` | 19,22,25 | CommonTypes, rust_drop_semantics, debug_info |
| `src/pass/analysis/ptr_lifetime/ptr_lifetime.zig` | 56,58-59,91 | checkStoreToGlobal等 |
| `src/output/cli.zig` | 11 | Severity |

### 1.3 其他Dead Code

| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| 未使用函数 | `src/main.zig` | 845-848 | `countFunction` 从未调用 |
| 永远true的stub | `src/main.zig` | 649-652 | `isDangerousFFIPattern` 永远返回true |
| 未使用enum variant | `src/types/pass_types.zig` | 55 | `PassKind.plugin` 从未使用 |
| 未使用enum variants | `src/types/ownership_types.zig` | 43-49 | `FFIRelevanceHint` 4/5个variant未使用 |
| 未使用常量 | `src/common/arena.zig` | 40 | `min_alignment` 未使用 |
| 被注释代码 | `src/pass/analysis/noise/issue_suppression.zig` | 156-184 | 6个不存在的函数调用 |
| 被注释代码 | `src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig` | 872-876 | 引用不存在的函数 |

### 1.4 重复代码

| 重复对 | 说明 |
|--------|------|
| `ffi_format_check.zig` vs `ffi_format_checker.zig` | 几乎相同的`isFormatStringConstant`实现 |
| `ffi_helpers.zig` vs `ffi_utils.zig` | 职责重叠的FFI工具函数 |

---

## 二、做了但没用的Pass（13个）

### 2.1 定义了但从未注册的Pass

| # | Pass名 | 文件 | 说明 |
|---|--------|------|------|
| 1 | `FFIAnalysisPass` ("ownership-violation") | `ffi/ffi_analysis.zig:85` | 被PointerOwnershipPass取代 |
| 2 | `FFIDetector` ("ffi-detector") | `ffi/ffi_detector.zig:142` | 被FFIBoundaryPass+FFITypeMismatchPass取代 |
| 3 | `InstrumentationPlanner` | `instrumentation/planner.zig:53` | 从未注册，从未import |
| 4 | `ABIMismatchPass` ("abi-mismatch") | `abi_mismatch.zig:59` | main.zig中被注释掉 |
| 5 | `ThreadCrossingPass` ("thread-crossing") | `thread_crossing.zig:108` | main.zig中被注释掉 |

### 2.2 完整实现但从未接入pipeline

| # | 模块 | 文件 | 说明 |
|---|------|------|------|
| 6 | `transmute_detection` | `transmute_detection.zig` | 完整逻辑，无Pass包装 |
| 7 | `steensgaard` | `steensgaard.zig` | 完整O(n)实现，从未接入 |

### 2.3 基础设施模块从未使用

| # | 模块 | 文件 | 说明 |
|---|------|------|------|
| 8 | `output/lsp.zig` | `lsp.zig` | LSP诊断输出，从未import |
| 9 | `output/cli.zig` | `cli.zig` | CLI诊断输出，从未import |
| 10 | `AnalysisContext` | `perf/analysis_context.zig` | 导出了但从未使用 |
| 11 | `bench_compare` | `perf/bench_compare.zig` | 性能对比，从未import |
| 12 | `FPPrecisionGuard` | `fp_precision_guard.zig` | import了但调用都是`_ =`丢弃 |
| 13 | `IssueGate` | `issue_gate.zig` | 完整实现，从未import |

---

## 三、潜在Bug（14个）

### 3.1 高严重性

#### Bug #1: 指针截断 — 64位→32位丢失数据

**文件**: `src/pass/analysis/ptr_lifetime/ptr_lifetime.zig:562,570`
**同样出现在**: `ptr_lifetime_track.zig:219,335,370`

```zig
const cfg_bb_id: u32 = @truncate(@intFromPtr(cfg_bb));
const succ_bb_id: u32 = @truncate(@intFromPtr(succ_bb));
```

**问题**: 在64位系统上，LLVM的BasicBlock指针是64位。`@truncate`到u32会丢失高32位，导致不同BB映射到相同ID，造成CFG图错误边和double-free检测误报。

**修复方案**: 使用完整的u64作为ID，或使用HashMap映射指针到递增的u32 ID。

#### Bug #2: 字符串字面量free — OOM下崩溃

**文件**: `src/pass/analysis/buffer_overflow.zig:191-202`

```zig
const msg = std.fmt.allocPrint(ctx.allocator, "...") catch "Stack buffer overflow detected";
// ...
if (!ctx.isRelevantAlloc(base_ptr_val)) {
    ctx.allocator.free(msg);  // msg可能是字符串字面量！
    return null;
}
```

**问题**: `allocPrint`失败时`msg`为字符串字面量，后续`allocator.free(msg)`会crash。

**修复方案**: 使用`catch null`模式，free前检查是否为null，或用flag标记是否需要free。

#### Bug #3: WorkStealingDeque逻辑错误

**文件**: `src/pipeline/parallel.zig:137-154`

**问题**: pop减少bottom但不减ArrayList len，push用appendAssumeCapacity（基于len而非bottom）写入，导致数据错乱。

**修复方案**: 使用固定容量的ring buffer替代ArrayList，用bottom和top直接索引。

### 3.2 中等严重性

#### Bug #4: deque初始化部分失败泄漏

**文件**: `src/pipeline/parallel.zig:246-250`

```zig
const deques = try allocator.alloc(WorkStealingDeque(usize), actual_workers);
errdefer allocator.free(deques);
for (deques) |*deque| {
    deque.* = try WorkStealingDeque(usize).init(allocator, 64);
    // 如果第i个init失败，deques[0..i-1]的内部资源泄漏
}
```

**修复方案**: 循环内添加`errdefer`释放已初始化的deque。

#### Bug #5: GlobalAllocTracker.insertAlloc() 缺少errdefer

**文件**: `src/types/pass_types.zig:145-159`

**问题**: `records.append()`失败时`name_owned`和`callee_owned`泄漏。

**修复方案**: append前添加`errdefer allocator.free(name_owned)`。

#### Bug #6: DataFlowGraph.addEdge() 缺少errdefer

**文件**: `src/dataflow/graph.zig:170-184`

**问题**: `outgoing_edges.put()`失败时`new_list`泄漏。

**修复方案**: 添加`errdefer self.allocator.free(new_list)`。

#### Bug #7: handleHeapAlloc() catch return泄漏

**文件**: `src/pass/analysis/ptr_lifetime/ptr_lifetime_track.zig:191-206`

**问题**: `putPtrInfo`失败时`desc_alloc`已分配但未释放。

**修复方案**: 使用errdefer释放desc_alloc。

#### Bug #8: pipeline.zig ctx部分初始化泄漏

**文件**: `src/pipeline/pipeline.zig:106-150`

**问题**: PassContext有30+字段，某个init失败时之前初始化的字段全部泄漏。

**修复方案**: 使用两阶段初始化，或逐字段初始化并errdefer。

### 3.3 低严重性

#### Bug #9: spawn_shared全局变量无同步保护

**文件**: `src/pipeline/parallel.zig:206-210`

**问题**: 模块级可变变量，多executor并发时数据竞争。当前使用模式安全，但设计脆弱。

#### Bug #10: MemoryPool.free() O(n)双重释放检测

**文件**: `src/perf/memory_pool.zig:94-113`

**问题**: 遍历free_list链表检测双重释放，频繁alloc/free时性能差。

#### Bug #11: isDangerousFFIPattern永远返回true

**文件**: `src/main.zig:649-652`

**问题**: stub函数导致多文件分析模式下所有FFI匹配都被报告为漏洞，产生大量FP。

#### Bug #12: diagToNoiseSeverity不安全强制转换

**文件**: `src/types/pass_types.zig:1209`

```zig
fn diagToNoiseSeverity(sev: DiagSeverity) NoiseSeverity {
    return @enumFromInt(@intFromEnum(sev));
}
```

**问题**: 假设两个不同enum有相同布局。改为显式switch映射。

---

## 四、架构问题

### 4.1 PassContext God Object

**文件**: `src/types/pass_types.zig` (~1140行)

PassContext包含40+字段，职责过多。建议拆分为：
- `AnalysisContext`: allocator, module, fact_store, query_engine, data_flow_graph
- `CacheContext`: zone_cache, registry_cache, function_surface, ffi_set_cache
- `TrackingContext`: global_alloc_tracker, cross_lang_edges, cross_edge_by_callee
- `ConfigContext`: module_language, early_exit, platform_profile

### 4.2 main.zig 职责过多

**文件**: `src/main.zig` (924行)

包含CLI参数处理、Pipeline编排、文本/JSON/SARIF输出格式化、可视化生成。应拆分为：
- `src/cli/args.zig`: 参数解析
- `src/output/text.zig`: 文本格式化
- `src/output/json.zig`: JSON格式化
- `src/multi_file.zig`: 多文件分析逻辑

### 4.3 addIssue 函数过长

**文件**: `src/types/pass_types.zig:540-789` (~250行)

包含多层嵌套的降级规则。应提取：
- `applyNoiseSuppression()`
- `applySurfaceClassification()`
- `applySeverityDowngrade()`
- `applyDeduplication()`

---

## 五、行动计划

| 阶段 | 任务 | 工作量 | 影响 |
|------|------|--------|------|
| Phase 1 | 删除9个dead code模块 + 清理import | 0.5天 | 减少~3000行噪声 |
| Phase 2 | 清理13个未使用的Pass | 1天 | 消除困惑 |
| Phase 3 | 修复3个高严重性Bug | 1-2天 | 修复分析准确性 |
| Phase 4 | 修复5个中等Bug | 1天 | 消除OOM泄漏 |
| Phase 5 | 架构重构（拆分God Object） | 2-3天 | 改善可维护性 |
| Phase 6 | 合并重复代码 | 1天 | 消除冗余 |
| Phase 7 | 测试补全 | 3-5天 | 长期质量保障 |

**建议立即执行Phase 1-4**（约3-5天），收益最高且风险可控。
