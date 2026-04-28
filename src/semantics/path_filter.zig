//! Cross-Language Noise Reduction Engine - Layer 2: Path/Debug Metadata Filter
//!
//! Classifies function origin by analyzing LLVM debug metadata (!DIFile).
//! This is the most accurate filter layer but requires debug info in the IR.
//!
//! Reference: plan/lang_ffi_analysis/plan.md - Layer 2: Path / Debug Metadata Filter
//!
//! Key insight: Even mangled names can't hide their origin when
//! debug metadata contains the source file path:
//!
//!   !DIFile(filename: "/rustc/.../library/core/src/ptr/mod.rs")
//!   !DIFile(filename: ".../zig/lib/std/array_list.zig")

const std = @import("std");
const debug_info = @import("../ir/debug_info.zig");

/// Path-based classification result.
pub const PathClassificationResult = struct {
    /// Classification based on source path
    origin: noise_filter.FunctionOrigin,
    /// Risk level after path-based adjustment
    risk_level: noise_filter.RiskLevel,
    /// Reason for classification
    reason: []const u8,
    /// Source file path (if available)
    source_file: []const u8,
    /// Source directory path (if available)
    source_dir: []const u8,
};

// ============================================================================
// Language-Specific Path Patterns for Suppression
// ============================================================================

/// Rust standard library path patterns - suppress these.
const RUST_STDLIB_PATHS = [_][]const u8{
    // Rust compiler source
    "/rustc/",
    "/.rustup/",
    "/rustlib/",

    // Rust standard library source paths
    "library/core/",
    "library/alloc/",
    "library/std/",
    "library/procedural_macro/",

    // Cargo registry (third-party crates treated as stdlib-ish)
    "cargo/registry/",
    ".cargo/registry/",

    // Rust toolchain internals
    "/src/libcore/",
    "/src/liballoc/",
    "/src/libstd/",
    "/src/libtest/",
};

/// Zig standard library path patterns.
const ZIG_STDLIB_PATHS = [_][]const u8{
    // Zig standard library
    "zig/lib/std/",
    "zig/lib/builtin/",
    "zig/lib/compiler/",
    "zig/lib/os/",

    // Zig installation path
    "/lib/zig/",
    "/zig/lib/",
};

/// C++ standard library path patterns.
const CPP_STDLIB_PATHS = [_][]const u8{
    // GCC libstdc++
    "/include/c++/",
    "/usr/include/c++/",
    "/usr/local/include/c++/",
    "/lib/gcc/",

    // libc++
    "/include/c++/v1/",
    "libcxx/",

    // System headers (treat as stdlib)
    "/usr/include/",
    "/usr/local/include/",
    "/Library/Developer/",

    // MSVC
    "\\Program Files (x86)\\Microsoft Visual Studio\\",
    "\\VC\\Tools\\MSVC\\",
    "\\Windows Kits\\",
};

/// Go standard library path patterns.
const GO_STDLIB_PATHS = [_][]const u8{
    // Go runtime and standard library
    "go/src/runtime/",
    "go/src/internal/",
    "go/src/sync/",
    "go/src/net/",
    "go/src/fmt/",
    "go/src/strings/",
    "go/src/io/",

    // Go module cache (third-party)
    "/go/pkg/mod/",
    "gopath/pkg/mod/",

    // CGo generated code patterns
    "_cgo_gotypes.go",
    "?_cgo_export.",
};

/// User code indicators - presence of these suggests user code.
const USER_CODE_INDICATORS = [_][]const u8{
    // Common project source directories
    "/src/",
    "/app/",
    "/pkg/",
    "/lib/",
    "/cmd/",
    "/internal/",
    "/api/",
    "/handler/",
    "/model/",
    "/service/",
    "/utils/",

    // Home directory projects
    "/home/",
    "/Users/",
    "/workspace/",
    "/project/",
    "/repo/",
};

// ============================================================================
// Public API
// ============================================================================

/// Classify a function's origin based on its debug metadata source path.
///
/// This is Layer 2 of the Noise Reduction Engine - more accurate than
/// name-based filtering because it uses actual source file locations.
///
/// Arguments:
///   location - SourceLocation from debug metadata (may be invalid)
///   func_name - Fallback for name-based classification if no debug info
///
/// Returns:
///   PathClassificationResult with origin, risk level, and reasoning
pub fn classifyByPath(
    location: ?debug_info.SourceLocation,
    func_name: []const u8,
) PathClassificationResult {
    // No debug info available - fall back to name-based classification
    if (location) |loc| {
        // Check if location is valid
        if (!loc.valid()) {
            return fallbackClassification(func_name);
        }

        // Build full path for matching
        const full_path = buildFullPath(loc);

        // Classify based on language-specific path patterns
        if (isRustStdlibPath(full_path)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust stdlib source path",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        if (isZigStdlibPath(full_path)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Zig stdlib source path",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        if (isCppStdlibPath(full_path)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "C++ stdlib/system header",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        if (isGoRuntimePath(full_path)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Go runtime/cgo source",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        // Check for cgo generated files specifically
        if (isCgoGeneratedFile(loc.file)) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "CGo glue code",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        // Check for user code indicators
        if (isUserCodePath(full_path) or isUserFile(loc.file)) {
            // Apply additional FFI risk assessment
            const risk = assessFfiRiskFromPath(full_path);
            return .{
                .origin = .user,
                .risk_level = risk,
                .reason = "User source code",
                .source_file = loc.file,
                .source_dir = loc.directory,
            };
        }

        // Unknown path - treat as user code with medium confidence
        return .{
            .origin = .user,
            .risk_level = .medium,
            .reason = "Unknown source path, assuming user code",
            .source_file = loc.file,
            .source_dir = loc.directory,
        };
    } else {
        return fallbackClassification(func_name);
    }
}

/// Classify using only file name (no directory).
/// Useful when directory info is not available.
pub fn classifyByFilename(filename: []const u8) PathClassificationResult {
    if (filename.len == 0) {
        return .{
            .origin = .unknown,
            .risk_level = .medium,
            .reason = "No filename available",
            .source_file = "",
            .source_dir = "",
        };
    }

    // Check for known generated file patterns
    if (isCgoGeneratedFile(filename)) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "Generated glue code filename",
            .source_file = filename,
            .source_dir = "",
        };
    }

    // Check for common stdlib file patterns
    if (isStdlibFilenamePattern(filename)) {
        return .{
            .origin = .stdlib,
            .risk_level = .low,
            .reason = "Standard library filename pattern",
            .source_file = filename,
            .source_dir = "",
        };
    }

    // Default to user code
    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "User code filename",
        .source_file = filename,
        .source_dir = "",
    };
}

/// Combine Layer 1 (name-based) and Layer 2 (path-based) classifications.
/// Uses path-based result when available, falls back to name-based.
pub fn combinedClassify(
    path_result: ?PathClassificationResult,
    name_result: noise_filter.ClassificationResult,
) noise_filter.ClassificationResult {
    if (path_result) |pr| {
        // If path classification found something specific, use it
        if (pr.origin == .compiler_generated or pr.origin == .stdlib) {
            return .{
                .origin = pr.origin,
                .risk_level = pr.risk_level,
                .reason = pr.reason,
            };
        }
    }

    // Fall back to name-based classification
    return name_result;
}

// ============================================================================
// Internal Helpers
// ============================================================================

const noise_filter = @import("noise_filter.zig");

/// Build full path from SourceLocation for matching.
fn buildFullPath(loc: debug_info.SourceLocation) []const u8 {
    if (loc.directory.len > 0) {
        return loc.directory; // Just use directory for path matching
    }
    return loc.file;
}

fn fallbackClassification(func_name: []const u8) PathClassificationResult {
    const result = noise_filter.classifyFunction(func_name, null);
    return .{
        .origin = result.origin,
        .risk_level = result.risk_level,
        .reason = "No debug info, using name-based fallback",
        .source_file = "",
        .source_dir = "",
    };
}

/// Check if path matches Rust stdlib patterns.
fn isRustStdlibPath(path: []const u8) bool {
    for (RUST_STDLIB_PATHS) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if path matches Zig stdlib patterns.
fn isZigStdlibPath(path: []const u8) bool {
    for (ZIG_STDLIB_PATHS) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if path matches C++ stdlib patterns.
fn isCppStdlibPath(path: []const u8) bool {
    for (CPP_STDLIB_PATHS) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if path matches Go runtime patterns.
fn isGoRuntimePath(path: []const u8) bool {
    for (GO_STDLIB_PATHS) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if path contains user code indicators.
fn isUserCodePath(path: []const u8) bool {
    for (USER_CODE_INDICATORS) |indicator| {
        if (std.mem.indexOf(u8, path, indicator) != null) {
            return true;
        }
    }
    return false;
}

/// Check if filename looks like user code.
fn isUserFile(filename: []const u8) bool {
    // Exclude obvious non-user files
    if (filename.len == 0) return false;

    // Generated files
    if (isCgoGeneratedFile(filename)) return false;

    // Files starting with '.' or '_' are often internal
    if (filename[0] == '.') return false;

    return true;
}

/// Check if file is CGo-generated glue code.
fn isCgoGeneratedFile(filename: []const u8) bool {
    const cgo_patterns = [_][]const u8{
        "_cgo_gotypes.go",
        "_cgo_export.c",
        "_cgo_export.h",
        "_cgo_import.c",
        ".cgo2.c",
    };

    for (cgo_patterns) |pattern| {
        if (std.mem.indexOf(u8, filename, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if filename matches common stdlib patterns.
fn isStdlibFilenamePattern(filename: []const u8) bool {
    // Common stdlib file naming conventions
    if (std.mem.startsWith(u8, filename, "__")) return true; // Compiler internal
    if (std.mem.startsWith(u8, filename, "_")) return true; // May be library internal

    // Specific stdlib file patterns
    const stdlib_files = [_][]const u8{
        "panic.",
        "runtime.",
        "alloc.",
        "string.",
        "vector.",
        "memory.",
        "iterator.",
        "algorithm.",
    };

    for (stdlib_files) |pattern| {
        if (std.mem.indexOf(u8, filename, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Assess FFI risk based on path context.
/// Some directories are more likely to contain FFI code.
fn assessFfiRiskFromPath(path: []const u8) noise_filter.RiskLevel {
    const ffi_indicators = [_][]const u8{
        "/ffi/",
        "/native/",
        "/binding/",
        "/bridge/",
        "/interop/",
        "/syscall/",
        "/platform/",
        "/c_api/",
        "/c_bindings/",
        "/extern/",
        "/wrapper/",
        "/cbindgen/",
    };

    for (ffi_indicators) |indicator| {
        if (std.mem.indexOf(u8, path, indicator) != null) {
            return .high;
        }
    }

    return .medium;
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for path-based filtering results.
pub const PathFilterStats = struct {
    path_classified: u32 = 0,
    fallback_used: u32 = 0,
    rust_stdlib_found: u32 = 0,
    zig_stdlib_found: u32 = 0,
    cpp_stdlib_found: u32 = 0,
    go_runtime_found: u32 = 0,
    user_code_found: u32 = 0,
    cgo_generated_found: u32 = 0,

    pub fn record(self: *PathFilterStats, result: PathClassificationResult) void {
        switch (result.origin) {
            .user => self.user_code_found += 1,
            .stdlib => {
                if (std.mem.indexOf(u8, result.reason, "Rust") != null) self.rust_stdlib_found += 1 else if (std.mem.indexOf(u8, result.reason, "Zig") != null) self.zig_stdlib_found += 1 else if (std.mem.indexOf(u8, result.reason, "C++") != null) self.cpp_stdlib_found += 1 else if (std.mem.indexOf(u8, result.reason, "Go") != null) self.go_runtime_found += 1;
            },
            .compiler_generated => {
                if (std.mem.indexOf(u8, result.reason, "cgo") != null or
                    std.mem.indexOf(u8, result.reason, "CGo") != null)
                {
                    self.cgo_generated_found += 1;
                }
            },
            else => {},
        }

        if (result.source_file.len > 0) {
            self.path_classified += 1;
        } else {
            self.fallback_used += 1;
        }
    }

    pub fn coverageRatio(self: PathFilterStats) f64 {
        const total = self.path_classified + self.fallback_used;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.path_classified)) /
            @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "classifyByPath - Rust stdlib" {
    const loc = debug_info.SourceLocation{
        .file = "mod.rs",
        .directory = "/rustc/library/core/src/ptr",
        .line = 100,
        .column = 5,
    };

    const result = classifyByPath(&loc, "_ZN4core3ptr13drop_in_placeE");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.stdlib, result.origin);
    try std.testing.expectEqual(noise_filter.RiskLevel.low, result.risk_level);
}

test "classifyByPath - Zig stdlib" {
    const loc = debug_info.SourceLocation{
        .file = "array_list.zig",
        .directory = "/opt/homebrew/Cellar/zig/0.13.0/lib/zig/std",
        .line = 50,
        .column = 3,
    };

    const result = classifyByPath(&loc, "std.ArrayList.init");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.stdlib, result.origin);
}

test "classifyByPath - user code" {
    const loc = debug_info.SourceLocation{
        .file = "main.zig",
        .directory = "～/OmniScope/src",
        .line = 10,
        .column = 4,
    };

    const result = classifyByPath(&loc, "main.main");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, result.origin);
}

test "classifyByPath - no debug info fallback" {
    const result = classifyByPath(null, "_ZN4myapp4mainE");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, result.origin);
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "fallback") != null);
}

test "classifyByPath - invalid location fallback" {
    const loc = debug_info.SourceLocation{
        .file = "",
        .directory = "",
        .line = 0,
        .column = 0,
    };

    const result = classifyByPath(&loc, "some_function");
    try std.testing.expect(std.mem.indexOf(u8, result.reason, "fallback") != null);
}

test "classifyByPath - CGo generated" {
    const loc = debug_info.SourceLocation{
        .file = "_cgo_gotypes.go",
        .directory = "/tmp/go-build123456789",
        .line = 20,
        .column = 2,
    };

    const result = classifyByPath(&loc, "_cgo_cfunction_wrapper");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.compiler_generated, result.origin);
    try std.testing.expectEqual(noise_filter.RiskLevel.suppressed, result.risk_level);
}

test "classifyByPath - Go runtime" {
    const loc = debug_info.SourceLocation{
        .file = "proc.go",
        .directory = "/usr/local/go/src/runtime",
        .line = 500,
        .column = 8,
    };

    const result = classifyByPath(&loc, "runtime.mallocgc");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.stdlib, result.origin);
}

test "classifyByPath - C++ system header" {
    const loc = debug_info.SourceLocation{
        .file = "vector",
        .directory = "/usr/include/c++/v1",
        .line = 300,
        .column = 12,
    };

    const result = classifyByPath(&loc, "_ZNSt6vectorIiE");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.stdlib, result.origin);
}

test "classifyByPath - FFI directory gets high risk" {
    const loc = debug_info.SourceLocation{
        .file = "bindings.rs",
        .directory = "/project/src/ffi/native",
        .line = 42,
        .column = 5,
    };

    const result = classifyByPath(&loc, "my_binding_func");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, result.origin);
    try std.testing.expectEqual(noise_filter.RiskLevel.high, result.risk_level);
}

test "classifyByFilename - cgo generated" {
    const result = classifyByFilename("_cgo_gotypes.go");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.compiler_generated, result.origin);
}

test "classifyByFilename - normal user file" {
    const result = classifyByFilename("main.rs");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, result.origin);
}

test "classifyByFilename - empty string" {
    const result = classifyByFilename("");
    try std.testing.expectEqual(noise_filter.FunctionOrigin.unknown, result.origin);
}

test "combinedClassify - path takes priority" {
    const path_result = PathClassificationResult{
        .origin = .stdlib,
        .risk_level = .low,
        .reason = "Rust stdlib source path",
        .source_file = "mod.rs",
        .source_dir = "/rustc/library/core",
    };

    const name_result = noise_filter.ClassificationResult{
        .origin = .user,
        .risk_level = .high,
        .reason = "Rust extern C boundary",
    };

    const combined = combinedClassify(&path_result, name_result);
    try std.testing.expectEqual(noise_filter.FunctionOrigin.stdlib, combined.origin);
}

test "combinedClassify - falls back to name when path is user" {
    const path_result = PathClassificationResult{
        .origin = .user,
        .risk_level = .medium,
        .reason = "User source code",
        .source_file = "main.rs",
        .source_dir = "/project/src",
    };

    const name_result = noise_filter.ClassificationResult{
        .origin = .user,
        .risk_level = .high,
        .reason = "Rust extern C boundary",
    };

    const combined = combinedClassify(&path_result, name_result);
    // When both say user, use name result which may have better FFI detection
    try std.testing.expectEqual(noise_filter.FunctionOrigin.user, combined.origin);
}

test "PathFilterStats - tracking" {
    var stats = PathFilterStats{};

    stats.record(.{
        .origin = .user,
        .risk_level = .medium,
        .reason = "User source code",
        .source_file = "main.zig",
        .source_dir = "/project/src",
    });

    stats.record(.{
        .origin = .stdlib,
        .risk_level = .low,
        .reason = "Rust stdlib source path",
        .source_file = "mod.rs",
        .source_dir = "/rustc/library/core",
    });

    stats.record(.{
        .origin = .compiler_generated,
        .risk_level = .suppressed,
        .reason = "CGo glue code",
        .source_file = "_cgo_gotypes.go",
        .source_dir = "/tmp/go-build",
    });

    stats.record(.{
        .origin = .user,
        .risk_level = .medium,
        .reason = "No debug info, using name-based fallback",
        .source_file = "",
        .source_dir = "",
    });

    try std.testing.expectEqual(@as(u32, 3), stats.path_classified);
    try std.testing.expectEqual(@as(u32, 1), stats.fallback_used);
    try std.testing.expectEqual(@as(u32, 1), stats.rust_stdlib_found);
    try std.testing.expectEqual(@as(u32, 1), stats.cgo_generated_found);
    try std.testing.expectEqual(@as(u32, 2), stats.user_code_found);

    const ratio = stats.coverageRatio();
    try std.testing.expect(ratio > 0.7); // Should have good coverage
}

test "isRustStdlibPath - various patterns" {
    try std.testing.expect(isRustStdlibPath("/rustc/library/core/src/ptr/mod.rs"));
    try std.testing.expect(isRustStdlibPath("/home/user/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/library/core/src/ptr/mod.rs"));
    try std.testing.expect(isRustStdlibPath("/home/user/.cargo/registry/src/some-crate-1.0.0/src/lib.rs"));

    try std.testing.expect(!isRustStdlibPath("/home/user/project/src/main.rs"));
    try std.testing.expect(!isRustStdlibPath("/workspace/myapp/src/ffi/bindings.rs"));
}

test "isZigStdlibPath - various patterns" {
    try std.testing.expect(isZigStdlibPath("/opt/homebrew/Cellar/zig/0.13.0/lib/zig/std/array_list.zig"));
    try std.testing.expect(isZigStdlibPath("zig/lib/std/fs/file.zig"));

    try std.testing.expect(!isZigStdlibPath("/home/user/project/src/main.zig"));
    try std.testing.expect(!isZigStdlibPath("/workspace/myapp/app.zig"));
}

test "isCppStdlibPath - various patterns" {
    try std.testing.expect(isCppStdlibPath("/usr/include/c++/v1/vector"));
    try std.testing.expect(isCppStdlibPath("/usr/include/memory"));

    try std.testing.expect(!isCppStdlibPath("/home/user/project/src/main.cpp"));
    try std.testing.expect(!isCppStdlibPath("/workspace/myapp/app.cc"));
}
