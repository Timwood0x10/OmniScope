# OmniScope 安全审计报告

> **审计日期**: 2026-04-23 · **审计范围**: `src/` 全部 Zig 源文件 + CI/CD 工作流 + 构建系统 · **版本**: 0.1.5 · **方法**: 人工代码审计

***

## 1. 概览

| 项目        | 详情                                             |
| --------- | ---------------------------------------------- |
| **项目名称**  | OmniScope                                      |
| **项目描述**  | 基于 LLVM IR 的跨语言 FFI 静态安全分析框架                   |
| **主要语言**  | Zig (0.15.2+)                                  |
| **外部依赖**  | LLVM 21/22 (LLVM-C API)                        |
| **审计文件数** | 73+ Zig 源文件 + 3 CI/CD 工作流 + build.zig          |
| **发现问题数** | 52 (1 Critical / 18 High / 21 Medium / 12 Low) |
| **综合评分**  | 6.5 / 10                                       |

***

## 2. 问题汇总

### 严重性分布

| 严重等级             | 数量     | 占比    |
| ---------------- | ------ | ----- |
| 🔴 严重 (Critical) | 1      | 1.9%  |
| 🔴 高危 (High)     | 18     | 34.6% |
| 🟠 中危 (Medium)   | 21     | 40.4% |
| 🟡 低危 (Low)      | 12     | 23.1% |
| **合计**           | **52** | 100%  |

### 按类别分布

| 类别                           | 数量 |
| ---------------------------- | -- |
| 内存安全（缓冲区溢出、UAF、double-free）  | 12 |
| 逻辑错误（分析正确性）                  | 14 |
| 输出注入（JSON/SARIF 未转义）         | 6  |
| 资源管理（内存泄漏、悬空指针）              | 8  |
| CI/CD 安全                     | 6  |
| 错误处理（catch unreachable、吞没错误） | 4  |
| 类型安全（指针截断、整数溢出）              | 2  |

***

## 3. 严重 (Critical) 问题

### BUG-001 \[Critical] ffi\_detector.zig — 类型错误导致三类漏洞检测完全失效

- **文件**: `src/pass/analysis/ffi_detector.zig` 第 437 行
- **类别**: 类型安全 / 编译错误

**描述**: `callsDangerousFunction` 将 `FunctionInfo`（Zig 结构体）直接传递给 `c.LLVMGetFirstBasicBlock(func)`，后者期望 `c.LLVMValueRef`（`*const opaque{}`）。Zig 不允许将结构体隐式转换为指针类型。对比同文件第 476 行 `hasUseAfterFreePattern` 正确使用了 `func.func.raw`。

```zig
// 错误代码 (第 437 行)
const bb = c.LLVMGetFirstBasicBlock(func);  // func 是 FunctionInfo，不是 LLVMValueRef

// 正确代码 (第 476 行)
const bb = c.LLVMGetFirstBasicBlock(func.func.raw);  // 正确解包
```

**影响**: `detectCommandInjection`、`detectBufferOverflow`、`detectFormatString` 三个漏洞检测函数全部调用 `callsDangerousFunction`，因此**命令注入、缓冲区溢出、格式化字符串三类漏洞检测完全失效**。

**修复**: 将 `func` 改为 `func.func.raw`。

***

## 4. 高危 (High) 问题

### BUG-002 \[High] memory\_pool.zig — free\_node\_pool 扩容导致 free\_list 悬空指针

- **文件**: `src/perf/memory_pool.zig` 第 62-98 行
- **类别**: 内存安全 / 悬空指针

**描述**: `alloc()` 从空闲列表取出节点后，`free()` 将节点追加到 `free_node_pool`（ArrayList），并将该节点的指针存入 `free_list` 链表。当 `free_node_pool` 因 `append` 导致内部缓冲区重新分配时，之前存储在 `free_list` 中的指针全部失效（悬空指针）。后续 `alloc()` 从 `free_list` 取出节点时将解引用悬空指针。

**影响**: 未定义行为，可能崩溃或数据损坏。这是本项目最严重的内存安全 bug。

**修复**: 改用索引而非指针链接空闲节点，或在 ArrayList 扩容时重建 free\_list 链。

***

### BUG-003 \[High] memory\_pool.zig — 重复释放导致空闲列表污染

- **文件**: `src/perf/memory_pool.zig` 第 92-98 行
- **类别**: 内存安全 / 重复释放

**描述**: `free()` 方法没有验证 `item` 指针是否已存在于空闲列表中，也没有验证指针是否属于此内存池。同一指针被 `free()` 两次会导致：空闲列表出现环/重复项；`total_freed` 超过 `total_allocated` 导致 `in_use` 统计下溢；后续 `alloc()` 返回仍在使用中的内存。

**影响**: 数据竞争和内存损坏。

**修复**: 在 `free()` 中添加重复释放检查和指针归属验证。

***

### BUG-004 \[High] memory\_pool.zig — ArenaAllocator 整数溢出

- **文件**: `src/perf/memory_pool.zig` 第 164 行
- **类别**: 整数溢出

**描述**: `alloc_size = @max(len + alignment, block_size)` 中 `len + alignment` 在 `len` 接近 `usize` 最大值时可能溢出，导致分配过小的缓冲区。

**修复**: 使用 `@addWithOverflow` 或 `std.math.add` 进行溢出检查。

***

### BUG-005 \[High] pointer\_ownership.zig — BFS 队列固定大小导致分析不完整

- **文件**: `src/pass/analysis/pointer_ownership.zig` 第 533-561 行
- **类别**: 逻辑错误 / 安全分析完整性

**描述**: `markAllocSitesReachingValue()` 使用固定大小的 BFS 队列 `bfs_queue: [64]u32`。当反向流图中到达目标值的路径深度超过 64 个节点时，队列溢出导致 BFS 提前终止，静默丢弃超出容量限制的节点。

**影响**: 对于具有深度指针传播链的大型 LLVM IR，所有权转移分析将不完整，本应被标记为 `transferred = true` 的分配站点将被遗漏，导致内存泄漏误报。

**修复**: 改用动态分配的队列。

***

### BUG-006 \[High] alias.zig — getTypeId 指针截断破坏 TBAA 分组

- **文件**: `src/pass/analysis/alias.zig` 第 268-270 行
- **类别**: 类型安全 / 指针截断

**描述**: `getTypeId` 使用 `@intFromPtr(type_ref)` 将 64 位 `c.LLVMTypeRef` 截断为 `u32`。在 64 位系统上高 32 位被丢弃，不同 LLVM 类型可能获得相同的 type\_id。

**影响**: 不同类型的指针可能被归为同一 TBAA 组，产生错误的 alias 关系——不相关的指针被报告为 may-alias。

**修复**: 使用 `AutoHashMap` 直接以 `LLVMTypeRef` 为键，或使用 `u64` 作为 type\_id。

***

### BUG-007 \[High] call\_graph.zig — 间接调用解析中无符号整数下溢

- **文件**: `src/pass/analysis/call_graph.zig` 第 115 行
- **类别**: 整数下溢 / 越界访问

**描述**: `resolveIndirectCall` 中操作数索引计算：`num_operands - param_count + i`。如果 `num_operands < param_count`（如使用默认参数），`c_uint` 无符号减法将下溢为巨大值，传给 `LLVMGetOperand` 导致越界访问。

**影响**: 对某些 LLVM IR 输入可能导致越界内存访问或 panic。

**修复**: 添加 `num_operands > param_count` 前置检查。

***

### BUG-008 \[High] call\_graph.zig — 指针相等比较 LLVM 类型

- **文件**: `src/pass/analysis/call_graph.zig` 第 107-108 行
- **类别**: 逻辑错误

**描述**: `resolveIndirectCall` 使用 `==` 比较两个 `c.LLVMTypeRef`（指针值），而非比较类型本身的结构。两个结构相同但地址不同的 LLVM 类型会被错误地认为不相等。

**影响**: 间接调用解析产生错误的候选集，调用图不准确。

**修复**: 使用 `LLVMGetTypeKind` 或结构化类型比较。

***

### BUG-009 \[High] graph.zig — getIssuesBySeverity 内存所有权不一致导致泄漏

- **文件**: `src/dataflow/graph.zig` 第 384-418 行
- **类别**: 资源泄漏

**描述**: `getIssuesBySeverity()` 通过 `dupe` 新分配 message 字符串，但将 `owned` 设为 `false`。调用者调用 `Issue.deinit()` 时不会释放 message，造成内存泄漏。此外，OOM 时返回部分初始化的数据。

**修复**: 设置 `owned = true` 或使用不同的所有权模型。

***

### BUG-010 \[High] graph.zig — clear() 后 HashMap 残留悬空指针

- **文件**: `src/dataflow/graph.zig` 第 492-517 行
- **类别**: 内存安全

**描述**: `clear()` 释放了边索引的内存，但 `clearRetainingCapacity()` 后 HashMap 中可能残留指向已释放内存的值指针。在 `clear()` 和重新填充之间的窗口期内访问 HashMap 将解引用已释放内存。

**修复**: 确保使用正确的 clear 语义，或在 clear 后使用 `clearAndFree` 类操作。

***

### BUG-011 \[High] taint\_state.zig — TOCTOU 竞态条件

- **文件**: `src/pass/analysis/taint_state.zig` 第 90-125 行
- **类别**: 线程安全

**描述**: `setValueTaint()` 和 `getValueTaint()` 各自独立获取和释放互斥锁。`handleInstruction()` 系列函数在同一指令处理中先调用 `getValueTaint()` 再调用 `setValueTaint()`，两次调用之间锁被释放，存在 TOCTOU 竞态条件。

**影响**: 多线程场景下污点状态可能丢失或覆盖。当前单线程使用不受影响，但未来引入并行分析时将成为严重问题。

**修复**: 提供复合操作接口，在单次加锁内完成读-改-写。

***

### BUG-012 \[High] ffi\_boundary.zig — demangleRustName 手工解析器缺少畸形输入防护

- **文件**: `src/pass/analysis/ffi_boundary.zig` 第 459-523 行
- **类别**: 输入验证

**描述**: `demangleRustName` 手工解析 `_ZN...E` 符号名，长度解析 `len = len * 10 + ...` 没有溢出检查，且不验证 `pos + len` 是否在有效范围内。对畸形 LLVM IR 模块可能导致越界读取或无限循环。

**影响**: 处理恶意构造的 LLVM IR 时可能导致越界读取或 DoS。

**修复**: 添加完整的边界检查和最大长度限制。

***

### BUG-013 \[High] cpp\_fp\_reduction.zig — BFS 队列固定大小导致检测不完整（两处）

- **文件**: `src/pass/analysis/cpp_fp_reduction.zig` 第 438-441 行, 第 754-756 行
- **类别**: 逻辑错误

**描述**: `isFunctionLevelNullGuarded` 和 `findFreePath` 均使用固定大小 `bfs_queue: [64]u32`。对大型数据流图，64 节点限制导致搜索不完整。

**影响**: null 检查保护判断和释放路径搜索不完整，产生误报。

**修复**: 改用动态分配的队列。

***

### BUG-014 \[High] ffi\_detector.zig — LLVMGetValueName 返回值未做 null 检查

- **文件**: `src/pass/analysis/ffi_detector.zig` 第 486-487 行
- **类别**: 空指针解引用

**描述**: `hasUseAfterFreePattern` 中 `c.LLVMGetValueName(called_func)` 返回值未做 null 检查就直接传给 `std.mem.span`。

**影响**: 对某些 LLVM IR 输入可能导致运行时 panic。

**修复**: 添加 null 检查。

***

### BUG-015 \[High] output/sarif.zig — 规则描述未转义（JSON 注入）

- **文件**: `src/output/sarif.zig` 第 105-107 行
- **类别**: 输出注入 / JSON 注入

**描述**: `generate()` 方法中 `rule.toDescription()` 返回的字符串通过 `{s}` 直接插入 JSON，未调用 `writeEscapedString`。

**影响**: 生成无效的 SARIF JSON，可能导致 GitHub Code Scanning 等下游工具解析失败或产生安全绕过。

**修复**: 对所有动态字符串使用 `writeEscapedString`。

***

### BUG-016 \[High] output/formatter.zig — SARIF/JSON 输出多个字段未转义

- **文件**: `src/output/formatter.zig` 第 171-172, 224-228, 236 行
- **类别**: 输出注入 / JSON 注入

**描述**: `formatSarif()` 中 `vuln.description`、`vuln.vuln_type`、`vuln.source_location` 等字段通过 `{s}` 直接插入 JSON 未转义。同文件 `formatJson()` 对 `description` 正确使用了 `writeEscapedString`，说明这是遗漏。

**影响**: 漏洞描述包含 JSON 特殊字符时将生成无效输出。

**修复**: 统一使用 `writeEscapedString`。

***

### BUG-017 \[High] report/sarif.zig — reason 字段未转义

- **文件**: `src/report/sarif.zig` 第 387 行
- **类别**: 输出注入 / JSON 注入

**描述**: `writeProperties()` 中 `issue.reason`（自由文本字段）通过 `{s}` 直接插入 JSON 未转义。

**影响**: 如果 `issue.reason` 包含双引号或反斜杠，将破坏 SARIF JSON 结构。

**修复**: 使用 `std.json.stringEncode` 转义。

***

### BUG-018 \[High] CI/CD — Release 工作流缺少二进制签名和校验和

- **文件**: `.github/workflows/release.yml` 第 189-200 行
- **类别**: CI/CD 安全 / 供应链

**描述**: Release 工作流直接将编译的二进制文件上传到 GitHub Release，没有 SHA256 校验和、代码签名（GPG/cosign）或 SBOM。

**影响**: 用户无法验证发布的二进制文件是否被篡改，存在供应链攻击风险。

**修复**: 添加 `sha256sum` 生成、GPG 签名和 SBOM 生成步骤。

***

### BUG-019 \[High] CI/CD — 安全分析工作流错误被静默忽略

- **文件**: `.github/workflows/security-analysis.yml` 第 62 行
- **类别**: CI/CD 安全

**描述**: 安全分析命令使用 `2>/dev/null || echo "Analysis completed with warnings"` 将所有错误输出丢弃。此外，第 59 行可执行文件名拼写错误（`OmniSope` 而非 `OmniScope`），导致安全分析步骤实际不运行。

**影响**: 安全分析失败时不会被发现，可能将不安全的项目标记为安全。安全分析工作流形同虚设。

**修复**: 修正拼写错误，移除 `2>/dev/null`，使用 `set -euo pipefail`。

***

## 5. 中危 (Medium) 问题

### BUG-020 \[Medium] fact/store.zig — init/queryByKind 使用 catch unreachable

- **文件**: `src/fact/store.zig` 第 31-34, 99 行
- **描述**: 5 个 `initCapacity` 调用使用 `catch unreachable`，OOM 时进程立即终止。
- **修复**: 对查询路径使用优雅的错误传播。

### BUG-021 \[Medium] fact/store.zig — count()/get() 未持锁

- **文件**: `src/fact/store.zig` 第 78-91 行
- **描述**: 读写方法未持有互斥锁，并发场景下可能读取不一致状态。
- **修复**: 在 `count()` 和 `get()` 中加锁。

### BUG-022 \[Medium] pointer\_ownership.zig — 多个关键方法为空存根

- **文件**: `src/pass/analysis/pointer_ownership.zig` 第 910-933 行
- **描述**: `findFreePath()`、`canReachFree()`、`isMemoryAccess()` 始终返回 `false`。
- **修复**: 实现完整逻辑或移除死代码路径。

### BUG-023 \[Medium] pointer\_ownership.zig — ScopedTimer 重复 stop

- **文件**: `src/pass/analysis/pointer_ownership.zig` 第 139-211 行
- **描述**: `init_timer` 和 `analysis_timer` 同时有 `defer stop()` 和手动 `stop()` 调用，导致同一计时器被记录两次。
- **修复**: 移除重复的 `stop()` 调用。

### BUG-024 \[Medium] taint\_propagation.zig — GEP 深度因子过早截断

- **文件**: `src/pass/analysis/taint_propagation.zig` 第 512 行
- **描述**: `num_indices >= 6` 时 `depth_factor` 变为负数，所有深层 GEP 置信度被截断到同一最小值。
- **修复**: 调整 `GEP_DEPTH_CONFIDENCE_FACTOR` 或使用对数衰减。

### BUG-025 \[Medium] taint\_state.zig — getTaintedValues 所有权 API 易误用

- **文件**: `src/pass/analysis/taint_state.zig` 第 138-153 行
- **描述**: 接受外部 allocator 但文档未明确说明调用者必须用同一 allocator 释放返回值。
- **修复**: 添加文档说明或改用内部 allocator。

### BUG-026 \[Medium] profiler.zig — record() OOM 时 key 指针可能非堆内存

- **文件**: `src/perf/profiler.zig` 第 91-108 行
- **描述**: `getOrPut` 成功后 `dupe` 失败时，HashMap 中已插入条目但 key 指向临时字符串。`deinit()` 将尝试释放非堆内存。
- **修复**: 使用 errdefer 清理已插入的条目。

### BUG-027 \[Medium] profiler.zig — Timer.start()/elapsedNs() 使用 catch unreachable

- **文件**: `src/perf/profiler.zig` 第 16-17, 22-23 行
- **描述**: 高精度计时器不可用时触发 panic。
- **修复**: 返回错误或使用回退计时机制。

### BUG-028 \[Medium] graph.zig — addEdge() OOM 时内存泄漏

- **文件**: `src/dataflow/graph.zig` 第 165-179 行
- **描述**: `put` 失败时新分配的列表不会被释放。
- **修复**: 添加 errdefer 释放新分配的列表。

### BUG-029 \[Medium] graph.zig — deinit() 不释放 Issue 的 trace entries

- **文件**: `src/dataflow/graph.zig` 第 83-107 行
- **描述**: `deinit()` 只释放 `message`，不调用 `Issue.deinit()`，可能遗漏 owned 的 trace entries。
- **修复**: 调用 `Issue.deinit()` 或遍历释放所有 owned 字段。

### BUG-030 \[Medium] ffi\_analysis.zig — detectOwnershipMismatch 笛卡尔积误报

- **文件**: `src/pass/analysis/ffi_analysis.zig` 第 323-326 行
- **描述**: 对所有分配-释放对做笛卡尔积比较，不检查数据流是否实际连通。
- **修复**: 添加数据流连通性检查。

### BUG-031 \[Medium] ffi\_boundary.zig — identifyLanguage 子串匹配误分类

- **文件**: `src/pass/analysis/ffi_boundary.zig` 第 396-422 行
- **描述**: `indexOf` 匹配过于宽泛，`"extern"` 同时匹配 Rust 和 Zig 模式。
- **修复**: 使用更精确的正则表达式或词边界匹配。

### BUG-032 \[Medium] guard\_propagation.zig — 空值检查约束可能反转

- **文件**: `src/dataflow/guard_propagation.zig` 第 76-87 行
- **描述**: 假设 `true_bb_id` 对应 null 条件，但条件形式（`p == NULL` vs `p != NULL`）可能相反。
- **修复**: 根据 ICmp 谓词确定语义方向。

### BUG-033 \[Medium] guard\_propagation.zig — Value 指针截断为 u32

- **文件**: `src/dataflow/guard_propagation.zig` 第 114, 124 行
- **描述**: `@intFromPtr(value)` 截断为 `u32`，64 位系统上高 32 位丢失。
- **修复**: 使用 `u64` 或 `usize` 作为 value\_id。

### BUG-034 \[Medium] steensgaard.zig — 间接约束处理不完整

- **文件**: `src/pass/analysis/steensgaard.zig` 第 244-256 行
- **描述**: 对间接约束 `*p = q` 只执行 `unite(p, q)`，不处理 p 的 points-to 集合。
- **修复**: 遍历 p 的 points-to 集合并逐一合并。

### BUG-035 \[Medium] steensgaard.zig — handleAlloca 虚拟对象 ID 冲突

- **文件**: `src/pass/analysis/steensgaard.zig` 第 103-105 行
- **描述**: 使用 `@intFromPtr(inst) + 1` 作为虚拟对象 ID，理论上有冲突风险。
- **修复**: 使用独立递增的 ID 计数器。

### BUG-036 \[Medium] call\_graph.zig — propagateTaint 迭代上限过低

- **文件**: `src/pass/analysis/call_graph.zig` 第 315-345 行
- **描述**: 固定迭代上限 8 次，深度调用链中污点传播不完整。
- **修复**: 使用工作列表算法替代固定迭代。

### BUG-037 \[Medium] call\_graph.zig — classifyRisk/isSink 子串匹配过度

- **文件**: `src/pass/analysis/call_graph.zig` 第 400-406 行
- **描述**: `system_call`、`mysystem` 等安全函数被错误标记为危险 sink。
- **修复**: 使用精确匹配或白名单机制。

### BUG-038 \[Medium] cpp\_fp\_reduction.zig — detectUseAfterFree 逻辑方向错误

- **文件**: `src/pass/analysis/cpp_fp_reduction.zig` 第 527-558 行
- **描述**: 检查"被释放指针是否流向另一个释放点"而非"释放后是否被使用"。
- **修复**: 检查释放后的 load/store/call 操作。

### BUG-039 \[Medium] report/mod.zig — formatTimestamp OOM 时返回静态字符串

- **文件**: `src/report/mod.zig` 第 300-301 行
- **描述**: `allocator.dupe()` 失败时返回编译时常量字符串，调用者 `free()` 导致 UB。
- **修复**: OOM 时返回错误而非静态字符串。

### BUG-040 \[Medium] report/mod.zig — generate() 吞没 OOM 错误

- **文件**: `src/report/mod.zig` 第 99 行
- **描述**: `initCapacity` 失败时返回空字符串 `""`，调用者无法区分错误和空报告。
- **修复**: 传播错误。

***

## 6. 低危 (Low) 问题

| ID      | 文件                       | 描述                                           |
| ------- | ------------------------ | -------------------------------------------- |
| BUG-041 | `fact/store.zig`         | `count()`/`get()` 未持锁，数据竞争（当前单线程无影响）         |
| BUG-042 | `pointer_ownership.zig`  | `param_value_ids` 数组大小 32 但只使用 16            |
| BUG-043 | `pointer_ownership.zig`  | `summary_registry.initBuiltins()` 错误被吞没      |
| BUG-044 | `taint_propagation.zig`  | `source_count`/`inst_count` 为 u32，大型 IR 可能溢出 |
| BUG-045 | `profiler.zig`           | `ScopedTimer.start()` 借用调用者字符串，API 易误用       |
| BUG-046 | `graph.zig`              | FFI boundary ID `usize + 1` 截断为 `u32`        |
| BUG-047 | `ffi_analysis.zig`       | `@intCast(i)` usize 转 u32 可能截断               |
| BUG-048 | `ffi_boundary.zig`       | `isCppAbiInternalFunction` 精确匹配循环冗余          |
| BUG-049 | `alias.zig`              | `mayAliasByType` 函数声明但从未调用（死代码）              |
| BUG-050 | `cpp_fp_reduction.zig`   | `isLikelyIntentionalPattern` 可通过命名惯例绕过检测     |
| BUG-051 | `tracking/allocator.zig` | `resize` 缩小不更新 `free_count`，泄漏检测不准确          |
| BUG-052 | `output/lsp.zig`         | `FileMap.add` 重复添加同一 loc\_id 时旧 URI 未释放      |

***

## 7. CI/CD 安全专项

### 7.1 curl | bash 供应链风险

- **文件**: `.github/workflows/ci.yml` 第 29 行, `release.yml` 第 39 行
- **问题**: `curl -sSL https://www.zvm.app/install.sh | bash` 无校验和或 PGP 签名验证
- **建议**: 固定安装脚本版本，添加完整性校验

### 7.2 已弃用的 apt-key 和 HTTP 仓库

- **文件**: `.github/workflows/ci.yml` 第 39-41 行, `release.yml` 第 49-51 行
- **问题**: 使用已弃用的 `apt-key add`，且 LLVM 仓库 URL 使用 HTTP
- **建议**: 迁移到 `/etc/apt/keyrings/` 方式，使用 HTTPS URL

### 7.3 Release 工作流权限过宽

- **文件**: `.github/workflows/release.yml` 第 9-10 行
- **问题**: `contents: write` 未限制作用域
- **建议**: 遵循最小权限原则，限制到 release 操作

### 7.4 Zig 版本不一致

- **文件**: 三个 CI 工作流
- **问题**: `security-analysis.yml` 使用 `0.15.0`，其他使用 `0.15.2`
- **建议**: 统一 Zig 版本

### 7.5 Security Scorecard 为空操作

- **文件**: `.github/workflows/security-analysis.yml` 第 139-163 行
- **问题**: 只打印静态文本，未实际执行安全评分
- **建议**: 集成 OpenSSF Scorecard 等真实工具

***

## 8. 修复优先级

| 优先级       | 数量 | 说明                                           |
| --------- | -- | -------------------------------------------- |
| **P0 立即** | 4  | 编译错误(1) + 悬空指针(1) + double-free(1) + 整数溢出(1) |
| **P1 尽快** | 14 | 分析逻辑错误(8) + JSON 注入(3) + CI/CD 安全(3)         |
| **P2 计划** | 21 | 误报/漏报、资源管理、错误处理                              |
| **P3 后续** | 13 | 性能、代码质量、死代码                                  |

***

## 9. 代码质量评估

### 优势

1. **优秀的架构设计**: Pass-based 分析框架，拓扑排序依赖管理，模块解耦良好
2. **comptime 类型安全**: Pass 接口在编译期验证，零运行时开销
3. **SoA 数据布局**: FactStore 使用 Structure of Arrays 优化缓存友好性
4. **数据驱动设计**: SemanticMapper 使用规则表，易于扩展
5. **完善的测试体系**: 单元测试、集成测试、稳定性测试、压力测试、E2E 测试
6. **安全的 LLVM-C 封装**: 通过 llvm\_safe.zig 安全封装原始 LLVM-C API
7. **多格式输出**: Text/JSON/SARIF 格式，SARIF 兼容 v2.1.0
8. **可扩展的注册表**: SemanticRegistry 4 层查找机制

### 不足

1. **内存安全问题集中**: memory\_pool.zig 存在悬空指针和重复释放，是最需要优先修复的模块
2. **JSON/SARIF 输出转义不一致**: 多处遗漏字符串转义，影响下游安全工具
3. **固定大小缓冲区**: BFS 队列硬编码 64 元素上限，大型 IR 分析不完整
4. **指针截断问题普遍**: 多处将 64 位指针截断为 u32，大型模块存在 ID 冲突风险
5. **CI/CD 安全薄弱**: 缺少二进制签名、使用 curl|bash、安全分析工作流失效
6. **错误处理不一致**: 部分使用 catch unreachable，部分吞没错误

***

## 10. 结论

OmniScope 整体架构设计优秀，代码质量在同类项目中属于中上水平。本次审计共发现 52 个问题，其中 1 个 Critical（编译错误导致三类漏洞检测失效）、18 个 High（集中在内存安全、分析逻辑正确性和输出注入三个方面）。

**最需要优先修复的问题**:

1. `memory_pool.zig` 的悬空指针和重复释放问题（BUG-002, BUG-003）
2. `ffi_detector.zig` 的类型错误（BUG-001）
3. JSON/SARIF 输出注入问题（BUG-015, BUG-016, BUG-017）
4. CI/CD 安全分析工作流失效（BUG-019）

项目在内存安全、类型安全和错误处理方面表现良好，主要问题集中在特定模块的边界条件处理和 CI/CD 安全配置上。建议按优先级逐步修复，优先解决 P0 和 P1 级别的问题。
