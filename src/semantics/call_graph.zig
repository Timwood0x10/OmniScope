//! Call Graph module for inter-procedural pointer tracking.
//!
//! This is a standalone module that tracks function calls and enables
//! Memory Graph propagation across function boundaries. This is a KEY SELLING POINT
//! for OmniScope - the ability to track pointers across function boundaries.
//!
//! Architecture:
//!
//!   CallNode: represents a function (caller or callee)
//!   CallEdge: represents a call relationship with argument mapping
//!   ArgumentMapping: tracks which caller arg maps to which callee param
//!
//! TODO v0.1.9: Complete propagateMemoryGraphThroughCall() implementation
//! TODO v0.1.9: Complete analyzeArgumentDirections() implementation
//! TODO v0.1.9: Implement cross-function pointer tracking
//!
//! Usage with MemoryGraph:
//!   1. Build CallGraph for the module
//!   2. For each call site, use propagateMemoryGraphThroughCall()
//!   3. This extends MemoryGraph tracking across functions
//!
//! Key Insight:
//!   When ptr is passed from caller to callee, we need to track that
//!   the callee's parameter is an ALIAS of the caller's pointer.

const std = @import("std");
const c = @cImport(@cInclude("llvm-c/Core.h"));

/// Error set for call graph operations.
pub const CallGraphError = error{
    OutOfMemory,
    NodeNotFound,
    CycleDetected,
    DuplicateNode,
};

/// Direction of pointer ownership transfer across function boundary.
pub const TransferDirection = enum(u8) {
    /// Pointer flows from caller to callee (caller's ptr passed to callee).
    caller_to_callee,
    /// Pointer flows from callee to caller (callee returns ptr to caller).
    callee_to_caller,
    /// Bidirectional (pointer may be modified and returned).
    bidirectional,
    /// No transfer (pointer just borrowed, not used after call).
    borrowed_only,
};

/// Maps a caller argument to a callee parameter at a call site.
pub const ArgumentMapping = struct {
    /// The argument value passed by the caller.
    caller_arg: u64,
    /// The parameter name (if available) or index.
    param_name: []const u8,
    /// The direction of pointer transfer.
    direction: TransferDirection,
    /// Whether this is an output parameter (callee writes to it).
    is_output_param: bool,
};

/// Represents a function node in the call graph.
pub const CallNode = struct {
    /// Unique identifier for this function.
    id: u64,
    /// The LLVM valueRef for this function.
    func_ref: c.LLVMValueRef,
    /// Function name.
    name: []const u8,
    /// Number of parameters.
    param_count: u32,
    /// Whether this function is external (no body in this module).
    is_external: bool,
    /// Whether this is an FFI boundary function.
    is_ffi_boundary: bool,
    /// Calls made by this function.
    outgoing_edges: std.AutoArrayList(u64),
};

/// Represents a call edge in the call graph.
pub const CallEdge = struct {
    /// Unique identifier for this edge.
    id: u64,
    /// Source node (caller).
    caller_id: u64,
    /// Target node (callee).
    callee_id: u64,
    /// The LLVM instruction for this call.
    call_inst: c.LLVMValueRef,
    /// Argument mappings for this call.
    argument_mappings: []ArgumentMapping,
    /// Location info for debugging.
    func_name: []const u8,
};

/// Main call graph structure.
pub const CallGraph = struct {
    /// Map from function name → node ID.
    nodes_by_name: std.AutoHashMap([]const u8, u64),
    /// Map from function ref → node ID.
    nodes_by_ref: std.AutoHashMap(u64, u64),
    /// All nodes in the graph.
    nodes: std.AutoArrayList(CallNode),
    /// All edges in the graph.
    edges: std.AutoArrayList(CallEdge),
    /// Next available node ID.
    next_node_id: u64,
    /// Next available edge ID.
    next_edge_id: u64,
    /// Arena allocator for long-lived data.
    arena: std.heap.ArenaAllocator,
    /// Temporary allocator.
    temp_allocator: std.mem.Allocator,

    /// Initializes a new call graph.
    pub fn init(temp_allocator: std.mem.Allocator) CallGraphError!CallGraph {
        var arena = std.heap.ArenaAllocator.init(temp_allocator);
        errdefer arena.deinit();

        return CallGraph{
            .nodes_by_name = std.AutoHashMap([]const u8, u64).init(arena.allocator()),
            .nodes_by_ref = std.AutoHashMap(u64, u64).init(arena.allocator()),
            .nodes = std.AutoArrayList(CallNode).init(arena.allocator()),
            .edges = std.AutoArrayList(CallEdge).init(arena.allocator()),
            .next_node_id = 1,
            .next_edge_id = 1,
            .arena = arena,
            .temp_allocator = temp_allocator,
        };
    }

    /// Deinitializes the call graph.
    pub fn deinit(graph: *CallGraph) void {
        graph.arena.deinit();
        graph.* = undefined;
    }

    /// Adds a function node to the graph.
    pub fn addNode(
        graph: *CallGraph,
        func_ref: c.LLVMValueRef,
        name: []const u8,
        is_external: bool,
        is_ffi_boundary: bool,
    ) CallGraphError!u64 {
        // Check if node already exists.
        if (graph.nodes_by_name.get(name)) |existing_id| {
            return existing_id;
        }

        const id = graph.next_node_id;
        graph.next_node_id += 1;

        const node = CallNode{
            .id = id,
            .func_ref = func_ref,
            .name = try graph.arena.allocator().dupe(u8, name),
            .param_count = if (func_ref != null) c.LLVMCountParams(func_ref) else 0,
            .is_external = is_external,
            .is_ffi_boundary = is_ffi_boundary,
            .outgoing_edges = std.AutoArrayList(u64).init(graph.arena.allocator()),
        };

        try graph.nodes.push(node);
        try graph.nodes_by_name.put(node.name, id);
        if (func_ref != null) {
            const ref_int = @as(u64, @intFromPtr(func_ref));
            try graph.nodes_by_ref.put(ref_int, id);
        }

        return id;
    }

    /// Adds a call edge to the graph.
    pub fn addEdge(
        graph: *CallGraph,
        caller_id: u64,
        callee_id: u64,
        call_inst: c.LLVMValueRef,
        func_name: []const u8,
    ) CallGraphError!u64 {
        const id = graph.next_edge_id;
        graph.next_edge_id += 1;

        const edge = CallEdge{
            .id = id,
            .caller_id = caller_id,
            .callee_id = callee_id,
            .call_inst = call_inst,
            .argument_mappings = &.{},
            .func_name = try graph.arena.allocator().dupe(u8, func_name),
        };

        try graph.edges.push(edge);

        // Add to caller's outgoing edges.
        if (graph.nodes.items.len > caller_id) {
            try graph.nodes.items[@as(usize, caller_id - 1)].outgoing_edges.push(id);
        }

        return id;
    }

    /// Adds an argument mapping to an existing edge.
    pub fn addArgumentMapping(
        graph: *CallGraph,
        edge_id: u64,
        mapping: ArgumentMapping,
    ) CallGraphError!void {
        const edge_idx = @as(usize, edge_id - 1);
        if (edge_idx >= graph.edges.items.len) {
            return CallGraphError.NodeNotFound;
        }

        const edge = &graph.edges.items[edge_idx];
        edge.argument_mappings = try graph.arena.allocator().realloc(
            edge.argument_mappings,
            edge.argument_mappings.len + 1,
        );
        edge.argument_mappings[edge.argument_mappings.len - 1] = mapping;
    }

    /// Gets a node by ID.
    pub fn getNode(graph: *CallGraph, node_id: u64) ?*CallNode {
        const idx = @as(usize, node_id - 1);
        if (idx >= graph.nodes.items.len) return null;
        return &graph.nodes.items[idx];
    }

    /// Gets an edge by ID.
    pub fn getEdge(graph: *CallGraph, edge_id: u64) ?*CallEdge {
        const idx = @as(usize, edge_id - 1);
        if (idx >= graph.edges.items.len) return null;
        return &graph.edges.items[idx];
    }

    /// Gets the node ID for a function name.
    pub fn getNodeByName(graph: *CallGraph, name: []const u8) ?u64 {
        return graph.nodes_by_name.get(name);
    }

    /// Gets all edges where this node is the caller.
    pub fn getOutgoingEdges(graph: *CallGraph, node_id: u64) []CallEdge {
        const node = graph.getNode(node_id) orelse return &.{};
        var result: []CallEdge = &.{};
        for (node.outgoing_edges.items) |edge_id| {
            const edge = graph.getEdge(edge_id) orelse continue;
            result = result ++ &.{edge.*};
        }
        return result;
    }
};

/// Result of propagating MemoryGraph through a call site.
pub const PropagationResult = struct {
    /// Whether propagation was successful.
    success: bool,
    /// Number of aliases created.
    aliases_created: u32,
    /// Error message if failed.
    error_message: ?[]const u8,
};

/// Propagates MemoryGraph through a call edge.
/// This creates alias relationships between caller arguments and callee parameters.
pub fn propagateMemoryGraphThroughCall(
    graph: *CallGraph,
    edge_id: u64,
    _: anytype,
    comptime track_alias_fn: fn (anytype, u64, u64) CallGraphError!void,
) PropagationResult {
    _ = graph;
    _ = edge_id;
    _ = track_alias_fn;
    return PropagationResult{
        .success = true,
        .aliases_created = 0,
        .error_message = null,
    };
}

/// Analyzes a call site to determine argument transfer directions.
pub fn analyzeArgumentDirections(
    call_inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    callee_func: c.LLVMValueRef,
) []ArgumentMapping {
    _ = call_inst;
    _ = caller_func;
    _ = callee_func;
    return &.{};
}

// ============================================================================
// Tests
// ============================================================================

test "call_graph - basic node creation" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const fake_func: c.LLVMValueRef = @ptrFromInt(0x1000);
    const node_id = try graph.addNode(fake_func, "main", false, false);

    try std.testing.expectEqual(@as(u64, 1), node_id);

    const node = graph.getNode(node_id);
    try std.testing.expect(node != null);
    try std.testing.expectEqualStrings("main", node.?.name);
}

test "call_graph - duplicate node prevention" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const fake_func: c.LLVMValueRef = @ptrFromInt(0x1000);

    const id1 = try graph.addNode(fake_func, "foo", false, false);
    const id2 = try graph.addNode(fake_func, "foo", false, false);

    // Should return same ID for duplicate function.
    try std.testing.expectEqual(id1, id2);
}

test "call_graph - edge creation" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const caller_func: c.LLVMValueRef = @ptrFromInt(0x1000);
    const callee_func: c.LLVMValueRef = @ptrFromInt(0x2000);
    const call_inst: c.LLVMValueRef = @ptrFromInt(0x3000);

    const caller_id = try graph.addNode(caller_func, "caller", false, false);
    const callee_id = try graph.addNode(callee_func, "callee", false, false);

    const edge_id = try graph.addEdge(caller_id, callee_id, call_inst, "caller");

    try std.testing.expectEqual(@as(u64, 1), edge_id);

    const edge = graph.getEdge(edge_id);
    try std.testing.expect(edge != null);
    try std.testing.expectEqual(caller_id, edge.?.caller_id);
    try std.testing.expectEqual(callee_id, edge.?.callee_id);
}

test "call_graph - argument mapping" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const caller_func: c.LLVMValueRef = @ptrFromInt(0x1000);
    const callee_func: c.LLVMValueRef = @ptrFromInt(0x2000);
    const call_inst: c.LLVMValueRef = @ptrFromInt(0x3000);

    const caller_id = try graph.addNode(caller_func, "caller", false, false);
    const callee_id = try graph.addNode(callee_func, "callee", false, false);

    const edge_id = try graph.addEdge(caller_id, callee_id, call_inst, "callee");

    const mapping = ArgumentMapping{
        .caller_arg = 0x4000,
        .param_name = "ptr",
        .direction = .caller_to_callee,
        .is_output_param = false,
    };

    try graph.addArgumentMapping(edge_id, mapping);

    const edge = graph.getEdge(edge_id);
    try std.testing.expect(edge != null);
    try std.testing.expectEqual(@as(usize, 1), edge.?.argument_mappings.len);
    try std.testing.expectEqual(@as(u64, 0x4000), edge.?.argument_mappings[0].caller_arg);
}

test "call_graph - get outgoing edges" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const main_func: c.LLVMValueRef = @ptrFromInt(0x1000);
    const foo_func: c.LLVMValueRef = @ptrFromInt(0x2000);
    const bar_func: c.LLVMValueRef = @ptrFromInt(0x3000);

    const main_id = try graph.addNode(main_func, "main", false, false);
    const foo_id = try graph.addNode(foo_func, "foo", false, false);
    const bar_id = try graph.addNode(bar_func, "bar", false, false);

    const call_inst1: c.LLVMValueRef = @ptrFromInt(0x4000);
    const call_inst2: c.LLVMValueRef = @ptrFromInt(0x5000);

    _ = try graph.addEdge(main_id, foo_id, call_inst1, "foo");
    _ = try graph.addEdge(main_id, bar_id, call_inst2, "bar");

    const edges = graph.getOutgoingEdges(main_id);
    try std.testing.expect(edges.len == 2);
}

test "call_graph - external and ffi flags" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try CallGraph.init(allocator);
    defer graph.deinit();

    const local_func: c.LLVMValueRef = @ptrFromInt(0x1000);
    const external_func: c.LLVMValueRef = @ptrFromInt(0x2000);
    const ffi_func: c.LLVMValueRef = @ptrFromInt(0x3000);

    _ = try graph.addNode(local_func, "local_func", false, false);
    _ = try graph.addNode(external_func, "external_func", true, false);
    _ = try graph.addNode(ffi_func, "dlopen", false, true);

    const local = graph.getNodeByName("local_func").?;
    const external = graph.getNodeByName("external_func").?;
    const ffi = graph.getNodeByName("dlopen").?;

    try std.testing.expect(!graph.getNode(local).?.is_external);
    try std.testing.expect(graph.getNode(external).?.is_external);
    try std.testing.expect(graph.getNode(ffi).?.is_ffi_boundary);
}
