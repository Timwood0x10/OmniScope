//! main.zig - Zig code calling C via FFI
//!
//! Demonstrates Zig → C FFI boundary crossing.
//! OmniScope should detect:
//! 1. Ownership transfer across Zig/C boundary
//! 2. Dangerous C functions called from Zig
//! 3. Memory management issues

const std = @import("std");

// C function declarations
extern fn c_add(a: c_int, b: c_int) c_int;
extern fn c_multiply(a: c_int, b: c_int) c_int;
extern fn c_alloc(size: usize) ?*anyopaque;
extern fn c_free(ptr: ?*anyopaque) void;
extern fn c_strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn c_free_string(s: ?[*:0]u8) void;
extern fn c_unsafe_copy(dest: [*]u8, src: [*:0]const u8) void;
extern fn c_system_call(cmd: [*:0]const u8) void;

// Safe FFI calls - no memory involved
fn safeFFICalls() void {
    const a: c_int = 10;
    const b: c_int = 20;

    const sum = c_add(a, b); // Line 30: Zig → C FFI boundary
    std.debug.print("c_add(10, 20) = {}\n", .{sum});

    const product = c_multiply(a, b); // Line 33: Zig → C FFI boundary
    std.debug.print("c_multiply(10, 20) = {}\n", .{product});
}

// Ownership transfer across Zig/C boundary
fn ownershipTransfer() void {
    // C allocates, Zig uses, Zig must free with C function
    const size: usize = 1024;
    const ptr = c_alloc(size); // Line 41: C allocates, ownership to Zig
    if (ptr) |p| {
        // Use the memory...
        c_free(p); // Line 44: Zig returns ownership to C
    }

    // String duplication
    const zig_str = "Hello from Zig";
    const c_str = c_strdup(zig_str.ptr); // Line 49: C duplicates, ownership to Zig
    if (c_str) |s| {
        std.debug.print("Duplicated: {s}\n", .{s});
        c_free_string(s); // Line 52: Zig returns ownership
    }
}

// Dangerous FFI calls - intentional vulnerabilities
fn dangerousFFICalls() void {
    // VULNERABILITY: Buffer overflow
    var dest: [10]u8 = undefined;
    const src = "This string is way too long for the buffer";
    c_unsafe_copy(&dest, src.ptr); // Line 61: HIGH risk

    // VULNERABILITY: Command injection
    const cmd = "ls -la";
    c_system_call(cmd.ptr); // Line 65: CRITICAL risk
}

pub fn main() !void {
    std.debug.print("=== Zig → C FFI Demo ===\n", .{});

    safeFFICalls();
    ownershipTransfer();
    dangerousFFICalls();
}
