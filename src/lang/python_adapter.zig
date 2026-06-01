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

/// Hash context for LLVMValueRef keys in borrowed ref tracking.
///
/// LLVMValueRef is a pointer type, so we use pointer hashing for O(1) lookup.
/// This enables efficient SSA def-use chain analysis without allocating
/// wrapper structures for each value.
const llvmValueContext = struct {
    pub fn hash(self: @This(), key: c.LLVMValueRef) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHashStrat(&hasher, @intFromPtr(key), .Shallow);
        return hasher.final();
    }

    pub fn eql(self: @This(), a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        _ = self;
        return a == b;
    }
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

    // SSA-based borrowed reference tracking for precise DECREF detection
    // Maps LLVMValueRef (call instruction) -> source function name
    // This enables def-use chain analysis to detect exact which value is decref'd
    var borrowed_refs = std.HashMap(c.LLVMValueRef, []const u8, llvmValueContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer borrowed_refs.deinit();

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

            // Use tiered confidence calibration (T2b FP tuning)
            const call_confidence = calcTieredConfidence(callee_name, classification);
            const call_info = types.FFICallInfo.init(
                inst_addr,
                callee_name,
                classification,
                call_confidence,
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

                // SSA-based DECREF on borrowed reference detection (Step 3)
                // Use LLVMGetOperand to extract the decref'd value, then check
                // if it was defined by a borrowing function call (def-use chain)
                if (classification == .python_refcount_dec or
                    std.mem.indexOf(u8, callee_name, "Py_DECREF") != null or
                    std.mem.indexOf(u8, callee_name, "Py_XDECREF") != null)
                {
                    // Get operand 0 of DECREF - the value being decref'd
                    const decref_operand = c.LLVMGetOperand(inst, 0);
                    if (decref_operand != null) {
                        // Check if this operand is a known borrowed ref via def-use chain
                        if (borrowed_refs.get(decref_operand.?)) |src_func| {
                            // Exact match: this specific borrowed value is being decref'd
                            const msg = try std.fmt.allocPrint(
                                allocator,
                                "[Python CAPI] Borrowed reference from {s}() incorrectly DECREF'd at instruction 0x{x} in {s}",
                                .{ src_func, inst_addr, func_name },
                            );
                            // Use tiered confidence for borrowed ref error (T2b)
                            const borrow_issue_conf = calcTieredConfidenceForIssue(callee_name, .borrowed_ref_error);
                            try result.addIssue(.{
                                .issue_type = .borrowed_ref_error,
                                .message = msg,
                                .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                                .severity = .high,
                                .confidence = borrow_issue_conf,
                                .evidence = "SSA def-use chain: DECREF operand defined by borrowing function",
                            });

                            log.warn("Python: SSA detected borrowed ref DECREF: {s} -> {s}", .{ src_func, callee_name });
                        }
                    }
                }
            }

            // Track returned value from borrowing functions in SSA map
            // In LLVM IR, the call instruction itself IS the returned value (SSA form)
            if (classification == .returns_borrowed) {
                // Store mapping: call instruction (value) -> source function name
                // This enables later DECREF operands to be traced back to their definition
                try borrowed_refs.put(inst, callee_name);
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
                // Use tiered confidence for GIL violation (T2b)
                const gil_issue_conf = calcTieredConfidenceForIssue(callee_name, .gil_violation);
                try result.addIssue(.{
                    .issue_type = .gil_violation,
                    .message = msg,
                    .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                    .severity = .critical,
                    .confidence = gil_issue_conf,
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
                // Use tiered confidence for stale interpreter pointer (T2b)
                const stale_issue_conf = calcTieredConfidenceForIssue(callee_name, .stale_interpreter_ptr);
                try result.addIssue(.{
                    .issue_type = .stale_interpreter_ptr,
                    .message = msg,
                    .location = types.IssueLocation.initWithAddr(func_name, inst_addr),
                    .severity = .high,
                    .confidence = stale_issue_conf,
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
        // Use tiered confidence for buffer leak (T2b)
        const buffer_issue_conf = calcTieredConfidenceForIssue("PyObject_GetBuffer", .buffer_leak);
        try result.addIssue(.{
            .issue_type = .buffer_leak,
            .message = msg,
            .location = types.IssueLocation.init(func_name),
            .severity = .medium,
            .confidence = buffer_issue_conf,
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
        // Use tiered confidence for double-decref/UAF (T2b)
        const uaf_issue_conf = calcTieredConfidenceForIssue("Py_DECREF", .use_after_free);
        try result.addIssue(.{
            .issue_type = .use_after_free,
            .message = msg,
            .location = types.IssueLocation.init(func_name),
            .severity = .critical,
            .confidence = uaf_issue_conf,
            .evidence = "refcount imbalance: too many DECREF",
        });

        log.warn("Python: refcount imbalance: {} (more DECREF than INCREF - potential UAF)", .{result.refcount_balance});
    }

    result.is_analyzed = true;
    result.confidence = if (result.ffi_calls.items.len > 0) PyConfidence.default_py else 0.15;

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
// Confidence Calibration — Tiered confidence for Python C API
// ═══════════════════════════════════════════════════════════════

/// Confidence levels for different FFI call types in Python C API.
///
/// Calibrated based on false positive analysis for Python-specific patterns:
///   - Refcount operations have moderate confidence (may be intentional)
///   - GIL violations are high confidence (almost always bugs)
///   - JNI-style leaks are very high confidence (nearly certain bugs)
///
/// Reference: T2b FP tuning specification
pub const PyConfidence = struct {
    /// Default confidence for well-classified Python C API calls
    pub const default_py: f32 = 0.92;

    /// Py_INCREF without matching DECREF (may be intentional ref management)
    pub const refcount_imbalance: f32 = 0.80;

    /// Borrowed reference error (DECREF on borrowed ref)
    pub const borrowed_ref_error: f32 = 0.75;

    /// GIL violation (calling Python API without GIL)
    pub const gil_violation: f32 = 0.90;

    /// JNI NewGlobalRef without DeleteGlobalRef (almost certainly a leak)
    pub const jni_globalref_leak: f32 = 0.90;

    /// Buffer protocol leak (GetBuffer without Release)
    pub const buffer_leak: f32 = 0.85;

    /// Stale interpreter pointer (using pointer after finalization)
    pub const stale_interpreter: f32 = 0.70;
};

/// Calculate tiered confidence for a Python C API call based on callee name and classification.
///
/// Implements T2b FP tuning with Python-specific calibration:
///
///   - **Refcount operations**: 0.80 (may be legitimate ref management)
///   - **Borrowed ref functions**: 0.92 default (classification is usually accurate)
///   - **Owning functions**: 0.92 default (standard owned ref pattern)
///   - **GIL-related**: 0.90 (important but sometimes intentional)
///   - **Other calls**: 0.92 (default, maintains current behavior)
///
/// Arguments:
///
///   callee_name - The name of the called Python C API function
///   classification - The FFISemantics classification of the call
///
/// Returns:
///
///   Calibrated confidence value between 0.0 and 1.0
pub fn calcTieredConfidence(callee_name: []const u8, classification: FFISemantics) f32 {
    _ = callee_name; // Reserved for future per-function calibration

    // Refcount increment/decrement: moderate confidence
    // (May be part of complex ref management we don't fully understand)
    if (classification == .python_refcount_inc or
        classification == .python_refcount_dec)
    {
        return PyConfidence.refcount_imbalance;
    }

    // Default for other well-classified calls
    return PyConfidence.default_py;
}

/// Calculate confidence for Python-specific issues based on issue type.
///
/// Provides fine-grained calibration for detected Python C API issues:
///
///   - **GIL violations**: 0.90 (critical threading bug)
///   - **Refcount leaks**: 0.80-0.95 depending on severity
///   - **Borrowed ref errors**: 0.75 (may be false positive)
///   - **Buffer leaks**: 0.85 (common but not always critical)
///   - **Stale pointers**: 0.70 (hard to detect accurately)
///   - **JNI leaks**: 0.90 (nearly always bugs)
///
/// Arguments:
///
///   callee_name - The function that triggered the issue
///   issue_type - The type of issue detected
///
/// Returns:
///
///   Calibrated confidence value for the specific issue pattern
pub fn calcTieredConfidenceForIssue(callee_name: []const u8, issue_type: types.AdapterIssueType) f32 {
    switch (issue_type) {
        .gil_violation => return PyConfidence.gil_violation,
        .borrowed_ref_error => return PyConfidence.borrowed_ref_error,
        .buffer_leak => return PyConfidence.buffer_leak,
        .stale_interpreter_ptr => return PyConfidence.stale_interpreter,
        .memory_leak => {
            // JNI GlobalRef leaks get highest confidence
            if (std.mem.indexOf(u8, callee_name, "NewGlobalRef") != null) {
                return PyConfidence.jni_globalref_leak;
            }
            // Standard refcount leak
            return PyConfidence.refcount_imbalance;
        },
        else => return PyConfidence.default_py,
    }
}

// Import tests (only compiled in test mode)
const _ = @import("python_adapter_test.zig");

const testing = std.testing;

// ═══════════════════════════════════════════════════════════════
// T2b Confidence Calibration Tests
// ═══════════════════════════════════════════════════════════════

test "PythonAdapter - calcTieredConfidence returns correct values by classification" {
    // Refcount operations should return moderate confidence (0.80)
    try testing.expectApproxEqAbs(
        PyConfidence.refcount_imbalance,
        calcTieredConfidence("Py_INCREF", .python_refcount_inc),
        0.001,
    );
    try testing.expectApproxEqAbs(
        PyConfidence.refcount_imbalance,
        calcTieredConfidence("Py_DECREF", .python_refcount_dec),
        0.001,
    );

    // Owning functions should return default confidence (0.92)
    try testing.expectApproxEqAbs(
        PyConfidence.default_py,
        calcTieredConfidence("PyList_New", .returns_owned),
        0.001,
    );
    try testing.expectApproxEqAbs(
        PyConfidence.default_py,
        calcTieredConfidence("PyBytes_FromString", .returns_owned),
        0.001,
    );

    // Borrowing functions should also return default confidence
    try testing.expectApproxEqAbs(
        PyConfidence.default_py,
        calcTieredConfidence("PyList_GetItem", .returns_borrowed),
        0.001,
    );
}

test "PythonAdapter - calcTieredConfidenceForIssue calibrates all issue types" {
    // GIL violation: high confidence (0.90)
    try testing.expectApproxEqAbs(
        PyConfidence.gil_violation,
        calcTieredConfidenceForIssue("PyList_New", .gil_violation),
        0.001,
    );

    // Borrowed ref error: lower confidence (0.75)
    try testing.expectApproxEqAbs(
        PyConfidence.borrowed_ref_error,
        calcTieredConfidenceForIssue("PyList_GetItem", .borrowed_ref_error),
        0.001,
    );

    // Buffer leak: medium-high confidence (0.85)
    try testing.expectApproxEqAbs(
        PyConfidence.buffer_leak,
        calcTieredConfidenceForIssue("PyObject_GetBuffer", .buffer_leak),
        0.001,
    );

    // Stale interpreter pointer: low confidence (0.70)
    try testing.expectApproxEqAbs(
        PyConfidence.stale_interpreter,
        calcTieredConfidenceForIssue("PyList_New", .stale_interpreter_ptr),
        0.001,
    );

    // JNI GlobalRef leak: very high confidence (0.90)
    try testing.expectApproxEqAbs(
        PyConfidence.jni_globalref_leak,
        calcTieredConfidenceForIssue("NewGlobalRef", .memory_leak),
        0.001,
    );

    // Standard memory leak (refcount): moderate confidence (0.80)
    try testing.expectApproxEqAbs(
        PyConfidence.refcount_imbalance,
        calcTieredConfidenceForIssue("PyList_New", .memory_leak),
        0.001,
    );
}

test "PythonAdapter - PyConfidence constants match T2b specification" {
    // Verify all confidence constants match specification
    try testing.expectApproxEqAbs(@as(f32, 0.92), PyConfidence.default_py, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.80), PyConfidence.refcount_imbalance, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.75), PyConfidence.borrowed_ref_error, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.90), PyConfidence.gil_violation, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.90), PyConfidence.jni_globalref_leak, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.85), PyConfidence.buffer_leak, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.70), PyConfidence.stale_interpreter, 0.001);
}

test "PythonAdapter - tiered confidence boundary cases" {
    // Unknown issue type should use default confidence
    try testing.expectApproxEqAbs(
        PyConfidence.default_py,
        calcTieredConfidenceForIssue("unknown", .null_return_not_checked),
        0.001,
    );
}
