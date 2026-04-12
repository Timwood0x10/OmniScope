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
    kinds: std.ArrayList(FactKind),
    subj: std.ArrayList(u32),
    obj: std.ArrayList(u32),
    ctx: std.ArrayList(u32),

    /// Create a new fact store
    pub fn init(allocator: std.mem.Allocator) FactStore {
        return .{
            .allocator = allocator,
            .kinds = std.ArrayList(FactKind).init(allocator),
            .subj = std.ArrayList(u32).init(allocator),
            .obj = std.ArrayList(u32).init(allocator),
            .ctx = std.ArrayList(u32).init(allocator),
        };
    }

    /// Deinitialize the fact store
    pub fn deinit(self: *FactStore) void {
        self.kinds.deinit();
        self.subj.deinit();
        self.obj.deinit();
        self.ctx.deinit();
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
        try self.kinds.append(kind);
        try self.subj.append(subject);
        try self.obj.append(object);
        try self.ctx.append(context);
    }

    /// Get the number of facts in the store
    pub fn count(self: *const FactStore) usize {
        return self.kinds.items.len;
    }

    /// Get a fact by index
    pub fn get(self: *const FactStore, index: usize) ?Fact {
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
    pub fn queryByKind(self: *const FactStore, kind: FactKind, allocator: std.mem.Allocator) ![]usize {
        var indices = std.ArrayList(usize).init(allocator);
        for (self.kinds.items, 0..) |k, i| {
            if (k == kind) {
                try indices.append(i);
            }
        }
        return indices.toOwnedSlice();
    }
};

test "FactStore - init and deinit" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "FactStore - insert" {
    var store = FactStore.init(std.testing.allocator);
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
    var store = FactStore.init(std.testing.allocator);
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
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const fact = store.get(0);
    try std.testing.expect(fact == null);
}
