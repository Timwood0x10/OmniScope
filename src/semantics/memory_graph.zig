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
    /// Whether this allocation has been freed.
    freed: bool,
    /// The instruction that freed this allocation (raw pointer value).
    freed_by: ?u64,
    /// How this allocation was created.
    source_kind: SourceKind,
    /// Zone where this allocation occurred (.safe/.ffi/.unsafe/.runtime_internal).
    zone: ZoneKind = .unknown,
    /// Language of the module/function where this allocation was made.
    alloc_lang: Language = .unknown,
    /// Language of the module/function where this was freed (? = not yet freed).
    free_lang: ?Language = null,
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
    call_arg_by_ptr: std.AutoHashMap(u64, []const u32),
    call_ret_by_callee: std.StringHashMap([]const u32),

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
            .call_arg_by_ptr = std.AutoHashMap(u64, []const u32).init(allocator),
            .call_ret_by_callee = std.StringHashMap([]const u32).init(allocator),
        };
    }

    /// Deinitializes the memory graph. Frees all nodes and internal state.
    pub fn deinit(graph: *MemoryGraph) void {
        for (graph.node_store.items) |node| {
            node.aliases.deinit();
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
            graph.allocator.free(entry.value_ptr.*);
        }
        graph.call_arg_by_ptr.deinit();

        var ret_iter = graph.call_ret_by_callee.iterator();
        while (ret_iter.next()) |entry| {
            graph.allocator.free(entry.value_ptr.*);
        }
        graph.call_ret_by_callee.deinit();

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
        };
        errdefer node.aliases.deinit();

        try node.aliases.put(ret_value_ptr, {});
        try graph.nodes.put(ret_value_ptr, node);
        errdefer {
            _ = graph.nodes.remove(ret_value_ptr);
        }
        try graph.node_store.append(graph.allocator, node);

        return id;
    }

    /// Records an alias relationship: from_val = to_val.
    /// Called when we see a store like "ptr_b = ptr_a".
    pub fn trackAlias(graph: *MemoryGraph, from_val: u64, to_val: u64) !void {
        const target_node = graph.nodes.get(to_val) orelse {
            return MemoryGraphError.NodeNotFound;
        };

        try target_node.aliases.put(from_val, {});
        try graph.nodes.put(from_val, target_node);
    }

    /// Records a free operation and checks for double-free.
    /// Returns true if double-free detected, false otherwise.
    pub fn trackFree(
        graph: *MemoryGraph,
        free_inst_ptr: u64,
        ptr_val: u64,
        free_lang: Language,
    ) MemoryGraphError!bool {
        const node = graph.nodes.get(ptr_val) orelse {
            return false;
        };

        if (node.freed) {
            return true;
        }

        node.freed = true;
        node.freed_by = free_inst_ptr;
        node.free_lang = free_lang;
        return false;
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
            gop.value_ptr.* = &.{};
        }
        const new_list = try graph.allocator.alloc(u32, gop.value_ptr.*.len + 1);
        @memcpy(new_list[0..gop.value_ptr.*.len], gop.value_ptr.*);
        new_list[gop.value_ptr.*.len] = edge_idx;
        if (gop.value_ptr.*.len > 0) {
            graph.allocator.free(gop.value_ptr.*);
        }
        gop.value_ptr.* = new_list;
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
            gop.value_ptr.* = &.{};
        }
        const new_list = try graph.allocator.alloc(u32, gop.value_ptr.*.len + 1);
        @memcpy(new_list[0..gop.value_ptr.*.len], gop.value_ptr.*);
        new_list[gop.value_ptr.*.len] = edge_idx;
        if (gop.value_ptr.*.len > 0) {
            graph.allocator.free(gop.value_ptr.*);
        }
        gop.value_ptr.* = new_list;
    }

    /// Query: Get all call_arg edges where `ptr_val` is passed as an argument.
    /// Returns slice of indices into call_args (caller owns nothing).
    pub fn getCallArgsForPtr(graph: *MemoryGraph, ptr_val: u64) []const u32 {
        return graph.call_arg_by_ptr.get(ptr_val) orelse &.{};
    }

    /// Query: Get all call_ret edges for returns from `callee_name`.
    /// Returns slice of indices into call_rets (caller owns nothing).
    pub fn getCallRetsFromCallee(graph: *MemoryGraph, callee_name: []const u8) []const u32 {
        return graph.call_ret_by_callee.get(callee_name) orelse &.{};
    }

    /// Query: Check if a pointer flows into any function call as an argument.
    pub fn isPassedAsArg(graph: *MemoryGraph, ptr_val: u64) bool {
        return graph.call_arg_by_ptr.contains(ptr_val);
    }

    /// Query: Check if a pointer is returned from any function call.
    pub fn isReturnedFromCall(graph: *MemoryGraph, ptr_val: u64) bool {
        for (graph.call_rets.items) |edge| {
            if (edge.ret_ptr == ptr_val) return true;
        }
        return false;
    }

    // =====================================================================
    // Queries
    // =====================================================================

    /// Checks if a pointer value has been freed.
    pub fn isFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;
        return node.freed;
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

        var arg_iter = graph.call_arg_by_ptr.iterator();
        while (arg_iter.next()) |entry| {
            graph.allocator.free(entry.value_ptr.*);
        }
        graph.call_arg_by_ptr.clearRetainingCapacity();

        var ret_iter = graph.call_ret_by_callee.iterator();
        while (ret_iter.next()) |entry| {
            graph.allocator.free(entry.value_ptr.*);
        }
        graph.call_ret_by_callee.clearRetainingCapacity();

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

        for (arg_indices) |idx| {
            const arg_edge = &graph.call_args.items[idx];
            var returned = false;
            for (graph.call_rets.items) |ret_edge| {
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

        const arg_indices = graph.getCallArgsForPtr(ptr_val);
        for (arg_indices) |idx| {
            const arg_edge = &graph.call_args.items[idx];
            for (graph.call_rets.items) |ret_edge| {
                if (ret_edge.caller_inst == arg_edge.caller_inst) {
                    const ret_node = graph.nodes.get(ret_edge.ret_ptr) orelse continue;
                    if (ret_node.freed and ret_node.id == node.id) return true;
                }
            }
        }

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
    ) DangerPathKind {
        // (b): Check if ptr flows into any FFI boundary call as argument.
        // This catches function-parameter pointers (no AllocNode) that enter FFI.
        const arg_indices = graph.getCallArgsForPtr(ptr_val);
        for (arg_indices) |idx| {
            const arg_edge = &graph.call_args.items[idx];
            for (ffi_boundaries) |b| {
                if (b.is_ffi_boundary and std.mem.eql(u8, b.callee_name, arg_edge.callee_name)) {
                    return .ffi_arg;
                }
            }
        }

        // (c): Check if ptr returns from any FFI boundary call.
        for (graph.call_rets.items) |ret_edge| {
            if (ret_edge.ret_ptr == ptr_val) {
                for (ffi_boundaries) |b| {
                    if (b.is_ffi_boundary and std.mem.eql(u8, b.callee_name, ret_edge.callee_name)) {
                        return .ffi_ret;
                    }
                }
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
            const kind = isOnDangerPath(graph, alias_ptr, ffi_boundaries, visited);
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

// ============================================================================
// Fuzzy Matching for Alloc/Free Pairs
// ============================================================================

const c = @import("c").c;

pub const FnClass = enum {
    alloc,
    free,
    init,
    cleanup,
    create,
    destroy,
    open,
    close,
    other,
};

pub const FuzzyMatcher = struct {
    pub fn classify(fn_name: []const u8) FnClass {
        if (endsWithLower(fn_name, "free") or
            endsWithLower(fn_name, "_free") or
            endsWithLower(fn_name, "dealloc") or
            indexOfLower(fn_name, "dealloc") != null)
        {
            return .free;
        }

        if (endsWithLower(fn_name, "malloc") or
            endsWithLower(fn_name, "calloc") or
            endsWithLower(fn_name, "realloc") or
            endsWithLower(fn_name, "_alloc") or
            endsWithLower(fn_name, "alloc") or
            indexOfLower(fn_name, "alloc") != null)
        {
            return .alloc;
        }

        if (endsWithLower(fn_name, "_new") or
            indexOfLower(fn_name, "_new_") != null)
        {
            return .alloc;
        }

        if (endsWithLower(fn_name, "_delete") or
            indexOfLower(fn_name, "_delete_") != null)
        {
            return .free;
        }

        if (endsWithLower(fn_name, "_init"))
        {
            return .init;
        }

        if (endsWithLower(fn_name, "_cleanup") or
            endsWithLower(fn_name, "cleanup") or
            endsWithLower(fn_name, "finalize"))
        {
            return .cleanup;
        }

        if (endsWithLower(fn_name, "_create") or
            endsWithLower(fn_name, "create"))
        {
            return .create;
        }

        if (endsWithLower(fn_name, "_destroy") or
            endsWithLower(fn_name, "destroy"))
        {
            return .destroy;
        }

        if (endsWithLower(fn_name, "_open") or
            endsWithLower(fn_name, "dlopen"))
        {
            return .open;
        }

        if (endsWithLower(fn_name, "_close") or
            endsWithLower(fn_name, "dlclose"))
        {
            return .close;
        }

        return .other;
    }

    pub fn isMatchingAllocFreePair(alloc_fn: []const u8, free_fn: []const u8) bool {
        if (!isAllocLike(alloc_fn) or !isFreeLike(free_fn)) {
            return false;
        }

        if (std.mem.eql(u8, alloc_fn, free_fn)) {
            return false;
        }

        const alloc_prefix = extractLibPrefix(alloc_fn);
        const free_prefix = extractLibPrefix(free_fn);

        if (alloc_prefix.len == 0 or free_prefix.len == 0) {
            return false;
        }

        if (!std.mem.eql(u8, alloc_prefix, free_prefix)) {
            return false;
        }

        if (endsWithLower(alloc_fn, "new") and
            endsWithLower(free_fn, "delete"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "malloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "alloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "calloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "realloc") and
            endsWithLower(free_fn, "free"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "init") and
            endsWithLower(free_fn, "cleanup"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "create") and
            endsWithLower(free_fn, "destroy"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "open") and
            endsWithLower(free_fn, "close"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "dlopen") and
            endsWithLower(free_fn, "dlclose"))
        {
            return true;
        }

        if (endsWithLower(alloc_fn, "new")) {
            return endsWithLower(free_fn, "free");
        }

        return false;
    }

    fn isAllocLike(fn_name: []const u8) bool {
        const class = classify(fn_name);
        return class == .alloc or class == .init or class == .create or class == .open;
    }

    fn isFreeLike(fn_name: []const u8) bool {
        const class = classify(fn_name);
        return class == .free or class == .cleanup or class == .destroy or class == .close;
    }

    fn extractLibPrefix(fn_name: []const u8) []const u8 {
        if (fn_name.len == 0) return "";

        var end: usize = 0;
        while (end < fn_name.len and fn_name[end] != '_' and fn_name[end] != '_' and fn_name[end] != '_' and fn_name[end] != 0) {
            if (fn_name[end] >= 'A' and fn_name[end] <= 'Z') {
                end += 1;
            } else if (fn_name[end] >= 'a' and fn_name[end] <= 'z') {
                end += 1;
            } else if (fn_name[end] >= '0' and fn_name[end] <= '9') {
                end += 1;
            } else {
                break;
            }
        }

        if (end == 0) return "";

        const prefix = fn_name[0..end];

        if (prefix.len >= 3 and std.mem.startsWith(u8, fn_name[end..], "_")) {
            return prefix;
        }

        for (0..end) |i| {
            if (fn_name[i] == '_') {
                return fn_name[0..i];
            }
        }

        return prefix;
    }

    /// Case-insensitive endsWith. Zero allocation.
    fn endsWithLower(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        const offset = haystack.len - needle.len;
        for (needle, 0..) |ch, i| {
            if (std.ascii.toLower(haystack[offset + i]) != ch) return false;
        }
        return true;
    }

    /// Case-insensitive indexOf. Zero allocation.
    fn indexOfLower(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len > haystack.len) return null;
        const limit = haystack.len - needle.len;
        var i: usize = 0;
        while (i <= limit) : (i += 1) {
            var matched = true;
            for (needle, 0..) |ch, j| {
                if (std.ascii.toLower(haystack[i + j]) != ch) {
                    matched = false;
                    break;
                }
            }
            if (matched) return i;
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "memory_graph - basic alloc tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;

    const alloc_id = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);
    try std.testing.expectEqual(@as(u64, 1), alloc_id);

    const node = graph.nodes.get(fake_ret);
    try std.testing.expect(node != null);
    try std.testing.expectEqual(@as(u64, 1), node.?.id);
    try std.testing.expect(!node.?.freed);
    try std.testing.expectEqual(SourceKind.heap_alloc, node.?.source_kind);
}

test "memory_graph - alias tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret1: u64 = 0x2000;
    const fake_ret2: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc, .safe, .c);
    try graph.trackAlias(fake_ret2, fake_ret1);

    const node1 = graph.nodes.get(fake_ret1);
    const node2 = graph.nodes.get(fake_ret2);
    try std.testing.expect(node1 != null);
    try std.testing.expect(node2 != null);
    try std.testing.expectEqual(node1.?.id, node2.?.id);
}

test "memory_graph - double free detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_free1: u64 = 0x3000;
    const fake_free2: u64 = 0x4000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);

    const first_free = try graph.trackFree(fake_free1, fake_ret, .c);
    try std.testing.expect(!first_free);

    const second_free = try graph.trackFree(fake_free2, fake_ret, .c);
    try std.testing.expect(second_free);
}

test "memory_graph - alias double free" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret1: u64 = 0x2000;
    const fake_ret2: u64 = 0x3000;
    const fake_free1: u64 = 0x4000;
    const fake_free2: u64 = 0x5000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc, .safe, .c);
    try graph.trackAlias(fake_ret2, fake_ret1);

    _ = try graph.trackFree(fake_free1, fake_ret2, .c);

    const is_double = try graph.trackFree(fake_free2, fake_ret1, .c);
    try std.testing.expect(is_double);
}

test "memory_graph - is_freed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_free: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);

    try std.testing.expect(!graph.isFreed(fake_ret));

    _ = try graph.trackFree(fake_free, fake_ret, .c);
    try std.testing.expect(graph.isFreed(fake_ret));
}

test "memory_graph - source_kind tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: u64 = 0x1000;
    const fake_ret: u64 = 0x2000;
    const fake_alloca: u64 = 0x3000;

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc, .safe, .c);
    try std.testing.expectEqual(SourceKind.heap_alloc, graph.getSourceKind(fake_ret));

    _ = try graph.trackAlloc(fake_alloca, fake_alloca, .alloca, .safe, .c);
    try std.testing.expectEqual(SourceKind.alloca, graph.getSourceKind(fake_alloca));

    try std.testing.expectEqual(SourceKind.unknown, graph.getSourceKind(0xDEAD));
}

test "memory_graph - func_counter balance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const func: u64 = 0xA000;

    // No ops yet.
    var counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(u32, 0), counter.allocs);
    try std.testing.expectEqual(@as(u32, 0), counter.frees);
    try std.testing.expect(!counter.hasHeapOps());

    // 3 allocs, 1 free.
    graph.recordFuncAlloc(func);
    graph.recordFuncAlloc(func);
    graph.recordFuncAlloc(func);
    graph.recordFuncFree(func);

    counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(u32, 3), counter.allocs);
    try std.testing.expectEqual(@as(u32, 1), counter.frees);
    try std.testing.expectEqual(@as(i64, 2), counter.net());
    try std.testing.expect(counter.hasHeapOps());

    // Balanced: 2 more frees.
    graph.recordFuncFree(func);
    graph.recordFuncFree(func);

    counter = graph.getFuncCounter(func);
    try std.testing.expectEqual(@as(i64, 0), counter.net());
}

test "memory_graph - content_source tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const alloca_ptr: u64 = 0x1000;

    // alloca contains a heap pointer.
    graph.recordContentSource(alloca_ptr, .heap_alloc);

    // Direct source of alloca is .alloca.
    _ = try graph.trackAlloc(alloca_ptr, alloca_ptr, .alloca, .safe, .c);
    try std.testing.expectEqual(SourceKind.alloca, graph.getSourceKind(alloca_ptr));

    // Direct source of alloca is .alloca — this doesn't change even though
    // it contains a heap pointer. resolveSourceKind returns direct source first.
    try std.testing.expectEqual(SourceKind.alloca, graph.resolveSourceKind(alloca_ptr));

    // For an untracked pointer that has content source recorded.
    const unknown_ptr: u64 = 0x3000;
    graph.recordContentSource(unknown_ptr, .heap_alloc);
    try std.testing.expectEqual(SourceKind.unknown, graph.getSourceKind(unknown_ptr));
    try std.testing.expectEqual(SourceKind.heap_alloc, graph.resolveSourceKind(unknown_ptr));
}

test "memory_graph - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        _ = try graph.trackAlloc(i * 0x1000, i * 0x1000 + 1, .heap_alloc, .safe, .c);
        if (i > 0) {
            try graph.trackAlias(i * 0x1000 + 1, (i - 1) * 0x1000 + 1);
        }
        graph.recordFuncAlloc(0xA000);
        graph.recordContentSource(i * 0x1000, .alloca);
    }

    i = 0;
    while (i < 50) : (i += 1) {
        _ = try graph.trackFree(i * 0x1000 + 2, i * 0x1000 + 1, .c);
        graph.recordFuncFree(0xA000);
    }
}

// =====================================================================
// R8.0: Call edge tracking tests
// =====================================================================

test "memory_graph - trackCallArg basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track a call_arg: ptr 0x1000 passed as arg 0 to "malloc"
    try graph.trackCallArg(0x2000, "malloc", 0x1000, 0);

    // Verify call_args list has 1 entry
    try std.testing.expectEqual(@as(usize, 1), graph.call_args.items.len);

    const edge = graph.call_args.items[0];
    try std.testing.expectEqual(@as(u64, 0x2000), edge.caller_inst);
    try std.testing.expectEqualStrings("malloc", edge.callee_name);
    try std.testing.expectEqual(@as(u64, 0x1000), edge.arg_ptr);
    try std.testing.expectEqual(@as(u32, 0), edge.arg_index);

    // Query by ptr should find this edge
    const args_for_ptr = graph.getCallArgsForPtr(0x1000);
    try std.testing.expectEqual(@as(usize, 1), args_for_ptr.len);
}

test "memory_graph - trackCallRet basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track a call_ret: ptr 0x2000 returned from "malloc"
    try graph.trackCallRet(0x3000, "malloc", 0x2000);

    // Verify call_rets list has 1 entry
    try std.testing.expectEqual(@as(usize, 1), graph.call_rets.items.len);

    const edge = graph.call_rets.items[0];
    try std.testing.expectEqual(@as(u64, 0x3000), edge.caller_inst);
    try std.testing.expectEqualStrings("malloc", edge.callee_name);
    try std.testing.expectEqual(@as(u64, 0x2000), edge.ret_ptr);

    // Query by callee should find this edge
    const rets_from_callee = graph.getCallRetsFromCallee("malloc");
    try std.testing.expectEqual(@as(usize, 1), rets_from_callee.len);
}

test "memory_graph - isPassedAsArg and isReturnedFromCall" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Initially nothing is passed or returned
    try std.testing.expect(!graph.isPassedAsArg(0x1000));
    try std.testing.expect(!graph.isReturnedFromCall(0x2000));

    // Add a call_arg
    try graph.trackCallArg(0x5000, "free", 0x1000, 0);
    try std.testing.expect(graph.isPassedAsArg(0x1000));
    try std.testing.expect(!graph.isReturnedFromCall(0x1000));

    // Add a call_ret
    try graph.trackCallRet(0x6000, "malloc", 0x2000);
    try std.testing.expect(graph.isReturnedFromCall(0x2000));
    try std.testing.expect(!graph.isPassedAsArg(0x2000));
}

test "memory_graph - multiple call edges for same pointer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Same ptr passed to different functions
    try graph.trackCallArg(0x1000, "free", 0x5000, 0);
    try graph.trackCallArg(0x2000, "fclose", 0x5000, 0);
    try graph.trackCallArg(0x3000, "pthread_create", 0x5000, 2);

    // Should find all 3 edges
    const args = graph.getCallArgsForPtr(0x5000);
    try std.testing.expectEqual(@as(usize, 3), args.len);
}

test "memory_graph - call edges coexist with alloc/free tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Track allocation
    _ = try graph.trackAlloc(0x1000, 0x1001, .heap_alloc, .safe, .c);

    // Track call_arg with the allocated pointer
    try graph.trackCallArg(0x2000, "process_data", 0x1001, 0);

    // Track free
    _ = try graph.trackFree(0x3000, 0x1001, .c);

    // All data should coexist
    try std.testing.expect(graph.nodes.contains(0x1001));
    try std.testing.expectEqual(@as(usize, 1), graph.call_args.items.len);
    const node = graph.nodes.get(0x1001).?;
    try std.testing.expect(node.freed);
}

test "memory_graph - isLeaked cross-function propagation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);

    try std.testing.expect(!graph.isLeaked(0xA001));
    try std.testing.expect(!graph.isLeaked(0x9999));

    try graph.trackCallArg(0x2000, "sink", 0xA001, 0);

    try std.testing.expect(graph.isLeaked(0xA001));

    try graph.trackCallRet(0x2000, "sink", 0xB001);

    try std.testing.expect(!graph.isLeaked(0xA001));

    _ = try graph.trackFree(0x3000, 0xA001, .c);
    try std.testing.expect(!graph.isLeaked(0xA001));
}

test "memory_graph - isDoubleFreed alias closure + call chain" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try std.testing.expect(!graph.isDoubleFreed(0xA001));

    _ = try graph.trackFree(0x3000, 0xA001, .c);
    try std.testing.expect(graph.isDoubleFreed(0xA001));

    var graph2 = try MemoryGraph.init(allocator);
    defer graph2.deinit();

    _ = try graph2.trackAlloc(0x1000, 0xA002, .heap_alloc, .safe, .c);
    try graph2.trackAlias(0xB002, 0xA002);
    _ = try graph2.trackFree(0x3000, 0xB002, .c);
    try std.testing.expect(graph2.isDoubleFreed(0xA002));

    var graph3 = try MemoryGraph.init(allocator);
    defer graph3.deinit();

    _ = try graph3.trackAlloc(0x1000, 0xA003, .heap_alloc, .safe, .c);
    try graph3.trackCallArg(0x2000, "free_it", 0xA003, 0);
    try graph3.trackCallRet(0x2000, "free_it", 0xB003);
    try graph3.trackAlias(0xB003, 0xA003);
    _ = try graph3.trackFree(0x4000, 0xB003, .c);
    try std.testing.expect(graph3.isDoubleFreed(0xA003));
}

test "memory_graph - isOnDangerPath pure internal returns none" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    _ = try graph.trackFree(0x3000, 0xA001, .c);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.none, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath cross-lang lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .rust);
    _ = try graph.trackFree(0x3000, 0xA001, .c);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.cross_lang_lifecycle, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath FFI arg flow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try graph.trackCallArg(0x2000, "C.malloc", 0xA001, 0);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{
        .{ .callee_name = "C.malloc", .is_ffi_boundary = true },
    };
    try std.testing.expectEqual(DangerPathKind.ffi_arg, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath unsafe zone alloc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .unsafe, .rust);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{};
    try std.testing.expectEqual(DangerPathKind.unsafe_alloc, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}

test "memory_graph - isOnDangerPath alias propagation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try graph.trackAlias(0xB001, 0xA001);
    try graph.trackCallArg(0x2000, "ffi_callback", 0xB001, 0);

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const boundaries = [_]MemoryGraph.DangerSurface{
        .{ .callee_name = "ffi_callback", .is_ffi_boundary = true },
    };
    // 0xA001 itself doesn't have call_arg, but its alias 0xB001 does
    try std.testing.expectEqual(DangerPathKind.ffi_arg, graph.isOnDangerPath(0xA001, &boundaries, &visited));
}
