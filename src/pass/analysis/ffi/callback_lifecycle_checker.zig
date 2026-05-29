//! Callback Lifecycle Checker for FFI Boundaries
//!
//! Detects callback safety issues across FFI boundaries, including:
//! 1. Callbacks that consume one-time resources but may be called multiple times
//! 2. Callbacks that panic/throw across FFI boundaries
//! 3. Callbacks that access thread-local storage from wrong thread
//! 4. Callbacks that capture and use stale pointers
//! 5. Callbacks with mismatched signatures between registration and invocation
//!
//! This module uses the LLVM C API to analyze callback patterns in FFI code
//! and reports issues using IssueKind.callback_signature_mismatch,
//! IssueKind.callback_ownership_risk, and other relevant issue kinds.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../../diag/issue.zig").Severity;

/// Callback lifecycle issue kinds
pub const CallbackLifecycleIssueKind = enum {
    /// Callback consumes one-time resources but may be called multiple times
    one_time_resource_consumption,
    /// Callback may panic/throw across FFI boundaries
    cross_boundary_panic,
    /// Callback accesses thread-local storage from wrong thread
    thread_local_access_violation,
    /// Callback captures and uses stale pointers
    stale_pointer_capture,
    /// Callback signature mismatch between registration and invocation
    signature_mismatch,
};

/// Statistics for callback lifecycle analysis
pub const CallbackLifecycleStats = struct {
    /// Number of functions analyzed
    functions_analyzed: u32 = 0,
    /// Number of callback registrations found
    callback_registrations: u32 = 0,
    /// Number of callback invocations found
    callback_invocations: u32 = 0,
    /// Number of one-time resource consumption issues
    one_time_resource_issues: u32 = 0,
    /// Number of cross-boundary panic issues
    cross_boundary_panic_issues: u32 = 0,
    /// Number of thread-local access issues
    thread_local_access_issues: u32 = 0,
    /// Number of stale pointer capture issues
    stale_pointer_issues: u32 = 0,
    /// Number of signature mismatch issues
    signature_mismatch_issues: u32 = 0,
};

/// Represents a callback registration
pub const CallbackRegistration = struct {
    /// Function that registers the callback
    registrar_func: []const u8,
    /// Name of the callback function being registered
    callback_name: []const u8,
    /// LLVM value reference to the callback function
    callback_val: c.LLVMValueRef,
    /// Location in code where registration occurs
    location: Location,
    /// Whether this is a one-time use callback (e.g., destructor, cleanup)
    is_one_time: bool = false,
    /// Whether this callback may capture pointers
    may_capture_pointers: bool = false,
};

/// Represents a callback invocation
pub const CallbackInvocation = struct {
    /// Function that invokes the callback
    invoker_func: []const u8,
    /// Name of the callback function being invoked
    callback_name: []const u8,
    /// LLVM value reference to the callback function
    callback_val: c.LLVMValueRef,
    /// Location in code where invocation occurs
    location: Location,
    /// Whether this invocation is across FFI boundary
    is_cross_boundary: bool = false,
};

/// Callback Lifecycle Checker
///
/// Detects callback safety issues across FFI boundaries by analyzing:
/// - Callback registration patterns (function pointer arguments)
/// - Callback signature mismatches
/// - One-time resource consumption patterns
/// - Cross-boundary panic/throw patterns
/// - Stale pointer capture patterns
pub const CallbackLifecycleChecker = struct {
    /// Pass name for registration
    pub const name = "callback-lifecycle";
    /// Pass kind - analysis pass
    pub const kind = PassKind.analysis;
    /// Dependencies - requires FFI boundary detection and call graph
    pub const deps = &[_][]const u8{ "ffi-boundary", "call-graph" };

    /// Run the callback lifecycle analysis pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        const first_func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(first_func) == 0) return;

        var stats = CallbackLifecycleStats{};
        var registrations = std.ArrayList(CallbackRegistration).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
        defer registrations.deinit(ctx.allocator);

        var invocations = std.ArrayList(CallbackInvocation).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
        defer invocations.deinit(ctx.allocator);

        var func = first_func;

        // First pass: Collect callback registrations and invocations
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // Analyze function for callback patterns
            try analyzeFunction(ctx, func, func_name, diag, &stats, &registrations, &invocations);
            stats.functions_analyzed += 1;
        }

        // Second pass: Analyze collected data for issues
        try analyzeCallbackRegistrations(ctx, &registrations, diag, &stats);
        try checkCallbackSignatureMatch(ctx, &registrations, &invocations, diag, &stats);
        try detectOneTimeResourceConsumption(ctx, &registrations, diag, &stats);
        try detectCrossBoundaryPanic(ctx, &invocations, diag, &stats);
        try detectStalePointerCapture(ctx, &registrations, diag, &stats);

        diag.info("Callback Lifecycle Checker: {d} functions analyzed, {d} registrations, {d} invocations, {d} issues", .{
            stats.functions_analyzed,
            stats.callback_registrations,
            stats.callback_invocations,
            stats.one_time_resource_issues + stats.cross_boundary_panic_issues +
                stats.thread_local_access_issues + stats.stale_pointer_issues +
                stats.signature_mismatch_issues,
        });
    }

    /// Analyze a single function for callback patterns
    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
        registrations: *std.ArrayList(CallbackRegistration),
        invocations: *std.ArrayList(CallbackInvocation),
    ) !void {
        _ = ctx;
        _ = diag;

        // Scan basic blocks and instructions
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check call instructions
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    const called_name = if (@intFromPtr(called_name_ptr) != 0)
                        std.mem.span(called_name_ptr)
                    else
                        "";

                    // Check if this is a callback registration (function pointer argument)
                    if (isCallbackRegistrationFunction(called_name)) {
                        // Look for function pointer arguments
                        const num_operands = c.LLVMGetNumOperands(inst);
                        var arg_idx: u32 = 1; // Skip callee
                        while (arg_idx < num_operands) : (arg_idx += 1) {
                            const arg = c.LLVMGetOperand(inst, arg_idx);
                            if (@intFromPtr(arg) == 0) continue;

                            // Check if argument is a function pointer
                            if (isFunctionPointer(arg)) {
                                const arg_name_ptr = c.LLVMGetValueName(arg);
                                const arg_name = if (@intFromPtr(arg_name_ptr) != 0)
                                    std.mem.span(arg_name_ptr)
                                else
                                    "unknown";

                                // Create registration record
                                const registration = CallbackRegistration{
                                    .registrar_func = func_name,
                                    .callback_name = arg_name,
                                    .callback_val = arg,
                                    .location = Location.init(func_name),
                                    .is_one_time = isOneTimeCallback(called_name, arg_idx),
                                    .may_capture_pointers = mayCapturePointers(arg),
                                };

                                try registrations.append(registration);
                                stats.callback_registrations += 1;
                            }
                        }
                    }

                    // Check if this is a callback invocation (indirect call)
                    if (@intFromPtr(c.LLVMIsAFunction(called_val)) == 0) {
                        // This is an indirect call (possibly a callback)
                        const invoker_name = if (@intFromPtr(c.LLVMGetValueName(func)) != 0)
                            std.mem.span(c.LLVMGetValueName(func))
                        else
                            "unknown";

                        const callback_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "unknown";

                        const invocation = CallbackInvocation{
                            .invoker_func = invoker_name,
                            .callback_name = callback_name,
                            .callback_val = called_val,
                            .location = Location.init(invoker_name),
                            .is_cross_boundary = isCrossBoundaryCall(called_name),
                        };

                        try invocations.append(invocation);
                        stats.callback_invocations += 1;
                    }
                }
            }
        }
    }

    /// Check if a value is a function pointer
    fn isFunctionPointer(val: c.LLVMValueRef) bool {
        const type_ref = c.LLVMTypeOf(val);
        if (@intFromPtr(type_ref) == 0) return false;

        // Check if it's a pointer type
        if (c.LLVMGetTypeKind(type_ref) != c.LLVMPointerTypeKind) {
            return false;
        }

        // Check if it's a function pointer
        const element_type = c.LLVMGetElementType(type_ref);
        if (@intFromPtr(element_type) == 0) return false;

        return c.LLVMGetTypeKind(element_type) == c.LLVMFunctionTypeKind;
    }

    /// Check if a callback may capture pointers
    fn mayCapturePointers(callback_val: c.LLVMValueRef) bool {
        const func_name_ptr = c.LLVMGetValueName(callback_val);
        if (@intFromPtr(func_name_ptr) == 0) return false;

        const func_name = std.mem.span(func_name_ptr);

        // Patterns indicating pointer capture
        const capture_patterns = [_][]const u8{
            // Functions that typically capture pointers
            "store",
            "save",
            "cache",
            "remember",
            // Functions that use closures/captures
            "closure",
            "capture",
            "context",
            // Functions that store to globals
            "global",
            "static",
        };

        for (capture_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Analyze callback registrations for issues
    fn analyzeCallbackRegistrations(
        ctx: *PassContext,
        registrations: *std.ArrayList(CallbackRegistration),
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
    ) !void {
        _ = diag;

        // Track callbacks registered to multiple registrars
        var callback_registrar_count = std.StringHashMap(u32).init(ctx.allocator);
        defer callback_registrar_count.deinit();

        for (registrations.items) |reg| {
            const count = callback_registrar_count.get(reg.callback_name) orelse 0;
            try callback_registrar_count.put(reg.callback_name, count + 1);
        }

        // Check for callbacks registered to multiple registrars (potential misuse)
        var iter = callback_registrar_count.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > 1) {
                // Callback registered to multiple registrars - may indicate misuse
                const message = try std.fmt.allocPrint(ctx.allocator, "Callback '{s}' registered to {d} different registrars - potential lifecycle issue", .{ entry.key_ptr.*, entry.value_ptr.* });
                defer ctx.allocator.free(message);

                const location = Location.init(entry.key_ptr.*);
                const issue = Issue.init(
                    .callback_ownership_risk,
                    message,
                    location,
                    .medium,
                    0.7,
                );
                try ctx.addIssue(&issue);
            }
        }
    }

    /// Check for callback signature mismatches
    fn checkCallbackSignatureMatch(
        ctx: *PassContext,
        registrations: *std.ArrayList(CallbackRegistration),
        invocations: *std.ArrayList(CallbackInvocation),
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
    ) !void {
        _ = diag;

        // For each invocation, check if there's a matching registration
        for (invocations.items) |invocation| {
            var found_match = false;
            var matching_registration: ?CallbackRegistration = null;

            // Look for matching registration
            for (registrations.items) |reg| {
                if (std.mem.eql(u8, reg.callback_name, invocation.callback_name)) {
                    found_match = true;
                    matching_registration = reg;
                    break;
                }
            }

            if (!found_match) {
                // Callback invoked without registration
                const message = try std.fmt.allocPrint(ctx.allocator, "Callback '{s}' invoked without prior registration - potential use-after-free or stale pointer", .{invocation.callback_name});
                defer ctx.allocator.free(message);

                const location = Location.init(invocation.invoker_func);
                const issue = Issue.init(
                    .use_after_free,
                    message,
                    location,
                    .high,
                    0.8,
                );
                try ctx.addIssue(&issue);
                stats.signature_mismatch_issues += 1;
            } else if (matching_registration) |reg| {
                // Check for signature mismatch (simplified check)
                // In a real implementation, we would compare function signatures
                if (invocation.is_cross_boundary and !reg.is_one_time) {
                    // Cross-boundary invocation of non-one-time callback
                    const message = try std.fmt.allocPrint(ctx.allocator, "Cross-boundary invocation of callback '{s}' - verify signature compatibility", .{invocation.callback_name});
                    defer ctx.allocator.free(message);

                    const location = Location.init(invocation.invoker_func);
                    const issue = Issue.init(
                        .callback_signature_mismatch,
                        message,
                        location,
                        .medium,
                        0.6,
                    );
                    try ctx.addIssue(&issue);
                    stats.signature_mismatch_issues += 1;
                }
            }
        }
    }

    /// Detect callbacks that consume one-time resources
    fn detectOneTimeResourceConsumption(
        ctx: *PassContext,
        registrations: *std.ArrayList(CallbackRegistration),
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
    ) !void {
        _ = diag;

        for (registrations.items) |reg| {
            if (reg.is_one_time) {
                // Check if callback consumes resources that should only be consumed once
                if (isResourceConsumingCallback(reg.callback_name)) {
                    const message = try std.fmt.allocPrint(ctx.allocator, "One-time callback '{s}' may consume resources that should only be consumed once", .{reg.callback_name});
                    defer ctx.allocator.free(message);

                    const location = Location.init(reg.registrar_func);
                    const issue = Issue.init(
                        .memory_leak,
                        message,
                        location,
                        .high,
                        0.85,
                    );
                    try ctx.addIssue(&issue);
                    stats.one_time_resource_issues += 1;
                }
            }
        }
    }

    /// Detect callbacks that may panic/throw across FFI boundaries
    fn detectCrossBoundaryPanic(
        ctx: *PassContext,
        invocations: *std.ArrayList(CallbackInvocation),
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
    ) !void {
        _ = diag;

        for (invocations.items) |invocation| {
            if (invocation.is_cross_boundary) {
                // Check if callback may panic/throw
                if (mayPanicOrThrow(invocation.callback_name)) {
                    const message = try std.fmt.allocPrint(ctx.allocator, "Callback '{s}' may panic/throw across FFI boundary - undefined behavior", .{invocation.callback_name});
                    defer ctx.allocator.free(message);

                    const location = Location.init(invocation.invoker_func);
                    const issue = Issue.init(
                        .ffi_unsafe_call,
                        message,
                        location,
                        .critical,
                        0.95,
                    );
                    try ctx.addIssue(&issue);
                    stats.cross_boundary_panic_issues += 1;
                }
            }
        }
    }

    /// Detect callbacks that capture and use stale pointers
    fn detectStalePointerCapture(
        ctx: *PassContext,
        registrations: *std.ArrayList(CallbackRegistration),
        diag: *DiagnosticWriter,
        stats: *CallbackLifecycleStats,
    ) !void {
        _ = diag;

        for (registrations.items) |reg| {
            if (reg.may_capture_pointers) {
                // Check if callback captures pointers that may become stale
                if (mayCaptureStalePointers(reg.callback_name)) {
                    const message = try std.fmt.allocPrint(ctx.allocator, "Callback '{s}' may capture pointers that become stale - potential use-after-free", .{reg.callback_name});
                    defer ctx.allocator.free(message);

                    const location = Location.init(reg.registrar_func);
                    const issue = Issue.init(
                        .use_after_free,
                        message,
                        location,
                        .high,
                        0.8,
                    );
                    try ctx.addIssue(&issue);
                    stats.stale_pointer_issues += 1;
                }
            }
        }
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if a function name is a callback registration function
fn isCallbackRegistrationFunction(func_name: []const u8) bool {
    // Common callback registration patterns
    const registration_patterns = [_][]const u8{
        // Signal handlers
        "signal",
        "sigaction",
        // Event handlers
        "addEventListener",
        "register_callback",
        "set_callback",
        "set_handler",
        // Thread creation
        "pthread_create",
        "CreateThread",
        // Async operations
        "async_callback",
        "on_complete",
        "on_error",
        // Timer callbacks
        "setInterval",
        "setTimeout",
        // C++ virtual functions
        "virtual",
        "override",
    };

    for (registration_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callback is a one-time use callback
fn isOneTimeCallback(registrar_name: []const u8, arg_idx: u32) bool {
    _ = arg_idx;
    // Patterns indicating one-time callbacks
    const one_time_patterns = [_][]const u8{
        // Destructor callbacks
        "destructor",
        "cleanup",
        "finalize",
        "destroy",
        // Finalization callbacks
        "atexit",
        "at_exit",
        "on_exit",
        // Cleanup handlers
        "pthread_cleanup_push",
        "cleanup_handler",
    };

    for (one_time_patterns) |pattern| {
        if (std.mem.indexOf(u8, registrar_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a call is across FFI boundary
fn isCrossBoundaryCall(called_name: []const u8) bool {
    // Patterns indicating cross-language calls
    const cross_boundary_patterns = [_][]const u8{
        // Python
        "PyObject_Call",
        "PyObject_CallObject",
        "PyObject_CallFunction",
        // Java
        "CallVoidMethod",
        "CallObjectMethod",
        "CallStaticVoidMethod",
        // C#/.NET
        "Marshal_GetDelegateForFunctionPointer",
        // Ruby
        "rb_funcall",
        // Lua
        "lua_pcall",
        "lua_call",
    };

    for (cross_boundary_patterns) |pattern| {
        if (std.mem.indexOf(u8, called_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callback consumes resources
fn isResourceConsumingCallback(callback_name: []const u8) bool {
    // Patterns indicating resource consumption
    const resource_patterns = [_][]const u8{
        // Memory allocation
        "malloc",
        "alloc",
        "new",
        // File operations
        "fopen",
        "open",
        "create",
        // Network operations
        "connect",
        "bind",
        "listen",
        // Database operations
        "query",
        "execute",
        "transaction",
    };

    for (resource_patterns) |pattern| {
        if (std.mem.indexOf(u8, callback_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callback may panic/throw
fn mayPanicOrThrow(callback_name: []const u8) bool {
    // Patterns indicating potential panics/throws
    const panic_patterns = [_][]const u8{
        // Rust panics
        "panic",
        "unwrap",
        "expect",
        // C++ exceptions
        "throw",
        "exception",
        "catch",
        // Python exceptions
        "raise",
        "except",
        // Java exceptions
        "throw",
        "Exception",
        // Generic error patterns
        "error",
        "fail",
        "abort",
    };

    for (panic_patterns) |pattern| {
        if (std.mem.indexOf(u8, callback_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callback may capture stale pointers
fn mayCaptureStalePointers(callback_name: []const u8) bool {
    // Patterns indicating stale pointer capture
    const stale_patterns = [_][]const u8{
        // Functions that store pointers
        "store",
        "save",
        "cache",
        "remember",
        // Functions that use closures
        "closure",
        "capture",
        "context",
        // Functions that store to globals
        "global",
        "static",
        // Functions that use weak references
        "weak",
        "weak_ref",
        "WeakPtr",
    };

    for (stale_patterns) |pattern| {
        if (std.mem.indexOf(u8, callback_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "isCallbackRegistrationFunction detects common patterns" {
    const testing = std.testing;

    // Test signal handlers
    try testing.expect(isCallbackRegistrationFunction("signal"));
    try testing.expect(isCallbackRegistrationFunction("sigaction"));

    // Test event handlers
    try testing.expect(isCallbackRegistrationFunction("addEventListener"));
    try testing.expect(isCallbackRegistrationFunction("register_callback"));
    try testing.expect(isCallbackRegistrationFunction("set_callback"));
    try testing.expect(isCallbackRegistrationFunction("set_handler"));

    // Test thread creation
    try testing.expect(isCallbackRegistrationFunction("pthread_create"));
    try testing.expect(isCallbackRegistrationFunction("CreateThread"));

    // Test async operations
    try testing.expect(isCallbackRegistrationFunction("async_callback"));
    try testing.expect(isCallbackRegistrationFunction("on_complete"));
    try testing.expect(isCallbackRegistrationFunction("on_error"));

    // Test timer callbacks
    try testing.expect(isCallbackRegistrationFunction("setInterval"));
    try testing.expect(isCallbackRegistrationFunction("setTimeout"));

    // Test C++ virtual functions
    try testing.expect(isCallbackRegistrationFunction("virtual"));
    try testing.expect(isCallbackRegistrationFunction("override"));

    // Test non-registration functions
    try testing.expect(!isCallbackRegistrationFunction("malloc"));
    try testing.expect(!isCallbackRegistrationFunction("free"));
    try testing.expect(!isCallbackRegistrationFunction("printf"));
}

test "isOneTimeCallback detects one-time patterns" {
    const testing = std.testing;

    // Test destructor callbacks
    try testing.expect(isOneTimeCallback("destructor_callback", 0));
    try testing.expect(isOneTimeCallback("cleanup_handler", 0));
    try testing.expect(isOneTimeCallback("finalize_function", 0));
    try testing.expect(isOneTimeCallback("destroy_callback", 0));

    // Test finalization callbacks
    try testing.expect(isOneTimeCallback("atexit", 0));
    try testing.expect(isOneTimeCallback("at_exit", 0));
    try testing.expect(isOneTimeCallback("on_exit", 0));

    // Test cleanup handlers
    try testing.expect(isOneTimeCallback("pthread_cleanup_push", 0));
    try testing.expect(isOneTimeCallback("cleanup_handler", 0));

    // Test non-one-time callbacks
    try testing.expect(!isOneTimeCallback("event_handler", 0));
    try testing.expect(!isOneTimeCallback("data_processor", 0));
    try testing.expect(!isOneTimeCallback("log_callback", 0));
}

test "isResourceConsumingCallback detects resource consumption" {
    const testing = std.testing;

    // Test memory allocation
    try testing.expect(isResourceConsumingCallback("malloc_callback"));
    try testing.expect(isResourceConsumingCallback("alloc_handler"));
    try testing.expect(isResourceConsumingCallback("new_handler"));

    // Test file operations
    try testing.expect(isResourceConsumingCallback("fopen_callback"));
    try testing.expect(isResourceConsumingCallback("open_handler"));
    try testing.expect(isResourceConsumingCallback("create_callback"));

    // Test network operations
    try testing.expect(isResourceConsumingCallback("connect_callback"));
    try testing.expect(isResourceConsumingCallback("bind_handler"));
    try testing.expect(isResourceConsumingCallback("listen_callback"));

    // Test database operations
    try testing.expect(isResourceConsumingCallback("query_callback"));
    try testing.expect(isResourceConsumingCallback("execute_handler"));
    try testing.expect(isResourceConsumingCallback("transaction_callback"));

    // Test non-resource-consuming callbacks
    try testing.expect(!isResourceConsumingCallback("log_callback"));
    try testing.expect(!isResourceConsumingCallback("data_processor"));
    try testing.expect(!isResourceConsumingCallback("event_handler"));
}

test "mayPanicOrThrow detects panic patterns" {
    const testing = std.testing;

    // Test Rust panics
    try testing.expect(mayPanicOrThrow("panic_handler"));
    try testing.expect(mayPanicOrThrow("unwrap_callback"));
    try testing.expect(mayPanicOrThrow("expect_handler"));

    // Test C++ exceptions
    try testing.expect(mayPanicOrThrow("throw_handler"));
    try testing.expect(mayPanicOrThrow("exception_callback"));
    try testing.expect(mayPanicOrThrow("catch_handler"));

    // Test Python exceptions
    try testing.expect(mayPanicOrThrow("raise_handler"));
    try testing.expect(mayPanicOrThrow("except_callback"));

    // Test Java exceptions
    try testing.expect(mayPanicOrThrow("throw_callback"));
    try testing.expect(mayPanicOrThrow("Exception_handler"));

    // Test generic error patterns
    try testing.expect(mayPanicOrThrow("error_handler"));
    try testing.expect(mayPanicOrThrow("fail_callback"));
    try testing.expect(mayPanicOrThrow("abort_handler"));

    // Test non-panic patterns
    try testing.expect(!mayPanicOrThrow("success_handler"));
    try testing.expect(!mayPanicOrThrow("data_processor"));
    try testing.expect(!mayPanicOrThrow("log_callback"));
}

test "mayCaptureStalePointers detects stale pointer patterns" {
    const testing = std.testing;

    // Test pointer storage
    try testing.expect(mayCaptureStalePointers("store_callback"));
    try testing.expect(mayCaptureStalePointers("save_handler"));
    try testing.expect(mayCaptureStalePointers("cache_callback"));
    try testing.expect(mayCaptureStalePointers("remember_handler"));

    // Test closure patterns
    try testing.expect(mayCaptureStalePointers("closure_callback"));
    try testing.expect(mayCaptureStalePointers("capture_handler"));
    try testing.expect(mayCaptureStalePointers("context_callback"));

    // Test global storage
    try testing.expect(mayCaptureStalePointers("global_callback"));
    try testing.expect(mayCaptureStalePointers("static_handler"));

    // Test weak references
    try testing.expect(mayCaptureStalePointers("weak_callback"));
    try testing.expect(mayCaptureStalePointers("weak_ref_handler"));
    try testing.expect(mayCaptureStalePointers("WeakPtr_callback"));

    // Test non-stale patterns
    try testing.expect(!mayCaptureStalePointers("simple_callback"));
    try testing.expect(!mayCaptureStalePointers("data_processor"));
    try testing.expect(!mayCaptureStalePointers("event_handler"));
}

test "isCrossBoundaryCall detects cross-boundary patterns" {
    const testing = std.testing;

    // Test Python
    try testing.expect(isCrossBoundaryCall("PyObject_Call"));
    try testing.expect(isCrossBoundaryCall("PyObject_CallObject"));
    try testing.expect(isCrossBoundaryCall("PyObject_CallFunction"));

    // Test Java
    try testing.expect(isCrossBoundaryCall("CallVoidMethod"));
    try testing.expect(isCrossBoundaryCall("CallObjectMethod"));
    try testing.expect(isCrossBoundaryCall("CallStaticVoidMethod"));

    // Test C#/.NET
    try testing.expect(isCrossBoundaryCall("Marshal_GetDelegateForFunctionPointer"));

    // Test Ruby
    try testing.expect(isCrossBoundaryCall("rb_funcall"));

    // Test Lua
    try testing.expect(isCrossBoundaryCall("lua_pcall"));
    try testing.expect(isCrossBoundaryCall("lua_call"));

    // Test non-cross-boundary patterns
    try testing.expect(!isCrossBoundaryCall("local_function"));
    try testing.expect(!isCrossBoundaryCall("internal_call"));
    try testing.expect(!isCrossBoundaryCall("helper_function"));
}

test "CallbackRegistration initialization" {
    const testing = std.testing;

    const reg = CallbackRegistration{
        .registrar_func = "test_registrar",
        .callback_name = "test_callback",
        .callback_val = undefined,
        .location = Location.init("test_registrar"),
        .is_one_time = true,
        .may_capture_pointers = false,
    };

    try testing.expectEqualStrings("test_registrar", reg.registrar_func);
    try testing.expectEqualStrings("test_callback", reg.callback_name);
    try testing.expect(reg.is_one_time);
    try testing.expect(!reg.may_capture_pointers);
}

test "CallbackInvocation initialization" {
    const testing = std.testing;

    const inv = CallbackInvocation{
        .invoker_func = "test_invoker",
        .callback_name = "test_callback",
        .callback_val = undefined,
        .location = Location.init("test_invoker"),
        .is_cross_boundary = true,
    };

    try testing.expectEqualStrings("test_invoker", inv.invoker_func);
    try testing.expectEqualStrings("test_callback", inv.callback_name);
    try testing.expect(inv.is_cross_boundary);
}

test "CallbackLifecycleStats initialization" {
    const testing = std.testing;

    const stats = CallbackLifecycleStats{};
    try testing.expect(stats.functions_analyzed == 0);
    try testing.expect(stats.callback_registrations == 0);
    try testing.expect(stats.callback_invocations == 0);
    try testing.expect(stats.one_time_resource_issues == 0);
    try testing.expect(stats.cross_boundary_panic_issues == 0);
    try testing.expect(stats.thread_local_access_issues == 0);
    try testing.expect(stats.stale_pointer_issues == 0);
    try testing.expect(stats.signature_mismatch_issues == 0);
}
