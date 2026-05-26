//! Surface Classifier — Language-Agnostic Function Surface Classification
//!
//! Replaces the name-based whitelist approach in noise_filter.zig with
//! a provenance-based classification system. Shared across all passes
//! via PassContext.function_surface.
//!
//! Layers:
//!   L1 — Linkage Heuristic (surface_classifier_linkage.zig)
//!   L2 — Debug Origin / Source Path Provenance (surface_classifier_debug.zig)
//!   L3 — CallGraph Reachability (surface_classifier_callgraph.zig, invoked by pass)
//!
//! This file defines the canonical types and the merge logic.

const std = @import("std");
const linkage = @import("surface_classifier/linkage.zig");
const debug_origin = @import("surface_classifier/debug_origin.zig");

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

const c = @import("../ir/llvm_raw.zig").c;
