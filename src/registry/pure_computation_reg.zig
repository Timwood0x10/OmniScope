const std = @import("std");
const types = @import("types.zig");

/// Pure computation functions — no memory side effects, no writes, no global state changes.
/// These functions are pure computations that should not trigger FFI boundary warnings
/// when called across language boundaries.
pub const pure_computation_functions = [_]types.FunctionSemantics{
    // ── String length & comparison (string.h) ──
    .{ .pattern = "strlen", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get string length - pure computation, no side effects" },
    .{ .pattern = "strnlen", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get bounded string length - pure computation" },
    .{ .pattern = "strcmp", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compare strings - pure computation, read-only" },
    .{ .pattern = "strncmp", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compare bounded strings - pure computation, read-only" },
    .{ .pattern = "strchr", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Find character in string - pure computation, read-only" },
    .{ .pattern = "strrchr", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Find character from end - pure computation, read-only" },
    .{ .pattern = "strstr", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Find substring - pure computation, read-only" },
    .{ .pattern = "strspn", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get span of character set - pure computation" },
    .{ .pattern = "strcspn", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get complement span - pure computation" },

    // ── String/number conversion (stdlib.h) ──
    .{ .pattern = "atoi", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to int - pure computation" },
    .{ .pattern = "atol", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to long - pure computation" },
    .{ .pattern = "atoll", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to long long - pure computation" },
    .{ .pattern = "atof", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to double - pure computation" },
    .{ .pattern = "strtol", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to long (with base) - pure computation" },
    .{ .pattern = "strtoul", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to unsigned long - pure computation" },
    .{ .pattern = "strtod", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert string to double - pure computation" },

    // ── Time functions (time.h) ──
    .{ .pattern = "time", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get current time - pure computation, read-only" },
    .{ .pattern = "clock", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get processor clock time - pure computation" },
    .{ .pattern = "difftime", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute time difference - pure computation" },
    .{ .pattern = "mktime", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert local time to timestamp - pure computation" },

    // ── Random number generation (stdlib.h) ──
    .{ .pattern = "rand", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Generate random number - no memory side effects" },
    .{ .pattern = "srand", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Seed random number generator - no memory side effects" },
    .{ .pattern = "random", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Generate random number (BSD) - no memory side effects" },

    // ── Environment variable reading (stdlib.h) ──
    .{ .pattern = "getenv", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Get environment variable - read-only, no side effects" },

    // ── Absolute value & division (stdlib.h) ──
    .{ .pattern = "abs", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute absolute value - pure computation" },
    .{ .pattern = "labs", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute absolute value (long) - pure computation" },
    .{ .pattern = "llabs", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute absolute value (long long) - pure computation" },
    .{ .pattern = "div", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Integer division - pure computation" },
    .{ .pattern = "ldiv", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Long integer division - pure computation" },

    // ── Character classification & conversion (ctype.h) ──
    .{ .pattern = "isalnum", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check if alphanumeric - pure computation" },
    .{ .pattern = "isalpha", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check if alphabetic - pure computation" },
    .{ .pattern = "isdigit", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check if digit - pure computation" },
    .{ .pattern = "isspace", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check if whitespace - pure computation" },
    .{ .pattern = "toupper", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert to uppercase - pure computation" },
    .{ .pattern = "tolower", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Convert to lowercase - pure computation" },

    // ── Memory comparison (string.h) ──
    .{ .pattern = "memcmp", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compare memory regions - pure computation, read-only" },
    .{ .pattern = "bcmp", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compare byte sequences (legacy) - pure computation" },

    // ── Math functions (math.h) ──
    .{ .pattern = "fabs", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute absolute value (float) - pure computation" },
    .{ .pattern = "sqrt", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute square root - pure computation" },
    .{ .pattern = "sin", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute sine - pure computation" },
    .{ .pattern = "cos", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute cosine - pure computation" },
    .{ .pattern = "tan", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute tangent - pure computation" },
    .{ .pattern = "log", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute natural logarithm - pure computation" },
    .{ .pattern = "exp", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute exponential - pure computation" },
    .{ .pattern = "pow", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute power - pure computation" },
    .{ .pattern = "ceil", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute ceiling - pure computation" },
    .{ .pattern = "floor", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Compute floor - pure computation" },
    .{ .pattern = "round", .match_type = .exact, .kind = .pure_computation, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Round to nearest integer - pure computation" },
};

test "pure_computation_reg: function count" {
    const expected_count = pure_computation_functions.len;
    try std.testing.expectEqual(expected_count, pure_computation_functions.len);
}

test "pure_computation_reg: all entries have exact match type" {
    inline for (pure_computation_functions) |entry| {
        try std.testing.expectEqual(types.MatchType.exact, entry.match_type);
        try std.testing.expectEqual(types.RiskKind.pure_computation, entry.kind);
        try std.testing.expectEqual(types.Severity.low, entry.severity);
    }
}
