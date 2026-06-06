//! Issue Filtering — Multi-layer issue filtering for OmniScope
//!
//! Extracted from main.zig: filterIssues, isBoundaryIssueFast,
//! isFFIIssueKind, matchesSurfaceFilter, classifySurfaces,
//! isRuntimeInternalFunction, and related test helpers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Location = OmniScope.diag.Location;
const Severity = OmniScope.diag.Severity;
const Confidence = OmniScope.diag.Confidence;
const FFIBoundary = OmniScope.diag.FFIBoundary;
const CommonTypes = OmniScope.common.types;
const log = OmniScope.log;

const main_config = OmniScope.config.main_config;
const Config = main_config.Config;

/// Filter issues based on config settings (boundary_only, min_severity, surface_filter).
pub fn filterIssues(allocator: std.mem.Allocator, issues: []const Issue, config: Config) ![]Issue {
    var filtered = std.ArrayList(Issue).initCapacity(allocator, issues.len) catch return error.OutOfMemory;
    errdefer filtered.deinit(allocator);

    const should_check_boundary = config.boundary_only;
    const min_sev_int: u8 = config.min_severity.toInt();
    const surface_filter_enabled = config.surface_filter.isEnabled();

    for (issues) |issue| {
        const issue_sev: u8 = @intFromEnum(issue.severity);
        if (issue_sev < min_sev_int) continue;

        if (should_check_boundary) {
            if (!isBoundaryIssueFast(issue)) continue;
        }

        if (surface_filter_enabled) {
            if (!matchesSurfaceFilter(issue, config.surface_filter)) continue;
        }

        try filtered.append(allocator, issue);
    }

    return filtered.toOwnedSlice(allocator);
}

/// Multi-layer check for FFI boundary issues (optimized version).
fn isBoundaryIssueFast(issue: Issue) bool {
    if (issue.semantic_surface) |surface| {
        return switch (surface) {
            .boundary, .ffi_producer => true,
            .reachable_from_boundary => false,
            .internal_core, .runtime_internal, .unknown => false,
        };
    }

    if (issue.ffi_boundary != null) return true;

    return isFFIIssueKind(issue.kind);
}

/// Check if an issue kind is typically FFI-related.
fn isFFIIssueKind(kind: IssueKind) bool {
    return switch (kind) {
        .cross_language_leak,
        .cross_language_free,
        .ffi_unsafe_call,
        .ffi_type_mismatch,
        .memory_leak,
        .use_after_free,
        => true,

        .buffer_overflow,
        .integer_overflow,
        .format_string,
        => false,

        else => false,
    };
}

/// Check surface filter configuration against an issue's semantic surface.
fn matchesSurfaceFilter(issue: Issue, filter: main_config.SurfaceFilterConfig) bool {
    const surface = issue.semantic_surface orelse return true;

    return switch (surface) {
        .boundary => filter.show_boundary,
        .ffi_producer => filter.show_ffi_producer,
        .reachable_from_boundary => filter.show_reachable_from_boundary,
        .internal_core => filter.show_internal_core,
        .runtime_internal => filter.show_runtime_internal,
        .unknown => true,
    };
}

/// Classify semantic surfaces for all issues (post-processing step).
pub fn classifySurfaces(issues: []Issue) void {
    for (issues) |*issue| {
        if (issue.semantic_surface != null) continue;

        if (isFFIIssueKind(issue.kind)) {
            if (issue.ffi_boundary != null) {
                issue.semantic_surface = .boundary;
            } else {
                if (issue.severity == .critical or issue.severity == .high) {
                    issue.semantic_surface = .ffi_producer;
                } else {
                    issue.semantic_surface = .reachable_from_boundary;
                }
            }
        } else {
            const func_name = issue.location.func;
            if (isRuntimeInternalFunction(func_name)) {
                issue.semantic_surface = .runtime_internal;
            } else {
                issue.semantic_surface = .internal_core;
            }
        }
    }
}

/// Check if a function name looks like language runtime internal code.
fn isRuntimeInternalFunction(func_name: []const u8) bool {
    const runtime_patterns = [_][]const u8{
        "rust_begin_unwind",
        "__zig_dealloc",
        "runtime.mallocgc",
        "drop_in_place",
        "__pthread_start",
        "_ZNSt",
    };

    for (runtime_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

// ============================================================================
// Test Helper Functions
// ============================================================================

/// Create a test issue with explicit semantic surface.
fn makeTestIssue(kind: IssueKind, severity: Severity, surface: ?CommonTypes.SemanticSurface) Issue {
    const is_boundary = if (surface) |s| s == .boundary or s == .ffi_producer else false;
    return Issue{
        .kind = kind,
        .message = "test issue",
        .location = Location.init("test_function"),
        .severity = severity,
        .confidence = 0.8,
        .confidence_level = Confidence.fromScore(0.8),
        .reason = "test reason",
        .semantic_surface = surface,
        .escape_evidence = null,
        .explained_safe = false,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
        .function_owned = false,
        .classification = if (is_boundary) .ffi_boundary else .local_only,
        .resource_family = null,
        .release_family = null,
        .verdict = null,
        .adjusted_score = null,
        .is_contract_based = false,
    };
}

/// Create a test issue with FFI boundary information (no semantic_surface set).
fn makeTestIssueWithFFI(kind: IssueKind, severity: Severity) Issue {
    const loc = Location.init("ffi_wrapper");
    return Issue{
        .kind = kind,
        .message = "test FFI issue",
        .location = loc,
        .severity = severity,
        .confidence = 0.85,
        .confidence_level = Confidence.fromScore(0.85),
        .reason = "FFI test",
        .semantic_surface = null,
        .escape_evidence = null,
        .explained_safe = false,
        .ffi_boundary = FFIBoundary.init(
            1,
            .rust_to_c,
            .rust,
            .c,
            "external_c_func",
            loc,
        ),
        .trace = null,
        .owned = false,
        .function_owned = false,
        .classification = .local_only,
        .resource_family = null,
        .release_family = null,
        .verdict = null,
        .adjusted_score = null,
        .is_contract_based = false,
    };
}

// ============================================================================
// Boundary-Only Filtering Tests
// ============================================================================

test "filterIssues - boundary only filters correctly" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .high, .boundary),
        makeTestIssue(.buffer_overflow, .medium, .internal_core),
        makeTestIssue(.ffi_unsafe_call, .critical, .ffi_producer),
        makeTestIssue(.format_string, .low, .runtime_internal),
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.boundary_only = true;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 2), filtered.len);
    try std.testing.expectEqual(IssueKind.cross_language_leak, filtered[0].kind);
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, filtered[1].kind);
}

test "filterIssues - min-severity threshold works" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.memory_leak, .low, .internal_core),
        makeTestIssue(.buffer_overflow, .medium, .internal_core),
        makeTestIssue(.use_after_free, .high, .boundary),
        makeTestIssue(.double_free, .critical, .boundary),
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.min_severity = .medium;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 3), filtered.len);
    try std.testing.expectEqual(Severity.medium, filtered[0].severity);
    try std.testing.expectEqual(Severity.high, filtered[1].severity);
    try std.testing.expectEqual(Severity.critical, filtered[2].severity);
}

test "filterIssues - combined boundary_only + min_severity" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .low, .boundary),
        makeTestIssue(.buffer_overflow, .high, .internal_core),
        makeTestIssue(.ffi_unsafe_call, .critical, .ffi_producer),
        makeTestIssue(.memory_leak, .high, .reachable_from_boundary),
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.boundary_only = true;
    config.min_severity = .high;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, filtered[0].kind);
}

test "filterIssues - surface_filter fine-grained control" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .high, .boundary),
        makeTestIssue(.ffi_type_mismatch, .high, .ffi_producer),
        makeTestIssue(.memory_leak, .medium, .reachable_from_boundary),
        makeTestIssue(.buffer_overflow, .medium, .internal_core),
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.surface_filter.show_reachable_from_boundary = false;
    config.surface_filter.show_internal_core = false;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 2), filtered.len);
}

test "classifySurfaces - fills semantic_surface for unclassified issues" {
    var issues = [_]Issue{
        Issue{
            .kind = .cross_language_leak,
            .message = "",
            .location = Location.init("test"),
            .severity = .high,
            .confidence = 0.9,
            .confidence_level = .high,
            .reason = "",
            .semantic_surface = .boundary,
            .escape_evidence = null,
            .explained_safe = false,
            .ffi_boundary = null,
            .trace = null,
            .owned = false,
            .function_owned = false,
            .classification = .ffi_boundary,
            .resource_family = null,
            .release_family = null,
            .verdict = null,
            .adjusted_score = null,
            .is_contract_based = false,
        },
        makeTestIssueWithFFI(.ffi_unsafe_call, .high),
        makeTestIssue(.cross_language_free, .high, null),
        makeTestIssue(.buffer_overflow, .medium, null),
    };

    classifySurfaces(&issues);

    try std.testing.expect(issues[0].semantic_surface.? == .boundary);
    try std.testing.expect(issues[1].semantic_surface.? == .boundary);
    try std.testing.expect(issues[2].semantic_surface.? == .ffi_producer);
    try std.testing.expect(issues[3].semantic_surface.? == .internal_core);
}

test "isBoundaryIssueFast - multi-layer check works" {
    const issue_boundary = makeTestIssue(.cross_language_leak, .high, .boundary);
    try std.testing.expect(isBoundaryIssueFast(issue_boundary));

    const issue_internal = makeTestIssue(.buffer_overflow, .medium, .internal_core);
    try std.testing.expect(!isBoundaryIssueFast(issue_internal));

    const issue_with_ffi = makeTestIssueWithFFI(.ffi_type_mismatch, .critical);
    try std.testing.expect(isBoundaryIssueFast(issue_with_ffi));

    const issue_ffi_kind = makeTestIssue(.cross_language_free, .medium, null);
    try std.testing.expect(isBoundaryIssueFast(issue_ffi_kind));

    const issue_non_ffi = makeTestIssue(.format_string, .low, null);
    try std.testing.expect(!isBoundaryIssueFast(issue_non_ffi));
}

test "isRuntimeInternalFunction - detects runtime patterns" {
    try std.testing.expect(isRuntimeInternalFunction("rust_begin_unwind"));
    try std.testing.expect(isRuntimeInternalFunction("__zig_dealloc"));
    try std.testing.expect(isRuntimeInternalFunction("runtime.mallocgc"));
    try std.testing.expect(isRuntimeInternalFunction("drop_in_place"));
    try std.testing.expect(!isRuntimeInternalFunction("my_application_func"));
    try std.testing.expect(!isRuntimeInternalFunction("malloc"));
}
