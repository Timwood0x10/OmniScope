//! Instruction Classification System
//!
//! Provides fast classification of LLVM IR instructions into semantic categories.
//! Used by analysis passes to quickly skip irrelevant instructions.
//!
//! Performance impact: This classification can skip 30-40% of instructions
//! (arithmetic, bitwise, comparisons) that are irrelevant for memory safety / FFI analysis.

const std = @import("std");
const c = @import("llvm_raw.zig").c;

/// Semantic category of an LLVM instruction.
/// Used for quick filtering in analysis passes.
pub const InstClass = enum(u8) {
    /// Arithmetic operations (add, sub, mul, div, rem)
    /// Usually irrelevant for memory safety / FFI analysis
    arithmetic = 0,

    /// Bitwise operations (and, or, xor, shl, lshr, ashr)
    /// Usually irrelevant
    bitwise = 1,

    /// Comparison operations (icmp, fcmp)
    /// Usually irrelevant unless used in branch conditions
    comparison = 2,

    /// Memory access operations (load, store, alloca, gep)
    /// HIGHLY RELEVANT for memory safety analysis
    memory_access = 3,

    /// Function call/invoke instructions
    /// HIGHLY RELEVANT for FFI / resource analysis
    call_invoke = 4,

    /// Type conversion operations (bitcast, ptrtoint, inttoptr, trunc, zext, sext, fptrunc, fpext)
    /// Relevant for type confusion / transmute detection
    conversion = 5,

    /// Control flow operations (br, switch, ret, unreachable, indirectbr)
    /// Relevant for control flow analysis
    control_flow = 6,

    /// SSA phi nodes
    /// Usually skip (SSA-specific)
    phi_node = 7,

    /// Atomic operations (atomicrmw, cmpxchg, fence)
    /// Relevant for concurrency analysis
    atomic = 8,

    /// Exception handling (landingpad, resume, catchpad, etc.)
    /// May be relevant for exception path analysis
    exception = 9,

    /// Aggregate operations (extractvalue, insertvalue, extractelement, insertelement)
    /// Sometimes relevant
    aggregate = 10,

    /// Everything else (debug info, metadata references, etc.)
    other = 11,

    /// Quick check: should standard memory safety / FFI passes analyze this?
    pub fn isRelevantForAnalysis(self: InstClass) bool {
        return switch (self) {
            .arithmetic, .bitwise, .comparison, .phi_node => false,
            .memory_access, .call_invoke, .conversion, .control_flow, .atomic, .exception, .aggregate, .other => true,
        };
    }

    /// Check if this is a memory-related operation (load/store/gep/alloca)
    pub fn isMemoryOperation(self: InstClass) bool {
        return self == .memory_access;
    }

    /// Check if this is a call/invoke operation
    pub fn isCallOrInvoke(self: InstClass) bool {
        return self == .call_invoke;
    }

    /// Get human-readable name for logging/debugging
    pub fn name(self: InstClass) []const u8 {
        return switch (self) {
            .arithmetic => "arithmetic",
            .bitwise => "bitwise",
            .comparison => "comparison",
            .memory_access => "memory_access",
            .call_invoke => "call_invite",
            .conversion => "conversion",
            .control_flow => "control_flow",
            .phi_node => "phi_node",
            .atomic => "atomic",
            .exception => "exception",
            .aggregate => "aggregate",
            .other => "other",
        };
    }
};

/// Classify an LLVM opcode into InstClass.
/// This is a pure function (no side effects), suitable for hot paths.
pub fn classifyOpcode(opcode: c_uint) InstClass {
    return switch (opcode) {
        // Arithmetic
        c.LLVMAdd, c.LLVMSub, c.LLVMMul, c.LLVMUDiv, c.LLVMURem, c.LLVMSDiv, c.LLVMSRem, c.LLVMFAdd, c.LLVMFSub, c.LLVMFMul, c.LLVMFDiv, c.LLVMFRem => .arithmetic,

        // Bitwise
        c.LLVMAnd, c.LLVMOr, c.LLVMXor, c.LLVMShl, c.LLVMLShr, c.LLVMAShr => .bitwise,

        // Comparison
        c.LLVMICmp, c.LLVMFCmp => .comparison,

        // Memory access
        c.LLVMLoad, c.LLVMStore, c.LLVMAlloca, c.LLVMGetElementPtr, c.LLVMFence, c.LLVMAtomicRMW, c.LLVMAtomicCmpXchg => .memory_access,

        // Call/Invoke
        c.LLVMCall, c.LLVMInvoke => .call_invoke,

        // Conversion
        c.LLVMTrunc, c.LLVMZExt, c.LLVMSExt, c.LLVMFPToUI, c.LLVMFPToSI, c.LLVMUIToFP, c.LLVMSIToFP, c.LLVMFPTrunc, c.LLVMFPExt, c.LLVMPtrToInt, c.LLVMIntToPtr, c.LLVMBitCast, c.LLVMAddrSpaceCast => .conversion,

        // Control flow
        c.LLVMBr, c.LLVMSwitch, c.LLVMIndirectBr, c.LLVMRet, c.LLVMUnreachable => .control_flow,

        // Phi node
        c.LLVMPHI => .phi_node,

        // Exception handling
        c.LLVMLandingPad, c.LLVMResume, c.LLVMCatchRet, c.LLVMCatchSwitch, c.LLVMCatchPad, c.LLVMCleanupPad, c.LLVMCleanupRet => .exception,

        // Aggregate
        c.LLVMExtractValue, c.LLVMInsertValue, c.LLVMExtractElement, c.LLVMInsertElement => .aggregate,

        else => .other,
    };
}

/// Filter statistics tracker for measuring optimization effectiveness.
pub const FilterStats = struct {
    total_instructions: u64 = 0,
    skipped_irrelevant: u64 = 0,
    analyzed_relevant: u64 = 0,

    /// Record an instruction processing decision
    pub fn record(self: *FilterStats, is_relevant: bool) void {
        self.total_instructions += 1;
        if (is_relevant) {
            self.analyzed_relevant += 1;
        } else {
            self.skipped_irrelevant += 1;
        }
    }

    /// Get the skip percentage (0.0 - 100.0)
    pub fn skipPercentage(self: *FilterStats) f64 {
        if (self.total_instructions == 0) return 0.0;
        return @as(f64, @floatFromInt(self.skipped_irrelevant)) /
            @as(f64, @floatFromInt(self.total_instructions)) * 100.0;
    }

    /// Get the analyzed percentage (0.0 - 100.0)
    pub fn analyzePercentage(self: *FilterStats) f64 {
        if (self.total_instructions == 0) return 0.0;
        return @as(f64, @floatFromInt(self.analyzed_relevant)) /
            @as(f64, @floatFromInt(self.total_instructions)) * 100.0;
    }

    /// Reset statistics
    pub fn reset(self: *FilterStats) void {
        self.total_instructions = 0;
        self.skipped_irrelevant = 0;
        self.analyzed_relevant = 0;
    }

    /// Format statistics as log message
    pub fn formatLog(self: *FilterStats, pass_name: []const u8) [512]u8 {
        var buffer: [512]u8 = undefined;
        _ = std.fmt.bufPrint(&buffer,
            \\[PERF] {s} filter stats:
            \\  Total instructions: {d}
            \\  Skipped (irrelevant): {d} ({d:.1}%)
            \\  Analyzed (relevant): {d} ({d:.1}%)
        , .{
            pass_name,
            self.total_instructions,
            self.skipped_irrelevant,
            self.skipPercentage(),
            self.analyzed_relevant,
            self.analyzePercentage(),
        }) catch return buffer;
        return buffer;
    }
};

test "classifyOpcode maps opcodes correctly" {
    try std.testing.expectEqual(InstClass.arithmetic, classifyOpcode(c.LLVMAdd));
    try std.testing.expectEqual(InstClass.call_invoke, classifyOpcode(c.LLVMCall));
    try std.testing.expectEqual(InstClass.memory_access, classifyOpcode(c.LLVMLoad));
    try std.testing.expectEqual(InstClass.phi_node, classifyOpcode(c.LLVMPHI));
    try std.testing.expectEqual(InstClass.bitwise, classifyOpcode(c.LLVMAnd));
    try std.testing.expectEqual(InstClass.comparison, classifyOpcode(c.LLVMICmp));
    try std.testing.expectEqual(InstClass.conversion, classifyOpcode(c.LLVMBitCast));
    try std.testing.expectEqual(InstClass.control_flow, classifyOpcode(c.LLVMBr));
    try std.testing.expectEqual(InstClass.atomic, classifyOpcode(c.LLVMAtomicRMW));
    try std.testing.expectEqual(InstClass.exception, classifyOpcode(c.LLVMLandingPad));
    try std.testing.expectEqual(InstClass.aggregate, classifyOpcode(c.LLVMExtractValue));
}

test "isRelevantForAnalysis filters correctly" {
    try std.testing.expect(!InstClass.arithmetic.isRelevantForAnalysis());
    try std.testing.expect(!InstClass.bitwise.isRelevantForAnalysis());
    try std.testing.expect(!InstClass.comparison.isRelevantForAnalysis());
    try std.testing.expect(!InstClass.phi_node.isRelevantForAnalysis());

    try std.testing.expect(InstClass.memory_access.isRelevantForAnalysis());
    try std.testing.expect(InstClass.call_invoke.isRelevantForAnalysis());
    try std.testing.expect(InstClass.conversion.isRelevantForAnalysis());
    try std.testing.expect(InstClass.control_flow.isRelevantForAnalysis());
    try std.testing.expect(InstClass.atomic.isRelevantForAnalysis());
    try std.testing.expect(InstClass.exception.isRelevantForAnalysis());
    try std.testing.expect(InstClass.aggregate.isRelevantForAnalysis());
    try std.testing.expect(InstClass.other.isRelevantForAnalysis());
}

test "isMemoryOperation and isCallOrInvoke" {
    try std.testing.expect(InstClass.memory_access.isMemoryOperation());
    try std.testing.expect(!InstClass.call_invoke.isMemoryOperation());

    try std.testing.expect(InstClass.call_invoke.isCallOrInvoke());
    try std.testing.expect(!InstClass.memory_access.isCallOrInvoke());
}

test "FilterStats tracking" {
    var stats = FilterStats{};

    stats.record(true);
    stats.record(true);
    stats.record(false);
    stats.record(false);
    stats.record(false);

    try std.testing.expectEqual(@as(u64, 5), stats.total_instructions);
    try std.testing.expectEqual(@as(u64, 2), stats.analyzed_relevant);
    try std.testing.expectEqual(@as(u64, 3), stats.skipped_irrelevant);

    const skip_pct = stats.skipPercentage();
    try std.testing.expect(skip_pct > 59.9 and skip_pct < 60.1);

    const analyze_pct = stats.analyzePercentage();
    try std.testing.expect(analyze_pct > 39.9 and analyze_pct < 40.1);

    stats.reset();
    try std.testing.expectEqual(@as(u64, 0), stats.total_instructions);
}
