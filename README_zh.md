# OmniScope

**跨语言静态安全分析工具**

OmniScope 是一个基于 LLVM IR 的静态分析工具，专注于检测跨语言 FFI 边界的安全漏洞。

## 核心特性

- **跨语言数据流分析**：追踪 Rust ↔ C、Zig ↔ C 等 FFI 边界的数据流
- **安全漏洞检测**：命令注入、缓冲区溢出、内存泄漏、双重释放等
- **Traceable 输出**：每个漏洞都带有完整的推理路径
- **模块化 Pass 架构**：易于扩展新的检测规则

## 快速开始

### 前置要求

- Zig 0.15.2
- LLVM 22 (macOS: `brew install llvm`)

### 构建

```bash
make build
```

### 运行分析

```bash
# 分析单个 LLVM IR 文件
./zig-out/bin/OmniSope target.bc

# 分析多个文件（FFI 模式）
./zig-out/bin/OmniSope rust.ll c.ll

# JSON 输出
./zig-out/bin/OmniSope --json target.bc
```

## 检测的漏洞类型

| 漏洞类型       | Issue Kind          | 严重性      |
| ---------- | ------------------- | -------- |
| 命令注入       | `command_injection` | Critical |
| 缓冲区溢出      | `buffer_overflow`   | High     |
| 双重释放       | `double_free`       | High     |
| Malloc 未检查 | `malloc_unchecked`  | High     |
| 非法 free    | `invalid_free`      | High     |
| FFI 不安全调用  | `ffi_unsafe_call`   | Medium   |
| 整数溢出       | `integer_overflow`  | Medium   |
| 格式字符串      | `format_string`     | Medium   |

## 示例：Killer Demo

```bash
cd examples/rust_ffi_demo
make ir        # 生成 LLVM IR
make analyze   # 运行 OmniScope
```

### 检测结果示例

```
[INFO] FreeValidation: Analyzed functions, found 3 invalid free calls
[INFO] MallocCheck: Analyzed functions, found 1 unchecked allocations
[INFO] FFIUnsafe: Analyzed 79 boundaries, found 7 issues
[INFO] IntegerOverflow: Analyzed functions, found 8 potential overflows

info: Issues detected: 20
```

## 架构

```
src/
├── pass/
│   ├── analysis/
│   │   ├── issue/           # 漏洞检测 Pass
│   │   │   ├── malloc_check.zig
│   │   │   ├── free_validation.zig
│   │   │   ├── memory_safety.zig
│   │   │   ├── ffi_unsafe.zig
│   │   │   └── integer_overflow.zig
│   │   └── ffi_semantics.zig
│   └── manager.zig
├── dataflow/
│   └── graph.zig            # 数据流图
├── ffi/
│   └── ffi_matcher.zig      # FFI 边界匹配
├── diag/
│   └── issue.zig            # Issue 定义
└── pipeline/
    └── pipeline.zig         # 分析管道
```

## Pass 开发指南

### 创建新 Pass

1. 在 `src/pass/analysis/issue/` 创建新文件
2. 实现 Pass 接口：

```zig
pub const MyPass = struct {
    pub const name = "my-pass";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // 分析逻辑
        const issue = Issue.init(
            .unknown,
            try std.fmt.allocPrint(ctx.allocator, "Issue found", .{}),
            Location.init("func"),
            .medium,
            0.8,
        );
        try ctx.addIssue(issue);
    }
};
```

1. 在 `pass/manager.zig` 中注册

### Pass 依赖

```zig
pub const deps = &[_][]const u8{ "ffi-boundary", "call-graph" };
```

## 输出格式

### 人类可读

```
[WARN] Integer overflow detected in function: process_data
[WARN] Unchecked malloc result in function: dangerous_alloc
[INFO] Issues detected: 20
```

### JSON

```json
{
  "issue": "malloc_unchecked",
  "message": "malloc() result used without null check",
  "severity": "high",
  "confidence": 0.85,
  "location": "dangerous_alloc",
  "trace": [
    {
      "step": 1,
      "description": "Allocation function called without null check"
    },
    {
      "step": 2,
      "description": "Allocation via malloc() returns nullable pointer"
    }
  ]
}
```

## 限制

- 需要编译后的 LLVM IR（不支持源码直接分析）
- 跨函数分析有限（主要在函数内分析）
- 需要调试信息以获得更好的位置报告

## 贡献

欢迎贡献！请确保：

1. 遵循 `zig `的编码规范
2. 添加测试
3. 运行 `zig build test` 确保通过

## 许可证

MIT License
