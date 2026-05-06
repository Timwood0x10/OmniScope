//! Pass manager for scheduling and executing passes
//!
//! This module manages pass registration, dependency resolution,
//! and execution in the correct order using topological sorting.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Pass = @import("pass.zig").Pass;
const PassContext = @import("pass.zig").PassContext;
const DiagnosticWriter = @import("pass.zig").DiagnosticWriter;
const PassKind = @import("pass.zig").PassKind;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;

/// Dependency resolution error
pub const DependencyError = error{
    CycleDetected,
    MissingDependency,
};

/// Pass manager
pub const PassManager = struct {
    allocator: Allocator,
    passes: std.ArrayList(PassEntry),
    pass_map: std.StringHashMap(usize), // name -> index
    resolved_order: ?[]usize, // indices in execution order
    execution_names: ?[]const []const u8, // cached pass names in order

    const PassEntry = struct {
        name: []const u8,
        kind: PassKind,
        deps: []const []const u8,
        run_fn: *const fn (ctx: *PassContext, diag: *DiagnosticWriter) anyerror!void,
    };

    /// Create a new pass manager
    pub fn init(allocator: Allocator) PassManager {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(PassEntry).initCapacity(allocator, 0) catch unreachable,
            .pass_map = std.StringHashMap(usize).init(allocator),
            .resolved_order = null,
            .execution_names = null,
        };
    }

    /// Deinitialize the pass manager
    pub fn deinit(self: *PassManager) void {
        if (self.execution_names) |names| {
            self.allocator.free(names);
        }
        if (self.resolved_order) |order| {
            self.allocator.free(order);
        }
        self.pass_map.deinit();
        self.passes.deinit(self.allocator);
    }

    /// Register a pass with the manager
    pub fn registerPass(
        self: *PassManager,
        comptime T: type,
    ) !void {
        const pass_type = Pass(T);
        const entry = PassEntry{
            .name = pass_type.name,
            .kind = pass_type.kind,
            .deps = pass_type.deps,
            .run_fn = pass_type.run,
        };
        try self.passes.append(self.allocator, entry);
        try self.pass_map.put(entry.name, self.passes.items.len - 1);
        // Invalidate resolved order when new pass is registered
        self.invalidateResolvedOrder();
    }

    /// Invalidate resolved order (needs to be recomputed)
    fn invalidateResolvedOrder(self: *PassManager) void {
        if (self.execution_names) |names| {
            self.allocator.free(names);
            self.execution_names = null;
        }
        if (self.resolved_order) |order| {
            self.allocator.free(order);
            self.resolved_order = null;
        }
    }

    /// Resolve dependencies using Kahn's algorithm (topological sort)
    ///
    /// Returns:
    ///   - []const []const u8: Execution order (pass names)
    ///
    /// Errors:
    ///   - error.CycleDetected: Circular dependency found
    ///   - error.MissingDependency: A dependency is not registered
    pub fn resolveDependencies(self: *PassManager) ![]const []const u8 {
        // Build adjacency list and in-degree count
        const num_passes = self.passes.items.len;
        var in_degree = try self.allocator.alloc(usize, num_passes);
        defer self.allocator.free(in_degree);

        var adjacency = try std.ArrayList(std.ArrayList(usize)).initCapacity(self.allocator, num_passes);
        defer {
            for (adjacency.items) |*list| {
                list.deinit(self.allocator);
            }
            adjacency.deinit(self.allocator);
        }

        // Initialize in-degree and adjacency
        for (0..num_passes) |i| {
            in_degree[i] = 0;
            try adjacency.append(self.allocator, try std.ArrayList(usize).initCapacity(self.allocator, 0));
        }

        // Build graph
        for (0..num_passes) |i| {
            const pass = self.passes.items[i];
            for (pass.deps) |dep_name| {
                // Find dependency index
                const dep_idx = self.pass_map.get(dep_name) orelse {
                    // Dependency not found - check if it's a special case
                    // For now, we assume all dependencies must be registered
                    return error.MissingDependency;
                };
                // Add edge: dep_idx -> i
                try adjacency.items[dep_idx].append(self.allocator, i);
                in_degree[i] += 1;
            }
        }

        // Kahn's algorithm
        var queue = try std.ArrayList(usize).initCapacity(self.allocator, num_passes);
        defer queue.deinit(self.allocator);

        // Find all nodes with in-degree 0
        for (0..num_passes) |i| {
            if (in_degree[i] == 0) {
                try queue.append(self.allocator, i);
            }
        }

        var result = try std.ArrayList(usize).initCapacity(self.allocator, num_passes);
        defer result.deinit(self.allocator);

        while (queue.items.len > 0) {
            // Get next node (FIFO)
            const node = queue.orderedRemove(0);
            try result.append(self.allocator, node);

            // Reduce in-degree of neighbors
            for (adjacency.items[node].items) |neighbor| {
                in_degree[neighbor] -= 1;
                if (in_degree[neighbor] == 0) {
                    try queue.append(self.allocator, neighbor);
                }
            }
        }

        // Check for cycle
        if (result.items.len != num_passes) {
            return error.CycleDetected;
        }

        // Store resolved order
        self.resolved_order = try result.toOwnedSlice(self.allocator);

        // Build and cache execution names
        var names = try std.ArrayList([]const u8).initCapacity(self.allocator, num_passes);
        for (self.resolved_order.?) |idx| {
            try names.append(self.allocator, self.passes.items[idx].name);
        }
        self.execution_names = try names.toOwnedSlice(self.allocator);

        // Return cached names
        return self.execution_names.?;
    }

    /// Get execution order
    ///
    /// Returns:
    ///   - []const []const u8: Pass names in execution order, or null if not resolved
    pub fn getExecutionOrder(self: *PassManager) ?[]const []const u8 {
        return self.execution_names;
    }

    /// Execute all registered passes in dependency order
    pub fn run(self: *PassManager, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Resolve dependencies if not already done
        if (self.resolved_order == null) {
            _ = try self.resolveDependencies();
        }

        // Execute in resolved order with graceful degradation (v0.1.6)
        var pass_failures: usize = 0;
        for (self.resolved_order.?) |idx| {
            const pass_name = self.passes.items[idx].name;
            const t0 = std.time.nanoTimestamp();
            self.passes.items[idx].run_fn(ctx, diag) catch |err| {
                diag.warn("PassManager: pass '{s}' failed with error: {any}, degrading gracefully", .{ pass_name, err });
                pass_failures += 1;
                // Continue running remaining passes
            };
            const elapsed_ns = @max(@as(i128, 0), std.time.nanoTimestamp() - t0);
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            if (elapsed_ms > 10) {
                diag.info("[PERF] Pass '{s}: {d} ms", .{ pass_name, @as(u32, @intFromFloat(elapsed_ms)) });
            }
        }

        if (pass_failures > 0) {
            diag.info("PassManager: completed with {} degraded passes out of {}", .{ pass_failures, self.resolved_order.?.len });
        }
    }

    /// Get the number of registered passes
    pub fn count(self: *const PassManager) usize {
        return self.passes.items.len;
    }
};

test "PassManager - init and deinit" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();
    try std.testing.expectEqual(@as(usize, 0), manager.count());
}

test "PassManager - register pass" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(TestPass);
    try std.testing.expectEqual(@as(usize, 1), manager.count());
}

test "PassManager - run passes" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(TestPass);

    var ctx = try PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();
    var diag = DiagnosticWriter{ .allocator = std.testing.allocator };
    try manager.run(&ctx, &diag);
}

test "PassManager - resolve dependencies - simple chain" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassC = struct {
        pub const name = "C";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"B"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(PassC);
    try manager.registerPass(PassA);
    try manager.registerPass(PassB);

    const order = try manager.resolveDependencies();

    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqualStrings("A", order[0]);
    try std.testing.expectEqualStrings("B", order[1]);
    try std.testing.expectEqualStrings("C", order[2]);
}

test "PassManager - resolve dependencies - diamond" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassC = struct {
        pub const name = "C";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassD = struct {
        pub const name = "D";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{ "B", "C" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(PassD);
    try manager.registerPass(PassC);
    try manager.registerPass(PassA);
    try manager.registerPass(PassB);

    const order = try manager.resolveDependencies();

    try std.testing.expectEqual(@as(usize, 4), order.len);
    try std.testing.expectEqualStrings("A", order[0]);
    // B and C can be in any order, both must be before D
    var found_b = false;
    var found_c = false;
    for (order) |pass_name| {
        if (std.mem.eql(u8, pass_name, "B")) found_b = true;
        if (std.mem.eql(u8, pass_name, "C")) found_c = true;
    }
    try std.testing.expect(found_b);
    try std.testing.expect(found_c);
    try std.testing.expectEqualStrings("D", order[3]);
}

test "PassManager - detect cycle" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"B"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(PassA);
    try manager.registerPass(PassB);

    const result = manager.resolveDependencies();
    try std.testing.expectError(error.CycleDetected, result);
}

test "PassManager - missing dependency" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"NonExistent"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(PassA);

    const result = manager.resolveDependencies();
    try std.testing.expectError(error.MissingDependency, result);
}

test "PassManager - get execution order" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(PassB);
    try manager.registerPass(PassA);

    // Before resolving
    try std.testing.expect(manager.getExecutionOrder() == null);

    // After resolving
    _ = try manager.resolveDependencies();
    const order = manager.getExecutionOrder().?;

    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings("A", order[0]);
    try std.testing.expectEqualStrings("B", order[1]);
}
