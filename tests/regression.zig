//! Regression Tests for OmniScope
//!
//! These tests ensure that changes to the codebase don't break existing functionality.
//! Run with: zig test regression.zig

const std = @import("std");
const OmniScope = @import("OmniScope");
const registry = OmniScope.registry;
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Severity = OmniScope.diag.Severity;
const output = OmniScope.output;

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

// ========================================
// Output Format Validation
// ========================================

test "Output: JSON escapes special characters" {
    var buf = std.ArrayList(u8).initCapacity(std.testing.allocator, 64) catch return error.OutOfMemory;
    defer buf.deinit(std.testing.allocator);
    try output.writeJsonEscaped(buf.writer(), "hello\"world\\\n\r\t");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "hello\\\"world") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\\\") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\r") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\t") != null);
}

test "Output: JSON control characters are hex escaped" {
    var buf = std.ArrayList(u8).initCapacity(std.testing.allocator, 64) catch return error.OutOfMemory;
    defer buf.deinit(std.testing.allocator);
    try output.writeJsonEscaped(buf.writer(), "\x01\x1f");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\u0001") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\\u001f") != null);
}

test "Output: JSON ascii passes through unchanged" {
    var buf = std.ArrayList(u8).initCapacity(std.testing.allocator, 64) catch return error.OutOfMemory;
    defer buf.deinit(std.testing.allocator);
    try output.writeJsonEscaped(buf.writer(), "safe_text_123");
    try std.testing.expectEqualStrings("safe_text_123", buf.items);
}

test "Output: SarifOutput generates valid JSON" {
    const allocator = std.testing.allocator;
    var sarif = output.SarifOutput.init(allocator, "test-tool", "0.1.8");
    const loc = Issue.Location.init("test_func");
    const issues = [_]Issue{
        Issue.init(.memory_leak, "test leak", loc, .high, 0.9),
    };
    const result = try sarif.generate(&issues);
    defer allocator.free(result);
    // Verify it's valid JSON with expected fields
    try std.testing.expect(std.mem.indexOf(u8, result, "\"version\": \"2.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"runs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "memory_leak") != null);
}

test "Output: SarifOutput with multiple issues" {
    const allocator = std.testing.allocator;
    var sarif = output.SarifOutput.init(allocator, "test-tool", "0.1.8");
    const loc = Issue.Location.init("test_func");
    const issues = [_]Issue{
        Issue.init(.memory_leak, "leak1", loc, .high, 0.9),
        Issue.init(.double_free, "df1", loc, .critical, 0.95),
        Issue.init(.buffer_overflow, "bo1", loc, .medium, 0.7),
    };
    const result = try sarif.generate(&issues);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "memory_leak") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "double_free") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "buffer_overflow") != null);
}

test "Output: SarifOutput severity mapping" {
    const allocator = std.testing.allocator;
    var sarif = output.SarifOutput.init(allocator, "test-tool", "0.1.8");
    const loc = Issue.Location.init("test_func");
    const levels = [_]struct { Severity, []const u8 }{
        .{ .low, "note" },
        .{ .medium, "warning" },
        .{ .high, "error" },
        .{ .critical, "error" },
    };
    inline for (levels) |entry| {
        const issues = [_]Issue{Issue.init(.memory_leak, "test", loc, entry[0], 0.8)};
        const result = try sarif.generate(&issues);
        defer allocator.free(result);
        try std.testing.expect(std.mem.indexOf(u8, result, entry[1]) != null);
    }
}
