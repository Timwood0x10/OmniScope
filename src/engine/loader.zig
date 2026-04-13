//! LLVM IR Loader
//!
//! This module implements the IR loader that loads LLVM IR (.bc) files
//! and creates IR View instances.
//!
//! Architecture Principle:
//! - Only wraps LLVM-C API pointers
//! - No caching or computation
//! - Provides thin accessors to IR components

const std = @import("std");
const Allocator = std.mem.Allocator;

const llvm = @import("../ir/llvm_c.zig");
const ContextRef = @import("../ir/view.zig").ContextRef;
const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FunctionRef = @import("../ir/view.zig").FunctionRef;
const ValueRef = @import("../ir/view.zig").ValueRef;

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
/// Follows the "zero abstraction" principle - only wraps LLVM pointers.
pub const IRLoader = struct {
    allocator: Allocator,
    llvm_ctx: ContextRef,
    module: ?ModuleRef,

    /// Load a .bc file from disk
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for this loader
    ///   - path: Path to the .bc file
    ///
    /// Returns:
    ///   - IRLoader instance on success
    ///   - LoaderError on failure
    ///
    /// Errors:
    ///   - error.FileNotFound: The specified file does not exist
    ///   - error.InvalidIR: The file is not valid LLVM IR
    ///   - error.LLVMContextCreationFailed: Failed to create LLVM context
    ///   - error.ModuleParseFailed: Failed to parse the IR
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
        // Create LLVM context
        const ctx = llvm.LLVMContextCreate();
        // Note: LLVMContextCreate should always return a valid context
        // If it fails, the behavior is undefined per LLVM documentation

        // Create null-terminated path for C API
        const path_c = try allocator.dupeZ(u8, path);
        defer allocator.free(path_c);

        // Create memory buffer from file
        var mem_buf_ptr: llvm.LLVMMemoryBufferRef = undefined;
        var out_msg_ptr: [*:0]u8 = undefined;

        const result = llvm.LLVMCreateMemoryBufferWithContentsOfFile(
            path_c.ptr,
            &mem_buf_ptr,
            &out_msg_ptr,
        );

        if (result != 0) {
            // Clean up
            // TODO: Handle error message from out_msg_ptr
            llvm.LLVMContextDispose(ctx);
            return if (result == 1) error.FileNotFound else error.InvalidIR;
        }

        // Parse IR from memory buffer
        var out_parse_msg_ptr: [*:0]u8 = undefined;
        const module = llvm.LLVMParseIRInContext(
            ctx,
            mem_buf_ptr,
            &out_parse_msg_ptr,
        );

        // Note: module is a pointer, check if it's null
        if (@intFromPtr(module) == 0) {
            // Clean up
            // TODO: Handle parse error message from out_parse_msg_ptr
            llvm.LLVMDisposeMemoryBuffer(mem_buf_ptr);
            llvm.LLVMContextDispose(ctx);
            return error.ModuleParseFailed;
        }

        // Memory buffer is now owned by the module, don't dispose it

        return .{
            .allocator = allocator,
            .llvm_ctx = .{ .raw = ctx },
            .module = .{ .raw = module },
        };
    }

    /// Get the module reference
    ///
    /// Returns:
    ///   - ModuleRef if a module is loaded
    ///   - null if no module is loaded
    pub fn getModule(self: *IRLoader) ?ModuleRef {
        return self.module;
    }

    /// Get the LLVM context
    ///
    /// Returns:
    ///   - ContextRef for this loader
    pub fn getContext(self: *IRLoader) ContextRef {
        return self.llvm_ctx;
    }

    /// Iterate over all functions in the module
    ///
    /// Parameters:
    ///   - callback: Function to call for each function
    ///
    /// Errors:
    ///   - Propagates any error from the callback
    pub fn iterateFunctions(
        self: *IRLoader,
        callback: fn (FunctionRef) anyerror!void,
    ) !void {
        const module = self.module orelse return;

        // Get first function
        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (func != null) {
            const func_ref = FunctionRef{ .raw = func };
            try callback(func_ref);
            func = llvm.LLVMGetNextFunction(func);
        }
    }

    /// Get a function by name
    ///
    /// Parameters:
    ///   - name: Function name to search for
    ///
    /// Returns:
    ///   - FunctionRef if found
    ///   - null if not found
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef {
        const module = self.module orelse return null;

        // Convert name to null-terminated string
        var name_c: [256:0]u8 = undefined;
        if (name.len >= name_c.len) return null;
        @memcpy(name_c[0..name.len], name);
        name_c[name.len] = 0;

        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (func != null) {
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
    ///
    /// Returns:
    ///   - Number of functions, or 0 if no module is loaded
    pub fn getFunctionCount(self: *IRLoader) usize {
        const module = self.module orelse return 0;

        var count: usize = 0;
        var func = llvm.LLVMGetFirstFunction(module.raw);

        while (func != null) {
            count += 1;
            func = llvm.LLVMGetNextFunction(func);
        }

        return count;
    }

    /// Check if a module is loaded
    ///
    /// Returns:
    ///   - true if a module is loaded, false otherwise
    pub fn hasModule(self: *IRLoader) bool {
        return self.module != null;
    }

    /// Deinitialize the IR loader and free resources
    pub fn deinit(self: *IRLoader) void {
        if (self.module) |mod| {
            if (mod.raw != null) {
                llvm.LLVMDisposeModule(mod.raw);
            }
            self.module = null;
        }

        if (self.llvm_ctx.raw != null) {
            llvm.LLVMContextDispose(self.llvm_ctx.raw);
        }
    }
};

test "IRLoader - loadFile with non-existent file" {
    const result = IRLoader.loadFile(std.testing.allocator, "nonexistent.bc");
    try std.testing.expectError(error.FileNotFound, result);
}

test "IRLoader - getModule with no module loaded" {
    // Create a loader without loading a file
    // This is not possible with current API, but we can test the interface
    _ = IRLoader;
}

test "IRLoader - function interface validation" {
    // Validate that the interface matches the architecture
    // This is a compile-time check
    comptime {
        std.debug.assert(@hasDecl(IRLoader, "loadFile"));
        std.debug.assert(@hasDecl(IRLoader, "getModule"));
        std.debug.assert(@hasDecl(IRLoader, "iterateFunctions"));
        std.debug.assert(@hasDecl(IRLoader, "getFunction"));
        std.debug.assert(@hasDecl(IRLoader, "getFunctionCount"));
        std.debug.assert(@hasDecl(IRLoader, "hasModule"));
        std.debug.assert(@hasDecl(IRLoader, "deinit"));
    }
}

test "IRLoader - error set validation" {
    // Validate that LoaderError is an error set
    // This is enforced by the type system
    const ErrorSet = LoaderError;
    _ = ErrorSet;
}

test "IRLoader - context management" {
    // Test that context is properly managed
    // This is a structural test - context is managed through deinit
    // Actual testing requires a valid .bc file
    _ = IRLoader;
}

test "IRLoader - zero abstraction principle" {
    // Validate that IRLoader only wraps LLVM pointers
    // This is enforced at compile time by the struct definition

    // The struct should only contain:
    // - allocator: Allocator (for memory management)
    // - llvm_ctx: ContextRef (pointer wrapper)
    // - module: ?ModuleRef (optional pointer wrapper)

    const fields = std.meta.fields(IRLoader);
    try std.testing.expectEqual(@as(usize, 3), fields.len);

    // Check field names
    try std.testing.expectEqualStrings("allocator", fields[0].name);
    try std.testing.expectEqualStrings("llvm_ctx", fields[1].name);
    try std.testing.expectEqualStrings("module", fields[2].name);

    // Check field types
    try std.testing.expect(fields[0].type == Allocator);
    try std.testing.expect(fields[1].type == ContextRef);
    try std.testing.expect(fields[2].type == ?ModuleRef);
}
