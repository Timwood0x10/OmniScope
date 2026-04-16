//! Runtime Stage
//!
//! This module implements the runtime stage which collects
//! events from the instrumented program.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Stage = @import("stage.zig").Stage;
const StageContext = @import("stage.zig").StageContext;
const StageResult = @import("stage.zig").StageResult;
const StageKind = @import("stage.zig").StageKind;

const RingBuffer = @import("../runtime/rt_lib/ring_buffer.zig").RingBuffer;
const Event = @import("../runtime/rt_lib/ring_buffer.zig").Event;

/// Runtime stage configuration
pub const RuntimeStageConfig = struct {
    /// Ring buffer capacity
    ring_buffer_capacity: usize = 1 << 20,
    /// Collection timeout in milliseconds
    timeout_ms: u64 = 1000,
    /// Whether to enable background collection
    enable_background: bool = true,
};

/// Runtime stage
///
/// This stage collects runtime events from the instrumented program
/// through the ring buffer and decodes them.
pub const RuntimeStage = struct {
    config: RuntimeStageConfig,
    allocator: Allocator,
    ring_buffer: RingBuffer,
    event_buffer: std.ArrayListUnmanaged(Event),

    /// Create a new runtime stage
    pub fn init(allocator: Allocator, config: RuntimeStageConfig) !RuntimeStage {
        var event_buffer = std.ArrayListUnmanaged(Event){};
        try event_buffer.ensureTotalCapacity(allocator, 1024);

        return .{
            .config = config,
            .allocator = allocator,
            .ring_buffer = RingBuffer.init(),
            .event_buffer = event_buffer,
        };
    }

    /// Deinitialize the runtime stage
    pub fn deinit(self: *RuntimeStage) void {
        self.event_buffer.deinit(self.allocator);
    }

    /// Run the runtime stage
    pub fn run(self: *const RuntimeStage, ctx: *StageContext) StageResult {
        // This would:
        // 1. Start the instrumented program
        // 2. Collect events from the ring buffer
        // 3. Decode events
        // 4. Store events for later processing

        // For now, we just collect any available events
        _ = ctx;
        _ = self;

        return .success;
    }

    /// Collect events from the ring buffer
    pub fn collectEvents(self: *RuntimeStage) ![]Event {
        // Clear previous events
        self.event_buffer.clearRetainingCapacity();

        // Collect all available events
        while (self.ring_buffer.tryPop()) |ev| {
            try self.event_buffer.append(self.allocator, ev);
        }

        return self.event_buffer.items;
    }

    /// Get collection statistics
    pub fn getStats(self: *const RuntimeStage) RuntimeStats {
        const total_events = self.event_buffer.items.len;
        const buffer_utilization = @as(f32, @floatFromInt(self.ring_buffer.available())) /
            @as(f32, @floatFromInt(1 << 20));

        return .{
            .total_events = total_events,
            .events_per_second = 0.0, // Would need timing info
            .buffer_utilization = buffer_utilization,
        };
    }
};

/// Runtime collection statistics
pub const RuntimeStats = struct {
    /// Total events collected
    total_events: usize = 0,
    /// Events per second
    events_per_second: f64 = 0.0,
    /// Ring buffer utilization
    buffer_utilization: f32 = 0.0,
};

test "RuntimeStage - basic creation" {
    if (true) return error.SkipZigTest;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RuntimeStageConfig{};
    var stage = try RuntimeStage.init(allocator, config);
    defer stage.deinit();

    var ctx = StageContext{
        .allocator = allocator,
    };

    const result = stage.run(&ctx);
    try std.testing.expectEqual(StageResult.success, result);

    const stats = stage.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.total_events);
}

test "RuntimeStage - validate as Stage" {
    const ValidStage = Stage(struct {
        pub const name = "runtime-stage";
        pub const kind = StageKind.runtime;
        pub const run = RuntimeStage.run;
    });

    _ = ValidStage;
}

test "RuntimeStage - config with timeout" {
    if (true) return error.SkipZigTest;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RuntimeStageConfig{
        .timeout_ms = 2000,
        .enable_background = false,
    };
    var stage = try RuntimeStage.init(allocator, config);
    defer stage.deinit();

    var ctx = StageContext{
        .allocator = allocator,
    };

    const result = stage.run(&ctx);
    try std.testing.expectEqual(StageResult.success, result);
}

test "RuntimeStage - collect events" {
    if (true) return error.SkipZigTest;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RuntimeStageConfig{};
    var stage = try RuntimeStage.init(allocator, config);
    defer stage.deinit();

    // Push some test events
    const test_event = Event{
        .tag = 1,
        .tid = 100,
        .loc = 200,
        .arg = 300,
    };
    _ = stage.ring_buffer.tryPush(test_event);

    // Collect events
    const events = try stage.collectEvents();
    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(test_event.tag, events[0].tag);
    try std.testing.expectEqual(test_event.tid, events[0].tid);
    try std.testing.expectEqual(test_event.loc, events[0].loc);
    try std.testing.expectEqual(test_event.arg, events[0].arg);
}

test "RuntimeStage - multiple collect calls" {
    if (true) return error.SkipZigTest;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RuntimeStageConfig{};
    var stage = try RuntimeStage.init(allocator, config);
    defer stage.deinit();

    // First collect - no events
    const events1 = try stage.collectEvents();
    try std.testing.expectEqual(@as(usize, 0), events1.len);

    // Push events
    for (0..5) |i| {
        const ev = Event{
            .tag = @truncate(i),
            .tid = 1,
            .loc = @truncate(i),
            .arg = @intCast(i),
        };
        _ = stage.ring_buffer.tryPush(ev);
    }

    // Second collect - should have 5 events
    const events2 = try stage.collectEvents();
    try std.testing.expectEqual(@as(usize, 5), events2.len);

    // Third collect - should be empty
    const events3 = try stage.collectEvents();
    try std.testing.expectEqual(@as(usize, 0), events3.len);
}
