//! Type definitions for Call Graph Analysis module.
//!
//! Extracted from pass/analysis/call_graph.zig for better code organization.
//! Contains pure type definitions, constant arrays, and data structures
//! used by the call graph analysis system.

const std = @import("std");
const log = std.log.scoped(.call_graph_types);
const c = @import("../ir/llvm_raw.zig").c;

/// Classification of function origin in the call graph.
/// Used to determine trust boundaries and FFI transitions.
pub const FunctionKind = enum {
    /// Function defined within the analyzed module.
    internal,
    /// Standard C library function (trusted).
    libc,
    /// Function with unknown origin (potential FFI boundary).
    external_unknown,
};

/// Trusted libc functions (source: config/languages/c.json).
/// Dangerous functions (system, exec, popen) are NOT included — see DANGEROUS_FUNCTIONS.
pub const LIBC_FUNCTIONS = &[_][]const u8{
    "malloc",
    "free",
    "calloc",
    "realloc",
    "read",
    "write",
    "open",
    "close",
    "strlen",
    "strncpy",
    "snprintf",
    "fgets",
    "getline",
    "memcpy",
    "memmove",
    "memset",
    "memcmp",
    "printf",
    "fprintf",
    "puts",
    "fopen",
    "fclose",
    "fread",
    "fwrite",
};

/// List of dangerous functions that should be flagged as security risks.
/// These are treated as FFI boundaries and potential sinks.
pub const DANGEROUS_FUNCTIONS = &[_][]const u8{
    "system",
    "exec",
    "execve",
    "execvp",
    "execv",
    "execl",
    "execlp",
    "execle",
    "fexecve",
    "posix_spawn",
    "posix_spawnp",
    "popen",
    "gets",
    "strcpy",
    "strcat",
    "sprintf",
    "scanf",
    "getenv",
};

/// Functions that are considered sources of taint.
/// Taint propagation starts from these functions.
pub const SOURCE_FUNCTIONS = &[_][]const u8{
    "read",
    "recv",
    "gets",
    "fgets", // BUG-05/12 FIX: reads from stdin/file → taint source for command injection
    "scanf",
    "getenv", // BUG-05 FIX: environment variable → taint source
    "main", // argv parameters are user-controlled
};

/// Substring patterns that indicate dangerous sink functions.
/// Used to detect potential vulnerability paths.
pub const SINK_PATTERNS = &[_][]const u8{
    "system", // command execution sink (BUG-05, BUG-12)
    "exec", // exec* family command execution
    "popen", // pipe+command execution sink (BUG-12)
    "sprintf", // format string sink (also buffer overflow risk)
    "snprintf", // format string sink (safer but still risky with tainted input)
    "printf", // BUG-07 FIX: format string vulnerability when 1st arg is tainted
    "strcpy", // buffer overflow / memory corruption sink
    "strncpy", // buffer overflow sink
};

/// A node in the call graph representing a function.
pub const Node = struct {
    /// Unique identifier for this node.
    id: u32,
    /// Name of the function (owned by this node).
    name: []const u8,
    /// LLVM value reference to the function.
    func_ref: c.LLVMValueRef,
    /// Classification of the function's origin.
    kind: FunctionKind,
    /// Whether this function is external to the module.
    is_external: bool,
    /// Whether this function is reachable from a taint source.
    is_tainted: bool,
    /// ID of the node that tainted this function (null if source).
    tainted_by: ?u32,

    /// Deinitialize the node and free owned memory
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// An edge in the call graph representing a call relationship.
pub const Edge = struct {
    /// ID of the caller function.
    caller: u32,
    /// ID of the callee function.
    callee: u32,
    /// The call instruction (for extracting pointer arguments).
    call_inst: u64,
};
