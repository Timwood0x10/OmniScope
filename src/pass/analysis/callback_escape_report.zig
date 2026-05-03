//! Reporting functions for CallbackEscapePass.
//!
//! Contains all violation reporting functions that generate Issue objects
//! and diagnostic messages for detected callback escaping patterns.
//!
//! Extracted from callback_escape.zig to comply with the 1000-line limit.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

/// Information about a CGo call that may retain a Go pointer.
pub const CGoCallInfo = struct {
    inst: c.LLVMValueRef,
    callee_name: []const u8,
    is_pointer_arg: bool,
};

/// Information about a callback escape event.
pub const CallbackEscapeInfo = struct {
    inst: c.LLVMValueRef,
    receiver_name: []const u8,
    callback_arg: c.LLVMValueRef,
};

pub fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

pub fn reportMissingKeepAlive(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Go pointer passed to C function without runtime.KeepAlive");
    trace[1] = try makeTrace(ctx.allocator, "Call to {s}() at cgo boundary", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "GC may reclaim Go memory while C still holds pointer (CWE-662)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "CGo call {s}() passes Go pointer without runtime.KeepAlive - GC race condition",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        0.78,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[NO-KEEPALIVE] {s} -> {s}() in {s}", .{ "Go ptr", call.callee_name, func_name });
}

pub fn reportCBytesEscape(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("C.CBytes result passed to C function that may retain pointer");
    trace[1] = try makeTrace(ctx.allocator, "{s}() returns C-managed copy of Go bytes", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "Caller must ensure Go backing store outlives C usage (CWE-401)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "C.{s}() result escapes to retaining C function - verify Go slice lifetime",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.65,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CBYTES-ESCAPE] {s} in {s}", .{ call.callee_name, func_name });
}

pub fn reportGenericCallbackEscape(
    ctx: *PassContext,
    func_name: []const u8,
    escape: CallbackEscapeInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const escape_type = if (std.mem.eql(u8, escape.receiver_name, "global_store"))
        "stored to global variable (cross-function lifetime escape)"
    else
        "passed to callback receiver function";

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Function pointer escapes current scope");
    trace[1] = try makeTrace(ctx.allocator, "Callback {s} - {s}", .{ escape.receiver_name, escape_type });
    trace[2] = try makeTrace(ctx.allocator, "Escaped callback may be invoked after caller returns (CWE-416/CWE-562)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function pointer escapes via {s} in {s} - potential use-after-return if callback captures stack data",
        .{ escape.receiver_name, func_name },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .medium,
        0.68,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-ESCAPE] {s} -> {s} in {s}", .{ "fn_ptr", escape.receiver_name, func_name });
}

/// Report a callback signature mismatch between receiver expectation and actual callback type.
/// Low confidence (0.45) to avoid false positives from incomplete type information in LLVM IR.
pub fn reportSignatureMismatch(
    ctx: *PassContext,
    func_name: []const u8,
    escape: CallbackEscapeInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Callback passed to receiver with incompatible signature");
    trace[1] = try makeTrace(ctx.allocator, "Type mismatch may cause undefined behavior at runtime (CWE-688)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Callback signature may not match {s} expectation in {s} - potential UB from ABI mismatch",
        .{ escape.receiver_name, func_name },
    );

    const issue = Issue.initWithTrace(
        .callback_signature_mismatch,
        message,
        location,
        .low,
        0.45,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-SIG] {s} -> {s} in {s}", .{ "sig_mismatch", escape.receiver_name, func_name });
}

pub fn reportUnsafePtrRisk(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("unsafe.Pointer conversion at FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "Conversion via {s}() breaks Go type system guarantees", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "Pointer may become invalid if GC moves the underlying object (CWE-704)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "unsafe.Pointer conversion ({s}) at cgo boundary - dangling pointer risk if object relocates",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        0.72,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[UNSAFE-PTR] {s} in {s}", .{ call.callee_name, func_name });
}

pub fn reportMallocLeak(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{d} malloc/calloc calls found", .{malloc_count});
    trace[1] = try makeTrace(ctx.allocator, "{d} free() calls found - {d} allocations never freed", .{ free_count, malloc_count - free_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Memory leak: {d} malloc/calloc without matching free in {s} (CWE-401)",
        .{ malloc_count - free_count, func_name },
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.70,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[MALLOC-LEAK] {d} allocs vs {d} frees in {s}", .{ malloc_count, free_count, func_name });
}

pub fn reportFreeOrphan(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{d} free() calls found", .{free_count});
    trace[1] = try makeTrace(ctx.allocator, "{d} malloc/calloc calls - {d} frees may operate on unallocated memory", .{ malloc_count, free_count - malloc_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Potential double-free or invalid free: {d} free() vs {d} malloc in {s} (CWE-415)",
        .{ free_count - malloc_count, malloc_count, func_name },
    );

    const issue = Issue.initWithTrace(
        .double_free,
        message,
        location,
        .high,
        0.68,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[FREE-ORPHAN] {d} frees vs {d} allocs in {s}", .{ free_count, malloc_count, func_name });
}
