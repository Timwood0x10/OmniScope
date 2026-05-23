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
