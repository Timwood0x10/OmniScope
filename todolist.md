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


2. **补充更多 Rust FFI 测试用例**: 当前 20 bugs 只触发了部分检测路径
3. **trunc 启发式调优**: 可能需要在 MIR 层做额外分析来捕获更多 size 截断场景
4. **集成 CI**: 将 Red Team V3 测试纳入 `zig build test` 自动回归

***

## Project Health Check — FFI Boundary Focus (精简版)

> **日期**: 2026-05-04
> **核心原则**: OmniScope 只关心一件事——数据是否安全地跨越了 FFI/Unsafe 边界 (L12)
> **筛选标准**: 只保留**直接影响 FFI 边界检测能力**的修复项
> **遵循编码规范**: L572-583 (Surgical修改, Pre-commit: `zig fmt` + `zig build test`)
> **完整审计**: 见 [untodo.md](plan/untodo.md) （包含所有 74 个任务的完整版本）

---

### 🎯 必须立即修复 (P0 — 直接影响 Rust/C FFI 边界检测)

#### 🔴 FIX-1: 恢复 Rust FFI 内存操作追踪

**FFI 影响**: ❌ **致命** — `__rust_alloc` 被 noise filter 误杀 → Rust FFI 边界的所有内存操作被跳过 → PointerOwnership = 0

| 位置 | 文件:行号 | 当前代码 | 修复 |
|------|----------|---------|------|
| A | [noise_reduction.zig:194](src/pass/analysis/noise_reduction.zig#L194) | `"__rust_alloc",` | **删除** |
| B | [noise_reduction.zig:195](src/pass/analysis/noise_reduction.zig#L195) | `"__rust_dealloc",` | **删除** |
| C | [noise_reduction.zig:196](src/pass/analysis/noise_reduction.zig#L196) | `"__rust_realloc",` | **删除** |
| D | [noise_reduction.zig:290-291](src/pass/analysis/noise_reduction.zig#L290-L291) | 重复出现 | **删除这2行** |

**验收**:
- [ ] `zig build test` ✅
- [ ] `zig fmt` clean
- [ ] subtle_unsafe_rs.rs → PointerOwnership > 0 allocations

---

#### 🔴 FIX-2: FFI Type Mismatch 接入 CrossLangEdges

**FFI 影响**: ⚠️ **严重** — deps 为空 + 未使用 `ctx.getCrossLangEdges()` → unmangled Rust wrapper 函数不被识别为 FFI boundary

| 位置 | 文件:行号 | 当前代码 | 修复 |
|------|----------|---------|------|
| A | [ffi_type_mismatch.zig:98](src/pass/analysis/ffi_type_mismatch.zig#L98) | `deps = &[_][]const u8{}` | `&[_][]const u8{"call-graph"}` |
| B | [ffi_type_mismatch.zig:172](src/pass/analysis/ffi_type_mismatch.zig#L172) | 仅用 `isFFIBoundary()` | 加 `ctx.getCrossEdgeByCallee(callee) != null or` |

**验收**:
- [ ] `zig build test` ✅
- [ ] `zig fmt` clean
- [ ] `test_double_free_box` 等 unmangled wrapper 被识别为 FFI boundary

---

#### 🔴 FIX-3: hooks.zig Ownership 配对修复

**FFI 影响**: ⚠️ **严重** — 用指令地址做 key → `into_raw(ptr)` / `from_raw(ptr)` 永远配不上 → Rust FFI 边界的所有权泄漏无法检测

| 位置 | 文件:行号 | 当前代码 | 修复 |
|------|----------|---------|------|
| A | [hooks.zig:63](src/registry/hooks.zig#L63) | `@intFromPtr(ctx.inst)` | `ctx.first_arg_ptr_val` |
| B | [hooks.zig:194](src/registry/hooks.zig#L194) | 同上 | 同上 |
| C | [types.zig:105](src/registry/types.zig#L105) | 缺少字段 | 新增 `first_arg_ptr_val: u64 = 0` |

**验收**:
- [ ] `zig build test` ✅
- [ ] `zig fmt` clean
- [ ] RS-01/02/15 ownership leak 可检

---

#### 🟡 FIX-4: Pipeline 依赖声明 (仅影响 FFI 相关 pass)

**FFI 影响**: ⚠️ **中等** — 隐式依赖导致执行顺序脆弱，可能影响 FFI 数据流

**只需修复这些 pass** (其他 pass 与 FFI 无关，暂不处理):

```zig
// ptr_lifetime: 填充 MemoryGraph + 消费 cross_lang_edges
ptr_lifetime.zig:152       → deps = ["call-graph", "danger-surface"]

// ffi_boundary: 消费 cross_lang_edges
ffi_boundary.zig:96         → deps = ["call-graph", "danger-surface"]

// callback_escape: 消费 cross_lang_edges + relevant_functions
callback_escape.zig:349     → deps = ["call-graph", "danger-surface"]

// danger_surface: 需要 MemoryGraph (ptr_lifetime 先执行)
danger_surface.zig:31       → deps = ["call-graph", "ptr-lifetime"]
```

**验收**:
- [ ] `zig build test` ✅
- [ ] `zig fmt` clean
- [ ] 拓扑排序满足 FFI 数据依赖

---

### 📊 影响评估总结

| Fix | FFI 影响 | 代码量 | ROI |
|-----|---------|--------|-----|
| **FIX-1** | ❌→✅ Rust 检测恢复 | ~5 行删除 | **极高** |
| **FIX-2** | FFI boundary 覆盖提升 | ~3 行 | **高** |
| **FIX-3** | Ownership leak 可检 | ~15 行 | **高** |
| **FIX-4** | 执行顺序健壮性 | ~4 行 | **中** |
| **合计** | **Rust FFI TP rate: 0% → 25%+** | **~27 行** | - |

---

### 🚫 已排除的任务（不影响 FFI 边界检测）

以下任务已从本次工作范围移除（保留在 [untodo.md](plan/untodo.md) 作为参考）:

| 类别 | 原因 | 建议处理时机 |
|------|------|-------------|
| **DUP-1~7** (重复代码统一) | 不影响功能正确性，纯维护性 | 未来重构时处理 |
| **BUG-FIX-4/5** (allocator_kb) | 内部一致性问题，不影响 FFI 追踪 | 低优先级 |
| **BUG-FIX-6** (isGoFunction) | Go FFI 占比低，且当前无 Go 测试用例 | 有需求时再修 |
| **BUG-FIX-7** (LLVMInvoke) | C++ 内部问题，不影响 Rust FFI | C++ 测试覆盖后再修 |
| **BUG-FIX-8** (callback_escape) | 回调逃逸检测优化，非核心路径 | P2 |
| **DEAD Code 清理** (~45 functions) | 纯清理工作，不影响功能 | 代码冻结前统一清理 |
| **CTX-1~5** (未利用上下文) | 优化项，非 bug | FIX-1~4 完成后再评估 |

---

### ✅ 执行计划

```
Step 1: FIX-1 (5 分钟)
   ↓ 删除 noise_reduction.zig 中 5 行 __rust_alloc noise 标记
   ↓ 验证: zig build test + subtle_unsafe_rs.rs PointerOwnership > 0
   
Step 2: FIX-4 (3 分钟)
   ↓ 修改 4 个 pass 的 deps 声明
   ↓ 验证: zig build test
   
Step 3: FIX-2 (5 分钟)
   ↓ ffi_type_mismatch.zig 添加 call-graph 依赖 + CrossLangEdges 查询
   ↓ 验证: zig build test + unmangled wrapper 识别
   
Step 4: FIX-3 (10 分钟)
   ↓ hooks.zig 改用指针值做 key + HookContext 新增字段
   ↓ 验证: zig build test + into_raw/from_raw 配对成功

总预计: ~25 分钟, ~27 行代码变更
预期效果: Rust FFI TP rate 从 0% 提升到 25%+
```

---

### 🎯 成功标准

**必须达成**:
- [ ] `zig build test` EXIT: 0
- [ ] `zig fmt` clean (no changes)
- [ ] Rust FFI 测试用例 (subtle_unsafe_rs.rs) 检出 > 0 issues
- [ ] 总代码变更 ≤ 30 行 (surgical 修改)
- [ ] 单文件变更 ≤ 10 行 (符合 ≤1000 行/文件规范)

**禁止事项** (L581):
- ❌ 不删除任何文件
- ❌ 不做过度抽象或重构
- ❌ 不修复与 FFI 边界无关的问题
