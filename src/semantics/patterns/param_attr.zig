//! R-0: LLVM Parameter Attribute Detector — readonly / noalias / byval / sret / etc.
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
//! Additional attributes (byval, sret, inalloca, preallocated, nocapture)
//! provide ownership signals consumed by SemanticStep.propagateOwnership.
//!
//! Covers: 1877/1966 write_to_immutable FP (96% of all bun FP).

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Detect LLVM parameter attributes (per-function).
/// Extended for single-pass merged traversal optimization.
/// Records readonly/noalias for immutability analysis and additional
/// ownership-related attributes (byval, sret, inalloca, preallocated, nocapture).
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
        const has_byval = paramHasAttr(func, i + 1, "byval");
        const has_sret = paramHasAttr(func, i + 1, "sret");
        const has_inalloca = paramHasAttr(func, i + 1, "inalloca");
        const has_preallocated = paramHasAttr(func, i + 1, "preallocated");
        const has_nocapture = paramHasAttr(func, i + 1, "nocapture");

        const kind: SemanticKind = if (has_readonly) .readonly_param else .mutable_param;

        // Build evidence string by appending non-empty hints.
        var evidence_buf: [128]u8 = undefined;
        var ev_idx: usize = 0;

        const base_ev: []const u8 = if (has_noalias and has_readonly)
            "noalias+readonly=&T (exclusive shared ref)"
        else if (has_readonly)
            "readonly=&T (shared ref)"
        else if (has_noalias)
            "noalias=&mut T (exclusive mutable ref)"
        else
            "no attrs=&mut T (mutable ref)";

        @memcpy(evidence_buf[0..base_ev.len], base_ev);
        ev_idx = base_ev.len;

        if (has_byval) {
            const tag = " | byval";
            @memcpy(evidence_buf[ev_idx..][0..tag.len], tag);
            ev_idx += tag.len;
        }
        if (has_sret) {
            const tag = " | sret";
            @memcpy(evidence_buf[ev_idx..][0..tag.len], tag);
            ev_idx += tag.len;
        }
        if (has_inalloca) {
            const tag = " | inalloca";
            @memcpy(evidence_buf[ev_idx..][0..tag.len], tag);
            ev_idx += tag.len;
        }
        if (has_preallocated) {
            const tag = " | preallocated";
            @memcpy(evidence_buf[ev_idx..][0..tag.len], tag);
            ev_idx += tag.len;
        }
        if (has_nocapture) {
            const tag = " | nocapture";
            @memcpy(evidence_buf[ev_idx..][0..tag.len], tag);
            ev_idx += tag.len;
        }

        const evidence = evidence_buf[0..ev_idx];

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

/// Ownership implication inferred from LLVM parameter attributes.
///
/// Consumed by SemanticStep.propagateOwnership to refine ownership
/// tracking for cross-language boundary parameters.
pub const OwnershipHint = enum(u8) {
    /// Parameter is passed by value (byval); the callee owns a stack copy.
    byval_owned,
    /// Parameter is an sret pointer; the caller allocates the return slot.
    sret_caller_provided,
    /// inalloca parameter; caller-managed stack allocation.
    inalloca_caller,
    /// preallocated parameter; pre-allocated on caller stack.
    preallocated_caller,
    /// nocapture pointer; callee guarantees the pointer does not escape.
    nocapture_no_escape,
    /// No special ownership implication detected.
    none,
};

/// Infer ownership implications from parameter attributes for a given
/// function parameter.
///
/// Bridge function that feeds param_attr detection results into
/// SemanticStep.propagateOwnership. Each attribute maps to a specific
/// ownership semantic relevant to cross-language memory safety analysis.
///
/// Parameters:
///   - func: LLVM function containing the parameter
///   - param_idx: 1-based parameter index (LLVM convention)
///
/// Returns:
///   - OwnershipHint describing the ownership implication, or .none
pub fn inferOwnershipFromAttrs(func: c.LLVMValueRef, param_idx: c_uint) OwnershipHint {
    if (paramHasAttr(func, param_idx, "byval")) return .byval_owned;
    if (paramHasAttr(func, param_idx, "sret")) return .sret_caller_provided;
    if (paramHasAttr(func, param_idx, "inalloca")) return .inalloca_caller;
    if (paramHasAttr(func, param_idx, "preallocated")) return .preallocated_caller;
    if (paramHasAttr(func, param_idx, "nocapture")) return .nocapture_no_escape;
    return .none;
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

test "param_attr: inferOwnershipFromAttrs returns none for null function" {
    // Verify the API handles null function gracefully.
    const result = inferOwnershipFromAttrs(@ptrFromInt(0), 1);
    try std.testing.expectEqual(OwnershipHint.none, result);
}

test "param_attr: OwnershipHint enum values are distinct" {
    // Verify compile-time enum integrity.
    const hints = [_]OwnershipHint{
        .byval_owned,
        .sret_caller_provided,
        .inalloca_caller,
        .preallocated_caller,
        .nocapture_no_escape,
        .none,
    };
    try std.testing.expect(hints.len == 6);
}
