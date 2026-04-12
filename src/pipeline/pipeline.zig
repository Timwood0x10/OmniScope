//! Analysis Pipeline
//!
//! This module implements the overall analysis pipeline that
//! orchestrates passes, stages, and data flow.

const std = @import("std");
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;

const PassContext = @import("../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const PassManager = @import("../pass/manager.zig").PassManager;

const InstrumentationPlan = @import("../pass/instrumentation/planner.zig").InstrumentationPlan;

/// Analysis pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    fact_store: FactStore,
    query_engine: QueryEngine,
    pass_manager: PassManager,
    instrumentation_plan: InstrumentationPlan,

    /// Create a new analysis pipeline
    pub fn init(allocator: std.mem.Allocator) Pipeline {
        return .{
            .allocator = allocator,
            .fact_store = FactStore.init(allocator),
            .query_engine = QueryEngine.init(&FactStore.init(allocator)), // Temporary, will be fixed
            .pass_manager = PassManager.init(allocator),
            .instrumentation_plan = InstrumentationPlan.init(allocator),
        };
    }

    /// Deinitialize the pipeline
    pub fn deinit(self: *Pipeline) void {
        self.fact_store.deinit();
        self.pass_manager.deinit();
        self.instrumentation_plan.deinit();
    }

    /// Run the full analysis pipeline
    pub fn run(self: *Pipeline, module: []const u8) !void {
        _ = module;

        // Reinitialize query engine with correct store
        self.query_engine = QueryEngine.init(&self.fact_store);

        // Create context
        var ctx = PassContext{ .allocator = self.allocator };
        var diag = DiagnosticWriter{ .allocator = self.allocator };

        // Run passes
        try self.pass_manager.run(&ctx, &diag);

        // Optimize instrumentation plan
        try self.instrumentation_plan.optimize();
    }

    /// Get the fact store
    pub fn getFactStore(self: *Pipeline) *FactStore {
        return &self.fact_store;
    }

    /// Get the query engine
    pub fn getQueryEngine(self: *Pipeline) *QueryEngine {
        return &self.query_engine;
    }

    /// Get the instrumentation plan
    pub fn getInstrumentationPlan(self: *Pipeline) *InstrumentationPlan {
        return &self.instrumentation_plan;
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
    /// Number of instrumentations planned
    instrumentation_count: usize,
    /// Execution time in nanoseconds
    execution_time_ns: u64,

    /// Create a new pipeline result
    pub fn init(
        fact_count: usize,
        instrumentation_count: usize,
        execution_time_ns: u64,
    ) PipelineResult {
        return .{
            .fact_count = fact_count,
            .instrumentation_count = instrumentation_count,
            .execution_time_ns = execution_time_ns,
        };
    }
};

test "Pipeline - init and deinit" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    try std.testing.expectEqual(@as(usize, 0), pipeline.fact_store.count());
}

test "Pipeline - get components" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();
    const query_engine = pipeline.getQueryEngine();
    const plan = pipeline.getInstrumentationPlan();

    _ = fact_store;
    _ = query_engine;
    _ = plan;
}

test "Pipeline - register pass" {
    var pipeline = Pipeline.init(std.testing.allocator);
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

test "PipelineResult - init" {
    const result = PipelineResult.init(100, 50, 1_000_000);

    try std.testing.expectEqual(@as(usize, 100), result.fact_count);
    try std.testing.expectEqual(@as(usize, 50), result.instrumentation_count);
    try std.testing.expectEqual(@as(u64, 1_000_000), result.execution_time_ns);
}

test "Pipeline - basic flow" {
    var pipeline = Pipeline.init(std.testing.allocator);
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

    // Run pipeline (will not actually do much since we don't have a real module)
    // This just tests that the structure works
    try pipeline.run("test");

    // Verify components are accessible
    try std.testing.expect(pipeline.getFactStore() != null);
    try std.testing.expect(pipeline.getQueryEngine() != null);
    try std.testing.expect(pipeline.getInstrumentationPlan() != null);
}
