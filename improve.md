# OmniScope Memory + Ownership 深化开发计划

**目标:** 将 ffi-demo precision 从 73% 提升到 90%+，召回率从 50% 提升到 75%+
**范围:** Memory + Ownership 核心能力，不横向铺开 Bounds/Overflow

编码风格与约束：`./plan/rules/rules.md`

---

## 现状验证（源码级证据）

### 根因 1: Zig 模块零分析

**证据:** `src/pass/pass.zig:928-934`
```zig
pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .skip,    // ← 这里
        .go => .limited,
        else => .full,
    };
}
```

**影响:** `ptr_lifetime.zig:184` 收到 `.skip` 后直接 `return`，导致：
- GlobalAllocTracker 不记录任何分配 → ZIG-LEAK-6 漏检
- checkCrossLanguageFree 不运行 → ZIG-CROSS-1 漏检
- checkCallViolation 不运行 → UAF 漏检

**同样被 skip 的 pass:** `channelPointerOwnership` (pass.zig:941-947)、`channelCallbackEscape` (pass.zig:935-940)

### 根因 2: C++ 内部泄漏被 danger path 门控过滤

**证据:** `src/pass/analysis/cpp_fp_reduction.zig:1130-1138`
```zig
const on_danger_path = ctx.isOnDangerPathFull(@as(u64, alloc_info.inst_id));
if (!on_danger_path) {
    diag.debug("LEAK-SKIP: alloc {d} not on danger path (pure internal)", .{...});
    continue;  // ← cpp_hash 的 new uint32_t[48] 在这里被跳过
}
```

**影响:** `isOnDangerPathFull` (pass.zig:1062) 要求分配在 FFI 边界路径上。cpp_hash 的 `new uint32_t[48]` 是纯内部分配，从未传给任何 FFI 调用，所以永远返回 false → 3 个泄漏全部漏检。

**关键缺陷:** `isOnDangerPath` 的 `cross_lang_lifecycle` 检查 (memory_graph.zig:1117) 要求 `node.freed == true`，但泄漏的定义就是 unfreed，所以这个分支永远走不到。

### 根因 3: Zig @cImport free 无法通过函数名区分语言

**证据:** Zig 的 `@cImport` 生成的 `free` 调用在 IR 层面就是 C 的 `free`（字符串 "free"）。`classifyFreeLanguage("free")` 返回 `"c"`，而 `classifyAllocLanguage("malloc")` 也返回 `"c"` → 两者都是 "c"，不会触发跨语言报告。

**根本问题:** 当前分类器只看 callee 函数名，不看 call site 所在语言。需要引入 "call site language context"。

---

## 开发计划

### P0: 解锁 Zig 模块的内存分析（预计 1-2 天）

**改动文件:** `src/pass/pass.zig`

**改动内容:**
```zig
// 改前:
pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .skip,
        .go => .limited,
        else => .full,
    };
}

// 改后:
pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .limited,   // ← 从 skip 改为 limited
        .go => .limited,
        else => .full,
    };
}
```

同样修改 `channelPointerOwnership` 和 `channelCallbackEscape`。

**预期效果:**
- ZIG-LEAK-6 (C malloc 未释放) → 检出
- ZIG-CROSS-1 (C alloc → Zig free) → 部分检出（依赖 P1）
- Zig stdlib 内部的 write_to_immutable 等可能增加 FP → 需要 noise filter 调优

**验证:** 跑 `zig_main.bc`，检查 GlobalAllocTracker 是否记录到 `c_alloc_buffer` 的分配。

**风险:** 可能引入 Zig stdlib 内部的 FP。需要配合 noise filter 将 Zig stdlib 函数（`debug.*`、`heap.*`、`mem.*`）标记为 noise。

---

### P1: 跨语言 free 检测增强 — call site 语言上下文（预计 2-3 天）

**问题:** Zig @cImport 的 `free` 在 IR 里就是 C 的 `free`，callee 名无法区分。

**方案:** 在 `checkCrossLanguageFree` 中引入 call site 所在函数的语言信息。

**改动文件:**
1. `src/pass/analysis/ptr_lifetime_violations.zig` — `checkCrossLanguageFree`
2. `src/pass/analysis/ptr_lifetime.zig` — `trackInstruction` 传递 caller 语言
3. `src/pass/analysis/ptr_lifetime_classify.zig` — 新增 `classifyFreeLanguageWithContext`

**核心逻辑:**
```zig
fn checkCrossLanguageFree(
    callee_name: []const u8,
    caller_func_name: []const u8,  // 新增
    caller_lang: Language,          // 新增: call site 所在语言
    ...
) void {
    const free_lang = classifyFreeLanguage(callee_name);

    // 新规则: 如果 free 函数是 C 的 "free"，但 call site 在 Zig 代码中
    // → 语义上是 Zig 在释放内存，应该用 Zig 的 allocator
    if (free_lang == .c and caller_lang == .zig) {
        // 检查 alloc_lang 是否也是 .c
        // 如果 alloc_lang == .c → 同语言，不报
        // 如果 alloc_lang != .c → 跨语言 free
    }
}
```

**关键洞察:** Zig @cImport 的 `free` 虽然 IR 层面是 C 的 `free`，但语义上是 Zig 代码在调用。如果分配来自 C（alloc_lang == .c），这是合法的 C-alloc-C-free。但如果分配来自 Zig allocator（alloc_lang == .zig），这就是跨语言问题。

**实际场景:** 在 ffi-demo 中，`c_alloc_buffer` 返回的内存被 `c.c_release_buffer(ptr)` 释放，这其实是 C-alloc-C-free，本就不该报。真正的 bug 是 `c.free(ptr)` 在 double-free 路径上被 Zig 代码调用——这需要 P0 先解锁 Zig 分析。

**验证:** 跑 `zig_main.bc`，确认 `crossLanguageFreeDemo` 不误报（C-alloc + C-free via @cImport 是合法的），`doubleFreeDemo` 的第二次 free 被检测到。

---

### P2: C++ 内部泄漏检测 — 放宽 danger path 门控（预计 1-2 天）

**问题:** `detectMemoryLeaks` 的 `isOnDangerPathFull` 门控过滤掉了所有非 FFI 路径的泄漏。

**方案:** 新增一个 "internal leak" 检测路径，对 C++ 模块中的 `new`/`new[]` 分配，即使不在 FFI 路径上也报告（降低 severity）。

**改动文件:** `src/pass/analysis/cpp_fp_reduction.zig` — `detectMemoryLeaks`

**核心逻辑:**
```zig
// 现有逻辑: 只报告 danger path 上的泄漏
const on_danger_path = ctx.isOnDangerPathFull(alloc_info.inst_id);
if (!on_danger_path) {
    // 新增: 对 C++ new/new[] 分配，即使不在 danger path 也报告为 LOW
    if (isCppNewAllocation(alloc_info.callee_name)) {
        stats.memory_leaks += 1;
        ctx.addIssue(&Issue.init(
            .memory_leak,
            "C++ heap allocation never freed (internal)",
            Location.init(alloc_info.func_name),
            .low,      // 降级为 LOW
            0.5,       // 降低 confidence
        ));
    }
    continue;
}

fn isCppNewAllocation(callee: []const u8) bool {
    return containsAny(callee, &[_][]const u8{
        "_Znwm", "_Znam", "_Znw", "_Zna",
        "operator new", "operator new[]",
    });
}
```

**预期效果:**
- cpp_hash `CompressBlock`: `new uint32_t[48]` → 检出 (LOW)
- cpp_hash `Hash`: `new PadHelper()` → 检出 (LOW)
- cpp_hash `S0`: 静态 `new uint32_t[1024]` → 检出 (LOW)
- cpp_fft `InitTwiddle`: `new float[n]` → 检出 (LOW)

**验证:** 跑 `cpp_hash.bc` 和 `cpp_fft.bc`，确认 5 个 C++ 泄漏全部检出。

**风险:** 可能增加 C++ 模块的 FP（如 new 后通过 output parameter 传出所有权的情况）。需要配合 ownership transfer 启发式（如 `isIntentionalOwnershipTransfer`）过滤。

---

### P3: Zig noise filter 调优（预计 1 天）

**问题:** P0 解锁 Zig 分析后，Zig stdlib 内部的 issues 可能暴增。

**方案:** 在 noise filter 中增加 Zig stdlib 前缀过滤。

**改动文件:** `src/semantics/noise_filter.zig` 或 `src/semantics/surface_classifier/`

**需要过滤的 Zig stdlib 前缀:**
```
debug.          (DWARF, stacktrace)
heap.           (allocators)
mem.            (memory utilities)
io.             (I/O)
fmt.            (formatting)
posix.          (OS abstraction)
```

**验证:** 跑 `zig_main.bc`，确认 Zig stdlib 内部 issues 被过滤，只保留 `main.*` 函数的 issues。

---

### P4: GlobalAllocTracker ptr_id 修复（预计 0.5 天）

**问题:** `GlobalAllocTracker.insertAlloc` 存储 `ptr_id: 0`，下游代码无法交叉引用。

**证据:** `src/pass/pass.zig:160`
```zig
.ptr_id = 0, // Will be filled by caller if needed
```

**方案:** 在 `trackInstruction` 中，调用 `insertAlloc` 后立即设置 `ptr_id`。

**改动文件:** `src/pass/analysis/ptr_lifetime.zig`



### P5: 扩展跨语言 free 检测

当前只检测到 C++ new → C free 的不匹配。需要扩展到：
- Zig allocator → C free
- C malloc → Zig allocator free
- Rust alloc → C free

### P6: Go/LLVM bitcode 支持

考虑集成 `tinygo` 以支持纯 Go 项目的 LLVM bitcode 生成，使 OmniScope 能分析 Go 代码。

---

## 优先级排序

| 优先级 | 任务 | 预计工时 | 预期效果 | 依赖 |
|--------|------|---------|---------|------|
| P0 | 解锁 Zig 内存分析 | 1-2 天 | +2 TP (ZIG-LEAK-6, ZIG-CROSS-1 部分) | 无 |
| P1 | 跨语言 free call-site 上下文 | 2-3 天 | +1 TP (ZIG-CROSS-1 完整) | P0 |
| P2 | C++ 内部泄漏检测 | 1-2 天 | +5 TP (cpp_hash 3 + cpp_fft 2) | 无 |
| P3 | Zig noise filter | 1 天 | 减少 Zig FP | P0 |
| P4 | GlobalAllocTracker ptr_id | 0.5 天 | 架构改进 | 无 |

**总预计工时:** 5.5-8.5 天

**完成后预期:**
- TP: 8 → 15 (+7)
- FP: 3 → 5 (Zig stdlib 可能新增少量)
- Precision: 73% → 85-90%
- Recall: 50% → 75%

---

## 不做的事情（明确排除）

| 能力 | 原因 |
|------|------|
| 缓冲区溢出检测 | gep offset 是运行时值，静态分析不可靠，ASan 才能做 |
| 整数溢出检测 | FFI 场景不是痛点，Rust/Go IR 已有显式检查 |
| 死锁/竞态检测 | 需要线程模型，超出当前架构 |
| 逻辑 bug 检测 | 无统一 IR 模式，不可能做 |
| Go 纯代码分析 | 需要 tinygo 集成，工作量大，优先级低 |
