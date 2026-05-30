//! Pointer Lifetime Core Helpers
//!
//! Helper functions extracted from ptr_lifetime.zig to reduce main file size.
//! These are internal utilities used by PtrLifetimePass for:
//! - Debug file path extraction from LLVM metadata
//! - Content kind inference for untracked values
//! - Pointer info map operations (put/merge/propagate)
//!
//! Module prefix: [ptr-lifetime-core]

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const log = @import("../../../common/log.zig");

const memory_graph = @import("../../../semantics/memory_graph.zig");
const allocator_kb = @import("../../../semantics/allocator_kb.zig");
const zone_cls = @import("../../../semantics/zone_classifier.zig");
const Lang = zone_cls.Language;

const ptr_types = @import("ptr_lifetime_types.zig");
pub const PtrAllocSite = ptr_types.PtrAllocSite;
pub const PtrInfo = ptr_types.PtrInfo;
pub const FreeSiteList = ptr_types.FreeSiteList;

// ============================================================================
// Debug Info Extraction
// ============================================================================

/// Extract debug file path from LLVM subprogram metadata.
/// Used by NoiseReduction Layer 2 (path-based filter).
pub fn extractDebugFilePath(func: c.LLVMValueRef) ?[]const u8 {
    const subprogram = c.LLVMGetSubprogram(func);
    if (@intFromPtr(subprogram) == 0) return null;

    const file_ref = c.LLVMDIScopeGetFile(subprogram);
    if (@intFromPtr(file_ref) == 0) return null;

    var filename_len: c_uint = undefined;
    const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
    if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

    const max_path_len: c_uint = 4096;
    if (filename_len > max_path_len) return null;
    if (filename_ptr[0] == 0) return null;

    return filename_ptr[0..filename_len];
}

// ============================================================================
// Content Kind Inference
// ============================================================================

/// Infer the content source kind of a value that is not in pointer_map.
/// Used by store's else branch to record content_source for values that
/// pointer_map doesn't track (global constants, function params, etc.).
pub fn inferContentKind(value: c.LLVMValueRef) memory_graph.SourceKind {
    // Global variable (e.g., @.str.1027, @g_var)
    if (c.LLVMIsAGlobalValue(value) != null) return .resource_alloc;
    // Function pointer
    if (c.LLVMIsAFunction(value) != null) return .resource_alloc;
    // Constant expression or constant int (null pointer, inttoptr, etc.)
    if (c.LLVMIsAConstant(value) != null) return .resource_alloc;

    // Call/invoke result — the callee may return heap memory.
    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const called = c.LLVMGetCalledValue(value);
        if (@intFromPtr(called) != 0) {
            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) != 0) {
                const callee_name = std.mem.span(name_ptr);
                // Check if this is a known allocator function
                if (ptr_types.getAllocatorKB()) |kb| {
                    if (kb.isAllocator(callee_name)) return .heap_alloc;
                }
                // Fallback: check common allocator patterns
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

// ============================================================================
// Pointer Map Operations
// ============================================================================

/// Safely insert or update a pointer info entry in the map.
/// Handles cleanup of previously allocated source_desc strings.
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

/// Merge two allocation sites for phi node tracking.
/// Priority: heap > parameter > stack > global > constant > unknown.
/// If any incoming branch is heap, the phi result could be heap at runtime.
pub fn mergeAllocSite(current: PtrAllocSite, incoming: PtrAllocSite) PtrAllocSite {
    // If either is heap, result is heap (runtime may take that branch)
    if (current == .heap or incoming == .heap) return .heap;
    // Parameter is next priority (could be any origin)
    if (current == .parameter or incoming == .parameter) return .parameter;
    // Stack: both must be stack for result to be stack
    if (current == .stack or incoming == .stack) return .stack;
    // Global
    if (current == .global or incoming == .global) return .global;
    // Constant
    if (current == .constant or incoming == .constant) return .constant;
    return .unknown;
}

/// Propagate pointer origin information from src to dst.
/// Creates an alias relationship in MemoryGraph when available.
/// Used by load, getelementptr, bitcast, ptrtoint, inttoptr, addrspacecast.
///
/// PERF: Optimized to avoid unnecessary string duplication when src and dst
/// are in the same basic block (bb_id matches). The source_desc string is
/// shared via pointer reference instead of copied, reducing allocation overhead
/// for the common case of pointer propagation within the same scope.
pub fn propagateOrigin(
    dst: c.LLVMValueRef,
    src: c.LLVMValueRef,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    allocator: std.mem.Allocator,
    bb_id: usize,
    mem_graph: ?*memory_graph.MemoryGraph,
) !void {
    if (pointer_map.get(src)) |src_info| {
        // PERF: When propagating within the same basic block, share the string
        // reference instead of duplicating. The source_info's needs_free flag
        // ensures proper cleanup. For cross-block propagation, duplicate to
        // avoid use-after-free if the source block's data is freed first.
        const same_bb = (bb_id == src_info.alloc_bb_id);
        var new_info = src_info;
        if (!same_bb) {
            // Cross-block: must duplicate string for independent lifetime
            const desc = try allocator.dupe(u8, src_info.source_desc);
            new_info.source_desc = desc;
            new_info.needs_free = true;
        } else {
            // Same block: share string reference, mark as not needing free
            // (the original PtrInfo will handle cleanup)
            new_info.needs_free = false;
        }
        new_info.alloc_bb_id = bb_id;
        try putPtrInfo(pointer_map, dst, new_info, allocator);

        // Sync alias with MemoryGraph.
        if (mem_graph) |mg| {
            const from_hash = @as(u64, @intFromPtr(dst));
            const to_hash = @as(u64, @intFromPtr(src));
            if (mg.trackAliasStrong(from_hash, to_hash)) |_| {} else |err| {
                log.debug("[HELPERS] trackAliasStrong FAILED err={} from={x} to={x}", .{ err, from_hash, to_hash });
            }
        }
    }
}

// ============================================================================
// Post-Analysis Cross-Function Alias Propagation (R8.3-f)
// ============================================================================

/// Post-analysis cross-function freed status propagation.
/// Optimized: Instead of O(N×A) scan (each node × each alias),
/// build reverse alias index O(E) then propagate O(F) from freed nodes.
pub fn propagateCrossFunctionFreedStatus(
    allocator: std.mem.Allocator,
    mem_graph: *memory_graph.MemoryGraph,
    global_tracker: *@import("../../pass.zig").GlobalAllocTracker,
    lang: Lang,
) !u32 {
    _ = lang;
    var propagated: u32 = 0;

    var reverse_alias = std.AutoHashMap(u64, std.ArrayList(u64)).init(allocator);
    defer {
        var ra_iter = reverse_alias.iterator();
        while (ra_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        reverse_alias.deinit();
    }

    {
        var alias_iter = mem_graph.alias_to_canonical.iterator();
        while (alias_iter.next()) |entry| {
            const from_ptr = entry.key_ptr.*;
            const to_ptr = entry.value_ptr.*;
            const gop = try reverse_alias.getOrPut(to_ptr);
            if (!gop.found_existing) {
                gop.value_ptr.* = try std.ArrayList(u64).initCapacity(allocator, 0);
            }
            try gop.value_ptr.append(allocator, from_ptr);
        }
    }

    var node_iter = mem_graph.nodes.iterator();
    while (node_iter.next()) |entry| {
        const node = entry.value_ptr.*;
        if (node.freed) {
            const freed_ptr = entry.key_ptr.*;
            if (reverse_alias.get(freed_ptr)) |aliasers| {
                for (aliasers.items) |aliaser_ptr| {
                    if (mem_graph.nodes.get(aliaser_ptr)) |aliaser_node| {
                        if (!aliaser_node.freed) {
                            _ = global_tracker.markFreed(aliaser_node.alloc_inst, "R8.3-f-alias-propagation");
                            {
                                const free_inst = node.freed_by orelse aliaser_node.alloc_inst;
                                _ = mem_graph.trackFree(free_inst, aliaser_ptr, node.alloc_lang, 0) catch {};
                            }
                            propagated += 1;
                        }
                    }
                }
            }
        }
    }

    return propagated;
}
