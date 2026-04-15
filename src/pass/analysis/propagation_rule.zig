//! Propagation Rules for Taint Analysis
//!
//! Defines rules for how taint propagates through different LLVM instructions.

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const TaintContext = @import("./taint_state.zig").TaintContext;
const TaintInfo = @import("./taint_state.zig").TaintInfo;
const TaintState = @import("./taint_state.zig").TaintState;
const call_graph = @import("./call_graph.zig");

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
    /// LLVM opcode this rule applies to
    op_code: llvm.LLVMOpcode,
    /// Direction of propagation
    direction: PropagationDirection,
    /// Handler function for this rule
    handler: *const fn (ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void,
};

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
pub fn handleLoad(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const ptr_operand = llvm.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_operand) == 0) return;

    const ptr_taint = ctx.getValueTaint(@intFromPtr(ptr_operand));
    if (ptr_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = @max(info.confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
            };
            try ctx.setValueTaint(@intFromPtr(inst), new_info);
        }
    }
}

/// Handle store instruction - forward propagation
pub fn handleStore(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const value_operand = llvm.LLVMGetOperand(inst, 0);
    const ptr_operand = llvm.LLVMGetOperand(inst, 1);

    if (@intFromPtr(value_operand) == 0 or @intFromPtr(ptr_operand) == 0) return;

    const value_taint = ctx.getValueTaint(@intFromPtr(value_operand));
    if (value_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = info.state,
                .source_id = info.source_id,
                .confidence = info.confidence,
            };
            try ctx.setValueTaint(@intFromPtr(ptr_operand), new_info);
        }
    }
}

/// Handle call instruction - forward propagation
pub fn handleCall(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const called_value = llvm.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_value) == 0) return;

    const called_name_ptr = llvm.LLVMGetValueName(called_value);
    const called_func_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else "";

    if (called_func_name.len > 0 and isSinkFunc(called_func_name)) {
        const new_info = TaintInfo{
            .id = next_id,
            .state = .tainted,
            .source_id = null,
            .confidence = 1.0,
        };
        try ctx.setValueTaint(@intFromPtr(inst), new_info);
        return;
    }

    const num_operands = llvm.LLVMGetNumOperands(inst);
    var has_tainted_arg = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = llvm.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@intFromPtr(operand))) |info| {
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
        try ctx.setValueTaint(@intFromPtr(inst), new_info);
    }
}

/// Handle bitcast instruction - bidirectional propagation
pub fn handleBitCast(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    _ = next_id;
    const operand = llvm.LLVMGetOperand(inst, 0);
    if (@intFromPtr(operand) == 0) return;

    const operand_taint = ctx.getValueTaint(@intFromPtr(operand));
    if (operand_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            try ctx.setValueTaint(@intFromPtr(inst), info);
        }
    }

    const result_taint = ctx.getValueTaint(@intFromPtr(inst));
    if (result_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            try ctx.setValueTaint(@intFromPtr(operand), info);
        }
    }
}

/// Handle getelementptr instruction - forward propagation
pub fn handleGEP(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const ptr_operand = llvm.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_operand) == 0) return;

    const ptr_taint = ctx.getValueTaint(@intFromPtr(ptr_operand));
    if (ptr_taint) |info| {
        if (info.state == .source or info.state == .tainted) {
            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = @max(info.confidence * 0.98, MIN_CONFIDENCE),
            };
            try ctx.setValueTaint(@intFromPtr(inst), new_info);
        }
    }
}

/// Handle arithmetic instructions (Add, Sub, Mul, etc.)
pub fn handleArithmetic(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const num_operands = llvm.LLVMGetNumOperands(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = llvm.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@intFromPtr(operand))) |info| {
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
        try ctx.setValueTaint(@intFromPtr(inst), new_info);
    }
}

/// Handle comparison instructions
pub fn handleComparison(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const num_operands = llvm.LLVMGetNumOperands(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_operands) : (i += 1) {
        const operand = llvm.LLVMGetOperand(inst, i);
        if (@intFromPtr(operand) == 0) continue;

        if (ctx.getValueTaint(@intFromPtr(operand))) |info| {
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
        try ctx.setValueTaint(@intFromPtr(inst), new_info);
    }
}

/// Handle PHI instruction
pub fn handlePhi(ctx: *TaintContext, inst: llvm.LLVMValueRef, next_id: u32) anyerror!void {
    const num_incoming = llvm.LLVMCountIncoming(inst);
    var has_tainted: bool = false;
    var max_confidence: f32 = 0.0;
    var source_id: ?u32 = null;

    var i: u32 = 0;
    while (i < num_incoming) : (i += 1) {
        const incoming_value = llvm.LLVMGetIncomingValue(inst, i);
        if (@intFromPtr(incoming_value) == 0) continue;

        if (ctx.getValueTaint(@intFromPtr(incoming_value))) |info| {
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
        try ctx.setValueTaint(@intFromPtr(inst), new_info);
    }
}

/// Built-in propagation rules
pub const BUILTIN_RULES = &[_]PropagationRule{
    .{ .op_code = .Load, .direction = .forward, .handler = handleLoad },
    .{ .op_code = .Store, .direction = .forward, .handler = handleStore },
    .{ .op_code = .Call, .direction = .forward, .handler = handleCall },
    .{ .op_code = .BitCast, .direction = .both, .handler = handleBitCast },
    .{ .op_code = .GetElementPtr, .direction = .forward, .handler = handleGEP },
    .{ .op_code = .Add, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = .Sub, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = .Mul, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = .SDiv, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = .UDiv, .direction = .forward, .handler = handleArithmetic },
    .{ .op_code = .ICmp, .direction = .forward, .handler = handleComparison },
    .{ .op_code = .FCmp, .direction = .forward, .handler = handleComparison },
    .{ .op_code = .PHI, .direction = .forward, .handler = handlePhi },
};

/// Find a rule for a given opcode
pub fn findRule(opcode: llvm.LLVMOpcode) ?PropagationRule {
    for (BUILTIN_RULES) |rule| {
        if (@intFromEnum(rule.op_code) == @intFromEnum(opcode)) {
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
        .op_code = .Load,
        .direction = .forward,
        .handler = handleLoad,
    };
    try std.testing.expectEqual(llvm.LLVMOpcode.Load, rule.op_code);
    try std.testing.expectEqual(PropagationDirection.forward, rule.direction);
}

test "BUILTIN_RULES - not empty" {
    try std.testing.expect(BUILTIN_RULES.len > 0);
}

test "BUILTIN_RULES - contains Load" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (@intFromEnum(rule.op_code) == @intFromEnum(llvm.LLVMOpcode.Load)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "BUILTIN_RULES - contains Store" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (@intFromEnum(rule.op_code) == @intFromEnum(llvm.LLVMOpcode.Store)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "BUILTIN_RULES - contains Call" {
    var found = false;
    for (BUILTIN_RULES) |rule| {
        if (@intFromEnum(rule.op_code) == @intFromEnum(llvm.LLVMOpcode.Call)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "findRule - find Load rule" {
    const rule = findRule(.Load);
    try std.testing.expect(rule != null);
    try std.testing.expectEqual(llvm.LLVMOpcode.Load, rule.?.op_code);
}

test "findRule - find Call rule" {
    const rule = findRule(.Call);
    try std.testing.expect(rule != null);
    try std.testing.expectEqual(llvm.LLVMOpcode.Call, rule.?.op_code);
}

test "findRule - returns null for unknown opcode" {
    const rule = findRule(@as(llvm.LLVMOpcode, @enumFromInt(9999)));
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
