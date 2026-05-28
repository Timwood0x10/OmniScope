# 激进过滤策略验证报告 — 真实Bug被漏杀风险分析

**日期**: 2026-05-28
**分支**: dev
**审计范围**: 噪音过滤、FP Precision Guard、语义分类、Severity降级、Early-exit机制

---

## 概述

OmniScope 存在一个 **7层叠加的过滤体系**，每层都可以独立抑制issue。经验证，多条过滤规则存在 **过于激进** 的问题，会导致真实安全bug被漏杀。以下按严重性排列。

---

## 一、确认会漏杀真实Bug的规则（严重）

### 1.1 所有Rust `__rust_dealloc` 调用无条件标记为RAII

**文件**: `src/semantics/nomicon/ch06_obrm.zig:57-62`

```zig
const kind: SemanticKind = if (is_drop_ctx)
    .raii_drop_release
else if (isTailDealloc(inst))
    .raii_drop_release
else
    .raii_drop_release; // All Rust dealloc is RAII by default
```

**问题**: 无论 `is_drop_ctx` 和 `isTailDealloc` 结果如何，所有 `__rust_dealloc` 都被标记为 `.raii_drop_release`。Issue Gate的R-3规则会抑制所有标记为RAII的UAF：

```zig
// issue_gate.zig:63
if (semantic_kind == .raii_drop_release) return true; // suppress
```

**被漏杀的真实Bug**:
- unsafe代码中手动调用 `Box::from_raw` 后再次dealloc → double-free被忽略
- drop glue之外的dealloc（可能是double-free的一部分）被当作正常scope-end清理
- 第三方库中的错误dealloc模式被自动解释为安全

**修复方案**:
```zig
const kind: SemanticKind = if (is_drop_ctx)
    .raii_drop_release
else if (isTailDealloc(inst))
    .raii_drop_release
else
    .manual_dealloc; // 标记为手动释放，不自动抑制
```
同时在issue_gate.zig中对 `.manual_dealloc` 不做RAII抑制。

---

### 1.2 `invoke`指令在整个FFI检测链中被遗漏

**文件**: 3个关键位置

| 位置 | 行号 | 代码 |
|------|------|------|
| `src/pipeline/pipeline.zig` | 204 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) == 0) continue;` |
| `src/pass/analysis/call_graph.zig` | 215 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {` |
| `src/pass/analysis/ffi/ffi_boundary.zig` | 259 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {` |

**问题**: LLVM IR有两种调用指令：`call`（普通调用）和`invoke`（带异常处理的调用）。以上三处只检查 `LLVMIsACallInst`，完全忽略 `invoke`。

C++的try/catch块和Rust的panic/unwrap路径使用 `invoke`。如果FFI调用只出现在异常处理路径上，整个FFI分析会被跳过。

**被漏杀的真实Bug**:
- C++ try块中的FFI调用（如 `try { rust_callback(); } catch (...) {}`）
- Rust unwrap路径中的跨语言调用
- 任何异常处理路径上的内存安全问题

**项目中已有正确处理的参照**:
```zig
// rust_ffi_rules_basic.zig:400 — 正确
if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

// callback_escape_core.zig:61 — 正确
if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
```

**修复方案**: 创建统一辅助函数并替换所有3处：
```zig
fn isCallOrInvoke(inst: c.LLVMValueRef) bool {
    if (c.LLVMIsACallInst(inst) != 0) return true;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    return opcode == c.LLVMInvoke;
}
```

---

### 1.3 `null_dereference`在suppression guard中缺失

**文件**: `src/pass/analysis/noise/issue_suppression.zig:737-764`

`isRealMemorySafetyBug()` 的switch语句保护了 `use_after_free`, `double_free`, `invalid_free`, `memory_leak` 等，但 **没有保护 `null_dereference`**。

同时，`src/types/pass_types.zig:714` 的 `is_core_memory_safety_bug` 白名单 **包含了 `null_dereference`**。

**问题**: `null_dereference` 在P16-1层被保护不被降级，但在更早的suppression层（Pattern G/H）会被完全消除。一个 `null_dereference` 在 `__` 前缀函数或stdlib函数中会被静默抑制。

**被漏杀的真实Bug**:
- `__my_internal_api()` 中的空指针解引用（CWE-476）
- stdlib包装函数中的空指针解引用

**修复方案**: 在 `issue_suppression.zig` 的 `isRealMemorySafetyBug()` 中添加 `null_dereference`：
```zig
.null_dereference => return true,
```

---

### 1.4 编译后C++/Rust代码的double-free检测被完全禁用

**文件**: `src/types/cpp_fp_detect.zig:121-124`

```zig
const is_mangled = (std.mem.indexOf(u8, first_func, "_ZN") != null or
    std.mem.indexOf(u8, first_func, "$") != null or
    std.mem.indexOf(u8, first_func, "_R") != null);
if (is_mangled) continue;
```

**问题**: 函数名包含 `_ZN`（C++ Itanium mangling）、`$`（Rust legacy mangling）或 `_R`（Rust v0 mangling）时，直接跳过double-free检测。由于编译后的C++/Rust函数名几乎都是mangled的，这条规则**禁用了对所有编译后C++/Rust代码的double-free检测**。

**被漏杀的真实Bug**:
- C++ STL容器析构中的double-free
- Rust Drop实现中的double-free
- 任何编译后的跨语言double-free

**修复方案**: 删除此规则，改用更精确的条件：
```zig
// 只跳过已知的runtime drop glue，不跳过所有mangled函数
if (isKnownDropGlue(first_func)) continue;
```

---

### 1.5 libc危险函数在C模块中被标记为SAFE

**文件**: `src/semantics/zone_classifier.zig:219-221`

```zig
if (isLibcFunction(func_name)) {
    return .safe;
}
```

`isLibcFunction`（`zone_lang_cpp.zig:49-67`）将 `strcpy`, `strcat`, `sprintf`, `memcpy`, `memset` 等标记为safe。

**问题**: 这些函数是C代码中最危险的函数（CWE-120缓冲区溢出），但在C模块中被完全跳过分析。

**被漏杀的真实Bug**:
- `strcpy` 缓冲区溢出
- `sprintf` 格式化字符串漏洞
- `memcpy` 越界读写

**修复方案**: 将高危libc函数从safe列表中移除：
```zig
// 从 isLibcFunction 中移除: strcpy, strcat, sprintf, vsprintf, memcpy, memmove
// 保留: strlen, strcmp, strncmp, memcmp 等只读函数
```

---

### 1.6 Nomicon Ch4/Ch5/Ch8/Ch10 检测为空实现

**文件**:

| 文件 | 章节 | 覆盖的unsafe pattern | 状态 |
|------|------|---------------------|------|
| `src/semantics/nomicon/ch04_conversions.zig` | Ch4 | transmute, repr(C), from_raw | **空placeholder** |
| `src/semantics/nomicon/ch05_uninitialized.zig` | Ch5 | MaybeUninit::assume_init() | **空placeholder** |
| `src/semantics/nomicon/ch08_concurrency.zig` | Ch8 | Send/Sync违规, data race | **空placeholder** |
| `src/semantics/nomicon/ch10_pin_box.zig` | Ch10 | Interior Mutability | DI type walking返回null |

Ch10的具体问题（`ch10_pin_box.zig:118-135`）：
```zig
fn getDIType(value: c.LLVMValueRef) c.LLVMMetadataRef {
    _ = value;
    return null;  // Always returns null!
}
```

**被漏杀的真实Bug**:
- `transmute` 类型混淆导致的内存安全问题
- `MaybeUninit::assume_init()` 未初始化内存使用
- `Send`/`Sync` 违规导致的数据竞争
- `UnsafeCell`/`Cell`/`RefCell`/`Mutex` 的Interior Mutability问题

**修复方案**: 优先实现Ch5（MaybeUninit，最常见的UB来源）和Ch8（并发安全）。

---

## 二、高风险过滤规则（可能漏杀真实Bug）

### 2.1 UAF只检测danger path，忽略纯语言内部UAF

**文件**: `src/pass/analysis/noise/cpp_fp_reduction.zig:240-252`

```zig
const mg_danger = ctx.isOnDangerPathFull(@as(u64, ptr_id));
if (!mg_danger) {
    diag.debug("UAF-SKIP: ptr {d} not on danger path (pure internal)", .{ptr_id});
    continue;
}
```

**问题**: 只有在"danger path"（跨语言生命周期、FFI参数/返回值）上的UAF才会被报告。同一语言内部的UAF（如 `free(ptr); use(ptr);`）被完全忽略。

**修复方案**: 降低非danger path UAF的置信度而非完全跳过：
```zig
if (!mg_danger) {
    confidence *= 0.6; // 降低置信度但不跳过
}
```

### 2.2 Double-Free检测中不同Basic Block自动跳过

**文件**: `src/types/cpp_fp_detect.zig:134-139`

```zig
if (!is_same_bb) {
    diag.debug("DOUBLE-FREE-SKIP: ... multi-path cleanup", .{...});
    continue;
}
```

**问题**: 假设不同BB中的多次free一定是"多路径清理"（非bug），但真实的double-free完全可能出现在不同分支中。

**修复方案**: 改为降低置信度而非跳过：
```zig
if (!is_same_bb) {
    confidence *= 0.7; // 跨分支double-free置信度降低但不跳过
}
```

### 2.3 `isZigSafeCimport` 将安全关键C函数标记为safe

**文件**: `src/pass/analysis/ffi/ffi_zone_check.zig:82-125`

以下函数被标记为"safe Zig-C import"：

| 函数 | CWE风险 | 行号 |
|------|---------|------|
| `malloc`, `calloc`, `realloc`, `free` | CWE-252, CWE-415 | 86-88 |
| `strcpy`, `strcat`, `sprintf`, `vsprintf` | CWE-120 | 84, 92 |
| `printf`, `fprintf`, `scanf`, `fscanf` | CWE-134 | 91, 97 |
| `system`, `getenv` | CWE-78 | 122-123 |

匹配使用 `indexOf`（子串匹配），`my_malloc_aligned` 也会匹配 `malloc`。

**修复方案**: 从safe列表中移除高危函数，或改为 `exact` 匹配。

### 2.4 `isLikelyIntentionalPattern` 按callee名过滤

**文件**: `src/pass/analysis/ffi/ffi_zone_check.zig:302-334`

| Pattern | 匹配方式 | 误杀示例 |
|---------|---------|----------|
| `"safe_"` | startsWith | `safe_parse_buffer()` 中的真实溢出 |
| `"expected"` | contains | `unexpected_free_handler` |
| `"deliberate"` | contains | `deliberately_vulnerable_test_helper` |
| `"intentional"` | contains | 合法函数名 |

**问题**: 检查的是callee函数名，不是caller。第三方库函数 `safe_memcpy` 中的真实缓冲区溢出会被静默抑制。

**修复方案**: 改为检查caller而非callee，或使用更精确的匹配（如mangled name pattern）。

### 2.5 非FFI路径的memory leak实际上不可见

**文件**: `src/pipeline/pipeline.zig:309`, `src/diag/confidence_scorer.zig:61`

置信度阈值：
- `memory_leak` 基础分: **0.45**（低于0.50的informational阈值）
- 非FFI路径leak: **0.50**（恰好在边界）
- 条件分配leak: **0.50 × 0.75 = 0.375**（informational）

Informational级别的issue不会打印到控制台。

**修复方案**: 提高memory_leak基础分到0.55，或降低informational阈值到0.40。

### 2.6 `runtime_internal` surface强制降级为LOW

**文件**: `src/types/pass_types.zig:636-639`

```zig
if (surface == .runtime_internal) {
    issue.severity = .low;
}
```

**问题**: 如果surface classifier将用户函数误分类为 `compiler_generated`（如mangled name、缺少debug info），`use_after_free` 或 `double_free` 会被强制降为LOW。P16-1核心安全保护不覆盖此规则。

**修复方案**: 对核心内存安全bug豁免P19-12降级：
```zig
if (surface == .runtime_internal and !is_core_memory_safety_bug) {
    issue.severity = .low;
}
```

### 2.7 `__` 前缀函数过于宽泛的抑制

**文件**: `src/pass/analysis/noise/issue_suppression.zig:348`

```zig
if (startsWith(func, "__")) return true;
```

**问题**: 所有以 `__` 开头的函数都被抑制，包括用户自定义的 `__my_ffi_bridge` 等。非核心内存安全问题（如 `buffer_overflow`, `command_injection`）在此类函数中被完全抑制。

**修复方案**: 只抑制已知的compiler builtin前缀（`__asan_`, `__tsan_`, `__ubsan_` 等），不抑制所有 `__` 前缀。

### 2.8 Mangled name子串匹配过于宽泛

**文件**: `src/pass/analysis/noise/noise_reduction.zig:285-484`

使用 `indexOf`（子串匹配）的危险pattern：

| 行号 | Pattern | 误杀示例 |
|------|---------|----------|
| 298 | `"Iterator"` | `MyIterator`, `FileIterator` |
| 300 | `"next"` | `getNextBuffer`, `nextStep` |
| 301 | `"iter"` | `writeIteratively` |
| 290 | `"panic_"` | `handle_panic_error` |
| 306 | `"fmt::"` | `my_fmt::utils` |
| 389 | `"posix."` | `posix_compatibility_layer` |

**修复方案**: 将 `indexOf` 改为 `startsWith` 或精确匹配。

---

## 三、中等风险规则

### 3.1 Issue Gate的RAII误分类

**文件**: `src/pass/filter/issue_gate.zig:63`

```zig
if (semantic_kind == .raii_drop_release) return true; // suppress UAF
```

如果SRT错误地将手动free标记为 `raii_drop_release`（如规则1.1所述），真实UAF会被抑制。

### 3.2 `into_raw` 白名单使用contains匹配

**文件**: `src/pass/filter/fp_whitelist.zig:59`

```zig
.{ .pattern = "into_raw", .kind = .contains, ... }
```

`my_custom_into_raw_wrapper` 中的真实bug会被抑制。应改为 `.exact` 或 `.prefix` 匹配。

### 3.3 `memory_leak` 被排除在核心安全白名单外

**文件**: `src/types/pass_types.zig:704-718`

P16-3故意将 `memory_leak` 排除在 `is_core_memory_safety_bug` 外。编译器生成代码中的非CRITICAL memory_leak会被完全抑制。

### 3.4 Surface classifier的 `/src/` 路径过度匹配

**文件**: `src/semantics/surface_classifier/debug_origin.zig:188`

```zig
if (std.mem.indexOf(u8, dir, "/src/") != null) return .user_code;
```

第三方vendored依赖（如 `/project/vendor/lib/src/lib.rs`）被误分类为user_code。

### 3.5 `has_ffi_boundary` 是死字段

**文件**: `src/types/pass_types.zig:226`

在 `surface_classifier_pass.zig` 中设置，但整个代码库中没有任何地方读取此字段做决策。

---

## 四、过滤层冲突/不一致

| 位置A | 位置B | 冲突 |
|-------|-------|------|
| `issue_suppression.zig:458` | `noise_reduction.zig:228` | `__rust_dealloc` 在A中被视为runtime shim（抑制），B中注释说"NOT noise" |
| `intrinsic_filter.zig:99` | `noise_reduction.zig:279` | `llvm.mem*` 在A中标记为suppress=true，B中所有`llvm.*`统一返回true，覆盖细粒度分类 |
| `pass_types.zig:714` | `issue_suppression.zig:737` | `null_dereference` 在P16-1保护但在suppression层缺失 |

---

## 五、修复优先级

| 优先级 | 问题 | 文件 | 影响 |
|--------|------|------|------|
| **P0** | invoke指令遗漏 | pipeline.zig, call_graph.zig, ffi_boundary.zig | C++/Rust异常路径FFI完全漏检 |
| **P0** | Rust dealloc无条件RAII | ch06_obrm.zig:57 | unsafe代码double-free/UAF漏检 |
| **P0** | mangled name跳过double-free | cpp_fp_detect.zig:121 | 所有C++/Rust double-free漏检 |
| **P0** | null_dereference suppression gap | issue_suppression.zig:737 | stdlib/__函数中null deref漏检 |
| **P1** | libc危险函数标记safe | zone_classifier.zig:219 | strcpy/sprintf等溢出漏检 |
| **P1** | Nomicon Ch4/5/8/10空实现 | nomicon/目录 | 4类Rust unsafe bug无覆盖 |
| **P1** | UAF只检测danger path | cpp_fp_reduction.zig:240 | 纯语言内部UAF漏检 |
| **P1** | isZigSafeCimport | ffi_zone_check.zig:82 | Zig-C边界经典C漏洞漏检 |
| **P2** | runtime_internal强制LOW | pass_types.zig:636 | 误分类函数bug降级 |
| **P2** | __前缀过于宽泛 | issue_suppression.zig:348 | 用户__函数bug被抑制 |
| **P2** | mangled name子串匹配 | noise_reduction.zig:285 | 大量用户代码被误杀 |
| **P2** | memory leak不可见 | confidence_scorer.zig:61 | 非FFI leak不打印 |
| **P3** | into_raw contains匹配 | fp_whitelist.zig:59 | 自定义wrapper bug漏检 |
| **P3** | has_ffi_boundary死字段 | pass_types.zig:226 | 资源浪费 |

---

## 六、建议立即执行的修复

### Fix 1: 统一invoke处理（~30分钟）

创建辅助函数并替换所有位置：

```zig
// src/ir/view.zig 或 src/common/utils.zig
pub fn isCallOrInvoke(inst: c.LLVMValueRef) bool {
    if (c.LLVMIsACallInst(inst) != 0) return true;
    return c.LLVMGetInstructionOpcode(inst) == c.LLVMInvoke;
}
```

替换：
- `pipeline.zig:204`
- `call_graph.zig:215`
- `ffi_boundary.zig:259`
- `pointer_ownership.zig:284`
- `buffer_overflow.zig:105`
- `memory_safety.zig:131`
- `free_validation.zig:325`
- `malloc_check.zig:116`
- `taint_propagation.zig:791`

### Fix 2: 修复Rust dealloc RAII假设（~15分钟）

```zig
// ch06_obrm.zig:57-62
const kind: SemanticKind = if (is_drop_ctx)
    .raii_drop_release
else if (isTailDealloc(inst))
    .raii_drop_release
else
    .manual_dealloc; // 不再无条件RAII
```

### Fix 3: 修复null_dereference suppression gap（~5分钟）

```zig
// issue_suppression.zig:737 在switch中添加
.null_dereference => return true,
```

### Fix 4: 删除mangled name double-free跳过（~5分钟）

```zig
// cpp_fp_detect.zig:121-124 — 删除整个is_mangled检查块
```

### Fix 5: 修复libc safe标记（~10分钟）

从 `zone_lang_cpp.zig` 的 `isLibcFunction` 中移除：`strcpy`, `strcat`, `sprintf`, `vsprintf`, `memcpy`, `memmove`, `gets`。

---

**建议Phase 1（Fix 1-4）立即执行，总计约1小时，可修复最高风险的4个漏杀问题。**
