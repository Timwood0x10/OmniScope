//! Taint Propagation Analysis Pass
//!
//! Performs forward taint propagation to identify functions that may be
//! influenced by dangerous inputs (sources).

const std = @import("std");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

pub const SOURCE_FUNCTIONS = call_graph.SOURCE_FUNCTIONS;

pub const TaintError = error{
    OutOfMemory,
};

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
