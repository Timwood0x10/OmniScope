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

/// Hook context passed to semantic analysis hooks.
/// Provides access to the current instruction being analyzed.
/// Uses *anyopaque for the instruction to avoid coupling to LLVM C API.
pub const HookContext = struct {
    /// The instruction being analyzed (opaque pointer, cast to c.LLVMValueRef in hook impl)
    inst: *anyopaque,
    /// The callee function name (if call/invoke instruction)
    callee_name: []const u8,
    /// The opcode of the instruction
    opcode: c_uint,
    /// The detected language of the current function (empty if unknown).
    /// Used by AnalysisHook.run() for target_languages filtering.
    language: []const u8 = "",
};

/// Semantic analysis hook result.
/// Hooks return this to indicate whether they detected an issue.
pub const HookResult = enum {
    /// No issue detected, continue to next hook
    none,
    /// Issue detected, report it and stop further hooks for this instruction
    issue_found,
    /// Instruction suppressed (e.g., known safe pattern), skip remaining hooks
    suppressed,
};

/// A semantic analysis hook that can be registered in the Registry.
/// Hooks are called during FFI boundary analysis to provide language-specific
/// or domain-specific checks beyond the generic pattern matching.
pub const AnalysisHook = struct {
    /// Unique identifier for this hook
    name: []const u8,
    /// Which languages this hook applies to (empty = all languages)
    target_languages: []const []const u8,
    /// The hook function to execute
    fn_ptr: *const fn (ctx: *HookContext) HookResult,

    pub fn run(self: AnalysisHook, ctx: *HookContext) HookResult {
        // Language filtering: if target_languages is specified, only run
        // when the current instruction's language matches one of them.
        if (self.target_languages.len > 0 and ctx.language.len > 0) {
            var matches = false;
            for (self.target_languages) |lang| {
                if (std.mem.eql(u8, lang, ctx.language)) {
                    matches = true;
                    break;
                }
            }
            if (!matches) return .none; // Skip — language doesn't match
        }
        return self.fn_ptr(ctx);
    }
};
