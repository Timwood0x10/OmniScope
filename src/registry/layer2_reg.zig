const std = @import("std");
const types = @import("types.zig");

pub const layer2_functions = [_]types.FunctionSemantics{
    .{ .pattern = "into_raw", .match_type = .contains, .kind = .rust_ownership, .severity = .high, .consumes_ownership = true, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Rust ownership transfer OUT - caller must free correctly" },
    .{ .pattern = "from_raw", .match_type = .contains, .kind = .rust_ownership, .severity = .high, .consumes_ownership = true, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Rust ownership transfer IN - Rust takes responsibility" },
    .{ .pattern = "as_ptr", .match_type = .contains, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Borrow escape - pointer valid only while Rust owns it" },
};

test "layer2_reg: function count" {
    try std.testing.expectEqual(@as(usize, 3), layer2_functions.len);
}

test "layer2_reg: into_raw/from_raw transfer ownership" {
    inline for (layer2_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "into_raw") or std.mem.eql(u8, name, "from_raw")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}
