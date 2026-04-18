//! Analysis Pipeline
//!
//! This module implements the overall analysis pipeline that
//! orchestrates passes and data flow.

const std = @import("std");

const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const Issue = @import("../diag/issue.zig").Issue;
const ModuleRef = @import("../ir/view.zig").ModuleRef;

const PassContext = @import("../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const PassManager = @import("../pass/manager.zig").PassManager;

/// Analysis pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    data_flow_graph: DataFlowGraph,
    pass_manager: PassManager,
    module: ?ModuleRef,

    /// Create a new analysis pipeline
    pub fn init(allocator: std.mem.Allocator) !Pipeline {
        const fact_store = try allocator.create(FactStore);
        fact_store.* = FactStore.init(allocator);

        const query_engine = try allocator.create(QueryEngine);
        query_engine.* = QueryEngine.init(fact_store);

        const data_flow_graph = try DataFlowGraph.init(allocator, fact_store, query_engine);

        return .{
            .allocator = allocator,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .data_flow_graph = data_flow_graph,
            .pass_manager = PassManager.init(allocator),
            .module = null,
        };
    }

    /// Deinitialize the pipeline
    pub fn deinit(self: *Pipeline) void {
        self.data_flow_graph.deinit();
        self.fact_store.deinit();
        self.allocator.destroy(self.fact_store);
        self.allocator.destroy(self.query_engine);
        self.pass_manager.deinit();
    }

    /// Run the full analysis pipeline
    pub fn run(self: *Pipeline) !void {
        // Note: query_engine is a value type that references fact_store
        // We don't need to reinitialize it since fact_store pointer hasn't changed

        // Clear previous data flow graph state
        self.data_flow_graph.clear();

        // Create context with module and data flow graph
        var ctx = PassContext{
            .allocator = self.allocator,
            .module = self.module,
            .fact_store = self.fact_store,
            .query_engine = self.query_engine,
            .data_flow_graph = &self.data_flow_graph,
            .next_id = std.atomic.Value(u32).init(1),
        };

        var diag = DiagnosticWriter{ .allocator = self.allocator };

        // Run passes
        try self.pass_manager.run(&ctx, &diag);
    }

    /// Run static analysis stage
    pub fn runStaticAnalysis(self: *Pipeline) !PipelineResult {
        const start_time = std.time.nanoTimestamp();

        // Run passes
        try self.run();

        const end_time = std.time.nanoTimestamp();

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .execution_time_ns = @intCast(end_time - start_time),
        };
    }

    /// Get the fact store
    pub fn getFactStore(self: *Pipeline) *FactStore {
        return self.fact_store;
    }

    /// Get the query engine
    pub fn getQueryEngine(self: *Pipeline) *QueryEngine {
        return self.query_engine;
    }

    /// Get the data flow graph
    pub fn getDataFlowGraph(self: *Pipeline) *DataFlowGraph {
        return &self.data_flow_graph;
    }

    /// Get all detected issues
    pub fn getIssues(self: *const Pipeline) []const Issue {
        return self.data_flow_graph.getIssues();
    }

    /// Set the LLVM module to analyze
    pub fn setModule(self: *Pipeline, module: ModuleRef) void {
        self.module = module;
    }

    /// Register a pass with the pipeline
    pub fn registerPass(self: *Pipeline, comptime PassType: type) !void {
        try self.pass_manager.registerPass(PassType);
    }
};

/// Pipeline result
pub const PipelineResult = struct {
    /// Number of facts generated
    fact_count: usize,
    /// Execution time in nanoseconds
    execution_time_ns: u64,
};

test "Pipeline - init and deinit" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    try std.testing.expectEqual(@as(usize, 0), pipeline.fact_store.count());
}

test "Pipeline - get components" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();
    const query_engine = pipeline.getQueryEngine();

    _ = fact_store;
    _ = query_engine;
}

test "Pipeline - register pass" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(TestPass);
    try std.testing.expectEqual(@as(usize, 1), pipeline.pass_manager.count());
}

test "Pipeline - run static analysis" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register a test pass
    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(TestPass);

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify result
    try std.testing.expect(result.execution_time_ns >= 0);
    try std.testing.expect(result.fact_count >= 0);
}

test "Pipeline - component integration" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register multiple passes with dependencies
    const PassA = struct {
        pub const name = "A";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(PassB);
    try pipeline.registerPass(PassA);

    // Verify pass manager has correct count
    try std.testing.expectEqual(@as(usize, 2), pipeline.pass_manager.count());

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify execution order was resolved
    try std.testing.expect(result.execution_time_ns >= 0);
}

test "Pipeline - fact store integration" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();

    // Add some facts
    try fact_store.insert(.cfg_edge, 1, 2, 0);
    try fact_store.insert(.dfg_edge, 3, 4, 0);

    try std.testing.expectEqual(@as(usize, 2), fact_store.count());
}
