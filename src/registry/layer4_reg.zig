const std = @import("std");
const types = @import("types.zig");

pub const layer4_functions = [_]types.FunctionSemantics{
    .{ .pattern = "withUnsafeBytes", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Swift unsafe bytes access - pointer valid only in closure" },
    .{ .pattern = "withUnsafeMutableBytes", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Swift unsafe mutable bytes - pointer valid only in closure" },
    .{ .pattern = "UnsafeMutablePointer", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Swift unsafe pointer allocation - must deallocate" },
    .{ .pattern = "unsafeBitCast", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Swift unsafe bit cast - reinterpretation without ownership change" },
    .{ .pattern = "UnsafeRawPointer", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Swift raw pointer initialization - caller owns memory" },
    .{ .pattern = "withExtendedLifetime", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Swift extended lifetime - temporary lifetime extension" },
    .{ .pattern = "Unmanaged", .match_type = .contains, .kind = .rust_ownership, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Swift Unmanaged - manual reference counting, transfer ownership" },
    .{ .pattern = "autoreleasepool", .match_type = .contains, .kind = .borrow_escaped, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Swift autorelease pool - temporary memory management" },
};

test "layer4_reg: function count" {
    try std.testing.expectEqual(@as(usize, 8), layer4_functions.len);
}

test "layer4_reg: UnsafeMutablePointer transfers ownership" {
    inline for (layer4_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "UnsafeMutablePointer")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
    }
}
