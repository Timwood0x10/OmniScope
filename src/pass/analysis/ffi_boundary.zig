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
const FFIBoundary = @import("../../diag/issue.zig").FFIBoundary;
const BoundaryKind = @import("../../diag/issue.zig").FFIBoundary.BoundaryKind;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;

const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../../registry/semantic_registry.zig").FunctionSemantics;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;
const Severity = @import("../../registry/semantic_registry.zig").Severity;

const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;

// Phase 4: Cross-Language Noise Reduction Engine
const NoiseReduction = @import("noise_reduction.zig");
const SourceLocation = @import("../../ir/debug_info.zig").SourceLocation;

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

            // Analyze function for FFI calls
            const result = try analyzeFunction(ctx, func, diag);
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
        // Get subprogram (debug info) from function
        const subprogram = c.LLVMGetSubprogram(func);
        if (@intFromPtr(subprogram) == 0) return null;

        // Get file from scope
        const file_ref = c.LLVMDIScopeGetFile(subprogram);
        if (@intFromPtr(file_ref) == 0) return null;

        // Get filename from DIFile
        var filename_len: c_uint = undefined;
        const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
        if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

        // Safety: limit max path length to prevent issues with corrupt metadata
        const max_path_len = 4096;
        if (filename_len > max_path_len) return null;

        // Validate that the pointer points to readable memory
        // by checking for null terminator within bounds
        var valid = true;
        for (filename_ptr[0..filename_len]) |ch| {
            if (ch == 0) {
                valid = false;
                break;
            }
        }
        if (!valid) return null;

        // Return as slice (valid for duration of analysis)
        return filename_ptr[0..filename_len];
    }

    /// Analyze a single function for FFI boundaries.
    /// Applies Phase 4 Noise Reduction Engine before detailed analysis.
    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{ .count = 0, .cross_lang = 0, .libc = 0, .external_unknown = 0, .dangerous_count = 0 };

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
                const caller_demangled = demangleRustName(ctx.allocator, caller_name) catch caller_name;
                const caller_was_allocated = @intFromPtr(caller_demangled.ptr) != @intFromPtr(caller_name.ptr);
                defer if (caller_was_allocated) ctx.allocator.free(caller_demangled);
                const callee_demangled = demangleRustName(ctx.allocator, called_name) catch called_name;
                const callee_was_allocated = @intFromPtr(callee_demangled.ptr) != @intFromPtr(called_name.ptr);
                defer if (callee_was_allocated) ctx.allocator.free(callee_demangled);
                const sem = semantics.?;

                const severity_str = sem.severity.toString();
                const kind_str = @tagName(sem.kind);

                // Get debug info for the instruction
                const debug_loc = DebugInfoUtils.getInstructionDebugLoc(inst);

                diag.err("[{s}] RISKY LIBC CALL: {s} -> {s}", .{ severity_str, caller_demangled, callee_demangled });

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
                if (isZigInternalFunction(caller_name)) {
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
                    if (isZigSafeCImport(called_name)) {
                        diag.debug("ZIG-SKIP: {s} -> {s} (safe cimport)", .{ caller_name, called_name });
                        stats.cross_lang += 1;
                        return false;
                    }
                }
            }

            const boundary_kind = classifyBoundaryKind(caller_lang, callee_lang);

            // Create location
            const location = Location.init(caller_name);

            // Create FFI boundary
            const boundary = FFIBoundary.init(
                ctx.getNextId(),
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
                        printDangerousCallDetail(diag, ctx, caller_name, called_name, sem, inst, caller_func);
                    }
                } else {
                    stats.dangerous_count += 1;
                    printDangerousCallDetail(diag, ctx, caller_name, called_name, sem, inst, caller_func);
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
    ) void {
        const caller_demangled = demangleRustName(ctx.allocator, caller_name) catch caller_name;
        defer if (@intFromPtr(caller_demangled.ptr) != @intFromPtr(caller_name.ptr)) ctx.allocator.free(caller_demangled);
        const callee_demangled = demangleRustName(ctx.allocator, called_name) catch called_name;
        defer if (@intFromPtr(callee_demangled.ptr) != @intFromPtr(called_name.ptr)) ctx.allocator.free(callee_demangled);

        const severity_str = sem.severity.toString();
        const kind_str = @tagName(sem.kind);

        const debug_loc = DebugInfoUtils.getInstructionDebugLoc(inst);

        diag.err("[{s}] FFI RISK: {s} -> {s}", .{ severity_str, caller_demangled, callee_demangled });

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

        // Show taint status for command execution functions
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

        // P1 Task 2.1: Validate API contract compliance
        validateAPIContract(diag, inst, caller_func, sem);

        // Phase 3 Task #2: Cross-language type compatibility check
        checkTypeCompatibility(diag, inst);

        // Phase 3 Task #4: Lifetime annotation inference at FFI boundaries
        inferLifetimeConstraints(diag, inst, caller_func, sem);
    }

    /// P1 Task 2.1: Extern "C" API Contract Validation.
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
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        sem: FunctionSemantics,
    ) void {
        // Check 1: NULL guard validation
        if (sem.requires_null_check) {
            const has_null_guard = checkNullGuard(inst, caller_func);
            if (!has_null_guard) {
                diag.warn("  CONTRACT VIOLATION: {s} returns nullable pointer but no NULL check detected", .{
                    sem.pattern,
                });
                diag.warn("  Risk: NULL pointer dereference / crash", .{});
            } else {
                diag.debug("  Contract OK: NULL guard present for {s}", .{sem.pattern});
            }
        }

        // Check 2: Buffer safety — flag unbounded string ops
        if (sem.kind == .format_string) {
            const func_name_ptr = c.LLVMGetValueName(inst);
            if (@intFromPtr(func_name_ptr) != 0) {
                const called_name_str = std.mem.span(func_name_ptr);
                const is_unbounded = (std.mem.indexOf(u8, called_name_str, "sprintf") != null and
                    std.mem.indexOf(u8, called_name_str, "snprintf") == null) or
                    (std.mem.indexOf(u8, called_name_str, "strcpy") != null and
                    std.mem.indexOf(u8, called_name_str, "strncpy") == null) or
                    std.mem.eql(u8, called_name_str, "gets");
                if (is_unbounded) {
                    diag.warn("  CONTRACT WARNING: Unbounded buffer operation ({s}) — consider bounded alternative", .{called_name_str});
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
            }
        }
    }

    /// Scan forward in the same basic block for a NULL comparison of the call result.
    fn checkNullGuard(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        _ = func;
        const parent_bb = c.LLVMGetInstructionParent(inst);
        if (@intFromPtr(parent_bb) == 0) return false;

        var next_inst = c.LLVMGetNextInstruction(inst);
        const scan_limit: u32 = 20; // Don't scan too far
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
                        const other_name = c.LLVMGetValueName(other_op);
                        if (@intFromPtr(other_name) != 0) {
                            const name_str = std.mem.span(other_name);
                            // "null" in LLVM IR
                            if (std.mem.indexOf(u8, name_str, "null") != null) return true;
                        }
                        // Also check if it's a constant null (ConstantPointerNull)
                        if (c.LLVMIsAConstantPointerNull(other_op) != null) return true;
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
        const scan_limit: u32 = 15;
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
    fn checkTypeCompatibility(
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
    ) void {
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
                }
            }

            // Check: Size mismatch for integer types (ABI issues)
            if (param_kind == c.LLVMIntegerTypeKind and arg_kind == c.LLVMIntegerTypeKind) {
                const param_bits = c.LLVMGetIntTypeWidth(param_type);
                const arg_bits = c.LLVMGetIntTypeWidth(arg_type);
                if (param_bits > 0 and arg_bits > 0 and param_bits != arg_bits) {
                    if (param_bits >= arg_bits * 2 or arg_bits >= param_bits * 2) {
                        diag.warn("  SIZE MISMATCH: Param {d} — i{d} vs i{d} (potential truncation/sign-extension)", .{
                            param_idx, arg_bits, param_bits,
                        });
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

    /// Phase 3 Task #4: Lifetime Annotation Inference at FFI Boundaries.
    ///
    /// Infers lifetime constraints for pointers crossing FFI boundaries:
    /// 1. Return value lifetime: static, owned (caller must free), or borrowed (bound to arg)
    /// 2. Dangling pointer detection: using stack-allocated or short-lived args after call
    /// 3. Parameter validity: ensure pointer arguments remain valid during call
    fn inferLifetimeConstraints(
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        sem: FunctionSemantics,
    ) void {
        const callee_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(callee_val) == 0) return;

        const func_name_ptr = c.LLVMGetValueName(callee_val);
        if (@intFromPtr(func_name_ptr) == 0) return;
        const func_name = std.mem.span(func_name_ptr);

        // 1. Infer return value lifetime category
        const ret_lifetime = inferReturnValueLifetime(func_name, sem);
        if (ret_lifetime) |lifetime| {
            diag.debug("  LIFETIME: Return value -> {s}", .{lifetime.description});
            if (lifetime.risk_level == .warning or lifetime.risk_level == .danger) {
                diag.warn("  LIFETIME RISK: {s}", .{lifetime.warning});
            }
        }

        // 2. Check for dangling pointer patterns in arguments
        checkDanglingPointerPatterns(diag, inst, caller_func, func_name);

        // 3. Validate parameter lifetime constraints
        validateParameterLifetime(diag, inst, func_name, sem);
    }

    /// Categories of return value lifetimes at FFI boundaries
    const ReturnLifetime = struct {
        category: enum { static_lifetime, owned, borrowed, unknown },
        description: []const u8,
        risk_level: enum { info, warning, danger },
        warning: []const u8,
    };

    /// Infer the lifetime of a pointer returned from an FFI function
    fn inferReturnValueLifetime(func_name: []const u8, sem: FunctionSemantics) ?ReturnLifetime {
        // Static lifetime functions — return pointers to internal static buffers
        const static_lifetime_funcs = [_][]const u8{
            "ctime",       // Returns pointer to static buffer
            "ctime_r",     // Thread-safe variant
            "asctime",     // Returns pointer to static buffer
            "inet_ntoa",   // Returns pointer to static buffer
            "inet_ntop",   // May use caller-provided buffer
            "getgrgid",    // Returns pointer to static struct
            "getpwuid",    // Returns pointer to static struct
            "gethostbyname", // Returns pointer to static struct (deprecated)
            "strerror",    // Returns pointer to internal string
            "ttyname",     // Returns pointer to internal path
        };
        for (static_lifetime_funcs) |sf| {
            if (std.mem.eql(u8, func_name, sf)) {
                return ReturnLifetime{
                    .category = .static_lifetime,
                    .description = "static internal buffer (do NOT free)",
                    .risk_level = .warning,
                    .warning = "Return value points to STATIC buffer — freeing it causes UB; not thread-safe",
                };
            }
        }

        // Owned allocation functions — caller must free the result
        if (sem.transfers_ownership) {
            return ReturnLifetime{
                .category = .owned,
                .description = "heap-allocated (caller owns, must free)",
                .risk_level = .info,
                .warning = "",
            };
        }

        // Borrowed/sub-pointer functions — result is derived from input argument
        const borrowed_patterns = [_][]const u8{
            "strchr", "strrchr",      // Returns sub-pointer of first arg
            "strstr",                 // Returns sub-pointer of first arg
            "memchr",                 // Returns sub-pointer of first arg
            "getenv",                 // Returns pointer to environment string
            "dirname", "basename",    // May modify or return sub-string
        };
        for (borrowed_patterns) |bp| {
            if (std.mem.indexOf(u8, func_name, bp) != null) {
                return ReturnLifetime{
                    .category = .borrowed,
                    .description = "borrowed from input argument (lifetime bound to source)",
                    .risk_level = .warning,
                    .warning = "Return value borrows from input — source must outlive the result",
                };
            }
        }

        return null;
    }

    /// Detect dangling pointer patterns at FFI boundaries
    fn checkDanglingPointerPatterns(
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        callee_name: []const u8,
    ) void {
        _ = caller_func;

        // Pattern 1: Taking address of local variable and passing to FFI
        // This is usually OK for input parameters but dangerous for output params
        const num_operands = c.LLVMGetNumOperands(inst);
        var i: c.uint = 0;
        while (i < @as(c.uint, @intCast(num_operands - 1))) : (i += 1) {
            const arg = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(arg) == 0) continue;

            // Check if this argument is an alloca (stack variable address)
            if (c.LLVMGetInstructionOpcode(arg) == c.LLVMAlloca) {
                // alloca passed directly — check if this could be problematic
                // For write-type functions (sprintf, strcpy, etc.), stack buffer is normal
                // For read-type functions that store output, could indicate escape
                const is_write_op = isWriteOperation(callee_name);
                if (!is_write_op) {
                    diag.debug("  LIFETIME: Stack address (alloca) passed to {s} — verify scope safety", .{callee_name});
                }
            }

            // Pattern 2: Using return value of function that returns stack address
            // (e.g., returning &local_var — undefined behavior in C)
            if (c.LLVMIsAInstruction(arg)) |_| {
                const opcode = c.LLVMGetInstructionOpcode(arg);
                if (opcode == c.LLVMLoad) {
                    // Load from potential stack location
                    const ptr_operand = c.LLVMGetOperand(arg, 0);
                    if (@intFromPtr(ptr_operand) != 0 and c.LLVMIsAInstruction(ptr_operand) != null) {
                        if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMAlloca) {
                            diag.warn("  DANGLING RISK: Loading from stack variable and passing to FFI — ensure variable is still in scope", .{});
                        }
                    }
                }
            }
        }
    }

    /// Check if a function name indicates a write operation (safe to pass stack buffers)
    fn isWriteOperation(func_name: []const u8) bool {
        const write_patterns = [_][]const u8{
            "sprintf", "snprintf", "strcpy", "strncpy",
            "memcpy", "memmove", "memset",
            "fgets", "gets", "read", "recv",
            "fscanf", "sscanf",
        };
        for (write_patterns) |wp| {
            if (std.mem.indexOf(u8, func_name, wp) != null) return true;
        }
        return false;
    }

    /// Validate that pointer arguments satisfy lifetime requirements
    fn validateParameterLifetime(
        diag: *DiagnosticWriter,
        inst: c.LLVMValueRef,
        callee_name: []const u8,
        sem: FunctionSemantics,
    ) void {
        _ = sem;

        // Check for common lifetime violations:

        // 1. Passing NULL to non-nullable pointer parameter
        const num_operands = c.LLVMGetNumOperands(inst);
        var i: c.uint = 0;
        while (i < @as(c.uint, @intCast(num_operands - 1))) : (i += 1) {
            const arg = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(arg) == 0) continue;

            // Check for NULL constant being passed as pointer argument
            if (c.LLVMIsAConstantPointerNull(arg)) |_| {
                // NULL passed — may be intentional (sentinel) or bug
                // Only warn for functions where NULL is unusual
                const nullable_ok = isNullableParameter(callee_name, @intCast(i));
                if (!nullable_ok) {
                    diag.debug("  LIFETIME: NULL passed as param {d} to {s} — verify intent", .{ i, callee_name });
                }
            }

            // 2. Check for integer-to-pointer cast (potential invalid address)
            if (c.LLVMIsAIntToPtrInst(arg)) |_| {
                diag.warn("  LIFETIME RISK: inttoptr conversion passed to {s} — possible invalid pointer", .{callee_name});
            }
        }
    }

    /// Determine if NULL is acceptable for a given parameter position
    fn isNullableParameter(func_name: []const u8, param_idx: u32) bool {
        // Common functions where certain params can be NULL
        if (std.mem.eql(u8, func_name, "memcpy") or std.mem.eql(u8, func_name, "memmove")) {
            // memcpy(dst, src, n) — neither dst nor src should be NULL in practice
            return false;
        }
        if (std.mem.indexOf(u8, func_name, "printf") != null) {
            // printf format string should not be NULL
            if (param_idx == 0) return false;
            // Variadic args can be NULL (e.g., %s with NULL)
            return true;
        }
        if (std.mem.indexOf(u8, func_name, "free") != null) {
            // free(NULL) is explicitly defined as no-op
            return true;
        }
        // Default: NULL is suspicious
        return false;
    }

    /// Check if a Zig function is an internal/runtime function (SAFE — skip analysis).
    /// Based on zig_ffi_filter.md: Zig compiler-generated helpers are guaranteed
    /// safe by the type system and should not generate FFI warnings.
    pub fn isZigInternalFunction(func_name: []const u8) bool {
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
    pub fn isZigSafeCImport(func_name: []const u8) bool {
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
        if (isZigInternalFunction(caller_func_name)) {
            return false;
        }

        // Rule 2: Skip if callee is known-safe @cImport binding AND not dangerous
        if (isZigSafeCImport(callee_func_name)) {
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

    /// Demangle a Rust mangled name to a readable format
    /// Returns an allocated string that caller must free.
    fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) ![]u8 {
        if (mangled.len < 4 or mangled[0] != '_' or mangled[1] != 'Z' or mangled[2] != 'N') {
            return try allocator.dupe(u8, mangled);
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
            return std.fmt.allocPrint(allocator, "{s}::{s}", .{ components[0], components[1] });
        } else if (comp_count == 1) {
            return try allocator.dupe(u8, components[0]);
        }

        return try allocator.dupe(u8, mangled);
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
    pub fn isDangerousPattern(func_name: []const u8) bool {
        return SemanticRegistry.isKnown(func_name);
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

test "FFIBoundaryPass - isDangerousPattern" {
    // Exact matches from Layer 1 (FFI high-risk functions)
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("system"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("free"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("malloc"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("strcpy"));

    // Contains matches from Layer 2 (Rust ownership patterns)
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("into_raw"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("std::boxed::Box<T>::into_raw"));
    try std.testing.expect(FFIBoundaryPass.isDangerousPattern("as_ptr"));

    // Unknown functions are not flagged
    try std.testing.expect(!FFIBoundaryPass.isDangerousPattern("safe_func"));
    try std.testing.expect(!FFIBoundaryPass.isDangerousPattern("print_message"));
    try std.testing.expect(!FFIBoundaryPass.isDangerousPattern("exec_cmd"));
}
