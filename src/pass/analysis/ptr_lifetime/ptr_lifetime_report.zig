//! Reporting functions for PtrLifetimePass.
//!
//! Contains all violation reporting functions that generate Issue objects
//! and diagnostic messages for detected pointer lifetime violations.
//!
//! Extracted from ptr_lifetime.zig to comply with the 1000-line limit.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../../../pass/pass.zig").DiagnosticWriter;
const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;
const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;
const provenance = @import("../provenance.zig");
const memory_graph = @import("../../../semantics/memory_graph.zig");
const escape_mod = @import("../../../semantics/resource/escape.zig");
pub const EscapeRecord = escape_mod.EscapeRecord;

pub fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

pub fn reportStackEscape(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
    mem_graph: ?*provenance.memory_graph.MemoryGraph,
) !void {
    _ = inst;
    const is_extern_callee = is_extern_function(callee_name) or
        (std.mem.indexOf(u8, callee_name, "ffi_") != null);

    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!is_extern_callee and !ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[STACK-ESCAPE SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }

    const location = Location.init(func_name);

    // P0+: Use unified Provenance service for precise messages
    var prov = provenance.Provenance.init(ctx.allocator, mem_graph);
    const prov_desc = if (ptr_info.source_inst) |src_inst|
        prov.describeAllocaContent(src_inst)
    else
        "unknown content";

    // Generate suppression-friendly tag for generic pattern matching
    const tag = if (ptr_info.source_inst) |src_inst|
        prov.getSuppressionTag(src_inst)
    else
        "[unknown]";

    const trace = try ctx.allocator.alloc(TraceEntry, 4);
    trace[0] = TraceEntry.init("Stack pointer passed to FFI boundary function");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Provenance: {s} {s}", .{ tag, prov_desc });
    trace[3] = try makeTrace(ctx.allocator, "Passed to {s}() which may retain pointer beyond caller scope", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Stack pointer ({s}, provenance: {s} [{s}]) escapes to FFI function {s}() - pointer invalid after function returns (CWE-562)",
        .{ ptr_info.source_desc, prov_desc, tag, callee_name },
    );

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.88,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [STACK-ESCAPE] {s} ({s}) [{s}] -> {s}() in {s}", .{ ptr_info.source_desc, prov_desc, tag, callee_name, func_name });
}

pub fn reportReturnStackAddr(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - return stack addr only dangerous across FFI boundary
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[RETURN-STACK SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Function returns address of stack-local variable");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function returns stack-local address ({s}) - dangling pointer after return (CWE-562)",
        .{ptr_info.source_desc},
    );

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.92,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [RETURN-STACK] {s} returned from {s}", .{ ptr_info.source_desc, func_name });
}

pub fn reportReturnHeapPtr(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - heap return only matters if crosses FFI
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[RETURN-HEAP SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Function returns heap-allocated pointer");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s} (caller must free)", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Returning heap pointer creates ownership transfer ambiguity - who frees?");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function returns heap-allocated pointer ({s}) - caller may not know to free (CWE-401/CWE-662)",
        .{ptr_info.source_desc},
    );

    var issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.72,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [RETURN-HEAP] {s} returned from {s} - ownership unclear", .{ ptr_info.source_desc, func_name });
}

pub fn reportHeapToGlobal(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - heap to global only dangerous across FFI
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[HEAP-TO-GLOBAL SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Heap-allocated pointer stored to global variable");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s} (global lifetime)", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Global storage of heap pointer creates leak risk - when is it freed?");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) stored to global in {s} - potential memory leak if never freed (CWE-401)",
        .{ ptr_info.source_desc, func_name },
    );

    var issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.75,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [HEAP-TO-GLOBAL] {s} -> global in {s}", .{ ptr_info.source_desc, func_name });
}

pub fn reportStackToGlobal(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - stack to global only dangerous across FFI boundary
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[STACK-TO-GLOBAL SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Stack-local pointer stored to global variable");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Global storage outlives stack frame - dangling pointer after return");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Stack pointer ({s}) stored to global in {s} - dangling pointer after function returns (CWE-562)",
        .{ ptr_info.source_desc, func_name },
    );

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.90,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [STACK-TO-GLOBAL] {s} -> global in {s}", .{ ptr_info.source_desc, func_name });
}

pub fn reportUseAfterFree(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - UAF critical only on FFI path
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[UAF-RISK SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Freed pointer passed to function call");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s} (already freed)", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Use in {s}() after free", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Freed pointer ({s}) passed to {s}() - potential use-after-free (CWE-416)",
        .{ ptr_info.source_desc, callee_name },
    );

    var issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .high,
        0.82, // M5 FIX: UAF confidence raised from 0.75 to 0.82 (consistent with severity)
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [UAF-RISK] freed ptr -> {s}() in {s}", .{ callee_name, func_name });
}

pub fn reportResourceUAF(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // G-3: MemoryGraph gate - resource UAF only dangerous on FFI path
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[RESOURCE-UAF SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const resource_desc = switch (ptr_info.resource_type) {
        .dlopen_handle => "dlopen handle",
        .mmap_region => "memory mapping",
        .file_handle => "file handle",
        .socket_fd => "socket descriptor",
        .jni_ref => "JNI reference",
        .python_obj => "Python object",
        .none => "resource",
    };

    const violation_desc = switch (ptr_info.resource_type) {
        .dlopen_handle => "dlclose called while dlsym-derived pointers may still be in use",
        .mmap_region => "munmap called while pointers to mapped region may still be in use",
        .file_handle => "fclose called while FILE* may still be used",
        .socket_fd => "close called while socket fd may still be used",
        .jni_ref => "DeleteGlobalRef/DeleteLocalRef called while reference may still be in use",
        .python_obj => "Py_DECREF/Py_XDECREF called while object may still be referenced",
        .none => "resource released while still in use",
    };

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Resource used after release");
    trace[1] = try makeTrace(ctx.allocator, "Resource type: {s}, origin: {s}", .{ resource_desc, ptr_info.source_desc });
    trace[2] = try makeTrace(ctx.allocator, "{s} - passed to {s}()", .{ violation_desc, callee_name });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Released {s} ({s}) passed to {s}() - potential use-after-release (CWE-416/CWE-908)",
        .{ resource_desc, ptr_info.source_desc, callee_name },
    );

    var issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .critical,
        0.85,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [RESOURCE-UAF] {s} ({s}) -> {s}() in {s}", .{ resource_desc, ptr_info.source_desc, callee_name, func_name });
}

pub fn reportHeapAmbiguous(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    // M6 FIX: Add MemoryGraph gate - heap ambiguous only dangerous on FFI path
    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[HEAP-AMBIGUOUS SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Heap pointer passed to extern without clear ownership transfer");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Passed to {s}() - verify ownership contract", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) passed to {s}() - verify ownership transfer semantics (CWE-401)",
        .{ ptr_info.source_desc, callee_name },
    );

    var issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.60,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-MEDIUM] [HEAP-OWNERSHIP] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

/// Report heap pointer escaping to FFI boundary.
/// v0.1.6: malloc/calloc results passed to retaining extern functions
/// are critical FFI ownership issues — caller may not know to free them.
pub fn reportHeapEscapeToFFI(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 4);
    trace[0] = TraceEntry.init("Heap-allocated pointer escapes to FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s} (caller must manage lifetime)", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Passed to retaining FFI function {s}() - ownership transfer unclear", .{callee_name});
    trace[3] = try makeTrace(ctx.allocator, "If no matching free -> leak; if double-freed -> corruption (CWE-401/CWE-662)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) escapes to {s}() in {s} - ambiguous ownership transfer",
        .{ ptr_info.source_desc, callee_name, func_name },
    );

    var issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.78,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [HEAP-ESCAPE-FFI] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

pub fn reportFFINullGuardMissing(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("FFI extern function returns pointer but result not checked for NULL");
    trace[1] = try makeTrace(ctx.allocator, "Called {s}() which may return NULL on failure", .{callee_name});
    trace[2] = TraceEntry.init("Dereferencing NULL pointer from FFI call causes undefined behavior");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "FFI function {s}() return value not NULL-checked in {s} - potential NULL dereference (CWE-252/CWE-476)",
        .{ callee_name, func_name },
    );

    var issue = Issue.initWithTrace(
        .unchecked_return,
        message,
        location,
        .high,
        0.80,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [FFI-NULL-CHECK] {s}() result not NULL-checked in {s}", .{ callee_name, func_name });
}

pub fn reportBorrowEscapeFFI(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;

    // P6-13: Check if callee is a known bridge helper (returns_borrowed).
    // Bridge helpers like as_ptr, as_mut_ptr, c_str, data() return borrowed
    // pointers into existing data — they are NOT borrow_escape bugs.
    if (isBridgeHelper(ctx, callee_name)) {
        diag.debug("[BORROW-ESCAPE-FFI SUPPRESSED] '{s}' is known bridge helper (returns_borrowed) in {s}", .{ callee_name, func_name });
        return;
    }

    if (ptr_info.source_inst) |src_inst| {
        const ptr_val = @as(u64, @intFromPtr(src_inst));
        if (!ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[BORROW-ESCAPE-FFI SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }

    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Rust borrow (as_ptr/as_mut_ptr) passed to FFI function");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s} - borrow may outlive owner", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Passed to {s}() across FFI - if C stores pointer, use-after-free when Rust drops owner", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Borrowed pointer ({s}) passed to FFI {s}() in {s} - dangling if C retains beyond Rust owner lifetime (CWE-416)",
        .{ ptr_info.source_desc, callee_name, func_name },
    );

    var issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        0.82,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [BORROW-ESCAPE-FFI] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

pub fn reportCrossLanguageFree(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    alloc_lang: []const u8,
    free_lang: []const u8,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = try makeTrace(ctx.allocator, "Memory allocated by {s} deallocated by {s}", .{ alloc_lang, free_lang });
    trace[1] = try makeTrace(ctx.allocator, "Freed via {s}() - cross-language allocator mismatch", .{callee_name});
    trace[2] = TraceEntry.init("Different allocators may use incompatible heaps - undefined behavior on free");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Cross-language free: {s}-allocated memory freed by {s} deallocator {s}() in {s} (CWE-763)",
        .{ alloc_lang, free_lang, callee_name, func_name },
    );

    var issue = Issue.initWithTrace(
        .cross_language_free,
        message,
        location,
        .critical,
        0.88,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [CROSS-LANG-FREE] {s}-alloc freed by {s} {s}() in {s}", .{ alloc_lang, free_lang, callee_name, func_name });
}

pub fn reportFFITypeMismatch(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    mismatch_desc: []const u8,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Pointer type modified across FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "Modification: {s}", .{mismatch_desc});
    trace[2] = try makeTrace(ctx.allocator, "Passed to {s}() - type contract violation may cause undefined behavior", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "FFI type mismatch: {s} passed to {s}() in {s} - const/volatile contract violation (CWE-704)",
        .{ mismatch_desc, callee_name, func_name },
    );

    var issue = Issue.initWithTrace(
        .ffi_type_mismatch,
        message,
        location,
        .high,
        0.78,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [FFI-TYPE-MISMATCH] {s} -> {s}() in {s}", .{ mismatch_desc, callee_name, func_name });
}

// ============================================================================
// P6: Contract-Based Leak Guard
//
// Before reporting any leak, check if the resource has valid escapes.
// A resource that escaped via return/out-param/field/global is NOT a leak —
// ownership was transferred to someone else who is now responsible.
// ============================================================================

const contract_mod = @import("../../../semantics/resource/contract.zig");
const PointerContract = contract_mod.PointerContract;
const ViolationSeverity = contract_mod.ViolationSeverity;

/// Result of contract-based leak evaluation.
pub const LeakCheckResult = enum(u8) {
    /// Definitely a leak: owned, not released, no valid escapes.
    confirmed_leak,
    /// Probably a leak but some uncertainty (maybe_owned state).
    probable_leak,
    /// Not a leak: has valid disposal (return, out-param, field, global).
    valid_escape,
    /// Not a leak but lifetime risk (callback/thread escape).
    lifetime_risk,
    /// Cannot determine (no graph data available).
    unknown,
};

/// Evaluate whether an unfreed allocation is actually a leak using
/// PointerContract + EscapeKind analysis (P6-12).
///
/// Replaces the naive `allocated && !freed → leak` condition with:
///   `owned && !released && !hasValidEscape() → leak`
///
/// Returns what action the caller should take regarding this potential leak.
pub fn evaluateLeakWithContract(
    mem_graph: ?*memory_graph.MemoryGraph,
    ptr_val: u64,
) LeakCheckResult {
    const mg = mem_graph orelse return .unknown;
    const node = mg.nodes.get(ptr_val) orelse return .unknown;

    // Already freed → not a leak (could be use-after-release though)
    if (node.freed) return .valid_escape;

    // Has free sites recorded → was released somehow
    if (node.free_sites.items.len > 0) return .valid_escape;

    // Check escape list (P6 core logic)
    if (node.escapes) |escapes| {
        if (escapes.hasValidEscape()) {
            return .valid_escape;
        }
        if (escapes.hasLifetimeRiskEscape()) {
            return .lifetime_risk;
        }
    }

    // No escapes, no frees → this IS a leak
    // Check confidence based on alloc_family
    if (node.alloc_family != null) {
        return .confirmed_leak; // Family known → high confidence
    }

    return .probable_leak; // No family info → medium confidence
}

/// Check if a leak report should be suppressed due to valid escape.
/// Returns true if the report should be skipped/downgraded.
pub fn shouldSuppressLeakDueToEscape(
    mem_graph: ?*memory_graph.MemoryGraph,
    ptr_val: u64,
) bool {
    const result = evaluateLeakWithContract(mem_graph, ptr_val);
    return result == .valid_escape or result == .lifetime_risk or result == .unknown;
}

/// Get severity adjustment for a leak based on contract analysis.
/// Downgrades high-severity leaks that have partial evidence of escape.
pub fn getContractAdjustedSeverity(
    mem_graph: ?*memory_graph.MemoryGraph,
    ptr_val: u64,
    base_severity: Issue.Severity,
) Issue.Severity {
    const result = evaluateLeakWithContract(mem_graph, ptr_val);

    // Confirmed leak: keep original severity
    if (result == .confirmed_leak) return base_severity;

    // Probable leak: downgrade by one level
    if (result == .probable_leak) {
        return switch (base_severity) {
            .critical => .high,
            .high => .medium,
            else => base_severity,
        };
    }

    // Valid escape / lifetime risk / unknown: downgrade to diagnostic
    return .diagnostic;
}

/// Format a contract-based explanation string for issue messages.
/// Provides human-readable reason why something was/wasn't reported as leak.
pub fn formatContractExplanation(
    mem_graph: ?*memory_graph.MemoryGraph,
    ptr_val: u64,
) ![]const u8 {
    const mg = mem_graph orelse return "(no memory graph available)";
    const node = mg.nodes.get(ptr_val) orelse return "(node not found)";

    var parts = std.ArrayList([]const u8).init(mg.allocator);
    defer parts.deinit();

    // Show family info
    if (node.alloc_family) |f| {
        try parts.append(try std.fmt.allocPrint(mg.allocator, "alloc_family={s}", .{@tagName(f)}));
    }

    // Show escape info
    if (node.escapes) |escapes| {
        if (escapes.count() > 0) {
            var buf = std.ArrayList(u8).init(mg.allocator);
            defer buf.deinit();
            const writer = buf.writer();
            try writer.writeAll("escapes=[");
            _ = escapes.count(); // count available for future use
            try writer.writeAll("]");
            try parts.append(buf.toOwnedSlice());
        }
    }

    // Show free site count
    if (node.free_sites.items.len > 0) {
        try parts.append(try std.fmt.allocPrint(mg.allocator, "free_sites={d}", .{node.free_sites.items.len}));
    }

    if (parts.items.len == 0) {
        return "(no contract data)";
    }

    var result = std.ArrayList(u8).init(mg.allocator);
    const writer = result.writer();
    for (parts.items, 0..) |part, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll(part);
    }
    return result.toOwnedSlice();
}

// ============================================================================
// P6-13: Bridge Helper Detection
//
// Before reporting borrow_escape, check if the callee is a known bridge
// helper that returns borrowed pointers. These are NOT bugs — they're
// intentional safe-to-unsafe conversions.
// ============================================================================

/// Check if a callee function is a known bridge helper (returns borrowed pointer).
/// Uses SummaryStore for high-confidence matches, falls back to name patterns.
pub fn isBridgeHelper(ctx: *PassContext, callee_name: []const u8) bool {
    // 1. Check SummaryStore first (highest confidence)
    if (ctx.resource_summary) |store| {
        if (store.returnsBorrowed(callee_name)) {
            return true;
        }
    }

    // 2. Fallback: name pattern matching (from P5 bridge helper inference)
    const bridge_suffixes = [_][]const u8{
        "as_ptr", "as_mut_ptr", "ptr", "ptr_mut", "c_str",
        "data", "get_pointer", "slice::ptr",
    };
    for (bridge_suffixes) |suffix| {
        if (endsWithIgnoreCase(callee_name, suffix)) {
            // Higher confidence for qualified names (module::function)
            if (std.mem.indexOf(u8, callee_name, ".") != null or
                std.mem.indexOf(u8, callee_name, "::") != null)
            {
                return true;
            }
        }
    }

    // 3. Exact match for well-known bridge helpers
    const exact_matches = [_][]const u8{
        "@ptrCast",
    };
    for (exact_matches) |name| {
        if (std.mem.eql(u8, callee_name, name)) return true;
    }

    return false;
}

/// Case-insensitive suffix check (local helper).
fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const start = haystack.len - needle.len;
    for (needle, 0..) |nc, i| {
        const hc = haystack[start + i];
        const nlc = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
        const hlc = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
        if (hlc != nlc) return false;
    }
    return true;
}
