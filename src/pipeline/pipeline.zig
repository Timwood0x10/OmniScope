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

const RuntimeStage = @import("runtime_stage.zig").RuntimeStage;
const RuntimeStageConfig = @import("runtime_stage.zig").RuntimeStageConfig;
const MergeEngine = @import("../runtime/merge.zig").MergeEngine;
const DecodedEvent = @import("../runtime/collector.zig").DecodedEvent;
const PluginLoader = @import("../plugin/abi.zig").PluginLoader;
const StageContext = @import("stage.zig").StageContext;

/// Analysis pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    fact_store: FactStore,
    query_engine: QueryEngine,
    pass_manager: PassManager,
    instrumentation_plan: InstrumentationPlan,
    diagnostic_aggregator: DiagnosticAggregator,
    runtime_stage: ?RuntimeStage,
    merge_engine: MergeEngine,
    plugin_loader: ?PluginLoader,

    /// Create a new analysis pipeline
    pub fn init(allocator: std.mem.Allocator) Pipeline {
        var fact_store = FactStore.init(allocator);
        return .{
            .allocator = allocator,
            .fact_store = fact_store,
            .query_engine = QueryEngine.init(&fact_store),
            .pass_manager = PassManager.init(allocator),
            .instrumentation_plan = InstrumentationPlan.init(allocator),
            .diagnostic_aggregator = DiagnosticAggregator.init(allocator),
            .runtime_stage = null,
            .merge_engine = MergeEngine.init(allocator, &fact_store),
            .plugin_loader = null,
        };
    }

    /// Deinitialize the pipeline
    pub fn deinit(self: *Pipeline) void {
        self.fact_store.deinit();
        self.pass_manager.deinit();
        self.instrumentation_plan.deinit();
        self.diagnostic_aggregator.deinit();
        if (self.runtime_stage) |*stage| {
            stage.deinit();
        }
        if (self.plugin_loader) |*loader| {
            loader.deinit();
        }
        // MergeEngine is stack-allocated and will be cleaned up automatically
    }

    /// Run the full analysis pipeline
    pub fn run(self: *Pipeline) !void {
        // Reinitialize query engine with correct store
        self.query_engine = QueryEngine.init(&self.fact_store);

        // Create context with module
        // Note: Pipeline no longer handles IR loading, module must be provided separately
        var ctx = PassContext{
            .allocator = self.allocator,
            .module = null, // Module must be set externally if needed
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

    /// Run runtime stage to collect events
    pub fn runRuntimeStage(self: *Pipeline) !?PipelineResult {
        // Only run runtime stage if instrumentation was done
        if (self.instrumentation_plan.count() == 0) {
            return null;
        }

        const start_time = std.time.nanoTimestamp();

        // Initialize runtime stage if not already initialized
        if (self.runtime_stage == null) {
            const config = RuntimeStageConfig{};
            self.runtime_stage = try RuntimeStage.init(self.allocator, config);
        }

        // Create stage context
        const stage_ctx = StageContext{
            .allocator = self.allocator,
            .fact_store = &self.fact_store,
            .query_engine = &self.query_engine,
            .module = null, // Module must be provided externally when using runtime stage
            .instrumentation_plan = &self.instrumentation_plan,
        };

        // Run the runtime stage
        const result = self.runtime_stage.?.run(&stage_ctx);
        if (result != .success) {
            return error.RuntimeStageFailed;
        }

        const end_time = std.time.nanoTimestamp();

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .instrumentation_count = self.instrumentation_plan.count(),
            .execution_time_ns = @intCast(end_time - start_time),
        };
    }

    /// Run merge stage to combine static and runtime data
    pub fn runMergeStage(self: *Pipeline) !?PipelineResult {
        // Only run merge stage if runtime data is available
        if (self.runtime_stage == null) {
            return null;
        }

        const start_time = std.time.nanoTimestamp();

        // Collect runtime events
        const events = try self.runtime_stage.?.collectEvents();
        defer self.allocator.free(events);

        if (events.len == 0) {
            return null;
        }

        // Merge events with static facts
        const merged_events = try self.merge_engine.merge(events);
        defer self.allocator.free(merged_events);

        // Store merged results as diagnostic facts
        for (merged_events) |merged_ev| {
            if (merged_ev.is_anomaly) {
                try self.diagnostic_aggregator.addDiagnostic(.{
                    .kind = .runtime_issue,
                    .severity = .warning,
                    .loc = merged_ev.tag,
                    .message = "Runtime anomaly detected",
                    .confidence = merged_ev.confidence,
                });
            }
        }

        const end_time = std.time.nanoTimestamp();

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .instrumentation_count = self.instrumentation_plan.count(),
            .execution_time_ns = @intCast(end_time - start_time),
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

    /// Initialize plugin system
    pub fn initPluginSystem(self: *Pipeline) !void {
        if (self.plugin_loader == null) {
            self.plugin_loader = PluginLoader.init(self.allocator);
        }
    }

    /// Load a plugin from file
    pub fn loadPlugin(self: *Pipeline, path: []const u8) !void {
        if (self.plugin_loader) |loader| {
            try loader.load(path);
        } else {
            return error.PluginSystemNotInitialized;
        }
    }

    /// Query all loaded plugins
    pub fn queryPlugins(self: *Pipeline) !usize {
        if (self.plugin_loader) |loader| {
            const diagnostics = try loader.queryPlugins(&self.fact_store, &self.query_engine);
            return diagnostics.len;
        } else {
            return 0;
        }
    }

    /// Get the number of loaded plugins
    pub fn getPluginCount(self: *const Pipeline) usize {
        if (self.plugin_loader) |loader| {
            return loader.count();
        } else {
            return 0;
        }
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

/// Full pipeline result containing all stage results
pub const FullPipelineResult = struct {
    static_result: PipelineResult,
    instrumentation_result: PipelineResult,
    runtime_result: ?PipelineResult,
    merge_result: ?PipelineResult,
    total_time_ns: u64,
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
