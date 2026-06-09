//! FFI Type Compatibility Checker
//!
//! Extracted from ffi_boundary.zig (P2-2 refactoring).
//! Provides type checking utilities for FFI boundary analysis:
//! - Pointer/integer confusion detection
//! - Integer size mismatch detection (ABI issues)
//! - LLVM type description for diagnostics
//!
//! Design principle: Stateless utility functions, no internal state.
//! All functions accept explicit parameters (no hidden dependencies).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../../diag/issue.zig").Severity;

/// Check type compatibility between call arguments and function parameters.
///
/// Detects two categories of issues:
/// 1. **Pointer/integer confusion**: Passing a pointer where an integer is expected (or vice versa).
///    This is a common source of bugs in FFI code, especially on 64-bit systems where
///    pointers are 8 bytes but integers may be 4 bytes.
///
/// 2. **Integer size mismatch**: When both parameter and argument are integers but have
///    different sizes that could cause truncation or sign-extension. Only reports when
///    the size difference is >= 2x (to avoid noise from minor ABI differences).
///
/// Parameters:
///   - ctx: Pass context for issue reporting
///   - diag: Diagnostic writer for warnings
///   - inst: The call instruction to analyze
///   - caller_func: The calling function (for location info)
pub fn checkTypeCompatibility(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    report_fn: *const fn (*PassContext, IssueKind, []const u8, []const u8, IssueSeverity, f32) anyerror!void,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    const callee_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(callee_val) == 0) return;
    // Only check external declarations (extern "C" functions)
    if (c.LLVMIsDeclaration(callee_val) == 0) return;

    // Get function type from declaration
    const func_type = c.LLVMGetElementType(c.LLVMTypeOf(callee_val));
    if (@intFromPtr(func_type) == 0) return;

    const num_params = c.LLVMCountParams(callee_val);
    const num_operands = c.LLVMGetNumOperands(inst);
    // operands = args + callee, so args = num_operands - 1
    const num_args = @max(0, num_operands - 1);

    var param_idx: u32 = 0;
    while (param_idx < @min(num_params, num_args)) : (param_idx += 1) {
        // Use LLVMGetParam + LLVMTypeOf instead of LLVMGetParamType (not in Zig bindings)
        const param_val = c.LLVMGetParam(callee_val, param_idx);
        if (@intFromPtr(param_val) == 0) continue;
        const param_type = c.LLVMTypeOf(param_val);

        const arg_operand = c.LLVMGetOperand(inst, @intCast(param_idx));
        if (@intFromPtr(arg_operand) == 0) continue;

        // Use LLVMTypeOf instead of LLVMGetType (not in Zig bindings)
        const arg_type = c.LLVMTypeOf(arg_operand);
        if (@intFromPtr(arg_type) == 0) continue;

        const param_kind = c.LLVMGetTypeKind(param_type);
        const arg_kind = c.LLVMGetTypeKind(arg_type);

        // Check: Pointer passed as integer parameter (or vice versa)
        if (param_kind != arg_kind) {
            if ((param_kind == c.LLVMPointerTypeKind and arg_kind == c.LLVMIntegerTypeKind) or
                (param_kind == c.LLVMIntegerTypeKind and arg_kind == c.LLVMPointerTypeKind))
            {
                diag.warn("  TYPE MISMATCH: Param {d} — pointer/integer confusion detected", .{param_idx});
                diag.warn("    Expected: {s}, Got: kind={d}", .{
                    describeLLVMType(param_type),
                    arg_kind,
                });
                const msg = try std.fmt.allocPrint(ctx.allocator, "TYPE MISMATCH: Param {d} pointer/integer confusion in {s}", .{
                    param_idx, caller_name,
                });
                defer ctx.allocator.free(msg);
                try report_fn(ctx, .type_mismatch, msg, caller_name, .high, 0.80);
            }
        }

        // Check: Size mismatch for integer types (ABI issues)
        if (param_kind == c.LLVMIntegerTypeKind and arg_kind == c.LLVMIntegerTypeKind) {
            const param_bits = c.LLVMGetIntTypeWidth(param_type);
            const arg_bits = c.LLVMGetIntTypeWidth(arg_type);
            if (param_bits > 0 and arg_bits > 0 and param_bits < 8192 and arg_bits < 8192 and param_bits != arg_bits) {
                if (param_bits >= arg_bits * 2 or arg_bits >= param_bits * 2) {
                    diag.warn("  SIZE MISMATCH: Param {d} — i{d} vs i{d} (potential truncation/sign-extension)", .{
                        param_idx, arg_bits, param_bits,
                    });
                    const msg = try std.fmt.allocPrint(ctx.allocator, "SIZE MISMATCH: Param {d} i{d} vs i{d} in {s}", .{
                        param_idx, arg_bits, param_bits, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    try report_fn(ctx, .type_mismatch, msg, caller_name, .medium, 0.70);
                }
            }
        }
    }
}

/// Describe an LLVM type as a human-readable string.
///
/// Used for diagnostic messages when reporting type mismatches.
/// Handles all common LLVM type kinds with friendly names.
///
/// Parameters:
///   - ty: LLVM type reference to describe
///
/// Returns:
///   - Static string slice describing the type
pub fn describeLLVMType(ty: c.LLVMTypeRef) []const u8 {
    const type_kind = c.LLVMGetTypeKind(ty);
    switch (type_kind) {
        c.LLVMVoidTypeKind => return "void",
        c.LLVMFloatTypeKind => return "float",
        c.LLVMDoubleTypeKind => return "double",
        c.LLVMX86_FP80TypeKind => return "fp80",
        c.LLVMFP128TypeKind => return "fp128",
        c.LLVMPPC_FP128TypeKind => return "ppc_fp128",
        c.LLVMLabelTypeKind => return "label",
        c.LLVMIntegerTypeKind => {
            const bits = c.LLVMGetIntTypeWidth(ty);
            if (bits == 1) return "i1";
            if (bits == 8) return "i8";
            if (bits == 16) return "i16";
            if (bits == 32) return "i32";
            if (bits == 64) return "i64";
            return "integer";
        },
        c.LLVMFunctionTypeKind => return "function",
        c.LLVMStructTypeKind => return "struct",
        c.LLVMArrayTypeKind => return "array",
        c.LLVMPointerTypeKind => return "pointer",
        else => return "unknown",
    }
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "describeLLVMType - basic types" {
    // This test verifies the function compiles and handles basic cases
    // Full testing requires actual LLVM IR context which is not available in unit tests
    try std.testing.expectEqualStrings("pointer", describeLLVMType(undefined));
}
