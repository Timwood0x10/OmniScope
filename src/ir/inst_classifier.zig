//! Instruction Classifier — classifies LLVM opcodes for fast filtering.
//!
//! Provides coarse-grained instruction classification to enable
//! early-exit optimizations in analysis passes.

const std = @import("std");
const c = @import("llvm_raw.zig").c;

/// Coarse-grained instruction classification for filtering.
pub const InstClass = enum(u8) {
    /// Memory operations (load, store, alloca, etc.)
    memory,
    /// Arithmetic operations
    arithmetic,
    /// Control flow (br, switch, ret, invoke)
    control_flow,
    /// Call/Invoke instructions
    call,
    /// Type conversions (bitcast, ptrtoint, inttoptr, trunc, etc.)
    conversion,
    /// Aggregate operations (extractvalue, insertvalue — retained for compat)
    aggregate,
    /// Pointer operations (GEP, etc.)
    pointer,
    /// Phi nodes
    phi,
    /// Select (conditional value pick)
    select,
    /// extractvalue — field projection from aggregate
    extract_value,
    /// insertvalue — field insertion into aggregate
    insert_value,
    /// freeze — poison-free wrapper
    freeze,
    /// Atomic read-modify-write
    atomic_rmw,
    /// Atomic compare-and-exchange
    cmpxchg,
    /// Memory fence / barrier
    fence,
    /// Other / unclassified
    other,

    /// Check if this instruction class is relevant for memory safety / FFI analysis.
    pub fn isRelevantForAnalysis(self: InstClass) bool {
        return switch (self) {
            .memory,
            .call,
            .conversion,
            .pointer,
            .phi,
            .select,
            .extract_value,
            .insert_value,
            .freeze,
            .atomic_rmw,
            .cmpxchg,
            .fence,
            => true,
            else => false,
        };
    }
};

/// Statistics for instruction filtering.
pub const FilterStats = struct {
    total: u64 = 0,
    relevant: u64 = 0,
    filtered: u64 = 0,

    pub fn format(
        self: *const FilterStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("FilterStats{{ total={}, relevant={}, filtered={} }}", .{
            self.total,
            self.relevant,
            self.filtered,
        });
    }
};

/// Classify an LLVM opcode into an InstClass for fast filtering.
pub fn classifyOpcode(opcode: c_uint) InstClass {
    return switch (opcode) {
        c.LLVMLoad, c.LLVMStore, c.LLVMAlloca => .memory,
        c.LLVMCall, c.LLVMInvoke => .call,
        c.LLVMBr, c.LLVMSwitch, c.LLVMRet, c.LLVMIndirectBr => .control_flow,
        c.LLVMBitCast,
        c.LLVMPtrToInt,
        c.LLVMIntToPtr,
        c.LLVMTrunc,
        c.LLVMZExt,
        c.LLVMSExt,
        c.LLVMFPTrunc,
        c.LLVMFPExt,
        c.LLVMFPToUI,
        c.LLVMFPToSI,
        c.LLVMUIToFP,
        c.LLVMSIToFP,
        => .conversion,
        c.LLVMExtractValue => .extract_value,
        c.LLVMInsertValue => .insert_value,
        c.LLVMGetElementPtr => .pointer,
        c.LLVMPHI => .phi,
        c.LLVMSelect => .select,
        c.LLVMFreeze => .freeze,
        c.LLVMAtomicRMW => .atomic_rmw,
        c.LLVMAtomicCmpXchg => .cmpxchg,
        c.LLVMFence => .fence,

        // Arithmetic
        c.LLVMAdd,
        c.LLVMSub,
        c.LLVMMul,
        c.LLVMDiv,
        c.LLVMRem,
        c.LLVMAnd,
        c.LLVMOr,
        c.LLVMXor,
        c.LLVMShl,
        c.LLVMLShr,
        c.LLVMAShr,
        => .arithmetic,

        // Floating point arithmetic
        c.LLVMFAdd,
        c.LLVMFSub,
        c.LLVMMul,
        c.LLVMFDiv,
        c.LLVMFRem,
        => .arithmetic,

        // Compare
        c.LLVMICmp, c.LLVMFCmp => .arithmetic,

        else => .other,
    };
}
