const std = @import("std");
const types = @import("types.zig");

pub const layer1_functions = [_]types.FunctionSemantics{
    .{ .pattern = "system", .match_type = .suffix, .kind = .command_exec, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Execute shell command - command injection risk" },
    .{ .pattern = "popen", .match_type = .suffix, .kind = .command_exec, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Open pipe to process - command injection risk" },
    .{ .pattern = "strcpy", .match_type = .contains, .kind = .unchecked_copy, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Unchecked string copy - buffer overflow risk" },
    .{ .pattern = "strcat", .match_type = .contains, .kind = .unchecked_copy, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Unchecked string concatenate - buffer overflow risk" },
    .{ .pattern = "sprintf", .match_type = .contains, .kind = .unchecked_copy, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Unchecked formatted print - buffer overflow risk" },
    .{ .pattern = "vsprintf", .match_type = .contains, .kind = .unchecked_copy, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Unchecked formatted print (va_list) - buffer overflow risk" },
    .{ .pattern = "gets", .match_type = .exact, .kind = .unchecked_copy, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Read line without bounds - CRITICAL buffer overflow" },
    .{ .pattern = "memcpy", .match_type = .exact, .kind = .unchecked_copy, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Memory copy - requires correct size argument" },
    .{ .pattern = "__memcpy_chk", .match_type = .exact, .kind = .unchecked_copy, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Memory copy (fortified) - requires correct size argument" },
    .{ .pattern = "malloc", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Allocate memory - returns ownership, check for null" },
    .{ .pattern = "calloc", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Allocate zeroed memory - returns ownership, check for null" },
    .{ .pattern = "realloc", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = true, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Reallocate memory - consumes old, returns new ownership" },
    .{ .pattern = "malloc_zone_malloc", .match_type = .exact, .kind = .allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "macOS zone malloc - system allocator" },
    .{ .pattern = "malloc_zone_free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "macOS zone free - system deallocator" },
    .{ .pattern = "malloc_zone_realloc", .match_type = .exact, .kind = .allocator, .severity = .low, .consumes_ownership = true, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "macOS zone realloc - system reallocator" },
    .{ .pattern = "malloc_size", .match_type = .exact, .kind = .allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "macOS allocation size query - no ownership transfer" },
    .{ .pattern = "malloc_default_zone", .match_type = .exact, .kind = .allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "macOS default zone accessor - returns zone pointer" },
    .{ .pattern = "malloc_create_zone", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "macOS create allocation zone - caller must destroy with malloc_destroy_zone" },
    .{ .pattern = "free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Free memory - consumes ownership, cross-language mismatch risk" },
    .{ .pattern = "mmap", .match_type = .exact, .kind = .memory_map, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Map memory - returns ownership, must munmap to release" },
    .{ .pattern = "munmap", .match_type = .exact, .kind = .memory_map, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Unmap memory - consumes ownership, cross-language mismatch risk" },
    .{ .pattern = "mprotect", .match_type = .exact, .kind = .memory_map, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Change memory protection - can enable execution" },
    .{ .pattern = "printf", .match_type = .contains, .kind = .format_string, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Print formatted - format string vulnerability if user-controlled" },
    .{ .pattern = "EVP_CIPHER_CTX_new", .match_type = .exact, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL cipher context allocation" },
    .{ .pattern = "EVP_CIPHER_CTX_free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "OpenSSL cipher context deallocation" },
    .{ .pattern = "BIO_new", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL BIO allocation" },
    .{ .pattern = "BIO_free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "OpenSSL BIO deallocation" },
    .{ .pattern = "RSA_new", .match_type = .exact, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL RSA key allocation" },
    .{ .pattern = "RSA_free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "OpenSSL RSA key deallocation" },
    .{ .pattern = "SSL_CTX_new", .match_type = .exact, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL SSL context allocation" },
    .{ .pattern = "SSL_CTX_free", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "OpenSSL SSL context deallocation" },
    .{ .pattern = "X509_new", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL X509 certificate allocation" },
    .{ .pattern = "X509_free", .match_type = .exact, .kind = .deallocator, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "OpenSSL X509 certificate deallocation" },
    .{ .pattern = "PEM_read", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "OpenSSL PEM read (allocates object)" },
    .{ .pattern = "sqlite3_open", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "SQLite3 database connection allocation" },
    .{ .pattern = "sqlite3_close", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "SQLite3 database connection deallocation" },
    .{ .pattern = "sqlite3_prepare", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "SQLite3 prepared statement allocation" },
    .{ .pattern = "sqlite3_finalize", .match_type = .exact, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "SQLite3 prepared statement deallocation" },
    .{ .pattern = "inflateInit", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zlib inflate stream initialization (allocates state)" },
    .{ .pattern = "inflateEnd", .match_type = .exact, .kind = .deallocator, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zlib inflate stream cleanup (frees state)" },
    .{ .pattern = "deflateInit", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zlib deflate stream initialization (allocates state)" },
    .{ .pattern = "deflateEnd", .match_type = .exact, .kind = .deallocator, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zlib deflate stream cleanup (frees state)" },
    .{ .pattern = "gzopen", .match_type = .exact, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zlib gz file open (allocates handle)" },
    .{ .pattern = "gzclose", .match_type = .exact, .kind = .deallocator, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zlib gz file close (frees handle)" },
};

test "layer1_reg: function count" {
    try std.testing.expectEqual(@as(usize, 44), layer1_functions.len);
}

test "layer1_reg: critical functions exist" {
    inline for (layer1_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "system") or std.mem.eql(u8, name, "gets")) {
            try std.testing.expectEqual(types.Severity.critical, entry.severity);
        }
    }
}

test "layer1_reg: malloc/free pairs" {
    inline for (layer1_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "malloc") or std.mem.eql(u8, name, "calloc") or std.mem.eql(u8, name, "realloc")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
        if (std.mem.eql(u8, name, "free")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}
