//! Memory Pool for Performance Optimization
//!
//! This module provides a memory pool allocator to reduce allocation overhead.
//! Instead of many small allocations, we allocate large chunks and sub-allocate.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Memory pool for fixed-size allocations.
/// Reduces allocation overhead by pre-allocating chunks.
pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const chunk_size = 256;

        /// Free node for tracking freed items
        const FreeNode = struct {
            next: ?*FreeNode,
            item: *T,
        };

        /// Chunk of pre-allocated items
        const Chunk = struct {
            items: [chunk_size]T,
            used: usize,
            next: ?*Chunk,
        };

        allocator: Allocator,
        current_chunk: ?*Chunk,
        free_list: ?*FreeNode,
        free_node_pool: std.ArrayList(FreeNode),
        total_allocated: usize,
        total_reused: usize,
        total_freed: usize,

        /// Initialize a new memory pool
        pub fn init(allocator: Allocator) !Self {
            return .{
                .allocator = allocator,
                .current_chunk = null,
                .free_list = null,
                .free_node_pool = try std.ArrayList(FreeNode).initCapacity(allocator, 0),
                .total_allocated = 0,
                .total_reused = 0,
                .total_freed = 0,
            };
        }

        /// Free all resources
        pub fn deinit(self: *Self) void {
            var chunk = self.current_chunk;
            while (chunk) |c| {
                const next = c.next;
                self.allocator.destroy(c);
                chunk = next;
            }
            self.free_node_pool.deinit(self.allocator);
        }

        /// Allocate a new item from the pool
        pub fn alloc(self: *Self) !*T {
            if (self.free_list) |node| {
                self.free_list = node.next;
                const item = node.item;
                self.total_reused += 1;
                return item;
            }

            if (self.current_chunk) |chunk| {
                if (chunk.used < chunk_size) {
                    const item = &chunk.items[chunk.used];
                    chunk.used += 1;
                    self.total_allocated += 1;
                    return item;
                }
            }

            const new_chunk = try self.allocator.create(Chunk);
            new_chunk.* = .{
                .items = [_]T{undefined} ** chunk_size,
                .used = 1,
                .next = self.current_chunk,
            };
            self.current_chunk = new_chunk;

            self.total_allocated += 1;
            return &new_chunk.items[0];
        }

        /// Return an item to the pool
        pub fn free(self: *Self, item: *T) !void {
            const node = try self.free_node_pool.addOne();
            node.* = .{
                .next = self.free_list,
                .item = item,
            };
            self.free_list = node;
            self.total_freed += 1;
        }

        /// Get statistics
        pub fn stats(self: *const Self) struct {
            allocated: usize,
            reused: usize,
            freed: usize,
            in_use: usize,
        } {
            return .{
                .allocated = self.total_allocated,
                .reused = self.total_reused,
                .freed = self.total_freed,
                .in_use = self.total_allocated - self.total_freed,
            };
        }
    };
}

/// Arena allocator for batch allocations.
/// All allocations are freed at once.
pub const ArenaAllocator = struct {
    const Self = @This();
    const block_size = 4096;

    const Block = struct {
        data: []u8,
        used: usize,
        next: ?*Block,
    };

    allocator: Allocator,
    current_block: ?*Block,
    total_size: usize,

    /// Initialize arena
    pub fn init(backing_allocator: Allocator) !Self {
        return .{
            .allocator = backing_allocator,
            .current_block = null,
            .total_size = 0,
        };
    }

    /// Free all blocks
    pub fn deinit(self: *Self) void {
        var block = self.current_block;
        while (block) |b| {
            const next = b.next;
            self.allocator.free(b.data);
            self.allocator.destroy(b);
            block = next;
        }
    }

    /// Allocate bytes from arena
    pub fn alloc(self: *Self, len: usize, alignment: usize) ![]u8 {
        if (self.current_block) |block| {
            const aligned_start = std.mem.alignForward(usize, block.used, alignment);
            if (aligned_start + len <= block.data.len) {
                block.used = aligned_start + len;
                return block.data[aligned_start .. aligned_start + len];
            }
        }

        const alloc_size = @max(std.math.add(usize, len, alignment) catch return error.OutOfMemory, block_size);
        const block = try self.allocator.create(Block);
        errdefer self.allocator.destroy(block);

        const data = try self.allocator.alloc(u8, alloc_size);
        const data_addr = @intFromPtr(data.ptr);
        const aligned_addr = std.mem.alignForward(usize, data_addr, alignment);
        const offset = aligned_addr - data_addr;
        block.* = .{
            .data = data,
            .used = offset + len,
            .next = self.current_block,
        };
        self.current_block = block;
        self.total_size += alloc_size;

        return block.data[offset .. offset + len];
    }

    /// Create a typed value in the arena
    pub fn create(self: *Self, comptime T: type) !*T {
        const bytes = try self.alloc(@sizeOf(T), @alignOf(T));
        return @ptrCast(@alignCast(bytes.ptr));
    }

    /// Get allocator interface
    pub fn getAllocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = arenaAlloc,
                .resize = arenaResize,
                .free = arenaFree,
            },
        };
    }

    fn arenaAlloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const result = self.alloc(len, alignment.toByteUnits()) catch return null;
        return result.ptr;
    }

    fn arenaResize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn arenaFree(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void {}
};

// Unit tests

test "MemoryPool - basic operations" {
    var pool = try MemoryPool(u32).init(std.testing.allocator);
    defer pool.deinit();

    const item1 = try pool.alloc();
    item1.* = 42;

    const item2 = try pool.alloc();
    item2.* = 100;

    const s = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s.allocated);
    try std.testing.expectEqual(@as(usize, 0), s.freed);
    try std.testing.expectEqual(@as(usize, 2), s.in_use);

    try pool.free(item1);

    const s2 = pool.stats();
    try std.testing.expectEqual(@as(usize, 1), s2.freed);
    try std.testing.expectEqual(@as(usize, 1), s2.in_use);
}

test "MemoryPool - reuse freed items" {
    var pool = try MemoryPool(u32).init(std.testing.allocator);
    defer pool.deinit();

    const item1 = try pool.alloc();
    item1.* = 42;
    try pool.free(item1);

    const item2 = try pool.alloc();
    try std.testing.expectEqual(@as(u32, 42), item2.*);
}

test "MemoryPool - multiple chunks" {
    var pool = try MemoryPool(u32).init(std.testing.allocator);
    defer pool.deinit();

    // Allocate more than one chunk
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        const item = try pool.alloc();
        item.* = @intCast(i);
    }

    const s = pool.stats();
    try std.testing.expectEqual(@as(usize, 300), s.allocated);
}

test "ArenaAllocator - basic allocation" {
    var arena = try ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const bytes = try arena.alloc(100, 1);
    try std.testing.expectEqual(@as(usize, 100), bytes.len);
}

test "ArenaAllocator - create typed value" {
    var arena = try ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const value = try arena.create(u64);
    value.* = 123456789;

    try std.testing.expectEqual(@as(u64, 123456789), value.*);
}

test "ArenaAllocator - multiple allocations" {
    var arena = try ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const bytes = try arena.alloc(50, 1);
        try std.testing.expectEqual(@as(usize, 50), bytes.len);
    }
}
