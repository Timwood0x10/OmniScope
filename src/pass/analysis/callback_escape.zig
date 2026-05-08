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
//! Reference: /lang_ffi_analysis/go_ffi_fliter.md
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
const safe = @import("../../ir/llvm_safe.zig"); // Issue2/3: Standardized LLVM helpers
const word_boundary = @import("../../utils/word_boundary.zig");
// Issue2 FIX: Import helper for standardized CallInst argument counting
const getCallInstArgCount = @import("../../ir/llvm_safe.zig").getCallInstArgCount;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
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

// Reporting functions (extracted to separate module)
const cb_report = @import("callback_escape_report.zig");

// Re-export types from report module (used by both reporting and analysis code)
pub const CGoCallInfo = cb_report.CGoCallInfo;
pub const CallbackEscapeInfo = cb_report.CallbackEscapeInfo;

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

/// Enhanced Go cgo boundary patterns (v0.1.8)
/// Includes standard library, runtime, and common third-party patterns.
const CGO_ENHANCED_PATTERNS = &[_][]const u8{
    // Standard cgo glue (compiler-generated)
    "_cgo_",
    "_Cfunc_",
    "_cgo_gotypes",
    "crosscall2",

    // Go runtime cgo support
    "runtime_cgocall",
    "runtime_iscgo",
    "_cgo_runtime_cgocall",

    // Common Go package prefixes
    "golang_org.",
    "google.golang.org.",
    "github.com/",

    // Go-specific FFI patterns
    "__cgocallback",
    "cgoexp_",
    "_cgo_exp_",

    // JNI/Python interop via cgo
    "Java_", // cgo-JNI bridge
    "PyInit_", // cgo-Python bridge
    "Cython_", // cgo-Cython bridge
};

/// Go unsafe package patterns
const GO_UNSAFE_PATTERNS = &[_][]const u8{
    "unsafe.Pointer",
    "unsafe.String",
    "unsafe.Slice",
    "unsafe.SliceData",
    "unsafe.StringData",
    "Add",
    "Alignof",
    "Offsetof",
    "Sizeof",
};

/// Check if a function name indicates cgo boundary code.
pub fn isCgoBoundary(func_name: []const u8) bool {
    // First check enhanced patterns
    for (CGO_ENHANCED_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

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

/// Check if instruction involves Go unsafe operations
/// Enhanced with robust null safety and malformed IR protection
pub fn isGoUnsafeOperation(inst: c.LLVMValueRef) bool {
    // Safety check: ensure instruction is valid
    if (@intFromPtr(inst) == 0) return false;

    const called_val = c.LLVMGetCalledValue(inst);

    // Null safety: handle LLVM API failure gracefully
    if (@intFromPtr(called_val) == 0) {
        // Log debug info for malformed IR (optional, can be removed for performance)
        // std.log.debug("isGoUnsafeOperation: LLVMGetCalledValue returned null", .{});
        return false;
    }

    const callee_name_ptr = c.LLVMGetValueName(called_val);

    // Null safety: handle empty or invalid function names
    if (@intFromPtr(callee_name_ptr) == 0) {
        // std.log.debug("isGoUnsafeOperation: LLVMGetValueName returned null", .{});
        return false;
    }

    // Safe span conversion with length validation
    const callee_name = std.mem.span(callee_name_ptr);

    // Additional safety: skip empty names to prevent false positives
    if (callee_name.len == 0) return false;

    // Pattern matching with bounds checking
    for (GO_UNSAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }

    return false;
}

/// Detect Go-specific memory management patterns that may cause issues
pub fn detectGoMemoryPattern(func_name: []const u8) enum {
    /// Standard Go memory (GC-managed, safe)
    safe,
    /// Uses runtime.KeepAlive (properly guarded)
    keepalive_guarded,
    /// Missing KeepAlive (potential GC issue)
    missing_keepalive,
    /// Uses C.malloc/C.free directly (manual memory)
    manual_c_memory,
    /// Mixed pattern (complex analysis needed)
    mixed,
} {
    // Check for KeepAlive usage
    if (std.mem.indexOf(u8, func_name, "KeepAlive") != null)
        return .keepalive_guarded;

    // Check for direct C memory functions
    const has_malloc = std.mem.indexOf(u8, func_name, "C.malloc") != null or
        std.mem.indexOf(u8, func_name, "C.calloc") != null;
    const has_free = std.mem.indexOf(u8, func_name, "C.free") != null;

    if (has_malloc and has_free) return .manual_c_memory;
    if (has_malloc or has_free) return .mixed;

    // Default to safe for pure Go code
    return .safe;
}

/// Checks if a function name provides sufficient Go-specific evidence to be
/// considered a cgo boundary function.
///
/// This helper consolidates the three-tier Go evidence check used across multiple
/// linkage type validations in isCgoBoundaryFromLLVM():
///   1. Known cgo glue patterns (isCgoGlueByPattern)
///   2. Go runtime prefix (_cgo_)
///   3. Go callback marker (__cgocallback)
///
/// Using this single function ensures consistency and reduces maintenance overhead.
/// If the evidence requirements change, only this one place needs updating.
///
/// Arguments:
///   func_name - The LLVM function name to check
///
/// Returns:
///   true if the function name contains Go-specific cgo evidence
fn hasCgoEvidence(func_name: []const u8) bool {
    return isCgoGlueByPattern(func_name) or
        std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "__cgocallback") != null;
}

/// Unified CGO boundary detection by LLVM linkage type and name evidence.
///
/// Consolidates all cgo boundary checks into a single helper that:
///   1. Checks if the linkage type is one of the known cgo linkage types
///      (ExternalWeak, Common, External, WeakAny/ODR, LinkOnceAny/ODR)
///   2. Requires additional Go-specific evidence for non-obvious linkages
///      (prevents false positives in non-Go projects)
///
/// This replaces the duplicated logic previously in isCgoBoundaryFromLLVM()
/// where each linkage type had its own copy of the evidence check.
///
/// Arguments:
///   linkage - The LLVM linkage type of the function
///   func_name - The function name to check for Go patterns
///
/// Returns:
///   true if the function should be treated as a cgo boundary
fn isCgoBoundaryByLinkage(linkage: c.LLVMLinkage, func_name: []const u8) bool {
    // All these linkage types are commonly used in cgo glue code,
    // but can also appear in non-Go projects (e.g., weak symbols, COMDAT).
    // Therefore, we require additional Go-specific evidence to reduce false positives.
    const is_cgo_linkage = (linkage == c.LLVMExternalWeakLinkage or
        linkage == c.LLVMCommonLinkage or
        linkage == c.LLVMExternalLinkage or
        linkage == c.LLVMWeakAnyLinkage or
        linkage == c.LLVMWeakODRLinkage or
        linkage == c.LLVMLinkOnceAnyLinkage or
        linkage == c.LLVMLinkOnceODRLinkage);

    return is_cgo_linkage and hasCgoEvidence(func_name);
}

/// Check if a function is a cgo boundary using LLVM metadata.
///
/// Uses LLVM linkage type and declaration status to identify
/// compiler-generated cgo glue functions more precisely than string matching.
///
/// Delegates to isCgoBoundaryByLinkage() for all declaration-based checks,
/// ensuring consistent evidence requirements across all linkage types.
pub fn isCgoBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    if (func == null) return false;

    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return false;
    const func_name = std.mem.span(func_name_ptr);

    if (c.LLVMIsDeclaration(func) != 0) {
        // Unified check: all cgo-relevant linkage types + Go evidence
        const linkage = c.LLVMGetLinkage(func);
        if (isCgoBoundaryByLinkage(linkage, func_name)) return true;
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
/// Uses word boundary matching to prevent false positives from names like
/// "myCBytesHandler" or "CBytesUtils".
///
/// V2 ENHANCEMENT: Now also supports data flow verification via CallGraph.
/// Use `isCBytesEscapeWithDataFlow()` for more precise detection that checks
/// whether the CBytes return value actually reaches a retaining FFI call.
pub fn isCBytesPattern(name: []const u8) bool {
    // Use word boundary for precise matching (not substring)
    return word_boundary.isWordBoundaryMatch(name, "C.CBytes") or
        word_boundary.isWordBoundaryMatch(name, "C.GoString") or
        word_boundary.isWordBoundaryMatch(name, "C.GoStringN");
}

/// Enhanced CBytes escape detection with data flow analysis.
///
/// This V2 function combines:
/// 1. Name-based pattern matching (isCBytesPattern) - fast pre-filter
/// 2. Data flow verification via MemoryGraph - confirms return value is used in FFI context
///
/// When to use:
///   - Use this instead of isCBytesPattern() when you have access to ctx (PassContext)
///   - Provides fewer false positives than name-only checking
///
/// Example of false positive avoided by data flow check:
/// ```go
/// func safeUsage() {
///     buf := C.CBytes("hello")  // Matches pattern ✓
///     defer C.free(unsafe.Pointer(buf))  // Properly freed, NOT an escape ✗
/// }
/// ```
/// vs true positive:
/// ```go
/// func dangerousUsage() {
///     buf := C.CBytes("hello")  // Matches pattern ✓
///     C.storeGlobally(buf)      // Retained by C code → ESCAPE ✓
/// }
/// ```
pub fn isCBytesEscapeWithDataFlow(
    callee_name: []const u8,
    ptr_val: u64,
    ctx: *const PassContext,
) bool {
    // Step 1: Fast pre-filter by name (avoids expensive graph traversal for non-CBytes calls)
    if (!isCBytesPattern(callee_name)) return false;

    // Step 2: Check if the pointer value is tracked as passed to any FFI call
    // This uses MemoryGraph's cross-function tracking to verify actual data flow
    const mg = &ctx.memory_graph;

    // Check if this pointer is passed as argument to any external/FFI function
    if (mg.isPassedAsArg(ptr_val)) {
        // The pointer from C.Bytes is actually used in a call → potential escape
        return true;
    }

    // Step 3: Check if pointer is stored to global (another form of escape)
    if (mg.isStoredToGlobal(ptr_val)) {
        return true;
    }

    // Name matched but no data flow evidence found → likely safe usage
    return false;
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
    pub const deps = &[_][]const u8{ "call-graph", "danger-surface" };

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

            // v0.1.7: Three-layer noise reduction (supersedes zone-only check)
            const debug_file_path = extractDebugFilePath(func);
            const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // Defense-in-depth: known FP whitelist (v0.1.7 audit verified)
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

        // Track per-call-site KeepAlive protection.
        // Key: pointer value (u64), Value: void
        // This allows precise tracking of which specific pointers are protected,
        // preventing false negatives when some pointers have KeepAlive but others don't.
        var keepalive_protected = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer keepalive_protected.deinit();
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
                try scanInstruction(ctx.allocator, inst, &keepalive_protected, &alloc_sites, &free_sites, &cgo_calls, &callback_escapes, ctx.isGoModule());
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

        if (cgo_calls.items.len > 0) {
            // Per-call-site KeepAlive protection check.
            // Only report missing KeepAlive for pointers that are NOT protected.
            for (cgo_calls.items) |call| {
                // Check if ANY pointer argument to this call has KeepAlive protection.
                // A CGO call is considered "protected" if at least one of its pointer
                // arguments was explicitly passed to runtime.KeepAlive().
                //
                // This handles cases like:
                //   C.useData(ptr1, ptr2)  where only KeepAlive(ptr2) is called
                //   → The call is still considered protected (ptr2 is the critical one)
                var is_this_call_protected = false;
                {
                    // H13 FIX: For CallInst, operand (num_ops-1) is the callee, NOT operand 0.
                    // Issue2 FIX: Use standardized helper to avoid inconsistency across files.
                    const num_args = getCallInstArgCount(call.inst);
                    var arg_i: u32 = 0;
                    while (arg_i < num_args) : (arg_i += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_i);
                        if (@intFromPtr(arg) != 0) {
                            const arg_type = c.LLVMTypeOf(arg);
                            if (@intFromPtr(arg_type) != 0 and c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                                const ptr_val = @as(u64, @intFromPtr(arg));
                                if (keepalive_protected.contains(ptr_val)) {
                                    is_this_call_protected = true;
                                    // Don't break — continue checking remaining args
                                    // (though we already know it's protected)
                                }
                            }
                        }
                    }
                    // Note: We intentionally check ALL pointer arguments, not just the first.
                    // This ensures comprehensive coverage for multi-pointer CGO calls.
                }

                if (!is_this_call_protected and call.is_pointer_arg and mayRetainInCLanguageAware(call.callee_name, is_cgo_boundary)) {
                    // R8.0: Cross-verify with unified MemoryGraph before reporting.
                    // Only report if the pointer is confirmed to flow into a call edge.
                    const mg = &ctx.memory_graph;
                    var confirmed_by_graph = false;
                    var detected_ptr_val: u64 = 0;
                    // Issue2/3 FIX: Use standardized helper for consistent arg iteration
                    const num_args_keepalive = safe.getCallInstArgCount(call.inst);
                    var arg_k: u32 = 0;
                    while (arg_k < num_args_keepalive) : (arg_k += 1) {
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
                    // Issue2/3 FIX: Use standardized helper for consistent arg iteration
                    const cgo_num_args = safe.getCallInstArgCount(call.inst);
                    var arg_i: u32 = 0;
                    while (arg_i < cgo_num_args) : (arg_i += 1) {
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
                    // BUG-FIX-8: LLVMGetStructName returns null for function types.
                    // When type_name is empty, skip signature mismatch check
                    // and proceed to generic callback escape detection.
                    const type_str = c.LLVMGetStructName(cb_type);
                    const type_name = if (@intFromPtr(type_str) != 0)
                        std.mem.span(type_str)
                    else
                        "";
                    if (type_name.len > 0 and !validate_callback_signature(escape.receiver_name, type_name)) {
                        try reportSignatureMismatch(ctx, func_name, escape, diag);
                        stats.callback_escapes += 1;
                        continue;
                    }
                    // Issue1 fix: Debug log when type_name is empty (function type)
                    if (type_name.len == 0) {
                        diag.debug("[CALLBACK] Skipping signature check for function type: {s}", .{func_name});
                    }
                }
            }

            // E2-2c: Indirect escape via alias closure — check if the callback
            // argument's aliases reach FFI boundaries through memory graph.
            try reportCallbackWithAliasCheck(ctx, func_name, escape, diag);
            stats.callback_escapes += 1;
        }
    }

    /// E2-2c: Report callback escape with alias-closure FFI detection.
    /// Extracted from two identical call sites (analyzeFunction + checkCallbackEscape)
    /// to eliminate code duplication. Null-safe: null callback_arg reports with
    /// base confidence (no FFI boost).
    fn reportCallbackWithAliasCheck(
        ctx: *PassContext,
        func_name: []const u8,
        escape: CallbackEscapeInfo,
        diag: *DiagnosticWriter,
    ) !void {
        const indirect_escape = if (@intFromPtr(escape.callback_arg) == 0) false else ctx.isOnDangerPathFull(@intFromPtr(escape.callback_arg));
        try reportGenericCallbackEscape(ctx, func_name, escape, diag, indirect_escape);
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
            // v0.1.7: Use call_graph argument direction analysis to filter
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
            try reportCallbackWithAliasCheck(ctx, func_name, escape, diag);
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
        keepalive_protected: *std.AutoHashMap(u64, void),
        alloc_sites: *std.ArrayList(AllocSiteInfo),
        free_sites: *std.ArrayList(FreeSiteInfo),
        cgo_calls: *std.ArrayList(CGoCallInfo),
        callback_escapes: *std.ArrayList(CallbackEscapeInfo),
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
                // Record which pointer is protected by this KeepAlive call.
                // runtime.KeepAlive(ptr) takes one argument: the pointer to protect.
                if (c.LLVMGetNumOperands(inst) >= 2) {
                    const protected_ptr = c.LLVMGetOperand(inst, 1);
                    if (@intFromPtr(protected_ptr) != 0) {
                        const ptr_val = @as(u64, @intFromPtr(protected_ptr));
                        // Propagate allocation failure rather than silently ignoring.
                        // OOM here would indicate system resource exhaustion, which should
                        // be reported to the caller for proper error handling.
                        try keepalive_protected.put(ptr_val, {});
                    }
                }
            }

            // R7.2: Module-level language gate (passed from analyzeFunction).
            // Use word boundary matching to prevent false positives like "dmalloc" or "calfree"
            if (is_go_module or
                word_boundary.isWordBoundaryMatch(callee_name, "malloc") or
                word_boundary.isWordBoundaryMatch(callee_name, "calloc"))
            {
                try alloc_sites.append(allocator, .{
                    .inst_id = inst,
                    .func_name = try allocator.dupe(u8, callee_name),
                });
            }

            if (word_boundary.isWordBoundaryMatch(callee_name, "free")) {
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

        // A1-3/B3: Detect alloca (stack allocation) passed to FFI boundary.
        // Stack addresses become dangling when the FFI callee stores them
        // and accesses them after the caller returns.
        if (opcode == c.LLVMAlloca) {
            var alloca_use = c.LLVMGetFirstUse(inst);
            while (@intFromPtr(alloca_use) != 0) : (alloca_use = c.LLVMGetNextUse(alloca_use)) {
                const user = c.LLVMGetUser(alloca_use);
                if (@intFromPtr(user) == 0) continue;
                const user_opcode = c.LLVMGetInstructionOpcode(user);
                if (user_opcode == c.LLVMCall or user_opcode == c.LLVMInvoke) {
                    const called_val = c.LLVMGetCalledValue(user);
                    if (@intFromPtr(called_val) == 0) continue;
                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(called_name_ptr) == 0) continue;
                    const called_name = std.mem.span(called_name_ptr);
                    const callee_lang = lang_classifier.identifyCalleeLanguage(called_name);
                    if (callee_lang != .unknown) {
                        try callback_escapes.append(allocator, .{
                            .inst = user,
                            .receiver_name = called_name,
                            .callback_arg = inst,
                        });
                    }
                }
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

        // Count allocations (using word boundary matching for consistency)
        for (alloc_sites.items) |site| {
            if (word_boundary.isWordBoundaryMatch(site.func_name, "malloc") or
                word_boundary.isWordBoundaryMatch(site.func_name, "calloc") or
                word_boundary.isWordBoundaryMatch(site.func_name, "realloc"))
            {
                malloc_count += 1;
            }
        }

        // Count frees
        for (free_sites.items) |site| {
            if (word_boundary.isWordBoundaryMatch(site.func_name, "free")) {
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

// Re-export reporting functions from callback_escape_report.zig
pub const reportMissingKeepAlive = cb_report.reportMissingKeepAlive;
pub const reportCBytesEscape = cb_report.reportCBytesEscape;
pub const reportGenericCallbackEscape = cb_report.reportGenericCallbackEscape;
pub const reportSignatureMismatch = cb_report.reportSignatureMismatch;
pub const reportUnsafePtrRisk = cb_report.reportUnsafePtrRisk;
pub const reportMallocLeak = cb_report.reportMallocLeak;
pub const reportFreeOrphan = cb_report.reportFreeOrphan;
pub const makeTrace = cb_report.makeTrace;

// Tests are in callback_escape_test.zig (imported to run tests)
const _tests = @import("callback_escape_test.zig");
