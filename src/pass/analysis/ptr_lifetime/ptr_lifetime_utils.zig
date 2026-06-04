//! Utility functions for pointer lifetime analysis
//!
//! This module contains helper functions extracted from ptr_lifetime.zig
//! to reduce file size and improve code organization.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const FfiLang = @import("../../../diag/issue.zig").FFIBoundary.Language;
pub const Lang = @import("../../../semantics/zone_classifier.zig").Language;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;

/// Convert FFI boundary language to zone classifier language
pub fn toZoneLanguage(lang: FfiLang) Lang {
    return switch (lang) {
        .c => .c,
        .cpp => .cpp,
        .rust => .rust,
        .zig => .zig,
        .go => .go,
        .csharp => .unknown,
        else => .unknown,
    };
}

/// Check if a function name indicates a C++ destructor or constructor
pub fn isCppDestructorOrConstructor(func_name: []const u8) bool {
    // C++ destructor: ~ClassName or _ZN...D#Ev
    if (std.mem.indexOf(u8, func_name, "~") != null) return true;
    // Itanium ABI: _ZN...D#Ev (destructor) or _ZN...C#Ev (constructor)
    if (std.mem.indexOf(u8, func_name, "_ZN") != null) {
        if (std.mem.indexOf(u8, func_name, "D0Ev") != null or
            std.mem.indexOf(u8, func_name, "D1Ev") != null or
            std.mem.indexOf(u8, func_name, "D2Ev") != null)
            return true;
        if (std.mem.indexOf(u8, func_name, "C0Ev") != null or
            std.mem.indexOf(u8, func_name, "C1Ev") != null or
            std.mem.indexOf(u8, func_name, "C2Ev") != null)
            return true;
    }
    return false;
}

/// Check if a function name indicates intentional ownership transfer.
/// Covers:
///   - Factory prefixes/suffixes (create, new, make, alloc, from_raw, etc.)
///   - Rust-specific patterns (Box::leak, into_raw, ManuallyDrop, forget)
///   - FFI transfer semantics (donate, transfer_ownership, export_ptr, handoff, ffi_export, c_export)
pub fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
    // Pattern 1: Known intentional leak/transfer callee names (mangled Rust symbols)
    const intentional_patterns = [_][]const u8{
        "leak", // Box::leak — mangled name contains "leak"
        "into_raw", // Box::into_raw — ownership transfer to raw ptr
        "ManuallyDrop", // ManuallyDrop::new — suppresses drop/free
        "forget", // std::mem::forget — intentionally leaks
        "donate", // Ownership donation pattern
        "transfer_ownership", // Explicit transfer
        "export_ptr", // FFI export pointer
        "handoff", // Handoff pattern
        "ffi_export", // FFI export marker
        "c_export", // C export marker
    };
    for (intentional_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    // Pattern 2: Factory prefix/suffix patterns
    const factory_prefixes = [_][]const u8{
        "create", "Create", "CREATE",
        "new",    "New",    "NEW",
        "make",   "Make",   "MAKE",
        "alloc",  "Alloc",  "ALLOC",
        "malloc", "calloc", "realloc",
        "open",   "Open",   "init",
        "Init",   "dup",    "Dup",
        "clone",  "Clone",  "copy",
        "Copy",   "from",   "From",
        "wrap",   "Wrap",   "build",
        "Build",
    };
    for (factory_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    const factory_suffixes = [_][]const u8{
        "_create", "_new",  "_make", "_alloc",
        "_new_",   "_init", "_ctor", "_construct",
        "_clone",  "_copy", "_dup",  "_from",
    };
    for (factory_suffixes) |suffix| {
        if (std.mem.endsWith(u8, func_name, suffix)) return true;
    }
    return false;
}

/// Check if a function name indicates a resource close/deallocation function
pub fn isResourceCloseFunction(fn_name: []const u8) ?ResourceType {
    if (std.mem.indexOf(u8, fn_name, "dlclose") != null) return .dlopen_handle;
    if (std.mem.indexOf(u8, fn_name, "munmap") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "fclose") != null) return .file_handle;
    if (isSocketClose(fn_name)) return .socket_fd;
    if (std.mem.indexOf(u8, fn_name, "DeleteGlobalRef") != null or
        std.mem.indexOf(u8, fn_name, "DeleteLocalRef") != null) return .jni_ref;
    if (std.mem.indexOf(u8, fn_name, "Py_DECREF") != null or
        std.mem.indexOf(u8, fn_name, "Py_XDECREF") != null) return .python_obj;
    return null;
}

/// Check if function name indicates a socket close operation
pub fn isSocketClose(fn_name: []const u8) bool {
    const exact_matches = [_][]const u8{
        "close", "::close",
    };
    for (exact_matches) |m| {
        if (std.mem.eql(u8, fn_name, m)) return true;
    }
    const socket_patterns = [_][]const u8{
        "socket_close", "sock_close",  "fd_close",
        "::close(",     "posix_close", "shutdown",
    };
    for (socket_patterns) |p| {
        if (std.mem.indexOf(u8, fn_name, p) != null) return true;
    }
    return false;
}

/// Check if a description indicates a Rust borrow pattern
pub fn isRustBorrowPattern(source_desc: []const u8) bool {
    const patterns = [_][]const u8{
        "as_ptr",
        "as_mut_ptr",
        "as_raw",
        "get_unchecked",
        "from_raw_parts",
    };
    for (patterns) |p| {
        if (std.mem.indexOf(u8, source_desc, p) != null) return true;
    }
    return false;
}

/// Check if a function name indicates a resource allocation function
pub fn is_resource_alloc_function(fn_name: []const u8) ?ResourceType {
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return .dlopen_handle;
    if (std.mem.indexOf(u8, fn_name, "mmap64") != null or
        std.mem.indexOf(u8, fn_name, "mmap2") != null or
        std.mem.indexOf(u8, fn_name, "mmap") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "shm_open") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "fopen") != null) return .file_handle;
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return .socket_fd;
    // JNI resource allocations
    if (std.mem.indexOf(u8, fn_name, "JNI_") != null or
        std.mem.indexOf(u8, fn_name, "Java_") != null) return .jni_ref;
    // Python C API resource allocations
    if (std.mem.startsWith(u8, fn_name, "Py")) return .python_obj;
    return null;
}

/// Get human-readable resource type name
pub fn get_resource_type(fn_name: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return "dlopen handle";
    if (std.mem.indexOf(u8, fn_name, "mmap") != null) return "mmap region";
    if (std.mem.indexOf(u8, fn_name, "fopen") != null) return "file handle";
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return "socket";
    // JNI resource types
    if (std.mem.indexOf(u8, fn_name, "FindClass") != null or
        std.mem.indexOf(u8, fn_name, "NewGlobalRef") != null or
        std.mem.indexOf(u8, fn_name, "NewLocalRef") != null or
        std.mem.indexOf(u8, fn_name, "GetStringUTFChars") != null or
        std.mem.indexOf(u8, fn_name, "GetByteArrayElements") != null)
    {
        return "JNI reference";
    }
    // Python C API resource types
    if (std.mem.startsWith(u8, fn_name, "Py") and
        (std.mem.indexOf(u8, fn_name, "_New") != null or
            std.mem.indexOf(u8, fn_name, "_From") != null or
            std.mem.indexOf(u8, fn_name, "BuildValue") != null))
    {
        return "Python object";
    }
    return null;
}

/// Check if a value is derived from a base value through GEP/bitcast operations
pub fn isDerivedFrom(value: c.LLVMValueRef, base: c.LLVMValueRef) bool {
    if (@intFromPtr(value) == @intFromPtr(base)) return true;

    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMBitCast) {
        const num_operands = c.LLVMGetNumOperands(value);
        var i: c_uint = 0;
        while (i < num_operands) : (i += 1) {
            const operand = c.LLVMGetOperand(value, i);
            if (isDerivedFrom(operand, base)) return true;
        }
    }
    return false;
}

/// Check if two values are the same or one is derived from the other
pub fn isSameOrAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (isDerivedFrom(a, b) or isDerivedFrom(b, a)) return true;
    return false;
}

/// Check if a pointer is a global variable
pub fn isGlobalVariable(ptr: c.LLVMValueRef) bool {
    if (@intFromPtr(c.LLVMIsAGlobalVariable(ptr)) != 0) return true;
    // Check if it's a GEP of a global
    if (c.LLVMGetInstructionOpcode(ptr) == c.LLVMGetElementPtr) {
        const base = c.LLVMGetOperand(ptr, 0);
        return @intFromPtr(c.LLVMIsAGlobalVariable(base)) != 0;
    }
    return false;
}

/// Check if a value is a function parameter
pub fn isFuncParam(val: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    const val_name_ptr = c.LLVMGetValueName(val);
    if (@intFromPtr(val_name_ptr) == 0) return false;
    const val_name = std.mem.span(val_name_ptr);

    // Check if it's an argument to the function
    var param = c.LLVMGetFirstParam(func);
    while (@intFromPtr(param) != 0) : (param = c.LLVMGetNextParam(param)) {
        const param_name_ptr = c.LLVMGetValueName(param);
        if (@intFromPtr(param_name_ptr) != 0) {
            const param_name = std.mem.span(param_name_ptr);
            if (std.mem.eql(u8, val_name, param_name)) return true;
        }
    }
    return false;
}

/// Check if a return instruction returns a non-pointer type
pub fn isNonPointerReturnType(ret_inst: c.LLVMValueRef) bool {
    const ret_type = c.LLVMTypeOf(ret_inst);
    if (@intFromPtr(ret_type) == 0) return false;
    return c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind;
}

/// Check if a basic block contains an RC (reference count) pattern
/// that guards a free. Pattern: load RC -> sub 1 -> cmp eq 0 -> br.
/// If the free is in the RC==0 branch, it's a conditional free.
pub fn isRCPatternFree(bb: c.LLVMValueRef) bool {
    if (@intFromPtr(bb) == 0) return false;

    // Look for the pattern: sub N, 1 followed by icmp eq N-1, 0
    // This is the standard RC decrement + check pattern.
    var inst = c.LLVMGetFirstInstruction(@ptrCast(bb));
    var has_sub_one: bool = false;
    var has_cmp_zero: bool = false;

    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Pattern: sub N, 1 (RC decrement)
        if (opcode == c.LLVMSub) {
            if (c.LLVMGetNumOperands(inst) >= 2) {
                const rhs = c.LLVMGetOperand(inst, 1);
                // Check if RHS is constant 1
                if (c.LLVMIsAConstantInt(rhs) != null) {
                    const val = c.LLVMConstIntGetZExtValue(rhs);
                    if (val == 1) {
                        has_sub_one = true;
                    }
                }
            }
        }

        // Pattern: icmp eq ptr, 0 (RC == 0 / null check)
        // H9 FIX v2: Must verify LHS is a pointer type, not just any integer comparison.
        //   - "icmp eq ptr, 0" → null check on a pointer
        //   - "icmp eq int, 0" → integer zero comparison, NOT an RC pattern
        if (opcode == c.LLVMICmp) {
            const predicate = c.LLVMGetICmpPredicate(inst);
            if (predicate == c.LLVMIntEQ) {
                if (c.LLVMGetNumOperands(inst) >= 2) {
                    const lhs = c.LLVMGetOperand(inst, 0);
                    const rhs = c.LLVMGetOperand(inst, 1);
                    const lhs_type = if (@intFromPtr(lhs) != 0) c.LLVMTypeOf(lhs) else null;
                    const lhs_is_ptr = if (lhs_type) |t| @intFromPtr(t) != 0 and c.LLVMGetTypeKind(t) == c.LLVMPointerTypeKind else false;
                    if (lhs_is_ptr and c.LLVMIsAConstantInt(rhs) != null) {
                        const val = c.LLVMConstIntGetZExtValue(rhs);
                        if (val == 0) {
                            has_cmp_zero = true;
                        }
                    }
                }
            }
        }
    }

    // Both sub-1 and cmp-0 in the same block or its predecessors
    // indicates an RC pattern guarding this free.
    return has_sub_one and has_cmp_zero;
}

/// Get the single predecessor of a basic block.
/// Returns null if the block has 0 or more than 1 predecessor.
pub fn getSinglePredecessor(bb: c.LLVMBasicBlockRef) c.LLVMValueRef {
    // Iterate all instructions in the function to find branches
    // that target this block. This is O(n) but only called when
    // a potential double-free is detected (rare in practice).
    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return null;

    var result: c.LLVMValueRef = null;
    var cur_bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(cur_bb) != 0) : (cur_bb = c.LLVMGetNextBasicBlock(cur_bb)) {
        const term = c.LLVMGetBasicBlockTerminator(cur_bb);
        if (@intFromPtr(term) == 0) continue;

        const num_succ = c.LLVMGetNumSuccessors(term);
        var i: u32 = 0;
        while (i < num_succ) : (i += 1) {
            const succ = c.LLVMGetSuccessor(term, i);
            if (@intFromPtr(succ) == @intFromPtr(bb)) {
                // Found a predecessor
                if (@intFromPtr(result) != 0) {
                    // More than one predecessor → return null
                    return null;
                }
                result = @ptrCast(cur_bb);
            }
        }
    }
    return result;
}

/// Check if two basic blocks are mutually exclusive execution paths.
/// This happens when they are siblings (same predecessor, different branches of a conditional branch).
/// In this case, only one of them executes at runtime.
pub fn areMutuallyExclusive(bb1: c.LLVMValueRef, bb2: c.LLVMValueRef) bool {
    if (@intFromPtr(bb1) == 0 or @intFromPtr(bb2) == 0) return false;
    if (@intFromPtr(bb1) == @intFromPtr(bb2)) return false;

    // Get predecessors of both blocks
    // If they share a common predecessor that is a conditional branch
    // with exactly 2 successors (bb1 and bb2), they are mutually exclusive.
    const pred1 = getSinglePredecessor(@ptrCast(bb1));
    const pred2 = getSinglePredecessor(@ptrCast(bb2));

    if (@intFromPtr(pred1) == 0 or @intFromPtr(pred2) == 0) return false;
    if (@intFromPtr(pred1) != @intFromPtr(pred2)) return false;

    // Common predecessor → check terminator instruction type
    const term_inst = c.LLVMGetBasicBlockTerminator(@ptrCast(pred1));
    if (@intFromPtr(term_inst) == 0) return false;

    const opcode = c.LLVMGetInstructionOpcode(term_inst);
    const num_successors = c.LLVMGetNumSuccessors(pred1);

    // Case 1: Conditional branch (br i1) with exactly 2 successors
    if (opcode == c.LLVMBr and num_successors == 2) {
        const succ0 = c.LLVMGetSuccessor(pred1, 0);
        const succ1 = c.LLVMGetSuccessor(pred1, 1);

        // Check if the two successors are exactly bb1 and bb2
        const match = (@intFromPtr(succ0) == @intFromPtr(bb1) and @intFromPtr(succ1) == @intFromPtr(bb2)) or
            (@intFromPtr(succ0) == @intFromPtr(bb2) and @intFromPtr(succ1) == @intFromPtr(bb1));
        return match;
    }

    // M4 FIX: Case 2: Switch instruction → all case/default targets are mutually exclusive
    if (opcode == c.LLVMSwitch and num_successors >= 2) {
        var found_bb1 = false;
        var found_bb2 = false;
        var succ_idx: u32 = 0;
        while (succ_idx < num_successors) : (succ_idx += 1) {
            const succ = c.LLVMGetSuccessor(pred1, succ_idx);
            if (@intFromPtr(succ) == @intFromPtr(bb1)) found_bb1 = true;
            if (@intFromPtr(succ) == @intFromPtr(bb2)) found_bb2 = true;
            if (found_bb1 and found_bb2) return true; // Both blocks are switch targets → mutually exclusive
        }
        return false;
    }

    return false;
}
