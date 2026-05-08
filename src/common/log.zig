const std = @import("std");

pub const LogLevel = enum {
    quiet,
    normal,
    verbose,
    debug,
};

pub var current_log_level: LogLevel = .normal;

pub fn setLogLevel(level: LogLevel) void {
    current_log_level = level;
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.info("[INFO] " ++ fmt ++ "\n", args);
    }
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level == .debug) {
        std.log.info("[DEBUG] " ++ fmt ++ "\n", args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.info("[WARN] " ++ fmt ++ "\n", args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.log.info("[ERROR] " ++ fmt ++ "\n", args);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.info(fmt, args);
    }
}
