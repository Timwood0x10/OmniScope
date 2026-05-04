//! FFI Boundary Analyzer
//!
//! Layer 3 of the resource lifetime analysis architecture.
//!
//! This module detects cross-language resource contract violations:
//! - Rust Box::into_raw -> C free (ownership mismatch)
//! - C malloc -> Rust drop (ownership mismatch)
//! - Borrow escape across FFI boundaries
//! - Double free across language boundaries
//!
//! Architecture:
//! ```
//! Layer 1: LifetimeEngine (resource state machine)
//! Layer 2: SemanticMapper (IR -> semantic actions)
//! Layer 3: BoundaryAnalyzer (cross-language contract checker)
//! ```
//!
//! Key insight: FFI boundaries are where ownership contracts are
//! most likely to be violated. This module focuses on detecting
//! those violations.

const std = @import("std");
const engine = @import("engine.zig");
// NOTE: mapper module removed (dead code, 2026-05-04)
// See untodo.md DEAD-13 for details

pub const SemanticAction = engine.SemanticAction;
pub const LifetimeState = engine.LifetimeState;
pub const Owner = engine.Owner;
pub const LanguageHint = engine.LanguageHint;
pub const ResourceFact = engine.ResourceFact;
pub const IssueType = engine.IssueType;

/// FFI boundary direction.
pub const BoundaryDirection = enum(u8) {
    /// Calling from language A to language B.
    out,
    /// Returning from language B to language A.
    in_,
};

/// FFI boundary information.
pub const FFIBoundary = struct {
    /// Unique identifier for this boundary.
    id: u32,
    /// The function being called across the boundary.
    function_name: []const u8,
    /// The language of the caller.
    caller_lang: LanguageHint,
    /// The language of the callee.
    callee_lang: LanguageHint,
    /// Direction of the call.
    direction: BoundaryDirection,
    /// Source location.
    location: ?engine.SourceLocation,
};

/// Cross-language violation type.
pub const BoundaryViolation = enum(u8) {
    /// Rust memory freed by C (Box::into_raw -> free).
    rust_freed_by_c,
    /// C memory freed by Rust (malloc -> Box::from_raw).
    c_freed_by_rust,
    /// Borrow escaped across FFI (as_ptr -> stored globally in C).
    borrow_escape,
    /// Double free across languages.
    cross_lang_double_free,
    /// Ownership transfer without matching reclaim.
    orphaned_transfer,
    /// Reclaim without prior transfer.
    invalid_reclaim,
    /// Zig memory freed by C (alloc -> free).
    zig_freed_by_c,
    /// Go cgo CString leak (allocated but not freed).
    go_cstring_leak,
    /// Go cgo pointer stored in C (violates cgo pointer rules).
    go_pointer_stored_in_c,
    /// Go cgo passing Go pointer to C that stores it.
    go_pointer_escape,
};

/// A detected boundary violation.
pub const BoundaryIssue = struct {
    /// Type of violation.
    kind: BoundaryViolation,
    /// The FFI boundary where this occurred.
    boundary: FFIBoundary,
    /// The resource involved.
    resource_id: u64,
    /// Human-readable description.
    description: []const u8,
    /// Severity (1-4, higher is more severe).
    severity: u8,
};

/// Boundary contract rule.
pub const ContractRule = struct {
    /// Source language.
    source_lang: LanguageHint,
    /// Target language.
    target_lang: LanguageHint,
    /// Allowed semantic actions.
    allowed_actions: []const SemanticAction,
    /// Violation type if rule is broken.
    violation: BoundaryViolation,
    /// Description of the rule.
    description: []const u8,
};

/// Default boundary contract rules.
pub const CONTRACT_RULES = [_]ContractRule{
    .{
        .source_lang = .rust,
        .target_lang = .c,
        .allowed_actions = &.{ .transfer, .borrow },
        .violation = .rust_freed_by_c,
        .description = "Rust memory transferred to C should not be freed by C free()",
    },
    .{
        .source_lang = .c,
        .target_lang = .rust,
        .allowed_actions = &.{ .alloc, .transfer },
        .violation = .c_freed_by_rust,
        .description = "C memory should not be reclaimed by Rust Box::from_raw",
    },
};

/// The FFI Boundary Analyzer.
pub const BoundaryAnalyzer = struct {
    allocator: std.mem.Allocator,
    boundaries: std.ArrayList(FFIBoundary),
    issues: std.ArrayList(BoundaryIssue),
    next_boundary_id: u32,

    /// Initialize a new boundary analyzer.
    pub fn init(allocator: std.mem.Allocator) BoundaryAnalyzer {
        return .{
            .allocator = allocator,
            .boundaries = .{},
            .issues = .{},
            .next_boundary_id = 1,
        };
    }

    /// Free all resources.
    pub fn deinit(self: *BoundaryAnalyzer) void {
        self.boundaries.deinit(self.allocator);
        self.issues.deinit(self.allocator);
    }

    /// Register an FFI boundary.
    pub fn registerBoundary(
        self: *BoundaryAnalyzer,
        function_name: []const u8,
        caller_lang: LanguageHint,
        callee_lang: LanguageHint,
        direction: BoundaryDirection,
        location: ?engine.SourceLocation,
    ) u32 {
        const id = self.next_boundary_id;
        self.next_boundary_id += 1;

        self.boundaries.append(self.allocator, .{
            .id = id,
            .function_name = function_name,
            .caller_lang = caller_lang,
            .callee_lang = callee_lang,
            .direction = direction,
            .location = location,
        }) catch return 0;

        return id;
    }

    /// Check for cross-language ownership violation.
    pub fn checkOwnershipViolation(
        self: *BoundaryAnalyzer,
        resource: ResourceFact,
        action: SemanticAction,
        action_lang: LanguageHint,
        boundary: FFIBoundary,
    ) ?BoundaryIssue {
        if (resource.lang_hint == null or resource.lang_hint.? == .unknown) {
            return null;
        }

        const origin_lang = resource.lang_hint.?;

        if (origin_lang == action_lang) {
            return null;
        }

        const violation = detectOwnershipViolation(
            origin_lang,
            action_lang,
            resource.state,
            action,
        ) orelse return null;

        const issue: BoundaryIssue = .{
            .kind = violation,
            .boundary = boundary,
            .resource_id = resource.id,
            .description = formatViolationMessage(violation, origin_lang, action_lang),
            .severity = 4,
        };

        self.addIssue(issue);
        return issue;
    }

    /// Check for borrow escape across FFI.
    pub fn checkBorrowEscape(
        self: *BoundaryAnalyzer,
        resource: ResourceFact,
        boundary: FFIBoundary,
    ) ?BoundaryIssue {
        if (resource.state != .borrowed and resource.state != .escaped) {
            return null;
        }

        if (boundary.direction == .out and
            resource.state == .borrowed)
        {
            const issue: BoundaryIssue = .{
                .kind = .borrow_escape,
                .boundary = boundary,
                .resource_id = resource.id,
                .description = "Borrowed resource passed across FFI boundary - may escape",
                .severity = 3,
            };
            self.addIssue(issue);
            return issue;
        }

        return null;
    }

    /// Add an issue to the issue list.
    pub fn addIssue(self: *BoundaryAnalyzer, issue: BoundaryIssue) void {
        self.issues.append(self.allocator, issue) catch |err| {
            std.log.err("BoundaryAnalyzer: Failed to add issue: {}", .{err});
        };
    }

    /// Get all detected issues.
    pub fn getIssues(self: *const BoundaryAnalyzer) []const BoundaryIssue {
        return self.issues.items;
    }

    /// Get statistics.
    pub fn getStats(self: *const BoundaryAnalyzer) AnalyzerStats {
        var stats = AnalyzerStats{};
        stats.boundary_count = @intCast(self.boundaries.items.len);
        stats.issue_count = @intCast(self.issues.items.len);

        for (self.issues.items) |issue| {
            switch (issue.kind) {
                .rust_freed_by_c => stats.rust_freed_by_c_count += 1,
                .c_freed_by_rust => stats.c_freed_by_rust_count += 1,
                .borrow_escape => stats.borrow_escape_count += 1,
                .cross_lang_double_free => stats.double_free_count += 1,
                .orphaned_transfer => stats.orphaned_transfer_count += 1,
                .invalid_reclaim => stats.invalid_reclaim_count += 1,
                .zig_freed_by_c => stats.zig_freed_by_c_count += 1,
                .go_cstring_leak => stats.go_cstring_leak_count += 1,
                .go_pointer_stored_in_c => stats.go_pointer_stored_count += 1,
                .go_pointer_escape => stats.go_pointer_escape_count += 1,
            }
        }

        return stats;
    }
};

/// Detect language from function name patterns.
pub fn detectLanguage(func_name: []const u8) LanguageHint {
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        return .rust;
    }
    if (std.mem.startsWith(u8, func_name, "_Z")) {
        return .cpp;
    }
    if (std.mem.indexOf(u8, func_name, "rust_") != null) {
        return .rust;
    }
    if (std.mem.indexOf(u8, func_name, "zig.") != null) {
        return .zig;
    }
    if (std.mem.startsWith(u8, func_name, "$s")) {
        return .swift;
    }
    if (std.mem.indexOf(u8, func_name, "C.") != null or
        std.mem.indexOf(u8, func_name, "_cgo_") != null)
    {
        return .go;
    }
    return .c;
}

/// Statistics about the boundary analyzer.
pub const AnalyzerStats = struct {
    boundary_count: u32 = 0,
    issue_count: u32 = 0,
    rust_freed_by_c_count: u32 = 0,
    c_freed_by_rust_count: u32 = 0,
    borrow_escape_count: u32 = 0,
    double_free_count: u32 = 0,
    orphaned_transfer_count: u32 = 0,
    invalid_reclaim_count: u32 = 0,
    zig_freed_by_c_count: u32 = 0,
    go_cstring_leak_count: u32 = 0,
    go_pointer_stored_count: u32 = 0,
    go_pointer_escape_count: u32 = 0,
};

/// Detect ownership violation based on language combination.
fn detectOwnershipViolation(
    origin_lang: LanguageHint,
    action_lang: LanguageHint,
    current_state: LifetimeState,
    action: SemanticAction,
) ?BoundaryViolation {
    if (action == .free) {
        if (origin_lang == .rust and action_lang == .c) {
            return .rust_freed_by_c;
        }
        if (origin_lang == .c and action_lang == .rust) {
            return .c_freed_by_rust;
        }
        if (origin_lang == .zig and action_lang == .c) {
            return .zig_freed_by_c;
        }
        if (origin_lang == .go and action_lang == .c) {
            return .go_cstring_leak;
        }
        if (origin_lang == .c and action_lang == .go) {
            return .go_pointer_escape;
        }
    }

    if (action == .reclaim) {
        if (origin_lang == .c and action_lang == .rust) {
            if (current_state != .moved) {
                return .invalid_reclaim;
            }
        }
    }

    if (action == .transfer) {
        if (current_state == .moved) {
            return .orphaned_transfer;
        }
    }

    return null;
}

/// Format a violation message with language context.
fn formatViolationMessage(
    violation: BoundaryViolation,
    origin_lang: LanguageHint,
    action_lang: LanguageHint,
) []const u8 {
    _ = origin_lang;
    _ = action_lang;

    return switch (violation) {
        .rust_freed_by_c => "Rust memory freed by C free() - ownership mismatch",
        .c_freed_by_rust => "C memory reclaimed by Rust - ownership mismatch",
        .borrow_escape => "Borrowed resource escaped across FFI boundary",
        .cross_lang_double_free => "Double free detected across language boundary",
        .orphaned_transfer => "Ownership transferred but never reclaimed",
        .invalid_reclaim => "Reclaim without prior ownership transfer",
        .zig_freed_by_c => "Zig allocator memory freed by C free() - ownership mismatch",
        .go_cstring_leak => "Go cgo CString allocated but not freed - memory leak",
        .go_pointer_stored_in_c => "Go pointer stored in C memory - violates cgo pointer rules",
        .go_pointer_escape => "Go pointer escaped to C code - may cause GC issues",
    };
}

// Unit tests

test "BoundaryDirection enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BoundaryDirection.out));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(BoundaryDirection.in_));
}

test "BoundaryViolation enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BoundaryViolation.rust_freed_by_c));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(BoundaryViolation.cross_lang_double_free));
}

test "BoundaryAnalyzer - init and deinit" {
    var analyzer = BoundaryAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    try std.testing.expectEqual(@as(usize, 0), analyzer.boundaries.items.len);
}

test "BoundaryAnalyzer - registerBoundary" {
    var analyzer = BoundaryAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    const id = analyzer.registerBoundary(
        "c_function",
        .rust,
        .c,
        .out,
        null,
    );
    try std.testing.expectEqual(@as(u32, 1), id);
    try std.testing.expectEqual(@as(usize, 1), analyzer.boundaries.items.len);
}

test "BoundaryAnalyzer - detectLanguage" {
    try std.testing.expectEqual(LanguageHint.rust, BoundaryAnalyzer.detectLanguage("_ZN4core3str"));
    try std.testing.expectEqual(LanguageHint.cpp, BoundaryAnalyzer.detectLanguage("_ZSt4cout"));
    try std.testing.expectEqual(LanguageHint.zig, BoundaryAnalyzer.detectLanguage("zig.main"));
    try std.testing.expectEqual(LanguageHint.c, BoundaryAnalyzer.detectLanguage("malloc"));
}

test "BoundaryAnalyzer - checkOwnershipViolation rust_freed_by_c" {
    var analyzer = BoundaryAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    const resource = ResourceFact{
        .id = 1,
        .origin_fn = "test",
        .owner = .caller,
        .state = .live,
        .action = .alloc,
        .location = null,
        .lang_hint = .rust,
    };

    const boundary = FFIBoundary{
        .id = 1,
        .function_name = "free",
        .caller_lang = .rust,
        .callee_lang = .c,
        .direction = .out,
        .location = null,
    };

    const issue = analyzer.checkOwnershipViolation(
        resource,
        .free,
        .c,
        boundary,
    );

    try std.testing.expect(issue != null);
    try std.testing.expectEqual(BoundaryViolation.rust_freed_by_c, issue.?.kind);
}

test "BoundaryAnalyzer - checkBorrowEscape" {
    var analyzer = BoundaryAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    const resource = ResourceFact{
        .id = 1,
        .origin_fn = "test",
        .owner = .caller,
        .state = .borrowed,
        .action = .borrow,
        .location = null,
        .lang_hint = .rust,
    };

    const boundary = FFIBoundary{
        .id = 1,
        .function_name = "c_store_globally",
        .caller_lang = .rust,
        .callee_lang = .c,
        .direction = .out,
        .location = null,
    };

    const issue = analyzer.checkBorrowEscape(resource, boundary);
    try std.testing.expect(issue != null);
    try std.testing.expectEqual(BoundaryViolation.borrow_escape, issue.?.kind);
}

test "BoundaryAnalyzer - getStats" {
    var analyzer = BoundaryAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    _ = analyzer.registerBoundary("func1", .rust, .c, .out, null);
    _ = analyzer.registerBoundary("func2", .c, .rust, .out, null);

    analyzer.addIssue(.{
        .kind = .rust_freed_by_c,
        .boundary = analyzer.boundaries.items[0],
        .resource_id = 1,
        .description = "test",
        .severity = 4,
    });

    const stats = analyzer.getStats();
    try std.testing.expectEqual(@as(u32, 2), stats.boundary_count);
    try std.testing.expectEqual(@as(u32, 1), stats.issue_count);
    try std.testing.expectEqual(@as(u32, 1), stats.rust_freed_by_c_count);
}

test "detectOwnershipViolation" {
    const result = detectOwnershipViolation(.rust, .c, .live, .free);
    try std.testing.expectEqual(BoundaryViolation.rust_freed_by_c, result);

    const result2 = detectOwnershipViolation(.c, .rust, .live, .free);
    try std.testing.expectEqual(BoundaryViolation.c_freed_by_rust, result2);

    const result3 = detectOwnershipViolation(.c, .c, .live, .free);
    try std.testing.expect(result3 == null);
}

test "formatViolationMessage" {
    const msg = formatViolationMessage(.rust_freed_by_c, .rust, .c);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "C") != null);
}
