//! Query engine for fact store
//!
//! This module provides query capabilities for the fact store,
//! allowing passes to query facts efficiently.

const std = @import("std");
const FactStore = @import("store.zig").FactStore;
const Fact = @import("fact.zig").Fact;
const FactKind = @import("fact.zig").FactKind;

/// Query engine for fact store
pub const QueryEngine = struct {
    store: *FactStore,

    /// Create a new query engine
    pub fn init(store: *FactStore) QueryEngine {
        return .{ .store = store };
    }

    /// Query facts by kind
    ///
    /// Returns all facts matching the given kind
    pub fn queryByKind(
        self: *QueryEngine,
        kind: FactKind,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).init(allocator);
        for (0..self.store.count()) |i| {
            if (self.store.kinds.items[i] == kind) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(fact);
            }
        }
        return facts.toOwnedSlice();
    }

    /// Query facts by subject
    ///
    /// Returns all facts with the given subject ID
    pub fn queryBySubject(
        self: *QueryEngine,
        subject: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).init(allocator);
        for (0..self.store.count()) |i| {
            if (self.store.subj.items[i] == subject) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(fact);
            }
        }
        return facts.toOwnedSlice();
    }

    /// Query facts by object
    ///
    /// Returns all facts with the given object ID
    pub fn queryByObject(
        self: *QueryEngine,
        object: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).init(allocator);
        for (0..self.store.count()) |i| {
            if (self.store.obj.items[i] == object) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(fact);
            }
        }
        return facts.toOwnedSlice();
    }

    /// Query facts by context
    ///
    /// Returns all facts with the given context ID
    pub fn queryByContext(
        self: *QueryEngine,
        context: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).init(allocator);
        for (0..self.store.count()) |i| {
            if (self.store.ctx.items[i] == context) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(fact);
            }
        }
        return facts.toOwnedSlice();
    }
};

test "QueryEngine - queryByKind" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);
    try store.insert(.cfg_edge, 5, 6, 0);

    var engine = QueryEngine.init(&store);
    const facts = try engine.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
}

test "QueryEngine - queryBySubject" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 1, 4, 0);
    try store.insert(.cfg_edge, 5, 6, 0);

    var engine = QueryEngine.init(&store);
    const facts = try engine.queryBySubject(1, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
}
