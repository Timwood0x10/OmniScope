//! Nomicon Ch4: Conversions
//!
//! Placeholder for transmute, repr(C), from_raw patterns.
//! No direct bun FP coverage — reserved for future use.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

pub fn detect(
    _module: c.LLVMModuleRef,
    _srt: *SemanticTree,
    _diag: *DiagnosticWriter,
) !void {
    // Placeholder — no bun FP coverage yet
}
