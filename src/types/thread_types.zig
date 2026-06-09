//! Thread Crossing Types
//!
//! Type definitions for the Thread Crossing Detector pass.
//! Contains violation types, statistics, and pattern definitions.

const std = @import("std");

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

/// C++ exception-related instructions/functions.
pub const CPP_EXCEPTION_PATTERNS = &[_][]const u8{
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
pub const THREAD_FUNCTIONS = &[_][]const u8{
    "pthread_mutex_lock",
    "pthread_mutex_unlock",
    "pthread_rwlock_rdlock",
    "pthread_rwlock_wrlock",
    "std::mutex::lock",
    "std::unique_lock",
    "std::lock_guard",
};

/// Functions commonly used in signal handlers that are NOT async-signal-safe.
pub const SIGNAL_UNSAFE_FUNCTIONS = &[_][]const u8{
    "malloc",  "free",     "calloc",      "realloc",
    "printf",  "fprintf",  "sprintf",
    // R8-L1 FIX: Replaced duplicate "malloc" with "exit" (also signal-unsafe)
        "exit",
    "syslog",  "getpwuid", "getgrgid",    "strtok",
    "asctime", "ctime",    "std::string",
};

/// Callback-like function name patterns.
pub const CALLBACK_PATTERNS = &[_][]const u8{
    "callback",    "handler",  "on_",      "cb_",
    "_cb",         "listener", "observer", "signal_handler",
    "sig_handler",
};
