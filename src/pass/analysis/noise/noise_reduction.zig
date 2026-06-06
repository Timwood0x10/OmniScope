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
const log = @import("../../../common/log.zig");
const semantics = @import("../../../semantics/noise_filter.zig");
const ffi_utils = @import("../ffi/ffi_utils.zig");
const PatternRegistry = @import("../../../filter/pattern_registry.zig").PatternRegistry;

/// Re-export canonical FunctionOrigin from semantics module.
/// This ensures a single shared definition across all layers.
pub const FunctionOrigin = semantics.FunctionOrigin;

/// Re-export canonical FunctionSurface from surface_classifier.
/// New code should prefer FunctionSurface over FunctionOrigin.
pub const FunctionSurface = semantics.FunctionSurface;

/// Convert FunctionSurface → FunctionOrigin for backward compat.
pub const functionSurfaceToOrigin = semantics.functionSurfaceToOrigin;

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

/// Result of function classification for noise filtering.
pub const ClassificationResult = struct {
    origin: FunctionOrigin,
    weight: RiskWeight,
    reason: ?[]const u8,
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
) ClassificationResult {
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

/// E2-2e: Re-evaluate stdlib classification with MemoryGraph danger-path context.
///
/// Stdlib functions whose pointers flow into FFI boundaries should NOT be
/// suppressed — they are part of a cross-language data path and may carry
/// real risks. This function upgrades stdlib→user when the function is
/// confirmed to be on an FFI danger path.
pub fn reevaluateWithDangerPath(
    classification: ClassificationResult,
    is_on_danger_path: bool,
) ClassificationResult {
    if (!is_on_danger_path) return classification;
    if (classification.origin == .stdlib) {
        return .{
            .origin = .user,
            .weight = .medium,
            .reason = "stdlib-on-danger-path",
        };
    }
    return classification;
}

// ═══════════════════════════════════════════════════════════════
// Layer 1: Name-based Filter (⚡ Fastest, Highest ROI)
// ═══════════════════════════════════════════════════════════════

// Local pattern arrays removed — consolidated into PatternRegistry (single source of truth).
// See: src/filter/pattern_registry.zig

/// Check if a function name matches an LLVM intrinsic noise pattern.
///
/// This is the highest-ROI filter in the entire pipeline:
/// - O(n) prefix match against ~60 known patterns
/// - Eliminates 50%+ of FPs in Rust projects instantly
/// - Zero false negatives for FFI analysis (intrinsics are never FFI boundaries)
///
/// Delegates to PatternRegistry.isLLVMIntrinsic (single source of truth).
pub fn is_llvm_intrinsic_noise(func_name: []const u8) bool {
    return PatternRegistry.isLLVMIntrinsic(func_name);
}

/// Layer 1: Check if function name matches known stdlib/compiler patterns.
/// Returns reason string if should be filtered, null if should analyze.
///
/// Delegates to PatternRegistry.layer1NoiseFilter (single source of truth).
pub fn layer1_NameBasedFilter(func_name: []const u8) ?[]const u8 {
    return PatternRegistry.layer1NoiseFilter(func_name);
}

// ═══════════════════════════════════════════════════════════════
// Layer 2: Path/Debug Metadata Filter (🎯 Most Accurate)
// ═══════════════════════════════════════════════════════════════

// Local stdlib path arrays removed — consolidated into PatternRegistry.
// See: PatternRegistry.isStdlibPath

/// Layer 2: Check if file path indicates stdlib/compiler origin.
/// Returns FunctionOrigin if matched, null if user code.
///
/// Delegates to PatternRegistry.isStdlibPath (single source of truth).
pub fn layer2_PathBasedFilter(file_path: []const u8) ?FunctionOrigin {
    if (PatternRegistry.isStdlibPath(file_path)) return .stdlib;
    return null;
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
/// Delegates to unified ffi_utils.isRustDropGlue (single source of truth).
fn isRustDropGlueName(func_name: []const u8) bool {
    return ffi_utils.isRustDropGlue(func_name);
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
        log.info(
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

        log.info("\n{s} {d} issues → {d} user code", .{
            if (self.user_code > 0) "✅" else "⚠️",
            self.total_issues,
            self.user_code,
        });

        if (self.ffi_high_count > 0 or self.ffi_medium_count > 0) {
            log.info(" ({d} FFI HIGH, {d} FFI MEDIUM)", .{
                self.ffi_high_count,
                self.ffi_medium_count,
            });
        }

        log.info("\n", .{});

        if (self.category_count > 0) {
            log.info("\n┌─ Issue Categories ────────────────────────────────\n", .{});

            for (self.categories[0..self.category_count]) |cat| {
                if (cat.count == 0) continue;

                const icon = switch (cat.origin) {
                    .user => "✅",
                    .third_party => "📦",
                    .stdlib => "📚",
                    .compiler_generated => "🔧",
                    .unknown => "❓",
                };

                log.info("│ {s} [{s}] {d:>4} issues\n", .{
                    icon,
                    cat.kind,
                    cat.count,
                });
            }

            log.info("└────────────────────────────────────────────────\n", .{});
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

// ═══════════════════════════════════════════════════════════════
// Tests — P0-1 Noise Reduction Layer 1
// ═══════════════════════════════════════════════════════════════

test "is_llvm_intrinsic_noise - threadlocal (BLST #1 FP)" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.threadlocal.address"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.threadlocal.address.p0i8"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.threadlocal.restore"));
}

test "is_llvm_intrinsic_noise - lifetime markers" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.lifetime.start.p0i8"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.lifetime.end.p0i8"));
}

test "is_llvm_intrinsic_noise - debug info" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.dbg.declare"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.dbg.value"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.dbg.label"));
}

test "is_llvm_intrinsic_noise - optimization hints" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.assume"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.expect.i32"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.smax.i64"));
}

test "is_llvm_intrinsic_noise - coroutine (Wasmtime)" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.coro.id"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.coro.begin"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.coro.end"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.coro.async.ctx"));
}

test "is_llvm_intrinsic_noise - gc roots" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.gc.root"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.gcwrite"));
}

test "is_llvm_intrinsic_noise - catch-all llvm.* prefix" {
    // Any unrecognized llvm.* intrinsic should also be suppressed
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.unknown.intrinsic"));
}

test "is_llvm_intrinsic_noise - real FFI functions NOT suppressed" {
    // These are real user FFI calls that MUST NOT be filtered
    try std.testing.expect(!is_llvm_intrinsic_noise("dlopen"));
    try std.testing.expect(!is_llvm_intrinsic_noise("dlsym"));
    try std.testing.expect(!is_llvm_intrinsic_noise("malloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("free"));
    try std.testing.expect(!is_llvm_intrinsic_noise("pthread_create"));
    try std.testing.expect(!is_llvm_intrinsic_noise("sqlite3_open"));
    try std.testing.expect(!is_llvm_intrinsic_noise("JNI_OnLoad"));
    try std.testing.expect(!is_llvm_intrinsic_noise("Py_INCREF"));
    try std.testing.expect(!is_llvm_intrinsic_noise("socket"));
    try std.testing.expect(!is_llvm_intrinsic_noise("connect"));
    try std.testing.expect(!is_llvm_intrinsic_noise("mmap"));
    // User-defined function names
    try std.testing.expect(!is_llvm_intrinsic_noise("my_function"));
    try std.testing.expect(!is_llvm_intrinsic_noise("handle_request"));
}

test "is_llvm_intrinsic_noise - Rust synthetic patterns" {
    // After FIX-1 (v0.1.6): __rust_alloc/dealloc/realloc REMOVED from noise patterns.
    // They must now be tracked by ptr_lifetime for FFI boundary detection.
    try std.testing.expect(!is_llvm_intrinsic_noise("__rust_alloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("__rust_dealloc"));
    // These Rust stdlib safe primitives ARE still correctly classified as noise
    try std.testing.expect(is_llvm_intrinsic_noise("sync_channel::channel"));
    try std.testing.expect(is_llvm_intrinsic_noise("mpsc::channel::new"));
    try std.testing.expect(is_llvm_intrinsic_noise("Waker::wake"));
    try std.testing.expect(is_llvm_intrinsic_noise("Arc::<T>::clone"));
    try std.testing.expect(is_llvm_intrinsic_noise("RawVec::<T>::grow"));
}

test "layer1_NameBasedFilter - llvm intrinsics return reason" {
    const result = layer1_NameBasedFilter("llvm.threadlocal.address");
    try std.testing.expect(result != null);
}

test "layer1_NameBasedFilter - real FFI returns null (analyze)" {
    const result = layer1_NameBasedFilter("dlopen");
    try std.testing.expect(result == null);
}
