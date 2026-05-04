//! Tests for Pipeline Dependencies — FIX-4: FFI pass dependency correctness
//!
//! Coverage target: ≥70% for all FFI-related pass dependency declarations
//! Test categories: happy path (correct deps), boundary (reasonable counts), regression (not empty)

const std = @import("std");

// Import all FFI-related passes
const PtrLifetimePass = @import("ptr_lifetime.zig").PtrLifetimePass;
const FFIBoundaryPass = @import("ffi_boundary.zig").FFIBoundaryPass;
const CallbackEscapePass = @import("callback_escape.zig").CallbackEscapePass;
const DangerSurfacePass = @import("danger_surface.zig").DangerSurfacePass;
const FFITypeMismatchPass = @import("ffi_type_mismatch.zig").FFITypeMismatchPass;

const PassKind = @import("../pass.zig").PassKind;

// ============================================================================
// FIX-4 Core: All FFI passes must declare correct dependencies
// ============================================================================

test "PtrLifetimePass - depends on call-graph and danger-surface (FIX-4 happy path)" {
    // CRITICAL: After FIX-4, ptr_lifetime must depend on:
    // - call-graph: provides CrossLangEdges for Rust FFI detection
    // - danger-surface: provides relevant function markers
    const deps = PtrLifetimePass.deps;

    // Must have exactly 2 dependencies
    try std.testing.expectEqual(@as(usize, 2), deps.len, "ptr_lifetime should have 2 dependencies");

    // Verify call-graph is declared
    var has_call_graph = false;
    var has_danger_surface = false;
    for (deps) |dep| {
        if (std.mem.eql(u8, dep, "call-graph")) has_call_graph = true;
        if (std.mem.eql(u8, dep, "danger-surface")) has_danger_surface = true;
    }

    try std.testing.expect(has_call_graph, "ptr_lifetime must depend on call-graph");
    try std.testing.expect(has_danger_surface, "ptr_lifetime must depend on danger-surface");
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

test "DangerSurfacePass - depends on call-graph and ptr-lifetime (FIX-4 happy path)" {
    // CRITICAL: danger_surface needs MemoryGraph from ptr_lifetime to be populated first
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
