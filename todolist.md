# OmniScope — Graph-Driven FFI/Unsafe Boundary Analyzer

> **Version**: v0.3.0 (Graph-Driven Architecture)
> **Core Positioning**: **不是通用静态分析器。是 FFI/Unsafe 边界的门卫。**
> **Goal**: TP > 60%, FP < 10%, 大型项目 MS 级分析速度

***

## 核心原则

```
OmniScope 只关心一件事：数据是否安全地跨越了 FFI/Unsafe 边界。

Tier 1（放行，轻量）          Tier 2（严格，图驱动）
┌─────────────────────┐    ┌──────────────────────────┐
│ 纯 C/C++ 内存操作     │    │ unsafe {} 块内的所有操作   │
│ 同语言调用链          │    │ FFI 边界（CrossLangEdge） │
│ .safe / .runtime_int  │    │ .unsafe zone 函数        │
│ cgo/extern 外的代码   │    │ 跨语言指针传递            │
│                     │    │                          │
│ 策略：不报 issue      │    │ 策略：沿 MemoryGraph     │
│ 只做统计计数          │    │   + CallGraph 全路径追溯  │
│                     │    │   只报触达危险的真问题      │
│ 负担：极低           │    │ 负担：集中，精准          │
│ 噪声：零             │    │ 噪声：极少               │
└─────────────────────┘    └──────────────────────────┘

输出 = Tier 2 的结果。Tier 1 的数据留作统计概览。
```

**禁止白名单。** 每一条过滤都是「这条数据路径没有到达危险区域，所以不关心」。
**充分利用已有图。** MemoryGraph + CallGraph 已有完整基础设施。

***

## 目标指标

| 指标                          | 当前基线 (R8.0+ fresh)         | 目标                                      | 验证方法                                    |
| --------------------------- | -------------------------- | --------------------------------------- | --------------------------------------- |
| **TP Rate**                 | \~11-14%                   | **> 60%**                               | 18 文件 intentional bug 锚点 + 源码交叉验证       |
| **FP Rate**                 | \~86-89%                   | **< 10%**                               | 同上                                      |
| **Total Issues** (18 files) | \~1,356                    | **\~100-200**                           | `zig build test` + fresh run            |
| **Clean projects**          | 7/18 (39%)                 | **≥ 12/18 (67%)**                       | ring/blst/wasmtime/ripgrep/ark\_ff + 新增 |
| **sqlite3 analysis time**   | \~3.6s                     | **< 500ms** (MS 级)                      | `time ./omniscope sqlite3.ll`           |
| **大型项目 (>1000 funcs)**      | O(all\_funcs × all\_insts) | **O(danger\_surface × avg\_path\_len)** | profiler                                |
| **白名单数量**                   | 0 (已清零)                    | **0**                                   | code review                             |

***

## 架构：两张已有的图

### 图 1: CrossLangEdge（危险表面清单）

```zig
// pass.zig — 已有！CallGraphPass 生成
pub const CrossLangEdge = struct {
    caller_name: []u8,
    callee_name: []u8,
    caller_lang: Language,       // .rust/.c/.go/.zig/.cpp
    callee_lang: Language,
    is_ffi_boundary: bool,       // ★ 这是唯一的入口判据
    ptr_args: []u32,            // 哪些参数是指针
};
```

### 图 2: MemoryGraph（指针全生命周期）

```zig
// semantics/memory_graph.zig — 已有！各 pass 写入
pub const MemoryGraph = struct {
    nodes: AutoHashMap(u64, *AllocNode),         // ptr_val → 分配信息

    // ★ 跨函数边（R8.0 新建）
    call_args: ArrayList(CallArgEdge),            // caller_inst, callee_name, arg_ptr, arg_index
    call_rets: ArrayList(CallRetEdge),            // caller_inst, callee_name, ret_ptr
    call_arg_by_ptr: AutoHashMap(u64, ArrayList(u32)),  // ptr → [call_arg indices]
    call_ret_by_callee: AutoHashMap([]const u8, ArrayList(u32)),

    // ★ 关键查询 API（全部已实现）
    getCallArgsForPtr(ptr)     // 这个指针被作为参数传给了哪些调用？
    getCallRetsFromCallee(name) // 这个函数返回了哪些指针？
    isPassedAsArg(ptr)         // bool: 是否流入任何调用的参数？
    isReturnedFromCall(ptr)   // bool: 是否从任何调用返回？
    isLeaked(ptr)              // bool: 分配后逃逸且无配对 call_ret？
    isDoubleFreed(ptr)         // bool: 三层 double-free 检测
    analyzeLifecycle(ptr)      // 完整生命周期报告
};
```

### 缺失的一环：DangerSurfacePass（图驱动入口）

```
当前: 每个 pass 独立扫描所有函数 → 大量噪声
目标: 从 CrossLangEdge 出发 → 沿 MemoryGraph 追溯 → 只分析触达路径
```

***

## 执行计划

### Phase 0: 快速止血 + 核心算法

#### P0-1: reportRiskyCall 位置修复（预计 -200 FP，10 行代码）

**文件**: [ffi\_boundary.zig](src/pass/analysis/ffi_boundary.zig)

**问题**: L261-263 `reportRiskyCall()` 在同语言检查 (L286-290) **之前**执行。
pthread\_mutex\_lock 等 POSIX API 被 zone 分类为 `.ffi`，通过 zone gate，
到达 reportRiskyCall → 直接报告 → 永远走不到同语言跳过逻辑。

**修复**: 将 L261-263 的 `reportRiskyCall` 调用移到 L290（同语言检查）之后。

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] libuv150 FFI unsafe: 67 → < 20
- [ ] curl8 FFI unsafe: 151 → < 40
- [ ] sqlite3 FFI unsafe: 194 → < 50
- [ ] TP 零丢失（openssl\_wrapper 仍 \~17 TP, rust\_sqlite 仍 \~15 TP）
- [ ] libuv150 FFI unsafe: ↓70%+
- [ ] curl8 FFI unsafe: ↓70%+
- [ ] sqlite3 FFI unsafe: ↓70%+

***

#### P0-2: 编译器插桩识别（预计 -135 FP）

**文件**: [ffi\_boundary.zig](src/pass/analysis/ffi_boundary.zig) + [zone\_classifier.zig](src/semantics/zone_classifier.zig)

**问题**: `-D_FORTIFY_SOURCE=2` 下 `__memcpy_chk`/`__strcpy_chk`/`__snprintf_chk` 是编译器自动插入的边界保护函数。它们的存在说明代码**更安全**，但当前当作 unsafe 报告。

**方案**: 在 zone 分类或 ffi\_boundary 中识别 `_chk` 后缀：

- `_chk` 结尾的函数 → 分类为 `.runtime_internal`（或新增 `.compiler_fortify` zone）
- 不进入 FFI unsafe 报告路径

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] sqlite3 unchecked\_copy: \~80 → < 5
- [ ] libuv/curl \_\_memcpy\_chk 报告全部消失
- [ ] TP 零丢失

***

#### P0-3: ★ isOnDangerPath 核心算法 — 全局统一 Gate（预计 -400+ FP，架构核心）

> **这是整个 Graph-Driven 架构的基石。一个函数回答「是否关心这个指针」。**

**文件**: [memory\_graph.zig](src/semantics/memory_graph.zig) + [pass.zig](src/pass/pass.zig)

##### 设计（已整合 nexts.md 3 个修复点）

```zig
/// The ONE question that determines whether we care about a pointer.
///
/// Returns true if ptr_val's data path crosses ANY FFI/unsafe boundary.
/// This is the sole gate between Tier 1 (pass-through) and Tier 2 (strict analysis).
pub const DangerPathKind = enum {
    none,                  // Not on danger path → Tier 1, pass through (统计)
    unsafe_alloc,          // Allocated in .unsafe block → Tier 2, strict
    cross_lang_lifecycle,  // Alloc/free in different languages → Tier 2
    ffi_arg,               // Flows into FFI call as argument → Tier 2
    ffi_ret,               // Returns from FFI call → Tier 2
};

pub fn isOnDangerPath(
    graph: *MemoryGraph,
    ptr_val: u64,
    cross_lang_edges: []const CrossLangEdge,
    visited: *AutoHashMap(u64, void),  // cycle detection for alias recursion
) DangerPathKind {
    // ★ 修复 1: 先查 call_arg/call_ret（覆盖函数参数指针，无 AllocNode 的情况）
    //   C_func(user_data): ffi_callback(user_data) → user_data 是参数不是 malloc
    //   但它流入了 FFI 边界 → 必须检测！不能 early return .none

    // (b): ptr flows into an FFI boundary call as argument
    const arg_indices = graph.getCallArgsForPtr(ptr_val);
    for (arg_indices) |idx| {
        const arg_edge = &graph.call_args.items[idx];
        for (cross_lang_edges) |edge| {
            if (isSameFFICall(edge, arg_edge)) return .ffi_arg;
        }
    }

    // (c): ptr returns from an FFI boundary call
    for (graph.call_rets.items) |ret_edge| {
        if (ret_edge.ret_ptr == ptr_val) {
            for (cross_lang_edges) |edge| {
                if (isSameFFICall(edge, ret_edge)) return .ffi_ret;
            }
        }
    }

    // (a)/(e): 只对有 AllocNode 的 ptr 检查（zone + 跨语言生命周期）
    const node = graph.nodes.get(ptr_val) orelse return .none;
    if (node.zone == .unsafe) return .unsafe_alloc;
    if (node.freed and node.alloc_lang != node.free_lang) {
        return .cross_lang_lifecycle;
    }

    // ★ 修复 2: alias 传递闭包（用 visited set 防 cycle）
    var alias_iter = node.aliases.iterator();
    while (alias_iter.next()) |entry| {
        const alias_ptr = entry.key_ptr.*;
        if (visited.contains(alias_ptr)) continue; // cycle guard
        try visited.put(alias_ptr, {});
        const kind = isOnDangerPath(graph, alias_ptr, cross_lang_edges, visited);
        if (kind != .none) return kind;
    }

    return .none;  // Pure internal operation → Tier 1
}
```

##### 需要 AllocNode 扩展的 3 个字段

```zig
// memory_graph.zig — AllocNode 新增:
pub const AllocNode = struct {
    // ... 现有字段 ...
    zone: ZoneKind,           // ★ 分配发生的 zone（从 getOrComputeZone 取）
    alloc_lang: Language,     // ★ 分配发生的语言（从 ctx.module_language 取）
    free_lang: ?Language,     // ★ 释放发生的语言（trackFree 时填入，? 表示未释放）
};
```

`trackAlloc()` 时从 PassContext 取 `module_language.language` 写入 `alloc_lang`。
`trackFree()` 时同样写入 `free_lang`。成本：多存两个 enum 字段，几乎零开销。

#### P2-4:

MemoryGraph realloc\_chain (old\_ptr → new\_ptr)
trackInstruction realloc: mg.realloc\_chain.put(old, new)
checkDoubleFreeViolation: if mg.realloc\_chain.contains(freed\_ptr) → skip
预计 -30-50 double\_free FP

##### ★ 修复 3: Phase 3 迭代起点优化

不从全部 AllocNode 迭代（O(730) for sqlite3），而是从 **CrossLangEdge 出发反向追溯**：

```
Phase 3 (严格分析):
  for each CrossLangEdge where is_ffi_boundary == true:
    // 找到所有流入此 FFI 调用的指针参数
    for each call_arg where callee_name == edge.callee_name:
      kind = isOnDangerPath(arg_ptr, cross_lang_edges)
      if (kind != .none) → report with kind

    // 找到所有从此 FFI 调用返回的指针
    for each call_ret where callee_name == edge.callee_name:
      kind = isOnDangerPath(ret_ptr, cross_lang_edges)
      if (kind != .none) → report with kind

  sqlite3: ~30 条 CrossLangEdge × ~3 args ≈ 90 次 isOnDangerPath 调用
  vs 旧方式: 730 次 AllocNode 遍历
  → 8× 加速
```

##### 双路径捕获保证

| 场景                                            | 路径 (a) alloc\_lang≠free\_lang |     路径 (b/c) FFI arg/ret     | 结果         |
| --------------------------------------------- | :---------------------------: | :--------------------------: | ---------- |
| C: malloc→func(\&p)→free(p), 全部同语言            |             ✗ 不命中             |             ✗ 不命中            | `.none` 放行 |
| Rust: malloc→c\_func(p)→C: free(p)            |          ✓ .rust ≠ .c         |  ✓ c\_func 在 CrossLangEdge 上 | **报告**     |
| Go: p=C.malloc()→C.CBytes(p)                  |           ✗ 可能都是 .go          |     ✓ C.CBytes 是 cgo FFI     | **报告**     |
| C\_func(user\_data)→ffi\_callback(user\_data) |          无 AllocNode          | ✓ user\_data 流入 FFI callback | **报告**     |

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] 新增 `isOnDangerPath` + `DangerPathKind` 到 memory\_graph.zig
- [ ] AllocNode 扩展 3 字段（zone / alloc\_lang / free\_lang）
- [ ] trackAlloc / trackFree 填充新字段
- [ ] 新增测试：
  - 函数参数指针流入 FFI → 返回 `.ffi_arg`
  - Rust alloc + C free → 返回 `.cross_lang_lifecycle`
  - 纯 C 内部 malloc/free → 返回 `.none`
  - alias 传递：A→B(别名)→B 流入 FFI → A 也返回 `.ffi_arg`
  - cycle detection：A↔B 互相 alias 不死循环
- [ ] TP 零丢失（openssl\_wrapper / rust\_sqlite / gnark\_test intentional bug 全保留）

***

### Phase 1: DangerSurfacePass（核心架构变更）

#### P1-1: 危险表面收集 + 相关分配标记（预计 -300 FP）

**新文件**: `src/pass/analysis/danger_surface.zig`（或集成到现有 pass.zig）

**设计**:

```zig
pub const DangerSurfacePass = struct {
    pub const name = "danger-surface";
    pub const deps = &[_][]const u8{"call-graph"}; // 依赖 CallGraphPass 先跑

    pub fn run(ctx: *PassContext) !void {
        // Step 1: 收集所有危险表面
        var surface = DangerSurface.init(ctx.allocator);
        defer surface.deinit();

        // 1a: 所有 is_ffi_boundary == true 的 CrossLangEdge
        for (ctx.getCrossLangEdges()) |edge| {
            if (edge.is_ffi_boundary) {
                try surface.addFFICall(edge);
            }
        }

        // 1b: 所有 ZoneKind == .unsafe 的函数
        // （Rust unsafe 块、显式标记的不安全区域）
        for (ctx.allFunctions()) |func| {
            const zone = ctx.getOrComputeZone(func);
            if (zone == .unsafe) {
                try surface.addUnsafeFunc(func);
            }
        }

        // Step 2: 沿 MemoryGraph 追溯，标记「相关分配」
        var relevant_allocs = AutoHashMap(u64, void).init(ctx.allocator);
        defer relevant_allocs.deinit();

        for (surface.ff_calls) |ffi| {
            // 对每个 FFI 调用的指针参数:
            //   mg.getCallArgsForPtr(arg_ptr) → 找到 call_arg edge
            //   mg.nodes.get(arg_ptr) → 找到 AllocNode
            //   relevant_allocs.put(alloc_node_id) → 标记为相关
            //
            // 同时向上递归追踪:
            //   如果 arg_ptr 本身是某个 call 的 return 值 (call_ret)
            //   → 继续追溯到上游 alloc
            //   如果 arg_ptr 是 alias → 追溯到原始 alloc
            try surface.traceRelevantAllocs(&ctx.memory_graph, &relevant_allocs, ffi);
        }

        // Step 3: 存入 PassContext，后续 Pass 只分析这些
        ctx.setRelevantAllocs(&relevant_allocs);
        ctx.setDangerSurface(&surface);
    }
}
```

**后续 Pass 改造**: 每个 issue 报告前加 gate:

```zig
if (!ctx.isRelevantAlloc(ptr_val)) {
    // 此指针不在任何危险路径上 → 静默跳过（不是过滤，是不关心）
    return;
}
```

**需要改造的 Pass**:

| Pass             | 文件                       | 改动                                    |
| ---------------- | ------------------------ | ------------------------------------- |
| ptr\_lifetime    | ptr\_lifetime.zig        | memory\_leak / double\_free 报告前加 gate |
| callback\_escape | callback\_escape.zig     | borrow\_escape / CBytes escape 加 gate |
| ffi\_boundary    | ffi\_boundary.zig        | format\_string / unsafe call 加 gate   |
| fp\_precision    | fp\_precision\_guard.zig | invalid\_free / null\_deref 加 gate    |

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] 总 issues: \~1,356 → \~500-700（Phase 0+Phase 1 合计）
- [ ] borrow\_escape: \~143 → \~15（只剩真正逃逸到 FFI 的）
- [ ] format\_string: \~87 → \~5（只剩跨 FFI 边界的非常量格式串）
- [ ] memory\_leak: \~264 → \~50（只报触达 FFI 未释放的）
- [ ] TP 零丢失（intentional bug 全保留）
- [ ] sqlite3 分析时间 < 1s（大量函数直接跳过）

***

#### P1-2: MemoryGraph 增强 — getContentSource 查询（预计 -50 FP）

**文件**: [memory\_graph.zig](src/semantics/memory_graph.zig)

**问题**: 当前 content\_sources 字段存在但无公开查询 API。P1-1 的 traceRelevantAllocs 需要判断指针来源（alloca/constant/global/param/call\_ret）。

**方案**: 新增:

```zig
pub fn getContentSource(graph: *MemoryGraph, ptr_val: u64) ContentSource {
    // 1. 检查 content_sources map（已有字段）
    // 2. 如果 unknown → 检查是否是 alloca 结果（通过 alloc_inst 判断）
    // 3. 如果 unknown → 检查是否是 global variable load
    // 4. 如果未知 → 检查是否通过 call_ret 返回
}
```

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] 新增测试: alloca source → .stack, global load → .global, call\_ret → .call\_ret
- [ ] P1-1 的 traceRelevantAllocs 使用此 API

***

### Phase 2: 精度深化

#### P2-1: 过程间格式串追踪（预计 -30 FP，剩余 format\_string FP 归零）

**前提**: Phase 1 gate 生效后，剩余 format\_string 都是跨 FFI 边界的。

**问题**: sqlite3\_mprintf("SELECT \* FROM %s", user\_input) 格式串经 3 层内部传递后丢失常量信息。

**方案**: 轻量级 summary-based 传播

```zig
// 在 DangerSurfacePass 或独立 summary pass 中:
// 对每个 printf-family 函数调用:
//   fmt_arg = GetOperand(inst, fmt_pos)
//   if (isGlobalConstant(fmt_arg)) → 标记为 SAFE_FMT
//   else if (fmt_arg 来自 function param) → 标记为 DYNAMIC_FMT（需上层确认）
//   存入 FormatSummary map: func_name → {inst_index, safety}
//
// 下层调用点查表: if (callee in FormatSummary and summary[inst].safe) → skip
```

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] sqlite3 format\_string: 80 → < 5（常量格式串全部识别）
- [ ] openssl\_wrapper password printf 仍然报告（真正的 TP）

***

#### P2-2: 自定义分配器配对（预计 -50 FP）

**文件**: [ptr\_lifetime.zig](src/pass/analysis/ptr_lifetime.zig) + [memory\_graph.zig](src/semantics/memory_graph.zig)

**问题**: sqlite3Malloc/sqlite3Free 不匹配 isMallocFunction/isFreeFunction 硬编码列表。

**方案**: 利用 FuzzyMatcher.classify==`.alloc`/`.free` 自动推断项目级配对

```zig
// Phase 0 (扫描阶段): 
//   对模块内所有函数名做 FuzzyMatcher.classify
//   .alloc → 加入 potential_allocs 集合
//   .free  → 加入 potential_frees 集合
//   用命名相似度匹配: (xxxMalloc, xxxFree), (xxxAlloc, xxxDealloc)
//   存入 ctx.project_alloc_pairs
//
// Phase 1 (分析阶段):
//   isMallocFunction → 先查 project_alloc_pairs，再查硬编码列表
//   isFreeFunction → 同上
```

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] sqlite3 memory\_leak 中自定义分配器 FP 减少 ≥ 50%
- [ ] 不引入新的 FP（配对错误宁可漏报不误报）

***

#### P2-3: "跨 FFI 边界的 C escape IR 分析"，而非通用 C escape 分析

#### **文件**: [callback\_escape.zig](src/pass/analysis/callback_escape.zig)

**问题**: `mayRetainInCLanguageAware()` 基于 C\_RETAINING\_FUNCTIONS 名匹配，C 的 `func(&local_var)` 全部误报。

**方案**: 替换名为基于 IR 的 escape 检测

```zig
// 对于 C/C++ caller 的 pointer-arg:
//   1. 取 arg 对应的 LLVM Value
//   2. 在当前函数内扫描该 value 的所有 use:
//      a. store 到 GlobalVariable → ★ 真 escape
//      b. store 到 heap (malloc'd memory) → ★ 可能 escape
//      c. 作为 call @async_func 的参数 → ★ 可能 escape (callback)
//      d. 仅在 stack 上使用 (load/GEP/bitcast) 且函数结束后不再引用
//         → 不是 escape（C 的 output parameter 模式）
//   3. 只有 a/b 才报 borrow_escape, d 直接跳过
```

**这是非白名单方案的核心**——用 IR 证明指针确实逃逸了才报。

**Acceptance**:

- [ ] `zig build test` EXIT: 0
- [ ] curl8 borrow\_escape: 38 → < 8
- [ ] sqlite3 borrow\_escape: 76 → < 10
- [ ] gnark\_test borrow\_escape 中 Go runtime FP 大幅减少

<br />

***

### Phase 3: 性能与工程

#### P3-1: MS 级分析速度（大型项目 < 500ms）

**关键优化**:

1. **Zone cache 命中率提升**: getOrComputeZoneByName 已经缓存，确保无重复计算
2. **DangerSurfacePass 提前过滤**: Phase 1 后大部分函数根本不进入分析管线
3. **MemoryGraph query 索引**: call\_arg\_by\_ptr / call\_ret\_by\_callee 已是 HashMap，O(1) 查询
4. **惰性分析**: 只对 relevant\_allocs 中的指针做 lifecycle 分析

**✅ untodo.md 性能优化已实施 (P0+P1 全部完成)**：

| # | 优化项 | 状态 | 文件 |
|---|--------|------|------|
| P0-1 | 函数级 `isRelevantFunction()` gate | ✅ | pass.zig, danger_surface.zig, callback_escape.zig |
| P0-2 | 共享 callee→inst HashMap 索引 | ✅ | pipeline.zig, call_graph.zig, ffi_boundary.zig |
| P0-3a | PtrLifetime 三遍→单遍 | ✅ | ptr_lifetime.zig |
| P0-3b | CallbackEscape 两遍→单遍 | ✅ | callback_escape.zig |
| P1-4 | call\_ret\_by\_ptr 索引 O(1) | ✅ | memory_graph.zig |
| P1-5 | trackCallArg ArrayList | ✅ | memory_graph.zig |

**profiling 基准**:

| 项目               | Funcs | 优化前时间     | 优化后时间      | 目标时间        |
| ---------------- | ----- | -------- | ----------- | ----------- |
| sqlite3          | 3,346 | \~8.9s (segfault) | \~10-15s (稳定) | **< 500ms** |
| curl8            | \~947 | \~0.7s   | TBD         | **< 200ms** |
| libuv150         | 877   | \~0.18s  | TBD         | **< 100ms** |
| openssl\_wrapper | \~20  | \~0.006s | TBD         | **< 10ms**  |

**Acceptance**:

- [ ] sqlite3 < 500ms（当前 ~10-15s，瓶颈在 FFIBodyCheck/FFIUnsafe 等未优化 pass）
- [ ] 全部 18 文件总时间 < 5s
- [ ] 内存占用稳定（GPA 无泄漏）

***

## 执行顺序与依赖

```
Phase 0 (快速止血 + 核心算法, ~2-3天):
  P0-1 ─── reportRiskyCall 位置修复 (-200 FP)
  P0-2 ─── 编译器插桩 _chk 识别 (-135 FP)
  P0-3 ─── ★ isOnDangerPath 核心算法 + AllocNode 扩展 (-400+ FP)  ← ★ 架构基石
    ↓
Phase 1 (DangerSurfacePass 集成, ~2天):
  P1-1 ─── DangerSurfacePass: CrossLangEdge 出发 → isOnDangerPath → 各 Pass gate
  P1-2 ─── MemoryGraph.getContentSource() API
    ↓
Phase 2 (精度深化, ~3-4天):
  P2-3 ─── C borrow_escape IR 分析 (-80 FP)
  P2-1 ─── 过程间格式串追踪 (-30 FP)
  P2-2 ─── 自定义分配器配对 (-50 FP)
    ↓
Phase 3 (性能, ~1天):
  P3-1 ─── MS 级分析速度（sqlite3 < 500ms）

推荐: P0-1 → P0-2 → P0-3 → P1-1 → P1-2 → P2-3 → P2-1 → P2-2 → P3-1
总计: ~10-12 天
```

***

## Acceptance Criteria（最终）

- [x] **零白名单**: 所有过滤通过图拓扑/IR 语义实现
- [ ] **TP Rate > 60%**: intentional bug 锚点 (openssl\_wrapper + rust\_sqlite + gnark\_test)
- [ ] **FP Rate < 10%**: 源码交叉验证 (sqlite3/curl8/libuv150)
- [ ] **大型项目 < 500ms**: sqlite3 (3346 funcs)
- [ ] **Clean projects ≥ 12/18**: 新增归零项目
- [ ] **`zig build test`** **EXIT: 0**: 全部回归通过
- [ ] **架构清晰**: isOnDangerPath → DangerSurfacePass → 各 Pass gate（单一 Gate 原则）
- [ ] **通用内存放行**: 非 FFI/unsafe 的纯内部操作不报 issue（仅统计）
- [ ] **★ isOnDangerPath 核心算法**: 5 种 DangerPathKind，双路径捕获，alias 传递闭包，cycle detection
- [ ] **函数参数指针不漏检**: 无 AllocNode 的 ptr 通过 call\_arg/call\_ret 路径检测
- [ ] **Phase 3 从 CrossLangEdge 出发**: 不遍历全部 AllocNode，O(危险表面 × 平均路径长度)

***

## Coding Standards

| Rule        | Requirement                                        |
| ----------- | -------------------------------------------------- |
| File size   | <= 1000 lines per file                             |
| Simplicity  | Minimal solution, no over-abstraction              |
| Comments    | English only, code:comment \~ 7:3                  |
| Tests       | happy + boundary + error, esp. language boundaries |
| Naming      | TitleCase type, camelCase fn, snake\_case var      |
| Surgical    | Only change what's necessary                       |
| Goal-driven | Each task has verifiable success criteria          |
| No deletion | Never delete files                                 |
| Public API  | All pub functions have doc comments                |
| Pre-commit  | `zig fmt` + `zig build test` + line count          |

