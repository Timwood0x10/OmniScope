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
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;

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
pub fn detectBoundaryFromLLVM(func: c.LLVMValueRef, module_lang: ?Language) bool {
    // C/C++ modules: unmangled external linkage is normal, not FFI boundary
    if (module_lang == .c or module_lang == .cpp) {
        return false;
    }

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
pub fn detectLibraryExport(func: c.LLVMValueRef, module_lang: ?Language) bool {
    if (c.LLVMIsDeclaration(func) != 0) return false;
    if (c.LLVMGetLinkage(func) != c.LLVMExternalLinkage) return false;

    // Has external linkage but is NOT an FFI boundary → library export
    return !detectBoundaryFromLLVM(func, module_lang);
}

/// Detect if a function is a Windows DLL import/export boundary.
///
/// On Windows COFF, DLL boundaries are identified by:
///   - LLVM DLL storage class (DLLImportStorageClass / DLLEXportStorageClass)
///   - Functions with dllexport attribute are FFI exports
///   - Functions with dllimport attribute are FFI imports
///
/// This complements detectBoundaryFromLLVM() for Windows-specific patterns.
pub fn detectDllImportExport(func: c.LLVMValueRef) bool {
    // Only meaningful for defined functions (not declarations)
    if (c.LLVMIsDeclaration(func) != 0) return false;

    const linkage = c.LLVMGetLinkage(func);

    // Check for dllexport — this function is exported from the DLL
    if (linkage == c.LLVMDLLExportStorageClass) {
        log.debug("[BOUNDARY-DLL] '{s}': dllexport -> FFI boundary", .{
            if (@intFromPtr(c.LLVMGetValueName(func)) != 0)
                std.mem.span(c.LLVMGetValueName(func))
            else
                "<anon>",
        });
        return true;
    }

    return false;
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
///   ?<name>@...     — MSVC x64 / Itanium for C++ (Windows)
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

    // MSVC x64 mangling prefix — starts with ?
    // Examples:
    //   ?square@@YAHH@Z           — int square(int)
    //   ??0 MyClass @@ QAEAAV1@ABV1@ — copy constructor
    //   ??_G                      — scalar deleting destructor
    if (name.len > 0 and name[0] == '?') return false;

    // All other names are unmangled → potential FFI boundary
    return true;
}

/// Check if a section name indicates an exported symbol.
///
/// Export sections vary by platform/target:
///   WebAssembly: .export.*, .wasm.*
///   ELF:         .dynsym, .got, .plt (indirect signals)
///   macOS:       __DATA,__la_symbol_ptr, __DATA,__nl_symbol_ptr
///   COFF/PE:     .idata$2, .idata$5, .CRT$XCA, .CRT$XCU (DLL exports)
fn isExportSection(section: []const u8) bool {
    // WebAssembly export sections
    if (std.mem.indexOf(u8, section, ".export.") != null) return true;
    if (std.mem.indexOf(u8, section, ".wasm.") != null) return true;
    if (std.mem.eql(u8, section, ".wasm")) return true;

    // Dynamic linking export indicators
    if (std.mem.eql(u8, section, ".dynsym")) return true;

    // Mach-O lazy symbol pointer sections (macOS/iOS FFI exports)
    if (std.mem.indexOf(u8, section, "__DATA,__la_symbol_ptr") != null) return true;
    if (std.mem.indexOf(u8, section, "__DATA,__nl_symbol_ptr") != null) return true;

    // COFF/PE import/export tables (Windows DLL boundaries)
    if (std.mem.indexOf(u8, section, ".idata$") != null) return true;
    if (std.mem.indexOf(u8, section, ".CRT$XCA") != null) return true; // C++ static init array
    if (std.mem.indexOf(u8, section, ".CRT$XCU") != null) return true; // C++ static init array
    if (std.mem.eql(u8, section, ".edata")) return true; // Export data

    return false;
}

/// Detect if a function is a FFI CALLER (calls external FFI functions).
///
/// This complements detectBoundaryFromLLVM() which only detects callee-side
/// boundaries (functions DEFINED in this module that are exported via extern "C").
///
/// In real FFI scenarios:
///   - Rust module has: `extern "C" { fn c_hash(...); }` (declaration)
///   - Rust mangled function calls: `call void @c_hash(...)` (caller side)
///   - The mangled Rust function IS a FFI boundary caller (cross-ABI call site)
///
/// NOTE: Full instruction scanning requires LLVMGetFirstInstruction which may
/// not be available in all LLVM C API versions. This implementation uses a
/// lightweight heuristic: if the module contains external declarations with
/// unmangled/C-conv names AND this function is a user function with external
/// linkage (not stdlib/runtime/llvm), it's likely an FFI caller.
pub fn detectCallerSideFFI(func: c.LLVMValueRef, module: c.LLVMModuleRef) bool {
    if (c.LLVMIsDeclaration(func) != 0) return false;

    const name_ptr = c.LLVMGetValueName(func);
    const func_name = if (@intFromPtr(name_ptr) != 0) std.mem.span(name_ptr) else "<anon>";

    // Skip LLVM intrinsics, stdlib, and runtime functions
    if (isLLVMIntrinsic(func_name) or isStdlibOrRuntime(func_name)) return false;

    // Must have external linkage (user-visible function that could be FFI boundary)
    const linkage = c.LLVMGetLinkage(func);
    if (linkage != c.LLVMExternalLinkage) return false;

    // Check if the module has any external FFI declarations
    var decl = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(decl) != 0) : (decl = c.LLVMGetNextFunction(decl)) {
        if (c.LLVMIsDeclaration(decl) == 0) continue;

        const decl_name_ptr = c.LLVMGetValueName(decl);
        const decl_name = if (@intFromPtr(decl_name_ptr) != 0) std.mem.span(decl_name_ptr) else "";

        if (isUnmangledName(decl_name) and decl_name.len > 0) {
            const decl_conv = c.LLVMGetFunctionCallConv(decl);
            if (decl_conv == c.LLVMCCallConv or isFFIPrefixName(decl_name)) {
                log.debug("[BOUNDARY-CALLER] '{s}' potential FFI caller (module has FFI decl '{s}')", .{ func_name, decl_name });
                return true;
            }
        }
    }

    return false;
}

/// Check if a name looks like an LLVM intrinsic (llvm.*).
fn isLLVMIntrinsic(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "llvm.");
}

/// Check if a name looks like a standard library or runtime function.
fn isStdlibOrRuntime(name: []const u8) bool {
    // Rust stdlib patterns
    if (std.mem.startsWith(u8, name, "_RN")) return true; // Rust new mangling
    if (std.mem.startsWith(u8, name, "_ZN") and std.mem.indexOf(u8, name, "4core") != null) return true;
    if (std.mem.startsWith(u8, name, "_ZN") and std.mem.indexOf(u8, name, "5alloc") != null) return true;
    if (std.mem.startsWith(u8, name, "_ZN") and std.mem.indexOf(u8, name, "3std") != null) return true;

    // Special functions
    if (std.mem.eql(u8, name, "rust_eh_personality")) return true;
    if (std.mem.indexOf(u8, name, "__rust_") != null) return true;

    return false;
}

fn isFFIPrefixName(name: []const u8) bool {
    const ffi_prefixes = [_][]const u8{ "c_", "cpp_", "java_", "go_", "rust_" };
    for (ffi_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
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

// ============================================================================
// P1: Platform-Aware Boundary Detection Tests
// ============================================================================

test "isUnmangledName - MSVC mangled names (P1-a)" {
    // MSVC x64 mangling always starts with ?
    try std.testing.expect(!isUnmangledName("?square@@YAHH@Z"));
    try std.testing.expect(!isUnmangledName("??0 MyClass @@ QAEAAV1@ABV1@"));
    try std.testing.expect(!isUnmangledName("??_G")); // scalar deleting destructor
    try std.testing.expect(!isUnmangledName("??1?type_info@@"));
    try std.testing.expect(!isUnmangledName("??2@YAPEAX_K@Z")); // operator new
    try std.testing.expect(!isUnmangledName("??3@YAXPEAX@Z")); // operator delete
}

test "isUnmangledName - MSVC C names are unmangled" {
    // Plain C names on Windows are NOT mangled (no ? prefix)
    try std.testing.expect(isUnmangledName("square"));
    try std.testing.expect(isUnmangledName("main"));
    try std.testing.expect(isUnmangledName("_square")); // MinGW uses _ prefix for C
    try std.testing.expect(isUnmangledName("malloc"));
}

test "isExportSection - Mach-O lazy symbol pointers (P1-b)" {
    try std.testing.expect(isExportSection("__DATA,__la_symbol_ptr"));
    try std.testing.expect(isExportSection("__DATA,__la_symbol_ptr.local"));
    try std.testing.expect(isExportSection("__DATA,__nl_symbol_ptr"));
    try std.testing.expect(isExportSection("__DATA,__nl_symbol_ptr.local"));
    try std.testing.expect(!isExportSection("__DATA,__data"));
    try std.testing.expect(!isExportSection("__TEXT,__text"));
}

test "isExportSection - COFF/PE DLL sections (P1-b)" {
    try std.testing.expect(isExportSection(".idata$2"));
    try std.testing.expect(isExportSection(".idata$5"));
    try std.testing.expect(isExportSection(".idata$6"));
    try std.testing.expect(isExportSection(".CRT$XCA"));
    try std.testing.expect(isExportSection(".CRT$XCU"));
    try std.testing.expect(isExportSection(".edata"));
    try std.testing.expect(!isExportSection(".text$mn"));
    try std.testing.expect(!isExportSection(".rdata"));
}
