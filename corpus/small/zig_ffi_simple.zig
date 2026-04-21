// Zig FFI Simple Test
// Tests real Zig→C FFI patterns for unsafe boundary analysis
//
// Expected Issues: 3
// - Zig allocator, C free (cross-language mismatch)
// - Allocator leak (no corresponding free)
// - Pointer escape across FFI boundary

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

extern fn c_process_string(ptr: [*]u8) void;
extern fn c_free_string(ptr: [*]u8) void;

// Test 1: Zig allocator, C free - cross-language mismatch
export fn zig_alloc_c_free() void {
    const allocator = std.heap.page_allocator;
    const ptr = allocator.alloc(u8, 100) catch return;
    // Leak: Zig allocator, but C might try to free it
    c_process_string(ptr.ptr);
    // If C calls free() on this, it's a mismatch
}

// Test 2: Allocator leak - no corresponding free
export fn allocator_leak() void {
    const allocator = std.heap.page_allocator;
    _ = allocator.alloc(u8, 100) catch return;
    // Leak: never freed
}

// Test 3: Pointer escape across FFI boundary
export fn pointer_escape() [*]u8 {
    const allocator = std.heap.page_allocator;
    const ptr = allocator.alloc(u8, 100) catch return null;
    // Escape: pointer passed to C, ownership unclear
    return ptr.ptr;
}

// Test 4: Correct pattern - Zig alloc, Zig free
export fn correct_zig_alloc_free() void {
    const allocator = std.heap.page_allocator;
    const ptr = allocator.alloc(u8, 100) catch return;
    allocator.free(ptr);
}

// Test 5: Correct pattern - C alloc, C free
export fn correct_c_alloc_free() void {
    const ptr = c.malloc(100);
    if (ptr != null) {
        c.free(ptr);
    }
}

pub fn main() void {
    zig_alloc_c_free();
    allocator_leak();
    _ = pointer_escape();
    correct_zig_alloc_free();
    correct_c_alloc_free();
}
