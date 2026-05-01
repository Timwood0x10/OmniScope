//! FFI Type Mismatch Detection
//!
//! Detects type mismatches at FFI boundaries across ALL languages:
//!   - C/C++: extern declarations, API boundaries
//!   - Rust: extern "C", unsafe FFI
//!   - Go: cgo calls (C.CBytes, C.malloc, etc.)
//!   - Zig: extern declarations, @cImport
//!   - Python: C API calls (Py*, PyObject*)
//!
//! This is a CORE capability for OmniScope - FFI boundaries are blind spots
//! for every compiler, making them the most dangerous source of UB.
//!
//! INTEGRATION: Uses existing noise_filter system for function classification
//! and risk level computation. Does NOT replace or duplicate existing logic.
//!
//! Reference: todolist.md P0-1, plan/lang_ffi_analysis/plan.md

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

// INTEGRATION: Use existing noise_filter system
const noise_filter = @import("../../semantics/noise_filter.zig");
const FunctionOrigin = noise_filter.FunctionOrigin;
const RiskLevel = noise_filter.RiskLevel;
const Language = noise_filter.Language;
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;

/// Types of FFI type mismatches detected.
pub const TypeMismatchKind = enum(u8) {
    /// Size mismatch: types have different sizes (e.g., usize vs size_t on 32-bit)
    size_mismatch,
    /// Alignment mismatch: types have different alignment requirements
    alignment_mismatch,
    /// Signedness mismatch: signed vs unsigned
    signedness_mismatch,
    /// Pointer type mismatch: different pointee types
    pointer_type_mismatch,
    /// Go pointer escape: Go pointer passed to C without KeepAlive
    go_pointer_escape,
    /// Python refcount mismatch: INC/DEC not balanced
    python_refcount_mismatch,
    /// C++ ABI mismatch: different name mangling or calling convention
    cpp_abi_mismatch,
    /// Zig alignment mismatch: @alignOf != C alignof
    zig_alignment_mismatch,
};

/// Information about a detected type mismatch.
pub const TypeMismatchInfo = struct {
    kind: TypeMismatchKind,
    caller_type: []const u8,
    callee_type: []const u8,
    caller_lang: []const u8,
    callee_lang: []const u8,
    param_index: u32,
    description: []const u8,
};

/// Statistics for FFI type mismatch detection.
pub const TypeMismatchStats = struct {
    total_calls_analyzed: u32 = 0,
    ffi_boundaries_found: u32 = 0,
    size_mismatches: u32 = 0,
    alignment_mismatches: u32 = 0,
    go_pointer_escapes: u32 = 0,
    python_refcount_issues: u32 = 0,

    pub fn formatSummary(self: TypeMismatchStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   FFI TYPE MISMATCH DETECTOR         ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Calls analyzed:          {d:>8}     ║\n", .{self.total_calls_analyzed});
        try writer.print("║  FFI boundaries:          {d:>8}     ║\n", .{self.ffi_boundaries_found});
        try writer.print("║  Size mismatches:         {d:>8}     ║\n", .{self.size_mismatches});
        try writer.print("║  Alignment mismatches:    {d:>8}     ║\n", .{self.alignment_mismatches});
        try writer.print("║  Go pointer escapes:      {d:>8}     ║\n", .{self.go_pointer_escapes});
        try writer.print("║  Python refcount issues:  {d:>8}     ║\n", .{self.python_refcount_issues});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

/// Main FFI type mismatch detection pass.
pub const FFITypeMismatchPass = struct {
    pub const name = "ffi-type-mismatch";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var stats = TypeMismatchStats{};

        var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ref = c.LLVMIsAFunction(func);
            if (@intFromPtr(func_ref) == 0) continue;

            analyzeFunction(ctx, func_ref, diag, &stats) catch |err| {
                diag.warn("FFITypeMismatch: skipped function due to error: {}", .{err});
                continue;
            };
        }

        diag.info("FFITypeMismatch: analyzed {} calls, found {} FFI boundaries, {} issues", .{
            stats.total_calls_analyzed,
            stats.ffi_boundaries_found,
            stats.size_mismatches + stats.alignment_mismatches + stats.go_pointer_escapes + stats.python_refcount_issues,
        });
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *TypeMismatchStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return;
        const func_name = std.mem.span(func_name_ptr);

        // INTEGRATION: Use three-layer noise filter (name + path)
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);

        // Skip stdlib and compiler-generated code
        if (!classification.origin.shouldReportByDefault()) {
            diag.debug("[SUPPRESSED] FFITypeMismatch: {s} ({s})", .{ func_name, classification.reason });
            return;
        }

        // Skip LLVM intrinsics
        if (std.mem.startsWith(u8, func_name, "llvm.")) return;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    try analyzeCallSite(ctx, func_name, inst, diag, stats);
                }
            }
        }
    }

    fn analyzeCallSite(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *TypeMismatchStats,
    ) !void {
        stats.total_calls_analyzed += 1;

        const called_val = c.LLVMGetCalledValue(call_inst);
        if (@intFromPtr(called_val) == 0) return;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return;
        const callee_name = std.mem.span(callee_name_ptr);

        // Check if this is an FFI boundary
        const is_ffi = isFFIBoundary(caller_name, callee_name);
        if (!is_ffi) return;

        stats.ffi_boundaries_found += 1;

        // Check for type mismatches at each argument
        const num_args = c.LLVMGetNumOperands(call_inst) - 1;
        var arg_idx: u32 = 0;
        while (arg_idx < num_args) : (arg_idx += 1) {
            const arg = c.LLVMGetOperand(call_inst, arg_idx + 1);
            if (@intFromPtr(arg) == 0) continue;

            if (checkTypeMismatch(ctx, caller_name, callee_name, call_inst, arg, arg_idx, diag)) |mismatch| {
                switch (mismatch.kind) {
                    .size_mismatch => stats.size_mismatches += 1,
                    .alignment_mismatch => stats.alignment_mismatches += 1,
                    .go_pointer_escape => stats.go_pointer_escapes += 1,
                    .python_refcount_mismatch => stats.python_refcount_issues += 1,
                    else => {},
                }
            }
        }

        // Special checks for Go cgo
        if (isGoCgoCall(callee_name)) {
            if (try checkGoPointerEscape(ctx, caller_name, call_inst, diag)) {
                stats.go_pointer_escapes += 1;
            }
        }

        // Special checks for Python C API
        if (isPythonCAPI(callee_name)) {
            if (try checkPythonRefcount(ctx, caller_name, call_inst, diag)) {
                stats.python_refcount_issues += 1;
            }
        }
    }

    /// Checks for type mismatch at an FFI boundary.
    fn checkTypeMismatch(
        ctx: *PassContext,
        caller_name: []const u8,
        callee_name: []const u8,
        call_inst: c.LLVMValueRef,
        arg: c.LLVMValueRef,
        param_index: u32,
        diag: *DiagnosticWriter,
    ) ?TypeMismatchInfo {
        const arg_type = c.LLVMTypeOf(arg);
        if (@intFromPtr(arg_type) == 0) return null;

        // Check 1: Size mismatch (e.g., usize vs size_t)
        if (detectSizeMismatch(arg_type, callee_name, param_index)) |mismatch| {
            reportTypeMismatch(ctx, caller_name, callee_name, call_inst, mismatch, diag) catch {};
            return mismatch;
        }

        // Check 2: Alignment mismatch
        if (detectAlignmentMismatch(arg_type, callee_name, param_index, call_inst)) |mismatch| {
            reportTypeMismatch(ctx, caller_name, callee_name, call_inst, mismatch, diag) catch {};
            return mismatch;
        }

        // Check 3: Signedness mismatch
        if (detectSignednessMismatch(arg_type, callee_name, param_index)) |mismatch| {
            reportTypeMismatch(ctx, caller_name, callee_name, call_inst, mismatch, diag) catch {};
            return mismatch;
        }

        return null;
    }

    /// Detects size mismatches (e.g., usize vs size_t on 32-bit).
    fn detectSizeMismatch(
        arg_type: c.LLVMTypeRef,
        callee_name: []const u8,
        param_index: u32,
    ) ?TypeMismatchInfo {
        const type_kind = c.LLVMGetTypeKind(arg_type);

        // Check for integer types
        if (type_kind == c.LLVMIntegerTypeKind) {
            const bit_width = c.LLVMGetIntTypeWidth(arg_type);

            // Common size mismatch patterns:
            // - usize (64-bit on 64-bit platforms) vs size_t (32-bit on 32-bit platforms)
            // - long (platform-dependent) vs int32_t/int64_t

            // Pattern 1: Function expects size_t but receives usize
            if (std.mem.indexOf(u8, callee_name, "size_t") != null or
                std.mem.indexOf(u8, callee_name, "Size") != null)
            {
                // On 32-bit platforms, size_t is 32-bit, but usize might be 64-bit
                if (bit_width == 64) {
                    return TypeMismatchInfo{
                        .kind = .size_mismatch,
                        .caller_type = "usize (64-bit)",
                        .callee_type = "size_t (32-bit on 32-bit platforms)",
                        .caller_lang = "Rust",
                        .callee_lang = "C",
                        .param_index = param_index,
                        .description = "Potential size mismatch: usize is 64-bit but size_t may be 32-bit on target platform",
                    };
                }
            }
        }

        return null;
    }

    /// Detects alignment mismatches.
    /// Common pattern: Zig @alignCast to wrong alignment, or C struct
    /// with packed attribute passed to function expecting natural alignment.
    fn detectAlignmentMismatch(
        arg_type: c.LLVMTypeRef,
        callee_name: []const u8,
        param_index: u32,
        call_inst: c.LLVMValueRef,
    ) ?TypeMismatchInfo {
        const type_kind = c.LLVMGetTypeKind(arg_type);

        // Only check pointer types — alignment matters for pointer targets
        if (type_kind != c.LLVMPointerTypeKind) return null;

        // Get the element type (what the pointer points to)
        const elem_type = c.LLVMGetElementType(arg_type);
        if (@intFromPtr(elem_type) == 0) return null;

        const elem_kind = c.LLVMGetTypeKind(elem_type);

        // Get DataLayout from module to compute type size
        const bb = c.LLVMGetInstructionParent(call_inst);
        if (@intFromPtr(bb) == 0) return null;
        const func = c.LLVMGetBasicBlockParent(bb);
        if (@intFromPtr(func) == 0) return null;
        const module = c.LLVMGetGlobalParent(func);
        if (@intFromPtr(module) == 0) return null;
        const dl = c.LLVMGetModuleDataLayout(module);
        if (@intFromPtr(dl) == 0) return null;
        const elem_size = c.LLVMABISizeOfType(dl, elem_type);

        // Pattern 1: Functions with alignment requirements in their name
        // (aligned_alloc, posix_memalign, etc.)
        if (std.mem.indexOf(u8, callee_name, "aligned_alloc") != null or
            std.mem.indexOf(u8, callee_name, "posix_memalign") != null)
        {
            // These functions require the alignment parameter to be a power of 2
            // and at least sizeof(void*). We can't verify the runtime value,
            // but we can flag if the alignment type is suspicious.
            if (elem_size > 0 and elem_size < 64) {
                return TypeMismatchInfo{
                    .kind = .alignment_mismatch,
                    .caller_type = "pointer (under-aligned)",
                    .callee_type = "pointer (requires specific alignment)",
                    .caller_lang = "unknown",
                    .callee_lang = "C",
                    .param_index = param_index,
                    .description = "Alignment-sensitive function called — verify alignment matches requirements",
                };
            }
        }

        // Pattern 2: SIMD/vector types passed to C functions
        // These require strict alignment (16/32/64 bytes)
        if (elem_kind == c.LLVMVectorTypeKind) {
            if (elem_size >= 128) {
                return TypeMismatchInfo{
                    .kind = .alignment_mismatch,
                    .caller_type = "vector pointer",
                    .callee_type = "C function (may not guarantee SIMD alignment)",
                    .caller_lang = "unknown",
                    .callee_lang = "C",
                    .param_index = param_index,
                    .description = "SIMD vector passed across FFI — verify alignment is preserved",
                };
            }
        }

        return null;
    }

    /// Detects signedness mismatches.
    /// Common pattern: Rust i32 passed to C function expecting unsigned int,
    /// or C ssize_t vs Rust usize.
    fn detectSignednessMismatch(
        arg_type: c.LLVMTypeRef,
        callee_name: []const u8,
        param_index: u32,
    ) ?TypeMismatchInfo {
        const type_kind = c.LLVMGetTypeKind(arg_type);

        // Only check integer types
        if (type_kind != c.LLVMIntegerTypeKind) return null;

        const bit_width = c.LLVMGetIntTypeWidth(arg_type);

        // Pattern 1: C functions with "unsigned" in parameter name
        // but receiving a signed integer from the caller.
        // We detect this by checking if the callee name suggests
        // unsigned semantics but the argument type is a generic integer.
        if (bit_width == 32 or bit_width == 64) {
            // Functions with "count", "len", "size", "num" in name
            // typically expect unsigned values, but callers may pass signed.
            const unsigned_hint_patterns = [_][]const u8{
                "unsigned", "uint", "size", "count", "len", "num",
            };
            for (unsigned_hint_patterns) |pattern| {
                if (std.mem.indexOf(u8, callee_name, pattern) != null) {
                    return TypeMismatchInfo{
                        .kind = .signedness_mismatch,
                        .caller_type = if (bit_width == 32) "i32 (signed)" else "i64 (signed)",
                        .callee_type = if (bit_width == 32) "unsigned int" else "unsigned long",
                        .caller_lang = "unknown",
                        .callee_lang = "C",
                        .param_index = param_index,
                        .description = "Potential signedness mismatch: callee may expect unsigned but receives signed integer",
                    };
                }
            }
        }

        return null;
    }

    /// Checks for Go pointer escape (Go pointer passed to C without KeepAlive).
    fn checkGoPointerEscape(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        _ = ctx;
        _ = caller_name;
        _ = call_inst;
        _ = diag;

        // TODO: Implement Go cgo pointer escape detection
        // This requires:
        // 1. Detecting if the caller is Go code
        // 2. Checking if any argument is a Go pointer
        // 3. Verifying that runtime.KeepAlive is called after the FFI call

        return false;
    }

    /// Checks for Python reference count mismatches.
    fn checkPythonRefcount(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        _ = ctx;
        _ = caller_name;
        _ = call_inst;
        _ = diag;

        // TODO: Implement Python refcount checking
        // This requires:
        // 1. Detecting Py_INCREF/Py_DECREF calls
        // 2. Tracking reference count balance
        // 3. Reporting unbalanced INC/DEC

        return false;
    }

    /// Reports a detected type mismatch.
    fn reportTypeMismatch(
        ctx: *PassContext,
        caller_name: []const u8,
        callee_name: []const u8,
        _: c.LLVMValueRef,
        mismatch: TypeMismatchInfo,
        diag: *DiagnosticWriter,
    ) !void {
        const location = Location.init(caller_name);

        const trace = try ctx.allocator.alloc(TraceEntry, 3);
        trace[0] = try makeTrace(ctx.allocator, "FFI boundary: {s} → {s}", .{ caller_name, callee_name });
        trace[1] = try makeTrace(ctx.allocator, "Caller type: {s} ({s})", .{ mismatch.caller_type, mismatch.caller_lang });
        trace[2] = try makeTrace(ctx.allocator, "Callee expects: {s} ({s})", .{ mismatch.callee_type, mismatch.callee_lang });

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "FFI type mismatch at parameter {}: {s}",
            .{ mismatch.param_index, mismatch.description },
        );

        const issue = Issue.initWithTrace(
            .ffi_type_mismatch,
            message,
            location,
            .high,
            0.75,
            trace,
        );

        try ctx.addIssue(&issue);

        diag.warn("[FFI-TYPE-MISMATCH] {s} → {s}: {s}", .{ caller_name, callee_name, mismatch.description });
    }

    /// Checks if a call is an FFI boundary.
    fn isFFIBoundary(caller_name: []const u8, callee_name: []const u8) bool {
        // Pattern 1: Rust extern "C" functions
        if (std.mem.startsWith(u8, caller_name, "_ZN") or // Rust mangled
            std.mem.startsWith(u8, caller_name, "_R"))
        {
            if (!std.mem.startsWith(u8, callee_name, "_ZN") and
                !std.mem.startsWith(u8, callee_name, "_R"))
            {
                return true; // Rust → C
            }
        }

        // Pattern 2: Go cgo calls
        if (std.mem.indexOf(u8, caller_name, "_cgo_") != null) {
            return true;
        }

        // Pattern 3: Python C API calls
        if (std.mem.startsWith(u8, callee_name, "Py") or
            std.mem.startsWith(u8, callee_name, "PyObject"))
        {
            return true;
        }

        // Pattern 4: Zig extern calls
        if (std.mem.startsWith(u8, caller_name, "zig.") or
            std.mem.startsWith(u8, caller_name, "main."))
        {
            if (isCFunction(callee_name)) {
                return true;
            }
        }

        return false;
    }

    /// Checks if a function is a C function.
    fn isCFunction(func_name: []const u8) bool {
        // C functions typically don't have mangling prefixes
        if (std.mem.startsWith(u8, func_name, "_Z") or // C++ mangled
            std.mem.startsWith(u8, func_name, "_ZN") or // Rust mangled
            std.mem.startsWith(u8, func_name, "_R")) // Rust v0 mangled
        {
            return false;
        }

        // Common C standard library prefixes
        const c_prefixes = [_][]const u8{
            "malloc",   "free",   "calloc", "realloc",
            "fopen",    "fclose", "fread",  "fwrite",
            "pthread_", "sem_",   "dlopen", "dlsym",
            "dlclose",  "socket", "bind",   "listen",
            "accept",
        };

        for (c_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) {
                return true;
            }
        }

        return false;
    }

    /// Checks if a call is a Go cgo call.
    fn isGoCgoCall(callee_name: []const u8) bool {
        return std.mem.indexOf(u8, callee_name, "_Cfunc_") != null or
            std.mem.indexOf(u8, callee_name, "_cgo_") != null;
    }

    /// Checks if a function is Python C API.
    fn isPythonCAPI(callee_name: []const u8) bool {
        return std.mem.startsWith(u8, callee_name, "Py") or
            std.mem.startsWith(u8, callee_name, "PyObject");
    }
};

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "FFITypeMismatchPass - name and kind" {
    try std.testing.expectEqualStrings("ffi-type-mismatch", FFITypeMismatchPass.name);
    try std.testing.expectEqual(PassKind.analysis, FFITypeMismatchPass.kind);
}

test "isFFIBoundary - Rust to C" {
    try std.testing.expect(FFITypeMismatchPass.isFFIBoundary("_ZN4core3fooE", "malloc"));
    try std.testing.expect(!FFITypeMismatchPass.isFFIBoundary("_ZN4core3fooE", "_ZN4core3barE"));
}

test "isFFIBoundary - Go cgo" {
    try std.testing.expect(FFITypeMismatchPass.isFFIBoundary("main_cgo_foo", "C.malloc"));
}

test "isFFIBoundary - Python C API" {
    try std.testing.expect(FFITypeMismatchPass.isFFIBoundary("python_module", "PyObject_Call"));
}

test "isCFunction - standard library" {
    try std.testing.expect(FFITypeMismatchPass.isCFunction("malloc"));
    try std.testing.expect(FFITypeMismatchPass.isCFunction("pthread_create"));
    try std.testing.expect(!FFITypeMismatchPass.isCFunction("_ZN4core3fooE"));
}
