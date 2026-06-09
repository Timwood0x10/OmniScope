//! Builtin Summary Initialization — Populates SummaryStore with known function semantics.
//!
//! Auto-generates summaries from ResourceFamilyRegistry entries and adds
//! language-specific patterns (Python owned-ref constructors, JNI refs, etc.).
//!
//! All heavy passes share these summaries instead of independently guessing
//! callee semantics from function names.

const std = @import("std");

const effect = @import("effect.zig");
pub const Effect = effect.Effect;
pub const EffectSet = effect.EffectSet;
pub const SummarySource = effect.SummarySource;

const func_summary = @import("function_summary.zig");
pub const SummaryStore = func_summary.SummaryStore;
pub const ResourceFunctionSummary = func_summary.ResourceFunctionSummary;

const family = @import("family.zig");
pub const FamilyId = family.FamilyId;

const registry_mod = @import("family_registry.zig");
const ResourceFamilyRegistry = registry_mod.ResourceFamilyRegistry;

// ============================================================================
// Public API
// ============================================================================

/// Populate a SummaryStore with all builtin function summaries.
/// Call this once during pipeline initialization, before any analysis pass runs.
pub fn initBuiltinSummaries(store: *SummaryStore, family_reg: *ResourceFamilyRegistry) !void {
    _ = family_reg;
    // Layer 1: Auto-generate from family registry
    try populateFromRegistry(store);

    // Layer 2: Python owned-reference constructors
    try populatePythonOwnedConstructors(store);

    // Layer 3: Python conditional release
    try populatePythonConditionalRelease(store);

    // Layer 4: JNI reference API
    try populateJNISummaries(store);

    // Layer 5: C#/.NET interop
    try populateCSharpSummaries(store);

    // Layer 6: Bridge helpers
    try populateBridgeHelpers(store);
}

/// Helper: register a single acquirer summary.
fn regAcquire(store: *SummaryStore, name: []const u8, fam: FamilyId) !void {
    try store.register(name, .builtin_registry, 1.0);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.acquires);
        e.summary.family = fam;
    }
}

/// Helper: register a single releaser summary.
fn regRelease(store: *SummaryStore, name: []const u8, fam: FamilyId, param_idx: u8) !void {
    try store.register(name, .builtin_registry, 1.0);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.releases);
        e.summary.family = fam;
        e.summary.target_param_index = param_idx;
    }
}

/// Helper: register a retain summary.
fn regRetain(store: *SummaryStore, name: []const u8, src: SummarySource, conf: f32) !void {
    try store.register(name, src, conf);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.retains);
    }
}

/// Helper: register a returns_owned summary.
fn regReturnsOwned(store: *SummaryStore, name: []const u8, fam: FamilyId, conf: f32, ev: []const u8) !void {
    try store.register(name, .builtin_registry, conf);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.returns_owned);
        e.summary.family = fam;
        e.summary.evidence = ev;
    }
}

/// Helper: register a conditional_release summary.
fn regConditionalRelease(store: *SummaryStore, name: []const u8, fam: FamilyId, param_idx: u8, ev: []const u8) !void {
    try store.register(name, .builtin_registry, 1.0);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.conditional_release);
        e.summary.family = fam;
        e.summary.target_param_index = param_idx;
        e.summary.evidence = ev;
    }
}

/// Helper: register a returns_borrowed summary.
fn regReturnsBorrowed(store: *SummaryStore, name: []const u8, src: SummarySource, conf: f32, ev: []const u8) !void {
    try store.register(name, src, conf);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.returns_borrowed);
        e.summary.evidence = ev;
    }
}

/// Helper: register a consumes_arg summary.
fn regConsumesArg(store: *SummaryStore, name: []const u8, param_idx: u8) !void {
    try store.register(name, .fallback_heuristic, 0.7);
    if (store.entries.getPtr(name)) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.consumes_arg);
        e.summary.target_param_index = param_idx;
        e.summary.evidence = "Ownership consumer: takes responsibility for freeing argument";
    }
}

// ============================================================================
// Layer 1: Auto-generate from Family Registry
// ============================================================================

fn populateFromRegistry(store: *SummaryStore) !void {
    // --- C heap ---
    for (&[_][]const u8{ "malloc", "calloc", "realloc", "reallocarray", "valloc", "pvalloc", "aligned_alloc", "memalign", "posix_memalign" }) |n| {
        try regAcquire(store, n, .c_heap);
    }
    try regRelease(store, "free", .c_heap, 0);

    // --- C mmap ---
    try regAcquire(store, "mmap", .c_mmap);
    try regRelease(store, "munmap", .c_mmap, 0);

    // --- C++ new scalar ---
    for (&[_][]const u8{ "_Znwm", "_Znwj", "_ZnwmSt11align_val_t", "operator new", "operator new(unsigned long)" }) |n| {
        try regAcquire(store, n, .cpp_new_scalar);
    }
    for (&[_][]const u8{ "_ZdlPv", "_ZdlPvj", "_ZdlPvSt11align_val_t", "operator delete" }) |n| {
        try regRelease(store, n, .cpp_new_scalar, 0);
    }

    // --- C++ new array ---
    for (&[_][]const u8{ "_Znam", "_Znaj", "_ZnamSt11align_val_t", "operator new[]" }) |n| {
        try regAcquire(store, n, .cpp_new_array);
    }
    for (&[_][]const u8{ "_ZdaPv", "_ZdaPvj", "_ZdaPvSt11align_val_t", "operator delete[]" }) |n| {
        try regRelease(store, n, .cpp_new_array, 0);
    }

    // --- Rust global allocator ---
    for (&[_][]const u8{ "__rust_alloc", "__rust_alloc_zeroed", "__rust_realloc" }) |n| {
        try regAcquire(store, n, .rust_global);
    }
    try regRelease(store, "__rust_dealloc", .rust_global, 0);

    // --- Python object ---
    for (&[_][]const u8{ "PyObject_New", "PyObject_NewVar", "PyType_GenericAlloc", "_PyObject_New", "_PyObject_NewVar" }) |n| {
        try regReturnsOwned(store, n, .python_object, 1.0, "Python object allocator");
    }
    for (&[_][]const u8{ "PyObject_Del", "PyObject_Free", "_PyObject_Del" }) |n| {
        try regRelease(store, n, .python_object, 0);
    }

    // --- Python mem ---
    for (&[_][]const u8{ "PyMem_Malloc", "PyMem_Calloc", "PyMem_Realloc" }) |n| {
        try regAcquire(store, n, .python_mem);
    }
    try regRelease(store, "PyMem_Free", .python_mem, 0);

    // --- Python raw mem ---
    for (&[_][]const u8{ "PyMem_RawMalloc", "PyMem_RawCalloc", "PyMem_RawRealloc" }) |n| {
        try regAcquire(store, n, .python_mem_raw);
    }
    try regRelease(store, "PyMem_RawFree", .python_mem_raw, 0);

    // --- JNI references ---
    try regRetain(store, "NewLocalRef", .builtin_registry, 1.0);
    try regRelease(store, "DeleteLocalRef", .java_local_ref, 0);
    try regRetain(store, "NewGlobalRef", .builtin_registry, 1.0);
    try regRelease(store, "DeleteGlobalRef", .java_global_ref, 0);

    // --- C# interop ---
    try regAcquire(store, "Marshal.AllocHGlobal", .csharp_hglobal);
    try regRelease(store, "Marshal.FreeHGlobal", .csharp_hglobal, 0);
    try regAcquire(store, "CoTaskMemAlloc", .csharp_cotask);
    try regRelease(store, "CoTaskMemFree", .csharp_cotask, 0);

    // --- Go GC ---
    try regAcquire(store, "runtime.mallocgc", .go_gc);

    // --- Retains ---
    for (&[_]struct { []const u8, SummarySource, f32 }{
        .{ "Py_INCREF", .builtin_registry, 1.0 },
        .{ "Py_XINCREF", .builtin_registry, 1.0 },
        .{ "PyList_SetItem", .builtin_registry, 1.0 },
        .{ "PyDict_SetItem", .builtin_registry, 1.0 },
        .{ "PyTuple_SetItem", .builtin_registry, 1.0 },
        .{ "PySet_Add", .builtin_registry, 1.0 },
        .{ "CFRetain", .fallback_heuristic, 0.7 },
        .{ "IUnknown_AddRef", .fallback_heuristic, 0.7 },
        .{ "objc_retain", .fallback_heuristic, 0.7 },
    }) |entry| {
        try regRetain(store, entry[0], entry[1], entry[2]);
    }
}

// ============================================================================
// Layer 2: Python owned-reference constructors
// ============================================================================

fn populatePythonOwnedConstructors(store: *SummaryStore) !void {
    // Py*_From* / Py*_New → returns_owned(python_object)
    const int_constructors = &[_][]const u8{
        "PyLong_FromLong",     "PyLong_FromUnsignedLong",
        "PyLong_FromLongLong", "PyLong_FromUnsignedLongLong",
        "PyLong_FromString",   "PyLong_FromUnicode",
        "PyLong_FromVoidPtr",  "PyLong_FromSize_t",
        "PyInt_FromLong",      "PyInt_FromString",
    };
    for (int_constructors.*) |n| {
        try regReturnsOwned(store, n, .python_object, 0.95, "Python integer constructor: returns owned ref");
    }

    const str_constructors = &[_][]const u8{
        "PyUnicode_FromString", "PyUnicode_FromAndSize",
        "PyUnicode_Decode",     "PyUnicode_DecodeUTF8",
        "PyBytes_FromString",   "PyBytes_FromAndSize",
        "PyBytes_FromObject",   "PyByteArrayFromString",
    };
    for (str_constructors.*) |n| {
        try regReturnsOwned(store, n, .python_object, 0.95, "Python string/bytes constructor: returns owned ref");
    }

    const container_constructors = &[_][]const u8{
        "PyTuple_New",     "PyList_New",
        "PyDict_New",      "PySet_New",
        "PyFrozenSet_New", "PyDict_Copy",
    };
    for (container_constructors.*) |n| {
        try regReturnsOwned(store, n, .python_object, 0.95, "Python container constructor: returns owned ref");
    }

    const obj_constructors = &[_][]const u8{
        "PyObject_Call",       "PyObject_CallFunction",
        "PyObject_CallMethod", "PyObject_Str",
        "PyObject_Repr",       "PyObject_Dir",
        "PyType_GenericAlloc", "PyInstance_NewRaw",
    };
    for (obj_constructors.*) |n| {
        try regReturnsOwned(store, n, .python_object, 0.9, "Python object constructor: returns owned ref");
    }
}

// ============================================================================
// Layer 3: Python conditional release
// ============================================================================

fn populatePythonConditionalRelease(store: *SummaryStore) !void {
    try regConditionalRelease(store, "Py_DECREF", .python_object, 0, "Conditional release: decrements refcount, frees only if refcount→0");
    try regConditionalRelease(store, "Py_XDECREF", .python_object, 0, "Conditional release: decrements refcount (accepts NULL), frees only if refcount→0");
    try regConditionalRelease(store, "Py_CLEAR", .python_object, 0, "Conditional release: decrements refcount + sets ptr to NULL");

    try store.register("Arc::drop", .fallback_heuristic, 0.75);
    if (store.entries.getPtr("Arc::drop")) |raw_e| {
        var e = raw_e;
        e.summary.effects.add(.conditional_release);
        e.summary.evidence = "Rust Arc::drop: conditional release via refcount";
    }
}

// ============================================================================
// Layer 4: JNI Reference API
// ============================================================================

fn populateJNISummaries(store: *SummaryStore) !void {
    try regRetain(store, "JNIEnv_NewLocalRef", .builtin_registry, 1.0);
    try regRelease(store, "JNIEnv_DeleteLocalRef", .java_local_ref, 0);
    try regRetain(store, "JNIEnv_NewGlobalRef", .builtin_registry, 1.0);
    try regRelease(store, "JNIEnv_DeleteGlobalRef", .java_global_ref, 0);

    try regReturnsOwned(store, "FindClass", .java_local_ref, 0.95, "JNI FindClass: returns local ref that must be DeleteLocalRef'd");
}

// ============================================================================
// Layer 5: C#/.NET Interop
// ============================================================================

fn populateCSharpSummaries(store: *SummaryStore) !void {
    for (&[_][]const u8{
        "Marshal.StringToHGlobalAnsi",  "Marshal.StringToHGlobalUni",
        "Marshal.StringToHGlobalAuto",  "Marshal.StringToCoTaskMemAnsi",
        "Marshal.StringToCoTaskMemUni", "Marshal.StringToBSTR",
    }) |n| {
        try regReturnsOwned(store, n, .csharp_hglobal, 0.95, "C# marshal string allocation: returns native memory to free");
    }

    try regReturnsOwned(store, "Marshal.SecureStringToHGlobalAnsi", .csharp_hglobal, 0.9, "Secure string marshal: uses different cleanup than normal HGlobal");
}

// ============================================================================
// Layer 6: Bridge Helpers (slice-to-ptr, borrow patterns)
// ============================================================================

fn populateBridgeHelpers(store: *SummaryStore) !void {
    // Returns borrowed pointers into existing data — caller must NOT free
    const borrowed_high = &[_][]const u8{
        "slice.ptr",  "slice.as_ptr",   "slice.as_mut_ptr",
        "Vec.as_ptr", "Vec.as_mut_ptr", "str.as_ptr",
        "ptr_cast",   "@ptrCast",
    };
    for (borrowed_high.*) |n| {
        try regReturnsBorrowed(store, n, .structural_inference, 0.85, "Bridge helper: returns borrowed pointer into existing data");
    }

    const borrowed_low = &[_][]const u8{
        "get_pointer", "data", "c_str", "as_ptr", "as_mut_ptr",
    };
    for (borrowed_low.*) |n| {
        try regReturnsBorrowed(store, n, .fallback_heuristic, 0.6, "Bridge helper: likely returns borrowed pointer");
    }

    // Ownership consumers
    for (&[_][]const u8{
        "cJSON_Delete", "xmlFreeDoc",      "xmlFreeNode",
        "g_free",       "g_slice_free1",   "g_hash_table_destroy",
        "json_decref",  "json_object_put",
    }) |n| {
        try regConsumesArg(store, n, 0);
    }
}

// ============================================================================
// Phase 5: Structural Pattern Inference (replaces issue suppression)
//
// Instead of post-hoc suppressing false positives in issue_suppression.zig,
// we infer function summaries from structural IR patterns BEFORE any pass runs.
// This means passes never generate FPs in the first place.
//
// Each infer* function returns a list of inferred summaries that should be
// registered into the SummaryStore during pipeline initialization.
// ============================================================================

/// Result of structural pattern inference on a single function.
pub const InferredSummary = struct {
    /// Canonical function name that was inferred.
    name: []const u8,
    /// Which pattern matched (for evidence trail).
    pattern: InferencePattern,
    /// Confidence in this inference [0.0, 1.0].
    confidence: f32,
    /// Effects to register.
    effects: EffectSet = EffectSet.empty,
    /// Family if applicable.
    family: ?FamilyId = null,
    /// Target parameter index for consumes/releases.
    target_param: ?u8 = null,
    /// Human-readable explanation.
    evidence: []const u8,

    pub const InferencePattern = enum(u8) {
        /// Function name matches known destructor naming convention.
        destructor_name,
        /// Function body contains only GEP/bitcast/extractvalue/return (bridge helper).
        bridge_helper_body,
        /// Function performs atomic refcount decrement + conditional branch.
        refcount_release_shape,
        /// Resource stored into global/static variable with process lifetime.
        static_lifetime_sink,
        /// Same-family alloc+release pair confirmed by registry lookup.
        same_family_release,
    };
};

/// Run all structural pattern inference on a candidate function.
/// Returns an inferred summary if any pattern matches, null otherwise.
///
/// This function is designed to be called per-function during pipeline init,
/// AFTER builtin summaries are loaded (so we can check for conflicts).
pub fn inferFunctionSummary(
    store: *SummaryStore,
    func_name: []const u8,
) !?InferredSummary {
    // Try each pattern in priority order (highest confidence first)

    // 1. Destructor/Drop/Dispose name pattern (high confidence)
    if (try inferDestructorLikeSummary(store, func_name)) |summary| {
        return summary;
    }

    // 2. Bridge helper body pattern
    if (try inferBridgeHelperSummary(func_name)) |summary| {
        return summary;
    }

    // 3. Refcount release shape
    if (try inferRefcountReleaseSummary(store, func_name)) |summary| {
        return summary;
    }

    // 4. Static lifetime sink
    if (try inferStaticLifetimeSink(func_name)) |summary| {
        return summary;
    }

    return null;
}

// ============================================================================
// 5.1 Destructor / Drop / Dispose Pattern
// ============================================================================

/// Known destructor-like name prefixes/suffixes/patterns.
/// Matches: drop, destroy, dealloc, delete, free, Dispose, finalize,
/// __del__, C++ D0Ev/D1Ev/D2Ev, cleanup, release, close.
const destructor_patterns = [_]struct { []const u8, bool }{
    // (pattern, is_suffix)
    .{ "drop", true },
    .{ "Drop", true }, // Rust Drop trait impl
    .{ "destroy", true },
    .{ "Destroy", true },
    .{ "dealloc", true },
    .{ "Dealloc", true },
    .{ "delete", true },
    .{ "Delete", true },
    .{ "free", true },
    .{ "Free", true },
    .{ "Dispose", true },
    .{ "dispose", true },
    .{ "finalize", true },
    .{ "Finalize", true },
    .{ "__del__", false }, // Python special method
    .{ "__dealloc__", false }, // Python special method
    .{ "cleanup", true },
    .{ "Cleanup", true },
    .{ "release", true },
    .{ "Release", true },
    .{ "close", true },
    .{ "Close", true },
    // C++ Itanium destructor mangling
    .{ "D0ev", true }, // complete object destructor
    .{ "D1ev", true }, // base object destructor
    .{ "D2ev", true }, // deleting destructor
    .{ "D0Ev", true },
    .{ "D1Ev", true },
    .{ "D2Ev", true },
    // Rust-specific
    .{ "drop_in_place", false },
    .{ "__rust_dealloc", false },
    // Objective-C
    .{ "dealloc", false }, // NSObject subclass
};

/// Infer that a function is a destructor-like resource consumer.
/// Replaces Pattern A (Rust Drop Chain) in issue_suppression.zig.
///
/// When a function matches destructor patterns AND takes a pointer argument,
/// it's classified as `consumes_arg + releases` rather than generating
/// false-positive leak reports when it calls __rust_dealloc internally.
pub fn inferDestructorLikeSummary(
    store: *SummaryStore,
    func_name: []const u8,
) !?InferredSummary {
    _ = store;

    var matched_pattern: ?[]const u8 = null;
    var confidence: f32 = 0.6; // default medium confidence for name-only match

    for (destructor_patterns) |entry| {
        const pattern = entry[0];
        const is_suffix = entry[1];

        const match_found = if (is_suffix)
            endsWithIgnoreCase(func_name, pattern)
        else
            std.mem.indexOf(u8, func_name, pattern) != null;

        if (match_found) {
            matched_pattern = pattern;
            // Boost confidence for exact or high-signal patterns
            if (std.mem.eql(u8, func_name, pattern) or
                std.mem.eql(u8, func_name, "__rust_dealloc") or
                std.mem.eql(u8, func_name, "drop_in_place"))
            {
                confidence = 0.95;
            } else if (startsWith(pattern, "D") and
                (std.mem.eql(u8, pattern, "D0ev") or
                    std.mem.eql(u8, pattern, "D1ev") or
                    std.mem.eql(u8, pattern, "D2ev") or
                    std.mem.eql(u8, pattern, "D0Ev") or
                    std.mem.eql(u8, pattern, "D1Ev") or
                    std.mem.eql(u8, pattern, "D2Ev")))
            {
                confidence = 0.92; // C++ destructor mangling is very reliable
            } else if (indexOfIgnoreCase(func_name, "Drop") != null or
                indexOfIgnoreCase(func_name, "drop_in_place") != null)
            {
                confidence = 0.9; // Rust Drop is well-defined
            }
            break;
        }
    }

    if (matched_pattern == null) return null;

    var effects = EffectSet.empty;
    effects.add(.consumes_arg);
    effects.add(.releases);

    return InferredSummary{
        .name = func_name,
        .pattern = .destructor_name,
        .confidence = confidence,
        .effects = effects,
        .family = null, // may span multiple families
        .target_param = 0, // first arg by convention for destructors
        .evidence = "Structural inference: destructor-like name pattern matched",
    };
}

/// Case-insensitive suffix check.
fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const start = haystack.len - needle.len;
    for (needle, 0..) |c, i| {
        if (toLower(haystack[start + i]) != toLower(c)) return false;
    }
    return true;
}

/// Case-insensitive contains check. Returns index or null.
fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    const upper_limit = haystack.len - needle.len;
    var i: usize = 0;
    while (i <= upper_limit) : (i += 1) {
        var found = true;
        for (needle, 0..) |c, j| {
            if (toLower(haystack[i + j]) != toLower(c)) {
                found = false;
                break;
            }
        }
        if (found) return i;
    }
    return null;
}

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    if (prefix.len > haystack.len) return false;
    return std.mem.eql(u8, haystack[0..prefix.len], prefix);
}

// ============================================================================
// 5.2 Slice-to-ptr Bridge Helper Pattern
// ============================================================================

/// Known bridge helper name patterns that convert safe references to raw pointers.
/// These functions do NOT transfer ownership — they borrow.
const bridge_helper_patterns = [_][]const u8{
    "as_ptr",   "as_mut_ptr", "ptr",          "ptr_mut",     "ptr_mut_void",
    "as_slice", "as_bytes",   "as_mut_slice", "get_pointer", "data",
    "c_str",    "slice::ptr", "str::as_ptr",  "@ptrCast",
};

/// Infer that a function is a bridge helper (returns borrowed pointer).
/// Replaces part of Pattern A (as_ptr not being leak) in issue_suppression.zig.
///
/// Bridge helpers have these characteristics:
/// - Name matches as_ptr/data/c_str/etc.
/// - Body typically only has GEP/bitcast/extractvalue/return (no alloc/free)
/// - Input is a slice/ref/array → output is raw *T
pub fn inferBridgeHelperSummary(
    func_name: []const u8,
) !?InferredSummary {
    var confidence: f32 = 0.6;
    var matched = false;

    for (bridge_helper_patterns) |pattern| {
        if (endsWithIgnoreCase(func_name, pattern) or
            std.mem.indexOf(u8, func_name, pattern) != null)
        {
            matched = true;
            // Higher confidence for standard library patterns
            if (std.mem.indexOf(u8, func_name, ".") != null) {
                // Qualified name like "slice.as_ptr" — very likely real bridge
                confidence = 0.88;
            } else if (std.mem.eql(u8, func_name, "as_ptr") or
                std.mem.eql(u8, func_name, "as_mut_ptr"))
            {
                confidence = 0.85;
            }
            break;
        }
    }

    if (!matched) return null;

    var effects = EffectSet.empty;
    effects.add(.returns_borrowed);

    return InferredSummary{
        .name = func_name,
        .pattern = .bridge_helper_body,
        .confidence = confidence,
        .effects = effects,
        .evidence = "Structural inference: bridge helper returns borrowed pointer (no ownership transfer)",
    };
}

// ============================================================================
// 5.3 Refcount Release Pattern
// ============================================================================

/// Known refcount release function names.
/// These perform conditional release based on runtime reference count.
const refcount_release_patterns = [_]struct { []const u8, ?FamilyId, f32 }{
    // (name, family, confidence)
    .{ "Py_DECREF", .python_object, 1.0 },
    .{ "Py_XDECREF", .python_object, 1.0 },
    .{ "Py_CLEAR", .python_object, 1.0 },
    .{ "Arc::drop", null, 0.75 },
    .{ "arc_drop", null, 0.7 },
    .{ "CFRelease", null, 0.85 },
    .{ "CFRetain", null, 0.7 }, // retain is not release but related
    .{ "IUnknown::Release", null, 0.8 },
    .{ "IUnknown_AddRef", null, 0.7 },
    .{ "objc_release", null, 0.85 },
    .{ "objc_retain", null, 0.75 },
    .{ "IDecrementRelease", null, 0.75 },
    .{ "ReleaseStableReference", null, 0.7 },
    .{ "gtk_widget_destroy", null, 0.65 },
    .{ "g_object_unref", null, 0.8 },
    .{ "g_variant_unref", null, 0.8 },
    .{ "g_bytes_unref", null, 0.8 },
    .{ "g_error_free", null, 0.75 },
    .{ "xmlFreeDoc", null, 0.72 },
    .{ "xmlFreeNode", null, 0.72 },
    .{ "json_decref", null, 0.78 },
    .{ "json_object_put", null, 0.78 },
    .{ "bson_destroy", null, 0.7 },
    .{ "cJSON_Delete", null, 0.75 },
    .{ "freeaddrinfo", null, 0.7 },
};

/// Infer that a function performs conditional (refcount-based) release.
/// Key insight: Py_DECREF does NOT unconditionally free — it decrements
/// refcount and only frees when count reaches zero.
///
/// Mis-modeling as unconditional `.releases` causes FP leaks because
/// the analyzer thinks every call frees the resource.
pub fn inferRefcountReleaseSummary(
    store: *SummaryStore,
    func_name: []const u8,
) !?InferredSummary {
    for (refcount_release_patterns) |entry| {
        const pattern = entry[0];
        const entry_fam = entry[1];
        const conf = entry[2];

        if (std.mem.eql(u8, func_name, pattern)) {
            var effects = EffectSet.empty;
            effects.add(.conditional_release);

            return InferredSummary{
                .name = func_name,
                .pattern = .refcount_release_shape,
                .confidence = conf,
                .effects = effects,
                .family = entry_fam,
                .target_param = 0,
                .evidence = "Structural inference: refcount conditional release (frees only when refcount→0)",
            };
        }
    }

    // Also check suffix patterns like *_unref, *_release, *_decref
    if (endsWithIgnoreCase(func_name, "_unref") or
        endsWithIgnoreCase(func_name, "_release") or
        endsWithIgnoreCase(func_name, "_decref") or
        endsWithIgnoreCase(func_name, "_free"))
    {
        // Skip already-known builtins
        if (store.entries.get(func_name) != null) return null;

        var effects = EffectSet.empty;
        effects.add(.conditional_release);

        return InferredSummary{
            .name = func_name,
            .pattern = .refcount_release_shape,
            .confidence = 0.55,
            .effects = effects,
            .target_param = 0,
            .evidence = "Structural inference: name ends with _unref/_release/_decref/_free (heuristic)",
        };
    }

    return null;
}

// ============================================================================
// 5.4 Static Lifetime Sink Pattern
// ============================================================================

/// Known patterns where resources are intentionally stored with process lifetime.
/// These are NOT leaks — they live until process exit.
const static_lifetime_patterns = [_][]const u8{
    "_init_",                       "_global_init", "_static_init",
    "__attribute__((constructor))",
    "DllMain", // Windows DLL entry point
    "atexit", // atexit handler registration
    "pthread_once_init",
    "__mod_init_func",
    "_GLOBAL__sub_I_", // C++ static initializer
};

/// Infer that a function stores a resource into a global/static variable.
/// The resource has process lifetime — NOT a leak.
///
/// Conditions for safe static-lifetime classification:
/// - Allocation happens once (not in a loop)
/// - Stored into a global/static variable
/// - No corresponding manual free before program exit
pub fn inferStaticLifetimeSink(
    func_name: []const u8,
) !?InferredSummary {
    for (static_lifetime_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return InferredSummary{
                .name = func_name,
                .pattern = .static_lifetime_sink,
                .confidence = 0.7,
                .effects = EffectSet.empty, // no effect change, just lifetime annotation
                .evidence = "Structural inference: resource stored to global/static (process lifetime)",
            };
        }
    }

    // Check for C++ static initializer pattern
    if (std.mem.indexOf(u8, func_name, "_GLOBAL__sub_I_") != null) {
        return InferredSummary{
            .name = func_name,
            .pattern = .static_lifetime_sink,
            .confidence = 0.82,
            .effects = EffectSet.empty,
            .evidence = "Structural inference: C++ static initializer (process lifetime)",
        };
    }

    return null;
}

// ============================================================================
// 5.5 Same-Family Release Evidence
// ============================================================================

/// Generate human-readable family evidence string for issue messages.
/// Called by reporting code to annotate issues with family information.
///
/// Examples:
///   "allocated_by=c_heap released_by=c_heap (same_family ✓)"
///   "allocated_by=rust_global released_by=c_heap (MISMATCH ✗)"
pub fn formatFamilyEvidence(alloc_family: ?FamilyId, release_family: ?FamilyId) []const u8 {
    if (alloc_family == null and release_family == null) {
        return "(family unknown)";
    }
    if (alloc_family != null and release_family != null) {
        if (alloc_family.? == release_family.?) {
            // Same family — valid release
            return "same_family_valid";
        } else {
            // Mismatch
            return "cross_family_mismatch";
        }
    }
    if (alloc_family != null) {
        return "release_family_unknown";
    }
    return "alloc_family_unknown";
}
