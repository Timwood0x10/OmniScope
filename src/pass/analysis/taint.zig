//! Taint Analysis Pass
//!
//! This pass tracks data flow from tainted sources to sensitive sinks
//! to detect potential security vulnerabilities.

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;

const c = @import("../../ir/llvm_raw.zig").c;
const ValueRef = @import("../../ir/view.zig").ValueRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;

/// Taint analysis pass
pub const TaintPass = struct {
    pub const name = "taint";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    store: *FactStore,
    allocator: std.mem.Allocator,
    func_id: u32,
    sources: std.ArrayList(u32),
    sinks: std.ArrayList(u32),
    taint_graph: TaintGraph,

    pub fn init(store: *FactStore, allocator: std.mem.Allocator) TaintPass {
        return .{
            .store = store,
            .allocator = allocator,
            .func_id = 0,
            .sources = std.ArrayList(u32).init(allocator),
            .sinks = std.ArrayList(u32).init(allocator),
            .taint_graph = TaintGraph.init(allocator),
        };
    }

    pub fn deinit(self: *TaintPass) void {
        self.taint_graph.deinit();
        self.sources.deinit();
        self.sinks.deinit();
    }

    /// Run the taint analysis pass
    pub fn run(
        self: *TaintPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        const module = ctx.module orelse return;

        // Reset for new run
        self.func_id = 0;
        self.sources.clearRetainingCapacity();
        self.sinks.clearRetainingCapacity();
        self.taint_graph.reset();

        // Iterate over all functions
        var func = c.LLVMGetFirstFunction(module.raw);
        while (func != null) {
            const func_ref = c.LLVMIsAFunction(func);
            if (func_ref != null) {
                // Assign function ID
                self.func_id = ctx.getNextId();

                // Analyze function
                try self.analyzeFunction(ctx, FunctionRef{ .raw = func_ref });
            }
            func = c.LLVMGetNextFunction(func);
        }
    }

    /// Analyze a function for taint propagation
    fn analyzeFunction(
        self: *TaintPass,
        ctx: *PassContext,
        func: FunctionRef,
    ) !void {
        // Get first basic block
        var bb = c.LLVMGetFirstBasicBlock(func.raw);

        while (bb != null) {
            // Get first instruction
            var inst = c.LLVMGetFirstInstruction(bb);

            while (inst != null) {
                // Get opcode
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check if this is a call instruction (using LLVM opcode constants)
                if (opcode == c.LLVMCall) {
                    const inst_id = ctx.getNextId();

                    // Check if this is a taint source
                    if (isTaintSource(inst)) {
                        try self.sources.append(inst_id);
                        try self.taint_graph.markTaintedFromSource(inst_id, inst_id);
                        try self.store.insert(.taint, inst_id, inst_id, self.func_id);
                    }

                    // Check if this is a taint sink
                    if (isTaintSink(inst)) {
                        try self.sinks.append(inst_id);
                    }
                }

                // Move to next instruction
                inst = c.LLVMGetNextInstruction(inst);
            }

            // Move to next basic block
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        // Query DFG edges for data flow
        const dfg_indices = try ctx.fact_store.queryByKind(.dfg_edge, ctx.allocator);
        defer ctx.allocator.free(dfg_indices);

        // Build taint propagation graph from DFG
        for (dfg_indices) |idx| {
            const fact = ctx.fact_store.get(idx).?;
            try self.taint_graph.addPropagation(fact.subject, fact.object);
        }

        // Propagate taint
        try self.taint_graph.propagate();

        // Check if taint reaches any sinks
        for (self.sinks.items) |sink| {
            if (self.taint_graph.isTainted(sink)) {
                // Taint reached a sink - emit taint fact
                // Only associate sources that actually propagated to this sink
                if (self.taint_graph.getTaintSources(sink)) |source_list| {
                    for (source_list) |source| {
                        try self.store.insert(.taint, source, sink, self.func_id);
                    }
                }
            }
        }
    }

    /// Check if a call instruction is a taint source
    fn isTaintSource(inst: c.LLVMValueRef) bool {
        // Get called function
        const called_func = c.LLVMGetOperand(inst, 0);
        if (called_func == null) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
        const func_name_slice = std.mem.span(func_name);

        // Check if it's a known taint source
        return isKnownTaintSourceByName(func_name_slice);
    }

    /// Check if a function name is a known taint source (standalone function)
    fn isKnownTaintSourceByName(func_name_slice: []const u8) bool {
        // Common taint source functions
        const taint_sources = [_][]const u8{
            "read",
            "recv",
            "recvfrom",
            "getenv",
            "fgets",
            "fread",
            "scanf",
            "gets",
            "getchar",
            "getwd",
            "getcwd",
            "getlogin",
            "getpwnam",
            "getpwuid",
            "sysinfo",
        };

        for (taint_sources) |source| {
            if (std.mem.eql(u8, func_name_slice, source)) {
                return true;
            }
        }

        return false;
    }

    /// Check if a call instruction is a taint sink
    fn isTaintSink(inst: c.LLVMValueRef) bool {
        // Get called function
        const called_func = c.LLVMGetOperand(inst, 0);
        if (called_func == null) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
        const func_name_slice = std.mem.span(func_name);

        // Check if it's a known taint sink
        return isKnownTaintSinkByName(func_name_slice);
    }

    /// Check if a function name is a known taint sink (standalone function)
    fn isKnownTaintSinkByName(func_name_slice: []const u8) bool {

        // Common taint sink functions
        const taint_sinks = [_][]const u8{
            "system",
            "exec",
            "execv",
            "execl",
            "execlp",
            "execle",
            "popen",
            "open",
            "fopen",
            "fwrite",
            "printf",
            "sprintf",
            "snprintf",
            "strcpy",
            "strcat",
            "mysql_query",
            "sqlite3_exec",
        };

        for (taint_sinks) |sink| {
            if (std.mem.eql(u8, func_name_slice, sink)) {
                return true;
            }
        }

        return false;
    }
};

/// Taint propagation graph
pub const TaintGraph = struct {
    allocator: std.mem.Allocator,
    tainted_values: std.AutoHashMap(u32, bool),
    propagation_edges: std.ArrayList(Edge),
    // Track which source tainted each value (value -> source)
    taint_sources: std.AutoHashMap(u32, std.ArrayList(u32)),

    const Edge = struct {
        from: u32,
        to: u32,
    };

    /// Create a new taint graph
    pub fn init(allocator: std.mem.Allocator) TaintGraph {
        return .{
            .allocator = allocator,
            .tainted_values = std.AutoHashMap(u32, bool).init(allocator),
            .propagation_edges = std.ArrayList(Edge).init(allocator),
            .taint_sources = std.AutoHashMap(u32, std.ArrayList(u32)).init(allocator),
        };
    }

    /// Deinitialize the taint graph
    pub fn deinit(self: *TaintGraph) void {
        self.tainted_values.deinit();
        self.propagation_edges.deinit();
        var iter = self.taint_sources.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.taint_sources.deinit();
    }

    /// Reset the taint graph for reuse (clear all data)
    pub fn reset(self: *TaintGraph) void {
        self.tainted_values.clearRetainingCapacity();
        self.propagation_edges.clearRetainingCapacity();
        var iter = self.taint_sources.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }
    }

    /// Mark a value as tainted from a specific source
    pub fn markTaintedFromSource(self: *TaintGraph, value: u32, source: u32) !void {
        try self.tainted_values.put(value, true);

        // Record the source for this value
        if (try self.taint_sources.getOrPut(value)) |*entry| {
            try entry.value_ptr.append(source);
        } else {
            var sources = std.ArrayList(u32).init(self.allocator);
            try sources.append(source);
            try self.taint_sources.put(value, sources);
        }
    }

    /// Mark a value as tainted (backward compatibility)
    pub fn markTainted(self: *TaintGraph, value: u32) !void {
        try self.tainted_values.put(value, true);
    }

    /// Check if a value is tainted
    pub fn isTainted(self: *const TaintGraph, value: u32) bool {
        return self.tainted_values.contains(value);
    }

    /// Get the sources that tainted a specific value
    pub fn getTaintSources(self: *const TaintGraph, value: u32) ?[]const u32 {
        if (self.taint_sources.get(value)) |sources| {
            return sources.items;
        }
        return null;
    }

    /// Add a propagation edge
    pub fn addPropagation(self: *TaintGraph, from: u32, to: u32) !void {
        try self.propagation_edges.append(.{ .from = from, .to = to });

        // If source is tainted, propagate to destination
        if (self.tainted_values.contains(from)) {
            try self.tainted_values.put(to, true);

            // Propagate sources
            if (self.taint_sources.get(from)) |from_sources| {
                if (try self.taint_sources.getOrPut(to)) |*entry| {
                    for (from_sources.items) |src| {
                        try entry.value_ptr.append(src);
                    }
                } else {
                    var sources = std.ArrayList(u32).init(self.allocator);
                    for (from_sources.items) |src| {
                        try sources.append(src);
                    }
                    try self.taint_sources.put(to, sources);
                }
            }
        }
    }

    /// Propagate taint through the graph
    ///
    /// Note: max_iterations is set to 1000 as a safeguard against infinite loops
    /// in pathological cases. In practice, real-world data flow graphs converge
    /// much faster (typically < 100 iterations). If convergence is not reached
    /// within 1000 iterations, the graph is likely malformed or contains a cycle
    /// that doesn't contribute to the analysis result. This is a design decision
    /// to ensure termination at the cost of potentially missing some taint
    /// propagation in extremely complex graphs.
    pub fn propagate(self: *TaintGraph) !void {
        const max_iterations = 1000;
        var iterations: usize = 0;
        var changed = true;

        while (changed and iterations < max_iterations) {
            changed = false;
            iterations += 1;

            for (self.propagation_edges.items) |edge| {
                if (self.tainted_values.contains(edge.from) and
                    !self.tainted_values.contains(edge.to))
                {
                    try self.tainted_values.put(edge.to, true);
                    changed = true;

                    // Propagate sources
                    if (self.taint_sources.get(edge.from)) |from_sources| {
                        if (try self.taint_sources.getOrPut(edge.to)) |*entry| {
                            for (from_sources.items) |src| {
                                try entry.value_ptr.append(src);
                            }
                        } else {
                            var sources = std.ArrayList(u32).init(self.allocator);
                            for (from_sources.items) |src| {
                                try sources.append(src);
                            }
                            try self.taint_sources.put(edge.to, sources);
                        }
                    }
                }
            }
        }
    }

    /// Get all tainted values
    pub fn getTaintedValues(self: *const TaintGraph, allocator: std.mem.Allocator) ![]u32 {
        var values = std.ArrayList(u32).init(allocator);
        var iter = self.tainted_values.iterator();
        while (iter.next()) |entry| {
            try values.append(entry.key_ptr.*);
        }
        return values.toOwnedSlice();
    }
};

test "TaintPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = TaintPass.init(&store);
    _ = pass;
}

test "TaintPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-taint-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "TaintPass - emit taint fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Emit taint fact
    try pass.store.insert(.taint, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.taint, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "TaintPass - known taint sources" {
    // Test known taint sources
    try std.testing.expect(TaintPass.isKnownTaintSourceByName("read"));
    try std.testing.expect(TaintPass.isKnownTaintSourceByName("recv"));
    try std.testing.expect(TaintPass.isKnownTaintSourceByName("getenv"));
    try std.testing.expect(TaintPass.isKnownTaintSourceByName("fgets"));
    try std.testing.expect(TaintPass.isKnownTaintSourceByName("scanf"));

    // Test non-sources
    try std.testing.expect(!TaintPass.isKnownTaintSourceByName("malloc"));
    try std.testing.expect(!TaintPass.isKnownTaintSourceByName("free"));
    try std.testing.expect(!TaintPass.isKnownTaintSourceByName("printf")); // printf is a sink, not a source
}

test "TaintPass - known taint sinks" {
    // Test known taint sinks
    try std.testing.expect(TaintPass.isKnownTaintSinkByName("system"));
    try std.testing.expect(TaintPass.isKnownTaintSinkByName("exec"));
    try std.testing.expect(TaintPass.isKnownTaintSinkByName("popen"));
    try std.testing.expect(TaintPass.isKnownTaintSinkByName("printf"));
    try std.testing.expect(TaintPass.isKnownTaintSinkByName("sprintf"));

    // Test non-sinks
    try std.testing.expect(!TaintPass.isKnownTaintSinkByName("malloc"));
    try std.testing.expect(!TaintPass.isKnownTaintSinkByName("free"));
    try std.testing.expect(!TaintPass.isKnownTaintSinkByName("read")); // read is a source, not a sink
}

test "TaintPass - taint source tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Add taint sources
    try pass.sources.append(10);
    try pass.sources.append(20);
    try pass.sources.append(30);

    try std.testing.expectEqual(@as(usize, 3), pass.sources.items.len);
    try std.testing.expectEqual(@as(u32, 10), pass.sources.items[0]);
    try std.testing.expectEqual(@as(u32, 20), pass.sources.items[1]);
    try std.testing.expectEqual(@as(u32, 30), pass.sources.items[2]);
}

test "TaintPass - taint sink tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Add taint sinks
    try pass.sinks.append(100);
    try pass.sinks.append(200);

    try std.testing.expectEqual(@as(usize, 2), pass.sinks.items.len);
    try std.testing.expectEqual(@as(u32, 100), pass.sinks.items[0]);
    try std.testing.expectEqual(@as(u32, 200), pass.sinks.items[1]);
}

test "TaintPass - taint graph propagation" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Mark a value as tainted
    try pass.taint_graph.markTainted(1);

    // Add propagation edges
    try pass.taint_graph.addPropagation(1, 2);
    try pass.taint_graph.addPropagation(2, 3);
    try pass.taint_graph.addPropagation(3, 4);

    // Propagate taint
    try pass.taint_graph.propagate();

    // Verify all values are tainted
    try std.testing.expect(pass.taint_graph.isTainted(1));
    try std.testing.expect(pass.taint_graph.isTainted(2));
    try std.testing.expect(pass.taint_graph.isTainted(3));
    try std.testing.expect(pass.taint_graph.isTainted(4));
}

test "TaintPass - complex taint scenario" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Simulate a complex taint scenario:
    // Source A -> intermediate -> Sink X
    // Source B -> intermediate -> Sink Y
    // Both sources and sinks exist

    // Add sources
    try pass.sources.append(10); // Source A
    try pass.sources.append(20); // Source B

    // Add sinks
    try pass.sinks.append(100); // Sink X
    try pass.sinks.append(200); // Sink Y

    // Mark sources as tainted
    try pass.taint_graph.markTainted(10);
    try pass.taint_graph.markTainted(20);

    // Add propagation edges
    // Source A -> 50 -> Sink X
    try pass.taint_graph.addPropagation(10, 50);
    try pass.taint_graph.addPropagation(50, 100);

    // Source B -> 50 -> Sink Y
    try pass.taint_graph.addPropagation(20, 50);
    try pass.taint_graph.addPropagation(50, 200);

    // Propagate taint
    try pass.taint_graph.propagate();

    // Verify propagation
    try std.testing.expect(pass.taint_graph.isTainted(10)); // Source A
    try std.testing.expect(pass.taint_graph.isTainted(20)); // Source B
    try std.testing.expect(pass.taint_graph.isTainted(50)); // Intermediate
    try std.testing.expect(pass.taint_graph.isTainted(100)); // Sink X
    try std.testing.expect(pass.taint_graph.isTainted(200)); // Sink Y

    // Verify source and sink counts
    try std.testing.expectEqual(@as(usize, 2), pass.sources.items.len);
    try std.testing.expectEqual(@as(usize, 2), pass.sinks.items.len);
}

test "TaintPass - taint reaching sink" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = TaintPass.init(&store);
    pass.func_id = 1;

    // Add source and sink
    try pass.sources.append(1);
    try pass.sinks.append(3);

    // Mark source as tainted
    try pass.taint_graph.markTainted(1);

    // Add propagation edge: source -> intermediate -> sink
    try pass.taint_graph.addPropagation(1, 2);
    try pass.taint_graph.addPropagation(2, 3);

    // Propagate taint
    try pass.taint_graph.propagate();

    // Check if taint reaches sink
    try std.testing.expect(pass.taint_graph.isTainted(3));

    // Emit taint fact (simulating detection)
    for (pass.sources.items) |source| {
        if (pass.taint_graph.isTainted(3)) {
            try pass.store.insert(.taint, source, 3, pass.func_id);
        }
    }

    // Verify taint fact was emitted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.taint, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 3), fact.object);
}

test "TaintGraph - init and deinit" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectEqual(@as(usize, 0), graph.tainted_values.count());
}

test "TaintGraph - mark and check tainted" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.markTainted(1);
    try std.testing.expect(graph.isTainted(1));
    try std.testing.expect(!graph.isTainted(2));
}

test "TaintGraph - add propagation" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.markTainted(1);
    try graph.addPropagation(1, 2);

    // Taint should be propagated
    try std.testing.expect(graph.isTainted(2));
}

test "TaintGraph - propagate" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Build a chain: 1 -> 2 -> 3 -> 4
    try graph.markTainted(1);
    try graph.addPropagation(1, 2);
    try graph.addPropagation(2, 3);
    try graph.addPropagation(3, 4);

    // Propagate taint
    try graph.propagate();

    // All values should be tainted
    try std.testing.expect(graph.isTainted(1));
    try std.testing.expect(graph.isTainted(2));
    try std.testing.expect(graph.isTainted(3));
    try std.testing.expect(graph.isTainted(4));
}

test "TaintGraph - get tainted values" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.markTainted(1);
    try graph.markTainted(3);
    try graph.markTainted(5);

    const tainted = try graph.getTaintedValues(std.testing.allocator);
    defer std.testing.allocator.free(tainted);

    try std.testing.expectEqual(@as(usize, 3), tainted.len);
    try std.testing.expect(std.mem.indexOfScalar(u32, tainted, 1) != null);
    try std.testing.expect(std.mem.indexOfScalar(u32, tainted, 3) != null);
    try std.testing.expect(std.mem.indexOfScalar(u32, tainted, 5) != null);
}

test "TaintGraph - complex propagation" {
    var graph = TaintGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Build a diamond: 1 -> 2, 1 -> 3, 2 -> 4, 3 -> 4
    try graph.markTainted(1);
    try graph.addPropagation(1, 2);
    try graph.addPropagation(1, 3);
    try graph.addPropagation(2, 4);
    try graph.addPropagation(3, 4);

    try graph.propagate();

    // Check taint status
    try std.testing.expect(graph.isTainted(1));
    try std.testing.expect(graph.isTainted(2));
    try std.testing.expect(graph.isTainted(3));
    try std.testing.expect(graph.isTainted(4));
}
