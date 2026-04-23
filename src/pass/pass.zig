//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.

const std = @import("std");
const Allocator = std.mem.Allocator;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;

/// Pass kind classification
pub const PassKind = enum {
    foundation, // Basic analysis passes (CFG, DFG)
    analysis, // Advanced analysis passes (alias, lock, taint)
    plugin, // User-defined plugin passes
};

/// Pass context passed to each pass during execution
///
/// This struct provides all necessary context for pass execution:
/// - Memory allocation
/// - Access to IR module
/// - Access to fact store for reading/writing facts
/// - Access to query engine for querying facts
/// - Access to data flow graph for high-level data flow operations
/// - ID allocation for unique identifiers
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    data_flow_graph: *DataFlowGraph,
    next_id: std.atomic.Value(u32),
    vuln_id: std.atomic.Value(u32),
    raii_func_set: std.AutoHashMap(usize, void),
    meyers_singleton_set: std.AutoHashMap(usize, void),
    rc_container_func_set: std.AutoHashMap(usize, void),
    rust_into_raw_set: std.AutoHashMap(usize, void),
    rust_from_raw_set: std.AutoHashMap(usize, void),

    /// Create a new pass context
    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
        data_flow_graph: *DataFlowGraph,
    ) PassContext {
        return .{
            .allocator = allocator,
            .module = module,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .data_flow_graph = data_flow_graph,
            .next_id = std.atomic.Value(u32).init(1),
            .vuln_id = std.atomic.Value(u32).init(0),
            .raii_func_set = std.AutoHashMap(usize, void).init(allocator),
            .meyers_singleton_set = std.AutoHashMap(usize, void).init(allocator),
            .rc_container_func_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_into_raw_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_from_raw_set = std.AutoHashMap(usize, void).init(allocator),
        };
    }

    /// Get a unique ID
    ///
    /// Returns:
    ///   - u32: A unique ID (thread-safe)
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    /// Get a unique vulnerability ID (shared across all detection passes)
    pub fn getNextVulnId(self: *PassContext) u32 {
        return self.vuln_id.fetchAdd(1, .seq_cst) + 1;
    }

    /// Release all resources held by this context
    pub fn deinit(self: *PassContext) void {
        self.raii_func_set.deinit();
        self.meyers_singleton_set.deinit();
        self.rc_container_func_set.deinit();
        self.rust_into_raw_set.deinit();
        self.rust_from_raw_set.deinit();
    }

    /// Set the IR module
    ///
    /// Parameters:
    ///   - module: The LLVM module to analyze
    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    /// Check if a module is loaded
    ///
    /// Returns:
    ///   - true if a module is loaded, false otherwise
    pub fn hasModule(self: *const PassContext) bool {
        return self.module != null;
    }

    /// Get data flow graph
    ///
    /// Returns:
    ///   - Reference to the data flow graph
    pub fn getDataFlowGraph(self: *const PassContext) *DataFlowGraph {
        return self.data_flow_graph;
    }

    /// Add a node to data flow graph
    ///
    /// Parameters:
    ///   - node: The node to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addNode(self: *PassContext, node: anytype) !void {
        try self.data_flow_graph.addNode(node);
    }

    /// Add an edge to data flow graph
    ///
    /// Parameters:
    ///   - edge: The edge to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addEdge(self: *PassContext, edge: anytype) !void {
        try self.data_flow_graph.addEdge(edge);
    }

    /// Add an FFI boundary to data flow graph
    ///
    /// Parameters:
    ///   - boundary: The FFI boundary to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addFFIBoundary(self: *PassContext, boundary: anytype) !void {
        try self.data_flow_graph.addFFIBoundary(boundary);
    }

    /// Add an issue to data flow graph
    ///
    /// Parameters:
    ///   - issue: The issue to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addIssue(self: *PassContext, issue: anytype) !void {
        try self.data_flow_graph.addIssue(issue);
    }

    /// Mark a node as tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to mark as tainted
    ///   - source_id: Optional source node ID
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn markTainted(self: *PassContext, node_id: u32, source_id: ?u32) !void {
        try self.data_flow_graph.markTainted(node_id, source_id);
    }

    /// Check if a node is tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to check
    ///
    /// Returns:
    ///   - true if node is tainted
    pub fn isTainted(self: *const PassContext, node_id: u32) bool {
        return self.data_flow_graph.isTainted(node_id);
    }
};

/// ANSI color codes for terminal output
const Colors = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const green = "\x1b[32m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
};

/// Diagnostic writer for pass output with color support
pub const DiagnosticWriter = struct {
    allocator: Allocator,
    use_color: bool = true,

    pub fn write(self: *DiagnosticWriter, comptime severity: []const u8, comptime format: []const u8, args: anytype) void {
        const color = comptime getSeverityColor(severity);
        if (self.use_color) {
            std.debug.print(color ++ "[" ++ severity ++ "]" ++ Colors.reset ++ " " ++ format ++ "\n", args);
        } else {
            std.debug.print("[" ++ severity ++ "] " ++ format ++ "\n", args);
        }
    }

    pub fn info(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("INFO", format, args);
    }

    pub fn warn(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("WARN", format, args);
    }

    pub fn err(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("ERROR", format, args);
    }

    pub fn critical(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("CRITICAL", format, args);
    }

    pub fn debug(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("DEBUG", format, args);
    }
};

fn getSeverityColor(comptime severity: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, severity, "CRITICAL")) {
        return Colors.bold ++ Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "ERROR")) {
        return Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "WARN")) {
        return Colors.yellow;
    } else if (comptime std.mem.eql(u8, severity, "INFO")) {
        return Colors.green;
    } else if (comptime std.mem.eql(u8, severity, "DEBUG")) {
        return Colors.dim;
    }
    return Colors.reset;
}

/// Pass comptime wrapper with type validation
///
/// This function validates that a type satisfies the Pass interface
/// at compile time and returns the type unchanged.
pub fn Pass(comptime T: type) type {
    comptime {
        // Validate required declarations
        if (!@hasDecl(T, "name"))
            @compileError("Pass must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Pass must have a 'kind' declaration (PassKind)");
        if (!@hasDecl(T, "deps"))
            @compileError("Pass must have a 'deps' declaration ([]const []const u8)");
        if (!@hasDecl(T, "run"))
            @compileError("Pass must have a 'run' function");

        // Note: In Zig 0.15.2, strict type checking is simplified
        // The compiler will catch type mismatches during actual usage
    }
    return T;
}

test "Pass - comptime validation" {
    const ValidPass = Pass(struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "PassContext - init and deinit" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    const ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());
}

test "PassContext - getNextId" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    const id1 = ctx.getNextId();
    const id2 = ctx.getNextId();
    const id3 = ctx.getNextId();

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);
}

test "PassContext - setModule and hasModule" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());

    // Set a dummy module
    ctx.setModule(.{ .raw = undefined });

    try std.testing.expect(ctx.hasModule());
}

test "PassContext - access to components" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    const ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    // Verify access to components
    _ = ctx.fact_store;
    _ = ctx.query_engine;
    _ = ctx.allocator;
}
