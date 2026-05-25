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

    std.log.info("═══════════════════════════════════════════════════════════════", .{});
    std.log.info("Zone Classification Summary", .{});
    std.log.info("═══════════════════════════════════════════════════════════════", .{});

    std.log.info("  Total functions analyzed:    {d}", .{total});
    std.log.info("  Safe zone (skipped):         {d} ({d:.1}%)", .{ stats.safe_count, skip_ratio * 100 });
    std.log.info("  Runtime internal (skipped):  {d}", .{stats.runtime_count});
    std.log.info("  Unsafe zone (analyzed):      {d}", .{stats.unsafe_count});
    std.log.info("  FFI zone (analyzed):         {d}", .{stats.ffi_count});
    std.log.info("  Unknown zone:                {d}", .{stats.unknown_count});
    std.log.info("", .{});

    std.log.info("  Escape zone functions:       {d} ({d:.1}% of total)", .{ escape_count, if (total > 0) @as(f64, @floatFromInt(escape_count)) / @as(f64, @floatFromInt(total)) * 100 else 0 });

    if (issue_stats.total > 0) {
        std.log.info("  Issues found:              {d}", .{issue_stats.total});

        std.log.info("    Issue breakdown by category:", .{});
        if (issue_stats.memory_leak > 0) {
            std.log.info("      Memory leak:              {d}", .{issue_stats.memory_leak});
        }
        if (issue_stats.use_after_free > 0) {
            std.log.info("      Use after free:           {d}", .{issue_stats.use_after_free});
        }
        if (issue_stats.double_free > 0) {
            std.log.info("      Double free:               {d}", .{issue_stats.double_free});
        }
        if (issue_stats.ffi_unsafe > 0) {
            std.log.info("      FFI unsafe call:          {d}", .{issue_stats.ffi_unsafe});
        }
        if (issue_stats.command_injection > 0) {
            std.log.info("      Command injection:         {d}", .{issue_stats.command_injection});
        }
        if (issue_stats.buffer_overflow > 0) {
            std.log.info("      Buffer overflow:          {d}", .{issue_stats.buffer_overflow});
        }
        if (issue_stats.format_string > 0) {
            std.log.info("      Format string:            {d}", .{issue_stats.format_string});
        }
        if (issue_stats.type_mismatch > 0) {
            std.log.info("      Type mismatch:            {d}", .{issue_stats.type_mismatch});
        }
        if (issue_stats.borrow_escape > 0) {
            std.log.info("      Borrow escape:            {d}", .{issue_stats.borrow_escape});
        }
        if (issue_stats.null_dereference > 0) {
            std.log.info("      Null dereference:         {d}", .{issue_stats.null_dereference});
        }
        if (issue_stats.invalid_free > 0) {
            std.log.info("      Invalid free:             {d}", .{issue_stats.invalid_free});
        }
        if (issue_stats.unchecked_return > 0) {
            std.log.info("      Unchecked return:         {d}", .{issue_stats.unchecked_return});
        }
        if (issue_stats.malloc_unchecked > 0) {
            std.log.info("      Malloc unchecked:         {d}", .{issue_stats.malloc_unchecked});
        }
        if (issue_stats.callback_mismatch > 0) {
            std.log.info("      Callback mismatch:        {d}", .{issue_stats.callback_mismatch});
        }
        if (issue_stats.unknown > 0) {
            std.log.info("      Unknown:                  {d}", .{issue_stats.unknown});
        }

        std.log.info("", .{});
        std.log.info("    90/10 Priority Classification:", .{});
        std.log.info("      FFI Boundary (90% core):     {d}", .{ffi_issues});
        std.log.info("      Local Only (10% auxiliary):  {d}", .{local_issues});

        std.log.info("    Origin breakdown:", .{});
        std.log.info("      ✅ User code:             {d:>6} (ACTION NEEDED)", .{issue_stats.user_code});
        std.log.info("      📦 Third-party (FFI):     {d:>6}", .{issue_stats.third_party});
        std.log.info("      📚 Stdlib (suppressed):  {d:>6}", .{issue_stats.stdlib_suppressed});
        std.log.info("      🔧 Compiler (ignored):   {d:>6}", .{issue_stats.compiler_ignored});

        const actionable = issue_stats.user_code + issue_stats.third_party;
        if (actionable > 0) {
            std.log.info("    → {d} actionable issues ({d} user, {d} FFI boundary)", .{
                actionable,
                issue_stats.user_code,
                issue_stats.third_party,
            });
        }
        std.log.info("", .{});

        const graph_stats = dfg.getStats();
        const coverage_pct: f64 = if (graph_stats.node_count > 0)
            @as(f64, @floatFromInt(graph_stats.tainted_node_count)) / @as(f64, @floatFromInt(graph_stats.node_count)) * 100
        else
            0;
        std.log.info("    Graph coverage:", .{});
        std.log.info("      Total nodes analyzed:     {d}", .{graph_stats.node_count});
        std.log.info("      Nodes on danger path:     {d} ({d:.1}%)", .{ graph_stats.tainted_node_count, coverage_pct });
        std.log.info("      FFI boundaries tracked:   {d}", .{dfg.getFFIBoundaries().len});
        std.log.info("      Issues in graph:          {d}", .{dfg.getIssues().len});

        if (issue_stats.total > 0) {
            const depth_hint = if (coverage_pct > 50) "deep alias analysis" else if (coverage_pct > 20) "moderate reach" else "shallow scan";
            std.log.info("      Analysis depth:           {s}", .{depth_hint});
        }
    } else {
        std.log.info("  Issues found:                0", .{});
    }

    std.log.info("═══════════════════════════════════════════════════════════════", .{});
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

    var ctx = try PassContext.init(
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
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = try PassContext.init(
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
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
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

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    _ = ctx.fact_store;
    _ = ctx.query_engine;
    _ = ctx.allocator;
}

test "PassContext - getOrComputeZoneByName caching" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();
    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();
    var ctx = try PassContext.init(std.testing.allocator, null, &fact_store, &query_engine, &data_flow_graph);
    defer ctx.deinit();

    const llvm_zone = ctx.getOrComputeZoneByName("llvm.memcpy.p0i8.p0i8.i64");
    try std.testing.expectEqual(zone_classifier.ZoneKind.runtime_internal, llvm_zone);

    const llvm_zone2 = ctx.getOrComputeZoneByName("llvm.memcpy.p0i8.p0i8.i64");
    try std.testing.expectEqual(llvm_zone, llvm_zone2);

    const rust_zone = ctx.getOrComputeZoneByName("std::sync::Arc::new");
    try std.testing.expectEqual(zone_classifier.ZoneKind.safe, rust_zone);

    const unknown_zone = ctx.getOrComputeZoneByName("my_custom_function");
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
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();
    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();
    var ctx = try PassContext.init(std.testing.allocator, null, &fact_store, &query_engine, &data_flow_graph);
    defer ctx.deinit();

    var dummy: u8 = 0;
    const zone = ctx.getOrComputeZone(@ptrCast(&dummy), "dummy_func");
    _ = zone;
}
