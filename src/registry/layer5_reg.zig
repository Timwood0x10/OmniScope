const std = @import("std");
const types = @import("types.zig");

pub const layer5_functions = [_]types.FunctionSemantics{
    .{ .pattern = "GeneralPurposeAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig GPA - requires deinit to release memory" },
    .{ .pattern = "ArenaAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig arena allocator - requires deinit to release all memory" },
    .{ .pattern = "FixedBufferAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig fixed buffer allocator - stack-allocated memory" },
    .{ .pattern = "pageAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig page allocator - system memory allocation" },
    .{ .pattern = ".alloc(", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zig allocator alloc - method call form" },
    .{ .pattern = "allocator.alloc", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zig allocator alloc - field access form" },
    .{ .pattern = ".create(", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zig allocator create - method call form" },
    .{ .pattern = "allocator.create", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Zig allocator create - field access form" },
    .{ .pattern = ".destroy(", .match_type = .contains, .kind = .zig_allocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig allocator destroy - method call form" },
    .{ .pattern = "allocator.destroy", .match_type = .contains, .kind = .zig_allocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig allocator destroy - field access form" },
    .{ .pattern = ".free(", .match_type = .contains, .kind = .zig_allocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig allocator free - method call form" },
    .{ .pattern = "allocator.free", .match_type = .contains, .kind = .zig_allocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig allocator free - field access form" },
    .{ .pattern = "ArrayList", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig ArrayList - requires deinit to free internal memory" },
    .{ .pattern = "HashMap", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig HashMap - requires deinit to free internal memory" },
    .{ .pattern = "AutoHashMap", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig AutoHashMap - requires deinit to free internal memory" },
    .{ .pattern = "StringHashMap", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig StringHashMap - requires deinit to free internal memory" },
    .{ .pattern = "std.mem.allocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig std.mem - allocation functions require pairing with free" },
    .{ .pattern = "std.heap", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig std.heap - heap allocation primitives" },
    .{ .pattern = ".?", .match_type = .suffix, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Zig optional unwrap - requires null check" },
    .{ .pattern = ".!|", .match_type = .suffix, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig error union - requires error check" },
    .{ .pattern = "@ptrCast", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig ptr cast - pointer type conversion" },
    .{ .pattern = "@intToPtr", .match_type = .contains, .kind = .borrow_escaped, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig intToPtr - integer to pointer conversion" },
    .{ .pattern = "@ptrToInt", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig ptrToInt - pointer to integer conversion" },
    .{ .pattern = "SliceAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig SliceAllocator - allocator for slice operations" },
    .{ .pattern = "LoggingAllocator", .match_type = .contains, .kind = .zig_allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig LoggingAllocator - wraps another allocator for debugging" },
    .{ .pattern = "sentinel", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig sentinel terminated - memory with sentinel value" },
    .{ .pattern = "threadlocal", .match_type = .contains, .kind = .zig_allocator, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Zig threadlocal - thread-local memory allocation" },
    .{ .pattern = "c_allocator", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig c_allocator - libc malloc wrapper for C interoperability" },
    .{ .pattern = "rawSliceAlloc", .match_type = .contains, .kind = .zig_allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Zig rawSliceAlloc - low-level slice allocation" },
};

test "layer5_reg: function count" {
    try std.testing.expectEqual(@as(usize, 29), layer5_functions.len);
}

test "layer5_reg: allocator functions transfer ownership" {
    inline for (layer5_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.indexOf(u8, name, "Allocator") != null) {
            if (std.mem.indexOf(u8, name, "destroy") == null and std.mem.indexOf(u8, name, "free") == null) {
                try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            }
        }
    }
}
