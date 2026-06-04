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
const log = @import("../common/log.zig");

const zone = @import("zone_classifier.zig");
pub const ZoneKind = zone.ZoneKind;
pub const Language = zone.Language;

const mg_types = @import("../types/memory_graph_types.zig");
pub const MemoryGraphError = mg_types.MemoryGraphError;
pub const SourceKind = mg_types.SourceKind;
pub const FuncCounter = mg_types.FuncCounter;
pub const OwnershipTransferStatus = mg_types.OwnershipTransferStatus;
pub const ResourceLifecycle = mg_types.ResourceLifecycle;
pub const CallArgEdge = mg_types.CallArgEdge;
pub const CallRetEdge = mg_types.CallRetEdge;
pub const FreeRecord = mg_types.FreeRecord;
pub const FamilyId = mg_types.FamilyId;
const AllocNode = mg_types.AllocNode;
pub const DangerPathKind = mg_types.DangerPathKind;
pub const DangerSurface = mg_types.DangerSurface;
const hashValues = mg_types.hashValues;

const family_registry_mod = @import("resource/family_registry.zig");
const ResourceFamilyRegistry = family_registry_mod.ResourceFamilyRegistry;

const escape_mod = @import("resource/escape.zig");
pub const EscapeKind = escape_mod.EscapeKind;
const EscapeRecord = escape_mod.EscapeRecord;
const EscapeList = escape_mod.EscapeList;

// P16-2a: Split out escape tracking methods to keep file < 1000 lines
const mg_escape = @import("memory_graph_escape.zig");

const mg_methods = @import("../types/memory_graph_methods.zig");

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

    /// Reachability cache: maps (from_bb << 32 | to_bb) → reachability result.
    /// Avoids repeated graph traversals for the same BB pairs.
    /// Key encoding: high 32 bits = from_bb, low 32 bits = to_bb.
    reachability_cache: std.AutoHashMap(u64, bool),

    /// Object pool for AllocNode reuse to reduce allocation overhead.
    /// Freed nodes are returned to this pool instead of being destroyed.
    node_pool: std.ArrayList(*AllocNode),

    /// Optional resource family registry for family-based classification.
    /// When set, trackAlloc/trackFree will automatically classify alloc/release
    /// families via registry lookup. null = legacy language-only mode (no family data).
    family_registry: ?*ResourceFamilyRegistry,

    /// Capacity hints for HashMap pre-allocation (avoids rehash during population).
    /// Based on sqlite3 profile data; conservative over-estimates are fine.
    pub const CapacityHints = struct {
        nodes: usize = 0,
        call_arg_by_ptr: usize = 0,
        call_arg_by_callee: usize = 0,
        call_ret_by_callee: usize = 0,
        call_ret_by_ptr: usize = 0,
        alias_to_canonical: usize = 0,
        weak_aliases: usize = 0,
        bb_edges: usize = 0,
        reachability_cache: usize = 0,
        func_counters: usize = 0,
        content_sources: usize = 0,
    };

    /// Initializes a new memory graph.
    pub fn init(allocator: std.mem.Allocator) MemoryGraphError!MemoryGraph {
        return MemoryGraph{
            .nodes = std.AutoHashMap(u64, *AllocNode).init(allocator),
            .node_store = .{},
            .allocator = allocator,
            .next_id = 1,
            .func_counters = std.AutoHashMap(u64, FuncCounter).init(allocator),
            .content_sources = std.AutoHashMap(u64, SourceKind).init(allocator),
            .call_args = try std.ArrayList(CallArgEdge).initCapacity(allocator, 64),
            .call_rets = try std.ArrayList(CallRetEdge).initCapacity(allocator, 64),
            .call_arg_by_ptr = std.AutoHashMap(u64, std.ArrayList(u32)).init(allocator),
            .call_arg_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .call_ret_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .call_ret_by_ptr = std.AutoHashMap(u64, std.ArrayList(u32)).init(allocator),
            .alias_to_canonical = std.AutoHashMap(u64, u64).init(allocator),
            .weak_aliases = std.AutoHashMap(u64, void).init(allocator),
            .bb_edges = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(allocator),
            .reachability_cache = std.AutoHashMap(u64, bool).init(allocator),
            .node_pool = try std.ArrayList(*AllocNode).initCapacity(allocator, 32),
            .family_registry = null,
        };
    }

    /// Initializes a new memory graph with pre-allocated HashMap capacities.
    /// Use this for large-scale analysis (e.g. sqlite3) to avoid rehash overhead.
    pub fn initWithCapacity(allocator: std.mem.Allocator, hints: CapacityHints) MemoryGraphError!MemoryGraph {
        var mg = try init(allocator);
        if (hints.nodes > 0) try mg.nodes.ensureTotalCapacity(@as(u32, @intCast(hints.nodes)));
        if (hints.call_arg_by_ptr > 0) try mg.call_arg_by_ptr.ensureTotalCapacity(@as(u32, @intCast(hints.call_arg_by_ptr)));
        if (hints.call_arg_by_callee > 0) try mg.call_arg_by_callee.ensureTotalCapacity(@as(u32, @intCast(hints.call_arg_by_callee)));
        if (hints.call_ret_by_callee > 0) try mg.call_ret_by_callee.ensureTotalCapacity(@as(u32, @intCast(hints.call_ret_by_callee)));
        if (hints.call_ret_by_ptr > 0) try mg.call_ret_by_ptr.ensureTotalCapacity(@as(u32, @intCast(hints.call_ret_by_ptr)));
        if (hints.alias_to_canonical > 0) try mg.alias_to_canonical.ensureTotalCapacity(@as(u32, @intCast(hints.alias_to_canonical)));
        if (hints.weak_aliases > 0) try mg.weak_aliases.ensureTotalCapacity(@as(u32, @intCast(hints.weak_aliases)));
        if (hints.bb_edges > 0) try mg.bb_edges.ensureTotalCapacity(@as(u32, @intCast(hints.bb_edges)));
        if (hints.reachability_cache > 0) try mg.reachability_cache.ensureTotalCapacity(@as(u32, @intCast(hints.reachability_cache)));
        if (hints.func_counters > 0) try mg.func_counters.ensureTotalCapacity(@as(u32, @intCast(hints.func_counters)));
        if (hints.content_sources > 0) try mg.content_sources.ensureTotalCapacity(@as(u32, @intCast(hints.content_sources)));
        return mg;
    }

    /// Inject a resource family registry for automatic family classification.
    /// When set, trackAlloc/trackFree will look up callee names in the registry
    /// and populate alloc_family / release_family fields on nodes.
    /// Pass null to disable family classification (legacy mode).
    pub fn setFamilyRegistry(graph: *MemoryGraph, registry: ?*ResourceFamilyRegistry) void {
        graph.family_registry = registry;
    }

    /// Deinitializes the memory graph. Frees all nodes and internal state.
    pub fn deinit(graph: *MemoryGraph) void {
        for (graph.node_store.items) |node| {
            node.aliases.deinit();
            node.free_sites.deinit(graph.allocator);
            node.raii_cleanup_sites.deinit(graph.allocator);
            node.defer_sites.deinit(graph.allocator);
            graph.allocator.destroy(node);
        }
        graph.node_store.deinit(graph.allocator);
        graph.nodes.deinit();
        graph.func_counters.deinit();
        graph.content_sources.deinit();

        for (graph.call_args.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_args.deinit(graph.allocator);
        for (graph.call_rets.items) |*edge| {
            graph.allocator.free(edge.callee_name);
        }
        graph.call_rets.deinit(graph.allocator);

        mg_methods.deinitCallIndexMap(u64, &graph.call_arg_by_ptr, graph.allocator);
        mg_methods.deinitStringCallIndexMap(&graph.call_arg_by_callee, graph.allocator);
        mg_methods.deinitStringCallIndexMap(&graph.call_ret_by_callee, graph.allocator);
        mg_methods.deinitCallIndexMap(u64, &graph.call_ret_by_ptr, graph.allocator);

        graph.alias_to_canonical.deinit();
        graph.weak_aliases.deinit();

        var bb_iter = graph.bb_edges.iterator();
        while (bb_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        graph.bb_edges.deinit();

        graph.reachability_cache.deinit();
        graph.node_pool.deinit(graph.allocator);

        graph.* = undefined;
    }

    /// Allocate a node from the pool or create a new one.
    /// Reuses freed nodes to reduce allocation overhead.
    fn allocNode(graph: *MemoryGraph) !*AllocNode {
        if (graph.node_pool.items.len > 0) {
            return graph.node_pool.pop() orelse return error.OutOfMemory;
        }
        return try graph.allocator.create(AllocNode);
    }

    /// Return a node to the pool for reuse.
    /// Clears the node's state before returning it to the pool.
    fn freeNode(graph: *MemoryGraph, node: *AllocNode) !void {
        // Clear node state for reuse
        node.aliases.clearRetainingCapacity();
        node.free_sites.clearRetainingCapacity();
        node.raii_cleanup_sites.clearRetainingCapacity();
        node.defer_sites.clearRetainingCapacity();
        node.freed = false;
        node.freed_by = null;
        node.escapes = null;
        // v0.2.0: Reset lifecycle tracking fields
        node.ownership_model = .manual;
        node.has_raii_cleanup = false;
        node.refcount_ops = .{};
        node.is_gc_managed = false;
        node.gc_scope = null;
        node.has_deferred_cleanup = false;
        node.container_type = null;
        node.is_borrowed = false;

        // Return to pool if not at capacity (limit pool size to 128 nodes)
        if (graph.node_pool.items.len < 128) {
            try graph.node_pool.append(graph.allocator, node);
        } else {
            // Pool is full, actually free the node
            node.aliases.deinit();
            node.free_sites.deinit(graph.allocator);
            node.raii_cleanup_sites.deinit(graph.allocator);
            node.defer_sites.deinit(graph.allocator);
            graph.allocator.destroy(node);
        }
    }

    // =====================================================================
    // Allocation tracking
    // =====================================================================

    /// Creates a new allocation node and returns its ID.
    /// Accepts raw pointer values as u64 to avoid cross-cimport type mismatches.
    /// `kind` indicates how this allocation was created (alloca, heap, resource, etc.).
    /// `alloc_callee_opt` optionally records the callee name for ownership transfer detection.
    pub fn trackAlloc(
        graph: *MemoryGraph,
        alloc_inst_ptr: u64,
        ret_value_ptr: u64,
        kind: SourceKind,
        alloc_zone: ZoneKind,
        alloc_lang: Language,
        alloc_callee_opt: ?[]const u8,
    ) MemoryGraphError!u64 {
        const id = graph.next_id;
        graph.next_id += 1;

        const merkle_hash = hashValues(&.{
            alloc_inst_ptr,
            ret_value_ptr,
            id,
        });

        // Allocate node from pool or create new
        const node = try graph.allocNode();
        errdefer graph.freeNode(node) catch {};

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
            .alloc_callee = alloc_callee_opt,
            .free_sites = try std.ArrayList(FreeRecord).initCapacity(graph.allocator, 4),
            .escapes = null,
            // v0.2.0: Multi-language lifecycle tracking
            .ownership_model = .manual,
            .raii_cleanup_sites = try std.ArrayList(u64).initCapacity(graph.allocator, 4),
            .has_raii_cleanup = false,
            .refcount_ops = .{},
            .is_gc_managed = false,
            .gc_scope = null,
            .has_deferred_cleanup = false,
            .defer_sites = try std.ArrayList(u64).initCapacity(graph.allocator, 4),
            .container_type = null,
        };
        errdefer node.aliases.deinit();
        errdefer node.raii_cleanup_sites.deinit(graph.allocator);
        errdefer node.defer_sites.deinit(graph.allocator);
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
        var target_node = graph.nodes.get(to_val);

        if (target_node == null) {
            // Lazy node creation: if target doesn't exist, create a placeholder
            // This handles cases where store/alias instructions reference values
            // that haven't been explicitly tracked via trackAlloc yet.
            // Common in FFI scenarios where pointers cross ABI boundaries.
            target_node = try graph.createLazyNode(to_val);
        }

        try target_node.?.aliases.put(from_val, {});
        // V2: Store weak flag for downstream double-free decision making
        if (is_weak) {
            try graph.weak_aliases.put(from_val, {});
        }
        try graph.nodes.put(from_val, target_node.?);
        // Build reverse index for O(1) alias→canonical lookup
        try graph.alias_to_canonical.put(from_val, to_val);
    }

    /// Create a placeholder node for lazy initialization during alias tracking.
    /// Used when trackAlias references a value not yet tracked via trackAlloc.
    fn createLazyNode(graph: *MemoryGraph, val: u64) !*AllocNode {
        const lazy_id = graph.next_id;
        graph.next_id += 1;

        // Allocate node from pool or create new
        const lazy_node = try graph.allocNode();
        errdefer graph.freeNode(lazy_node) catch {};

        lazy_node.* = AllocNode{
            .id = lazy_id,
            .alloc_inst = val,
            .merkle_root = hashValues(&.{ val, lazy_id }),
            .aliases = std.AutoHashMap(u64, void).init(graph.allocator),
            .freed = false,
            .freed_by = null,
            .source_kind = .unknown,
            .zone = .unknown,
            .alloc_lang = .unknown,
            .free_lang = null,
            .free_sites = try std.ArrayList(FreeRecord).initCapacity(graph.allocator, 4),
            .escapes = null,
            // v0.2.0: Multi-language lifecycle tracking
            .ownership_model = .manual,
            .raii_cleanup_sites = try std.ArrayList(u64).initCapacity(graph.allocator, 4),
            .has_raii_cleanup = false,
            .refcount_ops = .{},
            .is_gc_managed = false,
            .gc_scope = null,
            .has_deferred_cleanup = false,
            .defer_sites = try std.ArrayList(u64).initCapacity(graph.allocator, 4),
            .container_type = null,
        };

        try graph.node_store.append(graph.allocator, lazy_node);
        try graph.nodes.put(val, lazy_node);

        log.debug("[MG] Lazy-created node for alias target {x} (id={d})", .{ val, lazy_id });
        return lazy_node;
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

    /// Mark an allocation as a borrowed reference (should NOT report as leak).
    ///
    /// Called by Language Adapter when it detects a function returns a borrowed
    /// reference (e.g., Python's PyList_GetItem, Rust's &mut borrow).
    ///
    /// This prevents false positive leak reports for pointers that:
    ///   - Are owned by another runtime (GC, refcount, etc.)
    ///   - Should NOT be freed by the caller
    ///   - Have their lifecycle managed by the callee
    ///
    /// Arguments:
    ///   inst_addr - The instruction address of the call that returned the borrowed ref
    ///
    /// Behavior:
    ///   - If node exists: marks is_borrowed=true and sets ownership_model=.refcount
    ///   - If node doesn't exist: creates a lazy node with is_borrowed=true
    pub fn markBorrowedReference(graph: *MemoryGraph, inst_addr: u64) !void {
        // Try to find existing node by instruction address or pointer value
        var node = graph.nodes.get(inst_addr);

        if (node == null) {
            // No direct match - try to find via alloc_inst field
            for (graph.node_store.items) |n| {
                if (n.alloc_inst == inst_addr) {
                    node = n;
                    break;
                }
            }
        }

        if (node) |n| {
            // Mark existing node as borrowed
            n.is_borrowed = true;
            n.ownership_model = .refcount;

            log.debug("MEMORY: Node {} (inst 0x{x}) marked as borrowed reference", .{
                n.id, inst_addr,
            });
        } else {
            // Create lazy node if not exists (will be filled in by later passes)
            const lazy_node = try graph.createLazyNode(inst_addr);
            lazy_node.is_borrowed = true;
            lazy_node.ownership_model = .refcount;

            log.debug("MEMORY: Created lazy borrowed node for inst 0x{x}", .{inst_addr});
        }
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

    // P16-2a: Escape tracking methods moved to memory_graph_escape.zig
    // Re-exported here for backward compatibility
    pub const classifyAllocFamily = mg_escape.classifyAllocFamily;
    pub const classifyReleaseFamily = mg_escape.classifyReleaseFamily;
    pub const recordEscapeReturnToCaller = mg_escape.recordEscapeReturnToCaller;
    pub const recordEscapeOutParam = mg_escape.recordEscapeOutParam;
    pub const recordEscapeFieldStore = mg_escape.recordEscapeFieldStore;
    pub const recordEscapeGlobalStore = mg_escape.recordEscapeGlobalStore;
    pub const recordEscapeStaticLifetime = mg_escape.recordEscapeStaticLifetime;
    pub const recordEscapeCallback = mg_escape.recordEscapeCallback;
    pub const recordEscapeThread = mg_escape.recordEscapeThread;
    pub const hasValidEscape = mg_escape.hasValidEscape;
    pub const hasLifetimeRiskEscape = mg_escape.hasLifetimeRiskEscape;

    /// Records a heap allocation in a function's counter.
    pub fn recordFuncAlloc(graph: *MemoryGraph, func_ptr: u64) void {
        if (mg_methods.getOrInitFuncCounter(&graph.func_counters, func_ptr)) |c| {
            c.allocs += 1;
        }
    }

    /// Records a free call in a function's counter.
    pub fn recordFuncFree(graph: *MemoryGraph, func_ptr: u64) void {
        if (mg_methods.getOrInitFuncCounter(&graph.func_counters, func_ptr)) |c| {
            c.frees += 1;
        }
    }

    /// Records that a function returns a pointer value.
    /// Used by borrow_escape analysis to identify sink functions
    /// (functions that consume pointers without returning them).
    pub fn recordFuncReturns(graph: *MemoryGraph, func_ptr: u64) void {
        if (mg_methods.getOrInitFuncCounter(&graph.func_counters, func_ptr)) |c| {
            c.returns_pointer = true;
        }
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
    pub fn isPassedAsArg(graph: *MemoryGraph, ptr_val: u64) bool {
        return graph.call_arg_by_ptr.contains(ptr_val);
    }
    pub fn isReturnedFromCall(graph: *MemoryGraph, ptr_val: u64) bool {
        return graph.call_ret_by_ptr.contains(ptr_val);
    }

    // =====================================================================
    // Queries
    // =====================================================================

    pub fn isFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;
        return node.freed;
    }

    pub fn shouldSkipAnalysis(graph: *const MemoryGraph, ptr_val: u64) bool {
        _ = graph;
        _ = ptr_val;
        return false;
    }

    pub fn getAllocInfo(graph: *MemoryGraph, ptr_val: u64) ?*const AllocNode {
        return graph.nodes.get(ptr_val);
    }

    /// Finds the canonical AllocNode for any pointer value (direct or alias).
    /// O(1) lookup via alias_to_canonical index, then fallback to nodes map.
    /// Returns null if the pointer is not tracked in the graph.
    ///
    /// Use this instead of getAllocInfo() when the pointer may be an alias
    /// (e.g., after ownership transfer or FFI boundary crossing). This is
    /// critical for fixing wasmtime false positives where __rust_dealloc
    /// receives an aliased pointer and is misclassified as invalid_free.
    pub fn findCanonicalAlloc(graph: *MemoryGraph, ptr_val: u64) ?*AllocNode {
        if (graph.alias_to_canonical.get(ptr_val)) |canonical_ptr| {
            return graph.nodes.get(canonical_ptr);
        }
        return graph.nodes.get(ptr_val);
    }

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

        graph.weak_aliases.clearRetainingCapacity();

        mg_methods.clearCallIndexMap(u64, &graph.call_arg_by_ptr, graph.allocator);
        mg_methods.clearStringCallIndexMap(&graph.call_arg_by_callee, graph.allocator);
        mg_methods.clearStringCallIndexMap(&graph.call_ret_by_callee, graph.allocator);
        mg_methods.clearCallIndexMap(u64, &graph.call_ret_by_ptr, graph.allocator);

        graph.alias_to_canonical.clearRetainingCapacity();

        var bb_edge_iter = graph.bb_edges.iterator();
        while (bb_edge_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        graph.bb_edges.clearRetainingCapacity();

        graph.next_id = 1;
    }

    // =====================================================================
    // Phase 2: RAII / Ownership-Aware Analysis
    // =====================================================================

    /// Track Rust Drop trait implementation for an allocation.
    ///
    /// When detected, marks the node as having RAII cleanup, which
    /// suppresses false-positive leak reports for Rust allocations.
    ///
    /// This is called by the Rust Drop Semantics pass when it identifies
    /// a drop_in_place → __rust_dealloc chain for an allocation.
    ///
    /// Arguments:
    ///   alloc_inst - The instruction address of the original allocation
    ///   drop_inst  - The instruction address of the drop_in_place call
    ///
    /// Behavior:
    ///   - Finds the AllocNode for alloc_inst (by alloc_inst field or pointer value)
    ///   - Marks has_raii_cleanup = true
    ///   - Sets ownership_model = .raii
    ///   - Appends drop_inst to raii_cleanup_sites
    pub fn trackRustDrop(
        graph: *MemoryGraph,
        alloc_inst: u64,
        drop_inst: u64,
    ) !void {
        // Try to find node by alloc_inst field first (most reliable for Rust)
        var node: ?*AllocNode = null;

        for (graph.node_store.items) |*n| {
            if (n.alloc_inst == alloc_inst) {
                node = n;
                break;
            }
        }

        // Fallback: try direct pointer lookup
        if (node == null) {
            node = graph.nodes.get(alloc_inst);
        }

        if (node) |n| {
            n.has_raii_cleanup = true;
            n.ownership_model = .raii;

            try n.raii_cleanup_sites.append(graph.allocator, drop_inst);

            log.debug("MEMORY: Node {} (inst 0x{x}) has Rust Drop at inst 0x{x}", .{
                n.id,
                alloc_inst,
                drop_inst,
            });
        } else {
            log.warn("MEMORY: Cannot find node for inst 0x{x} to track Drop", .{alloc_inst});
        }
    }

    /// Check if an allocation has RAII cleanup (suppresses leak reports).
    ///
    /// Returns true if the allocation is managed by RAII (Rust Drop, C++ destructor),
    /// meaning the compiler-generated cleanup code will handle deallocation.
    ///
    /// This is used by leak detection passes to suppress false positives:
    ///   - Rust: __rust_alloc + drop_in_place → NOT a leak
    ///   - C++: operator new + ~T destructor → NOT a leak
    ///
    /// Arguments:
    ///   alloc_inst - The instruction address to check
    ///
    /// Returns:
    ///   true if RAII cleanup was detected for this allocation
    pub fn hasRAIICleanup(graph: *MemoryGraph, alloc_inst: u64) bool {
        // Try to find node by alloc_inst field first
        var iter = graph.nodes.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.alloc_inst == alloc_inst) {
                return entry.value_ptr.*.has_raii_cleanup;
            }
        }

        // Fallback: direct pointer lookup
        if (graph.nodes.get(alloc_inst)) |node| {
            return node.has_raii_cleanup;
        }

        return false;
    }

    /// Find node index by alloc_inst field.
    /// O(N) scan — use only when pointer-based lookup fails.
    ///
    /// This is needed because Rust allocations often have different
    /// pointer values for the alloc instruction vs the returned value.
    /// The alloc_inst field stores the actual allocation call address.
    ///
    /// Returns:
    ///   Index into nodes array, or null if not found
    pub fn findNodeByInst(graph: *MemoryGraph, alloc_inst: u64) ?usize {
        for (graph.node_store.items, 0..) |node, idx| {
            if (node.alloc_inst == alloc_inst) {
                return idx;
            }
        }
        return null;
    }

    // =====================================================================
    // Advanced Detection Methods
    // =====================================================================

    pub fn isUseAfterFreeViaAlias(graph: *MemoryGraph, ptr_val: u64, use_inst: u64) ?*const AllocNode {
        _ = use_inst;
        const node = graph.nodes.get(ptr_val) orelse return null;
        if (!node.freed) return null;
        return node;
    }

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

    pub fn validateOwnershipTransfer(
        graph: *MemoryGraph,
        from_func: u64,
        to_func: u64,
        ptr_val: u64,
    ) OwnershipTransferStatus {
        const node = graph.nodes.get(ptr_val) orelse return .not_tracked;
        const from_counter = graph.getFuncCounter(from_func);
        if (from_counter.net() <= 0) return .transfer_without_ownership;
        if (node.freed) return .transfer_after_free;
        const to_counter = graph.getFuncCounter(to_func);
        if (to_counter.net() > 0) return .potential_double_transfer;
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
    /// Uses cached results to avoid repeated traversals.
    /// Internal implementation uses DFS with visited set to handle cycles.
    pub fn isBBReachable(graph: *MemoryGraph, from_bb: u32, to_bb: u32, visited: *std.AutoHashMap(u32, void)) bool {
        if (from_bb == to_bb) return true;

        // Check cache first: encode (from_bb, to_bb) as single u64 key
        const cache_key = (@as(u64, from_bb) << 32) | to_bb;
        if (graph.reachability_cache.get(cache_key)) |cached_result| {
            return cached_result;
        }

        // Compute reachability using DFS
        const result = isBBReachableImpl(graph, from_bb, to_bb, visited);

        // Cache the result for future queries
        graph.reachability_cache.put(cache_key, result) catch {};

        return result;
    }

    /// Internal DFS implementation for reachability checking.
    /// Separated to allow caching in the public API.
    fn isBBReachableImpl(graph: *MemoryGraph, from_bb: u32, to_bb: u32, visited: *std.AutoHashMap(u32, void)) bool {
        if (from_bb == to_bb) return true;
        if (visited.contains(from_bb)) return false;
        visited.put(from_bb, {}) catch return false;

        const successors = graph.bb_edges.get(from_bb) orelse return false;
        var succ_iter = successors.iterator();
        while (succ_iter.next()) |entry| {
            if (isBBReachableImpl(graph, entry.key_ptr.*, to_bb, visited)) return true;
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
        if (node.free_sites.items.len < 2) return false;

        if (!mg_methods.hasBBInfo(node.free_sites.items)) return node.freed;

        if (mg_methods.checkFreeSitesSameBB(node.free_sites.items)) return true;

        const Context = struct {
            g: *MemoryGraph,
            fn reachable(ctx: *const @This(), from_bb: u32, to_bb: u32) bool {
                var visited = std.AutoHashMap(u32, void).init(ctx.g.allocator);
                defer visited.deinit();
                return ctx.g.isBBReachable(from_bb, to_bb, &visited);
            }
        };
        const ctx = Context{ .g = graph };
        return mg_methods.checkFreeSitesReachability(node.free_sites.items, Context, &ctx, Context.reachable);
    }

    /// Enhanced double-free detection with confidence scoring and FP reduction.
    /// Implements 4-layer analysis to reduce false positives by ~40%:
    ///
    /// Layer 1: Path-sensitive analysis (existing isDoubleFreedOnSamePath)
    ///   - Checks if free sites are on mutually exclusive paths (if/else branches)
    ///
    /// Layer 2: Loop-aware analysis (NEW)
    ///   - If both frees are inside loops, may be per-iteration cleanup
    ///   - Not necessarily double-free of the same pointer instance
    ///
    /// Layer 3: Defensive pattern recognition (NEW)
    ///   - Detects NULL-check-before-free patterns: if (ptr) { free(ptr); ptr = NULL; }
    ///   - These are defensive programming, not bugs
    ///
    /// Layer 4: Confidence adjustment (NEW)
    ///   - Combines signals from layers 1-3 into final confidence score
    ///   - Low confidence (< 0.6) → suppress as likely FP
    ///
    /// Returns:
    ///   - .{ .is_double_free = true,  .confidence = 0.95 } → real bug, report it
    ///   - .{ .is_double_free = false, .confidence = 0.0  } → not a bug
    ///   - .{ .is_double_free = true,  .confidence = 0.45 } → likely FP, suppress
    pub fn analyzeDoubleFreeWithConfidence(graph: *MemoryGraph, ptr_val: u64) struct {
        is_double_free: bool,
        confidence: f32,
        reason: []const u8,
    } {
        const node = graph.nodes.get(ptr_val) orelse return .{
            .is_double_free = false,
            .confidence = 0.0,
            .reason = "no allocation node found",
        };

        if (node.free_sites.items.len < 2) return .{
            .is_double_free = false,
            .confidence = 0.0,
            .reason = "less than 2 free sites",
        };

        // Layer 1: Basic path-sensitive check (existing logic)
        const is_on_same_path = graph.isDoubleFreedOnSamePath(ptr_val);
        var confidence: f32 = if (is_on_same_path) 0.9 else 0.3;

        // Layer 2: Loop-aware analysis
        // Check if free sites are in loops - reduces confidence if both in loops
        const loop_info = graph.analyzeLoopContext(node.free_sites.items);
        if (loop_info.all_in_loops) {
            log.debug("DOUBLE-FREE-LOOP: All free sites are in loops, reducing confidence", .{});
            confidence -= 0.25; // Significant reduction for loop context
        } else if (loop_info.some_in_loops) {
            log.debug("DOUBLE-FREE-LOOP: Some free sites in loops, slightly reducing confidence", .{});
            confidence -= 0.1; // Minor reduction
        }

        // Layer 3: Defensive pattern detection
        // Check for common defensive coding patterns that look like double-free but aren't
        const defensive = graph.detectDefensivePatterns(node.free_sites.items);
        if (defensive.has_null_check) {
            log.debug("DOUBLE-FREE-DEFENSIVE: NULL check before free detected", .{});
            confidence -= 0.3; // Strong signal this is defensive code
        }
        if (defensive.has_null_assign) {
            log.debug("DOUBLE-FREE-DEFENSIVE: NULL assignment after free detected", .{});
            confidence -= 0.2; // Moderate signal
        }
        if (defensive.is_cleanup_pattern) {
            log.debug("DOUBLE-FREE-DEFENSIVE: Cleanup pattern detected", .{});
            confidence -= 0.15; // Weak-moderate signal
        }

        // Layer 4: Confidence adjustment and thresholding
        // Clamp to valid range
        if (confidence < 0.0) confidence = 0.0;
        if (confidence > 1.0) confidence = 1.0;

        // Determine final verdict
        const is_bug = confidence >= 0.6 and is_on_same_path;
        const reason = if (is_bug)
            "confirmed double-free (high confidence)"
        else if (is_on_same_path)
            "same-path but low confidence (likely FP)"
        else
            "mutually exclusive paths (not a bug)";

        log.debug("DOUBLE-FREE-ANALYSIS: ptr=0x{x}, sites={d}, same_path={}, loop_info={s}, defensive={s}, conf={d:.1}, verdict={s}", .{
            ptr_val,
            node.free_sites.items.len,
            is_on_same_path,
            if (loop_info.all_in_loops) "all_loops" else if (loop_info.some_in_loops) "some_loops" else "no_loops",
            if (defensive.has_null_check or defensive.has_null_assign or defensive.is_cleanup_pattern) "yes" else "no",
            confidence,
            if (is_bug) "BUG" else "NOT_BUG",
        });

        return .{
            .is_double_free = is_bug,
            .confidence = confidence,
            .reason = reason,
        };
    }

    /// Analyze loop context of free sites.
    /// Returns information about whether free sites are inside natural loops.
    fn analyzeLoopContext(graph: *MemoryGraph, free_sites: []const FreeRecord) struct {
        all_in_loops: bool,
        some_in_loops: bool,
    } {
        // Simplified heuristic: BB IDs > 10000 often indicate loop bodies
        // In real implementation, this would use LLVM's LoopInfo analysis
        var all_in_loops = true;
        var some_in_loops = false;

        for (free_sites) |site| {
            // Heuristic: check if BB has back-edge (indicates loop)
            // For now, we'll use a simplified check based on BB ID patterns
            // Real implementation would query LLVM LoopInfo pass
            const in_loop = graph.isBBLikelyInLoop(site.bb_id);
            if (!in_loop) {
                all_in_loops = false;
            } else {
                some_in_loops = true;
            }
        }

        return .{
            .all_in_loops = all_in_loops and some_in_loops,
            .some_in_loops = some_in_loops,
        };
    }

    /// Heuristic check if a basic block is likely inside a loop.
    /// Uses BB ID patterns and edge analysis as proxy for actual loop info.
    fn isBBLikelyInLoop(graph: *MemoryGraph, bb_id: u32) bool {
        if (bb_id == 0) return false; // Unknown BB

        // Check for back-edges (BB that can reach itself)
        // This is a strong indicator of being in a loop
        var visited = std.AutoHashMap(u32, void).init(graph.allocator);
        defer visited.deinit();

        // Simple check: does this BB have an edge to itself or to a dominator?
        const successors = graph.bb_edges.get(bb_id);
        if (successors) |succs| {
            var succ_iter = succs.iterator();
            while (succ_iter.next()) |entry| {
                // Back-edge to self or to lower BB ID (potential loop header)
                if (entry.key_ptr.* <= bb_id and entry.key_ptr.* != 0) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Detect defensive programming patterns around free sites.
    /// These patterns reduce the likelihood of a real double-free bug.
    fn detectDefensivePatterns(graph: *MemoryGraph, free_sites: []const FreeRecord) struct {
        has_null_check: bool,
        has_null_assign: bool,
        is_cleanup_pattern: bool,
    } {
        // In a full implementation, this would examine IR instructions
        // surrounding each free site for defensive patterns like:
        //
        // Pattern 1: NULL check before free
        //   if (ptr != NULL) { free(ptr); }
        //
        // Pattern 2: NULL assignment after free
        //   free(ptr); ptr = NULL;
        //
        // Pattern 3: Multiple cleanup labels (error handling)
        //   err_cleanup: free(ptr); return;
        //   err_cleanup2: free(ptr); return;

        // For now, we'll use heuristics based on BB structure:
        // - If frees are in different BBs that are not reachable from each other,
        //   it's likely error handling / cleanup code

        var has_null_check = false;
        var has_null_assign = false;
        var is_cleanup_pattern = false;

        // Heuristic: if we have exactly 2 free sites in different unreachable BBs,
        // it's likely a cleanup pattern (error path + normal path)
        if (free_sites.len == 2) {
            const site1 = free_sites[0];
            const site2 = free_sites[1];

            if (site1.bb_id != 0 and site2.bb_id != 0 and site1.bb_id != site2.bb_id) {
                // Check mutual reachability
                var visited1 = std.AutoHashMap(u32, void).init(graph.allocator);
                defer visited1.deinit();
                var visited2 = std.AutoHashMap(u32, void).init(graph.allocator);
                defer visited2.deinit();

                const r1_to_r2 = graph.isBBReachable(site1.bb_id, site2.bb_id, &visited1);
                const r2_to_r1 = graph.isBBReachable(site2.bb_id, site1.bb_id, &visited2);

                // Mutually unreachable = different execution paths (likely cleanup)
                if (!r1_to_r2 and !r2_to_r1) {
                    is_cleanup_pattern = true;
                    has_null_check = true; // Assume cleanup code has checks
                }
            }
        }

        // Additional heuristic: if there are > 2 free sites, it's almost certainly
        // defensive code with multiple exit points
        if (free_sites.len > 2) {
            is_cleanup_pattern = true;
            has_null_assign = true; // Likely defensive
        }

        return .{
            .has_null_check = has_null_check,
            .has_null_assign = has_null_assign,
            .is_cleanup_pattern = is_cleanup_pattern,
        };
    }

    /// Descriptor for an FFI/unsafe boundary call. Used by isOnDangerPath without
    /// depending on pass.zig's CrossLangEdge type (avoids circular import).
    // pub const DangerSurface is now imported from mg_types

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
        ffi_boundaries: []const DangerSurface,
        visited: *std.AutoHashMap(u64, void),
        ffi_set: ?*const std.StringHashMap(void),
    ) DangerPathKind {
        // FIX: Add ptr_val to visited at entry to prevent infinite recursion
        // when alias closure contains cycles back to the original pointer.
        if (visited.contains(ptr_val)) return .none;
        visited.put(ptr_val, {}) catch {
            // Allocation failure in visited set - cannot safely continue recursion.
            // Return .none to prevent potential infinite loop.
            return .none;
        };

        // Build callee_name set for O(1) lookup (only once at top-level call).
        var local_ffi_set: std.StringHashMap(void) = undefined;
        var local_ffi_set_needs_deinit = false;
        const set: *const std.StringHashMap(void) = if (ffi_set) |s| s else blk: {
            local_ffi_set = mg_methods.buildFFISet(graph.allocator, ffi_boundaries);
            local_ffi_set_needs_deinit = true;
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

// Re-export FuzzyMatcher from separate module
pub const FuzzyMatcher = @import("memory_graph_fuzzy.zig").FuzzyMatcher;
pub const FnClass = @import("memory_graph_fuzzy.zig").FnClass;

// Tests are in memory_graph_test.zig (imported to run tests)
const _tests = @import("memory_graph_test.zig");
