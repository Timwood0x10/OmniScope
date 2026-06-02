//! POSIX Syscall Semantic Classification
//!
//! Classifies POSIX syscalls into semantic categories: file, network, memory,
//! process operations. Only memory operations (free/dealloc) participate in
//! free/UAF semantics. File/network/process operations are NOT memory frees.
//!
//! POSIX standard is the authoritative source for syscall behavior.
//!
//! Covers: F3 (4 cross_language_free FP) — unlink() is file deletion, not free
//! Covers: F5 (2 command_injection FP) — execve() needs taint analysis

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Syscall semantic classification
pub const SyscallClass = enum {
    file_operation, // unlink, close, open, rename, symlink, readlink, fcntl
    network_operation, // socket, bind, connect, listen, send, recv
    memory_operation, // free, dealloc, realloc, calloc, mmap, munmap
    process_operation, // fork, vfork, execve, waitpid, kill, exit
    unknown,
};

/// File operation syscalls
const FILE_SYSCALLS = [_][]const u8{
    "unlink",     "unlinkat",
    "close",      "open",
    "openat",     "rename",
    "renameat",   "symlink",
    "symlinkat",  "readlink",
    "readlinkat", "fcntl",
    "fstat",      "fstatat",
    "lstat",      "stat",
    "access",     "faccessat",
    "chmod",      "fchmodat",
    "chown",      "fchownat",
    "lchown",     "truncate",
    "ftruncate",  "link",
    "linkat",     "mkdir",
    "mkdirat",    "rmdir",
    "getcwd",     "chdir",
    "opendir",    "readdir",
    "closedir",
};

/// Network operation syscalls
const NET_SYSCALLS = [_][]const u8{
    "socket",
    "bind",
    "listen",
    "accept",
    "accept4",
    "connect",
    "send",
    "sendto",
    "sendmsg",
    "recv",
    "recvfrom",
    "recvmsg",
    "shutdown",
    "getsockopt",
    "setsockopt",
    "getsockname",
    "getpeername",
    "socketpair",
    "poll",
    "ppoll",
    "select",
    "pselect",
    "epoll_create",
    "epoll_ctl",
    "epoll_wait",
    "kqueue",
    "kevent",
};

/// Memory operation syscalls (the ONLY ones that participate in free/UAF)
const MEM_SYSCALLS = [_][]const u8{
    "free",
    "dealloc",
    "__rust_dealloc",
    "realloc",
    "__rust_realloc",
    "calloc",
    "malloc",
    "__rust_alloc",
    "posix_memalign",
    "aligned_alloc",
    "mmap",
    "munmap",
    "mprotect",
    "mlock",
    "munlock",
};

/// Process operation syscalls
const PROC_SYSCALLS = [_][]const u8{
    "fork",        "vfork",
    "execve",      "execv",
    "execvp",      "execvpe",
    "posix_spawn", "posix_spawnp",
    "wait",        "waitpid",
    "waitid",      "kill",
    "exit",        "_exit",
    "abort",       "getpid",
    "getppid",     "getuid",
    "geteuid",     "getgid",
    "getegid",     "setuid",
    "seteuid",     "setgid",
    "setegid",     "setsid",
    "getpgid",     "setpgid",
    "tcsetpgrp",   "tcgetpgrp",
};

/// Classify a syscall name into a semantic category.
/// Uses substring matching to handle prefixed function names (e.g., Bun__unlink).
pub fn classifySyscall(name: []const u8) SyscallClass {
    // Check memory operations first (most critical for free/UAF)
    for (MEM_SYSCALLS) |mem_name| {
        if (std.mem.eql(u8, name, mem_name)) return .memory_operation;
        // Also check for __rust_alloc variants
        if (std.mem.startsWith(u8, name, "__rust_alloc")) return .memory_operation;
        if (std.mem.startsWith(u8, name, "__rust_dealloc")) return .memory_operation;
    }

    // Check file operations (substring matching for prefixed names like Bun__unlink)
    for (FILE_SYSCALLS) |file_name| {
        if (std.mem.eql(u8, name, file_name)) return .file_operation;
        if (std.mem.indexOf(u8, name, file_name) != null) return .file_operation;
    }

    // Check network operations
    for (NET_SYSCALLS) |net_name| {
        if (std.mem.eql(u8, name, net_name)) return .network_operation;
        if (std.mem.indexOf(u8, name, net_name) != null) return .network_operation;
    }

    // Check process operations
    for (PROC_SYSCALLS) |proc_name| {
        if (std.mem.eql(u8, name, proc_name)) return .process_operation;
        if (std.mem.indexOf(u8, name, proc_name) != null) return .process_operation;
    }

    return .unknown;
}

/// Detect syscall patterns (per-function).
/// Extracted for single-pass merged traversal optimization.
pub fn detectFunction(
    func: c.LLVMValueRef,
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = module;
    _ = diag;
    if (c.LLVMIsDeclaration(func) != 0) return;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (!llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) continue;
            const callee_name = getCalleeName(inst) orelse continue;

            const syscall_class = classifySyscall(callee_name);
            const kind: SemanticKind = switch (syscall_class) {
                .file_operation => .file_operation,
                .network_operation => .network_operation,
                .memory_operation => .raii_drop_release,
                .process_operation => .process_operation,
                .unknown => continue,
            };

            if (syscall_class == .memory_operation) continue;

            try srt.recordResolution(
                @intFromPtr(inst),
                kind,
                0.95,
                "POSIX",
                callee_name,
            );
        }
    }
}

/// Detect syscall patterns and write to SRT.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    var fn_iter = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(fn_iter) != 0) : (fn_iter = c.LLVMGetNextFunction(fn_iter)) {
        try detectFunction(fn_iter, module, srt, diag);
    }
}

/// Get callee name from a call instruction
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst) orelse return null;
    const name_raw = c.LLVMGetValueName(called_val) orelse return null;
    return std.mem.sliceTo(name_raw, 0);
}

/// Check if a syscall is a memory operation (for free/UAF detection)
pub fn isMemorySyscall(name: []const u8) bool {
    return classifySyscall(name) == .memory_operation;
}

/// Check if a syscall is NOT a memory operation (should skip free/UAF detection)
pub fn isNonMemorySyscall(name: []const u8) bool {
    const class = classifySyscall(name);
    return class == .file_operation or class == .network_operation or class == .process_operation;
}
