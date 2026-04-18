//! Path-Sensitive Analysis Support
//!
//! This module provides data structures for tracking path conditions
//! during data flow analysis. It enables more precise analysis by
//! considering which execution paths are feasible.
//!
//! Key use cases:
//! - Null check tracking: if (ptr) { free(ptr); } // safe, not double-free
//! - Bounds check tracking: if (i < len) { arr[i] = x; } // safe access
//! - Type check tracking: if (isa<Class>(obj)) { ... } // safe cast

const std = @import("std");

const Allocator = std.mem.Allocator;

/// Condition kind for path-sensitive analysis
pub const ConditionKind = enum(u8) {
    /// Pointer is not null
    ptr_not_null,
    /// Pointer is null
    ptr_is_null,
    /// Integer comparison (a < b, a >= b, etc.)
    int_comparison,
    /// Boolean value is true
    bool_true,
    /// Boolean value is false
    bool_false,
    /// Type check (isa, instanceof)
    type_check,
    /// Bounds check (index < length)
    bounds_check,
    /// Custom condition
    custom,
};

/// Comparison operator for integer conditions
pub const ComparisonOp = enum(u3) {
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
};

/// A single path condition
pub const PathCondition = struct {
    /// Kind of condition
    kind: ConditionKind,
    /// Value ID being tested
    value_id: u32,
    /// Whether this condition is negated
    negated: bool,
    /// Optional second operand for comparisons
    operand2: ?u32,
    /// Comparison operator for int_comparison
    cmp_op: ?ComparisonOp,
    /// Source location (for diagnostics)
    source_line: ?u32,

    /// Create a null check condition
    pub fn nullCheck(value_id: u32, is_not_null: bool) PathCondition {
        return .{
            .kind = if (is_not_null) .ptr_not_null else .ptr_is_null,
            .value_id = value_id,
            .negated = false,
            .operand2 = null,
            .cmp_op = null,
            .source_line = null,
        };
    }

    /// Create a bounds check condition
    pub fn boundsCheck(index_id: u32, len_id: u32, is_in_bounds: bool) PathCondition {
        return .{
            .kind = .bounds_check,
            .value_id = index_id,
            .negated = !is_in_bounds,
            .operand2 = len_id,
            .cmp_op = if (is_in_bounds) .lt else .ge,
            .source_line = null,
        };
    }

    /// Create an integer comparison condition
    pub fn intCompare(lhs_id: u32, op: ComparisonOp, rhs_id: u32) PathCondition {
        return .{
            .kind = .int_comparison,
            .value_id = lhs_id,
            .negated = false,
            .operand2 = rhs_id,
            .cmp_op = op,
            .source_line = null,
        };
    }

    /// Negate this condition
    pub fn negate(self: PathCondition) PathCondition {
        var result = self;
        result.negated = !result.negated;
        return result;
    }

    /// Check if this condition implies another condition
    pub fn implies(self: PathCondition, other: PathCondition) bool {
        if (self.value_id != other.value_id) return false;

        return switch (self.kind) {
            .ptr_not_null => switch (other.kind) {
                .ptr_not_null => !self.negated and !other.negated,
                .ptr_is_null => !self.negated and other.negated,
                else => false,
            },
            .ptr_is_null => switch (other.kind) {
                .ptr_is_null => !self.negated and !other.negated,
                .ptr_not_null => !self.negated and other.negated,
                else => false,
            },
            else => false,
        };
    }

    /// Check if this condition conflicts with another
    pub fn conflicts(self: PathCondition, other: PathCondition) bool {
        if (self.value_id != other.value_id) return false;

        return switch (self.kind) {
            .ptr_not_null => switch (other.kind) {
                .ptr_not_null => self.negated != other.negated,
                .ptr_is_null => !self.negated != other.negated,
                else => false,
            },
            .ptr_is_null => switch (other.kind) {
                .ptr_is_null => self.negated != other.negated,
                .ptr_not_null => !self.negated != other.negated,
                else => false,
            },
            else => false,
        };
    }
};

/// A path through the program with accumulated conditions
pub const ExecutionPath = struct {
    /// Unique path ID
    id: u32,
    /// Conditions that must hold on this path
    conditions: std.ArrayList(PathCondition),
    /// Parent path (for path splitting at branches)
    parent: ?u32,
    /// Whether this path is feasible
    is_feasible: bool,
    /// Allocator
    allocator: Allocator,

    /// Create a new execution path
    pub fn init(allocator: Allocator, id: u32) ExecutionPath {
        return .{
            .id = id,
            .conditions = std.ArrayList(PathCondition).init(allocator),
            .parent = null,
            .is_feasible = true,
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *ExecutionPath) void {
        self.conditions.deinit();
    }

    /// Add a condition to this path
    pub fn addCondition(self: *ExecutionPath, cond: PathCondition) !void {
        // Check for conflicts with existing conditions
        for (self.conditions.items) |existing| {
            if (existing.conflicts(cond)) {
                self.is_feasible = false;
                return;
            }
        }
        try self.conditions.append(cond);
    }

    /// Check if a condition holds on this path
    pub fn conditionHolds(self: *const ExecutionPath, cond: PathCondition) bool {
        for (self.conditions.items) |existing| {
            if (existing.implies(cond)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a pointer is known to be non-null on this path
    pub fn isPtrNonNull(self: *const ExecutionPath, value_id: u32) bool {
        const null_check = PathCondition.nullCheck(value_id, true);
        return self.conditionHolds(null_check);
    }

    /// Check if a pointer is known to be null on this path
    pub fn isPtrNull(self: *const ExecutionPath, value_id: u32) bool {
        const null_check = PathCondition.nullCheck(value_id, false);
        return self.conditionHolds(null_check);
    }

    /// Clone this path
    pub fn clone(self: *const ExecutionPath, new_id: u32) !ExecutionPath {
        var new_path = ExecutionPath.init(self.allocator, new_id);
        new_path.parent = self.id;
        new_path.is_feasible = self.is_feasible;
        try new_path.conditions.appendSlice(self.conditions.items);
        return new_path;
    }
};

/// Manager for execution paths during analysis
pub const PathManager = struct {
    /// All paths
    paths: std.AutoHashMap(u32, ExecutionPath),
    /// Next path ID
    next_id: u32,
    /// Current path ID
    current_path: u32,
    /// Allocator
    allocator: Allocator,

    /// Create a new path manager
    pub fn init(allocator: Allocator) PathManager {
        var paths = std.AutoHashMap(u32, ExecutionPath).init(allocator);
        var initial_path = ExecutionPath.init(allocator, 0);
        initial_path.is_feasible = true;
        paths.put(0, initial_path) catch {};

        return .{
            .paths = paths,
            .next_id = 1,
            .current_path = 0,
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *PathManager) void {
        var iter = self.paths.iterator();
        while (iter.next()) |entry| {
            var path = entry.value_ptr.*;
            path.deinit();
        }
        self.paths.deinit();
    }

    /// Get the current path
    pub fn getCurrentPath(self: *PathManager) ?*ExecutionPath {
        return self.paths.getPtr(self.current_path);
    }

    /// Add a condition to the current path
    pub fn addCondition(self: *PathManager, cond: PathCondition) !void {
        if (self.paths.getPtr(self.current_path)) |path| {
            try path.addCondition(cond);
        }
    }

    /// Split path at a branch (returns true/false branch path IDs)
    pub fn splitPath(self: *PathManager, cond: PathCondition) !struct { true_path: u32, false_path: u32 } {
        const current = self.paths.get(self.current_path) orelse {
            return error.NoCurrentPath;
        };

        // Create true branch
        const true_id = self.next_id;
        self.next_id += 1;
        var true_path = try current.clone(true_id);
        try true_path.addCondition(cond);

        // Create false branch
        const false_id = self.next_id;
        self.next_id += 1;
        var false_path = try current.clone(false_id);
        try false_path.addCondition(cond.negate());

        try self.paths.put(true_id, true_path);
        try self.paths.put(false_id, false_path);

        return .{ .true_path = true_id, .false_path = false_id };
    }

    /// Switch to a different path
    pub fn switchToPath(self: *PathManager, path_id: u32) void {
        self.current_path = path_id;
    }

    /// Check if current path is feasible
    pub fn isFeasible(self: *PathManager) bool {
        if (self.paths.get(self.current_path)) |path| {
            return path.is_feasible;
        }
        return false;
    }

    /// Check if pointer is non-null on current path
    pub fn isPtrNonNull(self: *PathManager, value_id: u32) bool {
        if (self.paths.get(self.current_path)) |path| {
            return path.isPtrNonNull(value_id);
        }
        return false;
    }

    /// Get statistics
    pub fn getStats(self: *const PathManager) PathStats {
        var feasible: u32 = 0;
        var infeasible: u32 = 0;
        var total_conditions: u32 = 0;

        var iter = self.paths.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.is_feasible) {
                feasible += 1;
            } else {
                infeasible += 1;
            }
            total_conditions += @intCast(entry.value_ptr.conditions.items.len);
        }

        return .{
            .total_paths = @intCast(self.paths.count()),
            .feasible_paths = feasible,
            .infeasible_paths = infeasible,
            .total_conditions = total_conditions,
        };
    }
};

/// Path statistics
pub const PathStats = struct {
    total_paths: u32,
    feasible_paths: u32,
    infeasible_paths: u32,
    total_conditions: u32,
};

// Unit tests

test "ConditionKind enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ConditionKind.ptr_not_null));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ConditionKind.ptr_is_null));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ConditionKind.int_comparison));
}

test "ComparisonOp enum values" {
    try std.testing.expectEqual(@as(u3, 0), @intFromEnum(ComparisonOp.eq));
    try std.testing.expectEqual(@as(u3, 1), @intFromEnum(ComparisonOp.ne));
    try std.testing.expectEqual(@as(u3, 2), @intFromEnum(ComparisonOp.lt));
}

test "PathCondition - nullCheck" {
    const not_null = PathCondition.nullCheck(42, true);
    try std.testing.expectEqual(ConditionKind.ptr_not_null, not_null.kind);
    try std.testing.expectEqual(@as(u32, 42), not_null.value_id);
    try std.testing.expect(!not_null.negated);

    const is_null = PathCondition.nullCheck(42, false);
    try std.testing.expectEqual(ConditionKind.ptr_is_null, is_null.kind);
}

test "PathCondition - negate" {
    const cond = PathCondition.nullCheck(42, true);
    const negated = cond.negate();
    try std.testing.expect(negated.negated);
}

test "PathCondition - implies" {
    const not_null = PathCondition.nullCheck(42, true);
    const also_not_null = PathCondition.nullCheck(42, true);
    const is_null = PathCondition.nullCheck(42, false);

    try std.testing.expect(not_null.implies(also_not_null));
    try std.testing.expect(!not_null.implies(is_null));
}

test "PathCondition - conflicts" {
    const not_null = PathCondition.nullCheck(42, true);
    const is_null = PathCondition.nullCheck(42, false);
    const other_not_null = PathCondition.nullCheck(99, true);

    try std.testing.expect(not_null.conflicts(is_null));
    try std.testing.expect(!not_null.conflicts(other_not_null));
}

test "ExecutionPath - init and deinit" {
    var path = ExecutionPath.init(std.testing.allocator, 0);
    defer path.deinit();

    try std.testing.expectEqual(@as(u32, 0), path.id);
    try std.testing.expect(path.is_feasible);
    try std.testing.expectEqual(@as(usize, 0), path.conditions.items.len);
}

test "ExecutionPath - addCondition" {
    var path = ExecutionPath.init(std.testing.allocator, 0);
    defer path.deinit();

    const cond = PathCondition.nullCheck(42, true);
    try path.addCondition(cond);

    try std.testing.expectEqual(@as(usize, 1), path.conditions.items.len);
}

test "ExecutionPath - addCondition conflict" {
    var path = ExecutionPath.init(std.testing.allocator, 0);
    defer path.deinit();

    const not_null = PathCondition.nullCheck(42, true);
    try path.addCondition(not_null);
    try std.testing.expect(path.is_feasible);

    const is_null = PathCondition.nullCheck(42, false);
    try path.addCondition(is_null);
    try std.testing.expect(!path.is_feasible);
}

test "ExecutionPath - isPtrNonNull" {
    var path = ExecutionPath.init(std.testing.allocator, 0);
    defer path.deinit();

    try std.testing.expect(!path.isPtrNonNull(42));

    const cond = PathCondition.nullCheck(42, true);
    try path.addCondition(cond);

    try std.testing.expect(path.isPtrNonNull(42));
    try std.testing.expect(!path.isPtrNonNull(99));
}

test "ExecutionPath - clone" {
    var path = ExecutionPath.init(std.testing.allocator, 0);
    defer path.deinit();

    const cond = PathCondition.nullCheck(42, true);
    try path.addCondition(cond);

    var cloned = try path.clone(1);
    defer cloned.deinit();

    try std.testing.expectEqual(@as(u32, 1), cloned.id);
    try std.testing.expectEqual(@as(usize, 1), cloned.conditions.items.len);
    try std.testing.expectEqual(@as(u32, 0), cloned.parent.?);
}

test "PathManager - init and deinit" {
    var manager = PathManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(u32, 1), manager.next_id);
    try std.testing.expect(manager.isFeasible());
}

test "PathManager - addCondition" {
    var manager = PathManager.init(std.testing.allocator);
    defer manager.deinit();

    const cond = PathCondition.nullCheck(42, true);
    try manager.addCondition(cond);

    try std.testing.expect(manager.isPtrNonNull(42));
}

test "PathManager - splitPath" {
    var manager = PathManager.init(std.testing.allocator);
    defer manager.deinit();

    const cond = PathCondition.nullCheck(42, true);
    const paths = try manager.splitPath(cond);

    try std.testing.expectEqual(@as(u32, 1), paths.true_path);
    try std.testing.expectEqual(@as(u32, 2), paths.false_path);

    manager.switchToPath(paths.true_path);
    try std.testing.expect(manager.isPtrNonNull(42));

    manager.switchToPath(paths.false_path);
    try std.testing.expect(!manager.isPtrNonNull(42));
}

test "PathManager - getStats" {
    var manager = PathManager.init(std.testing.allocator);
    defer manager.deinit();

    const cond = PathCondition.nullCheck(42, true);
    _ = try manager.splitPath(cond);

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.total_paths);
    try std.testing.expectEqual(@as(u32, 3), stats.feasible_paths);
    try std.testing.expectEqual(@as(u32, 0), stats.infeasible_paths);
}

test "PathCondition - boundsCheck" {
    const in_bounds = PathCondition.boundsCheck(10, 20, true);
    try std.testing.expectEqual(ConditionKind.bounds_check, in_bounds.kind);
    try std.testing.expectEqual(@as(u32, 10), in_bounds.value_id);
    try std.testing.expectEqual(@as(u32, 20), in_bounds.operand2.?);
    try std.testing.expect(!in_bounds.negated);

    const out_bounds = PathCondition.boundsCheck(10, 20, false);
    try std.testing.expect(out_bounds.negated);
}

test "PathCondition - intCompare" {
    const cmp = PathCondition.intCompare(10, .lt, 20);
    try std.testing.expectEqual(ConditionKind.int_comparison, cmp.kind);
    try std.testing.expectEqual(@as(u32, 10), cmp.value_id);
    try std.testing.expectEqual(@as(u32, 20), cmp.operand2.?);
    try std.testing.expectEqual(ComparisonOp.lt, cmp.cmp_op.?);
}
