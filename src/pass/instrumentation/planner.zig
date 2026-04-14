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

/// Event tags for instrumentation
pub const EventTag = enum(u8) {
    /// Memory allocation
    alloc = 1,
    /// Memory free
    free = 2,
    /// Lock acquire
    lock_acquire = 3,
    /// Lock release
    lock_release = 4,
    /// Taint source
    taint_source = 5,
    /// Taint sink
    taint_sink = 6,
    /// Taint propagation
    taint_prop = 7,
    /// Alias check
    alias_check = 8,
    /// Loop entry
    loop_entry = 9,
    /// Loop exit
    loop_exit = 10,
};

/// Instrumentation priority levels
pub const Priority = enum(u8) {
    /// Critical - must instrument (e.g., deadlock detection)
    critical = 3,
    /// High - very important (e.g., taint sources)
    high = 2,
    /// Medium - useful (e.g., alias checks)
    medium = 1,
    /// Low - optional (e.g., loop exits)
    low = 0,
};

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
        // Query facts from analysis passes
        try self.analyzeInstrumentationPoints(ctx, diag);

        // Optimize the instrumentation plan
        try self.plan.optimize();
    }

    /// Analyze potential instrumentation points
    fn analyzeInstrumentationPoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        // Step 1: Analyze and score each potential point
        try self.analyzeAndScorePoints(ctx, diag);

        // Step 2: Sort by priority (highest first)
        try self.plan.sortByPriority();

        // Step 3: Select top N points based on budget
        try self.plan.selectTopPoints(ctx, diag);
    }

    /// Analyze and score potential instrumentation points
    fn analyzeAndScorePoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        // 1. Find alias_may facts with shared memory (high priority)
        try self.analyzeAliasPoints(ctx, diag);

        // 2. Find loops (from CFG) - inside loops get higher score
        try self.analyzeLoopPoints(ctx, diag);

        // 3. Find lock operations (highest priority)
        try self.analyzeLockPoints(ctx, diag);

        // 4. Find taint sources and sinks (high priority)
        try self.analyzeTaintPoints(ctx, diag);

        // 5. Find hotspots (high frequency execution paths)
        try self.analyzeHotspots(ctx, diag);
    }

    /// Analyze hotspots (high frequency execution paths)
    fn analyzeHotspots(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        // Query all cfg_edge facts to find frequently executed paths
        const cfg_facts = self.query.queryByKind(.cfg_edge, ctx.allocator) catch return;
        defer ctx.allocator.free(cfg_facts);

        // Count how many successors each basic block has
        var successor_counts = std.AutoHashMap(u32, u32).init(ctx.allocator);
        defer successor_counts.deinit();

        for (cfg_facts) |fact| {
            const count = successor_counts.get(fact.subject) orelse 0;
            try successor_counts.put(fact.subject, count + 1);
        }

        // Blocks with many successors (>=3) are likely hotspots (switch statements, etc.)
        var iter = successor_counts.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* >= 3) {
                // This is a hotspot, instrument with high priority
                try self.plan.addInstrumentationWithPriority(
                    entry.key_ptr.*,
                    0,
                    @intFromEnum(EventTag.alias_check),
                    Priority.high,
                );
            }
        }
    }

    /// Analyze alias points for instrumentation
    fn analyzeAliasPoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        // Query all alias_may facts
        const alias_facts = self.query.queryByKind(.alias_may, ctx.allocator) catch return;
        defer ctx.allocator.free(alias_facts);

        // For each alias_may fact, instrument both pointers
        for (alias_facts) |fact| {
            // Instrument subject pointer with alias_check tag
            try self.plan.addInstrumentationWithTag(
                fact.subject,
                fact.context,
                @intFromEnum(EventTag.alias_check),
            );

            // Instrument object pointer with alias_check tag
            try self.plan.addInstrumentationWithTag(
                fact.object,
                fact.context,
                @intFromEnum(EventTag.alias_check),
            );
        }
    }

    /// Analyze loop points for instrumentation
    fn analyzeLoopPoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        // Query all cfg_edge facts to identify loops
        const cfg_facts = self.query.queryByKind(.cfg_edge, ctx.allocator) catch return;
        defer ctx.allocator.free(cfg_facts);

        // Build a map of back edges (edges that point to earlier blocks)
        var back_edges = std.AutoHashMap(u32, u32).init(ctx.allocator);
        defer back_edges.deinit();

        // Simple heuristic: if we see cfg_edge(a, b) where b < a, it's a back edge
        for (cfg_facts) |fact| {
            if (fact.object < fact.subject) {
                try back_edges.put(fact.subject, fact.object);
            }
        }

        // Instrument back edges (loop headers) with loop_entry tag
        var iter = back_edges.iterator();
        while (iter.next()) |entry| {
            try self.plan.addInstrumentationWithTag(
                entry.key_ptr.*,
                entry.value_ptr.*,
                @intFromEnum(EventTag.loop_entry),
            );
        }

        // Instrument loop exits (forward edges that leave the loop)
        // Simple heuristic: if we see cfg_edge(a, b) where b > a and b is not in back edges
        for (cfg_facts) |fact| {
            if (fact.object > fact.subject) {
                // Check if this is a loop exit (not a back edge)
                const is_back_edge = back_edges.contains(fact.subject);
                if (!is_back_edge) {
                    // Could be a loop exit, but we need more context
                    // For now, instrument as loop_exit
                    try self.plan.addInstrumentationWithTag(
                        fact.subject,
                        fact.context,
                        @intFromEnum(EventTag.loop_exit),
                    );
                }
            }
        }
    }

    /// Analyze lock points for instrumentation
    fn analyzeLockPoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        // Query all lock_acquire facts
        const lock_acquire_facts = self.query.queryByKind(.lock_acquire, ctx.allocator) catch return;
        defer ctx.allocator.free(lock_acquire_facts);

        // Instrument all lock acquire points
        for (lock_acquire_facts) |fact| {
            try self.plan.addInstrumentationWithTag(
                fact.subject,
                fact.context,
                @intFromEnum(EventTag.lock_acquire),
            );
        }

        // Query all lock_release facts
        const lock_release_facts = self.query.queryByKind(.lock_release, ctx.allocator) catch return;
        defer ctx.allocator.free(lock_release_facts);

        // Instrument all lock release points
        for (lock_release_facts) |fact| {
            try self.plan.addInstrumentationWithTag(
                fact.subject,
                fact.context,
                @intFromEnum(EventTag.lock_release),
            );
        }
    }

    /// Analyze taint points for instrumentation
    fn analyzeTaintPoints(
        self: *InstrumentationPlanner,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;

        // Query all taint facts
        const taint_facts = self.query.queryByKind(.taint, ctx.allocator) catch return;
        defer ctx.allocator.free(taint_facts);

        // Instrument all taint sources and sinks
        for (taint_facts) |fact| {
            // Instrument source with taint_source tag
            try self.plan.addInstrumentationWithTag(
                fact.subject,
                fact.context,
                @intFromEnum(EventTag.taint_source),
            );

            // Instrument sink with taint_sink tag
            try self.plan.addInstrumentationWithTag(
                fact.object,
                fact.context,
                @intFromEnum(EventTag.taint_sink),
            );
        }
    }

    /// Check if a location should be instrumented
    fn shouldInstrument(self: *InstrumentationPlanner, location: u32) bool {
        _ = self;
        _ = location;

        // This method is no longer used directly
        // Instead, we analyze all points in analyzeInstrumentationPoints
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
        /// Priority level
        priority: u8,
        /// Score (used for sorting within same priority)
        score: f32,
    };

    /// Create a new instrumentation plan
    pub fn init(allocator: std.mem.Allocator) InstrumentationPlan {
        return .{
            .allocator = allocator,
            .instrumentations = std.ArrayList(Instrumentation).initCapacity(allocator, 16) catch unreachable,
        };
    }

    /// Deinitialize the instrumentation plan
    pub fn deinit(self: *InstrumentationPlan) void {
        self.instrumentations.deinit(self.allocator);
    }

    /// Add an instrumentation point
    pub fn addInstrumentation(
        self: *InstrumentationPlan,
        inst_id: u32,
        location: u32,
    ) !void {
        try self.instrumentations.append(self.allocator, .{
            .inst_id = inst_id,
            .event_tag = 0, // Default tag
            .location = location,
            .priority = @intFromEnum(Priority.low),
            .score = 0.0,
        });
    }

    /// Add an instrumentation point with specific event tag
    pub fn addInstrumentationWithTag(
        self: *InstrumentationPlan,
        inst_id: u32,
        location: u32,
        event_tag: u8,
    ) !void {
        try self.instrumentations.append(self.allocator, .{
            .inst_id = inst_id,
            .event_tag = event_tag,
            .location = location,
            .priority = @intFromEnum(Priority.medium),
            .score = 0.0,
        });
    }

    /// Add an instrumentation point with priority
    pub fn addInstrumentationWithPriority(
        self: *InstrumentationPlan,
        inst_id: u32,
        location: u32,
        event_tag: u8,
        priority: Priority,
    ) !void {
        try self.instrumentations.append(self.allocator, .{
            .inst_id = inst_id,
            .event_tag = event_tag,
            .location = location,
            .priority = @intFromEnum(priority),
            .score = @floatFromInt(@intFromEnum(priority)),
        });
    }

    /// Add an instrumentation point with priority and score
    pub fn addInstrumentationWithScore(
        self: *InstrumentationPlan,
        inst_id: u32,
        location: u32,
        event_tag: u8,
        priority: Priority,
        score: f32,
    ) !void {
        try self.instrumentations.append(self.allocator, .{
            .inst_id = inst_id,
            .event_tag = event_tag,
            .location = location,
            .priority = @intFromEnum(priority),
            .score = score,
        });
    }

    /// Sort instrumentations by priority and score
    pub fn sortByPriority(self: *InstrumentationPlan) !void {
        // Sort by priority (highest first), then by score (highest first)
        std.sort.insertion(Instrumentation, self.instrumentations.items, {}, struct {
            fn lessThan(_: void, a: Instrumentation, b: Instrumentation) bool {
                if (a.priority != b.priority) {
                    return a.priority > b.priority; // Higher priority first
                }
                return a.score > b.score; // Higher score first
            }
        }.lessThan);
    }

    /// Select top N instrumentations based on budget
    pub fn selectTopPoints(
        self: *InstrumentationPlan,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ctx;
        _ = diag;

        const max_instrumentations = 1000; // Default budget

        if (self.instrumentations.items.len <= max_instrumentations) {
            return; // No need to trim
        }

        // Keep only top N instrumentations
        // Since we already sorted by priority, just truncate
        self.instrumentations.shrinkRetainingCapacity(max_instrumentations);
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
            try self.instrumentations.append(self.allocator, inst);
        }
    }

    /// Optimize the instrumentation plan
    /// Remove redundant instrumentations and consolidate by priority
    pub fn optimize(self: *InstrumentationPlan) !void {
        // Remove duplicate instrumentations, keeping the one with highest priority
        var seen = std.AutoHashMap(u32, Instrumentation).init(self.allocator);
        defer seen.deinit();

        var optimized = std.ArrayList(Instrumentation).initCapacity(self.allocator, 16) catch unreachable;

        for (self.instrumentations.items) |inst| {
            // Check if we already have an instrumentation at this location
            const existing = seen.get(inst.inst_id);

            if (existing) |prev| {
                // Keep the one with higher priority
                if (inst.priority > prev.priority or
                    (inst.priority == prev.priority and inst.score > prev.score))
                {
                    try seen.put(inst.inst_id, inst);
                }
            } else {
                try seen.put(inst.inst_id, inst);
            }
        }

        // Collect all unique instrumentations
        var iter = seen.iterator();
        while (iter.next()) |entry| {
            try optimized.append(self.allocator, entry.value_ptr.*);
        }

        self.instrumentations.deinit(self.allocator);
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
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.low)), inst.priority);
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

    // Add duplicate instrumentations with different priorities
    try plan.addInstrumentation(1, 42);
    try plan.addInstrumentationWithPriority(1, 42, @intFromEnum(EventTag.alias_check), Priority.high);
    try plan.addInstrumentation(2, 43);
    try plan.addInstrumentation(1, 42);

    try std.testing.expectEqual(@as(usize, 4), plan.count());

    try plan.optimize();
    try std.testing.expectEqual(@as(usize, 2), plan.count());

    // Verify the high priority instrumentation was kept
    const inst = plan.get(0).?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.high)), inst.priority);
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

test "InstrumentationPlan - priority sorting" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    // Add instrumentations with different priorities
    try plan.addInstrumentationWithPriority(1, 10, @intFromEnum(EventTag.lock_acquire), Priority.low);
    try plan.addInstrumentationWithPriority(2, 20, @intFromEnum(EventTag.lock_acquire), Priority.high);
    try plan.addInstrumentationWithPriority(3, 30, @intFromEnum(EventTag.lock_acquire), Priority.critical);
    try plan.addInstrumentationWithPriority(4, 40, @intFromEnum(EventTag.lock_acquire), Priority.medium);

    try std.testing.expectEqual(@as(usize, 4), plan.count());

    // Sort by priority
    try plan.sortByPriority();

    // Verify order: critical, high, medium, low
    const inst0 = plan.get(0).?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.critical)), inst0.priority);

    const inst1 = plan.get(1).?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.high)), inst1.priority);

    const inst2 = plan.get(2).?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.medium)), inst2.priority);

    const inst3 = plan.get(3).?;
    try std.testing.expectEqual(@as(u8, @intFromEnum(Priority.low)), inst3.priority);
}

test "InstrumentationPlan - selection with budget" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    // Add more than the default budget (1000)
    for (0..1500) |i| {
        const priority: Priority = if (i < 100) Priority.critical else Priority.low;
        try plan.addInstrumentationWithPriority(@intCast(i), @intCast(i), @intFromEnum(EventTag.alias_check), priority);
    }

    try std.testing.expectEqual(@as(usize, 1500), plan.count());

    // Sort by priority
    try plan.sortByPriority();

    // Select top points (should keep critical first, then trim)
    // Create dummy context and diag for the test
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();
    var ctx = PassContext.init(std.testing.allocator);
    defer ctx.deinit();
    var diag = DiagnosticWriter.init(std.testing.allocator);
    defer diag.deinit();

    try plan.selectTopPoints(&ctx, &diag);

    // Should keep at most 1000 instrumentations
    try std.testing.expect(@as(usize, 1000) >= plan.count());
}

test "InstrumentationPlan - instrumentation with score" {
    var plan = InstrumentationPlan.init(std.testing.allocator);
    defer plan.deinit();

    // Add instrumentations with same priority but different scores
    try plan.addInstrumentationWithScore(1, 10, @intFromEnum(EventTag.alias_check), Priority.medium, 0.5);
    try plan.addInstrumentationWithScore(2, 20, @intFromEnum(EventTag.alias_check), Priority.medium, 0.9);
    try plan.addInstrumentationWithScore(3, 30, @intFromEnum(EventTag.alias_check), Priority.medium, 0.7);

    try std.testing.expectEqual(@as(usize, 3), plan.count());

    // Sort by priority and score
    try plan.sortByPriority();

    // Verify order by score (highest first)
    const inst0 = plan.get(0).?;
    try std.testing.expectEqual(@as(u32, 2), inst0.inst_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), inst0.score, 0.01);

    const inst1 = plan.get(1).?;
    try std.testing.expectEqual(@as(u32, 3), inst1.inst_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), inst1.score, 0.01);

    const inst2 = plan.get(2).?;
    try std.testing.expectEqual(@as(u32, 1), inst2.inst_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), inst2.score, 0.01);
}
