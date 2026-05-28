# OmniScope Code Review Report

> **Date**: 2026-05-28  
> **Version**: 0.2.0  
> **Scope**: 全量代码审查 (~87,000 行 Zig, 275 个 .zig 文件)  
> **Method**: 12 个并行 agent 逐行审查所有模块

---

## Executive Summary

| Category | Count | Severity |
|----------|-------|----------|
| Technical Debt | ~200+ issues | Medium-High |
| Potential Bugs | ~120+ issues | Critical-High |
| Lazy/Superficial Tests | ~150+ issues | Critical |
| Dependency Issues | 7 circular deps, 125 layering violations | High |
| Orphan Modules | 26 modules never imported | Medium |

**最严重的三个问题:**
1. **测试大面积造假** — `tests/p0p6_benchmark.zig`(7/7)、`tests/ffi_benchmark.zig`(6/6)、`tests/integration/main.zig`(11/11) 的测试全部是 `expect(true)` 或本地数组计数，从未调用 OmniScope
2. **死锁 bug** — `src/fact/query.zig:235` 中 `queryByKindIndexed` 持有 mutex 后调用 `queryByKind` 再次加锁，`std.Thread.Mutex` 不可重入
3. **内存安全** — 多处 `catch {}` 静默吞掉 OOM、`@ptrFromInt` 类型混淆、use-after-free 风险

---

## Table of Contents

1. [src/common/](#1-srccommon)
2. [src/engine/](#2-srcengine)
3. [src/semantics/](#3-srcsemantics)
4. [src/registry/](#4-srcregistry)
5. [src/ffi/ src/ir/ src/lifetime/ src/dataflow/](#5-srcffi-srcir-srclifetime-srcdataflow)
6. [src/pass/ src/pipeline/ src/perf/](#6-srcpass-srcpipeline-srcperf)
7. [src/output/ src/visual/ src/tracking/ src/diag/](#7-srcoutput-srcvisual-srctracking-srcdiag)
8. [src/types/ src/utils/ src/fact/](#8-srctypes-srcutils-srcfact)
9. [tests/](#9-tests)
10. [Build System (build.zig, Makefile)](#10-build-system)
11. [scripts/](#11-scripts)
12. [Dependency Graph Analysis](#12-dependency-graph-analysis)

---

## 1. src/common/

### Technical Debt

- `[prefix_trie.zig:83]` — `MatchMode` 参数被完全忽略 (`_ = mode;`)。Prefix 和 substring 模式行为完全相同。整个 `MatchMode` 枚举和 mode 参数是死 API。
- `[prefix_trie.zig:176-186]` — `findChild` 对所有节点做线性扫描而非仅扫描给定 parent 的子节点。文档声称 O(n) 但实际复杂度为 O(input_len × node_count)。
- `[prefix_trie.zig:21,25]` — 魔数 `MAX_PATTERNS=64` 和 `MAX_DEPTH=128` 无编译时断言。
- `[prefix_trie.zig:258-264]` — stdlib 前缀不一致：大部分带尾部 `"."` 但 5 个模式省略了 (`"unicode"`, `"random"`, `"compress"`, `"hmac"`, `"aead"`, `"aes"`)，导致过度宽泛的匹配。
- `[log.zig:38-41]` — `print` 函数不一致地省略了级别前缀和换行后缀，与 `info`/`debug`/`warn` 不一致。
- `[types.zig:564-573]` — 测试硬编码 19 个 `IssueKind` 变体，但枚举已增长到 24 个。缺失 `integer_overflow`、`callback_ownership_risk`、`write_to_immutable`、`data_race`、`thread_safety_violation`。
- `[arena.zig:114-115]` — 冗余的 `@max(log_2_alignment, @as(u29, 0))` — `u29` 是无符号的，始终 ≥ 0。

### Potential Bugs

- **`[prefix_trie.zig:83]`** — `mode` 参数被完全忽略，`.prefix` MatchMode 变体不生效。
- **`[log.zig:18,25,31]`** — `std.log.info`/`debug`/`warn` 已经追加 `\n`，`++ "\n"` 产生双空行。
- **`[log.zig:10]`** — `current_log_level` 是线程不安全的可变全局状态。并发 `setLogLevel()` + 任何 log 函数 = 数据竞争 (CWE-362)。
- **`[arena.zig:134]`** — 对齐保证违反：`backing_allocator.alloc(u8, n)` 只保证 1 字节对齐，但 bump-pointer 对齐数学假设块基址指针自然对齐。
- **`[arena.zig:115]`** — 大对齐时 panic：`@intCast` 在 `effective_align > 63` 时 panic，无边界检查。
- **`[string_interner.zig:92]`** — `total_input_bytes += s.len` 在 32 位目标上可能溢出 panic，应使用 `+%`。
- **`[types.zig:334-339]`** — `Confidence.fromScore(f32)` 不处理 NaN。所有 NaN 比较返回 false，静默落入 `.experimental`。

### Lazy/Superficial Tests

- **`[types.zig:564-573]`** — 硬编码计数 19，不使用 `@typeInfo(IssueKind).Enum.fields.len`。枚举已增长到 24 但测试仍通过。
- **`[types.zig:576-590]`** — CWE 映射测试缺失 5 个变体的覆盖。
- **`[types.zig:559-562]`** — `Severity.toString` 只检查 `.low` 和 `.critical`，跳过 `.medium` 和 `.high`。
- **`[types.zig:443-512]`** — `SemanticSurface` 完全未测试。
- **`[prefix_trie.zig:192-203]`** — Prefix 模式测试是假象——因模式包含点号，substring 匹配偶然产生相同结果。
- **`[string_interner.zig:141-209]`** — 无哈希冲突测试。

---

## 2. src/engine/

### Technical Debt

- `[loader.zig:67]` — `_ = loaded;` 显式丢弃 `loadFile()` 返回值。
- `[loader.zig:89-101]` — `iterateFunctions` 重复了 `llvm_safe.Module.iterateFunctions` 中已有的迭代逻辑。
- `[loader.zig:40]` — `alive: bool = false` 手动生命周期标志，Zig 应使用 `?IRLoader` 可选类型。
- `[loader.zig:132-134]` — 注释声称 "IRLoader 不能被复制" 但无实际机制强制执行。
- `[loader.zig:43]` — `loadFile` 是静态方法，将构造与加载混为一谈，无法创建不加载文件的 IRLoader。

### Potential Bugs

- **`[loader.zig:77-80]`** — `getModule` 返回的 `ModuleRef` 在 `safe_loader` 被释放后是悬垂借用（use-after-free 风险）。
- **`[loader.zig:97-99]`** — `iterateFunctions` 中如果回调修改模块（如删除函数），`f.getNext()` 可能返回无效指针。
- **`[loader.zig:44-51]`** — 错误映射使用 `else => error.InvalidIR` 作为兜底，新增的 `llvm_safe.Error` 变体将被静默吞为 `InvalidIR`。
- **`[loader.zig:56-66]`** — 第二个错误映射块同样有兜底问题。

### Lazy/Superficial Tests

- **`[loader.zig:142-144]`** — 测试 "getModule with no module loaded" 只做 `_ = IRLoader;`，完全不测试 `getModule`。
- **`[loader.zig:159-162]`** — 测试 "error set validation" 用 `_ = ErrorSet` 丢弃错误集，不验证任何内容。
- **`[loader.zig:146-157]`** — 测试只检查 `@hasDecl` 存在性，不检查行为。即使每个函数体都是 `unreachable` 也能通过。
- **`[loader.zig:164-173]`** — 测试字段名和类型排序，重构即断——脆弱测试。

---

## 3. src/semantics/

### Technical Debt

- `[semantic_tree.zig:220-229]` — `findNodesByKind` 和 `findNodesByName` 是死桩实现，无条件返回空切片。
- `[semantic_tree.zig:291-373]` — `traceToHeapProvenance` 包含 ~15 个 `std.debug.print` 调用，在生产中无条件写 stderr。
- `[nomicon/ch08_concurrency.zig:11-17]` — 整个文件是占位符，无实现。`ch05_uninitialized.zig` 和 `ch04_conversions.zig` 同样。
- `[patterns/interior_mut.zig:117-119]` — `isInteriorMutableThroughChain` 直接委托给 `isInteriorMutDIName` 而不遍历链——与文档矛盾。
- `[language_detector.zig:324-385]` — Go 运行时内部检测块在 `zone_lang_detectors.zig:57-118` 和 `zone_lang_go.zig:40-101` 中有 3 份完全相同的 ~60 行逻辑。
- `[semantic_patterns.zig:162-174]` — `findMatchingPatterns` 分配 ArrayList 迭代但总是第一个匹配就 break 返回空切片——完全无功能的死代码。
- `[semantic_patterns.zig:180-244]` — 5 个 `create*Pattern` 函数忽略分配器参数 (`_ = _allocator`)。
- `[attribute.zig:234-241]` — `extractFramePointerPolicy` 是 TODO 桩，总是返回 `.unknown`。`extractTargetFeatures` (326-331) 同样。

### Potential Bugs

- **`[zone_classifier.zig:104]`** — `var result: ZoneKind = undefined;` — 如果控制流分析变化，可能读取 undefined。
- **`[memory_graph.zig:309-313]`** — `node.free_sites.append(...)` 用 `catch {}` 静默吞掉 OOM，丢失 free site 可能导致假阳性 double-free 报告。
- **`[summary_inference.zig:56-61]`** — `entries.getPtr(name)` 返回 hashmap 中的可变指针，如果后续 `register` 调用导致 hashmap 重分配，指针悬垂（use-after-reallocation）。
- **`[call_graph.zig:413]`** — 使用 `entry.found_exists` 但 Zig 的 `getOrPut` 返回 `.found_existing`——拼写错误导致编译错误。
- **`[call_graph.zig:234,249]`** — `@as(usize, edge_id - 1)` 和 `@as(usize, node_id - 1)` 在 ID 为 0 时下溢。
- **`[memory_graph.zig:688]`** — `isLeaked` 在 `call_ret_by_ptr.get(ptr_val)` 返回 null 时返回 true——但这只意味着指针从未被跟踪，不一定是泄漏。
- **`[transfer_inference.zig:272]`** — `isAllocationFunction` 匹配任何以 `"__"` 开头的函数——`__stack_chk_fail`、`__cxa_throw`、`__asan_init` 都会被分类为分配函数。

### Lazy/Superficial Tests

- **大量文件零测试**：`memory_graph_fuzzy.zig`(271 行)、`resource/platform_filter.zig`、`resource/model_mining.zig`(251 行)、`resource/ownership_state.zig`(241 行)、`resource/contract.zig`(243 行)、`resource/escape.zig`(290 行)、`resource/effect.zig`(228 行)、`resource/function_summary.zig`(265 行)、`resource/family_registry.zig`(477 行)、`resource/summary_inference.zig`(792 行)、`nomicon/ch06_obrm.zig`、`nomicon/ch09_vec_box.zig`(273 行)、`nomicon/ch10_pin_box.zig`(149 行)、`nomicon/posix_syscalls.zig`(208 行)、`patterns/heap_provenance.zig`(344 行)、`patterns/interior_mut.zig`(194 行)、`patterns/into_raw_transfer.zig`(112 行)、`patterns/lang_detector.zig`(212 行)、`patterns/library_alloc_pairs.zig`(206 行)。
- **`[call_graph.zig:805-947]`** — 测试使用 `@ptrFromInt(0x1000)` 作为假 LLVM 值，`reachesFFIBoundary`（核心卖点函数）零测试。
- **`[behavior_filter.zig:624-641]`** — Rust drop glue 测试只检查 `result.confidence > 0.5`，应断言精确预期值。
- **`[noise_filter_test.zig:80-99]`** — 边界用例测试 (`"."`, `".."`, `"_"`) 只验证不崩溃，无结果断言。

---

## 4. src/registry/

### Technical Debt

- `[semantic_registry.zig:90-137]` — `lookup()` 是 15 层顺序线性扫描，15 个相同的 `for + matchesPattern` 块被复制粘贴 15 次。
- `[layer1_reg.zig:4-82]` — 全部 82 个条目是极长的单行结构体字面量 (~300+ 字符)，严重损害可读性。
- `[layer2_reg.zig:3]` — 数据注册表导入 `pass/analysis/ptr_lifetime/ptr_lifetime_types.zig`——耦合倒置。
- `[hooks.zig:84-97]` — `transfer_out_patterns` 包含冗余条目：`Box::into_raw`、`Rc::into_raw`、`Arc::into_raw` 被 `"into_raw"` 包含。
- `[layer5_reg.zig:26]` — `@intToPtr` 在现代 Zig (0.11+) 中已弃用，应为 `@ptrFromInt`。
- `[layer5_reg.zig:24]` — 模式 `".!|"` 中的 `|` 字符不对应任何 Zig 语法。
- `[semantic_registry.zig:225-226]` — 可变模块级状态 (`hooks`, `hook_count`) 不是线程安全的。

### Potential Bugs

- **`[posix_io_reg.zig:4-37 vs 47-69]`** — `inet_ntoa`、`gethostbyname`、`gethostbyaddr` 在 `network_io_functions` 和 `static_buffer_functions` 中定义了**不同语义**。`semantic_registry.lookup()` 先扫描 `network_io`，`static_buffer` 定义被影子化。
- **`[layer1_reg.zig vs python_c_api_reg.zig]`** — 10 个函数在两个表中定义，Layer 1 先扫描导致 python_c_api_reg 定义是**永远被影子化的死代码**。更糟的是语义不同。
- **`[layer1_reg.zig vs jni_reg.zig]`** — 12 个 JNI 函数同样被影子化。
- **`[config_loader.zig:248-263]`** — `DynamicRegistry.addFunction()`: 如果 `append` 成功但 `put` 失败，已追加的条目不回滚（无 errdefer）。
- **`[config_loader.zig:292-331]`** — `DynamicRegistry.query()` 返回的 `FunctionInfo` 中的 `tags` 切片是堆分配的，但 `FunctionInfo` 无分配器字段——**每次调用都泄漏内存**。
- **`[hooks.zig:109]`** — `rust_transfer_map.put` 在 OOM 时返回 `.issue_found`（假阳性）。
- **`[hooks.zig:242,255]`** — `python_refcount_map.getOrPut` 在 OOM 时返回 `.none`，可能错过 use-after-free 检测。
- **`[layer1_reg.zig:7-10]`** — `strcpy`/`strcat` 使用 `.contains` 匹配，安全变体 `strcpy_s`/`strcat_s` 也被标记为 `.high` 严重性。

### Lazy/Superficial Tests

- **`[hooks_test.zig:70,82,110,134,154,172]`** — 多个测试丢弃返回值 `_ = result;`，只验证不崩溃。
- **`[layer1_reg.zig:84-87]`** — 同义反复测试：`expected_count = layer1_functions.len; expectEqual(expected_count, layer1_functions.len)`。
- **所有 layer 测试**使用硬编码魔数计数（layer1=65, layer2=12, layer3=4, layer4=9, layer5=29, layer6=57）——脆弱。
- **`[hooks_test.zig]`** — 缺失：无 `goEscapeHook` 测试；无 `initHookStates`/`deinitHookStates` 生命周期测试；无状态配对行为测试。

---

## 5. src/ffi/ src/ir/ src/lifetime/ src/dataflow/

### Technical Debt

- `[ffi_matcher.zig:172-241]` — `getUnmatchedDeclares` 和 `getUnmatchedDefines` 是近乎相同的 ~70 行代码重复。
- `[ir/debug_info.zig:158,167]` — 魔数 `4096` 重复出现。`getInstructionDebugInfo` 接受但忽略 `allocator` 参数。
- `[ir/debug_info.zig:353-362]` — 大块 "Future work" 注释表示未完成的内联栈支持。
- `[ir/llvm_safe.zig:166-189]` — 为 LLVM 22 文本 IR segfault 而 spawn `llvm-as` 子进程的大型变通方案。
- `[ir/location.zig:17-19]` — `LocationId` 定义为 `u32` 但无方法且未使用。
- `[lifetime/boundary.zig:225,252]` — 硬编码严重性值 (4, 3)。
- `[dataflow/guard_propagation.zig:1-8]` — 自文档为 "complete but NOT yet integrated"——编译但未使用的死代码。
- `[dataflow/function_summary.zig:142-144]` — `transfersOwnership` 简单返回 `self.is_allocator`——将分配与所有权转移混为一谈。

### Potential Bugs

- **`[ir/debug_info.zig:188]`** — `@enumFromInt(lang)` 不检查地将 C int 转为 `DWARFSourceLanguage` 枚举。LLVM 返回意外值时 UB。
- **`[ir/llvm_safe.zig:243]`** — `@intCast(c.LLVMGetNumOperands(inst))` — 从有符号 `c_int` 到无符号 `c_uint` 的不安全转换。
- **`[ir/llvm_safe.zig:189]`** — 递归 `self.loadFile()` 调用无递归保护。
- **`[lifetime/boundary.zig:179-180]`** — `next_boundary_id` 是 `u32`，溢出后产生与错误值相同的 0。
- **`[lifetime/boundary.zig:189]`** — `catch return 0` 将任何错误（包括 OOM）静默转为 0 返回值。
- **`[lifetime/engine.zig:315,333,387]`** — `catch return null` / `catch return false` 将 OOM 静默转为 null/false。
- **`[dataflow/graph.zig:306]`** — `_ZN` 前缀被分类为 Rust 是错误的——`_ZN` 是 C++ 和 Rust 共用的 Itanium 名称修饰。
- **`[dataflow/graph.zig:312]`** — `c_` 前缀被分类为 Zig 是非常弱的启发式，会错误分类许多 C 函数。
- **`[dataflow/graph.zig:132-135]`** — `addNode` 中如果 `incoming_edges.put` 失败，`empty_outgoing` 泄漏。
- **`[dataflow/graph.zig:170-176,178-184]`** — `addEdge` 中 `put` 失败时新分配的 `new_list` 泄漏。
- **`[dataflow/null_check_guard.zig:100-108]`** — `getGuardForBlock` 只返回第一个匹配的 guard，嵌套 if-else 时后续 guard 被静默忽略。
- **`[dataflow/null_check_guard.zig:134-143]`** — `isPtrGuardedNonNull_byValue` 在 null 分支也返回 true——逻辑错误。

### Lazy/Superficial Tests

- **`[ir/debug_info.zig:498-532]`** — 6 个测试全是桩：`_ = DIBuilder;`、设置 `raw = null` 检查 null、检查 `!= null`。
- **`[ir/view.zig:37-60]`** — 5 个测试创建 `undefined` raw 并赋值给 `_`——零断言。
- **`[ffi_matcher.zig:244-308]`** — 测试只检查 `@hasDecl` 存在性，"memory management" 测试为空。
- **`[dataflow/stats.zig]`** — `computeIssueStats`、`computeGraphStats` 和所有 `inferIs*` 函数零测试。

---

## 6. src/pass/ src/pipeline/ src/perf/

### Technical Debt

- `[steensgaard.zig:1]` — "fully implemented but NOT yet wired into the analysis pipeline"——死代码投资。
- `[transmute_detection.zig:1]` — "complete but NOT yet registered as a Pass"——又一个未接入的功能。
- `[pointer_ownership.zig:68-71]` — 40+ 个委托函数是简单的包装器转发到 `cpp_fp` 和 `analysis` 模块。
- `[pointer_ownership.zig:74]` — `run()` 跨越 lines 74-512 (~438 行)，远超 100 行准则。
- `[callback_escape.zig:130]` — `analyzeFunction()` 跨越 356-661 (~305 行)。
- `[lock.zig:53,273]` — `catch @panic("OOM")` 在生产代码中。应传播错误。
- `[lock.zig:174-193]` — 硬编码锁函数列表只有 6 个名称，缺失 std::mutex、Go sync.Mutex、Java synchronized 等。
- `[instrumentation/planner.zig:477]` — 魔数 `max_instrumentations = 1000`。
- `[instrumentation/planner.zig:330-337]` — `shouldInstrument()` 总是返回 false，注释说 "no longer used directly"。
- `[instrumentation/planner.zig:79-81]` — 使用 `std.heap.page_allocator` 绕过传入的分配器。
- `[buffer_overflow.zig:61]` — 魔数 `func_count > 500` 跳过大模块阈值。
- `[profiler.zig:402-422]` — `sampleRss()` 和 `sampleHeapAllocs()` 总是返回 0——TODO 未实现。

### Potential Bugs

- **`[callback_escape.zig:238-241]`** — `cb_context_ptr` 是模块级可变变量用于线程通信——不线程安全。
- **`[callback_escape.zig:287-288]`** — `wctx.mutex.lock()` + `defer unlock` 意味着所有函数分析被序列化，破坏并行执行器的目的。
- **`[ip_ffi.zig:193-201]`** — 固定大小栈数组 `bb_stack: [4]` 和 `visited_bbs: [8]` 无边界检查，可能溢出。
- **`[thread_crossing.zig:248-251,288-291,328-331,368-371]`** — 多处 `trace` 数组分配后无 errdefer，后续分配失败时泄漏。
- **`[abi_mismatch.zig:235,276,316]`** — 同样的泄漏模式。
- **`[abi_mismatch.zig:318]`** — 格式字符串 bug：`"{s()}"` 应为 `"{s}()"`。
- **`[steensgaard.zig:188,210]`** — 路径压缩和秩更新失败用 `catch {}` 静默忽略，可能导致 union-find 正确性问题。
- **`[pointer_ownership.zig:319-323,461-465]`** — timer 启动失败时 `return`，但 `defer timer.stop()` 已注册，可能停止无效 timer。
- **`[parallel.zig:206-209]`** — `spawn_shared` 是模块级 `var`，`run()` 并发调用时不安全。
- **`[parallel.zig:424]`** — `_ = @as(usize, 0)` 不是编译器屏障——在 Zig 中无效。
- **`[pass/manager.zig:219]`** — `profiler.PassTimer.startPass() catch null` 静默吞掉计时器失败。
- **`[dfg.zig:169]`** — 测试编译错误：`DFGPass.init(&store)` 传 1 个参数但 `init` 需要 2 个。
- **`[memory_pool.zig:94]`** — `free()` 返回 `!void` 错误联合——异常的 free 签名可能导致调用者意外泄漏。

### Lazy/Superficial Tests

- **`[dfg.zig:165-171]`** — 测试无法编译。
- **`[cfg.zig:204-224]`**、**`[alias.zig:330-369]`**、**`[lock.zig:321-341]`** — 模式：`const pass = Pass.init(...); _ = pass;`——零行为验证。
- **`[lock.zig:496-544]`** — 死锁测试创建了模拟操作但从不调用 `detectDeadlocks()`。
- **`[provenance.zig]`**、**`[debug_info.zig]`**、**`[alias_analysis.zig]`**、**`[issue_gate.zig]`**、**`[surface_classifier_pass.zig]`**、**`[semantic_resolver_pass.zig]`** — 整个文件零测试。
- **`[bench_compare.zig:198-211]`** — 基准测试只检查 `result.avg_ns > 0`——无性能回归检测。
- **`[profiler.zig:474-487]`** — RSS 测试用 `_ = stats.rss_before_kb;` 丢弃值——无断言。

---

## 7. src/output/ src/visual/ src/tracking/ src/diag/

### Technical Debt

- `[confidence_scorer.zig:1-134]` — 整个文件是死代码——从未被任何模块导入。
- `[rule_engine.zig:4-8]` — 自文档死代码："This module is fully implemented but NOT yet wired into the analysis pipeline"。
- `[sarif.zig:217-227]` — `defaultSeverity` 是私有且从未调用——死代码。
- `[graph_visualizer.zig:302-330]` — `kindToColor` 和 `kindToStatus` 是私有且从未调用——死代码。
- `[sarif.zig:36-174]` — `SarifOutput` 重复了 `formatter.zig:287-304` 中已有的 JSON 转义逻辑。`graph_visualizer.zig:336-361` 是第三份。
- `[formatter.zig:54-61]` — `AnalysisResult.init` 接受但不使用 `allocator` 参数。
- `[issue.zig:180-276]` — 三个 `init`/`initWithReason`/`initWithTrace` 构造函数共享 ~90% 相同的字段初始化。

### Potential Bugs

- **`[issue.zig:326-347]`** — `formatContractEvidence` 返回指向栈分配 `buf[256]` 的 `?[]const u8`——**use-after-return** 悬垂指针。
- **`[formatter.zig:158-194]`** — `formatJson` 生成格式错误的 JSON：`source_location` 字符串未关闭，`line` 值有多余的尾部 `"`。
- **`[formatter.zig:258]`** — SARIF 输出有无效 JSON：逗号位置假设特定字段顺序。
- **`[aggregator.zig:88-96,228-241,255-268,283-291,310-316]`** — 多处 `allocator.dupe` 后无 errdefer，`append` 失败时内存泄漏。
- **`[graph_visualizer.zig:154-157]`** — `kind_counts.put` 用 `catch {}` 静默吞掉 OOM，计数丢失。
- **`[graph_visualizer.zig:189]`** — `@intFromFloat(issue.confidence * 100)` 在 NaN/负数/极大值时 UB。
- **`[lsp.zig:233-243]`** — `locationToRange` 在查找失败时用 `loc_id` 直接作为行号——如果 `loc_id` 不是行号则产生无意义范围。
- **`[lsp.zig:116-124]`** — `FileMap.add` 中 `entries.put` 失败后 `uri_copy` 泄漏。

### Lazy/Superficial Tests

- **`[cli.zig:246-396]`** — 8 个测试全部丢弃返回值 `_ = output.printSummary(...)` 等——无输出内容断言。
- **`[formatter.zig:474]`** — 断言 `"version": "1.0.0"` 但实际输出 `"2.1.0"` 或 `"0.1.8"`——测试永远失败或从不执行。
- **`[graph_visualizer.zig:706-710]`** — 只检查 `buf.items.len == 0`。
- **`[confidence_scorer.zig]`**、**`[sarif.zig]`** — 整个文件零测试。

---

## 8. src/types/ src/utils/ src/fact/

### Technical Debt

- `[pass_types.zig:540-789]` — `addIssue` 约 250 行，深度嵌套条件——严重违反函数长度准则。
- `[pass_types.zig:1209-1211]` — `diagToNoiseSeverity` 假设 `DiagSeverity` 和 `NoiseSeverity` 共享相同整数映射——脆弱的隐式耦合。
- `[cpp_fp_types.zig:41-56]` — `into_raw_patterns` 和 `from_raw_patterns` 包含 `".*"` 模式但匹配代码使用 `indexOf`（子串匹配不是正则）——模式永远不匹配。
- `[ownership_types.zig:245-263]` — `isMemoryAccess` 将 `u32` 值 ID 转为 `c.LLVMValueRef`——**类型混淆**：值 ID 是哈希表键，不是 LLVM 指针。
- `[callback_escape_types.zig:328-339]` — `isCallbackReceiver` 使用线性数组扫描而非已构建的 trie。
- `[rust_ffi_types.zig:60-64]` — 私有 `getFunctionName` 在 `cpp_fp_helpers.zig` 和 `cpp_fp_types.zig` 中有 3 份副本。
- `[call_graph_types.zig:9]`、`[ip_ffi_types.zig:1]` — 导入但未使用的 LLVM C 绑定。
- `[memory_graph_types.zig:146-147]` — `freed_by` 字段标记为 `DEPRECATED` 但保留。
- `[memory_graph_types.zig:79-91]` — `ResourceLifecycle` 结构体定义但未使用。

### Potential Bugs

- **`[cpp_fp_detect.zig:103,105,179]`** — 三处 `catch {}` 静默吞掉 OOM，丢失去重条目可能导致假阳性 double-free。
- **`[cpp_fp_types.zig:264]`** — **严重类型混淆**：`const is_heap_msg: bool = std.fmt.allocPrint(...)` 将 `![]u8` 错误联合赋给 `bool` 变量。成功时泄漏分配的字符串，`is_heap_msg` 始终为 `true`。
- **`[callback_escape_core.zig:83-86,90-93,116-120]`** — 三处 `allocator.dupe` 分配字符串无对应 free 路径——内存泄漏。
- **`[ownership_types.zig:246,268]`** — 将哈希表 `u32` 键转为 LLVM 指针——如果值 ID 不对应实际 LLVM 指令指针则 UB。
- **`[pass_types.zig:162-170]`** — `markFreed` 在 OOM 时 `catch return true`——调用者认为标记成功但实际失败。
- **`[lock_types.zig:33,48,66]`** — 三处 `@panic("OOM")`——生产代码不应 panic。
- **`[query.zig:235-237]``** — **死锁**：`queryByKindIndexed` 持有 mutex 后调用 `queryByKind` 再次加锁。`std.Thread.Mutex` 不可重入。
- **`[query.zig:258-262]`** — 同样的死锁在 `queryBySubjectIndexed`。
- **`[ownership_analysis.zig:113-117]`** — `param_value_ids: [32]u32` 但循环限制为 `i < 16`，17-32 个参数的函数参数被静默丢失。
- **`[cpp_fp_types.zig:397-401]`** — `LLVMGetInstructionOpcode` 作用于非指令值——UB。

### Lazy/Superficial Tests

- **`[callback_escape_enhanced_test.zig:163-169]`** — 断言 `expect(.missing_keepalive == result1 or .safe == result1)`——接受两种结果，**永远通过**。
- **`[callback_escape_enhanced_test.zig:87-117]`** — 测试本地重新实现的 `isGoUnsafeOperation_from_name` 而非真实的 `isGoUnsafeOperation`。
- **`[ownership_types.zig:357-388]`** — 5 个测试只验证 `@intFromEnum` 值——测试枚举排序而非行为。
- **大量文件零测试**：`thread_types.zig`、`abi_types.zig`、`zone_types.zig`、`memory_graph_types.zig`、`memory_graph_methods.zig`、`call_graph_types.zig`、`alias_types.zig`、`ip_ffi_types.zig`、`rust_ffi_types.zig`、`callback_escape_types.zig`、`word_boundary.zig`。

---

## 9. tests/

### Technical Debt

- `[main.zig:19-23]` — "coverage: summary" 测试只打印调试输出，零断言。
- `[main.zig:166-175 vs 299-308]` — 完全重复的测试（"SemanticRegistry: layer counts" vs "Regression: layer counts unchanged"）。
- `[p0p6_benchmark.zig:80-82,117,161,295]` — 多处 `_ = pair.cwe; _ = pair.severity; _ = sym.spec_source;` 丢弃文档化字段。
- `[e2e_ir_test.zig:83-101 vs 199-218]` — 近乎重复的多文件分析测试。

### Potential Bugs

- **`[regression.zig:44 vs main.zig:142]`** — 矛盾断言：`regression.zig` 断言 `RiskKind` 有 **13** 个变体，`main.zig` 断言 **20** 个。
- **`[regression.zig:132 vs main.zig:356]`** — 矛盾断言：`UnsafeMutablePointer` 的 kind 分别是 `.borrow_escaped` 和 `.allocator`。
- **`[ffi_integration_test.zig:66]`** — `expect(result != null)` 对错误联合使用——语义错误。
- **`[e2e_ir_test.zig:80]`** — `expect(result.fact_count >= 0)` — `usize` 无符号，**永远为真**。
- **`[e2e_ir_test.zig:255-256]`** — 同样的同义反复 `>= 0` 断言。

### Lazy/Superficial Tests — 最严重的问题

#### 完全造假的测试（从未调用 OmniScope）

| 文件 | 测试数 | 问题 |
|------|--------|------|
| `tests/p0p6_benchmark.zig` | 7/7 | 硬编码 `status = true`、本地数组计数，从未调用任何 OmniScope 函数 |
| `tests/ffi_benchmark.zig` | 6/6 | `_ = expected_languages; try std.testing.expect(true);` — **永远通过** |
| `tests/integration/main.zig` | 11/11 | 硬编码 `passed = true, actual_issues = 0`，有 `TODO: Replace with actual pipeline execution result` |
| `tests/integration/issue_verification.zig` | 3/4 | `metrics.true_positives = expected_count;` 硬编码完美检测率 |
| `tests/benchmark/main.zig` | 7 | P0-P6 测试是本地数组计数 |

#### 测试 Zig stdlib 而非 OmniScope

| 文件 | 测试 | 问题 |
|------|------|------|
| `tests/ffi_integration_test.zig:69-81` | "FFI function name matching" | 测试 `std.mem.eql(u8, "register_transaction", "register_transaction")` |
| `tests/ffi_integration_test.zig:100-115` | "Multi-file FFI analysis" | 创建 ArrayList 追加 2 个字符串 |
| `tests/ffi_integration_test.zig:136-163` | "Cross-language data flow" | 分配字符串检查 `len > 0` |
| `tests/ffi_integration_test.zig:165-178` | "FFI memory safety" | `test_data[0] = 42; expectEqual(42, test_data[0])` |
| `tests/stress/main.zig:136-143` | "boundary: empty string" | `expectEqual(0, "".len)` |
| `tests/stability/main.zig:92-103` | "stability: null pointer" | `if (ptr) |_| expect(false)` |

#### 弱断言

- `tests/e2e_ir_test.zig:80,255` — `>= 0` on `usize`（永远真）
- `tests/regression.zig:30-36` — `l1 > 0` through `l6 > 0`（宽松边界）
- `tests/benchmark/main.zig:229-238` — `l1 > 0`, `total >= 100`, `total < 10000`
- `tests/integration/issue_verification.zig:247,281` — `leak_count >= 10`, `high_priority >= 10`

---

## 10. Build System

### Technical Debt

- `[build.zig:8-12]` — 硬编码 LLVM 路径假设 Homebrew ARM (Apple Silicon)，Intel Mac 路径不同。
- `[build.zig:16-18]` — `getDefaultLLVMVersion()` 总是返回 `"22"` 与 OS 无关。
- `[build.zig:130-158]` — `test` 步骤不包含 `test-integration`、`test-issues`、`test-stability`、`test-stress`，与 Makefile 不一致。
- `[build.zig:147-157]` — `unit_test_mod` 未接收 `optimize` 选项——始终 Debug。
- `[build.zig:88-102]` — `verify-ir` 步骤引用不存在的 `verify_ir_loading.zig`——死代码。
- `[build.zig.zon:34-63]` — 整个 `dependencies` 块是注释掉的模板代码。
- `[Makefile:605]` — `corpus-check` 打印字面 `%` 字符——看起来是残留。
- `[Makefile:640]` — `red-team` 写入 `/tmp/omniscope-red-team` 但从未使用。
- `[Makefile:485-495]` — `clean` 目标不清理 `benchmark-output/` 和 `$(EXAMPLES_DIR)/reports/`。
- `[Makefile:772,745]` — 版本号引用过时的 `v0.1.6`，当前版本 `0.2.0`。

### Potential Bugs

- **`[build.zig:92]`** — 引用不存在的 `verify_ir_loading.zig`，`zig build verify-ir` 会失败。
- **`[build.zig:219-223,232-236,245-249,258-262,290-294,303-307]`** — 6 个测试模块缺少 `configureLLVM` 调用，如果测试使用 LLVM 函数则链接失败。
- **`[Makefile:416-424]`** — `real-world-ir` 用 `2>/dev/null || true` 编译，编译失败被静默吞掉。
- **`[Makefile:523-544]`** — 所有 `corpus-ir` 编译步骤用 `2>/dev/null || true`。
- **`[Makefile:796-797]`** — `open` 命令仅 macOS 可用，Linux 应用 `xdg-open`。
- **`[Makefile:659]`** — `red-team` 阈值 10 太低，8 个 IR 文件每个预期 ≥10 个问题，阈值应为 ~80。
- **`[Makefile:72]`** — `all: test-all bench` — 成功横幅暗示所有类别通过但实际只确认最后一个前提条件。

---

## 11. scripts/

### Technical Debt

- `[corpus_verify.sh:4]` — 硬编码绝对路径 `/Users/scc/code/zigcode/OmniScope/corpus`——其他机器上会断。
- `[full_corpus_analysis_final.sh:10]` — 硬编码 Homebrew LLVM 路径。
- `[full_corpus_analysis.sh:75-76]` — 硬编码 `39` 文件计数——语料库变化时会错。
- `[benchmark.sh:297-301]` — 硬编码基准目标 (`0.40`, `0.70`, `0.54`)。
- `[benchmark.sh:354-431]` — `generate_json_report` 重复了 `print_summary` 中的精度/召回/F1 计算。
- `[run_audit.sh:134-148,227-240]` — 内嵌 Python 代码——难以维护、测试或 lint。
- `[run_audit.sh vs run_realworld.sh]` — `analyze_file` 和 `generate_summary` 函数大量重复。
- `[translate_cn.sh:3]` — 600+ 字符单行 `find | xargs grep` 命令。
- `[translate_cn.sh:6-59]` — 53 个顺序 `sed -e` 替换——应放入独立映射文件。
- `[run_audit.py:2,22,86]` — 版本字符串 `0.1.7` 与 shell 脚本的 `0.1.8` 不一致。
- `[regression_test.sh:107,122]`、`[run_audit.py:68]` — 裸 `except:` 捕获所有异常——隐藏真实错误。

### Potential Bugs

- **`[test.sh:29]`** — 变量拼写错误 `${ELAPED}` 应为 `${ELAPSED}`——展开为空字符串。
- **`[corpus_verify.sh:36]`** — `FILES=($(find ...))` 数组赋值在文件名含空格时断词分割。
- **`[full_corpus_analysis.sh:83-84]`** — `ls "$OUTDIR/*.json"` 双引号内 glob 不展开——永远返回 0 匹配。
- **`[full_corpus_analysis_final.sh:128-129]`**、**`[full_corpus_analysis_llvm22.sh:110-112]`** — 同样的 broken `ls` 模式。
- **`[stability_test.sh:73-76]`** — 错误的行续接使 `log_fail` 成为 OmniScope 的参数而非错误处理器。
- **`[release.sh:19]`** — `for arg in "$@"` 循环中的 `shift` 无效——`for` 迭代的是 `$@` 的快照。
- **`[bench_perf.sh:92]`** — `N/A` 未加引号写入 JSON——产生无效 JSON。
- **`[bench_perf.sh:26-29]`** — 检查 `build/OmniScope` 但其他脚本使用 `zig-out/bin/OmniScope`。
- **`[bench_perf.sh:40]`** — `eval "$cmd"` 命令注入风险。
- **`[install_deps.sh:82]`** — `curl | bash` 无校验和验证。
- **`[translate_cn.sh:6]`** — `sed -i ''` 是 macOS 特定语法，GNU sed 用 `sed -i`。
- **多处 `cd` 副作用**：`stability_test.sh:34`、`regression_test.sh:40`、`release.sh:80,105,119`、`bench_perf.sh:28` 中的 `cd` 改变调用者的工作目录。

---

## 12. Dependency Graph Analysis

### Overview

| Metric | Value |
|--------|-------|
| Total modules | 247 |
| Total import edges | 917 |
| Avg imports per module | 3.7 |
| Orphan modules | 26 |
| Circular dependencies | 7 |
| Layering violations | 125 |

### Circular Dependencies (7 cycles)

| # | Modules | Description |
|---|---------|-------------|
| 1 | `ffi_language_classifier` ↔ `ffi_utils` ↔ `language_detector` | FFI ↔ semantics 交叉依赖 |
| 2 | `surface_classifier` ↔ `mangled_name`/`linkage`/`debug_origin` | Surface classifier 互依赖 |
| 3 | `memory_graph` ↔ `memory_graph_test` | 测试导入循环 |
| 4 | `rust_ffi_auditor` ↔ `rust_ffi_rules_{basic,lifetime,advanced}` | Rust FFI 规则互依赖 |
| 5 | `ptr_lifetime` ↔ `ptr_lifetime_test` | 测试导入循环 |
| 6 | `ffi_boundary` ↔ `ffi_parallel` | FFI 并行处理循环 |
| 7 | `callback_escape` ↔ `callback_escape_test` | 测试导入循环 |

### Coupling Hotspots

**Most Imported (fan-in):**

| Module | Imported By |
|--------|-------------|
| `src/ir/llvm_raw.zig` | **110** — 极端耦合 |
| `src/pass/pass.zig` | **69** |
| `src/diag/issue.zig` | **58** |
| `src/common/log.zig` | **24** |
| `src/pass/analysis/ptr_lifetime/ptr_lifetime_types.zig` | **20** |

**Most Dependent (fan-out):**

| Module | Imports |
|--------|---------|
| `src/root.zig` | **69** |
| `src/types/pass_types.zig` | **28** — 高耦合风险 |
| `src/pass/analysis/ptr_lifetime/ptr_lifetime.zig` | **27** |
| `src/pipeline/pipeline.zig` | **23** |

### Layering Violations (125 violations)

主要模式：
- **`types/` → `ir/`** (14 violations): 类型定义依赖 LLVM IR 层
- **`types/` → `semantics/`** (10 violations): `pass_types.zig` 导入语义分析模块
- **`types/` → `dataflow/`** (6 violations): 类型模块依赖数据流基础设施
- **`types/` → `fact/`** (2 violations): 类型定义依赖事实存储

`src/types/pass_types.zig` 单独贡献了 **~20 个层级违规**。

### Orphan Modules (26 modules never imported)

**Dead code candidates:**
- `src/pass/analysis/steensgaard.zig` — 未接入的分析 pass
- `src/pass/analysis/transmute_detection.zig` — 未注册的检测 pass
- `src/pass/instrumentation/planner.zig` — 未接入的插桩
- `src/diag/aggregator.zig` — 未使用的诊断聚合器
- `src/diag/confidence_scorer.zig` — 未使用的置信度评分
- `src/ir/location.zig` — 未使用的 IR 位置模块
- `src/dataflow/guard_propagation.zig` — 未接入的 guard 传播
- `src/pass/filter/issue_gate.zig` — 未使用的问题过滤器
- `src/semantics/attribute.zig` — 未使用的属性模块
- `src/semantics/surface_classifier.zig` — 未使用的顶层分类器
- `src/semantics/resource/{allocator_family,arena_inference,model_mining,ownership_state}` — 未使用的资源分析模块
- `src/perf/bench_compare.zig` — 未接入的基准比较
- `src/pass/analysis/resource/path_analyzer.zig` — 未接入的路径分析器

---

## Priority Recommendations

### P0 — Critical (立即修复)

1. **修复死锁** — `src/fact/query.zig:235,258` 中的 mutex 重入
2. **修复类型混淆** — `src/types/cpp_fp_types.zig:264` 的 bool 赋值、`src/types/ownership_types.zig:246,268` 的 u32→指针转换
3. **修复 use-after-free** — `src/diag/issue.zig:326` 的栈指针返回、`src/engine/loader.zig:77` 的悬垂 ModuleRef
4. **修复 JSON 格式错误** — `src/output/formatter.zig:158-194`
5. **修复测试造假** — 删除或重写 `tests/p0p6_benchmark.zig`、`tests/ffi_benchmark.zig`、`tests/integration/main.zig` 中的假测试

### P1 — High (本周修复)

6. **修复内存泄漏** — `src/diag/aggregator.zig` 多处缺少 errdefer、`src/pass/analysis/thread_crossing.zig` trace 泄漏、`src/registry/config_loader.zig:292` tags 泄漏
7. **修复错误静默吞掉** — 替换所有 `catch {}` 为适当的错误处理
8. **修复 `@panic("OOM")`** — `src/types/lock_types.zig:33,48,66`、`src/pass/analysis/lock.zig:53,273`
9. **修复影子化 bug** — `src/registry/posix_io_reg.zig`、`layer1_reg.zig` vs `python_c_api_reg.zig`、`layer1_reg.zig` vs `jni_reg.zig`
10. **修复 build.zig** — 添加缺失的 `configureLLVM` 调用、删除不存在的文件引用

### P2 — Medium (本月修复)

11. **消除死代码** — 26 个孤儿模块、多个自文档 "NOT yet wired" 模块
12. **消除代码重复** — `semantic_registry.zig` 15 层复制粘贴、`language_detector.zig` 3 份 Go 运行时检测、JSON 转义 3 份
13. **修复层级违规** — `pass_types.zig` 导入 28 个模块跨 5 层
14. **重写测试** — 所有使用 `expect(true)`、本地数组计数、`>= 0` 的测试
15. **修复脚本** — 变量拼写错误、文件名空格处理、`ls` glob 引号问题

### P3 — Low (技术债务清理)

16. 拆分超长函数（`addIssue` 250 行、`run()` 438 行、`analyzeFunction` 305 行）
17. 消除魔数，引入命名常量
18. 统一错误处理模式
19. 补充模块文档
20. 清理过时版本号引用
