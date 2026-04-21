# Dataflow 模块

## 概述

Dataflow 模块定义了数据流图结构，用于表示和分析程序的数据流关系。该模块是所有分析 Pass 的核心数据结构，在 Fact Store 之上提供高级抽象。

## 模块结构

```text
src/dataflow/
├── graph.zig  # 数据流图
├── node.zig   # 数据流节点
└── edge.zig   # 数据流边
```

## DataFlowGraph

统一的数据流图结构，表示分析程序中的所有数据流关系。

### DataFlowGraph 结构定义

```zig
/// Data Flow Graph
///
/// The unified data structure that represents all data flow relationships
/// in the analyzed program. This graph is built on top of the Fact Store
/// and provides high-level abstractions for analysis passes.
pub const DataFlowGraph = struct {
    /// Memory allocator
    allocator: Allocator,
    /// Reference to the underlying fact store
    fact_store: *FactStore,
    /// Reference to the query engine
    query_engine: *QueryEngine,

    /// Map of node ID to node data
    nodes: std.AutoHashMap(u32, DataNode),
    /// List of data flow edges
    edges: std.ArrayList(DataEdge),
    /// List of FFI boundaries
    ffi_boundaries: std.ArrayList(FFIBoundary),
    /// List of detected issues
    issues: std.ArrayList(Issue),

    /// Optional FFI matcher for cross-language function matching
    /// Only available when analyzing multiple IR files
    ffi_matcher: ?*FFIMatcher,

    /// Quick lookup indices for efficient queries
    outgoing_edges: std.AutoHashMap(u32, []const u32),
    incoming_edges: std.AutoHashMap(u32, []const u32),
    tainted_nodes: std.ArrayList(u32),
};
```

### DataFlowGraph 字段

- **allocator**: `Allocator` - 内存分配器
- **fact_store**: `*FactStore` - 底层事实存储引用
- **query_engine**: `*QueryEngine` - 查询引擎引用
- **nodes**: `std.AutoHashMap(u32, DataNode)` - 节点 ID 到节点数据的映射
- **edges**: `std.ArrayList(DataEdge)` - 数据流边列表
- **ffi_boundaries**: `std.ArrayList(FFIBoundary)` - FFI 边界列表
- **issues**: `std.ArrayList(Issue)` - 检测到的问题列表
- **ffi_matcher**: `?*FFIMatcher` - 可选的 FFI 匹配器，用于跨语言函数匹配
- **outgoing_edges**: `std.AutoHashMap(u32, []const u32)` - 出边快速查找索引
- **incoming_edges**: `std.AutoHashMap(u32, []const u32)` - 入边快速查找索引
- **tainted_nodes**: `std.ArrayList(u32)` - 污染节点列表

### DataFlowGraph 方法

#### init()

初始化数据流图。

**参数:**

- `allocator`: 内存分配器
- `fact_store`: 事实存储引用
- `query_engine`: 查询引擎引用

**返回值:** 新的 DataFlowGraph 实例

```zig
var dfg = DataFlowGraph.init(allocator, &fact_store, &query_engine);
defer dfg.deinit();
```

#### deinit()

释放数据流图资源。

```zig
dfg.deinit();
```

#### addNode()

向图中添加节点。

**参数:**

- `node`: 要添加的节点

**返回值:** 如果节点已存在则返回错误

```zig
const location = Location.init("test_func");
const node = DataNode.init(1, .pointer, location);
try dfg.addNode(node);
```

#### getNode()

通过 ID 获取节点。

**参数:**

- `id`: 节点 ID

**返回值:** 节点指针，如果未找到则返回 null

```zig
if (dfg.getNode(1)) |node| {
    // 使用节点
}
```

#### addEdge()

向图中添加边。

**参数:**

- `edge`: 要添加的边

**返回值:** 如果边引用不存在的节点则返回错误

```zig
const edge = DataEdge.init(1, 2, .direct);
try dfg.addEdge(edge);
```

#### getOutgoingEdges()

获取节点的出边。

**参数:**

- `node_id`: 节点 ID

**返回值:** 出边索引切片

```zig
const outgoing = dfg.getOutgoingEdges(1);
```

#### getIncomingEdges()

获取节点的入边。

**参数:**

- `node_id`: 节点 ID

**返回值:** 入边索引切片

```zig
const incoming = dfg.getIncomingEdges(2);
```

#### addFFIBoundary()

向图中添加 FFI 边界。

**参数:**

- `boundary`: FFI 边界

```zig
const boundary = FFIBoundary.init(1, .rust_to_c, .rust, .c, "func", location);
try dfg.addFFIBoundary(boundary);
```

#### getFFIBoundaries()

获取所有 FFI 边界。

**返回值:** FFI 边界切片

```zig
const boundaries = dfg.getFFIBoundaries();
```

#### addIssue()

向图中添加问题。

**参数:**

- `issue`: 要添加的问题

```zig
const issue = Issue.init(.ffi_unsafe_call, "message", location, .high, 0.9);
try dfg.addIssue(issue);
```

#### markTainted()

将节点标记为污染。

**参数:**

- `node_id`: 要标记为污染的节点 ID
- `source_id`: 可选的源节点 ID

```zig
try dfg.markTainted(1, null); // 标记为污染源
try dfg.markTainted(2, 1);   // 标记为被节点1污染
```

#### isTainted()

检查节点是否被污染。

**参数:**

- `node_id`: 要检查的节点 ID

**返回值:** 如果节点被污染返回 true

```zig
if (dfg.isTainted(1)) {
    // 节点被污染
}
```

#### getStats()

获取图统计信息。

**返回值:** GraphStats 结构

```zig
const stats = dfg.getStats();
std.debug.print("Nodes: {}, Edges: {}\n", .{stats.node_count, stats.edge_count});
```

## DataNode

数据流节点，表示分析程序中的值或变量。

### DataNode 结构定义

```zig
/// Data flow node
///
/// Represents a value or variable in the analyzed program.
/// Nodes are connected by edges to form the data flow graph.
pub const DataNode = struct {
    /// Unique identifier for this node
    id: u32,
    /// Type of the value represented by this node
    value_type: ValueType,
    /// Whether this node is tainted (influenced by dangerous input)
    is_tainted: bool,
    /// Location where this value was created
    location: Location,
    /// ID of the node that tainted this node (null if this is a source)
    taint_source: ?u32,
    /// Additional metadata (optional)
    metadata: ?NodeMetadata,
};
```

### DataNode 字段

- **id**: `u32` - 节点的唯一标识符
- **value_type**: `ValueType` - 节点表示的值的类型
- **is_tainted**: `bool` - 节点是否被污染（受危险输入影响）
- **location**: `Location` - 值创建的位置
- **taint_source**: `?u32` - 污染此节点的节点 ID（如果是源则为 null）
- **metadata**: `?NodeMetadata` - 额外的元数据（可选）

### DataNode 方法

#### init()

创建新的数据节点。

**参数:**

- `id`: 唯一标识符
- `value_type`: 值的类型
- `location`: 值创建的位置

**返回值:** 新的 DataNode 实例

```zig
const location = Location.init("test_func");
const node = DataNode.init(1, .pointer, location);
```

#### initWithMetadata()

创建带元数据的数据节点。

**参数:**

- `id`: 唯一标识符
- `value_type`: 值的类型
- `location`: 值创建的位置
- `metadata`: 额外的元数据

**返回值:** 新的 DataNode 实例

```zig
var metadata = DataNode.NodeMetadata.init();
metadata.size = 64;
metadata.name = "test_var";
const node = DataNode.initWithMetadata(1, .pointer, location, metadata);
```

#### setTainted()

将节点标记为污染。

**参数:**

- `source_id`: 污染此节点的节点 ID

```zig
node.setTainted(null); // 标记为污染源
node.setTainted(2);   // 标记为被节点2污染
```

#### clearTaint()

清除节点的污染标记。

```zig
node.clearTaint();
```

#### isTaintSource()

检查节点是否是污染源。

**返回值:** 如果节点被污染且没有源（是源）则返回 true

```zig
if (node.isTaintSource()) {
    // 这是污染源
}
```

#### isPointer()

检查节点是否是指针。

**返回值:** 如果节点表示指针值则返回 true

```zig
if (node.isPointer()) {
    // 处理指针
}
```

## ValueType

值类型枚举，定义数据流图中可以表示的值类型。

### ValueType 枚举定义

```zig
/// Value type enumeration
///
/// Defines the types of values that can be represented in the data flow graph.
pub const ValueType = enum {
    /// Pointer type
    pointer,
    /// Integer type
    integer,
    /// Struct type
    struct_,
    /// Array type
    array,
    /// Function type
    function,
    /// Unknown type
    unknown,
};
```

### ValueType 类型

- **pointer**: 指针类型
- **integer**: 整数类型
- **struct_**: 结构体类型
- **array**: 数组类型
- **function**: 函数类型
- **unknown**: 未知类型

## DataEdge

数据流边，表示图中两个节点之间的数据流关系。

### DataEdge 结构定义

```zig
/// Data flow edge
///
/// Represents a data flow relationship between two nodes in the graph.
/// Edges are directed, showing the direction of data flow.
pub const DataEdge = struct {
    /// Source node ID (where data flows from)
    from: u32,
    /// Target node ID (where data flows to)
    to: u32,
    /// Type of the edge
    edge_type: EdgeType,
    /// Function name if edge is through a function call (optional)
    via_function: ?[]const u8,
    /// Additional metadata (optional)
    metadata: ?EdgeMetadata,
};
```

### DataEdge 字段

- **from**: `u32` - 源节点 ID（数据流从哪里开始）
- **to**: `u32` - 目标节点 ID（数据流到哪里）
- **edge_type**: `EdgeType` - 边的类型
- **via_function**: `?[]const u8` - 如果边通过函数调用，则为函数名（可选）
- **metadata**: `?EdgeMetadata` - 额外的元数据（可选）

### DataEdge 方法

#### init()

创建新的数据边。

**参数:**

- `from`: 源节点 ID
- `to`: 目标节点 ID
- `edge_type`: 边的类型

**返回值:** 新的 DataEdge 实例

```zig
const edge = DataEdge.init(1, 2, .direct);
```

#### initWithFunction()

创建带函数名的数据边。

**参数:**

- `from`: 源节点 ID
- `to`: 目标节点 ID
- `edge_type`: 边的类型
- `via_function`: 如果边通过函数调用，则为函数名

**返回值:** 新的 DataEdge 实例

```zig
const edge = DataEdge.initWithFunction(1, 2, .call_arg, "test_func");
```

#### isCallEdge()

检查边是否是函数调用边。

**返回值:** 如果边通过函数调用则返回 true

```zig
if (edge.isCallEdge()) {
    // 处理函数调用边
}
```

#### isFFIBoundary()

检查边是否是 FFI 边界边。

**返回值:** 如果边跨越 FFI 边界则返回 true

```zig
if (edge.isFFIBoundary()) {
    // 处理 FFI 边界
}
```

## EdgeType

边类型枚举，定义节点之间可以存在的数据流边类型。

### EdgeType 枚举定义

```zig
/// Edge type enumeration
///
/// Defines the types of data flow edges that can exist between nodes.
pub const EdgeType = enum {
    /// Direct assignment or flow
    direct,
    /// Flow through function call argument
    call_arg,
    /// Flow through function return value
    call_ret,
    /// Store operation (memory write)
    store,
    /// Load operation (memory read)
    load,
    /// Flow across FFI boundary
    ffi_boundary,
    /// Unknown edge type
    unknown,
};
```

### EdgeType 类型

- **direct**: 直接赋值或流
- **call_arg**: 通过函数调用参数的流
- **call_ret**: 通过函数返回值的流
- **store**: 存储操作（内存写入）
- **load**: 加载操作（内存读取）
- **ffi_boundary**: 跨越 FFI 边界的流
- **unknown**: 未知边类型

## 使用示例

### 构建数据流图

```zig
const std = @import("std");
const dataflow = @import("dataflow");

pub fn buildGraph() !void {
    var fact_store = FactStore.init(allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    var dfg = DataFlowGraph.init(allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    // 添加节点
    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);
    const node3 = DataNode.init(3, .pointer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);
    try dfg.addNode(node3);

    // 添加边
    try dfg.addEdge(DataEdge.init(1, 2, .direct));
    try dfg.addEdge(DataEdge.init(2, 3, .call_arg));

    // 标记污染
    try dfg.markTainted(1, null);
    try dfg.markTainted(3, 1);

    // 查询图
    const stats = dfg.getStats();
    std.debug.print("Nodes: {}, Edges: {}, Tainted: {}\n", .{
        stats.node_count,
        stats.edge_count,
        stats.tainted_node_count,
    });
}
```

### 添加 FFI 边界

```zig
const boundary = FFIBoundary.init(
    1,
    .rust_to_c,
    .rust,
    .c,
    "external_func",
    location,
);
try dfg.addFFIBoundary(boundary);

const boundaries = dfg.getFFIBoundaries();
for (boundaries) |b| {
    std.debug.print("FFI boundary: {} -> {}\n", .{ b.caller_lang, b.callee_lang });
}
```

### 添加问题

```zig
const issue = Issue.init(
    .ffi_unsafe_call,
    "Unsafe FFI call detected",
    location,
    .high,
    0.9,
);
try dfg.addIssue(issue);

const issues = dfg.getIssues();
for (issues) |i| {
    std.debug.print("Issue: {} (severity: {})\n", .{ i.message, i.severity });
}
```

## 注意事项

1. **内存管理**: DataFlowGraph 拥有其内部数据的所有权，必须在适当的时候调用 `deinit()` 释放资源。
2. **节点 ID 唯一性**: 节点 ID 必须唯一，尝试添加重复节点会返回错误。
3. **边验证**: 添加边时会验证源节点和目标节点是否存在，如果不存则返回错误。
4. **FFI 匹配器**: FFI 匹配器是可选的，只在分析多个 IR 文件时可用。
5. **性能优化**: 图使用快速查找索引（outgoing_edges, incoming_edges）来优化查询性能。
