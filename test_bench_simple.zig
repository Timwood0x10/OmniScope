const std = @import("std");
const OmniScope = @import("src/root.zig");

pub fn main() !void {
    std.debug.print("Testing cross_lang imports...\n", .{});

    // Test TaintContext
    var ctx = OmniScope.cross_lang.TaintContext.init(std.heap.page_allocator);
    defer ctx.deinit();

    const info = OmniScope.cross_lang.TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.9,
    };
    try ctx.setValueTaint(100, info);

    std.debug.print("TaintContext test passed\n", .{});

    // Test FFIBoundaryDetector
    var detector = OmniScope.cross_lang.FFIBoundaryDetector.init(std.heap.page_allocator);
    defer detector.deinit();

    const is_ffi = detector.isFFICall("rust_function");
    std.debug.print("FFIBoundaryDetector test passed: {}\n", .{is_ffi});

    // Test FlowPath
    var path = OmniScope.cross_lang.FlowPath.init();
    defer path.deinit(std.heap.page_allocator);

    const step = OmniScope.cross_lang.FlowStep{
        .id = 1,
        .func_name = "test",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.9,
    };
    try path.addStep(std.heap.page_allocator, step);

    std.debug.print("FlowPath test passed\n", .{});

    // Test classifyRiskLevel
    const risk = OmniScope.cross_lang.classifyRiskLevel("system");
    std.debug.print("classifyRiskLevel test passed: {}\n", .{risk});

    std.debug.print("All tests passed!\n", .{});
}
