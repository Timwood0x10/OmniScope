# Dataflow Module

## Overview

The Dataflow module defines data flow graph structures for representing and analyzing data flow relationships in programs. This module serves as the central data structure for all analysis passes, providing high-level abstractions over the Fact Store.

## Module Structure

```text
src/dataflow/
├── graph.zig  # Data flow graph
├── node.zig   # Data flow node
└── edge.zig   # Data flow edge
```

## DataFlowGraph

The unified data flow graph structure representing all data flow relationships in the analyzed program.

### DataFlowGraph Structure Definition

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

### DataFlowGraph Fields

- **allocator**: `Allocator` - Memory allocator
- **fact_store**: `*FactStore` - Reference to underlying fact store
- **query_engine**: `*QueryEngine` - Reference to query engine
- **nodes**: `std.AutoHashMap(u32, DataNode)` - Map of node ID to node data
- **edges**: `std.ArrayList(DataEdge)` - List of data flow edges
- **ffi_boundaries**: `std.ArrayList(FFIBoundary)` - List of FFI boundaries
- **issues**: `std.ArrayList(Issue)` - List of detected issues
- **ffi_matcher**: `?*FFIMatcher` - Optional FFI matcher for cross-language function matching
- **outgoing_edges**: `std.AutoHashMap(u32, []const u32)` - Outgoing edge quick lookup index
- **incoming_edges**: `std.AutoHashMap(u32, []const u32)` - Incoming edge quick lookup index
- **tainted_nodes**: `std.ArrayList(u32)` - List of tainted nodes

### DataFlowGraph Methods

#### init()

Initialize the data flow graph.

**Parameters:**

- `allocator`: Memory allocator
- `fact_store`: Reference to fact store
- `query_engine`: Reference to query engine

**Returns:** New DataFlowGraph instance

```zig
var dfg = DataFlowGraph.init(allocator, &fact_store, &query_engine);
defer dfg.deinit();
```

#### deinit()

Release data flow graph resources.

```zig
dfg.deinit();
```

#### addNode()

Add a node to the graph.

**Parameters:**

- `node`: The node to add

**Returns:** Error if node already exists

```zig
const location = Location.init("test_func");
const node = DataNode.init(1, .pointer, location);
try dfg.addNode(node);
```

#### getNode()

Get a node by ID.

**Parameters:**

- `id`: Node ID

**Returns:** Pointer to the node, or null if not found

```zig
if (dfg.getNode(1)) |node| {
    // Use the node
}
```

#### addEdge()

Add an edge to the graph.

**Parameters:**

- `edge`: The edge to add

**Returns:** Error if edge references non-existent nodes

```zig
const edge = DataEdge.init(1, 2, .direct);
try dfg.addEdge(edge);
```

#### getOutgoingEdges()

Get outgoing edges for a node.

**Parameters:**

- `node_id`: Node ID

**Returns:** Slice of outgoing edge indices

```zig
const outgoing = dfg.getOutgoingEdges(1);
```

#### getIncomingEdges()

Get incoming edges for a node.

**Parameters:**

- `node_id`: Node ID

**Returns:** Slice of incoming edge indices

```zig
const incoming = dfg.getIncomingEdges(2);
```

#### addFFIBoundary()

Add an FFI boundary to the graph.

**Parameters:**

- `boundary`: The FFI boundary to add

```zig
const boundary = FFIBoundary.init(1, .rust_to_c, .rust, .c, "func", location);
try dfg.addFFIBoundary(boundary);
```

#### getFFIBoundaries()

Get all FFI boundaries.

**Returns:** Slice of FFI boundaries

```zig
const boundaries = dfg.getFFIBoundaries();
```

#### addIssue()

Add an issue to the graph.

**Parameters:**

- `issue`: The issue to add

```zig
const issue = Issue.init(.ffi_unsafe_call, "message", location, .high, 0.9);
try dfg.addIssue(issue);
```

#### markTainted()

Mark a node as tainted.

**Parameters:**

- `node_id`: Node ID to mark as tainted
- `source_id`: Optional source node ID

```zig
try dfg.markTainted(1, null); // Mark as taint source
try dfg.markTainted(2, 1);   // Mark as tainted by node 1
```

#### isTainted()

Check if a node is tainted.

**Parameters:**

- `node_id`: Node ID to check

**Returns:** `true` if node is tainted

```zig
if (dfg.isTainted(1)) {
    // Node is tainted
}
```

#### getStats()

Get graph statistics.

**Returns:** GraphStats structure

```zig
const stats = dfg.getStats();
std.debug.print("Nodes: {}, Edges: {}\n", .{stats.node_count, stats.edge_count});
```

## DataNode

Data flow node representing a value or variable in the analyzed program.

### DataNode Structure Definition

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

### DataNode Fields

- **id**: `u32` - Unique identifier for the node
- **value_type**: `ValueType` - Type of the value represented by this node
- **is_tainted**: `bool` - Whether this node is tainted (influenced by dangerous input)
- **location**: `Location` - Location where this value was created
- **taint_source**: `?u32` - ID of the node that tainted this node (null if this is a source)
- **metadata**: `?NodeMetadata` - Additional metadata (optional)

### DataNode Methods

#### init()

Create a new data node.

**Parameters:**

- `id`: Unique identifier
- `value_type`: Type of the value
- `location`: Location where value was created

**Returns:** New DataNode instance

```zig
const location = Location.init("test_func");
const node = DataNode.init(1, .pointer, location);
```

#### initWithMetadata()

Create a data node with metadata.

**Parameters:**

- `id`: Unique identifier
- `value_type`: Type of the value
- `location`: Location where value was created
- `metadata`: Additional metadata

**Returns:** New DataNode instance

```zig
var metadata = DataNode.NodeMetadata.init();
metadata.size = 64;
metadata.name = "test_var";
const node = DataNode.initWithMetadata(1, .pointer, location, metadata);
```

#### setTainted()

Mark this node as tainted.

**Parameters:**

- `source_id`: ID of the node that tainted this node

```zig
node.setTainted(null); // Mark as taint source
node.setTainted(2);   // Mark as tainted by node 2
```

#### clearTaint()

Clear taint from this node.

```zig
node.clearTaint();
```

#### isTaintSource()

Check if this node is a taint source.

**Returns:** `true` if this node is tainted and has no source (is a source)

```zig
if (node.isTaintSource()) {
    // This is a taint source
}
```

#### isPointer()

Check if this node is a pointer.

**Returns:** `true` if this node represents a pointer value

```zig
if (node.isPointer()) {
    // Handle pointer
}
```

## ValueType

Value type enumeration defining the types of values that can be represented in the data flow graph.

### ValueType Enumeration Definition

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

### ValueType Types

- **pointer**: Pointer type
- **integer**: Integer type
- **struct_**: Struct type
- **array**: Array type
- **function**: Function type
- **unknown**: Unknown type

## DataEdge

Data flow edge representing a data flow relationship between two nodes in the graph.

### DataEdge Structure Definition

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

### DataEdge Fields

- **from**: `u32` - Source node ID (where data flows from)
- **to**: `u32` - Target node ID (where data flows to)
- **edge_type**: `EdgeType` - Type of the edge
- **via_function**: `?[]const u8` - Function name if edge is through a function call (optional)
- **metadata**: `?EdgeMetadata` - Additional metadata (optional)

### DataEdge Methods

#### init()

Create a new data edge.

**Parameters:**

- `from`: Source node ID
- `to`: Target node ID
- `edge_type`: Type of the edge

**Returns:** New DataEdge instance

```zig
const edge = DataEdge.init(1, 2, .direct);
```

#### initWithFunction()

Create a data edge with function name.

**Parameters:**

- `from`: Source node ID
- `to`: Target node ID
- `edge_type`: Type of the edge
- `via_function`: Function name if edge is through a function call

**Returns:** New DataEdge instance

```zig
const edge = DataEdge.initWithFunction(1, 2, .call_arg, "test_func");
```

#### isCallEdge()

Check if this edge is a function call edge.

**Returns:** `true` if edge is through a function call

```zig
if (edge.isCallEdge()) {
    // Handle function call edge
}
```

#### isFFIBoundary()

Check if this edge is an FFI boundary edge.

**Returns:** `true` if edge crosses FFI boundary

```zig
if (edge.isFFIBoundary()) {
    // Handle FFI boundary
}
```

## EdgeType

Edge type enumeration defining the types of data flow edges that can exist between nodes.

### EdgeType Enumeration Definition

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

### EdgeType Types

- **direct**: Direct assignment or flow
- **call_arg**: Flow through function call argument
- **call_ret**: Flow through function return value
- **store**: Store operation (memory write)
- **load**: Load operation (memory read)
- **ffi_boundary**: Flow across FFI boundary
- **unknown**: Unknown edge type

## Usage Examples

### Building a Data Flow Graph

```zig
const std = @import("std");
const dataflow = @import("dataflow");

pub fn buildGraph() !void {
    var fact_store = FactStore.init(allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    var dfg = DataFlowGraph.init(allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    // Add nodes
    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);
    const node3 = DataNode.init(3, .pointer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);
    try dfg.addNode(node3);

    // Add edges
    try dfg.addEdge(DataEdge.init(1, 2, .direct));
    try dfg.addEdge(DataEdge.init(2, 3, .call_arg));

    // Mark taint
    try dfg.markTainted(1, null);
    try dfg.markTainted(3, 1);

    // Query the graph
    const stats = dfg.getStats();
    std.debug.print("Nodes: {}, Edges: {}, Tainted: {}\n", .{
        stats.node_count,
        stats.edge_count,
        stats.tainted_node_count,
    });
}
```

### Adding FFI Boundaries

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

### Adding Issues

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

## Notes

1. **Memory Management**: DataFlowGraph owns its internal data. You must call `deinit()` to release resources at the appropriate time.
2. **Unique Node IDs**: Node IDs must be unique. Attempting to add a duplicate node returns an error.
3. **Edge Validation**: When adding edges, the graph validates that both source and target nodes exist. Returns an error if they don't.
4. **FFI Matcher**: The FFI matcher is optional and only available when analyzing multiple IR files.
5. **Performance Optimization**: The graph uses quick lookup indices (outgoing_edges, incoming_edges) to optimize query performance.
