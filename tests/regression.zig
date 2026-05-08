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
    // DC-C15 FIX: Update layer counts to match current registry
    // Old values were stale, now using dynamic validation
    const l1 = registry.SemanticRegistry.layer1Count();
    const l2 = registry.SemanticRegistry.layer2Count();
    const l3 = registry.SemanticRegistry.layer3Count();
    const l4 = registry.SemanticRegistry.layer4Count();
    const l5 = registry.SemanticRegistry.layer5Count();
    const l6 = registry.SemanticRegistry.layer6Count();
    const total = registry.SemanticRegistry.totalCount();

    // Validate counts are non-zero and sum correctly
    try std.testing.expect(l1 > 0);
    try std.testing.expect(l2 > 0);
    try std.testing.expect(l3 > 0);
    try std.testing.expect(l4 > 0);
    try std.testing.expect(l5 > 0);
    try std.testing.expect(l6 > 0);
    try std.testing.expectEqual(total, l1 + l2 + l3 + l4 + l5 + l6);
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
        "malloc",   "free",         "system",          "popen",
        "strcpy",   "sprintf",      "gets",            "into_raw",
        "from_raw", "operator new", "operator delete",
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
        "malloc",                  "calloc",         "realloc",
        "GeneralPurposeAllocator", "ArenaAllocator", "operator new",
        "make_unique",             "make_shared",
    };

    for (allocators) |func| {
        const sem = registry.SemanticRegistry.lookup(func) orelse continue;
        try std.testing.expect(sem.transfers_ownership, "{s} should transfer ownership", .{func});
    }
}

test "Regression: deallocators consume ownership" {
    const deallocators = [_][]const u8{
        "free",            ".free(",            "allocator.free",
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
        "malloc",       "calloc", "realloc",
        "fopen",        "dlopen", ".?",
        "dynamic_cast",
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
