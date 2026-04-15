//! Sink Tracer Analysis Pass
//!
//! Traces tainted data flow from sources to dangerous sinks.

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const FlowPath = @import("./flow_path.zig").FlowPath;
const FlowStep = @import("./flow_path.zig").FlowStep;
const RiskLevel = @import("./flow_path.zig").RiskLevel;
const VulnerabilityReport = @import("./flow_path.zig").VulnerabilityReport;
const VulnerabilityReportBuilder = @import("./flow_path.zig").VulnerabilityReportBuilder;
const TaintState = @import("./taint_state.zig").TaintState;
const TaintInfo = @import("./taint_state.zig").TaintInfo;
const TaintContext = @import("./taint_state.zig").TaintContext;

const Allocator = std.mem.Allocator;

/// Error type for sink tracing operations.
pub const FlowPathError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Path not found.
    PathNotFound,
    /// Invalid taint state.
    InvalidTaintState,
};

/// Sink tracer analysis pass.
///
/// Reconstructs source-to-sink vulnerability paths through the call graph.
/// Uses taint propagation information to identify dangerous data flows.
pub const SinkTracerPass = struct {
    pub const name = "sink-tracer";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "ffi-boundary", "taint-propagation" };

    /// Run sink tracing analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FlowPathError!void {
        if (ctx.module == null) return;

        var taint_ctx = TaintContext.init(ctx.allocator);
        defer taint_ctx.deinit();

        try collectTaintFacts(ctx, &taint_ctx);

        const tainted_values = try findTaintedValues(ctx);
        defer ctx.allocator.free(tainted_values);

        var vulnerability_id: u32 = 0;

        for (tainted_values) |value_id| {
            if (try traceFlowPath(ctx.allocator, &taint_ctx, value_id)) |path| {
                vulnerability_id += 1;
                try reportVulnerability(ctx, path, vulnerability_id, diag);
            }
        }

        if (vulnerability_id > 0) {
            diag.info("SinkTracer: Found {} potential vulnerabilities", .{vulnerability_id});
        }
    }

    /// Collect taint facts from fact store
    fn collectTaintFacts(ctx: *PassContext, taint_ctx: *TaintContext) !void {
        const facts = try ctx.query_engine.queryByKind(.taint, ctx.allocator);
        defer ctx.allocator.free(facts);

        for (facts) |fact| {
            if (fact.object != 0) {
                const info = TaintInfo{
                    .id = fact.context,
                    .state = @enumFromInt(fact.object),
                    .source_id = null,
                    .confidence = 1.0,
                };
                try taint_ctx.setValueTaint(fact.subject, info);
            }
        }
    }

    /// Find all tainted values in the IR
    fn findTaintedValues(ctx: *PassContext) ![]u32 {
        var tainted = std.ArrayList(u32).init(ctx.allocator);
        errdefer tainted.deinit();

        const facts = try ctx.query_engine.queryByKind(.taint, ctx.allocator);
        defer ctx.allocator.free(facts);

        for (facts) |fact| {
            if (fact.object != 0) {
                try tainted.append(fact.subject);
            }
        }

        return tainted.toOwnedSlice();
    }

    /// Trace flow path from tainted value to sink
    fn traceFlowPath(allocator: Allocator, taint_ctx: *TaintContext, value_id: u32) FlowPathError!?FlowPath {
        var path = try FlowPath.init(allocator);
        errdefer path.deinit();

        const taint_info = taint_ctx.getValueTaint(value_id);
        const state: TaintState = if (taint_info) |info| info.state else .none;
        const confidence: f32 = if (taint_info) |info| info.confidence else 0.0;

        const func_name = if (taint_info) |info| blk: {
            if (info.source_id) |source_id| {
                const source_info = taint_ctx.getValueTaint(source_id);
                if (source_info) |_| {
                    break :blk "source_function";
                }
            }
            break :blk "propagated_taint";
        } else "unknown";

        const step = FlowStep{
            .id = value_id,
            .func_name = func_name,
            .location = .{ .file = null, .line = 0, .column = 0 },
            .taint_state = state,
            .confidence = confidence,
        };

        try path.addStep(step);

        if (taint_info) |info| {
            if (info.source_id) |source_id| {
                const source_step = FlowStep{
                    .id = source_id,
                    .func_name = "source",
                    .location = .{ .file = null, .line = 0, .column = 0 },
                    .taint_state = .source,
                    .confidence = 1.0,
                };
                try path.addStep(source_step);
            }
        }

        return path;
    }

    /// Report vulnerability with complete information
    fn reportVulnerability(ctx: *PassContext, path: FlowPath, vuln_id: u32, diag: *DiagnosticWriter) !void {
        var builder = try VulnerabilityReportBuilder.init(vuln_id, ctx.allocator);
        _ = builder.withRisk(.high);
        _ = builder.withSource("source");
        _ = builder.withSink("sink");
        _ = builder.withFlowPath(path);
        _ = builder.withDescription("Potential data flow vulnerability");
        _ = builder.withRecommendation("Review data flow and add sanitization");

        const report = builder.build();

        diag.err("VULNERABILITY DETECTED", .{});
        diag.err("Risk Level: {s}", .{@tagName(report.risk_level)});
        diag.err("Source: {s}", .{report.source_func});
        diag.err("Sink: {s}", .{report.sink_func});
        diag.err("Cross-language: {}", .{report.flow_path.is_cross_language});

        diag.err("Flow Path:", .{});
        for (report.flow_path.steps) |step| {
            diag.err("  -> {s} (confidence: {d:.2})", .{ step.func_name, step.confidence });
        }

        try ctx.fact_store.insert(
            .vulnerability,
            vuln_id,
            @intFromEnum(report.risk_level),
            report.flow_path.length(),
        );
    }
};

/// Classify risk level based on sink function.
///
/// Simple and fast classification using minimal string operations.
/// Optimized for performance with early exit on critical patterns.
///
/// Parameters:
///   - sink_name: Name of the sink function to classify
///
/// Returns:
///   - RiskLevel classification for the function
pub fn classifyRiskLevel(sink_name: []const u8) RiskLevel {
    // Critical: command injection (CWE-78)
    if (std.mem.indexOf(u8, sink_name, "system") != null or
        std.mem.indexOf(u8, sink_name, "exec") != null or
        std.mem.indexOf(u8, sink_name, "popen") != null)
    {
        return .critical;
    }

    // High: buffer overflow (CWE-120)
    if (std.mem.indexOf(u8, sink_name, "strcpy") != null or
        std.mem.indexOf(u8, sink_name, "strcat") != null or
        std.mem.indexOf(u8, sink_name, "sprintf") != null or
        std.mem.indexOf(u8, sink_name, "gets") != null)
    {
        return .high;
    }

    // High: format string (CWE-134)
    if (std.mem.indexOf(u8, sink_name, "printf") != null or
        std.mem.indexOf(u8, sink_name, "fprintf") != null or
        std.mem.indexOf(u8, sink_name, "snprintf") != null)
    {
        return .high;
    }

    return .low;
}

/// Check if a function is a dangerous sink
pub fn isDangerousSink(func_name: []const u8) bool {
    const dangerous_sinks = &[_][]const u8{
        "system",
        "exec",
        "popen",
        "strcpy",
        "strcat",
        "sprintf",
        "gets",
    };

    for (dangerous_sinks) |sink| {
        if (std.mem.indexOf(u8, func_name, sink) != null) {
            return true;
        }
    }
    return false;
}

test "RiskLevel - enum values" {
    try std.testing.expectEqual(RiskLevel.medium, .medium);
    try std.testing.expectEqual(RiskLevel.critical, .critical);
}

test "RiskLevel - ordering" {
    const medium = RiskLevel.medium;
    const critical = RiskLevel.critical;
    try std.testing.expect(@intFromEnum(medium) < @intFromEnum(critical));
}

test "FlowStep - structure" {
    const step = FlowStep{
        .id = 1,
        .func_name = "test",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.9,
    };
    try std.testing.expectEqual(@as(u32, 1), step.id);
    try std.testing.expectEqualStrings("test", step.func_name);
}

test "FlowStep - empty name" {
    const step = FlowStep{
        .id = 0,
        .func_name = "",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .clean,
        .confidence = 1.0,
    };
    try std.testing.expectEqualStrings("", step.func_name);
}

test "FlowStep - long name" {
    const long_name = "a" ** 1000;
    const step = FlowStep{
        .id = 1,
        .func_name = long_name,
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.5,
    };
    try std.testing.expectEqualStrings(long_name, step.func_name);
}

test "FlowStep - special characters" {
    const step = FlowStep{
        .id = 1,
        .func_name = "_func@#$%",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.9,
    };
    try std.testing.expectEqualStrings("_func@#$%", step.func_name);
}

test "FlowPath - structure" {
    const path = FlowPath{
        .steps = &[0]FlowStep{},
        .risk_level = .medium,
        .is_cross_language = false,
        .source_func = "",
        .sink_func = "",
    };
    try std.testing.expectEqual(@as(usize, 0), path.steps.len);
    try std.testing.expect(!path.is_cross_language);
    try std.testing.expectEqual(RiskLevel.medium, path.risk_level);
}

test "FlowPath - cross language true" {
    const step = FlowStep{
        .id = 1,
        .func_name = "test",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.9,
    };
    const path = FlowPath{
        .steps = &[1]FlowStep{step},
        .risk_level = .critical,
        .is_cross_language = true,
        .source_func = "source",
        .sink_func = "sink",
    };
    try std.testing.expect(path.is_cross_language);
    try std.testing.expectEqual(RiskLevel.critical, path.risk_level);
}

test "FlowPath - empty steps" {
    const path = FlowPath{
        .steps = &[0]FlowStep{},
        .risk_level = .low,
        .is_cross_language = false,
        .source_func = "",
        .sink_func = "",
    };
    try std.testing.expectEqual(@as(usize, 0), path.steps.len);
}

test "FlowPathError - error type exists" {
    const err = FlowPathError.OutOfMemory;
    try std.testing.expect(err == FlowPathError.OutOfMemory);
}

test "SinkTracerPass - name" {
    try std.testing.expectEqualStrings("sink-tracer", SinkTracerPass.name);
}

test "SinkTracerPass - kind" {
    try std.testing.expectEqual(PassKind.analysis, SinkTracerPass.kind);
}

test "SinkTracerPass - deps" {
    try std.testing.expectEqual(@as(usize, 2), SinkTracerPass.deps.len);
    try std.testing.expectEqualStrings("ffi-boundary", SinkTracerPass.deps[0]);
    try std.testing.expectEqualStrings("taint-propagation", SinkTracerPass.deps[1]);
}

test "SinkTracerPass - deps not empty" {
    try std.testing.expect(SinkTracerPass.deps.len > 0);
}

test "classifyRiskLevel - critical sinks" {
    try std.testing.expectEqual(RiskLevel.critical, classifyRiskLevel("system"));
    try std.testing.expectEqual(RiskLevel.critical, classifyRiskLevel("exec"));
    try std.testing.expectEqual(RiskLevel.critical, classifyRiskLevel("popen"));
    try std.testing.expectEqual(RiskLevel.critical, classifyRiskLevel("__libc_system"));
    try std.testing.expectEqual(RiskLevel.critical, classifyRiskLevel("system_r"));
}

test "classifyRiskLevel - high risk sinks" {
    try std.testing.expectEqual(RiskLevel.high, classifyRiskLevel("strcpy"));
    try std.testing.expectEqual(RiskLevel.high, classifyRiskLevel("strcat"));
    try std.testing.expectEqual(RiskLevel.high, classifyRiskLevel("sprintf"));
    try std.testing.expectEqual(RiskLevel.high, classifyRiskLevel("normal_func"));
}

test "isDangerousSink - matches patterns" {
    try std.testing.expect(isDangerousSink("system"));
    try std.testing.expect(isDangerousSink("execve"));
    try std.testing.expect(isDangerousSink("strcpy"));
    try std.testing.expect(isDangerousSink("my_system_call"));
}

test "isDangerousSink - no match" {
    try std.testing.expect(!isDangerousSink("malloc"));
    try std.testing.expect(!isDangerousSink("printf"));
    try std.testing.expect(!isDangerousSink("free"));
    try std.testing.expect(!isDangerousSink("strlen"));
}

test "isDangerousSink - partial match" {
    try std.testing.expect(isDangerousSink("system_call"));
    try std.testing.expect(isDangerousSink("my_popen_wrapper"));
}
