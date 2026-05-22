# 红蓝队测试指南

**版本**: v0.1.9
**目的**: 用 `corpus/` 测试套件验证 OmniScope 的检出率（红队）和误报率（蓝队）。

## 快速开始

```bash
make red-team       # 红队：能检测到已知漏洞吗？
make blue-team      # 蓝队：会不会误报？
make corpus-test    # 两个都跑
```

***

## 第一部分：红队 — 对抗性检测测试

### 测试内容

对 `corpus/red_team_test/` 中的**已知漏洞**文件运行 OmniScope（内存泄漏、double-free、use-after-free、FFI 边界违规）。衡量**召回率** — 工具能捕获多少注入的漏洞。

### 运行日志（真实输出）

```
╔════════════════════════════════════════════════════════════════╗
║                    RED TEAM TEST                              ║
║  Adversarial: detect known bugs in crafted test cases         ║
╚════════════════════════════════════════════════════════════════╝
  ✅ red_team_bugs.ll                         25 issues
  ✅ ffi_boundary_bugs.ll                     18 issues
  ✅ cross_lang_free_bugs.ll                  12 issues
  ✅ cross_lang_free_complete.ll              15 issues
  ✅ subtle_ffi_bugs.ll                        8 issues
  ✅ python_c_api_bugs.ll                     10 issues
  ✅ posix_ffi_bugs.ll                         6 issues
────────────────────────────────────────────────────────
  Red Team: 7 files, 94 total issues detected
  ✅ Detection threshold met
```

### 逐行解读

#### 标题栏

```
╔════════════════════════════════════════════════════════════════╗
║                    RED TEAM TEST                              ║
╚════════════════════════════════════════════════════════════════╝
```

测试横幅。Makefile 目标 `red-team`（定义在 `Makefile:640`）先触发 `build`，然后遍历 `RED_IR_FILES`。

#### 单文件结果

```
  ✅ red_team_bugs.ll                         25 issues
```

| 字段 | 含义 |
|------|------|
| `✅` | 文件产出了 ≥1 个 issue（通过） |
| `❌` | 文件产出 0 个 issue（漏检 — 可能有回归） |
| `red_team_bugs.ll` | 测试文件名 |
| `25 issues` | OmniScope 检出的 issue 总数 |

**如何定位源码**：每个 `.ll` 文件由同目录下的 `.c` 文件编译而来：

```
corpus/red_team_test/red_team_bugs.c      ← 注入了漏洞的源码
corpus/red_team_test/red_team_bugs.ll     ← 编译后的 LLVM IR（OmniScope 分析的输入）
```

#### 汇总行

```
  Red Team: 7 files, 94 total issues detected
```

- `7 files` — 存在且被分析的 `.ll` 文件数
- `94 total issues` — 所有文件的 issue 总和

#### 阈值检查

```
  ✅ Detection threshold met
```

如果 `total_issues < 10`，测试报告 `⚠️ LOW detection count — investigate regressions`。这是一个粗略的合理性检查，不是精确的基准测试。精确的检出率请使用 `make benchmark`。

### 深入单个文件

查看单个测试文件的完整 OmniScope 输出：

```bash
./zig-out/bin/OmniScope corpus/red_team_test/red_team_bugs_O0.ll 2>&1
```

#### 启动阶段

```
info: [INFO] === OmniScope IR Analysis ===
info: [INFO] File: corpus/red_team_test/red_team_bugs_O0.ll
info: [INFO] Loaded: 35 functions
```

| 日志行 | 含义 |
|--------|------|
| `=== OmniScope IR Analysis ===` | 分析会话开始 |
| `File: ...` | 输入 LLVM IR 文件路径 |
| `Loaded: 35 functions` | 从 IR 中解析的函数数量 |

#### 语言检测

```
info: [INFO] LANG-DETECT: module language = c, confidence = 100.0%, method = sampling
```

| 字段 | 含义 |
|------|------|
| `module language = c` | 模块中的主要语言 |
| `confidence = 100.0%` | 确信度（sampling 方法统计函数名模式） |
| `method = sampling` | `sampling` = 统计方法；`personality` = DWARF 调试信息 |

`sampling` 方法遍历所有函数名，统计语言特定模式（`_ZN` 对应 C++/Rust，`_R` 对应 Rust v0，`Go.` 对应 Go 等）。

#### 预扫描器

```
info: [INFO] MallocCheck: Analyzed functions, found 9 unchecked allocations
info: [INFO] IntegerOverflow: Analyzed functions, found 0 potential overflows
info: [INFO] BufferOverflow: No buffer overflow issues detected
info: [INFO] ReturnCheck: Analyzed functions, found 1 unchecked return values
info: [INFO] RustFfiFilter: analyzed 17 funcs, 0 findings (0 stack escapes)
```

| 扫描器 | 检查内容 |
|--------|---------|
| `MallocCheck` | `malloc()` 返回值未做 null 检查 |
| `IntegerOverflow` | 可能溢出的算术运算 |
| `BufferOverflow` | 数组越界 |
| `ReturnCheck` | FFI 调用的返回值未检查 |
| `RustFfiFilter` | 无 FFI 相关性的 Rust 函数（跳过） |

#### 跨语言边提取

```
info: [INFO] CallGraph: extracted 15 cross-language edges
info: [INFO] CallGraph: built semantics CallGraph with 35 nodes, 63 edges for BFS traversal
```

| 字段 | 含义 |
|------|------|
| `15 cross-language edges` | 调用者和被调用者属于不同语言的调用 |
| `35 nodes, 63 edges` | 用于 BFS 可达性分析的调用图大小 |

每条边记录 `(caller_name, callee_name, caller_lang, callee_lang)`。当 `caller_lang != callee_lang` 时，该边是"跨语言"的。

#### 危险表面分析

```
info: [INFO] [P1-1] DangerSurfacePass: 15 FFI, 0 allocs, 0 funcs | Phase1=0ms (args=0 rets=0 alias_traces=0) Phase2=0ms (cross_lang_free=0)
```

| 字段 | 含义 |
|------|------|
| `15 FFI` | MemoryGraph 中的 FFI 边界节点数 |
| `Phase1` | 追踪 call args/rets 穿过 FFI 边界的时间 |
| `Phase2` | 扫描跨语言 free 违规的时间 |
| `cross_lang_free=0` | 发现的跨语言 alloc/free 不匹配数 |

#### 指针所有权分析

```
info: [INFO] PointerOwnership: Source 1 (MemoryGraph) — 59 unfreed + 23 freed = 82 total nodes
info: [INFO] PointerOwnership: Source 2 (GlobalAllocTracker) — 9 records, 0 freed
info: [INFO] PointerOwnership: Source 3 (IR scan) added 32 frees — total now 32
info: [INFO] PointerOwnership: Pre-populated from MemoryGraph + GlobalAllocTracker + IR-scan — 59 allocs, 32 frees
```

这是**三数据源融合**：

| 数据源 | 提供什么 |
|--------|---------|
| Source 1: MemoryGraph | 上游 pass 的分配点 + freed 状态 |
| Source 2: GlobalAllocTracker | 补充 free 追踪 |
| Source 3: IR 扫描 | 直接扫描 LLVM IR 中的 `free`/`dealloc` 调用指令（兜底） |

**如何解读**：`59 unfreed` 表示 59 个分配没有匹配到对应的 free。这些是潜在的内存泄漏。工具随后应用过滤器（RAII、Meyers 单例、引用计数容器）来减少误报。

#### 漏洞行

```
info: [ERROR] VULNERABILITY OMI-001 [medium] [Confidence: MEDIUM]
info: [ERROR] Type: tainted_path_to_sink
info: [ERROR] Reason: Untrusted data flows to sensitive sink without validation
info: [ERROR] Path:
info: [ERROR]   [Sink] printf()
info: [ERROR]   [Source] main() - initial taint source
```

| 字段 | 含义 |
|------|------|
| `OMI-001` | 自增的 issue ID（每次分析运行唯一） |
| `[medium]` | 严重级别：`critical` > `high` > `medium` > `low` |
| `[Confidence: MEDIUM]` | `HIGH` / `MEDIUM` / `LOW` |
| `Type: tainted_path_to_sink` | issue 类别（20+ 种） |
| `Reason:` | 人类可读的问题解释 |
| `Path:` | 从 source 到 sink 的数据流路径 |

**如何在你的代码中定位问题**：

**第一步：找到函数。** 输出中始终包含函数名（mangled）。例如：

```
info: [ERROR]   in _Z37bug_cpp_05_unique_ptr_callback_escapev
```

反混淆函数名：
```bash
# C++ (Itanium ABI)
echo "_Z37bug_cpp_05_unique_ptr_callback_escapev" | c++filt
# → bug_cpp_05_unique_ptr_callback_escape()

# Rust (v0)
rustfilt "_ZN4core3ptr13drop_in_place17h1234E"
# → core::ptr::drop_in_place<Type>
```

然后在你的源码中搜索：
```bash
grep -rn "bug_cpp_05_unique_ptr_callback_escape" src/
```

**第二步：用调试信息获取精确行号。** 如果编译时加了 `-g`，JSON 输出会包含 `file` 和 `line`：

```bash
./zig-out/bin/OmniScope target.ll --json | jq '.issues[] | {function: .location.function, file: .location.file, line: .location.line}'
```

没有 `-g` 时只能看到函数名。**始终用 `-g` 编译以获得可操作的报告。**

**第三步：理解 issue 类型。** 每种类型对应特定的源码模式：

| Issue 类型 | 在你的代码中找什么 |
|-----------|------------------|
| `memory_leak` | `malloc`/`new`/`Box::new` 没有匹配的 `free`/`delete`/`drop` |
| `use_after_free` | 指针在 `free()` 或 `Box::from_raw()` 之后继续使用 |
| `double_free` | 同一个指针被释放两次 |
| `cross_lang_free_mismatch` | Rust 中分配（`Box::into_raw`），C 中释放（`free`）— 或反过来 |
| `borrow_escape` | 栈指针或 `&mut` 传给 FFI 函数，但生命周期不够长 |
| `tainted_path_to_sink` | 用户输入到达 `system()`/`exec()`/`printf()` 且未校验 |
| `null_dereference` | `malloc` 或 FFI 调用后未检查 null 就使用指针 |
| `buffer_overflow` | 数组访问时未检查索引 |
| `ffi_unsafe_call` | 以错误的指针类型或生命周期调用 FFI 函数 |
| `format_string` | `printf`/`sprintf` 中使用非字面量格式串 |

**第四步：用 `--sarif` 集成到 IDE。** SARIF 输出直接映射到源文件，可在 VS Code / GitHub Code Scanning 中内联显示。

#### 性能 Profile

```
info: Operation                           Calls   Total (ms)     Avg (us)     Max (us)
info: --------------------------------------------------------------------------------
info: init                                    1         7.77      7770.96      7770.96
info: analysis                                1         5.89      5888.63      5888.63
info: detect                                  2         3.75      1877.17      1909.58
info: total                                   1         7.78      7775.04      7775.04
```

| 阶段 | 发生了什么 |
|------|-----------|
| `init` | 加载模块，初始化数据结构 |
| `analysis` | 主函数遍历 + 所有权追踪 |
| `detect` | 违规检测（泄漏、double-free、UAF） |
| `total` | 端到端挂钟时间 |

#### 最终汇总

```
info: [INFO] Analysis complete
info: [INFO] Functions processed: 35
info: [INFO] Facts generated: 54
info: [INFO] Time: 24ms
info: [INFO] Issues detected: 25
```

| 字段 | 含义 |
|------|------|
| `Functions processed` | 分析的函数数（经过 zone/noise 过滤后） |
| `Facts generated` | 向 fact store 发射的 fact 数（alias、taint、ownership） |
| `Time` | 总分析挂钟时间 |
| `Issues detected` | 发现的 issue 总数（红队统计的就是这个数字） |

***

## 第二部分：蓝队 — 误报审计

### 测试内容

对 `corpus/{small,medium,ffi-dense}` 测试文件运行 OmniScope，将检出数与预期的 in-scope 阈值对比。衡量**精确率** — 工具是否过度报告。

### 运行日志（真实输出）

```
╔════════════════════════════════════════════════════════════════╗
║                    BLUE TEAM TEST                             ║
║  Defensive: false positive audit on corpus                    ║
╚════════════════════════════════════════════════════════════════╝

── small/ (expected ≤13 in-scope issues)
  ✅ small/:        11 issues (expected ≤13, ok)
── medium/ (expected ≤20 in-scope issues)
  ✅ medium/:       16 issues (expected ≤20, ok)
── ffi-dense/ (expected ≤26 in-scope issues)
  ✅ ffi-dense/:    28 issues (expected ≤26, OVER)

────────────────────────────────────────────────────────
  Blue Team: 2 passed, 1 failed
  ⚠️  False positive regression detected
```

### 逐行解读

#### 目录标题

```
── small/ (expected ≤13 in-scope issues)
```

正在测试的 corpus 目录和预期上限。阈值来自 `corpus/EXPECTED_RESULTS.md`：

| 目录 | 预期 in-scope | 来源 |
|------|--------------|------|
| `small/` | 13 issues（4 个文件 × ~3 个 issue） | `EXPECTED_RESULTS.md:198` |
| `medium/` | 20 issues（1 个文件，14 in-scope + 6 out-of-scope） | `EXPECTED_RESULTS.md:202` |
| `ffi-dense/` | 26 issues（4 个文件，4+6+6+6 in-scope） | `EXPECTED_RESULTS.md:204-207` |

#### 通过/失败结果

```
  ✅ small/:        11 issues (expected ≤13, ok)
```

| 符号 | 含义 |
|------|------|
| `✅` | issue 数在预期范围内 |
| `❌` | issue 数超出预期（可能有误报回归） |

阈值有约 **50% 的余量**，用于容纳版本间合理的检测差异。目的是捕获**大幅膨胀**，而非微小波动。

#### 汇总

```
  Blue Team: 2 passed, 1 failed
  ⚠️  False positive regression detected
```

如果任何目录失败，整体蓝队结果为警告。通过在单个文件上运行 OmniScope 来调查：

```bash
./zig-out/bin/OmniScope corpus/ffi-dense/output/sqlite_binding.ll 2>&1
```

将 issue 列表与 `corpus/EXPECTED_RESULTS.md` 对比，识别哪些是真实 issue，哪些是误报。

***

## 第三部分：贡献者参考 — OmniScope 内部实现

> **注意**：本节面向 OmniScope 开发者/贡献者。如果你是**用户**，想在自己的代码中定位问题，请参阅上方的[漏洞行](#漏洞行)一节。

### 每行日志的 OmniScope 源码位置

| 日志模式 | OmniScope 源文件 | 函数 |
|---------|-----------------|------|
| `=== OmniScope IR Analysis ===` | `src/main.zig` | `runSingleFileAnalysis` |
| `LANG-DETECT: module language` | `src/semantics/language_detector.zig` | `detectModuleLanguage` |
| `MallocCheck: Analyzed functions` | `src/pass/analysis/malloc_check.zig` | `run` |
| `IntegerOverflow: Analyzed functions` | `src/pass/analysis/issue/integer_overflow.zig` | `run` |
| `CallGraph: extracted N cross-language edges` | `src/pass/analysis/call_graph.zig` | `extractCrossLangEdges` |
| `DangerSurfacePass: N FFI` | `src/pass/analysis/danger_surface.zig` | `run` |
| `FFITypeMismatch: analyzed N calls` | `src/pass/analysis/ffi_type_mismatch.zig` | `run` |
| `PointerOwnership: Source 1` | `src/pass/analysis/pointer_ownership.zig` | `run`（第 265 行） |
| `VULNERABILITY OMI-NNN` | `src/diag/issue.zig` | `Issue.init` |
| `Issues detected: N` | `src/main.zig` | `emitOutput` |
| `GlobalAllocTracker: N memory leaks` | `src/semantics/global_alloc_tracker.zig` | `confirmLeaks` |

### Issue 类型 → 检测 Pass（OmniScope 内部）

| Issue 类型 | 检测 Pass |
|-----------|----------|
| `memory_leak` | `pointer_ownership.zig:detectViolations` |
| `cross_lang_free_mismatch` | `cpp_fp_reduction.zig:detectCrossLangAllocMismatch` |
| `use_after_free` | `cpp_fp_reduction.zig:detectUseAfterFree` |
| `double_free` | `cpp_fp_reduction.zig:detectDoubleFree` |
| `null_dereference` | `pointer_ownership.zig:detectNullDereferences` |
| `borrow_escape` | `pointer_ownership.zig:detectAsPtrBorrowEscape` |
| `tainted_path_to_sink` | `taint.zig` |
| `ffi_unsafe_call` | `ffi_boundary.zig:checkCallForFFI` |
| `buffer_overflow` | `buffer_overflow.zig` |
| `integer_overflow` | `issue/integer_overflow.zig` |
| `format_string` | `format_string.zig` |

### Corpus 文件 → 源码映射

| IR 文件 | 源文件 | 注入的漏洞 |
|---------|--------|-----------|
| `red_team_bugs_O0.ll` | `red_team_bugs.c` | 内存泄漏、UAF、double-free、null 解引用、格式字符串 |
| `ffi_boundary_bugs.ll` | `ffi_boundary_bugs.c` | FFI 边界违规、栈逃逸 |
| `cross_lang_free_bugs.ll` | `cross_lang_free_bugs.c` | Rust→C、C→C++ free 不匹配 |
| `subtle_ffi_bugs.ll` | `subtle_ffi_bugs.c` | 细微 FFI 模式（realloc、部分清理） |
| `python_c_api_bugs.ll` | `python_c_api_bugs.c` | Python C API 误用（Py_DECREF、引用计数） |
| `posix_ffi_bugs.ll` | `posix_ffi_bugs.c` | POSIX API 误用（FILE*、fd 泄漏） |
| `cpp_ffi_simple.ll` | `cpp_ffi_simple.cpp` | C++ new/delete 不匹配、RAII 逃逸 |
| `boundary_test.ll` | `boundary_test.c` | FFI 边界 null 解引用、循环所有权 |
| `stress_patterns.ll` | `stress_patterns.c` | 70 个漏洞：alloc 泄漏、跨语言不匹配、调用链 |
| `sqlite_binding.ll` | `sqlite_binding.c` | SQLite 资源泄漏、悬空指针 |
| `openssl_wrapper.ll` | `openssl_wrapper.c` | OpenSSL ctx/bio/key 泄漏 |
| `zlib_binding.ll` | `zlib_binding.c` | zlib 流泄漏、double-free、UAF |
