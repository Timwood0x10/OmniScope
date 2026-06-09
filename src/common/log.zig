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

/// Log info message (only if level >= normal)
/// Uses comptime-level check to avoid function call overhead when disabled
pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.info("[INFO] " ++ fmt ++ "\n", args);
    }
}

/// Log debug message (only if level == debug)
/// Note: In release builds, this branch is typically optimized out entirely
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level == .debug) {
        std.log.debug("[DEBUG] " ++ fmt ++ "\n", args);
    }
}

/// Log warning message
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.warn("[WARN] " ++ fmt ++ "\n", args);
    }
}

/// Log error message (always emitted)
pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.log.err("[ERROR] " ++ fmt ++ "\n", args);
}

/// Print generic message
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (current_log_level != .quiet) {
        std.log.info(fmt, args);
    }
}
