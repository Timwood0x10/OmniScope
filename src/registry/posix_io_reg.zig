const std = @import("std");
const types = @import("types.zig");

pub const file_io_functions = [_]types.FunctionSemantics{
    .{ .pattern = "fopen", .match_type = .exact, .kind = .file_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = true, .description = "Open file - returns ownership, must fclose to release" },
    .{ .pattern = "fclose", .match_type = .exact, .kind = .file_io, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Close file - consumes ownership" },
    .{ .pattern = "fread", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Read from file - check return value for errors" },
    .{ .pattern = "fwrite", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Write to file - check return value for errors" },
    .{ .pattern = "fgets", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Read line from file - bounded read, safer than gets" },
    .{ .pattern = "fputs", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Write string to file - check return value" },
    .{ .pattern = "open", .match_type = .exact, .kind = .file_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = true, .description = "Open file descriptor - returns ownership, must close" },
    .{ .pattern = "close", .match_type = .exact, .kind = .file_io, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Close file descriptor - consumes ownership" },
    .{ .pattern = "read", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Read from file descriptor - check return value" },
    .{ .pattern = "write", .match_type = .exact, .kind = .file_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Write to file descriptor - check return value" },
};

pub const network_io_functions = [_]types.FunctionSemantics{
    .{ .pattern = "socket", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create socket - returns ownership, must close" },
    .{ .pattern = "connect", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Connect to server - verify destination address" },
    .{ .pattern = "bind", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Bind socket to address - check return value" },
    .{ .pattern = "listen", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Listen for connections - check return value" },
    .{ .pattern = "accept", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Accept connection - returns new socket ownership" },
    .{ .pattern = "recv", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Receive data - check return value, handle partial reads" },
    .{ .pattern = "send", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Send data - check return value, handle partial writes" },
    .{ .pattern = "recvfrom", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Receive data from - check return value" },
    .{ .pattern = "sendto", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Send data to - check return value" },
    .{ .pattern = "getaddrinfo", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = true, .description = "DNS lookup and service resolution - must freeaddrinfo to release" },
    .{ .pattern = "getnameinfo", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Reverse DNS lookup - convert address to hostname" },
    .{ .pattern = "freeaddrinfo", .match_type = .exact, .kind = .network_io, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Free address info - paired with getaddrinfo" },
    .{ .pattern = "gethostbyname", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "DNS lookup (deprecated) - returns static pointer, not thread-safe" },
    .{ .pattern = "gethostbyaddr", .match_type = .exact, .kind = .network_io, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Reverse DNS lookup (deprecated) - returns static pointer" },
    .{ .pattern = "inet_ntoa", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert IP to string - returns static buffer, not thread-safe" },
    .{ .pattern = "inet_ntop", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert binary IP to string - thread-safe version" },
    .{ .pattern = "inet_pton", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string IP to binary - returns -1 on error" },
    .{ .pattern = "setsockopt", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Set socket option - check return value for errors" },
    .{ .pattern = "getsockopt", .match_type = .exact, .kind = .network_io, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get socket option - check return value for errors" },
};

/// P2-1: Functions that return pointers to static buffers.
///
/// These functions return pointers to internal static storage that:
/// - Must NOT be freed (doing so is undefined behavior)
/// - May be overwritten by subsequent calls (not thread-safe)
/// - Should be copied if long-term retention is needed
///
/// Migrated from deleted `inferLifetimeConstraints` to preserve knowledge.
pub const static_buffer_functions = [_]types.FunctionSemantics{
    // Time functions - return pointer to static string buffer
    .{ .pattern = "ctime", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Time to string - returns static buffer, NOT thread-safe" },
    .{ .pattern = "ctime_r", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Time to string (reentrant) - user-provided buffer, thread-safe" },
    .{ .pattern = "asctime", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Time struct to string - returns static buffer, NOT thread-safe" },
    .{ .pattern = "asctime_r", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Time struct to string (reentrant) - user-provided buffer" },

    // Network functions - return static structs/buffers
    .{ .pattern = "inet_ntoa", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "IP to string - returns static buffer, use inet_ntop instead" },
    .{ .pattern = "gethostbyname", .match_type = .exact, .kind = .static_buffer, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "DNS lookup - returns static hostent, deprecated" },
    .{ .pattern = "gethostbyaddr", .match_type = .exact, .kind = .static_buffer, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Reverse DNS - returns static hostent, deprecated" },

    // User/Group database functions - return static buffers
    .{ .pattern = "getgrgid", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "GID to group name - returns static group struct" },
    .{ .pattern = "getgrnam", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Group name to GID - returns static group struct" },
    .{ .pattern = "getpwuid", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "UID to passwd entry - returns static passwd struct" },
    .{ .pattern = "getpwnam", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Username to passwd entry - returns static passwd struct" },

    // Error/terminal functions
    .{ .pattern = "strerror", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Error number to string - returns static buffer, use strerror_r instead" },
    .{ .pattern = "ttyname", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "FD to terminal name - returns static buffer path" },
    .{ .pattern = "ctermid", .match_type = .exact, .kind = .static_buffer, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Controlling terminal name - returns static buffer" },
};

test "posix_io_reg: file_io function count" {
    try std.testing.expectEqual(@as(usize, 10), file_io_functions.len);
}

test "posix_io_reg: network_io function count" {
    try std.testing.expectEqual(@as(usize, 19), network_io_functions.len);
}

test "posix_io_reg: fopen/fclose pairs" {
    inline for (file_io_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "fopen") or std.mem.eql(u8, name, "open")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
        if (std.mem.eql(u8, name, "fclose") or std.mem.eql(u8, name, "close")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}

test "posix_io_reg: socket/accept transfer ownership" {
    inline for (network_io_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "socket") or std.mem.eql(u8, name, "accept")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
    }
}

test "posix_io_reg: getaddrinfo/freeaddrinfo pairs" {
    inline for (network_io_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "getaddrinfo")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
        if (std.mem.eql(u8, name, "freeaddrinfo")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}

test "posix_io_reg: static_buffer_functions count" {
    // P2-1: Verify all known static buffer functions are registered
    try std.testing.expect(static_buffer_functions.len >= 14);
}

test "posix_io_reg: static_buffer key functions present" {
    // P2-1: Verify critical static buffer functions are included
    const expected = [_][]const u8{
        "ctime",    "asctime",  "inet_ntoa", "gethostbyname",
        "getgrgid", "getpwuid", "strerror",  "ttyname",
    };

    var found_count: usize = 0;
    for (expected) |func_name| {
        for (static_buffer_functions) |entry| {
            if (std.mem.eql(u8, func_name, entry.pattern)) {
                found_count += 1;
                // Verify they have correct semantics
                try std.testing.expectEqual(@as(bool, false), entry.transfers_ownership);
                try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
                break;
            }
        }
    }

    try std.testing.expectEqual(expected.len, found_count);
}
