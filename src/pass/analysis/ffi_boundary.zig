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

// Existing extracted modules
const type_checker = @import("ffi_type_checker.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const safety_checker = @import("ffi_safety_checker.zig");
const NoiseReduction = @import("noise_reduction.zig");
const FPWhitelist = @import("../filter/fp_whitelist.zig");
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
    pub const deps = &[_][]const u8{};

    /// Run the FFI boundary detection pass (Pass interface requirement).
    /// Delegates to analyze() for actual implementation.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) == 0) {
                _ = try @This().analyze(ctx, func, diag);
            }
        }
    }

    /// Analyze a single function for FFI boundaries.
    pub fn analyze(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{};

        // Get function name for logging
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        // Phase 1: Quick classification using noise reduction engine.
        // This filters out compiler-generated functions, runtime helpers,
        // and other non-user code to reduce false positives.
        const classification = NoiseReduction.classifyFunction(
            func_name,
            null, // debug_file_path (optional, can be null)
            .{},   // default configuration
        );

        // Skip compiler-generated and ignored functions
        if (classification.weight == .ignored) {
            diag.debug("SKIP [NOISE]: {s} ({s})",
                .{ func_name, classification.origin.toString() });
            return result;
        }

        // Phase 2: FP whitelist check
        if (FPWhitelist.is_known_fp(func_name)) |fp| {
            diag.debug("FP-WHITELIST [{s}]: {s}", .{ fp.reason, func_name });
            return result;
        }

        // Log user code / third-party for visibility
        if (classification.origin == .user) {
            diag.debug("ANALYZE [USER]: {s}", .{func_name});
        } else {
            diag.debug("ANALYZE [{s}]: {s}", .{ classification.origin.toString(), func_name });
        }

        // Phase 3: Scan all call instructions for FFI boundaries
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    if (try checkCallForFFI(ctx, inst, func, diag, &result)) {
                        result.count += 1;
                    }
                }
            }
        }
        return result;
    }

    /// Check a call instruction for FFI boundary (delegates to boundary_check module).
    fn checkCallForFFI(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *AnalyzeResult,
    ) !bool {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        // Get function name
        const called_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) == 0) return false;
        const called_name = std.mem.span(called_name_ptr);

        // Check if it's a known risky function via Semantic Registry
        const semantics = SemanticRegistry.lookup(called_name);
        const is_dangerous = semantics != null;

        // Skip safe libc patterns (noise filter)
        if (is_dangerous) {
            if (noise_filter.isSafeLibcPattern(called_name)) {
                return false;
            }
            // Skip C++ ABI runtime internal functions
            if (noise_filter.isCppAbiInternalFunction(called_name)) {
                return false;
            }
            // Skip C++ memory management operators
            if (noise_filter.isCppOperatorPattern(called_name)) {
                return false;
            }
            // Skip calls inside STL/libc++ internal template expansion functions
            const caller_name_ptr = c.LLVMGetValueName(caller_func);
            const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                std.mem.span(caller_name_ptr)
            else
                "unknown";
            if (noise_filter.isStlInternalFunction(caller_name)) {
                return false;
            }
        }

        // Report risky libc functions even if they're not FFI boundaries
        if (semantics) |sem| {
            try reportRiskyCall(ctx, inst, caller_func, called_name, sem, diag, stats);
        }

        // Identify languages of caller and callee
        const caller_lang = zone_check.identifyLanguage(caller_func);
        const callee_lang = zone_check.identifyCalleeLanguage(called_name);

        // Skip same-language calls (not FFI boundaries)
        if (caller_lang != .unknown and callee_lang != .unknown and
            caller_lang == callee_lang)
        {
            return false;
        }

        // Classify the boundary kind
        const boundary_kind = zone_check.classifyBoundaryKindEnhanced(
            caller_lang, callee_lang, called_name,
        );

        // Apply severity rules (simplified for now)
        const severity: Severity = if (semantics != null) .medium else .low;
        const confidence: f32 = if (semantics != null) 0.7 else 0.5;

        // Skip low-confidence or intentional patterns
        if (confidence < 0.4) return false;
        if (zone_check.isLikelyIntentionalPattern(called_name)) return false;

        // For Zig callers, apply additional filtering
        if (caller_lang == .zig) {
            const caller_name_ptr = c.LLVMGetValueName(caller_func);
            const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                std.mem.span(caller_name_ptr)
            else
                "unknown";
            if (!zone_check.isZigFFIWorthReporting(caller_name, called_name, semantics orelse undefined)) {
                return false;
            }
        }

        // Report the FFI boundary issue
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const message = try std.fmt.allocPrint(ctx.allocator,
            \\FFI Boundary: {s} ({s}) -> {s} ({s})
            \\Boundary Kind: {s}
        , .{
            caller_name, @tagName(caller_lang),
            called_name, @tagName(callee_lang),
            @tagName(boundary_kind),
        });
        defer ctx.allocator.free(message);

        try boundary_check.reportFFIIssue(
            ctx, .ffi_unsafe_call, message, caller_name, severity, confidence,
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
        caller_func: c.LLVMValueRef,
        called_name: []const u8,
        sem: FunctionSemantics,
        diag: *DiagnosticWriter,
        stats: *AnalyzeResult,
    ) !void {
        _ = inst;
        _ = stats;

        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

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
};
