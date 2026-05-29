# 深度验证报告 — 修复质量和遗留问题

**日期**: 2026-05-29
**编译状态**: ✅ `zig build` 通过
**测试状态**: ⚠️ 77/78 通过，6个测试文件编译失败

---

## 一、编译和测试状态

### 编译
`zig build` 成功通过，无错误。

### 测试（77/78 通过，6个文件编译失败）

| 失败类型 | 文件 | 原因 |
|----------|------|------|
| 运行时失败 | `tests/semantic_resolution_test.zig:59` | `stats.total_nodes == 1` 断言失败 |
| 编译失败 | `tests/unit/p0_regression.zig` | `@import("../../src/...")` 路径不允许 |
| 编译失败 | `tests/unit/p1_regression.zig` | 同上 |
| 编译失败 | `tests/unit/p2_enhancement.zig` | 同上 |
| 编译失败 | `tests/unit/boundary_conditions.zig` | 同上 + `var` 应改 `const` |
| 编译失败 | `src/root.zig` 测试 | Zig 0.15.2 格式字符串API变更 |

**根因**: 4个unit test文件使用 `../../src/` 相对路径直接导入源文件，Zig模块系统不允许此操作。应改为通过 `@import("OmniScope")` 模块导入。

### 新增测试文件

| 文件 | 集成状态 | 问题 |
|------|----------|------|
| `tests/p1_critical_fix_test.zig` | ❌ 未集成到build.zig | `isHighRiskInternalUAF` 非pub会导致编译失败 |
| `verify_p1_fixes.zig` | ❌ 未集成到build.zig | 自包含副本，与源码脱节 |

---

## 二、invoke指令处理 — 完整遗漏清单

### 已确认的5处遗漏（仅检查LLVMCall，不检查LLVMInvoke）

| # | 文件 | 行号 | 当前代码 | 功能 | 严重性 |
|---|------|------|----------|------|--------|
| 1 | `ptr_lifetime/allocation_classifier.zig` | 153 | `if (opcode != c.LLVMCall) return .unknown;` | 分类释放操作类型 | **高** |
| 2 | `types/ownership_analysis.zig` | 328 | `c.LLVMCall => {` | 构建所有权流图 | **高** |
| 3 | `issue/malloc_check.zig` | 175 | `if (opcode == c.LLVMCall or ...)` | 检测未检查的malloc | 中 |
| 4 | `semantics/patterns/heap_provenance.zig` | 299 | `c.LLVMCall => classifyAllocationCall(...)` | 追踪堆来源 | 中 |
| 5 | `issue/malloc_check.zig` | 290 | `c.LLVMCall => "call"` | 显示名称 | 低 |

**注意**: `pipeline.zig:204`、`call_graph.zig:215`、`ffi_boundary.zig:259` 的 `LLVMIsACallInst` 已被移除，但可能已替换为opcode检查方式（需确认是否同时检查了LLVMInvoke）。

### 项目中已正确处理的参照（60处使用isCallOrInvoke）

`callback_escape_core.zig`, `cpp_fp_helpers.zig`, `rust_ffi_rules_basic.zig`, `provenance.zig`, `ptr_lifetime.zig`, `allocation_classifier.zig`（部分）, `taint_propagation.zig`, `ch06_obrm.zig` 等。

---

## 三、Nomicon模块实现质量

### 完全实现（可工作）

| 文件 | 函数 | 状态 |
|------|------|------|
| `ch04_conversions.zig` | `detect()`, `analyzeBitcast()`, `analyzePtrIntConversion()` | ✅ 完整 |
| `ch04_conversions.zig` | `getTypeSize()`, `recordResolution()` | ✅ 完整 |
| `ch06_obrm.zig` | `detect()`, `shouldMarkAsRAII()` | ✅ 完整 |
| `ch08_concurrency.zig` | `detect()`, `isThreadSpawnPattern()`, `isAtomicOperation()` | ✅ 完整 |
| `ch08_concurrency.zig` | `analyzeThreadSpawn()`, `analyzeAtomicUsage()` | ✅ 完整 |
| `ch08_concurrency.zig` | `recordResolution()` | ✅ 完整 |

### 部分实现（有简化启发式）

| 文件 | 函数 | 问题 |
|------|------|------|
| `ch05_uninitialized.zig` | `analyzeAssumeInitUsage()` | 标记所有assume_init调用（无数据流验证），`func_name`参数被忽略 |
| `ch05_uninitialized.zig` | `analyzeAllocWithoutInit()` | 只检查下一条指令（非完整def-use链），`func_name`参数被忽略 |
| `ch05_uninitialized.zig` | `analyzePotentialUninitLoad()` | 使用size>16字节启发式（非初始化追踪） |

### Dead Path（整条检测链失效）

| 文件 | 函数 | 问题 |
|------|------|------|
| `ch10_pin_box.zig` | `getDIType()` | ⚠️ 始终返回null |
| `ch10_pin_box.zig` | `getDITypeName()` | ⚠️ 始终返回null |
| `ch10_pin_box.zig` | `getDIBaseType()` | ⚠️ 始终返回null |
| `ch10_pin_box.zig` | `isInteriorMutableThroughChain()` | ❌ 因getDIType返回null永远返回false |

**影响**: Interior Mutability检测的主策略（DI type chain walking，置信度0.90）完全失效，只能依赖回退启发式（置信度0.70）。

### 统一问题：所有detect()忽略diag参数

5个文件的 `detect()` 函数都用 `_ = diag;` 丢弃了 `DiagnosticWriter` 参数，所有诊断输出通过 `log.debug` 而非结构化诊断系统。

---

## 四、过滤层完整性新发现

### 4.1 `isRealMemorySafetyBug` Exception 1 过于宽泛

**文件**: `issue_suppression.zig:742-747`

```zig
if (isStdlibInternalFunction(issue)) {
    return false;  // 让Pattern G处理
}
```

此exception在switch语句之前执行。即使是 `use_after_free`（CWE-416）或 `buffer_overflow`（CWE-120）在stdlib函数中，也会被判定为"非真实bug"并交给Pattern G抑制。

**矛盾**: 注释（line 126-136）声称"内存安全违规...即使在名为'safe_*'的函数中也是真正的安全漏洞"，但代码明确豁免了stdlib。

### 4.2 `command_injection` 和 `format_string` 未受保护

`isRealMemorySafetyBug` 的switch未包含：
- `command_injection`（CWE-78）— OS命令注入
- `format_string`（CWE-134）— 格式化字符串漏洞

这些在 `__` 前缀函数或stdlib中会被完全抑制。

### 4.3 `is_ffi_issue` 遗漏关键issue kind

`pass_types.zig:658-676` 的 `is_ffi_issue` 未包含：
- `null_dereference` — 可被noise filter抑制
- `buffer_overflow` — 可被noise filter抑制
- `integer_overflow` — 可被noise filter抑制

### 4.4 `write_to_immutable` 级联降级路径

```
HIGH → P19-10 → MEDIUM → P19-12(runtime_internal) → LOW → noise filter → suppressed
```

3级降级，从HIGH到完全被抑制。

### 4.5 `ffi_zone_check.zig` 分类不一致

| 问题 | 位置 |
|------|------|
| `printf`/`fprintf` 同时在blacklist和safe列表 | line 105 vs line 183 |
| `memset` 在safe(L3)但`memcpy`在conditional(L2) | line 177 vs line 152 |
| `gmtime`/`localtime` 在dangerous_c_functions但不在blacklist | line 98-99 vs line 128 |
| `alloca` 未在任何层中 | 缺失 |

### 4.6 Issue Gate规则过于宽泛

| 规则 | 问题 |
|------|------|
| R-1 (line 54) | `heap_provenance` 抑制 `borrow_escape` — 堆指针可以不安全地escape |
| R-3 (line 68) | `raii_drop_release` 抑制 `use_after_free` — UAF可以发生在RAII drop之后 |
| R-4 (line 74) | `file_operation` 抑制 `cross_language_free` — 同时有文件和内存操作时误杀 |

---

## 五、遗留问题优先级排序

### P0 — 立即修复

| # | 问题 | 文件 | 修复方案 |
|---|------|------|----------|
| 1 | invoke遗漏: allocation_classifier | `allocation_classifier.zig:153` | `opcode != c.LLVMCall and opcode != c.LLVMInvoke` |
| 2 | invoke遗漏: ownership_analysis | `ownership_analysis.zig:328` | `c.LLVMCall, c.LLVMInvoke =>` |
| 3 | 测试编译失败 | `tests/unit/*.zig` | 改用 `@import("OmniScope")` 模块导入 |
| 4 | p1_critical_fix_test未集成 | `build.zig` | 添加test step |
| 5 | isHighRiskInternalUAF非pub | `cpp_fp_reduction.zig` | 改为 `pub fn` |

### P1 — 尽快修复

| # | 问题 | 文件 | 修复方案 |
|---|------|------|----------|
| 6 | invoke遗漏: malloc_check | `malloc_check.zig:175` | 增加 `opcode == c.LLVMInvoke` |
| 7 | invoke遗漏: heap_provenance | `heap_provenance.zig:299` | `c.LLVMCall, c.LLVMInvoke =>` |
| 8 | Exception 1过于宽泛 | `issue_suppression.zig:742` | 核心内存安全bug不应被stdlib exception豁免 |
| 9 | ch10 DI type walking全返回null | `ch10_pin_box.zig:146-163` | 实现LLVM DI type API集成 |
| 10 | printf矛盾 | `ffi_zone_check.zig:105,183` | 从safe列表移除printf/fprintf |
| 11 | 测试不一致 | `ffi_zone_check.zig:605-615` | 更新测试期望值 |

### P2 — 后续修复

| # | 问题 | 文件 |
|---|------|------|
| 12 | mangled name double-free跳过 | `cpp_fp_detect.zig:121` |
| 13 | 子串匹配精确化 | `noise_reduction.zig:285` |
| 14 | `__`前缀过于宽泛 | `issue_suppression.zig:347` |
| 15 | runtime_internal对安全bug豁免 | `pass_types.zig:636` |
| 16 | memory_leak基础分 | `confidence_scorer.zig:66` |
| 17 | command_injection/format_string未保护 | `issue_suppression.zig:782` |
| 18 | is_ffi_issue遗漏null_deref/buffer_overflow | `pass_types.zig:658` |
| 19 | memset/memcpy分类不一致 | `ffi_zone_check.zig` |
| 20 | alloca未在任何分类层中 | `ffi_zone_check.zig` |
| 21 | Issue Gate R-1/R-3/R-4过于宽泛 | `issue_gate.zig` |
| 22 | 11个dead code文件 | 多个文件 |
| 23 | semantic_resolution_test失败 | `tests/semantic_resolution_test.zig:59` |
| 24 | 格式字符串兼容性 | `src/root.zig` |

---

## 六、总结

### 修复质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| P0修复完成率 | 3/5 (60%) | invoke和mangled name double-free未修复 |
| 新代码质量 | 良好 | ch04/ch06/ch08实现完整，三层分类设计合理 |
| 测试集成 | 差 | 新测试未集成到build.zig，unit test全部编译失败 |
| 一致性 | 中等 | 多处分类矛盾和不一致 |
| 整体风险 | 中等 | 编译通过但测试覆盖不足 |

### 最关键的3个遗留问题

1. **invoke遗漏（5处）** — C++/Rust异常路径的内存安全问题仍会漏检
2. **测试系统损坏** — 6个测试文件编译失败，新增测试未集成
3. **过滤层不一致** — printf矛盾、memset/memcpy不一致、Exception 1过于宽泛
