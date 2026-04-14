//! Taint Propagation Analysis Pass
//!
//! Performs forward taint propagation to identify functions that may be
//! influenced by dangerous inputs (sources).

const std = @import("std");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

/// Re-exports SOURCE_FUNCTIONS from call_graph module.
/// These functions are considered sources of taint.
pub const SOURCE_FUNCTIONS = call_graph.SOURCE_FUNCTIONS;

/// Error type for taint propagation operations.
pub const TaintError = error{
    /// Memory allocation failed.
    OutOfMemory,
};

/// Taint propagation analysis pass.
///
/// This pass performs forward taint propagation through the call graph.
/// It depends on the call-graph pass for the graph structure.
///
/// Note: Currently a placeholder pass that delegates to call-graph
/// for actual taint propagation implementation.
pub const TaintPropagationPass = struct {
    pub const name = "taint-propagation";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(_: *PassContext, diag: *DiagnosticWriter) TaintError!void {
        diag.info("pass registered (stateless)", .{});
    }
};

test "SOURCE_FUNCTIONS - contains main" {
    var found_main = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found_main = true;
            break;
        }
    }
    try std.testing.expect(found_main);
}

test "SOURCE_FUNCTIONS - contains read" {
    var found_read = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "read")) {
            found_read = true;
            break;
        }
    }
    try std.testing.expect(found_read);
}

test "SOURCE_FUNCTIONS - all non-empty" {
    for (SOURCE_FUNCTIONS) |s| {
        try std.testing.expect(s.len > 0);
    }
}

test "SOURCE_FUNCTIONS - has expected sources" {
    const expected = &[_][]const u8{ "main", "read", "recv", "gets", "scanf" };
    for (expected) |exp| {
        var found = false;
        for (SOURCE_FUNCTIONS) |s| {
            if (std.mem.eql(u8, s, exp)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "SOURCE_FUNCTIONS - no duplicates" {
    for (SOURCE_FUNCTIONS, 0..) |s1, i| {
        for (SOURCE_FUNCTIONS, 0..) |s2, j| {
            if (i != j and std.mem.eql(u8, s1, s2)) {
                try std.testing.expect(false);
            }
        }
    }
}

test "TaintError - error type exists" {
    const err = TaintError.OutOfMemory;
    try std.testing.expect(err == TaintError.OutOfMemory);
}

test "TaintPropagationPass - name" {
    try std.testing.expectEqualStrings("taint-propagation", TaintPropagationPass.name);
}

test "TaintPropagationPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, TaintPropagationPass.kind);
}

test "TaintPropagationPass - deps" {
    try std.testing.expectEqual(@as(usize, 1), TaintPropagationPass.deps.len);
    try std.testing.expectEqualStrings("call-graph", TaintPropagationPass.deps[0]);
}
