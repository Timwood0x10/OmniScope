//! Go Language Zone Classification
//!
//! Classifies Go functions into safe/unsafe/ffi/runtime_internal zones.
//! Handles Go runtime internals (GC, scheduler, channels, etc.), cgo,
//! and unsafe.Pointer patterns.

const std = @import("std");

const zone_types = @import("../types/zone_types.zig");
const ZoneKind = zone_types.ZoneKind;
pub const GO_SAFE_PATTERNS = zone_types.GO_SAFE_PATTERNS;
pub const GO_ESCAPE_PATTERNS = zone_types.GO_ESCAPE_PATTERNS;

/// Classify a Go function.
pub fn classifyGoFunction(func_name: []const u8) ZoneKind {
    if (isGoRuntimeInternal(func_name)) {
        return .runtime_internal;
    }

    for (GO_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (GO_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "C.") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Check if function is a Go runtime internal function.
pub fn isGoRuntimeInternal(func_name: []const u8) bool {
    if (!std.mem.startsWith(u8, func_name, "runtime.")) return false;

    const rest = func_name["runtime.".len..];

    if (std.mem.startsWith(u8, rest, "gc") or
        std.mem.startsWith(u8, rest, "mallocgc") or
        std.mem.startsWith(u8, rest, "scanobject") or
        std.mem.startsWith(u8, rest, "markroot") or
        std.mem.startsWith(u8, rest, "sweep") or
        std.mem.startsWith(u8, rest, "scanstack"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "schedule") or
        std.mem.startsWith(u8, rest, "park") or
        std.mem.startsWith(u8, rest, "wake") or
        std.mem.startsWith(u8, rest, "stopm") or
        std.mem.startsWith(u8, rest, "startm") or
        std.mem.startsWith(u8, rest, "handoffp"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "chan") or
        std.mem.startsWith(u8, rest, "select"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "interface") or
        std.mem.startsWith(u8, rest, "assertI2I") or
        std.mem.startsWith(u8, rest, "assertE2I") or
        std.mem.startsWith(u8, rest, "convI2E"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "mapaccess") or
        std.mem.startsWith(u8, rest, "mapassign") or
        std.mem.startsWith(u8, rest, "mapdelete") or
        std.mem.startsWith(u8, rest, "mapiter"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "newproc") or
        std.mem.startsWith(u8, rest, "goexit") or
        std.mem.startsWith(u8, rest, "systemstack") or
        std.mem.startsWith(u8, rest, "morestack") or
        std.mem.startsWith(u8, rest, "lessstack"))
    {
        return true;
    }

    if (std.mem.startsWith(u8, rest, "defer")) {
        return true;
    }

    return false;
}

test "Go runtime internal symbols are classified as .runtime_internal" {
    const gc_symbols = [_][]const u8{
        "runtime.gcStart",
        "runtime.gcDrain",
        "runtime.mallocgc",
        "runtime.scanobject",
        "runtime.markroot",
        "runtime.sweep",
        "runtime.scanstack",
    };

    for (gc_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const scheduler_symbols = [_][]const u8{
        "runtime.schedule",
        "runtime.park0",
        "runtime.wakep",
        "runtime.stopm",
        "runtime.startm",
        "runtime.handoffp",
    };

    for (scheduler_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const channel_symbols = [_][]const u8{
        "runtime.chansend1",
        "runtime.chanrecv1",
        "runtime.chanclose",
        "runtime.selectgo",
        "runtime.selectnbrecv",
    };

    for (channel_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const interface_symbols = [_][]const u8{
        "runtime.interface",
        "runtime.assertI2I",
        "runtime.assertI2I2",
        "runtime.assertE2I",
        "runtime.convI2E",
    };

    for (interface_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const map_symbols = [_][]const u8{
        "runtime.mapaccess1",
        "runtime.mapaccess2",
        "runtime.mapassign",
        "runtime.mapdelete",
        "runtime.mapiterinit",
        "runtime.mapiternext",
    };

    for (map_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const goroutine_symbols = [_][]const u8{
        "runtime.newproc",
        "runtime.newproc1",
        "runtime.goexit",
        "runtime.systemstack",
        "runtime.morestack",
        "runtime.lessstack",
    };

    for (goroutine_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }

    const defer_symbols = [_][]const u8{
        "runtime.deferproc",
        "runtime.deferreturn",
        "runtime.deferprocStack",
    };

    for (defer_symbols) |sym| {
        try std.testing.expectEqual(ZoneKind.runtime_internal, classifyGoFunction(sym));
    }
}

test "Non-Go runtime symbols not falsely classified" {
    const non_go_runtime = [_][]const u8{
        "main.main",
        "my_package.func",
        "runtime_custom",
        "_ZN4core3ptr",
        "std::vector",
    };

    for (non_go_runtime) |sym| {
        const result = isGoRuntimeInternal(sym);
        try std.testing.expect(!result);
    }
}
