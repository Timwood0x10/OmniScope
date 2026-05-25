# OmniScope 优化方案

编码风格：./plan/rules/rules.md 


---
 一、已完成的修复（工作区未提交）

  ┌─────┬─────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────┐
  │ ID  │                                      修复                                       │                    验证状态                    │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────┤
  │ B1  │ shouldSuppress 顶部加 isRealMemorySafetyBug 全局守卫                            │ ✅ 单测覆盖 + ffi-demo 验证有效                │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────┤
  │ B6  │ is_ffi_issue 白名单加 double_free / use_after_free / invalid_free / memory_leak │ ✅ cpp_hash/cpp_fft 内部 leak 不再被 risk 层丢 │
  ├─────┼─────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────┤
  │ B8  │ suppression_stats 加 safe_example / defensive_coding 归账                       │ ✅                                             │
  └─────┴─────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────┘

  未完成：B3（NonNull 子串匹配）、B7（mutually-exclusive 看 caller）。但 B3 实际效果已被 B1 全局守卫覆盖大半，B7 在当前 demo 没触发 FN。

  二、ffi-demo 全语言检测结果（vs baseline 2026-05-24）

  ┌─────────────────────────────────────┬──────────────────────────────────────────┬─────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────┐
  │                模块                 │              baseline 检出               │                          当前检出                           │                        关键变化                         │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ cpp_hash                            │ 0（3 个 leak 全漏）                      │ 1 TP (CompressBlock)                                        │ ✅ B6 解锁内部 leak                                     │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ cpp_fft                             │ 0 / 1 invalid_free                       │ 1 TP + 2 新 FP                                              │ ✅ InitTwiddle leak / ❌ 内部 new[]/delete[] 错判跨语言 │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ rust_merkle                         │ 0                                        │ 1 TP (rust→c_hash) + 1 新 FP                                │ ✅ FFI 边界 / ❌ format_digest drop chain double_free   │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ zig_main                            │ 6 TP (1 真精确 + 5 漏) / 7 stdlib / 3 FP │ 至少 6 TP（6 个 demo 全命中泛型 ffi_unsafe_call）/ 7 stdlib │ ✅ 5 个原本漏的 demo 全部触发                           │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ zig_ffi_bridge                      │ 1                                        │ 2 TP (malloc_unchecked + leak)                              │ 持平                                                    │
  ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ c_hash / c_fft / merkle / rust_hash │ 各 1 TP / 0 / 0 / 0                      │ 同 baseline                                                 │ 无变化                                                  │
  └─────────────────────────────────────┴──────────────────────────────────────────┴─────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────┘

  整体：TP 显著上涨（≈ 8 → 14+），新增 3 个 FP 是 B1 + ptr_lifetime classifier 的副作用。

  三、新增 3 个 FP 的精确根因

  FP-1：rust_merkle::format_digest 报 double_free（B1 副作用）

  - format_digest 是纯 Rust，String::with_capacity + format! 的 drop chain 在 IR 里看是 __rust_dealloc 多次。
  - 原本 Pattern A 抑制掉了；B1 全局豁免后所有 double_free 一律放行。
  - 修法：isRealMemorySafetyBug 加 caller-language 条件——纯 Rust 模块内部、callee 是 __rust_dealloc / drop_in_place 且没有 FFI 跨边界证据时，仍走 Pattern A。

  FP-2/3：cpp_fft::FFT 报 cross_language_free + invalid_free（真 bug）

  src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig:134 命名误导：
  const alloc_is_c = alloc_lang == .c or alloc_lang == .cpp;   // ← cpp 也算进 "c"
  ...
  if ((free_is_csharp or free_is_cpp) and (alloc_is_c or alloc_is_rust)) {
      // free=cpp + alloc=cpp 时也命中 → 同语言被报跨语言
  FFT() 里 rev = BitReverseTable() 返回 new[] (cpp)、delete[] rev (cpp)，两边都是 cpp 却走进了"跨语言"分支。
  修法：第 150 行排除 alloc_lang == free_lang_enum，或把 alloc_is_c 拆为 alloc_is_pure_c 和 alloc_is_cpp。
  
  附带：invalid_free 的消息 confidence: 0.85% 是 {d:.2}% 没乘 100 的格式 bug（free_validation.zig:604），显示一下不影响判定。

  四、当前仍漏 / 仍粗的关键 FN（按 ROI）

  ┌──────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                 漏检                 │                                    当前状态                                    │                                                      推荐改动                                                       │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Zig demo 5 个 bug 都只命中泛型       │ useAfterFreeDemo / crossLanguageFreeDemo / typeConfusionDemo / memoryLeakDemo  │ 这些 demo 的 Zig caller 已经触发 FFI 边界。需要在 ptr_lifetime_violations.checkCrossLanguageFree 的 Path            │
  │ ffi_unsafe_call                      │ / bufferOverflowDemo 只报 "FFI Boundary"，没有 use_after_free /                │ 2（call-site 语言上下文）里，识别 caller=zig, callee=c_alloc_buffer, no free →                                      │
  │                                      │ cross_language_free / type_confusion / memory_leak / buffer_overflow 精确 kind │ memory_leak；callee=c_get_dangling_ptr → use_after_free。这是 P0：能把粗粒度报警升级成 5 个精确 TP。                │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ FFT-LEAK-2 / FFT-LEAK-3 error-path   │ 漏                                                                             │ 路径敏感性。需要在 GlobalAllocTracker 加 "freed_on_some_path" 标志，error 分支没 free 就算泄漏。中期项目。          │
  │ leak                                 │                                                                                │                                                                                                                     │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ BUG-4b/c (cpp_hash 跨函数 new)       │ 漏                                                                             │ 过程间 ownership 追踪。new PadHelper() 返回值流到 caller，caller 没 delete。当前只跑 intra-procedural。             │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │                                      │                                                                                │ 返回值丢弃 / null 处理。unchecked_return / null_dereference 检测器存在但没跑出来，原因是 rust_hash 函数被           │
  │ rust_hash 2 个 unsafe FFI bug        │ 漏（非内存类）                                                                 │ surface_classifier 标成 stdlib/未分类后被 risk 层吞——B6 的白名单没覆盖这两个 kind。可加 unchecked_return 进入       │
  │                                      │                                                                                │ is_ffi_issue。                                                                                                      │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Zig stdlib 7 条 noise                │                                                                                │ debug.* / hash_map.* / array_hash_map.* 这些 Zig stdlib 函数没被 surface_classifier cache 标为 stdlib，导致         │
  │ (write_to_immutable /                │ 持续 FP                                                                        │ origin=unknown → risk 没降级。需要在 surface_classifier 给 Zig stdlib 加前缀匹配。                                  │
  │ callback_ownership_risk)             │                                                                                │                                                                                                                     │
  └──────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  五、建议下一步顺序（按 ROI / 风险）

  1. 修 FP-2/3（ptr_lifetime_violations.zig:134/150 改 5 行）— 立刻消两个 cpp 内部 FP。低风险，高 ROI。
  2. 修 FP-1（isRealMemorySafetyBug 加 caller-language guard）— 消 Rust drop chain 副作用 FP。B1 的精修，不可省略。
  3. 修 Zig demo 粗粒度问题（Path 2 call-site 上下文升级精确 kind）— 5 个 Zig demo 从泛型 ffi_unsafe_call 升级为精确 kind。P0，对 actionability 影响最大。
  4. 修 confidence 格式 bug（free_validation.zig:604 乘 100）— 1 行修复，纯显示。
  5. Zig stdlib 加入 surface classifier 抑制（B6 之外的另一条路径）— 减 7 条 noise。
  6. （远期）error-path leak / 过程间 ownership / unchecked_return 白名单。

---

## 验收清单

- [x] File is under 1000 lines
- [x] Code is simple and straightforward
- [x] All comments are in English
- [x] Code-to-comment ratio is approximately 7:3
- [x] Tests include boundary cases
- [x] No files were deleted without permission
- [x] Naming conventions are followed
- [x] Code is formatted with `zig fmt`
- [x] All tests pass
- [x] Public APIs have doc comments
- [x] Error handling is appropriate
- [x] Memory management is correct
- [x] Changes are surgical and minimal