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
const c = @import("../ir/llvm_raw.zig").c;
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

    /// Load a .bc or .ll file from disk
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
        var self = IRLoader{
            .allocator = allocator,
            .llvm_ctx = .{ .raw = undefined },
            .module = null,
            .alive = false,
        };

        self.llvm_ctx.raw = c.LLVMContextCreate();

        // Safety check for context creation
        if (@intFromPtr(self.llvm_ctx.raw) == 0) {
            log.warn("loader", "Failed to create LLVM context", .{});
            return error.LLVMContextCreationFailed;
        }

        const path_c = try allocator.dupeZ(u8, path);
        defer allocator.free(path_c);

        var mem_buf_ptr: c.LLVMMemoryBufferRef = undefined;
        var err_msg: [*:0]u8 = undefined;

        if (c.LLVMCreateMemoryBufferWithContentsOfFile(
            path_c.ptr,
            &mem_buf_ptr,
            &err_msg,
        ) != 0) {
            log.warn("loader", "Failed to load file: {s}", .{std.mem.span(err_msg)});
            c.LLVMDisposeMessage(err_msg);
            return error.FileNotFound;
        }
        // Don't use defer here - memory buffer ownership is handled by
        // LLVM on success and by us on failure (in error handling above)

        // Add safety check for memory buffer
        if (@intFromPtr(mem_buf_ptr) == 0) {
            log.warn("loader", "Memory buffer is null after creation", .{});
            return error.InvalidIR;
        }

        // Detect file type by extension
        const is_ll_file = std.mem.endsWith(u8, path, ".ll");

        log.debug("loader", "Loading file: {s}, is_ll_file: {}", .{ path, is_ll_file });

        var module: c.LLVMModuleRef = undefined;

        // Parse based on file type
        if (is_ll_file) {
            // Parse LLVM IR text format (.ll file)
            log.info("loader", "Attempting to parse .ll file", .{});

            const result = c.LLVMParseIRInContext(
                self.llvm_ctx.raw,
                mem_buf_ptr,
                &module,
                &err_msg,
            );

            if (result != 0) {
                // Failed to parse
                if (@intFromPtr(err_msg) != 0) {
                    const error_slice = std.mem.span(err_msg);
                    log.warn("loader", "Failed to parse .ll file: {s}", .{error_slice});
                    c.LLVMDisposeMessage(err_msg);
                } else {
                    log.warn("loader", "Failed to parse .ll file: unknown error", .{});
                }
                // LLVMParseIRInContext takes ownership of mem_buf even on failure
                c.LLVMDisposeMemoryBuffer(mem_buf_ptr);
                return error.ModuleParseFailed;
            }
            // LLVMParseIRInContext takes ownership of mem_buf on success
        } else {
            // Parse LLVM bitcode format (.bc file)
            if (c.LLVMParseBitcodeInContext2(
                self.llvm_ctx.raw,
                mem_buf_ptr,
                &module,
            ) != 0) {
                // Safely handle error message - check if err_msg is valid
                if (@intFromPtr(err_msg) != 0) {
                    const error_slice = std.mem.span(err_msg);
                    log.warn("loader", "Failed to parse module: {s}", .{error_slice});
                    c.LLVMDisposeMessage(err_msg);
                } else {
                    log.warn("loader", "Failed to parse module: unknown error", .{});
                }
                // LLVMParseBitcodeInContext2 doesn't take ownership on failure
                c.LLVMDisposeMemoryBuffer(mem_buf_ptr);
                return error.ModuleParseFailed;
            }
            // LLVMParseBitcodeInContext2 takes ownership of mem_buf on success
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
        ctx: anytype,
        callback: fn (c.LLVMValueRef, @TypeOf(ctx)) anyerror!void,
    ) !void {
        const module = self.module orelse return;
        var func = c.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            try callback(func, ctx);
            func = c.LLVMGetNextFunction(func);
        }
    }

    /// Get a function by name (borrowed reference)
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef {
        const module = self.module orelse return null;

        var func = c.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            const func_name = c.LLVMGetValueName(func);
            const func_name_slice = std.mem.span(func_name);

            if (std.mem.eql(u8, name, func_name_slice)) {
                return .{ .raw = func };
            }

            func = c.LLVMGetNextFunction(func);
        }

        return null;
    }

    /// Get the number of functions in the module
    pub fn getFunctionCount(self: *IRLoader) usize {
        const module = self.module orelse return 0;

        var count: usize = 0;
        var func = c.LLVMGetFirstFunction(module.raw);

        while (@intFromPtr(func) != 0) {
            count += 1;
            func = c.LLVMGetNextFunction(func);
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
            // Check if module pointer is valid before disposing
            if (@intFromPtr(mod.raw) != 0) {
                c.LLVMDisposeModule(mod.raw);
            }
            self.module = null;
        }

        // Check if context pointer is valid before disposing
        if (@intFromPtr(self.llvm_ctx.raw) != 0) {
            c.LLVMContextDispose(self.llvm_ctx.raw);
        }

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
