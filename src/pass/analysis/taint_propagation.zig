//! Taint Propagation Analysis Pass
//!
//! Performs forward taint propagation to identify functions that may be
//! influenced by dangerous inputs (sources).
//!
//! This pass analyzes data flow within and across function boundaries,
//! tracking how tainted values propagate through the IR.

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
const propagation_rule = @import("./propagation_rule.zig");

/// Re-exports SOURCE_FUNCTIONS from call_graph module.
/// These functions are considered sources of taint.
pub const SOURCE_FUNCTIONS = call_graph.SOURCE_FUNCTIONS;

/// Error type for taint propagation operations.
pub const TaintError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Invalid IR encountered.
    InvalidIR,
    /// Propagation failed.
    PropagationFailed,
};

/// Taint propagation analysis pass.
///
/// This pass performs forward taint propagation through the call graph.
/// It depends on the call-graph pass for the graph structure.
pub const TaintPropagationPass = struct {
    pub const name = "taint-propagation";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    /// Run taint propagation analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) TaintError!void {
        if (ctx.module == null) return;

        var taint_ctx = TaintContext.init(ctx.allocator);
        defer taint_ctx.deinit();

        try markSources(ctx, &taint_ctx, diag);
        try propagateTaint(ctx, &taint_ctx, diag);
        try storeResults(ctx, &taint_ctx, diag);
    }

    /// Mark source function parameters as tainted
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
            diag.info("TaintPropagation: Found {} source functions", .{source_count});
        }
    }

    /// Propagate taint through all functions
    fn propagateTaint(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;
        var inst_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            try propagateThroughFunction(ctx, taint_ctx, func, &inst_count, diag);
        }

        const tainted_count = taint_ctx.taintedCount();
        if (tainted_count > 0) {
            diag.info("TaintPropagation: {} values tainted after propagation", .{tainted_count});
        }
    }

    /// Propagate taint through a single function
    fn propagateThroughFunction(ctx: *PassContext, taint_ctx: *TaintContext, func: c.LLVMValueRef, inst_count: *u32, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            try propagateThroughBasicBlock(ctx, taint_ctx, bb, inst_count, diag);
        }
    }

    /// Propagate taint through a basic block
    fn propagateThroughBasicBlock(ctx: *PassContext, taint_ctx: *TaintContext, bb: c.LLVMBasicBlockRef, inst_count: *u32, diag: *DiagnosticWriter) !void {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            try propagateThroughInstruction(ctx, taint_ctx, inst, inst_count, diag);
        }
    }

    /// Propagate taint through a single instruction
    fn propagateThroughInstruction(ctx: *PassContext, taint_ctx: *TaintContext, inst: c.LLVMValueRef, inst_count: *u32, diag: *DiagnosticWriter) !void {
        inst_count.* += 1;
        const opcode = c.LLVMGetInstructionOpcode(inst);

        const rule = propagation_rule.findRule(opcode) orelse {
            diag.warn("No propagation rule for opcode {}", .{@intFromEnum(opcode)});
            return;
        };
        rule.handler(taint_ctx, inst, ctx.getNextId()) catch |err| {
            diag.warn("Propagation failed for opcode {}: {}", .{ @intFromEnum(opcode), err });
        };
    }

    /// Store taint analysis results in fact store
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
            diag.info("TaintPropagation: Stored {} taint facts", .{count});
        }
    }

    /// Check if a function is a taint source
    fn isSourceFunction(func_name: []const u8) bool {
        return isSource(func_name);
    }

    /// Check if a function is a taint sink
    fn isSinkFunction(func_name: []const u8) bool {
        return isSink(func_name);
    }

    /// Mark function parameters as tainted
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
                .source_id = @intFromPtr(func),
                .confidence = 1.0,
            };
            try taint_ctx.setValueTaint(@intFromPtr(arg), info);
            param_idx += 1;
        }

        if (param_idx > 0) {
            diag.info("TaintPropagation: Marked {} parameters of '{s}' as tainted", .{ param_idx, func_name });
        }
    }

    /// Check for tainted call to sink
    fn checkTaintedCall(ctx: *PassContext, taint_ctx: *TaintContext, inst: c.LLVMValueRef, sink_name: []const u8, diag: *DiagnosticWriter) !void {
        const num_operands = c.LLVMGetNumOperands(inst);

        var i: u32 = 0;
        while (i < num_operands) : (i += 1) {
            const operand = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(operand) == 0) continue;

            if (taint_ctx.getValueTaint(@intFromPtr(operand))) |info| {
                if (info.state != .none and info.state != .safe) {
                    diag.err("TAINT FLOW: Tainted data flows to sink '{s}' (confidence: {d:.2})", .{ sink_name, info.confidence });
                    try ctx.fact_store.insert(.taint, info.source_id orelse 0, @intFromPtr(inst), ctx.getNextId());
                }
            }
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
    for (call_graph.SINK_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }
    return false;
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

test "SOURCE_FUNCTIONS - contains read" {
    var found_read = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "read")) {
            found_read = true;
            break;
        }
    }
    try std.testing.expect(found_read);
}

test "SOURCE_FUNCTIONS - all non-empty" {
    for (SOURCE_FUNCTIONS) |s| {
        try std.testing.expect(s.len > 0);
    }
}

test "SOURCE_FUNCTIONS - has expected sources" {
    const expected = &[_][]const u8{ "main", "read", "recv", "gets", "scanf" };
    for (expected) |exp| {
        var found = false;
        for (SOURCE_FUNCTIONS) |s| {
            if (std.mem.eql(u8, s, exp)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "SOURCE_FUNCTIONS - no duplicates" {
    for (SOURCE_FUNCTIONS, 0..) |s1, i| {
        for (SOURCE_FUNCTIONS, 0..) |s2, j| {
            if (i != j and std.mem.eql(u8, s1, s2)) {
                try std.testing.expect(false);
            }
        }
    }
}

test "TaintError - error type exists" {
    const err = TaintError.OutOfMemory;
    try std.testing.expect(err == TaintError.OutOfMemory);
}

test "TaintPropagationPass - name" {
    try std.testing.expectEqualStrings("taint-propagation", TaintPropagationPass.name);
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
    try std.testing.expect(isSource("recv"));
    try std.testing.expect(!isSource("malloc"));
    try std.testing.expect(!isSource("printf"));
}

test "isSink - matches sink patterns" {
    try std.testing.expect(isSink("system"));
    try std.testing.expect(isSink("execve"));
    try std.testing.expect(isSink("popen"));
    try std.testing.expect(isSink("__strcpy_chk"));
    try std.testing.expect(!isSink("malloc"));
    try std.testing.expect(!isSink("free"));
}

test "isSink - partial matches" {
    try std.testing.expect(isSink("system_call"));
    try std.testing.expect(isSink("my_popen_wrapper"));
}

test "TaintPropagationPass - deps not empty" {
    try std.testing.expect(TaintPropagationPass.deps.len > 0);
}

test "TaintPropagationPass - deps valid strings" {
    for (TaintPropagationPass.deps) |dep| {
        try std.testing.expect(dep.len > 0);
    }
}

test "TaintPropagationPass - handles null module gracefully" {
    // Test that the pass handles null module without crashing
    const allocator = std.testing.allocator;
    var fact_store = FactStore.init(allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var data_flow_graph = @import("../../dataflow/graph.zig").DataFlowGraph.init(allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var context = PassContext.init(allocator, null, &fact_store, &query_engine, &data_flow_graph);

    var diagnostics = DiagnosticWriter{ .allocator = allocator };

    // This should not panic, just return early
    _ = TaintPropagationPass.run(&context, &diagnostics);
}
