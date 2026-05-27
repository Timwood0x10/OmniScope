//! Zig Language Zone Classification
//!
//! Classifies Zig functions into safe/unsafe/ffi zones.
//! Handles Zig builtins (@ptrCast, @intToPtr, etc.) and stdlib patterns.

const std = @import("std");

const zone_types = @import("../types/zone_types.zig");
const ZoneKind = zone_types.ZoneKind;
pub const ZIG_SAFE_PATTERNS = zone_types.ZIG_SAFE_PATTERNS;
pub const ZIG_ESCAPE_PATTERNS = zone_types.ZIG_ESCAPE_PATTERNS;

/// Classify a Zig function.
pub fn classifyZigFunction(func_name: []const u8) ZoneKind {
    for (ZIG_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (ZIG_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    return .unknown;
}
