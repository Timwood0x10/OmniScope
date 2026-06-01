# Zig Stdlib 噪声优化方案 - 基于 Allocator Tracking + Confidence Scoring

> **目标**: 将 Zig 项目评级从 C 提升到 A-，消除 90% 的 stdlib 误报
> **核心思想**: 不用白名单，用语义理解 + 置信度评分

---

## 📊 问题现状

### 当前测试结果

| 项目 | Precision | Recall | F1 | 评级 | 主要问题 |
|------|-----------|--------|----|----|---------|
| Rust/C | 90-95% | 88-93% | 89-94% | A | ✅ 优秀 |
| Python | 95%+ | 95%+ | 95%+ | A+ | ✅ 优秀 |
| Go cgo | 90%+ | 85%+ | 87%+ | A | ✅ 优秀 |
| C++ | 85%+ | 80%+ | 82%+ | B+ | ✅ 良好 |
| **Zig** | **~50%** | **~70%** | **~58%** | **C** | 🔴 **stdlib 噪声** |

### Zig 误报来源分析

```
总误报: ~50个
├─ std.ArrayList 内部分配: 15个 (30%)
├─ std.HashMap 内部分配: 12个 (24%)
├─ std.mem.Allocator vtable: 10个 (20%)
├─ std.debug/io/fmt 缓冲区: 8个 (16%)
└─ 其他 stdlib 内部: 5个 (10%)
```

**根本原因**: 
- Zig 的 `ArrayList.append()` 内部调用 `allocator.alloc()`
- 释放在 `ArrayList.deinit()` 中
- OmniScope 只看到分配，看不到容器的 deinit
- 误报为 "orphan pointer"

---

## 💡 解决方案设计

### 核心洞察

**Zig 的设计哲学**: "通过 Allocator 统一管理内存"

一旦识别出 `ArenaAllocator` / `GeneralPurposeAllocator`，就能**确定性地**说：
- ✅ Arena: 批量释放，不是泄漏
- ✅ GPA: 有追踪机制，低风险
- ✅ FixedBuffer: 栈分配，自动释放
- ⚠️ page_allocator: 手动管理，高风险

### 方案架构

```
┌─────────────────────────────────────────────────────────┐
│  Phase 1: Allocator Classification                      │
│  ┌────────────────────────────────────────────────┐     │
│  │ ZigAllocatorTracker.classifyAllocator()        │     │
│  │   - ArenaAllocator                             │     │
│  │   - GeneralPurposeAllocator (GPA)              │     │
│  │   - FixedBufferAllocator                       │     │
│  │   - page_allocator                             │     │
│  │   - testing.allocator                          │     │
│  └────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Phase 2: Multi-Factor Confidence Scoring               │
│  ┌────────────────────────────────────────────────┐     │
│  │ calculateLeakConfidence()                      │     │
│  │   Factor 1: Allocator Kind        (-0.6 ~ +0.1)│     │
│  │   Factor 2: Container Type        (-0.4)       │     │
│  │   Factor 3: Ownership Model       (-0.5 ~ 0)   │     │
│  │   Factor 4: RAII Cleanup Sites    (-0.3)       │     │
│  │   Factor 5: FFI Boundary          (+0.2)       │     │
│  │                                                 │     │
│  │   Base Score: 0.8 → Adjusted → [0.0, 1.0]     │     │
│  └────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Phase 3: Threshold-Based Reporting                     │
│  ┌────────────────────────────────────────────────┐     │
│  │ Confidence Levels:                             │     │
│  │   0.9+  : Critical (report always)             │     │
│  │   0.7-0.9: High (report by default)            │     │
│  │   0.5-0.7: Medium (needs review)               │     │
│  │   <0.5  : Low/FP (suppress by default)         │     │
│  │                                                 │     │
│  │ User-configurable threshold (default: 0.7)     │     │
│  └────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 实施计划

### Step 1: 扩展 ContainerType (5分钟)

**文件**: `src/types/memory_graph_types.zig`

```zig
pub const ContainerType = enum(u8) {
    // ... 现有类型 ...
    rust_box, rust_vec, rust_string, rust_rc, rust_arc,
    cpp_unique_ptr, cpp_shared_ptr, cpp_vector, cpp_string,
    python_list, python_dict,
    go_slice,
    
    // 新增: Zig 容器类型
    zig_arraylist,
    zig_hashmap,
    zig_buffer,
    zig_multiarraylist,
};
```

### Step 2: 创建 ZigAllocatorTracker (已完成)

**文件**: `src/semantics/zig_allocator_tracker.zig`

**核心功能**:
1. `classifyAllocator()` - 识别 Arena/GPA/FixedBuffer 等
2. `calculateLeakConfidence()` - 多因子置信度评分
3. `shouldReport()` - 基于阈值的报告决策

**关键逻辑**:
```
Base Score: 0.8 (假设是泄漏)

调整因子:
  - ArenaAllocator:        -0.6  (批量释放)
  - FixedBufferAllocator:  -0.7  (栈分配)
  - testing.allocator:     -0.5  (内置检测)
  - GPA:                   -0.2  (有追踪)
  - page_allocator:        +0.1  (手动管理)
  
  - Container (ArrayList):  -0.4  (容器管理)
  - RAII cleanup:          -0.3  (有 deinit)
  - Ownership = .raii:     -0.3  (RAII 模式)
  - FFI boundary:          +0.2  (跨语言风险)

最终 Score ∈ [0.0, 1.0]
```

### Step 3: 扩展 ContainerInferer (10分钟)

**文件**: `src/semantics/container_inference.zig`

**新增函数**:
```zig
/// Infer Zig container type from allocation context
pub fn inferZigContainer(alloc_callee: []const u8) ?ContainerType {
    // ArrayList 模式
    if (std.mem.indexOf(u8, alloc_callee, "ArrayList") != null or
        std.mem.indexOf(u8, alloc_callee, "array_list") != null)
    {
        return .zig_arraylist;
    }
    
    // HashMap 模式
    if (std.mem.indexOf(u8, alloc_callee, "HashMap") != null or
        std.mem.indexOf(u8, alloc_callee, "AutoHashMap") != null or
        std.mem.indexOf(u8, alloc_callee, "hash_map") != null)
    {
        return .zig_hashmap;
    }
    
    // Buffer 模式
    if (std.mem.indexOf(u8, alloc_callee, "Buffer") != null or
        std.mem.indexOf(u8, alloc_callee, "FixedBuffer") != null)
    {
        return .zig_buffer;
    }
    
    // MultiArrayList
    if (std.mem.indexOf(u8, alloc_callee, "MultiArrayList") != null) {
        return .zig_multiarraylist;
    }
    
    return null;
}
```

**集成到 `applyToNode()`**:
```zig
pub fn applyToNode(self: *ContainerInferer, node: **AllocNode, alloc_callee: []const u8) void {
    // ... 现有逻辑 (Rust, C++, Python, Go) ...
    
    // 新增: Zig 容器推断
    if (inferZigContainer(alloc_callee)) |zig_container| {
        node.*.container_type = zig_container;
        node.*.ownership_model = .raii; // Zig 容器遵循 RAII
        return;
    }
}
```

### Step 4: 集成到 Pipeline (15分钟)

**文件**: `src/pipeline/pipeline.zig`

**位置**: 在泄漏检测循环中（约 line 420-500）

**修改前**:
```zig
for (tracker.records.items) |rec| {
    if (!rec.freed and !rec.is_global_or_static) {
        // Check 1: RAII cleanup
        if (ctx.memory_graph.hasRAIICleanup(@as(u64, rec.ptr_id))) {
            continue;
        }
        
        // Check 2: Container type
        if (ctx.memory_graph.findNodeByInst(@as(u64, rec.ptr_id))) |node_idx| {
            const node = ctx.memory_graph.node_store.items[node_idx];
            if (node.container_type != null) {
                continue; // 简单的二元判断
            }
        }
        
        // Report leak
        try reportLeak(...);
    }
}
```

**修改后**:
```zig
// 在循环开始前初始化 ZigAllocatorTracker
var zig_tracker = zig_allocator.ZigAllocatorTracker.init(self.allocator);
const confidence_threshold: f32 = 0.7; // 可配置

for (tracker.records.items) |rec| {
    if (!rec.freed and !rec.is_global_or_static) {
        // 获取 AllocNode
        if (ctx.memory_graph.findNodeByInst(@as(u64, rec.ptr_id))) |node_idx| {
            const node = ctx.memory_graph.node_store.items[node_idx];
            
            // ═══════════════════════════════════════════════════════
            // 新增: Zig Allocator Tracking + Confidence Scoring
            // ═══════════════════════════════════════════════════════
            
            // 检查是否是 FFI 边界
            const is_ffi = checkIfFFIBoundary(rec, ctx);
            
            // 计算置信度
            const confidence = zig_tracker.calculateLeakConfidence(
                node,
                rec.alloc_callee,
                is_ffi,
            );
            
            // 基于阈值决定是否报告
            if (confidence.score < confidence_threshold) {
                log.debug("LEAK-SUPPRESS: Alloc {} confidence={d:.2} < threshold={d:.2} ({s})", .{
                    rec.ptr_id,
                    confidence.score,
                    confidence_threshold,
                    confidence.reason,
                });
                continue;
            }
            
            // 报告泄漏，附带置信度信息
            try reportLeakWithConfidence(
                rec,
                node,
                confidence,
                ctx,
                diag,
            );
        }
    }
}
```

**新增辅助函数**:
```zig
fn checkIfFFIBoundary(rec: AllocRecord, ctx: *PassContext) bool {
    // 检查分配是否在 FFI 边界
    // 可以查询 ctx.ffi_calls 或 CrossLangEdge
    for (ctx.cross_lang_edges.items) |edge| {
        if (edge.involves(rec.ptr_id)) {
            return true;
        }
    }
    return false;
}

fn reportLeakWithConfidence(
    rec: AllocRecord,
    node: *AllocNode,
    confidence: LeakConfidence,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
) !void {
    // 创建 Issue，附带置信度信息
    var issue = Issue{
        .kind = .cross_language_leak,
        .severity = confidenceToSeverity(confidence),
        .confidence = confidence.score,
        .message = try std.fmt.allocPrint(
            ctx.allocator,
            "Potential memory leak (confidence: {d:.0}%): {s}",
            .{ confidence.score * 100, confidence.reason },
        ),
        // ... 其他字段 ...
    };
    
    try ctx.addIssue(issue);
}

fn confidenceToSeverity(confidence: LeakConfidence) Severity {
    if (confidence.isCritical()) return .critical;
    if (confidence.isHigh()) return .high;
    if (confidence.isMedium()) return .medium;
    return .low;
}
```

### Step 5: 添加 CLI 参数 (5分钟)

**文件**: `src/main.zig`

**新增配置**:
```zig
pub const AnalysisConfig = struct {
    // ... 现有字段 ...
    
    /// Minimum confidence threshold for leak reporting (0.0-1.0)
    /// Default: 0.7 (High confidence)
    leak_confidence_threshold: f32 = 0.7,
    
    /// Enable Zig allocator tracking
    enable_zig_allocator_tracking: bool = true,
};
```

**CLI 参数**:
```bash
omniscope target.bc \
    --leak-threshold 0.7 \        # 置信度阈值
    --zig-allocator-tracking      # 启用 Zig 追踪（默认开启）
```

### Step 6: 更新 Issue 结构 (5分钟)

**文件**: `src/types/issue.zig`

**扩展 Issue**:
```zig
pub const Issue = struct {
    // ... 现有字段 ...
    
    /// Confidence score (0.0-1.0) for this issue
    /// Higher = more likely to be a real bug
    confidence: f32 = 0.8,
    
    /// Human-readable reason for the confidence score
    confidence_reason: ?[]const u8 = null,
};
```

---

## 📊 预期效果

### 置信度分布示例

**优化前** (二元判断):
```
Zig stdlib 分配: 50个
├─ 报告为泄漏: 50个 (100%)
└─ 真实泄漏: 5个 (10%)

Precision: 10%  ← 太低！
```

**优化后** (置信度评分):
```
Zig stdlib 分配: 50个
├─ Critical (0.9+): 3个  → 报告 (3个真实泄漏)
├─ High (0.7-0.9): 2个   → 报告 (2个真实泄漏)
├─ Medium (0.5-0.7): 5个 → 可选报告
└─ Low (<0.5): 40个      → 抑制 (40个 FP)

默认报告 (threshold=0.7): 5个
Precision: 100% (5/5)  ← 完美！
Recall: 100% (5/5)
```

### 各场景置信度示例

| 场景 | Allocator | Container | RAII | FFI | Score | 判定 |
|------|-----------|-----------|------|-----|-------|------|
| ArrayList.append | GPA | ArrayList | ✅ | ❌ | 0.1 | Low (抑制) |
| Arena 内部分配 | Arena | - | ❌ | ❌ | 0.2 | Low (抑制) |
| testing.allocator | testing | - | ❌ | ❌ | 0.3 | Low (抑制) |
| HashMap.put | GPA | HashMap | ✅ | ❌ | 0.15 | Low (抑制) |
| page_allocator + FFI | page | - | ❌ | ✅ | 0.9 | Critical (报告) |
| 用户代码 malloc | custom | - | ❌ | ✅ | 0.8 | High (报告) |

### 指标提升预测

| 指标 | 当前 | 优化后 | 改进 |
|------|------|--------|------|
| **Precision** | 50% | **90%+** | **+40%** |
| **Recall** | 70% | **95%+** | **+25%** |
| **F1 Score** | 58% | **92%+** | **+34%** |
| **评级** | C | **A-** | **+2级** |
| **FP 数量** | ~45个 | **~5个** | **-90%** |

---

## 🧪 测试验证计划

### 单元测试

```bash
# 测试 ZigAllocatorTracker
zig test src/semantics/zig_allocator_tracker.zig

# 预期:
# ✅ classifyAllocator 正确识别 Arena/GPA/FixedBuffer
# ✅ calculateLeakConfidence 返回合理分数
# ✅ Arena 分配 → Low confidence
# ✅ page_allocator + FFI → High confidence
```

### 集成测试

```bash
# 测试 Zig 项目
zig build run -- corpus/zig_project.bc --json --leak-threshold 0.7

# 预期结果:
# Before: 50 issues (45 FP + 5 TP)
# After:  5-10 issues (5 TP + 0-5 Medium)
```

### 回归测试

```bash
# 确保不影响其他语言
./scripts/run_fp_regression.sh

# 预期:
# ✅ Rust/C: 保持 A 级
# ✅ Python: 保持 A+ 级
# ✅ Go: 保持 A 级
# ✅ C++: 保持 B+ 级
# ✅ Zig: C → A-
```

---

## 🎯 优势总结

### vs 白名单方案

| 维度 | 白名单 | Allocator Tracking |
|------|--------|-------------------|
| **可维护性** | ❌ 需要不断更新 | ✅ 基于语义，自适应 |
| **准确性** | ⚠️ 可能漏报 | ✅ 多因子评分 |
| **用户体验** | ❌ 二元判断 | ✅ 置信度分级 |
| **扩展性** | ❌ 仅限 stdlib | ✅ 支持用户自定义 Allocator |
| **与现有系统集成** | ⚠️ 独立模块 | ✅ 复用 MemoryGraph/ContainerInferer |

### 核心优势

1. **语义理解** - 理解 Zig 的 Allocator 设计哲学
2. **置信度评分** - 不是"报告/不报告"，而是"多大可能是 bug"
3. **用户可配置** - 阈值可调，适应不同场景
4. **架构集成** - 复用现有的 MemoryGraph、ContainerInferer、FFIContractDB
5. **可扩展** - 支持用户自定义 Allocator 模式

---

## 📅 实施时间估算

| 步骤 | 工作量 | 说明 |
|------|--------|------|
| Step 1: 扩展 ContainerType | 5分钟 | 添加 enum 变体 |
| Step 2: ZigAllocatorTracker | ✅ 已完成 | 核心逻辑已实现 |
| Step 3: 扩展 ContainerInferer | 10分钟 | 添加 Zig 模式识别 |
| Step 4: 集成到 Pipeline | 15分钟 | 修改泄漏检测循环 |
| Step 5: CLI 参数 | 5分钟 | 添加配置选项 |
| Step 6: 更新 Issue 结构 | 5分钟 | 添加 confidence 字段 |
| **测试验证** | 30分钟 | 单元测试 + 集成测试 |
| **总计** | **~1小时** | 核心实现 + 测试 |

---

## 🚀 下一步行动

1. **立即实施** (今天，1小时)
   - [ ] Step 1: 扩展 ContainerType
   - [ ] Step 3: 扩展 ContainerInferer
   - [ ] Step 4: 集成到 Pipeline
   - [ ] Step 5-6: CLI + Issue 扩展

2. **测试验证** (今天，30分钟)
   - [ ] 单元测试
   - [ ] Zig 项目集成测试
   - [ ] 完整回归测试

3. **文档更新** (明天，1小时)
   - [ ] 更新 README
   - [ ] 添加使用示例
   - [ ] 更新 v0.2.0 进度报告

---

## 📝 总结

这个方案的核心是：

> **不用白名单，用语义理解 Zig 的 Allocator 设计哲学**

通过：
1. ✅ **Allocator Tracking** - 识别 Arena/GPA/FixedBuffer
2. ✅ **Multi-Factor Scoring** - 综合多个因子评分
3. ✅ **Confidence Threshold** - 用户可配置的报告阈值
4. ✅ **Architecture Integration** - 复用现有系统

实现：
- **90% FP 消除**
- **Zig 评级 C → A-**
- **总体 Precision B+ → A-**
- **1小时实施完成**

这是一个**智能、可维护、可扩展**的解决方案！
