//! Thin pointer-based wrappers for LLVM IR
//!
//! This module provides zero-abstraction wrappers around LLVM-C API pointers.
//! Principle: only wrap pointers, no caching or computation.
//!
//! Note: For safe LLVM operations, use llvm_safe.zig instead.
//! This module only provides thin pointer wrappers for compatibility.

const std = @import("std");
const c = @import("llvm_raw.zig").c;

/// Thin wrapper for LLVM value (instruction, function, etc.)
pub const ValueRef = struct {
    raw: c.LLVMValueRef,
};

/// Thin wrapper for LLVM basic block
pub const BasicBlockRef = struct {
    raw: c.LLVMBasicBlockRef,
};

/// Thin wrapper for LLVM module
pub const ModuleRef = struct {
    raw: c.LLVMModuleRef,
};

/// Thin wrapper for LLVM context
pub const ContextRef = struct {
    raw: c.LLVMContextRef,
};

/// Thin wrapper for LLVM function
pub const FunctionRef = struct {
    raw: c.LLVMValueRef,
};

test "ValueRef - thin wrapper" {
    const ref = ValueRef{ .raw = undefined };
    _ = ref;
}

test "BasicBlockRef - thin wrapper" {
    const ref = BasicBlockRef{ .raw = undefined };
    _ = ref;
}

test "ModuleRef - thin wrapper" {
    const ref = ModuleRef{ .raw = undefined };
    _ = ref;
}

test "ContextRef - thin wrapper" {
    const ref = ContextRef{ .raw = undefined };
    _ = ref;
}

test "FunctionRef - thin wrapper" {
    const ref = FunctionRef{ .raw = undefined };
    _ = ref;
}
