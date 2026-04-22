//! Regression Tests for OmniScope
//!
//! These tests ensure that changes to the codebase don't break existing functionality.
//! Run with: zig test regression.zig

const std = @import("std");
const OmniScope = @import("OmniScope");
const registry = OmniScope.registry;

// ========================================
// Regression: Semantic Registry Layer Counts
// ========================================

test "Regression: layer counts unchanged" {
    const expected = struct {
        l1: usize = 58,
        l2: usize = 3,
        l3: usize = 4,
        l4: usize = 8,
        l5: usize = 25,
        l6: usize = 54,
        total: usize = 152,
    };

    try std.testing.expectEqual(expected.l1, registry.SemanticRegistry.layer1Count());
    try std.testing.expectEqual(expected.l2, registry.SemanticRegistry.layer2Count());
    try std.testing.expectEqual(expected.l3, registry.SemanticRegistry.layer3Count());
    try std.testing.expectEqual(expected.l4, registry.SemanticRegistry.layer4Count());
    try std.testing.expectEqual(expected.l5, registry.SemanticRegistry.layer5Count());
    try std.testing.expectEqual(expected.l6, registry.SemanticRegistry.layer6Count());
    try std.testing.expectEqual(expected.total, registry.SemanticRegistry.totalCount());
}

// ========================================
// Regression: RiskKind Enum Size
// ========================================

test "Regression: RiskKind has exactly 13 variants" {
    try std.testing.expectEqual(@as(usize, 13), @typeInfo(registry.RiskKind).@"enum".fields.len);
}

// ========================================
// Regression: Critical Functions Always Detected
// ========================================

test "Regression: critical functions always detected" {
    const critical_functions = [_][]const u8{
        "malloc", "free", "system", "popen",
        "strcpy", "sprintf", "gets",
        "into_raw", "from_raw",
        "operator new", "operator delete",
    };

    for (critical_functions) |func| {
        const sem = registry.SemanticRegistry.lookup(func) orelse {
            std.debug.print("CRITICAL: {s} not in registry\n", .{func});
            return error.MissingCriticalFunction;
        };
        _ = sem;
    }
}

// ========================================
// Regression: Ownership Semantics Consistency
// ========================================

test "Regression: allocators transfer ownership" {
    const allocators = [_][]const u8{
        "malloc", "calloc", "realloc",
        "GeneralPurposeAllocator", "ArenaAllocator",
        "operator new", "make_unique", "make_shared",
    };

    for (allocators) |func| {
        const sem = registry.SemanticRegistry.lookup(func) orelse continue;
        try std.testing.expect(sem.transfers_ownership, "{s} should transfer ownership", .{func});
    }
}

test "Regression: deallocators consume ownership" {
    const deallocators = [_][]const u8{
        "free", "destroy(", "free(",
        "operator delete", "operator delete[]",
    };

    for (deallocators) |func| {
        const sem = registry.SemanticRegistry.lookup(func) orelse continue;
        try std.testing.expect(sem.consumes_ownership, "{s} should consume ownership", .{func});
    }
}

// ========================================
// Regression: Null Check Requirements
// ========================================

test "Regression: functions requiring null check" {
    const null_check_required = [_][]const u8{
        "malloc", "calloc", "realloc",
        "fopen", "dlopen",
        ".?", "dynamic_cast",
    };

    for (null_check_required) |func| {
        const sem = registry.SemanticRegistry.lookup(func) orelse continue;
        try std.testing.expect(sem.requires_null_check, "{s} requires null check", .{func});
    }
}

// ========================================
// Regression: Severity Ordering
// ========================================

test "Regression: severity ordering consistent" {
    try std.testing.expect(@intFromEnum(registry.Severity.low) < @intFromEnum(registry.Severity.medium));
    try std.testing.expect(@intFromEnum(registry.Severity.medium) < @intFromEnum(registry.Severity.high));
    try std.testing.expect(@intFromEnum(registry.Severity.high) < @intFromEnum(registry.Severity.critical));
}

// ========================================
// Regression: Cross-Language Detection
// ========================================

test "Regression: all languages detectable" {
    const language_patterns = [_]struct { []const u8, registry.RiskKind }{
        .{ "malloc", .allocator },
        .{ "into_raw", .rust_ownership },
        .{ "C.malloc", .go_cgo_alloc },
        .{ "UnsafeMutablePointer", .borrow_escaped },
        .{ "GeneralPurposeAllocator", .zig_allocator },
        .{ "operator new", .cpp_allocator },
    };

    for (language_patterns) |entry| {
        const sem = registry.SemanticRegistry.lookup(entry[0]) orelse {
            std.debug.print("MISSING: {s}\n", .{entry[0]});
            return error.LanguagePatternMissing;
        };
        try std.testing.expectEqual(entry[1], sem.kind);
    }
}
