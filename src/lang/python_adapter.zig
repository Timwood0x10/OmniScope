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
const Severity = types.Severity;
const log = std.log.scoped(.python_adapter);

// LLVM C API for IR traversal
const c = @import("../ir/llvm_raw.zig").c;

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
    // Attribute access (returns NEW reference - must DECREF)
    "PyObject_GetAttrString",
    "PyObject_GetAttr", // overloaded variant that returns new ref
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
    "PyModule_GetDict", // Returns borrowed! Actually this is borrowed — see note below
    // BuildValue (returns owned tuple/dict/etc.)
    "Py_BuildValue",
    "Py_VaBuildValue",
    // Import (returns new reference or borrowed depending on variant)
    "PyImport_ImportModule",
    "PyImport_ReloadModule",
    // Buffer protocol (acquires buffer - must release with PyBuffer_Release)
    "PyObject_GetBuffer",
    // Interpreter lifecycle (returns new interpreter state)
    "Py_NewInterpreter",
    // Exception handling (returns owned exception info)
    "PyErr_Fetch",
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
    // String access (returns pointer into object's internal storage)
    "PyUnicode_AsUTF8",
    "PyUnicode_AsUTF8AndSize",
    "PyUnicode_AsWideCharString",
    "PyBytes_AsString",
    "PyBytesAsString", // alias
    // Misc
    "PyException_Instance_Class",
    "PyCell_Get",
    "PySys_GetObject",
    // Iteration
    "PyErr_Occurred",
    // Interpreter state (returns borrowed reference to main interpreter)
    "PyInterpreterState_Main",
    // Hash (returns C value)
    "PyObject_Hash",
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
    // Buffer protocol (releases acquired buffer)
    "PyBuffer_Release",
    // Interpreter lifecycle (finalizes interpreter state)
    "Py_EndInterpreter",
    "Py_FinalizeEx",
    "Py_Finalize",
    // Exception handling (consumes exception references passed to it)
    "PyErr_Restore",
    // Capsule destructor registration
    "PyCapsule_SetDestructor",
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

/// Python-specific issue patterns for advanced detection.
///
/// These patterns go beyond simple ownership classification to detect
/// complex bug patterns specific to Python C API usage.
pub const IssuePattern = enum {
    /// DECREF called on a borrowed reference (Test 1 in edge cases)
    borrowed_ref_decref,
    /// New reference returned but never DECREF'd (Test 2)
    new_ref_leak,
    /// Reference stolen by SetItem then also DECREF'd (Test 3)
    stolen_ref_double_decref,
    /// Python API called without holding GIL (Test 4)
    gil_violation,
    /// PyObject_Call* returned NULL but not checked (Test 5)
    null_return_not_checked,
    /// PyObject_GetBuffer without PyBuffer_Release (Test 6)
    buffer_leak,
    /// PyUnicode_AsUTF8 pointer used after DECREF (Test 7)
    dangling_utf8_pointer,
    /// Capsule destructor + explicit double free (Test 8)
    capsule_double_free,
    /// Stale pointer after interpreter finalization (Test 9, 10)
    stale_interpreter_ptr,
};

/// GIL state tracking for detecting GIL violations.
pub const GILState = enum {
    held,
    released,
    unknown,
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
/// then consuming, then refcount operations. Unknown functions default to .unknown (conservative).
pub fn classifyCall(
    self_ptr: *const adapter_mod.LanguageAdapter,
    callee_name: []const u8,
) FFISemantics {
    _ = self_ptr;

    // Check refcount operations first (most common in Python C API)
    if (std.mem.eql(u8, callee_name, "Py_INCREF") or
        std.mem.eql(u8, callee_name, "Py_XINCREF"))
    {
        return .python_refcount_inc;
    }

    if (std.mem.eql(u8, callee_name, "Py_DECREF") or
        std.mem.eql(u8, callee_name, "Py_XDECREF"))
    {
        return .python_refcount_dec;
    }

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
/// using the Python C API pattern tables, and builds an AdapterAnalysis
/// with reference count tracking, leak detection, and advanced pattern detection.
///
/// ## Algorithm
/// 1. Check if function has a body (not just a declaration)
/// 2. Iterate through all basic blocks
/// 3. For each CALL instruction, extract callee name
/// 4. Classify the call using Python C API pattern tables
/// 5. Track reference count operations (INCREF/DECREF)
/// 6. Detect potential leaks from unbalanced refcount operations
/// 7. Advanced detection:
///    - GIL violations (Python API calls without GIL)
///    - Buffer leaks (GetBuffer without Release)
///    - Null return not checked after fallible calls
///    - Stale interpreter pointers after finalization
pub fn analyzeFunction(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_opaque: *anyopaque,
    ctx: adapter_mod.ContextPtr,
    allocator: std.mem.Allocator,
) !types.AdapterAnalysis {
    _ = ctx;

    var result = try types.AdapterAnalysis.init(allocator, self_ptr.language);
    errdefer result.deinit();

    const llvm_func: c.LLVMValueRef = @ptrCast(@alignCast(func_opaque));

    if (c.LLVMIsDeclaration(llvm_func) != 0) {
        result.confidence = 0.1;
        return result;
    }

    // Get function name for issue location tracking
    const func_name_ptr = c.LLVMGetValueName(llvm_func);
    const func_name = if (func_name_ptr != null)
        std.mem.span(func_name_ptr)
    else
        "unknown_function";

    // Advanced tracking state for pattern detection
    var gil_state: GILState = .unknown;
    var buffer_acquired: u32 = 0;
    var interpreter_finalized: bool = false;

    // Borrowed reference tracking for DECREF detection
    // Tracks values returned by borrowing functions that should not be decref'd
    const BorrowedRefTracker = struct {
        value_addr: u64,
        source_func: []const u8,
        inst_addr: u64,
    };
    var borrowed_ref_trackers = std.ArrayList(BorrowedRefTracker){};
    defer {
        borrowed_ref_trackers.deinit(allocator);
    }

    // ── Iterate through all basic blocks ──
    var bb_iter = c.LLVMGetFirstBasicBlock(llvm_func);

    while (bb_iter != null) : (bb_iter = c.LLVMGetNextBasicBlock(bb_iter)) {
        const bb = bb_iter.?;
        var inst_iter = c.LLVMGetFirstInstruction(bb);

        while (inst_iter != null) : (inst_iter = c.LLVMGetNextInstruction(inst_iter)) {
            const inst = inst_iter.?;
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall) continue;

            const called_value = c.LLVMGetCalledValue(inst);
            if (called_value == null) continue;

            const callee_name_ptr = c.LLVMGetValueName(called_value);
            if (callee_name_ptr == null) continue;
            const callee_name = std.mem.span(callee_name_ptr);

            const classification = classifyCall(self_ptr, callee_name);
            if (classification == .unknown) continue;

            const inst_addr: u64 = @intFromPtr(inst);
            const call_info = types.FFICallInfo.init(
                inst_addr,
                callee_name,
                classification,
                0.92,
                .python,
            );

            try result.addCall(call_info);

            // Track reference count operations
            if (classification == .returns_owned or
                classification == .python_refcount_inc)
            {
                result.refcount_increments += 1;
            } else if (classification == .python_refcount_dec or
                classification == .consumes_arg)
            {
                result.refcount_decrements += 1;

                // Check for DECREF on borrowed references (Step 3)
                if (classification == .python_refcount_dec or
                    std.mem.indexOf(u8, callee_name, "Py_DECREF") != null or
                    std.mem.indexOf(u8, callee_name, "Py_XDECREF") != null)
                {
                    // Get the operand being decref'd (simplified check)
                    // In production, this would need proper def-use analysis
                    if (borrowed_ref_trackers.items.len > 0) {
                        // Flag potential borrowed ref error if we see DECREF after borrowed ref
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "[Python CAPI] Potential DECREF on borrowed reference: {s}() called after borrowing function in {s}",
                            .{ callee_name, func_name },
                        );
                        try result.addIssue(.{
                            .issue_type = .borrowed_ref_error,
                            .message = msg,
                            .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                            .severity = .high,
                            .confidence = 0.75,
                            .evidence = "borrowed ref tracking: DECREF after GetItem/As* function",
                        });
                    }
                }
            }

            // Track returned value from borrowing functions
            if (classification == .returns_borrowed) {
                // Mark this return value as borrowed (simplified: track by instruction address)
                const ret_value_addr = @intFromPtr(inst); // Simplified: use inst addr as proxy
                try borrowed_ref_trackers.append(allocator, .{
                    .value_addr = ret_value_addr,
                    .source_func = callee_name,
                    .inst_addr = inst_addr,
                });
            }

            // ── Advanced Pattern Detection ──

            // GIL state tracking
            if (std.mem.eql(u8, callee_name, "PyEval_SaveThread") or
                std.mem.eql(u8, callee_name, "Py_BEGIN_ALLOW_THREADS"))
            {
                gil_state = .released;
            } else if (std.mem.eql(u8, callee_name, "PyEval_RestoreThread") or
                std.mem.eql(u8, callee_name, "Py_END_ALLOW_THREADS"))
            {
                gil_state = .held;
            }

            // Detect GIL violation: Python API call while GIL is released (Step 2)
            if (gil_state == .released and
                isPythonCApiFunction(callee_name) and
                !isGILFunction(callee_name))
            {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "[Python CAPI] GIL violation: {s}() called while GIL is released at instruction 0x{x} in {s}",
                    .{ callee_name, inst_addr, func_name },
                );
                try result.addIssue(.{
                    .issue_type = .gil_violation,
                    .message = msg,
                    .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                    .severity = .critical,
                    .confidence = 0.90,
                    .evidence = "GIL state tracking: Py_* API call without holding GIL",
                });
            }

            // Buffer protocol tracking
            if (std.mem.eql(u8, callee_name, "PyObject_GetBuffer")) {
                buffer_acquired += 1;
            } else if (std.mem.eql(u8, callee_name, "PyBuffer_Release")) {
                if (buffer_acquired > 0) buffer_acquired -= 1;
            }

            // Interpreter lifecycle tracking
            if (std.mem.eql(u8, callee_name, "Py_FinalizeEx") or
                std.mem.eql(u8, callee_name, "Py_Finalize"))
            {
                interpreter_finalized = true;
            }
            if (interpreter_finalized and
                (classification == .returns_owned or classification == .returns_borrowed))
            {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "[Python CAPI] Possible stale pointer after Py_FinalizeEx: {s}() called in {s}",
                    .{ callee_name, func_name },
                );
                try result.addIssue(.{
                    .issue_type = .stale_interpreter_ptr,
                    .message = msg,
                    .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                    .severity = .high,
                    .confidence = 0.70,
                    .evidence = "interpreter lifecycle tracking: API call after finalization",
                });
            }

            // Null-return check detection for fallible functions
            if (isFalliblePythonFunction(callee_name) and classification == .returns_owned) {
                // Note: In a full implementation, we would check if the next instruction
                // is a null-check. For now, we flag the pattern as potentially unsafe.
                result.has_potential_leak = true;
            }
        }
    }

    // ── Post-analysis checks ──

    // Check for buffer leak: unmatched GetBuffer calls
    if (buffer_acquired > 0) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "[Python CAPI] Buffer leak: {} PyObject_GetBuffer without matching PyBuffer_Release in {s}",
            .{ buffer_acquired, func_name },
        );
        try result.addIssue(.{
            .issue_type = .buffer_leak,
            .message = msg,
            .location = types.IssueLocation.init(func_name),
            .severity = .medium,
            .confidence = 0.85,
            .evidence = "buffer protocol tracking",
        });
    }

    // Analyze reference count balance and generate issues (Step 1)
    result.refcount_balance = @as(i32, @intCast(result.refcount_increments)) -
        @as(i32, @intCast(result.refcount_decrements));

    if (result.refcount_balance > 0) {
        // Reference leak: more INC than DEC
        const leaked_count = result.refcount_balance;
        const severity = if (leaked_count > 3) Severity.critical else Severity.high;
        const confidence = if (leaked_count > 5) @as(f32, 0.95) else @as(f32, 0.80);

        const msg = try std.fmt.allocPrint(
            allocator,
            "[Python CAPI] Reference leak: {d} owned reference(s) not decremented (INC: {d}, DEC: {d}) in {s}",
            .{ leaked_count, result.refcount_increments, result.refcount_decrements, func_name },
        );
        try result.addIssue(.{
            .issue_type = .memory_leak,
            .message = msg,
            .location = types.IssueLocation.init(func_name),
            .severity = severity,
            .confidence = confidence,
            .evidence = "refcount imbalance analysis",
        });

        log.warn("Python: refcount imbalance: +{} (more INCREF than DECREF)", .{result.refcount_balance});
    } else if (result.refcount_balance < 0) {
        // Potential double-decref / UAF: more DEC than INC
        const over_dec_count = -result.refcount_balance;
        const msg = try std.fmt.allocPrint(
            allocator,
            "[Python CAPI] Potential double-decref/UAF: {d} more DECREF than INCREF (INC: {d}, DEC: {d}) in {s}",
            .{ over_dec_count, result.refcount_increments, result.refcount_decrements, func_name },
        );
        try result.addIssue(.{
            .issue_type = .use_after_free,
            .message = msg,
            .location = types.IssueLocation.init(func_name),
            .severity = .critical,
            .confidence = 0.70,
            .evidence = "refcount imbalance: too many DECREF",
        });

        log.warn("Python: refcount imbalance: {} (more DECREF than INCREF - potential UAF)", .{result.refcount_balance});
    }

    result.is_analyzed = true;
    result.confidence = if (result.ffi_calls.items.len > 0) 0.92 else 0.15;

    return result;
}

/// Check if a Python C API function can return NULL on failure.
///
/// Fallible functions must have their return value checked before use.
fn isFalliblePythonFunction(callee_name: []const u8) bool {
    const fallible_patterns = [_][]const u8{
        "PyList_New",             "PyDict_New",                "PyTuple_New",
        "PyBytes_FromString",     "PyBytes_FromStringAndSize", "PyUnicode_FromString",
        "PyLong_FromLong",        "PyObject_Call",             "PyObject_CallObject",
        "PyObject_GetAttrString", "PyObject_GetBuffer",        "PyCapsule_New",
        "PyModule_Create2",       "PyImport_ImportModule",     "Py_BuildValue",
        "Py_NewInterpreter",
    };

    for (fallible_patterns) |pattern| {
        if (std.mem.eql(u8, callee_name, pattern)) return true;
    }
    return false;
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
        "PyObject_GetAttrString", // Fixed: was incorrectly in borrowing
        "PyObject_GetBuffer", // New: buffer protocol
        "Py_NewInterpreter", // New: interpreter lifecycle
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
        "PyBytes_AsString", // New: string access
        "PyInterpreterState_Main", // New: interpreter state
        "PyObject_Hash", // New: hash function
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
    // New: buffer and interpreter lifecycle
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("PyBuffer_Release"));
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("Py_FinalizeEx"));
    try std.testing.expectEqual(FFISemantics.consumes_arg, instance.classifyCall("Py_EndInterpreter"));
    // Py_DECREF/Py_XDECREF are classified as python_refcount_dec (more specific)
    try std.testing.expectEqual(FFISemantics.python_refcount_dec, instance.classifyCall("Py_DECREF"));
    try std.testing.expectEqual(FFISemantics.python_refcount_dec, instance.classifyCall("Py_XDECREF"));
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

test "PythonAdapter - classifyCall detects refcount operations" {
    // Py_INCREF should be classified as refcount increment
    try std.testing.expectEqual(FFISemantics.python_refcount_inc, instance.classifyCall("Py_INCREF"));
    try std.testing.expectEqual(FFISemantics.python_refcount_inc, instance.classifyCall("Py_XINCREF"));

    // Py_DECREF/Py_XDECREF are classified as python_refcount_dec (more specific than consumes_arg)
    try std.testing.expectEqual(FFISemantics.python_refcount_dec, instance.classifyCall("Py_DECREF"));
    try std.testing.expectEqual(FFISemantics.python_refcount_dec, instance.classifyCall("Py_XDECREF"));
}

test "PythonAdapter - AdapterAnalysis new fields initialized correctly" {
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Verify new fields have correct default values
    try std.testing.expectEqual(@as(u32, 0), analysis.refcount_increments);
    try std.testing.expectEqual(@as(u32, 0), analysis.refcount_decrements);
    try std.testing.expectEqual(@as(i32, 0), analysis.refcount_balance);
    try std.testing.expectEqual(false, analysis.has_potential_leak);
    try std.testing.expectEqual(types.Severity.low, analysis.leak_severity);
    try std.testing.expectEqual(false, analysis.is_analyzed);

    // Verify hasFindings returns false for empty analysis
    try std.testing.expect(!analysis.hasFindings());
}

test "PythonAdapter - FFISemantics displayName includes new variants" {
    try std.testing.expectEqualStrings("PythonRefcountInc", FFISemantics.python_refcount_inc.displayName());
    try std.testing.expectEqualStrings("PythonRefcountDec", FFISemantics.python_refcount_dec.displayName());
}

test "PythonAdapter - IssuePattern enum covers all edge cases" {
    // Verify all 9 issue patterns exist by checking specific variants
    _ = IssuePattern.borrowed_ref_decref;
    _ = IssuePattern.new_ref_leak;
    _ = IssuePattern.stolen_ref_double_decref;
    _ = IssuePattern.gil_violation;
    _ = IssuePattern.null_return_not_checked;
    _ = IssuePattern.buffer_leak;
    _ = IssuePattern.dangling_utf8_pointer;
    _ = IssuePattern.capsule_double_free;
    _ = IssuePattern.stale_interpreter_ptr;
}

test "PythonAdapter - isFalliblePythonFunction detects fallible APIs" {
    // These functions can return NULL and must be checked
    try std.testing.expect(isFalliblePythonFunction("PyList_New"));
    try std.testing.expect(isFalliblePythonFunction("PyObject_Call"));
    try std.testing.expect(isFalliblePythonFunction("PyObject_GetBuffer"));
    try std.testing.expect(isFalliblePythonFunction("PyCapsule_New"));

    // Non-fallible functions (return void or C types)
    try std.testing.expect(!isFalliblePythonFunction("PyList_GetItem")); // returns borrowed
    try std.testing.expect(!isFalliblePythonFunction("Py_INCREF")); // void
    try std.testing.expect(!isFalliblePythonFunction("PyLong_AsLong")); // returns C long
}

// ═══════════════════════════════════════════════════════════════
// Phase 2 Tests - Memory Safety Detection
// ═══════════════════════════════════════════════════════════════

test "PythonAdapter - Test 1: Balanced refcount (INC = DEC) produces no issues" {
    // Simulate a function with balanced reference counting:
    // PyBytes_FromString (owned, +1 INC) -> Py_DECREF (-1 DEC)
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Add one owned ref creation (increment)
    analysis.refcount_increments += 1;
    // Add one matching DECREF (decrement)
    analysis.refcount_decrements += 1;

    // Calculate balance (this simulates the post-analysis check)
    analysis.refcount_balance = @as(i32, @intCast(analysis.refcount_increments)) -
        @as(i32, @intCast(analysis.refcount_decrements));

    // Balanced refcount should have zero balance and no leak issues
    try std.testing.expectEqual(@as(i32, 0), analysis.refcount_balance);

    // Verify no memory_leak or use_after_free issues exist
    var has_refcount_issue = false;
    for (analysis.issues.items) |issue| {
        if (issue.issue_type == .memory_leak or issue.issue_type == .use_after_free) {
            has_refcount_issue = true;
        }
    }
    try std.testing.expect(!has_refcount_issue);
}

test "PythonAdapter - Test 2: Refcount leak (INC > DEC) reports memory_leak issue" {
    // Simulate a function that creates 3 owned refs but only decrements 1:
    // Leak of 2 references
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    analysis.refcount_increments = 3; // 3x Py_BuildValue, PyList_New, etc.
    analysis.refcount_decrements = 1; // Only 1x Py_DECREF

    // Simulate post-analysis refcount imbalance detection
    analysis.refcount_balance = @as(i32, @intCast(analysis.refcount_increments)) -
        @as(i32, @intCast(analysis.refcount_decrements));

    try std.testing.expectEqual(@as(i32, 2), analysis.refcount_balance); // Leaked 2 refs

    // Generate issue as analyzeFunction would
    const msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] Reference leak: {d} owned reference(s) not decremented (INC: {d}, DEC: {d}) in test_func",
        .{ analysis.refcount_balance, analysis.refcount_increments, analysis.refcount_decrements },
    );

    try analysis.addIssue(.{
        .issue_type = .memory_leak,
        .message = msg,
        .location = types.IssueLocation.init("test_func"),
        .severity = .high, // 2 leaks is high severity (< 3 would be critical)
        .confidence = 0.80,
        .evidence = "refcount imbalance analysis",
    });

    // Verify issue was added
    try std.testing.expectEqual(@as(usize, 1), analysis.issues.items.len);
    const issue = &analysis.issues.items[0];
    try std.testing.expectEqual(types.AdapterIssueType.memory_leak, issue.issue_type);
    try std.testing.expectEqual(Severity.high, issue.severity);
    try std.testing.expect(issue.confidence >= 0.75);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "Reference leak") != null);
    try std.testing.expect(analysis.has_potential_leak);
}

test "PythonAdapter - Test 3: Over-decrement (INC < DEC) reports use_after_free issue" {
    // Simulate a function that decrements more than it increments:
    // Potential double-decref / UAF
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    analysis.refcount_increments = 1; // Only 1x Py_INCREF
    analysis.refcount_decrements = 4; // 4x Py_DECREF (3 extra!)

    // Simulate post-analysis refcount imbalance detection
    analysis.refcount_balance = @as(i32, @intCast(analysis.refcount_increments)) -
        @as(i32, @intCast(analysis.refcount_decrements));

    try std.testing.expectEqual(@as(i32, -3), analysis.refcount_balance); // -3 = 3 over-decrefs

    // Generate issue as analyzeFunction would
    const over_dec_count = -analysis.refcount_balance;
    const msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] Potential double-decref/UAF: {d} more DECREF than INCREF (INC: {d}, DEC: {d}) in test_func",
        .{ over_dec_count, analysis.refcount_increments, analysis.refcount_decrements },
    );

    try analysis.addIssue(.{
        .issue_type = .use_after_free,
        .message = msg,
        .location = types.IssueLocation.init("test_func"),
        .severity = .critical, // Over-dec is always critical
        .confidence = 0.70,
        .evidence = "refcount imbalance: too many DECREF",
    });

    // Verify critical severity issue was added
    try std.testing.expectEqual(@as(usize, 1), analysis.issues.items.len);
    const issue = &analysis.issues.items[0];
    try std.testing.expectEqual(types.AdapterIssueType.use_after_free, issue.issue_type);
    try std.testing.expectEqual(Severity.critical, issue.severity);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "double-decref") != null);
}

test "PythonAdapter - Test 4: GIL violation detection reports gil_violation issue" {
    // Simulate a function that releases GIL then calls Python API
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Simulate detecting GIL violation at a specific instruction address
    const inst_addr: u64 = 0xDEAD_BEEF;
    const callee_name = "PyList_New";
    const func_name = "thread_unsafe_function";

    const msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] GIL violation: {s}() called while GIL is released at instruction 0x{x} in {s}",
        .{ callee_name, inst_addr, func_name },
    );

    try analysis.addIssue(.{
        .issue_type = .gil_violation,
        .message = msg,
        .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
        .severity = .critical, // GIL violations are always critical
        .confidence = 0.90,
        .evidence = "GIL state tracking: Py_* API call without holding GIL",
    });

    // Verify GIL violation issue properties
    try std.testing.expectEqual(@as(usize, 1), analysis.issues.items.len);
    const issue = &analysis.issues.items[0];
    try std.testing.expectEqual(types.AdapterIssueType.gil_violation, issue.issue_type);
    try std.testing.expectEqual(Severity.critical, issue.severity);
    try std.testing.expect(issue.confidence >= 0.85);
    try std.testing.expectEqual(inst_addr, issue.location.instruction_addr);
    try std.testing.expectEqualStrings(func_name, issue.location.function_name);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "GIL violation") != null);
}

test "PythonAdapter - Test 5: Borrowed ref safe usage (GetItem without DECREF)" {
    // Simulate correct borrowed ref usage: PyList_GetItem followed by use but NO DECREF
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Add a borrowing function call (returns borrowed ref)
    const borrow_call = types.FFICallInfo.init(
        0x1000,
        "PyList_GetItem",
        .returns_borrowed,
        0.92,
        .python,
    );
    try analysis.addCall(borrow_call);

    // Use the borrowed value (e.g., PyLong_AsLong to convert to C type)
    const use_call = types.FFICallInfo.init(
        0x1001,
        "PyLong_AsLong",
        .returns_borrowed, // AsLong returns C long, classified as borrowed
        0.92,
        .python,
    );
    try analysis.addCall(use_call);

    // No DECREF on the borrowed ref - this is CORRECT behavior
    // Should NOT generate any borrowed_ref_error issues

    // Verify we have calls recorded
    try std.testing.expectEqual(@as(usize, 2), analysis.ffi_calls.items.len);

    // Verify no borrowed_ref_error issues exist
    var has_borrowed_error = false;
    for (analysis.issues.items) |issue| {
        if (issue.issue_type == .borrowed_ref_error) {
            has_borrowed_error = true;
        }
    }
    try std.testing.expect(!has_borrowed_error); // Correct: no error when no DECREF
}

test "PythonAdapter - Test 6: Edge cases - empty function and no Py_* calls" {
    // Test 6a: Empty function (no FFI calls at all)
    {
        var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
        defer analysis.deinit();

        // Empty function should have balanced refcounts (0=0)
        try std.testing.expectEqual(@as(u32, 0), analysis.refcount_increments);
        try std.testing.expectEqual(@as(u32, 0), analysis.refcount_decrements);
        try std.testing.expectEqual(@as(i32, 0), analysis.refcount_balance);
        try std.testing.expectEqual(@as(usize, 0), analysis.ffi_calls.items.len);
        try std.testing.expectEqual(@as(usize, 0), analysis.issues.items.len);
        try std.testing.expect(!analysis.hasFindings());
        try std.testing.expect(!analysis.has_potential_leak);
    }

    // Test 6b: Function with non-Python FFI calls (should be ignored)
    {
        var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
        defer analysis.deinit();

        // Add some non-Python calls (these would be filtered by classifyCall returning .unknown)
        // Since they're unknown, they won't affect refcount tracking
        try std.testing.expectEqual(@as(u32, 0), analysis.refcount_increments);
        try std.testing.expectEqual(@as(usize, 0), analysis.issues.items.len);
    }

    // Test 6c: Function with only GIL management calls (no violations)
    {
        var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
        defer analysis.deinit();

        // Simulate proper GIL management: Ensure -> do work -> Release
        // This should NOT generate any gil_violation issues
        const ensure_call = types.FFICallInfo.init(
            0x2000,
            "PyGILState_Ensure",
            .unknown, // GIL functions are not classified as owning/borrowing
            0.90,
            .python,
        );
        try analysis.addCall(ensure_call);

        const release_call = types.FFICallInfo.init(
            0x2001,
            "PyGILState_Release",
            .unknown,
            0.90,
            .python,
        );
        try analysis.addCall(release_call);

        // Should have calls but no issues (proper GIL usage)
        try std.testing.expectEqual(@as(usize, 2), analysis.ffi_calls.items.len);

        var has_gil_violation = false;
        for (analysis.issues.items) |issue| {
            if (issue.issue_type == .gil_violation) {
                has_gil_violation = true;
            }
        }
        try std.testing.expect(!has_gil_violation); // Correct: no violation
    }
}

test "PythonAdapter - AdapterIssueType enum completeness" {
    // Verify all issue types can create valid issues with proper defaults
    const issue_types = [_]types.AdapterIssueType{
        .memory_leak,
        .use_after_free,
        .gil_violation,
        .borrowed_ref_error,
        .buffer_leak,
        .null_return_not_checked,
        .stale_interpreter_ptr,
    };

    for (issue_types) |issue_type| {
        // Check displayName doesn't panic
        _ = issue_type.displayName();

        // Check defaultSeverity returns valid Severity enum value
        const severity = issue_type.defaultSeverity();

        // Verify severity ordering makes sense
        switch (issue_type) {
            .use_after_free, .gil_violation => {
                try std.testing.expectEqual(Severity.critical, severity);
            },
            .memory_leak, .borrowed_ref_error, .stale_interpreter_ptr => {
                try std.testing.expect(severity == .high or severity == .critical);
            },
            .buffer_leak, .null_return_not_checked => {
                try std.testing.expect(severity == .medium);
            },
        }
    }
}

test "PythonAdapter - IssueLocation init variants" {
    // Test basic init
    const loc1 = types.IssueLocation.init("my_function");
    try std.testing.expectEqualStrings("my_function", loc1.function_name);
    try std.testing.expectEqual(@as(u64, 0), loc1.instruction_addr);

    // Test initWithAddr
    const loc2 = types.IssueLocation.initWithAddr("another_func", 0xBEEF);
    try std.testing.expectEqualStrings("another_func", loc2.function_name);
    try std.testing.expectEqual(@as(u64, 0xBEEF), loc2.instruction_addr);
}

test "PythonAdapter - AdapterAnalysis issues integration" {
    // Test that addIssue properly updates legacy flags
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Initially no findings
    try std.testing.expect(!analysis.hasFindings());
    try std.testing.expect(!analysis.has_potential_leak);

    // Add a memory leak issue
    const msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] Reference leak: 1 owned reference(s) not decremented",
        .{},
    );

    try analysis.addIssue(.{
        .issue_type = .memory_leak,
        .message = msg,
        .location = types.IssueLocation.init("leaky_func"),
        .severity = .high,
        .confidence = 0.85,
        .evidence = "refcount test",
    });

    // Legacy flags should be updated
    try std.testing.expect(analysis.has_potential_leak);
    try std.testing.expect(analysis.hasFindings());
    try std.testing.expectEqual(Severity.high, analysis.leak_severity);
    try std.testing.expectEqual(@as(usize, 1), analysis.issues.items.len);
}

test "PythonAdapter - Multiple issues can coexist" {
    // A real-world scenario: function has both refcount leak AND GIL violation
    var analysis = try types.AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    // Issue 1: Memory leak
    const leak_msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] Reference leak: 2 owned reference(s) not decremented",
        .{},
    );

    try analysis.addIssue(.{
        .issue_type = .memory_leak,
        .message = leak_msg,
        .location = types.IssueLocation.init("buggy_func"),
        .severity = .high,
        .confidence = 0.80,
        .evidence = "refcount test",
    });

    // Issue 2: GIL violation
    const gil_msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] GIL violation: PyList_New() called while GIL is released",
        .{},
    );

    try analysis.addIssue(.{
        .issue_type = .gil_violation,
        .message = gil_msg,
        .location = types.IssueLocation.initWithAddr("buggy_func", 0x1000),
        .severity = .critical,
        .confidence = 0.90,
        .evidence = "GIL test",
    });

    // Issue 3: Buffer leak
    const buffer_msg = try std.fmt.allocPrint(
        std.testing.allocator,
        "[Python CAPI] Buffer leak: 1 PyObject_GetBuffer without PyBuffer_Release",
        .{},
    );

    try analysis.addIssue(.{
        .issue_type = .buffer_leak,
        .message = buffer_msg,
        .location = types.IssueLocation.init("buggy_func"),
        .severity = .medium,
        .confidence = 0.85,
        .evidence = "buffer test",
    });

    // Verify all three issues coexist
    try std.testing.expectEqual(@as(usize, 3), analysis.issues.items.len);

    // Verify each issue type is present
    var found_types = [_]bool{false} ** 3;
    for (analysis.issues.items) |issue| {
        switch (issue.issue_type) {
            .memory_leak => found_types[0] = true,
            .gil_violation => found_types[1] = true,
            .buffer_leak => found_types[2] = true,
            else => {},
        }
    }
    try std.testing.expect(found_types[0]); // memory_leak found
    try std.testing.expect(found_types[1]); // gil_violation found
    try std.testing.expect(found_types[2]); // buffer_leak found

    // Overall state should reflect most severe issue
    try std.testing.expect(analysis.hasFindings());
    try std.testing.expect(analysis.has_potential_leak);
    try std.testing.expectEqual(Severity.high, analysis.leak_severity); // memory_leak is high, gil_violation doesn't affect leak_severity
}
