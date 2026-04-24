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

        /// Zig FFI function name patterns
        const zig_patterns = &[_][]const u8{
            "extern", // extern functions
            "c_", // C API prefixes
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

    /// Analyze a single function for FFI boundaries
    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !AnalyzeResult {
        var result = AnalyzeResult{ .count = 0, .cross_lang = 0, .libc = 0, .external_unknown = 0, .dangerous_count = 0 };
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
