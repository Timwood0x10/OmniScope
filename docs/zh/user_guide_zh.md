# 用户指南

> "你的代码有 bug，我们能帮你找到一些。"

最后更新: 2026-05-06 | 版本: v0.1.7

## OmniScope 做什么

OmniScope 分析 LLVM IR 文件，定位 FFI 边界上的**跨语言内存安全问题**。它能检测：

- **Use-after-free**: 内存在一侧被释放，另一侧仍在访问
- **Double-free**: 内存被释放两次（通常每种语言各一次）
- **Memory leaks**: 跨语言边界分配但从未释放的内存
- **Pointer escape**: 指针未经所有权转移就跨越 FFI 边界
- **Type mismatches**: 跨 FFI 调用传递了错误的类型

## 快速开始

### 前置要求
- Zig 0.1.5.0+
- 一个 LLVM IR 文件（`.ll`）

### 构建

```bash
git clone https://github.com/your-org/omniscope.git
cd omniscope
zig build
```

### 运行

```bash
# 基本分析
./zig-out/bin/omniscope your_file.ll

# 详细输出
./zig-out/bin/omniscope --verbose your_file.ll

# JSON 输出（用于 CI 集成）
./zig-out/bin/omniscope --format json your_file.ll > report.json
```

### 生成 LLVM IR

你需要 LLVM IR 文件才能进行分析。获取方式如下：

```bash
# 从 C/C++
clang -S -emit-llvm -o file.ll file.c

# 从 Rust
cargo rustc -- --emit=llvm-ir

# 从 Go（使用 TinyGo）
tinygo build -emit-llvm -o file.ll

# 从 Zig
zig build-obj --emit-llvm-ir file.zig
```

## 理解输出

### 文本输出

```
[ISSUE] DOUBLE_FREE @ function "my_c_free" (line 42)
  Confidence: HIGH
  Pointer: %ptr (allocated at line 38 via malloc)
  First free: line 40 via rust_dealloc
  Second free: line 42 via free
  FFI Boundary: Rust → C
```

### JSON 输出

```json
{
  "tool_version 0.1.7",
  "issues": [
    {
      "kind": "DOUBLE_FREE",
      "confidence": "HIGH",
      "function": "my_c_free",
      "line": 42,
      "details": {
        "pointer": "%ptr",
        "first_free": "rust_dealloc",
        "second_free": "free",
        "ffi_boundary": "Rust → C"
      }
    }
  ]
}
```

## 置信度等级

| 等级 | 含义 |
|------|------|
| HIGH | 通过图分析确认，数据流完整 |
| MEDIUM | 证据充分，但 alias tracking 不完整 |
| HEURISTIC | 基于模式匹配，可能存在误报 |
| EXPERIMENTAL | 新的检测路径，请谨慎对待 |

## 使用建议

1. **先用 verbose 模式**: `--verbose` 会显示每条 issue 的报告原因
2. **按置信度过滤**: 在 CI 中，你可能只想在 HIGH 置信度时失败
3. **检查 FFI 边界**: 如果 OmniScope 报告 0 个 FFI 边界，说明你的文件可能没有跨语言调用
4. **配合语言原生工具使用**: OmniScope 能发现 Clippy/Clang SA 在 FFI 边界遗漏的问题。建议搭配使用。

## 局限性

- 只能分析 LLVM IR（不支持源码）
- 对 FFI 密集型项目效果最好（Rust+C、Go+C 等）
- 纯 Rust/Go/C++ 项目（无 FFI）报告的问题会较少（这是正常行为）
- Size truncation、buffer overflow 和 type confusion 检测已在计划中，尚未实现

## 获取帮助

- [架构文档](../architecture.md) — 分析流水线的工作原理
- [开发者指南](developer_guide_zh.md) — 参与代码贡献
- [调查报告](../investigation_reports/zh/README.md) — 真实案例分析
