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
const ffi_language_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

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

    // One slot per concrete language. `.unknown` is the "no winner" fallback
    // and intentionally has no vote slot — letting it index in would write
    // past the array (see T0.2 in plan/todolist_v2.md).
    var weighted_votes = [_]f32{0} ** 8; // [rust, go, zig, cpp, c, csharp, java, python]

    if (sampling_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * SAMPLING_WEIGHT;
        }
    }

    if (personality_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * PERSONALITY_WEIGHT;
        }
    }

    if (globals_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * GLOBALS_WEIGHT;
        }
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

/// Map a concrete language to its weighted-vote slot, or null for `.unknown`.
///
/// `.unknown` is the "no signal" sentinel returned when no concrete language
/// wins — it deliberately has no vote slot, so callers must skip it instead
/// of indexing the array (T0.2: prior code wrote past the 8-slot bound).
fn langToIndex(lang: Language) ?usize {
    return switch (lang) {
        .rust => 0,
        .go => 1,
        .zig => 2,
        .cpp => 3,
        .c => 4,
        .csharp => 5,
        .java => 6,
        .python => 7,
        .unknown => null,
    };
}

fn indexToLang(idx: usize) Language {
    return switch (idx) {
        0 => .rust,
        1 => .go,
        2 => .zig,
        3 => .cpp,
        4 => .c,
        5 => .csharp,
        6 => .java,
        7 => .python,
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
/// Delegates to ffi_language_classifier.isRustMangledName for consistency.
fn detectFromSampling(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_count: u32 = 0;
    var go_count: u32 = 0;
    var zig_count: u32 = 0;
    var cpp_count: u32 = 0;
    var csharp_count: u32 = 0;
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

        // C# / .NET NativeAOT markers (unambiguous)
        // .NET NativeAOT produces distinctive symbol names:
        //   - <Module>.  prefix for module-level methods
        //   - System.*, Microsoft.* namespace prefixes
        //   - _N3System (Itanium-mangled .NET: N=namespace, 3=len("System"))
        //   - Rh* prefix = Runtime Helpers (RhThrowHresult, RhNewArray etc.)
        //   - GC_* = GC interaction stubs (GCPinAllocHandle, GCGlobalHandleFree2)
        //   - IL_* = IL code stubs
        if (std.mem.startsWith(u8, name, "<Module>.") or
            std.mem.startsWith(u8, name, "System.") or
            std.mem.startsWith(u8, name, "Microsoft.") or
            (name.len > 9 and std.mem.indexOf(u8, name[0..9], "_N3System") != null) or
            (name.len > 2 and name[0] == 'R' and name[1] == 'h') or
            std.mem.startsWith(u8, name, "GC_") or
            std.mem.startsWith(u8, name, "IL_") or
            std.mem.indexOf(u8, name, "__DotNet") != null or
            std.mem.indexOf(u8, name, "Marshal_") != null)
        {
            csharp_count += 1;
            continue;
        }

        // Go / TinyGo markers (from TINYGO_IR_SPEC.md)
        // TinyGo produces distinctive runtime.* and internal/task.* symbols.
        // Standard Go (gc) uses similar naming with more GC-related functions.
        // User code follows package.FunctionName convention (e.g., main.foo).
        if (std.mem.startsWith(u8, name, "runtime.") or
            std.mem.startsWith(u8, name, "internal/task.") or
            std.mem.startsWith(u8, name, "reflect/types."))
        {
            go_count += 1;
            continue;
        }
        // _Cgo_* prefix — CGo bridge functions (unambiguous)
        if (std.mem.indexOf(u8, name, "_Cgo_") != null) {
            go_count += 1;
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
        .{ .lang = .csharp, .count = csharp_count },
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

        if (std.mem.eql(u8, name, "rust_eh_personality") or
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

        // C++ RTTI / vtable globals (Itanium C++ ABI)
        // These are unambiguous strong signals — only present in C++ with RTTI enabled:
        //   _ZTV* = vtable (virtual function table pointer)
        //   _ZTI* = typeinfo (RTTI type information object)
        //   _ZTS* = typeinfo name (null-terminated mangled type name)
        // Weight: same as __cxa_ since they're equally definitive.
        if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'T') {
            const third_char = name[3];
            if (third_char == 'V' or third_char == 'I' or third_char == 'S') {
                cpp_score += GLOBAL_STRONG_WEIGHT;
                total_votes += 1;
                continue;
            }
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
    return @import("../pass/analysis/ffi/ffi_language_classifier.zig").identifyLanguage(func);
}

/// Identify the language of a called function by name string.
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    return @import("../pass/analysis/ffi/ffi_language_classifier.zig").identifyCalleeLanguage(func_name);
}

/// Multi-layer Rust mangled name detector for _ZN disambiguation.
/// Returns true if the symbol is a Rust-mangled name, false for C++ Itanium.
///
/// Detection layers (ordered by reliability):
///   1. '$' presence -- Rust uses $LT$, $GT$, $u20$, $RF$ etc.
///   2. Hash suffix <N>h<hex>E -- Rust incremental compilation hash
///   3. Known Rust namespace prefixes -- _ZN4core, _ZN3std, etc.
///
/// This function delegates to ffi_language_classifier.isRustMangledName
/// to ensure consistent detection across the codebase.
fn isRustMangledName(name: []const u8) bool {
    return ffi_language_classifier.isRustMangledName(name);
}

// Boundary: every `Language` variant must map to a slot that is either
// in-bounds for `weighted_votes` or explicitly null (`.unknown`). A regression
// would silently corrupt the next stack slot in `detectModuleLanguage`.
test "langToIndex covers all Language enum variants without OOB" {
    const expected_slots: usize = 8;

    inline for (@typeInfo(Language).@"enum".fields) |field| {
        const lang: Language = @field(Language, field.name);
        if (langToIndex(lang)) |idx| {
            try std.testing.expect(idx < expected_slots);
            // Round-trip: index must map back to the same language.
            try std.testing.expectEqual(lang, indexToLang(idx));
        } else {
            // Only `.unknown` is allowed to have no vote slot.
            try std.testing.expectEqual(Language.unknown, lang);
        }
    }
}

// indexToLang must return .unknown for any index >= 8 instead of panicking.
test "indexToLang returns .unknown for out-of-range indices" {
    try std.testing.expectEqual(Language.unknown, indexToLang(8));
    try std.testing.expectEqual(Language.unknown, indexToLang(100));
}

/// Classify a single global variable name to its likely language.
///
/// This is a test helper that exposes the prefix-matching logic from
/// detectFromGlobals() for unit-testing individual symbol names without
/// needing a full LLVM module.
fn classifyGlobalName(name: []const u8) ?Language {
    // C++ RTTI / vtable globals (Itanium C++ ABI)
    if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'T') {
        const third_char = name[3];
        if (third_char == 'V' or third_char == 'I' or third_char == 'S') {
            return .cpp;
        }
    }

    // C++ ABI globals (__cxa_guard*, __cxa_atexit, etc.)
    if (std.mem.startsWith(u8, name, "__cxa_")) {
        return .cpp;
    }

    // Rust global patterns
    if (std.mem.startsWith(u8, name, "__rust_")) {
        return .rust;
    }

    // Go runtime globals
    if (std.mem.startsWith(u8, name, "__go_")) {
        return .go;
    }

    // Zig globals
    if (std.mem.startsWith(u8, name, "zig.") or
        std.mem.startsWith(u8, name, "__zig_"))
    {
        return .zig;
    }

    // C linker symbols
    if (std.mem.startsWith(u8, name, "__start_") or
        std.mem.startsWith(u8, name, "__stop_") or
        std.mem.startsWith(u8, name, "__end_"))
    {
        return .c;
    }

    return null;
}

test "C++ vtable/RTTI globals are classified as cpp" {
    // _ZTV = vtable (virtual function table)
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTV4Base"));
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTVN3foo6BarE"));

    // _ZTI = typeinfo (RTTI type information)
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTI4Base"));
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTIN3foo6BarE"));

    // _ZTS = typeinfo name (mangled type name string)
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTS4Base"));
    try std.testing.expectEqual(Language.cpp, classifyGlobalName("_ZTSN3foo6BarE"));

    // Edge case: _ZTx where x is not V/I/S should NOT match
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("_ZTX4Base"));
}

test "Pure C globals are not misclassified as C++" {
    // C linker symbols should be classified as C, not C++
    try std.testing.expectEqual(Language.c, classifyGlobalName("__start_mysection"));
    try std.testing.expectEqual(Language.c, classifyGlobalName("__stop_mysection"));
    try std.testing.expectEqual(Language.c, classifyGlobalName("__end_mysection"));

    // Common C library symbols should not match C++ patterns
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("printf"));
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("malloc"));
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("global_var"));

    // _Z prefix without _ZT should not trigger RTTI detection
    // (e.g., plain mangled function names in globals is unusual but possible)
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("_Z4funcv"));
}

test "C++ with RTTI produces strong cpp signal" {
    // Simulate a C++ module with multiple RTTI symbols
    // In real usage, detectFromGlobals would see all of these and
    // accumulate a high cpp_score
    const rtti_symbols = [_][]const u8{
        "_ZTV4Base", // vtable for Base
        "_ZTVN3foo6BarE", // vtable for foo::Bar
        "_ZTI4Base", // typeinfo for Base
        "_ZTIN3foo6BarE", // typeinfo for foo::Bar
        "_ZTS4Base", // typeinfo name for Base
        "_ZTIN3foo6BarE", // typeinfo name for foo::Bar
    };

    var cpp_count: u32 = 0;
    for (rtti_symbols) |sym| {
        if (classifyGlobalName(sym)) |lang| {
            if (lang == .cpp) cpp_count += 1;
        }
    }

    // All RTTI symbols should be classified as C++
    try std.testing.expectEqual(@as(u32, 6), cpp_count);
}
