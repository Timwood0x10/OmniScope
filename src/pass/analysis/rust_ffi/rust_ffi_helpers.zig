//! Rust FFI Detection Helpers
//!
//! Extracted from rust_ffi_auditor.zig for modularity.
//! Contains pattern-matching helpers for Rust FFI boundary detection,
//! ownership transfer patterns, and stack escape analysis.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const ffi_language_classifier = @import("../ffi/ffi_language_classifier.zig");

// ============================================================================
// Detection Helpers
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
        "_Znwm", // operator new(unsigned long) - Rust's default allocator
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
        "c_void",
        "c_char",
        "c_int",
        "c_long",
        "c_uint",
        "c_ulong",
        "c_float",
        "c_double",
        "CStr",
        "CString",
        "from_raw",
        "into_raw",
        "as_ptr",
        "to_ptr",
        "to_str",
        "from_bytes_with_nul_unchecked",
        "from_bytes_with_nul",
    };

    for (core_ffi_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if function is from libc crate (POSIX/C standard library bindings)
pub fn isLibcFunction(callee_name: []const u8) bool {
    const libc_patterns = [_][]const u8{
        // POSIX memory
        "malloc",
        "calloc",
        "realloc",
        "free",
        "memalign",
        "posix_memalign",

        // POSIX I/O
        "open",
        "read",
        "write",
        "close",
        "fcntl",
        "ioctl",
        "fstat",
        "lseek",
        "mmap",
        "munmap",

        // POSIX threads
        "pthread_create",
        "pthread_join",
        "pthread_mutex_lock",
        "pthread_mutex_unlock",
        "pthread_cond_wait",
        "pthread_cond_signal",

        // String operations
        "strlen",
        "strcpy",
        "strncpy",
        "strcat",
        "strncat",
        "strcmp",
        "strncmp",
        "strdup",

        // Network
        "socket",
        "bind",
        "listen",
        "accept",
        "connect",
        "send",
        "recv",

        // Time
        "time",
        "gettimeofday",
        "clock_gettime",
        "sleep",
        "usleep",
        "nanosleep",

        // Environment
        "getenv",
        "setenv",
        "unsetenv",

        // Error handling
        "errno",
        "strerror",
        "perror",
    };

    for (libc_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Classify Rust FFI boundary type for enhanced detection
pub fn classifyFfiBoundaryType(
    callee_name: []const u8,
    module_name: ?[]const u8,
) enum {
    /// Standard extern "C" function
    standard,
    /// core::ffi utility (CStr, CString, etc.)
    core_ffi,
    /// libc crate wrapper
    libc_crate,
    /// OS-specific API (Win32, macOS, Linux)
    os_api,
    /// Unknown/custom FFI
    unknown,
} {
    _ = module_name; // Reserved for future use

    if (isCoreFfiFunction(callee_name)) return .core_ffi;
    if (isLibcFunction(callee_name)) return .libc_crate;

    // OS-specific APIs
    const win32_patterns = [_][]const u8{ "CreateFile", "ReadFile", "WriteFile", "CloseHandle" };
    const macos_patterns = [_][]const u8{ "CFStringCreate", "dispatch_async", "kqueue" };
    const linux_patterns = [_][]const u8{ "epoll_create", "inotify_init", "signalfd" };

    for (win32_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }
    for (macos_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }
    for (linux_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }

    // Default to standard extern "C"
    if (isExternCCall(callee_name)) return .standard;

    return .unknown;
}

/// Detect Rust FFI pairing functions (populates into_raw/from_raw sets)
/// POT-BUG-8 FIX: Changed from AutoHashMap(usize, void) to StringHashMap(void)
/// to use string content as key instead of pointer address, preventing missed
/// ownership-transfer detections when the same function name has different
/// backing string allocations.
pub fn detectRustFfiPairingFunctions(
    func: c.LLVMValueRef,
    into_raw_set: *std.StringHashMap(void),
    from_raw_set: *std.StringHashMap(void),
) void {
    var has_into_raw = false;
    var has_from_raw = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands == 0) continue;
            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (isRustIntoRawCall(name_slice)) has_into_raw = true;
            if (isRustFromRawCall(name_slice)) has_from_raw = true;
        }
        if (has_into_raw and has_from_raw) break;
    }

    if (has_into_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_name_slice = std.mem.sliceTo(func_name_raw, 0);
            into_raw_set.put(func_name_slice, {}) catch {};
        }
    }
    if (has_from_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_name_slice = std.mem.sliceTo(func_name_raw, 0);
            from_raw_set.put(func_name_slice, {}) catch {};
        }
    }
}

// ============================================================================
// Stack Escape Detection Helpers (Rule 5)
// ============================================================================

/// Check if function name has a Rust mangled name prefix (_R / _ZN with disambiguation).
/// _ZN is ambiguous between C++ Itanium ABI and Rust legacy v0 — uses
/// ffi_language_classifier.isRustMangledName for disambiguation.
pub fn isRustMangledName(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_R")) {
        return true;
    }
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        return ffi_language_classifier.isRustMangledName(func_name);
    }
    return false;
}

// ============================================================================
// Detection Helpers (module-level functions)
// ============================================================================

/// Check if an FFI callee may store/retain a pointer argument beyond the call.
/// Uses heuristic name patterns for retain/store/register callbacks.
pub fn mayRetainPointer(callee_name: []const u8) bool {
    // Functions that copy data don't retain the original pointer
    const copy_indicators = [_][]const u8{
        "strdup",   "strndup",         "memcpy",    "memmove",       "strcpy", "strncpy",
        "set_name", "set_description", "set_label", "set_zone_name",
    };
    for (copy_indicators) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return false;
    }

    const retain_indicators = [_][]const u8{
        "_store_",  "_save_", "_set_",  "_register_",
        "_retain_", "_keep_", "_hold_",
    };
    for (retain_indicators) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }
    // Callback registration patterns
    if (std.mem.indexOf(u8, callee_name, "callback") != null or
        std.mem.indexOf(u8, callee_name, "register") != null)
    {
        return true;
    }
    return false;
}

/// Check if a value originates from a Rust allocator call within the same function.
/// Walks use-def chains through phi/select/bitcast/GEP instructions to find
/// the ultimate source. Returns true if traced back to isRustAllocCall.
pub fn ptrOriginatesFromRustAlloc(
    func: c.LLVMValueRef,
    val: c.LLVMValueRef,
    visited: *std.AutoHashMap(usize, void),
) bool {
    if (@intFromPtr(val) == 0) return false;
    if (visited.contains(@intFromPtr(val))) return false;
    visited.put(@intFromPtr(val), {}) catch return false;

    const opcode = c.LLVMGetInstructionOpcode(val);

    // Check if this is a call instruction returning from a Rust allocator
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(val));
        if (num_operands > 0) {
            const callee = c.LLVMGetOperand(val, num_operands - 1);
            if (@intFromPtr(callee) != 0) {
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) != 0) {
                    const name_slice = std.mem.sliceTo(callee_name, 0);
                    if (isRustAllocCall(name_slice)) return true;
                }
            }
        }
        return false;
    }

    // Follow phi, select, bitcast, GEP, ptrtoint/inttoptr chains
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr or
        opcode == c.LLVMPHI or opcode == c.LLVMSelect or
        opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr)
    {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(val));
        var i: c_uint = 0;
        while (i < num_operands) : (i += 1) {
            const op = c.LLVMGetOperand(val, i);
            if (ptrOriginatesFromRustAlloc(func, op, visited)) return true;
        }
    }

    return false;
}

/// Pure-consumption functions that read pointers but don't store them.
/// Safe to pass stack addresses to — no escape risk.
pub fn isPureConsumptionFunction(callee_name: []const u8) bool {
    const safe_fns = [_][]const u8{
        "memcpy",  "memmove",  "printf",  "fprintf",
        "sprintf", "snprintf", "puts",    "fputs",
        "strlen",  "strcmp",   "strncmp",
    };
    for (safe_fns) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }
    return false;
}
