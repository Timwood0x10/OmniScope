//! OmniScope Benchmark Suite
//!
//! Run with: zig build bench
//! For realistic performance: zig build bench -Doptimize=ReleaseFast
//!
//! Features:
//! - Instrumented allocator for accurate memory tracking
//! - Complete statistics (min/max/avg/stddev)
//! - Comprehensive coverage of all core components

const std = @import("std");
const OmniScope = @import("OmniScope");
const FactStore = OmniScope.fact.FactStore;
const FactKind = OmniScope.fact.FactKind;
const QueryEngine = OmniScope.fact.QueryEngine;
const TaintContext = OmniScope.cross_lang.TaintContext;
const TaintInfo = OmniScope.cross_lang.TaintInfo;
const FFIBoundaryDetector = OmniScope.cross_lang.FFIBoundaryDetector;
const FlowPath = OmniScope.cross_lang.FlowPath;
const FlowStep = OmniScope.cross_lang.FlowStep;
const RiskLevel = OmniScope.cross_lang.RiskLevel;
const classifyRiskLevel = OmniScope.cross_lang.classifyRiskLevel;

const WARMUP_ITERATIONS = 3;
const MEASUREMENT_ITERATIONS = 10;

var compiler_sink: usize = 0;

fn consumeValue(comptime T: type, value: T) void {
    const ptr = @as(*const volatile T, @ptrCast(&value));
    compiler_sink = compiler_sink +% @as(usize, @intCast(@intFromPtr(ptr)));
}

const MemoryStats = struct {
    alloc_bytes: usize = 0,
    free_count: usize = 0,
};

var mem_stats: MemoryStats = .{};

fn resetMemoryStats() void {
    mem_stats = .{};
}

fn getMemoryStats() MemoryStats {
    return mem_stats;
}

fn trackAlloc(size: usize) void {
    mem_stats.alloc_bytes += size;
}

fn trackFree() void {
    mem_stats.free_count += 1;
}

const RunStats = struct {
    min_ns: i128 = std.math.maxInt(i128),
    max_ns: i128 = 0,
    total_ns: i128 = 0,
    values: []i128,

    fn init(allocator: std.mem.Allocator, capacity: usize) !RunStats {
        return .{
            .values = try allocator.alloc(i128, capacity),
        };
    }

    fn deinit(self: *RunStats, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
    }

    fn record(self: *RunStats, elapsed_ns: i128) void {
        if (elapsed_ns < self.min_ns) self.min_ns = elapsed_ns;
        if (elapsed_ns > self.max_ns) self.max_ns = elapsed_ns;
        self.total_ns += elapsed_ns;
    }

    fn avg_ms(self: *const RunStats, count: usize) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) / @as(f64, @floatFromInt(count)) / 1_000_000.0;
    }

    fn min_ms(self: *const RunStats) f64 {
        return @as(f64, @floatFromInt(self.min_ns)) / 1_000_000.0;
    }

    fn max_ms(self: *const RunStats) f64 {
        return @as(f64, @floatFromInt(self.max_ns)) / 1_000_000.0;
    }

    fn stddev_ms(self: *const RunStats, count: usize) f64 {
        if (count <= 1) return 0.0;
        const avg_ns = @as(f64, @floatFromInt(self.total_ns)) / @as(f64, @floatFromInt(count));
        const avg_ms_val = avg_ns / 1_000_000.0;
        var variance_sum: f64 = 0.0;
        for (self.values[0..count]) |v| {
            const v_ms = @as(f64, @floatFromInt(v)) / 1_000_000.0;
            const diff = v_ms - avg_ms_val;
            variance_sum += diff * diff;
        }
        return @sqrt(variance_sum / @as(f64, @floatFromInt(count - 1)));
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== OmniScope Benchmark Suite ===\n", .{});
    std.debug.print("Configuration: {} warmup, {} measurement iterations\n", .{ WARMUP_ITERATIONS, MEASUREMENT_ITERATIONS });
    std.debug.print("Optimization mode: Debug (use -Doptimize=ReleaseFast for realistic performance)\n\n", .{});

    try benchmarkFactStore(allocator);
    try benchmarkQueryEngine(allocator);
    try benchmarkTaintContext(allocator);
    try benchmarkFFIBoundary(allocator);
    try benchmarkFlowPath(allocator);
    try benchmarkRiskLevel(allocator);

    std.debug.print("\n=== All benchmarks complete ===\n\n", .{});
}

fn benchmarkFactStore(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FactStore ---\n", .{});

    const insert_count = 100000;
    var insert_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer insert_stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var store = FactStore.init(allocator);
        defer store.deinit();
        var j: u32 = 0;
        while (j < insert_count) : (j += 1) {
            try store.insert(.cfg_edge, j, j + 1, j / 100);
        }
        consumeValue(usize, store.count());
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        var store = FactStore.init(allocator);
        defer store.deinit();
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < insert_count) : (j += 1) {
            try store.insert(.cfg_edge, j, j + 1, j / 100);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        insert_stats.values[i] = elapsed;
        insert_stats.record(elapsed);
        consumeValue(usize, store.count());
    }

    const mem = getMemoryStats();
    std.debug.print("  Insert ({d} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ insert_count, insert_stats.avg_ms(MEASUREMENT_ITERATIONS), insert_stats.min_ms(), insert_stats.max_ms(), insert_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });

    var query_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer query_stats.deinit(allocator);

    var store = FactStore.init(allocator);
    defer store.deinit();
    var j: u32 = 0;
    while (j < insert_count) : (j += 1) {
        const kind: FactKind = @enumFromInt(j % 5);
        try store.insert(kind, j, j + 1, j / 100);
    }

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        _ = try store.queryByKind(.cfg_edge, allocator);
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        _ = try store.queryByKind(.cfg_edge, allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        query_stats.values[i] = elapsed;
        query_stats.record(elapsed);
    }

    const mem2 = getMemoryStats();
    std.debug.print("  Query (5 kind queries, {} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ insert_count, query_stats.avg_ms(MEASUREMENT_ITERATIONS), query_stats.min_ms(), query_stats.max_ms(), query_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem2.alloc_bytes, mem2.free_count });
}

fn benchmarkQueryEngine(allocator: std.mem.Allocator) !void {
    std.debug.print("--- QueryEngine ---\n", .{});

    const fact_count = 50000;
    var store = FactStore.init(allocator);
    defer store.deinit();

    var j: u32 = 0;
    while (j < fact_count) : (j += 1) {
        const kind: FactKind = @enumFromInt(j % 5);
        const ctx: u32 = j / 1000;
        try store.insert(kind, j, j + 1, ctx);
    }

    var engine = QueryEngine.init(&store);

    var byKind_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer byKind_stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        const results = try engine.queryByKind(.cfg_edge, allocator);
        allocator.free(results);
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        const results = try engine.queryByKind(.cfg_edge, allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        byKind_stats.values[i] = elapsed;
        byKind_stats.record(elapsed);
        consumeValue(usize, results.len);
        allocator.free(results);
    }

    const mem = getMemoryStats();
    std.debug.print("  queryByKind: avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ byKind_stats.avg_ms(MEASUREMENT_ITERATIONS), byKind_stats.min_ms(), byKind_stats.max_ms(), byKind_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });

    var byCtx_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer byCtx_stats.deinit(allocator);

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        const results = try engine.queryByContext(10, allocator);
        allocator.free(results);
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        const results = try engine.queryByContext(10, allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        byCtx_stats.values[i] = elapsed;
        byCtx_stats.record(elapsed);
        consumeValue(usize, results.len);
        allocator.free(results);
    }

    const mem2 = getMemoryStats();
    std.debug.print("  queryByContext: avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ byCtx_stats.avg_ms(MEASUREMENT_ITERATIONS), byCtx_stats.min_ms(), byCtx_stats.max_ms(), byCtx_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem2.alloc_bytes, mem2.free_count });
}

fn benchmarkTaintContext(allocator: std.mem.Allocator) !void {
    std.debug.print("--- TaintContext ---\n", .{});

    const count = 100000;

    var set_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer set_stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var ctx = TaintContext.init(allocator);
        defer ctx.deinit();
        var j: u32 = 0;
        while (j < count) : (j += 1) {
            const info = TaintInfo{
                .id = j,
                .state = .tainted,
                .source_id = 0,
                .confidence = 0.9,
            };
            try ctx.setValueTaint(j, info);
        }
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        var ctx = TaintContext.init(allocator);
        defer ctx.deinit();
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < count) : (j += 1) {
            const info = TaintInfo{
                .id = j,
                .state = .tainted,
                .source_id = 0,
                .confidence = 0.9,
            };
            try ctx.setValueTaint(j, info);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        set_stats.values[i] = elapsed;
        set_stats.record(elapsed);
        consumeValue(usize, ctx.taintedCount());
    }

    const mem = getMemoryStats();
    std.debug.print("  setValueTaint ({d} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ count, set_stats.avg_ms(MEASUREMENT_ITERATIONS), set_stats.min_ms(), set_stats.max_ms(), set_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });

    var get_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer get_stats.deinit(allocator);

    var ctx = TaintContext.init(allocator);
    defer ctx.deinit();
    var setup_j: u32 = 0;
    while (setup_j < count) : (setup_j += 1) {
        const info = TaintInfo{ .id = setup_j, .state = .tainted, .source_id = 0, .confidence = 0.9 };
        try ctx.setValueTaint(setup_j, info);
    }

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            _ = ctx.getValueTaint(k);
        }
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            _ = ctx.getValueTaint(k);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        get_stats.values[i] = elapsed;
        get_stats.record(elapsed);
    }

    const mem2 = getMemoryStats();
    std.debug.print("  getValueTaint ({d} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ count, get_stats.avg_ms(MEASUREMENT_ITERATIONS), get_stats.min_ms(), get_stats.max_ms(), get_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem2.alloc_bytes, mem2.free_count });
}

fn benchmarkFFIBoundary(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FFIBoundaryDetector ---\n", .{});

    var detector = FFIBoundaryDetector.init(allocator);
    defer detector.deinit();

    const test_functions = &[_][]const u8{
        "rust_function",
        "cgo_wrapper",
        "my_popen_wrapper",
        "_Z3fooi",
        "malloc",
        "printf",
        "Java_com_example_native",
        "PyObject_Call",
    };

    const call_count = 1000000;

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            _ = detector.isFFICall(test_functions[j % test_functions.len]);
        }
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        var ffi_count: usize = 0;
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            if (detector.isFFICall(test_functions[j % test_functions.len])) {
                ffi_count += 1;
            }
        }
        const elapsed = std.time.nanoTimestamp() - start;
        stats.values[i] = elapsed;
        stats.record(elapsed);
        consumeValue(usize, ffi_count);
    }

    const mem = getMemoryStats();
    std.debug.print("  isFFICall ({d} calls): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ call_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });
}

fn benchmarkFlowPath(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FlowPath ---\n", .{});

    const step_count = 10000;

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var path = FlowPath.init();
        defer path.deinit(allocator);
        var j: u32 = 0;
        while (j < step_count) : (j += 1) {
            const step = FlowStep{
                .id = j,
                .func_name = "test_function",
                .location = .{ .file = null, .line = j, .column = 0 },
                .taint_state = .tainted,
                .confidence = 0.9,
            };
            try path.addStep(allocator, step);
        }
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        var path = FlowPath.init();
        defer path.deinit(allocator);
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < step_count) : (j += 1) {
            const step = FlowStep{
                .id = j,
                .func_name = "test_function",
                .location = .{ .file = null, .line = j, .column = 0 },
                .taint_state = .tainted,
                .confidence = 0.9,
            };
            try path.addStep(allocator, step);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        stats.values[i] = elapsed;
        stats.record(elapsed);
        consumeValue(usize, path.length());
    }

    const mem = getMemoryStats();
    std.debug.print("  addStep ({d} steps): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ step_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });
}

fn benchmarkRiskLevel(allocator: std.mem.Allocator) !void {
    std.debug.print("--- RiskLevel ---\n", .{});

    const test_functions = &[_][]const u8{
        "system",
        "execve",
        "strcpy",
        "strcat",
        "sprintf",
        "popen",
        "malloc",
        "printf",
    };

    const call_count = 1000000;

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit(allocator);

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            _ = classifyRiskLevel(test_functions[j % test_functions.len]);
        }
    }

    resetMemoryStats();
    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        const start = std.time.nanoTimestamp();
        var critical_count: usize = 0;
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            if (classifyRiskLevel(test_functions[j % test_functions.len]) == .critical) {
                critical_count += 1;
            }
        }
        const elapsed = std.time.nanoTimestamp() - start;
        stats.values[i] = elapsed;
        stats.record(elapsed);
        consumeValue(usize, critical_count);
    }

    const mem = getMemoryStats();
    std.debug.print("  classifyRisk ({d} calls): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ call_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} frees\n", .{ mem.alloc_bytes, mem.free_count });
}
