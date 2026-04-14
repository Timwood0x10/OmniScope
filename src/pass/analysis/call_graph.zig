//! Call Graph Analysis Pass
//!
//! Builds a call graph from LLVM IR, recording function relationships
//! and classifying functions by kind (internal, libc, external_unknown).
//!
//! This pass is stateless - it analyzes the IR directly and emits diagnostics.

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

pub const FunctionKind = enum {
    internal,
    libc,
    external_unknown,
};

pub const LIBC_FUNCTIONS = &[_][]const u8{
    "malloc",
    "free",
    "calloc",
    "realloc",
    "read",
    "write",
    "open",
    "close",
    "system",
    "exec",
    "popen",
    "strlen",
    "strcpy",
    "strncpy",
    "sprintf",
    "snprintf",
    "gets",
    "fgets",
    "scanf",
    "getenv",
    "getline",
};

pub const SOURCE_FUNCTIONS = &[_][]const u8{
    "read",
    "recv",
    "gets",
    "scanf",
    "main",
};

pub const SINK_PATTERNS = &[_][]const u8{
    "system",
    "exec",
    "popen",
    "sprintf",
    "snprintf",
    "strcpy",
    "strncpy",
};

pub const Node = struct {
    id: u32,
    name: []const u8,
    func_ref: llvm.LLVMValueRef,
    kind: FunctionKind,
    isExternal: bool,
    isTainted: bool,
    taintedBy: ?u32,
};

pub const Edge = struct {
    caller: u32,
    callee: u32,
};

pub const CallGraphPass = struct {
    pub const name = "call-graph";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;

        var nodes: std.ArrayList(Node) = .{};
        errdefer nodes.deinit(ctx.allocator);

        var edges: std.ArrayList(Edge) = .{};
        errdefer edges.deinit(ctx.allocator);

        try buildNodes(ctx.allocator, mod, &nodes);
        try buildEdges(ctx.allocator, &nodes, &edges);
        classifyFunctions(&nodes);
        markSources(&nodes);
        try propagateTaint(ctx.allocator, &nodes, &edges);
        try detectAndReportSinks(&nodes, &edges, diag);
    }

    fn buildNodes(allocator: std.mem.Allocator, mod: llvm.LLVMModuleRef, nodes: *std.ArrayList(Node)) !void {
        var func = llvm.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            const func_ref = llvm.LLVMIsAFunction(func);
            if (@intFromPtr(func_ref) == 0) continue;

            const func_name_ptr = llvm.LLVMGetValueName(func);
            const func_name = std.mem.span(func_name_ptr);
            const is_external = llvm.LLVMIsDeclaration(func) != 0;

            const id = @as(u32, @intCast(nodes.items.len));
            try nodes.append(allocator, .{ .id = id, .name = func_name, .func_ref = func, .kind = .internal, .isExternal = is_external, .isTainted = false, .taintedBy = null });
        }
    }

    fn buildEdges(allocator: std.mem.Allocator, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        for (nodes.items, 0..) |*caller_node, caller_idx| {
            try findCallsInFunction(allocator, caller_node, @as(u32, @intCast(caller_idx)), nodes, edges);
        }
    }

    fn findCallsInFunction(allocator: std.mem.Allocator, caller_node: *Node, caller_idx: u32, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        var bb = llvm.LLVMGetFirstBasicBlock(caller_node.func_ref);
        while (@intFromPtr(bb) != 0) : (bb = llvm.LLVMGetNextBasicBlock(bb)) {
            var inst = llvm.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = llvm.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(llvm.LLVMIsACallInst(inst)) != 0) {
                    const called_val = llvm.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) != 0) {
                        const called_name_ptr = llvm.LLVMGetValueName(called_val);
                        if (@intFromPtr(called_name_ptr) != 0) {
                            const called_name = std.mem.span(called_name_ptr);
                            for (nodes.items, 0..) |*callee_node, callee_idx| {
                                if (std.mem.eql(u8, callee_node.name, called_name)) {
                                    try edges.append(allocator, .{ .caller = caller_idx, .callee = @as(u32, @intCast(callee_idx)) });
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn classifyFunctions(nodes: *std.ArrayList(Node)) void {
        for (nodes.items) |*node| {
            if (isLibCName(node.name)) {
                node.kind = .libc;
            } else if (node.isExternal) {
                node.kind = .external_unknown;
            } else {
                node.kind = .internal;
            }
        }
    }

    fn isLibCName(func_name: []const u8) bool {
        for (LIBC_FUNCTIONS) |libc_name| {
            if (std.mem.eql(u8, func_name, libc_name)) {
                return true;
            }
        }
        return false;
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
                node.isTainted = true;
                node.taintedBy = null;
            }
        }
    }

    fn propagateTaint(allocator: std.mem.Allocator, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        var changed = true;
        var iterations: u32 = 0;
        const max_iterations: u32 = 8;

        while (changed and iterations < max_iterations) {
            changed = false;
            iterations += 1;

            var visited = std.AutoHashMap(u32, void).init(allocator);
            defer visited.deinit();

            for (edges.items) |edge| {
                if (edge.caller >= nodes.items.len or edge.callee >= nodes.items.len) continue;

                if (visited.contains(edge.callee)) continue;
                visited.put(edge.callee, {}) catch continue;

                const caller = &nodes.items[edge.caller];
                var callee = &nodes.items[edge.callee];

                if (caller.isTainted and !callee.isTainted) {
                    callee.isTainted = true;
                    callee.taintedBy = caller.id;
                    changed = true;
                }
            }
        }
    }

    fn detectAndReportSinks(nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge), diag: *DiagnosticWriter) !void {
        _ = edges;
        for (nodes.items) |node| {
            if (node.isTainted and isSink(node.name)) {
                const risk = classifyRisk(node.name);
                if (risk == .critical) {
                    diag.err("Data flow to sink: {s}", .{node.name});
                    if (node.taintedBy) |source_id| {
                        if (source_id < nodes.items.len) {
                            diag.err("  Source: {s}", .{nodes.items[source_id].name});
                        }
                    }
                } else {
                    diag.warn("Data flow to sink: {s}", .{node.name});
                }
            }
        }
    }

    fn classifyRisk(func_name: []const u8) enum { medium, critical } {
        if (contains(func_name, "system") or contains(func_name, "exec") or contains(func_name, "popen")) {
            return .critical;
        }
        return .medium;
    }

    fn isSink(func_name: []const u8) bool {
        for (SINK_PATTERNS) |pattern| {
            if (contains(func_name, pattern)) {
                return true;
            }
        }
        return false;
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
