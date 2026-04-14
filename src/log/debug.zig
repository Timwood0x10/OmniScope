//! Debug System
//!
//! Provides debug utilities including assertions, panics with context,
//! and conditional debug code execution.
//!
//! Usage:
//!   const dbg = @import("debug.zig");
//!   dbg.assert(condition, "Expected condition to be true");
//!   dbg.assertFn(func() == expected, "Function should return expected value");

const std = @import("std");
const log = @import("log.zig");

pub const EnableDebug = @import("builtin").mode != .ReleaseFast;

pub const Config = struct {
    enable_asserts: bool = true,
    enable_panics: bool = true,
    enable_stack_trace: bool = true,
    enable_source_context: bool = true,
};

var global_config: Config = .{};

pub fn init(config: Config) void {
    global_config = config;
}

pub fn deinit() void {
    global_config.enable_asserts = true;
    global_config.enable_panics = true;
    global_config.enable_stack_trace = true;
    global_config.enable_source_context = true;
}

pub fn assert(condition: bool, comptime message: []const u8) void {
    if (!EnableDebug) return;
    if (!global_config.enable_asserts) return;
    if (condition) return;

    if (global_config.enable_source_context) {
        log.err("assert", "{s}", .{message});
        if (global_config.enable_stack_trace) {
            std.debug.dumpCurrentStackTrace(null);
        }
    }

    @panic(message);
}

pub fn assertWithContext(
    condition: bool,
    comptime message: []const u8,
    comptime file: []const u8,
    comptime line: u32,
    comptime col: u32,
) void {
    if (!EnableDebug) return;
    if (!global_config.enable_asserts) return;
    if (condition) return;

    var buffer: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buffer, "{s} at {s}:{d}:{d}", .{
        message, file, line, col,
    }) catch "assertion failed";

    if (global_config.enable_source_context) {
        log.err("assert", "{s}", .{msg});
        if (global_config.enable_stack_trace) {
            std.debug.dumpCurrentStackTrace(null);
        }
    }

    @panic(msg);
}

pub fn panicWithContext(
    comptime message: []const u8,
    comptime file: []const u8,
    comptime line: u32,
    comptime col: u32,
) noreturn {
    if (global_config.enable_panics) {
        var buffer: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, "{s} at {s}:{d}:{d}", .{
            message, file, line, col,
        }) catch message;

        if (global_config.enable_source_context) {
            log.err("panic", "{s}", .{msg});
            if (global_config.enable_stack_trace) {
                std.debug.dumpCurrentStackTrace(null);
            }
        }

        @panic(msg);
    }

    @panic(message);
}

pub fn unreachableWithContext(
    comptime message: []const u8,
    comptime file: []const u8,
    comptime line: u32,
    comptime col: u32,
) noreturn {
    panicWithContext("unreachable: " ++ message, file, line, col);
}

pub fn debugAssert(comptime condition: bool, comptime message: []const u8) void {
    if (comptime !condition) {
        @panic(message);
    }
}

pub fn debugPanic(comptime message: []const u8) noreturn {
    @panic(message);
}

pub fn notImplemented(comptime feature: []const u8) noreturn {
    @panic("not implemented: " ++ feature);
}

pub fn todo(comptime feature: []const u8) noreturn {
    @panic("TODO: " ++ feature);
}

pub fn setEnableAsserts(enable: bool) void {
    global_config.enable_asserts = enable;
}

pub fn setEnablePanics(enable: bool) void {
    global_config.enable_panics = enable;
}

test "Debug - assert passes on true" {
    const config = Config{ .enable_asserts = true, .enable_panics = false, .enable_stack_trace = false, .enable_source_context = false };
    init(config);
    defer deinit();

    assert(true, "This should not fail");
}

test "Debug - debugAssert compiles with true" {
    comptime debugAssert(true, "comptime check");
}
