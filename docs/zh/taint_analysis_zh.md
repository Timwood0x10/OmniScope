# Taint Analysis Pass (污点分析)

## 概述

Taint Analysis Pass 实现污点分析功能，用于跟踪数据从污染源到敏感汇的流动，以检测潜在的安全漏洞。该 Pass 识别已知的污点源（如 `read`、`getenv`）和汇（如 `system`、`printf`），并通过从 DFG 边构建的图传播污点。

## 模块位置

```text
src/pass/analysis/taint.zig
```

## TaintPass

污点分析 Pass 结构，负责执行污点分析。

### TaintPass 结构定义

```zig
/// Taint analysis pass
pub const TaintPass = struct {
    pub const name = "taint";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    allocator: std.mem.Allocator,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    // Taint graph
    taint_graph: TaintGraph,
    // Function ID
    func_id: u32,
    // Taint sources
    sources: std.ArrayList(u32),
    // Taint sinks
    sinks: std.ArrayList(u32),
};
```

### TaintPass 字段说明

- **name**: `const` - Pass 名称 "taint"
- **kind**: `PassKind` - Pass 类型（分析）
- **deps**: `[]const u8` - 依赖的 Pass（cfg, dfg, alias）
- **allocator**: `std.mem.Allocator` - 内存分配器
- **ctx**: `*PassContext` - Pass 上下文
- **diag**: `*DiagnosticWriter` - 诊断写入器
- **store**: `*FactStore` - 事实存储
- **query**: `QueryEngine` - 查询引擎
- **taint_graph**: `TaintGraph` - 污点图
- **func_id**: `u32` - 函数 ID
- **sources**: `std.ArrayList(u32)` - 污点源列表
- **sinks**: `std.ArrayList(u32)` - 污点汇列表

### TaintPass 方法

#### init()

初始化污点分析 Pass。

**参数:**

- `allocator`: 内存分配器
- `ctx`: Pass 上下文
- `diag`: 诊断写入器
- `store`: 事实存储
- `query`: 查询引擎

**返回值:** 新的 TaintPass 实例

```zig
var taint_pass = TaintPass.init(allocator, ctx, diag, store, query);
defer taint_pass.deinit();
```

#### deinit()

释放污点分析 Pass 资源。

```zig
taint_pass.deinit();
```

#### run()

运行污点分析。

**参数:**

- `func_id`: 要分析的函数 ID

**返回值:** 分析结果或错误

```zig
const result = try taint_pass.run(func_id);
```

## TaintGraph

污点图结构，用于管理和传播污点信息。

### TaintGraph 结构定义

```zig
/// Taint graph for tracking tainted values
pub const TaintGraph = struct {
    allocator: std.mem.Allocator,
    // Map from node ID to taint information
    tainted_nodes: std.AutoHashMap(u32, TaintInfo),
    // Edges for propagation
    propagation_edges: std.ArrayList(PropagationEdge),
};
```

### TaintGraph 字段说明

- **allocator**: `std.mem.Allocator` - 内存分配器
- **tainted_nodes**: `std.AutoHashMap(u32, TaintInfo)` - 污染节点映射
- **propagation_edges**: `std.ArrayList(PropagationEdge)` - 传播边列表

### TaintGraph 方法

#### init()

初始化污点图。

**参数:**

- `allocator`: 内存分配器

**返回值:** 新的 TaintGraph 实例

```zig
var taint_graph = TaintGraph.init(allocator);
defer taint_graph.deinit();
```

#### deinit()

释放污点图资源。

```zig
taint_graph.deinit();
```

#### markTainted()

将节点标记为污染。

**参数:**

- `node_id`: 节点 ID
- `source_id`: 污染源节点 ID

```zig
taint_graph.markTainted(node_id, source_id);
```

#### isTainted()

检查节点是否被污染。

**参数:**

- `node_id`: 节点 ID

**返回值:** 如果节点被污染返回 true

```zig
if (taint_graph.isTainted(node_id)) {
    // 节点被污染
}
```

#### propagate()

传播污点信息。

**返回值:** 传播结果或错误

```zig
try taint_graph.propagate();
```

## 已知污点源

TaintPass 识别以下已知的污点源函数：

- `read` - 从文件读取数据
- `getenv` - 获取环境变量
- `fgets` - 从流读取字符串
- `scanf` - 格式化输入
- `recv` - 接收网络数据
- `fread` - 从文件读取数据

### isKnownTaintSourceByName()

通过函数名检查是否是已知的污点源。

**参数:**

- `name`: 函数名

**返回值:** 如果是已知污点源返回 true

```zig
if (TaintPass.isKnownTaintSourceByName("getenv")) {
    // 这是污点源
}
```

## 已知污点汇

TaintPass 识别以下已知的污点汇函数：

- `system` - 执行系统命令
- `printf` - 格式化输出
- `exec` - 执行程序
- `popen` - 打开进程
- `sprintf` - 格式化字符串到缓冲区
- `strcpy` - 字符串复制

### isKnownTaintSinkByName()

通过函数名检查是否是已知的污点汇。

**参数:**

- `name`: 函数名

**返回值:** 如果是已知污点汇返回 true

```zig
if (TaintPass.isKnownTaintSinkByName("system")) {
    // 这是污点汇
}
```

## 使用示例

### 基本污点分析

```zig
const std = @import("std");
const taint = @import("taint");

pub fn analyzeTaint() !void {
    var taint_pass = TaintPass.init(allocator, ctx, diag, store, query);
    defer taint_pass.deinit();

    // 分析函数
    const func_id = 1;
    const result = try taint_pass.run(func_id);

    // 检查检测到的污点流
    for (result.taint_flows) |flow| {
        std.debug.print("Taint flow: {} -> {}\n", .{ flow.source, flow.sink });
    }
}
```

### 检查污点源和汇

```zig
pub fn checkSourcesAndSinks() void {
    // 检查污点源
    if (TaintPass.isKnownTaintSourceByName("getenv")) {
        std.debug.print("getenv is a taint source\n");
    }

    // 检查污点汇
    if (TaintPass.isKnownTaintSinkByName("system")) {
        std.debug.print("system is a taint sink\n");
    }
}
```

## 污点传播规则

污点通过以下方式传播：

1. **直接赋值**: 污染值赋值给新变量会传播污点
2. **函数参数**: 污染值作为参数传递给函数会传播污点
3. **函数返回**: 函数返回污染值会传播污点
4. **内存操作**: 通过存储和加载操作传播污点
5. **指针操作**: 通过指针解引用传播污点

## 检测的问题

TaintPass 可以检测以下安全问题：

- **命令注入**: 污染数据传递给 `system()` 或类似函数
- **格式字符串漏洞**: 污染数据用作格式字符串
- **缓冲区溢出**: 污染数据用于不安全的字符串操作
- **路径遍历**: 污染数据用于文件路径操作
- **SQL 注入**: 污染数据用于 SQL 查询（如果检测到）

## 注意事项

1. **依赖关系**: TaintPass 依赖于 cfg、dfg 和 alias Pass，必须在这些 Pass 之后运行。
2. **误报**: 污点分析可能会产生误报，特别是在复杂的控制流中。
3. **性能**: 污点分析可能需要大量计算资源，特别是在大型代码库上。
4. **上下文敏感度**: 当前实现是流敏感的，但可能不是完全上下文敏感的。
5. **可扩展性**: 可以通过添加更多的污点源和汇来扩展检测能力。
