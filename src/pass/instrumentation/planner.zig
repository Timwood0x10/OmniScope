//! Instrumentation Planner
//!
//! This pass analyzes facts and generates instrumentation plans
//! for runtime verification. It decides where to insert probes
//! based on static analysis results.

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;

/// Instrumentation planner pass
pub const InstrumentationPlanner = struct {
    pub const name = "instrumentation-planner";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias", "lock", "taint" };

    store: *FactStore,
    query: QueryEngine,
    plan: InstrumentationPlan,

    /// Create a new instrumentation planner
    pub fn init(store: *FactStore) InstrumentationPlanner {
        return .{
            .store = store,
            .query = QueryEngine.init(store),
            .plan = InstrumentationPlan.init(std.heap.page_allocator),
        };
    }

    /// Run the instrumentation planner
    pub fn run(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ctx;
        _ = diag;

        // TODO: Load module from context
        // The actual implementation will:
        // 1. Query facts from analysis passes
        // 2. Identify hotspots (shared memory, loops, etc.)
        // 3. Generate instrumentation plan
        // 4. Store plan for instrumentation pass

        // Example: Generate sample plan
        try self.plan.addInstrumentation(1, 42);
    }

    /// Analyze potential instrumentation points
    fn analyzeInstrumentationPoints(self: *InstrumentationPlanner) !void {
        // Implementation steps:
        // 1. Find alias_may facts with shared memory
        // 2. Find loops (from CFG)
        // 3. Find lock operations
        // 4. Find taint sources and sinks
        // 5. Prioritize based on risk and cost
    }

    /// Check if a location should be instrumented
    fn shouldInstrument(self: *InstrumentationPlanner, location: u32) bool {
        _ = self;
        _ = location;

        // Criteria for instrumentation:
        // - May alias with shared memory
        // - Inside loops
        // - Lock operations
        // - Taint propagation points
        return false;
    }
};

/// Instrumentation plan
pub const InstrumentationPlan = struct {
    allocator: std.mem.Allocator,
    instrumentations: std.ArrayList(Instrumentation),

    const Instrumentation = struct {
        /// Instruction ID to instrument
        inst_id: u32,
        /// Event tag to use
        event_tag: u8,
        /// Location ID
        location: u32,
    };

    /// Create a new instrumentation plan
    pub fn init(allocator: std.mem.Allocator) InstrumentationPlan {
        return .{
            .allocator = allocator,
            .instrumentations = std.ArrayList(Instrumentation).init(allocator),
        };
    }

    /// Deinitialize the instrumentation plan
    pub fn deinit(self: *InstrumentationPlan) void {
        self.instrumentations.deinit();
    }

    /// Add an instrumentation point
    pub fn addInstrumentation(
        self: *InstrumentationPlan,
        inst_id: u32,
        location: u32,
    ) !void {
        try self.instrumentations.append(.{
            .inst_id = inst_id,
            .event_tag = 0, // Default tag
            .location = location,
        });
    }

    /// Get the number of instrumentation points
    pub fn count(self: *const InstrumentationPlan) usize {
        return self.instrumentations.items.len;
    }

    /// Get an instrumentation point by index
    pub fn get(self: *const InstrumentationPlan, index: usize) ?Instrumentation {
        if (index >= self.instrumentations.items.len) return null;
        return self.instrumentations.items[index];
    }

    /// Clear the instrumentation plan
    pub fn clear(self: *InstrumentationPlan) void {
        self.instrumentations.clearRetainingCapacity();
    }

    /// Merge another instrumentation plan
    pub fn merge(self: *InstrumentationPlan, other: *const InstrumentationPlan) !void {
        for (other.instrumentations.items) |inst| {
            try self.instrumentations.append(inst);
        }
    }

    /// Optimize the instrumentation plan
    /// Remove redundant instrumentations
    pub fn optimize(self: *InstrumentationPlan) !void {
        // Remove duplicate instrumentations
        var seen = std.AutoHashMap(usize, bool).init(self.allocator);
        defer seen.deinit();

        var optimized = std.ArrayList(Instrumentation).init(self.allocator);

        for (self.instrumentations.items) |inst| {
            const key = @as(usize, inst.inst_id) << 32 | @as(usize, inst.event_tag);
            if (!seen.contains(key)) {
                try seen.put(key, true);
                try optimized.append(inst);
            }
        }

        self.instrumentations.deinit();
        self.instrumentations = optimized;
    }
};

test "InstrumentationPlanner - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const planner = InstrumentationPlanner.init(&store);
    _ = planner;
}

test "InstrumentationPlanner - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-planner-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "cfg", "dfg", "alias", "lock", "taint" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "InstrumentationPlan - init and deinit" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 0), plan.count());
}

test "InstrumentationPlan - add instrumentation" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    try plan.addInstrumentation(1, 42);
    try std.testing.expectEqual(@as(usize, 1), plan.count());

    const inst = plan.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), inst.inst_id);
    try std.testing.expectEqual(@as(u32, 42), inst.location);
}

test "InstrumentationPlan - get out of bounds" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    const inst = plan.get(0);
    try std.testing.expect(inst == null);
}

test "InstrumentationPlan - clear" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    try plan.addInstrumentation(1, 42);
    try plan.addInstrumentation(2, 43);
    try std.testing.expectEqual(@as(usize, 2), plan.count());

    plan.clear();
    try std.testing.expectEqual(@as(usize, 0), plan.count());
}

test "InstrumentationPlan - merge" {
    var plan1 = InstrumentationPlan.init(std.testing.allocator);
    defer plan1.deinit();

    var plan2 = InstrumentationPlan.init(std.testing.allocator);
    defer plan2.deinit();

    try plan1.addInstrumentation(1, 42);
    try plan2.addInstrumentation(2, 43);

    try plan1.merge(&plan2);
    try std.testing.expectEqual(@as(usize, 2), plan1.count());
}

test "InstrumentationPlan - optimize" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    // Add duplicate instrumentations
    try plan.addInstrumentation(1, 42);
    try plan.addInstrumentation(1, 42);
    try plan.addInstrumentation(2, 43);
    try plan.addInstrumentation(1, 42);

    try std.testing.expectEqual(@as(usize, 4), plan.count());

    try plan.optimize();
    try std.testing.expectEqual(@as(usize, 2), plan.count());
}

test "InstrumentationPlan - large scale" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    const count = 10000;

    // Add many instrumentations
    for (0..count) |i| {
        try plan.addInstrumentation(@intCast(i), @intCast(i * 2));
    }

    try std.testing.expectEqual(@as(usize, count), plan.count());

    // Verify data integrity
    for (0..count) |i| {
        const inst = plan.get(i).?;
        try std.testing.expectEqual(@as(u32, @intCast(i)), inst.inst_id);
        try std.testing.expectEqual(@as(u32, @intCast(i * 2)), inst.location);
    }
}
