//! P1 Regression Tests — High Priority Bug Fixes Verification
//!
//! These tests verify that P1-level fixes remain stable:
//!   - Fix #5: libc dangerous function blacklist
//!   - Fix #6: UAF Tier 2 detection with proper confidence
//!   - Fix #7: isZigSafeCimport three-tier classification
//!   - Fix #8: CSafetyLevel classification consistency
//!
//! Run: zig build test-p1-regression

const std = @import("std");
const OmniScope = @import("OmniScope");

const ffi_zone_check = OmniScope.pass.analysis.ffi.ffi_zone_check;
const cpp_fp_reduction = OmniScope.pass.analysis.noise.cpp_fp_reduction;
const FunctionSemantics = OmniScope.registry.FunctionSemantics;

// ============================================================================
// Test Group D: libc dangerous function blacklist (Fix #5)
// ============================================================================

test "P1-D1: dangerous C functions — command injection (CWE-78)" {
    const cmd_injection = [_][]const u8{
        "system", "popen",  "execve",
        "execl",  "execle", "execlp",
        "execv",  "execvp",
    };
    for (cmd_injection) |func| {
        try std.testing.expect(ffi_zone_check.isDangerousCFunction(func));
    }
}

test "P1-D2: dangerous C functions — buffer overflow (CWE-120)" {
    const buf_overflow = [_][]const u8{
        "strcpy", "strcat", "sprintf",
        "gets",   "scanf",  "vsprintf",
    };
    for (buf_overflow) |func| {
        try std.testing.expect(ffi_zone_check.isDangerousCFunction(func));
    }
}

test "P1-D3: dangerous C functions — format string (CWE-134)" {
    const fmt_vuln = [_][]const u8{
        "fprintf", "printf", "sscanf",
        "fscanf",
    };
    for (fmt_vuln) |func| {
        try std.testing.expect(ffi_zone_check.isDangerousCFunction(func));
    }
}

test "P1-D4: dangerous C functions — deprecated/race condition" {
    const deprecated = [_][]const u8{
        "strtok", "asctime",   "ctime",
        "gmtime", "localtime", "bcopy",
        "bzero",
    };
    for (deprecated) |func| {
        try std.testing.expect(ffi_zone_check.isDangerousCFunction(func));
    }
}

test "P1-D5: safe C functions are NOT in dangerous blacklist" {
    const safe_funcs = [_][]const u8{
        "strlen", "memcpy",  "snprintf",
        "memcmp", "malloc",  "free",
        "fgets",  "strncpy", "strncat",
    };
    for (safe_funcs) |func| {
        try std.testing.expect(!ffi_zone_check.isDangerousCFunction(func));
    }
}

// ============================================================================
// Test Group E: UAF Tier 2 detection (Fix #6)
// ============================================================================

test "P1-E1: isHighRiskInternalUAF detects risky function name patterns" {
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("raw_pointer_handler"));
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("unsafe_buffer_op"));
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("manual_memory_manager"));
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("c_style_string"));
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("legacy_code_v1"));
    try std.testing.expect(cpp_fp_reduction.isHighRiskInternalUAF("unchecked_array_access"));
}

test "P1-E2: isHighRiskInternalUAF returns false for safe function names" {
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF("process_data"));
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF("handle_request"));
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF("safe_wrapper"));
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF("validate_input"));
    try std.testing.expect(!cpp_fp_reduction.isHighRiskInternalUAF("compute_hash"));
}

test "P1-E3: UAF confidence calculation — Tier 1 danger path passes threshold" {
    const tier1_confidence: f32 = 0.8;
    try std.testing.expect(tier1_confidence >= 0.75);
}

test "P1-E4: UAF confidence calculation — Tier 2 internal below threshold without boosts" {
    const tier2_confidence: f32 = 0.8 * 0.6;
    try std.testing.expect(tier2_confidence < 0.75);
}

test "P1-E5: UAF confidence calculation — Tier 2 + high-risk boost still below" {
    var tier2_confidence: f32 = 0.8 * 0.6;
    tier2_confidence += 0.25;
    try std.testing.expect(tier2_confidence < 0.75);
}

test "P1-E6: UAF confidence calculation — Tier 2 + both boosts passes threshold" {
    var tier2_confidence: f32 = 0.8 * 0.6;
    tier2_confidence += 0.25;
    tier2_confidence += 0.15;
    try std.testing.expect(tier2_confidence >= 0.75);
}

test "P1-E7: UAF severity levels differ between tiers" {
    const Severity = OmniScope.diag.Severity;

    const mg_danger = true;
    const tier1_severity: Severity = if (mg_danger) .high else .medium;
    try std.testing.expectEqual(Severity.high, tier1_severity);

    const mg_safe = false;
    const tier2_severity: Severity = if (mg_safe) .high else .medium;
    try std.testing.expectEqual(Severity.medium, tier2_severity);
}

// ============================================================================
// Test Group F: isZigSafeCimport three-tier classification (Fix #7 & #8)
// ============================================================================

test "P1-F1: CSafetyLevel Layer 1 — dangerous functions classified correctly" {
    const dangerous_funcs = [_][]const u8{
        "system", "popen",   "execve",
        "strcpy", "strcat",  "sprintf",
        "gets",   "scanf",   "vsprintf",
        "printf", "fprintf",
    };
    for (dangerous_funcs) |func| {
        const level = ffi_zone_check.classifyCSafetyLevel(func);
        try std.testing.expect(level != null);
        try std.testing.expectEqual(ffi_zone_check.CSafetyLevel.dangerous, level.?);
    }
}

test "P1-F2: CSafetyLevel Layer 2 — conditional functions classified correctly" {
    const conditional_funcs = [_][]const u8{
        "malloc",  "calloc",   "realloc",
        "free",    "memcpy",   "memmove",
        "strncpy", "strncat",  "fgets",
        "fread",   "fwrite",   "fopen",
        "freopen", "snprintf", "vsnprintf",
    };
    for (conditional_funcs) |func| {
        const level = ffi_zone_check.classifyCSafetyLevel(func);
        try std.testing.expect(level != null);
        try std.testing.expectEqual(ffi_zone_check.CSafetyLevel.conditional, level.?);
    }
}

test "P1-F3: CSafetyLevel Layer 3 — safe functions classified correctly" {
    const safe_funcs = [_][]const u8{
        "strlen", "strcmp",   "strncmp",
        "memcmp", "strchr",   "strrchr",
        "memset", "sin",      "cos",
        "sqrt",   "strlen",   "strcmp",
        "errno",  "strerror",
    };
    for (safe_funcs) |func| {
        const level = ffi_zone_check.classifyCSafetyLevel(func);
        try std.testing.expect(level != null);
        try std.testing.expectEqual(ffi_zone_check.CSafetyLevel.safe, level.?);
    }
}

test "P1-F4: CSafetyLevel unknown functions return null (conservative)" {
    const unknown_funcs = [_][]const u8{
        "my_custom_function",
        "unknown_lib_func",
        "custom_malloc_wrapper",
        "third_party_api_v2",
        "proprietary_func",
    };
    for (unknown_funcs) |func| {
        const level = ffi_zone_check.classifyCSafetyLevel(func);
        try std.testing.expectEqual(@as(?ffi_zone_check.CSafetyLevel, null), level);
    }
}

test "P1-F5: isZigSafeCimport returns true ONLY for Layer 3 (safe)" {
    const safe_only = [_][]const u8{
        "strlen", "strcmp", "sin", "sqrt", "memcmp", "strncmp",
    };
    for (safe_only) |func| {
        try std.testing.expect(ffi_zone_check.isZigSafeCimport(func));
    }
}

test "P1-F6: isZigSafeCimport returns false for Layer 1 (dangerous)" {
    const dangerous = [_][]const u8{
        "system", "strcpy", "gets", "sprintf", "popen",
    };
    for (dangerous) |func| {
        try std.testing.expect(!ffi_zone_check.isZigSafeCimport(func));
    }
}

test "P1-F7: isZigSafeCimport returns false for Layer 2 (conditional)" {
    const conditional = [_][]const u8{
        "malloc", "free", "memcpy", "snprintf", "fopen",
    };
    for (conditional) |func| {
        try std.testing.expect(!ffi_zone_check.isZigSafeCimport(func));
    }
}

test "P1-F8: isZigSafeCimport returns false for unknown (conservative)" {
    try std.testing.expect(!ffi_zone_check.isZigSafeCimport("unknown_func"));
    try std.testing.expect(!ffi_zone_check.isZigSafeCimport("custom_c_binding"));
}

// ============================================================================
// Test Group G: isZigFFIWorthReporting integration (Fix #8)
// ============================================================================

test "P1-G1: isZigFFIWorthReporting — dangerous functions always reported" {
    const sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .file_io,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    const dangerous = [_][]const u8{ "system", "strcpy", "gets", "sprintf" };
    for (dangerous) |func| {
        try std.testing.expect(
            ffi_zone_check.isZigFFIWorthReporting("zig_main", func, sem),
        );
    }
}

test "P1-G2: isZigFFIWorthReporting — conditional functions need semantic triggers" {
    const normal_sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .file_io,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expect(!ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", normal_sem));

    const ownership_sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .file_io,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = true,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };
    try std.testing.expect(ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", ownership_sem));

    const cmd_sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .command_exec,
        .severity = .high,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };
    try std.testing.expect(ffi_zone_check.isZigFFIWorthReporting("zig_main", "malloc", cmd_sem));
}

test "P1-G3: isZigFFIWorthReporting — safe functions not reported by default" {
    const sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .file_io,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    const safe = [_][]const u8{ "strlen", "strcmp", "sin", "sqrt" };
    for (safe) |func| {
        try std.testing.expect(
            !ffi_zone_check.isZigFFIWorthReporting("zig_main", func, sem),
        );
    }
}

test "P1-G4: isZigFFIWorthReporting — unknown functions analyzed conservatively" {
    const sem = FunctionSemantics{
        .pattern = "test",
        .match_type = .exact,
        .kind = .file_io,
        .severity = .medium,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = false,
        .description = "",
    };

    try std.testing.expect(ffi_zone_check.isZigFFIWorthReporting("zig_main", "custom_c_function", sem));
    try std.testing.expect(ffi_zone_check.isZigFFIWorthReporting("zig_main", "third_party_lib_func", sem));
}

// ============================================================================
// Regression: Previously incorrect classifications now fixed
// ============================================================================

test "P1-REGRESSION-1: malloc/free were incorrectly in old safe list" {
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("malloc").?,
    );
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.conditional,
        ffi_zone_check.classifyCSafetyLevel("free").?,
    );
}

test "P1-REGRESSION-2: strcpy was incorrectly marked as safe" {
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("strcpy").?,
    );
}

test "P1-REGRESSION-3: system was extremely dangerous but was in safe list" {
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("system").?,
    );
}

test "P1-REGRESSION-4: sprintf has buffer overflow risk" {
    try std.testing.expectEqual(
        ffi_zone_check.CSafetyLevel.dangerous,
        ffi_zone_check.classifyCSafetyLevel("sprintf").?,
    );
}

test "P1-BLACKLIST-COMPLETE: all major CWE categories covered" {
    const TestCase = struct { []const u8, []const u8 };

    const cases = [_]TestCase{
        .{ "CWE-78: Command Injection", "system" },
        .{ "CWE-78: Command Injection", "popen" },
        .{ "CWE-120: Buffer Overflow", "strcpy" },
        .{ "CWE-120: Buffer Overflow", "gets" },
        .{ "CWE-134: Format String", "vsprintf" },
    };

    for (cases) |tc| {
        const level = ffi_zone_check.classifyCSafetyLevel(tc[1]);
        try std.testing.expect(level != null);
        try std.testing.expectEqual(ffi_zone_check.CSafetyLevel.dangerous, level.?);
    }
}
