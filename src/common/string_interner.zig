//! String Interner — Deduplicate []const u8 slices for memory efficiency
//!
//! This module provides a string interning facility that eliminates duplicate
//! string allocations across the analysis pipeline. When the same function name
//! or path appears in call_graph, ptr_lifetime, and memory_graph, only one copy
//! is stored and all references point to the canonical instance.
//!
//! Key design decisions:
//! - HashMap-backed: O(1) lookup by pre-computed Wyhash key
//! - Ownership: interner owns all interned strings; freed on deinit
//! - Semantic safety: interned strings are byte-identical to originals
//! - Nullable integration: PassContext.interner is optional (?StringInterner)
//!
//! Usage:
//!   var interner = StringInterner.init(allocator);
//!   defer interner.deinit();
//!   const name = try interner.intern("malloc");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("log.zig");

/// Hash context for u64 keys where the key IS the hash value.
/// Since we pre-compute Wyhash, equality is direct u64 comparison.
const U64KeyContext = struct {
    pub fn hash(self: @This(), key: u64) u64 {
        _ = self;
        return key;
    }

    pub fn eql(self: @This(), a: u64, b: u64) bool {
        _ = self;
        return a == b;
    }
};

/// String interner for deduplicating []const u8 slices.
///
/// Stores a single canonical copy of each unique string. Subsequent calls
/// with identical content return the existing pointer instead of allocating
/// a new copy. This reduces memory usage and improves cache locality for
/// repeated strings like function names and file paths.
pub const StringInterner = struct {
    /// Hash map: pre-computed wyhash → canonical string slice (owned by allocator)
    map: std.HashMap(u64, []const u8, U64KeyContext, std.hash_map.default_max_load_percentage),
    /// Allocator used for string storage
    allocator: Allocator,
    /// Total bytes input across all intern() calls (for savings calculation)
    total_input_bytes: usize,

    /// Initialize a new string interner with the given allocator.
    ///
    /// Arguments:
    ///   allocator - Memory allocator for internal storage
    ///
    /// Returns:
    ///   Ready-to-use StringInterner (empty state)
    pub fn init(allocator: Allocator) StringInterner {
        return .{
            .map = std.HashMap(u64, []const u8, U64KeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .total_input_bytes = 0,
        };
    }

    /// Release all interned strings and internal storage.
    ///
    /// Must be called when the interner is no longer needed.
    /// Invalidates all previously returned slices.
    pub fn deinit(self: *StringInterner) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    /// Return the canonical copy of a string.
    ///
    /// If this is the first time seeing this content, allocates and stores
    /// a copy. Otherwise returns the existing canonical slice.
    ///
    /// Arguments:
    ///   s - Input string slice to intern
    ///
    /// Returns:
    ///   Canonical slice owned by the interner (valid until deinit)
    ///
    /// Errors:
    ///   OutOfMemory if allocation fails
    pub fn intern(self: *StringInterner, s: []const u8) ![]const u8 {
        self.total_input_bytes += s.len;

        const key = hashKey(s);

        const gop = try self.map.getOrPut(key);
        if (gop.found_existing) {
            return gop.value_ptr.*;
        }

        const copy = try self.allocator.dupe(u8, s);
        gop.value_ptr.* = copy;
        return copy;
    }

    /// Number of unique strings currently stored.
    pub fn size(self: *const StringInterner) usize {
        return self.map.count();
    }

    /// Estimated bytes saved through deduplication.
    ///
    /// Calculates: total_input - unique_stored_bytes.
    /// This is an upper-bound estimate since we don't track per-string counts.
    pub fn bytesSaved(self: *const StringInterner) usize {
        if (self.size() == 0) return 0;

        var total_stored: usize = 0;
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            total_stored += entry.value_ptr.*.len;
        }

        return self.total_input_bytes -% total_stored;
    }

    /// Compute Wyhash of a string slice for use as map key.
    ///
    /// Uses std.hash.Wyhash which provides good distribution and speed.
    fn hashKey(s: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(s);
        return hasher.final();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "string interner - same content returns same pointer" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    const a = try interner.intern("malloc");
    const b = try interner.intern("malloc");

    try testing.expectEqual(@as(usize, a.len), b.len);
    try testing.expect(std.mem.eql(u8, a, b));
    try testing.expect(a.ptr == b.ptr);
}

test "string interner - different content returns different pointers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    const a = try interner.intern("malloc");
    const b = try interner.intern("free");

    try testing.expect(!std.mem.eql(u8, a, b));
    try testing.expect(a.ptr != b.ptr);
}

test "string interner - size tracking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    _ = try interner.intern("a");
    _ = try interner.intern("b");
    _ = try interner.intern("c");

    try testing.expectEqual(@as(usize, 3), interner.size());
}

test "string interner - deduplication increases savings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    _ = try interner.intern("same_string");
    _ = try interner.intern("same_string");
    _ = try interner.intern("same_string");

    try testing.expectEqual(@as(usize, 1), interner.size());
    try testing.expect(interner.bytesSaved() > 0);
}

test "string interner - empty string handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    const empty = try interner.intern("");
    try testing.expectEqual(@as(usize, 0), empty.len);
    try testing.expectEqual(@as(usize, 1), interner.size());
}
