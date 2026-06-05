# OmniScope 文件拆分重构计划

> 目标：将所有超过 1000 行的文件拆分为职责单一的模块，每个模块控制在 400–600 行以内

---

## 概览

| 文件 | 当前行数 | 拆分后模块数 | 优先级 |
|------|---------|------------|--------|
| `src/main.zig` | 2517 | 5 | P0 |
| `src/pass/analysis/ffi/cross_lang_dataflow.zig` | 2233 | 4 | P0 |
| `src/pass/analysis/issue/free_validation.zig` | 1899 | 3 | P0 |
| `src/types/pass_types.zig` | 1413 | 4 | P1 |
| `src/semantics/memory_graph.zig` | 1444 | 3 | P1 |
| `src/pipeline/pipeline.zig` | 1376 | 3 | P1 |
| `src/resource/ffi_contract_db.zig` | 1257 | 2 | P1 |
| `src/filter/rule_customization.zig` | 1208 | 2 | P2 |
| `src/pass/analysis/ffi/gc_safety_analyzer.zig` | 1189 | 3 | P2 |
| `src/semantics/language_detector.zig` | 1122 | 3 | P2 |
| `src/pass/analysis/issue/ffi_body_check.zig` | 1032 | 2 | P2 |
| `src/pass/analysis/ffi/ffi_language_classifier.zig` | 1010 | 2 | P2 |
| `src/pass/analysis/ffi/abi_compat_checker.zig` | 1006 | 2 | P2 |

## 优先级说明

- **P0**：职责混乱最严重，拆分收益最大，阻碍整体可读性
- **P1**：超过 1400 行，有明显的逻辑边界，被多处引用
- **P2**：1000–1200 行，有改善空间，但可在 P0/P1 完成后处理

---

## main.zig（2517 行）— P0

### 当前职责

`main.zig` 同时承担了五类职责：

1. **Pass 注册**（第 39–93 行）：`registerAllPasses()` 注册全部 ~25 个分析 pass
2. **Pipeline 驱动**（第 95–238 行）：`runModulePipeline()` / `runSingleFileAnalysis()` / `runMultiFileAnalysis()`
3. **Issue 过滤**（第 239–391 行）：`filterIssues()` / `isBoundaryIssueFast()` / `isFFIIssueKind()` / `classifySurfaces()`
4. **输出格式化**（第 392–955 行）：`emitOutput()` / `formatStructuredReport()` / `formatIssuesAsJson()` / `writeCallGraph()`；这部分超过 550 行
5. **FFI 信号评分**（第 988–1536 行）：`isDangerousFFIPattern()` / `countSecondarySignals()` / `hasTypeMismatchSignal()` / `calculateFFIConfidence()` / `classifyFFIVulnType()` / `ffiMatchToIssue()` 等 ~14 个函数，共约 550 行
6. **程序入口 + 测试**（第 1830–2517 行）：`main()` 和大量 test 块

### 拆分方案

#### 模块 1：`src/cli/pass_registry.zig`

- **职责**：声明所有 pass 的注册顺序
- **包含**：`registerAllPasses(pipeline: *Pipeline) !void`
- **依赖**：`OmniScope.pipeline`、`OmniScope.cross_lang`
- **大约行数**：~70 行
- **说明**：当前这个函数几乎只有 `pipeline.registerPass(...)` 调用，完全可以独立。将来新增 pass 时只改这一个文件。

#### 模块 2：`src/cli/runner.zig`

- **职责**：分析驱动层（加载 IR、运行 pipeline、聚合结果）
- **包含**：
  - `AnalyzeResult` 结构体
  - `runModulePipeline()`
  - `deinitAnalyzeResult()`
  - `runSingleFileAnalysis()`
  - `runMultiFileAnalysis()`
  - `countFunction()`
- **依赖**：`Pipeline`、`IRLoader`、`LanguageDetector`、`Config`、`cli/pass_registry`、`cli/output`
- **大约行数**：~350 行

#### 模块 3：`src/cli/issue_filter.zig`

- **职责**：issue 过滤与语义表面分类
- **包含**：
  - `filterIssues()`
  - `isBoundaryIssueFast()`
  - `isFFIIssueKind()`
  - `matchesSurfaceFilter()`
  - `classifySurfaces()`
  - `isRuntimeInternalFunction()`
- **依赖**：`Issue`、`IssueKind`、`Config`、`SurfaceFilterConfig`
- **大约行数**：~160 行

#### 模块 4：`src/cli/output.zig`

- **职责**：所有输出格式化（text / JSON / SARIF）
- **包含**：
  - `emitOutput()`
  - `formatStructuredReport()`（text 格式，约 380 行）
  - `formatIssuesAsJson()`
  - `writeCallGraph()`
  - `languageDisplayName()`
  - `detectTargetLanguage()`
- **依赖**：`Issue`、`Config`、`SarifOutput`、`log`、`term`
- **大约行数**：~580 行
- **注意**：`formatStructuredReport` 本身就有 380 行，如果需要进一步缩减可将其中的"每个 severity 块"提取为辅助函数，但不强求

#### 模块 5：`src/cli/ffi_signal.zig`

- **职责**：FFI 危险信号评分与 issue 生成
- **包含**：
  - `isDangerousFFIPattern()`
  - `countSecondarySignals()`
  - `hasTypeMismatchSignal()`
  - `hasMemorySafetyRisk()`
  - `hasLifetimeIssue()`
  - `hasTrustBoundaryViolation()`
  - `hasMissingValidation()`
  - `hasUncheckedReturn()`
  - `calculateFFIConfidence()`
  - `classifyFFIVulnType()`
  - `isWhitelistedFFI()`
  - `ffiMatchToIssue()`
  - `buildFFIIssueMessage()`
  - `calculateFFISeverity()`
  - `issueToGraphKind()`
  - `SecondarySignal`（enum）
  - `FFIVulnType`（enum，如有）
- **依赖**：`call_graph.FFIMatch`、`Issue`、`IssueKind`、`Severity`
- **大约行数**：~550 行

#### 保留在 main.zig

- `main()` 入口函数（约 90 行）
- `pub const AnalyzeResult` 的 re-export（或直接从 runner 导入）
- 顶层 `@import` 与命名空间引入
- **目标行数**：~150 行

### 迁移注意事项

- `main.zig` 目前只引用别人，不被别人引用，所以没有循环 import 风险
- test 块（第 1917–2517 行）：目前 test 与生产代码混在一起。建议将测试移入对应模块或创建 `src/cli/tests/` 目录
- `generateVisualization()` 函数（第 1601–1638 行）在 `runSingleFileAnalysis` 中调用；若不提取 runner.zig 中调用的依赖，可以暂时保留在 runner.zig 尾部
- 新建 `src/cli/` 目录，并在 `src/root.zig`（或构建文件）中更新模块路径

---

## cross_lang_dataflow.zig（2233 行）— P0

### 当前职责

1. **公共数据结构**（第 41–78 行）：`DataFlowStats`、`CrossLangAlloc`
2. **主 Pass 逻辑**（第 79–1146 行）：`CrossLangDataFlow` struct 及其 `run()` 方法，包含 alloc/free 追踪的主循环，约 1000 行
3. **语言分类辅助函数**（第 1149–1383 行）：`isAllocationFunction()`、`isFreeFunction()`、`classifyAllocLanguage()`、`classifyFreeLanguage()`、`formatLanguages()`，约 240 行
4. **JNI 专用检测**（第 1384–1575 行）：`isKnownAllocFunction()`、`isJniAllocCall()`、`isJniReleaseCall()`、`requiresJniNullCheck()`、`isRealJNICall()`、`isPointerToPointer()`、`isJNIEnvType()`、`isJNIStructType()`，约 190 行
5. **内部工具函数**（第 1576–2233 行）：`findInstructionIndexFir()`、`calculateOrphanConfidence()`、`isIntentionalOwnershipTransfer()`，约 600 行

### 拆分方案

#### 模块 1：`src/pass/analysis/ffi/cross_lang_dataflow_types.zig`

- **职责**：公共数据类型定义
- **包含**：`DataFlowStats`、`CrossLangAlloc`
- **大约行数**：~80 行

#### 模块 2：`src/pass/analysis/ffi/cross_lang_alloc_classify.zig`

- **职责**：跨语言 alloc/free 函数分类
- **包含**：
  - `isAllocationFunction()`
  - `isFreeFunction()`
  - `classifyAllocLanguage()`
  - `classifyFreeLanguage()`
  - `formatLanguages()`
  - `isKnownAllocFunction()`
  - 所有 JNI 相关检测函数（`isJniAllocCall`、`isJniReleaseCall`、`requiresJniNullCheck`、`isRealJNICall`、`isJNIEnvType`、`isJNIStructType`、`isPointerToPointer`）
- **大约行数**：~450 行
- **说明**：语言分类和 JNI 检测是同一职责（"这个 call 是否是 alloc/free，属于哪个语言"），合并在一个模块中比分开更合理

#### 模块 3：`src/pass/analysis/ffi/cross_lang_orphan.zig`

- **职责**：孤儿指针与 ownership transfer 判断
- **包含**：
  - `calculateOrphanConfidence()`
  - `isIntentionalOwnershipTransfer()`
  - `findInstructionIndexFir()`
- **大约行数**：~100 行

#### 模块 4（保留）：`src/pass/analysis/ffi/cross_lang_dataflow.zig`

- **职责**：主 Pass 入口（`CrossLangDataFlow.run()` 主循环）
- **包含**：`CrossLangDataFlow` struct + `run()` + alloc/free 追踪主循环
- **依赖**：`cross_lang_dataflow_types`、`cross_lang_alloc_classify`、`cross_lang_orphan`
- **大约行数**：~600 行（拆出后）

### 迁移注意事项

- `CrossLangDataFlow` 内部方法（`analyzeFunction`、`trackAllocs` 等）中直接调用了大量 `isAllocationFunction` 等本地函数；提取后需要将这些函数 `pub` 化并更新 `@import`
- `SummaryPropagation` 和 `RAIIDetector` 的初始化在 `run()` 中，这些逻辑留在主文件不移动

---

## free_validation.zig（1899 行）— P0

### 当前职责

1. **Pass 入口与函数遍历**（第 61–155 行）：`FreeValidationPass.run()` 和 `analyzeFunction()`
2. **指针起源追踪**（约 155–500 行）：`trackPointerOrigin()`，追踪 malloc / Rust alloc / C++ new / 参数来源
3. **Free 调用检查**（约 500–840 行）：`checkFreeCall()`，包含 cross-lang free、invalid free、library contract 检查
4. **语言专属辅助函数**（约 840–1899 行）：`isRustDeallocFunction()`、`isRustAllocCall()`、`isCppAllocCall()`、`isZigAllocCall()`、`isCrossLangFreeMismatch()` 等十余个函数，约 1060 行

### 拆分方案

#### 模块 1：`src/pass/analysis/issue/free_validation_lang.zig`

- **职责**：各语言 alloc/dealloc 函数识别
- **包含**：
  - `isRustDeallocFunction()`
  - `isRustAllocCall()`
  - `isCppAllocCall()`（如有）
  - `isCppDeallocCall()`（如有）
  - `isZigAllocCall()`（如有）
  - `isCrossLangFreeMismatch()`
  - `PointerOrigin` enum 和 `PointerInfo` struct（第 157–180 行），如果它们只用于语言判断
- **大约行数**：~350 行

#### 模块 2：`src/pass/analysis/issue/free_validation_tracker.zig`

- **职责**：指针起源追踪
- **包含**：
  - `trackPointerOrigin()`
  - 相关辅助：`PointerOrigin`、`PointerInfo`、`ValueOrigin`（如未放入 lang 模块）
  - `createOriginTraceEntry()`、`createFreeTraceEntry()`
- **依赖**：`free_validation_lang`
- **大约行数**：~400 行

#### 模块 3（保留）：`src/pass/analysis/issue/free_validation.zig`

- **职责**：Pass 入口、函数遍历、`checkFreeCall()` 主逻辑
- **包含**：`FreeValidationPass`、`analyzeFunction()`、`checkFreeCall()`
- **依赖**：`free_validation_lang`、`free_validation_tracker`
- **大约行数**：~500 行

### 迁移注意事项

- `PointerInfo` 和 `ValueOrigin` 会被 tracker 和 checker 共用，应放在 lang 模块或单独的 `free_validation_types.zig`（~30 行）中
- `FREE_FUNCTIONS` 和 `ALLOC_FUNCTIONS` 常量（第 48–55 行）已经是导入的，不需要移动

---

## pass_types.zig（1413 行）— P1

### 当前职责

1. **基础类型与 re-export**（第 1–62 行）：`PassKind`、`CrossLangEdge`、`CallSiteIndex`、`CallSite`
2. **GlobalAllocTracker**（第 120–272 行）：全局分配跟踪器，约 150 行
3. **PassContext**（第 275–1174 行）：主上下文结构体及其所有方法，约 900 行——这是文件膨胀的核心原因
4. **DiagnosticWriter + Colors**（第 1177–1241 行）：输出诊断工具，约 65 行
5. **内部辅助函数**（第 1243–1413 行）：`isZigStdlibFunctionImpl()`、`looksLikeInternalZigFunction()`、`looksLikeUserCode()` 等，约 170 行（这些函数是 `PassContext.isZigStdlibFunction()` 的实现）

### 拆分方案

#### 模块 1：`src/types/pass_context_stdlib.zig`

- **职责**：stdlib/内部函数识别逻辑（pass_types 中最独立的部分）
- **包含**：
  - `isZigStdlibFunctionImpl()`
  - `looksLikeInternalZigFunction()`
  - `looksLikeUserCode()`
  - `countChar()`
  - `diagToNoiseSeverity()`
  - `getSeverityColor()`
- **大约行数**：~200 行

#### 模块 2：`src/types/diagnostic_writer.zig`

- **职责**：诊断输出工具
- **包含**：
  - `Colors` struct
  - `DiagnosticWriter` struct 及其所有方法（`write`、`info`、`warn`、`err`、`critical`、`debug`）
- **依赖**：`log`，以及 `pass_context_stdlib` 中的 `getSeverityColor`（或直接内联）
- **大约行数**：~80 行
- **注意**：`DiagnosticWriter` 当前从 `pass/pass.zig` re-export，提取后需更新所有 `@import("../../pass/pass.zig").DiagnosticWriter`

#### 模块 3：`src/types/global_alloc_tracker.zig`

- **职责**：全局分配记录跟踪
- **包含**：`GlobalAllocTracker` struct 及其所有方法（`init`、`deinit`、`insertAlloc`、`markFreed`、`getRecord`）
- **依赖**：LLVM C bindings
- **大约行数**：~160 行

#### 模块 4（保留）：`src/types/pass_types.zig`

- **职责**：`PassContext` 主体 + 基础类型
- **包含**：
  - `PassKind`、`CrossLangEdge`、`CallSiteIndex`、`CallSite`
  - `PassContext` struct 及其所有方法
  - re-export from 上面三个新模块
- **依赖**：`global_alloc_tracker`、`diagnostic_writer`、`pass_context_stdlib`
- **大约行数**：~900 行（PassContext 的方法还很多，如有必要可进一步提取 `pass_context_queries.zig`）

### 迁移注意事项

- `DiagnosticWriter` 被大量 pass 文件通过 `@import("../../pass/pass.zig").DiagnosticWriter` 引用，提取后需要全局 grep 更新引用路径，**或**在 `pass/pass.zig` 中保留 re-export
- `GlobalAllocTracker` 依赖 `c.LLVMValueRef`，需要在新模块中保留 LLVM import

---

## memory_graph.zig（1444 行）— P1

### 当前职责

1. **主结构体定义与初始化**（第 55–230 行）：`MemoryGraph` struct 定义（含所有字段）、`init`、`initWithCapacity`、`deinit`、`reset`
2. **核心追踪方法**（约 230–700 行）：`trackAlloc`、`trackFree`、`trackAlias`、`trackCallArg`、`trackCallRet`、`trackContentSource` 等
3. **查询方法**（约 700–900 行）：`resolveSourceKind`、`getSourceKind`、`getContentSource`、`findNode`、`findNodeByInst`、危险路径查询等
4. **RAII / CFG 分析方法**（约 764–1440 行）：Phase 2 RAII ownership、`buildCFG`、`canReach`、`hasCrossPathDoubleFree`、`extractDangerSurfaces` 等

文件顶部注释表明已有 `memory_graph_escape.zig` 和 `memory_graph_fuzzy.zig` 被拆出（第 43–46 行），本次延续这个思路。

### 拆分方案

#### 模块 1：`src/semantics/memory_graph_cfg.zig`

- **职责**：CFG 构建与可达性分析
- **包含**：
  - `buildCFG()`
  - `canReach()`
  - `hasCrossPathDoubleFree()`
  - 相关 BB edge 查询辅助函数
- **大约行数**：~250 行

#### 模块 2：`src/semantics/memory_graph_query.zig`

- **职责**：图查询接口（只读操作）
- **包含**：
  - `findNode()`
  - `findNodeByInst()`
  - `getSourceKind()`
  - `resolveSourceKind()`
  - `getContentSource()`
  - `extractDangerSurfaces()`
  - 其他纯查询方法
- **大约行数**：~220 行

#### 模块 3（保留）：`src/semantics/memory_graph.zig`

- **职责**：struct 定义、初始化、核心 track 方法
- **包含**：`MemoryGraph` struct、`init` / `initWithCapacity` / `deinit` / `reset`、所有 `track*` 方法
- **依赖**：`memory_graph_cfg`、`memory_graph_query`、已有的 `memory_graph_escape`、`memory_graph_fuzzy`
- **大约行数**：~600 行

### 迁移注意事项

- `MemoryGraph` 的方法（`impl` 块）在 Zig 中都必须定义在 struct 所在文件内，**无法**像 Rust 那样跨文件实现。所以 `buildCFG` 等方法只能以 **独立函数** 形式存在于新文件中，接受 `graph: *MemoryGraph` 参数，然后在 `memory_graph.zig` 中的 `pub fn buildCFG(self: *MemoryGraph) void { memory_graph_cfg.buildCFG(self); }` 包装。这是 Zig 代码拆分的标准模式（与已有的 `mg_methods`、`mg_escape` 保持一致）
- `reachability_cache` 字段属于 CFG 分析，但它定义在 struct 中，无法移动，只能由 `memory_graph_cfg.zig` 中的函数访问

---

## pipeline.zig（1376 行）— P1

### 当前职责

1. **Pipeline struct 与初始化**（第 63–200 行）：`Pipeline.init`、`deinit`、配置 setter（`setLeakThreshold`、`setFocusUserCode` 等）
2. **`Pipeline.run()` 主循环**（第 200–1000 行）：包含 Zig alloc tracker、Rust drop 分析、leak reporting、confidence 评分等，约 800 行——这是膨胀核心
3. **`LeakCheckPass` 内嵌 Pass**（约 1000–1256 行）：实际上在 `Pipeline.run()` 内有一个完整的 leak 分析子系统
4. **`PipelineResult` + 测试**（第 1259–1376 行）

### 拆分方案

#### 模块 1：`src/pipeline/leak_reporter.zig`

- **职责**：leak 检测与上报逻辑（当前嵌在 `Pipeline.run()` 中的大段代码）
- **包含**：
  - `checkLeakRecord(ctx, rec, ...) !bool` —— 提取 `run()` 中针对每条 `GlobalAllocTracker` 记录的判断逻辑（Zig confidence、Rust drop、P19-2 transfer inference、severity/confidence 计算）
  - `buildLeakIssue()`
  - 相关常量（`LARGE_MODULE_THRESHOLD` 等）
- **大约行数**：~450 行

#### 模块 2：`src/pipeline/pipeline_config.zig`

- **职责**：Pipeline 可配置项及其 setter
- **包含**：
  - Pipeline 配置字段的文档（以常量或 Config struct 形式）
  - `setLeakThreshold()`、`setFocusUserCode()`、`setZigAllocatorTracking()`、`setLanguageOverrides()` 等所有 setter
  - `getFactStore()`、`getQueryEngine()` 等 getter
- **大约行数**：~100 行
- **注意**：Zig 不支持跨文件 struct 方法，这些方法需要留在 `Pipeline` struct 中，但可以将 **逻辑文档** 和 **配置字段** 注释集中到单独的文件辅助阅读；实际实现仍需留在 `pipeline.zig`——如果这一点导致拆分价值降低，可以只拆 `leak_reporter.zig`

#### 模块 3（保留）：`src/pipeline/pipeline.zig`

- **职责**：`Pipeline` struct 主体与 `run()` 入口（调度层）
- **大约行数**：~400 行（将 leak 逻辑外移后）

### 迁移注意事项

- `Pipeline.run()` 中 leak 检测逻辑目前内联在循环里，提取为独立函数时需要传入所有上下文：`ctx`、`diag`、`zig_tracker`、`rust_drop_semantics`、`transfer_infer` 等，参数较多——考虑用一个 `LeakCheckContext` 结构体包装传参
- `PipelineResult` 和测试块（第 1259–1376 行）行数不多，保留在主文件即可

---

## ffi_contract_db.zig（1257 行）— P1

### 当前职责

1. **数据类型定义**（第 24–118 行）：`OwnershipModel`、`PairMatchResult`、`AllocPairRule`、`ManagedTypeInfo`、`LibraryContract`
2. **FFIContractDB struct 与查询 API**（第 119–378 行）：`init`、`deinit`、`shouldReportLeak`、`isValidRelease`、`getExpectedReleases`、`getOwnership`、`totalRules`、`libraryCount` 等
3. **内嵌合同数据**（第 379–1257 行）：`builtinLibraries()` 函数返回约 900 行的静态数组，包含 OpenSSL、SQLite、JNI、Python C-API、libcurl、PCRE 等约 15 个库的 alloc/release pair 规则

### 拆分方案

#### 模块 1：`src/resource/ffi_contract_data.zig`

- **职责**：内嵌合同数据（纯数据，无逻辑）
- **包含**：`builtinLibraries() []const LibraryContract` 及其数据，以及数据所依赖的 `LibraryContract`、`AllocPairRule`、`ManagedTypeInfo`、`OwnershipModel` 的 re-export（或直接 import 自 db 文件）
- **大约行数**：~900 行
- **说明**：合同数据是纯静态配置，与查询逻辑完全分离，独立成文件后未来新增库只改这一个文件

#### 模块 2（保留）：`src/resource/ffi_contract_db.zig`

- **职责**：数据类型 + 查询 API
- **包含**：所有类型定义 + `FFIContractDB` struct + 查询方法 + `matchFuncName*` 辅助函数
- **依赖**：`ffi_contract_data`
- **大约行数**：~380 行

### 迁移注意事项

- `builtinLibraries()` 中的数据引用了 `LibraryContract`、`AllocPairRule` 等类型，这些类型定义在同文件的前部。移动时需确保 `ffi_contract_data.zig` 能 import 回这些类型（或将类型定义也移入 `ffi_contract_data.zig`，然后在 `ffi_contract_db.zig` 中 re-export）
- 最简做法：`ffi_contract_data.zig` 中 `const types = @import("ffi_contract_db.zig");` 并使用 `types.LibraryContract` 等——**但这会产生循环 import**。正确做法：将数据类型移入 `ffi_contract_data.zig`，`ffi_contract_db.zig` 从它那里 import

---

## rule_customization.zig（1208 行）— P2

### 当前职责

1. **类型定义**（第 24–63 行）：`MatchType`、`RuleAction`、`CustomRule`、`RuleConfig`
2. **RuleConfig 主逻辑**（第 64–238 行）：`init`、`deinit`、`loadFromJson`、`parseJsonConfig`、`applyToIssue`、`shouldSuppress`、`overrideSeverity`
3. **JSON 解析辅助**（第 259–358 行）：`parseCustomPatterns()`、`parseCustomRule()`、`parseMatchType()`、`parseAction()`、`parseSeverity()`、`parseStringList()`

### 拆分方案

#### 模块 1：`src/filter/rule_customization_parser.zig`

- **职责**：JSON 配置解析
- **包含**：
  - `parseCustomPatterns()`
  - `parseCustomRule()`
  - `parseMatchType()`
  - `parseAction()`
  - `parseSeverity()`
  - `parseStringList()`
  - `escalateSeverity()`
- **大约行数**：~200 行

#### 模块 2（保留）：`src/filter/rule_customization.zig`

- **职责**：类型定义 + `RuleConfig` 主体逻辑
- **包含**：`MatchType`、`RuleAction`、`CustomRule`、`RuleConfig`、`matchPattern()`
- **依赖**：`rule_customization_parser`
- **大约行数**：~300 行

---

## gc_safety_analyzer.zig（1189 行）— P2

### 当前职责

1. **类型定义**（第 46–89 行）：`GcSafetyIssueKind`、`GcSafetyResult`
2. **主 Pass + 函数分析**（第 90–200 行）：`GcSafetyAnalyzer.run()`、`analyzeFunction()`
3. **call 级别检测**（约 200–600 行）：`analyzeCallInstruction()`，包含 JNI / Python GIL / finalizer / use-after-collect 等各类 GC 安全检查，约 400 行
4. **引用循环检测**（约 630–750 行）：`detectReferenceCycle()`
5. **JNI/Python 识别辅助函数**（约 750–1189 行）：`isJniObjectCreation()`、`isPythonObjectCreation()`、`isJniReferenceOperation()`、`isJniGilSafeFunction()`、`isJniLocalRef*`、`isPythonGilRelease()` 等 ~20 个函数，约 440 行

### 拆分方案

#### 模块 1：`src/pass/analysis/ffi/gc_jni_patterns.zig`

- **职责**：JNI 和 Python GC 模式识别（纯函数名匹配）
- **包含**：所有 `isJni*`、`isPython*` 辅助函数（约 20 个）
- **大约行数**：~440 行

#### 模块 2：`src/pass/analysis/ffi/gc_reference_cycle.zig`

- **职责**：引用循环检测
- **包含**：`detectReferenceCycle()`
- **大约行数**：~120 行

#### 模块 3（保留）：`src/pass/analysis/ffi/gc_safety_analyzer.zig`

- **职责**：Pass 入口、类型定义、主分析循环
- **包含**：`GcSafetyIssueKind`、`GcSafetyResult`、`GcSafetyAnalyzer`（`run` + `analyzeFunction` + `analyzeCallInstruction`）
- **依赖**：`gc_jni_patterns`、`gc_reference_cycle`
- **大约行数**：~450 行

---

## language_detector.zig（1122 行）— P2

### 当前职责

1. **类型定义**（第 20–51 行）：`DetectionMethod`、`LanguageProfile`
2. **模块级语言检测入口**（第 52–188 行）：`detectModuleLanguage()` 主函数，约 130 行
3. **采样检测**（第 189–491 行）：`detectFromSampling()`，扫描所有函数做统计，约 300 行
4. **Personality 检测**（第 492–579 行）：`detectFromPersonality()`，约 90 行
5. **全局变量检测**（第 580–723 行）：`detectFromGlobals()`，约 145 行
6. **函数级语言识别**（第 724–777 行）：`identifyLanguage()`（LLVM value 版）
7. **Name-based 识别**（第 729–1122 行）：`identifyCalleeLanguage()`、`isRustMangledName()`、`classifyGlobalName()` 等

### 拆分方案

#### 模块 1：`src/semantics/language_detector_sampling.zig`

- **职责**：基于函数名采样的模块级语言检测
- **包含**：
  - `detectFromSampling()`
  - `detectFromPersonality()`
  - `detectFromGlobals()`
  - 相关语言评分权重常量
- **大约行数**：~550 行

#### 模块 2：`src/semantics/language_detector_name.zig`

- **职责**：基于函数名的语言识别（call-level）
- **包含**：
  - `identifyLanguage()`（LLVM value 版）
  - `identifyCalleeLanguage()`
  - `isRustMangledName()`
  - `classifyGlobalName()`
- **大约行数**：~400 行
- **说明**：`ffi_language_classifier.zig` 中有重复的 `isRustMangledName` 实现（第 753 行），拆分后可考虑统一引用这里的版本

#### 模块 3（保留）：`src/semantics/language_detector.zig`

- **职责**：公共类型 + 主入口 `detectModuleLanguage()`
- **包含**：`DetectionMethod`、`LanguageProfile`、`detectModuleLanguage()`（调用各子模块）
- **依赖**：`language_detector_sampling`、`language_detector_name`
- **大约行数**：~200 行

---

## ffi_body_check.zig（1032 行）— P2

### 当前职责

1. **内部类型**（第 28–62 行）：`ValueInfo`、`AnalysisContext`、`VulnerabilityInfo`
2. **指针别名分析工具**（第 63–158 行）：`pointsToStoreOfMallocResult()`、`isAliasOf()`
3. **漏洞检测函数**（第 159–508 行）：`isMallocUnchecked()`、`isFreeFromNonMalloc()`、`isDoubleFree()`、`checkUnknownFFIPointerUsage()`、`checkFormatStringVulnerability()`、`checkCommandInjectionVulnerability()`、`getVulnerabilityDesc()`、`isSafeUtilityFunction()`
4. **主 Pass**（第 508–1032 行）：`FFIBodyCheckPass.run()` 和内部分析函数

### 拆分方案

#### 模块 1：`src/pass/analysis/issue/ffi_body_vuln_checks.zig`

- **职责**：具体漏洞检测逻辑
- **包含**：
  - `isMallocUnchecked()`
  - `isFreeFromNonMalloc()`
  - `isDoubleFree()`
  - `checkUnknownFFIPointerUsage()`
  - `checkFormatStringVulnerability()`
  - `checkCommandInjectionVulnerability()`
  - `getVulnerabilityDesc()`
  - `isSafeUtilityFunction()`
  - `pointsToStoreOfMallocResult()`
  - `isAliasOf()`
  - 类型定义：`ValueInfo`、`AnalysisContext`、`VulnerabilityInfo`
- **大约行数**：~480 行

#### 模块 2（保留）：`src/pass/analysis/issue/ffi_body_check.zig`

- **职责**：Pass 入口
- **包含**：`FFIBodyCheckPass.run()` 及其直接调用的分析逻辑
- **依赖**：`ffi_body_vuln_checks`
- **大约行数**：~550 行

---

## ffi_language_classifier.zig（1010 行）— P2

### 当前职责

1. **`identifyLanguage()` + `identifyCalleeLanguage()`**（第 82–511 行）：基于函数名的语言识别，约 430 行，与 `language_detector.zig` 存在部分重叠
2. **`identifyCalleeLanguageWithContext()`**（第 432–498 行）：带上下文消歧
3. **名称解析工具**（第 511–1010 行）：`demangleRustName()`、`demangleMsvcName()`、`classifyBoundaryKind()`、`isLibcFunction()`、`isDynamicLoadingFunction()`、`isJNIFunction()`、`isPythonCApiFunction()`、`isCppAbiInternalFunction()`、`isStlInternalFunction()`、`isRustMangledName()`、`isMsvcMangledName()` 等，约 500 行

### 拆分方案

#### 模块 1：`src/pass/analysis/ffi/ffi_demangle.zig`

- **职责**：name mangling 解析与检测
- **包含**：
  - `demangleRustName()`
  - `demangleMsvcName()`
  - `isRustMangledName()`
  - `isMsvcMangledName()`
- **大约行数**：~300 行

#### 模块 2（保留）：`src/pass/analysis/ffi/ffi_language_classifier.zig`

- **职责**：语言分类主逻辑
- **包含**：`FFIPatterns`、`identifyLanguage()`、`identifyCalleeLanguage()`、`identifyCalleeLanguageWithContext()`、`classifyBoundaryKind()`、`isLibcFunction()`、`isDynamicLoadingFunction()`、`isJNIFunction()`、`isPythonCApiFunction()` 等
- **依赖**：`ffi_demangle`
- **大约行数**：~600 行

### 迁移注意事项

- `isRustMangledName()` 在 `language_detector.zig`（第 743 行）和本文件（第 753 行）各有一份实现，内容相近。拆分后统一使用 `ffi_demangle.zig` 中的版本，从 `language_detector.zig` 删除重复实现

---

## abi_compat_checker.zig（1006 行）— P2

### 当前职责

1. **类型定义**（第 33–108 行）：`AbiMismatchKind`、`AbiMismatchInfo`、`AbiCompatStats`
2. **主 Pass**（第 109–160 行）：`AbiCompatChecker.run()`
3. **Signature 收集**（第 162–250 行）：`collectFunctionSignature()`
4. **函数分析**（第 250–450 行）：`analyzeFunction()`、`checkCallSiteAbi()`
5. **类型兼容性检查**（约 450–800 行）：`areTypesCompatible()`、`checkStructLayout()`、`isFunctionPointerType()`、`checkFunctionPointerCompatibility()`、`checkEnumSizeCompatibility()`，约 350 行
6. **辅助工具**（第 800–1006 行）：`getCallingConventionName()`、`isCStdlibFunction()`、`calculateConfidence()`、`reportAbiMismatch()`

### 拆分方案

#### 模块 1：`src/pass/analysis/ffi/abi_type_compat.zig`

- **职责**：LLVM 类型兼容性比较
- **包含**：
  - `areTypesCompatible()`
  - `checkStructLayout()` 及 `StructLayoutCheckResult`
  - `isFunctionPointerType()`
  - `checkFunctionPointerCompatibility()`
  - `checkEnumSizeCompatibility()`
  - `FunctionSignature` struct（第 917 行）
- **大约行数**：~380 行

#### 模块 2（保留）：`src/pass/analysis/ffi/abi_compat_checker.zig`

- **职责**：Pass 入口、类型定义、分析逻辑
- **包含**：`AbiMismatchKind`、`AbiMismatchInfo`、`AbiCompatStats`、`AbiCompatChecker`、`collectFunctionSignature()`、`analyzeFunction()`、`checkCallSiteAbi()`、`getCallingConventionName()`、`isCStdlibFunction()`、`calculateConfidence()`、`reportAbiMismatch()`
- **依赖**：`abi_type_compat`
- **大约行数**：~500 行

---

## 执行顺序建议

### 阶段一：P0 文件（影响面广，立即改善）

1. **main.zig** — 最优先。它只引用别人，无被引用风险。拆出后主文件降至 ~150 行，立竿见影。
   - 创建 `src/cli/` 目录
   - 按顺序：`pass_registry.zig` → `issue_filter.zig` → `ffi_signal.zig` → `output.zig` → `runner.zig`
   - 最后精简 `main.zig` 至入口函数

2. **free_validation.zig** — 独立性强，不被其他 pass 引用（只注册在 pipeline 中），风险低。
   - 先提取 `free_validation_lang.zig`（纯函数，无状态）
   - 再提取 `free_validation_tracker.zig`
   - 最后精简主文件

3. **cross_lang_dataflow.zig** — 先提取 `cross_lang_alloc_classify.zig`，这些是纯函数；再提取 `cross_lang_orphan.zig`；最后清理主文件的 `run()` 方法

### 阶段二：P1 文件（接口稳定后，其他文件改动变容易）

4. **ffi_contract_db.zig** — 最简单的 P1，纯数据/逻辑分离，提取 `ffi_contract_data.zig` 即可

5. **pass_types.zig** — 被大量文件引用，需要格外小心。建议：
   - 先提取 `diagnostic_writer.zig`（最独立）
   - 再提取 `pass_context_stdlib.zig`（无外部依赖）
   - 最后提取 `global_alloc_tracker.zig`
   - 在 `pass_types.zig` 保留 re-export，避免大量引用路径变更

6. **pipeline.zig** — 提取 `leak_reporter.zig`；其余逻辑保留

7. **memory_graph.zig** — 延续已有的 `mg_*` 拆分模式，提取 `memory_graph_cfg.zig` 和 `memory_graph_query.zig`

### 阶段三：P2 文件（收尾优化）

8. `rule_customization.zig` → 提取 `rule_customization_parser.zig`
9. `gc_safety_analyzer.zig` → 提取 `gc_jni_patterns.zig` 和 `gc_reference_cycle.zig`
10. `language_detector.zig` → 提取 `language_detector_sampling.zig` 和 `language_detector_name.zig`
11. `ffi_body_check.zig` → 提取 `ffi_body_vuln_checks.zig`
12. `ffi_language_classifier.zig` → 提取 `ffi_demangle.zig`（顺便合并重复的 `isRustMangledName`）
13. `abi_compat_checker.zig` → 提取 `abi_type_compat.zig`

---

## 风险点

### Zig 语言约束

- **Zig 不支持跨文件 struct 方法**：所有 struct 方法（`pub fn foo(self: *MyStruct)`）必须定义在 struct 所在文件。拆分时要么：(a) 将大方法提取为接受 `*StructType` 参数的独立函数放在新文件，然后在原 struct 中用包装方法调用；(b) 直接在原文件保留方法，只提取不依赖 struct 状态的纯函数。`memory_graph.zig`、`pipeline.zig`、`pass_types.zig` 的拆分都面临此约束。
- **Zig 不允许循环 import**：`ffi_contract_db.zig` 和 `ffi_contract_data.zig` 之间的类型依赖需仔细设计（见该文件的迁移注意事项）。`pass_types.zig` 引用了许多其他模块，需确认新建子模块不会反向引用 `pass_types`。

### 引用路径变更

- `DiagnosticWriter` 被大量 pass 通过 `@import("../../pass/pass.zig").DiagnosticWriter` 使用，提取后如不保留 re-export 需做全局替换
- `pass_types.zig` 中的所有类型被整个 `src/pass/` 下的文件引用，建议提取后在原文件保留 re-export（`pub const GlobalAllocTracker = @import("global_alloc_tracker.zig").GlobalAllocTracker;`），这样所有现有 import 路径无需修改

### 测试覆盖

- `main.zig` 第 1917–2517 行有大量 test 块，拆分时注意将测试随对应逻辑一起迁移，或保留在 `main.zig` 中调用新模块的导出函数
- 建议每提取一个模块后立即运行 `zig build test` 确认无回归

### build.zig 更新

- 新创建的 `src/cli/` 目录和其中的模块需要确认是否需要在 `build.zig` 或 `root.zig` 中显式注册（取决于项目的模块导出结构）
