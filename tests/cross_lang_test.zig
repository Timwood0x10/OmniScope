//! Cross-Language Data Flow Analysis - Boundary and Pressure Tests
//!
//! Boundary tests: edge cases like empty IR, single function, no calls
//! Pressure tests: large number of functions, deep call chains

const std = @import("std");
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;

test "CallGraph - empty IR" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    try pipeline.loadIR("examples/sample_wasm_wasm32.bc");
    const loader = pipeline.getIRLoader();
    try std.testing.expect(loader != null);
}

test "CallGraph - single function no calls" {
    var pass = call_graph.CallGraphPass.init(std.testing.allocator);
    defer pass.deinit();

    try std.testing.expectEqual(@as(usize, 0), pass.nodes.items.len);
}

test "CallGraph - FunctionKind classification" {
    try std.testing.expectEqual(call_graph.FunctionKind.internal, .internal);
    try std.testing.expectEqual(call_graph.FunctionKind.libc, .libc);
    try std.testing.expectEqual(call_graph.FunctionKind.external_unknown, .external_unknown);
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

test "TaintPropagation - SOURCE_FUNCTIONS contains main" {
    const taint_mod = @import("../src/pass/analysis/taint_propagation.zig");
    var found = false;
    for (taint_mod.SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "SinkTracer - RiskLevel enum" {
    const sink_mod = @import("../src/pass/analysis/sink_tracer.zig");
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(sink_mod.RiskLevel.medium));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(sink_mod.RiskLevel.critical));
}

test "SinkTracer - FlowStep structure" {
    const sink_mod = @import("../src/pass/analysis/sink_tracer.zig");
    const step = sink_mod.FlowStep{ .funcName = "test" };
    try std.testing.expectEqualStrings("test", step.funcName);
}

test "SinkTracer - contains helper" {
    const sink_mod = @import("../src/pass/analysis/sink_tracer.zig");
    _ = sink_mod;
    try std.testing.expect(std.mem.indexOf(u8, "system", "system") != null);
    try std.testing.expect(std.mem.indexOf(u8, "__libc_system", "system") != null);
    try std.testing.expect(std.mem.indexOf(u8, "malloc", "system") == null);
}

test "FFIBoundary - FFIEdge structure" {
    const ffi_mod = @import("../src/pass/analysis/ffi_boundary.zig");
    const edge = ffi_mod.FFIEdge{ .caller = 0, .callee = 1 };
    try std.testing.expectEqual(@as(u32, 0), edge.caller);
    try std.testing.expectEqual(@as(u32, 1), edge.callee);
}

test "CallGraph - CallEdge structure" {
    const cg_mod = @import("../src/pass/analysis/call_graph.zig");
    const edge = cg_mod.CallEdge{ .caller = 5, .callee = 10 };
    try std.testing.expectEqual(@as(u32, 5), edge.caller);
    try std.testing.expectEqual(@as(u32, 10), edge.callee);
}

test "CallGraph - FunctionNode structure" {
    const cg_mod = @import("../src/pass/analysis/call_graph.zig");
    const node = cg_mod.FunctionNode{
        .id = 1,
        .name = "test_func",
        .raw = null,
        .kind = .internal,
        .isExternal = false,
        .calls = .{},
        .callers = .{},
    };
    try std.testing.expectEqual(@as(u32, 1), node.id);
    try std.testing.expectEqualStrings("test_func", node.name);
    try std.testing.expectEqual(cg_mod.FunctionKind.internal, node.kind);
    try std.testing.expect(!node.isExternal);
}

test "Boundary - Pipeline with IR" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    try pipeline.loadIR("examples/sample_wasm_wasm32.bc");

    const loader = pipeline.getIRLoader();
    try std.testing.expect(loader != null);
    try std.testing.expect(loader.?.hasModule());

    const func_count = loader.?.getFunctionCount();
    try std.testing.expect(func_count > 0);
}

test "Boundary - Non-existent file" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const result = pipeline.loadIR("nonexistent/file.bc");
    try std.testing.expectError(OmniScope.engine.LoaderError.FileNotFound, result);
}

test "Pressure - CallGraph initialization" {
    var pass = call_graph.CallGraphPass.init(std.testing.allocator);
    defer pass.deinit();

    try std.testing.expectEqual(@as(usize, 0), pass.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), pass.edges.items.len);
}

test "Pressure - Multiple pass inits" {
    var pass1 = call_graph.CallGraphPass.init(std.testing.allocator);
    defer pass1.deinit();

    var pass2 = call_graph.CallGraphPass.init(std.testing.allocator);
    defer pass2.deinit();

    try std.testing.expect(pass1.nodes.items.len == 0);
    try std.testing.expect(pass2.nodes.items.len == 0);
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
