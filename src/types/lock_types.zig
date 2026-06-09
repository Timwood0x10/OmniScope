//! Lock Analysis — Type Definitions & Graph Structures
//!
//! Extracted from pass/analysis/lock.zig to reduce file size.
//! Contains LockOperation data type and LockGraph algorithm.

const std = @import("std");
const log = std.log.scoped(.lock_types);

/// Lock operation information
/// Represents a single lock acquire or release operation.
pub const LockOperation = struct {
    lock_id: u32,
    inst_id: u32,
    is_acquire: bool,
};

/// Lock acquisition graph for deadlock detection.
/// Uses DFS-based cycle detection to find potential deadlocks.
pub const LockGraph = struct {
    allocator: std.mem.Allocator,
    adjacency: std.ArrayList(Edge),

    pub const Edge = struct {
        from: u32,
        to: u32,
    };

    /// Create a new lock graph
    pub fn init(allocator: std.mem.Allocator) LockGraph {
        return .{
            .allocator = allocator,
            .adjacency = std.ArrayList(Edge).initCapacity(allocator, 16) catch @panic("OOM"),
        };
    }

    /// Deinitialize the lock graph
    pub fn deinit(self: *LockGraph) void {
        self.adjacency.deinit(self.allocator);
    }

    /// Add an edge to the graph
    pub fn addEdge(self: *LockGraph, from: u32, to: u32) !void {
        try self.adjacency.append(self.allocator, .{ .from = from, .to = to });
    }

    /// Get neighbors of a node
    pub fn getNeighbors(self: *const LockGraph, node: u32, allocator: std.mem.Allocator) ![]u32 {
        var neighbors = std.ArrayList(u32).initCapacity(allocator, 8) catch @panic("OOM");
        for (self.adjacency.items) |edge| {
            if (edge.from == node) {
                try neighbors.append(allocator, edge.to);
            }
        }
        return neighbors.toOwnedSlice(allocator);
    }

    /// Check if the graph has a cycle using DFS
    pub fn hasCycle(self: *LockGraph) !bool {
        var visited = std.AutoHashMap(u32, bool).init(self.allocator);
        defer visited.deinit();

        var recursion_stack = std.AutoHashMap(u32, bool).init(self.allocator);
        defer recursion_stack.deinit();

        // Collect all unique nodes
        var nodes = std.ArrayList(u32).initCapacity(self.allocator, 16) catch @panic("OOM");
        defer nodes.deinit(self.allocator);

        for (self.adjacency.items) |edge| {
            if (!visited.contains(edge.from)) {
                try nodes.append(self.allocator, edge.from);
                try visited.put(edge.from, true);
            }
            if (!visited.contains(edge.to)) {
                try nodes.append(self.allocator, edge.to);
                try visited.put(edge.to, true);
            }
        }

        // Reset visited for DFS
        visited.clearRetainingCapacity();

        // DFS for each unvisited node
        for (nodes.items) |node| {
            if (!visited.contains(node)) {
                if (try self.hasCycleDFS(node, &visited, &recursion_stack)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// DFS helper for cycle detection
    fn hasCycleDFS(
        self: *LockGraph,
        node: u32,
        visited: *std.AutoHashMap(u32, bool),
        recursion_stack: *std.AutoHashMap(u32, bool),
    ) !bool {
        try visited.put(node, true);
        try recursion_stack.put(node, true);

        const neighbors = try self.getNeighbors(node, self.allocator);
        defer self.allocator.free(neighbors);

        for (neighbors) |neighbor| {
            if (!visited.contains(neighbor)) {
                if (try self.hasCycleDFS(neighbor, visited, recursion_stack)) {
                    return true;
                }
            } else if (recursion_stack.contains(neighbor)) {
                // Back edge found - cycle exists
                return true;
            }
        }

        _ = recursion_stack.remove(node);
        return false;
    }
};

// ========== Tests for LockGraph ==========
test "LockGraph - init and deinit" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectEqual(@as(usize, 0), graph.adjacency.items.len);
}

test "LockGraph - add edge" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge(1, 2);
    try std.testing.expectEqual(@as(usize, 1), graph.adjacency.items.len);
    try std.testing.expectEqual(@as(u32, 1), graph.adjacency.items[0].from);
    try std.testing.expectEqual(@as(u32, 2), graph.adjacency.items[0].to);
}

test "LockGraph - get neighbors" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 3);

    const neighbors = try graph.getNeighbors(1, std.testing.allocator);
    defer std.testing.allocator.free(neighbors);

    try std.testing.expectEqual(@as(usize, 2), neighbors.len);
    try std.testing.expect(neighbors[0] == 2 or neighbors[0] == 3);
    try std.testing.expect(neighbors[1] == 2 or neighbors[1] == 3);
}

test "LockGraph - has cycle simple" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges: 1 -> 2 -> 3 -> 1 (cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
    try graph.addEdge(3, 1);

    try std.testing.expect(try graph.hasCycle());
}

test "LockGraph - has no cycle" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges: 1 -> 2 -> 3 (no cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    try std.testing.expect(!try graph.hasCycle());
}

test "LockGraph - has cycle complex" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges with multiple components
    // Component 1: 1 -> 2 -> 1 (cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 1);

    // Component 2: 3 -> 4 -> 5 (no cycle)
    try graph.addEdge(3, 4);
    try graph.addEdge(4, 5);

    try std.testing.expect(try graph.hasCycle());
}
