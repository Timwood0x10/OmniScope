//! Unified FFI Analysis Pass
//!
//! This pass integrates FFIMatcher, FFIBoundaryPass, and FFIDetector
//! to provide comprehensive FFI security analysis.
//!
//! The unified approach:
//! 1. Use FFIMatcher for accurate cross-language function matching
//! 2. Create FFI boundaries from matcher results
//! 3. Detect vulnerabilities across FFI boundaries
//! 4. Provide a single entry point for FFI analysis

const std = @import("std");
const Allocator = std.mem.Allocator;

const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const ffi_matcher = @import("../../ffi/ffi_matcher.zig");
const FFIMatcher = ffi_matcher.FFIMatcher;
const FFIMatch = ffi_matcher.FFIMatch;

const llvm_safe = @import("../../ir/llvm_safe.zig");
const c = @import("../../ir/llvm_raw.zig").c;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;

const vulnerability_rules = @import("vulnerability_rules.zig");
const VulnerabilityRule = vulnerability_rules.VulnerabilityRule;
const VulnerabilityType = vulnerability_rules.VulnerabilityType;
const Severity = vulnerability_rules.Severity;

/// Error type for FFI analysis operations
pub const FFIAnalysisError = error{
    /// No module loaded
    NoModule,
    /// FFIMatcher initialization failed
    MatcherInitFailed,
    /// Memory allocation failed
    OutOfMemory,
};

/// FFI analysis result
pub const FFIAnalysisResult = struct {
    /// Number of FFI matches found
    match_count: usize,
    /// Number of FFI boundaries detected
    boundary_count: usize,
    /// Number of vulnerabilities found
    vulnerability_count: usize,
    /// List of vulnerabilities
    vulnerabilities: []const FFIAnalysisVulnerability,
};

/// FFI analysis vulnerability
pub const FFIAnalysisVulnerability = struct {
    /// Vulnerability type
    vuln_type: VulnerabilityType,
    /// Severity level
    severity: Severity,
    /// Related FFI match
    ffi_match: *const FFIMatch,
    /// Description of the vulnerability
    description: []const u8,
    /// Confidence score (0.0 - 1.0)
    confidence: f32,
};

/// Unified FFI analysis pass
pub const FFIAnalysisPass = struct {
    pub const name = "ffi-analysis";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "taint" };

    allocator: Allocator,
    store: *FactStore,
    matcher: ?FFIMatcher,
    vulnerabilities: std.ArrayList(FFIAnalysisVulnerability),

    /// Initialize the FFI analysis pass
    pub fn init(allocator: Allocator, store: *FactStore) FFIAnalysisPass {
        return .{
            .allocator = allocator,
            .store = store,
            .matcher = null,
            .vulnerabilities = std.ArrayList(FFIAnalysisVulnerability).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FFIAnalysisPass) void {
        if (self.matcher) |*m| {
            m.deinit();
        }
        self.vulnerabilities.deinit();
    }

    /// Run the unified FFI analysis pass
    pub fn run(self: *FFIAnalysisPass, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) {
            diag.warn("FFIAnalysis: No module loaded, skipping analysis", .{});
            return;
        }

        const mod = ctx.module.?.raw;

        // Step 1: Initialize FFIMatcher and extract functions
        var matcher = try FFIMatcher.init(ctx.allocator);
        self.matcher = matcher;

        const safe_module = llvm_safe.Module{ .raw = mod };
        try matcher.extractFunctions(safe_module);

        // Step 2: Match declare and define functions
        try matcher.matchFunctions();
        diag.info("FFIAnalysis: Found {} FFI matches", .{matcher.getMatches().len});

        // Step 3: Set matcher in DataFlowGraph for boundary creation
        ctx.data_flow_graph.setFFIMatcher(&matcher);

        // Step 4: Create FFI boundaries from matcher results
        try ctx.data_flow_graph.createFFIBoundariesFromMatcher();
        diag.info("FFIAnalysis: Created {} FFI boundaries", .{ctx.data_flow_graph.getFFIBoundaries().len});

        // Step 5: Analyze each match for vulnerabilities
        for (matcher.getMatches()) |*match| {
            if (!match.isValid()) continue;

            const vulns = try self.analyzeFFIMatch(ctx, match);
            for (vulns) |vuln| {
                try self.vulnerabilities.append(vuln);
            }
        }

        diag.info("FFIAnalysis: Complete - {} matches, {} boundaries, {} vulnerabilities", .{
            matcher.getMatches().len,
            ctx.data_flow_graph.getFFIBoundaries().len,
            self.vulnerabilities.items.len,
        });
    }

    /// Analyze an FFI match for vulnerabilities
    fn analyzeFFIMatch(
        self: *FFIAnalysisPass,
        ctx: *PassContext,
        ffi_match: *const FFIMatch,
    ) ![]const FFIAnalysisVulnerability {
        _ = ctx; // Context parameter for future extension
        var vulnerabilities = std.ArrayList(FFIAnalysisVulnerability).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        errdefer vulnerabilities.deinit();

        // Check if define function calls dangerous functions
        if (ffi_match.define_func) |define_func| {
            // Check for command injection vulnerabilities
            if (try self.checkCommandInjection(define_func, ffi_match)) |vuln| {
                try vulnerabilities.append(vuln);
            }

            // Check for buffer overflow vulnerabilities
            if (try self.checkBufferOverflow(define_func, ffi_match)) |vuln| {
                try vulnerabilities.append(vuln);
            }

            // Check for format string vulnerabilities
            if (try self.checkFormatString(define_func, ffi_match)) |vuln| {
                try vulnerabilities.append(vuln);
            }
        }

        return vulnerabilities.toOwnedSlice();
    }

    /// Check for command injection vulnerabilities
    fn checkCommandInjection(
        self: *FFIAnalysisPass,
        func: ffi_matcher.FunctionInfo,
        ffi_match: *const FFIMatch,
    ) !?FFIAnalysisVulnerability {
        const dangerous_funcs = &[_][]const u8{
            "system", "exec",   "execl", "execle",      "execlp", "execv",
            "execve", "execvp", "popen", "posix_spawn",
        };

        if (try self.callsDangerousFunction(func, dangerous_funcs)) |func_name| {
            return FFIAnalysisVulnerability{
                .vuln_type = .command_injection,
                .severity = .critical,
                .ffi_match = ffi_match,
                .description = try std.fmt.allocPrint(
                    self.allocator,
                    "Command injection: '{s}' calls dangerous function '{s}'",
                    .{ ffi_match.name, func_name },
                ),
                .confidence = 0.9,
            };
        }

        return null;
    }

    /// Check for buffer overflow vulnerabilities
    fn checkBufferOverflow(
        self: *FFIAnalysisPass,
        func: ffi_matcher.FunctionInfo,
        ffi_match: *const FFIMatch,
    ) !?FFIAnalysisVulnerability {
        const dangerous_funcs = &[_][]const u8{
            "strcpy", "strcat", "gets",     "sprintf", "scanf",
            "fscanf", "sscanf", "vsprintf",
        };

        if (try self.callsDangerousFunction(func, dangerous_funcs)) |func_name| {
            return FFIAnalysisVulnerability{
                .vuln_type = .buffer_overflow,
                .severity = .high,
                .ffi_match = ffi_match,
                .description = try std.fmt.allocPrint(
                    self.allocator,
                    "Buffer overflow: '{s}' calls unsafe string function '{s}'",
                    .{ ffi_match.name, func_name },
                ),
                .confidence = 0.85,
            };
        }

        return null;
    }

    /// Check for format string vulnerabilities
    fn checkFormatString(
        self: *FFIAnalysisPass,
        func: ffi_matcher.FunctionInfo,
        ffi_match: *const FFIMatch,
    ) !?FFIAnalysisVulnerability {
        const format_funcs = &[_][]const u8{
            "printf",  "fprintf",  "sprintf",  "snprintf",
            "vprintf", "vfprintf", "vsprintf", "vsnprintf",
            "syslog",
        };

        if (try self.callsDangerousFunction(func, format_funcs)) |func_name| {
            return FFIAnalysisVulnerability{
                .vuln_type = .format_string,
                .severity = .high,
                .ffi_match = ffi_match,
                .description = try std.fmt.allocPrint(
                    self.allocator,
                    "Format string: '{s}' calls format function '{s}' with potentially tainted data",
                    .{ ffi_match.name, func_name },
                ),
                .confidence = 0.8,
            };
        }

        return null;
    }

    /// Check if function calls any dangerous function
    fn callsDangerousFunction(
        self: *FFIAnalysisPass,
        func: ffi_matcher.FunctionInfo,
        dangerous_funcs: []const []const u8,
    ) !?[]const u8 {
        var bb = c.LLVMGetFirstBasicBlock(func.func.raw);
        while (bb != null) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);

                if (opcode_enum == .Call) {
                    const called_func = c.LLVMGetCalledFunction(inst);
                    if (called_func != null) {
                        const func_name = c.LLVMGetValueName(called_func);
                        if (func_name != null) {
                            const func_name_slice = std.mem.span(func_name);

                            for (dangerous_funcs) |dangerous| {
                                if (std.mem.eql(u8, func_name_slice, dangerous)) {
                                    return self.allocator.dupe(u8, func_name_slice);
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

    /// Get analysis results
    pub fn getResults(self: *const FFIAnalysisPass) FFIAnalysisResult {
        const match_count = if (self.matcher) |m| m.getMatches().len else 0;

        return .{
            .match_count = match_count,
            .boundary_count = 0, // Will be filled by caller
            .vulnerability_count = self.vulnerabilities.items.len,
            .vulnerabilities = self.vulnerabilities.items,
        };
    }
};

// Validate that FFIAnalysisPass satisfies Pass interface
comptime {
    _ = Pass(FFIAnalysisPass);
}

test "FFIAnalysisPass - pass interface" {
    comptime {
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "name"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "kind"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "deps"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "run"));
    }
}

test "FFIAnalysisPass - init and deinit" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = FFIAnalysisPass.init(std.testing.allocator, &store);
    defer pass.deinit();

    try std.testing.expect(pass.matcher == null);
    try std.testing.expectEqual(@as(usize, 0), pass.vulnerabilities.items.len);
}
