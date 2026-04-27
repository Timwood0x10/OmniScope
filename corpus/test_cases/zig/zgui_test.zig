// zgui - GUI Library Simulation (Simplified for Zig 0.15.2)
// Simulates FFI patterns from Dear ImGui + OpenGL

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
});

extern fn glGenBuffers(n: c_int, buffers: *c_uint) void;
extern fn glDeleteBuffers(n: c_int, buffers: *const c_uint) void;
extern fn glBindBuffer(target: c_uint, buffer: c_uint) void;
extern fn glBufferData(target: c_uint, size: isize, data: ?*const anyopaque, usage: c_uint) void;
extern fn glVertexAttribPointer(index: c_int, size: c_int, type_: c_uint, normalized: c_int, stride: c_int, pointer: ?*const anyopaque) void;
extern fn glEnableVertexAttribArray(index: c_int) void;

extern fn igCreateContext() ?*ImGuiContext;
extern fn igDestroyContext(ctx: *ImGuiContext) void;
extern fn igNewFrame() void;
extern fn igEndFrame() void;
extern fn igBegin(name: [*:0]const u8, p_open: ?*bool, flags: u32) bool;
extern fn igEnd() void;
extern fn igText(fmt: [*:0]const u8, ...) void;
extern fn igButton(label: [*:0]const u8) bool;

const ImGuiContext = opaque {};

const GL_ARRAY_BUFFER: c_uint = 0x8892;
const STATIC_DRAW: c_uint = 0x88E4;

// Test 1: OpenGL buffer management
export fn createVertexBuffer(data: [*]const f32, count: usize) c_uint {
    var vbo: c_uint = undefined;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    const size = @as(isize, @intCast(count * @sizeOf(f32)));
    glBufferData(GL_ARRAY_BUFFER, size, data, STATIC_DRAW);

    return vbo;
}

export fn destroyVertexBuffer(vbo: c_uint) void {
    const vbo_ptr = &vbo;
    glDeleteBuffers(1, vbo_ptr);
}

// Test 2: ImGui context management
export fn initGUI() ?*ImGuiContext {
    return igCreateContext();
}

export fn cleanupGUI(ctx: *ImGuiContext) void {
    igDestroyContext(ctx);
}

// Test 3: GUI rendering loop
export fn renderGUI() void {
    const ctx = igCreateContext();
    if (ctx == null) return;
    const ctx_nonnull = ctx.?;
    defer igDestroyContext(ctx_nonnull);

    igNewFrame();
    defer igEndFrame();

    if (igBegin("Test Window", null, 0)) {
        defer igEnd();

        igText("Hello from Zig!");
        _ = igButton("Click Me");
    }
}

// Test 4: Vertex setup with FFI calls
export fn setupMesh(vertices: [*]const f32, count: usize) void {
    const vbo = createVertexBuffer(vertices, count);
    defer destroyVertexBuffer(vbo);

    glVertexAttribPointer(0, 3, 5126, 0, 12, null);
    glEnableVertexAttribArray(0);
}

// Test 5: String handling across FFI boundary
var window_title: [256]u8 = undefined;

export fn setWindowTitle(title: [*:0]const u8) void {
    _ = c.strcpy(&window_title, title);
}

pub fn main() void {
    renderGUI();

    const vertices = [_]f32{ 0.0, 0.5, 0.0, 0.5, -0.5, 0.0 };
    setupMesh(&vertices, 6);
}
