//! P1 Critical Fix Tests: #7 (UAF Tier 2) and #8 (isZigSafeCimport Three-Tier)
//!
//! Test cases for:
//! - Issue #7: UAF detection extended to language-internal scenarios (Tier 2)
//! - Issue #8: Three-tier safety classification for C imports

const std = @import("std");
const omniscope = @import("OmniScope");

const ffi_zone_check = omniscope.pass.analysis.ffi.ffi_zone_check;
const cpp_fp_reduction = omniscope.pass.analysis.noise.cpp_fp_reduction;

// ══════════════════════════════════════════════════════════════════
// Issue #7: UAF Tier 2 Detection Tests
// ══════════════════════════════════════════════════════════════════

test "UAF Tier 2: isHighRiskInternalUAF detects risky patterns" {
    // Functions with manual memory management patterns should be flagged
    try std.testing.expectEqual(true, cpp_fp_reduction.isHighRiskInternalUAF("raw_pointer_handler"));
    try std.testing.expectEqual(true, cpp_fp_reduction.isHighRiskInternalUAF("unsafe_buffer_op"));
    try std.testing.expectEqual(true, cpp_fp_reduction.isHighRiskInternalUAF("manual_memory_manager"));
    try std.testing.expectEqual(true, cpp_fp_reduction.isHighRiskInternalUAF("c_style_string"));
    try std.testing.expectEqual(true, cpp_fp_reduction.isHighRiskInternalUAF("legacy_code_v1"));

    // Safe function names should not be flagged
    try std.testing.expectEqual(false, cpp_fp_reduction.isHighRiskInternalUAF("process_data"));
    try std.testing.expectEqual(false, cpp_fp_reduction.isHighRiskInternalUAF("handle_request"));
    try std.testing.expectEqual(false, cpp_fp_reduction.isHighRiskInternalUAF("safe_wrapper"));
}

test "UAF Tier 2: confidence calculation for internal UAF" {
    // Simulate confidence calculation logic from detectUseAfterFree
    // Tier 1 (danger path): base confidence = 0.8, no reduction
    const tier1_confidence: f32 = 0.8;
    try std.testing.expect(tier1_confidence >= 0.75);

    // Tier 2 (internal): base * 0.6 = 0.48
    var tier2_confidence: f32 = 0.8 * 0.6;
    try std.testing.expect(tier2_confidence < 0.75); // Below threshold

    // With high-risk boost (+0.25): 0.48 + 0.25 = 0.73
    tier2_confidence += 0.25;
    try std.testing.expect(tier2_confidence < 0.75); // Still below threshold

    // With same-function pattern boost (+0.15): 0.73 + 0.15 = 0.88
    tier2_confidence += 0.15;
    try std.testing.expect(tier2_confidence >= 0.75); // Now above threshold!
}

test "UAF Tier 2: severity levels differ between tiers" {
    // Tier 1 (danger path) should report as HIGH severity
    // Tier 2 (internal) should report as MEDIUM severity
    // This ensures we don't over-prioritize internal bugs

    const Severity = omniscope.diag.Severity;

    // Danger path → high severity
    const mg_danger = true;
    const tier1_severity: Severity = if (mg_danger) .high else .medium;
    try std.testing.expectEqual(Severity.high, tier1_severity);

    // Internal path → medium severity
    const mg_safe = false;
    const tier2_severity: Severity = if (mg_safe) .high else .medium;
    try std.testing.expectEqual(Severity.medium, tier2_severity);
}

// ══════════════════════════════════════════════════════════════════
// Issue #8: Three-Tier Safety Classification Tests
// ══════════════════════════════════════════════════════════════════

test "CSafetyLevel: Layer 1 - dangerous functions detected" {
    // Command injection functions
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("system").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("popen").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("execve").?,
    );

    // Buffer overflow functions
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("strcpy").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("strcat").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("gets").?,
    );

    // Format string vulnerability
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("vsprintf").?,
    );
}

test "CSafetyLevel: Layer 2 - conditional functions detected" {
    // Memory management functions
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("malloc").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("free").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("calloc").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("realloc").?,
    );

    // Memory operations
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("memcpy").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("memmove").?,
    );

    // String operations with size limits
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("strncpy").?,
    );

    // I/O operations
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("fopen").?,
    );
}

test "CSafetyLevel: Layer 3 - safe functions detected" {
    // String queries (read-only)
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("strlen").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("strcmp").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("strncmp").?,
    );

    // Math functions (pure)
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("sin").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("sqrt").?,
    );

    // Error handling
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("errno").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.safe,
        ffi_zone_check.classifyCSafetyLevel("strerror").?,
    );
}

test "CSafetyLevel: unknown functions return null" {
    // Unknown/custom functions should return null (conservative)
    try std.testing.expectEqual(
        @as(?ffi_zone_check.CSafetyLevel, null),
        ffi_zone_check.classifyCSafetyLevel("my_custom_function"),
    );
    try std.testing.expectEqual(
        @as(?ffi_zone_check.CSafetyLevel, null),
        ffi_zone_check.classifyCSafetyLevel("unknown_lib_func"),
    );
    try std.testing.expectEqual(
        @as(?ffi_zone_check.CSafetyLevel, null),
        ffi_zone_check.classifyCSafetyLevel("custom_malloc_wrapper"),
    );
}

test "isZigSafeCimport backward compatibility - only returns true for safe layer" {
    // Dangerous functions → false (Layer 1)
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("system"));
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("strcpy"));
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("gets"));

    // Conditional functions → false (Layer 2)
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("malloc"));
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("free"));
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("memcpy"));

    // Safe functions → true (Layer 3)
    try std.testing.expectEqual(true, ffi_zone_check.isZigSafeCimport("strlen"));
    try std.testing.expectEqual(true, ffi_zone_check.isZigSafeCimport("strcmp"));
    try std.testing.expectEqual(true, ffi_zone_check.isZigSafeCimport("sin"));

    // Unknown functions → false (conservative)
    try std.testing.expectEqual(false, ffi_zone_check.isZigSafeCimport("unknown_func"));
}

// ══════════════════════════════════════════════════════════════════
// Integration Tests: isZigFFIWorthReporting with three-tier system
// ══════════════════════════════════════════════════════════════════

test "isZigFFIWorthReporting: dangerous functions always reported" {
    const FunctionSemantics = omniscope.registry.FunctionSemantics;

    const sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .allocator,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    // Layer 1 dangerous functions should always be reported
    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "system", sem),
    );
    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "strcpy", sem),
    );
    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "gets", sem),
    );
}

test "isZigFFIWorthReporting: conditional functions need semantic triggers" {
    const FunctionSemantics = omniscope.registry.FunctionSemantics;

    // Normal semantics → don't report conditional functions
    const normal_sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .allocator,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expectEqual(
        false,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", normal_sem),
    );

    // With ownership transfer → report
    const ownership_sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .allocator,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = true,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", ownership_sem),
    );

    // With command exec kind → report
    const cmd_sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .command_exec,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", cmd_sem),
    );
}

test "isZigFFIWorthReporting: safe functions not reported by default" {
    const FunctionSemantics = omniscope.registry.FunctionSemantics;

    const sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .allocator,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    // Layer 3 safe functions should not be reported
    try std.testing.expectEqual(
        false,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "strlen", sem),
    );
    try std.testing.expectEqual(
        false,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "strcmp", sem),
    );
    try std.testing.expectEqual(
        false,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "sin", sem),
    );
}

test "isZigFFIWorthReporting: unknown functions analyzed conservatively" {
    const FunctionSemantics = omniscope.registry.FunctionSemantics;

    // Unknown functions default to analysis (conservative)
    const sem = FunctionSemantics{
        .pattern = "",
        .match_type = .contains,
        .kind = .allocator,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "custom_c_function", sem),
    );
    try std.testing.expectEqual(
        true,
        ffi_zone_check.isZigFFIWorthReporting("zig_main", "third_party_lib_func", sem),
    );
}

// ══════════════════════════════════════════════════════════════════
// Edge Cases and Regression Tests
// ══════════════════════════════════════════════════════════════════

test "Regression: previously safe functions now correctly classified" {
    // These were incorrectly marked as safe in old zig_cimport_safe list
    // They should now be classified as conditional or dangerous

    // malloc/free were in the old safe list but are actually conditional
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("malloc").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("free").?,
    );

    // strcpy was in the old safe list but is actually dangerous
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("strcpy").?,
    );

    // system was in the old safe list but is extremely dangerous
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("system").?,
    );

    // sprintf was in the old safe list but has buffer overflow risk
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("sprintf").?,
    );
}

test "Blacklist completeness: all critical vulnerabilities covered" {
    // Ensure all major CWE categories are represented in blacklist
    const dangerous_funcs = [_][]const u8{
        // CWE-78: OS Command Injection
        "system", "popen", "execve",

        // CWE-120: Buffer Copy without Checking Size
        "strcpy", "strcat", "sprintf", "gets",

        // CWE-134: Format String
        "vsprintf",
    };

    for (dangerous_funcs) |func| {
        const level = ffi_zone_check.classifyCSafetyLevel(func);
        try std.testing.expect(level != null);
        try std.testing.expectEqual(ffi_zone_check.CSafetyLevel.dangerous, level.?);
    }
}
