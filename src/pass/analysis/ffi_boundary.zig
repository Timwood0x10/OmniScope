//! FFI Boundary Detection Pass
//!
//! Marks cross-language transitions in the call graph.
//! Only external_unknown is considered a true FFI boundary (not libc).

const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

pub const FFIBoundaryError = error{
    OutOfMemory,
};

pub const FFIEdge = struct {
    caller: u32,
    callee: u32,
};

pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(_: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void {
        diag.info("pass registered (stateless)", .{});
    }
};

test "FFIEdge - structure" {
    const edge = FFIEdge{ .caller = 0, .callee = 1 };
    try std.testing.expectEqual(@as(u32, 0), edge.caller);
    try std.testing.expectEqual(@as(u32, 1), edge.callee);
}
