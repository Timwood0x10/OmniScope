const std = @import("std");

// Compiler protection to prevent over-optimization
fn consumeValue(comptime T: type, value: T) void {
    // Use inline assembly to prevent compiler from optimizing away the result
    var sink: T = value;
    asm volatile (""
        : [output] "=r" (sink),
    );
}

pub fn main() !void {
    std.debug.print("Testing consumeValue function...\n", .{});

    // Test with various types
    consumeValue(usize, 42);
    consumeValue(bool, true);
    consumeValue(f32, 3.14);

    const struct_val = struct { x: i32, y: i32 }{ .x = 1, .y = 2 };
    consumeValue(@TypeOf(struct_val), struct_val);

    std.debug.print("consumeValue test passed!\n", .{});
}
