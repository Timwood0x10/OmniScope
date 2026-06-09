//! Issue Gate — unified suppression gate for all issues
//!
//! Every issue must pass through this gate before being emitted.
//! The gate queries the SRT for semantic resolutions that explain
//! away the potential violation. This ensures that no pass can
//! bypass the semantic consensus layer.
//!
//! Design: R-0~R-8 detectors populate the SRT. This gate reads it.
//! New detectors automatically benefit from existing gate rules.
//!
//! Gate rules are derived from bun FP reduction plan (R-0~R-8):
//!   - R-0: readonly/mutable_param -> write_to_immutable suppression
//!   - R-1: heap_provenance -> borrow_escape suppression
//!   - R-2: interior_mutability -> write_to_immutable suppression
//!   - R-3: raii_drop_release -> use_after_free suppression
//!   - R-4: file/network/process_operation -> cross_language_free suppression
//!   - R-6: into_raw_transfer -> cross_language_free suppression
//!   - R-7: library_release -> cross_language_free suppression
//!   - R-8: from_parameter -> borrow_escape suppression

const std = @import("std");
const SemanticTree = @import("../../semantics/semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../../semantics/semantic_tree.zig").SemanticKind;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const log = std.log.scoped(.issue_gate);

/// Minimum confidence threshold for enhanced gate suppression.
/// Resolutions below this threshold are considered unreliable.
const MIN_CONFIDENCE_THRESHOLD: f32 = 0.85;

/// Gate verdict — what the gate decided about an issue.
pub const GateVerdict = enum {
    allow, // Issue passes through — report it
    suppress_mutable_param, // R-0: write to &mut T is legal
    suppress_interior_mut, // R-2: write to UnsafeCell is legal
    suppress_heap_origin, // R-1: pointer has heap provenance
    suppress_global_origin, // R-1: pointer has global provenance
    suppress_raii, // R-3: RAII drop is compiler-inserted
    suppress_non_memory_syscall, // R-4: syscall is not memory-related
    suppress_ownership_transfer, // R-6: into_raw ownership transfer
    suppress_library_release, // R-7: library-level release
    suppress_parameter_source, // R-8: parameter is not stack escape
};

/// Check an issue against the SRT gate rules.
/// Returns .allow if the issue should be reported, or the specific
/// suppression reason if it should be suppressed.
/// The value_ref parameter is the LLVM ValueRef associated with the issue.
pub fn checkIssue(srt: *const SemanticTree, value_ref: u64, kind: IssueKind) GateVerdict {
    switch (kind) {
        .borrow_escape => {
            // R-1: Heap pointers are not stack escapes
            if (srt.hasKind(value_ref, .heap_provenance) != null) return .suppress_heap_origin;
            // R-1: Global/static pointers are not stack escapes
            if (srt.hasKind(value_ref, .global_provenance) != null) return .suppress_global_origin;
            // R-0: Parameters passed with noalias (exclusive &mut T) are not escapes
            if (srt.hasKind(value_ref, .mutable_param) != null) return .suppress_parameter_source;
        },
        .write_to_immutable => {
            // R-0: Writing to &mut T is legal (no readonly attribute)
            if (srt.hasKind(value_ref, .mutable_param) != null) return .suppress_mutable_param;
            // R-2: Writing to UnsafeCell-derived memory is legal
            if (srt.hasKind(value_ref, .interior_mutability) != null) return .suppress_interior_mut;
        },
        .use_after_free => {
            // R-3: RAII drop is compiler-inserted, not a bug
            if (srt.hasKind(value_ref, .raii_drop_release) != null) return .suppress_raii;
        },
        .cross_language_leak, .cross_language_free => {
            // R-6: Ownership transferred via into_raw — C free() is legal
            if (srt.hasKind(value_ref, .into_raw_transfer) != null) return .suppress_ownership_transfer;
            // R-4: Non-memory syscalls (file/net/proc)
            if (srt.hasKind(value_ref, .file_operation) != null) return .suppress_non_memory_syscall;
            if (srt.hasKind(value_ref, .network_operation) != null) return .suppress_non_memory_syscall;
            if (srt.hasKind(value_ref, .process_operation) != null) return .suppress_non_memory_syscall;
            // R-7: Library-level allocator release
            if (srt.hasKind(value_ref, .library_release) != null) return .suppress_library_release;
        },
        else => {},
    }
    return .allow;
}

/// Check an issue against the SRT gate rules with enhanced verification.
///
/// Enhanced logic (compared to simple single-kind check):
///   1. Conflict detection: if value has BOTH suppressible AND non-suppressible
///      kinds, default to ALLOW (conservative)
///   2. Primary kind match required (existing behavior)
///   3. Confidence threshold: only suppress if resolution confidence >= 0.85
///   4. Secondary corroboration recommended (new):
///      - For write_to_immutable: also check that target is NOT allocation-only
///      - For borrow_escape: also check that source is NOT global provenance
///      - For cross_language_free: additional safety checks
///
/// Arguments:
///   srt        - The semantic resolution tree
///   value_ref  - The LLVM ValueRef associated with the issue
///   kind       - The issue kind to check
///
/// Returns:
///   .allow if the issue should be reported, or the specific suppression reason
pub fn checkIssueEnhanced(
    srt: *const SemanticTree,
    value_ref: u64,
    kind: IssueKind,
) GateVerdict {
    // ── Step 0: Conflict detection ──
    // If value has BOTH suppressible AND critical kinds, don't suppress
    if (hasConflictingResolutions(srt, value_ref)) {
        log.debug("[GATE-CONFLICT] Value {x} has conflicting resolutions — allowing issue", .{value_ref});
        return .allow;
    }

    // ── Step 1: Existing primary check (unchanged) ──
    const primary_verdict = checkIssue(srt, value_ref, kind);
    if (primary_verdict == .allow) return .allow;

    // ── Step 2: Confidence verification ──
    const resolution = srt.hasKind(value_ref, extractKindFromVerdict(primary_verdict)) orelse return .allow;
    if (resolution.confidence < MIN_CONFIDENCE_THRESHOLD) {
        log.debug("[GATE-LOW-CONF] Kind {s} confidence {d:.2} below threshold {d:.2} — allowing", .{ @tagName(kind), resolution.confidence, MIN_CONFIDENCE_THRESHOLD });
        return .allow;
    }

    // ── Step 3: Secondary corroboration (kind-specific) ──
    switch (kind) {
        .write_to_immutable => {
            // Additional check: make sure the value isn't also marked as
            // something that would indicate this write is problematic
            if (srt.hasKind(value_ref, .allocation) != null) {
                // Writing to a freshly allocated location might be init, not bug
                // But if it's ALSO interior mutable, that's fine
                if (srt.hasKind(value_ref, .interior_mutability) == null) {
                    log.debug("[GATE-CORROBORATE] write_to_alloc without interior_mut — allowing", .{});
                    return .allow;
                }
            }
        },
        .borrow_escape => {
            // Additional check: if escaping to global, that's more suspicious
            if (srt.hasKind(value_ref, .global_provenance) != null) {
                // Escaping to global is usually bad unless it's a known-safe pattern
                log.debug("[GATE-CORROBORATE] escape to global — needs review", .{});
                return .allow; // Conservative: let human review
            }
        },
        .cross_language_leak, .cross_language_free => {
            // Additional check: verify we have strong evidence for ownership transfer
            if (primary_verdict == .suppress_ownership_transfer) {
                // into_raw_transfer should have high confidence by default
                // but double-check there's no memory_leak marker too
                if (srt.hasKind(value_ref, .memory_leak) != null) {
                    log.debug("[GATE-CORROBORATE] both transfer and leak markers — allowing", .{});
                    return .allow;
                }
            }
        },
        else => {},
    }

    // All checks passed → suppress
    log.debug("[GATE-SUPPRESS] Enhanced checks passed for kind {s} — suppressing", .{@tagName(kind)});
    return primary_verdict;
}

/// Check if a value has resolutions that conflict with suppressing this issue.
///
/// Example conflicts:
///   - Value has BOTH .interior_mutability AND .readonly_param (ambiguous mutability)
///   - Value has BOTH .into_raw_transfer AND .memory_leak (ambiguous ownership)
///   - Value has BOTH .raii_drop_release AND .invalid_free (ambiguous release)
///
/// When conflicts exist, it's safer to allow the issue for human review.
fn hasConflictingResolutions(
    srt: *const SemanticTree,
    value_ref: u64,
) bool {
    // Define conflict pairs: if both present, it's ambiguous
    const conflict_pairs = [_][2]SemanticKind{
        .{ .interior_mutability, .readonly_param }, // Is it mutable or not?
        .{ .into_raw_transfer, .memory_leak }, // Transfer or leak?
        .{ .raii_drop_release, .invalid_free }, // RAII or invalid?
        .{ .allocation, .release }, // Both allocating and releasing? Suspicious.
    };

    for (conflict_pairs) |pair| {
        if ((srt.hasKind(value_ref, pair[0]) != null) and
            (srt.hasKind(value_ref, pair[1]) != null))
        {
            log.debug("[CONFLICT] Both {s} and {s} present on value {x}", .{ @tagName(pair[0]), @tagName(pair[1]), value_ref });
            return true;
        }
    }

    return false;
}

/// Extract the SemanticKind from a GateVerdict.
/// Maps suppression verdicts back to their corresponding semantic kinds.
fn extractKindFromVerdict(verdict: GateVerdict) SemanticKind {
    return switch (verdict) {
        .suppress_mutable_param => .mutable_param,
        .suppress_interior_mut => .interior_mutability,
        .suppress_heap_origin => .heap_provenance,
        .suppress_global_origin => .global_provenance,
        .suppress_raii => .raii_drop_release,
        .suppress_non_memory_syscall => .file_operation, // Best approximation
        .suppress_ownership_transfer => .into_raw_transfer,
        .suppress_library_release => .library_release,
        .suppress_parameter_source => .mutable_param, // Best approximation
        .allow => .unknown, // Should never be called with .allow
    };
}

/// Get a human-readable reason for a gate verdict.
pub fn verdictReason(verdict: GateVerdict) []const u8 {
    return switch (verdict) {
        .allow => "no suppression",
        .suppress_mutable_param => "R-0: write to &mut T (mutable_param) is legal",
        .suppress_interior_mut => "R-2: write to UnsafeCell-derived memory is legal",
        .suppress_heap_origin => "R-1: heap provenance - not a stack escape",
        .suppress_global_origin => "R-1: global provenance - not a stack escape",
        .suppress_raii => "R-3: RAII drop - compiler-inserted release",
        .suppress_non_memory_syscall => "R-4: non-memory syscall (file/net/proc)",
        .suppress_ownership_transfer => "R-6: into_raw ownership transfer - C free() is legal",
        .suppress_library_release => "R-7: library-level allocator release",
        .suppress_parameter_source => "R-8: function parameter - not a stack escape",
    };
}
