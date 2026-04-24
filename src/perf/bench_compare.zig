//! Performance Comparison Benchmark
//!
//! Compares performance with and without optimizations.

const std = @import("std");
const Allocator = std.mem.Allocator;

const perf = @import("mod.zig");
const AnalysisContext = perf.AnalysisContext;
const MemoryPool = perf.MemoryPool;
const Profiler = perf.Profiler;
const Timer = perf.Timer;

/// Benchmark result
const BenchResult = struct {
    name: []const u8,
    total_ns: u64,
    iterations: usize,
    avg_ns: f64,

    fn avgUs(self: *const BenchResult) f64 {
        return self.avg_ns / 1000.0;
    }

    fn avgMs(self: *const BenchResult) f64 {
        return self.avgUs() / 1000.0;
    }
};

/// Run standard allocation benchmark
fn benchStandardAlloc(allocator: Allocator, iterations: usize) !BenchResult {
    const timer = try Timer.start();
    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = timer.start_time;
        const ptr = try allocator.create(u64);
        ptr.* = @intCast(i);
        allocator.destroy(ptr);
        const end = std.time.Instant.now() catch break;
        total_ns += end.since(start);
    }

    return .{
        .name = "standard_alloc",
        .total_ns = total_ns,
        .iterations = iterations,
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
    };
}

/// Run memory pool benchmark
fn benchMemoryPool(allocator: Allocator, iterations: usize) !BenchResult {
    var pool = try MemoryPool(u64).init(allocator);
    defer pool.deinit();

    const timer = try Timer.start();
    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = timer.start_time;
        const ptr = try pool.alloc();
        ptr.* = @intCast(i);
        pool.free(ptr);
        const end = std.time.Instant.now() catch break;
        total_ns += end.since(start);
    }

    return .{
        .name = "memory_pool",
        .total_ns = total_ns,
        .iterations = iterations,
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
    };
}

/// Run arena allocation benchmark
fn benchArenaAlloc(allocator: Allocator, iterations: usize) !BenchResult {
    var ctx = try AnalysisContext.init(allocator);
    defer ctx.deinit();

    const timer = try Timer.start();
    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = timer.start_time;
        const ptr = try ctx.create(u64);
        ptr.* = @intCast(i);
        const end = std.time.Instant.now() catch break;
        total_ns += end.since(start);
    }

    return .{
        .name = "arena_alloc",
        .total_ns = total_ns,
        .iterations = iterations,
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
    };
}

/// Run HashMap benchmark (standard)
fn benchHashMapStandard(allocator: Allocator, iterations: usize) !BenchResult {
    var map = std.AutoHashMap(u32, u64).init(allocator);
    defer map.deinit();

    const timer = try Timer.start();
    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = timer.start_time;
        try map.put(@intCast(i), @intCast(i * 2));
        const end = std.time.Instant.now() catch break;
        total_ns += end.since(start);
    }

    return .{
        .name = "hashmap_standard",
        .total_ns = total_ns,
        .iterations = iterations,
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
    };
}

/// Run HashMap benchmark (arena-backed)
fn benchHashMapArena(allocator: Allocator, iterations: usize) !BenchResult {
    var ctx = try AnalysisContext.init(allocator);
    defer ctx.deinit();

    const arena_alloc = ctx.arenaAllocator();
    var map = std.AutoHashMap(u32, u64).init(arena_alloc);
    defer map.deinit();

    const timer = try Timer.start();
    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = timer.start_time;
        try map.put(@intCast(i), @intCast(i * 2));
        const end = std.time.Instant.now() catch break;
        total_ns += end.since(start);
    }

    return .{
        .name = "hashmap_arena",
        .total_ns = total_ns,
        .iterations = iterations,
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
    };
}

/// Print comparison report
fn printComparison(name: []const u8, standard: BenchResult, optimized: BenchResult) void {
    const speedup = standard.avg_ns / optimized.avg_ns;
    const improvement = ((standard.avg_ns - optimized.avg_ns) / standard.avg_ns) * 100;

    std.debug.print("\n{s}:\n", .{name});
    std.debug.print("  Standard: {d:.2} ns/iter\n", .{standard.avg_ns});
    std.debug.print("  Optimized: {d:.2} ns/iter\n", .{optimized.avg_ns});
    std.debug.print("  Speedup: {d:.2}x ({d:.1}% faster)\n", .{ speedup, improvement });
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const iterations = 10000;

    std.debug.print("\n╔════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           PERFORMANCE OPTIMIZATION COMPARISON                  ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\nIterations: {d}\n", .{iterations});

    // Allocation comparison
    std.debug.print("\n=== Allocation Performance ===\n", .{});
    const std_alloc = try benchStandardAlloc(allocator, iterations);
    const pool_alloc = try benchMemoryPool(allocator, iterations);
    const arena_alloc = try benchArenaAlloc(allocator, iterations);

    printComparison("Memory Pool", std_alloc, pool_alloc);
    printComparison("Arena Allocator", std_alloc, arena_alloc);

    // HashMap comparison
    std.debug.print("\n=== HashMap Performance ===\n", .{});
    const std_hashmap = try benchHashMapStandard(allocator, iterations);
    const arena_hashmap = try benchHashMapArena(allocator, iterations);

    printComparison("Arena HashMap", std_hashmap, arena_hashmap);

    // Summary
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Memory Pool speedup: {d:.2}x\n", .{std_alloc.avg_ns / pool_alloc.avg_ns});
    std.debug.print("Arena Allocator speedup: {d:.2}x\n", .{std_alloc.avg_ns / arena_alloc.avg_ns});
    std.debug.print("Arena HashMap speedup: {d:.2}x\n", .{std_hashmap.avg_ns / arena_hashmap.avg_ns});

    std.debug.print("\n╔════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                   BENCHMARK COMPLETE                           ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════════╝\n", .{});
}

test "bench standard alloc" {
    const result = try benchStandardAlloc(std.testing.allocator, 100);
    try std.testing.expect(result.avg_ns > 0);
}

test "bench memory pool" {
    const result = try benchMemoryPool(std.testing.allocator, 100);
    try std.testing.expect(result.avg_ns > 0);
}

test "bench arena alloc" {
    const result = try benchArenaAlloc(std.testing.allocator, 100);
    try std.testing.expect(result.avg_ns > 0);
}
