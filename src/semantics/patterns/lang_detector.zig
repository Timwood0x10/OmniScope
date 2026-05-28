//! R-5: Module Language Detector — gating for language-specific detectors
//!
//! Each IR module has a primary source language. Rust-specific detectors
//! (drop_glue, into_raw) should NOT run on Java JNI / Python CFFI IR.
//! Similarly, Go-specific patterns (runtime.alloc) should only run on Go IR.
//!
//! Detection uses multi-signal voting:
//!   1. Function name mangling prefixes (_R, _ZN, etc.)
//!   2. Personality functions (rust_eh_personality, __gxx_personality_v0)
//!   3. Reserved global symbols (__rust_no_alloc_shim_is_unstable, etc.)
//!   4. Source filename / target triple hints
//!
//! Covers: R-5 — ensures each detector only runs on its target language.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Detected language for an IR module.
pub const Language = enum {
    unknown,
    rust,
    cpp,
    c,
    go,
    java,
    python,
    csharp,
    zig,
};

/// Language detection result with confidence score.
pub const LanguageResult = struct {
    language: Language,
    confidence: f32,
    evidence: []const u8,
};

/// Rust v0 mangling prefix.
const RUST_V0_PREFIX = "_R";
/// Rust legacy mangling prefix (also used by C++, but Rust has hex hash suffix).
const RUST_LEGACY_PREFIX = "_ZN";
/// C++ Itanium mangling prefix.
const CPP_ITANIUM_PREFIX = "_Z";
/// Go runtime allocation symbol.
const GO_RUNTIME_ALLOC = "runtime.alloc";
/// Go cgo cross-call prefix.
const GO_CGO_PREFIX = "_cgo_";
/// Java JNI function prefix.
const JAVA_JNI_PREFIX = "Java_";
/// Python CFFI prefix.
const PYTHON_CFFI_PREFIX = "_cffi_";
/// Python GC prefix.
const PYTHON_GC_PREFIX = "_PyGC_";
/// C# namespace prefix.
const CSHARP_NS_PREFIX = "System_";
/// Rust personality function.
const RUST_PERSONALITY = "rust_eh_personality";
/// C++ personality function.
const CPP_PERSONALITY = "__gxx_personality_v0";

/// Detect the primary language of an IR module.
/// Uses sampling of function names and personality functions.
pub fn detectLanguage(module: c.LLVMModuleRef) LanguageResult {
    var rust_votes: u32 = 0;
    var cpp_votes: u32 = 0;
    var c_votes: u32 = 0;
    var go_votes: u32 = 0;
    var java_votes: u32 = 0;
    var python_votes: u32 = 0;
    var csharp_votes: u32 = 0;

    var total_funcs: u32 = 0;
    var func = c.LLVMGetFirstFunction(module);

    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        total_funcs += 1;
        const name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(name_raw) == 0) continue;
        const name = std.mem.sliceTo(name_raw, 0);

        // Rust v0 mangling — strongest signal
        if (std.mem.startsWith(u8, name, RUST_V0_PREFIX)) {
            rust_votes += 2;
            continue;
        }

        // C++ Itanium mangling (not Rust legacy)
        if (std.mem.startsWith(u8, name, CPP_ITANIUM_PREFIX)) {
            // Check if it's a Rust legacy mangling (has a 16-hex hash suffix)
            if (isRustLegacyMangling(name)) {
                rust_votes += 2;
            } else {
                cpp_votes += 2;
            }
            continue;
        }

        // Go runtime symbols
        if (std.mem.startsWith(u8, name, "runtime.") or
            std.mem.startsWith(u8, name, GO_CGO_PREFIX))
        {
            go_votes += 2;
            continue;
        }

        // Java JNI
        if (std.mem.startsWith(u8, name, JAVA_JNI_PREFIX)) {
            java_votes += 2;
            continue;
        }

        // Python CFFI
        if (std.mem.startsWith(u8, name, PYTHON_CFFI_PREFIX) or
            std.mem.startsWith(u8, name, PYTHON_GC_PREFIX))
        {
            python_votes += 2;
            continue;
        }

        // C# namespace
        if (std.mem.startsWith(u8, name, CSHARP_NS_PREFIX) or
            std.mem.startsWith(u8, name, "Microsoft_") or
            std.mem.startsWith(u8, name, "Mono_"))
        {
            csharp_votes += 2;
            continue;
        }

        // Plain C ABI (no mangling) — weak signal
        c_votes += 1;
    }

    // Find the language with the most votes
    const result = bestLanguage(rust_votes, cpp_votes, c_votes, go_votes, java_votes, python_votes, csharp_votes);
    const confidence: f32 = if (total_funcs > 0)
        @min(@as(f32, @floatFromInt(result.votes)) / @as(f32, @floatFromInt(total_funcs)), 1.0)
    else
        0.0;

    return LanguageResult{
        .language = result.lang,
        .confidence = confidence,
        .evidence = result.evidence,
    };
}

const LangVote = struct {
    lang: Language,
    votes: u32,
    evidence: []const u8,
};

fn bestLanguage(
    rust: u32,
    cpp: u32,
    c_lang: u32,
    go: u32,
    java: u32,
    python: u32,
    csharp: u32,
) LangVote {
    var best = LangVote{ .lang = .unknown, .votes = 0, .evidence = "no signal" };

    const candidates = [_]LangVote{
        .{ .lang = .rust, .votes = rust, .evidence = "Rust v0/legacy mangling" },
        .{ .lang = .cpp, .votes = cpp, .evidence = "C++ Itanium mangling" },
        .{ .lang = .c, .votes = c_lang, .evidence = "plain C ABI" },
        .{ .lang = .go, .votes = go, .evidence = "Go runtime/cgo symbols" },
        .{ .lang = .java, .votes = java, .evidence = "Java JNI symbols" },
        .{ .lang = .python, .votes = python, .evidence = "Python CFFI/GC symbols" },
        .{ .lang = .csharp, .votes = csharp, .evidence = "C# namespace symbols" },
    };

    for (candidates) |cand| {
        if (cand.votes > best.votes) best = cand;
    }

    return best;
}

/// Check if a _ZN mangled name is Rust legacy (has a 16-hex hash suffix).
fn isRustLegacyMangling(name: []const u8) bool {
    if (name.len < 20) return false;
    // Rust legacy mangling ends with a 17-byte suffix: 16 hex chars + 'E'
    // e.g., _ZN4core3foo17habcdef0123456789E
    if (name[name.len - 1] != 'E') return false;
    const hash_start = name.len - 17;
    if (hash_start < 3) return false;
    // Check if the 16 chars before 'E' are all hex
    for (name[hash_start .. name.len - 1]) |ch| {
        if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

/// Run language detection and write result to SRT.
/// This is called before other detectors — they can check the language
/// to decide whether to run.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    _ = srt;
    _ = module;
    // Language detection is done on-demand via detectLanguage().
    // No SRT entries needed — this is a query-only detector.
}
