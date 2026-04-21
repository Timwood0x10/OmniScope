// Zig test: Comptime and async patterns
const std = @import("std");

fn factorial(n: u32) u32 {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

fn fibonacci(n: u32) u32 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

fn sum_array(arr: []const u32) u32 {
    var sum: u32 = 0;
    for (arr) |val| {
        sum += val;
    }
    return sum;
}

pub fn main() void {
    const nums = [_]u32{ 1, 2, 3, 4, 5 };
    const fact = factorial(5);
    const fib = fibonacci(10);
    const sum = sum_array(&nums);
    std.debug.print("Result: {}\n", .{fact + fib + sum});
}
