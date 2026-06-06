//! Semantic Step — Per-opcode semantic propagation
//!
//! Each LLVM opcode has exactly one classifier function.
//! All consumers call these instead of open-coding opcode checks.

const std = @import("std");
const c = @import("llvm_raw.zig").c;
const InstClass = @import("inst_classifier.zig").InstClass;

// ============================================================================
// Semantic Types
// ============================================================================

/// Origin information for an LLVM value.
pub const OriginInfo = enum(u8) {
    allocation,
    argument,
    constant,
    derived,
    unsafe_transmute,
    field_projection,
    merged,
    atomic,
    unknown,
};

/// Per-instruction ownership propagation effect.
pub const Effect = enum(u8) {
    none,
    propagate,
    unsafe_transmute,
    field_projection,
    field_insertion,
    atomic,
    barrier,
};

/// Taint flow classification for an instruction.
pub const TaintFlow = enum(u8) {
    propagate,
    merge,
    unsafe_transmute,
    none,
};

// ============================================================================
// Lookup Callback Types
// ============================================================================

pub const OriginLookup = fn (inst: c.LLVMValueRef) ?OriginInfo;
pub const OwnershipLookup = fn (inst: c.LLVMValueRef) ?Effect;
pub const TaintLookup = fn (inst: c.LLVMValueRef) ?TaintFlow;

// ============================================================================
// Merge Helpers
// ============================================================================

fn mergeOrigin(a: OriginInfo, b: OriginInfo) OriginInfo {
    if (a != .unknown) return a;
    return b;
}

fn mergeEffect(a: Effect, b: Effect) Effect {
    if (a != .none) return a;
    return b;
}

fn mergeTaint(a: TaintFlow, b: TaintFlow) TaintFlow {
    if (a == .merge or b == .merge) return .merge;
    if (a != .none) return a;
    return b;
}

// ============================================================================
// Origin Propagation
// ============================================================================

/// Propagate origin information for an instruction based on its class.
pub fn propagateOrigin(inst: c.LLVMValueRef, class: InstClass, lookup: *const OriginLookup) OriginInfo {
    return switch (class) {
        .phi => blk: {
            var result: OriginInfo = .unknown;
            const n = c.LLVMCountIncoming(inst);
            var i: c_uint = 0;
            while (i < n) : (i += 1) {
                const val = c.LLVMGetIncomingValue(inst, i);
                if (lookup(val)) |info| result = mergeOrigin(result, info);
            }
            break :blk if (result != .unknown) .merged else .unknown;
        },
        .select => blk: {
            const tv = c.LLVMGetOperand(inst, 1);
            const fv = c.LLVMGetOperand(inst, 2);
            const a = if (lookup(tv)) |v| v else .unknown;
            const b = if (lookup(fv)) |v| v else .unknown;
            break :blk mergeOrigin(a, b);
        },
        .pointer => .derived,
        .conversion => .unsafe_transmute,
        .extract_value => {
            const agg = c.LLVMGetOperand(inst, 0);
            return lookup(agg) orelse .unknown;
        },
        .insert_value => {
            const val = c.LLVMGetOperand(inst, 1);
            return lookup(val) orelse .unknown;
        },
        .freeze => {
            const src = c.LLVMGetOperand(inst, 0);
            return lookup(src) orelse .unknown;
        },
        .atomic_rmw, .cmpxchg => .atomic,
        .fence => .unknown,
        else => .unknown,
    };
}

// ============================================================================
// Ownership Propagation
// ============================================================================

/// Propagate ownership effect for an instruction based on its class.
pub fn propagateOwnership(inst: c.LLVMValueRef, class: InstClass, lookup: *const OwnershipLookup) Effect {
    return switch (class) {
        .phi => blk: {
            var result: Effect = .none;
            const n = c.LLVMCountIncoming(inst);
            var i: c_uint = 0;
            while (i < n) : (i += 1) {
                const val = c.LLVMGetIncomingValue(inst, i);
                if (lookup(val)) |eff| result = mergeEffect(result, eff);
            }
            break :blk if (result != .none) .propagate else .none;
        },
        .select => blk: {
            const tv = c.LLVMGetOperand(inst, 1);
            const fv = c.LLVMGetOperand(inst, 2);
            const a = if (lookup(tv)) |v| v else .none;
            const b = if (lookup(fv)) |v| v else .none;
            break :blk mergeEffect(a, b);
        },
        .pointer => .propagate,
        .conversion => .unsafe_transmute,
        .extract_value => .field_projection,
        .insert_value => .field_insertion,
        .freeze => .propagate,
        .atomic_rmw, .cmpxchg => .atomic,
        .fence => .barrier,
        else => .none,
    };
}

// ============================================================================
// Taint Propagation
// ============================================================================

/// Propagate taint flow for an instruction based on its class.
pub fn propagateTaint(inst: c.LLVMValueRef, class: InstClass, lookup: *const TaintLookup) TaintFlow {
    return switch (class) {
        .phi => blk: {
            var result: TaintFlow = .none;
            const n = c.LLVMCountIncoming(inst);
            var i: c_uint = 0;
            while (i < n) : (i += 1) {
                const val = c.LLVMGetIncomingValue(inst, i);
                if (lookup(val)) |tf| result = mergeTaint(result, tf);
            }
            break :blk result;
        },
        .select => blk: {
            const tv = c.LLVMGetOperand(inst, 1);
            const fv = c.LLVMGetOperand(inst, 2);
            const a = if (lookup(tv)) |v| v else .none;
            const b = if (lookup(fv)) |v| v else .none;
            break :blk mergeTaint(a, b);
        },
        .pointer => .propagate,
        .conversion => .unsafe_transmute,
        .extract_value, .insert_value => .propagate,
        .freeze => .propagate,
        .atomic_rmw, .cmpxchg => .propagate,
        .fence => .none,
        else => .none,
    };
}
