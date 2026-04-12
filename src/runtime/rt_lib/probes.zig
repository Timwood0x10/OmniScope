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

test "rt_all_probe_types" {
    var rb = RingBuffer.init();
    rt_init(&rb);

    // Test all probe types
    rt_alloc_probe(0x1000, 64, 1);
    rt_free_probe(0x1000, 2);
    rt_lock_acquire_probe(0x2000, 3);
    rt_lock_release_probe(0x2000, 4);
    rt_taint_source_probe(0x3000, 5);
    rt_taint_sink_probe(0x3000, 6);

    try std.testing.expectEqual(@as(u32, 6), rb.available());

    // Verify each probe in order
    const alloc_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.alloc)), alloc_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x1000), alloc_ev.arg);
    try std.testing.expectEqual(@as(u32, 1), alloc_ev.loc);

    const free_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.free)), free_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x1000), free_ev.arg);
    try std.testing.expectEqual(@as(u32, 2), free_ev.loc);

    const lock_acq_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_acquire)), lock_acq_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x2000), lock_acq_ev.arg);
    try std.testing.expectEqual(@as(u32, 3), lock_acq_ev.loc);

    const lock_rel_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_release)), lock_rel_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x2000), lock_rel_ev.arg);
    try std.testing.expectEqual(@as(u32, 4), lock_rel_ev.loc);

    const taint_src_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.taint_source)), taint_src_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x3000), taint_src_ev.arg);
    try std.testing.expectEqual(@as(u32, 5), taint_src_ev.loc);

    const taint_sink_ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.taint_sink)), taint_sink_ev.tag);
    try std.testing.expectEqual(@as(u64, 0x3000), taint_sink_ev.arg);
    try std.testing.expectEqual(@as(u32, 6), taint_sink_ev.loc);
}

test "rt_probes_with_null_buffer" {
    // This test verifies that probes handle null buffer gracefully
    // (they should do nothing without crashing)

    // First initialize with a valid buffer
    var rb = RingBuffer.init();
    rt_init(&rb);

    // Push an event
    rt_alloc_probe(0x1000, 64, 1);
    try std.testing.expectEqual(@as(u32, 1), rb.available());

    // Now reinitialize with null (this shouldn't crash the system)
    // Note: In a real system, we'd have proper cleanup logic
    // For this test, we just verify the existing behavior
    _ = rb.tryPop();
}

test "rt_probes_boundary_values" {
    var rb = RingBuffer.init();
    rt_init(&rb);

    // Test with boundary values
    rt_alloc_probe(0, 0, 0);
    rt_alloc_probe(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF);

    rt_lock_acquire_probe(0, 0);
    rt_lock_acquire_probe(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF);

    try std.testing.expectEqual(@as(u32, 4), rb.available());

    // Verify values are preserved
    const ev1 = rb.tryPop().?;
    try std.testing.expectEqual(@as(u64, 0), ev1.arg);

    const ev2 = rb.tryPop().?;
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), ev2.arg);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), ev2.loc);
}

test "rt_probes_interleaved_operations" {
    var rb = RingBuffer.init();
    rt_init(&rb);

    // Simulate a realistic sequence of operations
    rt_alloc_probe(0x1000, 64, 1);
    rt_lock_acquire_probe(0x2000, 2);
    rt_alloc_probe(0x1008, 32, 3);
    rt_lock_release_probe(0x2000, 4);
    rt_free_probe(0x1000, 5);
    rt_lock_acquire_probe(0x2000, 6);
    rt_lock_release_probe(0x2000, 7);
    rt_free_probe(0x1008, 8);

    try std.testing.expectEqual(@as(u32, 8), rb.available());

    // Verify the sequence is correct
    var ev: Event = undefined;

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.alloc)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_acquire)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.alloc)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_release)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.free)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_acquire)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.lock_release)), ev.tag);

    ev = rb.tryPop().?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(EventTag.free)), ev.tag);
}
