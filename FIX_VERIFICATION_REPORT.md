# 修复验证报告

**日期**: 2026-05-29
**分支**: dev
**变更统计**: +3123/-270 行，29个文件

---

## 一、P0级修复验证

### Fix 1: invoke指令处理 — ❌ 未修复

**状态**: 5个关键文件均未正确处理 `LLVMInvoke`

| 文件 | 行号 | 当前代码 | 问题 |
|------|------|----------|------|
| `src/pipeline/pipeline.zig` | 204 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) == 0) continue;` | 只检查CallInst |
| `src/pass/analysis/call_graph.zig` | 215 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {` | 只检查CallInst |
| `src/pass/analysis/ffi/ffi_boundary.zig` | 259 | `if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {` | 只检查CallInst |
| `src/pass/analysis/issue/memory_safety.zig` | 131 | `if (opcode == c.LLVMCall) {` | 缺少LLVMInvoke |
| `src/pass/analysis/issue/free_validation.zig` | 171 | `c.LLVMCall => {` | switch缺少LLVMInvoke分支 |

**项目中已有正确参照**: `callback_escape_core.zig:61`, `rust_ffi_rules_basic.zig:400`, `ch06_obrm.zig:66` 均使用 `isCallOrInvoke()`。

**修复方案**: 使用 `llvm_safe.isCallOrInvoke(opcode)` 替换上述5处。

---

### Fix 2: Rust dealloc RAII假设 — ✅ 已修复

**文件**: `src/semantics/nomicon/ch06_obrm.zig`

- 使用 `shouldMarkAsRAII()` 函数进行上下文判断（line 73）
- 只有 `is_drop_context` 或 `is_compiler_generated` 为true时才标记RAII
- 默认返回 `false`（line 122），保守策略防止误抑制
- 用户unsafe代码中的dealloc不会被标记为RAII

---

### Fix 3: null_dereference suppression gap — ✅ 已修复

**文件**: `src/pass/analysis/noise/issue_suppression.zig:785`

`isRealMemorySafetyBug()` 的switch语句已包含 `null_dereference`：
```zig
.null_dereference, // CWE-476: NULL Pointer Dereference
```

---

### Fix 4: mangled name double-free跳过 — ❌ 未修复

**文件**: `src/types/cpp_fp_detect.zig:121-124`

原始的宽泛跳过逻辑仍然存在：
```zig
const is_mangled = (std.mem.indexOf(u8, first_func, "_ZN") != null or
    std.mem.indexOf(u8, first_func, "$") != null or
    std.mem.indexOf(u8, first_func, "_R") != null);
if (is_mangled) continue;
```

所有编译后的C++/Rust代码的double-free检测仍被跳过。

---

### isDangerousFFIPattern — ✅ 已修复

**文件**: `src/main.zig:649`

不再永远返回true，已实现真实的模式匹配逻辑（约30个危险函数名pattern）。

---

## 二、P1级修复验证

### Fix 5: libc危险函数标记 — ✅ 已修复（有小问题）

**文件**: `src/pass/analysis/ffi/ffi_zone_check.zig`

已实现三层分类系统：
- **Layer 1 Blacklist**: `strcpy`, `strcat`, `sprintf`, `gets`, `system` 等 → `.dangerous`
- **Layer 2 Conditional**: `malloc`, `free`, `memcpy` 等 → `.conditional`
- **Layer 3 Safe**: `strlen`, `strcmp`, `memset` 等 → `.safe`

**遗留问题**:
1. 测试用例（line 605-615）仍期望 `malloc`/`free`/`memcpy` 返回true，与新实现不一致
2. `printf`/`fprintf` 同时出现在blacklist和safe列表中（矛盾）

---

### Fix 6: Nomicon空实现 — ⚠️ 部分实现

| 文件 | 状态 | 详情 |
|------|------|------|
| `ch04_conversions.zig` | 部分 | 检测逻辑存在但 `getTypeSize()` 返回0，size比较永远false |
| `ch05_uninitialized.zig` | 部分 | assume_init检测有效，但 `getTypeSize()` 返回0，alloca大小检查死代码 |
| `ch08_concurrency.zig` | 大部分 | 线程spawn/atomic检测有效，但 `recordResolution()` 是no-op |
| `ch10_pin_box.zig` | 部分 | DI type walking仍返回null，启发式回退有真实逻辑 |

**所有4个文件的 `recordResolution()` 都是no-op** — 检测结果永远不会被记录到SRT。

---

### Fix 7: UAF非danger path — ✅ 已修复

**文件**: `src/pass/analysis/noise/cpp_fp_reduction.zig:279-309`

实现梯度置信度策略：
- 基础0.8，非danger path × 0.6 = 0.48
- `isHighRiskInternalUAF` boost +0.25
- `isSameFunctionFreeThenUse` boost +0.15
- 阈值0.75以上仍报告（severity为medium）

---

### Fix 8: mangled name子串匹配 — ❌ 未修复

**文件**: `src/pass/analysis/noise/noise_reduction.zig:285-484`

仍使用 `indexOf` 子串匹配，`"Iterator"`, `"next"`, `"panic_"` 等pattern仍过于宽泛。

---

## 三、其他问题验证

### `__` 前缀抑制 — ❌ 未修复

**文件**: `src/pass/analysis/noise/issue_suppression.zig:347`

```zig
if (startsWith(func, "__")) return true;
```

所有 `__` 开头的函数仍被无条件抑制。

### runtime_internal强制LOW — ⚠️ 部分修复

**文件**: `src/types/pass_types.zig:636`

P19-12规则未变（runtime_internal强制LOW），但后续risk suppression对核心内存安全bug有豁免。问题是severity在P19-12已被提前降到LOW。

### memory_leak基础分 — ❌ 未修复

**文件**: `src/diag/confidence_scorer.zig:66`

```zig
.memory_leak => 0.45,
```

仍低于0.50的informational阈值。

### Dead Code清理 — ❌ 未清理

11个dead code文件全部仍存在，均未删除。

---

## 四、总结

| 修复项 | 状态 | 优先级 |
|--------|------|--------|
| invoke指令处理 | ❌ 未修复 | P0 |
| Rust dealloc RAII | ✅ 已修复 | P0 |
| null_dereference gap | ✅ 已修复 | P0 |
| mangled name double-free | ❌ 未修复 | P0 |
| isDangerousFFIPattern | ✅ 已修复 | P0 |
| libc危险函数 | ✅ 已修复（测试不一致） | P1 |
| Nomicon空实现 | ⚠️ 部分实现（recordResolution是no-op） | P1 |
| UAF danger path | ✅ 已修复 | P1 |
| 子串匹配精确化 | ❌ 未修复 | P2 |
| `__`前缀抑制 | ❌ 未修复 | P2 |
| runtime_internal豁免 | ⚠️ 部分修复 | P2 |
| memory_leak基础分 | ❌ 未修复 | P2 |
| Dead Code清理 | ❌ 未清理 | P3 |

**P0修复完成率: 3/5 (60%)**
**P1修复完成率: 2/4 (50%)**
**整体修复完成率: 5/13 (38%)**

---

## 五、仍需修复的关键问题

### 立即修复（P0）

1. **invoke指令处理** — 替换5处 `LLVMIsACallInst` 为 `isCallOrInvoke()`
2. **mangled name double-free** — 删除 `cpp_fp_detect.zig:121-144` 的宽泛跳过

### 尽快修复（P1）

3. **Nomicon recordResolution** — 4个文件的no-op需要接入SRT
4. **Nomicon getTypeSize** — ch04/ch05的返回0需要实现真实size查询
5. **libc测试用例** — 更新 `ffi_zone_check.zig:605-615` 的测试
6. **printf双重列表** — 解决blacklist和safe列表的矛盾

### 后续修复（P2）

7. 子串匹配改startsWith
8. `__`前缀改为已知builtin列表
9. runtime_internal对核心安全bug豁免
10. memory_leak基础分提高到0.55
11. 删除11个dead code文件
