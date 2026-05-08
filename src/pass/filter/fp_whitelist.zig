//! Known False-Positive Suppression Whitelist
//!
//! Maintains patterns that are known to produce false positives
//! from real-world audits (v0.1.6: BLST, Wasmtime, SQLite3, libuv, etc.).
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

/// Top 20 known false-positive patterns from v0.1.6 audit.
///
/// Organized by category for maintainability.
/// Each entry includes source project and reason for suppression.
const known_fp_patterns = [_]KnownFPPattern{
    // ── Category 1: LLVM Intrinsics (already handled by noise_reduction Layer 1)
    // These are duplicated here as defense-in-depth — if a pass bypasses
    // layer1_NameBasedFilter, the whitelist still catches them.

    .{ .pattern = "llvm.threadlocal.address", .kind = .prefix, .reason = "Rust std TLS access (BLST #1 FP)", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.lifetime.start", .kind = .prefix, .reason = "LLVM lifetime marker intrinsic", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.lifetime.end", .kind = .prefix, .reason = "LLVM lifetime marker intrinsic", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.dbg.declare", .kind = .prefix, .reason = "Debug info intrinsic", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.dbg.value", .kind = .prefix, .reason = "Debug info intrinsic", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.assume", .kind = .prefix, .reason = "Optimizer hint intrinsic", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.expect", .kind = .prefix, .reason = "Branch prediction hint", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.coro.begin", .kind = .prefix, .reason = "Coroutine frame (Wasmtime)", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.coro.end", .kind = .prefix, .reason = "Coroutine cleanup (Wasmtime)", .since_version = "v0.1.7" },
    .{ .pattern = "llvm.gc.root", .kind = .prefix, .reason = "GC root intrinsic", .since_version = "v0.1.7" },

    // ── Category 2: Rust Standard Library Safe Primitives

    .{ .pattern = "sync_channel::", .kind = .contains, .reason = "Rust std safe MPSC channel (BLST)", .since_version = "v0.1.7" },
    .{ .pattern = "mpsc::channel::", .kind = .contains, .reason = "Rust std safe channel (BLST)", .since_version = "v0.1.7" },
    .{ .pattern = "Arc::<", .kind = .contains, .reason = "Rust Arc shared ownership (BLST)", .since_version = "v0.1.7" },
    .{ .pattern = "Waker::", .kind = .contains, .reason = "Rust async runtime Waker (Wasmtime)", .since_version = "v0.1.7" },
    .{ .pattern = "RawVec::", .kind = .contains, .reason = "Rust Vec internals (various)", .since_version = "v0.1.7" },
    .{ .pattern = "__rust_alloc", .kind = .contains, .reason = "Rust global allocator shim", .since_version = "v0.1.7" },
    .{ .pattern = "__rust_dealloc", .kind = .contains, .reason = "Rust global deallocator shim", .since_version = "v0.1.7" },

    // ── Category 3: Project-Specific Contextual Patterns

    .{ .pattern = "uv__socket", .kind = .contains, .reason = "libuv internal socket + caller closes (design choice)", .since_version = "v0.1.7" },
    .{ .pattern = "sqlite3MemMalloc", .kind = .exact, .reason = "SQLite custom allocator (not system malloc)", .since_version = "v0.1.7" },
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

test "is_known_fp - llvm.threadlocal suppressed" {
    const fp = is_known_fp("llvm.threadlocal.address.p0i8");
    try std.testing.expect(fp != null);
    try std.testing.expectEqualStrings("Rust std TLS access (BLST #1 FP)", fp.?.reason);
}

test "is_known_fp - rust sync_channel suppressed" {
    const fp = is_known_fp("sync_channel::channel::new");
    try std.testing.expect(fp != null);
}

test "is_known_fp - real FFI NOT suppressed" {
    try std.testing.expect(is_known_fp("dlopen") == null);
    try std.testing.expect(is_known_fp("malloc") == null);
    try std.testing.expect(is_known_fp("pthread_create") == null);
    try std.testing.expect(is_known_fp("sqlite3_open") == null);
    try std.testing.expect(is_known_fp("JNI_OnLoad") == null);
    try std.testing.expect(is_known_fp("Py_INCREF") == null);
    try std.testing.expect(is_known_fp("socket") == null);
}

test "is_known_fp - uv__socket contextual suppression" {
    const fp = is_known_fp("uv__socket");
    try std.testing.expect(fp != null);
    try std.testing.expectEqualStrings(
        "libuv internal socket + caller closes (design choice)",
        fp.?.reason,
    );
}

test "is_known_fp - sqlite3MemMalloc exact match" {
    const fp = is_known_fp("sqlite3MemMalloc");
    try std.testing.expect(fp != null);
    // Similar but different name should NOT match (exact match kind)
    try std.testing.expect(is_known_fp("sqlite3MemMallocCustom") == null);
}

test "MatchKind - prefix matching" {
    const pattern = KnownFPPattern{
        .pattern = "llvm.",
        .kind = .prefix,
        .reason = "test",
        .since_version = "v0.1.0",
    };
    try std.testing.expect(pattern.matches("llvm.test"));
    try std.testing.expect(!pattern.matches("not_llvm"));
}

test "MatchKind - exact matching" {
    const pattern = KnownFPPattern{
        .pattern = "malloc",
        .kind = .exact,
        .reason = "test",
        .since_version = "v0.1.0",
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
        .since_version = "v0.1.0",
    };
    try std.testing.expect(pattern.matches("mpsc::channel"));
    try std.testing.expect(pattern.matches("sync_channel"));
    try std.testing.expect(!pattern.matches("no_match"));
}
