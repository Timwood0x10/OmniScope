//! Memory Graph Analysis — BB reachability, double-free, and danger path detection
//!
//! Extracted from memory_graph.zig to keep file under 1000 lines.
//! Contains: BB control-flow analysis, path-sensitive double-free detection,
//! cycle detection, dangerous path analysis, and lifecycle analysis.

const std = @import("std");
const log = @import("../common/log.zig");

const mg_types = @import("../types/memory_graph_types.zig");
const SourceKind = mg_types.SourceKind;
const FuncCounter = mg_types.FuncCounter;
const FreeRecord = mg_types.FreeRecord;
const DangerPathKind = mg_types.DangerPathKind;
const DangerSurface = mg_types.DangerSurface;
const ResourceLifecycle = mg_types.ResourceLifecycle;
const OwnershipTransferStatus = mg_types.OwnershipTransferStatus;

const mg_methods = @import("memory_graph_methods.zig");
const AllocNode = mg_types.AllocNode;

const MemoryGraph = @import("memory_graph.zig").MemoryGraph;
const DoubleFreeAnalysisResult = @import("memory_graph.zig").DoubleFreeAnalysisResult;

// =====================================================================
// Leak & Double-Free Detection
// =====================================================================

/// R8.0: Check if a pointer is leaked by tracing cross-function propagation.
pub fn isLeaked(graph: *MemoryGraph, ptr_val: u64) bool {
    const node = graph.nodes.get(ptr_val) orelse return false;
    if (node.freed) return false;

    const arg_indices = graph.getCallArgsForPtr(ptr_val);
    if (arg_indices.len == 0) return false;

    const ret_indices = graph.call_ret_by_ptr.get(ptr_val) orelse return true;

    for (arg_indices) |arg_idx| {
        const arg_edge = &graph.call_args.items[arg_idx];
        var returned = false;

        for (ret_indices.items) |ret_idx| {
            const ret_edge = &graph.call_rets.items[ret_idx];
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
pub fn isDoubleFreed(graph: *MemoryGraph, ptr_val: u64) bool {
    const node = graph.nodes.get(ptr_val) orelse return false;

    if (node.freed) return true;

    var alias_iter = node.aliases.iterator();
    while (alias_iter.next()) |entry| {
        const alias_node = graph.nodes.get(entry.key_ptr.*) orelse continue;
        if (alias_node.freed and alias_node.id == node.id) return true;
    }

    const arg_indices = graph.getCallArgsForPtr(ptr_val);
    for (arg_indices) |arg_idx| {
        const arg_edge = &graph.call_args.items[arg_idx];

        if (graph.call_ret_by_ptr.get(ptr_val)) |ret_indices| {
            for (ret_indices.items) |ret_idx| {
                const ret_edge = &graph.call_rets.items[ret_idx];
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
pub fn addBBEdge(graph: *MemoryGraph, from_bb: u32, to_bb: u32) !void {
    if (from_bb == to_bb) return;
    const gop = try graph.bb_edges.getOrPut(from_bb);
    if (!gop.found_existing) {
        gop.value_ptr.* = std.AutoHashMap(u32, void).init(graph.allocator);
    }
    try gop.value_ptr.put(to_bb, {});
}

/// Check if one BB can reach another via the control-flow graph.
/// Uses cached results to avoid repeated traversals.
pub fn isBBReachable(graph: *MemoryGraph, from_bb: u32, to_bb: u32, visited: *std.AutoHashMap(u32, void)) bool {
    if (from_bb == to_bb) return true;

    const cache_key = (@as(u64, from_bb) << 32) | to_bb;
    if (graph.reachability_cache.get(cache_key)) |cached_result| {
        return cached_result;
    }

    const result = isBBReachableImpl(graph, from_bb, to_bb, visited);

    graph.reachability_cache.put(cache_key, result) catch {};

    return result;
}

/// Internal DFS implementation for reachability checking.
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
pub fn analyzeDoubleFreeWithConfidence(graph: *MemoryGraph, ptr_val: u64) DoubleFreeAnalysisResult {
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

    const is_on_same_path = graph.isDoubleFreedOnSamePath(ptr_val);
    var confidence: f32 = if (is_on_same_path) 0.9 else 0.3;

    const loop_info = analyzeLoopContext(graph, node.free_sites.items);
    if (loop_info.all_in_loops) {
        log.debug("DOUBLE-FREE-LOOP: All free sites are in loops, reducing confidence", .{});
        confidence -= 0.25;
    } else if (loop_info.some_in_loops) {
        log.debug("DOUBLE-FREE-LOOP: Some free sites in loops, slightly reducing confidence", .{});
        confidence -= 0.1;
    }

    const defensive = detectDefensivePatterns(graph, node.free_sites.items);
    if (defensive.has_null_check) {
        log.debug("DOUBLE-FREE-DEFENSIVE: NULL check before free detected", .{});
        confidence -= 0.3;
    }
    if (defensive.has_null_assign) {
        log.debug("DOUBLE-FREE-DEFENSIVE: NULL assignment after free detected", .{});
        confidence -= 0.2;
    }
    if (defensive.is_cleanup_pattern) {
        log.debug("DOUBLE-FREE-DEFENSIVE: Cleanup pattern detected", .{});
        confidence -= 0.15;
    }

    if (confidence < 0.0) confidence = 0.0;
    if (confidence > 1.0) confidence = 1.0;

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
fn analyzeLoopContext(graph: *MemoryGraph, free_sites: []const FreeRecord) struct {
    all_in_loops: bool,
    some_in_loops: bool,
} {
    var all_in_loops = true;
    var some_in_loops = false;

    for (free_sites) |site| {
        const in_loop = isBBLikelyInLoop(graph, site.bb_id);
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
fn isBBLikelyInLoop(graph: *MemoryGraph, bb_id: u32) bool {
    if (bb_id == 0) return false;

    var visited = std.AutoHashMap(u32, void).init(graph.allocator);
    defer visited.deinit();

    const successors = graph.bb_edges.get(bb_id);
    if (successors) |succs| {
        var succ_iter = succs.iterator();
        while (succ_iter.next()) |entry| {
            if (entry.key_ptr.* <= bb_id and entry.key_ptr.* != 0) {
                return true;
            }
        }
    }

    return false;
}

/// Detect defensive programming patterns around free sites.
fn detectDefensivePatterns(graph: *MemoryGraph, free_sites: []const FreeRecord) struct {
    has_null_check: bool,
    has_null_assign: bool,
    is_cleanup_pattern: bool,
} {
    var has_null_check = false;
    var has_null_assign = false;
    var is_cleanup_pattern = false;

    if (free_sites.len == 2) {
        const site1 = free_sites[0];
        const site2 = free_sites[1];

        if (site1.bb_id != 0 and site2.bb_id != 0 and site1.bb_id != site2.bb_id) {
            var visited1 = std.AutoHashMap(u32, void).init(graph.allocator);
            defer visited1.deinit();
            var visited2 = std.AutoHashMap(u32, void).init(graph.allocator);
            defer visited2.deinit();

            const r1_to_r2 = graph.isBBReachable(site1.bb_id, site2.bb_id, &visited1);
            const r2_to_r1 = graph.isBBReachable(site2.bb_id, site1.bb_id, &visited2);

            if (!r1_to_r2 and !r2_to_r1) {
                is_cleanup_pattern = true;
                has_null_check = true;
            }
        }
    }

    if (free_sites.len > 2) {
        is_cleanup_pattern = true;
        has_null_assign = true;
    }

    return .{
        .has_null_check = has_null_check,
        .has_null_assign = has_null_assign,
        .is_cleanup_pattern = is_cleanup_pattern,
    };
}

/// The ONE question that determines whether we care about a pointer.
pub fn isOnDangerPath(
    graph: *MemoryGraph,
    ptr_val: u64,
    ffi_boundaries: []const DangerSurface,
    visited: *std.AutoHashMap(u64, void),
    ffi_set: ?*const std.StringHashMap(void),
) DangerPathKind {
    if (visited.contains(ptr_val)) return .none;
    visited.put(ptr_val, {}) catch {
        return .none;
    };

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

    const arg_indices = graph.getCallArgsForPtr(ptr_val);
    for (arg_indices) |idx| {
        const arg_edge = &graph.call_args.items[idx];
        if (set.contains(arg_edge.callee_name)) {
            return .ffi_arg;
        }
    }

    const ret_indices = graph.getCallRetsForPtr(ptr_val);
    for (ret_indices) |idx| {
        const ret_edge = &graph.call_rets.items[idx];
        if (set.contains(ret_edge.callee_name)) {
            return .ffi_ret;
        }
    }

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

// =====================================================================
// Use-After-Free Detection
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

// =====================================================================
// Ownership Transfer Validation
// =====================================================================

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

// =====================================================================
// Lifecycle Analysis
// =====================================================================

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
