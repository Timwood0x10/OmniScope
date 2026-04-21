//! Performance Profiler
//!
//! This module provides profiling utilities to measure and analyze
//! performance bottlenecks in the analyzer.

const std = @import("std");
const time = std.time;

/// Timer for measuring elapsed time
pub const Timer = struct {
    start_time: time.Instant,

    /// Start a new timer
    pub fn start() Timer {
        return .{
            .start_time = time.Instant.now() catch unreachable,
        };
    }

    /// Get elapsed time in nanoseconds
    pub fn elapsedNs(self: *const Timer) u64 {
        const end = time.Instant.now() catch unreachable;
        return end.since(self.start_time);
    }

    /// Get elapsed time in microseconds
    pub fn elapsedUs(self: *const Timer) f64 {
        return @as(f64, @floatFromInt(self.elapsedNs())) / 1000.0;
    }

    /// Get elapsed time in milliseconds
    pub fn elapsedMs(self: *const Timer) f64 {
        return self.elapsedUs() / 1000.0;
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

    /// Print report to stderr
    pub fn report(self: *const Profiler) void {
        std.debug.print("\n=== Performance Profile Report ===\n\n", .{});
        std.debug.print("{s:<30} {s:>10} {s:>12} {s:>12} {s:>12}\n", .{
            "Operation",
            "Calls",
            "Total (ms)",
            "Avg (us)",
            "Max (us)",
        });
        std.debug.print("{s:-<80}\n", .{""});

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const s = entry.value_ptr.*;
            std.debug.print("{s:<30} {d:>10} {d:>12.2} {d:>12.2} {d:>12.2}\n", .{
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
    pub fn start(profiler: *Profiler, name: []const u8) ScopedTimer {
        return .{
            .profiler = profiler,
            .name = name,
            .timer = Timer.start(),
        };
    }

    /// Stop and record the timing
    pub fn stop(self: *ScopedTimer) !void {
        const ns = self.timer.elapsedNs();
        try self.profiler.record(self.name, ns);
    }
};

// Unit tests

test "Timer - elapsed time" {
    const timer = Timer.start();
    std.time.sleep(1_000_000); // 1ms
    const elapsed = timer.elapsedNs();
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
        var scoped = ScopedTimer.start(&profiler, "scoped_test");
        std.time.sleep(100_000); // 100us
        try scoped.stop();
    }

    const stats = profiler.get("scoped_test").?;
    try std.testing.expect(stats.total_ns >= 100_000);
}
