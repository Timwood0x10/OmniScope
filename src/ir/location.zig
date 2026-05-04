//! Source code location information
//!
//! This module provides types for tracking source code locations
//! for diagnostics and instrumentation.
//!
//! Location type is now imported from common/types.zig for consistency.
//! This module re-exports it for backward compatibility and provides
//! LocationId for efficient storage.

const std = @import("std");
const CommonTypes = @import("../common/types.zig");

/// Re-export Location from common/types.zig.
/// New code should import from common/types.zig directly.
pub const Location = CommonTypes.Location;

/// Compressed location ID for efficient storage
/// Format: file_id (16 bits) | line (12 bits) | column (4 bits)
pub const LocationId = u32;

test "Location - init and validation" {
    const loc = Location.initWithFile("test.zig", "test", 10, 5);
    try std.testing.expect(loc.hasValidPosition());
    try std.testing.expect(loc.hasFilePath());
}

test "Location - invalid location" {
    const loc = Location.init("testFunction");
    try std.testing.expect(!loc.hasValidPosition());
}
