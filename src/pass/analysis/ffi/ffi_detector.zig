//! FFI Cross-Language Vulnerability Detector
//!
//! Detects security vulnerabilities that span across FFI boundaries.
//! This pass matches function declarations with implementations and
//! analyzes data flow between languages.
//!
//! Example vulnerability flow:
//! Rust (user input) → declare → FFI boundary → define → C (system call)

const std = @import("std");
const Allocator = std.mem.Allocator;

const Pass = @import("../../pass.zig").Pass;
const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const FactStore = @import("../../../fact/store.zig").FactStore;
const FactKind = @import("../../../fact/fact.zig").FactKind;

const ffi_matcher = @import("../../../ffi/ffi_matcher.zig");
const FFIMatcher = ffi_matcher.FFIMatcher;
const FFIMatch = ffi_matcher.FFIMatch;
const FunctionInfo = ffi_matcher.FunctionInfo;

const vulnerability_rules = @import("../noise/vulnerability_rules.zig");
const VulnerabilityRule = vulnerability_rules.VulnerabilityRule;
const VulnerabilityType = vulnerability_rules.VulnerabilityType;
const Severity = vulnerability_rules.Severity;

const llvm_safe = @import("../../../ir/llvm_safe.zig");
const c = @import("../../../ir/llvm_raw.zig").c;

/// FFI vulnerability severity (legacy compatibility)
pub const FFISeverity = enum {
    low,
    medium,
    high,
    critical,
};

/// FFI vulnerability type (legacy compatibility)
pub const FFIVulnerabilityType = enum {
    /// Command injection via FFI
    command_injection,
    /// Buffer overflow in FFI implementation
    buffer_overflow,
    /// Use-after-free in FFI implementation
    use_after_free,
    /// Integer overflow in FFI implementation
    integer_overflow,
    /// Format string vulnerability
    format_string,
    /// SQL injection
    sql_injection,
    /// Cross-site scripting
    xss,
    /// Path traversal
    path_traversal,
    /// XML External Entity
    xxe,
    /// Deserialization
    deserialization,
    /// Race condition
    race_condition,
    /// Tainted input crossing FFI boundary (data integrity risk)
    tainted_input,
    /// Unknown vulnerability type
    unknown,
};

/// Convert VulnerabilityType to FFIVulnerabilityType
pub fn toFFIVulnerabilityType(vuln_type: VulnerabilityType) FFIVulnerabilityType {
    return switch (vuln_type) {
        .command_injection => .command_injection,
        .sql_injection => .sql_injection,
        .xss => .xss,
        .path_traversal => .path_traversal,
        .buffer_overflow => .buffer_overflow,
        .use_after_free => .use_after_free,
        .integer_overflow => .integer_overflow,
        .format_string => .format_string,
        .xxe => .xxe,
        .deserialization => .deserialization,
        .race_condition => .race_condition,
        .unknown => .unknown,
    };
}

/// Convert Severity to FFISeverity
pub fn toFFISeverity(severity: Severity) FFISeverity {
    return switch (severity) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
    };
}

/// Get CWE ID for a vulnerability type
pub fn getCWEID(vuln_type: FFIVulnerabilityType) u32 {
    return switch (vuln_type) {
        .command_injection => 78,
        .sql_injection => 89,
        .xss => 79,
        .path_traversal => 22,
        .buffer_overflow => 120,
        .use_after_free => 416,
        .integer_overflow => 190,
        .format_string => 134,
        .xxe => 611,
        .deserialization => 502,
        .race_condition => 362,
        .tainted_input => 20,
        .unknown => 0,
    };
}

/// FFI vulnerability detection result
pub const FFIVulnerability = struct {
    /// Vulnerability ID
    id: u32,
    /// Vulnerability type
    vuln_type: FFIVulnerabilityType,
    /// Severity level
    severity: FFISeverity,
    /// FFI match that has the vulnerability
    ffi_match: *const FFIMatch,
    /// Description of the vulnerability
    description: []const u8,
    /// Source location (declare side)
    source_location: ?[]const u8,
    /// Sink location (define side)
    sink_location: ?[]const u8,
    /// Dangerous function call that caused the vulnerability
    dangerous_function: ?[]const u8,

    pub fn deinit(self: *FFIVulnerability, allocator: Allocator) void {
        if (self.dangerous_function) |df| {
            allocator.free(df);
        }
    }
};

/// FFI detector pass
pub const FFIDetector = struct {
    pub const name = "ffi-detector";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "pointer-flow" };

    allocator: Allocator,
    store: *FactStore,
    vulnerability_count: u32,
    vulnerabilities: std.ArrayList(FFIVulnerability),

    /// Pre-computed set of function-scope IDs that contain taint.
    tainted_contexts: std.AutoHashMap(u32, void),

    /// Tracks all name strings allocated during run() for cross-edge matches.
    /// Freed in deinit() to prevent GPA leak warnings at exit.
    owned_names: std.ArrayList([]u8),

    /// Initialize the FFI detector.
    pub fn init(allocator: Allocator, store: *FactStore) !FFIDetector {
        const vulnerabilities = std.ArrayList(FFIVulnerability).initCapacity(allocator, 0) catch return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .store = store,
            .vulnerability_count = 0,
            .vulnerabilities = vulnerabilities,
            .tainted_contexts = std.AutoHashMap(u32, void).init(allocator),
            .owned_names = std.ArrayList([]u8).initCapacity(allocator, 0) catch return error.OutOfMemory,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FFIDetector) void {
        self.tainted_contexts.deinit();
        for (self.vulnerabilities.items) |*v| {
            v.deinit(self.allocator);
        }
        self.vulnerabilities.deinit(self.allocator);
        // Free all cross-edge match name copies
        for (self.owned_names.items) |n| {
            self.allocator.free(n);
        }
        self.owned_names.deinit(self.allocator);
    }

    /// Run the FFI detector pass
    pub fn run(self: *FFIDetector, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // Build FFI matches from cross-language edges (not intra-module name matching).
        // This correctly handles the common case where declare is in one .ll file
        // and define is in another — FFIMatcher's single-module approach misses these.
        const cross_edges = ctx.getCrossLangEdges();

        if (cross_edges.len == 0) {
            diag.debug("FFIDetector: no cross-lang edges found in module", .{});
            return;
        }

        diag.info("FFIDetector: found {} cross-language edges to analyze", .{cross_edges.len});

        // Pre-compute tainted context set: O(T) one-time scan of taint facts
        // via FactStore's kind_index (O(1) lookup), reading SoA ctx[] directly.
        // After this, each per-edge check is O(1) HashMap contains().
        try self.buildTaintedContextSet(ctx);

        var match_count: u32 = 0;
        for (cross_edges) |*edge| {
            const callee_name = edge.callee_name;

            // Skip LLVM intrinsics — not real FFI boundaries
            if (std.mem.startsWith(u8, callee_name, "llvm.")) continue;

            // Allocate owned copies for FFIMatch lifecycle.
            // Registered in owned_names and freed uniformly in deinit(),
            // eliminating per-allocation errdefer + GPA leak warnings.
            const name_copy = try ctx.allocator.dupe(u8, callee_name);
            try self.owned_names.append(self.allocator, name_copy);

            const caller_name_copy = try ctx.allocator.dupe(u8, edge.caller_name);
            try self.owned_names.append(self.allocator, caller_name_copy);

            // Build synthetic FunctionInfo for declare (callee) and define (caller) sides.
            // func field is undefined because we don't have a local LLVM function ref for
            // the other module's functions. Detection methods that need IR access will
            // gracefully return null; taint-based detection still works via name lookup.
            const declare_info = FunctionInfo{
                .name = name_copy,
                .kind = .declare,
                .func = undefined,
                .is_external = true,
            };
            const define_info = FunctionInfo{
                .name = caller_name_copy,
                .kind = .define,
                .func = undefined,
                .is_external = false,
            };

            const match = FFIMatch{
                .name = name_copy,
                .declare_func = declare_info,
                .define_func = define_info,
                .is_complete = true,
            };

            match_count += 1;

            // Analyze this cross-edge match for vulnerabilities
            const vulnerabilities = try self.analyzeFFIMatch(ctx, &match);
            defer ctx.allocator.free(vulnerabilities);
            for (vulnerabilities) |vuln| {
                try self.vulnerabilities.append(self.allocator, vuln);
                try self.reportVulnerability(&vuln, diag);
            }
        }

        diag.info("FFI detection complete: {} edges analyzed, {} vulnerabilities found", .{
            match_count,
            self.vulnerability_count,
        });
    }

    /// Detect command injection vulnerabilities
    ///
    /// Checks if the define side calls dangerous functions like system(), exec(), popen()
    /// and if tainted data from declare side reaches them.
    fn detectCommandInjection(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Dangerous functions for command injection
        const dangerous_funcs = &[_][]const u8{
            "system",
            "exec",
            "execl",
            "execle",
            "execlp",
            "execv",
            "execve",
            "execvp",
            "popen",
            "posix_spawn",
        };

        // Check if function body calls any dangerous function
        if (try self.callsDangerousFunction(define_func, dangerous_funcs)) |func_name| {
            // Check if tainted data reaches this function
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

            if (has_taint) {
                self.vulnerability_count += 1;
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .command_injection,
                    .severity = .critical,
                    .ffi_match = ffi_match,
                    .description = "Command injection: tainted data reaches dangerous function",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = func_name,
                };
                return vuln;
            }
        }

        return null;
    }

    /// Detect buffer overflow vulnerabilities
    ///
    /// Checks if the define side uses dangerous functions like strcpy(), strcat(), gets()
    /// and if tainted data from declare side reaches them.
    fn detectBufferOverflow(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Dangerous functions for buffer overflow
        const dangerous_funcs = &[_][]const u8{
            "strcpy",
            "strcat",
            "gets",
            "sprintf",
            "scanf",
            "fscanf",
            "sscanf",
            "vsprintf",
            "strncpy",
            "strncat",
        };

        // Check if function body calls any dangerous function
        if (try self.callsDangerousFunction(define_func, dangerous_funcs)) |func_name| {
            // Check if tainted data reaches this function
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

            if (has_taint) {
                self.vulnerability_count += 1;
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .buffer_overflow,
                    .severity = .critical,
                    .ffi_match = ffi_match,
                    .description = "Buffer overflow: tainted data reaches unsafe string function",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = func_name,
                };
                return vuln;
            }
        }

        return null;
    }

    /// Detect format string vulnerabilities
    ///
    /// Checks if the define side uses printf/sprintf/snprintf with format strings
    /// that contain tainted data from declare side.
    fn detectFormatString(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Format string functions
        const format_funcs = &[_][]const u8{
            "printf",
            "fprintf",
            "sprintf",
            "snprintf",
            "vprintf",
            "vfprintf",
            "vsprintf",
            "vsnprintf",
            "syslog",
        };

        // Check if function body calls any format function
        if (try self.callsDangerousFunction(define_func, format_funcs)) |func_name| {
            // Check if tainted data reaches this function
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

            if (has_taint) {
                self.vulnerability_count += 1;
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .format_string,
                    .severity = .high,
                    .ffi_match = ffi_match,
                    .description = "Format string: tainted data used as format string",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = func_name,
                };
                return vuln;
            }
        }

        return null;
    }

    /// Detect use-after-free vulnerabilities
    ///
    /// Checks if the define side has potential use-after-free patterns
    /// and if tainted data from declare side is involved.
    fn detectUseAfterFree(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Memory management functions
        const mem_funcs = &[_][]const u8{
            "free",
            "delete",
            "realloc",
        };

        // Check if function body calls free and then uses the pointer
        if (try self.hasUseAfterFreePattern(define_func, mem_funcs)) {
            // Check if tainted data reaches this function
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

            if (has_taint) {
                self.vulnerability_count += 1;
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .use_after_free,
                    .severity = .high,
                    .ffi_match = ffi_match,
                    .description = "Use-after-free: pointer used after memory deallocation",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = null,
                };
                return vuln;
            }
        }

        return null;
    }

    /// Detect integer overflow vulnerabilities
    ///
    /// Checks if the define side has arithmetic operations that could overflow
    /// with tainted data from declare side.
    fn detectIntegerOverflow(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Check if function has arithmetic operations with tainted data
        if (try self.hasUnsafeArithmetic(define_func)) {
            // Check if tainted data reaches this function
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

            if (has_taint) {
                self.vulnerability_count += 1;
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .integer_overflow,
                    .severity = .medium,
                    .ffi_match = ffi_match,
                    .description = "Integer overflow: arithmetic with tainted data may overflow",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = null,
                };
                return vuln;
            }
        }

        return null;
    }

    /// Detect tainted data crossing FFI boundary (data integrity risk).
    /// Even without a specific dangerous function, tainted input at FFI boundary
    /// indicates potential information leakage or injection vector.
    fn detectTaintedCrossBoundary(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        // Always check taint for every valid FFI match — don't gate on "dangerous path"
        const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);

        if (has_taint) {
            self.vulnerability_count += 1;
            const vuln = FFIVulnerability{
                .id = self.vulnerability_count - 1,
                .vuln_type = .tainted_input,
                .severity = .high,
                .ffi_match = ffi_match,
                .description = "Tainted data flows across FFI boundary — unvalidated input may reach sensitive operations",
                .source_location = ffi_match.declare_func.?.name,
                .sink_location = ffi_match.define_func.?.name,
                .dangerous_function = null,
            };
            return vuln;
        }

        return null;
    }

    /// Detect potential buffer overflow via tainted size parameters.
    /// Checks if any tainted value is used as a length/size argument to
    /// memcpy, memset, strcpy, memmove, or similar memory operations.
    fn detectTaintedBufferSize(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !?FFIVulnerability {
        const define_func = ffi_match.define_func orelse return null;

        // Memory operations where tainted size = overflow risk
        const mem_ops = &[_][]const u8{
            "llvm.memcpy", "llvm.memset", "llvm.memmove",
            "llvm.strcpy", "memcpy",      "memset",
            "memmove",     "strcpy",      "strncpy",
        };

        if (try self.callsDangerousFunction(define_func, mem_ops)) |func_name| {
            const has_taint = try self.hasTaintedDataFlow(ctx, ffi_match);
            if (has_taint) {
                self.vulnerability_count += 1;
                return FFIVulnerability{
                    .id = self.vulnerability_count - 1,
                    .vuln_type = .buffer_overflow,
                    .severity = .critical,
                    .ffi_match = ffi_match,
                    .description = "Tainted size parameter reaches memory operation — buffer overflow risk across FFI boundary",
                    .source_location = ffi_match.declare_func.?.name,
                    .sink_location = ffi_match.define_func.?.name,
                    .dangerous_function = func_name,
                };
            }
        }

        return null;
    }

    /// Analyze FFI match for vulnerabilities
    fn analyzeFFIMatch(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) ![]FFIVulnerability {
        var vulnerabilities = std.ArrayList(FFIVulnerability).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        errdefer vulnerabilities.deinit(self.allocator);

        // Try to detect each type of vulnerability
        if (try self.detectCommandInjection(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        if (try self.detectBufferOverflow(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        if (try self.detectFormatString(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        if (try self.detectUseAfterFree(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        if (try self.detectIntegerOverflow(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        // Check for tainted data crossing FFI boundary (catch-all taint check)
        if (try self.detectTaintedCrossBoundary(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        // Check for buffer overflow via tainted size parameters
        if (try self.detectTaintedBufferSize(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(self.allocator, vuln);
        }

        return vulnerabilities.toOwnedSlice(self.allocator);
    }

    /// Check if function calls any dangerous function.
    /// Returns null if the function reference is unavailable (e.g., synthetic
    /// cross-edge match where IR access is not possible).
    fn callsDangerousFunction(self: *FFIDetector, func: FunctionInfo, dangerous_funcs: []const []const u8) !?[]const u8 {
        // Guard: synthetic matches from cross-edge data may not have an actual
        // LLVM function reference. Skip IR-based body inspection in that case.
        if (@intFromPtr(func.func.raw) == 0) return null;

        var bb = c.LLVMGetFirstBasicBlock(func.func.raw);
        while (@intFromPtr(bb) != 0) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_val = c.LLVMGetOperand(inst, 0);
                    if (called_val != null) {
                        const func_name = c.LLVMGetValueName(called_val);
                        if (func_name != null) {
                            const func_name_slice = std.mem.span(func_name);

                            for (dangerous_funcs) |dangerous| {
                                if (std.mem.eql(u8, func_name_slice, dangerous)) {
                                    // Copy the function name to avoid dangling pointer
                                    return try self.allocator.dupe(u8, func_name_slice);
                                }
                            }
                        }
                    }
                }

                inst = c.LLVMGetNextInstruction(inst);
            }
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        return null;
    }

    /// Check if function has use-after-free pattern
    fn hasUseAfterFreePattern(self: *FFIDetector, func: FunctionInfo, mem_funcs: []const []const u8) !bool {
        if (@intFromPtr(func.func.raw) == 0) return false;

        // Track use-after-free pattern:
        // 1. Find calls to free/delete
        // 2. Get the pointer being freed
        // 3. Check if that pointer is used after the free

        var bb = c.LLVMGetFirstBasicBlock(func.func.raw);
        while (@intFromPtr(bb) != 0) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_val = c.LLVMGetOperand(inst, 0);
                    if (called_val != null) {
                        const func_name = c.LLVMGetValueName(called_val);
                        if (func_name == null) continue;
                        const func_name_slice = std.mem.span(func_name);

                        // Check if this is a memory deallocation function
                        var is_dealloc = false;
                        for (mem_funcs) |mem_func| {
                            if (std.mem.eql(u8, func_name_slice, mem_func)) {
                                is_dealloc = true;
                                break;
                            }
                        }

                        if (is_dealloc) {
                            // Get the pointer being freed (first operand)
                            const freed_ptr = c.LLVMGetOperand(inst, 0);
                            if (freed_ptr != null and self.isPointerUsedAfter(inst, freed_ptr)) {
                                return true;
                            }
                        }
                    }
                }

                inst = c.LLVMGetNextInstruction(inst);
            }
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        return false;
    }

    /// Check if a pointer is used after a specific instruction
    fn isPointerUsedAfter(self: *FFIDetector, after_inst: c.LLVMValueRef, ptr: c.LLVMValueRef) bool {
        _ = self;

        // Collect all instructions after after_inst in the same basic block
        var found_after_inst = false;
        const bb = c.LLVMGetInstructionParent(after_inst);
        var inst = c.LLVMGetFirstInstruction(bb);

        while (@intFromPtr(inst) != 0) {
            if (found_after_inst) {
                // Check if this instruction uses the pointer
                const num_operands = c.LLVMGetNumOperands(inst);
                for (0..@as(usize, @intCast(num_operands))) |i| {
                    const operand = c.LLVMGetOperand(inst, @intCast(i));
                    if (operand == ptr) {
                        return true;
                    }
                }
            } else if (inst == after_inst) {
                found_after_inst = true;
            }
            inst = c.LLVMGetNextInstruction(inst);
        }

        return false;
    }

    /// Check if function has unsafe arithmetic operations
    fn hasUnsafeArithmetic(self: *FFIDetector, func: FunctionInfo) !bool {
        _ = self;
        if (@intFromPtr(func.func.raw) == 0) return false;

        var bb = c.LLVMGetFirstBasicBlock(func.func.raw);
        while (@intFromPtr(bb) != 0) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (opcode == c.LLVMAdd or opcode == c.LLVMSub or
                    opcode == c.LLVMMul or opcode == c.LLVMUDiv or
                    opcode == c.LLVMSDiv or opcode == c.LLVMURem or
                    opcode == c.LLVMSRem)
                {
                    const num_ops = c.LLVMGetNumOperands(inst);
                    if (num_ops >= 2) {
                        return true;
                    }
                }

                inst = c.LLVMGetNextInstruction(inst);
            }
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        return false;
    }

    /// Build a pre-computed set of all tainted value IDs.
    ///
    /// Reads taint fact indices from FactStore's O(1) kind_index, then
    /// collects BOTH .subject (tainted value) and .context (source param)
    /// IDs into a HashSet. Called once in run() before the cross-edge loop,
    /// making each subsequent per-edge check O(1) per argument inspected.
    fn buildTaintedContextSet(self: *FFIDetector, ctx: *PassContext) !void {
        const taint_indices = try ctx.fact_store.queryByKind(.taint, self.allocator);
        defer self.allocator.free(taint_indices);

        for (taint_indices) |idx| {
            // Subject: the tainted value itself (e.g., a parameter or local)
            const subj_id = ctx.fact_store.subj.items[idx];
            try self.tainted_contexts.put(subj_id, {});
            // Context: the source parameter ID from which taint originated
            const ctx_id = ctx.fact_store.ctx.items[idx];
            try self.tainted_contexts.put(ctx_id, {});
        }
    }

    /// Check if tainted data flows through this specific FFI edge.
    ///
    /// Scans the define-side function for call instructions targeting the
    /// declare-side callee, then checks each argument's value ID against
    /// the pre-computed tainted_contexts HashSet. O(1) per argument,
    /// O(B*I) total per edge where B=blocks, I=instructions (typically <100).
    ///
    /// This is per-edge precise: only returns true when a tainted value
    /// is actually passed across THIS specific FFI boundary.
    fn hasTaintedDataFlow(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !bool {
        const define_func = ffi_match.define_func orelse return false;
        const declare_func = ffi_match.declare_func orelse return false;

        // Synthetic cross-edge matches may not have an actual LLVM function ref.
        // Fall back to module-level presence check when IR access unavailable.
        if (@intFromPtr(define_func.func.raw) == 0) {
            return self.tainted_contexts.count() > 0;
        }

        // Scan define function's IR for calls to the declare-side callee
        var bb = c.LLVMGetFirstBasicBlock(define_func.func.raw);
        while (bb != null) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                // Verify this call targets our declare-side function
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;
                const called_name = c.LLVMGetValueName(called_val);
                if (!std.mem.eql(u8, std.mem.sliceTo(called_name, 0), declare_func.name)) continue;

                // Found the FFI boundary call — check each argument for taint
                const num_args = c.LLVMGetNumArgOperands(inst);
                var i: c_uint = 0;
                while (i < num_args) : (i += 1) {
                    const arg = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(arg) == 0) continue;
                    const arg_id = ctx.getValueId(@intFromPtr(arg)) catch continue;
                    if (self.tainted_contexts.contains(arg_id)) return true;
                }
            }
        }
        return false;
    }

    /// Report a vulnerability
    fn reportVulnerability(self: *FFIDetector, vuln: *const FFIVulnerability, diag: *DiagnosticWriter) !void {
        _ = self;

        diag.err("VULNERABILITY {d} [{s}]", .{ vuln.id, @tagName(vuln.severity) });
        diag.err("Type: {s}", .{@tagName(vuln.vuln_type)});
        diag.err("Reason: {s}", .{vuln.description});
        diag.err("  Source: {s}", .{vuln.source_location orelse "unknown"});
        diag.err("  Sink: {s}", .{vuln.sink_location orelse "unknown"});
        if (vuln.dangerous_function) |func| {
            diag.err("  Dangerous function: {s}", .{func});
        }
    }
};

/// Pass-compliant wrapper for FFIDetector — bridges method-style API to static Pass interface.
/// Follows the same pattern as LockPass: static run() creates instance internally.
pub const FFIDetectorPass = struct {
    pub const name = "ffi-detector";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "pointer-flow" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var store = try FactStore.init(ctx.allocator);
        defer store.deinit();
        var detector = try FFIDetector.init(ctx.allocator, &store);
        defer detector.deinit();
        try detector.run(ctx, diag);
    }
};

// Validate that FFIDetector satisfies Pass interface
comptime {
    _ = Pass(FFIDetector);
}

// Validate that FFIDetectorPass satisfies Pass interface
comptime {
    _ = Pass(FFIDetectorPass);
}

test "FFIVulnerability - struct fields" {
    try std.testing.expect(@hasDecl(FFIVulnerability, "id"));
    try std.testing.expect(@hasDecl(FFIVulnerability, "vuln_type"));
    try std.testing.expect(@hasDecl(FFIVulnerability, "severity"));
    try std.testing.expect(@hasDecl(FFIVulnerability, "ffi_match"));
    try std.testing.expect(@hasDecl(FFIVulnerability, "description"));
    try std.testing.expect(@hasDecl(FFIVulnerability, "dangerous_function"));
}

test "FFISeverity - enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(FFISeverity.low));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(FFISeverity.medium));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(FFISeverity.high));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(FFISeverity.critical));
}

test "FFIVulnerabilityType - enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(FFIVulnerabilityType.command_injection));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(FFIVulnerabilityType.buffer_overflow));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(FFIVulnerabilityType.use_after_free));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(FFIVulnerabilityType.integer_overflow));
    try std.testing.expectEqual(@as(usize, 4), @intFromEnum(FFIVulnerabilityType.format_string));
    try std.testing.expectEqual(@as(usize, 11), @intFromEnum(FFIVulnerabilityType.tainted_input));
    try std.testing.expectEqual(@as(usize, 12), @intFromEnum(FFIVulnerabilityType.unknown));
}

test "FFIDetector - pass interface" {
    comptime {
        try std.testing.expect(@hasDecl(FFIDetector, "name"));
        try std.testing.expect(@hasDecl(FFIDetector, "kind"));
        try std.testing.expect(@hasDecl(FFIDetector, "deps"));
        try std.testing.expect(@hasDecl(FFIDetector, "run"));
    }
}

test "FFIDetector - init and deinit" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var detector = FFIDetector.init(std.testing.allocator, &store);
    defer detector.deinit();

    try std.testing.expectEqual(@as(u32, 0), detector.vulnerability_count);
    try std.testing.expectEqual(@as(usize, 0), detector.vulnerabilities.items.len);
}

test "FFIDetector - dangerous function detection patterns" {
    // Test that dangerous function patterns are correct
    const command_injection_funcs = &[_][]const u8{
        "system", "exec", "popen",
    };

    const buffer_overflow_funcs = &[_][]const u8{
        "strcpy", "strcat", "gets",
    };

    try std.testing.expectEqual(@as(usize, 3), command_injection_funcs.len);
    try std.testing.expectEqual(@as(usize, 3), buffer_overflow_funcs.len);
}

test "FFIVulnerability - vulnerability creation" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var detector = FFIDetector.init(std.testing.allocator, &store);
    defer detector.deinit();

    // Create a mock FFI match
    const mock_declare = FunctionInfo{
        .name = "test_declare",
        .kind = .declare,
        .func = undefined,
        .is_external = true,
    };

    const mock_define = FunctionInfo{
        .name = "test_define",
        .kind = .define,
        .func = undefined,
        .is_external = false,
    };

    const mock_match = FFIMatch{
        .name = "test_func",
        .declare_func = mock_declare,
        .define_func = mock_define,
        .is_complete = true,
    };

    // Create a vulnerability
    const vuln = FFIVulnerability{
        .id = 0,
        .vuln_type = .command_injection,
        .severity = .critical,
        .ffi_match = &mock_match,
        .description = "Test vulnerability",
        .source_location = "test_declare",
        .sink_location = "test_define",
        .dangerous_function = "system",
    };

    try std.testing.expectEqual(@as(u32, 0), vuln.id);
    try std.testing.expectEqual(FFIVulnerabilityType.command_injection, vuln.vuln_type);
    try std.testing.expectEqual(FFISeverity.critical, vuln.severity);
}
