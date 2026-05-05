//! Reporting functions for PtrLifetimePass.
//!
//! Contains all violation reporting functions that generate Issue objects
//! and diagnostic messages for detected pointer lifetime violations.
//!
//! Extracted from ptr_lifetime.zig to comply with the 1000-line limit.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;
const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;

pub fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

pub fn reportStackEscape(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    _: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    const is_extern_callee = is_extern_function(callee_name) or
        (std.mem.indexOf(u8, callee_name, "ffi_") != null);

    if (ptr_info.source_inst) |inst| {
        const ptr_val = @as(u64, @intFromPtr(inst));
        if (!is_extern_callee and !ctx.isOnDangerPathFull(ptr_val)) {
            diag.debug("[STACK-ESCAPE SUPPRESSED] Pointer not on FFI danger path in {s}", .{func_name});
            return;
        }
    }

    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Stack pointer passed to FFI boundary function");
    trace[1] = try makeTrace(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = try makeTrace(ctx.allocator, "Passed to {s}() which may retain pointer beyond caller scope", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Stack pointer ({s}) escapes to FFI function {s}() - pointer invalid after function returns (CWE-562)",
        .{ ptr_info.source_desc, callee_name },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.88,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.critical("[OMI-CRITICAL] [STACK-ESCAPE] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
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

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.92,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.72,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.75,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.90,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .high,
        0.82, // M5 FIX: UAF confidence raised from 0.75 to 0.82 (consistent with severity)
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .critical,
        0.85,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.60,
        trace,
    );

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

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.78,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [HEAP-ESCAPE-FFI] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}
