//! Shared type definitions for language adapters.
//!
//! This module provides the canonical type system for the multi-language
//! adapter framework. All language-specific adapters use these types to
//! communicate with the core analysis engine in a language-agnostic way.
//!
//! Design principle: Types here map 1:1 to FFIBoundary.Language where possible,
//! but extend it with memory model and FFI semantics classifications that
//! are specific to cross-language analysis.

const std = @import("std");

/// Re-export the canonical Language enum from diag/issue.zig.
/// All new code should use TargetLanguage as the adapter-framework alias.
pub const Language = @import("../diag/issue.zig").FFIBoundary.Language;

/// Memory management model for a target language.
///
/// Classifies how each language manages object lifetimes, which determines
/// whether leaks are possible and how ownership transfers work across FFI.
pub const MemoryModel = enum {
    /// Manual malloc/free (C style). Leaks are common.
    manual,
    /// RAII / destructors (C++, Rust). Compiler inserts cleanup at scope end.
    raii,
    /// Reference counting (Python, Objective-C). Leak if refcount never reaches 0.
    refcount,
    /// Garbage collected (Java, Go runtime). Collector handles cleanup.
    gc,
    /// Hybrid (C# SafeHandle + GC, Go cgo). Depends on usage pattern.
    hybrid,

    /// Human-readable name for logging and diagnostics.
    pub fn displayName(self: MemoryModel) []const u8 {
        return switch (self) {
            .manual => "Manual",
            .raii => "RAII",
            .refcount => "RefCount",
            .gc => "GC",
            .hybrid => "Hybrid",
        };
    }

    /// Check if this memory model allows resource leaks in normal operation.
    pub fn allowsLeak(self: MemoryModel) bool {
        return switch (self) {
            .manual => true,
            .raii => false,
            .refcount => true,
            .gc => false,
            .hybrid => true,
        };
    }

    /// Get the default memory model for a given target language.
    pub fn forLanguage(lang: Language) MemoryModel {
        return switch (lang) {
            .c => .manual,
            .cpp => .raii,
            .rust => .raii,
            .zig => .raii,
            .python => .refcount,
            .go => .hybrid,
            .csharp => .hybrid,
            .java => .gc,
            .unknown => .manual,
        };
    }
};

/// FFI call semantics classification.
pub const FFISemantics = enum {
    returns_owned,
    returns_borrowed,
    consumes_arg,
    python_refcount_inc,
    python_refcount_dec,
    inout,
    unknown,

    pub fn displayName(self: FFISemantics) []const u8 {
        return switch (self) {
            .returns_owned => "ReturnsOwned",
            .returns_borrowed => "ReturnsBorrowed",
            .consumes_arg => "ConsumesArg",
            .python_refcount_inc => "PythonRefcountInc",
            .python_refcount_dec => "PythonRefcountDec",
            .inout => "InOut",
            .unknown => "Unknown",
        };
    }
};

/// Information about a single FFI call site classified by an adapter.
pub const FFICallInfo = struct {
    inst_addr: u64,
    callee_name: []const u8,
    semantics: FFISemantics,
    confidence: f32,
    callee_language: Language,

    pub fn init(
        inst_addr: u64,
        callee_name: []const u8,
        semantics: FFISemantics,
        confidence: f32,
        callee_language: Language,
    ) FFICallInfo {
        return .{
            .inst_addr = inst_addr,
            .callee_name = callee_name,
            .semantics = semantics,
            .confidence = confidence,
            .callee_language = callee_language,
        };
    }
};

/// Result of running a language adapter on a single function.
pub const AdapterAnalysis = struct {
    language: Language,
    memory_model: MemoryModel,
    confidence: f32,
    ffi_calls: std.ArrayList(FFICallInfo),
    issues: std.ArrayList(AdapterIssue),
    allocator: std.mem.Allocator,

    // Reference count tracking (for Python/refcount languages)
    refcount_increments: u32 = 0,
    refcount_decrements: u32 = 0,
    refcount_balance: i32 = 0,

    // Leak detection
    has_potential_leak: bool = false,
    leak_severity: Severity = .low,

    // Analysis metadata
    is_analyzed: bool = false,

    pub fn init(alloc: std.mem.Allocator, lang: Language) !AdapterAnalysis {
        var result = AdapterAnalysis{
            .language = lang,
            .memory_model = MemoryModel.forLanguage(lang),
            .confidence = 0.0,
            .ffi_calls = undefined,
            .issues = undefined,
            .allocator = alloc,
        };
        result.ffi_calls = try std.ArrayList(FFICallInfo).initCapacity(alloc, 16);
        result.issues = try std.ArrayList(AdapterIssue).initCapacity(alloc, 8);
        return result;
    }

    pub fn deinit(self: *AdapterAnalysis) void {
        self.ffi_calls.deinit(self.allocator);
        for (self.issues.items) |issue| {
            if (issue.message.len > 0) {
                self.allocator.free(issue.message);
            }
        }
        self.issues.deinit(self.allocator);
    }

    pub fn addCall(self: *AdapterAnalysis, info: FFICallInfo) !void {
        try self.ffi_calls.append(self.allocator, info);
    }

    /// Add an issue detected during analysis.
    pub fn addIssue(self: *AdapterAnalysis, issue: AdapterIssue) !void {
        try self.issues.append(self.allocator, issue);
        // Update legacy flags for backward compatibility
        switch (issue.issue_type) {
            .memory_leak, .use_after_free, .borrowed_ref_error => {
                self.has_potential_leak = true;
                if (issue.severity == .critical or issue.severity == .high) {
                    self.leak_severity = issue.severity;
                }
            },
            else => {},
        }
    }

    /// Check if this analysis has any meaningful findings.
    pub fn hasFindings(self: AdapterAnalysis) bool {
        return self.ffi_calls.items.len > 0 or self.has_potential_leak or self.issues.items.len > 0;
    }
};

/// Severity levels for issue classification (re-exported from common/types).
///
/// This is a type-compatible mirror of common/types.Severity to avoid
/// circular module dependencies in the adapter framework.
pub const Severity = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    critical = 3,
};

/// Issue type classification for adapter-detected problems.
///
/// These map to specific memory safety bugs that can occur at FFI boundaries.
/// Each type has associated severity and confidence heuristics.
pub const AdapterIssueType = enum {
    /// Reference leak: owned reference never decremented (INC > DEC)
    memory_leak,
    /// Use-after-free or double-decref (DEC > INC)
    use_after_free,
    /// Python API called without holding GIL
    gil_violation,
    /// DECREF called on a borrowed reference (should INCREF first)
    borrowed_ref_error,
    /// Buffer protocol leak (GetBuffer without Release)
    buffer_leak,
    /// Null return value not checked after fallible call
    null_return_not_checked,
    /// Stale pointer used after interpreter finalization
    stale_interpreter_ptr,

    pub fn displayName(self: AdapterIssueType) []const u8 {
        return switch (self) {
            .memory_leak => "MemoryLeak",
            .use_after_free => "UseAfterFree",
            .gil_violation => "GILViolation",
            .borrowed_ref_error => "BorrowedRefError",
            .buffer_leak => "BufferLeak",
            .null_return_not_checked => "NullReturnNotChecked",
            .stale_interpreter_ptr => "StaleInterpreterPtr",
        };
    }

    pub fn defaultSeverity(self: AdapterIssueType) Severity {
        return switch (self) {
            .memory_leak => .high,
            .use_after_free => .critical,
            .gil_violation => .critical,
            .borrowed_ref_error => .high,
            .buffer_leak => .medium,
            .null_return_not_checked => .medium,
            .stale_interpreter_ptr => .high,
        };
    }

    /// Convert adapter issue type to canonical IssueKind for pipeline integration.
    pub fn toIssueKind(self: AdapterIssueType) @import("../common/types.zig").IssueKind {
        return switch (self) {
            .memory_leak => .memory_leak,
            .use_after_free => .use_after_free,
            .gil_violation => .ffi_unsafe_call,
            .borrowed_ref_error => .use_after_free,
            .buffer_leak => .memory_leak,
            .null_return_not_checked => .unchecked_return,
            .stale_interpreter_ptr => .use_after_free,
        };
    }
};

/// Location information for an adapter issue.
///
/// Provides context about where in the source code the issue was detected.
pub const IssueLocation = struct {
    function_name: []const u8 = "unknown",
    instruction_addr: u64 = 0,

    pub fn init(func_name: []const u8) IssueLocation {
        return .{
            .function_name = func_name,
            .instruction_addr = 0,
        };
    }

    pub fn initWithAddr(func_name: []const u8, addr: u64) IssueLocation {
        return .{
            .function_name = func_name,
            .instruction_addr = addr,
        };
    }
};

/// A single issue detected by a language adapter during FFI analysis.
///
/// Encapsulates all metadata needed to report a problem to the user:
/// - What type of problem was found
/// - Human-readable description
/// - Where it occurred
/// - How confident we are in the finding
/// - What evidence supports this conclusion
pub const AdapterIssue = struct {
    issue_type: AdapterIssueType,
    message: []const u8,
    location: IssueLocation,
    severity: Severity,
    confidence: f32,
    evidence: []const u8,

    pub fn deinit(self: *AdapterIssue, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.evidence);
    }
};

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "MemoryModel - displayName" {
    try std.testing.expectEqualStrings("Manual", MemoryModel.manual.displayName());
    try std.testing.expectEqualStrings("RAII", MemoryModel.raii.displayName());
    try std.testing.expectEqualStrings("RefCount", MemoryModel.refcount.displayName());
    try std.testing.expectEqualStrings("GC", MemoryModel.gc.displayName());
    try std.testing.expectEqualStrings("Hybrid", MemoryModel.hybrid.displayName());
}

test "MemoryModel - allowsLeak" {
    try std.testing.expect(MemoryModel.manual.allowsLeak());
    try std.testing.expect(MemoryModel.refcount.allowsLeak());
    try std.testing.expect(MemoryModel.hybrid.allowsLeak());
    try std.testing.expect(!MemoryModel.raii.allowsLeak());
    try std.testing.expect(!MemoryModel.gc.allowsLeak());
}

test "MemoryModel - forLanguage mapping" {
    try std.testing.expectEqual(.manual, MemoryModel.forLanguage(.c));
    try std.testing.expectEqual(.raii, MemoryModel.forLanguage(.cpp));
    try std.testing.expectEqual(.raii, MemoryModel.forLanguage(.rust));
    try std.testing.expectEqual(.raii, MemoryModel.forLanguage(.zig));
    try std.testing.expectEqual(.refcount, MemoryModel.forLanguage(.python));
    try std.testing.expectEqual(.hybrid, MemoryModel.forLanguage(.go));
    try std.testing.expectEqual(.hybrid, MemoryModel.forLanguage(.csharp));
    try std.testing.expectEqual(.gc, MemoryModel.forLanguage(.java));
}

test "FFISemantics - displayName" {
    try std.testing.expectEqualStrings("ReturnsOwned", FFISemantics.returns_owned.displayName());
    try std.testing.expectEqualStrings("ReturnsBorrowed", FFISemantics.returns_borrowed.displayName());
    try std.testing.expectEqualStrings("ConsumesArg", FFISemantics.consumes_arg.displayName());
    try std.testing.expectEqualStrings("InOut", FFISemantics.inout.displayName());
    try std.testing.expectEqualStrings("Unknown", FFISemantics.unknown.displayName());
}

test "FFICallInfo - init and fields" {
    const info = FFICallInfo.init(
        0x1000,
        "PyBytes_FromString",
        .returns_owned,
        0.95,
        .python,
    );
    try std.testing.expectEqual(@as(u64, 0x1000), info.inst_addr);
    try std.testing.expectEqualStrings("PyBytes_FromString", info.callee_name);
    try std.testing.expectEqual(FFISemantics.returns_owned, info.semantics);
    try std.testing.expect(info.confidence > 0.9);
    try std.testing.expectEqual(Language.python, info.callee_language);
}

test "AdapterAnalysis - init and lifecycle" {
    var analysis = try AdapterAnalysis.init(std.testing.allocator, .python);
    defer analysis.deinit();

    try std.testing.expectEqual(Language.python, analysis.language);
    try std.testing.expectEqual(MemoryModel.refcount, analysis.memory_model);
    try std.testing.expectEqual(@as(f32, 0.0), analysis.confidence);
    try std.testing.expectEqual(@as(usize, 0), analysis.ffi_calls.items.len);

    const info = FFICallInfo.init(1, "PyBytes_FromString", .returns_owned, 0.9, .python);
    try analysis.addCall(info);
    try std.testing.expectEqual(@as(usize, 1), analysis.ffi_calls.items.len);
}
