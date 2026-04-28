const std = @import("std");
const types = @import("types.zig");

pub const layer3_functions = [_]types.FunctionSemantics{
    .{ .pattern = "C.malloc", .match_type = .contains, .kind = .go_cgo_alloc, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Go cgo malloc - must free with C.free, not Go GC" },
    .{ .pattern = "C.CString", .match_type = .contains, .kind = .go_cgo_alloc, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Go cgo CString - caller must free with C.free" },
    .{ .pattern = "C.CBytes", .match_type = .contains, .kind = .go_cgo_alloc, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Go cgo CBytes - caller must free with C.free" },
    .{ .pattern = "C.free", .match_type = .contains, .kind = .go_cgo_alloc, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Go cgo free - frees C memory, not managed by Go GC" },
};

test "layer3_reg: function count" {
    try std.testing.expectEqual(@as(usize, 4), layer3_functions.len);
}

test "layer3_reg: C.malloc/C.free pairs" {
    inline for (layer3_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "C.malloc") or std.mem.eql(u8, name, "C.CString") or std.mem.eql(u8, name, "C.CBytes")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
        }
        if (std.mem.eql(u8, name, "C.free")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}
