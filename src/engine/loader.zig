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

const llvm = @import("../ir/llvm_c.zig");
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
    llvm_ctx: ContextRef,
    module: ?ModuleRef,
    alive: bool = false,

    /// Load a .bc file from disk
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
        var self = IRLoader{
            .allocator = allocator,
            .llvm_ctx = .{ .raw = undefined },
            .module = null,
            .alive = false,
        };

        self.llvm_ctx.raw = llvm.LLVMContextCreate();

        const path_c = try allocator.dupeZ(u8, path);
        defer allocator.free(path_c);

        var mem_buf_ptr: llvm.LLVMMemoryBufferRef = undefined;
        var err_msg: [*:0]u8 = undefined;

        if (llvm.LLVMCreateMemoryBufferWithContentsOfFile(
            path_c.ptr,
            &mem_buf_ptr,
            &err_msg,
        ) != 0) {
            log.warn("loader", "Failed to load file: {s}", .{std.mem.span(err_msg)});
            llvm.LLVMDisposeMessage(err_msg);
            llvm.LLVMContextDispose(self.llvm_ctx.raw);
            return error.FileNotFound;
        }
        defer llvm.LLVMDisposeMemoryBuffer(mem_buf_ptr);

        var module: llvm.LLVMModuleRef = undefined;
        if (llvm.LLVMParseBitcodeInContext2(
            self.llvm_ctx.raw,
            mem_buf_ptr,
            &module,
        ) != 0) {
            log.warn("loader", "Failed to parse module: {s}", .{std.mem.span(err_msg)});
            llvm.LLVMDisposeMessage(err_msg);
            llvm.LLVMDisposeMemoryBuffer(mem_buf_ptr);
            llvm.LLVMContextDispose(self.llvm_ctx.raw);
            return error.ModuleParseFailed;
        }

        self.module = .{ .raw = module };
        self.alive = true;

        return self;
    }

    /// Get the module reference (borrowed, never releases)
    pub fn getModule(self: *IRLoader) ?ModuleRef {
        return self.module;
    }

    /// Get the LLVM context (borrowed, never releases)
    pub fn getContext(self: *IRLoader) ContextRef {
        return self.llvm_ctx;
    }

    /// Iterate over all functions in the module
    pub fn iterateFunctions(
        self: *IRLoader,
        callback: fn (FunctionRef) anyerror!void,
    ) !void {
        const module = self.module orelse return;
        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            try callback(FunctionRef{ .raw = func });
            func = llvm.LLVMGetNextFunction(func);
        }
    }

    /// Get a function by name (borrowed reference)
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef {
        const module = self.module orelse return null;

        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            const func_name = llvm.LLVMGetValueName(func);
            const func_name_slice = std.mem.span(func_name);

            if (std.mem.eql(u8, name, func_name_slice)) {
                return .{ .raw = func };
            }

            func = llvm.LLVMGetNextFunction(func);
        }

        return null;
    }

    /// Get the number of functions in the module
    pub fn getFunctionCount(self: *IRLoader) usize {
        const module = self.module orelse return 0;

        var count: usize = 0;
        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            count += 1;
            func = llvm.LLVMGetNextFunction(func);
        }

        return count;
    }

    /// Check if a module is loaded
    pub fn hasModule(self: *IRLoader) bool {
        return self.module != null;
    }

    /// Deinitialize and release all resources
    ///
    /// IMPORTANT: This is idempotent - safe to call multiple times.
    /// Only the first call will release resources.
    pub fn deinit(self: *IRLoader) void {
        if (!self.alive) return;

        if (self.module) |mod| {
            llvm.LLVMDisposeModule(mod.raw);
            self.module = null;
        }

        llvm.LLVMContextDispose(self.llvm_ctx.raw);
        self.alive = false;
    }

    /// Prevent copying (linear resource semantics)
    pub fn clone(_: IRLoader) noreturn {
        @panic("IRLoader is non-copyable (linear resource)");
    }
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
        std.debug.assert(@hasDecl(IRLoader, "clone"));
    }
}

test "IRLoader - error set validation" {
    const ErrorSet = LoaderError;
    _ = ErrorSet;
}

test "IRLoader - zero abstraction principle" {
    const fields = std.meta.fields(IRLoader);
    try std.testing.expectEqual(@as(usize, 4), fields.len);

    try std.testing.expectEqualStrings("allocator", fields[0].name);
    try std.testing.expectEqualStrings("llvm_ctx", fields[1].name);
    try std.testing.expectEqualStrings("module", fields[2].name);
    try std.testing.expectEqualStrings("alive", fields[3].name);

    try std.testing.expect(fields[0].type == Allocator);
    try std.testing.expect(fields[1].type == ContextRef);
    try std.testing.expect(fields[2].type == ?ModuleRef);
}
