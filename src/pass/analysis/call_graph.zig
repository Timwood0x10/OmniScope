//! Call Graph Analysis Pass
//!
//! Builds a call graph from LLVM IR, recording function relationships
//! and classifying functions by kind (internal, libc, external_unknown).
//!
//! This pass is stateless - it analyzes the IR directly and emits diagnostics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const CrossLangEdge = @import("../pass.zig").CrossLangEdge;
const ptr_types = @import("ptr_lifetime/ptr_lifetime_types.zig");
const language_detector = @import("../../semantics/language_detector.zig");
const semantics_call_graph = @import("../../semantics/call_graph.zig");
const cg_types = @import("../../types/call_graph_types.zig");
pub const FunctionKind = cg_types.FunctionKind;
pub const Node = cg_types.Node;
pub const Edge = cg_types.Edge;
pub const LIBC_FUNCTIONS = cg_types.LIBC_FUNCTIONS;
pub const DANGEROUS_FUNCTIONS = cg_types.DANGEROUS_FUNCTIONS;
pub const SOURCE_FUNCTIONS = cg_types.SOURCE_FUNCTIONS;
pub const SINK_PATTERNS = cg_types.SINK_PATTERNS;

pub fn isLibC(func_name: []const u8) bool {
    for (LIBC_FUNCTIONS) |libc_name| {
        if (std.mem.eql(u8, func_name, libc_name)) return true;
    }
    if (ptr_types.isHeapAllocFunction(func_name)) return true;
    if (ptr_types.isKnownDeallocFunction(func_name)) return true;
    return false;
}

/// Resolve indirect call to a list of candidate functions based on type signature.
///
/// Type-based devirtualization: LLVM IR is strongly typed, so an indirect call's
/// candidate targets are limited to functions whose signatures match the call's
/// function type. This provides a conservative may-call set.
///
/// Returns a slice of function pointers. Caller must free the returned slice
/// by calling `allocator.free(result)`.
pub fn resolveIndirectCall(
    allocator: Allocator,
    mod: c.LLVMModuleRef,
    call_inst: c.LLVMValueRef,
) ![]usize {
    const called_val = c.LLVMGetCalledValue(call_inst);
    if (called_val == null) return &[_]usize{};

    const call_type = c.LLVMTypeOf(called_val);
    if (@intFromPtr(call_type) == 0) return &[_]usize{};

    var candidates = try std.ArrayList(usize).initCapacity(allocator, 16);
    defer candidates.deinit(allocator);

    var func = c.LLVMGetFirstFunction(mod);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        const func_type = c.LLVMTypeOf(func);
        if (@intFromPtr(func_type) == 0) continue;

        if (c.LLVMCountParams(func) == c.LLVMCountParamTypes(call_type) and
            c.LLVMGetTypeKind(call_type) == c.LLVMGetTypeKind(func_type) and
            c.LLVMGetReturnType(call_type) == c.LLVMGetReturnType(func_type))
        {
            var param_match = true;
            const param_count = c.LLVMCountParams(func);
            const num_operands = c.LLVMGetNumOperands(call_inst);
            if (num_operands < param_count) continue;
            for (0..param_count) |i| {
                const func_param = c.LLVMGetParam(func, @intCast(i));
                const call_arg = c.LLVMGetOperand(call_inst, @as(c_uint, @intCast(i)));
                if (c.LLVMTypeOf(func_param) != c.LLVMTypeOf(call_arg)) {
                    param_match = false;
                    break;
                }
            }
            if (param_match) {
                try candidates.append(allocator, @intFromPtr(func));
            }
        }
    }

    return try candidates.toOwnedSlice(allocator);
}

/// Call graph analysis pass.
///
/// Analyzes LLVM IR to build a function call graph, classifies functions,
/// and detects taint propagation paths from sources to sinks.
pub const CallGraphPass = struct {
    pub const name = "call-graph";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;

        var nodes: std.ArrayList(Node) = .{};
        defer {
            for (nodes.items) |*node| {
                node.deinit(ctx.allocator);
            }
            nodes.deinit(ctx.allocator);
        }

        var edges: std.ArrayList(Edge) = .{};
        defer edges.deinit(ctx.allocator);

        try buildNodes(ctx.allocator, mod, &nodes);
        try buildEdges(ctx.allocator, &nodes, &edges);
        classifyFunctions(&nodes);
        markSources(&nodes);
        try propagateTaint(ctx.allocator, &nodes, &edges);
        try detectAndReportSinks(ctx, &nodes, &edges, diag);

        // R8.2-b: Extract cross-language call edges for downstream passes.
        try extractCrossLangEdges(ctx, &nodes, &edges, diag);

        // Early exit: no cross-language edges means pure single-language project.
        // Skip remaining heavy passes (pointer_ownership, taint, ffi_boundary, etc.)
        if (ctx.cross_lang_edges.items.len == 0) {
            diag.info("CallGraph: no cross-language edges — single-language project, skipping FFI passes", .{});
            ctx.early_exit = true;
            return;
        }

        // CRITICAL FIX for 0/73 benchmark: Build semantics-level CallGraph for BFS traversal.
        {
            var sg = semantics_call_graph.CallGraph.init(ctx.allocator) catch |err| {
                diag.warn("CallGraph: failed to init semantics CallGraph: {}", .{err});
                return;
            };
            errdefer sg.deinit();

            var name_to_sg_id = std.StringHashMap(u64).init(ctx.allocator);
            defer name_to_sg_id.deinit();

            var node_fail_count: u32 = 0;
            var edge_fail_count: u32 = 0;

            for (nodes.items) |node| {
                const is_ffi_boundary = node.kind == .external_unknown or isSink(node.name);
                const node_id = sg.addNode(null, node.name, node.is_external, is_ffi_boundary) catch {
                    node_fail_count += 1;
                    continue;
                };
                try name_to_sg_id.put(node.name, node_id);
            }

            for (edges.items) |edge| {
                if (edge.caller >= nodes.items.len or edge.callee >= nodes.items.len) continue;
                const caller_name = nodes.items[edge.caller].name;
                const callee_name = nodes.items[edge.callee].name;
                const caller_sg_id = name_to_sg_id.get(caller_name) orelse continue;
                const callee_sg_id = name_to_sg_id.get(callee_name) orelse continue;
                _ = sg.addEdge(caller_sg_id, callee_sg_id, null, callee_name) catch {
                    edge_fail_count += 1;
                    continue;
                };
            }

            if (node_fail_count > 0 or edge_fail_count > 0) {
                diag.warn("CallGraph: semantics graph built with {} node failures, {} edge failures", .{ node_fail_count, edge_fail_count });
            }
            if (sg.nodes.items.len == 0) {
                diag.warn("CallGraph: semantics graph is EMPTY — reachesFFIBoundary will always return false", .{});
            }

            ctx.semantics_call_graph = sg;
            diag.info("CallGraph: built semantics CallGraph with {} nodes, {} edges for BFS traversal", .{ sg.nodes.items.len, sg.edges.items.len });
        }
    }

    fn buildNodes(allocator: std.mem.Allocator, mod: c.LLVMModuleRef, nodes: *std.ArrayList(Node)) !void {
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ref = c.LLVMIsAFunction(func);
            if (@intFromPtr(func_ref) == 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);
            if (func_name.len > 1024) continue;
            const is_external = c.LLVMIsDeclaration(func) != 0;

            // Allocate independent copy of the name
            const name_owned = try allocator.dupe(u8, func_name);

            const id = @as(u32, @intCast(nodes.items.len));
            try nodes.append(allocator, .{ .id = id, .name = name_owned, .func_ref = func, .kind = .internal, .is_external = is_external, .is_tainted = false, .tainted_by = null });
        }
    }

    fn buildEdges(allocator: std.mem.Allocator, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        var name_to_idx = std.StringHashMap(u32).init(allocator);
        defer name_to_idx.deinit();
        try name_to_idx.ensureTotalCapacity(@as(u32, @intCast(nodes.items.len)));
        for (nodes.items, 0..) |*node, idx| {
            try name_to_idx.put(node.name, @as(u32, @intCast(idx)));
        }
        for (nodes.items, 0..) |*caller_node, caller_idx| {
            try findCallsInFunction(allocator, caller_node, @as(u32, @intCast(caller_idx)), edges, &name_to_idx);
        }
    }

    fn findCallsInFunction(allocator: std.mem.Allocator, caller_node: *Node, caller_idx: u32, edges: *std.ArrayList(Edge), name_to_idx: *std.StringHashMap(u32)) !void {
        var bb = c.LLVMGetFirstBasicBlock(caller_node.func_ref);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(called_name_ptr) != 0) {
                        const called_name = std.mem.span(called_name_ptr);
                        if (name_to_idx.get(called_name)) |callee_idx| {
                            try edges.append(allocator, .{
                                .caller = caller_idx,
                                .callee = callee_idx,
                                .call_inst = @intFromPtr(inst),
                            });
                        }
                    } else {
                        const module = c.LLVMGetGlobalParent(caller_node.func_ref);
                        const candidates = try resolveIndirectCall(allocator, module, inst);
                        defer allocator.free(candidates);

                        for (candidates) |candidate| {
                            const candidate_val = @as(c.LLVMValueRef, @ptrFromInt(candidate));
                            const candidate_name_ptr = c.LLVMGetValueName(candidate_val);
                            if (@intFromPtr(candidate_name_ptr) == 0) continue;
                            const candidate_name = std.mem.span(candidate_name_ptr);
                            if (name_to_idx.get(candidate_name)) |callee_idx| {
                                try edges.append(allocator, .{
                                    .caller = caller_idx,
                                    .callee = callee_idx,
                                    .call_inst = @intFromPtr(inst),
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    fn classifyFunctions(nodes: *std.ArrayList(Node)) void {
        for (nodes.items) |*node| {
            if (isLibC(node.name)) {
                node.kind = .libc;
            } else if (node.is_external) {
                node.kind = .external_unknown;
            } else {
                node.kind = .internal;
            }
        }
    }

    fn isSource(func_name: []const u8) bool {
        for (SOURCE_FUNCTIONS) |source| {
            if (std.mem.eql(u8, func_name, source)) {
                return true;
            }
        }
        return false;
    }

    fn markSources(nodes: *std.ArrayList(Node)) void {
        for (nodes.items) |*node| {
            if (isSource(node.name)) {
                node.is_tainted = true;
                node.tainted_by = null;
            }
        }
    }

    fn propagateTaint(allocator: std.mem.Allocator, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        _ = allocator;
        var changed = true;
        var iterations: u32 = 0;
        const max_iterations: u32 = 8;

        while (changed and iterations < max_iterations) {
            changed = false;
            iterations += 1;

            for (edges.items) |edge| {
                if (edge.caller >= nodes.items.len or edge.callee >= nodes.items.len) continue;

                const caller = &nodes.items[edge.caller];
                const callee = &nodes.items[edge.callee];

                if (caller.is_tainted and !callee.is_tainted) {
                    callee.is_tainted = true;
                    callee.tainted_by = caller.id;
                    changed = true;
                }
            }
        }
    }

    fn detectAndReportSinks(ctx: *PassContext, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge), diag: *DiagnosticWriter) !void {
        _ = edges;

        for (nodes.items) |node| {
            if (node.is_tainted and isSink(node.name)) {
                const risk = classifyRisk(node.name);
                const vulnerability_id = ctx.getNextVulnId();

                diag.err("VULNERABILITY OMI-{d:0>3} [{s}] [Confidence: MEDIUM]", .{ vulnerability_id, @tagName(risk) });
                diag.err("Type: tainted_path_to_sink", .{});
                diag.err("Reason: Untrusted data flows to sensitive sink without validation", .{});

                diag.err("Path:", .{});

                var current_id: ?u32 = node.id;
                var path_length: usize = 0;
                var visited = std.AutoHashMap(u32, void).init(ctx.allocator);
                defer visited.deinit();

                while (current_id != null and path_length < 64) : (path_length += 1) {
                    const id = current_id.?;
                    if (visited.contains(id)) {
                        diag.err("  └─> [CYCLE DETECTED]", .{});
                        break;
                    }
                    try visited.put(id, {});

                    if (id >= nodes.items.len) break;
                    const current_node = nodes.items[id];

                    if (path_length == 0) {
                        diag.err("  [Sink] {s}()", .{current_node.name});
                    } else if (current_node.tainted_by == null) {
                        diag.err("  [Source] {s}() - initial taint source", .{current_node.name});
                    } else {
                        diag.err("    └─> {s}()", .{current_node.name});
                    }

                    if (current_node.kind == .external_unknown and path_length > 0) {
                        diag.err("    └─> [FFI Boundary: cross-language call]", .{});
                    }

                    current_id = current_node.tainted_by;
                }

                if (risk == .critical) {
                    diag.err("Impact: Arbitrary command execution possible", .{});
                }
            }
        }
    }

    fn classifyRisk(func_name: []const u8) enum { medium, critical } {
        if (std.mem.eql(u8, func_name, "system") or
            std.mem.indexOf(u8, func_name, "_exec") != null or
            std.mem.eql(u8, func_name, "popen") or
            std.mem.eql(u8, func_name, "exec") or
            std.mem.indexOf(u8, func_name, "execl") != null)
        {
            return .critical;
        }
        return .medium;
    }

    fn isSink(func_name: []const u8) bool {
        for (DANGEROUS_FUNCTIONS) |func| {
            if (std.mem.eql(u8, func_name, func)) {
                return true;
            }
        }
        for (SINK_PATTERNS) |pattern| {
            if (std.mem.eql(u8, func_name, pattern)) {
                return true;
            }
        }
        return false;
    }

    /// R8.2-b: Extract cross-language call edges from the built call graph.
    /// For each edge where caller and callee have different detected languages
    /// (or the callee is external), emit a CrossLangEdge to PassContext for
    /// downstream consumption by ffi_boundary and callback_escape passes.
    fn extractCrossLangEdges(
        ctx: *PassContext,
        nodes: *const std.ArrayList(Node),
        edges: *const std.ArrayList(Edge),
        diag: *DiagnosticWriter,
    ) !void {
        var cross_count: u32 = 0;

        for (edges.items) |edge| {
            if (edge.caller >= nodes.items.len or edge.callee >= nodes.items.len) continue;

            const caller_node = nodes.items[edge.caller];
            const callee_node = nodes.items[edge.callee];

            // Detect language of caller (has LLVM function ref)
            const caller_lang = language_detector.identifyLanguage(caller_node.func_ref);

            // Detect language of callee (may be external — use name-based detection)
            const callee_lang = if (callee_node.is_external)
                language_detector.identifyCalleeLanguage(callee_node.name)
            else
                language_detector.identifyLanguage(callee_node.func_ref);

            // Cross-language condition: languages differ OR callee is external unknown
            const is_cross = caller_lang != callee_lang or callee_node.kind == .external_unknown;
            if (!is_cross) continue;

            // Duplicate names into ctx.allocator so they outlive CallGraphPass's local nodes.
            const caller_name_owned = try ctx.allocator.dupe(u8, caller_node.name);
            errdefer ctx.allocator.free(caller_name_owned);
            const callee_name_owned = try ctx.allocator.dupe(u8, callee_node.name);
            errdefer ctx.allocator.free(callee_name_owned);

            // Extract pointer argument indices from the call instruction
            var ptr_args_list = std.ArrayList(u32).initCapacity(ctx.allocator, 8) catch |e| return e;
            defer ptr_args_list.deinit(ctx.allocator);

            if (edge.call_inst != 0) {
                const call_inst: c.LLVMValueRef = @ptrFromInt(edge.call_inst);
                const opcode = c.LLVMGetInstructionOpcode(call_inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const num_ops = c.LLVMGetNumOperands(call_inst);
                    // Start from 1 to skip the called function itself (operand 0)
                    var i: u32 = 1;
                    while (i < num_ops) : (i += 1) {
                        const op = c.LLVMGetOperand(call_inst, i);
                        if (@intFromPtr(op) == 0) continue;
                        const op_type = c.LLVMTypeOf(op);
                        if (@intFromPtr(op_type) == 0) continue;
                        const type_kind = c.LLVMGetTypeKind(op_type);
                        if (type_kind == c.LLVMPointerTypeKind) {
                            try ptr_args_list.append(ctx.allocator, i - 1); // Store arg index (0-based)
                        }
                    }
                }
            }

            const ptr_args_owned = try ptr_args_list.toOwnedSlice(ctx.allocator);
            errdefer ctx.allocator.free(ptr_args_owned);

            const cross_edge = CrossLangEdge{
                .caller_name = caller_name_owned,
                .callee_name = callee_name_owned,
                .caller_lang = caller_lang,
                .callee_lang = callee_lang,
                .is_ffi_boundary = is_cross,
                .ptr_args = ptr_args_owned,
            };
            try ctx.addCrossLangEdge(cross_edge);
            cross_count += 1;
        }

        if (cross_count > 0) {
            diag.info("CallGraph: extracted {} cross-language edges", .{cross_count});
        }
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "FunctionKind - enum values" {
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(FunctionKind.internal));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(FunctionKind.libc));
    try std.testing.expectEqual(@as(u2, 2), @intFromEnum(FunctionKind.external_unknown));
}

test "LIBC_FUNCTIONS - common functions" {
    const common = &[_][]const u8{ "malloc", "free", "read", "write", "system" };
    for (common) |name| {
        var found = false;
        for (LIBC_FUNCTIONS) |libc| {
            if (std.mem.eql(u8, name, libc)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "SOURCE_FUNCTIONS - contains main" {
    var found = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "SINK_PATTERNS - contains system" {
    var found = false;
    for (SINK_PATTERNS) |p| {
        if (std.mem.eql(u8, p, "system")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "contains helper" {
    try std.testing.expect(contains("system", "system"));
    try std.testing.expect(contains("__libc_system", "system"));
    try std.testing.expect(!contains("malloc", "system"));
}

test "contains - empty strings" {
    try std.testing.expect(contains("", ""));
    try std.testing.expect(!contains("", "a"));
    try std.testing.expect(!contains("a", ""));
}

test "contains - exact match" {
    try std.testing.expect(contains("read", "read"));
    try std.testing.expect(!contains("read", "ead"));
    try std.testing.expect(!contains("read", "rea"));
}

test "classifyRisk - critical sinks" {
    try std.testing.expectEqual(CallGraphPass.classifyRisk("system"), .critical);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("exec"), .critical);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("popen"), .critical);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("__libc_system"), .critical);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("system_r"), .critical);
}

test "classifyRisk - medium sinks" {
    try std.testing.expectEqual(CallGraphPass.classifyRisk("sprintf"), .medium);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("snprintf"), .medium);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("strcpy"), .medium);
}

test "classifyRisk - non-sinks" {
    try std.testing.expectEqual(CallGraphPass.classifyRisk("malloc"), .medium);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("free"), .medium);
    try std.testing.expectEqual(CallGraphPass.classifyRisk("printf"), .medium);
}

test "isSink - matches patterns" {
    try std.testing.expect(CallGraphPass.isSink("system"));
    try std.testing.expect(CallGraphPass.isSink("execve"));
    try std.testing.expect(CallGraphPass.isSink("__strcpy_chk"));
    try std.testing.expect(CallGraphPass.isSink("__snprintf_chk"));
}

test "isSink - no match" {
    try std.testing.expect(!CallGraphPass.isSink("malloc"));
    try std.testing.expect(!CallGraphPass.isSink("printf"));
    try std.testing.expect(!CallGraphPass.isSink("free"));
    try std.testing.expect(!CallGraphPass.isSink("strlen"));
}

test "isSink - partial match edge cases" {
    try std.testing.expect(!CallGraphPass.isSink("systematic"));
    try std.testing.expect(!CallGraphPass.isSink("system_call"));
    try std.testing.expect(!CallGraphPass.isSink("mysystem"));
}

test "FunctionKind - all kinds have values" {
    try std.testing.expectEqual(FunctionKind.internal, FunctionKind.internal);
    try std.testing.expectEqual(FunctionKind.libc, FunctionKind.libc);
    try std.testing.expectEqual(FunctionKind.external_unknown, FunctionKind.external_unknown);
}

test "LIBC_FUNCTIONS - comprehensive check" {
    for (LIBC_FUNCTIONS) |name| {
        try std.testing.expect(name.len > 0);
    }
}

test "SOURCE_FUNCTIONS - comprehensive check" {
    for (SOURCE_FUNCTIONS) |name| {
        try std.testing.expect(name.len > 0);
    }
    try std.testing.expect(SOURCE_FUNCTIONS.len > 0);
}

test "SINK_PATTERNS - comprehensive check" {
    for (SINK_PATTERNS) |pattern| {
        try std.testing.expect(pattern.len > 0);
    }
    try std.testing.expect(SINK_PATTERNS.len > 0);
}

test "SOURCE_FUNCTIONS - main is a source" {
    var found_main = false;
    for (SOURCE_FUNCTIONS) |s| {
        if (std.mem.eql(u8, s, "main")) {
            found_main = true;
        }
    }
    try std.testing.expect(found_main);
}

test "SINK_PATTERNS - system is a sink" {
    var found_system = false;
    for (SINK_PATTERNS) |p| {
        if (contains(p, "system")) {
            found_system = true;
        }
    }
    try std.testing.expect(found_system);
}

test "resolveIndirectCall - null returns empty" {
    const result = try resolveIndirectCall(std.testing.allocator, null, null);
    defer std.testing.allocator.free(result);
    try std.testing.expect(result.len == 0);
}
