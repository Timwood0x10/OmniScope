//! Surface Classifier — Language-Agnostic Function Surface Classification
//!
//! Replaces the name-based whitelist approach in noise_filter.zig with
//! a provenance-based classification system. Shared across all passes
//! via PassContext.function_surface.
//!
//! Layers (ordered by cost, cheapest first):
//!   L0 — Mangled Name Heuristic (mangled_name.zig) — pure string match
//!   L1 — Linkage Heuristic (linkage.zig) — O(1) LLVM field read
//!   L2 — Debug Origin / Source Path Provenance (debug_origin.zig)
//!   L3 — CallGraph Reachability (callgraph.zig, invoked by pass)
//!   L4 — Boundary Detection (boundary.zig, invoked by pass)
//!
//! This file defines the canonical types and the merge logic.

const std = @import("std");
const linkage = @import("linkage.zig");
const debug_origin = @import("debug_origin.zig");
const mangled_name = @import("mangled_name.zig");
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

pub const classifyMangledName = mangled_name.classifyMangledName;
pub const classifyMangledNameDiagnostic = mangled_name.classifyMangledNameDiagnostic;
pub const classifyLinkage = linkage.classifyLinkage;
pub const classifyDebugOrigin = debug_origin.classifyDebugOrigin;
pub const classifyDebugOriginDiagnostic = debug_origin.classifyDebugOriginDiagnostic;
pub const classifySourcePath = debug_origin.classifySourcePath;
pub const detectBoundaryFromLLVM = @import("boundary.zig").detectBoundaryFromLLVM;

// ============================================================================
// Five-Layer Merge
// ============================================================================

/// Merge classification hints from L0+L1+L2 layers into a final decision.
///
/// Decision priority (highest wins):
///   1. boundary (L4) — overrides everything
///   2. L0/L1/L2 skip surfaces when not reachable — suppress analysis
///   3. L2 user_code/dependency/boundary when reachable — preserve
///   4. L0/L1 skip surfaces even when reachable — trust name/linkage over default
///   5. else → unknown (conservative: keep for analysis)
///
/// Key fix vs. old behavior: L0/L1 compiler_generated is respected even
/// when reachable=true, preventing stdlib functions from being misclassified
/// as user_code when debug info is absent.
pub fn mergeLayers(
    l0: ?SurfaceHint,
    l1: ?SurfaceHint,
    l2: ?SurfaceHint,
    is_reachable: ?bool,
    is_boundary: bool,
) FunctionSurface {
    // Boundary signal overrides everything
    if (is_boundary) return .boundary;

    // Collect the strongest skip signal from L0→L1→L2 (first non-null wins)
    const skip_signal = strongestSkipSignal(l0) orelse
        strongestSkipSignal(l1) orelse
        strongestSkipSignal(l2);

    const reachable = is_reachable orelse true;

    // When reachable and L2 gives a positive ID (user/dep/boundary), use it
    if (reachable and l2 != null) {
        const hint = l2.?;
        if (hint.surface == .user_code or
            hint.surface == .dependency or
            hint.surface == .boundary)
        {
            return hint.surface;
        }
        // L2 says skip → check if L0/L1 also agree on skip
        if (skip_signal) |skip| {
            return skip.surface;
        }
    }

    // When not reachable, any skip signal wins
    if (!reachable and skip_signal != null) {
        return skip_signal.?.surface;
    }

    // When reachable but no L2 positive ID:
    // Trust L0/L1 skip signals over blind user_code default.
    // This is the critical fix: drop_in_place shouldn't become user_code.
    if (reachable and skip_signal != null) {
        return skip_signal.?.surface;
    }

    // No strong signal → conservative keep
    return .unknown;
}

/// Extract a skip-surface hint from a layer result, if it indicates
/// the function should be suppressed (stdlib / compiler_generated / runtime).
fn strongestSkipSignal(hint: ?SurfaceHint) ?SurfaceHint {
    if (hint) |h| {
        if (h.surface == .standard_library or
            h.surface == .compiler_generated or
            h.surface == .runtime)
        {
            return h;
        }
    }
    return null;
}

// ============================================================================
// Convenience: Full Classification (L0 + L1 + L2, no L3)
// ============================================================================

/// Classify a single function using L0 + L1 + L2 layers.
/// Used when callgraph reachability is not yet available (early pipeline).
pub fn classifyFunction(func: c.LLVMValueRef, func_name: []const u8, is_boundary: bool) FunctionSurface {
    const l0 = mangled_name.classifyMangledName(func_name);
    const l1 = linkage.classifyLinkage(func);
    const l2 = debug_origin.classifyDebugOrigin(func);
    return mergeLayers(l0, l1, l2, true, is_boundary);
}

// ============================================================================
// Tests
// ============================================================================

test "strongestSkipSignal - extracts only skip surfaces" {
    const gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };
    const user: SurfaceHint = .{ .surface = .user_code, .confidence = .high, .reason = "test" };
    const stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };

    // strongestSkipSignal takes ?SurfaceHint (value), not *SurfaceHint (pointer)
    try std.testing.expect(strongestSkipSignal(gen) != null);
    try std.testing.expect(strongestSkipSignal(user) == null);
    try std.testing.expect(strongestSkipSignal(stdlib) != null);
    try std.testing.expect(strongestSkipSignal(null) == null);
}

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
    const l0_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "test" };
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "test" };

    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(l0_stdlib, l1_gen, null, false, true));
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(null, null, null, false, true));
    try std.testing.expectEqual(FunctionSurface.boundary, mergeLayers(null, null, null, true, true));
}

test "mergeLayers - L0/L1 skip signal respected when reachable (key fix)" {
    // Before fix: L1=COMPILER_GEN + reachable=true → USER_CODE (bug)
    // After fix:  L1=COMPILER_GEN + reachable=true → COMPILER_GEN (correct)
    const l0_null: ?SurfaceHint = null;
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "internal linkage no dbg" };
    const l2_null: ?SurfaceHint = null;

    try std.testing.expectEqual(
        FunctionSurface.compiler_generated,
        mergeLayers(l0_null, l1_gen, l2_null, true, false),
    );
}

test "mergeLayers - L0 skip signal takes priority over blind user_code" {
    // L0 identifies core::ptr::drop_in_place as compiler_generated
    // Even with reachable=true (default), this should stay compiler_generated
    const l0_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "drop_in_place pattern" };
    try std.testing.expectEqual(
        FunctionSurface.compiler_generated,
        mergeLayers(l0_gen, null, null, true, false),
    );
}

test "mergeLayers - L0 stdlib signal respected when reachable" {
    const l0_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "core::fmt" };
    try std.testing.expectEqual(
        FunctionSurface.standard_library,
        mergeLayers(l0_stdlib, null, null, true, false),
    );
}

test "mergeLayers - L2 user_code preserved when reachable" {
    const l2_user: SurfaceHint = .{ .surface = .user_code, .confidence = .high, .reason = "workspace path" };
    try std.testing.expectEqual(FunctionSurface.user_code, mergeLayers(null, null, l2_user, true, false));

    const l2_dep: SurfaceHint = .{ .surface = .dependency, .confidence = .high, .reason = "registry path" };
    try std.testing.expectEqual(FunctionSurface.dependency, mergeLayers(null, null, l2_dep, true, false));
}

test "mergeLayers - not reachable applies suppression" {
    const l0_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "core::fmt" };
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .high, .reason = "internal linkage" };
    const l2_rt: SurfaceHint = .{ .surface = .runtime, .confidence = .high, .reason = "panic" };

    try std.testing.expectEqual(FunctionSurface.standard_library, mergeLayers(l0_stdlib, null, null, false, false));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, mergeLayers(null, l1_gen, null, false, false));
    try std.testing.expectEqual(FunctionSurface.runtime, mergeLayers(null, null, l2_rt, false, false));
}

test "mergeLayers - no signals returns unknown" {
    try std.testing.expectEqual(FunctionSurface.unknown, mergeLayers(null, null, null, false, false));
    try std.testing.expectEqual(FunctionSurface.unknown, mergeLayers(null, null, null, true, false));
}

test "mergeLayers - L0 takes priority over L1 for skip signals" {
    const l0_stdlib: SurfaceHint = .{ .surface = .standard_library, .confidence = .high, .reason = "alloc crate" };
    const l1_gen: SurfaceHint = .{ .surface = .compiler_generated, .confidence = .low, .reason = "internal linkage" };
    // L0 checked first → stdlib wins
    try std.testing.expectEqual(FunctionSurface.standard_library, mergeLayers(l0_stdlib, l1_gen, null, false, false));
}

test "Confidence - ordering" {
    try std.testing.expect(@intFromEnum(Confidence.low) < @intFromEnum(Confidence.medium));
    try std.testing.expect(@intFromEnum(Confidence.medium) < @intFromEnum(Confidence.high));
}
