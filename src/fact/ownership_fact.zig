//! Ownership Fact for Cross-Language Ownership Analysis
//!
//! **DEPRECATED (2026-05-04):** This module is unused — no @import references found.
//! Retained for potential future use. See todolist.md DEAD-1 for details.
//!
//! This module defines the ownership tracking fact used to detect
//! ownership mismatches across Rust-C FFI boundaries.

const std = @import("std");
const Language = @import("../../diag/issue.zig").Language;

/// Ownership state enumeration
pub const OwnershipState = enum(u8) {
    /// Pointer is live and正常使用中
    live,
    /// Memory was allocated but never freed - potential leak
    leaked,
    /// Memory was freed - should not be used again
    freed,
    /// Unknown ownership state
    unknown,
};

/// Ownership violation type
pub const OwnershipViolationType = enum(u8) {
    /// Pointer allocated in one language, freed in another
    cross_lang_free_mismatch,
    /// Ownership transferred across boundary but not properly tracked
    ownership_lost,
    /// Same memory freed twice
    double_free,
    /// Memory allocated, passed to C, but Rust drop called - double free risk
    rust_drop_after_ffi_free,
    /// Borrowed reference escaped lifetime
    borrow_escaped,
};

/// Ownership fact - tracks pointer ownership across FFI boundaries
pub const OwnershipFact = struct {
    /// Pointer identifier (usually instruction/address ID)
    ptr_id: u32,
    /// Where the pointer was allocated (instruction ID)
    alloc_site: ?u32,
    /// Language where allocation happened
    alloc_lang: Language,
    /// Where the pointer was freed (instruction ID, if applicable)
    free_site: ?u32,
    /// Language where free happened
    free_lang: Language,
    /// Current ownership state
    state: OwnershipState,
    /// Whether this pointer crossed an FFI boundary
    crossed_boundary: bool,
    /// Function where allocation happened
    alloc_func: []const u8,
    /// Function where free happened (if applicable)
    free_func: []const u8,
};

test "OwnershipState - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipState.live));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipState.leaked));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipState.freed));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipState.unknown));
}

test "OwnershipViolationType - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipViolationType.ownership_lost));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipViolationType.double_free));
}
