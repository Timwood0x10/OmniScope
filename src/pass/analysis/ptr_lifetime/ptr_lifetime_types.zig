//! Pointer Lifetime Types and Shared Utilities
//!
//! Contains type definitions, constants, and utility functions shared
//! between ptr_lifetime.zig and other analysis passes.
//!
//! Extracted from ptr_lifetime.zig to comply with the 1000-line limit.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const log = @import("../../../common/log.zig");
const word_boundary = @import("../../../utils/word_boundary.zig");

const allocator_kb = @import("../../../semantics/allocator_kb.zig");
const intrinsic_filter = @import("../../../semantics/intrinsic_filter.zig");

// ============================================================================
// Type Definitions
// ============================================================================

/// Allocation site classification for pointers.
pub const PtrAllocSite = enum(u8) {
    /// Allocated via malloc/calloc/realloc (heap)
    heap,
    /// Address of local variable (alloca instruction)
    stack,
    /// Function parameter (incoming pointer)
    parameter,
    /// Global variable address
    global,
    /// Constant/null value
    constant,
    /// Unknown origin (e.g., function return value)
    unknown,
};

/// Lifetime violation types detected by the tracker.
pub const LifetimeViolation = enum(u8) {
    /// Stack pointer passed to extern function that may outlive it
    stack_escape_to_ffi,
    /// Return of stack-local address
    return_stack_address,
    /// Use of pointer after potential free
    use_after_free_risk,
    /// Heap pointer passed to extern without documented transfer
    heap_ownership_ambiguous,
    /// Resource handle (dlopen) closed while derived pointers may still be in use
    dlhandle_closed_while_active,
    /// Memory mapping (mmap) unmapped while pointers to it may still be used
    mmap_unmapped_while_active,
    /// File handle (fopen) closed while FILE* may still be used
    file_handle_closed_while_active,
    /// Socket closed while socket fd may still be used
    socket_closed_while_active,
    /// JNI local reference deleted while still in use
    jni_local_ref_deleted_while_active,
    /// Python object reference released while still in use
    python_obj_released_while_active,
};

/// Information about a tracked pointer's origin and state.
pub const PtrInfo = struct {
    /// Where this pointer was allocated
    alloc_site: PtrAllocSite,
    /// The instruction that created this pointer (if any)
    source_inst: ?c.LLVMValueRef,
    /// Human-readable description for trace output
    source_desc: []const u8,
    /// Whether this pointer has been passed to an extern call
    escaped: bool = false,
    /// Whether this pointer has been freed
    freed: bool = false,
    /// v0.1.7: Whether this pointer has been double-freed (freed twice)
    double_free_detected: bool = false,
    /// Basic block where the pointer was allocated (for scope tracking)
    alloc_bb_id: usize = 0,
    /// Resource handle this pointer is derived from (e.g., dlopen handle for dlsym result)
    derived_from_handle: ?c.LLVMValueRef = null,
    /// Type of resource handle if derived
    resource_type: ResourceType = .none,
    /// Whether source_desc was dynamically allocated (for safe free)
    needs_free: bool = false,
    /// Whether this alloca is used only for storing function parameters.
    /// If true, it's a "param storage alloca" — safe, not a borrow_escape risk.
    is_param_storage: bool = false,
    /// Whether this allocation occurs inside a conditional branch (Bug 4 fix).
    /// If true, the allocation may not execute on all code paths →
    /// path-insensitive leak detection may produce FP. Reduces confidence.
    is_conditional_alloc: bool = false,
};

/// Resource types for lifecycle tracking.
pub const ResourceType = enum(u8) {
    none,
    dlopen_handle,
    mmap_region,
    file_handle,
    socket_fd,
    jni_ref,
    python_obj,
};

/// Record of a free site for path-sensitive double-free detection.
/// Tracks which basic block a free occurred in, so we can check if
/// two frees are on mutually exclusive execution paths.
pub const FreeSiteRecord = struct {
    /// The basic block ID where the free occurred
    bb_id: usize,
    /// The basic block ref (for predecessor check)
    bb_ref: c.LLVMValueRef,
    /// The free instruction
    free_inst: c.LLVMValueRef,
};

/// Lightweight growable list for FreeSiteRecord (contains opaque C types
/// that prevent std.ArrayList from monomorphizing correctly in Zig 0.15.2).
pub const FreeSiteList = struct {
    items: []FreeSiteRecord,
    len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FreeSiteList {
        return .{ .items = &.{}, .len = 0, .capacity = 0, .allocator = allocator };
    }

    pub fn append(self: *FreeSiteList, record: FreeSiteRecord) !void {
        if (self.len >= self.capacity) {
            const new_cap = if (self.capacity == 0) 4 else self.capacity * 2;
            const new_items = try self.allocator.alloc(FreeSiteRecord, new_cap);
            @memcpy(new_items[0..self.len], self.items);
            if (self.capacity > 0) self.allocator.free(self.items);
            self.items = new_items;
            self.capacity = new_cap;
        }
        self.items[self.len] = record;
        self.len += 1;
    }

    pub fn deinit(self: *FreeSiteList) void {
        if (self.capacity > 0) self.allocator.free(self.items);
    }
};

/// Analysis result for a single function.
pub const LifetimeAnalysisResult = struct {
    /// Number of violations found
    violation_count: u32 = 0,
    /// Total pointers tracked
    pointers_tracked: u32 = 0,
    /// Functions analyzed
    func_name: []const u8,
};

/// Statistics for the lifetime tracker pass.
pub const LifetimeStats = struct {
    total_functions_analyzed: u32 = 0,
    total_pointers_tracked: u32 = 0,
    functions_skipped_by_gate: u32 = 0,
    stack_escapes_found: u32 = 0,
    return_stack_addr_found: u32 = 0,
    use_after_free_found: u32 = 0,
    heap_ambiguous_found: u32 = 0,
    heap_intentional_transfer: u32 = 0,

    pub fn formatSummary(self: LifetimeStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   POINTER LIFETIME TRACKER SUMMARY   ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:     {d:>8}      ║\n", .{self.total_functions_analyzed});
        try writer.print("║  Functions skipped(gate):{d:>8}      ║\n", .{self.functions_skipped_by_gate});
        try writer.print("║  Pointers tracked:       {d:>8}      ║\n", .{self.total_pointers_tracked});
        try writer.print("║  Stack-FFI escapes:      {d:>8}      ║\n", .{self.stack_escapes_found});
        try writer.print("║  Return-stack-address:   {d:>8}      ║\n", .{self.return_stack_addr_found});
        try writer.print("║  Use-after-free risks:   {d:>8}      ║\n", .{self.use_after_free_found});
        try writer.print("║  Heap ownership issues:  {d:>8}      ║\n", .{self.heap_ambiguous_found});
        try writer.print("║  Factory transfers (ok): {d:>8}      ║\n", .{self.heap_intentional_transfer});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// LLVM Lifetime Intrinsic Tracking (T1.2)
// ============================================================================

/// Lifetime interval for a single alloca instruction.
/// Tracks [start_inst, end_inst] where the alloca is logically "alive".
pub const LifetimeInterval = struct {
    /// Instruction where lifetime.start was called (inclusive)
    start_inst: c.LLVMValueRef,
    /// Instruction where lifetime.end was called (exclusive, null if not yet ended)
    end_inst: ?c.LLVMValueRef,
};

/// Map from alloca pointer to its lifetime interval.
/// Used to reduce false positives in stack escape detection:
/// if an escape occurs outside the lifetime interval, it's likely a FP.
///
/// Key design decisions:
/// - Uses AutoHashMap for O(1) lookup by alloca ref
/// - Stores LLVMValueRef directly (not hash) for comparison efficiency
/// - end_inst=null means lifetime.start seen but no matching lifetime.end yet
pub const LifetimeMap = std.AutoHashMap(c.LLVMValueRef, LifetimeInterval);

/// Check if an instruction falls within a lifetime interval.
/// Returns true if inst is within [interval.start_inst, interval.end_inst).
///
/// When interval.end_inst is null (no lifetime.end seen), we consider
/// the instruction to be within the interval if it comes after start_inst
/// in the same basic block (conservative: assume alive until function end).
pub fn isWithinLifetime(
    interval: LifetimeInterval,
    inst: c.LLVMValueRef,
) bool {
    const inst_ptr = @intFromPtr(inst);
    const start_ptr = @intFromPtr(interval.start_inst);

    // Must be after or at start instruction
    if (inst_ptr < start_ptr) return false;

    // If no end instruction, assume still alive (conservative)
    if (interval.end_inst == null) return true;

    const end_ptr = @intFromPtr(interval.end_inst.?);
    // Must be before end instruction (exclusive)
    return inst_ptr < end_ptr;
}

/// Check if an alloca has an active lifetime interval that contains the given instruction.
/// Returns true if the instruction is within the alloca's lifetime, false otherwise.
///
/// This is the main query function used by checkStackEscape/checkCallViolation
/// to suppress false positive reports when escapes occur outside the lifetime.
pub fn isAllocaAliveAt(
    lifetime_map: *const LifetimeMap,
    alloca_ref: c.LLVMValueRef,
    inst: c.LLVMValueRef,
) bool {
    const interval = lifetime_map.get(alloca_ref) orelse return false;
    return isWithinLifetime(interval, inst);
}

// ============================================================================
// Constants
// ============================================================================

/// Known FFI boundary functions that may retain pointers.
/// These are functions where passing a stack pointer is dangerous.
const FFI_RETAINING_FUNCTIONS = &[_][]const u8{
    "c_callback",
    "register_callback",
    "set_handler",
    "pthread_create",
    "signal",
    "atexit",
    "on_exit",
    "SDL_SetEventCallback",
    "glfwSetCallback",
    "curl_easy_setopt",
};

/// Functions that commonly take callbacks (their arguments may be stored).
const CALLBACK_TAKING_FUNCTIONS = &[_][]const u8{
    "register",
    "set_callback",
    "add_observer",
    "subscribe",
    "listen_on",
    "handler",
    "hook",
};

/// Known deallocator/finalizer functions that release resources.
/// These are paired with their corresponding allocators to reduce false positives.
pub const KNOWN_DEALLOCATORS = struct {
    pub const finalize_functions = &[_][]const u8{
        "sqlite3_finalize", "sqlite3_step",   "mysql_stmt_close",
        "stmt_finalize",    "query_finalize", "statement_finalize",
    };
    pub const close_functions = &[_][]const u8{
        "fclose",       "close",        "closedir",            "closed", "shutdown",
        "SSL_shutdown", "BIO_free_all", "EVP_CIPHER_CTX_free",
    };
    pub const free_functions = &[_][]const u8{
        "sqlite3_free",      "mysql_free_result",   "PQclear", "nghttp2_session_del",
        "curl_easy_cleanup", "curl_slist_free_all",
    };
    pub const destroy_functions = &[_][]const u8{
        "sqlite3_close", "sqlite3_close_v2", "mysql_close",
        "destroy",       "Delete",           "Release",
        "Free",
    };
};

/// Canonical Rust global allocator intrinsic patterns — single source of truth.
///
/// These appear in mangled LLVM IR names like:
///   _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc
///   _ZN5alloc9alloc18alloc_global17h...
///
/// All consumers MUST import from here — never hardcode these patterns elsewhere.
pub const RUST_ALLOC_INTRINSICS = struct {
    /// All 8 Rust allocator/deallocator intrinsics (alloc + dealloc combined)
    pub const all = [_][]const u8{
        "__rust_alloc",        "__rust_dealloc", "__rust_realloc",
        "__rust_alloc_zeroed", "__rdl_alloc",    "__rdl_dealloc",
        "__rg_alloc",          "__rg_dealloc",   "exchange_malloc",
    };
    /// Allocator-only subset (no deallocators)
    pub const alloc_only = [_][]const u8{
        "__rust_alloc", "__rust_realloc",  "__rdl_alloc",
        "__rg_alloc",   "exchange_malloc",
    };
    /// Deallocator-only subset
    pub const dealloc_only = [_][]const u8{
        "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
    };
};

/// Heap allocation functions (legacy list, for compatibility).
pub const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc",          "calloc",         "realloc",      "aligned_alloc",
    "valloc",          "pvalloc",        "memalign",     "operator new",
    "operator new[]",  "allocImpl",      "mmap",
    // C++ operator new — Itanium ABI mangled names
    // Scalar: _Znw*, _Znwm (operator new / operator new(unsigned long))
    // Array:  _Zna*, _Znam (operator new[] / operator new[](unsigned long))
    // Covers standard + aligned (C++17) + nothrow + placement variants
    // Substring matching ensures all suffixes are caught (_ZnamSt9align_val_t, etc.)
            "_Znwm",
    "_Znam",           "_Znw",           "_Zna",
    // C++17 aligned new/delete (double underscore prefix on some platforms)
            "__Znwm",
    "__Znam",          "__Znw",          "__Zna",
    // Bug 3 fix: also catch MSVC-mangled operator new (when cross-compiled to ELF)
            "?operator new@@",
    "?operator new[]@@",
    // v0.1.7 FIX: Removed "into_raw" from this list.
    // into_raw is an OWNERSHIP TRANSFER (Rust → C), not a heap allocation.
    // Keeping it here caused false-positive leaks: Box::into_raw(ptr) was
    // recorded as a new allocation, and without matching from_raw, reported
    // as leaked. The correct tracking is in hooks.zig (rustOwnershipHook)
    // which pairs into_raw/from_raw as transfer-out/transfer-in.
            "dlopen",
    "fopen",           "socket",         "JNI_OnLoad",   "Py_Initialize",
    "Py_BuildValue",   "PyTuple_New",    "PyList_New",   "PyDict_New",
    "NewStringUTF",    "NewByteArray",   "NewGlobalRef", "c_malloc",
    // Rust global allocator intrinsics (substring-matched via isAllocFunction callers)
    "__rust_alloc",    "__rust_realloc", "__rdl_alloc",  "__rg_alloc",
    "exchange_malloc",
};

// ============================================================================
// Project-Level Allocator Pair Detection (P2-2)
// ============================================================================

/// Check if a function name follows common project-level allocator naming patterns.
/// This implements automatic allocator/free pairing to reduce false positives
/// in leak detection for projects using custom allocators (e.g., sqlite3Malloc).
///
/// Patterns detected (case-insensitive prefix/suffix matching):
///   - xxxMalloc, xxxAlloc, xxxCalloc, xxxRealloc (allocation)
///   - xxxCreate, xxxNew, xxxMake, xxxBuild (factory functions)
///   - xxxAllocate, xxxAllocateArray (verbose forms)
///
/// Returns true if the function is likely a project-level allocator.
pub fn isProjectAllocFunction(func_name: []const u8) bool {
    if (func_name.len < 4) return false; // Minimum: "Xxx" + "Malloc"

    // Suffix patterns: function must END with these (avoids false positives on
    // names like "malloc_safe", "allocator_info" etc.)
    const alloc_suffixes = [_][]const u8{
        "Malloc", "malloc", "Alloc",   "alloc",
        "Calloc", "calloc", "Realloc", "realloc",
        "Create", "create", "New",     "new",
        "Make",   "make",   "Build",   "build",
        "Allocate", // Verbose form (10+ chars)
    };

    for (alloc_suffixes) |suffix| {
        if (func_name.len > suffix.len and // Ensure has prefix (project name)
            std.mem.endsWith(u8, func_name, suffix))
        {
            return true;
        }
    }

    return false;
}

/// Check if a function name follows common project-level deallocator naming patterns.
/// Pairs with isProjectAllocFunction to form complete allocator/deallocator pairs.
///
/// Patterns detected:
///   - xxxFree, xxxDealloc, xxxDestroy, xxxRelease (deallocation)
///   - xxxDelete, xxxDrop, xxxClose (resource cleanup)
///   - xxxDispose, xxxFinalize (verbose forms)
///
/// Returns true if the function is likely a project-level deallocator.
pub fn isProjectFreeFunction(func_name: []const u8) bool {
    if (func_name.len < 4) return false; // Minimum: "Xxx" + "Free"

    // Suffix patterns: function must END with these
    const free_suffixes = [_][]const u8{
        "Free",    "free",    "Dealloc", "dealloc",
        "Destroy", "destroy", "Release", "release",
        "Delete",  "delete",  "Drop",    "drop",
        "Close",   "close",   "Dispose", "dispose",
        "Finalize", // Verbose form (8+ chars)
    };

    for (free_suffixes) |suffix| {
        if (func_name.len > suffix.len and // Ensure has prefix (project name)
            std.mem.endsWith(u8, func_name, suffix))
        {
            return true;
        }
    }

    return false;
}

/// Check if two function names form a likely allocator/deallocator pair based on
/// naming conventions. Used for project-level pair validation and debugging.
///
/// Examples of matched pairs:
///   - sqlite3Malloc ↔ sqlite3Free
///   - myObj_Create ↔ myObj_Destroy
///   - CustomAlloc ↔ CustomDealloc
///
/// Returns true if alloc_name and free_name share a common prefix and have
/// matching alloc/free suffixes.
pub fn areAllocatorPair(alloc_name: []const u8, free_name: []const u8) bool {
    if (alloc_name.len < 4 or free_name.len < 4) return false;

    // Extract common prefix (before the alloc/free suffix)
    const alloc_prefix = extractFunctionPrefix(alloc_name);
    const free_prefix = extractFunctionPrefix(free_name);

    // Must share the same base name (project/module prefix)
    if (alloc_prefix.len == 0 or free_prefix.len == 0) return false;
    if (!std.mem.eql(u8, alloc_prefix, free_prefix)) return false;

    // Verify one is alloc-pattern and other is free-pattern
    return isProjectAllocFunction(alloc_name) and isProjectFreeFunction(free_name);
}

/// Extract the base function name prefix before the alloc/free suffix.
/// Used by areAllocatorPair to match pairs like sqlite3Malloc → sqlite3.
fn extractFunctionPrefix(func_name: []const u8) []const u8 {
    const suffixes = [_][]const u8{
        "Malloc",   "malloc",   "Alloc",   "alloc",
        "Calloc",   "calloc",   "Realloc", "realloc",
        "Create",   "create",   "New",     "new",
        "Make",     "make",     "Build",   "build",
        "Allocate", "Free",     "free",    "Dealloc",
        "dealloc",  "Destroy",  "destroy", "Release",
        "release",  "Delete",   "delete",  "Drop",
        "drop",     "Close",    "close",   "Dispose",
        "dispose",  "Finalize",
    };

    for (suffixes) |suffix| {
        if (func_name.len > suffix.len and std.mem.endsWith(u8, func_name, suffix)) {
            return func_name[0 .. func_name.len - suffix.len];
        }
    }

    return func_name; // No known suffix found, return full name
}

// ============================================================================
// Extern Function Detection
// ============================================================================

/// Check if a callee name looks like an extern/FFI function.
pub fn is_extern_function(name: []const u8) bool {
    if (name.len == 0) return false;

    if (std.mem.startsWith(u8, name, "c_ffi_")) return true;
    if (std.mem.startsWith(u8, name, "ffi_")) return true;

    for (FFI_RETAINING_FUNCTIONS) |func| {
        if (word_boundary.isWordBoundaryMatch(name, func)) return true;
    }

    for (CALLBACK_TAKING_FUNCTIONS) |pattern| {
        if (word_boundary.isWordBoundaryMatch(name, pattern)) return true;
    }

    return false;
}

/// Check if function is a known deallocator that releases resources.
/// Used to reduce false positives in leak detection.
pub fn is_known_deallocator(func_name: []const u8) bool {
    inline for (.{ KNOWN_DEALLOCATORS.finalize_functions, KNOWN_DEALLOCATORS.close_functions, KNOWN_DEALLOCATORS.free_functions, KNOWN_DEALLOCATORS.destroy_functions }) |group| {
        for (group) |dealloc| {
            if (word_boundary.isWordBoundaryMatch(func_name, dealloc)) return true;
        }
    }
    return false;
}

fn isResourceCloseFunctionForIntentional(fn_name: []const u8) bool {
    const close_fns = [_][]const u8{
        "dlclose",         "munmap",         "fclose",    "close",
        "DeleteGlobalRef", "DeleteLocalRef", "Py_DECREF", "Py_XDECREF",
    };
    for (close_fns) |close_fn| {
        if (std.mem.indexOf(u8, fn_name, close_fn) != null) return true;
    }
    return false;
}

/// Check if pointer was freed by a known deallocator.
/// Returns true if the free operation was intentional.
pub fn is_intentional_free(func_name: []const u8) bool {
    return is_known_deallocator(func_name) or isResourceCloseFunctionForIntentional(func_name);
}

/// Check if a function may store/retain its pointer argument.
pub fn may_retain_pointer(callee_name: []const u8) bool {
    // v0.1.7: Check if this is an LLVM intrinsic that should be suppressed.
    if (isIntrinsicNoise(callee_name)) return false;

    if (is_extern_function(callee_name)) return true;

    const retaining_patterns = [_][]const u8{
        "register_", "add_",  "insert_", "push_",
        "store_",    "save_", "cache_",  "copy_",
        "retain",    "keep",  "hold",    "pass",
    };

    for (retaining_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }

    if (std.mem.startsWith(u8, callee_name, "set_")) {
        if (isOutputParamSetter(callee_name)) return false;
        return true;
    }

    return false;
}

fn isOutputParamSetter(func_name: []const u8) bool {
    // v0.1.7: Check for output parameter patterns.

    // Check if function has output parameters based on common patterns.
    const output_patterns = [_][]const u8{
        "_ip",  "_addr", "_port", "_fd",    "_sock",
        "_buf", "_len",  "_size", "_count", "_ptr",
        "_str", "_name", "_path", "_url",
    };
    for (output_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }

    // Also check for pp*, xpp* patterns (Windows API style).
    if (std.mem.startsWith(u8, func_name, "pp") or
        std.mem.startsWith(u8, func_name, "xpp"))
    {
        return true;
    }

    return false;
}

// ============================================================================
// Allocation Site Detection
// ============================================================================

/// v0.1.7: Check if a function is a known heap allocator using Allocator KB.
var g_allocator_kb: ?allocator_kb.AllocatorKB = null;
var g_allocator_kb_init_failed: bool = false;
var g_allocator_kb_lock = std.atomic.Value(bool).init(false);

pub fn getAllocatorKB() ?*allocator_kb.AllocatorKB {
    if (g_allocator_kb_init_failed) return null;
    if (g_allocator_kb != null) return &g_allocator_kb.?;

    // Spinlock: only one thread initializes at a time.
    while (g_allocator_kb_lock.swap(true, .acquire)) {}
    defer g_allocator_kb_lock.store(false, .release);

    // Double-check after acquiring lock.
    if (g_allocator_kb_init_failed) return null;
    if (g_allocator_kb != null) return &g_allocator_kb.?;

    g_allocator_kb = allocator_kb.AllocatorKB.init(std.heap.page_allocator) catch |err| {
        log.warn("AllocatorKB init failed: {any}, falling back to legacy detection", .{err});
        g_allocator_kb_init_failed = true;
        return null;
    };
    return &g_allocator_kb.?;
}

pub fn isHeapAllocFunction(func_name: []const u8) bool {
    for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
        if (std.mem.indexOf(u8, func_name, alloc_fn) != null) return true;
    }

    if (getAllocatorKB()) |kb| {
        if (kb.isAllocator(func_name)) return true;
    }

    return false;
}

/// v0.1.7: Check if a function is a known deallocator using Allocator KB.
pub fn isKnownDeallocFunction(func_name: []const u8) bool {
    if (getAllocatorKB()) |kb| {
        if (kb.isDeallocator(func_name)) return true;
    }

    return is_known_deallocator(func_name);
}

// ============================================================================
// Intrinsic Filter
// ============================================================================

/// v0.1.7: Check if a function is an LLVM intrinsic that should be suppressed.
/// Note: IntrinsicFilter.init() does not return an error, so no error handling needed.
var g_intrinsic_filter: ?intrinsic_filter.IntrinsicFilter = null;
var g_intrinsic_filter_lock = std.atomic.Value(bool).init(false);

pub fn getIntrinsicFilter() *intrinsic_filter.IntrinsicFilter {
    if (g_intrinsic_filter != null) return &g_intrinsic_filter.?;

    while (g_intrinsic_filter_lock.swap(true, .acquire)) {}
    defer g_intrinsic_filter_lock.store(false, .release);

    if (g_intrinsic_filter != null) return &g_intrinsic_filter.?;

    g_intrinsic_filter = intrinsic_filter.IntrinsicFilter.init();
    return &g_intrinsic_filter.?;
}

pub fn isIntrinsicNoise(func_name: []const u8) bool {
    const filter = getIntrinsicFilter();
    return filter.shouldSuppress(func_name);
}

// ============================================================================
// Pointer Origin Classification
// ============================================================================

/// Classify the allocation site of a pointer value.
pub fn classify_ptr_origin(
    inst: c.LLVMValueRef,
    opcode: c_uint,
    func: c.LLVMValueRef,
    allocator: std.mem.Allocator,
) !?PtrInfo {
    _ = func;
    switch (opcode) {
        c.LLVMAlloca => {
            const desc = try std.fmt.allocPrint(allocator, "stack allocation (alloca)", .{});
            return PtrInfo{
                .alloc_site = .stack,
                .source_inst = inst,
                .source_desc = desc,
                .needs_free = true,
            };
        },
        c.LLVMCall, c.LLVMInvoke => {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) == 0) return null;

            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) == 0) return null;

            const callee_name = std.mem.span(name_ptr);

            for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                    const desc = try std.fmt.allocPrint(allocator, "heap allocation via {s}()", .{callee_name});
                    return PtrInfo{
                        .alloc_site = .heap,
                        .source_inst = inst,
                        .source_desc = desc,
                        .needs_free = true,
                    };
                }
            }

            return null;
        },
        else => return null,
    }
}
