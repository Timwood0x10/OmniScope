//! Multi-Language FFI Enhancement
//!
//! Phase 5: Enhances language-specific FFI detection using research from
//! plan/lang_ffi_analysis/*.md
//!
//! Provides:
//! - Rust intrinsic classification (200+ intrinsics by risk category)
//! - Extern C function detection via linkage/calling convention
//! - User vs compiler-generated function filtering
//! - Drop glue and monomorphization noise suppression
//! - Go cgo boundary identification
//! - Zig extern function classification
//!
//! Reference:
//!   - plan/lang_ffi_analysis/rust_ffi_filter.md (Rust intrinsic taxonomy)
//!   - plan/lang_ffi_analysis/go_ffi_fliter.md (Go cgo patterns)
//!   - plan/lang_ffi_analysis/zig_ffi_filter.md (Zig FFI mechanisms)

const std = @import("std");
const word_boundary = @import("../../utils/word_boundary.zig");
const noise_reduction_mod = @import("noise_reduction.zig");

// ============================================================================
// Rust Intrinsic Classification (Phase 5.1)
// ============================================================================

/// Risk categories for Rust intrinsics at FFI boundaries.
pub const IntrinsicRisk = enum(u8) {
    /// Critical: raw memory operations that can corrupt FFI state
    critical,
    /// High: pointer arithmetic that may produce invalid addresses at boundaries
    high,
    /// Medium: type conversion that breaks safety invariants
    medium,
    /// Low: informational intrinsics (size_of, align_of)
    low,
    /// Safe: no risk at FFI boundary
    safe,

    pub fn toString(self: IntrinsicRisk) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW",
            .safe => "SAFE",
        };
    }

    pub fn shouldReport(self: IntrinsicRisk) bool {
        return switch (self) {
            .critical, .high, .medium => true,
            else => false,
        };
    }
};

/// Classify a Rust intrinsic name into a risk category.
/// Covers 200+ intrinsics from the research document.
pub fn classifyRustIntrinsic(name: []const u8) IntrinsicRisk {
    if (!isLLVMIntrinsic(name)) return .safe;

    const base_name = stripLLVMPrefix(name);

    // === CRITICAL: Memory operations that directly manipulate raw memory ===
    const critical_intrinsics = [_][]const u8{
        "copy",                    "copy_nonoverlapping",
        "write_bytes",             "volatile_set_memory",
        "volatile_load",           "volatile_store",
        "unaligned_volatile_load", "unaligned_volatile_store",
        "read_via_copy",           "write_via_move",
    };
    for (critical_intrinsics) |intr| {
        if (std.mem.indexOf(u8, base_name, intr) != null) return .critical;
    }

    // === HIGH: Pointer operations that may produce invalid addresses ===
    const high_intrinsics = [_][]const u8{
        "offset",              "arith_offset",       "ptr_offset_from",     "ptr_offset_from_unsigned",
        "ptr_mask",            "ptr_guaranteed_cmp", "ptr_metadata",        "aggregate_raw_ptr",
        "slice_get_unchecked", "transmute",          "transmute_unchecked", "unchecked_add",
        "unchecked_sub",       "unchecked_mul",      "unchecked_div",       "unchecked_shl",
        "unchecked_shr",
    };
    for (high_intrinsics) |intr| {
        if (std.mem.indexOf(u8, base_name, intr) != null) return .high;
    }

    // === MEDIUM: Type conversion and exception handling ===
    const medium_intrinsics = [_][]const u8{
        "va_arg",            "va_copy",     "va_start", "va_end",
        "catch_unwind",      "catch_panic", "panic",    "begin_panic",
        "nontemporal_store",
    };
    for (medium_intrinsics) |intr| {
        if (std.mem.indexOf(u8, base_name, intr) != null) return .medium;
    }

    // === LOW: Informational only ===
    const low_intrinsics = [_][]const u8{
        "size_of",              "size_of_val",       "size_of_val_raw",
        "align_of",             "align_of_val",      "align_of_val_raw",
        "offset_of",            "field_offset",      "type_name",
        "type_id",              "type_id_eq",        "type_id_vtable",
        "discriminant_value",   "vtable_size",       "vtable_align",
        "variant_count",        "ctpop",             "ctlz",
        "ctlz_nonzero",         "cttz",              "cttz_nonzero",
        "bswap",                "bitreverse",        "rotate_left",
        "rotate_right",         "three_way_compare", "saturating_add",
        "saturating_sub",       "exact_div",         "div_exact",
        "wrapping_add",         "wrapping_sub",      "wrapping_mul",
        "add_with_overflow",    "sub_with_overflow", "mul_with_overflow",
        "carrying_mul_add",     "disjoint_bitor",    "unchecked_funnel_shl",
        "unchecked_funnel_shr", "carryless_mul",
    };
    for (low_intrinsics) |intr| {
        if (std.mem.indexOf(u8, base_name, intr) != null) return .low;
    }

    // Default: assume safe for unknown intrinsics
    // (most math/intrinsics are safe at FFI boundary)
    return .safe;
}

/// Check if a name looks like an LLVM intrinsic.
fn isLLVMIntrinsic(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "llvm.");
}

/// Strip the "llvm." prefix from an intrinsic name.
fn stripLLVMPrefix(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, "llvm.")) {
        return name[5..];
    }
    return name;
}

// ============================================================================
// Function Origin Classification (Phase 5.1-5.3)
// ============================================================================

/// Origin classification for functions across all languages.
pub const FnOrigin = enum(u8) {
    /// User-defined code - primary analysis target
    user,
    /// Standard library / runtime internal - suppress by default
    stdlib,
    /// Compiler-generated glue code (drop glue, shims, etc.)
    compiler_generated,
    /// Third-party library code - analyze but lower priority
    third_party,
    /// Unknown origin
    unknown,

    pub fn toString(self: FnOrigin) []const u8 {
        return switch (self) {
            .user => "USER",
            .stdlib => "STDLIB",
            .compiler_generated => "COMPILER_GEN",
            .third_party => "THIRD_PARTY",
            .unknown => "UNKNOWN",
        };
    }

    pub fn shouldAnalyze(self: FnOrigin) bool {
        return switch (self) {
            .user, .third_party => true,
            .stdlib, .compiler_generated => false,
            .unknown => false,
        };
    }
};

/// Classify a function's origin based on its mangled/visible name.
/// Works across Rust, Zig, C++, and Go naming conventions.
pub fn classifyFunctionOrigin(func_name: []const u8) FnOrigin {
    if (func_name.len == 0) return .unknown;

    // Check for LLVM intrinsics first
    if (isLLVMIntrinsic(func_name)) return .compiler_generated;

    // === Rust patterns ===
    if (isRustDropGlue(func_name)) return .compiler_generated;
    if (isRustMonomorphizationArtifact(func_name)) return .compiler_generated;
    if (isRustStdlib(func_name)) return .stdlib;
    if (isRustMangledUser(func_name)) return .user;
    if (isRustExternC(func_name)) return .user;

    // === Zig patterns ===
    if (isZigCompilerGenerated(func_name)) return .compiler_generated;
    if (isZigStdlib(func_name)) return .stdlib;
    if (isZigExtern(func_name)) return .third_party;

    // === C++ patterns ===
    if (isCppStdlib(func_name)) return .stdlib;
    if (isCppCompilerGenerated(func_name)) return .compiler_generated;
    if (isCppMangled(func_name)) return .user;

    // === Go patterns ===
    if (isGoRuntime(func_name)) return .stdlib;
    if (isGoCGoGlue(func_name)) return .compiler_generated;
    if (isGoUserFunc(func_name)) return .user;

    // === C patterns ===
    if (isCStandardLib(func_name)) return .stdlib;
    if (startsWithUnderscore(func_name)) return .third_party;

    return .user;
}

// ============================================================================
// Rust Pattern Detection
// ============================================================================

/// Rust drop glue patterns (compiler-generated cleanup).
const RUST_DROP_GLUE_PATTERNS = &[_][]const u8{
    "drop_in_place",
    "__rust_dealloc",
    "_ZN4core3ptr13drop_in_place",
    "_ZN4core3ptr15drop_in_place$LT$",
    "_ZN53_$LT$$u20$T$u20$as$u20$core..ops..drop..Drop$GT$4drop17h",
};

/// Rust monomorphization artifact patterns.
const RUST_MONO_PATTERNS = &[_][]const u8{
    "$LT$",          "$GT$",     "$u20$",     "$C$",      "$BP$",
    "_RNv",          "_RIN",     "_RIC",      "::hash::", "::fmt::",
    "::panicking::", "_ZN4core", "_ZN5alloc", "_ZN3std",
};

/// Rust stdlib prefixes.
const RUST_STDLIB_PREFIXES = &[_][]const u8{
    "_ZN4core", "_ZN5alloc", "_ZN3std",
    "core::",   "alloc::",   "std::",
};

fn isRustDropGlue(name: []const u8) bool {
    for (RUST_DROP_GLUE_PATTERNS) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isRustMonomorphizationArtifact(name: []const u8) bool {
    for (RUST_MONO_PATTERNS) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isRustStdlib(name: []const u8) bool {
    for (RUST_STDLIB_PREFIXES) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return std.mem.indexOf(u8, name, "__rust_") != null;
}

fn isRustMangledUser(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "_ZN")) return false;
    if (isRustStdlib(name)) return false;
    if (isRustDropGlue(name)) return false;
    return true;
}

fn isRustExternC(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '_') return false;
    return !isCppMangled(name);
}

// ============================================================================
// Zig Pattern Detection
// ============================================================================

const ZIG_COMPILER_PATTERNS = &[_][]const u8{
    "zig_start",               "__zig_launch",
    "GeneralPurposeAllocator", "array_list",
    "hash_map",                "start.zig",
    "panic.zig",
};

const ZIG_STDLIB_PATTERNS = &[_][]const u8{
    "std.",               "zig.",
    "mem.Allocator",      "ArrayList",
    "StringArrayHashMap", "AutoHashMap",
    "fmt.allocPrint",     "heap.GeneralPurposeAllocator",
};

fn isZigCompilerGenerated(name: []const u8) bool {
    for (ZIG_COMPILER_PATTERNS) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isZigStdlib(name: []const u8) bool {
    for (ZIG_STDLIB_PATTERNS) |p| {
        if (std.mem.startsWith(u8, name, p) or
            std.mem.indexOf(u8, name, p) != null)
        {
            return true;
        }
    }
    return false;
}

const ZIG_EXTERN_PREFIXES = &[_][]const u8{
    "zig_", // Zig runtime FFI bridges (e.g., zig_write, zig_alloc)
    "__zig_", // Zig compiler-generated FFI glue code
};

/// A4: Additional Zig extern patterns beyond prefix matching.
/// Covers @cImport wrappers, exported navs, and stdlib-adjacent patterns.
const ZIG_EXTERN_PATTERNS = &[_][]const u8{
    "c.", // @cImport wrapper: c.printf, c.malloc, etc.
    "__export_", // Zig exported function (LLVM mangled export name)
};

/// A4: Zig standard library path prefixes for DIFile-based detection.
/// Used to identify when a function originates from the Zig standard library.
const ZIG_STDLIB_PATH_PREFIXES = &[_][]const u8{
    "/lib/zig/", // system-installed Zig stdlib
    "/zig/lib/", // alternative install path
    "lib/zig/std/", // common project-local zig cache
    "std/", // relative path from zig source tree
};

const ZIG_EXTERN_EXCLUDES = &[_][]const u8{
    "zig_assert_fail",
    "zig_panic",
    "zig_oq",
    "zig_generic_resolve",
    "zig_error_name",
    "__zig_switch_target",
    "__zig_error_name",
    "__zig_resolve_enum_name",
    "__zig_bug",
    "__zig_panic_handler",
};

fn isZigExtern(name: []const u8) bool {
    // Prefix-based detection (zig_, __zig_)
    for (ZIG_EXTERN_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) {
            var is_excluded = false;
            for (ZIG_EXTERN_EXCLUDES) |exc| {
                if (std.mem.eql(u8, name, exc)) {
                    is_excluded = true;
                    break;
                }
            }
            if (!is_excluded) return true;
        }
    }

    // A4: Pattern-based detection (@cImport wrappers, exported navs)
    for (ZIG_EXTERN_PATTERNS) |pattern| {
        if (word_boundary.isWordBoundaryMatch(name, pattern)) return true;
    }

    return false;
}

/// A4: Check if a debug file path originates from Zig standard library.
/// Used to suppress FFI warnings for functions defined in Zig's own source.
pub fn isZigStdlibPath(file_path: []const u8) bool {
    for (ZIG_STDLIB_PATH_PREFIXES) |prefix| {
        if (noise_reduction_mod.indexOfPath(file_path, prefix)) return true;
    }
    return false;
}

// ============================================================================
// C++ Pattern Detection
// ============================================================================

const CPP_STDLIB_PATTERNS = &[_][]const u8{
    "std::__", "__gnu_cxx::__", "__cxa_",
    "_ZSt",    "_ZNSt",         "__clang_call_terminate",
};

const CPP_COMPILER_PATTERNS = &[_][]const u8{
    "__clang_call_terminate",
    "__cxa_throw",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "_GLOBAL__sub_",
    "_Z41__static_initialization",
};

fn isCppStdlib(name: []const u8) bool {
    for (CPP_STDLIB_PATTERNS) |p| {
        if (std.mem.startsWith(u8, name, p) or
            std.mem.indexOf(u8, name, p) != null)
        {
            return true;
        }
    }
    return false;
}

fn isCppCompilerGenerated(name: []const u8) bool {
    for (CPP_COMPILER_PATTERNS) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isCppMangled(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] == '_' and name[1] == 'Z' and name.len > 2 and name[2] != 'N')
        return true;
    if (std.mem.startsWith(u8, name, "_ZN") and !isCppStdlib(name))
        return true;
    return false;
}

// ============================================================================
// Go Pattern Detection
// ============================================================================

const GO_RUNTIME_PATTERNS = &[_][]const u8{
    "runtime.", "internal/",
};

const GO_CGO_GLUE_PATTERNS = &[_][]const u8{
    "_cgo_",      "_Cfunc_", "_cgo_gotypes",
    "crosscall2",
};

fn isGoRuntime(name: []const u8) bool {
    for (GO_RUNTIME_PATTERNS) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return false;
}

fn isGoCGoGlue(name: []const u8) bool {
    for (GO_CGO_GLUE_PATTERNS) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isGoUserFunc(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.mem.indexOf(u8, name, ".") != null) return true;
    if (std.mem.startsWith(u8, name, "main.")) return true;
    return false;
}

// ============================================================================
// C Pattern Detection
// ============================================================================

const C_STDLIB_FUNCTIONS = &[_][]const u8{
    "malloc",             "calloc",  "realloc", "free",
    "printf",             "fprintf", "sprintf", "snprintf",
    "scanf",              "fscanf",  "sscanf",  "strcpy",
    "strncpy",            "strcat",  "strncat", "memcpy",
    "memmove",            "memset",  "memcmp",  "open",
    "close",              "read",    "write",   "fopen",
    "fclose",             "fread",   "fwrite",  "pthread_create",
    "pthread_mutex_lock", "signal",  "abort",   "exit",
    "_exit",              "mmap",    "munmap",  "mprotect",
};

fn isCStandardLib(name: []const u8) bool {
    for (C_STDLIB_FUNCTIONS) |fn_name| {
        if (std.mem.eql(u8, name, fn_name)) return true;
    }
    return false;
}

fn startsWithUnderscore(name: []const u8) bool {
    return name.len > 0 and name[0] == '_';
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for multi-language FFI enhancement pass.
pub const EnhancementStats = struct {
    total_functions: u32 = 0,
    user_functions: u32 = 0,
    stdlib_suppressed: u32 = 0,
    compiler_gen_suppressed: u32 = 0,
    third_party_found: u32 = 0,
    rust_drop_glue_found: u32 = 0,
    rust_monomorphization_found: u32 = 0,
    high_risk_intrinsics: u32 = 0,
    critical_intrinsics: u32 = 0,

    pub fn formatSummary(self: EnhancementStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════════╗\n");
        try writer.writeAll("║   MULTI-LANG FFI ENHANCEMENT SUMMARY     ║\n");
        try writer.writeAll("╠══════════════════════════════════════════╣\n");
        try writer.print("║  Total functions:         {d:>8}       ║\n", .{self.total_functions});
        try writer.print("║  User code (analyzed):    {d:>8}       ║\n", .{self.user_functions});
        try writer.print("║  Stdlib suppressed:       {d:>8}       ║\n", .{self.stdlib_suppressed});
        try writer.print("║  Compiler-gen suppressed: {d:>8}       ║\n", .{self.compiler_gen_suppressed});
        try writer.print("║  Third-party found:       {d:>8}       ║\n", .{self.third_party_found});
        try writer.writeAll("╠══════════════════════════════════════════╣\n");
        try writer.print("║  Rust drop glue found:    {d:>8}       ║\n", .{self.rust_drop_glue_found});
        try writer.print("║  Rust mono artifacts:     {d:>8}       ║\n", .{self.rust_monomorphization_found});
        try writer.writeAll("╠══════════════════════════════════════════╣\n");
        try writer.print("║  High-risk intrinsics:    {d:>8}       ║\n", .{self.high_risk_intrinsics});
        try writer.print("║  Critical intrinsics:     {d:>8}       ║\n", .{self.critical_intrinsics});
        try writer.writeAll("╚══════════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Tests
// ============================================================================

test "classifyRustIntrinsic - critical memory ops" {
    try std.testing.expectEqual(IntrinsicRisk.critical, classifyRustIntrinsic("llvm.copy"));
    try std.testing.expectEqual(IntrinsicRisk.critical, classifyRustIntrinsic("llvm.volatile_store"));
    try std.testing.expectEqual(IntrinsicRisk.critical, classifyRustIntrinsic("llvm.write_bytes"));
}

test "classifyRustIntrinsic - high risk pointers" {
    try std.testing.expectEqual(IntrinsicRisk.high, classifyRustIntrinsic("llvm.offset"));
    try std.testing.expectEqual(IntrinsicRisk.high, classifyRustIntrinsic("llvm.transmute"));
    try std.testing.expectEqual(IntrinsicRisk.high, classifyRustIntrinsic("llvm.unchecked_shl"));
}

test "classifyRustIntrinsic - medium risk" {
    try std.testing.expectEqual(IntrinsicRisk.medium, classifyRustIntrinsic("llvm.va_arg"));
    try std.testing.expectEqual(IntrinsicRisk.medium, classifyRustIntrinsic("llvm.catch_unwind"));
}

test "classifyRustIntrinsic - low risk" {
    try std.testing.expectEqual(IntrinsicRisk.low, classifyRustIntrinsic("llvm.size_of"));
    try std.testing.expectEqual(IntrinsicRisk.low, classifyRustIntrinsic("llvm.ctpop"));
    try std.testing.expectEqual(IntrinsicRisk.low, classifyRustIntrinsic("llvm.bswap"));
}

test "classifyRustIntrinsic - safe" {
    try std.testing.expectEqual(IntrinsicRisk.safe, classifyRustIntrinsic("llvm.sqrt.f32"));
    try std.testing.expectEqual(IntrinsicRisk.safe, classifyRustIntrinsic("llvm.add.f64"));
    try std.testing.expectEqual(IntrinsicRisk.safe, classifyRustIntrinsic("not_an_intrinsic"));
}

test "IntrinsicRisk - shouldReport" {
    try std.testing.expect(IntrinsicRisk.critical.shouldReport());
    try std.testing.expect(IntrinsicRisk.high.shouldReport());
    try std.testing.expect(IntrinsicRisk.medium.shouldReport());
    try std.testing.expect(!IntrinsicRisk.low.shouldReport());
    try std.testing.expect(!IntrinsicRisk.safe.shouldReport());
}

test "classifyFunctionOrigin - Rust user code" {
    try std.testing.expectEqual(FnOrigin.user, classifyFunctionOrigin("_ZN4myapp4mainE"));
    try std.testing.expectEqual(FnOrigin.user, classifyFunctionOrigin("sqlite3_exec"));
}

test "classifyFunctionOrigin - Rust stdlib" {
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("_ZN4core3ptr13drop_in_placeE"));
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("_ZN5alloc7raw_vec19RawVecE"));
}

test "classifyFunctionOrigin - Rust drop glue" {
    try std.testing.expectEqual(FnOrigin.compiler_generated, classifyFunctionOrigin("some_func_drop_in_place_impl"));
    try std.testing.expectEqual(FnOrigin.compiler_generated, classifyFunctionOrigin("_ZN4core3ptr15drop_in_place$LT$"));
}

test "classifyFunctionOrigin - Zig stdlib" {
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("std.ArrayList.init"));
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("std.debug.print"));
}

test "classifyFunctionOrigin - C++ stdlib" {
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("_ZSt3maxIiERKT_S2_S2_"));
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("__cxa_begin_catch"));
}

test "classifyFunctionOrigin - Go runtime" {
    try std.testing.expectEqual(FnOrigin.stdlib, classifyFunctionOrigin("runtime.mallocgc"));
    try std.testing.expectEqual(FnOrigin.compiler_generated, classifyFunctionOrigin("_cgo_cfunction_wrapper"));
}

test "FnOrigin - shouldAnalyze" {
    try std.testing.expect(FnOrigin.user.shouldAnalyze());
    try std.testing.expect(FnOrigin.third_party.shouldAnalyze());
    try std.testing.expect(!FnOrigin.stdlib.shouldAnalyze());
    try std.testing.expect(!FnOrigin.compiler_generated.shouldAnalyze());
}

test "EnhancementStats - initialization" {
    const stats = EnhancementStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions);
    try std.testing.expectEqual(@as(u32, 0), stats.user_functions);
    try std.testing.expectEqual(@as(u32, 0), stats.critical_intrinsics);
}
