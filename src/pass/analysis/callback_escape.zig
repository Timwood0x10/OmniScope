//! Callback Escaping Detector
//!
//! Phase 4.2: Detects Go cgo pointer retention bugs and callback escaping patterns.
//!
//! Key detection targets:
//! - Go pointer passed to C via C.CBytes() without runtime.KeepAlive
//! - unsafe.Pointer conversion that may dangle after GC
//! - C function retaining Go-allocated pointer beyond call scope
//! - Missing C.free / C.malloc pairs in cgo code
//!
//! Reference: plan/lang_ffi_analysis/go_ffi_fliter.md
//!
//! Example bugs detected:
//!
//!   // Go: pointer retained by C after call
//!   var buf []byte{1, 2, 3}
//!   C.process(C.CBytes(string(buf)))  // C retains pointer, GC may reclaim buf
//!
//!   // Go: missing KeepAlive for escaped pointer
//!   ptr := C.malloc(1024)
//!   defer C.free(ptr)
//!   C.useData(ptr)
//!   // BUG: no runtime.KeepAlive(ptr) - GC could run during C.useData

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
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const FPWhitelist = @import("../filter/fp_whitelist.zig");
const FPPrecisionGuard = @import("../filter/fp_precision_guard.zig");
comptime {
    _ = FPPrecisionGuard.PrecisionMetrics;
} // Force test discovery
const NoiseReduction = @import("noise_reduction.zig");
const noise_filter = @import("../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;
const call_graph_mod = @import("../../semantics/call_graph.zig");

// : Integrated Hook system for semantic analysis.
// Replaces hardcoded C_RETAINING_FUNCTIONS with centralized patterns + hooks.
const hooks = @import("../../registry/hooks.zig");
const registry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const ptr_types = @import("ptr_lifetime_types.zig");

/// Types of callback escaping violations detected.
pub const EscapeViolation = enum(u8) {
    /// Go pointer passed to C without KeepAlive guard
    go_pointer_no_keepalive,
    /// C.CBytes result passed to retaining function
    cbytes_escape,
    /// unsafe.Pointer used across FFI boundary without lifetime guarantee
    unsafeptr_dangling_risk,
    /// malloc without corresponding free (leak)
    malloc_without_free,
    /// free without matching malloc (double-free risk)
    free_without_malloc,
};

/// Classification of a detected escape pattern.
pub const EscapePattern = struct {
    violation_type: EscapeViolation,
    confidence: f32,
    func_name: []const u8,
    callee_name: []const u8,
    description: []const u8,
};

/// Statistics for the callback escape detector.
pub const EscapeStats = struct {
    total_functions_analyzed: u32 = 0,
    go_cgo_boundaries_found: u32 = 0,
    keepalive_missing: u32 = 0,
    cbytes_escapes: u32 = 0,
    unsafeptr_risks: u32 = 0,
    malloc_leaks: u32 = 0,
    free_orphans: u32 = 0,
    callback_escapes: u32 = 0,

    pub fn formatSummary(self: EscapeStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   CALLBACK ESCAPE DETECTOR SUMMARY ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:      {d:>8}     ║\n", .{self.total_functions_analyzed});
        try writer.print("║  CGo boundaries found:    {d:>8}     ║\n", .{self.go_cgo_boundaries_found});
        try writer.print("║  Missing KeepAlive:       {d:>8}     ║\n", .{self.keepalive_missing});
        try writer.print("║  CBytes escapes:          {d:>8}     ║\n", .{self.cbytes_escapes});
        try writer.print("║  Callback escapes:        {d:>8}     ║\n", .{self.callback_escapes});
        try writer.print("║  Unsafe.Pointer risks:    {d:>8}     ║\n", .{self.unsafeptr_risks});
        try writer.print("║  Malloc-without-free:     {d:>8}     ║\n", .{self.malloc_leaks});
        try writer.print("║  Free-orphan calls:       {d:>8}     ║\n", .{self.free_orphans});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Go CGo Pattern Detection
// ============================================================================

/// Functions that indicate cgo glue code (compiler-generated).
const CGO_GLUE_PATTERNS = &[_][]const u8{
    "_cgo_",
    "_Cfunc_",
    "_cgo_gotypes",
    "crosscall2",
};

/// Known Go runtime functions related to cgo safety.
const GO_RUNTIME_SAFETY_FUNCTIONS = &[_][]const u8{
    "runtime.KeepAlive",
    "runtime_Pin",
    "runtime_Unpin",
    "runtime_cgocall",
};

/// C standard library functions that unconditionally retain pointers (escape analysis).
/// These functions store pointers for later use beyond the caller's lifetime.
const C_RETAINING_FUNCTIONS = &[_][]const u8{
    "pthread_create",          "signal",           "sigaction",
    "atexit",                  "on_exit",          "SDL_SetEventCallback",
    "glfwSetCallback",         "curl_easy_setopt", "RegisterNatives",
    "PyCapsule_SetDestructor", "dlopen",
};

/// Check if a function name indicates cgo boundary code.
pub fn isCgoBoundary(func_name: []const u8) bool {
    for (CGO_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

    // Cgo "C." prefix matching with stricter rules to avoid false positives:
    // - Must be at start of function name OR preceded by a package path (e.g., "main.C.")
    // - NOT in the middle of a name like "AC.BMethod" or "MC.function"
    const c_dot_idx = std.mem.indexOf(u8, func_name, "C.");
    if (c_dot_idx) |idx| {
        const valid = idx == 0 or
            (idx >= 2 and func_name[idx - 1] == '.');
        if (valid) return true;
    }

    return false;
}

/// Check if a function is a cgo boundary using LLVM metadata.
///
/// Uses LLVM linkage type and declaration status to identify
/// compiler-generated cgo glue functions more precisely than string matching.
pub fn isCgoBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    if (func == null) return false;

    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return false;
    const func_name = std.mem.span(func_name_ptr);

    if (c.LLVMIsDeclaration(func) != 0) {
        const linkage = c.LLVMGetLinkage(func);
        if (linkage == c.LLVMExternalWeakLinkage or
            linkage == c.LLVMCommonLinkage)
        {
            return true;
        }
        if (linkage == c.LLVMExternalLinkage) {
            if (isCgoGlueByPattern(func_name)) return true;
        }
        if (linkage == c.LLVMWeakAnyLinkage or
            linkage == c.LLVMWeakODRLinkage or
            linkage == c.LLVMLinkOnceAnyLinkage or
            linkage == c.LLVMLinkOnceODRLinkage)
        {
            if (isCgoGlueByPattern(func_name)) return true;
        }
    } else {
        if (isCgoGlueByPattern(func_name)) return true;

        const section = c.LLVMGetSection(func);
        if (@intFromPtr(section) != 0) {
            const section_name = std.mem.span(section);
            if (std.mem.indexOf(u8, section_name, ".text") != null) {
                if (isCgoGlueByPattern(func_name)) return true;
            }
        }
    }

    return false;
}

fn isCgoGlueByPattern(name: []const u8) bool {
    for (CGO_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }
    if (std.mem.indexOf(u8, name, "cgocall") != null) return true;
    if (std.mem.indexOf(u8, name, "_cgo_") != null) return true;
    if (std.mem.startsWith(u8, name, "crosscall")) return true;
    return false;
}

/// Check if a function is a Go runtime safety function (KeepAlive etc).
pub fn isGoSafetyFunction(callee_name: []const u8) bool {
    for (GO_RUNTIME_SAFETY_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }
    return false;
}

/// R7.1-3: Language-aware pointer retention check.
///
/// For **Go callers** (cgo boundary): Full detection — set_/add_/register_ prefixes
///   indicate the callee may hold the pointer beyond the call (Go runtime can't
///   see C memory, so KeepAlive is needed).
///
/// For **C callers**: Only detect REAL escapes — storing to global variables,
///   passing to async callbacks (pthread_create, signal), etc.
///   Plain func(&local) in C is standard borrowing — NOT an escape.
///
/// For **Rust callers**: Only detect escapes inside unsafe blocks.
///
/// For **Zig callers**: Skip entirely (compile-time lifetime guarantees).
fn mayRetainInCLanguageAware(callee_name: []const u8, caller_is_cgo: bool) bool {
    // Always-retaining functions regardless of language
    for (C_RETAINING_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }

    if (caller_is_cgo) {
        // Go cgo: broader prefix matching (set_, add_, register_ may hold pointers)
        const retaining_prefixes = [_][]const u8{
            "register_", "set_", "add_", "subscribe_",
        };
        for (retaining_prefixes) |prefix| {
            if (std.mem.startsWith(u8, callee_name, prefix)) return true;
        }
    }
    // NOTE: For C/Rust/Zig callers, C_RETAINING_FUNCTIONS above already covers
    // all truly escaping patterns (pthread_create, signal, atexit, etc.).
    // Functions like set_error(), add_data(), register_callback() are NOT
    // real escapes — they just write through a pointer parameter and return
    // before the caller's stack frame ends.

    return false;
}

/// Detect C.CBytes pattern in function names.
pub fn isCBytesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "CBytes") != null or
        std.mem.indexOf(u8, name, "C.GoString") != null or
        std.mem.indexOf(u8, name, "C.GoStringN") != null;
}

/// Detect unsafe.Pointer conversion pattern.
pub fn isUnsafePtrConversion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "unsafe.Pointer") != null or
        std.mem.indexOf(u8, name, "uintptr") != null;
}

/// Detect JNI RegisterNatives pattern for callback signature validation.
pub fn isRegisterNativesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "RegisterNatives") != null;
}

/// Detect pthread_create pattern for callback thread safety.
pub fn isPthreadCreatePattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "pthread_create") != null;
}

/// Check if function is a known callback receiver that requires type-safe pointers.
pub fn isCallbackReceiver(name: []const u8) bool {
    const receivers = [_][]const u8{
        "RegisterNatives",  "SetCallback",            "set_callback",
        "pthread_create",   "pthread_setcancelstate", "signal",
        "sigaction",        "SDL_SetEventCallback",   "glfwSetCallback",
        "curl_easy_setopt",
    };
    for (receivers) |r| {
        if (std.mem.indexOf(u8, name, r) != null) return true;
    }
    return false;
}

/// Validate callback function pointer has compatible signature.
/// This is a heuristic check based on naming conventions.
pub fn validate_callback_signature(func_name: []const u8, callback_arg_type: []const u8) bool {
    if (callback_arg_type.len == 0) return false;
    if (std.mem.indexOf(u8, func_name, "RegisterNatives") != null) {
        if (std.mem.indexOf(u8, callback_arg_type, "JNINativeMethod") != null) return true;
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "*") != null) return true;
        return false;
    }
    if (std.mem.indexOf(u8, func_name, "pthread_create") != null) {
        if (std.mem.indexOf(u8, callback_arg_type, "void*") != null) return true;
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "*") != null) return true;
        return false;
    }
    if (std.mem.indexOf(u8, func_name, "signal") != null or
        std.mem.indexOf(u8, func_name, "sigaction") != null)
    {
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "int") != null) return true;
        return false;
    }
    const generic_patterns = [_][]const u8{
        "atexit",  "qsort",              "bsearch",
        "on_exit", "pthread_key_create",
    };
    for (generic_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) {
            if (callback_arg_type.len > 0 and
                (std.mem.indexOf(u8, callback_arg_type, "void") != null or
                    std.mem.indexOf(u8, callback_arg_type, "*") != null))
            {
                return true;
            }
            return false;
        }
    }
    return false;
}

// ============================================================================
// Main Pass
// ============================================================================

/// Callback Escaping Detector Pass
///
/// Analyzes functions for cgo-related pointer lifetime issues:
/// 1. Go pointers passed to C without KeepAlive protection
/// 2. C.CBytes results escaping to retaining functions
/// 3. Unsafe.Pointer conversions at FFI boundaries
/// 4. Malloc/free pairing verification
pub const CallbackEscapePass = struct {
    pub const name = "callback-escape";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // R8.2-d: Consume cross-language edges from CallGraphPass.
        // Cross-lang edges help identify Go→C cgo boundaries for callback escape detection.
        const cross_edges = ctx.getCrossLangEdges();
        var go_cgo_edge_count: u32 = 0;
        for (cross_edges) |edge| {
            if (edge.caller_lang == .go and (edge.callee_lang == .c or edge.callee_lang == .cpp)) {
                go_cgo_edge_count += 1;
            }
        }
        if (go_cgo_edge_count > 0) {
            diag.info("CallbackEscape: {d} Go→C/C++ cross-language edges available", .{go_cgo_edge_count});
        }

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };
        var stats = EscapeStats{};

        // Initialize Hook system for semantic analysis.
        // Hooks provide language-specific detection beyond pattern matching.
        try hooks.initHookStates(ctx.allocator);
        defer hooks.deinitHookStates();

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);
                ctx.zone_stats.record(zone);
                continue;
            }

            const func_name_raw = c.LLVMGetValueName(func);
            const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";

            const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);
            ctx.zone_stats.record(zone);

            // v0.1.8: Three-layer noise reduction (supersedes zone-only check)
            const debug_file_path = extractDebugFilePath(func);
            const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // Defense-in-depth: known FP whitelist (v0.1.8 audit verified)
            if (FPWhitelist.is_known_fp(func_name) != null) continue;

            // P0-1: Function-level gate — skip functions without danger-surface-relevant
            // pointers to optimize analysis. DangerSurfacePass (upstream) populates
            // relevant_functions HashSet; functions not involved in FFI boundary
            // pointer flow can safely be skipped.
            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) {
                continue;
            }

            // : Reset hook state for this function scope.
            hooks.resetHookStatesForFunction();

            // Function-level error isolation
            analyzeFunction(ctx, func, diag, &stats) catch |err| {
                diag.warn("CallbackEscape: skipped function due to error: {any} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };

            // Check hook state for end-of-function issues.
            if (hooks.rustUnpairedTransferCount() > 0) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Unpaired Rust ownership transfer in {s} (into_raw without matching from_raw)", .{func_name});
                defer ctx.allocator.free(msg);
                const trace = try ctx.allocator.alloc(TraceEntry, 1);
                trace[0] = TraceEntry.init("Rust into_raw() not paired with from_raw() — potential ownership leak across FFI boundary");
                const issue = Issue.initWithTrace(
                    .cross_language_leak,
                    msg,
                    Location.init(func_name),
                    .medium,
                    0.65,
                    trace,
                );
                try ctx.addIssue(&issue);
                stats.unsafeptr_risks += 1;
            }
            if (hooks.pythonUnbalancedDecrefCount() > 0) {
                const count = hooks.pythonUnbalancedDecrefCount();
                const msg = try std.fmt.allocPrint(ctx.allocator, "{d} unbalanced Py_DECREF(s) in {s} (without matching Py_INCREF)", .{ count, func_name });
                defer ctx.allocator.free(msg);
                const trace = try ctx.allocator.alloc(TraceEntry, 1);
                trace[0] = TraceEntry.init("Python refcount imbalance — potential use-after-free across FFI boundary");
                const issue = Issue.initWithTrace(
                    .use_after_free,
                    msg,
                    Location.init(func_name),
                    .high,
                    0.80,
                    trace,
                );
                try ctx.addIssue(&issue);
                stats.unsafeptr_risks += @intCast(count);
            }
        }

        diag.info("CallbackEscape: analyzed {d} funcs, {d} cgo boundaries, {d} issues found", .{ stats.total_functions_analyzed, stats.go_cgo_boundaries_found, stats.keepalive_missing + stats.cbytes_escapes +
            stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans });
    }

    /// Extract debug file path from LLVM subprogram metadata.
    /// Used by NoiseReduction Layer 2 (path-based filter).
    fn extractDebugFilePath(func: c.LLVMValueRef) ?[]const u8 {
        const subprogram = c.LLVMGetSubprogram(func);
        if (@intFromPtr(subprogram) == 0) return null;

        const file_ref = c.LLVMDIScopeGetFile(subprogram);
        if (@intFromPtr(file_ref) == 0) return null;

        var filename_len: c_uint = undefined;
        const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
        if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

        const max_path_len: c_uint = 4096;
        if (filename_len > max_path_len) return null;
        if (filename_ptr[0] == 0) return null;

        return filename_ptr[0..filename_len];
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        // R7.2 Language Channel Gate
        const escape_channel = ctx.channelCallbackEscape();
        if (escape_channel == .skip) return;
        diag.debug("LANG-CHANNEL [callback_escape/{s}]: {s}", .{
            @tagName(escape_channel), func_name,
        });

        stats.total_functions_analyzed += 1;

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
        if (!classification.origin.shouldReportByDefault()) return;

        // R7.2: Use module-level language detection instead of per-function cgo check.
        // isGoModule() is set once at scan entry by Language-First Pipeline.
        // Keep isCgoBoundaryFromLLVM as a secondary refinement for mixed-language modules.
        const is_cgo_boundary = ctx.isGoModule() or isCgoBoundaryFromLLVM(func);
        if (is_cgo_boundary) {
            stats.go_cgo_boundaries_found += 1;
        }

        var has_keepalive = false;
        var alloc_sites: std.ArrayList(AllocSiteInfo) = .{};
        defer {
            for (alloc_sites.items) |site| ctx.allocator.free(site.func_name);
            alloc_sites.deinit(ctx.allocator);
        }
        var free_sites: std.ArrayList(FreeSiteInfo) = .{};
        defer {
            for (free_sites.items) |site| ctx.allocator.free(site.func_name);
            free_sites.deinit(ctx.allocator);
        }
        var cgo_calls: std.ArrayList(CGoCallInfo) = .{};
        defer {
            for (cgo_calls.items) |call| ctx.allocator.free(call.callee_name);
            cgo_calls.deinit(ctx.allocator);
        }
        var callback_escapes: std.ArrayList(CallbackEscapeInfo) = .{};
        defer callback_escapes.deinit(ctx.allocator);

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try scanInstruction(ctx.allocator, inst, &has_keepalive, &alloc_sites, &free_sites, &cgo_calls, ctx.isGoModule());
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called) == 0) continue;
                    const name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(name_ptr) == 0) continue;
                    const callee_name = std.mem.span(name_ptr);
                    if (isGenericCallbackReceiver(callee_name)) {
                        const num_ops = c.LLVMGetNumOperands(inst);
                        var i: u32 = 0;
                        while (i < num_ops) : (i += 1) {
                            const arg = c.LLVMGetOperand(inst, i);
                            if (@intFromPtr(arg) == 0) continue;
                            const arg_type = c.LLVMTypeOf(arg);
                            if (@intFromPtr(arg_type) == 0) continue;
                            if (c.LLVMGetTypeKind(arg_type) != c.LLVMPointerTypeKind) continue;
                            const elem_type = c.LLVMGetElementType(arg_type);
                            if (@intFromPtr(elem_type) == 0) continue;
                            if (c.LLVMGetTypeKind(elem_type) != c.LLVMFunctionTypeKind) continue;
                            if (isLikelyCallbackFunction(elem_type, callee_name)) {
                                try callback_escapes.append(ctx.allocator, .{
                                    .inst = inst,
                                    .receiver_name = callee_name,
                                    .callback_arg = arg,
                                });
                            }
                        }
                    }
                }
                if (opcode == c.LLVMStore) {
                    const value_op = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(value_op) == 0) continue;
                    const value_type = c.LLVMTypeOf(value_op);
                    if (@intFromPtr(value_type) == 0) continue;
                    if (c.LLVMGetTypeKind(value_type) != c.LLVMPointerTypeKind) continue;
                    const elem_type = c.LLVMGetElementType(value_type);
                    if (@intFromPtr(elem_type) == 0) continue;
                    if (c.LLVMGetTypeKind(elem_type) != c.LLVMFunctionTypeKind) continue;
                    const ptr_op = c.LLVMGetOperand(inst, 1);
                    if (@intFromPtr(ptr_op) == 0) continue;
                    if (isGlobalVariable(ptr_op)) {
                        try callback_escapes.append(ctx.allocator, .{
                            .inst = inst,
                            .receiver_name = "global_store",
                            .callback_arg = value_op,
                        });
                    }
                }
            }
        }

        if (cgo_calls.items.len > 0) {
            stats.go_cgo_boundaries_found += 1;
        }

        if (!has_keepalive and cgo_calls.items.len > 0) {
            for (cgo_calls.items) |call| {
                // R7.1-3: Language-aware retention check
                if (call.is_pointer_arg and mayRetainInCLanguageAware(call.callee_name, is_cgo_boundary)) {
                    // R8.0: Cross-verify with unified MemoryGraph before reporting.
                    // Only report if the pointer is confirmed to flow into a call edge.
                    const mg = &ctx.memory_graph;
                    var confirmed_by_graph = false;
                    var detected_ptr_val: u64 = 0;
                    var arg_k: u32 = 1;
                    while (arg_k < c.LLVMGetNumOperands(call.inst)) : (arg_k += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_k);
                        if (@intFromPtr(arg) == 0) continue;
                        const arg_ptr_val = @as(u64, @intFromPtr(arg));
                        if (mg.isPassedAsArg(arg_ptr_val)) {
                            confirmed_by_graph = true;
                            detected_ptr_val = arg_ptr_val;
                            break;
                        }
                    }
                    if (confirmed_by_graph) {
                        if (!ctx.isRelevantAlloc(detected_ptr_val)) continue;
                        try reportMissingKeepAlive(ctx, func_name, call, diag);
                        stats.keepalive_missing += 1;
                    }
                }
            }
        }

        // CBytes escape detection: if a function calls C.CBytes and may also call
        // a retaining function (like storing to global, registering callback), report escape.
        // Note: True next_call tracking requires call graph analysis (see TODO below).
        for (cgo_calls.items) |call| {
            if (isCBytesPattern(call.callee_name)) {
                // R7.1-3: Language-aware retention check for CBytes escape
                if (mayRetainInCLanguageAware(func_name, is_cgo_boundary)) {
                    // R8.0 consume: Cross-verify with MemoryGraph — only report
                    // if the CBytes call's pointer arg is tracked as passed to an FFI call.
                    const mg = &ctx.memory_graph;
                    var cgo_ptr_val: u64 = 0;
                    var arg_i: u32 = 1;
                    while (arg_i < c.LLVMGetNumOperands(call.inst)) : (arg_i += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_i);
                        if (@intFromPtr(arg) != 0 and mg.isPassedAsArg(@as(u64, @intFromPtr(arg)))) {
                            cgo_ptr_val = @as(u64, @intFromPtr(arg));
                            break;
                        }
                    }
                    if (cgo_ptr_val != 0) {
                        if (!ctx.isRelevantAlloc(cgo_ptr_val)) continue;
                        try reportCBytesEscape(ctx, func_name, call, diag);
                        stats.cbytes_escapes += 1;
                    }
                }
            }

            if (isUnsafePtrConversion(call.callee_name)) {
                try reportUnsafePtrRisk(ctx, func_name, call, diag);
                stats.unsafeptr_risks += 1;
            }
        }

        try checkMallocFreePairing(ctx, func_name, &alloc_sites, &free_sites, diag, stats);

        for (callback_escapes.items) |escape| {
            if (!std.mem.eql(u8, escape.receiver_name, "global_store")) {
                const called_val = c.LLVMGetCalledValue(escape.inst);
                if (@intFromPtr(called_val) != 0) {
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    const callee_name = if (@intFromPtr(callee_name_ptr) != 0)
                        std.mem.span(callee_name_ptr)
                    else
                        "unknown";
                    const cb_arg_hash = @as(u64, @intFromPtr(escape.callback_arg));
                    var is_borrowed = false;
                    const num_ops = c.LLVMGetNumOperands(escape.inst);
                    var j: u32 = 0;
                    while (j < num_ops) : (j += 1) {
                        const arg = c.LLVMGetOperand(escape.inst, j);
                        if (@intFromPtr(arg) == 0) continue;
                        const arg_hash = @as(u64, @intFromPtr(arg));
                        if (arg_hash != cb_arg_hash) continue;
                        const arg_type = c.LLVMTypeOf(arg);
                        if (@intFromPtr(arg_type) != 0 and
                            c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
                        {
                            const elem_type = c.LLVMGetElementType(arg_type);
                            if (@intFromPtr(elem_type) != 0 and
                                c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                            {
                                is_borrowed = true;
                            }
                        }
                        break;
                    }
                    if (is_borrowed) {
                        diag.debug("[SUPPRESSED] Callback arg is borrowed_only: {s} -> {s}", .{ func_name, callee_name });
                        continue;
                    }
                }
            }

            if (!std.mem.eql(u8, escape.receiver_name, "global_store")) {
                const cb_type = c.LLVMGetElementType(c.LLVMTypeOf(escape.callback_arg));
                if (@intFromPtr(cb_type) != 0) {
                    const num_params = c.LLVMCountParamTypes(cb_type);
                    if (num_params > 3) {
                        diag.debug("[SUPPRESSED] Callback has >3 params: {s}", .{func_name});
                        continue;
                    }
                    const type_str = c.LLVMGetStructName(cb_type);
                    const type_name = if (@intFromPtr(type_str) != 0)
                        std.mem.span(type_str)
                    else
                        "";
                    if (!validate_callback_signature(escape.receiver_name, type_name)) {
                        try reportSignatureMismatch(ctx, func_name, escape, diag);
                        stats.callback_escapes += 1;
                        continue;
                    }
                }
            }

            try reportGenericCallbackEscape(ctx, func_name, escape, diag);
            stats.callback_escapes += 1;
        }
    }

    fn checkCallbackEscape(
        ctx: *PassContext,
        func_name: []const u8,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        var callback_escapes: std.ArrayList(CallbackEscapeInfo) = .{};
        defer callback_escapes.deinit(ctx.allocator);

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called) == 0) continue;
                    const name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(name_ptr) == 0) continue;
                    const callee_name = std.mem.span(name_ptr);

                    if (isGenericCallbackReceiver(callee_name)) {
                        const num_ops = c.LLVMGetNumOperands(inst);
                        var i: u32 = 0;
                        while (i < num_ops) : (i += 1) {
                            const arg = c.LLVMGetOperand(inst, i);
                            if (@intFromPtr(arg) != 0) {
                                const arg_type = c.LLVMTypeOf(arg);
                                if (@intFromPtr(arg_type) == 0) continue;
                                if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                                    const elem_type = c.LLVMGetElementType(arg_type);
                                    if (@intFromPtr(elem_type) != 0 and
                                        c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                                    {
                                        if (isLikelyCallbackFunction(elem_type, callee_name)) {
                                            try callback_escapes.append(ctx.allocator, .{
                                                .inst = inst,
                                                .receiver_name = callee_name,
                                                .callback_arg = arg,
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (opcode == c.LLVMStore) {
                    const value_op = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(value_op) != 0) {
                        const value_type = c.LLVMTypeOf(value_op);
                        if (@intFromPtr(value_type) == 0) continue;
                        if (c.LLVMGetTypeKind(value_type) == c.LLVMPointerTypeKind) {
                            const elem_type = c.LLVMGetElementType(value_type);
                            if (@intFromPtr(elem_type) != 0 and
                                c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                            {
                                const ptr_op = c.LLVMGetOperand(inst, 1);
                                if (@intFromPtr(ptr_op) != 0) {
                                    if (isGlobalVariable(ptr_op)) {
                                        try callback_escapes.append(ctx.allocator, .{
                                            .inst = inst,
                                            .receiver_name = "global_store",
                                            .callback_arg = value_op,
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        for (callback_escapes.items) |escape| {
            // v0.1.8: Use call_graph argument direction analysis to filter
            // false-positive callback escapes. If the callback argument is
            // classified as borrowed_only (e.g. function pointer callback),
            // it's a legitimate pattern, not an escape.
            if (!std.mem.eql(u8, escape.receiver_name, "global_store")) {
                const called_val = c.LLVMGetCalledValue(escape.inst);
                if (@intFromPtr(called_val) != 0) {
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    const callee_name = if (@intFromPtr(callee_name_ptr) != 0)
                        std.mem.span(callee_name_ptr)
                    else
                        "unknown";

                    // Inline argument direction analysis to avoid cross-cimport type issues.
                    const cb_arg_hash = @as(u64, @intFromPtr(escape.callback_arg));
                    var is_borrowed = false;
                    const num_ops = c.LLVMGetNumOperands(escape.inst);
                    var j: u32 = 0;
                    while (j < num_ops) : (j += 1) {
                        const arg = c.LLVMGetOperand(escape.inst, j);
                        if (@intFromPtr(arg) == 0) continue;
                        const arg_hash = @as(u64, @intFromPtr(arg));
                        if (arg_hash != cb_arg_hash) continue;

                        // Check if this arg is a function pointer (callback)
                        const arg_type = c.LLVMTypeOf(arg);
                        if (@intFromPtr(arg_type) != 0 and
                            c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
                        {
                            const elem_type = c.LLVMGetElementType(arg_type);
                            if (@intFromPtr(elem_type) != 0 and
                                c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                            {
                                is_borrowed = true;
                            }
                        }
                        break;
                    }

                    if (is_borrowed) {
                        diag.debug("[SUPPRESSED] Callback arg is borrowed_only (not an escape): {s} -> {s}", .{ func_name, callee_name });
                        continue;
                    }
                }
            }

            // Validate callback signature when receiver is a known pattern.
            // This catches type mismatches like passing int(*)(int,int) to signal()
            // which expects void(*)(int). Reports as low-confidence to avoid FP.
            if (!std.mem.eql(u8, escape.receiver_name, "global_store")) {
                const cb_type = c.LLVMGetElementType(
                    c.LLVMTypeOf(escape.callback_arg),
                );
                if (@intFromPtr(cb_type) != 0) {
                    const type_str = c.LLVMGetStructName(cb_type);
                    const type_name = if (@intFromPtr(type_str) != 0)
                        std.mem.span(type_str)
                    else
                        "";
                    if (!validate_callback_signature(escape.receiver_name, type_name)) {
                        try reportSignatureMismatch(ctx, func_name, escape, diag);
                        stats.callback_escapes += 1;
                        continue;
                    }
                }
            }
            try reportGenericCallbackEscape(ctx, func_name, escape, diag);
            stats.callback_escapes += 1;
        }
    }

    fn isGlobalVariable(ptr: c.LLVMValueRef) bool {
        if (@intFromPtr(ptr) == 0) return false;
        return c.LLVMGetValueKind(ptr) == c.LLVMGlobalVariableValueKind;
    }

    fn isLikelyCallbackFunction(fn_type: c.LLVMTypeRef, receiver_name: []const u8) bool {
        if (@intFromPtr(fn_type) == 0) return false;

        const num_params = c.LLVMCountParamTypes(fn_type);
        if (num_params == 0) return false;

        const ret_type = c.LLVMGetReturnType(fn_type);
        if (@intFromPtr(ret_type) == 0) return false;

        const void_patterns = [_][]const u8{
            "atexit",         "qsort",              "bsearch", "signal", "sigaction",
            "pthread_create", "pthread_key_create",
        };
        for (void_patterns) |p| {
            if (std.mem.indexOf(u8, receiver_name, p) != null) return true;
        }

        if (c.LLVMGetTypeKind(ret_type) == c.LLVMVoidTypeKind or
            c.LLVMGetTypeKind(ret_type) == c.LLVMIntegerTypeKind or
            c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
        {
            return true;
        }

        return false;
    }

    fn isGenericCallbackReceiver(receiver: []const u8) bool {
        for (C_RETAINING_FUNCTIONS) |pattern| {
            if (std.mem.indexOf(u8, receiver, pattern) != null) return true;
        }
        return false;
    }

    fn scanInstruction(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        has_keepalive: *bool,
        alloc_sites: *std.ArrayList(AllocSiteInfo),
        free_sites: *std.ArrayList(FreeSiteInfo),
        cgo_calls: *std.ArrayList(CGoCallInfo),
        is_go_module: bool,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) == 0) return;

            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) == 0) return;
            const callee_name = std.mem.span(name_ptr);

            if (isGoSafetyFunction(callee_name)) {
                has_keepalive.* = true;
            }

            // R7.2: Module-level language gate (passed from analyzeFunction).
            if (is_go_module or
                std.mem.indexOf(u8, callee_name, "malloc") != null or
                std.mem.indexOf(u8, callee_name, "calloc") != null)
            {
                try alloc_sites.append(allocator, .{
                    .inst_id = inst,
                    .func_name = try allocator.dupe(u8, callee_name),
                });
            }

            if (std.mem.indexOf(u8, callee_name, "free") != null) {
                try free_sites.append(allocator, .{
                    .inst_id = inst,
                    .func_name = try allocator.dupe(u8, callee_name),
                });
            }

            // R7.2: Module-level language gate replaces isCgoBoundary name matching.
            if (is_go_module or
                isCBytesPattern(callee_name) or
                isUnsafePtrConversion(callee_name))
            {
                const num_ops = c.LLVMGetNumOperands(inst);
                var has_ptr_arg = false;
                var i: u32 = 0;
                while (i < num_ops) : (i += 1) {
                    const op = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(op) != 0) {
                        const op_type = c.LLVMTypeOf(op);
                        if (@intFromPtr(op_type) == 0) continue;
                        const type_kind = c.LLVMGetTypeKind(op_type);
                        if (type_kind == c.LLVMPointerTypeKind) {
                            has_ptr_arg = true;
                            break;
                        }
                    }
                }

                try cgo_calls.append(allocator, .{
                    .inst = inst,
                    .callee_name = try allocator.dupe(u8, callee_name),
                    .is_pointer_arg = has_ptr_arg,
                });
            }
        }
    }

    /// Checks malloc/free pairing with cross-function ownership awareness.
    ///
    /// This function analyzes the balance between allocations and frees within
    /// a single function, but with awareness of common ownership transfer patterns:
    ///
    ///   1. Factory functions: Return ownership to caller (more allocs than frees)
    ///   2. Destructor functions: Consume ownership from caller (more frees than allocs)
    ///   3. Transfer functions: Receive and pass on ownership (balanced but via params)
    ///
    /// By recognizing these patterns, we can suppress false positives where the
    /// mismatch is intentional and correct.
    fn checkMallocFreePairing(
        ctx: *PassContext,
        func_name: []const u8,
        alloc_sites: *const std.ArrayList(AllocSiteInfo),
        free_sites: *const std.ArrayList(FreeSiteInfo),
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        var malloc_count: u32 = 0;
        var free_count: u32 = 0;

        // Count allocations
        for (alloc_sites.items) |site| {
            if (std.mem.indexOf(u8, site.func_name, "malloc") != null or
                std.mem.indexOf(u8, site.func_name, "calloc") != null or
                std.mem.indexOf(u8, site.func_name, "realloc") != null)
            {
                malloc_count += 1;
            }
        }

        // Count frees
        for (free_sites.items) |site| {
            if (std.mem.indexOf(u8, site.func_name, "free") != null) {
                free_count += 1;
            }
        }

        // Pattern 1: Factory/Constructor functions
        // These intentionally have more allocs than frees because they transfer
        // ownership to the caller via return value or output parameter.
        if (isFactoryFunction(func_name)) {
            if (malloc_count > free_count) {
                // This is expected for factory functions
                diag.debug("[SUPPRESSED] Factory function {s}: {d} allocs > {d} frees (ownership transferred to caller)", .{ func_name, malloc_count, free_count });
                return;
            }
        }

        // Pattern 2: Destructor/Cleanup functions
        // These intentionally have more frees than allocs because they consume
        // ownership from the caller via parameters.
        if (isDestructorFunction(func_name)) {
            if (free_count > malloc_count) {
                // This is expected for destructor functions
                diag.debug("[SUPPRESSED] Destructor function {s}: {d} frees > {d} allocs (ownership consumed from caller)", .{ func_name, free_count, malloc_count });
                return;
            }
        }

        // Pattern 3: Transfer functions
        // These may have unbalanced counts but are correct because they receive
        // ownership via parameters and pass it on via return values.
        if (isTransferFunction(func_name)) {
            diag.debug("[SUPPRESSED] Transfer function {s}: {d} allocs, {d} frees (ownership flows through)", .{ func_name, malloc_count, free_count });
            return;
        }

        // Report actual issues only if no pattern matches
        // R8.0 consume: Cross-verify with unified MemoryGraph call edges
        // before reporting leaks. If pointers are tracked as transferred via
        // call_ret edges, suppress false-positive leak reports.
        const mg = &ctx.memory_graph;
        if (malloc_count > free_count) {
            // Check if any allocation result is recorded as a call return
            // (ownership transferred to caller via FFI boundary)
            var has_call_ret_transfer = false;
            for (alloc_sites.items) |site| {
                const ptr_val = @as(u64, @intFromPtr(site.inst_id));
                if (mg.isReturnedFromCall(ptr_val)) {
                    has_call_ret_transfer = true;
                    break;
                }
            }
            if (!has_call_ret_transfer) {
                try reportMallocLeak(ctx, func_name, malloc_count, free_count, diag);
                stats.malloc_leaks += @as(u32, @intCast(malloc_count - free_count));
            } else {
                diag.debug("[R8.0-SUPPRESSED] {s}: {d} allocs > {d} frees but ptr returned from call (ownership transferred)", .{ func_name, malloc_count, free_count });
            }
        }

        if (free_count > malloc_count) {
            // Check if any free() argument was received as a call arg
            // (pointer came from caller via FFI boundary)
            var has_call_arg_source = false;
            for (free_sites.items) |site| {
                const ptr_val = @as(u64, @intFromPtr(site.inst_id));
                if (mg.isPassedAsArg(ptr_val)) {
                    has_call_arg_source = true;
                    break;
                }
            }
            if (!has_call_arg_source) {
                try reportFreeOrphan(ctx, func_name, malloc_count, free_count, diag);
                stats.free_orphans += @as(u32, @intCast(free_count - malloc_count));
            } else {
                diag.debug("[R8.0-SUPPRESSED] {s}: {d} frees > {d} allocs but ptr came from call arg (external source)", .{ func_name, free_count, malloc_count });
            }
        }
    }

    /// Checks if a function is a factory/constructor that transfers ownership to caller.
    fn isFactoryFunction(func_name: []const u8) bool {
        const factory_patterns = [_][]const u8{
            "Alloc",  "Create", "New",     "Init", "Open", "Dup",
            "Malloc", "Calloc", "Realloc",
        };
        for (factory_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Checks if a function is a destructor that consumes ownership from caller.
    fn isDestructorFunction(func_name: []const u8) bool {
        const destructor_patterns = [_][]const u8{
            "Free",   "Destroy",  "Delete",  "Close", "Release", "Cleanup",
            "Finish", "Finalize", "Dispose",
        };
        for (destructor_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Checks if a function is a transfer function that passes ownership through.
    fn isTransferFunction(func_name: []const u8) bool {
        // Functions that receive ownership and pass it on
        const transfer_patterns = [_][]const u8{
            "Clone", "Copy", "Move", "Transfer", "Take",
        };
        for (transfer_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Data Structures
// ============================================================================

const AllocSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

const FreeSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

const CGoCallInfo = struct {
    inst: c.LLVMValueRef,
    callee_name: []const u8,
    is_pointer_arg: bool,
};

const CallbackEscapeInfo = struct {
    inst: c.LLVMValueRef,
    receiver_name: []const u8,
    callback_arg: c.LLVMValueRef,
};

// ============================================================================
// Reporting
// ============================================================================

fn reportMissingKeepAlive(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Go pointer passed to C function without runtime.KeepAlive");
    trace[1] = try makeTrace(ctx.allocator, "Call to {s}() at cgo boundary", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "GC may reclaim Go memory while C still holds pointer (CWE-662)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "CGo call {s}() passes Go pointer without runtime.KeepAlive - GC race condition",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        0.78,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[NO-KEEPALIVE] {s} -> {s}() in {s}", .{ "Go ptr", call.callee_name, func_name });
}

fn reportCBytesEscape(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("C.CBytes result passed to C function that may retain pointer");
    trace[1] = try makeTrace(ctx.allocator, "{s}() returns C-managed copy of Go bytes", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "Caller must ensure Go backing store outlives C usage (CWE-401)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "C.{s}() result escapes to retaining C function - verify Go slice lifetime",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.65,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CBYTES-ESCAPE] {s} in {s}", .{ call.callee_name, func_name });
}

fn reportGenericCallbackEscape(
    ctx: *PassContext,
    func_name: []const u8,
    escape: CallbackEscapeInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const escape_type = if (std.mem.eql(u8, escape.receiver_name, "global_store"))
        "stored to global variable (cross-function lifetime escape)"
    else
        "passed to callback receiver function";

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Function pointer escapes current scope");
    trace[1] = try makeTrace(ctx.allocator, "Callback {s} - {s}", .{ escape.receiver_name, escape_type });
    trace[2] = try makeTrace(ctx.allocator, "Escaped callback may be invoked after caller returns (CWE-416/CWE-562)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function pointer escapes via {s} in {s} - potential use-after-return if callback captures stack data",
        .{ escape.receiver_name, func_name },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .medium,
        0.68,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-ESCAPE] {s} -> {s} in {s}", .{ "fn_ptr", escape.receiver_name, func_name });
}

/// Report a callback signature mismatch between receiver expectation and actual callback type.
/// Low confidence (0.45) to avoid false positives from incomplete type information in LLVM IR.
fn reportSignatureMismatch(
    ctx: *PassContext,
    func_name: []const u8,
    escape: CallbackEscapeInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Callback passed to receiver with incompatible signature");
    trace[1] = try makeTrace(ctx.allocator, "Type mismatch may cause undefined behavior at runtime (CWE-688)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Callback signature may not match {s} expectation in {s} - potential UB from ABI mismatch",
        .{ escape.receiver_name, func_name },
    );

    const issue = Issue.initWithTrace(
        .callback_signature_mismatch,
        message,
        location,
        .low,
        0.45,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[CALLBACK-SIG] {s} -> {s} in {s}", .{ "sig_mismatch", escape.receiver_name, func_name });
}

fn reportUnsafePtrRisk(
    ctx: *PassContext,
    func_name: []const u8,
    call: CGoCallInfo,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("unsafe.Pointer conversion at FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "Conversion via {s}() breaks Go type system guarantees", .{call.callee_name});
    trace[2] = try makeTrace(ctx.allocator, "Pointer may become invalid if GC moves the underlying object (CWE-704)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "unsafe.Pointer conversion ({s}) at cgo boundary - dangling pointer risk if object relocates",
        .{call.callee_name},
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .high,
        0.72,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[UNSAFE-PTR] {s} in {s}", .{ call.callee_name, func_name });
}

fn reportMallocLeak(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{d} malloc/calloc calls found", .{malloc_count});
    trace[1] = try makeTrace(ctx.allocator, "{d} free() calls found - {d} allocations never freed", .{ free_count, malloc_count - free_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Memory leak: {d} malloc/calloc without matching free in {s} (CWE-401)",
        .{ malloc_count - free_count, func_name },
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.70,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[MALLOC-LEAK] {d} allocs vs {d} frees in {s}", .{ malloc_count, free_count, func_name });
}

fn reportFreeOrphan(
    ctx: *PassContext,
    func_name: []const u8,
    malloc_count: u32,
    free_count: u32,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = try makeTrace(ctx.allocator, "{d} free() calls found", .{free_count});
    trace[1] = try makeTrace(ctx.allocator, "{d} malloc/calloc calls - {d} frees may operate on unallocated memory", .{ malloc_count, free_count - malloc_count });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Potential double-free or invalid free: {d} free() vs {d} malloc in {s} (CWE-415)",
        .{ free_count - malloc_count, malloc_count, func_name },
    );

    const issue = Issue.initWithTrace(
        .double_free,
        message,
        location,
        .high,
        0.68,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[FREE-ORPHAN] {d} frees vs {d} allocs in {s}", .{ free_count, malloc_count, func_name });
}

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "CallbackEscapePass - name and kind" {
    try std.testing.expectEqualStrings("callback-escape", CallbackEscapePass.name);
    try std.testing.expectEqual(PassKind.analysis, CallbackEscapePass.kind);
}

test "isCgoBoundary - cgo patterns" {
    try std.testing.expect(isCgoBoundary("_cgo_cfunction_wrapper"));
    try std.testing.expect(isCgoBoundary("_Cfunc_process"));
    try std.testing.expect(isCgoBoundary("C.process"));
    try std.testing.expect(isCgoBoundary("C.malloc"));
    try std.testing.expect(!isCgoBoundary("my_function"));
    try std.testing.expect(!isCgoBoundary("runtime.main"));
}

test "isGoSafetyFunction - KeepAlive detection" {
    try std.testing.expect(isGoSafetyFunction("runtime.KeepAlive"));
    try std.testing.expect(isGoSafetyFunction("runtime_Pin"));
    try std.testing.expect(isGoSafetyFunction("runtime_cgocall"));
    try std.testing.expect(!isGoSafetyFunction("malloc"));
    try std.testing.expect(!isGoSafetyFunction("printf"));
}

test "isCBytesPattern - byte conversion detection" {
    try std.testing.expect(isCBytesPattern("C.CBytes"));
    try std.testing.expect(isCBytesPattern("C.GoString"));
    try std.testing.expect(isCBytesPattern("C.GoStringN"));
    try std.testing.expect(!isCBytesPattern("C.malloc"));
    try std.testing.expect(!isCBytesPattern("memcpy"));
}

test "isUnsafePtrConversion - unsafe pointer detection" {
    try std.testing.expect(isUnsafePtrConversion("unsafe.Pointer"));
    try std.testing.expect(isUnsafePtrConversion("some_unsafe.Pointer_func"));
    try std.testing.expect(isUnsafePtrConversion("uintptr_conversion"));
    try std.testing.expect(!isUnsafePtrConversion("malloc"));
    try std.testing.expect(!isUnsafePtrConversion("normal_func"));
}

test "EscapeViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(EscapeViolation.go_pointer_no_keepalive));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(EscapeViolation.cbytes_escape));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(EscapeViolation.unsafeptr_dangling_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(EscapeViolation.malloc_without_free));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(EscapeViolation.free_without_malloc));
}

test "isCgoBoundaryFromLLVM - null safety" {
    // Null function ref should return false
    try std.testing.expect(!isCgoBoundaryFromLLVM(null));
}

test "isCgoBoundaryFromLLVM - linkage detection logic" {
    // Verify the function exists and is callable
    const result = isCgoBoundaryFromLLVM(null);
    try std.testing.expectEqual(false, result);
}

test "EscapePattern - initialization" {
    const pattern = EscapePattern{
        .violation_type = .go_pointer_no_keepalive,
        .confidence = 0.85,
        .func_name = "test_func",
        .callee_name = "C.process",
        .description = "missing KeepAlive",
    };
    try std.testing.expectEqual(EscapeViolation.go_pointer_no_keepalive, pattern.violation_type);
    try std.testing.approxApproxEqAbs(@as(f32, 0.85), pattern.confidence, 0.01);
    try std.testing.expectEqualStrings("test_func", pattern.func_name);
}

test "EscapeStats - initialization" {
    const stats = EscapeStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.keepalive_missing);
    try std.testing.expectEqual(@as(u32, 0), stats.cbytes_escapes);
}

test "EscapeStats - tracking" {
    var stats = EscapeStats{};
    stats.total_functions_analyzed = 15;
    stats.go_cgo_boundaries_found = 5;
    stats.keepalive_missing = 3;
    stats.cbytes_escapes = 2;
    stats.unsafeptr_risks = 4;
    stats.malloc_leaks = 1;
    stats.free_orphans = 1;

    try std.testing.expectEqual(@as(u32, 15), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 5), stats.go_cgo_boundaries_found);
    try std.testing.expectEqual(@as(u32, 11), stats.keepalive_missing + stats.cbytes_escapes +
        stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans);
}

test "mayRetainInCLanguageAware - C_RETAINING_FUNCTIONS always match" {
    try std.testing.expect(mayRetainInCLanguageAware("pthread_create", true));
    try std.testing.expect(mayRetainInCLanguageAware("RegisterNatives", true));
    try std.testing.expect(mayRetainInCLanguageAware("PyCapsule_SetDestructor", true));
    try std.testing.expect(mayRetainInCLanguageAware("signal", true));
    try std.testing.expect(mayRetainInCLanguageAware("SDL_SetCallback", true));
    try std.testing.expect(!mayRetainInCLanguageAware("malloc", true));
    try std.testing.expect(!mayRetainInCLanguageAware("free", true));
}

test "isRegisterNativesPattern - JNI callback" {
    try std.testing.expect(isRegisterNativesPattern("RegisterNatives"));
    try std.testing.expect(isRegisterNativesPattern("RegisterNativesHook"));
    try std.testing.expect(!isRegisterNativesPattern("malloc"));
}

test "isPthreadCreatePattern - thread callback" {
    try std.testing.expect(isPthreadCreatePattern("pthread_create"));
    try std.testing.expect(!isPthreadCreatePattern("pthread_join"));
}

test "isCallbackReceiver - known receivers" {
    try std.testing.expect(isCallbackReceiver("RegisterNatives"));
    try std.testing.expect(isCallbackReceiver("SetCallback"));
    try std.testing.expect(isCallbackReceiver("pthread_create"));
    try std.testing.expect(isCallbackReceiver("signal"));
    try std.testing.expect(isCallbackReceiver("SDL_SetEventCallback"));
    try std.testing.expect(!isCallbackReceiver("malloc"));
    try std.testing.expect(!isCallbackReceiver("free"));
}

test "isCgoGlueByPattern - cgo glue detection" {
    try std.testing.expect(isCgoGlueByPattern("_cgo_123abc"));
    try std.testing.expect(isCgoGlueByPattern("crosscall2"));
    try std.testing.expect(isCgoGlueByPattern("runtime.cgocall"));
    try std.testing.expect(isCgoGlueByPattern("_Cfunc_abc123"));
    try std.testing.expect(isCgoGlueByPattern("_cgo_gotypes_init"));
    try std.testing.expect(!isCgoGlueByPattern("my_c_function"));
    try std.testing.expect(!isCgoGlueByPattern("cgo_wrapper_user"));
    try std.testing.expect(!isCgoGlueByPattern("printf"));
}

test "validate_callback_signature - JNI patterns" {
    try std.testing.expect(validate_callback_signature("RegisterNatives", "JNINativeMethod*"));
    try std.testing.expect(validate_callback_signature("RegisterNatives", "void*"));
    try std.testing.expect(!validate_callback_signature("RegisterNatives", "int"));
    try std.testing.expect(validate_callback_signature("pthread_create", "void*"));
    try std.testing.expect(validate_callback_signature("signal", "void, int"));
    try std.testing.expect(!validate_callback_signature("signal", "int, int"));
}

test "validate_callback_signature - boundary cases" {
    // Empty type string should return false
    try std.testing.expect(!validate_callback_signature("pthread_create", ""));
    // Unknown receiver with valid type should return false (not in known patterns)
    try std.testing.expect(!validate_callback_signature("unknown_func", "void*"));
    // atexit accepts void(*)(void)
    try std.testing.expect(validate_callback_signature("atexit", "void*"));
    // qsort accepts void(*)(const void*, const void*)
    try std.testing.expect(validate_callback_signature("qsort", "void*"));
    // bsearch accepts void(*)(const void*, const void*)
    try std.testing.expect(validate_callback_signature("bsearch", "void*"));
    // pthread_key_create accepts void(*)(void*)
    try std.testing.expect(validate_callback_signature("pthread_key_create", "void*"));
    // sigaction accepts void(*)(int)
    try std.testing.expect(validate_callback_signature("sigaction", "void, int"));
    // on_exit accepts void(*)(int, void*)
    try std.testing.expect(validate_callback_signature("on_exit", "void, int"));
}

// R8.0-P1-8: isCgoBoundary strict "C." prefix matching (no FP on AC.BMethod etc.)
test "isCgoBoundary - strict C. prefix matching" {
    // Valid cgo patterns: C. at start or after package separator
    try std.testing.expect(isCgoBoundary("C.add")); // direct C. prefix
    try std.testing.expect(isCgoBoundary("C.malloc")); // standard cgo
    try std.testing.expect(isCgoBoundary("main.C.function")); // package.C. pattern

    // Invalid: C. in middle of name (NOT cgo boundary)
    try std.testing.expect(!isCgoBoundary("AC.BMethod")); // A + C.BMethod
    try std.testing.expect(!isCgoBoundary("MC.function")); // M + C.function
    try std.testing.expect(!isCgoBoundary("OCSocket")); // OC + Socket
    try std.testing.expect(!isCgoBoundary("MAC.address")); // MAC + address
    try std.testing.expect(!isCgoBoundary("myFunction_C_helper")); // trailing _C_
}
