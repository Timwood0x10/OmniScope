//! Tests for NoiseFilter — PHASE3-TASK-3 (Part 2)
//!
//! Coverage target: isGoFunction fix verification + isExternCPattern + boundary cases
//! Test categories: regression prevention, language boundaries, error handling

const std = @import("std");
const noise_filter = @import("noise_filter.zig");

// ============================================================================
// Regression: Verify BUG-FIX-6 (isGoFunction no longer misclassifies C++/Rust)
// ============================================================================

test "NoiseFilter integration - C++ functions should not be classified as Go (regression)" {
    // After BUG-FIX-6, C++ namespaced functions should NOT be treated as Go.
    // They must be classified as third_party or user code, NOT stdlib/compiler_generated via Go path.
    const cpp_functions = [_][]const u8{
        "std::vector::push_back",
        "std::string::c_str",
        "_ZNSt6vectorIiE9push_backERKi",
    };

    for (cpp_functions) |func| {
        const result = noise_filter.classifyFunction(func, .cpp);
        // C++ stdlib names like std::* should be third_party or stdlib,
        // but crucially the reason must NOT mention "Go"
        const reason_has_go = std.mem.indexOf(u8, result.reason, "Go") != null;
        try std.testing.expect(!reason_has_go, "C++ function '{s}' was incorrectly classified as Go: {s}", .{ func, result.reason });
    }
}

test "NoiseFilter integration - Rust functions should not be classified as Go (regression)" {
    // After BUG-FIX-6, Rust module paths with dots should NOT be Go
    const rust_functions = [_][]const u8{
        "core::ptr::drop_in_place",
        "alloc::alloc::exchange",
        "_RNvCsfLfy6EI15iL_7___rustc",
    };

    for (rust_functions) |func| {
        // Auto-detect without language hint — must not classify as Go
        const result = noise_filter.classifyFunction(func, null);
        const reason_has_go = std.mem.indexOf(u8, result.reason, "Go") != null;
        try std.testing.expect(!reason_has_go, "Rust function '{s}' was incorrectly classified as Go: {s}", .{ func, result.reason });
    }
}

// ============================================================================
// Boundary: Go functions still correctly identified
// ============================================================================

test "NoiseFilter integration - Real Go functions are still recognized (boundary)" {
    // These SHOULD still be recognized as Go runtime / compiler-generated
    const go_expectations = struct {
        name: []const u8,
        expected_origin: noise_filter.FunctionOrigin,
    };
    const cases = [_]go_expectations{
        .{ .name = "runtime.main", .expected_origin = .stdlib },
        .{ .name = "main.main", .expected_origin = .stdlib },
        .{ .name = "go.func1", .expected_origin = .compiler_generated },
        .{ .name = "cgocall", .expected_origin = .compiler_generated },
        .{ .name = "crosscall2", .expected_origin = .compiler_generated },
    };

    for (cases) |case| {
        const result = noise_filter.classifyFunction(case.name, .go);
        try std.testing.expectEqual(case.expected_origin, result.origin, "Go function '{s}': expected origin {s}, got {s} (reason: {s})", .{
            case.name,
            case.expected_origin.toString(),
            result.origin.toString(),
            result.reason,
        });
    }
}

// ============================================================================
// Error handling: Edge inputs
// ============================================================================

test "NoiseFilter integration - handles special characters (error case)" {
    // Empty string → unknown origin (handled gracefully)
    const empty_result = noise_filter.classifyFunction("", null);
    try std.testing.expectEqual(noise_filter.FunctionOrigin.unknown, empty_result.origin);

    // Single dot → should not crash, return some valid classification
    const dot_result = noise_filter.classifyFunction(".", null);
    _ = dot_result.origin; // just verify no crash

    // Double dot → same
    const double_dot = noise_filter.classifyFunction("..", null);
    _ = double_dot.origin;

    // Underscore-only → should not crash
    const underscore = noise_filter.classifyFunction("_", null);
    _ = underscore.origin;

    // Single char → user code (default fallback)
    const single_char = noise_filter.classifyFunction("a", null);
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, single_char.origin);
}
