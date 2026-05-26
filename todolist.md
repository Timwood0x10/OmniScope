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

- [ ] 4-1：新增 `src/semantics/resource/effect.zig`。
- [ ] 4-2：定义 `Effect` union：`acquires`、`releases`、`retains`、`returns_owned`、`returns_borrowed`、`consumes_arg`、`stores_arg_to_owner`、`stores_arg_to_global`、`initializes_out_param`、`escapes_to_callback`、`conditional_release`。
- [ ] 4-3：新增 `src/semantics/resource/function_summary.zig`。
- [ ] 4-4：定义 `FunctionSummary`：function id、canonical name、origin、language hint、runtime hint、effects、confidence、evidence。
- [ ] 4-5：定义 `SummarySource`：`builtin_registry`、`structural_inference`、`project_model`、`fallback_heuristic`、`unknown`。
- [ ] 4-6：定义 `SummaryConfidence` 或使用 `f32 confidence`，但所有阈值集中在一个文件。

### 4.2 内置 summary

- [ ] 4-7：从 family registry 自动生成 builtin allocator/releaser summary。
- [ ] 4-8：为 Python owned-reference constructors 生成 `returns_owned(python_object)` summary：`PyLong_From*`、`PyUnicode_From*`、`PyTuple_New`、`PyList_New`、`PyDict_New`、`PyBytes_FromString*`。
- [ ] 4-9：为 `Py_DECREF` / `Py_XDECREF` 生成 `conditional_release(python_object)` summary。
- [ ] 4-10：为 JNI ref API 生成 local/global ref acquire/release summary。
- [ ] 4-11：为 C# HGlobal/CoTaskMem 生成 acquire/release summary。

### 4.3 Summary 查询接入

- [ ] 4-12：新增 `SummaryStore`，按 function id 和 canonical name 查询。
- [ ] 4-13：在 pass context 中挂载 `SummaryStore`，保证 heavy pass 共享。
- [ ] 4-14：`memory_graph` 创建 alloc/free/retain 节点时优先读取 summary。
- [ ] 4-15：`ptr_lifetime` 判断 release/transfer/escape 时优先读取 summary。
- [ ] 4-16：`ffi_boundary` 判断 boundary effect 时优先读取 summary。
- [ ] 4-17：旧 callee-name 判断保留为 fallback，并标记 evidence。

验收：

- [ ] 同一个函数在不同 pass 中得到相同 summary。
- [ ] summary 缺失不会 crash，不会默认高危报告。
- [ ] Python owned reference + DECREF 不再依赖 per-pass 特判。

---

## Phase 5：结构模式推断替代 suppression

目标：融合 `./improve.md` 的 5 个通用模式，但放在 summary inference 层，而不是 issue suppression 层。

### 5.1 Destructor / Drop / Dispose 模式

- [ ] 5-1：新增 `src/semantics/resource/summary_inference.zig` 中的 `inferDestructorLikeSummary`。
- [ ] 5-2：匹配名称/debug 标记：`drop`、`destroy`、`dealloc`、`delete`、`free`、`Dispose`、`finalize`、`__del__`、C++ destructor mangling `D0Ev/D1Ev/D2Ev`。
- [ ] 5-3：检查函数参数或 implicit this 是否 pointer-like。
- [ ] 5-4：检查函数体是否调用已知 release summary，或释放对象字段。
- [ ] 5-5：生成 `consumes_arg` + `releases` / `releases_fields` effect。
- [ ] 5-6：Rust Drop 调 C free 通过该 summary 解释为 RAII release，不再写 Rust 专用 suppression。
- [ ] 5-7：新增 zstd-rs Drop fixture，确认标准 RAII 不报 UAF。

### 5.2 Slice-to-ptr bridge 模式

- [ ] 5-8：实现 `inferBridgeHelperSummary`。
- [ ] 5-9：匹配函数体只包含 `getelementptr`、`bitcast`、`extractvalue`、`addrspacecast`、return，无 alloc/free/store-global。
- [ ] 5-10：匹配签名形态：slice/ref/array-like 输入 → raw pointer 输出。
- [ ] 5-11：生成 `returns_borrowed` + `bridge_helper` evidence。
- [ ] 5-12：zstd-rs `as_ptr` / `as_mut_ptr` / `ptr_mut_void` 不再报 borrow_escape。

### 5.3 Refcount release 模式

- [ ] 5-13：实现 `inferRefcountReleaseSummary`。
- [ ] 5-14：识别 atomic decrement + conditional release IR shape。
- [ ] 5-15：识别 `Py_DECREF`、`Py_XDECREF`、`Arc::drop`、`CFRelease`、`IUnknown::Release`、`objc_release` 形态。
- [ ] 5-16：生成 `conditional_release`，不要误建模为 unconditional free。
- [ ] 5-17：新增 Python/Cocoa/COM 风格最小 fixture。

### 5.4 Static lifetime sink 模式

- [ ] 5-18：实现 `inferStaticLifetimeSink`。
- [ ] 5-19：识别资源只初始化一次并存入 global/static 的场景。
- [ ] 5-20：生成 `escape_kind = static_lifetime` 与 `lifetime_domain = process_static`。
- [ ] 5-21：如果 allocation 在循环或多次路径发生，不允许 static-lifetime 降级。
- [ ] 5-22：C++ static `new[]` fixture 降级为 explained/diagnostic，不报普通 leak。

### 5.5 Same-family release 模式

- [ ] 5-23：把 same-family release 作为 `valid_release` evidence，而不是 suppression。
- [ ] 5-24：所有 issue message 增加 family evidence：`allocated_by=c_heap released_by=c_heap` 或 `allocated_by=rust_global released_by=c_heap`。

验收：

- [ ] 旧 suppression 数量下降。
- [ ] 新结构模式每个文件不超过 100 行核心判断或拆分为小函数。
- [ ] 每个模式都有正/负样本。

---

## Phase 6：PointerContract 与 EscapeKind

目标：让 leak / borrow_escape / callback_escape 不再把合法 escape 当成 bug。

- [ ] 6-1：新增 `src/semantics/resource/contract.zig`。
- [ ] 6-2：定义 `PointerContract`：`owned`、`borrowed`、`maybe_owned`、`transferred`、`retained`、`released`、`invalid`、`unknown`。
- [ ] 6-3：新增 `src/semantics/resource/escape.zig`。
- [ ] 6-4：定义 `EscapeKind`：`return_to_caller`、`out_param`、`field_store`、`global_store`、`callback`、`thread`、`container`、`static_lifetime`、`unknown`。
- [ ] 6-5：MemoryGraph/ResourceGraph 对每个 resource instance 记录 escape list。
- [ ] 6-6：return pointer 生成 `return_to_caller` escape。
- [ ] 6-7：写入 `T** out` 或 `*out = ptr` 生成 `out_param` escape。
- [ ] 6-8：写入 `ctx->field = ptr` 生成 `field_store` escape。
- [ ] 6-9：写入 global/static 生成 `global_store` 或 `static_lifetime` escape。
- [ ] 6-10：传给 register/callback-like API 生成 `callback` escape。
- [ ] 6-11：传给 thread/spawn-like API 生成 `thread` escape。
- [ ] 6-12：leak detector 从 `alloc && !free` 改为 `owned && !released && !valid_escape && !valid_transfer`。
- [ ] 6-13：borrow_escape 报告前检查 bridge helper、temporary borrow、return borrowed summary。

验收：

- [ ] return-owned 不报当前函数 leak。
- [ ] out-param 初始化不报当前函数 leak。
- [ ] field-store 到 owner object 不报当前函数 leak，但 owner destructor 缺失可产生 lower-confidence candidate。
- [ ] callback/global/thread escape 仍保留为 FFI lifetime 风险。

---

## Phase 7：Resource Contract Graph 与 Ownership Solver

目标：用统一状态机替代分散在多个 pass 里的生命周期判断。

### 7.1 ResourceContractGraph

- [ ] 7-1：新增 `src/pass/analysis/resource/contract_graph_builder.zig`。
- [ ] 7-2：定义 `ResourceInstance`：id、family、allocation site、state、owner、escape list、evidence。
- [ ] 7-3：定义 `ContractEdge`：from、to、effect、instruction、confidence。
- [ ] 7-4：从 Raw Fact + FunctionSummary 构建 resource instance。
- [ ] 7-5：为 acquire/release/retain/transfer/escape 建 edge。
- [ ] 7-6：与现有 CrossLangEdge 建关联：resource edge 可标记 `on_ffi_path` 和 `boundary_distance`。

### 7.2 Ownership State Solver

- [ ] 7-7：新增 `src/semantics/resource/ownership_state.zig`。
- [ ] 7-8：定义状态：`unknown`、`owned`、`borrowed`、`retained`、`transferred`、`returned`、`stored_in_owner`、`escaped`、`released`、`invalid`、`leak_candidate`。
- [ ] 7-9：实现状态转移表，不在各 pass 中手写状态 if/else。
- [ ] 7-10：处理 same-family release：`owned -> released`。
- [ ] 7-11：处理 mismatch release：生成 candidate，不立即报告。
- [ ] 7-12：处理 use-after-release：`released -> use` 生成 candidate。
- [ ] 7-13：处理 valid escape：`owned -> returned/stored/transferred/escaped`。
- [ ] 7-14：处理 refcount：`retained` / `conditional_release` 不等价于普通 free。

验收：

- [ ] 同一个 allocation 在 graph 中只有一个 primary resource instance。
- [ ] alias/bitcast/gep 不导致重复 resource。
- [ ] 状态转移可 trace。
- [ ] solver 不直接输出 SARIF issue。

---

## Phase 8：Issue Candidate Builder 与 Verifier

目标：所有问题二阶段确认，彻底减少 pattern-match 直接报告。

### 8.1 Candidate Builder

- [ ] 8-1：新增 `src/pass/analysis/resource/issue_candidate_builder.zig`。
- [ ] 8-2：定义 `IssueCandidate`：kind、resource、path、raw score、evidence、reason。
- [ ] 8-3：生成 `cross_family_free` candidate。
- [ ] 8-4：生成 `use_after_release` candidate。
- [ ] 8-5：生成 `conditional_leak` candidate。
- [ ] 8-6：生成 `borrow_escape` / `callback_escape` candidate。
- [ ] 8-7：生成 `needs_model` diagnostic candidate，用于 unknown family / unknown cleanup。

### 8.2 Verifier

- [ ] 8-8：新增 `src/pass/analysis/resource/issue_verifier.zig`。
- [ ] 8-9：定义 `VerifiedVerdict`：`confirmed_issue`、`probable_issue`、`diagnostic`、`explained_safe`。
- [ ] 8-10：实现 family verifier：same/compatible family 解释为 safe，mismatch 保留。
- [ ] 8-11：实现 escape verifier：return/out-param/field-store/static-lifetime 合法逃逸降级。
- [ ] 8-12：实现 destructor verifier：存在 destructor/drop/cleanup release path 时解释或降级。
- [ ] 8-13：实现 path verifier：有 concrete free-before-use path 才确认 UAF。
- [ ] 8-14：实现 FFI priority verifier：不在 FFI danger path 的 issue 降权；boundary/callback/cross-runtime issue 升权。
- [ ] 8-15：实现 unknown policy：unknown 不默认 high/critical，进入 diagnostic 或 `needs_model`。
- [ ] 8-16：默认 SARIF/JSON 只输出 `confirmed_issue` 和 high-confidence `probable_issue`；diagnostic 需要 debug flag。

### 8.3 Scoring

- [ ] 8-17：集中定义 risk score 参数。
- [ ] 8-18：加分项：concrete path、family mismatch、ownership violation、FFI boundary、cross-runtime、use-after-release。
- [ ] 8-19：减分项：valid escape、valid destructor、same family、runtime internal、unknown evidence。
- [ ] 8-20：阈值建议：`>=0.85 confirmed`，`>=0.65 probable`，`>=0.40 diagnostic`，其余 explained。

验收：

- [ ] 旧直接 report 入口逐步改为 candidate。
- [ ] 每个最终 issue 都有 verifier verdict。
- [ ] SARIF 不输出 `diagnostic`，除非用户显式打开。

---

## Phase 9：Path-sensitive leak 与 cleanup path

目标：解决 error path leak，避免成功路径有 free 就误认为安全。

- [ ] 9-1：在 ResourceContractGraph 上构建 allocation 后的 intra-procedural CFG slice。
- [ ] 9-2：枚举从 allocation 到 return/throw/unwind/abort-like exit 的路径。
- [ ] 9-3：标记经过 same-family release 的路径为 released path。
- [ ] 9-4：存在至少一条未释放路径且无 valid escape → 生成 `conditional_leak` candidate。
- [ ] 9-5：所有路径都未释放 → high-confidence leak candidate。
- [ ] 9-6：部分路径未释放 → medium-confidence conditional leak candidate。
- [ ] 9-7：跨过程返回且 caller 未知 → low-confidence boundary leak / diagnostic。
- [ ] 9-8：识别 C cleanup label / goto fail / errdefer / defer / RAII destructor path。
- [ ] 9-9：回归 ffi-demo FFT-LEAK-2 / FFT-LEAK-3。

验收：

- [ ] success path free 不掩盖 error path leak。
- [ ] cleanup label 正常释放不误报。
- [ ] path 枚举有上限，避免大函数指数爆炸。

---

## Phase 10：Project Semantic Model Mining

目标：不维护巨额白名单，而从项目 IR 自动挖 wrapper、allocator pair 和 cleanup contract。

- [ ] 10-1：新增 model mining 入口，命令形态暂定：`OmniScope target.bc --mine-model > omniscope.model.json`。
- [ ] 10-2：挖掘 candidate allocator：返回 pointer、名称含 `alloc/new/create/open/init`、或 body 调用已知 acquire。
- [ ] 10-3：挖掘 candidate deallocator：参数为 pointer、名称含 `free/delete/destroy/close/deinit/release`、或 body 调用已知 release。
- [ ] 10-4：通过 prefix/type/header/debug path/call graph 将 allocator/deallocator 聚类成 project family。
- [ ] 10-5：为每个推断结果输出 confidence 和 evidence，不能静默加入模型。
- [ ] 10-6：正式分析支持 `--semantic-model omniscope.model.json` 加载 project model。
- [ ] 10-7：project model 只能补充/覆盖 family 和 summary，不能直接 suppress issue。
- [ ] 10-8：为 sqlite/openssl/zlib 风格 wrapper 样例生成模型并回归。

验收：

- [ ] 新项目无需改代码即可解释常见 `foo_create/foo_destroy`、`foo_alloc/foo_free`。
- [ ] 模型是可审计 JSON，包含 evidence。
- [ ] 错误模型不会导致 crash，可通过 confidence 降级。

---

## Phase 11：替换旧 per-language suppression

目标：删除补丁式规则，让旧逻辑变成 fallback，再逐步移除。

- [ ] 11-1：清点 `issue_suppression.zig`、`noise_filter.zig`、`ptr_lifetime_violations.zig`、`ffi_boundary.zig` 中所有 per-language/per-name suppression。
- [ ] 11-2：为每条旧规则标记替代机制：family registry、summary inference、escape verifier、destructor verifier、path verifier、platform profile。
- [ ] 11-3：先把旧规则改成调用新机制，不直接删除。
- [ ] 11-4：连续两个 phase 的 golden output 稳定后，删除已被新机制覆盖的旧规则。
- [ ] 11-5：保留必要的 runtime/compiler provenance filter，但不能和 issue suppression 混在一起。
- [ ] 11-6：删除或降级 `alloc_lang != free_lang` 作为核心报告条件的所有入口。

验收：

- [ ] 新增语言时不需要新增 cross-free 检测分支。
- [ ] suppression 数量下降，summary/evidence 数量上升。
- [ ] 报告 message 能解释 family、contract、verifier verdict。

---

## Phase 12：平台特定 IR 信息过滤

平台信息只作为 `PlatformProfile` / `PlatformHint`，不能单独决定漏洞是否存在。安全优先：无法确认的平台特征归为 `unknown`，继续保留分析。boundary 优先：FFI export/import、cross-language edge、extern callback 永远不能因平台 runtime 规则被过滤。

已有数据结构（`PlatformKind`、`ObjectFormat`、`PlatformProfile`、`WindowsAbi`）在 `src/semantics/platform_profile.zig`。

- [ ] 12-1：把 platform profile 的输出接入 `FunctionSummary.origin` 与 `Evidence`。
- [ ] 12-2：`identifyCalleeLanguageWithContext` 的 Zig/Go 消歧继续保留，但结果只作为 language hint。
- [ ] 12-3：Mach-O leading underscore (`_main`) 与 ELF/COFF 裸名 (`main`) 的归一化统一进 `platform_normalizer.zig`。
- [ ] 12-4：准备 Windows MSVC bitcode fixture，验证 `?<sym>@@YA...` mangling 的 C++ 识别。
- [ ] 12-5：同一 C FFI 源码分别用 macOS / Linux / Windows toolchain 编译，验证 canonical symbol 和 issue verdict 稳定。
- [ ] 12-6：平台规则不能 suppress FFI boundary，只能改变 origin/evidence/confidence。

---

## Phase 13：崩溃修复与 type guard

目标：保留旧 P0/P4 这类与 family 无关但必须修复的问题。

- [ ] 13-1：在 pointer ownership 相关 pass 中增加 LLVM intrinsic guard，跳过 `llvm.x86.*`、`llvm.aarch64.*`、`core::arch::*` 的指针 ownership 分析。
- [ ] 13-2：为 `crc32fast` SIMD intrinsic crash 建最小 fixture。
- [ ] 13-3：所有将 call return 当 pointer 的逻辑必须先检查 LLVM type 是否 pointer-like。
- [ ] 13-4：非 pointer 返回值不得进入 ResourceContractGraph。
- [ ] 13-5：为 integer/struct/scalar return 的误判建立负样本。

验收：

- [ ] SIMD intrinsic 不 crash。
- [ ] 非指针返回值不产生 allocation/resource instance。
- [ ] type guard 失败只降级，不 panic。

---

## Phase 14：输出与报告解释

目标：让用户看到的是证据链，不是内部启发式。

- [ ] 14-1：JSON issue 增加可选字段：`resource_family`、`release_family`、`pointer_contract`、`escape_kind`、`verdict`、`verifier_evidence`。
- [ ] 14-2：SARIF message 中增加简短解释：allocated by X, released by Y, contract Z, verdict V。
- [ ] 14-3：text report 增加 `Why reported` 与 `Why not suppressed` 小节。
- [ ] 14-4：diagnostic 输出只在 debug flag 下出现，默认不污染安全报告。
- [ ] 14-5：更新 `docs/en/REPORT_INTERPRETATION.md` 与 `docs/zh/REPORT_INTERPRETATION.md`，解释新字段。

验收：

- [ ] 每个 high/critical issue 都能回答核心输出证据中的 5 个问题。
- [ ] 用户能区分 confirmed/probable/diagnostic/explained。

---

## Phase 15：性能与文件大小控制

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

## Phase 16：测试矩阵

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
