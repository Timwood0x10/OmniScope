//! FFI Call Analyzer - Core Analysis Logic
//!
//! Extracted from ffi_boundary.zig checkCallForFFI() to reduce file size.
//! This module contains the core FFI boundary detection logic split into
//! focused sub-functions for better maintainability.
//!
//! Key responsibilities:
//!   - Resolve callee name and zone classification
//!   - Identify caller/callee languages with Zig entry-point inference
//!   - T1.3 module-level cross-validation matrix
//!   - Compute boundary severity and confidence
//!   - Create FFI boundary issues with feedback loop

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../registry/semantic_registry.zig").Severity;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const BoundaryKind = @import("../../../diag/issue.zig").FFIBoundary.BoundaryKind;
const FunctionSemantics = @import("../../../registry/semantic_registry.zig").FunctionSemantics;
const AnalyzeResult = @import("ffi_types.zig").AnalyzeResult;

// Dependencies on other extracted modules
const zone_classifier = @import("../../../semantics/zone_classifier.zig");
const zone_check = @import("ffi_zone_check.zig");
const boundary_check = @import("ffi_boundary_check.zig");
const noise_filter = @import("ffi_noise_filter.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const kind_upgrade = @import("ffi_kind_upgrade.zig");
const SemanticRegistry = @import("../../../registry/semantic_registry.zig").SemanticRegistry;

/// Intermediate analysis context for a single call instruction.
/// Passed between sub-functions to avoid excessive parameter passing.
pub const CallAnalysisContext = struct {
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
    stats: *AnalyzeResult,
    caller_zone: zone_classifier.ZoneKind,

    // Resolved names
    caller_name: []const u8,
    called_name: []const u8,

    // Classification results
    callee_zone: zone_classifier.ZoneKind,
    caller_lang: Language,
    callee_lang: Language,

    // Semantic info
    semantics: ?FunctionSemantics,

    // Indirect call tracking
    is_indirect_call: bool,
};

/// Result of boundary classification with severity and confidence.
pub const BoundaryClassificationResult = struct {
    should_report: bool,
    boundary_kind: BoundaryKind,
    severity: Severity,
    confidence: f32,
};

/// Phase 1: Resolve callee name and classify zones.
///
/// Handles:
///   - Direct function name extraction
///   - Constant expression unwrapping (bitcast/addrspacecast)
///   - Indirect call resolution via resolveIndirectCallTarget
///   - Zone classification for both caller and callee
///
/// Returns: CallAnalysisContext with resolved names and zones, or null if should skip.
pub fn resolveCalleeAndZone(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
    stats: *AnalyzeResult,
    caller_zone: zone_classifier.ZoneKind,
) !?CallAnalysisContext {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;

    const indirect_resolver = @import("ffi_indirect_resolver.zig");

    // Get function name (or resolve indirect call target)
    var called_name: []const u8 = "";

    const called_name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(called_name_ptr) != 0) {
        called_name = std.mem.span(called_name_ptr);
    }

    // Get caller name for logging
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    const builtin = @import("builtin");
    const ffi_debug = builtin.mode == .Debug;

    // DEBUG (compile-time eliminated in Release builds): Log JNI calls
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
    var indirect_name_owned: ?[]u8 = null;
    defer if (indirect_name_owned) |owned| ctx.allocator.free(owned);
    var is_indirect_call = false;

    // T0.5: Unwrap constant expressions (bitcast/addrspacecast wrapping real functions)
    var resolved_via_const_unwrap = false;
    if (c.LLVMIsAConstantExpr(called_val) != null) {
        const const_opcode = c.LLVMGetConstOpcode(called_val);
        const is_wrap = (const_opcode == c.LLVMBitCast or
            const_opcode == c.LLVMAddrSpaceCast);
        if (is_wrap and c.LLVMGetNumOperands(called_val) > 0) {
            const inner = c.LLVMGetOperand(called_val, 0);
            if (@intFromPtr(inner) != 0 and c.LLVMIsAFunction(inner) != null) {
                const inner_name_ptr = c.LLVMGetValueName(inner);
                if (@intFromPtr(inner_name_ptr) != 0) {
                    called_name = std.mem.span(inner_name_ptr);
                    resolved_via_const_unwrap = true;
                }
            }
        }
    }

    // After unwrapping, only register-named or non-function callees should fall into resolver
    const is_indirect = !resolved_via_const_unwrap and
        (called_name.len == 0 or
            called_name[0] == '%' or // LLVM register (e.g., %11)
            c.LLVMIsAFunction(called_val) == null);
    if (is_indirect) {
        const resolved = indirect_resolver.resolveIndirectCallTarget(inst, diag);
        if (resolved.len > 0) {
            indirect_name_owned = try ctx.allocator.dupe(u8, resolved);
            std.debug.assert(indirect_name_owned != null);
            called_name = indirect_name_owned.?;
            is_indirect_call = true;
        } else {
            // Cannot resolve — skip this call
            if (ffi_debug) {
                const inst_text = c.LLVMPrintValueToString(inst);
                defer c.LLVMDisposeMessage(inst_text);
                diag.info("INDIRECT-SKIP: unresolved call '{s}' in {s}", .{
                    std.mem.span(inst_text), caller_name,
                });
            }
            return null;
        }
    }

    // Check semantic registry for known risky functions
    const semantics = if (is_indirect_call)
        SemanticRegistry.lookup(called_name)
    else
        ctx.cachedRegistryLookup(called_name);
    const is_dangerous = semantics != null;

    // Classify callee's zone (cached, except for indirect calls)
    const callee_zone = if (is_indirect_call)
        zone_classifier.classifyFunction(called_name, null)
    else
        ctx.getOrComputeZoneByName(called_name);

    // Zone-aware filtering: safe/runtime_internal → no FFI risk
    switch (callee_zone) {
        .safe => return null,
        .runtime_internal => {
            if (semantics) |sem| {
                if (sem.kind != .command_exec and sem.kind != .unchecked_copy) {
                    return null;
                }
            } else {
                return null;
            }
        },
        .unknown, .ffi, .unsafe => {},
    }

    // Legacy noise filter for edge cases not covered by zone classifier
    if (is_dangerous) {
        if (noise_filter.isStlInternalFunction(caller_name)) {
            return null;
        }
    }

    return CallAnalysisContext{
        .ctx = ctx,
        .inst = inst,
        .caller_func = caller_func,
        .diag = diag,
        .stats = stats,
        .caller_zone = caller_zone,
        .caller_name = caller_name,
        .called_name = called_name,
        .callee_zone = callee_zone,
        .caller_lang = undefined, // Will be set in classifyCallLanguages
        .callee_lang = undefined, // Will be set in classifyCallLanguages
        .semantics = semantics,
        .is_indirect_call = is_indirect_call,
    };
}

/// Phase 2: Identify languages of caller and callee.
///
/// Implements:
///   - Platform-aware language classification (Bug 2 fix)
///   - Zig entry-point inference (transitive Zig for "main", "_start")
///
/// Modifies: ac.caller_lang, ac.callee_lang
pub fn classifyCallLanguages(ac: *CallAnalysisContext) void {
    // Build optional evidence pointer from PassContext
    const evidence_ptr: ?*const @import("../../../ir/ir_evidence.zig").IREvidence =
        if (ac.ctx.evidence) |*ev| ev else null;

    // Identify languages using platform-aware classification with DWARF evidence
    ac.caller_lang = lang_classifier.identifyCalleeLanguageWithContext(
        ac.caller_name,
        ac.ctx.module_language.language,
        ac.ctx.platform_profile,
        ac.ctx.lookupFunctionLanguage(ac.caller_name),
        ac.caller_func,
        evidence_ptr,
    );
    ac.callee_lang = lang_classifier.identifyCalleeLanguageWithContext(
        ac.called_name,
        ac.ctx.module_language.language,
        ac.ctx.platform_profile,
        ac.ctx.lookupFunctionLanguage(ac.called_name),
        c.LLVMGetCalledValue(ac.inst),
        evidence_ptr,
    );

    // Bug 2 final fix: Transitive Zig inference for entry-point callers.
    //
    // When callee is classified as .zig but caller is .c/.unknown (e.g., plain "main"),
    // the caller is likely ALSO Zig. This happens because:
    //   - Zig's LLVM IR entry point is often named "main" (no prefix)
    //   - "main" doesn't match any zig_patterns → defaults to .c
    //   - But "main" calling "main.main" (Zig's package-qualified name) is internal Zig
    if (ac.callee_lang == .zig and (ac.caller_lang == .c or ac.caller_lang == .unknown)) {
        const is_generic_entry = std.mem.eql(u8, ac.caller_name, "main") or
            std.mem.eql(u8, ac.caller_name, "_start") or
            std.mem.eql(u8, ac.caller_name, "__main");
        if (is_generic_entry) {
            ac.caller_lang = .zig;
        }
    }
}

/// Phase 3: T1.3 Module-level cross-validation matrix.
///
/// Validates whether this cross-language call is a real FFI boundary or
/// a false positive using module-level language evidence as tiebreaker.
///
/// Cross-validation matrix:
///   | Caller | Callee | Module | Action                    |
///   |--------|--------|--------|---------------------------|
///   | .c     | .c     | .c     | ✅ Same-lang (skip)       |
///   | .rust  | .rust  | .rust  | ✅ Same-lang (skip)       |
///   | .c     | .rust | .rust  | ⚠️ Likely internal (skip)  |
///   | .rust  | .c     | .rust  | ✅ Real FFI (report)      |
///   | .c     | .c     | .rust  | ⚠️ Re-check needed        |
///   | .unknown| .rust | .rust  | ⚠️ Use module as caller    |
///
/// Returns: true if should continue to reporting, false if should skip.
pub fn validateCrossLanguageBoundary(ac: *CallAnalysisContext) bool {
    // R8.2-c: Check pre-computed cross-language edges from CallGraphPass
    var cross_edge_matched = false;
    if (ac.ctx.getCrossEdgeByCallee(ac.called_name)) |cross| {
        if (cross.is_ffi_boundary) {
            cross_edge_matched = true;
            if (cross.callee_lang != .unknown and ac.callee_lang == .unknown) {
                ac.callee_lang = cross.callee_lang;
            }
        }
    }

    // P1 FIX: Skip same-language calls regardless of cross_edge_matched.
    // CallGraph may mark C→C as cross-language when callee is external (e.g., time(), printf()),
    // but calling a libc function from C code is NOT FFI.
    if (ac.caller_lang != .unknown and ac.callee_lang != .unknown and
        ac.caller_lang == ac.callee_lang)
    {
        return false;
    }

    // T1.3 Enhanced: Module-level language context cross-validation
    const module_lang_profile = ac.ctx.getModuleLanguage();
    const module_lang = module_lang_profile.language;
    const is_module_lang_confident = module_lang_profile.confidence >= 0.6 and
        module_lang != .unknown;

    if (is_module_lang_confident) {
        // Case 1: Both match module language → same-lang skip
        if (ac.caller_lang == module_lang and ac.callee_lang == module_lang) {
            ac.diag.debug("T1.3-MODULE-SKIP [{s}]: {s} -> {s} (both match module lang)", .{
                @tagName(module_lang), ac.caller_name, ac.called_name,
            });
            return false;
        }

        // Case 2: Caller matches module, callee looks like internal pattern
        if (ac.caller_lang == module_lang and isInternalToLanguage(ac.called_name, module_lang)) {
            ac.diag.debug("T1.3-INTERNAL-SKIP [{s}]: {s} -> {s} (callee is internal)", .{
                @tagName(module_lang), ac.caller_name, ac.called_name,
            });
            return false;
        }

        // Case 3: Caller is .unknown but module provides context
        if (ac.caller_lang == .unknown and ac.callee_lang == module_lang) {
            ac.diag.debug("T1.3-CALLER-INFERENCE [{s}]: {s} -> {s} (inferred caller from module)", .{
                @tagName(module_lang), ac.caller_name, ac.called_name,
            });
            return false;
        }

        // Case 4: Callee is .unknown but matches external pattern → let it fall through
    }

    // P1 FIX: Skip C↔C++ bridge calls (same language family).
    // C/C++ share memory model, ABI, runtime — only risk is cross-allocator mismatches,
    // already handled by FreeValidationPass.isCrossAllocatorFree().
    if ((ac.caller_lang == .c and ac.callee_lang == .cpp) or
        (ac.caller_lang == .cpp and ac.callee_lang == .c))
    {
        ac.diag.debug("C-CPP-SKIP: {s} -> {s} (same language family)", .{ ac.caller_name, ac.called_name });
        return false;
    }

    return true; // Should continue to reporting
}

/// Check if a function name is internal to a specific language.
///
/// T1.3 utility: identifies language-internal patterns that should NOT
/// be treated as FFI boundaries when called from within the same language.
///
/// Patterns detected:
///   - Rust: `_rust_`, `rs2py_`, `rust_`, `_R` (v0 mangling), allocator intrinsics
///   - Zig: `zig_`, `__zig_`, `Allocator.`
///   - Go: `runtime.`, `main.`, `_Cgo_` (CGo internal)
///   - C/C++: libc functions, `__cxa_` (ABI internals)
pub fn isInternalToLanguage(func_name: []const u8, lang: Language) bool {
    return switch (lang) {
        .rust => {
            // Rust-internal patterns: compiler-generated, stdlib, allocator glue
            if (std.mem.indexOf(u8, func_name, "_rust_") != null) return true;
            if (std.mem.indexOf(u8, func_name, "rs2py_") != null) return true;
            if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') return true;
            // Rust allocator intrinsics
            const rust_alloc_patterns = [_][]const u8{
                "__rust_alloc",    "__rdl_alloc",   "__rg_alloc",
                "__rust_dealloc",  "__rdl_dealloc", "__rg_dealloc",
                "__rust_realloc",  "__rdl_realloc", "__rg_realloc",
                "exchange_malloc", "exchange_free",
            };
            for (rust_alloc_patterns) |p| {
                if (std.mem.indexOf(u8, func_name, p) != null) return true;
            }
            // Rust ownership/drop glue
            const rust_ownership = [_][]const u8{ "into_raw", "from_raw", "drop_in_place" };
            for (rust_ownership) |p| {
                if (std.mem.indexOf(u8, func_name, p) != null) return true;
            }
            return false;
        },
        .zig => {
            // Zig-internal patterns: compiler runtime, stdlib
            if (std.mem.indexOf(u8, func_name, "zig_") != null) return true;
            if (std.mem.startsWith(u8, func_name, "__zig_")) return true;
            if (std.mem.indexOf(u8, func_name, "Allocator.") != null) return true;
            return false;
        },
        .go => {
            // Go-internal patterns: runtime, CGo glue
            if (std.mem.startsWith(u8, func_name, "runtime.")) return true;
            if (std.mem.startsWith(u8, func_name, "main.")) return true;
            if (std.mem.indexOf(u8, func_name, "_Cgo_") != null) return true;
            if (std.mem.indexOf(u8, func_name, "_cgo_") != null) return true;
            return false;
        },
        .cpp => {
            // C++ ABI internals (safe within C++ code)
            if (std.mem.startsWith(u8, func_name, "__cxa_")) return true;
            // C++ RTTI/vtable symbols
            if (func_name.len > 3 and func_name[0] == '_' and func_name[1] == 'Z' and
                func_name[2] == 'T')
            {
                const third = func_name[3];
                if (third == 'V' or third == 'I' or third == 'S') return true;
            }
            return false;
        },
        .c => {
            // Most libc functions are C-internal when called from C code
            const libc_internal = [_][]const u8{
                "malloc",         "calloc",       "realloc", "free",
                "memcpy",         "memmove",      "memset",  "memcmp",
                "strlen",         "strcpy",       "strncpy", "strcmp",
                "printf",         "fprintf",      "sprintf", "snprintf",
                "fopen",          "fclose",       "fread",   "fwrite",
                "pthread_create", "pthread_join",
            };
            for (libc_internal) |p| {
                if (std.mem.eql(u8, func_name, p)) return true;
            }
            return false;
        },
        else => return false,
    };
}

/// Phase 4: Compute boundary classification, severity, and confidence.
///
/// Applies zone-aware adjustments and filters:
///   - Base severity from semantic registry
///   - Zone-aware confidence scaling
///   - Low-confidence and intentional pattern filtering
///   - Zig-specific additional filtering
///
/// Returns: BoundaryClassificationResult with decision and metrics.
pub fn computeBoundaryClassification(ac: *CallAnalysisContext) BoundaryClassificationResult {
    // Report risky libc functions (after same-language check passes)
    if (ac.semantics) |sem| {
        reportRiskyCall(ac.ctx, ac.inst, ac.caller_name, ac.called_name, sem, ac.diag);
    }

    // Classify the boundary kind
    const boundary_kind = zone_check.classifyBoundaryKindEnhanced(
        ac.caller_lang,
        ac.callee_lang,
        ac.called_name,
    );

    // Apply severity and confidence rules with zone-aware adjustments
    const base_severity: Severity = if (ac.semantics != null) .medium else .low;
    const base_confidence: f32 = if (ac.semantics != null) 0.7 else 0.5;

    // Zone-aware confidence adjustment
    const severity = base_severity;
    const confidence: f32 = switch (ac.caller_zone) {
        .unknown => base_confidence * 0.85, // Mild reduction — still FFI-relevant
        .safe, .runtime_internal => 0.0, // Should have been gated earlier
        .ffi, .unsafe => base_confidence, // Explicit FFI zone → full confidence
    };

    // Skip low-confidence or intentional patterns
    if (confidence < 0.4) {
        return BoundaryClassificationResult{
            .should_report = false,
            .boundary_kind = boundary_kind,
            .severity = severity,
            .confidence = confidence,
        };
    }
    if (zone_check.isLikelyIntentionalPattern(ac.called_name)) {
        return BoundaryClassificationResult{
            .should_report = false,
            .boundary_kind = boundary_kind,
            .severity = severity,
            .confidence = confidence,
        };
    }

    // For Zig callers, apply additional filtering
    if (ac.caller_lang == .zig) {
        if (ac.semantics) |sem| {
            if (!zone_check.isZigFFIWorthReporting(ac.caller_name, ac.called_name, sem)) {
                return BoundaryClassificationResult{
                    .should_report = false,
                    .boundary_kind = boundary_kind,
                    .severity = severity,
                    .confidence = confidence,
                };
            }
        }
    }

    return BoundaryClassificationResult{
        .should_report = true,
        .boundary_kind = boundary_kind,
        .severity = severity,
        .confidence = confidence,
    };
}

/// Report a known-risky function call.
///
/// Extracted from FFIBoundaryPass.reportRickyCall to keep analyzer self-contained.
fn reportRiskyCall(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    caller_name: []const u8,
    called_name: []const u8,
    sem: FunctionSemantics,
    diag: *DiagnosticWriter,
) !void {
    const format_checker = @import("ffi_format_checker.zig");
    const Location = @import("../../../diag/issue.zig").Location;
    const Issue = @import("../../../diag/issue.zig").Issue;

    // Format string constant detection
    if (sem.kind == .format_string) {
        if (format_checker.isFormatStringConstant(inst)) {
            diag.debug("FORMAT-SAFE: {s} in {s} — format arg is compile-time constant", .{ called_name, caller_name });
            return;
        }
    }

    // Map RiskKind to IssueKind
    var issue_kind = boundary_check.riskKindToIssueKind(sem.kind);

    // #3: Call-site name-based precision upgrade
    const upgraded = kind_upgrade.upgradeKindFromCallName(issue_kind, caller_name);
    if (upgraded) |precise_kind| {
        issue_kind = precise_kind;
        diag.debug("KIND-UPGRADE: {s} -> {s} (from caller '{s}')", .{
            @tagName(boundary_check.riskKindToIssueKind(sem.kind)),
            @tagName(precise_kind),
            caller_name,
        });
    }

    // Determine severity based on risk kind (re-evaluate after upgrade)
    const severity: Severity = switch (issue_kind) {
        .command_injection => .critical,
        .double_free, .use_after_free, .invalid_free, .cross_language_free => .high,
        .memory_leak, .type_mismatch, .borrow_escape, .buffer_overflow => .medium,
        else => switch (sem.kind) {
            .format_string => .high,
            .allocator, .deallocator, .memory_map => .medium,
            else => .low,
        },
    };

    // Boost confidence for name-matched precise kinds
    const base_confidence: f32 = if (sem.transfers_ownership or sem.consumes_ownership)
        0.85
    else if (upgraded != null)
        0.78
    else
        0.65;

    const location = Location.init(caller_name);
    const issue = Issue.init(issue_kind, sem.description, location, severity, base_confidence);
    try ctx.addIssue(&issue);

    diag.err("RISKY CALL [{s}] {s} in {s}: {s}", .{
        @tagName(severity), @tagName(sem.kind), caller_name, called_name,
    });
}

/// Phase 5: Create FFI boundary issue and run feedback loop.
///
/// Creates the issue with:
///   - Kind upgrade from caller name (#3)
///   - Severity re-evaluation after upgrade
///   - Confidence boost for name-matched kinds
///   - E2-2d feedback loop (mark pointer args as ffi_auto_relevant)
///   - Specialized boundary checks delegation
pub fn createBoundaryIssueAndFeedback(ac: *CallAnalysisContext, result: *BoundaryClassificationResult) !void {
    if (!result.should_report) return;

    // Build message
    const message = try std.fmt.allocPrint(ac.ctx.allocator,
        \\FFI Boundary: {s} ({s}) -> {s} ({s})
        \\Boundary Kind: {s}
    , .{
        ac.caller_name,                 @tagName(ac.caller_lang),
        ac.called_name,                 @tagName(ac.callee_lang),
        @tagName(result.boundary_kind),
    });
    defer ac.ctx.allocator.free(message);

    // #3: Call-site name-based precision upgrade for FFI boundary issues
    var boundary_issue_kind: IssueKind = .ffi_unsafe_call;
    if (kind_upgrade.upgradeKindFromCallName(boundary_issue_kind, ac.caller_name)) |precise_kind| {
        boundary_issue_kind = precise_kind;
        ac.diag.debug("KIND-UPGRADE [BOUNDARY]: ffi_unsafe_call -> {s} (from caller '{s}')", .{
            @tagName(precise_kind),
            ac.caller_name,
        });
    }

    // Re-evaluate severity after potential kind upgrade
    const final_severity: Severity = switch (boundary_issue_kind) {
        .command_injection => .critical,
        .double_free, .use_after_free, .invalid_free, .cross_language_free => .high,
        .memory_leak, .type_mismatch, .borrow_escape, .buffer_overflow => .medium,
        else => result.severity,
    };

    // Boost confidence for name-matched kinds
    const final_confidence: f32 = if (boundary_issue_kind != .ffi_unsafe_call)
        0.78 // Name-matched upgrade adds confidence
    else
        result.confidence;

    try boundary_check.reportFFIIssue(
        ac.ctx,
        boundary_issue_kind,
        message,
        ac.caller_name,
        final_severity,
        final_confidence,
    );
    ac.stats.count += 1;

    // E2-2d: Feedback loop — mark pointer args of FFI boundary calls as ffi_auto_relevant
    {
        var arg_i: u32 = 0;
        const num_ops = c.LLVMGetNumOperands(ac.inst);
        while (arg_i < num_ops) : (arg_i += 1) {
            const arg = c.LLVMGetOperand(ac.inst, arg_i);
            if (@intFromPtr(arg) == 0) continue;
            const arg_type = c.LLVMTypeOf(arg);
            if (@intFromPtr(arg_type) == 0) continue;
            if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                try ac.ctx.markFfiRelevant(@as(u64, @intFromPtr(arg)));
            }
        }
    }

    // Run specialized boundary checks (delegates to boundary_check module)
    try boundary_check.checkSpecializedBoundary(ac.ctx, ac.diag, ac.inst, ac.caller_func, ac.called_name);

    // Check return value escape (delegates to boundary_check module)
    try boundary_check.checkReturnValueEscape(ac.ctx, ac.diag, ac.inst, ac.caller_func, ac.called_name);

    // Check type compatibility (delegates to boundary_check module)
    if (ac.semantics) |sem| {
        try boundary_check.checkTypeCompatibility(ac.ctx, ac.diag, ac.inst, ac.caller_func, ac.called_name, sem);
    }
}
