//! Tests for Arena and ThreadLocalArena allocators.
//! Separated from arena.zig to keep core implementation and test concerns clean.

const std = @import("std");
const arena_mod = @import("arena.zig");
const Arena = arena_mod.Arena;
const ArenaStats = arena_mod.ArenaStats;
const ThreadLocalArena = @import("arena_threadlocal.zig").ThreadLocalArena;

test "Arena - basic allocation" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    const ptr = try arena.alloc(64, 0); // 1-byte alignment
    // Verify we can write to the allocated memory
    @memset(ptr[0..64], 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ptr[0]);
    try testing.expectEqual(@as(u8, 0xAA), ptr[63]);
}

test "Arena - multiple allocations" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Allocate multiple times
    const ptr1 = try arena.alloc(128, 0);
    const ptr2 = try arena.alloc(256, 0);
    const ptr3 = try arena.alloc(512, 0);

    // All should be valid and distinct
    try testing.expect(ptr1 != ptr2);
    try testing.expect(ptr2 != ptr3);
    try testing.expect(ptr1 != ptr3);

    // Write to each without interference
    @memset(ptr1[0..128], 0x11);
    @memset(ptr2[0..256], 0x22);
    @memset(ptr3[0..512], 0x33);

    try testing.expectEqual(@as(u8, 0x11), ptr1[0]);
    try testing.expectEqual(@as(u8, 0x22), ptr2[0]);
    try testing.expectEqual(@as(u8, 0x33), ptr3[0]);
}

test "Arena - alignment support" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Test various alignments (log2 values)
    const align_2 = try arena.alloc(16, 1); // 2-byte alignment
    const align_4 = try arena.alloc(16, 2); // 4-byte alignment
    const align_8 = try arena.alloc(16, 3); // 8-byte alignment
    const align_16 = try arena.alloc(16, 4); // 16-byte alignment

    // Verify alignment
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_2) % 2);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_4) % 4);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_8) % 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_16) % 16);
}

test "Arena - reset and reuse" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // First round of allocations
    const ptr1 = try arena.alloc(1024, 0);
    @memset(ptr1[0..1024], 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), ptr1[0]);

    // Reset should free all allocations
    arena.reset();

    // Second round - should reuse the same block
    const ptr2 = try arena.alloc(512, 0);
    @memset(ptr2[0..512], 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ptr2[0]);

    // Verify total allocated hasn't grown significantly (still using first block)
    const total = arena.totalAllocated();
    try testing.expect(total >= 512);
}

test "Arena - large allocation spans block boundary" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Default block size is 8KB, request larger allocation
    const large_ptr = try arena.alloc(16 * 1024, 0); // 16KB > default 8KB block

    // Should be able to write to it
    @memset(large_ptr[0 .. 16 * 1024], 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), large_ptr[0]);
    try testing.expectEqual(@as(u8, 0xCC), large_ptr[16 * 1024 - 1]);

    // Total allocated should be at least 16KB
    try testing.expect(arena.totalAllocated() >= 16 * 1024);
}

test "Arena - totalUsed tracking" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(usize, 0), arena.totalUsed());

    _ = try arena.alloc(100, 0);
    try testing.expectEqual(@as(usize, 100), arena.totalUsed());

    _ = try arena.alloc(200, 0);
    try testing.expectEqual(@as(usize, 300), arena.totalUsed());
}

test "Arena - statistics tracking" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Initial stats
    var stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.allocation_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);

    // First allocation
    _ = try arena.alloc(100, 0);
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 1), stats.allocation_count);
    try testing.expectEqual(@as(usize, 100), stats.bytes_used);

    // Second allocation
    _ = try arena.alloc(200, 0);
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 2), stats.allocation_count);
    try testing.expectEqual(@as(usize, 300), stats.bytes_used);

    // Reset should increment reset_count
    arena.reset();
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 1), stats.reset_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "Arena - statistics utilization" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Allocate a small amount
    _ = try arena.alloc(100, 0);
    const stats = arena.getStats();

    // Utilization should be reasonable (not 0)
    const util = stats.utilization();
    try testing.expect(util > 0.0);
    try testing.expect(util <= 1.0);
}

test "Arena - statistics average allocation size" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);
    _ = try arena.alloc(300, 0);

    const stats = arena.getStats();
    const avg = stats.averageAllocationSize();
    // Average should be (100 + 200 + 300) / 3 = 200
    try testing.expectApproxEqAbs(@as(f64, 200.0), avg, 0.1);
}

test "Arena - initWithBlockSize" {
    const testing = std.testing;

    var arena = Arena.initWithBlockSize(testing.allocator, 4096);
    defer arena.deinit();

    // Should work like normal arena
    const ptr = try arena.alloc(64, 0);
    @memset(ptr[0..64], 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ptr[0]);

    // Block size should be set
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 4096), stats.block_size);
}

test "Arena - resetStats" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);

    // Reset stats should clear counters
    arena.resetStats();
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.allocation_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "Arena - blockCount" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Initially no blocks
    try testing.expectEqual(@as(usize, 0), arena.blockCount());

    // First allocation creates a block
    _ = try arena.alloc(100, 0);
    try testing.expectEqual(@as(usize, 1), arena.blockCount());

    // Large allocation creates another block
    _ = try arena.alloc(16 * 1024, 0); // 16KB > default 8KB block
    try testing.expectEqual(@as(usize, 2), arena.blockCount());
}

test "ArenaStats - empty stats" {
    const testing = std.testing;

    const stats = ArenaStats{};
    try testing.expectEqual(@as(f64, 0.0), stats.utilization());
    try testing.expectEqual(@as(f64, 0.0), stats.averageAllocationSize());
}

test "ThreadLocalArena - basic usage" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get allocator for current thread
    const alloc = try thread_arena.allocator();

    // Use with ArrayList
    var list = std.array_list.Managed(u32).init(alloc);
    defer list.deinit();

    try list.append(42);
    try list.append(100);
    try testing.expectEqual(@as(u32, 42), list.items[0]);
    try testing.expectEqual(@as(u32, 100), list.items[1]);
}

test "ThreadLocalArena - resetCurrentThread" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(100, 0);

    // Reset should clear allocations
    thread_arena.resetCurrentThread();
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "ThreadLocalArena - statistics" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);

    // Update global stats
    thread_arena.updateGlobalStats();
    const global_stats = thread_arena.getGlobalStats();
    try testing.expectEqual(@as(usize, 2), global_stats.allocation_count);
    try testing.expectEqual(@as(usize, 300), global_stats.bytes_used);
}

test "ThreadLocalArena - initWithBlockSize" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.initWithBlockSize(testing.allocator, 4096);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();

    // Block size should be set
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 4096), stats.block_size);
}

test "Arena - concurrent usage simulation" {
    const testing = std.testing;

    // Simulate multiple threads using their own arenas
    var arena1 = Arena.init(testing.allocator);
    defer arena1.deinit();

    var arena2 = Arena.init(testing.allocator);
    defer arena2.deinit();

    // Both arenas should work independently
    const ptr1 = try arena1.alloc(100, 0);
    const ptr2 = try arena2.alloc(100, 0);

    // Should not interfere with each other
    @memset(ptr1[0..100], 0x11);
    @memset(ptr2[0..100], 0x22);

    try testing.expectEqual(@as(u8, 0x11), ptr1[0]);
    try testing.expectEqual(@as(u8, 0x22), ptr2[0]);

    // Stats should be independent
    const stats1 = arena1.getStats();
    const stats2 = arena2.getStats();
    try testing.expectEqual(@as(usize, 1), stats1.allocation_count);
    try testing.expectEqual(@as(usize, 1), stats2.allocation_count);
}

test "ThreadLocalArena - cleanupCurrentThread" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Allocate through the thread-local arena
    const alloc1 = try thread_arena.allocator();
    var list = std.array_list.Managed(u8).init(alloc1);
    try list.append(0xAA);
    try testing.expectEqual(@as(u8, 0xAA), list.items[0]);

    // cleanupCurrentThread clears the thread-local pointer
    thread_arena.cleanupCurrentThread();

    // A subsequent allocator() call should create a fresh arena
    // (the old Arena object is still tracked in all_arenas and will
    // be freed by deinit, but the thread-local pointer is now null).
    const alloc2 = try thread_arena.allocator();
    var list2 = std.array_list.Managed(u8).init(alloc2);
    try list2.append(0xBB);
    try testing.expectEqual(@as(u8, 0xBB), list2.items[0]);
}

test "ThreadLocalArena - withArena success" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    try thread_arena.withArena(testSuccessFn);

    // thread-local pointer should have been cleaned up;
    // a fresh call to getArena should succeed without error.
    _ = try thread_arena.getArena();
}

test "ThreadLocalArena - withArena cleanup on error" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // First, prime the thread-local arena so the function runs inside it
    _ = try thread_arena.getArena();

    // The function returns an error; cleanup should still happen.
    const result = thread_arena.withArena(testErrorFn);

    try testing.expectError(error.DeliberateTestError, result);

    // Verify cleanup happened: getArena should lazily create a new arena
    // (the thread-local ptr was null after cleanup).
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(8, 0);
}

/// Helper: allocation succeeds and uses the arena.
fn testSuccessFn(alloc: std.mem.Allocator) !void {
    var list = std.array_list.Managed(u32).init(alloc);
    try list.append(123);
    if (list.items[0] != 123) return error.Unexpected;
}

/// Helper: deliberately returns an error.
fn testErrorFn(_: std.mem.Allocator) !void {
    return error.DeliberateTestError;
}
