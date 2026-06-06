//! FFI Precision Filtering — Multi-layer FFI match to issue conversion
//!
//! Extracted from main.zig: ffiMatchToIssue, calculateFFIConfidence,
//! all secondary signal functions, and related types.

const std = @import("std");
const log = std.log;
const OmniScope = @import("OmniScope");
const call_graph = OmniScope.cross_lang;
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Location = OmniScope.diag.Location;
const Severity = OmniScope.diag.Severity;

/// Classify FFI vulnerability type based on function name patterns.
pub const FFIVulnType = enum {
    command_injection,
    buffer_overflow,
    format_string,
    control_flow,
    generic,
};

// Secondary signal types for FFI vulnerability detection
const SecondarySignal = enum {
    type_mismatch,
    memory_safety_risk,
    lifetime_issue,
    trust_boundary_violation,
    missing_validation,
    unchecked_return,
};

/// Check for type mismatch between FFI function declaration and definition.
fn hasTypeMismatchSignal(match: *const call_graph.FFIMatch) bool {
    if (match.declare_func == null or match.define_func == null) {
        return false;
    }
    const func_name = match.name;
    const type_unsafe_patterns = [_][]const u8{
        "void*",     "char*",    "int*", "handle_t", "size_t",
        "uintptr_t", "intptr_t", "long", "unsigned",
    };
    for (type_unsafe_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check for memory safety risks in the FFI function.
fn hasMemorySafetyRisk(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const unsafe_mem_patterns = [_][]const u8{
        "malloc",  "free",    "realloc", "calloc",
        "memcpy",  "memmove", "memset",  "strncpy",
        "strncat",
    };
    for (unsafe_mem_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            const safe_wrappers = [_][]const u8{
                "safe_malloc", "checked_alloc", "bounded_copy",
            };
            var is_safe_wrapper = false;
            for (safe_wrappers) |safe| {
                if (std.mem.indexOf(u8, func_name, safe) != null) {
                    is_safe_wrapper = true;
                    break;
                }
            }
            if (!is_safe_wrapper) {
                return true;
            }
        }
    }
    return false;
}

/// Check for Rust-specific lifetime issues at FFI boundary.
fn hasLifetimeIssue(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const rust_lifetime_patterns = [_][]const u8{
        "into_raw",          "from_raw",    "as_ptr",
        "Box::new",          "Vec::as_ptr", "String::as_ptr",
        "CString::into_raw",
    };
    for (rust_lifetime_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if this FFI call crosses a trust boundary (untrusted input → FFI).
fn hasTrustBoundaryViolation(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const trust_boundary_indicators = [_][]const u8{
        "user",     "input",     "argv",    "env",
        "request",  "socket",    "network", "http",
        "url",      "query",     "form",    "post",
        "get_",     "param",     "arg",     "client",
        "external", "untrusted", "remote",
    };
    for (trust_boundary_indicators) |indicator| {
        if (std.mem.indexOf(u8, func_name, indicator) != null) {
            return true;
        }
    }
    return false;
}

/// Check if the caller context lacks validation for the FFI call.
fn hasMissingValidation(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const validation_patterns = [_][]const u8{
        "validate", "sanitize", "escape", "check",
        "verify",   "filter",   "clean",  "bounds",
        "safe",     "guard",
    };
    var has_validation = false;
    for (validation_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            has_validation = true;
            break;
        }
    }
    if (!has_validation and func_name.len > 4) {
        const risky_prefixes = [_][]const u8{
            "wrap",    "call",   "invoke", "exec", "run", "do_",
            "process", "handle", "parse",
        };
        for (risky_prefixes) |prefix| {
            if (std.mem.indexOf(u8, func_name, prefix) != null) {
                return true;
            }
        }
    }
    return false;
}

/// Check if the FFI function returns a value that should be checked.
fn hasUncheckedReturn(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const must_check_patterns = [_][]const u8{
        "malloc",   "calloc",   "realloc",
        "fopen",    "fread",    "fwrite",
        "socket",   "connect",  "accept",
        "send",     "recv",     "pthread_create",
        "sem_open", "shm_open", "mmap",
    };
    for (must_check_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern) or
            std.mem.endsWith(u8, func_name, pattern))
        {
            return true;
        }
    }
    return false;
}

/// Count secondary danger signals for an FFI match.
pub fn countSecondarySignals(match: *const call_graph.FFIMatch) u32 {
    var signal_count: u32 = 0;
    if (hasTypeMismatchSignal(match)) signal_count += 1;
    if (hasMemorySafetyRisk(match)) signal_count += 1;
    if (hasLifetimeIssue(match)) signal_count += 1;
    if (hasTrustBoundaryViolation(match)) signal_count += 1;
    if (hasMissingValidation(match)) signal_count += 1;
    if (hasUncheckedReturn(match)) signal_count += 1;
    return signal_count;
}

/// Calculate dynamic confidence based on secondary signals.
pub fn calculateFFIConfidence(signal_count: u32, vuln_type: FFIVulnType) f32 {
    var base_confidence: f32 = 0.5;
    const type_mismatch_weight: f32 = 0.15;
    const memory_safety_weight: f32 = 0.12;
    const lifetime_weight: f32 = 0.10;
    const trust_boundary_weight: f32 = 0.14;
    const missing_validation_weight: f32 = 0.08;
    const unchecked_return_weight: f32 = 0.09;

    const avg_signal_weight = (type_mismatch_weight + memory_safety_weight +
        lifetime_weight + trust_boundary_weight + missing_validation_weight +
        unchecked_return_weight) / 6.0;
    base_confidence += @as(f32, @floatFromInt(signal_count)) * avg_signal_weight;

    switch (vuln_type) {
        .command_injection => base_confidence += 0.15,
        .buffer_overflow => base_confidence += 0.10,
        .format_string => base_confidence += 0.10,
        .control_flow => base_confidence += 0.05,
        .generic => {},
    }
    if (base_confidence > 0.95) base_confidence = 0.95;
    return base_confidence;
}

/// Classify FFI vulnerability type based on function name patterns.
pub fn classifyFFIVulnType(func_name: []const u8) FFIVulnType {
    if (std.mem.indexOf(u8, func_name, "system") != null or
        std.mem.indexOf(u8, func_name, "exec") != null or
        std.mem.indexOf(u8, func_name, "popen") != null)
    {
        return .command_injection;
    }
    if (std.mem.indexOf(u8, func_name, "strcpy") != null or
        std.mem.indexOf(u8, func_name, "strcat") != null or
        std.mem.indexOf(u8, func_name, "gets") != null or
        std.mem.indexOf(u8, func_name, "sprintf") != null)
    {
        return .buffer_overflow;
    }
    if (std.mem.indexOf(u8, func_name, "printf") != null or
        std.mem.indexOf(u8, func_name, "fprintf") != null or
        std.mem.indexOf(u8, func_name, "sprintf") != null or
        std.mem.indexOf(u8, func_name, "vprintf") != null)
    {
        return .format_string;
    }
    if (std.mem.indexOf(u8, func_name, "setjmp") != null or
        std.mem.indexOf(u8, func_name, "longjmp") != null)
    {
        return .control_flow;
    }
    return .generic;
}

/// Check if an FFI match is a dangerous pattern.
pub fn isDangerousFFIPattern(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    const command_patterns = [_][]const u8{
        "system", "popen",  "exec",   "execve",  "execvp",      "execv",
        "execl",  "execlp", "execle", "fexecve", "posix_spawn", "posix_spawnp",
    };
    const buffer_patterns = [_][]const u8{
        "strcpy", "strcat", "gets", "sprintf", "vsprintf",
    };
    const format_patterns = [_][]const u8{
        "vprintf", "vfprintf", "vsprintf", "vsnprintf", "vsscanf", "vfscanf",
    };
    const control_patterns = [_][]const u8{
        "setjmp", "longjmp", "sigsetjmp", "siglongjmp",
    };
    const dynamic_patterns = [_][]const u8{
        "dlopen", "dlsym", "dlclose",
    };

    const all_patterns = command_patterns ++ buffer_patterns ++ format_patterns ++ control_patterns ++ dynamic_patterns;
    for (all_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) return true;
        if (std.mem.endsWith(u8, func_name, pattern) or
            std.mem.startsWith(u8, func_name, pattern))
        {
            return true;
        }
    }
    return false;
}

/// Whitelist check for known-safe FFI patterns.
pub fn isWhitelistedFFI(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;
    const stdlib_prefixes = [_][]const u8{
        "sqlite3Mem", "sqlite3Db", "proxy",     "conch",      "lock",
        "uv__",       "uv_",       "__rust_",   "std::",      "Py_DEBUG",
        "_debug",     "_Py_debug", "JNI_debug", "_jni_debug", "debug_",
        "log_",       "trace_",    "diag_",     "dump_",
    };
    for (stdlib_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
    }

    const safe_patterns = [_][]const u8{
        "safe", "check", "validate", "init", "finalize",
        "get_", "set_",  "is_",      "has_", "count",
        "size",
    };
    for (safe_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            if (!isDangerousFFIPattern(match)) return true;
        }
    }
    return false;
}

/// Build detailed FFI issue message with signal information.
fn buildFFIIssueMessage(
    match: *const call_graph.FFIMatch,
    vuln_type: FFIVulnType,
    signal_count: u32,
    confidence: f32,
) []const u8 {
    _ = match;
    const vuln_desc = switch (vuln_type) {
        .command_injection => "Command injection vulnerability",
        .buffer_overflow => "Buffer overflow vulnerability",
        .format_string => "Format string vulnerability",
        .control_flow => "Control flow violation (setjmp/longjmp)",
        .generic => "FFI safety violation",
    };
    _ = signal_count;
    _ = confidence;
    return vuln_desc;
}

/// Calculate severity level based on confidence score.
fn calculateFFISeverity(confidence: f32) Severity {
    if (confidence >= 0.9) return .critical;
    if (confidence >= 0.8) return .high;
    if (confidence >= 0.7) return .medium;
    return .low;
}

/// Convert an FFI match to an issue with multi-layer precision filtering.
pub fn ffiMatchToIssue(match: *const call_graph.FFIMatch) ?Issue {
    if (isWhitelistedFFI(match)) {
        log.debug("FFI-SKIP [WHITELIST]: {s}", .{match.name});
        return null;
    }

    const vuln_type = classifyFFIVulnType(match.name);
    const signal_count = countSecondarySignals(match);

    const min_signals: u4 = switch (vuln_type) {
        .command_injection => 0,
        .buffer_overflow => 0,
        .format_string => 1,
        .control_flow => 1,
        .generic => 2,
    };
    if (signal_count < min_signals) {
        log.debug("FFI-SKIP [NO-SIGNALS]: {s} — only {d} signals (need {d})", .{
            match.name, signal_count, min_signals,
        });
        return null;
    }

    const confidence = calculateFFIConfidence(signal_count, vuln_type);

    const min_confidence: f32 = switch (vuln_type) {
        .command_injection => 0.70,
        .buffer_overflow => 0.70,
        .format_string => 0.75,
        .control_flow => 0.75,
        .generic => 0.80,
    };
    if (confidence < min_confidence) {
        log.debug("FFI-SKIP [LOW-CONF]: {s} confidence={d:.2} < {d:.2} (signals={d})", .{
            match.name, confidence, min_confidence, signal_count,
        });
        return null;
    }

    const message = buildFFIIssueMessage(match, vuln_type, signal_count, confidence);
    return Issue.init(
        .ffi_unsafe_call,
        message,
        Location.init(match.name),
        calculateFFISeverity(confidence),
        confidence,
    );
}

/// Convert IssueKind to GraphKind for visualization.
pub fn issueToGraphKind(kind: IssueKind) @import("visual/graph_visualizer.zig").GraphKind {
    return switch (kind) {
        .double_free => .double_free,
        .use_after_free => .use_after_free,
        .null_dereference => .null_dereference,
        .memory_leak => .memory_leak,
        .buffer_overflow => .buffer_overflow,
        .integer_overflow => .other,
        .ffi_type_mismatch, .type_mismatch => .type_mismatch,
        .ffi_unsafe_call => .ffi_unsafe_call,
        .borrow_escape => .borrow_escape,
        .callback_signature_mismatch, .callback_ownership_risk => .callback_signature_mismatch,
        .invalid_free => .invalid_free,
        .unchecked_return => .unchecked_return,
        .malloc_unchecked => .malloc_unchecked,
        .cross_language_leak => .cross_language_leak,
        .cross_language_free => .cross_language_free,
        .format_string => .format_string,
        .command_injection => .command_injection,
        .write_to_immutable => .write_to_immutable,
        .static_buffer_misuse => .static_buffer_misuse,
        else => .other,
    };
}
