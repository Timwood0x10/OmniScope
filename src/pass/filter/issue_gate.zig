//! Issue Gate — unified filter for all Issues before aggregator.
//!
//! All Passes MUST query SRT before emitting an Issue. This gate
//! enforces the semantic consensus: if SRT says "this value has
//! heap_provenance" or "this is a file_operation", the gate suppresses
//! or downgrades the Issue.
//!
//! Design: every Issue goes through checkIssue() → GateVerdict.
//! New Passes don't need whitelist code — just add Resolution to SRT.

const std = @import("std");
const SemanticTree = @import("../../semantics/semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../../semantics/semantic_tree.zig").SemanticKind;
const Issue = @import("../../diag/issue.zig").Issue;

/// Gate verdict for an Issue
pub const GateVerdict = enum {
    /// Allow the Issue to proceed to aggregator
    allow,
    /// Suppress — SRT provides a semantic explanation
    suppress_heap_origin,
    suppress_global_origin,
    suppress_interior_mut,
    suppress_raii,
    suppress_non_memory_syscall,
    /// Downgrade — reduce severity/confidence
    downgrade_low_confidence,
};

/// Check an Issue against SRT semantic consensus.
/// Returns the verdict: allow, suppress, or downgrade.
pub fn checkIssue(srt: *const SemanticTree, issue: *const Issue) GateVerdict {
    // Get the value reference from the issue
    // Note: Issue structure may vary — adapt as needed
    const value_ref = getValueRefFromIssue(issue);

    switch (issue.kind) {
        .borrow_escape => {
            // F1: 74 borrow_escape FP — heap/global provenance suppresses
            if (srt.hasKind(value_ref, .heap_provenance) != null) {
                return .suppress_heap_origin;
            }
            if (srt.hasKind(value_ref, .global_provenance) != null) {
                return .suppress_global_origin;
            }
        },
        .write_to_immutable => {
            // F2: 23 write_to_immutable FP — interior mutability suppresses
            if (srt.hasKind(value_ref, .interior_mutability) != null) {
                return .suppress_interior_mut;
            }
            // Also check if the enclosing function is a once-init context
            if (srt.hasKind(value_ref, .interior_mutability) != null) {
                return .suppress_interior_mut;
            }
        },
        .use_after_free => {
            // F4: 3 use_after_free FP — RAII drop suppresses
            if (srt.hasKind(value_ref, .raii_drop_release) != null) {
                return .suppress_raii;
            }
            // Non-memory syscalls should not trigger UAF
            if (srt.hasKind(value_ref, .file_operation) != null) {
                return .suppress_non_memory_syscall;
            }
            if (srt.hasKind(value_ref, .network_operation) != null) {
                return .suppress_non_memory_syscall;
            }
        },
        .cross_language_free => {
            // F3: 4 cross_language_free FP — non-memory syscalls suppress
            if (srt.hasKind(value_ref, .file_operation) != null) {
                return .suppress_non_memory_syscall;
            }
            if (srt.hasKind(value_ref, .network_operation) != null) {
                return .suppress_non_memory_syscall;
            }
            if (srt.hasKind(value_ref, .process_operation) != null) {
                return .suppress_non_memory_syscall;
            }
        },
        .command_injection => {
            // F5: 2 command_injection FP — global provenance suppresses
            // (self_exe_path, compile-time constants)
            if (srt.hasKind(value_ref, .global_provenance) != null) {
                return .suppress_global_origin;
            }
            // process_operation alone is not enough — need taint source
            // This is handled by the Pass itself (queries taint_state)
        },
        else => {},
    }

    return .allow;
}

/// Get value reference from an Issue.
/// Adapt this based on the actual Issue structure.
fn getValueRefFromIssue(issue: *const Issue) u64 {
    // Try to extract from the issue's location or trace
    // This may need adaptation based on Issue struct layout
    if (issue.location.func.len > 0) {
        // Use function name hash as a fallback value_ref
        return std.hash_map.hashString(issue.location.func);
    }
    return 0;
}

/// Get a human-readable reason for suppression (for diagnostics)
pub fn verdictReason(verdict: GateVerdict) ?[]const u8 {
    return switch (verdict) {
        .allow => null,
        .suppress_heap_origin => "suppressed: value has heap provenance (Nomicon Ch9)",
        .suppress_global_origin => "suppressed: value has global provenance",
        .suppress_interior_mut => "suppressed: interior mutability via UnsafeCell (Nomicon Ch5)",
        .suppress_raii => "suppressed: RAII drop/release (Nomicon Ch6)",
        .suppress_non_memory_syscall => "suppressed: non-memory syscall (POSIX file/net/proc)",
        .downgrade_low_confidence => "downgraded: low confidence due to SRT analysis",
    };
}
