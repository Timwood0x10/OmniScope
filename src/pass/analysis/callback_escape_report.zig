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
const Severity = @import("../../diag/issue.zig").Severity;

/// Confidence levels for callback escape issue reporting.
/// Named constants replace magic numbers for maintainability.
const Confidence = struct {
    /// High: confirmed dangerous pattern with strong evidence (CGo KeepAlive, FFI-augmented escape)
    const high_keepalive: f32 = 0.78;
    const high_callback_ffi: f32 = 0.80;

    /// Medium-high: likely issue with moderate evidence (base callback escape, unsafe ptr, alloc/free imbalance)
    const med_callback_base: f32 = 0.68;
    const med_unsafe_ptr: f32 = 0.72;
    const med_malloc_leak: f32 = 0.70;

    /// Medium: possible issue, needs validation (CBytes retention)
    const med_cbytes_escape: f32 = 0.65;

    /// Low: weak signal, high FP risk from incomplete LLVM IR type info
    const low_sig_mismatch: f32 = 0.45;
};

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
        Confidence.high_keepalive,
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
        Confidence.med_cbytes_escape,
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
    indirect_escape: bool,
) !void {
    const location = Location.init(func_name);

    const escape_type = if (std.mem.eql(u8, escape.receiver_name, "global_store"))
        "stored to global variable (cross-function lifetime escape)"
    else
        "passed to callback receiver function";

    // E2-2c: Indirect escape via alias closure — if the escaped pointer's aliases
    // reach FFI boundaries through the memory graph, this is more severe because
    // the callback may be invoked from a cross-language context.
    const confidence: f32 = if (indirect_escape) Confidence.high_callback_ffi else Confidence.med_callback_base;
    const severity: Severity = if (indirect_escape) .high else .medium;

    const ffi_note = if (indirect_escape) " [alias-closure reaches FFI]" else "";

    const trace = try ctx.allocator.alloc(TraceEntry, if (indirect_escape) 4 else 3);
    trace[0] = TraceEntry.init("Function pointer escapes current scope");
    trace[1] = try makeTrace(ctx.allocator, "Callback {s} - {s}", .{ escape.receiver_name, escape_type });
    trace[2] = try makeTrace(ctx.allocator, "Escaped callback may be invoked after caller returns (CWE-416/CWE-562)", .{});
    if (indirect_escape) {
        trace[3] = try makeTrace(ctx.allocator, "Pointer aliases reach FFI boundary via memory graph alias closure", .{});
    }

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function pointer escapes via {s} in {s} - potential use-after-return if callback captures stack data (confidence: {d:.1}%{s})",
        .{ escape.receiver_name, func_name, confidence * 100.0, ffi_note },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        severity,
        confidence,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-ESCAPE] {s} -> {s} in {s}{s}", .{ "fn_ptr", escape.receiver_name, func_name, ffi_note });
}

/// Report a callback signature mismatch between receiver expectation and actual callback type.
/// Low confidence (Confidence.low_sig_mismatch) to avoid false positives from incomplete type information in LLVM IR.
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
        Confidence.low_sig_mismatch,
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
        Confidence.med_unsafe_ptr,
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
        Confidence.med_malloc_leak,
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
        Confidence.med_callback_base,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[FREE-ORPHAN] {d} frees vs {d} allocs in {s}", .{ free_count, malloc_count, func_name });
}
