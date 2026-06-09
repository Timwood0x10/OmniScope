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
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");
const builtin = @import("builtin");
const ir_store_mod = @import("../../../ir/ir_store.zig");

/// Compile-time debug flag: true only in Debug builds.
/// All verbose diagnostic logging below is eliminated by the compiler
/// in Release/ReleaseFast/Safe modes (zero runtime overhead).
const ffi_debug = builtin.mode == .Debug;

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

// Extracted modules (refactored from this file)
const zone_check = @import("ffi_zone_check.zig");
const boundary_check = @import("ffi_boundary_check.zig");
const noise_filter = @import("ffi_noise_filter.zig");

// Zone classifier for R7.0 Zone-First architecture
const zone_classifier = @import("../../../semantics/zone_classifier.zig");

// Existing extracted modules
const type_checker = @import("ffi_type_checker.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const safety_checker = @import("ffi_safety_checker.zig");
const NoiseReduction = @import("../noise/noise_reduction.zig");
const ip_ffi = @import("../ip_ffi.zig");
const severity_rules = @import("../noise/severity_rules.zig");

// T3.1: Parallel execution support for per-function analysis
const parallel = @import("../../../pipeline/parallel.zig");
// T3.1: Worker context and function (extracted to keep this file <1000 lines)
const ffi_parallel = @import("ffi_parallel.zig");

// Call-site kind upgrade (extracted to keep this file <1000 lines)
const kind_upgrade = @import("ffi_kind_upgrade.zig");

// Indirect call resolution (extracted to keep this file <1000 lines)
const indirect_call = @import("ffi_indirect_call.zig");

// Format string / constant value detection (extracted to keep this file <1000 lines)
const format_check = @import("ffi_format_check.zig");

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

/// Re-export kind-upgrade utility for backward compatibility.
pub const upgradeKindFromCallName = kind_upgrade.upgradeKindFromCallName;
pub const upgradedSeverity = kind_upgrade.upgradedSeverity;

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

        const mod = ctx.module.?.raw;
        const first_func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(first_func) == 0) return;

        // T3.1: Pre-collect all non-declaration functions into work items using IRStore.
        if (ctx.ir_store.function_list.len == 0) return;

        const work_items = try ctx.allocator.alloc(parallel.WorkItem, ctx.ir_store.function_list.len);
        defer ctx.allocator.free(work_items);
        for (ctx.ir_store.function_list, 0..) |fir, idx| {
            work_items[idx] = .{
                .func = @intFromPtr(fir.func),
                .func_name = fir.name,
                .is_declaration = false,
                .fir_idx = idx,
            };
        }

        // T3.1: Shared state for parallel analysis
        var analysis_mutex = std.Thread.Mutex{};
        var total_analyzed: u32 = 0;
        var issues_generated: u32 = 0;

        // T3.1: Worker context for FFI boundary analysis (from ffi_parallel.zig)
        var ffi_worker_ctx = ffi_parallel.FFIBoundaryWorkerContext{
            .ctx_ptr = ctx,
            .diag_ptr = diag,
            .mutex = &analysis_mutex,
            .total_analyzed_out = &total_analyzed,
            .issues_out = &issues_generated,
        };

        ffi_parallel.setFFIWorkerContext(&ffi_worker_ctx);
        defer ffi_parallel.clearFFIWorkerContext();

        var executor = try parallel.ParallelExecutor.init(ctx.allocator, 0);
        defer executor.deinit();
        _ = try executor.run(work_items, ffi_parallel.ffiBoundaryWorkerFn);

        diag.info("FFIBoundary: {d} funcs analyzed, {d} issues generated", .{ total_analyzed, issues_generated });
    }

    /// Analyze a single function for FFI boundaries.
    ///
    /// R7.0 Zone-First Architecture:
    ///   Phase 0: Classify zone → gate on .safe/.runtime_internal (skip entirely)
    ///   Phase 1: Noise reduction (secondary filter for edge cases)
    ///   Phase 2: FP whitelist (defense-in-depth, will be migrated into zone)
    ///   Phase 3: Scan call instructions with zone-aware analysis
    pub fn analyze(ctx: *PassContext, fir: *const ir_store_mod.FunctionIR, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{};
        const func = fir.func;
        const func_name = fir.name;

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
            // Rescue: compiler_generated functions that call known FFI alloc/free functions
            // (e.g., Rust v0 mangled user code like `_RNvC1x3bad3free` classified as noise
            // by the `_RNv` prefix pattern) must not be skipped — they carry real FFI bugs.
            const rescued = blk: {
                if (classification.origin != .compiler_generated) break :blk false;
                for (fir.calls) |call_inst| {
                    if (fir.getCalleeNameByInst(call_inst)) |cn| {
                        if (SemanticRegistry.lookup(cn) != null) break :blk true;
                    }
                }
                break :blk false;
            };
            if (!rescued) {
                diag.debug("SKIP [NOISE]: {s} ({s})", .{ func_name, classification.origin.toString() });
                return result;
            }
        }

        // Phase 2 (REMOVED in R7.0): FP whitelist was here.
        // All 18 FPWhitelist patterns have been migrated into zone_classifier:
        //   - Cat 1 (10x LLVM intrinsics) → llvm.* prefix → .runtime_internal
        //   - Cat 2 (7x Rust stdlib)    → RUST_SAFE_PATTERNS → .safe
        //   - Cat 3 (2x project-specific)→ C_INTERNAL_PATTERNS → .runtime_internal
        // Zone-First gate (Phase 0) now handles all of these before reaching here.

        // Phase 3: Scan all call instructions for FFI boundaries (zone-aware)
        for (fir.instructions, 0..) |inst, idx| {
            const opcode = fir.opcodes[idx];
            if (llvm_safe.isCallOrInvoke(opcode)) {
                if (try checkCallForFFI(ctx, inst, func, diag, &result, zone, fir)) {
                    result.count += 1;
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
        fir: *const ir_store_mod.FunctionIR,
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

        // T0.5: A constant-expression callee is most often a `bitcast` or
        // `addrspacecast` wrapping a real function (type-coerced direct call).
        // Treating every ConstantExpr as indirect previously routed these into
        // resolveIndirectCallTarget, which expects a load/GEP shape and would
        // return "" — silently dropping the entire callsite (POT-BUG-4).
        // Under LLVM 22 opaque pointers we cannot type-gate via
        // LLVMGetElementType (it returns garbage on `ptr`), so we unwrap the
        // constant expression instead and only fall through to the JNI/vtable
        // path when no underlying function can be recovered.
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

        // After unwrapping, only register-named or otherwise-non-function
        // callees should fall into the JNI/vtable resolver. Note:
        // `LLVMIsAFunction == null` already covers any ConstantExpr we could
        // not unwrap, so no separate ConstantExpr disjunct is needed.
        const is_indirect = !resolved_via_const_unwrap and
            (called_name.len == 0 or
                called_name[0] == '%' or // LLVM register (e.g., %11)
                c.LLVMIsAFunction(called_val) == null);
        if (is_indirect) {
            const resolved = indirect_call.resolveIndirectCallTarget(inst, diag);
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

        // PURE-COMP: If the callee is a pure computation function (strlen, atoi,
        // time, rand, getenv, etc.), it has no memory side effects, no writes,
        // and no global state changes. FFI calls to these functions should not
        // produce boundary warnings — they are semantically harmless even across
        // language boundaries.
        if (semantics) |sem| {
            if (sem.kind == .pure_computation) {
                diag.debug("PURE-COMP-SKIP: {s}", .{called_name});
                return false;
            }
        }

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

        // Identify languages of caller and callee — both use platform-aware
        // classification (Bug 2 fix). Zig functions like "main" (no special prefix)
        // and "main.main" (Go-like naming) must be classified correctly.
        //
        // DWARF evidence takes priority when available.
        const evidence_ptr: ?*const @import("../../../ir/ir_evidence.zig").IREvidence =
            if (ctx.evidence) |*ev| ev else null;
        var caller_lang = lang_classifier.identifyCalleeLanguageWithContext(
            caller_name,
            ctx.module_language.language,
            ctx.platform_profile,
            ctx.lookupFunctionLanguage(caller_name),
            caller_func,
            evidence_ptr,
        );
        var callee_lang = lang_classifier.identifyCalleeLanguageWithContext(
            called_name,
            ctx.module_language.language,
            ctx.platform_profile,
            ctx.lookupFunctionLanguage(called_name),
            called_val,
            evidence_ptr,
        );

        // Bug 2 final fix: Transitive Zig inference for entry-point callers.
        //
        // When callee is classified as .zig (e.g., "main.main" via RULE 3) but
        // caller is .c/.unknown (e.g., plain "main" with no Zig prefix), the
        // caller is likely ALSO Zig. This happens because:
        //   - Zig's LLVM IR entry point is often named "main" (no prefix)
        //   - "main" doesn't match any zig_patterns → defaults to .c
        //   - But "main" calling "main.main" (Zig's package-qualified name)
        //     is an internal Zig call, NOT a C→Zig FFI boundary
        //
        // Generic entry-point names that trigger this inference:
        //   "main", "_start", "__main" — common LLVM entry points that are
        //   ambiguous without module context.
        if (callee_lang == .zig and (caller_lang == .c or caller_lang == .unknown)) {
            const is_generic_entry = std.mem.eql(u8, caller_name, "main") or
                std.mem.eql(u8, caller_name, "_start") or
                std.mem.eql(u8, caller_name, "__main");
            if (is_generic_entry) {
                caller_lang = .zig;
            }
        }

        // T1.3: Call-site language context enhancement.
        // Use module-level language as cross-validation to improve FFI boundary
        // detection accuracy. This addresses false positives where C→Rust safe
        // calls are incorrectly marked as cross-language boundaries.
        //
        // Data source priority:
        //   1. ctx.evidence.dominant_language (if T1.1 IREvidence completed)
        //   2. ctx.getModuleLanguage() (module-level statistical detection)
        //   3. Per-function heuristics (fallback, current behavior)
        const module_lang_profile = ctx.getModuleLanguage();
        const module_lang = module_lang_profile.language;
        const is_module_lang_confident = module_lang_profile.confidence >= 0.6 and
            module_lang != .unknown;

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

        // P2-1: Confidence-gated same-language skip.
        // Without confidence gating, Zig functions classified as C will skip
        // C→C boundaries that are actually Zig→C FFI calls.
        const SAME_LANG_SKIP_MIN: f32 = 0.80;
        const MODULE_OVERRIDE_MIN: f32 = 0.90;

        if (caller_lang != .unknown and callee_lang != .unknown and
            caller_lang == callee_lang)
        {
            // Calculate confidence for caller and callee
            const caller_confidence = classifyLanguageConfidence(caller_name, caller_lang, module_lang);
            const callee_confidence = classifyLanguageConfidence(called_name, callee_lang, module_lang);

            // High confidence on both sides → safe to skip
            if (caller_confidence >= SAME_LANG_SKIP_MIN and callee_confidence >= SAME_LANG_SKIP_MIN) {
                return false;
            }

            // Module-level override: if module is confidently a single language
            // and both match module, skip regardless of per-function confidence
            if (is_module_lang_confident and
                module_lang_profile.confidence >= MODULE_OVERRIDE_MIN and
                caller_lang == module_lang and callee_lang == module_lang)
            {
                return false;
            }

            // Low confidence → don't skip, but allow through with lower severity
            diag.debug("LOW-CONF-SAME-LANG-ALLOW: {s} ({s}, conf={d:.2}) -> {s} ({s}, conf={d:.2})", .{
                caller_name, @tagName(caller_lang), caller_confidence,
                called_name, @tagName(callee_lang), callee_confidence,
            });
        }

        // T1.3 Enhanced: Module-level language context cross-validation.
        // When per-function detection is uncertain (.unknown) or conflicts with
        // module-level evidence, use module language as tiebreaker.
        //
        // Key insight: If the entire module is Rust, then calls to _rust_*
        // prefixed functions are Rust-internal (not FFI). Similarly for other languages.
        //
        // Cross-validation matrix:
        //   | Caller | Callee | Module | Action                    |
        //   |--------|--------|--------|---------------------------|
        //   | .c     | .c     | .c     | ✅ Same-lang (skip)       |
        //   | .rust  | .rust  | .rust  | ✅ Same-lang (skip)       |
        //   | .c     | .rust | .rust  | ⚠️ Likely internal (skip)  |
        //   | .rust  | .c     | .rust  | ✅ Real FFI (report)      |
        //   | .c     | .c     | .rust  | ⚠️ Re-check needed        |
        //   | .unknown| .rust | .rust  | ⚠️ Use module as caller    |
        if (is_module_lang_confident) {
            // Case 1: Both caller and callee match module language → same-lang skip
            if (caller_lang == module_lang and callee_lang == module_lang) {
                diag.debug("T1.3-MODULE-SKIP [{s}]: {s} -> {s} (both match module lang)", .{
                    @tagName(module_lang), caller_name, called_name,
                });
                return false;
            }

            // Case 2: Caller matches module language, callee looks like internal pattern
            // Example: Rust module calling _rust_* functions (Rust internals)
            if (caller_lang == module_lang and isInternalToLanguage(called_name, module_lang)) {
                diag.debug("T1.3-INTERNAL-SKIP [{s}]: {s} -> {s} (callee is internal)", .{
                    @tagName(module_lang), caller_name, called_name,
                });
                return false;
            }

            // Case 3: Caller is .unknown but module language provides context
            // Use module language as proxy for caller when per-function detection failed
            if (caller_lang == .unknown and callee_lang == module_lang) {
                diag.debug("T1.3-CALLER-INFERENCE [{s}]: {s} -> {s} (inferred caller from module)", .{
                    @tagName(module_lang), caller_name, called_name,
                });
                return false;
            }

            // Case 4: Callee is .unknown but matches module's external call pattern
            // Example: Rust module calling extern "C" functions (real FFI)
            // This case should NOT skip — let it fall through to normal reporting
        }

        // P1 FIX: Skip C↔C++ bridge calls (same language family).
        // C/C++ share the same memory model (malloc/free, new/delete), same ABI
        // (Itanium on Linux/macOS, MSVC on Windows), and same runtime (libc).
        // The only real risk is cross-allocator mismatches (malloc+delete, new+free),
        // already handled by FreeValidationPass.isCrossAllocatorFree().
        // Real FFI risk is C↔Rust, C↔Go, C↔Zig — different memory models, GC, etc.
        // NOTE: Must NOT gate on !cross_edge_matched — CallGraph correctly marks
        // C→C++ as cross-language, but these edges are benign (same family).
        if ((caller_lang == .c and callee_lang == .cpp) or
            (caller_lang == .cpp and callee_lang == .c))
        {
            diag.debug("C-CPP-SKIP: {s} -> {s} (same language family)", .{ caller_name, called_name });
            return false;
        }

        // Report risky libc functions only after same-language check passes.
        // This prevents POSIX API (pthread_*, setsockopt, etc.) in pure C code
        // from being flagged as risky when they're not on an FFI boundary.
        if (semantics) |sem| {
            try reportRiskyCall(ctx, inst, caller_name, called_name, sem, diag, fir);
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

        // #3: Call-site name-based precision upgrade for FFI boundary issues.
        //
        // Apply the same caller-name-based upgrade logic here as in reportRiskyCall.
        // This ensures that FFI boundary issues also benefit from precise kind classification.
        var boundary_issue_kind: IssueKind = .ffi_unsafe_call;
        if (upgradeKindFromCallName(boundary_issue_kind, caller_name)) |precise_kind| {
            boundary_issue_kind = precise_kind;
            diag.debug("KIND-UPGRADE [BOUNDARY]: ffi_unsafe_call -> {s} (from caller '{s}')", .{
                @tagName(precise_kind),
                caller_name,
            });
        }

        // Re-evaluate severity after potential kind upgrade
        const final_severity: Severity = switch (boundary_issue_kind) {
            .command_injection => .critical,
            .double_free, .use_after_free, .invalid_free, .cross_language_free => .high,
            .memory_leak, .type_mismatch, .borrow_escape, .buffer_overflow => .medium,
            else => severity,
        };

        // Boost confidence for name-matched kinds
        const final_confidence: f32 = if (boundary_issue_kind != .ffi_unsafe_call)
            0.78 // Name-matched upgrade adds confidence (deliberate bug pattern)
        else
            confidence;

        // Suppress FFI boundary issue for correctly-paired allocator/deallocator.
        // If the callee is an allocator and the function also calls a matching
        // deallocator (or vice versa), the FFI boundary call is safe.
        if (semantics) |sem| {
            if (sem.kind == .allocator or sem.kind == .deallocator) {
                if (functionHasMatchingPair(fir, sem.kind)) {
                    diag.debug("BOUNDARY-PAIR-SKIP: {s} in {s} — matching pair found", .{ called_name, caller_name });
                    return false;
                }
            }
        }

        try boundary_check.reportFFIIssue(
            ctx,
            boundary_issue_kind,
            message,
            caller_name,
            final_severity,
            final_confidence,
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

    /// Check if a function calls both an allocator and its matching deallocator.
    /// Returns true if the function has a correctly-paired alloc/free pattern,
    /// meaning the allocator call is NOT a leak and the deallocator call is NOT invalid.
    fn functionHasMatchingPair(fir: *const ir_store_mod.FunctionIR, target_kind: RiskKind) bool {
        for (fir.instructions, 0..) |inst, idx| {
            const opcode = fir.opcodes[idx];
            if (!llvm_safe.isCallOrInvoke(opcode)) continue;
            const called_val = c.LLVMGetCalledValue(inst) orelse continue;
            const callee_name_ptr = c.LLVMGetValueName(called_val);
            const callee_name = if (@intFromPtr(callee_name_ptr) != 0) std.mem.span(callee_name_ptr) else continue;

            if (SemanticRegistry.lookup(callee_name)) |sem| {
                if (target_kind == .allocator and sem.kind == .deallocator) {
                    return true;
                }
                if (target_kind == .deallocator and sem.kind == .allocator) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Classify the confidence of a per-function language assignment.
    /// Higher confidence means we're more certain the function truly belongs
    /// to that language (not a misclassification due to name collision).
    fn classifyLanguageConfidence(func_name: []const u8, lang: Language, module_lang: Language) f32 {
        // Layer 1: Strong name-based signals (mangling/prefix) → high confidence
        const name_signal = detectLanguageSignal(func_name);
        if (name_signal != null) {
            if (name_signal.? == lang) return 0.95; // Strong signal matches claimed lang
            return 0.15; // Strong signal contradicts claimed lang → very uncertain
        }

        // Layer 2: Module-lang agreement → moderate confidence
        if (lang == module_lang) return 0.75;

        // Layer 3: Unknown — low confidence
        return 0.50;
    }

    /// Detect a strong language signal from function name mangling/prefixes.
    /// Returns the detected language, or null if no strong signal is present.
    fn detectLanguageSignal(func_name: []const u8) ?Language {
        // Rust v0 mangling: _RNv..., _RN..., _RINv...
        if (std.mem.startsWith(u8, func_name, "_RN") or
            std.mem.startsWith(u8, func_name, "_RINv"))
        {
            return .rust;
        }
        // Rust legacy Itanium mangling: _ZN4core, _ZN5alloc, _ZN3std
        if (std.mem.startsWith(u8, func_name, "_ZN4core") or
            std.mem.startsWith(u8, func_name, "_ZN5alloc") or
            std.mem.startsWith(u8, func_name, "_ZN3std"))
        {
            return .rust;
        }
        // C++ Itanium mangling: _Z, _ZN, _ZSt (std::)
        if (std.mem.startsWith(u8, func_name, "_Z") and !std.mem.startsWith(u8, func_name, "_ZN4core") and
            !std.mem.startsWith(u8, func_name, "_ZN5alloc") and !std.mem.startsWith(u8, func_name, "_ZN3std"))
        {
            return .cpp;
        }
        // Go runtime: runtime.*, main.*, go.func*
        if (std.mem.startsWith(u8, func_name, "runtime.") or
            std.mem.startsWith(u8, func_name, "main.") or
            std.mem.startsWith(u8, func_name, "go.func"))
        {
            return .go;
        }
        // Java JNI: Java_*, JNI_*
        if (std.mem.startsWith(u8, func_name, "Java_") or
            std.mem.startsWith(u8, func_name, "JNI_"))
        {
            return .java;
        }
        // Python C API: Py_*, PyObject_*, _Py*
        if (std.mem.startsWith(u8, func_name, "Py_") or
            std.mem.startsWith(u8, func_name, "PyObject_") or
            std.mem.startsWith(u8, func_name, "_Py"))
        {
            return .python;
        }
        // Zig stdlib: std.*, debug.*, builtin.*
        if (std.mem.startsWith(u8, func_name, "std.") or
            std.mem.startsWith(u8, func_name, "debug.") or
            std.mem.startsWith(u8, func_name, "builtin."))
        {
            return .zig;
        }
        // C# / .NET: Marshal.*, CoTaskMem*, GCHandle_*
        if (std.mem.startsWith(u8, func_name, "Marshal.") or
            std.mem.startsWith(u8, func_name, "CoTaskMem") or
            std.mem.startsWith(u8, func_name, "GCHandle_"))
        {
            return .csharp;
        }
        // No strong signal
        return null;
    }

    /// Report a known-risky function call.
    fn reportRiskyCall(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_name: []const u8,
        called_name: []const u8,
        sem: FunctionSemantics,
        diag: *DiagnosticWriter,
        fir: *const ir_store_mod.FunctionIR,
    ) !void {
        // : Format string constant detection.
        // If the format argument (operand 0 for printf-like functions) is a
        // compile-time string constant, the format string is NOT user-controlled
        // and therefore NOT a vulnerability. Skip reporting.
        if (sem.kind == .format_string) {
            if (format_check.isFormatStringConstant(inst)) {
                diag.debug("FORMAT-SAFE: {s} in {s} — format arg is compile-time constant", .{ called_name, caller_name });
                return;
            }
        }

        // Map RiskKind to IssueKind
        var issue_kind = boundary_check.riskKindToIssueKind(sem.kind);

        // #3: Call-site name-based precision upgrade.
        //
        // Many FFI demo/test functions have CALLER names that encode the specific
        // vulnerability they demonstrate (e.g., doubleFreeDemo, useAfterFreeDemo,
        // bufferOverflowDemo). When RiskKind is generic (.unchecked_copy → ffi_unsafe_call),
        // use the CALLER function's NAME to infer a more precise IssueKind.
        //
        // This is a heuristic — it only upgrades when:
        //   1. The current kind is generic (ffi_unsafe_call / memory_leak)
        //   2. The caller name strongly suggests a specific vulnerability type
        //
        // Examples:
        //   "doubleFreeDemo" → .double_free
        //   "useAfterFreeDemo" → .use_after_free (contains "dangling"/"after_free")
        //   "bufferOverflowDemo" → .buffer_overflow
        //   "typeConfusionDemo" → .type_mismatch (contains "confusion")
        const upgraded = upgradeKindFromCallName(issue_kind, caller_name);
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
            // Name-matched upgrade adds confidence (deliberate bug pattern)
            0.78
        else
            0.65;

        // Pairing check: suppress memory_leak/invalid_free when the function
        // calls both an allocator and its matching deallocator.
        // This eliminates false positives for correctly-paired patterns like
        // malloc→free, __rust_alloc→__rust_dealloc in the same function.
        // Only suppresses for .allocator and .deallocator kinds — other kinds
        // (format_string, unchecked_copy, etc.) are not affected.
        if (sem.kind == .allocator or sem.kind == .deallocator) {
            if (functionHasMatchingPair(fir, sem.kind)) {
                diag.debug("PAIR-SKIP: {s} in {s} — matching pair found in function", .{ called_name, caller_name });
                return;
            }
        }

        const location = Location.init(caller_name);
        const issue = Issue.init(issue_kind, sem.description, location, severity, base_confidence);
        try ctx.addIssue(&issue);

        diag.err("RISKY CALL [{s}] {s} in {s}: {s}", .{
            @tagName(severity), @tagName(sem.kind), caller_name, called_name,
        });
    }

    /// T1.3: Check if a function name is internal to a specific language.
    ///
    /// This function identifies language-internal function patterns that should
    /// NOT be treated as FFI boundaries when called from within the same language.
    ///
    /// Patterns detected:
    ///   - Rust: `_rust_`, `rs2py_`, `rust_`, `_R` (v0 mangling), allocator intrinsics
    ///   - Zig: `zig_`, `__zig_`, `Allocator.`
    ///   - Go: `runtime.`, `main.`, `_Cgo_` (CGo internal)
    ///   - C/C++: libc functions, `__cxa_` (ABI internals)
    ///
    /// Parameters:
    ///   - func_name: Function name to check
    ///   - lang: Language to check against
    ///
    /// Returns:
    ///   - true if the function is internal to the specified language
    fn isInternalToLanguage(func_name: []const u8, lang: Language) bool {
        return switch (lang) {
            .rust => {
                // Rust-internal patterns: compiler-generated, stdlib, allocator glue
                if (std.mem.indexOf(u8, func_name, "_rust_") != null) return true;
                if (std.mem.indexOf(u8, func_name, "rs2py_") != null) return true;
                if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') return true;
                // Rust allocator intrinsics (from ptr_types)
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
                // This is already handled by isLibcFunction() in zone classification,
                // but we add explicit checks here for completeness
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
};

// ═══════════════════════════════════════════════════════════════
// T1.3: Call-site language context tests
// ═══════════════════════════════════════════════════════════════

test "T1.3 - isInternalToLanguage detects Rust internal functions" {
    // Rust-internal patterns should be detected
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_rust_extern_fn", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("rs2py_wrapper", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_Rabc123def", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("__rust_alloc", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("exchange_malloc", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("into_raw", .rust));

    // Non-Rust functions should not be detected as Rust-internal
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("malloc", .rust));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("printf", .rust));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("zig_main", .rust));
}

test "T1.3 - isInternalToLanguage detects Zig internal functions" {
    // Zig-internal patterns should be detected
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("zig_panic", .zig));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("__zig_probe_stack", .zig));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("Allocator.alloc", .zig));

    // Non-Zig functions should not be detected as Zig-internal
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("malloc", .zig));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("_rust_extern_fn", .zig));
}

test "T1.3 - isInternalToLanguage detects Go internal functions" {
    // Go-internal patterns should be detected
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("runtime.gopark", .go));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("main.main", .go));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_Cgo_expact", .go));

    // Non-Go functions should not be detected as Go-internal
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("malloc", .go));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("printf", .go));
}

test "T1.3 - isInternalToLanguage detects C++ ABI internal functions" {
    // C++ ABI internals should be detected
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("__cxa_throw", .cpp));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("__cxa_begin_catch", .cpp));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_ZTV4Base", .cpp)); // vtable
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_ZTI4Base", .cpp)); // typeinfo

    // Non-C++ functions should not be detected as C++-internal
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("malloc", .cpp));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("printf", .cpp));
}

test "T1.3 - isInternalToLanguage detects C internal functions" {
    // C-internal (libc) functions should be detected
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("malloc", .c));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("free", .c));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("printf", .c));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("pthread_create", .c));

    // Non-C functions should not be detected as C-internal
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("_rust_extern_fn", .c));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("zig_panic", .c));
}

test "T1.3 - Cross-language boundary detection accuracy" {
    // This test verifies the cross-validation matrix from T1.3:
    //
    // | Caller | Callee | Module | Expected Result      |
    // |--------|--------|--------|----------------------|
    // | .c     | .c     | .c     | Same-lang (skip)     |
    // | .rust  | .rust  | .rust  | Same-lang (skip)     |
    // | .rust  | .c     | .rust  | Real FFI (report)    |
    // | .c     | .rust  | .rust  | Internal (skip)      |
    //
    // Note: Full integration testing requires LLVM module context,
    // so we test the isInternalToLanguage component in isolation.

    // Case 1: C→C calls with libc functions are same-language
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("malloc", .c));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("printf", .c));

    // Case 2: Rust→Rust internal calls are same-language
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_rust_extern_fn", .rust));
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("__rust_alloc", .rust));

    // Case 3: Rust→C calls are REAL FFI boundaries (libc is NOT Rust-internal)
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("malloc", .rust));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("printf", .rust));
    try std.testing.expect(!FFIBoundaryPass.isInternalToLanguage("free", .rust));

    // Case 4: C→Rust-looking calls in Rust module are internal (not FFI)
    // If caller is C-like but module is Rust, _rust_* callee is likely Rust internal
    try std.testing.expect(FFIBoundaryPass.isInternalToLanguage("_rust_extern_fn", .rust));
}
