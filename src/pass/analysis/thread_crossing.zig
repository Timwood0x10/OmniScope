//! Thread Crossing Detector
//!
//! Phase 4.4: Detects thread safety violations at FFI boundaries.
//!
//! Key detection targets:
//! - Exception propagation to extern "C" boundary (undefined behavior in C++)
//! - Shared mutable state without synchronization across FFI
//! - Callback invoked from wrong thread context
//! - Lock order inversion across language boundaries
//! - Signal handler accessing non-signal-safe functions
//!
//! Reference: C++ standard, POSIX threading rules, Go runtime constraints
//!
//! Example bugs detected:
//!
//!   // C++: exception crosses C boundary (UB)
//!   extern "C" void cpp_callback() {
//!       throw std::runtime_error("error");  // UB! Stack unwind across C frame
//!   }
//!
//!   // Go: callback from wrong goroutine
//!   func handleData(data []byte) {
//!       globalState = data  // Race: called from C thread without sync
//!   }

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

/// Types of thread safety violations detected.
pub const ThreadViolation = enum(u8) {
    /// Exception thrown inside extern "C" function
    exception_across_ffi,
    /// Global state modified without lock in callback
    unsynchronized_global_write,
    /// Lock acquired in callback that may deadlock
    callback_lock_risk,
    /// Signal-unsafe function called from signal handler
    signal_unsafe_call,
    /// pthread_create with function that may throw
    thread_fn_exception_risk,
};

/// Statistics for the thread crossing detector.
pub const ThreadStats = struct {
    total_functions_analyzed: u32 = 0,
    callbacks_found: u32 = 0,
    exception_ffi_violations: u32 = 0,
    unsynchronized_writes: u32 = 0,
    lock_risks: u32 = 0,
    signal_unsafe_calls: u32 = 0,

    pub fn formatSummary(self: ThreadStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   THREAD CROSSING DETECTOR SUMMARY  ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:      {d:>8}     ║\n", .{self.total_functions_analyzed});
        try writer.print("║  Callbacks found:         {d:>8}     ║\n", .{self.callbacks_found});
        try writer.print("║  Exception-across-FFI:    {d:>8}     ║\n", .{self.exception_ffi_violations});
        try writer.print("║  Unsynchronized writes:   {d:>8}     ║\n", .{self.unsynchronized_writes});
        try writer.print("║  Lock risks in callbacks: {d:>8}     ║\n", .{self.lock_risks});
        try writer.print("║  Signal-unsafe calls:     {d:>8}     ║\n", .{self.signal_unsafe_calls});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Pattern Detection
// ============================================================================

/// C++ exception-related instructions/functions.
const CPP_EXCEPTION_PATTERNS = &[_][]const u8{
    "__cxa_throw",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_allocate_exception",
    "__cxa_free_exception",
    "_ZSt17__throw_bad_allocv",
    "_ZSt20__throw_length_error",
    "_ZSt20__throw_out_of_range",
    "std::runtime_error",
    "std::exception",
    "throw",
};

/// Threading/synchronization functions.
const THREAD_FUNCTIONS = &[_][]const u8{
    "pthread_mutex_lock",
    "pthread_mutex_unlock",
    "pthread_rwlock_rdlock",
    "pthread_rwlock_wrlock",
    "std::mutex::lock",
    "std::unique_lock",
    "std::lock_guard",
};

/// Functions commonly used in signal handlers that are NOT async-signal-safe.
const SIGNAL_UNSAFE_FUNCTIONS = &[_][]const u8{
    "malloc", "free", "calloc", "realloc",
    "printf", "fprintf", "sprintf",
    "malloc", "syslog",
    "getpwuid", "getgrgid",
    "strtok", "asctime", "ctime",
    "std::string",
};

/// Callback-like function name patterns.
const CALLBACK_PATTERNS = &[_][]const u8{
    "callback", "handler", "on_", "cb_",
    "_cb", "listener", "observer",
    "signal_handler", "sig_handler",
};

/// Check if an instruction or function involves C++ exception handling.
pub fn isExceptionRelated(name: []const u8) bool {
    for (CPP_EXCEPTION_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }
    return false;
}

/// Check if a function is a synchronization primitive.
pub fn isSyncFunction(name: []const u8) bool {
    for (THREAD_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, name, fn_name) != null) return true;
    }
    return false;
}

/// Check if a function is not safe to call from a signal handler.
pub fn isSignalUnsafe(name: []const u8) bool {
    for (SIGNAL_UNSAFE_FUNCTIONS) |fn_name| {
        if (std.mem.eql(u8, name, fn_name)) return true;
    }
    return false;
}

/// Check if a function looks like a callback.
pub fn isCallbackFunction(func_name: []const u8) bool {
    for (CALLBACK_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a function is declared as extern "C" or equivalent.
pub fn isExternCFunction(func_name: []const u8) bool {
    if (func_name.len == 0) return false;

    if (!isMangledName(func_name)) return true;

    return false;
}

/// Check if a name looks like a C++ mangled name.
fn isMangledName(name: []const u8) bool {
    if (name.len < 2) return false;
    return name[0] == '_' and (name[1] == 'Z' or name[1] == 'N');
}

// ============================================================================
// Main Pass
// ============================================================================

/// Thread Crossing Detector Pass
///
/// Analyzes functions for thread safety issues at FFI boundaries:
/// 1. Exceptions propagating across extern "C" boundaries
/// 2. Unsynchronized global state access in callbacks
/// 3. Lock acquisition patterns that may deadlock
/// 4. Signal-unsafe function calls in signal handlers
pub const ThreadCrossingPass = struct {
    pub const name = "thread-crossing";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var stats = ThreadStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            try analyzeFunction(ctx, func, diag, &stats);
        }

        diag.info("ThreadCrossing: analyzed {} funcs, {} callbacks, {} violations found",
            .{ stats.total_functions_analyzed, stats.callbacks_found,
               stats.exception_ffi_violations + stats.unsynchronized_writes +
                   stats.lock_risks + stats.signal_unsafe_calls });
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *ThreadStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        stats.total_functions_analyzed += 1;

        const is_callback = isCallbackFunction(func_name);
        const is_extern_c = isExternCFunction(func_name);
        const is_signal_handler = std.mem.indexOf(u8, func_name, "signal") != null or
            std.mem.indexOf(u8, func_name, "sig_") != null;

        if (is_callback) {
            stats.callbacks_found += 1;
        }

        var has_exception = false;
        var has_global_write = false;
        var has_lock = false;
        var has_signal_unsafe = false;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called) == 0) continue;

                    const name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(name_ptr) == 0) continue;

                    const callee_name = std.mem.span(name_ptr);

                    if (isExceptionRelated(callee_name)) {
                        has_exception = true;
                    }
                    if (isSyncFunction(callee_name)) {
                        has_lock = true;
                    }
                    if (isSignalUnsafe(callee_name)) {
                        has_signal_unsafe = true;
                    }
                }

                if (opcode == c.LLVMStore) {
                    const ptr_op = c.LLVMGetOperand(inst, 1);
                    if (@intFromPtr(ptr_op) != 0) {
                        const ptr_name_ptr = c.LLVMGetValueName(ptr_op);
                        if (@intFromPtr(ptr_name_ptr) != 0) {
                            const ptr_name = std.mem.span(ptr_name_ptr);
                            if (std.mem.startsWith(u8, ptr_name, "@")) {
                                has_global_write = true;
                            }
                        }
                    }
                }
            }
        }

        if (is_extern_c and has_exception) {
            try reportExceptionAcrossFFI(ctx, func_name, diag);
            stats.exception_ffi_violations += 1;
        }

        if (is_callback and has_global_write and !has_lock) {
            try reportUnsyncedWrite(ctx, func_name, diag);
            stats.unsynchronized_writes += 1;
        }

        if (is_callback and has_lock) {
            try reportLockRisk(ctx, func_name, diag);
            stats.lock_risks += 1;
        }

        if (is_signal_handler and has_signal_unsafe) {
            try reportSignalUnsafe(ctx, func_name, diag);
            stats.signal_unsafe_calls += 1;
        }
    }
};

// ============================================================================
// Reporting
// ============================================================================

fn reportExceptionAcrossFFI(
    ctx: *PassContext,
    func_name: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Exception thrown inside extern \"C\" function");
    trace[1] = try makeTrace(ctx.allocator, "{s} is declared as extern \"C\"", .{func_name});
    trace[2] = try makeTrace(ctx.allocator, "C++ exception unwinding across C stack frame is undefined behavior (CWE-698)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Exception thrown in extern \"C\" function {s} - UB when exception crosses C boundary",
        .{func_name},
    );

    const issue = Issue.initWithTrace(
        .command_injection,
        message,
        location,
        .critical,
        0.92,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[EXCEPTION-FFI] {s}", .{func_name});
}

fn reportUnsyncedWrite(
    ctx: *PassContext,
    func_name: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Global state written without synchronization in callback");
    trace[1] = try makeTrace(ctx.allocator, "Callback {s} may be invoked from any thread", .{func_name});
    trace[2] = try makeTrace(ctx.allocator, "Data race possible if callback runs concurrently (CWE-362)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Callback {s} writes global state without lock - potential data race",
        .{func_name},
    );

    const issue = Issue.initWithTrace(
        .buffer_overflow,
        message,
        location,
        .high,
        0.75,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[UNSYNCED-WRITE] {s}", .{func_name});
}

fn reportLockRisk(
    ctx: *PassContext,
    func_name: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Lock acquired inside callback function");
    trace[1] = try makeTrace(ctx.allocator, "Callback {s} may be invoked while holding other locks", .{func_name});
    trace[2] = try makeTrace(ctx.allocator, "Lock order inversion risk may cause deadlock (CWE-807)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Callback {s} acquires lock - deadlock risk if caller holds locks",
        .{func_name},
    );

    const issue = Issue.initWithTrace(
        .buffer_overflow,
        message,
        location,
        .medium,
        0.65,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[LOCK-RISK] {s}", .{func_name});
}

fn reportSignalUnsafe(
    ctx: *PassContext,
    func_name: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Signal-unsafe function called from signal handler");
    trace[1] = try makeTrace(ctx.allocator, "Signal handler {s} must only use async-signal-safe functions", .{func_name});
    trace[2] = try makeTrace(ctx.allocator, "Calling malloc/free/printf in signal handler is undefined behavior (CWE-479)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Signal handler {s} calls non-signal-safe function - undefined behavior on signal delivery",
        .{func_name},
    );

    const issue = Issue.initWithTrace(
        .null_dereference,
        message,
        location,
        .high,
        0.80,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[SIGNAL-UNSAFE] {s}", .{func_name});
}

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "ThreadCrossingPass - name and kind" {
    try std.testing.expectEqualStrings("thread-crossing", ThreadCrossingPass.name);
    try std.testing.expectEqual(PassKind.analysis, ThreadCrossingPass.kind);
}

test "isExceptionRelated - C++ exception patterns" {
    try std.testing.expect(isExceptionRelated("__cxa_throw"));
    try std.testing.expect(isExceptionRelated("__cxa_begin_catch"));
    try std.testing.expect(isExceptionRelated("_ZSt20__throw_out_of_range"));
    try std.testing.expect(isExceptionRelated("std::runtime_error"));
    try std.testing.expect(!isExceptionRelated("malloc"));
    try std.testing.expect(!isExceptionRelated("printf"));
}

test "isSyncFunction - synchronization primitives" {
    try std.testing.expect(isSyncFunction("pthread_mutex_lock"));
    try std.testing.expect(isSyncFunction("pthread_mutex_unlock"));
    try std.testing.expect(isSyncFunction("std::mutex::lock"));
    try std.testing.expect(!isSyncFunction("malloc"));
    try std.testing.expect(!isSyncFunction("memcpy"));
}

test "isSignalUnsafe - unsafe signal functions" {
    try std.testing.expect(isSignalUnsafe("malloc"));
    try std.testing.expect(isSignalUnsafe("printf"));
    try std.testing.expect(isSignalUnsafe("free"));
    try std.testing.expect(!isSignalUnsafe("_exit"));
    try std.testing.expect(!isSignalUnsafe("abort"));
}

test "isCallbackFunction - callback patterns" {
    try std.testing.expect(isCallbackFunction("on_data_received"));
    try std.testing.expect(isCallbackFunction("signal_handler"));
    try std.testing.expect(isCallbackFunction("my_cb"));
    try std.testing.expect(isCallbackFunction("event_listener"));
    try std.testing.expect(!isCallbackFunction("main"));
    try std.testing.expect(!isCallbackFunction("process_data"));
}

test "isExternCFunction - extern C detection" {
    try std.testing.expect(isExternCFunction("c_callback"));
    try std.testing.expect(isExternCFunction("process_data"));
    try std.testing.expect(!isExternCFunction("_Z9processDatav"));
    try std.testing.expect(!isExternCFunction("_ZN4myapp4funcEv"));
}

test "ThreadViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ThreadViolation.exception_across_ffi));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ThreadViolation.unsynchronized_global_write));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ThreadViolation.callback_lock_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ThreadViolation.signal_unsafe_call));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ThreadViolation.thread_fn_exception_risk));
}

test "ThreadStats - initialization" {
    const stats = ThreadStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.callbacks_found);
    try std.testing.expectEqual(@as(u32, 0), stats.exception_ffi_violations);
}

test "ThreadStats - tracking" {
    var stats = ThreadStats{};
    stats.total_functions_analyzed = 50;
    stats.callbacks_found = 8;
    stats.exception_ffi_violations = 2;
    stats.unsynchronized_writes = 3;
    stats.lock_risks = 4;
    stats.signal_unsafe_calls = 1;

    try std.testing.expectEqual(@as(u32, 50), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 10), stats.exception_ffi_violations +
        stats.unsynchronized_writes + stats.lock_risks + stats.signal_unsafe_calls);
}
