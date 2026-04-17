//! Propagation Rules for Taint Analysis
//!
//! Defines rules for how taint propagates through different LLVM instructions.
//! Uses semantic classification instead of per-opcode rules.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const TaintContext = @import("./taint_state.zig").TaintContext;
const TaintInfo = @import("./taint_state.zig").TaintInfo;
const TaintState = @import("./taint_state.zig").TaintState;
const call_graph = @import("./call_graph.zig");

/// Opcode classification based on semantic behavior for taint propagation
pub const OpcodeClass = enum {
    /// Control flow instructions: br, switch, ret, unreachable
    /// These don't produce taintable values
    control_flow,
    /// Cast/passthrough instructions: trunc, zext, bitcast, ptrtoint
    /// Taint passes through from operand to result
    cast,
    /// Arithmetic instructions: add, sub, mul, xor, etc.
    /// Taint if any operand is tainted
    arithmetic,
    /// Memory operations: load, store
    /// Load: tainted if pointer is tainted
    /// Store: taints the memory location
    memory,
    /// Call/invoke instructions
    /// Special handling for FFI and function semantics
    call,
    /// Aggregate operations: phi, select, extractvalue, insertvalue
    /// Field-level or conditional propagation
    aggregate,
    /// Instructions that don't affect taint propagation
    noop,
};

/// Direction of taint propagation
pub const PropagationDirection = enum {
    /// Taint flows from operands to result
    forward,
    /// Taint flows from result to operands
    backward,
    /// Taint flows in both directions
    both,
};

/// Taint propagation rule for a specific opcode
pub const PropagationRule = struct {
    /// LLVM opcode number (c_uint) - use LLVM opcode constants like c.LLVMLoad
    /// Note: LLVM C API defines these as integer constants, not enum variants
    op_code: c_uint,
    /// Direction of propagation
    direction: PropagationDirection,
    /// Handler function for this rule
    handler: *const fn (ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void,
};

/// Get the semantic class for an opcode
pub fn classifyOpcode(opcode: c_uint) OpcodeClass {
    return switch (opcode) {
        // Control flow - no propagation
        c.LLVMBr,
        c.LLVMSwitch,
        c.LLVMRet,
        c.LLVMUnreachable,
        c.LLVMInvoke,
        c.LLVMResume,
        => .control_flow,

        // Cast/passthrough - taint passes through
        c.LLVMTrunc,
        c.LLVMZExt,
        c.LLVMSExt,
        c.LLVMBitCast,
        c.LLVMPtrToInt,
        c.LLVMIntToPtr,
        c.LLVMFPTrunc,
        c.LLVMFPExt,
        c.LLVMFPToUI,
        c.LLVMFPToSI,
        c.LLVMUIToFP,
        c.LLVMSIToFP,
        c.LLVMAddrSpaceCast,
        => .cast,

        // Arithmetic - taint if operand tainted
        c.LLVMAdd,
        c.LLVMFAdd,
        c.LLVMSub,
        c.LLVMFSub,
        c.LLVMMul,
        c.LLVMFMul,
        c.LLVMUDiv,
        c.LLVMSDiv,
        c.LLVMFDiv,
        c.LLVMURem,
        c.LLVMSRem,
        c.LLVMFRem,
        c.LLVMShl,
        c.LLVMLShr,
        c.LLVMAShr,
        c.LLVMAnd,
        c.LLVMOr,
        c.LLVMXor,
        => .arithmetic,

        // Memory operations
        c.LLVMLoad => .memory,
        c.LLVMStore => .memory,

        // Calls
        c.LLVMCall,
        c.LLVMCallBr,
        => .call,

        // Aggregate operations
        c.LLVMPHI,
        c.LLVMSelect,
        c.LLVMExtractValue,
        c.LLVMInsertValue,
        c.LLVMExtractElement,
        c.LLVMInsertElement,
        c.LLVMShuffleVector,
        => .aggregate,

        // Noop instructions
        c.LLVMAlloca,
        c.LLVMVAArg,
        c.LLVMFence,
        c.LLVMAtomicCmpXchg,
        c.LLVMAtomicRMW,
        c.LLVMLandingPad,
        c.LLVMFreeze,
        c.LLVMCatchRet,
        c.LLVMCatchPad,
        c.LLVMCatchSwitch,
        => .noop,

        else => .noop,
    };
}

/// Handle an instruction based on its semantic class
pub fn handleByClass(ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) anyerror!void {
    const op_class = classifyOpcode(opcode);
    switch (op_class) {
        .noop, .control_flow => {},
        .cast => try handleCast(ctx, inst, next_id),
        .arithmetic => try handleArithmetic(ctx, inst, next_id),
        .memory => try handleMemoryOp(ctx, inst, opcode, next_id),
        .call => try handleCall(ctx, inst, next_id),
        .aggregate => try handleAggregate(ctx, inst, opcode, next_id),
    }
}

/// Handle cast/passthrough instructions
fn handleCast(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    _ = next_id;
    const operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(operand) == 0) return;

    if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
        if (info.state == .source or info.state == .tainted) {
            try ctx.setValueTaint(@truncate(@intFromPtr(inst)), info);
        }
    }
}

/// Handle memory operations (load/store)
fn handleMemoryOp(ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) anyerror!void {
    switch (opcode) {
        c.LLVMLoad => {
            const ptr_operand = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(ptr_operand) == 0) return;

            const ptr_taint = ctx.getValueTaint(@truncate(@intFromPtr(ptr_operand)));
            if (ptr_taint) |info| {
                if (info.state == .source or info.state == .tainted) {
                    const new_info = TaintInfo{
                        .id = next_id,
                        .state = .tainted,
                        .source_id = info.source_id,
                        .confidence = @max(info.confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
                    };
                    try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
                }
            }
        },
        c.LLVMStore => {
            const value_operand = c.LLVMGetOperand(inst, 0);
            const ptr_operand = c.LLVMGetOperand(inst, 1);

            if (@intFromPtr(value_operand) == 0 or @intFromPtr(ptr_operand) == 0) return;

            const value_taint = ctx.getValueTaint(@truncate(@intFromPtr(value_operand)));
            if (value_taint) |info| {
                if (info.state == .source or info.state == .tainted) {
                    const new_info = TaintInfo{
                        .id = next_id,
                        .state = info.state,
                        .source_id = info.source_id,
                        .confidence = info.confidence,
                    };
                    try ctx.setValueTaint(@truncate(@intFromPtr(ptr_operand)), new_info);
                }
            }
        },
        else => {},
    }
}

/// Handle aggregate operations (phi, select, etc.)
fn handleAggregate(ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) anyerror!void {
    switch (opcode) {
        c.LLVMSelect => {
            const true_value = c.LLVMGetOperand(inst, 1);
            const false_value = c.LLVMGetOperand(inst, 2);

            var source_id: ?u32 = null;
            var max_confidence: f32 = 0.0;

            if (@intFromPtr(true_value) != 0) {
                if (ctx.getValueTaint(@truncate(@intFromPtr(true_value)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        source_id = info.source_id;
                        max_confidence = info.confidence;
                    }
                }
            }

            if (@intFromPtr(false_value) != 0) {
                if (ctx.getValueTaint(@truncate(@intFromPtr(false_value)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        if (info.confidence > max_confidence) {
                            source_id = info.source_id;
                            max_confidence = info.confidence;
                        }
                    }
                }
            }

            if (source_id != null) {
                const new_info = TaintInfo{
                    .id = next_id,
                    .state = .tainted,
                    .source_id = source_id,
                    .confidence = max_confidence,
                };
                try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
            }
        },
        c.LLVMPHI => {
            const num_incoming = c.LLVMCountIncoming(inst);
            var has_tainted = false;
            var max_confidence: f32 = 0.0;
            var source_id: ?u32 = null;

            var i: u32 = 0;
            while (i < num_incoming) : (i += 1) {
                const incoming_value = c.LLVMGetIncomingValue(inst, i);
                if (@intFromPtr(incoming_value) == 0) continue;

                if (ctx.getValueTaint(@truncate(@intFromPtr(incoming_value)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        has_tainted = true;
                        if (info.confidence > max_confidence) {
                            max_confidence = info.confidence;
                            source_id = info.source_id;
                        }
                    }
                }
            }

            if (has_tainted) {
                const new_info = TaintInfo{
                    .id = next_id,
                    .state = .tainted,
                    .source_id = source_id,
                    .confidence = @max(max_confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
                };
                try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
            }
        },
        else => {
            const operand = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(operand) == 0) return;

            if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
                if (info.state == .source or info.state == .tainted) {
                    try ctx.setValueTaint(@truncate(@intFromPtr(inst)), info);
                }
            }
        },
    }
}

/// Confidence decay factor for propagation
pub const CONFIDENCE_DECAY: f32 = 0.95;

/// Minimum confidence threshold
pub const MIN_CONFIDENCE: f32 = 0.1;

/// Sink patterns for dangerous function detection
const SINK_PATTERNS = &[_][]const u8{
    "system",
    "exec",
    "popen",
    "sprintf",
    "snprintf",
    "strcpy",
    "strncpy",
};

fn isSinkFunc(func_name: []const u8) bool {
    for (SINK_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Handle load instruction - forward propagation
pub fn handleLoad(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const ptr_operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_operand) == 0) return;

    const ptr_taint = ctx.getValueTaint(@truncate(@intFromPtr(ptr_operand)));
    if (ptr_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = @max(info.confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
            };
            try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
        }
    }
}

/// Handle store instruction - forward propagation
pub fn handleStore(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const value_operand = c.LLVMGetOperand(inst, 0);
    const ptr_operand = c.LLVMGetOperand(inst, 1);

    if (@intFromPtr(value_operand) == 0 or @intFromPtr(ptr_operand) == 0) return;

    const value_taint = ctx.getValueTaint(@truncate(@intFromPtr(value_operand)));
    if (value_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = info.state,
                .source_id = info.source_id,
                .confidence = info.confidence,
            };
            try ctx.setValueTaint(@truncate(@intFromPtr(ptr_operand)), new_info);
        }
    }
}

/// Handle call instruction - forward propagation
pub fn handleCall(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const called_value = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_value) == 0) return;

    const called_name_ptr = c.LLVMGetValueName(called_value);
    const called_func_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else "";

    if (called_func_name.len > 0 and isSinkFunc(called_func_name)) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = null,
            .confidence = 1.0,
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
        return;
    }

    const num_operands = c.LLVMGetNumOperands(inst);
    var has_tainted_arg = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                has_tainted_arg = true;
                if (info.confidence > max_confidence) {
                    max_confidence = info.confidence;
                    source_id = info.source_id;
                }
            }
        }
    }

    if (has_tainted_arg) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = source_id,
            .confidence = @max(max_confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// Handle bitcast instruction - bidirectional propagation
pub fn handleBitCast(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    _ = next_id;
    const operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(operand) == 0) return;

    const operand_taint = ctx.getValueTaint(@truncate(@intFromPtr(operand)));
    if (operand_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            try ctx.setValueTaint(@truncate(@intFromPtr(inst)), info);
        }
    }

    const result_taint = ctx.getValueTaint(@truncate(@intFromPtr(inst)));
    if (result_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            try ctx.setValueTaint(@truncate(@intFromPtr(operand)), info);
        }
    }
}

/// Handle getelementptr instruction - forward propagation
pub fn handleGEP(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const ptr_operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_operand) == 0) return;

    const ptr_taint = ctx.getValueTaint(@truncate(@intFromPtr(ptr_operand)));
    if (ptr_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = @max(info.confidence * 0.98, MIN_CONFIDENCE),
            };
            try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
        }
    }
}

/// Handle arithmetic instructions (Add, Sub, Mul, etc.)
pub fn handleArithmetic(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const num_operands = c.LLVMGetNumOperands(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                has_tainted = true;
                if (info.confidence > max_confidence) {
                    max_confidence = info.confidence;
                    source_id = info.source_id;
                }
            }
        }
    }

    if (has_tainted) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = source_id,
            .confidence = @max(max_confidence * 0.9, MIN_CONFIDENCE),
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// Handle comparison instructions
pub fn handleComparison(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const num_operands = c.LLVMGetNumOperands(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                has_tainted = true;
                if (info.confidence > max_confidence) {
                    max_confidence = info.confidence;
                    source_id = info.source_id;
                }
            }
        }
    }

    if (has_tainted) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = source_id,
            .confidence = @max(max_confidence * 0.85, MIN_CONFIDENCE),
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// Handle conversion and passthrough instructions (Trunc, ZExt, SExt, PtrToInt, etc.)
/// These instructions propagate taint from their operand to their result
pub fn handlePassthrough(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(operand) == 0) return;

    if (ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
        const new_info = TaintInfo{
            .id = next_id,
            .state = info.state,
            .source_id = info.source_id,
            .confidence = info.confidence,
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// No-op handler for instructions that don't produce taintable values
/// (terminators, allocas, etc.)
pub fn handleNoop(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    _ = ctx;
    _ = inst;
    _ = next_id;
}

/// Handle Select instruction - taint flows from the selected operand
pub fn handleSelect(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const true_value = c.LLVMGetOperand(inst, 1);
    const false_value = c.LLVMGetOperand(inst, 2);

    var source_id: ?u32 = null;
    var max_confidence: f32 = 0.0;

    if (@intFromPtr(true_value) != 0) {
        if (ctx.getValueTaint(@truncate(@intFromPtr(true_value)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                source_id = info.source_id;
                max_confidence = info.confidence;
            }
        }
    }

    if (@intFromPtr(false_value) != 0) {
        if (ctx.getValueTaint(@truncate(@intFromPtr(false_value)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                if (info.confidence > max_confidence) {
                    source_id = info.source_id;
                    max_confidence = info.confidence;
                }
            }
        }
    }

    if (source_id != null) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = source_id,
            .confidence = max_confidence,
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// Handle PHI instruction
pub fn handlePhi(ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) anyerror!void {
    const num_incoming = c.LLVMCountIncoming(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_incoming) : (i += 1) {
        const incoming_value = c.LLVMGetIncomingValue(inst, i);
        if (@intFromPtr(incoming_value) == 0) continue;

        if (ctx.getValueTaint(@truncate(@intFromPtr(incoming_value)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                has_tainted = true;
                if (info.confidence > max_confidence) {
                    max_confidence = info.confidence;
                    source_id = info.source_id;
                }
            }
        }
    }

    if (has_tainted) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = source_id,
            .confidence = @max(max_confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
        };
        try ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
    }
}

/// Built-in propagation rules
pub const BUILTIN_RULES = &[_]PropagationRule{
    .{ .op_code = c.LLVMLoad, .direction = .forward, .handler = handleLoad },
    .{ .op_code = c.LLVMStore, .direction = .forward, .handler = handleStore },
    .{ .op_code = c.LLVMCall, .direction = .forward, .handler = handleCall },
    .{ .op_code = c.LLVMBitCast, .direction = .both, .handler = handleBitCast },
    .{ .op_code = c.LLVMGetElementPtr, .direction = .forward, .handler = handleGEP },
    .{ .op_code = c.LLVMAdd, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = c.LLVMSub, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = c.LLVMMul, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = c.LLVMSDiv, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = c.LLVMUDiv, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = c.LLVMICmp, .direction = .forward, .handler = handleComparison },
    .{ .op_code = c.LLVMFCmp, .direction = .forward, .handler = handleComparison },
    .{ .op_code = c.LLVMSelect, .direction = .forward, .handler = handleSelect },
    .{ .op_code = c.LLVMTrunc, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMZExt, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMSExt, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMPtrToInt, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMIntToPtr, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMFPTrunc, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMFPExt, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMFPToUI, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMFPToSI, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMUIToFP, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMSIToFP, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMExtractValue, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMInsertValue, .direction = .forward, .handler = handlePassthrough },
    .{ .op_code = c.LLVMLandingPad, .direction = .forward, .handler = handlePassthrough },
};

/// Find a rule for a given opcode
pub fn findRule(opcode: c_uint) ?PropagationRule {
    for (BUILTIN_RULES) |rule| {
        if (rule.op_code == opcode) {
            return rule;
        }
    }
    return null;
}

test "PropagationDirection - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PropagationDirection.forward));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PropagationDirection.backward));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(PropagationDirection.both));
}

test "PropagationRule - structure" {
    const rule = PropagationRule{
        .op_code = c.LLVMLoad,
        .direction = .forward,
        .handler = handleLoad,
    };
    try std.testing.expectEqual(c.LLVMLoad, rule.op_code);
    try std.testing.expectEqual(PropagationDirection.forward, rule.direction);
}

test "BUILTIN_RULES - not empty" {
    try std.testing.expect(BUILTIN_RULES.len > 0);
}

test "BUILTIN_RULES - contains Load" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (rule.op_code == c.LLVMLoad) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "BUILTIN_RULES - contains Store" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (rule.op_code == c.LLVMStore) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "BUILTIN_RULES - contains Call" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (rule.op_code == c.LLVMCall) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "findRule - find Load rule" {
    const rule = findRule(c.LLVMLoad);
    try std.testing.expect(rule != null);
    try std.testing.expectEqual(c.LLVMLoad, rule.?.op_code);
}

test "findRule - find Call rule" {
    const rule = findRule(c.LLVMCall);
    try std.testing.expect(rule != null);
    try std.testing.expectEqual(c.LLVMCall, rule.?.op_code);
}

test "findRule - returns null for unknown opcode" {
    const rule = findRule(9999);
    try std.testing.expect(rule == null);
}

test "CONFIDENCE_DECAY - value" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), CONFIDENCE_DECAY, 0.001);
}

test "MIN_CONFIDENCE - value" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), MIN_CONFIDENCE, 0.001);
}

test "BUILTIN_RULES - all have handlers" {
    for (BUILTIN_RULES) |rule| {
        _ = rule.handler;
    }
}

test "BUILTIN_RULES - all have valid opcodes" {
    for (BUILTIN_RULES) |rule| {
        const opcode_val = @intFromEnum(rule.op_code);
        try std.testing.expect(opcode_val >= 0);
    }
}

test "BUILTIN_RULES - directions are valid" {
    for (BUILTIN_RULES) |rule| {
        const dir = @intFromEnum(rule.direction);
        try std.testing.expect(dir >= 0 and dir <= 2);
    }
}
