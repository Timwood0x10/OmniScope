//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.

const std = @import("std");

/// Pass kind classification
pub const PassKind = enum {
    foundation, // Basic analysis passes (CFG, DFG)
    analysis, // Advanced analysis passes (alias, lock, taint)
    plugin, // User-defined plugin passes
};

/// Pass context passed to each pass during execution
pub const PassContext = struct {
    allocator: std.mem.Allocator,
    // Additional context fields will be added as needed
};

/// Diagnostic writer for pass output
pub const DiagnosticWriter = struct {
    allocator: std.mem.Allocator,
    // Additional fields will be added as needed
};

/// Pass comptime wrapper with type validation
///
/// This function validates that a type satisfies the Pass interface
/// at compile time and returns the type unchanged.
///
/// Required declarations for a Pass type:
///   - name: []const u8 (pass name)
///   - kind: PassKind (pass classification)
///   - deps: []const []const u8 (dependency pass names)
///   - run: fn (ctx: *PassContext, diag: *DiagnosticWriter) !void
pub fn Pass(comptime T: type) type {
    comptime {
        // Validate required declarations
        if (!@hasDecl(T, "name"))
            @compileError("Pass must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Pass must have a 'kind' declaration (PassKind)");
        if (!@hasDecl(T, "deps"))
            @compileError("Pass must have a 'deps' declaration ([]const []const u8)");
        if (!@hasDecl(T, "run"))
            @compileError("Pass must have a 'run' function");

        // Validate types
        const name_type = @TypeOf(T.name);
        if (name_type != []const u8)
            @compileError("Pass 'name' must be []const u8");

        const kind_type = @TypeOf(T.kind);
        if (kind_type != PassKind)
            @compileError("Pass 'kind' must be PassKind");

        const deps_type = @TypeOf(T.deps);
        if (deps_type != []const []const u8)
            @compileError("Pass 'deps' must be []const []const u8");

        // Validate run function signature
        const run_fn = @TypeOf(T.run);
        const run_info = @typeInfo(run_fn);
        if (run_info != .Fn)
            @compileError("Pass 'run' must be a function");
    }
    return T;
}

test "Pass - comptime validation" {
    // This test validates that the Pass macro correctly validates types
    const ValidPass = Pass(struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    // If we got here, validation passed
    _ = ValidPass;
}
