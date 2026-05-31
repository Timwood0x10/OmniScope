//! Unified interface for language-specific FFI analysis adapters.
//!
//! Each language adapter implements this interface (via the VTable pattern) to
//! provide language-specific semantic knowledge to the core analysis engine.
//! The adapter framework follows a "thin adapter layer + thick core engine"
//! architecture: adapters are ~200 LOC per language and only map language
//! idioms to the unified FFISemantics enum.
//!
//! ## Design Pattern
//!
//! Zig does not have interfaces/traits, so we use a VTable (function pointer
//! struct) pattern. Each adapter provides:
//!
//!   1. **Static metadata** (name, language, memory_model) — zero-cost dispatch
//!   2. **VTable** (fn pointers for analyzeFunction, classifyCall, etc.)
//!   3. **Pattern tables** (owning/borrowing/consuming function name lists)
//!
//! ## Integration Point
//!
//! Adapters are registered in AdapterRegistry and selected either:
//!   - Automatically via `detectAdapter()` (module-level heuristics)
//!   - Manually via `getAdapter(language)` (user-specified)
//!
//! The PassManager calls `adapter.analyzeFunction()` during its FFI analysis
//! phase, and the results feed into MemoryGraph construction.

const std = @import("std");
const types = @import("types.zig");
const Language = types.Language;
const MemoryModel = types.MemoryModel;
const FFISemantics = types.FFISemantics;
const AdapterAnalysis = types.AdapterAnalysis;
const FFICallInfo = types.FFICallInfo;

/// Opaque context pointer type passed to adapter methods.
///
/// In production this is typically *PassContext or *AnalysisContext,
/// carrying allocator, module reference, and configuration.
pub const ContextPtr = *anyopaque;

/// VTable of function pointers that every language adapter must implement.
///
/// This is the "interface" that all concrete adapters satisfy. Methods that
/// are not meaningful for a particular language can return sensible defaults
/// (e.g., classifyCall returning .unknown).
pub const AdapterVTable = struct {
    /// Analyze an LLVM function's FFI calls and return classified results.
    ///
    /// This is the primary entry point called by the analysis pipeline.
    /// The implementation should iterate over call instructions in `func`,
    /// classify each FFI boundary call using language-specific knowledge,
    /// and populate the returned AdapterAnalysis with FFICallInfo entries.
    ///
    /// Parameters:
    ///   - self: The adapter instance
    ///   - func: LLVM function value to analyze
    ///   - ctx: Opaque context (cast to concrete type as needed)
    ///   - allocator: Allocator for result storage
    ///
    /// Returns:
    ///   - AdapterAnalysis with classified FFI calls (caller owns memory)
    const AnalyzeFn = *const fn (
        self: *const LanguageAdapter,
        func: *anyopaque,
        ctx: ContextPtr,
        allocator: std.mem.Allocator,
    ) anyerror!AdapterAnalysis;

    /// Classify the semantics of a single FFI call by callee name.
    ///
    /// Lightweight classification used when full LLVM IR analysis is not
    /// available (e.g., call-graph-only mode). Returns the most likely
    /// semantics based on function name pattern matching.
    ///
    /// Parameters:
    ///   - self: The adapter instance
    ///   - callee_name: Name of the called function
    ///
    /// Returns:
    ///   - Classified FFISemantics (.unknown if unrecognized)
    const ClassifyFn = *const fn (
        self: *const LanguageAdapter,
        callee_name: []const u8,
    ) FFISemantics;

    /// Check if a function should be suppressed from analysis entirely.
    ///
    /// Internal/runtime functions that are never real FFI boundaries
    /// (e.g., Go runtime.morestack, Python internal GC functions) should
    /// return true here so the analyzer skips them.
    ///
    /// Parameters:
    ///   - self: The adapter instance
    ///   - func_name: Name of the function to check
    ///
    /// Returns:
    ///   - true if the function should be suppressed
    const SuppressFn = *const fn (
        self: *const LanguageAdapter,
        func_name: []const u8,
    ) bool;

    /// Get list of function name patterns that return OWNED references.
    ///
    /// Used by the registry for fast prefix/pattern matching without
    /// calling into the full VTable. Each string is a function name
    /// or prefix that indicates ownership transfer to the caller.
    ///
    /// Returns:
    ///   - Slice of owning pattern strings (static lifetime)
    const OwningPatternsFn = *const fn (
        self: *const LanguageAdapter,
    ) []const []const u8;

    /// Get list of function name patterns that return BORROWED references.
    ///
    /// Complement to getOwningPatterns — these functions return references
    /// that the caller must NOT free/DECREF.
    ///
    /// Returns:
    ///   - Slice of borrowing pattern strings (static lifetime)
    const BorrowingPatternsFn = *const fn (
        self: *const LanguageAdapter,
    ) []const []const u8;

    /// Function pointers (filled in by each adapter implementation).
    analyzeFn: AnalyzeFn,
    classifyFn: ClassifyFn,
    suppressFn: SuppressFn,
    owningPatternsFn: OwningPatternsFn,
    borrowingPatternsFn: BorrowingPatternsFn,
};

/// Language adapter instance — the concrete struct registered with the registry.
///
/// Combines static metadata (name, target language, memory model) with a VTable
/// of function pointers that implement language-specific logic. Created once per
/// language and reused across all analyses (stateless design).
pub const LanguageAdapter = struct {
    /// Human-readable adapter name (e.g., "python", "go", "cpp").
    name: []const u8,
    /// Target language this adapter handles.
    language: Language,
    /// Memory model of the target language.
    memory_model: MemoryModel,
    /// VTable of language-specific implementations.
    vtable: AdapterVTable,

    /// Delegate analyzeFunction to the VTable.
    pub fn analyzeFunction(
        self: *const LanguageAdapter,
        func: *anyopaque,
        ctx: ContextPtr,
        allocator: std.mem.Allocator,
    ) !AdapterAnalysis {
        return self.vtable.analyzeFn(self, func, ctx, allocator);
    }

    /// Delegate classifyCall to the VTable.
    pub fn classifyCall(
        self: *const LanguageAdapter,
        callee_name: []const u8,
    ) FFISemantics {
        return self.vtable.classifyFn(self, callee_name);
    }

    /// Delegate shouldSuppress to the VTable.
    pub fn shouldSuppress(
        self: *const LanguageAdapter,
        func_name: []const u8,
    ) bool {
        return self.vtable.suppressFn(self, func_name);
    }

    /// Delegate getOwningPatterns to the VTable.
    pub fn getOwningPatterns(self: *const LanguageAdapter) []const []const u8 {
        return self.vtable.owningPatternsFn(self);
    }

    /// Delegate getBorrowingPatterns to the VTable.
    pub fn getBorrowingPatterns(self: *const LanguageAdapter) []const []const u8 {
        return self.vtable.borrowingPatternsFn(self);
    }

    /// Check if this adapter handles the given language.
    pub fn supportsLanguage(self: *const LanguageAdapter, lang: Language) bool {
        return self.language == lang;
    }
};

/// Default no-op adapter implementations.
///
/// These provide safe defaults for adapters that don't need to override
/// every VTable slot. Used by simple adapters that only implement classifyCall.
pub const Defaults = struct {
    /// Default analyzeFunction: returns empty analysis with basic metadata.
    pub fn defaultAnalyze(
        self_ptr: *const LanguageAdapter,
        func_opaque: *anyopaque,
        ctx: ContextPtr,
        allocator: std.mem.Allocator,
    ) anyerror!AdapterAnalysis {
        _ = func_opaque;
        _ = ctx;
        var result = try AdapterAnalysis.init(allocator, self_ptr.language);
        result.confidence = 0.0;
        return result;
    }

    /// Default classifyCall: returns .unknown (conservative).
    pub fn defaultClassify(
        self_ptr: *const LanguageAdapter,
        callee_name: []const u8,
    ) FFISemantics {
        _ = self_ptr;
        _ = callee_name;
        return .unknown;
    }

    /// Default shouldSuppress: never suppress (analyze everything).
    pub fn defaultSuppress(
        self_ptr: *const LanguageAdapter,
        func_name: []const u8,
    ) bool {
        _ = self_ptr;
        _ = func_name;
        return false;
    }

    /// Default getOwningPatterns: empty list.
    pub fn defaultOwningPatterns(
        self_ptr: *const LanguageAdapter,
    ) []const []const u8 {
        _ = self_ptr;
        return &[_][]const u8{};
    }

    /// Default getBorrowingPatterns: empty list.
    pub fn defaultBorrowingPatterns(
        self_ptr: *const LanguageAdapter,
    ) []const []const u8 {
        _ = self_ptr;
        return &[_][]const u8{};
    }

    /// Build a complete VTable filled with default implementations.
    /// Override individual fields after calling this to customize.
    pub fn makeDefaultVTable() AdapterVTable {
        return .{
            .analyzeFn = defaultAnalyze,
            .classifyFn = defaultClassify,
            .suppressFn = defaultSuppress,
            .owningPatternsFn = defaultOwningPatterns,
            .borrowingPatternsFn = defaultBorrowingPatterns,
        };
    }
};

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "Defaults - defaultClassify returns unknown" {
    // Create a minimal adapter with default VTable
    const adapter = LanguageAdapter{
        .name = "test",
        .language = .c,
        .memory_model = .manual,
        .vtable = Defaults.makeDefaultVTable(),
    };

    try std.testing.expectEqual(FFISemantics.unknown, adapter.classifyCall("malloc"));
    try std.testing.expectEqual(FFISemantics.unknown, adapter.classifyCall("anything"));
}

test "Defaults - defaultSuppress returns false" {
    const adapter = LanguageAdapter{
        .name = "test",
        .language = .c,
        .memory_model = .manual,
        .vtable = Defaults.makeDefaultVTable(),
    };

    try std.testing.expect(!adapter.shouldSuppress("runtime.internal"));
    try std.testing.expect(!adapter.shouldSuppress(""));
}

test "Defaults - defaultPatterns return empty" {
    const adapter = LanguageAdapter{
        .name = "test",
        .language = .c,
        .memory_model = .manual,
        .vtable = Defaults.makeDefaultVTable(),
    };

    try std.testing.expectEqual(@as(usize, 0), adapter.getOwningPatterns().len);
    try std.testing.expectEqual(@as(usize, 0), adapter.getBorrowingPatterns().len);
}

test "LanguageAdapter - supportsLanguage check" {
    const adapter = LanguageAdapter{
        .name = "python_test",
        .language = .python,
        .memory_model = .refcount,
        .vtable = Defaults.makeDefaultVTable(),
    };

    try std.testing.expect(adapter.supportsLanguage(.python));
    try std.testing.expect(!adapter.supportsLanguage(.go));
    try std.testing.expect(!adapter.supportsLanguage(.rust));
}

test "Defaults - defaultAnalyze produces valid result" {
    const adapter = LanguageAdapter{
        .name = "test",
        .language = .python,
        .memory_model = .refcount,
        .vtable = Defaults.makeDefaultVTable(),
    };

    var result = try adapter.analyzeFunction(undefined, undefined, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(Language.python, result.language);
    try std.testing.expectEqual(MemoryModel.refcount, result.memory_model);
    try std.testing.expectEqual(@as(f32, 0.0), result.confidence);
    try std.testing.expectEqual(@as(usize, 0), result.ffi_calls.items.len);
}
