const std = @import("std");
const types = @import("types.zig");

pub const signal_handler_functions = [_]types.FunctionSemantics{
    .{ .pattern = "signal", .match_type = .exact, .kind = .signal_handler, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Set signal handler - only async-signal-safe functions allowed in handler" },
    .{ .pattern = "sigaction", .match_type = .exact, .kind = .signal_handler, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Set signal handler with options - preferred over signal()" },
    .{ .pattern = "sigprocmask", .match_type = .exact, .kind = .signal_handler, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Change signal mask - block/unblock signals" },
    .{ .pattern = "sigwait", .match_type = .exact, .kind = .signal_handler, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Wait for signal - requires blocked signals" },
    .{ .pattern = "sigsuspend", .match_type = .exact, .kind = .signal_handler, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Atomically change signal mask and wait - temporary mask change" },
};

pub const thread_mgmt_functions = [_]types.FunctionSemantics{
    .{ .pattern = "pthread_create", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Create new thread - thread must be joined or detached" },
    .{ .pattern = "pthread_join", .match_type = .exact, .kind = .thread_mgmt, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Wait for thread termination - paired with pthread_create" },
    .{ .pattern = "pthread_detach", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Detach thread - auto-cleanup, cannot pthread_join after" },
    .{ .pattern = "pthread_mutex_lock", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Lock mutex - deadlock risk if not unlocked, double-lock risk" },
    .{ .pattern = "pthread_mutex_unlock", .match_type = .exact, .kind = .thread_mgmt, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Unlock mutex - paired with lock, unlock without lock = UB" },
    .{ .pattern = "pthread_mutex_init", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Initialize mutex - must pthread_mutex_destroy to cleanup" },
    .{ .pattern = "pthread_mutex_destroy", .match_type = .exact, .kind = .thread_mgmt, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Destroy mutex - locked mutex = UB" },
    .{ .pattern = "pthread_cond_wait", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Wait for condition - atomically unlocks mutex, spurious wakeup possible" },
    .{ .pattern = "pthread_cond_signal", .match_type = .exact, .kind = .thread_mgmt, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Signal condition - wake one waiting thread" },
    .{ .pattern = "pthread_cond_broadcast", .match_type = .exact, .kind = .thread_mgmt, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Broadcast condition - wake all waiting threads" },
    .{ .pattern = "pthread_rwlock_rdlock", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Read lock rwlock - multiple readers allowed" },
    .{ .pattern = "pthread_rwlock_wrlock", .match_type = .exact, .kind = .thread_mgmt, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Write lock rwlock - exclusive access" },
    .{ .pattern = "pthread_rwlock_unlock", .match_type = .exact, .kind = .thread_mgmt, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Unlock rwlock - paired with rdlock or wrlock" },
};

pub const process_mgmt_functions = [_]types.FunctionSemantics{
    .{ .pattern = "fork", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Fork process - double-free risk in child before exec" },
    .{ .pattern = "vfork", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Fork with minimal memory - vfork until exec in child" },
    .{ .pattern = "execve", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Execute program - replaces process image, command injection risk" },
    .{ .pattern = "execv", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Execute program (array form) - command injection risk" },
    .{ .pattern = "execl", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Execute program (list form) - command injection risk" },
    .{ .pattern = "execvp", .match_type = .exact, .kind = .process_mgmt, .severity = .critical, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Execute with PATH search - command injection risk" },
    .{ .pattern = "waitpid", .match_type = .exact, .kind = .process_mgmt, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Wait for process termination - consumes zombie process" },
    .{ .pattern = "wait", .match_type = .exact, .kind = .process_mgmt, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Wait for any child - consumes zombie process" },
    .{ .pattern = "kill", .match_type = .exact, .kind = .process_mgmt, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = true, .description = "Send signal to process - privilege escalation risk" },
};

test "posix_thread_reg: signal_handler count" {
    try std.testing.expectEqual(@as(usize, 5), signal_handler_functions.len);
}

test "posix_thread_reg: thread_mgmt count" {
    try std.testing.expectEqual(@as(usize, 13), thread_mgmt_functions.len);
}

test "posix_thread_reg: process_mgmt count" {
    try std.testing.expectEqual(@as(usize, 9), process_mgmt_functions.len);
}

test "posix_thread_reg: pthread_create/join/detach" {
    inline for (thread_mgmt_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "pthread_create")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "pthread_join")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "pthread_detach")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}

test "posix_thread_reg: fork has critical severity" {
    inline for (process_mgmt_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "fork") or std.mem.eql(u8, name, "vfork")) {
            try std.testing.expectEqual(types.Severity.critical, entry.severity);
        }
    }
}

test "posix_thread_reg: mutex lock/unlock pairs" {
    inline for (thread_mgmt_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "pthread_mutex_lock")) {
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "pthread_mutex_unlock")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
        }
    }
}
