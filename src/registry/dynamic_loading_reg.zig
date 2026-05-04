const std = @import("std");
const types = @import("types.zig");

pub const dynamic_loading_functions = [_]types.FunctionSemantics{
    .{ .pattern = "dlopen", .match_type = .exact, .kind = .dynamic_loading, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Open dynamic library - returns handle, must dlclose to release" },
    .{ .pattern = "dlsym", .match_type = .exact, .kind = .dynamic_loading, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get symbol from dynamic library - returns pointer, invalid after dlclose" },
    .{ .pattern = "dlclose", .match_type = .exact, .kind = .dynamic_loading, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Close dynamic library - invalidates symbols from dlsym" },
    .{ .pattern = "dlerror", .match_type = .exact, .kind = .dynamic_loading, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get dynamic loading error message" },
};

test "dynamic_loading_reg: function count" {
    try std.testing.expectEqual(@as(usize, 4), dynamic_loading_functions.len);
}

test "dynamic_loading_reg: dlopen/dlclose pairs" {
    inline for (dynamic_loading_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "dlopen")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "dlclose")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.transfers_ownership);
        }
    }
}
