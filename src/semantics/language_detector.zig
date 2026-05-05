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
    /// LLVM personality function attribute analysis
    personality,
    /// LLVM global variable name prefix analysis
    globals,
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
/// R8.5 Enhanced: 3-round weighted voting:
///   Phase 1: detectFromSampling() (primary — function name patterns, weight 1.0x)
///   Phase 2: detectFromPersonality() (secondary — personality attrs, weight 0.8x)
///   Phase 3: detectFromGlobals() (tertiary — global var prefixes, weight 0.6x)
///   Final: Weighted sum across all phases, pick dominant language.
pub fn detectModuleLanguage(module: c.LLVMModuleRef) LanguageProfile {
    // Phase 1: Statistical sampling (existing, most reliable)
    const sampling_result = detectFromSampling(module);

    // Phase 2: Personality function analysis (new, orthogonal signal)
    const personality_result = detectFromPersonality(module);

    // Phase 3: Global variable prefix analysis (new, weak but useful tiebreaker)
    const globals_result = detectFromGlobals(module);

    // If only sampling produced a result, return it directly
    if (sampling_result != null and personality_result == null and globals_result == null) {
        return sampling_result.?;
    }

    // Weighted voting across all phases
    const SAMPLING_WEIGHT: f32 = 1.0;
    const PERSONALITY_WEIGHT: f32 = 0.8;
    const GLOBALS_WEIGHT: f32 = 0.6;

    var weighted_votes = [_]f32{ 0, 0, 0, 0, 0, 0, 0, 0 }; // [rust, go, zig, cpp, c, swift, java, unknown]

    if (sampling_result) |r| {
        const lang_idx = langToIndex(r.language);
        weighted_votes[lang_idx] += r.confidence * SAMPLING_WEIGHT;
    }

    if (personality_result) |r| {
        const lang_idx = langToIndex(r.language);
        weighted_votes[lang_idx] += r.confidence * PERSONALITY_WEIGHT;
    }

    if (globals_result) |r| {
        const lang_idx = langToIndex(r.language);
        weighted_votes[lang_idx] += r.confidence * GLOBALS_WEIGHT;
    }

    // Find dominant language from weighted votes
    var max_vote: f32 = 0;
    var dominant: Language = .unknown;
    var total_weight: f32 = 0;
    // Track which detection method contributed most to the winning language
    var winning_method: DetectionMethod = .sampling;
    for (weighted_votes, 0..) |vote, i| {
        total_weight += vote;
        if (vote > max_vote) {
            max_vote = vote;
            dominant = indexToLang(i);
            // Determine which method(s) voted for this language
            if (personality_result != null and personality_result.?.language == dominant) {
                winning_method = .personality;
            } else if (globals_result != null and globals_result.?.language == dominant) {
                winning_method = .globals;
            } else if (sampling_result != null and sampling_result.?.language == dominant) {
                winning_method = .sampling;
            }
        }
    }

    if (max_vote < 0.3 or total_weight < 0.3) {
        return .{
            .language = .unknown,
            .confidence = 0.0,
            .method = .unknown,
        };
    }

    const confidence = @min(max_vote / total_weight, 1.0);
    return .{
        .language = dominant,
        .confidence = confidence,
        .method = winning_method,
    };
}

fn langToIndex(lang: Language) usize {
    return switch (lang) {
        .rust => 0,
        .go => 1,
        .zig => 2,
        .cpp => 3,
        .c => 4,
        .swift => 5,
        .java => 6,
        .unknown => 7,
    };
}

fn indexToLang(idx: usize) Language {
    return switch (idx) {
        0 => .rust,
        1 => .go,
        2 => .zig,
        3 => .cpp,
        4 => .c,
        5 => .swift,
        6 => .java,
        else => .unknown,
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
    }) {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;

        const name = std.mem.span(name_ptr);

        if (std.mem.startsWith(u8, name, "llvm.")) continue;

        sampled += 1;

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
    var dominant: Language = .unknown;
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

/// R8.5-a: Detect language by scanning LLVM personality function attributes.
///
/// Each LLVM function may have a "personality" attribute that identifies
/// the exception handling runtime, which is strongly correlated with the
/// source language:
///   - @rust_eh_personality  → Rust (weight +3)
///   - __gxx_personality_v0  → C++ (weight +3)
///   - __gnat_eh_personality → Ada (rare, treat as cpp)
///   - _Unwind_Resume        → C (weight +1)
///   - _Unwind_RaiseException → C (weight +1)
///   - No personality         → no vote (skip)
fn detectFromPersonality(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_score: f32 = 0;
    const go_score: f32 = 0;
    const zig_score: f32 = 0;
    var cpp_score: f32 = 0;
    var c_score: f32 = 0;
    var total_votes: u32 = 0;

    const PERSONALITY_WEIGHT: f32 = 3.0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        // Check if function has a personality attribute
        // In LLVM-C API, we check for named metadata or function attributes
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);

        // Personality functions are typically named with known patterns.
        // We scan for them by checking function names directly since
        // LLVM-C doesn't expose a direct "getPersonality" API in older versions.

        if (std.mem.eql(u8, name, "@rust_eh_personality") or
            std.mem.indexOf(u8, name, "rust_eh_personality") != null)
        {
            rust_score += PERSONALITY_WEIGHT;
            total_votes += 1;
        } else if (std.mem.eql(u8, name, "__gxx_personality_v0") or
            std.mem.indexOf(u8, name, "__gxx_personality") != null)
        {
            cpp_score += PERSONALITY_WEIGHT;
            total_votes += 1;
        } else if (std.mem.eql(u8, name, "_Unwind_Resume") or
            std.mem.eql(u8, name, "_Unwind_RaiseException"))
        {
            c_score += 1.0; // Lower weight — C/C++ both use this
            total_votes += 1;
        }
    }

    if (total_votes == 0) return null;

    const scores = [_]struct { lang: Language, score: f32 }{
        .{ .lang = .rust, .score = rust_score },
        .{ .lang = .go, .score = go_score },
        .{ .lang = .zig, .score = zig_score },
        .{ .lang = .cpp, .score = cpp_score },
        .{ .lang = .c, .score = c_score },
    };

    var max_score: f32 = 0;
    var dominant: Language = .unknown;
    for (scores) |entry| {
        if (entry.score > max_score) {
            max_score = entry.score;
            dominant = entry.lang;
        }
    }

    if (max_score < 2.0) return null; // Need at least one strong signal

    const confidence = @min(max_score / (PERSONALITY_WEIGHT * @as(f32, @floatFromInt(total_votes))), 1.0);
    return .{
        .language = dominant,
        .confidence = confidence,
        .method = .personality,
    };
}

/// R8.5-b: Detect language by scanning LLVM global variable name prefixes.
///
/// Global variables often carry language-specific naming conventions:
///   - __rust_no_alloc_shim* → Rust (weight +2)
///   - __go_*                → Go (weight +2)
///   - zig.*                 → Zig (weight +2)
///   - __cxa_*               → C++ ABI (weight +2)
///   - __start/__stop        → C linker symbols (weight +1)
fn detectFromGlobals(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_score: f32 = 0;
    var go_score: f32 = 0;
    var zig_score: f32 = 0;
    var cpp_score: f32 = 0;
    var c_score: f32 = 0;
    var total_votes: u32 = 0;

    const GLOBAL_STRONG_WEIGHT: f32 = 2.0;
    const GLOBAL_WEAK_WEIGHT: f32 = 1.0;

    var global = c.LLVMGetFirstGlobal(module);
    while (@intFromPtr(global) != 0) : (global = c.LLVMGetNextGlobal(global)) {
        const name_ptr = c.LLVMGetValueName(global);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);

        // Rust global patterns
        if (std.mem.startsWith(u8, name, "__rust_")) {
            rust_score += GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Go runtime globals
        if (std.mem.startsWith(u8, name, "__go_")) {
            go_score += GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Zig globals
        if (std.mem.startsWith(u8, name, "zig.") or
            std.mem.startsWith(u8, name, "__zig_"))
        {
            zig_score += GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C++ ABI globals (__cxa_guard*, __cxa_atexit, etc.)
        if (std.mem.startsWith(u8, name, "__cxa_")) {
            cpp_score += GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C linker symbols
        if (std.mem.startsWith(u8, name, "__start_") or
            std.mem.startsWith(u8, name, "__stop_") or
            std.mem.startsWith(u8, name, "__end_"))
        {
            c_score += GLOBAL_WEAK_WEIGHT;
            total_votes += 1;
        }
    }

    if (total_votes == 0) return null;

    const scores = [_]struct { lang: Language, score: f32 }{
        .{ .lang = .rust, .score = rust_score },
        .{ .lang = .go, .score = go_score },
        .{ .lang = .zig, .score = zig_score },
        .{ .lang = .cpp, .score = cpp_score },
        .{ .lang = .c, .score = c_score },
    };

    var max_score: f32 = 0;
    var dominant: Language = .unknown;
    for (scores) |entry| {
        if (entry.score > max_score) {
            max_score = entry.score;
            dominant = entry.lang;
        }
    }

    if (max_score < 1.5) return null; // Need at least one strong signal

    const confidence = @min(max_score / (GLOBAL_STRONG_WEIGHT * @as(f32, @floatFromInt(total_votes))), 1.0);
    return .{
        .language = dominant,
        .confidence = confidence,
        .method = .globals,
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
