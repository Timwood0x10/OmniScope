//! Unwind Boundary Checker — detects panic/unwind crossing FFI boundaries.
//!
//! When a panic (Rust), exception (C++), or longjmp crosses an FFI boundary
//! (e.g., an extern "C" function panics), the behavior is undefined.
//! This pass scans LLVM IR for such unsafe patterns.
//!
//! Detection targets:
//!   1. Rust `extern "C"` fn calling `panic!()` → calls `__rust_start_panic`
//!   2. C++ `extern "C"` fn that `throw`s → calls `__cxa_throw`
//!   3. Zig extern fn calling `@panic` or `unreachable`
//!   4. `longjmp` across non-C stack frames (skipping destructors)
//!
//! Design: Single-pass, stateless. Each function is analyzed independently.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const isCallOrInvoke = @import("../../../ir/llvm_safe.zig").isCallOrInvoke;

const PassWrapper = @import("../../pass.zig");
const PassContext = PassWrapper.PassContext;
const PassKind = PassWrapper.PassKind;
const DiagnosticWriter = PassWrapper.DiagnosticWriter;
const Pass = PassWrapper.Pass;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const ffi_language_classifier = @import("ffi_language_classifier.zig");

/// Known panic/unwind function names that should never cross an FFI boundary.
const PanicFunctions = struct {
    /// Rust panic entry points.
    const rust_panics = [_][]const u8{
        "__rust_start_panic",
        "panic_unwind",
        "rust_begin_unwind",
        "core::panicking::panic",
    };

    /// C++ exception throwing functions.
    const cpp_exceptions = [_][]const u8{
        "__cxa_throw",
        "_Unwind_RaiseException",
        "__cxa_rethrow",
    };

    /// Zig panic/unreachable functions.
    const zig_panics = [_][]const u8{
        "__zig_panic",
        "std.debug.panic",
        "std.debug.reachedUnreachable",
    };

    /// longjmp family — skips destructors across non-C frames.
    const longjmps = [_][]const u8{
        "longjmp",
        "siglongjmp",
    };

    /// Check if a function name matches any known panic/unwind function.
    fn match(name: []const u8) ?PanicKind {
        for (rust_panics) |p| {
            if (std.mem.indexOf(u8, name, p) != null) return .rust_panic;
        }
        for (cpp_exceptions) |p| {
            if (std.mem.indexOf(u8, name, p) != null) return .cpp_exception;
        }
        for (zig_panics) |p| {
            if (std.mem.indexOf(u8, name, p) != null) return .zig_panic;
        }
        for (longjmps) |p| {
            if (std.mem.indexOf(u8, name, p) != null) return .longjmp;
        }
        return null;
    }
};

/// Classification of the detected unwind function.
const PanicKind = enum {
    rust_panic,
    cpp_exception,
    zig_panic,
    longjmp,

    fn label(self: PanicKind) []const u8 {
        return switch (self) {
            .rust_panic => "Rust panic",
            .cpp_exception => "C++ exception",
            .zig_panic => "Zig panic",
            .longjmp => "longjmp",
        };
    }

    fn severity(self: PanicKind) Severity {
        return switch (self) {
            .rust_panic, .cpp_exception => .critical,
            .zig_panic => .high,
            .longjmp => .high,
        };
    }
};

/// Helper: check if LLVM pointer is non-null.
inline fn llvmNotNull(ptr: anytype) bool {
    return @intFromPtr(ptr) != 0;
}

/// Check if a function definition uses LLVM C calling convention.
/// Note: LLVMCCallConv (value 0) is the default for all C functions,
/// not just `extern "C"` — internal C functions also use it.
fn hasCConvention(func: c.LLVMValueRef) bool {
    const cc = c.LLVMGetFunctionCallConv(func);
    return cc == 0;
}

// Use the Language type from FFIBoundary for consistency.
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;

/// Statistics collected during analysis (for diagnostics).
pub const UnwindStats = struct {
    functions_scanned: u32 = 0,
    issues_found: u32 = 0,
    rust_panics: u32 = 0,
    cpp_exceptions: u32 = 0,
    zig_panics: u32 = 0,
    longjmps: u32 = 0,
};

/// Unwind boundary checker pass.
pub const UnwindBoundaryPass = struct {
    pub const name = "unwind-boundary";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Run the unwind boundary detection pass.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var stats = UnwindStats{};
        const mod = ctx.module.?.raw;

        var func = c.LLVMGetFirstFunction(mod);
        while (llvmNotNull(func)) : (func = c.LLVMGetNextFunction(func)) {
            // Skip declarations — only analyze function definitions.
            if (c.LLVMIsDeclaration(func) != 0) continue;

            stats.functions_scanned += 1;
            const func_name_ptr = c.LLVMGetValueName(func);
            if (!llvmNotNull(func_name_ptr)) continue;
            const func_name = std.mem.span(func_name_ptr);

            // Skip LLVM intrinsics.
            if (std.mem.startsWith(u8, func_name, "llvm.")) continue;

            const caller_lang = ffi_language_classifier.identifyLanguage(func);

            // Scan all instructions in this function.
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (llvmNotNull(bb)) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (llvmNotNull(inst)) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (!isCallOrInvoke(opcode)) continue;

                    const called_val = c.LLVMGetCalledValue(inst);
                    if (!llvmNotNull(called_val)) continue;

                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    if (!llvmNotNull(called_name_ptr)) continue;
                    const called_name = std.mem.span(called_name_ptr);

                    const panic_kind = PanicFunctions.match(called_name) orelse continue;

                    // Found a panic/unwind call. Check if it crosses FFI boundary.
                    try reportIfCrossingBoundary(ctx, diag, func, func_name, caller_lang, called_name, panic_kind, &stats);
                }
            }
        }

        // Summary for verbose logging.
        if (stats.issues_found > 0) {
            diag.warn("UnwindBoundary: {d} issues in {d} functions ({d} rust, {d} cpp, {d} zig, {d} longjmp)", .{
                stats.issues_found,
                stats.functions_scanned,
                stats.rust_panics,
                stats.cpp_exceptions,
                stats.zig_panics,
                stats.longjmps,
            });
        }
    }
};

/// Report an issue when a panic/unwind crosses an FFI boundary.
fn reportIfCrossingBoundary(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    func: c.LLVMValueRef,
    func_name: []const u8,
    caller_lang: Language,
    called_name: []const u8,
    kind: PanicKind,
    stats: *UnwindStats,
) !void {
    // Determine the "source" language of the unwind mechanism.
    const source_lang = switch (kind) {
        .rust_panic => Language.rust,
        .cpp_exception => Language.cpp,
        .zig_panic => Language.zig,
        .longjmp => Language.c,
    };

    // Polarity check:
    //   - If caller_lang matches source_lang AND function is NOT extern "C" → no issue
    //     (same-language panic is fine, e.g., Rust fn calling Rust panic)
    //   - If caller_lang != source_lang → cross-language panic → UB
    //   - If function has C calling convention → extern "C" → UB
    //   - longjmp is always risky in any non-C context

    const is_extern_c = hasCConvention(func);
    const is_same_lang = caller_lang == source_lang;
    const is_longjmp = kind == .longjmp;

    // For longjmp: flag only when not in a pure C context.
    // Pure C functions are expected to use setjmp/longjmp correctly.
    // Note: LLVMCCallConv (0) applies to all C functions, not just extern "C",
    // so we must rely on language classification rather than calling convention.
    if (is_longjmp) {
        if (caller_lang != .c) {
            try emitIssue(ctx, diag, func_name, called_name, kind, stats);
        }
        return;
    }

    // For panic/exception:
    //   - extern "C" function with any panic → UB
    //   - Mixed-language: caller != source → UB
    if (is_extern_c or !is_same_lang) {
        try emitIssue(ctx, diag, func_name, called_name, kind, stats);
    }
}

/// Create and submit an issue for an unwind boundary violation.
fn emitIssue(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    func_name: []const u8,
    called_name: []const u8,
    kind: PanicKind,
    stats: *UnwindStats,
) !void {
    stats.issues_found += 1;
    switch (kind) {
        .rust_panic => stats.rust_panics += 1,
        .cpp_exception => stats.cpp_exceptions += 1,
        .zig_panic => stats.zig_panics += 1,
        .longjmp => stats.longjmps += 1,
    }

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "{s} '{s}' in function '{s}' — crossing FFI boundary is undefined behavior",
        .{ kind.label(), called_name, func_name },
    );
    defer ctx.allocator.free(message);

    const location = Location.init(func_name);
    const issue = Issue.init(
        .ffi_unsafe_call,
        message,
        location,
        kind.severity(),
        0.95,
    );
    try ctx.addIssue(&issue);

    diag.err("UnwindBoundary: {s} in {s} calls {s} across FFI boundary", .{
        kind.label(),
        func_name,
        called_name,
    });
}

comptime {
    _ = Pass(UnwindBoundaryPass);
}

// ============================================================================
// Tests
// ============================================================================

test "UnwindBoundaryPass - pass interface validation" {
    try std.testing.expectEqualStrings("unwind-boundary", UnwindBoundaryPass.name);
    try std.testing.expectEqual(PassKind.analysis, UnwindBoundaryPass.kind);
    try std.testing.expect(UnwindBoundaryPass.deps.len == 0);
}

test "PanicFunctions.match - rust panic detection" {
    try std.testing.expect(PanicFunctions.match("__rust_start_panic") != null);
    try std.testing.expect(PanicFunctions.match("panic_unwind") != null);
    try std.testing.expect(PanicFunctions.match("rust_begin_unwind") != null);

    const result = PanicFunctions.match("__rust_start_panic").?;
    try std.testing.expectEqual(PanicKind.rust_panic, result);
}

test "PanicFunctions.match - cpp exception detection" {
    try std.testing.expect(PanicFunctions.match("__cxa_throw") != null);
    try std.testing.expect(PanicFunctions.match("_Unwind_RaiseException") != null);
    try std.testing.expect(PanicFunctions.match("__cxa_rethrow") != null);

    const result = PanicFunctions.match("__cxa_throw").?;
    try std.testing.expectEqual(PanicKind.cpp_exception, result);
}

test "PanicFunctions.match - zig panic detection" {
    try std.testing.expect(PanicFunctions.match("__zig_panic") != null);
    try std.testing.expect(PanicFunctions.match("std.debug.panic") != null);

    const result = PanicFunctions.match("__zig_panic").?;
    try std.testing.expectEqual(PanicKind.zig_panic, result);
}

test "PanicFunctions.match - longjmp detection" {
    try std.testing.expect(PanicFunctions.match("longjmp") != null);
    try std.testing.expect(PanicFunctions.match("siglongjmp") != null);

    const result = PanicFunctions.match("longjmp").?;
    try std.testing.expectEqual(PanicKind.longjmp, result);
}

test "PanicFunctions.match - non-panic function returns null" {
    try std.testing.expect(PanicFunctions.match("malloc") == null);
    try std.testing.expect(PanicFunctions.match("free") == null);
    try std.testing.expect(PanicFunctions.match("printf") == null);
    try std.testing.expect(PanicFunctions.match("") == null);
}

test "PanicKind.label - human-readable labels" {
    try std.testing.expectEqualStrings("Rust panic", PanicKind.rust_panic.label());
    try std.testing.expectEqualStrings("C++ exception", PanicKind.cpp_exception.label());
    try std.testing.expectEqualStrings("Zig panic", PanicKind.zig_panic.label());
    try std.testing.expectEqualStrings("longjmp", PanicKind.longjmp.label());
}

test "PanicKind.severity - severity levels" {
    try std.testing.expectEqual(Severity.critical, PanicKind.rust_panic.severity());
    try std.testing.expectEqual(Severity.critical, PanicKind.cpp_exception.severity());
    try std.testing.expectEqual(Severity.high, PanicKind.zig_panic.severity());
    try std.testing.expectEqual(Severity.high, PanicKind.longjmp.severity());
}

test "UnwindStats - default initialization" {
    const stats = UnwindStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.functions_scanned);
    try std.testing.expectEqual(@as(u32, 0), stats.issues_found);
    try std.testing.expectEqual(@as(u32, 0), stats.rust_panics);
    try std.testing.expectEqual(@as(u32, 0), stats.cpp_exceptions);
    try std.testing.expectEqual(@as(u32, 0), stats.zig_panics);
    try std.testing.expectEqual(@as(u32, 0), stats.longjmps);
}
