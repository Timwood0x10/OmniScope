//! Value ID Mapping for LLVM Values
//!
//! This module provides a mapping from LLVM value pointers to unique 32-bit IDs.
//! This avoids collision issues from pointer truncation on 64-bit systems.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Value ID mapping for LLVM values.
/// Maps 64-bit pointer values to unique 32-bit IDs.
pub const ValueIdMap = struct {
    /// Map from pointer value to assigned ID
    ptr_to_id: std.AutoHashMap(usize, u32),
    /// Next ID to assign
    next_id: u32,

    /// Initialize a new ValueIdMap
    pub fn init(allocator: Allocator) ValueIdMap {
        return .{
            .ptr_to_id = std.AutoHashMap(usize, u32).init(allocator),
            .next_id = 0,
        };
    }

    /// Free resources
    pub fn deinit(self: *ValueIdMap) void {
        self.ptr_to_id.deinit();
    }

    /// Get or create an ID for a value.
    /// Returns the ID (existing or newly created).
    ///
    /// Parameters:
    ///   - ptr: Pointer value to map. Must be non-zero.
    ///
    /// Returns:
    ///   - Unique 32-bit ID for the pointer
    ///
    /// Errors:
    ///   - error.NullPointer: If ptr is 0
    ///   - error.Overflow: If ID counter would overflow
    ///
    /// Note: Callers should check ptr != 0 before calling to avoid errors.
    pub fn getOrPutId(self: *ValueIdMap, ptr: usize) !u32 {
        if (ptr == 0) return error.NullPointer;

        const entry = try self.ptr_to_id.getOrPut(ptr);
        if (entry.found_existing) {
            return entry.value_ptr.*;
        }

        // Check for overflow before incrementing
        if (self.next_id == std.math.maxInt(u32)) {
            return error.Overflow;
        }

        const id = self.next_id;
        self.next_id += 1;
        entry.value_ptr.* = id;
        return id;
    }

    /// Get existing ID for a pointer, or null if not tracked.
    pub fn getId(self: *const ValueIdMap, ptr: usize) ?u32 {
        if (ptr == 0) return null;
        return self.ptr_to_id.get(ptr);
    }

    /// Check if a pointer is tracked
    pub fn contains(self: *const ValueIdMap, ptr: usize) bool {
        return self.ptr_to_id.contains(ptr);
    }

    /// Get the number of tracked values
    pub fn count(self: *const ValueIdMap) usize {
        return self.ptr_to_id.count();
    }

    /// Clear all mappings
    pub fn clear(self: *ValueIdMap) void {
        self.ptr_to_id.clearRetainingCapacity();
        self.next_id = 0;
    }
};

// Unit tests

test "ValueIdMap - init and deinit" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();
    try std.testing.expectEqual(@as(usize, 0), map.count());
}

test "ValueIdMap - getOrPutId" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    const id1 = try map.getOrPutId(0x1000);
    const id2 = try map.getOrPutId(0x2000);
    const id3 = try map.getOrPutId(0x1000); // Same pointer

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 0), id3); // Returns same ID
    try std.testing.expectEqual(@as(usize, 2), map.count());
}

test "ValueIdMap - getId" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    _ = try map.getOrPutId(0x1000);

    try std.testing.expectEqual(@as(u32, 0), map.getId(0x1000).?);
    try std.testing.expect(map.getId(0x2000) == null);
    try std.testing.expect(map.getId(0) == null);
}

test "ValueIdMap - null pointer error" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    const result = map.getOrPutId(0);
    try std.testing.expectError(error.NullPointer, result);
}

test "ValueIdMap - contains" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    _ = try map.getOrPutId(0x1000);

    try std.testing.expect(map.contains(0x1000));
    try std.testing.expect(!map.contains(0x2000));
}

test "ValueIdMap - clear" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    _ = try map.getOrPutId(0x1000);
    _ = try map.getOrPutId(0x2000);

    try std.testing.expectEqual(@as(usize, 2), map.count());

    map.clear();

    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expectEqual(@as(u32, 0), map.next_id);
}

test "ValueIdMap - large number of values" {
    var map = ValueIdMap.init(std.testing.allocator);
    defer map.deinit();

    var i: usize = 1;
    while (i <= 1000) : (i += 1) {
        _ = try map.getOrPutId(i * 0x1000);
    }

    try std.testing.expectEqual(@as(usize, 1000), map.count());
    try std.testing.expectEqual(@as(u32, 1000), map.next_id);
}
