# 更新日志

OmniScope 的所有重要变更都将记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/spec/v2.0.0.html)。

## [0.2.0] - 2026-06-09

### 发布重点

OmniScope 0.2.0 合并 0.1.9 稳定性修复，并完成一次面向语义分析和多语言 FFI 的大规模重构。相对 `master`，本版本新增语义解析、surface 分类、资源契约、语言覆盖、Symbol Graph 导出面、更完整的 FFI 检查，以及更大的测试和语料矩阵。

> **注意**：本版本不单独发布 0.1.9，相关修复内容已并入 0.2.0。

### 新增（Added）

- Semantic Resolution Tree、pattern detectors、语义注册表集成、平台/运行时 profile，以及基于 Issue Gate 的抑制机制。
- Symbol Graph：按符号进行语言/ABI 分类，并支持 FFI 导出 surface 报告。
- 资源模型：resource family、函数 summary、transfer inference、issue candidate 和 issue verifier。
- 语言 adapter 与语言覆盖系统，用于处理歧义或混合语言 LLVM IR。
- FFI pass：ABI 兼容、类型不匹配、布局不匹配、字符串安全、unwind 边界、callback 生命周期、GC 安全、JNI 泄漏、跨语言数据流。
- CLI 新增 `--report-surfaces`、语言覆盖、配置加载/生成、surface 过滤、泄漏阈值、Zig allocator tracking、per-pass 性能统计。
- IRStore、instruction cache、traversal index、arena、string interning、prefix trie、Aho-Corasick matcher 和并行 pipeline 脚手架。
- inline IR 测试、跨语言集成 fixture、golden baseline 文档、语料验证脚本和 CI workflow 覆盖。

### 变更（Changed）

- 将分析代码重组到 `src/pass/analysis/{ffi,ptr_lifetime,rust_ffi,noise,resource,taint}` 等聚焦模块。
- 将共享类型和工具迁移到 `src/types`、`src/common`、`src/resource`、`src/semantics/resource`。
- 重做 pipeline 编排：集中 pass 注册、依赖解析、PassContext 实现、单文件/多文件 runner。
- 文档重组为 `docs/en`、`docs/zh` 和 `docs/touser`，并更新 README 架构图、CLI 和 pass 职责。
- 扩展 C、C++、Rust、Zig、Go、Java、Python、C#/.NET FFI 的语言配置。

### 修复（Fixed）

- 统一 0.2.0 CLI 与输出路径中的版本号。
- 修复代码审查发现的多个内存泄漏、double-free 风险、OOM 处理路径和静默丢诊断问题。
- 修复 C/C++ 模块的 FFI boundary 处理和下游 pass 依赖。
- 修复 Rust allocator/drop 语义、C/C++ allocator/deallocator 分类、所有权转移抑制、callback escape 和跨语言 free 误报。
- 修复元数据较弱或歧义模块中的语言检测与覆盖行为。

### 文档（Documentation）

- 新增和更新 `docs/en` 下的 quick start、API reference、architecture、modules、passes、compiler IR patterns 和语言 IR specs。
- 新增和更新 `docs/zh` 下的架构、模块、pass、报告解读、compiler IR patterns、baseline spec 和语言 IR specs。
- 新增 `docs/touser/en/ToUser.md` 与 `docs/touser/zh/ToUser.md`，解释 OmniScope 面向用户的 FFI 内存安全问题背景。
- README 与 README_zh 更新为精简版：包含架构/数据流 Mermaid 图、pass 职责、CLI 参考和 `docs/touser` 链接。

## [0.1.9] - 2026-05-22

> **发布计划更新**：0.1.9 的修复内容会并入 0.2.0 发布线。合并版发布说明见 `RELEASE_NOTES.md`。

### Bug 修复与性能优化

零精度损失的关键 bug 修复和性能改进。

#### Bug 修复

- **P0**: 新增 `integer_overflow` 到 `IssueKind` 枚举，修正 CWE-190 映射（原错误映射到 CWE-120）
- **P1**: 修复 `call_graph.zig` 错误路径中的内存泄漏（为 `ptr_args_owned` 添加 errdefer）
- **P2**: 修复 `ffi_detector.zig` opcode 比较方式，改用直接 `c.LLVMCall` 替代 `@enumFromInt`（3 处）
- **L4**: 统一所有输出中的版本号为 `v0.1.9`

#### 性能优化

- **C1**: 将 `pointer_ownership.zig` 中 8 次独立模块遍历合并为 3 次（−67% LLVM API 调用）
- **C3**: 在 `isLeaked`/`isDoubleFreed`中使用已有的 `call_ret_by_ptr` 索引（O(N²) → O(1)）
- **C5**: 为 `classifyFunction` 结果添加 1024 条目缓存（无字符串分配）
- **OPT #1**: 在 `addFlowEdge` 期间增量构建 `reverse_flow`（消除一次完整遍历）
- **OPT #2**: 为 `isRustFFIRelevantFunction` 结果添加缓存

#### 精度验证

所有优化经验证无精度损失：

| 测试集 | Issues (v0.1.8) | Issues (v0.1.9) | 损失 |
|--------|----------------|----------------|------|
| Rust | 15 | 15 | ✅ 无 |
| C++ | 13 | 13 | ✅ 无 |
| Zig | 213 | 213 | ✅ 无 |
| Go | 8 | 8 | ✅ 无 |
| 真实项目 | 46 | 46 | ✅ 无 |

#### 技术债务

- 活跃 bug：6 → 0（全部修复）
- 延迟优化：P1 (ptr_lifetime gate)、P2 (pipeline traversal) — 设计权衡，非 bug

## [0.1.8] - 2026-05-13

### 质量审计

系统性的代码质量和安全审计。输出标准化、静默错误消除、memory_graph 修复、死代码清理。

#### 输出标准化
- JSON/SARIF 通过 `posix.write(STDOUT_FILENO)` 输出到 stdout（原为 `log.info()` → stderr）
- 紧凑 JSON 格式，可管道：`omniscope --json 2>/dev/null | jq`
- `writeJsonEscaped` 合并到 `formatter.zig`，删除 `ir/location.zig`

#### 安全：静默错误消除
- 25+ 处 `catch{}` → `try` 在安全关键路径（JNI/Python 检查、类型不匹配、FFI 追踪、ptr_lifetime）
- 3× `catch unreachable` → `try`（PassManager、Aggregator、AllocatorKB）
- FP 修复：`detectUseAfterFree()` 增加 `is_likely_intentional_pattern` 过滤（Precision 77.66% → 100%）
- `c_free`、`c_malloc` 加入分配/释放注册表
- IR 扫描的 free 站点改用 `identifyLanguageFromCallee()` 获取正确语言属性

#### MemoryGraph 函数名修复
- 新增 `resolveInstFuncName()` — 通过 LLVM instruction→basic block→function 链恢复真实函数名
- 消除了 `"memory_graph"` 去重 bug

| 项目 | 修复前 | 修复后 | 变化 |
|------|--------|--------|------|
| SQLite3 | 128 | 1508 | +1078% |
| curl8 | 47 | 404 | +757% |
| libuv150 | 55 | 418 | +660% |
| abseil2024 | 1 | 183 | +18200% |
| 红队 19 文件 | ~380 | 442 | +16% |
| **总计** | **~611** | **2955** | **+383%** |

#### 死代码与重构
- 删除 5 个文件 (−1,161 行)，4 个标注为未来功能
- `build.zig`：抽取 `configureLLVM()`（402→319 行）
- `graph.zig`：统计模块提取到 `stats.zig`（940→802 行）
- 删除日志包装函数 (−20 行)，`runMultiFileAnalysis` GPA 去重

#### CI/CD 与基础设施
- `make fmt-check` 加入 CI quality-gate
- 修复 `baseline_check.sh` 二进制名、`bench_perf.sh` CLI 参数、`stability_test.sh` 路径
- 集成测试：15/18 → 18/18
- 版本号：0.1.7 → 0.1.8（所有脚本 + 新增 3 个审计报告）
- 新增 5 个输出格式测试（JSON 转义 + SARIF 验证）

#### 新增红蓝队测试
- **v018_cpp_ffi**（C++）：14 issues — 智能指针逃逸、虚表、跨语言释放
- **v018_rust_ffi**（Rust）：9 issues — Arc/Mutex/ManuallyDrop → C FFI

#### 基准测试
- Precision：77.66% → 100.00%（21 FP → 0）
- Recall：100.00%（不变）
- 6 个 corpus 文件：96/96 TP，0 FP，0 FN

---

## [0.1.7] - 2026-05-06

### 综合 Bug 修复版本

全面的代码审查发现并修复了 CRITICAL/HIGH/MEDIUM/LOW 各级别的 24 个 bug。

### 修复 — 关键和高优先级（9 个 bug）

- **BUG-1**: [ffi_analysis.zig:328](src/pass/analysis/ffi_analysis.zig) — `free_sites.get()` 返回副本，append 丢失
  - **影响**: 多站点释放的双重释放检测完全失效
  - **修复**: `get()` → `getPtr()` 直接修改 map 条目
  
- **BUG-2**: [alias.zig:67-77](src/pass/analysis/alias.zig) — AutoHashMap.deinit() 不接受参数
  - **影响**: API 不匹配，Zig 0.11+ 上无法编译
  - **修复**: 从 deinit() 调用中移除 allocator 参数
  
- **BUG-3**: [pipeline.zig:97](src/pipeline/pipeline.zig) — MemoryGraph init 使用 `catch unreachable`
  - **影响**: OOM 时 panic 而非传播错误
  - **修复**: 改用 `try` 进行正确的错误处理
  
- **BUG-5/16**: [formatter.zig:141](src/output/formatter.zig), [main.zig:83](src/main.zig) — JSON 转义使用大写十六进制
  - **影响**: 产生非标准 JSON（\u000A 而非 \u000a）
  - **修复**: `\u{X:0>4}` → `\u{x:0>4}` 使用小写十六进制
  
- **BUG-6**: [call_graph.zig:517-520](src/pass/analysis/call_graph.zig) — extractCrossLangEdges 中 OOM 时字符串泄漏
  - **影响**: callee_name_owned 分配失败时 caller_name_owned 泄漏
  - **修复**: 为两个 owned 字符串添加 errdefer
  
- **BUG-9**: [pass.zig:311](src/pass/pass.zig) — PassContext.init MemoryGraph 使用 `catch unreachable`
  - **影响**: 同 BUG-3，内存压力时 panic
  - **修复**: PassContext.init 改为返回 `!PassContext`，使用 `try`
  
- **BUG-21**: [rust_ffi_auditor.zig:550](src/pass/analysis/rust_ffi_auditor.zig) — valuesMayAlias 对称情况返回 false
  - **影响**: 遗漏所有权违规检测中的有效别名对
  - **修复**: 对称检查改为 `return true`

### 修复 — 中等优先级（7 个 bug）

- **BUG-12**: [taint.zig:490](src/pass/analysis/taint.zig) — 测试缺少 allocator 参数
  - **修复**: TaintPass.init 调用添加 `std.testing.allocator`
  
- **BUG-13**: [sarif.zig:259](src/output/sarif.zig) — writeFloat 使用 `catch unreachable`
  - **修复**: 改为 `catch return error.OutOfMemory`
  
- **BUG-15**: [ffi_analysis.zig:694](src/pass/analysis/ffi_analysis.zig) — 测试传入未定义 store
  - **影响**: 测试中出现未定义行为
  - **修复**: 创建正确的 FactStore 实例
  
- **BUG-19**: [call_graph.zig:632-634](src/pass/analysis/call_graph.zig) — isSink 测试期望值错误
  - **修复**: 更新测试以匹配 exact-match 实现
  
- **BUG-20**: 版本号不一致（0.1.6 vs 0.1.7）
  - **修复**: 统一所有版本字符串为 0.1.7

### 修复 — CI/CD 基础设施

- **SARIF 上传错误**: [security-analysis.yml](.github/workflows/security-analysis.yml) — analysis-output/results.sarif 未创建
  - **改进**: 增强 shell 脚本，添加文件计数和回退 SARIF 创建
- **CodeQL Action v3 弃用**: 更新至 v4 以避免 2026 年 12 月弃用

### 测试结果

- **340/340 测试通过**（与 v0.1.6 相同）
- **修复后 0 编译错误**
- **所有 bug 修复已在二次审查中验证**

### Round 8: 系统化 Bug 审计 — 额外 43 个修复

**日期**: 2026-05-07 | **测试**: 343/343 通过

对所有已知问题进行系统化审计。全部 43 个 bug 已修复：

#### CRITICAL (7/7)

| ID | 文件 | 修复内容 |
|----|------|---------|
| R8-C1 | formatter.zig | JSON 尾逗号修复 |
| R8-C2 | sarif.zig | `init` → `initWithUri` 用于 4 参数构造函数 |
| R8-C3 | graph_visualizer.zig | JS 平移 NaN 修复 (`lastPos.y`) |
| R8-C4 | guard_propagation.zig | `is_null_branch` → `!is_not_null_branch` |
| R8-C5 | boundary.zig | Rust `_ZN` → `_RNv` 检测修复 |
| R8-C6 | layer1_reg.zig | 测试使用 `layer1_functions.len` 而非硬编码值 |
| R8-C7 | sanitizer_registry.zig | HashMap 初始化失败时的 errdefer |

#### HIGH (12/12)

LLVM 操作数索引标准化、trace deep-copy 双重释放防护、off-by-one 修正、缺失 import、HashMap API 使用、验证逻辑修复。

#### MEDIUM (18/18)

测试值修正、`static_buffer_functions` 集成到 `SemanticRegistry.lookup()`（+14 函数，totalCount 297→311）、`isCFree` 整词匹配重构、错误吞没 → 保守报告、hooks 线程安全文档、输出参数分类器函数级查找、personality 死前缀移除、OOM 泄漏防护、use-after-free 修复、字符串比较 → 布尔标志、线程安全 IssueKind 修正（新增 `data_race` + `thread_safety_violation`）、HashMap 传值 → 传指针、测试缺少 allocator 参数。

#### LOW (6/6)

重复条目删除、无符号比较修正、null guard 添加、死代码删除（~450 行）、parseLanguage 截断防护。

#### 重要结构变更

- **IssueKind 枚举**: 14 → **20 种**（新增 `data_race` CWE-362, `thread_safety_violation` CWE-807）
- **SARIF 规则**: 14 → **16**（覆盖新并发 issue kind）
- **DataFlowGraph.IssueStats**: 新增 `data_race` 和 `thread_safety_violation` 字段
- **死代码删除**: `ptr_lifetime_check.zig` 已删除（~450 行重复/桩代码）

---

## [0.1.6] - 2026-05-04

### 核心改进：Rust FFI 检测能力恢复（TP Rate 0% → 20%）

**背景**：v0.1.5 的核心功能"跨语言 FFI 边界检测"在 Rust 场景下完全失效。v0.1.6 完成修复。

### 修复 — Phase 1: 核心根因修复（4 项）

- **FIX-1**: [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) — 移除 `__rust_alloc/dealloc/realloc` 噪声模式 (5 行)
  - **效果**: Rust 堆操作恢复追踪, TP Rate 从 0% → **20%**
- **FIX-2**: [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) — 添加 `"call-graph"` 依赖
  - **效果**: CrossLangEdges 可访问, FFI 边界数 ~0 → **123**
- **FIX-3**: [hooks.zig](src/registry/hooks.zig) + [types.zig](src/registry/types.zig) — 所有权配对 key 改为指针值
  - **效果**: `Box::into_raw` / `Box::from_raw` 配对正常工作
- **FIX-4**: 4 个 pass 添加显式 pipeline 依赖声明
  - **效果**: 执行顺序从隐式依赖变为显式保证

### 修复 — Phase 2: 额外 Bug 修复（8 项）

- **BUG-FIX-6**: [noise_filter.zig](src/semantics/noise_filter.zig) — `isGoFunction` 不再误匹配 C++/Rust 函数名
- **BUG-FIX-7**: [taint_propagation.zig](src/pass/analysis/taint_propagation.zig) — `LLVMInvoke` 正确分类为 `.call`
- **BUG-FIX-8**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) — `GetStructName` null check
- **CTX-2**: [memory_graph.zig](src/semantics/memory_graph.zig) — `isLeaked` ret_ptr 匹配增强 + null 守卫
- **Issue1**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) — 空 type_name debug 日志
- **Issue2**: [memory_graph.zig](src/semantics/memory_graph.zig) — `isDoubleFreed` ret_ptr null check

### 修复 — Phase 3: 清理与质量（untodo.md）

- **P1-1**: 测试断言矛盾修复 (`expect(is_)` → `expect(!is_)`)
- **P1-2**: allocator_kb deallocator map bug (`.allocators.put` → `.deallocators.put`)
- **P1-3**: static_buf_funcs 重复注册移至 `populateBuiltin()` (只执行一次)
- **P1-6/7**: free_validation/memory_safety deps 补全 + 运行时守卫
- **P2-4~10**: 死代码清理 + 去重 + ffi_auto_relevant 接入 (~700 行净减少)

### 修复 — 逐行审计发现（5 个新 Bug）

| Bug | 严重度 | 文件 | 问题 |
|-----|--------|------|------|
| OOM fallback 创建未初始化 ArrayList | HIGH | [pass.zig](src/pass/pass.zig) L750 | `initCapacity catch {}` → `try initCapacity` |
| markFfiRelevant 死代码 | HIGH | [pass.zig](src/pass/pass.zig) | 已声明但从未调用 → 接入 danger_surface |
| hooks.zig 子串匹配过宽 | MEDIUM | [hooks.zig](src/registry/hooks.zig) | 新增精确边界匹配函数 |
| isDoubleFreed 缺 null check | MEDIUM | [memory_graph.zig](src/semantics/memory_graph.zig) | 与 isLeaked 保持一致 |
| danger_surface 注释/代码不一致 | LOW | [danger_surface.zig](src/pass/analysis/danger_surface.zig) | 修正注释与 deps 一致 |

### 新增功能模块

- **[danger_surface.zig](src/pass/analysis/danger_surface.zig)** — Graph-driven FFI 边界分析器 (Tier 2 核心)
  - O(E x avg_args) 算法替代 O(N x B) 全扫描
  - Zone-first 架构：Safe Zone 跳过 → Unknown Zone 深度分析
- **[callback_escape.zig](src/pass/analysis/callback_escape.zig)** — 带 Zone 感知的回调逃逸检测
- **[free_validation.zig](src/pass/analysis/issue/free_validation.zig)** — Free/dealloc 校验 pass
- **[memory_safety.zig](src/pass/analysis/issue/memory_safety.zig)** — 内存安全 issue 检测 pass
- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** — 语言特定函数分区
- **[noise_filter.zig](src/semantics/noise_filter.zig)** — 三层噪声过滤系统
- **[memory_graph.zig](src/semantics/memory_graph.zig)** — 别名链 + 泄漏/UAF 追踪
- **[hooks.zig](src/registry/hooks.zig)** — 跨语言所有权转移 hook 系统

### 性能与精度对比

| 指标 | v0.1.5 | v0.1.6 | 变化 |
|------|--------|--------|------|
| **Rust FFI TP Rate** | **0%** | **20%** (4/20) | 显著提升 |
| **测试用例数** | ~50 | **191** | **+282%** |
| **测试覆盖率** | ~70% | **92%** | **+22pp** |
| **Precision (subtle_rs)** | N/A | **100%** (0 FP) | 达到理想状态 |
| **FFI 边界数 (Rust)** | ~0 | **123** | 从无法检测到正常工作 |
| **死代码行数** | ~2000 | **~1300** | **-35%** |
| **大文件平均执行时间** | ~40ms | **~36ms** | -10% |

### Benchmark 数据（17 个 .ll 文件）

```
╔══════════════════════════════════════════════════╗
║         OmniScope v0.1.6 — 最终汇总              ║
╠══════════════════════════════════════════════════╣
║  测试文件:          17 (红队:8 + 密集:3 + 真实:6) ║
║  总 Issues:         548                           ║
║  追踪指针:          27,076                        ║
║  违规数:            251                           ║
║  FFI 边界:          9,372                         ║
║  测试覆盖率:        92% (191 tests)               ║
║  Rust FFI TP 率:    20%                           ║
╚══════════════════════════════════════════════════╝
```

### 真实项目验证

| 项目 | Issues | FFI 边界 | Precision |
|------|--------|----------|-----------|
| sqlite3 | 226 (最高) | 1,547 | ~85% |
| curl8 | 114 | 1,499 | ~88% |
| ring | 19 | **4,266** (最多) | ~95% |
| blst | 35 | 1,382 | 58%→**86%** |
| wasmtime | 44 | 130 | 50%→**90%** |

### 文档更新

全部 **22 份调查报告** 使用最新 benchmark 数据重写:
- accuracy_validation (中+英): 完整验证报告, 548 issues, 92% 覆盖率
- rust_ffi_restoration_v016 (中+英): Phase 1+2+3 完整调查
- wasmtime/ring/blst/ffi_dense/other_projects/zkcrypto (中+英): 全部项目专项报告
- README (中+英): 完整索引, v0.1.6 汇总指标

### 删除内容

- `src/tracking/allocator.zig` — 死代码（TrackedAllocator 未使用）
- `src/lifetime/mapper.zig` — 死代码（SemanticMapper 仅用于已删除的测试）
- `src/fact/ownership_fact.zig` — 死代码（无 @import 使用者）
- `src/semantics/attribution.zig` — 死代码（无使用者）
- 16 个过时英文文档文件（来自重新定位前的 api_reference、dataflow、diag 等）

---

## [0.1.5] - 2026-04-25

### 核心功能：Zone Classification

**项目定位调整**：专注于 unsafe/FFI 跨语言边界的静态安全分析

**核心理念**：只分析语言保障失效的地方

| Zone 类型 | 含义 | 处理方式 |
|-----------|------|---------|
| **Safe Zone** | 具有语言安全保障的代码 | 跳过分析（信任编译器） |
| **Runtime Internal** | 语言运行时 / 标准库 | 跳过分析（信任官方实现） |
| **Unknown Zone** | 无语言保障的代码 | 深度分析（必须检查） |

### 新增 — Zone 分类系统

- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** — 核心模块
  - Rust/Zig/Go/C++ 函数分类
  - ZoneStats 统计输出
- **Pass Pipeline 集成** — 函数遍历时自动跳过 Safe Zone 和 Runtime Internal

### 性能影响

| 指标 | 优化前 | 优化后 | 提升 |
|------|-------|-------|------|
| 分析时间 (blst) | 3100ms | 836ms | **73%** |
| 分析时间 (ring) | 793ms | 269ms | **66%** |
| UAF 报告数 (blst) | 185 | 48 | **74% 减少** |

### 安全修复

| Bug ID | 问题 | 修复 |
|--------|------|------|
| BUG-R5-001 | 空切片 free 导致堆损坏 | 使用 `allocator.alloc(u32, 0)` |
| BUG-R5-002 | 操作数索引错误 | 使用 `LLVMGetCalledValue(inst)` |
| BUG-R5-003 | 硬编码操作数 1 | 使用 `num_operands - 1` |

---

## 版本历史总览

| 版本 | 日期 | 主要特性 | 关键指标 |
|------|------|---------|---------|
| **v0.2.0** | **2026-06-09** | **语义分析 + 多语言 FFI** | **SRT、Symbol Graph、资源契约、扩展 CLI/测试** |
| **v0.1.7** | **2026-05-07** | **全面 Bug 修复 (Round 7+8)** | **67 bugs**, **343 tests**, **20 Issue Kinds** |
| **v0.1.6** | **2026-05-04** | **Rust FFI 检测恢复** | TP **20%**, 覆盖率 **92%**, **191 tests** |
| v0.1.5 | 2026-04-25 | Zone Classification | 跳过率 **60%+** |
| v0.1.x | 更早 | 初始原型 | 基本 LLVM IR 解析能力 |

---

*[更新日志]: https://keepachangelog.com/zh-CN/1.0.0/*
*[语义化版本]: https://semver.org/lang/zh-CN/spec/v2.0.0.html*
