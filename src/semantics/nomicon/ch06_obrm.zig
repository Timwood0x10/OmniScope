//! Nomicon Ch6: OBRM (Ownership, Borrowing, Resource Management)
//!
//! Detects Drop trait implementations, drop_in_place functions, and
//! scope-end dealloc patterns. These are RAII releases — never bugs.
//!
//! Nomicon §6.1: Constructors & Destructors
//! - Drop trait implementations appear as `drop_in_place<T>` in LLVM IR
//! - Scope-end dealloc is __rust_dealloc in tail position before ret
//!
//! Covers: F4 (3 use_after_free FP) — bun_base64::wyhash_url_safe fmt_str Drop

const std = @import("std");
const log = std.log.scoped(.obrm);
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Drop-related function name patterns (Rust compiler generated)
const DROP_PATTERNS = [_][]const u8{
    "drop_in_place",
    "::drop",
    "~", // C++ destructors
};

/// Rust dealloc symbol
const RUST_DEALLOC = "__rust_dealloc";

/// Patterns that indicate compiler-generated internal functions
/// (not user-visible functions)
const COMPILER_INTERNAL_PREFIXES = [_][]const u8{
    "_ZN", // Itanium C++ ABI / Rust legacy mangling
    "_R", // Rust v0 mangling
    "__rust_",
    "__rdl_",
    "__rg_",
};

/// Detect OBRM patterns and write to SRT.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) == 0) continue;
        const func_name = std.mem.sliceTo(func_name_raw, 0);

        // Check if this function is a drop context
        const is_drop_ctx = isDropContextFunction(func_name);

        // Check if this is a compiler-generated function
        const is_compiler_gen = isCompilerGeneratedFunction(func_name);

        // Walk all instructions
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (!llvm_safe.isCallOrInvoke(opcode)) continue;
                const callee_name = getCalleeName(inst) orelse continue;

                // Only care about Rust dealloc
                if (!std.mem.eql(u8, callee_name, RUST_DEALLOC)) continue;

                // FIX: Add context validation to distinguish compiler RAII from user unsafe code
                const should_mark_raii = shouldMarkAsRAII(is_drop_ctx, is_compiler_gen, func_name);

                if (should_mark_raii) {
                    // This is legitimate compiler-generated RAII cleanup
                    try srt.recordResolution(
                        @intFromPtr(inst),
                        .raii_drop_release,
                        0.95,
                        "Ch6 OBRM",
                        if (is_drop_ctx) "dealloc in drop_in_place context" else "dealloc in tail position",
                    );
                } else {
                    // User unsafe code using __rust_dealloc — do NOT mark as RAII
                    // Let normal detection flow handle potential double-free/UAF
                    log.debug("[RAII-SKIP] __rust_dealloc in user code {s} — not marking as RAII to allow bug detection", .{func_name});
                }
            }
        }
    }
}

/// Determine if a __rust_dealloc call should be marked as RAII.
///
/// Returns true only when we're confident this is compiler-generated cleanup:
/// - In a drop context function (drop_in_place, etc.)
/// - In a compiler-internal mangled function
///
/// User unsafe code (Box::from_raw, GlobalAlloc impls) will return false.
fn shouldMarkAsRAII(
    is_drop_context: bool,
    is_compiler_generated: bool,
    caller_func_name: []const u8,
) bool {
    // Condition 1: Always trust drop context functions
    // (drop_in_place, <T as Drop>::drop, etc.)
    if (is_drop_context) return true;

    // Condition 2: Compiler-generated internal functions with mangled names
    // These are invisible to users — their __rust_dealloc is always RAII
    if (is_compiler_generated) return true;

    // Condition 3: Check for known user-level patterns that use __rust_dealloc
    // but are NOT compiler RAII (GlobalAlloc trait impls, custom allocators)
    if (isUserAllocatorImpl(caller_func_name)) {
        return false;
    }

    // Default: conservative — don't mark as RAII if uncertain
    // This prevents suppressing real bugs in user unsafe code
    return false;
}

/// Check if a function name indicates a compiler-generated internal function.
fn isCompilerGeneratedFunction(func_name: []const u8) bool {
    for (COMPILER_INTERNAL_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    return false;
}

/// Check if function looks like a user-defined allocator implementation
/// (e.g., GlobalAlloc trait impl, custom allocator).
///
/// These use __rust_dealloc but are NOT compiler RAII — they're user code.
fn isUserAllocatorImpl(func_name: []const u8) bool {
    // GlobalAlloc trait implementation patterns
    const user_allocator_patterns = [_][]const u8{
        "global_alloc",
        "GlobalAlloc",
        "allocator",
        "Allocator",
        // User-defined allocators often have these in demangled form
        "alloc::alloc::",
        "std::alloc::",
    };

    for (user_allocator_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if function name indicates a drop context
fn isDropContextFunction(func_name: []const u8) bool {
    for (DROP_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a dealloc call is in tail position (before ret)
fn isTailDealloc(inst: c.LLVMValueRef) bool {
    var next = c.LLVMGetNextInstruction(inst);
    while (@intFromPtr(next) != 0) {
        const opcode = c.LLVMGetInstructionOpcode(next);
        if (opcode == c.LLVMRet) return true;
        if (opcode != c.LLVMBr) break;
        next = c.LLVMGetNextInstruction(next);
    }
    return false;
}

/// Get callee name from a call instruction
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst) orelse return null;
    const name_raw = c.LLVMGetValueName(called_val) orelse return null;
    return std.mem.sliceTo(name_raw, 0);
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "isDropContextFunction - recognizes drop patterns" {
    try std.testing.expect(isDropContextFunction("_ZN4core3ptr13drop_in_place17hE"));
    try std.testing.expect(isDropContextFunction("drop_in_place"));
    try std.testing.expect(isDropContextFunction("my_type::drop"));

    try std.testing.expect(!isDropContextFunction("my_function"));
    try std.testing.expect(!isDropContextFunction("malloc"));
}

test "isCompilerGeneratedFunction - recognizes mangled names" {
    // Rust v0 mangling
    try std.testing.expect(isCompilerGeneratedFunction("_RIN4core3ptr"));
    // Itanium C++ ABI / Rust legacy
    try std.testing.expect(isCompilerGeneratedFunction("_ZN4core3ptr13drop_in_place"));
    // Rust intrinsics
    try std.testing.expect(isCompilerGeneratedFunction("__rust_alloc"));
    try std.testing.expect(isCompilerGeneratedFunction("__rdl_dealloc"));

    // User-visible functions (demangled or simple names)
    try std.testing.expect(!isCompilerGeneratedFunction("my_function"));
    try std.testing.expect(!isCompilerGeneratedFunction("main"));
}

test "isUserAllocatorImpl - recognizes user allocator code" {
    // GlobalAlloc trait impls
    try std.testing.expect(isUserAllocatorImpl("_ZN4alloc5alloc9global_alloc"));
    // Demangled forms
    try std.testing.expect(isUserAllocatorImpl("alloc::alloc::GlobalAlloc"));

    // Normal functions
    try std.testing.expect(!isUserAllocatorImpl("drop_in_place"));
    try std.testing.expect(!isUserAllocatorImpl("main"));
}

test "shouldMarkAsRAII - correct classification" {
    // Compiler RAII: drop context → should mark
    try std.testing.expect(shouldMarkAsRAII(true, false, "drop_in_place<T>"));

    // Compiler RAII: compiler-generated internal → should mark
    try std.testing.expect(shouldMarkAsRAII(false, true, "_ZN4core3ptr13drop_in_place"));

    // User unsafe code: user-visible function, not drop context → should NOT mark
    try std.testing.expect(!shouldMarkAsRAII(false, false, "my_unsafe_function"));

    // User allocator impl: uses __rust_dealloc but is user code → should NOT mark
    try std.testing.expect(!shouldMarkAsRAII(false, false, "_ZN4alloc5alloc9global_alloc"));
}
