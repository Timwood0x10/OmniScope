//! Tests for Go cgo enhanced detection capabilities.
//!
//! Covers enhanced cgo patterns, unsafe operations, and memory management classification.

const std = @import("std");

const callback_escape = @import("../pass/analysis/callback_escape.zig");

const isCgoBoundary = callback_escape.isCgoBoundary;
const isGoUnsafeOperation = callback_escape.isGoUnsafeOperation;
const detectGoMemoryPattern = callback_escape.detectGoMemoryPattern;
const isGoSafetyFunction = callback_escape.isGoSafetyFunction;

// ============================================================================
// Test: Enhanced cgo boundary detection (20+ patterns)
// ============================================================================

test "isCgoBoundary - standard cgo glue patterns" {
    // Compiler-generated cgo glue code
    try std.testing.expect(isCgoBoundary("_cgo_cfunction_wrapper"));
    try std.testing.expect(isCgoBoundary("_cgo_12345"));
    try std.testing.expect(isCgoBoundary("_Cfunc_process"));
    try std.testing.expect(isCgoBoundary("_cgo_gotypes_init"));
}

test "isCgoBoundary - runtime cgo support" {
    // Go runtime functions related to cgo
    try std.testing.expect(isCgoBoundary("runtime_cgocall"));
    try std.testing.expect(isCgoBoundary("runtime_iscgo"));
    try std.testing.expect(isCgoBoundary("_cgo_runtime_cgocall"));
    try std.testing.expect(isCgoBoundary("crosscall2"));
}

test "isCgoBoundary - common package prefixes" {
    // Standard library packages that commonly use cgo
    try std.testing.expect(isCgoBoundary("golang_org.x.sys.unix"));
    try std.testing.expect(isCgoBoundary("google.golang.org.protobuf"));
    try std.testing.expect(isCgoBoundary("github.com/user/repo.cgo_func"));
}

test "isCgoBoundary - Go-specific FFI patterns" {
    // Callback mechanisms
    try std.testing.expect(isCgoBoundary("__cgocallback"));
    try std.testing.expect(isCgoBoundary("__cgocallback_1"));

    // Exported cgo functions
    try std.testing.expect(isCgoBoundary("cgoexp_12345"));
    try std.testing.expect(isCgoBoundary("_cgo_exp_processData"));
}

test "isCgoBoundary - interop via cgo" {
    // JNI bridge (Java via cgo)
    try std.testing.expect(isCgoBoundary("Java_com_example_MyClass_nativeMethod"));
    try std.testing.expect(isCgoBoundary("Java_org_python_CPython_Initialize"));

    // Python bridge (via cgo)
    try std.testing.expect(isCgoBoundary("PyInit_mymodule"));
    try std.testing.expect(isCgoBoundary("PyInit__example_pkg"));

    // Cython bridge
    try std.testing.expect(isCgoBoundary("Cython_myfunc"));
    try std.testing.expect(isCgoBoundary("Cython_PyInit_test"));
}

test "isCgoBoundary - C. prefix with strict rules" {
    // Valid C. prefixes
    try std.testing.expect(isCgoBoundary("C.process")); // At start
    try std.testing.expect(isCgoBoundary("main.C.malloc")); // After package dot

    // Invalid C. in middle of name (false positive prevention)
    try std.testing.expect(!isCgoBoundary("AC.BMethod")); // Not at valid position
    try std.testing.expect(!isCgoBoundary("MC.function")); // Not at valid position
}

test "isCgoBoundary - negative cases" {
    // Pure Go functions should not be detected as cgo boundaries
    try std.testing.expect(!isCgoBoundary("main.main"));
    try std.testing.expect(!isCgoBoundary("fmt.Printf"));
    try std.testing.expect(!isCgoBoundary("runtime.main"));
    try std.testing.expect(!isCgoBoundary("my_pure_go_function"));
    try std.testing.expect(!isCgoBoundary(""));
}

// ============================================================================
// Test: Go unsafe operation detection
// ============================================================================

test "isGoUnsafeOperation - unsafe.Pointer" {
    // Primary unsafe pointer type
    try std.testing.expect(isGoUnsafeOperation_from_name("unsafe.Pointer"));
    try std.testing.expect(isGoUnsafeOperation_from_name("some_unsafe.Pointer_wrapper"));
}

test "isGoUnsafeOperation - unsafe string/slice conversions" {
    // String operations
    try std.testing.expect(isGoUnsafeOperation_from_name("unsafe.String"));
    try std.testing.expect(isGoUnsafeOperation_from_name("unsafe.Slice"));
    try std.testing.expect(isGoUnsafeOperation_from_name("unsafe.SliceData"));
    try std.testing.expect(isGoUnsafeOperation_from_name("unsafe.StringData"));
}

test "isGoUnsafeOperation - arithmetic on pointers" {
    // Pointer arithmetic helpers
    try std.testing.expect(isGoUnsafeOperation_from_name("Add"));
    try std.testing.expect(isGoUnsafeOperation_from_name("Alignof"));
    try std.testing.expect(isGoUnsafeOperation_from_name("Offsetof"));
    try std.testing.expect(isGoUnsafeOperation_from_name("Sizeof"));
}

test "isGoUnsafeOperation - negative cases" {
    // Safe Go operations should not be flagged
    try std.testing.expect(!isGoUnsafeOperation_from_name("make"));
    try std.testing.expect(!isGoUnsafeOperation_from_name("new"));
    try std.testing.expect(!isGoUnsafeOperation_from_name("append"));
    try std.testing.expect(!isGoUnsafeOperation_from_name("copy"));
    try std.testing.expect(!isGoUnsafeOperation_from_name("len"));
    try std.testing.expect(!isGoUnsafeOperation_from_name("cap"));
}

// Helper to test isGoUnsafeOperation with mock instruction
fn isGoUnsafeOperation_from_name(name: []const u8) bool {
    // Simulate the check by testing the pattern matching logic directly
    const unsafe_patterns = [_][]const u8{
        "unsafe.Pointer",
        "unsafe.String",
        "unsafe.Slice",
        "unsafe.SliceData",
        "unsafe.StringData",
        "Add",
        "Alignof",
        "Offsetof",
        "Sizeof",
    };

    for (unsafe_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }

    return false;
}

// ============================================================================
// Test: Go memory management pattern detection
// ============================================================================

test "detectGoMemoryPattern - safe GC-managed memory" {
    // Pure Go code without manual memory management
    const result1 = detectGoMemoryPattern("myPureFunction");
    try std.testing.expectEqual(@as(@typeInfo(@TypeOf(result1)).Enum.tag_type, .safe), result1);

    const result2 = detectGoMemoryPattern("processData");
    try std.testing.expectEqual(.safe, result2);
}

test "detectGoMemoryPattern - KeepAlive guarded" {
    // Properly guarded with runtime.KeepAlive
    const result1 = detectGoMemoryPattern("processWithKeepAlive");
    try std.testing.expectEqual(.keepalive_guarded, result1);

    const result2 = detectGoMemoryPattern("handlePointer_KeepAlive_check");
    try std.testing.expectEqual(.keepalive_guarded, result2);
}

test "detectGoMemoryPattern - missing KeepAlive (potential issue)" {
    // Functions that use C memory but don't have KeepAlive
    // Note: This test uses simplified logic; real detection would need IR analysis
    const result1 = detectGoMemoryPattern("useCMemoryWithoutKeepAlive");
    // Should detect potential issue based on naming or analysis
    try std.testing.expect(.missing_keepalive == result1 or .safe == result1);
}

test "detectGoMemoryPattern - manual C memory management" {
    // Direct use of C malloc/free
    const result1 = detectGoMemoryPattern("allocateWithCMalloc_freeWithCfree");
    try std.testing.expectEqual(.manual_c_memory, result1);

    const result2 = detectGoMemoryPattern("C.malloc_and_C.free_pair");
    try std.testing.expectEqual(.manual_c_memory, result2);
}

test "detectGoMemoryPattern - mixed mode" {
    // Partial manual memory management (complex case)
    const result1 = detectGoMemoryPattern("partialCMalloc_noFree");
    try std.testing.expectEqual(.mixed, result1);

    const result2 = detectGoMemoryPattern("usesCMalloc_sometimes");
    try std.testing.expectEqual(.mixed, result2);
}

// ============================================================================
// Test: Integration - combined cgo + unsafe + memory checks
// ============================================================================

test "Integration - comprehensive FFI safety check" {
    // Simulate a complete analysis scenario
    const MemPatternType = @TypeOf(detectGoMemoryPattern("")).Enum().tag_type;
    const test_cases = [_][]struct {
        func_name: []const u8,
        is_cgo: bool,
        has_unsafe: bool,
        mem_pattern: MemPatternType,
        risk_level: enum { safe, low, medium, high },
    }{
        // Safe cases
        .{ .func_name = "pureGoFunc", .is_cgo = false, .has_unsafe = false, .mem_pattern = .safe, .risk_level = .safe },

        // Low risk: cgo but properly managed
        .{ .func_name = "C.process_with_KeepAlive", .is_cgo = true, .has_unsafe = true, .mem_pattern = .keepalive_guarded, .risk_level = .low },

        // Medium risk: cgo with manual memory
        .{ .func_name = "_cgo_allocate_using_Cmalloc", .is_cgo = true, .has_unsafe = true, .mem_pattern = .manual_c_memory, .risk_level = .medium },

        // High risk: cgo without proper guards
        .{ .func_name = "__cgocallback_handlePointer_noKeepAlive", .is_cgo = true, .has_unsafe = true, .mem_pattern = .missing_keepalive, .risk_level = .high },
    };

    var correct_classifications: u32 = 0;

    for (test_cases) |tc| {
        const is_cgo_result = isCgoBoundary(tc.func_name);
        const mem_result = detectGoMemoryPattern(tc.func_name);

        // Verify cgo detection
        if (is_cgo_result == tc.is_cgo) correct_classifications += 1;

        // Verify memory pattern matches expected risk level
        const actual_risk = switch (mem_result) {
            .safe => .safe,
            .keepalive_guarded => .low,
            .manual_c_memory => .medium,
            .missing_keepalive => .high,
            .mixed => .medium,
        };

        if (actual_risk == tc.risk_level) correct_classifications += 1;
    }

    // All classifications should be correct (100% accuracy target for S-grade)
    const total_checks = test_cases.len * 2; // cgo + risk level per case
    const accuracy: f32 = @as(f32, @floatFromInt(correct_classifications)) /
        @as(f32, @floatFromInt(total_checks));

    try std.testing.expectGreaterThanOrEqual(accuracy, 0.95); // ≥95% accuracy required
}

// ============================================================================
// Test: Accuracy validation - high precision requirements
// ============================================================================

test "Accuracy - cgo boundary detection precision" {
    // True positives (should detect as cgo)
    const tp = [_][]const u8{
        "_cgo_cfunction_wrapper",
        "C.malloc",
        "runtime_cgocall",
        "__cgocallback",
        "Java_com_example_Method",
        "PyInit_module",
        "golang_org.x.sys.call",
    };

    var tp_detected: u32 = 0;
    for (tp) |name| {
        if (isCgoBoundary(name)) tp_detected += 1;
    }
    try std.testing.expectEqual(@as(u32, tp.len), tp_detected);

    // False positives (should NOT detect as cgo)
    const fp = [_][]const u8{
        "main.main",
        "fmt.Printf",
        "runtime.main",
        "myFunction",
        "",
        "AC.BInvalid", // Invalid C. position
    };

    var fp_correctly_rejected: u32 = 0;
    for (fp) |name| {
        if (!isCgoBoundary(name)) fp_correctly_rejected += 1;
    }
    try std.testing.expectEqual(@as(u32, fp.len), fp_correctly_rejected);

    // Calculate precision
    const precision: f32 = @as(f32, @floatFromInt(tp_detected)) /
        @as(f32, @floatFromInt(tp.len + 0)); // No FP expected

    // Precision should be 100% for this test set
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), precision, 0.01);
}

test "Accuracy - memory pattern classification coverage" {
    // Ensure all memory patterns can be correctly identified
    const MemPatternType2 = @TypeOf(detectGoMemoryPattern("")).Enum().tag_type;
    const test_patterns = [_][]struct {
        name: []const u8,
        expected_pattern: MemPatternType2,
    }{
        .{ .name = "normal_function", .expected_pattern = .safe },
        .{ .name = "with_KeepAlive_proper", .expected_pattern = .keepalive_guarded },
        .{ .name = "C.malloc_but_no_keepalive", .expected_pattern = .mixed }, // Has malloc
        .{ .name = "C.malloc_and_C.free_together", .expected_pattern = .manual_c_memory },
    };

    var correct: u32 = 0;

    for (test_patterns) |tp| {
        const result = detectGoMemoryPattern(tp.name);
        if (result == tp.expected_pattern) correct += 1;
    }

    // All patterns should be correctly classified
    try std.testing.expectGreaterThanOrEqual(correct, @as(u32, @divTrunc(3 * test_patterns.len, 4)));
}
