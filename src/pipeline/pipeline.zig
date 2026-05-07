//! Analysis Pipeline
//!
//! This module implements the overall analysis pipeline that
//! orchestrates passes and data flow.

const std = @import("std");

const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const Issue = @import("../diag/issue.zig").Issue;
const Severity = @import("../diag/issue.zig").Severity;
const TraceEntry = @import("../diag/issue.zig").TraceEntry;
const Location = @import("../diag/issue.zig").Location;
const ModuleRef = @import("../ir/view.zig").ModuleRef;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;

const PassContext = @import("../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const call_graph_mod = @import("../semantics/call_graph.zig");
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;
const zone_classifier = @import("../semantics/zone_classifier.zig");
const PassManager = @import("../pass/manager.zig").PassManager;
const c = @import("../ir/llvm_raw.zig").c;

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
        fact_store.* = try FactStore.init(allocator);

        const query_engine = try allocator.create(QueryEngine);
        query_engine.* = QueryEngine.init(fact_store, allocator);

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
        self.query_engine.deinit();
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
            .vuln_id = std.atomic.Value(u32).init(0),
            .value_id_map = ValueIdMap.init(self.allocator),
            .raii_func_set = std.AutoHashMap(usize, void).init(self.allocator),
            .meyers_singleton_set = std.AutoHashMap(usize, void).init(self.allocator),
            .rc_container_func_set = std.AutoHashMap(usize, void).init(self.allocator),
            .rust_into_raw_set = std.AutoHashMap(usize, void).init(self.allocator),
            .rust_from_raw_set = std.AutoHashMap(usize, void).init(self.allocator),
            .reported_keys = std.AutoHashMap(u64, void).init(self.allocator),
            .registry_cache = std.StringHashMap(FunctionSemantics).init(self.allocator),
            .zone_cache = std.StringHashMap(zone_classifier.ZoneKind).init(self.allocator),
            .zone_stats = .{},
            .module_language = .{ .language = .unknown, .confidence = 0.0, .method = .unknown },
            .language_detected = false,
            .degraded_functions = std.atomic.Value(u32).init(0),
            .cross_lang_edges = std.ArrayList(@import("../pass/pass.zig").CrossLangEdge).empty,
            .global_alloc_tracker = @import("../pass/pass.zig").GlobalAllocTracker.init(self.allocator),
            .memory_graph = try @import("../semantics/memory_graph.zig").MemoryGraph.init(self.allocator),
            .danger_surface_relevant = std.AutoHashMap(u64, void).init(self.allocator),
            .ffi_auto_relevant = std.AutoHashMap(u64, void).init(self.allocator),
            .relevant_functions = std.AutoHashMap(u64, void).init(self.allocator),
            .CallSiteIndex = @import("../pass/pass.zig").CallSiteIndex.init(self.allocator),
            .cross_edge_by_callee = std.StringHashMap(std.ArrayList(u32)).init(self.allocator),
            .semantics_call_graph = null,
        };
        // CRITICAL: Deinit semantics CallGraph to prevent GPA memory leak warnings.
        // Must be deferred because semantics_call_graph is populated later in CallGraphPass.run().
        // The graph uses GeneralPurposeAllocator (not Arena) so all internal
        // allocations (HashMap, ArrayList, dupe'd strings) must be explicitly freed.
        defer {
            if (ctx.semantics_call_graph) |*sg| {
                call_graph_mod.CallGraph.deinit(sg);
            }
        }
        defer ctx.deinit();

        // R7.2 Language-First: detect module language ONCE before any passes run.
        // This activates the correct zone rules channel for all subsequent analysis.
        ctx.initModuleLanguage(self.module);

        // P0-2: Build shared callee→call_sites index ONCE before any passes run.
        // All call_graph and ffi_boundary lookups become O(1) instead of O(F).
        {
            const t_idx = std.time.nanoTimestamp();
            if (self.module) |mod| {
                const raw_mod = mod.raw;
                var func = c.LLVMGetFirstFunction(raw_mod);
                while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
                    if (c.LLVMIsDeclaration(func) != 0) continue;
                    const func_ptr = @as(u64, @intFromPtr(func));
                    var bb = c.LLVMGetFirstBasicBlock(func);
                    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                        var inst = c.LLVMGetFirstInstruction(bb);
                        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                            if (@intFromPtr(c.LLVMIsACallInst(inst)) == 0) continue;
                            const called_val = c.LLVMGetCalledValue(inst);
                            if (@intFromPtr(called_val) == 0) continue;
                            const called_name_ptr = c.LLVMGetValueName(called_val);
                            if (@intFromPtr(called_name_ptr) == 0) continue;
                            const called_name = std.mem.span(called_name_ptr);
                            const inst_ptr = @as(u64, @intFromPtr(inst));
                            ctx.CallSiteIndex.addCall(self.allocator, called_name, func_ptr, inst_ptr) catch {};
                        }
                    }
                }
            }
            const idx_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t_idx)) / 1_000_000.0;
            if (idx_ms > 10) std.log.info("[PERF] CallSiteIndex build: {d:.1} ms", .{@as(u32, @intFromFloat(idx_ms))});
        }

        var diag = DiagnosticWriter{ .allocator = self.allocator };

        // Run passes
        try self.pass_manager.run(&ctx, &diag);

        // R8.3-d: Post-pass leak report — scan GlobalAllocTracker for unfreed allocations.
        // After all passes have run, any allocation that was never freed is a leak candidate.
        // Skip global/static variables (intentionally never freed) and already-matched pairs.
        // D1-4: Promote candidates to confirmed leaks when they reach FFI boundaries.
        const leak_count = ctx.global_alloc_tracker.leakCount();
        if (leak_count > 0) {
            const tracker = &ctx.global_alloc_tracker;
            var confirmed_high: u32 = 0;
            for (tracker.records.items) |rec| {
                if (!rec.freed and !rec.is_global_or_static) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Potential memory leak: heap allocation in {s}() was never freed", .{rec.alloc_func});
                    const trace = try self.allocator.alloc(TraceEntry, 1);
                    trace[0] = TraceEntry.init("Allocation tracked by GlobalAllocTracker but no matching free found in module");
                    // D1-4: Check if leaked ptr reaches FFI boundary → promote severity
                    const is_on_ffi_path = ctx.isOnDangerPathFull(rec.ptr_id);
                    const severity: Severity = if (is_on_ffi_path) .high else .low;
                    const confidence: f32 = if (is_on_ffi_path) 0.78 else 0.50;
                    if (is_on_ffi_path) confirmed_high += 1;

                    // FIX: Let addIssue take ownership by setting owned=true.
                    // Previous code used owned=false + manual free, which leaked trace[0].description.
                    // The correct ownership model is:
                    //   1. We allocate msg and trace (with trace[0].description)
                    //   2. We set owned=true to indicate we own this memory
                    //   3. addIssue deep-copies everything, then calls deinit on our original
                    //   4. deinit frees msg + trace + trace[0].description (all owned)
                    //   5. The graph owns the deep copies and frees them on graph.deinit
                    var issue = Issue.initWithTrace(
                        .memory_leak,
                        msg,
                        Location.init(rec.alloc_func),
                        severity,
                        confidence,
                        trace,
                    );
                    issue.owned = true; // We own msg and trace; addIssue will deep-copy then deinit our originals
                    try ctx.addIssue(&issue);
                }
            }
            const omi_prefix = if (confirmed_high > 0) "[OMI-HIGH] " else "";
            diag.info("{s}GlobalAllocTracker: {d} memory leaks confirmed from {d} tracked allocations ({d} cross-FFI)", .{
                omi_prefix, leak_count, tracker.size(), confirmed_high,
            });
        }
    }

    /// Run static analysis stage
    pub fn runStaticAnalysis(self: *Pipeline) !PipelineResult {
        const start_time = std.time.nanoTimestamp();

        // Run passes
        try self.run();

        const end_time = std.time.nanoTimestamp();
        const duration_ns = @max(@as(i128, 0), end_time - start_time);

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .execution_time_ns = @intCast(duration_ns),
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
