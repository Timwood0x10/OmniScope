//! FFI Boundary Tuple — Per-function classification result for FFI boundaries.
//!
//! Combines DWARF language evidence, module-level signals, and caller/callee
//! heuristics into a single `BoundaryEvidence` struct. This replaces ad-hoc
//! per-pass re-detection with a unified classification that all downstream
//! passes (ffi_unsafe, ffi_precision, etc.) can rely on.
//!
//! Design:
//!   - One `BoundaryEvidence` per FFI call site (caller→callee edge)
//!   - Confidence is derived from IREvidence.dwarf_lang_map + fallback signals
//!   - If DWARF metadata is available, confidence is higher
//!   - If fallback heuristics are used, confidence is lower

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const IREvidence = @import("../../ir/ir_evidence.zig").IREvidence;
const DWARFSourceLanguage = @import("../../ir/ir_evidence.zig").DWARFSourceLanguage;
const dwarfLangToLanguage = @import("../../ir/ir_evidence.zig").dwarfLangToLanguage;

/// Classification of a single FFI boundary call site.
///
/// Carries the combined evidence from multiple sources so that downstream
/// passes can make consistent decisions without re-running detection.
pub const BoundaryEvidence = struct {
    /// Overall confidence [0.0, 1.0] that this is a cross-language FFI boundary.
    confidence: f32 = 0.0,

    /// Detected language of the callee (the function being called across FFI).
    language: Language = .unknown,

    /// DWARF source language if extracted from debug info.
    dwarf_lang: ?DWARFSourceLanguage = null,

    /// Whether the callee function has debug info (DISubprogram) available.
    has_debug_info: bool = false,

    /// Whether the boundary was classified via DWARF evidence (vs fallback).
    classified_via_dwarf: bool = false,

    /// Human-readable description of how this classification was reached.
    /// Useful for diagnostic output and debugging.
    evidence_description: ?[]const u8 = null,
};

/// Classify an FFI boundary call site using the module-level IREvidence.
///
/// Combines multiple signals:
///   - Primary: per-function DWARF language from `evidence.getDwarfLang(func)`
///   - Fallback: module-level dominant language from `evidence.dominant_language`
///   - Confidence is proportional to signal strength and specificity
///
/// Parameters:
///   - evidence: Module-level IREvidence (from EvidenceCollector)
///   - callee_func: LLVM value ref for the callee function (may be null for declarations)
///   - callee_name: Name of the callee function (used when func ref is unavailable)
///
/// Returns a BoundaryEvidence struct with the combined classification.
pub fn classifyBoundary(
    evidence: *const IREvidence,
    callee_func: ?c.LLVMValueRef,
    callee_name: []const u8,
) BoundaryEvidence {
    // Try DWARF evidence first (most reliable)
    if (callee_func) |func| {
        if (evidence.getDwarfLang(func)) |dwarf_lang| {
            const lang = dwarfLangToLanguage(dwarf_lang);
            const confidence: f32 = if (lang != .unknown) 0.85 else 0.5;
            return .{
                .confidence = confidence,
                .language = lang,
                .dwarf_lang = dwarf_lang,
                .has_debug_info = true,
                .classified_via_dwarf = true,
                .evidence_description = "Per-function DWARF subprogram language",
            };
        }
    }

    // Fallback: use module-level dominant language
    if (evidence.dominant_language != .unknown) {
        // Module-level confidence is lower than per-function DWARF evidence.
        // Scale it by 0.7 to reflect the module-level approximation.
        const scaled_confidence = evidence.confidence * 0.7;
        return .{
            .confidence = scaled_confidence,
            .language = evidence.dominant_language,
            .dwarf_lang = null,
            .has_debug_info = false,
            .classified_via_dwarf = false,
            .evidence_description = "Module-level dominant language (fallback)",
        };
    }

    // No evidence available — return unknown
    return .{
        .confidence = 0.0,
        .language = .unknown,
        .dwarf_lang = null,
        .has_debug_info = false,
        .classified_via_dwarf = false,
        .evidence_description = "No language evidence available",
    };
}

// Unit tests

test "BoundaryEvidence default initialization" {
    const bev = BoundaryEvidence{};
    try std.testing.expectEqual(@as(f32, 0.0), bev.confidence);
    try std.testing.expectEqual(Language.unknown, bev.language);
    try std.testing.expectEqual(@as(?DWARFSourceLanguage, null), bev.dwarf_lang);
    try std.testing.expectEqual(false, bev.has_debug_info);
    try std.testing.expectEqual(false, bev.classified_via_dwarf);
}

test "classifyBoundary with unknown evidence returns unknown" {
    // Evidence with no signals = unknown
    const allocator = std.testing.allocator;
    var evidence = IREvidence.init(allocator);
    defer evidence.deinit();

    const result = classifyBoundary(&evidence, null, "some_function");
    try std.testing.expectEqual(Language.unknown, result.language);
    try std.testing.expectEqual(@as(f32, 0.0), result.confidence);
    try std.testing.expectEqual(false, result.classified_via_dwarf);
}

test "classifyBoundary uses module-level dominant language as fallback" {
    const allocator = std.testing.allocator;
    var evidence = IREvidence.init(allocator);
    defer evidence.deinit();

    // Set up module-level evidence
    evidence.dominant_language = .rust;
    evidence.confidence = 0.8;

    const result = classifyBoundary(&evidence, null, "some_function");
    try std.testing.expectEqual(Language.rust, result.language);
    // Module-level scaled by 0.7: 0.8 * 0.7 = 0.56
    try std.testing.expectEqual(@as(f32, 0.56), result.confidence);
    try std.testing.expectEqual(false, result.classified_via_dwarf);
}
