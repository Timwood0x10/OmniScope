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
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../diag/issue.zig").Severity;
const Location = @import("../../diag/issue.zig").Location;
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

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
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
            // BUG-05/07/12 FIX: Taint propagation must analyze ALL functions, not just
            // danger-surface-relevant ones. Source functions (fgets, read) and sinks
            // (system, printf) may live in ANY function — skipping non-"relevant" ones
            // breaks the entire source→sink detection chain.
            // Original: if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) continue;
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
                    const inst_id = ctx.getValueId(@intFromPtr(inst)) catch return;
                    try handleControlFlow(taint_ctx, pm, inst, opcode, inst_id);
                }
            },
            .noop => {},
            .cast => try handleCast(taint_ctx, inst, ctx.getValueId(@intFromPtr(inst)) catch return),
            .arithmetic => try handleArithmetic(taint_ctx, inst, ctx.getValueId(@intFromPtr(inst)) catch return),
            .memory => try handleMemoryOp(taint_ctx, inst, opcode, ctx.getValueId(@intFromPtr(inst)) catch return),
            .call => try handleCall(ctx, taint_ctx, sanitizer_registry, path_manager, inst, ctx.getValueId(@intFromPtr(inst)) catch return),
            .aggregate => try handleAggregate(taint_ctx, inst, opcode, ctx.getValueId(@intFromPtr(inst)) catch return),
        }
    }

    fn handleControlFlow(taint_ctx: *TaintContext, path_manager: *PathManager, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) !void {
        _ = next_id;

        if (opcode == c.LLVMBr) {
            // Conditional branch has 2 successors (true/false).
            // Unconditional branch has 1 successor.
            const num_succ = c.LLVMGetNumSuccessors(inst);
            const is_conditional = num_succ >= 2;
            if (is_conditional) {
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
                                const ptr_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(ptr_value));

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
            c.LLVMBr, c.LLVMSwitch, c.LLVMRet, c.LLVMUnreachable, c.LLVMResume => .control_flow,
            // BUG-FIX-7: LLVMInvoke is a call (with exception handling), not control_flow
            c.LLVMInvoke => .call,
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

        const operand_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(operand));
        if (taint_ctx.getValueTaint(operand_id)) |info| {
            if (info.state == .source or info.state == .tainted) {
                const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                try taint_ctx.setValueTaint(inst_id, info);
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
            const operand_val = @intFromPtr(operand);
            if (operand_val == 0) continue;

            const operand_id = try taint_ctx.getValueIdFromUsize(operand_val);
            if (taint_ctx.getValueTaint(operand_id)) |info| {
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
            const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
            try taint_ctx.setValueTaint(inst_id, new_info);
        }
    }

    fn handleMemoryOp(taint_ctx: *TaintContext, inst: c.LLVMValueRef, opcode: c_uint, next_id: u32) !void {
        switch (opcode) {
            c.LLVMLoad => {
                const ptr_operand = c.LLVMGetOperand(inst, 0);
                const ptr_val = @intFromPtr(ptr_operand);
                if (ptr_val == 0) return;

                const ptr_id = try taint_ctx.getValueIdFromUsize(ptr_val);
                if (taint_ctx.getValueTaint(ptr_id)) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        const new_info = TaintInfo{
                            .id = next_id,
                            .state = .tainted,
                            .source_id = info.source_id,
                            .confidence = @max(info.confidence * CONFIDENCE_DECAY, MIN_CONFIDENCE),
                        };
                        const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                        try taint_ctx.setValueTaint(inst_id, new_info);
                    }
                }
            },
            c.LLVMStore => {
                const value_operand = c.LLVMGetOperand(inst, 0);
                const ptr_operand = c.LLVMGetOperand(inst, 1);
                const value_val = @intFromPtr(value_operand);
                const ptr_val = @intFromPtr(ptr_operand);

                if (value_val == 0 or ptr_val == 0) return;

                const value_id = try taint_ctx.getValueIdFromUsize(value_val);
                if (taint_ctx.getValueTaint(value_id)) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        const ptr_id = try taint_ctx.getValueIdFromUsize(ptr_val);
                        try taint_ctx.setValueTaint(ptr_id, info);
                    }
                }
            },
            else => {},
        }
    }

    fn handleCall(ctx: *PassContext, taint_ctx: *TaintContext, sanitizer_registry: *SanitizerRegistry, path_manager: ?*PathManager, inst: c.LLVMValueRef, next_id: u32) !void {
        _ = path_manager;
        const called_value = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_value) == 0) return;

        const called_name_ptr = c.LLVMGetValueName(called_value);
        const called_func_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else "";

        // If this call is TO a source function (fgets, read, getenv, etc.),
        // mark all actual arguments as tainted sources.
        // This bridges the gap between formal params (marked by markFunctionParametersTainted)
        // and actual args at call sites (what we see during propagation).
        if (called_func_name.len > 0 and isSource(called_func_name)) {
            const num_ops = c.LLVMGetNumOperands(inst);
            var k: u32 = 0;
            while (k < num_ops) : (k += 1) {
                const arg = c.LLVMGetOperand(inst, k);
                const arg_val = @intFromPtr(arg);
                if (arg_val == 0) continue;
                const arg_id = try taint_ctx.getValueIdFromUsize(arg_val);
                const src_info = TaintInfo{
                    .id = next_id,
                    .state = .source,
                    .source_id = null,
                    .confidence = 1.0,
                };
                try taint_ctx.setValueTaint(arg_id, src_info);
            }
        }

        // BUG-05/07/12 FIX: Check for tainted data reaching dangerous sinks BEFORE
        // the sanitizer check (which may return early). This ensures we detect
        // command injection and format string vulnerabilities even when the
        // function is also classified as a sanitizer (e.g., snprintf).
        if (called_func_name.len > 0) {
            const num_ops = c.LLVMGetNumOperands(inst);
            var tainted_arg_idx: ?u32 = null;
            var max_taint_conf: f32 = 0.0;

            var j: u32 = 0;
            while (j < num_ops) : (j += 1) {
                const op = c.LLVMGetOperand(inst, j);
                const op_val = @intFromPtr(op);
                if (op_val == 0) continue;
                const op_id = try taint_ctx.getValueIdFromUsize(op_val);
                if (taint_ctx.getValueTaint(op_id)) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        if (info.confidence > max_taint_conf) {
                            max_taint_conf = info.confidence;
                            tainted_arg_idx = j;
                        }
                    }
                }
            }

            if (tainted_arg_idx) |arg_idx| {
                // Normalize: strip \01 prefix from mangled/internal symbols
                const normalized = if (called_func_name.len > 0 and called_func_name[0] == '\x01')
                    called_func_name[1..]
                else
                    called_func_name;
                const is_cmd = std.mem.indexOf(u8, normalized, "system") != null or
                    std.mem.indexOf(u8, normalized, "exec") != null or
                    std.mem.indexOf(u8, normalized, "popen") != null;
                // Match both vanilla (sprintf) and FORTIFY (__sprintf_chk) variants
                const is_fmt = std.mem.indexOf(u8, normalized, "printf") != null or
                    std.mem.indexOf(u8, normalized, "sprintf") != null or
                    std.mem.indexOf(u8, normalized, "snprintf") != null;

                if (is_cmd) {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "Command injection risk: tainted user input passed to {s}() — attacker may execute arbitrary commands", .{called_func_name});
                    defer ctx.allocator.free(msg);
                    var issue = Issue.init(
                        .command_injection,
                        msg,
                        Location.init(called_func_name),
                        IssueSeverity.critical,
                        max_taint_conf,
                    );
                    issue.owned = false;
                    try ctx.addIssue(&issue);
                } else if (is_fmt and arg_idx == 0) {
                    const fmt_op = c.LLVMGetOperand(inst, 0);
                    const is_literal = c.LLVMIsAConstantDataSequential(fmt_op) != null or
                        c.LLVMIsAConstantAggregateZero(fmt_op) != null;
                    if (!is_literal) {
                        const msg = try std.fmt.allocPrint(ctx.allocator, "Format string vulnerability: tainted data used as format string in {s}()", .{called_func_name});
                        defer ctx.allocator.free(msg);
                        var issue = Issue.init(
                            .format_string,
                            msg,
                            Location.init(called_func_name),
                            IssueSeverity.high,
                            max_taint_conf,
                        );
                        issue.owned = false;
                        try ctx.addIssue(&issue);
                    }
                }

                // Taint propagation for sprintf/snprintf: the destination buffer (operand 0)
                // receives tainted data from other arguments via internal side effect.
                // Without this, system(cmd) won't see %cmd as tainted because sprintf's
                // internal store to %cmd is invisible at IR level.
                if (is_fmt and num_ops >= 2 and arg_idx > 0) {
                    const dest_op = c.LLVMGetOperand(inst, 0);
                    const dest_val = @intFromPtr(dest_op);
                    if (dest_val != 0) {
                        const dest_id = try taint_ctx.getValueIdFromUsize(dest_val);
                        const prop_info = TaintInfo{
                            .id = next_id,
                            .state = .tainted,
                            .source_id = null,
                            .confidence = max_taint_conf * CONFIDENCE_DECAY,
                        };
                        try taint_ctx.setValueTaint(dest_id, prop_info);
                    }
                }
            }
        }

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
                const operand_val = @intFromPtr(operand);
                if (operand_val == 0) continue;

                const operand_id = try taint_ctx.getValueIdFromUsize(operand_val);
                if (taint_ctx.getValueTaint(operand_id)) |info| {
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
                    const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                    try taint_ctx.setValueTaint(inst_id, new_info);
                }
            }
            return;
        }

        // Check if this is a dangerous sink (known risky function in registry).
        // Mark return value as tainted (issue emission handled above, before sanitizer check).
        if (called_func_name.len > 0) {
            const sem = SemanticRegistry.lookup(called_func_name) orelse return;
            const is_dangerous = sem.severity == .critical or sem.severity == .high;
            if (!is_dangerous) return;

            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = null,
                .confidence = 1.0,
            };
            const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
            try taint_ctx.setValueTaint(inst_id, new_info);
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
            const operand_val = @intFromPtr(operand);
            if (operand_val == 0) continue;

            const operand_id = try taint_ctx.getValueIdFromUsize(operand_val);
            if (taint_ctx.getValueTaint(operand_id)) |info| {
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
            // Use semantic-aware confidence decay (default to CONFIDENCE_DECAY)
            const decay_factor = CONFIDENCE_DECAY;

            const new_info = TaintInfo{
                .id = next_id,
                .state = .tainted,
                .source_id = source_id,
                .confidence = @max(max_confidence * decay_factor, MIN_CONFIDENCE),
            };
            const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
            try taint_ctx.setValueTaint(inst_id, new_info);
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
                    const true_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(true_value));
                    if (taint_ctx.getValueTaint(true_id)) |info| {
                        if (info.state == .source or info.state == .tainted) {
                            source_id = info.source_id;
                            max_confidence = info.confidence;
                        }
                    }
                }

                if (@intFromPtr(false_value) != 0) {
                    const false_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(false_value));
                    if (taint_ctx.getValueTaint(false_id)) |info| {
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
                    const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                    try taint_ctx.setValueTaint(inst_id, new_info);
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
                    const incoming_val = @intFromPtr(incoming_value);
                    if (incoming_val == 0) continue;

                    const incoming_id = try taint_ctx.getValueIdFromUsize(incoming_val);
                    if (taint_ctx.getValueTaint(incoming_id)) |info| {
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
                    const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                    try taint_ctx.setValueTaint(inst_id, new_info);
                }
            },
            c.LLVMGetElementPtr => {
                const base_ptr = c.LLVMGetOperand(inst, 0);
                const base_val = @intFromPtr(base_ptr);
                if (base_val != 0) {
                    const base_id = try taint_ctx.getValueIdFromUsize(base_val);
                    if (taint_ctx.getValueTaint(base_id)) |info| {
                        if (info.state == .source or info.state == .tainted) {
                            const num_indices = c.LLVMGetNumIndices(inst);
                            const depth_factor: f32 = @max(0.0, 1.0 - (@as(f32, @floatFromInt(num_indices)) * GEP_DEPTH_CONFIDENCE_FACTOR));
                            const new_confidence = info.confidence * @max(depth_factor, MIN_GEP_DEPTH_CONFIDENCE);

                            const new_info = TaintInfo{
                                .id = next_id,
                                .state = .tainted,
                                .source_id = info.source_id,
                                .confidence = new_confidence,
                            };
                            const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                            try taint_ctx.setValueTaint(inst_id, new_info);
                        }
                    }
                }
            },
            else => {
                const operand = c.LLVMGetOperand(inst, 0);
                const operand_val = @intFromPtr(operand);
                if (operand_val == 0) return;

                const operand_id = try taint_ctx.getValueIdFromUsize(operand_val);
                if (taint_ctx.getValueTaint(operand_id)) |info| {
                    if (info.state == .source or info.state == .tainted) {
                        const inst_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(inst));
                        try taint_ctx.setValueTaint(inst_id, info);
                    }
                }
            },
        }
    }

    fn storeResults(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        var iter = taint_ctx.value_taint.iterator();
        var count: u32 = 0;
        var filtered_count: u32 = 0;

        while (iter.next()) |entry| {
            const value_id = entry.key_ptr.*;
            const taint_info = entry.value_ptr.*;

            if (taint_info.state != .none) {
                // E2-1a: MemoryGraph gate - only store taint facts for pointers
                // that are on a danger path (FFI-relevant). This prevents non-FFI
                // taint data from polluting downstream analysis passes.
                if (!ctx.isRelevantAlloc(value_id)) {
                    filtered_count += 1;
                    continue;
                }

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
            diag.info("PointerFlow: Stored {} pointer flow facts ({} filtered as non-FFI)", .{ count, filtered_count });
        } else if (filtered_count > 0) {
            diag.debug("PointerFlow: All {} taint facts filtered (not on FFI danger path)", .{filtered_count});
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
            const func_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(func));
            const param_id = ctx.getValueId(@intFromPtr(arg)) catch continue;
            const info = TaintInfo{
                .id = param_id,
                .state = .source,
                .source_id = func_id,
                .confidence = 1.0,
            };
            const arg_id = try taint_ctx.getValueIdFromUsize(@intFromPtr(arg));
            try taint_ctx.setValueTaint(arg_id, info);
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

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../../dataflow/graph.zig").DataFlowGraph.init(allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var context = try PassContext.init(allocator, null, &fact_store, &query_engine, &data_flow_graph);
    defer context.deinit();

    var diagnostics = DiagnosticWriter{ .allocator = allocator };

    _ = TaintPropagationPass.run(&context, &diagnostics);
}
