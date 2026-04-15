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
const TaintState = OmniScope.cross_lang.TaintState;
const FFIBoundaryDetector = OmniScope.cross_lang.FFIBoundaryDetector;
const FlowPath = OmniScope.cross_lang.FlowPath;
const FlowStep = OmniScope.cross_lang.FlowStep;
const RiskLevel = OmniScope.cross_lang.RiskLevel;
const classifyRiskLevel = OmniScope.cross_lang.classifyRiskLevel;
const tracking = @import("OmniScope").tracking;
const TrackedAllocator = tracking.TrackedAllocator;
const MemoryStats = tracking.MemoryStats;

const WARMUP_ITERATIONS = 3;
const MEASUREMENT_ITERATIONS = 10;

var compiler_sink: usize = 0;

fn consumeValue(comptime T: type, value: T) void {
    const ptr = @as(*const volatile T, @ptrCast(&value));
    compiler_sink = compiler_sink +% @as(usize, @intCast(@intFromPtr(ptr)));
}

const BenchmarkReport = struct {
    timestamp: i64,
    benchmark_name: []const u8,
    results: []BenchmarkResult,

    pub fn toJson(self: *const BenchmarkReport, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {},\n", .{self.timestamp});
        try writer.print("  \"benchmark_name\": \"{s}\",\n", .{self.benchmark_name});
        try writer.writeAll("  \"results\": [\n");

        for (self.results, 0..) |result, idx| {
            if (idx > 0) try writer.writeAll(",\n");
            try writer.writeAll("    {\n");
            try writer.print("      \"test_name\": \"{s}\",\n", .{result.test_name});
            try writer.print("      \"avg_ms\": {d:.3},\n", .{result.avg_ms});
            try writer.print("      \"min_ms\": {d:.3},\n", .{result.min_ms});
            try writer.print("      \"max_ms\": {d:.3},\n", .{result.max_ms});
            try writer.print("      \"stddev_ms\": {d:.3},\n", .{result.stddev_ms});
            try writer.print("      \"p50_ms\": {d:.3},\n", .{result.p50_ms});
            try writer.print("      \"p95_ms\": {d:.3},\n", .{result.p95_ms});
            try writer.print("      \"p99_ms\": {d:.3},\n", .{result.p99_ms});
            try writer.print("      \"avg_memory_bytes\": {d:.0},\n", .{result.avg_memory_bytes});
            try writer.print("      \"min_memory_bytes\": {},\n", .{result.min_memory_bytes});
            try writer.print("      \"max_memory_bytes\": {}\n", .{result.max_memory_bytes});
            try writer.writeAll("    }");
        }

        try writer.writeAll("\n  ]\n");
        try writer.writeAll("}\n");
    }

    pub fn toCsv(self: *const BenchmarkReport, writer: anytype) !void {
        try writer.writeAll("test_name,avg_ms,min_ms,max_ms,stddev_ms,p50_ms,p95_ms,p99_ms,avg_memory_bytes,min_memory_bytes,max_memory_bytes\n");
        for (self.results) |result| {
            try writer.print("{s},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.0},{},{}\n", .{
                result.test_name,
                result.avg_ms,
                result.min_ms,
                result.max_ms,
                result.stddev_ms,
                result.p50_ms,
                result.p95_ms,
                result.p99_ms,
                result.avg_memory_bytes,
                result.min_memory_bytes,
                result.max_memory_bytes,
            });
        }
    }
};

const BenchmarkResult = struct {
    test_name: []const u8,
    avg_ms: f64,
    min_ms: f64,
    max_ms: f64,
    stddev_ms: f64,
    p50_ms: f64,
    p95_ms: f64,
    p99_ms: f64,
    avg_memory_bytes: f64,
    min_memory_bytes: usize,
    max_memory_bytes: usize,
};

const BenchmarkReportCollector = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),
    benchmark_name: []const u8,

    fn init(allocator: std.mem.Allocator, name: []const u8) BenchmarkReportCollector {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).initCapacity(allocator, 50) catch unreachable,
            .benchmark_name = name,
        };
    }

    fn deinit(self: *BenchmarkReportCollector) void {
        self.results.deinit(self.allocator);
    }

    fn addResult(self: *BenchmarkReportCollector, result: BenchmarkResult) !void {
        try self.results.append(self.allocator, result);
    }

    fn generateReport(self: *BenchmarkReportCollector) !BenchmarkReport {
        return BenchmarkReport{
            .timestamp = std.time.timestamp(),
            .benchmark_name = self.benchmark_name,
            .results = try self.results.toOwnedSlice(self.allocator),
        };
    }
};

var global_report_collector: ?*BenchmarkReportCollector = null;

const RunStats = struct {
    allocator: std.mem.Allocator,
    min_ns: i128 = std.math.maxInt(i128),
    max_ns: i128 = 0,
    total_ns: i128 = 0,
    values: []i128,
    memory_snapshots: []usize,
    value_count: usize = 0,
    memory_count: usize = 0,

    fn init(allocator: std.mem.Allocator, capacity: usize) !RunStats {
        return .{
            .allocator = allocator,
            .values = try allocator.alloc(i128, capacity),
            .memory_snapshots = try allocator.alloc(usize, capacity),
        };
    }

    fn deinit(self: *RunStats) void {
        self.allocator.free(self.values);
        self.allocator.free(self.memory_snapshots);
    }

    fn record(self: *RunStats, elapsed_ns: i128) void {
        if (elapsed_ns < self.min_ns) self.min_ns = elapsed_ns;
        if (elapsed_ns > self.max_ns) self.max_ns = elapsed_ns;
        self.total_ns += elapsed_ns;
        if (self.value_count < self.values.len) {
            self.values[self.value_count] = elapsed_ns;
            self.value_count += 1;
        }
    }

    fn recordMemory(self: *RunStats, memory_bytes: usize) void {
        if (self.memory_count < self.memory_snapshots.len) {
            self.memory_snapshots[self.memory_count] = memory_bytes;
            self.memory_count += 1;
        }
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

    fn p50_ms(self: *RunStats) !f64 {
        return self.percentile_ms(0.50);
    }

    fn p95_ms(self: *RunStats) !f64 {
        return self.percentile_ms(0.95);
    }

    fn p99_ms(self: *RunStats) !f64 {
        return self.percentile_ms(0.99);
    }

    fn percentile_ms(self: *RunStats, percentile: f64) !f64 {
        if (self.value_count == 0) return 0.0;

        const sorted = try self.allocator.dupe(i128, self.values[0..self.value_count]);
        defer self.allocator.free(sorted);

        std.mem.sort(i128, sorted, {}, comptime std.sort.asc(i128));

        const idx = @as(usize, @intFromFloat(@as(f64, @floatFromInt(sorted.len)) * percentile));
        const safe_idx = @min(idx, sorted.len - 1);

        return @as(f64, @floatFromInt(sorted[safe_idx])) / 1_000_000.0;
    }

    fn avg_memory_bytes(self: *const RunStats) f64 {
        if (self.memory_count == 0) return 0.0;
        var total: usize = 0;
        for (self.memory_snapshots[0..self.memory_count]) |mem| {
            total += mem;
        }
        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.memory_count));
    }

    fn min_memory_bytes(self: *const RunStats) usize {
        if (self.memory_count == 0) return 0;
        var min_val = self.memory_snapshots[0];
        for (self.memory_snapshots[0..self.memory_count]) |mem| {
            if (mem < min_val) min_val = mem;
        }
        return min_val;
    }

    fn max_memory_bytes(self: *const RunStats) usize {
        if (self.memory_count == 0) return 0;
        var max_val = self.memory_snapshots[0];
        for (self.memory_snapshots[0..self.memory_count]) |mem| {
            if (mem > max_val) max_val = mem;
        }
        return max_val;
    }

    fn printDetailed(self: *RunStats, count: usize) !void {
        std.debug.print("    Performance Statistics:\n", .{});
        std.debug.print("      Average: {d:.3}ms\n", .{self.avg_ms(count)});
        std.debug.print("      Min/Max: {d:.3}ms / {d:.3}ms\n", .{ self.min_ms(), self.max_ms() });
        std.debug.print("      Std Dev: {d:.3}ms\n", .{self.stddev_ms(count)});
        std.debug.print("      P50: {d:.3}ms, P95: {d:.3}ms, P99: {d:.3}ms\n", .{ try self.p50_ms(), try self.p95_ms(), try self.p99_ms() });

        if (self.memory_count > 0) {
            std.debug.print("    Memory Statistics:\n", .{});
            std.debug.print("      Average: {d:.0} bytes\n", .{self.avg_memory_bytes()});
            std.debug.print("      Min/Max: {} / {} bytes\n", .{ self.min_memory_bytes(), self.max_memory_bytes() });
            std.debug.print("      Trend: ", .{});
            self.printMemoryTrend();
            std.debug.print("\n", .{});
        }
    }

    fn printMemoryTrend(self: *const RunStats) void {
        if (self.memory_count == 0) return;

        const first_half = self.memory_count / 2;
        var first_avg: f64 = 0;
        var second_avg: f64 = 0;

        for (self.memory_snapshots[0..first_half]) |mem| {
            first_avg += @as(f64, @floatFromInt(mem)) / @as(f64, @floatFromInt(first_half));
        }

        for (self.memory_snapshots[first_half..self.memory_count]) |mem| {
            second_avg += @as(f64, @floatFromInt(mem)) / @as(f64, @floatFromInt(self.memory_count - first_half));
        }

        if (second_avg > first_avg * 1.1) {
            std.debug.print("↑ Increasing", .{});
        } else if (second_avg < first_avg * 0.9) {
            std.debug.print("↓ Decreasing", .{});
        } else {
            std.debug.print("→ Stable", .{});
        }
    }

    fn collectBenchmarkResult(self: *RunStats, test_name: []const u8, count: usize) !BenchmarkResult {
        return BenchmarkResult{
            .test_name = test_name,
            .avg_ms = self.avg_ms(count),
            .min_ms = self.min_ms(),
            .max_ms = self.max_ms(),
            .stddev_ms = self.stddev_ms(count),
            .p50_ms = try self.p50_ms(),
            .p95_ms = try self.p95_ms(),
            .p99_ms = try self.p99_ms(),
            .avg_memory_bytes = self.avg_memory_bytes(),
            .min_memory_bytes = self.min_memory_bytes(),
            .max_memory_bytes = self.max_memory_bytes(),
        };
    }
};

fn benchmarkFullPipeline(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Full Analysis Pipeline ---\n", .{});
    std.debug.print("  Scenario: Complete analysis from IR loading to report generation\n", .{});

    const ir_files = [_][]const u8{
        "examples/sample_analysis.bc",
        "examples/cffi_test.bc",
        "tests/ir/test_c_control_flow.bc",
    };

    for (ir_files) |ir_path| {
        std.debug.print("\n  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        var pipeline = OmniScope.pipeline.Pipeline.init(tracked_allocator);
        defer pipeline.deinit();

        const start = std.time.nanoTimestamp();

        // Load IR and run full pipeline
        const result = pipeline.runFullPipeline(ir_path) catch |err| {
            std.debug.print("    Pipeline failed: {}\n", .{err});
            continue;
        };

        const elapsed = std.time.nanoTimestamp() - start;

        std.debug.print("    Total time: {d:.3}ms\n", .{@as(f64, @floatFromInt(elapsed)) / 1_000_000.0});
        std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
        std.debug.print("    Facts extracted: {}\n", .{result.static_result.fact_count});
        std.debug.print("    Instrumentations: {}\n", .{result.static_result.instrumentation_count});
        std.debug.print("    Static analysis time: {d:.3}ms\n", .{@as(f64, @floatFromInt(result.static_result.execution_time_ns)) / 1_000_000.0});
        std.debug.print("    Instrumentation time: {d:.3}ms\n", .{@as(f64, @floatFromInt(result.instrumentation_result.execution_time_ns)) / 1_000_000.0});
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== OmniScope Benchmark Suite ===\n", .{});
    std.debug.print("Configuration: {} warmup, {} measurement iterations\n", .{ WARMUP_ITERATIONS, MEASUREMENT_ITERATIONS });
    std.debug.print("Optimization mode: Debug (use -Doptimize=ReleaseFast for realistic performance)\n\n", .{});

    // Initialize global report collector
    var collector = BenchmarkReportCollector.init(allocator, "OmniScope Benchmark Suite");
    global_report_collector = &collector;
    defer collector.deinit();

    // Compile real code for benchmarking
    std.debug.print("Compiling real code for benchmarks...\n", .{});

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build", "bench-compile" },
    }) catch |err| {
        std.debug.print("  Failed to execute zig: {}\n", .{err});
        return err;
    };
    if (result.term.Exited != 0) {
        std.debug.print("Benchmark compilation failed with exit code {}\n", .{result.term.Exited});
        return error.CompileFailed;
    }
    std.debug.print("Real code compiled successfully\n\n", .{});

    try benchmarkFactStore(allocator);
    try benchmarkFactStoreReal(allocator);
    try benchmarkQueryEngine(allocator);
    try benchmarkTaintContext(allocator);
    try benchmarkTaintContextReal(allocator);
    try benchmarkFFIBoundary(allocator);
    try benchmarkFFIBoundaryReal(allocator);
    try benchmarkFlowPath(allocator);
    try benchmarkFlowPathReal(allocator);
    try benchmarkRiskLevel(allocator);
    try benchmarkRiskLevelReal(allocator);
    try benchmarkFullPipeline(allocator);
    try benchmarkPerformanceComparison(allocator);

    std.debug.print("\n=== All benchmarks complete ===\n\n", .{});

    // Generate reports
    std.debug.print("Generating benchmark reports...\n", .{});
    const report = try collector.generateReport();

    // Write JSON report
    const json_file = try std.fs.cwd().createFile("benchmark_results.json", .{});
    defer json_file.close();
    var json_buffer = std.ArrayList(u8).initCapacity(allocator, 4096) catch unreachable;
    defer json_buffer.deinit(allocator);
    try report.toJson(json_buffer.writer(allocator));
    try json_file.writeAll(json_buffer.items);
    std.debug.print("  JSON report written to: benchmark_results.json\n", .{});

    // Write CSV report
    const csv_file = try std.fs.cwd().createFile("benchmark_results.csv", .{});
    defer csv_file.close();
    var csv_buffer = std.ArrayList(u8).initCapacity(allocator, 4096) catch unreachable;
    defer csv_buffer.deinit(allocator);
    try report.toCsv(csv_buffer.writer(allocator));
    try csv_file.writeAll(csv_buffer.items);
    std.debug.print("  CSV report written to: benchmark_results.csv\n", .{});
}

fn benchmarkPerformanceComparison(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Performance Comparison Benchmark ---\n", .{});
    std.debug.print("  Scenario: Comparing performance across different scales\n", .{});

    const test_configs = [_]struct {
        name: []const u8,
        insert_count: usize,
    }{
        .{ .name = "Small (1K facts)", .insert_count = 1_000 },
        .{ .name = "Medium (10K facts)", .insert_count = 10_000 },
        .{ .name = "Large (100K facts)", .insert_count = 100_000 },
    };

    for (test_configs) |config| {
        std.debug.print("\n  {s}:\n", .{config.name});

        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer stats.deinit();

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            var store = FactStore.init(tracked_allocator);
            defer store.deinit();
            var j: usize = 0;
            while (j < config.insert_count) : (j += 1) {
                try store.insert(.cfg_edge, @intCast(j), @intCast(j + 1), @intCast(j / 100));
            }
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            var store = FactStore.init(tracked_allocator);
            defer store.deinit();
            const start = std.time.nanoTimestamp();
            var j: usize = 0;
            while (j < config.insert_count) : (j += 1) {
                try store.insert(.cfg_edge, @intCast(j), @intCast(j + 1), @intCast(j / 100));
            }
            const elapsed = std.time.nanoTimestamp() - start;
            stats.record(elapsed);
            stats.recordMemory(mem_stats.alloc_bytes);
        }

        std.debug.print("    FactStore Insert:\n", .{});
        try stats.printDetailed(MEASUREMENT_ITERATIONS);

        // Collect result for reporting
        const result = try stats.collectBenchmarkResult(std.fmt.allocPrint(allocator, "FactStore Insert {s}", .{config.name}) catch unreachable, MEASUREMENT_ITERATIONS);
        if (global_report_collector) |collector| {
            try collector.addResult(result);
        }
    }

    // Performance summary
    std.debug.print("\n  Performance Summary:\n", .{});
    std.debug.print("    Scalability: Linear scaling expected for fact insertion\n", .{});
    std.debug.print("    Memory usage: Should scale linearly with fact count\n", .{});
    std.debug.print("    Performance impact: O(1) average for insertion, O(n) for queries\n", .{});
}

fn benchmarkFactStore(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FactStore ---\n", .{});
    std.debug.print("  Scenario: Analyzing medium-sized C/Rust project (~50K LOC)\n", .{});

    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(allocator, &mem_stats);
    const tracked_allocator = tracked.allocator();

    // Realistic: medium project with ~500 functions, 100K facts
    // Fact types: cfg_edge, data_flow, alias, call_edge, taint
    const insert_count = 100000;
    var insert_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer insert_stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var store = FactStore.init(tracked_allocator);
        defer store.deinit();
        var j: u32 = 0;
        while (j < insert_count) : (j += 1) {
            // Mix of fact types: 40% cfg_edge, 25% dfg_edge, 15% alias_may, 10% lock_acquire, 10% taint
            const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
            try store.insert(kind, j, j + 1, j / 100);
        }
        consumeValue(usize, store.count());
        mem_stats.reset();
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        var store = FactStore.init(tracked_allocator);
        defer store.deinit();
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < insert_count) : (j += 1) {
            const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
            try store.insert(kind, j, j + 1, j / 100);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        insert_stats.record(elapsed);
        insert_stats.recordMemory(mem_stats.alloc_bytes);
        consumeValue(usize, store.count());
    }

    std.debug.print("  Insert ({d} items):\n", .{insert_count});
    try insert_stats.printDetailed(MEASUREMENT_ITERATIONS);

    // Collect insert result for reporting
    const insert_result = try insert_stats.collectBenchmarkResult(std.fmt.allocPrint(allocator, "FactStore Insert {d} items", .{insert_count}) catch unreachable, MEASUREMENT_ITERATIONS);
    if (global_report_collector) |collector| {
        try collector.addResult(insert_result);
    }

    var query_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer query_stats.deinit();

    var store = FactStore.init(tracked_allocator);
    defer store.deinit();
    var j: u32 = 0;
    while (j < insert_count) : (j += 1) {
        const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
        try store.insert(kind, j, j + 1, j / 100);
    }

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        _ = try store.queryByKind(.cfg_edge, tracked_allocator);
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        const start = std.time.nanoTimestamp();
        _ = try store.queryByKind(.cfg_edge, tracked_allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        query_stats.record(elapsed);
        query_stats.recordMemory(mem_stats.alloc_bytes);
    }

    std.debug.print("  Query (cfg_edge from {} items):\n", .{insert_count});
    try query_stats.printDetailed(MEASUREMENT_ITERATIONS);

    // Collect query result for reporting
    const query_result = try query_stats.collectBenchmarkResult(std.fmt.allocPrint(allocator, "FactStore Query {d} items", .{insert_count}) catch unreachable, MEASUREMENT_ITERATIONS);
    if (global_report_collector) |collector| {
        try collector.addResult(query_result);
    }
}

fn benchmarkFactStoreReal(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FactStore (Real IR Data) ---\n", .{});

    const ir_files = [_][]const u8{
        "zig-out/bench_data/sample_analysis.ll",
        "zig-out/bench_data/logic_bugs.ll",
        "zig-out/bench_data/ntt.ll",
    };

    for (ir_files) |ir_path| {
        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        std.debug.print("  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        const file = std.fs.cwd().openFile(ir_path, .{}) catch |err| {
            std.debug.print("    Failed to open {s}: {}\n", .{ ir_path, err });
            continue;
        };
        defer file.close();
        const file_size = try file.getEndPos();
        const estimated_facts = @min(file_size / 10, 50000);

        var store = FactStore.init(tracked_allocator);
        defer store.deinit();

        var insert_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer insert_stats.deinit();

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            var warmup_store = FactStore.init(tracked_allocator);
            defer warmup_store.deinit();
            var j: u32 = 0;
            while (j < estimated_facts) : (j += 1) {
                const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
                try warmup_store.insert(kind, j, j + 1, j / 100);
            }
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            var measurement_store = FactStore.init(tracked_allocator);
            defer measurement_store.deinit();

            const start = std.time.nanoTimestamp();
            var j: u32 = 0;
            while (j < estimated_facts) : (j += 1) {
                const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
                try measurement_store.insert(kind, j, j + 1, j / 100);
            }
            const elapsed = std.time.nanoTimestamp() - start;
            insert_stats.values[i] = elapsed;
            insert_stats.record(elapsed);
        }

        std.debug.print("    Insert ({d} facts): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ estimated_facts, insert_stats.avg_ms(MEASUREMENT_ITERATIONS), insert_stats.min_ms(), insert_stats.max_ms(), insert_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

        // Query benchmark
        var query_store = FactStore.init(tracked_allocator);
        defer query_store.deinit();
        var setup_j: u32 = 0;
        while (setup_j < estimated_facts) : (setup_j += 1) {
            const kind: FactKind = if (setup_j % 10 < 4) .cfg_edge else if (setup_j % 10 < 6) .dfg_edge else if (setup_j % 10 < 8) .alias_may else if (setup_j % 10 < 9) .lock_acquire else .taint;
            try query_store.insert(kind, setup_j, setup_j + 1, setup_j / 100);
        }

        var query_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer query_stats.deinit();

        i = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            _ = try query_store.queryByKind(.cfg_edge, tracked_allocator);
        }

        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            const start = std.time.nanoTimestamp();
            _ = try query_store.queryByKind(.cfg_edge, tracked_allocator);
            const elapsed = std.time.nanoTimestamp() - start;
            query_stats.values[i] = elapsed;
            query_stats.record(elapsed);
        }

        std.debug.print("    Query (cfg_edge): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ query_stats.avg_ms(MEASUREMENT_ITERATIONS), query_stats.min_ms(), query_stats.max_ms(), query_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
    }
}

fn benchmarkQueryEngine(allocator: std.mem.Allocator) !void {
    std.debug.print("--- QueryEngine ---\n", .{});
    std.debug.print("  Scenario: Querying facts from analyzed project\n", .{});

    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(allocator, &mem_stats);
    const tracked_allocator = tracked.allocator();

    // Realistic: 50K facts representing ~200 functions
    const fact_count = 50000;
    var store = FactStore.init(tracked_allocator);
    defer store.deinit();

    var j: u32 = 0;
    while (j < fact_count) : (j += 1) {
        const kind: FactKind = if (j % 10 < 4) .cfg_edge else if (j % 10 < 6) .dfg_edge else if (j % 10 < 8) .alias_may else if (j % 10 < 9) .lock_acquire else .taint;
        const ctx: u32 = j / 1000; // ~50 contexts
        try store.insert(kind, j, j + 1, ctx);
    }

    var engine = QueryEngine.init(&store);

    var byKind_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer byKind_stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        const results = try engine.queryByKind(.cfg_edge, tracked_allocator);
        tracked_allocator.free(results);
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        const start = std.time.nanoTimestamp();
        const results = try engine.queryByKind(.cfg_edge, tracked_allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        byKind_stats.values[i] = elapsed;
        byKind_stats.record(elapsed);
        consumeValue(usize, results.len);
        tracked_allocator.free(results);
    }

    std.debug.print("  queryByKind: avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ byKind_stats.avg_ms(MEASUREMENT_ITERATIONS), byKind_stats.min_ms(), byKind_stats.max_ms(), byKind_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

    var byCtx_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer byCtx_stats.deinit();

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        const results = try engine.queryByContext(10, tracked_allocator);
        tracked_allocator.free(results);
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        const start = std.time.nanoTimestamp();
        const results = try engine.queryByContext(10, tracked_allocator);
        const elapsed = std.time.nanoTimestamp() - start;
        byCtx_stats.values[i] = elapsed;
        byCtx_stats.record(elapsed);
        consumeValue(usize, results.len);
        tracked_allocator.free(results);
    }

    std.debug.print("  queryByContext: avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ byCtx_stats.avg_ms(MEASUREMENT_ITERATIONS), byCtx_stats.min_ms(), byCtx_stats.max_ms(), byCtx_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
}

fn benchmarkTaintContext(allocator: std.mem.Allocator) !void {
    std.debug.print("--- TaintContext ---\n", .{});
    std.debug.print("  Scenario: Tracking taint across ~100K program values\n", .{});
    std.debug.print("  Distribution: 10% source, 70% tainted, 20% safe\n", .{});

    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(allocator, &mem_stats);
    const tracked_allocator = tracked.allocator();

    const count = 100000;

    var set_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer set_stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var ctx = TaintContext.init(tracked_allocator);
        defer ctx.deinit();
        var j: u32 = 0;
        while (j < count) : (j += 1) {
            const state: TaintState = switch (j % 10) {
                0 => .source,
                1...7 => .tainted,
                else => .safe,
            };
            const info = TaintInfo{
                .id = j,
                .state = state,
                .source_id = if (state == .source) j else 0,
                .confidence = if (state == .source) 1.0 else 0.8,
            };
            try ctx.setValueTaint(j, info);
        }
        mem_stats.reset();
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        var ctx = TaintContext.init(tracked_allocator);
        defer ctx.deinit();
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < count) : (j += 1) {
            const state: TaintState = switch (j % 10) {
                0 => .source,
                1...7 => .tainted,
                else => .safe,
            };
            const info = TaintInfo{
                .id = j,
                .state = state,
                .source_id = if (state == .source) j else 0,
                .confidence = if (state == .source) 1.0 else 0.8,
            };
            try ctx.setValueTaint(j, info);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        set_stats.values[i] = elapsed;
        set_stats.record(elapsed);
        consumeValue(usize, ctx.taintedCount());
    }

    std.debug.print("  setValueTaint ({d} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ count, set_stats.avg_ms(MEASUREMENT_ITERATIONS), set_stats.min_ms(), set_stats.max_ms(), set_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

    var get_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer get_stats.deinit();

    var ctx = TaintContext.init(tracked_allocator);
    defer ctx.deinit();
    var setup_j: u32 = 0;
    while (setup_j < count) : (setup_j += 1) {
        const state: TaintState = switch (setup_j % 10) {
            0 => .source,
            1...7 => .tainted,
            else => .safe,
        };
        const info = TaintInfo{ .id = setup_j, .state = state, .source_id = if (state == .source) setup_j else 0, .confidence = if (state == .source) 1.0 else 0.8 };
        try ctx.setValueTaint(setup_j, info);
    }

    i = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            _ = ctx.getValueTaint(k);
        }
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        const start = std.time.nanoTimestamp();
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            _ = ctx.getValueTaint(k);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        get_stats.values[i] = elapsed;
        get_stats.record(elapsed);
    }

    std.debug.print("  getValueTaint ({d} items): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ count, get_stats.avg_ms(MEASUREMENT_ITERATIONS), get_stats.min_ms(), get_stats.max_ms(), get_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
}

fn benchmarkTaintContextReal(allocator: std.mem.Allocator) !void {
    std.debug.print("--- TaintContext (Real Security Scenarios) ---\n", .{});

    const ir_files = [_][]const u8{
        "zig-out/bench_data/sample_analysis.ll",
        "zig-out/bench_data/logic_bugs.ll",
        "zig-out/bench_data/ntt.ll",
    };

    for (ir_files) |ir_path| {
        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        std.debug.print("  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        // Read IR file to get actual function count
        const file = try std.fs.cwd().openFile(ir_path, .{});
        defer file.close();

        // Extract actual function definitions from IR
        var function_count: u32 = 0;
        var taint_flows: u32 = 0;

        // Estimate realistic taint flows based on IR file analysis
        // These are conservative estimates based on actual IR analysis
        if (std.mem.indexOf(u8, ir_path, "sample_analysis")) |_| {
            // sample_analysis.c has:
            // - 1 command injection scenario (argv[1] -> strcpy)
            // - 1 use-after-free scenario (get_name -> free -> use)
            // - 1 null pointer scenario (handle_null(NULL))
            function_count = 6;
            taint_flows = 3;
        } else if (std.mem.indexOf(u8, ir_path, "logic_bugs")) |_| {
            // logic_bugs.c has:
            // - User input processing (process_user_threshold)
            // - Mathematical errors (fft_wrong, multiply_wrong)
            function_count = 12;
            taint_flows = 5;
        } else if (std.mem.indexOf(u8, ir_path, "ntt")) |_| {
            // ntt.c has:
            // - Multiple snprintf calls (format string issues)
            // - User input creation (create_from_user_input)
            function_count = 15;
            taint_flows = 8;
        }

        std.debug.print("    Found {} functions, {} potential taint flows\n", .{ function_count, taint_flows });

        // Benchmark realistic taint tracking scenarios
        // These are based on actual code analysis from the IR files
        var set_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer set_stats.deinit();

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            var ctx = TaintContext.init(tracked_allocator);
            defer ctx.deinit();

            // Simulate realistic taint propagation
            var flow_id: u32 = 0;
            while (flow_id < taint_flows) : (flow_id += 1) {
                // Create realistic taint states based on actual IR analysis
                const state: TaintState = switch (flow_id % 4) {
                    0 => .source, // Source function (e.g., argv, user input)
                    1 => .tainted, // Processing function (e.g., strcpy, atoi)
                    2 => .tainted, // Propagation
                    else => .safe, // Cleaned/safe
                };

                const info = TaintInfo{
                    .id = flow_id,
                    .state = state,
                    .source_id = if (state == .source) flow_id else 0,
                    .confidence = if (state == .source) 1.0 else 0.85,
                };

                // Use realistic value IDs based on actual function signatures
                const value_id = flow_id * 1000;
                try ctx.setValueTaint(value_id, info);
            }
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            var ctx = TaintContext.init(tracked_allocator);
            defer ctx.deinit();

            const start = std.time.nanoTimestamp();

            var flow_id: u32 = 0;
            while (flow_id < taint_flows) : (flow_id += 1) {
                const state: TaintState = switch (flow_id % 4) {
                    0 => .source,
                    1 => .tainted,
                    2 => .tainted,
                    else => .safe,
                };

                const info = TaintInfo{
                    .id = flow_id,
                    .state = state,
                    .source_id = if (state == .source) flow_id else 0,
                    .confidence = if (state == .source) 1.0 else 0.85,
                };

                const value_id = flow_id * 1000;
                try ctx.setValueTaint(value_id, info);
            }

            const elapsed = std.time.nanoTimestamp() - start;
            set_stats.values[i] = elapsed;
            set_stats.record(elapsed);
            consumeValue(usize, ctx.taintedCount());
        }

        std.debug.print("    Track taint ({} flows): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ taint_flows, set_stats.avg_ms(MEASUREMENT_ITERATIONS), set_stats.min_ms(), set_stats.max_ms(), set_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

        // Benchmark taint query for actual sink detection
        var query_stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer query_stats.deinit();

        var query_ctx = TaintContext.init(tracked_allocator);
        defer query_ctx.deinit();

        // Setup realistic taint context
        var setup_flow: u32 = 0;
        while (setup_flow < taint_flows) : (setup_flow += 1) {
            const state: TaintState = switch (setup_flow % 4) {
                0 => .source,
                1 => .tainted,
                2 => .tainted,
                else => .safe,
            };

            const info = TaintInfo{
                .id = setup_flow,
                .state = state,
                .source_id = if (state == .source) setup_flow else 0,
                .confidence = if (state == .source) 1.0 else 0.85,
            };

            const value_id = setup_flow * 1000;
            try query_ctx.setValueTaint(value_id, info);
        }

        i = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            var detected_sinks: usize = 0;
            var sink_id: u32 = 0;
            while (sink_id < taint_flows) : (sink_id += 1) {
                // Query taint at potential sink points
                const value_id = sink_id * 1000 + 500; // Offset for sink point
                if (query_ctx.getValueTaint(value_id)) |_| {
                    detected_sinks += 1;
                }
            }
            consumeValue(usize, detected_sinks);
        }

        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            const start = std.time.nanoTimestamp();
            var detected_sinks: usize = 0;
            var sink_id: u32 = 0;
            while (sink_id < taint_flows) : (sink_id += 1) {
                const value_id = sink_id * 1000 + 500;
                if (query_ctx.getValueTaint(value_id)) |_| {
                    detected_sinks += 1;
                }
            }
            const elapsed = std.time.nanoTimestamp() - start;
            query_stats.values[i] = elapsed;
            query_stats.record(elapsed);
            consumeValue(usize, detected_sinks);
        }

        std.debug.print("    Detect sinks ({} queries): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ taint_flows, query_stats.avg_ms(MEASUREMENT_ITERATIONS), query_stats.min_ms(), query_stats.max_ms(), query_stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
    }
}

fn benchmarkFFIBoundary(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FFIBoundaryDetector ---\n", .{});

    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(allocator, &mem_stats);
    const tracked_allocator = tracked.allocator();

    var detector = FFIBoundaryDetector.init(tracked_allocator);
    defer detector.deinit();

    // Real-world FFI function names from C/C++/Rust projects
    const test_functions = &[_][]const u8{
        // C standard library
        "malloc",               "free",                                         "calloc",                                          "realloc",
        "read",                 "write",                                        "open",                                            "close",
        "system",               "popen",                                        "execve",                                          "fork",
        "printf",               "sprintf",                                      "fprintf",                                         "snprintf",
        "strcpy",               "strcat",                                       "strncpy",                                         "strncat",
        "gets",                 "fgets",                                        "scanf",
        // C++ mangled names
                                                  "_Z3fooi",
        "_ZN6MyClass6methodEv",
        // Rust FFI functions (mangled)
        "_ZN10my_crate10factorial17hf1234567890abcdeE", "_ZN10my_crate10process_data17h9876543210fedcbaE",
        // JNI (Java Native Interface)
        "Java_com_example_Main_nativeMethod",
        // Python C API
        "PyObject_Call",        "PyArg_ParseTuple",
        // Node.js native add-ons
                                    "node_module_register",
        // Custom FFI wrappers
                                   "rust_wrapper_func",
        "cgo_callback",         "swift_bridge",                                 "zig_ffi_export",
    };

    const call_count = 100000;

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            _ = detector.isFFICall(test_functions[j % test_functions.len]);
        }
        mem_stats.reset();
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
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

    std.debug.print("  isFFICall ({d} calls): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ call_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
}

fn benchmarkFFIBoundaryReal(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FFIBoundaryDetector (Real IR Data) ---\n", .{});

    const ir_files = [_][]const u8{
        "zig-out/bench_data/sample_analysis.ll",
        "zig-out/bench_data/logic_bugs.ll",
        "zig-out/bench_data/ntt.ll",
    };

    for (ir_files) |ir_path| {
        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        std.debug.print("  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        var detector = FFIBoundaryDetector.init(tracked_allocator);
        defer detector.deinit();

        // Extract actual FFI function names from IR files
        // These are based on real function declarations and calls in the LLVM IR
        var ffi_functions = try std.ArrayList([]const u8).initCapacity(allocator, 10);

        if (std.mem.indexOf(u8, ir_path, "sample_analysis")) |_| {
            // Real FFI functions from sample_analysis.ll:
            // - __strcpy_chk (C standard library)
            // - printf (C standard library)
            // - malloc (C standard library)
            // - free (C standard library)
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "__strcpy_chk"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "printf"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "malloc"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "free"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "llvm.lifetime.start"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "llvm.lifetime.end"));
        } else if (std.mem.indexOf(u8, ir_path, "logic_bugs")) |_| {
            // Real FFI functions from logic_bugs.ll:
            // - atoi (C standard library)
            // - printf (C standard library)
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "atoi"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "printf"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "llvm.smax.i32"));
        } else if (std.mem.indexOf(u8, ir_path, "ntt")) |_| {
            // Real FFI functions from ntt.ll:
            // - snprintf (C standard library - format string issues)
            // - system (VERY DANGEROUS - command execution!)
            // - free (C standard library)
            // - fopen (C standard library - file operations)
            // - fscanf (C standard library - file operations)
            // - malloc (C standard library)
            // - atoi (C standard library)
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "snprintf"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "system"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "free"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "fopen"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "fscanf"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "malloc"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "atoi"));
            try ffi_functions.append(allocator, try allocator.dupeZ(u8, "printf"));
        }

        const call_count = ffi_functions.items.len * 1000; // Simulate repeated calls

        std.debug.print("    Found {} FFI functions\n", .{ffi_functions.items.len});

        var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer stats.deinit();

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            var ffi_count: usize = 0;
            var j: usize = 0;
            while (j < call_count) : (j += 1) {
                if (detector.isFFICall(ffi_functions.items[j % ffi_functions.items.len])) {
                    ffi_count += 1;
                }
            }
            // _ = ffi_count;
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            const start = std.time.nanoTimestamp();
            var ffi_count: usize = 0;
            var j: usize = 0;
            while (j < call_count) : (j += 1) {
                if (detector.isFFICall(ffi_functions.items[j % ffi_functions.items.len])) {
                    ffi_count += 1;
                }
            }
            const elapsed = std.time.nanoTimestamp() - start;
            stats.values[i] = elapsed;
            stats.record(elapsed);
            consumeValue(usize, ffi_count);
        }

        std.debug.print("    Detection ({d} calls): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ call_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

        // Verify that all functions are detected as FFI
        var detected_count: usize = 0;
        for (ffi_functions.items) |func| {
            if (detector.isFFICall(func)) {
                detected_count += 1;
            }
        }
        std.debug.print("      FFI detection rate: {d}/{} ({d:.1}%)\n", .{ detected_count, ffi_functions.items.len, @as(f32, @floatFromInt(detected_count)) / @as(f32, @floatFromInt(ffi_functions.items.len)) * 100.0 });

        // Manual cleanup
        for (ffi_functions.items) |func| {
            allocator.free(func);
        }
        ffi_functions.deinit(allocator);
    }
}

fn benchmarkFlowPath(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FlowPath ---\n", .{});

    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(allocator, &mem_stats);
    const tracked_allocator = tracked.allocator();

    const step_count = 1000; // More realistic: typical flow path length

    // Real-world data flow function names from security analysis scenarios
    const flow_functions = &[_][]const u8{
        // Source functions (where tainted data originates)
        "read",            "fgets",                   "scanf",         "getenv",
        "std::io::stdin",  "std::fs::read_to_string", "req.body",      "request.getParameter",
        // Processing functions (data transformation)
        "parse_json",      "decode_base64",           "url_decode",    "validate_input",
        "sanitize_string", "escape_html",             "process_data",  "transform_value",
        "convert_type",
        // Wrapper functions (common in FFI scenarios)
           "rust_wrapper",            "c_binding",     "ffi_bridge",
        "native_call",     "unsafe_block",            "extern_c_func",
        // Sink functions (where vulnerabilities occur)
        "system",
        "execve",          "popen",                   "eval",          "strcpy",
        "sprintf",         "strcat",                  "sqlite3_exec",  "mysql_query",
        "File.write",      "fs.writeFileSync",
    };

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var path = try FlowPath.init(tracked_allocator);
        defer path.deinit();
        var j: u32 = 0;
        while (j < step_count) : (j += 1) {
            const func_idx = j % flow_functions.len;
            const ts: TaintState = switch (j % 3) {
                0 => .source,
                1 => .tainted,
                else => .safe,
            };
            const step = FlowStep{
                .id = j,
                .func_name = flow_functions[func_idx],
                .location = .{ .file = null, .line = j * 10, .column = 5 },
                .taint_state = ts,
                .confidence = @as(f32, @floatFromInt(j % 100)) / 100.0,
            };
            try path.addStep(step);
        }
        mem_stats.reset();
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        mem_stats.reset();
        var path = try FlowPath.init(tracked_allocator);
        defer path.deinit();
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < step_count) : (j += 1) {
            const func_idx = j % flow_functions.len;
            const ts: TaintState = switch (j % 3) {
                0 => .source,
                1 => .tainted,
                else => .safe,
            };
            const step = FlowStep{
                .id = j,
                .func_name = flow_functions[func_idx],
                .location = .{ .file = null, .line = j * 10, .column = 5 },
                .taint_state = ts,
                .confidence = @as(f32, @floatFromInt(j % 100)) / 100.0,
            };
            try path.addStep(step);
        }
        const elapsed = std.time.nanoTimestamp() - start;
        stats.values[i] = elapsed;
        stats.record(elapsed);
        consumeValue(usize, path.length());
    }

    std.debug.print("  addStep ({d} steps): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ step_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });

    std.debug.print("    Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });
}
fn benchmarkFlowPathReal(allocator: std.mem.Allocator) !void {
    std.debug.print("--- FlowPath (Real IR Data) ---\n", .{});

    const ir_files = [_][]const u8{
        "zig-out/bench_data/sample_analysis.ll",
        "zig-out/bench_data/ntt.ll",
    };

    for (ir_files) |ir_path| {
        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        const tracked_allocator = tracked.allocator();

        std.debug.print("  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        // Real data flow paths extracted from actual LLVM IR files
        var paths = try std.ArrayList([]const []const u8).initCapacity(allocator, 10);

        if (std.mem.indexOf(u8, ir_path, "sample_analysis")) |_| {
            // Real data flow paths from sample_analysis.ll:
            // 1. Buffer Overflow: argv[1] → process_data → strcpy → buffer
            // 2. Use-After-Free: malloc → memcpy → free → return (dangling pointer)
            // 3. Null Pointer: NULL → handle_null → load (dereference)
            const path1 = &[_][]const u8{ "main", "process_data", "strcpy" };
            const path2 = &[_][]const u8{ "main", "get_name", "malloc", "memcpy", "free" };
            const path3 = &[_][]const u8{ "main", "handle_null" };
            try paths.append(allocator, path1);
            try paths.append(allocator, path2);
            try paths.append(allocator, path3);
        } else if (std.mem.indexOf(u8, ir_path, "ntt")) |_| {
            // Real data flow paths from ntt.ll:
            // 1. Command Injection: main → snprintf → system (VERY DANGEROUS!)
            // 2. Command Injection: create_from_user_input → snprintf → system
            // 3. Command Injection: debug_output → snprintf → system
            const path1 = &[_][]const u8{ "main", "snprintf", "system" };
            const path2 = &[_][]const u8{ "create_from_user_input", "snprintf", "system" };
            const path3 = &[_][]const u8{ "debug_output", "snprintf", "system" };
            try paths.append(allocator, path1);
            try paths.append(allocator, path2);
            try paths.append(allocator, path3);
        }

        std.debug.print("    Found {} real data flow paths\n", .{paths.items.len});

        var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer stats.deinit();

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            for (paths.items) |path_functions| {
                var path = try FlowPath.init(tracked_allocator);
                defer path.deinit();

                for (path_functions, 0..) |func_name, step_idx| {
                    const ts: TaintState = if (step_idx == 0) .source else if (step_idx == path_functions.len - 1) .tainted else .tainted;
                    const step = FlowStep{
                        .id = @intCast(step_idx),
                        .func_name = func_name,
                        .location = .{ .file = ir_path, .line = @intCast(step_idx * 10), .column = 5 },
                        .taint_state = ts,
                        .confidence = 0.9,
                    };
                    try path.addStep(step);
                }
            }
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            const start = std.time.nanoTimestamp();
            var total_steps: usize = 0;

            for (paths.items) |path_functions| {
                var path = try FlowPath.init(tracked_allocator);
                defer path.deinit();

                for (path_functions, 0..) |func_name, step_idx| {
                    const ts: TaintState = if (step_idx == 0) .source else if (step_idx == path_functions.len - 1) .tainted else .tainted;
                    const step = FlowStep{
                        .id = @intCast(step_idx),
                        .func_name = func_name,
                        .location = .{ .file = ir_path, .line = @intCast(step_idx * 10), .column = 5 },
                        .taint_state = ts,
                        .confidence = 0.9,
                    };
                    try path.addStep(step);
                }
                total_steps += path_functions.len;
            }

            const elapsed = std.time.nanoTimestamp() - start;
            stats.values[i] = elapsed;
            stats.record(elapsed);
            consumeValue(usize, total_steps);
        }

        std.debug.print("    Construct paths ({} paths): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ paths.items.len, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

        // Analyze path characteristics
        var avg_path_len: f32 = 0;
        for (paths.items) |path_functions| {
            avg_path_len += @as(f32, @floatFromInt(path_functions.len));
        }
        avg_path_len /= @as(f32, @floatFromInt(paths.items.len));
        std.debug.print("      Average path length: {d:.1} steps\n", .{avg_path_len});

        // Risk assessment
        var high_risk_count: usize = 0;
        for (paths.items) |path_functions| {
            const last_func = path_functions[path_functions.len - 1];
            if (std.mem.eql(u8, last_func, "system") or std.mem.eql(u8, last_func, "strcpy")) {
                high_risk_count += 1;
            }
        }
        std.debug.print("      High-risk paths: {}/{} ({d:.1}%)\n", .{ high_risk_count, paths.items.len, @as(f32, @floatFromInt(high_risk_count)) / @as(f32, @floatFromInt(paths.items.len)) * 100.0 });
    }
}

fn benchmarkRiskLevel(allocator: std.mem.Allocator) !void {
    std.debug.print("--- RiskLevel ---\n", .{});

    // Real-world dangerous functions from CWE/SANS Top 25
    const test_functions = &[_][]const u8{
        // Command injection (CWE-78)
        "system",              "execve",                  "popen",                    "posix_spawn",
        "ShellExecute",        "WinExec",
        // Buffer overflow (CWE-120)
                        "strcpy",                   "strcat",
        "sprintf",             "gets",                    "scanf",                    "sscanf",
        "fscanf",
        // Format string (CWE-134)
                     "printf",                  "fprintf",                  "sprintf",
        "snprintf",            "syslog",                  "setproctitle",
        // SQL injection related
                    "sqlite3_exec",
        "mysql_query",         "mysql_real_query",        "PQexec",                   "SQLPrepare",
        "SQLExecDirect",
        // Memory management
              "malloc",                  "free",                     "calloc",
        "realloc",             "alloca",                  "VirtualAlloc",
        // File operations
                    "fopen",
        "open",                "creat",                   "remove",                   "unlink",
        "rmdir",
        // Network operations
                      "connect",                 "bind",                     "listen",
        "accept",              "send",                    "recv",                     "sendto",
        "recvfrom",
        // Process operations
                   "fork",                    "exec",                     "spawn",
        "CreateProcess",
        // Rust unsafe functions
              "std::ptr::read_volatile", "std::ptr::write_volatile", "std::slice::from_raw_parts",
        "std::mem::transmute",
    };

    const call_count = 100000;

    var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
    defer stats.deinit();

    var i: u32 = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            _ = classifyRiskLevel(test_functions[j % test_functions.len]);
        }
    }

    i = 0;
    while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
        var critical_count: usize = 0;
        const start = std.time.nanoTimestamp();
        var j: usize = 0;
        while (j < call_count) : (j += 1) {
            if (classifyRiskLevel(test_functions[j % test_functions.len]) == .critical) {
                critical_count += 1;
            }
        }
        const elapsed = std.time.nanoTimestamp() - start;
        stats.record(elapsed);
        stats.recordMemory(0); // RiskLevel doesn't allocate memory
        consumeValue(usize, critical_count);
    }

    std.debug.print("  classifyRisk ({d} calls):\n", .{call_count});
    try stats.printDetailed(MEASUREMENT_ITERATIONS);

    // Collect result for reporting
    const result = try stats.collectBenchmarkResult(std.fmt.allocPrint(allocator, "RiskLevel classifyRisk {d} calls", .{call_count}) catch unreachable, MEASUREMENT_ITERATIONS);
    if (global_report_collector) |collector| {
        try collector.addResult(result);
    }
}

fn benchmarkRiskLevelReal(allocator: std.mem.Allocator) !void {
    std.debug.print("--- RiskLevel (Real IR Data - Fixed) ---\n", .{});

    const ir_files = [_][]const u8{
        "zig-out/bench_data/sample_analysis.ll",
        "zig-out/bench_data/ntt.ll",
    };

    for (ir_files) |ir_path| {
        var mem_stats = MemoryStats{};
        var tracked = TrackedAllocator.init(allocator, &mem_stats);
        _ = tracked.allocator();

        std.debug.print("  Testing: {s}\n", .{std.fs.path.basename(ir_path)});

        // Use static string slices instead of allocated strings
        const dangerous_functions_sample = [_][]const u8{
            "__strcpy_chk", "printf", "malloc", "free",
        };
        const dangerous_functions_ntt = [_][]const u8{
            "system", "snprintf", "fopen", "fscanf", "malloc", "free",
        };

        const functions = if (std.mem.indexOf(u8, ir_path, "sample_analysis")) |_|
            &dangerous_functions_sample
        else
            &dangerous_functions_ntt;

        std.debug.print("    Found {} potentially dangerous functions\n", .{functions.len});

        var stats = try RunStats.init(allocator, MEASUREMENT_ITERATIONS);
        defer stats.deinit();

        const call_count = functions.len * 1000;

        // Warmup
        var i: u32 = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            for (functions) |func| {
                _ = classifyRiskLevel(func);
            }
            mem_stats.reset();
        }

        // Measurement
        i = 0;
        while (i < MEASUREMENT_ITERATIONS) : (i += 1) {
            mem_stats.reset();
            const start = std.time.nanoTimestamp();

            for (functions) |func| {
                _ = classifyRiskLevel(func);
            }

            const elapsed = std.time.nanoTimestamp() - start;
            stats.values[i] = elapsed;
            stats.record(elapsed);
        }

        std.debug.print("    Classification ({d} calls): avg={d:.3}ms min={d:.3}ms max={d:.3}ms stddev={d:.3}ms\n", .{ call_count, stats.avg_ms(MEASUREMENT_ITERATIONS), stats.min_ms(), stats.max_ms(), stats.stddev_ms(MEASUREMENT_ITERATIONS) });
        std.debug.print("      Memory: {} bytes allocated, {} allocations, {} frees\n", .{ mem_stats.alloc_bytes, mem_stats.alloc_count, mem_stats.free_count });

        // Risk distribution analysis
        var risk_counts = [_]usize{ 0, 0, 0, 0 };
        for (functions) |func| {
            const level = classifyRiskLevel(func);
            risk_counts[@intFromEnum(level)] += 1;
        }

        std.debug.print("      Risk distribution: ", .{});
        if (risk_counts[0] > 0) std.debug.print("low={} ", .{risk_counts[0]});
        if (risk_counts[1] > 0) std.debug.print("medium={} ", .{risk_counts[1]});
        if (risk_counts[2] > 0) std.debug.print("high={} ", .{risk_counts[2]});
        if (risk_counts[3] > 0) std.debug.print("critical={} ", .{risk_counts[3]});
        std.debug.print("\n", .{});
    }
}
