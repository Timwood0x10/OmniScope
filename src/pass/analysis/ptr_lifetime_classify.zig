const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const pt = @import("ptr_lifetime_types.zig");
const ResourceType = pt.ResourceType;
const HEAP_ALLOC_FUNCTIONS = pt.HEAP_ALLOC_FUNCTIONS;
const KNOWN_DEALLOCATORS = pt.KNOWN_DEALLOCATORS;

/// Function classification and identification utilities for PtrLifetimePass.
/// Extracted from ptr_lifetime.zig to improve code organization.
///
/// This module contains pure functions that classify LLVM function names
/// into categories (alloc/free/resource) based on naming conventions.
/// No state is maintained — all functions are deterministic lookups.
pub fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
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

pub fn isFreeFunction(fn_name: []const u8) bool {
    // Exact matches for well-known free/dealloc functions
    const exact_fns = [_][]const u8{
        "free",       "realloc",  "kfree",   "vfree",
        "g_free",     "cfree",    "__rust_dealloc", "__rdl_dealloc",
        "__rg_dealloc",
    };
    for (exact_fns) |exact| {
        if (std.mem.eql(u8, fn_name, exact)) return true;
    }
    // Suffix patterns: function must END with these to avoid false positives
    // on names like "free_size", "freestyle", "set_freedom" etc.
    const suffixes = [_][]const u8{
        "_free",      "_dealloc", "_deallocate",
        "_release",   "_destroy", "_drop",
        "delete",     "Delete",   "deallocate",
        "Deallocate",
    };
    for (suffixes) |suffix| {
        if (fn_name.len >= suffix.len and
            std.mem.eql(u8, fn_name[fn_name.len - suffix.len ..], suffix))
        {
            return true;
        }
    }
    // C++ operator delete (contains space)
    if (std.mem.indexOf(u8, fn_name, "operator delete") != null) return true;
    return false;
}

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

pub fn isSameOrAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (isDerivedFrom(a, b) or isDerivedFrom(b, a)) return true;
    return false;
}

pub fn isDerivedFrom(value: c.LLVMValueRef, base: c.LLVMValueRef) bool {
    if (@intFromPtr(value) == 0 or @intFromPtr(base) == 0) return false;
    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMBitCast or opcode == c.LLVMPtrToInt or
        opcode == c.LLVMIntToPtr or opcode == c.LLVMAddrSpaceCast)
    {
        const src = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(src) == @intFromPtr(base)) return true;
        if (isDerivedFrom(src, base)) return true;
    }
    if (opcode == c.LLVMGetElementPtr) {
        const ptr_op = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(ptr_op) == @intFromPtr(base)) return true;
        if (isDerivedFrom(ptr_op, base)) return true;
    }
    return false;
}

pub fn isSocketClose(fn_name: []const u8) bool {
    const non_socket_patterns = [_][]const u8{
        "file_",   "document", "database",  "db_",
        "window",  "dir_",     "stream",    "buf_",
        "mem_",    "str_",     "xml_",      "json_",
        "log_",    "config",   "session",   "cache",
        "mutex",   "lock",     "semaphore", "cond_",
        "thread",  "process",  "handle",    "ref_",
        "context", "scope",    "state",     "node",
    };
    for (non_socket_patterns) |np| {
        if (std.mem.indexOf(u8, fn_name, np) != null and
            std.mem.indexOf(u8, fn_name, "close") != null)
        {
            return false;
        }
    }

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
    if (std.mem.endsWith(u8, fn_name, "_close")) {
        const prefix = fn_name[0 .. fn_name.len - 6];
        const socket_prefixes = [_][]const u8{
            "sock",   "fd_",    "conn", "pipe",
            "listen", "accept",
        };
        for (socket_prefixes) |sp| {
            if (std.mem.indexOf(u8, prefix, sp) != null) return true;
        }
    }
    return false;
}

pub fn is_resource_alloc_function(fn_name: []const u8) ?ResourceType {
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return .dlopen_handle;
    if (std.mem.indexOf(u8, fn_name, "mmap64") != null or
        std.mem.indexOf(u8, fn_name, "mmap2") != null or
        std.mem.indexOf(u8, fn_name, "mmap") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "shm_open") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "fopen") != null) return .file_handle;
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return .socket_fd;
    if (std.mem.indexOf(u8, fn_name, "JNI_") != null or
        std.mem.indexOf(u8, fn_name, "Java_") != null) return .jni_ref;
    if (std.mem.startsWith(u8, fn_name, "Py")) return .python_obj;
    return null;
}

pub fn get_resource_type(fn_name: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null or std.mem.indexOf(u8, fn_name, "dlsym") != null) return "dlhandle";
    if (std.mem.indexOf(u8, fn_name, "mmap") != null) return "mmap";
    if (std.mem.indexOf(u8, fn_name, "fopen") != null or std.mem.indexOf(u8, fn_name, "FILE") != null) return "file";
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return "socket";
    if (std.mem.indexOf(u8, fn_name, "JNI") != null) return "jni";
    if (std.mem.indexOf(u8, fn_name, "Py_") != null) return "python";
    return null;
}
