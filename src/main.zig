const std = @import("std");
const OmniScope = @import("OmniScope");

pub fn main() !void {
    std.debug.print("OmniScope - Universal LLVM Analysis Framework\n", .{});
    std.debug.print("Usage: omniscope [options] <input.bc>\n", .{});
}
