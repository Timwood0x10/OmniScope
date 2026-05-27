//! Resource Contract Graph Builder — Builds a unified graph of resource lifecycle.
//!
//! Replaces scattered per-pass state tracking with a single directed graph
//! where nodes are resource instances and edges are operations (acquire/release/
//! retain/transfer/escape). The graph is the source of truth for all downstream
//! analysis: leak detection, cross-free validation, borrow-escape checking.
//!
//! Design:
//!   - One ResourceInstance per allocation site (deduplicated by pointer value)
//!   - ContractEdge connects instances through operations
//!   - Built from MemoryGraph nodes + SummaryStore effects during pipeline init
//!   - Read-only after build; all passes query the same graph

const std = @import("std");

const family = @import("../semantics/resource/family.zig");
pub const FamilyId = family.FamilyId;
const effect = @import("../semantics/resource/effect.zig");
pub const Effect = effect.Effect;
pub const EffectSet = effect.EffectSet;
const contract = @import("../semantics/resource/contract.zig");
pub const PointerContract = contract.PointerContract;
pub const ContractTransition = contract.ContractTransition;
pub const ContractViolation = contract.ContractViolation;
const escape_mod = @import("../semantics/resource/escape.zig");
pub const EscapeKind = escape_mod.EscapeKind;

// ============================================================================
// ResourceInstance — One node in the contract graph
// ============================================================================

/// Represents one allocated resource instance in the program.
/// Each unique allocation site (by pointer value) maps to exactly one instance.
pub const ResourceInstance = struct {
    /// Unique identifier for this resource instance.
    id: u32,
    /// Raw LLVM value address of the allocation instruction.
    alloc_inst_addr: u64,
    /// Which resource family this belongs to (from registry lookup).
    family: ?FamilyId = null,
    /// Current ownership contract state.
    state: PointerContract = .unknown,
    /// Function name where this resource was allocated.
    alloc_func_name: ?[]const u8 = null,
    /// All edges (operations) on this resource.
    edges: std.ArrayList(ContractEdge),
    /// Escape records for this resource (from MemoryGraph).
    escapes: ?*escape_mod.EscapeList = null,
    /// Evidence string explaining why this classification was made.
    evidence: ?[]const u8 = null,
    /// Confidence [0.0, 1.0] in this instance's classification.
    confidence: f32 = 0.5,

    pub fn init(allocator: std.mem.Allocator, id: u32, addr: u64) ResourceInstance {
        return .{
            .id = id,
            .alloc_inst_addr = addr,
            .edges = std.ArrayList(ContractEdge).init(allocator),
        };
    }

    pub fn deinit(self: *ResourceInstance) void {
        self.edges.deinit();
    }
};

// ============================================================================
// ContractEdge — One operation edge in the contract graph
// ============================================================================

/// A directed edge representing one operation on a resource.
/// Edges form the history of what happened to each resource instance.
pub const ContractEdge = struct {
    /// Source instance ID (the resource being operated on).
    from_id: u32,
    /// Target instance ID (for transfer edges; same as from_id otherwise).
    to_id: u32,
    /// What kind of operation this edge represents.
    effect: Effect,
    /// Instruction address where this operation occurred (0 = unknown).
    inst_addr: u64,
    /// Basic block ID where this occurred (0 = unknown).
    bb_id: u32,
    /// Callee function name if this is a call edge.
    callee_name: ?[]const u8 = null,
    /// Confidence [0.0, 1.0] in this edge's classification.
    confidence: f32 = 0.7,
    /// Whether this edge crosses an FFI boundary.
    is_ffi_boundary: bool = false,
    /// Distance from nearest FFI boundary (0 = at boundary).
    ffi_boundary_distance: u8 = 255,

    pub fn init(from: u32, to: u32, eff: Effect, inst: u64) ContractEdge {
        return .{
            .from_id = from,
            .to_id = to,
            .effect = eff,
            .inst_addr = inst,
        };
    }
};

// ============================================================================
// ResourceContractGraph — The complete contract graph
// ============================================================================

/// Directed graph of all resource instances and their lifecycle operations.
/// Built once during pipeline initialization, queried by all passes.
pub const ResourceContractGraph = struct {
    allocator: std.mem.Allocator,
    /// All resource instances, keyed by their allocation pointer value.
    instances: std.AutoHashMapUnmanaged(u64, ResourceInstance),
    /// Next available instance ID.
    next_id: u32,
    /// Total number of edges across all instances.
    total_edges: u32,

    pub fn init(allocator: std.mem.Allocator) ResourceContractGraph {
        return .{
            .allocator = allocator,
            .instances = .{},
            .next_id = 1,
            .total_edges = 0,
        };
    }

    pub fn deinit(self: *ResourceContractGraph) void {
        var it = self.instances.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.instances.deinit(self.allocator);
    }

    // ========================================================================
    // Instance management
    // ========================================================================

    /// Get or create a resource instance by its allocation pointer value.
    /// Ensures deduplication: same pointer → same instance always.
    pub fn getOrCreateInstance(self: *ResourceContractGraph, ptr_val: u64) !*ResourceInstance {
        const gop = try self.instances.getOrPut(self.allocator, ptr_val);
        if (!gop.found_existing) {
            gop.value_ptr.* = ResourceInstance.init(self.allocator, self.next_id, ptr_val);
            self.next_id += 1;
        }
        return gop.value_ptr;
    }

    /// Look up an existing instance. Returns null if not found.
    pub fn getInstance(self: *const ResourceContractGraph, ptr_val: u64) ?*const ResourceInstance {
        return self.instances.get(ptr_val);
    }

    /// Get mutable reference to an existing instance.
    pub fn getInstanceMut(self: *ResourceContractGraph, ptr_val: u64) ?*ResourceInstance {
        return self.instances.getPtr(ptr_val);
    }

    /// Total number of tracked resource instances.
    pub fn instanceCount(self: *const ResourceContractGraph) usize {
        return self.instances.count();
    }

    // ========================================================================
    // Edge building (called during analysis)
    // ========================================================================

    /// Add an operation edge to a resource instance.
    pub fn addEdge(self: *ResourceContractGraph, ptr_val: u64, edge: ContractEdge) !void {
        const instance = try self.getOrCreateInstance(ptr_val);
        try instance.edges.append(edge);
        self.total_edges += 1;
    }

    /// Record an acquire (allocation) event on a resource.
    pub fn recordAcquire(self: *ResourceContractGraph, ptr_val: u64, inst_addr: u64, func_name: ?[]const u8, fam: ?FamilyId) !void {
        var instance = try self.getOrCreateInstance(ptr_val);
        instance.state = .owned;
        instance.alloc_func_name = func_name;
        instance.family = fam;
        instance.confidence = if (fam != null) 1.0 else 0.6;
        var edge = ContractEdge.init(instance.id, instance.id, .acquire, inst_addr);
        edge.callee_name = func_name;
        edge.confidence = instance.confidence;
        try instance.edges.append(edge);
        self.total_edges += 1;
    }

    /// Record a release (free/dealloc) event on a resource.
    pub fn recordRelease(self: *ResourceContractGraph, ptr_val: u64, inst_addr: u64, callee_name: ?[]const u8, release_fam: ?FamilyId) !void {
        const instance = self.getInstanceMut(ptr_val) orelse return;
        var edge = ContractEdge.init(instance.id, instance.id, .releases, inst_addr);
        edge.callee_name = callee_name;
        edge.confidence = if (release_fam != null) 1.0 else 0.7;
        try instance.edges.append(edge);
        self.total_edges += 1;
    }

    /// Record a retain (refcount increment) event.
    pub fn recordRetain(self: *ResourceContractGraph, ptr_val: u64, inst_addr: u64, callee_name: ?[]const u8) !void {
        const instance = self.getInstanceMut(ptr_val) orelse return;
        var edge = ContractEdge.init(instance.id, instance.id, .retains, inst_addr);
        edge.callee_name = callee_name;
        try instance.edges.append(edge);
        self.total_edges += 1;
    }

    /// Record a transfer/escape event.
    pub fn recordTransfer(self: *ResourceContractGraph, ptr_val: u64, inst_addr: u64, effect_kind: Effect, target_name: ?[]const u8) !void {
        const instance = self.getInstanceMut(ptr_val) orelse return;
        var edge = ContractEdge.init(instance.id, instance.id, effect_kind, inst_addr);
        edge.callee_name = target_name;
        try instance.edges.append(edge);
        self.total_edges += 1;
    }

    // ========================================================================
    // CrossLangEdge association (P7-6)
    // ========================================================================

    /// Mark all edges on an FFI path with boundary distance info.
    /// Called after the main graph is built, using danger path data.
    pub fn markFFIBoundaryEdges(
        self: *ResourceContractGraph,
        ptr_val: u64,
        is_on_ffi_path: bool,
        boundary_distance: u8,
    ) void {
        if (self.getInstanceMut(ptr_val)) |instance| {
            for (instance.edges.items) |*edge| {
                if (is_on_ffi_path) {
                    edge.is_ffi_boundary = true;
                    edge.ffi_boundary_distance = boundary_distance;
                }
            }
        }
    }

    // ========================================================================
    // Query / iteration
    // ========================================================================

    /// Iterate over all resource instances.
    pub fn iterateInstances(self: *const ResourceContractGraph, context: anytype, comptime visitor_fn: fn (context: @TypeOf(context), inst: *const ResourceInstance) bool) void {
        var it = self.instances.iterator();
        while (it.next()) |entry| {
            if (!visitor_fn(context, &entry.value_ptr.*)) break;
        }
    }

    /// Count total edges.
    pub fn edgeCount(self: *const ResourceContractGraph) u32 {
        return self.total_edges;
    }

    /// Find all instances that are in a given state.
    pub fn findByState(self: *const ResourceContractGraph, target_state: PointerContract) usize {
        var count: usize = 0;
        var it = self.instances.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.state == target_state) count += 1;
        }
        return count;
    }
};
