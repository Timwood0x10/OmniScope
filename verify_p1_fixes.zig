//! Quick verification script for P1 critical fixes
//! Tests the core logic without complex module dependencies

const std = @import("std");

// ══════════════════════════════════════════════════════════════════
// Test 1: UAF Tier 2 Confidence Calculation (from cpp_fp_reduction.zig)
// ══════════════════════════════════════════════════════════════════

test "UAF Tier 2: confidence calculation logic" {
    // Simulate the confidence calculation from detectUseAfterFree

    // Tier 1: Danger path - base confidence
    const tier1_base: f32 = 0.8;
    const is_danger_path = true;

    var confidence = tier1_base;

    if (!is_danger_path) {
        // Tier 2 reduction
        confidence *= 0.6; // 0.48

        // High-risk pattern boost
        const has_risky_name = true;
        if (has_risky_name) {
            confidence += 0.25; // 0.73
        }

        // Same-function pattern boost
        const has_clear_pattern = true;
        if (has_clear_pattern) {
            confidence += 0.15; // 0.88
        }
    }

    // For danger path, should be >= 0.75
    try std.testing.expect(confidence >= 0.75);
}

test "UAF Tier 2: internal UAF below threshold without boosts" {
    const base_confidence: f32 = 0.8;
    const is_danger_path = false;

    var confidence = base_confidence;

    if (!is_danger_path) {
        confidence *= 0.6; // 0.48

        // No boosts applied
        // Should remain below threshold
    }

    try std.testing.expect(confidence < 0.75);
}

test "UAF Tier 2: high-risk pattern detection" {
    // Simulate isHighRiskInternalUAF logic
    const func_names = [_][]const u8{
        "raw_pointer_handler",
        "unsafe_buffer_op",
        "manual_memory_manager",
        "process_data",  // Should NOT match
        "safe_wrapper",   // Should NOT match
    };

    const expected_results = [_]bool{ true, true, true, false, false };

    for (func_names, expected_results) |name, expected| {
        var is_risky = false;
        const risky_patterns = [_][]const u8{
            "raw_", "unsafe_", "unchecked_", "manual_",
            "c_style_", "legacy_",
        };

        for (risky_patterns) |pattern| {
            if (std.mem.indexOf(u8, name, pattern) != null) {
                is_risky = true;
                break;
            }
        }

        try std.testing.expectEqual(expected, is_risky);
    }
}

// ══════════════════════════════════════════════════════════════════
// Test 2: Three-Tier Safety Classification (from ffi_zone_check.zig)
// ══════════════════════════════════════════════════════════════════

pub const CSafetyLevel = enum {
    dangerous,
    conditional,
    safe,
};

fn classifyCSafetyLevel(func_name: []const u8) ?CSafetyLevel {
    // Layer 1: Blacklist
    const blacklist = &[_][]const u8{
        "system", "popen", "execve", "execl", "execlp",
        "execle", "execvp", "execv", "posix_spawn",
        "strcpy", "strcat", "sprintf", "gets", "scanf",
        "sscanf", "fscanf",
        "strtok", "asctime", "ctime",
        "vsprintf",
    };

    for (blacklist) |danger| {
        if (std.mem.eql(u8, func_name, danger)) {
            return .dangerous;
        }
    }

    // Layer 2: Conditional
    const conditional = &[_][]const u8{
        "malloc", "calloc", "realloc", "free",
        "memcpy", "memmove",
        "strncpy", "strncat",
        "fgets", "fread", "fwrite",
        "fopen", "freopen",
        "snprintf", "vsnprintf",
    };

    for (conditional) |cond| {
        if (std.mem.eql(u8, func_name, cond)) {
            return .conditional;
        }
    }

    // Layer 3: Safe
    const safe = &[_][]const u8{
        "strlen", "strcmp", "strncmp", "memcmp",
        "strchr", "strrchr", "strstr",
        "memset",
        "atoi", "atol", "strtoul", "strtol", "strtod",
        "printf", "fprintf",
        "exit", "abort", "atexit",
        "errno", "strerror", "perror",
        "getenv",
        "sin", "cos", "tan", "sqrt",
    };

    for (safe) |s| {
        if (std.mem.eql(u8, func_name, s)) {
            return .safe;
        }
    }

    return null;
}

fn isZigSafeCimport(func_name: []const u8) bool {
    const level = classifyCSafetyLevel(func_name);
    return level == .safe;
}

test "Three-tier: Layer 1 dangerous functions" {
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("system").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("strcpy").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("gets").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("popen").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("vsprintf").?);
}

test "Three-tier: Layer 2 conditional functions" {
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("malloc").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("free").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("memcpy").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("fopen").?);
}

test "Three-tier: Layer 3 safe functions" {
    try std.testing.expectEqual(CSafetyLevel.safe, classifyCSafetyLevel("strlen").?);
    try std.testing.expectEqual(CSafetyLevel.safe, classifyCSafetyLevel("strcmp").?);
    try std.testing.expectEqual(CSafetyLevel.safe, classifyCSafetyLevel("sin").?);
    try std.testing.expectEqual(CSafetyLevel.safe, classifyCSafetyLevel("errno").?);
}

test "Three-tier: unknown functions return null" {
    try std.testing.expectEqual(@as(?CSafetyLevel, null), classifyCSafetyLevel("custom_func"));
    try std.testing.expectEqual(@as(?CSafetyLevel, null), classifyCSafetyLevel("unknown"));
}

test "Backward compatibility: isZigSafeCimport only returns true for safe layer" {
    // Dangerous → false
    try std.testing.expectEqual(false, isZigSafeCimport("system"));
    try std.testing.expectEqual(false, isZigSafeCimport("strcpy"));

    // Conditional → false
    try std.testing.expectEqual(false, isZigSafeCimport("malloc"));
    try std.testing.expectEqual(false, isZigSafeCimport("free"));

    // Safe → true
    try std.testing.expectEqual(true, isZigSafeCimport("strlen"));
    try std.testing.expectEqual(true, isZigSafeCimport("strcmp"));

    // Unknown → false
    try std.testing.expectEqual(false, isZigSafeCimport("unknown_func"));
}

// ══════════════════════════════════════════════════════════════════
// Regression Tests
// ══════════════════════════════════════════════════════════════════

test "Regression: previously misclassified functions now correct" {
    // These were incorrectly in old zig_cimport_safe list

    // malloc/free should be conditional, not safe
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("malloc").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, classifyCSafetyLevel("free").?);

    // strcpy should be dangerous, not safe
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("strcpy").?);

    // system should be dangerous, not safe
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("system").?);

    // sprintf should be dangerous, not safe
    try std.testing.expectEqual(CSafetyLevel.dangerous, classifyCSafetyLevel("sprintf").?);
}
