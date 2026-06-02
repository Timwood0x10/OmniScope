//! Error Propagation Tracer
//!
//! Tracks error codes and exceptions across FFI boundaries to detect:
//! 1. Error codes not checked after FFI calls
//! 2. Exceptions/panics crossing FFI boundaries uncaught
//! 3. Error codes from one language misinterpreted in another
//! 4. Resource leaks when errors occur (missing cleanup on error paths)
//! 5. Error propagation through callback chains
//!
//! This module analyzes LLVM IR to identify error handling patterns at FFI
//! boundaries and reports issues when error codes or exceptions may be
//! mismanaged.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");
const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const Location = @import("../../../diag/issue.zig").Location;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const log = @import("../../../common/log.zig");
const rust_whitelist = @import("../../../whitelists/rust_internal.zig");
const allocator_shim = @import("../../../detectors/allocator_shim.zig");

/// Statistics for error propagation analysis
pub const ErrorPropagationStats = struct {
    /// Number of FFI calls analyzed
    ffi_calls_analyzed: u32 = 0,
    /// Number of unchecked error codes detected
    unchecked_errors: u32 = 0,
    /// Number of exception boundary violations
    exception_violations: u32 = 0,
    /// Number of error code misinterpretations
    error_misinterpretations: u32 = 0,
    /// Number of error path resource leaks
    error_path_leaks: u32 = 0,
};

/// Represents an FFI call that may return an error code
pub const FFICallInfo = struct {
    /// Instruction reference
    inst: c.LLVMValueRef,
    /// Name of the called function
    callee_name: []const u8,
    /// Name of the calling function
    caller_name: []const u8,
    /// Language of the callee
    callee_lang: Language,
    /// Whether this function is known to return error codes
    returns_error: bool,
    /// Whether the return value is checked
    return_checked: bool,
};

/// Error patterns for different languages
pub const ErrorPatterns = struct {
    /// C-style error patterns (return -1, NULL, errno)
    pub const c_errors = [_][]const u8{
        "error",     "err",   "errno", "fail",  "failed",
        "invalid",   "bad",   "fault", "abort", "crash",
        "panic",     "fatal", "die",   "exit",  "quit",
        "exception", "throw", "catch", "try",   "finally",
    };

    /// Windows HRESULT patterns
    pub const windows_hresult = [_][]const u8{
        "HRESULT",      "SUCCEEDED",     "FAILED",       "S_OK", "E_FAIL",
        "E_INVALIDARG", "E_OUTOFMEMORY", "E_UNEXPECTED",
    };

    /// POSIX error patterns
    pub const posix_errors = [_][]const u8{
        "strerror", "perror", "errno", "EBADF", "EACCES", "ENOENT",
        "ENOMEM",   "EINVAL", "EIO",   "EPERM", "EAGAIN", "ECHILD",
    };

    /// Rust Result/Option patterns
    pub const rust_result = [_][]const u8{
        "Result",         "Option",            "unwrap",  "expect",   "unwrap_or",
        "unwrap_or_else", "unwrap_or_default", "map_err", "and_then", "or_else",
        "ok",             "err",               "some",    "none",
    };

    /// Go error patterns
    pub const go_error = [_][]const u8{
        "error", "errors.New",     "fmt.Errorf",       "panic",  "recover",
        "defer", "os.ErrNotExist", "os.ErrPermission", "io.EOF",
    };

    /// Java exception patterns
    pub const java_exception = [_][]const u8{
        "Exception",                "Throwable",             "Error",                         "RuntimeException",
        "IOException",              "NullPointerException",  "ClassCastException",            "ArrayIndexOutOfBoundsException",
        "IllegalArgumentException", "IllegalStateException", "UnsupportedOperationException",
    };

    /// Python exception patterns
    pub const python_exception = [_][]const u8{
        "Exception",           "BaseException",       "SystemExit",        "KeyboardInterrupt",
        "GeneratorExit",       "StopIteration",       "ArithmeticError",   "OverflowError",
        "ZeroDivisionError",   "FloatingPointError",  "AttributeError",    "EOFError",
        "ImportError",         "ModuleNotFoundError", "IndexError",        "KeyError",
        "MemoryError",         "NameError",           "UnboundLocalError", "OSError",
        "IOError",             "EnvironmentError",    "EOFError",          "RuntimeError",
        "NotImplementedError", "SyntaxError",         "IndentationError",  "TabError",
        "TypeError",           "ValueError",
    };
};

/// Main error propagation tracer pass
pub const ErrorPropagationTracer = struct {
    pub const name = "error-propagation-tracer";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "ffi-boundary", "call-graph" };

    /// Run the error propagation analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var stats = ErrorPropagationStats{};
        const module = ctx.module.?.raw;

        // Collect all FFI calls
        var ffi_calls = std.ArrayList(FFICallInfo).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
        defer {
            for (ffi_calls.items) |*call_info| {
                ctx.allocator.free(call_info.callee_name);
                ctx.allocator.free(call_info.caller_name);
            }
            ffi_calls.deinit(ctx.allocator);
        }

        try collectFFICalls(ctx, &ffi_calls, module);
        stats.ffi_calls_analyzed = @intCast(ffi_calls.items.len);

        // Language-specific optimization: Skip irrelevant detectors for Rust modules
        // Rust uses Result/? operator instead of C++ exceptions or errno-style error codes,
        // so detectExceptionBoundaryViolations() and detectErrorCodeMisinterpretation()
        // produce no meaningful results for Rust modules.
        const lang = ctx.module_language.language;
        if (lang == .rust) {
            log.info("ErrorPropagationTracer: using Rust-optimized path (skipping exception/errno checks)", .{});

            // Only run meaningful detectors for Rust:
            // 1. detectUncheckedFFICalls(): Still relevant - FFI return values must be checked
            // 2. detectErrorPathLeaks(): Still relevant - resource cleanup on error paths matters
            //
            // Skipped for Rust (target Java/C++/C exception model):
            // - detectExceptionBoundaryViolations(): Rust doesn't use C++ exceptions or landingpad
            // - detectErrorCodeMisinterpretation(): Rust doesn't use errno or HRESULT patterns
            try detectUncheckedFFICalls(ctx, diag, &ffi_calls, &stats);
            try detectErrorPathLeaks(ctx, diag, module, &stats);
        } else {
            // Full detection pipeline for non-Rust languages (C/C++, Zig, Go, etc.)
            try detectUncheckedFFICalls(ctx, diag, &ffi_calls, &stats);
            try detectExceptionBoundaryViolations(ctx, diag, module, &stats);
            try detectErrorCodeMisinterpretation(ctx, diag, &ffi_calls, &stats);
            try detectErrorPathLeaks(ctx, diag, module, &stats);
        }

        diag.info("ErrorPropagationTracer: {d} FFI calls analyzed, {d} unchecked errors, {d} exception violations, {d} misinterpretations, {d} error path leaks", .{
            stats.ffi_calls_analyzed,
            stats.unchecked_errors,
            stats.exception_violations,
            stats.error_misinterpretations,
            stats.error_path_leaks,
        });
    }

    /// Collect all FFI calls from the module
    fn collectFFICalls(
        ctx: *PassContext,
        ffi_calls: *std.ArrayList(FFICallInfo),
        module: c.LLVMModuleRef,
    ) !void {
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // ── RUST INTERNAL WHITELIST: Skip panic/unwind internals entirely ──
            if (rust_whitelist.RustInternalWhitelist.shouldSkipAnalysis(func_name)) {
                log.debug("RUST-INTERNAL-SKIP: {s} — skipping FFI analysis", .{func_name});
                continue;
            }

            // Scan instructions in this function
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // Check if this is an FFI call (external function or different language)
                        if (isFFIFunction(called_name)) {
                            const callee_name_dup = ctx.allocator.dupe(u8, called_name) catch continue;
                            const caller_name_dup = ctx.allocator.dupe(u8, func_name) catch {
                                ctx.allocator.free(callee_name_dup);
                                continue;
                            };

                            const call_info = FFICallInfo{
                                .inst = inst,
                                .callee_name = callee_name_dup,
                                .caller_name = caller_name_dup,
                                .callee_lang = classifyLanguage(called_name),
                                .returns_error = isErrorReturningFunction(called_name),
                                .return_checked = false,
                            };

                            ffi_calls.append(ctx.allocator, call_info) catch {
                                ctx.allocator.free(callee_name_dup);
                                ctx.allocator.free(caller_name_dup);
                            };
                        }
                    }
                }
            }
        }
    }

    /// Detect FFI calls whose return values are not checked
    fn detectUncheckedFFICalls(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        ffi_calls: *std.ArrayList(FFICallInfo),
        stats: *ErrorPropagationStats,
    ) !void {
        for (ffi_calls.items) |*call_info| {
            // Only check functions that are known to return error codes
            if (!call_info.returns_error) continue;

            // ── RUST INTERNAL WHITELIST: Ignore return values of panic/unwind functions ──
            if (rust_whitelist.RustInternalWhitelist.canIgnoreReturnValue(call_info.callee_name)) {
                log.debug("RUST-INTERNAL-IGNORE-RET: {s} — can safely ignore return value", .{
                    call_info.callee_name,
                });
                continue;
            }

            // ── ALLOCATOR SHIM: Don't report allocator vtable as unchecked return ──
            if (allocator_shim.AllocatorShimDetector.isAllocatorShim(call_info.callee_name) == .confirmed_shim) {
                log.debug("ALLOCATOR-SHIM-SUPPRESS: {s} is allocator, not error-returning", .{
                    call_info.callee_name,
                });
                continue;
            }

            // Check if the return value is used (stored, compared, or passed to another function)
            const is_checked = isReturnValueChecked(call_info.inst);

            if (!is_checked) {
                stats.unchecked_errors += 1;

                const message = try std.fmt.allocPrint(ctx.allocator, "Unchecked error code from FFI call: {s}() in {s}", .{ call_info.callee_name, call_info.caller_name });
                defer ctx.allocator.free(message);

                diag.warn("ErrorPropagationTracer: {s}", .{message});

                const location = Location.init(call_info.caller_name);
                const issue = Issue.init(
                    .unchecked_return,
                    message,
                    location,
                    .medium,
                    0.75,
                );
                try ctx.addIssue(&issue);
            }
        }
    }

    /// Detect exceptions/panics crossing FFI boundaries uncaught
    fn detectExceptionBoundaryViolations(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        module: c.LLVMModuleRef,
        stats: *ErrorPropagationStats,
    ) !void {
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // ── RUST INTERNAL WHITELIST: Skip panic/unwind internals ──
            if (rust_whitelist.RustInternalWhitelist.shouldSkipAnalysis(func_name)) {
                log.debug("RUST-INTERNAL-SKIP: {s} — skipping exception analysis", .{func_name});
                continue;
            }

            // Scan instructions in this function
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // Check if this is an exception throwing function
                        if (isExceptionThrowingFunction(called_name)) {
                            // Check if there's a catch handler (landingpad or invoke)
                            const has_handler = hasExceptionHandler(inst, func);

                            if (!has_handler) {
                                stats.exception_violations += 1;

                                const message = try std.fmt.allocPrint(ctx.allocator, "Exception crossing FFI boundary: {s}() throws but no handler in {s}", .{ called_name, func_name });
                                defer ctx.allocator.free(message);

                                diag.warn("ErrorPropagationTracer: {s}", .{message});

                                const location = Location.init(func_name);
                                const issue = Issue.init(
                                    .unchecked_return,
                                    message,
                                    location,
                                    .high,
                                    0.80,
                                );
                                try ctx.addIssue(&issue);
                            }
                        }
                    }
                }
            }
        }
    }

    /// Detect error codes from one language misinterpreted in another
    fn detectErrorCodeMisinterpretation(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        ffi_calls: *std.ArrayList(FFICallInfo),
        stats: *ErrorPropagationStats,
    ) !void {
        for (ffi_calls.items) |call_info| {
            if (!call_info.returns_error) continue;

            // Check if the error code is used in a way that suggests misinterpretation
            const is_misused = checkErrorCodeUsage(call_info.inst, call_info.callee_lang);

            if (is_misused) {
                stats.error_misinterpretations += 1;

                const message = try std.fmt.allocPrint(ctx.allocator, "Potential error code misinterpretation: {s}() from {s} language in {s}", .{ call_info.callee_name, @tagName(call_info.callee_lang), call_info.caller_name });
                defer ctx.allocator.free(message);

                diag.warn("ErrorPropagationTracer: {s}", .{message});

                const location = Location.init(call_info.caller_name);
                const issue = Issue.init(
                    .type_mismatch,
                    message,
                    location,
                    .medium,
                    0.70,
                );
                try ctx.addIssue(&issue);
            }
        }
    }

    /// Detect resource leaks when errors occur (missing cleanup on error paths)
    fn detectErrorPathLeaks(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        module: c.LLVMModuleRef,
        stats: *ErrorPropagationStats,
    ) !void {
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // ── RUST INTERNAL WHITELIST: Skip panic/unwind internals ──
            if (rust_whitelist.RustInternalWhitelist.shouldSkipAnalysis(func_name)) {
                log.debug("RUST-INTERNAL-SKIP: {s} — skipping error path analysis", .{func_name});
                continue;
            }

            // Track allocations in this function
            var allocations = std.ArrayList(c.LLVMValueRef).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
            defer allocations.deinit(ctx.allocator);

            // Track error returns
            var error_returns = std.ArrayList(c.LLVMValueRef).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
            defer error_returns.deinit(ctx.allocator);

            // Scan instructions in this function
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // Track allocations
                        if (isAllocationFunction(called_name)) {
                            try allocations.append(ctx.allocator, inst);
                        }

                        // Track error returns
                        if (isErrorReturningFunction(called_name)) {
                            try error_returns.append(ctx.allocator, inst);
                        }
                    }
                }
            }

            // Check for leaks on error paths
            for (error_returns.items) |error_inst| {
                // Check if allocations made before this error are properly freed
                const has_leak = checkForLeakOnErrorPath(error_inst, allocations.items);

                if (has_leak) {
                    stats.error_path_leaks += 1;

                    const message = try std.fmt.allocPrint(ctx.allocator, "Resource leak on error path in {s}: allocation may not be freed on error", .{func_name});
                    defer ctx.allocator.free(message);

                    diag.warn("ErrorPropagationTracer: {s}", .{message});

                    const location = Location.init(func_name);
                    const issue = Issue.init(
                        .memory_leak,
                        message,
                        location,
                        .high,
                        0.85,
                    );
                    try ctx.addIssue(&issue);
                }
            }
        }
    }
};

/// Check if a function is an FFI function (external or different language)
fn isFFIFunction(func_name: []const u8) bool {
    // Common FFI patterns
    const ffi_patterns = [_][]const u8{
        "extern", "foreign", "ffi",     "native", "dll", "so",   "dylib",
        "c_",     "C_",      "rust_",   "Rust_",  "go_", "Go_",  "java_",
        "Java_",  "python_", "Python_", "py_",    "Py_", "JNI_", "JNI",
    };

    for (ffi_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if a function is known to return error codes
pub fn isErrorReturningFunction(func_name: []const u8) bool {
    // Check for error-related patterns in function name
    for (ErrorPatterns.c_errors) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    for (ErrorPatterns.windows_hresult) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    for (ErrorPatterns.posix_errors) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    // Common error-returning functions
    const error_funcs = [_][]const u8{
        "fopen",    "fclose",   "fread",          "fwrite",       "fseek",              "ftell",
        "malloc",   "calloc",   "realloc",        "free",         "open",               "close",
        "read",     "write",    "lseek",          "socket",       "connect",            "bind",
        "listen",   "accept",   "pthread_create", "pthread_join", "pthread_mutex_lock", "dlopen",
        "dlsym",    "dlclose",  "ioctl",          "fcntl",        "mmap",               "munmap",
        "sem_wait", "sem_post", "sem_init",       "sem_destroy",
    };

    for (error_funcs) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if a function is an exception throwing function
fn isExceptionThrowingFunction(func_name: []const u8) bool {
    // Exception throwing patterns
    const throw_patterns = [_][]const u8{
        "throw",          "raise",         "panic",     "abort",        "exit",           "_exit",
        "longjmp",        "siglongjmp",    "terminate", "unexpected",   "std::terminate", "std::unexpected",
        "__cxa_throw",    "__cxa_rethrow", "panic!",    "unreachable!", "todo!",          "unimplemented!",
        "notImplemented",
    };

    for (throw_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if an allocation function
fn isAllocationFunction(func_name: []const u8) bool {
    const alloc_patterns = [_][]const u8{
        "malloc",       "calloc",         "realloc",         "aligned_alloc", "posix_memalign",
        "mmap",         "VirtualAlloc",   "HeapAlloc",       "new",           "new[]",
        "operator new", "operator new[]", "__rust_alloc",    "alloc::alloc",  "Allocator.alloc",
        "heap_alloc",   "PyMem_Malloc",   "PyObject_Malloc",
    };

    for (alloc_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if the return value of a call is checked
fn isReturnValueChecked(inst: c.LLVMValueRef) bool {
    // Scan forward to see how the return value is used
    var next_inst = c.LLVMGetNextInstruction(inst);
    var scanned: u32 = 0;
    const scan_limit: u32 = 10;

    while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
        next_inst = c.LLVMGetNextInstruction(next_inst);
        scanned += 1;
    }) {
        const opcode = c.LLVMGetInstructionOpcode(next_inst);

        // Store instruction - return value is stored (could be checked later)
        if (opcode == c.LLVMStore) {
            const val_op = c.LLVMGetOperand(next_inst, 0);
            if (@intFromPtr(val_op) == @intFromPtr(inst)) {
                return true; // Value is stored, assume it will be checked
            }
        }

        // Comparison instruction - return value is being compared
        if (opcode == c.LLVMICmp or opcode == c.LLVMFCmp) {
            const num_operands = c.LLVMGetNumOperands(next_inst);
            var i: u32 = 0;
            while (i < num_operands) : (i += 1) {
                const op = c.LLVMGetOperand(next_inst, i);
                if (@intFromPtr(op) == @intFromPtr(inst)) {
                    return true; // Value is being compared
                }
            }
        }

        // Branch instruction - return value is used in conditional
        if (opcode == c.LLVMBr) {
            const num_operands = c.LLVMGetNumOperands(next_inst);
            if (num_operands == 3) { // Conditional branch
                const cond_op = c.LLVMGetOperand(next_inst, 0);
                if (@intFromPtr(cond_op) == @intFromPtr(inst)) {
                    return true; // Value is used as condition
                }
            }
        }

        // Switch instruction - return value is used in switch
        if (opcode == c.LLVMSwitch) {
            const cond_op = c.LLVMGetOperand(next_inst, 0);
            if (@intFromPtr(cond_op) == @intFromPtr(inst)) {
                return true; // Value is used as switch condition
            }
        }
    }

    return false;
}

/// Check if there's an exception handler (landingpad or invoke) for an instruction
fn hasExceptionHandler(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    _ = inst;

    // Check if function has landingpad instructions (exception handling)
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var bb_inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(bb_inst) != 0) : (bb_inst = c.LLVMGetNextInstruction(bb_inst)) {
            // Check for landingpad instruction
            if (@intFromPtr(c.LLVMIsALandingPadInst(bb_inst)) != 0) {
                return true;
            }

            // Check for invoke instruction (which has exception handling)
            const opcode = c.LLVMGetInstructionOpcode(bb_inst);
            if (opcode == c.LLVMInvoke) {
                return true;
            }
        }
    }

    return false;
}

/// Check if an error code is misused
fn checkErrorCodeUsage(inst: c.LLVMValueRef, source_lang: Language) bool {
    // This is a simplified check - in practice, we would analyze how the error code is used
    // For now, we'll check for common misuse patterns

    // Check if the error code is used in a way that suggests misinterpretation
    var next_inst = c.LLVMGetNextInstruction(inst);
    var scanned: u32 = 0;
    const scan_limit: u32 = 10;

    while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
        next_inst = c.LLVMGetNextInstruction(next_inst);
        scanned += 1;
    }) {
        const opcode = c.LLVMGetInstructionOpcode(next_inst);

        // Check for comparison with wrong error code values
        if (opcode == c.LLVMICmp) {
            const num_operands = c.LLVMGetNumOperands(next_inst);
            var i: u32 = 0;
            while (i < num_operands) : (i += 1) {
                const op = c.LLVMGetOperand(next_inst, i);
                if (@intFromPtr(op) == @intFromPtr(inst)) {
                    // Found comparison with error code
                    // Check if the other operand is a suspicious value
                    var other_op_idx: u32 = 0;
                    if (i == 0) {
                        other_op_idx = 1;
                    }
                    if (other_op_idx < num_operands) {
                        const other_op = c.LLVMGetOperand(next_inst, other_op_idx);
                        const const_val = c.LLVMIsAConstantInt(other_op);
                        if (@intFromPtr(const_val) != 0) {
                            const val = c.LLVMConstIntGetZExtValue(const_val);

                            // Check for common misinterpretation patterns
                            if (source_lang == .c and (val == 0 or val == 1)) {
                                // C error codes are often negative, not 0 or 1
                                return true;
                            }
                            if (source_lang == .rust and val == 0) {
                                // Rust Result is Err(...) for errors, not 0
                                return true;
                            }
                        }
                    }
                }
            }
        }
    }

    return false;
}

/// Check for resource leaks on error paths
fn checkForLeakOnErrorPath(
    error_inst: c.LLVMValueRef,
    allocations: []const c.LLVMValueRef,
) bool {
    // This is a simplified check - in practice, we would need to do path-sensitive analysis
    // For now, we'll check if there are allocations that might not be freed on error paths

    // Get the basic block of the error instruction
    const error_bb = c.LLVMGetInstructionParent(error_inst);
    if (@intFromPtr(error_bb) == 0) return false;

    // Check if there are allocations in the same basic block that might leak
    for (allocations) |alloc_inst| {
        const alloc_bb = c.LLVMGetInstructionParent(alloc_inst);
        if (@intFromPtr(alloc_bb) == 0) continue;

        // If allocation is in the same basic block as error, it might leak
        if (@intFromPtr(alloc_bb) == @intFromPtr(error_bb)) {
            // Check if there's a free call after the allocation
            var has_free = false;
            var next_inst = c.LLVMGetNextInstruction(alloc_inst);
            while (@intFromPtr(next_inst) != 0) : (next_inst = c.LLVMGetNextInstruction(next_inst)) {
                const opcode = c.LLVMGetInstructionOpcode(next_inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_val = c.LLVMGetCalledValue(next_inst);
                    if (@intFromPtr(called_val) != 0) {
                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        if (isFreeFunction(called_name)) {
                            has_free = true;
                            break;
                        }
                    }
                }

                // Stop at the error instruction
                if (@intFromPtr(next_inst) == @intFromPtr(error_inst)) {
                    break;
                }
            }

            if (!has_free) {
                return true; // Potential leak
            }
        }
    }

    return false;
}

/// Check if a function is a free function
fn isFreeFunction(func_name: []const u8) bool {
    const free_patterns = [_][]const u8{
        "free",            "munmap",            "VirtualFree",    "HeapFree", "delete",         "delete[]",
        "operator delete", "operator delete[]", "__rust_dealloc", "dealloc",  "Allocator.free", "heap_free",
        "PyMem_Free",      "PyObject_Free",
    };

    for (free_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Classify the language of a function based on its name
fn classifyLanguage(func_name: []const u8) Language {
    // Rust patterns
    if (std.mem.indexOf(u8, func_name, "rust") != null or
        std.mem.indexOf(u8, func_name, "Rust") != null or
        std.mem.indexOf(u8, func_name, "_ZN") != null or
        std.mem.indexOf(u8, func_name, "__rust") != null)
    {
        return .rust;
    }

    // Zig patterns
    if (std.mem.indexOf(u8, func_name, "zig") != null or
        std.mem.indexOf(u8, func_name, "Zig") != null)
    {
        return .zig;
    }

    // C++ patterns
    if (std.mem.indexOf(u8, func_name, "_Z") != null or
        std.mem.indexOf(u8, func_name, "std::") != null or
        std.mem.indexOf(u8, func_name, "operator") != null)
    {
        return .cpp;
    }

    // Go patterns
    if (std.mem.indexOf(u8, func_name, "go.") != null or
        std.mem.indexOf(u8, func_name, "Go.") != null or
        std.mem.indexOf(u8, func_name, "_cgo_") != null)
    {
        return .go;
    }

    // Java patterns
    if (std.mem.indexOf(u8, func_name, "Java_") != null or
        std.mem.indexOf(u8, func_name, "JNI_") != null)
    {
        return .java;
    }

    // Python patterns
    if (std.mem.indexOf(u8, func_name, "Py") != null or
        std.mem.indexOf(u8, func_name, "python") != null)
    {
        return .python;
    }

    // Default to C
    return .c;
}

// ============================================================================
// Tests
// ============================================================================

test "isErrorReturningFunction detects common error functions" {
    // Test C-style error functions
    try std.testing.expect(isErrorReturningFunction("fopen"));
    try std.testing.expect(isErrorReturningFunction("malloc"));
    try std.testing.expect(isErrorReturningFunction("pthread_create"));
    try std.testing.expect(isErrorReturningFunction("socket"));

    // Test functions with "error" in name
    try std.testing.expect(isErrorReturningFunction("check_error"));
    try std.testing.expect(isErrorReturningFunction("handle_error"));
    try std.testing.expect(isErrorReturningFunction("error_handler"));

    // Test POSIX error functions
    try std.testing.expect(isErrorReturningFunction("strerror"));
    try std.testing.expect(isErrorReturningFunction("perror"));

    // Test functions that don't return errors
    try std.testing.expect(!isErrorReturningFunction("printf"));
    try std.testing.expect(!isErrorReturningFunction("strlen"));
    try std.testing.expect(!isErrorReturningFunction("memcpy"));
}

test "isExceptionThrowingFunction detects exception functions" {
    // Test exception throwing functions
    try std.testing.expect(isExceptionThrowingFunction("throw"));
    try std.testing.expect(isExceptionThrowingFunction("raise"));
    try std.testing.expect(isExceptionThrowingFunction("panic"));
    try std.testing.expect(isExceptionThrowingFunction("abort"));
    try std.testing.expect(isExceptionThrowingFunction("exit"));
    try std.testing.expect(isExceptionThrowingFunction("longjmp"));
    try std.testing.expect(isExceptionThrowingFunction("__cxa_throw"));
    try std.testing.expect(isExceptionThrowingFunction("panic!"));
    try std.testing.expect(isExceptionThrowingFunction("unreachable!"));
    try std.testing.expect(isExceptionThrowingFunction("todo!"));

    // Test functions that don't throw exceptions
    try std.testing.expect(!isExceptionThrowingFunction("printf"));
    try std.testing.expect(!isExceptionThrowingFunction("malloc"));
    try std.testing.expect(!isExceptionThrowingFunction("free"));
}

test "classifyLanguage identifies language from function name" {
    // Test Rust patterns
    try std.testing.expectEqual(Language.rust, classifyLanguage("rust_function"));
    try std.testing.expectEqual(Language.rust, classifyLanguage("Rust_function"));
    try std.testing.expectEqual(Language.rust, classifyLanguage("_ZN3foo3barE"));
    try std.testing.expectEqual(Language.rust, classifyLanguage("__rust_alloc"));

    // Test Zig patterns
    try std.testing.expectEqual(Language.zig, classifyLanguage("zig_function"));
    try std.testing.expectEqual(Language.zig, classifyLanguage("Zig_function"));

    // Test C++ patterns
    try std.testing.expectEqual(Language.cpp, classifyLanguage("_Z3foo"));
    try std.testing.expectEqual(Language.cpp, classifyLanguage("std::vector"));
    try std.testing.expectEqual(Language.cpp, classifyLanguage("operator new"));

    // Test Go patterns
    try std.testing.expectEqual(Language.go, classifyLanguage("go.function"));
    try std.testing.expectEqual(Language.go, classifyLanguage("Go.function"));
    try std.testing.expectEqual(Language.go, classifyLanguage("_cgo_func"));

    // Test Java patterns
    try std.testing.expectEqual(Language.java, classifyLanguage("Java_com_example_Class_method"));
    try std.testing.expectEqual(Language.java, classifyLanguage("JNI_CreateJavaVM"));

    // Test Python patterns
    try std.testing.expectEqual(Language.python, classifyLanguage("PyObject_Call"));
    try std.testing.expectEqual(Language.python, classifyLanguage("python_function"));

    // Test C patterns (default)
    try std.testing.expectEqual(Language.c, classifyLanguage("printf"));
    try std.testing.expectEqual(Language.c, classifyLanguage("malloc"));
    try std.testing.expectEqual(Language.c, classifyLanguage("my_function"));
}

test "isFFIFunction detects FFI functions" {
    // Test FFI patterns
    try std.testing.expect(isFFIFunction("extern_function"));
    try std.testing.expect(isFFIFunction("foreign_function"));
    try std.testing.expect(isFFIFunction("ffi_function"));
    try std.testing.expect(isFFIFunction("native_function"));
    try std.testing.expect(isFFIFunction("dll_function"));
    try std.testing.expect(isFFIFunction("so_function"));
    try std.testing.expect(isFFIFunction("dylib_function"));
    try std.testing.expect(isFFIFunction("c_function"));
    try std.testing.expect(isFFIFunction("C_function"));
    try std.testing.expect(isFFIFunction("rust_function"));
    try std.testing.expect(isFFIFunction("Rust_function"));
    try std.testing.expect(isFFIFunction("go_function"));
    try std.testing.expect(isFFIFunction("Go_function"));
    try std.testing.expect(isFFIFunction("java_function"));
    try std.testing.expect(isFFIFunction("Java_function"));
    try std.testing.expect(isFFIFunction("python_function"));
    try std.testing.expect(isFFIFunction("Python_function"));
    try std.testing.expect(isFFIFunction("py_function"));
    try std.testing.expect(isFFIFunction("Py_function"));
    try std.testing.expect(isFFIFunction("JNI_function"));
    try std.testing.expect(isFFIFunction("JNI"));

    // Test non-FFI functions
    try std.testing.expect(!isFFIFunction("printf"));
    try std.testing.expect(!isFFIFunction("malloc"));
    try std.testing.expect(!isFFIFunction("my_function"));
}

test "isAllocationFunction detects allocation functions" {
    // Test allocation functions
    try std.testing.expect(isAllocationFunction("malloc"));
    try std.testing.expect(isAllocationFunction("calloc"));
    try std.testing.expect(isAllocationFunction("realloc"));
    try std.testing.expect(isAllocationFunction("aligned_alloc"));
    try std.testing.expect(isAllocationFunction("posix_memalign"));
    try std.testing.expect(isAllocationFunction("mmap"));
    try std.testing.expect(isAllocationFunction("VirtualAlloc"));
    try std.testing.expect(isAllocationFunction("HeapAlloc"));
    try std.testing.expect(isAllocationFunction("new"));
    try std.testing.expect(isAllocationFunction("new[]"));
    try std.testing.expect(isAllocationFunction("operator new"));
    try std.testing.expect(isAllocationFunction("operator new[]"));
    try std.testing.expect(isAllocationFunction("__rust_alloc"));
    try std.testing.expect(isAllocationFunction("alloc::alloc"));
    try std.testing.expect(isAllocationFunction("Allocator.alloc"));
    try std.testing.expect(isAllocationFunction("heap_alloc"));
    try std.testing.expect(isAllocationFunction("PyMem_Malloc"));
    try std.testing.expect(isAllocationFunction("PyObject_Malloc"));

    // Test non-allocation functions
    try std.testing.expect(!isAllocationFunction("free"));
    try std.testing.expect(!isAllocationFunction("printf"));
    try std.testing.expect(!isAllocationFunction("my_function"));
}

test "isFreeFunction detects free functions" {
    // Test free functions
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("munmap"));
    try std.testing.expect(isFreeFunction("VirtualFree"));
    try std.testing.expect(isFreeFunction("HeapFree"));
    try std.testing.expect(isFreeFunction("delete"));
    try std.testing.expect(isFreeFunction("delete[]"));
    try std.testing.expect(isFreeFunction("operator delete"));
    try std.testing.expect(isFreeFunction("operator delete[]"));
    try std.testing.expect(isFreeFunction("__rust_dealloc"));
    try std.testing.expect(isFreeFunction("dealloc"));
    try std.testing.expect(isFreeFunction("Allocator.free"));
    try std.testing.expect(isFreeFunction("heap_free"));
    try std.testing.expect(isFreeFunction("PyMem_Free"));
    try std.testing.expect(isFreeFunction("PyObject_Free"));

    // Test non-free functions
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("printf"));
    try std.testing.expect(!isFreeFunction("my_function"));
}
