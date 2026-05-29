//! R-6: Ownership Transfer Detector — Box/CString/Vec::into_raw
//!
//! When Rust code calls Box::into_raw(), CString::into_raw(), or
//! Vec::into_raw(), ownership of the underlying memory is explicitly
//! transferred to the caller. Subsequent C free() on that pointer
//! is a legitimate ownership transfer, not a cross-language free bug.
//!
//! In LLVM IR, these appear as calls to Rust v0-mangled functions
//! whose name ends with "into_raw" (e.g., _RNvXs_*Box*8into_raw).
//!
//! Covers: 4/1966 cross_language_free FP + real Rust↔C ownership patterns.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Patterns that indicate ownership transfer (into_raw variants).
/// All Rust into_raw methods contain this substring in their mangled name.
const INTO_RAW_PATTERNS = [_][]const u8{
    "8into_raw", // Rust v0 mangling: 8into_raw (length-prefixed)
    "into_raw", // Fallback for legacy or demangled names
};

/// Detect into_raw ownership transfer calls and write to SRT.
/// Pattern: %raw = call ptr @<mangled_name>_into_raw(...)
/// The return value of into_raw is the transferred raw pointer.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMCall) continue;

                const callee_name = getCalleeName(inst) orelse continue;
                if (!isIntoRawCall(callee_name)) continue;

                // The return value of into_raw is the transferred pointer.
                // Mark both the call instruction AND the return value.
                try srt.recordResolution(
                    @intFromPtr(inst),
                    .into_raw_transfer,
                    0.95,
                    "R-6 into_raw",
                    callee_name,
                );

                // Also mark the function argument (the Box/CString being consumed)
                // The first argument (operand 0) is the box value being converted
                const num_operands = c.LLVMGetNumOperands(inst);
                if (num_operands >= 2) {
                    const box_arg = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(box_arg) != 0) {
                        try srt.recordResolution(
                            @intFromPtr(box_arg),
                            .into_raw_transfer,
                            0.90,
                            "R-6 into_raw arg",
                            "Box/CString consumed by into_raw",
                        );
                    }
                }
            }
        }
    }
}

/// Check if a callee name indicates an into_raw ownership transfer.
/// Must be a Rust-mangled name containing "into_raw".
pub fn isIntoRawCall(name: []const u8) bool {
    // Must contain "into_raw" somewhere
    var found = false;
    for (INTO_RAW_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            found = true;
            break;
        }
    }
    if (!found) return false;

    // Verify it's a Rust mangled name (starts with _R or contains Rust patterns)
    // This prevents false positives from C/C++ functions that happen to contain "into_raw"
    if (std.mem.startsWith(u8, name, "_R")) return true; // Rust v0 mangling
    if (std.mem.startsWith(u8, name, "_ZN")) { // Rust legacy mangling
        // Rust legacy names often end with a 16-hex hash before E
        if (std.mem.indexOf(u8, name, "into_raw") != null) return true;
    }

    return false;
}

/// Get callee name from a call instruction.
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_raw = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_raw) == 0) return null;
    const name = std.mem.sliceTo(name_raw, 0);
    if (name.len == 0) return null;
    return name;
}
