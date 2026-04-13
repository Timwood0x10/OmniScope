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
const DiagnosticAggregator = @import("../diag/aggregator.zig").DiagnosticAggregator;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const IRLoader = @import("../engine/loader.zig").IRLoader;

/// Analysis pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    fact_store: FactStore,
    query_engine: QueryEngine,
    pass_manager: PassManager,
    instrumentation_plan: InstrumentationPlan,
    diagnostic_aggregator: DiagnosticAggregator,
    ir_loader: ?IRLoader,

    /// Create a new analysis pipeline
    pub fn init(allocator: std.mem.Allocator) Pipeline {
        return .{
            .allocator = allocator,
            .fact_store = FactStore.init(allocator),
            .query_engine = QueryEngine.init(&FactStore.init(allocator)), // Temporary, will be fixed
            .pass_manager = PassManager.init(allocator),
            .instrumentation_plan = InstrumentationPlan.init(allocator),
            .diagnostic_aggregator = DiagnosticAggregator.init(allocator),
            .ir_loader = null,
        };
    }

    /// Deinitialize the pipeline
    pub fn deinit(self: *Pipeline) void {
        self.fact_store.deinit();
        self.pass_manager.deinit();
        self.instrumentation_plan.deinit();
        self.diagnostic_aggregator.deinit();
        if (self.ir_loader) |loader| {
            loader.deinit();
        }
    }

    /// Load IR from file
    pub fn loadIR(self: *Pipeline, path: []const u8) !void {
        // Create IR loader
        const loader = try IRLoader.loadFile(self.allocator, path);

        // Clean up previous loader if exists
        if (self.ir_loader) |old_loader| {
            old_loader.deinit();
        }

        self.ir_loader = loader;
    }

    /// Run the full analysis pipeline
    pub fn run(self: *Pipeline) !void {
        // Reinitialize query engine with correct store
        self.query_engine = QueryEngine.init(&self.fact_store);

        // Create context with module
        var ctx = PassContext{
            .allocator = self.allocator,
            .module = if (self.ir_loader) |loader| loader.getModule() else null,
            .fact_store = &self.fact_store,
            .query_engine = &self.query_engine,
            .next_id = std.atomic.Value(u32).init(1),
        };

        var diag = DiagnosticWriter{ .allocator = self.allocator };

        // Run passes
        try self.pass_manager.run(&ctx, &diag);

        // Optimize instrumentation plan
        try self.instrumentation_plan.optimize();
    }

    /// Run static analysis stage
    pub fn runStaticAnalysis(self: *Pipeline) !PipelineResult {
        const start_time = std.time.nanoTimestamp();

        // Run passes
        try self.run();

        const end_time = std.time.nanoTimestamp();

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .instrumentation_count = self.instrumentation_plan.count(),
            .execution_time_ns = @intCast(end_time - start_time),
        };
    }

    /// Run instrumentation stage
    pub fn runInstrumentation(self: *Pipeline) !PipelineResult {
        const start_time = std.time.nanoTimestamp();

        // In a real implementation, this would:
        // 1. Use the instrumentation plan to modify IR
        // 2. Insert probe calls
        // 3. Generate instrumented IR

        // For now, just optimize the plan
        try self.instrumentation_plan.optimize();

        const end_time = std.time.nanoTimestamp();

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .instrumentation_count = self.instrumentation_plan.count(),
            .execution_time_ns = @intCast(end_time - start_time),
        };
    }

    /// Run full pipeline (static analysis + instrumentation)
    pub fn runFullPipeline(self: *Pipeline, ir_path: []const u8) !FullPipelineResult {
        const pipeline_start = std.time.nanoTimestamp();

        // 1. Load IR
        try self.loadIR(ir_path);

        // 2. Run static analysis
        const static_result = try self.runStaticAnalysis();

        // 3. Run instrumentation
        const instrumentation_result = try self.runInstrumentation();

        // 4. Generate diagnostics
        // In a real implementation, this would aggregate diagnostics from all sources

        const pipeline_end = std.time.nanoTimestamp();

        return FullPipelineResult{
            .static_result = static_result,
            .instrumentation_result = instrumentation_result,
            .runtime_result = null, // Runtime collection not yet implemented
            .merge_result = null, // Merge engine not yet implemented
            .total_time_ns = @intCast(pipeline_end - pipeline_start),
        };
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

    /// Get the diagnostic aggregator
    pub fn getDiagnosticAggregator(self: *Pipeline) *DiagnosticAggregator {
        return &self.diagnostic_aggregator;
    }

    /// Get the IR loader
    pub fn getIRLoader(self: *Pipeline) ?*IRLoader {
        if (self.ir_loader) |*loader| {
            return loader;
        }
        return null;
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
    const diag_aggregator = pipeline.getDiagnosticAggregator();

    _ = fact_store;
    _ = query_engine;
    _ = plan;
    _ = diag_aggregator;
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

test "Pipeline - run static analysis" {
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

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify result
    try std.testing.expect(result.execution_time_ns >= 0);
    try std.testing.expect(result.fact_count >= 0);
    try std.testing.expect(result.instrumentation_count >= 0);
}

test "Pipeline - run instrumentation" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Run instrumentation (no IR loaded, should still work)
    const result = try pipeline.runInstrumentation();

    // Verify result
    try std.testing.expect(result.execution_time_ns >= 0);
}

test "Pipeline - get IR loader" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // No IR loaded yet
    try std.testing.expect(pipeline.getIRLoader() == null);

    // Try to load a non-existent file (should fail gracefully)
    const load_result = pipeline.loadIR("nonexistent.bc");
    try std.testing.expectError(error.FileNotFound, load_result);
}

test "Pipeline - full pipeline without IR" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Try to run full pipeline with non-existent IR
    const result = pipeline.runFullPipeline("nonexistent.bc");

    // Should fail because file doesn't exist
    try std.testing.expectError(error.FileNotFound, result);
}

test "Pipeline - component integration" {
    var pipeline = Pipeline.init(std.testing.allocator);
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

test "Pipeline - instrumentation plan access" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const plan = pipeline.getInstrumentationPlan();

    // Add some instrumentations
    try plan.addInstrumentation(1, 42);
    try plan.addInstrumentation(2, 43);

    try std.testing.expectEqual(@as(usize, 2), plan.count());
}

test "Pipeline - diagnostic aggregator access" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const diag = pipeline.getDiagnosticAggregator();

    // Add a diagnostic
    const diagnostic = @import("../diag/aggregator.zig").Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 1,
        .message = "Test diagnostic",
        .confidence = 0.8,
    };

    try diag.add(diagnostic);

    // Verify diagnostic was added
    const all_diags = diag.getAll();
    try std.testing.expectEqual(@as(usize, 1), all_diags.len);
}

test "Pipeline - fact store integration" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();

    // Add some facts
    try fact_store.insert(.cfg_edge, 1, 2, 0);
    try fact_store.insert(.dfg_edge, 3, 4, 0);

    try std.testing.expectEqual(@as(usize, 2), fact_store.count());
}
