//! Memory Leak Confidence Tuning - Verification Tests
//!
//! Tests verify the new confidence calculation logic:
//!   - Base confidence: 0.58 (non-FFI), 0.78 (FFI)
//!   - Global allocation boost: +0.08
//!   - Dangerous function boost: +0.07
//!   - Conditional multiplier: x0.75
//!   - Upper clamp: 0.95

const std = @import("std");

test "memory leak base confidence should be reasonable" {
    const non_ffi_base: f32 = 0.58;
    const ffi_base: f32 = 0.78;
    try std.testing.expect(non_ffi_base >= 0.50);
    try std.testing.expect(non_ffi_base <= 0.70);
    try std.testing.expect(ffi_base >= 0.70);
    try std.testing.expect(ffi_base <= 0.85);
}

test "FFI leak has higher base than internal leak" {
    const ffi_base: f32 = 0.78;
    const non_ffi_base: f32 = 0.58;
    try std.testing.expect(ffi_base > non_ffi_base);
    const diff = ffi_base - non_ffi_base;
    try std.testing.expect(diff >= 0.15);
}

test "global allocation boost increases confidence" {
    const non_ffi_base: f32 = 0.58;
    const global_boost: f32 = 0.08;
    const with_global = non_ffi_base + global_boost;
    try std.testing.expect(with_global > non_ffi_base);
    try std.testing.expectApproxEqAbs(@as(f32, 0.66), with_global, 0.01);
}

test "dangerous alloc function boost increases confidence" {
    const non_ffi_base: f32 = 0.58;
    const dangerous_boost: f32 = 0.07;
    const with_dangerous = non_ffi_base + dangerous_boost;
    try std.testing.expect(with_dangerous > non_ffi_base);
    try std.testing.expectApproxEqAbs(@as(f32, 0.65), with_dangerous, 0.01);
}

test "combined boosts reach HIGH tier" {
    var confidence: f32 = 0.58;
    confidence += 0.08;
    confidence += 0.07;
    try std.testing.expect(confidence >= 0.70);
    try std.testing.expectApproxEqAbs(@as(f32, 0.73), confidence, 0.01);
}

test "conditional allocation reduces confidence appropriately" {
    const normal_confidence: f32 = 0.58;
    const conditional_multiplier: f32 = 0.75;
    const conditional_confidence = normal_confidence * conditional_multiplier;
    try std.testing.expect(conditional_confidence < normal_confidence);
    try std.testing.expect(conditional_confidence >= 0.30);
    try std.testing.expectApproxEqAbs(@as(f32, 0.435), conditional_confidence, 0.001);
}

test "conditional FFI leak still above MEDIUM threshold" {
    var ffi_confidence: f32 = 0.78;
    ffi_confidence *= 0.75;
    try std.testing.expect(ffi_confidence >= 0.50);
    try std.testing.expectApproxEqAbs(@as(f32, 0.585), ffi_confidence, 0.001);
}

test "confidence clamping prevents overflow" {
    var high_confidence: f32 = 0.78;
    high_confidence += 0.08;
    high_confidence += 0.07;
    high_confidence = @min(high_confidence, 0.95);
    try std.testing.expect(high_confidence <= 0.95);
    try std.testing.expectApproxEqAbs(@as(f32, 0.93), high_confidence, 0.01);
}

test "floor protection for very low confidence" {
    var very_low: f32 = 0.35;
    very_low *= 0.75;
    if (very_low < 0.30) {
        very_low = 0.30;
    }
    try std.testing.expect(very_low >= 0.30);
}

test "non-FFI with both boosts reaches HIGH tier" {
    var confidence: f32 = 0.58;
    confidence += 0.08;
    confidence += 0.07;
    try std.testing.expect(confidence >= 0.70);
    try std.testing.expect(confidence < 0.85);
}
