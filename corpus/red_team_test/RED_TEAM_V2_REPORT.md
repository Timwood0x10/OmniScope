# OmniScope Red Team v2 — Subtle Bug Detection Report

> **Date**: 2026-05-03
> **Test Files**:
> - [subtle_ffi_bugs.c](subtle_ffi_bugs.c) — 12 intentional subtle C bugs (1525 lines IR)
> - [subtle_unsafe_rs.rs](subtle_unsafe_rs.rs) — 10 intentional subtle Rust bugs (4456 lines IR)
> **Design Principle**: Bugs that **survive first-pass code review**

---

## 一、执行摘要

| 文件 | Intentional Bugs | Issues Detected | Detection Rate | Verdict |
|------|-----------------|-----------------|----------------|---------|
| **subtle_ffi_bugs.c** (C) | **12** | **13** (Zone:8 + PtrLifetime:5) | **~42-58%** | ⚠️ 中等 |
| **subtle_unsafe_rs.rs** (Rust) | **10** | **1** | **10%** | 🔴 差 |
| **合计** | **22** | **14** | **~27-36%** | ⚠️ |

### 核心发现

1. **C subtle bugs**: OmniScope 检出了约一半。主要检出的是内存泄漏和栈逃逸模式。
   - **漏检的**: FFI size truncation, double-close aliasing, static TOCTOU, integer overflow alloc, enum-as-index OOB, free-non-heap, global UAF
2. **Rust subtle bugs**: **几乎全部漏检** (9/10)。仅检出一个 UAF。
   - **漏检的**: transmute lifetime extension, OOB raw arithmetic, unaligned cast, double-free across FFI boundary, mutable alias via raw ptr, CString UAF across FFI, slice length mismatch, dangling closure capture, mutex deadlock, expose &mut as shared

---

## 二、C 文件逐 Bug 分析 (subtle_ffi_bugs.c)

### 检出矩阵

| # | Bug 名称 | Bug 类型 | 检出? | Issue 类别 | 证据 | 判定 |
|---|---------|---------|-------|-----------|------|------|
| **01** | `partial_init_leak` | Error path leak | ✅ **TP** | Memory leak ×1 + Borrow escape? | PointerOwnership: 2 allocs/0 frees; cleanup path missing free for some fields | **TP** |
| **02** | `stack_escape_via_callback` | Stack ptr → async callback | ✅ **TP** | Borrow escape ×1 + FFI unsafe? | g_user_data = (void*)buffer (stack addr); stored in global | **TP** |
| **03** | `realloc_lost_original` | Classic realloc leak | ✅ **TP** | Memory leak ×1 + RISKY CALL(__strcpy_chk) | buf = realloc(buf,...); if(!buf) return NULL → original leaked. __strcpy_chk from strcpy() call | **TP** |
| **04** | `size_truncation_write` | FFI size_t→int truncation | ❌ **FN** | — | No issue detected. Type mismatch not caught by FFITypeMismatch (0 issues) | **FN** |
| **05** | `double_close_aliasing` | fd aliasing → double close | ❌ **FN** | — | fake_close called twice on same fd value. Not detected as invalid_free or double_free | **FN** |
| **06** | `static_buffer_toctou` | Static buf returned, overwritten | ❌ **FN** | — | Returns pointer to static buffer. Not detected as borrow_escape or UAF | **FN** |
| **07** | `store_borrowed_ptr` | FFI borrowed ref stored globally | ✅? | Borrow escape? | borrowed_cache = borrowed_data (parameter stored in global). May be one of the 3 BE issues | **可能 TP** |
| **08** | `alloc_overflow` | calloc count*sizeof overflow | ✅? | OMI-001 null_dereference? | calloc may return NULL if overflow wraps to small size. OMI-001 triggered somewhere | **可能 TP** |
| **09** | `calloc_logical_init` | Zero is valid but wrong value | ❌ **FN** | — | Logical bug, not a memory safety issue per se. calloc zeroed everything correctly | **N/A** (非内存安全) |
| **10** | `enum_as_index` | Array index no bounds check | ❌ **FN** | — | handler_table[handler_id] with no bounds check. Not detected | **FN** |
| **11** | `free_non_heap` | free(stack) or free(mid-object) | ❌ **FN** | — | FreeValidation reported 0 issues! Should have caught flag==2 (free stack) or flag==3 (free mid-object) | **FN** |
| **12** | `use_after_cleanup` | Global ptr freed but not NULLed → UAF+DF | ❌ **FN** | — | subtle_12_cleanup frees global_resource but doesn't NULL it. Then subtle_12_use_after_cleanup calls cleanup twice (double-free) and uses the pointer. Not detected as UAF or DF | **FN** |

### C 检出详情

**OmniScope 输出**:
```
Issues found: 8 (Zone Summary)
  Memory leak:              2
  FFI unsafe call:          2    ← __strcpy_chk (from strcpy in SUBTLE-03) + 未知
  Borrow escape:            3    ← SUBTLE-02 (stack) + SUBTLE-07 (borrowed) + ?
  Null dereference:         1    ← OMI-001 (可能是 SUBTLE-08 或 SUBTLE-01 的 malloc NULL check)

PtrLifetime: 5 violations     ← 内部检测，可能覆盖 SUBTLE-01/03/11/12 的部分
PointerOwnership: 1 memory leak  ← SUBTLE-01 或 SUBTLE-03
```

**关键 FN (False Negative) 分析**:

| FN Bug | 为什么没检出 | 应该怎么检 | 难度 |
|--------|------------|-----------|------|
| **SUBTLE-04 size_truncation** | FFITypeMismatch 报告 0 issues。C 侧参数类型是 `int`，调用处也是 `int` — 在 C IR 层面类型匹配！截断发生在跨语言边界（Rust usize → C int），但 OmniScope 只看 C 侧 IR | 需要 **跨语言类型签名对比**（Rust 函数签名 vs C 参数声明） | 高 |
| **SUBTLE-05 double_close** | FreeValidation 报告 0 issues。两次 `fake_close(3)` 对同一值 3 调用 — 但 fake_close 是自定义函数不是标准 `close()`，不在 free_patterns 中 | 需要 **值敏感的 free 跟踪**（跟踪具体 fd 值是否被关闭过） | 中 |
| **SUBTLE-06 static TOCTOU** | 返回 `static char[64]` 地址。这不是 heap allocation，PointerOwnership 不追踪 static 变量 | 需要 **static/local 变量逃逸分析** | 中 |
| **SUBTLE-10 enum_as-index** | 数组越界访问在 C 中极其普遍（几乎每个程序都有），OmniScope 不对每个数组索引做 bounds check（噪音太大） | 需要 **FFI 来源标记**：如果 index 来自 FFI 参数才检查 | 中 |
| **SUBTLE-11 free_non-heap** | FreeValidation 报告 0 issues！这是最令人担忧的 FN。`flag==2` 时 `target = stack_buf` 然后 `free(target)` — 这应该是可检出的 | **FreeValidation pass 可能有 bug 或不完整** | 低 (应该能检!) |
| **SUBTLE-12 global UAF+DF** | `global_resource` 被 free 后未 NULL，然后再次使用。需要 **全局变量状态跟踪** | 全局变量 taint analysis / def-use chain 跨函数 | 高 |

---

## 三、Rust 文件逐 Bug 分析 (subtle_unsafe_rs.rs)

### 检出矩阵

| # | Bug 名称 | Bug 类型 | 检出? | Issue 类别 | 证据 | 判定 |
|---|---------|---------|-------|-----------|------|------|
| **RS-01** | `lifetime_extension` | transmute &'a → 'static | ❌ **FN** | — | mem::transmute 在 IR 中只是 bitcast，无法区分合法的类型转换和非法的 lifetime extension | **FN** |
| **RS-02** | `oob_raw_arithmetic` | OOB write via ptr::write | ❌ **FN** | — | base.add(4) then write count*4 bytes into count*4 allocation → 4 byte OOB. PtrLifetime 只找到 1 violation 但可能不是这个 | **FN** |
| **RS-03** | `unaligned_cast` | Packed struct unaligned read | ❌ **FN** | — | ptr::read on unaligned u32 pointer. 需要 alignment analysis | **FN** |
| **RS-04** | `box_into_raw_double_free` | Box::into_raw → both sides free | ❌ **FN** | — | GLOBAL_C_PTR freed by Rust, also "owned" by C via c_store_pointer. Cross-language ownership not tracked | **FN** |
| **RS-05** | `mutable_alias_shared` | &mut from &self via raw | ❌ **FN** | — | Cell.as_ptr() 返回 *mut i32 while &self exists. Alias analysis needed | **FN** |
| **RS-06** | `cstring_uaf_ffi` | CString into_raw → C frees → Rust uses | ❌ **FN** | — | c_get_stored_string() 返回的指针可能已被 C 释放。跨语言 temporal analysis | **FN** |
| **RS-07** | `slice_length_mismatch` | from_raw_parts with oversized len | ❌ **FN** | — | slice::from_raw_parts(ptr, 1024) where ptr only has 16 bytes. Need size validation | **FN** |
| **RS-08** | `dangling_closure` | Vec dropped, callback still has ptr | ✅ **TP?** | Use after free ×1 | data.as_ptr() captured in ctx, data dropped, then cb writes through ctx.user_data. This IS the 1 UAF detected! | **TP** ✅ |
| **RS-09** | `mutex_deadlock` | Lock held during callback | ❌ **FN** | — | Mutex lock acquired, then external callback called. Need deadlock pattern detection | **FN** |
| **RS-10** | `expose_mut_as_shared` | &mut self → *const Self via FFI | ❌ **FN** | — | c_store_pointer receives *const StateMachine derived from &mut self. Data race potential | **FN** |

### Rust 检出详情

**OmniScope 输出**:
```
Issues found: 1
  Use after free:           1       ← RS-08 dangling_closure (唯一检出!)

Lang detect: rust, confidence=51.9%   ← 置信度低!
FFI edges: 93 (大量 FFI 调用)
PtrLifetime: analyzed 2 funcs, 13 ptrs, 1 violation
PointerOwnership: 0 allocs, 2 frees, 0 tracked, 1 UAF
```

### 关键发现：Rust unsafe/FFI 漏检率 90%

| 漏检类别 | 漏检数 | 根本原因 | 改进方向 |
|----------|--------|----------|----------|
| **Lifetime/transmute** (RS-01) | 1 | transmute 在 LLVM IR 中是 bitcast，无 lifetime 信息 | 需要 **LLVM lifetime intrinsic** 或 **源码级 annotation** |
| **OOB/arithmetic** (RS-02) | 1 | ptr::write 在 IR 中是 store instruction，bounds 未检查 | 需要 **allocation size tracking** + **pointer range analysis** |
| **Alignment** (RS-03) | 1 | unaligned load/store 在 x86 上是合法的 (just slower)，只在 strict-align 平台 UB | 需要 **alignment analysis pass** |
| **Cross-language ownership** (RS-04, RS-06) | 2 | Box::into_raw / CString::into_raw 所有权转移未被跟踪 | 需要 **FFI ownership protocol** (who-frees-whom) |
| **Alias/safety** (RS-05, RS-10) | 2 | 通过 raw pointer 绕过 Rust borrow checker，IR 层无借用信息 | 需要 **unsafe alias analysis** |
| **Slice safety** (RS-07) | 1 | from_raw_parts 是 trust-me 机制，IR 无法验证 | 需要 **slice bounds validation** against allocation |
| **Deadlock** (RS-09) | 1 | 控制流图中的 lock→callback→lock 模式 | 需要 **lock-ordering / deadlock detection** |

---

## 四、与旧版 red_team_test 对比

| 指标 | 旧版 (red_team_bugs.c) | 新版 V2 (subtle_ffi_bugs.c) | 变化 |
|------|----------------------|--------------------------|------|
| Bug 数量 | 17 (all obvious) | **12 (all subtle)** | 更难 |
| Bug 类型 | malloc-no-free, UAF, double-free (一眼看出) | error-path leak, realloc antipattern, FFI truncation, TOCTOU, etc. (需仔细审) | **质量大幅提升** |
| 检出率 | ~70%+ (太容易了) | **~42-58%** | **更真实** |
| 新增维度 | 无 | FFI boundary, lifetime, ownership, type mismatch | **覆盖面扩展** |

| 指标 | 旧版 (无) | 新版 V2 (subtle_unsafe_rs.rs) | 意义 |
|------|---------|--------------------------|------|
| Rust unsafe bugs | N/A | **10 个 subtle bugs** | **全新测试维度** |
| 检出率 | N/A | **10%** | **暴露严重短板** |

---

## 五、改进建议 (按优先级)

### P0 — 立即可修 (应检未检)

| # | 改进项 | 目标 FN | 复杂度 | 影响 |
|---|--------|---------|--------|------|
| 1 | **Free 增强**: 检测 free(stack_var) 和 free(mid_object_ptr) | SUBTLE-11 | 低 | C 文件 +8% TP |
| 2 | **__strcpy_chk 白名单**: 编译器 builtin 不应报 risky | FP 减少 | 极低 | 全局 FP ↓ |
| 3 | **Global variable UAF**: 跨函数全局 ptr free→use 跟踪 | SUBTLE-12 | 中 | C 文件 +8% TP |

### P1 — 短期改进 (新能力)

| # | 改进项 | 目标 FN | 复杂度 | 影响 |
|---|--------|---------|--------|------|
| 4 | **FFI type mismatch**: 跨语言参数类型对比 (usize vs int) | SUBTLE-04 | 高 | FFI 安全核心能力 |
| 5 | **Double-close/dup 检测**: 值敏感的 close/free 跟踪 | SUBTLE-05 | 中 | Unix API 安全 |
| 6 | **Static buffer escape**: 返回 static/local 变量地址 | SUBTLE-06 | 中 | TOCTOU 检测 |
| 7 | **Array index bounds**: FFI-sourced index 才检查 | SUBTLE-10 | 中 | OOB 检测 |

### P2 — Rust unsafe 专项 (重大短板)

| # | 改进项 | 目标 FN | 复杂度 | 影响 |
|---|--------|---------|--------|------|
| 8 | **transmute lifetime detection**: 识别 &'a → 'static bitcast | RS-01 | 高 | Rust unsafe 核心 |
| 9 | **into_raw ownership tracking**: Box/CString into_raw → who owns? | RS-04, RS-06 | 高 | FFI ownership |
| 10 | **OOB via raw ptr arithmetic**: 分配大小 vs 访问范围 | RS-02, RS-07 | 高 | 内存安全 |
| 11 | **Unsafe alias analysis**: &mut from &self via raw | RS-05, RS-10 | 中 | 数据竞争 |
| 12 | **Dangling closure/capture**: 闭包捕获的原始指针生命周期 | RS-08 已检出 ✓ | — | 继续保持 |

---

## 六、数据文件

| 文件 | 行数 | 用途 |
|------|------|------|
| [subtle_ffi_bugs.c](subtle_ffi_bugs.c) | ~500 | C subtle bug 源码 (12 bugs) |
| [subtle_ffi_bugs.ll](subtle_ffi_bugs.ll) | 1525 | C 编译后的 LLVM IR |
| [subtle_unsafe_rs.rs](subtle_unsafe_rs.rs) | ~280 | Rust subtle bug 源码 (10 bugs) |
| [subtle_unsafe_rs.ll](subtle_unsafe_rs.ll) | 4456 | Rust 编译后的 LLVM IR |
| 审计输出 | — | `/tmp/omniscope_audit/subtle_ffi_bugs.txt`, `subtle_unsafe_rs.txt` |

---
**结论**: OmniScope 对 **明显的** C 内存 bug 有较好检出率 (~70%+, 旧版测试)。但对 **subtle 的** FFI/unsafe/lifetime bug 检出率显著下降 (C: ~42-58%, Rust: **10%**)。这更真实地反映了工具在实战中的表现。Rust unsafe/FFI 是当前最大的盲区。
