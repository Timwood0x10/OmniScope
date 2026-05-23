 已完成的优化
  
  1. DangerSurfacePass Phase 2 — 已实现

  问题: 原先对每个 MemoryGraph 节点调用 isOnDangerPathFull()，每次都分配 72,532 元素数组 + 2 个 HashMap。15K+ 节点 = 上千万次无谓分配。

  方案: 内联廉价检查 + 预构建 ffi_set
  - (1) 检查 node.zone == .unsafe
  - (2) 检查跨语言生命周期（alloc_lang != free_lang）
  - (3) 检查 FFI arg（通过 getCallArgsForPtr + ffi_set.contains）
  - (4) 检查 FFI ret（通过 getCallRetsForPtr + ffi_set.contains）
  - (5) 只有以上都失败且节点有 alias 时才走 isOnDangerPath
  
  状态: 构建通过，小测试用例验证正确。

  2. 报告函数内存泄漏 — 已修复 14 处

  ptr_lifetime_report.zig (13处) + free_validation.zig (1处) 添加了 errdefer issue.deinit(ctx.allocator)。

  ---
  待做优化方案
  
  3. isOnDangerPathFull 全局缓存（影响多 pass）

  PassContext.isOnDangerPathFull() (pass.zig:898) 不只被 DangerSurfacePass 调用。可以把 ffi_set 缓存到 PassContext 中，首次构建后复用，避免每次重建。

  PointerOwnership 优化方向

  PointerOwnership 过滤链已经比较完善（zone gate → noise filter → isRustFFIRelevantFunction → isRelevantFunction），但在 wasmtime 这种 17MB 的大文件上，即使过滤后函数数量仍然可观。可能的优化：

  - Source 3 IR scan (line 385-418): 扫描全部函数的全部指令找 free。可以延迟到主循环中合并执行，减少一次全量遍历。
  - isRustFFIRelevantFunction (line 686): 对每个非 Rust 函数直接返回 true，不扫描指令。对 Rust 函数扫描指令找 extern 调用。可以缓存更多结果。

  4. Zone classification 收紧

  当前 .unknown 函数全部进入分析。如果在 zone_classifier.zig 中把更多用户函数分类为 .safe（比如通过 debug info 源文件路径判断），可以大幅减少分析范围。

