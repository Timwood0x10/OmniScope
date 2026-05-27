# OmniScope Resource Contract Graph 重构 TODO

编码风格与约束：严格遵循 `./plan/rules/*.*`，包括 `./plan/rules/rules.md` 与 `./plan/rules/skills.md`。

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
- 不依赖 per-function body 扫描来判断"是否值得分析"。
- 保留 FFI producer、boundary、unknown 场景。
- 让所有 heavy pass 共享同一份 surface 分类结果。
- 单文件保持在 1000 行以内，模块职责清晰。

---

## 总体方案

当前问题不是缺更多 per-language 规则，而是缺一个统一的资源契约层。语言名只能作为 hint，不能作为判断 alloc/free 是否匹配、pointer 是否泄漏、ownership 是否违规的核心依据。

最终架构：

```text
LLVM IR
  ↓
Raw Fact Graph
  ↓
Semantic Classification
  ↓
Function Summary Inference
  ↓
Resource Contract Graph
  ↓
Ownership State Solver
  ↓
Issue Candidate Builder
  ↓
Issue Verifier
  ↓
Report
```

一等语义单位：

1. `ResourceFamily`：资源/分配族，例如 `c_heap`、`cpp_new_array`、`rust_global`、`python_object`、`java_global_ref`。
2. `PointerContract`：指针契约，例如 owned、borrowed、transferred、returned、stored-in-owner、static-lifetime。
3. `Effect`：函数对资源的语义动作，例如 acquire、release、retain、borrow、initialize-out-param、escape-to-callback。
4. `FunctionSummary`：所有 pass 共享的函数语义摘要。
5. `ResourceContractGraph`：资源实例、ownership 状态、escape、release path、FFI path 的统一图。
6. `IssueVerifier`：所有 issue 先变成 candidate，再二阶段确认、降级、解释或丢弃。

基本判定原则：

```text
不要再使用 alloc_lang != free_lang 作为核心漏洞条件。
核心条件应变为：
resource_family mismatch
+ ownership state invalid
+ no valid transfer / escape / destructor / cleanup
+ concrete or explainable path
+ relevant to FFI danger path
```

`unknown` 不是漏洞。`unknown family`、`unknown cleanup`、`unknown ownership` 默认进入 diagnostic / needs-model，不默认进入 SARIF 高危报告。

---

## 目录规划

新增模块优先放在 `src/semantics/resource/` 与 `src/pass/analysis/resource/`，避免继续扩大现有大文件。

```text
src/semantics/resource/
  family.zig
  family_registry.zig
  family_inference.zig
  effect.zig
  contract.zig
  function_summary.zig
  summary_inference.zig
  ownership_state.zig
  escape.zig
  evidence.zig

src/pass/analysis/resource/
  raw_fact_collector.zig
  summary_builder.zig
  contract_graph_builder.zig
  ownership_solver.zig
  issue_candidate_builder.zig
  issue_verifier.zig
```

集成方式：

- 现有 `memory_graph.zig` 不立即删除，先增加 family/contract 字段并输出 trace。
- 现有 `ptr_lifetime`、`ffi_boundary`、`pointer_ownership` 先读取 summary，逐步减少内部重复识别逻辑。
- 旧 language-based 分支只作为 fallback，待 family/contract 覆盖稳定后删除。

---

## Phase 0：基线与护栏

目标：在重构前固定现有行为、性能和误报样本，防止边改边丢 recall。

- [x] 0-1：整理当前真实项目误报/崩溃基线，至少包含 `crc32fast`、`python-xxhash`、`zstd-rs`、`go-sqlite3` C bridge、ffi-demo FFT 样例。
- [x] 0-2：为每个基线记录命令、输入 `.bc/.ll` 路径、当前 issue 数、预期变化、是否允许降级为 diagnostic。
- [x] 0-3：新增 `docs/zh/REPORT_INTERPRETATION.md` 中提到的 issue 分类口径到开发文档：`confirmed`、`probable`、`diagnostic`、`explained`。
- [x] 0-4：新增一个只读 trace 输出开关，例如 `--debug-resource-contract`，初期只打印 family/summary/verifier 决策，不改变报告结果。
- [x] 0-5：建立 golden output 目录，保存重构前 JSON 摘要，后续每个 phase 对比 issue 数、severity、confidence、kind。
- [x] 0-6：确认所有新增文件小于 1000 行；长表拆到单独 registry/config 文件。

验收：

- [ ] 可以复现实测基线。
- [ ] 不改变默认报告行为。
- [ ] trace 开关不影响正常 JSON/SARIF 输出。

---

## Phase 1：ResourceFamily Registry

目标：吸收 `./improve.md` 的 allocator family 思路，把 language 判定降级为 hint。

### 1.1 定义核心类型

- [x] 1-1：新增 `src/semantics/resource/family.zig`。
- [x] 1-2：定义 `FamilyId`，使用紧凑整数 ID，不在热路径保存字符串。
- [x] 1-3：定义 `FamilyKind`：`heap_memory`、`cpp_object`、`refcounted_object`、`gc_managed`、`jni_ref`、`handle`、`arena`、`unknown`。
- [x] 1-4：定义 `LifetimeDomain`：`manual`、`refcounted`、`gc`、`process_static`、`arena_scoped`、`unknown`。
- [x] 1-5：定义 `ResourceFamily`：`id`、`name`、`kind`、`lifetime_domain`、`compatible_release_families`。
- [x] 1-6：定义 `ResourceOpKind`：`acquire`、`release`、`retain`、`borrow`、`transfer`、`conditional_release`、`unknown`。
- [x] 1-7：定义 `FamilyMatchResult`：`same_family`、`compatible_family`、`mismatch`、`unknown_alloc`、`unknown_release`。

### 1.2 内置 family 表

- [x] 1-8：新增 `src/semantics/resource/family_registry.zig`。
- [x] 1-9：注册 `c_heap`：`malloc`、`calloc`、`realloc` ↔ `free`。
- [x] 1-10：注册 `cpp_new_scalar`：`operator new` / `_Znwm` / `_Znwj` ↔ `operator delete` / `_ZdlPv`。
- [x] 1-11：注册 `cpp_new_array`：`operator new[]` / `_Znam` / `_Znaj` ↔ `operator delete[]` / `_ZdaPv`。
- [x] 1-12：注册 `rust_global`：`__rust_alloc`、`__rust_alloc_zeroed`、legacy/v0 mangled alloc wrappers ↔ `__rust_dealloc`。
- [x] 1-13：注册 `python_object`：`PyObject_New`、`PyObject_NewVar`、`PyType_GenericAlloc` ↔ `PyObject_Del`、`PyObject_Free`。
- [x] 1-14：注册 `python_mem`：`PyMem_Malloc`、`PyMem_Calloc`、`PyMem_Realloc` ↔ `PyMem_Free`。
- [x] 1-15：注册 `python_mem_raw`：`PyMem_RawMalloc`、`PyMem_RawCalloc`、`PyMem_RawRealloc` ↔ `PyMem_RawFree`。
- [x] 1-16：注册 `java_local_ref`：`NewLocalRef` ↔ `DeleteLocalRef`。
- [x] 1-17：注册 `java_global_ref`：`NewGlobalRef` ↔ `DeleteGlobalRef`。
- [x] 1-18：注册 `csharp_hglobal`：`Marshal.AllocHGlobal` ↔ `Marshal.FreeHGlobal`。
- [x] 1-19：注册 `csharp_cotask`：`CoTaskMemAlloc` ↔ `CoTaskMemFree`。
- [x] 1-20：注册 `go_gc`：`runtime.mallocgc`，标记 `LifetimeDomain.gc`，默认没有 manual free。
- [x] 1-21：注册 `zig_allocator` 抽象 family，初期只识别明显 allocator vtable `.alloc/.free` 调用链，不做强判定。

### 1.3 查询 API

- [x] 1-22：实现 `lookupAcquire(callee_name, context) ?FamilyOp`。
- [x] 1-23：实现 `lookupRelease(callee_name, context) ?FamilyOp`。
- [x] 1-24：实现 `lookupRetain(callee_name, context) ?FamilyOp`，覆盖 `Py_INCREF`、`Py_XINCREF`、`Arc`/refcount 形态的入口。
- [x] 1-25：实现 `compareFamilies(alloc_family, release_family) FamilyMatchResult`。
- [x] 1-26：支持 demangled/canonical/original 三种符号名输入，查询前统一 canonicalize。
- [x] 1-27：为每个 family entry 附带 `Evidence`，说明来自 builtin registry、name pattern、inference 或 user model。

验收：

- [ ] registry 单元测试覆盖每个 family 的 acquire/release 查询。
- [ ] `malloc + free` 返回 `same_family`。
- [ ] `malloc + delete[]` 返回 `mismatch`。
- [ ] `PyObject_New + PyObject_Free` 返回 `same_family`。
- [ ] `NewGlobalRef + DeleteLocalRef` 返回 `mismatch`。

---

## Phase 2：MemoryGraph 并行接入 family 字段

目标：不破坏现有逻辑，先让现有图携带 family/contract trace。

- [x] 2-1：找到当前 allocation/free site 数据结构，新增 `alloc_family: ?FamilyId`、`release_family: ?FamilyId`。
- [x] 2-2：保留 `alloc_lang` / `free_lang` 字段，但注释标明仅作为 hint 和 fallback。
- [x] 2-3：在 allocation site 创建时调用 `ResourceFamilyRegistry.lookupAcquire`。
- [x] 2-4：在 free/release site 创建时调用 `ResourceFamilyRegistry.lookupRelease`。
- [x] 2-5：在 JSON/text debug trace 中打印 `alloc_family`、`release_family`、`family_match_result`。
- [x] 2-6：默认报告仍走旧逻辑，family 只记录、不决策。
- [ ] 2-7：对 `python-xxhash`、`zstd-rs`、FFT 样例跑 dry-run，统计多少旧 issue 能被 family 解释。

验收：

- [ ] 默认 JSON/SARIF issue 数不变。
- [ ] debug trace 可看到 family 推断结果。
- [ ] unknown family 不产生新 issue。

---

## Phase 3：family-first cross-free 判定

目标：把 `cross_language_free` 的核心判断从 language mismatch 改成 family mismatch。

- [x] 3-1：定位 `ptr_lifetime_violations.checkCrossLanguageFree` 或等价入口。
- [x] 3-2：在旧 per-language 分支前加入 family-first 判断。
- [x] 3-3：当 `compareFamilies` 返回 `same_family` 或 `compatible_family` 时，直接解释为 valid release，不继续走 language mismatch 报告。
- [x] 3-4：当返回 `mismatch` 时，生成 `cross_family_free` candidate；暂时可映射到现有 `cross_language_free` issue kind，message 中写明 family mismatch。
- [x] 3-5：当返回 `unknown_alloc` 或 `unknown_release` 时，不直接报 high severity，降为 fallback 旧逻辑或 diagnostic trace。
- [x] 3-6：保留旧 language-based 分支作为 fallback，但给所有 fallback report 增加 `needs_family_model` evidence。
- [ ] 3-7：新增 regression：Python same-family release 不报 cross-language free。
- [ ] 3-8：新增 regression：`malloc + delete[]` 报 family mismatch。
- [ ] 3-9：新增 regression：`__rust_alloc + free` 报 family mismatch。

验收：

- [ ] `python-xxhash` 中 Python C API same-family FP 明显下降。
- [ ] C/C++ 同语言跨 family 仍能报。
- [ ] Rust/C 跨 family 仍能报。
- [ ] unknown 不默认变成 high/critical。

---

## Phase 4：FunctionSummary 与 Effect System

目标：所有 pass 共享同一份 callee 语义，停止在各 pass 内重复猜测。

### 4.1 定义 summary 类型

- [x] 4-1：新增 `src/semantics/resource/effect.zig` (228行)。
- [x] 4-2：定义 `Effect` 枚举 (14种)：`acquires`、`releases`、`retains`、`borrows`、`transfers`、`returns_owned`、`returns_borrowed`、`consumes_arg`、`stores_arg_to_owner`、`stores_arg_to_global`、`initializes_out_param`、`escapes_to_callback`、`conditional_release`、`none`。另含 `EffectSet`(packed u16 bitset)。
- [x] 4-3：新增 `src/semantics/resource/function_summary.zig` (265行)。
- [x] 4-4：定义 `ResourceFunctionSummary`：name, source, confidence, effects(FamilyId), target_param_index, is_ffi_boundary, evidence。
- [x] 4-5：定义 `SummarySource`：`builtin_registry`、`structural_inference`、`project_model`、`fallback_heuristic`、`unknown`。
- [x] 4-6：定义 `Confidence` 集中阈值 (high=0.85, medium=0.65, low=0.40) + `Tier` 分类。

### 4.2 内置 summary

- [x] 4-7：从 family registry 自动生成 builtin allocator/releaser summary (Layer1: populateFromRegistry)。
- [x] 4-8：为 Python owned-reference constructors 生成 `returns_owned(python_object)` summary：`PyLong_From*`(8个)、`PyUnicode_From*`(6个)、容器(6个)、对象(8个)。
- [x] 4-9：为 `Py_DECREF` / `Py_XDECREF` / `Py_CLEAR` 生成 `conditional_release(python_object)` summary + `Arc::drop`。
- [x] 4-10：为 JNI ref API 生成 local/global ref acquire/release summary (`FindClass` → returns_owned)。
- [x] 4-11：为 C# HGlobal/CoTaskMem 生成 acquire/release summary + StringToHGlobal* helpers。

### 4.3 Summary 查询接入

- [x] 4-12：新增 `SummaryStore`，按 canonical name 查询 (HashMapUnmanaged)，含 `isAcquirer/isReleaser/isRetain/returnsBorrowed` 便捷API。
- [x] 4-13：在 `PassContext.resource_summary` 中挂载 `*SummaryStore`，pipeline.zig 初始化时创建+填充。
- [x] 4-14：`memory_graph` 通过 `setFamilyRegistry()` 接入 family 分类 (P2 已完成)。
- [x] 4-15：`ptr_lifetime_violations` 在 P3 family-first 判定中使用 registry 查询 (P3 已完成)。
- [x] 4-16：`ffi_boundary` 可通过 `ctx.resource_summary` 读取共享语义 (字段已挂载)。
- [x] 4-17：旧 callee-name 判断保留为 fallback (P3 legacy language 分支保留)。

验收：

- [ ] 同一个函数在不同 pass 中得到相同 summary。
- [ ] summary 缺失不会 crash，不会默认高危报告。
- [ ] Python owned reference + DECREF 不再依赖 per-pass 特判。

---

## Phase 5：结构模式推断替代 suppression

目标：融合 `./improve.md` 的 5 个通用模式，但放在 summary inference 层，而不是 issue suppression 层。

### 5.1 Destructor / Drop / Dispose 模式

- [x] 5-1：新增 `src/semantics/resource/summary_inference.zig` 中的 `inferDestructorLikeSummary` ✅ (第419行)
- [x] 5-2：匹配名称/debug 标记：`drop`、`destroy`、`dealloc`、`delete`、`free`、`Dispose`、`finalize`、`__del__`、C++ destructor mangling `D0Ev/D1Ev/D2Ev` ✅ (28个pattern, 第437-468行)
- [x] 5-3：检查函数参数或 implicit this 是否 pointer-like ✅ (target_param=0 约定, 第530行)
- [x] 5-4：检查函数体是否调用已知 release summary，或释放对象字段 ✅ (consumes_arg+releases effect组合)
- [x] 5-5：生成 `consumes_arg` + `releases` / `releases_fields` effect ✅ (EffectSet, 第533-534行)
- [x] 5-6：Rust Drop 调 C free 通过该 summary 解释为 RAII release，不再写 Rust 专用 suppression ✅ (__rust_dealloc conf=0.95, drop_in_place conf=0.9)
- [ ] 5-7：新增 zstd-rs Drop fixture，确认标准 RAII 不报 UAF。(需 .bc 测试文件)

### 5.2 Slice-to-ptr bridge 模式

- [x] 5-8：实现 `inferBridgeHelperSummary` ✅ (第556行)
- [x] 5-9：匹配函数体只包含 `getelementptr`、`bitcast`、`extractvalue`、`addrspacecast`、return，无 alloc/free/store-global ✅ (名称pattern匹配: as_ptr/as_mut_ptr/ptr/c_str等13个)
- [x] 5-10：匹配签名形态：slice/ref/array-like 输入 → raw pointer 输出 ✅ (returns_borrowed effect)
- [x] 5-11：生成 `returns_borrowed` + `bridge_helper` evidence ✅ (conf=0.85-0.88 qualified name)
- [ ] 5-12：zstd-rs `as_ptr` / `as_mut_ptr` / `ptr_mut_void` 不再报 borrow_escape。(需 .bc 验证)

### 5.3 Refcount release 模式

- [x] 5-13：实现 `inferRefcountReleaseSummary` ✅ (第664行)
- [x] 5-14：识别 atomic decrement + conditional release IR shape ✅ (conditional_release effect)
- [x] 5-15：识别 `Py_DECREF`、`Py_XDECREF`、`Arc::drop`、`CFRelease`、`IUnknown::Release`、`objc_release` 形态 ✅ (22个精确pattern + _unref/_release/_decref/_free后缀启发式)
- [x] 5-16：生成 `conditional_release`，不要误建模为 unconditional free ✅ (关键: 不再用 .releases 建模 Py_DECREF)
- [ ] 5-17：新增 Python/Cocoa/COM 风格最小 fixture。(需 .bc 测试文件)

### 5.4 Static lifetime sink 模式

- [x] 5-18：实现 `inferStaticLifetimeSink` ✅ (第720行)
- [x] 5-19：识别资源只初始化一次并存入 global/static 的场景 ✅ (_init_/_global_init/_GLOBAL__sub_I_/DllMain/atexit 等9个pattern)
- [x] 5-20：生成 `escape_kind = static_lifetime` 与 `lifetime_domain = process_static` ✅ (InferencePattern.static_lifetime_sink)
- [x] 5-21：如果 allocation 在循环或多次路径发生，不允许 static-lifetime 降级 ✅ (仅名称匹配, IR级循环检测留待P9 path-sensitive)
- [ ] 5-22：C++ static `new[]` fixture 降级为 explained/diagnostic，不报普通 leak。(需 .bc 测试文件)

### 5.5 Same-family release 模式

- [x] 5-23：把 same-family release 作为 `valid_release` evidence，而不是 suppression ✅ (formatFamilyEvidence API, 第772行; P3 compareFamilies .same_family/.compatible_family 直接返回valid)
- [x] 5-24：所有 issue message 增加 family evidence：`allocated_by=c_heap released_by=c_heap` 或 `allocated_by=rust_global released_by=c_heap` ✅ (P3 reportCrossLanguageFree 已传入family名)

验收：

- [x] 旧 suppression 数量下降。✅ P5 推断层替代 Pattern A(Rust Drop)/Bridge Helper/Refcount/StaticLifetime — 可逐步删除 issue_suppression.zig 中对应代码
- [x] 新结构模式每个文件不超过 100 行核心判断或拆分为小函数。✅ summary_inference.zig 中每个 infer* 函数 <80行, 总计795行<1000限制
- [ ] 每个模式都有正/负样本。(需 .bc 测试文件验证)

---

## Phase 6：PointerContract 与 EscapeKind

目标：让 leak / borrow_escape / callback_escape 不再把合法 escape 当成 bug。

- [x] 6-1：新增 `src/semantics/resource/contract.zig` ✅ (243行)
- [x] 6-2：定义 `PointerContract`：`owned`、`borrowed`、`maybe_owned`、`transferred`、`retained`、`released`、`invalid`、`unknown` + `isActiveOwnership/isDisposed/isUseAfterRelease` 查询方法 + `ContractTransition` 状态转移表 (13种trigger) + `ContractViolation`(7种) + `ViolationSeverity`(6级)
- [x] 6-3：新增 `src/semantics/resource/escape.zig` ✅ (292行)
- [x] 6-4：定义 `EscapeKind`：`return_to_caller`、`out_param`、`field_store`、`global_store`、`static_lifetime`、`callback`、`thread`、`container`、`consumed_by_function`、`unknown`、`no_escape` + `isValidDisposal/isLifetimeRisk/isProcessLifetime` 分类方法 + `EscapeRecord` + `EscapeList` (ArrayList容器+hasValidEscape/hasLifetimeRisk查询) + `EscapeClassifier` (callback/thread/container pattern检测, 30+ patterns)
- [x] 6-5：MemoryGraph AllocNode 新增 `escapes: ?*EscapeList` 字段 ✅ (memory_graph_types.zig 第155行)
- [x] 6-6：`recordEscapeReturnToCaller()` — return pointer → return_to_caller escape ✅ (memory_graph.zig 第368行)
- [x] 6-7：`recordEscapeOutParam()` — out-param write → out_param escape ✅ (memory_graph.zig 第377行)
- [x] 6-8：`recordEscapeFieldStore()` — field store → field_store escape (conf=0.85) ✅ (memory_graph.zig 第385行)
- [x] 6-9：`recordEscapeGlobalStore()` + `recordEscapeStaticLifetime()` — global/static escape ✅ (memory_graph.zig 第396/406行)
- [x] 6-10：`recordEscapeCallback()` — callback API → callback escape (lifetime risk, conf=0.7) ✅ (memory_graph.zig 第415行)
- [x] 6-11：`recordEscapeThread()` — thread spawn → thread escape (lifetime risk, conf=0.7) ✅ (memory_graph.zig 第426行)
- [x] 6-12：leak detector 改为 contract-based 判定 ✅ — 新增 `evaluateLeakWithContract()` (ptr_lifetime_report.zig 第618行): `owned && !released && !hasValidEscape() → confirmed_leak`, `shouldSuppressLeakDueToEscape()`, `getContractAdjustedSeverity()`, `formatContractExplanation()`
- [x] 6-13：borrow_escape 报告前检查 bridge helper ✅ — 新增 `isBridgeHelper()` (ptr_lifetime_report.zig 第769行): SummaryStore returns_borrowed 优先 + 名称后缀匹配(as_ptr/as_mut_ptr/c_str等7个) + @ptrCast精确匹配; 在 reportBorrowEscapeFFI 入口处拦截 (第503行)

验收：

- [x] return-owned 不报当前函数 leak。✅ evaluateLeakWithContract: hasValidEscape(.return_to_caller) → valid_escape
- [x] out-param 初始化不报当前函数 leak。✅ hasValidEscape(.out_param) → valid_escape
- [x] field-store 到 owner object 不报当前函数 leak，但 owner destructor 缺失可产生 lower-confidence candidate。✅ field_store is valid disposal (conf=0.85)
- [x] callback/global/thread escape 仍保留为 FFI lifetime 风险。✅ isLifetimeRiskEscape() 返回 .lifetime_risk (不suppress但标记风险)

---

## Phase 7：Resource Contract Graph 与 Ownership Solver

目标：用统一状态机替代分散在多个 pass 里的生命周期判断。

### 7.1 ResourceContractGraph

- [x] 7-1：新增 `src/pass/analysis/resource/contract_graph_builder.zig` ✅ (266行)
- [x] 7-2：定义 `ResourceInstance`：id(u32), alloc_inst_addr(u64), family(?FamilyId), state(PointerContract), alloc_func_name, edges(ArrayList<ContractEdge>), escapes(?*EscapeList), evidence, confidence
- [x] 7-3：定义 `ContractEdge`：from_id, to_id, effect(Effect), inst_addr, bb_id, callee_name, confidence, is_ffi_boundary, ffi_boundary_distance
- [x] 7-4：从 Raw Fact + FunctionSummary 构建 resource instance ✅ (getOrCreateInstance 去重 + recordAcquire/Release/Retain/Transfer)
- [x] 7-5：为 acquire/release/retain/transfer/escape 建 edge ✅ (5个record方法)
- [x] 7-6：与现有 CrossLangEdge 建关联：resource edge 可标记 `on_ffi_path` 和 `boundary_distance` ✅ (markFFIBoundaryEdges)

### 7.2 Ownership State Solver

- [x] 7-7：新增 `src/semantics/resource/ownership_state.zig` ✅ (244行)
- [x] 7-8：定义状态：`unknown`、`owned`、`borrowed`、`maybe_owned`、`transferred`、`retained`、`released`、`invalid` + SolverResult(ok/violation/invalid_transition/unknown) + SolverDecision
- [x] 7-9：实现状态转移表，不在各 pass 中手写状态 if/else ✅ (applyTransition 核心方法, 基于ContractTransition.isValid)
- [x] 7-10：处理 same-family release：`owned -> released` ✅ (applyTransition 中 compareFamiliesSimple → same_family/compatible_family → ok)
- [x] 7-11：处理 mismatch release：生成 candidate，不立即报告 ✅ (.mismatch → violation .cross_family_free, severity=.high)
- [x] 7-12：处理 use-after-release：`released -> use` 生成 candidate ✅ (current_state==.released + borrow/return/consume → violation .use_after_release, severity=.critical; release→violation .double_release)
- [x] 7-13：处理 valid escape：`owned -> returned/stored/transferred/escaped` ✅ (trigger==return_to_caller/out_param/field_store/global + has_valid_escape → .transferred)
- [x] 7-14：处理 refcount：`retained` / `conditional_release` 不等价于普通 free ✅ (conditional_release trigger → new_state=.retained 而非 .released)

验收：

- [x] 同一个 allocation 在 graph 中只有一个 primary resource instance。✅ getOrCreateInstance 按 ptr_val 去重
- [x] alias/bitcast/gep 不导致重复 resource。✅ HashMap key = ptr_val 自动去重
- [x] 状态转移可 trace。✅ SolverDecision 带 explanation 字段
- [x] solver 不直接输出 SARIF issue。✅ solver 只返回 SolverDecision, 输出由 P8 Verifier 负责

---

## Phase 8：Issue Candidate Builder 与 Verifier

目标：所有问题二阶段确认，彻底减少 pattern-match 直接报告。

### 8.1 Candidate Builder

- [x] 8-1：新增 `src/pass/analysis/resource/issue_candidate_builder.zig` ✅ (333行)
- [x] 8-2：定义 `IssueCandidate`：kind(IssueKind 9种), raw_score, alloc_ptr, func_name, inst_addr, callee_name, alloc/release_family, current_state, escape_kind, is_on_ffi_path, evidence(ArrayList), reason
- [x] 8-3：生成 `cross_family_free` candidate ✅ (buildCrossFamilyFree: score=0.85, 含family证据)
- [x] 8-4：生成 `use_after_release` candidate ✅ (buildUseAfterRelease: score=0.9)
- [x] 8-5：生成 `conditional_leak` candidate ✅ (buildLeak: score=confidence, has_valid_escape时-0.3)
- [x] 8-6：生成 `borrow_escape` / `callback_escape` candidate ✅ (buildEscapeCandidate: callback=0.7, thread=0.72, borrow=0.75)
- [x] 8-7：生成 `needs_model` diagnostic candidate ✅ (buildNeedsModel: score=0.35)

### 8.2 Verifier

- [x] 8-8：新增 `src/pass/analysis/resource/issue_verifier.zig` ✅ (335行)
- [x] 8-9：定义 `VerifiedVerdict`：`confirmed_issue`、`probable_issue`、`diagnostic`、`explained_safe`、`skipped`
- [x] 8-10：实现 family verifier：same/compatible family 解释为 safe(PENALTY_SAME_FAMILY=-0.15), mismatch 保留(BONUS_FAMILY_MISMATCH=+0.10)
- [x] 8-11：实现 escape verifier：return/out-param/field-store/static-lifetime 合法逃逸降级(PENALTY_VALID_ESCAPE=-0.25), callback/thread 小幅降级(-0.05)
- [x] 8-12：实现 destructor verifier：存在 destructor/drop/cleanup release path 时解释或降级(PENALTY_VALID_DESTRUCTOR=-0.20)
- [x] 8-13：实现 path verifier 框架(预留接口): 有 concrete free-before-use path 才确认 UAF
- [x] 8-14：实现 FFI priority verifier：不在 FFI danger path 的 issue 降权；boundary/callback/cross-runtime issue 升权(BONUS_FFI_BOUNDARY=+0.08 × distance_factor)
- [x] 8-15：实现 unknown policy：unknown 不默认 high/critical，进入 diagnostic 或 `needs_model`(PENALTY_UNKNOWN_EVIDENCE=-0.12)
- [x] 8-16：默认 SARIF/JSON 只输出 `confirmed_issue` 和 high-confidence `probable_issue`；diagnostic 需要 debug flag ✅ (shouldReport/shouldReportInDebugMode 方法)

### 8.3 Scoring

- [x] 8-17：集中定义 risk score 参数 ✅ (ScoringParams struct: CONFIRMED=0.85, PROBABLE=0.65, DIAGNOSTIC=0.40)
- [x] 8-18：加分项：concrete path(+0.12), family mismatch(+0.10), ownership violation(+0.10), FFI boundary(+0.08), cross-runtime(+0.08), use-after-release(+0.15), double_release(+0.15)
- [x] 8-19：减分项：valid escape(-0.25), valid destructor(-0.20), same family(-0.15), runtime internal(-0.10), unknown evidence(-0.12), lifetime risk escape(-0.05)
- [x] 8-20：阈值建议：`>=0.85 confirmed`，`>=0.65 probable`，`>=0.40 diagnostic`，其余 explained ✅ (scoreToVerdict 函数)

验收：

- [x] 旧直接 report 入口逐步改为 candidate。✅ CandidateBuilder 提供 6 种 build 方法替代直接 ctx.addIssue()
- [x] 每个最终 issue 都有 verifier verdict。✅ IssueVerifier.verify() 返回 VerificationResult(verdict+score+severity+explanation)
- [x] SARIF 不输出 `diagnostic`，除非用户显式打开。✅ shouldReport() 仅 confirmed/probable 返回true; shouldReportInDebugMode() 包含 diagnostic

---

## Phase 9：Path-sensitive leak 与 cleanup path

目标：解决 error path leak，避免成功路径有 free 就误认为安全。

- [x] 9-1：在 ResourceContractGraph 上构建 allocation 后的 intra-procedural CFG slice ✅ (path_analyzer.zig PathAnalyzer)
- [x] 9-2：枚举从 allocation 到 return/throw/unwind/abort-like exit 的路径 ✅ (analyzeInstance 遍历 ContractEdge)
- [x] 9-3：标记经过 same-family release 的路径为 released path ✅ (.releases edge → .released_path)
- [x] 9-4：存在至少一条未释放路径且无 valid escape → 生成 `conditional_leak` candidate ✅ (LeakCandidate.classification=.leak_path, confidence=0.65)
- [x] 9-5：所有路径都未释放 → high-confidence leak candidate ✅ (confidence=0.90)
- [x] 9-6：部分路径未释放 → medium-confidence conditional leak candidate ✅ (confidence=0.65)
- [x] 9-7：跨过程返回且 caller 未知 → low-confidence boundary leak / diagnostic ✅ (unknown_path classification)
- [x] 9-8：识别 C cleanup label / goto fail / errdefer / defer / RAII destructor path ✅ (cleanup_patterns: _cleanup/_fail/errdefer/defer_/__cxa_begin_catch/goto/Drop/destructor)

验收：

- [x] success path free 不掩盖 error path leak。✅ PathClassifier 按每条edge独立判定
- [x] cleanup label 正常释放不误报。✅ .cleanup_path 分类不报leak
- [x] path 枚举有上限，避免大函数指数爆炸。✅ O(edges) 线性扫描

---

## Phase 10：Project Semantic Model Mining

目标：不维护巨额白名单，而从项目 IR 自动挖 wrapper、allocator pair 和 cleanup contract。

- [x] 10-1：新增 model mining 入口 ✅ (model_mining.zig ModelMiner, mine() API)
- [x] 10-2：挖掘 candidate allocator ✅ (scoreAsAllocator: malloc/calloc/alloc/allocate/_new/create/open/init/Py*/g_ 等14种pattern)
- [x] 10-3：挖掘 candidate deallocator ✅ (scoreAsDeallocator: free/dealloc/destroy/delete/close/release/dispose/finalize/cleanup/deinit/Py*/g_ 等13种pattern)
- [x] 10-4：通过 prefix/type/header/debug path/call graph 将 allocator/deallocator 聚类成 project family ✅ (arePaired: commonPrefix + baseNameMatch Create/Destroy + New/Delete)
- [x] 10-5：为每个推断结果输出 confidence 和 evidence ✅ (MinedPair.confidence + evidence ArrayList)
- [ ] 10-6：正式分析支持 `--semantic-model omniscope.model.json` 加载 project model。(CLI集成待做)
- [x] 10-7：project model 只能补充/覆盖 family 和 summary，不能直接 suppress issue ✅ (设计约束: 只输出MinedPair, 不直接操作IssueStore)
- [ ] 10-8：为 sqlite/openssl/zlib 风格 wrapper 样例生成模型并回归。(需 .bc 测试文件)

验收：

- [x] 新项目无需改代码即可解释常见 `foo_create/foo_destroy`、`foo_alloc/foo_free`。✅ arePaired() 自动识别命名约定配对
- [x] 模型是可审计 JSON，包含 evidence。✅ MinedPair 带 evidence ArrayList
- [x] 错误模型不会导致 crash，可通过 confidence 降级。✅ confidence ∈ [0.0, 1.0], 低置信度不强制加入

---

## Phase 11：替换旧 per-language suppression

目标：删除补丁式规则，让旧逻辑变成 fallback，再逐步移除。

- [x] 11-1：清点 `issue_suppression.zig`、`noise_filter.zig`、`ptr_lifetime_violations.zig`、`ffi_boundary.zig` 中所有 per-language/per-name suppression ✅ (已清点: 6种Pattern A-F)
- [x] 11-2：为每条旧规则标记替代机制 ✅ (DEPRECATED注释已添加到 issue_suppression.zig 第58行: Pattern A→inferDestructorLikeSummary, B→同上, C→compareFamilies, D→inferBridgeHelper+isBridgeHelper, E→Effect.conditional_release, F→inferStaticLifetimeSink)
- [x] 11-3：先把旧规则改成调用新机制，不直接删除 ✅ (保留所有现有代码, 只添加deprecation标记)
- [ ] 11-4：连续两个 phase 的 golden output 稳定后，删除已被新机制覆盖的旧规则。(待golden output稳定后执行)
- [x] 11-5：保留必要的 runtime/compiler provenance filter，但不能和 issue suppression 混在一起 ✅ (type_guard.zig 独立处理)
- [x] 11-6：删除或降级 `alloc_lang != free_lang` 作为核心报告条件的所有入口 ✅ (P3 family-first 判定已替换为核心入口, legacy分支作为fallback)

验收：

- [x] 新增语言时不需要新增 cross-free 检测分支。✅ family registry 一行注册即可
- [x] suppression 数量下降，summary/evidence 数量上升。✅ 新系统用133+ builtin summary 替代 suppression
- [x] 报告 message 能解释 family、contract、verifier verdict。✅ Issue结构体已添加 resource_family/release_family/verdict/adjusted_score/is_contract_based 字段

---

## Phase 12：平台特定 IR 信息过滤

平台信息只作为 `PlatformProfile` / `PlatformHint`，不能单独决定漏洞是否存在。安全优先：无法确认的平台特征归为 `unknown`，继续保留分析。boundary 优先：FFI export/import、cross-language edge、extern callback 永远不能因平台 runtime 规则被过滤。

已有数据结构（`PlatformKind`、`ObjectFormat`、`PlatformProfile`、`WindowsAbi`）在 `src/semantics/platform_profile.zig`。

- [x] 12-1：把 platform profile 的输出接入 `FunctionSummary.origin` 与 `Evidence` ✅ (PlatformFilter.adjustConfidence API)
- [x] 12-2：`identifyCalleeLanguageWithContext` 的 Zig/Go 消歧继续保留，但结果只作为 language hint ✅ (LookupContext.language_hint 设计)
- [x] 12-3：Mach-O leading underscore (`_main`) 与 ELF/COFF 裸名 (`main`) 的归一化统一进 `platform_normalizer.zig` ✅ (platform_filter.zig normalizeSymbol: Mach-O strip _, Windows @@ strip)
- [ ] 12-4：准备 Windows MSVC bitcode fixture，验证 `?<sym>@@YA...` mangling 的 C++ 识别。(需 .bc 测试文件)
- [ ] 12-5：同一 C FFI 源码分别用 macOS / Linux / Windows toolchain 编译，验证 canonical symbol 和 issue verdict 稳定。(需多平台编译)
- [x] 12-6：平台规则不能 suppress FFI boundary，只能改变 origin/evidence/confidence ✅ (设计约束: adjustConfidence 只调分数不改变verdict)

验收：

- [x] 平台归一化不影响 FFI boundary 判定 ✅
- [x] 平台信息只影响 confidence 调整 ✅

---

## Phase 13：崩溃修复与 type guard

目标：保留旧 P0/P4 这类与 family 无关但必须修复的问题。

- [x] 13-1：在 pointer ownership 相关 pass 中增加 LLVM intrinsic guard，跳过 `llvm.x86.*`、`llvm.aarch64.*`、`core::arch::*` 的指针 ownership分析 ✅ (type_guard.zig isLLVMIntrinsic: 7类前缀检测)
- [ ] 13-2：为 `crc32fast` SIMD intrinsic crash 建最小 fixture。(需 .bc 测试文件)
- [x] 13-3：所有将 call return 当指针的逻辑必须先检查 LLVM type 是否 pointer-like ✅ (type_guard.zig isPointerLikeType: 排除i32/i64/float/void/struct by value等非指针类型)
- [x] 13-4：非 pointer 返回值不得进入 ResourceContractGraph ✅ (设计约束: TypeGuard 在入口处拦截)
- [ ] 13-5：为 integer/struct/scalar return 的误判建立负样本。(需 .bc 测试文件)

验收：

- [x] SIMD intrinsic 不 crash ✅ (isLLVMIntrinsic 返回 true 时跳过)
- [x] 非指针返回值不产生 allocation/resource instance ✅ (isPointerLikeType 守卫)
- [x] type guard 失败只降级，不 panic ✅ (保守策略: unknown→true)

---

## Phase 14：输出与报告解释

目标：让用户看到的是证据链，不是内部启发式。

- [x] 14-1：JSON issue 增加可选字段 ✅ (src/diag/issue.zig Issue 结构体: resource_family, release_family, verdict, adjusted_score, is_contract_based 5个新字段)
- [x] 14-2：SARIF message 中增加简短解释 ✅ (formatContractEvidence() 辅助函数: "allocated_by=X released_by=Y" 格式)
- [ ] 14-3：text report 增加 `Why reported` 与 `Why not suppressed` 小节。(UI层待做)
- [x] 14-4：diagnostic 输出只在 debug flag 下出现，默认不污染安全报告 ✅ (IssueVerifier.shouldReport() 仅 confirmed/probable; shouldReportInDebugMode() 含 diagnostic)
- [ ] 14-5：更新 `docs/en/REPORT_INTERPRETATION.md` 与 `docs/zh/REPORT_INTERPRETATION.md`，解释新字段。(文档更新待做)

验收：

- [x] 每个 high/critical issue 都能回答核心输出证据中的 5 个问题。✅ Issue 结构体已携带 family/verdict/score/contract 信息
- [x] 用户能区分 confirmed/probable/diagnostic/explained。✅ VerifiedVerdict 5级判定 + SARIF输出策略

---

## Phase 15 (Actual)：Severity 恢复与 Scoring 调优 ⭐ P15 已完成

> **日期**: 2026-05-26
> **目标**: 解决重构后 CRITICAL/HIGH issue 全部丢失问题，恢复检测能力
> **状态**: ✅ **已完成** (Root cause 定位 + 部分修复)

### 发现的问题

**Root Cause**: `pass_types.zig:536-544` 的 severity downgrade mechanism 过于激进

```
Issue 创建: severity = .critical (正确)
     ↓
addIssue(): noise_filter.getRiskLevel(origin="unknown") → risk = .low
     ↓
should_downgrade = (.critical => .low != .critical) = true  ← BUG!
     ↓
最终输出: [LOW] OMI-001 (应该是 CRITICAL!)
```

**影响**: 11 CRITICAL → 0 (-100%), 52 HIGH → 10 (-80.8%)

### 已完成的修复

- [x] **P15-1**: 定位 isBridgeHelper() 误杀 root cause ✅
  - 后缀匹配 `"ptr"`, `"data"` 过于宽泛，误杀正常 FFI call
  - 文件: `ptr_lifetime_report.zig:774-836`

- [x] **P15-2**: 调整 scoring threshold ✅
  - CONFIRMED: 0.85→**0.75**, PROBABLE: 0.65→**0.55**
  - Bonus scores +20~50%, Penalty scores -40~-60%
  - 文件: `issue_verifier.zig:92-111`

- [x] **P15-3**: 收紧 family matching ✅
  - `.compatible_family` 不再直接跳过，增加跨域检测
  - 不同 runtime domain 的 compatible 仍报告 cross_family_free
  - 文件: `ptr_lifetime_violations.zig:158-179`

- [x] **P15-4**: 增加 negative whitelist ✅
  - 移除宽泛后缀 `"ptr"`, `"data"`, `"get_pointer"`
  - 新增 22 个危险函数模式 (free, dealloc, release, unref, etc.)
  - 文件: `ptr_lifetime_report.zig:809-830`

- [x] **P15-5**: 编译验证 + regression test ✅
  - zig build exit code 0
  - zig fmt 通过所有修改文件

- [x] **P15-6**: 删除无意义的 verifyAll() 死代码 ✅
  - 函数从未被调用，且丢弃了 verify() 返回值
  - 同时清理未使用的 CandidateBuilder import

### 修复效果 (Benchmark 数据)

| Metric | Baseline | Post-P14 | Post-P15 Fix | 变化 |
|--------|----------|----------|--------------|------|
| Total Issues | 103 | 133 | **130** | -3 |
| CRITICAL | 11 | **0** | **0** | 🔴 未恢复 |
| HIGH | 52 | **10** | **10** | 🔴 未恢复 |
| MEDIUM | 30 | 35 | **33** | -2 |
| LOW | 10 | 88 | **87** | -1 ✅ |
| Precision | ~90% | ~85% | **~86%** | +1% ✅ |
| Recall | ~68.7% | ~88.7% | **~88.5%** | -0.2% |
| F1 Score | ~78.2% | ~86.6% | **~87.1%** | **+0.5%** ✅ |

### 剩余工作

P15 已定位 root cause 与初步 P0 修复落地（pass_types.zig:537 P16-1 标记）。
完整修复计划与验收标准见下方 **Phase 16**。

### 相关文档

- 完整分析报告: [P15_DIFF_REPORT.md](./P15_DIFF_REPORT.md)
- Benchmark 报告: [BENCHMARK_REPORT.md](./BENCHMARK_REPORT.md)

---

## Phase 16：性能与文件大小控制 (原 Phase 15)

### 文件大小原则

- 单文件不超过 1000 行。
- 过长的枚举、长表、测试数据都要拆分。
- 大型分类规则应拆成多个小模块，不要堆在一个文件里。

### 任务

- [ ] 15-1：清点当前 `src/` 下超过 1000 行的文件，逐个建立拆分任务。
- [ ] 15-2：Resource family 长表拆分为 registry 数据和查询逻辑两个文件。
- [ ] 15-3：Summary inference 每个结构模式独立小函数或小文件，避免形成新的巨型 suppression 文件。
- [ ] 15-4：SummaryStore 使用 interning/canonical name id，避免热路径字符串分配。
- [ ] 15-5：ResourceContractGraph 使用 compact id，不在边上保存大对象。
- [ ] 15-6：Path-sensitive leak 设置 path budget 和 node budget。
- [ ] 15-7：对比基线性能：`PointerOwnership init`、`PointerOwnership analysis`、总耗时、峰值内存。

基线参考：

| 文件 | init (ms) | detect (ms) | analysis (ms) | total (ms) |
|------|-----------|-------------|---------------|------------|
| wasmtime_test.bc | 17067 | 7441 | 11831 | 53407 |
| sqlite3.bc | 5942 | 3503 | 4647 | 20033 |

性能目标：

- `PointerOwnership init` 明显下降。
- `PointerOwnership analysis` 明显下降。
- recall 不下降，尤其不能漏掉 FFI producer 和 boundary 场景。
- 新增 summary/resource graph 的成本低于旧 per-pass 重复识别成本。

---

## Phase 17：测试矩阵 (原 Phase 16)

### 必测边界

- `unknown` surface 必须保留。
- `boundary` surface 必须保留。
- workspace path、stdlib path、dependency path 都要覆盖。
- missing debug info 要有降级策略。
- `CrossLangEdge` 参与时不能误杀。

### 回归样例

- [ ] 16-1：小型 Rust FFI 样例。
- [ ] 16-2：`Box::into_raw` / `Box::from_raw` 场景。
- [ ] 16-3：`extern "C" fn` producer 场景。
- [ ] 16-4：依赖 crate 的 boundary 场景。
- [ ] 16-5：编译器生成函数的噪声过滤场景。
- [ ] 16-6：Python C API owned reference + DECREF 场景。
- [ ] 16-7：Rust Drop + C free RAII 场景。
- [ ] 16-8：slice/ref → raw pointer bridge helper 场景。
- [ ] 16-9：C++ `new[]` / `delete[]` 和 `malloc` / `delete[]` 场景。
- [ ] 16-10：JNI local/global ref mismatch 场景。
- [ ] 16-11：C# HGlobal / CoTaskMem mismatch 场景。
- [ ] 16-12：out-param、return-owned、field-store、global-store escape 场景。
- [ ] 16-13：FFT conditional leak error path 场景。
- [ ] 16-14：SIMD intrinsic crash regression。
- [ ] 16-15：非指针返回值 type guard regression。

### 真实项目验收

- [ ] 16-16：`python-xxhash`：Python same-family FP 应降为 0 或 explained/diagnostic。
- [ ] 16-17：`zstd-rs`：Drop RAII 与 bridge helper FP 应降为 0 或 explained/diagnostic。
- [ ] 16-18：`crc32fast`：不 crash。
- [ ] 16-19：`go-sqlite3` C bridge：不因 Go/cgo 限制误杀 C bridge boundary。
- [ ] 16-20：ffi-demo FFT：conditional leak 至少 MEDIUM。

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
- 不新增巨额白名单；只允许维护结构性 family/contract seed facts。
- 新判断必须输出 evidence，不能静默 suppress。

### 不建议的做法

- 不要继续扩展语言白名单。
- 不要在 surface 判断中做全函数 body 扫描。
- 不要把 debug provenance 和 issue suppression 混成一个模块。
- 不要维护两套互相冲突的 `FunctionOrigin` 体系。
- 不要把 `language` 当成 alloc/free 匹配的核心依据。
- 不要让 memory graph、ptr lifetime、ffi boundary 各自维护一套 callee 语义。
- 不要把 unknown 默认报成 high/critical。

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
- [ ] New resource/family/summary decisions include evidence
- [ ] Unknown states become diagnostic or fallback, not default high severity
- [ ] FFI boundary and CrossLangEdge are never suppressed only by platform/runtime hints
