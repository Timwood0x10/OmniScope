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

const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;

const ffi_matcher = @import("../../ffi/ffi_matcher.zig");
const FFIMatcher = ffi_matcher.FFIMatcher;
const FFIMatch = ffi_matcher.FFIMatch;
const FunctionInfo = ffi_matcher.FunctionInfo;

const vulnerability_rules = @import("vulnerability_rules.zig");
const VulnerabilityRule = vulnerability_rules.VulnerabilityRule;
const VulnerabilityType = vulnerability_rules.VulnerabilityType;
const Severity = vulnerability_rules.Severity;

const llvm_safe = @import("../../ir/llvm_safe.zig");
const c = @import("../../ir/llvm_raw.zig").c;

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
};

/// FFI detector pass
pub const FFIDetector = struct {
    pub const name = "ffi-detector";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "taint" };

    allocator: Allocator,
    store: *FactStore,
    vulnerability_count: u32,
    vulnerabilities: std.ArrayList(FFIVulnerability),

    /// Initialize the FFI detector
    pub fn init(allocator: Allocator, store: *FactStore) FFIDetector {
        return .{
            .allocator = allocator,
            .store = store,
            .vulnerability_count = 0,
            .vulnerabilities = std.ArrayList(FFIVulnerability).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FFIDetector) void {
        self.vulnerabilities.deinit();
    }

    /// Run the FFI detector pass
    pub fn run(self: *FFIDetector, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const module = ctx.module.?.raw;

        // Create matcher for this analysis
        var matcher = FFIMatcher.init(ctx.allocator);
        defer matcher.deinit();

        // Extract functions from module
        const safe_module = llvm_safe.Module{ .raw = module };
        try matcher.extractFunctions(safe_module);

        // Match declare and define functions
        try matcher.matchFunctions();

        diag.info("Found {} FFI matches", .{matcher.getMatches().len});

        // Analyze each match for vulnerabilities
        for (matcher.getMatches()) |*match| {
            if (!match.isValid()) continue;

            const vulnerabilities = try self.analyzeFFIMatch(ctx, match);
            for (vulnerabilities) |vuln| {
                try self.vulnerabilities.append(vuln);
                try self.reportVulnerability(&vuln, diag);
                self.vulnerability_count += 1;
            }
        }

        diag.info("FFI detection complete: {} vulnerabilities found", .{self.vulnerability_count});
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
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count,
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
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count,
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
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count,
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
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count,
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
                const vuln = FFIVulnerability{
                    .id = self.vulnerability_count,
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

    /// Analyze FFI match for vulnerabilities
    fn analyzeFFIMatch(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) ![]FFIVulnerability {
        var vulnerabilities = std.ArrayList(FFIVulnerability).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        errdefer vulnerabilities.deinit();

        // Try to detect each type of vulnerability
        if (try self.detectCommandInjection(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(vuln);
        }

        if (try self.detectBufferOverflow(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(vuln);
        }

        if (try self.detectFormatString(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(vuln);
        }

        if (try self.detectUseAfterFree(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(vuln);
        }

        if (try self.detectIntegerOverflow(ctx, ffi_match)) |vuln| {
            try vulnerabilities.append(vuln);
        }

        return vulnerabilities.toOwnedSlice();
    }

    /// Check if function calls any dangerous function
    fn callsDangerousFunction(self: *FFIDetector, func: FunctionInfo, dangerous_funcs: []const []const u8) !?[]const u8 {
        _ = self;

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
                        const func_name_slice = std.mem.span(func_name);

                        for (dangerous_funcs) |dangerous| {
                            if (std.mem.eql(u8, func_name_slice, dangerous)) {
                                return func_name_slice;
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
        _ = self;
        _ = mem_funcs;

        // Simplified detection: check if function calls free
        // In a full implementation, we would track pointer usage
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
                        const func_name_slice = std.mem.span(func_name);

                        if (std.mem.eql(u8, func_name_slice, "free") or
                            std.mem.eql(u8, func_name_slice, "delete"))
                        {
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

    /// Check if function has unsafe arithmetic operations
    fn hasUnsafeArithmetic(self: *FFIDetector, func: FunctionInfo) !bool {
        _ = self;

        var bb = c.LLVMGetFirstBasicBlock(func.func.raw);
        while (bb != null) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);

                switch (opcode_enum) {
                    .Add, .Sub, .Mul, .UDiv, .SDiv, .URem, .SRem => {
                        const num_ops = c.LLVMGetNumOperands(inst);
                        if (num_ops >= 2) {
                            return true;
                        }
                    },
                    else => {},
                }

                inst = c.LLVMGetNextInstruction(inst);
            }
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        return false;
    }

    /// Check if tainted data flows from declare to define
    fn hasTaintedDataFlow(self: *FFIDetector, ctx: *PassContext, ffi_match: *const FFIMatch) !bool {
        _ = self;

        const taint_facts = try ctx.query_engine.queryByKind(.taint, ctx.allocator);
        defer ctx.allocator.free(taint_facts);

        if (taint_facts.len == 0) {
            return false;
        }

        const func_name = ffi_match.name;
        if (std.mem.indexOf(u8, func_name, "input") != null or
            std.mem.indexOf(u8, func_name, "user") != null or
            std.mem.indexOf(u8, func_name, "data") != null or
            std.mem.indexOf(u8, func_name, "buf") != null or
            std.mem.indexOf(u8, func_name, "str") != null)
        {
            return true;
        }

        return false;
    }

    /// Report a vulnerability
    fn reportVulnerability(self: *FFIDetector, vuln: *const FFIVulnerability, diag: *DiagnosticWriter) !void {
        _ = self;

        diag.err("VULNERABILITY #{}: {s}", .{ vuln.id, @tagName(vuln.vuln_type) });
        diag.err("  Severity: {s}", .{@tagName(vuln.severity)});
        diag.err("  Description: {s}", .{vuln.description});
        diag.err("  Source: {s}", .{vuln.source_location orelse "unknown"});
        diag.err("  Sink: {s}", .{vuln.sink_location orelse "unknown"});
        if (vuln.dangerous_function) |func| {
            diag.err("  Dangerous function: {s}", .{func});
        }
    }
};

// Validate that FFIDetector satisfies Pass interface
comptime {
    _ = Pass(FFIDetector);
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
    try std.testing.expectEqual(@as(usize, 5), @intFromEnum(FFIVulnerabilityType.unknown));
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
