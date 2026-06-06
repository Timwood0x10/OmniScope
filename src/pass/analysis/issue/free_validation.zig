//! Free Validation Detection Pass
//!
//! Detects when free() is called on pointers that do not originate from
//! memory allocation functions. This can cause undefined behavior.
//!
//! Design principle: Only based on IR facts, no guessing.
//! - Track pointer origins (from_malloc, from_param, from_global, unknown)
//! - Check free() calls for valid origins
//! - Report violations with traceable reasoning
//!
//! Sub-modules:
//!   - free_validation_safety.zig  — Pure predicates for function name checks
//!   - free_validation_origin.zig — Pointer origin tracking state machine
//!   - free_validation_mg.zig     — MemoryGraph-based 6-layer validation pipeline
//!   - free_validation_contract.zig — FFIContractDB alloc/free pair validation
//!   - free_validation_report.zig — Issue report constructors

const std = @import("std");
const log = std.log.scoped(.free_validation);
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");
const ir_store_mod = @import("../../../ir/ir_store.zig");
const ModuleIRStore = ir_store_mod.ModuleIRStore;
const FunctionIR = ir_store_mod.FunctionIR;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const ValueOrigin = @import("../ffi/ffi_semantics.zig").ValueOrigin;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;
const cross_lang_detector = @import("cross_lang_free_detector.zig");
const ptr_utils = @import("../ptr_lifetime/ptr_lifetime_utils.zig");
const isIntentionalOwnershipTransfer = ptr_utils.isIntentionalOwnershipTransfer;

// Sub-module imports
const safety = @import("free_validation_safety.zig");
const origin = @import("free_validation_origin.zig");
const mg = @import("free_validation_mg.zig");
const contract = @import("free_validation_contract.zig");
const report = @import("free_validation_report.zig");

/// Memory deallocation functions — basic memory deallocators for free validation.
pub const FREE_FUNCTIONS = safety.FREE_FUNCTIONS;

/// Memory allocation functions — delegated to ptr_types (single source of truth).
pub const ALLOC_FUNCTIONS = safety.ALLOC_FUNCTIONS;

/// Free validation detection pass
///
/// This pass implements Rule 2 from go_noise.md:
/// Detect when free is called on non-malloc pointers.
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "danger-surface", "ptr-lifetime" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const ir_store = ctx.ir_store;
        if (ir_store.function_list.len == 0) return;

        const has_danger_surface = ctx.danger_surface_relevant.count() > 0;

        var issue_count: usize = 0;
        for (ir_store.function_list) |fir| {
            if (has_danger_surface and !ctx.isRelevantFunction(@as(u64, @intFromPtr(fir.func)))) continue;
            const count = analyzeFunction(ctx, fir, diag, has_danger_surface) catch |err| {
                diag.warn("FreeValidation: skipped function due to error: {} ({s})", .{ err, fir.name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += count;
        }

        if (issue_count > 0) {
            diag.info("[OMI-HIGH] FreeValidation: Found {} invalid free calls", .{issue_count});
        } else {
            diag.debug("FreeValidation: No invalid free calls found", .{});
        }
    }

    fn analyzeFunction(ctx: *PassContext, fir: *const FunctionIR, diag: *DiagnosticWriter, has_danger_surface: bool) !usize {
        var issue_count: usize = 0;
        const func = fir.func;

        const func_name = fir.name;
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = ctx.classifyFunctionSurface(func_name, func_loc);
        if (!classification.origin.shouldReportByDefault()) return 0;

        var pointer_origins = std.AutoHashMap(c.LLVMValueRef, origin.PointerInfo).init(ctx.allocator);
        defer {
            var iter = pointer_origins.iterator();
            while (iter.next()) |entry| {
                ctx.allocator.free(entry.value_ptr.source_desc);
            }
            pointer_origins.deinit();
        }

        // First pass: track function parameters as from_param
        {
            var param = c.LLVMGetFirstParam(func);

            var param_index: u32 = 0;
            while (@intFromPtr(param) != 0) : (param = c.LLVMGetNextParam(param)) {
                const desc = try std.fmt.allocPrint(ctx.allocator, "from parameter {d} in {s}", .{ param_index, func_name });
                const gop = try pointer_origins.getOrPut(param);
                if (gop.found_existing) {
                    ctx.allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = .{
                    .origin = .from_param,
                    .source_inst = null,
                    .source_desc = desc,
                };
                param_index += 1;
            }
        }

        // Second pass: track instruction pointer origins
        for (fir.instructions, 0..) |inst, idx| {
            _ = idx;
            try origin.trackPointerOrigin(ctx, inst, &pointer_origins);
        }

        // Third pass: check free calls
        for (fir.instructions) |inst| {
            if (try checkFreeCall(ctx, inst, &pointer_origins, func, diag, has_danger_surface)) {
                issue_count += 1;
            }
        }

        return issue_count;
    }

    /// Check if a free call is valid
    fn checkFreeCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        pointer_origins: *const std.AutoHashMap(c.LLVMValueRef, origin.PointerInfo),
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        has_danger_surface: bool,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (!llvm_safe.isCallOrInvoke(opcode)) return false;

        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return false;

        const callee_name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(callee_name_ptr) == 0) return false;

        const callee_name = std.mem.span(callee_name_ptr);
        if (!safety.isFreeFunction(callee_name)) return false;

        // Get the pointer being freed
        const ptr_arg = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(ptr_arg) == 0) return false;

        // Check origin
        const origin_info = pointer_origins.get(ptr_arg);
        const origin_val = if (origin_info) |info| info.origin else .unknown;

        // ── NEW: Cross-Language Free Detection (v0.2.0 enhancement) ──
        if (origin_info) |info| {
            const src_desc = info.source_desc;
            const alloc_func_name = contract.extractAllocFuncNameForCrossLang(src_desc);
            if (alloc_func_name) |alloc_func| {
                log.debug("CROSS-LANG-CHECK: alloc={s}, free={s}", .{ alloc_func, callee_name });

                const caller_name_ptr = c.LLVMGetValueName(caller_func);
                const caller_name_str = if (@intFromPtr(caller_name_ptr) != 0) std.mem.span(caller_name_ptr) else "";
                const intentional_caller_patterns = [_][]const u8{
                    "into_raw", "ManuallyDrop", "forget",   "transfer_ownership",
                    "handoff",  "ffi_export",   "c_export", "export_ptr",
                    "donate",
                };
                var is_intentional = false;
                for (intentional_caller_patterns) |pat| {
                    if (std.mem.indexOf(u8, caller_name_str, pat) != null) {
                        is_intentional = true;
                        break;
                    }
                }

                if (!is_intentional) {
                    if (try cross_lang_detector.detectCrossLanguageFree(alloc_func, callee_name, ctx.allocator)) |cross_issue| {
                        try report.reportCrossLangFreeIssue(ctx, caller_func, callee_name, ptr_arg, &cross_issue, diag);
                        return true;
                    }
                } else {
                    log.debug("CROSS-LANG-CHECK: Intentional transfer in caller={s}, skipping", .{caller_name_str});
                }
            }
        }

        // ── FFI Contract Database Validation (source_desc-based) ──
        if (origin_info) |info| {
            if (try contract.validateWithContractDBFromSource(ctx, info.source_desc, callee_name, caller_func, inst, diag)) |result| {
                return result;
            }
        }

        // Only report for clearly invalid origins (not unknown)
        switch (origin_val) {
            .from_param => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (safety.isFreeSafe(callee_name, origin_val, src)) return false;

                if (has_danger_surface) {
                    if (try mg.validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result;
                    }
                }

                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.startsWith(u8, callee_name, "operator delete"))
                {
                    return false;
                }
                try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                return true;
            },
            .from_global, .from_constant => {
                try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                return true;
            },
            .from_ffi_call => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (safety.isCrossAllocatorFree(.from_ffi_call, src, callee_name)) {
                    try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                    return true;
                }
                if (safety.isFreeSafe(callee_name, origin_val, src)) return false;

                if (has_danger_surface) {
                    if (try mg.validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result;
                    }
                }

                if (origin_info) |info| {
                    const cross_src = info.source_desc;
                    const alloc_is_cpp_new = std.mem.indexOf(u8, cross_src, "_Znwm") != null or
                        std.mem.indexOf(u8, cross_src, "_Znam") != null or
                        std.mem.indexOf(u8, cross_src, "operator new") != null;
                    const free_is_c_free = std.mem.eql(u8, callee_name, "free");
                    const alloc_is_c_malloc = std.mem.indexOf(u8, cross_src, "malloc") != null or
                        std.mem.indexOf(u8, cross_src, "calloc") != null or
                        std.mem.indexOf(u8, cross_src, "realloc") != null;
                    const free_is_cpp_delete = std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                        std.mem.indexOf(u8, callee_name, "_ZdaPv") != null;

                    if ((alloc_is_cpp_new and free_is_c_free) or
                        (alloc_is_c_malloc and free_is_cpp_delete))
                    {
                        try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                        return true;
                    }
                }

                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.eql(u8, callee_name, "kfree") or
                    std.mem.eql(u8, callee_name, "g_free") or
                    std.mem.startsWith(u8, callee_name, "operator delete") or
                    std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                    std.mem.indexOf(u8, callee_name, "_ZdaPv") != null or
                    std.mem.indexOf(u8, callee_name, "_Zdl") != null or
                    std.mem.indexOf(u8, callee_name, "_Zda") != null)
                {
                    return false;
                }
                try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                return true;
            },
            .from_malloc => {
                const src = if (origin_info) |info| info.source_desc else "";
                if (safety.isCrossAllocatorFree(.from_malloc, src, callee_name)) {
                    try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                    return true;
                }
                if (safety.isFreeSafe(callee_name, origin_val, src)) return false;

                if (has_danger_surface) {
                    if (try mg.validateFreeWithMemoryGraph(ctx, ptr_arg, callee_name, caller_func, diag)) |result| {
                        return result;
                    }
                }

                if (origin_info) |info| {
                    const cross_src = info.source_desc;
                    const alloc_is_cpp_new = std.mem.indexOf(u8, cross_src, "_Znwm") != null or
                        std.mem.indexOf(u8, cross_src, "_Znam") != null or
                        std.mem.indexOf(u8, cross_src, "operator new") != null;
                    const free_is_c_free = std.mem.eql(u8, callee_name, "free");
                    const alloc_is_c_malloc = std.mem.indexOf(u8, cross_src, "malloc") != null or
                        std.mem.indexOf(u8, cross_src, "calloc") != null or
                        std.mem.indexOf(u8, cross_src, "realloc") != null;
                    const free_is_cpp_delete = std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                        std.mem.indexOf(u8, callee_name, "_ZdaPv") != null;

                    if ((alloc_is_cpp_new and free_is_c_free) or
                        (alloc_is_c_malloc and free_is_cpp_delete))
                    {
                        try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                        return true;
                    }
                }

                if (std.mem.eql(u8, callee_name, "free") or
                    std.mem.eql(u8, callee_name, "kfree") or
                    std.mem.eql(u8, callee_name, "g_free") or
                    std.mem.startsWith(u8, callee_name, "operator delete") or
                    std.mem.indexOf(u8, callee_name, "_ZdlPv") != null or
                    std.mem.indexOf(u8, callee_name, "_ZdaPv") != null or
                    std.mem.indexOf(u8, callee_name, "_Zdl") != null or
                    std.mem.indexOf(u8, callee_name, "_Zda") != null)
                {
                    return false;
                }
                if (src.len > 0 and !safety.isFreeSafe(callee_name, origin_val, src)) {
                    try report.reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin_val, origin_info, diag);
                    return true;
                }
            },
            .from_library_borrow => {
                const caller_name_ptr = c.LLVMGetValueName(caller_func);
                const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                    std.mem.span(caller_name_ptr)
                else
                    "unknown";

                const message = try std.fmt.allocPrint(
                    ctx.allocator,
                    "Invalid free: pointer from borrowed library function was freed. " ++
                        "Borrowed references must not be freed by the caller (origin: {s}).",
                    .{if (origin_info) |info| info.source_desc else "unknown"},
                );
                const location = Location.init(caller_name);

                const trace = try ctx.allocator.alloc(TraceEntry, 3);
                trace[0] = TraceEntry.init("Free called on borrowed library reference");
                trace[1] = try createOriginTraceEntry(ctx.allocator, origin_val, origin_info);
                trace[2] = try createFreeTraceEntry(ctx.allocator, callee_name);

                var issue = Issue.initWithTrace(
                    .invalid_free,
                    message,
                    location,
                    .critical,
                    0.90,
                    trace,
                );
                errdefer issue.deinit(ctx.allocator);

                try ctx.addIssue(&issue);
                diag.warn("[OMI-CRITICAL] Invalid free of borrowed library ref in {s}: {s}() on borrowed pointer", .{
                    caller_name, callee_name,
                });
                return true;
            },
            .unknown => {},
        }

        return false;
    }
};

fn createOriginTraceEntry(allocator: std.mem.Allocator, origin_val: ValueOrigin, origin_info: ?origin.PointerInfo) !TraceEntry {
    const desc = if (origin_info) |info|
        try std.fmt.allocPrint(allocator, "Pointer origin: {s}", .{info.source_desc})
    else switch (origin_val) {
        .from_param => try allocator.dupe(u8, "Pointer origin: function parameter"),
        .from_global => try allocator.dupe(u8, "Pointer origin: global variable"),
        .from_constant => try allocator.dupe(u8, "Pointer origin: constant value"),
        .from_library_borrow => try allocator.dupe(u8, "Pointer origin: borrowed library reference"),
        .unknown => try allocator.dupe(u8, "Pointer origin: unknown"),
        else => try allocator.dupe(u8, "Pointer origin: non-heap source"),
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

test "FreeValidationPass - name and kind" {
    try std.testing.expectEqualStrings("free-validation", FreeValidationPass.name);
    try std.testing.expectEqual(PassKind.analysis, FreeValidationPass.kind);
}
