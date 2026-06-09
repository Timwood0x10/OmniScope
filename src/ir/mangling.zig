//! Mangling prefix decoder for Rust v0 and Itanium ABIs.
//! Uses structural prefix matching only — no symbol tables.
//!
//! Also provides `isRustInternal()` — a structural replacement for the
//! deprecated static whitelist in `whitelists/rust_internal.zig`.

const std = @import("std");
const IREvidence = @import("ir_evidence.zig").IREvidence;

pub const Language = enum { rust, cpp, swift, go, unknown };

pub const ManglingInfo = struct {
    lang: Language,
    is_drop_glue: bool,
    is_destructor: bool,
    is_vtable_thunk: bool,
    crate_or_namespace: ?[]const u8,
};

/// Returns true if a function is a Rust-internal symbol.
/// Uses structural IR evidence rather than name matching:
/// 1. DWARF lang of defining CU is Rust, OR
/// 2. has Rust personality (rust_eh_personality) AND
/// 3. name passes Rust v0 mangling validator
pub fn isRustInternal(evidence: *const IREvidence, func_name: []const u8) bool {
    if (evidence.dominant_language == .rust) return true;
    if (!evidence.has_rust_personality) return false;
    return isRustVMangled(func_name);
}

/// Validates Rust v0 mangling prefix: _R... with length-prefixed segments.
/// This is purely structural — no symbol table lookup.
///
/// Rust v0 mangling (RFC 2603) format:
///   _R<base62-hash>_<encoded-path>
/// where the hash and path use only base-62 characters [0-9a-zA-Z].
pub fn isRustVMangled(name: []const u8) bool {
    if (name.len < 5) return false;
    if (name[0] != '_' or name[1] != 'R') return false;

    // After _R, scan through base-62 hash characters until '_' separator.
    var i: usize = 2;
    while (i < name.len and name[i] != '_') : (i += 1) {
        if (!isBase62(name[i])) return false;
    }
    // Must have found '_' (the hash-to-path separator) with non-empty hash
    // and content after it. Hash must be at least 1 character (i > 2) and
    // content must follow '_' (i < name.len - 1).
    if (i < 3 or i >= name.len - 1) return false;
    return true;
}

/// Check if a function name is a Rust v0 mangled alloc function.
/// Rust v0 mangled names start with `_R` and contain `alloc`/`allocate` segments.
/// This is purely structural detection — no static name list needed.
pub fn isRustAllocCall(func_name: []const u8) bool {
    if (!std.mem.startsWith(u8, func_name, "_R")) return false;
    return std.mem.indexOf(u8, func_name, "alloc") != null;
}

/// Returns true if c is a base-62 digit: 0-9, a-z, or A-Z.
fn isBase62(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'z', 'A'...'Z' => true,
        else => false,
    };
}

/// Parse mangling prefix and return ManglingInfo.
/// Returns .unknown if no known mangling scheme is detected.
pub fn parse(name: []const u8) ManglingInfo {
    if (name.len < 2) return fallback();

    // Rust v0: _R...
    if (name[0] == '_' and name[1] == 'R') {
        return parseRustV0(name);
    }

    // Itanium: _Z...
    if (name[0] == '_' and name[1] == 'Z') {
        return parseItanium(name);
    }

    // Swift: $s...
    if (name[0] == '$' and name[1] == 's') {
        return ManglingInfo{
            .lang = .swift,
            .is_drop_glue = false,
            .is_destructor = false,
            .is_vtable_thunk = false,
            .crate_or_namespace = null,
        };
    }

    return fallback();
}

fn parseRustV0(name: []const u8) ManglingInfo {
    // Rust v0: _R<module-hash><path-segments>
    // Find "drop_in_place" in path for drop glue detection
    const has_drop = std.mem.indexOf(u8, name, "drop_in_place") != null;
    return ManglingInfo{
        .lang = .rust,
        .is_drop_glue = has_drop,
        .is_destructor = false,
        .is_vtable_thunk = false,
        .crate_or_namespace = null,
    };
}

fn parseItanium(name: []const u8) ManglingInfo {
    // Itanium: _Z<length><name>...
    // D0/D1/D2 = destructor, TT/TV = vtable thunk
    const is_destructor = name.len > 3 and name[2] == 'D' and
        (name[3] == '0' or name[3] == '1' or name[3] == '2');
    const is_vtable = std.mem.indexOf(u8, name, "TT") != null or
        std.mem.indexOf(u8, name, "TV") != null;
    return ManglingInfo{
        .lang = .cpp,
        .is_drop_glue = false,
        .is_destructor = is_destructor,
        .is_vtable_thunk = is_vtable,
        .crate_or_namespace = null,
    };
}

fn fallback() ManglingInfo {
    return ManglingInfo{
        .lang = .unknown,
        .is_drop_glue = false,
        .is_destructor = false,
        .is_vtable_thunk = false,
        .crate_or_namespace = null,
    };
}

// ── Tests ──

test "isRustVMangled - valid Rust v0 names" {
    // _R + base62 hash + _ + path
    try std.testing.expect(isRustVMangled("_RA1b2c3_def"));
    try std.testing.expect(isRustVMangled("_RNvCsfLfy6EI15iL_7__rustc"));
    try std.testing.expect(isRustVMangled("_RNC2a3b_4test"));
    try std.testing.expect(isRustVMangled("_Rv0M1f_3foo"));
}

test "isRustVMangled - rejects non-Rust names" {
    try std.testing.expect(!isRustVMangled("_ZN4core3fmt5Debug3fmtE"));
    try std.testing.expect(!isRustVMangled("_Z3fooi"));
    try std.testing.expect(!isRustVMangled("rust_function"));
    try std.testing.expect(!isRustVMangled("malloc"));
    try std.testing.expect(!isRustVMangled(""));
    try std.testing.expect(!isRustVMangled("_R"));
    try std.testing.expect(!isRustVMangled("_R_"));
    try std.testing.expect(!isRustVMangled("_Rx_"));
}

test "isRustVMangled - rejects malformed prefix" {
    // No underscore before path
    try std.testing.expect(!isRustVMangled("_Rabc"));
    // Hash contains non-base62
    try std.testing.expect(!isRustVMangled("_Rab-c_def"));
}

test "parse - Rust v0 mangling" {
    const info = parse("_RNvCsfLfy6EI15iL_7__rustc");
    try std.testing.expectEqual(Language.rust, info.lang);
}

test "parse - C++ Itanium mangling" {
    const info = parse("_Z3fooi");
    try std.testing.expectEqual(Language.cpp, info.lang);
}

test "parse - Swift mangling" {
    const info = parse("$ss5print");
    try std.testing.expectEqual(Language.swift, info.lang);
}

test "parse - unknown mangling" {
    const info = parse("malloc");
    try std.testing.expectEqual(Language.unknown, info.lang);
}

test "parse - destructor detection" {
    const d0 = parse("_ZD0fooi");
    try std.testing.expectEqual(true, d0.is_destructor);
    const d1 = parse("_ZD1fooi");
    try std.testing.expectEqual(true, d1.is_destructor);
    const d2 = parse("_ZD2fooi");
    try std.testing.expectEqual(true, d2.is_destructor);
    const normal = parse("_Z3fooi");
    try std.testing.expectEqual(false, normal.is_destructor);
}

test "parse - vtable thunk detection" {
    const tt = parse("_ZTT4Base");
    try std.testing.expectEqual(true, tt.is_vtable_thunk);
    const tv = parse("_ZTV4Base");
    try std.testing.expectEqual(true, tv.is_vtable_thunk);
    const normal = parse("_Z3fooi");
    try std.testing.expectEqual(false, normal.is_vtable_thunk);
}

test "parse - drop glue detection" {
    const drop = parse("_RNvCsfLfy6EI15iL_7drop_in_place");
    try std.testing.expectEqual(true, drop.is_drop_glue);
    const normal = parse("_RNvCsfLfy6EI15iL_7__rustc");
    try std.testing.expectEqual(false, normal.is_drop_glue);
}
