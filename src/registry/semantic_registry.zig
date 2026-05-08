//! Semantic Registry for FFI Boundary Analysis
//!
//! This module provides a knowledge base for FFI boundary function semantics.
//! It is NOT a simple "dangerous function blacklist" - instead, it captures
//! the semantic properties of functions that are relevant when crossing
//! language boundaries.
//!
//! Key insight: The same function has different risk levels depending on context:
//! - `strcpy` in pure C code = medium risk
//! - `strcpy` crossing Rust→C boundary = HIGH risk (length constraint broken, lifetime broken)
//!
//! Layers:
//! - Layer 1: FFI high-risk functions (C standard library)
//! - Layer 2: Rust ownership patterns (into_raw, from_raw, as_ptr)
//! - Layer 3: Go cgo allocator patterns
//! - Layer 4: Swift FFI patterns
//! - Layer 5: Zig Standard Library patterns
//! - Layer 6: C++ Standard Library patterns
//!
//! Additional modules:
//! - JNI functions
//! - Python C API functions
//! - POSIX I/O functions
//! - POSIX thread/signal/process management

const std = @import("std");
const types = @import("types.zig");

// Import language/function-specific registries
const layer1_reg = @import("layer1_reg.zig");
const layer2_reg = @import("layer2_reg.zig");
const layer3_reg = @import("layer3_reg.zig");
const layer4_reg = @import("layer4_reg.zig");
const layer5_reg = @import("layer5_reg.zig");
const layer6_reg = @import("layer6_reg.zig");
const jni_reg = @import("jni_reg.zig");
const python_c_api_reg = @import("python_c_api_reg.zig");
const posix_io_reg = @import("posix_io_reg.zig");
const posix_thread_reg = @import("posix_thread_reg.zig");
const dynamic_loading_reg = @import("dynamic_loading_reg.zig");

pub const RiskKind = types.RiskKind;
pub const Severity = types.Severity;
pub const MatchType = types.MatchType;
pub const FunctionSemantics = types.FunctionSemantics;

/// The semantic registry containing all known function semantics.
pub const SemanticRegistry = struct {
    /// Layer 1: FFI high-risk functions (C standard library)
    const layer1 = layer1_reg.layer1_functions;

    /// Layer 2: Rust ownership patterns
    const layer2 = layer2_reg.layer2_functions;

    /// Layer 3: Go cgo allocator patterns
    const layer3 = layer3_reg.layer3_functions;

    /// Layer 4: Swift FFI patterns
    const layer4 = layer4_reg.layer4_functions;

    /// Layer 5: Zig Standard Library patterns
    const layer5 = layer5_reg.layer5_functions;

    /// Layer 6: C++ Standard Library patterns
    const layer6 = layer6_reg.layer6_functions;

    /// JNI functions
    const jni = jni_reg.jni_functions;

    /// Python C API functions
    const python_c_api = python_c_api_reg.python_c_api_functions;

    /// POSIX I/O functions
    const file_io = posix_io_reg.file_io_functions;
    const network_io = posix_io_reg.network_io_functions;

    /// POSIX static buffer functions (return internal static storage)
    const static_buffer = posix_io_reg.static_buffer_functions;

    /// POSIX thread/signal/process management
    const signal_handler = posix_thread_reg.signal_handler_functions;
    const thread_mgmt = posix_thread_reg.thread_mgmt_functions;
    const process_mgmt = posix_thread_reg.process_mgmt_functions;

    /// Dynamic loading functions
    const dynamic_loading = dynamic_loading_reg.dynamic_loading_functions;

    /// Lookup function semantics by name.
    /// Searches all layers in order.
    pub fn lookup(func_name: []const u8) ?FunctionSemantics {
        for (layer1) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer2) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer3) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer4) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer5) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer6) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (jni) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (python_c_api) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (file_io) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (network_io) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (signal_handler) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (thread_mgmt) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (process_mgmt) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (dynamic_loading) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (static_buffer) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        return null;
    }

    fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
        return switch (match_type) {
            .exact => std.mem.eql(u8, func_name, pattern),
            .contains => std.mem.indexOf(u8, func_name, pattern) != null,
            .suffix => std.mem.endsWith(u8, func_name, pattern),
        };
    }

    pub fn isKnown(func_name: []const u8) bool {
        return lookup(func_name) != null;
    }

    pub fn getRiskKind(func_name: []const u8) ?RiskKind {
        const sem = lookup(func_name) orelse return null;
        return sem.kind;
    }

    pub fn getSeverity(func_name: []const u8) ?Severity {
        const sem = lookup(func_name) orelse return null;
        return sem.severity;
    }

    pub fn consumesOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.consumes_ownership;
    }

    pub fn transfersOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.transfers_ownership;
    }

    pub fn requiresNullCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_null_check;
    }

    pub fn requiresTaintCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_taint_check;
    }

    pub fn getDescription(func_name: []const u8) ?[]const u8 {
        const sem = lookup(func_name) orelse return null;
        return sem.description;
    }

    pub fn layer1Count() usize {
        return layer1.len;
    }

    pub fn layer2Count() usize {
        return layer2.len;
    }

    pub fn layer3Count() usize {
        return layer3.len;
    }

    pub fn layer4Count() usize {
        return layer4.len;
    }

    pub fn layer5Count() usize {
        return layer5.len;
    }

    pub fn layer6Count() usize {
        return layer6.len;
    }

    pub fn totalCount() usize {
        return layer1.len + layer2.len + layer3.len + layer4.len + layer5.len + layer6.len +
            jni.len + python_c_api.len + file_io.len + network_io.len +
            signal_handler.len + thread_mgmt.len + process_mgmt.len + dynamic_loading.len +
            static_buffer.len;
    }

    // ========================================================================
    // Hook System (Phase 3)
    // ========================================================================

    /// Registered analysis hooks (comptime-initialized for zero runtime cost).
    /// NOTE: Not thread-safe — registerHook/runHooks must be called from a single
    /// thread or externally synchronized. This is acceptable because hook registration
    /// happens once during pass initialization before analysis begins.
    var hooks: [MAX_HOOKS]?types.AnalysisHook = [_]?types.AnalysisHook{null} ** MAX_HOOKS;
    var hook_count: usize = 0;

    const MAX_HOOKS = 16;

    /// Register an analysis hook. Returns error if hook table is full.
    pub fn registerHook(hook: types.AnalysisHook) !void {
        if (hook_count >= MAX_HOOKS) return error.HookTableFull;
        hooks[hook_count] = hook;
        hook_count += 1;
    }

    /// Run all registered hooks against the given context.
    /// Stops at first hook that returns .issue_found or .suppressed.
    pub fn runHooks(ctx: *types.HookContext) types.HookResult {
        for (hooks[0..hook_count]) |opt_hook| {
            if (opt_hook) |hook| {
                const result = hook.run(ctx);
                if (result != .none) return result;
            }
        }
        return .none;
    }

    /// Get number of registered hooks.
    pub fn hookCount() usize {
        return hook_count;
    }

    // ========================================================================
    // R9.1: Hierarchical (Context-Sensitive) Risk Inference
    // ========================================================================

    /// Result of context-sensitive risk inference.
    pub const InferredRisk = struct {
        kind: RiskKind,
        severity: Severity,
        confidence: f32,
        consumes_ownership: bool,
        transfers_ownership: bool,
        reason: []const u8,
    };

    /// Known language identifiers for cross-language inference.
    pub const Language = enum { go, rust, c, cpp, python, swift, zig, unknown };

    /// Parse a language identifier string to Language enum.
    pub fn parseLanguage(lang_str: []const u8) Language {
        if (lang_str.len > 64) return .unknown;
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (lang_str) |c| {
            if (len >= buf.len) break;
            buf[len] = if (c >= 'A' and c <= 'Z') c + 32 else c;
            len += 1;
        }
        const lower = buf[0..len];
        if (std.mem.eql(u8, lower, "go")) return .go;
        if (std.mem.eql(u8, lower, "rust") or std.mem.eql(u8, lower, "rs")) return .rust;
        if (std.mem.eql(u8, lower, "c")) return .c;
        if (std.mem.eql(u8, lower, "cpp") or std.mem.eql(u8, lower, "c++")) return .cpp;
        if (std.mem.eql(u8, lower, "python") or std.mem.eql(u8, lower, "py")) return .python;
        if (std.mem.eql(u8, lower, "swift")) return .swift;
        if (std.mem.eql(u8, lower, "zig")) return .zig;
        return .unknown;
    }

    /// R9.1 core: Infer risk from caller language + callee function name.
    ///
    /// This implements hierarchical reasoning that goes beyond simple pattern matching:
    /// - `caller=Go ∧ callee=C.malloc ⇒ {risk: go_cgo_alloc, conf: 0.95}`
    /// - `caller=Rust ∧ callee=C.strcpy ⇒ {risk: unchecked_copy, conf: 0.90}`
    /// - Falls back to registry lookup if no cross-language rule matches.
    pub fn inferCrossLangRisk(caller_lang: []const u8, callee_name: []const u8) ?InferredRisk {
        const lang = parseLanguage(caller_lang);
        const sem = lookup(callee_name) orelse return null;

        // Rule: Go → C allocator functions get elevated to go_cgo_alloc with high confidence
        if (lang == .go and isCAllocator(callee_name)) {
            return InferredRisk{
                .kind = .go_cgo_alloc,
                .severity = .high,
                .confidence = 0.95,
                .consumes_ownership = false,
                .transfers_ownership = true,
                .reason = "Go caller invoking C allocator — memory not managed by Go GC",
            };
        }

        // Rule: Go → C.free is especially dangerous (double-free / GC race)
        if (lang == .go and isCFree(callee_name)) {
            return InferredRisk{
                .kind = .go_cgo_alloc,
                .severity = .critical,
                .confidence = 0.97,
                .consumes_ownership = true,
                .transfers_ownership = false,
                .reason = "Go caller invoking C.free — may free GC-managed or already-freed memory",
            };
        }

        // Rule: Rust → C string functions elevate risk (no length info crossing FFI)
        if (lang == .rust and isCStringFunc(callee_name)) {
            return InferredRisk{
                .kind = .unchecked_copy,
                .severity = .high,
                .confidence = 0.90,
                .consumes_ownership = false,
                .transfers_ownership = false,
                .reason = "Rust→C string op — length guarantee lost at FFI boundary",
            };
        }

        // Rule: Rust → C allocator needs from_raw pairing
        if (lang == .rust and isCAllocator(callee_name)) {
            return InferredRisk{
                .kind = .rust_ownership,
                .severity = .high,
                .confidence = 0.92,
                .consumes_ownership = false,
                .transfers_ownership = true,
                .reason = "Rust caller allocating via C malloc — must pair with from_raw",
            };
        }

        // Default: return registry semantics as-is (no elevation)
        return InferredRisk{
            .kind = sem.kind,
            .severity = sem.severity,
            .confidence = 0.70,
            .consumes_ownership = sem.consumes_ownership,
            .transfers_ownership = sem.transfers_ownership,
            .reason = "Registry pattern match (no cross-language elevation)",
        };
    }

    /// Check if a function name is a C allocator (malloc, calloc, realloc, etc.)
    fn isCAllocator(name: []const u8) bool {
        const alloc_patterns = [_][]const u8{
            "malloc",        "calloc",         "realloc",  "reallocarray",
            "aligned_alloc", "posix_memalign", "memalign", "_Znwm",
            "_Znam",         "mmap",           "mmap64",
        };
        for (alloc_patterns) |pat| {
            if (std.mem.indexOf(u8, name, pat) != null) return true;
        }
        return false;
    }

    /// Check if a function name is a C deallocator (free, etc.)
    fn isCFree(name: []const u8) bool {
        // Specific patterns with low false-positive risk
        const exact_patterns = [_][]const u8{
            "_ZdlPv", "_ZdaPv", "munmap", "dealloc",
        };
        for (exact_patterns) |pat| {
            if (std.mem.indexOf(u8, name, pat) != null) return true;
        }
        // "destroy" / "release" need compound-word exclusion to avoid
        // matching pthread_mutex_destroy, release_lock, sem_destroy, etc.
        if (isWordMatch(name, "destroy")) return true;
        if (isWordMatch(name, "release")) return true;
        // "free" with compound word exclusion
        if (isWordMatch(name, "free")) return true;
        return false;
    }

    /// Check if `needle` appears as a whole word in `haystack`
    /// (not surrounded by alphanumeric characters)
    fn isWordMatch(haystack: []const u8, needle: []const u8) bool {
        const idx = std.mem.indexOf(u8, haystack, needle) orelse return false;
        const needle_len = needle.len;
        if (idx > 0 and isAlphaNum(haystack[idx - 1])) return false;
        const after = idx + needle_len;
        if (after < haystack.len and isAlphaNum(haystack[after])) return false;
        return true;
    }

    /// Check if a function is a C string operation (strcpy, strlen, etc.)
    fn isCStringFunc(name: []const u8) bool {
        const str_patterns = [_][]const u8{
            "strcpy",  "strncpy",  "strcat", "strncat",
            "sprintf", "snprintf", "strlen", "strcmp",
            // R8-M10 FIX: Removed duplicate "strncpy" (was at end of array)
            "strndup",
        };
        for (str_patterns) |pat| {
            if (std.mem.indexOf(u8, name, pat) != null) return true;
        }
        return false;
    }

    fn isAlphaNum(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
    }
};

test "SemanticRegistry - RiskKind enum" {
    try std.testing.expectEqual(@as(usize, 20), @typeInfo(RiskKind).@"enum".fields.len);
}

test "SemanticRegistry - Severity enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Severity.low));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Severity.medium));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Severity.high));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Severity.critical));
}

test "SemanticRegistry - lookup exact match" {
    const sem = SemanticRegistry.lookup("malloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
}

test "SemanticRegistry - lookup unknown function" {
    try std.testing.expect(SemanticRegistry.lookup("unknown_func") == null);
}

test "SemanticRegistry - isKnown" {
    try std.testing.expect(SemanticRegistry.isKnown("free"));
    try std.testing.expect(SemanticRegistry.isKnown("into_raw"));
    try std.testing.expect(!SemanticRegistry.isKnown("unknown_func"));
}

test "SemanticRegistry - getRiskKind" {
    try std.testing.expectEqual(RiskKind.command_exec, SemanticRegistry.getRiskKind("system").?);
    try std.testing.expectEqual(RiskKind.deallocator, SemanticRegistry.getRiskKind("free").?);
}

test "SemanticRegistry - getSeverity" {
    try std.testing.expectEqual(Severity.critical, SemanticRegistry.getSeverity("system").?);
    try std.testing.expectEqual(Severity.high, SemanticRegistry.getSeverity("free").?);
}

test "SemanticRegistry - totalCount" {
    try std.testing.expect(SemanticRegistry.totalCount() > 0);
}

test "R9.1 inferCrossLangRisk - Go to C.malloc" {
    const result = SemanticRegistry.inferCrossLangRisk("go", "malloc") orelse
        @panic("expected inference result");
    try std.testing.expectEqual(RiskKind.go_cgo_alloc, result.kind);
    try std.testing.expectEqual(Severity.high, result.severity);
    try std.testing.expect(result.confidence >= 0.90);
    try std.testing.expect(result.transfers_ownership);
}

test "R9.1 inferCrossLangRisk - Go to C.free is critical" {
    const result = SemanticRegistry.inferCrossLangRisk("go", "free") orelse
        @panic("expected inference result");
    try std.testing.expectEqual(RiskKind.go_cgo_alloc, result.kind);
    try std.testing.expectEqual(Severity.critical, result.severity);
    try std.testing.expect(result.confidence >= 0.95);
    try std.testing.expect(result.consumes_ownership);
}

test "R9.1 inferCrossLangRisk - Rust to C.strcpy" {
    const result = SemanticRegistry.inferCrossLangRisk("rust", "strcpy") orelse
        @panic("expected inference result");
    try std.testing.expectEqual(RiskKind.unchecked_copy, result.kind);
    try std.testing.expect(result.confidence >= 0.85);
}

test "R9.1 inferCrossLangRisk - unknown function returns null" {
    const result = SemanticRegistry.inferCrossLangRisk("go", "xyz_nonexistent_func_12345");
    try std.testing.expect(result == null);
}

test "R9.1 parseLanguage" {
    try std.testing.expectEqual(SemanticRegistry.Language.go, SemanticRegistry.parseLanguage("Go"));
    try std.testing.expectEqual(SemanticRegistry.Language.rust, SemanticRegistry.parseLanguage("RUST"));
    try std.testing.expectEqual(SemanticRegistry.Language.c, SemanticRegistry.parseLanguage("c"));
    try std.testing.expectEqual(SemanticRegistry.Language.python, SemanticRegistry.parseLanguage("Python"));
    try std.testing.expectEqual(SemanticRegistry.Language.unknown, SemanticRegistry.parseLanguage("Java"));
}
