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

    // Indicator density (normalized)
    const indicator_density = @as(f64, @floatFromInt(indicator_count)) /
        @as(f64, @floatFromInt(@max(instructions.len, 1)));
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
fn detectSequence(
    instructions: [][]const u8,
    sequence: []const []const u8,
) bool {
    if (sequence.len == 0) return false;
    if (instructions.len < sequence.len) return false;

    var seq_idx: usize = 0;

    for (instructions) |inst| {
        if (seq_idx >= sequence.len) break;

        if (std.mem.indexOf(u8, inst, sequence[seq_idx]) != null) {
            seq_idx += 1;
        } else if (seq_idx > 0) {
            // Reset if we lose the sequence (allow gaps)
            // Only reset partially - we want some tolerance
            if (seq_idx > sequence.len / 2) {
                seq_idx = 0; // Full reset
            }
        }
    }

    return seq_idx >= sequence.len / 2; // Allow partial matches
}

/// Check if instructions contain allocation patterns.
fn hasAllocationPattern(instructions: [][]const u8) bool {
    const alloc_patterns = [_][]const u8{
        "malloc",
        "calloc",
        "realloc",
        "alloc",
        "new ",
    };

    for (instructions) |inst| {
        for (alloc_patterns) |pat| {
            if (std.mem.indexOf(u8, inst, pat) != null) {
                return true;
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

test "analyzeBehavior - Zig allocator wrapper" {
    var instructions = [_][]const u8{
        "entry:",
        "  %result = call i8* @allocator.alloc(i64 %size)",
        "  store i64 %len, i64* %result_len",
        "  store i64 %cap, i64* %result_cap",
        "  ret i8* %result",
    };

    const result = analyzeBehavior("std.ArrayList.append", &instructions);
    try std.testing.expectEqual(BehaviorPattern.zig_allocator_wrapper, result.pattern);
    try std.testing.expect(result.shouldSuppress() == true);
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

test "analyzeBehavior - FFI boundary" {
    var instructions = [_][]const u8{
        "entry:",
        "  %handle = call i8* @dlopen(i8* %path, i32 %mode)",
        "  %func = call i8* @dlsym(i8* %handle, i8* %symbol)",
        "  call void %func(i8* %data)",
        "  ret void",
    };

    const result = analyzeBehavior("load_native_library", &instructions);
    try std.testing.expectEqual(BehaviorPattern.ffi_boundary, result.pattern);
    try std.testing.expect(result.shouldSuppress() == false);
}

test "analyzeBehavior - user logic" {
    var instructions = [_][]const u8{
        "entry:",
        "  %sum = add i32 %a, %b",
        "  %product = mul i32 %sum, %c",
        "  ret i32 %product",
    };

    const result = analyzeBehavior("calculate_total", &instructions);
    try std.testing.expectEqual(BehaviorPattern.user_logic, result.pattern);
    try std.testing.expect(result.shouldSuppress() == false);
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

test "looksLikeDropGlue - positive cases" {
    try std.testing.expect(looksLikeDropGlue("core::ptr::drop_in_place"));
    try std.testing.expect(looksLikeDropGlue("__rust_dealloc"));
    try std.testing.expect(looksLikeDropGlue("__destroy_with_cleanup"));

    try std.testing.expect(!looksLikeDropGlue("my_user_function"));
    try std.testing.expect(!looksLikeDropGlue("process_data"));
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
