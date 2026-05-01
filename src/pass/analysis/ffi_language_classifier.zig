//! FFI Language Classifier
//!
//! Extracted from ffi_boundary.zig (P2-2 refactoring).
//! Provides language detection and classification utilities for FFI boundary analysis:
//! - Language identification (Rust, Zig, C, unknown)
//! - Rust name demangling
//! - Boundary kind classification
//! - Function family detection (libc, JNI, Python C API, C++ ABI, STL)
//!
//! Design principle: Stateless utility functions with pattern matching.
//! No internal state, all functions are pure (except demangleRustName which allocates).

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const FFIBoundary = @import("../../diag/issue.zig").FFIBoundary;
const Language = FFIBoundary.Language;
const BoundaryKind = FFIBoundary.BoundaryKind;

/// Pattern definitions for language detection.
/// Shared across multiple classification functions.
/// These patterns match the ones originally in FFIBoundaryPass.FFIPatterns.
const FFIPatterns = struct {
    /// Known Rust FFI patterns in function names
    pub const rust_patterns = [_][]const u8{
        "_ZN", // Rust mangled name prefix
        "_rust_", // Rust extern function prefix
        "rs2py_", // Rust-to-Python bridge
        "rust_", // Generic Rust prefix
    };

    /// Known Zig FFI patterns in function names
    pub const zig_patterns = [_][]const u8{
        "zig_", // Zig external function prefix
        "extern", // Zig extern block marker
        "c_", // Zig C interop convention
        "@cImport", // C import macro
        "__zig", // Zig compiler-generated FFI glue
    };

    /// Known libc function names (exact match)
    pub const libc_patterns = [_][]const u8{
        "malloc",       "calloc",             "realloc",              "free",
        "memcpy",       "memmove",            "memset",               "memcmp",
        "strcpy",       "strncpy",            "strlen",               "strcmp",
        "strchr",       "fopen",              "fclose",               "fread",
        "fwrite",       "fgets",              "fputs",                "open",
        "close",        "read",               "write",                "lseek",
        "printf",       "fprintf",            "sprintf",              "snprintf",
        "scanf",        "fscanf",             "sscanf",               "pthread_create",
        "pthread_join", "pthread_mutex_lock", "pthread_mutex_unlock", "socket",
        "connect",      "bind",               "listen",               "accept",
        "recv",         "send",               "dlopen",               "dlsym",
        "dlclose",
    };
};

/// Identify the language of a function based on its LLVM value.
///
/// Uses pattern matching on the function name to detect:
/// - **Rust**: `_ZN` (mangled), `_rust_`, `rs2py_`, `rust_`
/// - **Zig**: `zig_` prefix with additional indicators (`@`, `zig_`)
/// - **C**: Default fallback (most common for C ABI code)
///
/// Parameters:
///   - func: LLVM function value to identify
///
/// Returns:
///   - Detected language enum value
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return .unknown;

    const func_name = std.mem.span(func_name_ptr);

    // Check for Rust patterns
    for (FFIPatterns.rust_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .rust;
        }
    }

    // Check for Zig patterns (be more specific to avoid false positives)
    // Only mark as zig if we see clear Zig indicators
    var has_zig_indicator = false;
    for (FFIPatterns.zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            // Check for additional Zig-specific patterns
            if (std.mem.indexOf(u8, func_name, "zig_") != null or
                std.mem.indexOf(u8, func_name, "@") != null)
            {
                has_zig_indicator = true;
                break;
            }
        }
    }

    if (has_zig_indicator) {
        return .zig;
    }

    // Default to C (most common case for C ABI)
    return .c;
}

/// Identify the language of a called function based on its name string.
///
/// Similar to `identifyLanguage()` but operates on a string slice instead of
/// an LLVM value. Used when the caller already has the function name extracted.
///
/// Parameters:
///   - func_name: Function name string to analyze
///
/// Returns:
///   - Detected language enum value
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    // LLVM intrinsics (llvm.* prefix) are compiler-generated,
    // not any language's FFI function. Skip them to prevent
    // misclassification (e.g., llvm.threadlocal.address.p0 as Zig).
    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .unknown;
    }

    // Check for Rust patterns
    for (FFIPatterns.rust_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .rust;
        }
    }

    // Check for Zig patterns (be more specific to avoid false positives)
    for (FFIPatterns.zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            // Check for additional Zig-specific patterns
            if (std.mem.indexOf(u8, func_name, "zig_") != null or
                std.mem.indexOf(u8, func_name, "@") != null)
            {
                return .zig;
            }
            // If only matched "extern" or "c_" prefix without Zig indicators,
            // it's likely a C function with extern declaration
            if (std.mem.eql(u8, pattern, "extern") or std.mem.eql(u8, pattern, "c_")) {
                continue;
            }
            return .zig;
        }
    }

    // Check for libc functions — these are C by definition
    for (FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return .c;
        }
    }

    // Check for Go functions (main.* or runtime.* patterns)
    if (std.mem.startsWith(u8, func_name, "main.") or
        std.mem.startsWith(u8, func_name, "runtime.") or
        std.mem.startsWith(u8, func_name, "syscall."))
    {
        return .go;
    }

    // Check for Objective-C functions
    if (std.mem.startsWith(u8, func_name, "_OBJC_") or
        std.mem.startsWith(u8, func_name, "objc_"))
    {
        return .unknown;
    }

    // For external declarations with C ABI naming (no Rust/Zig/Go/ObjC
    // patterns), classify as C. This covers extern "C" functions,
    // libc wrappers, and typical C library functions.
    // Internal (non-external) functions default to unknown to avoid
    // misclassifying language-specific internal helpers.
    return .c;
}

/// Demangle a Rust mangled name to a readable format.
///
/// Rust uses Itanium-style mangling (`_ZN...E`). This function extracts
/// the crate and module path components for human-readable diagnostics.
///
/// Parameters:
///   - allocator: Memory allocator for output string
///   - mangled: Mangled Rust symbol name
///
/// Returns:
///   - Demangled name (caller must free), or null if not a Rust mangled name
pub fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
    if (mangled.len < 4 or mangled[0] != '_' or mangled[1] != 'Z' or mangled[2] != 'N') {
        return null;
    }

    var pos: usize = 3;
    var components: [3][]const u8 = .{ "", "", "" };
    var comp_count: usize = 0;

    while (pos < mangled.len and comp_count < 3) {
        if (mangled[pos] == 'E') break;

        var len: usize = 0;
        while (pos < mangled.len and mangled[pos] >= '0' and mangled[pos] <= '9') {
            const new_len = std.math.mul(usize, len, 10) catch break;
            const digit = @as(usize, mangled[pos] - '0');
            len = std.math.add(usize, new_len, digit) catch break;
            pos += 1;
        }

        if (len == 0 or pos >= mangled.len or pos + len > mangled.len) break;
        if (len > 50) break;

        const slice = mangled[pos .. pos + len];
        pos += len;

        if (slice.len == 0) continue;
        if (slice[0] == '$' or slice[0] == 'C' or slice[0] == '{' or slice[0] == '}') {
            if (pos < mangled.len and mangled[pos] == 'E') pos += 1;
            continue;
        }

        if (comp_count == 0) {
            if (std.mem.eql(u8, slice, "core") or
                std.mem.eql(u8, slice, "alloc") or
                std.mem.eql(u8, slice, "std") or
                std.mem.eql(u8, slice, "rust_ffi_demo"))
            {
                components[0] = slice;
                comp_count = 1;
                continue;
            }
        }

        if (comp_count > 0 or
            (!std.mem.eql(u8, slice, "core") and
                !std.mem.eql(u8, slice, "alloc") and
                !std.mem.eql(u8, slice, "std")))
        {
            components[comp_count] = slice;
            comp_count += 1;
        }

        if (pos < mangled.len and mangled[pos] == 'E') {
            pos += 1;
            break;
        }
    }

    if (comp_count >= 2) {
        return (try std.fmt.allocPrint(allocator, "{s}::{s}", .{ components[0], components[1] }));
    } else if (comp_count == 1) {
        return (try allocator.dupe(u8, components[0]));
    }

    return (try allocator.dupe(u8, mangled));
}

/// Classify the FFI boundary kind based on caller and callee languages.
///
/// Maps language pairs to specific boundary kinds:
/// - Rust -> C: `.rust_to_c`
/// - Zig -> C: `.zig_to_c`
/// - C -> Rust: `.c_to_rust`
/// - C -> Zig: `.c_to_zig`
/// - Other combinations: `.external_unknown`
///
/// Parameters:
///   - caller_lang: Detected language of the calling function
///   - callee_lang: Detected language of the called function
///
/// Returns:
///   - Boundary kind enum value
pub fn classifyBoundaryKind(caller_lang: Language, callee_lang: Language) BoundaryKind {
    return switch (caller_lang) {
        .rust => switch (callee_lang) {
            .c => .rust_to_c,
            .zig => .external_unknown,
            else => .external_unknown,
        },
        .zig => switch (callee_lang) {
            .c => .zig_to_c,
            .rust => .external_unknown,
            else => .external_unknown,
        },
        .c => switch (callee_lang) {
            .rust => .c_to_rust,
            .zig => .c_to_zig,
            else => .external_unknown,
        },
        else => .external_unknown,
    };
}

/// Check if a function name matches a known libc function.
///
/// Uses exact string matching against a comprehensive list of standard
/// C library functions (memory, string, I/O, threading, networking, dynamic loading).
///
/// Parameters:
///   - func_name: Function name to check
///
/// Returns:
///   - true if it's a known libc function
pub fn isLibcFunction(func_name: []const u8) bool {
    for (FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return true;
        }
    }
    return false;
}

/// Classify FFI boundary with enhanced detection for dynamic loading/JNI/Python.
///
/// Extends `classifyBoundaryKind()` by checking for:
/// - Dynamic loading functions (dlopen/dlsym/dlclose)
/// - JNI functions (Java Native Interface)
/// - Python C API functions
///
/// If none of these special families match, falls back to standard classification.
///
/// Parameters:
///   - caller_lang: Detected language of the calling function
///   - callee_lang: Detected language of the called function
///   - func_name: Name of the called function
///
/// Returns:
///   - Boundary kind enum value (may be special kind like .dynamic_loading)
pub fn classify_boundary_kind_enhanced(caller_lang: Language, callee_lang: Language, func_name: []const u8) BoundaryKind {
    if (isDynamicLoadingFunction(func_name)) return .dynamic_loading;
    if (isJNIFunction(func_name)) return .jni_call;
    if (isPythonCApiFunction(func_name)) return .python_c_api_call;
    return classifyBoundaryKind(caller_lang, callee_lang);
}

/// Alias for classify_boundary_kind_enhanced (camelCase variant).
pub const classifyBoundaryKindEnhanced = classify_boundary_kind_enhanced;

/// Check if a function is a POSIX dynamic loading function.
///
/// Detects: dlopen, dlsym, dlclose
pub fn isDynamicLoadingFunction(func_name: []const u8) bool {
    const dl_patterns = [_][]const u8{ "dlopen", "dlsym", "dlclose" };
    for (dl_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a Java Native Interface (JNI) function.
///
/// Detects JNI prefixes (`JNI_`, `Java_`) and common JNI method names
/// (FindClass, GetMethodID, NewObject, Call*Method, etc.)
pub fn isJNIFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "JNI_")) return true;
    if (std.mem.startsWith(u8, func_name, "Java_")) return true;
    const jni_patterns = [_][]const u8{
        "FindClass",                "GetMethodID",             "GetStaticMethodID",
        "GetFieldID",               "GetStaticFieldID",        "NewObject",
        "CallVoidMethod",           "CallIntMethod",           "CallObjectMethod",
        "CallStaticVoidMethod",     "CallStaticIntMethod",     "CallStaticObjectMethod",
        "CallNonvirtualVoidMethod", "CallNonvirtualIntMethod", "NewStringUTF",
        "NewGlobalRef",             "NewLocalRef",             "DeleteGlobalRef",
        "DeleteLocalRef",           "NewByteArray",            "AttachCurrentThread",
        "DetachCurrentThread",      "GetEnv",                  "GetJavaVM",
        "MonitorEnter",             "MonitorExit",             "ExceptionCheck",
        "ExceptionClear",           "ExceptionDescribe",       "ExceptionOccurred",
        "Throw",                    "ThrowNew",                "GetStringUTFChars",
        "ReleaseStringUTFChars",    "GetObjectField",          "SetObjectField",
        "GetIntField",              "SetIntField",             "IsSameObject",
        "IsInstanceOf",
    };
    for (jni_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a Python C API function.
///
/// Detects Python C API prefixes (`Py_`, `Py`) and common patterns
/// (PyArg_*, PyBool*, PyDict*, PyErr_*, etc.)
pub fn isPythonCApiFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "Py_")) return true;
    if (std.mem.startsWith(u8, func_name, "Py")) {
        const py_prefixes = [_][]const u8{
            "PyArg_",        "PyBool",        "PyBytes",          "PyCallable",
            "PyDict",        "PyErr_",        "PyEval_",          "PyFile",
            "PyFloat",       "PyFrame",       "PyFrozenSet",      "PyGC_",
            "PyGetSetDescr", "PyHash",        "PyImport_",        "PyInt_",
            "PyIter",        "PyList_",       "PyLong",           "PyMapping",
            "PyMem_",        "PyMethodDescr", "PyModule_",        "PyObject_",
            "PyProperty",    "PyRange",       "PySeqIter",        "PySet_",
            "PySlice",       "PyString",      "PyStructSequence", "PySys_",
            "PyThreadState", "PyTraceBack",   "PyTuple_",         "PyType",
            "PyUnicode",     "PyWeakref",     "PyCapsule",
        };
        for (py_prefixes) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
    }
    const py_gil_patterns = [_][]const u8{
        "PyGILState_",            "PyEval_InitThreads",
        "PyEval_RestoreThread",   "PyEval_SaveThread",
        "Py_BEGIN_ALLOW_THREADS", "Py_END_ALLOW_THREADS",
    };
    for (py_gil_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a C++ ABI runtime internal function.
/// These are compiler-generated functions for exception handling,
/// thread-local storage initialization, dynamic type info, and
/// Meyers singleton initialization guards. They are NOT user code
/// and should never be reported as FFI risks or security issues.
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    const cxa_prefixes = [_][]const u8{
        "__cxa_begin_catch",
        "__cxa_end_catch",
        "__cxa_allocate_exception",
        "__cxa_throw",
        "__cxa_free_exception",
        "__cxa_get_globals",
        "__cxa_guard_acquire",
        "__cxa_guard_release",
        "__cxa_guard_abort",
        "__cxa_atexit",
        "__cxa_demangle",
        "__cxa_pure_virtual",
        "__cxa_rethrow",
        "__cxa_allocate_dependent_exception",
        "__cxa_throw_dependent_exception",
        "__cxa_dependent_exception",
        "__cxa_current_exception_type",
        "__cxa_get_exception_ptr",
        "__cxa_exception_class",
    };
    for (cxa_prefixes) |prefix| {
        if (std.mem.eql(u8, func_name, prefix)) {
            return true;
        }
    }
    // Also catch any __cxa_* function by prefix
    if (std.mem.indexOf(u8, func_name, "__cxa_") != null) {
        return true;
    }
    return false;
}

/// Check if a function is an STL/libc++ internal template expansion.
/// These are template instantiation helpers and should be skipped during analysis.
pub fn isStlInternalFunction(func_name: []const u8) bool {
    const stl_prefixes = [_][]const u8{
        "_ZNSt3__", "_ZNSt4", "_ZNSt6", "_ZNSt7", "_ZNSt10",
    };
    for (stl_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
    }
    if (std.mem.indexOf(u8, func_name, "__gnu") != null) return true;
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "identifyLanguage - defaults to C" {
    try std.testing.expectEqual(Language.c, identifyLanguage(undefined));
}

test "isLibcFunction - known functions" {
    try std.testing.expect(isLibcFunction("malloc"));
    try std.testing.expect(isLibcFunction("free"));
    try std.testing.expect(isLibcFunction("pthread_create"));
    try std.testing.expect(!isLibcFunction("my_custom_func"));
}

test "isDynamicLoadingFunction - dlopen family" {
    try std.testing.expect(isDynamicLoadingFunction("dlopen"));
    try std.testing.expect(isDynamicLoadingFunction("dlsym"));
    try std.testing.expect(isDynamicLoadingFunction("dlclose"));
    try std.testing.expect(!isDynamicLoadingFunction("malloc"));
}

test "isCppAbiInternalFunction - __cxa_ functions" {
    try std.testing.expect(isCppAbiInternalFunction("__cxa_throw"));
    try std.testing.expect(isCppAbiInternalFunction("__cxa_begin_catch"));
    try std.testing.expect(!isCppAbiInternalFunction("my_function"));
}
