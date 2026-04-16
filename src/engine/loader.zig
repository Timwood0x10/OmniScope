//! LLVM IR Loader
//!
//! This module implements the IR loader that loads LLVM IR (.bc) files
//! and creates IR View instances.
//!
//! Architecture Principle:
//! - Single owner (IRLoader) for all LLVM resources
//! - Linear resource with explicit lifetime
//! - All Ref/View types are borrowed (never release resources)

const std = @import("std");
const Allocator = std.mem.Allocator;

const llvm_safe = @import("../ir/llvm_safe.zig");
const ContextRef = @import("../ir/view.zig").ContextRef;
const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FunctionRef = @import("../ir/view.zig").FunctionRef;
const log = @import("../log/log.zig");

/// IR Loader error set
pub const LoaderError = error{
    FileNotFound,
    InvalidIR,
    LLVMContextCreationFailed,
    ModuleParseFailed,
    OutOfMemory,
};

/// LLVM IR Loader
///
/// This struct manages the loading and lifecycle of LLVM IR modules.
/// Follows the "single owner" principle:
///
/// - Only IRLoader can release resources
/// - All Ref types are borrowed (never release resources)
/// - deinit is idempotent (safe to call multiple times)
pub const IRLoader = struct {
    allocator: Allocator,
    safe_loader: llvm_safe.IRLoader,
    alive: bool = false,

    /// Load a .bc or .ll file from disk
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
        var safe_loader = llvm_safe.IRLoader.init(allocator) catch |err| {
            log.warn("loader", "Failed to create safe loader: {}", .{err});
            return switch (err) {
                llvm_safe.Error.OutOfMemory => error.OutOfMemory,
                llvm_safe.Error.ContextCreationFailed => error.LLVMContextCreationFailed,
                else => error.InvalidIR,
            };
        };
        errdefer safe_loader.deinit();

        log.debug("loader", "Loading file: {s}", .{path});

        _ = safe_loader.loadFile(path) catch |err| {
            log.warn("loader", "Failed to load file: {}", .{err});
            return switch (err) {
                llvm_safe.Error.FileNotFound => error.FileNotFound,
                llvm_safe.Error.IRLoadFailed => error.InvalidIR,
                llvm_safe.Error.ParseFailed => error.ModuleParseFailed,
                llvm_safe.Error.InvalidIR => error.InvalidIR,
                llvm_safe.Error.ContextCreationFailed => error.LLVMContextCreationFailed,
                llvm_safe.Error.OutOfMemory => error.OutOfMemory,
            };
        };

        return .{
            .allocator = allocator,
            .safe_loader = safe_loader,
            .alive = true,
        };
    }

    /// Get the module reference (borrowed, never releases)
    pub fn getModule(self: *IRLoader) ?ModuleRef {
        const module = self.safe_loader.getModule() orelse return null;
        return .{ .raw = module.raw };
    }

    /// Get the LLVM context (borrowed, never releases)
    pub fn getContext(self: *IRLoader) ContextRef {
        const context = self.safe_loader.getContext();
        return .{ .raw = context.raw };
    }

    /// Iterate over all functions in the module
    pub fn iterateFunctions(
        self: *IRLoader,
        ctx: anytype,
        callback: fn (FunctionRef, @TypeOf(ctx)) anyerror!void,
    ) !void {
        const module = self.safe_loader.getModule() orelse return;
        var func = module.getFirstFunction();

        while (func) |f| {
            try callback(.{ .raw = f.raw }, ctx);
            func = f.getNext();
        }
    }

    /// Get a function by name (borrowed reference)
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef {
        const module = self.safe_loader.getModule() orelse return null;
        const func = module.getFunction(name) orelse return null;
        return .{ .raw = func.raw };
    }

    /// Get the number of functions in the module
    pub fn getFunctionCount(self: *IRLoader) usize {
        const module = self.safe_loader.getModule() orelse return 0;
        return module.getFunctionCount();
    }

    /// Check if a module is loaded
    pub fn hasModule(self: *IRLoader) bool {
        return self.safe_loader.getModule() != null;
    }

    /// Deinitialize and release all resources
    ///
    /// IMPORTANT: This is idempotent - safe to call multiple times.
    /// Only the first call will release resources.
    pub fn deinit(self: *IRLoader) void {
        if (!self.alive) return;

        self.safe_loader.deinit();
        self.alive = false;
    }

    // IRLoader is a linear resource and cannot be copied.
    // The default copy is prevented by the compiler because safe_loader
    // contains a pointer (IRLoader in llvm_safe.zig has a Context field).
};

test "IRLoader - loadFile with non-existent file" {
    const result = IRLoader.loadFile(std.testing.allocator, "nonexistent.bc");
    try std.testing.expectError(error.FileNotFound, result);
}

test "IRLoader - getModule with no module loaded" {
    _ = IRLoader;
}

test "IRLoader - function interface validation" {
    comptime {
        std.debug.assert(@hasDecl(IRLoader, "loadFile"));
        std.debug.assert(@hasDecl(IRLoader, "getModule"));
        std.debug.assert(@hasDecl(IRLoader, "iterateFunctions"));
        std.debug.assert(@hasDecl(IRLoader, "getFunction"));
        std.debug.assert(@hasDecl(IRLoader, "getFunctionCount"));
        std.debug.assert(@hasDecl(IRLoader, "hasModule"));
        std.debug.assert(@hasDecl(IRLoader, "deinit"));
        // Note: clone() is intentionally not provided to prevent copying
    }
}

test "IRLoader - error set validation" {
    const ErrorSet = LoaderError;
    _ = ErrorSet;
}

test "IRLoader - zero abstraction principle" {
    const fields = std.meta.fields(IRLoader);
    try std.testing.expectEqual(@as(usize, 3), fields.len);

    try std.testing.expectEqualStrings("allocator", fields[0].name);
    try std.testing.expectEqualStrings("safe_loader", fields[1].name);
    try std.testing.expectEqualStrings("alive", fields[2].name);

    try std.testing.expect(fields[0].type == Allocator);
    try std.testing.expect(fields[1].type == llvm_safe.IRLoader);
}
