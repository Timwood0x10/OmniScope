诊断报告：四个问题的根因与修复路径

  问题 1：cross_language_free 检测为 0%

  根因有两层，叠加导致完全失效：

  第一层（上游门控）：free_validation.zig:69
  if (ctx.danger_surface_relevant.count() == 0) return;  // ← 整个 pass 直接退出
  FreeValidationPass.run() 依赖 DangerSurfacePass 的输出。只要 danger_surface_relevant 为空，cross_lang 检测连入口都进不去。
  
  第二层（tracking 遗漏）：free_validation.zig:178-200 的 trackPointerOrigin()，对于 isAllocFunction() 返回 true 的调用，source_desc 格式是 "from malloc()" 这样的字符串。extractAllocFuncNameForCrossLang()
  解析这个字符串提取函数名——这个解析逻辑本身是正确的。

  但真正的致命缺口是：isAllocFunction() 基于 HEAP_ALLOC_FUNCTIONS 列表做匹配，而 __rust_alloc、_Znwm 等都在列表里，但 Rust mangled 名（如 _RZN4alloc...）在 isAllocFunction() 里走 functionNameMatches() 的 endsWith 逻辑，不会匹配。这意味着典型的
  Rust 内存分配调用根本不进入 pointer_origins map，到 checkFreeCall 时 origin_info 为 null，直接跳过 cross-lang check（line 468 的 if (origin_info) |info|）。

  修复路径（优先级 P0）：

  1. 修 DangerSurfacePass 依赖问题：free_validation.zig:69 的门控过于激进。对于 cross-lang free，应当独立于 danger_surface 运行（或在 danger_surface 为空时降级为只做 cross-lang 检测）：
  // 当前
  if (ctx.danger_surface_relevant.count() == 0) return;
  
  // 修复：只跳过需要 danger_surface 的子检测，cross-lang 检测独立运行
  const has_danger_surface = ctx.danger_surface_relevant.count() > 0;
  2. 修 Rust 函数名 tracking：在 trackPointerOrigin() 里，当 isAllocFunction() 返回 false 时，补一个 Rust v0 mangling 检测分支：
  } else if (isRustAllocCall(func_name) or isCppNewCall(func_name)) {
      // 记录为 from_malloc，source_desc 包含真实函数名
  }
  2. 新增 isRustAllocCall() 检测 _R 前缀 + 包含 alloc/allocate 的模式；isCppNewCall() 检测 _Znwm/_Znam。

  ---
  问题 2：C++ operator new/delete 完全未支持
  
  根因：HEAP_ALLOC_FUNCTIONS（ptr_lifetime_types.zig:320）里有 _Znwm、_Znam 等 C++ 分配函数，但 isFreeFunction() 里对应的 delete 模式检测不完整。更关键的是，isCrossAllocatorFree() 里当 alloc_origin == .from_malloc 且 free 是 _ZdlPv/_ZdaPv
  时，走的是 line 550+ 的 豁免分支（直接 return false），而不是 cross-lang 检测。

  查看 free_validation.zig:544-562：
  // P1 FIX: Standard C free()/operator delete on FFI-sourced pointer is normal.
  if (std.mem.eql(u8, callee_name, "free") or
      ...
      std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or  // ← 直接放行！
      
  这个豁免是为了减少 FP 而加的，但副作用是 malloc + operator delete（典型 UB）、new + free()（同样 UB）这类跨分配器问题被完全静默。

  修复路径（P1）：在 isCrossAllocatorFree() 里，引入显式的 new/delete 与 malloc/free 交叉检测，先于豁免分支执行：
  // 在豁免分支之前检查 new/delete 与 malloc/free 交叉
  const alloc_is_cpp_new = isInSourceDesc(source_desc, &[_][]const u8{"_Znwm", "_Znam", "operator new"});
  const free_is_c_free = std.mem.eql(u8, callee_name, "free");
  const alloc_is_c_malloc = isInSourceDesc(source_desc, &[_][]const u8{"malloc", "calloc"});
  const free_is_cpp_delete = std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                              std.mem.indexOf(u8, callee_name, "_ZdaPv") != null;
                              
  if ((alloc_is_cpp_new and free_is_c_free) or (alloc_is_c_malloc and free_is_cpp_delete)) {
      return true; // ← 先报告，不走豁免
  }

  ---
  问题 3：库特定资源契约缺失
  
  当前状态：ffi_contract_db.zig 已有 SQLite 和 OpenSSL 的规则，但 连通路径有缺口。

  validateWithContractDBFromSource()（free_validation.zig:1040）调用路径是：
  checkFreeCall() → validateWithContractDBFromSource() → extractAllocFuncName(source_desc) → ctx.contract_db.isValidRelease()
  
  extractAllocFuncName()（line 1130）从 source_desc 提取函数名。问题在于 source_desc 格式是 "from sqlite3_open()" ——这个解析能正确工作。但 trackPointerOrigin() 只对 isAllocFunction() 返回 true 的函数创建 pointer_origins 条目，而
  isAllocFunction() 不认识 sqlite3_open、SSL_CTX_new 等库函数。

  因此 origin_info 为 null → validateWithContractDBFromSource 永远不被调用。

  修复路径（P1）：在 trackPointerOrigin() 里增加第三个分支：contract DB 查询。对 ctx.contract_db.shouldReportLeak(func_name) 返回 true 的调用，创建 from_ffi_call origin：
  } else if (ctx.contract_db.shouldReportLeak(func_name)) {
      const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
      // gop.value_ptr.* = .{ .origin = .from_ffi_call, ... };
  }   
  
  注意：trackPointerOrigin 当前签名没有 ctx 参数，需要加入或通过 closure 传入。

  ---
  问题 4：ffi_unsafe_call 噪音（Precision 11-14%）
  
  根因：hasAuxiliaryEvidence()（ffi_unsafe.zig:324）的 Layer 3 门控逻辑太宽松：

  // "不包含验证词汇" + "函数名有 wrap/call/invoke/exec/run/do_" → 报告
  if (!has_validation and func_name.len > 4) {
      const risky_prefixes = [_][]const u8{ "wrap", "call", "invoke", "exec", "run", "do_" };
      for (risky_prefixes) |prefix| {
          if (std.mem.indexOf(u8, func_name, prefix) != null) { return true; }
      }
  }

  "run" 是一个极其常见的函数名前缀，"call" 也是。这个规则本质上对大量普通函数返回 true，Layer 3 形同虚设。

  同时，isWhitelisted() 的 safe_name_patterns 里含 "init"、"get_"、"set_"，但这些用 indexOf 做子串匹配，"initialize"、"settings" 等都会命中——导致部分真正危险的函数被误放行（影响 recall），但这方向与 precision 问题相反。

  实际造成噪音的核心路径：DangerousPatterns 里的 "exec" 会匹配任何名字含 "exec" 的函数（如 sqlite3_exec），然后 classifyVulnerability() 返回 .command_injection——这是高置信度类型，直接跳过 Layer 3 的 hasAuxiliaryEvidence 检查（line 217 的
  is_generic_vuln 判断为 false）。

  修复路径（P0 for precision）：

  1. DangerousPatterns 里的 "exec" 改为精确匹配：execve/execvp/system 保留，去掉纯 "exec" 子串匹配：
  // 当前
  "exec",
  // 修复：只匹配实际危险的 exec 系列
  // 在 classifyVulnerability 里用精确匹配
  2. hasAuxiliaryEvidence() 收紧 "run" 和 "call" 规则：这两个词太通用，从 risky_prefixes 里删除，或改为仅在 "run" 作为独立词（不是前缀）时才算证据。
  3. isWhitelisted() 里 safe_name_patterns 改用词边界匹配：用 startsWith 代替 indexOf，或者直接删除 "init" 这类过于宽泛的词。

  ---
  修复优先级矩阵
  
  ┌────────┬───────────────────────┬──────────────────────────────────────────────────────────┬──────┬─────────────────────────────┐
  │ 优先级 │         问题          │                         改动位置                         │ 难度 │          预期收益           │
  ├────────┼───────────────────────┼──────────────────────────────────────────────────────────┼──────┼─────────────────────────────┤
  │ P0     │ ffi_unsafe_call noise │ ffi_unsafe.zig:DangerousPatterns、hasAuxiliaryEvidence   │ 小   │ Precision 从 11% → 40%+     │
  ├────────┼───────────────────────┼──────────────────────────────────────────────────────────┼──────┼─────────────────────────────┤
  │ P0     │ cross_lang_free 门控  │ free_validation.zig:69                                   │ 小   │ 解锁整个 pass               │
  ├────────┼───────────────────────┼──────────────────────────────────────────────────────────┼──────┼─────────────────────────────┤
  │ P1     │ Rust alloc tracking   │ free_validation.zig:trackPointerOrigin + isRustAllocCall │ 中   │ cross_lang Recall 0% → 30%+ │
  ├────────┼───────────────────────┼──────────────────────────────────────────────────────────┼──────┼─────────────────────────────┤
  │ P1     │ C++ new/delete 交叉   │ free_validation.zig:isCrossAllocatorFree                 │ 中   │ 新增 TP 类型                │
  ├────────┼───────────────────────┼──────────────────────────────────────────────────────────┼──────┼─────────────────────────────┤
  │ P2     │ Library contract 连通 │ trackPointerOrigin 加 contractDB 查询                    │ 中   │ SQLite/OpenSSL 契约生效     │
  └────────┴───────────────────────┴──────────────────────────────────────────────────────────┴──────┴─────────────────────────────┘

  最快能拿到实际 TP 的路径：先修 P0 的两个（20-30行改动），验证 cross_lang pass 能跑起来，然后再做 P1 的 Rust tracking。
