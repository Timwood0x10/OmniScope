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
