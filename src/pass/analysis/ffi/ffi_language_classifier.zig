//! FFI Language Classifier
//!
//! Extracted from ffi_boundary.zig (P2-2 refactoring).
//! Provides language detection and classification utilities for FFI boundary analysis:
//! - Language identification (Rust, Zig, C, unknown)
//! - Rust name demangling
//! - Boundary kind classification
//! - Function family detection (libc, JNI, Python C API, C++ ABI, STL)
//!
//! Design principle: Stateless utility functions with pattern matching.
//! No internal state, all functions are pure (except demangleRustName which allocates).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

/// Re-export ffi_utils for unified STL/ABI pattern matching (single source of truth).
const ffi_utils = @import("ffi_utils.zig");

/// Rust allocator intrinsic patterns — single source of truth from ptr_types.
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");

/// Platform profile for platform-aware language classification (P2-a).
const PlatformProfile = @import("../../../semantics/platform_profile.zig").PlatformProfile;
const WindowsAbi = @import("../../../semantics/platform_profile.zig").WindowsAbi;

const FFIBoundary = @import("../../../diag/issue.zig").FFIBoundary;
const Language = FFIBoundary.Language;
const BoundaryKind = FFIBoundary.BoundaryKind;

/// Pattern definitions for language detection.
/// Shared across multiple classification functions.
/// These patterns match the ones originally in FFIBoundaryPass.FFIPatterns.
const FFIPatterns = struct {
    /// Known Rust FFI patterns in function names
    /// NOTE: "_ZN" is NOT included here because it is ambiguous — both Rust and C++
    /// use Itanium-style _ZN mangling for nested names. Disambiguation requires
    /// isRustMangledName() multi-layer detection (see below, after C++ check).
    pub const rust_patterns = [_][]const u8{
        "_rust_", // Rust extern function prefix
        "rs2py_", // Rust-to-Python bridge
        "rust_", // Generic Rust prefix
    };

    /// Known Zig FFI patterns in function names
    pub const zig_patterns = [_][]const u8{
        "zig_", // Zig external function prefix
        "extern", // Zig extern block marker
        "c_", // Zig C interop convention
        "@cImport", // C import macro
        "__zig", // Zig compiler-generated FFI glue
    };

    /// Known libc function names (exact match)
    pub const libc_patterns = [_][]const u8{
        "malloc",       "calloc",             "realloc",              "free",
        "memcpy",       "memmove",            "memset",               "memcmp",
        "strcpy",       "strncpy",            "strlen",               "strcmp",
        "strchr",       "fopen",              "fclose",               "fread",
        "fwrite",       "fgets",              "fputs",                "open",
        "close",        "read",               "write",                "lseek",
        "printf",       "fprintf",            "sprintf",              "snprintf",
        "scanf",        "fscanf",             "sscanf",               "pthread_create",
        "pthread_join", "pthread_mutex_lock", "pthread_mutex_unlock", "socket",
        "connect",      "bind",               "listen",               "accept",
        "recv",         "send",               "dlopen",               "dlsym",
        "dlclose",
    };
};

/// Identify the language of a function based on its LLVM value.
///
/// Uses pattern matching on the function name to detect:
/// - **Rust**: `_rust_`, `rs2py_`, `rust_` (_ZN handled separately via isRustMangledName)
/// - **Zig**: `zig_` prefix with additional indicators (`@`, `zig_`)
/// - **C**: Default fallback (most common for C ABI code)
///
/// Parameters:
///   - func: LLVM function value to identify
///
/// Returns:
///   - Detected language enum value
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return .unknown;

    const func_name = std.mem.span(func_name_ptr);

    // LLVM intrinsics are compiler-generated, not any language's FFI function.
    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .unknown;
    }

    // Check for Rust patterns
    for (FFIPatterns.rust_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .rust;
        }
    }

    // Rust v0 mangling prefix (RFC 2603) — _R<hash>...
    // Missing from original identifyLanguage, present in identifyCalleeLanguage.
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') return .rust;

    // Rust ownership transfer / drop glue patterns.
    const rust_ownership = [_][]const u8{ "into_raw", "from_raw", "drop_in_place" };
    for (rust_ownership) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return .rust;
    }

    // Rust allocator intrinsics — __rust_alloc, __rdl_alloc, __rg_alloc, exchange_malloc.
    // These appear in mangled names like _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc
    // and must be classified as .rust, not .c (which causes cross_lang_free_mismatch to miss them).
    for (ptr_types.RUST_ALLOC_INTRINSICS.all) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return .rust;
    }

    // C++ Itanium mangling (_Z prefix) — but NOT _ZN which is ambiguous.
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z' and
        !(func_name.len > 3 and func_name[2] == 'N')) return .cpp;

    // _ZN ambiguity resolution: could be Rust or C++ Itanium nested name.
    // _ZN5alloc9alloc18alloc_global17h... is Rust, not C++.
    if (func_name.len > 3 and func_name[0] == '_' and func_name[1] == 'Z' and func_name[2] == 'N') {
        if (isRustMangledName(func_name)) return .rust;
        return .cpp;
    }

    // P2-a: MSVC x64 / Itanium for C++ mangling detection (?name@@...).
    if (func_name.len > 0 and func_name[0] == '?') return .cpp;

    // Check for Zig patterns (be more specific to avoid false positives)
    var has_zig_indicator = false;
    for (FFIPatterns.zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            if (std.mem.indexOf(u8, func_name, "zig_") != null or
                std.mem.indexOf(u8, func_name, "@") != null)
            {
                has_zig_indicator = true;
                break;
            }
            if (std.mem.eql(u8, pattern, "extern") or std.mem.eql(u8, pattern, "c_")) {
                continue;
            }
            has_zig_indicator = true;
            break;
        }
    }
    if (has_zig_indicator) {
        return .zig;
    }
    // Zig allocator patterns (missing from original)
    if (std.mem.indexOf(u8, func_name, "Allocator.") != null or
        std.mem.indexOf(u8, func_name, "allocImpl") != null)
    {
        return .zig;
    }
    // Zig compiler-reserved (IR spec §1.2): __zig_probe_stack, __zig_tag_name_*,
    // __zig_is_named_enum_value_*, __zig_lt_errors_len, __zig_err_name_table
    // Already covered by __zig pattern above, but add explicit checks for clarity.
    // Zig panic functions (IR spec §5.1): reachUnreachable, unwrapNull, etc.
    // These appear as "std.debug.reachedUnreachable" or similar FQN patterns.
    if (std.mem.startsWith(u8, func_name, "__zig_")) return .zig;
    // Zig compiler-rt soft-float patterns (IR spec §1.2): __float*, __fix*, __*f2
    // These are only Zig when they appear in a Zig module context;
    // at symbol level they're ambiguous with GCC compiler-rt, so skip here.

    // Check for libc functions — these are C by definition
    for (FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return .c;
        }
    }

    // A2: Go / TinyGo detection (enhanced with IR spec patterns)
    // Standard Go: main.*, runtime.*, syscall.*
    // TinyGo (IR spec §1.2): runtime.alloc, runtime.free, runtime._panic, etc.
    // TinyGo CGo (IR spec §1.3): _Cgo_*, _Cgo_static_<hash>_*, unionfield_*, bitfield_*
    // TinyGo scheduler: internal/task.*
    //
    // IMPORTANT: Zig also uses "main." prefix for its entry point (main.main).
    // To avoid misclassifying Zig's main.* as Go, we check for Zig indicators first.
    const is_main_prefix = std.mem.startsWith(u8, func_name, "main.");
    if (is_main_prefix or
        std.mem.startsWith(u8, func_name, "runtime.") or
        std.mem.startsWith(u8, func_name, "syscall.") or
        std.mem.startsWith(u8, func_name, "internal/task."))
    {
        // ZIG GUARD: If this looks like a Go function but has Zig characteristics,
        // it's likely a Zig function (e.g., main.main is Zig's entry point).
        // Zig-specific patterns that override Go detection:
        const has_zig_override = blk: {
            // Zig FQN pattern: Type.functionName (e.g., Io.Writer.defaultFlush)
            // Check for uppercase letter after dot — Zig uses PascalCase for types
            if (std.mem.indexOf(u8, func_name, ".") != null) {
                for (func_name, 0..) |ch, i| {
                    if (ch == '.' and i + 1 < func_name.len) {
                        const next = func_name[i + 1];
                        // PascalCase type name (Io.Writer, std.builtin, etc.) → Zig
                        if (next >= 'A' and next <= 'Z') break :blk true;
                    }
                }
            }

            // Explicit Zig patterns in the function name
            if (std.mem.indexOf(u8, func_name, "@") != null) break :blk true;
            if (std.mem.indexOf(u8, func_name, "__zig_") != null) break :blk true;
            if (std.mem.indexOf(u8, func_name, "Allocator") != null) break :blk true;
            if (std.mem.indexOf(u8, func_name, "zig_") != null) break :blk true;

            // Zig camelCase function names: lowercaseWord followed by UppercaseWord
            // Examples: doubleFreeDemo, useAfterFreeDemo, bufferOverflowDemo
            // This is a strong indicator of Zig/Go-style naming, but combined with
            // other context (like FFI boundary with C functions) it's likely Zig.
            var prev_is_lower = false;
            for (func_name) |ch| {
                if (prev_is_lower and ch >= 'A' and ch <= 'Z') {
                    // Found camelCase transition (e.g., "doubleFree")
                    break :blk true;
                }
                prev_is_lower = ch >= 'a' and ch <= 'z';
            }

            break :blk false;
        };

        if (has_zig_override) {
            return .zig;
        }

        return .go;
    }
    if (std.mem.startsWith(u8, func_name, "C.") or
        std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "_Cfunc_") != null or
        std.mem.indexOf(u8, func_name, "_Cgo_") != null or
        std.mem.indexOf(u8, func_name, "crosscall2") != null or
        std.mem.indexOf(u8, func_name, "runtime.cgocall") != null or
        std.mem.startsWith(u8, func_name, "unionfield_") or
        std.mem.startsWith(u8, func_name, "bitfield_") or
        std.mem.startsWith(u8, func_name, "_Ctype_"))
    {
        return .go;
    }

    // A3: Java JNI / Panama FFM detection (IR spec §7)
    // JVM_* must be excluded FIRST — they are VM-reserved, not user JNI code.
    // Java_* = JNI native methods (IR spec §1.1: Java_<class>_<method> mangling)
    // JNI_* = JNI utility functions
    // Panama FFM: _downcall_stub_*, _upcall_stub_* generated by DowncallLinker/UpcallLinker
    if (std.mem.startsWith(u8, func_name, "JVM_")) return .unknown;
    if (std.mem.startsWith(u8, func_name, "Java_") or
        std.mem.startsWith(u8, func_name, "JNI_") or
        std.mem.startsWith(u8, func_name, "_downcall_stub_") or
        std.mem.startsWith(u8, func_name, "_upcall_stub_"))
    {
        return .java;
    }

    // Objective-C detection (missing from original)
    if (std.mem.startsWith(u8, func_name, "_OBJC_") or
        std.mem.startsWith(u8, func_name, "objc_"))
    {
        return .unknown;
    }

    // Default to C (most common case for C ABI)
    return .c;
}

/// Identify the language of a called function based on its name string.
///
/// Similar to `identifyLanguage()` but operates on a string slice instead of
/// an LLVM value. Used when the caller already has the function name extracted.
///
/// Parameters:
///   - func_name: Function name string to analyze
///
/// Returns:
///   - Detected language enum value
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    // LLVM intrinsics (llvm.* prefix) are compiler-generated,
    // not any language's FFI function. Skip them to prevent
    // misclassification (e.g., llvm.threadlocal.address.p0 as Zig).
    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .unknown;
    }

    // Check for Rust patterns
    for (FFIPatterns.rust_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .rust;
        }
    }

    // Rust v0 mangling prefix (RFC 2603) — _R<hash>...
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'R') return .rust;
    // Rust ownership transfer / drop glue patterns
    const rust_ownership = [_][]const u8{ "into_raw", "from_raw", "drop_in_place" };
    for (rust_ownership) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return .rust;
    }

    // Rust allocator intrinsics — __rust_alloc, __rdl_alloc, __rg_alloc, exchange_malloc.
    // Must be classified as .rust, not .c (otherwise cross_lang_free_mismatch misses them).
    for (ptr_types.RUST_ALLOC_INTRINSICS.all) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return .rust;
    }

    // C++ Itanium mangling (_Z prefix) — but NOT _ZN which is ambiguous
    // between C++ nested names and Rust mangled names.
    // _ZN is handled below with isRustMangledName() disambiguation.
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z' and
        !(func_name.len > 3 and func_name[2] == 'N')) return .cpp;

    // _ZN ambiguity resolution: could be Rust or C++ Itanium nested name.
    // Use multi-layer detection to distinguish:
    //   - Rust: contains '$', has hash suffix (h<hex>E), or known Rust namespace
    //   - C++: std::, STL patterns, no Rust-specific markers
    if (func_name.len > 3 and func_name[0] == '_' and func_name[1] == 'Z' and func_name[2] == 'N') {
        if (isRustMangledName(func_name)) return .rust;
        return .cpp; // Default _ZN without Rust markers → C++
    }

    // P2-a: MSVC x64 / Itanium for C++ mangling detection (?name@@...).
    // MSVC mangling is unambiguous — only Microsoft toolchain uses `?` prefix.
    if (func_name.len > 0 and func_name[0] == '?') return .cpp;

    // Check for Zig patterns (be more specific to avoid false positives)
    for (FFIPatterns.zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            if (std.mem.indexOf(u8, func_name, "zig_") != null or
                std.mem.indexOf(u8, func_name, "@") != null)
            {
                return .zig;
            }
            if (std.mem.eql(u8, pattern, "extern") or std.mem.eql(u8, pattern, "c_")) {
                continue;
            }
            return .zig;
        }
    }
    // Zig allocator patterns
    if (std.mem.indexOf(u8, func_name, "Allocator.") != null or
        std.mem.indexOf(u8, func_name, "allocImpl") != null)
    {
        return .zig;
    }
    // Zig compiler-reserved (IR spec §1.2): __zig_probe_stack, __zig_tag_name_*,
    // __zig_is_named_enum_value_*, __zig_lt_errors_len, __zig_err_name_table
    if (std.mem.startsWith(u8, func_name, "__zig_")) return .zig;

    // Check for libc functions — these are C by definition
    for (FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return .c;
        }
    }

    // A2: Go / TinyGo detection (enhanced with IR spec patterns)
    // Standard Go: main.*, runtime.*, syscall.*
    // TinyGo (IR spec §1.2): runtime.alloc, runtime.free, runtime._panic, etc.
    // TinyGo CGo (IR spec §1.3): _Cgo_*, _Cgo_static_<hash>_*, unionfield_*, bitfield_*
    // TinyGo scheduler: internal/task.*
    if (std.mem.startsWith(u8, func_name, "main.") or
        std.mem.startsWith(u8, func_name, "runtime.") or
        std.mem.startsWith(u8, func_name, "syscall.") or
        std.mem.startsWith(u8, func_name, "internal/task."))
    {
        return .go;
    }
    if (std.mem.startsWith(u8, func_name, "C.") or
        std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "_Cfunc_") != null or
        std.mem.indexOf(u8, func_name, "_Cgo_") != null or
        std.mem.indexOf(u8, func_name, "crosscall2") != null or
        std.mem.indexOf(u8, func_name, "runtime.cgocall") != null or
        std.mem.startsWith(u8, func_name, "unionfield_") or
        std.mem.startsWith(u8, func_name, "bitfield_") or
        std.mem.startsWith(u8, func_name, "_Ctype_"))
    {
        return .go;
    }

    // A3: Java JNI / Panama FFM detection (IR spec §7)
    // JVM_* = VM-reserved, not user JNI code.
    // Java_* = JNI native methods (IR spec §1.1: Java_<class>_<method> mangling)
    // JNI_* = JNI utility functions
    // Panama FFM: _downcall_stub_*, _upcall_stub_* generated by DowncallLinker/UpcallLinker
    if (std.mem.startsWith(u8, func_name, "JVM_")) return .unknown;
    if (isJNIFunction(func_name) or
        std.mem.startsWith(u8, func_name, "JNI_") or
        std.mem.startsWith(u8, func_name, "_downcall_stub_") or
        std.mem.startsWith(u8, func_name, "_upcall_stub_"))
    {
        return .java;
    }

    // Check for Objective-C functions
    if (std.mem.startsWith(u8, func_name, "_OBJC_") or
        std.mem.startsWith(u8, func_name, "objc_"))
    {
        return .unknown;
    }

    // For external declarations with C ABI naming (no Rust/Zig/Go/ObjC
    // patterns), classify as C. This covers extern "C" functions,
    // libc wrappers, and typical C library functions.
    // Internal (non-external) functions default to unknown to avoid
    // misclassifying language-specific internal helpers.
    return .c;
}

/// Platform-aware language classification with Zig/Go disambiguation.
///
/// Extends `identifyCalleeLanguage()` by using module-level context
/// to resolve ambiguities between Zig and Go, which share naming patterns
/// (`main.*` prefix, camelCase function names).
///
/// Disambiguation rules (P2-c / Bug 2 fix):
///   1. If classifyCalleeLanguage returns .go but module_lang == .zig → .zig
///      (Zig's main.main entry point looks like Go's main.main)
///   2. If target triple contains "-none-" (Zig default) and name matches
///      Go patterns → .zig (Zig-compiled modules use -unknown-none-unknown)
///   3. Otherwise: delegate to identifyCalleeLanguage unchanged
///
/// Parameters:
///   - func_name: Function name string
///   - module_lang: The detected language of the containing module (from PassContext)
///   - profile: Optional platform profile for triple-based disambiguation (can be null)
pub fn identifyCalleeLanguageWithContext(
    func_name: []const u8,
    module_lang: Language,
    profile: ?PlatformProfile,
) Language {
    const base_result = identifyCalleeLanguage(func_name);

    // Only disambiguate when base result is .go — other languages are unambiguous
    if (base_result != .go) return base_result;

    // RULE 1: Module-level language override.
    // If the MODULE was detected as Zig (e.g., via __zig_probe_stack presence,
    // zig-specific FQN patterns like Io.Writer.defaultFlush), then even
    // "main.*" prefixed functions are Zig, not Go.
    if (module_lang == .zig) {
        return .zig;
    }

    // RULE 2: Target triple based disambiguation.
    // Zig-compiled modules typically have target triples ending in -none-unknown
    // or -unknown-none-*, while Go (via llgo/Go LLVM IR) uses different triples.
    if (profile) |*prof| {
        const triple = prof.target_triple;
        if (std.mem.indexOf(u8, triple, "-none-") != null) {
            return .zig;
        }
        if (std.mem.indexOf(u8, triple, "-zig-") != null) {
            return .zig;
        }
    }

    // RULE 3: main.* prefixed functions in a non-Go module → Zig (Bug 2 final fix).
    //
    // CRITICAL CONTEXT: combined.bc (linked bitcode) has the C module's triple
    // (e.g., aarch64-apple-macosx15.7.3-unknown), NOT Zig's -none- triple.
    // So RULE 2 (-none- check) NEVER fires for linked bitcode files.
    //
    // Key insight: Real Go modules ALWAYS produce strong Go detection signals
    // (runtime.*, syscall.*, _Cgo_*, gcops.*) that make detectModuleLanguage()
    // return .go with high confidence. If module_lang is .c/.unknown/.cpp despite
    // seeing "main.*" prefixed functions, those functions are from Zig, not Go.
    //
    // Both Zig and Go use "package.function" naming with "main." prefix:
    //   - Zig: main.main, main.dangerousFFICalls, main.safeFFICalls
    //   - Go:  main.main, main.foo, runtime.gcstart
    //
    // Disambiguation: Go modules have abundant runtime.* signals that make
    // detectModuleLanguage() return .go. Zig modules lack these signals.
    //
    // This rule is safe because:
    //   - Go modules → detectModuleLanguage() returns .go → RULE 3 skipped
    //   - Zig modules → detectModuleLanguage() returns .c/.unknown → RULE 3 fires
    //   - Mixed modules → handled by RULE 1 (module_lang == .zig override)
    if (std.mem.startsWith(u8, func_name, "main.") and module_lang != .go) {
        return .zig;
    }

    // No override applicable — keep original .go classification
    return base_result;
}

/// Demangle a Rust mangled name to a readable format.
///
/// Rust uses Itanium-style mangling (`_ZN...E`). This function extracts
/// the crate and module path components for human-readable diagnostics.
///
/// Parameters:
///   - allocator: Memory allocator for output string
///   - mangled: Mangled Rust symbol name
///
/// Returns:
///   - Demangled name (caller must free), or null if not a Rust mangled name
pub fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
    if (mangled.len < 4 or mangled[0] != '_' or mangled[1] != 'Z' or mangled[2] != 'N') {
        return null;
    }

    var pos: usize = 3;
    var components: [3][]const u8 = .{ "", "", "" };
    var comp_count: usize = 0;

    while (pos < mangled.len and comp_count < 3) {
        if (mangled[pos] == 'E') break;

        var len: usize = 0;
        while (pos < mangled.len and mangled[pos] >= '0' and mangled[pos] <= '9') {
            const new_len = std.math.mul(usize, len, 10) catch break;
            const digit = @as(usize, mangled[pos] - '0');
            len = std.math.add(usize, new_len, digit) catch break;
            pos += 1;
        }

        if (len == 0 or pos >= mangled.len or pos + len > mangled.len) break;
        if (len > 50) break;

        const slice = mangled[pos .. pos + len];
        pos += len;

        if (slice.len == 0) continue;
        if (slice[0] == '$' or slice[0] == 'C' or slice[0] == '{' or slice[0] == '}') {
            if (pos < mangled.len and mangled[pos] == 'E') pos += 1;
            continue;
        }

        if (comp_count == 0) {
            if (std.mem.eql(u8, slice, "core") or
                std.mem.eql(u8, slice, "alloc") or
                std.mem.eql(u8, slice, "std") or
                std.mem.eql(u8, slice, "rust_ffi_demo"))
            {
                components[0] = slice;
                comp_count = 1;
                continue;
            }
        }

        if (comp_count > 0 or
            (!std.mem.eql(u8, slice, "core") and
                !std.mem.eql(u8, slice, "alloc") and
                !std.mem.eql(u8, slice, "std")))
        {
            components[comp_count] = slice;
            comp_count += 1;
        }

        if (pos < mangled.len and mangled[pos] == 'E') {
            pos += 1;
            break;
        }
    }

    if (comp_count >= 2) {
        return (try std.fmt.allocPrint(allocator, "{s}::{s}", .{ components[0], components[1] }));
    } else if (comp_count == 1) {
        return (try allocator.dupe(u8, components[0]));
    }

    return (try allocator.dupe(u8, mangled));
}

/// Classify the FFI boundary kind based on caller and callee languages.
///
/// Maps language pairs to specific boundary kinds:
/// - Rust -> C: `.rust_to_c`
/// - Zig -> C: `.zig_to_c`
/// - C -> Rust: `.c_to_rust`
/// - C -> Zig: `.c_to_zig`
/// - Other combinations: `.external_unknown`
///
/// Parameters:
///   - caller_lang: Detected language of the calling function
///   - callee_lang: Detected language of the called function
///
/// Returns:
///   - Boundary kind enum value
pub fn classifyBoundaryKind(caller_lang: Language, callee_lang: Language) BoundaryKind {
    return switch (caller_lang) {
        .rust => switch (callee_lang) {
            .c => .rust_to_c,
            .zig => .external_unknown,
            else => .external_unknown,
        },
        .zig => switch (callee_lang) {
            .c => .zig_to_c,
            .rust => .external_unknown,
            else => .external_unknown,
        },
        .c => switch (callee_lang) {
            .rust => .c_to_rust,
            .zig => .c_to_zig,
            else => .external_unknown,
        },
        else => .external_unknown,
    };
}

/// Check if a function name matches a known libc function.
///
/// Uses exact string matching against a comprehensive list of standard
/// C library functions (memory, string, I/O, threading, networking, dynamic loading).
///
/// Parameters:
///   - func_name: Function name to check
///
/// Returns:
///   - true if it's a known libc function
pub fn isLibcFunction(func_name: []const u8) bool {
    for (FFIPatterns.libc_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return true;
        }
    }
    return false;
}

/// Classify FFI boundary with enhanced detection for dynamic loading/JNI/Python.
///
/// Extends `classifyBoundaryKind()` by checking for:
/// - Dynamic loading functions (dlopen/dlsym/dlclose)
/// - JNI functions (Java Native Interface)
/// - Python C API functions
///
/// If none of these special families match, falls back to standard classification.
///
/// Parameters:
///   - caller_lang: Detected language of the calling function
///   - callee_lang: Detected language of the called function
///   - func_name: Name of the called function
///
/// Returns:
///   - Boundary kind enum value (may be special kind like .dynamic_loading)
pub fn classify_boundary_kind_enhanced(caller_lang: Language, callee_lang: Language, func_name: []const u8) BoundaryKind {
    if (isDynamicLoadingFunction(func_name)) return .dynamic_loading;
    if (isJNIFunction(func_name)) return .jni_call;
    if (isPythonCApiFunction(func_name)) return .python_c_api_call;
    return classifyBoundaryKind(caller_lang, callee_lang);
}

/// Alias for classify_boundary_kind_enhanced (camelCase variant).
pub const classifyBoundaryKindEnhanced = classify_boundary_kind_enhanced;

/// Check if a function is a POSIX dynamic loading function.
///
/// Detects: dlopen, dlsym, dlclose
pub fn isDynamicLoadingFunction(func_name: []const u8) bool {
    const dl_patterns = [_][]const u8{ "dlopen", "dlsym", "dlclose" };
    for (dl_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a Java Native Interface (JNI) function.
///
/// Detects JNI prefixes (`JNI_`, `Java_`) and common JNI method names
/// (FindClass, GetMethodID, NewObject, Call*Method, etc.)
pub fn isJNIFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "JNI_")) return true;
    if (std.mem.startsWith(u8, func_name, "Java_")) return true;
    const jni_patterns = [_][]const u8{
        "FindClass",                "GetMethodID",             "GetStaticMethodID",
        "GetFieldID",               "GetStaticFieldID",        "NewObject",
        "CallVoidMethod",           "CallIntMethod",           "CallObjectMethod",
        "CallStaticVoidMethod",     "CallStaticIntMethod",     "CallStaticObjectMethod",
        "CallNonvirtualVoidMethod", "CallNonvirtualIntMethod", "NewStringUTF",
        "NewGlobalRef",             "NewLocalRef",             "DeleteGlobalRef",
        "DeleteLocalRef",           "NewByteArray",            "AttachCurrentThread",
        "DetachCurrentThread",      "GetEnv",                  "GetJavaVM",
        "MonitorEnter",             "MonitorExit",             "ExceptionCheck",
        "ExceptionClear",           "ExceptionDescribe",       "ExceptionOccurred",
        "Throw",                    "ThrowNew",                "GetStringUTFChars",
        "ReleaseStringUTFChars",    "GetObjectField",          "SetObjectField",
        "GetIntField",              "SetIntField",             "IsSameObject",
        "IsInstanceOf",
    };
    for (jni_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a Python C API function.
///
/// Detects Python C API prefixes (`Py_`, `Py`) and common patterns
/// (PyArg_*, PyBool*, PyDict*, PyErr_*, etc.)
pub fn isPythonCApiFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "Py_")) return true;
    if (std.mem.startsWith(u8, func_name, "Py")) {
        const py_prefixes = [_][]const u8{
            "PyArg_",        "PyBool",        "PyBytes",          "PyCallable",
            "PyDict",        "PyErr_",        "PyEval_",          "PyFile",
            "PyFloat",       "PyFrame",       "PyFrozenSet",      "PyGC_",
            "PyGetSetDescr", "PyHash",        "PyImport_",        "PyInt_",
            "PyIter",        "PyList_",       "PyLong",           "PyMapping",
            "PyMem_",        "PyMethodDescr", "PyModule_",        "PyObject_",
            "PyProperty",    "PyRange",       "PySeqIter",        "PySet_",
            "PySlice",       "PyString",      "PyStructSequence", "PySys_",
            "PyThreadState", "PyTraceBack",   "PyTuple_",         "PyType",
            "PyUnicode",     "PyWeakref",     "PyCapsule",
        };
        for (py_prefixes) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
    }
    const py_gil_patterns = [_][]const u8{
        "PyGILState_",            "PyEval_InitThreads",
        "PyEval_RestoreThread",   "PyEval_SaveThread",
        "Py_BEGIN_ALLOW_THREADS", "Py_END_ALLOW_THREADS",
    };
    for (py_gil_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function is a C++ ABI internal function (__cxa_*).
/// Delegated to unified ffi_utils (single source of truth).
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    return ffi_utils.isCppAbiInternalFunction(func_name);
}

/// Check if a function is an STL/libc++ internal template expansion.
/// Delegated to unified ffi_utils (single source of truth).
pub fn isStlInternalFunction(func_name: []const u8) bool {
    return ffi_utils.isStlInternalFunction(func_name);
}

/// Multi-layer Rust mangled name detector for _ZN disambiguation.
/// Returns true if the _ZN* symbol is a Rust-mangled name, false for C++ Itanium.
///
/// Detection layers (ordered by reliability):
///   1. '$' presence — Rust uses $LT$, $GT$, $u20$, $RF$ etc.
///   2. Hash suffix — <digits>h<hex_digits>E (Rust v0 symbol versioning)
///   3. Known Rust crate prefixes in _ZN path (e.g., _ZN4core, _ZN3std)
pub fn isRustMangledName(name: []const u8) bool {
    // Layer 0: _R prefix (Rust v0 mangling RFC 2603, Rust 1.37+)
    if (std.mem.startsWith(u8, name, "_R")) return true;

    // Layer 1: '$' separator (fastest check)
    if (std.mem.indexOf(u8, name, "$") != null) return true;

    // Layer 2: Hash suffix pattern — <digits>h<hex_digits>E
    var i: usize = name.len;
    if (i == 0) return false;
    if (name[i - 1] != 'E' and name[i - 1] != 'e') return false;
    i -= 1;
    if (i == 0) return false;
    var hex_len: usize = 0;
    while (i > 0) : (i -= 1) {
        const ch = name[i - 1];
        if ((ch >= '0' and ch <= '9') or
            (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F'))
        {
            hex_len += 1;
        } else if (ch == 'h') {
            if (i > 1 and name[i - 2] >= '0' and name[i - 2] <= '9') return true;
            return false;
        } else break;
    }

    // Layer 3: Known Rust namespace prefixes in Itanium encoding
    const rust_namespaces = [_][]const u8{
        "_ZN4core",      "_ZN3std",       "_ZN3alloc", "_ZN5macro",
        "_ZN9backtrace", "_ZN7panicking",
    };
    for (rust_namespaces) |ns| {
        if (std.mem.startsWith(u8, name, ns)) return true;
    }

    return false;
}

/// Check if a function name uses MSVC x64 / Itanium for C++ mangling.
///
/// MSVC mangled names always start with `?` and contain `@@` separators.
/// Examples:
///   ?square@@YAHH@Z           — int square(int)
///   ??0 MyClass @@ QAEAAV1@ABV1@ — copy constructor
///   ?operator new@@YAPEAX_K@Z  — operator new
pub fn isMsvcMangledName(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '?') return false;
    // Must contain @@ (MSVC name/type separator)
    return std.mem.indexOf(u8, name, "@@") != null;
}

/// Attempt to decode an MSVC mangled name to a human-readable format.
///
/// This is a simplified decoder that extracts the base function name from
/// the mangled form. Full MSVC demangling is extremely complex; this provides
/// a best-effort readable representation for diagnostics.
///
/// Examples:
///   "?square@@YAHH@Z"           → "square"
///   "??0MyClass@@QAE..."       → "MyClass::ctor"
///   "?operator new@@YAPEAX_K@Z" → "operator new"
///
/// Parameters:
///   - allocator: Memory allocator for output string
///   - mangled: MSVC-mangled symbol name (must start with '?')
///
/// Returns:
///   - Decoded name string, or null if not a valid MSVC mangled name
pub fn demangleMsvcName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
    if (!isMsvcMangledName(mangled)) return null;

    // Extract the name between '?' and first '@'
    const at_pos = std.mem.indexOf(u8, mangled, "@") orelse return null;
    if (at_pos <= 1) return null;

    var name = mangled[1..at_pos];

    // Handle special names: ??0 = ctor, ??1 = dtor, etc.
    if (name.len >= 2 and name[0] == '?' and name[1] == '?') {
        const special = name[2..];
        if (special.len >= 1) switch (special[0]) {
            '0' => return try allocator.dupe(u8, "<ctor>"),
            '1' => return try allocator.dupe(u8, "<dtor>"),
            '2' => return try allocator.dupe(u8, "<new>"),
            'G' => return try allocator.dupe(u8, "<scalar_dtor>"),
            else => {},
        };
        return try allocator.dupe(u8, special);
    }

    // Handle operator overloads: ?<op>@
    const operators = [_][]const u8{
        "operator ",    "operator=",       "operator+",      "operator-",         "operator*",
        "operator/",    "operator%",       "operator^",      "operator&",         "operator|",
        "operator~",    "operator!",       "operator<",      "operator>",         "operator+=",
        "operator-=",   "operator*=",      "operator/=",     "operator%=",        "operator^=",
        "operator&=",   "operator|=",      "operator<<",     "operator>>",        "operator<<=",
        "operator>>=",  "operator==",      "operator!=",     "operator<=",        "operator>=",
        "operator()",   "operator[]",      "operator->",     "operator->*",       "operator,",
        "operator new", "operator delete", "operator new[]", "operator delete[]",
    };
    for (operators) |op| {
        if (std.mem.eql(u8, name, op)) return try allocator.dupe(u8, op);
    }

    // Plain name — return as-is
    return try allocator.dupe(u8, name);
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "identifyLanguage - defaults to C for normal functions" {
    // Test that normal C function names are identified as C
    // Note: We cannot test with undefined as it causes undefined behavior
    // Instead, test with a typical C function name
    const result = identifyCalleeLanguage("my_function");
    try std.testing.expectEqual(Language.c, result);
}

test "isLibcFunction - known functions" {
    try std.testing.expect(isLibcFunction("malloc"));
    try std.testing.expect(isLibcFunction("free"));
    try std.testing.expect(isLibcFunction("pthread_create"));
    try std.testing.expect(!isLibcFunction("my_custom_func"));
}

test "isDynamicLoadingFunction - dlopen family" {
    try std.testing.expect(isDynamicLoadingFunction("dlopen"));
    try std.testing.expect(isDynamicLoadingFunction("dlsym"));
    try std.testing.expect(isDynamicLoadingFunction("dlclose"));
    try std.testing.expect(!isDynamicLoadingFunction("malloc"));
}

test "isCppAbiInternalFunction - __cxa_ functions" {
    try std.testing.expect(isCppAbiInternalFunction("__cxa_throw"));
    try std.testing.expect(isCppAbiInternalFunction("__cxa_begin_catch"));
    try std.testing.expect(isCppAbiInternalFunction("__cxa_atexit"));
    try std.testing.expect(!isCppAbiInternalFunction("my_function"));
}

test "isStlInternalFunction - STL template expansions" {
    try std.testing.expect(isStlInternalFunction("_ZNSt3__vector"));
    try std.testing.expect(isStlInternalFunction("_ZNSt6__map"));
    try std.testing.expect(isStlInternalFunction("_ZNSt10__deque"));
    try std.testing.expect(isStlInternalFunction("__gnu_debug"));
    try std.testing.expect(!isStlInternalFunction("my_function"));
    try std.testing.expect(!isStlInternalFunction("std::vector"));
}

test "delegation equivalence - isCppAbiInternalFunction matches ffi_utils" {
    const test_cases = [_][]const u8{
        "__cxa_throw",              "__cxa_begin_catch",    "__cxa_end_catch",
        "__cxa_allocate_exception", "__cxa_free_exception", "__cxa_guard_acquire",
        "__cxa_guard_release",      "__cxa_pure_virtual",   "__cxa_demangle",
        "my_func",                  "malloc",               "_ZNSt3__vector",
    };
    for (test_cases) |name| {
        const local = isCppAbiInternalFunction(name);
        const authority = ffi_utils.isCppAbiInternalFunction(name);
        try std.testing.expectEqual(authority, local);
    }
}

test "delegation equivalence - isStlInternalFunction matches ffi_utils" {
    const test_cases = [_][]const u8{
        "_ZNSt3__vector", "_ZNSt6__map", "_ZNSt7__set",
        "_ZNSt10__deque", "__gnu_debug", "__gnu_parallel",
        "my_func",        "malloc",      "__cxa_throw",
    };
    for (test_cases) |name| {
        const local = isStlInternalFunction(name);
        const authority = ffi_utils.isStlInternalFunction(name);
        try std.testing.expectEqual(authority, local);
    }
}

// ============================================================================
// P2-a: MSVC Mangling Detection Tests
// ============================================================================

test "isMsvcMangledName - basic detection" {
    // Standard MSVC mangled names
    try std.testing.expect(isMsvcMangledName("?square@@YAHH@Z"));
    try std.testing.expect(isMsvcMangledName("??0MyClass@@QAEAAV1@ABV1@"));
    try std.testing.expect(isMsvcMangledName("?operator new@@YAPEAX_K@Z"));

    // Non-MSVC names
    try std.testing.expect(!isMsvcMangledName("_ZN4core3ptr5dangleE")); // Rust Itanium
    try std.testing.expect(!isMsvcMangledName("_Z3fooi")); // C++ Itanium
    try std.testing.expect(!isMsvcMangledName("malloc")); // Plain C
    try std.testing.expect(!isMsvcMangledName("main")); // Plain C
    try std.testing.expect(!isMsvcMangledName("?single_no_at")); // ? without @@
}

test "identifyCalleeLanguage - MSVC mangled names classified as cpp (P2-a)" {
    // All MSVC-mangled names should be identified as C++
    try std.testing.expectEqual(.cpp, identifyCalleeLanguage("?square@@YAHH@Z"));
    try std.testing.expectEqual(.cpp, identifyCalleeLanguage("??0MyClass@@QAEAAV1@ABV1@"));
    try std.testing.expectEqual(.cpp, identifyCalleeLanguage("?operator new@@YAPEAX_K@Z"));
    try std.testing.expectEqual(.cpp, identifyCalleeLanguage("??1MyClass@@UAE@XZ")); // dtor
    try std.testing.expectEqual(.cpp, identifyCalleeLanguage("??_G@@AEPAXI@Z")); // scalar_dtor

    // MinGW plain C names should NOT be misclassified as C++ (no ? prefix)
    try std.testing.expectEqual(.c, identifyCalleeLanguage("malloc"));
    try std.testing.expectEqual(.c, identifyCalleeLanguage("_malloc")); // MinGW underscore prefix
}

test "demangleMsvcName - basic name extraction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const r1 = try demangleMsvcName(allocator, "?square@@YAHH@Z");
    if (r1) |v| {
        defer allocator.free(v);
        try std.testing.expectEqualStrings("square", v);
    }

    const r2 = try demangleMsvcName(allocator, "?operator new@@YAPEAX_K@Z");
    if (r2) |v| {
        defer allocator.free(v);
        try std.testing.expectEqualStrings("operator new", v);
    }

    // Constructor: ??0 → <ctor>
    const r3 = try demangleMsvcName(allocator, "??0MyClass@@QAEAAV1@");
    if (r3) |v| {
        defer allocator.free(v);
        try std.testing.expectEqualStrings("<ctor>", v);
    }

    // Destructor: ??1 → <dtor>
    const r4 = try demangleMsvcName(allocator, "??1MyClass@@UAE@XZ");
    if (r4) |v| {
        defer allocator.free(v);
        try std.testing.expectEqualStrings("<dtor>", v);
    }

    // Scalar deleting destructor: ??G
    const r5 = try demangleMsvcName(allocator, "??_G@@AEPAXI@Z");
    if (r5) |v| {
        defer allocator.free(v);
        try std.testing.expectEqualStrings("<scalar_dtor>", v);
    }

    // Non-MSVC name returns null
    const r6 = try demangleMsvcName(allocator, "malloc");
    try std.testing.expect(r6 == null);
}
