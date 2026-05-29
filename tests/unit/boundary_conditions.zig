//! Boundary Conditions Tests — Edge Cases and Robustness
//!
//! Run: zig build test-boundary

const std = @import("std");
const OmniScope = @import("OmniScope");

const issue_suppression = OmniScope.pass.analysis.noise.issue_suppression;
const ffi_zone_check = OmniScope.pass.analysis.ffi.ffi_zone_check;
const mangled_name = OmniScope.semantics.surface_classifier.mangled_name;
const cpp_fp_reduction = OmniScope.pass.analysis.noise.cpp_fp_reduction;
const Issue = OmniScope.diag.Issue;

test "BOUNDARY-G1: handle empty function names gracefully" {
    var issue = Issue.init(.memory_leak, "test", .{ .file = null, .func = "" }, .medium, 0.6);
    try std.testing.expect(!issue_suppression.isStdlibInternalFunction(&issue));
}

test "BOUNDARY-G2: handle empty function name in isCompilerInternalFunction" {
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction(""));
}

test "BOUNDARY-G3: handle empty function name in classifyMangledName" {
    const result = mangled_name.classifyMangledName("");
    try std.testing.expect(result == null);
}

test "BOUNDARY-G4: handle empty string in isDangerousCFunction" {
    try std.testing.expect(!ffi_zone_check.isDangerousCFunction(""));
}

test "BOUNDARY-G5: handle empty string in classifyCSafetyLevel" {
    try std.testing.expectEqual(@as(?ffi_zone_check.CSafetyLevel, null), ffi_zone_check.classifyCSafetyLevel(""));
}

test "BOUNDARY-G6: handle empty string in isZigSafeCimport" {
    try std.testing.expect(!ffi_zone_check.isZigSafeCimport(""));
}

test "BOUNDARY-G7: handle empty string in isHighRiskInternalUAF" {
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF(""));
}

test "BOUNDARY-H1: handle extremely long function name" {
    var buf: [1600]u8 = undefined;
    const long_name = std.fmt.bufPrint(&buf, "_ZN9{s}4mainE", .{"a" ** 1500}) catch unreachable;
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction(long_name));
}

test "BOUNDARY-H2: handle extremely long mangled name" {
    var buf: [2100]u8 = undefined;
    const long_name = std.fmt.bufPrint(&buf, "_ZN{s}E", .{"X" ** 2000}) catch unreachable;
    const result = mangled_name.classifyMangledName(long_name);
    try std.testing.expect(result == null);
}

test "BOUNDARY-H3: handle long dangerous function name check" {
    const allocator = std.testing.allocator;
    var long_name = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer long_name.deinit(allocator);

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        try long_name.appendSlice(allocator, "very_long_prefix_");
    }
    try long_name.appendSlice(allocator, "strcpy");

    try std.testing.expect(!ffi_zone_check.isDangerousCFunction(long_name.items));
}

test "BOUNDARY-I1: special characters return null from classifyCSafetyLevel" {
    for ([_][]const u8{ "function-with-dashes", "function.with.dots", "function$with$" }) |name| {
        try std.testing.expectEqual(@as(?ffi_zone_check.CSafetyLevel, null), ffi_zone_check.classifyCSafetyLevel(name));
    }
}

test "BOUNDARY-J1: confidence boundary values" {
    const issue1 = Issue.init(.use_after_free, "", .{ .file = null, .func = "" }, .medium, 0.75);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), issue1.confidence, 0.001);

    const issue2 = Issue.init(.memory_leak, "", .{ .file = null, .func = "" }, .low, 0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), issue2.confidence, 0.001);

    const issue3 = Issue.init(.double_free, "", .{ .file = null, .func = "" }, .critical, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), issue3.confidence, 0.001);
}

test "BOUNDARY-K1: partial matches should NOT trigger dangerous detection" {
    for ([_][]const u8{ "not_strcpy", "my_system_func", "gets_line" }) |name| {
        try std.testing.expect(!ffi_zone_check.isDangerousCFunction(name));
    }
}

test "BOUNDARY-K2: case sensitivity" {
    try std.testing.expect(ffi_zone_check.isDangerousCFunction("strcpy"));
    try std.testing.expect(!ffi_zone_check.isDangerousCFunction("StrCpy"));
}

test "BOUNDARY-L1: single char function not stdlib internal" {
    var issue = Issue.init(.memory_leak, "", .{ .file = null, .func = "x" }, .low, 0.5);
    try std.testing.expect(!issue_suppression.isStdlibInternalFunction(&issue));
}

test "BOUNDARY-L2: std. prefix IS stdlib internal" {
    var issue = Issue.init(.memory_leak, "", .{ .file = null, .func = "std." }, .low, 0.5);
    try std.testing.expect(issue_suppression.isStdlibInternalFunction(&issue));
}

test "BOUNDARY-M: minimal mangled names return null" {
    try std.testing.expect(mangled_name.classifyMangledName("_") == null);
    try std.testing.expect(mangled_name.classifyMangledName("_Z") == null);
    try std.testing.expect(mangled_name.classifyMangledName("_ZE") == null);
}
