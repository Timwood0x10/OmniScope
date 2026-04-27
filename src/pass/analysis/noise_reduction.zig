/// Cross-Language Noise Reduction Engine
///
/// Core insight from plan.md: "Modern language projects are not hard to analyze,
/// it's that standard library and compiler-generated code creates too much noise."
///
/// Three-layer filtering system:
/// - Layer 1: Name-based Filter (fastest, highest ROI)
/// - Layer 2: Path/Debug Metadata Filter (most accurate)
/// - Layer 3: Behavior Filter (most intelligent)
///
/// Expected impact:
/// - Rust (wasmtime): 297 → 10~20 issues
/// - Zig (avg): 191 → ~40 issues (FP rate <30%)
/// - C (SQLite): 0 → 0 (no change, already clean)
const std = @import("std");
const semantics = @import("../../semantics/noise_filter.zig");

/// Re-export canonical FunctionOrigin from semantics module.
/// This ensures a single shared definition across all layers.
pub const FunctionOrigin = semantics.FunctionOrigin;

/// Risk weight for combining origin + issue severity.
/// Determines final reporting priority.
pub const RiskWeight = enum(u8) {
    /// Critical: User code + dangerous sink (always report)
    critical = 4,
    /// High: User code + medium risk, or third-party + dangerous sink
    high = 3,
    /// Medium: Stdlib + dangerous (informational), or user + low risk
    medium = 2,
    /// Low: Stdlib + medium risk (suppressed by default)
    low = 1,
    /// Ignored: Compiler-generated anything, stdlib low-risk
    ignored = 0,

    pub fn toString(self: RiskWeight) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW (suppressed)",
            .ignored => "IGNORED",
        };
    }
};

/// Configuration for noise reduction behavior.
pub const NoiseReductionConfig = struct {
    /// Focus on user code only (suppress stdlib/compiler-generated)
    focus_user_code: bool = true,

    /// Report only FFI boundary issues (skip generic memory safety)
    ffi_only: bool = false,

    /// Include stdlib issues in output (usually noisy)
    include_stdlib: bool = false,

    /// Include compiler-generated issues (almost always noise)
    include_compiler_generated: bool = false,

    /// Maximum issues to report per category before grouping
    max_issues_per_category: u32 = 20,
};

/// Result of classifying a function's origin and risk.
pub fn classifyFunction(
    func_name: []const u8,
    debug_file_path: ?[]const u8,
    config: NoiseReductionConfig,
) struct { origin: FunctionOrigin, weight: RiskWeight, reason: ?[]const u8 } {
    // Layer 1: Name-based filter (fastest)
    if (layer1_NameBasedFilter(func_name)) |reason| {
        return .{
            .origin = .compiler_generated,
            .weight = .ignored,
            .reason = reason,
        };
    }

    // Layer 2: Path/Debug metadata filter (most accurate)
    if (debug_file_path) |path| {
        if (layer2_PathBasedFilter(path)) |origin| {
            const weight = if (config.include_stdlib) RiskWeight.low else RiskWeight.ignored;
            return .{ .origin = origin, .weight = weight, .reason = null };
        }
    }

    // Default: user code (analyze fully)
    return .{
        .origin = .user,
        .weight = .critical,
        .reason = null,
    };
}

// ═══════════════════════════════════════════════════════════════
// Layer 1: Name-based Filter (⚡ Fastest, Highest ROI)
// ═══════════════════════════════════════════════════════════════

/// Rust standard library / compiler patterns to skip.
const rust_stdlib_patterns = [_][]const u8{
    // Core library
    "core::",    "core.",
    "alloc::",   "alloc.",
    "std::",     "std.",

    // Panic handling (compiler-generated)
    "panic_",    "begin_panic",
    "panic_fmt",

    // Drop glue (guaranteed safe by ownership system)
    "drop_in_place",
    "_ZN4core3ptr13drop_in_place", // mangled form
    "<T as core::ops::drop::Drop>::drop",

    // Allocator internals (normal wrapper behavior)
    "RawVec",
    "Vec<",
    "slice::",
    "fmt::",
    "string::",

    // Iterator glue
    "Iterator",
    "IntoIterator",
    "next",

    // Mangled name patterns (Rust-specific)
    "_ZN4core", // core::
    "_ZN5alloc", // alloc::
    "_ZN3std", // std::
    "_RNv", // Rust namespacing
    "$LT$core", // <$ core
    "$LT$alloc", // <$ alloc
    "_$LT$", // ::<
    "_GT$", // ::>
    "_RNv", // namespaced

    // Common compiler-generated functions
    "__rust_dealloc",
    "__rust_alloc",
    "real_drop_in_place",
    "size_hint",
    "reserve_total",
};

/// Zig standard library patterns to skip.
/// Covers: std packages, allocator wrappers, compiler helpers, debug/DWARF, OS abstraction.
const zig_stdlib_patterns = [_][]const u8{
    // Standard library packages (core modules)
    "std.",
    "std.debug",
    "std.mem",
    "std.fmt",
    "std.heap",
    "std.fs",
    "std.io",
    "std.os",
    "std.posix",
    "std.ascii",
    "std.base64",
    "std.hash",
    "std.array_list",
    "std.bit_set",
    "std.builtin",
    "std.crypto",
    "std.compress",
    "std.random",

    // Allocator wrappers (safe abstraction layer — normal alloc/free pattern)
    "mem.Allocator",
    "GeneralPurposeAllocator",
    "ArenaAllocator",
    "page_allocator",
    "c_allocator",
    "raw_c_allocator",
    "FixedBufferAllocator",

    // Compiler helpers (guaranteed safe by type system)
    "zig_assert_fail",
    "zig_panic",
    "zig_oq",
    "zig_write",
    "zig_generic_resolve",

    // Debug/DWARF support (internal only — optional unwraps are not bugs)
    "debug.Dwarf",
    "debug.Info",
    "debug.Segment",
    "debug.LineInfo",

    // OS abstraction layer (safe wrappers around syscalls)
    "posix.",
    "posix_getenv",
    "posix_environ",
    "fs.File",
    "fs.Dir",
    "fs.Path",
    "fs.cwd",
    "fs.openFile",
    "fs.access",
    "fs.realpath",
    "fs.makeAbsolute",
    "fs.canonicalize",

    // Start/panic runtime (compiler-generated entry points)
    "start.zig",
    "panic.zig",
    "builtin.zig",

    // Zig-specific mangled/generated names
    "__zig_",
    "__anon_",
    "(anonymous namespace)",
    "@typeInfo",
    "is_named_enum_value",

    // Common Zig internal function suffixes/patterns
    "__zig_switch_target",
    "__zig_error_name",
    "__zig_resolve_enum_name",
};

/// C++ STL patterns to skip.
const cpp_stl_patterns = [_][]const u8{
    // C++ standard library
    "std::",
    "__gnu_cxx::",
    "__cxa_",

    // Exception handling (compiler-generated)
    "__clang_call_terminate",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_throw",

    // STL containers (normal grow/realloc behavior)
    "std::vector",
    "std::string",
    "std::map",
    "basic_string",
    "_M_insert",
    "_M_emplace_back",

    // Type info (RTTI)
    "type_info",
    "__class_type_info",
};

/// Layer 1: Check if function name matches known stdlib/compiler patterns.
/// Returns reason string if should be filtered, null if should analyze.
pub fn layer1_NameBasedFilter(func_name: []const u8) ?[]const u8 {
    // Check Rust patterns
    for (rust_stdlib_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return "Rust stdlib/compiler pattern";
        }
    }

    // Check Zig patterns
    for (zig_stdlib_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return "Zig stdlib/internal pattern";
        }
    }

    // Check C++ patterns
    for (cpp_stl_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return "C++ STL/compiler pattern";
        }
    }

    return null; // Not filtered — analyze this function
}

// ═══════════════════════════════════════════════════════════════
// Layer 2: Path/Debug Metadata Filter (🎯 Most Accurate)
// ═══════════════════════════════════════════════════════════════

/// Known standard library path prefixes.
/// These come from LLVM IR's !DIFile(filename: "...") metadata.
const rust_stdlib_paths = [_][]const u8{
    "/rustc/",
    "/library/core/",
    "/library/std/",
    "/library/alloc/",
    "/registry/src/",
    "/cargo/registry/",
    "/.cargo/registry/",
};

const zig_stdlib_paths = [_][]const u8{
    "zig/lib/std/",
    "zig/std/",
    "/lib/zig/std/",
    ".zig/lib/std/",
};

const cpp_stl_paths = [_][]const u8{
    "/usr/include/c++/",
    "/usr/include/g++",
    "/libc++/",
    "/libcxx/",
    "/include/c++/",
    "/clang/",
};

/// Layer 2: Check if file path indicates stdlib/compiler origin.
/// Returns FunctionOrigin if matched, null if user code.
pub fn layer2_PathBasedFilter(file_path: []const u8) ?FunctionOrigin {
    // Normalize path separators (Windows compatibility)
    // Note: LLVM DIFile usually uses forward slashes

    // Check Rust paths
    for (rust_stdlib_paths) |prefix| {
        if (indexOfPath(file_path, prefix)) {
            return .stdlib;
        }
    }

    // Check Zig paths
    for (zig_stdlib_paths) |prefix| {
        if (indexOfPath(file_path, prefix)) {
            return .stdlib;
        }
    }

    // Check C++ paths
    for (cpp_stl_paths) |prefix| {
        if (indexOfPath(file_path, prefix)) {
            return .stdlib;
        }
    }

    return null; // User code or unknown
}

/// Case-insensitive path contains check.
/// Returns true if needle is found in haystack (case-insensitive for Windows paths).
fn indexOfPath(haystack: []const u8, needle: []const u8) bool {
    // Edge case: empty inputs
    if (haystack.len == 0 or needle.len == 0) return false;
    if (needle.len > haystack.len) return false;

    // Simple case-sensitive check first (most common case)
    if (std.mem.indexOf(u8, haystack, needle) != null) return true;

    // Case-insensitive fallback for Windows paths
    // Compare char by char, converting both to lowercase
    var i: usize = 0;
    const max_start = haystack.len - needle.len;
    while (i <= max_start) : (i += 1) {
        var match = true;
        for (needle, 0..) |needle_char, j| {
            const h_char = haystack[i + j];
            const h_lower = std.ascii.toLower(h_char);
            const n_lower = std.ascii.toLower(needle_char);
            if (h_lower != n_lower) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }

    return false;
}

// ═══════════════════════════════════════════════════════════════
// Layer 3: Behavior Filter (🧠 Most Intelligent)
// ═══════════════════════════════════════════════════════════════

/// Detect Rust drop glue behavior pattern:
/// free(ptr) + memset(ptr, 0, size) + branch + panic_handler_call
/// This is normal destructor chaining, NOT a bug.
pub fn isRustDropGlueBehavior(
    func_name: []const u8,
    has_free: bool,
    has_memset: bool,
    has_branch: bool,
    instruction_count: u32,
) bool {
    // Name-based quick check
    if (isRustDropGlueName(func_name)) return true;

    // Behavior-based detection (for mangled/unrecognized names)
    if (has_free and has_memset and has_branch) {
        // Drop glue typically has:
        // - Relatively short (10-50 instructions in optimized builds)
        // - Free followed by memset (clearing the vtable pointer)
        // - Branch for size optimization
        if (instruction_count > 5 and instruction_count < 200) {
            // Additional heuristic: long mangled names are likely generic drop impls
            if (func_name.len > 40) return true;
        }
    }

    return false;
}

/// Quick name-based check for Rust drop glue.
fn isRustDropGlueName(func_name: []const u8) bool {
    const drop_patterns = [_][]const u8{
        "drop_in_place",
        "_ZN4core3ptr13drop_in_place",
        "<T as core::ops::drop::Drop>::drop",
        "::drop",
        "real_drop_in_place",
    };

    for (drop_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

    return false;
}

/// Detect Zig allocator wrapper behavior:
/// call allocator.alloc(size) → store length → return slice
/// This is safe wrapper around malloc, not a leak.
pub fn isZigAllocatorWrapperBehavior(
    func_name: []const u8,
    calls_allocator_alloc: bool,
    stores_length: bool,
    returns_slice: bool,
) bool {
    // Must have all three characteristics
    if (calls_allocator_alloc and stores_length and returns_slice) {
        // Verify it looks like an allocator method
        const alloc_patterns = [_][]const u8{
            "alloc",
            "create",
            "new",
            "init",
        };

        for (alloc_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
        }
    }

    return false;
}

/// Detect STL vector grow behavior:
/// malloc(new_size) → memcpy(old_ptr, new_ptr, old_size) → free(old_ptr)
/// This is reallocation, NOT a leak.
pub fn isSTLVectorGrowBehavior(
    func_name: []const u8,
    has_malloc: bool,
    has_memcpy: bool,
    has_free: bool,
) bool {
    if (has_malloc and has_memcpy and has_free) {
        // Vector grow patterns
        const vec_patterns = [_][]const u8{
            "_M_realloc",
            "_M_emplace_back",
            "_M_append",
            "grow",
            "reserve",
            "resize",
            "push_back",
            "append",
        };

        for (vec_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
        }
    }

    return false;
}

// ═══════════════════════════════════════════════════════════════
// Output Attribution Grouping
// ═══════════════════════════════════════════════════════════════

/// Maximum number of issue categories to track.
const max_categories = 32;

/// Single category entry for attribution tracking.
const CategoryEntry = struct {
    kind: []const u8,
    count: u32,
    origin: FunctionOrigin,

    pub fn init(kind: []const u8, origin: FunctionOrigin) CategoryEntry {
        return .{
            .kind = kind,
            .count = 0,
            .origin = origin,
        };
    }
};

/// Summary statistics for attribution grouping.
/// Tracks issues by origin (user/stdlib/compiler/third-party) and kind (UAF/leak/etc.).
/// Produces output in format: "191 issues → 21 user code (8 FFI HIGH)"
pub const AttributionSummary = struct {
    total_issues: usize = 0,
    user_code: usize = 0,
    stdlib_suppressed: usize = 0,
    compiler_ignored: usize = 0,
    third_party: usize = 0,

    /// Category breakdown for detailed reporting
    categories: [max_categories]CategoryEntry = [_]CategoryEntry{.{ .kind = "", .count = 0, .origin = .unknown }} ** max_categories,
    category_count: usize = 0,

    /// Track high-severity FFI issues separately for summary line
    ffi_high_count: usize = 0,
    ffi_medium_count: usize = 0,

    /// Add an issue to the summary, classified by origin and kind.
    pub fn addIssue(self: *AttributionSummary, origin: FunctionOrigin, kind: []const u8) void {
        self.total_issues += 1;

        // Update origin-level counters
        switch (origin) {
            .user => self.user_code += 1,
            .stdlib => self.stdlib_suppressed += 1,
            .compiler_generated => self.compiler_ignored += 1,
            .third_party => self.third_party += 1,
            .unknown => self.user_code += 1, // Treat unknown as user code
        }

        // Track FFI severity for summary
        if (std.mem.indexOf(u8, kind, "FFI") != null) {
            if (std.mem.indexOf(u8, kind, "CRITICAL") != null or
                std.mem.indexOf(u8, kind, "HIGH") != null)
            {
                self.ffi_high_count += 1;
            } else {
                self.ffi_medium_count += 1;
            }
        }

        // Find or create category entry
        var found = false;
        for (self.categories[0..self.category_count]) |*cat| {
            if (std.mem.eql(u8, cat.kind, kind)) {
                cat.count += 1;
                found = true;
                break;
            }
        }

        // Create new category entry if not found and space available
        if (!found and self.category_count < max_categories) {
            self.categories[self.category_count] = CategoryEntry.init(kind, origin);
            self.categories[self.category_count].count = 1;
            self.category_count += 1;
        }
    }

    /// Print the noise-reduced analysis report.
    /// Format: "191 issues → 21 user code (8 FFI HIGH)"
    pub fn printReport(self: *const AttributionSummary) void {
        std.debug.print(
            \\╔══════════════════════════════════════════════════════╗
            \\║     OmniScope Analysis Report (Noise-Reduced)         ║
            \\╠══════════════════════════════════════════════════════╣
            \\║ Total Issues Detected: {d:>6}                       ║
            \\╠──────────────────────────────────────────────────────╣
            \\║ ✅ User Code:           {d:>6} (ACTION NEEDED)       ║
            \\║ 📦 Third-Party:         {d:>6}                       ║
            \\║ 📚 Stdlib (Suppressed): {d:>6} (--include-stdlib)   ║
            \\║ 🔧 Compiler (Ignored):  {d:>6} (noise)              ║
            \\╚══════════════════════════════════════════════════════╝
        , .{
            self.total_issues,
            self.user_code,
            self.third_party,
            self.stdlib_suppressed,
            self.compiler_ignored,
        });

        std.debug.print("\n{s} {d} issues → {d} user code", .{
            if (self.user_code > 0) "✅" else "⚠️",
            self.total_issues,
            self.user_code,
        });

        if (self.ffi_high_count > 0 or self.ffi_medium_count > 0) {
            std.debug.print(" ({d} FFI HIGH, {d} FFI MEDIUM)", .{
                self.ffi_high_count,
                self.ffi_medium_count,
            });
        }

        std.debug.print("\n", .{});

        if (self.category_count > 0) {
            std.debug.print("\n┌─ Issue Categories ────────────────────────────────\n", .{});

            for (self.categories[0..self.category_count]) |cat| {
                if (cat.count == 0) continue;

                const icon = switch (cat.origin) {
                    .user => "✅",
                    .third_party => "📦",
                    .stdlib => "📚",
                    .compiler_generated => "🔧",
                    .unknown => "❓",
                };

                std.debug.print("│ {s} [{s}] {d:>4} issues\n", .{
                    icon,
                    cat.kind,
                    cat.count,
                });
            }

            std.debug.print("└────────────────────────────────────────────────\n", .{});
        }
    }

    /// Reset all counters (for reuse across multiple modules).
    pub fn reset(self: *AttributionSummary) void {
        self.total_issues = 0;
        self.user_code = 0;
        self.stdlib_suppressed = 0;
        self.compiler_ignored = 0;
        self.third_party = 0;
        self.category_count = 0;
        self.ffi_high_count = 0;
        self.ffi_medium_count = 0;
        @memset(&self.categories, CategoryEntry.init("", .unknown));
    }
};
