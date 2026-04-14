//! Thin pointer-based wrappers for LLVM IR
//!
//! This module provides zero-abstraction wrappers around LLVM-C API pointers.
//! Principle: only wrap pointers, no caching or computation.

const std = @import("std");
const llvm = @import("llvm_c.zig");

/// Thin wrapper for LLVM value (instruction, function, etc.)
pub const ValueRef = struct {
    raw: llvm.LLVMValueRef,
};

/// Thin wrapper for LLVM basic block
pub const BasicBlockRef = struct {
    raw: llvm.LLVMBasicBlockRef,
};

/// Thin wrapper for LLVM module
pub const ModuleRef = struct {
    raw: llvm.LLVMModuleRef,
};

/// Thin wrapper for LLVM context
pub const ContextRef = struct {
    raw: llvm.LLVMContextRef,
};

/// Thin wrapper for LLVM function
pub const FunctionRef = struct {
    raw: llvm.LLVMValueRef,

    pub fn name(self: FunctionRef) []const u8 {
        const c_str = llvm.LLVMGetValueName(self.raw);
        return std.mem.span(c_str);
    }
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
