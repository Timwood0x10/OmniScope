//! IR Helper Functions — Consolidated Single Source of Truth
//!
//! Consolidates duplicate IR utility functions found across the codebase.
//!
//! Sources (origin files):
//!   - getFunctionName():       types/cpp_fp_types.zig, types/cpp_fp_helpers.zig
//!   - identifyLanguageFromCallee(): types/ownership_analysis.zig (delegates to alloc_classifier)
//!
//! Design principle: Pure functions only, no dependency on PassContext state.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const Language = @import("../diag/issue.zig").FFIBoundary.Language;

// ============================================================================
// Function Name Extraction
// ============================================================================

/// Extract function name from LLVM value reference.
/// Returns "unknown" if the name cannot be determined.
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "unknown";
    return std.mem.span(name_ptr);
}

/// Extract callee name from a call instruction.
/// Returns null if the instruction is not a call or has no callee.
pub fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_ptr) == 0) return null;
    return std.mem.span(name_ptr);
}

// ============================================================================
// Language Identification
// ============================================================================

/// Identify the language of a function by examining its callee.
/// Delegates to language_detector for unified classification.
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    const name = getFunctionName(func);
    return identifyLanguageFromName(name);
}

/// Identify language from a function name using naming conventions.
pub fn identifyLanguageFromName(func_name: []const u8) Language {
    // Rust v0 mangling: _R prefix
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') {
        return .rust;
    }
    // Rust Itanium mangling: _ZN prefix with known Rust alloc/dealloc patterns
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        const rust_zn_patterns = [_][]const u8{
            "alloc",    "dealloc", "drop", "into_raw",
            "from_raw", "as_ptr",
        };
        for (rust_zn_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return .rust;
        }
    }
    // Rust compiler intrinsics
    if (std.mem.startsWith(u8, func_name, "__rust_") or
        std.mem.startsWith(u8, func_name, "__rdl_") or
        std.mem.startsWith(u8, func_name, "__rg_"))
    {
        return .rust;
    }
    // C++ Itanium ABI mangling: _Z prefix (but not _ZN which is Rust)
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z') {
        if (!std.mem.startsWith(u8, func_name, "_ZN")) {
            return .cpp;
        }
    }
    // C++ operator names
    if (std.mem.startsWith(u8, func_name, "operator new") or
        std.mem.startsWith(u8, func_name, "operator delete"))
    {
        return .cpp;
    }
    // Go cgo patterns
    if (std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "_Cfunc_") != null)
    {
        return .go;
    }
    // Java JNI
    if (std.mem.startsWith(u8, func_name, "Java_")) {
        return .java;
    }
    return .unknown;
}

/// Identify the language of the callee from a call instruction.
/// Delegates to alloc_classifier for classification.
pub fn identifyLanguageFromCallee(inst: c.LLVMValueRef, opcode: c_uint) Language {
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return .unknown;
    const callee_name = getCalleeName(inst) orelse return .unknown;
    return identifyLanguageFromName(callee_name);
}
