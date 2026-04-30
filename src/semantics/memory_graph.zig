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
/// Tracks how many heap allocations and frees a function performs.
pub const FuncCounter = struct {
    /// Number of heap/resource allocations in this function.
    allocs: u32,
    /// Number of free calls in this function.
    frees: u32,

    /// Net allocation count: positive means more allocs than frees.
    pub fn net(self: FuncCounter) i64 {
        return @as(i64, @intCast(self.allocs)) - @as(i64, @intCast(self.frees));
    }

    /// Whether this function has any heap operations at all.
    pub fn hasHeapOps(self: FuncCounter) bool {
        return self.allocs > 0 or self.frees > 0;
    }
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
};

/// Main memory graph structure.
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
    /// Key: function pointer value (u64), Value: FuncCounter.
    func_counters: std.AutoHashMap(u64, FuncCounter),

    /// Content source tracking: maps a storage location (alloca/heap) to
    /// the SourceKind of the pointer value stored in it.
    /// When `store ptr %heap_ptr, ptr %alloca`, we record:
    ///   content_sources[%alloca] = .heap_alloc
    /// This lets load instructions inherit the stored content's source kind.
    content_sources: std.AutoHashMap(u64, SourceKind),

    /// Initializes a new memory graph.
    pub fn init(allocator: std.mem.Allocator) MemoryGraphError!MemoryGraph {
        return MemoryGraph{
            .nodes = std.AutoHashMap(u64, *AllocNode).init(allocator),
            .node_store = .{},
            .allocator = allocator,
            .next_id = 1,
            .func_counters = std.AutoHashMap(u64, FuncCounter).init(allocator),
            .content_sources = std.AutoHashMap(u64, SourceKind).init(allocator),
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
    ) MemoryGraphError!bool {
        const node = graph.nodes.get(ptr_val) orelse {
            return false;
        };

        if (node.freed) {
            return true;
        }

        node.freed = true;
        node.freed_by = free_inst_ptr;
        return false;
    }

    // =====================================================================
    // Per-function alloc/free balance
    // =====================================================================

    /// Records a heap allocation in a function's counter.
    pub fn recordFuncAlloc(graph: *MemoryGraph, func_ptr: u64) void {
        const gop = graph.func_counters.getOrPut(func_ptr) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .allocs = 0, .frees = 0 };
        }
        gop.value_ptr.allocs += 1;
    }

    /// Records a free call in a function's counter.
    pub fn recordFuncFree(graph: *MemoryGraph, func_ptr: u64) void {
        const gop = graph.func_counters.getOrPut(func_ptr) catch return;
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .allocs = 0, .frees = 0 };
        }
        gop.value_ptr.frees += 1;
    }

    /// Gets the alloc/free counter for a function.
    /// Returns zero-initialized counter if the function is not tracked.
    pub fn getFuncCounter(graph: *MemoryGraph, func_ptr: u64) FuncCounter {
        return graph.func_counters.get(func_ptr) orelse .{ .allocs = 0, .frees = 0 };
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
        graph.next_id = 1;
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
        if (endsWithLower(fn_name, "malloc") or
            endsWithLower(fn_name, "calloc") or
            endsWithLower(fn_name, "realloc") or
            endsWithLower(fn_name, "_alloc") or
            endsWithLower(fn_name, "alloc") or
            indexOfLower(fn_name, "alloc") != null)
        {
            return .alloc;
        }

        if (endsWithLower(fn_name, "free") or
            endsWithLower(fn_name, "_free") or
            indexOfLower(fn_name, "dealloc") != null)
        {
            return .free;
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

        if (endsWithLower(fn_name, "_init") or
            endsWithLower(fn_name, "init"))
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

    const alloc_id = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc);

    const first_free = try graph.trackFree(fake_free1, fake_ret);
    try std.testing.expect(!first_free);

    const second_free = try graph.trackFree(fake_free2, fake_ret);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret1, .heap_alloc);
    try graph.trackAlias(fake_ret2, fake_ret1);

    _ = try graph.trackFree(fake_free1, fake_ret2);

    const is_double = try graph.trackFree(fake_free2, fake_ret1);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc);

    try std.testing.expect(!graph.isFreed(fake_ret));

    _ = try graph.trackFree(fake_free, fake_ret);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret, .heap_alloc);
    try std.testing.expectEqual(SourceKind.heap_alloc, graph.getSourceKind(fake_ret));

    _ = try graph.trackAlloc(fake_alloca, fake_alloca, .alloca);
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
    _ = try graph.trackAlloc(alloca_ptr, alloca_ptr, .alloca);
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
        _ = try graph.trackAlloc(i * 0x1000, i * 0x1000 + 1, .heap_alloc);
        if (i > 0) {
            try graph.trackAlias(i * 0x1000 + 1, (i - 1) * 0x1000 + 1);
        }
        graph.recordFuncAlloc(0xA000);
        graph.recordContentSource(i * 0x1000, .alloca);
    }

    i = 0;
    while (i < 50) : (i += 1) {
        _ = try graph.trackFree(i * 0x1000 + 2, i * 0x1000 + 1);
        graph.recordFuncFree(0xA000);
    }
}
