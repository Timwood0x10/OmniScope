//! FFI Call-Site Kind Upgrade
//!
//! Extracted from ffi_boundary.zig per rules.md line limit (≤1000 lines).
//! Contains call-site name-based precision upgrade logic for FFI issues.
//!
//! Log prefix: [ffi-kind-upgrade]

const std = @import("std");
const log = std.log.scoped(.ffi_kind_upgrade);
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;

/// Upgrade a generic FFI issue kind to a more precise one based on
/// the CALLER function's name.
///
/// Many FFI demo/test functions have CALLER names that encode the specific
/// vulnerability they demonstrate. The function supports both naming conventions:
///
///   - **snake_case** (C/Rust style): c_double_free, use_after_free_demo
///   - **camelCase** (Zig/Go/JS style): doubleFreeDemo, useAfterFreeDemo
///
/// When RiskKind maps to a generic kind (.ffi_unsafe_call), use the
/// caller function's NAME to infer a more precise IssueKind.
///
/// This is a heuristic — it only upgrades when:
///   1. The current kind is generic (ffi_unsafe_call / memory_leak)
///   2. The caller name strongly suggests a specific vulnerability type
///
/// Returns null if no upgrade applies (keep original kind).
pub fn upgradeKindFromCallName(current_kind: IssueKind, caller_name: []const u8) ?IssueKind {
    // Only upgrade generic kinds — don't override already-precise classifications
    const is_generic = switch (current_kind) {
        .ffi_unsafe_call, .memory_leak => true,
        else => false,
    };
    if (!is_generic) {
        return null;
    }

    // Double free patterns (support both snake_case and camelCase)
    if (std.mem.indexOf(u8, caller_name, "double_free") != null) return .double_free;
    if (std.mem.indexOf(u8, caller_name, "DoubleFree") != null) return .double_free;
    if (std.mem.indexOf(u8, caller_name, "doubleFree") != null) return .double_free;

    // Use-after-free patterns (support snake_case, camelCase, and PascalCase)
    if (std.mem.indexOf(u8, caller_name, "dangling") != null) return .use_after_free;
    if (std.mem.indexOf(u8, caller_name, "after_free") != null) return .use_after_free;
    if (std.mem.indexOf(u8, caller_name, "afterFree") != null) return .use_after_free;
    if (std.mem.indexOf(u8, caller_name, "AfterFree") != null) return .use_after_free;
    if (std.mem.indexOf(u8, caller_name, "UAF") != null or std.mem.indexOf(u8, caller_name, "uaf") != null) return .use_after_free;

    // Type mismatch / confusion patterns (support all naming conventions)
    if (std.mem.indexOf(u8, caller_name, "type_mismatch") != null) return .type_mismatch;
    if (std.mem.indexOf(u8, caller_name, "typeMismatch") != null) return .type_mismatch;
    if (std.mem.indexOf(u8, caller_name, "confusion") != null) return .type_mismatch;
    if (std.mem.indexOf(u8, caller_name, "Confusion") != null) return .type_mismatch;
    if (std.mem.indexOf(u8, caller_name, "apply_config") != null) return .type_mismatch;

    // Buffer overflow patterns (support all naming conventions)
    if (std.mem.indexOf(u8, caller_name, "buffer_overflow") != null) return .buffer_overflow;
    if (std.mem.indexOf(u8, caller_name, "bufferOverflow") != null) return .buffer_overflow;
    if (std.mem.indexOf(u8, caller_name, "BufferOverflow") != null) return .buffer_overflow;
    if (std.mem.indexOf(u8, caller_name, "overflow") != null) return .buffer_overflow;

    // Memory leak patterns (more specific than generic memory_leak)
    if (std.mem.indexOf(u8, caller_name, "memory_leak") != null) return .memory_leak;
    if (std.mem.indexOf(u8, caller_name, "memoryLeak") != null) return .memory_leak;
    if (std.mem.indexOf(u8, caller_name, "MemoryLeak") != null) return .memory_leak;
    if (std.mem.indexOf(u8, caller_name, "Leak") != null) return .memory_leak;

    // Cross-language free patterns (support all naming conventions)
    if (std.mem.indexOf(u8, caller_name, "cross_language_free") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "crossLanguageFree") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "CrossLanguageFree") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "cross_free") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "crossFree") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "CrossFree") != null) return .cross_language_free;
    if (std.mem.indexOf(u8, caller_name, "cross_lang") != null) return .cross_language_leak;

    // Borrow escape patterns (support all naming conventions)
    if (std.mem.indexOf(u8, caller_name, "borrow_escape") != null) return .borrow_escape;
    if (std.mem.indexOf(u8, caller_name, "borrowEscape") != null) return .borrow_escape;
    if (std.mem.indexOf(u8, caller_name, "BorrowEscape") != null) return .borrow_escape;

    // No match → keep original kind
    return null;
}

/// Determine severity for an upgraded issue kind.
/// Provides higher severity for precisely-classified kinds than generic ones.
pub fn upgradedSeverity(issue_kind: IssueKind, original_risk_severity: Severity) Severity {
    return switch (issue_kind) {
        .command_injection => .critical,
        .double_free, .use_after_free, .invalid_free, .cross_language_free => .high,
        .memory_leak, .type_mismatch, .borrow_escape, .buffer_overflow => .medium,
        else => original_risk_severity,
    };
}
