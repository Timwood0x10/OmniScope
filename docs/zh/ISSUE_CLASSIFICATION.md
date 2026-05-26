# OmniScope Issue 分类口径规范 (ISSUE CLASSIFICATION)

> **版本**: 1.0
> **更新日期**: 2026-05-26
> **适用范围**: OmniScope 静态分析工具所有输出

## 概述

本文档定义 OmniScope 分析结果的 **4 级分类体系**，用于区分真实缺陷、疑似问题、诊断信息和已确认安全的代码模式。分类结果直接影响 SARIF 输出内容和用户可见性。

---

## 分类级别定义

### Level 1: confirmed_issue ✅（确认问题）

**定义**: 高置信度判断为真实安全漏洞或缺陷的 issue。

#### 判定标准

必须 **同时满足** 以下条件：

| 条件 | 说明 |
|------|------|
| **置信度阈值** | confidence ≥ 0.85 |
| **路径可达性** | 存在明确的代码执行路径可触发该问题 |
| **数据流完整性** | 污点数据（taint）可从 source 追踪到 sink |
| **无抑制标记** | 代码中不存在 `// omniscope: ignore` 或等效注解 |
| **非编译器伪影** | 问题非由 LLVM IR 优化过程引入的虚假模式 |
| **语义一致性** | 与程序预期行为存在明确矛盾 |

#### 典型示例

```c
// ✅ confirmed_issue: 明确的 buffer overflow
void vuln(char *input) {
    char buf[8];
    strcpy(buf, input);  // 无边界检查，input 来自外部输入
}

// ✅ confirmed_issue: use-after-free
void use_after_free() {
    int *p = malloc(sizeof(int));
    free(p);
    *p = 42;  // 使用已释放内存
}
```

#### Severity 映射

| 原始 severity | 输出 severity | 说明 |
|---------------|--------------|------|
| critical | **critical** | 保持不变 |
| high | **high** | 保持不变 |
| medium | **medium** | 保持不变 |
| low | **low** | 保持不变 |

---

### Level 2: probable_issue ⚠️（疑似问题）

**定义**: 中高置信度，可能为真实问题，但存在某些不确定因素需要人工确认。

#### 判定标准

满足以下 **任一条件** 即归为此类：

| 条件 | 说明 |
|------|------|
| **置信度范围** | 0.65 ≤ confidence < 0.85 |
| **路径部分确定** | 主执行路径可达，但依赖运行时条件分支 |
| **数据流近似** | 污点追踪在复杂控制流中出现精度损失 |
| **跨语言边界** | FFI/CGO 场景下，类型映射或调用约定存在歧义 |
| **上下文敏感** | 在特定调用上下文中成立，但非全局成立 |
| **库函数假设** | 依赖于对第三方库行为的假设（未经验证） |

#### 典型示例

```rust
// ⚠️ probable_issue: 可能的越界访问（依赖运行时长度）
fn process(data: &[u8]) -> u8 {
    if data.len() >= 10 {
        data[9]  // 大多数情况安全，但若 data 被外部修改则危险
    } else {
        0
    }
}

// ⚠️ probable_issue: FFI 内存所有权不明确
extern "C" {
    fn get_buffer() -> *mut u8;  // 返回值所有权不明
}
let buf = unsafe { get_buffer() };
// buf 是否需要 free？取决于 C 库实现
```

#### Severity 映射

| 原始 severity | 输出 severity | 调整规则 |
|---------------|--------------|----------|
| critical | **high** | 降一级（不确定性导致） |
| high | **medium** | 降一级 |
| medium | **low** | 降一级 |
| low | **low** | 保持不变（已是最低） |
| - | **note** | 若 confidence < 0.70，附加 note 标记 |

---

### Level 3: diagnostic 🔍（诊断信息）

**定义**: 低置信度或工具内部状态信息，主要用于调试和分析过程透明化。

#### 判定标准

满足以下 **任一条件**：

| 条件 | 说明 |
|------|------|
| **置信度低** | confidence < 0.65 |
| **编译器伪影** | 由 LLVM IR 优化、内联、循环展开等引入的模式 |
| **实现细节暴露** | 涉及标准库/运行时内部实现的警告 |
| **理论性问题** | 仅在极端或理论上可能的场景触发 |
| **性能相关** | 非安全性问题的性能瓶颈提示 |
| **代码风格** | 不影响正确性的编码规范建议 |

#### 典型示例

```c
// 🔍 diagnostic: 编译器优化的死代码
void optimized() {
    int x = 0;
    if (false) {  // 编译器常量折叠后永远不执行
        x = undefined_value;  // 实际不可达
    }
}

// 🔍 diagnostic: SIMD intrinsic 的对齐假设
__m128i vec = _mm_loadu_si128(ptr);  // 未对齐加载，但在支持 unaligned access 的平台上安全
```

#### 输出控制

⚠️ **diagnostic 默认不输出到 SARIF**

仅在以下场景输出：
- `--debug` 标志启用时
- `--debug-resource-contract` 标志启用时（仅输出资源契约相关的 diagnostic）
- 显式指定 `--output-level=diagnostic` 时

---

### Level 4: explained_safe ✅🛡️（已解释的安全代码）

**定义**: 经分析确认安全的代码模式，被误报后通过规则/注解消除或自动归类为安全。

#### 判定标准

| 条件 | 说明 |
|------|------|
| **显式忽略** | 代码包含 `// omniscope: safe` 或 `#[allow(omniscope)]` 注解 |
| **模式匹配** | 匹配已知安全模式的白名单（如 Rust 的 slice indexing with checked bounds） |
| **静态证明** | 通过抽象解释或类型系统证明安全性 |
| **测试覆盖** | 存在针对性的 fuzz 测试或属性测试覆盖该路径 |
| **官方文档** | 依赖的库/框架文档明确说明该用法安全 |

#### 典型示例

```rust
// ✅🛡️ explained_safe: Rust 的边界检查（编译器保证）
fn safe_access(arr: &[i32], idx: usize) -> Option<&i32> {
    arr.get(idx)  // 返回 Option，不会 panic 或越界
}

// ✅🛡️ explained_safe: 用户显式标记
fn custom_alloc(size: usize) -> *mut u8 {
    // omniscope: safe: 自定义 allocator 已验证线程安全
    unsafe { alloc::alloc(Layout::from_size_align(size, 8).unwrap()) }
}
```

#### 处理方式

- **不包含在常规输出中**
- 可通过 `--show-safe-patterns` 查看统计信息
- 用于改进白名单规则和减少未来误报

---

## SARIF 输出策略

### 默认输出配置（生产模式）

```json
{
  "output_filter": {
    "include": ["confirmed_issue", "probable_issue(high)"],
    "exclude": ["diagnostic", "explained_safe", "probable_issue(medium|low)"],
    "probable_issue_threshold": {
      "min_confidence": 0.75,
      "min_severity": "medium"
    }
  }
}
```

**默认输出内容**:
- ✅ 所有 `confirmed_issue`
- ⚠️ `probable_issue` 中 confidence ≥ 0.75 且 severity ≥ medium 的子集
- ❌ 不输出 `diagnostic`
- ❌ 不输出 `explained_safe`

### Debug 输出配置

启用 `--debug` 后：

```json
{
  "output_filter": {
    "include": ["confirmed_issue", "probable_issue", "diagnostic"],
    "exclude": ["explained_safe"],
    "diagnostic_scope": "all"
  }
}
```

### Resource Contract Debug 输出

启用 `--debug-resource-contract` 后：

```json
{
  "output_filter": {
    "include": ["confirmed_issue", "probable_issue"],
    "diagnostic_scope": ["resource_contract", "lifetime_analysis", "ownership_tracking"],
    "exclude": ["explained_safe"]
  }
}
```

---

## 分类流程图

```mermaid
flowchart TD
    A[原始 Issue] --> B{confidence ≥ 0.85?}
    B -->|是| C{满足 confirmed 标准?}
    C -->|是| D[✅ confirmed_issue]
    C -->|否| E{confidence ≥ 0.65?}
    
    B -->|否| E
    
    E -->|是| F[⚠️ probable_issue]
    E -->|否| G{匹配 safe pattern?}
    
    G -->|是| H[✅🛡️ explained_safe]
    G -->|否| I[🔍 diagnostic]
    
    D --> J{SARIF 输出?}
    F --> J
    I --> K{--debug 启用?}
    
    J -->|默认| L[输出 confirmed + high probable]
    J |--debug| M[输出全部 except safe]
    
    K -->|是| N[输出 diagnostic]
    K -->|否| O[丢弃]
```

---

## 统计报告格式

每次分析完成后，输出分类统计：

```
=== OmniScope Analysis Summary ===
Total issues found: 42

Classification breakdown:
  ✅ confirmed_issue:   12 (28.6%)
     ├─ critical: 2
     ├─ high:     5
     ├─ medium:   3
     └─ low:      2
  
  ⚠️ probable_issue:    18 (42.9%)
     ├─ high:     4  [3 included in SARIF]
     ├─ medium:   8  [2 included in SARIF]
     └─ low:      6  [0 included in SARIF]
  
  🔍 diagnostic:         10 (23.8%)  [hidden, use --debug to show]
     ├─ compiler_artifact: 4
     ├─ theoretical:       3
     └─ performance:       3
  
  ✅🛡️ explained_safe:     2 (4.8%)   [hidden]

SARIF output: 17 issues (12 confirmed + 5 probable)
False positive estimate: ~35% (based on historical baseline)
```

---

## 配置文件支持

用户可通过 `.omniscope/config.toml` 自定义分类阈值：

```toml
[classification]
confirmed_min_confidence = 0.85
probable_min_confidence = 0.65
probable_sarif_min_confidence = 0.75
probable_sarif_min_severity = "medium"

[output]
include_diagnostic = false
include_explained_safe = false
debug_resource_contract_only = false
```

---

## 变更日志

| 日期 | 版本 | 变更内容 | 作者 |
|------|------|----------|------|
| 2026-05-26 | v1.0 | 初始版本，定义 4 级分类体系及 SARIF 输出策略 | OmniScope Team |
