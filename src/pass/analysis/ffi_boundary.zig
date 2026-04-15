//! FFI Boundary Detection Pass
//!
//! Marks cross-language transitions in the call graph.
//! Only external_unknown is considered a true FFI boundary (not libc).

const std = @import("std");
const llvm = @import("../../ir/llvm_c.zig");
const call_graph = @import("./call_graph.zig");
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const FFIBoundaryInfo = @import("./ffi_info.zig").FFIBoundaryInfo;
const FFIKind = @import("./ffi_info.zig").FFIKind;
const FFIBoundaryDetector = @import("./ffi_info.zig").FFIBoundaryDetector;

/// Error type for FFI boundary detection operations.
pub const FFIBoundaryError = error{
    /// Memory allocation failed.
    OutOfMemory,
};

/// Represents an FFI boundary edge in the call graph.
/// An FFI edge indicates a cross-language call transition.
pub const FFIEdge = struct {
    /// ID of the caller function (in the current language/module).
    caller: u32,
    /// ID of the callee function (in a different language/module).
    callee: u32,
};

/// FFI boundary detection pass.
///
/// Identifies cross-language transitions in the call graph.
/// An FFI boundary is detected when:
/// - Callee is external_unknown (not libc)
/// - Indicates a call from analyzed code to unknown external code
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    /// Run FFI boundary detection
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void {
        if (ctx.module == null) return;

        var detector = FFIBoundaryDetector.init(ctx.allocator);
        defer detector.deinit();

        try detectFFIBoundaries(ctx, &detector, diag);
        try storeFFIFacts(ctx, &detector, diag);
    }

    /// Detect FFI boundaries in the call graph
    fn detectFFIBoundaries(ctx: *PassContext, detector: *FFIBoundaryDetector, diag: *DiagnosticWriter) !void {
        const mod = ctx.module.?.raw;
        var func = llvm.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;
        var ffi_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            const func_name_ptr = llvm.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);
            if (func_name.len > 1024) continue;

            if (detector.isFFICall(func_name)) {
                const ffi_kind = detector.classifyFFIKind(func_name);
                ffi_count += 1;

                const info = FFIBoundaryInfo{
                    .edge_id = ctx.getNextId(),
                    .caller = @intFromPtr(func),
                    .callee = @intFromPtr(func),
                    .kind = ffi_kind,
                    .target_language = @tagName(ffi_kind),
                    .is_exported = false,
                    .is_imported = true,
                };
                try detector.addBoundary(info);

                diag.info("FFI boundary detected: {s} ({s})", .{ func_name, @tagName(ffi_kind) });
            }

            try detectCallsInFunction(ctx, detector, func, diag);
        }

        if (ffi_count > 0) {
            diag.info("FFIBoundary: Found {} FFI boundaries", .{ffi_count});
        }
    }

    /// Detect FFI calls within a function
    fn detectCallsInFunction(ctx: *PassContext, detector: *FFIBoundaryDetector, func: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        var bb = llvm.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = llvm.LLVMGetNextBasicBlock(bb)) {
            var inst = llvm.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = llvm.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(llvm.LLVMIsACallInst(inst)) != 0) {
                    try checkCallForFFI(ctx, detector, inst, func, diag);
                }
            }
        }
    }

    /// Check a call instruction for FFI boundary
    fn checkCallForFFI(ctx: *PassContext, detector: *FFIBoundaryDetector, inst: llvm.LLVMValueRef, caller_func: llvm.LLVMValueRef, diag: *DiagnosticWriter) !void {
        const called_val = llvm.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return;

        const called_name_ptr = llvm.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) == 0) return;
        const called_name = std.mem.span(called_name_ptr);

        if (detector.isFFICall(called_name)) {
            const ffi_kind = detector.classifyFFIKind(called_name);

            const caller_name_ptr = llvm.LLVMGetValueName(caller_func);
            const caller_name = if (@intFromPtr(caller_name_ptr) != 0) std.mem.span(caller_name_ptr) else "unknown";

            const info = FFIBoundaryInfo{
                .edge_id = ctx.getNextId(),
                .caller = @intFromPtr(caller_func),
                .callee = @intFromPtr(called_val),
                .kind = ffi_kind,
                .target_language = @tagName(ffi_kind),
                .is_exported = false,
                .is_imported = true,
            };
            try detector.addBoundary(info);

            diag.info("FFI call: {s} -> {s} ({s})", .{ caller_name, called_name, @tagName(ffi_kind) });
        }
    }

    /// Store FFI facts in fact store
    fn storeFFIFacts(ctx: *PassContext, detector: *FFIBoundaryDetector, diag: *DiagnosticWriter) !void {
        var count: u32 = 0;

        for (detector.boundaries.items) |boundary| {
            try ctx.fact_store.insert(
                .ffi_boundary,
                boundary.caller,
                boundary.callee,
                @intFromEnum(boundary.kind),
            );
            count += 1;
        }

        if (count > 0) {
            diag.info("FFIBoundary: Stored {} FFI facts", .{count});
        }
    }
};

test "FFIEdge - structure" {
    const edge = FFIEdge{ .caller = 0, .callee = 1 };
    try std.testing.expectEqual(@as(u32, 0), edge.caller);
    try std.testing.expectEqual(@as(u32, 1), edge.callee);
}

test "FFIEdge - edge case values" {
    const edge1 = FFIEdge{ .caller = 0, .callee = 0 };
    try std.testing.expectEqual(edge1.caller, edge1.callee);

    const edge2 = FFIEdge{ .caller = 100, .callee = 200 };
    try std.testing.expect(edge2.caller < edge2.callee);
}

test "FFIEdge - max values" {
    const edge = FFIEdge{ .caller = std.math.maxInt(u32), .callee = std.math.maxInt(u32) };
    try std.testing.expectEqual(@as(u32, 0), edge.caller - 1);
    try std.testing.expectEqual(@as(u32, 0), edge.callee - 1);
}

test "FFIEdge - self-loop" {
    const edge = FFIEdge{ .caller = 5, .callee = 5 };
    try std.testing.expectEqual(edge.caller, edge.callee);
}

test "FFIEdge - caller before callee" {
    const edge = FFIEdge{ .caller = 1, .callee = 2 };
    try std.testing.expect(edge.caller < edge.callee);
}

test "FFIBoundaryError - error type exists" {
    const err = FFIBoundaryError.OutOfMemory;
    try std.testing.expect(err == FFIBoundaryError.OutOfMemory);
}

test "FFIBoundaryPass - name" {
    try std.testing.expectEqualStrings("ffi-boundary", FFIBoundaryPass.name);
}

test "FFIBoundaryPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, FFIBoundaryPass.kind);
}

test "FFIBoundaryPass - deps" {
    try std.testing.expectEqual(@as(usize, 1), FFIBoundaryPass.deps.len);
    try std.testing.expectEqualStrings("call-graph", FFIBoundaryPass.deps[0]);
}

test "FFIBoundaryPass - deps not empty" {
    try std.testing.expect(FFIBoundaryPass.deps.len > 0);
}

test "FFIBoundaryPass - deps valid strings" {
    for (FFIBoundaryPass.deps) |dep| {
        try std.testing.expect(dep.len > 0);
    }
}

test "FFIKind - all variants" {
    try std.testing.expectEqual(FFIKind.none, .none);
    try std.testing.expectEqual(FFIKind.c_call, .c_call);
    try std.testing.expectEqual(FFIKind.rust_ffi, .rust_ffi);
    try std.testing.expectEqual(FFIKind.go_cgo, .go_cgo);
    try std.testing.expectEqual(FFIKind.other, .other);
}

test "FFIBoundaryInfo - all fields" {
    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 100,
        .callee = 200,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };

    try std.testing.expectEqual(@as(u32, 1), info.edge_id);
    try std.testing.expectEqual(@as(u32, 100), info.caller);
    try std.testing.expectEqual(@as(u32, 200), info.callee);
    try std.testing.expectEqual(FFIKind.rust_ffi, info.kind);
    try std.testing.expectEqualStrings("Rust", info.target_language);
    try std.testing.expect(info.is_exported);
    try std.testing.expect(!info.is_imported);
}
