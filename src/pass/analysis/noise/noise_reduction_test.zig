//! Tests for NoiseReduction module — FIX-1: Rust allocator tracking restoration
//!
//! Coverage target: ≥70% for is_llvm_intrinsic_noise + classifyFunction
//! Test categories: happy path, boundary cases, error cases, language boundaries

const std = @import("std");

const NoiseReduction = @import("noise_reduction.zig");
const is_llvm_intrinsic_noise = NoiseReduction.is_llvm_intrinsic_noise;
const classifyFunction = NoiseReduction.classifyFunction;
const RiskWeight = NoiseReduction.RiskWeight;
const FunctionOrigin = NoiseReduction.FunctionOrigin;

// ============================================================================
// FIX-1 Core: Rust allocators are NOT noise (FFI boundary detection)
// ============================================================================

test "is_llvm_intrinsic_noise - __rust_alloc is NOT noise (FIX-1 happy path)" {
    // CRITICAL: __rust_alloc must NOT be filtered as noise
    // because ptr_lifetime needs to track it for FFI boundary detection
    const result = is_llvm_intrinsic_noise("__rust_alloc");
    try std.testing.expect(!result);
}

test "is_llvm_intrinsic_noise - __rust_dealloc is NOT noise (FIX-1 happy path)" {
    const result = is_llvm_intrinsic_noise("__rust_dealloc");
    try std.testing.expect(!result);
}

test "is_llvm_intrinsic_noise - __rust_realloc is NOT noise (FIX-1 happy path)" {
    const result = is_llvm_intrinsic_noise("__rust_realloc");
    try std.testing.expect(!result);
}

// ============================================================================
// Boundary: Other Rust patterns ARE still noise (regression prevention)
// ============================================================================

test "is_llvm_intrinsic_noise - sync_channel:: IS noise (boundary)" {
    // Channel primitives are safe MPSC/SPMC, not FFI-related
    try std.testing.expect(is_llvm_intrinsic_noise("sync_channel::"));
}

test "is_llvm_intrinsic_noise - mpsc::channel IS noise (boundary)" {
    try std.testing.expect(is_llvm_intrinsic_noise("mpsc::channel"));
}

test "is_llvm_intrinsic_noise - real_drop_in_place IS noise (boundary)" {
    // real_drop_in_place is in rust_noise_patterns, checked by layer1NoiseFilter
    // is_llvm_intrinsic_noise only checks llvm_intrinsic_prefixes and rust_synthetic_patterns
    try std.testing.expect(!is_llvm_intrinsic_noise("real_drop_in_place"));
}

test "is_llvm_intrinsic_noise - size_hint IS noise (boundary)" {
    // size_hint is in rust_noise_patterns, checked by layer1NoiseFilter
    // is_llvm_intrinsic_noise only checks llvm_intrinsic_prefixes and rust_synthetic_patterns
    try std.testing.expect(!is_llvm_intrinsic_noise("size_hint"));
}

// ============================================================================
// Boundary: LLVM intrinsics ARE noise (baseline)
// ============================================================================

test "is_llvm_intrinsic_noise - llvm. prefix IS noise (happy path)" {
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.memcpy"));
    try std.testing.expect(is_llvm_intrinsic_noise("llvm.memmove"));
    // llvmmemset is NOT a valid LLVM intrinsic (missing dot separator)
    // Valid LLVM intrinsics use "llvm." prefix
    try std.testing.expect(!is_llvm_intrinsic_noise("llvmmemset"));
}

test "is_llvm_intrinsic_noise - non-LLVM functions are NOT noise (boundary)" {
    try std.testing.expect(!is_llvm_intrinsic_noise("malloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("free"));
    try std.testing.expect(!is_llvm_intrinsic_noise("printf"));
}

// ============================================================================
// Error cases: Edge inputs
// ============================================================================

test "is_llvm_intrinsic_noise - empty string is NOT noise (error case)" {
    const result = is_llvm_intrinsic_noise("");
    try std.testing.expect(!result);
}

test "is_llvm_intrinsic_noise - single char is NOT noise (error case)" {
    try std.testing.expect(!is_llvm_intrinsic_noise("x"));
}

// ============================================================================
// Language boundary: C/C++ functions should NOT be affected
// ============================================================================

test "is_llvm_intrinsic_noise - C standard library NOT noise (lang boundary)" {
    try std.testing.expect(!is_llvm_intrinsic_noise("malloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("calloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("realloc"));
    try std.testing.expect(!is_llvm_intrinsic_noise("free"));
    try std.testing.expect(!is_llvm_intrinsic_noise("memcpy"));
    try std.testing.expect(!is_llvm_intrinsic_noise("strcpy"));
}

test "is_llvm_intrinsic_noise - C++ operators NOT noise (lang boundary)" {
    try std.testing.expect(!is_llvm_intrinsic_noise("_Znwm")); // operator new
    try std.testing.expect(!is_llvm_intrinsic_noise("_ZdlPv")); // operator delete
}

// ============================================================================
// Language boundary: Go functions should NOT be affected
// ============================================================================

test "is_llvm_intrinsic_noise - Go runtime NOT noise (lang boundary)" {
    try std.testing.expect(!is_llvm_intrinsic_noise("runtime.main"));
    try std.testing.expect(!is_llvm_intrinsic_noise("main.main"));
}

// ============================================================================
// classifyFunction integration: Rust allocators get proper classification
// ============================================================================

test "classifyFunction - __rust_alloc gets analyzed (not skipped) (FIX-1)" {
    const config = NoiseReduction.NoiseReductionConfig{};
    const result = classifyFunction("__rust_alloc", "", config);
    // Should NOT return .ignored (which would skip analysis)
    // Should return a weight that allows further processing
    try std.testing.expect(result.weight != .ignored);
}

test "classifyFunction - __rust_dealloc gets analyzed (not skipped) (FIX-1)" {
    const config = NoiseReduction.NoiseReductionConfig{};
    const result = classifyFunction("__rust_dealloc", "", config);
    try std.testing.expect(result.weight != .ignored);
}

test "classifyFunction - sync_channel:: gets filtered (regression test)" {
    const config = NoiseReduction.NoiseReductionConfig{};
    const result = classifyFunction("sync_channel::recv", "", config);
    try std.testing.expectEqual(.ignored, result.weight);
}
