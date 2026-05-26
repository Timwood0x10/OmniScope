//! Platform Runtime & Compiler-Generated Shim Detection
//!
//! Identifies platform-specific runtime functions, compiler-generated shims,
//! and language runtime internals that should be classified as `runtime` or
//! `compiler_generated` rather than user code.
//!
//! This module extends the basic shim detection in platform_normalizer.zig
//! with more sophisticated pattern matching, including:
//!
//! - C++ allocator functions (operator new/delete/new[]/delete[])
//! - Language runtime startup/shutdown sequences
//! - Exception handling runtime
//! - Thread-local storage initialization
//! - Sanitizer runtime hooks
//!
//! Design Principles:
//! - Conservative: when unsure, prefer to keep analyzing (don't false-negative)
//! - Boundary-safe: FFI boundary functions are never classified as runtime
//! - Evidence-based: classification includes reason string for debugging

const std = @import("std");
const log = std.log.scoped(.platform_runtime);
const PlatformProfile = @import("platform_profile.zig").PlatformProfile;
const PlatformNormalizer = @import("platform_normalizer.zig");

/// Runtime function category for detailed classification.
pub const RuntimeCategory = enum {
    /// C/C++ standard library (malloc/free, new/delete, etc.)
    libc,
    /// C++ ABI runtime (__cxa_throw, __cxa_begin_catch, etc.)
    cpp_abi,
    /// C++ allocator operators (operator new, operator delete)
    cpp_allocator,
    /// Objective-C runtime (_objc_msgSend, etc.) — macOS only
    objc_runtime,
    /// Swift runtime (swift_retain, etc.) — macOS only
    swift_runtime,
    /// Grand Central Dispatch — macOS only
    gcd_runtime,
    /// Go runtime (runtime.gc, etc.)
    go_runtime,
    /// Rust runtime (__rust_alloc, drop_in_place, etc.)
    rust_runtime,
    /// Zig runtime (__zig_, etc.)
    zig_runtime,
    /// LLVM intrinsic (llvm.*, etc.)
    llvm_intrinsic,
    /// Sanitizer runtime (__asan_*, __msan_*, etc.)
    sanitizer,
    /// Code coverage / profiling (__gcov_, __profn_)
    profiling,
    /// Static initializer (.init_array, .CRT$XCU handler)
    static_init,
    /// Static destructor (.fini_array, .CRT$XTY handler)
    static_fini,
    /// Exception handling frame (.eh_frame, .pdata handler)
    exception_handler,
    /// Thread-local storage initializer
    tls_init,
    /// Stack protection canary (__stack_chk_fail, etc.)
    stack_protection,
    /// Dynamic linker/runtime loader (_dyld_, _dl_, etc.)
    dynamic_linker,
    /// Unknown or unrecognized runtime
    unknown,

    pub fn displayName(self: RuntimeCategory) []const u8 {
        return switch (self) {
            .libc => "LibC",
            .cpp_abi => "C++ABI",
            .cpp_allocator => "C++Allocator",
            .objc_runtime => "ObjCRuntime",
            .swift_runtime => "SwiftRuntime",
            .gcd_runtime => "GCD",
            .go_runtime => "GoRuntime",
            .rust_runtime => "RustRuntime",
            .zig_runtime => "ZigRuntime",
            .llvm_intrinsic => "LLVMIntrinsic",
            .sanitizer => "Sanitizer",
            .profiling => "Profiling",
            .static_init => "StaticInit",
            .static_fini => "StaticFini",
            .exception_handler => "ExceptionHandler",
            .tls_init => "TLSInit",
            .stack_protection => "StackProtection",
            .dynamic_linker => "DynamicLinker",
            .unknown => "Unknown",
        };
    }
};

/// Detailed result of runtime classification.
pub const RuntimeClassification = struct {
    /// Whether this function is a platform runtime / compiler-generated shim.
    is_runtime: bool,

    /// Specific category of runtime function (if is_runtime == true).
    category: RuntimeCategory,

    /// Human-readable explanation of why this was classified as runtime.
    reason: []const u8,

    /// Confidence level of this classification (0.0-1.0).
    confidence: f32,
};

/// Classify a function name to determine if it's a platform runtime shim.
///
/// This function performs comprehensive pattern matching against known runtime
/// function naming conventions across all supported platforms. It returns a
/// detailed classification including the category and reasoning.
///
/// Arguments:
///   func_name - Function name (may be mangled or canonicalized)
///   profile   - Current platform profile (used for platform-specific patterns)
///
/// Returns:
///   RuntimeClassification with is_runtime=true if this is a known runtime function
pub fn classifyRuntimeFunction(func_name: []const u8, profile: *const PlatformProfile) RuntimeClassification {
    // Fast path: check basic shim detection from normalizer first
    if (PlatformNormalizer.isPlatformRuntimeShim(func_name, profile)) {
        return .{
            .is_runtime = true,
            .category = .unknown,
            .reason = "matches universal runtime prefix pattern",
            .confidence = 0.9,
        };
    }

    // Detailed classification by category

    // 1. C++ allocator operators (IMPORTANT: helps solve cpp_fft FP!)
    if (isCppAllocator(func_name)) {
        return .{
            .is_runtime = true,
            .category = .cpp_allocator,
            .reason = "C++ operator new/delete/new[]/delete[]",
            .confidence = 0.95,
        };
    }

    // 2. C++ ABI runtime
    if (isCppAbiRuntime(func_name)) {
        return .{
            .is_runtime = true,
            .category = .cpp_abi,
            .reason = "C++ ABI runtime (exception handling, atexit, typeinfo)",
            .confidence = 0.95,
        };
    }

    // 3. LibC functions
    if (isLibcFunction(func_name)) {
        return .{
            .is_runtime = true,
            .category = .libc,
            .reason = "C standard library function",
            .confidence = 0.85,
        };
    }

    // 4. Platform-specific runtimes
    switch (profile.platform) {
        .macos => {
            const r = classifyMacOSRuntime(func_name) orelse null;
            if (r) |result| {
                if (result.is_runtime) return result;
            }
        },
        .linux => {
            const r = classifyLinuxRuntime(func_name) orelse null;
            if (r) |result| {
                if (result.is_runtime) return result;
            }
        },
        .windows => {
            const r = classifyWindowsRuntime(func_name) orelse null;
            if (r) |result| {
                if (result.is_runtime) return result;
            }
        },
        else => {},
    }

    // 5. Language-specific runtimes (cross-platform)
    const lr = classifyLanguageRuntime(func_name) orelse null;
    if (lr) |result| {
        if (result.is_runtime) return result;
    }

    // Default: not a runtime function
    return .{
        .is_runtime = false,
        .category = .unknown,
        .reason = "",
        .confidence = 0.0,
    };
}

// ============================================================================
// C++ Allocator Detection (P6 key feature for cpp_fft FP fix)
// ============================================================================

/// Check if function is a C++ memory allocator/deallocator.
///
/// These functions are compiler-generated and should not be treated as
/// user code. They include:
///   - `operator new(size_t)`
///   - `operator delete(void*)`
///   - `operator new[](size_t)`
///   - `operator delete[](void*)`
///   - `operator new(nothrow_t)` variants
///   - `::new` and `::delete` placement forms
///   - Mangled forms: `_Znwm`, `_ZdlPv`, `_Znam`, `_ZdaPv`
fn isCppAllocator(name: []const u8) bool {
    // Unmangled forms
    const unmangled_patterns = [_][]const u8{
        "operator new",
        "operator delete",
    };

    for (unmangled_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            log.debug("CPP-ALLOCATOR: '{s}' matches '{s}'", .{ name, pattern });
            return true;
        }
    }

    // Itanium C++ ABI mangled forms (most common on Linux/macOS)
    const mangled_patterns = [_][]const u8{
        "_Znw", // operator new (scalar)
        "_Zdl", // operator delete (scalar)
        "_Zna", // operator new[] (array)
        "_Zda", // operator delete[] (array)
        "_Znwm", // operator new(unsigned long)
        "_ZdlPv", // operator delete(void*)
        "_Znam", // operator new[](unsigned long)
        "_ZdaPv", // operator delete[](void*)
        "_ZnwmRKSt9nothrow_t", // operator new(unsigned long, std::nothrow_t const&)
        "_ZdlPvRKSt9nothrow_t", // operator delete(void*, std::nothrow_t const&)
    };

    for (mangled_patterns) |pattern| {
        if (std.mem.startsWith(u8, name, pattern)) {
            log.debug("CPP-ALLOCATOR-MANGLED: '{s}' matches mangled '{s}'", .{ name, pattern });
            return true;
        }
    }

    // MSVC mangled forms (Windows specific)
    const msvc_patterns = [_][]const u8{
        "??2@", // operator new (MSVC)
        "??3@", // operator delete (MSVC)
        "??_U", // operator new[] (MSVC)
        "??_V", // operator delete[] (MSVC)
    };

    for (msvc_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }

    return false;
}

// ============================================================================
// C++ ABI Runtime Detection
// ============================================================================

fn isCppAbiRuntime(name: []const u8) bool {
    const abi_prefixes = [_][]const u8{
        "__cxa_", // C++ ABI: exception handling, atexit, guard
        "__gxx_personality", // G++ personality routine
        "_ZTI", // Typeinfo vtable (RTTI)
        "_ZTS", // Typeinfo name (RTTI)
        "_ZTV", // Typeinfo virtual table (RTTI)
        "__dynamic_cast", // Dynamic cast support
    };

    for (abi_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }

    return false;
}

// ============================================================================
// LibC Function Detection
// ============================================================================

fn isLibcFunction(name: []const u8) bool {
    // Common LibC functions that are runtime-provided
    const libc_functions = [_][]const u8{
        "malloc",   "calloc",  "realloc", "free",
        "memcpy",   "memmove", "memset",  "memcmp",
        "memchr",   "strcpy",  "strncpy", "strcat",
        "strncat",  "strcmp",  "strncmp", "strlen",
        "strdup",   "strndup", "strstr",  "strchr",
        "strrchr",  "printf",  "fprintf", "sprintf",
        "snprintf", "vprintf", "scanf",   "fscanf",
        "sscanf",   "fopen",   "fclose",  "fread",
        "fwrite",   "fseek",   "ftell",
        "pthread_", // POSIX threads
        "dlopen", "dlsym",  "dlclose", // Dynamic linking
        "getenv", "setenv", "unsetenv",
        "exit",   "_exit",  "abort",
        "atexit", "signal", "sigaction",
        "raise",
    };

    // Exact match only (avoid partial matches like "my_malloc")
    for (libc_functions) |func| {
        if (std.mem.eql(u8, name, func)) return true;
    }

    return false;
}

// ============================================================================
// Platform-Specific Runtime Classification
// ============================================================================

fn classifyMacOSRuntime(name: []const u8) ?RuntimeClassification {
    // Objective-C runtime
    const objc_patterns = [_][]const u8{
        "_objc_", // All Objective-C runtime functions
        "objc_msgSend", // Message dispatch
        "objc_alloc", // Object allocation
        "objc_release", // Reference counting
    };

    for (objc_patterns) |p| {
        if (std.mem.startsWith(u8, name, p)) {
            return .{ .is_runtime = true, .category = .objc_runtime, .reason = "Objective-C runtime", .confidence = 0.95 };
        }
    }

    // Swift runtime
    const swift_patterns = [_][]const u8{
        "swift_retain",      "swift_release",
        "swift_allocObject",
        "$sS", // Swift symbol mangling
        "$sSo", // Swift object
    };

    for (swift_patterns) |p| {
        if (std.mem.startsWith(u8, name, p)) {
            return .{ .is_runtime = true, .category = .swift_runtime, .reason = "Swift runtime", .confidence = 0.95 };
        }
    }

    // Grand Central Dispatch
    const gcd_patterns = [_][]const u8{
        "dispatch_async",        "dispatch_sync",
        "dispatch_once",         "dispatch_after",
        "dispatch_queue_create", "_dispatch_main",
    };

    for (gcd_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) {
            return .{ .is_runtime = true, .category = .gcd_runtime, .reason = "Grand Central Dispatch", .confidence = 0.95 };
        }
    }

    // Darwin dynamic linker
    if (std.mem.startsWith(u8, name, "_dyld_")) {
        return .{ .is_runtime = true, .category = .dynamic_linker, .reason = "Darwin dynamic linker", .confidence = 0.95 };
    }

    return null;
}

fn classifyLinuxRuntime(name: []const u8) ?RuntimeClassification {
    // glibc internals
    const glibc_patterns = [_][]const u8{
        "__libc_start_main",
        "__register_frame_info",
        "__deregister_frame_info",
        "__do_global_dtors_aux",
        "__do_global_ctors_aux",
        "frame_dummy",
        "register_tm_clones",
        "deregister_tm_clones",
        "__stack_chk_fail",
        "__stack_chk_guard",
    };

    for (glibc_patterns) |p| {
        if (std.mem.eql(u8, name, p)) {
            return .{ .is_runtime = true, .category = .libc, .reason = "glibc internal", .confidence = 0.95 };
        }
    }

    // GCC runtime
    const gcc_patterns = [_][]const u8{
        "__x86.get_pc_thunk.bx",
        "__x86.get_pc_thunk.ax",
    };

    for (gcc_patterns) |p| {
        if (std.mem.eql(u8, name, p)) {
            return .{ .is_runtime = true, .category = .unknown, .reason = "GCC runtime thunk", .confidence = 0.90 };
        }
    }

    // ELF entry points
    if (std.mem.eql(u8, name, "_start") or std.mem.eql(u8, name, "_init") or std.mem.eql(u8, name, "_fini")) {
        return .{ .is_runtime = true, .category = .static_init, .reason = "ELF entry/init point", .confidence = 0.98 };
    }

    return null;
}

fn classifyWindowsRuntime(name: []const u8) ?RuntimeClassification {
    // MSVC CRT
    const msvc_patterns = [_][]const u8{
        "__security_init_cookie",
        "__security_check_cookie",
        "__report_gsfailure",
        "__report_rangecheckfailure",
        "__except_handler4",
        "__C_specific_handler",
        "___CxxFrameHandler3",
        "_amsg_exit",
        "_initterm_e",
        "_cexit",
        "_XcptFilter",
    };

    for (msvc_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) {
            return .{ .is_runtime = true, .category = .unknown, .reason = "MSVC CRT runtime", .confidence = 0.95 };
        }
    }

    // SEH handlers
    if (std.mem.startsWith(u8, name, "__except_handler") or
        std.mem.startsWith(u8, name, "___CxxFrameHandler"))
    {
        return .{ .is_runtime = true, .category = .exception_handler, .reason = "SEH handler", .confidence = 0.92 };
    }

    // CRT initialization sections
    if (std.mem.indexOf(u8, name, ".CRT$") != null) {
        return .{ .is_runtime = true, .category = .static_init, .reason = "CRT initialization section", .confidence = 0.95 };
    }

    return null;
}

// ============================================================================
// Cross-Platform Language Runtime Detection
// ============================================================================

fn classifyLanguageRuntime(name: []const u8) ?RuntimeClassification {
    // Go runtime
    const go_patterns = [_][]const u8{
        "runtime.", // Go runtime package
        "runtime.alloc",
        "runtime.free",
        "runtime._panic",
        "internal/task.", // TinyGo scheduler
    };

    for (go_patterns) |p| {
        if (std.mem.startsWith(u8, name, p)) {
            return .{ .is_runtime = true, .category = .go_runtime, .reason = "Go language runtime", .confidence = 0.93 };
        }
    }

    // Rust runtime
    const rust_patterns = [_][]const u8{
        "__rust_alloc",
        "__rust_dealloc",
        "__rust_alloc_error_handler",
        "__rust_out_of_procs",
        "drop_in_place",
        "rust_begin_unwind",
        "rust_panic",
    };

    for (rust_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) {
            return .{ .is_runtime = true, .category = .rust_runtime, .reason = "Rust language runtime", .confidence = 0.94 };
        }
    }

    // Zig runtime
    const zig_patterns = [_][]const u8{
        "__zig_probe_stack",
        "__zig_tag_name_",
        "__zig_is_named_enum_value_",
        "__zig_lt_errors_len",
        "__zig_err_name_table",
        "reachUnreachable",
        "unwrapNull",
    };

    for (zig_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) {
            return .{ .is_runtime = true, .category = .zig_runtime, .reason = "Zig language runtime", .confidence = 0.96 };
        }
    }

    // LLVM intrinsics (already partially covered, but add more here)
    if (std.mem.startsWith(u8, name, "llvm.")) {
        return .{ .is_runtime = true, .category = .llvm_intrinsic, .reason = "LLVM intrinsic function", .confidence = 0.99 };
    }

    // Sanitizer runtimes
    const sanitizer_prefixes = [_][]const u8{
        "__asan_",      "__msan_", "__tsan_", "__ubsan_",
        "__sanitizer_",
    };

    for (sanitizer_prefixes) |p| {
        if (std.mem.startsWith(u8, name, p)) {
            return .{ .is_runtime = true, .category = .sanitizer, .reason = "Address/Memory/Thread/UB sanitizer runtime", .confidence = 0.97 };
        }
    }

    // Profiling / coverage
    const prof_prefixes = [_][]const u8{
        "__gcov_", "__profn_", "__llvm_gcov", "__llvm_profile",
    };

    for (prof_prefixes) |p| {
        if (std.mem.startsWith(u8, name, p)) {
            return .{ .is_runtime = true, .category = .profiling, .reason = "Code coverage / profiling instrumentation", .confidence = 0.96 };
        }
    }

    // Stack protection
    if (std.mem.indexOf(u8, name, "__stack_chk") != null) {
        return .{ .is_runtime = true, .category = .stack_protection, .reason = "Stack canary check", .confidence = 0.98 };
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "classifyRuntimeFunction - C++ allocators" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "x86_64-pc-linux-gnu",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    // Unmangled forms
    var r = classifyRuntimeFunction("operator new(unsigned long)", &profile);
    try std.testing.expect(r.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.cpp_allocator, r.category);

    // Mangled forms (Itanium ABI)
    r = classifyRuntimeFunction("_Znam", &profile); // operator new[]
    try std.testing.expect(r.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.cpp_allocator, r.category);

    r = classifyRuntimeFunction("_ZdaPv", &profile); // operator delete[]
    try std.testing.expect(r.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.cpp_allocator, r.category);

    // User function should NOT be classified as runtime
    r = classifyRuntimeFunction("myCustomAllocator", &profile);
    try std.testing.expect(!r.is_runtime);
}

test "classifyRuntimeFunction - LibC" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "x86_64-pc-linux-gnu",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    const r = classifyRuntimeFunction("malloc", &profile);
    try std.testing.expect(r.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.libc, r.category);

    // Partial match should NOT trigger (e.g., "my_malloc_wrapper")
    const r2 = classifyRuntimeFunction("my_malloc_wrapper", &profile);
    try std.testing.expect(!r2.is_runtime);
}

test "classifyRuntimeFunction - Objective-C (macOS)" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "aarch64-apple-macosx",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    const r = classifyRuntimeFunction("_objc_msgSend", &profile);
    try std.testing.expect(r.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.objc_runtime, r.category);
}

test "classifyRuntimeFunction - user code not misclassified" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "x86_64-pc-linux-gnu",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    // These should NOT be classified as runtime
    const user_funcs = [_][]const u8{
        "main",
        "myFunction",
        "processData",
        "handleRequest",
        "FFT",
        "MerkleTree",
        "c_alloc_buffer",
    };

    for (user_funcs) |func| {
        const r = classifyRuntimeFunction(func, &profile);
        try std.testing.expect(!r.is_runtime, "'{s}' should not be classified as runtime", .{func});
    }
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "classifyRuntimeFunction - empty string" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    const r = classifyRuntimeFunction("", &profile);
    try std.testing.expect(!r.is_runtime);
}

test "classifyRuntimeFunction - similar but not runtime names" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    
    // These look like they could be runtime but are actually user code
    const ambiguous = [_][]const u8{
        "my_malloc_wrapper",     // Contains "malloc" but is user code
        "custom_new_operator",   // Contains "operator new" but not exact match
        "runtime_config",       // Contains "runtime." but user config
        "my_objc_helper",       // Contains "objc" but user helper
        "swiftUI_view",        // Contains "Swift" but user UI code
        "__my_private_func",   // Starts with __ but user-defined
    };
    
    for (ambiguous) |name| {
        const r = classifyRuntimeFunction(name, &profile);
        // Most of these should NOT be classified as runtime
        // (__my_private_func might be borderline but we're conservative)
        if (std.mem.indexOf(u8, name, "operator ") == null and 
            !std.mem.startsWith(u8, name, "llvm.") and
            !std.mem.startsWith(u8, name, "__asan_")) {
            try std.testing.expect(!r.is_runtime, "'{s}' should not be runtime", .{name});
        }
    }
}

test "classifyRuntimeFunction - MSVC C++ allocators" {
    var profile = PlatformProfile{
        .platform = .windows,
        .object_format = .coff,
        .target_triple = "x86_64-pc-windows-msvc",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };
    
    // MSVC decorated forms
    const msvc_allocs = [_][]const u8{
        "??2@YAPEAX_K@Z",  // operator new(unsigned __int64)
        "??3@YAXPEAX@Z",   // operator delete(void*)
        "??_U@YAPEAX_K@Z", // operator new[](unsigned __int64)
        "??_V@YAXPEAX@Z",  // operator delete[](void*)
    };
    
    for (msvc_allocs) |name| {
        const r = classifyRuntimeFunction(name, &profile);
        try std.testing.expect(r.is_runtime, "'{s}' should be MSVC allocator", .{name});
        try std.testing.expectEqual(RuntimeCategory.cpp_allocator, r.category);
    }
}

test "classifyRuntimeFunction - Go runtime variants" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    
    // Various Go runtime patterns
    const go_runtime = [_][]const u8{
        "runtime.gc",
        "runtime.alloc",
        "runtime.free",
        "runtime._panic",
        "internal/task.schedule",
    };
    
    for (go_runtime) |name| {
        const r = classifyRuntimeFunction(name, &profile);
        try std.testing.expect(r.is_runtime, "'{s}' should be Go runtime", .{name});
        try std.testing.expectEqual(RuntimeCategory.go_runtime, r.category);
    }
}

test "isCppAllocator - partial matches should NOT trigger" {
    // These contain substrings of allocator names but are NOT allocators
    try std.testing.expect(!isCppAllocator("operator_new_variable")); // Not "operator new"
    try std.testing.expect(!isCppAllocator("my_operator_delete")); // Has space in middle
    try std.testing.expect(!isCppAllocator("_Znam_custom")); // _Znam with extra suffix
}

// ============================================================================
// Comprehensive Edge Case Tests
// ============================================================================

test "classifyRuntimeFunction - Rust mangled runtime symbols" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // Rust drop_in_place (compiler-generated)
    const r1 = classifyRuntimeFunction("_ZN4core3ptr53drop_in_place<alloc::string::String>Ev", &profile);
    try std.testing.expect(r1.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.rust_runtime, r1.category);

    // Rust panic handler
    const r2 = classifyRuntimeFunction("rust_begin_unwind", &profile);
    try std.testing.expect(r2.is_runtime);

    // __rust_alloc / __rust_dealloc
    const r3 = classifyRuntimeFunction("__rust_alloc", &profile);
    try std.testing.expect(r3.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.rust_runtime, r3.category);

    const r4 = classifyRuntimeFunction("__rust_dealloc", &profile);
    try std.testing.expect(r4.is_runtime);
}

test "classifyRuntimeFunction - Swift mangled symbols" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "aarch64-apple-macosx", .datalayout = "", .arch = "", .vendor = "" };

    // Swift symbol mangling prefix $sS
    const r1 = classifyRuntimeFunction("$sSs5printyySS_pF", &profile); // Swift.print
    try std.testing.expect(r1.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.swift_runtime, r1.category);

    // swift_retain / swift_release
    const r2 = classifyRuntimeFunction("swift_retain", &profile);
    try std.testing.expect(r2.is_runtime);
}

test "classifyRuntimeFunction - Zig runtime patterns" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // Zig probe stack
    const r1 = classifyRuntimeFunction("__zig_probe_stack", &profile);
    try std.testing.expect(r1.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.zig_runtime, r1.category);

    // Zig error handling
    const r2 = classifyRuntimeFunction("reachUnreachable", &profile);
    try std.testing.expect(r2.is_runtime);

    const r3 = classifyRuntimeFunction("unwrapNull", &profile);
    try std.testing.expect(r3.is_runtime);
}

test "classifyRuntimeFunction - confidence levels vary by category" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // LLVM intrinsic: highest confidence (0.99)
    const r_llvm = classifyRuntimeFunction("llvm.memcpy.p0i8.p0i8.i64", &profile);
    try std.testing.expect(r_llvm.confidence >= 0.98);

    // Stack protection: very high confidence (0.98)
    const r_stack = classifyRuntimeFunction("__stack_chk_fail", &profile);
    try std.testing.expect(r_stack.confidence >= 0.97);

    // Sanitizer: high confidence (0.97)
    const r_san = classifyRuntimeFunction("__asan_init", &profile);
    try std.testing.expect(r_san.confidence >= 0.96);

    // LibC: medium-high confidence (0.85) — could be user wrapper with same name
    const r_libc = classifyRuntimeFunction("malloc", &profile);
    try std.testing.expect(r_libc.confidence >= 0.80 and r_libc.confidence < 0.90);

    // User code: zero confidence
    const r_user = classifyRuntimeFunction("myFunction", &profile);
    try std.testing.expect(r_user.confidence == 0.0);
}

test "classifyRuntimeFunction - C++ ABI RTTI patterns" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // Typeinfo vtable (_ZTV)
    try std.testing.expect(classifyRuntimeFunction("_ZTISt9exception", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("_ZTSSt9exception", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("_ZTVSt9exception", &profile).is_runtime);

    // Dynamic cast
    try std.testing.expect(classifyRuntimeFunction("__dynamic_cast", &profile).is_runtime);
}

test "classifyRuntimeFunction - Linux glibc internals" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // glibc startup
    const r1 = classifyRuntimeFunction("__libc_start_main", &profile);
    try std.testing.expect(r1.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.libc, r1.category);

    // Global constructors/destructors
    try std.testing.expect(classifyRuntimeFunction("__do_global_dtors_aux", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("__do_global_ctors_aux", &profile).is_runtime);

    // Frame dummy
    try std.testing.expect(classifyRuntimeFunction("frame_dummy", &profile).is_runtime);

    // TM clones
    try std.testing.expect(classifyRuntimeFunction("register_tm_clones", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("deregister_tm_clones", &profile).is_runtime);
}

test "classifyRuntimeFunction - Windows MSVC CRT details" {
    var profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "x86_64-pc-windows-msvc", .datalayout = "", .arch = "", .vendor = "" };

    // Security cookie
    try std.testing.expect(classifyRuntimeFunction("__security_init_cookie", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("__security_check_cookie", &profile).is_runtime);

    // GS failure reporting
    try std.testing.expect(classifyRuntimeFunction("__report_gsfailure", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("__report_rangecheckfailure", &profile).is_runtime);

    // SEH handlers
    const r_seh = classifyRuntimeFunction("__except_handler4", &profile);
    try std.testing.expect(r_seh.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.exception_handler, r_seh.category);

    // C++ frame handlers
    try std.testing.expect(classifyRuntimeFunction("___CxxFrameHandler3", &profile).is_runtime);
}

test "classifyRuntimeFunction - macOS specific runtimes" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "aarch64-apple-macosx", .datalayout = "", .arch = "", .vendor = "" };

    // ObjC message dispatch
    const r_objc = classifyRuntimeFunction("_objc_msgSend", &profile);
    try std.testing.expect(r_objc.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.objc_runtime, r_objc.category);

    // GCD dispatch
    const r_gcd = classifyRuntimeFunction("dispatch_async", &profile);
    try std.testing.expect(r_gcd.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.gcd_runtime, r_gcd.category);

    // dyld
    const r_dyld = classifyRuntimeFunction("_dyld_register_func_for_add_image", &profile);
    try std.testing.expect(r_dyld.is_runtime);
    try std.testing.expectEqual(RuntimeCategory.dynamic_linker, r_dyld.category);
}

test "classifyRuntimeFunction - profiling and coverage instrumentation" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // gcov
    try std.testing.expect(classifyRuntimeFunction("__gcov_init", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("__gcov_flush", &profile).is_runtime);

    // LLVM profiling
    try std.testing.expect(classifyRuntimeFunction("__llvm_profile_init", &profile).is_runtime);
    try std.testing.expect(classifyRuntimeFunction("__llvm_profile_write_file", &profile).is_runtime);

    // profn
    try std.testing.expect(classifyRuntimeFunction("__profn_foo", &profile).is_runtime);
}

test "RuntimeCategory enum completeness" {
    const cats = [_]RuntimeCategory{
        .libc, .cpp_abi, .cpp_allocator, .objc_runtime, .swift_runtime,
        .gcd_runtime, .go_runtime, .rust_runtime, .zig_runtime,
        .llvm_intrinsic, .sanitizer, .profiling, .static_init,
        .static_fini, .exception_handler, .tls_init, .stack_protection,
        .dynamic_linker, .unknown,
    };
    for (cats) |cat| {
        const name = cat.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "isLibcFunction - exact match only (no partial)" {
    // Exact match should work
    try std.testing.expect(isLibcFunction("malloc"));
    try std.testing.expect(isLibcFunction("free"));
    try std.testing.expect(isLibcFunction("printf"));

    // Partial match should NOT work
    try std.testing.expect(!isLibcFunction("my_malloc"));
    try std.testing.expect(!isLibcFunction("malloc_wrapper"));
    try std.testing.expect(!isLibcFunction("printf_debug"));
    try std.testing.expect(!isLibcFunction("freed")); // Contains "free" but not exact
}
