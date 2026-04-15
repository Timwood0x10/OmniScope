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
        const path_c = try std.cstr.addZ(self.allocator, path);
        defer self.allocator.free(path_c);

        var mem_buf: c.LLVMMemoryBufferRef = undefined;
        var err_msg: [*:0]u8 = undefined;

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
        
        var module_raw: c.LLVMModuleRef = undefined;
        var result: c_int = undefined;

        if (is_ll_file) {
            // Parse LLVM IR text format (.ll)
            result = c.LLVMParseIRInContext(
                self.context.raw,
                mem_buf,
                &module_raw,
                &err_msg,
            );
        } else {
            // Parse LLVM bitcode format (.bc)
            result = c.LLVMParseBitcodeInContext2(
                self.context.raw,
                mem_buf,
                &module_raw,
            );
        }

        if (result != 0) {
            defer if (err_msg != null) c.LLVMDisposeMessage(err_msg);
            c.LLVMDisposeMemoryBuffer(mem_buf);
            return Error.ParseFailed;
        }

        self.module = .{ .raw = module_raw };
        return self.module.?;
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
pub fn parseIR(allocator: Allocator, path: []const u8) !Module {
    var loader = try IRLoader.init(allocator);
    defer loader.deinit();
    
    return loader.loadFile(path);
}