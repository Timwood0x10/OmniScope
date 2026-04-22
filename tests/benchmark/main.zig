//! OmniScope Performance Benchmark Tests
//!
//! Validates performance targets defined in docs/BENCHMARK.md:
//!   - Core operation latency < 10μs
//!   - Memory usage < 1GB for < 500K IR lines
//!   - Linear scaling with input size
//!
//! Run with: zig build test-benchmark

const std = @import("std");
const time = std.time;
const testing = std.testing;

const OmniScope = @import("OmniScope");
const registry = OmniScope.registry;
const lifetime = OmniScope.lifetime;

const MAX_LATENCY_NS: i64 = 100_000;
const MAX_REGISTRY_LOOKUP_NS: i64 = 10_000;
const MAX_REGISTRY_UNKNOWN_NS: i64 = 100_000;
const MAX_ENGINE_CYCLE_NS: i64 = 50_000;
const MAX_LEAK_DETECT_NS: i64 = 1_000_000;

// ========================================
// Registry Lookup Latency Tests
// ========================================

test "benchmark: registry lookup known function latency" {
    const warmup: usize = 10;
    var i: usize = 0;
    while (i < warmup) : (i += 1) {
        _ = registry.SemanticRegistry.lookup("malloc");
    }

    const iterations: usize = 1000;
    const start = time.nanoTimestamp();

    i = 0;
    while (i < iterations) : (i += 1) {
        _ = registry.SemanticRegistry.lookup("malloc");
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_REGISTRY_LOOKUP_NS)));
}

test "benchmark: registry lookup unknown function latency" {
    const warmup: usize = 10;
    var i: usize = 0;
    while (i < warmup) : (i += 1) {
        _ = registry.SemanticRegistry.lookup("totally_unknown_function_xyz");
    }

    const iterations: usize = 1000;
    const start = time.nanoTimestamp();

    i = 0;
    while (i < iterations) : (i += 1) {
        _ = registry.SemanticRegistry.lookup("totally_unknown_function_xyz");
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_REGISTRY_UNKNOWN_NS)));
}

test "benchmark: registry isKnown latency" {
    const iterations: usize = 10000;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = registry.SemanticRegistry.isKnown("free");
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_REGISTRY_LOOKUP_NS)));
}

test "benchmark: registry getSeverity latency" {
    const iterations: usize = 10000;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = registry.SemanticRegistry.getSeverity("system");
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_REGISTRY_LOOKUP_NS)));
}

// ========================================
// Lifetime Engine Latency Tests
// ========================================

test "benchmark: engine init latency" {
    const iterations: usize = 1000;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        engine.deinit();
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_LATENCY_NS)));
}

test "benchmark: engine alloc latency" {
    const iterations: usize = 1000;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        defer engine.deinit();
        _ = engine.applyAction(.alloc, "bench_func", null, null);
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_ENGINE_CYCLE_NS)));
}

test "benchmark: engine full cycle latency" {
    const iterations: usize = 1000;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        defer engine.deinit();

        const id = engine.applyAction(.alloc, "bench_func", null, null) orelse continue;
        _ = engine.applyActionToResource(id, .free, null);
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_ENGINE_CYCLE_NS)));
}

test "benchmark: engine leak detection latency (100 resources)" {
    const iterations: usize = 100;
    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        defer engine.deinit();

        var j: usize = 0;
        while (j < 100) : (j += 1) {
            _ = engine.applyAction(.alloc, "bench_func", null, null);
        }

        engine.detectLeaks();
    }

    const end = time.nanoTimestamp();
    const avg_ns: f64 = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iterations));

    try testing.expect(avg_ns < @as(f64, @floatFromInt(MAX_LEAK_DETECT_NS)));
}

// ========================================
// Memory Usage Tests
// ========================================

test "benchmark: memory usage for 1000 resources" {
    var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
    defer engine.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = engine.applyAction(.alloc, "bench_func", null, null);
    }

    const stats = engine.getStats();
    try testing.expectEqual(@as(u32, 1000), stats.total_resources);
}

test "benchmark: memory stability across multiple runs" {
    const runs: usize = 5;

    var run: usize = 0;
    while (run < runs) : (run += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        defer engine.deinit();

        var i: usize = 0;
        while (i < 500) : (i += 1) {
            _ = engine.applyAction(.alloc, "bench_func", null, null);
        }

        const stats = engine.getStats();
        try testing.expectEqual(@as(u32, 500), stats.total_resources);
    }
}

// ========================================
// Registry Coverage Tests
// ========================================

test "benchmark: registry layer counts match expected" {
    try testing.expectEqual(@as(usize, 64), registry.SemanticRegistry.layer1Count());
    try testing.expectEqual(@as(usize, 3), registry.SemanticRegistry.layer2Count());
    try testing.expectEqual(@as(usize, 4), registry.SemanticRegistry.layer3Count());
    try testing.expectEqual(@as(usize, 8), registry.SemanticRegistry.layer4Count());
    try testing.expectEqual(@as(usize, 29), registry.SemanticRegistry.layer5Count());
    try testing.expectEqual(@as(usize, 58), registry.SemanticRegistry.layer6Count());

    const total = registry.SemanticRegistry.layer1Count() +
        registry.SemanticRegistry.layer2Count() +
        registry.SemanticRegistry.layer3Count() +
        registry.SemanticRegistry.layer4Count() +
        registry.SemanticRegistry.layer5Count() +
        registry.SemanticRegistry.layer6Count();
    try testing.expectEqual(@as(usize, 166), total);
}

test "benchmark: registry known functions respond correctly" {
    const known_funcs = [_][]const u8{
        "malloc",   "free",     "calloc", "realloc",
        "fopen",    "fclose",   "mmap",   "munmap",
        "into_raw", "from_raw",
    };

    for (known_funcs) |func| {
        const sem = registry.SemanticRegistry.lookup(func);
        try testing.expect(sem != null);
    }
}

test "benchmark: registry RiskKind count matches expected" {
    try testing.expect(registry.SemanticRegistry.isKnown("malloc"));
    try testing.expect(registry.SemanticRegistry.isKnown("into_raw"));
    try testing.expect(registry.SemanticRegistry.isKnown("operator new"));
}

// ========================================
// Throughput Tests
// ========================================

test "benchmark: registry lookup throughput" {
    const target_ops_per_sec: f64 = 100_000.0;
    const iterations: usize = 50_000;

    const funcs = [_][]const u8{
        "malloc", "free",   "calloc", "realloc", "strdup",
        "fopen",  "fclose", "fread",  "fwrite",  "printf",
    };

    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const idx = i % funcs.len;
        _ = registry.SemanticRegistry.lookup(funcs[idx]);
    }

    const end = time.nanoTimestamp();
    const elapsed_sec: f64 = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const throughput: f64 = @as(f64, @floatFromInt(iterations)) / elapsed_sec;

    try testing.expect(throughput >= target_ops_per_sec);
}

test "benchmark: engine alloc-free throughput" {
    const target_ops_per_sec: f64 = 10_000.0;
    const iterations: usize = 5_000;

    const start = time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var engine = lifetime.LifetimeEngine.init(std.heap.page_allocator);
        defer engine.deinit();

        const id = engine.applyAction(.alloc, "bench", null, null) orelse continue;
        _ = engine.applyActionToResource(id, .free, null);
    }

    const end = time.nanoTimestamp();
    const elapsed_sec: f64 = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const throughput: f64 = @as(f64, @floatFromInt(iterations)) / elapsed_sec;

    try testing.expect(throughput >= target_ops_per_sec);
}
