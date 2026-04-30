//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const zone_classifier = @import("../semantics/zone_classifier.zig");
const Issue = @import("../diag/issue.zig").Issue;

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
/// - Zone statistics for Safe/Escape zone classification
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    data_flow_graph: *DataFlowGraph,
    next_id: std.atomic.Value(u32),
    vuln_id: std.atomic.Value(u32),
    value_id_map: ValueIdMap,
    raii_func_set: std.AutoHashMap(usize, void),
    meyers_singleton_set: std.AutoHashMap(usize, void),
    rc_container_func_set: std.AutoHashMap(usize, void),
    rust_into_raw_set: std.AutoHashMap(usize, void),
    rust_from_raw_set: std.AutoHashMap(usize, void),

    /// Cross-pass deduplication: tracks (func_name, issue_kind) pairs
    /// that have already been reported by a previous pass.
    /// Prevents FFI Analysis + PointerOwnership from double-reporting
    /// the same underlying instruction/issue.
    reported_keys: std.AutoHashMap(u64, void),

    /// Zone statistics for function classification
    zone_stats: zone_classifier.ZoneStats,

    /// Degradation statistics
    /// Tracks the number of functions that were skipped due to errors
    degraded_functions: std.atomic.Value(u32),

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
            .value_id_map = ValueIdMap.init(allocator),
            .raii_func_set = std.AutoHashMap(usize, void).init(allocator),
            .meyers_singleton_set = std.AutoHashMap(usize, void).init(allocator),
            .rc_container_func_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_into_raw_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_from_raw_set = std.AutoHashMap(usize, void).init(allocator),
            .reported_keys = std.AutoHashMap(u64, void).init(allocator),
            .zone_stats = zone_classifier.ZoneStats{},
            .degraded_functions = std.atomic.Value(u32).init(0),
        };
    }

    /// Get a unique ID for non-pointer entities (functions, basic blocks, etc.)
    ///
    /// Returns:
    ///   - u32: A unique sequential ID (thread-safe)
    ///
    /// Note: For LLVM Value pointers, use getValueId() instead
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    /// Get a unique ID for an LLVM value pointer.
    /// Uses ValueIdMap to ensure the same pointer always gets the same ID,
    /// avoiding collision issues from pointer truncation on 64-bit systems.
    ///
    /// Parameters:
    ///   - ptr: LLVM value pointer (must be non-null)
    ///
    /// Returns:
    ///   - u32: Unique ID for this pointer (consistent across calls)
    ///
    /// Errors:
    ///   - error.NullPointer: If ptr is 0
    pub fn getValueId(self: *PassContext, ptr: usize) !u32 {
        return self.value_id_map.getOrPutId(ptr);
    }

    /// Get a unique vulnerability ID (shared across all detection passes)
    pub fn getNextVulnId(self: *PassContext) u32 {
        return self.vuln_id.fetchAdd(1, .seq_cst) + 1;
    }

    /// P-DEGRADE-3 — Increment degraded function counter
    /// Call this when a function analysis is skipped due to an error
    pub fn recordDegradedFunction(self: *PassContext) void {
        _ = self.degraded_functions.fetchAdd(1, .seq_cst);
    }

    /// P-DEGRADE-3 — Get degraded function count
    pub fn getDegradedFunctionCount(self: *const PassContext) u32 {
        return self.degraded_functions.load(.seq_cst);
    }

    /// Release all resources held by this context
    pub fn deinit(self: *PassContext) void {
        self.value_id_map.deinit();
        self.raii_func_set.deinit();
        self.meyers_singleton_set.deinit();
        self.rc_container_func_set.deinit();
        self.rust_into_raw_set.deinit();
        self.rust_from_raw_set.deinit();
        self.reported_keys.deinit();
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
    /// Features cross-pass deduplication: if another pass has already
    /// reported an issue with the same (function, kind) signature,
    /// this call is silently skipped to avoid duplicate alerts.
    pub fn addIssue(self: *PassContext, issue: *const Issue) !void {
        const dedup_key = self.dedupKey(issue);
        const gop = try self.reported_keys.getOrPut(dedup_key);
        if (gop.found_existing) {
            var dup = issue.*;
            dup.deinit(self.allocator);
            return;
        }
        try self.data_flow_graph.addIssue(issue.*);
    }

    /// Compute a dedup key from an issue's (func_name, kind) pair.
    /// Uses FNV-1a hash for fast lookup.
    fn dedupKey(self: *PassContext, issue: *const Issue) u64 {
        _ = self;
        const func_name = @field(issue, "location").function;
        const kind_tag = @tagName(@field(issue, "kind"));
        var hasher = std.hash.Fnv1a_64.init();
        hasher.update(func_name);
        hasher.update(kind_tag);
        if (@field(issue, "location").file) |file| hasher.update(file);
        if (@field(issue, "location").line) |line| hasher.update(&std.mem.toBytes(line));
        return hasher.final();
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
        if (log.current_log_level == .quiet) return;
        if (std.mem.eql(u8, severity, "DEBUG") and log.current_log_level != .debug) return;
        // WARN messages only show in verbose mode or higher (not normal mode)
        // This reduces noise: normal mode shows only issues, verbose shows analysis details
        if (std.mem.eql(u8, severity, "WARN") and log.current_log_level == .normal) return;

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

/// Print zone classification summary
/// Output format: "Analyzed 987 functions, 42 in unsafe/FFI zones, found 3 real issues"
pub fn printZoneSummary(stats: zone_classifier.ZoneStats, dfg: *DataFlowGraph) void {
    if (log.current_log_level == .quiet) return;

    const total = stats.total();
    const escape_count = stats.unsafe_count + stats.ffi_count;
    const skip_ratio = stats.skipRatio();
    const issue_stats = dfg.getIssueStats();

    std.debug.print("\n" ++ Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n", .{});
    std.debug.print(Colors.bold ++ "Zone Classification Summary" ++ Colors.reset ++ "\n", .{});
    std.debug.print(Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n\n", .{});

    std.debug.print("  Total functions analyzed:    {d}\n", .{total});
    std.debug.print("  Safe zone (skipped):         {d} ({d:.1}%)\n", .{ stats.safe_count, skip_ratio * 100 });
    std.debug.print("  Runtime internal (skipped):  {d}\n", .{stats.runtime_count});
    std.debug.print("  Unsafe zone (analyzed):      {d}\n", .{stats.unsafe_count});
    std.debug.print("  FFI zone (analyzed):         {d}\n", .{stats.ffi_count});
    std.debug.print("  Unknown zone:                {d}\n", .{stats.unknown_count});
    std.debug.print("\n", .{});

    std.debug.print(Colors.green ++ "  Escape zone functions:       {d} ({d:.1}% of total)" ++ Colors.reset ++ "\n", .{ escape_count, if (total > 0) @as(f64, @floatFromInt(escape_count)) / @as(f64, @floatFromInt(total)) * 100 else 0 });

    if (issue_stats.total > 0) {
        std.debug.print(Colors.yellow ++ "  Issues found:              {d}" ++ Colors.reset ++ "\n", .{issue_stats.total});

        std.debug.print("\n    " ++ Colors.bold ++ "Issue breakdown by category:" ++ Colors.reset ++ "\n", .{});
        if (issue_stats.memory_leak > 0) {
            std.debug.print("      Memory leak:              {d}\n", .{issue_stats.memory_leak});
        }
        if (issue_stats.use_after_free > 0) {
            std.debug.print("      Use after free:           {d}\n", .{issue_stats.use_after_free});
        }
        if (issue_stats.double_free > 0) {
            std.debug.print("      Double free:               {d}\n", .{issue_stats.double_free});
        }
        if (issue_stats.ffi_unsafe > 0) {
            std.debug.print("      FFI unsafe call:          {d}\n", .{issue_stats.ffi_unsafe});
        }
        if (issue_stats.command_injection > 0) {
            std.debug.print("      Command injection:         {d}\n", .{issue_stats.command_injection});
        }
        if (issue_stats.buffer_overflow > 0) {
            std.debug.print("      Buffer overflow:          {d}\n", .{issue_stats.buffer_overflow});
        }
        if (issue_stats.format_string > 0) {
            std.debug.print("      Format string:            {d}\n", .{issue_stats.format_string});
        }
        if (issue_stats.type_mismatch > 0) {
            std.debug.print("      Type mismatch:            {d}\n", .{issue_stats.type_mismatch});
        }
        if (issue_stats.borrow_escape > 0) {
            std.debug.print("      Borrow escape:            {d}\n", .{issue_stats.borrow_escape});
        }
        if (issue_stats.null_dereference > 0) {
            std.debug.print("      Null dereference:         {d}\n", .{issue_stats.null_dereference});
        }
        if (issue_stats.invalid_free > 0) {
            std.debug.print("      Invalid free:             {d}\n", .{issue_stats.invalid_free});
        }
        if (issue_stats.unchecked_return > 0) {
            std.debug.print("      Unchecked return:         {d}\n", .{issue_stats.unchecked_return});
        }
        if (issue_stats.malloc_unchecked > 0) {
            std.debug.print("      Malloc unchecked:         {d}\n", .{issue_stats.malloc_unchecked});
        }
        if (issue_stats.callback_mismatch > 0) {
            std.debug.print("      Callback mismatch:        {d}\n", .{issue_stats.callback_mismatch});
        }
        if (issue_stats.unknown > 0) {
            std.debug.print("      Unknown:                  {d}\n", .{issue_stats.unknown});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print(Colors.green ++ "  Issues found:                0" ++ Colors.reset ++ "\n\n", .{});
    }

    std.debug.print(Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n\n", .{});
}

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
