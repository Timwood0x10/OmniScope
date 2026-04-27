//! Cross-Language Noise Reduction Engine - Layer 1: Name-based Filter
//!
//! Distinguishes user code from compiler-generated/runtime code
//! by analyzing function name patterns.
//!
//! This is the fastest filter layer with medium accuracy.
//! Use as first-pass before more expensive analysis layers.
//!
//! Reference: plan/lang_ffi_analysis/plan.md - Layer 1: Name-based Filter

const std = @import("std");

/// Origin classification for functions.
/// Determines whether a function should be analyzed or suppressed.
/// This is the canonical FunctionOrigin definition used across all noise reduction layers.
pub const FunctionOrigin = enum(u8) {
    /// User-defined code - high priority for analysis.
    user,

    /// Standard library / runtime internal code - suppress by default.
    stdlib,

    /// Compiler-generated glue code (drop glue, shims, etc.) - ignore.
    compiler_generated,

    /// Third-party library code - analyze but lower priority.
    third_party,

    /// Unknown origin - needs further classification.
    unknown,

    pub fn toString(self: FunctionOrigin) []const u8 {
        return switch (self) {
            .user => "USER",
            .stdlib => "STDLIB",
            .compiler_generated => "COMPILER_GEN",
            .third_party => "THIRD_PARTY",
            .unknown => "UNKNOWN",
        };
    }

    /// Should issues from this origin be reported by default?
    pub fn shouldReportByDefault(self: FunctionOrigin) bool {
        return switch (self) {
            .user => true,
            .stdlib => false,
            .compiler_generated => false,
            .third_party => true,
            .unknown => true,
        };
    }
};

/// Risk level for issues based on function origin and issue type.
/// This is the canonical RiskLevel definition used across all noise reduction layers.
pub const RiskLevel = enum(u8) {
    /// Critical - must fix immediately (FFI boundary bugs).
    critical,

    /// High - should fix soon (user unsafe code).
    high,

    /// Medium - investigate when possible.
    medium,

    /// Low - informational only.
    low,

    /// Suppressed - not worth reporting (stdlib noise).
    suppressed,

    pub fn toString(self: RiskLevel) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW",
            .suppressed => "SUPPRESSED",
        };
    }

    /// Check if this risk level meets a minimum threshold.
    /// Note: lower enum value = higher priority (critical=0 < high=1 < ... < suppressed=4)
    pub fn meetsThreshold(self: RiskLevel, min: RiskLevel) bool {
        return @intFromEnum(self) <= @intFromEnum(min);
    }
};

/// Classification result with origin and risk level.
pub const ClassificationResult = struct {
    origin: FunctionOrigin,
    risk_level: RiskLevel,
    reason: []const u8,
};

// ============================================================================
// Rust Name Patterns
// ============================================================================

/// Rust standard library prefixes to skip.
/// These are compiler-generated or runtime-internal patterns.
const RUST_STDLIB_PREFIXES = [_][]const u8{
    // Core library
    "_ZN4core",
    "_ZN5alloc",
    "_ZN3std",

    // Compiler-generated patterns
    "__rust_",
    "_RNv", // Rust name versioning
    "$LT$core", // Generic core types
    "$LT$alloc", // Generic alloc types
    "$LT$std", // Generic std types
};

/// Rust standard library substrings to skip.
const RUST_STDLIB_SUBSTRINGS = [_][]const u8{
    "core::ptr::drop_in_place",
    "core::panicking::begin_panic",
    "alloc::raw_vec::RawVec",
    "panic_",
    "<alloc::vec::Vec",
    "<core::slice",
    "::fmt::",
};

/// Rust compiler-generated function patterns.
const RUST_COMPILER_PATTERNS = [_][]const u8{
    // Drop glue
    "drop_in_place",

    // Panic infrastructure
    "begin_panic",
    "panic_fmt",

    // Monomorphization artifacts
    "$LT$",
    "$GT$",
    "$u20$",
    "$C$",

    // Shims
    "_ZN17alloc", // alloc internals
    "_ZN4core", // core internals
};

// ============================================================================
// Zig Name Patterns
// ============================================================================

/// Zig standard library prefixes to skip.
const ZIG_STDLIB_PREFIXES = [_][]const u8{
    "std.",
    "zig.",
};

/// Zig standard library substrings to skip.
const ZIG_STDLIB_SUBSTRINGS = [_][]const u8{
    "std.mem.Allocator",
    "std.ArrayList",
    "std.StringArrayHashMap",
    "std.AutoHashMap",
    "std.fmt.allocPrint",
    "std.heap.GeneralPurposeAllocator",
    "array_list",
    "hash_map",
    "start.zig",
    "panic.zig",
};

/// Zig compiler-generated patterns.
const ZIG_COMPILER_PATTERNS = [_][]const u8{
    // Allocator wrappers
    "GeneralPurposeAllocator",

    // Runtime
    "zig_start",
    "__zig_launch",
};

// ============================================================================
// C++ Name Patterns
// ============================================================================

/// C++ standard library prefixes to skip.
const CPP_STDLIB_PREFIXES = [_][]const u8{
    "std::__",
    "__gnu_cxx",
    "__cxa_",
};

/// C++ standard library substrings to skip.
const CPP_STDLIB_SUBSTRINGS = [_][]const u8{
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_throw",
    "std::_Function_handler",
    "std::_Bind_back",
};

/// C++ compiler-generated patterns.
const CPP_COMPILER_PATTERNS = [_][]const u8{
    "__clang_call_terminate",
    "_ZSt", // std template instantiations
    "_ZNSt", // std namespace mangled
};

// ============================================================================
// Go Name Patterns
// ============================================================================

/// Go runtime/cgo prefixes to skip.
const GO_RUNTIME_PREFIXES = [_][]const u8{
    "runtime.",
    "internal/",
};

/// Go cgo generated patterns to skip.
const GO_CGO_PATTERNS = [_][]const u8{
    "_Cfunc_",
    "_cgo_",
    "_cgo_gotypes",
};

/// Go compiler-generated patterns.
const GO_COMPILER_PATTERNS = [_][]const u8{
    "init.",
    "gcWriteBarrier",
    "writeBarrier",
};

// ============================================================================
// Public API
// ============================================================================

/// Classify a function's origin based on its name.
///
/// Arguments:
///   func_name - The LLVM IR function name to classify
///   lang - Optional source language hint
///
/// Returns:
///   ClassificationResult with origin, risk level, and reason
pub fn classifyFunction(func_name: []const u8, lang: ?Language) ClassificationResult {
    if (func_name.len == 0) {
        return .{
            .origin = .unknown,
            .risk_level = .medium,
            .reason = "empty function name",
        };
    }

    // Check for LLVM intrinsics first (language-agnostic)
    if (isLLVMIntrinsic(func_name)) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "LLVM intrinsic",
        };
    }

    // Language-specific classification
    if (lang) |l| {
        return switch (l) {
            .rust => classifyRustFunction(func_name),
            .zig => classifyZigFunction(func_name),
            .go => classifyGoFunction(func_name),
            .cpp, .c => classifyCppFunction(func_name),
            else => defaultClassification(func_name),
        };
    }

    // Auto-detect language from patterns
    if (isRustMangledName(func_name)) {
        return classifyRustFunction(func_name);
    }
    if (isZigFunction(func_name)) {
        return classifyZigFunction(func_name);
    }
    if (isGoFunction(func_name)) {
        return classifyGoFunction(func_name);
    }
    if (isCppMangledName(func_name)) {
        return classifyCppFunction(func_name);
    }

    return defaultClassification(func_name);
}

/// Get effective risk level based on origin and issue severity.
///
/// This implements the risk weighting system:
/// - user + dangerous sink = HIGH/CRITICAL
/// - stdlib + leak = SUPPRESSED
/// - compiler_generated + anything = SUPPRESS/IGNORE
pub fn getRiskLevel(origin: FunctionOrigin, base_severity: Severity) RiskLevel {
    return switch (origin) {
        .compiler_generated => switch (base_severity) {
            .critical, .high => .suppressed,
            .medium, .low => .suppressed,
        },
        .stdlib => switch (base_severity) {
            .critical => .low,
            .high => .low,
            .medium => .suppressed,
            .low => .suppressed,
        },
        .third_party => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
        .user => switch (base_severity) {
            .critical => .critical,
            .high => .high,
            .medium => .medium,
            .low => .low,
        },
        .unknown => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
    };
}

/// Source language for classification.
pub const Language = enum(u8) {
    rust,
    zig,
    go,
    c,
    cpp,
    unknown,
};

/// Issue severity levels (before risk weighting).
pub const Severity = enum(u8) {
    critical,
    high,
    medium,
    low,
};

// ============================================================================
// Language-Specific Classification Functions
// ============================================================================

/// Classify a Rust function by name patterns.
fn classifyRustFunction(func_name: []const u8) ClassificationResult {
    // Check stdlib prefixes FIRST (more specific than compiler patterns)
    for (RUST_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust standard library",
            };
        }
    }

    // Check stdlib substrings
    for (RUST_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust standard library",
            };
        }
    }

    // Check compiler-generated patterns (after stdlib)
    for (RUST_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Rust compiler-generated code",
            };
        }
    }

    // Check for __rust_ prefix (compiler internal)
    if (std.mem.startsWith(u8, func_name, "__rust_")) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "Rust compiler internal",
        };
    }

    // Check for FFI-related patterns (extern C, libc calls)
    if (isExternCPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Rust extern C boundary",
        };
    }

    // Default: user code (mangled Rust function)
    if (isRustMangledName(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .medium,
            .reason = "Rust user code",
        };
    }

    return defaultClassification(func_name);
}

/// Classify a Zig function by name patterns.
fn classifyZigFunction(func_name: []const u8) ClassificationResult {
    // Check compiler-generated patterns
    for (ZIG_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Zig compiler-generated code",
            };
        }
    }

    // Check stdlib prefixes
    for (ZIG_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            // Allow certain safe stdlib patterns that users commonly use
            if (!isSafeStdlibPattern(func_name)) {
                return .{
                    .origin = .stdlib,
                    .risk_level = .low,
                    .reason = "Zig standard library",
                };
            }
        }
    }

    // Check stdlib substrings
    for (ZIG_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Zig standard library",
            };
        }
    }

    // Check for FFI patterns (@cImport, extern)
    if (isZigFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Zig FFI boundary",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Zig user code",
    };
}

/// Classify a Go function by name patterns.
fn classifyGoFunction(func_name: []const u8) ClassificationResult {
    // Check cgo generated patterns
    for (GO_CGO_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Go cgo generated code",
            };
        }
    }

    // Check compiler-generated patterns
    for (GO_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Go compiler-generated code",
            };
        }
    }

    // Check runtime prefixes
    for (GO_RUNTIME_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Go runtime",
            };
        }
    }

    // Check for cgo patterns in user code
    if (isGoFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Go cgo boundary",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Go user code",
    };
}

/// Classify a C++ function by name patterns.
fn classifyCppFunction(func_name: []const u8) ClassificationResult {
    // Check stdlib prefixes FIRST
    for (CPP_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "C++ standard library",
            };
        }
    }

    // Check stdlib substrings (includes _ZSt pattern)
    for (CPP_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "C++ standard library",
            };
        }
    }

    // Check _ZSt pattern (std template instantiations) as stdlib
    if (std.mem.startsWith(u8, func_name, "_ZSt")) {
        return .{
            .origin = .stdlib,
            .risk_level = .low,
            .reason = "C++ standard library template",
        };
    }

    // Check _ZNSt pattern (std namespace mangled) as stdlib
    if (std.mem.startsWith(u8, func_name, "_ZNSt")) {
        return .{
            .origin = .stdlib,
            .risk_level = .low,
            .reason = "C++ standard library",
        };
    }

    // Check compiler-generated patterns
    for (CPP_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "C++ compiler-generated code",
            };
        }
    }

    // Check for extern C patterns
    if (isExternCPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ extern C boundary",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "C++ user code",
    };
}

/// Default classification for unrecognized patterns.
fn defaultClassification(func_name: []const u8) ClassificationResult {
    // Heuristic: very long names are likely compiler-generated
    if (func_name.len > 100) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "long name suggests compiler-generated",
        };
    }

    // Heuristic: names starting with _ are often internal
    if (func_name.len > 0 and func_name[0] == '_') {
        return .{
            .origin = .third_party,
            .risk_level = .medium,
            .reason = "underscore prefix, possibly library code",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "unrecognized pattern, assuming user code",
    };
}

// ============================================================================
// Helper Detection Functions
// ============================================================================

/// Check if name matches LLVM intrinsic pattern.
fn isLLVMIntrinsic(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "llvm.")) return true;
    if (std.mem.startsWith(u8, name, "llvm.")) return true;
    return false;
}

/// Check if name looks like a Rust-mangled function (_ZN...).
fn isRustMangledName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "_ZN");
}

/// Check if name looks like a C++-mangled function (_Z...).
fn isCppMangledName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "_Z")) return false;
    // Exclude Rust mangled names which start with _ZN
    if (name.len > 2 and name[1] == 'N') return false;
    return true;
}

/// Check if this is a Zig function (by naming convention).
fn isZigFunction(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "std.")) return true;
    // Check for Zig builtin patterns (specific ones, not just @)
    if (std.mem.indexOf(u8, name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, name, "@cImport") != null) return true;
    return false;
}

/// Check if this is a Go function (by naming convention).
fn isGoFunction(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "runtime.")) return true;
    if (std.mem.startsWith(u8, name, "main.")) return true;
    if (std.mem.indexOf(u8, name, ".") != null) return true; // package.function
    return false;
}

/// Check for extern C / FFI boundary patterns.
fn isExternCPattern(name: []const u8) bool {
    // libc patterns
    if (std.mem.indexOf(u8, name, "libc::") != null) return true;
    if (std.mem.indexOf(u8, name, "nix::") != null) return true;

    // Raw pointer operations at FFI boundary
    if (std.mem.indexOf(u8, name, "from_raw") != null) return true;
    if (std.mem.indexOf(u8, name, "into_raw") != null) return true;

    // extern "C" indicator
    if (std.mem.indexOf(u8, name, "extern") != null) return true;

    return false;
}

/// Check for Zig FFI patterns.
fn isZigFfiPattern(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "@cImport") != null) return true;
    if (std.mem.indexOf(u8, name, "@cInclude") != null) return true;
    if (std.mem.indexOf(u8, name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, name, "@intToPtr") != null) return true;
    if (std.mem.indexOf(u8, name, "extern ") != null) return true;
    return false;
}

/// Check for Go cgo patterns.
fn isGoFfiPattern(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "C.") != null) return true;
    if (std.mem.indexOf(u8, name, "unsafe.Pointer") != null) return true;
    if (std.mem.indexOf(u8, name, "uintptr(") != null) return true;
    return false;
}

/// Check if a stdlib pattern is actually safe user-facing API.
/// Some stdlib functions are so commonly used they should be treated as user code.
fn isSafeStdlibPattern(name: []const u8) bool {
    const safe_patterns = [_][]const u8{
        "std.debug.print",
        "std.fs.cwd",
        "std.io.getStdOut",
        "std.io.getStdErr",
    };

    for (safe_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for noise filtering results.
pub const FilterStats = struct {
    user_count: u32 = 0,
    stdlib_count: u32 = 0,
    compiler_count: u32 = 0,
    third_party_count: u32 = 0,
    unknown_count: u32 = 0,
    suppressed_issues: u32 = 0,

    pub fn record(self: *FilterStats, result: ClassificationResult) void {
        switch (result.origin) {
            .user => self.user_count += 1,
            .stdlib => self.stdlib_count += 1,
            .compiler_generated => self.compiler_count += 1,
            .third_party => self.third_party_count += 1,
            .unknown => self.unknown_count += 1,
        }

        if (result.risk_level == .suppressed) {
            self.suppressed_issues += 1;
        }
    }

    pub fn total(self: FilterStats) u32 {
        return self.user_count + self.stdlib_count + self.compiler_count +
            self.third_party_count + self.unknown_count;
    }

    pub fn suppressionRatio(self: FilterStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.compiler_count + self.stdlib_count)) /
            @as(f64, @floatFromInt(t));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "classifyRustFunction - stdlib detection" {
    const result = classifyRustFunction("_ZN4core3ptr13drop_in_placeE");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);

    const result2 = classifyRustFunction("_ZN5alloc7raw_vec19RawVecT...");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result2.origin);
}

test "classifyRustFunction - compiler generated" {
    // Use a name that matches drop_in_place pattern (in RUST_COMPILER_PATTERNS)
    const result = classifyRustFunction("some_function_drop_in_place_impl");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
    try std.testing.expectEqual(RiskLevel.suppressed, result.risk_level);
}

test "classifyRustFunction - user code" {
    const result = classifyRustFunction("_ZN4myapp4main17h1234567890abcdefE");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyRustFunction - extern C boundary" {
    const result = classifyRustFunction("libc::write");
    try std.testing.expectEqual(RiskLevel.high, result.risk_level);
}

test "classifyZigFunction - stdlib detection" {
    const result = classifyZigFunction("std.ArrayList.init");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyZigFunction - user code" {
    const result = classifyZigFunction("myApp.main");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyZigFunction - FFI boundary" {
    const result = classifyZigFunction("myFunc@cImport");
    try std.testing.expectEqual(RiskLevel.high, result.risk_level);
}

test "classifyGoFunction - cgo generated" {
    const result = classifyGoFunction("_cgo_cfunction_wrapper");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "classifyGoFunction - runtime" {
    const result = classifyGoFunction("runtime.mallocgc");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyGoFunction - user code" {
    const result = classifyGoFunction("main.processData");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyCppFunction - stdlib" {
    const result = classifyCppFunction("_ZSt3maxIiERKT_S2_S2_");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyCppFunction - compiler generated" {
    // __clang_call_terminate is in CPP_COMPILER_PATTERNS
    const result = classifyCppFunction("some_function___clang_call_terminate_wrapper");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "classifyCppFunction - user code" {
    const result = classifyCppFunction("_Z9myProcessv");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "getRiskLevel - user code preserves severity" {
    try std.testing.expectEqual(RiskLevel.critical, getRiskLevel(.user, .critical));
    try std.testing.expectEqual(RiskLevel.high, getRiskLevel(.user, .high));
    try std.testing.expectEqual(RiskLevel.medium, getRiskLevel(.user, .medium));
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.user, .low));
}

test "getRiskLevel - compiler generated always suppressed" {
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .high));
}

test "getRiskLevel - stdlib downgrades severity" {
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.stdlib, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.stdlib, .medium));
}

test "FilterStats - tracking" {
    var stats = FilterStats{};

    stats.record(.{ .origin = .user, .risk_level = .high, .reason = "" });
    stats.record(.{ .origin = .stdlib, .risk_level = .low, .reason = "" });
    stats.record(.{ .origin = .compiler_generated, .risk_level = .suppressed, .reason = "" });

    try std.testing.expectEqual(@as(u32, 1), stats.user_count);
    try std.testing.expectEqual(@as(u32, 1), stats.stdlib_count);
    try std.testing.expectEqual(@as(u32, 1), stats.compiler_count);
    // Only compiler_generated is suppressed, stdlib is low risk
    try std.testing.expectEqual(@as(u32, 1), stats.suppressed_issues);
}

test "LLVM intrinsic detection" {
    const result = classifyFunction("llvm.sqrt.f32", null);
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "auto language detection - Rust" {
    const result = classifyFunction("_ZN4myapp4mainE", null);
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "auto language detection - C++" {
    const result = classifyFunction("_Z9myProcessv", null);
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}
