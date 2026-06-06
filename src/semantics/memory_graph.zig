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
pub const OwnershipTransferReason = mg_types.OwnershipTransferReason;
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

// Wave 3: Split out call edge/counter tracking and BB analysis methods
const mg_calls = @import("memory_graph_calls.zig");
const mg_analysis = @import("memory_graph_analysis.zig");

const mg_methods = @import("memory_graph_methods.zig");

/// Result of analyzeDoubleFreeWithConfidence analysis
pub const DoubleFreeAnalysisResult = struct {
    is_double_free: bool,
    confidence: f32,
    reason: []const u8,
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

    /// Mark a pointer as having its ownership intentionally transferred (e.g., via Box::into_raw).
    /// This records the transfer fact in the MemoryGraph so downstream passes
    /// (cross_lang_dataflow, free validation) know the transfer is deliberate.
    /// Uses `reason` to annotate why (e.g., .into_raw_transfer for Rust's into_raw pattern).
    pub fn markOwnershipTransferred(graph: *MemoryGraph, ptr_val: u64, reason: OwnershipTransferReason) void {
        // Try to find existing node by pointer value
        var node = graph.nodes.get(ptr_val);

        if (node == null) {
            // No direct match — search by alloc_inst field
            for (graph.node_store.items) |n| {
                if (n.alloc_inst == ptr_val) {
                    node = n;
                    break;
                }
            }
        }

        if (node) |n| {
            n.zone = .ffi;
            n.alloc_callee = @tagName(reason);
            log.debug("MEMORY: Node {} (ptr 0x{x}) ownership transferred via '{s}'", .{
                n.id, ptr_val, @tagName(reason),
            });
        } else {
            log.debug("MEMORY: No node found for ptr 0x{x} to mark ownership transfer", .{ptr_val});
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
    // Wrapper methods for backward compatibility
    pub fn classifyAllocFamily(self: *MemoryGraph, ptr_val: u64, callee_name: []const u8) void {
        return mg_escape.classifyAllocFamily(self, ptr_val, callee_name);
    }
    pub fn classifyReleaseFamily(self: *MemoryGraph, ptr_val: u64, callee_name: []const u8) void {
        return mg_escape.classifyReleaseFamily(self, ptr_val, callee_name);
    }
    pub fn recordEscapeReturnToCaller(self: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
        return mg_escape.recordEscapeReturnToCaller(self, ptr_val, inst_addr);
    }
    pub fn recordEscapeOutParam(self: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
        return mg_escape.recordEscapeOutParam(self, ptr_val, inst_addr);
    }
    pub fn recordEscapeFieldStore(self: *MemoryGraph, ptr_val: u64, inst_addr: u64, field_name: []const u8) void {
        return mg_escape.recordEscapeFieldStore(self, ptr_val, inst_addr, field_name);
    }
    pub fn recordEscapeGlobalStore(self: *MemoryGraph, ptr_val: u64, inst_addr: u64, var_name: []const u8) void {
        return mg_escape.recordEscapeGlobalStore(self, ptr_val, inst_addr, var_name);
    }
    pub fn recordEscapeStaticLifetime(self: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
        return mg_escape.recordEscapeStaticLifetime(self, ptr_val, inst_addr);
    }
    pub fn recordEscapeCallback(self: *MemoryGraph, ptr_val: u64, inst_addr: u64, callback_name: []const u8) void {
        return mg_escape.recordEscapeCallback(self, ptr_val, inst_addr, callback_name);
    }
    pub fn recordEscapeThread(self: *MemoryGraph, ptr_val: u64, inst_addr: u64, thread_api: []const u8) void {
        return mg_escape.recordEscapeThread(self, ptr_val, inst_addr, thread_api);
    }
    pub fn hasValidEscape(self: *const MemoryGraph, ptr_val: u64) bool {
        return mg_escape.hasValidEscape(self, ptr_val);
    }
    pub fn hasLifetimeRiskEscape(self: *const MemoryGraph, ptr_val: u64) bool {
        return mg_escape.hasLifetimeRiskEscape(self, ptr_val);
    }

    // Wave 3: Call edge tracking & counters (split to memory_graph_calls.zig)
    pub fn recordFuncAlloc(self: *MemoryGraph, func_ptr: u64) void {
        return mg_calls.recordFuncAlloc(self, func_ptr);
    }
    pub fn recordFuncFree(self: *MemoryGraph, func_ptr: u64) void {
        return mg_calls.recordFuncFree(self, func_ptr);
    }
    pub fn recordFuncReturns(self: *MemoryGraph, func_ptr: u64) void {
        return mg_calls.recordFuncReturns(self, func_ptr);
    }
    pub fn getFuncCounter(self: *MemoryGraph, func_ptr: u64) FuncCounter {
        return mg_calls.getFuncCounter(self, func_ptr);
    }
    pub fn recordContentSource(self: *MemoryGraph, dest_ptr: u64, content_kind: SourceKind) void {
        return mg_calls.recordContentSource(self, dest_ptr, content_kind);
    }
    pub fn getContentSource(self: *MemoryGraph, dest_ptr: u64) SourceKind {
        return mg_calls.getContentSource(self, dest_ptr);
    }
    pub fn resolveContentSource(self: *MemoryGraph, ptr_val: u64) SourceKind {
        return mg_calls.resolveContentSource(self, ptr_val);
    }
    pub fn trackCallArg(self: *MemoryGraph, caller_inst: u64, callee_name: []const u8, arg_ptr: u64, arg_index: u32) !void {
        return mg_calls.trackCallArg(self, caller_inst, callee_name, arg_ptr, arg_index);
    }
    pub fn trackCallRet(self: *MemoryGraph, caller_inst: u64, callee_name: []const u8, ret_ptr: u64) !void {
        return mg_calls.trackCallRet(self, caller_inst, callee_name, ret_ptr);
    }
    pub fn getCallArgsForPtr(self: *MemoryGraph, ptr_val: u64) []const u32 {
        return mg_calls.getCallArgsForPtr(self, ptr_val);
    }
    pub fn getCallRetsFromCallee(self: *MemoryGraph, callee_name: []const u8) []const u32 {
        return mg_calls.getCallRetsFromCallee(self, callee_name);
    }
    pub fn getCallRetsForPtr(self: *MemoryGraph, ptr_val: u64) []const u32 {
        return mg_calls.getCallRetsForPtr(self, ptr_val);
    }
    pub fn getCallArgsForCallee(self: *MemoryGraph, callee_name: []const u8) []const u32 {
        return mg_calls.getCallArgsForCallee(self, callee_name);
    }
    pub fn isPassedAsArg(self: *MemoryGraph, ptr_val: u64) bool {
        return mg_calls.isPassedAsArg(self, ptr_val);
    }
    pub fn isReturnedFromCall(self: *MemoryGraph, ptr_val: u64) bool {
        return mg_calls.isReturnedFromCall(self, ptr_val);
    }

    // Wave 3: BB analysis & danger path (split to memory_graph_analysis.zig)
    pub fn isLeaked(self: *MemoryGraph, ptr_val: u64) bool {
        return mg_analysis.isLeaked(self, ptr_val);
    }
    pub fn isDoubleFreed(self: *MemoryGraph, ptr_val: u64) bool {
        return mg_analysis.isDoubleFreed(self, ptr_val);
    }
    pub fn addBBEdge(self: *MemoryGraph, from_bb: u32, to_bb: u32) !void {
        return mg_analysis.addBBEdge(self, from_bb, to_bb);
    }
    pub fn isBBReachable(self: *MemoryGraph, from_bb: u32, to_bb: u32, visited: *std.AutoHashMap(u32, void)) bool {
        return mg_analysis.isBBReachable(self, from_bb, to_bb, visited);
    }
    pub fn isDoubleFreedOnSamePath(self: *MemoryGraph, ptr_val: u64) bool {
        return mg_analysis.isDoubleFreedOnSamePath(self, ptr_val);
    }
    pub fn analyzeDoubleFreeWithConfidence(self: *MemoryGraph, ptr_val: u64) DoubleFreeAnalysisResult {
        return mg_analysis.analyzeDoubleFreeWithConfidence(self, ptr_val);
    }
    pub fn isOnDangerPath(self: *MemoryGraph, ptr_val: u64, ffi_boundaries: []const DangerSurface, visited: *std.AutoHashMap(u64, void), ffi_set: ?*const std.StringHashMap(void)) DangerPathKind {
        return mg_analysis.isOnDangerPath(self, ptr_val, ffi_boundaries, visited, ffi_set);
    }
    pub fn isUseAfterFreeViaAlias(self: *MemoryGraph, ptr_val: u64, use_inst: u64) ?*const AllocNode {
        return mg_analysis.isUseAfterFreeViaAlias(self, ptr_val, use_inst);
    }
    pub fn findDangerousAliases(self: *MemoryGraph, ptr_val: u64, allocator: std.mem.Allocator) ![]u64 {
        return mg_analysis.findDangerousAliases(self, ptr_val, allocator);
    }
    pub fn validateOwnershipTransfer(self: *MemoryGraph, from_func: u64, to_func: u64, ptr_val: u64) OwnershipTransferStatus {
        return mg_analysis.validateOwnershipTransfer(self, from_func, to_func, ptr_val);
    }
    pub fn analyzeLifecycle(self: *MemoryGraph, alloc_inst: u64, allocator: std.mem.Allocator) !ResourceLifecycle {
        return mg_analysis.analyzeLifecycle(self, alloc_inst, allocator);
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
};

// Re-export FuzzyMatcher from separate module
pub const FuzzyMatcher = @import("memory_graph_fuzzy.zig").FuzzyMatcher;
pub const FnClass = @import("memory_graph_fuzzy.zig").FnClass;

// Tests are in memory_graph_test.zig (imported to run tests)
const _tests = @import("memory_graph_test.zig");
