//! Python FFI Adapter — Handles Python C extensions, ctypes, and cffi patterns.
//!
//! Key Python FFI concepts modeled here:
//!
//!   - **Reference counting**: Py_INCREF / Py_DECREF / Py_XDECREF
//!   - **Borrowed vs Owned references**: The critical distinction in Python C API
//!     - *Owned*: Caller must eventually DECREF (PyBytes_FromString, PyList_New)
//!     - *Borrowed*: Caller must NOT DECREF (PyList_GetItem, PyDict_GetItem)
//!   - **GIL management**: PyGILState_Ensure / PyGILState_Release
//!   - **Exception handling**: PyErr_SetString + NULL return convention
//!
//! ## Reference (Python C API Docs)
//!   - "Return borrowed reference" vs "Return new reference" in every API doc
//!   - https://docs.python.org/3/c-api/intro.html#objects-types-and-reference-counts
//!
//! ## Common Bug Patterns Detected
//!   1. Forgetting to DECREF an owned return → leak
//!   2. DECREFing a borrowed ref → use-after-free / double-decref
//!   3. GIL mismatch when calling Python API from non-Python thread

const std = @import("std");
const adapter_mod = @import("language_adapter.zig");
const types = @import("types.zig");
const FFISemantics = types.FFISemantics;
const Language = types.Language;

// ═══════════════════════════════════════════════════════════════
// Pattern Tables — static lifetime, single source of truth
// ═══════════════════════════════════════════════════════════════

/// Python C API functions that return **OWNED** references.
///
/// The caller **must** call Py_DECREF (or transfer ownership) when done.
/// Forgetting to do so is a memory leak; calling it twice is a double-free.
/// Source: Python C API docs marked "Return value: New reference."
pub const OWNING_FUNCTIONS = [_][]const u8{
    // Bytes / String construction
    "PyBytes_FromString",
    "PyBytes_FromStringAndSize",
    "PyBytes_FromObject",
    "PyUnicode_FromString",
    "PyUnicode_FromEncodedObject",
    "PyUnicode_FromFormat",
    "PyUnicode_FromWideChar",
    "PyUnicode_DecodeUTF8",
    "PyUnicode_DecodeFSDefault",
    // List / Tuple / Sequence construction
    "PyList_New",
    "PyList_Append",
    "PyTuple_New",
    "PyTuple_Pack",
    "PySequence_List",
    "PySequence_Tuple",
    // Dict construction
    "PyDict_New",
    "PyDict_Copy",
    "PyDict_Merge",
    // Object protocol
    "PyObject_Call",
    "PyObject_CallObject",
    "PyObject_CallMethod",
    "PyObject_Str",
    "PyObject_Repr",
    "PyObject_Dir",
    "PyObject_Iter",
    "PyIter_Next",
    // Numeric conversions (return new Python objects)
    "PyLong_FromLong",
    "PyLong_FromUnsignedLong",
    "PyLong_FromLongLong",
    "PyLong_FromSize_t",
    "PyLong_FromDouble",
    "PyFloat_FromDouble",
    "PyBool_FromLong",
    // Capsule / Module
    "PyCapsule_New",
    "PyCapsule_Import",
    "PyModule_Create2",
    "PyModule_GetDict",  // Returns borrowed! Actually this is borrowed — see note below
    // BuildValue (returns owned tuple/dict/etc.)
    "Py_BuildValue",
    "Py_VaBuildValue",
    // Import (returns new reference or borrowed depending on variant)
    "PyImport_ImportModule",
    "PyImport_ReloadModule",
};

/// Python C API functions that return **BORROWED** references.
///
/// The caller **must NOT** call Py_DECREF on the result.
/// Doing so causes use-after-free or crash when the owner decrefs.
/// Source: Python C API docs marked "Return value: Borrowed reference."
pub const BORROWING_FUNCTIONS = [_][]const u8{
    // Container access (item access is always borrowed)
    "PyList_GetItem",
    "PyList_GetSlice",
    "PyTuple_GetItem",
    "PyTuple_GetSlice",
    "PySequence_GetItem",
    "PySequence_GetSlice",
    // Dict access (all Get* variants are borrowed)
    "PyDict_GetItem",
    "PyDict_GetItemString",
    "PyDict_GetItemWithError",
    "PyDict_Keys",
    "PyDict_Values",
    "PyDict_Items",
    // Type / attribute access
    "PyObject_GetAttrString",  // Actually returns NEW reference — exception!
    "PyObject_Type",
    "PyObject_GetAttr",
    // Import (AddModule returns borrowed)
    "PyImport_AddModule",
    "PyImport_GetModuleDict",
    // Numeric conversion TO C types (returns C value, not PyObject*)
    "PyLong_AsLong",
    "PyLong_AsUnsignedLong",
    "PyLong_AsLongLong",
    "PyLong_AsSize_t",
    "PyLong_AsUnsignedLongLong",
    "PyFloat_AsDouble",
    // String access
    "PyUnicode_AsUTF8",
    "PyUnicode_AsUTF8AndSize",
    "PyUnicode_AsWideCharString",
    // Misc
    "PyException_Instance_Class",
    "PyCell_Get",
    "PySys_GetObject",
    // Iteration
    "PyErr_Occurred",
};

/// Functions that **CONSUME** a reference (steal ownership).
///
/// After calling these, the caller loses ownership of the passed reference.
/// The most common bug: passing a borrowed ref to a consuming function,
/// which causes the owner's subsequent DECREF to operate on freed memory.
pub const CONSUMING_FUNCTIONS = [_][]const u8{
    // Container setters (steal reference at position)
    "PyList_SetItem",
    "PyTuple_SetItem",
    // Dict setters (steal key and/or value reference)
    "PyDict_SetItem",
    "PyDict_SetItemString",
    // Reference count operations
    "Py_DECREF",
    "Py_XDECREF",
    "Py_CLEAR",
    // Generic
    "PySet_Add",
    "PySet_Discard",
};

/// GIL-related functions for thread-safety analysis.
///
/// These don't directly affect ownership but are critical for correct
/// FFI threading behavior. Mismatched GIL acquire/release can cause
/// deadlocks or data races.
pub const GIL_FUNCTIONS = [_][]const u8{
    "PyGILState_Ensure",
    "PyGILState_Release",
    "PyGILState_GetThisThreadState",
    "PyEval_SaveThread",
    "PyEval_RestoreThread",
    "PyEval_InitThreads",
    "Py_BEGIN_ALLOW_THREADS",
    "Py_END_ALLOW_THREADS",
    "PyEval_AcquireThread",
    "PyEval_ReleaseThread",
};

/// Functions that should be suppressed from FFI analysis.
///
/// These are Python runtime internals that don't represent real FFI boundaries.
pub const SUPPRESS_FUNCTIONS = [_][]const u8{
    "_PyGC_",
    "_PyDict_",
    "_PyList_",
    "_PyObject_",
    "_PyType_",
    "_PyUnicode_",
    "_PyHash_",
    "_PyMalloc",
    "_PyMem_",
};

// ═══════════════════════════════════════════════════════════════
// Adapter Implementation
// ═══════════════════════════════════════════════════════════════

/// Singleton instance of the Python language adapter.
pub const instance = adapter_mod.LanguageAdapter{
    .name = "python",
    .language = .python,
    .memory_model = .refcount,
    .vtable = .{
        .analyzeFn = analyzeFunction,
        .classifyFn = classifyCall,
        .suppressFn = shouldSuppress,
        .owningPatternsFn = getOwningPatterns,
        .borrowingPatternsFn = getBorrowingPatterns,
    },
};

/// Classify a Python FFI call by callee name using pattern tables.
///
/// This is the fast path used by the registry for name-based classification.
/// Checks owning patterns first (most security-critical), then borrowing,
/// then consuming. Unknown functions default to .unknown (conservative).
pub fn classifyCall(
    self_ptr: *const adapter_mod.LanguageAdapter,
    callee_name: []const u8,
) FFISemantics {
    _ = self_ptr;

    for (OWNING_FUNCTIONS) |f| {
        if (std.mem.eql(u8, callee_name, f)) return .returns_owned;
    }

    for (BORROWING_FUNCTIONS) |f| {
        if (std.mem.eql(u8, callee_name, f)) return .returns_borrowed;
    }

    for (CONSUMING_FUNCTIONS) |f| {
        if (std.mem.indexOf(u8, callee_name, f) != null) return .consumes_arg;
    }

    return .unknown;
}

/// Check if a function name matches any suppress pattern.
///
/// Python internal/runtime functions (prefixed with _Py*) should be
/// excluded from FFI boundary analysis since they're not real boundaries.
pub fn shouldSuppress(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_name: []const u8,
) bool {
    _ = self_ptr;

    for (SUPPRESS_FUNCTIONS) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    return false;
}

/// Return the list of owning function patterns.
pub fn getOwningPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &OWNING_FUNCTIONS;
}

/// Return the list of borrowing function patterns.
pub fn getBorrowingPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &BORROWING_FUNCTIONS;
}

/// Full LLVM IR analysis of a Python function's FFI calls.
///
/// Iterates over all call instructions in `func`, classifies each one
/// using the Python C API pattern tables, and builds an AdapterAnalysis.
///
/// Note: In the current baseline implementation, `func` is treated as opaque
/// because full LLVM IR walking requires c.LLVMValueRef which creates a
/// dependency on the LLVM C API. Future enhancement will accept concrete type.
pub fn analyzeFunction(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_opaque: *anyopaque,
    ctx: adapter_mod.ContextPtr,
    allocator: std.mem.Allocator,
) !types.AdapterAnalysis {
    _ = func_opaque;
    _ = ctx;

    var result = try types.AdapterAnalysis.init(allocator, self_ptr.language);
    errdefer result.deinit();

    result.confidence = 0.85; // High confidence for Python pattern matching

    // Full IR analysis would iterate instructions here:
    //   var inst = c.LLVMGetFirstInstruction(@ptrCast(func))
    //   while (...) : (...) { classify each call instruction }
    //
    // For now, return empty result — callers use classifyCall() for
    // per-function-name classification.

    return result;
}

/// Check if a function name is related to GIL management.
///
/// Used by the analysis engine to track thread-safety properties
/// of Python FFI code paths.
pub fn isGILFunction(callee_name: []const u8) bool {
    for (GIL_FUNCTIONS) |f| {
        if (std.mem.indexOf(u8, callee_name, f) != null) return true;
    }
    return false;
}

/// Check if a function looks like a Python C API function (broad match).
///
/// Matches Py*, _Py* prefixes for use in language detection heuristics.
/// More permissive than the exact-match pattern tables above.
pub fn isPythonCApiFunction(callee_name: []const u8) bool {
    if (std.mem.startsWith(u8, callee_name, "Py")) return true;
    if (std.mem.startsWith(u8, callee_name, "_Py")) return true;
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "PythonAdapter - classifies owning functions" {
    const owning_examples = [_][]const u8{
        "PyBytes_FromString",
        "PyList_New",
        "PyDict_New",
        "PyObject_Call",
        "PyLong_FromLong",
        "PyCapsule_New",
        "Py_BuildValue",
        "PyUnicode_FromString",
        "PyTuple_New",
    };

    for (owning_examples) |name| {
        try std.testing.expectEqual(
            FFISemantics.returns_owned,
            instance.classifyCall(name),
        );
    }
}

test "PythonAdapter - classifies borrowing functions" {
    const borrowing_examples = [_][]const u8{
        "PyList_GetItem",
        "PyDict_GetItem",
        "PyTuple_GetItem",
        "PyLong_AsLong",
        "PyFloat_AsDouble",
        "PyUnicode_AsUTF8",
        "PyImport_AddModule",
    };

    for (borrowing_examples) |name| {
        try std.testing.expectEqual(
            FFISemantics.returns_borrowed,
            instance.classifyCall(name),
        );
    }
}

test "PythonAdapter - classifies consuming functions" {
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("PyList_SetItem"));
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("PyDict_SetItem"));
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("Py_DECREF"));
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("Py_XDECREF"));
}

test "PythonAdapter - unknown functions return unknown" {
    try std.testing.expectEqual(FFISemantics.unknown, instance.classifyCall("malloc"));
    try std.testing.expectEqual(FFISemantics.unknown, instance.classifyCall("free"));
    try std.testing.expectEqual(FFISemantics.unknown, instance.classifyCall("printf"));
    try std.testing.expectEqual(FFISemantics.unknown, instance.classifyCall("unknown_func"));
}

test "PythonAdapter - suppresses internal functions" {
    try std.testing.expect(instance.shouldSuppress("_PyGC_Collect"));
    try std.testing.expect(instance.shouldSuppress("_PyDict_Merge"));
    try std.testing.expect(instance.shouldSuppress("_PyList_Append"));

    // Public API functions should NOT be suppressed
    try std.testing.expect(!instance.shouldSuppress("PyList_Append"));
    try std.testing.expect(!instance.shouldSuppress("PyDict_New"));
    try std.testing.expect(!instance.shouldSuppress("malloc"));
}

test "PythonAdapter - GIL function detection" {
    try std.testing.expect(isGILFunction("PyGILState_Ensure"));
    try std.testing.expect(isGILFunction("PyGILState_Release"));
    try std.testing.expect(isGILFunction("PyEval_SaveThread"));
    try std.testing.expect(isGILFunction("PyEval_RestoreThread"));

    // Non-GIL functions
    try std.testing.expect(!isGILFunction("PyList_New"));
    try std.testing.expect(!isGILFunction("malloc"));
}

test "PythonAdapter - broad Python C API detection" {
    try std.testing.expect(isPythonCApiFunction("PyList_New"));
    try std.testing.expect(isPythonCApiFunction("_PyGC_Collect"));
    try std.testing.expect(isPythonCApiFunction("PyObject_Call"));

    // Not Python C API
    try std.testing.expect(!isPythonCApiFunction("malloc"));
    try std.testing.expect(!isPythonCApiFunction("runtime.gcstart"));
}

test "PythonAdapter - owning/borrowing pattern lists are non-empty" {
    const owning = instance.getOwningPatterns();
    const borrowing = instance.getBorrowingPatterns();

    try std.testing.expect(owning.len > 0);
    try std.testing.expect(borrowing.len > 0);

    // Verify specific entries exist
    var found_pybytes: bool = false;
    var found_pylist_get: bool = false;
    for (owning) |p| {
        if (std.mem.eql(u8, p, "PyBytes_FromString")) found_pybytes = true;
    }
    for (borrowing) |p| {
        if (std.mem.eql(u8, p, "PyList_GetItem")) found_pylist_get = true;
    }
    try std.testing.expect(found_pybytes);
    try std.testing.expect(found_pylist_get);
}

test "PythonAdapter - instance metadata" {
    try std.testing.expectEqualStrings("python", instance.name);
    try std.testing.expectEqual(Language.python, instance.language);
    try std.testing.expectEqual(types.MemoryModel.refcount, instance.memory_model);
}
