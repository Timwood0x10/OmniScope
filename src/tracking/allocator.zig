//! Memory Tracking Allocator
//!
//! This module provides an allocator wrapper that tracks all memory allocations
//! and frees for accurate performance measurement and leak detection.

const std = @import("std");

/// Memory statistics tracked by the allocator
pub const MemoryStats = struct {
    /// Total bytes allocated
    alloc_bytes: usize = 0,
    /// Number of allocation operations
    alloc_count: usize = 0,
    /// Number of free operations
    free_count: usize = 0,

    /// Reset all statistics to zero
    pub fn reset(self: *MemoryStats) void {
        self.* = .{};
    }

    /// Get the net allocated bytes
    pub fn netAllocated(self: *const MemoryStats) usize {
        return self.alloc_bytes;
    }

    /// Check if allocation count matches free count
    pub fn isLeakFree(self: *const MemoryStats) bool {
        return self.alloc_count == self.free_count;
    }
};

/// Allocator wrapper that tracks memory operations
///
/// This allocator wraps any other allocator and tracks all allocations
/// and frees, recording statistics in a MemoryStats struct.
///
/// Usage:
/// ```zig
/// var mem_stats = MemoryStats{};
/// var tracked = TrackedAllocator.init(std.heap.page_allocator, &mem_stats);
/// const allocator = tracked.allocator();
///
/// var list = std.ArrayList(u8).init(allocator);
/// defer list.deinit();
///
/// std.debug.print("Allocated: {} bytes\n", .{mem_stats.alloc_bytes});
/// ```
pub const TrackedAllocator = struct {
    child_allocator: std.mem.Allocator,
    stats: *MemoryStats,

    const Self = @This();

    /// Initialize the tracked allocator
    ///
    /// Parameters:
    ///   - child_allocator: The underlying allocator to wrap
    ///   - stats: Pointer to MemoryStats struct for tracking
    ///
    /// Returns:
    ///   - Initialized TrackedAllocator
    pub fn init(child_allocator: std.mem.Allocator, stats: *MemoryStats) Self {
        return .{
            .child_allocator = child_allocator,
            .stats = stats,
        };
    }

    /// Get the std.mem.Allocator interface
    ///
    /// Returns:
    ///   - Allocator interface that can be used with standard library
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    /// Remap implementation (no-op for tracked allocator)
    fn remap(
        ctx: *anyopaque,
        old_mem: []u8,
        old_align: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.child_allocator.rawRemap(old_mem, old_align, new_len, ret_addr);
    }

    /// Allocation implementation
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        ptr_align: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.child_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;

        if (len > 0) {
            self.stats.alloc_bytes += len;
            self.stats.alloc_count += 1;
        }

        return result;
    }

    /// Resize implementation
    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        buf_align: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const old_len = buf.len;
        const success = self.child_allocator.rawResize(buf, buf_align, new_len, ret_addr);

        if (!success) return false;

        if (new_len > old_len) {
            self.stats.alloc_bytes += new_len - old_len;
        }

        return true;
    }

    /// Free implementation
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        buf_align: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (buf.len > 0) {
            self.stats.free_count += 1;
        }

        self.child_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

test "TrackedAllocator - basic allocation tracking" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 100), mem_stats.alloc_bytes);
    try std.testing.expectEqual(@as(usize, 1), mem_stats.alloc_count);
    try std.testing.expectEqual(@as(usize, 0), mem_stats.free_count);
}

test "TrackedAllocator - allocation and free tracking" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    const slice = try allocator.alloc(u8, 50);
    allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 50), mem_stats.alloc_bytes);
    try std.testing.expectEqual(@as(usize, 1), mem_stats.alloc_count);
    try std.testing.expectEqual(@as(usize, 1), mem_stats.free_count);
    try std.testing.expect(mem_stats.isLeakFree());
}

test "TrackedAllocator - ArrayList tracking" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    var list = try std.ArrayList(u32).initCapacity(allocator, 10);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try std.testing.expect(mem_stats.alloc_bytes > 0);
    try std.testing.expect(mem_stats.alloc_count > 0);
}

test "TrackedAllocator - HashMap tracking" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    var map = std.AutoHashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    try std.testing.expect(mem_stats.alloc_bytes > 0);
    try std.testing.expect(mem_stats.alloc_count > 0);
}

test "TrackedAllocator - reset statistics" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    const slice = try allocator.alloc(u8, 75);
    allocator.free(slice);

    try std.testing.expect(mem_stats.alloc_bytes > 0);

    mem_stats.reset();
    try std.testing.expectEqual(@as(usize, 0), mem_stats.alloc_bytes);
    try std.testing.expectEqual(@as(usize, 0), mem_stats.alloc_count);
    try std.testing.expectEqual(@as(usize, 0), mem_stats.free_count);
}

test "TrackedAllocator - leak detection" {
    var mem_stats = MemoryStats{};
    var tracked = TrackedAllocator.init(std.testing.allocator, &mem_stats);
    const allocator = tracked.allocator();

    const slice = try allocator.alloc(u8, 25);
    defer allocator.free(slice);

    try std.testing.expect(mem_stats.alloc_count > mem_stats.free_count);
    try std.testing.expect(!mem_stats.isLeakFree());
}
