//! FFI Semantic Model
//!
//! Minimum libc semantic model for FFI security analysis.
//! This module provides semantic information about common C library functions
//! to enable precise security checks based on actual IR facts.

const std = @import("std");

/// Function risk classification for noise reduction
pub const FunctionRiskLevel = enum {
    /// Low risk functions that can be safely ignored
    low_risk,
    /// Modeled functions with known semantics
    modeled,
    /// Unknown functions requiring conservative analysis
    unknown,
};

/// Value origin tracking
pub const ValueOrigin = enum {
    /// Unknown origin
    unknown,
    /// Returned from malloc/calloc/realloc / __rust_alloc
    from_malloc,
    /// Function parameter
    from_param,
    /// Global variable
    from_global,
    /// Constant value
    from_constant,
    /// Returned from an FFI boundary call (non-Rust-mangled callee)
    /// Indicates potential cross-allocator ownership risk.
    from_ffi_call,
};

/// Memory ownership semantics
pub const Ownership = enum {
    /// No special ownership
    none,
    /// Returns owned memory (malloc)
    returns_owned,
    /// Consumes owned memory (free)
    consumes,
};

/// Nullability semantics
pub const Nullability = enum {
    /// Unknown nullability
    unknown,
    /// Can be null
    nullable,
    /// Cannot be null
    nonnull,
};

/// FFI function semantics
pub const FFISemantics = struct {
    /// Function name
    name: []const u8,
    /// Risk classification
    risk_level: FunctionRiskLevel,
    /// Returns pointer type
    returns_ptr: bool,
    /// Return value nullability
    returns_nullability: Nullability,
    /// Memory ownership
    ownership: Ownership,
    /// Consumes argument index (for free, etc.)
    consumes_arg_index: ?u32,
};

/// Minimum libc semantic table
///
/// This table contains only the most critical functions for security analysis.
/// Following the principle of minimal modeling for maximum reliability.
const libc_semantics = [_]FFISemantics{
    // Memory allocation functions
    .{
        .name = "malloc",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
    .{
        .name = "calloc",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
    .{
        .name = "realloc",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = 0,
    },
    .{
        .name = "free",
        .risk_level = .modeled,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .consumes,
        .consumes_arg_index = 0,
    },

    // String functions
    .{
        .name = "strcpy",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nonnull,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "strcat",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nonnull,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "gets",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .none,
        .consumes_arg_index = null,
    },

    // Format string functions - low risk by default
    .{
        .name = "printf",
        .risk_level = .low_risk,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "fprintf",
        .risk_level = .low_risk,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "sprintf",
        .risk_level = .low_risk,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "snprintf",
        .risk_level = .low_risk,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "puts",
        .risk_level = .low_risk,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },

    // Command execution functions
    .{
        .name = "system",
        .risk_level = .modeled,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "exec",
        .risk_level = .modeled,
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .none,
        .consumes_arg_index = null,
    },
    .{
        .name = "popen",
        .risk_level = .modeled,
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
};

/// Get function semantics by name
///
/// Arguments:
///   - name: Function name to look up
///
/// Returns:
///   - Pointer to FFISemantics struct, or null if not found
pub fn getSemantics(name: []const u8) ?*const FFISemantics {
    for (&libc_semantics) |*semantics| {
        if (std.mem.eql(u8, semantics.name, name)) {
            return semantics;
        }
    }
    return null;
}

/// Classify function risk level
///
/// Arguments:
///   - name: Function name to classify
///
/// Returns:
///   - Risk level for the function
pub fn classifyRisk(name: []const u8) FunctionRiskLevel {
    if (getSemantics(name)) |semantics| {
        return semantics.risk_level;
    }
    return .unknown;
}

/// Check if function is low risk
///
/// Low risk functions can be safely ignored in most analysis.
///
/// Arguments:
///   - name: Function name to check
///
/// Returns:
///   - true if function is low risk
pub fn isLowRisk(name: []const u8) bool {
    return classifyRisk(name) == .low_risk;
}

/// Check if function returns owned memory
///
/// Arguments:
///   - name: Function name to check
///
/// Returns:
///   - true if function returns owned memory
pub fn returnsOwnedMemory(name: []const u8) bool {
    if (getSemantics(name)) |semantics| {
        return semantics.ownership == .returns_owned;
    }
    return false;
}

/// Check if function consumes owned memory
///
/// Arguments:
///   - name: Function name to check
///
/// Returns:
///   - true if function consumes owned memory
pub fn consumesOwnedMemory(name: []const u8) bool {
    if (getSemantics(name)) |semantics| {
        return semantics.ownership == .consumes;
    }
    return false;
}

/// Get argument index that consumes owned memory
///
/// Arguments:
///   - name: Function name to check
///
/// Returns:
///   - Argument index, or null if function doesn't consume memory
pub fn getConsumedArgIndex(name: []const u8) ?u32 {
    if (getSemantics(name)) |semantics| {
        return semantics.consumes_arg_index;
    }
    return null;
}

test "FFISemantics - getSemantics" {
    const malloc_sem = getSemantics("malloc");
    try std.testing.expect(malloc_sem != null);
    try std.testing.expectEqual(@as([]const u8, "malloc"), malloc_sem.?.name);
    try std.testing.expectEqual(FunctionRiskLevel.modeled, malloc_sem.?.risk_level);
    try std.testing.expectEqual(Ownership.returns_owned, malloc_sem.?.ownership);
}

test "FFISemantics - classifyRisk" {
    try std.testing.expectEqual(FunctionRiskLevel.low_risk, classifyRisk("printf"));
    try std.testing.expectEqual(FunctionRiskLevel.modeled, classifyRisk("malloc"));
    try std.testing.expectEqual(FunctionRiskLevel.modeled, classifyRisk("free"));
    try std.testing.expectEqual(FunctionRiskLevel.unknown, classifyRisk("unknown_func"));
}

test "FFISemantics - isLowRisk" {
    try std.testing.expect(isLowRisk("printf"));
    try std.testing.expect(isLowRisk("fprintf"));
    try std.testing.expect(isLowRisk("sprintf"));
    try std.testing.expect(!isLowRisk("malloc"));
    try std.testing.expect(!isLowRisk("free"));
}

test "FFISemantics - returnsOwnedMemory" {
    try std.testing.expect(returnsOwnedMemory("malloc"));
    try std.testing.expect(returnsOwnedMemory("calloc"));
    try std.testing.expect(returnsOwnedMemory("realloc"));
    try std.testing.expect(!returnsOwnedMemory("free"));
    try std.testing.expect(!returnsOwnedMemory("printf"));
}

test "FFISemantics - consumesOwnedMemory" {
    try std.testing.expect(consumesOwnedMemory("free"));
    try std.testing.expect(!consumesOwnedMemory("malloc"));
    try std.testing.expect(!consumesOwnedMemory("printf"));
}

test "FFISemantics - getConsumedArgIndex" {
    try std.testing.expectEqual(@as(u32, 0), getConsumedArgIndex("free").?);
    try std.testing.expect(getConsumedArgIndex("malloc") == null);
    try std.testing.expect(getConsumedArgIndex("printf") == null);
}

test "FFISemantics - table completeness" {
    // Verify critical functions are in the u32able
    const critical_functions = [_][]const u8{
        "malloc", "free", "printf", "system", "strcpy", "gets",
    };

    for (critical_functions) |func| {
        try std.testing.expect(getSemantics(func) != null, "{s} not found in semantics table", .{func});
    }
}
