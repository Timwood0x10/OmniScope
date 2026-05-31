//! Unified issue classification — Single Source of Truth for issue kind categorization.
//!
//! All filtering layers MUST reference this module instead of maintaining
//! their own protection lists. This eliminates the inconsistency between:
//! - isRealMemorySafetyBug (15 kinds in issue_suppression.zig)
//! - is_core_memory_safety_bug (7 kinds in pass_types.zig)
//! - is_ffi_issue (10 kinds in pass_types.zig)
//!
//! Categories determine suppression and downgrade behavior:
//! - core_memory_safety: NEVER suppressed, NEVER downgraded
//! - ffi_boundary: NEVER suppressed, can be downgraded
//! - security_critical: NEVER suppressed, NEVER downgraded
//! - leak: can be downgraded, not fully suppressed
//! - advisory: can be downgraded and suppressed

const std = @import("std");
const IssueKind = @import("../common/types.zig").IssueKind;

/// Authoritative categorization of all issue kinds.
/// Every filtering layer must use `categorize()` to determine behavior.
pub const IssueCategory = enum {
    /// Core memory safety violations — CWE-classified critical vulnerabilities.
    /// NEVER suppress, NEVER downgrade. These are real bugs regardless of context.
    core_memory_safety,

    /// FFI boundary issues — cross-language safety violations.
    /// NEVER suppress (inherently security-relevant), but CAN be downgraded.
    ffi_boundary,

    /// Security-critical vulnerabilities — injection, format string, etc.
    /// NEVER suppress, NEVER downgraded.
    security_critical,

    /// Memory leaks — deterministic but probabilistic impact.
    /// CAN be downgraded, but NOT fully suppressed.
    leak,

    /// Advisory issues — type mismatches, unchecked returns, etc.
    /// CAN be downgraded and suppressed.
    advisory,
};

/// Categorize an issue kind into its authoritative category.
/// This is the SINGLE function all layers should call to determine category.
pub fn categorize(kind: IssueKind) IssueCategory {
    return switch (kind) {
        // Core memory safety — CWE-classified critical vulnerabilities
        .use_after_free, // CWE-416
        .double_free, // CWE-415
        .invalid_free, // CWE-590
        .null_dereference, // CWE-476
        .buffer_overflow, // CWE-120
        .integer_overflow, // CWE-190
        => .core_memory_safety,

        // FFI boundary — cross-language safety violations
        .cross_language_leak, // CWE-401 (cross-boundary)
        .cross_language_free, // CWE-763
        .contract_mismatch, // CWE-763 (wrong release function)
        .ffi_unsafe_call, // CWE-668
        .ffi_type_mismatch, // CWE-704
        .borrow_escape, // CWE-704 (Rust borrow escape)
        .type_mismatch, // CWE-704
        .callback_ownership_risk, // CWE-825
        .callback_signature_mismatch, // CWE-688
        => .ffi_boundary,

        // Security-critical — injection and format string vulnerabilities
        .command_injection, // CWE-78
        .format_string, // CWE-134
        .malloc_unchecked, // CWE-252 (unchecked allocation)
        => .security_critical,

        // Memory leaks — deterministic but probabilistic impact
        .memory_leak, // CWE-401
        => .leak,

        // Advisory — everything else
        .unchecked_return,
        .write_to_immutable,
        .static_buffer_misuse,
        .data_race,
        .thread_safety_violation,
        .unknown,
        => .advisory,
    };
}

/// Whether this issue kind should NEVER be suppressed by any filtering layer.
/// Returns true for core_memory_safety, ffi_boundary, and security_critical.
pub fn isNeverSuppressed(kind: IssueKind) bool {
    return switch (categorize(kind)) {
        .core_memory_safety, .ffi_boundary, .security_critical => true,
        .leak, .advisory => false,
    };
}

/// Whether this issue kind should NEVER be downgraded by noise filter.
/// Returns true ONLY for core_memory_safety and security_critical.
/// Note: ffi_boundary issues CAN be downgraded but NOT suppressed.
pub fn isNeverDowngraded(kind: IssueKind) bool {
    return switch (categorize(kind)) {
        .core_memory_safety, .security_critical => true,
        .ffi_boundary, .leak, .advisory => false,
    };
}

/// Whether this issue kind is an FFI boundary issue.
/// Used by risk suppression to determine if FFI issues bypass suppression.
pub fn isFFIBoundary(kind: IssueKind) bool {
    return categorize(kind) == .ffi_boundary;
}

// ============================================================================
// Tests
// ============================================================================

test "core_memory_safety is never suppressed or downgraded" {
    const kinds = [_]IssueKind{ .use_after_free, .double_free, .invalid_free, .null_dereference, .buffer_overflow, .integer_overflow };
    for (kinds) |kind| {
        try std.testing.expect(categorize(kind) == .core_memory_safety);
        try std.testing.expect(isNeverSuppressed(kind));
        try std.testing.expect(isNeverDowngraded(kind));
    }
}

test "ffi_boundary is never suppressed but can be downgraded" {
    const kinds = [_]IssueKind{ .cross_language_leak, .cross_language_free, .ffi_unsafe_call, .ffi_type_mismatch, .borrow_escape, .type_mismatch, .callback_ownership_risk, .callback_signature_mismatch };
    for (kinds) |kind| {
        try std.testing.expect(categorize(kind) == .ffi_boundary);
        try std.testing.expect(isNeverSuppressed(kind));
        try std.testing.expect(!isNeverDowngraded(kind));
        try std.testing.expect(isFFIBoundary(kind));
    }
}

test "security_critical is never suppressed or downgraded" {
    const kinds = [_]IssueKind{ .command_injection, .format_string, .malloc_unchecked };
    for (kinds) |kind| {
        try std.testing.expect(categorize(kind) == .security_critical);
        try std.testing.expect(isNeverSuppressed(kind));
        try std.testing.expect(isNeverDowngraded(kind));
    }
}

test "leak can be downgraded but not fully suppressed" {
    try std.testing.expect(categorize(.memory_leak) == .leak);
    try std.testing.expect(!isNeverSuppressed(.memory_leak));
    try std.testing.expect(!isNeverDowngraded(.memory_leak));
}

test "advisory can be suppressed and downgraded" {
    const kinds = [_]IssueKind{ .unchecked_return, .write_to_immutable, .static_buffer_misuse, .data_race, .thread_safety_violation, .unknown };
    for (kinds) |kind| {
        try std.testing.expect(categorize(kind) == .advisory);
        try std.testing.expect(!isNeverSuppressed(kind));
        try std.testing.expect(!isNeverDowngraded(kind));
    }
}
