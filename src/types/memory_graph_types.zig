//! Type definitions for Memory Graph module.
//!
//! Extracted from memory_graph.zig for better code organization.
//! Contains pure type definitions used by the memory graph system.

const std = @import("std");
const log = std.log.scoped(.memory_graph_types);

const zone = @import("../semantics/zone_classifier.zig");
pub const ZoneKind = zone.ZoneKind;
pub const Language = zone.Language;

const resource_family = @import("../semantics/resource/family.zig");
pub const FamilyId = resource_family.FamilyId;

const escape_mod = @import("../semantics/resource/escape.zig");
pub const EscapeKind = escape_mod.EscapeKind;
pub const EscapeRecord = escape_mod.EscapeRecord;
pub const EscapeList = escape_mod.EscapeList;

/// Error set for memory graph operations.
pub const MemoryGraphError = error{
    OutOfMemory,
    NodeNotFound,
};

/// Source kind of an allocation node — how was this pointer created?
pub const SourceKind = enum(u8) {
    /// Created by an LLVM alloca instruction (stack).
    alloca,
    /// Created by a heap allocation (malloc, calloc, realloc, etc.).
    heap_alloc,
    /// Created by a resource allocation (dlopen, mmap, fopen, socket, etc.).
    resource_alloc,
    /// Created by a function call whose return type is unknown.
    call_result,
    /// Unknown source.
    unknown,
};

/// Per-function alloc/free balance counter.
/// Tracks how many heap allocations and frees a function performs,
/// and whether the function returns a pointer value.
pub const FuncCounter = struct {
    /// Number of heap/resource allocations in this function.
    allocs: u32,
    /// Number of free calls in this function.
    frees: u32,
    /// Whether this function returns a pointer value.
    /// Functions that don't return pointers are likely "sink" functions
    /// that consume their arguments rather than forwarding them.
    returns_pointer: bool,

    /// Net allocation count: positive means more allocs than frees.
    pub fn net(self: FuncCounter) i64 {
        return @as(i64, @intCast(self.allocs)) - @as(i64, @intCast(self.frees));
    }

    /// Whether this function has any heap operations at all.
    pub fn hasHeapOps(self: FuncCounter) bool {
        return self.allocs > 0 or self.frees > 0;
    }
};

/// Status of an ownership transfer between functions.
pub const OwnershipTransferStatus = enum(u8) {
    /// Transfer is valid and correct.
    valid,
    /// Pointer is not tracked in the memory graph.
    not_tracked,
    /// Attempting to transfer ownership that the function doesn't have.
    transfer_without_ownership,
    /// Attempting to transfer ownership after the pointer was freed.
    transfer_after_free,
    /// Potential double transfer (ownership already transferred).
    potential_double_transfer,
};

/// Complete lifecycle information for a resource.
pub const ResourceLifecycle = struct {
    /// The instruction that allocated this resource.
    allocation_site: u64,
    /// How the resource was created (heap, stack, resource, etc.).
    source_kind: SourceKind,
    /// All pointer values that alias to this allocation.
    aliases: []const u64,
    /// Whether the resource has been freed.
    is_freed: bool,
    /// The instruction that freed this resource (if any).
    free_site: ?u64,
};

// R8.0: Call edge types for cross-function pointer flow tracking.

/// A call_arg edge: pointer passed as argument to a function.
pub const CallArgEdge = struct {
    /// The call instruction (raw pointer as u64).
    caller_inst: u64,
    /// Callee function name (owned by the containing MemoryGraph).
    callee_name: []const u8,
    /// The pointer value passed as argument.
    arg_ptr: u64,
    /// Argument index (0-based).
    arg_index: u32,
};

/// A call_ret edge: pointer returned from a function call.
pub const CallRetEdge = struct {
    /// The call instruction (raw pointer as u64).
    caller_inst: u64,
    /// Callee function name (owned by the containing MemoryGraph).
    callee_name: []const u8,
    /// The returned pointer value.
    ret_ptr: u64,
};

/// Per-free-site record for path-sensitive double-free analysis.
/// Each free() call on the same allocation is recorded separately,
/// along with its basic block ID for control-flow reachability analysis.
pub const FreeRecord = struct {
    /// The instruction that performed the free (raw pointer value).
    free_inst: u64,
    /// Basic block ID where this free occurred (0 = unknown).
    bb_id: u32,
    /// Language of the free site.
    free_lang: Language,
    /// Resource family of the free/deallocator (from family registry).
    /// null = unclassified; .invalid = lookup failed.
    release_family: ?FamilyId = null,
};

/// Represents a single allocation (malloc/calloc/dlopen/mmap/etc).
pub const AllocNode = struct {
    /// Unique identifier for this allocation.
    id: u64,
    /// The instruction that performed the allocation (raw pointer value).
    alloc_inst: u64,
    /// Merkle hash for this allocation.
    merkle_root: u64,
    /// Set of all pointer values that alias to this allocation.
    aliases: std.AutoHashMap(u64, void),
    /// Whether this allocation has been freed (at least once).
    freed: bool,
    /// The instruction that freed this allocation (raw pointer value).
    /// DEPRECATED: Use free_sites for path-sensitive analysis.
    /// Kept for backward compatibility with downstream passes.
    freed_by: ?u64,
    /// How this allocation was created.
    source_kind: SourceKind,
    /// Zone where this allocation occurred (.safe/.ffi/.unsafe/.runtime_internal).
    zone: ZoneKind = .unknown,
    /// Language of the module/function where this allocation was made.
    alloc_lang: Language = .unknown,
    /// Resource family of the allocator (from family registry).
    /// null = unclassified; .invalid = lookup failed.
    alloc_family: ?FamilyId = null,
    /// Language of the module/function where this was freed (? = not yet freed).
    free_lang: ?Language = null,
    /// All free operations on this allocation (path-sensitive).
    /// Multiple entries = potential double-free; use isDoubleFreedOnSamePath
    /// to distinguish same-path (real bug) from multi-path cleanup (not a bug).
    free_sites: std.ArrayList(FreeRecord),
    /// All escape events for this allocation.
    /// Tracks how this pointer escaped the allocating function's scope:
    /// return_to_caller, out_param, field_store, global_store,
    /// callback, thread, container, consumed_by_function.
    /// null = no escapes recorded yet (or not initialized).
    escapes: ?*EscapeList,
    /// PERF v5: Alias closure version number for incremental updates.
    /// When == global_closure_version, this node's alias subgraph was already
    /// traversed in the current pass — skip redundant DFS.
    closure_version: u64 = 0,
};

/// Result of isOnDangerPath — why a pointer matters (or doesn't).
pub const DangerPathKind = enum {
    /// Not on any danger path → Tier 1, pass through (statistics only).
    none,
    /// Allocated inside an .unsafe block → Tier 2, strict analysis.
    unsafe_alloc,
    /// Alloc and free happened in different languages → Tier 2.
    cross_lang_lifecycle,
    /// Pointer flows into an FFI boundary call as argument → Tier 2.
    ffi_arg,
    /// Pointer returns from an FFI boundary call → Tier 2.
    ffi_ret,
};

/// Descriptor for an FFI/unsafe boundary call. Used by isOnDangerPath without
/// depending on pass.zig's CrossLangEdge type (avoids circular import).
pub const DangerSurface = struct {
    callee_name: []const u8,
    is_ffi_boundary: bool,
};

/// FNV-1a hash with wrapping multiplication.
/// Wrapping is intentional: hash values are not ordered, overflow is expected.
pub fn hashValues(values: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (values) |val| {
        hash ^= val;
        hash = hash *% 0x100000001b3;
    }
    return hash;
}
