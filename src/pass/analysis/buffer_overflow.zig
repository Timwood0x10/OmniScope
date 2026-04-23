//! Buffer Overflow Detection Pass
//!
//! Detects stack buffer overflows and array out-of-bounds accesses
//! using LLVM IR analysis (GEP + alloca size checking)

const std = @import("std");

const c = @import("llvm");

const PassContext = @import("../../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;

/// Buffer overflow detection pass
pub const BufferOverflowPass = struct {
    pub const name = "buffer-overflow";
    pub const kind = .analysis;

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var overflow_count: u32 = 0;
        var oob_count: u32 = 0;

        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    if (opcode == c.LLVMLoad or opcode == c.LLVMStore) {
                        const ptr_operand = c.LLVMGetOperand(inst, if (opcode == c.LLVMLoad) 0 else 1);
                        if (@intFromPtr(ptr_operand) == 0) continue;

                        if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr) {
                            if (checkGEPBounds(func, ptr_operand, diag)) |vuln| {
                                overflow_count += 1;
                                try reportIssue(ctx, vuln, diag);
                            }
                        }
                    }

                    if (opcode == c.LLVMGetElementPtr) {
                        if (checkGEPForOOB(func, inst, diag)) |vuln| {
                            oob_count += 1;
                            try reportIssue(ctx, vuln, diag);
                        }
                    }
                }
            }
        }

        if (overflow_count > 0) {
            diag.info("BufferOverflow: Found {d} potential stack buffer overflows", .{overflow_count});
        }
        if (oob_count > 0) {
            diag.info("BufferOverflow: Found {d} potential array out-of-bounds accesses", .{oob_count});
        }

        if (overflow_count == 0 and oob_count == 0) {
            diag.info("BufferOverflow: No buffer overflow issues detected", .{});
        }
    }

    fn checkGEPBounds(func: c.LLVMValueRef, gep: c.LLVMValueRef, diag: *DiagnosticWriter) ?Issue {
        const base_ptr = c.LLVMGetOperand(gep, 0);
        if (@intFromPtr(base_ptr) == 0) return null;

        if (c.LLVMGetInstructionOpcode(base_ptr) != c.LLVMAlloca) return null;

        const alloc_type = c.LLVMGetAllocatedType(base_ptr);
        if (@intFromPtr(alloc_type) == 0) return null;

        const base_func = c.LLVMGetBasicBlockParent(c.LLVMGetInstructionParent(base_ptr));
        const module = c.LLVMGetGlobalParent(base_func);
        const dl = c.LLVMGetModuleDataLayout(module);
        const type_size = c.LLVMABISizeOfType(dl, alloc_type);
        if (type_size <= 0) return null;

        const num_indices = c.LLVMNumIndices(gep);
        if (num_indices < 2) return null;

        var last_index_is_const = false;
        var last_index_value: i64 = 0;

        var i: u32 = 1;
        while (i < num_indices) : (i += 1) {
            const index_val = c.LLVMGetOperand(gep, i);
            if (c.LLVMIsConstant(index_val) != 0 and c.LLVMIsAConstantInt(index_val) != null) {
                if (i == num_indices - 1) {
                    last_index_value = c.LLVMConstIntGetSExtValue(index_val);
                    last_index_is_const = true;
                }
            }
        }

        if (!last_index_is_const) return null;

        if (last_index_value >= @as(i64, @intCast(type_size))) {
            const func_name = c.LLVMGetValueName(func) orelse "unknown";
            const loc = c.LLVMDebugLocToMDNode(c.LLVMGetCurrentDebugLocation(gep));

            diag.warn("STACK-OVERFLOW [HIGH]: GEP index {d} exceeds allocation size {d} in {s}", .{
                last_index_value, type_size,
                if (func_name) |n| std.mem.span(n) else "unknown",
            });

            return Issue.init(.buffer_overflow,
                std.fmt.allocPrint(std.heap.page_allocator,
                    "Stack buffer overflow: access at offset {d} exceeds allocation of {d} bytes",
                    .{ last_index_value, type_size }
                ) orelse "Stack buffer overflow detected",
                Location.init(if (func_name) |n| std.mem.span(n) else "unknown"),
                .high,
                0.85
            );
        }

        return null;
    }

    fn checkGEPForOOB(func: c.LLVMValueRef, gep: c.LLVMValueRef, diag: *DiagnosticWriter) ?Issue {
        _ = diag;

        const base_ptr = c.LLVMGetOperand(gep, 0);
        if (@intFromPtr(base_ptr) == 0) return null;

        const base_opcode = c.LLVMGetValueKind(base_ptr);
        if (base_opcode != c.LLVMValueKindInstruction and
            base_opcode != c.LLVMValueKindGlobalVariable)
        {
            return null;
        }

        var base_type = c.LLVMTypeOf(base_ptr);
        if (@intFromPtr(base_type) == 0) return null;

        const elem_type = c.LLVMGetElementType(base_type);
        if (@intFromPtr(elem_type) == 0) return null;

        const is_array = c.LLVMGetTypeKind(elem_type) == c.LLVMArrayTypeKind;
        if (!is_array) return null;

        const array_size = c.LLVMGetArrayLength(elem_type);
        if (array_size <= 0) return null;

        const num_indices = c.LLVMNumIndices(gep);
        if (num_indices < 2) return null;

        var last_index_value: i64 = 0;
        var has_const_index = false;

        var i: u32 = 1;
        while (i < num_indices) : (i += 1) {
            const index_val = c.LLVMGetOperand(gep, i);
            if (c.LLVMIsConstant(index_val) != 0 and c.LLVMIsAConstantInt(index_val) != null) {
                if (i == num_indices - 1) {
                    last_index_value = c.LLVMConstIntGetSExtValue(index_val);
                    has_const_index = true;
                }
            }
        }

        if (!has_const_index) return null;

        if (last_index_value >= @as(i64, @intCast(array_size))) {
            const func_name = c.LLVMGetValueName(func);

            diag.warn("ARRAY-OOB [HIGH]: Array index {d} exceeds array size {d}", .{
                last_index_value, array_size,
            });

            return Issue.init(.buffer_overflow,
                std.fmt.allocPrint(std.heap.page_allocator,
                    "Array out-of-bounds: index {d} exceeds array length {d}",
                    .{ last_index_value, array_size }
                ) orelse "Array out-of-bounds detected",
                Location.init(if (func_name) |n| std.mem.span(n) else "unknown"),
                .high,
                0.8
            );
        }

        return null;
    }

    fn reportIssue(ctx: *PassContext, issue: Issue, diag: *DiagnosticWriter) !void {
        try ctx.addIssue(issue);
        diag.err("[BUFFER-OVERFLOW] {s}: {s}", .{
            @tagName(issue.kind), issue.message
        });
    }
};
