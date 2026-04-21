//! Call Graph Analysis Pass
//!
//! Builds a call graph from LLVM IR, recording function relationships
//! and classifying functions by kind (internal, libc, external_unknown).
//!
//! This pass is stateless - it analyzes the IR directly and emits diagnostics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("../../ir/llvm_raw.zig").c;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

/// Classification of function origin in the call graph.
/// Used to determine trust boundaries and FFI transitions.
pub const FunctionKind = enum {
    /// Function defined within the analyzed module.
    internal,
    /// Standard C library function (trusted).
    libc,
    /// Function with unknown origin (potential FFI boundary).
    external_unknown,
};

/// List of known libc functions that are considered trusted.
/// These are NOT treated as FFI boundaries even if external.
/// Note: Dangerous functions like system, exec, popen are NOT included here
/// because they should be treated as potential FFI boundaries for security analysis.
pub const LIBC_FUNCTIONS = &[_][]const u8{
    "malloc",
    "free",
    "calloc",
    "realloc",
    "read",
    "write",
    "open",
    "close",
    "strlen",
    "strncpy",
    "snprintf",
    "fgets",
    "getline",
    "memcpy",
    "memmove",
    "memset",
    "memcmp",
    "printf",
    "fprintf",
    "puts",
    "fopen",
    "fclose",
    "fread",
    "fwrite",
};

/// List of dangerous functions that should be flagged as security risks.
/// These are treated as FFI boundaries and potential sinks.
pub const DANGEROUS_FUNCTIONS = &[_][]const u8{
    "system",
    "exec",
    "popen",
    "gets",
    "strcpy",
    "strcat",
    "sprintf",
    "scanf",
    "getenv",
};

pub fn isLibC(func_name: []const u8) bool {
    for (LIBC_FUNCTIONS) |libc_name| {
        if (std.mem.eql(u8, func_name, libc_name)) {
            return true;
        }
    }
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
    if (@intFromPtr(called_val) == 0) return &[_]usize{};

    const call_type = c.LLVMTypeOf(called_val);
    if (@intFromPtr(call_type) == 0) return &[_]usize{};

    var candidates = try std.ArrayList(usize).initCapacity(allocator, 16);
    defer candidates.deinit(allocator);

    var func = c.LLVMGetFirstFunction(mod);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        const func_type = c.LLVMTypeOf(func);
        if (@intFromPtr(func_type) == 0) continue;

        if (c.LLVMCountParams(func) == c.LLVMCountParamTypes(call_type) and
            c.LLVMGetReturnType(call_type) == c.LLVMGetReturnType(func_type))
        {
            var param_match = true;
            const param_count = c.LLVMCountParams(func);
            for (0..param_count) |i| {
                const func_param = c.LLVMGetParam(func, @intCast(i));
                const call_param = c.LLVMGetParam(called_val, @intCast(i));
                if (c.LLVMTypeOf(func_param) != c.LLVMTypeOf(call_param)) {
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

/// Functions that are considered sources of taint.
/// Taint propagation starts from these functions.
pub const SOURCE_FUNCTIONS = &[_][]const u8{
    "read",
    "recv",
    "gets",
    "scanf",
    "main",
};

/// Substring patterns that indicate dangerous sink functions.
/// Used to detect potential vulnerability paths.
pub const SINK_PATTERNS = &[_][]const u8{
    "system",
    "exec",
    "popen",
    "sprintf",
    "snprintf",
    "strcpy",
    "strncpy",
};

/// A node in the call graph representing a function.
pub const Node = struct {
    /// Unique identifier for this node.
    id: u32,
    /// Name of the function (owned by this node).
    name: []const u8,
    /// LLVM value reference to the function.
    func_ref: c.LLVMValueRef,
    /// Classification of the function's origin.
    kind: FunctionKind,
    /// Whether this function is external to the module.
    is_external: bool,
    /// Whether this function is reachable from a taint source.
    is_tainted: bool,
    /// ID of the node that tainted this function (null if source).
    tainted_by: ?u32,

    /// Deinitialize the node and free owned memory
    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// An edge in the call graph representing a call relationship.
pub const Edge = struct {
    /// ID of the caller function.
    caller: u32,
    /// ID of the callee function.
    callee: u32,
};

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
            // Free owned name memory before deinit
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
        try detectAndReportSinks(ctx.allocator, &nodes, &edges, diag);
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
        for (nodes.items, 0..) |*caller_node, caller_idx| {
            try findCallsInFunction(allocator, caller_node, @as(u32, @intCast(caller_idx)), nodes, edges);
        }
    }

    fn findCallsInFunction(allocator: std.mem.Allocator, caller_node: *Node, caller_idx: u32, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge)) !void {
        var bb = c.LLVMGetFirstBasicBlock(caller_node.func_ref);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(called_name_ptr) != 0) {
                        const called_name = std.mem.span(called_name_ptr);
                        for (nodes.items, 0..) |*callee_node, callee_idx| {
                            if (std.mem.eql(u8, callee_node.name, called_name)) {
                                try edges.append(allocator, .{ .caller = caller_idx, .callee = @as(u32, @intCast(callee_idx)) });
                                break;
                            }
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

                            for (nodes.items, 0..) |*callee_node, callee_idx| {
                                if (std.mem.eql(u8, callee_node.name, candidate_name)) {
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
        var changed = true;
        var iterations: u32 = 0;
        const max_iterations: u32 = 8;

        while (changed and iterations < max_iterations) {
            changed = false;
            iterations += 1;

            // Track processed callees in this iteration to avoid redundant processing
            var processed = std.AutoHashMap(u32, void).init(allocator);
            defer processed.deinit();

            for (edges.items) |edge| {
                if (edge.caller >= nodes.items.len or edge.callee >= nodes.items.len) continue;

                const caller = &nodes.items[edge.caller];
                const callee = &nodes.items[edge.callee];

                // Only propagate taint if caller is tainted and callee is not yet tainted
                if (caller.is_tainted and !callee.is_tainted) {
                    callee.is_tainted = true;
                    callee.tainted_by = caller.id;
                    changed = true;
                }

                // Mark callee as processed after handling to allow multiple paths to reach it
                try processed.put(edge.callee, {});
            }
        }
    }

    fn detectAndReportSinks(allocator: std.mem.Allocator, nodes: *std.ArrayList(Node), edges: *std.ArrayList(Edge), diag: *DiagnosticWriter) !void {
        _ = edges;
        var vulnerability_id: u32 = 0;

        for (nodes.items) |node| {
            if (node.is_tainted and isSink(node.name)) {
                const risk = classifyRisk(node.name);
                vulnerability_id += 1;

                diag.err("VULNERABILITY OMI-{d:0>3}", .{vulnerability_id});
                diag.err("Severity: {s}", .{@tagName(risk)});

                diag.err("Path:", .{});

                var current_id: ?u32 = node.id;
                var path_length: usize = 0;
                var visited = std.AutoHashMap(u32, void).init(allocator);
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
            std.mem.eql(u8, func_name, "exec") or
            std.mem.eql(u8, func_name, "popen"))
        {
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
        for (DANGEROUS_FUNCTIONS) |func| {
            if (contains(func_name, func)) {
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
    try std.testing.expect(CallGraphPass.isSink("system_call"));
    try std.testing.expect(CallGraphPass.isSink("mysystem"));
    try std.testing.expect(!CallGraphPass.isSink("systematic"));
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
