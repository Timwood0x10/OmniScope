const std = @import("std");
const zone = @import("zone_classifier.zig");

/// Type definitions for MemoryGraph.
/// Extracted from memory_graph.zig for code organization.
///
/// This module contains all type definitions used by the MemoryGraph:
/// - ZoneKind, Language (re-exported from zone_classifier)
/// - SourceKind, FuncCounter, OwnershipTransferStatus
/// - ResourceLifecycle, CallArgEdge, CallRetEdge
/// - DangerPathKind, AllocNode (internal)
pub const ZoneKind = zone.ZoneKind;
pub const Language = zone.Language;

pub const MemoryGraphError = error{
    OutOfMemory,
    NodeNotFound,
};

pub const SourceKind = enum(u8) {
    alloca,
    heap_alloc,
    resource_alloc,
    call_result,
    unknown,
};

pub const FuncCounter = struct {
    allocs: u32,
    frees: u32,
    returns_pointer: bool,

    pub fn net(self: FuncCounter) i64 {
        return @as(i64, @intCast(self.allocs)) - @as(i64, @intCast(self.frees));
    }

    pub fn hasHeapOps(self: FuncCounter) bool {
        return self.allocs > 0 or self.frees > 0;
    }
};

pub const OwnershipTransferStatus = enum(u8) {
    valid,
    not_tracked,
    transfer_without_ownership,
    transfer_after_free,
    potential_double_transfer,
};

pub const ResourceLifecycle = struct {
    allocation_site: u64,
    source_kind: SourceKind,
    aliases: []const u64,
    is_freed: bool,
    free_site: ?u64,
};

pub const CallArgEdge = struct {
    caller_inst: u64,
    callee_name: []const u8,
    arg_ptr: u64,
    arg_index: u32,
};

pub const CallRetEdge = struct {
    caller_inst: u64,
    callee_name: []const u8,
    ret_ptr: u64,
};

pub const DangerPathKind = enum {
    none,
    unsafe_alloc,
    cross_lang_lifecycle,
    ffi_arg,
    ffi_ret,
};

const AllocNode = struct {
    id: u64,
    alloc_inst: u64,
    merkle_root: u64,
    aliases: std.AutoHashMap(u64, void),
    freed: bool,
    freed_by: ?u64,
    source_kind: SourceKind,
    zone: ZoneKind = .unknown,
    alloc_lang: Language = .unknown,
    free_lang: ?Language = null,
};
