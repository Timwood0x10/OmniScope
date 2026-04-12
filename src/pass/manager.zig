//! Pass manager for scheduling and executing passes
//!
//! This module manages pass registration, dependency resolution,
//! and execution in the correct order.

const std = @import("std");
const Pass = @import("pass.zig").Pass;
const PassContext = @import("pass.zig").PassContext;
const DiagnosticWriter = @import("pass.zig").DiagnosticWriter;
const PassKind = @import("pass.zig").PassKind;

/// Pass manager
pub const PassManager = struct {
    allocator: std.mem.Allocator,
    passes: std.ArrayList(PassEntry),

    const PassEntry = struct {
        name: []const u8,
        kind: PassKind,
        deps: []const []const u8,
        run_fn: *const fn (ctx: *PassContext, diag: *DiagnosticWriter) anyerror!void,
    };

    /// Create a new pass manager
    pub fn init(allocator: std.mem.Allocator) PassManager {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(PassEntry).init(allocator),
        };
    }

    /// Deinitialize the pass manager
    pub fn deinit(self: *PassManager) void {
        self.passes.deinit();
    }

    /// Register a pass with the manager
    pub fn registerPass(
        self: *PassManager,
        comptime T: type,
    ) !void {
        const pass_type = Pass(T);
        const entry = PassEntry{
            .name = pass_type.name,
            .kind = pass_type.kind,
            .deps = pass_type.deps,
            .run_fn = pass_type.run,
        };
        try self.passes.append(entry);
    }

    /// Execute all registered passes in dependency order
    pub fn run(self: *PassManager, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // For now, execute in registration order
        // TODO: Implement topological sort based on dependencies
        for (self.passes.items) |entry| {
            try entry.run_fn(ctx, diag);
        }
    }

    /// Get the number of registered passes
    pub fn count(self: *const PassManager) usize {
        return self.passes.items.len;
    }
};

test "PassManager - init and deinit" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();
    try std.testing.expectEqual(@as(usize, 0), manager.count());
}

test "PassManager - register pass" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(TestPass);
    try std.testing.expectEqual(@as(usize, 1), manager.count());
}

test "PassManager - run passes" {
    var manager = PassManager.init(std.testing.allocator);
    defer manager.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try manager.registerPass(TestPass);

    var ctx = PassContext{ .allocator = std.testing.allocator };
    var diag = DiagnosticWriter{ .allocator = std.testing.allocator };
    try manager.run(&ctx, &diag);
}
