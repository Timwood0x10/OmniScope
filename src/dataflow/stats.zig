const std = @import("std");
const Issue = @import("../diag/issue.zig").Issue;

pub const IssueStats = struct {
    total: usize,
    memory_leak: usize,
    use_after_free: usize,
    double_free: usize,
    ffi_unsafe: usize,
    command_injection: usize,
    buffer_overflow: usize,
    integer_overflow: usize,
    format_string: usize,
    type_mismatch: usize,
    borrow_escape: usize,
    null_dereference: usize,
    invalid_free: usize,
    unchecked_return: usize,
    malloc_unchecked: usize,
    callback_mismatch: usize,
    cross_language_leak: usize,
    cross_language_free: usize,
    static_buffer_misuse: usize,
    data_race: usize,
    thread_safety_violation: usize,
    unknown: usize,
    user_code: usize = 0,
    stdlib_suppressed: usize = 0,
    compiler_ignored: usize = 0,
    third_party: usize = 0,
};

pub const GraphStats = struct {
    node_count: usize,
    edge_count: usize,
    tainted_node_count: usize,
    ffi_boundary_count: usize,
    issue_count: usize,
};

pub fn computeIssueStats(issues: []const Issue) IssueStats {
    var s = IssueStats{
        .total = issues.len,
        .memory_leak = 0,
        .use_after_free = 0,
        .double_free = 0,
        .ffi_unsafe = 0,
        .command_injection = 0,
        .buffer_overflow = 0,
        .integer_overflow = 0,
        .format_string = 0,
        .type_mismatch = 0,
        .borrow_escape = 0,
        .null_dereference = 0,
        .invalid_free = 0,
        .unchecked_return = 0,
        .malloc_unchecked = 0,
        .callback_mismatch = 0,
        .cross_language_leak = 0,
        .cross_language_free = 0,
        .static_buffer_misuse = 0,
        .data_race = 0,
        .thread_safety_violation = 0,
        .unknown = 0,
    };
    for (issues) |issue| {
        switch (issue.kind) {
            .memory_leak, .cross_language_leak => s.memory_leak += 1,
            .use_after_free => s.use_after_free += 1,
            .double_free => s.double_free += 1,
            .ffi_unsafe_call => s.ffi_unsafe += 1,
            .command_injection => s.command_injection += 1,
            .buffer_overflow => s.buffer_overflow += 1,
            .integer_overflow => s.integer_overflow += 1,
            .format_string => s.format_string += 1,
            .type_mismatch, .ffi_type_mismatch => s.type_mismatch += 1,
            .borrow_escape => s.borrow_escape += 1,
            .null_dereference => s.null_dereference += 1,
            .invalid_free => s.invalid_free += 1,
            .unchecked_return => s.unchecked_return += 1,
            .malloc_unchecked => s.malloc_unchecked += 1,
            .callback_signature_mismatch => s.callback_mismatch += 1,
        .callback_ownership_risk => s.callback_mismatch += 1,
        .cross_language_free => s.cross_language_free += 1,
            .static_buffer_misuse => s.static_buffer_misuse += 1,
            .data_race => s.data_race += 1,
            .thread_safety_violation => s.thread_safety_violation += 1,
            .unknown => s.unknown += 1,
        }
        const fn_name = issue.location.func;
        if (inferIsStdlib(fn_name)) {
            s.stdlib_suppressed += 1;
        } else if (inferIsCompilerGenerated(fn_name)) {
            s.compiler_ignored += 1;
        } else if (inferIsThirdParty(fn_name)) {
            s.third_party += 1;
        } else {
            s.user_code += 1;
        }
    }
    return s;
}

pub fn computeGraphStats(
    node_count: usize,
    edge_count: usize,
    tainted_node_count: usize,
    ffi_boundary_count: usize,
    issue_count: usize,
) GraphStats {
    return .{
        .node_count = node_count,
        .edge_count = edge_count,
        .tainted_node_count = tainted_node_count,
        .ffi_boundary_count = ffi_boundary_count,
        .issue_count = issue_count,
    };
}

fn inferIsStdlib(fn_name: []const u8) bool {
    const prefixes = [_][]const u8{
        "std::", "boost::",  "__gnu",    "__cxa_",     "llvm.",
        "std.",  "runtime.", "syscall.", "java.lang.",
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, fn_name, p)) return true;
    }
    return false;
}

fn inferIsCompilerGenerated(fn_name: []const u8) bool {
    const prefixes = [_][]const u8{
        "__",              "_Z",        "_GLOBAL__",           ".omp.",
        "zig_assert_fail", "zig_panic", "zig_generic_resolve", "llvm.dbg",
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, fn_name, p)) return true;
    }
    return false;
}

fn inferIsThirdParty(fn_name: []const u8) bool {
    const prefixes = [_][]const u8{
        "C.",         "_cgo_",   "_Cfunc_", "Java_", "JNI_",
        "crosscall2", "PyInit_", "Python_",
    };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, fn_name, p)) return true;
    }
    return false;
}
