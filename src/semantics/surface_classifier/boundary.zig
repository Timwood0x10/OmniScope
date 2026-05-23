//! Surface Classifier — Layer 4: Boundary Detection
//!
//! Detects cross-language / FFI boundary functions using:
//!   - Exported symbols (external linkage + defined body)
//!   - CrossLangEdge presence (populated by CallGraphPass in Phase 2)
//!
//! Boundary functions are always preserved regardless of L1/L2 signals.

const c = @import("../../ir/llvm_raw.zig").c;

/// Detect if a function is an FFI boundary from its LLVM properties.
///
/// Lightweight check — no instruction scanning required.
/// Signals:
///   - External linkage + defined body (exported API entry point)
pub fn detectBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    // Declarations are not boundaries themselves (callee side)
    if (c.LLVMIsDeclaration(func) != 0) return false;

    const linkage = c.LLVMGetLinkage(func);

    // Externally visible defined function — potential API entry point
    if (linkage == c.LLVMExternalLinkage) return true;

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "detectBoundaryFromLLVM - design constraints" {
    // Boundary detection relies on LLVM function properties:
    // - External linkage + defined body → potential API entry point (boundary)
    // - Declarations (no body) → not boundary themselves
    // - Internal/linkonce linkage → not externally visible → not boundary
    //
    // Full integration testing requires LLVM IR module construction,
    // which is covered by surface_classifier_pass integration tests.
    // This test documents the design constraints.
    const is_declaration: bool = true;
    const is_external_linkage: bool = true;
    // A declaration cannot be a boundary (it has no body)
    try @import("std").testing.expect(!(is_declaration and is_external_linkage));
}
