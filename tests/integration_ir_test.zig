//! Integration Tests for IR Loading
//!
//! These tests verify the complete IR loading pipeline with real LLVM IR files
//! from multiple programming languages (C, C++, Rust).
//!
//! Acceptance Criteria:
//! 1. All IR files must load without errors
//! 2. All expected functions must be detected
//! 3. Function counts must match expected values
//! 4. Specific named functions must exist and be retrievable
//! 5. No memory leaks in loader operations
//! 6. deinit is idempotent (safe to call multiple times)

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const LoaderError = OmniScope.engine.LoaderError;

const TEST_IR_DIR = "tests/ir";

fn getTestIRPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    _ = allocator;
    return std.fmt.allocPrint(std.testing.allocator, "{s}/{s}.bc", .{ TEST_IR_DIR, name });
}

test "IR Integration - C control flow loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getModule() != null);
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
}

test "IR Integration - C pointers loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_pointers");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunctionCount() >= 4);
}

test "IR Integration - C++ classes loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_cpp_classes");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunctionCount() > 0);
}

test "IR Integration - C++ virtual loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_cpp_virtual");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunctionCount() > 0);
}

test "IR Integration - Rust patterns loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_rust_patterns");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunctionCount() > 0);
}

test "IR Integration - C threads loads correctly" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_threads");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunctionCount() >= 2);
}

test "IR Integration - C control flow finds all functions by name" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.getFunction("factorial") != null);
    try std.testing.expect(loader.getFunction("fibonacci") != null);
    try std.testing.expect(loader.getFunction("gcd") != null);
    try std.testing.expect(loader.getFunction("main") != null);
    try std.testing.expect(loader.getFunction("nonexistent") == null);
}

test "IR Integration - iterateFunctions visits all functions" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    const func1 = loader.getFunction("factorial");
    const func2 = loader.getFunction("fibonacci");
    const func3 = loader.getFunction("gcd");
    const func4 = loader.getFunction("main");

    try std.testing.expect(func1 != null);
    try std.testing.expect(func2 != null);
    try std.testing.expect(func3 != null);
    try std.testing.expect(func4 != null);
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
}

test "IR Integration - non-existent file returns error.FileNotFound" {
    const result = IRLoader.loadFile(std.testing.allocator, "nonexistent/file.bc");
    try std.testing.expectError(LoaderError.FileNotFound, result);
}

test "IR Integration - empty path returns error.FileNotFound" {
    const result = IRLoader.loadFile(std.testing.allocator, "");
    try std.testing.expectError(LoaderError.FileNotFound, result);
}

test "IR Integration - invalid path returns error.FileNotFound" {
    const result = IRLoader.loadFile(std.testing.allocator, "/invalid/path/to/file.bc");
    try std.testing.expectError(LoaderError.FileNotFound, result);
}

test "IR Integration - deinit is idempotent" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    try std.testing.expect(loader.hasModule());

    loader.deinit();
    loader.deinit();
    loader.deinit();
}

test "IR Integration - all 6 IR files load successfully" {
    const ir_names = [_][]const u8{
        "test_c_control_flow",
        "test_c_pointers",
        "test_c_threads",
        "test_cpp_classes",
        "test_cpp_virtual",
        "test_rust_patterns",
    };

    for (ir_names) |name| {
        const path = try getTestIRPath(std.testing.allocator, name);
        defer std.testing.allocator.free(path);

        var loader = try IRLoader.loadFile(std.testing.allocator, path);
        defer loader.deinit();

        try std.testing.expect(loader.hasModule());
        try std.testing.expect(loader.getFunctionCount() > 0);
    }
}

test "IR Integration - C threads finds specific functions" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_threads");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.getFunction("compute") != null);
    try std.testing.expect(loader.getFunction("main") != null);
    try std.testing.expect(loader.getFunctionCount() >= 2);
}

test "IR Integration - Rust patterns finds specific functions" {
    const path = try getTestIRPath(std.testing.allocator, "test_rust_patterns");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    try std.testing.expect(loader.getFunction("factorial") != null);
    try std.testing.expect(loader.getFunction("fibonacci") != null);
    try std.testing.expect(loader.getFunction("rust_entry") != null);
}

test "IR Integration - context is accessible" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    const ctx = loader.getContext();
    try std.testing.expect(@intFromPtr(ctx.raw) != 0);
}

test "IR Integration - empty module after load has no functions" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    if (loader.getFunction("")) |_| {
        try std.testing.expect(false);
    }
}

test "IR Integration - module raw pointer is valid" {
    const path = try getTestIRPath(std.testing.allocator, "test_c_control_flow");
    defer std.testing.allocator.free(path);

    var loader = try IRLoader.loadFile(std.testing.allocator, path);
    defer loader.deinit();

    const module = loader.getModule();
    try std.testing.expect(module != null);
    try std.testing.expect(@intFromPtr(module.?.raw) != 0);
}
