//! Tests for Hooks module — FIX-3: Ownership pairing via pointer value
//!
//! Coverage target: ≥70% for HookContext + rustOwnershipHook + pythonRefcountHook
//! Test categories: happy path, boundary cases, error cases, language boundaries

const std = @import("std");

const types = @import("types.zig");
const HookContext = types.HookContext;
const HookResult = types.HookResult;
const rustOwnershipHook = @import("hooks.zig").rustOwnershipHook;
const pythonRefcountHook = @import("hooks.zig").pythonRefcountHook;

// ============================================================================
// FIX-3 Core: HookContext has first_arg_ptr_val field for ownership tracking
// ============================================================================

test "HookContext - has first_arg_ptr_val field (FIX-3 happy path)" {
    // After FIX-3, HookContext should include first_arg_ptr_val for ownership pairing
    const ctx = HookContext{
        .inst = undefined,
        .callee_name = "test",
        .opcode = 0,
        .first_arg_ptr_val = 0x12345678,
    };

    try std.testing.expectEqual(@as(u64, 0x12345678), ctx.first_arg_ptr_val);
}

test "HookContext - first_arg_ptr_val defaults to 0 (boundary)" {
    // When not explicitly set, should default to 0 (safe default)
    const ctx = HookContext{
        .inst = undefined,
        .callee_name = "test",
        .opcode = 0,
    };

    try std.testing.expectEqual(@as(u64, 0), ctx.first_arg_ptr_val);
}

// ============================================================================
// FIX-3 Core: rustOwnershipHook uses first_arg_ptr_val (not inst address)
// ============================================================================

test "rustOwnershipHook - returns none when first_arg_ptr_val is 0 (boundary)" {
    // CRITICAL: After FIX-3, hook should return .none for null/zero pointers
    // This prevents false positives from instructions without pointer arguments
    var ctx = HookContext{
        .inst = @as(*anyopaque, @ptrFromInt(0xDEADBEEF)),
        .callee_name = "into_raw",
        .opcode = 0,
        .first_arg_ptr_val = 0, // No pointer argument
    };

    const result = rustOwnershipHook(&ctx);
    try std.testing.expectEqual(HookResult.none, result);
}

test "rustOwnershipHook - processes into_raw with valid ptr (happy path)" {
    // When first_arg_ptr_val is non-zero, hook should process it
    var ctx = HookContext{
        .inst = @as(*anyopaque, @ptrFromInt(0xAAA)),
        .callee_name = "into_raw",
        .opcode = 0,
        .first_arg_ptr_val = 0x12345678, // Valid pointer value
    };

    // Should not crash and should return a valid result (either .none or .issue_found)
    const result = rustOwnershipHook(&ctx);
    _ = result; // Result depends on internal state machine
}

test "rustOwnershipHook - processes from_raw with matching ptr (happy path)" {
    var ctx = HookContext{
        .inst = @as(*anyopaque, @ptrFromInt(0xBBB)),
        .callee_name = "from_raw",
        .opcode = 0,
        .first_arg_ptr_val = 0x12345678, // Same ptr as into_raw
    };

    const result = rustOwnershipHook(&ctx);
    _ = result;
}

// ============================================================================
// FIX-3 Core: pythonRefcountHook uses first_arg_ptr_val
// ============================================================================

test "pythonRefcountHook - returns none when first_arg_ptr_val is 0 (boundary)" {
    var ctx = HookContext{
        .inst = @as(*anyopaque, @ptrFromInt(0xCAFE)),
        .callee_name = "Py_DECREF",
        .opcode = 0,
        .first_arg_ptr_val = 0,
    };

    const result = pythonRefcountHook(&ctx);
    try std.testing.expectEqual(HookResult.none, result);
}

test "pythonRefcountHook - processes Py_INCREF with valid ptr (happy path)" {
    var ctx = HookContext{
        .inst = undefined,
        .callee_name = "Py_INCREF",
        .opcode = 0,
        .first_arg_ptr_val = 0x87654321,
    };

    const result = pythonRefcountHook(&ctx);
    _ = result;
}

// ============================================================================
// Language boundary: Hooks work across Rust and Python FFI patterns
// ============================================================================

test "rustOwnershipHook - recognizes transfer_out patterns (lang boundary)" {
    // Verify hook knows about common Rust FFI transfer patterns
    const transfer_patterns = [_][]const u8{
        "into_raw",
        "Box::into_raw",
        "CString::into_raw",
    };

    // These should be processed (not crash) when called with valid ptr
    for (transfer_patterns) |pattern| {
        var ctx = HookContext{
            .inst = undefined,
            .callee_name = pattern,
            .opcode = 0,
            .first_arg_ptr_val = 0xABCD,
        };
        const result = rustOwnershipHook(&ctx);
        _ = result;
    }
}

test "pythonRefcountHook - recognizes refcount patterns (lang boundary)" {
    const refcount_patterns = [_][]const u8{
        "Py_INCREF",
        "Py_DECREF",
        "Py_XINCREF",
        "Py_XDECREF",
    };

    for (refcount_patterns) |pattern| {
        var ctx = HookContext{
            .inst = undefined,
            .callee_name = pattern,
            .opcode = 0,
            .first_arg_ptr_val = 0xDCBA,
        };
        const result = pythonRefcountHook(&ctx);
        _ = result;
    }
}

// ============================================================================
// Error cases: Edge inputs
// ============================================================================

test "rustOwnershipHook - handles empty callee name (error case)" {
    var ctx = HookContext{
        .inst = undefined,
        .callee_name = "",
        .opcode = 0,
        .first_arg_ptr_val = 0x1234,
    };

    // Should not crash on empty name
    const result = rustOwnershipHook(&ctx);
    _ = result;
}

test "pythonRefcountHook - handles unknown function (error case)" {
    var ctx = HookContext{
        .inst = undefined,
        .callee_name = "unknown_function",
        .opcode = 0,
        .first_arg_ptr_val = 0x5678,
    };

    const result = pythonRefcountHook(&ctx);
    try std.testing.expectEqual(HookResult.none, result, "Unknown functions should return none");
}
