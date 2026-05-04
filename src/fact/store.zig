//! Fact store with SoA (Structure of Arrays) layout
//!
//! This module implements the fact store using SoA for cache-friendliness
//! and append-only design for parallel access.

const std = @import("std");
const Fact = @import("fact.zig").Fact;
const FactKind = @import("fact.zig").FactKind;

/// Fact store with SoA layout
///
/// Principle: Structure of Arrays for cache-friendliness and append-only for parallelism
pub const FactStore = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    kinds: std.ArrayList(FactKind),
    subj: std.ArrayList(u32),
    obj: std.ArrayList(u32),
    ctx: std.ArrayList(u32),

    /// Create a new fact store
    ///
    /// Note: initCapacity with non-zero capacity uses catch unreachable because
    /// allocation failure here is considered fatal (process cannot continue without
    /// its fact store). This is a design decision - we panic rather than handle
    /// OOM during initialization since the fact store is core infrastructure.
    pub fn init(allocator: std.mem.Allocator) !FactStore {
        return .{
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .kinds = try std.ArrayList(FactKind).initCapacity(allocator, 1024),
            .subj = try std.ArrayList(u32).initCapacity(allocator, 1024),
            .obj = try std.ArrayList(u32).initCapacity(allocator, 1024),
            .ctx = try std.ArrayList(u32).initCapacity(allocator, 1024),
        };
    }

    /// Deinitialize the fact store
    pub fn deinit(self: *FactStore) void {
        self.kinds.deinit(self.allocator);
        self.subj.deinit(self.allocator);
        self.obj.deinit(self.allocator);
        self.ctx.deinit(self.allocator);
    }

    /// Insert a fact into the store (append-only)
    ///
    /// Parameters:
    ///   - kind: The fact kind
    ///   - subject: Subject ID
    ///   - object: Object ID
    ///   - context: Context ID
    pub fn insert(
        self: *FactStore,
        kind: FactKind,
        subject: u32,
        object: u32,
        context: u32,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const orig_len = self.kinds.items.len;
        errdefer {
            self.kinds.shrinkRetainingCapacity(orig_len);
            self.subj.shrinkRetainingCapacity(orig_len);
            self.obj.shrinkRetainingCapacity(orig_len);
            self.ctx.shrinkRetainingCapacity(orig_len);
        }

        try self.kinds.append(self.allocator, kind);
        try self.subj.append(self.allocator, subject);
        try self.obj.append(self.allocator, object);
        try self.ctx.append(self.allocator, context);
    }

    /// Get the number of facts in the store
    pub fn count(self: *FactStore) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.kinds.items.len;
    }

    /// Get the number of facts in the store (caller must hold mutex)
    pub fn countLocked(self: *FactStore) usize {
        return self.kinds.items.len;
    }

    /// Return a snapshot (copy) of all facts as an allocated slice.
    /// Caller must free with allocator.free().
    pub fn snapshot(self: *FactStore, allocator: std.mem.Allocator) ![]Fact {
        self.mutex.lock();
        defer self.mutex.unlock();
        const n = self.kinds.items.len;
        if (n == 0) return &.{};
        var result = try allocator.alloc(Fact, n);
        errdefer allocator.free(result);
        for (self.kinds.items, 0..) |kind, i| {
            result[i] = Fact.init(kind, self.subj.items[i], self.obj.items[i], self.ctx.items[i]);
        }
        return result;
    }

    /// Get a fact by index
    pub fn get(self: *FactStore, index: usize) ?Fact {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index >= self.kinds.items.len) return null;
        return Fact.init(
            self.kinds.items[index],
            self.subj.items[index],
            self.obj.items[index],
            self.ctx.items[index],
        );
    }

    /// Query facts by kind
    ///
    /// Returns a slice of indices matching the given kind
    pub fn queryByKind(self: *FactStore, kind: FactKind, allocator: std.mem.Allocator) ![]usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        var indices = try std.ArrayList(usize).initCapacity(allocator, 128);
        for (self.kinds.items, 0..) |k, i| {
            if (k == kind) {
                try indices.append(allocator, i);
            }
        }
        return indices.toOwnedSlice(allocator);
    }
};

test "FactStore - init and deinit" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "FactStore - insert" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.cfg_edge, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 0), fact.context);
}

test "FactStore - queryByKind" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);
    try store.insert(.cfg_edge, 5, 6, 0);

    const indices = try store.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(indices);

    try std.testing.expectEqual(@as(usize, 2), indices.len);
    try std.testing.expectEqual(@as(usize, 0), indices[0]);
    try std.testing.expectEqual(@as(usize, 2), indices[1]);
}

test "FactStore - get out of bounds" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    const fact = store.get(0);
    try std.testing.expect(fact == null);
}

test "FactStore - large scale insert and retrieve" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    const count = 10000;

    // Insert many facts
    for (0..count) |i| {
        const kind: FactKind = switch (i % 3) {
            0 => .cfg_edge,
            1 => .dfg_edge,
            2 => .alias_may,
            else => unreachable,
        };
        try store.insert(kind, @intCast(i), @intCast(i + 1), @intCast(i / 100));
    }

    try std.testing.expectEqual(@as(usize, count), store.count());

    // Verify all facts can be retrieved correctly
    for (0..count) |i| {
        const fact = store.get(i).?;
        try std.testing.expectEqual(@as(u32, @intCast(i)), fact.subject);
        try std.testing.expectEqual(@as(u32, @intCast(i + 1)), fact.object);
        try std.testing.expectEqual(@as(u32, @intCast(i / 100)), fact.context);
    }
}

test "FactStore - queryByKind with mixed kinds" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Insert facts of all kinds
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);
    try store.insert(.alias_may, 5, 6, 0);
    try store.insert(.alias_must, 7, 8, 0);
    try store.insert(.lock_acquire, 9, 10, 0);
    try store.insert(.lock_release, 11, 12, 0);
    try store.insert(.taint, 13, 14, 0);
    try store.insert(.allocation, 15, 16, 0);

    // Query each kind
    const kinds = [_]FactKind{
        .cfg_edge,     .dfg_edge,     .alias_may, .alias_must,
        .lock_acquire, .lock_release, .taint,     .allocation,
    };

    inline for (kinds, 0..) |kind, expected_idx| {
        const indices = try store.queryByKind(kind, std.testing.allocator);
        defer std.testing.allocator.free(indices);

        try std.testing.expectEqual(@as(usize, 1), indices.len);
        const fact = store.get(indices[0]).?;
        try std.testing.expectEqual(kind, fact.kind);
        try std.testing.expectEqual(@as(u32, @intCast(expected_idx * 2 + 1)), fact.subject);
    }
}

test "FactStore - append-only property" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Insert facts
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);

    const first_fact = store.get(0).?;
    const second_fact = store.get(1).?;

    // Store should maintain order
    try std.testing.expectEqual(FactKind.cfg_edge, first_fact.kind);
    try std.testing.expectEqual(FactKind.dfg_edge, second_fact.kind);

    // Insert more facts
    try store.insert(.cfg_edge, 5, 6, 0);

    // Previous facts should not be modified
    const first_fact_again = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), first_fact_again.subject);
    try std.testing.expectEqual(@as(u32, 2), first_fact_again.object);
}

test "FactStore - boundary values" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Test with maximum u32 values
    try store.insert(.cfg_edge, 0, 0, 0);
    try store.insert(.cfg_edge, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF);

    const first = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 0), first.subject);
    try std.testing.expectEqual(@as(u32, 0), first.object);
    try std.testing.expectEqual(@as(u32, 0), first.context);

    const second = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), second.subject);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), second.object);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), second.context);
}

test "FactStore - zero values" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Insert fact with all zero values
    try store.insert(.cfg_edge, 0, 0, 0);

    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.cfg_edge, fact.kind);
    try std.testing.expectEqual(@as(u32, 0), fact.subject);
    try std.testing.expectEqual(@as(u32, 0), fact.object);
    try std.testing.expectEqual(@as(u32, 0), fact.context);
}

test "FactStore - mixed operations" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Insert facts of different kinds
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);
    try store.insert(.cfg_edge, 5, 6, 0);

    // Query by kind
    const cfg_facts = try store.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(cfg_facts);
    try std.testing.expectEqual(@as(usize, 2), cfg_facts.len);

    const dfg_facts = try store.queryByKind(.dfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(dfg_facts);
    try std.testing.expectEqual(@as(usize, 1), dfg_facts.len);

    // Query non-existent kind
    const taint_facts = try store.queryByKind(.taint, std.testing.allocator);
    defer std.testing.allocator.free(taint_facts);
    try std.testing.expectEqual(@as(usize, 0), taint_facts.len);
}

test "FactStore - all fact kinds" {
    var store = try FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Test all fact kinds are valid
    const all_kinds = [_]FactKind{
        .cfg_edge,
        .dfg_edge,
        .alias_may,
        .alias_must,
        .lock_acquire,
        .lock_release,
        .taint,
        .allocation,
    };

    inline for (all_kinds, 0..) |kind, i| {
        try store.insert(kind, @intCast(i), @intCast(i + 1), @intCast(i + 2));
    }

    try std.testing.expectEqual(@as(usize, all_kinds.len), store.count());

    // Verify each kind was stored correctly
    inline for (all_kinds, 0..) |kind, i| {
        const fact = store.get(i).?;
        try std.testing.expectEqual(kind, fact.kind);
        try std.testing.expectEqual(@as(u32, @intCast(i)), fact.subject);
        try std.testing.expectEqual(@as(u32, @intCast(i + 1)), fact.object);
        try std.testing.expectEqual(@as(u32, @intCast(i + 2)), fact.context);
    }
}
