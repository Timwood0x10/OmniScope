# 跨语言安全性检测增强开发计划

## 项目概述

**目标**: 增强 OmniScope 的跨语言安全性检测能力，实现完整的数据流分析和漏洞检测

**当前状态**:
- ✅ CallGraphPass - 已实现，功能完整
- ⚠️ TaintPropagationPass - 占位符，需要实现
- ⚠️ FFIBoundaryPass - 占位符，需要实现
- ⚠️ SinkTracerPass - 占位符，需要实现

**编码规范**: 严格遵循 `./plan/zig_coding_guide.md`

---

## 第一阶段：污点传播分析增强

### 目标
实现完整的污点传播分析，包括数据流跟踪和污点状态管理

### 数据结构设计

#### TaintState (src/pass/analysis/taint_state.zig)

```zig
/// Represents taint state for a value or variable
pub const TaintState = enum(u8) {
    none = 0,           // No taint
    source = 1,         // Directly from source
    tainted = 2,        // Derived from tainted value
    safe = 3,           // Explicitly sanitized
};

/// Taint information for a value
pub const TaintInfo = struct {
    id: u32,
    state: TaintState,
    source_id: ?u32,    // Original source ID
    confidence: f32,    // Confidence score (0.0 - 1.0)
};

/// Taint propagation context
pub const TaintContext = struct {
    allocator: Allocator,
    value_taint: std.AutoHashMap(u32, TaintInfo),
    param_taint: std.AutoHashMap(u32, []TaintInfo),
    return_taint: std.AutoHashMap(u32, TaintInfo),

    pub fn init(allocator: Allocator) TaintContext;
    pub fn deinit(self: *TaintContext) void;
    pub fn setValueTaint(self: *TaintContext, value_id: u32, info: TaintInfo) !void;
    pub fn getValueTaint(self: *TaintContext, value_id: u32) ?TaintInfo;
    pub fn mergeTaint(self: *TaintContext, dst: u32, src: u32) !void;
};
```

#### PropagationRule (src/pass/analysis/propagation_rule.zig)

```zig
/// Taint propagation rule
pub const PropagationRule = struct {
    op_code: llvm.LLVMOpcode,
    direction: enum { forward, backward, both },
    handler: *const fn (ctx: *TaintContext, inst: llvm.LLVMValueRef) !void,
};

/// Built-in propagation rules
pub const BUILTIN_RULES = &[_]PropagationRule{
    .{ .op_code = .Load, .direction = .forward, .handler = handleLoad },
    .{ .op_code = .Store, .direction = .forward, .handler = handleStore },
    .{ .op_code = .Call, .direction = .forward, .handler = handleCall },
    .{ .op_code = .BitCast, .direction = .both, .handler = handleBitCast },
    .{ .op_code = .GetElementPtr, .direction = .forward, .handler = handleGEP },
};
```

### 模块设计

#### src/pass/analysis/taint_propagation.zig

```zig
//! Taint Propagation Analysis Pass
//!
//! Performs forward taint propagation to identify functions that may be
//! influenced by dangerous inputs (sources).
//!
//! This pass analyzes data flow within and across function boundaries,
//! tracking how tainted values propagate through the IR.

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const TaintContext = @import("./taint_state.zig").TaintContext;
const TaintInfo = @import("./taint_state.zig").TaintInfo;
const TaintState = @import("./taint_state.zig").TaintState;

pub const TaintError = error{
    OutOfMemory,
    InvalidIR,
    PropagationFailed,
};

pub const TaintPropagationPass = struct {
    pub const name = "taint-propagation";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    /// Run taint propagation analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) TaintError!void {
        if (ctx.module == null) return;

        var taint_ctx = TaintContext.init(ctx.allocator);
        defer taint_ctx.deinit();

        // Mark source functions as tainted
        try markSources(ctx, &taint_ctx, diag);

        // Propagate taint through the IR
        try propagateTaint(ctx, &taint_ctx, diag);

        // Store results in fact store
        try storeResults(ctx, &taint_ctx);
    }

    /// Mark source function parameters as tainted
    fn markSources(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = llvm.LLVMGetFirstFunction(mod);

        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            const func_name_ptr = llvm.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

            if (isSourceFunction(func_name)) {
                try markFunctionParametersTainted(ctx, taint_ctx, func, diag);
            }
        }
    }

    /// Propagate taint through all functions
    fn propagateTaint(ctx: *PassContext, taint_ctx: *TaintContext, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = llvm.LLVMGetFirstFunction(mod);

        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            try propagateThroughFunction(ctx, taint_ctx, func, diag);
        }
    }

    /// Propagate taint through a single function
    fn propagateThroughFunction(ctx: *PassContext, taint_ctx: *TaintContext, func: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        var bb = llvm.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = llvm.LLVMGetNextBasicBlock(bb)) {
            try propagateThroughBasicBlock(ctx, taint_ctx, bb, diag);
        }
    }

    /// Propagate taint through a basic block
    fn propagateThroughBasicBlock(ctx: *PassContext, taint_ctx: *TaintContext, bb: llvm.LLVMBasicBlockRef, diag: *DiagnosticWriter) !void {
        var inst = llvm.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = llvm.LLVMGetNextInstruction(inst)) {
            try propagateThroughInstruction(ctx, taint_ctx, inst, diag);
        }
    }

    /// Propagate taint through a single instruction
    fn propagateThroughInstruction(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const opcode = llvm.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            .Load => try handleLoad(ctx, taint_ctx, inst, diag),
            .Store => try handleStore(ctx, taint_ctx, inst, diag),
            .Call => try handleCall(ctx, taint_ctx, inst, diag),
            .BitCast => try handleBitCast(ctx, taint_ctx, inst, diag),
            .GetElementPtr => try handleGEP(ctx, taint_ctx, inst, diag),
            .Add, .Sub, .Mul => try handleArithmetic(ctx, taint_ctx, inst, diag),
            else => {}, // Ignore other instructions
        }
    }

    /// Handle load instruction
    fn handleLoad(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const ptr_operand = llvm.LLVMGetOperand(inst, 0);
        const ptr_taint = taint_ctx.getValueTaint(@intFromPtr(ptr_operand));

        if (ptr_taint) |info| {
            const new_info = TaintInfo{
                .id = ctx.getNextId(),
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = info.confidence * 0.95,
            };
            try taint_ctx.setValueTaint(@intFromPtr(inst), new_info);
        }
    }

    /// Handle store instruction
    fn handleStore(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const value_operand = llvm.LLVMGetOperand(inst, 0);
        const ptr_operand = llvm.LLVMGetOperand(inst, 1);
        const value_taint = taint_ctx.getValueTaint(@intFromPtr(value_operand));

        if (value_taint) |info| {
            try taint_ctx.setValueTaint(@intFromPtr(ptr_operand), info);
        }
    }

    /// Handle call instruction
    fn handleCall(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const called_value = llvm.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_value) == 0) return;

        const called_name_ptr = llvm.LLVMGetValueName(called_value);
        if (@intFromPtr(called_name_ptr) == 0) return;
        const called_name = std.mem.span(called_name_ptr);

        // Check if callee is a sink
        if (isSinkFunction(called_name)) {
            // Report vulnerability if tainted data flows to sink
            try checkTaintedCall(ctx, taint_ctx, inst, called_name, diag);
        } else {
            // Propagate taint to callee parameters
            try propagateToCallee(ctx, taint_ctx, inst, called_name);
        }
    }

    /// Handle bitcast instruction
    fn handleBitCast(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const operand = llvm.LLVMGetOperand(inst, 0);
        const operand_taint = taint_ctx.getValueTaint(@intFromPtr(operand));

        if (operand_taint) |info| {
            try taint_ctx.setValueTaint(@intFromPtr(inst), info);
        }
    }

    /// Handle getelementptr instruction
    fn handleGEP(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const ptr_operand = llvm.LLVMGetOperand(inst, 0);
        const ptr_taint = taint_ctx.getValueTaint(@intFromPtr(ptr_operand));

        if (ptr_taint) |info| {
            const new_info = TaintInfo{
                .id = ctx.getNextId(),
                .state = .tainted,
                .source_id = info.source_id,
                .confidence = info.confidence * 0.98,
            };
            try taint_ctx.setValueTaint(@intFromPtr(inst), new_info);
        }
    }

    /// Handle arithmetic instructions
    fn handleArithmetic(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const num_operands = llvm.LLVMGetNumOperands(inst);
        var tainted: bool = false;
        var max_confidence: f32 = 0.0;

        var i: u32 = 0;
        while (i < num_operands) : (i += 1) {
            const operand = llvm.LLVMGetOperand(inst, i);
            if (taint_ctx.getValueTaint(@intFromPtr(operand))) |info| {
                tainted = true;
                if (info.confidence > max_confidence) {
                    max_confidence = info.confidence;
                }
            }
        }

        if (tainted) {
            const new_info = TaintInfo{
                .id = ctx.getNextId(),
                .state = .tainted,
                .source_id = null, // Multiple sources possible
                .confidence = max_confidence * 0.9,
            };
            try taint_ctx.setValueTaint(@intFromPtr(inst), new_info);
        }
    }

    /// Store taint analysis results in fact store
    fn storeResults(ctx: *PassContext, taint_ctx: *TaintContext) !void {
        var iter = taint_ctx.value_taint.iterator();
        while (iter.next()) |entry| {
            const value_id = entry.key_ptr.*;
            const taint_info = entry.value_ptr.*;

            try ctx.fact_store.insert(
                .taint,
                value_id,
                @intFromEnum(taint_info.state),
                taint_info.id,
            );
        }
    }

    // Helper functions
    fn isSourceFunction(name: []const u8) bool {
        return call_graph.isSource(name);
    }

    fn isSinkFunction(name: []const u8) bool {
        return call_graph.isSink(name);
    }

    fn markFunctionParametersTainted(ctx: *PassContext, taint_ctx: *TaintContext, func: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        var arg = llvm.LLVMGetFirstParam(func);
        var param_idx: u32 = 0;

        while (@intFromPtr(arg) != 0) : (arg = llvm.LLVMGetNextParam(arg)) {
            const info = TaintInfo{
                .id = ctx.getNextId(),
                .state = .source,
                .source_id = @intFromPtr(func),
                .confidence = 1.0,
            };
            try taint_ctx.setValueTaint(@intFromPtr(arg), info);
            param_idx += 1;
        }

        diag.info("Marked {} parameters of source function as tainted", .{param_idx});
    }

    fn checkTaintedCall(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, sink_name: []const u8, diag: *DiagnosticWriter) !void {
        const num_operands = llvm.LLVMGetNumOperands(inst);

        var i: u32 = 0;
        while (i < num_operands) : (i += 1) {
            const operand = llvm.LLVMGetOperand(inst, i);
            if (taint_ctx.getValueTaint(@intFromPtr(operand))) |info| {
                if (info.state != .none) {
                    diag.err("TAINT FLOW: Tainted data to sink '{s}' (confidence: {:.2})", .{sink_name, info.confidence});
                }
            }
        }
    }

    fn propagateToCallee(ctx: *PassContext, taint_ctx: *TaintContext, inst: llvm.LLVMValueRef, callee_name: []const u8) !void {
        // Implementation depends on inter-procedural analysis
        // For now, handle intraprocedural only
    }
};
```

### 测试用例

```zig
test "TaintContext - init and deinit" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();
    try std.testing.expect(@as(usize, 0), ctx.value_taint.count());
}

test "TaintContext - set and get value taint" {
    var ctx = TaintContext.init(std.testing.allocator);
    defer ctx.deinit();

    const info = TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.95,
    };
    try ctx.setValueTaint(100, info);

    const retrieved = ctx.getValueTaint(100);
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(TaintState.tainted, retrieved.?.state);
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), retrieved.?.confidence, 0.001);
}

test "TaintState - all variants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TaintState.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TaintState.source));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(TaintState.tainted));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(TaintState.safe));
}

test "TaintInfo - structure" {
    const info = TaintInfo{
        .id = 42,
        .state = .tainted,
        .source_id = 10,
        .confidence = 0.8,
    };
    try std.testing.expectEqual(@as(u32, 42), info.id);
    try std.testing.expectEqual(TaintState.tainted, info.state);
    try std.testing.expectEqual(@as(?u32, 10), info.source_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), info.confidence, 0.001);
}

test "TaintInfo - default confidence" {
    const info = TaintInfo{
        .id = 1,
        .state = .source,
        .source_id = null,
        .confidence = 1.0,
    };
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), info.confidence, 0.001);
}

test "TaintInfo - no source" {
    const info = TaintInfo{
        .id = 1,
        .state = .tainted,
        .source_id = null,
        .confidence = 0.5,
    };
    try std.testing.expectEqual(@as(?u32, null), info.source_id);
}

test "TaintPropagationPass - pass interface" {
    const pass = TaintPropagationPass;
    try std.testing.expectEqualStrings("taint-propagation", pass.name);
    try std.testing.expectEqual(PassKind.foundation, pass.kind);
}
```

### 验收标准

- [ ] `make check` 显示 0 errors
- [ ] 所有测试通过
- [ ] 能够正确传播污点通过基本指令
- [ ] 能够检测污点数据流到汇点
- [ ] 代码符合编码规范

---

## 第二阶段：FFI 边界检测

### 目标
实现精确的 FFI 边界检测，标记跨语言调用

### 数据结构设计

#### FFIBoundaryInfo (src/pass/analysis/ffi_info.zig)

```zig
/// FFI boundary type
pub const FFIKind = enum {
    none,           // Not FFI
    c_call,         // C FFI call
    rust_ffi,       // Rust FFI
    go_cgo,         // Go CGO
    other,          // Other language
};

/// FFI boundary information
pub const FFIBoundaryInfo = struct {
    edge_id: u32,
    caller: u32,
    callee: u32,
    kind: FFIKind,
    target_language: []const u8,
    is_exported: bool,        // Function exported to other language
    is_imported: bool,        // Function imported from other language
};

/// FFI boundary detector
pub const FFIBoundaryDetector = struct {
    allocator: Allocator,
    boundaries: std.ArrayList(FFIBoundaryInfo),
    language_patterns: std.StringHashMap(FFIKind),

    pub fn init(allocator: Allocator) FFIBoundaryDetector;
    pub fn deinit(self: *FFIBoundaryDetector) void;
    pub fn detectBoundaries(self: *FFIBoundaryDetector, nodes: []call_graph.Node, edges: []call_graph.Edge) !void;
    pub fn isFFICall(self: *FFIBoundaryDetector, node: *const call_graph.Node) bool;
    pub fn classifyFFIKind(self: *FFIBoundaryDetector, func_name: []const u8) FFIKind;
};
```

### 模块设计

#### src/pass/analysis/ffi_boundary.zig

```zig
//! FFI Boundary Detection Pass
//!
//! Marks cross-language transitions in the call graph.
//! Only external_unknown is considered a true FFI boundary (not libc).

const std = @import("std");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const FFIBoundaryInfo = @import("./ffi_info.zig").FFIBoundaryInfo;
const FFIKind = @import("./ffi_info.zig").FFIKind;
const FFIBoundaryDetector = @import("./ffi_info.zig").FFIBoundaryDetector;

pub const FFIBoundaryError = error{
    OutOfMemory,
    InvalidCallGraph,
};

pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    /// Run FFI boundary detection
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void {
        if (ctx.module == null) return;

        var detector = FFIBoundaryDetector.init(ctx.allocator);
        defer detector.deinit();

        // Query call graph facts
        const nodes = try ctx.query_engine.queryByKind(.cfg_edge, ctx.allocator);
        defer ctx.allocator.free(nodes);

        // Detect FFI boundaries
        try detectFFIBoundaries(ctx, &detector, nodes, diag);

        // Store results
        try storeFFIFacts(ctx, detector, diag);
    }

    /// Detect FFI boundaries in the call graph
    fn detectFFIBoundaries(ctx: *PassContext, detector: *FFIBoundaryDetector, nodes: []Fact, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = llvm.LLVMGetFirstFunction(mod);

        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            const func_name_ptr = llvm.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

            if (detector.isFFICall(func_name)) {
                const kind = detector.classifyFFIKind(func_name);
                diag.info("FFI boundary detected: {s} ({s})", .{func_name, @tagName(kind)});
            }
        }
    }

    /// Store FFI facts in fact store
    fn storeFFIFacts(ctx: *PassContext, detector: *FFIBoundaryDetector, diag: *DiagnosticWriter) !void {
        for (detector.boundaries.items) |boundary| {
            try ctx.fact_store.insert(
                .ffi_boundary,
                boundary.caller,
                boundary.callee,
                @intFromEnum(boundary.kind),
            );
        }
    }
};
```

### 测试用例

```zig
test "FFIBoundaryDetector - init and deinit" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();
    try std.testing.expect(@as(usize, 0), detector.boundaries.items.len);
}

test "FFIBoundaryInfo - structure" {
    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 100,
        .callee = 200,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };
    try std.testing.expectEqual(@as(u32, 1), info.edge_id);
    try std.testing.expect(FFIKind.rust_ffi == info.kind);
    try std.testing.expect(info.is_exported);
}

test "FFIBoundaryPass - pass interface" {
    const pass = FFIBoundaryPass;
    try std.testing.expectEqualStrings("ffi-boundary", pass.name);
    try std.testing.expectEqual(PassKind.foundation, pass.kind);
}
```

### 验收标准

- [ ] `make check` 显示 0 errors
- [ ] 能够正确识别 FFI 调用
- [ ] 能够分类不同语言的 FFI
- [ ] 代码符合编码规范

---

## 第三阶段：汇点追踪

### 目标
实现完整的污点数据流追踪，从源到汇点的完整路径

### 数据结构设计

#### FlowPath (src/pass/analysis/flow_path.zig)

```zig
/// Risk level for vulnerabilities
pub const RiskLevel = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    critical = 3,
};

/// Flow step in the data flow path
pub const FlowStep = struct {
    id: u32,
    func_name: []const u8,
    location: Location,
    taint_state: TaintState,
    confidence: f32,
};

/// Complete flow path from source to sink
pub const FlowPath = struct {
    steps: []FlowStep,
    risk_level: RiskLevel,
    is_cross_language: bool,
    source_func: []const u8,
    sink_func: []const u8,
};

/// Vulnerability report
pub const VulnerabilityReport = struct {
    id: u32,
    risk_level: RiskLevel,
    source_func: []const u8,
    sink_func: []const u8,
    flow_path: FlowPath,
    description: []const u8,
    recommendation: []const u8,
};
```

### 模块设计

#### src/pass/analysis/sink_tracer.zig

```zig
//! Sink Tracer Analysis Pass
//!
//! Traces tainted data flow from sources to dangerous sinks.

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const FlowPath = @import("./flow_path.zig").FlowPath;
const FlowStep = @import("./flow_path.zig").FlowStep;
const RiskLevel = @import("./flow_path.zig").RiskLevel;
const VulnerabilityReport = @import("./flow_path.zig").VulnerabilityReport;

pub const FlowPathError = error{
    OutOfMemory,
    PathNotFound,
    InvalidTaintState,
};

pub const SinkTracerPass = struct {
    pub const name = "sink-tracer";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary", "taint-propagation"};

    /// Run sink tracing analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FlowPathError!void {
        if (ctx.module == null) return;

        // Find all tainted values
        const tainted_values = try findTaintedValues(ctx);
        defer ctx.allocator.free(tainted_values);

        // Trace flow paths to sinks
        for (tainted_values) |value_id| {
            const path = try traceFlowPath(ctx, value_id, diag);
            if (path) |p| {
                try reportVulnerability(ctx, p, diag);
            }
        }
    }

    /// Find all tainted values in the IR
    fn findTaintedValues(ctx: *PassContext) ![]u32 {
        var tainted = std.ArrayList(u32).init(ctx.allocator);
        errdefer tainted.deinit();

        const facts = try ctx.query_engine.queryByKind(.taint, ctx.allocator);
        defer ctx.allocator.free(facts);

        for (facts) |fact| {
            if (fact.object != 0) { // Not TaintState.none
                try tainted.append(fact.subject);
            }
        }

        return tainted.toOwnedSlice();
    }

    /// Trace flow path from tainted value to sink
    fn traceFlowPath(ctx: *PassContext, value_id: u32, diag: *DiagnosticWriter) FlowPathError!?FlowPath {
        // Implementation of backward data flow analysis
        // Returns complete path if sink is reached
        return null; // Placeholder
    }

    /// Report vulnerability with complete information
    fn reportVulnerability(ctx: *PassContext, path: FlowPath, diag: *DiagnosticWriter) !void {
        diag.err("VULNERABILITY DETECTED", .{});
        diag.err("Risk Level: {s}", .{@tagName(path.risk_level)});
        diag.err("Source: {s}", .{path.source_func});
        diag.err("Sink: {s}", .{path.sink_func});
        diag.err("Cross-language: {}", .{path.is_cross_language});

        diag.err("Flow Path:", .{});
        for (path.steps) |step| {
            diag.err("  -> {s} (confidence: {:.2})", .{step.func_name, step.confidence});
        }
    }
};
```

### 测试用例

```zig
test "FlowPath - empty path" {
    const path = FlowPath{
        .steps = &[0]FlowStep{},
        .risk_level = .low,
        .is_cross_language = false,
        .source_func = "",
        .sink_func = "",
    };
    try std.testing.expectEqual(@as(usize, 0), path.steps.len);
}

test "FlowStep - structure" {
    const step = FlowStep{
        .id = 1,
        .func_name = "test_func",
        .location = undefined,
        .taint_state = .tainted,
        .confidence = 0.95,
    };
    try std.testing.expectEqual(@as(u32, 1), step.id);
    try std.testing.expectEqualStrings("test_func", step.func_name);
}

test "RiskLevel - all variants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(RiskLevel.low));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(RiskLevel.medium));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(RiskLevel.high));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(RiskLevel.critical));
}

test "SinkTracerPass - pass interface" {
    const pass = SinkTracerPass;
    try std.testing.expectEqualStrings("sink-tracer", pass.name);
    try std.testing.expectEqual(PassKind.analysis, pass.kind);
}
```

### 验收标准

- [ ] `make check` 显示 0 errors
- [ ] 能够追踪完整的数据流路径
- [ ] 能够生成详细的漏洞报告
- [ ] 代码符合编码规范

---

## 第四阶段：集成和优化

### 目标
集成所有 pass，优化性能，添加更多检测规则

### 任务清单

1. **集成测试**
   - 创建完整的跨语言示例
   - 端到端测试
   - 性能基准测试

2. **性能优化**
   - 优化数据结构（SoA 布局）
   - 减少内存分配
   - 并行化分析

3. **增强检测规则**
   - 添加更多源函数模式
   - 添加更多汇点函数模式
   - 添加消毒函数检测

4. **错误处理改进**
   - 更好的错误消息
   - 恢复机制
   - 部分分析支持

### 验收标准

- [ ] 所有测试通过
- [ ] 性能基准达标
- [ ] 代码审查通过
- [ ] 文档完整

---

## 编码规范检查清单

### 文件结构
- [ ] 单文件不超过 1000 行
- [ ] 导入顺序正确
- [ ] 类型定义在前，函数在后

### 命名规范
- [ ] 类型使用 PascalCase
- [ ] 函数使用 camelCase
- [ ] 常量使用 SCREAMING_SNAKE_CASE
- [ ] 字段使用 camelCase

### 内存管理
- [ ] 所有分配器显式传递
- [ ] 正确使用 defer 清理
- [ ] 避免内存泄漏

### 错误处理
- [ ] 使用具体错误类型
- [ ] 正确传播错误
- [ ] 边界条件处理

### 测试质量
- [ ] 测试覆盖关键路径
- [ ] 测试边界条件
- [ ] 测试错误情况
- [ ] 避免敷衍的 assert

### 性能
- [ ] IR 层保持零抽象
- [ ] Fact Store 使用 SoA 布局
- [ ] 避免不必要的计算

### 文档
- [ ] 公共 API 有文档注释
- [ ] 所有注释使用英文
- [ ] 复杂逻辑有说明

---

## 时间估计

- **第一阶段**: 2-3 天
- **第二阶段**: 1-2 天
- **第三阶段**: 2-3 天
- **第四阶段**: 2-3 天

**总计**: 7-11 天

---

## 成功指标

1. **功能完整性**
   - 所有三个 pass 完整实现
   - 能够检测跨语言安全漏洞
   - 生成详细的漏洞报告

2. **代码质量**
   - `make check` 显示 0 errors
   - 测试覆盖率 > 80%
   - 代码符合编码规范

3. **性能**
   - 分析大型项目 (< 5s)
   - 内存使用合理 (< 1GB)
   - 可扩展性好

4. **可用性**
   - 文档完整
   - 示例清晰
   - 易于使用

---

## 后续优化方向

1. **更精确的污点分析**
   - 上下文敏感分析
   - 路径敏感分析
   - 字段敏感分析

2. **更多语言支持**
   - Python FFI
   - Java JNI
   - C# P/Invoke

3. **运行时验证**
   - 动态污点跟踪
   - 运行时插桩
   - 实时监控

4. **机器学习增强**
   - 模式识别
   - 异常检测
   - 风险预测

---

**文档版本**: 1.0
**最后更新**: 2026-04-14
**作者**: OmniScope 开发团队