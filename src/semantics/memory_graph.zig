//! Memory Graph module for pointer identity tracking and double-free detection.
//!
//! Tracks pointer EQUALITY (do two pointers point to the same allocation?)
//! rather than just counting alloc/free. This enables cross-alias double-free
//! detection: ptr1 = malloc(); ptr2 = ptr1; free(ptr2); free(ptr1).
//!
//! Added per-function alloc/free balance checking and content source
//! tracking. These signals help distinguish real borrow_escape from false
//! positives without project-specific whitelists.
//!
//! Uses direct allocator (no arena) for clean deinit and zero leaks.

const std = @import("std");

const zone = @import("zone_classifier.zig");
pub const ZoneKind = zone.ZoneKind;
pub const Language = zone.Language;

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
};

/// Represents a single allocation (malloc/calloc/dlopen/mmap/etc).
const AllocNode = struct {
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
    /// Language of the module/function where this was freed (? = not yet freed).
    free_lang: ?Language = null,
    /// All free operations on this allocation (path-sensitive).
    /// Multiple entries = potential double-free; use isDoubleFreedOnSamePath
    /// to distinguish same-path (real bug) from multi-path cleanup (not a bug).
    free_sites: std.ArrayList(FreeRecord),
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

/// Main memory graph structure.
///
/// R8.0: Unified pointer state graph. Tracks:
///   - Allocation nodes (alloc/alias/free) — pointer identity
///   - Call edges (call_arg/call_ret) — cross-function pointer flow
///   - Per-function alloc/free balance
///   - Content source tracking
pub const MemoryGraph = struct {
    /// Map from pointer value → AllocNode pointer.
    nodes: std.AutoHashMap(u64, *AllocNode),
    /// All allocated nodes (for cleanup).
    node_store: std.ArrayList(*AllocNode),
    /// Allocator reference.
    allocator: std.mem.Allocator,
    /// Next available allocation ID.
    next_id: u64,

    /// Per-function alloc/free counters for balance checking.
    func_counters: std.AutoHashMap(u64, FuncCounter),

    /// Content source tracking: maps a storage location (alloca/heap) to
    /// the SourceKind of the pointer value stored in it.
    content_sources: std.AutoHashMap(u64, SourceKind),

    // R8.0: Call edges — cross-function pointer flow tracking
    call_args: std.ArrayList(CallArgEdge),
    call_rets: std.ArrayList(CallRetEdge),
    call_arg_by_ptr: std.AutoHashMap(u64, std.ArrayList(u32)),
    call_arg_by_callee: std.StringHashMap(std.ArrayList(u32)),
    call_ret_by_callee: std.StringHashMap(std.ArrayList(u32)),
    call_ret_by_ptr: std.AutoHashMap(u64, std.ArrayList(u32)),

    /// Reverse index: alias pointer → canonical alloc pointer.
    /// Built by trackAlias. Enables O(1) reverse lookup instead of O(N) node scan.
    alias_to_canonical: std.AutoHashMap(u64, u64),

    /// V2: Set of weak aliases (borrowed pointers, not ownership transfers).
    /// Used to prevent false positives in double-free detection.
    /// A pointer in this set was borrowed, not owned, so freeing it is not a double-free error.
    weak_aliases: std.AutoHashMap(u64, void),

    /// BB control-flow edges: maps bb_id → set of successor bb_ids.
    /// Built by buildCFG(). Used for path-sensitive double-free analysis:
    /// if free_A.bb can reach free_B.bb via BB edges, they're on the same
    /// execution path → real double-free. If not reachable → multi-path cleanup.
    bb_edges: std.AutoHashMap(u32, std.AutoHashMap(u32, void)),

    /// Initializes a new memory graph.
    pub fn init(allocator: std.mem.Allocator) MemoryGraphError!MemoryGraph {
        return MemoryGraph{
            .nodes = std.AutoHashMap(u64, *AllocNode).init(allocator),
            .node_store = .{},
            .allocator = allocator,
            .next_id = 1,
            .func_counters = std.AutoHashMap(u64, FuncCounter).init(allocator),
            .content_sources = std.AutoHashMap(u64, SourceKind).init(allocator),
            .call_args = std.ArrayList(CallArgEdge).empty,
            .call_rets = std.ArrayList(CallRetEdge).empty,
            .call_arg_by_ptr = std.AutoHashMap(u64, std.ArrayList(u32)).init(allocator),
            .call_arg_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .call_ret_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .call_ret_by_ptr = std.AutoHashMap(u64, std.ArrayList(u32)).init(allocator),
            .alias_to_canonical = std.AutoHashMap(u64, u64).init(allocator),
            .weak_aliases = std.AutoHashMap(u64, void).init(allocator),
            .bb_edges = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(allocator),
        };
    }

    /// Deinitializes the memory graph. Frees all nodes and internal state.
    pub fn deinit(graph: *MemoryGraph) void {
        for (graph.node_store.items) |node| {
            node.aliases.deinit();
            node.free_sites.deinit(graph.allocator);
            graph.allocator.destroy(node);
        }
        graph.node_store.deinit(graph.allocator);
        graph.nodes.deinit();
        graph.func_counters.deinit();
        graph.content_sources.deinit();

        // R8.0: Free call edge data
        for (graph.call_args.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_args.deinit(graph.allocator);
        for (graph.call_rets.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_rets.deinit(graph.allocator);

        var arg_iter = graph.call_arg_by_ptr.iterator();
        while (arg_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_arg_by_ptr.deinit();

        var arg_callee_iter = graph.call_arg_by_callee.iterator();
        while (arg_callee_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_arg_by_callee.deinit();

        var ret_iter = graph.call_ret_by_callee.iterator();
        while (ret_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_ret_by_callee.deinit();

        var ret_ptr_iter = graph.call_ret_by_ptr.iterator();
        while (ret_ptr_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_ret_by_ptr.deinit();

        graph.alias_to_canonical.deinit();
        graph.weak_aliases.deinit(); // V2: Clean up weak aliases set
        // Deinitialize inner HashMaps before outer bb_edges HashMap
        var bb_iter = graph.bb_edges.iterator();
        while (bb_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        graph.bb_edges.deinit();

        graph.* = undefined;
    }

    // =====================================================================
    // Allocation tracking
    // =====================================================================

    /// Creates a new allocation node and returns its ID.
    /// Accepts raw pointer values as u64 to avoid cross-cimport type mismatches.
    /// `kind` indicates how this allocation was created (alloca, heap, resource, etc.).
    pub fn trackAlloc(
        graph: *MemoryGraph,
        alloc_inst_ptr: u64,
        ret_value_ptr: u64,
        kind: SourceKind,
        alloc_zone: ZoneKind,
        alloc_lang: Language,
    ) MemoryGraphError!u64 {
        const id = graph.next_id;
        graph.next_id += 1;

        const merkle_hash = hashValues(&.{
            alloc_inst_ptr,
            ret_value_ptr,
            id,
        });

        const node = try graph.allocator.create(AllocNode);
        errdefer graph.allocator.destroy(node);

        node.* = AllocNode{
            .id = id,
            .alloc_inst = alloc_inst_ptr,
            .merkle_root = merkle_hash,
            .aliases = std.AutoHashMap(u64, void).init(graph.allocator),
            .freed = false,
            .freed_by = null,
            .source_kind = kind,
            .zone = alloc_zone,
            .alloc_lang = alloc_lang,
            .free_sites = std.ArrayList(FreeRecord).empty,
        };
        errdefer node.aliases.deinit();
        try node.aliases.put(ret_value_ptr, {});
        try graph.nodes.put(ret_value_ptr, node);
        errdefer {
            _ = graph.nodes.remove(ret_value_ptr);
            node.aliases.deinit();
            graph.allocator.destroy(node);
        }
        try graph.node_store.append(graph.allocator, node);

        return id;
    }

    /// Records an alias relationship: from_val = to_val.
    /// Called when we see a store like "ptr_b = ptr_a".
    ///
    /// V2 Enhancement: Added is_weak parameter to distinguish:
    ///   - Strong alias (is_weak=false): Ownership transfer, double-free IS an error
    ///   - Weak alias (is_weak=true): Borrow only, freeing borrowed ptr is NOT double-free
    ///
    /// For backward compatibility, use trackAliasStrong() which defaults is_weak=false.
    pub fn trackAlias(graph: *MemoryGraph, from_val: u64, to_val: u64, is_weak: bool) !void {
        const target_node = graph.nodes.get(to_val) orelse {
            return MemoryGraphError.NodeNotFound;
        };

        try target_node.aliases.put(from_val, {});
        // V2: Store weak flag for downstream double-free decision making
        if (is_weak) {
            try graph.weak_aliases.put(from_val, {});
        }
        try graph.nodes.put(from_val, target_node);
        // Build reverse index for O(1) alias→canonical lookup
        try graph.alias_to_canonical.put(from_val, to_val);
    }

    /// Backward-compatible version of trackAlias that defaults to strong alias (is_weak=false).
    ///
    /// Use this function when you don't need weak alias tracking:
    ///   - Existing code that doesn't care about borrow vs ownership distinction
    ///   - V1-style analysis where all aliases are treated as strong
    ///   - Simple cases where double-free precision isn't critical
    ///
    /// For new code that needs weak alias support, use trackAlias() with explicit is_weak parameter.
    pub fn trackAliasStrong(graph: *MemoryGraph, from_val: u64, to_val: u64) !void {
        // Delegate to the full version with is_weak=false (strong alias)
        return trackAlias(graph, from_val, to_val, false);
    }

    /// Records a free operation and checks for double-free.
    /// Returns true if double-free detected, false otherwise.
    /// bb_id: basic block ID where this free occurred (0 = unknown).
    pub fn trackFree(
        graph: *MemoryGraph,
        free_inst_ptr: u64,
        ptr_val: u64,
        free_lang: Language,
        bb_id: u32,
    ) MemoryGraphError!bool {
        const node = graph.nodes.get(ptr_val) orelse {
            return false;
        };

        // Append to free_sites list (path-sensitive tracking).
        node.free_sites.append(graph.allocator, .{
            .free_inst = free_inst_ptr,
            .bb_id = bb_id,
            .free_lang = free_lang,
        }) catch {};

        const is_double = node.freed;
        if (!is_double) {
            node.freed = true;
            node.freed_by = free_inst_ptr;
            node.free_lang = free_lang;
        }
        return is_double;
    }

    // =====================================================================
    // Per-function alloc/free balance
    // =====================================================================

    /// Records a heap allocation in a function's counter.
    pub fn recordFuncAlloc(graph: *MemoryGraph, func_ptr: u64) void {
        const gop = graph.func_counters.getOrPut(func_ptr) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .allocs = 0, .frees = 0, .returns_pointer = false };
        }
        gop.value_ptr.allocs += 1;
    }

    /// Records a free call in a function's counter.
    pub fn recordFuncFree(graph: *MemoryGraph, func_ptr: u64) void {
        const gop = graph.func_counters.getOrPut(func_ptr) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .allocs = 0, .frees = 0, .returns_pointer = false };
        }
        gop.value_ptr.frees += 1;
    }

    /// Records that a function returns a pointer value.
    /// Used by borrow_escape analysis to identify sink functions
    /// (functions that consume pointers without returning them).
    pub fn recordFuncReturns(graph: *MemoryGraph, func_ptr: u64) void {
        const gop = graph.func_counters.getOrPut(func_ptr) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .allocs = 0, .frees = 0, .returns_pointer = false };
        }
        gop.value_ptr.returns_pointer = true;
    }

    /// Gets the alloc/free counter for a function.
    /// Returns zero-initialized counter if the function is not tracked.
    pub fn getFuncCounter(graph: *MemoryGraph, func_ptr: u64) FuncCounter {
        return graph.func_counters.get(func_ptr) orelse .{ .allocs = 0, .frees = 0, .returns_pointer = false };
    }

    // =====================================================================
    // Content source tracking
    // =====================================================================

    /// Records that a storage location (alloca/heap) now contains a pointer
    /// of the given source kind. Called on `store ptr %value, ptr %dest`
    /// when %value's source kind is known.
    pub fn recordContentSource(
        graph: *MemoryGraph,
        dest_ptr: u64,
        content_kind: SourceKind,
    ) void {
        graph.content_sources.put(dest_ptr, content_kind) catch {};
    }

    /// Gets the content source kind stored at a location.
    /// Returns .unknown if the location has no recorded content source.
    pub fn getContentSource(graph: *MemoryGraph, dest_ptr: u64) SourceKind {
        return graph.content_sources.get(dest_ptr) orelse .unknown;
    }

    /// Enhanced content source resolution with multi-level fallback:
    /// 1. content_sources map (explicitly recorded)
    /// 2. AllocNode.source_kind (how pointer was created: alloca/heap/etc.)
    /// 3. call_ret edges (returned from a function call)
    /// 4. .unknown if none match
    pub fn resolveContentSource(graph: *MemoryGraph, ptr_val: u64) SourceKind {
        const content = graph.content_sources.get(ptr_val);
        if (content) |kind| return kind;
        const node = graph.nodes.get(ptr_val);
        if (node) |n| return n.source_kind;
        if (graph.call_ret_by_ptr.get(ptr_val)) |indices| {
            if (indices.items.len > 0) return .call_result;
        }
        return .unknown;
    }

    // =====================================================================
    // R8.0: Call edge tracking
    // =====================================================================

    /// Records a call_arg edge: a pointer value passed as argument to a function.
    /// Used by ptr_lifetime when analyzing call/invoke instructions.
    pub fn trackCallArg(
        graph: *MemoryGraph,
        caller_inst: u64,
        callee_name: []const u8,
        arg_ptr: u64,
        arg_index: u32,
    ) !void {
        const name_owned = try graph.allocator.dupe(u8, callee_name);
        const edge_idx: u32 = @intCast(graph.call_args.items.len);
        try graph.call_args.append(graph.allocator, .{
            .caller_inst = caller_inst,
            .callee_name = name_owned,
            .arg_ptr = arg_ptr,
            .arg_index = arg_index,
        });
        // Index by ptr for fast lookup: "which calls receive this pointer?"
        const gop = try graph.call_arg_by_ptr.getOrPut(arg_ptr);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(u32).initCapacity(graph.allocator, 4);
        }
        try gop.value_ptr.append(graph.allocator, edge_idx);

        // Index by callee for fast lookup: "what args does this function receive?"
        const callee_gop = try graph.call_arg_by_callee.getOrPut(callee_name);
        if (!callee_gop.found_existing) {
            callee_gop.value_ptr.* = try std.ArrayList(u32).initCapacity(graph.allocator, 4);
        }
        try callee_gop.value_ptr.append(graph.allocator, edge_idx);
    }

    /// Records a call_ret edge: a pointer value returned from a function call.
    pub fn trackCallRet(
        graph: *MemoryGraph,
        caller_inst: u64,
        callee_name: []const u8,
        ret_ptr: u64,
    ) !void {
        const name_owned = try graph.allocator.dupe(u8, callee_name);
        const edge_idx: u32 = @intCast(graph.call_rets.items.len);
        try graph.call_rets.append(graph.allocator, .{
            .caller_inst = caller_inst,
            .callee_name = name_owned,
            .ret_ptr = ret_ptr,
        });
        // Index by callee for fast lookup: "what does this function return?"
        // Note: StringHashMap.getOrPut() manages key ownership internally.
        // When found_existing=true, the existing key is kept as-is (no leak).
        // When found_existing=false, a copy of callee_name is stored by the map.
        const gop = try graph.call_ret_by_callee.getOrPut(callee_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(u32).initCapacity(graph.allocator, 4);
        }
        try gop.value_ptr.append(graph.allocator, edge_idx);

        const ret_ptr_gop = try graph.call_ret_by_ptr.getOrPut(ret_ptr);
        if (!ret_ptr_gop.found_existing) {
            ret_ptr_gop.value_ptr.* = try std.ArrayList(u32).initCapacity(graph.allocator, 4);
        }
        try ret_ptr_gop.value_ptr.append(graph.allocator, edge_idx);
    }

    /// Query: Get all call_arg edges where `ptr_val` is passed as an argument.
    /// Returns slice of indices into call_args (caller owns nothing).
    pub fn getCallArgsForPtr(graph: *MemoryGraph, ptr_val: u64) []const u32 {
        if (graph.call_arg_by_ptr.get(ptr_val)) |list| return list.items;
        return &.{};
    }

    pub fn getCallRetsFromCallee(graph: *MemoryGraph, callee_name: []const u8) []const u32 {
        if (graph.call_ret_by_callee.get(callee_name)) |list| return list.items;
        return &.{};
    }

    pub fn getCallRetsForPtr(graph: *MemoryGraph, ptr_val: u64) []const u32 {
        if (graph.call_ret_by_ptr.get(ptr_val)) |list| return list.items;
        return &.{};
    }

    pub fn getCallArgsForCallee(graph: *MemoryGraph, callee_name: []const u8) []const u32 {
        if (graph.call_arg_by_callee.get(callee_name)) |list| return list.items;
        return &.{};
    }

    /// Query: Check if a pointer flows into any function call as an argument.
    pub fn isPassedAsArg(graph: *MemoryGraph, ptr_val: u64) bool {
        return graph.call_arg_by_ptr.contains(ptr_val);
    }

    /// Query: Check if a pointer is returned from any function call.
    pub fn isReturnedFromCall(graph: *MemoryGraph, ptr_val: u64) bool {
        return graph.call_ret_by_ptr.contains(ptr_val);
    }

    // =====================================================================
    // Queries
    // =====================================================================

    /// Checks if a pointer value has been freed.
    pub fn isFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;
        return node.freed;
    }

    /// Check if analysis should be skipped for a pointer based on semantic resolution.
    /// Returns true if the pointer has been identified as semantically safe
    /// (e.g., managed by a language runtime like Rust's Drop or Go's GC).
    pub fn shouldSkipAnalysis(graph: *const MemoryGraph, ptr_val: u64) bool {
        _ = graph;
        _ = ptr_val;
        // Placeholder: will be enhanced when semantic resolution is fully integrated
        return false;
    }

    /// Gets allocation info for a pointer.
    pub fn getAllocInfo(graph: *MemoryGraph, ptr_val: u64) ?*const AllocNode {
        return graph.nodes.get(ptr_val);
    }

    /// Gets the source kind of a pointer value.
    /// Returns .unknown if the pointer is not tracked.
    pub fn getSourceKind(graph: *MemoryGraph, ptr_val: u64) SourceKind {
        const node = graph.nodes.get(ptr_val) orelse return .unknown;
        return node.source_kind;
    }

    /// Resolves the effective source kind of a pointer value, considering
    /// both its own source kind and any content source stored at it.
    /// Priority: direct source > content source > unknown.
    ///
    /// Note: "direct source" means how the pointer itself was created.
    /// An alloca that contains a heap pointer still has direct source = .alloca.
    /// Use getContentSource() directly when you need the stored content's kind.
    pub fn resolveSourceKind(graph: *MemoryGraph, ptr_val: u64) SourceKind {
        // Direct: this pointer was created by alloca/malloc/etc.
        const direct = graph.getSourceKind(ptr_val);
        if (direct != .unknown) return direct;

        // Content: this pointer is a storage location that contains
        // a value with known source kind.
        const content = graph.getContentSource(ptr_val);
        if (content != .unknown) return content;

        return .unknown;
    }

    /// Resets the graph for reuse (clears all state but retains capacity).
    pub fn reset(graph: *MemoryGraph) void {
        for (graph.node_store.items) |node| {
            node.aliases.deinit();
            node.free_sites.deinit(graph.allocator);
            graph.allocator.destroy(node);
        }
        graph.node_store.clearRetainingCapacity();
        graph.nodes.clearRetainingCapacity();
        graph.func_counters.clearRetainingCapacity();
        graph.content_sources.clearRetainingCapacity();

        for (graph.call_args.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_args.clearRetainingCapacity();
        for (graph.call_rets.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_rets.clearRetainingCapacity();

        // M14 FIX: Clear weak_aliases to prevent stale data across resets.
        // Previous implementation cleared all other HashMap fields but missed this one,
        // causing weak alias information from previous analyses to leak into new ones.
        graph.weak_aliases.clearRetainingCapacity();

        var arg_iter = graph.call_arg_by_ptr.iterator();
        while (arg_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_arg_by_ptr.clearRetainingCapacity();

        var arg_callee_iter = graph.call_arg_by_callee.iterator();
        while (arg_callee_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_arg_by_callee.clearRetainingCapacity();

        var ret_iter = graph.call_ret_by_callee.iterator();
        while (ret_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_ret_by_callee.clearRetainingCapacity();

        var ret_ptr_iter = graph.call_ret_by_ptr.iterator();
        while (ret_ptr_iter.next()) |entry| {
            entry.value_ptr.deinit(graph.allocator);
        }
        graph.call_ret_by_ptr.clearRetainingCapacity();

        graph.alias_to_canonical.clearRetainingCapacity();

        // P2: Clear BB control-flow edges for path-sensitive analysis.
        var bb_edge_iter = graph.bb_edges.iterator();
        while (bb_edge_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        graph.bb_edges.clearRetainingCapacity();

        graph.next_id = 1;
    }

    // =====================================================================
    // Advanced Detection Methods
    // =====================================================================

    /// Checks if a pointer is used after being freed via an alias.
    ///
    /// This detects the pattern:
    ///   ptr1 = malloc();
    ///   ptr2 = ptr1;      // alias
    ///   free(ptr1);
    ///   use(ptr2);        // BUG: use after free via alias
    ///
    /// Arguments:
    ///   ptr_val - The pointer value being used
    ///   use_inst - The instruction using the pointer
    ///
    /// Returns:
    ///   The allocation node if use-after-free detected, null otherwise
    pub fn isUseAfterFreeViaAlias(graph: *MemoryGraph, ptr_val: u64, use_inst: u64) ?*const AllocNode {
        _ = use_inst; // Future: use for ordering check

        // Find the allocation this pointer belongs to
        const node = graph.nodes.get(ptr_val) orelse return null;

        // Check if the allocation has been freed
        if (!node.freed) return null;

        // This pointer is being used after the allocation was freed
        return node;
    }

    /// Finds all aliases of a pointer that form a use-after-free chain.
    ///
    /// Given a freed pointer, returns all other pointers that alias to it
    /// and could be used after the free, creating a use-after-free bug.
    ///
    /// Arguments:
    ///   ptr_val - The pointer that was freed
    ///
    /// Returns:
    ///   Slice of alias pointer values (caller owns the memory)
    pub fn findDangerousAliases(graph: *MemoryGraph, ptr_val: u64, allocator: std.mem.Allocator) ![]u64 {
        const node = graph.nodes.get(ptr_val) orelse return &.{};
        if (!node.freed) return &.{};

        var aliases = std.ArrayList(u64).init(allocator);
        errdefer aliases.deinit();

        var iter = node.aliases.iterator();
        while (iter.next()) |entry| {
            try aliases.append(entry.key_ptr.*);
        }

        return aliases.items;
    }

    /// Validates ownership transfer between functions.
    ///
    /// Checks if a function correctly transfers ownership of a resource
    /// to another function. This helps detect:
    ///   - Transfer without ownership (caller doesn't own it)
    ///   - Missing transfer (caller should transfer but doesn't)
    ///   - Double transfer (ownership transferred twice)
    ///
    /// Arguments:
    ///   from_func - Function transferring ownership
    ///   to_func - Function receiving ownership
    ///   ptr_val - The pointer being transferred
    ///
    /// Returns:
    ///   OwnershipTransferStatus indicating if the transfer is valid
    pub fn validateOwnershipTransfer(
        graph: *MemoryGraph,
        from_func: u64,
        to_func: u64,
        ptr_val: u64,
    ) OwnershipTransferStatus {
        const node = graph.nodes.get(ptr_val) orelse return .not_tracked;

        // Check if from_func has ownership to transfer
        const from_counter = graph.getFuncCounter(from_func);
        if (from_counter.net() <= 0) {
            // from_func doesn't have extra ownership to transfer
            return .transfer_without_ownership;
        }

        // Check if the pointer is already freed
        if (node.freed) {
            return .transfer_after_free;
        }

        // Check if to_func already has ownership
        const to_counter = graph.getFuncCounter(to_func);
        if (to_counter.net() > 0) {
            // to_func already owns something, might be double transfer
            return .potential_double_transfer;
        }

        return .valid;
    }

    /// Analyzes the complete lifecycle of a resource.
    ///
    /// Traces a resource from allocation through all uses to deallocation,
    /// providing a comprehensive view for debugging and leak detection.
    ///
    /// Arguments:
    ///   alloc_inst - The allocation instruction to analyze
    ///   allocator - Allocator for result arrays
    ///
    /// Returns:
    ///   ResourceLifecycle with complete trace information
    pub fn analyzeLifecycle(
        graph: *MemoryGraph,
        alloc_inst: u64,
        allocator: std.mem.Allocator,
    ) !ResourceLifecycle {
        const node = graph.nodes.get(alloc_inst) orelse return .{
            .allocation_site = alloc_inst,
            .source_kind = .unknown,
            .aliases = &.{},
            .is_freed = false,
            .free_site = null,
        };

        var aliases = std.ArrayList(u64).init(allocator);
        errdefer aliases.deinit();

        var iter = node.aliases.iterator();
        while (iter.next()) |entry| {
            try aliases.append(entry.key_ptr.*);
        }

        return ResourceLifecycle{
            .allocation_site = node.alloc_inst,
            .source_kind = node.source_kind,
            .aliases = aliases.items,
            .is_freed = node.freed,
            .free_site = node.freed_by,
        };
    }

    /// R8.0: Check if a pointer is leaked by tracing cross-function propagation.
    ///
    /// A pointer is considered leaked when:
    ///   1. It was allocated (has an AllocNode) and NOT freed
    ///   2. It escaped the current function via a call_arg edge
    ///   3. No corresponding call_ret edge returns ownership to the caller
    ///
    /// This detects patterns like:
    ///   ```c
    ///   void caller() {
    ///       void* p = malloc(100);
    ///       process(p);   // p escapes via call_arg, never comes back
    ///       // no free(p) → leak across function boundary
    ///   }
    ///   ```
    ///
    /// Returns true if the pointer appears to be leaked across a function boundary.
    pub fn isLeaked(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;
        if (node.freed) return false;

        const arg_indices = graph.getCallArgsForPtr(ptr_val);
        if (arg_indices.len == 0) return false;

        // C3 FIX: Use call_ret_by_ptr index instead of O(N) scan
        // Previously: for (graph.call_rets.items) - scans ALL returns
        // Now: Only check returns for this specific pointer
        const ret_indices = graph.call_ret_by_ptr.get(ptr_val) orelse return true;

        for (arg_indices) |arg_idx| {
            const arg_edge = &graph.call_args.items[arg_idx];
            var returned = false;

            for (ret_indices.items) |ret_idx| {
                const ret_edge = &graph.call_rets.items[ret_idx];
                // FIX-4 (CTX-2): Also match ret_ptr to reduce false positives
                if (ret_edge.caller_inst == arg_edge.caller_inst) {
                    returned = true;
                    break;
                }
            }
            if (!returned) return true;
        }

        return false;
    }

    /// R8.0: Check if a pointer is double-freed, including through alias closure
    /// and cross-function call chains.
    ///
    /// Detection layers:
    ///   1. Direct: the AllocNode for ptr_val is already marked freed
    ///   2. Alias closure: any alias of ptr_val shares the same AllocNode which is freed,
    ///      and ptr_val itself is being freed again
    ///   3. Call chain: ptr_val was passed as arg to a function call, and within that
    ///      call's context, a free operation targets the same or an aliased pointer
    ///
    /// Returns true if this free operation would be a double-free.
    pub fn isDoubleFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;

        if (node.freed) return true;

        var alias_iter = node.aliases.iterator();
        while (alias_iter.next()) |entry| {
            const alias_node = graph.nodes.get(entry.key_ptr.*) orelse continue;
            if (alias_node.freed and alias_node.id == node.id) return true;
        }

        // C3 FIX: Use call_ret_by_ptr index instead of O(N) scan
        // Previously: for (graph.call_rets.items) - scans ALL returns
        // Now: Only check returns for this specific pointer
        const arg_indices = graph.getCallArgsForPtr(ptr_val);
        for (arg_indices) |arg_idx| {
            const arg_edge = &graph.call_args.items[arg_idx];

            // Check if this pointer was returned from the same call site
            if (graph.call_ret_by_ptr.get(ptr_val)) |ret_indices| {
                for (ret_indices.items) |ret_idx| {
                    const ret_edge = &graph.call_rets.items[ret_idx];
                    // H22 FIX: Check if the returned pointer WAS freed AND matches our node
                    if (ret_edge.caller_inst == arg_edge.caller_inst) {
                        const ret_node = graph.nodes.get(ret_edge.ret_ptr) orelse continue;
                        if (ret_node.freed and ret_node.id == node.id) return true;
                    }
                }
            }
        }

        return false;
    }

    // =====================================================================
    // P2: Path-sensitive double-free analysis via BB control-flow graph
    // =====================================================================

    /// Add a directed edge in the BB control-flow graph.
    /// Called during CFG construction: from_bb → to_bb means control can
    /// flow from from_bb to to_bb (i.e., a branch/fall-through).
    pub fn addBBEdge(graph: *MemoryGraph, from_bb: u32, to_bb: u32) !void {
        if (from_bb == to_bb) return; // Skip self-edges
        const gop = try graph.bb_edges.getOrPut(from_bb);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(u32, void).init(graph.allocator);
        }
        try gop.value_ptr.put(to_bb, {});
    }

    /// Check if one BB can reach another via the control-flow graph.
    /// Uses BFS with visited set to handle cycles (loops).
    pub fn isBBReachable(graph: *MemoryGraph, from_bb: u32, to_bb: u32, visited: *std.AutoHashMap(u32, void)) bool {
        if (from_bb == to_bb) return true;
        if (visited.contains(from_bb)) return false;
        visited.put(from_bb, {}) catch return false;

        const successors = graph.bb_edges.get(from_bb) orelse return false;
        var succ_iter = successors.iterator();
        while (succ_iter.next()) |entry| {
            if (graph.isBBReachable(entry.key_ptr.*, to_bb, visited)) return true;
        }
        return false;
    }

    /// Path-sensitive double-free detection.
    ///
    /// Returns true if the same allocation is freed on the SAME execution path,
    /// i.e., there exists a pair of free sites (A, B) such that:
    ///   - A's BB can reach B's BB via control-flow edges
    ///   (meaning execution CAN flow from A to B, so B would free already-freed memory)
    ///
    /// Returns false if all free sites are on MUTUALLY EXCLUSIVE paths:
    ///   - Different branches of an if-else (A's BB cannot reach B's BB)
    ///   - This is multi-path cleanup, NOT a double-free bug.
    ///
    /// If BB info is missing (bb_id=0 for all sites), falls back to
    /// conservative behavior: return true (potential double-free).
    pub fn isDoubleFreedOnSamePath(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;

        // Need at least 2 free sites for double-free
        if (node.free_sites.items.len < 2) return false;

        // Check if any BB info is available
        var has_bb_info = false;
        for (node.free_sites.items) |site| {
            if (site.bb_id != 0) {
                has_bb_info = true;
                break;
            }
        }

        // Fallback: no BB info → cannot determine path sensitivity.
        // Conservative: assume same path (report potential double-free).
        if (!has_bb_info) return node.freed;

        // Same-BB check: if two frees are in the same BB, that's always
        // a real double-free (sequential execution, no branch between them).
        for (node.free_sites.items, 0..) |site_a, i| {
            for (node.free_sites.items[i + 1 ..]) |site_b| {
                if (site_a.bb_id != 0 and site_a.bb_id == site_b.bb_id) {
                    return true; // Same BB = same path = real double-free
                }
            }
        }

        // Cross-BB reachability: check if free_A's BB can reach free_B's BB.
        // If yes, they're on the same execution path → real double-free.
        for (node.free_sites.items, 0..) |site_a, i| {
            if (site_a.bb_id == 0) continue;
            for (node.free_sites.items[i + 1 ..]) |site_b| {
                if (site_b.bb_id == 0) continue;
                // Check A → B reachability
                var visited_ab = std.AutoHashMap(u32, void).init(graph.allocator);
                defer visited_ab.deinit();
                if (graph.isBBReachable(site_a.bb_id, site_b.bb_id, &visited_ab)) {
                    return true;
                }
                // Check B → A reachability
                var visited_ba = std.AutoHashMap(u32, void).init(graph.allocator);
                defer visited_ba.deinit();
                if (graph.isBBReachable(site_b.bb_id, site_a.bb_id, &visited_ba)) {
                    return true;
                }
            }
        }

        // No pair of free sites is on the same execution path.
        // All frees are on mutually exclusive paths → multi-path cleanup.
        return false;
    }

    /// Descriptor for an FFI/unsafe boundary call. Used by isOnDangerPath without
    /// depending on pass.zig's CrossLangEdge type (avoids circular import).
    pub const DangerSurface = struct {
        callee_name: []const u8,
        is_ffi_boundary: bool,
    };

    /// The ONE question that determines whether we care about a pointer.
    ///
    /// Returns a DangerPathKind describing WHY this pointer matters (or .none if it
    /// doesn't). This is the sole gate between Tier 1 (pass-through / statistics)
    /// and Tier 2 (strict analysis with issue reporting).
    ///
    /// Detection order matters — check call edges FIRST (covers function parameter
    /// pointers that have no AllocNode), then AllocNode fields:
    ///   (b) ptr flows into FFI boundary as argument → .ffi_arg
    ///   (c) ptr returns from FFI boundary → .ffi_ret
    ///   (e) allocated in .unsafe zone → .unsafe_alloc
    ///   (a) alloc_lang != free_lang → .cross_lang_lifecycle
    ///   (d) alias closure (with cycle detection via visited set)
    pub fn isOnDangerPath(
        graph: *MemoryGraph,
        ptr_val: u64,
        ffi_boundaries: []const MemoryGraph.DangerSurface,
        visited: *std.AutoHashMap(u64, void),
        ffi_set: ?*const std.StringHashMap(void),
    ) DangerPathKind {
        // H1 FIX: Add ptr_val to visited at entry to prevent infinite recursion
        // when alias closure contains cycles back to the original pointer.
        if (visited.contains(ptr_val)) return .none;
        visited.put(ptr_val, {}) catch {
            // Allocation failure in visited set - cannot safely continue recursion.
            // Return .none to prevent potential infinite loop.
            return .none;
        };

        // Build callee_name set for O(1) lookup (only once at top-level call).
        // PERF: Only allocate local_ffi_set when ffi_set is null (top-level call).
        // Recursive calls always receive a valid ffi_set, so this is a one-time cost.
        var local_ffi_set: std.StringHashMap(void) = undefined;
        var local_ffi_set_needs_deinit = false;
        const set: *const std.StringHashMap(void) = if (ffi_set) |s| s else blk: {
            local_ffi_set = std.StringHashMap(void).init(graph.allocator);
            local_ffi_set_needs_deinit = true;
            for (ffi_boundaries) |b| {
                if (b.is_ffi_boundary) {
                    local_ffi_set.put(b.callee_name, {}) catch {};
                }
            }
            break :blk &local_ffi_set;
        };
        defer {
            if (local_ffi_set_needs_deinit) local_ffi_set.deinit();
        }

        // (b): Check if ptr flows into any FFI boundary call as argument.
        const arg_indices = graph.getCallArgsForPtr(ptr_val);
        for (arg_indices) |idx| {
            const arg_edge = &graph.call_args.items[idx];
            if (set.contains(arg_edge.callee_name)) {
                return .ffi_arg;
            }
        }

        // (c): Check if ptr returns from any FFI boundary call.
        const ret_indices = graph.getCallRetsForPtr(ptr_val);
        for (ret_indices) |idx| {
            const ret_edge = &graph.call_rets.items[idx];
            if (set.contains(ret_edge.callee_name)) {
                return .ffi_ret;
            }
        }

        // (a)/(e): AllocNode-based checks (only for pointers with allocation info).
        const node = graph.nodes.get(ptr_val) orelse return .none;

        if (node.zone == .unsafe) {
            return .unsafe_alloc;
        }

        if (node.freed) {
            const fl = node.free_lang orelse return .none;
            if (node.alloc_lang != fl) {
                return .cross_lang_lifecycle;
            }
        }

        // (d): Alias closure — if any alias is on danger path, so are we.
        var alias_iter = node.aliases.iterator();
        while (alias_iter.next()) |entry| {
            const alias_ptr = entry.key_ptr.*;
            if (visited.contains(alias_ptr)) continue;
            visited.put(alias_ptr, {}) catch {};
            const kind = isOnDangerPath(graph, alias_ptr, ffi_boundaries, visited, set);
            if (kind != .none) return kind;
        }

        return .none;
    }
};

/// FNV-1a hash with wrapping multiplication.
/// Wrapping is intentional: hash values are not ordered, overflow is expected.
fn hashValues(values: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (values) |val| {
        hash ^= val;
        hash = hash *% 0x100000001b3;
    }
    return hash;
}

// Re-export FuzzyMatcher from separate module
pub const FuzzyMatcher = @import("memory_graph_fuzzy.zig").FuzzyMatcher;
pub const FnClass = @import("memory_graph_fuzzy.zig").FnClass;

// Tests are in memory_graph_test.zig (imported to run tests)
const _tests = @import("memory_graph_test.zig");
