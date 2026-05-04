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
const ffi_utils = @import("ffi_utils.zig");
const ptr_types = @import("ptr_lifetime_types.zig");

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

    // Fallback: delegate to centralized allocator detection (ptr_types + AllocatorKB).
    if (ptr_types.isHeapAllocFunction(callee_name)) return true;

    // Safety net: Rust mangled allocators (e.g. _RNv...__rust_alloc) that may not
    // be caught by exact-match fallback above. Uses substring match since Rust
    // compiler emits mangled names containing the intrinsic base name.
    return isRustMangledAllocator(callee_name);
}

/// Check if callee_name contains a Rust allocator intrinsic substring.
/// Handles mangled names like _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc
/// where the base name "__rust_alloc" appears as a contiguous substring.
///
/// Uses canonical pattern list from ptr_types.RUST_ALLOC_INTRINSICS.all (single source of truth).
fn isRustMangledAllocator(callee_name: []const u8) bool {
    for (ptr_types.RUST_ALLOC_INTRINSICS.all) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
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

    // Delegate to ffi_utils (single source of truth for language detection).
    // Convert from Language enum (ffi_utils) to our local Language enum.
    const lang = ffi_utils.identifyCalleeLanguage(callee_name);
    return switch (lang) {
        .c => .c,
        .rust => .rust,
        .cpp => .cpp,
        .zig => .zig,
        else => .unknown,
    };
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
