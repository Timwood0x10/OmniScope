const std = @import("std");
const types = @import("types.zig");

pub const layer4_functions = [_]types.FunctionSemantics{
    .{ .pattern = "Span", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "C# Span<T> - safe slice view, bounds checked" },
    .{ .pattern = "MemoryMarshal", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "C# MemoryMarshal - low-level memory operations, pointer valid only in scope" },
    .{ .pattern = "unsafe", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "C# unsafe context - pointer arithmetic and pinning" },
    .{ .pattern = "BitConverter", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "C# BitConverter - type reinterpretation without ownership change" },
    .{ .pattern = "Marshal", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "C# Marshal - interop memory allocation, caller must free" },
    .{ .pattern = "IntPtr", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "C# IntPtr - platform-specific integer as pointer, caller owns memory" },
    .{ .pattern = "GCHandle", .match_type = .contains, .kind = .rust_ownership, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "C# GCHandle - manual GC handle management, transfer ownership" },
    .{ .pattern = "GC.KeepAlive", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "C# GC.KeepAlive - object lifetime extension until this point" },
};

test "layer4_reg: function count" {
    try std.testing.expectEqual(@as(usize, 8), layer4_functions.len);
}

test "layer4_reg: Marshal transfers ownership" {
    inline for (layer4_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "Marshal")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
    }
}
