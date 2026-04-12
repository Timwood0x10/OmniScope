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
        var facts = std.ArrayList(Fact).initCapacity(allocator, 0) catch unreachable;
        for (0..self.store.count()) |i| {
            if (self.store.kinds.items[i] == kind) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(allocator, fact);
            }
        }
        return facts.toOwnedSlice(allocator);
    }

    /// Query facts by subject
    ///
    /// Returns all facts with the given subject ID
    pub fn queryBySubject(
        self: *QueryEngine,
        subject: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).initCapacity(allocator, 0) catch unreachable;
        for (0..self.store.count()) |i| {
            if (self.store.subj.items[i] == subject) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(allocator, fact);
            }
        }
        return facts.toOwnedSlice(allocator);
    }

    /// Query facts by object
    ///
    /// Returns all facts with the given object ID
    pub fn queryByObject(
        self: *QueryEngine,
        object: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).initCapacity(allocator, 0) catch unreachable;
        for (0..self.store.count()) |i| {
            if (self.store.obj.items[i] == object) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(allocator, fact);
            }
        }
        return facts.toOwnedSlice(allocator);
    }

    /// Query facts by context
    ///
    /// Returns all facts with the given context ID
    pub fn queryByContext(
        self: *QueryEngine,
        context: u32,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var facts = std.ArrayList(Fact).initCapacity(allocator, 0) catch unreachable;
        for (0..self.store.count()) |i| {
            if (self.store.ctx.items[i] == context) {
                const fact = Fact.init(
                    self.store.kinds.items[i],
                    self.store.subj.items[i],
                    self.store.obj.items[i],
                    self.store.ctx.items[i],
                );
                try facts.append(allocator, fact);
            }
        }
        return facts.toOwnedSlice(allocator);
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

test "QueryEngine - queryByObject" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 2, 0);
    try store.insert(.cfg_edge, 5, 6, 0);

    var engine = QueryEngine.init(&store);
    const facts = try engine.queryByObject(2, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
}

test "QueryEngine - queryByContext" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.dfg_edge, 3, 4, 0);
    try store.insert(.cfg_edge, 5, 6, 1);

    var engine = QueryEngine.init(&store);
    const facts = try engine.queryByContext(0, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
}

test "QueryEngine - complex query scenario" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Build a small fact graph:
    // Function 0 (context 0):
    //   - cfg_edge: 1 -> 2
    //   - cfg_edge: 2 -> 3
    //   - dfg_edge: 1 -> 3
    // Function 1 (context 1):
    //   - cfg_edge: 4 -> 5
    //   - dfg_edge: 4 -> 6

    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.cfg_edge, 2, 3, 0);
    try store.insert(.dfg_edge, 1, 3, 0);
    try store.insert(.cfg_edge, 4, 5, 1);
    try store.insert(.dfg_edge, 4, 6, 1);

    var engine = QueryEngine.init(&store);

    // Query all facts in context 0
    const ctx0_facts = try engine.queryByContext(0, std.testing.allocator);
    defer std.testing.allocator.free(ctx0_facts);
    try std.testing.expectEqual(@as(usize, 3), ctx0_facts.len);

    // Query all facts where subject is 2
    const subj2_facts = try engine.queryBySubject(2, std.testing.allocator);
    defer std.testing.allocator.free(subj2_facts);
    try std.testing.expectEqual(@as(usize, 1), subj2_facts.len);
    try std.testing.expectEqual(FactKind.cfg_edge, subj2_facts[0].kind);
    try std.testing.expectEqual(@as(u32, 3), subj2_facts[0].object);

    // Query all cfg_edge facts
    const cfg_facts = try engine.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(cfg_facts);
    try std.testing.expectEqual(@as(usize, 3), cfg_facts.len);
}

test "QueryEngine - empty query results" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);

    var engine = QueryEngine.init(&store);

    // Query for non-existent data
    const empty_kind = try engine.queryByKind(.taint, std.testing.allocator);
    defer std.testing.allocator.free(empty_kind);
    try std.testing.expectEqual(@as(usize, 0), empty_kind.len);

    const empty_subject = try engine.queryBySubject(999, std.testing.allocator);
    defer std.testing.allocator.free(empty_subject);
    try std.testing.expectEqual(@as(usize, 0), empty_subject.len);

    const empty_object = try engine.queryByObject(999, std.testing.allocator);
    defer std.testing.allocator.free(empty_object);
    try std.testing.expectEqual(@as(usize, 0), empty_object.len);

    const empty_context = try engine.queryByContext(999, std.testing.allocator);
    defer std.testing.allocator.free(empty_context);
    try std.testing.expectEqual(@as(usize, 0), empty_context.len);
}

test "QueryEngine - query on large dataset" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const count = 1000;

    // Insert facts with a pattern
    for (0..count) |i| {
        const kind: FactKind = if (i % 2 == 0) .cfg_edge else .dfg_edge;
        const context: u32 = @intCast(i / 100);
        try store.insert(kind, @intCast(i), @intCast(i + 1), context);
    }

    var engine = QueryEngine.init(&store);

    // Query all cfg_edge facts
    const cfg_facts = try engine.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(cfg_facts);
    try std.testing.expectEqual(@as(usize, count / 2), cfg_facts.len);

    // Query facts in a specific context
    const ctx_facts = try engine.queryByContext(5, std.testing.allocator);
    defer std.testing.allocator.free(ctx_facts);
    try std.testing.expectEqual(@as(usize, 100), ctx_facts.len);

    // Verify all facts in context 5 have correct context
    for (ctx_facts) |fact| {
        try std.testing.expectEqual(@as(u32, 5), fact.context);
    }
}
