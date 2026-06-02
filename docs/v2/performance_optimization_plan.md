# OmniScope 性能优化计划

> **日期**: 2026-06-02
> **问题**: wasmtime_test.bc 分析耗时 348s（目标 <60s）
> **测试命令**: `time ./zig-out/bin/OmniScope ./corpus/real_world/other/wasmtime_test.bc`

---
实测 Pass 耗时分析
  
  可见的 7 个 pass 合计 ~51s，总时间 218s，剩余 ~167s 散布在其他 pass 里（用户日志是截段，完整输出会有全部 27 个 pass 的 PERF 行）。
  
  逐个根因
  
  ---
  ① pointer-ownership：24.3s — 三次全量 IR 遍历
  
  pointer_ownership.zig 里存在 3 轮完整的 module-level 函数/BB/inst 遍历：
  
  ┌──────────────────┬──────────┬───────────────────────────────────────────┐
  │       阶段       │   位置   │                   作用                    │
  ├──────────────────┼──────────┼───────────────────────────────────────────┤
  │ Source 3 IR scan │ L272-311 │ 收集所有 free 调用点                      │
  ├──────────────────┼──────────┼───────────────────────────────────────────┤
  │ 主分析循环       │ L333-431 │ alloc/store/GEP/call 扫描 + 7个子检测函数 │
  ├──────────────────┼──────────┼───────────────────────────────────────────┤
  │ 第二轮遍历       │ L435-440 │ checkOwnershipTransferForFunction         │
  └──────────────────┴──────────┴───────────────────────────────────────────┘
  
  而且在第二轮里，detectAsPtrBorrowEscape()、detectStructMemberStores() 等子函数各自也对当前函数做独立扫描。这和之前 RustFfiAuditor 的问题如出一辙。
  
  ---
  ② SemanticResolver：11.8s — 14 个 Nomicon 检测器各自扫 IR
  
  // semantic_resolver_pass.zig:99
  // Run Nomicon detectors to populate SRT
  nomicon_ch04::detect(raw_mod, srt)
  nomicon_ch05::detect(raw_mod, srt)
  nomicon_ch06::detect(raw_mod, srt)
  ... // 共 14 个 detector，每个独立遍历模块
  
  前面还有一轮全量扫描来 processFunctionCall()，实际上同一模块被扫了 15 次。
  
  ---
  ③ error-propagation-tracer：8.5s — 4 次全量遍历，对 Rust 无意义
  
  collectFFICalls()            → 第 1 次全量 func/BB/inst 遍历
  detectUncheckedFFICalls()    → 用已收集的数据，相对轻量
  detectExceptionBoundaryViolations() → 第 2 次全量遍历（针对 Java/C++ 异常）
  detectErrorCodeMisinterpretation()  → 用收集的数据
  detectErrorPathLeaks()       → 第 3+4 次全量遍历
  
  Rust 模块不抛 C++ 异常，不用 errno 风格错误码，exception 和 misinterpretation 两个检测全部白跑。
  
  ---
  ④ gc-safety：2.7s — Rust 没有 GC，零收益
  
  GcSafetyPass 针对 Java/Python 的 GC 引用计数场景，对 Rust 模块没有任何语言门控，4000+ 函数全扫一遍。
  
  ---
  ⑤ 隐藏的 ~167s
  
  根据 pass 列表推断最可能的大头：
  
  ┌───────────────────────────────────────┬──────────────────────────────────────────────┐
  │                 Pass                  │                   预估原因                   │
  ├───────────────────────────────────────┼──────────────────────────────────────────────┤
  │ ptr-lifetime（PtrLifetimePass）       │ 跨函数指针生命周期跟踪，多文件实现，复杂度高 │
  ├───────────────────────────────────────┼──────────────────────────────────────────────┤
  │ ffi-boundary（FFIBoundaryPass）       │ 边界扫描，全量遍历                           │
  ├───────────────────────────────────────┼──────────────────────────────────────────────┤
  │ free-validation（FreeValidationPass） │ 验证每个 free 操作                           │
  ├───────────────────────────────────────┼──────────────────────────────────────────────┤
  │ rust-ffi-filter（RustFfiAuditor）     │ 即使优化后仍在 pass_manager 里跑一次         │
  ├───────────────────────────────────────┼──────────────────────────────────────────────┤
  │ callback-escape / return-check        │ 各自独立遍历                                 │
  └───────────────────────────────────────┴──────────────────────────────────────────────┘
  
  ---
  三类修法，按投入/产出排
  
  类型 A：语言门控（1-2小时，零风险）
  
  对 Rust 模块收益最大、改动最安全：
  
  // error_propagation_tracer.zig run() 开头加：
  const lang = ctx.module_language.language;
  if (lang == .rust) {
      // Rust 用 Result/? 而非异常/errno，跳过两个无意义的检测
      try collectFFICalls(ctx, &ffi_calls, module);
      try detectUncheckedFFICalls(ctx, diag, &ffi_calls, &stats);
      // detectExceptionBoundaryViolations → skip
      // detectErrorCodeMisinterpretation  → skip
      try detectErrorPathLeaks(ctx, diag, module, &stats);
      return;
  }
  
  // gc_safety.zig run() 开头加：
  const lang = ctx.module_language.language;
  if (lang == .rust or lang == .c or lang == .cpp) {
      diag.debug("GcSafety: skipping non-GC language ({s})", .{@tagName(lang)});
      return;
  }
  
  预期节省：8.5s (error-propagation) × 0.6 + 2.7s (gc-safety) ≈ -8s
  
  ---
  类型 B：合并多趟遍历（半天，中等改动）
  
  pointer-ownership 的三次全量遍历合并成一次：
  
  现在：Source3-scan → 主循环 → 第二轮
  目标：一次遍历 → 同时收集 frees + allocs + call sites + ownership transfer
  
  具体做：在主循环（L333）里同时做 Source 3 scan 的工作（把 free-site 收集逻辑 inline 进去），删掉 L272-311 的独立遍历；把 checkOwnershipTransferForFunction 也合进主循环，删掉 L435-440。
  
  同理，SemanticResolver 的 14 个 Nomicon 检测器：改为在同一次 func/BB/inst 遍历里依次调用，而不是每个检测器独立遍历模块。
  
  预期节省：pointer-ownership -15s, SemanticResolver -6s ≈ -21s
  
  ---
  类型 C：PassContext 共享指令列表（1天，架构改动）
  
  把「一次性收集全部指令」提升到 pipeline 层：
  
  // pipeline.zig run() 里，在 pass_manager.run() 之前：
  var module_insts: ModuleInstCache = try collectModuleInstructions(mod, allocator);
  defer module_insts.deinit();
  ctx.module_insts = &module_insts;  // 注入到 PassContext
  
  所有 pass 从 ctx.module_insts 拿预构建的指令列表，完全不再调用 LLVMGetFirstBasicBlock/LLVMGetFirstInstruction。这是最彻底的方案，收益覆盖所有 pass。
  
  ---
  优先级
  
  立刻做（今天）：
    类型A — gc-safety 语言门控（10分钟）       → -2.7s
    类型A — error-propagation Rust 分支（30分钟）→ -5s
  
  本周做：
    类型B — pointer-ownership 合并三趟遍历（半天）→ -15s
    类型B — SemanticResolver 合并14个检测器（半天）→ -6s
  
  长期做：
    类型C — PassContext 共享指令列表           → 覆盖所有 pass 的剩余浪费
  
  类型 A 两个修改加起来 40 分钟，可以把 218s 降到 ~210s。类型 B 做完预计降到 ~170s。要到 60s 以内还需要把隐藏的 167s 也挖出来——需要完整的 27-pass PERF 日志（把 > 10ms 的过滤改成 > 0 跑一次看全貌）。