//! Runtime Event Collector
//!
//! This module implements the event collector that reads from
//! the shared ring buffer and decodes events.

const std = @import("std");
const RingBuffer = @import("rt_lib/ring_buffer.zig").RingBuffer;
const Event = @import("rt_lib/ring_buffer.zig").Event;

/// Event collector
pub const Collector = struct {
    allocator: std.mem.Allocator,
    ring_buffer: *RingBuffer,
    running: bool,

    /// Create a new event collector
    pub fn init(allocator: std.mem.Allocator, ring_buffer: *RingBuffer) Collector {
        return .{
            .allocator = allocator,
            .ring_buffer = ring_buffer,
            .running = false,
        };
    }

    /// Start collecting events
    pub fn start(self: *Collector) !void {
        self.running = true;
    }

    /// Stop collecting events
    pub fn stop(self: *Collector) void {
        self.running = false;
    }

    /// Check if collector is running
    pub fn isRunning(self: *const Collector) bool {
        return self.running;
    }

    /// Collect available events
    pub fn collect(self: *Collector) ![]Event {
        var events = std.ArrayList(Event).init(self.allocator);

        while (self.ring_buffer.tryPop()) |ev| {
            try events.append(ev);
        }

        return events.toOwnedSlice();
    }

    /// Collect events with timeout
    pub fn collectWithTimeout(self: *Collector, timeout_ns: u64) ![]Event {
        var events = std.ArrayList(Event).init(self.allocator);

        const start_time = std.time.nanoTimestamp();
        var elapsed: i128 = 0;

        while (elapsed < timeout_ns) {
            if (self.ring_buffer.tryPop()) |ev| {
                try events.append(ev);
            } else {
                // No events available, sleep briefly
                std.time.sleep(1_000_000); // 1ms
            }

            const current_time = std.time.nanoTimestamp();
            elapsed = current_time - start_time;
        }

        return events.toOwnedSlice();
    }

    /// Collect events until buffer is empty
    pub fn collectAll(self: *Collector) ![]Event {
        var events = std.ArrayList(Event).init(self.allocator);

        while (true) {
            if (self.ring_buffer.tryPop()) |ev| {
                try events.append(ev);
            } else {
                break;
            }
        }

        return events.toOwnedSlice();
    }
};

/// Event decoder
pub const Decoder = struct {
    allocator: std.mem.Allocator,

    /// Create a new event decoder
    pub fn init(allocator: std.mem.Allocator) Decoder {
        return .{
            .allocator = allocator,
        };
    }

    /// Decode a single event
    pub fn decode(self: *Decoder, ev: Event) !DecodedEvent {
        _ = self;

        return .{
            .tag = ev.tag,
            .tid = ev.tid,
            .loc = ev.loc,
            .arg = ev.arg,
            .timestamp = std.time.nanoTimestamp(),
        };
    }

    /// Decode multiple events
    pub fn decodeBatch(self: *Decoder, events: []Event) ![]DecodedEvent {
        var decoded = std.ArrayList(DecodedEvent).init(self.allocator);

        for (events) |ev| {
            const dec_ev = try self.decode(ev);
            try decoded.append(dec_ev);
        }

        return decoded.toOwnedSlice();
    }
};

/// Decoded event with timestamp
pub const DecodedEvent = struct {
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

    /// Get the event duration since another event
    pub fn durationSince(self: DecodedEvent, other: DecodedEvent) i128 {
        return self.timestamp - other.timestamp;
    }

    /// Check if this event is before another
    pub fn isBefore(self: DecodedEvent, other: DecodedEvent) bool {
        return self.timestamp < other.timestamp;
    }
};

test "Collector - init" {
    var ring_buffer = RingBuffer.init();
    var collector = Collector.init(std.testing.allocator, &ring_buffer);
    _ = collector;
}

test "Collector - start and stop" {
    var ring_buffer = RingBuffer.init();
    var collector = Collector.init(std.testing.allocator, &ring_buffer);

    try collector.start();
    try std.testing.expect(collector.isRunning());

    collector.stop();
    try std.testing.expect(!collector.isRunning());
}

test "Collector - collect empty" {
    var ring_buffer = RingBuffer.init();
    var collector = Collector.init(std.testing.allocator, &ring_buffer);

    const events = try collector.collect();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 0), events.len);
}

test "Collector - collect with events" {
    var ring_buffer = RingBuffer.init();
    var collector = Collector.init(std.testing.allocator, &ring_buffer);

    // Push some events
    const ev1 = Event{ .tag = 1, .tid = 1, .loc = 10, .arg = 100 };
    const ev2 = Event{ .tag = 2, .tid = 1, .loc = 20, .arg = 200 };

    _ = ring_buffer.tryPush(ev1);
    _ = ring_buffer.tryPush(ev2);

    const events = try collector.collect();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 2), events.len);
}

test "Collector - collectAll" {
    var ring_buffer = RingBuffer.init();
    var collector = Collector.init(std.testing.allocator, &ring_buffer);

    // Push events
    for (0..10) |i| {
        const ev = Event{
            .tag = @truncate(i),
            .tid = 1,
            .loc = @truncate(i),
            .arg = @intCast(i),
        };
        _ = ring_buffer.tryPush(ev);
    }

    const events = try collector.collectAll();
    defer std.testing.allocator.free(events);

    try std.testing.expectEqual(@as(usize, 10), events.len);
}

test "Decoder - init" {
    var decoder = Decoder.init(std.testing.allocator);
    _ = decoder;
}

test "Decoder - decode" {
    var decoder = Decoder.init(std.testing.allocator);

    const ev = Event{ .tag = 1, .tid = 2, .loc = 3, .arg = 4 };
    const decoded = try decoder.decode(ev);

    try std.testing.expectEqual(@as(u8, 1), decoded.tag);
    try std.testing.expectEqual(@as(u16, 2), decoded.tid);
    try std.testing.expectEqual(@as(u32, 3), decoded.loc);
    try std.testing.expectEqual(@as(u64, 4), decoded.arg);
    try std.testing.expect(decoded.timestamp > 0);
}

test "Decoder - decodeBatch" {
    var decoder = Decoder.init(std.testing.allocator);

    var events = std.ArrayList(Event).init(std.testing.allocator);
    defer events.deinit();

    for (0..5) |i| {
        const ev = Event{
            .tag = @truncate(i),
            .tid = 1,
            .loc = @truncate(i),
            .arg = @intCast(i),
        };
        try events.append(ev);
    }

    const decoded = try decoder.decodeBatch(events.items);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqual(@as(usize, 5), decoded.len);
}

test "DecodedEvent - durationSince" {
    var decoder = Decoder.init(std.testing.allocator);

    const ev1 = Event{ .tag = 1, .tid = 1, .loc = 1, .arg = 1 };
    std.time.sleep(1_000_000); // 1ms

    const ev2 = Event{ .tag = 2, .tid = 1, .loc = 2, .arg = 2 };

    const dec1 = try decoder.decode(ev1);
    const dec2 = try decoder.decode(ev2);

    const duration = dec2.durationSince(dec1);
    try std.testing.expect(duration > 0);
}

test "DecodedEvent - isBefore" {
    var decoder = Decoder.init(std.testing.allocator);

    const ev1 = Event{ .tag = 1, .tid = 1, .loc = 1, .arg = 1 };
    std.time.sleep(1_000_000); // 1ms

    const ev2 = Event{ .tag = 2, .tid = 1, .loc = 2, .arg = 2 };

    const dec1 = try decoder.decode(ev1);
    const dec2 = try decoder.decode(ev2);

    try std.testing.expect(dec1.isBefore(dec2));
    try std.testing.expect(!dec2.isBefore(dec1));
}
