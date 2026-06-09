//! Language Detection Functions for Zone Classification
//!
//! This file contains language-specific detection functions and C function classification.
//! These are internal helpers used by zone_classifier.zig.

const std = @import("std");
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");
const ZoneKind = @import("../types/zone_types.zig").ZoneKind;

/// Detect if function is Rust.
pub fn isRustFunction(func_name: []const u8) bool {
    // Check for Rust v0 mangling prefix (_R...)
    if (std.mem.startsWith(u8, func_name, "_R")) return true;

    // Check for _ZN (Itanium nested name mangling) — could be Rust or C++
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        return ffi_language_classifier.isRustMangledName(func_name);
    }

    // Check for Rust-specific markers in mangled names
    if (std.mem.indexOf(u8, func_name, "$u20$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$LT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$GT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$C$") != null) return true;

    // Check for Rust namespace patterns (demangled form)
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "core::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "alloc::") != null) return true;

    return false;
}

/// Detect if function is Zig.
pub fn isZigFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "std.")) return true;
    // Only match Zig builtins (@ptrCast, @intToPtr, etc.), not LLVM globals
    if (std.mem.indexOf(u8, func_name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@alignCast") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@intToPtr") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@ptrToInt") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@cImport") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@cInclude") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@bitCast") != null) return true;
    return false;
}

/// Detect if function is Go.
pub fn isGoFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "runtime.")) return true;
    if (std.mem.startsWith(u8, func_name, "main.")) return true;
    if (std.mem.indexOf(u8, func_name, "C.") != null) return true;

    // Go runtime internal symbols (fine-grained detection)
    // These are unambiguous Go runtime markers that should be classified
    // as Go functions for correct zone classification (.runtime_internal).
    const is_go_runtime_internal = blk: {
        if (!std.mem.startsWith(u8, func_name, "runtime.")) break :blk false;

        const rest = func_name["runtime.".len..];

        if (std.mem.startsWith(u8, rest, "gc") or
            std.mem.startsWith(u8, rest, "mallocgc") or
            std.mem.startsWith(u8, rest, "scanobject") or
            std.mem.startsWith(u8, rest, "markroot") or
            std.mem.startsWith(u8, rest, "sweep") or
            std.mem.startsWith(u8, rest, "scanstack"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "schedule") or
            std.mem.startsWith(u8, rest, "park") or
            std.mem.startsWith(u8, rest, "wake") or
            std.mem.startsWith(u8, rest, "stopm") or
            std.mem.startsWith(u8, rest, "startm") or
            std.mem.startsWith(u8, rest, "handoffp"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "chan") or
            std.mem.startsWith(u8, rest, "select"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "interface") or
            std.mem.startsWith(u8, rest, "assertI2I") or
            std.mem.startsWith(u8, rest, "assertE2I") or
            std.mem.startsWith(u8, rest, "convI2E"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "mapaccess") or
            std.mem.startsWith(u8, rest, "mapassign") or
            std.mem.startsWith(u8, rest, "mapdelete") or
            std.mem.startsWith(u8, rest, "mapiter"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "newproc") or
            std.mem.startsWith(u8, rest, "goexit") or
            std.mem.startsWith(u8, rest, "systemstack") or
            std.mem.startsWith(u8, rest, "morestack") or
            std.mem.startsWith(u8, rest, "lessstack"))
        {
            break :blk true;
        }

        if (std.mem.startsWith(u8, rest, "defer")) {
            break :blk true;
        }

        break :blk false;
    };

    if (is_go_runtime_internal) return true;

    return false;
}

/// Detect if function is C++.
pub fn isCppFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_Z")) return true;
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    return false;
}

/// Detect if function is C using name-based heuristics.
///
/// C functions typically use snake_case naming and don't have
/// Rust/Zig/Go/C++ specific prefixes.
pub fn isCFunction(func_name: []const u8) bool {
    if (func_name.len == 0) return false;

    if (isRustFunction(func_name)) return false;
    if (isZigFunction(func_name)) return false;
    if (isGoFunction(func_name)) return false;
    if (isCppFunction(func_name)) return false;

    if (std.mem.startsWith(u8, func_name, "_")) return false;
    if (std.mem.indexOf(u8, func_name, "$") != null) return false;

    if (std.mem.indexOf(u8, func_name, "llvm.") != null) return false;
    if (std.mem.indexOf(u8, func_name, "__gnu_cxx") != null) return false;
    if (std.mem.indexOf(u8, func_name, "__cxa_") != null) return false;

    return true;
}

/// Classify a C function based on name patterns.
///
/// For pure C code, we use name heuristics to detect FFI relevance:
/// - snake_case with known FFI patterns → .ffi
/// - pure internal C logic → .unknown (conservative)
pub fn classifyCFunction(func_name: []const u8) ZoneKind {
    // R7.0: Library internal patterns — these are runtime-internal, NOT FFI boundaries.
    // Migrated from FPWhitelist Category 3 (project-specific contextual suppressions).
    const C_INTERNAL_PATTERNS = [_][]const u8{
        "uv__", // libuv internal functions (e.g., uv__socket)
        "sqlite3Mem", // SQLite custom allocator shims
        "__pthread", // glibc pthread internals
    };
    for (C_INTERNAL_PATTERNS) |pat| {
        if (std.mem.startsWith(u8, func_name, pat) or
            std.mem.indexOf(u8, func_name, pat) != null)
        {
            return .runtime_internal;
        }
    }

    // C_STDLIB_PATTERNS: Standard C library and POSIX functions.
    // In a pure C project, calling malloc/fopen/read/write etc. is normal C
    // code, NOT an FFI boundary. These must be checked before C_FFI_PATTERNS
    // to avoid false positive FFI classifications for pure C code.
    const C_STDLIB_PATTERNS = [_][]const u8{
        // Memory allocation
        "malloc",
        "calloc",
        "realloc",
        "free",

        // Memory operations
        "memcpy",
        "memmove",
        "memset",
        "memcmp",

        // File I/O
        "fopen",
        "fclose",
        "fread",
        "fwrite",
        "fprintf",
        "fscanf",
        "fflush",
        "fseek",
        "ftell",
        "rewind",
        "remove",
        "rename",
        "tmpfile",
        "tmpnam",

        // String operations
        "strcpy",
        "strncpy",
        "strcat",
        "strncat",
        "strlen",
        "strcmp",
        "strncmp",
        "strchr",
        "strrchr",
        "strstr",
        "strtok",
        "strspn",
        "strcspn",
        "sprintf",
        "snprintf",
        "sscanf",

        // Conversion
        "atoi",
        "atol",
        "atoll",
        "strtol",
        "strtoul",
        "strtoll",
        "strtoull",
        "strtod",
        "strtof",
        "strtold",

        // POSIX/Network I/O
        "socket",
        "connect",
        "bind",
        "listen",
        "accept",
        "send",
        "recv",
        "sendto",
        "recvfrom",
        "setsockopt",
        "getsockopt",
        "shutdown",
        "select",
        "poll",
        "epoll",
        "ioctl",
        "fcntl",

        // POSIX File I/O
        "open",
        "close",
        "read",
        "write",
        "pread",
        "pwrite",
        "lseek",
        "truncate",
        "ftruncate",
        "fsync",
        "fdatasync",
        "sync",
        "pipe",
        "dup",
        "dup2",

        // POSIX File system
        "stat",
        "lstat",
        "fstat",
        "mkdir",
        "rmdir",
        "chdir",
        "getcwd",
        "chmod",
        "chown",
        "link",
        "unlink",
        "symlink",
        "readlink",
        "realpath",
        "access",
        "opendir",
        "readdir",
        "closedir",

        // POSIX Memory mapping
        "mmap",
        "munmap",
        "mprotect",
        "mlock",
        "munlock",
        "msync",
        "brk",
        "sbrk",

        // Threading (POSIX threads)
        "pthread_",
        "sem_",
        "shm_",
        "msg_",
        "mkfifo",
        "mq_",

        // Process management
        "fork",
        "exec",
        "execve",
        "execvp",
        "wait",
        "waitpid",
        "waitid",
        "kill",
        "signal",
        "raise",
        "alarm",
        "pause",
        "sleep",
        "usleep",
        "nanosleep",
        "getpid",
        "getppid",
        "exit",

        // Control flow
        "setjmp",
        "longjmp",

        // Platform-specific allocators
        "malloc_zone",
    };
    for (C_STDLIB_PATTERNS) |pat| {
        // Use word-boundary matching: the pattern must appear at the start of the
        // function name or be preceded by a '_' separator. This prevents false
        // positives where a short stdlib word (e.g., "open") appears inside a
        // longer compound word (e.g., "dlopen") while still matching legitimate
        // C function names (e.g., "open_socket", "my_fopen_wrapper").
        const idx = std.mem.indexOf(u8, func_name, pat);
        if (idx) |i| {
            const at_word_boundary = i == 0 or func_name[i - 1] == '_';
            if (at_word_boundary) return .unknown;
        }
    }

    const C_FFI_PATTERNS = [_][]const u8{
        // FFI boundary markers
        "FFI_",
        "ffi_",

        // Dynamic loading
        "dlopen",
        "dlsym",
        "dlclose",

        // Python C API
        "Py_",
        "py_",
        "PyObject",

        // JNI
        "JNI_",
        "NewGlobalRef",
        "DeleteGlobalRef",
        "GetMethodID",
        "GetFieldID",
        "FindClass",
        "Call",

        // Resource lifecycle patterns with word-boundary matching
        // to avoid false positives (e.g., "get_handle_count", "handle_event")
    };

    for (C_FFI_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .ffi;
        }
    }

    // Broad prefix patterns that need word-boundary matching to reduce FP.
    // Without boundary checks, "handle_" matches "get_handle_count",
    // "init_" matches "reinitialize", etc.
    const C_FFI_BROAD_PREFIXES = [_][]const u8{
        "destroy_",  "create_",  "init_",     "cleanup_",
        "release_",  "acquire_", "allocate_", "deallocate_",
        "resource_", "handle_",
    };
    for (C_FFI_BROAD_PREFIXES) |word| {
        const idx = std.mem.indexOf(u8, func_name, word);
        if (idx) |i| {
            const is_component = std.mem.endsWith(u8, word, "_");
            // Component prefixes (ending in _): must be at name start
            // e.g., "cleanup_" matches "cleanup_init" but NOT "my_cleanup_func"
            // Bare words (no _): must be at name start AND followed by boundary
            // e.g., "close" matches "close_file" but NOT "disclose"
            if (is_component and i == 0) return .ffi;
            const is_bare_word = !is_component;
            if (is_bare_word and i == 0) {
                const after_idx = i + word.len;
                const after_ok = after_idx >= func_name.len or !isAlphaNumeric(func_name[after_idx]);
                if (after_ok) return .ffi;
            }
        }
    }

    if (std.mem.indexOf(u8, func_name, "_cb") != null) return .ffi;
    if (std.mem.indexOf(u8, func_name, "_callback") != null) return .ffi;
    if (std.mem.indexOf(u8, func_name, "_handler") != null) return .ffi;
    if (std.mem.indexOf(u8, func_name, "_hook") != null) return .ffi;

    // M17 FIX: Use word-boundary matching for _init to avoid false positives.
    // Previous code matched "_init" as substring, causing "initialize" to be classified as FFI.
    // Now check that _init is followed by non-alphanumeric character (word boundary).
    if (std.mem.indexOf(u8, func_name, "_init")) |idx| {
        const next_idx = idx + "_init".len;
        if (next_idx >= func_name.len or !isAlphaNumeric(func_name[next_idx])) {
            return .ffi;
        }
    }
    if (std.mem.indexOf(u8, func_name, "_cleanup") != null) return .ffi;
    if (std.mem.indexOf(u8, func_name, "_destroy") != null) return .ffi;

    return .unknown;
}

fn isAlphaNumeric(ch: u8) bool {
    // ASCII alphanumeric check (UTF-8 bytes outside ASCII range are non-alphanumeric)
    // This is conservative: multi-byte UTF-8 chars (ch > 127) return false,
    // which is safe because we only care about ASCII separators/punctuation.
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9');
}
