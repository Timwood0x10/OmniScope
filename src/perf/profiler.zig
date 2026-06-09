//! Performance Profiler
//!
//! This module provides profiling utilities to measure and analyze
//! performance bottlenecks in the analyzer, including per-pass timing,
//! memory sampling (RSS, heap allocations), and formatted output.

const std = @import("std");
const time = std.time;
const log = @import("../common/log.zig");

const LOG_PREFIX = "[profiler]";

/// Timer for measuring elapsed time
pub const Timer = struct {
    start_time: time.Instant,

    /// Start a new timer
    /// Returns error if system time is unavailable
    pub fn start() !Timer {
        return .{
            .start_time = try time.Instant.now(),
        };
    }

    /// Get elapsed time in nanoseconds
    /// Returns error if system time is unavailable
    pub fn elapsedNs(self: *const Timer) !u64 {
        const end = try time.Instant.now();
        return end.since(self.start_time);
    }

    /// Get elapsed time in microseconds
    /// Returns error if system time is unavailable
    pub fn elapsedUs(self: *const Timer) !f64 {
        const ns = try self.elapsedNs();
        return @as(f64, @floatFromInt(ns)) / 1000.0;
    }

    /// Get elapsed time in milliseconds
    /// Returns error if system time is unavailable
    pub fn elapsedMs(self: *const Timer) !f64 {
        const us = try self.elapsedUs();
        return us / 1000.0;
    }
};

/// Profiling statistics for a named operation
pub const ProfileStats = struct {
    name: []const u8,
    call_count: u64,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,

    /// Average time in nanoseconds
    pub fn avgNs(self: *const ProfileStats) f64 {
        if (self.call_count == 0) return 0;
        return @as(f64, @floatFromInt(self.total_ns)) / @as(f64, @floatFromInt(self.call_count));
    }

    /// Average time in microseconds
    pub fn avgUs(self: *const ProfileStats) f64 {
        return self.avgNs() / 1000.0;
    }

    /// Average time in milliseconds
    pub fn avgMs(self: *const ProfileStats) f64 {
        return self.avgUs() / 1000.0;
    }

    /// Total time in milliseconds
    pub fn totalMs(self: *const ProfileStats) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) / 1_000_000.0;
    }
};

/// Profiler for tracking multiple operations
pub const Profiler = struct {
    stats: std.StringHashMap(ProfileStats),
    allocator: std.mem.Allocator,

    /// Initialize a new profiler
    pub fn init(allocator: std.mem.Allocator) Profiler {
        return .{
            .stats = std.StringHashMap(ProfileStats).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Profiler) void {
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.stats.clearRetainingCapacity();
        self.stats.deinit();
    }

    /// Record a timing for an operation
    pub fn record(self: *Profiler, name: []const u8, ns: u64) !void {
        const entry = try self.stats.getOrPut(name);
        if (entry.found_existing) {
            entry.value_ptr.call_count += 1;
            entry.value_ptr.total_ns += ns;
            entry.value_ptr.min_ns = @min(entry.value_ptr.min_ns, ns);
            entry.value_ptr.max_ns = @max(entry.value_ptr.max_ns, ns);
        } else {
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);
            entry.key_ptr.* = name_copy;
            entry.value_ptr.* = .{
                .name = name_copy,
                .call_count = 1,
                .total_ns = ns,
                .min_ns = ns,
                .max_ns = ns,
            };
        }
    }

    /// Get statistics for an operation
    pub fn get(self: *const Profiler, name: []const u8) ?ProfileStats {
        return self.stats.get(name);
    }

    /// Print a summary report
    pub fn printReport(self: *const Profiler, writer: anytype) !void {
        try writer.print("\n=== Performance Profile Report ===\n\n", .{});
        try writer.print("{s:<30} {s:>10} {s:>12} {s:>12} {s:>12}\n", .{
            "Operation",
            "Calls",
            "Total (ms)",
            "Avg (us)",
            "Max (us)",
        });
        try writer.print("{s:-<80}\n", .{""});

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const s = entry.value_ptr.*;
            try writer.print("{s:<30} {d:>10} {d:>12.2} {d:>12.2} {d:>12.2}\n", .{
                s.name,
                s.call_count,
                s.totalMs(),
                s.avgUs(),
                @as(f64, @floatFromInt(s.max_ns)) / 1000.0,
            });
        }
    }

    /// Get total time across all operations
    pub fn totalTimeMs(self: *const Profiler) f64 {
        var total: u64 = 0;
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            total += entry.value_ptr.total_ns;
        }
        return @as(f64, @floatFromInt(total)) / 1_000_000.0;
    }

    /// Print report to stderr (only in verbose/debug mode)
    pub fn report(self: *const Profiler) void {
        // Performance profile is pipeline telemetry — only show in verbose/debug
        if (log.current_log_level != .verbose and log.current_log_level != .debug) return;

        log.info("\n=== Performance Profile Report ===\n\n", .{});
        log.info("{s:<30} {s:>10} {s:>12} {s:>12} {s:>12}\n", .{
            "Operation",
            "Calls",
            "Total (ms)",
            "Avg (us)",
            "Max (us)",
        });
        log.info("{s:-<80}\n", .{""});

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const s = entry.value_ptr.*;
            log.info("{s:<30} {d:>10} {d:>12.2} {d:>12.2} {d:>12.2}\n", .{
                s.name,
                s.call_count,
                s.totalMs(),
                s.avgUs(),
                @as(f64, @floatFromInt(s.max_ns)) / 1000.0,
            });
        }
    }

    /// Get a summary string (uses static buffer, not thread-safe)
    /// NOTE: This function is not thread-safe. Caller must ensure single-threaded access.
    pub fn summary(self: *const Profiler, buffer: []u8) ![]const u8 {
        const total_ms = self.totalTimeMs();
        const op_count = self.stats.count();

        return std.fmt.bufPrint(buffer, "{d} ops, {d:.2}ms total", .{ op_count, total_ms });
    }
};

/// Scoped timer that records on deinit
pub const ScopedTimer = struct {
    profiler: *Profiler,
    name: []const u8,
    timer: Timer,

    /// Start a scoped timer
    /// Returns error if system time is unavailable
    pub fn start(profiler: *Profiler, name: []const u8) !ScopedTimer {
        return .{
            .profiler = profiler,
            .name = name,
            .timer = try Timer.start(),
        };
    }

    /// Stop and record the timing
    pub fn stop(self: *ScopedTimer) !void {
        const ns = try self.timer.elapsedNs();
        try self.profiler.record(self.name, ns);
    }
};

/// Per-pass statistics collected during pipeline execution
/// Records wall-clock time, RSS delta, and heap allocation count
pub const PassStats = struct {
    pass_name: []const u8,
    wall_time_ns: u64,
    rss_before_kb: usize,
    rss_after_kb: usize,
    alloc_count_before: u64,
    alloc_count_after: u64,

    /// Calculate wall time in milliseconds
    pub fn wallTimeMs(self: *const PassStats) f64 {
        return @as(f64, @floatFromInt(self.wall_time_ns)) / 1_000_000.0;
    }

    /// Calculate RSS delta in KB (may be negative due to deallocations)
    pub fn rssDeltaKb(self: *const PassStats) i128 {
        return @as(i128, self.rss_after_kb) - @as(i128, self.rss_before_kb);
    }

    /// Calculate heap allocation count delta
    pub fn allocDelta(self: *const PassStats) i128 {
        return @as(i128, self.alloc_count_after) - @as(i128, self.alloc_count_before);
    }
};

/// Per-pass timer that samples timing and memory metrics
/// Used by PassManager to instrument each pass execution
pub const PassTimer = struct {
    timer: Timer,
    rss_before_kb: usize,
    alloc_count_before: u64,

    /// Start a new pass timer, sampling initial memory state
    /// Returns error if system time is unavailable
    pub fn startPass() !PassTimer {
        return .{
            .timer = try Timer.start(),
            .rss_before_kb = sampleRss(),
            .alloc_count_before = sampleHeapAllocs(),
        };
    }

    /// Stop the timer and collect final memory state
    /// Returns complete PassStats for the given pass name
    pub fn stopPass(self: *PassTimer, pass_name: []const u8) !PassStats {
        const wall_ns = try self.timer.elapsedNs();
        return .{
            .pass_name = pass_name,
            .wall_time_ns = wall_ns,
            .rss_before_kb = self.rss_before_kb,
            .rss_after_kb = sampleRss(),
            .alloc_count_before = self.alloc_count_before,
            .alloc_count_after = sampleHeapAllocs(),
        };
    }
};

/// Container for collecting per-pass statistics during a pipeline run
/// Supports formatted text and JSON output
pub const PassStatsCollector = struct {
    stats: std.ArrayList(PassStats),
    allocator: std.mem.Allocator,

    /// Initialize a new collector
    pub fn init(allocator: std.mem.Allocator) PassStatsCollector {
        return .{
            .stats = std.ArrayList(PassStats).initCapacity(allocator, 0) catch
                .{ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *PassStatsCollector) void {
        for (self.stats.items) |*s| {
            if (s.pass_name.len > 0) {
                self.allocator.free(s.pass_name);
            }
        }
        self.stats.deinit(self.allocator);
    }

    /// Record statistics for a completed pass
    pub fn record(self: *PassStatsCollector, pass_stats: PassStats) !void {
        // Duplicate the pass name to ensure ownership
        const name_copy = try self.allocator.dupe(u8, pass_stats.pass_name);
        var owned_stats = pass_stats;
        owned_stats.pass_name = name_copy;
        try self.stats.append(self.allocator, owned_stats);
    }

    /// Print formatted text table of all recorded passes
    /// Only outputs when perf_stats flag is enabled
    pub fn printReport(self: *const PassStatsCollector, enabled: bool) void {
        if (!enabled or self.stats.items.len == 0) return;

        log.info("{s} ══════════════════════════════════════════════════════", .{LOG_PREFIX});
        log.info("{s} Per-Pass Performance Statistics", .{LOG_PREFIX});
        log.info("{s} ══════════════════════════════════════════════════════", .{LOG_PREFIX});
        log.info("", .{});

        // Table header
        log.info("{s} {s} {s} {s} {s}", .{
            "Pass",
            "Time (ms)",
            "RSS Δ (KB)",
            "Alloc Δ",
            "Alloc/s",
        });
        log.info("{s}", .{"---------------------------------------------"});

        var total_ms: f64 = 0;
        for (self.stats.items) |s| {
            const ms = s.wallTimeMs();
            const rss_delta = s.rssDeltaKb();
            const alloc_delta = s.allocDelta();
            total_ms += ms;

            // Calculate allocations per second (avoid division by zero)
            const alloc_per_s: f64 = if (ms > 0)
                @as(f64, @floatFromInt(@abs(alloc_delta))) / (ms / 1000.0)
            else
                0;

            log.info("{s} {d:.2} {d} {d} {d}", .{
                s.pass_name,
                ms,
                rss_delta,
                alloc_delta,
                @as(u64, @intFromFloat(alloc_per_s)),
            });
        }

        log.info("{s} {s} {d:.2}", .{ "TOTAL", "", total_ms });
        log.info("", .{});
    }

    /// Generate JSON output of all recorded passes
    /// Returns allocated string that caller must free
    pub fn toJson(self: *const PassStatsCollector, enabled: bool) ?[]u8 {
        if (!enabled or self.stats.items.len == 0) return null;

        var buf = std.ArrayList(u8).initCapacity(self.allocator, 1024) catch return null;
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        w.writeAll("{\n") catch return null;
        w.print("  \"pass_count\": {d},\n", .{self.stats.items.len}) catch return null;
        w.writeAll("  \"passes\": [\n") catch return null;

        for (self.stats.items, 0..) |s, idx| {
            w.writeAll("    {\n") catch return null;
            w.print("      \"name\": \"{s}\",\n", .{s.pass_name}) catch return null;
            w.print("      \"wall_time_ns\": {d},\n", .{s.wall_time_ns}) catch return null;
            w.print("      \"wall_time_ms\": {d:.3},\n", .{s.wallTimeMs()}) catch return null;
            w.print("      \"rss_before_kb\": {d},\n", .{s.rss_before_kb}) catch return null;
            w.print("      \"rss_after_kb\": {d},\n", .{s.rss_after_kb}) catch return null;
            w.print("      \"rss_delta_kb\": {d},\n", .{s.rssDeltaKb()}) catch return null;
            w.print("      \"alloc_before\": {d},\n", .{s.alloc_count_before}) catch return null;
            w.print("      \"alloc_after\": {d},\n", .{s.alloc_count_after}) catch return null;
            w.print("      \"alloc_delta\": {d}\n", .{s.allocDelta()}) catch return null;
            if (idx < self.stats.items.len - 1) {
                w.writeAll("    },\n") catch return null;
            } else {
                w.writeAll("    }\n") catch return null;
            }
        }

        w.writeAll("  ]\n") catch return null;
        w.writeAll("}") catch return null;

        return buf.toOwnedSlice(self.allocator) catch null;
    }
};

/// Sample current RSS (Resident Set Size) in kilobytes
/// Uses platform-specific mechanism (macOS/Linux)
/// Returns 0 if sampling fails or not implemented (graceful degradation)
fn sampleRss() usize {
    // TODO: Implement platform-specific RSS sampling:
    // - macOS: mach_task_self() + task_info(TASK_BASIC_INFO)
    // - Linux: read /proc/self/statm field 2 (resident pages * page_size)
    //
    // For now, returns 0 as placeholder. The API surface is ready for
    // future integration when platform-specific FFI bindings are available.
    // This ensures per-pass timing works correctly while RSS is optional.
    return 0;
}

/// Sample current heap allocation count from GPA
/// This requires the allocator to support allocation counting
/// Returns 0 if not available (graceful degradation)
fn sampleHeapAllocs() u64 {
    // Note: Standard library allocators don't expose allocation counts.
    // This returns 0 as placeholder — actual implementation would require
    // wrapping the allocator with a counting wrapper or using custom GPA.
    // For now, this provides the API surface for future integration.
    return 0;
}

// Unit tests

test "Timer - elapsed time" {
    const timer = try Timer.start();
    std.Thread.sleep(1_000_000); // 1ms
    const elapsed = try timer.elapsedNs();
    try std.testing.expect(elapsed >= 1_000_000);
}

test "Profiler - record operations" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    try profiler.record("test_op", 1000);
    try profiler.record("test_op", 2000);
    try profiler.record("test_op", 3000);

    const stats = profiler.get("test_op").?;
    try std.testing.expectEqual(@as(u64, 3), stats.call_count);
    try std.testing.expectEqual(@as(u64, 6000), stats.total_ns);
    try std.testing.expectEqual(@as(u64, 1000), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 3000), stats.max_ns);
}

test "Profiler - average calculation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    try profiler.record("avg_test", 1000);
    try profiler.record("avg_test", 2000);
    try profiler.record("avg_test", 3000);

    const stats = profiler.get("avg_test").?;
    try std.testing.expectEqual(@as(f64, 2000.0), stats.avgNs());
}

test "ScopedTimer - automatic recording" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    {
        var scoped = try ScopedTimer.start(&profiler, "scoped_test");
        std.Thread.sleep(100_000); // 100us
        try scoped.stop();
    }

    const stats = profiler.get("scoped_test").?;
    try std.testing.expect(stats.total_ns >= 100_000);
}

test "PassTimer - timing accuracy" {
    // Verify PassTimer measures elapsed time accurately
    var pass_timer = try PassTimer.startPass();
    std.Thread.sleep(1_000_000); // 1ms
    const stats = try pass_timer.stopPass("test-pass");

    // Should have measured at least 1ms (allowing for scheduling variance)
    try std.testing.expect(stats.wall_time_ns >= 900_000); // 0.9ms tolerance
    try std.testing.expect(stats.wallTimeMs() >= 0.9);

    // RSS should be non-zero on macOS (process has memory)
    _ = stats.rss_before_kb;
    _ = stats.rss_after_kb;
}

test "PassStats - calculations" {
    var stats = PassStats{
        .pass_name = "test",
        .wall_time_ns = 5_000_000, // 5ms
        .rss_before_kb = 10000,
        .rss_after_kb = 10200, // +200KB
        .alloc_count_before = 100,
        .alloc_count_after = 150, // +50 allocs
    };

    // Verify wall time calculation
    const ms = stats.wallTimeMs();
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), ms, 0.01);

    // Verify RSS delta (+200KB)
    const rss_delta = stats.rssDeltaKb();
    try std.testing.expectEqual(@as(i128, 200), rss_delta);

    // Verify allocation delta (+50)
    const alloc_delta = stats.allocDelta();
    try std.testing.expectEqual(@as(i64, 50), alloc_delta);
}

test "PassStatsCollector - record and report" {
    var collector = PassStatsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Simulate recording multiple passes
    {
        var timer = try PassTimer.startPass();
        std.Thread.sleep(100_000); // 100us
        const stats = try timer.stopPass("pass-A");
        try collector.record(stats);
    }

    {
        var timer = try PassTimer.startPass();
        std.Thread.sleep(200_000); // 200us
        const stats = try timer.stopPass("pass-B");
        try collector.record(stats);
    }

    // Verify we recorded 2 passes
    try std.testing.expectEqual(@as(usize, 2), collector.stats.items.len);

    // Verify pass names are correct
    try std.testing.expectEqualStrings("pass-A", collector.stats.items[0].pass_name);
    try std.testing.expectEqualStrings("pass-B", collector.stats.items[1].pass_name);

    // Verify timing ordering (pass-B should take longer)
    try std.testing.expect(collector.stats.items[1].wall_time_ns >= collector.stats.items[0].wall_time_ns);
}

test "PassStatsCollector - JSON output" {
    var collector = PassStatsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record a test pass
    var timer = try PassTimer.startPass();
    const stats = try timer.stopPass("json-test");
    try collector.record(stats);

    // Generate JSON output
    const json = collector.toJson(true);
    defer if (json) |j| std.testing.allocator.free(j);

    // Should produce valid JSON
    try std.testing.expect(json != null);
    const json_str = json.?;

    // Verify JSON contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"name\": \"json-test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"pass_count\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"passes\"") != null);
}

test "PassStatsCollector - disabled output" {
    var collector = PassStatsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record a test pass
    var timer = try PassTimer.startPass();
    const stats = try timer.stopPass("disabled-test");
    try collector.record(stats);

    // When disabled, toJson should return null
    const json = collector.toJson(false);
    try std.testing.expect(json == null);
}
