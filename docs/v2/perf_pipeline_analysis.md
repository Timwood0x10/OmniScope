# OmniScope 性能链路全分析

> **日期**: 2026-06-02  
> **问题**: 小型 IR 文件（如 wasmtime_test.bc）分析耗时 ~30s，中型文件 ~218s，远超 60s 目标  
> **测试命令**: `time ./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc`

---

## 一、已知计时数据（部分 PERF 日志）

| Pass | 耗时 | 状态 |
|------|------|------|
| pointer-ownership | ~24.3s | 未优化 |
| SemanticResolver | ~11.8s | 未优化 |
| error-propagation-tracer | ~8.5s | **已优化** (Rust 分支) |
| gc-safety | ~2.7s | **已优化** (语言门控) |
| 其余 ~23 个 pass | **~167s** | **未知**（日志被过滤掉了） |

> 总计 ~218s。只看到 7 个 pass 合计 ~51s，剩余 167s 散布在其他 pass 里，原因见热点 3。

---

## 二、已完成的优化

### gc_safety_analyzer.zig:101 — 语言门控 ✅

```zig
const lang = ctx.module_language.language;
if (lang != .java and lang != .python) {
    log.debug("GcSafetyPass: skipping non-GC language module ({s})", .{@tagName(lang)});
    return;
}
```

Rust/C/C++ 模块跳过整个 GcSafety pass，节省 ~2.7s。

### error_propagation_tracer.zig:144 — Rust 快速路径 ✅

```zig
if (lang == .rust) {
    // 跳过 detectExceptionBoundaryViolations + detectErrorCodeMisinterpretation
    try detectUncheckedFFICalls(...);
    try detectErrorPathLeaks(...);
}
```

Rust 不使用 C++ 异常/landingpad 或 errno 风格错误码，跳过两个无意义检测，节省 ~5s。

---

## 三、当前热点详解

### 热点 1：SemanticResolver — 13 次独立全量 IR 遍历（~11.8s）

**文件**: `src/pass/analysis/semantic_resolver_pass.zig:99-168`

`SemanticResolverPass.run()` 里先跑一次完整 func/bb/inst 遍历（`processFunctionCall`，L58-96），然后调用 13 个独立 detector，**每个 detector 各自做一次完整模块遍历**：

```
ch04_conversions.zig:42    — func → bb → inst（bitcast/inttoptr）
ch05_uninitialized.zig:52  — func → bb → inst（MaybeUninit）
ch06_obrm.zig:77           — func → bb → inst（Drop/drop_in_place）
ch08_concurrency.zig:68    — func → bb → inst（Send/Sync）
ch09_vec_box.zig           — func → bb → inst（Vec/Box 堆分配）
ch10_pin_box.zig           — func → bb → inst（Pin/ManuallyDrop）
posix_syscalls.zig:152     — func → bb → inst（POSIX syscall 分类）
patterns/param_attr.zig:32        — func → bb → inst（readonly/noalias 属性）
patterns/heap_provenance.zig:88   — func → bb → inst（SROA + DI）
patterns/into_raw_transfer.zig:37 — func → bb → inst（Box::into_raw）
patterns/library_alloc_pairs.zig:145 — func → bb → inst（mimalloc/zlib/sqlite）
patterns/lang_detector.zig:76     — func → bb → inst（语言识别）
patterns/interior_mut.zig:47      — func → bb → inst（UnsafeCell）
```

同一模块被遍历 **14 次**（1 次 processFunctionCall + 13 个 detector）。

---

### 热点 2：pointer_ownership — 3 趟完整遍历（~24.3s）

**文件**: `src/pass/analysis/pointer_ownership.zig`

| 阶段 | 行号 | 内容 |
|------|------|------|
| Source 3 IR 扫描 | L272-311 | 单独一趟全量扫描，只为收集 free call sites |
| 主分析循环 | L333-431 | alloc/store/GEP/call 扫描 + analyzeFunctionForOwnership |
| 第二轮循环 | L435-440 | `checkOwnershipTransferForFunction` 再跑一遍 |

Source 3 扫描和第二轮循环可以消除，详见优化方案。

---

### 热点 3：隐藏的 ~167s — PERF 日志被过滤

**文件**: `src/pass/manager.zig:249`

```zig
// 当前：只打印超过 1ms 的 pass
if (elapsed_ms > 1) {
    log.info("[PERF] Pass '{s}': {d:.0} ms", .{ pass_name, elapsed_ms });
}
```

由于阈值是 1ms，大量耗时 pass 没有被记录。27 个注册 pass 中实际只看到 7 个的计时信息。

根据 pass 列表推断最可能的大头：

| 可疑 Pass | 预估原因 |
|-----------|----------|
| ptr-lifetime | 跨函数指针生命周期跟踪，多文件实现，复杂度高 |
| ffi-boundary | 边界扫描，全量遍历 |
| free-validation | 验证每个 free 操作 |
| callback-escape | 独立遍历 |
| rust-ffi-filter | 即使优化后仍在 pass_manager 里完整跑 |

---

### 热点 4：ParallelExecutor 存在但从未接线

**文件**: `src/pipeline/parallel.zig`

实现了完整的 work-stealing 线程池（Chase-Lev deque，per-worker result buffer），但 `src/pass/manager.zig` 完全没有引用它。所有 27 个 pass **全部串行执行**。

```zig
// manager.zig:215 — 纯串行循环
for (self.resolved_order.?) |idx| {
    self.passes.items[idx].run_fn(ctx, diag) catch |err| { ... };
}
```

在多核机器上，无依赖关系的 pass 组本可以并行跑。

---

## 四、优化方案，按 ROI 排序

### P0（今天，10 分钟）：打开完整 PERF 日志

**文件**: `src/pass/manager.zig:249`

```zig
// 改前
if (elapsed_ms > 1) {
// 改后（改回 0 暴露全量计时）
if (elapsed_ms > 0) {
```

重新编译后跑一次，获取完整 27-pass 耗时表。**这是所有后续优化的导航图**，不做这步，167s 的真正位置永远未知。

预期收益：无直接加速，但解锁后续所有优化的优先级判断。

---

### P1（半天）：SemanticResolver 合并为单次遍历（预期 -7~9s）

**改动文件**: `src/pass/analysis/semantic_resolver_pass.zig` + 各 nomicon/patterns 文件

**方向**: 把每个 detector 的逐指令/逐函数判断提取为 `analyzeFunc(func, srt)` / `analyzeInst(inst, opcode, func, srt)` 形式，然后在 SemanticResolver 已有的单次遍历里一起调用，删掉 L100-168 的 13 次独立 `detect()` 调用。

```zig
// semantic_resolver_pass.zig — 改后结构
var func = c.LLVMGetFirstFunction(raw_mod);
while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
    if (c.LLVMIsDeclaration(func) != 0) continue;
    const caller_name = ...;

    // 原 processFunctionCall 逻辑（保持不变）
    // + 函数级 detector 调用（ch06 Drop、ch08 Send/Sync 等）
    nomicon_ch06.analyzeFuncLevel(func, srt);
    nomicon_ch08.analyzeFuncLevel(func, srt);
    patterns_lang_detector.analyzeFuncLevel(func, srt);

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            // 原 processFunctionCall 指令逻辑
            if (llvm_safe.isCallOrInvoke(opcode)) {
                engine.processCallInst(inst, caller_name) catch {};
            }

            // 所有 detector 的指令级逻辑在同一循环里
            nomicon_ch04.analyzeInstLevel(inst, opcode, srt);  // bitcast/inttoptr
            nomicon_ch05.analyzeInstLevel(inst, opcode, srt);  // MaybeUninit
            nomicon_ch09.analyzeInstLevel(inst, opcode, srt);  // Vec/Box
            nomicon_ch10.analyzeInstLevel(inst, opcode, srt);  // Pin
            nomicon_posix.analyzeInstLevel(inst, opcode, srt); // POSIX syscall
            patterns_param_attr.analyzeInstLevel(inst, opcode, srt);
            patterns_heap_provenance.analyzeInstLevel(inst, opcode, srt);
            patterns_into_raw.analyzeInstLevel(inst, opcode, srt);
            patterns_library_alloc.analyzeInstLevel(inst, opcode, srt);
            patterns_interior_mut.analyzeInstLevel(inst, opcode, srt);
        }
    }
}
// 删除原 L100-168 的 13 次独立 detect() 调用
```

各 detector 文件需要新增 `analyzeInstLevel` / `analyzeFuncLevel` 函数，原 `detect(module, srt, diag)` 保留（供测试用），内部改为调用新的细粒度函数。

---

### P2（半天）：pointer_ownership 合并 Source 3 扫描（预期 -3~5s）

**文件**: `src/pass/analysis/pointer_ownership.zig:272-311`

Source 3 只是遍历所有函数收集 `free` call sites。主循环（L333）本来就遍历每个函数跑 `analyzeFunctionForOwnership`。可以把 free site 收集逻辑内联进主循环里同时执行：

```zig
// 改后：主循环里同时收 free sites
while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
    // ... 原有语言门控/noise filter/relevance check ...

    // 原 Source 3 逻辑（内联进来）
    collectFreeSitesInFunc(func, &free_map, &free_pool, &id_map);

    // 原主分析
    analyzeFunctionForOwnership(...);
    // ...
}
// 删除 L272-311 的独立 Source 3 遍历块
```

**安全性**: `detectViolations`（L468）在主循环**之后**运行，届时 `free_map` 已完全填充，合并不影响正确性。不同函数间跨函数 free 的场景（func A malloc，func B free）同样安全，因为两个函数都会在主循环中处理完，`free_map` 最终是完整的。

---

### P3（1 天）：PassContext 全局指令缓存（预期 -30s+，覆盖所有 pass）

**文件**: `src/pipeline/pipeline.zig` + `src/pass/pass.zig`

在 `pipeline.run()` 的 CallSiteIndex 构建循环中（L259-316，已有一次全量遍历），同时建立完整的 func/bb/inst 索引并注入 `ctx`：

```zig
// pipeline.zig run() — 在 pass_manager.run() 之前
// 现有 CallSiteIndex build 循环扩展为同时建立指令缓存
var module_inst_cache = try ModuleInstCache.build(mod, allocator);
defer module_inst_cache.deinit();
ctx.module_insts = &module_inst_cache;

// PassContext 新增字段
pub const PassContext = struct {
    // ...已有字段...
    module_insts: ?*ModuleInstCache = null,  // 新增
};

// ModuleInstCache 结构
pub const ModuleInstCache = struct {
    funcs: []FuncEntry,   // 所有非 declaration 函数
    // FuncEntry 包含 func ptr + 所有 bb + 所有 inst + opcode 预计算结果
};
```

所有 pass 从 `ctx.module_insts` 读取，完全不再调用 `LLVMGetFirstFunction/BasicBlock/Instruction`。这是覆盖最广的优化，一次改动让所有 27 个 pass 受益。

**代价**: 架构改动，需要对所有 pass 做兼容适配。

---

### P4（2-3 天）：接线 ParallelExecutor（预期 2-3x 总加速）

**文件**: `src/pass/manager.zig` + `src/pipeline/parallel.zig`

识别无依赖关系的 pass 组，分批并行执行：

```
轮次 1（并行）: SemanticResolver, CallGraph, SurfaceClassifier
轮次 2（并行）: PointerOwnership, FFIBoundary, BufferOverflow, ThreadCrossing, GcSafety, ErrorPropagation
轮次 3（串行）: PtrLifetime（依赖轮次2 的 FFIBoundary）
轮次 4（串行）: FreeValidation, RustFfiAuditor（依赖 PtrLifetime）
```

PassManager 的 `run()` 按依赖层次分批，同一批内启动 `ParallelExecutor`。

**前提条件**: 
1. `PassContext` 的并发写（`addIssue`、`cross_lang_edges` 等）需要加互斥锁或改为 per-worker buffer + 合并
2. LLVM C API 读操作是线程安全的（read-only），写操作禁止在并行阶段发生
3. 需完整 PERF 日志（P0）确认哪些 pass 耗时最长，再确定并行分组

---

## 五、执行计划

```
今天：
  [P0] manager.zig 1行改动，获取完整 27-pass PERF 日志
  [P0] 分析日志，确认 167s 的具体分布

本周：
  [P1] SemanticResolver 合并 13 个 detector → -7~9s
  [P2] pointer_ownership Source 3 合进主循环  → -3~5s

下周：
  [P3] PassContext 指令缓存（架构改动）       → -30s+

长期：
  [P4] ParallelExecutor 接线                 → 2-3x 总加速
```

按此计划，P0+P1+P2 完成后预计从 ~218s 降至 ~200s（已知热点部分）。P3 完成后预计降至 ~170s 以内。要达到 60s 目标，必须配合 P4 的并行化或针对 P0 日志暴露的具体 pass 做专项优化。

---

## 六、参考

- 原始性能分析计划: `docs/v2/performance_optimization_plan.md`
- Pipeline 主循环: `src/pipeline/pipeline.zig:120`
- Pass 管理器: `src/pass/manager.zig`
- 并行执行器: `src/pipeline/parallel.zig`
- SemanticResolver: `src/pass/analysis/semantic_resolver_pass.zig`
- PointerOwnership: `src/pass/analysis/pointer_ownership.zig`
- Nomicon 检测器目录: `src/semantics/nomicon/`
- Patterns 目录: `src/semantics/patterns/`
