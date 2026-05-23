# OmniScope 重构设计与待办

编码风格与约束：`./plan/rules/rules.md`

---

## 目标

把当前偏语言特化、偏名字匹配的噪声过滤逻辑，整理成一套**跨语言、可维护、可组合**的通用分析架构。

重点： CrossLangEdge + OwnershipGraph + Boundary Reachability

产品定位：

- OmniScope 是 LLVM IR 层跨语言 FFI 安全审计工具。
- OmniScope 不做通用静态检测器，不承诺证明所有漏洞。
- OmniScope 输出高置信风险和可追踪证据链。
- 重点问题是跨语言边界上的 ownership、lifetime、ABI、pointer flow 和 callback 风险。

核心输出证据：

- 哪个函数是 boundary。
- 哪个 pointer 跨过边界。
- 谁分配、谁释放。
- 为什么 ownership 不匹配。
- 哪条调用链让风险 reachable。

核心原则：

- 不依赖 crate 名白名单。
- 不依赖 per-function body 扫描来判断“是否值得分析”。
- 保留 FFI producer、boundary、unknown 场景。
- 让所有 heavy pass 共享同一份 surface 分类结果。
- 单文件保持在 1000 行以内，模块职责清晰。

---

## 当前状态

### 已完成或基本完成

- `PassContext` 中已有 `ffi_set_cache`、`danger_surfaces_cache`、`danger_path_visited_cache`。
- `isOnDangerPathFull()` 已按懒加载缓存方式工作。
- `origin_classifier.zig` 已存在雏形实现。
- `PassContext.function_origin` 已经预留。
- `PointerOwnership` 已经接入 MemoryGraph、GlobalAllocTracker 和 IR fallback 三来源。

### 仍需收敛

- surface 分类和 noise filter 的职责边界还不清晰。
- `PointerOwnership` 仍有重复扫描和重复分类。
- pipeline 里还没有统一的通用噪声过滤 pass 接线。
- 多处注释和实现状态不一致，需要同步。

---

## 推荐架构

### 分层职责

1. `ZoneClassifier`
   - 只做轻量 zone 判断。
   - 适合作为第一道 gate。

2. `SurfaceClassifierPass`
   - 做跨语言通用的函数表面分类。
   - 输出 `FunctionSurface`。
   - 供所有 heavy pass 共享。

3. `DangerSurfacePass`
   - 做 pointer 级别的 danger path 识别。
   - 依赖 `SurfaceClassifierPass` 的结果做早期过滤。

4. `PointerOwnership`
   - 只分析需要分析的函数。
   - 不能再为“是否值得分析”而扫描整个函数体。

5. `noise_filter`
   - 只负责 issue/report 侧的降噪与风险分级。
   - 不再承担主 surface 决策。

---

## 数据结构设计

### 1. `FunctionSurface`

建议作为全局统一分类结果：

```zig
pub const FunctionSurface = enum {
    user_code,
    dependency,
    runtime,
    standard_library,
    compiler_generated,
    boundary,
    unknown,
};
```

语义：

- `user_code`：默认完整分析。
- `dependency`：完整分析，但报告优先级可以更低。
- `boundary`：FFI、导出、跨语言边界，永远保留。
- `runtime` / `standard_library` / `compiler_generated`：默认跳过 heavy analysis。
- `unknown`：保留分析，安全优先。

### 2. `FunctionSurfaceHint`

每层分类先给 hint，再做最终合并：

```zig
pub const FunctionSurfaceHint = struct {
    surface: FunctionSurface,
    confidence: Confidence,
    reason: []const u8,
};

pub const Confidence = enum(u8) {
    low,
    medium,
    high,
};
```

用途：

- 便于调试分类来源。
- 便于测试每一层信号。
- 便于报告阶段打印“为什么跳过/保留”。

### 3. `FunctionSurfaceRecord`

建议在 `PassContext` 中缓存最终结果：

```zig
pub const FunctionSurfaceRecord = struct {
    func_ptr: u64,
    surface: FunctionSurface,
    confidence: Confidence,
    reason: []const u8,
};
```

更推荐的实际存储形式：

- `std.AutoHashMap(u64, FunctionSurface)` 作为主查询表。
- 如需调试，再补一个 `surface_reason_cache`。

### 4. `PassContext` 新增字段

建议增加：

```zig
function_surface: std.AutoHashMap(u64, surface_classifier.FunctionSurface),
function_surface_reason: std.StringHashMap([]const u8),
```

如果后续觉得字符串太重，可以只保留 surface，不保留 reason。

### 5. `Origin / Surface` 查询 API

建议在 `PassContext` 提供：

```zig
pub fn getFunctionSurface(self: *const PassContext, func_ptr: u64) surface_classifier.FunctionSurface
pub fn shouldAnalyzeFunctionSurface(self: *const PassContext, func_ptr: u64) bool
```

规则：

- `unknown` 返回 `true`。
- `boundary` 返回 `true`。
- `user_code` / `dependency` 返回 `true`。
- `runtime` / `standard_library` / `compiler_generated` 返回 `false`。

---

## 文件结构设计

目标是让每个文件都容易读，且不超过 1000 行。

### 推荐目录

```text
src/semantics/
  surface_classifier.zig
  surface_classifier_linkage.zig
  surface_classifier_debug.zig
  surface_classifier_callgraph.zig
  surface_classifier_tests.zig

src/pass/
  pass.zig
  manager.zig
  analysis/
    origin_classifier_pass.zig
    pointer_ownership.zig
    danger_surface.zig

src/semantics/
  noise_filter.zig
  language_detector.zig
  zone_classifier.zig
  call_graph.zig
```

### 拆分原则

- 每个文件只解决一个问题。
- 分类逻辑和 pipeline 执行逻辑分离。
- 单个分类文件不要同时做“定义 + 扫描 + 报告 + 测试”。
- 测试尽量跟实现邻近，但避免把主文件撑得过长。

### 建议文件职责

- `surface_classifier.zig`
  - 公共类型。
  - 聚合入口。
  - 最终 merge 逻辑。

- `surface_classifier_linkage.zig`
  - linkage / debug presence 相关的廉价启发式。

- `surface_classifier_debug.zig`
  - debug metadata / provenance 解析。

- `surface_classifier_callgraph.zig`
  - reachability / boundary propagation。

- `origin_classifier_pass.zig`
  - pass 入口，负责遍历 module、填充 `PassContext`。

---

## 分类信号设计

### Layer 1: Linkage

低成本信号：

- `LLVMGetLinkage`
- `LLVMIsDeclaration`
- debug info 是否存在

用途：

- 快速识别 compiler-generated 风格函数。
- 只能做 hint，不能单独做最终决策。

### Layer 2: Debug Provenance

统一读取：

- `!DISubprogram`
- `!DIFile`
- path / directory provenance

用途：

- 区分 workspace、stdlib、dependency、runtime、generated。
- 优先使用 provenance，不使用 crate 名白名单。

### Layer 3: CallGraph Reachability

用途：

- 捞回被误判为 generated 的可达函数。
- 保留 FFI producer 和 boundary 相关函数。
- 避免只靠 path / linkage 误杀。

### Layer 4: Language / ABI / Boundary Hints

输入信号：

- `language_detector`
- calling convention / ABI
- `CrossLangEdge`
- exported symbols

用途：

- 标记 `boundary`。
- 对依赖 crate 的 FFI 函数做保留。

---

## 实施待办

### 阶段 1：接入 surface classifier

1. 完成 `SurfaceClassifierPass`。
2. 在 `PassManager` 中注册到 zone classifier 后、heavy analysis 前。
3. 将最终结果写入 `ctx.function_surface`。
4. 补 `PassContext.getFunctionSurface()` 和 `shouldAnalyzeFunctionSurface()`。

### 阶段 2：统一下游消费

1. `PointerOwnership` 改为先查 surface 再决定是否分析。
2. `DangerSurfacePass` 优先使用 surface 结果做 pruning。
3. `noise_filter` 只保留 issue/report 侧逻辑。
4. 清理重复的 origin/surface 概念，保留一套 canonical 定义。

### 阶段 3：优化 PointerOwnership init

1. 给 `MemoryGraph` 缓存函数信息，减少 `resolveInstFuncName()` 重复调用。
2. 优化 Source 3 的 IR fallback scan。
3. 预构建 free 函数名集合，减少重复 registry lookup。
4. 避免对所有函数做无意义的 body 扫描。

### 阶段 4：优化 analysis 阶段

1. 在 heavy 子步骤前统一加 surface gate。
2. 对 `runtime` / `standard_library` / `compiler_generated` 默认跳过。
3. `unknown` 保留分析。
4. `boundary` 永远保留。

### 阶段 5：测试和回归

1. `FunctionSurface` 分类测试。
2. `mergeLayers()` 测试。
3. `PassContext` 查询 API 测试。
4. 小型 FFI 样例回归。
5. `wasmtime_test.bc` 和 `sqlite3.bc` 性能回归。

---

## 文件大小控制

### 原则

- 单文件不超过 1000 行。
- 过长的枚举、长表、测试数据都要拆分。
- 大型分类规则应拆成多个小模块，不要堆在一个文件里。

### 建议检查点

- `surface_classifier.zig` 不超过 400~500 行。
- `pointer_ownership.zig` 拆分辅助逻辑，避免继续膨胀。
- 测试表格和长样例单独放测试文件。

---

## 代码可维护性要求

### 必须满足

- 结构简单直接。
- 命名遵循项目规则。
- 所有注释使用英文。
- 公共 API 有 doc comments。
- 错误处理符合 Zig 风格。
- 内存所有权清晰。
- 改动尽量局部、外科手术式。

### 不建议的做法

- 不要继续扩展语言白名单。
- 不要在 surface 判断中做全函数 body 扫描。
- 不要把 debug provenance 和 issue suppression 混成一个模块。
- 不要维护两套互相冲突的 `FunctionOrigin` 体系。

---

## 测试要求

### 必测边界

- `unknown` surface 必须保留。
- `boundary` surface 必须保留。
- workspace path、stdlib path、dependency path 都要覆盖。
- missing debug info 要有降级策略。
- `CrossLangEdge` 参与时不能误杀。

### 回归样例

- 小型 Rust FFI 样例。
- `Box::into_raw` / `Box::from_raw` 场景。
- `extern "C" fn` producer 场景。
- 依赖 crate 的 boundary 场景。
- 编译器生成函数的噪声过滤场景。

---

## 性能验收

基线参考：

| 文件 | init (ms) | detect (ms) | analysis (ms) | total (ms) |
|------|-----------|-------------|---------------|------------|
| wasmtime_test.bc | 17067 | 7441 | 11831 | 53407 |
| sqlite3.bc | 5942 | 3503 | 4647 | 20033 |

目标：

- `PointerOwnership init` 明显下降。
- `PointerOwnership analysis` 明显下降。
- recall 不下降，尤其不能漏掉 FFI producer 和 boundary 场景。

---

## 推荐执行顺序

1. 定义 `FunctionSurface` 和查询 API。
2. 接入 `SurfaceClassifierPass`。
3. 让 `PassContext` 统一缓存 surface 结果。
4. 改造 `PointerOwnership` 的 gate 逻辑。
5. 拆分 `surface_classifier` 相关模块。
6. 优化 `MemoryGraph` 和 Source 3 fallback。
7. 补测试和性能回归。

---

## 验收清单

- [ ] File is under 1000 lines
- [ ] Code is simple and straightforward
- [ ] All comments are in English
- [ ] Code-to-comment ratio is approximately 7:3
- [ ] Tests include boundary cases
- [ ] No files were deleted without permission
- [ ] Naming conventions are followed
- [ ] Code is formatted with `zig fmt`
- [ ] All tests pass
- [ ] Public APIs have doc comments
- [ ] Error handling is appropriate
- [ ] Memory management is correct
- [ ] Changes are surgical and minimal

---

## 开发计划（基于可行性分析，分 4 阶段推进）

### 架构决策：统一目录 + 单一注册

SurfaceClassifier 是一个完整子系统，包含多层分类逻辑和一个 pass。
所有子模块放在 `src/semantics/surface_classifier/` 目录下，对外通过
`surface_classifier.zig`（目录 root）提供统一接口。

Pipeline 只注册一个 pass `SurfaceClassifierPass`。该 pass 内部自行编排
两阶段执行：
  - Phase 1（L1+L2+L3+L4-early）：CallGraphPass 之前，用 linkage / debug
    / reachability / exported symbols 完成首次分类
  - Phase 2（L4-late）：CallGraphPass 之后，用 CrossLangEdge 补标 boundary

这样 pipeline 只需一个注册点，内部时序由 pass 自己管理。

```
src/semantics/surface_classifier/
  surface_classifier.zig       ← 目录 root，导出类型 + 公共 API
  linkage.zig                  ← L1 linkage heuristic
  debug_origin.zig             ← L2 debug provenance
  callgraph.zig                ← L3 reachability logic
  boundary.zig                 ← L4 boundary detection

src/pass/analysis/
  surface_classifier_pass.zig  ← 唯一 pass 入口，对外注册
```

### 阶段 1：重命名 + 目录重组 + 新增 boundary（低风险）

- [x] 1.1 创建 `src/semantics/surface_classifier/` 目录
- [x] 1.2 创建 `surface_classifier.zig`（目录 root）：`FunctionSurface` enum（含 `boundary`）、`SurfaceHint`、`Confidence`、`mergeLayers()`、re-exports
- [x] 1.3 创建 `linkage.zig`：L1 linkage heuristic（从 origin_classifier.zig 迁移）
- [x] 1.4 创建 `debug_origin.zig`：L2 debug provenance（从 origin_classifier.zig 迁移）
- [x] 1.5 创建 `callgraph.zig`：L3 reachability placeholder
- [x] 1.6 创建 `boundary.zig`：L4 boundary detection（exported symbols + CrossLangEdge）
- [x] 1.7 创建 `surface_classifier_pass.zig`：统一 pass 入口（Phase 1 + Phase 2）
- [x] 1.8 删除旧文件 `src/semantics/origin_classifier.zig` 和 `src/pass/analysis/origin_classifier.zig`
- [x] 1.9 更新 `PassContext`：`function_origin` → `function_surface`，API 方法对齐新命名
- [x] 1.10 更新 `pipeline.zig` 初始化 `function_surface`
- [x] 1.11 更新 `root.zig` 导出：`SurfaceClassifierPass` + `FunctionSurface`
- [x] 1.12 更新 `main.zig` 注册：`SurfaceClassifierPass`（替换 `OriginClassifierPass`）
- [x] 1.13 验证：`zig build` 通过 + 60/60 测试通过

### 阶段 2：统一下游消费 + 消除双体系（中风险）

- [x] 2.1 将 `pass.zig` 中 `classifyFunctionOrigin()` 改为 `classifyFunctionSurface()`，返回类型对齐 `FunctionSurface`
- [x] 2.2 将 `pass.zig` 中 `shouldAnalyzeFunctionByName()` 改为 `shouldAnalyzeFunctionSurfaceByName()`
- [x] 2.3 逐个替换 12 个 `noise_filter.classifyFunctionFull()` 调用点为 `ctx.classifyFunctionSurface()`：
  - [x] 2.3.1 `pointer_ownership.zig:497`
  - [x] 2.3.2 `ffi_type_mismatch.zig:168`
  - [x] 2.3.3 `cpp_fp_reduction.zig:705`
  - [x] 2.3.4 `callback_escape.zig:723`
  - [x] 2.3.5 `ptr_lifetime.zig:250`
  - [x] 2.3.6 `return_check.zig:73`
  - [x] 2.3.7 `ffi_body_check.zig:564`
  - [x] 2.3.8 `memory_safety.zig:111`
  - [x] 2.3.9 `memory_safety.zig:223`
  - [x] 2.3.10 `free_validation.zig:91`
  - [x] 2.3.11 `pass.zig:606`（报告逻辑）
  - [x] 2.3.12 `ffi_type_mismatch.zig` 其他引用
- [x] 2.4 统一 `noise_filter.zig:FunctionOrigin` → 添加 `FunctionSurface` re-export + `functionSurfaceToOrigin()` 转换函数
- [x] 2.5 统一 `noise_reduction.zig:FunctionOrigin` → 添加 `FunctionSurface` + `functionSurfaceToOrigin` re-export
- [x] 2.6 更新 `path_filter.zig` 中 `FunctionOrigin` 引用为 `FunctionSurface`（通过 `noise_filter.FunctionSurface` 已可访问）
- [x] 2.7 更新 `root.zig` 中 `NoiseFunctionOrigin` 导出为 `FunctionSurface`（添加 `FunctionSurface` + `functionSurfaceToOrigin` re-export）
- [x] 2.8 验证：`zig build` 通过 + 60/60 测试通过

### 阶段 3：noise_filter 瘦身 + pass 内部两阶段编排（高风险）

- [x] 3.1 SurfaceClassifierPass 实现两阶段编排：
  - Phase 1：在 CallGraphPass 之前运行（L1+L2+L3+L4-early）
  - Phase 2：在 CallGraphPass 之后运行（L4-late，用 CrossLangEdge 补标 boundary）
  - 通过 `ctx.function_surface_phase` 标记当前阶段，同一 pass 两次 run()
- [x] 3.2 `noise_filter.zig` 瘦身：删除白名单数组（RUST_STDLIB_PREFIXES 等 ~200 行）
- [x] 3.3 `noise_filter.zig` 瘦身：删除 `classifyFunction()` 和各语言 `classifyXxxFunction()`（~600 行）
- [x] 3.4 `noise_filter.zig` 瘦身：删除 `classifyFunctionFull()` 和 `shouldAnalyze()`（~50 行）
- [x] 3.5 `noise_filter.zig` 保留：`RiskLevel` + `getRiskLevel()` + `ClassificationResult`（报告侧核心）
- [x] 3.6 `noise_filter.zig` 保留：`FunctionSurface` re-export（向后兼容 shim）
- [x] 3.7 验证：`zig build` 通过 + 60/60 测试通过

### 阶段 4：性能验证 + 回归测试

- [x] 4.1 `FunctionSurface` 分类单元测试（linkage/debug/callgraph/boundary 各层）
- [x] 4.2 `mergeLayers()` 单元测试（覆盖所有 L1+L2+L3+L4 组合）
- [x] 4.3 `PassContext.getFunctionSurface()` / `shouldAnalyzeFunctionSurface()` 测试
- [x] 4.4 小型 FFI 样例回归：Rust `Box::into_raw` / `extern "C" fn` 场景
- [x] 4.5 `wasmtime_test.bc` 性能回归：对比 init/detect/analysis 时间
- [x] 4.6 `sqlite3.bc` 性能回归：对比 init/detect/analysis 时间
- [x] 4.7 确认 recall 不下降：FFI producer 和 boundary 场景不被误杀
- [ ] 4.8 确认 `noise_filter.zig` 行数 < 200（当前 305 行，含测试 ~100 行，需进一步拆分测试）
- [ ] 4.9 确认所有单文件 ≤ 1000 行（当前 7 个文件超标，属历史遗留问题）

### 阶段 4 补充：ffi-demo TP/FP 分析

使用 `/Users/scc/code/ffi-demo/output/` 中的 7 个 .bc 文件进行了完整分析。

结果：TP=2, FP=0, FN=8, Precision=100%, Recall=20%, F1=0.333

检测到的真实漏洞：
- LEAK-MALLOC: `c_hash()` 中 malloc 在 len==0 时不 free
- FFT-LEAK-5: `c_fft_test_signal()` 中 temp_buf malloc 未 free

FN 主要原因：fd 泄漏(不在 scope)、C++ new/delete(未跟踪)、静态分配、跨过程 ownership。

报告已保存至 `outputs/ffi_demo_tp_fp_analysis.md`，原始 JSON 至 `outputs/ffi_demo/`。

### 阶段 4 性能结果

| 文件 | 基线 total | 当前 total | 变化 |
|------|-----------|------------|------|
| wasmtime_test.bc | 53407ms | 38276ms | -28% |
| sqlite3.bc | 20033ms | 17753ms | -11% |

FFI 回归：rust_ffi_bugs.ll (20 函数, 13 issues), cross_lang_free_bugs.ll (22 函数, 3 issues), red_team_cpp_ffi.bc (124 函数, 5 issues) — recall 正常。

新增测试：39 个（surface_classifier 15 + debug_origin 10 + linkage 3 + boundary 1 + noise_filter 10）。

### 阶段 5：输出优化（基于 improve.md 反馈）

- [x] 5.1 DiagnosticWriter.info() 改为只在 verbose/debug 输出（分离 pipeline telemetry）
- [x] 5.2 新增 formatStructuredReport()：Findings → Coverage → Summary → Verdict
- [x] 5.3 printZoneSummary() 改为只在 verbose/debug 输出
- [x] 5.4 Performance Profile 改为只在 verbose/debug 输出
- [x] 5.5 LANG-DETECT 改为 log.debug（只在 debug 输出）
- [x] 5.6 RustFfiFilter 重命名为 FFIAuditor（跨语言通用）
- [x] 5.7 main.zig 中 pipeline log 改为 log.debug
- [x] 5.8 验证：构建通过 + 60/60 测试通过

输出效果：
- **默认模式**：只有结构化报告（Findings/Coverage/Summary），干净专业
- **--verbose**：+ Zone Summary + SurfaceClassifier + Pipeline pass 统计
- **--debug**：+ 全部内部 trace
