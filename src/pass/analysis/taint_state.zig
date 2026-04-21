//! Taint State Management
//!
//! Defines taint states, taint information, and the taint context
//! for tracking data flow through LLVM IR.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ValueIdMap = @import("../../dataflow/value_id_map.zig").ValueIdMap;

/// Represents taint state for a value or variable.
/// Used to track how data flows through the program.
pub const TaintState = enum(u8) {
    /// No taint - value is clean
    none = 0,
    /// Directly from source - original tainted input
    source = 1,
    /// Derived from tainted value - propagated taint
    tainted = 2,
    /// Explicitly sanitized - safe after validation
    safe = 3,
};

/// Taint information for a value.
/// Tracks the state, source, and confidence of taint.
pub const TaintInfo = struct {
    /// Unique identifier for this taint record
    id: u32,
    /// Current taint state
    state: TaintState,
    /// Original source ID (null if not from a source)
    source_id: ?u32,
    /// Confidence score (0.0 - 1.0)
    confidence: f32,
};

/// Taint propagation context.
/// Manages taint state for values, parameters, and return values.
pub const TaintContext = struct {
    allocator: Allocator,
    mutex: std.Thread.Mutex,
    /// Value ID mapper to avoid pointer truncation collisions
    value_id_map: ValueIdMap,
    /// Taint info indexed by value ID
    value_taint: std.AutoHashMap(u32, TaintInfo),
    /// Parameter taint indexed by function ID
    param_taint: std.AutoHashMap(u32, std.ArrayList(TaintInfo)),
    /// Return value taint indexed by function ID
    return_taint: std.AutoHashMap(u32, TaintInfo),

    /// Initialize a new taint context
    pub fn init(allocator: Allocator) TaintContext {
        return .{
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .value_id_map = ValueIdMap.init(allocator),
            .value_taint = std.AutoHashMap(u32, TaintInfo).init(allocator),
            .param_taint = std.AutoHashMap(u32, std.ArrayList(TaintInfo)).init(allocator),
            .return_taint = std.AutoHashMap(u32, TaintInfo).init(allocator),
        };
    }

    /// Deinitialize the taint context
    pub fn deinit(self: *TaintContext) void {
        self.value_taint.deinit();
        var param_iter = self.param_taint.iterator();
        while (param_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.param_taint.deinit();
        self.return_taint.deinit();
        self.value_id_map.deinit();
    }

    /// Get or create a unique ID for a pointer value.
    /// This replaces direct pointer truncation to avoid collisions.
    pub fn getValueId(self: *TaintContext, ptr: anytype) !u32 {
        const ptr_val = @intFromPtr(ptr);
        if (ptr_val == 0) return error.NullPointer;
        return self.value_id_map.getOrPutId(ptr_val);
    }

    /// Get or create a unique ID from an already-converted usize value.
    /// Use this when you already have @intFromPtr result.
    pub fn getValueIdFromUsize(self: *TaintContext, ptr_val: usize) !u32 {
        if (ptr_val == 0) return error.NullPointer;
        return self.value_id_map.getOrPutId(ptr_val);
    }

    /// Set taint info for a value
    pub fn setValueTaint(self: *TaintContext, value_id: u32, info: TaintInfo) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.value_taint.put(value_id, info);
    }

    /// Get taint info for a value
    pub fn getValueTaint(self: *TaintContext, value_id: u32) ?TaintInfo {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value_taint.get(value_id);
    }

    /// Merge taint from source to destination
    pub fn mergeTaint(self: *TaintContext, dst: u32, src: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const src_info = self.value_taint.get(src) orelse return;
        const dst_info = self.value_taint.get(dst);

        const new_confidence = if (dst_info) |di|
            @max(src_info.confidence, di.confidence)
        else
            src_info.confidence;

        const decayed_confidence = @min(new_confidence * 0.95, 1.0);

        const new_info = TaintInfo{
            .id = src_info.id,
            .state = .tainted,
            .source_id = src_info.source_id,
            .confidence = decayed_confidence,
        };

        try self.value_taint.put(dst, new_info);
    }

    /// Check if a value is tainted
    pub fn isTainted(self: *TaintContext, value_id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.value_taint.get(value_id)) |info| {
            return info.state == .source or info.state == .tainted;
        }
        return false;
    }

    /// Get all tainted value IDs
    pub fn getTaintedValues(self: *TaintContext, allocator: Allocator) ![]u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        var values = std.ArrayList(u32).init(allocator);
        errdefer values.deinit(allocator);

        var iter = self.value_taint.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr.*;
            if (info.state == .source or info.state == .tainted) {
                try values.append(allocator, entry.key_ptr.*);
            }
        }

        return values.toOwnedSlice(allocator);
    }

    /// Get count of tainted values
    pub fn taintedCount(self: *TaintContext) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        var count: usize = 0;
        var iter = self.value_taint.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr.*;
            if (info.state == .source or info.state == .tainted) {
                count += 1;
            }
        }
        return count;
    }

    /// Clear all taint information
    pub fn clear(self: *TaintContext) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value_taint.clearRetainingCapacity();
        var param_iter = self.param_taint.iterator();
        while (param_iter.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }
        self.param_taint.clearRetainingCapacity();
        self.return_taint.clearRetainingCapacity();
    }
};

test "TaintState - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TaintState.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TaintState.source));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(TaintState.tainted));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(TaintState.safe));
}

test "TaintInfo - structure" {
    const info = TaintInfo{
        .id = 42,
        .state = .tainted,
        .source_id = 10,
        .confidence = 0.8,
    };
    try std.testing.expectEqual(@as(u32, 42), info.id);
    try std.testing.expectEqual(TaintState.tainted, info.state);
    try std.testing.expectEqual(@as(?u32, 10), info.source_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), info.confidence, 0.001);
}

test "TaintInfo - default confidence" {
    const info = TaintInfo{
        .id = 1,
        .state = .source,
        .source_id = null,
        .confidence = 1.0,
    };
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), info.confidence, 0.001);
}

test "TaintInfo - no source" {
    const info = TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.5,
    };
    try std.testing.expectEqual(@as(?u32, null), info.source_id);
}

test "TaintContext - init and deinit" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();
    try std.testing.expectEqual(@as(usize, 0), ctx.value_taint.count());
}

test "TaintContext - set and get value taint" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const info = TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.95,
    };
    try ctx.setValueTaint(100, info);

    const retrieved = ctx.getValueTaint(100);
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(TaintState.tainted, retrieved.?.state);
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), retrieved.?.confidence, 0.001);
}

test "TaintContext - merge taint" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const src_info = TaintInfo{
        .id = 1,
        .state = .source,
        .source_id = 5,
        .confidence = 1.0,
    };
    try ctx.setValueTaint(10, src_info);

    try ctx.mergeTaint(20, 10);

    const merged = ctx.getValueTaint(20);
    try std.testing.expect(merged != null);
    try std.testing.expectEqual(TaintState.tainted, merged.?.state);
    try std.testing.expectEqual(@as(?u32, 5), merged.?.source_id);
}

test "TaintContext - is tainted" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isTainted(100));

    const info = TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.9,
    };
    try ctx.setValueTaint(100, info);

    try std.testing.expect(ctx.isTainted(100));
}

test "TaintContext - get tainted values" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const info1 = TaintInfo{ .id = 1, .state = .source, .source_id = null, .confidence = 1.0 };
    const info2 = TaintInfo{ .id = 2, .state = .tainted, .source_id = 1, .confidence = 0.9 };
    const info3 = TaintInfo{ .id = 3, .state = .none, .source_id = null, .confidence = 0.0 };

    try ctx.setValueTaint(100, info1);
    try ctx.setValueTaint(200, info2);
    try ctx.setValueTaint(300, info3);

    const tainted = try ctx.getTaintedValues(std.testing.allocator);
    defer std.testing.allocator.free(tainted);

    try std.testing.expectEqual(@as(usize, 2), tainted.len);
}

test "TaintContext - tainted count" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.taintedCount());

    const info1 = TaintInfo{ .id = 1, .state = .source, .source_id = null, .confidence = 1.0 };
    const info2 = TaintInfo{ .id = 2, .state = .tainted, .source_id = 1, .confidence = 0.9 };
    const info3 = TaintInfo{ .id = 3, .state = .safe, .source_id = null, .confidence = 0.0 };

    try ctx.setValueTaint(100, info1);
    try ctx.setValueTaint(200, info2);
    try ctx.setValueTaint(300, info3);

    try std.testing.expectEqual(@as(usize, 2), ctx.taintedCount());
}

test "TaintContext - clear" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const info = TaintInfo{ .id = 1, .state = .tainted, .source_id = null, .confidence = 0.9 };
    try ctx.setValueTaint(100, info);

    try std.testing.expectEqual(@as(usize, 1), ctx.value_taint.count());

    ctx.clear();

    try std.testing.expectEqual(@as(usize, 0), ctx.value_taint.count());
}

test "TaintContext - safe state not tainted" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const info = TaintInfo{
        .id = 1,
        .state = .safe,
        .source_id = null,
        .confidence = 0.0,
    };
    try ctx.setValueTaint(100, info);

    try std.testing.expect(!ctx.isTainted(100));
}

test "TaintContext - multiple values" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const info = TaintInfo{
            .id = i,
            .state = if (i % 2 == 0) .tainted else .none,
            .source_id = null,
            .confidence = @as(f32, @floatFromInt(i)) / 100.0,
        };
        try ctx.setValueTaint(i, info);
    }

    try std.testing.expectEqual(@as(usize, 100), ctx.value_taint.count());
    try std.testing.expectEqual(@as(usize, 50), ctx.taintedCount());
}
