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

const CandidateBuilder = @import("resource/issue_candidate_builder.zig").CandidateBuilder;
const IssueCandidate = @import("resource/issue_candidate_builder.zig").IssueCandidate;
const IssueKind = @import("resource/issue_candidate_builder.zig").IssueKind;

/// Confidence levels for callback escape issue reporting.
/// Named constants replace magic numbers for maintainability.
pub const Confidence = struct {
    /// High: confirmed dangerous pattern with strong evidence (CGo KeepAlive, FFI-augmented escape)
    pub const high_keepalive: f32 = 0.78;
    pub const high_callback_ffi: f32 = 0.80;

    /// Medium-high: likely issue with moderate evidence (base callback escape, unsafe ptr, alloc/free imbalance)
    pub const med_callback_base: f32 = 0.68;
    pub const med_unsafe_ptr: f32 = 0.72;
    pub const med_malloc_leak: f32 = 0.70;

    /// Medium: possible issue, needs validation (CBytes retention)
    pub const med_cbytes_escape: f32 = 0.65;

    /// Low: weak signal, high FP risk from incomplete LLVM IR type info
    pub const low_sig_mismatch: f32 = 0.45;
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

pub fn reportCBytesEscape(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Go []byte (CBytes) escaped to C callback");
    trace[1] = try makeTrace(ctx.allocator, "Call to {s}() at cgo boundary", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "CBytes lifetime may exceed Go GC scope (CWE-662)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Go CBytes escaped to C callback in {s} — potential use-after-free if Go reclaims memory",
        .{func_name},
    );

    var cbe_cand = IssueCandidate.init(ctx.allocator, .callback_escape, 0.65);
    cbe_cand.func_name = func_name;
    cbe_cand.is_on_ffi_path = true;
    cbe_cand.addEvidence("Go []byte escaped to C callback") catch {};

    var issue = Issue.initWithTrace(
        .callback_ownership_risk,
        message,
        location,
        .medium,
        cbe_cand.raw_score,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);
    try ctx.addIssue(&issue);
    diag.warn("[CBYTES-ESCAPE] {s} in {s}", .{ call.callee_name, func_name });
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

    var ka_cand = IssueCandidate.init(ctx.allocator, .leak, 0.70);
    ka_cand.func_name = func_name;
    ka_cand.addEvidence("Missing runtime.KeepAlive for Go pointer passed to C") catch {};

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        ka_cand.raw_score,
        trace,
    );
    errdefer issue.deinit(ctx.allocator); // FIXED: Prevent leak if addIssue fails
    try ctx.addIssue(&issue);
    diag.warn("[NO-KEEPALIVE] {s} -> {s}() in {s}", .{ "Go ptr", call.callee_name, func_name });
}

/// Generate a CBytes escape candidate.
/// Returns an IssueCandidate instead of directly reporting.
pub fn generateCBytesEscapeCandidate(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !IssueCandidate {
    var candidate = IssueCandidate.init(ctx.allocator, .leak, Confidence.med_cbytes_escape);
    candidate.func_name = func_name;
    candidate.inst_addr = 0;
    candidate.callee_name = call.callee_name;

    try candidate.addEvidence("C.CBytes result passed to C function that may retain pointer");
    try candidate.addEvidence(try std.fmt.allocPrint(
        ctx.allocator,
        "{s}() returns C-managed copy of Go bytes",
        .{call.callee_name},
    ));
    try candidate.addEvidence("Caller must ensure Go backing store outlives C usage (CWE-401)");

    candidate.reason = try std.fmt.allocPrint(
        ctx.allocator,
        "C.{s}() result escapes to retaining C function - verify Go slice lifetime",
        .{call.callee_name},
    );

    diag.warn("[CBYTES-ESCAPE] {s} in {s}", .{ call.callee_name, func_name });
    return candidate;
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

    var co_cand = IssueCandidate.init(ctx.allocator, .callback_escape, 0.75);
    co_cand.func_name = func_name;
    co_cand.is_on_ffi_path = true;
    co_cand.addEvidence("Go pointer stored in C callback context without KeepAlive") catch {};

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        severity,
        co_cand.raw_score,
        trace,
    );
    errdefer issue.deinit(ctx.allocator); // FIXED: Prevent leak if addIssue fails
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

    var uaf_cand = IssueCandidate.init(ctx.allocator, .use_after_release, 0.80);
    uaf_cand.func_name = func_name;
    uaf_cand.is_on_ffi_path = true;
    uaf_cand.addEvidence("Potential use-after-free in CGo callback") catch {};

    var issue = Issue.initWithTrace(
        .callback_signature_mismatch,
        message,
        location,
        .low,
        uaf_cand.raw_score,
        trace,
    );
    errdefer issue.deinit(ctx.allocator); // FIXED: Prevent leak if addIssue fails
    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-SIG] {s} -> {s} in {s}", .{ "sig_mismatch", escape.receiver_name, func_name });
}

/// Generate an unsafe pointer risk candidate.
/// Returns an IssueCandidate instead of directly reporting.
pub fn generateUnsafePtrRiskCandidate(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !IssueCandidate {
    var candidate = IssueCandidate.init(ctx.allocator, .borrow_escape, Confidence.med_unsafe_ptr);
    candidate.func_name = func_name;
    candidate.inst_addr = 0;
    candidate.callee_name = call.callee_name;

    try candidate.addEvidence("unsafe.Pointer conversion at FFI boundary");
    try candidate.addEvidence(try std.fmt.allocPrint(
        ctx.allocator,
        "Conversion via {s}() breaks Go type system guarantees",
        .{call.callee_name},
    ));
    try candidate.addEvidence("Pointer may become invalid if GC moves the underlying object (CWE-704)");

    candidate.reason = try std.fmt.allocPrint(
        ctx.allocator,
        "unsafe.Pointer conversion ({s}) at cgo boundary - dangling pointer risk if object relocates",
        .{call.callee_name},
    );

    diag.warn("[UNSAFE-PTR] {s} in {s}", .{ call.callee_name, func_name });
    return candidate;
}

/// Generate a memory leak candidate for malloc/free imbalance.
/// Returns an IssueCandidate instead of directly reporting.
/// The caller (callback_escape.zig) should pass this to IssueVerifier.
pub fn generateMallocLeakCandidate(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !IssueCandidate {
    var candidate = IssueCandidate.init(ctx.allocator, .leak, Confidence.med_malloc_leak);
    candidate.func_name = func_name;
    candidate.inst_addr = 0; // Will be set by caller if available

    try candidate.addEvidenceFmt("{d} malloc/calloc calls found", .{malloc_count});
    try candidate.addEvidenceFmt("{d} free() calls found - {d} allocations never freed", .{ free_count, malloc_count - free_count });

    candidate.reason = try std.fmt.allocPrint(
        ctx.allocator,
        "Memory leak: {d} malloc/calloc without matching free in {s} (CWE-401)",
        .{ malloc_count - free_count, func_name },
    );

    diag.warn("[MALLOC-LEAK] {d} allocs vs {d} frees in {s}", .{ malloc_count, free_count, func_name });
    return candidate;
}

pub fn reportMallocLeak(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const candidate = try generateMallocLeakCandidate(ctx, func_name, malloc_count, free_count, diag);
    const location = Location.init(func_name);
    var issue = Issue.init(.memory_leak, candidate.reason orelse "Memory leak detected", location, .low, 0.5);
    errdefer issue.deinit(ctx.allocator);
    try ctx.addIssue(&issue);
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

    var up_cand = IssueCandidate.init(ctx.allocator, .borrow_escape, 0.82);
    up_cand.func_name = func_name;
    up_cand.is_on_ffi_path = true;
    up_cand.addEvidence("Unsafe pointer usage detected") catch {};

    var issue = Issue.initWithTrace(
        .double_free,
        message,
        location,
        .high,
        up_cand.raw_score,
        trace,
    );
    errdefer issue.deinit(ctx.allocator); // FIXED: Prevent leak if addIssue fails
    try ctx.addIssue(&issue);
    diag.warn("[FREE-ORPHAN] {d} frees vs {d} allocs in {s}", .{ free_count, malloc_count, func_name });
}
