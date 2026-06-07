//! LLVM-C API Safe Wrapper Layer
//!
//! This layer provides safe, Zig-style interfaces to LLVM C API.
//! All error handling and lifetime management is handled here.
//!
//! Usage: Always use this layer, never access llvm_raw.c directly.

const std = @import("std");
const log = @import("../common/log.zig");
const Allocator = std.mem.Allocator;
const c = @import("llvm_raw.zig").c;

// C++ bridge for direct LLVM IR parsing (avoids llvm-as external dependency).
// Declares the remaining C-compatible functions from llvm_cpp_bridge.cpp.
const cpp = struct {
    extern fn omni_parse_ir_file(path: [*:0]const u8, ctx: ?*anyopaque, module_out: ?*?*anyopaque, error_out: ?*?[*:0]u8) c_int;
    extern fn omni_free_string(str: ?*anyopaque) void;
};

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

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
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

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
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

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
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

        const is_ll_file = std.mem.endsWith(u8, path, ".ll");

        var module_raw: c.LLVMModuleRef = null;

        if (is_ll_file) {
            // LLVM 22: LLVMParseIRInContext segfaults on text IR (address 0x8).
            // Root cause: LLVM 22's IR text parser requires target/machine init
            // that the C API context doesn't provide by default.
            // Fix: Use C++ bridge (llvm::parseIRFile) which handles this correctly.
            // Fallback: llvm-as conversion if C++ bridge is unavailable.

            // Try C++ bridge first (direct llvm::parseIRFile)
            var cpp_module: ?*anyopaque = null;
            var cpp_error: ?[*:0]u8 = null;
            const cpp_result = cpp.omni_parse_ir_file(path_c, self.context.raw, &cpp_module, &cpp_error);
            defer if (cpp_error) |err| cpp.omni_free_string(@ptrCast(err));

            if (cpp_result == 0 and cpp_module != null) {
                module_raw = @ptrCast(cpp_module);
                self.module = .{ .raw = module_raw };
                return self.module.?;
            }

            // C++ bridge failed, fall back to llvm-as conversion.
            // This handles environments where the C++ bridge wasn't compiled
            // or the LLVM shared library doesn't support it.
            log.debug("C++ bridge parseIRFile failed ({s}), falling back to llvm-as", .{
                if (cpp_error) |e| std.mem.sliceTo(e, 0) else "unknown error",
            });
            const bc_path = try self.allocator.dupeZ(u8, path);
            defer self.allocator.free(bc_path);
            // Replace .ll suffix with .bc
            if (bc_path.len > 3 and std.mem.eql(u8, bc_path[bc_path.len - 3 ..], ".ll")) {
                @memcpy(bc_path[bc_path.len - 3 ..], ".bc");
            }
            // Strip LLVM 22+ attributes (target_memN, nocreateundeforpoison) unsupported by llvm-as 21
            const pp_path = try std.fmt.allocPrint(self.allocator, "{s}.pp", .{bc_path});
            defer self.allocator.free(pp_path);

            var pp_ok = false;
            pp_blk: {
                const file_content = std.fs.cwd().readFileAlloc(self.allocator, path, 100 * 1024 * 1024) catch break :pp_blk;
                defer self.allocator.free(file_content);

                var cleaned = std.ArrayList(u8){};
                defer cleaned.deinit(self.allocator);

                var i: usize = 0;
                while (i < file_content.len) {
                    if (std.mem.startsWith(u8, file_content[i..], "target_mem")) {
                        // Skip "target_memN: value" (no preceding comma added yet since it was
                        // appended as individual chars before we detected the pattern).
                        // We remove the already-appended ", " by truncating cleaned.
                        if (cleaned.items.len >= 2 and
                            cleaned.items[cleaned.items.len - 2] == ',' and
                            cleaned.items[cleaned.items.len - 1] == ' ')
                        {
                            cleaned.shrinkRetainingCapacity(cleaned.items.len - 2);
                        }
                        var j = i + 10;
                        while (j < file_content.len and file_content[j] != ',' and file_content[j] != ')') : (j += 1) {}
                        i = j;
                    } else if (std.mem.startsWith(u8, file_content[i..], "nocreateundeforpoison")) {
                        i += "nocreateundeforpoison".len;
                    } else {
                        cleaned.append(self.allocator, file_content[i]) catch break :pp_blk;
                        i += 1;
                    }
                }

                std.fs.cwd().writeFile(.{ .sub_path = pp_path, .data = cleaned.items }) catch break :pp_blk;
                pp_ok = true;
            }

            const as_path = if (pp_ok) pp_path else path;

            const result = std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "llvm-as", "-disable-verify", as_path, "-o", bc_path },
            }) catch return Error.ParseFailed;
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            if (result.term.Exited != 0) {
                log.warn("llvm-as conversion failed for {s}: {s}", .{ path, result.stderr });
                return Error.ParseFailed;
            }
            // Load converted .bc
            return self.loadFile(std.mem.sliceTo(bc_path, 0));
        } else {
            // .bc path: create memory buffer from file and parse bitcode
            var mem_buf: c.LLVMMemoryBufferRef = undefined;
            var err_msg: [*c]u8 = null;

            if (c.LLVMCreateMemoryBufferWithContentsOfFile(
                path_c,
                &mem_buf,
                &err_msg,
            ) != 0) {
                defer if (err_msg != null) c.LLVMDisposeMessage(err_msg);
                return Error.FileNotFound;
            }

            var parse_result: c.LLVMBool = 0;
            parse_result = c.LLVMParseBitcodeInContext2(
                self.context.raw,
                mem_buf,
                &module_raw,
            );

            if (parse_result != 0 or module_raw == null) {
                defer if (err_msg != null) c.LLVMDisposeMessage(err_msg);
                c.LLVMDisposeMemoryBuffer(mem_buf);
                return Error.ParseFailed;
            }

            c.LLVMDisposeMemoryBuffer(mem_buf);
            self.module = .{ .raw = module_raw };
            return self.module.?;
        }
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

// ============================================================================
// Helper Functions for LLVM Instruction Patterns
// ============================================================================

/// Get the number of arguments for a CallInst (excluding the callee).
/// In LLVM C API, CallInst operands are: [arg0, arg1, ..., argN, callee]
/// So num_args = num_operands - 1 (or 0 if no operands).
///
/// This standardizes the pattern used across multiple analysis passes
/// to avoid inconsistency and bugs from incorrect operand indexing.
pub fn getCallInstArgCount(inst: c.LLVMValueRef) u32 {
    const num_ops: c_uint = @intCast(c.LLVMGetNumOperands(inst));
    return if (num_ops > 0) num_ops - 1 else 0;
}

/// Check if an instruction opcode represents a call or invoke instruction.
/// This is the standardized way to check for both call and invoke opcodes
/// across all analysis passes to avoid missing FFI calls in exception paths.
///
/// LLVM IR has two call instructions:
///   - LLVMCall: Normal function call
///   - LLVMInvoke: Call that may throw an exception (C++/Rust/Swift)
///
/// Both must be checked for complete FFI vulnerability detection.
pub fn isCallOrInvoke(opcode: c_uint) bool {
    return (opcode == c.LLVMCall) or (opcode == c.LLVMInvoke);
}

/// Check if an instruction is a CallInst and return its argument count.
/// Returns null if not a CallInst.
pub fn getCallInstArgCountSafe(inst: c.LLVMValueRef) ?u32 {
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (!isCallOrInvoke(opcode)) return null;
    return getCallInstArgCount(inst);
}

/// Issue2/3 IMPROVEMENT: Standardized helper to iterate call arguments safely.
/// This eliminates duplicated patterns across analysis passes and ensures
/// consistent operand indexing (args are operands 0..num_args-1, callee is last).
/// Usage:
///   const safe = @import("llvm_safe.zig");
///   try safe.iterateCallArgs(inst, allocator, |arg, idx| {
///       // Process each argument (arg is LLVMValueRef, idx is u32)
///   });
pub fn iterateCallArgs(
    inst: c.LLVMValueRef,
    comptime callback: fn (c.LLVMValueRef, u32) anyerror!void,
) !void {
    const num_args = getCallInstArgCount(inst);
    var i: u32 = 0;
    while (i < num_args) : (i += 1) {
        const arg = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(arg) == 0) continue;
        try callback(arg, i);
    }
}
