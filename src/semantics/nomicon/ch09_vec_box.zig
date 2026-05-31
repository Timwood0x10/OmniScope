//! Nomicon Ch9: Vec/Box Heap Ownership
//!
//! Fixed-point forward propagation of heap provenance.
//!
//! Strategy: Mark all heap allocations, then propagate provenance through:
//!   - GEP, Load, BitCast, IntToPtr → operand flows to result
//!   - PHI nodes → if any incoming is heap, result is heap
//!   - Call arguments → propagate to callee's parameters
//!   - Store → if storing a heap ptr, the loaded value from that address is heap
//!
//! This is a classic dataflow fixed-point: iterate until no new marks added.
//!
//! Nomicon §9.1-9.3: Vec implementation — internal RawVec<T>{ ptr, cap }
//! Box/Arc/Rc follow the same heap-ownership pattern.
//!

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const log = @import("../../common/log.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Rust/Heap allocation function names
const HEAP_ALLOC_FUNCTIONS = [_][]const u8{
    "__rust_alloc",
    "__rust_alloc_zeroed",
    "malloc",
    "calloc",
    "realloc",
    "aligned_alloc",
    "posix_memalign",
};

fn isHeapAllocFunction(name: []const u8) bool {
    for (HEAP_ALLOC_FUNCTIONS) |alloc_name| {
        if (std.mem.eql(u8, name, alloc_name)) return true;
    }
    return false;
}

fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst) orelse return null;
    const name_raw = c.LLVMGetValueName(called_val) orelse return null;
    return std.mem.sliceTo(name_raw, 0);
}

/// Check if a function returns a heap-provenance value
/// (any ret instruction returns a value marked heap_provenance)
fn functionReturnsHeapProvenance(func: c.LLVMValueRef, srt: *SemanticTree) bool {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (c.LLVMGetInstructionOpcode(inst) != c.LLVMRet) continue;
            if (c.LLVMGetNumOperands(inst) == 0) continue;
            const ret_val = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(ret_val) == 0) continue;
            const ret_ref = @intFromPtr(ret_val);
            if (srt.hasKind(ret_ref, .heap_provenance) != null) {
                return true;
            }
        }
    }
    return false;
}

fn isHeapAllocCall(inst: c.LLVMValueRef) bool {
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;
    const callee_name = getCalleeName(inst) orelse return false;
    return isHeapAllocFunction(callee_name);
}

/// Forward propagate heap provenance through value flows.
/// Returns number of new marks added.
fn propagateHeapProvenance(module: c.LLVMModuleRef, srt: *SemanticTree) u32 {
    var new_marks: u32 = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                const ref = @intFromPtr(inst);

                // Skip if already marked
                if (srt.hasKind(ref, .heap_provenance) != null) continue;

                switch (opcode) {
                    // GEP, Load: if base has heap_provenance, mark result
                    c.LLVMGetElementPtr, c.LLVMLoad => {
                        const base = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(base) != 0) {
                            const base_ref = @intFromPtr(base);
                            if (srt.hasKind(base_ref, .heap_provenance) != null) {
                                srt.recordResolution(ref, .heap_provenance, 0.9, "Ch9 Vec/Box (prop)", "propagated from base") catch {};
                                new_marks += 1;
                            }
                        }
                    },
                    // BitCast, IntToPtr: if operand has heap_provenance, mark result
                    c.LLVMBitCast, c.LLVMIntToPtr => {
                        const operand = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(operand) != 0) {
                            const op_ref = @intFromPtr(operand);
                            if (srt.hasKind(op_ref, .heap_provenance) != null) {
                                srt.recordResolution(ref, .heap_provenance, 0.9, "Ch9 Vec/Box (prop)", "propagated from operand") catch {};
                                new_marks += 1;
                            }
                        }
                    },
                    // PHI: if any incoming has heap_provenance, mark PHI
                    c.LLVMPHI => {
                        const num_incoming = c.LLVMCountIncoming(inst);
                        var i: u32 = 0;
                        while (i < num_incoming) : (i += 1) {
                            const incoming = c.LLVMGetIncomingValue(inst, i);
                            if (@intFromPtr(incoming) != 0) {
                                if (srt.hasKind(@intFromPtr(incoming), .heap_provenance) != null) {
                                    srt.recordResolution(ref, .heap_provenance, 0.85, "Ch9 Vec/Box (prop)", "propagated from PHI incoming") catch {};
                                    new_marks += 1;
                                    break;
                                }
                            }
                        }
                    },
                    // Select: if either value operand has heap_provenance, mark result
                    c.LLVMSelect => {
                        const val1 = c.LLVMGetOperand(inst, 1);
                        const val2 = c.LLVMGetOperand(inst, 2);
                        if ((@intFromPtr(val1) != 0 and srt.hasKind(@intFromPtr(val1), .heap_provenance) != null) or
                            (@intFromPtr(val2) != 0 and srt.hasKind(@intFromPtr(val2), .heap_provenance) != null))
                        {
                            srt.recordResolution(ref, .heap_provenance, 0.85, "Ch9 Vec/Box (prop)", "propagated from select") catch {};
                            new_marks += 1;
                        }
                    },
                    // InsertValue: if any inserted value has heap_provenance, mark result
                    c.LLVMInsertValue => {
                        const num_ops = c.LLVMGetNumOperands(inst);
                        var i: u32 = 1; // skip first operand (aggregate)
                        while (i < num_ops) : (i += 1) {
                            const operand = c.LLVMGetOperand(inst, i);
                            if (@intFromPtr(operand) != 0 and srt.hasKind(@intFromPtr(operand), .heap_provenance) != null) {
                                srt.recordResolution(ref, .heap_provenance, 0.85, "Ch9 Vec/Box (prop)", "propagated from insertvalue") catch {};
                                new_marks += 1;
                                break;
                            }
                        }
                    },
                    // ExtractValue: if aggregate has heap_provenance, mark extracted value
                    c.LLVMExtractValue => {
                        const aggregate = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(aggregate) != 0 and srt.hasKind(@intFromPtr(aggregate), .heap_provenance) != null) {
                            srt.recordResolution(ref, .heap_provenance, 0.85, "Ch9 Vec/Box (prop)", "propagated from extractvalue") catch {};
                            new_marks += 1;
                        }
                    },
                    // Call/Invoke: propagate in both directions
                    c.LLVMCall, c.LLVMInvoke => {
                        const callee = c.LLVMGetCalledValue(inst) orelse continue;
                        if (@intFromPtr(c.LLVMIsAFunction(callee)) == 0) continue;

                        // Direction 1: arg → callee param (for defined functions)
                        if (c.LLVMIsDeclaration(callee) == 0) {
                            const num_args = c.LLVMGetNumArgOperands(inst);
                            const num_params = c.LLVMCountParams(callee);
                            const limit = if (num_args < num_params) num_args else num_params;

                            var i: u32 = 0;
                            while (i < limit) : (i += 1) {
                                const arg = c.LLVMGetOperand(inst, i);
                                if (@intFromPtr(arg) == 0) continue;
                                if (srt.hasKind(@intFromPtr(arg), .heap_provenance) == null) continue;

                                const param = c.LLVMGetParam(callee, i);
                                const param_ref = @intFromPtr(param);
                                if (srt.hasKind(param_ref, .heap_provenance) == null) {
                                    srt.recordResolution(param_ref, .heap_provenance, 0.8, "Ch9 Vec/Box (prop)", "propagated via call arg") catch {};
                                    new_marks += 1;
                                }
                            }
                        }

                        // Direction 2: callee return → call site
                        // Check if the callee function returns a heap-provenance value
                        if (c.LLVMIsDeclaration(callee) == 0) {
                            if (functionReturnsHeapProvenance(callee, srt)) {
                                if (srt.hasKind(ref, .heap_provenance) == null) {
                                    srt.recordResolution(ref, .heap_provenance, 0.8, "Ch9 Vec/Box (prop)", "propagated from callee return") catch {};
                                    new_marks += 1;
                                }
                            }
                        }
                    },
                    // Store: if storing a heap-provenance pointer, we can't mark the store itself,
                    // but we note it for potential load-through-memory propagation
                    c.LLVMStore => {
                        // No-op for now: store-to-load propagation requires alias analysis
                        // which is beyond simple fixed-point
                        _ = {};
                    },
                    else => {},
                }
            }
        }
    }

    return new_marks;
}

/// Count total heap_provenance marks in SRT
fn countHeapMarks(srt: *SemanticTree) u32 {
    var count: u32 = 0;
    for (srt.nodes.items) |node| {
        for (node.resolutions.items) |r| {
            if (r.kind == .heap_provenance) {
                count += 1;
                break;
            }
        }
    }
    return count;
}

/// Detect heap-owning patterns and write to SRT.
/// Uses fixed-point forward propagation to mark ALL values derived from heap allocations.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;

    // Phase 1: Mark all heap allocation call sites
    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (!isHeapAllocCall(inst)) continue;

                const callee_name = getCalleeName(inst) orelse continue;
                const ref = @intFromPtr(inst);

                if (srt.hasKind(ref, .heap_provenance) == null) {
                    try srt.recordResolution(ref, .heap_provenance, 0.95, "Ch9 Vec/Box", callee_name);
                }
            }
        }
    }

    // Phase 2: Fixed-point forward propagation
    // Iterate until no new marks are added
    var iterations: u32 = 0;
    const max_iterations: u32 = 20;
    while (iterations < max_iterations) : (iterations += 1) {
        const new_marks = propagateHeapProvenance(module, srt);
        if (new_marks == 0) break;
    }
}
