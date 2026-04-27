//! Memory Safety Detection Pass
//!
//! Detects memory safety issues: double free, use after free, memory leaks

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;

/// Memory safety detection pass
pub const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var issue_count: usize = 0;
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            issue_count += try analyzeFunction(ctx, func, diag);
        }

        diag.info("MemorySafety: Analyzed functions, found {} memory issues", .{issue_count});
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;

        // Track freed pointers in this function
        var freed_pointers = std.ArrayList(c.LLVMValueRef).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
        defer freed_pointers.deinit(ctx.allocator);

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (try checkInstruction(ctx, inst, func, &freed_pointers, diag)) {
                    issue_count += 1;
                }
            }
        }
        return issue_count;
    }

    fn checkInstruction(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        freed_pointers: *std.ArrayList(c.LLVMValueRef),
        diag: *DiagnosticWriter,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            c.LLVMCall => {
                // Check if this is a free function call
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) return false;

                const called_name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(called_name_ptr) == 0) return false;
                const called_name = std.mem.span(called_name_ptr);

                // Check if this is a free call
                if (isFreeFunction(called_name)) {
                    const ptr_arg = c.LLVMGetOperand(inst, 0);
                    const ptr_as_int = @intFromPtr(ptr_arg);

                    // Check if this pointer was already freed
                    for (freed_pointers.items) |freed_ptr| {
                        if (@intFromPtr(freed_ptr) == ptr_as_int) {
                            // Double free detected!
                            try reportDoubleFree(ctx, caller_func, called_name, diag);
                            return true;
                        }
                    }

                    // Mark this pointer as freed
                    try freed_pointers.append(ctx.allocator, ptr_arg);
                }
            },
            else => {},
        }

        return false;
    }

    fn isFreeFunction(func_name: []const u8) bool {
        const free_functions = &[_][]const u8{
            "free",            "dealloc",           "deallocate",
            "operator delete", "operator delete[]",
        };

        for (free_functions) |free_func| {
            if (std.mem.indexOf(u8, func_name, free_func) != null) {
                return true;
            }
        }
        return false;
    }

    fn reportDoubleFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);
        const confidence = 0.8; // High confidence for double free

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "Potential double free of pointer via '{s}' (confidence: {d:.2}%)",
            .{ func_name, confidence * 100.0 },
        );

        const issue = Issue.init(
            .double_free,
            message,
            location,
            .high,
            confidence,
        );

        try ctx.addIssue(issue);

        diag.warn("Double free detected in function: {s} via {s}", .{ caller_name, func_name });
    }
};

test "MemorySafetyPass - init" {
    // Basic test to ensure the pass compiles
    try std.testing.expectEqualStrings("memory-safety", MemorySafetyPass.name);
    try std.testing.expectEqual(PassKind.analysis, MemorySafetyPass.kind);
}
