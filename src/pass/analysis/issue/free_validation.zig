//! Free Validation Detection Pass
//!
//! Detects when free() is called on pointers that do not originate from
//! memory allocation functions. This can cause undefined behavior.
//!
//! Design principle: Only based on IR facts, no guessing.
//! - Track pointer origins (from_malloc, from_param, from_global, unknown)
//! - Check free() calls for valid origins
//! - Report violations with traceable reasoning

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const ValueOrigin = @import("../ffi_semantics.zig").ValueOrigin;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;
const ffi_utils = @import("../ffi_utils.zig");
const ptr_types = @import("../ptr_lifetime_types.zig");

/// Memory deallocation functions — basic memory deallocators for free validation.
/// NOTE: This is distinct from ptr_types.KNOWN_DEALLOCATORS.free_functions which
/// covers library-specific cleanup (sqlite3_free, curl_easy_cleanup, etc.).
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free",           "dealloc",       "deallocate",   "operator delete", "operator delete[]",
    // Rust global deallocator intrinsics (substring-matched via isFreeFunction)
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};

/// Memory allocation functions — delegated to ptr_types (single source of truth).
pub const ALLOC_FUNCTIONS = ptr_types.HEAP_ALLOC_FUNCTIONS;

/// Free validation detection pass
///
/// This pass implements Rule 2 from go_noise.md:
/// Detect when free is called on non-malloc pointers.
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var issue_count: usize = 0;
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) continue;
            // Function-level error isolation
            const count = analyzeFunction(ctx, func, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("FreeValidation: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += count;
        }

        diag.info("FreeValidation: Analyzed functions, found {} invalid free calls", .{issue_count});
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return 0;
        const func_name = std.mem.span(func_name_ptr);
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
        if (!classification.origin.shouldReportByDefault()) return 0;

        // Track pointer origins within this function
        var pointer_origins = std.AutoHashMap(c.LLVMValueRef, PointerInfo).init(ctx.allocator);
        defer {
            // Free all allocated source_desc strings
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
                // Use getOrPut to check if key exists and free old desc if needed
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
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try trackPointerOrigin(ctx.allocator, inst, &pointer_origins);
            }
        }

        // Third pass: check free calls
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (try checkFreeCall(ctx, inst, &pointer_origins, func, diag)) {
                    issue_count += 1;
                }
            }
        }

        return issue_count;
    }

    /// Information about a pointer's origin
    const PointerInfo = struct {
        /// Origin of the pointer
        origin: ValueOrigin,
        /// Source instruction (if from allocation)
        source_inst: ?c.LLVMValueRef,
        /// Description for trace
        source_desc: []const u8,
    };

    /// Track the origin of pointers
    fn trackPointerOrigin(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        pointer_origins: *std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            // Allocation calls - mark as from_malloc
            c.LLVMCall => {
                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) != 0) {
                    const func_name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(func_name_ptr) != 0) {
                        const func_name = std.mem.span(func_name_ptr);

                        if (isAllocFunction(func_name)) {
                            const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_malloc,
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        } else if (isFFIBoundaryCall(func_name)) {
                            // FFI boundary call returning a pointer — cross-allocator risk
                            const desc = try std.fmt.allocPrint(allocator, "from FFI call {s}()", .{func_name});
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_ffi_call,
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        }
                    }
                }
            },

            // Load/Store - propagate origin (copy source_desc)
            c.LLVMLoad => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            // GEP - propagate origin (copy source_desc)
            c.LLVMGetElementPtr => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            // BitCast - propagate origin (copy source_desc)
            c.LLVMBitCast => {
                const ptr = c.LLVMGetOperand(inst, 0);
                if (pointer_origins.get(ptr)) |info| {
                    const desc = try allocator.dupe(u8, info.source_desc);
                    const gop = try pointer_origins.getOrPut(inst);
                    if (gop.found_existing) {
                        allocator.free(gop.value_ptr.source_desc);
                    }
                    gop.value_ptr.* = .{
                        .origin = info.origin,
                        .source_inst = info.source_inst,
                        .source_desc = desc,
                    };
                }
            },

            else => {},
        }
    }

    /// Check if a free call is valid
    fn checkFreeCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        pointer_origins: *const std.AutoHashMap(c.LLVMValueRef, PointerInfo),
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode != c.LLVMCall) return false;

        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return false;

        const callee_name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(callee_name_ptr) == 0) return false;

        const callee_name = std.mem.span(callee_name_ptr);
        if (!isFreeFunction(callee_name)) return false;

        // Get the pointer being freed
        const ptr_arg = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(ptr_arg) == 0) return false;

        // Check origin
        const origin_info = pointer_origins.get(ptr_arg);
        const origin = if (origin_info) |info| info.origin else .unknown;

        // Only report for clearly invalid origins (not unknown - may be cross-function alloc)
        // unknown origin is skipped because allocation may have happened in another function
        //
        // ValueOrigin enum coverage (ffi_semantics.zig):
        //   - .from_param / .from_global / .from_constant → invalid free (report)
        //   - .from_malloc → valid (skip)
        //   - .unknown → cross-function alloc (skip to avoid false positives)
        //
        // NOTE: This switch is exhaustive for all ValueOrigin variants.
        // The Zig compiler will emit a compile error if new enum values are added
        // without updating this switch, ensuring completeness at compile time.
        switch (origin) {
            .from_param => {
                // Skip from_param when the free function is a Rust dealloc.
                // Rust's ownership model transfers allocation responsibility to callees,
                // so __rustc__rustc_dealloc on function parameters is normal behavior.
                // This avoids false positives for cross-function memory management.
                if (isRustDeallocFunction(callee_name)) return false;
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_global, .from_constant => {
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_ffi_call => {
                // Pointer from FFI boundary call being freed by a different allocator.
                // Risk: C-allocated pointer freed by __rust_dealloc, or vice versa.
                // Report with reduced confidence since cross-allocator free is
                // sometimes legitimate (e.g., C's malloc + Rust's free wrapper).
                if (!isRustDeallocFunction(callee_name) and
                    !std.mem.eql(u8, callee_name, "free"))
                {
                    // Non-standard free on FFI-sourced ptr — less confident
                    return false;
                }
                try reportInvalidFree(ctx, caller_func, callee_name, ptr_arg, origin, origin_info, diag);
                return true;
            },
            .from_malloc => {},
            .unknown => {},
        }

        return false;
    }

    /// Check if function is a Rust deallocation function.
    /// Only matches actual Rust dealloc intrinsics (NOT general drop glue).
    /// Drop glue includes destructors that don't necessarily deallocate memory.
    fn isRustDeallocFunction(func_name: []const u8) bool {
        const rust_dealloc_patterns = [_][]const u8{
            "__rustc__rustc_dealloc",
            "__rust_dealloc",
        };
        for (rust_dealloc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if callee is an FFI boundary function (non-Rust-mangled name).
    /// Used to detect pointers returned from C/external functions, which carry
    /// cross-allocator free risk when passed to libc::free or __rust_dealloc.
    fn isFFIBoundaryCall(func_name: []const u8) bool {
        if (func_name.len < 2) return false;
        // Rust-internal functions use _ZN / _RNv / _R mangled prefixes.
        // LLVM intrinsics start with "llvm.".
        // Anything else that doesn't start with these is likely an extern "C" FFI call.
        const rust_prefixes = [_][]const u8{ "_ZN", "_RNv", "_R" };
        for (rust_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return false;
        }
        if (std.mem.startsWith(u8, func_name, "llvm.")) return false;
        return true;
    }

    /// Check if function is a free function.
    /// Uses exact match + endsWith to avoid FP like 'my_custom_free' matching 'free'.
    fn isFreeFunction(func_name: []const u8) bool {
        for (FREE_FUNCTIONS) |free_func| {
            if (functionNameMatches(func_name, free_func)) {
                return true;
            }
        }
        return false;
    }

    /// Check if function is an allocation function.
    /// Uses exact match + endsWith to avoid FP like 'my_custom_allocator' matching 'alloc'.
    fn isAllocFunction(func_name: []const u8) bool {
        for (ALLOC_FUNCTIONS) |alloc_func| {
            if (functionNameMatches(func_name, alloc_func)) {
                return true;
            }
        }
        return false;
    }

    /// Match strategy: exact equality OR suffix match.
    /// Prevents substring FP (e.g., 'my_custom_free' ≠ 'free')
    /// while still catching mangled names like '_ZN...freeEv'.
    fn functionNameMatches(func_name: []const u8, pattern: []const u8) bool {
        if (std.mem.eql(u8, func_name, pattern)) return true;
        if (std.mem.endsWith(u8, func_name, pattern)) return true;
        return false;
    }

    /// Report invalid free call
    fn reportInvalidFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        free_func_name: []const u8,
        ptr_arg: c.LLVMValueRef,
        origin: ValueOrigin,
        origin_info: ?PointerInfo,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ptr_arg;
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // Build trace for reasoning path
        const trace = try ctx.allocator.alloc(TraceEntry, 3);
        trace[0] = TraceEntry.init("Free called on non-heap pointer");
        trace[1] = try createOriginTraceEntry(ctx.allocator, origin, origin_info);
        trace[2] = try createFreeTraceEntry(ctx.allocator, free_func_name);

        const origin_str = switch (origin) {
            .from_param => "function parameter",
            .from_global => "global variable",
            .from_constant => "constant",
            .unknown => "unknown source",
            else => "non-heap source",
        };

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}() called on {s} pointer (confidence: {d:.2}%)",
            .{ free_func_name, origin_str, 75.0 },
        );

        const issue = Issue.initWithTrace(
            .invalid_free,
            message,
            location,
            .high,
            0.75,
            trace,
        );

        try ctx.addIssue(&issue);

        diag.warn("Invalid {s} on {s} pointer in function: {s}", .{ free_func_name, origin_str, caller_name });
    }

    /// Create trace entry for pointer origin
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
            .unknown => try allocator.dupe(u8, "Pointer origin: unknown"),
            else => try allocator.dupe(u8, "Pointer origin: non-heap source"),
        };
        return TraceEntry.initOwned(desc);
    }

    /// Create trace entry for free call
    fn createFreeTraceEntry(allocator: std.mem.Allocator, func_name: []const u8) !TraceEntry {
        const desc = try std.fmt.allocPrint(
            allocator,
            "Passed to {s}() which requires heap-allocated pointer",
            .{func_name},
        );
        return TraceEntry.initOwned(desc);
    }
};

test "FreeValidationPass - name and kind" {
    try std.testing.expectEqualStrings("free-validation", FreeValidationPass.name);
    try std.testing.expectEqual(PassKind.analysis, FreeValidationPass.kind);
}

test "FreeValidationPass - isFreeFunction" {
    try std.testing.expect(FreeValidationPass.isFreeFunction("free"));
    try std.testing.expect(FreeValidationPass.isFreeFunction("dealloc"));
    try std.testing.expect(!FreeValidationPass.isFreeFunction("malloc"));
    try std.testing.expect(!FreeValidationPass.isFreeFunction("printf"));
}

test "FreeValidationPass - isAllocFunction" {
    try std.testing.expect(FreeValidationPass.isAllocFunction("malloc"));
    try std.testing.expect(FreeValidationPass.isAllocFunction("calloc"));
    try std.testing.expect(!FreeValidationPass.isAllocFunction("free"));
    try std.testing.expect(!FreeValidationPass.isAllocFunction("printf"));
}
