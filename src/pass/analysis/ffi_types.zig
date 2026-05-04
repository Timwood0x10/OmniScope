//! FFI Boundary Types and Constants
//!
//! Contains type definitions, constants, and patterns shared between
//! ffi_boundary.zig, ptr_lifetime.zig, and other FFI-related analysis passes.
//!
//! This module centralizes:
//! - FFI statistics and result types
//! - FFI pattern constants (language-specific patterns)
//! - API detection function lists (JNI, Python C-API, Dynamic Loading)

const std = @import("std");

// ============================================================================
// Type Definitions
// ============================================================================

/// Error type for FFI boundary detection operations.
pub const FFIBoundaryError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Module not available.
    NoModule,
};

/// Statistics for FFI boundary analysis
pub const FFIBoundaryStats = struct {
    func_count: u32 = 0,
    total_boundaries: u32 = 0,
    cross_lang: u32 = 0,
    libc: u32 = 0,
    external_unknown: u32 = 0,
    dangerous: u32 = 0,
    /// Count by risk kind
    command_exec: u32 = 0,
    unchecked_copy: u32 = 0,
    format_string: u32 = 0,
    allocator: u32 = 0,
    deallocator: u32 = 0,
    rust_ownership: u32 = 0,
    borrow_escaped: u32 = 0,
};

/// Result of analyzing a function for FFI boundaries
pub const AnalyzeResult = struct {
    count: u32 = 0,
    cross_lang: u32 = 0,
    libc: u32 = 0,
    external_unknown: u32 = 0,
    dangerous_count: u32 = 0,
    suppressed_intentional: u32 = 0,
};

// ============================================================================
// FFI Pattern Constants
// ============================================================================

/// Known FFI patterns for language identification
pub const FFIPatterns = struct {
    /// Rust FFI function name patterns
    pub const rust_patterns = &[_][]const u8{
        "extern", // extern "C"
        "rust_", // Rust C ABI
        "_ZN", // Rust mangling
    };

    /// Zig FFI function name patterns (based on zig_ffi_filter.md)
    pub const zig_patterns = &[_][]const u8{
        "extern", // extern "C" functions
        "c_", // C API prefixes from @cImport
        "@cImport", // C import macro
        "zig_", // Zig runtime functions calling C
        "__zig", // Zig compiler-generated FFI glue
    };

    /// Zig-specific internal/runtime functions (SAFE — not real FFI issues)
    pub const zig_internal_patterns = &[_][]const u8{
        // Zig compiler-generated helpers (guaranteed safe by type system)
        "zig_assert_fail",
        "zig_panic",
        "zig_oq",
        "zig_write",
        "zig_alloc",
        "zig_free",
        "zig_error",
        "zig_generic_resolve",
        "zig_monitor_init",
        "zig_monitor_lock",
        "zig_monitor_unlock",
        "zig_monitor_notify",
        "zig_monitor_wait",
        // Zig standard library internals
        "std.debug.assert",
        "std.debug.panic",
        "std.mem.copy",
        "std.mem.set",
        "std.fmt.format",
        "std.fmt.bufPrint",
        "std.heap.c_allocator",
        "std.heap.page_allocator",
        "std.heap.raw_c_allocator",
        // Zig OS abstraction layer (safe wrappers)
        "std.os.system",
        "std.posix",
        "std.windows",
        // Zig builtin functions (compiler intrinsics)
        "@memcpy",
        "@memset",
        "@memset",
        "@floatCast",
        "@intCast",
        "@bitCast",
        "@ptrCast",
        "@alignCast",
        "@errorReturnTrace",
    };

    /// Zig @cImport common patterns (known-safe libc bindings)
    pub const zig_cimport_safe = &[_][]const u8{
        "c.printf", "c.sprintf", "c.snprintf", // String formatting
        "c.malloc", "c.free", "c.realloc", "c.calloc", // Memory management
        "c.memcpy", "c.memmove", "c.memset", "c.memcmp", // Memory operations
        "c.strlen", "c.strcmp", "c.strncmp", "c.strcpy", "c.strncpy", // String ops
        "c.fopen", "c.fclose", "c.fread", "c.fwrite", // File I/O
        "c.exit", "c.abort", "c.atexit", // Process control
        "c.getenv", "c.setenv", // Environment
        "c.time", "c.clock", "c.gettimeofday", // Time
        "c.rand", "c.srand", // Random
    };

    /// C standard library functions (not FFI boundaries)
    pub const libc_patterns = &[_][]const u8{
        "malloc",
        "free",
        "printf",
        "scanf",
        "strcpy",
        "strcmp",
        "strlen",
        "memcpy",
        "memset",
        "exit",
        "abort",
    };

    /// Dangerous/suspicious FFI patterns
    pub const dangerous_patterns = &[_][]const u8{
        "system",
        "exec",
        "popen",
        "eval",
        "shell",
        "debug",
        "dump",
    };
};

// ============================================================================
// API Detection Patterns
// ============================================================================

/// JNI function patterns for boundary detection
pub const jni_patterns = struct {
    pub const nullable_functions = [_][]const u8{
        "FindClass",    "GetMethodID",      "GetStaticMethodID",
        "GetFieldID",   "GetStaticFieldID", "NewStringUTF",
        "NewByteArray", "GetObjectClass",
    };

    pub const call_methods = [_][]const u8{
        "CallVoidMethod",       "CallIntMethod",       "CallObjectMethod",
        "CallStaticVoidMethod", "CallStaticIntMethod", "CallNonvirtualVoidMethod",
    };

    pub const all_patterns = [_][]const u8{
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
};

/// Python C-API function patterns for boundary detection
pub const python_capi_patterns = struct {
    pub const nullable_functions = [_][]const u8{
        "PyArg_ParseTuple",      "PyArg_ParseKeywords", "Py_BuildValue",
        "PyObject_Call",         "PyObject_CallObject", "PyObject_CallFunction",
        "PyTuple_New",           "PyList_New",          "PyDict_New",
        "PyLong_AsLong",         "PyFloat_AsDouble",    "PyCapsule_GetPointer",
        "PyImport_ImportModule",
    };

    pub const gil_required = [_][]const u8{
        "PyEval_EvalCode",
        "PyEval_CallObject",
        "PyEval_CallFunction",
        "PyObject_CallObject",
        "PyObject_CallFunction",
        "PyObject_CallMethod",
        "PyRun_SimpleString",
        "PyRun_File",
        "PyImport_Import",
        "PyImport_ReloadModule",
        "PyObject_GetAttr",
        "PyObject_SetAttr",
        "PyObject_GetItem",
        "PyObject_SetItem",
    };

    pub const error_check = [_][]const u8{
        "PyArg_ParseTuple",     "PyArg_ParseKeywords",   "Py_BuildValue",
        "PyObject_Call",        "PyDict_GetItem",        "PyList_GetItem",
        "PyTuplet_Item",        "PyLong_AsLong",         "PyFloat_AsDouble",
        "PyCapsule_GetPointer", "PyImport_ImportModule",
    };
};

/// C++ ABI internal function prefixes (compiler-generated, should be suppressed)
pub const cpp_abi_prefixes = [_][]const u8{
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

/// STL/libc++ internal function prefixes (template expansions, should be suppressed)
pub const stl_prefixes = [_][]const u8{
    "_ZNSt3__", "_ZNSt4", "_ZNSt6", "_ZNSt7", "_ZNSt10",
};

/// Intentional/safe/test function naming patterns (should suppress warnings)
pub const intentional_prefixes = [_][]const u8{
    "safe_", // safe_example, safe_usage
    "correct_", // correct_usage, correct_pattern
    "example_", // example_basic, example_advanced
    "test_", // test_malloc, test_free
    "demo_", // demo_ffi, demo_binding
    "sample_", // sample_code, sample_api
    "bench_", // benchmark_alloc
    "fixture_", // fixture_data
    "mock_", // mock_database
    "stub_", // stub_network
    "reference_", // reference_impl
};

pub const intentional_contains = [_][]const u8{
    "intentional",
    "known_safe",
    "expected",
    "deliberate",
};

/// Safe libc fortified functions (__*_chk variants)
pub const safe_libc_patterns = [_][]const u8{
    "__memcpy_chk",  "__memmove_chk",  "__memset_chk",
    "__strcpy_chk",  "__strcat_chk",   "__strncpy_chk",
    "__sprintf_chk", "__snprintf_chk",
};

/// C++ memory management operator mangled names
pub const cpp_operators = [_][]const u8{
    "_Znwm",   "_Znam",   "_ZdlPv", "_ZdaPv",
    "_ZdlPvm", "_ZdaPvm",
};
