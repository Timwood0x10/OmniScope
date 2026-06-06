//! Data constants and pattern tables for language detection.
//!
//! Extracted from language_detector.zig to keep the main detection
//! logic focused on control flow rather than large pattern lists.

const std = @import("std");

// ═══════════════════════════════════════════════════════════════
// Detection Weights
// ═══════════════════════════════════════════════════════════════

pub const SAMPLING_WEIGHT: f32 = 1.0;
pub const PERSONALITY_WEIGHT: f32 = 0.8;
pub const GLOBALS_WEIGHT: f32 = 0.6;

pub const PERSONALITY_STRONG: f32 = 3.0;
pub const GLOBAL_STRONG_WEIGHT: f32 = 2.0;
pub const GLOBAL_WEAK_WEIGHT: f32 = 1.0;

pub const SAMPLE_SIZE: usize = 50;

pub const LANGUAGE_COUNT: usize = 8;

pub const MIN_SAMPLING_CONFIDENCE: f32 = 0.4;
pub const MIN_VOTE_THRESHOLD: f32 = 0.3;
pub const MIN_PERSONALITY_SCORE: f32 = 2.0;
pub const MIN_GLOBALS_SCORE: f32 = 1.5;

// ═══════════════════════════════════════════════════════════════
// Sampling Pattern Categories
// ═══════════════════════════════════════════════════════════════

/// Prefixes that identify Rust functions (unambiguous)
pub const rust_strong_prefixes = &[_][]const u8{
    "_rust_",
    "rs2py_",
};

/// Prefixes that identify Go functions (unambiguous)
pub const go_strong_prefixes = &[_][]const u8{
    "main.",
    "runtime.",
    "syscall.",
    "gcops.",
};

/// Zig markers (unambiguous)
pub const zig_markers = &[_][]const u8{
    "zig_",
    "Allocator.",
};

/// C# / .NET NativeAOT strong markers
pub const csharp_prefixes = &[_][]const u8{
    "$s",
    "<Module>.",
    "System.",
    "Microsoft.",
    "Mono_",
    "GC_",
    "IL_",
};

/// C# / .NET substring markers
pub const csharp_substrings = &[_][]const u8{
    "__DotNet",
    "Marshal_",
};

pub const PrefixLimited = struct { prefix: []const u8, len: usize };

/// C# / .NET first-N-char prefix patterns: (prefix, check_len)
pub const csharp_prefix_limited = &[_]PrefixLimited{
    .{ .prefix = "System_", .len = 7 },
    .{ .prefix = "Microsoft_", .len = 10 },
    .{ .prefix = "Mono_", .len = 5 },
    .{ .prefix = "_N3System", .len = 9 },
};

/// Go / TinyGo markers (from TINYGO_IR_SPEC.md)
pub const go_tinygo_prefixes = &[_][]const u8{
    "runtime.",
    "internal/task.",
    "reflect/types.",
};

/// Go CGo bridge markers
pub const go_cgo_markers = &[_][]const u8{
    "_Cgo_",
};

/// Go runtime internal function category patterns (after "runtime." prefix)
pub const go_runtime_gc = &[_][]const u8{ "gc", "mallocgc", "scanobject", "markroot", "sweep", "scanstack" };
pub const go_runtime_scheduler = &[_][]const u8{ "schedule", "park", "wake", "stopm", "startm", "handoffp" };
pub const go_runtime_channel = &[_][]const u8{ "chan", "select" };
pub const go_runtime_interface = &[_][]const u8{ "interface", "assertI2I", "assertE2I", "convI2E" };
pub const go_runtime_map = &[_][]const u8{ "mapaccess", "mapassign", "mapdelete", "mapiter" };
pub const go_runtime_goroutine = &[_][]const u8{ "newproc", "goexit", "systemstack", "morestack", "lessstack" };
pub const go_runtime_defer = &[_][]const u8{ "defer" };

/// Aggregated Go runtime internal patterns for bulk checking
pub const go_runtime_internal_categories = &[_][]const []const u8{
    go_runtime_gc,
    go_runtime_scheduler,
    go_runtime_channel,
    go_runtime_interface,
    go_runtime_map,
    go_runtime_goroutine,
    go_runtime_defer,
};

// ═══════════════════════════════════════════════════════════════
// Personality Function Patterns
// ═══════════════════════════════════════════════════════════════

pub const rust_personality = &[_][]const u8{ "rust_eh_personality" };
pub const cpp_personality = &[_][]const u8{ "__gxx_personality_v0", "__gxx_personality" };
pub const csharp_personality = &[_][]const u8{ "csharp_exception_personality", "mono_unity_personality" };
pub const c_personality_exact = &[_][]const u8{ "_Unwind_Resume", "_Unwind_RaiseException" };

// ═══════════════════════════════════════════════════════════════
// Global Variable Patterns
// ═══════════════════════════════════════════════════════════════

pub const csharp_global_prefixes = &[_][]const u8{
    "__dotnet_",
    "__cil_",
    "System_",
    "Microsoft_",
    "Mono_",
};

pub const csharp_global_substrings = &[_][]const u8{
    "__managed_",
    "gc_frame",
};

pub const rust_global_prefixes = &[_][]const u8{ "__rust_" };
pub const go_global_prefixes = &[_][]const u8{ "__go_" };
pub const zig_global_prefixes = &[_][]const u8{ "zig.", "__zig_" };
pub const cpp_global_prefixes = &[_][]const u8{ "__cxa_" };
pub const python_global_prefixes = &[_][]const u8{ "_PyGC_" };
pub const c_global_prefixes = &[_][]const u8{ "__start_", "__stop_", "__end_" };

// ═══════════════════════════════════════════════════════════════
// Helper Functions
// ═══════════════════════════════════════════════════════════════

/// Check if `name` starts with any of the given prefixes.
pub fn hasAnyPrefix(name: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return false;
}

/// Check if `name` contains any of the given substrings.
pub fn hasAnySubstring(name: []const u8, substrings: []const []const u8) bool {
    for (substrings) |s| {
        if (std.mem.indexOf(u8, name, s) != null) return true;
    }
    return false;
}

/// Check if `name` starts with any of the given prefixes within the first `check_len` characters.
pub fn hasAnyPrefixLimited(name: []const u8, patterns: []const PrefixLimited) bool {
    for (patterns) |p| {
        if (name.len > p.len and std.mem.indexOf(u8, name[0..p.len], p.prefix) != null) return true;
    }
    return false;
}

/// Check if a function name (after "runtime." prefix) matches any Go runtime internal pattern.
pub fn isGoRuntimeInternal(func_name: []const u8) bool {
    if (!std.mem.startsWith(u8, func_name, "runtime.")) return false;
    const rest = func_name["runtime.".len..];

    for (go_runtime_internal_categories) |category| {
        if (hasAnyPrefix(rest, category)) return true;
    }
    return false;
}

/// Check if a function name contains a '.' with .NET-specific namespace patterns.
pub fn hasDotNetQualifiedName(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, ".") == null) return false;
    return std.mem.indexOf(u8, name, "System.") != null or
        std.mem.indexOf(u8, name, "Microsoft.") != null or
        std.mem.indexOf(u8, name, "Mono.") != null;
}

/// Check if a global name has C++ RTTI/vtable pattern (_ZTV, _ZTI, _ZTS).
pub fn isCppRttiGlobal(name: []const u8) bool {
    if (name.len > 3 and name[0] == '_' and name[1] == 'Z' and name[2] == 'T') {
        const third = name[3];
        return third == 'V' or third == 'I' or third == 'S';
    }
    return false;
}

/// Check if a function name matches a personality function pattern.
pub fn matchPersonality(name: []const u8) ?enum { rust, cpp, csharp } {
    if (std.mem.eql(u8, name, "rust_eh_personality") or
        std.mem.indexOf(u8, name, "rust_eh_personality") != null)
    {
        return .rust;
    }
    if (std.mem.eql(u8, name, "__gxx_personality_v0") or
        std.mem.indexOf(u8, name, "__gxx_personality") != null)
    {
        return .cpp;
    }
    if (std.mem.eql(u8, name, "csharp_exception_personality") or
        std.mem.indexOf(u8, name, "csharp_exception_personality") != null or
        std.mem.eql(u8, name, "mono_unity_personality") or
        std.mem.indexOf(u8, name, "mono_unity_personality") != null)
    {
        return .csharp;
    }
    return null;
}

/// Check for C unwind personality functions (lower weight).
pub fn isCUnwindPersonality(name: []const u8) bool {
    return std.mem.eql(u8, name, "_Unwind_Resume") or
        std.mem.eql(u8, name, "_Unwind_RaiseException");
}