const std = @import("std");
const types = @import("types.zig");
const ptr_types = @import("../pass/analysis/ptr_lifetime/ptr_lifetime_types.zig");

pub const layer2_functions = [_]types.FunctionSemantics{
    // Ownership transfer patterns (existing)
    .{ .pattern = "into_raw", .match_type = .contains, .kind = .rust_ownership, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Rust ownership transfer OUT - caller must free correctly" },
    .{ .pattern = "from_raw", .match_type = .contains, .kind = .rust_ownership, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Rust ownership transfer IN - Rust takes responsibility" },
    .{ .pattern = "as_ptr", .match_type = .suffix, .kind = .borrow_escaped, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Borrow escape - pointer valid only while Rust owns it (suffix match to avoid raw_as_ptr false positives)" },
    // Rust global allocator intrinsics (mangled as _RNv...__rust_alloc / _ZN5alloc...)
    // Using .contains match so mangled names like _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc match
    .{ .pattern = "__rust_alloc", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Rust global allocator (replaces malloc)" },
    .{ .pattern = "__rust_alloc_zeroed", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Rust global zeroed allocator (replaces calloc)" },
    .{ .pattern = "__rust_dealloc", .match_type = .contains, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Rust global deallocator (replaces free)" },
    .{ .pattern = "__rust_realloc", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Rust global reallocator (replaces realloc)" },
    .{ .pattern = "__rdl_alloc", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "DefaultGlobal allocator backend (alloc::alloc::Global)" },
    .{ .pattern = "__rdl_dealloc", .match_type = .contains, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "DefaultGlobal deallocator backend" },
    .{ .pattern = "__rg_alloc", .match_type = .contains, .kind = .allocator, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "System allocator backend" },
    .{ .pattern = "__rg_dealloc", .match_type = .contains, .kind = .deallocator, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "System deallocator backend" },
    .{ .pattern = "exchange_malloc", .match_type = .contains, .kind = .allocator, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Legacy exchange malloc (old rustc)" },
};

test "layer2_reg: function count" {
    try std.testing.expectEqual(@as(usize, 12), layer2_functions.len);
}

test "layer2_reg: into_raw/from_raw transfer ownership" {
    inline for (layer2_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "into_raw")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "from_raw")) {
            try std.testing.expectEqual(@as(bool, false), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}

test "layer2_reg: rust allocators have correct kind" {
    for (ptr_types.RUST_ALLOC_INTRINSICS.all) |pat| {
        var found = false;
        for (layer2_functions) |entry| {
            if (std.mem.eql(u8, entry.pattern, pat)) {
                found = true;
                if (std.mem.indexOf(u8, pat, "dealloc") != null) {
                    try std.testing.expectEqual(types.RiskKind.deallocator, entry.kind);
                } else {
                    try std.testing.expectEqual(types.RiskKind.allocator, entry.kind);
                }
            }
        }
        try std.testing.expectEqual(@as(bool, true), found);
    }
}
