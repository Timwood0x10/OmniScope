//! Surface Classifier — Layer 4: Boundary Detection
//!
//! Distinguishes TWO types of "visible" functions:
//!
//!   1. FFI Boundary (cross-ABI, real language border)
//!      — extern "C", #[no_mangle], exported to C/other languages
//!      — MUST be analyzed (security surface)
//!      — Signals: unmangled name, C calling convention, export section
//!
//!   2. Library Export (same-language public API)
//!      — pub fn with external linkage but mangled (Rust internal API)
//!      — NOT a real FFI boundary — wasmtime's internal pub fns
//!      — Should be treated as dependency code, not security surface
//!
//! Why this matters:
//!   wasmtime has 1331 functions with external linkage (pub fn), but only
//!   ~10-20 are actual FFI boundaries (extern "C" exports). The old rule
//!   classified all 1331 as "boundary" → bypassed ALL noise filtering →
//!   caused 558 false positive issues.
//!
//! Design principle:
//!   A function is an FFI boundary ONLY if it crosses the ABI boundary.
//!   Rust-to-Rust calls within the same crate are NOT boundaries.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const log = @import("../../common/log.zig");

// ============================================================================
// Public API
// ============================================================================

/// Detect if a function is a REAL cross-ABI FFI boundary.
///
/// This is the strict definition: only functions that can be called from
/// a different language / different compilation unit via stable ABI.
///
/// Signals (any one sufficient):
///   - Unmangled name (no _ZN/_R prefix) + external linkage
///     → #[no_mangle] or extern "C" in Rust
///   - C calling convention (CCallConv = 0) + external linkage
///     → explicitly declared as C ABI
///   - In a known export section (.export.*, .wasm.*)
///
/// Returns false for:
///   - Mangled names (_ZN8wasmtime...) with external linkage
///     → Rust pub fn, same-language internal API
///   - Internal/linkonce linkage functions
///     → not visible outside this TU
pub fn detectBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    // Declarations are not boundaries themselves (callee side)
    if (c.LLVMIsDeclaration(func) != 0) return false;

    const linkage = c.LLVMGetLinkage(func);

    // Must be externally visible at minimum
    if (linkage != c.LLVMExternalLinkage) return false;

    // Get name once for all checks
    const name_ptr = c.LLVMGetValueName(func);
    const name = if (@intFromPtr(name_ptr) != 0) std.mem.span(name_ptr) else "<anon>";

    // Signal 1: Unmangled name + external linkage → likely #[no_mangle] or extern "C"
    //
    // This is the PRIMARY and most reliable signal.
    // Rust mangled names always start with _ZN or _R.
    // C symbols, #[no_mangle], and extern "C" functions use plain names.
    if (isUnmangledName(name)) {
        log.debug("[BOUNDARY] '{s}': FFI boundary (unmangled + external)", .{name});
        return true;
    }

    // Signal 2: C calling convention AND unmangled name → explicit extern "C"
    //
    // NOTE: CCallConv alone is NOT sufficient! Many Rust functions use
    // CCallConv internally (especially monomorphized trait impls that
    // get called from extern "C" wrappers). We require BOTH conditions:
    //   - CCallConv (ABI is C-compatible)
    //   - Unmangled name (symbol is visible at C ABI level)
    //
    // A mangled name with CCallConv is just a Rust function that happens
    // to use C calling convention — NOT a cross-ABI boundary.
    const call_conv = c.LLVMGetFunctionCallConv(func);
    if (call_conv == c.LLVMCCallConv and isUnmangledName(name)) {
        log.debug("[BOUNDARY] '{s}': FFI boundary (C call conv + unmangled)", .{name});
        return true;
    }

    // Signal 3: Export section (WebAssembly / dynamic library exports)
    // Only applies to functions in known export sections
    const section_ptr = c.LLVMGetSection(func);
    if (@intFromPtr(section_ptr) != 0) {
        const section = std.mem.span(section_ptr);
        if (isExportSection(section)) {
            log.debug("[BOUNDARY] '{s}': FFI boundary (section={s})", .{ name, section });
            return true;
        }
    }

    // External linkage BUT mangled name + non-C callconv → Rust pub fn
    // This is a library-internal public API, NOT a cross-ABI FFI boundary.
    // Example: wasmtime::Instance::new(_Z_N8wasmtime...) is callable from
    // other Rust crates but not from C/Python/Go via stable ABI.
    return false;
}

/// Detect if a function is a library-internal public API (not FFI boundary).
///
/// These are functions with external linkage that are visible within the
/// same language ecosystem but don't cross ABI boundaries.
/// Example: wasmtime's `pub fn Instance::new(_)` — callable from other
/// Rust crates but not from C/Python/etc.
///
/// Used for statistics and optional downstream filtering.
pub fn detectLibraryExport(func: c.LLVMValueRef) bool {
    if (c.LLVMIsDeclaration(func) != 0) return false;
    if (c.LLVMGetLinkage(func) != c.LLVMExternalLinkage) return false;

    // Has external linkage but is NOT an FFI boundary → library export
    return !detectBoundaryFromLLVM(func);
}

// ============================================================================
// Name Analysis Helpers
// ============================================================================

/// Check if a function name is UNMANGLED (plain C symbol).
///
/// Mangled patterns we reject:
///   _ZN<seq>E       — legacy Itanium (Rust/C++)
///   _R<var>_<hash>_ — v0 Itanium (Rust newer)
///   __Z             — some vendor extensions
///
/// Everything else (including names starting with single underscore like
/// `_start`, `_init`) is considered unmangled → potential FFI boundary.
fn isUnmangledName(name: []const u8) bool {
    if (name.len < 2) return true; // Very short names are never mangled

    // Rust/C++ Itanium mangling prefixes
    if (name[0] == '_') {
        if (name.len >= 3) {
            // _ZN... or _R...
            if (name[1] == 'Z' and (name[2] == 'N' or name[2] == 'R')) {
                return false; // Definitely mangled
            }
        }
        // __Z... (vendor extension)
        if (name[1] == '_' and name.len >= 3 and name[2] == 'Z') {
            return false;
        }
    }

    // All other names are unmangled → potential FFI boundary
    return true;
}

/// Check if a section name indicates an exported symbol.
///
/// Export sections vary by platform/target:
///   WebAssembly: .export.*, .wasm.*
///   ELF:         .dynsym, .got, .plt (indirect signals)
///   macOS:       __DATA,__la_symbol_ptr, __DATA,__nl_symbol_ptr
fn isExportSection(section: []const u8) bool {
    // WebAssembly export sections
    if (std.mem.indexOf(u8, section, ".export.") != null) return true;
    if (std.mem.indexOf(u8, section, ".wasm.") != null) return true;
    if (std.mem.eql(u8, section, ".wasm")) return true;

    // Dynamic linking export indicators
    if (std.mem.eql(u8, section, ".dynsym")) return true;

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "isUnmangledName - plain names are unmangled" {
    try std.testing.expect(isUnmangledName("main"));
    try std.testing.expect(isUnmangledName("_start"));
    try std.testing.expect(isUnmangledName("malloc"));
    try std.testing.expect(isUnmangledName("wasm_instance_new"));
    try std.testing.expect(isUnmangledName("__rust_alloc"));
}

test "isUnmangledName - Itanium mangled names" {
    try std.testing.expect(!isUnmangledName("_ZN4core3fmt5Debug3fmtE"));
    try std.testing.expect(!isUnmangledName("_ZN8wasmtime7runtime4Instance7newE"));
    try std.testing.expect(!isUnmangledName("_RNvXs_8wasmtime7runtime4Instance7new"));
    try std.testing.expect(!isUnmangledName("_ZSt16__throw_bad_allocv"));
    try std.testing.expect(!isUnmangledName("__ZN4test3fooE"));
}

test "isUnmangledName - edge cases" {
    try std.testing.expect(isUnmangledName("_")); // Single underscore
    try std.testing.expect(isUnmangledName("__")); // Double underscore (not __Z)
    try std.testing.expect(isUnmangledName("a")); // Single char
    try std.testing.expect(!isUnmangledName("_ZN")); // Prefix only
}

test "isExportSection - wasm exports" {
    try std.testing.expect(isExportSection(".export.wasm"));
    try std.testing.expect(isExportSection(".wasm.export.name"));
    try std.testing.expect(isExportSection(".wasm"));
    try std.testing.expect(!isExportSection(".text"));
    try std.testing.expect(!isExportSection(".rodata"));
    try std.testing.expect(isExportSection(".dynsym"));
}
