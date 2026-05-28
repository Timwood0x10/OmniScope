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
const c = @import("../../../ir/llvm_raw.zig").c;
const CommonTypes = @import("../../../common/types.zig");
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");
const ffi_language_classifier = @import("../ffi/ffi_language_classifier.zig");
const rust_drop_semantics = @import("../../../semantics/rust_drop_semantics.zig");
const tracking = @import("../ptr_lifetime/value_tracking.zig");
const helpers = @import("../ffi/ffi_helpers.zig");
const debug_info = @import("../debug_info.zig");
const alias = @import("../alias_analysis.zig");

// Import shared types from extracted module
const types = @import("../../../types/rust_ffi_types.zig");
pub const RustFfiIssueType = types.RustFfiIssueType;
pub const RustFfiFinding = types.RustFfiFinding;
pub const ValueSource = types.ValueSource;
pub const ValueUsage = types.ValueUsage;
pub const UsageSet = types.UsageSet;
const FreeEntry = types.FreeEntry;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Confidence = @import("../../../diag/issue.zig").Confidence;
const Severity = @import("../../../diag/issue.zig").Severity;
const Location = @import("../../../diag/issue.zig").Location;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

// Import rule implementations from sub-modules
const basic_rules = @import("rust_ffi_rules_basic.zig");
const lifetime_rules = @import("rust_ffi_rules_lifetime.zig");
const advanced_rules = @import("rust_ffi_rules_advanced.zig");

/// Main Rust FFI Auditor struct
pub const RustFfiAuditor = struct {
    pub const name = "rust-ffi-filter";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"SemanticResolver"};

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
        stack_escapes: usize = 0,
        unpaired_into_raw: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!RustFfiAuditor {
        return .{
            .allocator = allocator,
            .findings = try std.ArrayList(RustFfiFinding).initCapacity(allocator, 16),
            .stats = .{},
        };
    }

    pub fn deinit(self: *RustFfiAuditor) void {
        // C4 FIX: Don't free func_name and reason - they are NOT owned by this struct.
        // - func_name comes from LLVMGetValueName (LLVM-owned, must not free)
        // - reason is always a string literal (comptime, must not free)
        // Only the findings ArrayList itself was allocated by us.
        self.findings.deinit(self.allocator);
    }

    /// Run full audit on an LLVM module (Pass interface)
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        const mod = ctx.module.?.raw;

        var auditor = try RustFfiAuditor.init(ctx.allocator);
        defer auditor.deinit();

        // audit() returns toOwnedSlice — must free it to avoid leak
        const findings = try auditor.audit(mod, ctx, diag);
        ctx.allocator.free(findings);

        diag.info("FFIAuditor: analyzed {d} funcs, {d} findings ({d} stack escapes)", .{ auditor.stats.total_functions_analyzed, auditor.findings.items.len, auditor.stats.stack_escapes });
    }

    /// Run full audit on an LLVM module
    pub fn audit(self: *RustFfiAuditor, module: c.LLVMModuleRef, ctx: *PassContext, diag: *DiagnosticWriter) ![]const RustFfiFinding {
        self.findings.clearRetainingCapacity();
        self.stats = .{};

        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;
            self.stats.total_functions_analyzed += 1;

            try self.auditFunction(func, ctx, diag);
        }

        return try self.findings.toOwnedSlice(self.allocator);
    }

    /// Audit a single function for all Rust FFI patterns.
    fn auditFunction(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const func_name = getFunctionName(func);
        const is_rust = ctx.isRustModule();

        // ── Rust-specific rules (language-gated) ──
        if (is_rust) {
            // Rule 1: into_raw/from_raw pairing check
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) != 0) {
                const func_name_slice = std.mem.sliceTo(func_name_ptr, 0);
                if (ctx.rust_into_raw_set.contains(func_name_slice)) {
                    if (ctx.rust_from_raw_set.count() == 0) {
                        try basic_rules.addFinding(self, .{
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
            }

            // Rule 2: as_ptr borrow escape detection
            try basic_rules.detectAsPtrEscape(self, func, ctx, diag);

            // Rule 3: Cross-lang alloc mismatch (Rust _Znwm → C free)
            try basic_rules.detectCrossLangMismatch(self, func, ctx, diag);

            // Rule 6: Ownership transfer protocol (into_raw/from_raw pairing)
            try basic_rules.detectOwnershipTransferViolations(self, func, ctx, diag);

            // Rule 7: as_ptr dangling detection — borrowed ptr used after parent drop
            try lifetime_rules.detectAsPtrDangling(self, func, ctx, diag);
        }

        // ── Universal FFI boundary rules (run on ALL languages) ──

        // Rule 4: Unsafe block FFI call scan
        try basic_rules.detectUnsafeFfiCalls(self, func);

        // Rule 5: Stack address escape to FFI boundary (alloca/local → extern "C")
        try basic_rules.detectStackEscapeToFFI(self, func, ctx, diag);

        // Rule 8: Callback ownership risk — function pointer parameter stored to global
        try lifetime_rules.detectCallbackOwnershipRisk(self, func, ctx, diag);

        // Rule 9: Write to immutable — store through pointer from const-qualified struct field
        try advanced_rules.detectWriteToImmutable(self, func, ctx, diag);

        // Rule 10: Use after free — post-free pointer use within same function
        try advanced_rules.detectUseAfterFree(self, func, ctx, diag);
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
            try writer.print("│ Finding #{d}: {s}\n", .{ i + 1, @tagName(finding.issue_type) });
            try writer.print("│ Function: {s}\n", .{finding.func_name});
            try writer.print("│ Severity: [{s}]\n", .{finding.severity.toString()});
            try writer.print("│ Confidence: {d:.0%}\n", .{finding.confidence});
            try writer.print("│ Reason: {s}\n", .{finding.reason});
            try writer.writeAll("└─────────────────────────────────────────\n");
        }
    }

    // =====================================================================
    // Unified Value Tracking API (T1 + T2) — delegates to value_tracking.zig
    // =====================================================================

    pub fn traceValueSource(self: *RustFfiAuditor, val: c.LLVMValueRef, func: c.LLVMValueRef) ValueSource {
        _ = self;
        return tracking.traceValueSource(val, func);
    }

    pub fn traceValueUsage(self: *RustFfiAuditor, val: c.LLVMValueRef, func: c.LLVMValueRef) ?UsageSet {
        _ = self;
        return tracking.traceValueUsage(val, func);
    }
};

// ============================================================================
// Detection Helpers — Extracted to rust_ffi_helpers.zig
// ============================================================================

const rust_ffi_helpers = @import("rust_ffi_helpers.zig");

pub const getFunctionName = rust_ffi_helpers.getFunctionName;
pub const isRustIntoRawCall = rust_ffi_helpers.isRustIntoRawCall;
pub const isRustFromRawCall = rust_ffi_helpers.isRustFromRawCall;
pub const isRustAsPtrCall = rust_ffi_helpers.isRustAsPtrCall;
pub const isCFreeCall = rust_ffi_helpers.isCFreeCall;
pub const isRustAllocCall = rust_ffi_helpers.isRustAllocCall;
pub const isExternCCall = rust_ffi_helpers.isExternCCall;
pub const isCoreFfiFunction = rust_ffi_helpers.isCoreFfiFunction;
pub const isLibcFunction = rust_ffi_helpers.isLibcFunction;
pub const classifyFfiBoundaryType = rust_ffi_helpers.classifyFfiBoundaryType;
pub const detectRustFfiPairingFunctions = rust_ffi_helpers.detectRustFfiPairingFunctions;
pub const isRustMangledName = rust_ffi_helpers.isRustMangledName;
pub const mayRetainPointer = rust_ffi_helpers.mayRetainPointer;
pub const ptrOriginatesFromRustAlloc = rust_ffi_helpers.ptrOriginatesFromRustAlloc;
pub const isPureConsumptionFunction = rust_ffi_helpers.isPureConsumptionFunction;

// Re-export helper functions from sub-modules for external use
pub const valuesMayAlias = basic_rules.valuesMayAlias;
pub const unwrapSingleLevel = basic_rules.unwrapSingleLevel;
pub const isSameBasePointer = basic_rules.isSameBasePointer;
pub const getBaseValue = basic_rules.getBaseValue;
pub const findParentCall = basic_rules.findParentCall;
pub const isFreeLikeFunction = basic_rules.isFreeLikeFunction;
pub const isSafeGlobalStore = lifetime_rules.isSafeGlobalStore;
pub const isGlobalUsedForIndirectCall = lifetime_rules.isGlobalUsedForIndirectCall;
pub const isValueFromGlobal = lifetime_rules.isValueFromGlobal;
pub const hasStructDebugMetadata = lifetime_rules.hasStructDebugMetadata;
pub const instructionUsesValue = lifetime_rules.instructionUsesValue;
pub const ptrTracesTo = advanced_rules.ptrTracesTo;
pub const getStructNameForValue = advanced_rules.getStructNameForValue;
pub const findStoreToAlloca = advanced_rules.findStoreToAlloca;
pub const getStructNameFromGEP = advanced_rules.getStructNameFromGEP;
pub const getGepFieldIndex = advanced_rules.getGepFieldIndex;
pub const isDeallocator = advanced_rules.isDeallocator;
pub const instructionComesBeforeOrEqual = advanced_rules.instructionComesBeforeOrEqual;
pub const isConstQualifiedMember = advanced_rules.isConstQualifiedMember;
pub const getDIBaseType = advanced_rules.getDIBaseType;
pub const isDITag = advanced_rules.isDITag;
pub const getDIFieldName = advanced_rules.getDIFieldName;
pub const getDITypeName = advanced_rules.getDITypeName;

// ============================================================================
// Tests
// ============================================================================

test "RustFfiAuditor - init and deinit" {
    var auditor = try RustFfiAuditor.init(std.testing.allocator);
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

test "isRustMangledName - detection" {
    // Rust v0 with hash suffix
    try std.testing.expect(isRustMangledName("_ZN9hello_world4main17h1234567890abcdefE"));
    // Rust new mangling
    try std.testing.expect(isRustMangledName("_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc"));
    try std.testing.expect(isRustMangledName("_RINv"));
    // Rust std/core namespaces
    try std.testing.expect(isRustMangledName("_ZN4core3ptr13drop_in_place17h1234E"));
    // C++ _ZN should NOT be detected as Rust
    try std.testing.expect(!isRustMangledName("_ZN4Base1fEv"));
    try std.testing.expect(!isRustMangledName("_ZNSt3__110unique_ptr"));
    // Non-mangled names
    try std.testing.expect(!isRustMangledName("c_ffi_process_buffer"));
    try std.testing.expect(!isRustMangledName("malloc"));
}

test "mayRetainPointer - detection" {
    try std.testing.expect(mayRetainPointer("c_ffi_store_pointer"));
    try std.testing.expect(mayRetainPointer("c_ffi_register_callback"));
    try std.testing.expect(mayRetainPointer("set_user_data"));
    try std.testing.expect(!mayRetainPointer("memcpy"));
    try std.testing.expect(!mayRetainPointer("c_ffi_process_buffer"));
}

test "isPureConsumptionFunction - safe functions" {
    try std.testing.expect(isPureConsumptionFunction("memcpy"));
    try std.testing.expect(isPureConsumptionFunction("printf"));
    try std.testing.expect(isPureConsumptionFunction("strlen"));
    try std.testing.expect(!isPureConsumptionFunction("c_ffi_store_pointer"));
    try std.testing.expect(!isPureConsumptionFunction("pthread_create"));
}

test "StringHashMap pairing stability - same content, different backing" {
    const testing = std.testing;

    var into_raw_set = std.StringHashMap(void).init(testing.allocator);
    defer into_raw_set.deinit();
    var from_raw_set = std.StringHashMap(void).init(testing.allocator);
    defer from_raw_set.deinit();

    const name1 = "my_func_into_raw";
    const name2 = "my_func_into_raw";

    try into_raw_set.put(name1, {});
    try testing.expect(into_raw_set.contains(name2));
    try testing.expectEqual(@as(usize, 1), into_raw_set.count());

    const name3 = "my_func_from_raw";
    const name4 = "my_func_from_raw";
    try from_raw_set.put(name3, {});
    try testing.expect(from_raw_set.contains(name4));
    try testing.expectEqual(@as(usize, 1), from_raw_set.count());

    try testing.expect(!into_raw_set.contains("other_func"));
    try testing.expect(!from_raw_set.contains("my_func_into_raw"));
}

test "StringHashMap pairing stability - mangled Rust names" {
    const testing = std.testing;

    var set = std.StringHashMap(void).init(testing.allocator);
    defer set.deinit();

    const mangled_names = [_][]const u8{
        "_ZN5alloc3boxed3Box*.*8into_raw17habc123",
        "_ZN5alloc3boxed3Box*.*8from_raw17hdef456",
        "_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc",
    };

    for (mangled_names) |name| {
        try set.put(name, {});
    }

    try testing.expectEqual(@as(usize, 3), set.count());

    for (mangled_names) |name| {
        const dup = try testing.dupe(u8, name);
        defer testing.allocator.free(dup);
        try testing.expect(set.contains(dup));
    }
}
