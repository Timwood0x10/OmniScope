//! Merge Engine
//!
//! This module merges static analysis facts with runtime events
//! to produce enhanced diagnostics with confidence scores.

const std = @import("std");
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DecodedEvent = @import("collector.zig").DecodedEvent;

/// Merge engine
pub const MergeEngine = struct {
    allocator: std.mem.Allocator,
    fact_store: *FactStore,
    query_engine: QueryEngine,

    /// Create a new merge engine
    pub fn init(allocator: std.mem.Allocator, fact_store: *FactStore) MergeEngine {
        return .{
            .allocator = allocator,
            .fact_store = fact_store,
            .query_engine = QueryEngine.init(fact_store),
        };
    }

    /// Merge runtime events with static facts
    pub fn merge(
        self: *MergeEngine,
        events: []DecodedEvent,
    ) ![]MergedEvent {
        var merged = std.ArrayList(MergedEvent).init(self.allocator);

        for (events) |ev| {
            const merged_ev = try self.mergeEvent(ev);
            try merged.append(merged_ev);
        }

        return merged.toOwnedSlice();
    }

    /// Merge a single event with static facts
    fn mergeEvent(
        self: *MergeEngine,
        ev: DecodedEvent,
    ) !MergedEvent {
        // Find related static facts
        const confidence = try self.calculateConfidence(ev);

        return .{
            .tag = ev.tag,
            .tid = ev.tid,
            .loc = ev.loc,
            .arg = ev.arg,
            .timestamp = ev.timestamp,
            .confidence = confidence,
        };
    }

    /// Calculate confidence score based on static facts
    fn calculateConfidence(
        self: *MergeEngine,
        ev: DecodedEvent,
    ) !f32 {
        // Base confidence: 0.5 (no static information)
        var confidence: f32 = 0.5;

        // Check if location has static facts
        const location_facts = try self.query_engine.queryByObject(ev.loc, self.allocator);
        defer self.allocator.free(location_facts);

        if (location_facts.len > 0) {
            // Location has static facts, increase confidence
            confidence += 0.3;
        }

        // Check if this is a potential hotspot (from static analysis)
        // In a real implementation, this would check for specific patterns
        // like alias_may in loops, lock operations, etc.

        // Clamp confidence to [0.0, 1.0]
        if (confidence > 1.0) confidence = 1.0;
        if (confidence < 0.0) confidence = 0.0;

        return confidence;
    }

    /// Detect anomalies by comparing static and runtime behavior
    pub fn detectAnomalies(
        self: *MergeEngine,
        events: []DecodedEvent,
    ) ![]Anomaly {
        var anomalies = std.ArrayList(Anomaly).init(self.allocator);

        // Implementation steps:
        // 1. Group events by location
        // 2. Compare with static facts
        // 3. Detect inconsistencies
        // 4. Report anomalies

        return anomalies.toOwnedSlice();
    }
};

/// Merged event with confidence score
pub const MergedEvent = struct {
    /// Event tag
    tag: u8,
    /// Thread ID
    tid: u16,
    /// Location ID
    loc: u32,
    /// Argument value
    arg: u64,
    /// Timestamp (nanoseconds)
    timestamp: i128,
    /// Confidence score [0.0, 1.0]
    confidence: f32,

    /// Check if confidence is high
    pub fn isHighConfidence(self: MergedEvent) bool {
        return self.confidence >= 0.8;
    }

    /// Check if confidence is low
    pub fn isLowConfidence(self: MergedEvent) bool {
        return self.confidence < 0.5;
    }
};

/// Anomaly detected by merge engine
pub const Anomaly = struct {
    /// Anomaly type
    kind: AnomalyKind,
    /// Location ID
    loc: u32,
    /// Description
    description: []const u8,
    /// Confidence score
    confidence: f32,

    /// Anomaly kind
    pub const AnomalyKind = enum(u8) {
        /// Lock order violation
        lock_order_violation,
        /// Unexpected alias
        unexpected_alias,
        /// Taint flow
        taint_flow,
        /// Memory leak
        memory_leak,
        /// Other
        other,
    };
};

test "MergeEngine - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const engine = MergeEngine.init(std.testing.allocator, &store);
    _ = engine;
}

test "MergeEngine - merge empty" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const engine = MergeEngine.init(std.testing.allocator, &store);

    const events: []DecodedEvent = &.{};
    const merged = try engine.merge(events);
    defer std.testing.allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 0), merged.len);
}

test "MergeEngine - merge single event" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const engine = MergeEngine.init(std.testing.allocator, &store);

    const ev = DecodedEvent{
        .tag = 1,
        .tid = 1,
        .loc = 42,
        .arg = 100,
        .timestamp = std.time.nanoTimestamp(),
    };

    const merged = try engine.merge(&.{ev});
    defer std.testing.allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 1), merged.len);
    try std.testing.expectEqual(@as(u8, 1), merged[0].tag);
    try std.testing.expectEqual(@as(u32, 42), merged[0].loc);
    try std.testing.expect(merged[0].confidence >= 0.0 and merged[0].confidence <= 1.0);
}

test "MergeEngine - merge with static facts" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Add some static facts
    try store.insert(.cfg_edge, 1, 42, 0);
    try store.insert(.dfg_edge, 42, 100, 0);

    const engine = MergeEngine.init(std.testing.allocator, &store);

    const ev = DecodedEvent{
        .tag = 1,
        .tid = 1,
        .loc = 42,
        .arg = 100,
        .timestamp = std.time.nanoTimestamp(),
    };

    const merged = try engine.merge(&.{ev});
    defer std.testing.allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 1), merged.len);
    // Confidence should be higher due to static facts
    try std.testing.expect(merged[0].confidence > 0.5);
}

test "MergeEngine - merge multiple events" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const engine = MergeEngine.init(std.testing.allocator, &store);

    var events = std.ArrayList(DecodedEvent).init(std.testing.allocator);
    defer events.deinit();

    for (0..10) |i| {
        const ev = DecodedEvent{
            .tag = @truncate(i),
            .tid = 1,
            .loc = @truncate(i),
            .arg = @intCast(i),
            .timestamp = std.time.nanoTimestamp(),
        };
        try events.append(ev);
    }

    const merged = try engine.merge(events.items);
    defer std.testing.allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 10), merged.len);
}

test "MergedEvent - confidence checks" {
    const high_conf = MergedEvent{
        .tag = 1,
        .tid = 1,
        .loc = 1,
        .arg = 1,
        .timestamp = 0,
        .confidence = 0.9,
    };

    const low_conf = MergedEvent{
        .tag = 1,
        .tid = 1,
        .loc = 1,
        .arg = 1,
        .timestamp = 0,
        .confidence = 0.3,
    };

    try std.testing.expect(high_conf.isHighConfidence());
    try std.testing.expect(!low_conf.isHighConfidence());
    try std.testing.expect(low_conf.isLowConfidence());
    try std.testing.expect(!high_conf.isLowConfidence());
}
