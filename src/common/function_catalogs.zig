//! Function Name Catalogs — Single Source of Truth
//!
//! This module consolidates all function name catalog arrays that were previously
//! scattered across multiple files. All consumers should import from here.
//!
//! Sources (origin files):
//!   - FREE_FUNCTIONS:        pass/analysis/issue/free_validation.zig
//!   - HEAP_ALLOC_FUNCTIONS:  pass/analysis/ptr_lifetime/ptr_lifetime_types.zig
//!   - KNOWN_DEALLOCATORS:    pass/analysis/ptr_lifetime/ptr_lifetime_types.zig
//!   - RUST_ALLOC_INTRINSICS: pass/analysis/ptr_lifetime/ptr_lifetime_types.zig
//!   - LIBC_FUNCTIONS:        types/call_graph_types.zig
//!   - DANGEROUS_FUNCTIONS:   types/call_graph_types.zig
//!   - stdlib_prefixes:       types/ownership_types.zig
//!   - mem_intrinsics:        types/ownership_types.zig
//!   - resource_pairs:        types/cpp_fp_types.zig
//!   - ffi_name_patterns:     types/ownership_types.zig

const std = @import("std");

// ============================================================================
// Memory Deallocation Functions (source: free_validation.zig)
// ============================================================================

/// Memory deallocation functions — basic memory deallocators for free validation.
/// NOTE: This is distinct from KNOWN_DEALLOCATORS which covers library-specific
/// cleanup (sqlite3_free, curl_easy_cleanup, etc.).
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free",           "dealloc",       "deallocate",   "operator delete", "operator delete[]",
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};

// ============================================================================
// Heap Allocation Functions (source: ptr_lifetime_types.zig)
// ============================================================================

/// Heap allocation functions — canonical list of known heap allocators.
pub const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc",            "calloc",        "realloc",         "aligned_alloc",
    "valloc",            "pvalloc",       "memalign",        "operator new",
    "operator new[]",    "allocImpl",     "mmap",
    // C++ operator new — Itanium ABI mangled names
               "_Znwm",
    "_Znam",             "_Znw",          "_Zna",
    // C++17 aligned new/delete
               "__Znwm",
    "__Znam",            "__Znw",         "__Zna",
    // MSVC-mangled operator new
              "?operator new@@",
    "?operator new[]@@", "dlopen",        "fopen",           "socket",
    "JNI_OnLoad",        "Py_Initialize", "Py_BuildValue",   "PyTuple_New",
    "PyList_New",        "PyDict_New",    "NewStringUTF",    "NewByteArray",
    "NewGlobalRef",      "c_malloc",
    // Rust global allocator intrinsics
         "__rust_alloc",    "__rust_realloc",
    "__rdl_alloc",       "__rg_alloc",    "exchange_malloc",
};

// ============================================================================
// Known Deallocator/Finalizer Functions (source: ptr_lifetime_types.zig)
// ============================================================================

/// Known deallocator/finalizer functions that release resources.
pub const KNOWN_DEALLOCATORS = struct {
    pub const finalize_functions = &[_][]const u8{
        "sqlite3_finalize", "sqlite3_step",   "mysql_stmt_close",
        "stmt_finalize",    "query_finalize", "statement_finalize",
    };
    pub const close_functions = &[_][]const u8{
        "fclose",       "close",        "closedir",            "closed", "shutdown",
        "SSL_shutdown", "BIO_free_all", "EVP_CIPHER_CTX_free",
    };
    pub const free_functions = &[_][]const u8{
        "sqlite3_free",      "mysql_free_result",   "PQclear", "nghttp2_session_del",
        "curl_easy_cleanup", "curl_slist_free_all",
    };
    pub const destroy_functions = &[_][]const u8{
        "sqlite3_close", "sqlite3_close_v2", "mysql_close",
        "destroy",       "Delete",           "Release",
        "Free",
    };
};

// ============================================================================
// Rust Allocator Intrinsics (source: ptr_lifetime_types.zig)
// ============================================================================

/// Canonical Rust global allocator intrinsic patterns — single source of truth.
pub const RUST_ALLOC_INTRINSICS = struct {
    /// All 8 Rust allocator/deallocator intrinsics (alloc + dealloc combined)
    pub const all = [_][]const u8{
        "__rust_alloc",        "__rust_dealloc", "__rust_realloc",
        "__rust_alloc_zeroed", "__rdl_alloc",    "__rdl_dealloc",
        "__rg_alloc",          "__rg_dealloc",   "exchange_malloc",
    };
    /// Allocator-only subset (no deallocators)
    pub const alloc_only = [_][]const u8{
        "__rust_alloc", "__rust_realloc",  "__rdl_alloc",
        "__rg_alloc",   "exchange_malloc",
    };
    /// Deallocator-only subset
    pub const dealloc_only = [_][]const u8{
        "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
    };
};

// ============================================================================
// Standard C Library Functions (source: call_graph_types.zig)
// ============================================================================

/// Trusted libc functions (source: config/languages/c.json).
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
// Dangerous Functions (source: call_graph_types.zig)
// ============================================================================

/// List of dangerous functions that should be flagged as security risks.
pub const DANGEROUS_FUNCTIONS = &[_][]const u8{
    // Command execution
    "system",     "exec",        "execve",       "execvp",
    "execv",      "execl",       "execlp",       "execle",
    "fexecve",    "posix_spawn", "posix_spawnp", "popen",

    // Buffer overflow risks
    "gets",       "strcpy",      "strcat",       "sprintf",
    "vsprintf",   "asprintf",    "vasprintf",    "strncpy",
    "strncat",    "strdup",      "strndup",      "memcpy",
    "memmove",    "memset",      "bcopy",        "bzero",

    // Format string vulnerabilities
    "printf",     "fprintf",     "vprintf",      "vfprintf",
    "dprintf",    "vdprintf",

    // Input functions
       "scanf",        "fscanf",
    "sscanf",     "vfscanf",     "vscanf",       "vsscanf",

    // Environment and system info
    "getenv",     "setenv",      "putenv",       "clearenv",

    // File operations
    "fopen",      "freopen",     "open",         "creat",
    "tmpnam",     "tempnam",     "mktemp",       "mkstemp",
    "mkdtemp",

    // Process control
       "fork",        "vfork",        "clone",
    "kill",       "raise",       "abort",        "exit",
    "_exit",      "_Exit",

    // Dynamic loading
          "dlopen",       "dlsym",
    "dlclose",    "dlerror",

    // I/O control
        "ioctl",        "fcntl",

    // System calls
    "syscall",    "sysenter",    "int80",

    // Memory management
           "mmap",
    "munmap",     "mprotect",    "madvise",      "brk",
    "sbrk",

    // Signal handling
          "signal",      "sigaction",    "sigprocmask",
    "sigsuspend", "sigpending",

    // Network operations
     "connect",      "bind",
    "listen",     "accept",      "send",         "sendto",
    "sendmsg",    "setsockopt",  "getsockopt",

    // Temporary file creation
      "tmpfile",
    "tempnam",

    // Path manipulation
       "realpath",    "dirname",      "basename",
};

// ============================================================================
// Standard Library / Runtime Prefixes (source: ownership_types.zig)
// ============================================================================

/// Standard library / runtime function prefixes that do NOT represent
/// real FFI boundary security risk.
pub const stdlib_prefixes = [_][]const u8{
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
// FFI Name Patterns (source: ownership_types.zig)
// ============================================================================

/// Name-based patterns for fast-path Rust FFI relevance detection.
pub const ffi_name_patterns = [_][]const u8{
    "_ffi",     "_extern",   "_cinterop", "_bindgen",
    "_foreign", "_abi",      "_marshal",  "_syscall",
    "_invoke",  "_callback", "_native",   "_interop",
};

// ============================================================================
// LLVM Memory Intrinsics (source: ownership_types.zig)
// ============================================================================

/// LLVM memory intrinsic names for memory access classification.
pub const mem_intrinsics = [_][]const u8{
    "llvm.memcpy",        "llvm.memmove", "llvm.memset",
    "llvm.memset.inline",
};

// ============================================================================
// Resource Allocation/Deallocation Pairs (source: cpp_fp_types.zig)
// ============================================================================

/// Resource allocation/deallocation pairs for leak detection.
pub const resource_pairs = [_]struct { []const u8, []const u8 }{
    .{ "fopen", "fclose" },
    .{ "tmpfile", "fclose" },
    .{ "freopen", "fclose" },
    .{ "socket", "close" },
    .{ "accept", "close" },
    .{ "opendir", "closedir" },
    .{ "popen", "pclose" },
};

// ============================================================================
// Known Safe Wrappers for FFI-sourced pointers (source: free_validation.zig)
// ============================================================================

/// Known safe wrapper functions that can correctly free FFI-sourced pointers.
pub const known_safe_free_wrappers = [_][]const u8{
    "g_free",        "CFRelease",            "CFAutorelease",
    "PyObject_Free", "PyMem_Free",           "cudaFree",
    "vkFreeMemory",  "ID3D12Device_Release", "VirtualFree",
    "HeapFree",      "munmap",               "mmap_free",
    "objc_release",  "NSDeallocateObject",   "CoTaskMemFree",
    "SysFreeString",
};

// ============================================================================
// Opcode Name Table (source: ownership_types.zig)
// ============================================================================

/// Opcode name table for diagnostic messages.
pub const opcode_names = [_][]const u8{
    "load",   "store",   "gep",    "call",   "ret",
    "br",     "switch",  "phi",    "alloca", "extract",
    "insert", "shuffle", "select", "icmp",   "fcmp",
};
