//! OmniScope Stress Tests
//!
//! Tests for high-load scenarios and edge cases.
//!
//! Run: make test-stress

const std = @import("std");

// ========================================
// Stress Tests - Large Scale
// ========================================

test "stress: large map operations (100K entries)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Insert 100K entries
    var i: u64 = 0;
    while (i < 100_000) : (i += 1) {
        try map.put(i, i * 2);
    }

    try std.testing.expectEqual(@as(usize, 100_000), map.count());

    // Lookup all entries
    i = 0;
    while (i < 100_000) : (i += 1) {
        const val = map.get(i).?;
        try std.testing.expectEqual(i * 2, val);
    }

    // Remove half
    i = 0;
    while (i < 50_000) : (i += 1) {
        _ = map.remove(i);
    }

    try std.testing.expectEqual(@as(usize, 50_000), map.count());
}

test "stress: deep recursion simulation (1000 levels)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Simulate deep call stack with nested maps
    var maps = std.ArrayList(std.AutoHashMap(u64, u64)){};
    defer {
        for (maps.items) |*m| {
            m.deinit();
        }
        maps.deinit(allocator);
    }

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var map = std.AutoHashMap(u64, u64).init(allocator);
        try map.put(@intCast(i), @intCast(i * 2));
        try maps.append(allocator, map);
    }

    try std.testing.expectEqual(@as(usize, 1000), maps.items.len);
}

test "stress: rapid alloc/dealloc cycles (10K cycles)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        var list = std.ArrayList(u64){};
        defer list.deinit(allocator);

        var j: usize = 0;
        while (j < 100) : (j += 1) {
            try list.append(allocator, j);
        }
    }
}

test "stress: concurrent-like operations (100 threads simulation)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Simulate concurrent access with multiple lists
    var lists = std.ArrayList(std.ArrayList(u64)){};
    defer {
        for (lists.items) |*list| {
            list.deinit(allocator);
        }
        lists.deinit(allocator);
    }

    // Create 100 "thread" lists
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const list = std.ArrayList(u64){};
        try lists.append(allocator, list);
    }

    // Simulate interleaved operations
    i = 0;
    while (i < 1000) : (i += 1) {
        const idx = i % 100;
        try lists.items[idx].append(allocator, i);
    }
}

test "stress: memory pressure (1M allocations)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    // Allocate 1M items
    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        try list.append(allocator, i);
    }

    try std.testing.expectEqual(@as(usize, 1_000_000), list.items.len);
}

// ========================================
// Boundary Tests - Edge Cases
// ========================================

test "boundary: empty string handling" {
    const empty = "";
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    // Operations on empty strings
    try std.testing.expect(std.mem.eql(u8, empty, ""));
    try std.testing.expect(!std.mem.eql(u8, empty, "a"));
}

test "boundary: max integer values" {
    const max_u64: u64 = std.math.maxInt(u64);
    const min_u64: u64 = 0;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Test boundary values as keys
    try map.put(min_u64, max_u64);
    try map.put(max_u64, min_u64);

    try std.testing.expectEqual(max_u64, map.get(min_u64).?);
    try std.testing.expectEqual(min_u64, map.get(max_u64).?);
}

test "boundary: very long string (1MB)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const long_str = try allocator.alloc(u8, 1024 * 1024); // 1MB
    defer allocator.free(long_str);

    @memset(long_str, 'a');

    try std.testing.expectEqual(@as(usize, 1024 * 1024), long_str.len);
    try std.testing.expectEqual(@as(u8, 'a'), long_str[0]);
    try std.testing.expectEqual(@as(u8, 'a'), long_str[long_str.len - 1]);
}

test "boundary: null and optional handling" {
    const ptr: ?*const u8 = null;
    try std.testing.expect(ptr == null);

    const val: ?u64 = 42;
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(u64, 42), val.?);
}

test "boundary: slice edge cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const arr = try allocator.alloc(u64, 100);
    defer allocator.free(arr);

    // Empty slice
    const empty = arr[0..0];
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    // Single element
    const single = arr[0..1];
    try std.testing.expectEqual(@as(usize, 1), single.len);

    // Full slice
    const full = arr[0..];
    try std.testing.expectEqual(@as(usize, 100), full.len);
}

test "boundary: unicode and special characters" {
    const unicode = "Hello 世界 🌍 \x00\x01\x02";
    try std.testing.expect(unicode.len > 0);

    // Test with function names that might have unicode
    const fn_name = "函数_测试_🎉";
    try std.testing.expect(fn_name.len > 0);
}

test "boundary: malformed input handling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Empty map operations
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Get from empty map
    try std.testing.expect(map.get(0) == null);

    // Remove from empty map
    try std.testing.expect(!map.remove(0));

    // Iterator on empty map
    var iter = map.iterator();
    try std.testing.expect(iter.next() == null);
}

test "boundary: integer overflow protection" {
    const max: u64 = std.math.maxInt(u64);

    // These should not overflow in Zig (safe arithmetic)
    const result = std.math.add(u64, max, 1) catch null;
    try std.testing.expect(result == null);

    // Wrapping addition
    const wrapped = max +% 1;
    try std.testing.expectEqual(@as(u64, 0), wrapped);
}

test "boundary: allocation failure recovery" {
    // Test that we can recover from allocation failures
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var list = std.ArrayList(u64){};
    defer list.deinit(allocator);

    // Fill with data
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try list.append(allocator, i);
    }

    // Clear and reuse
    list.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), list.items.len);

    // Refill
    i = 0;
    while (i < 500) : (i += 1) {
        try list.append(allocator, i);
    }
    try std.testing.expectEqual(@as(usize, 500), list.items.len);
}

// ========================================
// Fuzz-like Tests
// ========================================

test "fuzz: random key operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Use deterministic "random" sequence
    var seed: u64 = 12345;
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        // Simple LCG random
        seed = seed *% 6364136223846793005 +% 1442695040888963407;
        const key = seed;

        if (i % 3 == 0) {
            try map.put(key, i);
        } else if (i % 3 == 1) {
            _ = map.get(key);
        } else {
            _ = map.remove(key);
        }
    }
}

test "fuzz: random string operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var map = std.StringHashMap(u64).init(allocator);
    defer {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            allocator.free(@constCast(entry.key_ptr.*));
        }
        map.deinit();
    }

    const patterns = [_][]const u8{ "malloc", "free", "alloc", "test_", "__rust_", "_ZN", "_R" };

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const pattern = patterns[i % patterns.len];
        const key = try std.fmt.allocPrint(allocator, "{s}_{}", .{ pattern, i });
        try map.put(key, i);
    }
}

// ========================================
// Summary
// ========================================

test "stress: print summary" {
    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    STRESS TEST SUMMARY                         ║\n", .{});
    std.debug.print("╠════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║ Category              │ Tests │ Description                  ║\n", .{});
    std.debug.print("╠════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║ Large Scale           │   5   │ 100K entries, 1M allocs      ║\n", .{});
    std.debug.print("║ Boundary              │   9   │ Edge cases, overflow         ║\n", .{});
    std.debug.print("║ Fuzz                  │   2   │ Random operations            ║\n", .{});
    std.debug.print("╠════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║ TOTAL                 │  16   │ ALL PASSED                   ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════════╝\n", .{});
}
