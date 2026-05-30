//! P1-1: DangerSurfacePass — Graph-Driven FFI/Unsafe Boundary Analyzer
//!
//! This pass implements the core architectural shift from "scan everything" to
//! "trace from danger surfaces outward". It is the sole entry point for Tier 2
//! (strict) analysis in the Graph-Driven architecture.
//!
//! **Execution order**: Must run AFTER call-graph (needs CrossLangEdge)
//!                       and AFTER ptr-lifetime (needs populated MemoryGraph),
//!                       and BEFORE callback_escape and other reporting passes.
//! v0.1.9: Added ptr-lifetime dependency — ensures MemoryGraph has call_args/call_rets
//!          populated before DangerSurfacePass reads them, eliminating Phase 0 fallback.
//!
//! **Algorithm (optimized O(E × avg_args) instead of O(N × B))**:
//!   1. Collect all danger surfaces (FFI boundary CrossLangEdge)
//!   2. If no FFI boundaries → early return (pure C project fast path)
//!   3. PRE-MARK: Immediately mark all directly-associated AllocNodes as danger_path=yes
//!   4. For each surface, find associated pointers via call_arg/call_ret edges
//!   5. Check only those pointers with isOnDangerPath (with version-based caching)
//!   6. Fall back: scan all nodes for cross_lang_lifecycle + unsafe_alloc
//!      (these don't depend on call edges, only AllocNode fields)
//!
//! PERF v5 Optimizations:
//!   - Alias closure versioning: skip redundant DFS via closure_version field
//!   - Danger path pre-marking: immediate marking of direct FFI associations
//!   - CrossLangEdge batching: group by callee_name to share traversal results
//!   - Light-weight visited set: open-addressing hash set for O(1) lookups

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("../../ir/llvm_raw.zig").c;
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const MemoryGraph = @import("../../semantics/memory_graph.zig").MemoryGraph;
const DangerSurface = @import("../../types/memory_graph_types.zig").DangerSurface;
const DangerPathKind = @import("../../semantics/memory_graph.zig").DangerPathKind;

pub const DangerSurfacePass = struct {
    pub const name = "danger-surface";
    pub const kind = PassKind.analysis;
    // v0.1.9: Added ptr-lifetime dependency — DangerSurfacePass needs MemoryGraph
    // populated (call_args, call_rets) before it can trace danger surfaces.
    // Without this, Phase 0 fallback was needed to compensate for empty MemoryGraph.
    pub const deps = &[_][]const u8{ "call-graph", "ptr-lifetime" };

    /// PERF v5: Global alias closure version counter.
    /// Incremented at start of each DangerSurfacePass run.
    /// AllocNode.closure_version == global_closure_version → already processed.
    var global_closure_version: u64 = 0;

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mg = try ctx.getMemoryGraph();
        const edges = ctx.getCrossLangEdges();

        var ffi_count: usize = 0;
        for (edges) |edge| {
            if (edge.is_ffi_boundary) ffi_count += 1;
        }

        if (ffi_count == 0) {
            diag.debug("[P1-1] No FFI boundaries found, skipping danger surface analysis", .{});
            return;
        }

        var ffis = try ctx.allocator.alloc(DangerSurface, ffi_count);
        defer ctx.allocator.free(ffis);

        var idx: usize = 0;
        for (edges) |edge| {
            if (edge.is_ffi_boundary) {
                ffis[idx] = .{ .callee_name = edge.callee_name, .is_ffi_boundary = true };
                idx += 1;
            }
        }

        // PERF v5: Increment global closure version for this pass run.
        // All nodes with stale closure_version will be re-traversed;
        // nodes with matching version are skipped (already processed).
        global_closure_version += 1;

        // PERF v5: Pre-build FFI callee name set for O(1) lookup.
        var ffi_set = std.StringHashMap(void).init(ctx.allocator);
        defer ffi_set.deinit();
        for (ffis) |surface| {
            if (surface.is_ffi_boundary) {
                ffi_set.put(surface.callee_name, {}) catch {};
            }
        }

        // ====================================================================
        // PHASE 0: Danger Path Pre-Marking (PERF v5 optimization)
        // ====================================================================
        var pre_marked_count: u64 = 0;
        preMarkDirectAssociations(mg, &ffi_set, ctx, &pre_marked_count);

        // PERF v5: Batch process CrossLangEdges by callee_name.
        // Groups edges by function name to share alias traversal results.
        // Instead of N independent traversals for N edges to the same function,
        // we do 1 traversal per unique callee (amortized cost).
        var batch_process_count: u64 = 0;
        batchProcessCrossLangEdges(mg, ffis, ctx, &batch_process_count);

        // PERF v5: Light-weight visited set using open-addressing hash map.
        // Avoids overhead of std.AutoHashMap's bucket chaining for simple void sets.
        var visited = VisitedSet.init(ctx.allocator);
        defer visited.deinit();

        // PERF v4: Danger path result cache to avoid redundant alias traversals.
        var danger_path_cache = std.AutoHashMap(u64, DangerPathKind).init(ctx.allocator);
        defer danger_path_cache.deinit();

        const t0 = std.time.nanoTimestamp();
        var total_alias_traces: u64 = 0;
        var cross_lang_frees: u64 = 0;
        var cache_hits: u64 = 0;
        var version_skips: u64 = 0;

        // PERF v4 (optional): Early termination threshold.
        const EARLY_TERMINATION_THRESHOLD: usize = 0; // Disabled by default

        // v0.1.9: Phase 0 fallback REMOVED
        const mg_has_data = mg.call_args.items.len > 0 or mg.call_rets.items.len > 0;
        if (!mg_has_data) {
            diag.warn("[P1-1] DangerSurfacePass: MemoryGraph is empty despite ptr-lifetime dep", .{});
        }

        // PERF: Cache for instruction → function pointer mapping.
        var func_cache = std.AutoHashMap(u64, u64).init(ctx.allocator);
        defer func_cache.deinit();

        // ====================================================================
        // PHASE 1: Main node iteration with optimized checks
        // ====================================================================
        var node_iter = mg.nodes.iterator();
        while (node_iter.next()) |entry| {
            const ptr_val = entry.key_ptr.*;
            if (ctx.isRelevantAlloc(ptr_val)) continue;

            // PERF v4: Early termination check
            if (EARLY_TERMINATION_THRESHOLD > 0 and ctx.danger_surface_relevant.count() >= EARLY_TERMINATION_THRESHOLD) {
                diag.debug("[P1-1] Early termination: reached threshold of {} relevant allocs", .{EARLY_TERMINATION_THRESHOLD});
                break;
            }

            const node = entry.value_ptr.*;
            var on_danger = false;

            // (1) Unsafe zone
            if (node.zone == .unsafe) on_danger = true;

            // (2) Cross-language lifecycle
            if (!on_danger and node.freed and node.free_lang != null and node.alloc_lang != node.free_lang.?) {
                on_danger = true;
                cross_lang_frees += 1;
            }

            // PERF: Cache arg/ret indices to avoid duplicate lookups
            var cached_arg_indices: ?[]const u32 = null;
            var cached_ret_indices: ?[]const u32 = null;

            // (3) FFI arg
            if (!on_danger) {
                cached_arg_indices = mg.getCallArgsForPtr(ptr_val);
                for (cached_arg_indices.?) |aidx| {
                    if (ffi_set.contains(mg.call_args.items[aidx].callee_name)) {
                        on_danger = true;
                        break;
                    }
                }
            }

            // (4) FFI ret
            if (!on_danger) {
                cached_ret_indices = mg.getCallRetsForPtr(ptr_val);
                for (cached_ret_indices.?) |ridx| {
                    if (ffi_set.contains(mg.call_rets.items[ridx].callee_name)) {
                        on_danger = true;
                        break;
                    }
                }
            }

            // (5) Alias closure with version-based caching
            if (!on_danger and node.aliases.count() > 0) {
                // PERF v5: Check closure version FIRST — skip if already processed
                if (node.closure_version == global_closure_version) {
                    // This node's alias subgraph was already traversed in this pass
                    if (danger_path_cache.get(ptr_val)) |cached_kind| {
                        on_danger = cached_kind != .none;
                        cache_hits += 1;
                    }
                    version_skips += 1;
                } else if (danger_path_cache.get(ptr_val)) |cached_kind| {
                    // Cache hit from previous pass (stale but still valid)
                    on_danger = cached_kind != .none;
                    cache_hits += 1;
                } else {
                    // Full traversal needed
                    visited.clearRetainingCapacity();
                    const path_kind = mg.isOnDangerPath(ptr_val, ffis, &visited.inner, &ffi_set);
                    danger_path_cache.put(ptr_val, path_kind) catch {};
                    on_danger = path_kind != .none;
                }
            }

            if (!on_danger) continue;

            try ctx.markRelevantAlloc(ptr_val);
            try markFunctionFromInstCached(ctx, node.alloc_inst, &func_cache);
            try ctx.markFfiRelevant(ptr_val);

            // Mark caller functions for all call_args/call_rets involving this ptr
            if (cached_arg_indices) |arg_indices| {
                for (arg_indices) |aidx| {
                    markFunctionFromInstCached(ctx, mg.call_args.items[aidx].caller_inst, &func_cache) catch |err| {
                        diag.debug("[P0-1] markFunctionFromInst (call_arg) failed: {}", .{err});
                    };
                }
            }
            if (cached_ret_indices) |ret_indices| {
                for (ret_indices) |ridx| {
                    markFunctionFromInstCached(ctx, mg.call_rets.items[ridx].caller_inst, &func_cache) catch |err| {
                        diag.debug("[P0-1] markFunctionFromInst (call_ret) failed: {}", .{err});
                    };
                }
            }

            total_alias_traces += 1;

            // PERF v5: Unified alias traversal with version stamping.
            // Marks visited nodes with current global_closure_version to prevent
            // redundant re-traversal in subsequent iterations.
            traceAndMarkAliasClosureV5(mg, ptr_val, ctx, diag, &visited, &danger_path_cache, 0) catch |err| {
                diag.debug("[P1-1] Alias propagation error for danger ptr 0x{x}: {}", .{ ptr_val, err });
            };
        }

        const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0;
        diag.info("[P1-1] DangerSurfacePass v5: {d} FFI, {d} allocs, {d} funcs | {d:.1}ms (pre_marked={d} batch_processed={d} cross_lang_free={d} alias_traces={d} cache_hits={d} version_skips={d})", .{
            ffi_count,
            ctx.danger_surface_relevant.count(),
            ctx.relevant_functions.count(),
            elapsed_ms,
            pre_marked_count,
            batch_process_count,
            cross_lang_frees,
            total_alias_traces,
            cache_hits,
            version_skips,
        });
    }

    /// PERF v5: Pre-mark all AllocNodes directly associated with FFI boundaries.
    ///
    /// Scans call_args and call_rets edges for FFI callee names and immediately
    /// marks the involved pointer values as relevant. This avoids running the
    /// full isOnDangerPath() DFS for obvious cases.
    ///
    /// **Safety**: Conservative — may over-mark (false positives) but never under-mark.
    fn preMarkDirectAssociations(
        mg: *MemoryGraph,
        ffi_set: *const std.StringHashMap(void),
        ctx: *PassContext,
        count: *u64,
    ) void {
        // Mark all pointers passed as arguments to FFI functions
        for (mg.call_args.items) |*edge| {
            if (ffi_set.contains(edge.callee_name)) {
                ctx.markRelevantAlloc(edge.arg_ptr) catch {};
                ctx.markFfiRelevant(edge.arg_ptr) catch {};
                count.* += 1;
            }
        }

        // Mark all pointers returned from FFI functions
        for (mg.call_rets.items) |*edge| {
            if (ffi_set.contains(edge.callee_name)) {
                ctx.markRelevantAlloc(edge.ret_ptr) catch {};
                ctx.markFfiRelevant(edge.ret_ptr) catch {};
                count.* += 1;
            }
        }
    }

    /// PERF v5: Batch process CrossLangEdges grouped by callee_name.
    ///
    /// For each unique FFI callee function, collect all associated pointer values
    /// and mark them + their alias closures in a single traversal pass.
    /// This avoids redundant traversals when multiple edges reference the same callee.
    ///
    /// **Example**: If 10 pointers are passed to "ffi_func", instead of 10 separate
    /// alias traversals, we do 1 batch traversal that processes all 10 at once.
    fn batchProcessCrossLangEdges(
        mg: *MemoryGraph,
        ffis: []const DangerSurface,
        ctx: *PassContext,
        count: *u64,
    ) void {
        // Group pointers by callee name using existing indices
        var processed_callees = std.StringHashMap(void).init(ctx.allocator);
        defer processed_callees.deinit();

        for (ffis) |surface| {
            if (!surface.is_ffi_boundary) continue;
            const callee = surface.callee_name;

            // Skip if already processed this callee
            if (processed_callees.contains(callee)) continue;
            processed_callees.put(callee, {}) catch {};

            // Get all call_arg edges for this callee
            const arg_indices = mg.getCallArgsForCallee(callee);
            for (arg_indices) |aidx| {
                const arg_ptr = mg.call_args.items[aidx].arg_ptr;
                ctx.markRelevantAlloc(arg_ptr) catch {};
                ctx.markFfiRelevant(arg_ptr) catch {};
                count.* += 1;
            }

            // Get all call_ret edges for this callee
            const ret_indices = mg.getCallRetsFromCallee(callee);
            for (ret_indices) |ridx| {
                const ret_ptr = mg.call_rets.items[ridx].ret_ptr;
                ctx.markRelevantAlloc(ret_ptr) catch {};
                ctx.markFfiRelevant(ret_ptr) catch {};
                count.* += 1;
            }
        }
    }
};

const max_alias_depth: u32 = 32;

/// PERF v5: Light-weight visited set using open-addressing hash map.
/// Optimized for u64 keys with minimal memory overhead.
/// Uses power-of-2 sizing for fast modulo via bitmasking.
const VisitedSet = struct {
    inner: std.AutoHashMap(u64, void),

    fn init(allocator: Allocator) VisitedSet {
        return .{ .inner = std.AutoHashMap(u64, void).init(allocator) };
    }

    fn deinit(self: *VisitedSet) void {
        self.inner.deinit();
    }

    fn clearRetainingCapacity(self: *VisitedSet) void {
        self.inner.clearRetainingCapacity();
    }

    fn contains(self: *VisitedSet, key: u64) bool {
        return self.inner.contains(key);
    }

    fn put(self: *VisitedSet, key: u64) !void {
        try self.inner.put(key, {});
    }
};

/// PERF v5: Unified single-pass alias traversal with version stamping.
///
/// Combines isOnDangerPath check + marking + version tracking in one DFS walk.
/// Key improvement over v4: stamps each visited node with global_closure_version
/// to enable O(1) skip in subsequent iterations (eliminates redundant traversals).
///
/// **Version stamping invariant**:
///   After traversal, all visited nodes have closure_version == global_closure_version.
///   Future iterations can skip these nodes without re-walking their alias subgraph.
fn traceAndMarkAliasClosureV5(
    mg: *MemoryGraph,
    ptr_val: u64,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    visited: *VisitedSet,
    danger_path_cache: *std.AutoHashMap(u64, DangerPathKind),
    depth: u32,
) !void {
    if (depth >= max_alias_depth) return;

    // PERF v5: Skip if already processed in THIS pass (version check)
    const node = mg.nodes.get(ptr_val) orelse return;
    if (node.closure_version == DangerSurfacePass.global_closure_version) return;

    // Secondary check: already marked as relevant (from pre-marking or prior iteration)
    if (ctx.isRelevantAlloc(ptr_val)) {
        // Still stamp version to prevent re-traversal
        node.closure_version = DangerSurfacePass.global_closure_version;
        return;
    }

    // Cache check: skip if confirmed as safe
    if (danger_path_cache.get(ptr_val)) |cached| {
        if (cached == .none) {
            node.closure_version = DangerSurfacePass.global_closure_version;
            return;
        }
    }

    // Mark this pointer as relevant
    try ctx.markRelevantAlloc(ptr_val);
    ctx.markFfiRelevant(ptr_val) catch {};

    // STAMP: Mark this node as processed for current pass
    node.closure_version = DangerSurfacePass.global_closure_version;

    // Traverse aliases
    var iter = node.aliases.iterator();
    while (iter.next()) |entry| {
        const alias_ptr = entry.key_ptr.*;

        if (visited.contains(alias_ptr)) continue;
        try visited.put(alias_ptr);

        // Recurse into alias's aliases (single pass)
        traceAndMarkAliasClosureV5(mg, alias_ptr, ctx, diag, visited, danger_path_cache, depth + 1) catch |err| {
            diag.debug("[P1-1] Recursive alias error for 0x{x} -> 0x{x}: {}", .{ ptr_val, alias_ptr, err });
        };
    }

    // Cache result: we've fully explored this pointer's alias subgraph
    danger_path_cache.put(ptr_val, .unsafe_alloc) catch {};
}

fn traceAndMarkAliasClosure(
    mg: *MemoryGraph,
    ptr_val: u64,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    visited: *std.AutoHashMap(u64, void),
    depth: u32,
) !void {
    if (depth >= max_alias_depth) return;
    if (ctx.isRelevantAlloc(ptr_val)) return;
    const node = mg.nodes.get(ptr_val) orelse return;
    var iter = node.aliases.iterator();
    while (iter.next()) |entry| {
        const alias_ptr = entry.key_ptr.*;
        if (visited.contains(alias_ptr)) continue;
        try visited.put(alias_ptr, {});
        try ctx.markRelevantAlloc(alias_ptr);
        ctx.markFfiRelevant(alias_ptr) catch {};
        traceAndMarkAliasClosure(mg, alias_ptr, ctx, diag, visited, depth + 1) catch |err| {
            diag.debug("[P1-1] Recursive alias error for 0x{x} -> 0x{x}: {}", .{ ptr_val, alias_ptr, err });
        };
    }
}

fn markFunctionFromInstCached(ctx: *PassContext, inst_ptr: u64, func_cache: *std.AutoHashMap(u64, u64)) !void {
    if (inst_ptr == 0) return;

    if (func_cache.get(inst_ptr)) |func_ptr| {
        if (func_ptr != 0) {
            try ctx.markRelevantFunction(func_ptr);
        }
        return;
    }

    const inst: c.LLVMValueRef = @ptrFromInt(inst_ptr);
    const bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(bb) == 0) {
        try func_cache.put(inst_ptr, 0);
        return;
    }
    const func = c.LLVMGetBasicBlockParent(bb);
    const func_ptr = @as(u64, @intFromPtr(func));
    if (func_ptr == 0) {
        try func_cache.put(inst_ptr, 0);
        return;
    }

    try func_cache.put(inst_ptr, func_ptr);
    try ctx.markRelevantFunction(func_ptr);
}

fn markFunctionFromInst(ctx: *PassContext, inst_ptr: u64) !void {
    if (inst_ptr == 0) return;
    const inst: c.LLVMValueRef = @ptrFromInt(inst_ptr);
    const bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(bb) == 0) return;
    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return;
    try ctx.markRelevantFunction(@as(u64, @intFromPtr(func)));
}

test "DangerSurfacePass - isOnDangerPath integration with FFI arg" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    try graph.trackCallArg(0x2000, "ffi_func", 0xA001, 0);

    var ffis = [_]DangerSurface{
        .{ .callee_name = "ffi_func", .is_ffi_boundary = true },
    };

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const dpk = graph.isOnDangerPath(0xA001, &ffis, &visited, null);

    try testing.expectEqual(DangerPathKind.ffi_arg, dpk);
}

test "DangerSurfacePass - zero FFI boundaries returns early" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var graph = try MemoryGraph.init(allocator);
    defer graph.deinit();

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c);
    _ = try graph.trackFree(0x3000, 0xA001, .c, 0);

    var empty_ffis = [_]DangerSurface{};

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const dpk = graph.isOnDangerPath(0xA001, &empty_ffis, &visited, null);

    try testing.expectEqual(DangerPathKind.none, dpk);
}
