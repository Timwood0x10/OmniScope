//! OmniScope Red Team — Zig FFI Boundary Bug Test Cases
//!
//! Simulates bugs that occur at Zig ↔ C FFI boundaries.
//! Based on patterns from ZIG_IR_SPEC.md:
//!   - Allocator misuse (vtable-based)
//!   - @extern symbol resolution errors
//!   - Comptime safety bypass
//!   - Slice safety violations
//!   - Error handling across FFI

const std = @import("std");

// ================================================================
// FFI declarations — C functions Zig calls
// ================================================================

extern fn c_ffi_alloc(size: usize) ?*anyopaque;
extern fn c_ffi_free(ptr: ?*anyopaque) void;
extern fn c_ffi_process(buf: [*]u8, len: usize) c_int;
extern fn c_ffi_get_string() ?[*:0]const u8;

// ================================================================
// ZIG-BUG-01: C pointer used after C frees it
//
// Zig receives a pointer from C, stores it, then C frees the
// memory. Zig tries to use it afterward.
//
// Expected: use_after_free (CWE-416)
// ================================================================

var g_stored_c_ptr: ?*anyopaque = null;

fn zig_bug_01_c_ptr_uaf() void {
    const ptr = c_ffi_alloc(128) orelse return;
    g_stored_c_ptr = ptr;

    // C frees the memory
    c_ffi_free(ptr);

    // [BUG] Use after C freed it
    const data: [*]u8 = @ptrCast(g_stored_c_ptr);
    _ = c_ffi_process(data, 10); // UAF
}

// ================================================================
// ZIG-BUG-02: Slice from C with incorrect length
//
// Zig creates a slice from a C pointer but uses wrong length.
// Accessing beyond the actual allocation is buffer overflow.
//
// Expected: buffer_overflow (CWE-120)
// ================================================================

fn zig_bug_02_wrong_length() void {
    const ptr = c_ffi_alloc(32) orelse return;

    // [BUG] C allocated 32 bytes, but Zig claims it's 256
    const buf: [*]u8 = @ptrCast(ptr);
    const slice = buf[0..256]; // Buffer overflow: only 32 bytes allocated

    // This writes beyond the allocation
    for (slice, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    c_ffi_free(ptr);
}

// ================================================================
// ZIG-BUG-03: Sentinel mismatch from C string
//
// Zig expects a sentinel-terminated string from C, but the C
 * function returns a non-sentinel buffer or wrong sentinel.
//
// Expected: buffer_overflow / null_dereference
// ================================================================

fn zig_bug_03_sentinel_mismatch() void {
    const c_str = c_ffi_get_string() orelse return;

    // [BUG] Assumes null terminator exists within reasonable distance
    // If C returns unterminated buffer, strlen goes out of bounds
    const len = std.mem.len(c_str);
    std.debug.print("ZIG-BUG-03: len={}\n", .{len});

    // Create slice assuming null terminator
    const slice = std.mem.span(c_str);
    _ = slice;
}

// ================================================================
// ZIG-BUG-04: Allocator vtable misuse — free with wrong allocator
//
// Zig uses vtable-based allocators. Freeing memory with a
// different allocator than the one that allocated it causes UB.
//
// Expected: cross_language_free (CWE-763)
// ================================================================

fn zig_bug_04_wrong_allocator() void {
    // Allocate with C allocator
    const c_ptr = c_ffi_alloc(64) orelse return;

    // [BUG] Try to free with Zig page allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const zig_alloc = gpa.allocator();

    // This would crash or corrupt heap — different allocator
    const buf: []u8 = @ptrCast(@alignCast(c_ptr));
    zig_alloc.free(buf); // Wrong allocator!
}

// ================================================================
// ZIG-BUG-05: Error return from C not checked
//
// C function returns error code. Zig code ignores it and
// proceeds with potentially invalid data.
//
// Expected: null_dereference / use_after_free
// ================================================================

fn zig_bug_05_unchecked_c_error() void {
    var buf: [256]u8 = undefined;

    const result = c_ffi_process(&buf, 256);

    // [BUG] Not checking error code
    // If result < 0, buf may contain garbage or be uninitialized
    const data = buf[0..@intCast(result)]; // Negative result → wrong slice
    _ = data;
}

// ================================================================
// ZIG-BUG-06: Comptime safety bypass — @intCast overflow
//
// Comptime-known values bypass runtime checks. If a value
// comes from C (runtime), @intCast can overflow.
//
// Expected: integer_overflow
// ================================================================

fn zig_bug_06_intcast_overflow() void {
    const c_value: c_int = c_ffi_process(undefined, 0);

    // [BUG] @intCast will trap if c_value doesn't fit in u8
    // C might return -1 or 256+
    const byte: u8 = @intCast(c_value); // Potential trap
    _ = byte;
}

// ================================================================
// ZIG-BUG-07: @ptrCast from integer without alignment check
//
// C returns an integer that's used as a pointer (handle pattern).
// Zig @ptrCast doesn't check alignment.
//
// Expected: alignment_violation
// ================================================================

fn zig_bug_07_alignment() void {
    // Simulate C returning a misaligned handle
    const handle: usize = 7; // Not aligned to any reasonable boundary

    // [BUG] @ptrCast from misaligned integer
    const ptr: *u32 = @ptrFromInt(handle);
    _ = ptr;
    // Dereferencing would be UB due to alignment
}

// ================================================================
// ZIG-BUG-08: Sentinel-terminated slice from non-sentinel memory
//
// Zig assumes sentinel-terminated data from C, but the buffer
// doesn't contain the sentinel.
//
// Expected: buffer_overflow
// ================================================================

fn zig_bug_08_no_sentinel() void {
    const ptr = c_ffi_alloc(16) orelse return;
    const buf: [*]u8 = @ptrCast(ptr);

    // Fill all 16 bytes — no room for null sentinel
    for (0..16) |i| {
        buf[i] = @intCast(i + 1); // No zero byte
    }

    // [BUG] Assumes sentinel exists, will scan past allocation
    const sentinel_slice: [*:0]u8 = @ptrCast(buf);
    const len = std.mem.len(sentinel_slice); // Scans past 16 bytes

    std.debug.print("ZIG-BUG-08: len={}\n", .{len});
    c_ffi_free(ptr);
}

// ================================================================
// Entry point
// ================================================================

pub fn main() void {
    zig_bug_01_c_ptr_uaf();
    zig_bug_02_wrong_length();
    zig_bug_03_sentinel_mismatch();
    zig_bug_04_wrong_allocator();
    zig_bug_05_unchecked_c_error();
    zig_bug_06_intcast_overflow();
    zig_bug_07_alignment();
    zig_bug_08_no_sentinel();
}
