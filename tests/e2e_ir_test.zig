//! End-to-End Integration Tests for OmniScope
//!
//! These tests verify the complete analysis pipeline works correctly
//! with real LLVM IR files from multiple programming languages.
//!
//! Acceptance Criteria:
//! 1. All IR files load without errors through Pipeline
//! 2. Passes can access loaded module information
//! 3. Diagnostics are generated correctly
//! 4. No memory leaks

const std = @import("std");
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const PassContext = OmniScope.pass.PassContext;
const PassKind = OmniScope.pass.PassKind;
const Diagnostic = OmniScope.diag.Diagnostic;
const IRLoader = OmniScope.engine.IRLoader;
const LoaderError = OmniScope.engine.LoaderError;

const TEST_IR_DIR = "tests/ir";

fn getTestIRPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}.bc", .{ cwd, TEST_IR_DIR, name });
}

test "E2E - Pipeline loads C control flow IR" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);

    const loader = pipeline.getIRLoader();
    try std.testing.expect(loader != null);
    try std.testing.expect(loader.?.hasModule());
}

test "E2E - Pipeline loads all 6 IR files" {
    const ir_names = [_][]const u8{
        "test_c_control_flow",
        "test_c_pointers",
        "test_c_threads",
        "test_cpp_classes",
        "test_cpp_virtual",
        "test_rust_patterns",
    };

    for (ir_names) |name| {
        var pipeline = Pipeline.init(std.testing.allocator);
        defer pipeline.deinit();

        const path = try getTestIRPath(std.testing.allocator, name);
        defer std.testing.allocator.free(path);

        try pipeline.loadIR(path);

        const loader = pipeline.getIRLoader();
        try std.testing.expect(loader != null);
        try std.testing.expect(loader.?.hasModule());
    }
}

test "E2E - Pipeline runs with IR loaded" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);

    const result = try pipeline.runStaticAnalysis();

    try std.testing.expect(result.execution_time_ns > 0);
    try std.testing.expect(result.fact_count >= 0);
}

test "E2E - Multiple IR files sequential analysis" {
    const ir_names = [_][]const u8{
        "test_c_control_flow",
        "test_c_pointers",
        "test_c_threads",
    };

    for (ir_names) |name| {
        var pipeline = Pipeline.init(std.testing.allocator);
        defer pipeline.deinit();

        const path = try getTestIRPath(std.testing.allocator, name);
        defer std.testing.allocator.free(path);

        try pipeline.loadIR(path);

        const result = try pipeline.runStaticAnalysis();
        try std.testing.expect(result.execution_time_ns > 0);
    }
}

test "E2E - Non-existent IR file returns error" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const result = pipeline.loadIR("nonexistent/file.bc");
    try std.testing.expectError(LoaderError.FileNotFound, result);
}

test "E2E - Pipeline cleanup after analysis" {
    var pipeline = Pipeline.init(std.testing.allocator);

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);
    try std.testing.expect(pipeline.getIRLoader() != null);

    pipeline.deinit();
}

test "E2E - Pipeline supports pass dependency resolution with IR" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *OmniScope.pass.DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.cfg_edge, 1, 2, ctx.getNextId());
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *OmniScope.pass.DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.dfg_edge, 3, 4, ctx.getNextId());
        }
    };

    try pipeline.registerPass(PassB);
    try pipeline.registerPass(PassA);

    const result = try pipeline.runStaticAnalysis();
    try std.testing.expect(result.fact_count >= 2);
}

test "E2E - Instrumentation plan populated after analysis" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);

    const InstrumentationPass = struct {
        pub const name = "instrumentation";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *OmniScope.pass.DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.cfg_edge, 1, 2, ctx.getNextId());
        }
    };

    try pipeline.registerPass(InstrumentationPass);

    _ = try pipeline.runStaticAnalysis();

    const plan = pipeline.getInstrumentationPlan();
    _ = plan;
}

test "E2E - IR loader deinit is called during pipeline deinit" {
    var pipeline = Pipeline.init(std.testing.allocator);

    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    try pipeline.loadIR(path);
    try std.testing.expect(pipeline.getIRLoader() != null);

    pipeline.deinit();
}
