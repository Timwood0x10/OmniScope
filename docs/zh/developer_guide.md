# 开发者指南

> "读代码。不是开玩笑，真的去读代码。"
>
> **⚠️ 实事求是声明**：本指南反映 v0.2.0 的真实开发状态，包含已知的限制和测试覆盖情况。
>
> 最后更新：2026-06-01 | 版本：v0.2.0 | 对应代码：VERSION 0.2.0, LLVM 22

## 架构概览

OmniScope 的核心是一个 **基于 pass 的分析流水线**。把它想象成一条传送带：LLVM IR 从一端进去，问题从另一端出来。

完整的架构文档见 [architecture.md](./architecture.md)（**新增中文版**）。

### 三层架构（v0.2.0）

- **Tier 1**（透传）：纯 C/C++ 内部操作。这里我们信任编译器。这些 pass 负责构建数据结构，不报告问题。（4个pass）
- **Tier 2**（图驱动）：FFI/unsafe 边界分析。这是魔法发生的地方。所有问题报告都通过 `isOnDangerPath()` 进行。（9个pass）
- **Tier 3**（FP 抑制层）：SRT + Issue Gate + Confidence Scorer。这不是 pass，而是 issue 发出前的统一抑制系统。（8个detectors + 1个gate + 1个scorer）

### 核心数据结构

| 结构 | 产生者 | 消费者 | 说明 |
|------|--------|--------|------|
| `CrossLangEdge` | call-graph | ptr-lifetime, ffi-boundary, callback-escape, danger-surface | 跨语言调用边 |
| `MemoryGraph` | ptr-lifetime | danger-surface, free-validation | 指针跟踪图 |
| `DangerSurface` markers | danger-surface | ptr-lifetime, callback-escape, free-validation, memory-safety, taint-propagation | 危险路径标记 |
| `SemanticTree` | R-0~R-7 Detectors | Issue Gate | 语义解析结果（27+ SemanticKind） |

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
4. **测试你的代码**：我们目前覆盖率 92%+，343 个测试全通过。让我们保持这个水平。
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

> **⚠️ 真实测试状态**：以下反映当前的测试基础设施和覆盖率情况。

### 测试套件概览

| 测试类别 | 命令 | 测试数量（估计） | 覆盖范围 | 最后验证 |
|----------|------|------------------|----------|----------|
| **全量测试** | `zig build test` | 340+ | 所有模块集成 | 2026-06-01 |
| **单元测试** | `zig build unit-test` | ~50+ | 核心数据结构和算法 | 2026-06-01 |
| **集成测试** | `zig build test-integration` | ~20+ | 完整流水线 + IR 文件 | 2026-06-01 |
| **Issue 验证测试** | `zig build test-issues` | ~15+ | Issue 检测准确性 | 2026-06-01 |
| **稳定性测试** | `zig build test-stability` | ~10+ | 崩溃恢复和异常输入 | 2026-06-01 |
| **压力测试** | `zig build test-stress` | ~8+ | 大规模数据和边界条件 | 2026-06-01 |
| **E2E 测试** | `zig build e2e-test` | ~12+ | 真实 IR 文件端到端 | 2026-06-01 |
| **语义解析测试** | `zig build test-semantic` | ~25+ | SRT detector 准确性 | 2026-06-01 |
| **回归测试 (P0)** | `zig build test-p0-regression` | ~15+ | 关键 bug 修复验证 | 2026-06-01 |
| **回归测试 (P1)** | `zig build test-p1-regression` | ~20+ | 高优先级修复验证 | 2026-06-01 |
| **增强测试 (P2)** | `zig build test-p2-enhancement` | ~18+ | 功能增强验证 | 2026-06-01 |
| **Rust FFI 测试** | `zig build test-rust-ffi` | ~30+ | Rust 特定 FFI 模式 | 2026-06-01 |
| **Go/Python/Java 测试** | `zig build test-gopyjava-ffi` | ~12+ | 多语言 FFI 模式 | 2026-06-01 |
| **性能基准测试** | `zig build bench-perf` | ~10+ | 性能回归检测 | 2026-06-01 |

### 运行测试

```bash
# 运行所有测试（推荐在提交 PR 前）
zig build test

# 运行特定测试
zig build test --filter "ptr_lifetime"
zig build test --filter "noise_reduction" -fsummary

# 运行带详细输出的测试
zig build test --filter "issue_suppression" -freference-trace -fsummary

# 仅运行单元测试（快速）
zig build unit-test

# 运行稳定性测试（检查崩溃恢复）
zig build test-stability

# 运行 E2E 测试（需要真实的 .ll 文件）
zig build e2e-test
```

### 测试覆盖率现状

> **⚠️ 诚实声明**

| 模块/功能 | 估计覆盖率 | 测试质量 | 说明 |
|-----------|-----------|----------|------|
| **核心 Pass 系统** | 90%+ | ✅ 高 | cfg, dfg, call-graph 等基础 pass |
| **Tier 2 分析 Pass** | 85%+ | ✅ 高 | ffi-boundary, ptr-lifetime 等 |
| **SRT Detectors (R-0~R-3, R-6~R-7)** | 80%+ | ✅ 中高 | 已实现的 8 个 detector |
| **Issue Gate** | 75%+ | ✅ 中 | 主要路径已覆盖，边缘情况有限 |
| **Confidence Scorer** | 70%+ | ⚠️ 中 | 基本评分逻辑已测试，组合场景有限 |
| **C/C++ 支持** | 92%+ | ✅ 高 | 最成熟的语言支持 |
| **Rust 支持** | 88%+ | ✅ 高 | 专用测试套件，FFI 边界重点覆盖 |
| **Zig 支持** | 50%+ | ⚠️ 低 | Beta 状态，基本功能测试 |
| **Go 支持** | 35%+ | ❌ 低 | Experimental，仅 basic tests |
| **Python/Java 支持** | 20%+ | ❌ 极低 | Minimal/no dedicated tests |
| **C# 支持** | 0% | ❌ 无 | 未实现 |
| **错误处理/异常路径** | 65%+ | ⚠️ 中 | 主要错误场景已覆盖 |
| **性能敏感路径** | 60%+ | ⚠️ 中 | 有 bench tests，但覆盖率不完整 |

### 已知测试缺口

1. **多语言支持测试不足**：Go/Python/Java 的测试覆盖率显著低于 C/C++/Rust
2. **边缘情况组合测试缺失**：多个 SRT detector 同时触发时的交互行为
3. **大规模性能回归测试不足**：>10K functions 的项目测试有限
4. **负面测试（确保不误报）不够系统化**：缺少已知的"安全代码"回归集
5. **并发安全性测试缺失**：多线程场景下的测试覆盖几乎为零

## 已知问题

当前已知 bug 及其状态见 [architecture.md](./architecture.md#-已知问题列表-v020)。

**关键已知问题摘要**（v0.2.0）：

| 类别 | 数量 | 严重度 | 状态 |
|------|------|--------|------|
| Pass 依赖 Bug | 3 | P2 (Medium) | 故意保留，计划 v0.2.1 修复 |
| 语义注册表缺陷 | 2 | P1/P3 | 部分影响精度 |
| FP 抑制边缘情况 | 3 | 低-中 | 已知限制 |
| 其他 (内存/平台) | 3 | 低 | 非关键 |

详细列表和 Bug ID 见 architecture.md 的「🐛 已知问题列表」章节。

## 如何添加新 Detector（SRT Pattern Detector）

> **重要**：这是 v0.2.0 架构的核心扩展点。添加新 detector 可以自动受益于现有的 Issue Gate 抑制系统。

### 步骤概览

1. **定义新的 SemanticKind 变体**
2. **创建 detector 实现文件**
3. **注册 detector 到 SRT 流水线**
4. **添加 Gate 规则（如果需要抑制 issue）**
5. **编写测试**

### 详细步骤

#### 1. 定义 SemanticKind 变体

在 `src/semantics/semantic_tree.zig` 中添加新的枚举值：

```zig
pub const SemanticKind = enum(u16) {
    // ... existing kinds ...

    // ── R-9: Your New Detector ──
    your_new_kind = 900, // 使用 900+ 范围避免冲突
    _,
};
```

#### 2. 创建 Detector 文件

在 `src/semantics/patterns/` 下创建新文件：

```zig
// src/semantics/patterns/your_detector.zig
const std = @import("std");
const SemanticTree = "../semantic_tree.zig";
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;

/// 检测你的特定模式并填充 SRT
pub fn detect(allocator: std.mem.Allocator, srt: *SemanticTree, value_ref: u64) !?f32 {
    // 你的检测逻辑在这里
    // 返回置信度 (0.0 ~ 1.0)，或 null 如果不匹配

    // 示例：检测某种 IR 模式
    if (isYourPattern(value_ref)) {
        try srt.addResolution(value_ref, .your_new_kind, 0.90);
        return 0.90;
    }

    return null;
}
```

#### 3. 注册到 SRT 流水线

在 `src/pass/analysis/semantic_resolver_pass.zig` 或相关位置注册你的 detector：

```zig
// 在 SRT 初始化逻辑中添加
const your_detector = @import("../../semantics/patterns/your_detector.zig");

// 在检测循环中调用
if (your_detector.detect(allocator, &srt, value_ref)) |confidence| {
    // 成功检测到模式
}
```

#### 4. 添加 Gate 规则（可选）

如果你的 detector 用于抑制某些 issue，在 `src/pass/filter/issue_gate.zig` 中添加规则：

```zig
pub const GateVerdict = enum(u8) {
    // ... existing verdicts ...

    suppress_your_new_kind, // R-9: 你的抑制原因
};

pub fn checkIssue(srt: *const SemanticTree, value_ref: u64, kind: IssueKind) GateVerdict {
    switch (kind) {
        .some_issue_kind => {
            // 添加你的 gate 规则
            if (srt.hasKind(value_ref, .your_new_kind) != null) {
                return .suppress_your_new_kind;
            }
        },
        else => {},
    }
    return .allow;
}
```

#### 5. 编写测试

在 `tests/` 目录下创建测试文件：

```zig
// tests/your_detector_test.zig
const std = @import("std");
const testing = std.testing;

test "your detector detects pattern X" {
    // 设置 SRT
    // 调用 detect()
    // 验证返回正确的 SemanticKind 和置信度
}

test "your detector does not false positive on safe code" {
    // 测试安全代码不被误报
}
```

### 现有 Detector 参考

参考已实现的 8 个 detector：
- **R-0**: `param_attr.zig` — LLVM 属性检测
- **R-1**: `heap_provenance.zig` — 堆来源推断
- **R-2**: `interior_mut.zig` — 内部可变性
- **R-3**: `drop_glue.zig` / `raii_detector.zig` — RAII 检测
- **R-5**: `lang_detector.zig` — 语言检测
- **R-6**: `into_raw_transfer.zig` — 所有权转移
- **R-7**: `library_alloc_pairs.zig` — 库级分配器

## 如何扩展 SRT（语义解析树）

### 添加新的多语言支持

OmniScope v0.2.0 支持通过 SemanticKind 扩展来添加新语言的语义理解：

```zig
// 在 semantic_tree.zig 中添加语言特定的变体
pub const SemanticKind = enum(u16) {
    // ... existing ...

    // ── Swift (4 variants) ──────────────────────
    swift_arc_retain = 400,
    swift_arc_release = 401,
    swift_unsafe_pointer = 402,
    swift_bridge_objc = 403,

    // ── Kotlin (3 variants) ──────────────────────
    kotlin_native_ptr = 500,
   .kotlin_cinterop = 502,
    // ...
};
```

### 添加新的 Zone 分类规则

在 `src/semantics/zone_lang_*.zig` 中添加语言特定的 zone 规则：

```zig
// src/semantics/zone_lang_swift.zig
pub fn classifySwiftFunction(fn_name: []const u8) Zone {
    if (std.mem.startsWith(u8, fn_name, "@objc")) {
        return .ffi; // Objective-C interop
    }
    if (std.mem.indexOf(u8, fn_name, "unsafe") != null) {
        return .unsafe;
    }
    return .safe;
}
```

## 编码规范（更新版）

这些没得商量：

1. **声明你的 deps**：每个 pass 都必须声明 `pub const deps`。空 deps 意味着"我什么都不需要"——如果你确实需要什么，就写出来。
2. **使用 `isOnDangerPath`**：所有 Tier 2 的问题报告都必须经过这个门。没有例外。
3. **不要静默失败**：出了问题就记日志。我们有诊断系统，用起来。
4. **测试你的代码**：
   - 核心模块目标覆盖率 ≥85%
   - 新功能必须包含正面测试（检测到 bug）和负面测试（不误报）
   - PR 必须通过全量测试套件
5. **唯一真相源**：如果一个函数/分类已经存在于某个地方，就 import 它。别复制粘贴。我们在这上面吃过亏。
6. **遵循三层架构**：
   - Tier 1 只收集数据，不发 issue
   - Tier 2 发 issue 前必须过 `isOnDangerPath()`
   - Tier 3 通过 SRT + Gate 进行 FP 抑制
7. **文档化你的变更**：
   - 新的 IssueKind 必须更新 docs/zh/architecture.md 的表格
   - 新的 SemanticKind 必须更新 SRT 文档
   - 性能敏感的变更需要 benchmark 数据
8. **处理错误而非忽略**：
   - 使用 `try` / `catch` 而非 `_ = someCall()`
   - 记录所有 unexpected 错误路径
9. **保持向后兼容**：
   - 不删除或重命名已有的 IssueKind/SemanticKind
   - SARIF 输出格式必须稳定

## 项目结构（更新版）

```
src/
├── common/          # 共享工具（日志、字符串操作等）
├── ir/              # LLVM IR 包装类型（raw, safe, view, debug_info, location）
├── dataflow/        # 数据流分析框架（图、节点、边）
├── semantics/       # 语义知识库（核心！）
│   ├── semantic_tree.zig      # SRT 核心数据结构（27+ SemanticKind）
│   ├── patterns/              # 8个 IR Pattern Detectors (R-0~R-7)
│   │   ├── param_attr.zig     # R-0
│   │   ├── heap_provenance.zig # R-1
│   │   ├── interior_mut.zig   # R-2
│   │   ├── drop_glue.zig      # R-3
│   │   ├── lang_detector.zig  # R-5
│   │   ├── into_raw_transfer.zig # R-6
│   │   └── library_alloc_pairs.zig # R-7
│   ├── nomicon/               # Rust 特定语义（Unsafe Book 章节）
│   ├── surface_classifier/    # 语言特定 zone 规则
│   ├── memory_graph*.zig      # 内存图实现
│   ├── noise_filter*.zig      # 噪声过滤
│   └── zone_*.zig             # Zone 分类器
├── pass/
│   ├── pass.zig               # PassContext、issue 报告、zone 分类
│   ├── manager.zig            # Pass 执行引擎
│   ├── foundation/            # cfg, dfg
│   ├── analysis/              # 分析 pass（13个）
│   │   ├── tier1/             # call-graph, pointer-flow, etc.
│   │   ├── tier2/             # ffi-boundary, ptr-lifetime, etc.
│   │   ├── ffi/               # FFI 专用子模块（30+ 文件）
│   │   ├── rust_ffi/          # Rust FFI 审计器
│   │   ├── ptr_lifetime/      # 指针生命周期追踪（12 文件）
│   │   ├── resource/          # Issue verifier + scorer
│   │   └── noise/             # FP 减少模块
│   └── filter/                # ⚠️ 重要！FP 抑制层
│       ├── issue_gate.zig     # 统一 Issue Gate（10 Verdicts）
│       ├── fp_whitelist.zig   # 白名单
│       └── fp_precision_guard.zig
├── registry/        # 语义注册表（311 函数）、Hook 注册
├── pipeline/        # 流水线编排
├── diag/            # 诊断和日志（Issue 类型定义）
├── ffi/             # FFI 类型系统
├── lifetime/        # 生命周期跟踪
├── output/          # 输出格式化（JSON、文本、SARIF）
├── perf/            # 性能分析（profiler、memory pool）
├── fact/            # 事实存储
├── report/          # 报告生成
├── visual/          # 可视化辅助工具
└── whitelists/      # Rust 内部白名单
```

## 贡献指南（更新版）

### 贡献类型与流程

#### 1. Bug 修复

1. 在 GitHub Issues 中确认 bug（检查是否已存在）
2. 创建分支：`git checkout -b fix/bug-description`
3. 修复代码 + 添加回归测试
4. 运行完整测试：`zig build test`
5. 提交 PR，描述：
   - 修复的 bug 及其影响
   - 修复方法
   - 测试覆盖情况
   - 是否有文档需要更新

#### 2. 新功能（Feature）

1. 先提 Issue 讨论（避免做无用功）
2. 设计阶段：
   - 影响哪些模块？
   - 是否需要新的 IssueKind/SemanticKind？
   - 是否需要修改 Issue Gate？
   - 性能影响评估
3. 实现 + 测试（覆盖率 ≥85%）
4. 更新文档（architecture.md, passes.md 等）
5. 提交 PR

#### 3. 新 Detector（SRT 扩展）

1. 定义新的 SemanticKind（见上方"如何添加新 Detector"）
2. 实现 detector 逻辑
3. 添加 Gate 规则（如需抑制 issue）
4. 编写全面测试（正面 + 负面）
5. 提供 FP 抑制效果数据（估算即可）

#### 4. 多语言支持扩展

1. 评估当前支持状态（见 modules.md 的语言矩阵）
2. 实现 language adapter（`src/lang/`）
3. 添加 zone 分类规则
4. 添加 SemanticKind 变体（如需）
5. 编写专用测试套件
6. 更新文档中的语言支持状态

### PR 审查标准

我们 review 每个 PR。审查清单：

- [ ] **代码质量**：符合编码规范，无 warning
- [ ] **测试**：新增代码有对应测试，覆盖率达标
- [ ] **文档**：必要时更新了 docs/zh/ 下的文档
- [ ] **性能**：无明显性能退化（可运行 bench-perf 验证）
- [ ] **向后兼容**：不破坏已有 API 或输出格式
- [ ] **真实性**：不夸大功能，标注限制和实验性特性
- [ ] **Commit 信息**：清晰的 commit message（参考 conventional commits）

### 开发环境设置

```bash
# 1. 克隆仓库
git clone https://github.com/your-org/OmniScope.git
cd OmniScope

# 2. 安装依赖（macOS）
brew install llvm@22

# 3. 构建
zig build

# 4. 运行测试
zig build test

# 5. 运行示例
zig build run -- examples/cffi/simple_ffi.ll
```

### 社区行为准则

我们很友好。可能会毒舌，但我们是友好的。具体来说：

- ✅ 欢迎：bug 修复、文档改进、测试增强、合理的 feature request
- ⚠️ 需要讨论：大型架构变更、新语言支持、性能优化
- ❌ 不接受：破坏性更改、无测试的代码、夸大宣传、不尊重的工作方式

---

**文档维护说明**：
- 最后更新日期：2026-06-01
- 对应代码版本：v0.2.0 (VERSION 文件)
- 下次计划更新：v0.2.1 发布后或重大架构变更时
- 维护者：中文文档组（欢迎贡献改进）
