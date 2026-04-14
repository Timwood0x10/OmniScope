//! Logging System
//!
//! Provides structured logging with multiple levels and output formats.
//! Thread-safe logging using a global writer.
//!
//! Log Levels:
//!   - debug: Detailed information for debugging
//!   - info: General informational messages
//!   - warn: Warning messages
//!   - err: Error messages
//!
//! Usage:
//!   const log = @import("log.zig");
//!   log.info("Loading IR file: {s}", .{path});
//!   log.err("Failed to load: {}", .{error});

const std = @import("std");
const builtin = @import("builtin");

pub const LogLevel = enum(u3) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

pub const Config = struct {
    level: LogLevel = .info,
    enable_colors: bool = true,
    enable_timestamps: bool = true,
    enable_module_prefix: bool = true,
};

var global_config: Config = .{};
var global_writer: ?std.io.AnyWriter = null;
var global_allocator: ?std.mem.Allocator = null;

pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config: Config) void {
    global_allocator = allocator;
    global_writer = writer;
    global_config = config;
}

pub fn deinit() void {
    global_writer = null;
    global_allocator = null;
}

fn getLevelPrefix(level: LogLevel) []const u8 {
    return switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARN",
        .err => "ERROR",
    };
}

fn getLevelColor(level: LogLevel) []const u8 {
    if (!global_config.enable_colors) return "";
    return switch (level) {
        .debug => "\x1b[90m",
        .info => "\x1b[36m",
        .warn => "\x1b[33m",
        .err => "\x1b[31m",
    };
}

const RESET_COLOR = "\x1b[0m";

fn shouldLog(level: LogLevel) bool {
    return @intFromEnum(level) >= @intFromEnum(global_config.level);
}

fn logInternal(
    level: LogLevel,
    comptime module: []const u8,
    comptime format: []const u8,
    args: anytype,
) void {
    if (!shouldLog(level)) return;

    const writer = global_writer orelse return;

    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var msg = std.ArrayList(u8).init(allocator);
    errdefer msg.deinit();

    if (global_config.enable_colors) {
        try msg.appendSlice(getLevelColor(level));
    }

    if (global_config.enable_timestamps) {
        const timestamp = std.time.timestamp();
        try msg.writer().print("[{d}] ", .{timestamp});
    }

    try msg.writer().print("[{s}] ", .{getLevelPrefix(level)});

    if (global_config.enable_module_prefix) {
        try msg.writer().print("[{s}] ", .{module});
    }

    try msg.writer().print(format, args);

    if (global_config.enable_colors) {
        try msg.appendSlice(RESET_COLOR);
    }

    try msg.append('\n');

    writer.writeAll(msg.items) catch return;
}

pub fn debug(comptime module: []const u8, comptime format: []const u8, args: anytype) void {
    logInternal(.debug, module, format, args);
}

pub fn info(comptime module: []const u8, comptime format: []const u8, args: anytype) void {
    logInternal(.info, module, format, args);
}

pub fn warn(comptime module: []const u8, comptime format: []const u8, args: anytype) void {
    logInternal(.warn, module, format, args);
}

pub fn err(comptime module: []const u8, comptime format: []const u8, args: anytype) void {
    logInternal(.err, module, format, args);
}

pub fn setLevel(level: LogLevel) void {
    global_config.level = level;
}

pub fn getLevel() LogLevel {
    return global_config.level;
}

test "LogLevel - ordering" {
    try std.testing.expect(@intFromEnum(LogLevel.debug) < @intFromEnum(LogLevel.info));
    try std.testing.expect(@intFromEnum(LogLevel.info) < @intFromEnum(LogLevel.warn));
    try std.testing.expect(@intFromEnum(LogLevel.warn) < @intFromEnum(LogLevel.err));
}

test "Log - getLevelPrefix" {
    try std.testing.expectEqualStrings("DEBUG", getLevelPrefix(.debug));
    try std.testing.expectEqualStrings("INFO", getLevelPrefix(.info));
    try std.testing.expectEqualStrings("WARN", getLevelPrefix(.warn));
    try std.testing.expectEqualStrings("ERROR", getLevelPrefix(.err));
}

test "Log - shouldLog" {
    global_config.level = .info;
    try std.testing.expect(!shouldLog(.debug));
    try std.testing.expect(shouldLog(.info));
    try std.testing.expect(shouldLog(.warn));
    try std.testing.expect(shouldLog(.err));

    global_config.level = .err;
    try std.testing.expect(!shouldLog(.debug));
    try std.testing.expect(!shouldLog(.info));
    try std.testing.expect(!shouldLog(.warn));
    try std.testing.expect(shouldLog(.err));
}
