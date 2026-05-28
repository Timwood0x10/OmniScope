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
