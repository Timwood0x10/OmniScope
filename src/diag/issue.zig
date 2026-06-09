//! Issue Types and Definitions
//!
//! This module provides the core issue types used throughout the analysis.
//! Issues represent security problems or code quality issues detected during analysis.
//!
//! Type definitions (Location, Severity, IssueKind, Confidence) are now imported
//! from common/types.zig for consistency across all modules.

const std = @import("std");

// Import unified type definitions from common/types.zig
const CommonTypes = @import("../common/types.zig");

/// Re-export core types for backward compatibility.
/// All new code should import directly from common/types.zig.
pub const Location = CommonTypes.Location;
pub const Severity = CommonTypes.Severity;
pub const IssueKind = CommonTypes.IssueKind;
pub const Confidence = CommonTypes.Confidence;
pub const SemanticSurface = CommonTypes.SemanticSurface;
const ContractTransition = @import("../semantics/resource/contract.zig").ContractTransition;

/// Trace entry for issue reasoning path
///
/// Represents a single step in the reasoning path that led to
/// detecting an issue. Used for SARIF code flows and debugging.
pub const TraceEntry = struct {
    /// Description of this trace step
    description: []const u8,
    /// Optional location for this step
    location: ?Location,
    /// Whether the description string is owned
    owned: bool,

    /// Create a trace entry with borrowed description
    pub fn init(description: []const u8) TraceEntry {
        return .{
            .description = description,
            .location = null,
            .owned = false,
        };
    }

    /// Create a trace entry with owned description
    pub fn initOwned(description: []const u8) TraceEntry {
        return .{
            .description = description,
            .location = null,
            .owned = true,
        };
    }

    /// Create a trace entry with location
    pub fn initWithLocation(description: []const u8, location: Location) TraceEntry {
        return .{
            .description = description,
            .location = location,
            .owned = false,
        };
    }

    /// Free owned memory
    pub fn deinit(self: *TraceEntry, allocator: std.mem.Allocator) void {
        if (self.owned and self.description.len > 0) {
            allocator.free(self.description);
        }
    }
};

/// Issue classification for 90/10 priority (FFI focus vs general memory)
pub const IssueClassification = enum(u8) {
    /// FFI boundary violation - 90% core priority
    ffi_boundary,
    /// Local-only memory issue - 10% auxiliary priority
    local_only,
};

/// Issue represents a detected security problem
///
/// ## Memory Ownership Model (DC-C3 FIX)
///
/// Issue uses **explicit ownership tags** to prevent memory leaks and double-free:
///
/// ### Ownership Fields
/// - `owned: bool` - If `true`, caller owns `message` and `trace` heap memory
///   - When `owned=true`: `deinit()` will free message and trace
///   - When `owned=false`: Message/trace are string literals or borrowed slices
///
/// - `function_owned: bool` - If `true`, `location.function` is heap-allocated
///   - When `function_owned=true`: `deinit()` will free location.function
///   - When `function_owned=false`: location.function is a borrowed slice
///
/// ### Ownership Transfer Rules
/// 1. **Caller-owned** (`owned=false`, default): Pass owns nothing, don't free
/// 2. **Callee-owned** (`owned=true`): Pass takes ownership, must call deinit()
/// 3. **Deep-copy**: Use `initWithOwnedMessage()` for callee-owned copies
/// 4. **Borrowed**: Temporary references, neither side frees
///
/// ### Usage Pattern
/// ```zig
/// // Pattern 1: Borrowed (stack literals, most common)
/// var issue = Issue.init(.memory_leak, "le detected", loc, .medium, 0.8);
/// // owned=false, no deinit() needed
///
/// // Pattern 2: Owned (heap-allocated messages)
/// var issue = Issue.initWithOwnedMessage(allocator, .memory_leak,
///     try allocator.dupe(u8, "heap msg"), loc, .medium, 0.8);
/// defer issue.deinit(allocator); // MUST free message
///
/// // Pattern 3: Transfer to collection (addIssue takes ownership)
/// try issues.append(issue); // If issue.owned=true, collection now owns it
/// ```
///
/// This struct contains all information about a detected issue including
/// its type, location, severity, and optional context about FFI boundaries.
pub const Issue = struct {
    /// Type of the issue
    kind: IssueKind,
    /// Human-readable description of the issue
    message: []const u8,
    /// Location where the issue was detected
    location: Location,
    /// Severity level of the issue
    severity: Severity,
    /// Confidence score (0.0 - 1.0)
    confidence: f32,
    /// Confidence level (HIGH / MEDIUM / HEURISTIC / EXPERIMENTAL)
    confidence_level: Confidence,
    /// Reason explaining why this confidence level was assigned
    reason: []const u8,

    // P19: Structural evidence fields (optional, default null for backward compat)
    /// Semantic surface: where does this issue originate?
    /// Used by pass_types.addIssue() for severity gating per Phase 19.2.
    semantic_surface: ?SemanticSurface = null,

    /// Escape/transfer evidence: how did the pointer escape the function?
    /// Derived from IR structural analysis (P19-2).
    /// Maps to ContractTransition.Trigger values.
    escape_evidence: ?ContractTransition.Trigger = null,

    /// Whether this issue has been explained as safe by structural analysis.
    /// When true, severity should be capped at .low or suppressed entirely.
    explained_safe: bool = false,

    /// Related FFI boundary if applicable
    ffi_boundary: ?FFIBoundary,
    /// Trace entries showing reasoning path
    trace: ?[]TraceEntry,
    /// Whether message and trace are owned
    owned: bool,
    /// Whether location.function is heap-allocated and should be freed
    function_owned: bool,
    /// Classification tag for 90/10 priority
    /// - ffi_boundary: 90% core - reaches FFI/unsafe boundary
    /// - local_only: 10% auxiliary - local memory issue
    classification: IssueClassification,
    /// Resource family classification for this issue.
    resource_family: ?[]const u8 = null,
    /// Release/deallocation family if applicable.
    release_family: ?[]const u8 = null,
    /// Verified verdict from the two-stage verifier (P8).
    verdict: ?[]const u8 = null,
    /// Adjusted risk score after verification [0.0, 1.0].
    adjusted_score: ?f32 = null,
    /// Whether this issue was generated by the new contract-based system.
    is_contract_based: bool = false,

    /// Create a new issue
    ///
    /// Parameters:
    ///   - kind: Type of the issue
    ///   - message: Description of the issue
    ///   - location: Location where issue was detected
    ///   - severity: Severity level
    ///   - confidence: Confidence score (0.0 - 1.0)
    ///
    /// Returns:
    ///   - A new Issue instance
    pub fn init(
        kind: IssueKind,
        message: []const u8,
        location: Location,
        severity: Severity,
        confidence: f32,
    ) Issue {
        return .{
            .kind = kind,
            .message = message,
            .location = location,
            .severity = severity,
            .confidence = confidence,
            .confidence_level = Confidence.fromScore(confidence),
            .reason = "",
            .ffi_boundary = null,
            .trace = null,
            .owned = false,
            .function_owned = false,
            .classification = .local_only, // Default to local-only
            .resource_family = null,
            .release_family = null,
            .verdict = null,
            .adjusted_score = null,
            .is_contract_based = false,
        };
    }

    /// Create a new issue with reason
    pub fn initWithReason(
        kind: IssueKind,
        message: []const u8,
        location: Location,
        severity: Severity,
        confidence: f32,
        reason: []const u8,
    ) Issue {
        return .{
            .kind = kind,
            .message = message,
            .location = location,
            .severity = severity,
            .confidence = confidence,
            .confidence_level = Confidence.fromScore(confidence),
            .reason = reason,
            .ffi_boundary = null,
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

    /// Create a new issue with trace entries
    ///
    /// Parameters:
    ///   - kind: Type of the issue
    ///   - message: Description of the issue (owned)
    ///   - location: Location where issue was detected
    ///   - severity: Severity level
    ///   - confidence: Confidence score (0.0 - 1.0)
    ///   - trace: Trace entries showing reasoning path (owned)
    ///
    /// Returns:
    pub fn initWithTrace(
        kind: IssueKind,
        message: []const u8,
        location: Location,
        severity: Severity,
        confidence: f32,
        trace: []TraceEntry,
    ) Issue {
        return .{
            .kind = kind,
            .message = message,
            .location = location,
            .severity = severity,
            .confidence = confidence,
            .confidence_level = Confidence.fromScore(confidence),
            .reason = "",
            .ffi_boundary = null,
            .trace = trace,
            .owned = true,
            .function_owned = false,
            .classification = .local_only,
            .resource_family = null,
            .release_family = null,
            .verdict = null,
            .adjusted_score = null,
            .is_contract_based = false,
        };
    }

    /// Set FFI boundary for this issue
    ///
    /// Parameters:
    ///   - boundary: The FFI boundary related to this issue
    pub fn setFFIBoundary(self: *Issue, boundary: FFIBoundary) void {
        self.ffi_boundary = boundary;
    }

    /// Check if issue has FFI boundary
    ///
    /// Returns:
    ///   - true if issue has associated FFI boundary
    pub fn hasFFIBoundary(self: *const Issue) bool {
        return self.ffi_boundary != null;
    }

    /// Check if issue has trace entries
    ///
    /// Returns:
    ///   - true if issue has trace entries
    pub fn hasTrace(self: *const Issue) bool {
        return self.trace != null and self.trace.?.len > 0;
    }

    /// Free owned memory
    pub fn deinit(self: *Issue, allocator: std.mem.Allocator) void {
        if (self.owned) {
            if (self.message.len > 0) {
                allocator.free(self.message);
            }
            if (self.function_owned and self.location.func.len > 0) {
                allocator.free(self.location.func);
            }
            if (self.trace) |trace| {
                for (trace) |*entry| {
                    entry.deinit(allocator);
                }
                allocator.free(trace);
            }
        }
    }
};

/// FFI boundary information
///
/// Contains information about a Foreign Function Interface boundary
/// where data crosses language boundaries.
pub const FFIBoundary = struct {
    /// Unique identifier for this boundary
    id: u32,
    /// Type of FFI boundary
    kind: BoundaryKind,
    /// Language of the caller
    caller_language: Language,
    /// Language of the callee
    callee_language: Language,
    /// Function name at the boundary
    function_name: []const u8,
    /// Location of the boundary
    location: Location,

    /// FFI boundary type enumeration
    pub const BoundaryKind = enum {
        /// Rust calling C
        rust_to_c,
        /// Zig calling C
        zig_to_c,
        /// C calling Rust
        c_to_rust,
        /// C calling Zig
        c_to_zig,
        /// Dynamic library loading (dlopen/dlsym/dlclose)
        dynamic_loading,
        /// Java Native Interface call
        jni_call,
        /// Python C API call
        python_c_api_call,
        /// Unknown external call
        external_unknown,
    };

    /// Language type enumeration for cross-language FFI analysis.
    /// Used by MemoryGraph.alloc_lang, FFIBoundary, and cross_language_free detection.
    pub const Language = enum {
        /// C language
        c,
        /// C++ language
        cpp,
        /// Rust language
        rust,
        /// Zig language
        zig,
        /// C# / .NET language (P/Invoke, NativeAOT)
        csharp,
        /// Go language (including cgo)
        go,
        /// Java/JNI language
        java,
        /// Python/C API language
        python,
        /// Unknown / undetermined language
        unknown,
    };

    /// Create a new FFI boundary
    ///
    /// Parameters:
    ///   - id: Unique identifier
    ///   - kind: Type of boundary
    ///   - caller_language: Language of caller
    ///   - callee_language: Language of callee
    ///   - function_name: Function name at boundary
    ///   - location: Location of boundary
    ///
    /// Returns:
    ///   - A new FFIBoundary instance
    pub fn init(
        id: u32,
        kind: BoundaryKind,
        caller_language: Language,
        callee_language: Language,
        function_name: []const u8,
        location: Location,
    ) FFIBoundary {
        return .{
            .id = id,
            .kind = kind,
            .caller_language = caller_language,
            .callee_language = callee_language,
            .function_name = function_name,
            .location = location,
        };
    }

    /// Check if this is a cross-language boundary
    ///
    /// Returns:
    ///   - true if caller and callee languages are different
    pub fn isCrossLanguage(self: *const FFIBoundary) bool {
        return self.caller_language != self.callee_language;
    }
};

// Unit tests

test "IssueKind - toString" {
    try std.testing.expectEqualStrings("ffi_unsafe_call", IssueKind.ffi_unsafe_call.toString());
    try std.testing.expectEqualStrings("unchecked_return", IssueKind.unchecked_return.toString());
    try std.testing.expectEqualStrings("callback_signature_mismatch", IssueKind.callback_signature_mismatch.toString());
    try std.testing.expectEqualStrings("unknown", IssueKind.unknown.toString());
}

test "Severity - toString" {
    try std.testing.expectEqualStrings("low", Severity.low.toString());
    try std.testing.expectEqualStrings("critical", Severity.critical.toString());
}

test "Issue - init" {
    const location = Location.init("test_func");
    const issue = Issue.init(
        .ffi_unsafe_call,
        "Test message",
        location,
        .high,
        0.9,
    );

    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, issue.kind);
    try std.testing.expectEqualStrings("Test message", issue.message);
    try std.testing.expectEqual(Severity.high, issue.severity);
    try std.testing.expectEqual(@as(f32, 0.9), issue.confidence);
}

test "Issue - setFFIBoundary" {
    const location = Location.init("test_func");
    var issue = Issue.init(
        .ffi_unsafe_call,
        "Test message",
        location,
        .high,
        0.9,
    );

    try std.testing.expect(!issue.hasFFIBoundary());

    const boundary = FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );
    issue.setFFIBoundary(boundary);

    try std.testing.expect(issue.hasFFIBoundary());
}

test "Location - init" {
    const location = Location.init("test_func");
    try std.testing.expectEqualStrings("test_func", location.func);
    try std.testing.expect(location.file == null);
    try std.testing.expect(location.line == 0);
}

test "Location - initWithFile" {
    const location = Location.initWithFile("test.zig", "test_func", 42, 10);
    try std.testing.expectEqualStrings("test_func", location.func);
    try std.testing.expectEqualStrings("test.zig", location.file.?);
    try std.testing.expectEqual(@as(u32, 42), location.line);
    try std.testing.expectEqual(@as(u32, 10), location.column);
}

test "Location - hasFilePath" {
    const location1 = Location.init("test_func");
    try std.testing.expect(!location1.hasFilePath());

    const location2 = Location.initWithFile("test.zig", "test_func", 0, 0);
    try std.testing.expect(location2.hasFilePath());
}

test "Location - displayName" {
    // Test minimal location (func only)
    const location1 = Location.init("test_func");
    try std.testing.expectEqualStrings("test_func", location1.displayName());

    // Test full location (file available)
    const location2 = Location.initWithFile("test.zig", "test_func", 42, 10);
    try std.testing.expectEqualStrings("test.zig", location2.displayName());
}

test "FFIBoundary - init" {
    const location = Location.init("test_func");
    const boundary = FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );

    try std.testing.expectEqual(@as(u32, 1), boundary.id);
    try std.testing.expectEqual(FFIBoundary.BoundaryKind.rust_to_c, boundary.kind);
    try std.testing.expectEqual(FFIBoundary.Language.rust, boundary.caller_language);
    try std.testing.expectEqual(FFIBoundary.Language.c, boundary.callee_language);
}

test "FFIBoundary - isCrossLanguage" {
    const location = Location.init("test_func");

    // Cross-language boundary
    const boundary1 = FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );
    try std.testing.expect(boundary1.isCrossLanguage());

    // Same-language boundary
    const boundary2 = FFIBoundary.init(
        2,
        .rust_to_c,
        .rust,
        .rust,
        "rust_func",
        location,
    );
    try std.testing.expect(!boundary2.isCrossLanguage());
}

test "TraceEntry - init" {
    const entry = TraceEntry.init("Test trace entry");
    try std.testing.expectEqualStrings("Test trace entry", entry.description);
    try std.testing.expect(!entry.owned);
    try std.testing.expect(entry.location == null);
}

test "TraceEntry - initOwned" {
    const allocator = std.testing.allocator;
    const desc = try allocator.dupe(u8, "Owned trace entry");
    var entry = TraceEntry.initOwned(desc);
    try std.testing.expectEqualStrings("Owned trace entry", entry.description);
    try std.testing.expect(entry.owned);
    entry.deinit(allocator);
}

test "TraceEntry - initWithLocation" {
    const location = Location.init("test_func");
    const entry = TraceEntry.initWithLocation("Trace with location", location);
    try std.testing.expectEqualStrings("Trace with location", entry.description);
    try std.testing.expect(entry.location != null);
}

test "Issue - initWithTrace" {
    const allocator = std.testing.allocator;
    const location = Location.init("test_func");

    const trace = try allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Step 1");
    trace[1] = TraceEntry.init("Step 2");

    const message = try allocator.dupe(u8, "Test with trace");
    var issue = Issue.initWithTrace(
        .malloc_unchecked,
        message,
        location,
        .high,
        0.85,
        trace,
    );

    try std.testing.expectEqual(IssueKind.malloc_unchecked, issue.kind);
    try std.testing.expect(issue.hasTrace());
    try std.testing.expectEqual(@as(usize, 2), issue.trace.?.len);
    try std.testing.expect(issue.owned);

    issue.deinit(allocator);
}

test "Issue - hasTrace" {
    const location = Location.init("test_func");

    // Issue without trace
    const issue1 = Issue.init(.ffi_unsafe_call, "No trace", location, .high, 0.9);
    try std.testing.expect(!issue1.hasTrace());

    // Issue with empty trace
    const issue2 = Issue{
        .kind = .ffi_unsafe_call,
        .message = "Empty trace",
        .location = location,
        .severity = .high,
        .confidence = 0.9,
        .confidence_level = .high,
        .reason = "",
        .ffi_boundary = null,
        .trace = &[_]TraceEntry{},
        .owned = false,
        .function_owned = false,
        .classification = .local_only,
    };
    try std.testing.expect(!issue2.hasTrace());
}

test "Issue - deinit" {
    const allocator = std.testing.allocator;
    const location = Location.init("test_func");

    const trace = try allocator.alloc(TraceEntry, 1);
    trace[0] = TraceEntry.initOwned(try allocator.dupe(u8, "Owned step"));

    const message = try allocator.dupe(u8, "Owned message");
    var issue = Issue.initWithTrace(
        .invalid_free,
        message,
        location,
        .medium,
        0.75,
        trace,
    );

    // Should not crash
    issue.deinit(allocator);
}

test "IssueKind - toCweId" {
    try std.testing.expectEqual(@as(u32, 78), IssueKind.command_injection.toCweId());
    try std.testing.expectEqual(@as(u32, 120), IssueKind.buffer_overflow.toCweId());
    try std.testing.expectEqual(@as(u32, 252), IssueKind.malloc_unchecked.toCweId());
    try std.testing.expectEqual(@as(u32, 590), IssueKind.invalid_free.toCweId());
    try std.testing.expectEqual(@as(u32, 688), IssueKind.callback_signature_mismatch.toCweId());
}

test "IssueKind - toDescription" {
    try std.testing.expectEqualStrings("Command injection vulnerability", IssueKind.command_injection.toDescription());
    try std.testing.expectEqualStrings("Malloc result used without null check", IssueKind.malloc_unchecked.toDescription());
    try std.testing.expectEqualStrings("Free called on non-malloc pointer", IssueKind.invalid_free.toDescription());
    try std.testing.expectEqualStrings("Callback signature does not match receiver expectation - potential ABI mismatch", IssueKind.callback_signature_mismatch.toDescription());
}

test "Confidence - toString" {
    try std.testing.expectEqualStrings("HIGH", Confidence.high.toString());
    try std.testing.expectEqualStrings("MEDIUM", Confidence.medium.toString());
    try std.testing.expectEqualStrings("HEURISTIC", Confidence.heuristic.toString());
    try std.testing.expectEqualStrings("EXPERIMENTAL", Confidence.experimental.toString());
}

test "Confidence - fromScore" {
    try std.testing.expectEqual(Confidence.high, Confidence.fromScore(1.0));
    try std.testing.expectEqual(Confidence.high, Confidence.fromScore(0.9));
    try std.testing.expectEqual(Confidence.high, Confidence.fromScore(0.95));
    try std.testing.expectEqual(Confidence.medium, Confidence.fromScore(0.85));
    try std.testing.expectEqual(Confidence.medium, Confidence.fromScore(0.7));
    try std.testing.expectEqual(Confidence.heuristic, Confidence.fromScore(0.55));
    try std.testing.expectEqual(Confidence.heuristic, Confidence.fromScore(0.5));
    try std.testing.expectEqual(Confidence.experimental, Confidence.fromScore(0.4));
    try std.testing.expectEqual(Confidence.experimental, Confidence.fromScore(0.0));
}

test "Confidence - defaultScore" {
    const testApproxEq = struct {
        fn run(expected: f32, actual: f32, tolerance: f32) !void {
            try std.testing.expect(@abs(actual - expected) < tolerance);
        }
    }.run;

    try testApproxEq(@as(f32, 0.95), Confidence.high.defaultScore(), 0.01);
    try testApproxEq(@as(f32, 0.75), Confidence.medium.defaultScore(), 0.01);
    try testApproxEq(@as(f32, 0.55), Confidence.heuristic.defaultScore(), 0.01);
    try testApproxEq(@as(f32, 0.35), Confidence.experimental.defaultScore(), 0.01);
}

test "Issue - confidence_level auto-derived from score" {
    const location = Location.init("test_func");

    const issue_high = Issue.init(.memory_leak, "high confidence", location, .high, 0.95);
    try std.testing.expectEqual(Confidence.high, issue_high.confidence_level);

    const issue_medium = Issue.init(.null_dereference, "medium confidence", location, .critical, 0.75);
    try std.testing.expectEqual(Confidence.medium, issue_medium.confidence_level);

    const issue_heuristic = Issue.init(.double_free, "heuristic confidence", location, .medium, 0.55);
    try std.testing.expectEqual(Confidence.heuristic, issue_heuristic.confidence_level);

    const issue_exp = Issue.init(.use_after_free, "experimental", location, .high, 0.3);
    try std.testing.expectEqual(Confidence.experimental, issue_exp.confidence_level);
}
