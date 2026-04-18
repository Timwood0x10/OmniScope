//! Optimized Analysis Context
//!
//! This module provides an optimized context for analysis passes,
//! using arena allocation and memory pools to reduce overhead.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = @import("../perf/memory_pool.zig").ArenaAllocator;
const Profiler = @import("../perf/profiler.zig").Profiler;

/// Optimized analysis context with arena allocation
pub const AnalysisContext = struct {
    /// Backing allocator for arena
    backing_allocator: Allocator,
    /// Arena for batch allocations
    arena: ArenaAllocator,
    /// Profiler for performance tracking
    profiler: Profiler,
    /// Whether profiling is enabled
    profiling_enabled: bool,

    /// Initialize a new analysis context
    pub fn init(backing_allocator: Allocator) !AnalysisContext {
        return .{
            .backing_allocator = backing_allocator,
            .arena = try ArenaAllocator.init(backing_allocator),
            .profiler = Profiler.init(backing_allocator),
            .profiling_enabled = false,
        };
    }

    /// Initialize with profiling enabled
    pub fn initWithProfiling(backing_allocator: Allocator) !AnalysisContext {
        var ctx = try init(backing_allocator);
        ctx.profiling_enabled = true;
        return ctx;
    }

    /// Free all resources
    pub fn deinit(self: *AnalysisContext) void {
        self.arena.deinit();
        self.profiler.deinit();
    }

    /// Get the arena allocator for batch allocations
    pub fn arenaAllocator(self: *AnalysisContext) Allocator {
        return self.arena.getAllocator();
    }

    /// Allocate bytes from the arena
    pub fn alloc(self: *AnalysisContext, comptime T: type, count: usize) ![]T {
        const bytes = try self.arena.alloc(count * @sizeOf(T), @alignOf(T));
        return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..count];
    }

    /// Create a single value in the arena
    pub fn create(self: *AnalysisContext, comptime T: type) !*T {
        return try self.arena.create(T);
    }

    /// Duplicate a string in the arena
    pub fn dupe(self: *AnalysisContext, bytes: []const u8) ![]u8 {
        const result = try self.arena.alloc(bytes.len, 1);
        @memcpy(result, bytes);
        return result;
    }

    /// Start profiling an operation
    pub fn startProfile(self: *AnalysisContext, name: []const u8) ?@import("../perf/profiler.zig").ScopedTimer {
        if (!self.profiling_enabled) return null;
        return @import("../perf/profiler.zig").ScopedTimer.start(&self.profiler, name);
    }

    /// Record a timing manually
    pub fn recordTime(self: *AnalysisContext, name: []const u8, ns: u64) !void {
        if (!self.profiling_enabled) return;
        try self.profiler.record(name, ns);
    }

    /// Print profiling report
    pub fn printProfileReport(self: *AnalysisContext, writer: anytype) !void {
        if (!self.profiling_enabled) {
            try writer.print("Profiling not enabled\n", .{});
            return;
        }
        try self.profiler.printReport(writer);
    }

    /// Get total memory used
    pub fn totalMemoryUsed(self: *const AnalysisContext) usize {
        return self.arena.total_size;
    }

    /// Reset arena for reuse (keeps profiler data)
    pub fn resetArena(self: *AnalysisContext) !void {
        self.arena.deinit();
        self.arena = try ArenaAllocator.init(self.backing_allocator);
    }
};

/// String interning for reducing string allocations
pub const StringInterner = struct {
    strings: std.StringHashMap(void),
    allocator: Allocator,

    /// Initialize a new string interner
    pub fn init(allocator: Allocator) StringInterner {
        return .{
            .strings = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *StringInterner) void {
        var iter = self.strings.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.strings.deinit();
    }

    /// Intern a string (returns canonical pointer)
    pub fn intern(self: *StringInterner, str: []const u8) ![]const u8 {
        if (self.strings.get(str)) |_| {
            return str;
        }

        const copy = try self.allocator.dupe(u8, str);
        try self.strings.put(copy, {});
        return copy;
    }

    /// Get interned string if exists
    pub fn get(self: *const StringInterner, str: []const u8) ?[]const u8 {
        return if (self.strings.contains(str)) str else null;
    }

    /// Get count of interned strings
    pub fn count(self: *const StringInterner) usize {
        return self.strings.count();
    }
};

// Unit tests

test "AnalysisContext - init and deinit" {
    var ctx = try AnalysisContext.init(std.testing.allocator);
    defer ctx.deinit();
    try std.testing.expectEqual(@as(usize, 0), ctx.totalMemoryUsed());
}

test "AnalysisContext - arena allocation" {
    var ctx = try AnalysisContext.init(std.testing.allocator);
    defer ctx.deinit();

    const slice = try ctx.alloc(u32, 100);
    try std.testing.expectEqual(@as(usize, 100), slice.len);

    const ptr = try ctx.create(u64);
    ptr.* = 42;
    try std.testing.expectEqual(@as(u64, 42), ptr.*);
}

test "AnalysisContext - string duplication" {
    var ctx = try AnalysisContext.init(std.testing.allocator);
    defer ctx.deinit();

    const str = try ctx.dupe("hello world");
    try std.testing.expectEqualStrings("hello world", str);
}

test "AnalysisContext - profiling" {
    var ctx = try AnalysisContext.initWithProfiling(std.testing.allocator);
    defer ctx.deinit();

    {
        var timer = ctx.startProfile("test_op").?;
        std.time.sleep(100_000);
        try timer.stop();
    }

    const stats = ctx.profiler.get("test_op");
    try std.testing.expect(stats != null);
    try std.testing.expect(stats.?.total_ns >= 100_000);
}

test "StringInterner - basic operations" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    const s1 = try interner.intern("hello");
    const s2 = try interner.intern("hello");
    const s3 = try interner.intern("world");

    try std.testing.expectEqualStrings("hello", s1);
    try std.testing.expectEqualStrings("hello", s2);
    try std.testing.expectEqualStrings("world", s3);
    try std.testing.expectEqual(@as(usize, 2), interner.count());
}
