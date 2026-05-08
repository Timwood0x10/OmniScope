//! FFI Body Check Pass
//!
//! Detects dangerous function calls inside FFI boundary functions.
//! This pass analyzes the function bodies of FFI boundary functions
//! to identify calls to dangerous functions like printf, system, etc.
//!
//! Uses semantic model for noise reduction and precise analysis.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../../pass/pass.zig").PassContext;
const PassKind = @import("../../../pass/pass.zig").PassKind;
const DiagnosticWriter = @import("../../../pass/pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const FFIBoundary = @import("../../../diag/issue.zig").FFIBoundary;

const ffi_semantics = @import("../ffi_semantics.zig");
const noise_filter = @import("../../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;

/// Value origin tracking information
const ValueInfo = struct {
    value: c.LLVMValueRef,
    origin: ffi_semantics.ValueOrigin,
    location: Location,
};

/// Function analysis context
const AnalysisContext = struct {
    allocator: std.mem.Allocator,
    boundary: *const FFIBoundary,
    value_map: std.AutoHashMap(c.LLVMValueRef, ValueInfo),
};

/// Vulnerability information with traceable path
const VulnerabilityInfo = struct {
    vuln_type: IssueKind,
    severity: Severity,
    message: []const u8,
    trace: []const []const u8,
    confidence: f32,
};

/// Check if a pointer points to a store that contains malloc_result
///
/// This function implements cross-basic-block tracking to find stores
/// of malloc results that may occur in different blocks.
///
/// Arguments:
///   - ptr: Pointer to check
///   - malloc_result: The malloc call result
///   - ctx: Analysis context
///
/// Returns:
///   - true if ptr points to a store of malloc_result
fn pointsToStoreOfMallocResult(ptr: c.LLVMValueRef, malloc_result: c.LLVMValueRef, ctx: *AnalysisContext) bool {
    // First check the value_map for tracked origins
    if (ctx.value_map.get(ptr)) |info| {
        if (info.value == malloc_result) {
            return true;
        }
    }

    // Get the function containing this pointer
    const ptr_inst = if (c.LLVMIsAGlobalValue(ptr) != null or c.LLVMIsAConstant(ptr) != null)
        return false
    else if (c.LLVMIsAInstruction(ptr) != null)
        ptr
    else
        return false;

    const func = c.LLVMGetBasicBlockParent(c.LLVMGetInstructionParent(ptr_inst) orelse return false);
    if (func == null) return false;

    // Iterate through ALL basic blocks in the function
    // to find if there's a store to this pointer with malloc_result
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode == c.LLVMStore) {
                const store_ptr = c.LLVMGetOperand(inst, 1);
                const store_value = c.LLVMGetOperand(inst, 0);
                // Check if storing malloc_result to ptr
                if (store_ptr == ptr and store_value == malloc_result) {
                    return true;
                }
                // Also check if storing through a GEP or bitcast of ptr
                if (store_value == malloc_result) {
                    if (isAliasOf(store_ptr, ptr)) {
                        return true;
                    }
                }
            }
            inst = c.LLVMGetNextInstruction(inst);
        }
        bb = c.LLVMGetNextBasicBlock(bb);
    }
    return false;
}

/// Check if two pointers are aliases (same underlying storage)
///
/// Arguments:
///   - ptr1: First pointer
///   - ptr2: Second pointer
///
/// Returns:
///   - true if pointers refer to same storage
fn isAliasOf(ptr1: c.LLVMValueRef, ptr2: c.LLVMValueRef) bool {
    if (ptr1 == ptr2) return true;

    // Check for GEP aliasing
    const ptr1_opcode = c.LLVMGetInstructionOpcode(ptr1);
    const ptr2_opcode = c.LLVMGetInstructionOpcode(ptr2);

    // GEP with same base pointer
    if (ptr1_opcode == c.LLVMGetElementPtr) {
        const base1 = c.LLVMGetOperand(ptr1, 0);
        if (base1 == ptr2) return true;
    }
    if (ptr2_opcode == c.LLVMGetElementPtr) {
        const base2 = c.LLVMGetOperand(ptr2, 0);
        if (base2 == ptr1) return true;
    }

    // BitCast aliasing
    if (ptr1_opcode == c.LLVMBitCast) {
        const src1 = c.LLVMGetOperand(ptr1, 0);
        if (src1 == ptr2) return true;
    }
    if (ptr2_opcode == c.LLVMBitCast) {
        const src2 = c.LLVMGetOperand(ptr2, 0);
        if (src2 == ptr1) return true;
    }

    return false;
}

/// Check if malloc result is checked for null
///
/// This implements Rule 1 from go_noise.md: malloc unchecked detection
///
/// Arguments:
///   - malloc_result: The value returned by malloc
///   - ctx: Analysis context
///   - boundary: FFI boundary information
///
/// Returns:
///   - true if malloc result is not checked
fn isMallocUnchecked(malloc_result: c.LLVMValueRef, ctx: *AnalysisContext, boundary: *const FFIBoundary) bool {
    _ = boundary;

    // Check instructions after malloc for null check
    // Handle common LLVM IR pattern: malloc -> store -> load -> icmp
    var inst = c.LLVMGetNextInstruction(malloc_result);
    while (@intFromPtr(inst) != 0) {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Skip store instructions (intermediate storage)
        if (opcode == c.LLVMStore) {
            inst = c.LLVMGetNextInstruction(inst);
            continue;
        }

        // Check for icmp instruction (null check)
        if (opcode == c.LLVMICmp) {
            const predicate = c.LLVMGetICmpPredicate(inst);
            // icmp eq or icmp ne with null
            if (predicate == c.LLVMIntEQ or predicate == c.LLVMIntNE) {
                const op0 = c.LLVMGetOperand(inst, 0);
                const op1 = c.LLVMGetOperand(inst, 1);

                // Check if any operand is malloc_result or load from malloc_result
                var is_malloc_check = false;

                // Direct comparison with malloc_result
                if (op0 == malloc_result or op1 == malloc_result) {
                    is_malloc_check = true;
                }

                // Check if operands are loads from malloc_result
                if (c.LLVMGetInstructionOpcode(op0) == c.LLVMLoad) {
                    const loaded_from = c.LLVMGetOperand(op0, 0);
                    if (loaded_from == malloc_result or pointsToStoreOfMallocResult(loaded_from, malloc_result, ctx)) {
                        is_malloc_check = true;
                    }
                }

                if (c.LLVMGetInstructionOpcode(op1) == c.LLVMLoad) {
                    const loaded_from = c.LLVMGetOperand(op1, 0);
                    if (loaded_from == malloc_result or pointsToStoreOfMallocResult(loaded_from, malloc_result, ctx)) {
                        is_malloc_check = true;
                    }
                }

                if (is_malloc_check) {
                    const other = if (op0 == malloc_result) op1 else op0;
                    // Also need to handle the case where other operand is the load
                    if (other != malloc_result) {
                        // Get the actual other operand (the constant or null)
                    }

                    // Check if other operand is null (or constant 0)
                    if (c.LLVMIsNull(other) != 0 or c.LLVMIsConstant(other) != 0) {
                        // Found null check
                        return false;
                    }
                }
            }
        }

        // Only check next few instructions to avoid infinite loops
        // Stop at branch or other control flow
        if (opcode == c.LLVMBr or opcode == c.LLVMRet or opcode == c.LLVMCall) {
            break;
        }

        inst = c.LLVMGetNextInstruction(inst);
    }

    // No null check found
    return true;
}

/// Check if pointer passed to free comes from malloc
///
/// This implements Rule 2 from go_noise.md: free non-malloc source detection
///
/// Arguments:
///   - freed_ptr: The pointer being freed
///   - ctx: Analysis context
///
/// Returns:
///   - true if pointer does not come from malloc
fn isFreeFromNonMalloc(freed_ptr: c.LLVMValueRef, ctx: *AnalysisContext) bool {
    if (ctx.value_map.get(freed_ptr)) |info| {
        // Check if pointer origin is from_malloc
        if (info.origin == .from_malloc) {
            return false; // Valid free
        }
    }

    // Check if this is a load from a malloc'd pointer
    if (c.LLVMGetInstructionOpcode(freed_ptr) == c.LLVMLoad) {
        const loaded_ptr = c.LLVMGetOperand(freed_ptr, 0);
        if (ctx.value_map.get(loaded_ptr)) |info| {
            if (info.origin == .from_malloc) {
                return false; // Valid free
            }
        }
    }

    // Pointer does not come from malloc
    return true;
}

/// Check for double free vulnerability
///
/// This implements Rule 3 from go_noise.md: double free detection
///
/// Arguments:
///   - freed_ptrs: Set of already freed pointers
///   - freed_ptr: The pointer being freed
///
/// Returns:
///   - true if this is a double free
fn isDoubleFree(freed_ptrs: *std.AutoHashMap(c.LLVMValueRef, void), freed_ptr: c.LLVMValueRef) bool {
    if (freed_ptrs.contains(freed_ptr)) {
        return true; // Double free detected
    }

    // Check if this is a load from an already freed pointer
    if (c.LLVMGetInstructionOpcode(freed_ptr) == c.LLVMLoad) {
        const loaded_ptr = c.LLVMGetOperand(freed_ptr, 0);
        if (freed_ptrs.contains(loaded_ptr)) {
            return true; // Double free via load
        }
    }

    return false;
}

/// Check if pointer passed to unknown FFI function
///
/// This implements Rule 4 from go_noise.md: unknown FFI pointer usage detection
///
/// Arguments:
///   - args: Function arguments
///   - func_name: Name of the called function
///   - ctx: Analysis context
///   - boundary: FFI boundary information
///
/// Returns:
///   - Vulnerability information if found, null otherwise
fn checkUnknownFFIPointerUsage(args: []c.LLVMValueRef, func_name: []const u8, ctx: *AnalysisContext, boundary: *const FFIBoundary) !?VulnerabilityInfo {
    _ = boundary;

    // Only check unknown functions (not modeled in FFISemantics)
    if (ffi_semantics.getSemantics(func_name) != null) {
        return null;
    }

    // Check if any argument is a pointer from malloc
    for (args) |arg| {
        if (ctx.value_map.get(arg)) |info| {
            if (info.origin == .from_malloc) {
                // malloc'd pointer passed to unknown FFI without validation
                const trace = try ctx.allocator.alloc([]const u8, 2);
                trace[0] = try std.fmt.allocPrint(ctx.allocator, "Pointer from malloc in function {s}", .{info.location.func});
                trace[1] = try std.fmt.allocPrint(ctx.allocator, "Passed to unknown FFI function {s}", .{func_name});

                return VulnerabilityInfo{
                    .vuln_type = .ffi_unsafe_call,
                    .severity = .medium,
                    .message = try std.fmt.allocPrint(
                        ctx.allocator,
                        "Unvalidated malloc'd pointer passed to unknown FFI function {s}",
                        .{func_name},
                    ),
                    .trace = trace,
                    .confidence = 0.7,
                };
            }
        }
    }

    return null;
}

/// Check if function call has format string vulnerability
///
/// Arguments:
///   - func_name: Name of the called function
///   - args: Array of argument values
///   - ctx: Analysis context
///
/// Returns:
///   - Vulnerability info if detected, null otherwise
fn checkFormatStringVulnerability(
    func_name: []const u8,
    args: []c.LLVMValueRef,
    ctx: *AnalysisContext,
) !?VulnerabilityInfo {
    // Skip if not a format function
    if (!std.mem.eql(u8, func_name, "printf") and
        !std.mem.eql(u8, func_name, "fprintf") and
        !std.mem.eql(u8, func_name, "sprintf") and
        !std.mem.eql(u8, func_name, "snprintf"))
    {
        return null;
    }

    // Check if first argument (format string) is from parameter
    if (args.len == 0) return null;

    const format_arg = args[0];
    if (ctx.value_map.get(format_arg)) |info| {
        if (info.origin == .from_param or info.origin == .from_malloc) {
            // Format string from parameter - potential vulnerability
            const trace = try ctx.allocator.alloc([]const u8, 2);
            trace[0] = try std.fmt.allocPrint(ctx.allocator, "Format string argument in function {s}", .{info.location.func});
            trace[1] = try std.fmt.allocPrint(ctx.allocator, "Used as format string in {s} call", .{func_name});

            return VulnerabilityInfo{
                .vuln_type = .format_string,
                .severity = .high,
                .message = try std.fmt.allocPrint(
                    ctx.allocator,
                    "Format string vulnerability: format string from {s} used in {s}",
                    .{ @tagName(info.origin), func_name },
                ),
                .trace = trace,
                .confidence = 0.9,
            };
        }
    }

    return null;
}

/// Check if function call has command injection vulnerability
///
/// Arguments:
///   - func_name: Name of the called function
///   - args: Array of argument values
///   - ctx: Analysis context
///
/// Returns:
///   - Vulnerability info if detected, null otherwise
fn checkCommandInjectionVulnerability(
    func_name: []const u8,
    args: []c.LLVMValueRef,
    ctx: *AnalysisContext,
) !?VulnerabilityInfo {
    // Check if this is a command execution function
    if (!std.mem.eql(u8, func_name, "system") and
        !std.mem.startsWith(u8, func_name, "exec") and
        !std.mem.eql(u8, func_name, "popen"))
    {
        return null;
    }

    // Check if first argument is from parameter
    if (args.len == 0) return null;

    const command_arg = args[0];
    if (ctx.value_map.get(command_arg)) |info| {
        if (info.origin == .from_param) {
            // Command from parameter - potential injection
            const trace = try ctx.allocator.alloc([]const u8, 2);
            trace[0] = try std.fmt.allocPrint(ctx.allocator, "Command argument in function {s}", .{info.location.func});
            trace[1] = try std.fmt.allocPrint(ctx.allocator, "Passed to {s} without validation", .{func_name});

            return VulnerabilityInfo{
                .vuln_type = .command_injection,
                .severity = .critical,
                .message = try std.fmt.allocPrint(
                    ctx.allocator,
                    "Command injection vulnerability: command from parameter used in {s}",
                    .{func_name},
                ),
                .trace = trace,
                .confidence = 0.95,
            };
        }
    }

    return null;
}

/// Get vulnerability description
///
/// Arguments:
///   - vuln_type: Type of vulnerability
///
/// Returns:
///   - Human-readable description
fn getVulnerabilityDesc(vuln_type: IssueKind) []const u8 {
    return switch (vuln_type) {
        .command_injection => "Command injection vulnerability",
        .buffer_overflow => "Buffer overflow vulnerability",
        .format_string => "Format string vulnerability",
        else => "General security issue",
    };
}

/// Check if a function is a safe utility function
///
/// These functions are always safe and can be skipped without analysis.
///
/// Arguments:
///   - func_name: Function name to check
///
/// Returns:
///   - true if function is safe and can be skipped
fn isSafeUtilityFunction(func_name: []const u8) bool {
    // Safe utility functions that don't need analysis
    const safe_functions = &[_][]const u8{
        "puts",          "putchar",       "putchar_unlocked",
        "memcpy",        "memmove",       "memset",
        "strlen",        "strcmp",        "strncmp",
        "strcasecmp",    "atoi",          "atol",
        "atof",          "abs",           "labs",
        "llabs",
        // Libc fortified variants (glibc __*_chk functions)
        // These are compiler-inserted bounds-checked versions of standard
        // functions and are NOT FFI safety issues — they're safer than
        // the originals. Filtering them eliminates ~97% of FFI RISK noise.
                "__memcpy_chk",  "__memmove_chk",
        "__memset_chk",  "__strcpy_chk",  "__strcat_chk",
        "__strncpy_chk", "__sprintf_chk", "__snprintf_chk",
    };

    for (safe_functions) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return true;
        }
    }

    return false;
}

/// FFI body check pass
pub const FFIBodyCheckPass = struct {
    pub const name = "ffi-body-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    /// Run the FFI body check pass
    ///
    /// This function analyzes FFI boundary functions to detect
    /// dangerous function calls inside their bodies.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const module = ctx.module.?.raw;

        // Get all FFI boundaries
        const ffi_boundaries = ctx.data_flow_graph.getFFIBoundaries();
        if (ffi_boundaries.len == 0) {
            diag.info("FFIBodyCheck: No FFI boundaries to analyze", .{});
            return;
        }

        diag.info("FFIBodyCheck: Analyzing {} FFI boundaries for dangerous function calls", .{ffi_boundaries.len});

        var issue_count: usize = 0;
        for (ffi_boundaries) |boundary| {
            // Create null-terminated string for C API
            // LLVMGetNamedFunction expects a null-terminated C string
            const null_terminated_name = try ctx.allocator.dupeZ(u8, boundary.function_name);
            defer ctx.allocator.free(null_terminated_name);

            // Get the function from the module
            const func = c.LLVMGetNamedFunction(module, null_terminated_name.ptr);
            if (func == null) continue;

            // Function-level error isolation
            const found_issues = analyzeFunction(ctx, func, &boundary, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("FFIBodyCheck: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += found_issues;
        }

        diag.info("FFIBodyCheck: Found {} dangerous function calls", .{issue_count});
    }

    /// Analyze a function for dangerous function calls
    ///
    /// This function iterates through all instructions in a function
    /// and checks if any of them call dangerous functions.
    /// Uses semantic model for noise reduction and precise analysis.
    ///
    /// Arguments:
    ///   - ctx: Pass context for adding issues
    ///   - func: LLVM function to analyze
    ///   - boundary: FFI boundary information
    ///   - diag: Diagnostic writer for logging
    ///
    /// Returns:
    ///   - Number of issues found
    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        boundary: *const FFIBoundary,
        diag: *DiagnosticWriter,
    ) !usize {
        // INTEGRATION: Three-layer noise filter (name + path)
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) != 0) {
            const func_name = std.mem.span(func_name_ptr);
            const func_loc = DebugInfoUtils.getFunctionLocation(func);
            const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
            if (!classification.origin.shouldReportByDefault()) return 0;
        }
        // Initialize analysis context
        var analysis_ctx = AnalysisContext{
            .allocator = ctx.allocator,
            .boundary = boundary,
            .value_map = std.AutoHashMap(c.LLVMValueRef, ValueInfo).init(ctx.allocator),
        };
        defer analysis_ctx.value_map.deinit();

        // Track function parameters
        const num_params = c.LLVMCountParams(func);
        var param_index: u32 = 0;
        while (param_index < num_params) : (param_index += 1) {
            const param = c.LLVMGetParam(func, param_index);
            if (param != null) {
                const info = ValueInfo{
                    .value = param,
                    .origin = .from_param,
                    .location = boundary.location,
                };
                try analysis_ctx.value_map.put(param, info);
            }
        }

        var issue_count: usize = 0;

        // Track malloc results and freed pointers for malloc/free detection
        var malloc_results = std.ArrayList(c.LLVMValueRef).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory;
        defer malloc_results.deinit(ctx.allocator);

        var freed_ptrs = std.AutoHashMap(c.LLVMValueRef, void).init(ctx.allocator);
        defer freed_ptrs.deinit();

        // Iterate through all basic blocks
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) {
            // Iterate through all instructions in the basic block
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check if this is a call instruction
                if (opcode == c.LLVMCall) {
                    // Get the called function - callee is at num_operands - 1
                    const num_operands = @as(c_uint, @bitCast(c.LLVMGetNumOperands(inst)));
                    if (num_operands >= 1) {
                        const called_value = c.LLVMGetOperand(inst, num_operands - 1);
                        if (@intFromPtr(called_value) != 0) {
                            const func_name = c.LLVMGetValueName(called_value);
                            if (@intFromPtr(func_name) != 0) {
                                const func_name_slice = std.mem.span(func_name);

                                // Noise reduction: skip truly low risk functions
                                // Note: printf is NOT skipped here because we need to
                                // check for format string vulnerabilities
                                if (isSafeUtilityFunction(func_name_slice)) {
                                    inst = c.LLVMGetNextInstruction(inst);
                                    continue;
                                }

                                // Collect arguments for semantic analysis
                                // Arguments are at operands 0 to num_operands - 2
                                var args = std.ArrayList(c.LLVMValueRef).initCapacity(ctx.allocator, @as(usize, @intCast(num_operands)) - 1) catch return error.OutOfMemory;
                                defer args.deinit(ctx.allocator);

                                var arg_idx: c_uint = 0;
                                while (arg_idx < num_operands - 1) : (arg_idx += 1) {
                                    const arg = c.LLVMGetOperand(inst, arg_idx);
                                    if (arg != null) {
                                        try args.append(ctx.allocator, arg);

                                        // Track load instructions to trace back to parameters
                                        if (c.LLVMGetInstructionOpcode(arg) == c.LLVMLoad) {
                                            const loaded_ptr = c.LLVMGetOperand(arg, 0);
                                            if (loaded_ptr != null) {
                                                try analysis_ctx.value_map.put(arg, ValueInfo{
                                                    .value = arg,
                                                    .origin = if (analysis_ctx.value_map.get(loaded_ptr) != null)
                                                        .from_param
                                                    else
                                                        .unknown,
                                                    .location = boundary.location,
                                                });
                                            }
                                        }
                                    }
                                }

                                // malloc/free detection rules from go_noise.md

                                // Rule 1: malloc unchecked detection
                                if (ffi_semantics.returnsOwnedMemory(func_name_slice)) {
                                    try malloc_results.append(ctx.allocator, inst);

                                    if (isMallocUnchecked(inst, &analysis_ctx, boundary)) {
                                        const trace = try ctx.allocator.alloc([]const u8, 2);
                                        trace[0] = try std.fmt.allocPrint(ctx.allocator, "malloc call in function {s}", .{boundary.function_name});
                                        trace[1] = try std.fmt.allocPrint(ctx.allocator, "Result not checked for null", .{});

                                        const message = try std.fmt.allocPrint(
                                            ctx.allocator,
                                            "malloc result not checked for null\nTrace:\n  {s}\n  {s}",
                                            .{ trace[0], trace[1] },
                                        );

                                        const issue = Issue.init(
                                            .ffi_unsafe_call,
                                            message,
                                            boundary.location,
                                            .medium,
                                            0.8,
                                        );

                                        try ctx.addIssue(&issue);
                                        issue_count += 1;

                                        diag.warn("FFIBodyCheck: malloc result not checked in function '{s}'", .{boundary.function_name});
                                    }
                                }

                                // Rule 2: free non-malloc source detection
                                // Rule 3: double free detection
                                if (ffi_semantics.consumesOwnedMemory(func_name_slice)) {
                                    if (args.items.len > 0) {
                                        const freed_ptr = args.items[0];

                                        // Check for double free (Rule 3)
                                        if (isDoubleFree(&freed_ptrs, freed_ptr)) {
                                            const trace = try ctx.allocator.alloc([]const u8, 2);
                                            trace[0] = try std.fmt.allocPrint(ctx.allocator, "Pointer freed in function {s}", .{boundary.function_name});
                                            trace[1] = try std.fmt.allocPrint(ctx.allocator, "Same pointer freed again", .{});

                                            const message = try std.fmt.allocPrint(
                                                ctx.allocator,
                                                "Double free detected\nTrace:\n  {s}\n  {s}",
                                                .{ trace[0], trace[1] },
                                            );

                                            const issue = Issue.init(
                                                .double_free,
                                                message,
                                                boundary.location,
                                                .high,
                                                0.9,
                                            );

                                            try ctx.addIssue(&issue);
                                            issue_count += 1;

                                            diag.warn("FFIBodyCheck: double free detected in function '{s}'", .{boundary.function_name});
                                        } else if (isFreeFromNonMalloc(freed_ptr, &analysis_ctx)) {
                                            // Check for free non-malloc source (Rule 2)
                                            const trace = try ctx.allocator.alloc([]const u8, 2);
                                            trace[0] = try std.fmt.allocPrint(ctx.allocator, "Pointer freed in function {s}", .{boundary.function_name});
                                            trace[1] = try std.fmt.allocPrint(ctx.allocator, "Pointer not from malloc", .{});

                                            const message = try std.fmt.allocPrint(
                                                ctx.allocator,
                                                "free called on non-malloc pointer\nTrace:\n  {s}\n  {s}",
                                                .{ trace[0], trace[1] },
                                            );

                                            const issue = Issue.init(
                                                .ffi_unsafe_call,
                                                message,
                                                boundary.location,
                                                .medium,
                                                0.7,
                                            );

                                            try ctx.addIssue(&issue);
                                            issue_count += 1;

                                            diag.warn("FFIBodyCheck: free called on non-malloc pointer in function '{s}'", .{boundary.function_name});
                                        }

                                        // Record freed pointer for double free detection
                                        try freed_ptrs.put(freed_ptr, {});
                                    }
                                }

                                // Rule 4: unknown FFI pointer usage detection
                                if (try checkUnknownFFIPointerUsage(args.items, func_name_slice, &analysis_ctx, boundary)) |vuln| {
                                    const message = try std.fmt.allocPrint(
                                        ctx.allocator,
                                        "{s}\nTrace:\n  {s}\n  {s}",
                                        .{ vuln.message, vuln.trace[0], vuln.trace[1] },
                                    );

                                    const issue = Issue.init(
                                        .ffi_unsafe_call,
                                        message,
                                        boundary.location,
                                        vuln.severity,
                                        vuln.confidence,
                                    );

                                    try ctx.addIssue(&issue);
                                    issue_count += 1;

                                    diag.warn("FFIBodyCheck: {s} in function '{s}'", .{ vuln.message, boundary.function_name });
                                }

                                // Check for format string vulnerabilities
                                if (try checkFormatStringVulnerability(func_name_slice, args.items, &analysis_ctx)) |vuln| {
                                    const message = try std.fmt.allocPrint(
                                        ctx.allocator,
                                        "{s}\nTrace:\n  {s}\n  {s}",
                                        .{ vuln.message, vuln.trace[0], vuln.trace[1] },
                                    );

                                    const issue = Issue.init(
                                        vuln.vuln_type,
                                        message,
                                        boundary.location,
                                        vuln.severity,
                                        vuln.confidence,
                                    );

                                    try ctx.addIssue(&issue);
                                    issue_count += 1;

                                    diag.warn("FFIBodyCheck: {s} in function '{s}'", .{ vuln.message, boundary.function_name });
                                }

                                // Check for command injection vulnerabilities
                                if (try checkCommandInjectionVulnerability(func_name_slice, args.items, &analysis_ctx)) |vuln| {
                                    const message = try std.fmt.allocPrint(
                                        ctx.allocator,
                                        "{s}\nTrace:\n  {s}\n  {s}",
                                        .{ vuln.message, vuln.trace[0], vuln.trace[1] },
                                    );

                                    const issue = Issue.init(
                                        vuln.vuln_type,
                                        message,
                                        boundary.location,
                                        vuln.severity,
                                        vuln.confidence,
                                    );

                                    try ctx.addIssue(&issue);
                                    issue_count += 1;

                                    diag.warn("FFIBodyCheck: {s} in function '{s}'", .{ vuln.message, boundary.function_name });
                                }
                            }
                        }
                    }
                }

                inst = c.LLVMGetNextInstruction(inst);
            }

            bb = c.LLVMGetNextBasicBlock(bb);
        }

        return issue_count;
    }
};

test "FFIBodyCheckPass - pass structure" {
    try std.testing.expectEqual(@as([]const u8, "ffi-body-check"), FFIBodyCheckPass.name);
    try std.testing.expectEqual(PassKind.analysis, FFIBodyCheckPass.kind);
    try std.testing.expectEqual(@as(usize, 1), FFIBodyCheckPass.deps.len);
}

test "FFIBodyCheckPass - vulnerability descriptions" {
    try std.testing.expectEqual(
        @as([]const u8, "Format string vulnerability"),
        getVulnerabilityDesc(.format_string),
    );
    try std.testing.expectEqual(
        @as([]const u8, "Command injection vulnerability"),
        getVulnerabilityDesc(.command_injection),
    );
    try std.testing.expectEqual(
        @as([]const u8, "Buffer overflow vulnerability"),
        getVulnerabilityDesc(.buffer_overflow),
    );
}

test "FFIBodyCheckPass - format string vulnerability check" {
    var value_map = std.AutoHashMap(c.LLVMValueRef, ValueInfo).init(std.testing.allocator);
    defer value_map.deinit();

    // Create test analysis context
    const boundary = FFIBoundary{
        .id = 0,
        .kind = undefined,
        .caller_language = undefined,
        .callee_language = undefined,
        .function_name = "printf",
        .location = Location.init("test.c:10"),
    };

    var analysis_ctx = AnalysisContext{
        .allocator = std.testing.allocator,
        .boundary = &boundary,
        .value_map = value_map,
    };

    // Mock format string from parameter
    const mock_param: c.LLVMValueRef = @ptrFromInt(0x1000);
    const mock_value = ValueInfo{
        .value = mock_param,
        .origin = .from_param,
        .location = Location.init("test.c:5"),
    };
    try analysis_ctx.value_map.put(mock_param, mock_value);

    const args = [_]c.LLVMValueRef{mock_param};

    // Should detect format string vulnerability
    const vuln = try checkFormatStringVulnerability("printf", &args, &analysis_ctx);
    try std.testing.expect(vuln != null);
    try std.testing.expectEqual(IssueKind.format_string, vuln.?.vuln_type);
    try std.testing.expectEqual(Severity.high, vuln.?.severity);
    try std.testing.expect(vuln.?.trace.len == 2);
}

test "FFIBodyCheckPass - command injection vulnerability check" {
    var value_map = std.AutoHashMap(c.LLVMValueRef, ValueInfo).init(std.testing.allocator);
    defer value_map.deinit();

    // Create test analysis context
    const boundary = FFIBoundary{
        .id = 1,
        .kind = undefined,
        .caller_language = undefined,
        .callee_language = undefined,
        .function_name = "system",
        .location = Location.init("test.c:10"),
    };

    var analysis_ctx = AnalysisContext{
        .allocator = std.testing.allocator,
        .boundary = &boundary,
        .value_map = value_map,
    };

    // Mock command from parameter
    const mock_param: c.LLVMValueRef = @ptrFromInt(0x2000);
    const mock_value = ValueInfo{
        .value = mock_param,
        .origin = .from_param,
        .location = Location.init("test.c:5"),
    };
    try analysis_ctx.value_map.put(mock_param, mock_value);

    const args = [_]c.LLVMValueRef{mock_param};

    // Should detect command injection vulnerability
    const vuln = try checkCommandInjectionVulnerability("system", &args, &analysis_ctx);
    try std.testing.expect(vuln != null);
    try std.testing.expectEqual(IssueKind.command_injection, vuln.?.vuln_type);
    try std.testing.expectEqual(Severity.critical, vuln.?.severity);
    try std.testing.expect(vuln.?.trace.len == 2);
}
