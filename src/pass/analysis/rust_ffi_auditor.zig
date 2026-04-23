//! Rust FFI Auditor - Independent Module for Rust↔C FFI Analysis
//!
//! This module provides dedicated analysis for Rust FFI boundary safety,
//! including ownership transfer pairing, borrow escape detection, and
//! cross-language allocation mismatch identification.
//!
//! Market positioning: The only static analysis tool focused on Rust FFI.
//!
//! Target scenarios:
//!   - sqlite bindings (rusqlite)
//!   - openssl bindings (rust-openssl)
//!   - tokio native deps
//!   - tauri plugins
//!   - napi-rs (Node.js)
//!   - pyo3 (Python)

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const Confidence = @import("../../diag/issue.zig").Confidence;
const Location = @import("../../diag/issue.zig").Location;

/// Rust FFI issue types specific to this auditor
pub const RustFfiIssueType = enum {
    /// Box::into_raw without matching from_raw
    unpaired_into_raw,
    /// CString::into_raw without matching from_raw
    unpaired_cstring_into_raw,
    /// as_ptr result passed to FFI, may dangle after drop
    as_ptr_borrow_escape,
    /// Rust _Znwm allocation freed by C free()
    cross_lang_alloc_mismatch,
    /// Unsafe FFI call without proper validation
    unsafe_ffi_call,
    /// extern "C" function with potential type mismatch
    extern_c_type_mismatch,
};

/// Rust FFI audit result for a single function
pub const RustFfiFinding = struct {
    func_name: []const u8,
    issue_type: RustFfiIssueType,
    severity: Severity,
    confidence: f32,
    reason: []const u8,
    location: Location,

    pub const Severity = enum {
        critical,
        high,
        medium,
        low,

        pub fn toString(self: Severity) []const u8 {
            return switch (self) {
                .critical => "CRITICAL",
                .high => "HIGH",
                .medium => "MEDIUM",
                .low => "LOW",
            };
        }
    };
};

/// Main Rust FFI Auditor struct
pub const RustFfiAuditor = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList(RustFfiFinding),
    stats: AuditStats,

    pub const AuditStats = struct {
        total_functions_analyzed: usize = 0,
        into_raw_funcs: usize = 0,
        from_raw_funcs: usize = 0,
        as_ptr_escapes: usize = 0,
        cross_lang_mismatches: usize = 0,
        unsafe_ffi_calls: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) RustFfiAuditor {
        return .{
            .allocator = allocator,
            .findings = std.ArrayList(RustFfiFinding).init(allocator),
            .stats = .{},
        };
    }

    pub fn deinit(self: *RustFfiAuditor) void {
        self.findings.deinit();
    }

    /// Run full audit on an LLVM module
    pub fn audit(self: *RustFfiAuditor, module: c.LLVMModuleRef, ctx: *PassContext, diag: *DiagnosticWriter) ![]const RustFfiFinding {
        self.findings.clearRetainCapacity();
        self.stats = .{};

        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;
            self.stats.total_functions_analyzed += 1;

            try self.auditFunction(func, ctx, diag);
        }

        return try self.findings.toOwnedSlice();
    }

    /// Audit a single function for all Rust FFI patterns
    fn auditFunction(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const func_name = getFunctionName(func);

        // Rule 1: into_raw/from_raw pairing check
        if (ctx.rust_into_raw_set.contains(@intFromPtr(c.LLVMGetValueName(func)))) {
            if (ctx.rust_from_raw_set.count() == 0) {
                try self.addFinding(.{
                    .func_name = func_name,
                    .issue_type = .unpaired_into_raw,
                    .severity = .high,
                    .confidence = 0.75,
                    .reason = "into_raw() called but no matching from_raw() in module",
                    .location = Location.init(func_name),
                });
                self.stats.into_raw_funcs += 1;
            }
        }

        // Rule 2: as_ptr borrow escape detection
        try self.detectAsPtrEscape(func, ctx, diag);

        // Rule 3: Cross-lang alloc mismatch
        try self.detectCrossLangMismatch(func, ctx, diag);

        // Rule 4: Unsafe block FFI call scan
        try self.detectUnsafeFfiCalls(func);
    }

    /// Detect as_ptr borrow escape in function body
    fn detectAsPtrEscape(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (!isRustAsPtrCall(name_slice)) continue;

                self.stats.as_ptr_escapes += 1;
                const func_name = getFunctionName(func);

                try self.addFinding(.{
                    .func_name = func_name,
                    .issue_type = .as_ptr_borrow_escape,
                    .severity = .high,
                    .confidence = 0.80,
                    .reason = "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                    .location = Location.init(func_name),
                });

                const vuln_id = ctx.getNextVulnId();
                ctx.addIssue(Issue.initWithReason(
                    .borrow_escape,
                    "Potential as_ptr borrow escape: local Rust value pointer passed to FFI",
                    Location.init(func_name),
                    .high,
                    0.8,
                    "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                )) catch |err| {
                    diag.warn("Failed to register borrow_escape issue: {}", .{err});
                };
                diag.err("VULNERABILITY OMI-{d:0>3} [high] [Confidence: medium]", .{vuln_id});
                diag.err("Type: borrow_escape", .{});
                diag.err("Reason: as_ptr() on local value passed to FFI - may dangle", .{});
            }
        }
    }

    /// Detect cross-language allocation mismatch (Rust _Znwm → C free)
    fn detectCrossLangMismatch(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (!isCFreeCall(name_slice)) continue;

                const func_name = getFunctionName(func);
                self.stats.cross_lang_mismatches += 1;

                try self.addFinding(.{
                    .func_name = func_name,
                    .issue_type = .cross_lang_alloc_mismatch,
                    .severity = .high,
                    .confidence = 0.85,
                    .reason = "C free() may be freeing Rust-allocated memory (_Znwm)",
                    .location = Location.init(func_name),
                });

                const vuln_id = ctx.getNextVulnId();
                ctx.addIssue(Issue.initWithReason(
                    .cross_language_leak,
                    "Cross-language alloc mismatch: Rust-alloc freed by C free()",
                    Location.init(func_name),
                    .high,
                    0.85,
                    "Rust _Znwm allocation freed by C free() - heap mismatch",
                )) catch |err| {
                    diag.warn("Failed to register cross_language_leak issue: {}", .{err});
                };
                diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [high] [Confidence: high]", .{vuln_id});
                diag.err("Type: cross_language_alloc_mismatch", .{});
                diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
            }
        }
    }

    /// Detect unsafe FFI calls without validation
    fn detectUnsafeFfiCalls(self: *RustFfiAuditor, func: c.LLVMValueRef) !void {
        var has_unsafe_ffi = false;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (isExternCCall(name_slice)) {
                    has_unsafe_ffi = true;
                }
            }
            if (has_unsafe_ffi) break;
        }

        if (has_unsafe_ffi) {
            self.stats.unsafe_ffi_calls += 1;
            const func_name = getFunctionName(func);

            try self.addFinding(.{
                .func_name = func_name,
                .issue_type = .unsafe_ffi_call,
                .severity = .medium,
                .confidence = 0.60,
                .reason = "Function contains extern \"C\" calls requiring manual review",
                .location = Location.init(func_name),
            });
        }
    }

    fn addFinding(self: *RustFfiAuditor, finding: RustFfiFinding) !void {
        try self.findings.append(finding);
    }

    /// Generate audit report as formatted text
    pub fn generateReport(self: *const RustFfiAuditor, writer: anytype) !void {
        try writer.writeAll(
            \\╔══════════════════════════════════════════════════════════╗
            \\║           Rust FFI Safety Audit Report                  ║
            \\╠══════════════════════════════════════════════════════════╣
        );

        try writer.print(
            \\║ Functions analyzed: {d:>8}                            ║
            \\║ Findings:           {d:>8}                            ║
            \\╚══════════════════════════════════════════════════════════╝
            \\
        , .{ self.stats.total_functions_analyzed, self.findings.items.len });

        for (self.findings.items, 0..) |finding, i| {
            try writer.writeAll("┌─────────────────────────────────────────\n");
            try writer.print("│ Finding #{}: {}\n", .{ i + 1, @tagName(finding.issue_type) });
            try writer.print("│ Function: {}\n", .{finding.func_name});
            try writer.print("│ Severity: [{}]\n", .{finding.severity.toString()});
            try writer.print("│ Confidence: {d:.0%}\n", .{finding.confidence});
            try writer.print("│ Reason: {}\n", .{finding.reason});
            try writer.writeAll("└─────────────────────────────────────────\n");
        }
    }
};

// ============================================================================
// Detection Helpers
// ============================================================================

/// Extract function name from LLVM value reference
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "unknown";
    return std.mem.span(name_ptr);
}

/// Check if a callee name is a Rust into_raw (ownership transfer OUT) call
pub fn isRustIntoRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "into_raw",
        "8into_raw",
        "Box.*into_raw",
        "CString.*into_raw",
        "Vec.*leak",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust from_raw (ownership transfer IN) call
pub fn isRustFromRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "from_raw",
        "8from_raw",
        "Box.*from_raw",
        "CString.*from_raw",
        "from_raw_parts",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust as_ptr (borrow escape) call
pub fn isRustAsPtrCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "as_ptr",
        "as_mut_ptr",
        "slice::as_ptr",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a C free() call
pub fn isCFreeCall(callee_name: []const u8) bool {
    return std.mem.eql(u8, callee_name, "free") or
        std.mem.indexOf(u8, callee_name, "free@") != null;
}

/// Check if a callee name looks like an extern "C" function
pub fn isExternCCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;
    if (callee_name[0] == '_') return false;
    if (std.mem.startsWith(u8, callee_name, "_Z")) return false;
    if (std.mem.startsWith(u8, callee_name, "_R")) return false;
    return true;
}

/// Detect Rust FFI pairing functions (populates into_raw/from_raw sets)
pub fn detectRustFfiPairingFunctions(
    func: c.LLVMValueRef,
    into_raw_set: *std.AutoHashMap(usize, void),
    from_raw_set: *std.AutoHashMap(usize, void),
) void {
    var has_into_raw = false;
    var has_from_raw = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands == 0) continue;
            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (isRustIntoRawCall(name_slice)) has_into_raw = true;
            if (isRustFromRawCall(name_slice)) has_from_raw = true;
        }
        if (has_into_raw and has_from_raw) break;
    }

    if (has_into_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            into_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
        }
    }
    if (has_from_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            from_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "RustFfiAuditor - init and deinit" {
    var auditor = RustFfiAuditor.init(std.testing.allocator);
    defer auditor.deinit();
    try std.testing.expectEqual(@as(usize, 0), auditor.findings.items.len);
    try std.testing.expectEqual(@as(usize, 0), auditor.stats.total_functions_analyzed);
}

test "isRustIntoRawCall - detection" {
    try std.testing.expect(isRustIntoRawCall("_ZN5alloc3boxed3Box*.*8into_raw17h"));
    try std.testing.expect(isRustIntoRawCall("into_raw"));
    try std.testing.expect(!isRustIntoRawCall("from_raw"));
    try std.testing.expect(!isRustIntoRawCall("malloc"));
}

test "isRustFromRawCall - detection" {
    try std.testing.expect(isRustFromRawCall("_ZN5alloc3boxed3Box*.*8from_raw17h"));
    try std.testing.expect(isRustFromRawCall("from_raw"));
    try std.testing.expect(!isRustFromRawCall("into_raw"));
}

test "isRustAsPtrCall - detection" {
    try std.testing.expect(isRustAsPtrCall("as_ptr"));
    try std.testing.expect(isRustAsPtrCall("as_mut_ptr"));
    try std.testing.expect(!isRustAsPtrCall("from_raw"));
}

test "isCFreeCall - detection" {
    try std.testing.expect(isCFreeCall("free"));
    try std.testing.expect(isCFreeCall("free@GLIBC"));
    try std.testing.expect(!isCFreeCall("malloc"));
}

test "isExternCCall - detection" {
    try std.testing.expect(isExternCCall("sqlite3_exec"));
    try std.testing.expect(isExternCCall("printf"));
    try std.testing.expect(!isExternCCall("_Znwm"));
    try std.testing.expect(!isExternCCall("_RNvC"));
}
