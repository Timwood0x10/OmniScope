# OmniScope 置信度计算详解

## 概述

OmniScope 的所有检测结果都包含置信度（confidence）信息，帮助用户判断结果的可靠性。

## 置信度级别

| 级别 | 数值范围 | 含义 | 示例 |
|------|---------|------|------|
| **HIGH** | 0.9 - 1.0 | 确定性检测，无误报风险 | 语言检测、明确的内存泄漏 |
| **MEDIUM** | 0.7 - 0.89 | 高概率检测，可能有少量误报 | 所有权违规、跨语言泄漏 |
| **LOW** | 0.5 - 0.69 | 启发式检测，需要人工验证 | 复杂控制流、间接调用 |

## 各类检测的置信度计算

### 1. 语言检测置信度

**方法**：统计采样 + 模式匹配

**计算公式**：
```
confidence = (匹配的函数数 / 采样的函数数) × 100%
```

**示例**：
```text
info: [INFO] LANG-DETECT: module language = c, confidence = 57.7%, method = sampling
```

**解读**：
- 57.7% 表示混合语言代码库
- 采样了 50 个函数，29 个是 C 函数
- 置信度 = 29/50 = 58%

**为什么不是 100%？**
- 测试文件包含 C、Rust、C++ 函数
- 主语言是 C，但有大量其他语言函数
- 这是**正常现象**，表示代码库是多语言的

### 2. 跨语言边界置信度

**方法**：确定性模式匹配

**置信度**：**HIGH (100%)**

**原因**：
1. **语言识别是确定性的**：
   - `_ZN` + Rust 标记 → Rust（二元决策）
   - `_ZN` + 无 Rust 标记 → C++（二元决策）
   - `_R` 前缀 → Rust v0（二元决策）
   - 无命名修饰 → C（二元决策）

2. **边界检测是精确的**：
   - `caller_lang != callee_lang` → FFI 边界
   - 不涉及概率或启发式方法

**示例**：
```text
info: [INFO] CallGraph: extracted 22 cross-language edges
```

**解读**：
- 所有 22 条边都是**真实的 FFI 边界**
- 置信度 100%，无误报风险
- 每条边都是潜在违规点

### 3. 内存泄漏置信度

**方法**：所有权追踪 + 控制流分析

**置信度计算**：
```
confidence = base_confidence × allocation_certainty × free_certainty
```

**示例**：
```json
{
  "kind": "memory_leak",
  "confidence": "MEDIUM",
  "confidence_score": 0.70
}
```

**为什么是 MEDIUM (70%)？**
- **base_confidence (0.8)**：检测到分配但未释放
- **allocation_certainty (1.0)**：分配点明确（malloc/calloc）
- **free_certainty (0.875)**：可能存在间接释放路径
- **最终**：0.8 × 1.0 × 0.875 = 0.70

**影响因素**：
- ✅ 直接分配/释放 → HIGH (90-100%)
- ⚠️ 间接调用 → MEDIUM (70-89%)
- ❓ 复杂控制流 → LOW (50-69%)

### 4. 未检查返回值置信度

**方法**：数据流分析

**置信度计算**：
```
confidence = function_risk × context_certainty
```

**示例**：
```json
{
  "kind": "unchecked_return",
  "confidence": "HIGH",
  "confidence_score": 0.90
}
```

**为什么是 HIGH (90%)？**
- **function_risk (1.0)**：`system()` 是已知危险函数
- **context_certainty (0.9)**：返回值确实未使用
- **最终**：1.0 × 0.9 = 0.90

**危险函数列表**：
- `system()`, `exec*()` → 命令注入风险
- `malloc()`, `calloc()` → 内存分配失败
- `fopen()`, `open()` → 文件操作失败
- `recv()`, `send()` → 网络操作失败

### 5. 跨语言所有权违规置信度

**方法**：所有权图分析

**置信度计算**：
```
confidence = lang_detection_conf × ownership_conf × boundary_conf
```

**示例**：
```text
Ownership transferred from Rust to C but never reclaimed
```

**置信度分解**：
- **lang_detection_conf (1.0)**：语言检测 100% 准确
- **ownership_conf (0.8)**：所有权转移检测
- **boundary_conf (0.875)**：边界违规检测
- **最终**：1.0 × 0.8 × 0.875 = 0.70 (MEDIUM)

## 置信度影响因素

### 提高置信度的因素

1. **明确的模式匹配**：
   - 函数名包含明确标记（`_ZN`, `_R`, `rust_`）
   - 调用已知库函数（`malloc`, `free`）

2. **直接的控制流**：
   - 无间接调用
   - 无复杂分支

3. **完整的调试信息**：
   - 编译时使用 `-g` 标志
   - 保留源码位置信息

### 降低置信度的因素

1. **间接调用**：
   - 函数指针调用
   - 虚函数调用

2. **复杂控制流**：
   - 多层嵌套分支
   - 循环中的分配/释放

3. **缺少调试信息**：
   - 优化级别过高（`-O2`, `-O3`）
   - 内联导致信息丢失

## 如何使用置信度信息

### 决策指南

| 置信度 | 建议动作 | 验证方式 |
|--------|---------|---------|
| **HIGH (90-100%)** | 直接修复 | 代码审查 |
| **MEDIUM (70-89%)** | 优先审查 | 动态测试 + 代码审查 |
| **LOW (50-69%)** | 人工验证 | 详细分析 + 测试 |

### 实际案例

**案例 1：HIGH 置信度问题**
```json
{
  "kind": "unchecked_return",
  "confidence": "HIGH",
  "confidence_score": 0.90,
  "message": "Unchecked return value from dangerous function 'system'"
}
```
**动作**：立即修复，添加错误处理

**案例 2：MEDIUM 置信度问题**
```json
{
  "kind": "memory_leak",
  "confidence": "MEDIUM",
  "confidence_score": 0.70,
  "message": "Memory allocated but never freed"
}
```
**动作**：审查代码，确认是否真的泄漏

**案例 3：LOW 置信度问题**
```json
{
  "kind": "potential_double_free",
  "confidence": "LOW",
  "confidence_score": 0.55,
  "message": "Possible double free in complex control flow"
}
```
**动作**：详细分析控制流，可能需要动态测试

## 置信度优化建议

### 对用户

1. **编译时添加调试信息**：
   ```bash
   clang -g -O0 -emit-llvm -S source.c -o source.ll
   ```

2. **避免过度优化**：
   - 分析时使用 `-O0` 或 `-O1`
   - 生产代码可以使用更高优化级别

3. **审查 MEDIUM 置信度问题**：
   - 这些最可能是真实问题
   - 优先处理 MEDIUM 级别

### 对开发者

1. **提高语言检测准确性**：
   - 添加更多语言特定模式
   - 改进 `_ZN` 消歧逻辑

2. **改进所有权追踪**：
   - 更精确的控制流分析
   - 更好的间接调用处理

3. **提供更详细的上下文**：
   - 显示置信度计算过程
   - 解释降低置信度的因素

## 总结

- ✅ **语言检测**：HIGH (100%) - 确定性模式匹配
- ✅ **跨语言边界**：HIGH (100%) - 精确的二元决策
- ⚠️ **内存泄漏**：MEDIUM (70%) - 依赖控制流分析
- ✅ **未检查返回**：HIGH (90%) - 危险函数识别
- ⚠️ **所有权违规**：MEDIUM (70%) - 依赖所有权图

**关键要点**：
1. 置信度帮助您优先处理最可能的问题
2. HIGH 置信度问题可以直接修复
3. MEDIUM 置信度问题需要审查
4. LOW 置信度问题需要详细验证
5. 提供调试信息可以提高置信度
