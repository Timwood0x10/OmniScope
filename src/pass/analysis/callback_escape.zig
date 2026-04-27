//! Callback Escaping Detector
//!
//! Phase 4.2: Detects Go cgo pointer retention bugs and callback escaping patterns.
//!
//! Key detection targets:
//! - Go pointer passed to C via C.CBytes() without runtime.KeepAlive
//! - unsafe.Pointer conversion that may dangle after GC
//! - C function retaining Go-allocated pointer beyond call scope
//! - Missing C.free / C.malloc pairs in cgo code
//!
//! Reference: plan/lang_ffi_analysis/go_ffi_fliter.md
//!
//! Example bugs detected:
//!
//!   // Go: pointer retained by C after call
//!   var buf []byte{1, 2, 3}
//!   C.process(C.CBytes(string(buf)))  // C retains pointer, GC may reclaim buf
//!
//!   // Go: missing KeepAlive for escaped pointer
//!   ptr := C.malloc(1024)
//!   defer C.free(ptr)
//!   C.useData(ptr)
//!   // BUG: no runtime.KeepAlive(ptr) - GC could run during C.useData

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

/// Types of callback escaping violations detected.
pub const EscapeViolation = enum(u8) {
    /// Go pointer passed to C without KeepAlive guard
    go_pointer_no_keepalive,
    /// C.CBytes result passed to retaining function
    cbytes_escape,
    /// unsafe.Pointer used across FFI boundary without lifetime guarantee
    unsafeptr_dangling_risk,
    /// malloc without corresponding free (leak)
    malloc_without_free,
    /// free without matching malloc (double-free risk)
    free_without_malloc,
};

/// Classification of a detected escape pattern.
pub const EscapePattern = struct {
    violation_type: EscapeViolation,
    confidence: f32,
    func_name: []const u8,
    callee_name: []const u8,
    description: []const u8,
};

/// Statistics for the callback escape detector.
pub const EscapeStats = struct {
    total_functions_analyzed: u32 = 0,
    go_cgo_boundaries_found: u32 = 0,
    keepalive_missing: u32 = 0,
    cbytes_escapes: u32 = 0,
    unsafeptr_risks: u32 = 0,
    malloc_leaks: u32 = 0,
    free_orphans: u32 = 0,

    pub fn formatSummary(self: EscapeStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   CALLBACK ESCAPE DETECTOR SUMMARY ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:      {d:>8}     ║\n", .{self.total_functions_analyzed});
        try writer.print("║  CGo boundaries found:    {d:>8}     ║\n", .{self.go_cgo_boundaries_found});
        try writer.print("║  Missing KeepAlive:       {d:>8}     ║\n", .{self.keepalive_missing});
        try writer.print("║  CBytes escapes:          {d:>8}     ║\n", .{self.cbytes_escapes});
        try writer.print("║  Unsafe.Pointer risks:    {d:>8}     ║\n", .{self.unsafeptr_risks});
        try writer.print("║  Malloc-without-free:     {d:>8}     ║\n", .{self.malloc_leaks});
        try writer.print("║  Free-orphan calls:       {d:>8}     ║\n", .{self.free_orphans});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Go CGo Pattern Detection
// ============================================================================

/// Functions that indicate cgo glue code (compiler-generated).
const CGO_GLUE_PATTERNS = &[_][]const u8{
    "_cgo_",
    "_Cfunc_",
    "_cgo_gotypes",
    "crosscall2",
};

/// Known Go runtime functions related to cgo safety.
const GO_RUNTIME_SAFETY_FUNCTIONS = &[_][]const u8{
    "runtime.KeepAlive",
    "runtime_Pin",
    "runtime_Unpin",
    "runtime_cgocall",
};

/// C standard library functions that commonly retain pointers.
const C_RETAINING_FUNCTIONS = &[_][]const u8{
    "register_callback",
    "set_handler",
    "pthread_create",
    "signal",
    "atexit",
    "SDL_SetEventCallback",
    "glfwSetCallback",
};

/// Check if a function name indicates cgo boundary code.
pub fn isCgoBoundary(func_name: []const u8) bool {
    for (CGO_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

    if (std.mem.indexOf(u8, func_name, "C.") != null) return true;

    return false;
}

/// Check if a function is a Go runtime safety function (KeepAlive etc).
pub fn isGoSafetyFunction(callee_name: []const u8) bool {
    for (GO_RUNTIME_SAFETY_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }
    return false;
}

/// Check if a callee may retain its pointer argument.
fn mayRetainInC(callee_name: []const u8) bool {
    for (C_RETAINING_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }

    const retaining_prefixes = [_][]const u8{
        "register_", "set_", "add_", "subscribe_",
    };
    for (retaining_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) return true;
    }

    return false;
}

/// Detect C.CBytes pattern in function names.
pub fn isCBytesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "CBytes") != null or
        std.mem.indexOf(u8, name, "C.GoString") != null or
        std.mem.indexOf(u8, name, "C.GoStringN") != null;
}

/// Detect unsafe.Pointer conversion pattern.
pub fn isUnsafePtrConversion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "unsafe.Pointer") != null or
        std.mem.indexOf(u8, name, "uintptr") != null;
}

// ============================================================================
// Main Pass
// ============================================================================

/// Callback Escaping Detector Pass
///
/// Analyzes functions for cgo-related pointer lifetime issues:
/// 1. Go pointers passed to C without KeepAlive protection
/// 2. C.CBytes results escaping to retaining functions
/// 3. Unsafe.Pointer conversions at FFI boundaries
/// 4. Malloc/free pairing verification
pub const CallbackEscapePass = struct {
    pub const name = "callback-escape";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var stats = EscapeStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            try analyzeFunction(ctx, func, diag, &stats);
        }

        diag.info("CallbackEscape: analyzed {} funcs, {} cgo boundaries, {} issues found",
            .{ stats.total_functions_analyzed, stats.go_cgo_boundaries_found,
               stats.keepalive_missing + stats.cbytes_escapes +
                   stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans });
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        stats.total_functions_analyzed += 1;

        var has_keepalive = false;
        var alloc_sites = std.ArrayList(AllocSiteInfo).init(ctx.allocator);
        defer alloc_sites.deinit();
        var free_sites = std.ArrayList(FreeSiteInfo).init(ctx.allocator);
        defer free_sites.deinit();
        var cgo_calls = std.ArrayList(CGoCallInfo).init(ctx.allocator);
        defer cgo_calls.deinit();

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try scanInstruction(ctx.allocator, inst, &has_keepalive, &alloc_sites, &free_sites, &cgo_calls);
            }
        }

        if (cgo_calls.items.len > 0) {
            stats.go_cgo_boundaries_found += 1;
        }

        if (!has_keepalive and cgo_calls.items.len > 0) {
            for (cgo_calls.items) |call| {
                if (call.is_pointer_arg and mayRetainInC(call.callee_name)) {
                    try reportMissingKeepAlive(ctx, func_name, call, diag);
                    stats.keepalive_missing += 1;
                }
            }
        }

        for (cgo_calls.items) |call| {
            if (isCBytesPattern(call.callee_name)) {
                if (mayRetainInC(call.next_call orelse "")) {
                    try reportCBytesEscape(ctx, func_name, call, diag);
                    stats.cbytes_escapes += 1;
                }
            }

            if (isUnsafePtrConversion(call.callee_name)) {
                try reportUnsafePtrRisk(ctx, func_name, call, diag);
                stats.unsafeptr_risks += 1;
            }
        }

        try checkMallocFreePairing(ctx, func_name, &alloc_sites, &free_sites, diag, stats);
    }

    fn scanInstruction(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        has_keepalive: *bool,
        alloc_sites: *std.ArrayList(AllocSiteInfo),
        free_sites: *std.ArrayList(FreeSiteInfo),
        cgo_calls: *std.ArrayList(CGoCallInfo),
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) == 0) return;

            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) == 0) return;

            const callee_name = std.mem.span(name_ptr);

            if (isGoSafetyFunction(callee_name)) {
                has_keepalive.* = true;
            }

            if (isCgoBoundary(callee_name) or
                std.mem.indexOf(u8, callee_name, "malloc") != null or
                std.mem.indexOf(u8, callee_name, "calloc") != null)
            {
                try alloc_sites.append(.{
                    .inst_id = inst,
                    .func_name = try allocator.dupe(u8, callee_name),
                });
            }

            if (std.mem.indexOf(u8, callee_name, "free") != null) {
                try free_sites.append(.{
                    .inst_id = inst,
                    .func_name = try allocator.dupe(u8, callee_name),
                });
            }

            if (isCgoBoundary(callee_name) or
                isCBytesPattern(callee_name) or
                isUnsafePtrConversion(callee_name))
            {
                const num_ops = c.LLVMGetNumOperands(inst);
                var has_ptr_arg = false;
                var i: u32 = 0;
                while (i < num_ops) : (i += 1) {
                    const op = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(op) != 0) {
                        const type_kind = c.LLVMGetTypeKind(c.LLVMTypeOf(op));
                        if (type_kind == c.LLVMPointerTypeKind) {
                            has_ptr_arg = true;
                            break;
                        }
                    }
                }

                try cgo_calls.append(.{
                    .inst = inst,
                    .callee_name = try allocator.dupe(u8, callee_name),
                    .is_pointer_arg = has_ptr_arg,
                    .next_call = null,
                });
            }
        }
    }

    fn checkMallocFreePairing(
        ctx: *PassContext,
        func_name: []const u8,
        alloc_sites: *const std.ArrayList(AllocSiteInfo),
        free_sites: *const std.ArrayList(FreeSiteInfo),
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        var malloc_count: u32 = 0;
        var free_count: u32 = 0;

        for (alloc_sites.items) |site| {
            if (std.mem.indexOf(u8, site.func_name, "malloc") != null or
                std.mem.indexOf(u8, site.func_name, "calloc") != null)
            {
                malloc_count += 1;
            }
        }

        for (free_sites.items) |site| {
            if (std.mem.indexOf(u8, site.func_name, "free") != null) {
                free_count += 1;
            }
        }

        if (malloc_count > free_count) {
            try reportMallocLeak(ctx, func_name, malloc_count, free_count, diag);
            stats.malloc_leaks += @as(u32, @intCast(malloc_count - free_count));
        }

        if (free_count > malloc_count) {
            try reportFreeOrphan(ctx, func_name, malloc_count, free_count, diag);
            stats.free_orphans += @as(u32, @intCast(free_count - malloc_count));
        }
    }
};

// ============================================================================
// Data Structures
// ============================================================================

const AllocSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

const FreeSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

const CGoCallInfo = struct {
    inst: c.LLVMValueRef,
    callee_name: []const u8,
    is_pointer_arg: bool,
    next_call: ?[]const u8,
};

// ============================================================================
// Reporting
// ============================================================================

fn reportMissingKeepAlive(
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

    try ctx.addIssue(issue);
    diag.warn("[NO-KEEPALIVE] {s} -> {s}() in {s}", .{ "Go ptr", call.callee_name, func_name });
}

fn reportCBytesEscape(
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

    try ctx.addIssue(issue);
    diag.warn("[CBYTES-ESCAPE] {s} in {s}", .{ call.callee_name, func_name });
}

fn reportUnsafePtrRisk(
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

    try ctx.addIssue(issue);
    diag.warn("[UNSAFE-PTR] {s} in {s}", .{ call.callee_name, func_name });
}

fn reportMallocLeak(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{} malloc/calloc calls found", .{malloc_count});
    trace[1] = try makeTrace(ctx.allocator, "{} free() calls found - {} allocations never freed", .{ free_count, malloc_count - free_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Memory leak: {} malloc/calloc without matching free in {s} (CWE-401)",
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

    try ctx.addIssue(issue);
    diag.warn("[MALLOC-LEAK] {} allocs vs {} frees in {s}", .{ malloc_count, free_count, func_name });
}

fn reportFreeOrphan(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{} free() calls found", .{free_count});
    trace[1] = try makeTrace(ctx.allocator, "{} malloc/calloc calls - {} frees may operate on unallocated memory", .{ malloc_count, free_count - malloc_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Potential double-free or invalid free: {} free() vs {} malloc in {s} (CWE-415)",
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

    try ctx.addIssue(issue);
    diag.warn("[FREE-ORPHAN] {} frees vs {} allocs in {s}", .{ free_count, malloc_count, func_name });
}

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "CallbackEscapePass - name and kind" {
    try std.testing.expectEqualStrings("callback-escape", CallbackEscapePass.name);
    try std.testing.expectEqual(PassKind.analysis, CallbackEscapePass.kind);
}

test "isCgoBoundary - cgo patterns" {
    try std.testing.expect(isCgoBoundary("_cgo_cfunction_wrapper"));
    try std.testing.expect(isCgoBoundary("_Cfunc_process"));
    try std.testing.expect(isCgoBoundary("C.process"));
    try std.testing.expect(isCgoBoundary("C.malloc"));
    try std.testing.expect(!isCgoBoundary("my_function"));
    try std.testing.expect(!isCgoBoundary("runtime.main"));
}

test "isGoSafetyFunction - KeepAlive detection" {
    try std.testing.expect(isGoSafetyFunction("runtime.KeepAlive"));
    try std.testing.expect(isGoSafetyFunction("runtime_Pin"));
    try std.testing.expect(isGoSafetyFunction("runtime_cgocall"));
    try std.testing.expect(!isGoSafetyFunction("malloc"));
    try std.testing.expect(!isGoSafetyFunction("printf"));
}

test "isCBytesPattern - byte conversion detection" {
    try std.testing.expect(isCBytesPattern("C.CBytes"));
    try std.testing.expect(isCBytesPattern("C.GoString"));
    try std.testing.expect(isCBytesPattern("C.GoStringN"));
    try std.testing.expect(!isCBytesPattern("C.malloc"));
    try std.testing.expect(!isCBytesPattern("memcpy"));
}

test "isUnsafePtrConversion - unsafe pointer detection" {
    try std.testing.expect(isUnsafePtrConversion("unsafe.Pointer"));
    try std.testing.expect(isUnsafePtrConversion("some_unsafe.Pointer_func"));
    try std.testing.expect(isUnsafePtrConversion("uintptr_conversion"));
    try std.testing.expect(!isUnsafePtrConversion("malloc"));
    try std.testing.expect(!isUnsafePtrConversion("normal_func"));
}

test "EscapeViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(EscapeViolation.go_pointer_no_keepalive));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(EscapeViolation.cbytes_escape));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(EscapeViolation.unsafeptr_dangling_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(EscapeViolation.malloc_without_free));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(EscapeViolation.free_without_malloc));
}

test "EscapePattern - initialization" {
    const pattern = EscapePattern{
        .violation_type = .go_pointer_no_keepalive,
        .confidence = 0.85,
        .func_name = "test_func",
        .callee_name = "C.process",
        .description = "missing KeepAlive",
    };
    try std.testing.expectEqual(EscapeViolation.go_pointer_no_keepalive, pattern.violation_type);
    try std.testing.approxApproxEqAbs(@as(f32, 0.85), pattern.confidence, 0.01);
    try std.testing.expectEqualStrings("test_func", pattern.func_name);
}

test "EscapeStats - initialization" {
    const stats = EscapeStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.keepalive_missing);
    try std.testing.expectEqual(@as(u32, 0), stats.cbytes_escapes);
}

test "EscapeStats - tracking" {
    var stats = EscapeStats{};
    stats.total_functions_analyzed = 15;
    stats.go_cgo_boundaries_found = 5;
    stats.keepalive_missing = 3;
    stats.cbytes_escapes = 2;
    stats.unsafeptr_risks = 4;
    stats.malloc_leaks = 1;
    stats.free_orphans = 1;

    try std.testing.expectEqual(@as(u32, 15), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 5), stats.go_cgo_boundaries_found);
    try std.testing.expectEqual(@as(u32, 11), stats.keepalive_missing + stats.cbytes_escapes +
        stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans);
}
