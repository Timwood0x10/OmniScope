//! P1-1: DangerSurfacePass — Graph-Driven FFI/Unsafe Boundary Analyzer
//!
//! This pass implements the core architectural shift from "scan everything" to
//! "trace from danger surfaces outward". It is the sole entry point for Tier 2
//! (strict) analysis in the Graph-Driven architecture.
//!
//! **Execution order**: Must run AFTER call-graph (needs CrossLangEdge)
//!                       and AFTER ptr-lifetime (needs populated MemoryGraph),
//!                       and BEFORE callback_escape and other reporting passes.
//! v0.2.0: Added ptr-lifetime dependency — ensures MemoryGraph has call_args/call_rets
//!          populated before DangerSurfacePass reads them, eliminating Phase 0 fallback.
//!
//! **Algorithm (optimized O(E × avg_args) instead of O(N × B))**:
//!   1. Collect all danger surfaces (FFI boundary CrossLangEdge)
//!   2. If no FFI boundaries → early return (pure C project fast path)
//!   3. For each surface, find associated pointers via call_arg/call_ret edges
//!   4. Check only those pointers with isOnDangerPath
//!   5. Fall back: scan all nodes for cross_lang_lifecycle + unsafe_alloc
//!      (these don't depend on call edges, only AllocNode fields)

const std = @import("std");
const Allocator = std.mem.Allocator;
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const MemoryGraph = @import("../../semantics/memory_graph.zig").MemoryGraph;
const DangerSurface = @import("../../types/memory_graph_types.zig").DangerSurface;
const DangerPathKind = @import("../../semantics/memory_graph.zig").DangerPathKind;
const c = @import("../../ir/llvm_raw.zig").c;

pub const DangerSurfacePass = struct {
    pub const name = "danger-surface";
    pub const kind = PassKind.analysis;
    // v0.2.0: Added ptr-lifetime dependency — DangerSurfacePass needs MemoryGraph
    // populated (call_args, call_rets) before it can trace danger surfaces.
    // Without this, Phase 0 fallback was needed to compensate for empty MemoryGraph.
    pub const deps = &[_][]const u8{ "call-graph", "ptr-lifetime" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mg = &ctx.memory_graph;
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

        // visited set for alias closure — pre-allocated to node count.
        var visited = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer visited.deinit();
        try visited.ensureTotalCapacity(@as(u32, @intCast(@max(mg.nodes.count(), 16384))));

        const t0 = std.time.nanoTimestamp();
        var total_alias_traces: u64 = 0;
        var cross_lang_frees: u64 = 0;

        const mg_has_data = mg.call_args.items.len > 0 or mg.call_rets.items.len > 0;
        if (!mg_has_data) {
            diag.warn("[P1-1] DangerSurfacePass: MemoryGraph is empty despite ptr-lifetime dep — ptr-lifetime may have skipped this module", .{});
        }

        // OPTIMIZATION 2: Integer hash set for O(1) FFI boundary name lookup.
        // Avoids StringHashMap's eql string comparison on every contains().
        var ffi_set = std.StringHashMap(void).init(ctx.allocator);
        defer ffi_set.deinit();
        try ffi_set.ensureTotalCapacity(@as(u32, @intCast(ffi_count * 2)));
        var ffi_hash_set = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer ffi_hash_set.deinit();
        try ffi_hash_set.ensureTotalCapacity(@as(u32, @intCast(ffi_count * 2)));
        for (ffis) |surface| {
            if (surface.is_ffi_boundary) {
                ffi_set.put(surface.callee_name, {}) catch {};
                const hash = std.hash.Wyhash.hash(0, surface.callee_name);
                ffi_hash_set.put(hash, {}) catch {};
            }
        }

        // OPTIMIZATION 3: FAST PATH — pre-build set of functions that have FFI calls.
        var ffi_func_set = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer ffi_func_set.deinit();
        {
            for (mg.call_args.items) |arg_edge| {
                if (ffi_hash_set.contains(std.hash.Wyhash.hash(0, arg_edge.callee_name))) {
                    const inst = @as(c.LLVMValueRef, @ptrFromInt(arg_edge.caller_inst));
                    if (@intFromPtr(inst) == 0) continue;
                    const bb = c.LLVMGetInstructionParent(inst);
                    if (@intFromPtr(bb) == 0) continue;
                    const func = c.LLVMGetBasicBlockParent(bb);
                    if (@intFromPtr(func) == 0) continue;
                    ffi_func_set.put(@as(u64, @intFromPtr(func)), {}) catch {};
                }
            }
            for (mg.call_rets.items) |ret_edge| {
                if (ffi_hash_set.contains(std.hash.Wyhash.hash(0, ret_edge.callee_name))) {
                    const inst = @as(c.LLVMValueRef, @ptrFromInt(ret_edge.caller_inst));
                    if (@intFromPtr(inst) == 0) continue;
                    const bb = c.LLVMGetInstructionParent(inst);
                    if (@intFromPtr(bb) == 0) continue;
                    const func = c.LLVMGetBasicBlockParent(bb);
                    if (@intFromPtr(func) == 0) continue;
                    ffi_func_set.put(@as(u64, @intFromPtr(func)), {}) catch {};
                }
            }
        }

        // OPTIMIZATION 4: Danger path cache — avoid repeated isOnDangerPath for same ptr_val.
        var danger_cache = std.AutoHashMap(u64, DangerPathKind).init(ctx.allocator);
        defer danger_cache.deinit();
        try danger_cache.ensureTotalCapacity(4096);

        var node_iter = mg.nodes.iterator();
        while (node_iter.next()) |entry| {
            const ptr_val = entry.key_ptr.*;
            if (ctx.isRelevantAlloc(ptr_val)) continue;

            // Inline cheap checks first — most nodes fail here, avoiding expensive alias walk.
            const node = entry.value_ptr.*;
            var on_danger = false;

            // (1) Unsafe zone — always check (no FFI dependency)
            if (node.zone == .unsafe) on_danger = true;

            // (2) Cross-language lifecycle — always check (no FFI dependency)
            // Suppress intentional ownership transfers (Box::leak, into_raw,
            // ManuallyDrop, forget) where cross-lang free is legitimate.
            // Also check language override registry: if user explicitly classified
            // the allocator as the same language as the free site, suppress this detection.
            if (!on_danger and node.freed and node.free_lang != null and node.alloc_lang != node.free_lang.?) {
                if (!isIntentionalOwnershipTransfer(node.alloc_callee)) {
                    // Defensive check: registry may have overridden the alloc language
                    // to match the free language, making this cross-lang detection a FP.
                    var registry_suppressed = false;
                    if (ctx.language_overrides) |reg| {
                        const alloc_lang = reg.lookup(node.alloc_callee orelse "") orelse reg.getDefault();
                        if (alloc_lang) |overridden| {
                            if (overridden == node.free_lang.?) {
                                registry_suppressed = true;
                            }
                        }
                    }
                    if (!registry_suppressed) {
                        on_danger = true;
                        cross_lang_frees += 1;
                    }
                }
            }

            // FAST PATH: if (1)(2) didn't trigger, check if alloc's function has FFI calls.
            // If not, skip expensive FFI arg/ret + alias walk entirely.
            if (!on_danger and ffi_func_set.count() > 0) {
                const alloc_inst = @as(c.LLVMValueRef, @ptrFromInt(node.alloc_inst));
                if (@intFromPtr(alloc_inst) != 0) {
                    const bb = c.LLVMGetInstructionParent(alloc_inst);
                    if (@intFromPtr(bb) != 0) {
                        const func = c.LLVMGetBasicBlockParent(bb);
                        if (@intFromPtr(func) != 0) {
                            if (!ffi_func_set.contains(@as(u64, @intFromPtr(func)))) {
                                continue;
                            }
                        }
                    }
                }
            }

            var cached_arg_indices: []const u32 = &.{};
            var cached_ret_indices: []const u32 = &.{};

            // (3) FFI arg — use integer hash set for O(1) lookup
            if (!on_danger) {
                cached_arg_indices = mg.getCallArgsForPtr(ptr_val);
                for (cached_arg_indices) |aidx| {
                    if (ffi_hash_set.contains(std.hash.Wyhash.hash(0, mg.call_args.items[aidx].callee_name))) {
                        on_danger = true;
                        break;
                    }
                }
            }

            // (4) FFI ret — use integer hash set for O(1) lookup
            if (!on_danger) {
                cached_ret_indices = mg.getCallRetsForPtr(ptr_val);
                for (cached_ret_indices) |ridx| {
                    if (ffi_hash_set.contains(std.hash.Wyhash.hash(0, mg.call_rets.items[ridx].callee_name))) {
                        on_danger = true;
                        break;
                    }
                }
            }

            // (5) Alias closure with danger path cache
            if (!on_danger and node.aliases.count() > 0) {
                const cached_kind = danger_cache.get(ptr_val);
                const path_kind = if (cached_kind) |k|
                    k
                else blk: {
                    visited.clearRetainingCapacity();
                    const k = mg.isOnDangerPath(ptr_val, ffis, &visited, &ffi_set);
                    danger_cache.put(ptr_val, k) catch {};
                    break :blk k;
                };
                on_danger = path_kind != .none;
            }

            if (!on_danger) continue;

            try ctx.markRelevantAlloc(ptr_val);
            try ctx.markFunctionFromInst(node.alloc_inst);
            try ctx.markFfiRelevant(ptr_val);

            // Mark caller functions for all call_args/call_rets involving this ptr.
            // Reuses cached indices from checks (3)/(4) above — no redundant HashMap lookups.
            for (cached_arg_indices) |aidx| {
                ctx.markFunctionFromInst(mg.call_args.items[aidx].caller_inst) catch |err| {
                    diag.debug("[P0-1] markFunctionFromInst (call_arg) failed: {}", .{err});
                };
            }
            for (cached_ret_indices) |ridx| {
                ctx.markFunctionFromInst(mg.call_rets.items[ridx].caller_inst) catch |err| {
                    diag.debug("[P0-1] markFunctionFromInst (call_ret) failed: {}", .{err});
                };
            }

            total_alias_traces += 1;
            traceAliasClosure(mg, ptr_val, ctx, diag, &visited, 0) catch |err| {
                diag.debug("[P1-1] Alias propagation error for danger ptr 0x{x}: {}", .{ ptr_val, err });
            };
        }

        diag.info("[P1-1] DangerSurfacePass: {d} FFI, {d} allocs, {d} funcs | {d:.0}ms (cross_lang_free={d} alias_traces={d} ffi_funcs={d} cache={d})", .{
            ffi_count,
            ctx.danger_surface_relevant.count(),
            ctx.relevant_functions.count(),
            @as(u32, @intFromFloat(@as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1_000_000.0)),
            cross_lang_frees,
            total_alias_traces,
            ffi_func_set.count(),
            danger_cache.count(),
        });
    }
};

const max_alias_depth: u32 = 32;

fn traceAliasClosure(
    mg: *MemoryGraph,
    ptr_val: u64,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    visited: *std.AutoHashMap(u64, void),
    depth: u32,
) !void {
    if (depth >= max_alias_depth) return;
    // PERF: isRelevantAlloc serves as a secondary visited check.
    // If a pointer was already marked relevant by a prior trace,
    // all its aliases have already been visited too. Skip entirely.
    if (ctx.isRelevantAlloc(ptr_val)) return;
    const node = mg.nodes.get(ptr_val) orelse return;
    var iter = node.aliases.iterator();
    while (iter.next()) |entry| {
        const alias_ptr = entry.key_ptr.*;
        if (visited.contains(alias_ptr)) continue;
        try visited.put(alias_ptr, {});
        try ctx.markRelevantAlloc(alias_ptr);
        ctx.markFfiRelevant(alias_ptr) catch {};
        traceAliasClosure(mg, alias_ptr, ctx, diag, visited, depth + 1) catch |err| {
            diag.debug("[P1-1] Recursive alias error for 0x{x} -> 0x{x}: {}", .{ ptr_val, alias_ptr, err });
        };
    }
}

/// Check if an allocation's callee indicates intentional ownership transfer
/// (not a leak or cross-language free bug).
///
/// Covers patterns like Box::leak(), Box::into_raw(), ManuallyDrop,
/// std::mem::forget, and functions with explicit transfer semantics
/// (leak/donate/transfer/export/handoff). When these patterns are detected,
/// the cross-language free is legitimate — ownership was deliberately
/// transferred to another language's deallocator.
///
/// This mirrors the logic in cross_lang_dataflow.isIntentionalOwnershipTransfer
/// but operates on AllocNode.alloc_callee (a single field) rather than
/// CrossLangAlloc (which has both alloc_callee and alloc_func).
fn isIntentionalOwnershipTransfer(alloc_callee: ?[]const u8) bool {
    const callee = alloc_callee orelse return false;

    // Known intentional transfer callee names (mangled Rust symbols)
    const intentional_patterns = [_][]const u8{
        "leak", // Box::leak
        "into_raw", // Box::into_raw, CString::into_raw, Vec::into_raw
        "ManuallyDrop", // ManuallyDrop::new
        "forget", // std::mem::forget
    };
    for (intentional_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee, pattern) != null) {
            return true;
        }
    }

    return false;
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

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c, null);
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

    _ = try graph.trackAlloc(0x1000, 0xA001, .heap_alloc, .safe, .c, null);
    _ = try graph.trackFree(0x3000, 0xA001, .c, 0);

    var empty_ffis = [_]DangerSurface{};

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const dpk = graph.isOnDangerPath(0xA001, &empty_ffis, &visited, null);

    try testing.expectEqual(DangerPathKind.none, dpk);
}

test "isIntentionalOwnershipTransfer - detects Box::leak pattern" {
    const t = std.testing;
    try t.expect(isIntentionalOwnershipTransfer("_ZN5alloc5boxed19Box$LT$T$GT$4leak17h") == true);
    try t.expect(isIntentionalOwnershipTransfer("_R...leak...") == true);
}

test "isIntentionalOwnershipTransfer - detects into_raw pattern" {
    const t = std.testing;
    try t.expect(isIntentionalOwnershipTransfer("_ZN5alloc5boxed19Box$LT$T$GT$9into_raw17h") == true);
}

test "isIntentionalOwnershipTransfer - detects forget and ManuallyDrop" {
    const t = std.testing;
    try t.expect(isIntentionalOwnershipTransfer("_ZN4core3mem5forget17h") == true);
    try t.expect(isIntentionalOwnershipTransfer("_ZN8core6mem13ManuallyDrop") == true);
}

test "isIntentionalOwnershipTransfer - rejects normal allocators" {
    const t = std.testing;
    try t.expect(isIntentionalOwnershipTransfer("__rust_alloc") == false);
    try t.expect(isIntentionalOwnershipTransfer("malloc") == false);
    try t.expect(isIntentionalOwnershipTransfer("free") == false);
}

test "isIntentionalOwnershipTransfer - null callee returns false" {
    const t = std.testing;
    try t.expect(isIntentionalOwnershipTransfer(null) == false);
}
