//! Rust Language Zone Classification
//!
//! Classifies Rust functions into safe/unsafe/ffi/runtime_internal zones.
//! Handles Rust mangled names (_ZN*, _R*), compiler intrinsics (__rust_*),
//! and demangled patterns (std::, core::).

const std = @import("std");

const zone_types = @import("../types/zone_types.zig");
const ZoneKind = zone_types.ZoneKind;
pub const RUST_SAFE_PATTERNS = zone_types.RUST_SAFE_PATTERNS;
pub const RUST_ESCAPE_PATTERNS = zone_types.RUST_ESCAPE_PATTERNS;

/// Classify a Rust function.
pub fn classifyRustFunction(func_name: []const u8) ZoneKind {
    const rust_allocator_patterns = [_][]const u8{
        "__rust_dealloc", "__rust_alloc", "__rust_realloc", "__rust_alloc_zeroed",
        "__rdl_dealloc",  "__rdl_alloc",  "__rdl_realloc",  "__rg_dealloc",
        "__rg_alloc",     "__rg_realloc",
    };
    for (rust_allocator_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .runtime_internal;
        }
    }

    for (RUST_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    if (std.mem.startsWith(u8, func_name, "_ZN4core") or
        std.mem.startsWith(u8, func_name, "_ZN5alloc") or
        std.mem.startsWith(u8, func_name, "_ZN3std"))
    {
        return .runtime_internal;
    }

    for (RUST_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    if (std.mem.startsWith(u8, func_name, "_ZN") or
        std.mem.startsWith(u8, func_name, "_R"))
    {
        return .unknown;
    }

    return .unknown;
}

test "classifyRustFunction - safe patterns" {
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::vec::Vec::push"));
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::sync::Arc::clone"));
    try std.testing.expectEqual(ZoneKind.runtime_internal, classifyRustFunction("_ZN4core3ptr13drop_in_place"));
    const ring_result = classifyRustFunction("_ZN4ring3rsa7keypair7KeyPair8from_der");
    try std.testing.expect(ring_result == .safe or ring_result == .unknown);
}

test "classifyRustFunction - escape patterns" {
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("std::mem::transmute"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("as_ptr"));
}
