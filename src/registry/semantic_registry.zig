//! Semantic Registry for FFI Boundary Analysis
//!
//! This module provides a knowledge base for FFI boundary function semantics.
//! It is NOT a simple "dangerous function blacklist" - instead, it captures
//! the semantic properties of functions that are relevant when crossing
//! language boundaries.
//!
//! Key insight: The same function has different risk levels depending on context:
//! - `strcpy` in pure C code = medium risk
//! - `strcpy` crossing Rust→C boundary = HIGH risk (length constraint broken, lifetime broken)
//!
//! Layers:
//! - Layer 1: FFI high-risk functions (~15 functions)
//! - Layer 2: Rust ownership patterns (into_raw, from_raw, as_ptr)
//! - Layer 3: Project-specific wrappers (future - config file or annotations)

const std = @import("std");

/// Risk category for FFI boundary analysis.
/// Each category represents a different type of semantic concern.
pub const RiskKind = enum {
    /// Command execution functions (system, exec*, popen)
    command_exec,
    /// Unchecked memory copy (strcpy, strcat, memcpy without bounds)
    unchecked_copy,
    /// Format string vulnerabilities (printf with user input)
    format_string,
    /// Memory allocation (malloc, calloc, realloc)
    allocator,
    /// Memory deallocation (free)
    deallocator,
    /// Rust ownership transfer (Box::into_raw, CString::into_raw)
    rust_ownership,
    /// Borrow escapes to FFI (&str.as_ptr, &slice.as_ptr)
    borrow_escaped,
};

/// Severity level for risk assessment.
/// Higher values indicate more critical issues.
pub const Severity = enum(u8) {
    low = 1,
    medium = 2,
    high = 3,
    critical = 4,

    /// Convert severity to string for display
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }
};

/// Match type for function name patterns.
pub const MatchType = enum {
    /// Exact name match (e.g., "malloc")
    exact,
    /// Prefix match (e.g., "into_raw" matches "std::boxed::Box<T>::into_raw")
    contains,
    /// Suffix match (e.g., "system" matches "\01_system")
    suffix,
};

/// Semantic rule for a function.
/// Captures the behavioral properties relevant to FFI boundary analysis.
pub const FunctionSemantics = struct {
    /// Function name pattern to match
    pattern: []const u8,
    /// How to match the pattern
    match_type: MatchType,
    /// Risk category
    kind: RiskKind,
    /// Severity when crossing FFI boundary
    severity: Severity,
    /// Whether this function consumes ownership of its pointer argument
    consumes_ownership: bool,
    /// Whether this function transfers ownership to the caller
    transfers_ownership: bool,
    /// Whether the result needs null check before use
    requires_null_check: bool,
    /// Whether this function needs taint checking on its arguments
    requires_taint_check: bool,
    /// Human-readable description
    description: []const u8,
};

/// The semantic registry containing all known function semantics.
/// Organized by layers for maintainability.
///
/// Platform Compatibility:
/// - Uses suffix/contains matching to handle platform-specific variants
/// - macOS: system -> \01_system, strcpy -> __strcpy_chk, sprintf -> __sprintf_chk
/// - Linux: Uses standard libc names
pub const SemanticRegistry = struct {
    /// Layer 1: FFI high-risk functions (C standard library)
    /// Uses suffix/contains matching for cross-platform compatibility
    const layer1 = [_]FunctionSemantics{
        // Command execution - CRITICAL
        // macOS: \01_system, Linux: system
        .{
            .pattern = "system",
            .match_type = .suffix,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Execute shell command - command injection risk",
        },
        .{
            .pattern = "popen",
            .match_type = .suffix,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Open pipe to process - command injection risk",
        },
        .{
            .pattern = "execve",
            .match_type = .exact,
            .kind = .command_exec,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Execute program - command injection risk",
        },

        // Unchecked copy - HIGH
        // macOS: __strcpy_chk, __sprintf_chk; Linux: strcpy, sprintf
        .{
            .pattern = "strcpy",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked string copy - buffer overflow risk",
        },
        .{
            .pattern = "strcat",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked string concatenate - buffer overflow risk",
        },
        .{
            .pattern = "sprintf",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked formatted print - buffer overflow risk",
        },
        .{
            .pattern = "vsprintf",
            .match_type = .contains,
            .kind = .unchecked_copy,
            .severity = .high,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Unchecked formatted print (va_list) - buffer overflow risk",
        },
        .{
            .pattern = "gets",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .critical,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Read line without bounds - CRITICAL buffer overflow",
        },
        // memcpy - use exact match to avoid matching llvm.memcpy intrinsics
        .{
            .pattern = "memcpy",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Memory copy - requires correct size argument",
        },
        // macOS fortified variant
        .{
            .pattern = "__memcpy_chk",
            .match_type = .exact,
            .kind = .unchecked_copy,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Memory copy (fortified) - requires correct size argument",
        },

        // Allocators - MEDIUM (require null check)
        .{
            .pattern = "malloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Allocate memory - returns ownership, check for null",
        },
        .{
            .pattern = "calloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Allocate zeroed memory - returns ownership, check for null",
        },
        .{
            .pattern = "realloc",
            .match_type = .exact,
            .kind = .allocator,
            .severity = .medium,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = true,
            .requires_taint_check = false,
            .description = "Reallocate memory - consumes old, returns new ownership",
        },

        // Deallocator - HIGH (cross-language free mismatch risk)
        .{
            .pattern = "free",
            .match_type = .exact,
            .kind = .deallocator,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Free memory - consumes ownership, cross-language mismatch risk",
        },

        // Format string - MEDIUM
        .{
            .pattern = "printf",
            .match_type = .contains,
            .kind = .format_string,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = true,
            .description = "Print formatted - format string vulnerability if user-controlled",
        },
    };

    /// Layer 2: Rust ownership patterns
    const layer2 = [_]FunctionSemantics{
        // Ownership transfer OUT of Rust
        .{
            .pattern = "into_raw",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Rust ownership transfer OUT - caller must free correctly",
        },

        // Ownership transfer INTO Rust
        .{
            .pattern = "from_raw",
            .match_type = .contains,
            .kind = .rust_ownership,
            .severity = .high,
            .consumes_ownership = true,
            .transfers_ownership = true,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Rust ownership transfer IN - Rust takes responsibility",
        },

        // Borrow escape - pointer without ownership transfer
        .{
            .pattern = "as_ptr",
            .match_type = .contains,
            .kind = .borrow_escaped,
            .severity = .medium,
            .consumes_ownership = false,
            .transfers_ownership = false,
            .requires_null_check = false,
            .requires_taint_check = false,
            .description = "Borrow escape - pointer valid only while Rust owns it",
        },
    };

    /// Lookup function semantics by name.
    /// Searches Layer 1 first, then Layer 2.
    /// Returns null if function is not in the registry.
    pub fn lookup(func_name: []const u8) ?FunctionSemantics {
        // Search Layer 1 (FFI high-risk functions)
        for (layer1) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Search Layer 2 (Rust ownership patterns)
        for (layer2) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        return null;
    }

    /// Check if a function name matches a pattern.
    fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
        return switch (match_type) {
            .exact => std.mem.eql(u8, func_name, pattern),
            .contains => std.mem.indexOf(u8, func_name, pattern) != null,
            .suffix => std.mem.endsWith(u8, func_name, pattern),
        };
    }

    /// Check if a function is known to the registry.
    pub fn isKnown(func_name: []const u8) bool {
        return lookup(func_name) != null;
    }

    /// Get the risk kind for a function.
    /// Returns null if function is not in the registry.
    pub fn getRiskKind(func_name: []const u8) ?RiskKind {
        const sem = lookup(func_name) orelse return null;
        return sem.kind;
    }

    /// Get the severity for a function.
    /// Returns null if function is not in the registry.
    pub fn getSeverity(func_name: []const u8) ?Severity {
        const sem = lookup(func_name) orelse return null;
        return sem.severity;
    }

    /// Check if a function consumes ownership.
    /// Returns false if function is not in the registry.
    pub fn consumesOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.consumes_ownership;
    }

    /// Check if a function transfers ownership.
    /// Returns false if function is not in the registry.
    pub fn transfersOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.transfers_ownership;
    }

    /// Check if a function requires null check on its result.
    /// Returns false if function is not in the registry.
    pub fn requiresNullCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_null_check;
    }

    /// Check if a function requires taint checking on its arguments.
    /// Returns false if function is not in the registry.
    pub fn requiresTaintCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_taint_check;
    }

    /// Get description for a function.
    /// Returns null if function is not in the registry.
    pub fn getDescription(func_name: []const u8) ?[]const u8 {
        const sem = lookup(func_name) orelse return null;
        return sem.description;
    }

    /// Check if a function is a dangerous sink.
    /// Uses the registry first, then falls back to pattern matching.
    pub fn isDangerousSink(func_name: []const u8) bool {
        // Use registry for known functions
        if (lookup(func_name)) |sem| {
            return sem.requires_taint_check;
        }

        // Fallback: pattern matching for unknown functions
        const dangerous_patterns = &[_][]const u8{
            "system",
            "exec",
            "popen",
            "strcpy",
            "strcat",
            "sprintf",
            "gets",
            "printf",
            "fprintf",
            "snprintf",
            "memcpy",
            "memmove",
        };

        for (dangerous_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Get the count of Layer 1 functions.
    pub fn layer1Count() usize {
        return layer1.len;
    }

    /// Get the count of Layer 2 functions.
    pub fn layer2Count() usize {
        return layer2.len;
    }

    /// Get total count of known functions.
    pub fn totalCount() usize {
        return layer1.len + layer2.len;
    }
};

// Unit tests

test "SemanticRegistry - RiskKind enum" {
    try std.testing.expectEqual(@as(usize, 7), @typeInfo(RiskKind).@"enum".fields.len);
}

test "SemanticRegistry - Severity enum" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Severity.low));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Severity.medium));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Severity.high));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(Severity.critical));
}

test "SemanticRegistry - Severity toString" {
    try std.testing.expectEqualStrings("LOW", Severity.low.toString());
    try std.testing.expectEqualStrings("MEDIUM", Severity.medium.toString());
    try std.testing.expectEqualStrings("HIGH", Severity.high.toString());
    try std.testing.expectEqualStrings("CRITICAL", Severity.critical.toString());
}

test "SemanticRegistry - lookup exact match" {
    const sem = SemanticRegistry.lookup("malloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
    try std.testing.expect(sem.transfers_ownership);
    try std.testing.expect(sem.requires_null_check);
}

test "SemanticRegistry - lookup contains match" {
    const sem = SemanticRegistry.lookup("std::boxed::Box<T>::into_raw").?;
    try std.testing.expectEqual(RiskKind.rust_ownership, sem.kind);
    try std.testing.expectEqual(Severity.high, sem.severity);
    try std.testing.expect(sem.consumes_ownership);
    try std.testing.expect(sem.transfers_ownership);
}

test "SemanticRegistry - lookup unknown function" {
    try std.testing.expect(SemanticRegistry.lookup("unknown_func") == null);
}

test "SemanticRegistry - isKnown" {
    try std.testing.expect(SemanticRegistry.isKnown("free"));
    try std.testing.expect(SemanticRegistry.isKnown("into_raw"));
    try std.testing.expect(!SemanticRegistry.isKnown("unknown_func"));
}

test "SemanticRegistry - getRiskKind" {
    try std.testing.expectEqual(RiskKind.command_exec, SemanticRegistry.getRiskKind("system").?);
    try std.testing.expectEqual(RiskKind.deallocator, SemanticRegistry.getRiskKind("free").?);
    try std.testing.expect(SemanticRegistry.getRiskKind("unknown") == null);
}

test "SemanticRegistry - getSeverity" {
    try std.testing.expectEqual(Severity.critical, SemanticRegistry.getSeverity("system").?);
    try std.testing.expectEqual(Severity.high, SemanticRegistry.getSeverity("free").?);
    try std.testing.expect(SemanticRegistry.getSeverity("unknown") == null);
}

test "SemanticRegistry - consumesOwnership" {
    try std.testing.expect(SemanticRegistry.consumesOwnership("free"));
    try std.testing.expect(!SemanticRegistry.consumesOwnership("malloc"));
    try std.testing.expect(!SemanticRegistry.consumesOwnership("unknown"));
}

test "SemanticRegistry - transfersOwnership" {
    try std.testing.expect(SemanticRegistry.transfersOwnership("malloc"));
    try std.testing.expect(!SemanticRegistry.transfersOwnership("free"));
    try std.testing.expect(!SemanticRegistry.transfersOwnership("unknown"));
}

test "SemanticRegistry - requiresNullCheck" {
    try std.testing.expect(SemanticRegistry.requiresNullCheck("malloc"));
    try std.testing.expect(!SemanticRegistry.requiresNullCheck("free"));
    try std.testing.expect(!SemanticRegistry.requiresNullCheck("unknown"));
}

test "SemanticRegistry - requiresTaintCheck" {
    try std.testing.expect(SemanticRegistry.requiresTaintCheck("system"));
    try std.testing.expect(SemanticRegistry.requiresTaintCheck("strcpy"));
    try std.testing.expect(!SemanticRegistry.requiresTaintCheck("malloc"));
    try std.testing.expect(!SemanticRegistry.requiresTaintCheck("unknown"));
}

test "SemanticRegistry - getDescription" {
    const desc = SemanticRegistry.getDescription("system").?;
    try std.testing.expect(std.mem.indexOf(u8, desc, "command injection") != null);
    try std.testing.expect(SemanticRegistry.getDescription("unknown") == null);
}

test "SemanticRegistry - counts" {
    try std.testing.expectEqual(@as(usize, 16), SemanticRegistry.layer1Count());
    try std.testing.expectEqual(@as(usize, 3), SemanticRegistry.layer2Count());
    try std.testing.expectEqual(@as(usize, 19), SemanticRegistry.totalCount());
}

test "SemanticRegistry - as_ptr borrow escape" {
    const sem = SemanticRegistry.lookup("slice.as_ptr").?;
    try std.testing.expectEqual(RiskKind.borrow_escaped, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
    try std.testing.expect(!sem.consumes_ownership);
    try std.testing.expect(!sem.transfers_ownership);
}

test "SemanticRegistry - realloc special case" {
    const sem = SemanticRegistry.lookup("realloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expect(sem.consumes_ownership);
    try std.testing.expect(sem.transfers_ownership);
}

test "SemanticRegistry - macOS platform variants" {
    // macOS uses \01_ prefix for some libc functions
    const sem_system = SemanticRegistry.lookup("\x01_system").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem_system.kind);
    try std.testing.expectEqual(Severity.critical, sem_system.severity);

    // macOS uses __*_chk for fortified functions
    const sem_strcpy = SemanticRegistry.lookup("__strcpy_chk").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_strcpy.kind);
    try std.testing.expectEqual(Severity.high, sem_strcpy.severity);

    const sem_sprintf = SemanticRegistry.lookup("__sprintf_chk").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_sprintf.kind);
    try std.testing.expectEqual(Severity.high, sem_sprintf.severity);

    const sem_printf = SemanticRegistry.lookup("__printf_chk").?;
    try std.testing.expectEqual(RiskKind.format_string, sem_printf.kind);
    try std.testing.expectEqual(Severity.medium, sem_printf.severity);
}

test "SemanticRegistry - Linux platform variants" {
    // Linux uses standard libc names
    const sem_system = SemanticRegistry.lookup("system").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem_system.kind);

    const sem_strcpy = SemanticRegistry.lookup("strcpy").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_strcpy.kind);

    const sem_sprintf = SemanticRegistry.lookup("sprintf").?;
    try std.testing.expectEqual(RiskKind.unchecked_copy, sem_sprintf.kind);
}

test "SemanticRegistry - suffix match type" {
    // Test suffix matching for system variants
    try std.testing.expect(SemanticRegistry.isKnown("system"));
    try std.testing.expect(SemanticRegistry.isKnown("\x01_system"));
    try std.testing.expect(SemanticRegistry.isKnown("popen"));
    try std.testing.expect(SemanticRegistry.isKnown("\x01_popen"));
}

test "SemanticRegistry - contains match type" {
    // Test contains matching for fortified variants
    try std.testing.expect(SemanticRegistry.isKnown("strcpy"));
    try std.testing.expect(SemanticRegistry.isKnown("__strcpy_chk"));
    try std.testing.expect(SemanticRegistry.isKnown("sprintf"));
    try std.testing.expect(SemanticRegistry.isKnown("__sprintf_chk"));
    try std.testing.expect(SemanticRegistry.isKnown("printf"));
    try std.testing.expect(SemanticRegistry.isKnown("__printf_chk"));
}
