//! LLVM-C API Safe Wrapper Layer
//!
//! This layer provides safe, Zig-style interfaces to LLVM C API.
//! All error handling and lifetime management is handled here.
//!
//! Usage: Always use this layer, never access llvm_raw.c directly.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("llvm_raw.zig").c;

/// Error types for LLVM operations
pub const Error = error{
    IRLoadFailed,
    ParseFailed,
    InvalidIR,
    ContextCreationFailed,
    FileNotFound,
    OutOfMemory,
};

/// Safe wrapper for LLVM Context
pub const Context = struct {
    raw: c.LLVMContextRef,

    /// Create a new LLVM context
    pub fn init() !Context {
        const ctx = c.LLVMContextCreate();
        if (ctx == null) return Error.ContextCreationFailed;

        return .{ .raw = ctx };
    }

    /// Destroy the context and all associated resources
    pub fn deinit(self: Context) void {
        c.LLVMContextDispose(self.raw);
    }
};

/// Safe wrapper for LLVM Module
pub const Module = struct {
    raw: c.LLVMModuleRef,

    /// Destroy the module
    pub fn deinit(self: Module) void {
        c.LLVMDisposeModule(self.raw);
    }

    /// Get the number of functions in the module
    pub fn getFunctionCount(self: Module) usize {
        var count: usize = 0;
        var func = c.LLVMGetFirstFunction(self.raw);

        while (func != null) : (func = c.LLVMGetNextFunction(func)) {
            count += 1;
        }

        return count;
    }

    /// Get the first function in the module
    pub fn getFirstFunction(self: Module) ?Function {
        const func = c.LLVMGetFirstFunction(self.raw);
        if (func == null) return null;
        return .{ .raw = func };
    }

    /// Get a function by name
    pub fn getFunction(self: Module, name: []const u8) ?Function {
        var func = c.LLVMGetFirstFunction(self.raw);

        while (func != null) : (func = c.LLVMGetNextFunction(func)) {
            const func_name = c.LLVMGetValueName(func);
            const func_name_slice = std.mem.span(func_name);

            if (std.mem.eql(u8, name, func_name_slice)) {
                return .{ .raw = func };
            }
        }

        return null;
    }

    /// Iterate over all functions in the module
    pub fn iterateFunctions(
        self: Module,
        ctx: anytype,
        callback: fn (Function, @TypeOf(ctx)) anyerror!void,
    ) !void {
        var func = c.LLVMGetFirstFunction(self.raw);

        while (func != null) : (func = c.LLVMGetNextFunction(func)) {
            try callback(.{ .raw = func }, ctx);
        }
    }
};

/// Safe wrapper for LLVM Function
pub const Function = struct {
    raw: c.LLVMValueRef,

    /// Get the function name (owned copy)
    pub fn getName(self: Function, allocator: Allocator) ![]u8 {
        const name_ptr = c.LLVMGetValueName(self.raw);
        const name_span = std.mem.span(name_ptr);
        return try allocator.dupe(u8, name_span);
    }

    /// Check if the function is a declaration (extern)
    pub fn isDeclaration(self: Function) bool {
        return c.LLVMIsDeclaration(self.raw) != 0;
    }

    /// Get the next function in the module
    pub fn getNext(self: Function) ?Function {
        const next = c.LLVMGetNextFunction(self.raw);
        if (next == null) return null;
        return .{ .raw = next };
    }
};

/// Safe wrapper for LLVM IR loading
pub const IRLoader = struct {
    allocator: Allocator,
    context: Context,
    module: ?Module,

    /// Create a new IR loader
    pub fn init(allocator: Allocator) !IRLoader {
        const context = try Context.init();

        return .{
            .allocator = allocator,
            .context = context,
            .module = null,
        };
    }

    /// Load LLVM IR from a file (.bc or .ll)
    pub fn loadFile(self: *IRLoader, path: []const u8) !Module {
        if (path.len == 0) return Error.FileNotFound;

        const path_c = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_c);

        var mem_buf: c.LLVMMemoryBufferRef = undefined;
        var err_msg: [*c]u8 = undefined;

        // Create memory buffer from file
        if (c.LLVMCreateMemoryBufferWithContentsOfFile(
            path_c,
            &mem_buf,
            &err_msg,
        ) != 0) {
            defer if (err_msg != null) c.LLVMDisposeMessage(err_msg);
            return Error.FileNotFound;
        }

        // Detect file type
        const is_ll_file = std.mem.endsWith(u8, path, ".ll");

        var module_raw: c.LLVMModuleRef = null;
        var parse_result: c.LLVMBool = 0;

        if (is_ll_file) {
            // Parse LLVM IR text format (.ll)
            parse_result = c.LLVMParseIRInContext(
                self.context.raw,
                mem_buf,
                &module_raw,
                &err_msg,
            );
        } else {
            // Parse LLVM bitcode format (.bc)
            parse_result = c.LLVMParseBitcodeInContext2(
                self.context.raw,
                mem_buf,
                &module_raw,
            );
        }

        if (parse_result != 0 or module_raw == null) {
            defer if (err_msg != null) c.LLVMDisposeMessage(err_msg);
            c.LLVMDisposeMemoryBuffer(mem_buf);
            return Error.ParseFailed;
        }

        self.module = .{ .raw = module_raw };
        return self.module.?;
    }

    /// Get the module
    pub fn getModule(self: *IRLoader) ?Module {
        return self.module;
    }

    /// Get the context
    pub fn getContext(self: *IRLoader) Context {
        return self.context;
    }

    /// Deinitialize the loader
    pub fn deinit(self: *IRLoader) void {
        if (self.module) |mod| {
            mod.deinit();
            self.module = null;
        }
        self.context.deinit();
    }
};

/// Parse LLVM IR from a file with proper error handling
///
/// DEPRECATED: This function is fundamentally broken and should not be used.
/// The returned Module holds a pointer to memory that is freed by loader.deinit().
/// Use IRLoader directly and manage its lifecycle appropriately instead.
///
/// Example correct usage:
///   var loader = try IRLoader.init(allocator);
///   defer loader.deinit();
///   const module = try loader.loadFile(path);
///   // use module while loader is still alive
pub fn parseIR(allocator: Allocator, path: []const u8) !Module {
    _ = allocator;
    _ = path;
    return Error.IRLoadFailed;
}

test "parseIR - deprecated function should not be used" {
    // parseIR is deprecated because it returns a dangling Module.
    // Use IRLoader directly instead.
    const result = parseIR(std.testing.allocator, "nonexistent_file.bc");
    try std.testing.expectError(Error.IRLoadFailed, result);
}
