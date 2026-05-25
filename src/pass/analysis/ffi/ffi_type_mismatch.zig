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
const c = @import("../../../ir/llvm_raw.zig").c;
// Issue2 FIX: Import helper for standardized CallInst argument counting
const getCallInstArgCount = @import("../../../ir/llvm_safe.zig").getCallInstArgCount;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const ffi_language_classifier = @import("ffi_language_classifier.zig");
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

// INTEGRATION: Use existing noise_filter system
const noise_filter = @import("../../../semantics/noise_filter.zig");
const FunctionOrigin = noise_filter.FunctionOrigin;
const RiskLevel = noise_filter.RiskLevel;
const Language = noise_filter.Language;
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;

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
    zig_align_mismatch,
    /// Size truncation: narrowing integer conversion at FFI boundary (trunc i64→i32)
    size_truncation,
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

/// Helper to check if LLVM API returned a valid (non-null) pointer.
///
/// **When to use**: For all LLVM C API return values (LLVMValueRef, LLVMTypeRef,
/// LLVMBasicBlockRef, etc.). LLVM APIs return null on failure/invalid input.
///
/// **When NOT to use**: For non-LLVM pointers (Zig slices, optionals, user-defined types).
/// Use direct comparison for those: `if (ptr == null) return;`
///
/// **Why this helper exists**: LLVM uses opaque pointer types (usize-sized handles) where
/// null is represented as integer 0. This helper encapsulates the `@intFromPtr(ptr) != 0`
/// pattern to improve readability and ensure consistent null-checking across the codebase.
///
/// Example:
/// ```zig
/// const val = c.LLVMGetOperand(inst, i);
/// if (!llvmNotNull(val)) return;  // Clean, self-documenting
///
/// // Equivalent verbose form:
/// if (@intFromPtr(val) == 0) return;
/// ```
///
/// Arguments:
///   ptr - Any LLVM API pointer type (comptime anytype for flexibility)
///
/// Returns:
///   true if pointer is non-null (valid), false if null (invalid/error)
inline fn llvmNotNull(ptr: anytype) bool {
    return @intFromPtr(ptr) != 0;
}

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
    pub const deps = &[_][]const u8{"call-graph"};

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
        if (!llvmNotNull(func_name_ptr)) return;
        const func_name = std.mem.span(func_name_ptr);

        // INTEGRATION: Use three-layer noise filter (name + path)
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = ctx.classifyFunctionSurface(func_name, func_loc);

        // Skip stdlib and compiler-generated code
        if (!classification.origin.shouldReportByDefault()) {
            diag.debug("[SUPPRESSED] FFITypeMismatch: {s} ({s})", .{ func_name, classification.reason });
            return;
        }

        // Skip LLVM intrinsics
        if (std.mem.startsWith(u8, func_name, "llvm.")) return;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (llvmNotNull(bb)) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (llvmNotNull(inst)) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (llvmNotNull(c.LLVMIsACallInst(inst))) {
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
        if (!llvmNotNull(called_val)) return;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (!llvmNotNull(callee_name_ptr)) return;
        const callee_name = std.mem.span(callee_name_ptr);

        // Check if this is an FFI boundary
        // Use CrossLangEdges from call-graph (covers unmangled Rust wrappers)
        // + fallback to pattern-based detection for edge cases
        const is_ffi = ctx.getCrossEdgeByCallee(callee_name) != null or
            isFFIBoundary(caller_name, callee_name);
        if (!is_ffi) return;

        stats.ffi_boundaries_found += 1;

        // Check for type mismatches at each argument
        // Issue2 FIX: Use standardized helper for CallInst argument count.
        const num_args = getCallInstArgCount(call_inst);
        var arg_idx: u32 = 0;
        while (arg_idx < num_args) : (arg_idx += 1) {
            const arg = c.LLVMGetOperand(call_inst, arg_idx);
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
        if (!llvmNotNull(arg_type)) return null;

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

        // Check 4: Truncation heuristic — narrowing int conversion at FFI boundary
        // Detects patterns like: trunc i64 %len → i32 passed to FFI call (Rust usize→i32)
        if (detectTruncationMismatch(arg, callee_name, param_index, call_inst)) |mismatch| {
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
        if (!llvmNotNull(elem_type)) return null;

        const elem_kind = c.LLVMGetTypeKind(elem_type);

        // Get DataLayout from module to compute type size
        const bb = c.LLVMGetInstructionParent(call_inst);
        if (!llvmNotNull(bb)) return null;
        const func = c.LLVMGetBasicBlockParent(bb);
        if (!llvmNotNull(func)) return null;
        const module = c.LLVMGetGlobalParent(func);
        if (!llvmNotNull(module)) return null;
        const dl = c.LLVMGetModuleDataLayout(module);
        if (!llvmNotNull(dl)) return null;
        const elem_size = c.LLVMABISizeOfType(dl, elem_type);

        // Pattern 1: Functions with alignment requirements in their name
        // (aligned_alloc, posix_memalign, etc.)
        if (std.mem.indexOf(u8, callee_name, "aligned_alloc") != null or
            std.mem.indexOf(u8, callee_name, "posix_memalign") != null)
        {
            // These functions require the alignment parameter to be a power of 2
            // and at least sizeof(void*). We can't verify the runtime value,
            // but we can flag if the alignment type is suspicious.
            // elem_size is in bits (from LLVMABISizeOfType), so 64 bytes = 512 bits
            if (elem_size > 0 and elem_size < 512) {
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

    /// Detects narrowing integer truncation at FFI boundary.
    ///
    /// When Rust code calls an extern "C" function with a truncated value
    /// (e.g., `len as i32` where len is usize/64-bit), the truncation has
    /// already happened in the IR. This heuristic detects the pattern:
    ///   %t = trunc i64 %src to i32
    ///   call @ffi_func(..., i32 %t, ...)
    ///
    /// Only flags when:
    /// 1. The argument's defining instruction is a `trunc`
    /// 2. Source type is wider than destination (narrowing)
    /// 3. Both are integer types
    /// 4. Not a known safe bit-packing pattern (dst ≤ 16 with flag/mask/pack name)
    fn detectTruncationMismatch(
        arg: c.LLVMValueRef,
        callee_name: []const u8,
        param_index: u32,
        call_inst: c.LLVMValueRef,
    ) ?TypeMismatchInfo {
        _ = call_inst; // Available for future location reporting
        // Get the defining instruction of this argument
        const def_inst = getDefiningInstruction(arg) orelse return null;

        const opcode = c.LLVMGetInstructionOpcode(def_inst);
        if (opcode != c.LLVMTrunc) return null;

        // Get source and destination types of the trunc
        const src_val = c.LLVMGetOperand(def_inst, 0);
        if (!llvmNotNull(src_val)) return null;

        const src_type = c.LLVMTypeOf(src_val);
        const dst_type = c.LLVMTypeOf(arg);
        if (!llvmNotNull(src_type) or !llvmNotNull(dst_type)) return null;

        const src_kind = c.LLVMGetTypeKind(src_type);
        const dst_kind = c.LLVMGetTypeKind(dst_type);

        // Both must be integers
        if (src_kind != c.LLVMIntegerTypeKind or dst_kind != c.LLVMIntegerTypeKind) {
            return null;
        }

        const src_width = c.LLVMGetIntTypeWidth(src_type);
        const dst_width = c.LLVMGetIntTypeWidth(dst_type);

        // Must be narrowing (source wider than destination)
        if (src_width <= dst_width) return null;

        // Exclude safe bit-packing patterns: small destinations (≤16 bits)
        // with flag/mask/pack keywords in callee name
        if (dst_width <= 16) {
            const safe_patterns = [_][]const u8{
                "flag",
                "mask",
                "pack",
                "options",
            };
            for (safe_patterns) |pat| {
                if (std.mem.indexOf(u8, callee_name, pat) != null) return null;
            }
        }

        const src_name = intWidthName(src_width);
        const dst_name = intWidthName(dst_width);

        return TypeMismatchInfo{
            .kind = .size_truncation,
            .caller_type = src_name,
            .callee_type = dst_name,
            .caller_lang = "Rust",
            .callee_lang = "C",
            .param_index = param_index,
            .description = "Potential size truncation at FFI boundary",
        };
    }

    /// Try to get the defining instruction of a value.
    /// Returns null if the value is not an instruction (e.g., constant, parameter).
    fn getDefiningInstruction(val: c.LLVMValueRef) ?c.LLVMValueRef {
        if (!llvmNotNull(val)) return null;
        const val_kind = c.LLVMGetValueKind(val);
        if (val_kind != c.LLVMInstructionValueKind) return null;
        return val;
    }

    /// Convert integer bit width to human-readable name.
    /// Returns a static string suitable for diagnostic messages.
    fn intWidthName(width: c_uint) []const u8 {
        return switch (width) {
            8 => "i8",
            16 => "i16",
            32 => "i32",
            64 => "i64",
            128 => "i128",
            else => "integer",
        };
    }

    /// Checks for Go pointer escape (Go pointer passed to C without KeepAlive).
    /// When a Go heap object is passed to C via cgo, the GC must be prevented
    /// from reclaiming it while C still holds the pointer. Without
    /// runtime.KeepAlive, the GC may collect the object prematurely.
    fn checkGoPointerEscape(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const num_args = c.LLVMGetNumArgOperands(call_inst);
        var go_ptr_arg: bool = false;

        for (0..@as(usize, @intCast(num_args))) |i| {
            const arg = c.LLVMGetOperand(call_inst, @intCast(i));
            if (@intFromPtr(arg) == 0) continue;
            const arg_name = c.LLVMGetValueName(arg);
            if (@intFromPtr(arg_name) == 0) continue;
            const name_str = std.mem.span(arg_name);

            const go_alloc_patterns = [_][]const u8{
                "runtime.newobject", "runtime.mallocgc", "C.malloc",
                "C.CString",         "C.CBytes",         "_cgo_allocate",
            };
            for (go_alloc_patterns) |pat| {
                if (std.mem.indexOf(u8, name_str, pat) != null) {
                    go_ptr_arg = true;
                    break;
                }
            }
        }

        if (!go_ptr_arg) return false;

        var has_keepalive = false;
        var next_inst = c.LLVMGetNextInstruction(call_inst);
        const scan_limit: u32 = 10;
        var scanned: u32 = 0;
        while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
            next_inst = c.LLVMGetNextInstruction(next_inst);
            scanned += 1;
        }) {
            if (c.LLVMGetInstructionOpcode(next_inst) == c.LLVMCall) {
                const callee = c.LLVMGetCalledValue(next_inst);
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) != 0) {
                    const cname = std.mem.span(callee_name);
                    if (std.mem.indexOf(u8, cname, "KeepAlive") != null or
                        std.mem.indexOf(u8, cname, "keepalive") != null or
                        std.mem.indexOf(u8, cname, "KeepAlive_p") != null)
                    {
                        has_keepalive = true;
                        break;
                    }
                }
            }
        }

        if (!has_keepalive) {
            diag.warn("  [CGO] Go pointer passed to C without runtime.KeepAlive in {s}", .{caller_name});
            diag.warn("    Risk: GC reclaims object while C still holds pointer (CWE-407)", .{});

            const msg = try std.fmt.allocPrint(ctx.allocator, "Go cgo pointer escape: no KeepAlive after passing Go heap ptr to C in {s}", .{
                caller_name,
            });

            const location = Location.init(caller_name);
            var issue = Issue.init(.borrow_escape, msg, location, .high, 0.75);
            issue.owned = true;
            try ctx.addIssue(&issue);

            return true;
        }

        return false;
    }

    /// Checks for Python reference count mismatches.
    fn checkPythonRefcount(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const called_val = c.LLVMGetCalledValue(call_inst);
        if (!llvmNotNull(called_val)) return false;
        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (!llvmNotNull(callee_name_ptr)) return false;
        const callee_name = std.mem.span(callee_name_ptr);
        const is_incr = std.mem.eql(u8, callee_name, "Py_INCREF") or
            std.mem.eql(u8, callee_name, "Py_XINCREF");
        const is_decr = std.mem.eql(u8, callee_name, "Py_DECREF") or
            std.mem.eql(u8, callee_name, "Py_XDECREF");
        if (!is_incr and !is_decr) return false;

        const py_obj = c.LLVMGetOperand(call_inst, 0);
        if (!llvmNotNull(py_obj)) return false;

        // Type safety: py_obj must be a pointer type (PyObject* is i8* in CPython ABI)
        const obj_type = c.LLVMTypeOf(py_obj);
        if (!llvmNotNull(obj_type)) return false;
        if (c.LLVMGetTypeKind(obj_type) != c.LLVMPointerTypeKind) return false;

        const decr_bb = c.LLVMGetInstructionParent(call_inst);
        if (!llvmNotNull(decr_bb)) return false;
        const func = c.LLVMGetBasicBlockParent(decr_bb);
        if (!llvmNotNull(func)) return false;
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (func_name_ptr) |p| std.mem.span(p) else "unknown";

        if (is_decr) {
            var use_iter = c.LLVMGetFirstUse(py_obj);
            var has_prior_incr = false;
            while (llvmNotNull(use_iter)) : (use_iter = c.LLVMGetNextUse(use_iter)) {
                const user = c.LLVMGetUser(use_iter);
                if (@intFromPtr(user) == 0 or user == call_inst) continue;
                const user_opcode = c.LLVMGetInstructionOpcode(user);
                if (user_opcode != c.LLVMCall and user_opcode != c.LLVMInvoke) continue;

                // Control-flow safety: Py_INCREF must dominate Py_DECREF's basic block,
                // OR be in the same basic block and appear before the Py_DECREF.
                // Note: LLVM C API does not expose dominance analysis; use BB ordering
                // as a safe approximation (conservative — may miss some detections but
                // never produces false positives).
                const user_bb = c.LLVMGetInstructionParent(user);
                if (@intFromPtr(user_bb) == 0) continue;
                const same_bb = @intFromPtr(user_bb) == @intFromPtr(decr_bb);
                if (!same_bb and !basicBlockComesBefore(user_bb, decr_bb)) continue;
                if (same_bb and !instructionComesBefore(user, call_inst)) continue;

                const user_called_val = c.LLVMGetCalledValue(user);
                if (@intFromPtr(user_called_val) == 0) continue;
                const user_callee_ptr = c.LLVMGetValueName(user_called_val);
                if (@intFromPtr(user_callee_ptr) == 0) continue;
                const user_callee = std.mem.span(user_callee_ptr);
                if (std.mem.eql(u8, user_callee, "Py_INCREF") or
                    std.mem.eql(u8, user_callee, "Py_XINCREF"))
                {
                    has_prior_incr = true;
                    break;
                }
            }
            if (!has_prior_incr) {
                const msg = try std.fmt.allocPrint(
                    ctx.allocator,
                    "[OMI-HIGH] Python FFI refcount imbalance in {s}(): Py{s}DECREF on object 0x{x} without matching Py_INCREF — potential UAF",
                    .{ caller_name, if (std.mem.indexOfScalar(u8, callee_name, 'X') != null) "X" else "", @intFromPtr(py_obj) },
                );
                diag.warn("{s}", .{msg});
                var issue = Issue.init(
                    .use_after_free,
                    msg,
                    Location.init(func_name),
                    .high,
                    0.72,
                );
                issue.owned = true;
                try ctx.addIssue(&issue);
                return true;
            }
        }
        return false;
    }

    /// Check if instruction `a` appears before instruction `b` within the same basic block.
    fn instructionComesBefore(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        var inst_a: ?c.LLVMValueRef = a;
        while (inst_a) |cur| : (inst_a = c.LLVMGetNextInstruction(cur)) {
            if (@intFromPtr(cur) == @intFromPtr(b)) return true;
        }
        return false;
    }

    /// Check if basic block `a` appears before `b` in the function's BB list.
    /// Used as conservative approximation for dominance when LLVM C API
    /// doesn't expose DominatorTree analysis. Safe for structured code.
    fn basicBlockComesBefore(a: c.LLVMBasicBlockRef, b: c.LLVMBasicBlockRef) bool {
        var bb: ?c.LLVMBasicBlockRef = c.LLVMGetFirstBasicBlock(c.LLVMGetBasicBlockParent(a));
        var found_a = false;
        while (bb) |cur| : (bb = c.LLVMGetNextBasicBlock(cur)) {
            if (@intFromPtr(cur) == @intFromPtr(b)) return found_a;
            if (@intFromPtr(cur) == @intFromPtr(a)) found_a = true;
        }
        return false;
    }

    /// Reports a detected type mismatch.
    fn reportTypeMismatch(
        ctx: *PassContext,
        caller_name: []const u8,
        callee_name: []const u8,
        call_inst: c.LLVMValueRef,
        mismatch: TypeMismatchInfo,
        diag: *DiagnosticWriter,
    ) !void {
        // E2-1b: MemoryGraph gate - only report type mismatches where at least one
        // call argument pointer is on an FFI danger path. This prevents reporting
        // type mismatches for internal/non-FFI-relevant calls.
        if (@intFromPtr(call_inst) != 0) {
            var has_relevant_ptr = false;
            var arg_idx: u32 = 0;
            while (arg_idx < c.LLVMGetNumArgOperands(call_inst)) : (arg_idx += 1) {
                const arg = c.LLVMGetOperand(call_inst, arg_idx);
                if (@intFromPtr(arg) != 0) {
                    const ptr_val = @as(u64, @intFromPtr(arg));
                    if (ctx.isRelevantAlloc(ptr_val)) {
                        has_relevant_ptr = true;
                        break;
                    }
                }
            }
            if (!has_relevant_ptr) {
                diag.debug("[FFI-TYPE-MISMATCH SUPPRESSED] No relevant pointers on FFI path in {s} -> {s}", .{ caller_name, callee_name });
                return;
            }
        }

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
        const caller_is_rust = std.mem.startsWith(u8, caller_name, "_R") or
            (std.mem.startsWith(u8, caller_name, "_ZN") and
                ffi_language_classifier.isRustMangledName(caller_name));
        if (caller_is_rust) {
            // Callee is not mangled at all → Rust calling C
            if (!std.mem.startsWith(u8, callee_name, "_ZN") and
                !std.mem.startsWith(u8, callee_name, "_R"))
            {
                return true;
            }
            // Callee is C++ _ZN (not Rust) → Rust calling C++ FFI boundary
            if (std.mem.startsWith(u8, callee_name, "_ZN") and
                !ffi_language_classifier.isRustMangledName(callee_name))
            {
                return true;
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

        // F2-3: Signature-based disambiguation — check calling convention.
        // Functions with C calling convention are more likely real FFI boundaries
        // than internal wrappers with the same name pattern.
        if (hasCCallingConvention(callee_name)) {
            if (!isSameLanguagePair(caller_name, callee_name)) {
                return true;
            }
        }

        return false;
    }

    fn hasCCallingConvention(func_name: []const u8) bool {
        const known_c_apis = [_][]const u8{
            "malloc", "free",    "realloc",        "calloc",
            "memcpy", "memmove", "memset",         "memcmp",
            "strlen", "strcpy",  "strcat",         "strcmp",
            "printf", "scanf",   "fopen",          "fread",
            "fwrite", "fclose",  "pthread_create", "pthread_join",
            "signal", "dlopen",  "dlsym",          "dlerror",
        };
        for (known_c_apis) |api| {
            if (std.mem.eql(u8, func_name, api)) return true;
        }
        return false;
    }

    fn isSameLanguagePair(caller: []const u8, callee: []const u8) bool {
        const rust_caller = std.mem.startsWith(u8, caller, "_R") or
            (std.mem.startsWith(u8, caller, "_ZN") and ffi_language_classifier.isRustMangledName(caller));
        const rust_callee = std.mem.startsWith(u8, callee, "_R") or
            (std.mem.startsWith(u8, callee, "_ZN") and ffi_language_classifier.isRustMangledName(callee));
        const go_caller = std.mem.indexOf(u8, caller, "_cgo_") != null;
        const zig_caller = std.mem.startsWith(u8, caller, "zig.") or std.mem.startsWith(u8, caller, "main.");
        if (rust_caller and rust_callee) return true;
        if (go_caller and std.mem.indexOf(u8, callee, "_cgo_") != null) return true;
        if (zig_caller and (std.mem.startsWith(u8, callee, "zig.") or std.mem.startsWith(u8, callee, "main."))) return true;
        return false;
    }

    /// Checks if a function is a C function.
    fn isCFunction(func_name: []const u8) bool {
        // C functions typically don't have mangling prefixes
        if (std.mem.startsWith(u8, func_name, "_Z") or // C++/Rust Itanium ABI
            std.mem.startsWith(u8, func_name, "_ZN") or // C++/Rust nested mangling
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
    // C++ _ZN should NOT be treated as Rust FFI boundary
    try std.testing.expect(!FFITypeMismatchPass.isFFIBoundary("_ZN4Base1fEv", "malloc"));
    // Rust calling C++ _ZN should be FFI boundary
    try std.testing.expect(FFITypeMismatchPass.isFFIBoundary("_ZN4core3fooE", "_ZNSt3__112basic_string"));
    // Rust _R calling C++ _ZN should be FFI boundary
    try std.testing.expect(FFITypeMismatchPass.isFFIBoundary("_RINvC1a4main", "_ZN4Base1fEv"));
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
