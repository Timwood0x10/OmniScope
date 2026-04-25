//! Transmute Lifetime Bypass Detection
//!
//! Detects unsafe transmute operations that bypass Rust's lifetime checking.
//! Key insight from investigation reports:
//! - blst: transmute::<Thunk<'scope>, Thunk<'static>> bypasses lifetime safety
//! - This is a real security risk, not a false positive
//!
//! This module implements:
//! 1. transmute call detection
//! 2. Lifetime annotation extraction
//! 3. Lifetime extension risk assessment

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const Severity = @import("../../diag/issue.zig").Severity;
const Location = @import("../../diag/issue.zig").Location;

/// Patterns that indicate transmute operations.
const TRANSMUTE_PATTERNS = [_][]const u8{
    "std::mem::transmute",
    "core::mem::transmute",
    "mem::transmute",
    "transmute<",
    "_ZN4core3mem8transmute",
    "_ZN3std3mem8transmute",
};

/// Represents a detected transmute operation.
pub const TransmuteOp = struct {
    /// The call instruction.
    inst: c.LLVMValueRef,
    /// The function name containing transmute.
    func_name: []const u8,
    /// Source type (if extractable).
    source_type: ?[]const u8,
    /// Target type (if extractable).
    target_type: ?[]const u8,
    /// Risk level.
    risk_level: RiskLevel,
};

/// Risk level for transmute operations.
pub const RiskLevel = enum(u8) {
    /// Safe transmute (same size, compatible types).
    low,
    /// Potentially unsafe (different lifetimes).
    medium,
    /// Definitely unsafe (lifetime bypass).
    high,
};

/// Check if a function is a transmute operation.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function is a transmute
pub fn isTransmute(func_name: []const u8) bool {
    for (TRANSMUTE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Extract lifetime annotations from a type string.
///
/// Arguments:
///   type_str - The type string to analyze
///
/// Returns:
///   A list of lifetime annotations found
pub fn extractLifetimes(allocator: std.mem.Allocator, type_str: []const u8) std.ArrayList([]const u8) {
    var lifetimes = std.ArrayList([]const u8).init(allocator);

    var i: usize = 0;
    while (i < type_str.len) {
        if (std.mem.startsWith(u8, type_str[i..], "'")) {
            var end = i + 1;
            while (end < type_str.len and (std.ascii.isAlphabetic(type_str[end]) or std.ascii.isDigit(type_str[end]))) {
                end += 1;
            }
            if (end > i + 1) {
                lifetimes.append(type_str[i..end]) catch {};
            }
            i = end;
        } else {
            i += 1;
        }
    }

    return lifetimes;
}

/// Check if a transmute extends a lifetime.
///
/// Pattern: transmute::<Type<'a>, Type<'static>>
/// This is dangerous because it extends a bounded lifetime to 'static.
///
/// Arguments:
///   source_lifetimes - Lifetimes in source type
///   target_lifetimes - Lifetimes in target type
///
/// Returns:
///   true if the transmute extends a lifetime
pub fn isLifetimeExtension(
    source_lifetimes: []const []const u8,
    target_lifetimes: []const []const u8,
) bool {
    for (target_lifetimes) |target_lt| {
        if (std.mem.eql(u8, target_lt, "'static")) {
            for (source_lifetimes) |source_lt| {
                if (!std.mem.eql(u8, source_lt, "'static")) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Detect transmute operations in a function.
///
/// Arguments:
///   allocator - Memory allocator
///   func - The function to analyze
///   diag - Diagnostic writer
///
/// Returns:
///   A list of transmute operations found
pub fn detectTransmutes(
    allocator: std.mem.Allocator,
    func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) std.ArrayList(TransmuteOp) {
    var transmutes = std.ArrayList(TransmuteOp).init(allocator);

    if (@intFromPtr(func) == 0) return transmutes;

    const func_name_ptr = c.LLVMGetValueName(func);
    const func_name = if (@intFromPtr(func_name_ptr) != 0)
        std.mem.span(func_name_ptr)
    else
        "unknown";

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            if (opcode == c.LLVMCall) {
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) != 0) {
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(callee_name_ptr) != 0) {
                        const callee_name = std.mem.span(callee_name_ptr);

                        if (isTransmute(callee_name)) {
                            diag.debug("TRANSMUTE: Found transmute in {s}", .{func_name});

                            var risk: RiskLevel = .medium;

                            if (std.mem.indexOf(u8, callee_name, "'static") != null) {
                                if (std.mem.indexOf(u8, callee_name, "'_") != null or
                                    std.mem.indexOf(u8, callee_name, "'a") != null or
                                    std.mem.indexOf(u8, callee_name, "'b") != null)
                                {
                                    risk = .high;
                                    diag.warn("LIFETIME-BYPASS [HIGH]: transmute extends lifetime to 'static in {s}", .{func_name});
                                }
                            }

                            transmutes.append(.{
                                .inst = inst,
                                .func_name = func_name,
                                .source_type = null,
                                .target_type = null,
                                .risk_level = risk,
                            }) catch {};
                        }
                    }
                }
            }
        }
    }

    return transmutes;
}

/// Report a transmute issue.
///
/// Arguments:
///   ctx - Pass context for issue reporting
///   transmute - The transmute operation
///   diag - Diagnostic writer
pub fn reportTransmuteIssue(
    ctx: *anyopaque,
    transmute: TransmuteOp,
    diag: *DiagnosticWriter,
) void {
    _ = ctx;

    const severity_str = switch (transmute.risk_level) {
        .low => "LOW",
        .medium => "MEDIUM",
        .high => "HIGH",
    };

    diag.warn("TRANSMUTE-{s}: transmute operation in {s} may bypass type safety", .{
        severity_str,
        transmute.func_name,
    });
}

/// Analyze a module for transmute issues.
///
/// Arguments:
///   allocator - Memory allocator
///   module - The LLVM module to analyze
///   diag - Diagnostic writer
///
/// Returns:
///   Total number of high-risk transmutes found
pub fn analyzeModule(
    allocator: std.mem.Allocator,
    module: c.LLVMModuleRef,
    diag: *DiagnosticWriter,
) usize {
    if (@intFromPtr(module) == 0) return 0;

    var high_risk_count: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        var transmutes = detectTransmutes(allocator, func, diag);
        for (transmutes.items) |t| {
            if (t.risk_level == .high) {
                high_risk_count += 1;
            }
        }
        transmutes.deinit();
    }

    diag.info("Transmute Analysis: Found {d} high-risk transmute operations", .{high_risk_count});

    return high_risk_count;
}

test "isTransmute" {
    try std.testing.expect(isTransmute("std::mem::transmute"));
    try std.testing.expect(isTransmute("core::mem::transmute"));
    try std.testing.expect(isTransmute("transmute<"));
    try std.testing.expect(!isTransmute("malloc"));
}

test "extractLifetimes" {
    const allocator = std.testing.allocator;
    var lifetimes = extractLifetimes(allocator, "Thunk<'a, 'b>");
    defer lifetimes.deinit();

    try std.testing.expectEqual(@as(usize, 2), lifetimes.items.len);
}

test "isLifetimeExtension" {
    const source = [_][]const u8{ "'a", "'b" };
    const target_static = [_][]const u8{ "'static" };
    const target_same = [_][]const u8{ "'a", "'b" };

    try std.testing.expect(isLifetimeExtension(&source, &target_static));
    try std.testing.expect(!isLifetimeExtension(&source, &target_same));
}
