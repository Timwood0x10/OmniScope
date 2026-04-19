//! Pointer Flow Analysis Pass
//!
//! Simplified taint propagation focused on pointer flow tracking.
//! This pass tracks how pointers flow through the program, enabling
//! ownership and lifetime analysis.
//!
//! Key differences from generic taint analysis:
//! - Only tracks pointer values (not all data)
//! - Uses allocation sites as sources
//! - Tracks ownership transfer across FFI boundaries
//!
//! v0.3 Enhancements:
//! - Sanitizer function recognition to reduce false positives
//! - Dynamic confidence adjustment based on function semantics

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const TaintContext = @import("./taint_state.zig").TaintContext;
const FactStore = @import("../../fact/store.zig").FactStore;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;
const TaintInfo = @import("./taint_state.zig").TaintInfo;
const TaintState = @import("./taint_state.zig").TaintState;
const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const SanitizerRegistry = @import("../../registry/sanitizer_registry.zig").SanitizerRegistry;
const PathManager = @import("../../dataflow/path_condition.zig").PathManager;
const PathCondition = @import("../../dataflow/path_condition.zig").PathCondition;

/// Re-exports SOURCE_FUNCTIONS from call_graph module.
pub const SOURCE_FUNCTIONS = call_graph.SOURCE_FUNCTIONS;

/// Error type for pointer flow operations.
pub const TaintError = error{
    OutOfMemory,
    InvalidIR,
    PropagationFailed,
};

/// Confidence decay factor for propagation
const CONFIDENCE_DECAY: f32 = 0.95;

/// Minimum confidence threshold
const MIN_CONFIDENCE: f32 = 0.1;

/// GEP depth confidence reduction factor per index level
const GEP_DEPTH_CONFIDENCE_FACTOR: f32 = 0.1;

/// Minimum confidence factor for GEP depth-based reduction
const MIN_GEP_DEPTH_CONFIDENCE: f32 = 0.5;

/// Opcode classification for pointer flow
const OpcodeClass = enum {
    control_flow,
    cast,
    arithmetic,
    memory,
    call,
    aggregate,
    noop,
};

/// Pointer flow analysis pass.
pub const TaintPropagationPass = struct {
    pub const name = "pointer-flow";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) TaintError!void {
        if (ctx.module == null) return;

        var taint_ctx = TaintContext.init(ctx.allocator);
        defer taint_ctx.deinit();

        var sanitizer_registry = SanitizerRegistry.init(ctx.allocator) catch {
            diag.warn("PointerFlow: Failed to init sanitizer registry", .{});
            return;
        };
        defer sanitizer_registry.deinit();

        try markSources(ctx, &taint_ctx, diag);
        try propagatePointerFlow(ctx, &taint_ctx, &sanitizer_registry, diag);
        try storeResults(ctx, &taint_ctx, diag);
    }

    fn markSources(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;
        var source_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

            if (isSourceFunction(func_name)) {
                try markFunctionParametersTainted(ctx, taint_ctx, func, diag);
                source_count += 1;
            }
        }

        if (source_count > 0) {
            diag.info("PointerFlow: Found {} source functions", .{source_count});
        }
    }

    fn propagatePointerFlow(ctx: *PassContext, taint_ctx: *TaintContext, sanitizer_registry: *SanitizerRegistry, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;
        var inst_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            try propagateThroughFunction(ctx, taint_ctx, sanitizer_registry, func, &inst_count, diag);
        }

        const tainted_count = taint_ctx.taintedCount();
        if (tainted_count > 0) {
            diag.info("PointerFlow: {} values tracked after propagation", .{tainted_count});
        }
    }

    fn propagateThroughFunction(ctx: *PassContext, taint_ctx: *TaintContext, sanitizer_registry: *SanitizerRegistry, func: c.LLVMValueRef, inst_count: *u32, diag: *DiagnosticWriter) !void {
        var path_manager = PathManager.init(ctx.allocator) catch {
            diag.warn("PointerFlow: PathManager init failed, continuing without path-sensitive analysis", .{});
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    try handleInstruction(ctx, taint_ctx, sanitizer_registry, null, inst, inst_count);
                }
            }
            return;
        };
        defer path_manager.deinit();

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try handleInstruction(ctx, taint_ctx, sanitizer_registry, &path_manager, inst, inst_count);
            }
        }
    }

    fn handleInstruction(ctx: *PassContext, taint_ctx: *TaintContext, sanitizer_registry: *SanitizerRegistry, path_manager: ?*PathManager, inst: c.LLVMValueRef, inst_count: *u32) !void {
        inst_count.* += 1;
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const op_class = classifyOpcode(opcode);

        switch (op_class) {
            .control_flow => {
                if (path_manager) |pm| {
                    try handleControlFlow(taint_ctx, pm, inst, opcode, ctx.getNextId());
                }
            },
            .noop => {},
            .cast => try handleCast(taint_ctx, inst, ctx.getNextId()),
            .arithmetic => try handleArithmetic(taint_ctx, inst, ctx.getNextId()),
            .memory => try handleMemoryOp(taint_ctx, inst, opcode, ctx.getNextId()),
            .call => try handleCall(taint_ctx, sanitizer_registry, path_manager, inst, ctx.getNextId()),
            .aggregate => try handleAggregate(taint_ctx, inst, opcode, ctx.getNextId()),
        }
    }

    fn handleControlFlow(taint_ctx: *TaintContext, path_manager: *PathManager, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) !void {
        _ = taint_ctx;
        _ = next_id;

        if (opcode == c.LLVMBr) {
            const is_conditional = c.LLVMIsConditionalBr(inst);
            if (is_conditional != 0) {
                const condition = c.LLVMGetCondition(inst);
                if (@intFromPtr(condition) != 0) {
                    const condition_opcode = c.LLVMGetInstructionOpcode(condition);
                    if (condition_opcode == c.LLVMICmp) {
                        const predicate = c.LLVMGetICmpPredicate(condition);
                        const lhs = c.LLVMGetOperand(condition, 0);
                        const rhs = c.LLVMGetOperand(condition, 1);

                        if (@intFromPtr(lhs) != 0 and @intFromPtr(rhs) != 0) {
                            const is_null_check = c.LLVMIsNull(rhs) != 0 or c.LLVMIsNull(lhs) != 0;

                            if (is_null_check) {
                                const ptr_value = if (c.LLVMIsNull(rhs) != 0) lhs else rhs;
                                const ptr_id: u32 = @truncate(@intFromPtr(ptr_value));

                                const is_not_null = predicate == c.LLVMIntNE;
                                const cond = PathCondition.nullCheck(ptr_id, is_not_null);
                                try path_manager.addCondition(cond);
                            }
                        }
                    }
                }
            }
        }
    }

    fn classifyOpcode(opcode: c_uint) OpcodeClass {
        return switch (opcode) {
            c.LLVMBr, c.LLVMSwitch, c.LLVMRet, c.LLVMUnreachable, c.LLVMInvoke, c.LLVMResume => .control_flow,
            c.LLVMTrunc, c.LLVMZExt, c.LLVMSExt, c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr, c.LLVMFPTrunc, c.LLVMFPExt, c.LLVMFPToUI, c.LLVMFPToSI, c.LLVMUIToFP, c.LLVMSIToFP, c.LLVMAddrSpaceCast => .cast,
            c.LLVMAdd, c.LLVMFAdd, c.LLVMSub, c.LLVMFSub, c.LLVMMul, c.LLVMFMul, c.LLVMUDiv, c.LLVMSDiv, c.LLVMFDiv, c.LLVMURem, c.LLVMSRem, c.LLVMFRem, c.LLVMShl, c.LLVMLShr, c.LLVMAShr, c.LLVMAnd, c.LLVMOr, c.LLVMXor => .arithmetic,
            c.LLVMLoad, c.LLVMStore => .memory,
            c.LLVMCall, c.LLVMCallBr => .call,
            c.LLVMPHI, c.LLVMSelect, c.LLVMExtractValue, c.LLVMInsertValue, c.LLVMExtractElement, c.LLVMInsertElement, c.LLVMShuffleVector, c.LLVMGetElementPtr => .aggregate,
            else => .noop,
        };
    }

    fn handleCast(taint_ctx: *TaintContext, inst: c.LLVMValueRef, _: u32) !void {
        const operand = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(operand) == 0) return;

        if (taint_ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
            if (info.state == .source or info.state == .tainted) {
                try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), info);
            }
        }
    }

    fn handleArithmetic(taint_ctx: *TaintContext, inst: c.LLVMValueRef, next_id: u32) !void {
        const num_operands = c.LLVMGetNumOperands(inst);
        var has_tainted: bool = false;
        var max_confidence: f32 = 0.0;
        var source_id: ?u32 = null;

        var i: u32 = 0;
        while (i < num_operands) : (i += 1) {
            const operand = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(operand) == 0) continue;

            if (taint_ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
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
            try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
        }
    }

    fn handleMemoryOp(taint_ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) !void {
        switch (opcode) {
            c.LLVMLoad => {
                const ptr_operand = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(ptr_operand) == 0) return;

                if (taint_ctx.getValueTaint(@truncate(@intFromPtr(ptr_operand)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        const new_info = TaintInfo{
                            .id = next_id,
                            .state = .tainted,
                            .source_id = info.source_id,
                            .confidence = @max(info.confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
                        };
                        try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
                    }
                }
            },
            c.LLVMStore => {
                const value_operand = c.LLVMGetOperand(inst, 0);
                const ptr_operand = c.LLVMGetOperand(inst, 1);

                if (@intFromPtr(value_operand) == 0 or @intFromPtr(ptr_operand) == 0) return;

                if (taint_ctx.getValueTaint(@truncate(@intFromPtr(value_operand)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        try taint_ctx.setValueTaint(@truncate(@intFromPtr(ptr_operand)), info);
                    }
                }
            },
            else => {},
        }
    }

    fn handleCall(taint_ctx: *TaintContext, sanitizer_registry: *SanitizerRegistry, path_manager: ?*PathManager, inst: c.LLVMValueRef, next_id: u32) !void {
        const called_value = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_value) == 0) return;

        const called_name_ptr = c.LLVMGetValueName(called_value);
        const called_func_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else "";

        // Check if this is a sanitizer function
        if (called_func_name.len > 0 and sanitizer_registry.isSanitizer(called_func_name)) {
            const sanitizer_factor = sanitizer_registry.getConfidenceFactor(called_func_name);

            const num_operands = c.LLVMGetNumOperands(inst);
            var has_tainted_arg = false;
            var max_confidence: f32 = 0.0;
            var source_id: ?u32 = null;

            var i: u32 = 0;
            while (i < num_operands) : (i += 1) {
                const operand = c.LLVMGetOperand(inst, i);
                if (@intFromPtr(operand) == 0) continue;

                if (taint_ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
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
                const new_confidence = max_confidence * sanitizer_factor;
                if (new_confidence >= MIN_CONFIDENCE) {
                    const new_info = TaintInfo{
                        .id = next_id,
                        .state = .tainted,
                        .source_id = source_id,
                        .confidence = new_confidence,
                    };
                    try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
                }
            }
            return;
        }

        // Check if this is a dangerous sink
        if (called_func_name.len > 0 and SemanticRegistry.isDangerousSink(called_func_name)) {
            var confidence: f32 = 1.0;

            // Reduce confidence if path conditions indicate safety
            if (path_manager) |pm| {
                const num_operands = c.LLVMGetNumOperands(inst);
                var i: u32 = 0;
                while (i < num_operands) : (i += 1) {
                    const operand = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(operand) == 0) continue;
                    const operand_id: u32 = @truncate(@intFromPtr(operand));

                    // If we know the pointer is not null on this path, reduce risk
                    if (pm.isPtrNonNull(operand_id)) {
                        confidence *= 0.7;
                    }
                }
            }

            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = null,
                .confidence = confidence,
            };
            try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
            return;
        }

        // Propagate taint from arguments
        const num_operands = c.LLVMGetNumOperands(inst);
        var has_tainted_arg = false;
        var max_confidence: f32 = 0.0;
        var source_id: ?u32 = null;

        var i: u32 = 0;
        while (i < num_operands) : (i += 1) {
            const operand = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(operand) == 0) continue;

            if (taint_ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
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
            // Use semantic-aware confidence decay
            const decay_factor = if (called_func_name.len > 0)
                SemanticRegistry.getConfidenceDecay(called_func_name)
            else
                CONFIDENCE_DECAY;

            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = source_id,
                .confidence = @max(max_confidence * decay_factor, MIN_CONFIDENCE),
            };
            try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
        }
    }

    fn handleAggregate(taint_ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) !void {
        switch (opcode) {
            c.LLVMSelect => {
                const true_value = c.LLVMGetOperand(inst, 1);
                const false_value = c.LLVMGetOperand(inst, 2);

                var source_id: ?u32 = null;
                var max_confidence: f32 = 0.0;

                if (@intFromPtr(true_value) != 0) {
                    if (taint_ctx.getValueTaint(@truncate(@intFromPtr(true_value)))) |info| {
                        if (info.state == .source or info.state == .tainted) {
                            source_id = info.source_id;
                            max_confidence = info.confidence;
                        }
                    }
                }

                if (@intFromPtr(false_value) != 0) {
                    if (taint_ctx.getValueTaint(@truncate(@intFromPtr(false_value)))) |info| {
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
                    try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
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

                    if (taint_ctx.getValueTaint(@truncate(@intFromPtr(incoming_value)))) |info| {
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
                    try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
                }
            },
            else => {
                const operand = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(operand) == 0) return;

                if (taint_ctx.getValueTaint(@truncate(@intFromPtr(operand)))) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), info);
                    }
                }
            },
            c.LLVMGetElementPtr => {
                const base_ptr = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(base_ptr) != 0) {
                    if (taint_ctx.getValueTaint(@truncate(@intFromPtr(base_ptr)))) |info| {
                        if (info.state == .source or info.state == .tainted) {
                            const num_indices = c.LLVMGetNumIndices(inst);
                            const depth_factor: f32 = 1.0 - (@as(f32, @floatFromInt(num_indices)) * GEP_DEPTH_CONFIDENCE_FACTOR);
                            const new_confidence = info.confidence * @max(depth_factor, MIN_GEP_DEPTH_CONFIDENCE);

                            const new_info = TaintInfo{
                                .id = next_id,
                                .state = .tainted,
                                .source_id = info.source_id,
                                .confidence = new_confidence,
                            };
                            try taint_ctx.setValueTaint(@truncate(@intFromPtr(inst)), new_info);
                        }
                    }
                }
            },
        }
    }

    fn storeResults(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        var iter = taint_ctx.value_taint.iterator();
        var count: u32 = 0;

        while (iter.next()) |entry| {
            const value_id = entry.key_ptr.*;
            const taint_info = entry.value_ptr.*;

            if (taint_info.state != .none) {
                try ctx.fact_store.insert(
                    .taint,
                    value_id,
                    @intFromEnum(taint_info.state),
                    taint_info.id,
                );
                count += 1;
            }
        }

        if (count > 0) {
            diag.info("PointerFlow: Stored {} pointer flow facts", .{count});
        }
    }

    fn isSourceFunction(func_name: []const u8) bool {
        return isSource(func_name);
    }

    fn markFunctionParametersTainted(ctx: *PassContext, taint_ctx: *TaintContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return;
        const func_name = std.mem.span(func_name_ptr);

        var arg = c.LLVMGetFirstParam(func);
        var param_idx: u32 = 0;

        while (@intFromPtr(arg) != 0) : (arg = c.LLVMGetNextParam(arg)) {
            const info = TaintInfo{
                .id = ctx.getNextId(),
                .state = .source,
                .source_id = @truncate(@intFromPtr(func)),
                .confidence = 1.0,
            };
            try taint_ctx.setValueTaint(@truncate(@intFromPtr(arg)), info);
            param_idx += 1;
        }

        if (param_idx > 0) {
            diag.info("PointerFlow: Marked {} parameters of '{s}' as sources", .{ param_idx, func_name });
        }
    }
};

/// Helper function to check if a name matches source patterns
pub fn isSource(name: []const u8) bool {
    for (SOURCE_FUNCTIONS) |source| {
        if (std.mem.eql(u8, name, source)) {
            return true;
        }
    }
    return false;
}

/// Helper function to check if a name matches sink patterns
pub fn isSink(name: []const u8) bool {
    return SemanticRegistry.isDangerousSink(name);
}

test "SOURCE_FUNCTIONS - contains main" {
    var found_main = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found_main = true;
            break;
        }
    }
    try std.testing.expect(found_main);
}

test "TaintError - error type exists" {
    const err = TaintError.OutOfMemory;
    try std.testing.expect(err == TaintError.OutOfMemory);
}

test "TaintPropagationPass - name" {
    try std.testing.expectEqualStrings("pointer-flow", TaintPropagationPass.name);
}

test "TaintPropagationPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, TaintPropagationPass.kind);
}

test "TaintPropagationPass - deps" {
    try std.testing.expectEqual(@as(usize, 1), TaintPropagationPass.deps.len);
    try std.testing.expectEqualStrings("call-graph", TaintPropagationPass.deps[0]);
}

test "isSource - matches source functions" {
    try std.testing.expect(isSource("main"));
    try std.testing.expect(isSource("read"));
    try std.testing.expect(!isSource("malloc"));
}

test "isSink - uses SemanticRegistry" {
    try std.testing.expect(isSink("system"));
    try std.testing.expect(isSink("strcpy"));
    try std.testing.expect(!isSink("malloc"));
}

test "TaintPropagationPass - handles null module gracefully" {
    const allocator = std.testing.allocator;
    var fact_store = FactStore.init(allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = try @import("../../dataflow/graph.zig").DataFlowGraph.init(allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var context = PassContext.init(allocator, null, &fact_store, &query_engine, &data_flow_graph);

    var diagnostics = DiagnosticWriter{ .allocator = allocator };

    _ = TaintPropagationPass.run(&context, &diagnostics);
}
