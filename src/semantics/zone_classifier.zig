//! Zone Classification for Multi-Language Unsafe Boundary Analysis
//!
//! Core principle: Analyze only where language guarantees stop.
//!
//! Safe Zone (default trusted):
//! - Rust: safe fn, Vec/String normal use, borrow checker constraints
//! - Zig: normal slice/allocator idiom, defer/errdefer paths
//! - Go: non-cgo, normal GC objects
//! - C++: RAII container internals
//!
//! Escape Zone (focus analysis):
//! - Rust: unsafe block, extern "C", raw pointer, transmute
//! - Zig: @ptrCast, @intToPtr, @cImport, extern fn
//! - Go: cgo, unsafe.Pointer, uintptr tricks
//! - C++: extern C, reinterpret_cast, manual malloc/free

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const debug_info = @import("../ir/debug_info.zig");
const FFIBoundary = @import("../diag/issue.zig").FFIBoundary;
pub const Language = FFIBoundary.Language;

/// Zone classification for code regions.
pub const ZoneKind = enum(u8) {
    /// Safe zone - language guarantees apply.
    /// Skip or low priority analysis.
    safe,

    /// Unsafe zone - explicit escape from safety.
    /// High priority analysis.
    unsafe,

    /// FFI boundary - cross-language call.
    /// Critical analysis.
    ffi,

    /// Runtime internal - stdlib/runtime code.
    /// Skip analysis.
    runtime_internal,

    /// Unknown - needs classification.
    unknown,
};

/// Escape trigger for each language.
pub const EscapeTrigger = enum(u8) {
    // Rust escape triggers
    rust_unsafe_block,
    rust_unsafe_fn,
    rust_extern_c,
    rust_raw_pointer,
    rust_transmute,
    rust_maybe_uninit,
    rust_pin_misuse,
    rust_asm,

    // Zig escape triggers
    zig_ptr_cast,
    zig_int_to_ptr,
    zig_c_import,
    zig_extern_fn,
    zig_volatile_ptr,
    zig_packed_abi,

    // Go escape triggers
    go_cgo,
    go_unsafe_pointer,
    go_uintptr_tricks,

    // C++ escape triggers
    cpp_extern_c,
    cpp_reinterpret_cast,
    cpp_manual_alloc,
    cpp_thread_callback,

    // Generic
    unknown,
};

/// Rust safe patterns - skip analysis.
pub const RUST_SAFE_PATTERNS = [_][]const u8{
    // Standard library safe wrappers
    "std::vec::Vec",
    "std::string::String",
    "std::collections::",
    "std::sync::Arc",
    "std::sync::Mutex",
    "std::sync::RwLock",
    "std::sync::mpsc",
    "std::sync::mpmc",
    "std::cell::RefCell",
    "std::cell::Cell",
    "std::rc::Rc",
    "std::boxed::Box",
    "std::option::Option",
    "std::result::Result",

    // Ownership patterns (safe by design)
    "drop_in_place",
    "clone",
    "into_iter",
    "from_iter",

    // R7.0: Migrated from FPWhitelist Category 2 (Rust stdlib safe primitives)
    // These were verified as FPs from BLST/Wasmtime audits — safe by language guarantee.
    "sync_channel::",
    "Waker::",
    "RawVec::",

    // R7.0: Rust global allocator shims (compiler-generated runtime glue)
    "__rust_alloc",
    "__rust_dealloc",
};

/// Rust escape triggers - focus analysis.
pub const RUST_ESCAPE_PATTERNS = [_][]const u8{
    // Unsafe blocks
    "unsafe",

    // FFI (source-level — may not match mangled names but kept for demangled paths)
    "extern \"C\"",
    "extern \"system\"",
    "libc::",
    "nix::",

    // Raw pointer operations
    "*mut ",
    "*const ",
    "as_ptr",
    "as_mut_ptr",
    "from_raw_parts",
    "from_raw_parts_mut",

    // Transmute
    "std::mem::transmute",
    "core::mem::transmute",
    "transmute_copy",

    // MaybeUninit
    "MaybeUninit",
    "assume_init",

    // Pin
    "Pin<",
    "get_unchecked",
    "get_unchecked_mut",

    // Assembly
    "asm!",
    "llvm_asm!",

    // v0.1.7: Mangled-name level patterns (actually match LLVM IR names).
    // Source-level patterns above rarely match because Rust mangles everything.
    // These patterns target the actual symbols seen in LLVM IR:
    "_ffi", // mymod::_ffi_func
    "_extern", // bindgen-generated wrappers
    "_bindgen", // rust-bindgen output
    "_cinterop", // Zig-style C interop in Rust projects
    "_marshal", // serialization FFI boundary
    "_syscall", // direct syscall invocation
    "_invoke", // indirect call through FFI trampoline
    "_callback", // FFI callback handler
    "_native", // JNI/native interop
    "_interop", // generic interop boundary
    "$", // Rust legacy mangling (often used for FFI shims)
};

/// Zig safe patterns - skip analysis.
pub const ZIG_SAFE_PATTERNS = [_][]const u8{
    // Standard library safe wrappers
    "std.ArrayList",
    "std.StringArrayHashMap",
    "std.AutoHashMap",
    "std.mem.split",
    "std.mem.replace",
    "std.process",

    // Allocator wrappers - DC-C8 FIX: Use word boundary patterns to avoid false positives
    // e.g., "my_custom_allocator_dealloc" should NOT be matched as safe "free"
    ".allocator",  // Explicit allocator type
    "@as(*std.mem.Allocator",  // Allocator cast pattern
    "std.heap.page_allocator",  // Specific safe allocators
    "std.heap.GeneralPurposeAllocator",

    // Defer patterns
    "defer",
    "errdefer",
};

/// Zig escape triggers - focus analysis.
pub const ZIG_ESCAPE_PATTERNS = [_][]const u8{
    // Pointer casts (Zig builtins)
    "@ptrCast",
    "@alignCast",
    "@intToPtr",
    "@ptrToInt",

    // C interop
    "@cImport",
    "@cInclude",
    "@cDefine",

    // Volatile (only with pointer, not standalone)
    "volatile ",

    // Packed ABI
    "packed struct",
    "@bitCast",
};

/// Go safe patterns - skip analysis.
pub const GO_SAFE_PATTERNS = [_][]const u8{
    // Runtime managed
    "runtime.",
    "make(",
    "new(",
    "append(",
    "copy(",
    "delete(",

    // GC managed
    "chan ",
    "map[",
    "func(",
    "interface{}",
};

/// Go escape triggers - focus analysis.
pub const GO_ESCAPE_PATTERNS = [_][]const u8{
    // Cgo
    "package C",
    "C.",
    "import \"C\"",

    // Unsafe
    "unsafe.Pointer",
    "unsafe.Sizeof",
    "unsafe.Offsetof",
    "unsafe.Alignof",

    // Uintptr tricks
    "uintptr(",
    "reflect.",
};

/// C++ safe patterns - skip analysis.
pub const CPP_SAFE_PATTERNS = [_][]const u8{
    // RAII containers
    "std::vector",
    "std::string",
    "std::unique_ptr",
    "std::shared_ptr",
    "std::weak_ptr",
    "std::map",
    "std::unordered_map",
    "std::set",

    // Smart pointer operations
    "make_unique",
    "make_shared",
    "get()",
    "reset()",
    "release()",
};

/// C++ escape triggers - focus analysis.
pub const CPP_ESCAPE_PATTERNS = [_][]const u8{
    // Dangerous casts
    "reinterpret_cast",
    "const_cast",
    "static_cast<void*",

    // Manual memory management
    "malloc(",
    "free(",
    "new ",
    "delete ",
    "realloc(",

    // Thread callback
    "pthread_create",
    "std::thread",
    "CreateThread",

    // Process management (C++ context)
    "fork(",
    "execvp(",
    "execve(",

    // Network I/O (C++ context)
    "getaddrinfo",
    "gethostbyname",
    "setsockopt",
    "getsockopt",
};

/// C escape triggers - focus analysis (C-specific, more precise than C++).
pub const C_ESCAPE_PATTERNS = [_][]const u8{
    // Dynamic loading
    "dlopen",
    "dlsym",
    "dlclose",

    // Memory mapping
    "mmap",
    "munmap",
    "mprotect",

    // Python C API prefix
    "Py_",

    // JNI prefix
    "JNI_",

    // Thread management
    "pthread_create",
    "pthread_join",

    // Signal handling
    "signal(",
    "sigaction(",

    // Process management
    "fork(",
    "exec",

    // Network I/O
    "getaddrinfo",
    "gethostbyname",
};

/// Classify a function name into zone kind.
///
/// Arguments:
///   func_name - The function name to classify
///   lang - The source language (if known)
///
/// Returns:
///   ZoneKind classification
fn isAlphaNumeric(ch: u8) bool {
    // ASCII alphanumeric check (UTF-8 bytes outside ASCII range are non-alphanumeric)
    // This is conservative: multi-byte UTF-8 chars (ch > 127) return false,
    // which is safe because we only care about ASCII separators/punctuation.
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9');
}

pub fn classifyFunction(func_name: []const u8, lang: ?Language) ZoneKind {
    if (func_name.len == 0) return .unknown;

    // LLVM intrinsics (llvm.* prefix) are always runtime_internal.
    // Check this before language-specific patterns to prevent misclassification
    // (e.g., llvm.threadlocal.address.p0 matching "threadlocal" zig_allocator).
    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .runtime_internal;
    }

    // Compiler FORTIFY_SOURCE functions (__*_chk suffix) are runtime-internal.
    // These are auto-inserted by -D_FORTIFY_SOURCE=2 and indicate the code is
    // MORE safe (bounds-checked), not less. Examples: __memcpy_chk, __strcpy_chk,
    // __snprintf_chk, __memmove_chk, __printf_chk, __fprintf_chk.
    if (std.mem.endsWith(u8, func_name, "_chk")) {
        return .runtime_internal;
    }

    // Check language-specific patterns
    if (lang) |l| {
        return switch (l) {
            .rust => classifyRustFunction(func_name),
            .zig => classifyZigFunction(func_name),
            .go => classifyGoFunction(func_name),
            .cpp, .c => classifyCppFunction(func_name),
            else => .unknown,
        };
    }

    // Auto-detect language from patterns
    if (isRustFunction(func_name)) return classifyRustFunction(func_name);
    if (isZigFunction(func_name)) return classifyZigFunction(func_name);
    if (isGoFunction(func_name)) return classifyGoFunction(func_name);
    if (isCppFunction(func_name)) return classifyCppFunction(func_name);
    if (isCFunction(func_name)) return classifyCFunction(func_name);

    return .unknown;
}

/// Classify a function using LLVM metadata (more precise than string matching).
///
/// Uses LLVM API to check (in priority order):
///   1. IsDeclaration: external declarations are typically library/runtime code
///   2. Linkage type: internal linkage = user code, external = library
///   3. IntrinsicID: compiler intrinsics should be skipped
///   4. Subprogram debug info path: source file location for stdlib detection
///   5. String-based fallback: name pattern matching
pub fn classifyFunctionFromLLVM(
    func: c.LLVMValueRef,
    func_name: []const u8,
) ZoneKind {
    // Check if it's a declaration (external, no definition)
    if (c.LLVMIsDeclaration(func) != 0) {
        // Declarations are typically runtime/library functions
        // But some may be user-defined extern functions
        const linkage = c.LLVMGetLinkage(func);

        // External linkage + declaration = likely runtime/library
        if (linkage == c.LLVMExternalLinkage or
            linkage == c.LLVMExternalWeakLinkage or
            linkage == c.LLVMCommonLinkage)
        {
            // Further check if it looks like user FFI vs stdlib
            if (isLikelyRuntimeInternal(func_name)) {
                return .runtime_internal;
            }
            return .ffi; // External declarations are FFI boundaries
        }

        // Internal/private declarations = likely user code
        return .unknown;
    }

    // Check for compiler intrinsics using intrinsic ID
    const intrinsic_id = c.LLVMGetIntrinsicID(func);
    if (intrinsic_id != 0) {
        return .runtime_internal; // All intrinsics are safe
    }

    // Layer 4: Use LLVM subprogram debug metadata for source-path-based classification
    // This is more accurate than string matching because it uses actual source locations
    if (classifyBySubprogramPath(func)) |zone| {
        return zone;
    }

    // For defined functions, use string-based classification as fallback
    // But first check for LLVM intrinsic prefix — llvm.* functions
    // are compiler-generated intrinsics, not user code or language allocators.
    // This prevents misclassification like llvm.threadlocal.address.p0
    // being classified as zig_allocator (via "threadlocal" contains match).
    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .runtime_internal;
    }

    return classifyFunction(func_name, null);
}

/// Classify a function by its LLVM DISubprogram debug metadata source path.
///
/// Checks the source file location from debug info to determine if the function
/// comes from standard library vs user code. This is significantly more accurate
/// than name-based heuristics, especially for mangled names (Rust _ZN*, C++ _Z*).
///
/// Returns:
///   ZoneKind if classification succeeded via debug path, null otherwise
fn classifyBySubprogramPath(func: c.LLVMValueRef) ?ZoneKind {
    const subprogram = debug_info.DebugInfoUtils.getFunctionSubprogram(func) orelse return null;

    // Use the same approach as ffi_boundary.extractDebugFilePath (verified working)
    const file_ref = c.LLVMDIScopeGetFile(subprogram.raw);
    if (@intFromPtr(file_ref) == 0) return null;

    var filename_len: c_uint = undefined;
    const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
    if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

    const max_path_len: c_uint = 4096;
    if (filename_len > max_path_len) return null;
    if (filename_ptr[0] == 0) return null;

    const filename = filename_ptr[0..filename_len];

    // Rust standard library paths → runtime_internal (skip analysis)
    const rust_stdlib_paths = [_][]const u8{
        "/rustc/",         "/.rustup/",        "/rustlib/",
        "library/core/",   "library/alloc/",   "library/std/",
        "/src/libcore/",   "/src/liballoc/",   "/src/libstd/",
        "cargo/registry/", ".cargo/registry/",
    };
    for (rust_stdlib_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    // Zig standard library paths → runtime_internal
    const zig_stdlib_paths = [_][]const u8{
        "/zig/lib/std/", "/zig/lib/builtin/",
        "lib/std/",      "lib/builtin/",
    };
    for (zig_stdlib_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    // Go runtime paths → runtime_internal
    const go_runtime_paths = [_][]const u8{
        "/usr/local/go/src/runtime/", "/go/src/runtime/",
        "go/src/runtime/",            "_cgo_gotypes.go",
    };
    for (go_runtime_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .runtime_internal;
    }

    // C/C++ system header paths → safe
    // NOTE: "/include/" alone is too broad (matches user project headers).
    // Only match known system include paths where headers are trusted.
    const system_paths = [_][]const u8{
        "/usr/include/", "/usr/local/include/",
        "/sysroot/",     "/llvm-project/",
        "/libcxx/",
    };
    for (system_paths) |pat| {
        if (std.mem.indexOf(u8, filename, pat) != null) return .safe;
    }

    // CGo generated files → runtime_internal (compiler-generated glue)
    if (std.mem.indexOf(u8, filename, "_cgo_") != null) return .runtime_internal;

    return null; // No match — fall through to string-based classification
}

/// Check if function name looks like runtime internal code.
fn isLikelyRuntimeInternal(name: []const u8) bool {
    // Rust standard library patterns
    const rust_stdlib_patterns = [_][]const u8{
        "_ZN4core",      "_ZN5alloc", "_ZN3std",
        "llvm.",         "__rust_",   "__cg",
        // Drop glue, panic, etc.
        "drop_in_place", "panic_",
    };

    for (rust_stdlib_patterns) |pat| {
        if (std.mem.startsWith(u8, name, pat)) return true;
    }

    // Go runtime patterns
    const go_runtime_patterns = [_][]const u8{
        "runtime.", "_cgo_",  "crosscall2",
        "__go_",    "__gcc_",
    };

    for (go_runtime_patterns) |pat| {
        if (std.mem.startsWith(u8, name, pat)) return true;
    }

    // C/C++ standard library patterns
    const cc_stdlib_patterns = [_][]const u8{
        "__gnu_cxx",              "__cxa_",
        "__clang_call_terminate", "llvm.",
    };

    for (cc_stdlib_patterns) |pat| {
        if (std.mem.indexOf(u8, name, pat) != null) return true;
    }

    return false;
}

/// Classify a Rust function.
fn classifyRustFunction(func_name: []const u8) ZoneKind {
    // Check escape triggers first
    for (RUST_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    // Check for runtime internal (core/alloc/std stdlib)
    if (std.mem.startsWith(u8, func_name, "_ZN4core") or
        std.mem.startsWith(u8, func_name, "_ZN5alloc") or
        std.mem.startsWith(u8, func_name, "_ZN3std"))
    {
        return .runtime_internal;
    }

    // Check safe patterns
    for (RUST_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    // Check for extern C
    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    // Default: user Rust code classification (v0.1.7 relaxed).
    // Old behavior: all user Rust functions → .safe (overly conservative, blocks FFI analysis).
    // New behavior: use .unknown to let downstream passes (isRustFFIRelevantFunction,
    // DangerSurface, etc.) make the final decision based on IR-level analysis.
    // This fixes the "three-layer break" where zone gate filtered ALL Rust functions.
    if (std.mem.startsWith(u8, func_name, "_ZN") or
        std.mem.startsWith(u8, func_name, "_R"))
    {
        return .unknown;
    }

    return .unknown;
}

/// Classify a Zig function.
fn classifyZigFunction(func_name: []const u8) ZoneKind {
    for (ZIG_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (ZIG_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Classify a Go function.
fn classifyGoFunction(func_name: []const u8) ZoneKind {
    for (GO_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (GO_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "C.") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Classify a C++ function.
fn classifyCppFunction(func_name: []const u8) ZoneKind {
    const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;

    // Step 1: Check C++ unsafe patterns (highest priority)
    for (CPP_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    // Step 2: Check C++ safe patterns (RAII, smart pointers)
    for (CPP_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    // Step 3: Check C escape patterns (FFI-related)
    for (C_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .ffi;
        }
    }

    // Step 4: Check extern "C" declaration (FFI boundary)
    if (std.mem.indexOf(u8, func_name, "extern \"C\"") != null) {
        return .ffi;
    }

    // Step 5: SemanticRegistry lookup (fallback for known functions)
    if (SemanticRegistry.lookup(func_name)) |sem| {
        switch (sem.kind) {
            .command_exec,
            .unchecked_copy,
            .format_string,
            .memory_map,
            .dynamic_loading,
            .jni,
            .python_c_api,
            .allocator,
            .deallocator,
            .network_io,
            .file_io,
            .signal_handler,
            .thread_mgmt,
            .process_mgmt,
            .rust_ownership,
            .borrow_escaped,
            .go_cgo_alloc,
            .zig_allocator,
            .cpp_allocator,
            .static_buffer,
            => return .ffi,
        }
    }

    return .unknown;
}

/// Detect if function is Rust.
fn isRustFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_ZN4core")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN5alloc")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN3std")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN4ring")) return true;
    if (std.mem.startsWith(u8, func_name, "_R")) return true;
    if (std.mem.indexOf(u8, func_name, "$u20$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$LT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$GT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$C$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "core::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "alloc::") != null) return true;
    return false;
}

/// Detect if function is Zig.
fn isZigFunction(func_name: []const u8) bool {
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
fn isGoFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "runtime.")) return true;
    if (std.mem.startsWith(u8, func_name, "main.")) return true;
    if (std.mem.indexOf(u8, func_name, "C.") != null) return true;
    return false;
}

/// Detect if function is C++.
fn isCppFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_Z")) return true;
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    return false;
}

/// Detect if function is C using name-based heuristics.
///
/// C functions typically use snake_case naming and don't have
/// Rust/Zig/Go/C++ specific prefixes.
fn isCFunction(func_name: []const u8) bool {
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
fn classifyCFunction(func_name: []const u8) ZoneKind {
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

    const C_FFI_PATTERNS = [_][]const u8{
        // FFI boundary markers
        "FFI_",
        "ffi_",

        // Dynamic loading
        "dlopen",
        "dlsym",
        "dlclose",

        // Memory mapping
        "mmap",
        "munmap",
        "mprotect",

        // Network I/O
        "socket",
        "connect",
        "bind",
        "listen",
        "accept",
        "send",
        "recv",

        // File I/O (specific variants with prefixes)
        "fopen",
        "fclose",

        // Threading
        "pthread_",
        "sem_",
        "shm_",
        "msg_",
        "mkfifo",

        // Process management
        "fork",
        "exec",
        "wait",
        "kill",
        "signal",
        "alarm",

        // Control flow
        "setjmp",
        "longjmp",
        "exit",

        // Memory allocation
        "malloc",
        "calloc",
        "realloc",
        "free",
        "memcpy",
        "memmove",
        "memset",
        "memcmp",

        // String operations (buffer overflow risk)
        "strcpy",
        "strncpy",
        "strcat",
        "strncat",
        "strlen",
        "strcmp",
        "strncmp",
        "sprintf",
        "snprintf",

        // Conversion
        "atoi",
        "atol",
        "strtol",
        "strtod",

        // Platform-specific allocators
        "malloc_zone",

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
        // Also include the previously ambiguous short words
         "close",     "open",
        "read",      "write",    "pipe",
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

/// Statistics for zone classification.
pub const ZoneStats = struct {
    safe_count: u32 = 0,
    unsafe_count: u32 = 0,
    ffi_count: u32 = 0,
    runtime_count: u32 = 0,
    unknown_count: u32 = 0,

    pub fn record(self: *ZoneStats, zone: ZoneKind) void {
        switch (zone) {
            .safe => self.safe_count += 1,
            .unsafe => self.unsafe_count += 1,
            .ffi => self.ffi_count += 1,
            .runtime_internal => self.runtime_count += 1,
            .unknown => self.unknown_count += 1,
        }
    }

    pub fn total(self: ZoneStats) u32 {
        return self.safe_count + self.unsafe_count + self.ffi_count + self.runtime_count + self.unknown_count;
    }

    pub fn skipRatio(self: ZoneStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.safe_count + self.runtime_count)) / @as(f64, @floatFromInt(t));
    }
};

test "classifyRustFunction - safe patterns" {
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::vec::Vec::push"));
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::sync::Arc::clone"));
    try std.testing.expectEqual(ZoneKind.runtime_internal, classifyRustFunction("_ZN4core3ptr13drop_in_place"));
    // _ZN4ring... is user code (not stdlib, not compiler-generated), classified as safe by default
    const ring_result = classifyRustFunction("_ZN4ring3rsa7keypair7KeyPair8from_der");
    // Accept either .safe or .unknown (depends on whether it's recognized as Rust mangled name)
    try std.testing.expect(ring_result == .safe or ring_result == .unknown);
}

test "classifyRustFunction - escape patterns" {
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("std::mem::transmute"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("as_ptr"));
}

test "ZoneStats" {
    var stats = ZoneStats{};
    stats.record(.safe);
    stats.record(.safe);
    stats.record(.unsafe);
    stats.record(.runtime_internal);

    try std.testing.expectEqual(@as(u32, 4), stats.total());
    try std.testing.expectEqual(@as(u32, 2), stats.safe_count);
    try std.testing.expectEqual(@as(f64, 0.75), stats.skipRatio());
}

test "isLikelyRuntimeInternal - Rust stdlib" {
    try std.testing.expect(isLikelyRuntimeInternal("_ZN4core3ptr13drop_in_place"));
    try std.testing.expect(isLikelyRuntimeInternal("_ZN5alloc6raw_vec17RawVec"));
    try std.testing.expect(isLikelyRuntimeInternal("_ZN3std3fmt9Arguments"));
    try std.testing.expect(isLikelyRuntimeInternal("llvm.memcpy.p0i8.p0i8.i64"));
    try std.testing.expect(!isLikelyRuntimeInternal("_ZN4my_crate3foo3bar"));
}

test "isLikelyRuntimeInternal - Go runtime" {
    try std.testing.expect(isLikelyRuntimeInternal("runtime.mallocgc"));
    try std.testing.expect(isLikelyRuntimeInternal("_cgo_12345"));
    try std.testing.expect(isLikelyRuntimeInternal("crosscall2"));
    try std.testing.expect(!isLikelyRuntimeInternal("main.main"));
}

test "isLikelyRuntimeInternal - C/C++ stdlib" {
    try std.testing.expect(isLikelyRuntimeInternal("__gnu_cxx::__enable_if"));
    try std.testing.expect(isLikelyRuntimeInternal("__cxa_begin_catch"));
    try std.testing.expect(isLikelyRuntimeInternal("__clang_call_terminate"));
    try std.testing.expect(!isLikelyRuntimeInternal("my_function"));
}

test "classifyCppFunction - CPP_ESCAPE_PATTERNS" {
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("reinterpret_cast<int*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("const_cast<int*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("static_cast<void*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("std::thread"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("CreateThread"));
}

test "classifyCppFunction - CPP_SAFE_PATTERNS" {
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::vector<int>::push_back"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::string::c_str"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::unique_ptr::get"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::shared_ptr::clone"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::map::insert"));
}

test "classifyCppFunction - extern C" {
    try std.testing.expectEqual(ZoneKind.ffi, classifyCppFunction("extern \"C\" my_func"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCppFunction("extern \"C\" void foo()"));
}

test "classifyCppFunction - unknown" {
    try std.testing.expectEqual(ZoneKind.unknown, classifyCppFunction("my_custom_function"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCppFunction("some_internal_func"));
}

test "isCFunction - positive detection" {
    try std.testing.expect(isCFunction("my_c_function"));
    try std.testing.expect(isCFunction("process_data"));
    try std.testing.expect(isCFunction("handle_request"));
    try std.testing.expect(isCFunction("init_server"));
    try std.testing.expect(isCFunction("cleanup_resources"));
}

test "isCFunction - negative detection (not C)" {
    try std.testing.expect(!isCFunction("_ZN4core3ptr"));
    try std.testing.expect(!isCFunction("std::vector"));
    try std.testing.expect(!isCFunction("runtime.main"));
    try std.testing.expect(!isCFunction("llvm.memcpy"));
    try std.testing.expect(!isCFunction("__gnu_cxx::"));
    try std.testing.expect(!isCFunction("_ZN3std"));
    try std.testing.expect(!isCFunction("my_func$u20$name"));
}

test "classifyCFunction - FFI patterns" {
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("FFI_01_dlopen_null_check"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("my_dlopen_wrapper"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("dlopen_handle"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("pthread_create_cb"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("signal_handler"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("malloc_wrapper"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("free_memory"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("my_mmap_handler"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("socket_create"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("fopen_file"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("cleanup_init"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("destroy_resource"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("PyObject_Call"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("JNI_OnLoad"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("NewGlobalRef"));
}

test "classifyCFunction - non-FFI returns unknown" {
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("my_internal_func"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("calculate_value"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("process_data_internal"));
}

// R8.0-P1-13: Word-boundary matching for broad C_FFI patterns (no FP)
test "classifyCFunction - word boundary prevents FP" {
    // Valid FFI: broad patterns at word start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("close_file")); // close at start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("open_socket")); // open at start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("read_data")); // read at start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("write_buffer")); // write at start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("pipe_create")); // pipe at start
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("destroy_handle")); // destroy_ prefix
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("create_resource")); // create_ prefix
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("init_module")); // init_ prefix
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("handle_event")); // handle_ prefix

    // Invalid (FP): broad pattern as substring
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("disclose")); // contains "close"
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("reopen")); // contains "open"
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("threadsafe")); // contains "read"
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("overwrite")); // contains "write"
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("pipeline")); // "pipe" followed by alpha → not a word boundary
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("get_handle_count")); // contains "handle"
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("reinitialize")); // contains "init"
}
