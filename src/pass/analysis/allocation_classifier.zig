//! Allocation & Free Classification
//!
//! Provides classification functions for LLVM IR allocation/free instructions.
//! Extracted from pointer_ownership.zig per rules.md line limit (≤1000 lines).
//!
//! These are standalone utility functions used by PointerOwnershipPass.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const lifetime = @import("../../lifetime/root.zig");

/// Convert internal Language enum to lifetime.LanguageHint.
pub fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
    return switch (lang) {
        .c => .c,
        .rust => .rust,
        .zig => .zig,
        .cpp => .cpp,
        .go => .go,
        .swift => .swift,
        .unknown => .unknown,
    };
}

/// Check if an instruction is an allocation using SemanticRegistry.
pub fn isAllocationInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;

    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return false;

    const name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_ptr) == 0) return false;

    const callee_name = std.mem.span(name_ptr);

    // Use SemanticRegistry for accurate identification.
    if (SemanticRegistry.lookup(callee_name)) |sem| {
        return sem.kind == .allocator or sem.kind == .cpp_allocator;
    }

    // Fallback: check for known allocation patterns.
    return std.mem.eql(u8, callee_name, "malloc") or
        std.mem.eql(u8, callee_name, "calloc") or
        std.mem.eql(u8, callee_name, "realloc") or
        std.mem.eql(u8, callee_name, "aligned_alloc") or
        std.mem.indexOf(u8, callee_name, "into_raw") != null or
        std.mem.indexOf(u8, callee_name, "operator new") != null;
}

/// Classify the type of allocation.
pub fn classifyAllocation(inst: c.LLVMValueRef, opcode: c_uint) AllocType {
    _ = opcode;

    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return .unknown;

    const callee_name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

    const callee_name = std.mem.span(callee_name_ptr);

    if (std.mem.indexOf(u8, callee_name, "into_raw") != null) {
        return .rust_box_into_raw;
    }
    if (std.mem.indexOf(u8, callee_name, "from_raw") != null) {
        return .rust_box_from_raw;
    }
    if (std.mem.indexOf(u8, callee_name, "allocImpl") != null) {
        return .zig_alloc;
    }
    if (std.mem.indexOf(u8, callee_name, "operator new") != null) {
        return .cpp_new;
    }

    return .heap;
}

/// Identify language from callee function name.
pub fn identifyLanguageFromCallee(inst: c.LLVMValueRef, opcode: c_uint) Language {
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return .unknown;

    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return .unknown;

    const callee_name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

    const callee_name = std.mem.span(callee_name_ptr);

    // Rust uses _R prefix for v0 mangling (RFC 2603).
    if (callee_name.len > 2 and
        callee_name[0] == '_' and
        callee_name[1] == 'R')
    {
        return .rust;
    }

    // Check for Rust-specific patterns.
    if (std.mem.indexOf(u8, callee_name, "into_raw") != null or
        std.mem.indexOf(u8, callee_name, "from_raw") != null or
        std.mem.indexOf(u8, callee_name, "drop_in_place") != null)
    {
        return .rust;
    }

    // Check for C standard library functions.
    if (std.mem.eql(u8, callee_name, "malloc") or
        std.mem.eql(u8, callee_name, "free") or
        std.mem.eql(u8, callee_name, "calloc") or
        std.mem.eql(u8, callee_name, "realloc"))
    {
        return .c;
    }

    // C++ mangled names start with _Z.
    if (callee_name.len > 2 and
        callee_name[0] == '_' and
        callee_name[1] == 'Z')
    {
        return .cpp;
    }

    // Check for Zig allocator patterns.
    if (std.mem.indexOf(u8, callee_name, "Allocator.") != null or
        std.mem.indexOf(u8, callee_name, "allocImpl") != null)
    {
        return .zig;
    }

    return .unknown;
}

/// Check if an instruction is a free using SemanticRegistry.
pub fn isFreeInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;

    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return false;

    const name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_ptr) == 0) return false;

    const callee_name = std.mem.span(name_ptr);

    // Use SemanticRegistry for accurate identification.
    if (SemanticRegistry.lookup(callee_name)) |sem| {
        return sem.kind == .deallocator;
    }

    // Fallback: check for known free patterns.
    return std.mem.eql(u8, callee_name, "free") or
        std.mem.indexOf(u8, callee_name, "from_raw") != null or
        std.mem.indexOf(u8, callee_name, "drop_in_place") != null or
        std.mem.indexOf(u8, callee_name, "operator delete") != null;
}

/// Classify the type of free.
pub fn classifyFree(inst: c.LLVMValueRef, opcode: c_uint) FreeType {
    if (opcode != c.LLVMCall) return .unknown;

    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return .unknown;

    const callee_name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

    const callee_name = std.mem.span(callee_name_ptr);

    if (std.mem.indexOf(u8, callee_name, "from_raw") != null) {
        return .rust_box_from_raw;
    }
    if (std.mem.indexOf(u8, callee_name, "drop_in_place") != null) {
        return .rust_drop;
    }
    if (std.mem.indexOf(u8, callee_name, "operator delete") != null) {
        return .cpp_delete;
    }

    return .free;
}

/// Allocation type classification.
pub const AllocType = enum {
    heap,
    stack,
    global,
    rust_box_into_raw,
    rust_box_from_raw,
    zig_alloc,
    cpp_new,
    unknown,
};

/// Free type classification.
pub const FreeType = enum {
    free,
    rust_box_from_raw,
    rust_drop,
    cpp_delete,
    scope_exit,
    unknown,
};
