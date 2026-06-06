//! Zone Classification for Multi-Language Unsafe Boundary Analysis
//!
//! Core principle: Analyze only where language guarantees stop.
//!
//! This is the main entry point for zone classification. Language-specific
//! classifiers are delegated to submodules:
//!   - zone_lang_rust.zig  → Rust classification
//!   - zone_lang_zig.zig   → Zig classification
//!   - zone_lang_go.zig    → Go classification
//!   - zone_lang_cpp.zig   → C/C++ classification
//!   - zone_llvm_path.zig  → LLVM debug path classification

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const FFIBoundary = @import("../diag/issue.zig").FFIBoundary;
pub const Language = FFIBoundary.Language;

const zone_types = @import("../types/zone_types.zig");
pub const ZoneKind = zone_types.ZoneKind;
pub const EscapeTrigger = zone_types.EscapeTrigger;
pub const ZoneStats = zone_types.ZoneStats;
pub const RUST_SAFE_PATTERNS = zone_types.RUST_SAFE_PATTERNS;
pub const RUST_ESCAPE_PATTERNS = zone_types.RUST_ESCAPE_PATTERNS;
pub const ZIG_SAFE_PATTERNS = zone_types.ZIG_SAFE_PATTERNS;
pub const ZIG_ESCAPE_PATTERNS = zone_types.ZIG_ESCAPE_PATTERNS;
pub const GO_SAFE_PATTERNS = zone_types.GO_SAFE_PATTERNS;
pub const GO_ESCAPE_PATTERNS = zone_types.GO_ESCAPE_PATTERNS;
pub const CPP_SAFE_PATTERNS = zone_types.CPP_SAFE_PATTERNS;
pub const CPP_ESCAPE_PATTERNS = zone_types.CPP_ESCAPE_PATTERNS;
pub const C_ESCAPE_PATTERNS = zone_types.C_ESCAPE_PATTERNS;

const language_detector = @import("language_detector.zig");
pub const LanguageProfile = language_detector.LanguageProfile;
const lang_detectors = @import("zone_lang_detectors.zig");

// Re-export language detection functions for backward compatibility
pub const isRustFunction = lang_detectors.isRustFunction;
pub const isZigFunction = lang_detectors.isZigFunction;
pub const isGoFunction = lang_detectors.isGoFunction;
pub const isCppFunction = lang_detectors.isCppFunction;
pub const isCFunction = lang_detectors.isCFunction;
pub const classifyCFunction = lang_detectors.classifyCFunction;

// Import language-specific classifiers
const rust_classifier = @import("zone_lang_rust.zig");
const zig_classifier = @import("zone_lang_zig.zig");
const go_classifier = @import("zone_lang_go.zig");
const cpp_classifier = @import("zone_lang_cpp.zig");
const llvm_path = @import("zone_llvm_path.zig");

// Re-export classifier functions
pub const classifyRustFunction = rust_classifier.classifyRustFunction;
pub const classifyZigFunction = zig_classifier.classifyZigFunction;
pub const classifyGoFunction = go_classifier.classifyGoFunction;
pub const classifyCppFunction = cpp_classifier.classifyCppFunction;
pub const isGoRuntimeInternal = go_classifier.isGoRuntimeInternal;
pub const isCppStlInternal = cpp_classifier.isCppStlInternal;
pub const isCppOperatorNewDelete = cpp_classifier.isCppOperatorNewDelete;
pub const isLibcFunction = cpp_classifier.isLibcFunction;
pub const isLikelyRuntimeInternal = cpp_classifier.isLikelyRuntimeInternal;
pub const classifyBySubprogramPath = llvm_path.classifyBySubprogramPath;

const CacheSize = 1024;
threadlocal var classify_cache: ?std.AutoHashMap(usize, ZoneKind) = null;

/// Initialize the thread-local cache (call once per thread)
pub fn initCache(allocator: std.mem.Allocator) void {
    if (classify_cache == null) {
        classify_cache = std.AutoHashMap(usize, ZoneKind).init(allocator);
    }
}

/// Clear the thread-local cache
pub fn deinitCache() void {
    if (classify_cache) |*cache| {
        cache.deinit();
        classify_cache = null;
    }
}

fn isAlphaNumeric(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9');
}

/// Classify a function name into zone kind.
pub fn classifyFunction(func_name: []const u8, lang: ?Language) ZoneKind {
    if (func_name.len == 0) return .unknown;

    const name_ptr = @intFromPtr(func_name.ptr);
    if (classify_cache) |*cache| {
        if (cache.get(name_ptr)) |cached_result| {
            return cached_result;
        }
    }

    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .runtime_internal;
    }

    if (std.mem.endsWith(u8, func_name, "_chk")) {
        return .runtime_internal;
    }

    var result: ZoneKind = undefined;

    if (lang) |l| {
        result = switch (l) {
            .rust => classifyRustFunction(func_name),
            .zig => classifyZigFunction(func_name),
            .go => classifyGoFunction(func_name),
            .cpp, .c => classifyCppFunction(func_name),
            else => .unknown,
        };
    } else {
        if (std.mem.startsWith(u8, func_name, "__rust_") or
            std.mem.startsWith(u8, func_name, "__rdl_") or
            std.mem.startsWith(u8, func_name, "__rg_"))
        {
            result = .runtime_internal;
        } else if (isRustFunction(func_name)) {
            result = classifyRustFunction(func_name);
        } else if (isZigFunction(func_name)) {
            result = classifyZigFunction(func_name);
        } else if (isGoFunction(func_name)) {
            result = classifyGoFunction(func_name);
        } else if (isCppFunction(func_name)) {
            result = classifyCppFunction(func_name);
        } else if (isCFunction(func_name)) {
            result = classifyCFunction(func_name);
        } else {
            result = .unknown;
        }
    }

    if (classify_cache) |*cache| {
        if (cache.count() < CacheSize) {
            cache.put(name_ptr, result) catch {};
        }
    }

    return result;
}

/// Evidence-driven zone classification using module-level language detection.
pub fn classifyFunctionWithEvidence(
    func_name: []const u8,
    lang: ?Language,
    evidence: ?LanguageProfile,
) ZoneKind {
    if (func_name.len == 0) return .unknown;

    if (evidence) |profile| {
        return classifyWithEvidence(func_name, lang, profile);
    }

    return classifyFunction(func_name, lang);
}

/// Internal: Apply evidence-aware classification rules based on dominant language.
fn classifyWithEvidence(
    func_name: []const u8,
    lang: ?Language,
    profile: LanguageProfile,
) ZoneKind {
    const log = std.log.scoped(.zone_classifier);

    const dominant = profile.language;

    switch (dominant) {
        .rust => {
            log.debug("Rust module: applying Rust-aware rules for {s}", .{func_name});

            if (std.mem.startsWith(u8, func_name, "_ZN") or
                std.mem.startsWith(u8, func_name, "__rust_") or
                std.mem.startsWith(u8, func_name, "__rdl_") or
                std.mem.startsWith(u8, func_name, "__rg_"))
            {
                const rust_alloc_patterns = [_][]const u8{
                    "__rust_dealloc",      "__rust_alloc",  "__rust_realloc",
                    "__rust_alloc_zeroed", "__rdl_dealloc", "__rdl_alloc",
                    "__rdl_realloc",       "__rg_dealloc",  "__rg_alloc",
                    "__rg_realloc",
                };
                for (rust_alloc_patterns) |pat| {
                    if (std.mem.indexOf(u8, func_name, pat) != null) {
                        return .runtime_internal;
                    }
                }
                if (std.mem.startsWith(u8, func_name, "_ZN4core") or
                    std.mem.startsWith(u8, func_name, "_ZN5alloc") or
                    std.mem.startsWith(u8, func_name, "_ZN3std"))
                {
                    return .runtime_internal;
                }
            }

            if (std.mem.indexOf(u8, func_name, "extern") != null) {
                return .ffi;
            }

            return classifyRustFunction(func_name);
        },
        .cpp => {
            log.debug("C++ module: applying C++-aware rules for {s}", .{func_name});

            if (isCppStlInternal(func_name)) {
                return .safe;
            }

            if (isCppOperatorNewDelete(func_name)) {
                return .safe;
            }

            return classifyCppFunction(func_name);
        },
        .c => {
            log.debug("C module: applying C-aware rules for {s}", .{func_name});

            if (isLibcFunction(func_name)) {
                return .safe;
            }

            return classifyCFunction(func_name);
        },
        else => {
            log.debug("Unknown language ({}) fallback to heuristic", .{dominant});
            return classifyFunction(func_name, lang);
        },
    }
}

/// Classify a function using LLVM metadata (more precise than string matching).
pub fn classifyFunctionFromLLVM(
    func: c.LLVMValueRef,
    func_name: []const u8,
) ZoneKind {
    if (c.LLVMIsDeclaration(func) != 0) {
        const linkage = c.LLVMGetLinkage(func);

        if (linkage == c.LLVMExternalLinkage or
            linkage == c.LLVMExternalWeakLinkage or
            linkage == c.LLVMCommonLinkage)
        {
            if (isLikelyRuntimeInternal(func_name)) {
                return .runtime_internal;
            }
            const rust_alloc_patterns = [_][]const u8{
                "__rust_dealloc", "__rust_alloc", "__rust_realloc", "__rust_alloc_zeroed",
                "__rdl_dealloc",  "__rdl_alloc",  "__rdl_realloc",  "__rg_dealloc",
                "__rg_alloc",     "__rg_realloc",
            };
            for (rust_alloc_patterns) |pat| {
                if (std.mem.indexOf(u8, func_name, pat) != null) {
                    return .runtime_internal;
                }
            }
            return .ffi;
        }

        return .unknown;
    }

    const intrinsic_id = c.LLVMGetIntrinsicID(func);
    if (intrinsic_id != 0) {
        return .runtime_internal;
    }

    if (classifyBySubprogramPath(func)) |zone| {
        return zone;
    }

    if (std.mem.startsWith(u8, func_name, "llvm.")) {
        return .runtime_internal;
    }

    return classifyFunction(func_name, null);
}

test "ZoneStats" {
    var stats = ZoneStats{};
    stats.record(.safe);
    stats.record(.safe);
    stats.record(.unsafe);
    stats.record(.runtime_internal);

    try std.testing.expectEqual(@as(u32, 4), stats.total());
    try std.testing.expectEqual(@as(u32, 2), stats.safe_count);
    try std.testing.expectEqual(@as(f64, 0.75), stats.skipRatio());
}

test "isCFunction - positive detection" {
    try std.testing.expect(isCFunction("my_c_function"));
    try std.testing.expect(isCFunction("process_data"));
    try std.testing.expect(isCFunction("handle_request"));
    try std.testing.expect(isCFunction("init_server"));
    try std.testing.expect(isCFunction("cleanup_resources"));
}

test "isCFunction - negative detection (not C)" {
    try std.testing.expect(!isCFunction("_ZN4core3ptr"));
    try std.testing.expect(!isCFunction("std::vector"));
    try std.testing.expect(!isCFunction("runtime.main"));
    try std.testing.expect(!isCFunction("llvm.memcpy"));
    try std.testing.expect(!isCFunction("__gnu_cxx::"));
    try std.testing.expect(!isCFunction("_ZN3std"));
    try std.testing.expect(!isCFunction("my_func$u20$name"));
}

test "classifyCFunction - FFI patterns" {
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("FFI_01_dlopen_null_check"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("my_dlopen_wrapper"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("dlopen_handle"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("cleanup_init"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("destroy_resource"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("PyObject_Call"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("JNI_OnLoad"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("NewGlobalRef"));
}

test "classifyCFunction - C stdlib patterns are not FFI" {
    // Standard C library calls should NOT be classified as FFI
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("malloc_wrapper"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("free_memory"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("my_mmap_handler"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("socket_create"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("fopen_file"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("pthread_create_cb"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("signal_handler"));
}

test "classifyCFunction - non-FFI returns unknown" {
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("my_internal_func"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("calculate_value"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("process_data_internal"));
}

test "classifyCFunction - word boundary prevents FP" {
    // POSIX I/O words (close, open, read, write, pipe) are now in C_STDLIB_PATTERNS → .unknown
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("close_file"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("open_socket"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("read_data"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("write_buffer"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("pipe_create"));

    // Generic lifecycle patterns still classify as FFI
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("destroy_handle"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("create_resource"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("init_module"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCFunction("handle_event"));

    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("disclose"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("reopen"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("threadsafe"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("overwrite"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("pipeline"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("get_handle_count"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCFunction("reinitialize"));
}

test "classifyFunctionWithEvidence - C++ STL mangled names -> .safe" {
    const cpp_evidence = LanguageProfile{
        .language = .cpp,
        .confidence = 0.9,
        .method = .sampling,
    };

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_ZNSt6vectorIiEE9push_backERKi", null, cpp_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_ZNSt7basic_stringIcSt11char_traitsIcESaIcEE5c_strEv", null, cpp_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_ZNSt3mapIiiSt4lessIiSaIiEE6insertERKi", null, cpp_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_ZSt4sortIPiEvT_S3_", null, cpp_evidence),
    );
}

test "classifyFunctionWithEvidence - C++ operator new/delete -> .safe" {
    const cpp_evidence = LanguageProfile{
        .language = .cpp,
        .confidence = 0.85,
        .method = .sampling,
    };

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_Znwm", null, cpp_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("_ZdlPv", null, cpp_evidence),
    );
}

test "classifyFunctionWithEvidence - C++ user code still uses standard rules" {
    const cpp_evidence = LanguageProfile{
        .language = .cpp,
        .confidence = 0.8,
        .method = .sampling,
    };

    try std.testing.expectEqual(
        ZoneKind.unsafe,
        classifyFunctionWithEvidence("reinterpret_cast<int*>", null, cpp_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.unknown,
        classifyFunctionWithEvidence("my_custom_function", null, cpp_evidence),
    );
}

test "classifyFunctionWithEvidence - Rust module with __rust_ intrinsics -> .runtime_internal" {
    const rust_evidence = LanguageProfile{
        .language = .rust,
        .confidence = 0.95,
        .method = .sampling,
    };

    try std.testing.expectEqual(
        ZoneKind.runtime_internal,
        classifyFunctionWithEvidence("__rust_dealloc", null, rust_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.runtime_internal,
        classifyFunctionWithEvidence("__rust_alloc", null, rust_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.runtime_internal,
        classifyFunctionWithEvidence("_ZN4core3ptr13drop_in_place", null, rust_evidence),
    );
}

test "classifyFunctionWithEvidence - C module with libc functions -> .safe" {
    const c_evidence = LanguageProfile{
        .language = .c,
        .confidence = 0.9,
        .method = .globals,
    };

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("memcpy", null, c_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("strlen", null, c_evidence),
    );

    try std.testing.expectEqual(
        ZoneKind.safe,
        classifyFunctionWithEvidence("qsort", null, c_evidence),
    );
}

test "classifyFunctionWithEvidence - null evidence falls back to original logic" {
    const result_with_null = classifyFunctionWithEvidence("my_function", null, null);
    const result_original = classifyFunction("my_function", null);

    try std.testing.expectEqual(result_original, result_with_null);
}
