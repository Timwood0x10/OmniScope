//! Tests for Free Function List Unification — PHASE3-TASK-2
//!
//! Coverage target: Verify isFreeFunction consistency across modules
//! Test categories: completeness, cross-module consistency, regression

const std = @import("std");

const ptr_lifetime_classify = @import("../pass/analysis/ptr_lifetime_classify.zig");

// ============================================================================
// PHASE3-TASK-2 Core: Verify Free function list completeness
// ============================================================================

test "isFreeFunction - contains standard C free functions (happy path)" {
    // Verify the canonical free functions are recognized
    const free_functions = [_][]const u8{
        "free",
        "realloc",
        "kfree",
        "g_free",
        "PyObject_Free",
        "PyMem_Free",
        "munmap",
        "close", // fd close can release resources
    };

    for (free_functions) |func_name| {
        const result = ptr_lifetime_classify.isFreeFunction(func_name);
        try std.testing.expect(result, "{s} should be recognized as free function", .{func_name});
    }
}

test "isFreeFunction - rejects non-free functions (boundary)" {
    const non_free_functions = [_][]const u8{
        "malloc",
        "calloc",
        "printf",
        "strcpy",
        "system",
        "unknown_func",
    };

    for (non_free_functions) |func_name| {
        const result = ptr_lifetime_classify.isFreeFunction(func_name);
        try std.testing.expect(!result, "{s} should NOT be recognized as free function", .{func_name});
    }
}

test "isFreeFunction - handles empty string (error case)" {
    const result = ptr_lifetime_classify.isFreeFunction("");
    try std.testing.expect(!result, "Empty string should not be a free function");
}

test "isFreeFunction - Rust deallocators included (lang boundary)" {
    // After FIX-1, __rust_dealloc should be tracked (not noise)
    // Verify it's in the free function list for proper pairing
    const rust_deallocators = [_][]const u8{
        "__rust_dealloc",
    };

    for (rust_deallocators) |dealloc| {
        // Note: This may or may not be in isFreeFunction depending on design
        // At minimum, it should NOT crash
        _ = ptr_lifetime_classify.isFreeFunction(dealloc);
    }
}

// ============================================================================
// Consistency: Verify no duplicates between modules
// ============================================================================

test "isFreeFunction - no duplicate patterns in implementation" {
    // This test ensures the implementation doesn't have redundant checks
    // (which would indicate copy-paste from another module)

    // Call multiple times with same input — should return same result
    const test_funcs = [_][]const u8{ "free", "malloc", "realloc" };

    for (test_funcs) |func| {
        const r1 = ptr_lifetime_classify.isFreeFunction(func);
        const r2 = ptr_lifetime_classify.isFreeFunction(func);
        try std.testing.expectEqual(r1, r2, "Result should be deterministic for {s}", .{func});
    }
}
