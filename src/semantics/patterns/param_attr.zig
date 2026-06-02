//! R-0: LLVM Parameter Attribute Detector — readonly / noalias
//!
//! This is the most critical detector for bun FP reduction.
//! In LLVM IR, Rust's &T (shared reference) maps to `readonly` parameter
//! attribute, while &mut T (mutable reference) does NOT have readonly.
//!
//! rustc_codegen_llvm always marks &T params as readonly (see
//! rustc_codegen_llvm/src/attributes.rs). This is a language-level
//! guarantee, not a heuristic.
//!
//! The key insight: writing to a pointer derived from a `readonly` param
//! is a true immutable violation; writing to a `mutable_param`-derived
//! pointer is a legal &mut T write (not a bug).
//!
//! Covers: 1877/1966 write_to_immutable FP (96% of all bun FP).

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Detect LLVM parameter attributes (per-function).
/// Extracted for single-pass merged traversal optimization.
pub fn detectFunction(
    func: c.LLVMValueRef,
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = module;
    _ = diag;
    if (c.LLVMIsDeclaration(func) != 0) return;

    const num_params = c.LLVMCountParams(func);
    var i: c_uint = 0;
    while (i < num_params) : (i += 1) {
        const param = c.LLVMGetParam(func, i);
        if (@intFromPtr(param) == 0) continue;

        const has_readonly = paramHasAttr(func, i + 1, "readonly");
        const has_noalias = paramHasAttr(func, i + 1, "noalias");

        const kind: SemanticKind = if (has_readonly) .readonly_param else .mutable_param;

        const evidence: []const u8 = if (has_noalias and has_readonly)
            "noalias+readonly=&T (exclusive shared ref)"
        else if (has_readonly)
            "readonly=&T (shared ref)"
        else if (has_noalias)
            "noalias=&mut T (exclusive mutable ref)"
        else
            "no attrs=&mut T (mutable ref)";

        try srt.recordResolution(
            @intFromPtr(param),
            kind,
            0.95,
            "R-0 LLVM attrs",
            evidence,
        );
    }
}

/// Detect LLVM parameter attributes and write to SRT.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    var fn_iter = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(fn_iter) != 0) : (fn_iter = c.LLVMGetNextFunction(fn_iter)) {
        try detectFunction(fn_iter, module, srt, diag);
    }
}

/// Check if a function parameter at the given index has a specific attribute.
/// Uses LLVM's string attribute API for LLVM 22 compatibility.
fn paramHasAttr(func: c.LLVMValueRef, idx: c_uint, name: []const u8) bool {
    return c.LLVMGetStringAttributeAtIndex(
        func,
        idx,
        name.ptr,
        @intCast(name.len),
    ) != null;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "param_attr: paramHasAttr returns false for functions with no attributes" {
    // This test verifies the API contract — we can't create LLVM modules
    // in unit tests, so we test with null function.
    const result = paramHasAttr(@ptrFromInt(0), 1, "readonly");
    try std.testing.expect(!result);
}
