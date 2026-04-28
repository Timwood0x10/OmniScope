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
