// zig-v Video Processing Library Simulation (Simplified for Zig 0.15.2)
// Simulates FFI patterns from video processing library

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

extern fn av_malloc(size: usize) ?*anyopaque;
extern fn av_free(ptr: *anyopaque) void;
extern fn av_frame_alloc() ?*AVFrame;
extern fn av_frame_free(frame: **AVFrame) void;

const AVFrame = opaque {};

// Test 1: Video frame allocation
export fn processVideoFrame() void {
    var frame = av_frame_alloc();
    if (frame != null) {
        av_frame_free(@as(**AVFrame, @ptrCast(&frame)));
    }
}

// Test 2: Buffer conversion
export fn convertPixelFormat(src: [*]const u8, src_size: usize, dst: [*]u8, dst_size: usize) c_int {
    if (src_size > dst_size) {
        _ = c.memcpy(dst, src, dst_size);
        return 1;
    }
    _ = c.memcpy(dst, src, src_size);
    return 0;
}

// Test 3: Memory allocation via C
export fn createBuffer(size: usize) ?*anyopaque {
    return c.malloc(size);
}

export fn destroyBuffer(buf: *anyopaque) void {
    c.free(buf);
}

// Test 4: Format string usage
export fn logVideoInfo(fmt: [*:0]const u8) void {
    _ = fmt;
    // Would call printf-like function
}

// Test 5: Correct pattern - proper resource management
export fn correctVideoProcessing() void {
    const buf = c.malloc(1024);
    if (buf != null) {
        _ = c.memset(buf, 0, 1024);
        c.free(buf);
    }
}

pub fn main() void {
    processVideoFrame();
    correctVideoProcessing();
}
