//! FFI Utility Functions
//!
//! Contains utility functions shared between ffi_boundary.zig,
//! ptr_lifetime.zig, and other FFI-related analysis passes.
//!
//! This module centralizes:
//! - Language identification (Rust, Zig, C, Go)
//! - API detection (JNI, Python C-API, Dynamic Loading)
//! - C++/STL internal function detection
//! - Name demangling utilities

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");

const ffi_types = @import("ffi_types.zig");

const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const BoundaryKind = @import("../../../diag/issue.zig").FFIBoundary.BoundaryKind;

// ============================================================================
// Language Identification
// ============================================================================

/// Identify the language of a function based on its characteristics.
/// Delegates to unified language_detector (single source of truth).
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return @import("../../../semantics/language_detector.zig").identifyLanguage(func);
}

/// Identify the language of a called function based on its name.
/// Delegates to unified language_detector (single source of truth).
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    return @import("../../../semantics/language_detector.zig").identifyCalleeLanguage(func_name);
}

// ============================================================================
// Boundary Classification
// ============================================================================

/// Classify the boundary kind based on caller and callee languages.
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

/// Classify FFI boundary with enhanced detection for dynamic loading/JNI/Python.
pub fn classify_boundary_kind_enhanced(caller_lang: Language, callee_lang: Language, func_name: []const u8) BoundaryKind {
    if (isDynamicLoadingFunction(func_name)) return .dynamic_loading;
    if (isJNIFunction(func_name)) return .jni_call;
    if (isPythonCApiFunction(func_name)) return .python_c_api_call;
    return classifyBoundaryKind(caller_lang, callee_lang);
}

// ============================================================================
// API Detection Functions
// ============================================================================

/// Check if a function name is a dynamic loading function (dlopen/dlsym/dlclose).
pub fn isDynamicLoadingFunction(func_name: []const u8) bool {
    const dl_patterns = [_][]const u8{ "dlopen", "dlsym", "dlclose" };
    for (dl_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function name is a JNI function.
pub fn isJNIFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "JNI_")) return true;
    if (std.mem.startsWith(u8, func_name, "Java_")) return true;

    for (ffi_types.jni_patterns.all_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function name is a Python C-API function.
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

// ============================================================================
// Zig-Specific Detection
// ============================================================================

/// Check if a Zig function is an internal/runtime function (SAFE — skip analysis).
/// Based on zig_ffi_filter.md: Zig compiler-generated helpers are guaranteed
/// safe by the type system and should not generate FFI warnings.
pub fn is_zig_internal_function(func_name: []const u8) bool {
    // Check against known-safe internal patterns
    for (ffi_types.FFIPatterns.zig_internal_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    // Check for Zig compiler-generated mangled names (safe by construction)
    // Pattern: __zig_* or zig.* (module paths)
    if (std.mem.indexOf(u8, func_name, "__zig") != null) {
        return true;
    }

    // Zig anonymous function names (lambda/closure helpers)
    if (std.mem.indexOf(u8, func_name, "(anonymous namespace)") != null) {
        return true;
    }

    // Zig generic instantiation patterns (e.g., "foo(T).inner")
    if (std.mem.indexOf(u8, func_name, "generic(") != null or
        std.mem.indexOf(u8, func_name, "__anon_") != null)
    {
        return true;
    }

    return false;
}

/// Check if a called C function from @cImport is a known-safe binding.
/// These are standard libc functions that Zig wraps safely.
pub fn is_zig_safe_cimport(func_name: []const u8) bool {
    for (ffi_types.FFIPatterns.zig_cimport_safe) |pattern| {
        if (std.mem.eql(u8, func_name, pattern) or
            std.mem.indexOf(u8, func_name, pattern) != null)
        {
            return true;
        }
    }
    return false;
}

// ============================================================================
// C++/STL Internal Function Detection
// ============================================================================

/// Check if a function is a C++ ABI runtime internal function.
/// These are compiler-generated functions for exception handling,
/// thread-local storage initialization, dynamic type info, and
/// Meyers singleton initialization guards. They are NOT user code
/// and should never be reported as FFI risks or security issues.
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    for (ffi_types.cpp_abi_prefixes) |prefix| {
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
pub fn isStlInternalFunction(func_name: []const u8) bool {
    for (ffi_types.stl_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
    }
    if (std.mem.indexOf(u8, func_name, "__gnu") != null) return true;
    return false;
}

/// Check if a function is Rust's drop_in_place (destructor glue).
/// These are guaranteed safe by Rust's ownership system —
/// UAF patterns here are normal destructor chaining, NOT bugs.
pub fn isRustDropGlue(func_name: []const u8) bool {
    const drop_patterns = [_][]const u8{
        // Drop glue / compiler-generated destructors
        "drop_in_place",
        "_ZN4core3ptr13drop_in_place",
        "<T as core::ops::drop::Drop>::drop",
        "::drop",
        "real_drop_in_place",
        "drop_and_deallocate",
        // Dealloc intrinsics (compiler-inserted)
        // Canonical source: ptr_types.RUST_ALLOC_INTRINSICS (subset below + __rustc__rustc_dealloc extension)
        "__rust_dealloc",
        "__rust_alloc",
        "__rustc__rustc_dealloc",
        // Panic infrastructure
        "panic",
        // Unwinding / cleanup paths
        "_Unwind_",
        "cleanup",
    };
    for (drop_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

// ============================================================================
// Intentional Pattern Detection
// ============================================================================

/// Check if a function name suggests intentional/safe/test code.
///
/// Functions with these naming patterns are likely:
/// - Reference implementations ("safe_*", "correct_*", "example_*")
/// - Test fixtures ("test_*", "*_test")
/// - Demo code ("demo_*", "sample_*")
/// - Benchmarking ("bench_*", "*_bench")
///
/// These functions should have their FFI warnings suppressed or
/// downgraded to INFO level, as they are not production code
/// where real vulnerabilities would matter.
pub fn is_likely_intentional_pattern(func_name: []const u8) bool {
    for (ffi_types.intentional_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }

    for (ffi_types.intentional_contains) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

    return false;
}

// ============================================================================
// LibC Function Detection
// ============================================================================

/// Check if a function name is a libc function.
pub fn isLibcFunction(func_name: []const u8) bool {
    for (ffi_types.FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Name Demangling
// ============================================================================

/// Demangle a Rust mangled name to a readable format.
/// Returns null if the name is not a Rust mangled name (caller should use the original).
/// Returns an allocated string on success (caller must free it).
pub fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
    if (mangled.len < 4 or mangled[0] != '_' or mangled[1] != 'Z' or mangled[2] != 'N') {
        return null;
    }

    var pos: usize = 3;
    var components: [8][]const u8 = .{ "", "", "", "", "", "", "", "" };
    var comp_count: usize = 0;

    while (pos < mangled.len and comp_count < 8) {
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
