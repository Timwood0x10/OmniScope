//! Lock-free Single Producer Single Consumer (SPSC) Ring Buffer
//!
//! This module implements a lock-free ring buffer for runtime event collection.
//! Designed for SPSC (single producer, single consumer) scenario.
//!
//! Principle: Use atomic operations for lock-free synchronization.

const std = @import("std");

/// Ring buffer capacity mask (must be power of 2)
const CAPACITY: usize = 1 << 20; // 1M events
const MASK: usize = CAPACITY - 1;

/// Runtime event (compressed format)
pub const Event = packed struct {
    /// Event tag (type)
    tag: u8,
    /// Thread ID
    tid: u16,
    /// Location ID
    loc: u32,
    /// Argument value
    arg: u64,
};

/// Lock-free SPSC ring buffer
pub const RingBuffer = struct {
    /// Event buffer
    buf: [CAPACITY]Event align(64),
    /// Head index (producer)
    head: std.atomic.Value(u32) align(64),
    /// Tail index (consumer)
    tail: std.atomic.Value(u32) align(64),
    /// Committed count (for debugging)
    committed: std.atomic.Value(u32),

    /// Initialize a new ring buffer
    pub fn init() RingBuffer {
        return .{
            .buf = undefined,
            .head = std.atomic.Value(u32).init(0),
            .tail = std.atomic.Value(u32).init(0),
            .committed = std.atomic.Value(u32).init(0),
        };
    }

    /// Try to push an event (non-blocking)
    ///
    /// Returns true if successful, false if buffer is full
    pub fn tryPush(self: *RingBuffer, ev: Event) bool {
        const idx = self.head.load(.monotonic);
        const next_idx = (idx + 1) & @as(u32, @truncate(MASK));

        // Check if buffer is full
        if (next_idx == self.tail.load(.acquire)) {
            return false;
        }

        // Write event
        self.buf[idx] = ev;

        // Commit
        self.head.store(next_idx, .release);
        _ = self.committed.fetchAdd(1, .monotonic);

        return true;
    }

    /// Try to pop an event (non-blocking)
    ///
    /// Returns null if buffer is empty
    pub fn tryPop(self: *RingBuffer) ?Event {
        const tail = self.tail.load(.monotonic);

        // Check if buffer is empty
        if (tail == self.head.load(.acquire)) {
            return null;
        }

        // Read event
        const ev = self.buf[tail];

        // Advance tail
        self.tail.store((tail + 1) & @as(u32, @truncate(MASK)), .release);

        return ev;
    }

    /// Get the number of available events
    pub fn available(self: *const RingBuffer) u32 {
        const head = self.head.load(.monotonic);
        const tail = self.tail.load(.monotonic);

        if (head >= tail) {
            return head - tail;
        } else {
            return @as(u32, @truncate(CAPACITY)) + head - tail;
        }
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *const RingBuffer) bool {
        return self.head.load(.monotonic) == self.tail.load(.monotonic);
    }

    /// Check if buffer is full
    pub fn isFull(self: *const RingBuffer) bool {
        const head = self.head.load(.monotonic);
        const tail = self.tail.load(.acquire);
        return ((head + 1) & @as(u32, @truncate(MASK))) == tail;
    }
};

test "RingBuffer - init" {
    var rb = RingBuffer.init();
    try std.testing.expect(rb.isEmpty());
}

test "RingBuffer - push and pop" {
    var rb = RingBuffer.init();

    const ev = Event{
        .tag = 1,
        .tid = 2,
        .loc = 3,
        .arg = 4,
    };

    // Push
    try std.testing.expect(rb.tryPush(ev));
    try std.testing.expect(!rb.isEmpty());

    // Pop
    const popped = rb.tryPop();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(ev.tag, popped.?.tag);
    try std.testing.expectEqual(ev.tid, popped.?.tid);
    try std.testing.expectEqual(ev.loc, popped.?.loc);
    try std.testing.expectEqual(ev.arg, popped.?.arg);
    try std.testing.expect(rb.isEmpty());
}

test "RingBuffer - multiple events" {
    var rb = RingBuffer.init();

    for (0..10) |i| {
        const ev = Event{
            .tag = @truncate(i),
            .tid = 1,
            .loc = @truncate(i),
            .arg = @intCast(i),
        };
        try std.testing.expect(rb.tryPush(ev));
    }

    try std.testing.expectEqual(@as(u32, 10), rb.available());

    for (0..10) |i| {
        const ev = rb.tryPop().?;
        try std.testing.expectEqual(@as(u8, @truncate(i)), ev.tag);
    }

    try std.testing.expect(rb.isEmpty());
}

test "RingBuffer - empty pop" {
    var rb = RingBuffer.init();
    try std.testing.expect(rb.tryPop() == null);
}
