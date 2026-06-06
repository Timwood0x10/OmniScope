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
// TODO: Reference from @import("./function_catalogs.zig") (or the shared function catalog
// module) once that module is created, to consolidate duplicate constant definitions.
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
// TODO: Reference from @import("./function_catalogs.zig") once that module is created,
// to consolidate duplicate constant definitions across the codebase.
pub const DANGEROUS_FUNCTIONS = &[_][]const u8{
    // Command execution
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

    // Buffer overflow risks
    "gets",
    "strcpy",
    "strcat",
    "sprintf",
    "vsprintf",
    "asprintf",
    "vasprintf",
    "strncpy",
    "strncat",
    "strdup",
    "strndup",
    "memcpy",
    "memmove",
    "memset",
    "bcopy",
    "bzero",

    // Format string vulnerabilities
    "printf",
    "fprintf",
    "vprintf",
    "vfprintf",
    "dprintf",
    "vdprintf",

    // Input functions (can be dangerous if misused)
    "scanf",
    "fscanf",
    "sscanf",
    "vfscanf",
    "vscanf",
    "vsscanf",

    // Environment and system info
    "getenv",
    "setenv",
    "putenv",
    "clearenv",

    // File operations (can be dangerous)
    "fopen",
    "freopen",
    "open",
    "creat",
    "tmpnam",
    "tempnam",
    "mktemp",
    "mkstemp",
    "mkdtemp",

    // Process control
    "fork",
    "vfork",
    "clone",
    "kill",
    "raise",
    "abort",
    "exit",
    "_exit",
    "_Exit",

    // Dynamic loading
    "dlopen",
    "dlsym",
    "dlclose",
    "dlerror",

    // I/O control
    "ioctl",
    "fcntl",

    // System calls
    "syscall",
    "sysenter",
    "int80", // x86 Linux syscall

    // Memory management (dangerous if misused)
    "mmap",
    "munmap",
    "mprotect",
    "madvise",
    "brk",
    "sbrk",

    // Signal handling
    "signal",
    "sigaction",
    "sigprocmask",
    "sigsuspend",
    "sigpending",

    // Network operations (can be dangerous)
    "connect",
    "bind",
    "listen",
    "accept",
    "send",
    "sendto",
    "sendmsg",
    "setsockopt",
    "getsockopt",

    // Temporary file creation
    "tmpfile",
    "tempnam",

    // Path manipulation
    "realpath",
    "dirname",
    "basename",
};

/// Functions that are considered sources of taint.
/// Taint propagation starts from these functions.
pub const SOURCE_FUNCTIONS = &[_][]const u8{
    // File/stdin reading functions
    "read",
    "readv",
    "recv",
    "recvfrom",
    "recvmsg",
    "gets",
    "fgets", // BUG-05/12 FIX: reads from stdin/file → taint source for command injection
    "getline",
    "fread",
    "getc",
    "getchar",
    "fgetc",
    "gets_s", // Safe version of gets
    "readline", // GNU readline
    "getpass", // Password input

    // Environment and system info functions
    "getenv", // BUG-05 FIX: environment variable → taint source
    "getlogin",
    "gethostname",
    "getcwd",
    "get_current_dir_name",

    // Network/socket functions
    "recv",
    "recvfrom",
    "recvmsg",
    "recvfrom",

    // User input functions
    "scanf",
    "fscanf",
    "sscanf",
    "vfscanf",
    "vscanf",
    "vsscanf",

    // Program arguments
    "main", // argv parameters are user-controlled

    // Random/entropy sources (potentially attacker-controlled)
    "rand",
    "random",
    "rand_r",

    // Signal handlers (attacker may control signals)
    "signal",
    "sigaction",
};

/// Substring patterns that indicate dangerous sink functions.
/// Used to detect potential vulnerability paths.
pub const SINK_PATTERNS = &[_][]const u8{
    // Command execution sinks
    "system", // command execution sink (BUG-05, BUG-12)
    "exec", // exec* family command execution
    "popen", // pipe+command execution sink (BUG-12)
    "posix_spawn", // process creation sink
    "posix_spawnp", // process creation sink

    // Format string sinks
    "sprintf", // format string sink (also buffer overflow risk)
    "snprintf", // format string sink (safer but still risky with tainted input)
    "vsprintf", // format string sink
    "vsnprintf", // format string sink
    "asprintf", // format string sink
    "vasprintf", // format string sink
    "printf", // BUG-07 FIX: format string vulnerability when 1st arg is tainted
    "fprintf", // format string sink
    "vprintf", // format string sink
    "vfprintf", // format string sink
    "dprintf", // format string sink
    "vdprintf", // format string sink

    // Buffer overflow sinks
    "strcpy", // buffer overflow / memory corruption sink
    "strncpy", // buffer overflow sink
    "strcat", // buffer overflow sink
    "strncat", // buffer overflow sink
    "gets", // buffer overflow sink
    "memcpy", // buffer overflow sink
    "memmove", // buffer overflow sink
    "memset", // buffer overflow sink
    "bcopy", // buffer overflow sink
    "bzero", // buffer overflow sink

    // Input sinks (can be dangerous if misused)
    "scanf", // format string / buffer overflow sink
    "fscanf", // format string / buffer overflow sink
    "sscanf", // format string / buffer overflow sink
    "vfscanf", // format string / buffer overflow sink
    "vscanf", // format string / buffer overflow sink
    "vsscanf", // format string / buffer overflow sink

    // File operation sinks
    "fopen", // file access sink
    "freopen", // file access sink
    "open", // file access sink
    "creat", // file access sink

    // Process control sinks
    "fork", // process creation sink
    "vfork", // process creation sink
    "clone", // process creation sink
    "kill", // signal delivery sink
    "raise", // signal delivery sink

    // Dynamic loading sinks
    "dlopen", // dynamic loading sink
    "dlsym", // dynamic loading sink

    // Memory management sinks
    "mmap", // memory mapping sink
    "munmap", // memory mapping sink
    "mprotect", // memory protection sink
    "brk", // heap manipulation sink
    "sbrk", // heap manipulation sink

    // Network sinks
    "connect", // network connection sink
    "bind", // network binding sink
    "send", // network data send sink
    "sendto", // network data send sink
    "sendmsg", // network data send sink
    "setsockopt", // socket option sink

    // Environment sinks
    "setenv", // environment modification sink
    "putenv", // environment modification sink
    "clearenv", // environment modification sink

    // Signal handling sinks
    "signal", // signal handler sink
    "sigaction", // signal handler sink

    // I/O control sinks
    "ioctl", // I/O control sink
    "fcntl", // file control sink

    // System call sinks
    "syscall", // system call sink
    "sysenter", // system call sink
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
