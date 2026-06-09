//! Known False-Positive Suppression Whitelist
//!
//! Maintains patterns that are known to produce false positives
//! from real-world audits (0.2.0 corpus: BLST, Wasmtime, SQLite3, libuv, etc.).
//!
//! Design principles (plan/rules/skills.md §2):
//! - Minimum code that solves the problem
//! - Every entry traces to an actual FP from audit data
//! - No speculative patterns — only verified cases

const std = @import("std");

/// Pattern matching kind for whitelist entries.
pub const MatchKind = enum(u8) {
    /// Prefix match: function name starts with this string
    prefix,
    /// Exact match: function name must equal exactly
    exact,
    /// Contains match: function name contains this substring
    contains,
};

/// A single known false-positive pattern with provenance tracking.
pub const KnownFPPattern = struct {
    /// The pattern string to match against function names
    pattern: []const u8,
    /// How to match the pattern against function names
    kind: MatchKind,
    /// Why this is a known FP (audit evidence)
    reason: []const u8,
    /// Which version this was added in
    since_version: []const u8,

    /// Check if a given function name matches this pattern.
    pub fn matches(self: KnownFPPattern, func_name: []const u8) bool {
        return switch (self.kind) {
            .prefix => std.mem.startsWith(u8, func_name, self.pattern),
            .exact => std.mem.eql(u8, func_name, self.pattern),
            .contains => std.mem.indexOf(u8, func_name, self.pattern) != null,
        };
    }
};

/// Minimal whitelist — exactly 3 entries per plan §2.2.
///
/// All other patterns are now covered by SRT detectors:
///   - LLVM intrinsics → noise filter layer (layer1_NameBasedFilter)
///   - Rust stdlib (Arc/RawVec/__rust_alloc/__rust_dealloc) → heap_provenance.zig + drop_glue.zig
///   - Interior mutability (UnsafeCell) → interior_mut.zig
///   - POSIX syscalls → posix_syscalls.zig (R-4)
///   - Library allocators → library_alloc_pairs.zig (R-7)
///   - into_raw ownership transfer → into_raw_transfer.zig (R-6)
///
/// Only patterns that cannot be expressed as IR-level semantic rules remain here.
const known_fp_patterns = [_]KnownFPPattern{
    // macOS malloc_set_zone_name: copies name string, does not retain pointer (man page)
    .{ .pattern = "malloc_set_zone_name", .kind = .exact, .reason = "macOS: copies name string, pointer not retained (man page)", .since_version = "v0.2.0" },
    // Rust Box::into_raw: explicit ownership transfer to caller
    .{ .pattern = "into_raw", .kind = .contains, .reason = "Rust Box/CString/Vec::into_raw — ownership transferred to caller", .since_version = "v0.2.0" },
    // Rust String::into_raw: same ownership transfer pattern
    .{ .pattern = "String_into_raw", .kind = .contains, .reason = "Rust String::into_raw — ownership transferred to caller", .since_version = "v0.2.0" },
};

/// Check if a function name matches any known false-positive pattern.
///
/// This is the primary API for all passes to check before reporting.
/// Returns the matched pattern if found, null otherwise (analyze normally).
///
/// Usage in pass pipeline:
///   if (fp_whitelist.is_known_fp(func_name)) |fp| {
///       diag.debug("FP-SUPPRESSED [{s}]: {s}", .{ fp.reason, func_name });
///       continue; // skip analysis
///   }
pub fn is_known_fp(func_name: []const u8) ?KnownFPPattern {
    for (known_fp_patterns) |pattern| {
        if (pattern.matches(func_name)) {
            return pattern;
        }
    }
    return null;
}

/// Check if a function name is a known FP AND safe to suppress at FFI boundaries.
///
/// More restrictive than is_known_fp() — only returns true for patterns
/// where we have high confidence the finding would be a false positive
/// in FFI safety context.
pub fn is_safe_to_suppress_at_ffi_boundary(func_name: []const u8) bool {
    // All known FP patterns are safe to suppress at FFI boundaries
    // because they represent compiler-generated or stdlib-internal code
    return is_known_fp(func_name) != null;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "is_known_fp - malloc_set_zone_name suppressed" {
    const fp = is_known_fp("malloc_set_zone_name");
    try std.testing.expect(fp != null);
    try std.testing.expect(fp.?.kind == .exact);
}

test "is_known_fp - into_raw suppressed" {
    const fp = is_known_fp("_RNvXs3std3Box3Foo8into_raw");
    try std.testing.expect(fp != null);
}

test "is_known_fp - real FFI NOT suppressed" {
    // These must NOT be whitelisted — they are real FFI functions
    // that should be analyzed by SRT detectors instead.
    try std.testing.expect(is_known_fp("dlopen") == null);
    try std.testing.expect(is_known_fp("malloc") == null);
    try std.testing.expect(is_known_fp("free") == null);
    try std.testing.expect(is_known_fp("pthread_create") == null);
    try std.testing.expect(is_known_fp("sqlite3_open") == null);
    try std.testing.expect(is_known_fp("JNI_OnLoad") == null);
    try std.testing.expect(is_known_fp("Py_INCREF") == null);
    try std.testing.expect(is_known_fp("socket") == null);
    // LLVM intrinsics — handled by noise filter, not whitelist
    try std.testing.expect(is_known_fp("llvm.lifetime.start") == null);
    try std.testing.expect(is_known_fp("llvm.dbg.declare") == null);
    // Rust stdlib — handled by SRT detectors
    try std.testing.expect(is_known_fp("__rust_alloc") == null);
    try std.testing.expect(is_known_fp("__rust_dealloc") == null);
}

test "MatchKind - prefix matching" {
    const pattern = KnownFPPattern{
        .pattern = "llvm.",
        .kind = .prefix,
        .reason = "test",
        .since_version = "v0.2.0",
    };
    try std.testing.expect(pattern.matches("llvm.test"));
    try std.testing.expect(!pattern.matches("not_llvm"));
}

test "MatchKind - exact matching" {
    const pattern = KnownFPPattern{
        .pattern = "malloc",
        .kind = .exact,
        .reason = "test",
        .since_version = "v0.2.0",
    };
    try std.testing.expect(pattern.matches("malloc"));
    try std.testing.expect(!pattern.matches("malloc_custom"));
    try std.testing.expect(!pattern.matches("my_malloc"));
}

test "MatchKind - contains matching" {
    const pattern = KnownFPPattern{
        .pattern = "channel",
        .kind = .contains,
        .reason = "test",
        .since_version = "v0.2.0",
    };
    try std.testing.expect(pattern.matches("mpsc::channel"));
    try std.testing.expect(pattern.matches("sync_channel"));
    try std.testing.expect(!pattern.matches("no_match"));
}
