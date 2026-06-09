//! Escape Analysis for identifying objects whose lifetimes are confined to
//! the current function scope (non-escaping allocations are safe).
//!
//! Key insight: If an allocation does NOT escape, any "leak" report is a FP.

const std = @import("std");
const log = @import("../common/log.zig");

pub const EscapeAnalysis = struct {
    allocator: std.mem.Allocator,

    /// Results cache per instruction address
    escape_status: std.AutoHashMap(u64, EscapeStatus),

    pub const EscapeStatus = enum {
        no_escape,
        escapes_arg,
        escapes_return,
        escapes_global,
        escapes_call,
        unknown,
    };

    pub fn init(allocator: std.mem.Allocator) EscapeAnalysis {
        return .{
            .allocator = allocator,
            .escape_status = std.AutoHashMap(u64, EscapeStatus).init(allocator),
        };
    }

    pub fn deinit(self: *EscapeAnalysis) void {
        self.escape_status.deinit();
    }

    pub fn analyzeEscape(
        self: *EscapeAnalysis,
        alloc_inst: u64,
        func_value: *anyopaque,
        graph: *anyopaque,
    ) !EscapeStatus {
        _ = func_value;
        _ = graph;

        if (self.escape_status.get(alloc_inst)) |cached| {
            return cached;
        }

        const status = EscapeStatus.unknown;

        try self.escape_status.put(alloc_inst, status);

        return status;
    }

    pub fn isNonEscaping(self: *EscapeAnalysis, alloc_inst: u64) bool {
        const status = self.escape_status.get(alloc_inst) orelse return false;
        return status == .no_escape;
    }

    pub fn shouldSuppressLeakReport(
        self: *EscapeAnalysis,
        alloc_inst: u64,
    ) bool {
        const status = self.escape_status.get(alloc_inst) orelse return false;

        if (status == .no_escape) {
            log.debug("ESCAPE: Suppressing leak for non-escaping alloc 0x{x}", .{alloc_inst});
            return true;
        }

        return false;
    }
};

test "EscapeAnalysis - basic functionality" {
    var ea = EscapeAnalysis.init(std.testing.allocator);
    defer ea.deinit();

    try std.testing.expectEqual(false, ea.isNonEscaping(12345));
}
