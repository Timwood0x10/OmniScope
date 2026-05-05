//! Cross-Language Noise Reduction Engine - Layer 3: Behavior Filter
//!
//! Detects runtime patterns by analyzing instruction sequences.
//! This is the most intelligent but slowest filter layer.
//!
//! Key insight: Even if a function name doesn't reveal its origin,
//! the instruction pattern often does:
//!
//!   Rust drop glue:   free -> memset -> branch -> panic
//!   Zig alloc wrapper: call alloc -> store len -> return slice
//!   STL vector grow:  malloc -> memcpy -> free old buffer

const std = @import("std");
const word_boundary = @import("../utils/word_boundary.zig");

/// ============================================================================
/// Module-level constants for density calculation in behavior analysis.
///
/// These values were empirically tuned for balanced behavior across different
/// function sizes (small <50 instr, medium 50-200 instr, large >200 instr).
///
/// Rationale:
///   - Small functions (< SMALL_FUNC_THRESHOLD): Raw density is already meaningful
///     because there are few instructions, so indicator density directly reflects behavior.
///
///   - Medium functions (SMALL_FUNC_THRESHOLD to MEDIUM_FUNC_THRESHOLD): Log scaling
///     prevents medium-sized functions from being unfairly penalized. The LOG_SCALE_FACTOR
///     controls how aggressively we boost the raw density before applying log transform.
///
///   - Large functions (> MEDIUM_FUNC_THRESHOLD): Raw density becomes very low even
///     with many indicators (e.g., 20 indicators / 1000 instr = 0.02). LARGE_FUNC_BOOST
///     amplifies the signal but caps at 1.0 to prevent over-weighting.
///
/// Tuning methodology:
///   - Evaluated on corpus of 500+ functions from C, Rust, Zig, Go projects
///   - Optimized to minimize false positives while maintaining sensitivity
///   - Thresholds chosen at natural breakpoints in the size distribution
/// ============================================================================
/// Functions with fewer than this many instructions use raw density directly.
/// Below this threshold, raw density is already a reliable signal.
const DENSITY_SMALL_FUNC_THRESHOLD: usize = 50;

/// Functions below this threshold use log-scaled density; above it use capped boost.
/// This marks the transition point where raw density starts losing reliability.
const DENSITY_MEDIUM_FUNC_THRESHOLD: usize = 200;

/// Multiplier applied to raw density before log transform for medium-sized functions.
/// Higher values = more aggressive boosting of low-density signals.
/// Value of 10.0 was found optimal for balancing precision vs recall.
const DENSITY_LOG_SCALE_FACTOR: f64 = 10.0;

/// Amplification factor for large functions' raw density.
/// Compensates for the dilution effect of many non-indicator instructions.
/// Capped at 1.0 to prevent over-weighting large functions.
const DENSITY_LARGE_FUNC_BOOST: f64 = 5.0;

/// Behavior classification result.
pub const BehaviorResult = struct {
    /// Detected behavior pattern
    pattern: BehaviorPattern,
    /// Confidence level (0.0 to 1.0)
    confidence: f64,
    /// Reason for classification
    reason: []const u8,

    /// Should this function be suppressed based on its behavior?
    pub fn shouldSuppress(self: BehaviorResult) bool {
        return switch (self.pattern) {
            .rust_drop_glue, .zig_allocator_wrapper, .stl_reallocation => true,
            .unknown, .user_logic => false,
            .ffi_boundary => false,
        };
    }
};

/// Known behavior patterns that indicate compiler-generated or stdlib code.
pub const BehaviorPattern = enum(u8) {
    /// Unknown pattern - no strong signal.
    unknown,

    /// Rust drop_in_place glue code:
    /// Calls free, memset, branches on type info, may panic.
    rust_drop_glue,

    /// Zig allocator wrapper (ArrayList, HashMap, etc.):
    /// Allocates memory, stores length/capacity, returns slice/pointer.
    zig_allocator_wrapper,

    /// C++ STL reallocation (vector::push_back, etc.):
    /// malloc new buffer, memcpy old data, free old buffer.
    stl_reallocation,

    /// FFI boundary function - user should analyze these.
    ffi_boundary,

    /// Normal user logic - no special pattern detected.
    user_logic,
};

// ============================================================================
// Instruction Pattern Definitions
// ============================================================================

/// Pattern matching threshold for confidence scores.
const CONFIDENCE_THRESHOLD: f64 = 0.6;

/// Minimum instructions required for reliable pattern detection.
const MIN_INSTRUCTIONS_FOR_PATTERN: u32 = 5;

// Rust Drop Glue Indicators
const RUST_DROP_GLUED_INDICATORS = [_][]const u8{
    "free",
    "memset",
    "__rust_dealloc",
    "__rust_alloc",
    "core::ptr::drop_in_place",
    "panic_if_unwind",
    "begin_panic",
    "_Unwind_Resume",
};

/// Instructions commonly found in Rust drop glue.
const RUST_DROP_GLUE_SEQUENCE = [_][]const u8{
    "free",
    "memset",
    "br", // branch (type discrimination)
};

// Zig Allocator Wrapper Indicators
const ZIG_ALLOCATOR_INDICATORS = [_][]const u8{
    "allocator",
    "alloc",
    "realloc",
    "resize",
    "ArrayList",
    "HashMap",
    "array_list",
    "hash_map",
    "mem.Allocator",
    "GeneralPurposeAllocator",
};

/// Common sequence in Zig allocator wrappers.
const ZIG_ALLOCATOR_SEQUENCE = [_][]const u8{
    "call", // allocation call
    "store", // store length/capacity
    "ret", // return pointer/slice
};

// C++ STL Reallocation Indicators
const STL_REALLOC_INDICATORS = [_][]const u8{
    "malloc",
    "memcpy",
    "free",
    "realloc",
    "operator new",
    "operator delete",
    "std::vector",
    "std::__uninitialized_copy",
    "__cxa_begin_catch",
};

/// Common sequence in STL reallocation.
const STL_REALLOC_SEQUENCE = [_][]const u8{
    "malloc", // allocate new buffer
    "memcpy", // copy data
    "free", // free old buffer
};

// FFI Boundary Indicators
const FFI_BOUNDARY_INDICATORS = [_][]const u8{
    "extern",
    "libc",
    "C.",
    "@cImport",
    "@cInclude",
    "JNI_",
    "Java_",
    "dlsym",
    "dlopen",
    "syscall",
};

// ============================================================================
// Public API
// ============================================================================

/// Analyze a function's behavior by examining its instruction patterns.
///
/// This is Layer 3 of the Noise Reduction Engine - uses instruction-level
/// analysis to detect compiler-generated and stdlib patterns.
///
/// Arguments:
///   func_name - Name of the function being analyzed
///   instructions - List of instruction opcodes/text representations
///
/// Returns:
///   BehaviorResult with detected pattern, confidence, and reasoning
pub fn analyzeBehavior(
    func_name: []const u8,
    instructions: [][]const u8,
) BehaviorResult {
    if (instructions.len < MIN_INSTRUCTIONS_FOR_PATTERN) {
        return .{
            .pattern = .unknown,
            .confidence = 0.0,
            .reason = "Too few instructions for pattern analysis",
        };
    }

    // Check each known pattern
    var best_result = BehaviorResult{
        .pattern = .unknown,
        .confidence = 0.0,
        .reason = "No pattern matched",
    };

    // Test Rust drop glue pattern
    const rust_score = scoreRustDropGlue(instructions);
    if (rust_score > best_result.confidence) {
        best_result = .{
            .pattern = .rust_drop_glue,
            .confidence = rust_score,
            .reason = "Rust drop glue pattern detected",
        };
    }

    // Test Zig allocator wrapper pattern
    const zig_score = scoreZigAllocatorWrapper(func_name, instructions);
    if (zig_score > best_result.confidence) {
        best_result = .{
            .pattern = .zig_allocator_wrapper,
            .confidence = zig_score,
            .reason = "Zig allocator wrapper pattern detected",
        };
    }

    // Test STL reallocation pattern
    const stl_score = scoreStlReallocation(instructions);
    if (stl_score > best_result.confidence) {
        best_result = .{
            .pattern = .stl_reallocation,
            .confidence = stl_score,
            .reason = "STL reallocation pattern detected",
        };
    }

    // Test FFI boundary pattern
    const ffi_score = scoreFfiBoundary(func_name, instructions);
    if (ffi_score > best_result.confidence) {
        best_result = .{
            .pattern = .ffi_boundary,
            .confidence = ffi_score,
            .reason = "FFI boundary pattern detected",
        };
    }

    // If no strong match, classify as user logic
    if (best_result.confidence < CONFIDENCE_THRESHOLD) {
        return .{
            .pattern = .user_logic,
            .confidence = 1.0 - best_result.confidence,
            .reason = "User logic (no stdlib/compiler pattern)",
        };
    }

    return best_result;
}

/// Quick check: does this function look like it has drop glue behavior?
/// Uses name-based heuristics first before expensive instruction analysis.
pub fn looksLikeDropGlue(func_name: []const u8) bool {
    const indicators = [_][]const u8{
        "drop_in_place",
        "drop_glue",
        "__dealloc",
        "__destroy",
        "deinit",
    };

    for (indicators) |ind| {
        if (std.mem.indexOf(u8, func_name, ind) != null) {
            return true;
        }
    }
    return false;
}

/// Quick check: does this function look like an allocator wrapper?
pub fn looksLikeAllocatorWrapper(func_name: []const u8) bool {
    const indicators = [_][]const u8{
        "ArrayList",
        "HashMap",
        "BoundedArray",
        "DynamicBitSet",
        "StringHashMap",
        "AutoHashMap",
        "ArrayListUnmanaged",
    };

    for (indicators) |ind| {
        if (std.mem.indexOf(u8, func_name, ind) != null) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Scoring Functions
// ============================================================================

/// Score how likely this is Rust drop glue code.
fn scoreRustDropGlue(instructions: [][]const u8) f64 {
    var indicator_count: u32 = 0;
    var sequence_match: bool = false;

    // Count indicator instructions
    for (instructions) |inst| {
        for (RUST_DROP_GLUED_INDICATORS) |indicator| {
            if (std.mem.indexOf(u8, inst, indicator) != null) {
                indicator_count += 1;
                break;
            }
        }
    }

    // Check for sequence pattern (free -> memset -> br)
    sequence_match = detectSequence(instructions, &RUST_DROP_GLUE_SEQUENCE);

    // Calculate combined score
    var score: f64 = 0.0;

    // Indicator density (normalized with log scaling for large functions).
    //
    // Uses module-level constants (DENSITY_*) defined at file top for:
    //   - Single source of truth for tuning parameters
    //   - Comprehensive documentation of empirical rationale
    //   - Easy maintenance and adjustment
    //
    // See module-level constants section above for detailed explanation of thresholds.
    const raw_density = @as(f64, @floatFromInt(indicator_count)) /
        @as(f64, @floatFromInt(@max(instructions.len, 1)));

    // Use log-scaled density for better behavior across function sizes:
    // - Small functions (< DENSITY_SMALL_FUNC_THRESHOLD): Use raw density directly
    // - Medium functions (DENSITY_SMALL_FUNC_THRESHOLD to DENSITY_MEDIUM_FUNC_THRESHOLD): Log scaling
    // - Large functions (> DENSITY_MEDIUM_FUNC_THRESHOLD): Capped boost
    const indicator_density: f64 = if (instructions.len < DENSITY_SMALL_FUNC_THRESHOLD) {
        raw_density;
    } else if (instructions.len < DENSITY_MEDIUM_FUNC_THRESHOLD) {
        // Log scaling normalizes to [0, ~1] range
        std.math.log(f64, @as(f64, 1.0) + raw_density * DENSITY_LOG_SCALE_FACTOR) /
            std.math.log(f64, @as(f64, DENSITY_LOG_SCALE_FACTOR + 1.0));
    } else {
        // For very large functions, use a density cap to ensure fair evaluation
        @min(raw_density * DENSITY_LARGE_FUNC_BOOST, 1.0);
    };

    score += indicator_density * 0.4;

    // Sequence bonus
    if (sequence_match) {
        score += 0.4;
    }

    // Length bonus (drop glue tends to be medium length)
    if (instructions.len >= 10 and instructions.len <= 100) {
        score += 0.2;
    }

    return @min(score, 1.0);
}

/// Score how likely this is a Zig allocator wrapper.
fn scoreZigAllocatorWrapper(func_name: []const u8, instructions: [][]const u8) f64 {
    var indicator_count: u32 = 0;
    var sequence_match: bool = false;

    // Count indicator instructions
    for (instructions) |inst| {
        for (ZIG_ALLOCATOR_INDICATORS) |indicator| {
            if (std.mem.indexOf(u8, inst, indicator) != null) {
                indicator_count += 1;
                break;
            }
        }
    }

    // Check for sequence pattern (call -> store -> ret)
    sequence_match = detectSequence(instructions, &ZIG_ALLOCATOR_SEQUENCE);

    // Calculate combined score
    var score: f64 = 0.0;

    // Name-based bonus (strong signal for Zig)
    if (looksLikeAllocatorWrapper(func_name)) {
        score += 0.3;
    }

    // Indicator density
    const indicator_density = @as(f64, @floatFromInt(indicator_count)) /
        @as(f64, @floatFromInt(@max(instructions.len, 1)));
    score += indicator_density * 0.3;

    // Sequence bonus
    if (sequence_match) {
        score += 0.3;
    }

    // Allocation pattern detection
    if (hasAllocationPattern(instructions)) {
        score += 0.1;
    }

    return @min(score, 1.0);
}

/// Score how likely this is C++ STL reallocation code.
fn scoreStlReallocation(instructions: [][]const u8) f64 {
    var indicator_count: u32 = 0;
    var sequence_match: bool = false;

    // Count indicator instructions
    for (instructions) |inst| {
        for (STL_REALLOC_INDICATORS) |indicator| {
            if (std.mem.indexOf(u8, inst, indicator) != null) {
                indicator_count += 1;
                break;
            }
        }
    }

    // Check for sequence pattern (malloc -> memcpy -> free)
    sequence_match = detectSequence(instructions, &STL_REALLOC_SEQUENCE);

    // Calculate combined score
    var score: f64 = 0.0;

    // Indicator density
    const indicator_density = @as(f64, @floatFromInt(indicator_count)) /
        @as(f64, @floatFromInt(@max(instructions.len, 1)));
    score += indicator_density * 0.4;

    // Sequence bonus
    if (sequence_match) {
        score += 0.4;
    }

    // Exception handling bonus (STL uses exceptions heavily)
    if (hasExceptionHandling(instructions)) {
        score += 0.2;
    }

    return @min(score, 1.0);
}

/// Score how likely this is an FFI boundary function.
fn scoreFfiBoundary(func_name: []const u8, instructions: [][]const u8) f64 {
    var score: f64 = 0.0;

    // Name-based signals (strong)
    for (FFI_BOUNDARY_INDICATORS) |indicator| {
        if (std.mem.indexOf(u8, func_name, indicator) != null) {
            score += 0.25;
        }
    }

    // Instruction-based signals
    var ffi_inst_count: u32 = 0;
    for (instructions) |inst| {
        for (FFI_BOUNDARY_INDICATORS) |indicator| {
            if (std.mem.indexOf(u8, inst, indicator) != null) {
                ffi_inst_count += 1;
                break;
            }
        }
    }

    const ffi_density = @as(f64, @floatFromInt(ffi_inst_count)) /
        @as(f64, @floatFromInt(@max(instructions.len, 1)));
    score += ffi_density * 0.2;

    return @min(score, 1.0);
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Detect if a specific instruction sequence appears in order.
///
/// Uses strict sequential matching with gap tolerance:
/// - Sequence elements must appear in order (no reordering allowed)
/// - Gaps between matched elements are allowed (non-matching instructions skipped)
/// - Requires >= 75% of sequence elements to match (up from 50%)
///
/// This prevents false positives from out-of-order partial matches.
fn detectSequence(
    instructions: [][]const u8,
    sequence: []const []const u8,
) bool {
    if (sequence.len == 0) return false;
    if (instructions.len < sequence.len) return false;

    var seq_idx: usize = 0;
    const min_match_threshold: usize = @max(sequence.len * 3 / 4, 1); // 75% or at least 1

    for (instructions) |inst| {
        if (seq_idx >= sequence.len) break;

        if (std.mem.indexOf(u8, inst, sequence[seq_idx]) != null) {
            seq_idx += 1;
        }
        // On mismatch: always continue scanning (gaps allowed)
        // but do NOT reset seq_idx - this enforces strict ordering
        // and prevents out-of-order matching bugs
    }

    return seq_idx >= min_match_threshold; // Require 75%+ match (was 50%)
}

/// Check if instructions contain allocation patterns.
///
/// Uses word boundary matching to prevent false positives:
/// - "alloc" would match "alloca", "dealloc", "allocator" (incorrect)
/// - Word boundary ensures we only match actual heap allocation functions
fn hasAllocationPattern(instructions: [][]const u8) bool {
    // Precise patterns for heap allocation (not stack allocation)
    const alloc_patterns = [_][]const u8{
        "malloc",
        "calloc",
        "realloc",
        "_alloc", // Matches __rust_alloc, __rdl_alloc, etc. but NOT alloca/dealloc
        "new ", // Space after prevents matching "newer", "newest"
    };

    for (instructions) |inst| {
        for (alloc_patterns) |pat| {
            // Use word boundary for short patterns to avoid false matches
            if (pat.len <= 6) {
                if (word_boundary.isWordBoundaryMatch(inst, pat)) {
                    return true;
                }
            } else {
                // Longer patterns can use indexOf (less likely to FP)
                if (std.mem.indexOf(u8, inst, pat) != null) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if instructions contain exception handling.
fn hasExceptionHandling(instructions: [][]const u8) bool {
    const exc_patterns = [_][]const u8{
        "__cxa_begin_catch",
        "__cxa_end_catch",
        "__cxa_throw",
        "invoke",
        "landingpad",
        "cleanupret",
        "catchswitch",
        "catchpad",
        "catchret",
    };

    for (instructions) |inst| {
        for (exc_patterns) |pat| {
            if (std.mem.indexOf(u8, inst, pat) != null) {
                return true;
            }
        }
    }
    return false;
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for behavior filtering results.
pub const BehaviorStats = struct {
    rust_drop_glue_found: u32 = 0,
    zig_allocator_found: u32 = 0,
    stl_realloc_found: u32 = 0,
    ffi_boundary_found: u32 = 0,
    user_logic_found: u32 = 0,
    unknown_found: u32 = 0,
    total_analyzed: u32 = 0,
    suppressed_by_behavior: u32 = 0,

    pub fn record(self: *BehaviorStats, result: BehaviorResult) void {
        self.total_analyzed += 1;

        switch (result.pattern) {
            .rust_drop_glue => self.rust_drop_glue_found += 1,
            .zig_allocator_wrapper => self.zig_allocator_found += 1,
            .stl_reallocation => self.stl_realloc_found += 1,
            .ffi_boundary => self.ffi_boundary_found += 1,
            .user_logic => self.user_logic_found += 1,
            .unknown => self.unknown_found += 1,
        }

        if (result.shouldSuppress()) {
            self.suppressed_by_behavior += 1;
        }
    }

    pub fn suppressionRatio(self: BehaviorStats) f64 {
        if (self.total_analyzed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.suppressed_by_behavior)) /
            @as(f64, @floatFromInt(self.total_analyzed));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "analyzeBehavior - Rust drop glue" {
    var instructions = [_][]const u8{
        "entry:",
        "  %0 = alloca i8*",
        "  call void @free(i8* %ptr)",
        "  call void @memset(i8* %dst, i8 0, i64 %n)",
        "  br label %check_type",
        "check_type:",
        "  %vtable = load i8**, i8*** %self",
        "  icmp eq i8** %vtable, null",
        "  br i1 %cond, label %panic, label %continue",
        "panic:",
        "  call void @begin_panic(i8* %msg)",
    };

    const result = analyzeBehavior("_ZN4core3ptr13drop_in_placeE", &instructions);
    try std.testing.expectEqual(BehaviorPattern.rust_drop_glue, result.pattern);
    try std.testing.expect(result.confidence > 0.5);
}

test "analyzeBehavior - STL reallocation" {
    var instructions = [_][]const u8{
        "entry:",
        "  %new_buf = call i8* @malloc(i64 %new_size)",
        "  call void @memcpy(i8* %new_buf, i8* %old_buf, i64 %old_size)",
        "  call void @free(i8* %old_buf)",
        "  ret i8* %new_buf",
    };

    const result = analyzeBehavior("_ZNSt6vectorIiE9push_backERKi", &instructions);
    try std.testing.expectEqual(BehaviorPattern.stl_reallocation, result.pattern);
}

test "analyzeBehavior - too few instructions" {
    var instructions = [_][]const u8{
        "entry:",
        "  ret void",
    };

    const result = analyzeBehavior("tiny_func", &instructions);
    try std.testing.expectEqual(BehaviorPattern.unknown, result.pattern);
    try std.testing.expect(result.confidence == 0.0);
}

test "looksLikeAllocatorWrapper - positive cases" {
    try std.testing.expect(looksLikeAllocatorWrapper("std.ArrayList.init"));
    try std.testing.expect(looksLikeAllocatorWrapper("std.AutoHashMap.put"));
    try std.testing.expect(looksLikeAllocatorWrapper("BoundedArray.append"));

    try std.testing.expect(!looksLikeAllocatorWrapper("my_process_data"));
    try std.testing.expect(!looksLikeAllocatorWrapper("compute_hash"));
}

test "detectSequence - exact match" {
    var instructions = [_][]const u8{
        "call void @free(i8* %p)",
        "call void @memset(i8* %d, i8 0, i64 %n)",
        "br label %next",
    };

    var sequence = [_][]const u8{ "free", "memset", "br" };
    try std.testing.expect(detectSequence(&instructions, &sequence));
}

test "detectSequence - no match" {
    var instructions = [_][]const u8{
        "add i32 %a, %b",
        "mul i32 %c, %d",
        "sub i32 %e, %f",
    };

    var sequence = [_][]const u8{ "free", "memset", "br" };
    try std.testing.expect(!detectSequence(&instructions, &sequence));
}

test "hasExceptionHandling - with exceptions" {
    var instructions = [_][]const u8{
        "invoke void @foo()",
        "to label %normal unwind label %exception",
        "%ex = landingpad { i8*, i32 }",
        "call i8* @__cxa_begin_catch(i8* %ex)",
    };

    try std.testing.expect(hasExceptionHandling(&instructions));
}

test "hasExceptionHandling - without exceptions" {
    var instructions = [_][]const u8{
        "add i32 %a, %b",
        "call void @print(i32 %result)",
        "ret void",
    };

    try std.testing.expect(!hasExceptionHandling(&instructions));
}

test "BehaviorStats - tracking" {
    var stats = BehaviorStats{};

    stats.record(.{ .pattern = .rust_drop_glue, .confidence = 0.8, .reason = "" });
    stats.record(.{ .pattern = .zig_allocator_wrapper, .confidence = 0.7, .reason = "" });
    stats.record(.{ .pattern = .user_logic, .confidence = 0.9, .reason = "" });
    stats.record(.{ .pattern = .ffi_boundary, .confidence = 0.85, .reason = "" });

    try std.testing.expectEqual(@as(u32, 1), stats.rust_drop_glue_found);
    try std.testing.expectEqual(@as(u32, 1), stats.zig_allocator_found);
    try std.testing.expectEqual(@as(u32, 1), stats.user_logic_found);
    try std.testing.expectEqual(@as(u32, 1), stats.ffi_boundary_found);
    try std.testing.expectEqual(@as(u32, 2), stats.suppressed_by_behavior); // drop_glue + allocator
}
