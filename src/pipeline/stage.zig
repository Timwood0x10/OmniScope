//! Pipeline Stage Interface
//!
//! This module defines the base interface for all pipeline stages.
//! Each stage represents a distinct phase in the analysis pipeline.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Stage execution result
pub const StageResult = union(enum) {
    /// Stage completed successfully
    success,
    /// Stage failed with an error
    failure: []const u8,
    /// Stage was skipped (optional stage)
    skipped,
};

/// Stage context passed to each stage during execution
pub const StageContext = struct {
    allocator: Allocator,
    // Additional context fields will be added as needed
};

/// Stage kind classification
pub const StageKind = enum {
    /// Static analysis stage (IR processing)
    static,
    /// Instrumentation stage (IR modification)
    instrumentation,
    /// Runtime stage (event collection)
    runtime,
    /// Merge stage (data fusion)
    merge,
};

/// Pipeline stage interface
///
/// All pipeline stages must implement this interface.
pub fn Stage(comptime T: type) type {
    comptime {
        // Validate required declarations
        if (!@hasDecl(T, "name"))
            @compileError("Stage must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Stage must have a 'kind' declaration (StageKind)");
        if (!@hasDecl(T, "run"))
            @compileError("Stage must have a 'run' function");
    }
    return T;
}

test "Stage - comptime validation" {
    const ValidStage = Stage(struct {
        pub const name = "test-stage";
        pub const kind = StageKind.static;
        pub fn run(ctx: *StageContext) StageResult {
            _ = ctx;
            return .success;
        }
    });

    _ = ValidStage;
}
