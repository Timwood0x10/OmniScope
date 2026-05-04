const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const memory_graph = @import("../semantics/memory_graph.zig");

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const PtrAllocSite = @import("ptr_lifetime_types.zig").PtrAllocSite;
const getAllocatorKB = @import("ptr_lifetime_types.zig").getAllocatorKB;

/// IR instruction tracking logic for PtrLifetimePass.
/// Extracted from ptr_lifetime.zig for code organization.
///
/// This module contains the core pointer tracking functions:
/// - inferContentKind: Classify value sources
/// - putPtrInfo: HashMap insertion with cleanup
/// - mergeAllocSite: Phi node merging
/// - propagateOrigin: Alias chain propagation
pub fn inferContentKind(value: c.LLVMValueRef) memory_graph.SourceKind {
    if (c.LLVMIsAGlobalValue(value) != null) return .resource_alloc;
    if (c.LLVMIsAFunction(value) != null) return .resource_alloc;
    if (c.LLVMIsAConstant(value) != null) return .resource_alloc;

    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const called = c.LLVMGetCalledValue(value);
        if (@intFromPtr(called) != 0) {
            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) != 0) {
                const callee_name = std.mem.span(name_ptr);
                if (getAllocatorKB()) |kb| {
                    if (kb.isAllocator(callee_name)) return .heap_alloc;
                }
                if (std.mem.indexOf(u8, callee_name, "malloc") != null or
                    std.mem.indexOf(u8, callee_name, "calloc") != null or
                    std.mem.indexOf(u8, callee_name, "realloc") != null)
                {
                    return .heap_alloc;
                }
            }
        }
        return .call_result;
    }

    return .unknown;
}

pub fn putPtrInfo(
    map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    key: c.LLVMValueRef,
    info: PtrInfo,
    allocator: std.mem.Allocator,
) !void {
    const gop = try map.getOrPut(key);
    if (gop.found_existing and gop.value_ptr.needs_free) {
        allocator.free(gop.value_ptr.source_desc);
    }
    gop.value_ptr.* = info;
}

pub fn mergeAllocSite(current: PtrAllocSite, incoming: PtrAllocSite) PtrAllocSite {
    if (current == .heap or incoming == .heap) return .heap;
    if (current == .parameter or incoming == .parameter) return .parameter;
    if (current == .stack or incoming == .stack) return .stack;
    if (current == .global or incoming == .global) return .global;
    if (current == .constant or incoming == .constant) return .constant;
    return .unknown;
}

pub fn propagateOrigin(
    dst: c.LLVMValueRef,
    src: c.LLVMValueRef,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    allocator: std.mem.Allocator,
    bb_id: usize,
    mem_graph: ?*memory_graph.MemoryGraph,
) !void {
    if (pointer_map.get(src)) |src_info| {
        const desc = try allocator.dupe(u8, src_info.source_desc);
        var new_info = src_info;
        new_info.source_desc = desc;
        new_info.alloc_bb_id = bb_id;
        new_info.needs_free = true;
        try putPtrInfo(pointer_map, dst, new_info, allocator);

        if (mem_graph) |mg| {
            const from_hash = @as(u64, @intFromPtr(dst));
            const to_hash = @as(u64, @intFromPtr(src));
            mg.trackAlias(from_hash, to_hash) catch {};
        }
    }
}
