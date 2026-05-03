//! P1-1: DangerSurfacePass — Graph-Driven FFI/Unsafe Boundary Analyzer
//!
//! This pass implements the core architectural shift from "scan everything" to
//! "trace from danger surfaces outward". It is the sole entry point for Tier 2
//! (strict) analysis in the Graph-Driven architecture.
//!
//! **Execution order**: Must run AFTER call-graph (needs CrossLangEdge)
//!                       and BEFORE all reporting passes (ptr_lifetime, etc.)
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
const DangerSurface = MemoryGraph.DangerSurface;

pub const DangerSurfacePass = struct {
    pub const name = "danger-surface";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"call-graph"};

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

        var visited = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer visited.deinit();

        for (ffis) |surface| {
            const arg_indices = mg.getCallArgsForCallee(surface.callee_name);
            for (arg_indices) |arg_idx| {
                const arg_ptr_val = mg.call_args.items[arg_idx].arg_ptr;
                visited.clearRetainingCapacity();
                const dpk = mg.isOnDangerPath(arg_ptr_val, ffis, &visited);
                if (dpk != .none) {
                    try ctx.markRelevantAlloc(arg_ptr_val);
                    traceAliasClosure(mg, arg_ptr_val, ctx, diag, &visited) catch |err| {
                        diag.debug("[P1-1] Alias propagation error for ptr 0x{x}: {}", .{ arg_ptr_val, err });
                    };
                }
            }

            const ret_indices = mg.getCallRetsFromCallee(surface.callee_name);
            for (ret_indices) |ret_idx| {
                const ret_ptr_val = mg.call_rets.items[ret_idx].ret_ptr;
                visited.clearRetainingCapacity();
                const dpk = mg.isOnDangerPath(ret_ptr_val, ffis, &visited);
                if (dpk != .none) {
                    try ctx.markRelevantAlloc(ret_ptr_val);
                    traceAliasClosure(mg, ret_ptr_val, ctx, diag, &visited) catch |err| {
                        diag.debug("[P1-1] Alias propagation error for ptr 0x{x}: {}", .{ ret_ptr_val, err });
                    };
                }
            }
        }

        var node_iter = mg.nodes.iterator();
        while (node_iter.next()) |entry| {
            const ptr_val = entry.key_ptr.*;
            if (ctx.isRelevantAlloc(ptr_val)) continue;
            const node = entry.value_ptr.*;
            if (node.zone == .unsafe) {
                try ctx.markRelevantAlloc(ptr_val);
                traceAliasClosure(mg, ptr_val, ctx, diag, &visited) catch |err| {
                    diag.debug("[P1-1] Alias propagation error for unsafe ptr 0x{x}: {}", .{ ptr_val, err });
                };
            } else if (node.freed) {
                const fl = node.free_lang orelse continue;
                if (node.alloc_lang != fl) {
                    try ctx.markRelevantAlloc(ptr_val);
                    traceAliasClosure(mg, ptr_val, ctx, diag, &visited) catch |err| {
                        diag.debug("[P1-1] Alias propagation error for cross-lang ptr 0x{x}: {}", .{ ptr_val, err });
                    };
                }
            }
        }

        diag.info("[P1-1] DangerSurfacePass: {d} FFI boundaries, {d} relevant allocs marked", .{
            ffi_count,
            ctx.danger_surface_relevant.count(),
        });
    }
};

fn traceAliasClosure(
    mg: *MemoryGraph,
    ptr_val: u64,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    visited: *std.AutoHashMap(u64, void),
) !void {
    const node = mg.nodes.get(ptr_val) orelse return;
    var iter = node.aliases.iterator();
    while (iter.next()) |entry| {
        const alias_ptr = entry.key_ptr.*;
        if (visited.contains(alias_ptr)) continue;
        try visited.put(alias_ptr, {});
        try ctx.markRelevantAlloc(alias_ptr);
        traceAliasClosure(mg, alias_ptr, ctx, diag, visited) catch |err| {
            diag.debug("[P1-1] Recursive alias error for 0x{x} -> 0x{x}: {}", .{ ptr_val, alias_ptr, err });
        };
    }
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
    const dpk = graph.isOnDangerPath(0xA001, &ffis, &visited);

    try testing.expectEqual(MemoryGraph.DangerPathKind.ffi_arg, dpk);
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
    _ = try graph.trackFree(0x3000, 0xA001, .c);

    var empty_ffis = [_]DangerSurface{};

    var visited = std.AutoHashMap(u64, void).init(allocator);
    defer visited.deinit();
    const dpk = graph.isOnDangerPath(0xA001, &empty_ffis, &visited);

    try testing.expectEqual(MemoryGraph.DangerPathKind.none, dpk);
}
