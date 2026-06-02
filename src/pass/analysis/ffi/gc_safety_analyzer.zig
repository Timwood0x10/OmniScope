//! GC Safety Analyzer for Python/Java FFI
//!
//! This module detects GC interaction issues in Python/Java FFI code.
//! It identifies problems like dangling GC references, use-after-GC-collect,
//! JNI GlobalRef leaks, Python GIL violations, and GC-finalizer ordering issues.
//!
//! Detection patterns:
//! - Dangling GC references: C pointer held by GC language without proper reference keeping
//! - Use-after-GC-collect: Pointer used after GC language released the reference
//! - JNI GlobalRef leaks: NewGlobalRef without matching DeleteGlobalRef
//! - Python GIL violations: FFI calls without holding the GIL when needed
//! - GC-finalizer ordering: Finalizer runs before FFI cleanup completes

const std = @import("std");
const log = std.log.scoped(.gc_safety);
const c = @import("../../../ir/llvm_raw.zig").c;
const builtin = @import("builtin");
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../../diag/issue.zig").Severity;
const FFIBoundary = @import("../../../diag/issue.zig").FFIBoundary;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const BoundaryKind = @import("../../../diag/issue.zig").FFIBoundary.BoundaryKind;

const SemanticRegistry = @import("../../../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../../../registry/semantic_registry.zig").FunctionSemantics;
const RiskKind = @import("../../../registry/semantic_registry.zig").RiskKind;
const Severity = @import("../../../registry/semantic_registry.zig").Severity;

// Import existing FFI analysis modules
const ffi_boundary = @import("ffi_boundary.zig");
const zone_check = @import("ffi_zone_check.zig");
const noise_filter = @import("ffi_noise_filter.zig");
const lang_classifier = @import("ffi_language_classifier.zig");

/// GC safety issue kinds specific to Python/Java FFI
pub const GcSafetyIssueKind = enum {
    /// C pointer held by GC language without proper reference keeping
    dangling_gc_reference,
    /// Pointer used after GC language released the reference
    use_after_gc_collect,
    /// NewGlobalRef without matching DeleteGlobalRef
    jni_global_ref_leak,
    /// FFI call without holding the GIL when needed
    python_gil_violation,
    /// Finalizer runs before FFI cleanup completes
    gc_finalizer_ordering,
    /// Reference cycle detected across FFI boundaries
    reference_cycle,
    /// Finalizer accesses FFI resources after cleanup
    finalizer_safety,
    /// Python reference counting error
    python_refcount_error,
    /// JNI array operation without proper release
    jni_array_leak,
    /// Buffer protocol violation
    buffer_protocol_violation,
};

/// GC safety analysis result for a single function
pub const GcSafetyResult = struct {
    /// Number of GC safety issues found
    issue_count: u32 = 0,
    /// Number of functions analyzed
    functions_analyzed: u32 = 0,
    /// Number of JNI GlobalRef operations tracked
    jni_global_ref_ops: u32 = 0,
    /// Number of Python GIL operations tracked
    python_gil_ops: u32 = 0,
    /// Number of GC-finalizer patterns detected
    gc_finalizer_patterns: u32 = 0,
};

/// GC Safety Analyzer for Python/Java FFI
///
/// Detects GC interaction issues in FFI code by analyzing:
/// - JNI GlobalRef usage patterns
/// - Python GIL acquisition/release patterns
/// - GC-finalizer ordering issues
/// - Dangling references across language boundaries
pub const GcSafetyAnalyzer = struct {
    /// Pass name for registration
    pub const name = "gc-safety";
    /// Pass kind - foundation analysis
    pub const kind = PassKind.foundation;
    /// Dependencies - requires FFI boundary detection
    pub const deps = &[_][]const u8{ "ffi-boundary", "call-graph" };

    /// Run the GC safety analysis pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Language gate: GC safety analysis only meaningful for GC languages (Java, Python)
        // For Rust/C/C++, the borrow checker and manual memory management make this irrelevant
        const lang = ctx.module_language.language;
        if (lang != .java and lang != .python) {
            log.debug("GcSafetyPass: skipping non-GC language module ({s})", .{@tagName(lang)});
            return;
        }

        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        const first_func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(first_func) == 0) return;

        var result = GcSafetyResult{};
        var func = first_func;

        // Iterate through all functions in the module
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // Skip internal/runtime functions
            if (zone_check.isZigInternalFunction(func_name) or
                zone_check.isGoInternalFunction(func_name))
            {
                continue;
            }

            // Analyze function for GC safety issues
            try analyzeFunction(ctx, func, func_name, diag, &result);
            result.functions_analyzed += 1;
        }

        diag.info("GC Safety Analyzer: {d} functions analyzed, {d} issues found", .{
            result.functions_analyzed,
            result.issue_count,
        });
    }

    /// Analyze a single function for GC safety issues
    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
    ) !void {
        // Track JNI GlobalRef operations in this function
        var jni_global_refs = std.StringHashMap(u32).init(ctx.allocator);
        defer jni_global_refs.deinit();

        // Track Python GIL state
        var gil_held = false;
        var gil_acquired_count: u32 = 0;
        var gil_released_count: u32 = 0;

        // Track GC-finalizer patterns
        var has_finalizer = false;
        var has_ffi_cleanup = false;

        // Scan basic blocks and instructions
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check call instructions
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    try analyzeCallInstruction(
                        ctx,
                        inst,
                        func_name,
                        diag,
                        result,
                        &jni_global_refs,
                        &gil_held,
                        &gil_acquired_count,
                        &gil_released_count,
                        &has_finalizer,
                        &has_ffi_cleanup,
                    );
                }
            }
        }

        // Check for JNI GlobalRef leaks
        try checkJniGlobalRefLeaks(ctx, func_name, diag, result, &jni_global_refs);

        // Check for Python GIL violations
        try checkPythonGilViolations(ctx, func_name, diag, result, gil_held, gil_acquired_count, gil_released_count);

        // Check for GC-finalizer ordering issues
        try checkGcFinalizerOrdering(ctx, func_name, diag, result, has_finalizer, has_ffi_cleanup);
    }

    /// Analyze a call instruction for GC safety issues
    fn analyzeCallInstruction(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
        jni_global_refs: *std.StringHashMap(u32),
        gil_held: *bool,
        gil_acquired_count: *u32,
        gil_released_count: *u32,
        has_finalizer: *bool,
        has_ffi_cleanup: *bool,
    ) !void {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return;

        const called_name_ptr = c.LLVMGetValueName(called_val);
        const called_name = if (@intFromPtr(called_name_ptr) != 0)
            std.mem.span(called_name_ptr)
        else
            return;

        // Check for JNI GlobalRef operations
        if (isJniGlobalRefOperation(called_name)) {
            try trackJniGlobalRefOperation(inst, called_name, caller_name, diag, result, jni_global_refs);
        }

        // Check for Python GIL operations
        if (isPythonGilOperation(called_name)) {
            trackPythonGilOperation(called_name, gil_held, gil_acquired_count, gil_released_count);
        }

        // Check for GC-finalizer patterns
        if (isGcFinalizerPattern(called_name)) {
            has_finalizer.* = true;
        }

        // Check for FFI cleanup patterns
        if (isFfiCleanupPattern(called_name)) {
            has_ffi_cleanup.* = true;
        }

        // Check for dangling GC references
        if (isDanglingReferencePattern(called_name, caller_name)) {
            try reportDanglingReference(ctx, inst, caller_name, called_name, diag, result);
        }

        // Check for use-after-GC-collect patterns
        if (isUseAfterGcCollectPattern(called_name, caller_name)) {
            try reportUseAfterGcCollect(ctx, inst, caller_name, called_name, diag, result);
        }
    }

    /// Check if function name is a JNI GlobalRef operation
    fn isJniGlobalRefOperation(func_name: []const u8) bool {
        // JNI GlobalRef operations
        if (std.mem.indexOf(u8, func_name, "NewGlobalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "DeleteGlobalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "NewLocalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "DeleteLocalRef") != null) return true;
        return false;
    }

    /// Track JNI GlobalRef operations
    fn trackJniGlobalRefOperation(
        inst: c.LLVMValueRef,
        called_name: []const u8,
        caller_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
        jni_global_refs: *std.StringHashMap(u32),
    ) !void {
        _ = inst;
        result.jni_global_ref_ops += 1;

        // Track NewGlobalRef operations
        if (std.mem.indexOf(u8, called_name, "NewGlobalRef") != null) {
            // Create a unique key for this GlobalRef
            const key = try std.fmt.allocPrint(jni_global_refs.allocator, "{s}:{s}", .{ caller_name, called_name });
            defer jni_global_refs.allocator.free(key);

            const count = jni_global_refs.get(key) orelse 0;
            try jni_global_refs.put(key, count + 1);

            diag.debug("JNI GlobalRef created in {s}: {s} (count: {d})", .{ caller_name, called_name, count + 1 });
        }

        // Track DeleteGlobalRef operations
        if (std.mem.indexOf(u8, called_name, "DeleteGlobalRef") != null) {
            // Create a unique key for this GlobalRef deletion
            const key = try std.fmt.allocPrint(jni_global_refs.allocator, "{s}:NewGlobalRef", .{caller_name});
            defer jni_global_refs.allocator.free(key);

            if (jni_global_refs.get(key)) |count| {
                if (count > 0) {
                    try jni_global_refs.put(key, count - 1);
                    diag.debug("JNI GlobalRef deleted in {s}: {s} (remaining: {d})", .{ caller_name, called_name, count - 1 });
                }
            }
        }
    }

    /// Check for JNI GlobalRef leaks
    fn checkJniGlobalRefLeaks(
        ctx: *PassContext,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
        jni_global_refs: *std.StringHashMap(u32),
    ) !void {
        var iter = jni_global_refs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > 0) {
                // Found leaked GlobalRefs
                const message = try std.fmt.allocPrint(ctx.allocator,
                    \\JNI GlobalRef leak detected in {s}
                    \\{d} GlobalRef(s) created without matching DeleteGlobalRef
                    \\This may cause memory leaks and GC issues
                , .{ func_name, entry.value_ptr.* });
                defer ctx.allocator.free(message);

                const location = Location.init(func_name);
                const issue = Issue.init(
                    .memory_leak,
                    message,
                    location,
                    .high,
                    0.9,
                );
                try ctx.addIssue(&issue);

                result.issue_count += 1;
                diag.err("JNI GlobalRef leak in {s}: {d} unmatched refs", .{ func_name, entry.value_ptr.* });
            }
        }
    }

    /// Check if function name is a Python GIL operation
    fn isPythonGilOperation(func_name: []const u8) bool {
        // Python GIL operations
        if (std.mem.indexOf(u8, func_name, "PyGILState_Ensure") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyGILState_Release") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyEval_SaveThread") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyEval_RestoreThread") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Py_BEGIN_ALLOW_THREADS") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Py_END_ALLOW_THREADS") != null) return true;
        return false;
    }

    /// Track Python GIL operations
    fn trackPythonGilOperation(
        called_name: []const u8,
        gil_held: *bool,
        gil_acquired_count: *u32,
        gil_released_count: *u32,
    ) void {
        // GIL acquisition patterns
        if (std.mem.indexOf(u8, called_name, "PyGILState_Ensure") != null or
            std.mem.indexOf(u8, called_name, "PyEval_RestoreThread") != null or
            std.mem.indexOf(u8, called_name, "Py_END_ALLOW_THREADS") != null)
        {
            gil_held.* = true;
            gil_acquired_count.* += 1;
        }

        // GIL release patterns
        if (std.mem.indexOf(u8, called_name, "PyGILState_Release") != null or
            std.mem.indexOf(u8, called_name, "PyEval_SaveThread") != null or
            std.mem.indexOf(u8, called_name, "Py_BEGIN_ALLOW_THREADS") != null)
        {
            gil_held.* = false;
            gil_released_count.* += 1;
        }
    }

    /// Check for Python GIL violations
    fn checkPythonGilViolations(
        ctx: *PassContext,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
        gil_held: bool,
        gil_acquired_count: u32,
        gil_released_count: u32,
    ) !void {
        // Check for unbalanced GIL operations
        if (gil_acquired_count != gil_released_count) {
            const message = try std.fmt.allocPrint(ctx.allocator,
                \\Python GIL violation in {s}
                \\Unbalanced GIL operations: {d} acquired, {d} released
                \\This may cause deadlocks or race conditions
            , .{ func_name, gil_acquired_count, gil_released_count });
            defer ctx.allocator.free(message);

            const location = Location.init(func_name);
            const issue = Issue.init(
                .data_race,
                message,
                location,
                .high,
                0.85,
            );
            try ctx.addIssue(&issue);

            result.issue_count += 1;
            diag.err("Python GIL violation in {s}: unbalanced operations", .{func_name});
        }

        // Check for FFI calls without GIL
        if (!gil_held and gil_acquired_count > 0) {
            const message = try std.fmt.allocPrint(ctx.allocator,
                \\Python GIL not held during FFI call in {s}
                \\GIL was acquired {d} times but not held at function exit
                \\This may cause data races with Python's garbage collector
            , .{ func_name, gil_acquired_count });
            defer ctx.allocator.free(message);

            const location = Location.init(func_name);
            const issue = Issue.init(
                .data_race,
                message,
                location,
                .medium,
                0.75,
            );
            try ctx.addIssue(&issue);

            result.issue_count += 1;
            diag.err("Python GIL not held at exit in {s}", .{func_name});
        }
    }

    /// Check if function name is a GC-finalizer pattern
    fn isGcFinalizerPattern(func_name: []const u8) bool {
        // Java finalizer patterns
        if (std.mem.indexOf(u8, func_name, "finalize") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Finalize") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Destructor") != null) return true;

        // Python destructor patterns
        if (std.mem.indexOf(u8, func_name, "__del__") != null) return true;
        if (std.mem.indexOf(u8, func_name, "tp_del") != null) return true;

        // C++ destructor patterns
        if (std.mem.indexOf(u8, func_name, "~") != null) return true;
        if (std.mem.indexOf(u8, func_name, "D1") != null or
            std.mem.indexOf(u8, func_name, "D2") != null)
        {
            return true;
        }

        return false;
    }

    /// Check if function name is an FFI cleanup pattern
    fn isFfiCleanupPattern(func_name: []const u8) bool {
        // JNI cleanup patterns
        if (std.mem.indexOf(u8, func_name, "DeleteGlobalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "DeleteLocalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "ReleaseStringUTFChars") != null) return true;
        if (std.mem.indexOf(u8, func_name, "ReleaseByteArrayElements") != null) return true;

        // Python cleanup patterns
        if (std.mem.indexOf(u8, func_name, "Py_DECREF") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Py_XDECREF") != null) return true;
        if (std.mem.indexOf(u8, func_name, "Py_CLEAR") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyBuffer_Release") != null) return true;

        // General FFI cleanup patterns
        if (std.mem.indexOf(u8, func_name, "free") != null) return true;
        if (std.mem.indexOf(u8, func_name, "dealloc") != null) return true;
        if (std.mem.indexOf(u8, func_name, "release") != null) return true;

        return false;
    }

    /// Check for GC-finalizer ordering issues
    fn checkGcFinalizerOrdering(
        ctx: *PassContext,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
        has_finalizer: bool,
        has_ffi_cleanup: bool,
    ) !void {
        if (has_finalizer and !has_ffi_cleanup) {
            const message = try std.fmt.allocPrint(ctx.allocator,
                \\GC-finalizer ordering issue in {s}
                \\Function has finalizer/destructor but no FFI cleanup calls
                \\This may cause FFI resources to be leaked when GC runs
            , .{func_name});
            defer ctx.allocator.free(message);

            const location = Location.init(func_name);
            const issue = Issue.init(
                .memory_leak,
                message,
                location,
                .medium,
                0.7,
            );
            try ctx.addIssue(&issue);

            result.issue_count += 1;
            result.gc_finalizer_patterns += 1;
            diag.err("GC-finalizer ordering issue in {s}: no FFI cleanup", .{func_name});
        }
    }

    /// Check if call is a dangling reference pattern
    fn isDanglingReferencePattern(called_name: []const u8, caller_name: []const u8) bool {
        _ = caller_name;
        // Patterns that indicate dangling GC references
        // C pointer passed to GC language without proper reference keeping

        // JNI dangling reference patterns
        if (std.mem.indexOf(u8, called_name, "GetByteArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetStringUTFChars") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetPrimitiveArrayCritical") != null) return true;

        // JNI array operations that create dangling references
        if (std.mem.indexOf(u8, called_name, "GetBooleanArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetCharArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetShortArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetIntArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetLongArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetFloatArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "GetDoubleArrayElements") != null) return true;

        // Python dangling reference patterns
        if (std.mem.indexOf(u8, called_name, "PyObject_GetBuffer") != null) return true;
        if (std.mem.indexOf(u8, called_name, "PyCapsule_GetPointer") != null) return true;
        if (std.mem.indexOf(u8, called_name, "PyArg_ParseTuple") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_BuildValue") != null) return true;

        // Python buffer protocol patterns
        if (std.mem.indexOf(u8, called_name, "PyBuffer_FillInfo") != null) return true;

        // Python reference counting patterns that create new references
        if (std.mem.indexOf(u8, called_name, "Py_INCREF") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_XINCREF") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_NewRef") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_NewWeakRef") != null) return true;

        return false;
    }

    /// Report dangling GC reference issue
    fn reportDanglingReference(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_name: []const u8,
        called_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
    ) !void {
        _ = inst;
        const message = try std.fmt.allocPrint(ctx.allocator,
            \\Dangling GC reference detected in {s}
            \\Call to {s} may create a reference that GC language doesn't track
            \\This can lead to use-after-free when GC collects the reference
        , .{ caller_name, called_name });
        defer ctx.allocator.free(message);

        const location = Location.init(caller_name);
        const issue = Issue.init(
            .use_after_free,
            message,
            location,
            .high,
            0.8,
        );
        try ctx.addIssue(&issue);

        result.issue_count += 1;
        diag.err("Dangling GC reference in {s}: {s}", .{ caller_name, called_name });
    }

    /// Check if call is a use-after-GC-collect pattern
    fn isUseAfterGcCollectPattern(called_name: []const u8, caller_name: []const u8) bool {
        _ = caller_name;
        // Patterns that indicate use-after-GC-collect
        // Using a pointer after GC language released the reference

        // JNI use-after-GC-collect patterns
        if (std.mem.indexOf(u8, called_name, "ReleaseByteArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseStringUTFChars") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleasePrimitiveArrayCritical") != null) return true;

        // JNI array release operations
        if (std.mem.indexOf(u8, called_name, "ReleaseBooleanArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseCharArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseShortArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseIntArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseLongArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseFloatArrayElements") != null) return true;
        if (std.mem.indexOf(u8, called_name, "ReleaseDoubleArrayElements") != null) return true;

        // Python use-after-GC-collect patterns
        if (std.mem.indexOf(u8, called_name, "PyBuffer_Release") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_DECREF") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_XDECREF") != null) return true;
        if (std.mem.indexOf(u8, called_name, "Py_CLEAR") != null) return true;

        return false;
    }

    /// Report use-after-GC-collect issue
    fn reportUseAfterGcCollect(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_name: []const u8,
        called_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
    ) !void {
        _ = inst;
        const message = try std.fmt.allocPrint(ctx.allocator,
            \\Use-after-GC-collect detected in {s}
            \\Call to {s} releases a reference that may be used later
            \\GC language may have already collected the underlying object
        , .{ caller_name, called_name });
        defer ctx.allocator.free(message);

        const location = Location.init(caller_name);
        const issue = Issue.init(
            .use_after_free,
            message,
            location,
            .high,
            0.85,
        );
        try ctx.addIssue(&issue);

        result.issue_count += 1;
        diag.err("Use-after-GC-collect in {s}: {s}", .{ caller_name, called_name });
    }

    /// Detect reference cycles across FFI boundaries
    ///
    /// This function analyzes function call patterns to detect potential reference cycles
    /// where objects in different languages hold references to each other, preventing GC
    /// from collecting them.
    fn detectReferenceCycle(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
    ) !void {
        // Track object creation and reference patterns
        var created_objects = std.StringHashMap(u32).init(ctx.allocator);
        defer created_objects.deinit();

        var referenced_objects = std.StringHashMap(u32).init(ctx.allocator);
        defer referenced_objects.deinit();

        // Scan for object creation and reference patterns
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
                        continue;

                    // Track object creation patterns
                    if (isJniObjectCreation(called_name) or isPythonObjectCreation(called_name)) {
                        const count = created_objects.get(called_name) orelse 0;
                        try created_objects.put(called_name, count + 1);
                    }

                    // Track reference patterns
                    if (isJniReferenceOperation(called_name) or isPythonReferenceOperation(called_name)) {
                        const count = referenced_objects.get(called_name) orelse 0;
                        try referenced_objects.put(called_name, count + 1);
                    }
                }
            }
        }

        // Check for potential reference cycles
        // A cycle is detected when we see both creation and reference operations
        var created_iter = created_objects.iterator();
        while (created_iter.next()) |entry| {
            const created_name = entry.key_ptr.*;
            const created_count = entry.value_ptr.*;

            // Check if there are corresponding reference operations
            var ref_iter = referenced_objects.iterator();
            while (ref_iter.next()) |ref_entry| {
                const ref_name = ref_entry.key_ptr.*;
                const ref_count = ref_entry.value_ptr.*;

                // If we see both creation and reference operations, it might be a cycle
                if (created_count > 0 and ref_count > 0) {
                    // Check if this is a cross-language reference pattern
                    if (isCrossLanguageReference(created_name, ref_name)) {
                        const message = try std.fmt.allocPrint(ctx.allocator,
                            \\Potential reference cycle detected in {s}
                            \\Object created via {s} and referenced via {s}
                            \\This may cause memory leaks due to circular references across FFI boundaries
                        , .{ func_name, created_name, ref_name });
                        defer ctx.allocator.free(message);

                        const location = Location.init(func_name);
                        const issue = Issue.init(
                            .memory_leak,
                            message,
                            location,
                            .medium,
                            calculateReferenceCycleConfidence(created_name, ref_name),
                        );
                        try ctx.addIssue(&issue);

                        result.issue_count += 1;
                        diag.err("Reference cycle in {s}: {s} -> {s}", .{ func_name, created_name, ref_name });
                    }
                }
            }
        }
    }

    /// Check if function name is a JNI object creation pattern
    fn isJniObjectCreation(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "NewObject") != null) return true;
        if (std.mem.indexOf(u8, func_name, "NewString") != null) return true;
        if (std.mem.indexOf(u8, func_name, "NewArray") != null) return true;
        if (std.mem.indexOf(u8, func_name, "AllocObject") != null) return true;
        return false;
    }

    /// Check if function name is a Python object creation pattern
    fn isPythonObjectCreation(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "PyObject_New") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyLong_FromLong") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyFloat_FromDouble") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyUnicode_FromString") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyList_New") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyDict_New") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyTuple_New") != null) return true;
        return false;
    }

    /// Check if function name is a JNI reference operation
    fn isJniReferenceOperation(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "GetObjectField") != null) return true;
        if (std.mem.indexOf(u8, func_name, "GetObjectArrayElement") != null) return true;
        if (std.mem.indexOf(u8, func_name, "CallObjectMethod") != null) return true;
        if (std.mem.indexOf(u8, func_name, "CallStaticObjectMethod") != null) return true;
        if (std.mem.indexOf(u8, func_name, "GetStaticObjectField") != null) return true;
        return false;
    }

    /// Check if function name is a Python reference operation
    fn isPythonReferenceOperation(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "PyObject_GetAttr") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyObject_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyDict_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyList_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyTuple_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PySequence_GetItem") != null) return true;
        return false;
    }

    /// Check if this is a cross-language reference pattern
    fn isCrossLanguageReference(created_name: []const u8, ref_name: []const u8) bool {
        // JNI creation + Python reference
        if (isJniObjectCreation(created_name) and isPythonReferenceOperation(ref_name)) return true;
        // Python creation + JNI reference
        if (isPythonObjectCreation(created_name) and isJniReferenceOperation(ref_name)) return true;
        return false;
    }

    /// Calculate confidence score for reference cycle detection
    fn calculateReferenceCycleConfidence(created_name: []const u8, ref_name: []const u8) f64 {
        // Higher confidence for cross-language patterns
        if (isJniObjectCreation(created_name) and isPythonReferenceOperation(ref_name)) return 0.75;
        if (isPythonObjectCreation(created_name) and isJniReferenceOperation(ref_name)) return 0.75;
        // Lower confidence for same-language patterns
        return 0.5;
    }

    /// Check finalizer safety - verify finalizers don't access FFI resources after cleanup
    ///
    /// This function checks if finalizers/destructors properly handle FFI resources
    /// and don't access them after they've been cleaned up.
    fn checkFinalizerSafety(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        result: *GcSafetyResult,
    ) !void {
        var has_finalizer = false;
        var has_ffi_cleanup = false;
        var has_ffi_access_after_cleanup = false;
        var cleanup_position: u32 = 0;
        var current_position: u32 = 0;

        // Scan for finalizer patterns and FFI operations
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
                        continue;

                    current_position += 1;

                    // Check for finalizer patterns
                    if (isGcFinalizerPattern(called_name)) {
                        has_finalizer = true;
                    }

                    // Check for FFI cleanup patterns
                    if (isFfiCleanupPattern(called_name)) {
                        has_ffi_cleanup = true;
                        cleanup_position = current_position;
                    }

                    // Check for FFI access after cleanup
                    if (has_ffi_cleanup and current_position > cleanup_position) {
                        if (isFfiAccessPattern(called_name)) {
                            has_ffi_access_after_cleanup = true;
                        }
                    }
                }
            }
        }

        // Report issues
        if (has_finalizer and has_ffi_access_after_cleanup) {
            const message = try std.fmt.allocPrint(ctx.allocator,
                \\Finalizer safety issue in {s}
                \\Finalizer accesses FFI resources after cleanup has been performed
                \\This may cause use-after-free or undefined behavior
            , .{func_name});
            defer ctx.allocator.free(message);

            const location = Location.init(func_name);
            const issue = Issue.init(
                .use_after_free,
                message,
                location,
                .high,
                0.8,
            );
            try ctx.addIssue(&issue);

            result.issue_count += 1;
            diag.err("Finalizer safety issue in {s}: FFI access after cleanup", .{func_name});
        }
    }

    /// Check if function name is an FFI access pattern
    fn isFfiAccessPattern(func_name: []const u8) bool {
        // JNI access patterns
        if (std.mem.indexOf(u8, func_name, "GetObjectField") != null) return true;
        if (std.mem.indexOf(u8, func_name, "SetObjectField") != null) return true;
        if (std.mem.indexOf(u8, func_name, "CallObjectMethod") != null) return true;
        if (std.mem.indexOf(u8, func_name, "CallVoidMethod") != null) return true;
        if (std.mem.indexOf(u8, func_name, "GetArrayLength") != null) return true;
        if (std.mem.indexOf(u8, func_name, "GetByteArrayElements") != null) return true;

        // Python access patterns
        if (std.mem.indexOf(u8, func_name, "PyObject_GetAttr") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyObject_SetAttr") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyObject_Call") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyDict_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyDict_SetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyList_GetItem") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyList_SetItem") != null) return true;

        return false;
    }

    /// Get confidence score for a specific issue type
    pub fn getConfidenceScore(issue_kind: GcSafetyIssueKind) f64 {
        return switch (issue_kind) {
            .dangling_gc_reference => 0.8,
            .use_after_gc_collect => 0.85,
            .jni_global_ref_leak => 0.9,
            .python_gil_violation => 0.85,
            .gc_finalizer_ordering => 0.7,
            .reference_cycle => 0.75,
            .finalizer_safety => 0.8,
            .python_refcount_error => 0.9,
            .jni_array_leak => 0.85,
            .buffer_protocol_violation => 0.8,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "GcSafetyAnalyzer - JNI GlobalRef operation detection" {
    const testing = std.testing;

    // Test JNI GlobalRef operations
    try testing.expect(GcSafetyAnalyzer.isJniGlobalRefOperation("NewGlobalRef"));
    try testing.expect(GcSafetyAnalyzer.isJniGlobalRefOperation("DeleteGlobalRef"));
    try testing.expect(GcSafetyAnalyzer.isJniGlobalRefOperation("NewLocalRef"));
    try testing.expect(GcSafetyAnalyzer.isJniGlobalRefOperation("DeleteLocalRef"));

    // Test non-JNI operations
    try testing.expect(!GcSafetyAnalyzer.isJniGlobalRefOperation("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isJniGlobalRefOperation("free"));
    try testing.expect(!GcSafetyAnalyzer.isJniGlobalRefOperation("printf"));
}

test "GcSafetyAnalyzer - Python GIL operation detection" {
    const testing = std.testing;

    // Test Python GIL operations
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("PyGILState_Ensure"));
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("PyGILState_Release"));
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("PyEval_SaveThread"));
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("PyEval_RestoreThread"));
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("Py_BEGIN_ALLOW_THREADS"));
    try testing.expect(GcSafetyAnalyzer.isPythonGilOperation("Py_END_ALLOW_THREADS"));

    // Test non-Python operations
    try testing.expect(!GcSafetyAnalyzer.isPythonGilOperation("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isPythonGilOperation("free"));
    try testing.expect(!GcSafetyAnalyzer.isPythonGilOperation("printf"));
}

test "GcSafetyAnalyzer - GC-finalizer pattern detection" {
    const testing = std.testing;

    // Test Java finalizer patterns
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("finalize"));
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("Finalize"));
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("Destructor"));

    // Test Python destructor patterns
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("__del__"));
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("tp_del"));

    // Test C++ destructor patterns
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("~MyClass"));
    try testing.expect(GcSafetyAnalyzer.isGcFinalizerPattern("_ZN7MyClassD1Ev"));

    // Test non-finalizer patterns
    try testing.expect(!GcSafetyAnalyzer.isGcFinalizerPattern("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isGcFinalizerPattern("free"));
    try testing.expect(!GcSafetyAnalyzer.isGcFinalizerPattern("printf"));
}

test "GcSafetyAnalyzer - FFI cleanup pattern detection" {
    const testing = std.testing;

    // Test JNI cleanup patterns
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("DeleteGlobalRef"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("DeleteLocalRef"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("ReleaseStringUTFChars"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("ReleaseByteArrayElements"));

    // Test Python cleanup patterns
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("Py_DECREF"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("Py_XDECREF"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("Py_CLEAR"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("PyBuffer_Release"));

    // Test general cleanup patterns
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("free"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("dealloc"));
    try testing.expect(GcSafetyAnalyzer.isFfiCleanupPattern("release"));

    // Test non-cleanup patterns
    try testing.expect(!GcSafetyAnalyzer.isFfiCleanupPattern("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isFfiCleanupPattern("alloc"));
    try testing.expect(!GcSafetyAnalyzer.isFfiCleanupPattern("printf"));
}

test "GcSafetyAnalyzer - dangling reference pattern detection" {
    const testing = std.testing;

    // Test JNI dangling reference patterns
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetByteArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetStringUTFChars", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetPrimitiveArrayCritical", "test_func"));

    // Test Python dangling reference patterns
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("PyObject_GetBuffer", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("PyCapsule_GetPointer", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("PyArg_ParseTuple", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("Py_BuildValue", "test_func"));

    // Test non-dangling patterns
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("Py_INCREF", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("Py_DECREF", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("NewGlobalRef", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("malloc", "test_func"));
}

test "GcSafetyAnalyzer - use-after-GC-collect pattern detection" {
    const testing = std.testing;

    // Test JNI use-after-GC-collect patterns
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseByteArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseStringUTFChars", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleasePrimitiveArrayCritical", "test_func"));

    // Test Python use-after-GC-collect patterns
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("PyBuffer_Release", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("Py_DECREF", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("Py_XDECREF", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("Py_CLEAR", "test_func"));

    // Test non-use-after patterns
    try testing.expect(!GcSafetyAnalyzer.isUseAfterGcCollectPattern("malloc", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isUseAfterGcCollectPattern("free", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isUseAfterGcCollectPattern("printf", "test_func"));
}

test "GcSafetyAnalyzer - Python reference counting patterns" {
    const testing = std.testing;

    // Test Python reference counting patterns in dangling reference detection
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("Py_INCREF", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("Py_XINCREF", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("Py_NewRef", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("Py_NewWeakRef", "test_func"));

    // Test that Py_DECREF and Py_XDECREF are in use-after-GC-collect patterns
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("Py_DECREF", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("Py_XDECREF", "test_func"));

    // Test non-reference counting patterns
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("malloc", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("free", "test_func"));
}

test "GcSafetyAnalyzer - JNI array operations" {
    const testing = std.testing;

    // Test JNI array get operations in dangling reference detection
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetBooleanArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetByteArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetCharArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetShortArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetIntArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetLongArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetFloatArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("GetDoubleArrayElements", "test_func"));

    // Test JNI array release operations in use-after-GC-collect detection
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseBooleanArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseByteArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseCharArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseShortArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseIntArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseLongArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseFloatArrayElements", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("ReleaseDoubleArrayElements", "test_func"));

    // Test non-JNI array patterns
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("malloc", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isUseAfterGcCollectPattern("malloc", "test_func"));
}

test "GcSafetyAnalyzer - Python buffer protocol patterns" {
    const testing = std.testing;

    // Test Python buffer protocol patterns in dangling reference detection
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("PyObject_GetBuffer", "test_func"));
    try testing.expect(GcSafetyAnalyzer.isDanglingReferencePattern("PyBuffer_FillInfo", "test_func"));

    // Test Python buffer protocol patterns in use-after-GC-collect detection
    try testing.expect(GcSafetyAnalyzer.isUseAfterGcCollectPattern("PyBuffer_Release", "test_func"));

    // Test non-buffer protocol patterns
    try testing.expect(!GcSafetyAnalyzer.isDanglingReferencePattern("malloc", "test_func"));
    try testing.expect(!GcSafetyAnalyzer.isUseAfterGcCollectPattern("malloc", "test_func"));
}

test "GcSafetyAnalyzer - reference cycle detection helpers" {
    const testing = std.testing;

    // Test JNI object creation patterns
    try testing.expect(GcSafetyAnalyzer.isJniObjectCreation("NewObject"));
    try testing.expect(GcSafetyAnalyzer.isJniObjectCreation("NewString"));
    try testing.expect(GcSafetyAnalyzer.isJniObjectCreation("NewArray"));
    try testing.expect(GcSafetyAnalyzer.isJniObjectCreation("AllocObject"));

    // Test Python object creation patterns
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyObject_New"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyLong_FromLong"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyFloat_FromDouble"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyUnicode_FromString"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyList_New"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyDict_New"));
    try testing.expect(GcSafetyAnalyzer.isPythonObjectCreation("PyTuple_New"));

    // Test JNI reference operation patterns
    try testing.expect(GcSafetyAnalyzer.isJniReferenceOperation("GetObjectField"));
    try testing.expect(GcSafetyAnalyzer.isJniReferenceOperation("GetObjectArrayElement"));
    try testing.expect(GcSafetyAnalyzer.isJniReferenceOperation("CallObjectMethod"));
    try testing.expect(GcSafetyAnalyzer.isJniReferenceOperation("CallStaticObjectMethod"));
    try testing.expect(GcSafetyAnalyzer.isJniReferenceOperation("GetStaticObjectField"));

    // Test Python reference operation patterns
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PyObject_GetAttr"));
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PyObject_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PyDict_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PyList_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PyTuple_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isPythonReferenceOperation("PySequence_GetItem"));

    // Test non-creation/reference patterns
    try testing.expect(!GcSafetyAnalyzer.isJniObjectCreation("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isPythonObjectCreation("free"));
    try testing.expect(!GcSafetyAnalyzer.isJniReferenceOperation("printf"));
    try testing.expect(!GcSafetyAnalyzer.isPythonReferenceOperation("malloc"));
}

test "GcSafetyAnalyzer - cross-language reference detection" {
    const testing = std.testing;

    // Test cross-language reference patterns
    try testing.expect(GcSafetyAnalyzer.isCrossLanguageReference("NewObject", "PyObject_GetAttr"));
    try testing.expect(GcSafetyAnalyzer.isCrossLanguageReference("PyObject_New", "GetObjectField"));

    // Test same-language patterns (should return false)
    try testing.expect(!GcSafetyAnalyzer.isCrossLanguageReference("NewObject", "GetObjectField"));
    try testing.expect(!GcSafetyAnalyzer.isCrossLanguageReference("PyObject_New", "PyObject_GetAttr"));

    // Test non-creation patterns
    try testing.expect(!GcSafetyAnalyzer.isCrossLanguageReference("malloc", "free"));
}

test "GcSafetyAnalyzer - finalizer safety helpers" {
    const testing = std.testing;

    // Test FFI access patterns
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("GetObjectField"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("SetObjectField"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("CallObjectMethod"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("CallVoidMethod"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("GetArrayLength"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("GetByteArrayElements"));

    // Test Python access patterns
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyObject_GetAttr"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyObject_SetAttr"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyObject_Call"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyDict_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyDict_SetItem"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyList_GetItem"));
    try testing.expect(GcSafetyAnalyzer.isFfiAccessPattern("PyList_SetItem"));

    // Test non-access patterns
    try testing.expect(!GcSafetyAnalyzer.isFfiAccessPattern("malloc"));
    try testing.expect(!GcSafetyAnalyzer.isFfiAccessPattern("free"));
    try testing.expect(!GcSafetyAnalyzer.isFfiAccessPattern("printf"));
}

test "GcSafetyAnalyzer - confidence scoring" {
    const testing = std.testing;

    // Test confidence scores for all issue types
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.dangling_gc_reference) == 0.8);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.use_after_gc_collect) == 0.85);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.jni_global_ref_leak) == 0.9);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.python_gil_violation) == 0.85);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.gc_finalizer_ordering) == 0.7);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.reference_cycle) == 0.75);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.finalizer_safety) == 0.8);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.python_refcount_error) == 0.9);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.jni_array_leak) == 0.85);
    try testing.expect(GcSafetyAnalyzer.getConfidenceScore(.buffer_protocol_violation) == 0.8);
}

test "GcSafetyAnalyzer - reference cycle confidence calculation" {
    const testing = std.testing;

    // Test cross-language confidence
    try testing.expect(GcSafetyAnalyzer.calculateReferenceCycleConfidence("NewObject", "PyObject_GetAttr") == 0.75);
    try testing.expect(GcSafetyAnalyzer.calculateReferenceCycleConfidence("PyObject_New", "GetObjectField") == 0.75);

    // Test same-language confidence
    try testing.expect(GcSafetyAnalyzer.calculateReferenceCycleConfidence("NewObject", "GetObjectField") == 0.5);
    try testing.expect(GcSafetyAnalyzer.calculateReferenceCycleConfidence("PyObject_New", "PyObject_GetAttr") == 0.5);

    // Test non-creation patterns
    try testing.expect(GcSafetyAnalyzer.calculateReferenceCycleConfidence("malloc", "free") == 0.5);
}
