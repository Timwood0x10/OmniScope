//! Issue Types and Definitions
//!
//! This module defines the core issue types used throughout the analysis.
//! Issues represent security problems or code quality issues detected during analysis.

const std = @import("std");

/// Issue type enumeration
///
/// Defines the categories of security issues that can be detected.
pub const IssueKind = enum {
    /// FFI call without proper safety validation
    ffi_unsafe_call,
    /// Function return value not checked after call
    unchecked_return,
    /// Type mismatch across FFI boundary
    type_mismatch,
    /// Memory leak across language boundary
    cross_language_leak,
    /// General memory leak (not necessarily cross-language)
    memory_leak,
    /// Use after free across language boundary
    use_after_free,
    /// Command injection vulnerability
    command_injection,
    /// Buffer overflow vulnerability
    buffer_overflow,
    /// Double free across language boundary
    double_free,
    /// Format string vulnerability
    format_string,
    /// Malloc result used without null check
    malloc_unchecked,
    /// Null pointer dereference (nullable allocation used without guard)
    null_dereference,
    /// Free called on non-malloc pointer
    invalid_free,
    /// Unknown issue type
    unknown,

    /// Convert issue kind to string representation
    pub fn toString(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "ffi_unsafe_call",
            .unchecked_return => "unchecked_return",
            .type_mismatch => "type_mismatch",
            .cross_language_leak => "cross_language_leak",
            .memory_leak => "memory_leak",
            .use_after_free => "use_after_free",
            .command_injection => "command_injection",
            .buffer_overflow => "buffer_overflow",
            .double_free => "double_free",
            .format_string => "format_string",
            .malloc_unchecked => "malloc_unchecked",
            .null_dereference => "null_dereference",
            .invalid_free => "invalid_free",
            .unknown => "unknown",
        };
    }

    /// Get CWE (Common Weakness Enumeration) ID for this issue kind
    ///
    /// Returns the CWE ID associated with this issue type.
    pub fn toCweId(self: IssueKind) u32 {
        return switch (self) {
            .ffi_unsafe_call => 668, // CWE-668: Exposure of Resource to Wrong Sphere
            .unchecked_return => 252, // CWE-252: Unchecked Return Value
            .type_mismatch => 704, // CWE-704: Incorrect Type Conversion or Cast
            .cross_language_leak => 401, // CWE-401: Memory Leak
            .memory_leak => 401, // CWE-401: Memory Leak
            .use_after_free => 416, // CWE-416: Use After Free
            .command_injection => 78, // CWE-78: OS Command Injection
            .buffer_overflow => 120, // CWE-120: Buffer Overflow
            .double_free => 415, // CWE-415: Double Free
            .format_string => 134, // CWE-134: Format String Vulnerability
            .malloc_unchecked => 252, // CWE-252: Unchecked Return Value
            .null_dereference => 476, // CWE-476: NULL Pointer Dereference
            .invalid_free => 590, // CWE-590: Free of Memory Not on Heap
            .unknown => 0,
        };
    }

    /// Get human-readable description for this issue kind
    pub fn toDescription(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "FFI call without proper safety validation",
            .unchecked_return => "Function return value not checked after call",
            .type_mismatch => "Type mismatch across FFI boundary",
            .cross_language_leak => "Memory leak across language boundary",
            .memory_leak => "Memory allocated but never freed",
            .use_after_free => "Use after free across language boundary",
            .command_injection => "Command injection vulnerability",
            .buffer_overflow => "Buffer overflow vulnerability",
            .double_free => "Double free across language boundary",
            .format_string => "Format string vulnerability",
            .malloc_unchecked => "Malloc result used without null check",
            .null_dereference => "Null pointer dereference - nullable allocation used without guard",
            .invalid_free => "Free called on non-malloc pointer",
            .unknown => "Unknown issue type",
        };
    }
};

/// Severity level enumeration
///
/// Defines the severity levels for issues.
pub const Severity = enum(u8) {
    /// Low severity issue
    low = 0,
    /// Medium severity issue
    medium = 1,
    /// High severity issue
    high = 2,
    /// Critical severity issue
    critical = 3,

    /// Convert severity to string representation
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
            .critical => "critical",
        };
    }

    /// Get severity color code for terminal output
    pub fn toColorCode(self: Severity) []const u8 {
        return switch (self) {
            .low => "\x1b[36m", // Cyan
            .medium => "\x1b[33m", // Yellow
            .high => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

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

/// Issue represents a detected security problem
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
    /// Related FFI boundary if applicable
    ffi_boundary: ?FFIBoundary,
    /// Trace entries showing reasoning path
    trace: ?[]TraceEntry,
    /// Whether message and trace are owned
    owned: bool,

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
            .ffi_boundary = null,
            .trace = null,
            .owned = false,
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
    ///   - A new Issue instance with trace
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
            .ffi_boundary = null,
            .trace = trace,
            .owned = true,
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
            if (self.trace) |trace| {
                for (trace) |*entry| {
                    entry.deinit(allocator);
                }
                allocator.free(trace);
            }
        }
    }
};

/// Location information for an issue
///
/// Contains the location where an issue was detected, including function,
/// file, line, and column information.
pub const Location = struct {
    /// Function name where issue was detected
    function: []const u8,
    /// File name (optional, may not be available)
    file: ?[]const u8,
    /// Line number (optional, may not be available)
    line: ?u32,
    /// Column number (optional, may not be available)
    column: ?u32,

    /// Create a new location with minimal information
    ///
    /// Parameters:
    ///   - function: Function name
    ///
    /// Returns:
    ///   - A new Location instance
    pub fn init(function: []const u8) Location {
        return .{
            .function = function,
            .file = null,
            .line = null,
            .column = null,
        };
    }

    /// Create a new location with full information
    ///
    /// Parameters:
    ///   - function: Function name
    ///   - file: File name
    ///   - line: Line number
    ///   - column: Column number
    ///
    /// Returns:
    ///   - A new Location instance
    pub fn initFull(function: []const u8, file: []const u8, line: u32, column: u32) Location {
        return .{
            .function = function,
            .file = file,
            .line = line,
            .column = column,
        };
    }

    /// Set file information
    ///
    /// Parameters:
    ///   - file: File name
    pub fn setFile(self: *Location, file: []const u8) void {
        self.file = file;
    }

    /// Set line information
    ///
    /// Parameters:
    ///   - line: Line number
    pub fn setLine(self: *Location, line: u32) void {
        self.line = line;
    }

    /// Set column information
    ///
    /// Parameters:
    ///   - column: Column number
    pub fn setColumn(self: *Location, column: u32) void {
        self.column = column;
    }

    /// Format location as string
    ///
    /// Returns:
    ///   - String representation of location
    pub fn format(self: *const Location, allocator: std.mem.Allocator) ![]const u8 {
        if (self.file) |file| {
            if (self.line) |line| {
                if (self.column) |column| {
                    return std.fmt.allocPrint(allocator, "{s}:{d}:{d}", .{ file, line, column });
                }
                return std.fmt.allocPrint(allocator, "{s}:{d}", .{ file, line });
            }
            return std.fmt.allocPrint(allocator, "{s}", .{file});
        }
        return std.fmt.allocPrint(allocator, "{s}", .{self.function});
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
        /// Unknown external call
        external_unknown,
    };

    /// Language type enumeration
    pub const Language = enum {
        /// C language
        c,
        /// C++ language
        cpp,
        /// Rust language
        rust,
        /// Zig language
        zig,
        /// Swift language
        swift,
        /// Go language
        go,
        /// Unknown language
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
    try std.testing.expectEqualStrings("test_func", location.function);
    try std.testing.expect(location.file == null);
    try std.testing.expect(location.line == null);
}

test "Location - initFull" {
    const location = Location.initFull("test_func", "test.zig", 42, 10);
    try std.testing.expectEqualStrings("test_func", location.function);
    try std.testing.expectEqualStrings("test.zig", location.file.?);
    try std.testing.expectEqual(@as(u32, 42), location.line.?);
    try std.testing.expectEqual(@as(u32, 10), location.column.?);
}

test "Location - setFile" {
    var location = Location.init("test_func");
    try std.testing.expect(location.file == null);

    location.setFile("test.zig");
    try std.testing.expectEqualStrings("test.zig", location.file.?);
}

test "Location - format" {
    var allocator = std.testing.allocator;

    // Test minimal location
    const location1 = Location.init("test_func");
    const formatted1 = try location1.format(allocator);
    defer allocator.free(formatted1);
    try std.testing.expectEqualStrings("test_func", formatted1);

    // Test full location
    const location2 = Location.initFull("test_func", "test.zig", 42, 10);
    const formatted2 = try location2.format(allocator);
    defer allocator.free(formatted2);
    try std.testing.expectEqualStrings("test.zig:42:10", formatted2);
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
        .ffi_boundary = null,
        .trace = &[_]TraceEntry{},
        .owned = false,
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
}

test "IssueKind - toDescription" {
    try std.testing.expectEqualStrings("Command injection vulnerability", IssueKind.command_injection.toDescription());
    try std.testing.expectEqualStrings("Malloc result used without null check", IssueKind.malloc_unchecked.toDescription());
    try std.testing.expectEqualStrings("Free called on non-malloc pointer", IssueKind.invalid_free.toDescription());
}
