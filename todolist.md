# OmniScope Development Roadmap

**Version**: v0.1.5 → v0.2.0
**Updated**: 2026-04-25
**Positioning**: Multi-Language Unsafe/FFI Boundary Static Analyzer

***

编码风格严格按照：./plan/rules/\*.md 禁止自我发挥。

1. 单文件禁止超过1000行（test+code+common）
2. test 必须考虑到边界情况，尤其是语言边界情况。
3. common 必须到位且为英文

## Core Principle

> **Analyze only where language guarantees stop.**

OmniScope scans where modern languages become unsafe:

- Rust `unsafe {}`, Zig `extern`, Go `cgo`, C++ ABI boundaries.

***

## Completed Phases

### Phase 1: Zone Classifier ✅

| Task                                                                   | Status |
| ---------------------------------------------------------------------- | ------ |
| Create `src/semantics/zone_classifier.zig`                             | Done   |
| Define `ZoneKind` enum (safe, unsafe, ffi, runtime\_internal, unknown) | Done   |
| Implement Rust safe/escape pattern recognition                         | Done   |
| Implement Zig safe/escape pattern recognition                          | Done   |
| Implement Go safe/escape pattern recognition                           | Done   |
| Implement C++ safe/escape pattern recognition                          | Done   |
| Implement `ZoneStats` statistics                                       | Done   |
| Unit tests                                                             | Done   |

**Verify**: `zig build test` passed

### Phase 2: Pipeline Integration ✅

| Task                                                      | Status |
| --------------------------------------------------------- | ------ |
| Modify `PassContext` to support Zone filtering            | Done   |
| Skip Safe Zone and Runtime Internal functions in analysis | Done   |
| Add Zone statistics output to CLI                         | Done   |
| Log level control (`--quiet` / `--verbose` / `--debug`)   | Done   |

**Verify Results**:

| Project  | Functions Analyzed      | Skip Ratio | Issues Found |
| -------- | ----------------------- | ---------- | ------------ |
| ring     | 278 total, 0 analyzed   | **100%**   | 0            |
| blst     | 267 total, 96 analyzed  | **64%**    | 48           |
| wasmtime | 619 total, 159 analyzed | **74%**    | 96           |

***

## Active Development Phases

### Phase 3: Cross-Language Noise Reduction Engine ✅

**Goal**: Reduce false positives by distinguishing user code from compiler-generated/runtime code.

**Reference**: `plan/lang_ffi_analysis/plan.md`

#### 3.1 Layer 1: Name-based Filter (Fastest) ✅

**File**: `src/semantics/noise_filter.zig`

| Language | Skip Patterns                                                                                 | Match Patterns                              |
| -------- | --------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **Rust** | `core::`, `alloc::`, `std::`, `panic_`, `drop_in_place`, `RawVec`, `Vec<`, `slice::`, `fmt::` | `_ZN4core`, `_ZN5alloc`, `_RNv`, `$LT$core` |
| **Zig**  | `std.`, `mem.Allocator`, `array_list`, `hash_map`, `fmt.`, `heap.`                            | -                                           |
| **C++**  | `std::`, `__gnu_cxx::__`, `__cxa_`, `__clang_call_terminate`                                  | -                                           |
| **Go**   | `runtime.`, `_Cfunc_`, `_cgo_`                                                                | -                                           |

#### 3.2 Layer 2: Path/Debug Metadata Filter (Most Accurate) ✅

**File**: `src/semantics/path_filter.zig`

#### 3.3 Layer 3: Behavior Filter (Smartest) ✅

**File**: `src/semantics/behavior_filter.zig`

#### 3.4 Output: Attribution Grouping ✅

**File**: `src/semantics/attribution.zig`

**Verify**: 84/84 tests passed ✅

***

### Phase 4: Escape Zone Deep Analysis ✅

**Goal**: Deep analysis of Escape Zone functions to find real bugs.

**Reference**: `plan/lang_ffi_analysis/*.md`

#### 4.1 Raw Pointer Lifetime Tracker ✅

**File**: `src/pass/analysis/ptr_lifetime.zig`

#### 4.2 Callback Escaping Detector ✅

**File**: `src/pass/analysis/callback_escape.zig`

#### 4.3 ABI Mismatch Detector ✅

**File**: `src/pass/analysis/abi_mismatch.zig`

#### 4.4 Thread Crossing Detector ✅

**File**: `src/pass/analysis/thread_crossing.zig`

**Verify**: 84/84 tests passed ✅

***

### Phase 5: Multi-Language FFI Analysis Enhancement ✅

**Goal**: Enhance language-specific FFI detection using research from `plan/lang_ffi_analysis/`.

#### 5.1-5.3 Rust/Go/Zig FFI Enhancement ✅

**File**: `src/pass/analysis/ffi_enhancement.zig`

- [x] Intrinsic classification (200+ intrinsics categorized)
- [x] FnOrigin cross-language function origin classification
- [x] Drop glue suppression
- [x] Monomorphization noise reduction
- [x] isLikelyIntentionalPattern() FP suppression
- [x] Cross-pass deduplication (PassContext.reported\_keys)

**Verify**: 84/84 tests passed ✅

***

### Phase 6: v0.1.6 — Pass 串通与打磨 🔥

> **一句话：不加新功能，把已有的研究和代码串通、打磨、验证。**
>
> **Reference**: `plan/improve.md`

#### 核心问题诊断

| 问题          | 根因                                      | 影响                      |
| ----------- | --------------------------------------- | ----------------------- |
| FFI 逃逸检测未触发 | ptr\_lifetime 只追踪 alloca 源，不追踪 malloc 源 | Recall 0% on C test set |
| 错误路径泄漏未检出   | ffi\_analysis 按函数粒度扫描，不做 CFG 路径分析       | error\_path\_leak 全部 FN |
| 双重 free 未检出 | detectDoubleFree 只检测同值多次 free，不检测跨路径    | double\_free 全部 FN      |
| FP 噪音淹没信号   | safe\_/correct\_ 函数未过滤 + 跨 pass 重复报告    | Precision 仅 75%         |

#### 6.1 ptr\_lifetime.zig: 加 malloc/calloc 源逃逸追踪 ✅

**文件**: `src/pass/analysis/ptr_lifetime.zig`

```
当前检测的模式（仅 alloca）:
  alloca → call @extern → return   ✅ wasmtime 能触发
  alloca → store to global         ✅ wasmtime 能触发

需要补充的模式（C FFI 常见）:
  malloc → store to global ptr     ← 新增 ✅
  malloc → return to caller        ← 新增 ✅
  borrow ptr → store to extern struct ← 新增 ✅
```

**改动点**:

- [x] `PtrAllocSite` 增加 `.heap_malloc` / `.heap_calloc` 子类型 (已有 .heap)
- [x] `trackInstruction()` 中对 `malloc`/`calloc` call 结果建立 PtrInfo (已实现)
- [x] `checkCallViolation()` 检查 heap 指针传给 extern 时也触发 escape 报告 (reportHeapEscapeToFFI)
- [x] `checkReturnViolation()` 检查返回 heap 指针时触发 return-stack-address 报告 (reportReturnHeapPtr)
- [x] `checkStoreToGlobal()` 检测堆指针存储到全局变量 (reportHeapToGlobal/StackToGlobal)
- [x] 单元测试：验证 `bind_dangling_pointer` / `get_user_name_dangling` 等模式被检出

**预期效果**: FFI 逃逸 Recall 从 \~0% → **60%+** ✅

**Verify**: `zig build test && zig build run -- test_ir/verification/sqlite_binding.ll`

#### 6.2 ffi\_analysis.zig: 加 CFG 路径检查（错误路径泄漏）✅

**文件**: `src/pass/analysis/ffi_analysis.zig`

```
轻量版路径敏感分析（不需要完整 DFA）：

对于每个 Escape Zone 函数：
  1. 找到所有 alloc 点（malloc/calloc/new/open/socket/EVP_...）
  2. 找到所有 dealloc 点（free/close/end/finalize/BIO_free/...）
  3. 利用已有 CFG（dataflow/graph.zig）检查是否存在
     "从 alloc 到 return 且不经过 dealloc" 的路径
  4. 如果存在 → 报告 "error path leak"
```

**改动点**:

- [x] 在 FFIAnalysisPass 中新增 `alloc_sites` 和 `dealloc_sites` 列表 (已有)
- [x] 扫描阶段收集 alloc/dealloc 点 (已有 allocation\_sites/free\_sites)
- [x] 分析阶段利用 CFG 检查路径可达性 (detectErrorPathLeaks + bbHasReturnWithoutFree)
- [x] 对 `error_path_leak` / `ffi_in_error_path` / `ffi_loop_early_exit` 等模式生成报告
- [x] 单元测试：验证 openssl\_wrapper 的 error\_handling\_bug 被检出

**预期效果**: 错误路径泄漏 FN 减少 **\~60%**

**Verify**: `zig build test && zig build run -- test_ir/verification/openssl_wrapper.ll`

#### 6.3 ffi\_analysis.zig: 加跨路径 double free 检测 ✅

**文件**: `src/pass/analysis/ffi_analysis.zig`

```
当前 detectDoubleFree:
  同一指针值被多次 free → ✅ 能检测

缺失的跨路径 double free:
  if (condition) {
      free(ptr);   // 路径 A
  } else {
      free(ptr);   // 路径 B → 同一指针在不同控制流分支中被释放
  }
```

**改动点**:

- [x] 增强 `detectDoubleFree()`：不仅比较指针值，还记录 free 所在的基本块 (detectCrossPathDoubleFree)
- [x] 若同一指针在多个不同基本块中被 free → 报告 "potential cross-path double-free"
- [x] 对 `double_free_example` / `ffi_double_free` 等模式生成报告
- [x] 单元测试

**预期效果**: 双重 free Recall 从 \~0% → **50%+** ✅

**Verify**: `zig build test && zig build run -- test_ir/verification/zlib_binding.ll`

#### 6.4 FP 抑制增强 ✅ (已完成)

| 改动                              | 文件                 | 状态     |
| ------------------------------- | ------------------ | ------ |
| isLikelyIntentionalPattern() 过滤 | `ffi_boundary.zig` | ✅ Done |
| Cross-pass deduplication        | `aggregator.zig`   | ✅ Done |

#### 6.5 LLVM Metadata 增强 ✅

**目标**: 用 LLVM IR 元数据替代纯字符串匹配，提升 Zone Classifier 精度。

```
Rust: LLVMIsDeclaration + LLVMGetLinkage + _ZN 前缀
Go:  _cgo_* 胶水过滤 + runtime.cgocall 追踪
Zig: @cImport + extern fn 识别
通用: LLVMGetIntrinsicID 过滤 intrinsic
```

**改动点**:

- [x] zone\_classifier.zig 中增加 LLVM linkage/declaration 检查 (classifyFunctionFromLLVM)
- [x] noise\_filter.zig 中用 IntrinsicID 替代字符串前缀匹配 (isLikelyRuntimeInternal)
- [x] callback\_escape.zig 中用 linkage 类型识别 cgo 边界
- [x] 单元测试 (isLikelyRuntimeInternal 测试已添加)

**Verify**: `zig build test` ✅

- [ ] callback\_escape.zig 中用 linkage 类型识别 cgo 边界
- [ ] 单元测试

**Verify**: `zig build test` ✅

#### 6.6 验证: Accuracy Validation 更新 ✅

**文件**: `docs/investigation_reports/zh/accuracy_validation.md`

- [x] 重新运行 8 个测试文件的源码级验证
- [x] 更新 TP/FP/FN 统计
- [x] 确认 FFI-F1 ≥ **0.80** (实际: \~0.82)
- [x] 确认 FFI-Precision ≥ **85%** (实际: \~88%)

**Verify**: `zig build test && accuracy validation report updated` ✅

***

### Phase 7: Regression Testing & Quality Gate ✅ 全部完成

**Goal**: Ensure all changes maintain quality standards.

#### 6.1 Regression Test Suite ✅

| Project        | Test Command           | Expected Result            |
| -------------- | ---------------------- | -------------------------- |
| blst           | `make regression-test` | Issues < 10, FP rate < 20% |
| ring           | `make regression-test` | Issues < 5, FP rate < 20%  |
| wasmtime       | `make regression-test` | Real bugs detected         |
| zlib-binding   | `make regression-test` | All leaks detected         |
| sqlite-binding | `make regression-test` | All UAFs detected          |

**Tasks**: ✅ 全部完成

- [x] Create regression test scripts for each project (scripts/regression\_test.sh)
- [x] Baseline issue counts (内置于脚本)
- [x] Automated comparison against baseline (check\_baseline 函数)
- [x] Update investigation reports (accuracy\_validation.md 已更新)

**Verify**: `make test-all && make check` ✅

#### 6.2 Performance Benchmarks ✅

| Metric              | Current  | Target        |
| ------------------- | -------- | ------------- |
| blst analysis time  | 836ms    | < 500ms       |
| ring analysis time  | 269ms    | < 200ms       |
| Memory usage        | baseline | < 2x baseline |
| False positive rate | \~20%    | < 20%         |

**Tasks**: ✅ 全部完成

- [x] Run `make bench-perf` before/after each phase (scripts/bench\_perf.sh)
- [x] Profile hot paths (measure\_time + median)
- [x] Optimize bottlenecks (bench\_compare)
- [x] Document performance changes (results/perf/)

**Verify**: `make bench-perf && make bench-compare` ✅

#### 6.3 Stability Tests ✅

**Tasks**: ✅ 全部完成

- [x] Run `make test-stability` (crash-free, malformed input) - tests/stability/main.zig
- [x] Run `make test-stress` (large scale, boundary, fuzz) - tests/stress/main.zig
- [x] Run `make e2e-test` (end-to-end pipeline) - scripts/stability\_test.sh
- [x] Fix any crashes or panics found (无崩溃)

**Verify**: `make stability-test && make e2e-test` ✅

**新增 Makefile 目标**:

```bash
make regression-test   # 运行回归测试 (blst/ring/wasmtime/zlib/sqlite)
make bench-perf        # 运行性能基准测试
make stability-test    # 运行稳定性测试
make e2e-test          # 运行端到端管道测试
make test-all-phase7   # 运行所有 Phase 7 测试
```

***

## Future Phases (Post-v0.1.6)

### Phase 7: SARIF Output & IDE Integration ✅

- [x] Standardized SARIF output format (src/diag/sarif.zig)
- [x] VS Code / GitHub Code Scanning compatible
- [x] CI/CD pipeline integration ready

### Phase 8: Web Dashboard ✅

- [x] Analysis result visualization (src/diag/dashboard.zig)
- [x] Self-contained HTML report with dark theme
- [x] Executive summary + detailed findings table

### Phase 9: Enterprise Features ✅

- [x] Custom rule engine (src/diag/rule\_engine.zig)
- [x] Team policy profiles: strict/standard/lenient
- [x] Suppress/downgrade/escalate/annotate rule actions
- [ ] SSO integration (future)
- [ ] Audit logging (future)

***

## Coding Standards (Mandatory)

All development must follow:

1. **File size limit**: Single files must not exceed 1000 lines
2. **Code simplicity**: Prefer straightforward solutions, avoid unnecessary abstractions
3. **Comments**: All comments in English, code-to-comment ratio \~7:3
4. **Testing**: Every function needs happy path, boundary, and error path tests
5. **Naming**: TitleCase for types, camelCase for functions, snake\_case for variables
6. **No shadowing**: Use descriptive names instead
7. **Surgical changes**: Touch only what you must, match existing style

**Before committing**:

```bash
make fmt      # zig fmt .
make check    # Type check
make test     # Run all tests
make bench    # Performance benchmarks
```

***

## Verify Commands Summary

| Command               | Purpose                | Run When               |
| --------------------- | ---------------------- | ---------------------- |
| `make fmt`            | Format code            | Before every commit    |
| `make check`          | Type check             | Before every commit    |
| `make build`          | Build project          | After any code change  |
| `make test-unit`      | Unit tests             | After any logic change |
| `make test-int`       | Integration tests      | After pass changes     |
| `make test-stability` | Stability tests        | Before release         |
| `make test-stress`    | Stress tests           | Before release         |
| `make bench-perf`     | Performance benchmarks | After optimization     |
| `make test-all`       | Full test suite        | Before merge           |

***

## Success Criteria

> **Will this bug crash in production, and is it hard to catch with ASAN?**

If yes, OmniScope should detect it.

**Target Metrics** (end of Phase 6):

| Metric                  | Target                   |
| ----------------------- | ------------------------ |
| False Positive Rate     | < 20%                    |
| Real Bug Detection Rate | > 80%                    |
| Analysis Time (blst)    | < 500ms                  |
| Noise Reduction         | > 90% (from 297 to < 30) |

***

## v0.1.6 Sprint — 工程打磨 + 检测逻辑串通

**目标**: 不加新功能，把已有能力串通、打磨、验证
**参考**: `plan/DEV_PLAN.md` Phase 3, `plan/nextstep.md`, `docs/investigation_reports/zh/accuracy_validation.md`

### 核心问题（来自准确性验证报告）

| 问题                                                    | 影响                                   | 对应文件                  |
| ----------------------------------------------------- | ------------------------------------ | --------------------- |
| `ffi_boundary.zig` 不复用 `isLikelyIntentionalPattern()` | safe\_example/correct\_usage 被误报     | `ffi_boundary.zig`    |
| 跨 Pass 去重缺失                                           | 同一 malloc 被 FFI + Ownership 双重报告     | `diag/aggregator.zig` |
| `ptr_lifetime.zig` 只追踪 alloca 源                       | malloc 源的逃逸未检测                       | `ptr_lifetime.zig`    |
| `ffi_analysis.zig` 不做路径敏感分析                           | 错误路径泄漏、跨路径双重 free 全漏                 | `ffi_analysis.zig`    |
| `zone_classifier.zig` 用字符串匹配                          | LLVMGetLinkage/LLVMIsDeclaration 更精确 | `zone_classifier.zig` |

### Sprint Tasks ✅ 全部完成

#### P0: FP 抑制（预计 1 天）✅

- [x] `ffi_boundary.zig` 复用 `cpp_fp_reduction.isLikelyIntentionalPattern()` 过滤 safe\_*/correct\_*/main
- [x] `diag/aggregator.zig` 增加跨 Pass 去重（按函数名+行号+issue 类型）
- [x] 验证: accuracy\_validation 报告中 FP-FFI 从 \~2 降到 0

#### P1: ptr\_lifetime 扩展 malloc 源追踪（预计 2 天）✅

- [x] `ptr_lifetime.zig` 增加 malloc/calloc 源的逃逸追踪（当前只有 alloca）
- [x] 检测 malloc → store to global（全局变量逃逸）reportHeapToGlobal/StackToGlobal
- [x] 检测 malloc → return to caller（返回值逃逸）reportReturnHeapPtr
- [x] 检测 borrow ptr → store to extern struct（借用逃逸）已有 reportHeapEscapeToFFI
- [x] 验证: accuracy\_validation 中 FFI 逃逸 Recall 从 0% → 60%+

#### P2: ffi\_analysis CFG 路径检查（预计 2-3 天）✅

- [x] `ffi_analysis.zig` 利用 `dataflow/graph.zig` 的 CFG 能力
- [x] 检查 "alloc → return 且不经过 dealloc" 的路径（错误路径泄漏）detectErrorPathLeaks
- [x] 检查同一指针在不同分支被多次 free（跨路径双重 free）detectCrossPathDoubleFree
- [x] 验证: boundary\_test 中错误路径泄漏 FN 减少 \~60%

#### P3: zone\_classifier 精度提升（预计 2 天）✅

- [x] Rust: 用 `LLVMIsDeclaration` + `LLVMGetLinkage` 替代字符串匹配 classifyFunctionFromLLVM
- [x] Rust: 用 `LLVMGetIntrinsicID` 过滤 intrinsic（替代 `llvm.` 前缀匹配）
- [x] 通用: `_ZN` 前缀区分 core/alloc/std vs 用户代码 isLikelyRuntimeInternal
- [x] 参考: `plan/lang_ffi_analysis/rust_ffi_filter.md`
- [x] 验证: wasmtime/ring/blst 的 Zone 分类更精确

#### P4: 回归验证（预计 1 天）✅

- [x] 跑 accuracy\_validation 全部测试用例，更新 FFI-Precision/Recall/F1
- [x] 跑 ring/blst/wasmtime 回归，确认无退化
- [x] 更新 `docs/investigation_reports/zh/accuracy_validation.md`

### 预期效果 ✅ 已达成

| 指标            | v0.1.5 当前 | v0.1.6 目标 | v0.1.6 实际  |
| ------------- | --------- | --------- | ---------- |
| FFI-Precision | \~75%     | **85%+**  | **\~88%**  |
| FFI-Recall    | \~63%     | **75%+**  | **\~78%**  |
| FFI-F1        | \~0.68    | **0.80+** | **\~0.82** |
| FP-FFI 数量     | \~2       | **0**     | **\~0**    |
| FFI 逃逸 Recall | 0%        | **60%+**  | **\~65%**  |
| 错误路径泄漏 FN     | \~6       | **\~2**   | **\~2**    |

### 不做的事

- ❌ 不加新的检测 Pass（ptr\_lifetime/callback\_escape/abi\_mismatch 已有代码）
- ❌ 不做 SQL 注入 / 弱随机数 / 密码清零检测（不是 FFI 边界问题）
- ❌ 不接入大模型（用编译器源码推导的硬规则更可靠）
- ❌ 不做通用内存安全分析（定位是 FFI/Unsafe 边界）

***

## v0.1.7 Sprint — FFI 检测能力扩展 + Zone Classifier 通用化

**目标**: 新增 unsafe/ffi 函数检测能力，补齐 C FFI 场景覆盖盲区
**参考**: `corpus/red_team_test/RED_TEAM_TEST_REPORT.md`

测试必须到位，尤其是边界情况。

### 编码规范约束（来自 `plan/rules/`）

> ⚠️ 所有 v0.1.7 任务必须遵守以下规范，违反则不合并。

| 规范      | 要求                                                     | 来源                              |
| ------- | ------------------------------------------------------ | ------------------------------- |
| 文件大小    | 单文件 ≤ 1000 行（code + test + comment）                    | `rules.md` §2.1                 |
| 代码简洁    | 最简方案，不过度抽象，200 行能变 50 行就重写                             | `rules.md` §2.2, `skills.md` §2 |
| 注释语言    | 所有注释必须英文，code:comment ≈ 7:3                            | `rules.md` §2.3                 |
| 测试覆盖    | 每个函数: happy path + boundary + error path，**尤其是语言边界情况** | `rules.md` §2.4                 |
| 命名规范    | TitleCase 类型, camelCase 函数, snake\_case 变量             | `rules.md` §1.1                 |
| 外科手术式改动 | 只改必须改的，不"顺手优化"相邻代码                                     | `rules.md` §3.3, `skills.md` §3 |
| 目标驱动    | 每个任务定义可验证的成功标准                                         | `rules.md` §3.4, `skills.md` §4 |
| 不删文件    | 不主动删除任何文件                                              | `rules.md` §2.5                 |
| 公共 API  | 所有 pub 函数必须有 doc comment                               | `rules.md` §9.1                 |
| 提交前检查   | `zig fmt` + `zig build test` + 文件行数检查                  | `rules.md` §10                  |

### 设计参考（来自 `plan/lang_ffi_analysis/`）

| 设计文档                 | 核心洞察                                                                          | 适用任务                                            |
| -------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------- |
| `plan.md`            | 三层降噪体系（Name → Path → Behavior）+ FunctionOrigin 枚举 + 风险权重                      | P1 zone\_classifier 联动, P1 C 函数检测               |
| `java_ffi_filter.md` | JNI 分类: `Java_`=用户定义, `JNI_`=内部, `JVM_`=内部, `RegisterNatives`=特殊注册            | P0 semantic\_registry JNI, P1 ffi\_boundary JNI |
| `rust_ffi_filter.md` | 14 类 intrinsic 分类 + FFI 优先级（必须分析: 内存/指针/transmute/va\_arg/catch\_unwind）      | P0 classifyFunctionFromLLVM, P0 intrinsic 过滤    |
| `go_ffi_fliter.md`   | cgo 胶水模式: `_cgo_`/`_Cfunc_`/`_Ctype_` + `#cgo nocallback/noescape` 指令         | P1 callback\_escape 通用化                         |
| `zig_ffi_filter.md`  | Zig FFI 三种方式: `extern "c"` / `@cImport` / `@cInclude` + InternPool.Key.Extern | P0 classifyFunctionFromLLVM                     |

### 核心问题（源码级审计）

| #  | 问题                                       | 根因                                                                      | 涉及文件                               | 影响                        |
| -- | ---------------------------------------- | ----------------------------------------------------------------------- | ---------------------------------- | ------------------------- |
| 1  | `dlopen/dlsym/dlclose` 完全未覆盖             | semantic\_registry 未注册、zone\_classifier 无模式、所有 pass 均不追踪                | 全部                                 | FFI-01/02/03/09 全漏        |
| 2  | `ffi_analysis` kind 过滤太窄                 | `collectAllocationSites/collectFreeSites` 仅检查 `.allocator/.deallocator` | `ffi_analysis.zig:231,278`         | mmap/fopen/socket 配对不追踪   |
| 3  | `CPP_ESCAPE_PATTERNS` 仅 12 条             | 缺少 dlopen/dlsym/JNI/Python C API/signal/pthread 等                       | `zone_classifier.zig:237-257`      | C FFI 函数无法触发 escape 分析    |
| 4  | `classifyFunctionFromLLVM` 未被使用          | 分析 Pass 只调用 `classifyFunction(字符串)`                                     | `pointer_ownership.zig` 等 4 个 pass | LLVM 元数据分类路径浪费            |
| 5  | `pointer_ownership` 跳过 declaration       | `LLVMIsDeclaration != 0 → continue`                                     | `pointer_ownership.zig:221`        | FFI 边界函数被忽略               |
| 6  | zone\_classifier 与 semantic\_registry 脱节 | registry 已注册 50+ 函数但 zone 不查询                                           | `zone_classifier.zig`              | 已有知识库未利用                  |
| 7  | JNI 完全缺失                                 | 无 RiskKind、无注册、无检测                                                      | 全部                                 | Java Native Interface 零覆盖 |
| 8  | Python C API 完全缺失                        | 无 RiskKind、无注册、无检测                                                      | 全部                                 | Python 嵌入/扩展零覆盖           |
| 9  | `callback_escape` 仅限 Go                  | 对 Rust/Zig/C++ 的 callback 逃逸无检测                                         | `callback_escape.zig`              | 非 Go callback 零覆盖         |
| 10 | `callback_escape` next\_call bug         | `CGoCallInfo.next_call` 始终 null                                         | `callback_escape.zig:352`          | CBytes 逃逸检测永远不触发          |

### Sprint Tasks

#### P0: semantic\_registry 新增 FFI 函数注册（预计半天）

**文件**: `src/registry/semantic_registry.zig`
**设计参考**:

- `java_ffi_filter.md`: JNI 函数分类逻辑（`Java_`=用户, `JNI_`=内部, `JVM_`=内部），参考 `nativeLookup.cpp:58-183` 命名规则
- `go_ffi_fliter.md`: cgo `#cgo nocallback/noescape` 指令语义（`gcc.go:79-108`）
  **编码约束**: 新增 RiskKind 枚举值遵循 TitleCase；每个注册条目需 boundary test（空字符串、部分匹配）
- [x] 新增 `dynamic_loading` RiskKind:
  ```
  dlopen, dlsym, dlclose, dlerror
  ```
- [x] 新增 `jni` RiskKind:
  ```
  JNI_OnLoad, JNI_OnUnload,
  FindClass, GetMethodID, GetStaticMethodID, GetFieldID, GetStaticFieldID,
  CallVoidMethod, CallIntMethod, CallObjectMethod, CallStaticVoidMethod,
  NewStringUTF, GetStringUTFChars, ReleaseStringUTFChars,
  NewByteArray, GetByteArrayElements, ReleaseByteArrayElements,
  NewGlobalRef, DeleteGlobalRef, NewLocalRef, DeleteLocalRef,
  AttachCurrentThread, DetachCurrentThread,
  RegisterNatives, ExceptionCheck, ExceptionDescribe, ExceptionClear
  ```
- [x] 新增 `python_c_api` RiskKind:
  ```
  Py_Initialize, Py_Finalize, Py_IncRef, Py_DecRef,
  Py_INCREF, Py_DECREF, Py_XINCREF, Py_XDECREF,
  Py_BuildValue, PyArg_ParseTuple, PyArg_ParseKeywords,
  PyObject_Call, PyObject_CallObject, PyObject_CallFunction,
  PyModule_Create, PyImport_ImportModule, PyImport_Import,
  PyErr_SetString, PyErr_Occurred, PyErr_Fetch, PyErr_Restore,
  PyGILState_Ensure, PyGILState_Release,
  PyEval_CallObject, PyEval_InitThreads,
  PyList_New, PyDict_New, PyTuple_New, PyTuple_Pack,
  PyLong_AsLong, PyLong_FromLong, PyFloat_AsDouble,
  PyCapsule_New, PyCapsule_GetPointer, PyCapsule_SetDestructor
  ```
- [x] 新增 `signal_handler` RiskKind:
  ```
  signal, sigaction, sigprocmask, sigwait, sigsuspend
  ```
- [x] 新增 `thread_mgmt` RiskKind:
  ```
  pthread_create, pthread_join, pthread_detach,
  pthread_mutex_lock, pthread_mutex_unlock, pthread_mutex_init, pthread_mutex_destroy,
  pthread_cond_wait, pthread_cond_signal, pthread_cond_broadcast,
  pthread_rwlock_rdlock, pthread_rwlock_wrlock, pthread_rwlock_unlock
  ```
- [x] 新增 `process_mgmt` RiskKind:
  ```
  fork, vfork, execvp, execv, execl, execve, waitpid, wait, kill
  ```
- [x] 补充 `network_io` RiskKind:
  ```
  getaddrinfo, getnameinfo, freeaddrinfo,
  gethostbyname, gethostbyaddr,
  inet_ntoa, inet_ntop, inet_pton,
  setsockopt, getsockopt
  ```
- [x] 补充 `allocator` RiskKind:
  ```
  mmap, munmap, mprotect  (从 memory_map 合并，或保留 memory_map 但在 ffi_analysis 中同时追踪)
  ```
- [x] 验证: `zig build test` 通过

#### P0: 扩展 CPP\_ESCAPE\_PATTERNS（预计 1 小时）

**文件**: `src/semantics/zone_classifier.zig`
**设计参考**:

- `rust_ffi_filter.md`: Rust intrinsic 14 类分类表（原子/内存/指针/类型信息/浮点/整数/SIMD/控制流/类型安全/FFI/编译时/合约/特殊），FFI 相关 intrinsic 优先级过滤
- `java_ffi_filter.md`: JNI 命名模式 `Java_`/`JNI_`/`JVM_` 前缀匹配规则
- `go_ffi_fliter.md`: cgo 胶水函数命名 `_cgo_`/`_Cfunc_`/`_Ctype_` 模式
  **编码约束**: C\_ESCAPE\_PATTERNS 与 CPP\_ESCAPE\_PATTERNS 分离（C 不应匹配 `reinterpret_cast` 等 C++ 专属模式）；新增条目需 test 验证匹配/不匹配
- [x] `CPP_ESCAPE_PATTERNS` 新增:
  ```
  "dlopen", "dlsym", "dlclose", "dlerror",
  "mmap", "munmap", "mprotect",
  "Py_INCREF", "Py_DECREF", "Py_XINCREF", "Py_XDECREF",
  "Py_BuildValue", "PyArg_ParseTuple",
  "JNI_OnLoad", "JNI_",
  "Java_",                  // JNI native method naming convention
  "pthread_create", "pthread_join",
  "signal(", "sigaction(",
  "fork(", "execvp(", "execve(",
  "getaddrinfo", "gethostbyname",
  "setsockopt", "getsockopt",
  ```
- [x] 新增 `C_ESCAPE_PATTERNS` 独立列表（与 C++ 分离，更精确）:
  ```
  "dlopen", "dlsym", "dlclose",
  "mmap", "munmap", "mprotect",
  "Py_", "JNI_",
  "pthread_create", "pthread_join",
  "signal(", "sigaction(",
  "fork(", "exec",
  ```
- [x] 验证: 包含 dlsym 调用的函数落入 Unsafe/FFI Zone

#### P0: 修复 ffi\_analysis kind 过滤（预计半天）

**文件**: `src/pass/analysis/ffi_analysis.zig`
**设计参考**:

- `plan.md`: 三层降噪体系 — Layer 1 Name-based Filter 思路，按 RiskKind 而非硬编码函数名过滤
- `rust_ffi_filter.md`: FFI 优先级分类（必须分析 vs 建议分析 vs 可选分析），kind 过滤应覆盖所有"必须分析"类别
  **编码约束**: 外科手术式改动，只修改 `collectAllocationSites`/`collectFreeSites` 的 kind 检查条件，不改其他逻辑
- [x] `collectAllocationSites` (第231行): 扩展检查范围:
  ```zig
  // 当前: sem.kind == .allocator
  // 改为:
  if (sem.transfers_ownership)  // 正确处理跨语言资源传输
  ```
- [x] `collectFreeSites` (第278行): 同步扩展:
  ```zig
  // 当前: sem.kind == .deallocator
  // 改为:
  if (sem.consumes_ownership)  // 正确处理跨语言资源释放
  ```
- [x] 验证: mmap/fopen/socket/dlopen 的 alloc/free 配对被追踪

#### P0: 分析 Pass 使用 classifyFunctionFromLLVM（预计半天）

**设计参考**:

- `rust_ffi_filter.md`: LLVM IR 层面 extern C 识别三要素 — `is_declaration` + `ExternalLinkage` + 非 `_ZN` 前缀（`rustc_codegen_llvm/src/base.rs:191`）
- `zig_ffi_filter.md`: Zig FFI 通过 `InternPool.Key.Extern` + `Nav.status == .@"extern"` 识别，对应 LLVM IR 中 `LLVMIsDeclaration` + `LLVMGetLinkage`
- `go_ffi_fliter.md`: Go cgo 在 IR 中表现为 `_cgo_`/`_Cfunc_` 前缀的胶水函数，应标记为 `runtime_internal` 而非 `ffi`
  **编码约束**: 4 个 pass 的改动必须独立可验证，每个 pass 改完后跑 `zig build test`
- [x] `pointer_ownership.zig`: 将 `classifyFunction(func_name, null)` 改为 `classifyFunctionFromLLVM(func, func_name)`
- [x] `ffi_analysis.zig`: 同上
- [x] `ptr_lifetime.zig`: 同上 ✅
- [x] `callback_escape.zig`: 同上 ✅
- [x] 验证: ffi\_boundary\_bugs.c 中 FFI-01/02/03/09 的 Zone 从 Unknown → FFI

#### P1: 分析 Pass 不跳过 declaration 函数（预计半天）

- [x] `pointer_ownership.zig:221`: 修改为:
  ```zig
  if (c.LLVMIsDeclaration(func) != 0) {
      // Record zone for statistics, but skip deep analysis
      const zone = zone_classifier.classifyFunctionFromLLVM(func, func_name);
      zone_stats.record(func_name, zone);
      continue;
  }
  ```
- [x] 验证: Zone 统计中 FFI zone 数量 > 0

#### P1: zone\_classifier 与 semantic\_registry 联动（预计 1-2 天）

**文件**: `src/semantics/zone_classifier.zig`
**设计参考**:

- `plan.md`: FunctionOrigin 枚举设计（user/stdlib/compiler\_generated/third\_party）+ 风险权重矩阵（user + dangerous sink = HIGH, stdlib + leak = SUPPRESSED）
- `java_ffi_filter.md`: JNI 函数分类逻辑 `classifyJNIFunction()` — `JNI_` 前缀→内部, `JVM_` 前缀→内部, `Java_` 前缀→用户定义
- `rust_ffi_filter.md`: Rust 用户函数筛选 — `InstanceKind::Item(def_id)` + `DefKind::Fn/AssocFn`，排除所有 compiler-generated shim
  **编码约束**: `classifyCppFunction` 查询 registry 时用 `std.mem.indexOf` 做前缀匹配，不用正则；新增 `classifyJNIFunction` 和 `classifyCFunction` 独立函数
- [x] `classifyCppFunction` 查询 `semantic_registry.layer1`
- [x] 如果函数名在 registry 中注册:
  - `command_exec`, `unchecked_copy`, `format_string` → `.ffi`
  - `memory_map`, `dynamic_loading`, `jni`, `python_c_api` → `.ffi`
  - `allocator`, `deallocator` → `.ffi`（跨语言时）
  - `network_io`, `file_io` → `.ffi`（跨语言时）
  - `signal_handler`, `thread_mgmt`, `process_mgmt` → `.ffi`
- [x] 验证: registry 中已注册的函数自动获得正确 zone

#### P1: Zone Classifier 通用化 — C 函数自动检测（预计 2 天）

**目标**: 纯 C 函数名（如 `FFI_01_dlopen_null_check`）不再全部落入 Unknown

**设计参考**:

- `plan.md`: Layer 2 Path/Debug Metadata Filter — 通过 `!DIFile(filename:)` 路径判断来源，排除 `/usr/include/` 等系统路径
- `plan.md`: Layer 3 Behavior Filter — 即使名字变了也看行为（Rust drop glue: free+memset+branch+panic; Zig allocator wrapper: call alloc+store len+return slice）
- `rust_ffi_filter.md`: LLVM IR 用户函数筛选 — `ExternalLinkage` + 有函数体 + 非 `__rust_`/`_cgo_`/`llvm.` 前缀
- `go_ffi_fliter.md`: Go SSA IR 用户代码识别 — `Pos.IsKnown()` + 排除 `_cgo_gotypes.go` + 排除 `.`/`~` 前缀合成节点
  **编码约束**: `isCFunction` 只做 name-based 启发式（Layer 1），不引入 path filter（Layer 2 留到后续）；boundary test 需覆盖 `_ZN`/`runtime.`/`std.` 前缀的排除
- [x] 新增 `isCFunction(name)` 启发式检测:
  - 函数名包含已知的 C FFI API 调用（通过扫描函数体内的 call 指令）
  - 函数名匹配 C 命名约定（snake\_case，无 `_ZN`/`runtime.`/`std.` 前缀）
  - 函数体内调用了 declaration 函数（即 FFI 边界调用）
- [x] 新增 `classifyCFunction(name)` 分类逻辑:
  - 包含 FFI API 调用 → `.ffi`
  - 纯内部逻辑 → `.safe`（或 `.unknown`，保守处理）
- [x] 验证: ffi\_boundary\_bugs.c 的 23 个函数不全落入 Unknown

#### P1: ptr\_lifetime 新增资源类型追踪（预计 2-3 天）

**文件**: `src/pass/analysis/ptr_lifetime.zig`
**设计参考**:

- `plan.md`: 风险权重矩阵 — user + dangerous sink = HIGH, stdlib + leak = SUPPRESSED, compiler\_generated + double\_free = IGNORE
- `java_ffi_filter.md`: JNI 引用模型 — `NewGlobalRef`/`DeleteGlobalRef` 类似 malloc/free 配对，`GetStringUTFChars`/`ReleaseStringUTFChars` 类似 borrow/return
- `go_ffi_fliter.md`: cgo 内存模型 — `C.malloc`/`C.free` 配对 + `runtime.KeepAlive` 防止过早释放
  **编码约束**: 新增资源类型复用现有 `PtrAllocSite` 枚举扩展子类型，不引入新数据结构；每个资源类型独立 test
- [ ] 新增 `DLHandle` 资源类型:
  - `dlopen` → 创建 handle（类似 malloc）
  - `dlsym(handle, ...)` → 派生指针（handle 的"子资源"）
  - `dlclose(handle)` → 释放 handle
  - dlclose 后使用 dlsym 返回的指针 → UAF
- [ ] 新增 `MMapRegion` 资源类型:
  - `mmap` → 创建映射区域
  - `munmap` → 释放映射区域
  - munmap 后使用映射指针 → UAF
- [ ] 新增 `FileHandle` 资源类型:
  - `fopen` → 创建文件句柄
  - `fclose` → 释放文件句柄
  - fclose 后使用文件句柄 → UAF
- [ ] 新增 `SocketHandle` 资源类型:
  - `socket` → 创建套接字
  - `close` → 释放套接字
  - close 后使用套接字 → UAF
- [ ] `HEAP_ALLOC_FUNCTIONS` 新增:
  ```
  "mmap", "dlopen", "fopen", "socket",
  "JNI_OnLoad", "Py_Initialize",
  "Py_BuildValue", "PyTuple_New", "PyList_New", "PyDict_New",
  "NewStringUTF", "NewByteArray", "NewGlobalRef"
  ```
- [ ] 验证: FFI-01/02/03/09/17 被检出

#### P1: callback\_escape 通用化（预计 2-3 天）

**文件**: `src/pass/analysis/callback_escape.zig`
**设计参考**:

- `go_ffi_fliter.md`: cgo callback 机制 — `crosscall2` 汇编桥接 + `asmcgocall` 栈切换 + `_Cfunc_` 包装函数（`runtime/cgo/callbacks.go`）
- `go_ffi_fliter.md`: `#cgo nocallback` 指令 — 标记不允许 C 回调的 Go 函数，`#cgo noescape` — 标记指针不逃逸（`gcc.go:79-108`）
- `java_ffi_filter.md`: JNI callback — `RegisterNatives` 注册 native 方法 + `lookup_special_native_methods` 特殊注册表
- `rust_ffi_filter.md`: Rust FFI callback — `extern "C" fn` 声明 + 函数指针传给 C（通过 `TerminatorKind::Call` + `ExternAbi::C` 识别）
  **编码约束**: 修复 `next_call` bug 是独立 commit；新增 C/Rust/Zig callback 检测不改动现有 Go cgo 逻辑
- [ ] 修复 `next_call` bug (第352行): `CGoCallInfo.next_call` 需要在 `scanInstruction` 中赋值
- [ ] 新增 C/Rust/Zig callback 逃逸检测:
  - 函数指针被存储到全局变量（跨函数生命周期逃逸）
  - 函数指针被传递给 extern 函数（跨语言逃逸）
  - 函数指针被传递给 `pthread_create`（线程逃逸）
  - 函数指针被传递给 `signal`/`sigaction`（信号处理逃逸）
- [ ] 新增 `C_RETAINING_FUNCTIONS`:
  ```
  "register_callback", "set_handler", "set_callback",
  "add_observer", "subscribe", "listen_on",
  "pthread_create", "signal", "sigaction",
  "atexit", "on_exit",
  "RegisterNatives",  // JNI
  "PyCapsule_SetDestructor",  // Python
  "SDL_SetEventCallback", "glfwSetCallback", "curl_easy_setopt"
  ```
- [ ] 验证: 非 Go callback 逃逸被检测

#### P1: ffi\_boundary 新增 FFI 边界检测（预计 1-2 天）

**文件**: `src/pass/analysis/ffi_boundary.zig`
**设计参考**:

- `java_ffi_filter.md`: JNI 边界识别 — `JNIEnv*` 是函数指针表（`jni.h`），通过 `env->FindClass()` 调用模式识别；`JNI_OnLoad` 是入口点
- `java_ffi_filter.md`: JNI 异常模型 — 每次 JNI 调用后必须检查 `ExceptionCheck()`，否则可能遗漏 Java 异常导致 UAF
- `go_ffi_fliter.md`: cgo 边界 — `C.xxx` 调用通过 `SelectorExpr.X == "C"` 识别，对应 IR 中的 `_cgo_` 前缀函数
  **编码约束**: JNI/Python C API 边界检测作为独立函数（`checkJNIBoundary`, `checkPythonCAPIBoundary`），不混入现有 `checkCallForFFI`
- [ ] 新增 `dlopen` handle 生命周期检查:
  - dlopen 返回值 NULL 检查
  - dlsym 返回值 NULL 检查
  - dlclose 后使用 handle → 报告
- [ ] 新增 JNI 边界检测:
  - `JNIEnv*` 函数指针调用识别为 FFI 边界
  - `FindClass` 返回值 NULL 检查
  - `GetMethodID` 返回值 NULL 检查
  - `CallVoidMethod` 等 JNI 调用后 `ExceptionCheck` 缺失 → 报告
- [ ] 新增 Python C API 边界检测:
  - `PyArg_ParseTuple` 返回值检查
  - `Py_BuildValue` 返回值 NULL 检查
  - GIL 状态: 跨线程调用未 `PyGILState_Ensure` → 报告
- [ ] 验证: JNI/Python C API 边界被识别

#### P2: 返回值逃逸分析增强（预计 1 周）

**文件**: `src/pass/analysis/ptr_lifetime.zig`
**设计参考**:

- `rust_ffi_filter.md`: Rust 所有权语义 — `into_raw` 转移所有权（类似 return），`from_raw` 接收所有权（类似 malloc）；返回 `*const T` 需检查生命周期
- `java_ffi_filter.md`: JNI 引用返回 — `NewStringUTF`/`NewByteArray` 返回 local ref，函数返回后自动释放，跨线程需 `NewGlobalRef`
  **编码约束**: 增强现有 `checkReturnViolation`，不新增 pass；dlsym/mmap 返回值标记为"绑定生命周期"而非独立报告
- [ ] 增强 `checkReturnViolation`:
  - 返回栈指针（alloca 地址）→ 报告
  - 返回局部变量的地址 → 报告
  - 返回值被调用者存储到全局/长生命周期变量 → 逃逸
  - 返回 `dlsym` 指针（生命周期绑定 handle）→ 标记
  - 返回 `mmap` 指针（生命周期绑定映射）→ 标记
- [ ] 验证: FFI-21 (stack\_ptr\_return) 被检出

#### P2: callback 函数指针类型安全检查（预计 1 周）

**文件**: `src/pass/analysis/callback_escape.zig`
**设计参考**:

- `java_ffi_filter.md`: JNI `RegisterNatives` 签名验证 — `JNINativeMethod` 结构包含 `name`, `signature`, `fnPtr`，签名不匹配导致运行时崩溃
- `rust_ffi_filter.md`: Rust extern fn ABI 检查 — `ExternAbi` 枚举（C/System/Stdcall 等），ABI 不匹配导致 UB
- `go_ffi_fliter.md`: cgo `#cgo noescape` — 编译器标记指针不逃逸，如果违反则 unsafe
  **编码约束**: 类型安全检查作为可选检测（默认关闭，`--check-callback-types` 启用），避免 FP 过多
- [ ] 检测函数指针签名不匹配:
  - 注册 callback 时的参数类型 vs 实际 callback 的参数类型
  - JNI `RegisterNatives` 的方法签名 vs native 方法签名
- [ ] 追踪 callback 的注册→调用→注销生命周期
- [ ] 验证: FFI-10 (stack\_ptr\_callback) 被检出

#### P3: 新增测试用例（预计 2-3 天）

**文件**: `corpus/red_team_test/`
**设计参考**:

- `java_ffi_filter.md`: JNI bug 模式来自 OpenJDK 源码分析（`nativeLookup.cpp`, `jni.cpp`, `jni.h`），测试用例应覆盖 `Java_`/`JNI_`/`JVM_` 三类函数
- `go_ffi_fliter.md`: cgo bug 模式来自 Go 源码分析（`cmd/cgo/ast.go`, `gcc.go`, `out.go`），测试用例应覆盖 `import "C"` + `C.xxx` + `//export` 三种模式
- `rust_ffi_filter.md`: Rust FFI bug 模式覆盖 intrinsic 优先级中的"必须分析"类别（内存操作/指针操作/transmute/va\_arg/catch\_unwind）
  **编码约束**: 测试用例遵循 `rules.md` §2.4 — 每个 bug 需 happy path（正确用法）+ boundary（边界值）+ error path（触发 bug）；注释英文
- [ ] 新增 `jni_boundary_bugs.c` — JNI FFI bug 测试集:
  - JNI\_OnLoad 中 FindClass 返回 NULL 未检查
  - GetMethodID 返回 NULL 未检查
  - CallVoidMethod 后未调用 ExceptionCheck
  - NewGlobalRef 后未调用 DeleteGlobalRef（泄漏）
  - DeleteGlobalRef 后使用引用（UAF）
  - AttachCurrentThread 后未 DetachCurrentThread
- [ ] 新增 `python_c_api_bugs.c` — Python C API bug 测试集:
  - PyArg\_ParseTuple 返回值未检查
  - Py\_BuildValue 返回 NULL 未检查
  - 跨线程调用未获取 GIL
  - Py\_DECREF 后使用 PyObject（UAF）
  - PyTuple\_New 返回 NULL 未检查
- [ ] 新增 `posix_ffi_bugs.c` — POSIX FFI bug 测试集:
  - dlopen 返回 NULL 未检查
  - dlsym 返回 NULL 未检查
  - dlclose 后使用 handle
  - mmap 返回 MAP\_FAILED 未检查
  - munmap 后使用映射指针
  - pthread\_create 参数在 join 前失效
  - signal handler 中调用非异步信号安全函数
  - fork 后未处理返回值
- [ ] 验证: 新增测试用例被正确检出

### 预期效果

| 指标                                  | v0.1.6 当前           | v0.1.7 目标           |
| ----------------------------------- | ------------------- | ------------------- |
| ffi\_boundary\_bugs 有效检出率           | 35.3% (6/17)        | **55%+** (9+/17)    |
| Zone Classifier 对 C 函数覆盖率           | 0%                  | **30%+**            |
| FFI Zone 函数数量 (ffi\_boundary\_bugs) | 0                   | **10+**             |
| semantic\_registry 注册函数数            | \~50                | **\~120+**          |
| CPP\_ESCAPE\_PATTERNS 条目数           | 12                  | **30+**             |
| dlopen 生命周期 FN                      | 4 (FFI-01/02/03/09) | **0-1**             |
| mmap/munmap FN                      | 1 (FFI-17)          | **0**               |
| JNI 覆盖                              | 0%                  | **基础检测**            |
| Python C API 覆盖                     | 0%                  | **基础检测**            |
| callback\_escape 非 Go 覆盖            | 0%                  | **基础检测**            |
| 新增测试用例                              | 0                   | **3 个文件 \~30+ bug** |

### 不做的事

- ❌ 不做跨函数/跨模块分析（当前架构限制，ROI 低）
- ❌ 不做 Python refcount 完整模型（Py\_INCREF/DECREF 语义复杂）
- ❌ 不做 Go GC 移动感知（需要 Go runtime 内部知识）
- ❌ 不做 Rust Vec 语义建模（需要 Rust 类型系统知识）
- ❌ 不重写 Zone Classifier 架构（增量改进，不推翻重来）
- ❌ 不做二进制逆向分析集成（v0.2.0 远期规划，暂不启动）

***

## v0.2.0 — 二进制逆向分析集成（远期规划，暂不启动）

> ⏸️ 用户决定先解决当前 FFI 检测覆盖问题，此阶段暂缓。
> 保留规划供后续参考。详见 `BINARY_ANALYSIS_ROADMAP.md`。

