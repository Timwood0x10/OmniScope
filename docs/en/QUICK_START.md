# OmniScope 快速入门指南 (Quick Start Guide)

> **版本**: v0.2.0 | **语言**: Zig 0.15.2 | **LLVM**: 22.1.4
> **预计时间**: 10 分钟完成首次分析

---

## 🚀 一、安装

### 前置要求

| 组件 | 版本 | 安装命令 |
|------|------|----------|
| Zig | 0.13+ | `brew install zig` 或 [ziglang.org](https://ziglang.org/download) |
| LLVM | 22.x | `brew install llvm@22` |
| Git | 任意 | 系统自带 |

### 克隆与构建

```bash
# 1. 克隆项目
git clone https://github.com/your-org/OmniScope.git
cd OmniScope

# 2. Debug 构建（推荐用于开发）
zig build -Ddebug-safe

# 3. ReleaseFast 构建（推荐用于生产）
zig build -Drelease-fast
```

### 验证安装

```bash
# 检查二进制文件
./zig-out/bin/OmniScope --version

# 运行测试套件
zig build test

# 预期输出: 343/343 tests passing ✅
```

---

## 🔧 二、基础用法

### 分析单个文件

```bash
# 基础分析（文本输出）
./zig-out/bin/OmniScope your_file.ll

# JSON 输出（推荐用于CI/CD）
./zig-out/bin/OmniScope your_file.ll --json > results.json

# 分析 bitcode 文件 (.bc)
./zig-out/bin/OmniScope your_file.bc --json
```

### 批量分析语料库

```bash
# 使用内置脚本分析全部 corpus 文件
./scripts/full_corpus_analysis_final.sh

# 输出目录: outputs/full_analysis_v017_final/
# 包含:
#   - *.json: 每个文件的完整分析结果
#   - *.err.log: 错误日志（如有）
```

---

## 📖 三、理解输出格式

### 3.1 控制台输出示例

```
[INFO] === OmniScope IR Analysis ===
[INFO] File: /path/to/file.bc
[INFO] Loaded: 1245 functions
[INFO] LANG-DETECT: module language = c, confidence = 100.0%
[INFO] CallGraph: extracted 1506 cross-language edges
...
[OMI-HIGH] PtrLifetime: analyzed 318 funcs, found 4 violations
[PERF] Total time: 2079ms
{"schema_version":"1.0.0","tool":"omniscope","tool_version":"0.2.0",
 "summary":{"functions":1245,"issues":49,"time_ms":2079},"issues":[...]}
```

### 3.2 JSON 输出结构

```json
{
  "schema_version": "1.0.0",
  "tool": "omniscope",
  "tool_version": "0.2.0",
  "timestamp": 1778158865,
  "summary": {
    "functions": 1245,
    "issues": 49,
    "time_ms": 2079
  },
  "issues": [
    {
      "id": "OMI-001",
      "kind": "memory_leak",
      "severity": "medium",
      "confidence": "MEDIUM",
      "confidence_score": 0.70,
      "cwe_id": 401,
      "message": "Memory allocated but never freed",
      "location": {
        "function": "some_function"
      }
    }
  ]
}
```

### 3.3 Issue 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 唯一标识符 (OMI-NNN) |
| `kind` | enum | Issue类型（见下方列表）|
| `severity` | enum | critical/high/medium/low |
| `confidence` | enum | HIGH/MEDIUM/LOW/HEURISTIC |
| `cwe_id` | int | CWE漏洞分类编号 |
| `message` | string | 问题描述 |
| `location.function` | string | 检出位置（函数名）|

#### 支持的 Issue Kind (20种)

**内存安全类**:
- `memory_leak` - 内存泄漏
- `use_after_free` - 释放后使用
- `double_free` - 双重释放
- `null_dereference` - 空指针解引用
- `buffer_overflow_risk` - 缓冲区溢出风险
- `stack_buffer_overflow` - 栈缓冲区溢出
- `invalid_free` - 无效释放

**FFI安全类**:
- `borrow_escape` - Rust借用逃逸到FFI
- `cross_language_free` - 跨语言释放
- `cross_language_leak` - 跨语言泄漏
- `ffi_unsafe_call` - 不安全的FFI调用
- `jni_type_mismatch` - JNI类型不匹配
- `jni_unchecked_return` - JNI返回值未检查

**数据流类**:
- `tainted_path_to_sink` - 污点传播到敏感函数
- `command_injection` - 命令注入
- `format_string` - 格式化字符串漏洞
- `unsafe_deserialization` - 不安全的反序列化

**并发类**:
- `data_race` - 数据竞争
- `thread_safety_violation` - 线程安全问题

---

## 🎯 四、典型使用场景

### 场景1: 分析Rust FFI绑定库

```bash
# 分析 ring 加密库的Rust FFI安全性
/opt/homebrew/opt/llvm@22/bin/llvm-as corpus/real_world/other/ring.ll \
  -o /tmp/ring.bc

./zig-out/bin/OmniScope /tmp/ring.bc --json

# 预期输出:
#   functions: 410
#   issues: 16 (含4个borrow_escape)
#   FFI boundaries: 4,252
```

**关键检查项**:
- ✅ `Box::into_raw()` / `Box::from_raw()` 配对检测
- ✅ `&mut *ptr` 借用逃逸识别
- ✅ Safe Zone 分类（纯Rust代码自动排除）

### 场景2: 检测C项目内存泄漏

```bash
# 分析 sqlite3 数据库引擎
./zig-out/bin/OmniScope /tmp/sqlite3.bc --json | jq '.issues[] | select(.kind=="memory_leak")'

# 预期输出: ~69 个潜在内存泄漏
# 其中约60个为真阳性（错误处理分支遗漏free）
```

### 场景3: CI/CD集成

创建 `.github/workflows/omniscope.yml`:

```yaml
name: OmniScope Analysis

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Zig
        uses: goto-bus-setup/setup-zig@v2
      
      - name: Build OmniScope
        run: zig build -Drelease-fast
      
      - name: Run Analysis
        run: |
          ./zig-out/bin/OmniScope corpus/**/*.ll --json \
            --sarif > omniscope-results.sarif
      
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif-file: omniscope-results.sarif
```

---

## ⚙️ 五、高级配置

### 5.1 配置文件

在项目根目录创建 `omniscope.config.json`:

```json
{
  "analysis": {
    "max_functions_per_module": 5000,
    "taint_depth": 3,
    "enable_rust_ffi_auditor": true,
    "enable_pointer_ownership": true
  },
  "noise_filter": {
    "suppress_stdlib": true,
    "min_confidence_threshold": 0.50
  },
  "output": {
    "format": ["json", "console", "sarif"],
    "verbose": true
  }
}
```

### 5.2 命令行参数

```bash
# 完整参数列表
./zig-out/bin/OmniScope --help

# 常用参数:
--json              # JSON格式输出
--sarif             # SARIF格式输出（用于GitHub Code Scanning）
--config <file>    # 指定配置文件
--verbose           # 详细输出（显示每个pass的耗时）
--no-color          # 禁用彩色输出
```

### 5.3 性能调优

| 文件规模 | Debug模式 | ReleaseFast模式 |
|----------|-----------|-----------------|
| <100 函数 | <1s | <200ms |
| 100-500 函数 | 1-5s | <1s |
| 500-3000 函数 | 5-20s | 1-5s |
| >3000 函数 | 20s+ | 5-15s |

**建议**: 生产环境使用 `zig build -Drelease-fast`

---

## 🔍 六、常见问题排查

### Q1: "ModuleParseFailed" 错误

**原因**: IR文件损坏或LLVM版本不兼容

**解决方案**:
```bash
# 使用 llvm-as-22 预转换
/opt/homebrew/opt/llvm@22/bin/llvm-as input.ll -o input.bc
./zig-out/bin/OmniScope input.bc
```

### Q2: "Invalid free" 或 GPA错误

**原因**: 内存泄漏 bug（v0.2.0 当前版本已处理）

**解决方案**:
```bash
# 确保使用最新构建
zig build clean && zig build -Ddebug-safe
```

### Q3: 分析大型文件时OOM

**原因**: Debug模式下内存占用较高

**解决方案**:
```bash
# 使用ReleaseFast构建
zig build -Drelease-fast

# 或限制分析深度
# 在配置文件中设置: "max_functions_per_module": 500
```

### Q4: 如何过滤误报？

**方法1**: 使用置信度阈值
```bash
jq '.issues[] | select(.confidence_score >= 0.70)' results.json
```

**方法2**: 按严重级别筛选
```bash
jq '.issues[] | select(.severity == "critical" or .severity == "high")' results.json
```

**方法3**: 使用OmniScope内置噪声过滤器（默认启用）

---

## 📊 七、下一步学习

### 📖 推荐阅读顺序

1. **本文档** ← 你在这里 ✅
2. [README.md](../README.md) - 项目概述和核心哲学
3. [Architecture Guide](architecture.md) - 架构设计详解
4. [Developer Guide](en/developer_guide.md) - 开发者指南
5. [Passes Reference](en/passes.md) - 所有分析Pass说明
6. [Modules Reference](en/modules.md) - 模块API文档
7. [Full Verification Report](investigation_reports/en/FULL_VERIFICATION_V017.md) - 完整验证报告

### 🛠️ 动手实践

1. **运行示例**: `./scripts/full_corpus_analysis_final.sh`
2. **查看结果**: `cat outputs/full_analysis_v017_final/sqlite3.json`
3. **自定义分析**: 创建自己的测试 `.ll` 文件并分析
4. **贡献代码**: 阅读 [Developer Guide](en/developer_guide.md) 了解开发流程

---

## 💡 八、最佳实践

### ✅ Do（推荐做法）

- ✅ 对所有跨语言边界代码运行OmniScope
- ✅ 在CI/CD中集成自动化分析
- ✅ 使用 `--json` 格式便于后续处理
- ✅ 定期更新corpus以覆盖新场景
- ✅ 关注 CRITICAL 和 HIGH 级别的issue

### ❌ Don't（避免做法）

- ❌ 仅依赖编译器警告（无法检测FFI问题）
- ❌ 忽略 MEDIUM/LOW 级别issue（可能隐藏真实风险）
- ❌ 在Debug模式下分析超大型项目（使用ReleaseFast）
- ❌ 手动审查所有FP（利用噪声过滤器）

---

## 🎓 九、概念速查表

| 术语 | 解释 | 示例 |
|------|------|------|
| **FFI Boundary** | 跨语言函数调用 | Rust调用C的`extern "C"`函数 |
| **Safe Zone** | 无需分析的代码区域 | 纯Rust safe代码 |
| **Ownership Transfer** | 内存所有权转移 | `Box::into_raw()` 将所有权交给C |
| **Borrow Escape** | 借用逃逸作用域 | 将栈上引用传给FFI |
| **Taint Propagation** | 污点数据流追踪 | 用户输入→SQL注入 |
| **GPA (General Purpose Allocator)** | Zig通用分配器 | 用于检测内存泄漏 |
| **SARIF** | 静态分析结果交换格式 | GitHub Code Scanning标准格式 |

---

*文档版本*: v0.2.0 | *最后更新*: 2026-05-29 | *作者*: OmniScope Team
*反馈*: 请提交 [GitHub Issues](https://github.com/your-org/OmniScope/issues)
