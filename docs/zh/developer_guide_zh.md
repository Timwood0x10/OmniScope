# OmniScope 开发者指南

本指南适用于希望为 OmniScope 做出贡献、创建自定义 pass 或扩展框架的开发者。

## 目录

1. [开发环境设置](#开发环境设置)
2. [代码组织](#代码组织)
3. [编码规范](#编码规范)
4. [Pass 开发](#pass-开发)
5. [测试](#测试)
6. [构建系统](#构建系统)
7. [调试](#调试)
8. [贡献指南](#贡献指南)
9. [性能优化](#性能优化)

---

## 开发环境设置

### 前置要求

- **Zig** 0.15.2 或更高版本
- **LLVM** 22.x 开发库
- **Git** 用于版本控制
- **Make** 用于构建自动化

### IDE/编辑器配置

#### VSCode

安装这些扩展：
- `ziglang.vscode-zig` - Zig 语言支持
- `llvm-vs-code-extensions.vscode-llvm` - LLVM 支持

**`.vscode/settings.json`**:
```json
{
    "zig.zigPath": "/path/to/zig",
    "zig.buildOnSave": false,
    "zig.formatOnSave": true,
    "zig.checkForUpdate": false
}
```

#### Vim/Neovim

安装 Zig 插件：
```vim
Plug: ziglang/zig.vim
```

配置：
```vim
autocmd FileType zig setlocal expandtab
autocmd FileType zig setlocal tabstop=4
autocmd FileType zig setlocal shiftwidth=4
```

### 开发工作流程

```bash
# 1. 创建功能分支
git checkout -b feature/my-new-feature

# 2. 进行更改
vim src/pass/analysis/my_pass.zig

# 3. 格式化代码
make fmt

# 4. 检查错误
make check

# 5. 运行测试
make test

# 6. 提交更改
git add .
git commit -m "feat: add my new feature"

# 7. 推送并创建 PR
git push origin feature/my-new-feature
```

---

## 代码组织

### 目录结构

```
src/
├── main.zig                  # CLI 入口点
├── root.zig                  # 库公共 API
├── ir/                      # LLVM IR 包装器
│   ├── llvm_raw.zig         # 原始 LLVM C API 绑定
│   ├── llvm_safe.zig        # 安全包装器
│   ├── view.zig             # IR 视图工具
│   ├── location.zig          # 源代码位置跟踪
│   └── debug_info.zig       # 调试信息解析
├── engine/                   # 核心引擎
│   └── loader.zig           # IR 文件加载
├── pass/                     # 分析 passes
│   ├── pass.zig             # PassContext + Pass 接口
│   ├── manager.zig          # Pass 管理器
│   ├── foundation/          # 基础 passes
│   │   ├── cfg.zig         # 控制流图
│   │   └── dfg.zig         # 数据流图
│   ├── analysis/           # 分析 passes
│   │   ├── pointer_ownership.zig    # 核心内存泄漏/UAF (936 行)
│   │   ├── allocation_classifier.zig  # AllocType/FreeType (206 行)
│   │   ├── cpp_fp_reduction.zig       # C++ 8 层 FP 过滤 (937 行)
│   │   ├── rust_ffi_auditor.zig       # Rust FFI 审计器 (464 行) ← v0.1.5
│   │   ├── ffi_detector.zig          # FFI 边界检测
│   │   ├── ffi_analysis.zig          # FFI 分析
│   │   ├── ffi_boundary.zig          # FFI 边界分析器
│   │   ├── ffi_info.zig             # FFI 信息注册表
│   │   ├── ffi_semantics.zig         # FFI 语义注册表
│   │   ├── call_graph.zig           # 调用图 + 污染路径
│   │   ├── taint.zig                 # 污染分析
│   │   ├── taint_propagation.zig     # 污染传播
│   │   ├── taint_state.zig           # 污染状态管理
│   │   ├── lock.zig                 # 锁分析 (719 行)
│   │   ├── alias.zig                # 别名分析
│   │   ├── steensgaard.zig          # Steensgaard 指针分析
│   │   ├── vulnerability_rules.zig  # 漏洞规则引擎
│   │   ├── flow_path.zig             # 数据流路径分析
│   │   └── issue/                    # 问题特定检查器
│   │       ├── ffi_unsafe.zig       # 不安全 FFI 调用
│   │       ├── ffi_body_check.zig   # FFI 函数体检查
│   │       ├── malloc_check.zig     # malloc 验证
│   │       ├── free_validation.zig  # free() 验证
│   │       ├── memory_safety.zig    # 内存安全检查
│   │       ├── return_check.zig     # 返回值检查
│   │       └── integer_overflow.zig  # 整数溢出
│   └── instrumentation/      # 插桩 passes
│       └── planner.zig    # 插桩规划器
├── fact/                     # 事实存储系统 (SoA 布局)
│   ├── fact.zig           # 事实类型定义
│   ├── store.zig           # 事实存储
│   ├── query.zig           # 查询引擎
│   └── ownership_fact.zig  # 所有权事实
├── dataflow/                 # 数据流分析
│   ├── graph.zig           # DFG 构建
│   ├── node.zig            # 数据流节点
│   ├── edge.zig            # 数据流边
│   ├── guard_propagation.zig # Guard 传播
│   ├── null_check_guard.zig # 空值检查分析
│   ├── path_condition.zig  # 路径条件
│   ├── value_id_map.zig    # 值 ID 映射
│   └── function_summary.zig # 函数摘要
├── lifetime/                 # 生命周期和边界分析
│   ├── engine.zig          # 生命周期引擎
│   ├── boundary.zig        # 跨语言边界分析器
│   ├── mapper.zig          # 生命周期映射器
│   └── root.zig            # 生命周期模块根
├── registry/                 # 语义注册表
│   ├── semantic_registry.zig # 函数语义知识库
│   ├── config_loader.zig   # JSON 配置加载器
│   └── sanitizer_registry.zig # 消毒剂注册表
├── diag/                     # 诊断
│   ├── issue.zig           # 问题类型 + 置信度系统
│   └── aggregator.zig      # 诊断聚合
├── output/                   # 输出适配器
│   ├── cli.zig            # CLI 输出
│   ├── formatter.zig       # 文本格式化器
│   ├── sarif.zig          # SARIF v2.1.0 输出
│   └── lsp.zig            # LSP 集成
├── report/                   # 报告生成
│   ├── mod.zig            # 报告生成器
│   ├── sarif.zig          # SARIF 报告 (v2.1.0)
│   └── ci_integration.zig # CI/CD 集成
├── pipeline/                 # 分析管道
│   └── pipeline.zig       # 管道编排
├── tracking/                 # 内存跟踪
│   ├── allocator.zig      # 分配跟踪
│   └── mod.zig            # 跟踪模块
└── perf/                     # 性能分析
    ├── profiler.zig        # 性能分析器
    ├── memory_pool.zig     # 内存池
    ├── analysis_context.zig # 分析上下文
    └── bench_compare.zig    # 基准比较

### 模块依赖

```
main.zig
  └── root.zig
        ├─> ir/
        ├─> pass/
        ├─> fact/
        ├─> runtime/
        ├─> diag/
        ├─> plugin/
        ├─> output/
        └─> log/

pass/
  ├─> ir/
  ├─> fact/
  └─> log/

fact/
  └─> log/

runtime/
  └─> log/
```

---

## 编码规范

### 文件命名

- 所有 Zig 文件使用 `snake_case`
- 保持文件名描述性和简洁性
- 尽可能一个文件一个公共类型

示例：
- `pass.zig` ✓
- `Pass.zig` ✗
- `fact_store.zig` ✓
- `FactStore.zig` ✗

### 代码风格

#### 缩进和格式化

- 使用 4 个空格缩进（不使用制表符）
- 最大行长度：100 个字符
- 使用 `zig fmt` 格式化代码

```bash
# 格式化所有 Zig 文件
make fmt

# 格式化特定文件
zig fmt src/pass/pass.zig
```

#### 命名约定

```zig
// 类型：PascalCase
const FactStore = struct { ... };
const PassContext = struct { ... };

// 函数：camelCase
pub fn run(ctx: *PassContext) !void { ... }
pub fn insertFact(store: *FactStore, fact: Fact) !void { ... }

// 常量：UPPER_SNAKE_CASE
pub const MAX_FUNCTIONS: usize = 1_000_000;
pub const DEFAULT_TIMEOUT: u64 = 5000;

// 变量：camelCase
var next_id: u32 = 0;
const function_count = loader.getFunctionCount();

// 枚举：类型用 PascalCase，值用小写
pub const PassKind = enum {
    foundation,
    analysis,
    plugin,
};

// 错误集：PascalCase
pub const LoaderError = error{
    FileNotFound,
    InvalidIR,
    OutOfMemory,
};
```

#### 注释

- 使用 `///` 表示文档注释
- 使用 `//!` 表示模块级文档
- 使用 `//` 表示行内注释
- 所有注释必须使用英文

```zig
//! 此模块提供具有编译时验证的 Pass 接口
//!
//! Pass 系统通过编译时类型检查实现模块化分析。

/// 表示单个分析 pass
///
/// Pass 是 OmniScope 中分析的主要单元。
/// 每个 pass 实现 Pass 接口并可以声明依赖关系。
pub const Pass = struct {
    /// 用于标识的 pass 名称
    pub const name: []const u8 = "example";

    /// pass 类型分类
    pub const kind: PassKind = .analysis;

    /// 必须在此 pass 之前运行的依赖项
    pub const deps: []const []const u8 = &.{};

    /// 运行 pass 分析
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // 实现
    }
};
```

#### 错误处理

- 使用 Zig 的错误联合类型（`!T`）表示可能失败的函数
- 提供描述性错误消息
- 适当地处理错误

```zig
// 好
pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        log.err("Failed to open file: {} (path: {s})", .{err, path});
        return error.FileNotFound;
    };
    defer file.close();

    // ... 其余实现
}

// 差
pub fn loadFile(allocator: Allocator, path: []const u8) !IRLoader {
    // 错误处理模糊
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        // ...
    } else |_| {
        return error.Fail;
    }
}
```

#### 内存管理

- 始终使用显式分配器
- 遵循 RAII 模式进行资源管理
- 在 `defer` 语句中清理资源

```zig
// 好
pub fn analyze(allocator: Allocator, input: []const u8) !void {
    var store = FactStore.init(allocator);
    defer store.deinit();

    var nodes = std.ArrayList(Node).init(allocator);
    defer nodes.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
}

// 差
pub fn analyze(allocator: Allocator, input: []const u8) !void {
    var store = FactStore.init(allocator);
    // 缺少 defer store.deinit() - 内存泄漏！

    var nodes = std.ArrayList(Node).init(allocator);
    // 缺少 defer nodes.deinit() - 内存泄漏！
}
```

### 测试标准

- 为所有公共函数编写测试
- 使用描述性测试名称
- 测试边界情况和错误条件
- 保持测试覆盖率在 80% 以上

```zig
test "PassContext - getNextId 生成唯一 ID" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    const id1 = ctx.getNextId();
    const id2 = ctx.getNextId();
    const id3 = ctx.getNextId();

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);
}

test "PassContext - getNextId 处理溢出" {
    // 测试边界情况
}
```

---

## Pass 开发

### Pass 接口

每个 pass 必须实现以下接口：

```zig
pub const MyPass = struct {
    /// Pass 名称（必须唯一）
    pub const name: []const u8 = "my-pass";

    /// Pass 类型
    pub const kind: PassKind = PassKind.analysis;

    /// 依赖项（必须在此 pass 之前运行）
    pub const deps: []const []const u8 = &.{ "cfg", "dfg" };

    /// 运行 pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Pass 实现
    }
};

// 在编译时验证 pass
const ValidatedPass = Pass(MyPass);
```

### Pass 类型

```zig
pub const PassKind = enum {
    foundation,  // 基础分析 pass（CFG、DFG）
    analysis,    // 高级分析 pass（别名、锁、污点）
    plugin,      // 用户定义的插件 pass
};
```

### Pass 上下文

`PassContext` 提供对分析资源的访问：

```zig
pub const PassContext = struct {
    allocator: Allocator,              // 内存分配器
    module: ?ModuleRef,                // LLVM 模块（如果已加载）
    fact_store: *FactStore,            // 事实存储
    query_engine: *QueryEngine,        // 查询引擎
    next_id: std.atomic.Value(u32),    // ID 分配器

    // 获取唯一 ID（线程安全）
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    // 设置 IR 模块
    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    // 检查是否加载了模块
    pub fn hasModule(self: *PassContext) bool {
        return self.module != null;
    }
};
```

### 创建基础 Pass

```zig
pub const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const module = ctx.module orelse return;

        // 遍历函数
        var func = llvm.LLVMGetFirstFunction(module.raw);
        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            // 为每个函数构建 CFG
            try buildCFG(ctx, func);
        }
    }

    fn buildCFG(ctx: *PassContext, func: llvm.LLVMValueRef) !void {
        // 实现
    }
};
```

### 创建分析 Pass

```zig
pub const AliasPass = struct {
    pub const name = "alias";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // 查询 CFG 和 DFG 事实
        const cfg_edges = try ctx.query_engine.queryByKind(.cfg_edge, ctx.allocator);
        defer ctx.allocator.free(cfg_edges);

        // 执行别名分析
        for (cfg_edges) |edge| {
            try analyzeAlias(ctx, edge);
        }
    }

    fn analyzeAlias(ctx: *PassContext, edge: Fact) !void {
        // 实现
    }
};
```

### 创建插件 Pass

```zig
pub const CustomPluginPass = struct {
    pub const name = "custom-plugin";
    pub const kind = PassKind.plugin;
    pub const deps = &[_][]const u8{ "cfg" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        diag.info("运行自定义插件", .{});

        // 自定义分析逻辑
        const next_id = ctx.getNextId();
        try ctx.fact_store.insert(.custom_fact, next_id, 0, 0);

        diag.info("插件完成", .{});
    }
};
```

### 最佳实践

1. **声明依赖关系**：始终声明依赖关系以确保正确的执行顺序
2. **使用事实存储**：通过事实存储传递数据，而不是直接传递
3. **处理错误**：正确处理所有错误条件
4. **编写测试**：为每个 pass 创建全面的测试
5. **文档**：为 pass 行为提供清晰的文档

---

## 测试

### 测试组织

```
tests/
├── integration.zig           # 集成测试
├── e2e_ir_test.zig          # 端到端 IR 测试
├── integration_ir_test.zig  # 集成 IR 测试
└── ir/                      # 测试 IR 文件
    ├── test_c_control_flow.c
    ├── test_c_pointers.c
    ├── test_c_threads.c
    ├── test_cpp_classes.cpp
    ├── test_cpp_virtual.cpp
    └── test_rust_patterns.rs
```

### 运行测试

```bash
# 运行所有测试
make test-all

# 运行单元测试
make test-unit

# 运行集成测试
make test-int

# 运行 Issue 验证测试
make test-issues

# 运行稳定性测试
make test-stability

# 运行性能基准测试
make bench

# 运行特定测试文件
zig test src/fact/store.zig

# 使用详细输出运行测试
zig test src/pass/pass.zig --summary all
```

### 编写测试

```zig
test "FactStore - 插入和查询事实" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    // 插入事实
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.cfg_edge, 2, 3, 1);

    // 查询事实
    const facts = try store.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
    try std.testing.expectEqual(@as(u32, 1), facts[0].subject);
}

test "IRLoader - 加载无效文件" {
    const result = IRLoader.loadFile(std.testing.allocator, "nonexistent.bc");
    try std.testing.expectError(error.FileNotFound, result);
}
```

### 测试覆盖率

检查测试覆盖率：

```bash
# 安装 kcov (Linux)
sudo apt-get install kcov

# 运行测试并生成覆盖率
zig build test --enable-coverage

# 生成覆盖率报告
kcov --include-pattern=src/ coverage/ zig-cache/test/...
```

---

## 构建系统

### 构建配置

`build.zig` 文件定义了构建系统：

```zig
pub fn build(b: *std.Build) void {
    // 解析选项
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_lto = b.option(bool, "enable-lto", "启用 LTO") orelse false;

    // 创建库模块
    const lib_mod = b.addModule("OmniScope", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // 构建可执行文件
    const exe = b.addExecutable(.{
        .name = "OmniSope",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });

    // 添加 LLVM 配置
    exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    exe.linkSystemLibrary("LLVM-22");
    exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

    b.installArtifact(exe);
}
```

### 构建步骤

```bash
# 可用的构建步骤
zig build --help

# 构建可执行文件
zig build

# 运行测试
zig build test

# 运行集成测试
zig build integration-test

# 运行端到端测试
zig build e2e-test

# 构建运行时库
zig build rt

# 验证 IR 加载
zig build verify-ir

# 运行演示
zig build demo
```

### Makefile 目标

```bash
make build          # 构建项目
make test-all       # 运行所有测试（单元+集成+稳定性）
make test-unit      # 运行单元测试
make test-int       # 运行集成测试
make test-issues    # 运行 Issue 验证测试
make test-stability # 运行稳定性测试
make bench          # 运行性能基准测试
make check          # 检查编译错误
make fmt            # 格式化代码
make clean          # 清理构建产物
make corpus         # 编译测试语料库
make corpus-analyze # 分析测试语料库
make run            # 运行 FFI 例子分析
```

---

## 调试

### 使用 Zig 内置调试器

```bash
# 使用调试符号构建
zig build -Doptimize=Debug

# 使用 LLDB 运行
lldb ./zig-out/bin/OmniSope
(lldb) b main
(lldb) run input.bc
(lldb) bt
```

### 调试日志

启用调试日志：

```bash
./zig-out/bin/OmniSope -d input.bc
```

添加自定义调试消息：

```zig
const log = @import("log/log.zig");

pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    log.debug("my-pass", "Starting analysis", .{});
    log.debug("my-pass", "Module loaded: {}", .{ctx.hasModule()});
    log.debug("my-pass", "Fact count: {}", .{ctx.fact_store.count()});
}
```

### 内存调试

使用 Valgrind 检测内存泄漏：

```bash
# 使用调试符号构建
zig build -Doptimize=Debug

# 使用 Valgrind 运行
valgrind --leak-check=full ./zig-out/bin/OmniSope input.bc
```

### 常见调试技术

#### 打印调试

```zig
pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    std.debug.print("Starting pass\n", .{});
    std.debug.print("Module: {?}\n", .{ctx.module});
    std.debug.print("Fact store size: {}\n", .{ctx.fact_store.count()});
}
```

#### 断言调试

```zig
const assert = @import("log/debug.zig").assert;

pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    assert(ctx.module != null, "Module must be loaded");
    assert(ctx.fact_store != null, "Fact store must be initialized");
}
```

---

## 贡献指南

### 贡献前

1. 阅读本开发者指南
2. 查看编码规范
3. 了解架构
4. 检查现有问题和 PR

### 进行更改

1. **创建分支**：
```bash
git checkout -b feature/your-feature-name
```

2. **进行更改**：
   - 遵循编码规范
   - 编写测试
   - 更新文档

3. **格式化和检查**：
```bash
make fmt
make check
```

4. **运行测试**：
```bash
make test
```

5. **提交**：
```bash
git add .
git commit -m "type: description"
```

6. **推送并创建 PR**：
```bash
git push origin feature/your-feature-name
# 在 GitHub 上创建 PR
```

### 提交消息格式

```
<type>(<scope>): <description>

[可选正文]

[可选页脚]
```

类型：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更改
- `style`: 代码样式更改（格式化）
- `refactor`: 代码重构
- `test`: 添加或更新测试
- `chore`: 构建过程或辅助工具更改

示例：
```
feat(pass): 添加调用图分析 pass

实现 CFG 构建和函数调用跟踪。
为基本和复杂调用图添加测试。

Closes #123
```

```
fix(loader): 正确处理 LLVM 错误消息

修复 LLVM 错误消息在文件加载失败后未被释放的内存泄漏。

Fixes #456
```

### Pull Request 检查清单

- [ ] 代码遵循编码规范
- [ ] 代码已格式化（`make fmt`）
- [ ] 所有测试通过（`make test`）
- [ ] 为新功能添加新测试
- [ ] 文档已更新
- [ ] 提交消息遵循格式
- [ ] PR 描述解释更改

---

## 性能优化

### 性能分析

```bash
# 使用性能分析支持构建
zig build -Doptimize=ReleaseFast

# 使用性能分析器运行
./zig-out/bin/OmniSope input.bc

# 分析结果
# （平台特定的性能分析器工具）
```

### 优化技术

#### 使用 SoA 布局

```zig
// 好 - 结构数组
pub const FactStore = struct {
    kinds: []FactKind,
    subjects: []u32,
    objects: []u32,
    contexts: []u32,
};

// 差 - 结构数组（缓存不友好）
pub const FactStore = struct {
    facts: []Fact,  // Fact 包含所有字段
};
```

#### 最小化分配

```zig
// 好 - 预分配容量
var nodes = std.ArrayList(Node).initCapacity(allocator, estimated_count) catch unreachable;

// 差 - 根据需要重新分配
var nodes = std.ArrayList(Node).init(allocator);
```

#### 使用 Comptime

```zig
// 好 - 编译时验证
const ValidatedPass = Pass(MyPass);

// 差 - 运行时验证（较慢）
if (!isValidPass(MyPass)) {
    return error.InvalidPass;
}
```

### 内存使用优化

```bash
# 监控内存使用
/usr/bin/time -v ./zig-out/bin/OmniSope input.bc

# 使用 heaptrack 进行性能分析 (Linux)
heaptrack ./zig-out/bin/OmniSope input.bc
heaptrack_print heaptrack.out.*.gz
```

---

## 其他资源

- [Zig 文档](https://ziglang.org/documentation/master/)
- [LLVM 文档](https://llvm.org/docs/)
- [架构文档](../plan/improve.md)
- [Bug 报告](../plan/bugs_report.md)
- [编码指南](../plan/zig_coding_guide.md)

---

**最后更新**: 2026-04-17  
**版本**: v0.2 Alpha