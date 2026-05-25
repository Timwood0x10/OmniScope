//! Alias Analysis Helpers for Pointer Value Tracking
//!
//! Extracted from rust_ffi_auditor.zig. Provides pointer alias analysis,
//! value unwrapping, and base pointer resolution utilities.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const ptr_types = @import("ptr_lifetime/ptr_lifetime_types.zig");

// ============================================================================
// Value Alias Analysis
// ============================================================================

/// Check if two values may alias (same pointer or derived from same source).
pub fn valuesMayAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == 0 or @intFromPtr(b) == 0) return false;
    if (a == b) return true;

    const a_unwrapped = unwrapSingleLevel(a);
    const b_unwrapped = unwrapSingleLevel(b);

    if (a_unwrapped == b_unwrapped) return true;
    if (a_unwrapped != null and a_unwrapped.? == b) return true;
    if (b_unwrapped != null and b_unwrapped.? == a) return true;

    if (isSameBasePointer(a, b)) return true;
    return false;
}

/// Unwrap one level of bitcast/GEP/ptrtoint/inttoptr
pub fn unwrapSingleLevel(val: c.LLVMValueRef) ?c.LLVMValueRef {
    if (@intFromPtr(val) == 0) return null;
    const opcode = c.LLVMGetInstructionOpcode(val);
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr or
        opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr)
    {
        return c.LLVMGetOperand(val, 0);
    }
    return null;
}

/// Check if two values may point to the same base allocation.
pub fn isSameBasePointer(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    const a_base = getBaseValue(a);
    const b_base = getBaseValue(b);
    if (a_base) |ab| {
        if (b_base) |bb| return ab == bb;
    }
    return false;
}

/// Get the "base" value of a pointer chain (strip bitcast/GEP).
pub fn getBaseValue(val: c.LLVMValueRef) ?c.LLVMValueRef {
    var current = val;
    var depth: u32 = 0;
    while (depth < 4) : (depth += 1) {
        if (@intFromPtr(current) == 0) return null;
        const opcode = c.LLVMGetInstructionOpcode(current);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
            current = c.LLVMGetOperand(current, 0);
        } else {
            break;
        }
    }
    return current;
}

/// Find the call instruction that produces the parent value of an instruction.
pub fn findParentCall(inst: c.LLVMValueRef) ?c.LLVMValueRef {
    if (@intFromPtr(inst) == 0) return null;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMExtractValue and opcode != c.LLVMInsertValue) return null;
    const agg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(agg) == 0) return null;
    if (c.LLVMGetValueKind(agg) != c.LLVMInstructionValueKind) return null;
    const agg_opcode = c.LLVMGetInstructionOpcode(agg);
    if (agg_opcode == c.LLVMCall or agg_opcode == c.LLVMInvoke) return agg;
    if (agg_opcode == c.LLVMBitCast) {
        const src = c.LLVMGetOperand(agg, 0);
        if (@intFromPtr(src) != 0 and c.LLVMGetValueKind(src) == c.LLVMInstructionValueKind) {
            const src_opcode = c.LLVMGetInstructionOpcode(src);
            if (src_opcode == c.LLVMCall or src_opcode == c.LLVMInvoke) return src;
        }
    }
    return null;
}

/// Check if function name looks like a free/dealloc (conservative).
pub fn isFreeLikeFunction(func_name: []const u8) bool {
    const free_patterns = [_][]const u8{
        "free", "dealloc", "deallocate", "operator delete", "operator delete[]",
    };
    for (free_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    for (ptr_types.RUST_ALLOC_INTRINSICS.dealloc_only) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    return false;
}

/// Instruction ordering: check if instruction A comes before (or at) instruction B.
pub fn instructionComesBeforeOrEqual(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == 0 or @intFromPtr(b) == 0) return false;
    if (a == b) return true;

    const bb_a = c.LLVMGetInstructionParent(a);
    const bb_b = c.LLVMGetInstructionParent(b);
    if (@intFromPtr(bb_a) == 0 or @intFromPtr(bb_b) == 0) return false;

    // Different basic blocks: use BB ordering as approximation
    if (bb_a != bb_b) {
        var bb = c.LLVMGetFirstBasicBlock(c.LLVMGetBasicBlockParent(bb_a));
        var found_a = false;
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            if (bb == bb_a) found_a = true;
            if (bb == bb_b) return found_a;
        }
        return false;
    }

    // Same BB: walk instructions in order
    var inst = c.LLVMGetFirstInstruction(bb_a);
    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        if (inst == a) return true;
        if (inst == b) return false;
    }
    return false;
}
