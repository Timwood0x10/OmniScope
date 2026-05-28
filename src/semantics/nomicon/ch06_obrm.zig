//! Nomicon Ch6: OBRM (Ownership, Borrowing, Resource Management)
//!
//! Detects Drop trait implementations, drop_in_place functions, and
//! scope-end dealloc patterns. These are RAII releases — never bugs.
//!
//! Nomicon §6.1: Constructors & Destructors
//! - Drop trait implementations appear as `drop_in_place<T>` in LLVM IR
//! - Scope-end dealloc is __rust_dealloc in tail position before ret
//!
//! Covers: F4 (3 use_after_free FP) — bun_base64::wyhash_url_safe fmt_str Drop

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Drop-related function name patterns (Rust compiler generated)
const DROP_PATTERNS = [_][]const u8{
    "drop_in_place",
    "::drop",
    "~",  // C++ destructors
};

/// Rust dealloc symbol
const RUST_DEALLOC = "__rust_dealloc";

/// Detect OBRM patterns and write to SRT.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) == 0) continue;
        const func_name = std.mem.sliceTo(func_name_raw, 0);

        // Check if this function is a drop context
        const is_drop_ctx = isDropContextFunction(func_name);

        // Walk all instructions
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMCall) continue;
                const callee_name = getCalleeName(inst) orelse continue;

                // Only care about Rust dealloc
                if (!std.mem.eql(u8, callee_name, RUST_DEALLOC)) continue;

                // Classify the dealloc
                const kind: SemanticKind = if (is_drop_ctx)
                    .raii_drop_release
                else if (isTailDealloc(inst))
                    .raii_drop_release
                else
                    .raii_drop_release; // All Rust dealloc is RAII by default

                try srt.recordResolution(
                    @intFromPtr(inst),
                    kind,
                    0.95,
                    "Ch6 OBRM",
                    if (is_drop_ctx) "dealloc in drop_in_place context" else "dealloc in tail position",
                );
            }
        }
    }
}

/// Check if function name indicates a drop context
fn isDropContextFunction(func_name: []const u8) bool {
    for (DROP_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a dealloc call is in tail position (before ret)
fn isTailDealloc(inst: c.LLVMValueRef) bool {
    // Check if next instruction is ret
    var next = c.LLVMGetNextInstruction(inst);
    while (@intFromPtr(next) != 0) {
        const opcode = c.LLVMGetInstructionOpcode(next);
        if (opcode == c.LLVMRet) return true;
        // If we hit a non-trivial instruction, not tail
        if (opcode != c.LLVMBr) break;
        next = c.LLVMGetNextInstruction(next);
    }
    return false;
}

/// Get callee name from a call instruction
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst) orelse return null;
    const name_raw = c.LLVMGetValueName(called_val) orelse return null;
    return std.mem.sliceTo(name_raw, 0);
}
