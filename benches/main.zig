//! Benchmarks for OmniScope
//!
//! Run with: zig build bench-perf

const std = @import("std");
const builtin = @import("builtin");

// Import via module
const OmniScope = @import("OmniScope");

// Re-export types for convenience
const lifetime = OmniScope.lifetime;
const registry = OmniScope.registry;
const mapper = OmniScope.lifetime;

// Benchmark helper
fn benchmark(comptime name: []const u8, comptime func: fn () void, iterations: usize) !void {
    if (builtin.mode != .ReleaseFast) {
        std.debug.print("WARNING: Run benchmarks with -Doptimize=ReleaseFast\n", .{});
    }

    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        func();
    }
    const end = std.time.nanoTimestamp();

    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const elapsed_ms = elapsed_ns / 1_000_000.0;
    const per_iter_ns = elapsed_ns / @as(f64, @floatFromInt(iterations));

    std.debug.print("{s}: {d:.2}ms total, {d:.2}ns/iter ({d} iterations)\n", .{
        name,
        elapsed_ms,
        per_iter_ns,
        iterations,
    });
}

// ========================================
// Lifetime Engine Benchmarks
// ========================================

fn benchLifetimeEngineInit() void {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    engine.deinit();
}

fn benchLifetimeEngineAlloc() void {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();
    _ = engine.applyAction(.alloc, "test_func", null, null);
}

fn benchLifetimeEngineFullCycle() void {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();

    // Full lifecycle: alloc -> use -> free
    const id = engine.applyAction(.alloc, "test_func", null, null) orelse return;
    _ = engine.applyActionToResource(id, .free, null);
}

fn benchLifetimeEngineDetectLeaks() void {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();

    // Create 100 resources
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = engine.applyAction(.alloc, "test_func", null, null);
    }

    engine.detectLeaks();
}

// ========================================
// Semantic Registry Benchmarks
// ========================================

fn benchRegistryLookup() void {
    _ = registry.SemanticRegistry.lookup("malloc");
}

fn benchRegistryLookupUnknown() void {
    _ = registry.SemanticRegistry.lookup("unknown_function_name");
}

fn benchRegistryIsKnown() void {
    _ = registry.SemanticRegistry.isKnown("free");
}

fn benchRegistryGetSeverity() void {
    _ = registry.SemanticRegistry.getSeverity("system");
}

// ========================================
// Semantic Mapper Benchmarks
// ========================================

fn benchMapperMapFunction() void {
    _ = mapper.SemanticMapper.mapFunction("malloc");
}

fn benchMapperMapRustFunction() void {
    _ = mapper.SemanticMapper.mapFunction("std::boxed::Box<T>::into_raw");
}

fn benchMapperIsAllocation() void {
    _ = mapper.SemanticMapper.isAllocation("malloc");
}

fn benchMapperIsDeallocation() void {
    _ = mapper.SemanticMapper.isDeallocation("free");
}

// ========================================
// Run All Benchmarks
// ========================================

test "bench: Lifetime Engine" {
    std.debug.print("\n=== Lifetime Engine Benchmarks ===\n", .{});

    try benchmark("Engine Init", benchLifetimeEngineInit, 10000);
    try benchmark("Engine Alloc", benchLifetimeEngineAlloc, 10000);
    try benchmark("Engine Full Cycle", benchLifetimeEngineFullCycle, 10000);
    try benchmark("Engine Detect Leaks (100)", benchLifetimeEngineDetectLeaks, 100);
}

test "bench: Semantic Registry" {
    std.debug.print("\n=== Semantic Registry Benchmarks ===\n", .{});

    try benchmark("Registry Lookup (known)", benchRegistryLookup, 100000);
    try benchmark("Registry Lookup (unknown)", benchRegistryLookupUnknown, 100000);
    try benchmark("Registry IsKnown", benchRegistryIsKnown, 100000);
    try benchmark("Registry GetSeverity", benchRegistryGetSeverity, 100000);
}

test "bench: Semantic Mapper" {
    std.debug.print("\n=== Semantic Mapper Benchmarks ===\n", .{});

    try benchmark("Mapper MapFunction (C)", benchMapperMapFunction, 100000);
    try benchmark("Mapper MapFunction (Rust)", benchMapperMapRustFunction, 100000);
    try benchmark("Mapper IsAllocation", benchMapperIsAllocation, 100000);
    try benchmark("Mapper IsDeallocation", benchMapperIsDeallocation, 100000);
}

test "bench: Memory Usage" {
    std.debug.print("\n=== Memory Usage ===\n", .{});

    // Measure memory for Lifetime Engine with 1000 resources
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = engine.applyAction(.alloc, "test_func", null, null);
    }

    const stats = engine.getStats();
    std.debug.print("Resources tracked: {}\n", .{stats.total_resources});
    std.debug.print("Issues detected: {}\n", .{stats.issue_count});
}
