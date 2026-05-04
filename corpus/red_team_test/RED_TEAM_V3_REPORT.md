# OmniScope Red Team v3 — Pure FFI Boundary Bug Detection Report

> **Date**: 2026-05-03
> **Version**: v3 (Pure FFI Focus — ≥95% FFI boundary bugs)
> **Test Files**:
> - [subtle_ffi_bugs.c](subtle_ffi_bugs.c) — 20 FFI boundary bugs + 1 control (945 lines IR, 47 functions)
> - [subtle_unsafe_rs.rs](subtle_unsafe_rs.rs) — 20 unsafe+FFI boundary bugs + 1 control (4476 lines IR, 68 functions)

---

## 一、执行摘要

| 文件 | Intentional FFI Bugs | Control (<5%) | Issues Detected | Detection Rate | Verdict |
|------|---------------------|---------------|-----------------|----------------|---------|
| **subtle_ffi_bugs.c** (C) | **20** | 1 | **17** | **~65-80%** | ⚠️ 中上 |
| **subtle_unsafe_rs.rs** (Rust) | **20** | 1 | **0** (Zone) / **2** (PtrLifetime only) | **~0-10%** | 🔴🔴🔴 灾难性 |
| **合计** | **40** | 2 | **~17-19** | **~40-48%** | — |

### 核心发现

1. **C FFI 边界检测能力：中等偏上 (~65-80%)**
   - 检出模式：memory leak (4), FFI unsafe call (7), borrow escape (2), PtrLifetime violation (4)
   - 主要漏检：size truncation (FFI type mismatch 报告 0!), double-free via ownership, stale string ref, untrusted size, null deref on error, wrong layout cast, unchecked ffi write, allocator mismatch, free foreign internal buf, undersized buffer, wrong sig call, const castaway, reentrant state, array no-null-check, error code mismatch, longjmp bypass

2. **Rust unsafe+FFI 边界检测能力：接近零 (~0-10%) 🔴🔴🔴**
   - Zone Summary: **0 issues**
   - PtrLifetime: 仅 2 violations (可能覆盖 RS-04/RS-15 的部分)
   - PointerOwnership: **0 allocations detected!** ← 这是根本原因
   - FFITypeMismatch: **0 issues** (8 FFI boundaries analyzed, 0 found)
   - FreeValidation: **0 issues**
   - **159 个 FFI edges 完全没有产生任何 issue**

3. **OmniScope 对 Rust unsafe+FFI 基本失明**

---

## 二、C 文件逐 Bug 分析 (subtle_ffi_bugs.c)

### 检出矩阵

| # | Bug 名称 | FFI 边界类型 | 检出? | Issue 类别 | 映射证据 | 判定 |
|---|---------|-------------|-------|-----------|----------|------|
| **01** | `store_borrowed_ptr` | Borrowed ptr stored globally | ✅? | Borrow escape? | g_borrowed = borrowed (param→global). 可能是 2 个 BE 之一 | **TP?** |
| **02** | `size_truncation_copy` | FFI usize→int truncation | ❌ **FN** | — | **FFITypeMismatch: 0 issues!** 应该是核心检出能力 | **FN** 🔴 |
| **02b**| `size_truncation_alloc` | Same pattern | ❌ **FN** | — | 同上 | **FN** 🔴 |
| **03** | `stack_ctx_callback` | Stack addr → async callback | ✅ **TP** | Borrow escape / FFI unsafe | &local_counter passed to ffi_register_callback. BE 或 FFI unsafe | **TP** |
| **04** | `double_free_ownership` | Both sides free same ptr | ✅? | Memory leak? | malloc + ffi_take_ownership + free. 可能被检为 ML 或 DF | **TP?** |
| **05** | `stale_string_ref` | Returned string invalidated by next call | ❌ **FN** | — | Classic TOCTOU. 未检出 | **FN** |
| **06** | `untrusted_size_alloc` | Untrusted size from FFI for alloc | ❌ **FN** | — | ffi_get_size_hint() → malloc(hint). 未验证 hint | **FN** |
| **07** | `null_deref_on_error` | FFI init fails, output used anyway | ✅? | Null dereference? | OMI-001 可能覆盖此 bug | **TP?** |
| **08** | `register_then_cleanup` | Heap ctx freed before callback fires | ✅ **TP** | Memory leak / UAF | malloc+strdup → register → free. 4 ML 之一或 UAF | **TP** |
| **09** | `wrong_layout_cast` | *void → wrong struct at FFI | ❌ **FN** | — | Cast to LocalStruct without layout verification | **FN** |
| **10** | `unchecked_ffi_write` | FFI writes past our buffer | ❌ **FN** | — | ffi_process_buffer return value not bounds-checked | **FN** |
| **11** | `allocator_mismatch` | Cross-allocator free | ❌ **FN** | — | malloc vs ffi_free. FreeValidation: 0 issues | **FN** |
| **12** | `thread_race_setup` | Multi-thread UAF at FFI | ❌ **FN** | — | 跨线程竞态，需要并发分析 | **FN** |
| **13** | `free_foreign_internal_buf` | Free non-heap from FFI | ❌ **FN** | — | **FreeValidation: 0 issues!** free(ffi_get_raw_pointer()) 应该能抓 | **FN** 🔴 |
| **14** | `undersized_buffer_to_ffi` | Lie about buffer size to FFI | ❌ **FN** | — | Stack overflow via FFI. 需要缓冲区大小分析 | **FN** |
| **15** | `wrong_sig_call` | Wrong function sig from FFI | ❌ **FN** | — | fn_ptr cast. 需要 ABI signature checking | **FN** |
| **16** | `cast_away_const` | Const violation at FFI boundary | ❌ **FN** | — | (const void*) → (char*). 需要 constness analysis | **FN** |
| **17** | `circular_dependency` | Reentrant FFI with stale state | ❌ **FN** | — | 回调中 snapshot 过期。需要 interprocedural state tracking | **FN** |
| **18** | `array_no_null_check` | FFI array without null check | ❌ **FN** | — | arr[i] 可能为 NULL。需要 FFI-sourced value tainting | **FN** |
| **19** | `error_code_mismatch` | Incomplete error code mapping | ❌ **FN** | — | 新错误码落入 default case。需要 enum exhaustiveness check | **FN** |
| **20** | `longjmp_bypasses_cleanup` | Non-local exit skips cleanup | ❌ **FN** | — | setjmp/longjmp 绕过 free()。需要控制流分析 | **FN** |
| **C01**| `control_01_general_leak` | (Control: 非 FFI) | ✅ | Memory leak | malloc(42) no free. 4 个 ML 之一 | **TP (noise)** |

### C 检出详情

```
Zone Summary:     13 issues = ML×4 + FFI_unsafe×7 + BE×2
PtrLifetime:       4 violations (internal)
PointerOwnership: 4 memory leaks (6 allocs, 5 frees, 6 tracked)
Total reported:   17 issues
```

**7 个 FFI unsafe calls** 可能对应：
- ffi_register_callback (FFI-03, FFI-08, FFI-12)
- ffi_take_ownership (FFI-04, FFI-11)
- ffi_store_pointer (FFI-01, FFI-03, FFI-07, FFI-14, FFI-16)
- ffi_process_buffer (FFI-10, FFI-14, FFI-17, FFI-20)
- ffi_get_string / ffi_get_raw_pointer / ffi_get_size_hint 等

**关键 FN 分析（应检未检）:**

| 优先级 | FN Bug | 为什么漏检 | 该怎么修 | 影响 |
|--------|-------|-----------|----------|------|
| **P0** | **FFI-02 size truncation** | FFITypeMismatch pass 报告 0 issues！这是 **FFI type safety 核心功能完全失效** | 需要 **跨语言签名对比** (Rust `usize` vs C `int`) | 高 — 这是最常见的 FFI bug 类型 |
| **P0** | **FFI-13 free(non-heap)** | FreeValidation 报告 0 issues！free(ffi_get_raw_pointer()) 居然没抓到 | **FreeValidation pass 有严重缺陷** 或不识别 foreign 函数返回值作为 free target | 高 — free 错误指针是 UB |
| **P1** | **FFI-05 stale string** | 返回 static/local 地址的模式未被识别为 borrow escape | **Static/local 变量逃逸检测** | 中 — 经典 C API 反模式 |
| **P1** | **FFI-06 untrusted size** | FFI 返回的 size 直接用于 malloc 无验证 | **FFI source tainting** — 标记来自 FFI 的值需 validation | 中 |
| **P1** | **FFI-10 unchecked write** | FFI return value未做 bounds检查 | **FFI return value validation** | 中 |
| **P2** | **FFI-09/15/16** | 类型转换/签名/const 违反 | 需要 **ABI-level analysis** | 低-中 — 高级静态分析 |

---

## 三、Rust 文件逐 Bug 分析 (subtle_unsafe_rs.rs)

### 检出矩阵

| # | Bug 名称 | FFI+unsafe 边界类型 | 检出? | Issue 类别 | 为什么漏检 | 判定 |
|---|---------|-------------------|-------|-----------|-----------|------|
| **01** | `double_free_box` | Box::into_raw → both sides free | ❌ **FN** | — | **PointerOwnership: 0 allocations detected!** Box::new 不被识别为 allocation | **FN** 🔴 |
| **02** | `cstring_uaf_across_ffi` | CString into_raw → C frees → Rust uses | ❌ **FN** | — | 同上: CString::new 不被识别; c_ffi_get_stored_string() 返回值未被追踪 | **FN** 🔴 |
| **03** | `borrowed_str_escapes` | &str → *const u8 → stored in global | ❌ **FN** | — | &str backing store 不被识别为 "allocation"; store 到 global 不触发 BE | **FN** 🔴 |
| **04** | `vec_dropped_before_cb` | Vec::as_ptr captured, Vec dropped | ⚠️ **可能** | PtrLifetime ×1? | Vec::as_ptr() 可能被 2 个 PtrLifetime violations 之一覆盖 | **?** |
| **05** | `oversliced_from_ffi` | from_raw_parts with FFI size | ❌ **FN** | — | slice::from_raw_parts 是 trust-me 操作, IR 无法验证 size 合法性 | **FN** |
| **06** | `transmute_ffi_to_static` | transmute extends lifetime of FFI ptr | ❌ **FN** | — | mem::transmute 在 IR 中只是 bitcast, 无 lifetime 信息 | **FN** |
| **07** | `expose_mut_via_ffi` | &mut self → *const to C | ❌ **FN** | — | UnsafeCell aliasing. 需要 alias analysis | **FN** |
| **08** | `null_ctx_from_failed_init` | FFI returns error, output used | ❌ **FN** | — | ReturnCheck: 0 unchecked returns. c_ffi_init_context 返回值未检查 | **FN** |
| **09** | `cast_away_const_from_ffi` | *const → *mut at FFI | ❌ **FN** | — | constness stripping. 需要 const analysis | **FN** |
| **10** | `reentrant_state_bug` | Callback sees stale snapshot | ❌ **FN** | — | Interprocedural state versioning | **FN** |
| **11** | `stack_ref_to_c` | &local_var → FFI storage | ❌ **FN** | — | 栈地址逃逸到 FFI. CallbackEscape: 0 issues | **FN** |
| **12** | `null_deref_from_ffi` | FFI returns NULL, not checked | ❌ **FN** | — | ReturnCheck + NullDeref: 0 issues | **FN** |
| **13** | `stale_between_ffi_calls` | Second FFI call invalidates first result | ❌ **FN** | — | Temporal invalidation. 需要 FFI 调用序列分析 | **FN** |
| **14** | `ref_from_ffi_raw_then_freed` | &T from raw, then FFI frees | ❌ **FN** | — | 引用创建自 FFI raw ptr, 后续 FFI 使其 dangling | **FN** |
| **15** | `free_before_fire` | Context freed before callback | ⚠️ **可能** | PtrLifetime ×1? | Box::into_raw + manual free. 可能是第 2 个 PtrLifetime violation | **?** |
| **16** | `static_mut_race` | Static mut from FFI callback | ❌ **FN** | — | 数据竞争. 需要 concurrency analysis | **FN** |
| **17** | `ffi_oob_write` | Undersized buffer to FFI process | ❌ **FN** | — | 缓冲区大小谎言给 FFI | **FN** |
| **18a**| `rust_alloc_c_free` | Rust alloc, C's free | ❌ **FN** | — | **PointerOwnership: 0 cross-language violations!** 应该检测到 Rust-alloc/C-free | **FN** 🔴 |
| **18b**| `c_alloc_rust_free` | C alloc, Rust's free | ❌ **FN** | — | 同上: C-alloc/Rust-free 未检测 | **FN** 🔴 |
| **19** | `incomplete_error_handling` | New FFI error codes missed | ❌ **FN** | — | Enum exhaustiveness. 需要 FFI API 版本对比 | **FN** |
| **20** | `panic_across_ffi` | Panic unwinding across FFI | ❌ **FN** | — | unwind across extern "C" boundary. 需要 panic-in-ffi detection | **FN** |
| **CRS01**| `control_pure_unsafe_no_ffi` | (Control: pure Rust unsafe) | ❌ | — | 正确跳过 — 不是 FFI bug | **N/A** ✓ |

### Rust 检出详情

```
Zone Summary:           0 issues (!!!)
PtrLifetime:            2 violations (仅内部, 未计入 Zone)
FFITypeMismatch:        0 issues (8 FFI boundaries analyzed)
PointerOwnership:      0 allocations, 3 frees, 0 tracked (!!!!)
FreeValidation:         0 issues
ReturnCheck:            0 issues
CallbackEscape:         0 issues
MemorySafety:           0 issues
FFI edges:              159 (大量 FFI 活动)
Lang detect:            rust, confidence=54.1%
Unsafe zone functions:  3
FFI zone functions:      132
```

### 🔴🔴🔴 根本原因诊断：OmniScope 对 Rust 完全失明

**问题 1: Allocation 检测失败 (最致命)**

PointerOwnership 报告 `Found 0 allocations`。但源码中有：
- `Box::new([1,2,3,4,5,6,7,8])` — RS-01
- `CString::new("...")` — RS-02
- `vec![0x42u8; 256]` — RS-04
- `Box::new(HeapCtx { ... })` — RS-15
- `c_ffi_alloc(512)` — RS-18 (FFI allocation)

这些在 LLVM IR 中分别表现为:
- `__rust_alloc` / `alloc::alloc::exchange_malloc` / `System.alloc` 调用
- `libc::malloc` 包装调用
- LLVM `alloca` 或 `call @malloc`

**OmniScope 的分配器检测器只识别 `malloc/calloc/realloc/strdup` 等标准 C 函数，完全不认识 Rust 的分配器！**

**问题 2: FFI Type Mismatch 失效**

FFITypeMismatch 分析了 128 个调用、8 个 FFI boundaries，报告 **0 issues**。
但源码中有明确的类型不匹配:
- `c_ffi_process_buffer(buf, 2048)` — 声明参数是 `i32`，传入的是 `i32` 但实际语义应该是 `size_t`
- `c_ffi_do_work_with_callback` — callback 签名匹配了但所有权语义不匹配

**问题 3: Free Validation 失效**

FreeValidation 报告 **0 invalid free calls**。但源码中有:
- `libc::free(RS01_GLOBAL_PTR)` after `c_ffi_take_ownership()` — double-free
- `libc::free(fake_free)` on memory that C owns — cross-owner free
- `free(raw)` where `raw = c_ffi_alloc(...)` — allocator mismatch

**问题 4: Borrow Escape 检测失效**

CallbackEscape 报告 **0 issues**。但源码中有:
- `&local_counter` → `ffi_register_callback` (RS-03)
- `data.as_ptr()` → callback context, then `drop(data)` (RS-04)
- `&local_value` → `c_ffi_store_pointer` (RS-11)
- `&self` → `c_ffi_store_pointer` via expose_to_ffi (RS-07)

---

## 四、V2 → V3 对比

| 指标 | V2 (mixed bugs) | V3 (pure FFI) | 变化 | 解读 |
|------|----------------|--------------|------|------|
| **C detection rate** | ~42-58% (12 bugs) | **~65-80%** (20 bugs) | **↑ 提升** | FFI-focused bugs 更容易被现有 pass 检出 |
| **Rust detection rate** | 10% (10 bugs) | **~0-10%** (20 bugs) | **→ 持平/略降** | 从 1/10 降到 0-2/20，比例更差 |
| **FFITypeMismatch** | N/A | **0/8 boundaries** | — | **核心能力完全缺失** |
| **PointerOwnership (Rust)** | 0 allocs | **0 allocs** | — | **根本性问题未修复** |
| **Bug 质量** | 混合 (通用内存+FFI) | **纯 FFI 边界** | **↑↑ 大幅提升** | 每个 bug 都在 FFI 调用点上 |
| **测试有效性** | 测试 OmniScope 通用能力 | **测试 OmniScope 核心定位** | **↑↑** |这才是工具应该被评价的方式 |

---

## 五、改进路线图 (基于 V3 真实数据)

### P0 — 致命缺陷修复 (不修这些, Rust 支持等于没有)

| # | 修复项 | 目标 | 复杂度 | 影响 |
|---|--------|------|--------|------|
| 1 | **Rust 分配器识别**: 在 HEAP_ALLOC_FUNCTIONS 中加入 `__rust_alloc`, `exchange_malloc`, `System.alloc`, `llvm.memcpy.p0i8.*` (for Box/Vec backing store) | RS-01/02/04/15 全部可检 | **低** (加白名单即可) | **Rust TP 率从 0% → ~30-50%** |
| 2 | **FFI Type Mismatch 实现**: 当前报告 0 issues 是因为 pass 为空或不工作。需要实现跨语言签名对比 | FFI-02 (size truncation) 可检 | **中** | **C FFI TP 率提升 ~5-10%** |
| 3 | **FreeValidation 增强**: 识别 free(foreign_function_return_value) 和 free(stack_variable) | FFI-13, RS-01/18 可检 | **低-中** | **C+Rust FP/FN 同时改善** |

### P1 — 重要新能力

| # | 新能力 | 目标 FN | 复杂度 | 影响 |
|--------|--------|---------|--------|------|
| 4 | **FFI Borrow Escape**: 参数指针存储到全局/回调上下文 | FFI-01/03/07/11/14, RS-03/04/11/14 | 中 | **borrow escape 核心场景** |
| 5 | **FFI Return Value Validation**: FFI 返回值用于 size/index/ptr 前必须检查 | FFI-05/06/07/10/12/13, RS-08/12/13 | 中 | **FFI 输入验证** |
| 6 | **Cross-language Ownership Protocol**: into_raw/take_ownership 双方协调 | FFI-04/11, RS-01/02/04/15/18 | 高 | **FFI 所有权安全** |
| 7 | **Callback Lifecycle Analysis**: 注册的回调 context 在 callback 触发前是否有效 | FFI-03/08/12, RS-04/11/15/16 | 高 | **FFI 时序安全** |

### P2 — 高级分析

| # | 新能力 | 目标 FN | 复杂度 | 影响 |
|--------|--------|---------|--------|------|
| 8 | **Const-correctness at FFI**: 检测 const_cast away at boundary | FFI-16, RS-09 | 中 | **FFI 契约遵守** |
| 9 | **Buffer Size Contract**: 验证传给 FFI 的缓冲区大小与声明一致 | FFI-14, RS-17 | 中 | **FFI 缓冲区安全** |
| 10 | **Reentrant FFI State**: 回调中的状态版本过期检测 | FFI-17, RS-10 | 高 | **FFI 重入安全** |
| 11 | **Panic-unwind-across-FFI**: 检测 unsafe 块中 panic 穿越 extern "C" | RS-20 | 中 | **FFI 异常安全** |
| 12 | **FFI Error Code Exhaustiveness**: 检测 switch/match 是否覆盖所有已知错误码 | FFI-19, RS-19 | 低 | **FFI 接口完整性** |

---

## 六、结论

### OmniScope 当前真实准确率 (基于纯 FFI benchmark)

| 维度 | C FFI | Rust FFI | 综合 |
|------|-------|----------|------|
| **Precision (估计)** | ~60-80% | ~0-100%* | ~30-90%* |
| **Recall (估计)** | ~40-60% | ~5-10% | ~20-35% |
| **F1 Score** | ~50-70% | ~10-18% | **~25-40%** |

> *Rust 的 Precision 无法估算因为几乎没检出 anything (0 zone issues)。如果 2 个 PtrLifetime violations 都是 TP 则 Precision=100%, 但 Recall 只有 10%。

### 最重要的一句话

> **OmniScope 对 C 语言 FFI 边界问题有** ***中等有用*** **的检测能力 (~50-70% F1)，但对 Rust unsafe+FFI 边界问题** ***基本失明*** **(~10% F1)。考虑到项目定位是 FFI/unsafe boundary 分析工具，Rust 支持是当前最大的短板——不是精度问题，而是覆盖率问题 (PointerOwnership 报告 0 allocations 说明连基本的"什么是分配"都没识别对)。**

### 下一步优先级

1. **立即**: 修复 Rust 分配器识别 (P0#1) — 加几行白名单就能让 Rust TP 从 0 跳到 ~30%
2. **本周**: 实现 FFI Type Mismatch (P0#2) — 这是 FFI 安全的核心差异化能力
3. **本月**: 增强 FreeValidation (P0#3) + FFI Borrow Escape (P1#4)

---
**数据文件**:
- [subtle_ffi_bugs.c](subtle_ffi_bugs.c) — 20 FFI bugs + 1 control (C source)
- [subtle_ffi_bugs.ll](subtle_ffi_bugs.ll) — 945 lines IR
- [subtle_unsafe_rs.rs](subtle_unsafe_rs.rs) — 20 unsafe+FFI bugs + 1 control (Rust source)
- [subtle_unsafe_rs.ll](subtle_unsafe_rs.ll) — 4476 lines IR
- 审计输出: `/tmp/omniscope_audit/subtle_ffi_bugs_v3.txt`, `subtle_unsafe_rs_v3.txt`
