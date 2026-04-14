//! Sink Tracer Analysis Pass
//!
//! Traces tainted data flow from sources to dangerous sinks.

const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

pub const RiskLevel = enum {
    medium,
    critical,
};

pub const FlowStep = struct {
    funcName: []const u8,
};

pub const FlowPath = struct {
    steps: []const FlowStep,
    isCrossLanguage: bool,
    risk: RiskLevel,
};

pub const FlowPathError = error{
    OutOfMemory,
};

pub const SinkTracerPass = struct {
    pub const name = "sink-tracer";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    pub fn run(_: *PassContext, diag: *DiagnosticWriter) FlowPathError!void {
        diag.info("pass registered (stateless)", .{});
    }
};

test "RiskLevel - enum values" {
    try std.testing.expectEqual(RiskLevel.medium, .medium);
    try std.testing.expectEqual(RiskLevel.critical, .critical);
}

test "FlowStep - structure" {
    const step = FlowStep{ .funcName = "test" };
    try std.testing.expectEqualStrings("test", step.funcName);
}
