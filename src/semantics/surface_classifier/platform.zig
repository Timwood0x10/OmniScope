//! Platform Hint Integration for SurfaceClassifier
//!
//! This module provides the bridge between platform detection and the
//! SurfaceClassifierPass. It converts PlatformProfile, RuntimeClassification,
//! and PathProvenance into FunctionSurface hints that participate in the
//! mergeLayers() decision.
//!
//! Design Principles (from todolist.md):
//! - P7: Platform hints are merged into SurfaceClassifier as one layer among many
//! - P8: Boundary and unknown surfaces always take priority over platform runtime hints
//! - Safety first: when platform info conflicts with other signals, keep analyzing

const std = @import("std");
const log = std.log.scoped(.platform_surface);

const PlatformProfile = @import("../../semantics/platform_profile.zig").PlatformProfile;
const PlatformNormalizer = @import("../../semantics/platform_normalizer.zig");
const PlatformRuntime = @import("../../semantics/platform_runtime.zig");

const FunctionSurface = @import("surface_classifier.zig").FunctionSurface;
const Confidence = @import("surface_classifier.zig").Confidence;

/// Platform-derived surface hint for a function.
///
/// This struct captures all platform-related information that influences
/// how a function should be classified by the SurfaceClassifier.
pub const PlatformSurfaceHint = struct {
    /// Suggested surface classification based on platform evidence alone.
    /// Note: This is only a HINT — the final decision is made by mergeLayers().
    suggested_surface: FunctionSurface,

    /// Confidence in this suggestion (0.0-1.0).
    confidence: Confidence,

    /// Human-readable reason for this suggestion.
    reason: []const u8,

    /// Detailed runtime classification (if applicable).
    runtime_category: ?PlatformRuntime.RuntimeCategory,
};

/// Generate a platform-based surface hint for a function.
///
/// This function examines the function name through multiple platform-specific
/// lenses and produces a consolidated hint that can be fed into mergeLayers().
///
/// Arguments:
///   func_name - Canonicalized function name (after symbol normalization)
///   profile   - Current platform profile (must not be null)
///
/// Returns:
///   PlatformSurfaceHint with suggestion, confidence, and reasoning
pub fn generatePlatformHint(func_name: []const u8, profile: *const PlatformProfile) PlatformSurfaceHint {
    // Step 1: Check if it's a known runtime / compiler-generated shim
    const runtime_class = PlatformRuntime.classifyRuntimeFunction(func_name, profile);

    if (runtime_class.is_runtime) {
        // Map runtime category to surface suggestion
        const surface = runtimeToSurface(runtime_class.category);

        return .{
            .suggested_surface = surface,
            .confidence = if (runtime_class.confidence >= 0.9) .high else if (runtime_class.confidence >= 0.7) .medium else .low,
            .reason = runtime_class.reason,
            .runtime_category = runtime_class.category,
        };
    }

    // Step 2: Check basic shim patterns (from normalizer)
    if (PlatformNormalizer.isPlatformRuntimeShim(func_name, profile)) {
        return .{
            .suggested_surface = .compiler_generated,
            .confidence = .high,
            .reason = "matches universal runtime prefix pattern",
            .runtime_category = null,
        };
    }

    // Step 3: No strong platform signal → suggest unknown (keep analyzing)
    return .{
        .suggested_surface = .unknown,
        .confidence = .low,
        .reason = "no strong platform runtime pattern detected",
        .runtime_category = null,
    };
}

/// Merge platform hint into final surface decision.
///
/// Implements P8 design principle:
/// **Boundary and unknown surfaces ALWAYS take priority over platform runtime hints.**
///
/// Arguments:
///   current_surface - Surface from previous layers (L1-L4)
///   platform_hint   - Platform-derived hint (may be null)
///   is_boundary     - Whether this function is an FFI boundary
///
/// Returns:
///   Final surface after considering platform information
pub fn mergePlatformHint(
    current_surface: FunctionSurface,
    platform_hint: ?PlatformSurfaceHint,
    is_boundary: bool,
) FunctionSurface {
    // P8: Boundary functions are NEVER downgraded by platform rules
    if (is_boundary or current_surface == .boundary) {
        return .boundary;
    }

    // P8: Unknown surface is preserved (safety first)
    if (current_surface == .unknown) {
        return .unknown;
    }

    // If no platform hint, keep current surface
    const hint = platform_hint orelse return current_surface;

    // Apply platform hint based on confidence
    switch (hint.confidence) {
        .high => {
            // High-confidence platform hint can override user_code/dependency
            // but NOT boundary or unknown (handled above)
            switch (current_surface) {
                .user_code, .dependency => {
                    return hint.suggested_surface;
                },
                else => {
                    // Don't downgrade existing classifications
                    return current_surface;
                },
            }
        },
        .medium => {
            // Medium-confidence hint only influences if current is user_code
            if (current_surface == .user_code) {
                return hint.suggested_surface;
            }
            return current_surface;
        },
        .low => {
            // Low-confidence hint is ignored
            return current_surface;
        },
    }
}

// ============================================================================
// Internal Helpers
// ============================================================================

/// Map runtime category to suggested FunctionSurface.
fn runtimeToSurface(category: PlatformRuntime.RuntimeCategory) FunctionSurface {
    return switch (category) {
        // Standard library / allocator → standard_library (skip heavy analysis)
        .libc, .cpp_allocator, .cpp_abi => .standard_library,

        // Language runtimes → runtime (skip analysis)
        .objc_runtime, .swift_runtime, .gcd_runtime, .go_runtime, .rust_runtime, .zig_runtime => .runtime,

        // Compiler intrinsics → compiler_generated (skip)
        .llvm_intrinsic, .profiling, .exception_handler, .static_init, .static_fini, .tls_init, .stack_protection, .dynamic_linker => .compiler_generated,

        // Sanitizers → runtime (instrumentation code)
        .sanitizer => .runtime,

        // Unknown → conservative: standard_library
        .unknown => .standard_library,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "generatePlatformHint - C++ allocator" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "x86_64-pc-linux-gnu",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    const hint = generatePlatformHint("_Znam", &profile); // operator new[]
    try std.testing.expectEqual(FunctionSurface.standard_library, hint.suggested_surface);
    try std.testing.expectEqual(Confidence.high, hint.confidence);
    try std.testing.expect(hint.runtime_category != null);
}

test "generatePlatformHint - user code" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "x86_64-pc-linux-gnu",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    const hint = generatePlatformHint("myFunction", &profile);
    try std.testing.expectEqual(FunctionSurface.unknown, hint.suggested_surface);
    try std.testing.expectEqual(Confidence.low, hint.confidence);
}

test "mergePlatformHint - boundary takes priority (P8)" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .compiler_generated,
        .confidence = .high,
        .reason = "C++ operator new[]",
        .runtime_category = .cpp_allocator,
    };

    // Even with high-confidence runtime hint, boundary wins
    const result = mergePlatformHint(.boundary, &hint, true);
    try std.testing.expectEqual(.boundary, result);
}

test "mergePlatformHint - unknown preserved (P8)" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .compiler_generated,
        .confidence = .high,
        .reason = "LLVM intrinsic",
        .runtime_category = .llvm_intrinsic,
    };

    // Unknown surface is never overridden
    const result = mergePlatformHint(.unknown, &hint, false);
    try std.testing.expectEqual(.unknown, result);
}

test "mergePlatformHint - high confidence overrides user_code" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .standard_library,
        .confidence = .high,
        .reason = "LibC malloc",
        .runtime_category = .libc,
    };

    // High-confidence hint can override user_code
    const result = mergePlatformHint(.user_code, &hint, false);
    try std.testing.expectEqual(.standard_library, result);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "mergePlatformHint - null hint returns current surface" {
    const result = mergePlatformHint(.user_code, null, false);
    try std.testing.expectEqual(.user_code, result);

    // Boundary should still be boundary even with null hint
    const bnd_result = mergePlatformHint(.boundary, null, true);
    try std.testing.expectEqual(.boundary, bnd_result);
}

test "mergePlatformHint - low confidence hint ignored for user_code" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .standard_library,
        .confidence = .low,
        .reason = "Weak evidence",
        .runtime_category = null,
    };

    // Low-confidence hint should NOT override user_code
    const result = mergePlatformHint(.user_code, &hint, false);
    try std.testing.expectEqual(.user_code, result);
}

test "mergePlatformHint - medium confidence only affects user_code" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .compiler_generated,
        .confidence = .medium,
        .reason = "Some evidence",
        .runtime_category = null,
    };

    // Medium hint overrides user_code
    try std.testing.expectEqual(.compiler_generated, mergePlatformHint(.user_code, &hint, false));

    // But does NOT override dependency (stronger than user_code)
    try std.testing.expectEqual(.dependency, mergePlatformHint(.dependency, &hint, false));

    // And does NOT override standard_library (already a skip signal)
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.standard_library, &hint, false));
}

test "mergePlatformHint - high confidence does not downgrade existing classification" {
    const hint = PlatformSurfaceHint{
        .suggested_surface = .compiler_generated,
        .confidence = .high,
        .reason = "Strong evidence",
        .runtime_category = .llvm_intrinsic,
    };

    // High-confidence hint should NOT downgrade boundary or unknown
    try std.testing.expectEqual(.boundary, mergePlatformHint(.boundary, &hint, true));
    try std.testing.expectEqual(.unknown, mergePlatformHint(.unknown, &hint, false));

    // Should NOT downgrade standard_library to compiler_generated
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.standard_library, &hint, false));
}

test "generatePlatformHint - boundary function still gets runtime hint" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // Even if the name looks like a runtime function, we generate a hint
    // The caller is responsible for applying P8 boundary priority
    const hint = generatePlatformHint("_Znam", &profile); // C++ operator new[]
    try std.testing.expect(hint.runtime_category != null);
    try std.testing.expectEqual(PlatformRuntime.RuntimeCategory.cpp_allocator, hint.runtime_category.?);
}

// ============================================================================
// Comprehensive Edge Case Tests
// ============================================================================

test "generatePlatformHint - all runtime categories produce hints" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // C++ allocator → standard_library surface
    const h_alloc = generatePlatformHint("_Znwm", &profile);
    try std.testing.expectEqual(FunctionSurface.standard_library, h_alloc.suggested_surface);
    try std.testing.expectEqual(Confidence.high, h_alloc.confidence);

    // LibC → standard_library surface
    const h_libc = generatePlatformHint("malloc", &profile);
    try std.testing.expectEqual(FunctionSurface.standard_library, h_libc.suggested_surface);
    try std.testing.expect(h_libc.confidence >= .medium);

    // LLVM intrinsic → compiler_generated surface
    const h_llvm = generatePlatformHint("llvm.memcpy.p0i8.p0i8.i64", &profile);
    try std.testing.expectEqual(FunctionSurface.compiler_generated, h_llvm.suggested_surface);
    try std.testing.expectEqual(Confidence.high, h_llvm.confidence);

    // User code → unknown surface (no strong signal)
    const h_user = generatePlatformHint("myApplicationLogic", &profile);
    try std.testing.expectEqual(FunctionSurface.unknown, h_user.suggested_surface);
    try std.testing.expectEqual(Confidence.low, h_user.confidence);
}

test "generatePlatformHint - empty string returns unknown" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    const hint = generatePlatformHint("", &profile);
    try std.testing.expectEqual(FunctionSurface.unknown, hint.suggested_surface);
    try std.testing.expectEqual(Confidence.low, hint.confidence);
}

test "mergePlatformHint - all confidence levels with user_code" {
    const low_hint = PlatformSurfaceHint{ .suggested_surface = .standard_library, .confidence = .low, .reason = "weak", .runtime_category = null };
    const med_hint = PlatformSurfaceHint{ .suggested_surface = .standard_library, .confidence = .medium, .reason = "some", .runtime_category = null };
    const high_hint = PlatformSurfaceHint{ .suggested_surface = .standard_library, .confidence = .high, .reason = "strong", .runtime_category = null };

    // Low: ignored
    try std.testing.expectEqual(.user_code, mergePlatformHint(.user_code, &low_hint, false));
    // Medium: applied to user_code only
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.user_code, &med_hint, false));
    // High: applied to user_code and dependency
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.user_code, &high_hint, false));
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.dependency, &high_hint, false));
}

test "mergePlatformHint - high confidence does NOT downgrade standard_library or compiler_generated" {
    const hint = PlatformSurfaceHint{ .suggested_surface = .compiler_generated, .confidence = .high, .reason = "strong evidence", .runtime_category = .llvm_intrinsic };

    // standard_library stays standard_library (not downgraded)
    try std.testing.expectEqual(.standard_library, mergePlatformHint(.standard_library, &hint, false));

    // compiler_generated stays compiler_generated
    try std.testing.expectEqual(.compiler_generated, mergePlatformHint(.compiler_generated, &hint, false));

    // runtime stays runtime
    try std.testing.expectEqual(.runtime, mergePlatformHint(.runtime, &hint, false));
}

test "mergePlatformHint - dependency resists medium confidence but not high" {
    const med_hint = PlatformSurfaceHint{ .suggested_surface = .compiler_generated, .confidence = .medium, .reason = "some", .runtime_category = null };
    const high_hint = PlatformSurfaceHint{ .suggested_surface = .compiler_generated, .confidence = .high, .reason = "strong", .runtime_category = null };

    // Medium does NOT override dependency
    try std.testing.expectEqual(.dependency, mergePlatformHint(.dependency, &med_hint, false));

    // High DOES override dependency
    try std.testing.expectEqual(.compiler_generated, mergePlatformHint(.dependency, &high_hint, false));
}

test "runtimeToSurface - all categories mapped correctly" {
    // Standard library category
    try std.testing.expectEqual(FunctionSurface.standard_library, runtimeToSurface(.libc));
    try std.testing.expectEqual(FunctionSurface.standard_library, runtimeToSurface(.cpp_allocator));
    try std.testing.expectEqual(FunctionSurface.standard_library, runtimeToSurface(.cpp_abi));

    // Runtime category
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.objc_runtime));
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.swift_runtime));
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.gcd_runtime));
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.go_runtime));
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.rust_runtime));
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.zig_runtime));

    // Compiler generated category
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.llvm_intrinsic));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.profiling));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.exception_handler));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.static_init));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.static_fini));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.tls_init));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.stack_protection));
    try std.testing.expectEqual(FunctionSurface.compiler_generated, runtimeToSurface(.dynamic_linker));

    // Sanitizer → runtime
    try std.testing.expectEqual(FunctionSurface.runtime, runtimeToSurface(.sanitizer));

    // Unknown → conservative standard_library
    try std.testing.expectEqual(FunctionSurface.standard_library, runtimeToSurface(.unknown));
}
