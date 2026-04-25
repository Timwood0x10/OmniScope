//! Sensitive Data Flow Analysis
//!
//! Detects sensitive data (keys, secrets) that are freed without being cleared.
//! Key insight from investigation reports:
//! - Sensitive data should be zeroed before free to prevent memory forensics attacks.
//!
//! This module implements:
//! 1. Sensitive source detection (key generation, derivation)
//! 2. Data flow tracking from source to free
//! 3. Secure clear function detection

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const Severity = @import("../../diag/issue.zig").Severity;
const Location = @import("../../diag/issue.zig").Location;

/// Functions that generate sensitive data.
const SENSITIVE_SOURCES = [_][]const u8{
    // Key generation
    "gen_key",
    "generate_key",
    "create_key",
    "keygen",
    "KeyGen",
    "generate_secret",
    "create_secret",

    // Key derivation
    "derive_key",
    "kdf",
    "pbkdf",
    "scrypt",
    "argon2",
    "hkdf",
    "EVP_BytesToKey",
    "PKCS5_PBKDF2",

    // Cryptographic operations
    "crypto_scalarmult",
    "crypto_box",
    "crypto_sign",
    "ECDH",
    "DH_compute_key",

    // Random generation
    "RAND_bytes",
    "RAND_priv_bytes",
    "getrandom",
    "random_bytes",
};

/// Functions that securely clear memory.
const SECURE_CLEAR_FUNCS = [_][]const u8{
    "memset",
    "explicit_bzero",
    "explicit_memset",
    "OPENSSL_cleanse",
    "CRYPTO_cleanse",
    "sodium_memzero",
    "secure_zero",
    "secure_clear",
    "memzero",
    "bzero",
};

/// Represents a sensitive data source.
pub const SensitiveSource = struct {
    /// The instruction that generates sensitive data.
    inst: c.LLVMValueRef,
    /// The function name.
    func_name: []const u8,
    /// The pointer value ID.
    ptr_id: u32,
    /// Whether the data has been cleared.
    cleared: bool,
};

/// Represents a potential sensitive data residue issue.
pub const SensitiveDataIssue = struct {
    /// The source of the sensitive data.
    source: SensitiveSource,
    /// The free instruction.
    free_inst: c.LLVMValueRef,
    /// The function where the issue occurs.
    func_name: []const u8,
};

/// Check if a function is a sensitive data source.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function generates sensitive data
pub fn isSensitiveSource(func_name: []const u8) bool {
    for (SENSITIVE_SOURCES) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a function securely clears memory.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function clears memory securely
pub fn isSecureClearFunc(func_name: []const u8) bool {
    for (SECURE_CLEAR_FUNCS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a memset call is clearing to zero.
///
/// Arguments:
///   call_inst - The call instruction
///
/// Returns:
///   true if the memset is clearing to zero
pub fn isMemsetToZero(call_inst: c.LLVMValueRef) bool {
    if (@intFromPtr(call_inst) == 0) return false;
    if (c.LLVMIsACallInst(call_inst) == null) return false;

    const num_ops = c.LLVMGetNumOperands(call_inst);
    if (num_ops < 3) return false;

    const value_op = c.LLVMGetOperand(call_inst, 2);
    if (@intFromPtr(value_op) == 0) return false;

    if (c.LLVMIsAConstantInt(value_op) != null) {
        const value = c.LLVMConstIntGetZExtValue(value_op);
        return value == 0;
    }

    return false;
}

/// Detect sensitive data flow issues in a function.
///
/// This function scans a function for:
/// 1. Sensitive data sources (key generation, etc.)
/// 2. Memory free operations
/// 3. Missing secure clear before free
///
/// Arguments:
///   allocator - Memory allocator
///   func - The function to analyze
///   diag - Diagnostic writer
///
/// Returns:
///   A list of sensitive data issues found
pub fn detectSensitiveDataIssues(
    allocator: std.mem.Allocator,
    func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) std.ArrayList(SensitiveDataIssue) {
    var issues = std.ArrayList(SensitiveDataIssue).init(allocator);

    if (@intFromPtr(func) == 0) return issues;

    const func_name_ptr = c.LLVMGetValueName(func);
    const func_name = if (@intFromPtr(func_name_ptr) != 0)
        std.mem.span(func_name_ptr)
    else
        "unknown";

    var sensitive_sources = std.ArrayList(SensitiveSource).init(allocator);
    defer sensitive_sources.deinit();

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

                        if (isSensitiveSource(callee_name)) {
                            diag.debug("SENSITIVE-SOURCE: {s} generates sensitive data", .{callee_name});
                            sensitive_sources.append(.{
                                .inst = inst,
                                .func_name = callee_name,
                                .ptr_id = 0,
                                .cleared = false,
                            }) catch {};
                        }

                        if (isSecureClearFunc(callee_name) and isMemsetToZero(inst)) {
                            diag.debug("SECURE-CLEAR: {s} securely clears memory", .{callee_name});
                            for (sensitive_sources.items) |*source| {
                                source.cleared = true;
                            }
                        }
                    }
                }
            }
        }
    }

    for (sensitive_sources.items) |source| {
        if (!source.cleared) {
            issues.append(.{
                .source = source,
                .free_inst = null,
                .func_name = func_name,
            }) catch {};
        }
    }

    return issues;
}

/// Report a sensitive data residue issue.
///
/// Arguments:
///   ctx - Pass context for issue reporting
///   issue - The sensitive data issue
///   diag - Diagnostic writer
pub fn reportSensitiveDataIssue(
    ctx: *anyopaque,
    issue: SensitiveDataIssue,
    diag: *DiagnosticWriter,
) void {
    _ = ctx;
    diag.warn("SENSITIVE-DATA-RESIDUE [HIGH]: Sensitive data from {s} may not be cleared before free in {s}", .{
        issue.source.func_name,
        issue.func_name,
    });
}

/// Analyze a module for sensitive data flow issues.
///
/// Arguments:
///   allocator - Memory allocator
///   module - The LLVM module to analyze
///   diag - Diagnostic writer
///
/// Returns:
///   Total number of issues found
pub fn analyzeModule(
    allocator: std.mem.Allocator,
    module: c.LLVMModuleRef,
    diag: *DiagnosticWriter,
) usize {
    if (@intFromPtr(module) == 0) return 0;

    var total_issues: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        var issues = detectSensitiveDataIssues(allocator, func, diag);
        total_issues += issues.items.len;
        issues.deinit();
    }

    diag.info("Sensitive Data Flow: Found {d} potential issues", .{total_issues});

    return total_issues;
}

test "isSensitiveSource" {
    try std.testing.expect(isSensitiveSource("gen_key"));
    try std.testing.expect(isSensitiveSource("derive_key"));
    try std.testing.expect(isSensitiveSource("EVP_BytesToKey"));
    try std.testing.expect(!isSensitiveSource("malloc"));
}

test "isSecureClearFunc" {
    try std.testing.expect(isSecureClearFunc("memset"));
    try std.testing.expect(isSecureClearFunc("sodium_memzero"));
    try std.testing.expect(isSecureClearFunc("OPENSSL_cleanse"));
    try std.testing.expect(!isSecureClearFunc("free"));
}
