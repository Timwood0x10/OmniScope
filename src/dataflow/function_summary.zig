//! Function Summary for Inter-procedural Analysis
//!
//! This module provides function summary data structures for tracking
//! data flow across function boundaries. It enables precise tracking
//! of pointer ownership through function calls.
//!
//! Key concepts:
//! - Parameter flow: which parameters flow to return value
//! - Side effects: whether function allocates/frees memory
//! - Ownership transfer: whether function consumes/transfers ownership
//! - Cross-function leak detection: summary-based propagation for 1-level depth
//!
//! T4 Enhancement: Added cross-function memory leak detection fields:
//! - alloc_params: which parameters are allocations (callee must free)
//! - free_params: which parameters are freed (ownership consumed)
//! - returns_owned: whether return value is an owned allocation
//! - may_escape: whether allocation can escape to global scope

const std = @import("std");
const log = @import("../common/log.zig");

const Allocator = std.mem.Allocator;

/// Parameter flow direction
pub const ParamFlow = enum(u8) {
    /// Parameter does not flow anywhere
    none,
    /// Parameter flows to return value
    to_return,
    /// Parameter flows to another parameter (output param)
    to_param,
    /// Parameter flows to both return and another param
    to_both,
};

/// Function side effects
pub const SideEffects = packed struct {
    /// Function allocates memory
    allocates: bool,
    /// Function frees memory
    frees: bool,
    /// Function writes to memory through pointer
    writes_memory: bool,
    /// Function reads from memory through pointer
    reads_memory: bool,
    /// Function may throw exceptions
    may_throw: bool,
    /// Function has external side effects (I/O, etc.)
    external: bool,
};

/// Ownership behavior for a parameter
pub const OwnershipBehavior = enum(u8) {
    /// Function does not affect ownership
    none,
    /// Function consumes ownership (takes responsibility)
    consumes,
    /// Function transfers ownership to caller
    transfers,
    /// Function borrows (does not take ownership)
    borrows,
};

/// Summary of a function's behavior for inter-procedural analysis
pub const FunctionSummary = struct {
    /// Function name
    name: []const u8,
    /// Number of parameters
    param_count: u8,
    /// Parameter flow relationships
    /// Maps param_index -> ParamFlow
    param_flows: []ParamFlow,
    /// Side effects of the function
    side_effects: SideEffects,
    /// Ownership behavior for each parameter
    ownership: []OwnershipBehavior,
    /// Whether this function is a known allocator
    is_allocator: bool,
    /// Whether this function is a known deallocator
    is_deallocator: bool,
    /// Confidence level (0.0 - 1.0)
    confidence: f32,

    // T4: Cross-function leak detection fields
    /// Which parameters are allocations that callee must free.
    /// If alloc_params[i] = true, param i is an owned pointer that
    /// the callee takes responsibility for freeing.
    alloc_params: std.DynamicBitSet,
    /// Which parameters have their ownership consumed (freed by callee).
    /// If free_params[i] = true, param i's ownership is transferred to callee.
    free_params: std.DynamicBitSet,
    /// Whether the return value is an owned allocation (caller must free).
    /// True for malloc, calloc, PyList_New, etc.
    returns_owned: bool,
    /// Whether allocations in this function may escape to global scope.
    /// If true, suppress leak reports (may be intentionally long-lived).
    may_escape: bool,
    /// Maximum propagation depth for this summary (always 1 for T4).
    propagation_depth: u8,

    /// Create a new function summary
    pub fn init(
        allocator: Allocator,
        name: []const u8,
        param_count: u8,
    ) !FunctionSummary {
        const param_flows = try allocator.alloc(ParamFlow, param_count);
        errdefer allocator.free(param_flows);
        @memset(param_flows, .none);

        const ownership = try allocator.alloc(OwnershipBehavior, param_count);
        @memset(ownership, .none);

        // T4: Initialize bitsets for cross-function analysis
        var alloc_params = try std.DynamicBitSet.initEmpty(allocator, param_count);
        errdefer alloc_params.deinit();

        var free_params = try std.DynamicBitSet.initEmpty(allocator, param_count);
        errdefer free_params.deinit();

        return .{
            .name = name,
            .param_count = param_count,
            .param_flows = param_flows,
            .side_effects = .{
                .allocates = false,
                .frees = false,
                .writes_memory = false,
                .reads_memory = false,
                .may_throw = false,
                .external = false,
            },
            .ownership = ownership,
            .is_allocator = false,
            .is_deallocator = false,
            .confidence = 1.0,
            // T4: Initialize cross-function fields
            .alloc_params = alloc_params,
            .free_params = free_params,
            .returns_owned = false,
            .may_escape = false,
            .propagation_depth = 1,
        };
    }

    /// Free resources
    pub fn deinit(self: *FunctionSummary, allocator: Allocator) void {
        allocator.free(self.param_flows);
        allocator.free(self.ownership);
        // T4: Free bitsets
        self.alloc_params.deinit();
        self.free_params.deinit();
    }

    /// Set parameter flow
    pub fn setParamFlow(self: *FunctionSummary, param_idx: u8, flow: ParamFlow) void {
        if (param_idx < self.param_count) {
            self.param_flows[param_idx] = flow;
        }
    }

    /// Set ownership behavior for a parameter
    pub fn setOwnership(self: *FunctionSummary, param_idx: u8, behavior: OwnershipBehavior) void {
        if (param_idx < self.param_count) {
            self.ownership[param_idx] = behavior;
        }
    }

    /// Check if parameter flows to return
    pub fn paramFlowsToReturn(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.param_flows[param_idx] == .to_return or
            self.param_flows[param_idx] == .to_both;
    }

    /// Check if function consumes ownership of parameter
    pub fn consumesOwnership(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.ownership[param_idx] == .consumes;
    }

    /// Check if function transfers ownership through return
    pub fn transfersOwnership(self: *const FunctionSummary) bool {
        return self.is_allocator or self.returns_owned;
    }

    // T4: Cross-function leak detection methods

    /// Mark a parameter as an allocation that callee must free.
    /// Used when caller passes an owned pointer to a function that
    /// takes ownership (e.g., passing malloc'd ptr to free()).
    pub fn markAllocParam(self: *FunctionSummary, param_idx: usize) void {
        if (param_idx < self.param_count) {
            self.alloc_params.set(param_idx);
            log.debug("SUMMARY: Marked param {} of {s} as alloc_param", .{ param_idx, self.name });
        }
    }

    /// Mark a parameter as having its ownership consumed by callee.
    /// Used when function frees the pointer (e.g., free(ptr)).
    pub fn markFreeParam(self: *FunctionSummary, param_idx: usize) void {
        if (param_idx < self.param_count) {
            self.free_params.set(param_idx);
            log.debug("SUMMARY: Marked param {} of {s} as free_param", .{ param_idx, self.name });
        }
    }

    /// Check if a parameter is an allocation (callee must free).
    pub fn isAllocParam(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.alloc_params.isSet(param_idx);
    }

    /// Check if a parameter's ownership is consumed (freed by callee).
    pub fn isFreeParam(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.free_params.isSet(param_idx);
    }

    /// Check if this function's return value should be tracked for leaks.
    /// Returns true if the function returns an owned allocation.
    pub fn shouldTrackReturn(self: *const FunctionSummary) bool {
        return self.returns_owned or self.is_allocator;
    }

    /// Check if this function may cause allocations to escape to global scope.
    /// If true, suppress leak reports for pointers passed to this function.
    pub fn mayCauseEscape(self: *const FunctionSummary) bool {
        return self.may_escape;
    }

    /// Get string representation of this summary (for debugging).
    pub fn format(self: *const FunctionSummary, allocator: Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        try buf.writer().print("FunctionSummary({s}, params={d}, ", .{ self.name, self.param_count });
        try buf.writer().print("alloc={s}, free={s}, ", .{
            if (self.side_effects.allocates) "Y" else "N",
            if (self.side_effects.frees) "Y" else "N",
        });
        try buf.writer().print("returns_owned={s}, may_escape={s})", .{
            if (self.returns_owned) "Y" else "N",
            if (self.may_escape) "Y" else "N",
        });

        return buf.toOwnedSlice();
    }
};

/// Registry of known function summaries
pub const SummaryRegistry = struct {
    /// Map of function name to summary
    summaries: std.StringHashMap(FunctionSummary),
    /// Allocator
    allocator: Allocator,

    /// Create a new summary registry
    pub fn init(allocator: Allocator) SummaryRegistry {
        return .{
            .summaries = std.StringHashMap(FunctionSummary).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *SummaryRegistry) void {
        var iter = self.summaries.iterator();
        while (iter.next()) |entry| {
            var summary = entry.value_ptr.*;
            summary.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.summaries.deinit();
    }

    /// Register a function summary
    pub fn register(self: *SummaryRegistry, summary: FunctionSummary) !void {
        // M2 FIX v2: Free old entry on duplicate registration to prevent memory leak.
        // Ownership semantics:
        //   - entry.key:     heap string copy made by register()'s dupe() → must free
        //   - entry.value:   FunctionSummary with internal heap arrays (param_flows, ownership)
        //                     allocated by FunctionSummary.init() → must deinit to free them
        // Only the key is explicitly freed here; the value's internal arrays are freed by deinit().
        if (self.summaries.fetchRemove(summary.name)) |entry| {
            var old_value = entry.value;
            old_value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }
        const name_copy = try self.allocator.dupe(u8, summary.name);
        errdefer self.allocator.free(name_copy);
        try self.summaries.put(name_copy, summary);
    }

    /// Look up a function summary by name
    pub fn lookup(self: *const SummaryRegistry, name: []const u8) ?FunctionSummary {
        return self.summaries.get(name);
    }

    /// Check if a function is known
    pub fn isKnown(self: *const SummaryRegistry, name: []const u8) bool {
        return self.summaries.contains(name);
    }

    /// Initialize with built-in summaries for common functions
    /// T4 Enhanced: Added cross-language function summaries (Python, Rust, JNI)
    pub fn initBuiltins(self: *SummaryRegistry) !void {
        // ====================================================================
        // C Standard Library Functions
        // ====================================================================

        // malloc: allocates, transfers ownership via return
        var malloc_summary = try FunctionSummary.init(self.allocator, "malloc", 1);
        errdefer malloc_summary.deinit(self.allocator);
        malloc_summary.side_effects.allocates = true;
        malloc_summary.is_allocator = true;
        malloc_summary.returns_owned = true;
        malloc_summary.confidence = 1.0;
        try self.register(malloc_summary);

        // free: frees, consumes ownership of param 0
        var free_summary = try FunctionSummary.init(self.allocator, "free", 1);
        errdefer free_summary.deinit(self.allocator);
        free_summary.side_effects.frees = true;
        free_summary.setOwnership(0, .consumes);
        free_summary.markFreeParam(0);
        free_summary.is_deallocator = true;
        free_summary.confidence = 1.0;
        try self.register(free_summary);

        // calloc: allocates, transfers ownership via return
        var calloc_summary = try FunctionSummary.init(self.allocator, "calloc", 2);
        errdefer calloc_summary.deinit(self.allocator);
        calloc_summary.side_effects.allocates = true;
        calloc_summary.is_allocator = true;
        calloc_summary.returns_owned = true;
        calloc_summary.confidence = 1.0;
        try self.register(calloc_summary);

        // realloc: allocates and frees, consumes old ptr, returns new
        var realloc_summary = try FunctionSummary.init(self.allocator, "realloc", 2);
        errdefer realloc_summary.deinit(self.allocator);
        realloc_summary.side_effects.allocates = true;
        realloc_summary.side_effects.frees = true;
        realloc_summary.setOwnership(0, .consumes);
        realloc_summary.markFreeParam(0);
        realloc_summary.setParamFlow(0, .to_return);
        realloc_summary.is_allocator = true;
        realloc_summary.returns_owned = true;
        realloc_summary.confidence = 1.0;
        try self.register(realloc_summary);

        // memcpy: writes memory (not an allocator, but moves data)
        var memcpy_summary = try FunctionSummary.init(self.allocator, "memcpy", 3);
        errdefer memcpy_summary.deinit(self.allocator);
        memcpy_summary.side_effects.writes_memory = true;
        memcpy_summary.setParamFlow(0, .to_return);
        memcpy_summary.confidence = 1.0;
        try self.register(memcpy_summary);

        // strcpy: writes memory, dangerous buffer overflow risk
        var strcpy_summary = try FunctionSummary.init(self.allocator, "strcpy", 2);
        errdefer strcpy_summary.deinit(self.allocator);
        strcpy_summary.side_effects.writes_memory = true;
        strcpy_summary.setParamFlow(0, .to_return);
        strcpy_summary.confidence = 1.0;
        try self.register(strcpy_summary);

        // ====================================================================
        // Python C API Functions
        // ====================================================================

        // PyList_New: allocates new list, returns owned reference
        var pylist_new = try FunctionSummary.init(self.allocator, "PyList_New", 1);
        errdefer pylist_new.deinit(self.allocator);
        pylist_new.side_effects.allocates = true;
        pylist_new.is_allocator = true;
        pylist_new.returns_owned = true;
        pylist_new.confidence = 1.0;
        try self.register(pylist_new);

        // PyDict_New: allocates new dict, returns owned reference
        var pydict_new = try FunctionSummary.init(self.allocator, "PyDict_New", 0);
        errdefer pydict_new.deinit(self.allocator);
        pydict_new.side_effects.allocates = true;
        pydict_new.is_allocator = true;
        pydict_new.returns_owned = true;
        pydict_new.confidence = 1.0;
        try self.register(pydict_new);

        // PyTuple_New: allocates new tuple, returns owned reference
        var pytuple_new = try FunctionSummary.init(self.allocator, "PyTuple_New", 1);
        errdefer pytuple_new.deinit(self.allocator);
        pytuple_new.side_effects.allocates = true;
        pytuple_new.is_allocator = true;
        pytuple_new.returns_owned = true;
        pytuple_new.confidence = 1.0;
        try self.register(pytuple_new);

        // Py_INCREF: increments refcount (borrows, does not allocate)
        var py_incref = try FunctionSummary.init(self.allocator, "Py_INCREF", 1);
        errdefer py_incref.deinit(self.allocator);
        py_incref.setOwnership(0, .borrows);
        py_incref.confidence = 1.0;
        try self.register(py_incref);

        // Py_DECREF: decrements refcount, may free (consumes ownership)
        var py_decref = try FunctionSummary.init(self.allocator, "Py_DECREF", 1);
        errdefer py_decref.deinit(self.allocator);
        py_decref.side_effects.frees = true;
        py_decref.setOwnership(0, .consumes);
        py_decref.markFreeParam(0);
        py_decref.is_deallocator = true;
        py_decref.confidence = 1.0;
        try self.register(py_decref);

        // Py_XDECREF: safe decref (consumes ownership, handles null)
        var py_xdecref = try FunctionSummary.init(self.allocator, "Py_XDECREF", 1);
        errdefer py_xdecref.deinit(self.allocator);
        py_xdecref.side_effects.frees = true;
        py_xdecref.setOwnership(0, .consumes);
        py_xdecref.markFreeParam(0);
        py_xdecref.is_deallocator = true;
        py_xdecref.confidence = 1.0;
        try self.register(py_xdecref);

        // PyMem_Malloc: raw memory allocation, returns owned pointer
        var pymem_malloc = try FunctionSummary.init(self.allocator, "PyMem_Malloc", 1);
        errdefer pymem_malloc.deinit(self.allocator);
        pymem_malloc.side_effects.allocates = true;
        pymem_malloc.is_allocator = true;
        pymem_malloc.returns_owned = true;
        pymem_malloc.confidence = 1.0;
        try self.register(pymem_malloc);

        // PyMem_Free: raw memory deallocation (consumes ownership)
        var pymem_free = try FunctionSummary.init(self.allocator, "PyMem_Free", 1);
        errdefer pymem_free.deinit(self.allocator);
        pymem_free.side_effects.frees = true;
        pymem_free.setOwnership(0, .consumes);
        pymem_free.markFreeParam(0);
        pymem_free.is_deallocator = true;
        pymem_free.confidence = 1.0;
        try self.register(pymem_free);

        // PyObject_Malloc: object allocator, returns owned pointer
        var pyobj_malloc = try FunctionSummary.init(self.allocator, "PyObject_Malloc", 1);
        errdefer pyobj_malloc.deinit(self.allocator);
        pyobj_malloc.side_effects.allocates = true;
        pyobj_malloc.is_allocator = true;
        pyobj_malloc.returns_owned = true;
        pyobj_malloc.confidence = 1.0;
        try self.register(pyobj_malloc);

        // PyObject_Free: object deallocator (consumes ownership)
        var pyobj_free = try FunctionSummary.init(self.allocator, "PyObject_Free", 1);
        errdefer pyobj_free.deinit(self.allocator);
        pyobj_free.side_effects.frees = true;
        pyobj_free.setOwnership(0, .consumes);
        pyobj_free.markFreeParam(0);
        pyobj_free.is_deallocator = true;
        pyobj_free.confidence = 1.0;
        try self.register(pyobj_free);

        // ====================================================================
        // Rust FFI Functions
        // ====================================================================

        // into_raw: converts Box to raw pointer, transfers ownership to caller
        var into_raw = try FunctionSummary.init(self.allocator, "into_raw", 1);
        errdefer into_raw.deinit(self.allocator);
        into_raw.setOwnership(0, .consumes);
        into_raw.markFreeParam(0);
        into_raw.returns_owned = true;
        into_raw.confidence = 1.0;
        try self.register(into_raw);

        // from_raw: converts raw pointer back to Box, takes ownership
        var from_raw = try FunctionSummary.init(self.allocator, "from_raw", 1);
        errdefer from_raw.deinit(self.allocator);
        from_raw.setOwnership(0, .consumes);
        from_raw.markAllocParam(0);
        from_raw.is_deallocator = true;
        from_raw.confidence = 1.0;
        try self.register(from_raw);

        // __rust_alloc: Rust global allocator, returns owned memory
        var rust_alloc = try FunctionSummary.init(self.allocator, "__rust_alloc", 2);
        errdefer rust_alloc.deinit(self.allocator);
        rust_alloc.side_effects.allocates = true;
        rust_alloc.is_allocator = true;
        rust_alloc.returns_owned = true;
        rust_alloc.confidence = 1.0;
        try self.register(rust_alloc);

        // __rust_dealloc: Rust global deallocator (consumes ownership)
        var rust_dealloc = try FunctionSummary.init(self.allocator, "__rust_dealloc", 2);
        errdefer rust_dealloc.deinit(self.allocator);
        rust_dealloc.side_effects.frees = true;
        rust_dealloc.setOwnership(0, .consumes);
        rust_dealloc.markFreeParam(0);
        rust_dealloc.is_deallocator = true;
        rust_dealloc.confidence = 1.0;
        try self.register(rust_dealloc);

        // drop_in_place: calls destructor without freeing (partial consume)
        var drop_in_place = try FunctionSummary.init(self.allocator, "drop_in_place", 1);
        errdefer drop_in_place.deinit(self.allocator);
        drop_in_place.setOwnership(0, .borrows);
        drop_in_place.confidence = 0.9;
        try self.register(drop_in_place);

        // ====================================================================
        // JNI (Java Native Interface) Functions
        // ====================================================================

        // NewGlobalRef: creates global reference, returns owned ref
        var new_global_ref = try FunctionSummary.init(self.allocator, "NewGlobalRef", 2);
        errdefer new_global_ref.deinit(self.allocator);
        new_global_ref.side_effects.allocates = true;
        new_global_ref.is_allocator = true;
        new_global_ref.returns_owned = true;
        new_global_ref.may_escape = true; // Global refs persist beyond function scope
        new_global_ref.confidence = 1.0;
        try self.register(new_global_ref);

        // DeleteGlobalRef: deletes global reference (consumes ownership)
        var delete_global_ref = try FunctionSummary.init(self.allocator, "DeleteGlobalRef", 1);
        errdefer delete_global_ref.deinit(self.allocator);
        delete_global_ref.side_effects.frees = true;
        delete_global_ref.setOwnership(0, .consumes);
        delete_global_ref.markFreeParam(0);
        delete_global_ref.is_deallocator = true;
        delete_global_ref.confidence = 1.0;
        try self.register(delete_global_ref);

        // NewLocalRef: creates local reference, returns owned ref
        var new_local_ref = try FunctionSummary.init(self.allocator, "NewLocalRef", 2);
        errdefer new_local_ref.deinit(self.allocator);
        new_local_ref.side_effects.allocates = true;
        new_local_ref.is_allocator = true;
        new_local_ref.returns_owned = true;
        new_local_ref.confidence = 1.0;
        try self.register(new_local_ref);

        // DeleteLocalRef: deletes local reference (consumes ownership)
        var delete_local_ref = try FunctionSummary.init(self.allocator, "DeleteLocalRef", 1);
        errdefer delete_local_ref.deinit(self.allocator);
        delete_local_ref.side_effects.frees = true;
        delete_local_ref.setOwnership(0, .consumes);
        delete_local_ref.markFreeParam(0);
        delete_local_ref.is_deallocator = true;
        delete_local_ref.confidence = 1.0;
        try self.register(delete_local_ref);

        // GetByteArrayElements: gets array elements, returns owned pointer
        var get_byte_array = try FunctionSummary.init(self.allocator, "GetByteArrayElements", 3);
        errdefer get_byte_array.deinit(self.allocator);
        get_byte_array.side_effects.allocates = true;
        get_byte_array.is_allocator = true;
        get_byte_array.returns_owned = true;
        get_byte_array.confidence = 1.0;
        try self.register(get_byte_array);

        // ReleaseByteArrayElements: releases array elements (consumes ownership)
        var release_byte_array = try FunctionSummary.init(self.allocator, "ReleaseByteArrayElements", 4);
        errdefer release_byte_array.deinit(self.allocator);
        release_byte_array.side_effects.frees = true;
        release_byte_array.setOwnership(1, .consumes);
        release_byte_array.markFreeParam(1);
        release_byte_array.is_deallocator = true;
        release_byte_array.confidence = 1.0;
        try self.register(release_byte_array);

        // ====================================================================
        // Go CGo Functions
        // ====================================================================

        // C.CString: converts Go string to C string (allocates, returns owned)
        var c_cstring = try FunctionSummary.init(self.allocator, "C.CString", 1);
        errdefer c_cstring.deinit(self.allocator);
        c_cstring.side_effects.allocates = true;
        c_cstring.is_allocator = true;
        c_cstring.returns_owned = true;
        c_cstring.confidence = 0.88; // Go may free in defer, lower confidence
        try self.register(c_cstring);

        // C.CBytes: converts Go byte slice to C pointer (allocates, returns owned)
        var c_cbytes = try FunctionSummary.init(self.allocator, "C.CBytes", 1);
        errdefer c_cbytes.deinit(self.allocator);
        c_cbytes.side_effects.allocates = true;
        c_cbytes.is_allocator = true;
        c_cbytes.returns_owned = true;
        c_cbytes.confidence = 0.88;
        try self.register(c_cbytes);

        // C.free: frees memory allocated by C.CString/C.CBytes (consumes ownership)
        var c_free = try FunctionSummary.init(self.allocator, "C.free", 1);
        errdefer c_free.deinit(self.allocator);
        c_free.side_effects.frees = true;
        c_free.setOwnership(0, .consumes);
        c_free.markFreeParam(0);
        c_free.is_deallocator = true;
        c_free.confidence = 1.0;
        try self.register(c_free);

        // C.malloc: Go's wrapper around C malloc (allocates, returns owned)
        var c_malloc = try FunctionSummary.init(self.allocator, "C.malloc", 1);
        errdefer c_malloc.deinit(self.allocator);
        c_malloc.side_effects.allocates = true;
        c_malloc.is_allocator = true;
        c_malloc.returns_owned = true;
        c_malloc.confidence = 0.9;
        try self.register(c_malloc);

        // C.calloc: Go's wrapper around C calloc (allocates, returns owned)
        var c_calloc = try FunctionSummary.init(self.allocator, "C.calloc", 2);
        errdefer c_calloc.deinit(self.allocator);
        c_calloc.side_effects.allocates = true;
        c_calloc.is_allocator = true;
        c_calloc.returns_owned = true;
        c_calloc.confidence = 0.9;
        try self.register(c_calloc);

        // runtime.deferreturn: indicates defer pattern (may suppress leak reports)
        // This is a marker function, not an actual allocator/deallocator
        var defer_return = try FunctionSummary.init(self.allocator, "runtime.deferreturn", 0);
        errdefer defer_return.deinit(self.allocator);
        defer_return.may_escape = true; // Defer may free later
        defer_return.confidence = 0.7;
        try self.register(defer_return);

        log.info("SUMMARY: Initialized {} built-in function summaries", .{self.summaries.count()});
    }
};

// Unit tests

test "ParamFlow enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ParamFlow.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ParamFlow.to_return));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ParamFlow.to_param));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ParamFlow.to_both));
}

test "SideEffects packed struct" {
    const effects = SideEffects{
        .allocates = true,
        .frees = false,
        .writes_memory = true,
        .reads_memory = true,
        .may_throw = false,
        .external = false,
    };
    try std.testing.expect(effects.allocates);
    try std.testing.expect(!effects.frees);
    try std.testing.expect(effects.writes_memory);
    try std.testing.expect(effects.reads_memory);
}

test "OwnershipBehavior enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipBehavior.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipBehavior.consumes));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipBehavior.transfers));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipBehavior.borrows));
}

test "FunctionSummary - init and deinit" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test_func", 3);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("test_func", summary.name);
    try std.testing.expectEqual(@as(u8, 3), summary.param_count);
    try std.testing.expectEqual(@as(usize, 3), summary.param_flows.len);
}

test "FunctionSummary - setParamFlow" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setParamFlow(0, .to_return);
    summary.setParamFlow(1, .to_param);

    try std.testing.expectEqual(ParamFlow.to_return, summary.param_flows[0]);
    try std.testing.expectEqual(ParamFlow.to_param, summary.param_flows[1]);
}

test "FunctionSummary - setOwnership" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setOwnership(0, .consumes);
    summary.setOwnership(1, .borrows);

    try std.testing.expectEqual(OwnershipBehavior.consumes, summary.ownership[0]);
    try std.testing.expectEqual(OwnershipBehavior.borrows, summary.ownership[1]);
}

test "FunctionSummary - paramFlowsToReturn" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setParamFlow(0, .to_return);
    summary.setParamFlow(1, .none);

    try std.testing.expect(summary.paramFlowsToReturn(0));
    try std.testing.expect(!summary.paramFlowsToReturn(1));
}

test "FunctionSummary - consumesOwnership" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 1);
    defer summary.deinit(std.testing.allocator);

    summary.setOwnership(0, .consumes);

    try std.testing.expect(summary.consumesOwnership(0));
    try std.testing.expect(!summary.consumesOwnership(1)); // out of bounds
}

test "SummaryRegistry - init and deinit" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.summaries.count());
}

test "SummaryRegistry - register and lookup" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var summary = try FunctionSummary.init(std.testing.allocator, "my_func", 2);
    summary.setParamFlow(0, .to_return);
    try registry.register(summary);

    const found = registry.lookup("my_func");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(ParamFlow.to_return, found.?.param_flows[0]);
}

test "SummaryRegistry - initBuiltins" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.initBuiltins();

    try std.testing.expect(registry.isKnown("malloc"));
    try std.testing.expect(registry.isKnown("free"));
    try std.testing.expect(registry.isKnown("calloc"));
    try std.testing.expect(registry.isKnown("realloc"));
    try std.testing.expect(registry.isKnown("memcpy"));
    try std.testing.expect(registry.isKnown("strcpy"));

    const malloc = registry.lookup("malloc").?;
    try std.testing.expect(malloc.is_allocator);
    try std.testing.expect(malloc.side_effects.allocates);

    const free = registry.lookup("free").?;
    try std.testing.expect(free.is_deallocator);
    try std.testing.expect(free.side_effects.frees);
    try std.testing.expect(free.consumesOwnership(0));
}
