//! FFI Noise Filter and Pattern Matching
//!
//! Extracted from ffi_boundary.zig for better code organization.
//! Contains noise reduction, pattern matching for C++/STL/ABI functions,
//! and false positive filtering.

const std = @import("std");

/// Re-export language classifier for unified access.
const lang_classifier = @import("ffi_language_classifier.zig");

/// Check if a function is a C++ ABI internal function (__cxa_*).
/// These are compiler-generated exception handling, TLS, guard (singleton),
/// atexit registration, and dynamic cast support functions.
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    return lang_classifier.isCppAbiInternalFunction(func_name);
}

/// Check if a function is an internal STL/libc++ template expansion.
/// Delegated to unified language classifier (single source of truth).
pub fn isStlInternalFunction(func_name: []const u8) bool {
    return lang_classifier.isStlInternalFunction(func_name);
}

/// Safe libc patterns that should be skipped during FFI analysis.
/// These are compiler-inserted bounds-checked versions and are NOT FFI risks.
pub const SAFE_LIBC_PATTERNS = [_][]const u8{
    "__memcpy_chk",  "__memmove_chk",  "__memset_chk",
    "__strcpy_chk",  "__strcat_chk",   "__strncpy_chk",
    "__sprintf_chk", "__snprintf_chk",
};

/// C++ memory management operator patterns to skip.
pub const CPP_OPERATOR_PATTERNS = [_][]const u8{
    "_Znwm",   "_Znam",   "_ZdlPv", "_ZdaPv",
    "_ZdlPvm", "_ZdaPvm",
};

/// Check if a function name matches safe libc patterns.
pub fn isSafeLibcPattern(called_name: []const u8) bool {
    for (SAFE_LIBC_PATTERNS) |safe| {
        if (std.mem.eql(u8, called_name, safe)) {
            return true;
        }
    }
    return false;
}

/// Check if a function name matches C++ operator patterns.
pub fn isCppOperatorPattern(called_name: []const u8) bool {
    for (CPP_OPERATOR_PATTERNS) |op| {
        if (std.mem.eql(u8, called_name, op)) {
            return true;
        }
    }
    return false;
}
