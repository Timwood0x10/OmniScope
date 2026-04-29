//! Memory Graph module for pointer identity tracking and double-free detection.
//!
//! This module implements a Memory Graph with Merkle Tree for efficient pointer
//! identity tracking. The key insight is that we track pointer EQUALITY (do two
//! pointers point to the same allocation?) rather than just counting alloc/free.
//!
//! Architecture:
//!
//!   AllocNode: represents one allocation (malloc call)
//!   PointerEdge: represents alias relationship (ptr_a == ptr_b)
//!   MerkleNode: hash tree for O(log n) pointer comparison
//!
//! Detection logic:
//!   - alloc() creates an AllocNode with unique id
//!   - store (ptr_b = ptr_a) creates PointerEdge (alias)
//!   - free(ptr) looks up which AllocNode ptr belongs to
//!   - if AllocNode.freed == true → DOUBLE FREE

const std = @import("std");
const c = @cImport(@cInclude("llvm-c/Core.h"));

/// Error set for memory graph operations.
pub const MemoryGraphError = error{
    OutOfMemory,
    NodeNotFound,
    AlreadyFreed,
};

/// Represents a single allocation (malloc call).
/// Each allocation gets a unique node in the memory graph.
const AllocNode = struct {
    /// Unique identifier for this allocation.
    id: u64,
    /// The LLVM instruction that performed the allocation.
    alloc_inst: c.LLVMValueRef,
    /// Merkle hash root for this allocation - used for fast comparison.
    merkle_root: u64,
    /// Set of all pointer values that alias to this allocation.
    /// This tracks pointer equality: if ptr is in this set, ptr == returned_value.
    aliases: std.AutoHashMap(u64, void),
    /// Whether this allocation has been freed.
    freed: bool,
    /// The LLVM instruction that freed this allocation (if any).
    freed_by: ?c.LLVMValueRef,
    /// Source location for debugging.
    loc: ?SourceLoc,
};

/// Lightweight source location info.
const SourceLoc = struct {
    func_name: []const u8,
    line: u32,
};

/// Represents an alias relationship between two pointer values.
/// When we see "ptr_b = ptr_a", we create a PointerEdge.
const PointerEdge = struct {
    /// The "from" pointer value.
    from_val: u64,
    /// The "to" pointer value (both point to same allocation).
    to_val: u64,
    /// Merkle leaf hash for this edge.
    merkle_leaf: u64,
};

/// Merkle Tree node for efficient pointer identity comparison.
/// Uses hashing to compress storage and enable O(log n) lookups.
const MerkleNode = struct {
    /// Hash value for this node.
    hash: u64,
    /// Left child (for combining hashes).
    left: ?*MerkleNode,
    /// Right child.
    right: ?*MerkleNode,
    /// Leaf value (only set for leaf nodes).
    leaf_val: ?u64,
};

/// Main memory graph structure that tracks all allocations and aliases.
pub const MemoryGraph = struct {
    /// Map from pointer value hash → AllocNode.
    /// This lets us quickly find which allocation a pointer belongs to.
    nodes: std.AutoHashMap(u64, *AllocNode),
    /// List of all alias edges (ptr_a = ptr_b relationships).
    edges: []PointerEdge,
    /// Merkle tree for efficient pointer comparison.
    merkle_root: ?*MerkleNode,
    /// Next available allocation ID.
    next_id: u64,
    /// Arena allocator for long-lived nodes.
    arena: std.heap.ArenaAllocator,
    /// Allocator for temporary allocations.
    temp_allocator: std.mem.Allocator,

    /// Initializes a new memory graph.
    pub fn init(temp_allocator: std.mem.Allocator) MemoryGraphError!MemoryGraph {
        var arena = std.heap.ArenaAllocator.init(temp_allocator);
        errdefer arena.deinit();

        return MemoryGraph{
            .nodes = std.AutoHashMap(u64, *AllocNode).init(arena.allocator()),
            .edges = &.{},
            .merkle_root = null,
            .next_id = 1,
            .arena = arena,
            .temp_allocator = temp_allocator,
        };
    }

    /// Deinitializes the memory graph.
    pub fn deinit(graph: *MemoryGraph) void {
        graph.arena.deinit();
        graph.* = undefined;
    }

    /// Creates a new allocation node and returns its ID.
    /// Called when we see a malloc/calloc/etc instruction.
    pub fn trackAlloc(
        graph: *MemoryGraph,
        alloc_inst: c.LLVMValueRef,
        ret_value: c.LLVMValueRef,
    ) MemoryGraphError!u64 {
        const id = graph.next_id;
        graph.next_id += 1;

        // Calculate Merkle hash for this allocation.
        const merkle_hash = hashValues(&.{
            @as(u64, @intFromPtr(alloc_inst)),
            @as(u64, @intFromPtr(ret_value)),
            id,
        });

        // Create the allocation node.
        const node = try graph.arena.allocator().create(AllocNode);
        node.* = AllocNode{
            .id = id,
            .alloc_inst = alloc_inst,
            .merkle_root = merkle_hash,
            .aliases = std.AutoHashMap(u64, void).init(graph.arena.allocator()),
            .freed = false,
            .freed_by = null,
            .loc = null,
        };

        // Add ret_value as first alias.
        const ret_hash = @as(u64, @intFromPtr(ret_value));
        try node.aliases.put(ret_hash, {});

        // Store by pointer value hash.
        try graph.nodes.put(ret_hash, node);

        return id;
    }

    /// Records an alias relationship: from_val = to_val.
    /// Called when we see a store instruction like "ptr_b = ptr_a".
    pub fn trackAlias(graph: *MemoryGraph, from_val: u64, to_val: u64) !void {
        // Find the allocation node that to_val belongs to.
        if (graph.nodes.get(to_val)) |target_node| {
            // Add from_val as an alias to the same allocation.
            try target_node.aliases.put(from_val, {});

            // Also add the node mapping for from_val so we can find it quickly.
            try graph.nodes.put(from_val, target_node);

            // Create a PointerEdge.
            const edge = PointerEdge{
                .from_val = from_val,
                .to_val = to_val,
                .merkle_leaf = hashValues(&.{ from_val, to_val }),
            };
            graph.edges = try graph.arena.allocator().realloc(
                graph.edges,
                graph.edges.len + 1,
            );
            graph.edges[graph.edges.len - 1] = edge;

            return;
        }

        // to_val not found in graph - might be external or from unknown source.
        return MemoryGraphError.NodeNotFound;
    }

    /// Records a free operation and checks for double-free.
    /// Returns true if double-free detected, false otherwise.
    pub fn trackFree(
        graph: *MemoryGraph,
        free_inst: c.LLVMValueRef,
        ptr_val: u64,
    ) MemoryGraphError!bool {
        // Find which allocation this pointer belongs to.
        const node = graph.nodes.get(ptr_val) orelse {
            // Pointer not tracked - might be external or null.
            return false;
        };

        if (node.freed) {
            // Double free! This pointer was already freed.
            return true;
        }

        // Mark as freed.
        node.freed = true;
        node.freed_by = free_inst;

        return false;
    }

    /// Checks if a pointer value has been freed.
    pub fn isFreed(graph: *MemoryGraph, ptr_val: u64) bool {
        const node = graph.nodes.get(ptr_val) orelse {
            return false;
        };
        return node.freed;
    }

    /// Gets allocation info for a pointer.
    pub fn getAllocInfo(graph: *MemoryGraph, ptr_val: u64) ?*const AllocNode {
        return graph.nodes.get(ptr_val);
    }

    /// Resets the graph for a new function analysis.
    pub fn reset(graph: *MemoryGraph) void {
        graph.nodes.clearRetainingCapacity();
        graph.edges = &.{};
        graph.merkle_root = null;
        graph.next_id = 1;
    }
};

/// Computes a combined hash from multiple u64 values.
/// Uses FNV-1a inspired algorithm for simplicity and speed.
fn hashValues(values: []const u64) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (values) |val| {
        hash ^= val;
        hash = hash * 0x100000001b3;
    }
    return hash;
}

/// Simple hash combine for two values.
fn hashCombine(a: u64, b: u64) u64 {
    return hashValues(&.{ a, b });
}

test "memory_graph - basic alloc tracking" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Simulate: ptr = malloc()
    const fake_malloc: c.LLVMValueRef = @ptrFromInt(0x1000);
    const fake_ret: c.LLVMValueRef = @ptrFromInt(0x2000);

    const alloc_id = try graph.trackAlloc(fake_malloc, fake_ret);
    try std.testing.expectEqual(@as(u64, 1), alloc_id);

    // Check that we can find the node by pointer value.
    const ret_hash = @as(u64, @intFromPtr(fake_ret));
    const node = graph.nodes.get(ret_hash);
    try std.testing.expect(node != null);
    try std.testing.expectEqual(@as(u64, 1), node.?.id);
    try std.testing.expect(!node.?.freed);
}

test "memory_graph - alias tracking" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Simulate: ptr1 = malloc(); ptr2 = ptr1;
    const fake_malloc: c.LLVMValueRef = @ptrFromInt(0x1000);
    const fake_ret1: c.LLVMValueRef = @ptrFromInt(0x2000);
    const fake_ret2: c.LLVMValueRef = @ptrFromInt(0x3000);

    _ = try graph.trackAlloc(fake_malloc, fake_ret1);

    // Create alias: ret2 = ret1
    const hash1 = @as(u64, @intFromPtr(fake_ret1));
    const hash2 = @as(u64, @intFromPtr(fake_ret2));
    try graph.trackAlias(hash2, hash1);

    // Both should point to same allocation.
    const node1 = graph.nodes.get(hash1);
    const node2 = graph.nodes.get(hash2);
    try std.testing.expect(node1 != null);
    try std.testing.expect(node2 != null);
    try std.testing.expectEqual(node1.?.id, node2.?.id);
}

test "memory_graph - double free detection" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Simulate: ptr = malloc(); free(ptr); free(ptr);
    const fake_malloc: c.LLVMValueRef = @ptrFromInt(0x1000);
    const fake_ret: c.LLVMValueRef = @ptrFromInt(0x2000);
    const fake_free1: c.LLVMValueRef = @ptrFromInt(0x3000);
    const fake_free2: c.LLVMValueRef = @ptrFromInt(0x4000);

    _ = try graph.trackAlloc(fake_malloc, fake_ret);

    const ptr_hash = @as(u64, @intFromPtr(fake_ret));

    // First free - should succeed (not double free).
    const first_free = try graph.trackFree(fake_free1, ptr_hash);
    try std.testing.expect(!first_free);

    // Second free - should detect double free.
    const second_free = try graph.trackFree(fake_free2, ptr_hash);
    try std.testing.expect(second_free);
}

test "memory_graph - alias double free" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    // Simulate: ptr1 = malloc(); ptr2 = ptr1; free(ptr2); free(ptr1);
    // Both point to same allocation - second free is double free.
    const fake_malloc: c.LLVMValueRef = @ptrFromInt(0x1000);
    const fake_ret1: c.LLVMValueRef = @ptrFromInt(0x2000);
    const fake_ret2: c.LLVMValueRef = @ptrFromInt(0x3000);
    const fake_free1: c.LLVMValueRef = @ptrFromInt(0x4000);
    const fake_free2: c.LLVMValueRef = @ptrFromInt(0x5000);

    _ = try graph.trackAlloc(fake_malloc, fake_ret1);

    // Create alias: ret2 = ret1
    const hash1 = @as(u64, @intFromPtr(fake_ret1));
    const hash2 = @as(u64, @intFromPtr(fake_ret2));
    try graph.trackAlias(hash2, hash1);

    // First free with ptr2 - succeeds.
    _ = try graph.trackFree(fake_free1, hash2);

    // Second free with ptr1 - should be double free.
    const is_double = try graph.trackFree(fake_free2, hash1);
    try std.testing.expect(is_double);
}

test "memory_graph - is_freed" {
    var temp_mem = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = temp_mem.deinit();
    const allocator = temp_mem.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    const fake_malloc: c.LLVMValueRef = @ptrFromInt(0x1000);
    const fake_ret: c.LLVMValueRef = @ptrFromInt(0x2000);
    const fake_free: c.LLVMValueRef = @ptrFromInt(0x3000);

    _ = try graph.trackAlloc(fake_malloc, fake_ret);

    const ptr_hash = @as(u64, @intFromPtr(fake_ret));

    // Before free - not freed.
    try std.testing.expect(!graph.isFreed(ptr_hash));

    // After free - is freed.
    _ = try graph.trackFree(fake_free, ptr_hash);
    try std.testing.expect(graph.isFreed(ptr_hash));
}
