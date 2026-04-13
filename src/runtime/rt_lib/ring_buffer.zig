//! Lock-free Single Producer Single Consumer (SPSC) Ring Buffer
//!
//! This module implements a lock-free ring buffer for runtime event collection.
//! Designed for SPSC (single producer, single consumer) scenario.
//!
//! Principle: Use atomic operations for lock-free synchronization.

const std = @import("std");

/// Production ring buffer capacity (1M events ≈ 16MB)
const PRODUCTION_CAPACITY: usize = 1 << 20;

/// Test ring buffer capacity (1K events to avoid stack overflow in tests)
const TEST_CAPACITY: usize = 1 << 10;

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

/// Lock-free SPSC ring buffer with configurable capacity
///
/// Usage:
///   - Production: `RingBuffer.init()` uses PRODUCTION_CAPACITY
///   - Testing: `TestRingBuffer.init()` uses TEST_CAPACITY (smaller)
pub const RingBuffer = RingBufferType(PRODUCTION_CAPACITY);

/// Test ring buffer with smaller capacity to avoid stack overflow
pub const TestRingBuffer = RingBufferType(TEST_CAPACITY);

fn RingBufferType(comptime capacity: usize) type {
    const MASK: usize = capacity - 1;

    return struct {
        /// Event buffer
        buf: [capacity]Event align(64),
        /// Head index (producer)
        head: std.atomic.Value(u32) align(64),
        /// Tail index (consumer)
        tail: std.atomic.Value(u32) align(64),
        /// Committed count (for debugging)
        committed: std.atomic.Value(u32),

        const CAPACITY = capacity;
        const MASK_VALUE = MASK;

        /// Initialize a new ring buffer
        pub fn init() @This() {
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
        pub fn tryPush(self: *@This(), ev: Event) bool {
            const idx = self.head.load(.monotonic);
            const next_idx = (idx + 1) & @as(u32, @truncate(MASK_VALUE));

            if (next_idx == self.tail.load(.acquire)) {
                return false;
            }

            self.buf[idx] = ev;
            self.head.store(next_idx, .release);
            _ = self.committed.fetchAdd(1, .monotonic);

            return true;
        }

        /// Try to pop an event (non-blocking)
        ///
        /// Returns null if buffer is empty
        pub fn tryPop(self: *@This()) ?Event {
            const tail = self.tail.load(.monotonic);

            if (tail == self.head.load(.acquire)) {
                return null;
            }

            const ev = self.buf[tail];
            self.tail.store((tail + 1) & @as(u32, @truncate(MASK_VALUE)), .release);

            return ev;
        }

        /// Get the number of available events
        pub fn available(self: *const @This()) u32 {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.monotonic);

            if (head >= tail) {
                return head - tail;
            } else {
                return @as(u32, @truncate(CAPACITY)) + head - tail;
            }
        }

        /// Check if buffer is empty
        pub fn isEmpty(self: *const @This()) bool {
            return self.head.load(.monotonic) == self.tail.load(.monotonic);
        }

        /// Check if buffer is full
        pub fn isFull(self: *const @This()) bool {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.acquire);
            return ((head + 1) & @as(u32, @truncate(MASK_VALUE))) == tail;
        }
    };
}

test "RingBuffer - init" {
    var rb = TestRingBuffer.init();
    try std.testing.expect(rb.isEmpty());
}

test "RingBuffer - push and pop" {
    var rb = TestRingBuffer.init();

    const ev = Event{
        .tag = 1,
        .tid = 2,
        .loc = 3,
        .arg = 4,
    };

    try std.testing.expect(rb.tryPush(ev));
    try std.testing.expect(!rb.isEmpty());

    const popped = rb.tryPop();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(ev.tag, popped.?.tag);
    try std.testing.expectEqual(ev.tid, popped.?.tid);
    try std.testing.expectEqual(ev.loc, popped.?.loc);
    try std.testing.expectEqual(ev.arg, popped.?.arg);
    try std.testing.expect(rb.isEmpty());
}

test "RingBuffer - multiple events" {
    var rb = TestRingBuffer.init();

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
    var rb = TestRingBuffer.init();
    try std.testing.expect(rb.tryPop() == null);
}
