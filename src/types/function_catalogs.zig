//! Function Name Catalogs — Single Source of Truth
//!
//! Consolidates all function-name-based classification constants
//! from across the codebase into one place.
//!
//! Sources:
//!   - FREE_FUNCTIONS / ALLOC_FUNCTIONS:    pass/analysis/issue/free_validation_safety.zig
//!   - LIBC_FUNCTIONS / DANGEROUS_FUNCTIONS: types/call_graph_types.zig
//!   - stdlib_prefixes / mem_intrinsics:      types/ownership_types.zig
//!   - resource_pairs:                        types/cpp_fp_types.zig

const std = @import("std");

// ============================================================================
// Memory Allocation Functions
// ============================================================================

/// Heap allocation functions — comprehensive list covering C, C++, Rust, and OS-level allocators.
/// Source: ptr_lifetime_types.zig (HEAP_ALLOC_FUNCTIONS).
pub const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc",            "calloc",        "realloc",         "aligned_alloc",
    "valloc",            "pvalloc",       "memalign",        "operator new",
    "operator new[]",    "allocImpl",     "mmap",
    // C++ operator new — Itanium ABI mangled names
    // Scalar: _Znw*, _Znwm (operator new / operator new(unsigned long))
    // Array:  _Zna*, _Znam (operator new[] / operator new[](unsigned long))
    // Covers standard + aligned (C++17) + nothrow + placement variants
    // Substring matching ensures all suffixes are caught (_ZnamSt9align_val_t, etc.)
               "_Znwm",
    "_Znam",             "_Znw",          "_Zna",
    // C++17 aligned new/delete (double underscore prefix on some platforms)
               "__Znwm",
    "__Znam",            "__Znw",         "__Zna",
    // Bug 3 fix: also catch MSVC-mangled operator new (when cross-compiled to ELF)
              "?operator new@@",
    "?operator new[]@@",
    // OS-level resource acquisition
    "dlopen",        "fopen",           "socket",
    "JNI_OnLoad",        "Py_Initialize", "Py_BuildValue",   "PyTuple_New",
    "PyList_New",        "PyDict_New",    "NewStringUTF",    "NewByteArray",
    "NewGlobalRef",      "c_malloc",
    // Rust global allocator intrinsics
         "__rust_alloc",    "__rust_realloc",
    "__rdl_alloc",       "__rg_alloc",    "exchange_malloc",
};

/// ALLOC_FUNCTIONS is an alias for HEAP_ALLOC_FUNCTIONS for backward compatibility.
pub const ALLOC_FUNCTIONS = HEAP_ALLOC_FUNCTIONS;

// ============================================================================
// Memory Deallocation Functions
// ============================================================================

/// Memory deallocation functions — basic memory deallocators for free validation.
/// Source: free_validation_safety.zig (FREE_FUNCTIONS).
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free",           "dealloc",       "deallocate",   "operator delete", "operator delete[]",
    // Rust global deallocator intrinsics
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};

// ============================================================================
// Standard Library (libc) Functions
// ============================================================================

/// Trusted libc functions (source: call_graph_types.zig / LIBC_FUNCTIONS).
/// Dangerous functions (system, exec, popen) are NOT included — see DANGEROUS_FUNCTIONS.
pub const LIBC_FUNCTIONS = &[_][]const u8{
    "malloc",
    "free",
    "calloc",
    "realloc",
    "read",
    "write",
    "open",
    "close",
    "strlen",
    "strncpy",
    "snprintf",
    "fgets",
    "getline",
    "memcpy",
    "memmove",
    "memset",
    "memcmp",
    "printf",
    "fprintf",
    "puts",
    "fopen",
    "fclose",
    "fread",
    "fwrite",
};

// ============================================================================
// Dangerous Functions
// ============================================================================

/// List of dangerous functions that should be flagged as security risks.
/// These are treated as FFI boundaries and potential sinks.
/// Source: call_graph_types.zig (DANGEROUS_FUNCTIONS).
pub const DANGEROUS_FUNCTIONS = &[_][]const u8{
    // Command execution
    "system",
    "exec",
    "execve",
    "execvp",
    "execv",
    "execl",
    "execlp",
    "execle",
    "fexecve",
    "posix_spawn",
    "posix_spawnp",
    "popen",

    // Buffer overflow risks
    "gets",
    "strcpy",
    "strcat",
    "sprintf",
    "vsprintf",
    "asprintf",
    "vasprintf",
    "strncpy",
    "strncat",
    "strdup",
    "strndup",
    "memcpy",
    "memmove",
    "memset",
    "bcopy",
    "bzero",

    // Format string vulnerabilities
    "printf",
    "fprintf",
    "vprintf",
    "vfprintf",
    "dprintf",
    "vdprintf",

    // Input functions (can be dangerous if misused)
    "scanf",
    "fscanf",
    "sscanf",
    "vfscanf",
    "vscanf",
    "vsscanf",

    // Environment and system info
    "getenv",
    "setenv",
    "putenv",
    "clearenv",

    // File operations (can be dangerous)
    "fopen",
    "freopen",
    "open",
    "creat",
    "tmpnam",
    "tempnam",
    "mktemp",
    "mkstemp",
    "mkdtemp",

    // Process control
    "fork",
    "vfork",
    "clone",
    "kill",
    "raise",
    "abort",
    "exit",
    "_exit",
    "_Exit",

    // Dynamic loading
    "dlopen",
    "dlsym",
    "dlclose",
    "dlerror",

    // I/O control
    "ioctl",
    "fcntl",

    // System calls
    "syscall",
    "sysenter",
    "int80",

    // Memory management (dangerous if misused)
    "mmap",
    "munmap",
    "mprotect",
    "madvise",
    "brk",
    "sbrk",

    // Signal handling
    "signal",
    "sigaction",
    "sigprocmask",
    "sigsuspend",
    "sigpending",

    // Network operations (can be dangerous)
    "connect",
    "bind",
    "listen",
    "accept",
    "send",
    "sendto",
    "sendmsg",
    "setsockopt",
    "getsockopt",

    // Temporary file creation
    "tmpfile",
    "tempnam",

    // Path manipulation
    "realpath",
    "dirname",
    "basename",
};

// ============================================================================
// Standard Library / Runtime Prefixes
// ============================================================================

/// Standard library / runtime function prefixes that do NOT represent
/// real FFI boundary security risk. Used by FFI Relevance Gate.
/// Source: ownership_types.zig (stdlib_prefixes).
pub const STDLIB_PREFIXES = &[_][]const u8{
    "malloc",      "calloc",             "realloc",          "free",
    "abort",       "exit",               "printf",           "fprintf",
    "sprintf",     "snprintf",           "puts",             "fputs",
    "memcpy",      "memset",             "memmove",          "memcmp",
    "strlen",      "strcpy",             "strncpy",          "strcmp",
    "__rust_",     "llvm.",              "_Znwm",            "_Znam",
    "_ZdlPv",      "pthread_",           "dlopen",           "dlsym",
    "sigaltstack", "__deregister_frame", "__register_frame",
};

// ============================================================================
// LLVM Memory Intrinsics
// ============================================================================

/// LLVM memory intrinsic names for memory access classification.
/// Source: ownership_types.zig (mem_intrinsics).
pub const MEM_INTRINSICS = &[_][]const u8{
    "llvm.memcpy",        "llvm.memmove", "llvm.memset",
    "llvm.memset.inline",
};

// ============================================================================
// Resource Pairs (Alloc/Free)
// ============================================================================

/// Resource allocation/deallocation pairs for leak detection.
/// Source: cpp_fp_types.zig (resource_pairs).
pub const RESOURCE_PAIRS = &[_]struct { []const u8, []const u8 }{
    .{ "fopen", "fclose" },
    .{ "tmpfile", "fclose" },
    .{ "freopen", "fclose" },
    .{ "socket", "close" },
    .{ "accept", "close" },
    .{ "opendir", "closedir" },
    .{ "popen", "pclose" },
};
