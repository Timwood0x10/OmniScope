//! Resource Lifetime Engine
//!
//! A language-agnostic resource lifetime analysis framework.
//!
//! Key insight: Lifetime is NOT Rust-specific borrow checking.
//! In the cross-language world, lifetime means:
//!   - Who owns this resource?
//!   - Is it still valid?
//!   - Has it escaped across boundaries?
//!
//! This module provides a universal model for:
//! - Rust ↔ C
//! - Zig ↔ C
//! - Swift ↔ C
//! - C++ ↔ C ABI
//! - Julia ↔ C
//! - Any LLVM language ↔ Native boundary
//!
//! Architecture:
//! ```
//! Language Frontends (Rust/Zig/C/Swift symbol hints)
//!         ↓
//! Semantic Mapper (alloc/free/borrow/transfer/reclaim/escape)
//!         ↓
//! Lifetime Engine (owner + state transitions)
//!         ↓
//! Issue Detector (leak/UAF/double free/escape)
//! ```

const std = @import("std");

/// Resource owner classification.
/// Who is responsible for this resource's lifetime?
pub const Owner = enum(u8) {
    /// Owner could not be determined.
    unknown,
    /// The caller owns this resource.
    caller,
    /// The callee owns this resource.
    callee,
    /// Ownership is shared (e.g., reference counted).
    shared,
    /// The runtime/system owns this resource.
    system,
};

/// Resource lifetime state.
/// What is the current validity state of this resource?
pub const LifetimeState = enum(u8) {
    /// State could not be determined.
    unknown,
    /// Resource is alive and valid.
    live,
    /// Ownership has been transferred to another party.
    moved,
    /// Resource is borrowed (temporary access).
    borrowed,
    /// Resource has been freed/released.
    freed,
    /// Resource has escaped to unknown scope (e.g., stored globally).
    escaped,
    /// Resource is in an invalid state (use after free, etc.).
    invalid,
};

/// Semantic action on a resource.
/// These are the 6 core operations that drive lifetime analysis.
pub const SemanticAction = enum(u8) {
    /// Allocate a new resource.
    /// State transition: unknown -> live(owner=caller)
    alloc,
    /// Free/release a resource.
    /// State transition: live -> freed
    free,
    /// Borrow a resource (temporary access).
    /// State transition: live -> borrowed
    borrow,
    /// Transfer ownership to another party.
    /// State transition: live -> moved, owner changes
    transfer,
    /// Reclaim ownership from another party.
    /// State transition: moved -> live, owner changes
    reclaim,
    /// Resource escapes to unknown scope.
    /// State transition: borrowed -> escaped
    escape,
};

/// A fact about a resource's lifetime.
/// This is the core data structure for lifetime analysis.
pub const ResourceFact = struct {
    /// Unique identifier for this resource.
    id: u64,
    /// The function where this resource originated.
    origin_fn: []const u8,
    /// Current owner of this resource.
    owner: Owner,
    /// Current lifetime state.
    state: LifetimeState,
    /// The semantic action that created this fact.
    action: SemanticAction,
    /// Source location (if available).
    location: ?SourceLocation,
    /// Language hint (if available).
    lang_hint: ?LanguageHint,
};

/// Source location for diagnostics.
pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

/// Language hint for better diagnostics.
pub const LanguageHint = enum(u8) {
    unknown,
    c,
    rust,
    zig,
    swift,
    cpp,
    julia,
    nim,
};

/// Issue type detected by the lifetime engine.
pub const IssueType = enum(u8) {
    /// Double free: freeing an already freed resource.
    double_free,
    /// Use after free: accessing a freed resource.
    use_after_free,
    /// Memory leak: resource never freed.
    leak,
    /// Borrow escape: borrowed resource escaped to unknown scope.
    borrow_escape,
    /// Invalid transition: illegal state transition.
    invalid_transition,
    /// Ownership conflict: multiple owners claim the same resource.
    ownership_conflict,
};

/// A detected issue.
pub const Issue = struct {
    /// Type of issue.
    kind: IssueType,
    /// The resource involved.
    resource_id: u64,
    /// Description of the issue.
    description: []const u8,
    /// Source location (if available).
    location: ?SourceLocation,
    /// Severity (1-4, higher is more severe).
    severity: u8,
};

/// State transition rule.
/// Defines valid state transitions for each semantic action.
pub const TransitionRule = struct {
    /// The action that triggers this transition.
    action: SemanticAction,
    /// Required previous state (null = any).
    required_state: ?LifetimeState,
    /// The new state after transition.
    new_state: LifetimeState,
    /// Whether owner changes.
    owner_change: bool,
    /// New owner (if owner_change is true).
    new_owner: ?Owner,
};

/// The 6 core transition rules.
pub const TRANSITION_RULES = [_]TransitionRule{
    // alloc: unknown -> live(owner=caller)
    .{
        .action = .alloc,
        .required_state = null,
        .new_state = .live,
        .owner_change = true,
        .new_owner = .caller,
    },
    // free: live -> freed
    .{
        .action = .free,
        .required_state = .live,
        .new_state = .freed,
        .owner_change = false,
        .new_owner = null,
    },
    // borrow: live -> borrowed
    .{
        .action = .borrow,
        .required_state = .live,
        .new_state = .borrowed,
        .owner_change = false,
        .new_owner = null,
    },
    // transfer: live -> moved
    .{
        .action = .transfer,
        .required_state = .live,
        .new_state = .moved,
        .owner_change = true,
        .new_owner = .callee,
    },
    // reclaim: moved -> live
    .{
        .action = .reclaim,
        .required_state = .moved,
        .new_state = .live,
        .owner_change = true,
        .new_owner = .caller,
    },
    // escape: borrowed -> escaped
    .{
        .action = .escape,
        .required_state = .borrowed,
        .new_state = .escaped,
        .owner_change = false,
        .new_owner = null,
    },
};

/// The Resource Lifetime Engine.
/// Tracks resource lifetimes across language boundaries.
pub const LifetimeEngine = struct {
    allocator: std.mem.Allocator,
    resources: std.AutoHashMap(u64, ResourceFact),
    issues: std.ArrayList(Issue),
    next_id: u64,

    /// Initialize a new lifetime engine.
    pub fn init(allocator: std.mem.Allocator) LifetimeEngine {
        return .{
            .allocator = allocator,
            .resources = std.AutoHashMap(u64, ResourceFact).init(allocator),
            .issues = .{},
            .next_id = 1,
        };
    }

    /// Free all resources.
    pub fn deinit(self: *LifetimeEngine) void {
        self.resources.deinit();
        self.issues.deinit(self.allocator);
    }

    /// Apply a semantic action to create a new resource.
    /// Returns the resource ID on success, null on failure.
    pub fn applyAction(
        self: *LifetimeEngine,
        action: SemanticAction,
        origin_fn: []const u8,
        location: ?SourceLocation,
        lang_hint: ?LanguageHint,
    ) ?u64 {
        const id = self.next_id;
        self.next_id += 1;

        // Find the transition rule for this action.
        const rule = findTransitionRule(action) orelse {
            // Unknown action - create fact anyway.
            const fact = ResourceFact{
                .id = id,
                .origin_fn = origin_fn,
                .owner = .unknown,
                .state = .unknown,
                .action = action,
                .location = location,
                .lang_hint = lang_hint,
            };
            self.resources.put(id, fact) catch return null;
            return id;
        };

        // Create the new fact.
        const fact = ResourceFact{
            .id = id,
            .origin_fn = origin_fn,
            .owner = if (rule.owner_change and rule.new_owner != null)
                rule.new_owner.?
            else
                .caller,
            .state = rule.new_state,
            .action = action,
            .location = location,
            .lang_hint = lang_hint,
        };

        self.resources.put(id, fact) catch return null;
        return id;
    }

    /// Apply a semantic action to an existing resource.
    /// Checks for invalid transitions and detects issues.
    pub fn applyActionToResource(
        self: *LifetimeEngine,
        resource_id: u64,
        action: SemanticAction,
        location: ?SourceLocation,
    ) bool {
        // Find the existing resource.
        const existing = self.resources.get(resource_id) orelse {
            // Resource not found - this is an issue.
            self.addIssue(.{
                .kind = .invalid_transition,
                .resource_id = resource_id,
                .description = "Action on unknown resource",
                .location = location,
                .severity = 3,
            });
            return false;
        };

        // Find the transition rule.
        const rule = findTransitionRule(action) orelse return false;

        // Check if the transition is valid.
        if (rule.required_state) |required| {
            if (existing.state != required) {
                // Invalid transition - detect the specific issue.
                const issue_type = detectIssueType(existing.state, action);
                self.addIssue(.{
                    .kind = issue_type,
                    .resource_id = resource_id,
                    .description = formatTransitionError(existing.state, action),
                    .location = location,
                    .severity = 4,
                });
                return false;
            }
        }

        // Apply the transition.
        var new_fact = existing;
        new_fact.state = rule.new_state;
        new_fact.action = action;
        new_fact.location = location;

        if (rule.owner_change and rule.new_owner != null) {
            new_fact.owner = rule.new_owner.?;
        }

        self.resources.put(resource_id, new_fact) catch return false;
        return true;
    }

    /// Add an issue to the issue list.
    fn addIssue(self: *LifetimeEngine, issue: Issue) void {
        self.issues.append(self.allocator, issue) catch |err| {
            std.log.err("LifetimeEngine: Failed to add issue: {}", .{err});
        };
    }

    /// Get all detected issues.
    pub fn getIssues(self: *const LifetimeEngine) []const Issue {
        return self.issues.items;
    }

    /// Check for leaks (resources that are still live at end of analysis).
    pub fn detectLeaks(self: *LifetimeEngine) void {
        var iter = self.resources.iterator();
        while (iter.next()) |entry| {
            const fact = entry.value_ptr.*;
            if (fact.state == .live or fact.state == .borrowed) {
                self.addIssue(.{
                    .kind = .leak,
                    .resource_id = fact.id,
                    .description = "Resource not freed before end of scope",
                    .location = fact.location,
                    .severity = 2,
                });
            }
        }
    }

    /// Get statistics about tracked resources.
    pub fn getStats(self: *const LifetimeEngine) EngineStats {
        var stats = EngineStats{};
        var iter = self.resources.iterator();
        while (iter.next()) |entry| {
            const fact = entry.value_ptr.*;
            stats.total_resources += 1;
            switch (fact.state) {
                .live => stats.live_count += 1,
                .moved => stats.moved_count += 1,
                .borrowed => stats.borrowed_count += 1,
                .freed => stats.freed_count += 1,
                .escaped => stats.escaped_count += 1,
                .invalid => stats.invalid_count += 1,
                .unknown => stats.unknown_count += 1,
            }
        }
        stats.issue_count = @intCast(self.issues.items.len);
        return stats;
    }
};

/// Statistics about the lifetime engine.
pub const EngineStats = struct {
    total_resources: u32 = 0,
    live_count: u32 = 0,
    moved_count: u32 = 0,
    borrowed_count: u32 = 0,
    freed_count: u32 = 0,
    escaped_count: u32 = 0,
    invalid_count: u32 = 0,
    unknown_count: u32 = 0,
    issue_count: u32 = 0,
};

/// Find the transition rule for a semantic action.
fn findTransitionRule(action: SemanticAction) ?TransitionRule {
    for (TRANSITION_RULES) |rule| {
        if (rule.action == action) return rule;
    }
    return null;
}

/// Detect the issue type based on current state and attempted action.
fn detectIssueType(current_state: LifetimeState, action: SemanticAction) IssueType {
    return switch (action) {
        .free => switch (current_state) {
            .freed => .double_free,
            .moved => .ownership_conflict,
            .borrowed => .ownership_conflict,
            else => .invalid_transition,
        },
        .transfer => switch (current_state) {
            .freed => .use_after_free,
            .moved => .ownership_conflict,
            else => .invalid_transition,
        },
        .escape => switch (current_state) {
            .freed => .use_after_free,
            else => .invalid_transition,
        },
        else => .invalid_transition,
    };
}

/// Format a transition error message.
fn formatTransitionError(current_state: LifetimeState, action: SemanticAction) []const u8 {
    return switch (action) {
        .free => switch (current_state) {
            .freed => "Double free: resource already freed",
            .moved => "Free on moved resource: ownership transferred",
            .borrowed => "Free on borrowed resource: not owned",
            else => "Invalid free",
        },
        .transfer => switch (current_state) {
            .freed => "Transfer of freed resource: use after free",
            .moved => "Transfer of moved resource: ownership conflict",
            else => "Invalid transfer",
        },
        .escape => switch (current_state) {
            .freed => "Escape of freed resource: use after free",
            else => "Invalid escape",
        },
        else => "Invalid state transition",
    };
}

// Unit tests

test "Owner enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Owner.unknown));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Owner.caller));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Owner.callee));
}

test "LifetimeState enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(LifetimeState.unknown));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(LifetimeState.live));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(LifetimeState.freed));
}

test "SemanticAction enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SemanticAction.alloc));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SemanticAction.free));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(SemanticAction.escape));
}

test "TRANSITION_RULES count" {
    try std.testing.expectEqual(@as(usize, 6), TRANSITION_RULES.len);
}

test "LifetimeEngine - init and deinit" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();
    try std.testing.expectEqual(@as(usize, 0), engine.resources.count());
}

test "LifetimeEngine - applyAction alloc" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();

    const id = engine.applyAction(.alloc, "test_func", null, null);
    try std.testing.expect(id != null);
    try std.testing.expectEqual(@as(usize, 1), engine.resources.count());

    const fact = engine.resources.get(id.?).?;
    try std.testing.expectEqual(LifetimeState.live, fact.state);
    try std.testing.expectEqual(Owner.caller, fact.owner);
}

test "LifetimeEngine - applyActionToResource free" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();

    // First allocate
    const id = engine.applyAction(.alloc, "test_func", null, null).?;

    // Then free
    const ok = engine.applyActionToResource(id, .free, null);
    try std.testing.expect(ok);

    const fact = engine.resources.get(id).?;
    try std.testing.expectEqual(LifetimeState.freed, fact.state);
}

test "LifetimeEngine - detect double free" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();

    // Allocate
    const id = engine.applyAction(.alloc, "test_func", null, null).?;
    // Free once
    _ = engine.applyActionToResource(id, .free, null);
    // Try to free again
    const ok = engine.applyActionToResource(id, .free, null);
    try std.testing.expect(!ok);

    const issues = engine.getIssues();
    try std.testing.expectEqual(@as(usize, 1), issues.len);
    try std.testing.expectEqual(IssueType.double_free, issues[0].kind);
}

test "LifetimeEngine - detect leak" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();

    // Allocate but never free
    _ = engine.applyAction(.alloc, "test_func", null, null);

    engine.detectLeaks();

    const issues = engine.getIssues();
    try std.testing.expectEqual(@as(usize, 1), issues.len);
    try std.testing.expectEqual(IssueType.leak, issues[0].kind);
}

test "LifetimeEngine - getStats" {
    var engine = LifetimeEngine.init(std.testing.allocator);
    defer engine.deinit();

    const id1 = engine.applyAction(.alloc, "test_func", null, null).?;
    _ = engine.applyAction(.alloc, "test_func", null, null);
    _ = engine.applyActionToResource(id1, .free, null);

    const stats = engine.getStats();
    try std.testing.expectEqual(@as(u32, 2), stats.total_resources);
    try std.testing.expectEqual(@as(u32, 1), stats.live_count);
    try std.testing.expectEqual(@as(u32, 1), stats.freed_count);
}

test "detectIssueType" {
    try std.testing.expectEqual(IssueType.double_free, detectIssueType(.freed, .free));
    try std.testing.expectEqual(IssueType.use_after_free, detectIssueType(.freed, .transfer));
    try std.testing.expectEqual(IssueType.ownership_conflict, detectIssueType(.moved, .free));
}

test "findTransitionRule" {
    const rule = findTransitionRule(.alloc).?;
    try std.testing.expectEqual(SemanticAction.alloc, rule.action);
    try std.testing.expectEqual(LifetimeState.live, rule.new_state);
    try std.testing.expect(rule.owner_change);
}
