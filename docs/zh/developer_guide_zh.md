# 开发者指南

> "读代码。不是开玩笑，真的去读代码。"

最后更新：2026-05-06 | 版本：v0.1.7

## 架构概览

OmniScope 的核心是一个 **基于 pass 的分析流水线**。把它想象成一条传送带：LLVM IR 从一端进去，问题从另一端出来。

完整的架构文档见 [architecture.md](../architecture.md)。

### Tier 1 / Tier 2

- **Tier 1**（透传）：纯 C/C++ 内部操作。这里我们信任编译器。这些 pass 负责构建数据结构，不报告问题。
- **Tier 2**（图驱动）：FFI/unsafe 边界分析。这是魔法发生的地方。所有问题报告都通过 `isOnDangerPath()` 进行。

### 核心数据结构

| 结构 | 产生者 | 消费者 |
|------|--------|--------|
| `CrossLangEdge` | call-graph | ptr-lifetime, ffi-boundary, callback-escape, danger-surface |
| `MemoryGraph` | ptr-lifetime | danger-surface, free-validation |
| `DangerSurface` markers | danger-surface | ptr-lifetime, callback-escape, free-validation, memory-safety, taint-propagation |

## 添加新 Pass

1. 创建 `src/pass/analysis/your_pass.zig`
2. 定义 `pub const deps: []const []const u8` — 列出你的 pass 依赖的 pass
3. 实现 `pub fn run(ctx: *PassContext) !void`
4. 在 `src/main.zig` 的 pass 注册块中注册
5. 在 `src/pass/analysis/your_pass.zig` 中添加测试（我们喜欢测试）

### Pass 模板

```zig
const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;

pub const name = "your-pass";
pub const deps = &[_][]const u8{ "call-graph" }; // 声明你的依赖！

pub fn run(ctx: *PassContext) !void {
    // 访问共享数据：
    // ctx.cross_edges — 跨语言调用边
    // ctx.memory_graph — 指针跟踪图
    // ctx.danger_surface_relevant_functions — 危险路径上的函数
    // ctx.danger_surface_relevant_allocs — 危险路径上的分配

    // 报告问题：
    // ctx.reportIssue(.{ .kind = .your_issue_kind, ... });
}
```

## 编码规范

这些没得商量：

1. **声明你的 deps**：每个 pass 都必须声明 `pub const deps`。空 deps 意味着"我什么都不需要"——如果你确实需要什么，就写出来。
2. **使用 `isOnDangerPath`**：所有 Tier 2 的问题报告都必须经过这个门。没有例外。
3. **不要静默失败**：出了问题就记日志。我们有诊断系统，用起来。
4. **测试你的代码**：我们目前覆盖率 92%。让我们保持这个水平。
5. **唯一真相源**：如果一个函数/分类已经存在于某个地方，就 import 它。别复制粘贴。我们在这上面吃过亏。

## 项目结构

```
src/
├── common/          # 共享工具
├── ir/              # LLVM IR 包装类型
├── dataflow/        # 数据流分析框架
├── semantics/       # 语义知识（分配器、噪声过滤器、内存图）
├── pass/
│   ├── pass.zig     # PassContext、问题报告、区域分类
│   ├── pipeline.zig # Pass 执行引擎
│   ├── analysis/    # 分析 pass（共 13 个）
│   └── issue/       # 问题验证 pass
├── registry/        # Hook 注册表（into_raw/from_raw 配对）
├── pipeline/        # 流水线编排
├── diag/            # 诊断和日志
├── ffi/             # FFI 类型系统
├── lifetime/        # 生命周期跟踪
├── output/          # 输出格式化（JSON、文本）
├── perf/            # 性能分析
├── fact/            # 事实存储
├── report/          # 报告生成
└── visual/          # 可视化辅助工具
```

## 测试

```bash
# 运行所有测试
zig build test

# 运行特定测试
zig build test --filter "ptr_lifetime"

# 带详细输出运行
zig build test --filter "noise_reduction" -fsummary
```

## 已知问题

当前已知 bug 及其状态见 [architecture.md](../architecture.md#known-issues)。

## 贡献

1. Fork 仓库
2. 创建 feature 分支
3. 写代码 + 测试
4. `zig build test` 必须通过
5. 提交 PR

我们 review 每个 PR。我们很友好。可能会毒舌，但我们是友好的。
