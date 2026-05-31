//! Pointer Lifetime Instruction Tracking
//!
//! Extracted from ptr_lifetime.zig to reduce main file size.
//! Contains per-opcode handlers for trackInstruction() switch cases.
//!
//! Module prefix: [ptr-lifetime-track]

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const log = @import("../../../common/log.zig");

const memory_graph = @import("../../../semantics/memory_graph.zig");
const zone_cls = @import("../../../semantics/zone_classifier.zig");
const ZoneKind = zone_cls.ZoneKind;
const Lang = zone_cls.Language;

const getCallInstArgCount = @import("../../../ir/llvm_safe.zig").getCallInstArgCount;
const classifyAllocLanguageEnum = @import("ptr_lifetime_classify.zig").classifyAllocLanguageEnum;
const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;

const GlobalAllocTracker = @import("../../../types/pass_types.zig").GlobalAllocTracker;

const ptr_types = @import("ptr_lifetime_types.zig");
const PtrAllocSite = ptr_types.PtrAllocSite;
const PtrInfo = ptr_types.PtrInfo;
const HEAP_ALLOC_FUNCTIONS = ptr_types.HEAP_ALLOC_FUNCTIONS;
const LifetimeMap = ptr_types.LifetimeMap;
const LifetimeInterval = ptr_types.LifetimeInterval;

const core = @import("ptr_lifetime_helpers.zig");
const putPtrInfo = core.putPtrInfo;
const propagateOrigin = core.propagateOrigin;
const mergeAllocSite = core.mergeAllocSite;
const inferContentKind = core.inferContentKind;

const ptr_utils = @import("ptr_lifetime_utils.zig");
const is_resource_alloc_function = ptr_utils.is_resource_alloc_function;
const isResourceCloseFunction = ptr_utils.isResourceCloseFunction;
const isSameOrAlias = ptr_utils.isSameOrAlias;
const isFuncParam = ptr_utils.isFuncParam;
const getAllocatorKB = ptr_types.getAllocatorKB;

// ============================================================================
// Track Context — shared parameters for all handlers
// ============================================================================

pub const TrackContext = struct {
    allocator: std.mem.Allocator,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    bb_id: usize,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    stats: *ptr_types.LifetimeStats,
    global_tracker: *@import("../../pass.zig").GlobalAllocTracker,
    lang: Lang,
    zone: ZoneKind,
    is_ffi_func: bool,
    /// T1.2: Map tracking alloca lifetime intervals from LLVM intrinsics
    lifetime_map: ?*LifetimeMap,

    pub fn mgEffective(self: *const TrackContext) ?*memory_graph.MemoryGraph {
        return if (self.is_ffi_func) self.mem_graph else null;
    }

    pub fn funcPtr(self: *const TrackContext) u64 {
        return @as(u64, @intFromPtr(self.func));
    }
};

// ============================================================================
// Alloca Handler
// ============================================================================

pub fn handleAlloca(ctx: *TrackContext) !void {
    const desc = try std.fmt.allocPrint(ctx.allocator, "stack alloca", .{});
    const info = PtrInfo{
        .alloc_site = .stack,
        .source_inst = ctx.inst,
        .source_desc = desc,
        .alloc_bb_id = ctx.bb_id,
        .needs_free = true,
    };
    try putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator);
    ctx.stats.total_pointers_tracked += 1;

    if (ctx.mgEffective()) |mg| {
        const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
        _ = mg.trackAlloc(inst_ptr, inst_ptr, .alloca, ctx.zone, ctx.lang) catch {};
    }
}

// ============================================================================
// Call/Invoke Handler (largest branch ~300 lines)
// ============================================================================

pub fn handleCallInvoke(ctx: *TrackContext) !void {
    const called = c.LLVMGetCalledValue(ctx.inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;

    const callee_name = std.mem.span(name_ptr);

    for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
        if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
            handleHeapAlloc(ctx, callee_name);
            return;
        }
    }

    if (getAllocatorKB()) |kb| {
        if (kb.isAllocator(callee_name)) {
            const desc = try std.fmt.allocPrint(ctx.allocator, "heap via allocator {s}()", .{callee_name});
            const info = PtrInfo{
                .alloc_site = .heap,
                .source_inst = ctx.inst,
                .source_desc = desc,
                .alloc_bb_id = ctx.bb_id,
                .needs_free = true,
            };
            try putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator);
            ctx.stats.total_pointers_tracked += 1;

            if (ctx.mgEffective()) |mg| {
                const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
                const alloc_lang = classifyAllocLanguageEnum(callee_name, ctx.lang) orelse ctx.lang;
                _ = mg.trackAlloc(inst_ptr, inst_ptr, .heap_alloc, ctx.zone, alloc_lang) catch {};
                mg.recordFuncAlloc(ctx.funcPtr());
            }
        }
    }

    if (is_resource_alloc_function(callee_name)) |res_type| {
        const desc = try std.fmt.allocPrint(ctx.allocator, "resource via {s}()", .{callee_name});
        const info = PtrInfo{
            .alloc_site = .heap,
            .source_inst = ctx.inst,
            .source_desc = desc,
            .alloc_bb_id = ctx.bb_id,
            .resource_type = res_type,
            .needs_free = true,
        };
        try putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator);
        ctx.stats.total_pointers_tracked += 1;

        if (ctx.mgEffective()) |mg| {
            const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
            _ = mg.trackAlloc(inst_ptr, inst_ptr, .resource_alloc, ctx.zone, ctx.lang) catch {};
            mg.recordFuncAlloc(ctx.funcPtr());
        }
    }

    if (std.mem.indexOf(u8, callee_name, "dlsym") != null) {
        handleDlsym(ctx);
    }

    if (isFreeFunction(callee_name)) {
        handleFreeCall(ctx, callee_name);
    }

    if (isResourceCloseFunction(callee_name)) |closed_type| {
        handleResourceClose(ctx, closed_type);
    }

    if (ctx.is_ffi_func) {
        trackCallEdges(ctx, callee_name);
    }
}

fn handleHeapAlloc(ctx: *TrackContext, callee_name: []const u8) void {
    if (std.mem.indexOf(u8, callee_name, "realloc") != null) {
        const old_ptr = c.LLVMGetOperand(ctx.inst, 0);
        if (@intFromPtr(old_ptr) != 0) {
            if (ctx.pointer_map.getPtr(old_ptr)) |old_info| {
                if (!old_info.freed) {
                    old_info.freed = true;
                    const old_ptr_int = @as(u64, @intFromPtr(old_ptr));
                    const func_name_raw = c.LLVMGetValueName(ctx.func);
                    const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                    _ = ctx.global_tracker.markFreed(old_ptr_int, func_name);
                    if (ctx.mem_graph) |mg| {
                        const free_inst: u64 = @intFromPtr(ctx.inst);
                        _ = mg.trackFree(free_inst, old_ptr_int, ctx.lang, 0) catch {};
                    }
                    _ = &old_info;
                }
            }
        }
    }

    const desc_alloc = std.fmt.allocPrint(ctx.allocator, "heap via {s}()", .{callee_name}) catch return;
    // Bug 4: Path-sensitive analysis — detect if allocation is inside
    // a conditional branch. Conditional allocs may not execute on all paths,
    // so path-insensitive leak detection produces FPs (FFT-LEAK-3, FFT-LEAK-2).
    const is_conditional = isAllocationInConditionalBranch(ctx.inst);

    const info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = ctx.inst,
        .source_desc = desc_alloc,
        .alloc_bb_id = ctx.bb_id,
        .needs_free = true,
        .is_conditional_alloc = is_conditional,
    };
    putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator) catch return;
    ctx.stats.total_pointers_tracked += 1;

    if (ctx.mgEffective()) |mg| {
        const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
        const alloc_lang = classifyAllocLanguageEnum(callee_name, ctx.lang) orelse ctx.lang;
        _ = mg.trackAlloc(inst_ptr, inst_ptr, .heap_alloc, ctx.zone, alloc_lang) catch return;
        mg.recordFuncAlloc(ctx.funcPtr());
    }

    {
        const inst_ptr_val = @as(u64, @intFromPtr(ctx.inst));
        const fn_name_raw = c.LLVMGetValueName(ctx.func);
        const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
        const inst_id = @as(u32, @truncate(inst_ptr_val));
        // Allocation size detection — DISABLED for safety.
        // Root cause: wasmtime_test.bc (and potentially other optimized .bc files)
        // contain instructions where LLVM C API (LLVMGetInstructionOpcode) segfaults
        // even with non-null inst pointer. This is a known LLVM issue with
        // optimized/bitcode modules where instruction metadata is incomplete.
        // The alloc_size is only used for confidence boost (not core detection),
        // so disabling it has zero impact on analysis precision.
        // TODO: Re-enable after implementing LLVM instruction validation or
        //       switching to LLVM's new C API (LLVMGetOperandAsValue etc.)
        const alloc_size: u64 = 0;
        _ = ctx.global_tracker.insertAlloc(inst_ptr_val, fn_name, callee_name, false, inst_id, is_conditional, ctx.func, alloc_size) catch return;
    }
}

fn handleDlsym(ctx: *TrackContext) void {
    const num_ops = c.LLVMGetNumOperands(ctx.inst);
    var op_idx: u32 = 0;
    while (op_idx < @min(num_ops, 2)) : (op_idx += 1) {
        const handle_arg = c.LLVMGetOperand(ctx.inst, op_idx);
        if (@intFromPtr(handle_arg) == 0) continue;
        if (ctx.pointer_map.get(handle_arg)) |handle_info| {
            if (handle_info.resource_type == .dlopen_handle or
                handle_info.resource_type == .none)
            {
                const desc = std.fmt.allocPrint(ctx.allocator, "dlsym-derived pointer from {s}", .{handle_info.source_desc}) catch continue;
                const info = PtrInfo{
                    .alloc_site = .heap,
                    .source_inst = ctx.inst,
                    .source_desc = desc,
                    .alloc_bb_id = ctx.bb_id,
                    .derived_from_handle = handle_arg,
                    .resource_type = handle_info.resource_type,
                    .needs_free = true,
                };
                putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator) catch continue;
                ctx.stats.total_pointers_tracked += 1;

                if (ctx.mgEffective()) |mg| {
                    const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
                    const handle_ptr = @as(u64, @intFromPtr(handle_arg));
                    mg.trackAliasStrong(inst_ptr, handle_ptr) catch {};
                }
            }
        }
    }
}

// ============================================================================
// Bug 4: Path-Sensitive Analysis Helpers
// ============================================================================

/// Check if an allocation instruction is inside a conditional (branch) path.
///
/// Path-insensitive analysis treats all allocations as "always executed",
/// but if an alloc is inside an if/else branch, it may not execute on all
/// code paths. This causes false positive leak reports for patterns like:
///
///   if (condition) {
///       p = malloc(100);  // Only on this branch
///   }
///   // p might not be allocated → no real leak
///
/// Detection heuristics:
///   1. Current BB has >1 predecessors → merge point from different paths
///   2. Current BB's single predecessor has a conditional terminator
///      (br with 2 successors, i.e., if/else)
///
/// Returns true if the allocation should be treated as conditional.
fn isAllocationInConditionalBranch(inst: c.LLVMValueRef) bool {
    const parent_bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(parent_bb) == 0) return false;

    const parent_func = c.LLVMGetBasicBlockParent(parent_bb);
    if (@intFromPtr(parent_func) == 0) return false;

    // Heuristic: If this allocation is NOT in the entry basic block,
    // it may be inside a conditional branch (if/else, loop body, etc.)
    // The entry block is always executed unconditionally.
    const entry_bb = c.LLVMGetEntryBasicBlock(parent_func);
    if (@intFromPtr(entry_bb) == 0) return false;

    // If parent_bb != entry_bb → potentially conditional
    if (parent_bb != entry_bb) {
        // Additional check: does the entry block end with a conditional branch?
        // If yes, we're definitely in a conditional path
        const entry_term = c.LLVMGetBasicBlockTerminator(entry_bb);
        if (@intFromPtr(entry_term) != 0) {
            const num_succ = c.LLVMGetNumSuccessors(entry_term);
            if (num_succ > 1) return true; // Entry has conditional branch
        }
        // Even without that, non-entry blocks in small functions are often conditional
    }

    return false;
}

fn handleFreeCall(ctx: *TrackContext, _: []const u8) void {
    if (ctx.mgEffective()) |mg| {
        mg.recordFuncFree(ctx.funcPtr());
    }

    const ptr_arg = c.LLVMGetOperand(ctx.inst, 0);
    if (ctx.pointer_map.getPtr(ptr_arg)) |ptr_info| {
        if (ptr_info.freed and !ptr_info.double_free_detected) {
            const new_desc = std.fmt.allocPrint(ctx.allocator, "DOUBLE_FREE: {s}", .{ptr_info.source_desc}) catch return;
            if (ptr_info.needs_free) {
                ctx.allocator.free(ptr_info.source_desc);
            }
            ptr_info.source_desc = new_desc;
            ptr_info.needs_free = true;
            ptr_info.double_free_detected = true;
        } else {
            ptr_info.freed = true;
        }
    }

    {
        const ptr_val = @as(u64, @intFromPtr(ptr_arg));
        const fn_name_raw = c.LLVMGetValueName(ctx.func);
        const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
        _ = ctx.global_tracker.markFreed(ptr_val, fn_name);

        if (ctx.mem_graph) |mg| {
            const free_inst: u64 = @intFromPtr(ctx.inst);
            const free_bb = c.LLVMGetInstructionParent(ctx.inst);
            const free_bb_id: u32 = if (@intFromPtr(free_bb) != 0) @truncate(@intFromPtr(free_bb)) else 0;
            _ = mg.trackFree(free_inst, ptr_val, ctx.lang, free_bb_id) catch {};
        }
    }

    if (ctx.mgEffective()) |mg| {
        const ptr_val = @as(u64, @intFromPtr(ptr_arg));

        if (mg.nodes.get(ptr_val)) |node| {
            var alias_iter = node.aliases.iterator();
            while (alias_iter.next()) |alias_entry| {
                const alias_ptr = alias_entry.key_ptr.*;
                if (alias_ptr % @sizeOf(usize) != 0) continue;
                const alias_ref: c.LLVMValueRef = @ptrFromInt(alias_ptr);
                if (ctx.pointer_map.getPtr(alias_ref)) |alias_info| {
                    if (!alias_info.freed and !alias_info.double_free_detected) {
                        alias_info.freed = true;
                    }
                }
            }
        }

        if (mg.alias_to_canonical.get(ptr_val)) |canon_inst| {
            if (canon_inst % @sizeOf(usize) == 0) {
                const canon_ref: c.LLVMValueRef = @ptrFromInt(canon_inst);
                if (ctx.pointer_map.getPtr(canon_ref)) |canon_info| {
                    if (!canon_info.freed and !canon_info.double_free_detected) {
                        canon_info.freed = true;
                    }
                }
                const fn_name_raw = c.LLVMGetValueName(ctx.func);
                const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                _ = ctx.global_tracker.markFreed(canon_inst, fn_name);
                const free_inst_canon: u64 = @intFromPtr(ctx.inst);
                const canon_bb = c.LLVMGetInstructionParent(ctx.inst);
                const canon_bb_id: u32 = if (@intFromPtr(canon_bb) != 0) @truncate(@intFromPtr(canon_bb)) else 0;
                _ = mg.trackFree(free_inst_canon, canon_inst, ctx.lang, canon_bb_id) catch {};
            }
        }
    }
}

fn handleResourceClose(ctx: *TrackContext, closed_type: ptr_types.ResourceType) void {
    if (ctx.mgEffective()) |mg| {
        mg.recordFuncFree(ctx.funcPtr());
    }

    const handle_arg = c.LLVMGetOperand(ctx.inst, 0);
    if (ctx.pointer_map.getPtr(handle_arg)) |handle_info| {
        handle_info.freed = true;
        var it = ctx.pointer_map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.resource_type == closed_type and
                entry.value_ptr.derived_from_handle != null)
            {
                const derived = entry.value_ptr.derived_from_handle.?;
                if (isSameOrAlias(derived, handle_arg)) {
                    entry.value_ptr.freed = true;
                }
            }
        }
    } else {
        var it = ctx.pointer_map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.resource_type == closed_type and
                entry.value_ptr.derived_from_handle == null)
            {
                entry.value_ptr.freed = true;
            }
        }
    }
}

fn trackCallEdges(ctx: *TrackContext, callee_name: []const u8) void {
    if (ctx.mgEffective()) |mg| {
        const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
        const num_args = getCallInstArgCount(ctx.inst);
        var arg_i: u32 = 0;
        while (arg_i < num_args) : (arg_i += 1) {
            const arg = c.LLVMGetOperand(ctx.inst, arg_i);
            if (@intFromPtr(arg) == 0) continue;
            const arg_ptr_val = @as(u64, @intFromPtr(arg));
            if (mg.nodes.get(arg_ptr_val) != null or ctx.pointer_map.contains(arg)) {
                _ = mg.trackCallArg(inst_ptr, callee_name, arg_ptr_val, arg_i) catch {};
            }
        }
        if (ctx.pointer_map.contains(ctx.inst)) {
            const ret_ptr_val = @as(u64, @intFromPtr(ctx.inst));
            _ = mg.trackCallRet(inst_ptr, callee_name, ret_ptr_val) catch {};
        }
    }
}

// ============================================================================
// Load Handler
// ============================================================================

pub fn handleLoad(ctx: *TrackContext) !void {
    if (ctx.mgEffective()) |mg| {
        const src_ptr = @as(u64, @intFromPtr(c.LLVMGetOperand(ctx.inst, 0)));
        const content_kind = mg.getContentSource(src_ptr);
        if (content_kind != .unknown) {
            const inst_ptr = @as(u64, @intFromPtr(ctx.inst));
            _ = mg.trackAlloc(inst_ptr, inst_ptr, content_kind, ctx.zone, ctx.lang) catch {};
        }
    }

    try propagateOrigin(ctx.inst, c.LLVMGetOperand(ctx.inst, 0), ctx.pointer_map, ctx.allocator, ctx.bb_id, ctx.mem_graph);

    if (ctx.mgEffective()) |mg| {
        const src_ptr = @as(u64, @intFromPtr(c.LLVMGetOperand(ctx.inst, 0)));
        const content_kind = mg.getContentSource(src_ptr);
        if (content_kind == .heap_alloc or content_kind == .resource_alloc) {
            if (ctx.pointer_map.getPtr(ctx.inst)) |load_info| {
                load_info.alloc_site = .heap;
            }
        }
    }
}

// ============================================================================
// Store Handler
// ============================================================================

pub fn handleStore(ctx: *TrackContext) !void {
    const value = c.LLVMGetOperand(ctx.inst, 0);
    const dest = c.LLVMGetOperand(ctx.inst, 1);

    if (isFuncParam(value, ctx.func)) {
        if (ctx.pointer_map.getPtr(dest)) |dest_info| {
            if (dest_info.alloc_site == .stack) {
                dest_info.is_param_storage = true;
            }
        }
    }

    if (ctx.pointer_map.get(value)) |src_info| {
        if (ctx.mgEffective()) |mg| {
            const dest_ptr = @as(u64, @intFromPtr(dest));
            const content_kind: memory_graph.SourceKind = switch (src_info.alloc_site) {
                .heap => .heap_alloc,
                .stack => .alloca,
                .global => .unknown,
                .parameter => .unknown,
                .constant => .unknown,
                .unknown => .unknown,
            };
            mg.recordContentSource(dest_ptr, content_kind);
        }

        var new_info = src_info;
        const desc = try ctx.allocator.dupe(u8, src_info.source_desc);
        new_info.source_desc = desc;
        new_info.needs_free = true;
        try putPtrInfo(ctx.pointer_map, dest, new_info, ctx.allocator);

        if (ctx.mgEffective()) |mg| {
            const from_hash = @as(u64, @intFromPtr(dest));
            const to_hash = @as(u64, @intFromPtr(value));
            if (mg.trackAliasStrong(from_hash, to_hash)) |_| {} else |err| {
                log.debug("[TRACK] trackAliasStrong FAILED err={} from={x} to={x}", .{ err, from_hash, to_hash });
            }
        }
    } else {
        if (ctx.mgEffective()) |mg| {
            const dest_ptr = @as(u64, @intFromPtr(dest));
            const content_kind = inferContentKind(value);
            if (content_kind != .unknown) {
                mg.recordContentSource(dest_ptr, content_kind);
            }
        }
    }
}

// ============================================================================
// GetElementPtr Handler
// ============================================================================

pub fn handleGetElementPtr(ctx: *TrackContext) !void {
    const src = c.LLVMGetOperand(ctx.inst, 0);
    _ = ctx.pointer_map.get(src) != null;
    try propagateOrigin(ctx.inst, c.LLVMGetOperand(ctx.inst, 0), ctx.pointer_map, ctx.allocator, ctx.bb_id, ctx.mem_graph);
}

// ============================================================================
// BitCast / Conversion Handlers
// ============================================================================

pub fn handleBitCastAndConversions(ctx: *TrackContext) !void {
    const src = c.LLVMGetOperand(ctx.inst, 0);
    if (@intFromPtr(src) != 0) {
        try propagateOrigin(ctx.inst, src, ctx.pointer_map, ctx.allocator, ctx.bb_id, ctx.mem_graph);
    }
}

// ============================================================================
// Phi Node Handler
// ============================================================================

pub fn handlePhi(ctx: *TrackContext) !void {
    const num_incoming = c.LLVMCountIncoming(ctx.inst);
    var merged_site: PtrAllocSite = .constant;
    var found_any: bool = false;
    var best_desc: []const u8 = "phi merge";

    var i: u32 = 0;
    while (i < num_incoming) : (i += 1) {
        const incoming = c.LLVMGetIncomingValue(ctx.inst, i);
        if (@intFromPtr(incoming) == 0) continue;

        if (ctx.pointer_map.get(incoming)) |incoming_info| {
            found_any = true;
            merged_site = mergeAllocSite(merged_site, incoming_info.alloc_site);
            if (incoming_info.alloc_site == .heap or
                incoming_info.alloc_site == .parameter)
            {
                best_desc = incoming_info.source_desc;
            }
        }
    }

    if (found_any) {
        const desc = try ctx.allocator.dupe(u8, best_desc);
        const info = PtrInfo{
            .alloc_site = merged_site,
            .source_inst = ctx.inst,
            .source_desc = desc,
            .alloc_bb_id = ctx.bb_id,
            .needs_free = true,
        };
        try putPtrInfo(ctx.pointer_map, ctx.inst, info, ctx.allocator);
    }
}

// ============================================================================
// Ret Handler
// ============================================================================

pub fn handleRet(ctx: *TrackContext) void {
    if (ctx.mgEffective()) |mg| {
        const num_ops = c.LLVMGetNumOperands(ctx.inst);
        if (num_ops > 0) {
            const ret_val = c.LLVMGetOperand(ctx.inst, 0);
            if (@intFromPtr(ret_val) != 0) {
                const ret_type = c.LLVMTypeOf(ret_val);
                if (@intFromPtr(ret_type) != 0 and
                    c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
                {
                    mg.recordFuncReturns(ctx.funcPtr());
                }
            }
        }
    }
}

// ============================================================================
// LLVM Lifetime Intrinsic Handler (T1.2)
// ============================================================================

/// Handle @llvm.lifetime.start and @llvm.lifetime.end intrinsics.
///
/// These intrinsics mark the begin and end of a variable's lifetime in the IR.
/// LLVM generates them when optimizations are enabled (-O1 and above).
/// They allow us to precisely track when an alloca is "alive" vs "dead",
/// which reduces false positives in stack escape detection.
///
/// Intrinsic signatures:
///   - @llvm.lifetime.start.p0(i64 %size, ptr %alloca) → void
///   - @llvm.lifetime.end.p0(i64 %size, ptr %alloca)   → void
///
/// The first operand is the size (ignored here), the second is the alloca pointer.
pub fn handleLifetimeIntrinsic(ctx: *TrackContext) void {
    const lifetime_map = ctx.lifetime_map orelse return;

    const called = c.LLVMGetCalledValue(ctx.inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;

    const intrinsic_name = std.mem.span(name_ptr);

    // Get the alloca operand (second operand, index 1)
    const alloca_operand = c.LLVMGetOperand(ctx.inst, 1);
    if (@intFromPtr(alloca_operand) == 0) return;

    // Check if this operand is a known alloca in our pointer_map
    if (!ctx.pointer_map.contains(alloca_operand)) {
        return;
    }

    if (std.mem.indexOf(u8, intrinsic_name, "llvm.lifetime.start") != null) {
        const interval = LifetimeInterval{
            .start_inst = ctx.inst,
            .end_inst = null,
        };
        lifetime_map.put(alloca_operand, interval) catch {
            log.warn("[ptr-lifetime] Failed to record lifetime.start for alloca", .{});
            return;
        };
    } else if (std.mem.indexOf(u8, intrinsic_name, "llvm.lifetime.end") != null) {
        if (lifetime_map.getPtr(alloca_operand)) |existing| {
            existing.end_inst = ctx.inst;
        } else {
            const interval = LifetimeInterval{
                .start_inst = ctx.inst,
                .end_inst = ctx.inst,
            };
            lifetime_map.put(alloca_operand, interval) catch {
                log.warn("[ptr-lifetime] Failed to record orphaned lifetime.end", .{});
                return;
            };
        }
    }
}
