//! FFI Boundary Detection Pass
//!
//! Marks cross-language transitions in the call graph.
//! Only external_unknown is considered a true FFI boundary (not libc).

const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

/// Error type for FFI boundary detection operations.
pub const FFIBoundaryError = error{
    /// Memory allocation failed.
    OutOfMemory,
};

/// Represents an FFI boundary edge in the call graph.
/// An FFI edge indicates a cross-language call transition.
pub const FFIEdge = struct {
    /// ID of the caller function (in the current language/module).
    caller: u32,
    /// ID of the callee function (in a different language/module).
    callee: u32,
};

/// FFI boundary detection pass.
///
/// Identifies cross-language transitions in the call graph.
/// An FFI boundary is detected when:
/// - Callee is external_unknown (not libc)
/// - Indicates a call from analyzed code to unknown external code
///
/// Note: Currently a placeholder pass.
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

test "FFIEdge - edge case values" {
    const edge1 = FFIEdge{ .caller = 0, .callee = 0 };
    try std.testing.expectEqual(edge1.caller, edge1.callee);

    const edge2 = FFIEdge{ .caller = 100, .callee = 200 };
    try std.testing.expect(edge2.caller < edge2.callee);
}

test "FFIEdge - max values" {
    const edge = FFIEdge{ .caller = std.math.maxInt(u32), .callee = std.math.maxInt(u32) };
    try std.testing.expectEqual(@as(u32, 0), edge.caller - 1);
    try std.testing.expectEqual(@as(u32, 0), edge.callee - 1);
}

test "FFIEdge - self-loop" {
    const edge = FFIEdge{ .caller = 5, .callee = 5 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "FFIEdge - caller before callee" {
    const edge = FFIEdge{ .caller = 1, .callee = 2 };
    try std.testing.expect(edge.caller < edge.callee);
}

test "FFIBoundaryError - error type exists" {
    const err = FFIBoundaryError.OutOfMemory;
    try std.testing.expect(err == FFIBoundaryError.OutOfMemory);
}

test "FFIBoundaryPass - name" {
    try std.testing.expectEqualStrings("ffi-boundary", FFIBoundaryPass.name);
}

test "FFIBoundaryPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, FFIBoundaryPass.kind);
}

test "FFIBoundaryPass - deps" {
    try std.testing.expectEqual(@as(usize, 1), FFIBoundaryPass.deps.len);
    try std.testing.expectEqualStrings("call-graph", FFIBoundaryPass.deps[0]);
}

test "FFIBoundaryPass - deps not empty" {
    try std.testing.expect(FFIBoundaryPass.deps.len > 0);
}

test "FFIBoundaryPass - deps valid strings" {
    for (FFIBoundaryPass.deps) |dep| {
        try std.testing.expect(dep.len > 0);
    }
}
