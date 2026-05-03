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
    pub const deps = &[_][]const u8{"danger-surface"};

    /// Run the FFI boundary detection pass (Pass interface requirement).
    /// Delegates to analyze() for actual implementation.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // R8.2-c: Consume cross-language edges from CallGraphPass.
        const cross_edges = ctx.getCrossLangEdges();
        if (cross_edges.len > 0) {
            diag.info("FFIBoundary: consuming {} cross-language edges from CallGraph", .{cross_edges.len});
        }

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) == 0) {
                // P0-2: Function-level gate — skip functions with no danger-surface-relevant pointers.
                if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) {
                    continue;
                }
                _ = try @This().analyze(ctx, func, diag);
            }
        }
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

        // Get function name
        const called_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) == 0) return false;
        const called_name = std.mem.span(called_name_ptr);

        // Extract caller name once (P1b: was retrieved 3 times at L199/L240/L251)
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        // Check if it's a known risky function via Semantic Registry
        const semantics = ctx.cachedRegistryLookup(called_name);
        const is_dangerous = semantics != null;

        // ═══ R7.0 Zone-Aware Filtering ═══
        // Replace scattered whitelist logic with unified zone classification.

        // Classify the callee's zone for zone-aware decisions (cached)
        const callee_zone = ctx.getOrComputeZoneByName(called_name);

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

        // Legacy noise filter kept for edge cases not yet covered by zone classifier.
        // TODO(R7.1): Remove entirely once zone coverage is complete.
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
        // Unknown-zone callers get lower confidence (may be auto-generated code).
        // FFI/unsafe zone callers get full confidence (explicit escape hatch).
        const severity = base_severity;
        const confidence: f32 = switch (caller_zone) {
            .unknown => base_confidence * 0.6, // Uncertain origin → lower confidence
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
        const fmt_arg = c.LLVMGetOperand(inst, 1);
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
};
