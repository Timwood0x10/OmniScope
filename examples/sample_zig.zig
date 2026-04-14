// Zig example - memory safety built into the language
const std = @import("std");

fn stackAllocation() i32 {
    const x: i32 = 5;
    return x;
}

fn heapAllocation() !void {
    const allocator = std.heap.page_allocator;
    const memory = try allocator.alloc(u8, 100);
    defer allocator.free(memory);
    std.debug.print("Allocated {d} bytes\n", .{memory.len});
}

fn optionalReturn() ?i32 {
    return null;
}

fn errorReturn() !i32 {
    return error.OutOfMemory;
}

pub fn main() void {
    const x = stackAllocation();
    std.debug.print("Stack value: {d}\n", .{x});

    heapAllocation() catch |err| {
        std.debug.print("Allocation failed: {}\n", .{err});
    };

    if (optionalReturn()) |val| {
        std.debug.print("Got value: {d}\n", .{val});
    } else {
        std.debug.print("Got null\n", .{});
    }

    std.debug.print("Done\n", .{});
}
