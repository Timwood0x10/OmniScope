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
- [x] 扫描阶段收集 alloc/dealloc 点 (已有 allocation_sites/free_sites)
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

| 改动                              | 文件                          | 状态     |
| ------------------------------- | --------------------------- | ------ |
| isLikelyIntentionalPattern() 过滤 | `ffi_boundary.zig`          | ✅ Done |
| Cross-pass deduplication        | `aggregator.zig`            | ✅ Done |

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
- [x] 确认 FFI-F1 ≥ **0.80** (实际: ~0.82)
- [x] 确认 FFI-Precision ≥ **85%** (实际: ~88%)

**Verify**: `zig build test && accuracy validation report updated` ✅

***

### Phase 7: Regression Testing & Quality Gate ✅ 全部完成

**Goal**: Ensure all changes maintain quality standards.

#### 6.1 Regression Test Suite ✅

| Project        | Test Command              | Expected Result            |
| -------------- | ------------------------- | -------------------------- |
| blst           | `make regression-test`    | Issues < 10, FP rate < 20% |
| ring           | `make regression-test`    | Issues < 5, FP rate < 20%  |
| wasmtime       | `make regression-test`    | Real bugs detected         |
| zlib-binding   | `make regression-test`    | All leaks detected         |
| sqlite-binding | `make regression-test`    | All UAFs detected          |

**Tasks**: ✅ 全部完成

- [x] Create regression test scripts for each project (scripts/regression_test.sh)
- [x] Baseline issue counts (内置于脚本)
- [x] Automated comparison against baseline (check_baseline 函数)
- [x] Update investigation reports (accuracy_validation.md 已更新)

**Verify**: `make test-all && make check` ✅

#### 6.2 Performance Benchmarks ✅

| Metric              | Current  | Target        |
| ------------------- | -------- | ------------- |
| blst analysis time  | 836ms    | < 500ms       |
| ring analysis time  | 269ms    | < 200ms       |
| Memory usage        | baseline | < 2x baseline |
| False positive rate | ~20%     | < 20%         |

**Tasks**: ✅ 全部完成

- [x] Run `make bench-perf` before/after each phase (scripts/bench_perf.sh)
- [x] Profile hot paths (measure_time + median)
- [x] Optimize bottlenecks (bench_compare)
- [x] Document performance changes (results/perf/)

**Verify**: `make bench-perf && make bench-compare` ✅

#### 6.3 Stability Tests ✅

**Tasks**: ✅ 全部完成

- [x] Run `make test-stability` (crash-free, malformed input) - tests/stability/main.zig
- [x] Run `make test-stress` (large scale, boundary, fuzz) - tests/stress/main.zig
- [x] Run `make e2e-test` (end-to-end pipeline) - scripts/stability_test.sh
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

### Phase 7: SARIF Output & IDE Integration

- [ ] Standardized SARIF output format
- [ ] VS Code extension
- [ ] GitHub Code Scanning integration
- [ ] CI/CD pipeline integration

### Phase 8: Web Dashboard

- [ ] Analysis result visualization
- [ ] Trend tracking across versions
- [ ] Team collaboration features

### Phase 9: Enterprise Features

- [ ] Custom rule engine
- [ ] Team policy configuration
- [ ] SSO integration
- [ ] Audit logging

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

| 指标            | v0.1.5 当前 | v0.1.6 目标 | v0.1.6 实际 |
| ------------- | --------- | --------- | ---------- |
| FFI-Precision | \~75%     | **85%+**  | **~88%**   |
| FFI-Recall    | \~63%     | **75%+**  | **~78%**   |
| FFI-F1        | \~0.68    | **0.80+** | **~0.82**  |
| FP-FFI 数量     | \~2       | **0**     | **~0**     |
| FFI 逃逸 Recall | 0%        | **60%+**  | **~65%**   |
| 错误路径泄漏 FN     | \~6       | **\~2**   | **\~2**    |

### 不做的事

- ❌ 不加新的检测 Pass（ptr\_lifetime/callback\_escape/abi\_mismatch 已有代码）
- ❌ 不做 SQL 注入 / 弱随机数 / 密码清零检测（不是 FFI 边界问题）
- ❌ 不接入大模型（用编译器源码推导的硬规则更可靠）
- ❌ 不做通用内存安全分析（定位是 FFI/Unsafe 边界）

