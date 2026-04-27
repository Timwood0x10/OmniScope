# OmniScope 用户指南

本指南提供了安装、配置和使用 OmniScope 进行 LLVM IR 分析的全面说明。

## 目录

1. [安装](#安装)
2. [快速开始](#快速开始)
3. [配置](#配置)
4. [命令行使用](#命令行使用)
5. [库使用](#库使用)
6. [常见工作流程](#常见工作流程)
7. [故障排除](#故障排除)
8. [示例](#示例)

---

## 安装

### 前置要求

在安装 OmniScope 之前，请确保满足以下前置要求：

- **Zig** 版本 0.15.2 或更高
  - 从 [ziglang.org](https://ziglang.org/download/) 下载
  - 验证安装：`zig version`

- **LLVM** 开发库
  - 推荐使用版本 22.x
  - macOS（Homebrew）：`brew install llvm@22`
  - Ubuntu/Debian：`sudo apt-get install llvm-22-dev`
  - Fedora：`sudo dnf install llvm22-devel`

### 从源代码构建

1. 克隆仓库：
```bash
git clone <repository-url>
cd OmniSope
```

2. 配置构建选项：
```bash
# 默认构建
zig build

# 使用自定义 LLVM 路径
zig build -Dllvm-path=/path/to/llvm

# 启用优化
zig build -Doptimize=ReleaseFast

# 启用 LTO
zig build -Denable-lto=true
```

3. 构建项目：
```bash
make build
```

4. 安装（可选）：
```bash
zig build install
```

### 验证安装

运行验证测试以确保一切正常：
```bash
zig build verify-ir
```

---

## 快速开始

### 第一次分析

创建一个简单的 C 程序并编译为 LLVM IR：

```c
// hello.c
#include <stdio.h>

int main() {
    printf("Hello, World!\n");
    return 0;
}
```

编译为位码：
```bash
clang -c -emit-llvm hello.c -o hello.bc
```

使用 OmniScope 分析：
```bash
./zig-out/bin/OmniSope hello.bc
```

预期输出：
```
=== OmniScope 跨语言数据流分析 ===

[*] 正在加载 IR: hello.bc
[*] IR 已加载: 1 个函数

[*] 注册分析 pass...
[*] 运行分析...

=== 分析结果 ===
未发现问题。
```

### 理解输出

OmniScope 提供几种类型的输出：

- **INFO**: 关于分析过程的信息性消息
- **WARN**: 应该审查的潜在问题
- **ERROR**: 检测到的明确问题

输出包括：
- 分析的函数数量
- 执行的 pass
- 发现的问题（如果有）

---

## 配置

### 构建配置

在构建时使用选项配置 OmniScope：

```bash
# 指定 LLVM 安装路径
zig build -Dllvm-path=/opt/homebrew/Cellar/llvm/22.1.3

# 启用链接时优化
zig build -Denable-lto=true

# 设置优化级别
zig build -Doptimize=Debug
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseSmall

# 针对特定平台
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-macos
```

### 运行时配置

可以通过命令行参数在运行时配置 OmniScope：

```bash
# 启用详细日志
./zig-out/bin/OmniSope -v input.bc

# 启用调试日志
./zig-out/bin/OmniSope -d input.bc

# 显示帮助
./zig-out/bin/OmniSope --help

# 显示版本
./zig-out/bin/OmniSope --version
```

---

## 命令行使用

### 基本语法

```bash
OmniSope [选项] <输入文件>
```

### 选项

| 选项 | 描述 |
|------|------|
| `-h, --help` | 显示帮助消息 |
| `-v, --verbose` | 启用详细日志 |
| `-d, --debug` | 启用调试日志 |
| `--version` | 显示版本信息 |
| `--json` | 以稳定 JSON Schema v1 格式输出 |
| `--sarif` | 以 SARIF v2.1.0 格式输出 |
| `-o, --output <文件>` | 输出文件路径 |
| `-l, --level <级别>` | 最低严重级别 (critical/high/medium/low) |

### 示例

**基本分析：**
```bash
./zig-out/bin/OmniSope program.ll
```

**JSON 输出：**
```bash
./zig-out/bin/OmniSope --json program.ll > results.json
./zig-out/bin/OmniSope --json -o results.json program.ll
```

**SARIF 输出（GitHub Code Scanning 兼容）：**
```bash
./zig-out/bin/OmniSope --sarif -o results.sarif program.ll
```

**按严重级别过滤：**
```bash
./zig-out/bin/OmniSope -l high program.ll
```

---

## 库使用

### 初始化 OmniScope

```zig
const std = @import("std");
const OmniScope = @import("OmniScope");

pub fn main() !void {
    // 设置分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化事实存储
    var store = OmniScope.fact.FactStore.init(allocator);
    defer store.deinit();

    // 初始化查询引擎
    var engine = OmniScope.fact.QueryEngine.init(&store);
}
```

### 加载 LLVM IR

```zig
const engine = @import("OmniScope").engine;

// 加载位码文件
var loader = try engine.IRLoader.loadFile(allocator, "input.bc");
defer loader.deinit();

// 检查是否加载了模块
if (loader.hasModule()) {
    std.debug.print("模块加载成功\n", .{});
}

// 获取函数数量
const func_count = loader.getFunctionCount();
std.debug.print("找到 {} 个函数\n", .{func_count});
```

### 使用 Pass

```zig
const pass = @import("OmniScope").pass;

// 创建 pass 上下文
var ctx = pass.PassContext.init(
    allocator,
    loader.getModule(),
    &store,
    &engine,
);

// 创建诊断写入器
var diag = pass.DiagnosticWriter{ .allocator = allocator };

// 运行 pass
var result = OmniScope.cross_lang.CallGraphPass.run(&ctx, &diag) catch |err| {
    std.debug.print("Pass 失败: {}\n", .{err});
    return err;
};
```

### 查询事实

```zig
const fact = @import("OmniScope").fact;

// 按事实类型查询
const cfg_edges = try engine.queryByKind(.cfg_edge, allocator);
defer allocator.free(cfg_edges);

// 按主体查询
const related_facts = try engine.queryBySubject(123, allocator);
defer allocator.free(related_facts);

// 按对象查询
const aliases = try engine.queryByObject(456, allocator);
defer allocator.free(aliases);
```

---

## 常见工作流程

### 工作流程 1: 跨语言数据流分析

检测从源到汇点的跨 FFI 边界的数据流：

```bash
# 分析具有 FFI 调用的程序
./zig-out/bin/OmniSope cross_lang_program.bc

# 预期输出显示：
# - 函数分类（内部、libc、external_unknown）
# - FFI 边界交叉
# - 污点数据流路径
# - 接收污点数据的汇点调用
```

### 工作流程 2: 内存安全分析

检查内存安全问题：

```zig
// 内存安全自定义 pass
const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg", "alias"};

    pub fn run(ctx: *pass.PassContext, diag: *pass.DiagnosticWriter) !void {
        // 检查释放后使用
        // 检查双重释放
        // 检查内存泄漏
    }
};
```

### 工作流程 3: 并发分析

检测潜在的竞态条件和死锁：

```zig
const ConcurrencyPass = struct {
    pub const name = "concurrency";
    pub const kind = pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg", "lock"};

    pub fn run(ctx: *pass.PassContext, diag: *pass.DiagnosticWriter) !void {
        // 分析锁使用
        // 检测潜在死锁
        // 检查数据竞争
    }
};
```

### 工作流程 4: 安全漏洞检测

查找安全漏洞：

```bash
# 分析常见漏洞
./zig-out/bin/OmniSope -v security_critical.bc

# 查找：
# - 缓冲区溢出
# - 整数溢出
# - 格式字符串漏洞
# - 危险函数的使用
```

---

## 故障排除

### 常见问题

#### 问题: 找不到 LLVM 库

**错误：**
```
error: Unable to find LLVM library
```

**解决方案：**
```bash
# 显式指定 LLVM 路径
zig build -Dllvm-path=/path/to/llvm

# 或设置环境变量
export LLVM_DIR=/path/to/llvm
```

#### 问题: 未定义的 LLVM 符号

**错误：**
```
Undefined symbols: "_LLVMContextCreate", ...
```

**解决方案：**
```bash
# 确保 LLVM 库正确链接
# 检查库路径
ls $LLVM_DIR/lib/libLLVM-22.dylib

# 使用正确路径重新构建
zig build -Dllvm-path=$LLVM_DIR
```

#### 问题: 检测到内存泄漏

**错误：**
```
Warning: Memory leak detected!
```

**解决方案：**
```zig
// 更新 main.zig 以检查内存泄漏
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Warning: Memory leak detected!\n", .{});
    }
};
```

#### 问题: Pass 执行失败

**错误：**
```
Pass failed: InvalidIR
```

**解决方案：**
```bash
# 验证输入文件是有效的 LLVM IR
llvm-dis input.bc -o input.ll
# 检查 input.ll 是否有错误

# 使用正确标志重新编译
clang -c -emit-llvm -O0 -g input.c -o input.bc
```

### 调试模式

启用调试日志以获取详细信息：

```bash
./zig-out/bin/OmniSope -d input.bc 2> debug.log
```

### 获取帮助

如果您遇到此处未涵盖的问题：

1. 查看 [GitHub Issues](https://github.com/your-repo/issues)
2. 查看 [架构文档](../plan/improve.md)
3. 查看 [开发者指南](developer_guide_zh.md)

---

## 示例

### 示例 1: 简单 C 程序分析

```c
// simple.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char* buffer = malloc(100);
    if (buffer) {
        strcpy(buffer, "Hello");
        printf("%s\n", buffer);
        free(buffer);
    }
    return 0;
}
```

编译和分析：
```bash
clang -c -emit-llvm simple.c -o simple.bc
./zig-out/bin/OmniSope simple.bc
```

### 示例 2: 跨语言程序

```c
// cross_lang.c
#include <stdio.h>
#include <stdlib.h>

// 外部函数（Rust/Go 等）
extern void external_process(char* data);

int main() {
    char* input = malloc(256);
    if (!input) return 1;

    read(0, input, 256);
    external_process(input);

    free(input);
    return 0;
}
```

编译和分析：
```bash
clang -c -emit-llvm cross_lang.c -o cross_lang.bc
./zig-out/bin/OmniSope -v cross_lang.bc
```

### 示例 3: Zig 中的自定义 Pass

```zig
// my_custom_pass.zig
const std = @import("std");
const Pass = @import("OmniScope").pass.Pass;
const PassContext = @import("OmniScope").pass.PassContext;
const DiagnosticWriter = @import("OmniScope").pass.DiagnosticWriter;

pub const MyCustomPass = struct {
    pub const name = "my-custom-pass";
    pub const kind = Pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        diag.info("开始自定义分析", .{});

        if (!ctx.hasModule()) {
            diag.err("未加载模块", .{});
            return error.NoModule;
        }

        // 此处为自定义分析逻辑
        const next_id = ctx.getNextId();
        diag.info("已分配 ID: {}", .{next_id});

        diag.info("自定义分析完成", .{});
    }
};

const ValidatedPass = Pass(MyCustomPass);
```

---

## 高级主题

### 性能优化

对于大型项目：

```bash
# 启用 LTO 以获得更好的性能
zig build -Denable-lto=true -Doptimize=ReleaseFast

# 使用发布模式进行生产分析
./zig-out/bin/OmniSope large_project.bc
```

### 批处理

分析多个文件：

```bash
#!/bin/bash
for file in *.bc; do
    echo "正在分析 $file..."
    ./zig-out/bin/OmniSope "$file" > "results/${file%.bc}.txt" 2>&1
done
```

### 与 CI/CD 集成

GitHub Actions 示例：

```yaml
name: OmniScope 分析

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: 安装 Zig
        uses: goto-bus-stop/setup-zig@v1
      - name: 安装 LLVM
        run: sudo apt-get install llvm-22-dev
      - name: 构建 OmniScope
        run: make build
      - name: 运行分析
        run: make test
```

---

## 其他资源

- [架构文档](../plan/improve.md)
- [开发者指南](developer_guide_zh.md)
- [API 参考](api_reference_zh.md)
- [Bug 报告](../plan/bugs_report.md)
- [编码指南](../plan/zig_coding_guide.md)

---

## 支持

如有问题、bug 报告或贡献：

- GitHub Issues: [repository-url]/issues
- Discussions: [repository-url]/discussions
- 文档: [repository-url]/wiki

---

**最后更新**: 2026-04-24  
**版本**: v0.1.5