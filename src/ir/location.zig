//! Source code location information
//!
//! This module provides types for tracking source code locations
//! for diagnostics and instrumentation.

/// Source code location
pub const Location = struct {
    /// File path
    file: []const u8,
    /// Line number (1-indexed)
    line: u32,
    /// Column number (1-indexed)
    column: u32,

    /// Create a new location
    pub fn init(file: []const u8, line: u32, column: u32) Location {
        return .{
            .file = file,
            .line = line,
            .column = column,
        };
    }

    /// Check if location is valid
    pub fn isValid(self: Location) bool {
        return self.line > 0 and self.column > 0;
    }
};

/// Compressed location ID for efficient storage
/// Format: file_id (16 bits) | line (12 bits) | column (4 bits)
pub const LocationId = u32;

test "Location - init and validation" {
    const loc = Location.init("test.zig", 10, 5);
    try std.testing.expect(loc.isValid());
}

test "Location - invalid location" {
    const loc = Location.init("test.zig", 0, 0);
    try std.testing.expect(!loc.isValid());
}

const std = @import("std");
