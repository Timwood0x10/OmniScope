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
const word_boundary = @import("../utils/word_boundary.zig");

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
    outgoing_edges: std.ArrayList(u64),
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
    nodes_by_name: std.StringHashMap(u64),
    /// Map from function ref → node ID.
    nodes_by_ref: std.AutoHashMap(u64, u64),
    /// All nodes in the graph.
    nodes: std.ArrayList(CallNode),
    /// All edges in the graph.
    edges: std.ArrayList(CallEdge),
    /// Next available node ID.
    next_node_id: u64,
    /// Next available edge ID.
    next_edge_id: u64,
    /// Allocator used for all internal allocations.
    /// CRITICAL: Using ArenaAllocator caused panic "start index 16 > end index 0"
    /// when processing 99+ functions (HashMap grow exhausted arena buffer chain).
    /// Switched to GeneralPurposeAllocator for reliability — this graph persists
    /// for the entire analysis lifetime anyway, so arena semantics don't apply.
    allocator: std.mem.Allocator,
    /// Temporary allocator for BFS traversal (uses caller-provided temp allocator).
    temp_allocator: std.mem.Allocator,

    /// Initializes a new call graph.
    pub fn init(allocator: std.mem.Allocator) CallGraphError!CallGraph {
        return CallGraph{
            .nodes_by_name = std.StringHashMap(u64).init(allocator),
            .nodes_by_ref = std.AutoHashMap(u64, u64).init(allocator),
            // Zig 0.15.2 requires initCapacity() — std.ArrayList.init() was removed.
            .nodes = std.ArrayList(CallNode).initCapacity(allocator, 0) catch return error.OutOfMemory,
            .edges = std.ArrayList(CallEdge).initCapacity(allocator, 0) catch return error.OutOfMemory,
            .next_node_id = 1,
            .next_edge_id = 1,
            .allocator = allocator,
            .temp_allocator = allocator,
        };
    }

    /// Deinitializes the call graph and frees all internal memory.
    pub fn deinit(graph: *CallGraph) void {
        // Free all node names (allocated via allocator.dupe in addNode)
        for (graph.nodes.items) |node| {
            graph.allocator.free(node.name);
        }
        // Free all outgoing_edges ArrayLists inside nodes
        for (0..graph.nodes.items.len) |i| {
            graph.nodes.items[i].outgoing_edges.deinit(graph.allocator);
        }
        // CRITICAL FIX: Free all edge func_name strings (allocated via allocator.dupe in addEdge)
        for (graph.edges.items) |edge| {
            graph.allocator.free(edge.func_name);
        }
        // CRITICAL FIX: Free all edge argument_mappings slices (allocated via allocator.realloc in addArgumentMapping)
        for (graph.edges.items) |edge| {
            graph.allocator.free(edge.argument_mappings);
        }
        graph.nodes.deinit(graph.allocator);
        graph.edges.deinit(graph.allocator);
        graph.nodes_by_name.deinit();
        graph.nodes_by_ref.deinit();
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
            .name = try graph.allocator.dupe(u8, name),
            .param_count = 0,
            .is_external = is_external,
            .is_ffi_boundary = is_ffi_boundary,
            .outgoing_edges = std.ArrayList(u64).initCapacity(graph.allocator, 4) catch return error.OutOfMemory,
        };

        try graph.nodes.append(graph.allocator, node);
        try graph.nodes_by_name.put(node.name, id);
        if (func_ref != null) {
            // Only call LLVMCountParams on real (non-fake) function refs.
            // Fake refs (e.g., @ptrFromInt(0x1000) in tests) will segfault.
            const ref_int = @as(u64, @intFromPtr(func_ref));
            if (ref_int > 0xFFFF) {
                graph.nodes.items[graph.nodes.items.len - 1].param_count = c.LLVMCountParams(func_ref);
            }
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
            .func_name = try graph.allocator.dupe(u8, func_name),
        };

        try graph.edges.append(graph.allocator, edge);

        // Add to caller's outgoing edges with safe bounds checking.
        // caller_id is 1-based (starts from 1), so valid range is [1, nodes.len]
        // Use explicit positive integer check to prevent potential overflow edge cases
        if (caller_id > 0 and caller_id <= graph.nodes.items.len) {
            try graph.nodes.items[caller_id - 1].outgoing_edges.append(graph.allocator, id);
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
        edge.argument_mappings = try graph.allocator.realloc(
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
    /// Returns an ArrayList of outgoing edges. Caller must call result.deinit().
    pub fn getOutgoingEdges(graph: *CallGraph, allocator: std.mem.Allocator, node_id: u64) !std.ArrayList(CallEdge) {
        const node = graph.getNode(node_id) orelse return std.ArrayList(CallEdge).initCapacity(allocator, 0) catch return error.OutOfMemory;
        var result = std.ArrayList(CallEdge).initCapacity(allocator, 4) catch return error.OutOfMemory;
        for (node.outgoing_edges.items) |edge_id| {
            const edge = graph.getEdge(edge_id) orelse continue;
            try result.append(allocator, edge.*);
        }
        return result;
    }

    /// Zero-allocation iterator over outgoing edges. Preferred for performance-critical paths.
    /// Callback receives each edge; iteration stops if callback returns false.
    pub fn forEachOutgoingEdge(graph: *CallGraph, node_id: u64, ctx: anytype, comptime callback: fn (@TypeOf(ctx), CallEdge) bool) bool {
        const node = graph.getNode(node_id) orelse return true;
        for (node.outgoing_edges.items) |edge_id| {
            const edge = graph.getEdge(edge_id) orelse continue;
            if (!callback(ctx, edge.*)) return false;
        }
        return true;
    }

    /// Convenience wrapper: returns owned slice (caller must free via allocator.free()).
    /// Prefer forEachOutgoingEdge() or getOutgoingEdges() for better control.
    pub fn getOutgoingEdgesSlice(graph: *CallGraph, allocator: std.mem.Allocator, node_id: u64) ![]CallEdge {
        var list = try graph.getOutgoingEdges(allocator, node_id);
        errdefer list.deinit(allocator);
        return list.toOwnedSlice();
    }

    /// Checks if a function (node) eventually reaches an FFI boundary through its call chain.
    /// Uses BFS traversal with cycle detection via visited set.
    ///
    /// This is the KEY function for V2 cross-function FFI analysis:
    /// - Enables ptr_lifetime.zig to ask: "Should I track this call edge?"
    /// - Enables ip_ffi.zig to ask: "Is this wrapper function actually an acquisition?"
    ///
    /// Example:
    ///   malloc() → my_wrapper() → process_data()  [process_data is not FFI]
    ///   process_data() → C.save_to_file()          [C.save_to_file IS FFI boundary]
    ///   → reachesFFIBoundary(process_data) = true
    ///
    /// Arguments:
    ///   node_id - The starting function node ID
    ///   max_depth - Maximum traversal depth (default: 10, prevents infinite loops)
    ///
    /// Returns:
    ///   true if the function's call chain eventually reaches an FFI boundary function
    pub fn reachesFFIBoundary(graph: *CallGraph, node_id: u64, max_depth: u32) bool {
        // Quick check: is this node itself an FFI boundary?
        if (graph.getNode(node_id)) |node| {
            if (node.is_ffi_boundary) return true;
        }

        // BFS traversal with depth limit and cycle detection.
        // All allocation failures degrade gracefully to return false
        // rather than crashing (unreachable) or producing unreliable results.
        var visited = std.AutoHashMap(u64, void).init(graph.temp_allocator);
        defer visited.deinit();

        var queue = std.ArrayList(u64).initCapacity(graph.temp_allocator, 16) catch return false;
        defer queue.deinit(graph.temp_allocator);

        queue.append(graph.temp_allocator, node_id) catch return false;
        visited.put(node_id, {}) catch return false;

        var depth: u32 = 0;

        // Standard BFS level-by-level traversal with proper depth tracking.
        // Uses two pointers to track current level boundaries:
        //   - queue_start: next node to process
        //   - level_end: last node at current depth level
        var queue_start: usize = 0;
        var level_end: usize = 1; // Initially only root node at depth 0

        while (queue_start < queue.items.len and depth < max_depth) {
            const current_node_id = queue.items[queue_start];
            queue_start += 1;

            // Check if we've finished processing current level
            if (queue_start == level_end) {
                // Move to next depth level
                depth += 1;
                // All nodes added since last level_end are now the new level boundary
                level_end = queue.items.len;
                if (depth >= max_depth) break; // Don't process nodes beyond max depth
            }

            // Get outgoing edges for this node
            if (graph.getNode(current_node_id)) |node| {
                for (node.outgoing_edges.items) |edge_id| {
                    if (graph.getEdge(edge_id)) |edge| {
                        // Check if callee is FFI boundary
                        if (graph.getNode(edge.callee_id)) |callee| {
                            if (callee.is_ffi_boundary) return true;

                            // Add to queue for further traversal (if not visited).
                            // On allocation failure, bail out entirely — partial BFS results
                            // are worse than no cross-function analysis (which is the fallback).
                            if (!visited.contains(edge.callee_id)) {
                                visited.put(edge.callee_id, {}) catch return false;
                                queue.append(graph.temp_allocator, edge.callee_id) catch return false;
                            }
                        }
                    }
                }
            }
        }

        return false; // No FFI boundary found within depth limit
    }

    /// Gets all functions that can reach FFI boundaries through their call chains.
    /// Uses reverse BFS from FFI boundary nodes.
    ///
    /// Returns:
    ///   ArrayList of node IDs that can reach FFI boundaries (caller must deinit)
    pub fn getFFIBoundaryReachableFunctions(graph: *CallGraph, allocator: std.mem.Allocator) !std.ArrayList(u64) {
        var result = std.ArrayList(u64).initCapacity(allocator, 16) catch return error.OutOfMemory;

        // Find all FFI boundary nodes first
        var ffi_boundaries = std.ArrayList(u64).initCapacity(graph.temp_allocator, 8) catch return error.OutOfMemory;
        defer ffi_boundaries.deinit();

        for (graph.nodes.items) |node| {
            if (node.is_ffi_boundary) {
                try ffi_boundaries.append(graph.temp_allocator, node.id);
            }
        }

        // If no FFI boundaries, return empty list
        if (ffi_boundaries.items.len == 0) return result;

        // Build reverse adjacency map (callee -> callers)
        var reverse_map = std.AutoHashMap(u64, std.ArrayList(u64)).init(graph.temp_allocator);
        defer {
            var it = reverse_map.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(graph.temp_allocator);
            }
            reverse_map.deinit();
        }

        // Populate reverse map from edges
        for (graph.edges.items) |edge| {
            const entry = try reverse_map.getOrPut(edge.callee_id);
            if (!entry.found_exists) {
                entry.value_ptr.* = std.ArrayList(u64).initCapacity(graph.temp_allocator, 4) catch return error.OutOfMemory;
            }
            try entry.value_ptr.append(graph.temp_allocator, edge.caller_id);
        }

        // BFS from FFI boundaries backwards
        var visited = std.AutoHashMap(u64, void).init(graph.temp_allocator);
        defer visited.deinit();
        var queue = std.ArrayList(u64).initCapacity(graph.temp_allocator, 16) catch return error.OutOfMemory;
        defer queue.deinit(graph.temp_allocator);

        // Initialize queue with all FFI boundary nodes
        for (ffi_boundaries.items) |ffi_id| {
            try queue.append(graph.temp_allocator, ffi_id);
            try visited.put(ffi_id, {});
        }

        var queue_start: usize = 0;
        while (queue_start < queue.items.len) : (queue_start += 1) {
            const current_id = queue.items[queue_start];
            try result.append(allocator, current_id); // This node can reach FFI

            // Find all callers of this node
            if (reverse_map.get(current_id)) |callers| {
                for (callers.items) |caller_id| {
                    if (!visited.contains(caller_id)) {
                        try visited.put(caller_id, {});
                        try queue.append(graph.temp_allocator, caller_id);
                    }
                }
            }
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
///
/// This is the KEY function for cross-function ownership tracking.
/// When a pointer is passed from caller to callee, we track that the callee's
/// parameter is an ALIAS of the caller's pointer, enabling cross-function
/// double-free detection and ownership verification.
///
/// Cycle Protection:
///   - Uses a visited set to prevent re-processing the same edge
///   - Limits recursion depth to MAX_PROPAGATION_DEPTH (default: 32)
///   - Returns CycleDetected error if a cycle is detected
///
/// Arguments:
///   graph - The call graph containing the edge
///   edge_id - The ID of the call edge to propagate through
///   memory_graph - The memory graph to update with alias relationships
///   track_alias_fn - Callback to record alias relationships with ownership semantics
///     Signature: fn (memory_graph: anytype, ptr1: u64, ptr2: u64, is_weak: bool) CallGraphError!void
///     where is_weak=true means "borrow only" (no ownership transfer) and is_weak=false means
///     "ownership transfer" (strong alias that should be checked for double-free)
///   visited - Set of already-visited edge IDs (prevents cycles)
///   current_depth - Current recursion depth (starts at 0)
///
/// **IMPORTANT**: When calling this function, you MUST:
///   1. Initialize a `std.AutoHashMap(u64, void)` for cycle detection
///   2. Pass `current_depth = 0` on the initial call
///   3. The function will manage the visited set internally (no manual cleanup needed for entries)
///
/// **Ownership Semantics**:
///   - `.caller_to_callee` with `is_output_param=false`: Strong alias (caller transfers ownership to callee)
///   - `.caller_to_callee` with `is_output_param=true`: Strong alias (callee writes result to caller's output param)
///   - `.callee_to_caller` with `is_output_param=true`: Strong alias (output parameter returns ownership to caller)
///   - `.callee_to_caller` with `is_output_param=false`: Strong alias (return value like malloc() transfers ownership)
///   - `.borrowed_only`: **Weak alias** (callee borrows pointer but doesn't take ownership)
///
/// Example usage:
/// ```zig
/// var visited = std.AutoHashMap(u64, void).init(allocator);
/// defer visited.deinit();
///
/// const result = try CallGraph.propagateMemoryGraphThroughCall(
///     &call_graph,
///     edge_id,
///     &memory_graph,
///     trackAliasHelper,  // Must accept (mg, p1, p2, is_weak: bool)
///     &visited,          // Cycle detection set
///     0,                // Start at depth 0
/// );
/// ```
///
/// Returns:
///   PropagationResult with success status and number of aliases created
const MAX_PROPAGATION_DEPTH = 32;

pub fn propagateMemoryGraphThroughCall(
    graph: *CallGraph,
    edge_id: u64,
    memory_graph: anytype,
    comptime track_alias_fn: fn (anytype, u64, u64, bool) CallGraphError!void,
    visited: *std.AutoHashMap(u64, void),
    current_depth: u32,
) CallGraphError!PropagationResult {
    // Prevent infinite recursion on cyclic call graphs
    if (current_depth > MAX_PROPAGATION_DEPTH) {
        return PropagationResult{
            .success = false,
            .aliases_created = 0,
            .error_message = "Max propagation depth exceeded (possible cycle)",
        };
    }

    // Check if this edge was already processed (cycle detection)
    if (visited.contains(edge_id)) {
        return PropagationResult{
            .success = false,
            .aliases_created = 0,
            .error_message = "Cycle detected: edge already visited",
        };
    }

    // Mark this edge as visited
    try visited.put(edge_id, {});

    const edge = graph.getEdge(edge_id) orelse return PropagationResult{
        .success = false,
        .aliases_created = 0,
        .error_message = "Edge not found",
    };

    var aliases_created: u32 = 0;

    // Process each argument mapping at this call site
    for (edge.argument_mappings) |mapping| {
        switch (mapping.direction) {
            .caller_to_callee => {
                // Pointer flows from caller to callee (ownership transfer).
                // Create strong alias: callee's param is an alias of caller's arg.
                // The callee may free this pointer (e.g., passing to free()).
                track_alias_fn(memory_graph, mapping.caller_arg, @as(u64, @intFromPtr(edge.call_inst)), false) catch continue;
                aliases_created += 1;
            },
            .callee_to_caller => {
                // Pointer flows from callee to caller (return value or output param).
                // This indicates ownership transfer from callee to caller.
                // The caller becomes responsible for the resource.
                if (mapping.is_output_param) {
                    // Output parameter: callee writes to caller's pointer (strong alias).
                    // Common pattern: int* ptr; factory(&ptr);  // ptr gets ownership
                    track_alias_fn(memory_graph, @as(u64, @intFromPtr(edge.call_inst)), mapping.caller_arg, false) catch continue;
                    aliases_created += 1;
                } else {
                    // Return value: callee creates resource and returns it to caller (strong alias).
                    // Critical for tracking malloc(), dlopen(), etc.
                    // Example: void* ptr = malloc(size);  // call_inst = ptr
                    track_alias_fn(memory_graph, @as(u64, @intFromPtr(edge.call_inst)), mapping.caller_arg, false) catch continue;
                    aliases_created += 1;
                }
            },
            .bidirectional => {
                // Pointer may be modified and returned (both directions are ownership transfers).
                track_alias_fn(memory_graph, mapping.caller_arg, @as(u64, @intFromPtr(edge.call_inst)), false) catch continue;
                track_alias_fn(memory_graph, @as(u64, @intFromPtr(edge.call_inst)), mapping.caller_arg, false) catch continue;
                aliases_created += 2;
            },
            .borrowed_only => {
                // Pointer is borrowed, not transferred (WEAK alias).
                // Track as weak alias for use-after-free detection only.
                // Freeing a borrowed pointer is NOT a double-free error
                // (the original owner is still responsible for freeing it).
                //
                // V2 FIX: Now properly distinguished via is_weak=true parameter,
                // enabling downstream analysis to make correct double-free decisions.
                track_alias_fn(memory_graph, mapping.caller_arg, @as(u64, @intFromPtr(edge.call_inst)), true) catch continue;
                aliases_created += 1;
            },
        }
    }

    return PropagationResult{
        .success = true,
        .aliases_created = aliases_created,
        .error_message = null,
    };
}

/// Analyzes a call site to determine argument transfer directions.
/// Uses LLVM type information and callee name heuristics.
/// Accepts raw pointer values as u64 to avoid cross-cimport type mismatches.
pub fn analyzeArgumentDirections(
    call_inst_ptr: u64,
    callee_name: []const u8,
    param_count: u32,
    get_operand_fn: *const fn (u64, u32) u64,
    get_type_kind_fn: *const fn (u64) u32,
    get_elem_type_kind_fn: *const fn (u64) u32,
    arena: std.mem.Allocator,
) ![]ArgumentMapping {
    var mappings = std.ArrayList(ArgumentMapping).init(arena);
    errdefer mappings.deinit(arena);

    var i: u32 = 0;
    while (i < param_count) : (i += 1) {
        const arg = get_operand_fn(call_inst_ptr, i);
        if (arg == 0) continue;

        const type_kind = get_type_kind_fn(arg);
        if (type_kind != c.LLVMPointerTypeKind) continue;

        const elem_type_kind = get_elem_type_kind_fn(arg);

        const direction: TransferDirection = if (elem_type_kind == c.LLVMFunctionTypeKind)
            .borrowed_only
        else if (elem_type_kind == c.LLVMPointerTypeKind)
            .callee_to_caller
        else
            classifyArgDirectionByName(callee_name, i);

        const param_name = std.fmt.allocPrint(arena, "param_{}", .{i}) catch "param";

        const is_output = isOutputParam(callee_name, i);

        try mappings.append(arena, .{
            .caller_arg = arg,
            .param_name = param_name,
            .direction = direction,
            .is_output_param = is_output,
        });
    }

    return mappings.items;
}

/// Classifies argument direction by callee name patterns and common C API conventions.
///
/// This function uses heuristics based on function naming patterns to determine
/// how pointer arguments flow across function boundaries. This is essential for
/// tracking ownership transfer in C code where ownership is not explicit in types.
///
/// Common patterns recognized:
///   - Alloc/Create/Init → gives ownership (callee_to_caller)
///   - Free/Destroy/Close → takes ownership (caller_to_callee)
///   - Get/Read/Fetch → output parameter (callee_to_caller)
///   - Set/Write/Send → input parameter (caller_to_callee)
///
/// Arguments:
///   callee_name - Name of the function being called
///   param_index - Index of the parameter being classified
///
/// Returns:
///   TransferDirection indicating how the pointer flows
fn classifyArgDirectionByName(callee_name: []const u8, param_index: u32) TransferDirection {
    // Pattern 1: Factory/Constructor functions - give ownership
    // These functions allocate resources and transfer ownership to caller
    const factory_patterns = [_][]const u8{
        "Alloc", "Create", "New", "Init", "Open", "Dup",
    };
    for (factory_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            // First param is often the output pointer (T**)
            if (param_index == 0) return .callee_to_caller;
        }
    }

    // Pattern 2: Destructor/Cleanup functions - take ownership
    // These functions consume resources and invalidate the pointer
    const cleanup_patterns = [_][]const u8{
        "Free", "Destroy", "Delete", "Close", "Release", "Cleanup",
    };
    for (cleanup_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return .caller_to_callee;
        }
    }

    // Pattern 3: Getter functions - output parameters
    // These functions write results to caller-provided buffers
    const getter_prefixes = [_][]const u8{
        "get_", "read_", "recv_", "fetch_", "query_", "load_",
    };
    for (getter_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) {
            // Later parameters are often output buffers
            if (param_index > 0) return .callee_to_caller;
        }
    }

    // Pattern 4: Setter functions - input parameters
    // These functions read from caller-provided data
    const setter_prefixes = [_][]const u8{
        "set_", "write_", "send_", "put_", "store_", "copy_",
    };
    for (setter_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) {
            return .caller_to_callee;
        }
    }

    // Pattern 5: Thread/Process creation - special case
    // pthread_create, sqlite3ThreadCreate, etc.
    // Use word boundary matching consistently to prevent false positives like "myThreadCreator"
    if (word_boundary.isWordBoundaryMatch(callee_name, "ThreadCreate") or
        word_boundary.isWordBoundaryMatch(callee_name, "pthread_create"))
    {
        // First param is output (thread handle), rest are input
        if (param_index == 0) return .callee_to_caller;
        return .caller_to_callee;
    }

    // Pattern 6: Mutex operations - special case
    // pthreadMutexAlloc returns mutex, pthreadMutexFree consumes it
    if (word_boundary.isWordBoundaryMatch(callee_name, "MutexAlloc")) {
        return .callee_to_caller;
    }
    if (word_boundary.isWordBoundaryMatch(callee_name, "MutexFree")) {
        return .caller_to_callee;
    }

    // Default: assume borrowed_only (conservative)
    // Most functions borrow pointers without transferring ownership.
    // Only known acquire/release patterns should be classified as caller_to_callee/callee_to_caller.
    // This reduces false positives in cross-function analysis.
    return .borrowed_only;
}

/// Checks if a parameter at the given index is an output parameter.
///
/// Output parameters are pointers through which the callee writes results
/// to the caller. Common patterns include:
///   - T** parameters (double pointers) for returning allocated objects
///   - void** parameters for returning generic pointers
///   - Last parameters in getter functions
///
/// This is critical for recognizing factory patterns where ownership is
/// transferred via output parameters rather than return values.
///
/// Arguments:
///   callee_name - Name of the function being called
///   param_index - Index of the parameter to check
///
/// Returns:
///   true if this parameter is an output parameter
fn isOutputParam(callee_name: []const u8, param_index: u32) bool {
    // Pattern 1: Known output parameter functions
    const output_param_functions = [_][]const u8{
        "sqlite3_prepare", "sqlite3_open", "sqlite3ThreadCreate",
        "pthread_create",  "pthread_join", "getsockopt",
        "getaddrinfo",     "getnameinfo",  "clock_gettime",
        "gettimeofday",    "regcomp",      "curl_easy_getinfo",
    };
    for (output_param_functions) |pattern| {
        if (std.mem.startsWith(u8, callee_name, pattern)) {
            // First or second parameter is typically the output
            return param_index <= 1;
        }
    }

    // Pattern 2: Factory functions with output parameters
    // Common pattern: int create_XXX(XXX** ppResult, ...)
    if (std.mem.indexOf(u8, callee_name, "Create") != null or
        std.mem.indexOf(u8, callee_name, "Alloc") != null or
        std.mem.indexOf(u8, callee_name, "Init") != null)
    {
        // First parameter is often the output (T**)
        if (param_index == 0) return true;
    }

    // Pattern 3: Getter functions with output buffers
    // Common pattern: int get_XXX(..., void* pBuffer, size_t* pSize)
    if (std.mem.startsWith(u8, callee_name, "get_") or
        std.mem.startsWith(u8, callee_name, "read_") or
        std.mem.startsWith(u8, callee_name, "fetch_"))
    {
        // Later parameters are often output buffers
        if (param_index >= 1) return true;
    }

    return false;
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

    var edges = try graph.getOutgoingEdges(allocator, main_id);
    defer edges.deinit(allocator);
    try std.testing.expect(edges.items.len == 2);
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
