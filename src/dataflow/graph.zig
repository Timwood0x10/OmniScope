//! Data Flow Graph
//!
//! This module defines the unified data flow graph that serves as the central
//! data structure for all analysis passes. It provides a high-level abstraction
//! over the Fact Store for managing data flow relationships.
//!
//! v0.3 Enhancements:
//! - Arena allocator for batch allocations

const std = @import("std");

const Allocator = std.mem.Allocator;

const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;

const Location = @import("../diag/issue.zig").Location;
const Issue = @import("../diag/issue.zig").Issue;
const IssueKind = @import("../diag/issue.zig").IssueKind;
const Severity = @import("../diag/issue.zig").Severity;
const FFIBoundary = @import("../diag/issue.zig").FFIBoundary;

const DataNode = @import("node.zig").DataNode;
const DataEdge = @import("edge.zig").DataEdge;
const ValueType = @import("node.zig").ValueType;
const EdgeType = @import("edge.zig").EdgeType;

const FFIMatcher = @import("../ffi/ffi_matcher.zig").FFIMatcher;
const ArenaAllocator = @import("../perf/memory_pool.zig").ArenaAllocator;

/// Data Flow Graph
///
/// The unified data structure that represents all data flow relationships
/// in the analyzed program. This graph is built on top of the Fact Store
/// and provides high-level abstractions for analysis passes.
pub const DataFlowGraph = struct {
    /// Memory allocator
    allocator: Allocator,
    /// Arena allocator for batch allocations
    arena: ArenaAllocator,
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

    /// Create a new data flow graph
    pub fn init(allocator: Allocator, fact_store: *FactStore, query_engine: *QueryEngine) !DataFlowGraph {
        return .{
            .allocator = allocator,
            .arena = try ArenaAllocator.init(allocator),
            .fact_store = fact_store,
            .query_engine = query_engine,
            .nodes = std.AutoHashMap(u32, DataNode).init(allocator),
            .edges = try std.ArrayList(DataEdge).initCapacity(allocator, 0),
            .ffi_boundaries = try std.ArrayList(FFIBoundary).initCapacity(allocator, 0),
            .issues = try std.ArrayList(Issue).initCapacity(allocator, 0),
            .ffi_matcher = null,
            .outgoing_edges = std.AutoHashMap(u32, []const u32).init(allocator),
            .incoming_edges = std.AutoHashMap(u32, []const u32).init(allocator),
            .tainted_nodes = try std.ArrayList(u32).initCapacity(allocator, 0),
        };
    }

    /// Deinitialize the data flow graph
    pub fn deinit(self: *DataFlowGraph) void {
        self.nodes.deinit();
        self.edges.deinit(self.allocator);
        self.ffi_boundaries.deinit(self.allocator);

        for (self.issues.items) |issue| {
            self.allocator.free(issue.message);
        }
        self.issues.deinit(self.allocator);

        var outgoing_iter = self.outgoing_edges.iterator();
        while (outgoing_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.outgoing_edges.deinit();

        var incoming_iter = self.incoming_edges.iterator();
        while (incoming_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.incoming_edges.deinit();

        self.tainted_nodes.deinit(self.allocator);
        self.arena.deinit();
    }

    /// Add a node to the graph
    ///
    /// Parameters:
    ///   - node: The node to add
    ///
    /// Returns:
    ///   - error if node already exists
    pub fn addNode(self: *DataFlowGraph, node: DataNode) !void {
        if (self.nodes.contains(node.id)) {
            return error.NodeAlreadyExists;
        }

        try self.nodes.put(node.id, node);

        // If node is tainted, add to tainted nodes list
        if (node.is_tainted) {
            try self.tainted_nodes.append(self.allocator, node.id);
        }

        // Initialize edge indices for this node
        try self.outgoing_edges.put(node.id, &[_]u32{});
        try self.incoming_edges.put(node.id, &[_]u32{});
    }

    /// Get a node by ID
    ///
    /// Parameters:
    ///   - id: Node ID
    ///
    /// Returns:
    ///   - Pointer to the node, or null if not found
    pub fn getNode(self: *const DataFlowGraph, id: u32) ?*const DataNode {
        return self.nodes.getPtr(id);
    }

    /// Add an edge to the graph
    ///
    /// Parameters:
    ///   - edge: The edge to add
    ///
    /// Returns:
    ///   - error if edge references non-existent nodes
    pub fn addEdge(self: *DataFlowGraph, edge: DataEdge) !void {
        // Validate that both nodes exist
        if (!self.nodes.contains(edge.from)) {
            return error.SourceNodeNotFound;
        }
        if (!self.nodes.contains(edge.to)) {
            return error.TargetNodeNotFound;
        }

        // Add edge to the list
        const edge_index = self.edges.items.len;
        try self.edges.append(self.allocator, edge);

        // Update indices
        if (self.outgoing_edges.get(edge.from)) |outgoing| {
            const new_list = try self.allocator.alloc(u32, outgoing.len + 1);
            @memcpy(new_list[0..outgoing.len], outgoing);
            new_list[@intCast(outgoing.len)] = @intCast(edge_index);
            self.allocator.free(outgoing);
            try self.outgoing_edges.put(edge.from, new_list);
        }

        if (self.incoming_edges.get(edge.to)) |incoming| {
            const new_list = try self.allocator.alloc(u32, incoming.len + 1);
            @memcpy(new_list[0..incoming.len], incoming);
            new_list[@intCast(incoming.len)] = @intCast(edge_index);
            self.allocator.free(incoming);
            try self.incoming_edges.put(edge.to, new_list);
        }
    }

    /// Get outgoing edges for a node
    ///
    /// Parameters:
    ///   - node_id: Node ID
    ///
    /// Returns:
    ///   - Slice of outgoing edge indices
    pub fn getOutgoingEdges(self: *const DataFlowGraph, node_id: u32) []const u32 {
        return self.outgoing_edges.get(node_id) orelse &[_]u32{};
    }

    /// Get incoming edges for a node
    ///
    /// Parameters:
    ///   - node_id: Node ID
    ///
    /// Returns:
    ///   - Slice of incoming edge indices
    pub fn getIncomingEdges(self: *const DataFlowGraph, node_id: u32) []const u32 {
        return self.incoming_edges.get(node_id) orelse &[_]u32{};
    }

    /// Add an FFI boundary to the graph
    ///
    /// Parameters:
    ///   - boundary: The FFI boundary to add
    pub fn addFFIBoundary(self: *DataFlowGraph, boundary: FFIBoundary) !void {
        try self.ffi_boundaries.append(self.allocator, boundary);
    }

    /// Get all FFI boundaries
    ///
    /// Returns:
    ///   - Slice of FFI boundaries
    pub fn getFFIBoundaries(self: *const DataFlowGraph) []const FFIBoundary {
        return self.ffi_boundaries.items;
    }

    /// Set the FFI matcher for cross-language function matching
    ///
    /// Parameters:
    ///   - matcher: Pointer to the FFI matcher instance
    pub fn setFFIMatcher(self: *DataFlowGraph, matcher: *FFIMatcher) void {
        self.ffi_matcher = matcher;
    }

    /// Get the FFI matcher if available
    ///
    /// Returns:
    ///   - Pointer to FFI matcher, or null if not set
    pub fn getFFIMatcher(self: *const DataFlowGraph) ?*FFIMatcher {
        return self.ffi_matcher;
    }

    /// Check if FFI matcher is available
    ///
    /// Returns:
    ///   - true if FFI matcher is set
    pub fn hasFFIMatcher(self: *const DataFlowGraph) bool {
        return self.ffi_matcher != null;
    }

    /// Create FFI boundaries from FFIMatcher matches
    ///
    /// This method iterates through all FFI matches and creates
    /// corresponding FFIBoundary entries in the graph.
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn createFFIBoundariesFromMatcher(self: *DataFlowGraph) !void {
        if (self.ffi_matcher == null) return;

        const matcher = self.ffi_matcher.?;
        const matches = matcher.getMatches();

        // Generate IDs starting from the current boundary count + 1
        var id: u32 = @intCast(self.ffi_boundaries.items.len + 1);

        for (matches) |match| {
            if (!match.isValid()) continue;

            // Infer languages from function names
            const declare_name = match.declare_func.?.name;
            const define_name = match.define_func.?.name;

            const caller_lang = inferLanguage(declare_name);
            const callee_lang = inferLanguage(define_name);

            const boundary_kind = inferBoundaryKind(caller_lang, callee_lang);

            // Create location
            const location = Location.init(declare_name);

            // Create FFI boundary
            const boundary = FFIBoundary.init(
                id,
                boundary_kind,
                caller_lang,
                callee_lang,
                match.name,
                location,
            );

            try self.ffi_boundaries.append(self.allocator, boundary);
            id += 1;
        }
    }

    /// Infer language from function name
    ///
    /// Parameters:
    ///   - func_name: Function name
    ///
    /// Returns:
    ///   - Inferred language
    fn inferLanguage(func_name: []const u8) FFIBoundary.Language {
        // Check for Rust patterns
        if (std.mem.indexOf(u8, func_name, "extern") != null or
            std.mem.indexOf(u8, func_name, "rust_") != null or
            std.mem.indexOf(u8, func_name, "_ZN") != null)
        {
            return .rust;
        }

        // Check for Zig patterns
        if (std.mem.indexOf(u8, func_name, "c_") != null) {
            // Be careful: c_ prefix could be either Zig calling C or just a C function name
            // Additional context needed for accurate identification
            return .zig;
        }

        // Default to C
        return .c;
    }

    /// Infer boundary kind from caller and callee languages
    ///
    /// Parameters:
    ///   - caller_lang: Caller language
    ///   - callee_lang: Callee language
    ///
    /// Returns:
    ///   - Boundary kind
    fn inferBoundaryKind(
        caller_lang: FFIBoundary.Language,
        callee_lang: FFIBoundary.Language,
    ) FFIBoundary.BoundaryKind {
        return switch (caller_lang) {
            .rust => switch (callee_lang) {
                .c => .rust_to_c,
                .zig => .external_unknown,
                else => .external_unknown,
            },
            .zig => switch (callee_lang) {
                .c => .zig_to_c,
                .rust => .external_unknown,
                else => .external_unknown,
            },
            .c => switch (callee_lang) {
                .rust => .c_to_rust,
                .zig => .c_to_zig,
                else => .external_unknown,
            },
            else => .external_unknown,
        };
    }

    /// Add an issue to the graph
    ///
    /// Parameters:
    ///   - issue: The issue to add
    pub fn addIssue(self: *DataFlowGraph, issue: Issue) !void {
        // Copy message to ensure we own the memory
        const message_copy = try self.allocator.dupe(u8, issue.message);
        var issue_copy = issue;
        issue_copy.message = message_copy;

        try self.issues.append(self.allocator, issue_copy);
    }

    /// Get all issues
    ///
    /// Returns:
    ///   - Slice of issues
    pub fn getIssues(self: *const DataFlowGraph) []const Issue {
        return self.issues.items;
    }

    /// Get issues by severity
    ///
    /// WARNING: Unlike most getters in this struct which return borrowed slices,
    /// this function allocates new memory. The caller MUST free the returned
    /// slice using the same allocator used by this DataFlowGraph instance.
    ///
    /// Arguments:
    ///   - severity: Severity level to filter by
    ///
    /// Returns:
    ///   - Newly allocated slice of issues with the specified severity
    ///   - Returns empty slice (not null) if no matches found
    ///   - Returns error on OOM
    ///   - Caller owns the returned memory
    pub fn getIssuesBySeverity(self: *const DataFlowGraph, severity: Severity) ![]Issue {
        var count: usize = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == severity) {
                count += 1;
            }
        }

        if (count == 0) {
            return &[_]Issue{};
        }

        const result = try self.allocator.alloc(Issue, count);

        var index: usize = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == severity) {
                result[index] = issue;
                index += 1;
            }
        }

        return result;
    }

    /// Get all tainted nodes
    ///
    /// Returns:
    ///   - Slice of tainted node IDs
    pub fn getTaintedNodes(self: *const DataFlowGraph) []const u32 {
        return self.tainted_nodes.items;
    }

    /// Mark a node as tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to mark as tainted
    ///   - source_id: Optional source node ID
    ///
    /// Returns:
    ///   - error if node not found
    pub fn markTainted(self: *DataFlowGraph, node_id: u32, source_id: ?u32) !void {
        if (!self.nodes.contains(node_id)) {
            return error.NodeNotFound;
        }

        if (self.nodes.getPtr(node_id)) |node| {
            if (!node.is_tainted) {
                node.setTainted(source_id);
                try self.tainted_nodes.append(self.allocator, node_id);
            }
        }
    }

    /// Check if a node is tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to check
    ///
    /// Returns:
    ///   - true if node is tainted
    pub fn isTainted(self: *const DataFlowGraph, node_id: u32) bool {
        if (self.nodes.get(node_id)) |node| {
            return node.is_tainted;
        }
        return false;
    }

    /// Get graph statistics
    ///
    /// Returns:
    ///   - Graph statistics
    pub fn getStats(self: *const DataFlowGraph) GraphStats {
        return .{
            .node_count = self.nodes.count(),
            .edge_count = self.edges.items.len,
            .tainted_node_count = self.tainted_nodes.items.len,
            .ffi_boundary_count = self.ffi_boundaries.items.len,
            .issue_count = self.issues.items.len,
        };
    }

    /// Graph statistics
    pub const GraphStats = struct {
        /// Total number of nodes
        node_count: usize,
        /// Total number of edges
        edge_count: usize,
        /// Number of tainted nodes
        tainted_node_count: usize,
        /// Number of FFI boundaries
        ffi_boundary_count: usize,
        /// Total number of issues
        issue_count: usize,
    };

    /// Clear all data from the graph
    pub fn clear(self: *DataFlowGraph) void {
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
        self.ffi_boundaries.clearRetainingCapacity();

        // Free owned issue messages before clearing
        for (self.issues.items) |issue| {
            self.allocator.free(issue.message);
        }
        self.issues.clearRetainingCapacity();

        self.tainted_nodes.clearRetainingCapacity();

        // Clear edge indices
        var outgoing_iter = self.outgoing_edges.iterator();
        while (outgoing_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.outgoing_edges.clearRetainingCapacity();

        var incoming_iter = self.incoming_edges.iterator();
        while (incoming_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.incoming_edges.clearRetainingCapacity();
    }
};

// Unit tests

test "DataFlowGraph - init and deinit" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    try std.testing.expectEqual(@as(usize, 0), dfg.nodes.count());
    try std.testing.expectEqual(@as(usize, 0), dfg.edges.items.len);
}

test "DataFlowGraph - addNode" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node = DataNode.init(1, .pointer, location);

    try dfg.addNode(node);

    try std.testing.expectEqual(@as(usize, 1), dfg.nodes.count());
    try std.testing.expect(dfg.getNode(1) != null);
}

test "DataFlowGraph - addNode duplicate" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node = DataNode.init(1, .pointer, location);

    try dfg.addNode(node);
    const result = dfg.addNode(node);

    try std.testing.expectError(error.NodeAlreadyExists, result);
}

test "DataFlowGraph - addEdge" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);

    const edge = DataEdge.init(1, 2, .direct);
    try dfg.addEdge(edge);

    try std.testing.expectEqual(@as(usize, 1), dfg.edges.items.len);
    try std.testing.expectEqual(@as(usize, 1), dfg.getOutgoingEdges(1).len);
    try std.testing.expectEqual(@as(usize, 1), dfg.getIncomingEdges(2).len);
}

test "DataFlowGraph - addEdge invalid node" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);

    try dfg.addNode(node1);

    const edge = DataEdge.init(1, 999, .direct);
    const result = dfg.addEdge(edge);

    try std.testing.expectError(error.TargetNodeNotFound, result);
}

test "DataFlowGraph - markTainted" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);

    try dfg.markTainted(1, null);
    try dfg.markTainted(2, 1);

    try std.testing.expect(dfg.isTainted(1));
    try std.testing.expect(dfg.isTainted(2));
    try std.testing.expectEqual(@as(usize, 2), dfg.getTaintedNodes().len);
}

test "DataFlowGraph - addIssue" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const issue = Issue.init(
        .ffi_unsafe_call,
        "Test message",
        location,
        .high,
        0.9,
    );

    try dfg.addIssue(issue);

    try std.testing.expectEqual(@as(usize, 1), dfg.getIssues().len);
}

test "DataFlowGraph - getStats" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);

    const edge = DataEdge.init(1, 2, .direct);
    try dfg.addEdge(edge);

    try dfg.markTainted(1, null);

    const boundary = FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );
    try dfg.addFFIBoundary(boundary);

    const issue = Issue.init(
        .ffi_unsafe_call,
        "Test message",
        location,
        .high,
        0.9,
    );
    try dfg.addIssue(issue);

    const stats = dfg.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.node_count);
    try std.testing.expectEqual(@as(usize, 1), stats.edge_count);
    try std.testing.expectEqual(@as(usize, 1), stats.tainted_node_count);
    try std.testing.expectEqual(@as(usize, 1), stats.ffi_boundary_count);
    try std.testing.expectEqual(@as(usize, 1), stats.issue_count);
}

test "DataFlowGraph - clear" {
    var fact_store = @import("../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = @import("../fact/query.zig").QueryEngine.init(&fact_store);

    var dfg = try DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer dfg.deinit();

    const location = Location.init("test_func");
    const node1 = DataNode.init(1, .pointer, location);
    const node2 = DataNode.init(2, .integer, location);

    try dfg.addNode(node1);
    try dfg.addNode(node2);

    const edge = DataEdge.init(1, 2, .direct);
    try dfg.addEdge(edge);

    dfg.clear();

    try std.testing.expectEqual(@as(usize, 0), dfg.nodes.count());
    try std.testing.expectEqual(@as(usize, 0), dfg.edges.items.len);
}
