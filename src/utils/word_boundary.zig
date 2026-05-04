/// Word Boundary Matching Utilities
///
/// Provides pattern matching functions that respect word boundaries
/// to avoid false positives from substring matching.
///
/// Examples:
///   - my_free_wrapper should NOT match "free"
///   - my_handler should NOT match "handler"
///   - myCallback SHOULD match "Callback" (camelCase)
///   - handle_Event SHOULD match "Event" (snake_case)
const std = @import("std");

/// Check if pattern matches at a word boundary in name.
/// Prevents false positives from substring matching:
///   - my_free_wrapper should NOT match "free"
///   - my_handler should NOT match "handler"
///   - myCallback SHOULD match "Callback) (camelCase)
///   - handle_Event SHOULD match "Event) (snake_case)
pub fn isWordBoundaryMatch(name: []const u8, pattern: []const u8) bool {
    // Exact match
    if (std.mem.eql(u8, name, pattern)) return true;

    // Pattern is suffix (e.g., myCallback → Callback)
    if (name.len > pattern.len) {
        const prefix = name[0 .. name.len - pattern.len];
        const suffix = name[name.len - pattern.len ..];
        if (std.mem.eql(u8, suffix, pattern)) {
            const last_prefix = prefix[prefix.len - 1];
            const first_pattern = pattern[0];
            if (isSeparator(last_prefix)) return true; // _ or .
            if (isLower(last_prefix) and isUpper(first_pattern)) return true; // camelCase
        }
    }

    // Pattern is prefix (e.g., Handler_func → Handler)
    if (name.len > pattern.len) {
        const prefix = name[0..pattern.len];
        if (std.mem.eql(u8, prefix, pattern)) {
            const next_char = name[pattern.len];
            if (isSeparator(next_char)) return true; // _ or . after pattern
        }
    }

    return false;
}

pub fn isSeparator(ch: u8) bool {
    return ch == '_' or ch == '.' or ch == '-';
}

pub fn isUpper(ch: u8) bool {
    return ch >= 'A' and ch <= 'Z';
}

pub fn isLower(ch: u8) bool {
    return ch >= 'a' and ch <= 'z';
}
