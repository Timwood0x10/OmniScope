//! Helper functions for MemoryGraph methods.
//!
//! Extracted from memory_graph.zig to reduce file size.
//! Contains pure logic functions that don't depend on MemoryGraph self,
//! used by struct methods via delegation.

const std = @import("std");
const log = std.log.scoped(.memory_graph_methods);

const mg_types = @import("memory_graph_types.zig");
pub const DangerSurface = mg_types.DangerSurface;
pub const DangerPathKind = mg_types.DangerPathKind;
pub const FreeRecord = mg_types.FreeRecord;

/// Builds a StringHashSet of FFI boundary callee names from DangerSurface slice.
/// Used by isOnDangerPath for O(1) callee name lookup.
/// Caller owns the returned set and must deinit it.
pub fn buildFFISet(
    allocator: std.mem.Allocator,
    ffi_boundaries: []const DangerSurface,
) std.StringHashMap(void) {
    var ffi_set = std.StringHashMap(void).init(allocator);
    for (ffi_boundaries) |b| {
        if (b.is_ffi_boundary) {
            ffi_set.put(b.callee_name, {}) catch {};
        }
    }
    return ffi_set;
}

/// Checks if any pair of free sites share the same basic block.
/// Same-BB frees are always on the same execution path (real double-free).
pub fn checkFreeSitesSameBB(free_sites: []const FreeRecord) bool {
    for (free_sites, 0..) |site_a, i| {
        for (free_sites[i + 1 ..]) |site_b| {
            if (site_a.bb_id != 0 and site_a.bb_id == site_b.bb_id) {
                return true;
            }
        }
    }
    return false;
}

/// Checks if any free site's BB can reach another free site's BB.
/// Uses reachability check provided by caller via context pointer.
/// Returns true if any pair is on the same execution path.
pub fn checkFreeSitesReachability(
    free_sites: []const FreeRecord,
    comptime Context: type,
    ctx: *const Context,
    reachableFn: *const fn (ctx_ptr: *const Context, u32, u32) bool,
) bool {
    for (free_sites, 0..) |site_a, i| {
        if (site_a.bb_id == 0) continue;
        for (free_sites[i + 1 ..]) |site_b| {
            if (site_b.bb_id == 0) continue;
            if (reachableFn(ctx, site_a.bb_id, site_b.bb_id)) return true;
            if (reachableFn(ctx, site_b.bb_id, site_a.bb_id)) return true;
        }
    }
    return false;
}

/// Checks if any free site has valid BB info (bb_id != 0).
pub fn hasBBInfo(free_sites: []const FreeRecord) bool {
    for (free_sites) |site| {
        if (site.bb_id != 0) return true;
    }
    return false;
}

/// Initializes or retrieves a FuncCounter entry in a HashMap.
/// Used by recordFuncAlloc/Free/Returns to avoid duplicated init code.
pub fn getOrInitFuncCounter(
    map: *std.AutoHashMap(u64, mg_types.FuncCounter),
    func_ptr: u64,
) ?*mg_types.FuncCounter {
    const gop = map.getOrPut(func_ptr) catch return null;
    if (!gop.found_existing) {
        gop.value_ptr.* = .{ .allocs = 0, .frees = 0, .returns_pointer = false };
    }
    return gop.value_ptr;
}

/// Clears an inner HashMap-of-ArrayLists pattern used by call edge indices.
/// Iterates all values, deinit each ArrayList, then clearRetainingCapacity.
pub fn clearCallIndexMap(comptime K: type, map: *std.AutoHashMap(K, std.ArrayList(u32)), allocator: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(allocator);
    }
    map.clearRetainingCapacity();
}

pub fn clearStringCallIndexMap(map: *std.StringHashMap(std.ArrayList(u32)), allocator: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(allocator);
    }
    map.clearRetainingCapacity();
}

/// Deinitializes an inner HashMap-of-ArrayLists pattern used by call edge indices.
/// Iterates all values, deinit each ArrayList with allocator, then deinit the map.
pub fn deinitCallIndexMap(comptime K: type, map: *std.AutoHashMap(K, std.ArrayList(u32)), allocator: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}

pub fn deinitStringCallIndexMap(map: *std.StringHashMap(std.ArrayList(u32)), allocator: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}
