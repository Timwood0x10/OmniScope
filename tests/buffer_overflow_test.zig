//! Buffer Overflow Detection Tests
//!
//! Tests for the buffer overflow detection pass.

const std = @import("std");
const c = @import("../src/ir/llvm_raw.zig").c;

const BufferOverflowPass = @import("../src/pass/analysis/buffer_overflow.zig").BufferOverflowPass;
const PassContext = @import("../src/pass/pass.zig").PassContext;

test "BufferOverflowPass: metadata" {
    try std.testing.expectEqualSlices(u8, "buffer-overflow", BufferOverflowPass.name);
    try std.testing.expectEqual(@as(@typeInfo(@TypeOf(BufferOverflowPass.kind)).@"enum".tag_type, .analysis), BufferOverflowPass.kind);
    try std.testing.expectEqual(@as(usize, 0), BufferOverflowPass.deps.len);
}

test "BufferOverflowPass: null module handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = PassContext.init(allocator, null, null, null);
    defer ctx.deinit();

    const DiagnosticWriter = @import("../src/pass/pass.zig").DiagnosticWriter;
    var diag = DiagnosticWriter.init(null);

    try BufferOverflowPass.run(&ctx, &diag);
}

test "BufferOverflowPass: safe UTF-8 function name" {
    const getSafeFuncName = BufferOverflowPass.getSafeFuncName;

    const null_ref: c.LLVMValueRef = null;
    try std.testing.expectEqualSlices(u8, "unknown", getSafeFuncName(null_ref));
}
