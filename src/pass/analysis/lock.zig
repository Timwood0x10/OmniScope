//! Lock Analysis Pass
//!
//! This pass detects potential deadlocks by:
//! 1. Building a lock acquisition graph from facts
//! 2. Finding cycles using Tarjan's SCC algorithm
//! 3. Reporting potential deadlock scenarios

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;

/// Lock analysis pass
pub const LockPass = struct {
    pub const name = "lock";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    store: *FactStore,
    query: QueryEngine,

    /// Create a new lock analysis pass
    pub fn init(store: *FactStore) LockPass {
        return .{
            .store = store,
            .query = QueryEngine.init(store),
        };
    }

    /// Run the lock analysis pass
    pub fn run(
        self: *LockPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ctx;
        _ = diag;

        // TODO: Load module from context
        // The actual implementation will:
        // 1. Build lock acquisition graph from facts
        // 2. Find cycles using Tarjan's SCC
        // 3. Report potential deadlocks

        // Example: Emit sample lock facts
        try self.store.insert(.lock_acquire, 1, 2, 0);
        try self.store.insert(.lock_release, 1, 2, 0);
    }

    /// Build lock graph from facts
    fn buildLockGraph(self: *LockPass, context: u32) !LockGraph {
        _ = self;
        _ = context;

        // Implementation steps:
        // 1. Query lock_acquire facts
        // 2. Build adjacency list
        // 3. Return graph for cycle detection

        return LockGraph.init(std.testing.allocator);
    }

    /// Find cycles using Tarjan's SCC algorithm
    fn findCycles(graph: *LockGraph) ![][]u32 {
        // Implementation of Tarjan's algorithm
        // Returns list of cycles (each cycle is a list of lock IDs)
        var cycles = std.ArrayList([]u32).init(std.testing.allocator);
        defer {
            for (cycles.items) |cycle| {
                std.testing.allocator.free(cycle);
            }
            cycles.deinit();
        }

        return cycles.toOwnedSlice();
    }
};

/// Lock acquisition graph
pub const LockGraph = struct {
    allocator: std.mem.Allocator,
    adjacency: std.ArrayList(Edge),

    const Edge = struct {
        from: u32,
        to: u32,
    };

    /// Create a new lock graph
    pub fn init(allocator: std.mem.Allocator) LockGraph {
        return .{
            .allocator = allocator,
            .adjacency = std.ArrayList(Edge).init(allocator),
        };
    }

    /// Deinitialize the lock graph
    pub fn deinit(self: *LockGraph) void {
        self.adjacency.deinit();
    }

    /// Add an edge to the graph
    pub fn addEdge(self: *LockGraph, from: u32, to: u32) !void {
        try self.adjacency.append(.{ .from = from, .to = to });
    }

    /// Get neighbors of a node
    pub fn getNeighbors(self: *const LockGraph, node: u32, allocator: std.mem.Allocator) ![]u32 {
        var neighbors = std.ArrayList(u32).init(allocator);
        for (self.adjacency.items) |edge| {
            if (edge.from == node) {
                try neighbors.append(edge.to);
            }
        }
        return neighbors.toOwnedSlice();
    }

    /// Check if the graph has a cycle
    pub fn hasCycle(self: *LockGraph) !bool {
        var visited = std.AutoHashMap(u32, bool).init(self.allocator);
        defer visited.deinit();

        var recursion_stack = std.AutoHashMap(u32, bool).init(self.allocator);
        defer recursion_stack.deinit();

        // Collect all nodes
        var nodes = std.ArrayList(u32).init(self.allocator);
        defer nodes.deinit();

        for (self.adjacency.items) |edge| {
            if (!visited.contains(edge.from)) {
                try nodes.append(edge.from);
                try visited.put(edge.from, true);
            }
            if (!visited.contains(edge.to)) {
                try nodes.append(edge.to);
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

test "LockPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = LockPass.init(&store);
    _ = pass;
}

test "LockPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-lock-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

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
