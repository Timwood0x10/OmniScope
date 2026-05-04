//! Tests for Layer1Reg — PHASE3-TASK-1: Dangerous Functions SSOT Verification
//!
//! Coverage target: Verify Single Source of Truth (SSOT) for dangerous functions
//! Test categories: completeness, consistency, regression prevention

const std = @import("std");

const layer1_reg = @import("../registry/layer1_reg.zig");
const layer1_functions = layer1_reg.layer1_functions;

// ============================================================================
// PHASE3-TASK-1 Core: Verify SSOT contains all critical dangerous functions
// ============================================================================

test "layer1_functions - total count is 43 (SSOT baseline)" {
    // CRITICAL: This is the Single Source of Truth count
    // All other files should reference this, not define their own lists
    try std.testing.expectEqual(@as(usize, 43), layer1_functions.len);
}

test "layer1_functions - contains critical memory functions" {
    // Verify essential allocator/deallocator functions are present
    var has_malloc = false;
    var has_free = false;
    var has_calloc = false;
    var has_realloc = false;

    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "malloc")) has_malloc = true;
        if (std.mem.eql(u8, func.pattern, "free")) has_free = true;
        if (std.mem.eql(u8, func.pattern, "calloc")) has_calloc = true;
        if (std.mem.eql(u8, func.pattern, "realloc")) has_realloc = true;
    }

    try std.testing.expect(has_malloc, "SSOT must contain malloc");
    try std.testing.expect(has_free, "SSOT must contain free");
    try std.testing.expect(has_calloc, "SSOT must contain calloc");
    try std.testing.expect(has_realloc, "SSOT must contain realloc");
}

test "layer1_functions - contains critical string functions" {
    var has_strcpy = false;
    var has_strcat = false;
    var has_gets = false;

    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "strcpy")) has_strcpy = true;
        if (std.mem.eql(u8, func.pattern, "strcat")) has_strcat = true;
        if (std.mem.eql(u8, func.pattern, "gets")) has_gets = true;
    }

    try std.testing.expect(has_strcpy, "SSOT must contain strcpy");
    try std.testing.expect(has_strcat, "SSOT must contain strcat");
    try std.testing.expect(has_gets, "SSOT must contain gets");
}

test "layer1_functions - contains command execution functions" {
    var has_system = false;
    var has_popen = false;

    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "system")) has_system = true;
        if (std.mem.eql(u8, func.pattern, "popen")) has_popen = true;
    }

    try std.testing.expect(has_system, "SSOT must contain system");
    try std.testing.expect(has_popen, "SSOT must contain popen");
}

test "layer1_functions - contains OpenSSL functions" {
    var has_RSA_new = false;
    var has_RSA_free = false;
    var has_SSL_CTX_new = false;
    var has_SSL_CTX_free = false;

    for (layer1_functions) |func| {
        if (std.mem.indexOf(u8, func.pattern, "RSA_new") != null) has_RSA_new = true;
        if (std.mem.indexOf(u8, func.pattern, "RSA_free") != null) has_RSA_free = true;
        if (std.mem.indexOf(u8, func.pattern, "SSL_CTX_new") != null) has_SSL_CTX_new = true;
        if (std.mem.indexOf(u8, func.pattern, "SSL_CTX_free") != null) has_SSL_CTX_free = true;
    }

    try std.testing.expect(has_RSA_new, "SSOT must contain RSA_new");
    try std.testing.expect(has_RSA_free, "SSOT must contain RSA_free");
    try std.testing.expect(has_SSL_CTX_new, "SSOT must contain SSL_CTX_new");
    try std.testing.expect(has_SSL_CTX_free, "SSOT must contain SSL_CTX_free");
}

test "layer1_functions - contains SQLite3 functions" {
    var has_sqlite3_open = false;
    var has_sqlite3_close = false;

    for (layer1_functions) |func| {
        if (std.mem.indexOf(u8, func.pattern, "sqlite3_open") != null) has_sqlite3_open = true;
        if (std.mem.indexOf(u8, func.pattern, "sqlite3_close") != null) has_sqlite3_close = true;
    }

    try std.testing.expect(has_sqlite3_open, "SSOT must contain sqlite3_open");
    try std.testing.expect(has_sqlite3_close, "SSOT must contain sqlite3_close");
}

// ============================================================================
// Boundary: Verify function semantics are correct
// ============================================================================

test "layer1_functions - malloc has correct semantics" {
    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "malloc")) {
            try std.testing.expectEqual(.allocator, func.kind);
            try std.testing.expectEqual(.medium, func.severity);
            try std.testing.expect(func.transfers_ownership);
            try std.testing.expect(func.requires_null_check);
            break;
        }
    }
}

test "layer1_functions - free has correct semantics" {
    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "free")) {
            try std.testing.expectEqual(.deallocator, func.kind);
            try std.testing.expectEqual(.high, func.severity);
            try std.testing.expect(func.consumes_ownership);
            break;
        }
    }
}

test "layer1_functions - system has critical severity" {
    for (layer1_functions) |func| {
        if (std.mem.eql(u8, func.pattern, "system")) {
            try std.testing.expectEqual(.critical, func.severity);
            try std.testing.expectEqual(.command_exec, func.kind);
            break;
        }
    }
}

// ============================================================================
// Regression: Ensure no duplicates in SSOT
// ============================================================================

test "layer1_functions - no duplicate patterns" {
    var seen = std.AutoHashMap([]const u8, void).init(std.testing.allocator);
    defer seen.deinit();

    for (layer1_functions) |func| {
        try std.testing.expect(!seen.contains(func.pattern), "Duplicate pattern found: {s}", .{func.pattern});
        try seen.put(func.pattern, {});
    }
}
