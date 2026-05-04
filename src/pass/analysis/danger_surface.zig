//! P1-1: DangerSurfacePass — Graph-Driven FFI/Unsafe Boundary Analyzer
//!
//! This pass implements the core architectural shift from "scan everything" to
//! "trace from danger surfaces outward". It is the sole entry point for Tier 2
//! (strict) analysis in the Graph-Driven architecture.
//!
//! **Execution order**: Must run AFTER ptr_lifetime (needs populated MemoryGraph)
//!                       and AFTER call-graph (needs CrossLangEdge)
//!                       and BEFORE callback_escape and other reporting passes
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
const c = @import("../../ir/llvm_raw.zig").c;
const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const PassKind = @import("../pass.zig").PassKind;
const MemoryGraph = @import("../../semantics/memory_graph.zig").MemoryGraph;
const DangerSurface = MemoryGraph.DangerSurface;

pub const DangerSurfacePass = struct {
    pub const name = "danger-surface";
    pub const kind = PassKind.analysis;
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

        var visited = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer visited.deinit();

        const t0 = std.time.nanoTimestamp();
        var total_args: u64 = 0;
        var total_rets: u64 = 0;
        var total_alias_traces: u64 = 0;

        for (ffis) |surface| {
            // Phase 1 args: callee is already a known FFI boundary →
            // isOnDangerPath would always return .ffi_arg. Skip the expensive call.
            const arg_indices = mg.getCallArgsForCallee(surface.callee_name);
            for (arg_indices) |arg_idx| {
                total_args += 1;
                const arg_ptr_val = mg.call_args.items[arg_idx].arg_ptr;
                try ctx.markRelevantAlloc(arg_ptr_val);
                ctx.markFunctionFromInst(mg.call_args.items[arg_idx].caller_inst);
                visited.clearRetainingCapacity();
                total_alias_traces += 1;
                traceAliasClosure(mg, arg_ptr_val, ctx, diag, &visited) catch |err| {
                    diag.debug("[P1-1] Alias propagation error for ptr 0x{x}: {}", .{ arg_ptr_val, err });
                };
            }

            // Phase 1 rets: callee is already a known FFI boundary →
            // isOnDangerPath would always return .ffi_ret. Skip the expensive call.
            const ret_indices = mg.getCallRetsFromCallee(surface.callee_name);
            for (ret_indices) |ret_idx| {
                total_rets += 1;
                const ret_ptr_val = mg.call_rets.items[ret_idx].ret_ptr;
                try ctx.markRelevantAlloc(ret_ptr_val);
                ctx.markFunctionFromInst(mg.call_rets.items[ret_idx].caller_inst);
                visited.clearRetainingCapacity();
                total_alias_traces += 1;
                traceAliasClosure(mg, ret_ptr_val, ctx, diag, &visited) catch |err| {
                    diag.debug("[P1-1] Alias propagation error for ptr 0x{x}: {}", .{ ret_ptr_val, err });
                };
            }
        }

        const t1 = std.time.nanoTimestamp();

        var node_iter = mg.nodes.iterator();
        while (node_iter.next()) |entry| {
            const ptr_val = entry.key_ptr.*;
            if (ctx.isRelevantAlloc(ptr_val)) continue;
            const node = entry.value_ptr.*;
            if (node.zone == .unsafe) {
                try ctx.markRelevantAlloc(ptr_val);
                try markFunctionFromInst(ctx, node.alloc_inst);
                traceAliasClosure(mg, ptr_val, ctx, diag, &visited) catch |err| {
                    diag.debug("[P1-1] Alias propagation error for unsafe ptr 0x{x}: {}", .{ ptr_val, err });
                };
            } else if (node.freed) {
                const fl = node.free_lang orelse continue;
                if (node.alloc_lang != fl) {
                    try ctx.markRelevantAlloc(ptr_val);
                    try markFunctionFromInst(ctx, node.alloc_inst);
                    traceAliasClosure(mg, ptr_val, ctx, diag, &visited) catch |err| {
                        diag.debug("[P1-1] Alias propagation error for cross-lang ptr 0x{x}: {}", .{ ptr_val, err });
                    };
                }
            }
        }

        diag.info("[P1-1] DangerSurfacePass: {d} FFI, {d} allocs, {d} funcs | Phase1={d:.0}ms (args={d} rets={d} alias_traces={d}) Phase2={d:.0}ms", .{
            ffi_count,
            ctx.danger_surface_relevant.count(),
            ctx.relevant_functions.count(),
            @as(u32, @intFromFloat(@as(f64, @floatFromInt(t1 - t0)) / 1_000_000.0)),
            total_args,
            total_rets,
            total_alias_traces,
            @as(u32, @intFromFloat(@as(f64, @floatFromInt(std.time.nanoTimestamp() - t1)) / 1_000_000.0)),
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
    if (ctx.isRelevantAlloc(ptr_val)) return;
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
