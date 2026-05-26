//! Resource Family Registry — Builtin Allocator/Deallocator Table and Query API.
//!
//! Central registry for all known resource (allocator) families.
//! Replaces per-language alloc/free matching with a unified family-based lookup.
//!
//! Design principles:
//!   - Family table is finite, stable, and enumerable (~50 entries max).
//!   - Language name is a hint, not a decision criterion.
//!   - Every lookup result carries EvidenceSource for auditability.
//!   - Unknown is safe: returns null/error rather than guessing wrong.

const std = @import("std");
const log = std.log.scoped(.family_registry);

const family = @import("family.zig");
pub const FamilyId = family.FamilyId;
pub const FamilyKind = family.FamilyKind;
pub const LifetimeDomain = family.LifetimeDomain;
pub const ResourceOpKind = family.ResourceOpKind;
pub const FamilyMatchResult = family.FamilyMatchResult;
pub const EvidenceSource = family.EvidenceSource;
pub const FamilyOp = family.FamilyOp;
pub const ResourceFamily = family.ResourceFamily;
pub const LookupContext = family.LookupContext;

// ============================================================================
// Builtin Family Definitions
// ============================================================================

/// Static table of all builtin resource families.
/// Each entry defines the family metadata and its compatible release families.
const builtin_families = [_]ResourceFamily{
    .{
        .id = .c_heap,
        .name = "c_heap",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .c_mmap,
        .name = "c_mmap",
        .kind = .mapped_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .cpp_new_scalar,
        .name = "cpp_new_scalar",
        .kind = .cpp_object,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .cpp_new_array,
        .name = "cpp_new_array",
        .kind = .cpp_object,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .rust_global,
        .name = "rust_global",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .rust_box,
        .name = "rust_box",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{.rust_global},
        .default_confidence = 0.9,
    },
    .{
        .id = .python_object,
        .name = "python_object",
        .kind = .refcounted_object,
        .lifetime_domain = .refcounted,
        .compatible_release_families = &.{ .python_mem, .python_mem_raw },
        .default_confidence = 1.0,
    },
    .{
        .id = .python_mem,
        .name = "python_mem",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{ .python_object, .python_mem_raw },
        .default_confidence = 1.0,
    },
    .{
        .id = .python_mem_raw,
        .name = "python_mem_raw",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{ .python_object, .python_mem },
        .default_confidence = 1.0,
    },
    .{
        .id = .java_local_ref,
        .name = "java_local_ref",
        .kind = .jni_ref,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .java_global_ref,
        .name = "java_global_ref",
        .kind = .jni_ref,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .csharp_hglobal,
        .name = "csharp_hglobal",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .csharp_cotask,
        .name = "csharp_cotask",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 1.0,
    },
    .{
        .id = .go_gc,
        .name = "go_gc",
        .kind = .gc_managed,
        .lifetime_domain = .gc,
        .compatible_release_families = &.{},
        .default_confidence = 0.8,
    },
    .{
        .id = .zig_allocator,
        .name = "zig_allocator",
        .kind = .heap_memory,
        .lifetime_domain = .manual,
        .compatible_release_families = &.{},
        .default_confidence = 0.6,
    },
};

// ============================================================================
// Builtin Operation Name Table
// ============================================================================

/// A single entry in the operation name lookup table.
/// Maps function names (canonical + aliases) to their family operation.
const OpEntry = struct {
    /// Canonical or alias name to match against.
    name: []const u8,
    /// The family operation this name corresponds to.
    op: FamilyOp,
};

/// Builtin acquire (allocator) function names organized by family.
/// Each entry maps a known allocator name to its FamilyOp.
const builtin_acquires = [_]OpEntry{
    // --- c_heap ---
    .{ .name = "malloc", .op = FamilyOp.init(.c_heap, .acquire, "malloc", .builtin_registry) },
    .{ .name = "calloc", .op = FamilyOp.init(.c_heap, .acquire, "calloc", .builtin_registry) },
    .{ .name = "realloc", .op = FamilyOp.init(.c_heap, .acquire, "realloc", .builtin_registry) },
    .{ .name = "reallocarray", .op = FamilyOp.init(.c_heap, .acquire, "reallocarray", .builtin_registry) },
    .{ .name = "valloc", .op = FamilyOp.init(.c_heap, .acquire, "valloc", .builtin_registry) },
    .{ .name = "pvalloc", .op = FamilyOp.init(.c_heap, .acquire, "pvalloc", .builtin_registry) },
    .{ .name = "aligned_alloc", .op = FamilyOp.init(.c_heap, .acquire, "aligned_alloc", .builtin_registry) },
    .{ .name = "memalign", .op = FamilyOp.init(.c_heap, .acquire, "memalign", .builtin_registry) },
    .{ .name = "posix_memalign", .op = FamilyOp.init(.c_heap, .acquire, "posix_memalign", .builtin_registry) },

    // --- c_mmap ---
    .{ .name = "mmap", .op = FamilyOp.init(.c_mmap, .acquire, "mmap", .builtin_registry) },
    .{ .name = "mmap64", .op = FamilyOp.init(.c_mmap, .acquire, "mmap64", .builtin_registry) },

    // --- cpp_new_scalar (Itanium C++ mangling) ---
    .{ .name = "_Znwm", .op = FamilyOp.init(.cpp_new_scalar, .acquire, "_Znwm", .builtin_registry) },
    .{ .name = "_Znwj", .op = FamilyOp.init(.cpp_new_scalar, .acquire, "_Znwj", .builtin_registry) },
    .{ .name = "_ZnwmSt11align_val_t", .op = FamilyOp.init(.cpp_new_scalar, .acquire, "_ZnwmSt11align_val_t", .builtin_registry) },
    .{ .name = "operator new", .op = FamilyOp.init(.cpp_new_scalar, .acquire, "operator new", .builtin_registry) },
    .{ .name = "operator new(unsigned long)", .op = FamilyOp.init(.cpp_new_scalar, .acquire, "operator new(unsigned long)", .builtin_registry) },

    // --- cpp_new_array ---
    .{ .name = "_Znam", .op = FamilyOp.init(.cpp_new_array, .acquire, "_Znam", .builtin_registry) },
    .{ .name = "_Znaj", .op = FamilyOp.init(.cpp_new_array, .acquire, "_Znaj", .builtin_registry) },
    .{ .name = "_ZnamSt11align_val_t", .op = FamilyOp.init(.cpp_new_array, .acquire, "_ZnamSt11align_val_t", .builtin_registry) },
    .{ .name = "operator new[]", .op = FamilyOp.init(.cpp_new_array, .acquire, "operator new[]", .builtin_registry) },

    // --- rust_global ---
    .{ .name = "__rust_alloc", .op = FamilyOp.init(.rust_global, .acquire, "__rust_alloc", .builtin_registry) },
    .{ .name = "__rust_alloc_zeroed", .op = FamilyOp.init(.rust_global, .acquire, "__rust_alloc_zeroed", .builtin_registry) },
    .{ .name = "__rust_realloc", .op = FamilyOp.init(.rust_global, .acquire, "__rust_realloc", .builtin_registry) },
    // Legacy/v0 mangled wrappers
    .{ .name = "_ZN5alloc5alloc18exchange_malloc17he", .op = FamilyOp.init(.rust_global, .acquire, "_ZN5alloc5alloc18exchange_malloc17he", .name_pattern) },
    .{ .name = "rust_alloc_error", .op = FamilyOp.init(.rust_global, .acquire, "rust_alloc_error", .name_pattern) },

    // --- python_object ---
    .{ .name = "PyObject_New", .op = FamilyOp.init(.python_object, .acquire, "PyObject_New", .builtin_registry) },
    .{ .name = "PyObject_NewVar", .op = FamilyOp.init(.python_object, .acquire, "PyObject_NewVar", .builtin_registry) },
    .{ .name = "PyType_GenericAlloc", .op = FamilyOp.init(.python_object, .acquire, "PyType_GenericAlloc", .builtin_registry) },
    .{ .name = "_PyObject_New", .op = FamilyOp.init(.python_object, .acquire, "_PyObject_New", .builtin_registry) },
    .{ .name = "_PyObject_NewVar", .op = FamilyOp.init(.python_object, .acquire, "_PyObject_NewVar", .builtin_registry) },

    // --- python_mem ---
    .{ .name = "PyMem_Malloc", .op = FamilyOp.init(.python_mem, .acquire, "PyMem_Malloc", .builtin_registry) },
    .{ .name = "PyMem_Calloc", .op = FamilyOp.init(.python_mem, .acquire, "PyMem_Calloc", .builtin_registry) },
    .{ .name = "PyMem_Realloc", .op = FamilyOp.init(.python_mem, .acquire, "PyMem_Realloc", .builtin_registry) },

    // --- python_mem_raw ---
    .{ .name = "PyMem_RawMalloc", .op = FamilyOp.init(.python_mem_raw, .acquire, "PyMem_RawMalloc", .builtin_registry) },
    .{ .name = "PyMem_RawCalloc", .op = FamilyOp.init(.python_mem_raw, .acquire, "PyMem_RawCalloc", .builtin_registry) },
    .{ .name = "PyMem_RawRealloc", .op = FamilyOp.init(.python_mem_raw, .acquire, "PyMem_RawRealloc", .builtin_registry) },

    // --- java_local_ref ---
    .{ .name = "NewLocalRef", .op = FamilyOp.init(.java_local_ref, .acquire, "NewLocalRef", .builtin_registry) },
    .{ .name = "JNIEnv_NewLocalRef", .op = FamilyOp.init(.java_local_ref, .acquire, "JNIEnv_NewLocalRef", .builtin_registry) },

    // --- java_global_ref ---
    .{ .name = "NewGlobalRef", .op = FamilyOp.init(.java_global_ref, .acquire, "NewGlobalRef", .builtin_registry) },
    .{ .name = "JNIEnv_NewGlobalRef", .op = FamilyOp.init(.java_global_ref, .acquire, "JNIEnv_NewGlobalRef", .builtin_registry) },

    // --- csharp_hglobal ---
    .{ .name = "Marshal.AllocHGlobal", .op = FamilyOp.init(.csharp_hglobal, .acquire, "Marshal.AllocHGlobal", .builtin_registry) },

    // --- csharp_cotask ---
    .{ .name = "CoTaskMemAlloc", .op = FamilyOp.init(.csharp_cotask, .acquire, "CoTaskMemAlloc", .builtin_registry) },

    // --- go_gc ---
    .{ .name = "runtime.mallocgc", .op = FamilyOp.init(.go_gc, .acquire, "runtime.mallocgc", .builtin_registry) },
};

/// Builtin release (deallocator) function names organized by family.
const builtin_releases = [_]OpEntry{
    // --- c_heap ---
    .{ .name = "free", .op = FamilyOp.init(.c_heap, .release, "free", .builtin_registry) },

    // --- c_mmap ---
    .{ .name = "munmap", .op = FamilyOp.init(.c_mmap, .release, "munmap", .builtin_registry) },

    // --- cpp_new_scalar ---
    .{ .name = "_ZdlPv", .op = FamilyOp.init(.cpp_new_scalar, .release, "_ZdlPv", .builtin_registry) },
    .{ .name = "_ZdlPvj", .op = FamilyOp.init(.cpp_new_scalar, .release, "_ZdlPvj", .builtin_registry) },
    .{ .name = "_ZdlPvSt11align_val_t", .op = FamilyOp.init(.cpp_new_scalar, .release, "_ZdlPvSt11align_val_t", .builtin_registry) },
    .{ .name = "operator delete", .op = FamilyOp.init(.cpp_new_scalar, .release, "operator delete", .builtin_registry) },

    // --- cpp_new_array ---
    .{ .name = "_ZdaPv", .op = FamilyOp.init(.cpp_new_array, .release, "_ZdaPv", .builtin_registry) },
    .{ .name = "_ZdaPvj", .op = FamilyOp.init(.cpp_new_array, .release, "_ZdaPvj", .builtin_registry) },
    .{ .name = "_ZdaPvSt11align_val_t", .op = FamilyOp.init(.cpp_new_array, .release, "_ZdaPvSt11align_val_t", .builtin_registry) },
    .{ .name = "operator delete[]", .op = FamilyOp.init(.cpp_new_array, .release, "operator delete[]", .builtin_registry) },

    // --- rust_global ---
    .{ .name = "__rust_dealloc", .op = FamilyOp.init(.rust_global, .release, "__rust_dealloc", .builtin_registry) },

    // --- python_object ---
    .{ .name = "PyObject_Del", .op = FamilyOp.init(.python_object, .release, "PyObject_Del", .builtin_registry) },
    .{ .name = "PyObject_Free", .op = FamilyOp.init(.python_object, .release, "PyObject_Free", .builtin_registry) },
    .{ .name = "_PyObject_Del", .op = FamilyOp.init(.python_object, .release, "_PyObject_Del", .builtin_registry) },

    // --- python_mem ---
    .{ .name = "PyMem_Free", .op = FamilyOp.init(.python_mem, .release, "PyMem_Free", .builtin_registry) },

    // --- python_mem_raw ---
    .{ .name = "PyMem_RawFree", .op = FamilyOp.init(.python_mem_raw, .release, "PyMem_RawFree", .builtin_registry) },

    // --- java_local_ref ---
    .{ .name = "DeleteLocalRef", .op = FamilyOp.init(.java_local_ref, .release, "DeleteLocalRef", .builtin_registry) },
    .{ .name = "JNIEnv_DeleteLocalRef", .op = FamilyOp.init(.java_local_ref, .release, "JNIEnv_DeleteLocalRef", .builtin_registry) },

    // --- java_global_ref ---
    .{ .name = "DeleteGlobalRef", .op = FamilyOp.init(.java_global_ref, .release, "DeleteGlobalRef", .builtin_registry) },
    .{ .name = "JNIEnv_DeleteGlobalRef", .op = FamilyOp.init(.java_global_ref, .release, "JNIEnv_DeleteGlobalRef", .builtin_registry) },

    // --- csharp_hglobal ---
    .{ .name = "Marshal.FreeHGlobal", .op = FamilyOp.init(.csharp_hglobal, .release, "Marshal.FreeHGlobal", .builtin_registry) },

    // --- csharp_cotask ---
    .{ .name = "CoTaskMemFree", .op = FamilyOp.init(.csharp_cotask, .release, "CoTaskMemFree", .builtin_registry) },
};

/// Builtin retain (reference count increment) function names.
/// These functions do NOT transfer ownership but increment a reference count.
const builtin_retains = [_]OpEntry{
    // --- python_object (reference counting) ---
    .{ .name = "Py_INCREF", .op = FamilyOp.init(.python_object, .retain, "Py_INCREF", .builtin_registry) },
    .{ .name = "Py_XINCREF", .op = FamilyOp.init(.python_object, .retain, "Py_XINCREF", .builtin_registry) },
    .{ .name = "PyList_SetItem", .op = FamilyOp.init(.python_object, .retain, "PyList_SetItem", .builtin_registry) },
    .{ .name = "PyDict_SetItem", .op = FamilyOp.init(.python_object, .retain, "PyDict_SetItem", .builtin_registry) },
    .{ .name = "PyTuple_SetItem", .op = FamilyOp.init(.python_object, .retain, "PyTuple_SetItem", .builtin_registry) },
    .{ .name = "PySet_Add", .op = FamilyOp.init(.python_object, .retain, "PySet_Add", .builtin_registry) },

    // --- java_local_ref ---
    .{ .name = "NewLocalRef", .op = FamilyOp.init(.java_local_ref, .retain, "NewLocalRef", .builtin_registry) },

    // --- java_global_ref ---
    .{ .name = "NewGlobalRef", .op = FamilyOp.init(.java_global_ref, .retain, "NewGlobalRef", .builtin_registry) },

    // Generic ARC-like patterns (weak match)
    .{ .name = "CFRetain", .op = FamilyOp.init(.invalid, .retain, "CFRetain", .name_pattern) },
    .{ .name = "IUnknown_AddRef", .op = FamilyOp.init(.invalid, .retain, "IUnknown_AddRef", .name_pattern) },
    .{ .name = "objc_retain", .op = FamilyOp.init(.invalid, .retain, "objc_retain", .name_pattern) },
};

// ============================================================================
// ResourceFamilyRegistry — Main registry struct
// ============================================================================

/// Thread-safe (read-only after init) registry for resource family lookups.
/// All builtin data is comptime-known; project model extensions are runtime.
pub const ResourceFamilyRegistry = struct {
    allocator: std.mem.Allocator,

    /// Sorted index into builtin tables for fast lookup.
    /// Built at init time from the comptime tables above.
    acquire_index: std.StringHashMapUnmanaged(FamilyOp),
    release_index: std.StringHashMapUnmanaged(FamilyOp),
    retain_index: std.StringHashMapUnmanaged(FamilyOp),

    pub fn init(allocator: std.mem.Allocator) !ResourceFamilyRegistry {
        var registry = ResourceFamilyRegistry{
            .allocator = allocator,
            .acquire_index = .{},
            .release_index = .{},
            .retain_index = .{},
        };

        try registry.buildIndex(&builtin_acquires, &registry.acquire_index);
        try registry.buildIndex(&builtin_releases, &registry.release_index);
        try registry.buildIndex(&builtin_retains, &registry.retain_index);

        return registry;
    }

    pub fn deinit(self: *ResourceFamilyRegistry) void {
        self.acquire_index.deinit(self.allocator);
        self.release_index.deinit(self.allocator);
        self.retain_index.deinit(self.allocator);
    }

    /// Build a string hashmap index from a comptime op table.
    fn buildIndex(self: *ResourceFamilyRegistry, table: []const OpEntry, index: *std.StringHashMapUnmanaged(FamilyOp)) !void {
        for (table) |entry| {
            try index.put(self.allocator, entry.name, entry.op);
        }
    }

    // ========================================================================
    // Query API
    // ========================================================================

    /// Look up whether a callee name is a known acquire (allocator) operation.
    /// Returns null if the name does not match any known allocator.
    pub fn lookupAcquire(self: *const ResourceFamilyRegistry, callee_name: []const u8, ctx: ?LookupContext) ?FamilyOp {
        _ = ctx;
        const canonical = canonicalize(callee_name);
        return self.acquire_index.get(canonical) orelse
            self.acquire_index.get(callee_name) orelse null;
    }

    /// Look up whether a callee name is a known release (deallocator) operation.
    /// Returns null if the name does not match any known deallocator.
    pub fn lookupRelease(self: *const ResourceFamilyRegistry, callee_name: []const u8, ctx: ?LookupContext) ?FamilyOp {
        _ = ctx;
        const canonical = canonicalize(callee_name);
        return self.release_index.get(canonical) orelse
            self.release_index.get(callee_name) orelse null;
    }

    /// Look up whether a callee name is a known retain (refcount increment) operation.
    /// Covers Py_INCREF, Py_XINCREF, CFRetain, ARC patterns, etc.
    pub fn lookupRetain(self: *const ResourceFamilyRegistry, callee_name: []const u8, ctx: ?LookupContext) ?FamilyOp {
        _ = ctx;
        const canonical = canonicalize(callee_name);
        return self.retain_index.get(canonical) orelse
            self.retain_index.get(callee_name) orelse null;
    }

    /// Compare an allocation family with a release family to determine validity.
    /// This is the core decision function that replaces `alloc_lang != free_lang`.
    ///
    /// Returns:
    ///   - `.same_family` — identical family, always valid
    ///   - `.compatible_family` — different but semantically compatible
    ///   - `.mismatch` — incompatible families, potential bug
    ///   - `.unknown_alloc` / `.unknown_release` — cannot classify one side
    pub fn compareFamilies(self: *const ResourceFamilyRegistry, alloc_family: FamilyId, release_family: FamilyId) FamilyMatchResult {
        _ = self;
        if (alloc_family == .invalid) {
            if (release_family == .invalid) return .unknown_both;
            return .unknown_alloc;
        }
        if (release_family == .invalid) return .unknown_release;

        if (alloc_family == release_family) return .same_family;

        // Check compatible release families
        for (builtin_families) |f| {
            if (f.id == alloc_family) {
                if (f.isCompatibleRelease(release_family)) {
                    return .compatible_family;
                }
                break;
            }
        }

        return .mismatch;
    }

    /// Get full metadata for a family by ID. Returns null for unknown families.
    pub fn getFamily(self: *const ResourceFamilyRegistry, id: FamilyId) ?*const ResourceFamily {
        _ = self;
        for (&builtin_families) |*f| {
            if (f.id == id) return f;
        }
        return null;
    }

    /// Get total number of registered builtin families.
    pub fn familyCount(self: *const ResourceFamilyRegistry) usize {
        _ = self;
        return builtin_families.len;
    }

    /// Iterate over all registered families. Caller provides the loop body.
    pub fn iterateFamilies(self: *const ResourceFamilyRegistry, context: anytype, comptime visitor_fn: fn (context: @TypeOf(context), family: *const ResourceFamily) bool) void {
        _ = self;
        for (&builtin_families) |*f| {
            if (!visitor_fn(context, f)) break;
        }
    }
};

// ============================================================================
// Name Canonicalization
// ============================================================================

/// Normalize a symbol name for registry lookup.
/// Handles common variations: demangled vs mangled, leading underscores, etc.
pub fn canonicalize(name: []const u8) []const u8 {
    // Strip leading "@" used by some IR formats (e.g., @malloc)
    var trimmed = name;
    if (trimmed.len > 0 and trimmed[0] == '@') {
        trimmed = trimmed[1..];
    }
    return trimmed;
}

/// Check if a name matches a pattern with wildcard support.
/// Supports suffix wildcards (e.g., "_ZN*" matches any Itanium-mangled name).
pub fn nameMatchesPattern(name: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return false;

    // Simple prefix match for patterns ending with *
    if (pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0 .. pattern.len - 1];
        return startsWith(name, prefix);
    }

    // Exact match (case-sensitive for C/C++ symbols)
    return std.mem.eql(u8, name, pattern);
}

/// Check if `haystack` starts with `needle`.
fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}
