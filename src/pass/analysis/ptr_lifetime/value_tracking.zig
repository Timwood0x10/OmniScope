//! Unified Value Tracking API for FFI Safety Analysis
//!
//! Part of todo.md T1-T6 framework. Provides language-agnostic value origin
//! classification and usage inference for LLVM IR values under opaque pointers.
//!
//! Replaces scattered implementations:
//!   - isDerivedFromAlloca() → traceValueSource() + ValueSource
//!   - isValueFromParameter() → traceValueSource() returns .from_parameter
//!   - isGlobalUsedForIndirectCall() → traceValueUsage() returns .as_call_target
//!   - mayRetainPointer() partial logic → traceValueUsage() returns .as_store_dest
//!
//! Design: All functions are pure (no allocator, no state). Types are plain enums/structs.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const ir_store_mod = @import("../../../ir/ir_store.zig");
const FunctionIR = ir_store_mod.FunctionIR;

// ============================================================================
// Type Definitions
// ============================================================================

/// Value source classification — answers "where did this value come from?"
pub const ValueSource = enum {
    from_parameter,
    from_alloca,
    from_call,
    from_global,
    from_constant,
    from_code_section,
    unknown,
};

/// Value usage classification — answers "how is this value being used?"
pub const ValueUsage = enum {
    as_call_target,
    as_store_dest,
    as_load_src,
    as_gep_base,
    as_arg_to_ffi,
    as_free_arg,
};

/// Fixed-size set of detected usages for a single value.
pub const UsageSet = struct {
    items: [6]ValueUsage = undefined,
    len: usize = 0,

    pub fn contains(self: *const UsageSet, usage: ValueUsage) bool {
        for (self.items[0..self.len]) |u| {
            if (u == usage) return true;
        }
        return false;
    }
};

// ============================================================================
// T1: Value Source Tracing
// ============================================================================

/// Find the index of a target instruction in the FunctionIR instructions array.
/// O(1) via fir.inst_index — falls back to linear scan if the value isn't
/// in the map (shouldn't happen for instructions from the same function).
pub fn findInstructionIndex(fir: *const FunctionIR, target: c.LLVMValueRef) ?usize {
    if (fir.indexOf(target)) |idx| return @as(usize, idx);
    return null;
}

/// Trace a value back to its origin source.
///
/// Walks def-use chain to determine where `val` ultimately comes from.
/// Key enhancement over isDerivedFromAlloca(): also traces alloca CONTENT
/// (what was stored into the alloca), not just the alloca itself.
pub fn traceValueSource(val: c.LLVMValueRef, func: c.LLVMValueRef, fir: *const FunctionIR) ValueSource {
    if (@intFromPtr(val) == 0) return .unknown;

    const opcode = c.LLVMGetInstructionOpcode(val);

    if (c.LLVMIsAArgument(val) != null) return .from_parameter;
    if (opcode == c.LLVMAlloca) {
        return traceAllocaContent(val, fir);
    }
    if (c.LLVMIsAGlobalValue(val) != null) return .from_global;
    if (c.LLVMIsAConstant(val) != null or c.LLVMIsAConstantInt(val) != null) return .from_constant;
    if (c.LLVMIsAFunction(val) != null) return .from_code_section;
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) return .from_call;

    // Recursive tracing through wrappers
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
        const src = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(src) != 0) return traceValueSource(src, func, fir);
    }

    // Load instruction → trace what's being loaded
    if (opcode == c.LLVMLoad) {
        const ptr_op = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(ptr_op) != 0) {
            const src_kind = traceValueSource(ptr_op, func, fir);
            if (src_kind == .from_alloca) {
                return traceAllocaContent(ptr_op, fir);
            }
            return src_kind;
        }
    }

    return .unknown;
}

/// Trace what content is stored inside an alloca.
/// Distinguishes alloca CONTENT provenance, not just "is it an alloca".
/// Uses pre-categorized fir.stores[] — O(stores) instead of O(instructions).
pub fn traceAllocaContent(alloca_val: c.LLVMValueRef, fir: *const FunctionIR) ValueSource {
    for (fir.stores) |inst| {
        if (c.LLVMGetOperand(inst, 1) != alloca_val) continue;

        const stored_val = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(stored_val) == 0) continue;

        if (c.LLVMIsAArgument(stored_val) != null) return .from_parameter;
        if (c.LLVMIsAGlobalValue(stored_val) != null) {
            const gname_ptr = c.LLVMGetValueName(stored_val);
            if (@intFromPtr(gname_ptr) != 0) {
                const gname = std.mem.span(gname_ptr);
                if (isCodeSectionGlobal(gname)) return .from_code_section;
            }
            return .from_global;
        }
        if (c.LLVMIsAConstant(stored_val) != null) return .from_constant;
        if (c.LLVMIsAFunction(stored_val) != null) return .from_code_section;

        const stored_opcode = c.LLVMGetInstructionOpcode(stored_val);
        if (stored_opcode == c.LLVMCall or stored_opcode == c.LLVMInvoke) return .from_call;
        if (stored_opcode == c.LLVMAlloca) return .from_alloca;
    }

    return .from_alloca;
}

/// Check if a global name suggests it lives in .text/.rodata section.
pub fn isCodeSectionGlobal(gname: []const u8) bool {
    const section_patterns = [_][]const u8{
        ".text", ".rodata",  "__TEXT", "__const",
        "llvm.", "metadata", "comdat",
    };
    for (section_patterns) |pat| {
        if (std.mem.indexOf(u8, gname, pat) != null) return true;
    }
    return false;
}

// ============================================================================
// T2: Value Usage Inference
// ============================================================================

/// Infer how a value is being used by scanning its use-sites within `func`.
///
/// Returns all detected usage patterns. A single value can have multiple
/// simultaneous uses (e.g., both stored AND passed as FFI argument).
pub fn traceValueUsage(val: c.LLVMValueRef, func: c.LLVMValueRef, fir: *const FunctionIR) ?UsageSet {
    if (@intFromPtr(val) == 0 or @intFromPtr(func) == 0) return null;

    var usage_count: usize = 0;
    var usages: [6]ValueUsage = undefined;

    for (fir.instructions) |inst| {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (!instructionUsesValue(inst, val)) continue;

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) != 0 and called == val) {
                addUsage(&usages, &usage_count, .as_call_target);
            } else {
                addUsage(&usages, &usage_count, .as_arg_to_ffi);
            }
            if (isDeallocCall(inst)) {
                addUsage(&usages, &usage_count, .as_free_arg);
            }
        } else if (opcode == c.LLVMStore) {
            addUsage(&usages, &usage_count, .as_store_dest);
        } else if (opcode == c.LLVMLoad) {
            addUsage(&usages, &usage_count, .as_load_src);
        } else if (opcode == c.LLVMGetElementPtr) {
            addUsage(&usages, &usage_count, .as_gep_base);
        }

        if (usage_count >= usages.len) break;
    }

    if (usage_count == 0) return null;
    return .{ .items = usages, .len = usage_count };
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if `inst` uses `target_value` as any operand.
pub fn instructionUsesValue(inst: c.LLVMValueRef, target_value: c.LLVMValueRef) bool {
    if (@intFromPtr(inst) == 0 or @intFromPtr(target_value) == 0) return false;
    const num_operands = c.LLVMGetNumOperands(inst);
    var i: c_uint = 0;
    while (i < num_operands) : (i += 1) {
        if (c.LLVMGetOperand(inst, i) == target_value) return true;
    }
    return false;
}

/// Check if a call/invoke instruction calls a known deallocator.
pub fn isDeallocCall(inst: c.LLVMValueRef) bool {
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return false;
    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return false;
    return isDeallocator(std.mem.span(name_ptr));
}

/// Check if a function name matches known deallocator patterns across languages.
pub fn isDeallocator(func_name: []const u8) bool {
    if (std.mem.eql(u8, func_name, "free")) return true;
    if (std.mem.eql(u8, func_name, "realloc")) return true;
    if (std.mem.indexOf(u8, func_name, "_cgo_free") != null) return true;
    if (std.mem.indexOf(u8, func_name, "_Cfunc_GoFree") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__rust_dealloc") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__rust_alloc") != null) return true;
    if (std.mem.indexOf(u8, func_name, "PyMem_Free") != null) return true;
    if (std.mem.indexOf(u8, func_name, "objc_release") != null) return true;
    if (std.mem.indexOf(u8, func_name, "DeleteLocalRef") != null) return true;
    if (std.mem.indexOf(u8, func_name, "ReleaseStringUTFChars") != null) return true;
    if (std.mem.indexOf(u8, func_name, "Dispose") != null) return true;
    return false;
}

/// Safely add a usage to the array if not already present.
fn addUsage(usages: *[6]ValueUsage, count: *usize, usage: ValueUsage) void {
    for (usages[0..count.*]) |u| {
        if (u == usage) return;
    }
    if (count.* < usages.len) {
        usages[count.*] = usage;
        count.* += 1;
    }
}

/// Check if `user_value` traces to `source_value` through GEP/bitcast/load chains.
pub fn valueTracesTo(user_value: c.LLVMValueRef, source_value: c.LLVMValueRef, fir: *const FunctionIR) bool {
    if (user_value == source_value) return true;

    const opcode = c.LLVMGetInstructionOpcode(user_value);

    if (opcode == c.LLVMGetElementPtr) {
        const base = c.LLVMGetOperand(user_value, 0);
        if (@intFromPtr(base) != 0 and valueTracesTo(base, source_value, fir)) return true;
    }

    if (opcode == c.LLVMBitCast) {
        const src = c.LLVMGetOperand(user_value, 0);
        if (@intFromPtr(src) != 0 and valueTracesTo(src, source_value, fir)) return true;
    }

    if (opcode == c.LLVMLoad) {
        const load_ptr = c.LLVMGetOperand(user_value, 0);
        if (@intFromPtr(load_ptr) != 0) {
            // Find the load instruction's position and scan forward for stores
            const start_idx = findInstructionIndex(fir, user_value) orelse return false;
            for (fir.instructions[start_idx..]) |inst| {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
                if (c.LLVMGetOperand(inst, 1) != load_ptr) continue;
                if (c.LLVMGetOperand(inst, 0) == source_value) return true;
            }
        }
    }

    return false;
}

/// Recursively check if `inst` uses a value loaded from `target_global`.
pub fn instructionUsesLoadedFromGlobal(
    inst: c.LLVMValueRef,
    target_global: c.LLVMValueRef,
) bool {
    if (@intFromPtr(inst) == 0 or @intFromPtr(target_global) == 0) return false;

    const num_operands = c.LLVMGetNumOperands(inst);
    var i: c_uint = 0;
    while (i < num_operands) : (i += 1) {
        const op = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(op) == 0) continue;

        const op_opcode = c.LLVMGetInstructionOpcode(op);
        if (op_opcode == c.LLVMLoad) {
            const load_src = c.LLVMGetOperand(op, 0);
            if (load_src == target_global) return true;
        }

        if (op_opcode == c.LLVMBitCast or op_opcode == c.LLVMGetElementPtr) {
            if (instructionUsesLoadedFromGlobal(op, target_global)) return true;
        }
    }
    return false;
}

/// T5 helper: Check if instruction has debug metadata (struct type hint).
pub fn hasStructDebugMetadata(inst: c.LLVMValueRef) bool {
    if (@intFromPtr(inst) == 0) return false;
    const meta = c.LLVMGetMetadata(inst, 0);
    return @intFromPtr(meta) != 0;
}
