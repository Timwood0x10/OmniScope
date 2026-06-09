//! Issue Gate + into_raw Transfer Tests
//!
//! Validates correct behavior of R-6 (into_raw_transfer) markers in the issue gate:
//!
//! Core scenarios:
//!   - After Rust calls Box::into_raw(), pointer ownership transfers to the caller
//!   - If C side calls free(), this is a legitimate ownership transfer → should suppress
//!   - But if the pointer is neither passed to C free nor released in Rust → real memory leak → should NOT suppress
//!
//! Test coverage:
//!   A: into_raw + cross_language_free → suppress_ownership_transfer (legitimate C free)
//!   B: into_raw + memory_leak → allow (leak must be reported!)
//!   C: into_raw + use_after_free → allow (does not affect other issue types)
//!   D: isIntoRawCall() function correctness

const std = @import("std");
const omniscope = @import("OmniScope");

// ============================================================================
// Test Helpers
// ============================================================================

/// Create a SemanticTree with an into_raw_transfer marker.
/// Returns the tree and the marked value_ref.
fn createIntoRawMarkedTree(allocator: std.mem.Allocator) !struct {
    tree: omniscope.semantics.SemanticTree,
    value_ref: u64,
} {
    var tree = omniscope.semantics.SemanticTree.init(allocator);
    errdefer tree.deinit();

    const value_ref: u64 = 0xDEAD; // Simulated LLVM ValueRef

    // Simulate into_raw_transfer detect() behavior: record resolution
    try tree.recordResolution(
        value_ref,
        .into_raw_transfer,
        0.95,
        "R-6 into_raw",
        "_RNvXs_<core::ptr::unique::Unique<T>>::8into_raw",
    );

    return .{ .tree = tree, .value_ref = value_ref };
}

// ============================================================================
// Test A: into_raw + cross_language_free → suppress_ownership_transfer
// ============================================================================

test "A: into_raw_transfer correctly suppresses cross_language_free" {
    const allocator = std.testing.allocator;

    // Scenario: Rust calls Box::into_raw(), then C calls free()
    // This is a legitimate ownership transfer — should not report cross_language_free
    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    // Check cross_language_free on value with into_raw_transfer marker
    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .cross_language_free);

    // Assert: should return suppress_ownership_transfer (C free is legitimate)
    try std.testing.expectEqual(omniscope.pass.GateVerdict.suppress_ownership_transfer, verdict);

    // Verify reason message
    const reason = omniscope.pass.verdictReason(verdict);
    try std.testing.expect(std.mem.indexOf(u8, reason, "R-6") != null);
    try std.testing.expect(std.mem.indexOf(u8, reason, "into_raw") != null);
}

test "A: into_raw_transfer also correctly suppresses cross_language_leak" {
    const allocator = std.testing.allocator;

    // cross_language_leak and cross_language_free share the same gate branch
    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .cross_language_leak);

    try std.testing.expectEqual(omniscope.pass.GateVerdict.suppress_ownership_transfer, verdict);
}

// ============================================================================
// Test B: into_raw + memory_leak → allow (critical test!)
// ============================================================================

test "B: into_raw_transfer must not suppress memory_leak" {
    const allocator = std.testing.allocator;

    // Scenario: Rust calls Box::into_raw(), then the pointer is neither
    // passed to C free nor released in Rust — this is a real memory leak
    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    // Check memory_leak on the same value
    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .memory_leak);

    // Assert: must return allow! leak must not be suppressed
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

test "B: cross_language_free without into_raw_transfer marker should also allow" {
    const allocator = std.testing.allocator;

    // Control group: plain value without into_raw_transfer marker
    var tree = omniscope.semantics.SemanticTree.init(allocator);
    defer tree.deinit();

    const plain_value: u64 = 0xBEEF;
    // Record a different resolution type (not into_raw_transfer)
    try tree.recordResolution(plain_value, .allocation, 0.90, "normal alloc", "malloc");

    const verdict = omniscope.pass.checkIssue(&tree, plain_value, .cross_language_free);

    // Without into_raw_transfer marker, should not suppress
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

// ============================================================================
// Test C: into_raw does not affect other issue types
// ============================================================================

test "C: into_raw_transfer does not affect use_after_free" {
    const allocator = std.testing.allocator;

    // use_after_free is a completely different bug type — into_raw marker should not affect it
    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .use_after_free);

    // use_after_free is only suppressed by raii_drop_release, not into_raw_transfer
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

test "C: into_raw_transfer does not affect borrow_escape" {
    const allocator = std.testing.allocator;

    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .borrow_escape);

    // borrow_escape is suppressed by heap_provenance / global_provenance / mutable_param
    // into_raw_transfer is not among them
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

test "C: into_raw_transfer does not affect write_to_immutable" {
    const allocator = std.testing.allocator;

    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .write_to_immutable);

    // write_to_immutable is suppressed by mutable_param / interior_mutability
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

test "C: into_raw_transfer does not affect buffer_overflow" {
    const allocator = std.testing.allocator;

    var result = try createIntoRawMarkedTree(allocator);
    defer result.tree.deinit();

    // buffer_overflow is not in any gate rule — always allow
    const verdict = omniscope.pass.checkIssue(&result.tree, result.value_ref, .buffer_overflow);

    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, verdict);
}

// ============================================================================
// Test D: isIntoRawCall unit tests
// ============================================================================

test "D: isIntoRawCall recognizes Rust v0 mangled names" {
    // Rust v0 mangled: _RNvXs_<path>8into_raw
    try std.testing.expect(omniscope.semantics.isIntoRawCall("_RNvXs_<core::ptr::unique::Unique<T>>::8into_raw"));
    try std.testing.expect(omniscope.semantics.isIntoRawCall("_RNvXs_<alloc::boxed::Box<T>>::8into_raw"));
    try std.testing.expect(omniscope.semantics.isIntoRawCall("_RNvXs_<ffi::c_str::CString>>::8into_raw"));
    try std.testing.expect(omniscope.semantics.isIntoRawCall("_RNvXs_<vec::Vec<T>>::8into_raw"));
}

test "D: isIntoRawCall recognizes legacy mangled names" {
    // Legacy mangling: _ZN...into_raw...
    try std.testing.expect(omniscope.semantics.isIntoRawCall("_ZN5alloc3vec::Vec*8into_raw17habcdef123456789E"));
}

test "D: isIntoRawCall rejects non-Rust names" {
    // C/C++ function names containing "into_raw" should not match
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("my_into_raw_function"));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("cpp_into_raw_wrapper"));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("handle_into_raw"));

    // Completely unrelated names
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("malloc"));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("free"));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("memcpy"));
}

test "D: isIntoRawCall rejects empty and short strings" {
    try std.testing.expect(!omniscope.semantics.isIntoRawCall(""));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("into"));
    try std.testing.expect(!omniscope.semantics.isIntoRawCall("raw"));
}

// ============================================================================
// Integration tests: full SRT → Gate pipeline
// ============================================================================

test "integration: leak detection after into_raw — full pipeline" {
    const allocator = std.testing.allocator;

    // Simulate the full scenario:
    // 1. Rust calls Box::into_raw(ptr)
    // 2. Return value is marked as into_raw_transfer
    // 3. Subsequent analysis finds the pointer was never freed
    // 4. memory_leak issue is raised
    // 5. Gate should allow reporting (this is a real leak)

    var tree = omniscope.semantics.SemanticTree.init(allocator);
    defer tree.deinit();

    const raw_ptr: u64 = 0xDEAD_BEEF;

    // Step 1-2: into_raw_transfer detector marks the return value
    try tree.recordResolution(
        raw_ptr,
        .into_raw_transfer,
        0.95,
        "R-6 into_raw",
        "_RNvXs_<alloc::boxed::Box<i32>>::8into_raw",
    );

    // Step 3-4: Analysis finds leak, raises issue check
    // Multiple leak types should all be allowed
    const leak_verdict = omniscope.pass.checkIssue(&tree, raw_ptr, .memory_leak);
    const cross_leak_verdict = omniscope.pass.checkIssue(&tree, raw_ptr, .cross_language_leak);

    // Step 5: Verify results
    // memory_leak must pass (this is critical!)
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, leak_verdict);

    // cross_language_leak is suppressed (C free is legitimate)
    try std.testing.expectEqual(omniscope.pass.GateVerdict.suppress_ownership_transfer, cross_leak_verdict);
}

test "integration: priority behavior with multiple coexisting markers" {
    const allocator = std.testing.allocator;

    // Scenario: same value has multiple semantic markers
    // Verify the gate handles this correctly
    var tree = omniscope.semantics.SemanticTree.init(allocator);
    defer tree.deinit();

    const value_ref: u64 = 0xCAFE_BABE;

    // Mark as both into_raw_transfer and heap_provenance
    try tree.recordResolution(value_ref, .into_raw_transfer, 0.95, "R-6", "into_raw");
    try tree.recordResolution(value_ref, .heap_provenance, 0.90, "R-1", "Box::new");

    // cross_language_free should be suppressed by into_raw_transfer
    const clf_verdict = omniscope.pass.checkIssue(&tree, value_ref, .cross_language_free);
    try std.testing.expectEqual(omniscope.pass.GateVerdict.suppress_ownership_transfer, clf_verdict);

    // borrow_escape should be suppressed by heap_provenance
    const be_verdict = omniscope.pass.checkIssue(&tree, value_ref, .borrow_escape);
    try std.testing.expectEqual(omniscope.pass.GateVerdict.suppress_heap_origin, be_verdict);

    // memory_leak should still allow (no rule suppresses it)
    const ml_verdict = omniscope.pass.checkIssue(&tree, value_ref, .memory_leak);
    try std.testing.expectEqual(omniscope.pass.GateVerdict.allow, ml_verdict);
}
