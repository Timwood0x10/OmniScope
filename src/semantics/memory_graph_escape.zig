//! Memory Graph Escape Tracking — P6 PointerContract integration.
//!
//! Provides escape recording and query methods for the MemoryGraph.
//! Tracks how pointers escape allocation scope via:
//!   - Return to caller
//!   - Out-parameters
//!   - Field stores (owner objects)
//!   - Global/static storage
//!   - Callbacks/closures
//!   - Thread APIs
//!
//! Split from memory_graph.zig to keep file under 1000 lines.

const std = @import("std");
const log = @import("../common/log.zig");

const mg_types = @import("../types/memory_graph_types.zig");
const FamilyId = mg_types.FamilyId;

const family_registry_mod = @import("resource/family_registry.zig");
const ResourceFamilyRegistry = family_registry_mod.ResourceFamilyRegistry;

const escape_mod = @import("resource/escape.zig");
pub const EscapeKind = escape_mod.EscapeKind;
const EscapeRecord = escape_mod.EscapeRecord;
const EscapeList = escape_mod.EscapeList;

const MemoryGraph = @This();

/// Classify the allocation family for a node by callee name.
/// Call this after trackAlloc when the allocator function name is known.
/// No-op if family_registry is not set or name is null.
pub fn classifyAllocFamily(graph: *MemoryGraph, ptr_val: u64, callee_name: []const u8) void {
    const node = graph.nodes.get(ptr_val) orelse return;
    const registry = graph.family_registry orelse return;
    if (registry.lookupAcquire(callee_name, null)) |op| {
        node.alloc_family = op.family;
        log.debug("alloc_family={s} for alloc at 0x{x} (callee={s})", .{
            @tagName(op.family), ptr_val, callee_name,
        });
    }
}

/// Classify the release family for a free site by callee name.
/// Call this after trackFree when the deallocator function name is known.
/// Applies to the most recent FreeRecord on the node's free_sites list.
pub fn classifyReleaseFamily(graph: *MemoryGraph, ptr_val: u64, callee_name: []const u8) void {
    const node = graph.nodes.get(ptr_val) orelse return;
    const registry = graph.family_registry orelse return;
    if (node.free_sites.items.len == 0) return;
    if (registry.lookupRelease(callee_name, null)) |op| {
        var last = &node.free_sites.items[node.free_sites.items.len - 1];
        last.release_family = op.family;
        log.debug("release_family={s} for free at 0x{x} (callee={s})", .{
            @tagName(op.family), ptr_val, callee_name,
        });
    }
}

// =====================================================================
// Escape Tracking (P6: PointerContract integration)
// =====================================================================

/// Record that a pointer escaped via return to caller (P6-6).
/// This is a valid disposal of ownership — the caller now owns it.
pub fn recordEscapeReturnToCaller(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
    graph.recordEscape(ptr_val, EscapeRecord.init(.return_to_caller, inst_addr));
    log.debug("ESCAPE: ptr=0x{x} returned to caller at inst=0x{x}", .{ ptr_val, inst_addr });
}

/// Record that a pointer escaped via out-parameter (P6-7).
/// Valid disposal — caller receives ownership through out-param.
pub fn recordEscapeOutParam(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
    graph.recordEscape(ptr_val, EscapeRecord.init(.out_param, inst_addr));
    log.debug("ESCAPE: ptr=0x{x} written to out-param at inst=0x{x}", .{ ptr_val, inst_addr });
}

/// Record that a pointer escaped into an owner object's field (P6-8).
/// Valid disposal if owner object is properly managed.
pub fn recordEscapeFieldStore(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64, field_name: []const u8) void {
    var rec = EscapeRecord.init(.field_store, inst_addr);
    rec.withTarget(field_name);
    rec.withConfidence(0.85);
    graph.recordEscape(ptr_val, rec);
    log.debug("ESCAPE: ptr=0x{x} stored to field '{s}' at inst=0x{x}", .{ ptr_val, field_name, inst_addr });
}

/// Record that a pointer escaped to global/static storage (P6-9).
/// Process-lifetime — NOT a leak.
pub fn recordEscapeGlobalStore(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64, var_name: []const u8) void {
    var rec = EscapeRecord.init(.global_store, inst_addr);
    rec.withTarget(var_name);
    rec.withConfidence(0.9);
    graph.recordEscape(ptr_val, rec);
    log.debug("ESCAPE: ptr=0x{x} stored to global '{s}' at inst=0x{x}", .{ ptr_val, var_name, inst_addr });
}

/// Record static-lifetime escape specifically (C++ static initializers).
pub fn recordEscapeStaticLifetime(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64) void {
    var rec = EscapeRecord.init(.static_lifetime, inst_addr);
    rec.withConfidence(0.85);
    graph.recordEscape(ptr_val, rec);
    log.debug("ESCAPE: ptr=0x{x} has static lifetime at inst=0x{x}", .{ ptr_val, inst_addr });
}

/// Record that a pointer escaped to a callback/closure (P6-10).
/// Lifetime risk — callback must not outlive the resource.
pub fn recordEscapeCallback(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64, callback_name: []const u8) void {
    var rec = EscapeRecord.init(.callback, inst_addr);
    rec.withTarget(callback_name);
    rec.withConfidence(0.7);
    graph.recordEscape(ptr_val, rec);
    log.debug("ESCAPE: ptr=0x{x} passed to callback '{s}' at inst=0x{x}", .{ ptr_val, callback_name, inst_addr });
}

/// Record that a pointer escaped to a spawned thread (P6-11).
/// Lifetime risk — thread may access after spawn returns.
pub fn recordEscapeThread(graph: *MemoryGraph, ptr_val: u64, inst_addr: u64, thread_api: []const u8) void {
    var rec = EscapeRecord.init(.thread, inst_addr);
    rec.withTarget(thread_api);
    rec.withConfidence(0.7);
    graph.recordEscape(ptr_val, rec);
    log.debug("ESCAPE: ptr=0x{x} passed to thread API '{s}' at inst=0x{x}", .{ ptr_val, thread_api, inst_addr });
}

/// Internal: record an escape event on a node's escape list.
fn recordEscape(graph: *MemoryGraph, ptr_val: u64, rec: EscapeRecord) void {
    const node = graph.nodes.get(ptr_val) orelse return;
    if (node.escapes == null) {
        // Lazily initialize escape list
        const list = graph.allocator.create(EscapeList) catch {
            log.warn("Failed to allocate EscapeList for ptr=0x{x}", .{ptr_val});
            return;
        };
        list.* = EscapeList.init(graph.allocator);
        node.escapes = list;
    }
    node.escapes.?.add(rec) catch {};
}

/// Check if a resource has any valid-disposal escape.
/// Used by leak detector (P6-12): `owned && !released && !valid_escape` → leak.
pub fn hasValidEscape(graph: *const MemoryGraph, ptr_val: u64) bool {
    const node = graph.nodes.get(ptr_val) orelse return false;
    const escapes = node.escapes orelse return false;
    return escapes.hasValidEscape();
}

/// Check if a resource has any lifetime-risk escape (callback/thread).
pub fn hasLifetimeRiskEscape(graph: *const MemoryGraph, ptr_val: u64) bool {
    const node = graph.nodes.get(ptr_val) orelse return false;
    const escapes = node.escapes orelse return false;
    return escapes.hasLifetimeRisk();
}
