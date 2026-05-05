//! OmniScope v0.1.7 — Zig FFI Detection Test Cases
//!
//! Target: A4 — zig_*/__zig_*/c.* / @cImport detection
//! Target: E2-2 — alias closure severity boost at FFI boundary
//!
//! Intentional bugs: 7, Control cases: 3

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
});

// Simulated Zig runtime FFI bridges (these are real patterns in compiled Zig)
extern fn zig_write(fd: c_int, buf: [*]const u8, len: usize) isize;
extern fn zig_alloc(size: usize) ?*anyopaque;
extern fn zig_free(ptr: *anyopaque) void;
extern fn zig_c_memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;

// Simulated compiler-generated glue functions
extern fn __zig_c_allocator(size: usize) ?*anyopaque;
extern fn __zig_c_dealloc(ptr: *anyopaque) void;
extern fn __zig_panic_handler(msg: [*:0]const u8) noreturn;

// Simulated C library functions called through @cImport
extern fn c_process_data(buf: [*]u8, len: c_int) c_int;
extern fn c_register_callback(cb: ?*const fn ([*]u8, c_int) void) void;

// ================================================================
// BUG-ZIG-01: zig_alloc without zig_free — memory leak at FFI bridge
//
// zig_alloc is a Zig runtime function that allocates C-compatible memory.
// If we allocate with it but free with c.free() instead of zig_free(),
// that's a cross-language allocator mismatch.
// ================================================================

pub export fn bugZig01_ZigAllocLeak() void {
    const ptr = zig_alloc(1024); // Zig runtime FFI bridge allocation
    if (ptr) |p| {
        _ = c_process_data(@ptrCast(p), 1024);
        // BUG: never freed — leak through zig_alloc bridge
        // Also: if freed with c.free(p), that's a mismatch
    }
}

// ================================================================
// BUG-ZIG-02: c.malloc + zig_free — allocator mismatch
//
// Allocate with C's malloc (via @cImport as c.malloc),
// then try to free with Zig's runtime deallocator.
// The allocators are incompatible — this is a use-after-free risk.
// ================================================================

pub export fn bugZig02_CMallocZigFreeMismatch() void {
    const ptr = c.malloc(256); // C allocator
    if (ptr != null) {
        _ = c_process_data(@ptrCast(ptr), 256);
        zig_free(ptr.?); // BUG: freeing C memory with Zig's deallocator!
        // After this, C's internal bookkeeping is corrupted
    }
}

// ================================================================
// BUG-ZIG-03: __zig_c_allocator result escapes to global — UAF
//
// __zig_c_allocator is a compiler-generated glue function for
// allocating C-compatible memory from Zig's arena allocator.
// Storing its result globally and accessing later creates UAF risk
// when the arena scope ends.
// ================================================================

var g_zig_ptr: ?[*]u8 = null;

pub export fn bugZig03_ZigGlueGlobalEscape() void {
    g_zig_ptr = @ptrCast(__zig_c_allocator(512));
    _ = c_process_data(g_zig_ptr.?, 512);
}

pub export fn bugZig03_UseAfterArenaEnd() u8 {
    // If the arena that backed __zig_c_allocator was already destroyed,
    // this pointer is dangling. But OmniScope should detect that
    // g_zig_ptr reaches FFI boundary (c_process_data) → severity boost
    return g_zig_ptr.?[0]; // Potential UAF
}

// ================================================================
// BUG-ZIG-04: Stack address passed to c.printf — format string injection
//
// c.printf is an @cImport wrapper. Passing user-controlled data
// to it as format string is a classic vulnerability.
// ================================================================

pub export fn bugZig04_FormatStringInjection(user_input: [*:0]const u8) void {
    // BUG: user_input used as format string in c.printf
    _ = c.printf(user_input); // Format string vuln at FFI boundary
}

// ================================================================
// BUG-ZIG-05: Callback registration with stack-captured pointer
//
// Registering a callback that captures a local variable's address.
// When the callback fires asynchronously, the stack frame may be gone.
// E2-2c: This indirect escape through alias closure should boost severity.
// ================================================================

var g_callback_fn: ?*const fn () void = null;

fn onCallbackFires(data: [*]u8, len: c_int) void {
    _ = len;
    // This fires after bugZig05 returns — data is on dead stack
    _ = c_printf_debug(data[0]); // UAF via callback
}
extern fn c_printf_debug(val: u8) void;

pub export fn bugZig05_CallbackStackEscape() void {
    var secret: [16]u8 = .{0xDE} ** 16; // Stack variable
    _ = &secret;
    c_register_callback(@ptrCast(&onCallbackFires)); // Indirect escape path
    // When callback fires: secret is out of scope → UAF
}

// ================================================================
// BUG-ZIG-06: Double-free via zig_free + c.free on same pointer
//
// Same pointer freed twice through different deallocators.
// E2-2a/b: Should detect alias closure reaching FFI → .critical severity
// ================================================================

pub export fn bugZig06_DoubleFreeCrossDealloc() void {
    const ptr = c.malloc(128);
    if (ptr != null) {
        _ = c_process_data(@ptrCast(ptr), 128);

        zig_free(ptr.?); // First free (via Zig bridge)

        // ... complex branching logic ...

        c.free(ptr); // BUG: double free! Different deallocators, same pointer
    }
}

// ================================================================
// BUG-ZIG-07: __export_main receives heap pointer — escape chain
//
// __export_* symbols are Zig-exported functions visible to C loaders.
// Receiving a heap pointer through one and storing it globally
// creates an escape chain that crosses the FFI boundary.
// ================================================================

var g_exported_payload: ?[*]u8 = null;

pub export fn __export_receivePayload(data: [*]u8, len: usize) void {
    _ = len; // Length info stored for bounds checking
    g_exported_payload = data; // Store incoming FFI pointer
    // E2-2d: markFfiRelevant feedback loop should tag this ptr
}

pub export fn __export_usePayload() i32 {
    if (g_exported_payload) |p| {
        // Read from potentially-freed foreign memory
        return @as(i32, @bitCast(p[0..4].*)); // Potential UAF
    }
    return -1;
}

// ================================================================
// CONTROL-ZIG-01: Correct zig_alloc + zig_free pattern
// ================================================================

pub export fn controlZig01_CorrectZigAllocFree() void {
    const ptr = zig_alloc(64);
    if (ptr) |p| {
        _ = c_process_data(@ptrCast(p), 64);
        zig_free(p); // Correct: matched pair
    }
}

// ================================================================
// CONTROL-ZIG-02: Correct c.malloc + c.free pattern
// ================================================================

pub export fn controlZig02_CorrectCMallocFree() void {
    const ptr = c.malloc(128);
    if (ptr != null) {
        _ = c_process_data(@ptrCast(ptr), 128);
        c.free(ptr); // Correct: matched pair
    }
}

// ================================================================
// CONTROL-ZIG-03: No FFI interaction — pure Zig (should be silent)
// ================================================================

pub export fn controlZig03_PureZigNoFFI() void {
    var buf: [32]u8 = undefined;
    const src = "hello world";
    @memcpy(buf[0..src.len], src);
    _ = buf[0]; // Pure Zig, no FFI — no issues expected
}

// ================================================================
// Main entry
// ================================================================

pub fn main() void {
    bugZig01_ZigAllocLeak();
    bugZig02_CMallocZigFreeMismatch();
    bugZig03_ZigGlueGlobalEscape();
    _ = bugZig03_UseAfterArenaEnd();
    bugZig04_FormatStringInjection("test %s %x %n");
    bugZig05_CallbackStackEscape();
    bugZig06_DoubleFreeCrossDealloc();

    controlZig01_CorrectZigAllocFree();
    controlZig02_CorrectCMallocFree();
    controlZig03_PureZigNoFFI();
}
