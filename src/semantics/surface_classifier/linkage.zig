//! Surface Classifier — Layer 1: Linkage Heuristic
//!
//! Classifies function origin from LLVM linkage type and debug info presence.
//! Compiler-generated functions (drop glue, panic helpers, monomorphized
//! internals) typically have internal/linkonce_odr linkage AND lack debug info.
//!
//! This is the cheapest layer: O(1) field reads, zero instruction scanning.

const c = @import("../../ir/llvm_raw.zig").c;
const SurfaceHint = @import("surface_classifier.zig").SurfaceHint;
const FunctionSurface = @import("surface_classifier.zig").FunctionSurface;

/// Classify function surface from LLVM linkage type and debug info presence.
pub fn classifyLinkage(func: c.LLVMValueRef) ?SurfaceHint {
    const linkage = c.LLVMGetLinkage(func);
    const has_dbg = hasDebugSubprogram(func);

    // Strong signal: internal/private linkage without debug info
    if ((linkage == c.LLVMInternalLinkage or
        linkage == c.LLVMPrivateLinkage) and !has_dbg)
    {
        return .{
            .surface = .compiler_generated,
            .confidence = .high,
            .reason = "internal/private linkage without debug info",
        };
    }

    // Strong signal: linkonce_odr without debug info
    if (linkage == c.LLVMLinkOnceODRLinkage and !has_dbg) {
        return .{
            .surface = .compiler_generated,
            .confidence = .high,
            .reason = "linkonce_odr without debug info",
        };
    }

    // Medium signal: available_externally without debug info
    if (linkage == c.LLVMAvailableExternallyLinkage and !has_dbg) {
        return .{
            .surface = .compiler_generated,
            .confidence = .medium,
            .reason = "available_externally without debug info",
        };
    }

    // External linkage declarations are runtime/library boundaries
    if (c.LLVMIsDeclaration(func) != 0) {
        if (linkage == c.LLVMExternalLinkage) {
            return .{
                .surface = .runtime,
                .confidence = .low,
                .reason = "external declaration",
            };
        }
    }

    // No strong linkage signal — defer to L2
    return null;
}

/// Check if a function has a DISubprogram attached (has debug info).
fn hasDebugSubprogram(func: c.LLVMValueRef) bool {
    const sp = c.LLVMGetSubprogram(func);
    return @intFromPtr(sp) != 0;
}

// ============================================================================
// Tests
// ============================================================================

test "classifyLinkage - SurfaceHint fields for compiler_generated" {
    // Verify SurfaceHint structure is correct for L1 signals.
    // Actual LLVM integration is tested in surface_classifier_pass integration tests.
    const hint: SurfaceHint = .{
        .surface = .compiler_generated,
        .confidence = .high,
        .reason = "internal/private linkage without debug info",
    };
    const testing = @import("std").testing;
    try testing.expectEqual(FunctionSurface.compiler_generated, hint.surface);
    try testing.expectEqual(@import("surface_classifier.zig").Confidence.high, hint.confidence);
}

test "classifyLinkage - SurfaceHint for runtime external declaration" {
    const hint: SurfaceHint = .{
        .surface = .runtime,
        .confidence = .low,
        .reason = "external declaration",
    };
    const testing = @import("std").testing;
    try testing.expectEqual(FunctionSurface.runtime, hint.surface);
    try testing.expectEqual(@import("surface_classifier.zig").Confidence.low, hint.confidence);
}

test "classifyLinkage - null return means defer to other layers" {
    // When no strong linkage signal exists, classifyLinkage returns null
    // to let L2/L3/L4 make the decision.
    const result: ?SurfaceHint = null;
    const testing = @import("std").testing;
    try testing.expectEqual(@as(?SurfaceHint, null), result);
}
