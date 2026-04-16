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
    /// Unknown issue type
    unknown,

    /// Convert issue kind to string representation
    pub fn toString(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "ffi_unsafe_call",
            .unchecked_return => "unchecked_return",
            .type_mismatch => "type_mismatch",
            .cross_language_leak => "cross_language_leak",
            .use_after_free => "use_after_free",
            .command_injection => "command_injection",
            .buffer_overflow => "buffer_overflow",
            .double_free => "double_free",
            .format_string => "format_string",
            .unknown => "unknown",
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
        /// Rust language
        rust,
        /// Zig language
        zig,
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
