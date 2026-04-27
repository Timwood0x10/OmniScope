// mach-core - Game Engine Simulation (Simplified for Zig 0.15.2)
// Simulates FFI patterns from game engine with multiple C libraries

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("dlfcn.h");
});

// Platform layer (simulating GLFW/SDL)
extern fn machInit() bool;
extern fn machTerminate() void;
extern fn machCreateWindow(width: c_int, height: c_int, title: [*:0]const u8) ?*MachWindow;
extern fn machDestroyWindow(window: *MachWindow) void;
extern fn machPollEvents() void;
extern fn machShouldClose(window: *MachWindow) bool;

// Audio functions (simulating miniaudio)
extern fn ma_engine_init(pEngine: *ma_engine) c_int;
extern fn ma_engine_uninit(pEngine: *ma_engine) void;
extern fn ma_sound_init_from_file(pEngine: *ma_engine, filePath: [*:0]const u8, pSound: *ma_sound) c_int;
extern fn ma_sound_uninit(pSound: *ma_sound) void;

// Input handling
extern fn machGetKeyState(key: c_int) c_int;
extern fn machGetMousePosition(x: *f64, y: *f64) void;

// Opaque types
const MachWindow = opaque {};
const ma_engine = opaque {};
const ma_sound = opaque {};

// Test 1: Window lifecycle management
export fn runGameLoop() bool {
    if (!machInit()) return false;
    defer machTerminate();

    const window = machCreateWindow(800, 600, "Mach Engine") orelse return false;
    defer machDestroyWindow(window);

    var count: c_int = 0;
    while (!machShouldClose(window) and count < 10) : (count += 1) {
        machPollEvents();
    }

    return true;
}

// Test 2: Audio engine management
export fn initAudio() ?*ma_engine {
    const heap_engine = c.malloc(256); // Fixed size for opaque type
    if (heap_engine == null) return null;

    const result = ma_engine_init(@as(*ma_engine, @ptrCast(heap_engine)));
    if (result != 0) {
        c.free(heap_engine);
        return null;
    }

    return @as(*ma_engine, @ptrCast(heap_engine));
}

export fn cleanupAudio(engine: *ma_engine) void {
    ma_engine_uninit(engine);
    c.free(@as(*anyopaque, @ptrCast(engine)));
}

// Test 3: Sound loading
export fn loadSound(engine: *ma_engine, path: [*:0]const u8) ?*ma_sound {
    const heap_sound = c.malloc(128); // Fixed size for opaque type
    if (heap_sound == null) return null;

    const result = ma_sound_init_from_file(engine, path, @as(*ma_sound, @ptrCast(heap_sound)));
    if (result != 0) {
        c.free(heap_sound);
        return null;
    }

    return @as(*ma_sound, @ptrCast(heap_sound));
}

export fn unloadSound(sound: *ma_sound) void {
    ma_sound_uninit(sound);
    c.free(@as(*anyopaque, @ptrCast(sound)));
}

// Test 4: Dynamic library loading (dlopen/dlsym pattern)
export fn loadPlugin(path: [*:0]const u8) ?*anyopaque {
    return c.dlopen(path, 2); // RTLD_NOW
}

export fn unloadPlugin(handle: *anyopaque) void {
    _ = c.dlclose(handle);
}

export fn getSymbol(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque {
    return c.dlsym(handle, symbol);
}

// Test 5: Input state handling
var mouse_x: f64 = 0.0;
var mouse_y: f64 = 0.0;

export fn captureInput() void {
    machGetMousePosition(&mouse_x, &mouse_y);
}

export fn getKey(key: c_int) c_int {
    return machGetKeyState(key);
}

// Test 6: String operations across FFI
var title_buffer: [256]u8 = undefined;

export fn setGameTitle(title: [*:0]const u8) void {
    _ = c.strcpy(&title_buffer, title);
}

export fn getGameTitle() [*]u8 {
    return &title_buffer;
}

// Test 7: Memory allocation patterns
export fn allocateEntity() ?*Entity {
    const entity = c.malloc(@sizeOf(Entity));
    if (entity == null) return null;

    _ = c.memset(entity, 0, @sizeOf(Entity));
    return @as(*Entity, @alignCast(@ptrCast(entity)));
}

export fn destroyEntity(entity: *Entity) void {
    c.free(@as(*anyopaque, @ptrCast(entity)));
}

const Entity = extern struct { id: c_int, x: f32, y: f32 };

pub fn main() void {
    _ = runGameLoop();

    const audio = initAudio();
    if (audio != null) {
        cleanupAudio(audio.?);
    }
}
