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
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");
// Platform profile is consulted when available to disambiguate
// MSVC `?` mangling from plain C names on Windows.
const platform_profile_mod = @import("../semantics/platform_profile.zig");
// NOTE: mapper module removed (dead code, 2026-05-04)
// See untodo.md DEAD-13 for details

pub const SemanticAction = engine.SemanticAction;
pub const LifetimeState = engine.LifetimeState;
pub const Owner = engine.Owner;
pub const LanguageHint = engine.LanguageHint;
pub const ResourceFact = engine.ResourceFact;
pub const IssueType = engine.IssueType;
pub const PlatformProfile = platform_profile_mod.PlatformProfile;

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
    /// Rust memory freed by C++ (ownership mismatch).
    rust_freed_by_cpp,
    /// C++ memory freed by Rust (ownership mismatch).
    cpp_freed_by_rust,
    /// Zig memory freed by Rust (ownership mismatch).
    zig_freed_by_rust,
    /// Rust memory freed by Zig (ownership mismatch).
    rust_freed_by_zig,
    /// C++ memory freed by C (ownership mismatch).
    cpp_freed_by_c,
    /// C memory freed by C++ (ownership mismatch).
    c_freed_by_cpp,
};

/// A detected boundary violation.
pub const BoundaryIssue = struct {
    /// Type of violation.
    kind: BoundaryViolation,
    /// The FFI boundary where this occurred.
    boundary: FFIBoundary,
    /// The resource involved.
    resource_id: u64,
    /// Language that originally allocated the resource.
    origin_lang: LanguageHint,
    /// Language that performed the action.
    action_lang: LanguageHint,
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
            .origin_lang = origin_lang,
            .action_lang = action_lang,
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
                .origin_lang = boundary.caller_lang,
                .action_lang = boundary.callee_lang,
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
                .rust_freed_by_cpp, .cpp_freed_by_rust, .zig_freed_by_rust, .rust_freed_by_zig, .cpp_freed_by_c, .c_freed_by_cpp => {},
            }
        }

        return stats;
    }
};

/// Detect language from function name patterns (platform-agnostic shortcut).
///
/// This is the legacy entry point kept for backward compatibility. It assumes
/// no platform context is available and falls back to pure-name heuristics.
/// New code should prefer [`detectLanguageWithProfile`] so MSVC `?`-mangled
/// symbols are classified as C++ instead of being treated as plain C names.
pub fn detectLanguage(func_name: []const u8) LanguageHint {
    return detectLanguageWithProfile(func_name, null);
}

/// Detect language with optional [`PlatformProfile`] context.
///
/// When `profile` indicates an MSVC Windows target, any name starting with
/// `?` is classified as C++ (Microsoft Visual C++ mangling). Without that
/// context we cannot reliably distinguish MSVC mangled names from plain
/// C symbols that happen to begin with `?` in non-Windows pipelines, so
/// `?`-prefixed names fall through to the default C bucket.
///
/// All other classification rules remain identical to [`detectLanguage`].
///
/// Arguments:
///
///   func_name - Raw function symbol name (mangled or unmangled)
///   profile   - Optional platform profile from the LLVM module
///
/// Returns:
///
///   The detected language hint, defaulting to `.c` when no rule matches.
pub fn detectLanguageWithProfile(
    func_name: []const u8,
    profile: ?*const PlatformProfile,
) LanguageHint {
    // MSVC mangled names always start with `?`. We only honor this signal
    // when the profile confirms a Windows + MSVC ABI; otherwise a stray
    // `?` could be a literal artifact and not a C++ symbol.
    if (func_name.len > 0 and func_name[0] == '?') {
        if (profile) |p| {
            if (p.platform == .windows and p.windows_abi == .msvc) {
                return .cpp;
            }
        }
    }

    // Rust v0 mangling prefix (RFC 2603) — _R<hash>...
    // This is the most reliable Rust indicator for modern Rust (1.37+).
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') {
        return .rust;
    }

    // _ZN (Itanium nested name mangling) — used by BOTH Rust and C++.
    // Must disambiguate using multi-layer detection to avoid misclassification.
    // Rust uses _ZN with: $ separators, hash suffix (h<hex>E), or known namespaces.
    if (func_name.len > 3 and func_name[0] == '_' and func_name[1] == 'Z' and func_name[2] == 'N') {
        if (ffi_language_classifier.isRustMangledName(func_name)) {
            return .rust;
        }
        return .cpp;
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
        return .csharp;
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
        // Rust origin violations
        if (origin_lang == .rust) {
            if (action_lang == .c) return .rust_freed_by_c;
            if (action_lang == .cpp) return .rust_freed_by_cpp;
            if (action_lang == .zig) return .rust_freed_by_zig;
        }

        // C origin violations
        if (origin_lang == .c) {
            if (action_lang == .rust) return .c_freed_by_rust;
            if (action_lang == .cpp) return .c_freed_by_cpp;
            if (action_lang == .go) return .go_pointer_escape;
        }

        // Zig origin violations
        if (origin_lang == .zig) {
            if (action_lang == .c) return .zig_freed_by_c;
            if (action_lang == .rust) return .zig_freed_by_rust;
        }

        // Go origin violations
        if (origin_lang == .go and action_lang == .c) {
            return .go_cstring_leak;
        }

        // C++ origin violations
        if (origin_lang == .cpp) {
            if (action_lang == .c) return .cpp_freed_by_c;
            if (action_lang == .rust) return .cpp_freed_by_rust;
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
pub fn formatViolationMessage(
    allocator: std.mem.Allocator,
    violation: BoundaryViolation,
    origin_lang: LanguageHint,
    action_lang: LanguageHint,
) ![]const u8 {
    const origin = langName(origin_lang);
    const action = langName(action_lang);

    return switch (violation) {
        .rust_freed_by_c => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} free() - ownership mismatch", .{ origin, action }),
        .c_freed_by_rust => try std.fmt.allocPrint(allocator, "{s} memory reclaimed by {s} - ownership mismatch", .{ origin, action }),
        .borrow_escape => try std.fmt.allocPrint(allocator, "Borrowed resource escaped across {s} -> {s} FFI boundary", .{ origin, action }),
        .cross_lang_double_free => try std.fmt.allocPrint(allocator, "Double free detected across {s} -> {s} boundary", .{ origin, action }),
        .orphaned_transfer => try std.fmt.allocPrint(allocator, "Ownership transferred from {s} to {s} but never reclaimed", .{ origin, action }),
        .invalid_reclaim => try std.fmt.allocPrint(allocator, "{s} reclaiming {s} memory without prior ownership transfer", .{ action, origin }),
        .zig_freed_by_c => try std.fmt.allocPrint(allocator, "{s} allocator memory freed by {s} free() - ownership mismatch", .{ origin, action }),
        .go_cstring_leak => try std.fmt.allocPrint(allocator, "{s} cgo CString allocated but not freed - memory leak", .{origin}),
        .go_pointer_stored_in_c => try std.fmt.allocPrint(allocator, "{s} pointer stored in {s} memory - violates cgo pointer rules", .{ origin, action }),
        .go_pointer_escape => try std.fmt.allocPrint(allocator, "{s} pointer escaped to {s} code - may cause GC issues", .{ origin, action }),
        .rust_freed_by_cpp => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
        .cpp_freed_by_rust => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
        .zig_freed_by_rust => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
        .rust_freed_by_zig => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
        .cpp_freed_by_c => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
        .c_freed_by_cpp => try std.fmt.allocPrint(allocator, "{s} memory freed by {s} - ownership mismatch", .{ origin, action }),
    };
}

/// Map LanguageHint to a display name.
fn langName(lang: LanguageHint) []const u8 {
    return switch (lang) {
        .unknown => "Unknown",
        .c => "C",
        .rust => "Rust",
        .zig => "Zig",
        .csharp => "C#",
        .cpp => "C++",
        .go => "Go",
        .julia => "Julia",
        .nim => "Nim",
        .java => "Java",
        .python => "Python",
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
    // Test _R prefix (Rust v0 mangling)
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_RNvCsfLfy6EI15iL_7___rustc"));
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_RINvC1a4main"));

    // Test _ZN with Rust patterns
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_ZN4core3str"));
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_ZN3std2io4Read"));
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_ZN5alloc5alloc8allocate"));

    // Test _ZN with C++ patterns
    try std.testing.expectEqual(LanguageHint.cpp, detectLanguage("_ZN4absl4CordC2"));
    try std.testing.expectEqual(LanguageHint.cpp, detectLanguage("_ZNSt3__112basic_string"));

    // Test plain _Z (C++ Itanium)
    try std.testing.expectEqual(LanguageHint.cpp, detectLanguage("_ZSt4cout"));

    // Test Zig patterns
    try std.testing.expectEqual(LanguageHint.zig, detectLanguage("zig.main"));
    try std.testing.expectEqual(LanguageHint.zig, detectLanguage("Allocator.init"));

    // Test C patterns
    try std.testing.expectEqual(LanguageHint.c, detectLanguage("malloc"));
    try std.testing.expectEqual(LanguageHint.c, detectLanguage("my_function"));
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
        .origin_lang = .rust,
        .action_lang = .c,
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
    const msg = try formatViolationMessage(std.testing.allocator, .rust_freed_by_c, .rust, .c);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "C") != null);
}

test "formatViolationMessage - generic violations include language" {
    const msg = try formatViolationMessage(std.testing.allocator, .borrow_escape, .rust, .c);
    defer std.testing.allocator.free(msg);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Rust") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "C") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "FFI boundary") != null);
}

// ============================================================================
// detectLanguageWithProfile — platform-aware classification tests
// ============================================================================

// Builds a minimal PlatformProfile suitable for the no-allocation tests below.
// All string slices are empty literals so deinit() is never required.
fn makeProfile(
    platform: platform_profile_mod.PlatformKind,
    object_format: platform_profile_mod.ObjectFormat,
    abi: platform_profile_mod.WindowsAbi,
) PlatformProfile {
    return PlatformProfile{
        .platform = platform,
        .object_format = object_format,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
        .windows_abi = abi,
    };
}

test "detectLanguageWithProfile - MSVC ? prefix classifies as cpp on Windows MSVC" {
    // The `?` prefix is unambiguous only on Windows + MSVC. With that profile
    // we expect any leading `?` to map to C++ (MSVC mangling).
    const profile = makeProfile(.windows, .coff, .msvc);
    try std.testing.expectEqual(
        LanguageHint.cpp,
        detectLanguageWithProfile("?square@@YAHH@Z", &profile),
    );
    try std.testing.expectEqual(
        LanguageHint.cpp,
        detectLanguageWithProfile("??0MyClass@@QAE@XZ", &profile),
    );
}

test "detectLanguageWithProfile - MinGW does NOT trigger MSVC ? branch" {
    // MinGW emits Itanium-style mangling, not MSVC `?`. A `?`-prefixed name
    // under MinGW should fall through to the default classifier (C).
    const profile = makeProfile(.windows, .coff, .gnu);
    try std.testing.expectEqual(
        LanguageHint.c,
        detectLanguageWithProfile("?weird_name", &profile),
    );
}

test "detectLanguageWithProfile - non-Windows ignores ? prefix" {
    // Without a Windows+MSVC profile we cannot trust `?` as a C++ signal.
    const linux_profile = makeProfile(.linux, .elf, .unknown);
    try std.testing.expectEqual(
        LanguageHint.c,
        detectLanguageWithProfile("?notcpp", &linux_profile),
    );

    // A null profile (legacy callers) preserves the pre-existing behavior.
    try std.testing.expectEqual(
        LanguageHint.c,
        detectLanguageWithProfile("?notcpp", null),
    );
}

test "detectLanguageWithProfile - Itanium rules still win over profile" {
    // _ZN/_R classification must work regardless of profile so MinGW
    // mangled symbols keep landing in the right bucket.
    const profile = makeProfile(.windows, .coff, .gnu);
    try std.testing.expectEqual(
        LanguageHint.rust,
        detectLanguageWithProfile("_RNvCsfLfy6EI15iL_7___rustc", &profile),
    );
    try std.testing.expectEqual(
        LanguageHint.cpp,
        detectLanguageWithProfile("_ZN4absl4CordC2", &profile),
    );
}

test "detectLanguage - legacy entry point still works without profile" {
    // The legacy signature must remain compatible with existing callers
    // (e.g. root.zig re-export).
    try std.testing.expectEqual(LanguageHint.rust, detectLanguage("_RXX"));
    try std.testing.expectEqual(LanguageHint.cpp, detectLanguage("_ZSt4cout"));
    try std.testing.expectEqual(LanguageHint.c, detectLanguage("malloc"));
}

test "detectLanguageWithProfile - boundary: empty / single-char names" {
    const profile = makeProfile(.windows, .coff, .msvc);
    // Empty input should never crash and should default to .c.
    try std.testing.expectEqual(LanguageHint.c, detectLanguageWithProfile("", &profile));
    // A single `?` on MSVC is still a C++ signal (matches the prefix rule).
    try std.testing.expectEqual(LanguageHint.cpp, detectLanguageWithProfile("?", &profile));
    // A single `?` without an MSVC profile must NOT short-circuit.
    try std.testing.expectEqual(LanguageHint.c, detectLanguageWithProfile("?", null));
}
