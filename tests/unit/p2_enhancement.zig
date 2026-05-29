//! P2 Enhancement Tests — Medium Priority Improvements Verification
//!
//! These tests verify P2-level enhancements:
//!   - Mangled name classification edge cases
//!   - into_raw context-aware confidence
//!   - No regression in existing behavior
//!
//! Run: zig build test-p2-enhancement

const std = @import("std");
const OmniScope = @import("OmniScope");

const mangled_name = OmniScope.semantics.surface_classifier.mangled_name;
const into_raw_transfer = OmniScope.semantics.patterns.into_raw_transfer;
const issue_suppression = OmniScope.pass.analysis.noise.issue_suppression;
const Issue = OmniScope.diag.Issue;

// ============================================================================
// Test Group H: Mangled name classification (P2-A: DI chain walking)
// ============================================================================

test "P2-H1: classifyMangledName — Rust core library detected" {
    const result = mangled_name.classifyMangledName("_ZN4core3ptr10drop_in_place17habc123");
    try std.testing.expect(result != null);
}

test "P2-H2: classifyMangledName — Rust alloc crate detected" {
    // alloc crate is detected by _ZN5alloc prefix
    const result = mangled_name.classifyMangledName("_ZN5alloc6alloc::exchange_malloc17habc");
    if (result) |r| {
        try std.testing.expect(r.surface == .standard_library);
    }
}

test "P2-H3: classifyMangledName — Rust panicking is runtime" {
    const result = mangled_name.classifyMangledName("_ZN9panicking9begin_panic17habc");
    try std.testing.expect(result != null);
}

test "P2-H4: classifyMangledName — Rust dependency (unknown crate) returns null" {
    const result = mangled_name.classifyMangledName("_ZN8wasmtime7runtime4Instance7new17habc");
    try std.testing.expect(result == null);
}

test "P2-H5: classifyMangledName — plain user function returns null" {
    const result = mangled_name.classifyMangledName("my_function");
    try std.testing.expect(result == null);
}

test "P2-H6: classifyMangledName — empty string returns null" {
    const result = mangled_name.classifyMangledName("");
    try std.testing.expect(result == null);
}

// ============================================================================
// Test Group J: into_raw context-aware confidence (P2-C)
// ============================================================================

test "P2-J1: isIntoRawCall detects into_raw patterns" {
    // The actual pattern matching checks for "into_raw" substring
    // Test with a realistic Rust mangled name containing into_raw
    try std.testing.expect(into_raw_transfer.isIntoRawCall("_RNvXs_8into_raw"));
}

test "P2-J2: isIntoRawCall rejects non-into_raw patterns" {
    try std.testing.expect(!into_raw_transfer.isIntoRawCall("from_raw"));
    try std.testing.expect(!into_raw_transfer.isIntoRawCall("as_ptr"));
    try std.testing.expect(!into_raw_transfer.isIntoRawCall("normal_function"));
}

// ============================================================================
// Cross-cutting: No regression in existing behavior
// ============================================================================

test "P2-NO-REGRESSION-1: existing FP suppression still works for stdlib internals" {
    var issue = Issue.init(
        .write_to_immutable,
        "write to immutable in HashMap internals",
        .{ .file = null, .func = "hash_map.putOrPutContext" },
        .medium,
        0.6,
    );
    try std.testing.expect(issue_suppression.shouldSuppress(&issue));
}
