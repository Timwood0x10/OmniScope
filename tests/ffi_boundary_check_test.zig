//! FFI Boundary Check Tests
//!
//! Tests for the FFI boundary check module.

const std = @import("std");

const ffi_boundary_check = @import("../src/pass/analysis/ffi_boundary_check.zig");
const PassContext = @import("../src/pass/pass.zig").PassContext;

test "FFIBoundaryCheck: constants" {
    try std.testing.expectEqual(@as(u32, 15), ffi_boundary_check.OWNERSHIP_CHAIN_SCAN_LIMIT);
}

test "FFIBoundaryCheck: reportFFIIssue with null context" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = PassContext.init(allocator, null, null, null);
    defer ctx.deinit();

    const IssueKind = @import("../src/diag/issue.zig").IssueKind;
    const Severity = @import("../src/registry/semantic_registry.zig").Severity;

    try ffi_boundary_check.reportFFIIssue(
        &ctx,
        IssueKind.ffi_null_deref,
        "Test FFI issue",
        "test_func",
        Severity.high,
        0.9,
    );

    try std.testing.expectEqual(@as(usize, 1), ctx.issues.items.len);
}

test "FFIBoundaryCheck: ownership chain null instruction" {
    const c = @import("../src/ir/llvm_raw.zig").c;
    const null_inst: c.LLVMValueRef = null;
    const null_func: c.LLVMValueRef = null;

    const result = ffi_boundary_check.checkOwnershipChain(null_inst, null_func);
    try std.testing.expectEqual(false, result);
}
