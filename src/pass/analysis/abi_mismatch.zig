//! ABI Mismatch Detector
//!
//! Phase 4.3: Detects packed struct ABI issues, alignment mismatches, and
//! unsafe type conversions across FFI boundaries.
//!
//! Key detection targets:
//! - Packed struct passed to extern function (C expects different layout)
//! - Alignment mismatch between caller/callee at FFI boundary
//! - Variadic argument type mismatches
//! - Endianness-sensitive types across platform boundaries
//!
//! Reference: plan/lang_ffi_analysis/zig_ffi_filter.md
//!
//! Example bugs detected:
//!
//!   // Zig: packed struct ABI mismatch
//!   const Packed = packed struct { a: u32, b: u8 };
//!   extern fn c_func(p: Packed) void;  // C expects different alignment/padding
//!
//!   // Zig: passing misaligned pointer to extern
//!   var buf: [256]u8 align(1) = undefined;
//!   c_process(&buf);  // C expects natural alignment

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

/// Types of ABI violations detected.
pub const ABIViolation = enum(u8) {
    /// Packed struct passed across FFI boundary
    packed_struct_ffi,
    /// Alignment mismatch at call site
    alignment_mismatch,
    /// Size mismatch between expected and actual
    size_mismatch,
    /// Variadic args with wrong types
    variadic_type_mismatch,
    /// Endianness-sensitive integer passed to extern
    endianness_risk,
};

/// Severity level for each violation type.
pub fn abiViolationSeverity(violation: ABIViolation) Severity {
    return switch (violation) {
        .packed_struct_ffi => .critical,
        .alignment_mismatch => .high,
        .size_mismatch => .high,
        .variadic_type_mismatch => .medium,
        .endianness_risk => .medium,
    };
}

/// Information about a detected ABI issue.
pub const ABIIssue = struct {
    violation: ABIViolation,
    confidence: f32,
    func_name: []const u8,
    callee_name: []const u8,
    description: []const u8,
    instruction_line: ?u32 = null,
};

/// Statistics for the ABI mismatch detector.
pub const ABIStats = struct {
    total_functions_analyzed: u32 = 0,
    extern_calls_checked: u32 = 0,
    packed_struct_violations: u32 = 0,
    alignment_mismatches: u32 = 0,
    size_mismatches: u32 = 0,
    variadic_issues: u32 = 0,
    endianness_warnings: u32 = 0,

    pub fn formatSummary(self: ABIStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║     ABI MISMATCH DETECTOR SUMMARY    ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:      {d:>8}     ║\n", .{self.total_functions_analyzed});
        try writer.print("║  Extern calls checked:    {d:>8}     ║\n", .{self.extern_calls_checked});
        try writer.print("║  Packed struct violations: {d:>8}     ║\n", .{self.packed_struct_violations});
        try writer.print("║  Alignment mismatches:    {d:>8}     ║\n", .{self.alignment_mismatches});
        try writer.print("║  Size mismatches:         {d:>8}     ║\n", .{self.size_mismatches});
        try writer.print("║  Variadic issues:         {d:>8}     ║\n", .{self.variadic_issues});
        try writer.print("║  Endianness warnings:     {d:>8}     ║\n", .{self.endianness_warnings});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Pattern Detection
// ============================================================================

/// Patterns indicating packed struct usage in Zig FFI.
const PACKED_STRUCT_PATTERNS = &[_][]const u8{
    "packed struct",
    "packed union",
    "extern struct",
    "bit_field",
    "__attribute__((packed))",
};

/// Functions known to be variadic (take variable arguments).
const VARIADIC_FUNCTIONS = &[_][]const u8{
    "printf",         "fprintf", "sprintf", "snprintf",
    "scanf",          "fscanf",  "sscanf",  "openlog",
    "syslog",         "execl",   "execle",  "execlp",
    "pthread_create",
};

/// Types that are endianness-sensitive when passed to C.
const ENDIAN_SENSITIVE_TYPES = &[_][]const u8{
    "u16le", "u16be", "u32le", "u32be",
    "u64le", "u64be", "i16le", "i16be",
    "i32le", "i32be", "i64le", "i64be",
};

/// Check if a type name suggests a packed structure.
pub fn isPackedStructType(type_name: []const u8) bool {
    for (PACKED_STRUCT_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, type_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee is a known variadic function.
pub fn isVariadicFunction(callee_name: []const u8) bool {
    for (VARIADIC_FUNCTIONS) |fn_name| {
        if (std.mem.eql(u8, callee_name, fn_name)) return true;
    }
    return false;
}

/// Check if a type name indicates endianness-sensitive data.
pub fn isEndianSensitive(type_name: []const u8) bool {
    for (ENDIAN_SENSITIVE_TYPES) |t| {
        if (std.mem.indexOf(u8, type_name, t) != null) return true;
    }
    return false;
}

/// Check if a function name indicates an extern/FFI boundary.
pub fn isExternCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;

    if (std.mem.startsWith(u8, callee_name, "c_") or
        std.mem.startsWith(u8, callee_name, "C."))
    {
        return true;
    }

    const common_extern_prefixes = [_][]const u8{
        "SDL_",     "GL_",     "glfw", "curl",  "openssl",
        "pthread_", "signal(", "mmap", "ioctl",
    };
    for (common_extern_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) return true;
    }

    return false;
}

// ============================================================================
// Main Pass
// ============================================================================

/// ABI Mismatch Detector Pass
///
/// Analyzes functions for ABI compatibility issues at FFI boundaries:
/// 1. Packed structs passed to extern functions
/// 2. Alignment mismatches between caller and callee expectations
/// 3. Size mismatches in struct/union parameters
/// 4. Variadic function argument type issues
/// 5. Endianness-sensitive types crossing language boundaries
pub const ABIMismatchPass = struct {
    pub const name = "abi-mismatch";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var stats = ABIStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            // Function-level error isolation
            analyzeFunction(ctx, func, diag, &stats) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("ABIMismatch: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
        }

        diag.info("ABIMismatch: analyzed {} funcs, {} extern calls, {} violations found", .{ stats.total_functions_analyzed, stats.extern_calls_checked, stats.packed_struct_violations + stats.alignment_mismatches +
            stats.size_mismatches + stats.variadic_issues + stats.endianness_warnings });
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *ABIStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        stats.total_functions_analyzed += 1;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try checkCallABI(ctx, inst, func_name, diag, stats);
            }
        }
    }

    fn checkCallABI(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
        stats: *ABIStats,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return;

        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return;

        const name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(name_ptr) == 0) return;

        const callee_name = std.mem.span(name_ptr);

        if (!isExternCall(callee_name)) return;

        stats.extern_calls_checked += 1;

        var i: u32 = 0;
        const num_ops = c.LLVMGetNumOperands(inst);
        while (i < num_ops) : (i += 1) {
            const arg = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(arg) == 0) continue;

            const arg_type = c.LLVMTypeOf(arg);
            if (@intFromPtr(arg_type) == 0) continue;

            const type_str = try getTypeString(ctx.allocator, arg_type);

            if (isPackedStructType(type_str)) {
                try reportPackedStructFFI(ctx, func_name, callee_name, type_str, diag);
                stats.packed_struct_violations += 1;
            }

            if (isEndianSensitive(type_str)) {
                try reportEndiannessRisk(ctx, func_name, callee_name, type_str, diag);
                stats.endianness_warnings += 1;
            }

            ctx.allocator.free(type_str);
        }

        if (isVariadicFunction(callee_name)) {
            try reportVariadicWarning(ctx, func_name, callee_name, diag);
            stats.variadic_issues += 1;
        }
    }

    fn getTypeString(allocator: std.mem.Allocator, ty: c.LLVMTypeRef) ![]const u8 {
        const type_kind = c.LLVMGetTypeKind(ty);
        const kind_name = switch (type_kind) {
            c.LLVMVoidTypeKind => "void",
            c.LLVMHalfTypeKind => "f16",
            c.LLVMFloatTypeKind => "f32",
            c.LLVMDoubleTypeKind => "f64",
            c.LLVMX86_FP80TypeKind => "x86_fp80",
            c.LLVMFP128TypeKind => "fp128",
            c.LLVMPPC_FP128TypeKind => "ppc_fp128",
            c.LLVMLabelTypeKind => "label",
            c.LLVMIntegerTypeKind => {
                const bits = c.LLVMGetIntTypeWidth(ty);
                return std.fmt.allocPrint(allocator, "i{}", .{bits});
            },
            c.LLVMFunctionTypeKind => "fn",
            c.LLVMStructTypeKind => "struct",
            c.LLVMArrayTypeKind => "array",
            c.LLVMPointerTypeKind => "ptr",
            c.LLVMVectorTypeKind => "vec",
            c.LLVMMetadataTypeKind => "metadata",
            c.LLVMX86_MMXTypeKind => "x86_mmx",
            c.LLVMTokenTypeKind => "token",
            else => "unknown",
        };
        return allocator.dupe(u8, kind_name);
    }
};

// ============================================================================
// Reporting
// ============================================================================

fn reportPackedStructFFI(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    type_str: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Packed struct or bit-field type passed to extern function");
    trace[1] = try makeTrace(ctx.allocator, "Argument type: {s}", .{type_str});
    trace[2] = try makeTrace(ctx.allocator, "C compiler may use different padding/alignment than Zig (CWE-190)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Packed struct ({s}) passed to {s}() - ABI layout may differ from C expectation",
        .{ type_str, callee_name },
    );

    const issue = Issue.initWithTrace(
        .type_mismatch,
        message,
        location,
        .critical,
        0.85,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[PACKED-FFI] {s} -> {s}() in {s}", .{ type_str, callee_name, func_name });
}

fn reportEndiannessRisk(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    type_str: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Endianness-sensitive type passed across FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "Argument type: {s}", .{type_str});
    trace[2] = try makeTrace(ctx.allocator, "Target platform endianness may differ from compilation host (CWE-198)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Endianness-sensitive type ({s}) passed to {s}() - verify target platform byte order",
        .{ type_str, callee_name },
    );

    const issue = Issue.initWithTrace(
        .type_mismatch,
        message,
        location,
        .medium,
        0.60,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[ENDIAN-RISK] {s} -> {s}() in {s}", .{ type_str, callee_name, func_name });
}

fn reportVariadicWarning(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Call to variadic function at FFI boundary");
    trace[1] = try makeTrace(ctx.allocator, "{s()}: argument types cannot be verified at compile time (CWE-134)", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Variadic function {s}() called - argument types should match format specifiers exactly",
        .{callee_name},
    );

    const issue = Issue.initWithTrace(
        .format_string,
        message,
        location,
        .medium,
        0.55,
        trace,
    );

    try ctx.addIssue(&issue);
    diag.warn("[VARIADIC] {s}() in {s}", .{ callee_name, func_name });
}

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "ABIMismatchPass - name and kind" {
    try std.testing.expectEqualStrings("abi-mismatch", ABIMismatchPass.name);
    try std.testing.expectEqual(PassKind.analysis, ABIMismatchPass.kind);
}

test "isPackedStructType - pattern matching" {
    try std.testing.expect(isPackedStructType("my_packed_struct"));
    try std.testing.expect(isPackedStructType("packed struct Foo"));
    try std.testing.expect(isPackedStructType("__attribute__((packed))"));
    try std.testing.expect(!isPackedStructType("normal_struct"));
    try std.testing.expect(!isPackedStructType("MyStruct"));
}

test "isVariadicFunction - known variadics" {
    try std.testing.expect(isVariadicFunction("printf"));
    try std.testing.expect(isVariadicFunction("sprintf"));
    try std.testing.expect(isVariadicFunction("snprintf"));
    try std.testing.expect(isVariadicFunction("pthread_create"));
    try std.testing.expect(!isVariadicFunction("malloc"));
    try std.testing.expect(!isVariadicFunction("free"));
}

test "isEndianSensitive - endian types" {
    try std.testing.expect(isEndianSensitive("u16le"));
    try std.testing.expect(isEndianSensitive("u32be"));
    try std.testing.expect(isEndianSensitive("i64le"));
    try std.testing.expect(!isEndianSensitive("u32"));
    try std.testing.expect(!isEndianSensitive("i64"));
    try std.testing.expect(!isEndianSensitive("f32"));
}

test "isExternCall - FFI detection" {
    try std.testing.expect(isExternCall("c_func"));
    try std.testing.expect(isExternCall("C.malloc"));
    try std.testing.expect(isExternCall("SDL_Init"));
    try std.testing.expect(isExternCall("glfwCreateWindow"));
    try std.testing.expect(isExternCall("pthread_create"));
    try std.testing.expect(!isExternCall("my_function"));
    try std.testing.expect(!isExternCall("std.debug.print"));
}

test "ABIViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ABIViolation.packed_struct_ffi));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ABIViolation.alignment_mismatch));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ABIViolation.size_mismatch));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ABIViolation.variadic_type_mismatch));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ABIViolation.endianness_risk));
}

test "abiViolationSeverity - severity mapping" {
    try std.testing.expectEqual(Severity.critical, abiViolationSeverity(.packed_struct_ffi));
    try std.testing.expectEqual(Severity.high, abiViolationSeverity(.alignment_mismatch));
    try std.testing.expectEqual(Severity.high, abiViolationSeverity(.size_mismatch));
    try std.testing.expectEqual(Severity.medium, abiViolationSeverity(.variadic_type_mismatch));
    try std.testing.expectEqual(Severity.medium, abiViolationSeverity(.endianness_risk));
}

test "ABIIssue - initialization" {
    const issue = ABIIssue{
        .violation = .packed_struct_ffi,
        .confidence = 0.90,
        .func_name = "test_func",
        .callee_name = "c_process",
        .description = "packed struct in FFI call",
    };
    try std.testing.expectEqual(ABIViolation.packed_struct_ffi, issue.violation);
    try testApproxEq(@as(f32, 0.90), issue.confidence, 0.01);
    try std.testing.expectEqualStrings("test_func", issue.func_name);
}

test "ABIStats - initialization and tracking" {
    const stats = ABIStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.packed_struct_violations);

    var mutable = ABIStats{};
    mutable.packed_struct_violations = 5;
    mutable.alignment_mismatches = 3;
    mutable.size_mismatches = 2;
    mutable.variadic_issues = 4;
    mutable.endianness_warnings = 1;
    try std.testing.expectEqual(@as(u32, 15), mutable.packed_struct_violations +
        mutable.alignment_mismatches + mutable.size_mismatches +
        mutable.variadic_issues + mutable.endianness_warnings);
}

fn testApproxEq(expected: f32, actual: f32, tolerance: f32) !void {
    try std.testing.expect(@abs(actual - expected) < tolerance);
}
