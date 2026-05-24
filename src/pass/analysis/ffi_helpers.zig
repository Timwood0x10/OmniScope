//! FFI Helper Functions for Rust FFI Auditor
//!
//! Module-level helper functions extracted from rust_ffi_auditor.zig.
//! These are pure functions with no state dependency on RustFfiAuditor struct.
//!
//! Covers: function name classification, callee pattern matching,
//! FFI boundary type classification, and ownership transfer detection.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const ptr_types = @import("ptr_lifetime_types.zig");

// ============================================================================
// Function Name Utilities
// ============================================================================

/// Extract function name from LLVM value reference
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "unknown";
    return std.mem.span(name_ptr);
}

/// Check if a callee name is a Rust into_raw (ownership transfer OUT) call
pub fn isRustIntoRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "into_raw",
        "8into_raw",
        "Box.*into_raw",
        "CString.*into_raw",
        "Vec.*leak",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust from_raw (ownership transfer IN) call
pub fn isRustFromRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "from_raw",
        "8from_raw",
        "Box.*from_raw",
        "CString.*from_raw",
        "from_raw_parts",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust as_ptr (borrow escape) call
pub fn isRustAsPtrCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "as_ptr",
        "as_mut_ptr",
        "slice::as_ptr",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a C free() call
pub fn isCFreeCall(callee_name: []const u8) bool {
    return std.mem.eql(u8, callee_name, "free") or
        std.mem.indexOf(u8, callee_name, "free@") != null;
}

/// Check if a callee name is a Rust allocator call (_Znwm, __rust_alloc, etc.)
pub fn isRustAllocCall(callee_name: []const u8) bool {
    const rust_alloc_patterns = [_][]const u8{
        "_Znwm", // operator new(unsigned long)
        "_Znw", // operator new variants
        "__rust_alloc",
        "__rust_alloc_zeroed",
        "alloc::alloc::alloc",
        "alloc::alloc::alloc_zeroed",
    };
    for (rust_alloc_patterns) |pattern| {
        if (std.mem.startsWith(u8, callee_name, pattern)) return true;
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name looks like an extern "C" function
pub fn isExternCCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;
    if (callee_name[0] == '_') return false;
    if (std.mem.startsWith(u8, callee_name, "_Z")) return false;
    if (std.mem.startsWith(u8, callee_name, "_R")) return false;
    return true;
}

/// Check if function is from core::ffi crate (Rust standard FFI utilities)
pub fn isCoreFfiFunction(callee_name: []const u8) bool {
    const core_ffi_patterns = [_][]const u8{
        "c_void",  "c_char",   "c_int",  "c_long",                        "c_uint",              "c_ulong",
        "c_float", "c_double", "CStr",   "CString",                       "from_raw",            "into_raw",
        "as_ptr",  "to_ptr",   "to_str", "from_bytes_with_nul_unchecked", "from_bytes_with_nul",
    };
    for (core_ffi_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if function is from libc crate (POSIX/C standard library bindings)
pub fn isLibcFunction(callee_name: []const u8) bool {
    const libc_patterns = [_][]const u8{
        // POSIX memory
        "malloc",             "calloc",               "realloc",           "free",                "memalign",       "posix_memalign",
        // POSIX I/O
        "open",               "read",                 "write",             "close",               "fcntl",          "ioctl",
        "fstat",              "lseek",                "mmap",              "munmap",
        // POSIX threads
                     "pthread_create", "pthread_join",
        "pthread_mutex_lock", "pthread_mutex_unlock", "pthread_cond_wait", "pthread_cond_signal",
        // String operations
        "strlen",         "strcpy",
        "strncpy",            "strcat",               "strncat",           "strcmp",              "strncmp",        "strdup",
        // Network
        "socket",             "bind",                 "listen",            "accept",              "connect",        "send",
        "recv",
        // Time
                      "time",                 "gettimeofday",      "clock_gettime",       "sleep",          "usleep",
        "nanosleep",
        // Environment
                 "getenv",               "setenv",            "unsetenv",
        // Error handling
                   "errno",          "strerror",
        "perror",
    };
    for (libc_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

// ============================================================================
// FFI Boundary Classification
// ============================================================================

/// Classify Rust FFI boundary type for enhanced detection
pub fn classifyFfiBoundaryType(
    callee_name: []const u8,
    _: ?[]const u8,
) enum {
    unknown,
    /// C standard library / POSIX API
    c_standard,
    /// Rust core::ffi types (CStr, CString, c_void, etc.)
    core_ffi,
    /// External library via extern "C"
    external_c,
    /// OS kernel / runtime API (platform-specific)
    os_api,
    /// Rust allocator intrinsics (_Znwm, __rust_alloc, etc.)
    rust_allocator,
    /// Custom user-defined FFI wrapper
    custom_wrapper,
} {
    if (isLibcFunction(callee_name)) return .c_standard;
    if (isCoreFfiFunction(callee_name)) return .core_ffi;

    // OS-specific patterns
    const os_patterns = [_][]const u8{
        "mach_",           "pthread_",     "dladdr",    "sysctl",
        "GetModuleHandle", "VirtualAlloc", "HeapAlloc",
    };
    for (os_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return .os_api;
    }

    if (isRustAllocCall(callee_name)) return .rust_allocator;
    if (isExternCCall(callee_name)) return .external_c;

    return .unknown;
}

/// Detect paired into_raw/from_raw functions in a module
pub fn detectRustFfiPairingFunctions(
    module: c.LLVMModuleRef,
) struct { into_raw_count: usize, from_raw_count: usize } {
    var into_raw_count: usize = 0;
    var from_raw_count: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (!c.LLVMHasExternalLinkage(func)) continue;
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);

        if (isRustIntoRawCall(name)) into_raw_count += 1;
        if (isRustFromRawCall(name)) from_raw_count += 1;
    }

    return .{ .into_raw_count = into_raw_count, .from_raw_count = from_raw_count };
}

/// Check if a function name looks like a mangled Rust name
pub fn isRustMangledName(func_name: []const u8) bool {
    if (func_name.len < 2) return false;
    // Common Rust mangling prefixes
    if (std.mem.startsWith(u8, func_name, "_Z") or
        std.mem.startsWith(u8, func_name, "_R"))
    {
        return true;
    }
    // Also check for hash-based names common in newer Rust
    if (std.mem.indexOf(u8, func_name, ".h") != null) {
        // Has type hash suffix like _ZN3foo17hba3a1b2c3d4e5f6E
        return true;
    }
    return false;
}

// ============================================================================
// Ownership & Retention Analysis
// ============================================================================

/// Check if an FFI callee may retain a pointer beyond the caller's scope.
/// Conservative: assumes most FFI functions MAY retain unless known-safe.
pub fn mayRetainPointer(callee_name: []const u8) bool {
    // Known safe: pure functions that don't retain
    const safe_patterns = [_][]const u8{
        "memcmp",  "memcpy",  "memmove",  "memset",
        "strlen",  "strcmp",  "strncmp",  "strncpy",
        "printf",  "fprintf", "snprintf", "sprintf",
        "tolower", "toupper", "isalpha",  "isdigit",
    };
    for (safe_patterns) |pat| {
        if (std.mem.eql(u8, callee_name, pat)) return false;
    }

    // Known retaining: storage functions
    const retain_patterns = [_][]const u8{
        "strcpy",            "strcat",       "strdup",                 "strndup",
        "sqlite3_bind",      "sqlite3_exec", "SetEnvironmentVariable", "putenv",
        "register_callback", "set_handler",  "g_signal_connect",
    };
    for (retain_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }

    // Default: assume may retain for safety
    return true;
}

/// Check if a value originates from a Rust global allocator allocation.
/// Traces through bitcast/GEP/load chains to find alloc source.
pub fn ptrOriginatesFromRustAlloc(
    val: c.LLVMValueRef,
    func: c.LLVMValueRef,
) bool {
    if (@intFromPtr(val) == 0) return false;

    const opcode = c.LLVMGetInstructionOpcode(val);

    // Direct: call to Rust allocator
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const called = c.LLVMGetCalledValue(val);
        if (@intFromPtr(called) != 0) {
            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) != 0) {
                if (isRustAllocCall(std.mem.span(name_ptr))) return true;
            }
        }
    }

    // Recursive: trace through bitcast/GEP wrappers
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
        const src = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(src) != 0 and ptrOriginatesFromRustAlloc(src, func))
            return true;
    }

    // Trace through load: check what was stored to the loaded pointer
    if (opcode == c.LLVMLoad) {
        const src = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(src) != 0) {
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
                    if (c.LLVMGetOperand(inst, 1) != src) continue;
                    const stored_val = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(stored_val) != 0 and
                        ptrOriginatesFromRustAlloc(stored_val, func))
                        return true;
                }
            }
        }
    }

    return false;
}

/// Check if a function is a pure consumption function (uses pointer but doesn't store).
/// These are safe to pass stack/short-lived pointers to.
pub fn isPureConsumptionFunction(callee_name: []const u8) bool {
    const pure_patterns = [_][]const u8{
        "printf",  "fprintf", "snprintf", "sprintf",
        "puts",    "fputc",   "fwrite",   "memcmp",
        "memcpy",  "memmove", "memset",   "strlen",
        "strcmp",  "strncmp", "strncpy",  "tolower",
        "toupper", "isalpha", "isdigit",  "isspace",
        "atoi",    "atol",    "atof",     "strtod",
        "strtol",  "htonl",   "ntohl",    "htons",
        "ntohs",   "crc32",   "md5",      "sha1",
        "hash",
    };
    for (pure_patterns) |pat| {
        if (std.mem.eql(u8, callee_name, pat)) return true;
    }
    return false;
}
