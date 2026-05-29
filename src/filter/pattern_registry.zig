//! Pattern Registry — Single Source of Truth for Function Name Matching
//!
//! Consolidates ~565 patterns from 4 source files into comptime arrays
//! with zero runtime overhead. Original source files preserved (callers exist).
//!
//! Query functions: isStdlibInternal, isRuntimeShim, classifyCSafety,
//!   classifyZone, isLLVMIntrinsic, isCompilerInternal, isIntentionalPattern,
//!   isDangerousCFunction, isLanguageInternal, isCryptoPrimitive, isTableDriven,
//!   isStdlibPath, isFFIPattern, layer1NoiseFilter.
//!
//! Matching: prefix (startsWith), contains (indexOf), exact (eql).

const std = @import("std");
const PatternData = @import("pattern_registry_data.zig").PatternData;

/// Three-tier C function safety classification for @cImport bindings.
pub const CSafetyLevel = enum {
    dangerous, // Always warn — system, strcpy, gets, etc.
    conditional, // Warn if suspicious args — malloc, memcpy, etc.
    safe, // No warning — strlen, strcmp, etc.
};

/// Zone classification result for function name matching.
pub const ZoneClassification = enum {
    safe, // Language guarantees — skip analysis.
    escape, // Explicit safety escape — focus analysis.
    unknown, // No pattern matched — caller decides.
};

pub const PatternRegistry = struct {
    // NOTE: Some patterns intentionally appear in multiple arrays.
    // This is by design — each array serves a different query function:
    //   - drop_in_place: rust_safe_patterns (safe context) + rust_runtime_patterns (runtime shim)
    //   - __rust_alloc/__rust_dealloc: rust_safe_patterns + rust_runtime_patterns
    //   - pthread_create: c_escape_patterns + cpp_escape_patterns
    // Changes to one array must consider the other to avoid semantic drift.

    // LLVM Intrinsics & Rust Synthetic (noise_reduction.zig) — prefix/contains match
    pub const llvm_intrinsic_prefixes = PatternData.llvm_intrinsic_prefixes;
    /// Rust safe primitives — channels, smart ptrs, iterators (contains match).
    pub const rust_synthetic_patterns = PatternData.rust_synthetic_patterns;

    // Zone Safe/Escape Patterns (zone_types.zig) — contains match
    pub const rust_safe_patterns = PatternData.rust_safe_patterns;
    pub const rust_escape_patterns = PatternData.rust_escape_patterns;
    pub const zig_safe_patterns = PatternData.zig_safe_patterns;
    pub const zig_escape_patterns = PatternData.zig_escape_patterns;
    pub const go_safe_patterns = PatternData.go_safe_patterns;
    pub const go_escape_patterns = PatternData.go_escape_patterns;
    pub const cpp_safe_patterns = PatternData.cpp_safe_patterns;
    pub const cpp_escape_patterns = PatternData.cpp_escape_patterns;
    pub const c_escape_patterns = PatternData.c_escape_patterns;

    // C Safety Three-Tier (ffi_zone_check.zig) — exact match
    /// Layer 1: Never safe — always warn.
    pub const c_import_blacklist = PatternData.c_import_blacklist;
    /// Layer 2: Safe only when used correctly.
    pub const c_import_conditional = PatternData.c_import_conditional;
    /// Layer 3: Presumed safe.
    pub const c_import_safe = PatternData.c_import_safe;
    /// Absolute blacklist — CWE-120/134/787 (exact match).
    pub const dangerous_c_functions = PatternData.dangerous_c_functions;

    // Zig/Go Internal (ffi_zone_check.zig) — contains match
    pub const zig_internal_patterns = PatternData.zig_internal_patterns;
    /// Broad Zig internal markers (contains match).
    /// These are more general than specific function names above.
    pub const zig_broad_internal_patterns = PatternData.zig_broad_internal_patterns;
    pub const go_internal_patterns = PatternData.go_internal_patterns;
    pub const go_runtime_extra = PatternData.go_runtime_extra;

    // FFI Language Patterns (ffi_zone_check.zig) — contains match
    pub const rust_ffi_patterns = PatternData.rust_ffi_patterns;
    pub const zig_ffi_patterns = PatternData.zig_ffi_patterns;
    pub const go_ffi_patterns = PatternData.go_ffi_patterns;

    // Intentional/Test Patterns (ffi_zone_check.zig)
    pub const intentional_prefixes = PatternData.intentional_prefixes;
    pub const intentional_substrings = PatternData.intentional_substrings;

    // Stdlib Prefixes — Pattern G (issue_suppression.zig)
    pub const zig_stdlib_prefixes = PatternData.zig_stdlib_prefixes;
    pub const rust_stdlib_prefixes = PatternData.rust_stdlib_prefixes;
    /// C++ stdlib — contains match (not prefix).
    pub const cpp_stdlib_patterns = PatternData.cpp_stdlib_patterns;

    // Compiler Builtins (issue_suppression.zig) — prefix match
    pub const compiler_builtins = PatternData.compiler_builtins;

    // Platform Runtime Shims — Pattern H (issue_suppression.zig)
    /// C++ allocators — Itanium ABI mangled (contains match).
    pub const cpp_alloc_patterns = PatternData.cpp_alloc_patterns;
    /// C++ ABI runtime (prefix match).
    pub const cpp_abi_prefixes = PatternData.cpp_abi_prefixes;
    /// Objective-C runtime (contains match).
    pub const objc_patterns = PatternData.objc_patterns;
    /// Swift runtime (prefix match).
    pub const swift_patterns = PatternData.swift_patterns;
    /// Go runtime (prefix match).
    pub const go_runtime_patterns = PatternData.go_runtime_patterns;
    /// Rust runtime (contains match).
    pub const rust_runtime_patterns = PatternData.rust_runtime_patterns;
    /// Zig runtime (contains match).
    pub const zig_runtime_patterns = PatternData.zig_runtime_patterns;
    /// Sanitizer runtimes (prefix match).
    pub const sanitizer_prefixes = PatternData.sanitizer_prefixes;
    /// Dynamic linker / CRT (contains match).
    pub const dl_patterns = PatternData.dl_patterns;

    // Windows MSVC CRT (issue_suppression.zig) — contains match
    pub const seh_patterns = PatternData.seh_patterns;
    pub const crt_init_patterns = PatternData.crt_init_patterns;
    pub const msvc_security = PatternData.msvc_security;
    pub const tls_patterns = PatternData.tls_patterns;

    // Crypto Primitives (issue_suppression.zig) — contains match
    pub const cipher_names = PatternData.cipher_names;
    pub const hash_names = PatternData.hash_names;
    pub const pk_names = PatternData.pk_names;
    pub const mac_names = PatternData.mac_names;

    // Table-Driven & Compiler Internal (issue_suppression.zig)
    pub const table_signals = PatternData.table_signals;
    /// Mangled name compiler-internal patterns (prefix match).
    pub const compiler_internal_patterns = PatternData.compiler_internal_patterns;

    // Stdlib Paths (noise_reduction.zig) — contains match
    pub const rust_stdlib_paths = PatternData.rust_stdlib_paths;
    pub const zig_stdlib_paths = PatternData.zig_stdlib_paths;
    pub const cpp_stdlib_paths = PatternData.cpp_stdlib_paths;

    // Noise Filter Patterns (noise_reduction.zig) — contains match
    pub const rust_noise_patterns = PatternData.rust_noise_patterns;
    pub const zig_noise_patterns = PatternData.zig_noise_patterns;
    pub const cpp_noise_patterns = PatternData.cpp_noise_patterns;

    // Query Functions
    /// Check if a function is a stdlib/internal function (Pattern G).
    /// Covers Zig/Rust/C++ stdlib prefixes and compiler builtins.
    pub fn isStdlibInternal(func_name: []const u8) bool {
        if (func_name.len == 0) return false;
        for (zig_stdlib_prefixes) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        for (rust_stdlib_prefixes) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        for (cpp_stdlib_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (compiler_builtins) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        return false;
    }

    /// Check if a function is a platform runtime / compiler shim (Pattern H).
    /// Platform-agnostic — callers gate Windows patterns via isWindowsMsvcRuntime.
    pub fn isRuntimeShim(func_name: []const u8) bool {
        return isGenericRuntimeShim(func_name) or isWindowsMsvcRuntime(func_name);
    }

    /// Cross-platform runtime shim patterns (no Windows-specific checks).
    pub fn isGenericRuntimeShim(func_name: []const u8) bool {
        for (cpp_alloc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (cpp_abi_prefixes) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        for (objc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (swift_patterns) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        for (go_runtime_patterns) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        for (rust_runtime_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (zig_runtime_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        if (std.mem.startsWith(u8, func_name, "llvm.")) return true;
        for (sanitizer_prefixes) |p| {
            if (std.mem.startsWith(u8, func_name, p)) return true;
        }
        if (std.mem.indexOf(u8, func_name, "__stack_chk") != null) return true;
        for (dl_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Windows MSVC CRT / runtime patterns. Only consult on Windows targets.
    pub fn isWindowsMsvcRuntime(func_name: []const u8) bool {
        for (seh_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (crt_init_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (msvc_security) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (tls_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        if (func_name.len > 0 and func_name[0] == '?') {
            if (std.mem.indexOf(u8, func_name, "?_type_info@") != null) return true;
            if (std.mem.indexOf(u8, func_name, "??_R") != null) return true;
            if (std.mem.indexOf(u8, func_name, "??_7") != null) return true;
        }
        return false;
    }

    /// Classify C function safety level for @cImport bindings.
    /// Returns null for unknown functions (conservative: analyze).
    pub fn classifyCSafety(func_name: []const u8) ?CSafetyLevel {
        for (c_import_blacklist) |p| {
            if (std.mem.eql(u8, func_name, p)) return .dangerous;
        }
        for (c_import_conditional) |p| {
            if (std.mem.eql(u8, func_name, p)) return .conditional;
        }
        for (c_import_safe) |p| {
            if (std.mem.eql(u8, func_name, p)) return .safe;
        }
        return null;
    }

    /// Classify function zone for a specific language.
    /// Checks safe patterns first (skip), then escape triggers (focus).
    pub fn classifyZone(func_name: []const u8, comptime lang: enum { rust, zig, go, cpp, c }) ZoneClassification {
        return switch (lang) {
            .rust => {
                for (rust_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (rust_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .zig => {
                for (zig_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (zig_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .go => {
                for (go_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (go_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .cpp => {
                for (cpp_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (cpp_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .c => {
                for (c_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
        };
    }

    /// Check if a function is an LLVM intrinsic or Rust synthetic noise.
    /// Any "llvm.*" is noise. Rust synthetic (channels, smart ptrs, iterators) too.
    pub fn isLLVMIntrinsic(func_name: []const u8) bool {
        if (std.mem.startsWith(u8, func_name, "llvm.")) {
            for (llvm_intrinsic_prefixes) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) return true;
            }
            return true; // Catch-all for unrecognized llvm.* intrinsics
        }
        for (rust_synthetic_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a mangled name is compiler-internal (precise whitelist).
    /// Patterns: _ZNSt (C++ std), _ZN4core (Rust), $ss/$sS (Swift), etc.
    pub fn isCompilerInternal(func_name: []const u8) bool {
        for (compiler_internal_patterns) |pattern| {
            if (std.mem.startsWith(u8, func_name, pattern)) return true;
        }
        return false;
    }

    /// Check if function name indicates intentional safe/test code.
    /// Matches safe_*, test_*, demo_*, bench_*, mock_* and substrings
    /// like "intentional", "known_safe".
    pub fn isIntentionalPattern(func_name: []const u8) bool {
        for (intentional_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return true;
        }
        for (intentional_substrings) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a C function is in the absolute blacklist.
    /// CWE-120, CWE-134, CWE-787 — always dangerous.
    pub fn isDangerousCFunction(func_name: []const u8) bool {
        for (dangerous_c_functions) |p| {
            if (std.mem.eql(u8, func_name, p)) return true;
        }
        return false;
    }

    /// Check if a function is a Zig/Go internal runtime function (safe, skip FFI).
    pub fn isLanguageInternal(func_name: []const u8) bool {
        for (zig_internal_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (zig_broad_internal_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (go_internal_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (go_runtime_extra) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a function name indicates a cryptographic primitive.
    /// Covers ciphers, hashes, public key, MAC/KDF.
    pub fn isCryptoPrimitive(func_name: []const u8) bool {
        for (cipher_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (hash_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (pk_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (mac_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        return false;
    }

    /// Check if a function name suggests table-driven implementation.
    /// Table-driven crypto loads function pointer tables from .text — alloca FPs.
    pub fn isTableDriven(func_name: []const u8) bool {
        for (table_signals) |signal| {
            if (std.mem.indexOf(u8, func_name, signal) != null) return true;
        }
        return false;
    }

    /// Check if a debug file path indicates stdlib/compiler origin.
    /// Matches Rust, Zig, C++ path prefixes (case-insensitive for Windows).
    pub fn isStdlibPath(file_path: []const u8) bool {
        for (rust_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        for (zig_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        for (cpp_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        return false;
    }

    /// Check if a function name matches any FFI language pattern (Rust/Zig/Go).
    pub fn isFFIPattern(func_name: []const u8) bool {
        for (rust_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (zig_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (go_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Layer 1 noise filter: check if function name matches stdlib/compiler.
    /// Returns reason string if should be filtered, null if should analyze.
    pub fn layer1NoiseFilter(func_name: []const u8) ?[]const u8 {
        if (isLLVMIntrinsic(func_name)) return "LLVM intrinsic (compiler-generated)";
        for (rust_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "Rust stdlib/compiler pattern";
        }
        for (zig_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "Zig stdlib/internal pattern";
        }
        for (cpp_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "C++ STL/compiler pattern";
        }
        return null;
    }
    // Internal Helpers
    fn indexOfPath(haystack: []const u8, needle: []const u8) bool {
        if (haystack.len == 0 or needle.len == 0) return false;
        if (needle.len > haystack.len) return false;
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
        // Case-insensitive fallback for Windows paths
        var i: usize = 0;
        const max_start = haystack.len - needle.len;
        while (i <= max_start) : (i += 1) {
            var match = true;
            for (needle, 0..) |needle_char, j| {
                const hc = haystack[i + j];
                const nc = needle_char;
                // Convert backslashes to forward slashes for comparison
                const h_normalized: u8 = if (hc == '\\') '/' else hc;
                const n_normalized: u8 = if (nc == '\\') '/' else nc;
                if (std.ascii.toLower(h_normalized) != std.ascii.toLower(n_normalized)) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }
};
const P = PatternRegistry;

test "isStdlibInternal: Zig/Rust/C++ stdlib and builtins" {
    // Zig
    try std.testing.expect(P.isStdlibInternal("debug.Dwarf"));
    try std.testing.expect(P.isStdlibInternal("hash_map.getOrPut"));
    try std.testing.expect(P.isStdlibInternal("std.mem.copy"));
    try std.testing.expect(P.isStdlibInternal("Io.Writer.writeAll"));
    try std.testing.expect(!P.isStdlibInternal("my_function"));
    // Rust
    try std.testing.expect(P.isStdlibInternal("core::fmt::write"));
    try std.testing.expect(P.isStdlibInternal("alloc::vec::Vec::new"));
    try std.testing.expect(!P.isStdlibInternal("mylib::core::func"));
    // Compiler builtins
    try std.testing.expect(P.isStdlibInternal("__builtin_memcpy"));
    try std.testing.expect(P.isStdlibInternal("__cxa_throw"));
    try std.testing.expect(P.isStdlibInternal("__asan_report_load1"));
    try std.testing.expect(!P.isStdlibInternal("__cinit__"));
    try std.testing.expect(!P.isStdlibInternal("__custom_helper"));
}

test "isRuntimeShim: C++/ObjC/Swift/Go/Rust/Zig/MSVC runtimes" {
    // C++ allocators
    try std.testing.expect(P.isRuntimeShim("_Znwm"));
    try std.testing.expect(P.isRuntimeShim("operator new"));
    // ObjC/Swift
    try std.testing.expect(P.isRuntimeShim("objc_msgSend"));
    try std.testing.expect(P.isRuntimeShim("swift_retain"));
    // Go/Rust/Zig
    try std.testing.expect(P.isRuntimeShim("runtime.gc"));
    try std.testing.expect(P.isRuntimeShim("__rust_dealloc"));
    try std.testing.expect(P.isRuntimeShim("__zig_probe_stack"));
    // LLVM intrinsics
    try std.testing.expect(P.isRuntimeShim("llvm.lifetime.start.p0i8"));
    // Windows MSVC
    try std.testing.expect(P.isRuntimeShim("__except_handler4"));
    try std.testing.expect(P.isRuntimeShim("_initterm"));
    try std.testing.expect(P.isRuntimeShim("__security_check_cookie"));
}

test "isGenericRuntimeShim: excludes Windows patterns" {
    try std.testing.expect(P.isGenericRuntimeShim("_Znwm"));
    try std.testing.expect(P.isGenericRuntimeShim("objc_msgSend"));
    try std.testing.expect(!P.isGenericRuntimeShim("__except_handler4"));
    try std.testing.expect(!P.isGenericRuntimeShim("_initterm"));
    try std.testing.expect(!P.isGenericRuntimeShim("__security_check_cookie"));
}
test "isWindowsMsvcRuntime: SEH/CRT/security/RTTI" {
    try std.testing.expect(P.isWindowsMsvcRuntime("__except_handler4"));
    try std.testing.expect(P.isWindowsMsvcRuntime("___CxxFrameHandler3"));
    try std.testing.expect(P.isWindowsMsvcRuntime("_initterm"));
    try std.testing.expect(P.isWindowsMsvcRuntime("__security_check_cookie"));
    try std.testing.expect(P.isWindowsMsvcRuntime("TlsCallback_0"));
    try std.testing.expect(P.isWindowsMsvcRuntime("?_type_info@Foo@@"));
    try std.testing.expect(!P.isWindowsMsvcRuntime("my_function"));
}
test "classifyCSafety: three-tier classification" {
    // Layer 1: Dangerous
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("system").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("strcpy").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("printf").?);
    // Layer 2: Conditional
    try std.testing.expectEqual(CSafetyLevel.conditional, P.classifyCSafety("malloc").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, P.classifyCSafety("memcpy").?);
    // Layer 3: Safe
    try std.testing.expectEqual(CSafetyLevel.safe, P.classifyCSafety("strlen").?);
    try std.testing.expectEqual(CSafetyLevel.safe, P.classifyCSafety("sqrt").?);
    // Unknown
    try std.testing.expectEqual(@as(?CSafetyLevel, null), P.classifyCSafety("sqlite3_open"));
}

test "classifyZone: all five languages" {
    // Rust
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std::vec::Vec", .rust));
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("__rust_alloc", .rust));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("std::mem::transmute", .rust));
    try std.testing.expectEqual(ZoneClassification.unknown, P.classifyZone("my_function", .rust));
    // Zig
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std.ArrayList", .zig));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("@ptrCast", .zig));
    // Go
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("runtime.gopark", .go));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("unsafe.Pointer", .go));
    // C++
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std::vector<int>", .cpp));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("reinterpret_cast", .cpp));
    // C
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("dlopen", .c));
    try std.testing.expectEqual(ZoneClassification.unknown, P.classifyZone("strlen", .c));
}

test "isLLVMIntrinsic: intrinsics, Rust synthetic, and real FFI" {
    // LLVM intrinsics
    try std.testing.expect(P.isLLVMIntrinsic("llvm.threadlocal.address"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.lifetime.start.p0i8"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.dbg.declare"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.unknown.intrinsic"));
    // Rust synthetic
    try std.testing.expect(P.isLLVMIntrinsic("sync_channel::channel"));
    try std.testing.expect(P.isLLVMIntrinsic("Waker::wake"));
    try std.testing.expect(P.isLLVMIntrinsic("Arc::<T>::clone"));
    try std.testing.expect(!P.isLLVMIntrinsic("__rust_alloc"));
    try std.testing.expect(!P.isLLVMIntrinsic("__rust_dealloc"));
    // Real FFI NOT filtered
    try std.testing.expect(!P.isLLVMIntrinsic("dlopen"));
    try std.testing.expect(!P.isLLVMIntrinsic("malloc"));
    try std.testing.expect(!P.isLLVMIntrinsic("my_function"));
}

test "isCompilerInternal: C++ std, Rust core/alloc, Swift, and user functions" {
    try std.testing.expect(P.isCompilerInternal("_ZNSt6vectorIiEE"));
    try std.testing.expect(P.isCompilerInternal("_ZN4core9fmt::Formatter"));
    try std.testing.expect(P.isCompilerInternal("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(P.isCompilerInternal("__cxx_global_var_init"));
    try std.testing.expect(P.isCompilerInternal("$sS4base8toString"));
    // User functions NOT matched
    try std.testing.expect(!P.isCompilerInternal("_ZN9my_app4mainE"));
    try std.testing.expect(!P.isCompilerInternal("user_function"));
}

test "isIntentionalPattern: prefixes and substrings" {
    try std.testing.expect(P.isIntentionalPattern("test_malloc"));
    try std.testing.expect(P.isIntentionalPattern("safe_example"));
    try std.testing.expect(P.isIntentionalPattern("demo_ffi"));
    try std.testing.expect(P.isIntentionalPattern("bench_alloc"));
    try std.testing.expect(P.isIntentionalPattern("test_intentional_usage"));
    try std.testing.expect(P.isIntentionalPattern("known_safe_pattern"));
    try std.testing.expect(!P.isIntentionalPattern("my_function"));
}

test "isDangerousCFunction: buffer overflow, command injection, format string" {
    try std.testing.expect(P.isDangerousCFunction("strcpy"));
    try std.testing.expect(P.isDangerousCFunction("system"));
    try std.testing.expect(P.isDangerousCFunction("gets"));
    try std.testing.expect(P.isDangerousCFunction("printf"));
    try std.testing.expect(!P.isDangerousCFunction("memcpy"));
    try std.testing.expect(!P.isDangerousCFunction("strlen"));
}
test "isLanguageInternal: Zig and Go internals" {
    // Zig
    try std.testing.expect(P.isLanguageInternal("zig_assert_fail"));
    try std.testing.expect(P.isLanguageInternal("__zig_bug"));
    try std.testing.expect(P.isLanguageInternal("some_function(generic(T))"));
    try std.testing.expect(!P.isLanguageInternal("user_function"));
    // Go
    try std.testing.expect(P.isLanguageInternal("runtime.gopark"));
    try std.testing.expect(P.isLanguageInternal("runtime.morestack"));
    try std.testing.expect(P.isLanguageInternal("typedmemmove"));
    try std.testing.expect(!P.isLanguageInternal("my_go_func"));
}
test "isCryptoPrimitive: cipher, hash, PK, MAC" {
    try std.testing.expect(P.isCryptoPrimitive("aes_encrypt_block"));
    try std.testing.expect(P.isCryptoPrimitive("sha256_update"));
    try std.testing.expect(P.isCryptoPrimitive("ecdsa_sign"));
    try std.testing.expect(P.isCryptoPrimitive("hmac_sha256"));
    try std.testing.expect(!P.isCryptoPrimitive("my_function"));
}

test "isTableDriven: table/lookup/vtable/dispatch" {
    try std.testing.expect(P.isTableDriven("aes_lookup_table"));
    try std.testing.expect(P.isTableDriven("crypto_dispatch"));
    try std.testing.expect(P.isTableDriven("hw_accelerated"));
    try std.testing.expect(!P.isTableDriven("my_function"));
}
test "isStdlibPath: Rust/Zig/C++ paths including Windows" {
    try std.testing.expect(P.isStdlibPath("/rustc/abc/library/core/src/fmt/mod.rs"));
    try std.testing.expect(P.isStdlibPath("/home/user/zig/lib/std/mem.zig"));
    try std.testing.expect(P.isStdlibPath("/usr/include/c++/13/vector"));
    try std.testing.expect(P.isStdlibPath("C:\\Users\\zig\\lib\\std\\mem.zig"));
    try std.testing.expect(!P.isStdlibPath("/home/user/myproject/src/main.zig"));
}

test "isFFIPattern: Rust/Zig/Go FFI indicators" {
    try std.testing.expect(P.isFFIPattern("extern"));
    try std.testing.expect(P.isFFIPattern("C.free"));
    try std.testing.expect(P.isFFIPattern("_cgo_allocate"));
    try std.testing.expect(P.isFFIPattern("__zig"));
    try std.testing.expect(!P.isFFIPattern("my_function"));
}
test "layer1NoiseFilter: LLVM/Rust/Zig/C++ noise" {
    try std.testing.expect(P.layer1NoiseFilter("llvm.threadlocal.address") != null);
    try std.testing.expect(P.layer1NoiseFilter("core::fmt::write") != null);
    try std.testing.expect(P.layer1NoiseFilter("std.mem.copy") != null);
    try std.testing.expect(P.layer1NoiseFilter("std::vector::push_back") != null);
    try std.testing.expect(P.layer1NoiseFilter("dlopen") == null);
    try std.testing.expect(P.layer1NoiseFilter("my_function") == null);
}
test "pattern count: registry has ~560 consolidated patterns" {
    const total =
        P.llvm_intrinsic_prefixes.len + P.rust_synthetic_patterns.len +
        P.rust_safe_patterns.len + P.rust_escape_patterns.len +
        P.zig_safe_patterns.len + P.zig_escape_patterns.len +
        P.go_safe_patterns.len + P.go_escape_patterns.len +
        P.cpp_safe_patterns.len + P.cpp_escape_patterns.len +
        P.c_escape_patterns.len +
        P.c_import_blacklist.len + P.c_import_conditional.len + P.c_import_safe.len +
        P.dangerous_c_functions.len +
        P.zig_internal_patterns.len + P.zig_broad_internal_patterns.len + P.go_internal_patterns.len + P.go_runtime_extra.len +
        P.rust_ffi_patterns.len + P.zig_ffi_patterns.len + P.go_ffi_patterns.len +
        P.intentional_prefixes.len + P.intentional_substrings.len +
        P.zig_stdlib_prefixes.len + P.rust_stdlib_prefixes.len + P.cpp_stdlib_patterns.len +
        P.compiler_builtins.len +
        P.cpp_alloc_patterns.len + P.cpp_abi_prefixes.len +
        P.objc_patterns.len + P.swift_patterns.len +
        P.go_runtime_patterns.len + P.rust_runtime_patterns.len + P.zig_runtime_patterns.len +
        P.sanitizer_prefixes.len + P.dl_patterns.len +
        P.seh_patterns.len + P.crt_init_patterns.len + P.msvc_security.len + P.tls_patterns.len +
        P.cipher_names.len + P.hash_names.len + P.pk_names.len + P.mac_names.len +
        P.table_signals.len + P.compiler_internal_patterns.len +
        P.rust_stdlib_paths.len + P.zig_stdlib_paths.len + P.cpp_stdlib_paths.len +
        P.rust_noise_patterns.len + P.zig_noise_patterns.len + P.cpp_noise_patterns.len;
    std.debug.print("Total patterns: {d}\n", .{total});
    try std.testing.expect(total > 500);
    try std.testing.expect(total < 750);
}
