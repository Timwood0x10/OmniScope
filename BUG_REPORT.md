# OmniScope Bug Report & Technical Debt

**Date**: 2026-05-22
**Version**: v0.1.9 (dev branch)
**Consolidated from**: `plan/bugs.md`, `plan/bugs_full_review.md`, `code_review_technical_debt.md`, 本次 code review

---

## Part 1: Active Bugs (待修复)

### P0 — integer_overflow 映射到错误的 IssueKind

**File**: `src/pass/analysis/issue/integer_overflow.zig:86`
**Source**: 本次 code review

```zig
const issue = Issue.init(
    .buffer_overflow, // 错误 — 应该是 .integer_overflow
    ...
);
```

`IssueKind`（定义在 `src/common/types.zig:151`）没有 `integer_overflow` 变体。代码用 `.buffer_overflow` 作为替代，导致 SARIF/JSON 输出中 **CWE 编号错误**（输出 CWE-120 而非 CWE-190）。

**修复**: 在 `IssueKind` 枚举中添加 `integer_overflow`，补充 `toString()`、`toCweId()`、`toDescription()`。

---

### P1 — call_graph.zig ptr_args_owned 错误路径内存泄漏

**File**: `src/pass/analysis/call_graph.zig:529-561`
**Source**: 本次 code review

```zig
var ptr_args_list = std.ArrayList(u32).initCapacity(ctx.allocator, 8) catch return;
//     ^^^ OOM 时 caller_name_owned/callee_name_owned 泄漏（errdefer 不会触发）

const ptr_args_owned = try ptr_args_list.toOwnedSlice(ctx.allocator);
//     ^^^ 已分配，无 errdefer 保护

try ctx.addCrossLangEdge(cross_edge);
//     ^^^ 失败时 ptr_args_owned 泄漏
```

两个泄漏路径：
1. `catch return` 绕过了 `caller_name_owned`/`callee_name_owned` 的 errdefer
2. `ptr_args_owned` 在 `addCrossLangEdge` 之前没有 errdefer

**修复**: `catch return` 改为 `catch |e| return e`（传播错误，触发 errdefer）。`toOwnedSlice` 之后加 `errdefer ctx.allocator.free(ptr_args_owned)`。

---

### P1 — ptr_lifetime.zig is_ffi_func 门控过于严格

**File**: `src/pass/analysis/ptr_lifetime.zig:542, 844-866`
**Source**: `plan/bugs.md` P1-1 — **仍然存在**

```zig
// Line 542: 门控所有 MemoryGraph 操作
const mg_effective = if (is_ffi_func) mem_graph else null;

// Line 844-866: 门控 call edge 记录
if (is_ffi_func) {
    // trackCallArg / trackCallRet
}
```

`is_ffi_func` 仅在函数名存在于 `ffi_func_names` HashSet 中时为 true。如果函数通过函数指针间接调用 FFI 函数但自身不在 `ffi_func_names` 中，其 call edge 不会被记录。L542 的门控更严重——阻止了非 FFI 函数的**所有** MemoryGraph 写入。

---

### P2 — ffi_detector.zig LLVM opcode 比较方式不一致

**File**: `src/pass/analysis/ffi_detector.zig` lines 443, 482, 555
**Source**: 本次 code review

仍使用 `@enumFromInt(opcode)` 模式，而 `malloc_check.zig` 和 `lock.zig` 已正确修复为直接 `c.LLVMCall` 比较。`@enumFromInt` 在 opcode 值不是有效枚举变体时会 panic。

---

### P2 — pipeline.zig CallSiteIndex 与 ptr-lifetime 重复遍历 IR

**File**: `src/pipeline/pipeline.zig:122-151`
**Source**: `plan/bugs.md` P2-3 — **仍然存在**

CallSiteIndex 构建和 ptr-lifetime 分析各自独立遍历全部 IR（function → basic block → instruction），产生 2× LLVM C API 调用开销。Profile 显示 `"CallSiteIndex build: 34ms"`。

---

### M1 — sarif.zig 借用切片无所有权

**File**: `src/output/sarif.zig:46-52`
**Source**: `plan/bugs_full_review.md` BUG-17 — **仍然存在**

```zig
pub fn initWithUri(..., tool_name: []const u8, tool_version: []const u8, uri: []const u8) SarifOutput {
    return .{
        .tool_name = tool_name,    // 借用，非拥有
        .tool_version = tool_version,
        .tool_uri = uri,
    };
}
```

如果调用方在 `generate()` 之前释放这些字符串，会产生悬空指针。结构体有 `allocator` 字段但未用于复制字符串。

---

### L4 — 版本号不一致

**File**: `src/main.zig:608`
**Source**: `code_review_technical_debt.md` L4

`--version` 输出 `v0.1.8`，SARIF/JSON 输出 `0.1.9`。

---

## Part 2: 已修复的 Bug（历史记录）

### v0.1.9 本次修复（2026-05-22）

| Bug | 文件 | 问题 | 修复 |
|-----|------|------|------|
| double deinit | pipeline.zig:105-122 | errdefer + defer 双重调用 deinit → 崩溃 | 删除 errdefer 块 |
| MissingDependency | lock.zig:34 | lock pass 依赖未注册的 cfg/dfg/alias | 删除无用依赖 |
| _ZN 消歧缺失 | ffi_language_classifier.zig:552 | `_R` 前缀（Rust v0 mangling）未识别 | 添加 Layer 0 `_R` 检查 |
| formatViolationMessage OOM | lifetime/boundary.zig | `catch "string literal"` 返回编译期字符串，caller free → 崩溃 | 改为 `![]const u8` + `try` |
| ffi_type_mismatch callee-side | ffi_type_mismatch.zig:784 | Rust 调用 C++ `_ZN` 未标记为 FFI 边界 | 添加 callee 侧 isRustMangledName 检查 |
| ffi_enhancement 全 _ZN 当 Rust | ffi_enhancement.zig:411 | isRustMangledUser 对所有 _ZN 返回 true | 添加 ffi_language_classifier 守卫 |
| noise_filter 本地实现不完整 | noise_filter.zig:775 | 本地 isRustMangledName 只检查 hash 后缀 | 委托给 ffi_language_classifier |

### v0.1.8 修复（2026-05-06，来源 plan/bugs_full_review.md）

| Bug | 严重度 | 文件 | 问题 | 修复 |
|-----|--------|------|------|------|
| BUG-1 | CRITICAL | ffi_analysis.zig:328 | free_sites.get 返回副本，append 丢失 | `get` → `getPtr` |
| BUG-2 | CRITICAL | alias.zig:67 | deinit 传多余 allocator 参数 | 删除参数 |
| BUG-3 | CRITICAL | pipeline.zig:97 | `catch unreachable` OOM 时 panic | 改为 `try` |
| BUG-5 | HIGH | formatter.zig:141 | JSON 大写 hex `
` | 改为 `{x:0>4}` 小写 |
| BUG-6 | HIGH | call_graph.zig:517 | extractCrossLangEdges OOM 泄漏 | 添加 errdefer |
| BUG-9 | HIGH | pass.zig:311 | 同 BUG-3 | 改为 `try` |
| BUG-12 | MEDIUM | taint.zig:490 | 测试缺少 allocator 参数 | 补充参数 |
| BUG-13 | MEDIUM | sarif.zig:259 | writeFloat catch unreachable | 错误传播 |
| BUG-15 | MEDIUM | ffi_analysis.zig:694 | 测试传 undefined store | 正确初始化 |
| BUG-16 | HIGH | main.zig:83 | 同 BUG-5 大写 hex | 改为小写 |
| BUG-19 | MEDIUM | call_graph.zig:632 | isSink 测试期望不一致 | 修正测试 |
| BUG-20 | LOW | 多文件 | 版本号不一致 | 统一为 v0.1.8 |
| BUG-21 | MEDIUM | rust_ffi_auditor.zig:550 | valuesMayAlias 对称情况返回 false | 改为 true |
| BUG-22 | HIGH | ffi_analysis.zig:337 | free_bb_map.get 返回副本 | `get` → `getPtr` |
| BUG-23 | LOW | call_graph.zig:385 | propagateTaint 无用 HashMap | 删除死代码 |
| BUG-24 | HIGH | rust_ffi_auditor.zig:230 | detectCrossLangMismatch 高误报 | 添加 ptrOriginatesFromRustAlloc 追踪 |

### 其他已修复（来源 plan/bugs.md）

| Bug | 文件 | 问题 | 修复 |
|-----|------|------|------|
| P0-1 | danger_surface.zig:76,87 | 传指令指针而非函数指针 | 改用 markFunctionFromInst |
| P1-2 | ptr_lifetime.zig:877 | 删除 BitCast propagateOrigin | 已恢复（L975-990） |
| P2-2 | pass.zig:732 | cross_edge_by_callee 覆盖 | 改为 StringHashMap(ArrayList(u32)) |
| BUG-8 | rust_ffi_auditor.zig:231 | free() 误报 | 添加 ptrOriginatesFromRustAlloc |
| BUG-11 | ffi_analysis.zig:376 | O(n*m) 暴力匹配 | 改为 HashMap 索引 O(n+m) |
| BUG-17 | sarif.zig:259 | writeFloat catch unreachable | 正确错误处理 |

---

## Part 3: Technical Debt（已验证）

原始报告: `code_review_technical_debt.md`（2025-01）。每个条目于 2026-05-22 重新验证。

### CRITICAL（5 项 — 全部验证存在）

| ID | 文件 | 验证 | 问题 |
|----|------|------|------|
| C1 | pointer_ownership.zig:411-613 | **存在** | 8 次独立全模块函数遍历 |
| C2 | pointer_ownership.zig:247-409 | **存在** | 3 数据源合并: MemoryGraph + GlobalAllocTracker + IR scan |
| C3 | memory_graph.zig:805-871 | **存在** | isLeaked/isDoubleFreed O(N²) 嵌套循环，已有索引未使用 |
| C4 | memory_graph.zig:178-183 | **部分存在** | 6 字段（非 5），4 个二级索引部分使用 |
| C5 | zone_classifier.zig:348-385 | **存在** | classifyFunction 零缓存，纯函数每次都线性扫描 |

### HIGH（13 项 — 全部验证存在）

| ID | 文件 | 验证 | 问题 |
|----|------|------|------|
| H1 | pass.zig:192-279 | **存在** | PassContext 29 字段，上帝对象 |
| H2 | pass.zig:459-549 | **存在** | addIssue 91 行 |
| H3 | ffi_boundary.zig:221-473 | **存在** | checkCallForFFI 253 行 |
| H4 | memory_graph.zig:296 | **存在** | 每个 AllocNode 独立 HashMap |
| H5 | memory_graph.zig:910-922 | **部分存在** | FFI 集合顶层调用间不缓存（递归内已缓解） |
| H6 | memory_graph.zig:957-964 | **存在** | 别名闭包无跨调用缓存 |
| H7 | call_graph.zig:384-448 | **存在** | getFFIBoundaryReachableFunctions 每次重建反向图 |
| H8 | call_graph.zig:672-744 | **存在** | classifyArgDirectionByName 无缓存 |
| H9 | zone_classifier + ffi_noise_filter | **部分存在** | 概念重叠（都检查 __cxa_*），具体模式不同 |
| H10 | main.zig:65-71 | **存在** | AnalyzeResult 按值嵌入 Pipeline |
| H11 | main.zig:359-363 | **存在** | defer 逻辑简单，但 deinitAnalyzeResult 未使用 |
| H12 | main.zig:118-119 | **存在** | arg_copy 无 errdefer，append 失败泄漏 |
| H13 | log.zig:10 | **存在** | 全局可变日志级别，无同步原语 |

### MEDIUM（14 项 — 全部验证存在）

| ID | 文件 | 验证 | 问题 |
|----|------|------|------|
| M1 | ptr_lifetime.zig:219-344 | **存在** | 4 层噪声过滤依次执行 |
| M2 | ptr_lifetime.zig:129-155 | **存在** | FreeSiteList 手写 ArrayList |
| M3 | ptr_lifetime.zig:363-419 | **存在** | reverse_alias 每次重建 |
| M4 | ptr_lifetime.zig:497-502 | **存在** | 硬编码 1000/50000 限制 |
| M5 | danger_surface.zig:150-170 | **存在** | traceAliasClosure 无深度限制 |
| M6 | danger_surface.zig:172-180 | **存在** | markFunctionFromInst 重复实现 |
| M7 | ffi_boundary.zig:277-278 | **存在** | 间接调用名称内存管理复杂 |
| M8 | ffi_boundary.zig:647-752 | **存在** | resolveIndirectCallTarget 106 行 |
| M9 | pointer_ownership.zig:500-531 | **存在** | flow_graph 反向索引即时构建 |
| M10 | pass.zig:624-632 | **存在** | getOrComputeZone 类型擦除 |
| M11 | build.zig:193-294 | **存在** | 7 个测试步骤重复模式 |
| M12 | build.zig:4-18 | **存在** | 硬编码 LLVM 路径和版本 |
| M13 | types.zig:30-105 | **存在** | Location 无 deinit/free/clone |
| M14 | types.zig:319-336 | **存在** | 置信度阈值魔法数字 |

### LOW（9 项验证存在，1 项移除）

| ID | 文件 | 验证 | 问题 |
|----|------|------|------|
| L1 | main.zig:179-180 | **存在** | 2 个注释掉的 pass 注册 |
| L2 | main.zig:571-574 | **存在** | countFunction 死代码 |
| L3 | main.zig:624-645 | **存在** | 测试覆盖不足，2 个测试实质相同 |
| L4 | main.zig:608 | **存在** | 版本号 0.1.8 vs 0.1.9 |
| L5 | build.zig:9-11 | **存在** | .linux 和 else 返回相同值 |
| L6 | root.zig:168-177 | **存在** | 同一模块 @import 重复 10 次 |
| L7 | log.zig:18-35 | **存在** | [INFO]/[DEBUG] 前缀与 std.log 级别重复 |
| L8 | semantics/call_graph.zig:315 | **部分存在** | max_depth=10 硬编码在调用方 |
| L9 | zone_classifier.zig:341-346 | **已移除** | 注释与实现一致，无不匹配 |
| L10 | noise_filter.zig:775-807 | **存在** | isRustMangledName 已委托，其余语言检测函数仍独立实现 |

---

## Part 4: 假阳性汇总

| 来源 | ID | 原始描述 | 删除原因 |
|------|----|---------|---------|
| code_review_technical_debt.md | L9 | isAlphaNumeric 注释与实现不匹配 | 注释准确描述代码 |
| plan/bugs.md | P0-1 | 传指令指针而非函数指针 | 已修复为 markFunctionFromInst |
| plan/bugs.md | P1-2 | 删除 BitCast propagateOrigin | 已恢复，代码完整 |
| plan/bugs.md | P2-2 | cross_edge_by_callee 覆盖 | 已修复为 ArrayList 存储 |
| plan/bugs_full_review.md | BUG-1~24 | 24 个 bug | 全部在 v0.1.8 修复 |
| plan/bugs_full_review.md | BUG-8 | free() 误报 | 已添加 ptrOriginatesFromRustAlloc |
| plan/bugs_full_review.md | BUG-11 | O(n*m) 暴力匹配 | 已优化为 HashMap O(n+m) |
| code_review_technical_debt.md | H1 | "30+ 字段" | 实际 29 字段 |
| code_review_technical_debt.md | C4 | "5 个冗余索引" | 实际 6 字段（2 主 + 4 二级） |
| code_review_technical_debt.md | H5 | "重复构建 FFI 集合" | 递归内已缓解，仅顶层间不缓存 |
| code_review_technical_debt.md | H11 | "defer 逻辑复杂" | 实际 4 行，不复杂 |

---

## Part 5: 统计

| 类别 | 数量 |
|------|------|
| 活跃 Bug（待修复） | 6 |
| 已修复 Bug（v0.1.8 + v0.1.9） | 27 |
| 假阳性（已删除/修正） | 11 |
| Technical Debt CRITICAL | 5 |
| Technical Debt HIGH | 13 |
| Technical Debt MEDIUM | 14 |
| Technical Debt LOW | 9 |
| **合计** | **85** |

### 修复优先级

| 优先级 | 项目 | 说明 |
|--------|------|------|
| 立即 | P0: integer_overflow IssueKind | SARIF 输出 CWE 错误 |
| 立即 | P1: ptr_args_owned errdefer | 错误路径内存泄漏 |
| 立即 | L4: 版本号 0.1.8 → 0.1.9 | 用户可见 |
| 短期 | C3: isLeaked/isDoubleFreed 用已有索引 | 消除 O(N²) |
| 短期 | C5: zone_classifier 加 HashMap 缓存 | 最易获得的性能提升 |
| 短期 | C1: 8 次遍历合并为单次 | 大模块性能 5-8× 提升 |
| 中期 | H12: arg_copy 加 errdefer | 内存泄漏 |
| 中期 | M5: traceAliasClosure 加深度限制 | 栈溢出风险 |
| 中期 | P2: ffi_detector opcode 比较统一 | 代码一致性 |
