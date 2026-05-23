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
