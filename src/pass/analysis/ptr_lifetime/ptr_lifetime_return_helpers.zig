//! Return Violation Helpers — split from ptr_lifetime_violations.zig to keep file < 1000 lines.
//!
//! Contains helper functions for return value violation detection:
//!   - is_lifecycle_bound_return — lifecycle-bound handle detection
//!   - isSretAlloca — LLVM sret pattern recognition
//!   - isAllocaReturnSuppressed — constructor/factory suppression
//!   - isStackEscapeSuppressed — known safe stack escapes
//!
//! These functions support checkReturnViolation() in ptr_lifetime_violations.zig.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const word_boundary = @import("../../../utils/word_boundary.zig");

/// Check if a function's return value is a lifecycle-bound handle.
/// Lifecycle-bound handles are pointers whose lifetime is tied to
/// another object (e.g., FILE* tied to fd, sqlite3* tied to db handle).
pub fn is_lifecycle_bound_return(func_name: []const u8, ptr_info: PtrInfo) bool {
    if (ptr_info.resource_type == .none) return false;
    if (ptr_info.resource_type == .dlopen_handle) {
        return std.mem.indexOf(u8, func_name, "dlsym") != null;
    }
    if (ptr_info.resource_type == .mmap_region) {
        return std.mem.indexOf(u8, func_name, "mmap") != null;
    }
    if (ptr_info.resource_type == .file_handle) {
        return std.mem.indexOf(u8, func_name, "fopen") != null;
    }
    if (ptr_info.resource_type == .socket_fd) {
        return std.mem.indexOf(u8, func_name, "socket") != null;
    }
    if (ptr_info.resource_type == .jni_ref) {
        return std.mem.indexOf(u8, func_name, "NewStringUTF") != null or
            std.mem.indexOf(u8, func_name, "NewByteArray") != null;
    }
    if (ptr_info.resource_type == .python_obj) {
        return std.mem.indexOf(u8, func_name, "Py_BuildValue") != null or
            std.mem.indexOf(u8, func_name, "PyTuple_New") != null;
    }
    return false;
}

/// Checks if a retval is an sret-style alloca (return value slot).
/// LLVM generates "alloca ptr" as a local slot to hold the return value.
/// The alloca is on the stack but only holds a pointer to heap memory.
/// Returning the alloca address is standard LLVM behavior, not a stack escape.
///
/// Detection: retval is an alloca, its allocated type is ptr (not a data buffer),
/// and the function's return type is also ptr.
pub fn isSretAlloca(retval: c.LLVMValueRef, _: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    // retval must be an alloca instruction
    if (c.LLVMGetInstructionOpcode(retval) != c.LLVMAlloca) return false;

    // The alloca's allocated type must be ptr (not i8, [N x i8], etc.)
    const alloca_type = c.LLVMGetAllocatedType(retval);
    if (@intFromPtr(alloca_type) == 0) return false;
    if (c.LLVMGetTypeKind(alloca_type) != c.LLVMPointerTypeKind) return false;

    // The function's return type must also be ptr.
    // Use LLVMGetElementType(LLVMTypeOf(func)) to get the function type,
    // consistent with the rest of the codebase.
    const func_ptr_type = c.LLVMTypeOf(func);
    if (@intFromPtr(func_ptr_type) == 0) return false;
    const func_type = c.LLVMGetElementType(func_ptr_type);
    if (@intFromPtr(func_type) == 0) return false;
    if (c.LLVMGetTypeKind(func_type) != c.LLVMFunctionTypeKind) return false;
    const ret_type = c.LLVMGetReturnType(func_type);
    if (@intFromPtr(ret_type) == 0) return false;
    if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return false;

    return true;
}

/// Checks if a function returning an alloca pointer should be suppressed.
/// Many C projects use alloca as temporary workspace in constructor/factory
/// functions (e.g., sqlite3PExpr, sqlite3SelectNew). The alloca is just an
/// intermediate buffer — the actual return value points to heap memory that
/// was copied from the alloca. Reporting these creates massive noise.
pub fn isAllocaReturnSuppressed(func_name: []const u8, ptr_info: PtrInfo) bool {
    // Only applies to alloca-sourced pointers.
    if (!std.mem.startsWith(u8, ptr_info.source_desc, "stack")) return false;

    // Constructor/factory naming patterns.
    const factory_suffixes = [_][]const u8{
        "New",  "Create", "Make",  "Alloc", "AllocX",
        "Init", "Open",   "Build", "From",  "Copy",
    };
    for (factory_suffixes) |suffix| {
        if (std.mem.endsWith(u8, func_name, suffix)) return true;
    }

    // Common C API patterns that use alloca internally.
    const factory_substrings = [_][]const u8{
        "Expr",     "Select",   "Token",        "SrcList",     "Name",
        "Trigger",  "CollSeq",  "Vtab",         "Module",
        // Extended factory patterns for C API recognition
             "Malloc",
        "Alloc",    "Realloc",  "Hash",         "List",        "Table",
        "Cache",    "Pool",
        // Callback/Hook patterns that legitimately take stack addrs
            "Hook",         "Callback",    "Handler",
        "Notifier", "Observer", "busy_handler", "commit_hook", "rollback_hook",
        "wal_hook",
    };
    for (factory_substrings) |sub| {
        if (std.mem.indexOf(u8, func_name, sub) != null) {
            // Only suppress if the function also has a factory-like prefix.
            const factory_prefixes = [_][]const u8{
                "sqlite3",  "rowSet",    "alloc", "create",
                "vtab",     "attach",    "token",
                // Extended prefixes for broader coverage
                "curl_",
                "uv_",      "json_",     "xml_",  "ldap_",
                "avcodec_", "avformat_",
            };
            for (factory_prefixes) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) return true;
            }
            // Suppress callback/hook patterns regardless of prefix
            if (std.mem.indexOf(u8, func_name, "Hook") != null or
                std.mem.indexOf(u8, func_name, "Callback") != null or
                std.mem.indexOf(u8, func_name, "Handler") != null or
                std.mem.indexOf(u8, func_name, "busy_handler") != null or
                std.mem.indexOf(u8, func_name, "_hook") != null)
            {
                return true;
            }
        }
    }

    // Thread creation pattern - pthread_create legitimately takes stack addr
    if (std.mem.indexOf(u8, func_name, "pthread_create") != null) {
        return true;
    }

    return false;
}

/// Check if a stack escape should be suppressed.
/// Callback/hook patterns legitimately receive stack pointer.
pub fn isStackEscapeSuppressed(callee_name: []const u8, _: PtrInfo) bool {
    // Callback/Hook patterns that legitimately take stack pointers.
    // Use word-boundary-aware matching to avoid false positives:
    //   - my_handler should NOT match Handler
    //   - myCallback SHOULD match Callback (camelCase convention)
    // Strategy: match if pattern appears at start, end, or after '_'/'.' separator
    const callback_patterns = [_][]const u8{
        "Hook",         "Callback",    "Handler",       "Notifier", "Observer",
        "busy_handler", "commit_hook", "rollback_hook", "wal_hook", "pthread_create",
        "pthread_join",
    };
    for (callback_patterns) |pattern| {
        if (word_boundary.isWordBoundaryMatch(callee_name, pattern)) {
            return true;
        }
    }
    return false;
}
