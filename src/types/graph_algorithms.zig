//! Graph Algorithms — Consolidated Single Source of Truth
//!
//! Consolidates duplicate graph traversal algorithms found across the codebase.
//! Extracted from ownership_types.zig and cpp_fp_types.zig.
//!
//! Pure logic — no dependency on PassContext.

const std = @import("std");

// ============================================================================
// Type Aliases
// ============================================================================

/// Flow graph type: maps source node to set of target nodes.
pub const FlowGraph = std.AutoHashMap(u32, std.AutoHashMap(u32, void));

/// Allocator-aware flow graph type for cpp_fp_types-style usage.
pub const FlowGraphAlloc = std.AutoHashMap(u32, std.AutoHashMap(u32, void));

// ============================================================================
// Reachability
// ============================================================================

/// Check if a value can reach another value through the flow graph (DFS).
/// Uses visited set for cycle detection on cyclic graphs.
pub fn canReach(
    flow_graph: *const FlowGraph,
    from: u32,
    to: u32,
    visited: *std.AutoHashMap(u32, void),
) bool {
    if (from == to) return true;
    if (visited.contains(from)) return false;
    visited.put(from, {}) catch return false;

    const edges = flow_graph.get(from) orelse return false;
    var iter = edges.iterator();
    while (iter.next()) |entry| {
        if (canReach(flow_graph, entry.key_ptr.*, to, visited)) return true;
    }
    return false;
}

// ============================================================================
// Free Path Detection
// ============================================================================

/// BFS traversal from from_ptr to find any reachable free site.
/// Returns true if from_ptr can reach any entry in free_map via flow_graph.
pub fn findFreePath(
    from_ptr: u32,
    free_map: *std.AutoHashMap(u32, void),
    flow_graph: *const FlowGraph,
    visited: *std.AutoHashMap(u32, void),
) bool {
    if (free_map.contains(from_ptr)) return true;
    if (visited.contains(from_ptr)) return false;
    visited.put(from_ptr, {}) catch return false;

    if (flow_graph.get(from_ptr)) |outgoing| {
        for (outgoing.keys()) |target| {
            if (findFreePath(target, free_map, flow_graph, visited)) return true;
        }
    }
    return false;
}

/// DFS with cycle detection to check if 'from' can reach any free site.
/// Used by use-after-free detection after a pointer is freed.
pub fn canReachFree(
    from: u32,
    flow: std.AutoHashMap(u32, void),
    free_map: *std.AutoHashMap(u32, void),
    flow_graph: *const FlowGraph,
    visited: *std.AutoHashMap(u32, void),
) bool {
    if (flow.count() > 0) {
        var alias_iter = flow.iterator();
        while (alias_iter.next()) |entry| {
            if (free_map.contains(entry.key_ptr.*)) return true;
        }
    }
    if (free_map.contains(from)) return true;
    if (visited.contains(from)) return false;
    visited.put(from, {}) catch return false;

    if (flow_graph.get(from)) |outgoing| {
        for (outgoing.keys()) |target| {
            if (canReachFree(target, .{}, free_map, flow_graph, visited)) return true;
        }
    }
    return false;
}

// ============================================================================
// Flow Edge Management
// ============================================================================

/// Add a forward edge (from → to) to flow_graph and reverse edge to reverse_flow.
/// Skips self-edges. Both maps must use the same allocator.
pub fn addFlowEdge(
    allocator: std.mem.Allocator,
    from: u32,
    to: u32,
    flow_graph: *FlowGraph,
    reverse_flow: ?*FlowGraph,
) !void {
    if (from == to) return;

    const entry = try flow_graph.getOrPut(from);
    if (!entry.found_existing) {
        entry.value_ptr.* = std.AutoHashMap(u32, void).init(allocator);
    }
    try entry.value_ptr.put(to, {});

    if (reverse_flow) |rf| {
        const rf_entry = try rf.getOrPut(to);
        if (!rf_entry.found_existing) {
            rf_entry.value_ptr.* = std.AutoHashMap(u32, void).init(allocator);
        }
        try rf_entry.value_ptr.put(from, {});
    }
}

// ============================================================================
// Hashing
// ============================================================================

/// FNV-1a hash with wrapping multiplication.
/// Wrapping is intentional: hash values are not ordered, overflow is expected.
pub fn hashValues(values: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (values) |val| {
        hash ^= val;
        hash = hash *% 0x100000001b3;
    }
    return hash;
}

// ============================================================================
// Tests
// ============================================================================

test "graph_algorithms - canReach" {
    const allocator = std.testing.allocator;
    var flow = FlowGraph.init(allocator);
    defer {
        var iter = flow.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        flow.deinit();
    }

    try addFlowEdge(allocator, 1, 2, &flow, null);
    try addFlowEdge(allocator, 2, 3, &flow, null);

    var visited = std.AutoHashMap(u32, void).init(allocator);
    defer visited.deinit();

    try std.testing.expect(canReach(&flow, 1, 3, &visited));
    visited.clearRetainingCapacity();
    try std.testing.expect(!canReach(&flow, 3, 1, &visited));
}

test "graph_algorithms - hashValues" {
    const h1 = hashValues(&[_]u64{ 1, 2, 3 });
    const h2 = hashValues(&[_]u64{ 1, 2, 3 });
    try std.testing.expectEqual(h1, h2);

    const h3 = hashValues(&[_]u64{ 3, 2, 1 });
    try std.testing.expect(h1 != h3);
}
