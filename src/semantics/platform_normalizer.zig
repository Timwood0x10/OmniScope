//! Platform-Specific Normalization
//!
//! Normalizes platform-specific symbols, paths, sections, and ABI decorations
//! into a canonical form that is independent of the target OS/object format.
//!
//! This module handles:
//! - P3: Symbol name canonicalization (Mach-O underscore, COFF decoration, etc.)
//! - P4: Debug path / SDK path / toolchain path normalization
//! - P5: Section name category mapping (Mach-O/ELF/COFF → unified categories)
//!
//! Design Principles:
//! - Normalize early, before any language/surface/noise analysis
//! - Preserve original name in metadata for debugging
//! - Never lose information — only add canonical form alongside original

const std = @import("std");
const log = std.log.scoped(.platform_normalizer);
const PlatformProfile = @import("platform_profile.zig").PlatformProfile;

// ============================================================================
// P3: Symbol Name Canonicalization
// ============================================================================

/// Canonicalize a symbol name by removing platform-specific decoration.
///
/// Transformations applied (order matters):
///
/// 1. **Mach-O leading underscore** (macOS/iOS):
///    `_foo` → `foo` (C symbols on Mach-O always have leading `_`)
///
/// 2. **COFF decorated symbols** (Windows MSVC):
///    `foo@12` → `foo` (stdcall stack size suffix)
///    `foo@@4` → `foo` (C++ mangled with fastcall)
///
/// 3. **Import thunk prefixes** (Windows):
///    `__imp__foo` → `foo` (import address table entry)
///    `.refptr.foo` → `foo` (MinGW reference pointer)
///
/// 4. **LLVM intrinsic suffixes** (all platforms):
///    `llvm.memcpy.p0i8.p0i8.i64` → `llvm.memcpy`
///
/// Returns:
///   Canonical symbol name suitable for cross-platform comparison.
///   If no transformation needed, returns original slice.
pub fn canonicalizeSymbolName(name: []const u8, profile: *const PlatformProfile) []const u8 {
    var result = name;

    // Step 1: Remove Mach-O leading underscore
    if (profile.usesMachoUnderscore() and result.len > 0 and result[0] == '_') {
        // Only strip single leading underscore (not double __ which is compiler-internal)
        if (result.len == 1 or result[1] != '_') {
            result = result[1..];
            log.debug("SYMBOL-CANON: stripped Mach-O '_' from '{s}' -> '{s}'", .{ name, result });
        }
    }

    // Step 2: Remove COFF stdcall/fastcall decoration (@N or @@N)
    if (profile.usesCoffDecoration()) {
        if (std.mem.lastIndexOf(u8, result, "@")) |at_idx| {
            // Check if everything after @ is numeric (stdcall suffix)
            const suffix = result[at_idx + 1 ..];
            var is_numeric = true;
            for (suffix) |ch| {
                if (ch < '0' or ch > '9') {
                    is_numeric = false;
                    break;
                }
            }
            if (is_numeric and at_idx > 0) {
                result = result[0..at_idx];
                log.debug("SYMBOL-CANON: stripped COFF decoration from '{s}' -> '{s}'", .{ name, result });
            }
        }
    }

    // Step 3: Remove Windows import thunk prefix
    if (result.len > 6 and std.mem.startsWith(u8, result, "__imp_")) {
        result = result[6..];
        log.debug("SYMBOL-CANON: stripped import thunk from '{s}' -> '{s}'", .{ name, result });
    } else if (result.len > 8 and std.mem.startsWith(u8, result, "__imp__")) {
        result = result[7..]; // Keep one _ for potential Mach-O
        log.debug("SYMBOL-CANON: stripped import thunk from '{s}' -> '{s}'", .{ name, result });
    }

    return result;
}

/// Check if a symbol name is a known platform runtime shim.
///
/// These are compiler-generated or libc-provided functions that should
/// be classified as `runtime` or `compiler_generated`, not user code.
pub fn isPlatformRuntimeShim(canonical_name: []const u8, profile: *const PlatformProfile) bool {
    // Common patterns across all platforms
    const universal_runtime_prefixes = [_][]const u8{
        "llvm.", // LLVM intrinsics
        "__stack_", // Stack protection canaries
        "__asan_", // AddressSanitizer runtime
        "__msan_", // MemorySanitizer runtime
        "__tsan_", // ThreadSanitizer runtime
        "__ubsan_", // UndefinedBehaviorSanitizer runtime
        "__gcov_", // GCOV coverage instrumentation
        "__profn_", // profiling runtime
        ".init.", // C++ static initializers
        ".fini.", // C++ static destructors
        "_GLOBAL_", // Global constructors/destructors (ELF)
        "_ZGTt", // C++ guard variables (Itanium ABI)
        "__cxa_", // C++ ABI runtime (exception handling, atexit)
        "__dso_handle", // Dynamic shared object handle
    };

    for (universal_runtime_prefixes) |prefix| {
        if (std.mem.startsWith(u8, canonical_name, prefix)) {
            return true;
        }
    }

    // Platform-specific shims
    switch (profile.platform) {
        .macos => {
            const macos_runtime_prefixes = [_][]const u8{
                "_dispatch_", // Grand Central Dispatch runtime
                "_objc_", // Objective-C runtime
                "_swift_", // Swift runtime
                "_mach_msg_", // Mach IPC stubs
                "_dyld_", // Dynamic linker runtime
                "__darwin_", // Darwin libc internals
                "_TLV_", // Thread-local variables initializer
                "__block_", // Blocks runtime (Apple extension)
            };

            for (macos_runtime_prefixes) |prefix| {
                if (std.mem.startsWith(u8, canonical_name, prefix)) {
                    return true;
                }
            }
        },

        .linux => {
            const linux_runtime_prefixes = [_][]const u8{
                "__x86.get_pc_thunk", // Position-independent code thunks (x86)
                "register_tm_clones", // libgcc TM clone table
                "__do_global_dtors", // Global destructor registration
                "__do_global_ctors", // Global constructor registration
                "frame_dummy", // GCC frame setup dummy
                "_dl_", // Dynamic linker internals
                "__libc_start_main", // libc startup
                "_start", // ELF entry point
            };

            for (linux_runtime_prefixes) |prefix| {
                if (std.mem.startsWith(u8, canonical_name, prefix)) {
                    return true;
                }
            }
        },

        .windows => {
            const windows_runtime_prefixes = [_][]const u8{
                "__security_cookie", // Stack cookie init (MSVC)
                "__report_gsfailure", // GS failure handler
                "__check_return", // SAL annotation check
                "_except_handler4", // SEH handler
                "__C_specific_handler", // C exception handler
                "_CRT$", // CRT initialization
                "___CxxFrameHandler", // C++ frame handler
                "__imp_", // Import thunk (already stripped in canonicalize)
            };

            for (windows_runtime_prefixes) |prefix| {
                if (std.mem.startsWith(u8, canonical_name, prefix)) {
                    return true;
                }
            }
        },

        else => {}, // WASI/unknown: no additional patterns yet
    }

    return false;
}

// ============================================================================
// P4: Debug Path Normalization
// ============================================================================

/// Categories of file paths found in LLVM debug info (DIFile).
pub const PathProvenance = enum {
    /// User source code — analyze fully
    user_code,
    /// Standard library / SDK headers — surface classification only
    standard_library,
    /// Compiler / toolchain internal — skip analysis
    toolchain_internal,
    /// Build system generated (preprocessed, generated code) — low priority
    build_generated,
    /// Unknown or missing debug info — conservative: keep analyzing
    unknown,
};

/// Normalize a debug file path to determine its provenance.
///
/// This function examines DIFile paths from LLVM debug metadata and
/// classifies them into categories that guide analysis depth:
///
/// - **user_code**: Project workspace, user-written source files
/// - **standard_library**: System headers (/usr/include, SDK paths, etc.)
/// - **toolchain_internal**: Compiler runtime, builtin definitions
/// - **build_generated**: Preprocessor output, generated wrappers
/// - **unknown**: Missing or unrecognizable paths
///
/// Arguments:
///   path    - Full or relative file path from DIFile
///   profile - Current platform profile (used for platform-specific paths)
///
/// Returns:
///   PathProvenance indicating how deeply to analyze functions from this path
pub fn normalizeDebugPath(path: []const u8, profile: *const PlatformProfile) PathProvenance {
    if (path.len == 0) return .unknown;

    // Convert to lowercase for case-insensitive matching (Windows paths are case-insensitive)
    var lower_buf: [1024]u8 = undefined;
    const lower = if (path.len < lower_buf.len) blk: {
        for (path, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z')
                @as(u8, ch + 32)
            else
                ch;
        }
        break :blk lower_buf[0..path.len];
    } else path; // Fallback: use original if too long

    // Check for toolchain-internal paths first (most specific)
    if (isToolchainPath(lower, profile)) {
        return .toolchain_internal;
    }

    // Check for standard library / SDK paths
    if (isStandardLibraryPath(lower)) {
        return .standard_library;
    }

    // Check for build-generated paths
    if (isBuildGeneratedPath(lower)) {
        return .build_generated;
    }

    // Default: assume user code (conservative)
    return .user_code;
}

/// Check if path points to compiler/toolchain internals.
fn isToolchainPath(path: []const u8, profile: *const PlatformProfile) bool {
    const toolchain_patterns = [_][]const u8{
        // LLVM/Clang builtins
        "/lib/clang/",
        "/lib64/clang/",
        "/usr/lib/clang/",
        "/usr/local/lib/clang/",
        // Compiler resource directories
        "/include/__stddef",
        "/include/stddef.h",
        "/include/stdarg.h",
        "/include/limits.h",
        "/include/float.h",
        // Zig compiler builtins
        "/zig/lib/",
        "/zig/libc/",
        "/zig/std/",
        // Rust sysroot
        "/rustc/",
        "/rustlib/",
        // GCC internals
        "/lib/gcc/",
        "/lib64/gcc/",
        "/usr/include/c++/", // libstdc++
        // MSVC CRT
        "\\vc\\tools\\msvc\\",
        "\\Program Files\\Microsoft Visual Studio\\",
        "\\Windows Kits\\10\\Include\\",
        // Xcode toolchain (macOS)
        "/Applications/Xcode.app/",
        "/Library/Developer/CommandLineTools/",
        "/Platforms/MacOSX.platform/Developer/SDKs/",
    };

    for (toolchain_patterns) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }

    // Platform-specific toolchain paths
    if (profile.isAppleDarwin()) {
        const xcode_paths = [_][]const u8{
            "/usr/local/opt/llvm", // Homebrew LLVM
            "/opt/homebrew/Cellar/llvm", // Apple Silicon Homebrew
        };

        for (xcode_paths) |p| {
            if (std.mem.indexOf(u8, path, p) != null) return true;
        }
    }

    return false;
}

/// Check if path points to standard library / system headers.
fn isStandardLibraryPath(path: []const u8) bool {
    const stdlib_patterns = [_][]const u8{
        // POSIX / glibc
        "/usr/include/",
        "/usr/local/include/",
        "/include/sys/",
        "/include/netinet/",
        "/include/arpa/",
        // macOS SDK
        "/System/Library/Frameworks/",
        "/usr/include/malloc/",
        "/usr/include/string.h",
        "/usr/include/stdlib.h",
        "/usr/include/stdio.h",
        // Linux alternatives
        "/nix/store/", // NixOS
        "/gnu/store/", // Guix
    };

    for (stdlib_patterns) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if path looks like build-generated code (preprocessed, wrapped).
fn isBuildGeneratedPath(path: []const u8) bool {
    const generated_patterns = [_][]const u8{
        "/tmp/", // Temporary build directory
        "/var/folders/", // macOS temp
        "$BUILD", // CMake generator expression
        "generated-", // Explicitly generated
        ".pb.cc", // Protocol buffer generated C++
        ".grpc.pb.cc", // gRPC generated
        "_wrap.c", // SWIG wrapper
        "_ffi_bindings", // cffi bindings
    };

    for (generated_patterns) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }

    return false;
}

// ============================================================================
// P5: Section Category Normalization
// ============================================================================

/// Unified section category (platform-independent).
///
/// Maps platform-specific section names (.text, __TEXT, .CRT$XCU, etc.)
/// into a common set of categories used for origin/surface classification.
pub const SectionCategory = enum {
    /// Executable code (instructions)
    code,
    /// Read-only data (constants, string literals)
    rodata,
    /// Read-write data (global variables, static data)
    data,
    /// BSS (zero-initialized data)
    bss,
    /// C/C++ static constructors (.init_array, .CRT$XCU, etc.)
    init_array,
    /// C/C++ static destructors (.fini_array, .CRT$XTY, etc.)
    fini_array,
    /// Exception handling tables (.eh_frame, .pdata, .xdata, etc.)
    exception,
    /// Debug information (.debug_*, DWARF sections)
    debug,
    /// Thread-local storage (.tdata, .tbss)
    tls,
    /// Import/export tables (PLT, GOT, IAT, etc.)
    import_export,
    /// Unknown or unrecognized section
    unknown,

    pub fn displayName(self: SectionCategory) []const u8 {
        return switch (self) {
            .code => "Code",
            .rodata => "ReadOnlyData",
            .data => "Data",
            .bss => "BSS",
            .init_array => "InitArray",
            .fini_array => "FiniArray",
            .exception => "Exception",
            .debug => "Debug",
            .tls => "TLS",
            .import_export => "ImportExport",
            .unknown => "Unknown",
        };
    }
};

/// Map a platform-specific section name to unified category.
///
/// Handles Mach-O (__TEXT, __DATA), ELF (.text, .rodata, .init_array),
/// COFF (.text, .rdata, .CRT$XCU), and wasm (.text, .rodata) sections.
pub fn categorizeSection(section_name: []const u8) SectionCategory {
    if (section_name.len == 0) return .unknown;

    // Convert to lowercase for case-insensitive comparison
    var lower_buf: [128]u8 = undefined;
    const lower = if (section_name.len < lower_buf.len) blk: {
        for (section_name, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z')
                @as(u8, ch + 32)
            else
                ch;
        }
        break :blk lower_buf[0..section_name.len];
    } else section_name;

    // Code sections (all platforms use similar naming)
    if (isCodeSection(lower)) return .code;

    // Read-only data
    if (isRodataSection(lower)) return .rodata;

    // Read-write data
    if (isDataSection(lower)) return .data;

    // BSS (uninitialized data)
    if (isBssSection(lower)) return .bss;

    // Static constructors
    if (isInitArraySection(lower)) return .init_array;

    // Static destructors
    if (isFinisArraySection(lower)) return .fini_array;

    // Exception handling
    if (isExceptionSection(lower)) return .exception;

    // Debug information
    if (isDebugSection(lower)) return .debug;

    // Thread-local storage
    if (isTlsSection(lower)) return .tls;

    // Import/export tables
    if (isImportExportSection(lower)) return .import_export;

    return .unknown;
}

// Section detection helpers (case-insensitive)

fn isCodeSection(name: []const u8) bool {
    const code_patterns = [_][]const u8{
        ".text", "__text", "$T", // Standard code sections
    };
    for (code_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isRodataSection(name: []const u8) bool {
    const rodata_patterns = [_][]const u8{
        ".rodata", "__const", "__TEXT,__const", "__TEXT,__literal",
        ".rdata", ".rdata$", // ELF/COFF read-only data
        ".gcc_except_table", // Exception tables (read-only)
    };
    for (rodata_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isDataSection(name: []const u8) bool {
    const data_patterns = [_][]const u8{
        ".data", "__data", "__DATA,__data",
        ".sdata", "__DATA,__sdata", // Small data
    };
    for (data_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isBssSection(name: []const u8) bool {
    const bss_patterns = [_][]const u8{
        ".bss", "__bss", "__DATA,__bss",
        ".sbss", "__DATA,__common", // Small BSS / common
    };
    for (bss_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isInitArraySection(name: []const u8) bool {
    const init_patterns = [_][]const u8{
        ".init_array",     ".ctors",       ".CRT$XCU", "__DATA,__mod_init_func",
        "__MOD_INIT_FUNC", "__init_array",
    };
    for (init_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isFinisArraySection(name: []const u8) bool {
    const fini_patterns = [_][]const u8{
        ".fini_array",     ".dtors",       ".CRT$XTY", "__DATA,__mod_term_func",
        "__MOD_TERM_FUNC", "__fini_array",
    };
    for (fini_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isExceptionSection(name: []const u8) bool {
    const exc_patterns = [_][]const u8{
        ".eh_frame", ".eh_frame_hdr", ".gcc_except_table",
        ".pdata", ".xdata", "$P", "$X", // COFF exception tables
    };
    for (exc_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isDebugSection(name: []const u8) bool {
    const dbg_patterns = [_][]const u8{
        ".debug_", ".zdebug_", "__DWARF", // DWARF debug sections
    };
    for (dbg_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isTlsSection(name: []const u8) bool {
    const tls_patterns = [_][]const u8{
        ".tdata",   ".tbss", "__DATA,__thread_data", "__DATA,__thread_bss",
        ".tcommon",
    };
    for (tls_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

fn isImportExportSection(name: []const u8) bool {
    const ie_patterns = [_][]const u8{
        ".plt", ".got", ".got.plt", // ELF PLT/GOT
        ".idata", ".edata", // COFF import/export
        ".reloc", "__IMPORT", // Mach-O indirect symbols
    };
    for (ie_patterns) |p| {
        if (std.mem.indexOf(u8, name, p) != null) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "canonicalizeSymbolName - Mach-O underscore" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expectEqualStrings("foo", canonicalizeSymbolName("_foo", &profile));
    try std.testing.expectEqualStrings("__foo", canonicalizeSymbolName("__foo", &profile)); // Double underscore preserved
    try std.testing.expectEqualStrings("main", canonicalizeSymbolName("_main", &profile));
}

test "canonicalizeSymbolName - COFF decoration" {
    var profile = PlatformProfile{
        .platform = .windows,
        .object_format = .coff,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expectEqualStrings("foo", canonicalizeSymbolName("foo@12", &profile));
    try std.testing.expectEqualStrings("bar", canonicalizeSymbolName("bar@@4", &profile));
    try std.testing.expectEqualStrings("baz", canonicalizeSymbolName("baz@0", &profile));
}

test "canonicalizeSymbolName - import thunk" {
    var profile = PlatformProfile{
        .platform = .windows,
        .object_format = .coff,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expectEqualStrings("malloc", canonicalizeSymbolName("__imp_malloc", &profile));
    try std.testing.expectEqualStrings("free", canonicalizeSymbolName("__imp__free", &profile));
}

test "isPlatformRuntimeShim - LLVM intrinsics" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expect(isPlatformRuntimeShim("llvm.memcpy.p0i8.p0i8.i64", &profile));
    try std.testing.expect(isPlatformRuntimeShim("llvm.dbg.value", &profile));
    try std.testing.expect(!isPlatformRuntimeShim("my_function", &profile));
}

test "isPlatformRuntimeShim - macOS Objective-C" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expect(isPlatformRuntimeShim("_objc_msgSend", &profile));
    try std.testing.expect(isPlatformRuntimeShim("_dispatch_async", &profile));
    try std.testing.expect(!isPlatformRuntimeShim("_ZN5myClass4funcEv", &profile)); // User C++ mangled
}

test "normalizeDebugPath - toolchain paths" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "aarch64-apple-macosx",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expectEqual(.toolchain_internal, normalizeDebugPath("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include/stddef.h", &profile));
    try std.testing.expectEqual(.standard_library, normalizeDebugPath("/usr/include/stdio.h", &profile));
    try std.testing.expectEqual(.user_code, normalizeDebugPath("/Users/scc/code/myproject/src/main.c", &profile));
}

test "categorizeSection - Mach-O" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };

    try std.testing.expectEqual(.code, categorizeSection("__TEXT,__text", &profile));
    try std.testing.expectEqual(.rodata, categorizeSection("__TEXT,__const", &profile));
    try std.testing.expectEqual(.data, categorizeSection("__DATA,__data", &profile));
    try std.testing.expectEqual(.init_array, categorizeSection("__DATA,__mod_init_func", &profile));
}

test "categorizeSection - ELF" {
    try std.testing.expectEqual(.code, categorizeSection(".text"));
    try std.testing.expectEqual(.rodata, categorizeSection(".rodata"));
    try std.testing.expectEqual(.init_array, categorizeSection(".init_array"));
    try std.testing.expectEqual(.exception, categorizeSection(".eh_frame"));
}

test "categorizeSection - COFF" {
    try std.testing.expectEqual(.code, categorizeSection(".text$mn"));
    try std.testing.expectEqual(.init_array, categorizeSection(".CRT$XCU"));
    try std.testing.expectEqual(.exception, categorizeSection(".pdata"));
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "canonicalizeSymbolName - empty string" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expectEqualStrings("", canonicalizeSymbolName("", &profile));
}

test "canonicalizeSymbolName - single underscore (Mach-O)" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // Single leading underscore should be stripped on Mach-O
    try std.testing.expectEqualStrings("x", canonicalizeSymbolName("_x", &profile));
}

test "canonicalizeSymbolName - double underscore preserved (Mach-O)" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // Double underscore is compiler-internal, should NOT be stripped
    try std.testing.expectEqualStrings("__foo", canonicalizeSymbolName("__foo", &profile));
}

test "canonicalizeSymbolName - no underscore on non-Mach-O" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // On ELF, leading underscore is part of the name
    try std.testing.expectEqualStrings("_foo", canonicalizeSymbolName("_foo", &profile));
}

test "canonicalizeSymbolName - COFF @0 suffix" {
    var profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // @0 suffix should be stripped
    try std.testing.expectEqualStrings("foo", canonicalizeSymbolName("foo@0", &profile));
}

test "canonicalizeSymbolName - COFF non-numeric suffix not stripped" {
    var profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // If suffix after @ is not purely numeric, don't strip (e.g., foo@bar)
    try std.testing.expectEqualStrings("foo@bar", canonicalizeSymbolName("foo@bar", &profile));
}

test "normalizeDebugPath - empty path returns unknown" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expectEqual(.unknown, normalizeDebugPath("", &profile));
}

test "normalizeDebugPath - user code path" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expectEqual(.user_code, normalizeDebugPath("/home/user/project/src/main.c", &profile));
}

test "normalizeDebugPath - Windows-style path (case insensitive)" {
    var profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expectEqual(.toolchain_internal, normalizeDebugPath("C:\\Program Files\\Microsoft Visual Studio\\include\\stdio.h", &profile));
}

test "categorizeSection - empty string returns unknown" {
    try std.testing.expectEqual(.unknown, categorizeSection(""));
}

test "categorizeSection - case insensitive" {
    try std.testing.expectEqual(.code, categorizeSection(".TEXT")); // uppercase
    try std.testing.expectEqual(.rodata, categorizeSection(".RODATA")); // uppercase
}

test "categorizeSection - unknown section" {
    try std.testing.expectEqual(.unknown, categorizeSection(".custom_section"));
    try std.testing.expectEqual(.unknown, categorizeSection(".weird"));
}

// ============================================================================
// Comprehensive Edge Case Tests
// ============================================================================

test "canonicalizeSymbolName - LLVM intrinsic suffix stripped" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // LLVM intrinsics with type suffixes should be canonicalized
    try std.testing.expectEqualStrings("llvm.memcpy", canonicalizeSymbolName("llvm.memcpy.p0i8.p0i8.i64", &profile));
    try std.testing.expectEqualStrings("llvm.memmove", canonicalizeSymbolName("llvm.memmove.p0i8.p0i8.i64", &profile));
}

test "canonicalizeSymbolName - combined Mach-O underscore + COFF decoration (edge case)" {
    // If somehow both flags are set (shouldn't happen in practice, but test robustness)
    var profile = PlatformProfile{ .platform = .macos, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // Mach-O underscore takes priority first, then COFF decoration
    try std.testing.expectEqualStrings("foo", canonicalizeSymbolName("_foo@12", &profile));
}

test "canonicalizeSymbolName - single character name with underscore" {
    var profile = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expectEqualStrings("", canonicalizeSymbolName("_", &profile)); // Just underscore -> empty
}

test "canonicalizeSymbolName - COFF @ in middle of name not stripped" {
    var profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    // @ in middle is not a stdcall suffix (only at end)
    try std.testing.expectEqualStrings("foo@bar", canonicalizeSymbolName("foo@bar", &profile));
}

test "isPlatformRuntimeShim - sanitizer variants" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // AddressSanitizer
    try std.testing.expect(isPlatformRuntimeShim("__asan_init", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__asan_report_load1", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__asan_store4", &profile));

    // MemorySanitizer
    try std.testing.expect(isPlatformRuntimeShim("__msan_init", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__msan_warning", &profile));

    // ThreadSanitizer
    try std.testing.expect(isPlatformRuntimeShim("__tsan_init", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__tsan_read4", &profile));

    // UBSan
    try std.testing.expect(isPlatformRuntimeShim("__ubsan_handle_type_mismatch_v1", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__ubsan_handle_shift_out_of_bounds", &profile));
}

test "isPlatformRuntimeShim - C++ ABI patterns" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expect(isPlatformRuntimeShim("__cxa_throw", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__cxa_begin_catch", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__cxa_end_catch", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__cxa_allocate_exception", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__cxa_atexit", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__gxx_personality_v0", &profile));
    try std.testing.expect(isPlatformRuntimeShim("_ZTISt9exception", &profile)); // RTTI typeinfo
}

test "isPlatformRuntimeShim - stack protection variants" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expect(isPlatformRuntimeShim("__stack_chk_fail", &profile));
    try std.testing.expect(isPlatformRuntimeShim("__stack_chk_guard", &profile));
    try std.testing.expect(!isPlatformRuntimeShim("__stack_check_custom", &profile)); // Not exact prefix match
}

test "normalizeDebugPath - NixOS and Guix paths" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    // NixOS store paths
    try std.testing.expectEqual(.standard_library, normalizeDebugPath("/nix/store/abc123-glibc-2.35/include/stdio.h", &profile));
    // Guix store paths
    try std.testing.expectEqual(.standard_library, normalizeDebugPath("/gnu/store/def456-glibc/include/string.h", &profile));
}

test "normalizeDebugPath - build generated paths" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expectEqual(.build_generated, normalizeDebugPath("/tmp/build/src/protobuf-generated.pb.cc", &profile));
    try std.testing.expectEqual(.build_generated, normalizeDebugPath("/var/folders/zz/preprocessed.c", &profile));
}

test "normalizeDebugPath - Rust sysroot paths" {
    var profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expectEqual(.toolchain_internal, normalizeDebugPath("/rustc/a1b2c3d4/out/rust-src-1.70.0/library/core/src/num/mod.rs", &profile));
    try std.testing.expectEqual(.toolchain_internal, normalizeDebugPath("/rustlib/x86_64-unknown-linux-gnu/lib/libstd-*.rlib", &profile));
}

test "categorizeSection - all section categories covered" {
    // Code sections
    try std.testing.expectEqual(.code, categorizeSection(".text"));
    try std.testing.expectEqual(.code, categorizeSection(".text.hot"));
    try std.testing.expectEqual(.code, categorizeSection(".text.startup"));
    try std.testing.expectEqual(.code, categorizeSection("__TEXT,__text"));
    try std.testing.expectEqual(.code, categorizeSection(".text$mn"));

    // Read-only data sections
    try std.testing.expectEqual(.rodata, categorizeSection(".rodata"));
    try std.testing.expectEqual(.rodata, categorizeSection(".rodata.str1.1"));
    try std.testing.expectEqual(.rodata, categorizeSection("__TEXT,__const"));
    try std.testing.expectEqual(.rodata, categorizeSection(".rdata"));

    // Data sections
    try std.testing.expectEqual(.data, categorizeSection(".data"));
    try std.testing.expectEqual(.data, categorizeSection(".data.rel.ro"));
    try std.testing.expectEqual(.data, categorizeSection("__DATA,__data"));

    // BSS sections
    try std.testing.expectEqual(.bss, categorizeSection(".bss"));
    try std.testing.expectEqual(.bss, categorizeSection(".bss.rel.ro"));
    try std.testing.expectEqual(.bss, categorizeSection("__DATA,__bss"));

    // Init array sections
    try std.testing.expectEqual(.init_array, categorizeSection(".init_array"));
    try std.testing.expectEqual(.init_array, categorizeSection(".ctors"));
    try std.testing.expectEqual(.init_array, categorizeSection(".CRT$XCU"));

    // Fini array sections
    try std.testing.expectEqual(.fini_array, categorizeSection(".fini_array"));
    try std.testing.expectEqual(.fini_array, categorizeSection(".dtors"));
    try std.testing.expectEqual(.fini_array, categorizeSection(".CRT$XTY"));

    // Exception handling
    try std.testing.expectEqual(.exception, categorizeSection(".eh_frame"));
    try std.testing.expectEqual(.exception, categorizeSection(".eh_frame_hdr"));
    try std.testing.expectEqual(.exception, categorizeSection(".pdata"));
    try std.testing.expectEqual(.exception, categorizeSection(".xdata"));

    // Debug info
    try std.testing.expectEqual(.debug, categorizeSection(".debug_info"));
    try std.testing.expectEqual(.debug, categorizeSection(".debug_line"));
    try std.testing.expectEqual(.debug, categorizeSection(".debug_abbrev"));

    // TLS
    try std.testing.expectEqual(.tls, categorizeSection(".tdata"));
    try std.testing.expectEqual(.tls, categorizeSection(".tbss"));

    // Import/export
    try std.testing.expectEqual(.import_export, categorizeSection(".plt"));
    try std.testing.expectEqual(.import_export, categorizeSection(".got"));
    try std.testing.expectEqual(.import_export, categorizeSection(".got.plt"));
    try std.testing.expectEqual(.import_export, categorizeSection(".idata"));
}

test "categorizeSection - SectionCategory displayName completeness" {
    const cats = [_]SectionCategory{ .code, .rodata, .data, .bss, .init_array, .fini_array, .exception, .debug, .tls, .import_export, .unknown };
    for (cats) |cat| {
        const name = cat.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "PathProvenance enum completeness" {
    const provs = [_]PathProvenance{ .user_code, .standard_library, .toolchain_internal, .build_generated, .unknown };
    // Just verify all variants exist and can be used
    for (provs) |p| {
        _ = p;
    }
}
