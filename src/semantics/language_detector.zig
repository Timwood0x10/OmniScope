//! Unified Language Detector
//!
//! Single source of truth for language identification across all analysis passes.
//! Eliminates the 4 duplicate identifyLanguage() implementations.
//!
//! Two-level detection:
//!   1. Per-function: delegate to ffi_language_classifier (name-pattern matching)
//!   2. Per-module: statistical sampling (R7.2 Language-First)
//!
//! R7.2 Design: At scan entry point, detect source language ONCE, then activate
//! the corresponding zone rules channel. No per-pass adaptation needed.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;

const Language = @import("../diag/issue.zig").FFIBoundary.Language;

/// How the language was detected
pub const DetectionMethod = enum {
    /// Statistical sampling of function name patterns
    sampling,
    /// Could not determine
    unknown,
};

/// Module-level language detection result
pub const LanguageProfile = struct {
    /// Detected source language
    language: Language,
    /// Confidence score (0.0-1.0)
    confidence: f32,
    /// How the detection was made
    method: DetectionMethod,
};

/// Detect the source language of an entire LLVM module.
///
/// This is the R7.2 entry point: called once at scan time, before any
/// analysis passes run. The result is cached in PassContext and used
/// to activate the correct zone rules channel.
///
/// Detection strategy:
///   1. Statistical sampling of function names (primary - stable API)
///   2. Fallback to .unknown -- generic adaptation mode
pub fn detectModuleLanguage(module: c.LLVMModuleRef) LanguageProfile {
    // Single sampling pass — detectFromSampling already handles confidence
    // threshold internally (returns null if confidence < 0.4).
    if (detectFromSampling(module)) |profile| {
        return profile;
    }

    return .{
        .language = .unknown,
        .confidence = 0.0,
        .method = .unknown,
    };
}

/// Detect language by statistically sampling function names.
///
/// Sampling strategy (SAMPLE_SIZE=50 functions):
///   1. Skip LLVM intrinsics (llvm.* prefix)
///   2. Count language-specific patterns:
///      - Rust: _rust_, rs2py_ prefix; _ZN with '$' or hash suffix
///      - Go: main., runtime., syscall., gcops. prefixes
///      - Zig: zig_, Allocator. patterns
///      - C++: _Z prefix (non-_ZN) = plain Itanium without nested names
///      - _ZN (Itanium nested): ambiguous between Rust/C++, resolved by
///        isRustMangledName() multi-layer check
///      - Default: C
const SAMPLE_SIZE: usize = 50;

/// Multi-layer Rust mangled name detector for _ZN disambiguation.
/// Returns true if the symbol is a Rust-mangled name, false for C++ Itanium.
///
/// Detection layers (ordered by reliability):
///   1. '$' presence -- Rust uses $LT$, $GT$, $u20$, $RF$ etc.
///   2. Hash suffix <N>h<hex>E -- Rust incremental compilation hash
///   3. Double-dot path segments (..) -- Rust crate::module encoding
fn isRustMangledName(name: []const u8) bool {
    // Layer 1: '$' separator (fastest check, catches most Rust names)
    if (std.mem.indexOf(u8, name, "$") != null) return true;

    // Layer 2: Hash suffix pattern -- <digits>h<hex_digits>E
    // Example: 17he1b7ec36415abac2E or h575f0ddf6ebefeccE
    // This is unique to Rust's v0 mangling scheme for symbol versioning.
    var i: usize = name.len;
    if (i == 0) return false;
    // Find trailing 'E'
    if (name[i - 1] != 'E') {
        // Also check lowercase 'e' (some toolchains emit this)
        if (name[i - 1] != 'e') return false;
    }
    i -= 1;
    if (i == 0) return false;

    // Scan backward through hex digits
    var hex_len: usize = 0;
    while (i > 0) : (i -= 1) {
        const ch = name[i - 1];
        if (ch >= '0' and ch <= '9' or ch >= 'a' and ch <= 'f' or ch >= 'A' and ch <= 'F') {
            hex_len += 1;
        } else if (ch == 'h') {
            // Found 'h' preceding hex digits -- verify length prefix
            if (i > 1 and name[i - 2] >= '0' and name[i - 2] <= '9') {
                return true;
            }
            return false;
        } else {
            break;
        }
    }

    // Layer 3: Double-dot path segments (core..fmt..Debug style)
    // Rust encodes :: as .. in mangled paths between crate/module/name parts
    if (std.mem.indexOf(u8, name, "..") != null) {
        // But exclude C++ patterns that might have ".." in rare cases
        // by checking for Rust-std patterns like "core.." or "std.."
        if (std.mem.indexOf(u8, name, "core..") != null or
            std.mem.indexOf(u8, name, "std..") != null or
            std.mem.indexOf(u8, name, "alloc..") != null)
        {
            return true;
        }
    }

    return false;
}

fn detectFromSampling(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_count: u32 = 0;
    var go_count: u32 = 0;
    var zig_count: u32 = 0;
    var cpp_count: u32 = 0;
    var c_count: u32 = 0;
    var total: u32 = 0;

    var func = c.LLVMGetFirstFunction(module);
    var sampled: usize = 0;

    while (@intFromPtr(func) != 0 and sampled < SAMPLE_SIZE) : ({
        func = c.LLVMGetNextFunction(func);
        sampled += 1;
    }) {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;

        const name = std.mem.span(name_ptr);

        if (std.mem.startsWith(u8, name, "llvm.")) continue;

        total += 1;

        // Explicit Rust markers (unambiguous)
        if (std.mem.indexOf(u8, name, "_rust_") != null or
            std.mem.indexOf(u8, name, "rs2py_") != null)
        {
            rust_count += 1;
            continue;
        }

        // Go runtime markers (unambiguous)
        if (std.mem.startsWith(u8, name, "main.") or
            std.mem.startsWith(u8, name, "runtime.") or
            std.mem.startsWith(u8, name, "syscall.") or
            std.mem.startsWith(u8, name, "gcops."))
        {
            go_count += 1;
            continue;
        }

        // Zig markers (unambiguous)
        if (std.mem.indexOf(u8, name, "zig_") != null or
            std.mem.indexOf(u8, name, "Allocator.") != null)
        {
            zig_count += 1;
            continue;
        }

        // _ZN (Itanium nested name mangling) -- used by BOTH Rust and C++.
        // Multi-layer disambiguation with increasing specificity:
        //
        // Layer 1: '$' separator -- Rust uses $ for generics/refs/lifetimes
        //   Rust: _ZN103_$LT$ring..ec$u20$as$u20$core..fmt..Debug$GT$3fmt17h...
        //   C++:   _ZN4absl4CordC2INSt3__112basic_stringIcNS2_11char_traits...
        //
        // Layer 2: Hash suffix 'h<hex>E' -- Rust symbol hashing for incremental
        //   compilation. Every Rust _ZN name ends with <len>h<hex_digits>E.
        //   This is the most reliable discriminator when $ is absent.
        //   Rust: ...execute17he1b7ec36415abac2E
        //   C++:   ...set_dataEPKcm (no h-hex-E suffix)
        //
        // Layer 3: Double-dot path segments -- Rust encodes :: as ..
        //   Rust: core..convert..TryFrom (double dots between crate/module)
        //   C++:   std::__1::basic_string (single colon, Itanium-encoded)
        if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
            if (isRustMangledName(name)) {
                rust_count += 1;
            } else {
                cpp_count += 1;
            }
            continue;
        }

        // Plain _Z (non-_ZN) = C++ Itanium mangling (unambiguous)
        if (name.len > 2 and name[0] == '_' and name[1] == 'Z' and name[2] != 'N') {
            cpp_count += 1;
            continue;
        }

        c_count += 1;
    }

    if (total == 0) return null;

    const counts = [_]struct { lang: Language, count: u32 }{
        .{ .lang = .rust, .count = rust_count },
        .{ .lang = .go, .count = go_count },
        .{ .lang = .zig, .count = zig_count },
        .{ .lang = .cpp, .count = cpp_count },
        .{ .lang = .c, .count = c_count },
    };

    var max_count: u32 = 0;
    var dominant: Language = .c;
    for (counts) |entry| {
        if (entry.count > max_count) {
            max_count = entry.count;
            dominant = entry.lang;
        }
    }

    const confidence = @as(f32, @floatFromInt(max_count)) / @as(f32, @floatFromInt(total));

    if (confidence < 0.4) {
        return .{ .language = .unknown, .confidence = 0.3, .method = .sampling };
    }

    return .{
        .language = dominant,
        .confidence = confidence,
        .method = .sampling,
    };
}

/// Identify the language of an LLVM function value.
///
/// This is the **single canonical implementation** used by all analysis passes.
/// Do NOT duplicate this logic elsewhere -- always call through here.
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return @import("../pass/analysis/ffi_language_classifier.zig").identifyLanguage(func);
}

/// Identify the language of a called function by name string.
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    return @import("../pass/analysis/ffi_language_classifier.zig").identifyCalleeLanguage(func_name);
}
