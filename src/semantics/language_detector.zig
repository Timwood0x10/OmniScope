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
const data = @import("language_detector_data.zig");

/// How the language was detected
pub const DetectionMethod = enum {
    sampling,
    personality,
    globals,
    metadata,
    unknown,
};

/// Module-level language detection result
pub const LanguageProfile = struct {
    language: Language,
    confidence: f32,
    method: DetectionMethod,
};

/// Maximum number of CU entries to scan during metadata-based detection.
/// Scanning all CUs in LTO modules is unnecessary — the first few usually suffice.
const METADATA_MAX_CU: u32 = 8;

/// Detect language from LLVM debug metadata (llvm.dbg.cu).
///
/// Safe DI API approach — avoids LLVMGetMDNodeOperands (which uses
/// cast<MDNode> internally and crashes on MetadataAsValue wrappers
/// returned by LLVMGetNamedMetadataOperands).
///
/// Strategy 1: Read producer string from DICompileUnit operands.
///   Uses LLVMGetMDNodeNumOperands (safe: uses dyn_cast_or_null internally)
///   to guard the call to LLVMGetMDNodeOperands. If num_ops is 0 (expected
///   for MetadataAsValue wrappers), we skip — no crash.
///
/// LLVMGetMDNodeNumOperands: returns 1 for non-MDNode metadata wrappers
/// (e.g., MetadataAsValue), or the actual operand count for MDNode nodes.
/// The `> 2` lower bound below safely excludes both 1 (non-MDNode guard)
/// and 2 (insufficient operands for minimum CU format).
fn detectFromMetadata(module: c.LLVMModuleRef, allocator: std.mem.Allocator) ?LanguageProfile {
    const cu_count = c.LLVMGetNamedMetadataNumOperands(module, "llvm.dbg.cu");

    // ── llvm.dbg.cu metadata analysis ──────────────────────────
    if (cu_count > 0) {
        // Heap-allocate CU operands buffer (some modules can have many CUs)
        const cu_buf = allocator.alloc(c.LLVMValueRef, cu_count) catch {
            return null;
        };
        defer allocator.free(cu_buf);
        c.LLVMGetNamedMetadataOperands(module, "llvm.dbg.cu", cu_buf.ptr);

        const scan_count = @min(cu_count, METADATA_MAX_CU);
        for (cu_buf[0..scan_count]) |cu_val| {
            if (cu_val == null) continue;

            // ── Convert to metadata ref and verify kind ──────────────
            const cu_md = c.LLVMValueAsMetadata(cu_val);
            if (cu_md == null) continue;
            // Verify this is actually a DICompileUnit before making DI calls
            if (c.LLVMGetMetadataKind(cu_md) != c.LLVMDICompileUnitMetadataKind) continue;

            // ═══════════════════════════════════════════════════════════
            // Strategy 1: Producer string from DICompileUnit operands
            // ═══════════════════════════════════════════════════════════
            //
            // LLVMGetMDNodeNumOperands: returns 1 for non-MDNode metadata wrappers
            // (e.g., MetadataAsValue), or the actual operand count for MDNode nodes.
            // The `> 2` lower bound below safely excludes both 1 (non-MDNode guard)
            // and 2 (insufficient operands for minimum CU format).
            const num_ops = c.LLVMGetMDNodeNumOperands(cu_val);
            if (num_ops > 2 and num_ops < 100) {
                // DICompileUnit operands can be numerous; allocate dynamically
                // to avoid stack overflow (ref: CODE_REVIEW).
                // SAFETY: num_ops > 2 confirms this is a viable MDNode, so
                // LLVMGetMDNodeOperands (which uses cast<MDNode>) should be safe.
                const ops_buf = allocator.alloc(c.LLVMValueRef, num_ops) catch {
                    return null;
                };
                defer allocator.free(ops_buf);
                c.LLVMGetMDNodeOperands(cu_val, ops_buf.ptr);

                // Check producer at index 2 — DICompileUnit layout:
                // [source_lang, file, producer, isOptimized, flags, ...]
                if (ops_buf.len > 2) {
                    const producer_val = ops_buf[2];
                    // LLVMIsAMDString returns non-null if the value IS an MDString
                    if (producer_val != null and c.LLVMIsAMDString(producer_val) != null) {
                        var producer_len: c_uint = 0;
                        const producer_ptr = c.LLVMGetMDString(producer_val, &producer_len);
                        if (producer_ptr != null and producer_len > 0) {
                            const producer = producer_ptr[0..producer_len];
                            if (std.mem.startsWith(u8, producer, "rustc version")) {
                                return LanguageProfile{ .language = .rust, .confidence = 0.95, .method = .metadata };
                            }
                            if (std.mem.startsWith(u8, producer, "zig ")) {
                                return LanguageProfile{ .language = .zig, .confidence = 0.95, .method = .metadata };
                            }
                            if (std.mem.startsWith(u8, producer, "Go cmd/compile")) {
                                return LanguageProfile{ .language = .go, .confidence = 0.95, .method = .metadata };
                            }
                            if (std.mem.startsWith(u8, producer, "clang")) {
                                // Clang-produced code could be C or C++; defer to other strategies
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════
            // Strategy 2: CU-level file extension via safe DI APIs
            // ═══════════════════════════════════════════════════════════
            const file_md = c.LLVMDIScopeGetFile(cu_md);
            if (file_md != null) {
                var file_len: c_uint = 0;
                const file_ptr = c.LLVMDIFileGetFilename(file_md, &file_len);
                if (file_ptr != null and file_len > 0) {
                    const filename = file_ptr[0..file_len];
                    if (std.mem.endsWith(u8, filename, ".zig")) {
                        return LanguageProfile{ .language = .zig, .confidence = 0.85, .method = .metadata };
                    }
                    if (std.mem.endsWith(u8, filename, ".rs")) {
                        return LanguageProfile{ .language = .rust, .confidence = 0.85, .method = .metadata };
                    }
                    if (std.mem.endsWith(u8, filename, ".go")) {
                        return LanguageProfile{ .language = .go, .confidence = 0.85, .method = .metadata };
                    }
                    if (std.mem.endsWith(u8, filename, ".c")) {
                        return LanguageProfile{ .language = .c, .confidence = 0.85, .method = .metadata };
                    }
                    if (std.mem.endsWith(u8, filename, ".cpp") or
                        std.mem.endsWith(u8, filename, ".cc") or
                        std.mem.endsWith(u8, filename, ".cxx") or
                        std.mem.endsWith(u8, filename, ".hpp") or
                        std.mem.endsWith(u8, filename, ".h"))
                    {
                        return LanguageProfile{ .language = .cpp, .confidence = 0.85, .method = .metadata };
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Strategy 3: Subprogram-level file extension analysis
    // ═══════════════════════════════════════════════════════════════════
    // Iterate through functions, read each subprogram's DIFile, and tally
    // file extensions. This catches cases where the CU file is generic
    // (e.g., "main") but individual functions reference .zig/.rs/.go files.
    {
        const sample_limit = 100;
        var counts = std.EnumMap(Language, u32){};
        var total_sampled: u32 = 0;

        var func = c.LLVMGetFirstFunction(module);
        while (func != null and total_sampled < sample_limit) : ({
            func = c.LLVMGetNextFunction(func);
        }) {
            const subprogram = c.LLVMGetSubprogram(func);
            if (subprogram == null) continue;

            const file_md = c.LLVMDIScopeGetFile(subprogram);
            if (file_md == null) continue;

            var file_len: c_uint = 0;
            const file_ptr = c.LLVMDIFileGetFilename(file_md, &file_len);
            if (file_ptr == null or file_len == 0) continue;

            const filename = file_ptr[0..file_len];
            const detected = if (std.mem.endsWith(u8, filename, ".zig"))
                Language.zig
            else if (std.mem.endsWith(u8, filename, ".rs"))
                Language.rust
            else if (std.mem.endsWith(u8, filename, ".go"))
                Language.go
            else if (std.mem.endsWith(u8, filename, ".c"))
                Language.c
            else if (std.mem.endsWith(u8, filename, ".cpp") or
                std.mem.endsWith(u8, filename, ".cc") or
                std.mem.endsWith(u8, filename, ".cxx") or
                std.mem.endsWith(u8, filename, ".hpp") or
                std.mem.endsWith(u8, filename, ".h"))
                Language.cpp
            else
                continue;

            counts.put(detected, (counts.get(detected) orelse 0) + 1);
            total_sampled += 1;
        }

        if (total_sampled > 0) {
            // Find the dominant language with at least 60% share
            var dominant: Language = .unknown;
            var max_count: u32 = 0;
            var iter = counts.iterator();
            while (iter.next()) |entry| {
                if (entry.value.* > max_count) {
                    max_count = entry.value.*;
                    dominant = entry.key;
                }
            }

            const share = @as(f32, @floatFromInt(max_count)) / @as(f32, @floatFromInt(total_sampled));
            if (share >= 0.6) {
                return LanguageProfile{ .language = dominant, .confidence = share * 0.95, .method = .metadata };
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Strategy 4: Module-level !llvm.ident metadata analysis
    // ═══════════════════════════════════════════════════════════════════
    // Check for compiler identification strings in llvm.ident metadata.
    // This catches modules compiled without debug info (e.g., rustc -C
    // debuginfo=0) which lack llvm.dbg.cu entries entirely.
    //
    // Structure: !llvm.ident = !{!1} / !1 = !{!"rustc version 1.95.0 ..."}
    // Named metadata operands are MetadataAsValue wrappers. We use the same
    // safe access pattern as Strategy 1 (LLVMGetMDNodeNumOperands guard).
    {
        const ident_count = c.LLVMGetNamedMetadataNumOperands(module, "llvm.ident");
        if (ident_count > 0) {
            const ident_buf = allocator.alloc(c.LLVMValueRef, ident_count) catch {
                return null;
            };
            defer allocator.free(ident_buf);
            c.LLVMGetNamedMetadataOperands(module, "llvm.ident", ident_buf.ptr);

            for (ident_buf[0..ident_count]) |ident_val| {
                if (ident_val == null) continue;

                // Safety guard: only proceed if this is a real MDNode
                const num_ops = c.LLVMGetMDNodeNumOperands(ident_val);
                if (num_ops == 0 or num_ops > 20) continue;

                const ops_buf = allocator.alloc(c.LLVMValueRef, num_ops) catch {
                    return null;
                };
                defer allocator.free(ops_buf);
                c.LLVMGetMDNodeOperands(ident_val, ops_buf.ptr);

                for (ops_buf[0..num_ops]) |op_val| {
                    if (op_val == null) continue;
                    if (c.LLVMIsAMDString(op_val) == null) continue;

                    var str_len: c_uint = 0;
                    const str_ptr = c.LLVMGetMDString(op_val, &str_len);
                    if (str_ptr == null or str_len == 0) continue;

                    const ident_str = str_ptr[0..str_len];
                    if (std.mem.startsWith(u8, ident_str, "rustc version")) {
                        return LanguageProfile{ .language = .rust, .confidence = 0.90, .method = .metadata };
                    }
                    if (std.mem.startsWith(u8, ident_str, "zig ")) {
                        return LanguageProfile{ .language = .zig, .confidence = 0.90, .method = .metadata };
                    }
                    if (std.mem.startsWith(u8, ident_str, "Go cmd/compile")) {
                        return LanguageProfile{ .language = .go, .confidence = 0.90, .method = .metadata };
                    }
                    // clang in llvm.ident doesn't distinguish C vs C++
                }
            }
        }
    }

    return null;
}

/// Detect the source language of an entire LLVM module.
///
/// Detection priority:
///   1. Metadata (llvm.dbg.cu) — highest confidence, returns immediately
///   2. Function-name sampling — statistical pattern matching
///   3. Personality function attributes
///   4. Global variable name patterns
pub fn detectModuleLanguage(module: c.LLVMModuleRef, allocator: std.mem.Allocator) LanguageProfile {
    // Priority 1: Metadata detection — highest confidence, safe DI API approach.
    // Only falls back to sampling/personality/globals if metadata is absent.
    if (detectFromMetadata(module, allocator)) |meta_result| {
        return meta_result;
    }

    // Fall back to existing sampling/personality/globals voting
    const sampling_result = detectFromSampling(module);
    const personality_result = detectFromPersonality(module);
    const globals_result = detectFromGlobals(module);

    if (sampling_result != null and personality_result == null and globals_result == null) {
        return sampling_result.?;
    }

    var weighted_votes = [_]f32{0} ** data.LANGUAGE_COUNT;

    if (sampling_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * data.SAMPLING_WEIGHT;
        }
    }
    if (personality_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * data.PERSONALITY_WEIGHT;
        }
    }
    if (globals_result) |r| {
        if (langToIndex(r.language)) |idx| {
            weighted_votes[idx] += r.confidence * data.GLOBALS_WEIGHT;
        }
    }

    var max_vote: f32 = 0;
    var dominant: Language = .unknown;
    var total_weight: f32 = 0;
    var winning_method: DetectionMethod = .sampling;
    for (weighted_votes, 0..) |vote, i| {
        total_weight += vote;
        if (vote > max_vote) {
            max_vote = vote;
            dominant = indexToLang(i);
            if (personality_result != null and personality_result.?.language == dominant) {
                winning_method = .personality;
            } else if (globals_result != null and globals_result.?.language == dominant) {
                winning_method = .globals;
            } else if (sampling_result != null and sampling_result.?.language == dominant) {
                winning_method = .sampling;
            }
        }
    }

    if (max_vote < data.MIN_VOTE_THRESHOLD or total_weight < data.MIN_VOTE_THRESHOLD) {
        return .{ .language = .unknown, .confidence = 0.0, .method = .unknown };
    }

    const confidence = @min(max_vote / total_weight, 1.0);
    return .{ .language = dominant, .confidence = confidence, .method = winning_method };
}

pub fn langToIndex(lang: Language) ?usize {
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

pub fn indexToLang(idx: usize) Language {
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
fn detectFromSampling(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_count: u32 = 0;
    var go_count: u32 = 0;
    var zig_count: u32 = 0;
    var cpp_count: u32 = 0;
    var csharp_count: u32 = 0;
    var python_count: u32 = 0;
    var c_count: u32 = 0;
    var total: u32 = 0;

    var func = c.LLVMGetFirstFunction(module);
    var sampled: usize = 0;

    while (@intFromPtr(func) != 0 and sampled < data.SAMPLE_SIZE) : ({
        func = c.LLVMGetNextFunction(func);
    }) {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);
        if (std.mem.startsWith(u8, name, "llvm.")) continue;

        sampled += 1;
        total += 1;

        // Rust: _rust_ and rs2py_ markers
        if (data.hasAnySubstring(name, data.rust_strong_prefixes)) {
            rust_count += 1;
            continue;
        }

        // Rust v0 mangling prefix (RFC 2603) — _R<hash><crate>...
        // This MUST be checked before _ZN and _Z since _R is an unambiguous Rust prefix.
        if (name.len > 2 and name[0] == '_' and name[1] == 'R') {
            rust_count += 1;
            continue;
        }

        // Go strong prefixes (main., runtime., syscall., gcops.)
        if (data.hasAnyPrefix(name, data.go_strong_prefixes)) {
            go_count += 1;
            continue;
        }

        // Zig markers (zig_, Allocator.)
        if (data.hasAnySubstring(name, data.zig_markers)) {
            zig_count += 1;
            continue;
        }

        // Python C extension module init function (unambiguous)
        if (std.mem.startsWith(u8, name, "PyInit_")) {
            python_count += 1;
            continue;
        }

        // C# / .NET strong markers
        if (data.hasAnyPrefix(name, data.csharp_prefixes) or
            data.hasAnySubstring(name, data.csharp_substrings) or
            data.hasAnyPrefixLimited(name, data.csharp_prefix_limited))
        {
            csharp_count += 1;
            continue;
        }

        // C# / .NET qualified name with '.' pattern
        if (data.hasDotNetQualifiedName(name)) {
            csharp_count += 1;
            continue;
        }

        // Go / TinyGo markers
        if (data.hasAnyPrefix(name, data.go_tinygo_prefixes)) {
            go_count += 1;
            continue;
        }

        // Go runtime internal symbols (fine-grained classification)
        if (data.isGoRuntimeInternal(name)) {
            go_count += 1;
            continue;
        }

        // Reflect package symbols (medium Go signal)
        if (std.mem.startsWith(u8, name, "reflect.")) {
            go_count += 1;
            continue;
        }

        // _Cgo_* prefix — CGo bridge functions (unambiguous)
        if (data.hasAnySubstring(name, data.go_cgo_markers)) {
            go_count += 1;
            continue;
        }

        // _ZN (Itanium nested name mangling) — used by BOTH Rust and C++.
        if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
            if (ffi_language_classifier.isRustMangledName(name)) {
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
        .{ .lang = .python, .count = python_count },
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
    if (confidence < data.MIN_SAMPLING_CONFIDENCE) {
        return .{ .language = .unknown, .confidence = 0.3, .method = .sampling };
    }
    return .{ .language = dominant, .confidence = confidence, .method = .sampling };
}

/// Detect language by scanning LLVM personality function attributes.
fn detectFromPersonality(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_score: f32 = 0;
    const go_score: f32 = 0;
    const zig_score: f32 = 0;
    var cpp_score: f32 = 0;
    var csharp_score: f32 = 0;
    const python_score: f32 = 0;
    var c_score: f32 = 0;
    var total_votes: u32 = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);

        if (data.matchPersonality(name)) |lang| {
            switch (lang) {
                .rust => rust_score += data.PERSONALITY_STRONG,
                .cpp => cpp_score += data.PERSONALITY_STRONG,
                .csharp => csharp_score += data.PERSONALITY_STRONG,
            }
            total_votes += 1;
        } else if (data.isCUnwindPersonality(name)) {
            c_score += 1.0;
            total_votes += 1;
        }
    }

    if (total_votes == 0) return null;

    const scores = [_]struct { lang: Language, score: f32 }{
        .{ .lang = .rust, .score = rust_score },
        .{ .lang = .go, .score = go_score },
        .{ .lang = .zig, .score = zig_score },
        .{ .lang = .cpp, .score = cpp_score },
        .{ .lang = .csharp, .score = csharp_score },
        .{ .lang = .python, .score = python_score },
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

    if (max_score < data.MIN_PERSONALITY_SCORE) return null;

    const confidence = @min(max_score / (data.PERSONALITY_STRONG * @as(f32, @floatFromInt(total_votes))), 1.0);
    return .{ .language = dominant, .confidence = confidence, .method = .personality };
}

/// Detect language by scanning LLVM global variable name prefixes.
fn detectFromGlobals(module: c.LLVMModuleRef) ?LanguageProfile {
    var rust_score: f32 = 0;
    var go_score: f32 = 0;
    var zig_score: f32 = 0;
    var cpp_score: f32 = 0;
    var csharp_score: f32 = 0;
    var python_score: f32 = 0;
    var c_score: f32 = 0;
    var total_votes: u32 = 0;

    var global = c.LLVMGetFirstGlobal(module);
    while (@intFromPtr(global) != 0) : (global = c.LLVMGetNextGlobal(global)) {
        const name_ptr = c.LLVMGetValueName(global);
        if (@intFromPtr(name_ptr) == 0) continue;
        const name = std.mem.span(name_ptr);

        // C# / .NET global symbols
        if (data.hasAnyPrefix(name, data.csharp_global_prefixes)) {
            csharp_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C# weak markers
        if (data.hasAnySubstring(name, data.csharp_global_substrings)) {
            csharp_score += data.GLOBAL_WEAK_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Rust global patterns
        if (data.hasAnyPrefix(name, data.rust_global_prefixes)) {
            rust_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Go runtime globals
        if (data.hasAnyPrefix(name, data.go_global_prefixes)) {
            go_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Zig globals
        if (data.hasAnyPrefix(name, data.zig_global_prefixes)) {
            zig_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C++ ABI globals (__cxa_*)
        if (data.hasAnyPrefix(name, data.cpp_global_prefixes)) {
            cpp_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C++ RTTI / vtable globals (_ZTV, _ZTI, _ZTS)
        if (data.isCppRttiGlobal(name)) {
            cpp_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // Python GC internal runtime symbols
        if (data.hasAnyPrefix(name, data.python_global_prefixes)) {
            python_score += data.GLOBAL_STRONG_WEIGHT;
            total_votes += 1;
            continue;
        }

        // C linker symbols
        if (data.hasAnyPrefix(name, data.c_global_prefixes)) {
            c_score += data.GLOBAL_WEAK_WEIGHT;
            total_votes += 1;
        }
    }

    if (total_votes == 0) return null;

    const scores = [_]struct { lang: Language, score: f32 }{
        .{ .lang = .rust, .score = rust_score },
        .{ .lang = .go, .score = go_score },
        .{ .lang = .zig, .score = zig_score },
        .{ .lang = .cpp, .score = cpp_score },
        .{ .lang = .csharp, .score = csharp_score },
        .{ .lang = .python, .score = python_score },
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

    if (max_score < data.MIN_GLOBALS_SCORE) return null;

    const confidence = @min(max_score / (data.GLOBAL_STRONG_WEIGHT * @as(f32, @floatFromInt(total_votes))), 1.0);
    return .{ .language = dominant, .confidence = confidence, .method = .globals };
}

/// Identify the language of an LLVM function value.
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return @import("../pass/analysis/ffi/ffi_language_classifier.zig").identifyLanguage(func);
}

/// Identify the language of a called function by name string.
pub fn identifyCalleeLanguage(func_name: []const u8) Language {
    return @import("../pass/analysis/ffi/ffi_language_classifier.zig").identifyCalleeLanguage(func_name);
}
