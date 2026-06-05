# OmniScope 准确率提升路线图

> 基于 codegraph 索引 + grep 精准定位，2026-06-05

---

## 一、僵尸 Pass（已定义但从未注册）

以下 pass 有完整的 `pub const name` 和 `pub fn run` 定义，但 **main.zig 中没有 `registerPass` 调用**。它们占用编译时间、混淆代码结构，但对分析结果零贡献。

| Pass 名称 | 文件 | 状态 | 建议 |
|-----------|------|------|------|
| `callback-lifecycle` | `src/pass/analysis/ffi/callback_lifecycle_checker.zig` | 907 行，有真实逻辑 | **激活** — 与已有 `callback-escape` 互补，检测 JS/Go 回调生命周期错误 |
| `abi-compat-checker` | `src/pass/analysis/ffi/abi_compat_checker.zig` | 958 行，有真实逻辑 | **激活** — 直接提升 ABI 类型不匹配检测；abi-mismatch 被注释掉了恰好能补位 |
| `ffi-detector` | `src/pass/analysis/ffi/ffi_detector.zig` | 728 行，消费 taint facts | **激活** — 是 taint 结果唯一消费者之一，不跑就浪费了 `pointer-flow` 的所有计算 |
| `ownership-violation` | `src/pass/analysis/ffi/ffi_analysis.zig` | 742 行，有完整 FFIMatcher 逻辑 | **激活** — 独立 FFI 匹配路径，不与其他 pass 重叠 |
| `dfg` | `src/pass/foundation/dfg.zig` | foundation pass | **激活** — 若 `ffi_body_check` 依赖 DataFlowGraph，dfg 应该在它之前运行 |
| `instrumentation-planner` | `src/pass/instrumentation/planner.zig` | 规划器 | 低优先级，可延后 |
| `abi-mismatch` | `src/pass/analysis/abi_mismatch.zig` | 已注释 | 与 `abi-compat-checker` 合并后再激活 |
| `thread-crossing` | `src/pass/analysis/thread_crossing.zig` | 已注释 | 依赖 memory_graph，可在 memory_graph 稳定后激活 |

**激活方式** (main.zig 约第 60 行后插入):
```zig
try pipeline.registerPass(OmniScope.cross_lang.FFIDetectorPass);
try pipeline.registerPass(OmniScope.cross_lang.FFIAnalysisPass);        // ownership-violation
try pipeline.registerPass(OmniScope.cross_lang.AbiCompatCheckerPass);
try pipeline.registerPass(OmniScope.cross_lang.CallbackLifecyclePass);
```

---

## 二、Stub Pass（已注册但实际什么都不做）

| Pass 名称 | 文件 | 证据 | 影响 |
|-----------|------|------|------|
| `lock` (内部 FreeingLockPass) | `src/pass/analysis/lock.zig:335-337` | `_ = ctx; _ = diag; return;` | **无输出** — 注册了，跑了，0 findings，浪费调度开销 |
| `pointer-flow` (taint 结果丢失) | `src/pass/analysis/taint/taint_propagation.zig` | 结果存入 `fact_store`，但只有 `ffi-detector`（未注册）读取 | **taint 计算白做** — 跑了 1000 行传播逻辑，下游没人消费 |

### Lock Pass 内层 Stub 定位

```
src/pass/analysis/lock.zig:335
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        _ = ctx;   // ← stub
        _ = diag;
```

外层 `LockPass.run()` (line 77) 是真实实现，做了锁顺序分析和死锁检测。**内层结构体 stub 不影响外层**，可以删掉内层或合并。

---

## 三、基础设施断线问题（已有能力但未接入）

### 3.1 `SemanticResolver` 结果 → 分析 pass 的单向盲区

**现状**: `SemanticResolver` 调用 `heap_provenance`、`into_raw_transfer`、`library_alloc_pairs` 三个 detector，结果存入 `ctx.semantic_resolution` (`ResolutionEngine`)。

**消费者**: 只有 `pointer_ownership`、`rust_ffi_auditor`、`rust_ffi_rules_basic/advanced`、`ffi_body_check`、`cpp_fp_reduction` 读取。

**断线**: `free_validation` 和 `ffi_unsafe` **完全不查询 `ctx.semantic_resolution`**。
- `library_alloc_pairs` 里有 SQLite、OpenSSL、zlib、mimalloc、JNI、Python CFFI 的 acquire/release 对照表（`src/semantics/patterns/library_alloc_pairs.zig`）
- `free_validation` 的 `trackPointerOrigin()` 不查这张表 → `sqlite3_open` 之类的分配无法被追踪 → cross-lang 检测对库资源永远 miss

**修复位置**: `src/pass/analysis/issue/free_validation.zig` → `trackPointerOrigin()` 内 `isAllocFunction()` 调用前，插入：
```zig
// 查询 SemanticResolver 结论：库级分配函数
if (ctx.semantic_resolution) |engine| {
    const srt = engine.getSemanticTree();
    if (srt.classifyFunction(callee_name) == .library_alloc) {
        // 记录为 from_library_alloc origin
    }
}
```

### 3.2 `TaintPropagation` 结果未被消费

**现状**: `pointer-flow` pass 跑完后把 taint facts 写入 `ctx.fact_store`（key=`.taint`）。

**唯一消费者**: `ffi_detector`（未注册的僵尸 pass）在 line 597 读取。

**断线**: `ffi_unsafe` 不查 taint facts。如果一个 `system()` 的参数来自 FFI 输入（tainted），它的危险程度应该高于普通调用，但 `ffi_unsafe` 对此无感知 → 漏报高危 + 误报低危无法区分。

**修复**: 激活 `ffi-detector` 或在 `ffi_unsafe.calculateConfidence()` 中查询 taint facts 上调置信度。

### 3.3 `language_overrides` 覆盖面不足

**现状**: 只有两个 pass 查询 `ctx.language_overrides`：
- `ffi_unsafe.zig:181`（刚修复的 skip 逻辑）
- `danger_surface.zig`（用于过滤）

**断线**: `free_validation`、`jni_leak_detector`、`ffi_body_check` 都不查 language_overrides。用户设置 `--lang-prefix "Java_" java` 后，`jni_leak_detector` 仍然对所有函数一视同仁。

### 3.4 PHI 节点追踪缺失

**现状**: `trackPointerOrigin()` 追踪了 Load、GEP、BitCast（`free_validation.zig:257-291`），**但没有 PHI 处理**。

```
// LLVMPHI 没有出现在 switch 分支里
```

**影响**: 常见于 if/else 分支分配路径：
```c
ptr = cond ? rust_alloc() : malloc();
// PHI node merges both. trackPointerOrigin misses the rust_alloc branch
free(ptr);  // cross-lang miss
```

**修复位置**: `free_validation.zig` `trackPointerOrigin()` 的 switch 中加 `c.LLVMPHI` 分支，遍历所有 incoming values，合并 origin（选最高风险 family）。

---

## 四、可复用但孤立的模块

| 模块 | 路径 | 已实现内容 | 谁该用但没用 |
|------|------|-----------|------------|
| `library_alloc_pairs` | `src/semantics/patterns/library_alloc_pairs.zig` | SQLite/OpenSSL/zlib/mimalloc/JNI/Python/Go 分配对表 | `free_validation.trackPointerOrigin()` |
| `allocator_kb` | `src/semantics/allocator_kb.zig` | 可扩展分配函数知识库 | `cross_lang_free_detector.classifyAllocatorFamily()` |
| `into_raw_transfer` | `src/semantics/patterns/into_raw_transfer.zig` | Rust Box::into_raw/from_raw 配对检测 | `free_validation` 的 intentional-transfer 判断（当前已从 detectCrossLanguageFree 移走，但新的 caller 函数名检测不如这个精确）|
| `rust_drop_semantics` | `src/semantics/rust_drop_semantics.zig` | Rust drop glue / 隐式 drop 识别 | `cross_lang_free_detector`（目前只在 `free_validation.isFreeSafe` 里用） |
| `zone_lang_*` detectors | `src/semantics/zone_lang_rust/cpp/go/zig.zig` | 按 zone 识别语言边界 | `cross_lang_free_detector.classifyAllocatorFamily()` 可用这些替代手写 pattern list |
| `noise_filter` | `src/semantics/noise_filter.zig` | 函数分类白名单 | `jni_leak_detector`（未使用，导致对系统函数误报）|

---

## 五、优先级矩阵

| 优先级 | 改动 | 收益 | 成本 | 文件 |
|--------|------|------|------|------|
| 🔴 P0 | 激活 `ffi-detector` pass | taint 计算结果终于被消费；`pointer-flow` 不再白跑 | 1 行 main.zig | main.zig:67 后 |
| 🔴 P0 | `trackPointerOrigin` 接入 `library_alloc_pairs` | SQLite/OpenSSL/zlib 分配可被追踪 → cross-lang FN 大幅下降 | ~30 行 | free_validation.zig |
| 🔴 P0 | 激活 `abi-compat-checker` | ABI 类型不匹配（int32/int64 混用）直接报出 | 1 行 main.zig | main.zig |
| 🟠 P1 | PHI 节点追踪 | 消除条件分配路径的所有 cross-lang miss | ~20 行 | free_validation.zig:trackPointerOrigin |
| 🟠 P1 | 激活 `ownership-violation` | 独立 FFIMatch 路径，捕获 ptr 逃逸到错误语言 | 1 行 main.zig | main.zig |
| 🟠 P1 | 激活 `callback-lifecycle` | JS/Go/Python 回调释放时机错误 | 1 行 main.zig | main.zig |
| 🟡 P2 | `ffi_unsafe` 接入 taint facts | 区分 tainted 参数与静态常量，置信度分层 | ~15 行 | ffi_unsafe.zig:calculateConfidence |
| 🟡 P2 | `language_overrides` 接入 `jni_leak_detector`/`ffi_body_check` | --lang-prefix 规则对 JNI 生效 | ~10 行/pass | jni_leak_detector.zig, ffi_body_check.zig |
| 🟡 P2 | `cross_lang_free_detector` 接入 `allocator_kb` | 用户自定义分配函数被正确分类 | ~10 行 | cross_lang_free_detector.zig:classifyAllocatorFamily |
| 🟢 P3 | 删除 `lock.zig` 内层 stub | 消除死代码噪音 | 3 行 | lock.zig:335-338 |
| 🟢 P3 | 激活 `thread-crossing` | 线程边界 ptr 传递检测 | 1 行 main.zig | main.zig |

---

## 六、建议执行顺序

```
Week 1 (P0):
  1. main.zig: registerPass(FFIDetectorPass)          # 激活 taint 消费者
  2. main.zig: registerPass(AbiCompatCheckerPass)     # 零成本激活
  3. free_validation.zig: library_alloc_pairs 接入    # 最大 recall 提升

Week 2 (P1):
  4. free_validation.zig: PHI 节点追踪
  5. main.zig: registerPass(FFIAnalysisPass)          # ownership-violation
  6. main.zig: registerPass(CallbackLifecyclePass)

Week 3 (P2):
  7. ffi_unsafe.zig: taint facts 置信度上调
  8. jni_leak_detector.zig + ffi_body_check.zig: language_overrides 接入
  9. cross_lang_free_detector.zig: allocator_kb 接入
```

---

## 附：Pass 注册全景图

```
已注册 (26个):
  Foundation:  cfg, dfg*                           (* dfg 实际未注册，应补上)
  Semantic:    surface-classifier, SemanticResolver, call-graph
  Taint:       pointer-flow (taint_propagation)
  FFI:         ffi-boundary, ffi-type-mismatch, ffi-body-check, cross-lang-dataflow
  Issues:      malloc-check, buffer-overflow, integer-overflow, return-check
               ffi-unsafe, free-validation, memory-safety, jni-leak-detector
  Lifetime:    ptr-lifetime, danger-surface
  Ownership:   pointer-ownership
  Lang:        rust-ffi-filter, callback-escape
  Optional:    gc-safety, error-propagation-tracer, lock

僵尸 (7个，零输出):
  ffi-detector, ownership-violation, abi-compat-checker,
  callback-lifecycle, instrumentation-planner,
  [abi-mismatch], [thread-crossing]   (后两个已注释)

Stub (1个，已注册但无输出):
  lock.zig 内层 FreeingLockPass struct
```
