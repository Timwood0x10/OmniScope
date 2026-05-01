//! Unified Language Detector
//!
//! Single source of truth for language identification across all analysis passes.
//! Eliminates the 4 duplicate identifyLanguage() implementations.
//!
//! Delegates to the authoritative implementation in pass/analysis/ffi_language_classifier.zig
//! and provides a clean API for all consumers.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;

const Language = @import("../diag/issue.zig").FFIBoundary.Language;

/// Identify the language of an LLVM function value.
///
/// This is the **single canonical implementation** used by all analysis passes.
/// Do NOT duplicate this logic elsewhere — always call through here.
///
/// Detection logic (delegated to ffi_language_classifier):
/// - Rust: `_ZN`, `_rust_`, `rs2py_`, `rust_` patterns
/// - Zig: `zig_` + additional indicators (`@`, `zig_`)
/// - C: Default fallback for C ABI functions
///
/// Parameters:
///   - func: LLVM function value to classify
///
/// Returns:
///   - Detected language (.rust, .zig, .c, .unknown)
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return @import("../pass/analysis/ffi_language_classifier.zig").identifyLanguage(func);
}

/// Identify the language of a called function by name string.
///
/// Used when caller already has extracted the function name.
/// Handles LLVM intrinsic filtering and Go/ObjC detection.
///
/// Parameters:
///   - func_name: Function name string to analyze
///
/// Returns:
///   - Detected language enum value
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    return @import("../pass/analysis/ffi_language_classifier.zig").identifyCalleeLanguage(func_name);
}
