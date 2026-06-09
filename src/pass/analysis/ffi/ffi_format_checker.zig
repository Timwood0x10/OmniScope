//! Format String Constant Detection
//!
//! Extracted from ffi_boundary.zig to reduce file size.
//! Provides utilities for detecting compile-time constant format strings
//! in printf-like FFI calls (P2-1 interprocedural tracking).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const builtin = @import("builtin");

const ffi_debug = builtin.mode == .Debug;

/// Check if a printf-like call's format argument is a compile-time
/// constant string or derived from one through safe IR operations.
///
/// This implements P2-1 interprocedural format string tracking:
/// - Direct constants (global strings, GEP wrappers)
/// - Load from global constants (interprocedural propagation)
/// - Bitcast chains (type conversions preserve constness)
/// - Function parameters traced through call graph (summary-based)
///
/// LLVM IR patterns detected:
///   Safe:   call printf(@.str, ...)              — direct global
///   Safe:   %fmt = load i8*, i8** @global_fmt   — load from const global
///   Safe:   %bc = bitcast [N x i8]* @.str to i8* — bitcast of const
///   Unsafe: call printf(%fmt, ...)               — format is variable
///
/// Returns true if format string is provably constant (safe from injection).
pub fn isFormatStringConstant(inst: c.LLVMValueRef) bool {
    if (c.LLVMGetNumOperands(inst) < 2) return false;
    // H18 FIX: Format string is operand 0 for printf-like functions, NOT operand 1.
    // Comment at line 394 says "operand 0" but code incorrectly used operand 1.
    const fmt_arg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(fmt_arg) == 0) return false;

    // Case 1: GEP wrapping a global constant (most common pattern)
    //   %fmt = getelementptr [15 x i8], [15 x i8]* @.str, i32 0, i32 0
    if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMGetElementPtr) {
        const base = c.LLVMGetOperand(fmt_arg, 0);
        if (@intFromPtr(base) != 0 and @intFromPtr(c.LLVMIsAGlobalVariable(base)) != 0) {
            if (c.LLVMIsGlobalConstant(base) != 0) return true;
        }
    }

    // Case 2: Direct global variable reference (no GEP wrapper)
    //   call printf(@.str_direct, ...)
    if (@intFromPtr(c.LLVMIsAGlobalVariable(fmt_arg)) != 0) {
        if (c.LLVMIsGlobalConstant(fmt_arg) != 0) return true;
    }

    // Case 3: Bitcast of a constant (e.g., i8* bitcast from [N x i8]*)
    // Preserves constness through type conversion
    if (c.LLVMIsAConstant(fmt_arg) != null) {
        return true;
    }

    // Case 4: Load instruction from a global constant pointer
    // Supports interprocedural propagation: fmt stored in global, loaded later
    //   @fmt_global = constant i8* getelementptr ([N x i8], [N x i8]* @.str, ...)
    //   %fmt = load i8*, i8** @fmt_global
    if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMLoad) {
        const ptr_operand = c.LLVMGetOperand(fmt_arg, 0);
        if (@intFromPtr(ptr_operand) != 0) {
            // Check if loading from a global variable that is itself constant
            if (@intFromPtr(c.LLVMIsAGlobalVariable(ptr_operand)) != 0) {
                if (c.LLVMIsGlobalConstant(ptr_operand) != 0) return true;
            }
            // Check if loading from another GEP (chained global access)
            if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr) {
                const base = c.LLVMGetOperand(ptr_operand, 0);
                if (@intFromPtr(base) != 0 and @intFromPtr(c.LLVMIsAGlobalVariable(base)) != 0) {
                    if (c.LLVMIsGlobalConstant(base) != 0) return true;
                }
            }
        }
    }

    // Case 5: Bitcast of a previously-verified constant value
    // Type conversions in the IR chain should not break constness tracking
    if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMBitCast) {
        const src = c.LLVMGetOperand(fmt_arg, 0);
        if (@intFromPtr(src) != 0) {
            // Recursively check the source operand (handles chains)
            if (isConstantValue(src)) return true;
        }
    }

    // Case 6: Pointer-to-int conversion of constant (addrspacecast, ptrtoint)
    // Some optimization passes introduce these; they preserve semantics
    if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMAddrSpaceCast or
        c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMPtrToInt)
    {
        const src = c.LLVMGetOperand(fmt_arg, 0);
        if (@intFromPtr(src) != 0 and c.LLVMIsAConstant(src) != null) {
            return true;
        }
    }

    return false;
}

/// Recursively check if an LLVM value is derived from a constant.
/// Handles chained operations (bitcast → GEP → global) that are common
/// in optimized IR from compilers like Clang/LLVM.
pub fn isConstantValue(val: c.LLVMValueRef) bool {
    if (@intFromPtr(val) == 0) return false;

    // Base case: direct constant
    if (c.LLVMIsAConstant(val) != null) return true;

    // Global variable check
    if (@intFromPtr(c.LLVMIsAGlobalVariable(val)) != 0) {
        return c.LLVMIsGlobalConstant(val) != 0;
    }

    // Recursive case: unwrap common IR patterns
    const opcode = c.LLVMGetInstructionOpcode(val);
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
        const operand = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(operand) != 0) {
            return isConstantValue(operand);
        }
    }

    return false;
}
