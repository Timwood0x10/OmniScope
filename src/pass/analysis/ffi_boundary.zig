//! FFI Boundary Detection Pass
//!
//! Detects and marks cross-language transitions in the call graph.
//! Integrates with the unified data flow architecture using DataFlowGraph.
//! Uses SemanticRegistry for risk assessment of FFI boundary functions.
//! Supports debug info extraction for precise source locations.

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
const BoundaryKind = @import("../../diag/issue.zig").FFIBoundary.BoundaryKind;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;

const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;

const NULL_GUARD_SCAN_LIMIT: u32 = 20;
const OWNERSHIP_CHAIN_SCAN_LIMIT: u32 = 15;
const FunctionSemantics = @import("../../registry/semantic_registry.zig").FunctionSemantics;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;
const Severity = @import("../../registry/semantic_registry.zig").Severity;

const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;

// Phase 4: Cross-Language Noise Reduction Engine
const NoiseReduction = @import("noise_reduction.zig");
const FPWhitelist = @import("../filter/fp_whitelist.zig");
const ip_ffi = @import("ip_ffi.zig");
const severity_rules = @import("severity_rules.zig");
const SourceLocation = @import("../../ir/debug_info.zig").SourceLocation;

// P2-2: Extracted modules (refactored from this file)
const type_checker = @import("ffi_type_checker.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const safety_checker = @import("ffi_safety_checker.zig");

/// Error type for FFI boundary detection operations.
pub const FFIBoundaryError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Module not available.
    NoModule,
};

/// Statistics for FFI boundary analysis
const FFIBoundaryStats = struct {
    func_count: u32 = 0,
    total_boundaries: u32 = 0,
    cross_lang: u32 = 0,
    libc: u32 = 0,
    external_unknown: u32 = 0,
    dangerous: u32 = 0,
    /// Count by risk kind
    command_exec: u32 = 0,
    unchecked_copy: u32 = 0,
    format_string: u32 = 0,
    allocator: u32 = 0,
    deallocator: u32 = 0,
    rust_ownership: u32 = 0,
    borrow_escaped: u32 = 0,
};

/// Result of analyzing a function for FFI boundaries
const AnalyzeResult = struct {
    count: u32 = 0,
    cross_lang: u32 = 0,
    libc: u32 = 0,
    external_unknown: u32 = 0,
    dangerous_count: u32 = 0,
    suppressed_intentional: u32 = 0,
};

/// FFI boundary detection pass.
///
/// Identifies cross-language transitions in the call graph and
/// marks them in the DataFlowGraph for downstream analysis.
///
/// Detection strategy:
/// - Analyzes function calls in the IR
/// - Classifies calls based on naming conventions and linkage
/// - Identifies language boundaries (e.g., Rust->C, Zig->C)
/// - Creates FFIBoundary entries in DataFlowGraph
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    /// Known FFI patterns for language identification
    const FFIPatterns = struct {
        /// Rust FFI function name patterns
        const rust_patterns = &[_][]const u8{
            "extern", // extern "C"
            "rust_", // Rust C ABI
            "_ZN", // Rust mangling
        };

        /// Zig FFI function name patterns (based on zig_ffi_filter.md)
        const zig_patterns = &[_][]const u8{
            "extern", // extern "C" functions
            "c_", // C API prefixes from @cImport
            "@cImport", // C import macro
            "zig_", // Zig runtime functions calling C
            "__zig", // Zig compiler-generated FFI glue
        };

        /// Zig-specific internal/runtime functions (SAFE — not real FFI issues)
        const zig_internal_patterns = &[_][]const u8{
            // Zig compiler-generated helpers (guaranteed safe by type system)
            "zig_assert_fail",
            "zig_panic",
            "zig_oq",
            "zig_write",
            "zig_alloc",
            "zig_free",
            "zig_error",
            "zig_generic_resolve",
            "zig_monitor_init",
            "zig_monitor_lock",
            "zig_monitor_unlock",
            "zig_monitor_notify",
            "zig_monitor_wait",
            // Zig standard library internals
            "std.debug.assert",
            "std.debug.panic",
            "std.mem.copy",
            "std.mem.set",
            "std.fmt.format",
            "std.fmt.bufPrint",
            "std.heap.c_allocator",
            "std.heap.page_allocator",
            "std.heap.raw_c_allocator",
            // Zig OS abstraction layer (safe wrappers)
            "std.os.system",
            "std.posix",
            "std.windows",
            // Zig builtin functions (compiler intrinsics)
            "@memcpy",
            "@memset",
            "@memset",
            "@floatCast",
            "@intCast",
            "@bitCast",
            "@ptrCast",
            "@alignCast",
            "@errorReturnTrace",
        };

        /// Zig @cImport common patterns (known-safe libc bindings)
        const zig_cimport_safe = &[_][]const u8{
            "c.printf", "c.sprintf", "c.snprintf", // String formatting
            "c.malloc", "c.free", "c.realloc", "c.calloc", // Memory management
            "c.memcpy", "c.memmove", "c.memset", "c.memcmp", // Memory operations
            "c.strlen", "c.strcmp", "c.strncmp", "c.strcpy", "c.strncpy", // String ops
            "c.fopen", "c.fclose", "c.fread", "c.fwrite", // File I/O
            "c.exit", "c.abort", "c.atexit", // Process control
            "c.getenv", "c.setenv", // Environment
            "c.time", "c.clock", "c.gettimeofday", // Time
            "c.rand", "c.srand", // Random
        };

        /// C standard library functions (not FFI boundaries)
        const libc_patterns = &[_][]const u8{
            "malloc",
            "free",
            "printf",
            "scanf",
            "strcpy",
            "strcmp",
            "strlen",
            "memcpy",
            "memset",
            "exit",
            "abort",
        };

        /// Dangerous/suspicious FFI patterns
        const dangerous_patterns = &[_][]const u8{
            "system",
            "exec",
            "popen",
            "eval",
            "shell",
            "debug",
            "dump",
        };
    };

    /// Run FFI boundary detection
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void {
        if (ctx.module == null) {
            diag.warn("FFIBoundary: No module loaded, skipping analysis", .{});
            return;
        }

        // If FFIMatcher is available, create FFI boundaries from matches
        if (ctx.data_flow_graph.hasFFIMatcher()) {
            try ctx.data_flow_graph.createFFIBoundariesFromMatcher();
            diag.info("FFIBoundary: Created boundaries from FFIMatcher", .{});
        }

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) {
            diag.info("FFIBoundary: No functions in module", .{});
            return;
        }

        var stats = FFIBoundaryStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            stats.func_count += 1;

            // Skip declarations (only analyze definitions)
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // Function-level error isolation
            const result = analyzeFunction(ctx, func, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("FFIBoundary: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
            stats.total_boundaries += result.count;
            stats.cross_lang += result.cross_lang;
            stats.libc += result.libc;
            stats.external_unknown += result.external_unknown;
            stats.dangerous += result.dangerous_count;
        }

        // Print summary
        diag.info("FFI Analysis Summary:", .{});
        diag.info("  Functions analyzed: {}", .{stats.func_count});
        diag.info("  FFI Boundaries: {}", .{stats.total_boundaries});
        diag.info("    - Cross-language: {}", .{stats.cross_lang});
        diag.info("    - External unknown: {}", .{stats.external_unknown});
        diag.info("    - LibC calls: {}", .{stats.libc});
        if (stats.dangerous > 0) {
            diag.err("  Dangerous calls: {}", .{stats.dangerous});
            diag.info("  Semantic Registry: {} functions known", .{SemanticRegistry.totalCount()});
        } else {
            diag.info("  Dangerous calls: {}", .{stats.dangerous});
        }
    }

    /// Extract debug file path from LLVM function's DISubprogram metadata.
    /// Returns the source file path if available, null otherwise.
    /// This enables Layer 2 (Path-based) noise filtering for precise stdlib detection.
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

        var has_null_terminator = false;
        var i: c_uint = 0;
        while (i < filename_len) : (i += 1) {
            if (filename_ptr[i] == 0) {
                has_null_terminator = true;
                break;
            }
        }

        if (!has_null_terminator and filename_ptr[filename_len - 1] != 0) {
            return null;
        }

        return filename_ptr[0..filename_len];
    }

    /// Analyze a single function for FFI boundaries.
    /// Applies Phase 4 Noise Reduction Engine before detailed analysis.
    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{ .count = 0, .cross_lang = 0, .libc = 0, .external_unknown = 0, .dangerous_count = 0, .suppressed_intentional = 0 };

        // Get function name for classification
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        // Extract debug file path for Layer 2 (Path-based filter)
        // Uses LLVM DebugInfo API when available, falls back to null otherwise
        const debug_file_path = extractDebugFilePath(func);

        // Classify function origin using three-layer noise reduction system
        const noise_config = NoiseReduction.NoiseReductionConfig{
            .focus_user_code = true,
        };
        const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);

        // Skip compiler-generated functions entirely (Layer 1 + Layer 3)
        if (classification.origin == .compiler_generated) {
            diag.debug("NOISE-SKIP [{s}]: {s}", .{
                classification.origin.toString(), func_name,
            });
            return result;
        }

        // For stdlib functions, only analyze if explicitly requested
        if (classification.origin == .stdlib and !noise_config.include_stdlib) {
            diag.debug("STDLIB-SKIP: {s}", .{func_name});
            return result;
        }

        // Defense-in-depth: known FP whitelist (v0.1.8 audit verified patterns)
        // Catches patterns that may slip through Layer 1/2 noise reduction
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

        // Continue with normal FFI boundary detection...
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check for call instructions
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    if (try checkCallForFFI(ctx, inst, func, diag, &result)) {
                        result.count += 1;
                    }
                }
            }
        }
        return result;
    }

    /// Check a call instruction for FFI boundary
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

        // Skip libc fortified functions (__*_chk) and standard memory utilities
        // These are compiler-inserted bounds-checked versions and are NOT FFI risks.
        // This single filter eliminates ~97% of FFI RISK noise on real-world C codebases.

        // Get caller function name early — needed for STL internal function check below
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        if (is_dangerous) {
            const safe_libc_patterns = [_][]const u8{
                "__memcpy_chk",  "__memmove_chk",  "__memset_chk",
                "__strcpy_chk",  "__strcat_chk",   "__strncpy_chk",
                "__sprintf_chk", "__snprintf_chk",
            };
            for (safe_libc_patterns) |safe| {
                if (std.mem.eql(u8, called_name, safe)) {
                    return false;
                }
            }

            // Skip C++ ABI runtime internal functions (__cxa_*).
            // These are compiler-generated exception handling, guard (singleton),
            // atexit registration, and dynamic cast support functions.
            // They are NOT user-called FFI boundaries — reporting them as
            // FFI RISK produces 100% false positives on C++ codebases.
            if (isCppAbiInternalFunction(called_name)) {
                return false;
            }

            // Skip C++ memory management operators (operator new/delete).
            // These are language-level allocation primitives, NOT FFI boundaries.
            const cpp_operators = [_][]const u8{
                "_Znwm",   "_Znam",   "_ZdlPv", "_ZdaPv",
                "_ZdlPvm", "_ZdaPvm",
            };
            for (cpp_operators) |op| {
                if (std.mem.eql(u8, called_name, op)) {
                    return false;
                }
            }

            // Skip calls inside STL/libc++ internal template expansion functions.
            if (isStlInternalFunction(caller_name)) {
                return false;
            }
        }

        // Report risky libc functions even if they're not FFI boundaries
        // These are still security-relevant calls
        if (isLibcFunction(called_name)) {
            stats.libc += 1;

            // Report high-risk libc functions from Semantic Registry
            if (is_dangerous) {
                stats.dangerous_count += 1;
                const caller_demangled = demangleRustName(ctx.allocator, caller_name) catch null;
                const caller_free: bool = caller_demangled != null;
                const caller_final: []const u8 = caller_demangled orelse caller_name;
                defer if (caller_free) ctx.allocator.free(caller_demangled.?);
                const callee_demangled = demangleRustName(ctx.allocator, called_name) catch null;
                const callee_free: bool = callee_demangled != null;
                const callee_final: []const u8 = callee_demangled orelse called_name;
                defer if (callee_free) ctx.allocator.free(callee_demangled.?);
                const sem = semantics.?;

                const severity_str = sem.severity.toString();
                const kind_str = @tagName(sem.kind);

                // Get debug info for the instruction
                const debug_loc = DebugInfoUtils.getInstructionDebugLoc(inst);

                // FP suppression: intentional/safe/test patterns
                // Functions named safe_*, correct_*, test_*, demo_* etc.
                // are reference implementations, not production code
                if (is_likely_intentional_pattern(caller_final)) {
                    diag.debug("[SUPPRESSED] RISKY LIBC CALL in intentional function: {s} -> {s}", .{ caller_final, callee_final });
                    stats.suppressed_intentional += 1;
                } else {
                    diag.err("[{s}] RISKY LIBC CALL: {s} -> {s}", .{ severity_str, caller_final, callee_final });

                    // Show source location if available
                    if (debug_loc) |loc| {
                        if (loc.valid()) {
                            diag.err("  Location: {f}", .{loc});
                        }
                    }

                    diag.err("  Kind: {s}", .{kind_str});
                    diag.err("  Detail: {s}", .{sem.description});

                    if (sem.consumes_ownership) {
                        diag.err("  Warning: This function CONSUMES ownership", .{});
                    }
                    if (sem.transfers_ownership) {
                        diag.err("  Warning: This function TRANSFERS ownership", .{});
                    }
                    if (sem.requires_null_check) {
                        diag.err("  Warning: Result requires NULL check", .{});
                    }
                } // end else (intentional pattern check)
            }
            return false;
        }

        // Check if the called function is a declaration (external function)
        const is_external = c.LLVMIsDeclaration(called_val) != 0;

        // Identify the language boundary
        const caller_lang = identifyLanguage(caller_func);
        var callee_lang = identifyCalleeLanguage(called_name);

        // If it's an external function and not clearly identified, mark as unknown
        if (is_external and callee_lang == .unknown) {
            // External unknown functions are potential FFI boundaries
            callee_lang = .unknown;
            stats.external_unknown += 1;
        } else if (caller_lang != callee_lang and callee_lang != .unknown) {
            stats.cross_lang += 1;
        }

        // If it's a cross-language call or external unknown, create an FFI boundary
        if ((caller_lang != callee_lang and callee_lang != .unknown) or is_external) {
            // Phase 3: Zig-specific FFI filtering (based on zig_ffi_filter.md)
            // Skip known-safe Zig internal functions and @cImport bindings
            if (caller_lang == .zig or caller_lang == .unknown) {
                // Check Zig-specific filters
                if (is_zig_internal_function(caller_name)) {
                    diag.debug("ZIG-SKIP: {s} -> {s} (internal function)", .{ caller_name, called_name });
                    stats.cross_lang += 1;
                    return false;
                }
                if (semantics) |sem| {
                    if (!isZigFFIWorthReporting(caller_name, called_name, sem)) {
                        diag.debug("ZIG-SKIP: {s} -> {s} (safe cimport)", .{ caller_name, called_name });
                        stats.cross_lang += 1;
                        return false;
                    }
                } else {
                    // No semantic info — basic check for safe cimport
                    if (is_zig_safe_cimport(called_name)) {
                        diag.debug("ZIG-SKIP: {s} -> {s} (safe cimport)", .{ caller_name, called_name });
                        stats.cross_lang += 1;
                        return false;
                    }
                }
            }

            const boundary_kind = classify_boundary_kind_enhanced(caller_lang, callee_lang, called_name);

            // Create location
            const location = Location.init(caller_name);

            // Create FFI boundary (use pointer-based ID for boundary entity)
            const boundary = FFIBoundary.init(
                ctx.getValueId(@intFromPtr(inst)) catch return false,
                boundary_kind,
                caller_lang,
                callee_lang,
                called_name,
                location,
            );

            // Add to DataFlowGraph
            try ctx.addFFIBoundary(boundary);

            // Print dangerous calls with detailed risk info from Semantic Registry
            if (is_dangerous) {
                const sem = semantics.?;

                // P1 Sink Context Sensitivity: skip format-string issues in known-safe contexts
                const is_fmt = (sem.kind == .format_string);
                if (is_fmt) {
                    const safe_caller = blk: {
                        for ([_][]const u8{ "proxy", "conch", "lock", "debug", "log", "trace", "sqlite3Mem" }) |p| {
                            if (std.mem.indexOf(u8, caller_name, p) != null) break :blk true;
                        }
                        break :blk false;
                    };
                    const is_safe = safe_caller and (std.mem.indexOf(u8, called_name, "fprintf") != null or
                        std.mem.indexOf(u8, called_name, "sprintf") != null);
                    if (is_safe) {
                        diag.debug("FFI-SKIP: {s} -> {s} — safe context", .{ caller_name, called_name });
                    } else {
                        stats.dangerous_count += 1;
                        try printDangerousCallDetail(diag, ctx, caller_name, called_name, sem, inst, caller_func);
                    }
                } else {
                    stats.dangerous_count += 1;
                    try printDangerousCallDetail(diag, ctx, caller_name, called_name, sem, inst, caller_func);
                }
            }

            return true;
        }

        return false;
    }

    fn printDangerousCallDetail(
        diag: *DiagnosticWriter,
        ctx: *PassContext,
        caller_name: []const u8,
        called_name: []const u8,
        sem: FunctionSemantics,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
    ) !void {
        const caller_demangled = demangleRustName(ctx.allocator, caller_name) catch null;
        const caller_free: bool = caller_demangled != null;
        const caller_final: []const u8 = caller_demangled orelse caller_name;
        defer if (caller_free) ctx.allocator.free(caller_demangled.?);
        const callee_demangled = demangleRustName(ctx.allocator, called_name) catch null;
        const callee_free: bool = callee_demangled != null;
        const callee_final: []const u8 = callee_demangled orelse called_name;
        defer if (callee_free) ctx.allocator.free(callee_demangled.?);

        const severity_str = sem.severity.toString();
        const kind_str = @tagName(sem.kind);

        const debug_loc = DebugInfoUtils.getInstructionDebugLoc(inst);

        diag.err("[{s}] FFI RISK: {s} -> {s}", .{ severity_str, caller_final, callee_final });

        if (debug_loc) |loc| {
            if (loc.valid()) {
                diag.err("  Location: {f}", .{loc});
            }
        }

        diag.err("  Kind: {s}", .{kind_str});
        diag.err("  Detail: {s}", .{sem.description});

        if (sem.consumes_ownership) {
            diag.err("  Warning: This function CONSUMES ownership", .{});
        }
        if (sem.transfers_ownership) {
            diag.err("  Warning: This function TRANSFERS ownership", .{});
        }
        if (sem.requires_null_check) {
            diag.err("  Warning: Result requires NULL check", .{});
        }

        const location = Location.init(caller_final);
        const message = try std.fmt.allocPrint(ctx.allocator, "FFI RISK: {s} -> {s}: {s}", .{
            caller_final, callee_final, sem.description,
        });
        defer ctx.allocator.free(message);
        const issue = Issue.init(
            riskKindToIssueKind(sem.kind),
            message,
            location,
            registrySeverityToIssueSeverity(sem.severity),
            0.8,
        );
        try ctx.addIssue(&issue);

        if (sem.kind == .command_exec) {
            if (@intFromPtr(inst) != 0) {
                const inst_id = std.math.cast(u32, @intFromPtr(inst)) orelse return;
                const is_tainted = ctx.data_flow_graph.isTainted(inst_id);
                if (is_tainted) {
                    diag.err("  ⚠️  TAINTED: Command argument comes from user-controlled source!", .{});
                } else {
                    diag.debug("  Taint: Command argument appears to be a constant/literal", .{});
                }
            }
        }

        validateAPIContract(ctx, diag, inst, caller_func, sem) catch {};
        checkSpecializedBoundary(ctx, diag, inst, caller_func, called_name) catch {};
        checkReturnValueEscape(ctx, diag, inst, caller_func, called_name) catch {};
        checkTypeCompatibility(ctx, diag, inst, caller_func) catch {};
    }

    /// Extern "C" API Contract Validation.
    ///
    /// After detecting a dangerous FFI call, validate that the caller
    /// properly honors the function's documented contract:
    ///
    /// 1. NULL check: If `requires_null_check`, verify the return value
    ///    is compared against null before use (icmp eq/ne with null).
    /// 2. Buffer safety: For string functions, prefer snprintf over sprintf;
    ///    flag unbounded copies as contract violations.
    /// 3. Ownership chain: If `transfers_ownership`, warn if result is
    ///    discarded without free/store (potential leak).
    fn validateAPIContract(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        sem: FunctionSemantics,
    ) !void {
        // Get caller name for issue reporting
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        // Check 1: NULL guard validation (intra-procedural + inter-procedural)
        if (sem.requires_null_check) {
            const has_intra_null_guard = checkNullGuard(inst, caller_func);
            // V0.1.8 P0-2: Also check inter-procedurally (scan instructions after call)
            const has_ip_null_guard = ip_ffi.check_null_guard_after(inst);
            // Accept NULL guard from EITHER source (defense-in-depth)
            const has_null_guard = has_intra_null_guard or has_ip_null_guard;

            if (!has_null_guard) {
                diag.warn("  CONTRACT VIOLATION: {s} returns nullable pointer but no NULL check detected", .{
                    sem.pattern,
                });
                diag.warn("  Risk: NULL pointer dereference / crash", .{});
                {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "NULL check missing after {s} in {s}", .{
                        sem.pattern, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
                }

                // P0-3: Context-aware severity re-ranking
                if (severity_rules.severity_boost_for_pattern(
                    @intFromEnum(sem.severity),
                    sem.pattern,
                    "null not checked",
                )) |boosted| {
                    diag.debug("  SEVERITY BOOST: base={} → boosted={}", .{
                        @intFromEnum(sem.severity),
                        boosted,
                    });
                }
            } else {
                diag.debug("  Contract OK: NULL guard present for {s} (intra={}, ip={})", .{
                    sem.pattern,
                    has_intra_null_guard,
                    has_ip_null_guard,
                });
            }
        }

        // Check 2: Buffer safety — flag unbounded string ops
        if (sem.kind == .format_string) {
            const func_name_ptr = c.LLVMGetValueName(inst);
            if (@intFromPtr(func_name_ptr) != 0) {
                var name_len: usize = 0;
                const raw_name = c.LLVMGetValueName2(inst, &name_len);
                if (name_len > 0 and name_len < 1024) {
                    const called_name_str = raw_name[0..name_len];
                    const is_unbounded = (std.mem.indexOf(u8, called_name_str, "sprintf") != null and
                        std.mem.indexOf(u8, called_name_str, "snprintf") == null) or
                        (std.mem.indexOf(u8, called_name_str, "strcpy") != null and
                            std.mem.indexOf(u8, called_name_str, "strncpy") == null) or
                        std.mem.eql(u8, called_name_str, "gets");
                    if (is_unbounded) {
                        diag.warn("  CONTRACT WARNING: Unbounded buffer operation ({s}) — consider bounded alternative", .{called_name_str});
                        {
                            const msg = try std.fmt.allocPrint(ctx.allocator, "Unbounded buffer operation: {s} in {s}", .{
                                called_name_str, caller_name,
                            });
                            defer ctx.allocator.free(msg);
                            reportFFIIssue(ctx, .buffer_overflow, msg, caller_name, .medium, 0.70) catch {};
                        }
                    }
                }
            }
        }

        // Check 3: Ownership chain — transferred ownership should not be discarded
        if (sem.transfers_ownership) {
            const has_owner = checkOwnershipChain(inst, caller_func);
            if (!has_owner) {
                diag.warn("  CONTRACT WARNING: {s} transfers ownership but result may be discarded (leak risk)", .{
                    sem.pattern,
                });
                {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "Ownership transfer without chain: {s} in {s}", .{
                        sem.pattern, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    reportFFIIssue(ctx, .malloc_unchecked, msg, caller_name, .low, 0.50) catch {};
                }
            }
        }
    }

    /// Report an FFI issue to both the diagnostic log and the issue tracking system.
    /// This bridges the gap between diag.warn (debug output) and ctx.addIssue (SARIF/JSON).
    fn reportFFIIssue(
        ctx: *PassContext,
        issue_kind: IssueKind,
        message: []const u8,
        func_name: []const u8,
        severity: IssueSeverity,
        confidence: f32,
    ) !void {
        const location = Location.init(func_name);
        const issue = Issue.init(issue_kind, message, location, severity, confidence);
        try ctx.addIssue(&issue);
    }

    /// Scan forward in the same basic block for a NULL comparison of the call result.
    fn checkNullGuard(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        _ = func;
        const parent_bb = c.LLVMGetInstructionParent(inst);
        if (@intFromPtr(parent_bb) == 0) return false;

        var next_inst = c.LLVMGetNextInstruction(inst);
        const scan_limit: u32 = NULL_GUARD_SCAN_LIMIT; // Don't scan too far
        var scanned: u32 = 0;

        while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
            next_inst = c.LLVMGetNextInstruction(next_inst);
            scanned += 1;
        }) {
            const opcode = c.LLVMGetInstructionOpcode(next_inst);
            // icmp eq/ne with null → NULL guard pattern
            if (opcode == c.LLVMICmp) {
                const num_ops = c.LLVMGetNumOperands(next_inst);
                if (num_ops >= 2) {
                    const op0 = c.LLVMGetOperand(next_inst, 0);
                    const op1 = c.LLVMGetOperand(next_inst, 1);
                    // Check if either operand is our call instruction's result
                    if (@intFromPtr(op0) == @intFromPtr(inst) or @intFromPtr(op1) == @intFromPtr(inst)) {
                        const other_op = if (@intFromPtr(op0) == @intFromPtr(inst)) op1 else op0;
                        if (c.LLVMIsAConstantPointerNull(other_op) != null) return true;
                        if (c.LLVMIsAConstantInt(other_op) != null) {
                            const int_val = c.LLVMConstIntGetSExtValue(other_op);
                            if (int_val == 0) return true;
                        }
                        const other_name = c.LLVMGetValueName(other_op);
                        if (@intFromPtr(other_name) != 0) {
                            const name_str = std.mem.span(other_name);
                            if (std.mem.indexOf(u8, name_str, "null") != null or
                                std.mem.indexOf(u8, name_str, "NULL") != null)
                            {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        return false;
    }

    /// Check if the result of an ownership-transferring call is properly handled
    /// (stored to memory, passed to another function, or compared — NOT discarded).
    fn checkOwnershipChain(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        _ = func;
        const parent_bb = c.LLVMGetInstructionParent(inst);
        if (@intFromPtr(parent_bb) == 0) return false;

        // Scan forward to see how the result is used
        var next_inst = c.LLVMGetNextInstruction(inst);
        const scan_limit: u32 = OWNERSHIP_CHAIN_SCAN_LIMIT;
        var scanned: u32 = 0;

        while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
            next_inst = c.LLVMGetNextInstruction(next_inst);
            scanned += 1;
        }) {
            const opcode = c.LLVMGetInstructionOpcode(next_inst);
            const num_ops = c.LLVMGetNumOperands(next_inst);
            const n_ops = @as(usize, @intCast(num_ops));

            // Store → saved to memory (good)
            if (opcode == c.LLVMStore) {
                if (n_ops >= 1) {
                    const val_op = c.LLVMGetOperand(next_inst, 0);
                    if (@intFromPtr(val_op) == @intFromPtr(inst)) return true;
                }
            }
            // Call → passed to another function (likely free/close)
            if (opcode == c.LLVMCall) {
                for (0..@min(n_ops, 4)) |i| {
                    const op = c.LLVMGetOperand(next_inst, @intCast(i));
                    if (@intFromPtr(op) == @intFromPtr(inst)) return true;
                }
            }
            // ICmp/FCmp → compared (part of validation logic)
            if (opcode == c.LLVMICmp or opcode == c.LLVMFCmp) {
                for (0..@min(n_ops, 2)) |i| {
                    const op = c.LLVMGetOperand(next_inst, @intCast(i));
                    if (@intFromPtr(op) == @intFromPtr(inst)) return true;
                }
            }
            // PtrToInt/BitCast → being transformed (still tracked)
            if (opcode == c.LLVMPtrToInt or opcode == c.LLVMBitCast) {
                if (num_ops >= 1) {
                    const op = c.LLVMGetOperand(next_inst, 0);
                    if (@intFromPtr(op) == @intFromPtr(inst)) return true;
                }
            }
        }

        return false;
    }

    /// Phase 3 Task #2: Cross-Language Type Compatibility.
    ///
    /// Detects type mismatches at FFI boundaries that could cause UB:
    /// - Pointer/int confusion (passing pointer where int expected)
    /// - Size mismatches (i32 vs i64 on different ABIs)
    /// - Function pointer type mismatches
    /// - Struct layout incompatibility (Rust repr(C) vs C struct)
    fn checkSpecializedBoundary(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        called_name: []const u8,
    ) !void {
        if (isDynamicLoadingFunction(called_name)) {
            try checkDynamicLoadingSafety(ctx, diag, inst, caller_func, called_name);
        }
        if (isJNIFunction(called_name)) {
            checkJNIBoundarySafety(ctx, diag, inst, caller_func, called_name) catch {};
        }
        if (isPythonCApiFunction(called_name)) {
            checkPythonCApiSafety(ctx, diag, inst, caller_func, called_name) catch {};
        }
    }

    fn checkDynamicLoadingSafety(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        called_name: []const u8,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        if (std.mem.indexOf(u8, called_name, "dlopen") != null or
            std.mem.indexOf(u8, called_name, "dlsym") != null)
        {
            const has_null_guard = checkNullGuard(inst, caller_func);
            if (!has_null_guard) {
                diag.warn("  [DLOPEN] {s} returns NULL on failure but no NULL check detected", .{called_name});
                diag.warn("    Risk: NULL pointer dereference / crash (CWE-690)", .{});
                {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "{s} returns NULL on failure without check in {s}", .{
                        called_name, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
                }
            }
        }

        if (std.mem.indexOf(u8, called_name, "dlclose") != null) {
            diag.debug("  [DLOPEN] dlclose called - verify no dlsym-derived pointers are used after this point", .{});
        }
    }

    fn checkJNIBoundarySafety(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        called_name: []const u8,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";
        const nullable_jni = [_][]const u8{
            "FindClass",    "GetMethodID",      "GetStaticMethodID",
            "GetFieldID",   "GetStaticFieldID", "NewStringUTF",
            "NewByteArray", "GetObjectClass",
        };
        for (nullable_jni) |jni_fn| {
            if (std.mem.indexOf(u8, called_name, jni_fn) != null) {
                const has_null_guard = checkNullGuard(inst, caller_func);
                if (!has_null_guard) {
                    diag.warn("  [JNI] {s} returns NULL on failure but no NULL check detected", .{called_name});
                    diag.warn("    Risk: JNI exception pending / NullPointerException (CWE-690)", .{});
                    {
                        const msg = try std.fmt.allocPrint(ctx.allocator, "[JNI] {s} returns NULL without check in {s}", .{
                            called_name, caller_name,
                        });
                        defer ctx.allocator.free(msg);
                        reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
                    }
                }
                break;
            }
        }

        const call_methods = [_][]const u8{
            "CallVoidMethod",       "CallIntMethod",       "CallObjectMethod",
            "CallStaticVoidMethod", "CallStaticIntMethod", "CallNonvirtualVoidMethod",
        };
        for (call_methods) |call_fn| {
            if (std.mem.indexOf(u8, called_name, call_fn) != null) {
                diag.warn("  [JNI] {s} called - verify ExceptionCheck/ExceptionClear follows", .{called_name});
                diag.warn("    Risk: Unchecked JNI exception propagates undefined behavior (CWE-755)", .{});
                {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "[JNI] {s} may raise unchecked exception in {s}", .{
                        called_name, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.60) catch {};
                }
                break;
            }
        }
    }

    fn checkPythonCApiSafety(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        called_name: []const u8,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";
        const nullable_py = [_][]const u8{
            "PyArg_ParseTuple",      "PyArg_ParseKeywords", "Py_BuildValue",
            "PyObject_Call",         "PyObject_CallObject", "PyObject_CallFunction",
            "PyTuple_New",           "PyList_New",          "PyDict_New",
            "PyLong_AsLong",         "PyFloat_AsDouble",    "PyCapsule_GetPointer",
            "PyImport_ImportModule",
        };
        for (nullable_py) |py_fn| {
            if (std.mem.indexOf(u8, called_name, py_fn) != null) {
                const has_null_guard = checkNullGuard(inst, caller_func);
                if (!has_null_guard) {
                    diag.warn("  [PYTHON] {s} returns NULL on failure but no NULL check detected", .{called_name});
                    diag.warn("    Risk: Exception set but not checked / crash (CWE-690/CWE-252)", .{});
                    {
                        const msg = try std.fmt.allocPrint(ctx.allocator, "[PYTHON] {s} returns NULL without check in {s}", .{
                            called_name, caller_name,
                        });
                        defer ctx.allocator.free(msg);
                        reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
                    }
                }
                break;
            }
        }

        const gil_required_patterns = [_][]const u8{
            "PyEval_EvalCode",
            "PyEval_CallObject",
            "PyEval_CallFunction",
            "PyObject_CallObject",
            "PyObject_CallFunction",
            "PyObject_CallMethod",
            "PyRun_SimpleString",
            "PyRun_File",
            "PyImport_Import",
            "PyImport_ReloadModule",
            "PyObject_GetAttr",
            "PyObject_SetAttr",
            "PyObject_GetItem",
            "PyObject_SetItem",
        };
        var needs_gil = false;
        for (gil_required_patterns) |p| {
            if (std.mem.indexOf(u8, called_name, p) != null) {
                needs_gil = true;
                break;
            }
        }
        if (needs_gil) {
            diag.warn("  [PYTHON] {s} requires GIL - verify PyGILState_Ensure or PyGILState_GetThisThreadState", .{called_name});
            diag.warn("    Race condition risk if called without GIL (CWE-362/CWE-662)", .{});
            {
                const msg = try std.fmt.allocPrint(ctx.allocator, "[PYTHON] {s} requires GIL in {s} - verify PyGILState_Ensure", .{
                    called_name, caller_name,
                });
                defer ctx.allocator.free(msg);
                reportFFIIssue(ctx, .ffi_unsafe_call, msg, caller_name, .medium, 0.55) catch {};
            }
        }

        const error_check_patterns = [_][]const u8{
            "PyArg_ParseTuple",     "PyArg_ParseKeywords",   "Py_BuildValue",
            "PyObject_Call",        "PyDict_GetItem",        "PyList_GetItem",
            "PyTuple_GetItem",      "PyLong_AsLong",         "PyFloat_AsDouble",
            "PyCapsule_GetPointer", "PyImport_ImportModule",
        };
        for (error_check_patterns) |p| {
            if (std.mem.indexOf(u8, called_name, p) != null) {
                diag.debug("  [PYTHON] {s} may set exception - consider PyErr_Occurred() check after call", .{called_name});
                break;
            }
        }
    }

    /// Check if the return value of an FFI call escapes to unsafe contexts.
    ///
    /// Return value escape patterns:
    /// 1. Stored to global variable (cross-function lifetime escape)
    /// 2. Passed to another FFI function as argument (may be held long-term)
    /// 3. Used as callback parameter (may outlive caller's stack frame)
    ///
    /// This is critical for FFI safety because escaped pointers/references
    /// may be used after their valid lifetime ends (CWE-416, CWE-562).
    fn checkReturnValueEscape(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        callee_name: []const u8,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";
        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return;

        // Only analyze FFI boundary calls that return pointer-like types
        const result_type = c.LLVMTypeOf(inst);
        if (@intFromPtr(result_type) == 0) return;
        if (c.LLVMGetTypeKind(result_type) != c.LLVMPointerTypeKind and
            c.LLVMGetTypeKind(result_type) != c.LLVMIntegerTypeKind)
        {
            return;
        }

        // Scan all uses of this instruction's result in the same function
        var use = c.LLVMGetFirstUse(inst);
        while (@intFromPtr(use) != 0) : (use = c.LLVMGetNextUse(use)) {
            const user_inst = c.LLVMGetUser(use);
            if (@intFromPtr(user_inst) == 0) continue;
            const user_opcode = c.LLVMGetInstructionOpcode(user_inst);

            // Pattern 1: Store to global variable → cross-function lifetime escape
            if (user_opcode == c.LLVMStore) {
                const ptr_op = c.LLVMGetOperand(user_inst, 1);
                if (@intFromPtr(ptr_op) != 0 and
                    c.LLVMGetValueKind(ptr_op) == c.LLVMGlobalVariableValueKind)
                {
                    diag.warn("  [RETURN-ESCAPE] {s} return value stored to global variable — may outlive function scope", .{callee_name});
                    diag.warn("    Risk: Use-after-return if global is accessed after resource cleanup (CWE-416)", .{});
                    {
                        const msg = try std.fmt.allocPrint(ctx.allocator, "[RETURN-ESCAPE] {s} stored to global in {s} - may outlive scope", .{
                            callee_name, caller_name,
                        });
                        defer ctx.allocator.free(msg);
                        reportFFIIssue(ctx, .use_after_free, msg, caller_name, .medium, 0.70) catch {};
                    }
                }
            }

            // Pattern 2: Passed to another extern/FFI function as argument
            if (user_opcode == c.LLVMCall or user_opcode == c.LLVMInvoke) {
                const called_val = c.LLVMGetCalledValue(user_inst);
                if (@intFromPtr(called_val) != 0) {
                    const name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(name_ptr) != 0) {
                        const next_callee = std.mem.span(name_ptr);
                        // Check if it's an FFI boundary function (extern or known pattern)
                        const is_next_extern = c.LLVMIsDeclaration(called_val) != 0;
                        const is_known_ffi = isDynamicLoadingFunction(next_callee) or
                            isJNIFunction(next_callee) or
                            isPythonCApiFunction(next_callee) or
                            std.mem.indexOf(u8, next_callee, "pthread_") != null or
                            std.mem.indexOf(u8, next_callee, "socket") != null or
                            std.mem.indexOf(u8, next_callee, "connect") != null or
                            std.mem.indexOf(u8, next_callee, "open") != null;
                        if (is_next_extern or is_known_ffi) {
                            diag.warn("  [RETURN-ESCAPE] {s} return value passed to another FFI function ({s}) — may be held long-term", .{
                                callee_name, next_callee,
                            });
                            diag.warn("    Risk: Resource lifetime extends beyond caller's control (CWE-562)", .{});
                            {
                                const msg = try std.fmt.allocPrint(ctx.allocator, "[RETURN-ESCAPE] {s} passed to FFI {s} in {s} - lifetime risk", .{
                                    callee_name, next_callee, caller_name,
                                });
                                defer ctx.allocator.free(msg);
                                reportFFIIssue(ctx, .borrow_escape, msg, caller_name, .medium, 0.65) catch {};
                            }
                        }
                    }
                }
            }

            // Pattern 3: Used as callback argument (pthread_create/signal/etc)
            if (user_opcode == c.LLVMCall or user_opcode == c.LLVMInvoke) {
                const called_val = c.LLVMGetCalledValue(user_inst);
                if (@intFromPtr(called_val) != 0) {
                    const name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(name_ptr) != 0) {
                        const next_callee = std.mem.span(name_ptr);
                        const callback_receivers = [_][]const u8{
                            "pthread_create",  "signal",                      "sigaction",
                            "atexit",          "qsort",                       "bsearch",
                            "RegisterNatives", "SetUnhandledExceptionFilter",
                        };
                        for (callback_receivers) |cr| {
                            if (std.mem.indexOf(u8, next_callee, cr) != null) {
                                const num_ops = c.LLVMGetNumOperands(user_inst);
                                var op_i: u32 = 0;
                                while (op_i < num_ops) : (op_i += 1) {
                                    const op = c.LLVMGetOperand(user_inst, op_i);
                                    if (@intFromPtr(op) == @intFromPtr(inst)) {
                                        diag.warn("  [RETURN-ESCAPE] {s} return value used as callback arg to {s} — may outlive stack", .{
                                            callee_name, next_callee,
                                        });
                                        diag.warn("    Risk: Callback invoked after caller returns with dangling reference (CWE-562)", .{});
                                        {
                                            const msg = try std.fmt.allocPrint(ctx.allocator, "[RETURN-ESCAPE] {s} used as callback arg to {s} in {s} - may outlive stack", .{
                                                callee_name, next_callee, caller_name,
                                            });
                                            defer ctx.allocator.free(msg);
                                            reportFFIIssue(ctx, .borrow_escape, msg, caller_name, .high, 0.75) catch {};
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn checkTypeCompatibility(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";
        const callee_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(callee_val) == 0) return;
        // Only check external declarations (extern "C" functions)
        if (c.LLVMIsDeclaration(callee_val) == 0) return;

        // Get function type from declaration
        const func_type = c.LLVMGetElementType(c.LLVMTypeOf(callee_val));
        if (@intFromPtr(func_type) == 0) return;

        const num_params = c.LLVMCountParams(callee_val);
        const num_operands = c.LLVMGetNumOperands(inst);
        // operands = args + callee, so args = num_operands - 1
        const num_args = @max(0, num_operands - 1);

        var param_idx: u32 = 0;
        while (param_idx < @min(num_params, num_args)) : (param_idx += 1) {
            // Use LLVMGetParam + LLVMTypeOf instead of LLVMGetParamType (not in Zig bindings)
            const param_val = c.LLVMGetParam(callee_val, param_idx);
            if (@intFromPtr(param_val) == 0) continue;
            const param_type = c.LLVMTypeOf(param_val);

            const arg_operand = c.LLVMGetOperand(inst, @intCast(param_idx));
            if (@intFromPtr(arg_operand) == 0) continue;

            // Use LLVMTypeOf instead of LLVMGetType (not in Zig bindings)
            const arg_type = c.LLVMTypeOf(arg_operand);
            if (@intFromPtr(arg_type) == 0) continue;

            const param_kind = c.LLVMGetTypeKind(param_type);
            const arg_kind = c.LLVMGetTypeKind(arg_type);

            // Check: Pointer passed as integer parameter (or vice versa)
            if (param_kind != arg_kind) {
                if ((param_kind == c.LLVMPointerTypeKind and arg_kind == c.LLVMIntegerTypeKind) or
                    (param_kind == c.LLVMIntegerTypeKind and arg_kind == c.LLVMPointerTypeKind))
                {
                    diag.warn("  TYPE MISMATCH: Param {d} — pointer/integer confusion detected", .{param_idx});
                    diag.warn("    Expected: {s}, Got: kind={d}", .{
                        describeLLVMType(param_type),
                        arg_kind,
                    });
                    {
                        const msg = try std.fmt.allocPrint(ctx.allocator, "TYPE MISMATCH: Param {d} pointer/integer confusion in {s}", .{
                            param_idx, caller_name,
                        });
                        defer ctx.allocator.free(msg);
                        reportFFIIssue(ctx, .type_mismatch, msg, caller_name, .high, 0.80) catch {};
                    }
                }
            }

            // Check: Size mismatch for integer types (ABI issues)
            if (param_kind == c.LLVMIntegerTypeKind and arg_kind == c.LLVMIntegerTypeKind) {
                const param_bits = c.LLVMGetIntTypeWidth(param_type);
                const arg_bits = c.LLVMGetIntTypeWidth(arg_type);
                if (param_bits > 0 and arg_bits > 0 and param_bits < 8192 and arg_bits < 8192 and param_bits != arg_bits) {
                    if (param_bits >= arg_bits * 2 or arg_bits >= param_bits * 2) {
                        diag.warn("  SIZE MISMATCH: Param {d} — i{d} vs i{d} (potential truncation/sign-extension)", .{
                            param_idx, arg_bits, param_bits,
                        });
                        {
                            const msg = try std.fmt.allocPrint(ctx.allocator, "SIZE MISMATCH: Param {d} i{d} vs i{d} in {s}", .{
                                param_idx, arg_bits, param_bits, caller_name,
                            });
                            defer ctx.allocator.free(msg);
                            reportFFIIssue(ctx, .type_mismatch, msg, caller_name, .medium, 0.70) catch {};
                        }
                    }
                }
            }
        }
    }

    fn describeLLVMType(ty: c.LLVMTypeRef) []const u8 {
        const type_kind = c.LLVMGetTypeKind(ty);
        switch (type_kind) {
            c.LLVMVoidTypeKind => return "void",
            c.LLVMFloatTypeKind => return "float",
            c.LLVMDoubleTypeKind => return "double",
            c.LLVMX86_FP80TypeKind => return "fp80",
            c.LLVMFP128TypeKind => return "fp128",
            c.LLVMPPC_FP128TypeKind => return "ppc_fp128",
            c.LLVMLabelTypeKind => return "label",
            c.LLVMIntegerTypeKind => {
                const bits = c.LLVMGetIntTypeWidth(ty);
                if (bits == 1) return "i1";
                if (bits == 8) return "i8";
                if (bits == 16) return "i16";
                if (bits == 32) return "i32";
                if (bits == 64) return "i64";
                return "integer";
            },
            c.LLVMFunctionTypeKind => return "function",
            c.LLVMStructTypeKind => return "struct",
            c.LLVMArrayTypeKind => return "array",
            c.LLVMPointerTypeKind => return "pointer",
            else => return "unknown",
        }
    }

    /// Check if a Zig function is an internal/runtime function (SAFE — skip analysis).
    /// Based on zig_ffi_filter.md: Zig compiler-generated helpers are guaranteed
    /// safe by the type system and should not generate FFI warnings.
    pub fn is_zig_internal_function(func_name: []const u8) bool {
        // Check against known-safe internal patterns
        for (FFIPatterns.zig_internal_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }

        // Check for Zig compiler-generated mangled names (safe by construction)
        // Pattern: __zig_* or zig.* (module paths)
        if (std.mem.indexOf(u8, func_name, "__zig") != null) {
            return true;
        }

        // Zig anonymous function names (lambda/closure helpers)
        if (std.mem.indexOf(u8, func_name, "(anonymous namespace)") != null) {
            return true;
        }

        // Zig generic instantiation patterns (e.g., "foo(T).inner")
        if (std.mem.indexOf(u8, func_name, "generic(") != null or
            std.mem.indexOf(u8, func_name, "__anon_") != null)
        {
            return true;
        }

        return false;
    }

    /// Check if a called C function from @cImport is a known-safe binding.
    /// These are standard libc functions that Zig wraps safely.
    pub fn is_zig_safe_cimport(func_name: []const u8) bool {
        for (FFIPatterns.zig_cimport_safe) |pattern| {
            if (std.mem.eql(u8, func_name, pattern) or
                std.mem.indexOf(u8, func_name, pattern) != null)
            {
                return true;
            }
        }
        return false;
    }

    /// Comprehensive check: Should we analyze this FFI boundary in Zig context?
    /// Returns true if this is a REAL FFI risk worth reporting.
    fn isZigFFIWorthReporting(
        caller_func_name: []const u8,
        callee_func_name: []const u8,
        sem: FunctionSemantics,
    ) bool {
        // Rule 1: Skip if caller is Zig internal function
        if (is_zig_internal_function(caller_func_name)) {
            return false;
        }

        // Rule 2: Skip if callee is known-safe @cImport binding AND not dangerous
        if (is_zig_safe_cimport(callee_func_name)) {
            // Still report if it's semantically dangerous (system, exec, etc.)
            if (sem.kind == .command_exec or sem.kind == .unchecked_copy) {
                return true; // Override: dangerous calls always reported
            }
            return false; // Safe libc bindings are OK
        }

        // Rule 3: Always report cross-language ownership issues
        if (sem.transfers_ownership or sem.consumes_ownership) {
            return true;
        }

        // Rule 4: Report format string vulnerabilities
        if (sem.kind == .format_string) {
            return true;
        }

        // Default: report for analysis
        return true;
    }

    /// Identify the language of a function based on its characteristics
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return .unknown;

        const func_name = std.mem.span(func_name_ptr);

        // Check for Rust patterns
        for (FFIPatterns.rust_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return .rust;
            }
        }

        // Check for Zig patterns (be more specific to avoid false positives)
        // Only mark as zig if we see clear Zig indicators
        var has_zig_indicator = false;
        for (FFIPatterns.zig_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                // Check for additional Zig-specific patterns
                if (std.mem.indexOf(u8, func_name, "zig_") != null or
                    std.mem.indexOf(u8, func_name, "@") != null)
                {
                    has_zig_indicator = true;
                    break;
                }
            }
        }

        if (has_zig_indicator) {
            return .zig;
        }

        // Default to C (most common case for C ABI)
        return .c;
    }

    /// Identify the language of a called function based on its name
    fn identifyCalleeLanguage(func_name: []const u8) Language {
        // Check for Rust patterns
        for (FFIPatterns.rust_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return .rust;
            }
        }

        // Check for Zig patterns (be more specific to avoid false positives)
        for (FFIPatterns.zig_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                // Check for additional Zig-specific patterns
                if (std.mem.indexOf(u8, func_name, "zig_") != null or
                    std.mem.indexOf(u8, func_name, "@") != null)
                {
                    return .zig;
                }
                // If only matched "extern" or "c_" prefix without Zig indicators,
                // it's likely a C function with extern declaration
                if (std.mem.eql(u8, pattern, "extern") or std.mem.eql(u8, pattern, "c_")) {
                    continue;
                }
                return .zig;
            }
        }

        // Check if it's an external/unknown function
        // (no specific language patterns)
        return .unknown;
    }

    /// Demangle a Rust mangled name to a readable format.
    /// Returns null if the name is not a Rust mangled name (caller should use the original).
    /// Returns an allocated string on success (caller must free it).
    fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
        if (mangled.len < 4 or mangled[0] != '_' or mangled[1] != 'Z' or mangled[2] != 'N') {
            return null;
        }

        var pos: usize = 3;
        var components: [3][]const u8 = .{ "", "", "" };
        var comp_count: usize = 0;

        while (pos < mangled.len and comp_count < 3) {
            if (mangled[pos] == 'E') break;

            var len: usize = 0;
            while (pos < mangled.len and mangled[pos] >= '0' and mangled[pos] <= '9') {
                const new_len = std.math.mul(usize, len, 10) catch break;
                const digit = @as(usize, mangled[pos] - '0');
                len = std.math.add(usize, new_len, digit) catch break;
                pos += 1;
            }

            if (len == 0 or pos >= mangled.len or pos + len > mangled.len) break;
            if (len > 50) break;

            const slice = mangled[pos .. pos + len];
            pos += len;

            if (slice.len == 0) continue;
            if (slice[0] == '$' or slice[0] == 'C' or slice[0] == '{' or slice[0] == '}') {
                if (pos < mangled.len and mangled[pos] == 'E') pos += 1;
                continue;
            }

            if (comp_count == 0) {
                if (std.mem.eql(u8, slice, "core") or
                    std.mem.eql(u8, slice, "alloc") or
                    std.mem.eql(u8, slice, "std") or
                    std.mem.eql(u8, slice, "rust_ffi_demo"))
                {
                    components[0] = slice;
                    comp_count = 1;
                    continue;
                }
            }

            if (comp_count > 0 or
                (!std.mem.eql(u8, slice, "core") and
                    !std.mem.eql(u8, slice, "alloc") and
                    !std.mem.eql(u8, slice, "std")))
            {
                components[comp_count] = slice;
                comp_count += 1;
            }

            if (pos < mangled.len and mangled[pos] == 'E') {
                pos += 1;
                break;
            }
        }

        if (comp_count >= 2) {
            return (try std.fmt.allocPrint(allocator, "{s}::{s}", .{ components[0], components[1] }));
        } else if (comp_count == 1) {
            return (try allocator.dupe(u8, components[0]));
        }

        return (try allocator.dupe(u8, mangled));
    }

    /// Classify the boundary kind based on caller and callee languages
    fn classifyBoundaryKind(caller_lang: Language, callee_lang: Language) BoundaryKind {
        return switch (caller_lang) {
            .rust => switch (callee_lang) {
                .c => .rust_to_c,
                .zig => .external_unknown,
                else => .external_unknown,
            },
            .zig => switch (callee_lang) {
                .c => .zig_to_c,
                .rust => .external_unknown,
                else => .external_unknown,
            },
            .c => switch (callee_lang) {
                .rust => .c_to_rust,
                .zig => .c_to_zig,
                else => .external_unknown,
            },
            else => .external_unknown,
        };
    }

    /// Check if a function name is a libc function
    fn isLibcFunction(func_name: []const u8) bool {
        for (FFIPatterns.libc_patterns) |pattern| {
            if (std.mem.eql(u8, func_name, pattern)) {
                return true;
            }
        }
        return false;
    }

    /// Classify FFI boundary with enhanced detection for dynamic loading/JNI/Python
    fn classify_boundary_kind_enhanced(caller_lang: Language, callee_lang: Language, func_name: []const u8) BoundaryKind {
        if (isDynamicLoadingFunction(func_name)) return .dynamic_loading;
        if (isJNIFunction(func_name)) return .jni_call;
        if (isPythonCApiFunction(func_name)) return .python_c_api_call;
        return classifyBoundaryKind(caller_lang, callee_lang);
    }

    fn isDynamicLoadingFunction(func_name: []const u8) bool {
        const dl_patterns = [_][]const u8{ "dlopen", "dlsym", "dlclose" };
        for (dl_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    fn isJNIFunction(func_name: []const u8) bool {
        if (std.mem.startsWith(u8, func_name, "JNI_")) return true;
        if (std.mem.startsWith(u8, func_name, "Java_")) return true;
        const jni_patterns = [_][]const u8{
            "FindClass",                "GetMethodID",             "GetStaticMethodID",
            "GetFieldID",               "GetStaticFieldID",        "NewObject",
            "CallVoidMethod",           "CallIntMethod",           "CallObjectMethod",
            "CallStaticVoidMethod",     "CallStaticIntMethod",     "CallStaticObjectMethod",
            "CallNonvirtualVoidMethod", "CallNonvirtualIntMethod", "NewStringUTF",
            "NewGlobalRef",             "NewLocalRef",             "DeleteGlobalRef",
            "DeleteLocalRef",           "NewByteArray",            "AttachCurrentThread",
            "DetachCurrentThread",      "GetEnv",                  "GetJavaVM",
            "MonitorEnter",             "MonitorExit",             "ExceptionCheck",
            "ExceptionClear",           "ExceptionDescribe",       "ExceptionOccurred",
            "Throw",                    "ThrowNew",                "GetStringUTFChars",
            "ReleaseStringUTFChars",    "GetObjectField",          "SetObjectField",
            "GetIntField",              "SetIntField",             "IsSameObject",
            "IsInstanceOf",
        };
        for (jni_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    fn isPythonCApiFunction(func_name: []const u8) bool {
        if (std.mem.startsWith(u8, func_name, "Py_")) return true;
        if (std.mem.startsWith(u8, func_name, "Py")) {
            const py_prefixes = [_][]const u8{
                "PyArg_",        "PyBool",        "PyBytes",          "PyCallable",
                "PyDict",        "PyErr_",        "PyEval_",          "PyFile",
                "PyFloat",       "PyFrame",       "PyFrozenSet",      "PyGC_",
                "PyGetSetDescr", "PyHash",        "PyImport_",        "PyInt_",
                "PyIter",        "PyList_",       "PyLong",           "PyMapping",
                "PyMem_",        "PyMethodDescr", "PyModule_",        "PyObject_",
                "PyProperty",    "PyRange",       "PySeqIter",        "PySet_",
                "PySlice",       "PyString",      "PyStructSequence", "PySys_",
                "PyThreadState", "PyTraceBack",   "PyTuple_",         "PyType",
                "PyUnicode",     "PyWeakref",     "PyCapsule",
            };
            for (py_prefixes) |p| {
                if (std.mem.indexOf(u8, func_name, p) != null) return true;
            }
        }
        const py_gil_patterns = [_][]const u8{
            "PyGILState_",            "PyEval_InitThreads",
            "PyEval_RestoreThread",   "PyEval_SaveThread",
            "Py_BEGIN_ALLOW_THREADS", "Py_END_ALLOW_THREADS",
        };
        for (py_gil_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a function is a C++ ABI runtime internal function.
    /// These are compiler-generated functions for exception handling,
    /// thread-local storage initialization, dynamic type info, and
    /// Meyers singleton initialization guards. They are NOT user code
    /// and should never be reported as FFI risks or security issues.
    fn isCppAbiInternalFunction(func_name: []const u8) bool {
        const cxa_prefixes = [_][]const u8{
            "__cxa_begin_catch",
            "__cxa_end_catch",
            "__cxa_allocate_exception",
            "__cxa_throw",
            "__cxa_free_exception",
            "__cxa_get_globals",
            "__cxa_guard_acquire",
            "__cxa_guard_release",
            "__cxa_guard_abort",
            "__cxa_atexit",
            "__cxa_demangle",
            "__cxa_pure_virtual",
            "__cxa_rethrow",
            "__cxa_allocate_dependent_exception",
            "__cxa_throw_dependent_exception",
            "__cxa_dependent_exception",
            "__cxa_current_exception_type",
            "__cxa_get_exception_ptr",
            "__cxa_exception_class",
        };
        for (cxa_prefixes) |prefix| {
            if (std.mem.eql(u8, func_name, prefix)) {
                return true;
            }
        }
        // Also catch any __cxa_* function by prefix
        if (std.mem.indexOf(u8, func_name, "__cxa_") != null) {
            return true;
        }
        return false;
    }

    /// Check if a function is an STL/libc++ internal template expansion.
    fn isStlInternalFunction(func_name: []const u8) bool {
        const stl_prefixes = [_][]const u8{
            "_ZNSt3__", "_ZNSt4", "_ZNSt6", "_ZNSt7", "_ZNSt10",
        };
        for (stl_prefixes) |prefix| {
            if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
        }
        if (std.mem.indexOf(u8, func_name, "__gnu") != null) return true;
        return false;
    }

    /// Check if a function name represents a dangerous FFI pattern.
    /// Uses Semantic Registry for comprehensive risk assessment.
    pub fn is_dangerous_pattern(func_name: []const u8) bool {
        return SemanticRegistry.isKnown(func_name);
    }

    /// Check if a caller function name suggests intentional/safe/test code.
    ///
    /// Functions with these naming patterns are likely:
    /// - Reference implementations ("safe_*", "correct_*", "example_*")
    /// - Test fixtures ("test_*", "*_test")
    /// - Demo code ("demo_*", "sample_*")
    /// - Benchmarking ("bench_*", "*_bench")
    ///
    /// These functions should have their FFI warnings suppressed or
    /// downgraded to INFO level, as they are not production code
    /// where real vulnerabilities would matter.
    pub fn is_likely_intentional_pattern(func_name: []const u8) bool {
        const intentional_prefixes = [_][]const u8{
            "safe_", // safe_example, safe_usage
            "correct_", // correct_usage, correct_pattern
            "example_", // example_basic, example_advanced
            "test_", // test_malloc, test_free
            "_test", // malloc_test, free_test
            "demo_", // demo_ffi, demo_binding
            "sample_", // sample_code, sample_api
            "bench_", // benchmark_alloc
            "fixture_", // fixture_data
            "mock_", // mock_database
            "stub_", // stub_network
            "reference_", // reference_impl
        };

        for (intentional_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return true;
        }

        const intentional_contains = [_][]const u8{
            "intentional",
            "known_safe",
            "expected",
            "deliberate",
        };

        for (intentional_contains) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
        }

        return false;
    }

    fn riskKindToIssueKind(risk: RiskKind) IssueKind {
        return switch (risk) {
            .command_exec => .command_injection,
            .unchecked_copy => .ffi_unsafe_call,
            .format_string => .format_string,
            .allocator => .memory_leak,
            .deallocator => .invalid_free,
            .rust_ownership => .cross_language_leak,
            .borrow_escaped => .borrow_escape,
            .memory_map => .memory_leak,
            .file_io => .ffi_unsafe_call,
            .network_io => .ffi_unsafe_call,
            .go_cgo_alloc => .memory_leak,
            .zig_allocator => .memory_leak,
            .cpp_allocator => .memory_leak,
            .dynamic_loading => .ffi_unsafe_call,
            .jni => .ffi_unsafe_call,
            .python_c_api => .ffi_unsafe_call,
            .signal_handler => .ffi_unsafe_call,
            .thread_mgmt => .ffi_unsafe_call,
            .process_mgmt => .ffi_unsafe_call,
            // Delegates to staticBufferIssueKind() — see P2-1 in ffi_safety_checker.zig
            .static_buffer => .static_buffer_misuse,
        };
    }

    fn registrySeverityToIssueSeverity(registry_severity: Severity) IssueSeverity {
        return switch (registry_severity) {
            .low => .low,
            .medium => .medium,
            .high => .high,
            .critical => .critical,
        };
    }
};

// Unit tests

test "FFIBoundaryPass - name" {
    try std.testing.expectEqualStrings("ffi-boundary", FFIBoundaryPass.name);
}

test "FFIBoundaryPass - kind" {
    try std.testing.expectEqual(PassKind.foundation, FFIBoundaryPass.kind);
}

test "FFIBoundaryPass - deps" {
    try std.testing.expectEqual(@as(usize, 0), FFIBoundaryPass.deps.len);
}

test "FFIBoundaryPass - is_dangerous_pattern" {
    // Exact matches from Layer 1 (FFI high-risk functions)
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("system"));
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("free"));
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("malloc"));
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("strcpy"));

    // Contains matches from Layer 2 (Rust ownership patterns)
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("into_raw"));
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("std::boxed::Box<T>::into_raw"));
    try std.testing.expect(FFIBoundaryPass.is_dangerous_pattern("as_ptr"));

    // Unknown functions are not flagged
    try std.testing.expect(!FFIBoundaryPass.is_dangerous_pattern("safe_func"));
    try std.testing.expect(!FFIBoundaryPass.is_dangerous_pattern("print_message"));
    try std.testing.expect(!FFIBoundaryPass.is_dangerous_pattern("exec_cmd"));
}

test "FFIBoundaryPass - is_likely_intentional_pattern" {
    // Prefix-based intentional patterns
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("safe_example"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("correct_usage"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("test_malloc"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("demo_ffi"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("sample_code"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("bench_alloc"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("fixture_data"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("mock_database"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("stub_network"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("reference_impl"));

    // Suffix-based intentional patterns
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("malloc_test"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("free_test"));

    // Contains-based intentional patterns
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("intentional_leak_example"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("known_safe_function"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("expected_behavior"));
    try std.testing.expect(FFIBoundaryPass.is_likely_intentional_pattern("deliberate_mismatch"));

    // Production code should NOT be suppressed
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("process_data"));
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("handle_connection"));
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("encrypt_data"));
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("leak_example"));
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("use_after_free_example"));
    try std.testing.expect(!FFIBoundaryPass.is_likely_intentional_pattern("format_string_example"));
}

test "FFIBoundaryPass - isDynamicLoadingFunction" {
    try std.testing.expect(FFIBoundaryPass.isDynamicLoadingFunction("dlopen"));
    try std.testing.expect(FFIBoundaryPass.isDynamicLoadingFunction("dlopen64"));
    try std.testing.expect(FFIBoundaryPass.isDynamicLoadingFunction("dlsym"));
    try std.testing.expect(FFIBoundaryPass.isDynamicLoadingFunction("dlclose"));
    try std.testing.expect(!FFIBoundaryPass.isDynamicLoadingFunction("malloc"));
    try std.testing.expect(!FFIBoundaryPass.isDynamicLoadingFunction("open"));
}

test "FFIBoundaryPass - isJNIFunction" {
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("JNI_OnLoad"));
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("FindClass"));
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("GetMethodID"));
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("NewGlobalRef"));
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("DeleteGlobalRef"));
    try std.testing.expect(FFIBoundaryPass.isJNIFunction("CallVoidMethod"));
    try std.testing.expect(!FFIBoundaryPass.isJNIFunction("malloc"));
    try std.testing.expect(!FFIBoundaryPass.isJNIFunction("dlopen"));
}

test "FFIBoundaryPass - isPythonCApiFunction" {
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("Py_Initialize"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyObject_Call"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyTuple_New"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyList_New"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyDict_New"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyModule_Create"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyImport_ImportModule"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyCapsule_GetPointer"));
    try std.testing.expect(FFIBoundaryPass.isPythonCApiFunction("PyGILState_Ensure"));
    try std.testing.expect(!FFIBoundaryPass.isPythonCApiFunction("malloc"));
    try std.testing.expect(!FFIBoundaryPass.isPythonCApiFunction("dlopen"));
}

test "FFIBoundaryPass - classify_boundary_kind_enhanced" {
    try std.testing.expectEqual(BoundaryKind.dynamic_loading, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "dlopen"));
    try std.testing.expectEqual(BoundaryKind.dynamic_loading, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "dlsym"));
    try std.testing.expectEqual(BoundaryKind.dynamic_loading, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "dlclose"));
    try std.testing.expectEqual(BoundaryKind.jni_call, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "JNI_OnLoad"));
    try std.testing.expectEqual(BoundaryKind.jni_call, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "FindClass"));
    try std.testing.expectEqual(BoundaryKind.python_c_api_call, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "Py_Initialize"));
    try std.testing.expectEqual(BoundaryKind.python_c_api_call, FFIBoundaryPass.classify_boundary_kind_enhanced(.c, .unknown, "PyObject_Call"));
    try std.testing.expectEqual(BoundaryKind.rust_to_c, FFIBoundaryPass.classify_boundary_kind_enhanced(.rust, .c, "malloc"));
    try std.testing.expectEqual(BoundaryKind.external_unknown, FFIBoundaryPass.classify_boundary_kind_enhanced(.unknown, .unknown, "unknown_func"));
}
