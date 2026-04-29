//! Memory Graph module for pointer identity tracking and double-free detection.
//!
//! Tracks pointer EQUALITY (do two pointers point to the same allocation?)
//! rather than just counting alloc/free. This enables cross-alias double-free
//! detection: ptr1 = malloc(); ptr2 = ptr1; free(ptr2); free(ptr1).
//!
//! Uses direct allocator (no arena) for clean deinit and zero leaks.

const std = @import("std");

/// Error set for memory graph operations.
pub const MemoryGraphError = error{
    OutOfMemory,
    NodeNotFound,
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

    /// Initializes a new memory graph.
    pub fn init(allocator: std.mem.Allocator) MemoryGraphError!MemoryGraph {
        return MemoryGraph{
            .nodes = std.AutoHashMap(u64, *AllocNode).init(allocator),
            .node_store = .{},
            .allocator = allocator,
            .next_id = 1,
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
        graph.* = undefined;
    }

    /// Creates a new allocation node and returns its ID.
    /// Accepts raw pointer values as u64 to avoid cross-cimport type mismatches.
    pub fn trackAlloc(
        graph: *MemoryGraph,
        alloc_inst_ptr: u64,
        ret_value_ptr: u64,
    ) MemoryGraphError!u64 {
        const id = graph.next_id;
        graph.next_id += 1;

        const merkle_hash = hashValues(&.{
            alloc_inst_ptr,
            ret_value_ptr,
            id,
        });

        const node = try graph.allocator.create(AllocNode);
        node.* = AllocNode{
            .id = id,
            .alloc_inst = alloc_inst_ptr,
            .merkle_root = merkle_hash,
            .aliases = std.AutoHashMap(u64, void).init(graph.allocator),
            .freed = false,
            .freed_by = null,
        };

        try node.aliases.put(ret_value_ptr, {});
        try graph.nodes.put(ret_value_ptr, node);
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

    /// Checks if a pointer value has been freed.
    pub fn isFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse return false;
        return node.freed;
    }

    /// Gets allocation info for a pointer.
    pub fn getAllocInfo(graph: *MemoryGraph, ptr_val: u64) ?*const AllocNode {
        return graph.nodes.get(ptr_val);
    }

    /// Resets the graph for reuse (clears all state but retains capacity).
    pub fn reset(graph: *MemoryGraph) void {
        for (graph.node_store.items) |node| {
            node.aliases.deinit();
            graph.allocator.destroy(node);
        }
        graph.node_store.clearRetainingCapacity();
        graph.nodes.clearRetainingCapacity();
        graph.next_id = 1;
    }
};

/// FNV-1a hash with intentional overflow (RFC 7049).
///
/// Uses the Fowler-Noll-Vo hash algorithm variant 1a for combining
/// multiple u64 values into a single hash key. This is used for
/// deduplication keys in MemoryGraph node lookups.
///
/// **Why wrapping multiply?**
/// FNV-1a deliberately uses modular arithmetic overflow as part of
/// its mixing function. The `*%` operator in Zig performs wrapping
/// multiplication which matches the FNV specification. This is NOT
/// a bug - overflow is mathematically expected and required.
///
/// Parameters:
///   - values: Array of u64 values to hash
///
/// Returns:
///   - Combined 64-bit hash value
fn hashValues(values: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325; // FNV offset basis (64-bit)
    for (values) |val| {
        hash ^= val; // FNV-1a: XOR before multiply
        // Wrapping multiply is correct here - overflow is expected in FNV-1a
        hash = hash *% 0x100000001b3; // FNV prime (64-bit)
    }
    return hash;
}

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

    const alloc_id = try graph.trackAlloc(fake_malloc, fake_ret);
    try std.testing.expectEqual(@as(u64, 1), alloc_id);

    const node = graph.nodes.get(fake_ret);
    try std.testing.expect(node != null);
    try std.testing.expectEqual(@as(u64, 1), node.?.id);
    try std.testing.expect(!node.?.freed);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret1);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret);

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

    _ = try graph.trackAlloc(fake_malloc, fake_ret1);
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

    _ = try graph.trackAlloc(fake_malloc, fake_ret);

    try std.testing.expect(!graph.isFreed(fake_ret));

    _ = try graph.trackFree(fake_free, fake_ret);
    try std.testing.expect(graph.isFreed(fake_ret));
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

    // Allocate many nodes and aliases, then free.
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        _ = try graph.trackAlloc(i * 0x1000, i * 0x1000 + 1);
        if (i > 0) {
            try graph.trackAlias(i * 0x1000 + 1, (i - 1) * 0x1000 + 1);
        }
    }

    // Free half of them.
    i = 0;
    while (i < 50) : (i += 1) {
        _ = try graph.trackFree(i * 0x1000 + 2, i * 0x1000 + 1);
    }
}
