//! Benchmarks for OmniScope
//!
//! Run with: zig build bench-perf

const std = @import("std");
const builtin = @import("builtin");

const OmniScope = @import("OmniScope");

const lifetime = OmniScope.lifetime;
const registry = OmniScope.registry;
const noise_reduction = OmniScope.noise_reduction;

fn benchmark(comptime name: []const u8, comptime func: fn () void, iterations: usize) !void {
    if (builtin.mode != .ReleaseFast) {
        std.log.warn("WARNING: Run benchmarks with -Doptimize=ReleaseFast\n", .{});
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

    const id = engine.applyAction(.alloc, "test_func", null, null) orelse return;
    _ = engine.applyActionToResource(id, .free, null);
}

fn benchLifetimeEngineDetectLeaks() void {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();

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
// NOTE: SemanticMapper removed as dead code (2026-05-04, see untodo.md DEAD-13)
// Replaced with SemanticRegistry benchmarks above
// ========================================

// ========================================
// Phase 4: Noise Reduction Benchmarks
// ========================================

fn benchNoiseLayer1FilterUserCode() void {
    _ = noise_reduction.layer1_NameBasedFilter("user_malloc_wrapper");
}

fn benchNoiseLayer1FilterRustStdlib() void {
    _ = noise_reduction.layer1_NameBasedFilter("core::ptr::drop_in_place");
}

fn benchNoiseLayer1FilterZigStdlib() void {
    _ = noise_reduction.layer1_NameBasedFilter("std.mem.Allocator");
}

fn benchNoiseLayer1FilterCppStl() void {
    _ = noise_reduction.layer1_NameBasedFilter("std::vector::push_back");
}

fn benchNoiseLayer2PathUser() void {
    _ = noise_reduction.layer2_PathBasedFilter("/home/user/project/src/main.c");
}

fn benchNoiseLayer2PathRustStdlib() void {
    _ = noise_reduction.layer2_PathBasedFilter("/rustc/1234567890/library/core/src/ptr.rs");
}

fn benchNoiseLayer2PathZigStdlib() void {
    _ = noise_reduction.layer2_PathBasedFilter("zig/lib/std/mem.zig");
}

fn benchNoiseClassifyUser() void {
    const config = noise_reduction.NoiseReductionConfig{};
    _ = noise_reduction.classifyFunction("my_ffi_bridge", null, config);
}

fn benchNoiseClassifyRustDropGlue() void {
    const config = noise_reduction.NoiseReductionConfig{};
    _ = noise_reduction.classifyFunction("drop_in_place", null, config);
}

fn benchNoiseClassifyZigAllocator() void {
    const config = noise_reduction.NoiseReductionConfig{};
    _ = noise_reduction.classifyFunction("std.mem.Allocator", null, config);
}

fn benchNoiseAttributionSummaryAdd() void {
    var summary = noise_reduction.AttributionSummary{};
    summary.addIssue(.user, "FFI_HIGH");
    summary.addIssue(.user, "FFI_CRITICAL");
    summary.addIssue(.stdlib, "MEMORY_LEAK");
}

fn benchNoiseAttributionSummaryPrint() void {
    var summary = noise_reduction.AttributionSummary{};
    summary.addIssue(.user, "FFI_HIGH");
    summary.addIssue(.user, "FFI_CRITICAL");
    summary.addIssue(.stdlib, "MEMORY_LEAK");
    summary.addIssue(.user, "USE_AFTER_FREE");
    summary.printReport();
}

fn benchRustDropGlueBehavior() void {
    _ = noise_reduction.isRustDropGlueBehavior(
        "core::ptr::drop_in_place",
        true,
        true,
        true,
        50,
    );
}

fn benchZigAllocatorWrapperBehavior() void {
    _ = noise_reduction.isZigAllocatorWrapperBehavior(
        "mem.Allocator.alloc",
        true,
        true,
        true,
    );
}

fn benchSTLVectorGrowBehavior() void {
    _ = noise_reduction.isSTLVectorGrowBehavior(
        "std::vector::_M_realloc",
        true,
        true,
        true,
    );
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

// NOTE: "bench: Semantic Mapper" test removed — SemanticMapper was dead code, removed 2026-05-04

test "bench: Phase 4 Noise Reduction - Layer 1" {
    std.debug.print("\n=== Phase 4: Noise Reduction (Layer 1 Name Filter) ===\n", .{});

    try benchmark("Layer1 Filter (user code)", benchNoiseLayer1FilterUserCode, 100000);
    try benchmark("Layer1 Filter (Rust stdlib)", benchNoiseLayer1FilterRustStdlib, 100000);
    try benchmark("Layer1 Filter (Zig stdlib)", benchNoiseLayer1FilterZigStdlib, 100000);
    try benchmark("Layer1 Filter (C++ STL)", benchNoiseLayer1FilterCppStl, 100000);
}

test "bench: Phase 4 Noise Reduction - Layer 2" {
    std.debug.print("\n=== Phase 4: Noise Reduction (Layer 2 Path Filter) ===\n", .{});

    try benchmark("Layer2 Filter (user path)", benchNoiseLayer2PathUser, 100000);
    try benchmark("Layer2 Filter (Rust path)", benchNoiseLayer2PathRustStdlib, 100000);
    try benchmark("Layer2 Filter (Zig path)", benchNoiseLayer2PathZigStdlib, 100000);
}

test "bench: Phase 4 Noise Reduction - Classification" {
    std.debug.print("\n=== Phase 4: Noise Reduction (Classification) ===\n", .{});

    try benchmark("Classify (user code)", benchNoiseClassifyUser, 100000);
    try benchmark("Classify (Rust drop glue)", benchNoiseClassifyRustDropGlue, 100000);
    try benchmark("Classify (Zig allocator)", benchNoiseClassifyZigAllocator, 100000);
}

test "bench: Phase 4 Noise Reduction - Layer 3 Behavior" {
    std.debug.print("\n=== Phase 4: Noise Reduction (Layer 3 Behavior) ===\n", .{});

    try benchmark("Rust Drop Glue Detection", benchRustDropGlueBehavior, 10000);
    try benchmark("Zig Allocator Wrapper", benchZigAllocatorWrapperBehavior, 10000);
    try benchmark("STL Vector Grow", benchSTLVectorGrowBehavior, 10000);
}

test "bench: Phase 4 Noise Reduction - Attribution" {
    std.debug.print("\n=== Phase 4: Noise Reduction (Attribution Summary) ===\n", .{});

    try benchmark("Attribution AddIssue", benchNoiseAttributionSummaryAdd, 10000);
    try benchmark("Attribution PrintReport", benchNoiseAttributionSummaryPrint, 1000);
}

test "bench: Memory Usage" {
    std.debug.print("\n=== Memory Usage ===\n", .{});

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
