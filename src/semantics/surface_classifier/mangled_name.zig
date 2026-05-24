//! Surface Classifier — Layer 0: Mangled Name Heuristic
//!
//! Classifies function origin from the mangled symbol name itself.
//! This layer is the cheapest of all (pure string matching, zero LLVM API calls)
//! and serves as the fallback when debug metadata (L2) is unavailable.
//!
//! Why this works: Rust/C++ mangled names encode crate paths and namespace
//! hierarchies. _ZN4core3fmt5Debug3fmt means core::fmt::Debug::fmt — we can
//! determine provenance without any debug info.
//!
//! Design principle (from todo.md):
//!   1. No crate-name whitelists — match structural patterns only
//!   2. Zero instruction scanning — O(1) per function
//!   3. Language-agnostic — Rust Itanium, C++ Itanium, Zig, Go

const std = @import("std");
const log = @import("../../common/log.zig");

const SurfaceHint = @import("surface_classifier.zig").SurfaceHint;
const FunctionSurface = @import("surface_classifier.zig").FunctionSurface;

// ============================================================================
// Public API
// ============================================================================

/// Classify function surface from its mangled name alone.
///
/// Returns null if the name doesn't match any known pattern,
/// in which case downstream layers (L1 linkage, L2 debug origin) decide.
pub fn classifyMangledName(name: []const u8) ?SurfaceHint {
    if (name.len == 0) return null;

    // Fast path: Rust Itanium mangling (_ZN... or _RNv... prefix)
    if (name.len > 2 and name[0] == '_' and (name[1] == 'Z' or name[1] == 'R')) {
        return classifyRustItanium(name);
    }

    // C++ Itanium mangling
    if (name.len > 1 and name[0] == '_' and name[1] == 'Z') {
        return classifyCppItanium(name);
    }

    // Unmangled / plain names — check well-known compiler patterns
    return classifyPlainName(name);
}

/// Diagnostic version with detailed logging.
/// Logs why each function matched (or didn't match) at L0 level.
pub fn classifyMangledNameDiagnostic(name: []const u8) ?SurfaceHint {
    const result = classifyMangledName(name);
    if (result) |hint| {
        log.debug("[L0-MANGLE] '{s}': => {s} ({s})", .{ name, hint.surface.toString(), hint.reason });
    } else {
        log.debug("[L0-MANGLE] '{s}': no pattern matched, deferring to L1/L2", .{name});
    }
    return result;
}

// ============================================================================
// Rust Itanium Mangling (_ZN<seq>E, _R<variant><hash>_<seq>E)
// ============================================================================

/// Classify a Rust-Itanium-mangled function name.
///
/// Rust uses Itanium-style mangling with extensions:
///   _ZN<length><segment><length><segment>...E  — legacy (pre-0.29)
///   _R<variant><hash>_<length><segment>...E   — new style (v0 mangling)
///
/// We don't need full demangling — just check leading segments for
/// known stdlib/compiler paths.
fn classifyRustItanium(name: []const u8) ?SurfaceHint {
    // --- Standard library paths (high confidence) ---

    // core::*, std::*, alloc::* — always stdlib regardless of project
    if (hasPrefixSegment(name, "core")) {
        // core::panicking, core::ptr (drop_in_place), core::ops, core::fmt etc.
        if (isCoreInternal(name)) {
            return .{
                .surface = .standard_library,
                .confidence = .high,
                .reason = "Rust core library internal",
            };
        }
        // Some core traits impl on user types — be conservative
        return .{
            .surface = .standard_library,
            .confidence = .medium,
            .reason = "Rust core library",
        };
    }

    if (hasPrefixSegment(name, "std")) return .{
        .surface = .standard_library,
        .confidence = .high,
        .reason = "Rust standard library",
    };

    if (hasPrefixSegment(name, "alloc")) return .{
        .surface = .standard_library,
        .confidence = .high,
        .reason = "Rust alloc crate (stdlib)",
    };

    if (hasPrefixSegment(name, "panic_unwind") or hasPrefixSegment(name, "panic_runtime")) return .{
        .surface = .runtime,
        .confidence = .high,
        .reason = "Rust panic/runtime internal",
    };

    // --- Compiler-generated glue (high confidence, 100% safe) ---

    // drop_in_place<T> — compiler-generated destructor shim.
    // This is purely compiler glue with no user logic whatsoever:
    // it just calls ptr::drop_in_place which is a single LLVM intrinsic.
    if (std.mem.indexOf(u8, name, "drop_in_place") != null) return .{
        .surface = .compiler_generated,
        .confidence = .high,
        .reason = "compiler drop glue",
    };

    // panicking functions (assert_failed, panic, begin_panic)
    if (std.mem.indexOf(u8, name, "panicking") != null) return .{
        .surface = .runtime,
        .confidence = .high,
        .reason = "Rust panic machinery",
    };

    // __rust_* allocator intrinsics
    if (std.mem.indexOf(u8, name, "__rust_") != null) return .{
        .surface = .standard_library,
        .confidence = .high,
        .reason = "Rust global allocator intrinsic",
    };

    // --- Trait method shims: $LT$<type> as Trait>$GT$::method ---
    //
    // ⚠️ REMOVED: We no longer classify these as compiler_generated.
    //
    // Why: 81%+ of $LT$ matches are user-written trait implementations
    // (e.g., ring::rsa::PKCS1 as Verification::verify contains real
    // crypto logic). The mangled name is compiler-generated but the
    // function body is user code.
    //
    // These functions now fall through to null → downstream layers decide.
    // If debug info (L2) is available, source path classification works.
    // If not, they get classified as unknown → analyzed by default (safe).
    //
    // Future improvement: when debug info IS available, we could check
    // whether the trait is a well-known derive macro target (Debug,
    // Clone, PartialEq, etc.) vs. a user-defined trait — the former
    // are more likely to be boilerplate.

    // --- Unknown Rust-mangled name (dependency or user code) ---
    // Cannot distinguish wasmtime::runtime from user::mycrate without
    // knowing the workspace crate list. Defer to L1/L2/L3.
    return null;
}

/// Check if a Rust-mangled name starts with a given segment as its first
/// namespace component after the _ZN/_R prefix.
///
/// For _ZN4core3fmt5Debug3fmtE, hasPrefixSegment(name, "core") returns true.
fn hasPrefixSegment(name: []const u8, segment: []const u8) bool {
    // Find the start of segments (skip _ZN, _R<variant><hash>_ etc.)
    const seg_start = findFirstSegment(name) orelse return false;

    // Check if first segment matches
    if (seg_start + segment.len > name.len) return false;
    return std.mem.eql(u8, name[seg_start..][0..segment.len], segment);
}

/// Find the byte offset of the first namespace segment in a mangled name.
/// Skips _ZN prefix or _R<variant><hash>_ prefix.
fn findFirstSegment(name: []const u8) ?usize {
    if (name.len < 3) return null;

    // Legacy: _ZN<seg_len><seg>...
    if (name[0] == '_' and name[1] == 'Z' and name[2] == 'N') {
        return 3; // right after "_ZN"
    }

    // New v0: _R<variant><hash64>_<seg_len><seg>...
    // variant is one char, hash is up to 16 hex chars, then underscore
    if (name[0] == '_' and name[1] == 'R') {
        if (name.len < 3) return null;
        var i: usize = 2; // skip _R
        // Skip variant char
        i += 1;
        // Skip hex hash digits until '_'
        while (i < name.len and name[i] != '_') : (i += 1) {}
        if (i >= name.len) return null;
        return i + 1; // skip the '_'
    }

    return null;
}

/// Detect known core-internal paths that are definitely compiler artifacts,
/// not user code implementing core traits.
fn isCoreInternal(name: []const u8) bool {
    // core::ptr::{drop_in_place, unique, non_null} — compiler glue
    if (std.mem.indexOf(u8, name, "3ptr") != null) return true;
    // core::ops::{function, FnOnce, FnMut, Fn} — closure shims
    if (std.mem.indexOf(u8, name, "3ops") != null) return true;
    // core::fmt — auto-derived Debug/Display impls
    if (std.mem.indexOf(u8, name, "3fmt") != null) return true;
    // core::num — numeric trait impls
    if (std.mem.indexOf(u8, name, "3num") != null) return true;
    // core::str — string trait impls
    if (std.mem.indexOf(u8, name, "3str") != null) return true;
    // core::array — array trait impls
    if (std.mem.indexOf(u8, name, "5array") != null) return true;
    // core::task — async/waker internals
    if (std.mem.indexOf(u8, name, "4task") != null) return true;
    // core::future — future internals
    if (std.mem.indexOf(u8, name, "6future") != null) return true;
    // core::iter — iterator internals
    if (std.mem.indexOf(u8, name, "4iter") != null) return true;
    // core::panicking — assert/panic
    if (std.mem.indexOf(u8, name, "9panicking") != null) return true;
    return false;
}

/// Detect trait method shims by checking for Itanium substitution tokens
/// that appear in monomorphized trait method names:
///   $LT$ = <, $GT$ = >, $u20$ = space, $RF$ = &, $BP$ = *
///   $LP$ = (, $RP$ = ), $C$ = :, $u7b$ = {, $u7d$ = }
fn isTraitMethodShim(name: []const u8) bool {
    // The most reliable signal: $LT$..$GT$ pattern (generic args)
    if (std.mem.indexOf(u8, name, "$LT$") != null) return true;
    // Legacy angle-bracket encoding (less common but exists)
    if (std.mem.indexOf(u8, name, "as$") != null and
        std.mem.indexOf(u8, name, "$GT$") != null) return true;
    return false;
}

// ============================================================================
// C++ Itanium Mangling
// ============================================================================

fn classifyCppItanium(name: []const u8) ?SurfaceHint {
    // C++ STL: std::* → standard_library
    // _ZSt = std::, _ZNSt = std::
    if (std.mem.startsWith(u8, name, "_ZSt") or
        std.mem.startsWith(u8, name, "_ZNSt"))
    {
        return .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = "C++ standard library",
        };
    }

    // C++ ABI internals: __cxa_* → runtime
    if (std.mem.indexOf(u8, name, "__cxa_") != null) return .{
        .surface = .runtime,
        .confidence = .high,
        .reason = "C++ ABI runtime",
    };

    // GCC/Clang builtins: __*_chk (fortified), __builtin_* → compiler_generated
    if (std.mem.indexOf(u8, name, "__") != null) {
        if (std.mem.indexOf(u8, name, "_chk") != null or
            std.mem.indexOf(u8, name, "_builtin") != null)
        {
            return .{
                .surface = .compiler_generated,
                .confidence = .high,
                .reason = "compiler builtin / fortified",
            };
        }
    }

    return null;
}

// ============================================================================
// Plain (unmangled) Names
// ============================================================================

fn classifyPlainName(name: []const u8) ?SurfaceHint {
    // Well-known compiler-generated patterns across languages
    if (std.mem.indexOf(u8, name, ".llvm.") != null) return .{
        .surface = .compiler_generated,
        .confidence = .high,
        .reason = "LLVM internal",
    };

    // C# / .NET NativeAOT patterns — these are unambiguous
    // <Module>. is the canonical prefix for module-level static methods in AOT output
    const dotnet_module_prefix = "\x3CModule\x3E.";
    if (std.mem.startsWith(u8, name, dotnet_module_prefix)) {
        return .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = ".NET NativeAOT module method",
        };
    }
    // System.* / Microsoft.* = BCL (Base Class Library)
    if (std.mem.startsWith(u8, name, "System.") or
        std.mem.startsWith(u8, name, "Microsoft."))
    {
        return .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = ".NET Base Class Library",
        };
    }
    // Rh* = Runtime Helpers (ILC-generated runtime support functions)
    if (name.len > 2 and name[0] == 'R' and name[1] == 'h') {
        return .{
            .surface = .runtime,
            .confidence = .high,
            .reason = ".NET Runtime Helper (Rh*)",
        };
    }
    // GC_* = GC interaction stubs
    if (std.mem.startsWith(u8, name, "GC_")) {
        return .{
            .surface = .runtime,
            .confidence = .high,
            .reason = ".NET GC stub",
        };
    }
    // IL_* = IL code stubs
    if (std.mem.startsWith(u8, name, "IL_")) {
        return .{
            .surface = .runtime,
            .confidence = .medium,
            .reason = ".NET IL stub",
        };
    }

    // Go/TinyGo runtime patterns (from TINYGO_IR_SPEC.md)
    // TinyGo's runtime package is the primary entry point for all runtime operations.
    // Standard Go uses similar naming but with more GC-related functions.
    if (std.mem.startsWith(u8, name, "runtime.")) {
        return .{
            .surface = .runtime,
            .confidence = .high,
            .reason = "Go-TinyGo runtime",
        };
    }
    if (std.mem.startsWith(u8, name, "internal/task.")) {
        return .{
            .surface = .runtime,
            .confidence = .high,
            .reason = "TinyGo task scheduler",
        };
    }
    if (std.mem.startsWith(u8, name, "reflect/types.")) {
        return .{
            .surface = .standard_library,
            .confidence = .high,
            .reason = "Go reflect types",
        };
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "classifyMangledName - Rust core stdlib" {
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZN4core3ptr45drop_in_place<...>").?.surface);
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZN4core9panicking13assert_failed").?.surface);
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZN3std3io2io5print17habc123").?.surface);
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZN5alloc6string6String3new").?.surface);
}

test "compileMangledName - Rust compiler-generated" {
    try std.testing.expectEqual(FunctionSurface.compiler_generated, classifyMangledName("_ZN4core3ptr10drop_in_place17habc123").?.surface);
    // $LT$ trait shims are NO LONGER classified as compiler_generated
    // because 81%+ of matches are user-written trait impls with real logic.
    // They now return null → downstream layers decide.
    const trait_shim = classifyMangledName("_ZN103_$LT$ring..ec..suite_b$GT$3fmt17habc");
    try std.testing.expect(trait_shim == null);
}

test "classifyMangledName - Rust runtime" {
    try std.testing.expectEqual(FunctionSurface.runtime, classifyMangledName("_ZN9panicking9begin_panic17habc").?.surface);
}

test "classifyMangledName - Rust dependency (unknown crate)" {
    // wasmtime::runtime::* should NOT match any stdlib pattern → returns null
    const result = classifyMangledName("_ZN8wasmtime7runtime4Instance7new17habc");
    try std.testing.expect(result == null);
}

test "classifyMangledName - C++ STL" {
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZSt16__throw_bad_allocv").?.surface);
    try std.testing.expectEqual(FunctionSurface.standard_library, classifyMangledName("_ZNSt6vectorIiEE5clearEv").?.surface);
}

test "classifyMangledName - C++ ABI runtime" {
    try std.testing.expectEqual(FunctionSurface.runtime, classifyMangledName("__cxa_begin_catch").?.surface);
}

test "classifyMangledName - plain name no match" {
    const result = classifyMangledName("my_function");
    try std.testing.expect(result == null);

    const result2 = classifyMangledName("");
    try std.testing.expect(result2 == null);
}

test "hasPrefixSegment - basic" {
    try std.testing.expect(hasPrefixSegment("_ZN4core3fmt5Debug3fmtE", "core"));
    try std.testing.expect(hasPrefixSegment("_ZN3std3io3fooE", "std"));
    try std.testing.expect(!hasPrefixSegment("_ZN4core3fmt5Debug3fmtE", "std"));
}

test "isTraitMethodShim - detects generics" {
    // isTraitMethodShim still works as a utility function for future use,
    // but we no longer use it to classify functions as compiler_generated.
    try std.testing.expect(isTraitMethodShim("_ZN103_$LT$ring..ec$GT$3fmt17habc"));
    try std.testing.expect(!isTraitMethodShim("_ZN4ring4sha25617habc"));
}

test "isCoreInternal - detects compiler internals" {
    try std.testing.expect(isCoreInternal("_ZN4core3ptr10drop_in_place17habc"));
    try std.testing.expect(isCoreInternal("_ZN4core3ops8function6FnOnce9call_once17habc"));
    try std.testing.expect(!isCoreInternal("_ZN4mycrate5utils7helper17habc"));
}
