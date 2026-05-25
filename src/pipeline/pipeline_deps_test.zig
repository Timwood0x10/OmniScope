//! Tests for Pipeline Dependencies — FIX-4: FFI pass dependency correctness
//!
//! Coverage target: ≥70% for all FFI-related pass dependency declarations
//! Test categories: happy path (correct deps), boundary (reasonable counts), regression (not empty)

const std = @import("std");

// Import all FFI-related passes
const PtrLifetimePass = @import("../pass/analysis/ptr_lifetime/ptr_lifetime.zig").PtrLifetimePass;
const FFIBoundaryPass = @import("../pass/analysis/ffi/ffi_boundary.zig").FFIBoundaryPass;
const CallbackEscapePass = @import("../pass/analysis/callback_escape.zig").CallbackEscapePass;
const DangerSurfacePass = @import("../pass/analysis/danger_surface.zig").DangerSurfacePass;
const FFITypeMismatchPass = @import("../pass/analysis/ffi/ffi_type_mismatch.zig").FFITypeMismatchPass;

const PassKind = @import("../pass/pass.zig").PassKind;

// ============================================================================
// FIX-4 Core: All FFI passes must declare correct dependencies
// ============================================================================

test "PtrLifetimePass - depends on call-graph only (v0.1.9 circular dep fix)" {
    // v0.1.9: Removed danger-surface dependency to break circular dependency.
    // Execution order: call-graph → ptr-lifetime → danger-surface → ffi_boundary.
    // ptr-lifetime no longer needs danger-surface to run first — it populates
    // MemoryGraph independently, and danger-surface consumes it afterwards.
    const deps = PtrLifetimePass.deps;

    // Must have exactly 1 dependency (call-graph only)
    try std.testing.expectEqual(@as(usize, 1), deps.len, "ptr_lifetime should have 1 dependency");

    var has_call_graph = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
    }

    try std.testing.expect(has_call_graph, "ptr_lifetime must depend on call-graph");
}

test "FFIBoundaryPass - depends on call-graph and danger-surface (FIX-4 happy path)" {
    const deps = FFIBoundaryPass.deps;

    try std.testing.expect(deps.len >= 2, "ffi_boundary should have at least 2 dependencies");

    var has_call_graph = false;
    var has_danger_surface = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
        if (std.mem.eql(u8, dep, "danger-surface")) has_danger_surface = true;
    }

    try std.testing.expect(has_call_graph, "ffi_boundary must depend on call-graph");
    try std.testing.expect(has_danger_surface, "ffi_boundary must depend on danger-surface");
}

test "CallbackEscapePass - depends on call-graph and danger-surface (FIX-4 happy path)" {
    const deps = CallbackEscapePass.deps;

    try std.testing.expect(deps.len >= 2, "callback_escape should have at least 2 dependencies");

    var has_call_graph = false;
    var has_danger_surface = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
        if (std.mem.eql(u8, dep, "danger-surface")) has_danger_surface = true;
    }

    try std.testing.expect(has_call_graph, "callback_escape must depend on call-graph");
    try std.testing.expect(has_danger_surface, "callback_escape must depend on danger-surface");
}

test "DangerSurfacePass - depends on call-graph and ptr-lifetime (v0.1.9 happy path)" {
    // v0.1.9: Added ptr-lifetime dependency to ensure MemoryGraph is populated
    // before DangerSurfacePass reads it. This eliminates the Phase 0 fallback
    // that was needed when MemoryGraph was empty.
    const deps = DangerSurfacePass.deps;

    try std.testing.expectEqual(@as(usize, 2), deps.len, "danger_surface should have 2 dependencies");

    var has_call_graph = false;
    var has_ptr_lifetime = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
        if (std.mem.eql(u8, dep, "ptr-lifetime")) has_ptr_lifetime = true;
    }

    try std.testing.expect(has_call_graph, "danger_surface must depend on call-graph");
    try std.testing.expect(has_ptr_lifetime, "danger_surface must depend on ptr-lifetime (MemoryGraph)");
}

test "FFITypeMismatchPass - depends on call-graph (FIX-2 + FIX-4)" {
    // Verified in FIX-2 test, but re-check here for completeness
    const deps = FFITypeMismatchPass.deps;

    try std.testing.expect(deps.len >= 1, "ffi_type_mismatch must have at least 1 dependency");

    var has_call_graph = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
    }

    try std.testing.expect(has_call_graph, "ffi_type_mismatch must depend on call-graph");
}

// ============================================================================
// Regression prevention: No FFI pass should have empty deps
// ============================================================================

test "Regression - no FFI pass has empty deps (regression test)" {
    // Before FIX-2/FIX-4, several FFI passes had empty deps arrays
    // This caused fragile execution order dependent on registration order

    try std.testing.expect(PtrLifetimePass.deps.len > 0, "ptr_lifetime deps should not be empty");
    try std.testing.expect(FFIBoundaryPass.deps.len > 0, "ffi_boundary deps should not be empty");
    try std.testing.expect(CallbackEscapePass.deps.len > 0, "callback_escape deps should not be empty");
    try std.testing.expect(DangerSurfacePass.deps.len > 0, "danger_surface deps should not be empty");
    try std.testing.expect(FFITypeMismatchPass.deps.len > 0, "ffi_type_mismatch deps should not be empty");
}

// ============================================================================
// Boundary: Dependency count sanity check
// ============================================================================

test "Boundary - FFI pass dependency count is reasonable (boundary)" {
    // Each FFI pass should have 1-3 dependencies (not 0, not excessive)
    const max_reasonable_deps: usize = 5;

    try std.testing.expect(PtrLifetimePass.deps.len <= max_reasonable_deps);
    try std.testing.expect(FFIBoundaryPass.deps.len <= max_reasonable_deps);
    try std.testing.expect(CallbackEscapePass.deps.len <= max_reasonable_deps);
    try std.testing.expect(DangerSurfacePass.deps.len <= max_reasonable_deps);
    try std.testing.expect(FFITypeMismatchPass.deps.len <= max_reasonable_deps);
}

// ============================================================================
// Pass kind verification
// ============================================================================

test "FFI passes have correct kinds (coverage)" {
    try std.testing.expectEqual(PassKind.analysis, PtrLifetimePass.kind);
    try std.testing.expectEqual(PassKind.foundation, FFIBoundaryPass.kind);
    try std.testing.expectEqual(PassKind.analysis, CallbackEscapePass.kind);
    try std.testing.expectEqual(PassKind.analysis, DangerSurfacePass.kind);
    try std.testing.expectEqual(PassKind.analysis, FFITypeMismatchPass.kind);
}
