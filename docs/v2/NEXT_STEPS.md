# OmniScope 下一步开发方案

> **日期**: 2026-06-01
> **基于**: 实际测试结果 + 代码库审查
> **原则**: 只做有明确 ROI 的事，不做推测性优化

---

## 问题清单（实测结果）

| 问题 | 严重度 | 根因（已确认） |
|------|--------|--------------|
| Zig stdlib FP 86.8% | 🔴 P0 | `focus_user_code` CLI→Pass 链路断裂 |
| Rust recall 极低 | 🔴 P0 | IR 层丢失 ownership 语义 |
| C recall 43-57% | 🟡 P1 | double_free/UAF 漏检 |
| Go/Python 仅接受 IR | 🟡 P1 | 无预处理管道 |
| Zig 大项目 7.78s | 🟢 P2 | 全量扫描无过滤 |

---

## P0-1: Zig Stdlib FP 根本修复

### 实际根因（不是猜测）

探查发现 **两层矛盾**：

```
CLI Config:  focus_user_code = false  (默认关闭)
                      ↓
NoiseReductionConfig: focus_user_code = true  (pass 内部硬编码)
```

Pass 内部写死了 `focus_user_code: true`，**完全绕过了 CLI 配置**。
所以即使用户传 `--focus-user-code`，也只是对已经开着的开关再开一次。
而 `zig_allocator_tracker` 只接入了 pipeline 的**泄漏检测循环**，
没有接入产生 86.8% FP 的 `cross_lang_dataflow` pass。

### 修复方案

#### 方案 A（推荐，外科手术式）

**Step 1**: 将 `focus_user_code` 从 CLI Config 传入 PassContext。

```
main_config.Config.focus_user_code
    → Pipeline.run() 参数
    → PassContext.focus_user_code 字段（新增）
```

**Step 2**: 让 `cross_lang_dataflow.zig` 在报告前检查 `ctx.focus_user_code`：

```zig
// cross_lang_dataflow.zig 中每个 reportIssue 调用前
if (ctx.focus_user_code and isStdlibFunction(alloc_func_name)) {
    // 不报告，只记录统计
    continue;
}
```

**Step 3**: 将 CLI 默认值改为 `focus_user_code = true`（Zig 项目标准用法）。

**涉及文件**：
- `src/types/main_config.zig` — 改默认值
- `src/pipeline/pipeline.zig` — 传入 PassContext
- `src/pass/pass.zig` — PassContext 加字段
- `src/pass/analysis/ffi/cross_lang_dataflow.zig` — 加判断

**预期效果**：Zig FP 从 86.8% → 10-15%（消除 stdlib 噪声）

#### 方案 B（不推荐）

继续扩充 `zig_allocator_tracker`。
**问题**：FP 来自 `cross_lang_dataflow`，不是泄漏检测循环。
治标不治本。

---

## P0-2: Rust Recall 修复

### 实际根因

漏检的 2 个 bug 类型是什么？根据测试报告和代码审查：

**猜测**：可能是 `Box::into_raw()` + `ptr::drop_in_place()` 这类 ownership
transfer 模式，或者跨函数的 double_free（即 alloc 在函数 A，free 在函数 B）。

**需要确认**：运行一次 debug 分析找到漏检原因。

```bash
zig build run -- corpus/rust_ffi_bugs.c.bc --debug 2>&1 | grep "SKIP\|SUPPRESS" | head -30
```

### 已有基础

- `rust_ffi_auditor.zig` (394 行) + `rust_ffi_rules_advanced.zig` (833 行) 已有大量规则
- `rust_drop_semantics.zig` (549 行) 已有 Drop 语义
- `ownership_types.zig` (496 行) 已有所有权分类

### 方案

先用 debug 输出定位具体是哪条规则在 suppress，再做针对性修改。
**不要在不知道漏检原因时就开始写新代码**。

**Step 1**（诊断）：
```bash
# 对已知 bug 的 IR 文件跑 debug 模式，看 suppress 日志
zig build run -- known_rust_bug.bc --debug 2>&1 | grep -E "(SUPPRESS|SKIP|WHITELIST)"
```

**Step 2**（修复）：根据诊断结果，在对应的 suppress 条件里加例外，
或者调整 `rust_ffi_rules_advanced.zig` 中的检测逻辑。

---

## P1-1: C Recall 提升

### 漏检的 bug 类型

- `double_free`：ptr_lifetime pass 有检测，但 recall 低
- `use_after_free`：free_validation pass 有检测
- `buffer_overflow`：buffer_overflow.zig (363 行) 有检测

### 方案

与 Rust 问题一样：**先诊断，后修复**。

```bash
# 对已知的 C double_free bug 跑 debug
zig build run -- rust_ffi_bugs.bc --debug 2>&1 | grep -E "double_free|use_after_free"
```

最可能的原因：指针别名导致 `freed` 状态没有正确传播。
`memory_graph.zig` 的 `isDoubleFreed()` 依赖 alias resolution，
如果 alias chain 中断就漏检。

**涉及文件**：`src/semantics/memory_graph.zig:isDoubleFreed()`

---

## P1-2: Go/Python 源码支持

### 当前状态

OmniScope 只接受 LLVM IR (`.bc`/`.ll`)，这是正确的设计。
但用户通常拿到的是 `.go`/`.py` 文件，需要预处理管道。

### 方案：预处理脚本（不改 OmniScope 核心）

**Go → IR**：
```bash
# scripts/compile_go.sh
go tool compile -N -l -S -o /dev/stdout "$1" 2>&1 | \
    llvm-as - -o "${1%.go}.bc"
```

**Python C Extension → IR**（仅适用于 C extension）：
```bash
# scripts/compile_python_ext.sh  
clang -emit-llvm -c "$1" -o "${1%.c}.bc" \
    $(python3-config --includes)
```

**核心原则**：不在 OmniScope 里集成编译器。保持分析器的职责单一。

---

## P2: Zig 大项目性能

### 当前：7.78s，原因

全量扫描所有函数。对 Zig stdlib 的 1000+ 内部函数也做了完整分析。

### 方案

`focus_user_code = true` 默认开启后，**跳过 stdlib 函数的完整分析**，
只做快速分类。这是 P0-1 的附带收益，不需要单独优化。

预期：7.78s → 2-3s（减少 60-70% 的函数分析量）。

---

## 执行顺序

```
本周:
  1. P0-1: Zig FP 修复（1天）
     - 确认 focus_user_code 链路
     - 修复 PassContext 传递
     - 改默认值 + 接入 cross_lang_dataflow
     - 验证：Zig FP 从 86.8% → <15%

  2. P0-2: Rust recall 诊断（半天）
     - 运行 debug，找到 suppress 原因
     - 如果是简单过滤问题：当天修复
     - 如果是架构问题：记录，列入 P1

下周:
  3. P1-1: C recall 诊断 + 修复
  4. P1-2: 预处理脚本

后续:
  5. P2: 性能（等 P0-1 完成后重新测）
```

---

## 不做的事

1. **不新建 Rust adapter**：已有 6316 行 Rust 代码，先找为什么不生效
2. **不集成 Go/Python 编译器**：保持职责单一，用脚本解决
3. **不做并行化**：先解决 FP 问题，7.78s 对于分析工具是可接受的
4. **不扩充白名单**：P0-1 用正确方式修复后白名单自然缩小

---

## 成功标准

| 目标 | 当前 | 完成标准 |
|------|------|---------|
| Zig FP 率 | 86.8% | **< 15%** |
| Rust F1 | ~0% recall | **> 50% recall** |
| C recall | 43-57% | **> 70%** |
| Zig 分析时间 | 7.78s | **< 3s** |
| 总体评级 | B+ | **A-** |
