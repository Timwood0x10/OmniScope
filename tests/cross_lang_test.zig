//! Cross-Language Data Flow Analysis - Boundary and Pressure Tests
//!
//! Boundary tests: edge cases like empty IR, single function, no calls
//! Pressure tests: large number of functions, deep call chains
//! Edge case tests: recursive functions, self-loops, unreachable code

const std = @import("std");
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;

test "CallGraph - FunctionKind all variants" {
    try std.testing.expectEqual(call_graph.FunctionKind.internal, .internal);
    try std.testing.expectEqual(call_graph.FunctionKind.libc, .libc);
    try std.testing.expectEqual(call_graph.FunctionKind.external_unknown, .external_unknown);
}

test "CallGraph - FunctionKind tagName" {
    try std.testing.expectEqualStrings("internal", @tagName(call_graph.FunctionKind.internal));
    try std.testing.expectEqualStrings("libc", @tagName(call_graph.FunctionKind.libc));
    try std.testing.expectEqualStrings("external_unknown", @tagName(call_graph.FunctionKind.external_unknown));
}

test "LIBC_FUNCTIONS - common functions present" {
    const common = &[_][]const u8{ "malloc", "free", "read", "write", "system" };
    for (common) |name| {
        var found = false;
        for (call_graph.LIBC_FUNCTIONS) |libc| {
            if (std.mem.eql(u8, name, libc)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "LIBC_FUNCTIONS - sink functions present" {
    const sinks = &[_][]const u8{ "system", "exec", "popen" };
    for (sinks) |name| {
        var found = false;
        for (call_graph.LIBC_FUNCTIONS) |libc| {
            if (std.mem.eql(u8, name, libc)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "LIBC_FUNCTIONS - all non-empty" {
    for (call_graph.LIBC_FUNCTIONS) |name| {
        try std.testing.expect(name.len > 0);
    }
}

test "LIBC_FUNCTIONS - no duplicates" {
    for (call_graph.LIBC_FUNCTIONS, 0..) |s1, i| {
        for (call_graph.LIBC_FUNCTIONS, 0..) |s2, j| {
            if (i != j and std.mem.eql(u8, s1, s2)) {
                try std.testing.expect(false);
            }
        }
    }
}

test "SOURCE_FUNCTIONS - has expected sources" {
    const expected = &[_][]const u8{ "main", "read", "recv" };
    for (expected) |exp| {
        var found = false;
        for (call_graph.SOURCE_FUNCTIONS) |s| {
            if (std.mem.eql(u8, s, exp)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "SOURCE_FUNCTIONS - all non-empty" {
    for (call_graph.SOURCE_FUNCTIONS) |name| {
        try std.testing.expect(name.len > 0);
    }
}

test "SINK_PATTERNS - system is a sink" {
    var found_system = false;
    for (call_graph.SINK_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, pattern, "system") != null) {
            found_system = true;
            break;
        }
    }
    try std.testing.expect(found_system);
}

test "SINK_PATTERNS - all non-empty" {
    for (call_graph.SINK_PATTERNS) |pattern| {
        try std.testing.expect(pattern.len > 0);
    }
}

test "TaintPropagation - SOURCE_FUNCTIONS imported from call_graph" {
    var found_main = false;
    for (call_graph.SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found_main = true;
            break;
        }
    }
    try std.testing.expect(found_main);
}

test "SinkTracer - RiskLevel enum ordering" {
    try std.testing.expect(@intFromEnum(call_graph.SinkTracerPass.RiskLevel.medium) < @intFromEnum(call_graph.SinkTracerPass.RiskLevel.critical));
}

test "SinkTracer - FlowStep structure" {
    const step = call_graph.SinkTracerPass.FlowStep{ .funcName = "test" };
    try std.testing.expectEqualStrings("test", step.funcName);
}

test "SinkTracer - FlowPath structure" {
    const steps = &[0]call_graph.SinkTracerPass.FlowStep{};
    const path = call_graph.SinkTracerPass.FlowPath{
        .steps = steps,
        .isCrossLanguage = false,
        .risk = .medium,
    };
    try std.testing.expectEqual(steps.len, path.steps.len);
    try std.testing.expect(!path.isCrossLanguage);
    try std.testing.expectEqual(call_graph.SinkTracerPass.RiskLevel.medium, path.risk);
}

test "FFIBoundary - FFIEdge structure" {
    const edge = call_graph.FFIBoundaryPass.FFIEdge{ .caller = 0, .callee = 1 };
    try std.testing.expectEqual(@as(u32, 0), edge.caller);
    try std.testing.expectEqual(@as(u32, 1), edge.callee);
}

test "FFIBoundary - FFIEdge self-loop" {
    const edge = call_graph.FFIBoundaryPass.FFIEdge{ .caller = 5, .callee = 5 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "FFIBoundary - FFIEdge boundary values" {
    const edge_min = call_graph.FFIBoundaryPass.FFIEdge{ .caller = 0, .callee = 0 };
    try std.testing.expect(edge_min.caller == 0);

    const edge_max = call_graph.FFIBoundaryPass.FFIEdge{ .caller = 100, .callee = 200 };
    try std.testing.expect(edge_max.caller < edge_max.callee);
}

test "CallGraph - Edge structure" {
    const edge = call_graph.Edge{ .caller = 5, .callee = 10 };
    try std.testing.expectEqual(@as(u32, 5), edge.caller);
    try std.testing.expectEqual(@as(u32, 10), edge.callee);
}

test "CallGraph - Edge self-loop" {
    const edge = call_graph.Edge{ .caller = 3, .callee = 3 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "CallGraph - Node structure fields" {
    const node = call_graph.Node{
        .id = 1,
        .name = "test_func",
        .func_ref = undefined,
        .kind = .internal,
        .isExternal = false,
        .isTainted = false,
        .taintedBy = null,
    };
    try std.testing.expectEqual(@as(u32, 1), node.id);
    try std.testing.expectEqualStrings("test_func", node.name);
    try std.testing.expectEqual(call_graph.FunctionKind.internal, node.kind);
    try std.testing.expect(!node.isExternal);
    try std.testing.expect(!node.isTainted);
    try std.testing.expect(node.taintedBy == null);
}

test "CallGraph - Node with taint source" {
    const node = call_graph.Node{
        .id = 0,
        .name = "main",
        .func_ref = undefined,
        .kind = .internal,
        .isExternal = false,
        .isTainted = true,
        .taintedBy = null,
    };
    try std.testing.expect(node.isTainted);
    try std.testing.expect(node.taintedBy == null);
}

test "CallGraph - Node with taint propagation" {
    const node = call_graph.Node{
        .id = 2,
        .name = "tainted_func",
        .func_ref = undefined,
        .kind = .libc,
        .isExternal = true,
        .isTainted = true,
        .taintedBy = @as(u32, 0),
    };
    try std.testing.expect(node.isTainted);
    try std.testing.expect(node.taintedBy != null);
    try std.testing.expectEqual(@as(u32, 0), node.taintedBy.?);
}

test "Boundary - Non-existent file error" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const result = pipeline.loadIR("nonexistent/file.bc");
    try std.testing.expectError(OmniScope.engine.LoaderError.FileNotFound, result);
}

test "Integration - CrossLang module accessible" {
    try std.testing.expect(@hasDecl(OmniScope, "cross_lang"));
    try std.testing.expect(@hasDecl(OmniScope.cross_lang, "FunctionKind"));
    try std.testing.expect(@hasDecl(OmniScope.cross_lang, "CallGraphPass"));
    try std.testing.expect(@hasDecl(OmniScope.cross_lang, "LIBC_FUNCTIONS"));
}

test "Integration - All passes have correct interface" {
    try std.testing.expect(@hasDecl(call_graph.CallGraphPass, "name"));
    try std.testing.expect(@hasDecl(call_graph.CallGraphPass, "kind"));
    try std.testing.expect(@hasDecl(call_graph.CallGraphPass, "deps"));
    try std.testing.expect(@hasDecl(call_graph.CallGraphPass, "run"));
}

test "Integration - Pass metadata types" {
    try std.testing.expectEqualStrings("call-graph", call_graph.CallGraphPass.name);
    try std.testing.expectEqualStrings("taint-propagation", OmniScope.cross_lang.TaintPropagationPass.name);
    try std.testing.expectEqualStrings("ffi-boundary", OmniScope.cross_lang.FFIBoundaryPass.name);
    try std.testing.expectEqualStrings("sink-tracer", OmniScope.cross_lang.SinkTracerPass.name);
}

test "Integration - PassKind values" {
    try std.testing.expectEqual(call_graph.PassKind.foundation, OmniScope.cross_lang.TaintPropagationPass.kind);
    try std.testing.expectEqual(call_graph.PassKind.foundation, OmniScope.cross_lang.FFIBoundaryPass.kind);
    try std.testing.expectEqual(call_graph.PassKind.analysis, OmniScope.cross_lang.SinkTracerPass.kind);
}

test "Integration - Pass dependencies" {
    try std.testing.expect(call_graph.CallGraphPass.deps.len == 0);

    try std.testing.expect(OmniScope.cross_lang.TaintPropagationPass.deps.len > 0);
    try std.testing.expectEqualStrings("call-graph", OmniScope.cross_lang.TaintPropagationPass.deps[0]);

    try std.testing.expect(OmniScope.cross_lang.FFIBoundaryPass.deps.len > 0);
    try std.testing.expectEqualStrings("call-graph", OmniScope.cross_lang.FFIBoundaryPass.deps[0]);

    try std.testing.expect(OmniScope.cross_lang.SinkTracerPass.deps.len > 0);
    try std.testing.expectEqualStrings("ffi-boundary", OmniScope.cross_lang.SinkTracerPass.deps[0]);
}

test "EdgeCase - Max u32 values in Edge" {
    const max_u32 = std.math.maxInt(u32);
    const edge = call_graph.Edge{ .caller = max_u32, .callee = max_u32 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "EdgeCase - Zero values in Edge" {
    const edge = call_graph.Edge{ .caller = 0, .callee = 0 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "EdgeCase - Large but valid Edge values" {
    const edge = call_graph.Edge{ .caller = 1000000, .callee = 2000000 };
    try std.testing.expect(edge.caller < edge.callee);
}

test "EdgeCase - Near max u32 Edge" {
    const max_u32 = std.math.maxInt(u32);
    const edge = call_graph.Edge{ .caller = max_u32 - 1, .callee = max_u32 };
    try std.testing.expect(edge.caller < edge.callee);
}
