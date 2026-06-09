//! Memory Graph Call Edge & Counter Tracking
//!
//! Extracted from memory_graph.zig to keep file under 1000 lines.
//! Contains: function counter tracking, content source tracking,
//! and call edge tracking/query functions.

const std = @import("std");
const log = @import("../common/log.zig");

const mg_types = @import("../types/memory_graph_types.zig");
const SourceKind = mg_types.SourceKind;
const FuncCounter = mg_types.FuncCounter;
const CallArgEdge = mg_types.CallArgEdge;
const CallRetEdge = mg_types.CallRetEdge;
const mg_methods = @import("memory_graph_methods.zig");

const MemoryGraph = @import("memory_graph.zig").MemoryGraph;

// =====================================================================
// Per-function alloc/free counters
// =====================================================================

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
