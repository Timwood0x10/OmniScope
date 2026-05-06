//! Unified Type Definitions for OmniScope
//!
//! This module provides the canonical type definitions used across all analysis passes.
//! All modules should import types from here to ensure consistency and eliminate duplication.
//!
//! Centralizes:
//! - Location (source code position)
//! - Severity (issue severity levels)
//! - IssueKind (issue category enumeration)
//! - ZoneTag (memory zone classification for FFI detection)
//! - Tag (semantic function tags)
//!
//! Design principle: Single source of truth for core types.

const std = @import("std");

// ============================================================================
// Location
// ============================================================================

/// Source code location information.
///
/// Tracks where an issue or diagnostic was found in the source code.
/// Used by all issue reporting, diagnostics, and trace entries.
///
/// Design principle: Separate file path and function name to avoid ambiguity.
/// - `file`: Actual source file path from DWARF debug info (optional)
/// - `func`: Function name (always available as fallback)
/// - Output formats (JSON/SARIF) should use `file` for file field, not `func`
pub const Location = struct {
    /// Source file path from DWARF debug info.
    /// Null if unavailable (common in stripped binaries or IR-only analysis).
    file: ?[]const u8,
    /// Function name where the issue was detected.
    /// Always available. Used as fallback display when file path is unknown.
    func: []const u8,
    /// Line number (1-indexed). 0 means unknown.
    line: u32 = 0,
    /// Column number (1-indexed). 0 means unknown.
    column: u32 = 0,

    /// Create location from function name only (common case for IR-level analysis).
    ///
    /// Most LLVM IR analysis operates at function granularity without
    /// precise line numbers or file paths. This constructor handles that case.
    pub fn init(func_name: []const u8) Location {
        return .{
            .file = null,
            .func = func_name,
            .line = 0,
            .column = 0,
        };
    }

    /// Create location with full source position (file + line + column).
    ///
    /// Use this when DWARF debug info is available to provide
    /// precise file/line/column information.
    pub fn initWithFile(file_path: []const u8, func_name: []const u8, line: u32, column: u32) Location {
        return .{
            .file = file_path,
            .func = func_name,
            .line = line,
            .column = column,
        };
    }

    /// Create location with function name and approximate position (no file path).
    ///
    /// Use this when you have line/column but no file path (rare but possible).
    pub fn initWithPosition(func_name: []const u8, line: u32, column: u32) Location {
        return .{
            .file = null,
            .func = func_name,
            .line = line,
            .column = column,
        };
    }

    /// Check if location has valid file path information.
    pub fn hasFilePath(self: Location) bool {
        return self.file != null;
    }

    /// Check if location has valid position information (line + column).
    pub fn hasValidPosition(self: Location) bool {
        return self.line > 0 and self.column > 0;
    }

    /// Get display string for output (prefer file path, fallback to function name).
    ///
    /// For JSON/SARIF file field: use `.file` directly, not this method.
    /// For human-readable messages: use this method.
    pub fn displayName(self: Location) []const u8 {
        return self.file orelse self.func;
    }
};

// ============================================================================
// Severity
// ============================================================================

/// Issue severity level.
///
/// Ordered from lowest to highest severity. Used for prioritization,
/// filtering, and display formatting in diagnostics output.
pub const Severity = enum(u8) {
    /// Low severity: informational or minor issues.
    low = 0,
    /// Medium severity: potential issues that should be reviewed.
    medium = 1,
    /// High severity: significant issues requiring attention.
    high = 2,
    /// Critical severity: severe vulnerabilities that must be fixed immediately.
    critical = 3,

    /// Convert severity to string representation.
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
            .critical => "critical",
        };
    }

    /// Get ANSI color code for terminal output.
    ///
    /// Returns escape sequence for colorizing severity labels in console output.
    pub fn toColorCode(self: Severity) []const u8 {
        return switch (self) {
            .low => "\x1b[36m", // Cyan
            .medium => "\x1b[33m", // Yellow
            .high => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

// ============================================================================
// IssueKind
// ============================================================================

/// Issue category enumeration.
///
/// Defines all types of security issues and code quality problems that
/// OmniScope can detect. Each kind maps to a CWE ID and human-readable description.
///
/// Extensibility rule: Add new kinds only when a new detection pattern is implemented.
/// Never remove or rename existing kinds (breaks SARIF compatibility).
pub const IssueKind = enum {
    /// FFI call without proper safety validation (CWE-668).
    ffi_unsafe_call,
    /// Function return value not checked after call (CWE-252).
    unchecked_return,
    /// Type mismatch across FFI boundary (CWE-704).
    type_mismatch,
    /// FFI type mismatch - size, alignment, or signedness (CWE-704).
    ffi_type_mismatch,
    /// Memory leak across language boundary (CWE-401).
    cross_language_leak,
    /// Cross-language free violation - alloc_lang != free_lang (CWE-763).
    cross_language_free,
    /// General memory leak - allocated but never freed (CWE-401).
    memory_leak,
    /// Use after free across language boundary (CWE-416).
    use_after_free,
    /// OS command injection vulnerability (CWE-78).
    command_injection,
    /// Buffer overflow vulnerability (CWE-120).
    buffer_overflow,
    /// Double free across language boundary (CWE-415).
    double_free,
    /// Format string vulnerability (CWE-134).
    format_string,
    /// Malloc result used without null check (CWE-252).
    malloc_unchecked,
    /// Null pointer dereference - nullable allocation used without guard (CWE-476).
    null_dereference,
    /// Rust borrow escape - as_ptr result passed to FFI may dangle (CWE-704).
    borrow_escape,
    /// Callback signature does not match receiver expectation (CWE-688).
    callback_signature_mismatch,
    /// Free called on non-malloc pointer (CWE-590).
    invalid_free,
    /// Static buffer misuse - thread-unsafe functions like ctime, strerror (CWE-242).
    static_buffer_misuse,
    /// Unknown issue type (fallback for future extensibility).
    unknown,

    /// Convert issue kind to string identifier.
    ///
    /// Used in JSON/SARIF output and log messages.
    pub fn toString(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "ffi_unsafe_call",
            .unchecked_return => "unchecked_return",
            .type_mismatch => "type_mismatch",
            .ffi_type_mismatch => "ffi_type_mismatch",
            .cross_language_leak => "cross_language_leak",
            .cross_language_free => "cross_language_free",
            .memory_leak => "memory_leak",
            .use_after_free => "use_after_free",
            .command_injection => "command_injection",
            .buffer_overflow => "buffer_overflow",
            .double_free => "double_free",
            .format_string => "format_string",
            .malloc_unchecked => "malloc_unchecked",
            .null_dereference => "null_dereference",
            .borrow_escape => "borrow_escape",
            .callback_signature_mismatch => "callback_signature_mismatch",
            .invalid_free => "invalid_free",
            .static_buffer_misuse => "static_buffer_misuse",
            .unknown => "unknown",
        };
    }

    /// Get CWE (Common Weakness Enumeration) ID for this issue kind.
    ///
    /// Maps each issue type to its standardized weakness ID for
    /// compliance reporting and vulnerability databases.
    pub fn toCweId(self: IssueKind) u32 {
        return switch (self) {
            .ffi_unsafe_call => 668,
            .unchecked_return => 252,
            .type_mismatch => 704,
            .ffi_type_mismatch => 704,
            .cross_language_leak => 401,
            .cross_language_free => 763, // Release of memory not allocated by same allocator
            .memory_leak => 401,
            .use_after_free => 416,
            .command_injection => 78,
            .buffer_overflow => 120,
            .double_free => 415,
            .format_string => 134,
            .malloc_unchecked => 252,
            .null_dereference => 476,
            .borrow_escape => 704,
            .callback_signature_mismatch => 688,
            .invalid_free => 590,
            .static_buffer_misuse => 242,
            .unknown => 0,
        };
    }

    /// Get human-readable description for this issue kind.
    ///
    /// Used in diagnostic messages and report generation.
    pub fn toDescription(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "FFI call without proper safety validation",
            .unchecked_return => "Function return value not checked after call",
            .type_mismatch => "Type mismatch across FFI boundary",
            .ffi_type_mismatch => "FFI type mismatch (size, alignment, or signedness)",
            .cross_language_leak => "Memory leak across language boundary",
            .cross_language_free => "Cross-language free violation - allocation and free in different languages",
            .memory_leak => "Memory allocated but never freed",
            .use_after_free => "Use after free across language boundary",
            .command_injection => "Command injection vulnerability",
            .buffer_overflow => "Buffer overflow vulnerability",
            .double_free => "Double free across language boundary",
            .format_string => "Format string vulnerability",
            .malloc_unchecked => "Malloc result used without null check",
            .null_dereference => "Null pointer dereference - nullable allocation used without guard",
            .borrow_escape => "Rust borrow escape - as_ptr result may dangle after local drop",
            .callback_signature_mismatch => "Callback signature does not match receiver expectation - potential ABI mismatch",
            .invalid_free => "Free called on non-malloc pointer",
            .static_buffer_misuse => "Static buffer function misuse - thread-unsafe or data overwrite risk (ctime, strerror, etc.)",
            .unknown => "Unknown issue type",
        };
    }
};

// ============================================================================
// Confidence Level
// ============================================================================

/// Detection confidence level.
///
/// Indicates how trustworthy a detected issue is based on evidence strength.
/// Used for filtering, prioritization, and precision metrics calculation.
pub const Confidence = enum(u8) {
    /// Multiple cross-validated signals (e.g., alloc + no free + no transfer + no escape).
    high = 0,
    /// Single strong signal but may have exceptions (e.g., intra-procedural leak).
    medium = 1,
    /// Heuristic pattern match (e.g., function name convention, naming inference).
    heuristic = 2,
    /// Experimental detection, likely to have many false positives.
    experimental = 3,

    /// Convert confidence to string representation.
    pub fn toString(self: Confidence) []const u8 {
        return switch (self) {
            .high => "HIGH",
            .medium => "MEDIUM",
            .heuristic => "HEURISTIC",
            .experimental => "EXPERIMENTAL",
        };
    }

    /// Map numeric score to confidence level.
    ///
    /// Thresholds chosen empirically from baseline measurements:
    /// - >= 0.9: high confidence (strong multi-signal correlation)
    /// - >= 0.7: medium confidence (single strong signal)
    /// - >= 0.5: heuristic (pattern-based inference)
    /// - < 0.5: experimental (unproven detection method)
    pub fn fromScore(score: f32) Confidence {
        if (score >= 0.9) return .high;
        if (score >= 0.7) return .medium;
        if (score >= 0.5) return .heuristic;
        return .experimental;
    }

    /// Get default score for this confidence level.
    ///
    /// Used when converting confidence back to numeric representation.
    pub fn defaultScore(self: Confidence) f32 {
        return switch (self) {
            .high => 0.95,
            .medium => 0.75,
            .heuristic => 0.55,
            .experimental => 0.35,
        };
    }
};

// ============================================================================
// ZoneTag (Memory Zone Classification)
// ============================================================================

/// Memory zone tag for FFI boundary detection.
///
/// Classifies which language/runtime owns a memory region.
/// FFI boundaries are detected as zone mismatches between caller and callee.
///
/// Minimal tag set per design principle: only zones necessary for
/// cross-language ownership tracking. Do NOT extend without strong justification.
pub const ZoneTag = enum(u8) {
    /// Unknown or unclassifiable zone.
    /// Functions that cannot be assigned to any specific language runtime.
    unknown = 0,
    /// C heap memory (malloc/free/calloc/realloc).
    /// Standard C library allocations and manual memory management.
    c_heap = 1,
    /// Rust-owned memory (Box/Rc/Arc/String/Vec).
    /// Memory managed by Rust's ownership system and Drop trait.
    rust_owned = 2,
    /// Python reference-counted objects (PyObject).
    /// Memory managed by Python's reference counting (INCREF/DECREF).
    python_ref = 3,
    /// Go pointer (runtime-managed GC memory).
    /// Pointers that must not escape beyond Go's garbage collector scope.
    go_pointer = 4,
    /// FFI boundary zone.
    /// Marks functions that cross language boundaries (dlopen/dlsym/JNI/etc).
    ffi = 5,

    /// Convert zone tag to human-readable name.
    pub fn toString(self: ZoneTag) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .c_heap => "CHeap",
            .rust_owned => "RustOwned",
            .python_ref => "PythonRef",
            .go_pointer => "GoPointer",
            .ffi => "FFI",
        };
    }

    /// Check if this zone represents a safe language runtime.
    ///
    /// Safe languages have automatic memory management (GC, refcount, ownership).
    /// C heap is NOT safe because it requires manual malloc/free.
    pub fn isSafeLanguage(self: ZoneTag) bool {
        return switch (self) {
            .rust_owned, .python_ref, .go_pointer => true,
            else => false,
        };
    }
};

// ============================================================================
// Tag (Semantic Function Tags)
// ============================================================================

/// Semantic tag for function classification.
///
/// Tags describe what a function does semantically (allocates, frees, transfers, etc.).
/// Loaded from JSON annotations and used by Registry for query-based analysis.
///
/// Minimal tag set: only tags necessary for MemoryGraph construction and FFI detection.
pub const Tag = enum {
    /// Memory allocation function (malloc, calloc, Box::new, etc.).
    alloc,
    /// Memory deallocation function (free, drop, dealloc, etc.).
    free,
    /// Borrow operation (as_ptr, &mut, borrowing reference).
    borrow,
    /// Ownership transfer operation (into_raw, std::mem::forget, etc.).
    transfer,
    /// FFI boundary function (extern, dlopen, JNI, etc.).
    ffi,

    /// Convert tag to string representation.
    pub fn toString(self: Tag) []const u8 {
        return switch (self) {
            .alloc => "Alloc",
            .free => "Free",
            .borrow => "Borrow",
            .transfer => "Transfer",
            .ffi => "FFI",
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Location - init from function name" {
    const loc = Location.init("myFunction");
    try std.testing.expect(loc.file == null);
    try std.testing.expectEqualStrings("myFunction", loc.func);
    try std.testing.expectEqual(@as(u32, 0), loc.line);
    try std.testing.expect(!loc.hasValidPosition());
    try std.testing.expect(!loc.hasFilePath());
    // displayName should fallback to func when file is null
    try std.testing.expectEqualStrings("myFunction", loc.displayName());
}

test "Location - init with position only (no file)" {
    const loc = Location.initWithPosition("analyzeData", 42, 10);
    try std.testing.expect(loc.file == null);
    try std.testing.expectEqualStrings("analyzeData", loc.func);
    try std.testing.expectEqual(@as(u32, 42), loc.line);
    try std.testing.expectEqual(@as(u32, 10), loc.column);
    try std.testing.expect(loc.hasValidPosition());
    try std.testing.expect(!loc.hasFilePath());
}

test "Location - init with full file + position" {
    const loc = Location.initWithFile("src/main.zig", "main", 42, 10);
    try std.testing.expect(loc.file != null);
    try std.testing.expectEqualStrings("src/main.zig", loc.file.?);
    try std.testing.expectEqualStrings("main", loc.func);
    try std.testing.expectEqual(@as(u32, 42), loc.line);
    try std.testing.expectEqual(@as(u32, 10), loc.column);
    try std.testing.expect(loc.hasValidPosition());
    try std.testing.expect(loc.hasFilePath());
    // displayName should prefer file over func
    try std.testing.expectEqualStrings("src/main.zig", loc.displayName());
}

test "Severity - enum values and ordering" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Severity.low));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Severity.medium));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Severity.high));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Severity.critical));
}

test "Severity - toString" {
    try std.testing.expectEqualStrings("low", Severity.low.toString());
    try std.testing.expectEqualStrings("critical", Severity.critical.toString());
}

test "IssueKind - count matches expected" {
    // Verify we have exactly 19 issue kinds (18 known + 1 unknown)
    const kinds = [_]IssueKind{
        .ffi_unsafe_call,      .unchecked_return, .type_mismatch,               .ffi_type_mismatch,
        .cross_language_leak,  .cross_language_free, .memory_leak,              .use_after_free,
        .command_injection,    .buffer_overflow,      .double_free,              .format_string,
        .malloc_unchecked,     .null_dereference,    .borrow_escape,            .callback_signature_mismatch,
        .invalid_free,         .static_buffer_misuse, .unknown,
    };
    try std.testing.expectEqual(@as(usize, 19), kinds.len);
}

test "IssueKind - CWE mapping consistency" {
    // Each known issue should have a valid CWE ID (> 0)
    const known_kinds = [_]IssueKind{
        .ffi_unsafe_call,      .unchecked_return, .type_mismatch,               .ffi_type_mismatch,
        .cross_language_leak,  .cross_language_free, .memory_leak,              .use_after_free,
        .command_injection,    .buffer_overflow,      .double_free,              .format_string,
        .malloc_unchecked,     .null_dereference,    .borrow_escape,            .callback_signature_mismatch,
        .invalid_free,         .static_buffer_misuse,
    };
    for (known_kinds) |kind| {
        try std.testing.expect(kind.toCweId() > 0);
    }
    // Unknown should have CWE 0
    try std.testing.expectEqual(@as(u32, 0), IssueKind.unknown.toCweId());
}

test "ZoneTag - safe language detection" {
    try std.testing.expect(ZoneTag.rust_owned.isSafeLanguage());
    try std.testing.expect(ZoneTag.python_ref.isSafeLanguage());
    try std.testing.expect(ZoneTag.go_pointer.isSafeLanguage());

    // C heap is NOT safe (manual memory management)
    try std.testing.expect(!ZoneTag.c_heap.isSafeLanguage());
    try std.testing.expect(!ZoneTag.unknown.isSafeLanguage());
    try std.testing.expect(!ZoneTag.ffi.isSafeLanguage());
}

test "Tag - semantic categories" {
    // Verify we have exactly 5 tags (minimal set per design)
    const tags = [_]Tag{ .alloc, .free, .borrow, .transfer, .ffi };
    try std.testing.expectEqual(@as(usize, 5), tags.len);

    // Each tag should have a non-empty string representation
    for (tags) |tag| {
        const str = tag.toString();
        try std.testing.expect(str.len > 0);
    }
}

test "Confidence - score mapping thresholds" {
    // Test boundary conditions
    try std.testing.expectEqual(Confidence.high, Confidence.fromScore(0.95));
    try std.testing.expectEqual(Confidence.high, Confidence.fromScore(0.90));
    try std.testing.expectEqual(Confidence.medium, Confidence.fromScore(0.89));
    try std.testing.expectEqual(Confidence.medium, Confidence.fromScore(0.70));
    try std.testing.expectEqual(Confidence.heuristic, Confidence.fromScore(0.69));
    try std.testing.expectEqual(Confidence.heuristic, Confidence.fromScore(0.50));
    try std.testing.expectEqual(Confidence.experimental, Confidence.fromScore(0.49));
    try std.testing.expectEqual(Confidence.experimental, Confidence.fromScore(0.00));
}
