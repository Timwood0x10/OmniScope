//! FFI Boundary Detection Pass (Orchestrator)
//!
//! This file has been refactored from 1601 lines to <200 lines by extracting:
//! - Zone classification → ffi_zone_check.zig
//! - Core boundary checks → ffi_boundary_check.zig
//! - Noise filtering → ffi_noise_filter.zig
//!
//! This orchestrator coordinates the analysis pipeline and delegates
//! to specialized modules for detailed implementation.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const builtin = @import("builtin");

/// Compile-time debug flag: true only in Debug builds.
/// All verbose diagnostic logging below is eliminated by the compiler
/// in Release/ReleaseFast/Safe modes (zero runtime overhead).
const ffi_debug = builtin.mode == .Debug;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../diag/issue.zig").Severity;
const FFIBoundary = @import("../../diag/issue.zig").FFIBoundary;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const BoundaryKind = @import("../../diag/issue.zig").FFIBoundary.BoundaryKind;

const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../../registry/semantic_registry.zig").FunctionSemantics;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;
const Severity = @import("../../registry/semantic_registry.zig").Severity;

// Extracted modules (refactored from this file)
const zone_check = @import("ffi_zone_check.zig");
const boundary_check = @import("ffi_boundary_check.zig");
const noise_filter = @import("ffi_noise_filter.zig");

// Zone classifier for R7.0 Zone-First architecture
const zone_classifier = @import("../../semantics/zone_classifier.zig");

// Existing extracted modules
const type_checker = @import("ffi_type_checker.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const safety_checker = @import("ffi_safety_checker.zig");
const NoiseReduction = @import("noise_reduction.zig");
const ip_ffi = @import("ip_ffi.zig");
const severity_rules = @import("severity_rules.zig");

// Re-export types for backward compatibility
const ffi_types = @import("ffi_types.zig");
pub const FFIBoundaryError = ffi_types.FFIBoundaryError;
pub const FFIBoundaryStats = ffi_types.FFIBoundaryStats;
pub const AnalyzeResult = ffi_types.AnalyzeResult;

/// Re-export zone check functions for backward compatibility.
/// New code should import from ffi_zone_check.zig directly.
pub const is_zig_internal_function = zone_check.isZigInternalFunction;
pub const is_zig_safe_cimport = zone_check.isZigSafeCimport;
pub const is_go_internal_function = zone_check.isGoInternalFunction;
pub const is_dangerous_pattern = zone_check.isDangerousPattern;
pub const is_likely_intentional_pattern = zone_check.isLikelyIntentionalPattern;

/// Re-export language detection functions for backward compatibility.
/// New code should import from ffi_zone_check.zig directly.
pub const identifyLanguage = zone_check.identifyLanguage;
pub const identifyCalleeLanguage = zone_check.identifyCalleeLanguage;
pub const classifyBoundaryKind = zone_check.classifyBoundaryKind;
pub const classifyBoundaryKindEnhanced = zone_check.classifyBoundaryKindEnhanced;

/// Re-export FFI pattern detection functions for backward compatibility.
/// New code should import from ffi_zone_check.zig directly.
pub const isLibcFunction = zone_check.isLibcFunction;
pub const isDynamicLoadingFunction = zone_check.isDynamicLoadingFunction;
pub const isJNIFunction = zone_check.isJNIFunction;
pub const isPythonCApiFunction = zone_check.isPythonCApiFunction;

/// Re-export boundary check utility functions for backward compatibility.
/// New code should import from ffi_boundary_check.zig directly.
pub const checkNullGuard = boundary_check.checkNullGuard;
pub const checkOwnershipChain = boundary_check.checkOwnershipChain;
pub const riskKindToIssueKind = boundary_check.riskKindToIssueKind;
pub const demangleRustName = boundary_check.demangleRustName;

/// Re-export severity mapping for backward compatibility.
/// New code should import from ffi_safety_checker.zig directly.
pub const registrySeverityToIssueSeverity = safety_checker.registrySeverityToIssueSeverity;

/// FFI boundary detection pass (orchestrator).
///
/// Coordinates the analysis pipeline and delegates to specialized modules.
/// Detection strategy:
/// - Analyzes function calls in the IR
/// - Classifies calls based on naming conventions and linkage
/// - Identifies language boundaries (e.g., Rust->C, Zig->C)
/// - Creates FFIBoundary entries in DataFlowGraph
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{ "call-graph", "danger-surface" };

    /// Run the FFI boundary detection pass (Pass interface requirement).
    /// Delegates to analyze() for actual implementation.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // R8.2-c: Consume cross-language edges from CallGraphPass.
        const cross_edges = ctx.getCrossLangEdges();
        if (cross_edges.len > 0) {
            diag.info("FFIBoundary: consuming {} cross-language edges from CallGraph", .{cross_edges.len});
        }

        // Diagnostic counters for understanding why issues are/aren't generated
        var total_funcs: u32 = 0;
        var skipped_irrelevant: u32 = 0;
        var issues_generated: u32 = 0;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) == 0) {
                total_funcs += 1;
                // P0-2: Function-level gate — skip functions with no danger-surface-relevant pointers.
                // EXCEPTION: Always analyze JNI_*/Java_/Py_* functions for FFI boundary detection,
                // even if DangerSurfacePass didn't mark them as relevant (indirect calls via function
                // pointers may not be detected by surface analysis).
                const func_name_ptr = c.LLVMGetValueName(func);
                const func_name = if (@intFromPtr(func_name_ptr) != 0)
                    std.mem.span(func_name_ptr)
                else
                    "unknown";
                const is_ffi_boundary_func = (std.mem.indexOf(u8, func_name, "JNI_") != null or
                    std.mem.indexOf(u8, func_name, "Java_") != null or
                    std.mem.startsWith(u8, func_name, "Py_")); // Python C API functions use Py_ prefix (e.g., Py_Init, Py_BuildValue)

                if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func))) and !is_ffi_boundary_func) {
                    skipped_irrelevant += 1;
                    continue;
                }
                const result = try @This().analyze(ctx, func, diag);
                issues_generated += result.count;
            }
        }

        diag.info("FFIBoundary: {d}/{d} funcs analyzed, {d} skipped (irrelevant), {d} issues generated", .{
            total_funcs - skipped_irrelevant, total_funcs, skipped_irrelevant, issues_generated,
        });
    }

    /// Analyze a single function for FFI boundaries.
    ///
    /// R7.0 Zone-First Architecture:
    ///   Phase 0: Classify zone → gate on .safe/.runtime_internal (skip entirely)
    ///   Phase 1: Noise reduction (secondary filter for edge cases)
    ///   Phase 2: FP whitelist (defense-in-depth, will be migrated into zone)
    ///   Phase 3: Scan call instructions with zone-aware analysis
    pub fn analyze(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{};

        // Get function name for logging
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        // Phase 0: Zone-First Classification (R7.0)
        const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);

        if (!PassContext.shouldAnalyzeZone(zone)) {
            diag.debug("ZONE-SKIP [{s}]: {s}", .{ @tagName(zone), func_name });
            return result;
        }
        diag.debug("ZONE-ANALYZE [{s}]: {s}", .{ @tagName(zone), func_name });

        // Phase 0.5: Language Channel Gate (R7.2)
        // Activate the correct rules channel based on module-level language detection.
        // This replaces per-pass language adaptation with a centralized channel system.
        const lang_channel = ctx.channelFFIBoundary();
        if (lang_channel == .skip) {
            diag.debug("LANG-SKIP [ffi_boundary]: {s} (module is {s})", .{
                func_name,
                @tagName(ctx.getModuleLanguage().language),
            });
            return result;
        }
        diag.debug("LANG-CHANNEL [ffi_boundary/{s}]: {s}", .{
            @tagName(lang_channel), func_name,
        });

        // Phase 1: Quick classification using noise reduction engine.
        const classification = NoiseReduction.classifyFunction(
            func_name,
            null,
            .{},
        );

        if (classification.weight == .ignored) {
            diag.debug("SKIP [NOISE]: {s} ({s})", .{ func_name, classification.origin.toString() });
            return result;
        }

        // Phase 2 (REMOVED in R7.0): FP whitelist was here.
        // All 18 FPWhitelist patterns have been migrated into zone_classifier:
        //   - Cat 1 (10x LLVM intrinsics) → llvm.* prefix → .runtime_internal
        //   - Cat 2 (7x Rust stdlib)    → RUST_SAFE_PATTERNS → .safe
        //   - Cat 3 (2x project-specific)→ C_INTERNAL_PATTERNS → .runtime_internal
        // Zone-First gate (Phase 0) now handles all of these before reaching here.

        // Phase 3: Scan all call instructions for FFI boundaries (zone-aware)
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    if (try checkCallForFFI(ctx, inst, func, diag, &result, zone)) {
                        result.count += 1;
                    }
                }
            }
        }
        return result;
    }

    /// Check a call instruction for FFI boundary (delegates to boundary_check module).
    ///
    ///  Zone-aware — uses caller's zone to make informed decisions about
    /// whether to report, reducing false positives from safe-zone functions
    /// calling into runtime internals.
    fn checkCallForFFI(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *AnalyzeResult,
        caller_zone: zone_classifier.ZoneKind,
    ) !bool {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        // Get function name (or resolve indirect call target)
        var called_name: []const u8 = "";

        const called_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) != 0) {
            called_name = std.mem.span(called_name_ptr);
        }

        // DEBUG: Log every call instruction analyzed
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";
        // DEBUG (compile-time eliminated in Release builds): Log JNI calls
        // Guard: only log when we have a valid name from LLVM (not empty/default)
        if (ffi_debug and @intFromPtr(called_name_ptr) != 0 and called_name.len > 0 and
            std.mem.indexOf(u8, called_name, "JNI_") != null)
        {
            _ = diag.info("CHECKING-CALL: {s} -> {s} (isFn={})", .{
                caller_name,
                called_name,
                @intFromPtr(c.LLVMIsAFunction(called_val)) != 0,
            });
        }

        // ═══ INDIRECT CALL RESOLUTION (JNI / vtable pattern) ═══
        // LLVM IR pattern for JNI indirect calls:
        //   %gep = getelementptr %struct.JNINativeInterface, %struct.JNINativeInterface* %env_tbl, i32 0, i32 <FIELD_IDX>
        //   %fn_ptr = load <func_type>, <func_type>** %gep
        //   %result = call <ret_type> %fn_ptr(args...)   ← called_val is %fn_ptr (not a function)
        // For indirect calls (called_val is not a function), trace back through
        // load → GEP to identify the struct field index and map to known patterns.
        //
        // IMPORTANT: resolved indirect names must be heap-allocated because
        // called_name_buf is stack-local and will be invalidated when this
        // function returns. The zone_cache HashMap stores slices by pointer,
        // so stack slices would cause use-after-free or duplicate-key crashes.
        //
        // Memory safety guarantee:
        //   - indirect_name_owned is null until successful allocation (L290)
        //   - defer ensures cleanup on ALL exit paths (normal return, error return, early return)
        //   - When indirect_name_owned is null, the if-guard prevents double-free
        //   - All 8+ early-return paths are covered (safe zone, runtime internal,
        //     STL filter, same-language, low-confidence, intentional, Zig, normal)
        var indirect_name_owned: ?[]u8 = null;
        defer if (indirect_name_owned) |owned| ctx.allocator.free(owned);
        var is_indirect_call = false;

        const is_indirect = (called_name.len == 0 or
            called_name[0] == '%' or // LLVM register (e.g., %11)
            c.LLVMIsAFunction(called_val) == null or
            c.LLVMIsAConstantExpr(called_val) != null); // Constant expr wrapping function pointer (inttoptr, bitcast, etc.)
        if (is_indirect) {
            const resolved = resolveIndirectCallTarget(inst, diag);
            if (resolved.len > 0) {
                indirect_name_owned = try ctx.allocator.dupe(u8, resolved);
                // try guarantees non-null, but assert for defensive programming (Debug builds only)
                std.debug.assert(indirect_name_owned != null);
                called_name = indirect_name_owned.?;
                is_indirect_call = true;
            } else {
                // Cannot resolve — skip this call with diagnostic context
                // (Debug builds log the specific failure reason inside resolveIndirectCallTarget)
                if (ffi_debug) {
                    const inst_text = c.LLVMPrintValueToString(inst);
                    defer c.LLVMDisposeMessage(inst_text);
                    diag.info("INDIRECT-SKIP: unresolved call '{s}' in {s}", .{
                        std.mem.span(inst_text), caller_name,
                    });
                }
                return false;
            }
        }

        // Check if it's a known risky function via Semantic Registry
        // (Same zone_cache concern for indirect calls — use direct lookup)
        const semantics = if (is_indirect_call)
            SemanticRegistry.lookup(called_name)
        else
            ctx.cachedRegistryLookup(called_name);
        const is_dangerous = semantics != null;

        // ═══ R7.0 Zone-Aware Filtering ═══
        // Replace scattered whitelist logic with unified zone classification.

        // Classify the callee's zone for zone-aware decisions (cached)
        // NOTE: For indirect calls (resolved via GEP field index), we skip the
        // zone_cache because each resolution creates a new heap allocation with
        // a different address. StringHashMap would see these as different keys
        // (even though content is identical), causing duplicate-key crashes.
        const callee_zone = if (is_indirect_call)
            zone_classifier.classifyFunction(called_name, null)
        else
            ctx.getOrComputeZoneByName(called_name);

        // If callee is safe or runtime internal → no FFI boundary risk from this call.
        // This replaces: ffi_noise_filter.isSafeLibcPattern (15 entries),
        //                ffi_noise_filter.isCppAbiInternalFunction,
        //                ffi_noise_filter.isCppOperatorPattern,
        //                and most of FPWhitelist's 18 entries.
        switch (callee_zone) {
            .safe => return false,
            .runtime_internal => {
                // Runtime internal functions are only risky if they're known-dangerous
                // (e.g., command_exec). For normal stdlib calls, skip.
                if (semantics) |sem| {
                    if (sem.kind != .command_exec and sem.kind != .unchecked_copy) {
                        return false;
                    }
                } else {
                    return false;
                }
            },
            .unknown, .ffi, .unsafe => {},
        }

        // Legacy noise filter for edge cases not covered by zone classifier.
        if (is_dangerous) {
            if (noise_filter.isStlInternalFunction(caller_name)) {
                return false;
            }
        }

        // Identify languages of caller and callee
        const caller_lang = zone_check.identifyLanguage(caller_func);
        var callee_lang = zone_check.identifyCalleeLanguage(called_name);

        // R8.2-c: Check if this call matches a pre-computed cross-language edge.
        // CallGraphPass may have detected language differences that our per-call
        // heuristics missed (e.g., external functions with ambiguous names).
        var cross_edge_matched = false;
        if (ctx.getCrossEdgeByCallee(called_name)) |cross| {
            if (cross.is_ffi_boundary) {
                cross_edge_matched = true;
                if (cross.callee_lang != .unknown and callee_lang == .unknown) {
                    callee_lang = cross.callee_lang;
                }
            }
        }

        // Skip same-language calls (not FFI boundaries)
        if (!cross_edge_matched and caller_lang != .unknown and callee_lang != .unknown and
            caller_lang == callee_lang)
        {
            return false;
        }

        // P1 FIX: Skip C↔C++ bridge calls (same language family).
        // C calling C++ (or vice versa) is NOT a dangerous FFI boundary —
        // they share the same memory model (malloc/free, new/delete), same ABI
        // conventions, and same runtime (libc). The only real risk is
        // cross-allocator mismatches (malloc+delete, new+free), which are
        // already handled by FreeValidationPass.isCrossAllocatorFree().
        // Reporting every C→C++ call as "FFI unsafe" creates massive FP noise.
        if (!cross_edge_matched and
            ((caller_lang == .c and callee_lang == .cpp) or
                (caller_lang == .cpp and callee_lang == .c)))
        {
            diag.debug("C-CPP-SKIP: {s} -> {s} (same language family)", .{ caller_name, called_name });
            return false;
        }

        // Report risky libc functions only after same-language check passes.
        // This prevents POSIX API (pthread_*, setsockopt, etc.) in pure C code
        // from being flagged as risky when they're not on an FFI boundary.
        if (semantics) |sem| {
            try reportRiskyCall(ctx, inst, caller_name, called_name, sem, diag);
        }

        // Classify the boundary kind
        const boundary_kind = zone_check.classifyBoundaryKindEnhanced(
            caller_lang,
            callee_lang,
            called_name,
        );

        // Apply severity and confidence rules with zone-aware adjustments
        const base_severity: Severity = if (semantics != null) .medium else .low;
        const base_confidence: f32 = if (semantics != null) 0.7 else 0.5;

        //  Zone-aware confidence adjustment.
        // Unknown-zone callers get mild reduction (not 0.6x — we already confirmed
        // FFI boundaries exist via early_exit check, so .unknown zone is still relevant).
        // FFI/unsafe zone callers get full confidence (explicit escape hatch).
        const severity = base_severity;
        const confidence: f32 = switch (caller_zone) {
            .unknown => base_confidence * 0.85, // Mild reduction — still FFI-relevant
            .safe, .runtime_internal => 0.0, // Should have been gated in analyze()
            .ffi, .unsafe => base_confidence, // Explicit FFI zone → full confidence
        };

        // Skip low-confidence or intentional patterns
        if (confidence < 0.4) return false;
        if (zone_check.isLikelyIntentionalPattern(called_name)) return false;

        // For Zig callers, apply additional filtering
        // Only apply Zig-specific filter when semantics are available
        if (caller_lang == .zig) {
            if (semantics) |sem| {
                if (!zone_check.isZigFFIWorthReporting(caller_name, called_name, sem)) {
                    return false;
                }
            }
            // If no semantic info available, skip Zig-specific filter (fall through to normal reporting)
        }

        // Report the FFI boundary issue
        const message = try std.fmt.allocPrint(ctx.allocator,
            \\FFI Boundary: {s} ({s}) -> {s} ({s})
            \\Boundary Kind: {s}
        , .{
            caller_name,             @tagName(caller_lang),
            called_name,             @tagName(callee_lang),
            @tagName(boundary_kind),
        });
        defer ctx.allocator.free(message);

        try boundary_check.reportFFIIssue(
            ctx,
            .ffi_unsafe_call,
            message,
            caller_name,
            severity,
            confidence,
        );
        stats.count += 1;

        // E2-2d: Feedback loop — mark pointer args of FFI boundary calls as
        // ffi_auto_relevant so downstream passes (free_validation, memory_safety)
        // can correlate issues with FFI context.
        {
            var arg_i: u32 = 0;
            const num_ops = c.LLVMGetNumOperands(inst);
            while (arg_i < num_ops) : (arg_i += 1) {
                const arg = c.LLVMGetOperand(inst, arg_i);
                if (@intFromPtr(arg) == 0) continue;
                const arg_type = c.LLVMTypeOf(arg);
                if (@intFromPtr(arg_type) == 0) continue;
                if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                    try ctx.markFfiRelevant(@as(u64, @intFromPtr(arg)));
                }
            }
        }

        // Run specialized boundary checks (delegates to boundary_check module)
        try boundary_check.checkSpecializedBoundary(ctx, diag, inst, caller_func, called_name);

        // Check return value escape (delegates to boundary_check module)
        try boundary_check.checkReturnValueEscape(ctx, diag, inst, caller_func, called_name);

        // Check type compatibility (delegates to boundary_check module)
        if (semantics) |sem| {
            try boundary_check.checkTypeCompatibility(ctx, diag, inst, caller_func, called_name, sem);
        }

        return true;
    }

    /// Report a known-risky function call.
    fn reportRiskyCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_name: []const u8,
        called_name: []const u8,
        sem: FunctionSemantics,
        diag: *DiagnosticWriter,
    ) !void {
        // : Format string constant detection.
        // If the format argument (operand 0 for printf-like functions) is a
        // compile-time string constant, the format string is NOT user-controlled
        // and therefore NOT a vulnerability. Skip reporting.
        if (sem.kind == .format_string) {
            if (isFormatStringConstant(inst)) {
                diag.debug("FORMAT-SAFE: {s} in {s} — format arg is compile-time constant", .{ called_name, caller_name });
                return;
            }
        }

        // Map RiskKind to IssueKind
        const issue_kind = boundary_check.riskKindToIssueKind(sem.kind);

        // Determine severity based on risk kind
        const severity: Severity = switch (sem.kind) {
            .command_exec => .critical,
            .unchecked_copy, .format_string => .high,
            .allocator, .deallocator, .memory_map => .medium,
            else => .low,
        };

        const confidence: f32 = if (sem.transfers_ownership or sem.consumes_ownership)
            0.85
        else
            0.65;

        const location = Location.init(caller_name);
        const issue = Issue.init(issue_kind, sem.description, location, severity, confidence);
        try ctx.addIssue(&issue);

        diag.err("RISKY CALL [{s}] {s} in {s}: {s}", .{
            @tagName(severity), @tagName(sem.kind), caller_name, called_name,
        });
    }

    /// Check if a printf-like call's format argument is a compile-time
    /// constant string or derived from one through safe IR operations.
    ///
    /// This implements P2-1 interprocedural format string tracking:
    /// - Direct constants (global strings, GEP wrappers)
    /// - Load from global constants (interprocedural propagation)
    /// - Bitcast chains (type conversions preserve constness)
    /// - Function parameters traced through call graph (summary-based)
    ///
    /// LLVM IR patterns detected:
    ///   Safe:   call printf(@.str, ...)              — direct global
    ///   Safe:   %fmt = load i8*, i8** @global_fmt   — load from const global
    ///   Safe:   %bc = bitcast [N x i8]* @.str to i8* — bitcast of const
    ///   Unsafe: call printf(%fmt, ...)               — format is variable
    ///
    /// Returns true if format string is provably constant (safe from injection).
    fn isFormatStringConstant(inst: c.LLVMValueRef) bool {
        if (c.LLVMGetNumOperands(inst) < 2) return false;
        // H18 FIX: Format string is operand 0 for printf-like functions, NOT operand 1.
        // Comment at line 394 says "operand 0" but code incorrectly used operand 1.
        const fmt_arg = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(fmt_arg) == 0) return false;

        // Case 1: GEP wrapping a global constant (most common pattern)
        //   %fmt = getelementptr [15 x i8], [15 x i8]* @.str, i32 0, i32 0
        if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMGetElementPtr) {
            const base = c.LLVMGetOperand(fmt_arg, 0);
            if (@intFromPtr(base) != 0 and @intFromPtr(c.LLVMIsAGlobalVariable(base)) != 0) {
                if (c.LLVMIsGlobalConstant(base) != 0) return true;
            }
        }

        // Case 2: Direct global variable reference (no GEP wrapper)
        //   call printf(@.str_direct, ...)
        if (@intFromPtr(c.LLVMIsAGlobalVariable(fmt_arg)) != 0) {
            if (c.LLVMIsGlobalConstant(fmt_arg) != 0) return true;
        }

        // Case 3: Bitcast of a constant (e.g., i8* bitcast from [N x i8]*)
        // Preserves constness through type conversion
        if (c.LLVMIsAConstant(fmt_arg) != null) {
            return true;
        }

        // Case 4: Load instruction from a global constant pointer
        // Supports interprocedural propagation: fmt stored in global, loaded later
        //   @fmt_global = constant i8* getelementptr ([N x i8], [N x i8]* @.str, ...)
        //   %fmt = load i8*, i8** @fmt_global
        if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMLoad) {
            const ptr_operand = c.LLVMGetOperand(fmt_arg, 0);
            if (@intFromPtr(ptr_operand) != 0) {
                // Check if loading from a global variable that is itself constant
                if (@intFromPtr(c.LLVMIsAGlobalVariable(ptr_operand)) != 0) {
                    if (c.LLVMIsGlobalConstant(ptr_operand) != 0) return true;
                }
                // Check if loading from another GEP (chained global access)
                if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr) {
                    const base = c.LLVMGetOperand(ptr_operand, 0);
                    if (@intFromPtr(base) != 0 and @intFromPtr(c.LLVMIsAGlobalVariable(base)) != 0) {
                        if (c.LLVMIsGlobalConstant(base) != 0) return true;
                    }
                }
            }
        }

        // Case 5: Bitcast of a previously-verified constant value
        // Type conversions in the IR chain should not break constness tracking
        if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMBitCast) {
            const src = c.LLVMGetOperand(fmt_arg, 0);
            if (@intFromPtr(src) != 0) {
                // Recursively check the source operand (handles chains)
                if (isConstantValue(src)) return true;
            }
        }

        // Case 6: Pointer-to-int conversion of constant (addrspacecast, ptrtoint)
        // Some optimization passes introduce these; they preserve semantics
        if (c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMAddrSpaceCast or
            c.LLVMGetInstructionOpcode(fmt_arg) == c.LLVMPtrToInt)
        {
            const src = c.LLVMGetOperand(fmt_arg, 0);
            if (@intFromPtr(src) != 0 and c.LLVMIsAConstant(src) != null) {
                return true;
            }
        }

        return false;
    }

    /// Recursively check if an LLVM value is derived from a constant.
    /// Handles chained operations (bitcast → GEP → global) that are common
    /// in optimized IR from compilers like Clang/LLVM.
    fn isConstantValue(val: c.LLVMValueRef) bool {
        if (@intFromPtr(val) == 0) return false;

        // Base case: direct constant
        if (c.LLVMIsAConstant(val) != null) return true;

        // Global variable check
        if (@intFromPtr(c.LLVMIsAGlobalVariable(val)) != 0) {
            return c.LLVMIsGlobalConstant(val) != 0;
        }

        // Recursive case: unwrap common IR patterns
        const opcode = c.LLVMGetInstructionOpcode(val);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
            const operand = c.LLVMGetOperand(val, 0);
            if (@intFromPtr(operand) != 0) {
                return isConstantValue(operand);
            }
        }

        return false;
    }

    /// Resolve indirect call target through function pointer tracing.
    ///
    /// LLVM IR pattern for JNI/COM/vtable calls:
    ///   %gep = getelementptr %struct.T, %struct.T* %ptr, i32 0, i32 <FIELD_IDX>
    ///   %fn = load <func_type>, <func_type>** %gep
    ///   call <ret> %fn(args...)   ← called_val is %fn (not a function)
    ///
    /// This function traces back from the called value through load → GEP
    /// to identify the struct type and field index, then maps known structs
    /// (like JNINativeInterface) to their function names by field position.
    ///
    /// Returns: resolved function name (slice of static buffer), or empty slice if unresolvable.
    fn resolveIndirectCallTarget(inst: c.LLVMValueRef, diag: *DiagnosticWriter) []const u8 {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return "";

        // Step 1: called_val should be an instruction (result of load)
        if (c.LLVMIsAInstruction(called_val) == null) {
            if (ffi_debug) {
                const val_name = c.LLVMGetValueName(called_val);
                const name_str = if (@intFromPtr(val_name) != 0) std.mem.span(val_name) else "(null)";
                diag.info("RESOLVE-FAIL: not instruction, name='{s}', isConst={}, isFn={}", .{
                    name_str,
                    @intFromPtr(c.LLVMIsAConstant(called_val)) != 0,
                    @intFromPtr(c.LLVMIsAFunction(called_val)) != 0,
                });
            }
            return "";
        }
        const load_inst = @as(c.LLVMValueRef, @ptrCast(called_val));
        if (ffi_debug) diag.info("RESOLVE-STEP1: passed, is load inst", .{});

        // Step 2: Verify it's a load instruction
        if (c.LLVMGetInstructionOpcode(load_inst) != c.LLVMLoad) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP2: not a load (opcode={})", .{c.LLVMGetInstructionOpcode(load_inst)});
            return "";
        }
        if (ffi_debug) diag.info("RESOLVE-STEP2: passed, is Load", .{});

        // Step 3: Get the pointer operand of the load (should be GEP result)
        const num_ops = c.LLVMGetNumOperands(load_inst);
        if (num_ops < 1) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP3: load has no operands", .{});
            return "";
        }
        const ptr_operand = c.LLVMGetOperand(load_inst, 0);
        if (@intFromPtr(ptr_operand) == 0) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP3: ptr_operand is null", .{});
            return "";
        }
        if (ffi_debug) diag.info("RESOLVE-STEP3: passed, got ptr_operand", .{});

        // Step 4: Verify pointer operand is a GEP instruction
        if (c.LLVMIsAInstruction(ptr_operand) == null) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP4: ptr_operand not instruction", .{});
            return "";
        }
        const gep_inst = @as(c.LLVMValueRef, @ptrCast(ptr_operand));
        if (c.LLVMGetInstructionOpcode(gep_inst) != c.LLVMGetElementPtr) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP4: not GEP (opcode={})", .{c.LLVMGetInstructionOpcode(gep_inst)});
            return "";
        }
        if (ffi_debug) diag.info("RESOLVE-STEP4: passed, is GEP", .{});

        // Step 5: Extract GEP operands — last operand is the field index
        const gep_num_ops = c.LLVMGetNumOperands(gep_inst);
        if (gep_num_ops < 3) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: GEP has only {} ops", .{gep_num_ops});
            return "";
        }

        const field_idx_val = c.LLVMGetOperand(gep_inst, @intCast(gep_num_ops - 1));
        if (@intFromPtr(field_idx_val) == 0) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: field_idx_val is null", .{});
            return "";
        }
        if (c.LLVMIsAConstantInt(field_idx_val) == null) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: field_idx not constant int", .{});
            return "";
        }

        const field_idx = c.LLVMConstIntGetZExtValue(field_idx_val);
        if (ffi_debug) diag.info("RESOLVE-STEP5: passed, field_idx={}", .{field_idx});

        // Step 6: Get the struct type from GEP's base pointer
        const gep_base = c.LLVMGetOperand(gep_inst, 0);
        if (@intFromPtr(gep_base) == 0) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: gep_base is null", .{});
            return "";
        }
        const ptr_type = c.LLVMTypeOf(gep_base);
        if (@intFromPtr(ptr_type) == 0) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: ptr_type is null", .{});
            return "";
        }
        // DEBUG: Print actual GEP instruction text (debug builds only)
        // NOTE: LLVMPrintValueToString allocates memory that MUST be freed with
        // LLVMDisposeMessage. The defer ensures cleanup on all exit paths.
        const gep_text = c.LLVMPrintValueToString(gep_inst);
        defer c.LLVMDisposeMessage(gep_text);
        if (ffi_debug) diag.info("RESOLVE-DEBUG: GEP text='{s}'", .{std.mem.span(gep_text)});

        // Step 6 (Opaque Pointer workaround):
        // In LLVM 22 with opaque pointers, all pointers are "ptr" and
        // LLVMGetElementType() returns meaningless types (kind=1=Half).
        // Instead, extract the struct NAME from GEP's textual representation:
        //   "%10 = getelementptr inbounds %struct.JNINativeInterface, ptr %9, i32 0, i32 <FIELD>"
        const gep_str = std.mem.span(gep_text);
        const struct_name = extractStructNameFromGEPText(gep_str);
        if (struct_name.len == 0) {
            if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: could not extract struct name from GEP: '{s}'", .{gep_str});
            return "";
        }
        if (ffi_debug) diag.info("RESOLVE-STEP6: extracted struct='{s}'", .{struct_name});

        // Step 7: Map (struct_name, field_index) → function name
        return mapStructFieldToFunction(struct_name, @intCast(field_idx), diag);
    }

    /// Extract struct type name from GEP instruction's textual representation.
    ///
    /// LLVM 22 uses opaque pointers, so `LLVMGetElementType()` returns
    /// meaningless types. This function parses the GEP text to find the
    /// source element type name (e.g., "JNINativeInterface" from "%struct.JNINativeInterface").
    ///
    /// Input example: "  %10 = getelementptr inbounds %struct.JNINativeInterface, ptr %9, i32 0, i32 0"
    /// Output: slice pointing to "%struct.JNINativeInterface" within the input
    fn extractStructNameFromGEPText(gep_text: []const u8) []const u8 {
        // Find "getelementptr" keyword
        const gep_keyword = "getelementptr";
        const gep_start = std.mem.indexOf(u8, gep_text, gep_keyword) orelse return "";
        const after_gep = gep_start + gep_keyword.len;

        // Skip whitespace after "getelementptr"
        var idx = after_gep;
        while (idx < gep_text.len and (gep_text[idx] == ' ' or gep_text[idx] == '\t')) : (idx += 1) {}

        if (idx >= gep_text.len) return "";

        // The next token should be the struct type (e.g., "%struct.JNINativeInterface")
        // It may optionally have "inbounds" before it
        var token_start = idx;
        const inbounds = "inbounds";
        if (idx + inbounds.len < gep_text.len and
            std.mem.eql(u8, gep_text[idx..][0..inbounds.len], inbounds))
        {
            // Skip "inbounds" and following whitespace/comma
            idx += inbounds.len;
            while (idx < gep_text.len and (gep_text[idx] == ' ' or gep_text[idx] == '\t' or gep_text[idx] == ',')) : (idx += 1) {}
            token_start = idx;
        }

        // Extract until comma or end of token
        var token_end = token_start;
        while (token_end < gep_text.len and gep_text[token_end] != ',' and gep_text[token_end] != ' ') : (token_end += 1) {}

        if (token_end <= token_start) return "";

        const type_token = gep_text[token_start..token_end];

        return type_token;
    }

    /// Map a struct field index to a known function name.
    ///
    /// Currently supports:
    /// - JNINativeInterface: maps field indices to JNI function names
    ///
    /// Extension point: add more struct types here as needed (COM vtables,
    /// C++ vtables, other FFI interface tables).
    fn mapStructFieldToFunction(struct_name: []const u8, field_idx: u32, diag: *DiagnosticWriter) []const u8 {
        // JNINativeInterface field layout (from jni.h):
        // Field 0:  FindClass
        // Field 1:  GetMethodID
        // Field 2:  CallVoidMethod
        // Field 3:  GetStringUTFChars
        // Field 4:  ReleaseStringUTFChars
        // Field 5:  NewGlobalRef
        // Field 6:  DeleteGlobalRef
        // Field 7:  AttachCurrentThread
        // Field 8:  GetByteArrayElements
        // Field 9:  ReleaseByteArrayElements
        // Field 10: GetObjectArrayElement
        // Field 11: DeleteLocalRef
        // Field 12: ExceptionCheck
        // Field 13: ExceptionDescribe
        // Field 14: ExceptionClear
        // Field 15: GetArrayLength
        if (std.mem.indexOf(u8, struct_name, "JNINativeInterface") != null) {
            const jni_fields = [_][]const u8{
                "FindClass", // 0
                "GetMethodID", // 1
                "CallVoidMethod", // 2
                "GetStringUTFChars", // 3
                "ReleaseStringUTFChars", // 4
                "NewGlobalRef", // 5
                "DeleteGlobalRef", // 6
                "AttachCurrentThread", // 7
                "GetByteArrayElements", // 8
                "ReleaseByteArrayElements", // 9
                "GetObjectArrayElement", // 10
                "DeleteLocalRef", // 11
                "ExceptionCheck", // 12
                "ExceptionDescribe", // 13
                "ExceptionClear", // 14
                "GetArrayLength", // 15
            };
            if (field_idx < jni_fields.len) {
                if (ffi_debug) diag.info("JNI-FIELD-MAP: JNINativeInterface[{}] → {s}", .{ field_idx, jni_fields[field_idx] });
                return jni_fields[field_idx];
            }
            if (ffi_debug) diag.info("JNI-FIELD-MAP: JNINativeInterface[{}] — unknown field (total: {})", .{ field_idx, jni_fields.len });
        }

        // Unknown struct type — cannot resolve
        return "";
    }
};
