//! Runtime probe stubs for instrumentation
//!
//! This module provides lightweight probe functions that will be
//! inserted into instrumented code to capture runtime events.
//!
//! Principle: Minimal overhead, lock-free, inline-friendly

const std = @import("std");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const Event = @import("ring_buffer.zig").Event;

/// Global ring buffer instance (will be initialized by collector)
///
/// Note: This is a simplified approach. In production, this would
/// be allocated in shared memory for multi-process scenarios.
var global_ring_buffer: ?*RingBuffer = null;

/// Event tags for different probe types
pub const EventTag = enum(u8) {
    /// Memory allocation
    alloc = 1,
    /// Memory deallocation
    free = 2,
    /// Lock acquire
    lock_acquire = 3,
    /// Lock release
    lock_release = 4,
    /// Taint source
    taint_source = 5,
    /// Taint sink
    taint_sink = 6,
};

/// Initialize the runtime system
///
/// This must be called before any probe is used.
pub export fn rt_init(buf_ptr: *RingBuffer) void {
    global_ring_buffer = buf_ptr;
}

/// Probe for memory allocation
///
/// Parameters:
///   - ptr: Pointer to allocated memory
///   - size: Size of allocation
///   - loc: Location ID (from instrumentation)
pub export fn rt_alloc_probe(ptr: u64, size: u64, loc: u32) void {
    _ = size; // Not used in this simple implementation
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.alloc),
            .tid = tid,
            .loc = loc,
            .arg = ptr, // Store pointer in arg field
        };
        _ = rb.tryPush(ev);
    }
}

/// Probe for memory deallocation
///
/// Parameters:
///   - ptr: Pointer to freed memory
///   - loc: Location ID (from instrumentation)
pub export fn rt_free_probe(ptr: u64, loc: u32) void {
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.free),
            .tid = tid,
            .loc = loc,
            .arg = ptr,
        };
        _ = rb.tryPush(ev);
    }
}

/// Probe for lock acquire
///
/// Parameters:
///   - lock_id: Unique lock identifier
///   - loc: Location ID (from instrumentation)
pub export fn rt_lock_acquire_probe(lock_id: u64, loc: u32) void {
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.lock_acquire),
            .tid = tid,
            .loc = loc,
            .arg = lock_id,
        };
        _ = rb.tryPush(ev);
    }
}

/// Probe for lock release
///
/// Parameters:
///   - lock_id: Unique lock identifier
///   - loc: Location ID (from instrumentation)
pub export fn rt_lock_release_probe(lock_id: u64, loc: u32) void {
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.lock_release),
            .tid = tid,
            .loc = loc,
            .arg = lock_id,
        };
        _ = rb.tryPush(ev);
    }
}

/// Probe for taint source
///
/// Parameters:
///   - value: Tainted value
///   - loc: Location ID (from instrumentation)
pub export fn rt_taint_source_probe(value: u64, loc: u32) void {
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.taint_source),
            .tid = tid,
            .loc = loc,
            .arg = value,
        };
        _ = rb.tryPush(ev);
    }
}

/// Probe for taint sink
///
/// Parameters:
///   - value: Tainted value
///   - loc: Location ID (from instrumentation)
pub export fn rt_taint_sink_probe(value: u64, loc: u32) void {
    if (global_ring_buffer) |rb| {
        const tid = getCurrentThreadId();
        const ev = Event{
            .tag = @intFromEnum(EventTag.taint_sink),
            .tid = tid,
            .loc = loc,
            .arg = value,
        };
        _ = rb.tryPush(ev);
    }
}

/// Get current thread ID
///
/// Note: This is a simplified implementation. In production,
/// use platform-specific thread ID APIs.
fn getCurrentThreadId() u16 {
    // Simplified: use a counter for single-threaded testing
    // In production, use pthread_self() or similar
    return 1;
}

test "rt_init and probe" {
    var rb = RingBuffer.init();
    rt_init(&rb);

    // Test alloc probe
    rt_alloc_probe(0x1000, 64, 42);
    try std.testing.expect(!rb.isEmpty());

    const ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.alloc)), ev.tag);
    try std.testing.expectEqual(@as(u64, 0x1000), ev.arg);
    try std.testing.expectEqual(@as(u32, 42), ev.loc);
}

test "rt_lock_acquire_probe" {
    var rb = RingBuffer.init();
    rt_init(&rb);

    rt_lock_acquire_probe(0x2000, 10);
    const ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_acquire)), ev.tag);
    try std.testing.expectEqual(@as(u64, 0x2000), ev.arg);
}
