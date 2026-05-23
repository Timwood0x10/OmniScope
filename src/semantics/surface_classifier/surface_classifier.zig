//! Surface Classifier — Language-Agnostic Function Surface Classification
//!
//! Replaces the name-based whitelist approach in noise_filter.zig with
//! a provenance-based classification system. Shared across all passes
//! via PassContext.function_surface.
//!
//! Layers:
//!   L1 — Linkage Heuristic (linkage.zig)
//!   L2 — Debug Origin / Source Path Provenance (debug_origin.zig)
//!   L3 — CallGraph Reachability (callgraph.zig, invoked by pass)
//!   L4 — Boundary Detection (boundary.zig, invoked by pass)
//!
//! This file defines the canonical types and the merge logic.

const std = @import("std");
const linkage = @import("linkage.zig");
const debug_origin = @import("debug_origin.zig");
const c = @import("../../ir/llvm_raw.zig").c;

// ============================================================================
// Public Types
// ============================================================================

/// Canonical function surface classification.
/// Shared across all passes via PassContext.function_surface.
pub const FunctionSurface = enum(u8) {
    /// User-written code — always analyze.
    user_code,
    /// Third-party dependency — analyze but lower priority.
    dependency,
    /// FFI / cross-language boundary — always preserve.
    boundary,
    /// Standard library — skip by default.
    standard_library,
    /// Compiler-generated glue (drop glue, shims, panic) — skip.
    compiler_generated,
    /// Language runtime internals — skip.
    runtime,
    /// Cannot determine — keep for analysis (safe default).
    unknown,

    pub fn toString(self: FunctionSurface) []const u8 {
        return switch (self) {
            .user_code => "USER_CODE",
            .dependency => "DEPENDENCY",
            .boundary => "BOUNDARY",
            .standard_library => "STDLIB",
            .compiler_generated => "COMPILER_GEN",
            .runtime => "RUNTIME",
            .unknown => "UNKNOWN",
        };
    }

    /// Should functions of this surface be analyzed by default?
    pub fn shouldAnalyze(self: FunctionSurface) bool {
        return switch (self) {
            .user_code, .dependency, .boundary, .unknown => true,
            .standard_library, .compiler_generated, .runtime => false,
        };
    }
};

/// Confidence level for a classification hint.
pub const Confidence = enum(u8) { low, medium, high };

/// Intermediate result from a single classification layer.
/// Each layer produces hints; the final decision merges all layers.
pub const SurfaceHint = struct {
    surface: FunctionSurface,
    confidence: Confidence,
    reason: []const u8,
};

// ============================================================================
// Re-exports from sub-modules
// ============================================================================

pub const classifyLinkage = linkage.classifyLinkage;
pub const classifyDebugOrigin = debug_origin.classifyDebugOrigin;
pub const classifySourcePath = debug_origin.classifySourcePath;
pub const detectBoundaryFromLLVM = @import("boundary.zig").detectBoundaryFromLLVM;

// ============================================================================
// Three-Layer Merge
// ============================================================================

/// Merge classification hints from all three layers into a final decision.
///
/// Decision logic:
///   - boundary overrides everything (L4 signal is strongest)
///   - L3 reachable → override skip signals from L1/L2
///   - L2 stdlib/generated + L3 not_reachable → skip
///   - L1 generated + L3 not_reachable → skip
///   - else → unknown (conservative: keep for analysis)
pub fn mergeLayers(
    l1: ?SurfaceHint,
    l2: ?SurfaceHint,
    is_reachable: ?bool,
    is_boundary: bool,
) FunctionSurface {
    // Boundary signal overrides everything
    if (is_boundary) return .boundary;

    const reachable = is_reachable orelse true; // default: keep if unknown

    // L3 reachable → override any skip signal from L1/L2
    if (reachable) {
        if (l2) |hint| {
            if (hint.surface == .user_code or hint.surface == .dependency or hint.surface == .boundary) {
                return hint.surface;
            }
        }
        return .user_code;
    }

    // Not reachable — apply L1/L2 suppression signals
    if (l2) |hint| {
        if (hint.surface == .standard_library or
            hint.surface == .compiler_generated or
            hint.surface == .runtime)
        {
            return hint.surface;
        }
    }

    if (l1) |hint| {
        if (hint.surface == .compiler_generated or hint.surface == .runtime) {
            return hint.surface;
        }
    }

    // No strong signal → conservative keep
    return .unknown;
}

// ============================================================================
// Convenience: Full Classification (L1 + L2, no L3)
// ============================================================================

/// Classify a single function using L1 + L2 layers only.
/// Used when callgraph reachability is not yet available (early pipeline).
pub fn classifyFunction(func: c.LLVMValueRef, is_boundary: bool) FunctionSurface {
    const l1 = linkage.classifyLinkage(func);
    const l2 = debug_origin.classifyDebugOrigin(func);
    return mergeLayers(l1, l2, true, is_boundary);
}

// ============================================================================
// Tests
// ============================================================================

test "FunctionSurface.shouldAnalyze - analyze surfaces" {
    try std.testing.expect(FunctionSurface.user_code.shouldAnalyze());
    try std.testing.expect(FunctionSurface.dependency.shouldAnalyze());
    try std.testing.expect(FunctionSurface.boundary.shouldAnalyze());
    try std.testing.expect(FunctionSurface.unknown.shouldAnalyze());
}

test "FunctionSurface.shouldAnalyze - skip surfaces" {
    try std.testing.expect(!FunctionSurface.standard_library.shouldAnalyze());
    try std.testing.expect(!FunctionSurface.compiler_generated.shouldAnalyze());
    try std.testing.expect(!FunctionSurface.runtime.shouldAnalyze());
}

test "FunctionSurface.toString - all variants" {
    try std.testing.expectEqualStrings("USER_CODE", FunctionSurface.user_code.toString());
    try std.testing.expectEqualStrings("DEPENDENCY", FunctionSurface.dependency.toString());
    try std.testing.expectEqualStrings("BOUNDARY", FunctionSurface.boundary.toString());
    try std.testing.expectEqualStrings("STDLIB", FunctionSurface.standard_library.toString());
    try std.testing.expectEqualStrings("COMPILER_GEN", FunctionSurface.compiler_generated.toString());
    try std.testing.expectEqualStrings("RUNTIME", FunctionSurface.runtime.toString());
    try std.testing.expectEqualStrings("UNKNOWN", FunctionSurface.unknown.toString());
}

test "mergeLayers - boundary overrides everything" {
    const l1_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    const l2_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };

    // Boundary + stdlib hint + not reachable = still boundary
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(l1_stdlib, l2_gen, false, true));
    // Boundary + no hints = still boundary
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(null, null, false, true));
    // Boundary + reachable = still boundary
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(null, null, true, true));
}

test "mergeLayers - reachable overrides skip signals" {
    const l2_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    const l2_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };

    // Reachable + stdlib L2 → user_code (reachable overrides skip)
    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(null, l2_stdlib, true, false));
    // Reachable + generated L2 → user_code
    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(null, l2_gen, true, false));
    // Reachable + generated L1 + no L2 → user_code
    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(l1_gen, null, true, false));
}

test "mergeLayers - reachable with user/dep/boundary L2 preserves L2" {
    const l2_user: SurfaceHint = .{ .surface = .user_code, .confidence = .high, .reason = "test" };
    const l2_dep: SurfaceHint = .{ .surface = .dependency, .confidence = .high, .reason = "test" };
    const l2_bnd: SurfaceHint = .{ .surface = .boundary, .confidence = .high, .reason = "test" };

    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(null, l2_user, true, false));
    try std.testing.expectEqual(FunctionSurface.dependency, mergeLayers(null, l2_dep, true, false));
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(null, l2_bnd, true, false));
}

test "mergeLayers - not reachable applies L2 suppression" {
    const l2_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    const l2_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    const l2_rt: SurfaceHint = .{ .surface = .runtime, .confidence = .high, .reason = "test" };

    try std.testing.expectEqual(FunctionSurface.standard_library, mergeLayers(null, l2_stdlib, false, false));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, mergeLayers(null, l2_gen, false, false));
    try std.testing.expectEqual(FunctionSurface.runtime, mergeLayers(null, l2_rt, false, false));
}

test "mergeLayers - not reachable applies L1 suppression when no L2" {
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    const l1_rt: SurfaceHint = .{ .surface = .runtime, .confidence = .low, .reason = "test" };

    try std.testing.expectEqual(FunctionSurface.compiler_generated, mergeLayers(l1_gen, null, false, false));
    try std.testing.expectEqual(FunctionSurface.runtime, mergeLayers(l1_rt, null, false, false));
}

test "mergeLayers - no strong signal returns unknown" {
    // No hints, not boundary, not reachable → unknown (conservative keep)
    try std.testing.expectEqual(FunctionSurface.unknown, mergeLayers(null, null, false, false));
    // L1 null + L2 null + reachable default (null → true) → user_code
    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(null, null, null, false));
}

test "mergeLayers - L2 user_code with not reachable falls through" {
    // L2 user_code is not a skip signal, so with no L1 skip and not reachable → unknown
    const l2_user: SurfaceHint = .{ .surface = .user_code, .confidence = .high, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.unknown, mergeLayers(null, l2_user, false, false));
}

test "mergeLayers - L1 confidence does not affect outcome" {
    // Low-confidence L1 skip signal should still apply when not reachable
    const l1_gen_low: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .low, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.compiler_generated, mergeLayers(l1_gen_low, null, false, false));
    // High-confidence L1 skip signal
    const l1_gen_high: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.compiler_generated, mergeLayers(l1_gen_high, null, false, false));
}

test "mergeLayers - L2 takes priority over L1 when both present and not reachable" {
    // L1 says runtime, L2 says stdlib → L2 wins (checked first)
    const l1_rt: SurfaceHint = .{ .surface = .runtime, .confidence = .high, .reason = "test" };
    const l2_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.standard_library, mergeLayers(l1_rt, l2_stdlib, false, false));
}

test "mergeLayers - dependency L2 is not a skip signal" {
    // L2 dependency with not reachable → falls through to unknown (not a skip surface)
    const l2_dep: SurfaceHint = .{ .surface = .dependency, .confidence = .high, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.unknown, mergeLayers(null, l2_dep, false, false));
}

test "classifyFunction - boundary function classified correctly" {
    // When is_boundary=true, the result should always be boundary
    // regardless of other signals (cannot test with real LLVM here,
    // but mergeLayers with is_boundary=true covers the logic)
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    const l2_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(l1_gen, l2_stdlib, false, true));
}

test "Confidence - ordering" {
    // Verify confidence enum values for comparison
    try std.testing.expect(@intFromEnum(Confidence.low) < @intFromEnum(Confidence.medium));
    try std.testing.expect(@intFromEnum(Confidence.medium) < @intFromEnum(Confidence.high));
}
