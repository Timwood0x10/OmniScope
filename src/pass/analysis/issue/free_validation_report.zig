//! Free Validation — Report Constructors
//!
//! Extracted from free_validation.zig: all report functions that create
//! issues and diagnostic output for invalid free, double-free, mismatch, etc.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const ValueOrigin = @import("../ffi/ffi_semantics.zig").ValueOrigin;
const mg_types = @import("../../../types/memory_graph_types.zig");
const AllocNode = mg_types.AllocNode;
const FFIContractDB = @import("../../../resource/ffi_contract_db.zig").FFIContractDB;
const cross_lang_detector = @import("cross_lang_free_detector.zig");
const ptr_utils = @import("../ptr_lifetime/ptr_lifetime_utils.zig");
const isIntentionalOwnershipTransfer = ptr_utils.isIntentionalOwnershipTransfer;
const origin_mod = @import("free_validation_origin.zig");
const PointerInfo = origin_mod.PointerInfo;

fn createOriginTraceEntry(
    allocator: std.mem.Allocator,
    origin: ValueOrigin,
    origin_info: ?PointerInfo,
) !TraceEntry {
    const desc = if (origin_info) |info|
        try std.fmt.allocPrint(allocator, "Pointer origin: {s}", .{info.source_desc})
    else switch (origin) {
        .from_param => try allocator.dupe(u8, "Pointer origin: function parameter"),
        .from_global => try allocator.dupe(u8, "Pointer origin: global variable"),
        .from_constant => try allocator.dupe(u8, "Pointer origin: constant value"),
        .from_malloc => try allocator.dupe(u8, "Pointer origin: heap allocation"),
        .from_ffi_call => try allocator.dupe(u8, "Pointer origin: FFI call"),
        .from_library_borrow => try allocator.dupe(u8, "Pointer origin: borrowed library reference"),
        .unknown => try allocator.dupe(u8, "Pointer origin: unknown"),
    };
    return TraceEntry.initOwned(desc);
}

fn createFreeTraceEntry(allocator: std.mem.Allocator, func_name: []const u8) !TraceEntry {
    const desc = try std.fmt.allocPrint(
        allocator,
        "Passed to {s}() which requires heap-allocated pointer",
        .{func_name},
    );
    return TraceEntry.initOwned(desc);
}

/// Report invalid free call
pub fn reportInvalidFree(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    free_func_name: []const u8,
    ptr_arg: c.LLVMValueRef,
    origin: ValueOrigin,
    origin_info: ?PointerInfo,
    diag: *DiagnosticWriter,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    // SAME-LANGUAGE MERGE GUARD for invalid_free:
    const is_cpp_deallocator = std.mem.indexOf(u8, free_func_name, "_ZdlPv") != null or
        std.mem.indexOf(u8, free_func_name, "_ZdaPv") != null;
    const is_unknown_origin = origin == .unknown or origin == .from_param or
        origin == .from_global or origin == .from_constant;

    if (is_cpp_deallocator and is_unknown_origin) {
        const module_lang = ctx.module_language.language;
        if (module_lang == .cpp or module_lang == .c) {
            std.log.scoped(.free_validation).debug("SAME-LANG-MERGE [invalid_free]: skipping {s} in {s} (origin={s}, module={s})", .{
                free_func_name, caller_name, @tagName(origin), @tagName(module_lang),
            });
            return;
        }
    }

    const location = Location.init(caller_name);

    const ptr_val: u64 = @intFromPtr(ptr_arg);
    const reaches_ffi = ctx.isOnDangerPathFull(ptr_val);
    const base_confidence: f32 = if (reaches_ffi) 0.85 else 0.75;
    const severity: Severity = if (reaches_ffi) .critical else .high;

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Free called on non-heap pointer");
    trace[1] = try createOriginTraceEntry(ctx.allocator, origin, origin_info);
    trace[2] = try createFreeTraceEntry(ctx.allocator, free_func_name);

    const origin_str = switch (origin) {
        .from_param => "function parameter",
        .from_global => "global variable",
        .from_constant => "constant",
        .from_malloc => "heap-allocated",
        .from_ffi_call => "FFI call",
        .from_library_borrow => "borrowed library reference",
        .unknown => "unknown source",
    };

    const ffi_note = if (reaches_ffi) " [cross-FFI alias detected]" else "";

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "{s}() called on {s} pointer (confidence: {d:.0}%%{s})",
        .{ free_func_name, origin_str, @as(u32, @intFromFloat(base_confidence * 100.0)), ffi_note },
    );

    var issue = Issue.initWithTrace(
        .invalid_free,
        message,
        location,
        severity,
        base_confidence,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);

    const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
    diag.warn("{s}Invalid {s} on {s} pointer in function: {s}{s}", .{ omi_prefix, free_func_name, origin_str, caller_name, ffi_note });
}

/// Report a cross-allocator mismatch free as CRITICAL issue.
pub fn reportCrossAllocatorFree(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    callee_name: []const u8,
    ptr_arg: c.LLVMValueRef,
    node: *const AllocNode,
    diag: *DiagnosticWriter,
) !void {
    std.log.scoped(.free_validation).debug("CROSS-ALLOCATOR: {s} on ptr allocated by family {s}", .{
        callee_name, if (node.alloc_family) |f| @tagName(f) else "unknown",
    });
    try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, .from_param, null, diag);
}

/// Report a double-free issue with high confidence.
pub fn reportDoubleFreeIssue(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    callee_name: []const u8,
    ptr_arg: c.LLVMValueRef,
    node: *const AllocNode,
    diag: *DiagnosticWriter,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    const location = Location.init(caller_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 4);
    trace[0] = TraceEntry.init("Double-free detected");
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory at 0x{x} was first freed at instruction 0x{x}", .{ @intFromPtr(ptr_arg), node.freed_by orelse 0 }));
    trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Second free attempt via {s}()", .{callee_name}));
    trace[3] = try createFreeTraceEntry(ctx.allocator, callee_name);

    const message = try std.fmt.allocPrint(ctx.allocator, "Double free detected: memory allocated at 0x{x} was already freed at 0x{x}. " ++
        "Second free via {s}() causes undefined behavior (heap corruption, security vulnerability).", .{
        node.alloc_inst,
        node.freed_by orelse 0,
        callee_name,
    });

    var issue = Issue.initWithTrace(
        .double_free,
        message,
        location,
        .critical,
        0.98,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);

    diag.warn("[OMI-CRITICAL] Double free detected in {s}: {s}() on already-freed memory", .{
        caller_name, callee_name,
    });
}

/// Report an alloc/free mismatch issue from FFI Contract Database.
pub fn reportMismatchIssue(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    wrong_free_func: []const u8,
    ptr_arg: c.LLVMValueRef,
    node: *const AllocNode,
    alloc_func_name: []const u8,
    db: *FFIContractDB,
    diag: *DiagnosticWriter,
) !void {
    _ = ptr_arg;
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    const location = Location.init(caller_name);

    const expected_releases = db.getExpectedReleases(alloc_func_name);
    const expected_str = if (expected_releases) |releases| blk: {
        if (releases.len == 0) break :blk "see documentation";
        break :blk releases[0];
    } else "see documentation";

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Resource allocated via {s}() at instruction 0x{x}", .{ alloc_func_name, node.alloc_inst }));
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Incorrectly released via {s}() (wrong function for this resource type)", .{wrong_free_func}));
    trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Expected release function(s): {s}", .{expected_str}));

    const message = try std.fmt.allocPrint(ctx.allocator, "Allocation/release mismatch: {s}() at 0x{x} incorrectly freed with {s}(). " ++
        "Expected: {s}. This may cause memory corruption or leaks.", .{
        alloc_func_name,
        node.alloc_inst,
        wrong_free_func,
        expected_str,
    });

    const severity: Severity = if (db.isErrorProneLib(alloc_func_name))
        .critical
    else
        .high;

    const base_confidence: f32 = db.getConfidence(alloc_func_name);

    var issue = Issue.initWithTrace(
        .contract_mismatch,
        message,
        location,
        severity,
        base_confidence,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);

    const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
    diag.warn("{s}Allocation/release mismatch in {s}: {s} should use {s}, not {s}", .{
        omi_prefix,
        caller_name,
        alloc_func_name,
        expected_str,
        wrong_free_func,
    });
}

/// Report a cross-allocator mismatch bug using source_desc information.
pub fn reportCrossAllocatorMismatch(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    alloc_func_name: []const u8,
    wrong_free_func: []const u8,
    expected_frees: []const []const u8,
    diag: *DiagnosticWriter,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    const location = Location.init(caller_name);

    var expected_buf: [512]u8 = undefined;
    var expected_fbs = std.io.fixedBufferStream(&expected_buf);
    const expected_writer = expected_fbs.writer();
    for (expected_frees, 0..) |free_name, i| {
        if (i > 0) expected_writer.writeAll(" or ") catch {};
        expected_writer.writeAll(free_name) catch {};
    }
    const expected_str = expected_fbs.getWritten();

    const message = try std.fmt.allocPrint(ctx.allocator,
        \\Cross-allocator mismatch: memory was allocated by '{s}' but freed with '{s}'.
        \\Expected release function(s): {s}.
        \\This can cause memory corruption, heap overflow, or double-free vulnerabilities.
        \\
        \\Example of correct usage:
        \\  ptr = {s}(...);   // Allocation
        \\  // ... use ptr ...
        \\  {s}(ptr);         // Correct release (NOT {s})
    , .{
        alloc_func_name,
        wrong_free_func,
        expected_str,
        alloc_func_name,
        expected_frees[0],
        wrong_free_func,
    });

    const trace = try ctx.allocator.alloc(TraceEntry, 4);
    trace[0] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory allocated via {s}() - library-specific allocator", .{alloc_func_name}));
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Incorrectly released via {s}() - wrong deallocator for this resource type", .{wrong_free_func}));
    trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Expected: {s}", .{expected_str}));
    trace[3] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator,
        \\Correct pattern:
        \\  ptr = {s}(...);
        \\  {s}(ptr);  // NOT {s}(ptr)
    , .{ alloc_func_name, expected_frees[0], wrong_free_func }));

    var db_check = FFIContractDB.init(ctx.allocator) catch return;
    defer db_check.deinit();
    const severity: Severity = if (db_check.isErrorProneLib(alloc_func_name))
        .critical
    else
        .high;

    const base_confidence: f32 = 0.95;

    var issue = Issue.initWithTrace(
        .contract_mismatch,
        message,
        location,
        severity,
        base_confidence,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);

    const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
    diag.warn("{s}Cross-allocator mismatch in {s}: {s} allocated by '{s}' but freed with '{s}'. Use {s} instead.", .{
        omi_prefix,
        caller_name,
        alloc_func_name,
        alloc_func_name,
        wrong_free_func,
        expected_str,
    });
}

/// Report a cross-language free mismatch issue.
pub fn reportCrossLangFreeIssue(
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    callee_name: []const u8,
    ptr_arg: c.LLVMValueRef,
    cross_issue: *cross_lang_detector.CrossLangFreeIssue,
    diag: *DiagnosticWriter,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    if (isIntentionalOwnershipTransfer(caller_name)) {
        diag.info("[SUPPRESSED] Cross-language free in {s}: intentional ownership transfer (alloc={s}, free={s})", .{
            caller_name, cross_issue.alloc_family.displayName(), cross_issue.free_family.family.displayName(),
        });
        ctx.allocator.free(cross_issue.message);
        return;
    }

    const location = Location.init(caller_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 5);
    trace[0] = TraceEntry.init("Cross-language free detected");
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Pointer address: 0x{x}", .{@intFromPtr(ptr_arg)}));
    trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Memory allocated by {s} ({s})", .{ cross_issue.alloc_family.displayName(), cross_issue.free_family.func_name }));
    trace[3] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Freed using {s} ({s})", .{ cross_issue.free_family.family.displayName(), callee_name }));
    trace[4] = TraceEntry.initOwned(try std.fmt.allocPrint(ctx.allocator, "Different runtimes may use different heaps - this is undefined behavior", .{}));

    const severity: Severity = switch (cross_issue.severity) {
        .critical => .critical,
        .high => .high,
    };

    var issue = Issue.initWithTrace(
        .invalid_free,
        cross_issue.message,
        location,
        severity,
        cross_issue.confidence,
        trace,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);

    const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
    diag.warn("{s}Cross-language free in {s}: {s} freed by {s}. Confidence: {d:.0}%%", .{
        omi_prefix,
        caller_name,
        cross_issue.alloc_family.displayName(),
        cross_issue.free_family.family.displayName(),
        @as(u32, @intFromFloat(cross_issue.confidence * 100.0)),
    });
}
