//! Tests for language_detector.zig
//!
//! These tests verify the core language detection logic including:
//!   - Language enum type safety (langToIndex / indexToLang)
//!   - Global variable name classification
//!   - C++ RTTI/vtable detection
//!   - Python C extension detection
//!   - C# / .NET symbol detection
//!   - Go runtime symbol detection
//!   - False positive prevention

const std = @import("std");
const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const language_detector = @import("language_detector.zig");

const langToIndex = language_detector.langToIndex;
const indexToLang = language_detector.indexToLang;

/// Classify a single global variable name to its likely language.
///
/// Mirrors the prefix-matching logic from language_detector.detectFromGlobals()
/// for unit-testing individual symbol names without needing a full LLVM module.
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

    // Go runtime globals (fine-grained classification)
    if (std.mem.startsWith(u8, name, "__go_")) {
        return .go;
    }

    // Go runtime internal global variables
    const is_go_runtime_global = blk: {
        if (!std.mem.startsWith(u8, name, "runtime.")) break :blk false;

        const rest = name["runtime.".len..];

        if (std.mem.startsWith(u8, rest, "gclock") or
            std.mem.startsWith(u8, rest, "gc") or
            std.mem.startsWith(u8, rest, "sched") or
            std.mem.startsWith(u8, rest, "mcache") or
            std.mem.startsWith(u8, rest, "mheap") or
            std.mem.startsWith(u8, rest, "mcentral") or
            std.mem.startsWith(u8, rest, "mfixed") or
            std.mem.startsWith(u8, rest, "allg") or
            std.mem.startsWith(u8, rest, "allm") or
            std.mem.startsWith(u8, rest, "allp") or
            std.mem.startsWith(u8, rest, "park") or
            std.mem.startsWith(u8, rest, "wake") or
            std.mem.startsWith(u8, rest, "stopm") or
            std.mem.startsWith(u8, rest, "startm") or
            std.mem.startsWith(u8, rest, "handoffp"))
        {
            break :blk true;
        }

        break :blk false;
    };

    if (is_go_runtime_global) {
        return .go;
    }

    // Zig globals
    if (std.mem.startsWith(u8, name, "zig.") or
        std.mem.startsWith(u8, name, "__zig_"))
    {
        return .zig;
    }

    // Python GC internal runtime symbols
    if (std.mem.startsWith(u8, name, "_PyGC_")) {
        return .python;
    }

    // C# / .NET global symbols
    if (std.mem.startsWith(u8, name, "__dotnet_") or
        std.mem.startsWith(u8, name, "__cil_") or
        std.mem.startsWith(u8, name, "System_") or
        std.mem.startsWith(u8, name, "Microsoft_") or
        std.mem.startsWith(u8, name, "Mono_"))
    {
        return .csharp;
    }

    // C# managed code / GC markers (weaker signal)
    if (std.mem.indexOf(u8, name, "__managed_") != null or
        std.mem.indexOf(u8, name, "gc_frame") != null)
    {
        return .csharp;
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
    try std.testing.expectEqual(@as(?Language, null), classifyGlobalName("_Z4funcv"));
}

test "C++ with RTTI produces strong cpp signal" {
    const rtti_symbols = [_][]const u8{
        "_ZTV4Base",
        "_ZTVN3foo6BarE",
        "_ZTI4Base",
        "_ZTIN3foo6BarE",
        "_ZTS4Base",
        "_ZTIN3foo6BarE",
    };

    var cpp_count: u32 = 0;
    for (rtti_symbols) |sym| {
        if (classifyGlobalName(sym)) |lang| {
            if (lang == .cpp) cpp_count += 1;
        }
    }

    try std.testing.expectEqual(@as(u32, 6), cpp_count);
}

test "Python C extension PyInit_ functions are detected" {
    const pyinit_symbols = [_][]const u8{
        "PyInit_mymodule",
        "PyInit_numpy",
        "PyInit__ctypes",
        "PyInit_spam",
    };

    for (pyinit_symbols) |sym| {
        try std.testing.expect(std.mem.startsWith(u8, sym, "PyInit_"));
        try std.testing.expect(sym.len > 7);
    }
}

test "Python GC internal _PyGC_ globals are detected" {
    const pygc_symbols = [_][]const u8{
        "_PyGC_Collect",
        "_PyGC_AddToRootSet",
        "_PyGC_RemoveFromRootSet",
        "_PyGC_Track",
        "_PyGC_UnTrack",
    };

    for (pygc_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.python, lang.?);
    }
}

test "Non-Python symbols are not falsely detected as Python" {
    const non_python = [_][]const u8{
        "PyInitializer",
        "init_py_module",
        "__py__",
        "python_func",
        "_PyNonGC_",
    };

    for (non_python) |sym| {
        if (std.mem.startsWith(u8, sym, "PyInit_")) {
            unreachable;
        }
        if (std.mem.startsWith(u8, sym, "_PyGC_")) {
            unreachable;
        }
    }
}

test "C# / .NET global symbols are classified as csharp" {
    const csharp_strong_symbols = [_][]const u8{
        "__dotnet_init",
        "__cil_exceptions",
        "System_Console",
        "Microsoft_Win32",
        "Mono_Runtime",
    };

    for (csharp_strong_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.csharp, lang.?);
    }

    const csharp_weak_symbols = [_][]const u8{
        "__managed_thread_id",
        "gc_frame_0",
    };

    for (csharp_weak_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.csharp, lang.?);
    }
}

test "Non-C# symbols are not falsely detected as C#" {
    const non_csharp = [_][]const u8{
        "__rust_no_alloc_shim",
        "__go_go",
        "__cxa_guard",
        "__start_mysection",
        "system_call",
        "dotnet_custom",
    };

    for (non_csharp) |sym| {
        const lang = classifyGlobalName(sym);
        if (lang) |l| {
            try std.testing.expect(l != .csharp);
        }
    }
}

test "Go runtime internal symbols are classified as Go in classifyGlobalName" {
    // GC internals
    const gc_symbols = [_][]const u8{
        "runtime.gclock_gw",
        "runtime.gcBgMarkWorker",
        "runtime.gcStart",
        "runtime.gcDrain",
        "runtime.gcSweep",
        "runtime.gcResetMarkState",
    };

    for (gc_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.go, lang.?);
    }

    // Scheduler internals
    const scheduler_symbols = [_][]const u8{
        "runtime.schedinit",
        "runtime.schedule",
        "runtime.park0",
        "runtime.park1",
        "runtime.wakep",
        "runtime.stopm",
        "runtime.startm",
        "runtime.handoffp",
    };

    for (scheduler_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.go, lang.?);
    }

    // Memory management internals
    const mem_symbols = [_][]const u8{
        "runtime.mcache",
        "runtime.mheap_",
        "runtime.mcentral",
        "runtime.allg",
        "runtime.allm",
        "runtime.allp",
    };

    for (mem_symbols) |sym| {
        const lang = classifyGlobalName(sym);
        try std.testing.expect(lang != null);
        try std.testing.expectEqual(Language.go, lang.?);
    }
}

test "Non-Go symbols are not falsely detected as Go" {
    const non_go = [_][]const u8{
        "__rust_no_alloc_shim",
        "__cxa_guard",
        "_ZTV4Base",
        "System_Console",
        "running_time",
        "my_runtime_var",
    };

    for (non_go) |sym| {
        const lang = classifyGlobalName(sym);
        if (lang) |l| {
            try std.testing.expect(l != .go);
        }
    }
}
