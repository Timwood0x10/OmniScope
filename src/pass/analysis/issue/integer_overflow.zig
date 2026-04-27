//! Integer Overflow Detection Pass
//!
//! Detects potential integer overflow vulnerabilities in arithmetic operations

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;

/// Integer overflow detection pass
pub const IntegerOverflowPass = struct {
    pub const name = "integer-overflow";
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

        diag.info("IntegerOverflow: Analyzed functions, found {} potential overflows", .{issue_count});
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (try checkInstructionForOverflow(ctx, inst, func, diag)) {
                    issue_count += 1;
                }
            }
        }
        return issue_count;
    }

    fn checkInstructionForOverflow(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            c.LLVMAdd, c.LLVMSub, c.LLVMMul => {
                if (try isPotentiallyUnsafeOperation(inst)) {
                    const caller_name_ptr = c.LLVMGetValueName(caller_func);
                    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                        std.mem.span(caller_name_ptr)
                    else
                        "unknown";

                    const location = Location.init(caller_name);
                    const confidence = 0.6; // Base confidence for integer overflow

                    const message = try std.fmt.allocPrint(
                        ctx.allocator,
                        "Potential integer overflow in arithmetic operation (confidence: {d:.2}%)",
                        .{confidence * 100.0},
                    );

                    const issue = Issue.init(
                        .integer_overflow,
                        message,
                        location,
                        .medium,
                        confidence,
                    );

                    try ctx.addIssue(issue);

                    diag.warn("Integer overflow detected in function: {s}", .{caller_name});
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn isPotentiallyUnsafeOperation(inst: c.LLVMValueRef) !bool {
        const num_operands = c.LLVMGetNumOperands(inst);
        if (num_operands < 2) return false;

        const opcode = c.LLVMGetInstructionOpcode(inst);

        const lhs = c.LLVMGetOperand(inst, 0);
        const rhs = c.LLVMGetOperand(inst, 1);

        const lhs_is_const = c.LLVMIsConstant(lhs) != 0;
        const rhs_is_const = c.LLVMIsConstant(rhs) != 0;

        if (lhs_is_const and rhs_is_const) {
            return false;
        }

        if (opcode == c.LLVMAdd or opcode == c.LLVMMul) {
            if (rhs_is_const) {
                const rhs_value = c.LLVMConstIntGetZExtValue(rhs);
                if (rhs_value < 1000) {
                    return false;
                }
            }
            if (lhs_is_const) {
                const lhs_value = c.LLVMConstIntGetZExtValue(lhs);
                if (lhs_value < 1000) {
                    return false;
                }
            }
        }

        // For subtraction, check if it could underflow
        if (opcode == c.LLVMSub) {
            // Only flag if we can't determine safety (both operands non-constant)
            if (!lhs_is_const and !rhs_is_const) {
                // Check type width - small types are more risky
                const lhs_type = c.LLVMTypeOf(lhs);
                const type_kind = c.LLVMGetTypeKind(lhs_type);
                if (type_kind == c.LLVMIntegerTypeKind) {
                    const bit_width = c.LLVMGetIntTypeWidth(lhs_type);
                    if (bit_width <= 8) {
                        return true;
                    }
                }
            }
            return false;
        }

        const lhs_type = c.LLVMTypeOf(lhs);
        const type_kind = c.LLVMGetTypeKind(lhs_type);

        if (type_kind == c.LLVMIntegerTypeKind) {
            const bit_width = c.LLVMGetIntTypeWidth(lhs_type);
            if (bit_width <= 8) {
                return true;
            }
        }

        return false;
    }
};

test "IntegerOverflowPass - init" {
    // Basic test to ensure the pass compiles
    try std.testing.expectEqualStrings("integer-overflow", IntegerOverflowPass.name);
    try std.testing.expectEqual(PassKind.analysis, IntegerOverflowPass.kind);
}
