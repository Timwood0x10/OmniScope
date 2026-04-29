const std = @import("std");

/// Risk category for FFI boundary analysis.
pub const RiskKind = enum {
    command_exec,
    unchecked_copy,
    format_string,
    allocator,
    deallocator,
    rust_ownership,
    borrow_escaped,
    memory_map,
    file_io,
    network_io,
    go_cgo_alloc,
    zig_allocator,
    cpp_allocator,
    dynamic_loading,
    jni,
    python_c_api,
    signal_handler,
    thread_mgmt,
    process_mgmt,
    /// P2-1: Functions returning pointers to static buffers (ctime, strerror, etc.)
    static_buffer,
};

/// Severity level for risk assessment.
pub const Severity = enum(u8) {
    low = 1,
    medium = 2,
    high = 3,
    critical = 4,

    /// Convert severity to string for display
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }
};

/// Match type for function name patterns.
pub const MatchType = enum {
    exact,
    contains,
    suffix,
};

/// Semantic rule for a function.
pub const FunctionSemantics = struct {
    pattern: []const u8,
    match_type: MatchType,
    kind: RiskKind,
    severity: Severity,
    consumes_ownership: bool,
    transfers_ownership: bool,
    requires_null_check: bool,
    requires_taint_check: bool,
    description: []const u8,
};
