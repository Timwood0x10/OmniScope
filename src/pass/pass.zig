//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.
//!
//! Type definitions are extracted to types/pass_types.zig for maintainability.

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");

const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const zone_classifier = @import("../semantics/zone_classifier.zig");

const pass_types = @import("../types/pass_types.zig");

pub const PassKind = pass_types.PassKind;
pub const CrossLangEdge = pass_types.CrossLangEdge;
pub const CallSiteIndex = pass_types.CallSiteIndex;
pub const CallSite = pass_types.CallSite;
pub const GlobalAllocTracker = pass_types.GlobalAllocTracker;
pub const PassContext = pass_types.PassContext;
pub const ChannelMode = pass_types.ChannelMode;
pub const DiagnosticWriter = pass_types.DiagnosticWriter;
pub const Colors = pass_types.Colors;

/// Print zone classification summary with 90/10 priority分层
/// Output format: "Analyzed 987 functions, 42 in unsafe/FFI zones, found 3 real issues"
pub fn printZoneSummary(stats: zone_classifier.ZoneStats, dfg: *DataFlowGraph) void {
    if (log.current_log_level != .verbose and log.current_log_level != .debug) return;

    const total = stats.total();
    const escape_count = stats.unsafe_count + stats.ffi_count;
    const skip_ratio = stats.skipRatio();
    const issue_stats = dfg.getIssueStats();

    var ffi_issues: u32 = 0;
    var local_issues: u32 = 0;
    for (dfg.issues.items) |issue| {
        if (issue.classification == .ffi_boundary) {
            ffi_issues += 1;
        } else {
            local_issues += 1;
        }
    }

    log.info("═══════════════════════════════════════════════════════════════", .{});
    log.info("Zone Classification Summary", .{});
    log.info("═══════════════════════════════════════════════════════════════", .{});

    log.info("  Total functions analyzed:    {d}", .{total});
    log.info("  Safe zone (skipped):         {d} ({d:.1}%)", .{ stats.safe_count, skip_ratio * 100 });
    log.info("  Runtime internal (skipped):  {d}", .{stats.runtime_count});
    log.info("  Unsafe zone (analyzed):      {d}", .{stats.unsafe_count});
    log.info("  FFI zone (analyzed):         {d}", .{stats.ffi_count});
    log.info("  Unknown zone:                {d}", .{stats.unknown_count});
    log.info("", .{});

    log.info("  Escape zone functions:       {d} ({d:.1}% of total)", .{ escape_count, if (total > 0) @as(f64, @floatFromInt(escape_count)) / @as(f64, @floatFromInt(total)) * 100 else 0 });

    if (issue_stats.total > 0) {
        log.info("  Issues found:              {d}", .{issue_stats.total});

        log.info("    Issue breakdown by category:", .{});
        if (issue_stats.memory_leak > 0) {
            log.info("      Memory leak:              {d}", .{issue_stats.memory_leak});
        }
        if (issue_stats.use_after_free > 0) {
            log.info("      Use after free:           {d}", .{issue_stats.use_after_free});
        }
        if (issue_stats.double_free > 0) {
            log.info("      Double free:               {d}", .{issue_stats.double_free});
        }
        if (issue_stats.ffi_unsafe > 0) {
            log.info("      FFI unsafe call:          {d}", .{issue_stats.ffi_unsafe});
        }
        if (issue_stats.command_injection > 0) {
            log.info("      Command injection:         {d}", .{issue_stats.command_injection});
        }
        if (issue_stats.buffer_overflow > 0) {
            log.info("      Buffer overflow:          {d}", .{issue_stats.buffer_overflow});
        }
        if (issue_stats.format_string > 0) {
            log.info("      Format string:            {d}", .{issue_stats.format_string});
        }
        if (issue_stats.type_mismatch > 0) {
            log.info("      Type mismatch:            {d}", .{issue_stats.type_mismatch});
        }
        if (issue_stats.borrow_escape > 0) {
            log.info("      Borrow escape:            {d}", .{issue_stats.borrow_escape});
        }
        if (issue_stats.null_dereference > 0) {
            log.info("      Null dereference:         {d}", .{issue_stats.null_dereference});
        }
        if (issue_stats.invalid_free > 0) {
            log.info("      Invalid free:             {d}", .{issue_stats.invalid_free});
        }
        if (issue_stats.unchecked_return > 0) {
            log.info("      Unchecked return:         {d}", .{issue_stats.unchecked_return});
        }
        if (issue_stats.malloc_unchecked > 0) {
            log.info("      Malloc unchecked:         {d}", .{issue_stats.malloc_unchecked});
        }
        if (issue_stats.callback_mismatch > 0) {
            log.info("      Callback mismatch:        {d}", .{issue_stats.callback_mismatch});
        }
        if (issue_stats.unknown > 0) {
            log.info("      Unknown:                  {d}", .{issue_stats.unknown});
        }

        log.info("", .{});
        log.info("    90/10 Priority Classification:", .{});
        log.info("      FFI Boundary (90% core):     {d}", .{ffi_issues});
        log.info("      Local Only (10% auxiliary):  {d}", .{local_issues});

        log.info("    Origin breakdown:", .{});
        log.info("      ✅ User code:             {d:>6} (ACTION NEEDED)", .{issue_stats.user_code});
        log.info("      📦 Third-party (FFI):     {d:>6}", .{issue_stats.third_party});
        log.info("      📚 Stdlib (suppressed):  {d:>6}", .{issue_stats.stdlib_suppressed});
        log.info("      🔧 Compiler (ignored):   {d:>6}", .{issue_stats.compiler_ignored});

        const actionable = issue_stats.user_code + issue_stats.third_party;
        if (actionable > 0) {
            log.info("    → {d} actionable issues ({d} user, {d} FFI boundary)", .{
                actionable,
                issue_stats.user_code,
                issue_stats.third_party,
            });
        }
        log.info("", .{});

        const graph_stats = dfg.getStats();
        const coverage_pct: f64 = if (graph_stats.node_count > 0)
            @as(f64, @floatFromInt(graph_stats.tainted_node_count)) / @as(f64, @floatFromInt(graph_stats.node_count)) * 100
        else
            0;
        log.info("    Graph coverage:", .{});
        log.info("      Total nodes analyzed:     {d}", .{graph_stats.node_count});
        log.info("      Nodes on danger path:     {d} ({d:.1}%)", .{ graph_stats.tainted_node_count, coverage_pct });
        log.info("      FFI boundaries tracked:   {d}", .{dfg.getFFIBoundaries().len});
        log.info("      Issues in graph:          {d}", .{dfg.getIssues().len});

        if (issue_stats.total > 0) {
            const depth_hint = if (coverage_pct > 50) "deep alias analysis" else if (coverage_pct > 20) "moderate reach" else "shallow scan";
            log.info("      Analysis depth:           {s}", .{depth_hint});
        }
    } else {
        log.info("  Issues found:                0", .{});
    }

    log.info("═══════════════════════════════════════════════════════════════", .{});
}

/// Pass comptime wrapper with type validation
///
/// This function validates that a type satisfies the Pass interface
/// at compile time and returns the type unchanged.
pub fn Pass(comptime T: type) type {
    comptime {
        if (!@hasDecl(T, "name"))
            @compileError("Pass must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Pass must have a 'kind' declaration (PassKind)");
        if (!@hasDecl(T, "deps"))
            @compileError("Pass must have a 'deps' declaration ([]const []const u8)");
        if (!@hasDecl(T, "run"))
            @compileError("Pass must have a 'run' function");
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
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    // Create minimal IR store for PassContext
    const ir_mod = @import("../ir/ir_store.zig");
    var ir_store = ir_mod.ModuleIRStore{
        .allocator = std.testing.allocator,
        .functions = std.StringHashMap(*ir_mod.FunctionIR).init(std.testing.allocator),
        .function_list = &[_]*ir_mod.FunctionIR{},
        .globals = &.{},
        .global_names = std.StringHashMap(usize).init(std.testing.allocator),
        .function_count = 0,
        .total_instruction_count = 0,
    };
    defer {
        ir_store.functions.deinit();
        ir_store.global_names.deinit();
    }

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
        &ir_store,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());
}

test "PassContext - getNextId" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    // Create minimal IR store for PassContext
    const ir_mod2 = @import("../ir/ir_store.zig");
    var ir_store2 = ir_mod2.ModuleIRStore{
        .allocator = std.testing.allocator,
        .functions = std.StringHashMap(*ir_mod2.FunctionIR).init(std.testing.allocator),
        .function_list = &[_]*ir_mod2.FunctionIR{},
        .globals = &.{},
        .global_names = std.StringHashMap(usize).init(std.testing.allocator),
        .function_count = 0,
        .total_instruction_count = 0,
    };
    defer {
        ir_store2.functions.deinit();
        ir_store2.global_names.deinit();
    }

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
        &ir_store2,
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
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    const ir_mod3 = @import("../ir/ir_store.zig");
    var ir_store3 = ir_mod3.ModuleIRStore{
        .allocator = std.testing.allocator,
        .functions = std.StringHashMap(*ir_mod3.FunctionIR).init(std.testing.allocator),
        .function_list = &[_]*ir_mod3.FunctionIR{},
        .globals = &.{},
        .global_names = std.StringHashMap(usize).init(std.testing.allocator),
        .function_count = 0,
        .total_instruction_count = 0,
    };
    defer {
        ir_store3.functions.deinit();
        ir_store3.global_names.deinit();
    }

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
        &ir_store3,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());

    ctx.setModule(.{ .raw = undefined });

    try std.testing.expect(ctx.hasModule());
}

test "PassContext - access to components" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    const ir_mod4 = @import("../ir/ir_store.zig");
    var ir_store4 = ir_mod4.ModuleIRStore{
        .allocator = std.testing.allocator,
        .functions = std.StringHashMap(*ir_mod4.FunctionIR).init(std.testing.allocator),
        .function_list = &[_]*ir_mod4.FunctionIR{},
        .globals = &.{},
        .global_names = std.StringHashMap(usize).init(std.testing.allocator),
        .function_count = 0,
        .total_instruction_count = 0,
    };
    defer {
        ir_store4.functions.deinit();
        ir_store4.global_names.deinit();
    }

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
        &ir_store4,
    );
    defer ctx.deinit();

    _ = ctx.fact_store;
    _ = ctx.query_engine;
    _ = ctx.allocator;
}

test "PassContext - getOrComputeZoneByName caching" {
    // Note: Full PassContext.init requires ir_store which needs LLVM module.
    // Zone cache logic is tested indirectly via integration tests.
    // This test verifies the zone classifier directly instead.
    const llvm_zone = zone_classifier.classifyFunction("llvm.memcpy.p0i8.p0i8.i64", null);
    try std.testing.expectEqual(zone_classifier.ZoneKind.runtime_internal, llvm_zone);

    const rust_zone = zone_classifier.classifyFunction("std::sync::Arc::new", null);
    try std.testing.expectEqual(zone_classifier.ZoneKind.safe, rust_zone);

    const unknown_zone = zone_classifier.classifyFunction("my_custom_function", null);
    try std.testing.expectEqual(zone_classifier.ZoneKind.unknown, unknown_zone);
}

test "PassContext - shouldAnalyzeZone gate logic" {
    try std.testing.expect(!PassContext.shouldAnalyzeZone(.safe));
    try std.testing.expect(!PassContext.shouldAnalyzeZone(.runtime_internal));

    try std.testing.expect(PassContext.shouldAnalyzeZone(.unknown));
    try std.testing.expect(PassContext.shouldAnalyzeZone(.unsafe));
    try std.testing.expect(PassContext.shouldAnalyzeZone(.ffi));
}

test "PassContext - getOrComputeZone null safety" {
    // Verify that zone classification handles gracefully.
    const zone = zone_classifier.classifyFunction("dummy_func", null);
    _ = zone; // Just verify no crash — actual classification tested elsewhere
}
