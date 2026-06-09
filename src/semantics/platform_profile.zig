//! Platform Profile Detection
//!
//! Parses LLVM module-level metadata to determine the target platform,
//! object format, and ABI characteristics. This information is used
//! to normalize platform-specific symbols, paths, and runtime patterns
//! before they enter the analysis pipeline.
//!
//! Design Principles (from todolist.md):
//! - Platform info is only a hint — cannot alone determine if a bug exists
//! - Safety first: unknown platform features default to unknown, keep analyzing
//! - Boundary priority: FFI export/import/cross-language edges never filtered by platform rules
//! - Normalize first, whitelist second: standardize symbols/paths/sections before language/surface/noise logic

const std = @import("std");
const log = std.log.scoped(.platform_profile);
const c = @import("../ir/llvm_raw.zig").c;

/// Target operating system / platform family.
pub const PlatformKind = enum {
    /// Apple macOS (including iOS, tvOS, watchOS — all use Mach-O)
    macos,
    /// Linux (glibc, musl, Alpine — all use ELF)
    linux,
    /// Windows (MSVC, MinGW — all use COFF/PE)
    windows,
    /// WebAssembly System Interface (uses wasm binary format)
    wasi,
    /// Unknown or unrecognizable platform
    unknown,

    pub fn displayName(self: PlatformKind) []const u8 {
        return switch (self) {
            .macos => "macOS",
            .linux => "Linux",
            .windows => "Windows",
            .wasi => "WASI",
            .unknown => "Unknown",
        };
    }
};

/// Windows ABI variant — distinguishes MinGW (GNU) from MSVC toolchain.
///
/// Both produce COFF object files but have critical differences:
///   - MinGW: GNU struct passing, Itanium C++ mangling (_ZN), plain names
///   - MSVC: Microsoft x64 calling convention, MSVC mangling (?name@@YA...)
pub const WindowsAbi = enum {
    /// MinGW-w64 / Cygwin (triple ends with -gnu)
    gnu,
    /// Microsoft Visual Studio (triple ends with -msvc)
    msvc,
    /// Unknown Windows toolchain
    unknown,

    pub fn displayName(self: WindowsAbi) []const u8 {
        return switch (self) {
            .gnu => "MinGW",
            .msvc => "MSVC",
            .unknown => "Unknown-WinABI",
        };
    }

    pub fn usesItaniumMangling(self: WindowsAbi) bool {
        return self == .gnu;
    }

    pub fn usesMsvcMangling(self: WindowsAbi) bool {
        return self == .msvc;
    }
};

/// Object file format (determines symbol decoration, section naming, linkage).
pub const ObjectFormat = enum {
    /// Mach-O (macOS / iOS / Darwin) — uses leading underscore for C symbols
    macho,
    /// ELF (Linux / BSD / Unix) — no leading underscore, uses .text/.rodata sections
    elf,
    /// COFF/PE (Windows) — uses decorated symbols (@N for stdcall), import thunks
    coff,
    /// WebAssembly binary format
    wasm,
    /// Unknown object format
    unknown,

    pub fn displayName(self: ObjectFormat) []const u8 {
        return switch (self) {
            .macho => "Mach-O",
            .elf => "ELF",
            .coff => "COFF",
            .wasm => "WASM",
            .unknown => "Unknown",
        };
    }
};

/// Complete platform profile extracted from LLVM module metadata.
///
/// Populated once during module initialization, cached in PassContext,
/// and read-only thereafter. All downstream normalization logic
/// references this struct instead of re-parsing the module.
pub const PlatformProfile = struct {
    /// Detected target OS/platform family.
    platform: PlatformKind,

    /// Detected object file format.
    object_format: ObjectFormat,

    /// Raw LLVM target triple string (e.g., "aarch64-apple-macosx15.7.3-unknown").
    /// Owned by caller (typically PassContext.allocator).
    target_triple: []const u8,

    /// Raw LLVM datalayout string (e.g., "e-m:o-p270:32:32...").
    /// Describes endianness, pointer size, alignment, address spaces.
    datalayout: []const u8,

    /// Architecture component extracted from target triple (e.g., "aarch64", "x86_64").
    /// Empty string if triple cannot be parsed.
    arch: []const u8,

    /// Vendor component from target triple (e.g., "apple", "pc", "unknown").
    vendor: []const u8,

    /// Windows ABI variant — only meaningful when platform == .windows.
    /// Distinguishes MinGW (GNU toolchain) from MSVC. Defaults to `.unknown`
    /// so non-Windows callers and minimal test fixtures can omit it.
    windows_abi: WindowsAbi = .unknown,

    /// Detect platform profile from LLVM module metadata.
    ///
    /// Reads `target triple` and `target datalayout` module-level attributes,
    /// then parses them into structured PlatformProfile. Falls back to
    /// `.unknown` for any field that cannot be determined.
    ///
    /// Arguments:
    ///   module     - LLVM module to analyze
    ///   allocator  - Memory allocator for owned strings (triple/datalayout/arch/vendor)
    ///
    /// Returns:
    ///   Fully populated PlatformProfile (may have .unknown fields)
    ///
    /// Errors:
    ///   OutOfMemory if allocator fails for string duplication
    pub fn detect(module: c.LLVMModuleRef, allocator: std.mem.Allocator) !PlatformProfile {
        // Step 1: Read raw target triple from LLVM module
        const triple_ptr = c.LLVMGetTarget(module);
        const triple_raw: []const u8 = if (@intFromPtr(triple_ptr) != 0)
            std.mem.span(triple_ptr)
        else
            "";

        // Step 2: Read raw datalayout from LLVM module
        const dl_ptr = c.LLVMGetDataLayout(module);
        const dl_raw: []const u8 = if (@intFromPtr(dl_ptr) != 0)
            std.mem.span(dl_ptr)
        else
            "";

        // Step 3: Duplicate strings into allocator-owned memory
        const triple = try allocator.dupe(u8, triple_raw);
        errdefer allocator.free(triple);

        const datalayout = try allocator.dupe(u8, dl_raw);
        errdefer allocator.free(datalayout);

        // Step 4: Parse platform kind from target triple
        const platform = parsePlatformKind(triple);

        // Step 5: Parse object format (can be inferred from platform)
        const object_format = parseObjectFormat(triple, platform);

        // Step 6: Extract architecture and vendor components
        const arch = extractArchComponent(triple, allocator);
        const vendor = extractVendorComponent(triple, allocator);

        // Step 7: Parse Windows ABI variant (if applicable)
        const win_abi = parseWindowsAbi(triple);

        log.debug("Platform detected: {s} ({s}) arch={s} vendor={s} win_abi={s}", .{
            platform.displayName(),
            object_format.displayName(),
            arch,
            vendor,
            win_abi.displayName(),
        });

        return PlatformProfile{
            .platform = platform,
            .object_format = object_format,
            .target_triple = triple,
            .datalayout = datalayout,
            .arch = arch,
            .vendor = vendor,
            .windows_abi = win_abi,
        };
    }

    /// Check if this profile indicates an Apple/Darwin platform (macOS/iOS/tvOS/watchOS).
    pub fn isAppleDarwin(self: *const PlatformProfile) bool {
        return self.platform == .macos;
    }

    /// Check if this profile indicates a Unix-like platform (macOS/Linux).
    pub fn isUnixLike(self: *const PlatformProfile) bool {
        return self.platform == .macos or self.platform == .linux;
    }

    /// Check if this profile uses Mach-O symbol decoration (leading underscore).
    pub fn usesMachoUnderscore(self: *const PlatformProfile) bool {
        return self.object_format == .macho;
    }

    /// Check if this profile uses COFF decorated symbols (stdcall/fastcall suffixes).
    pub fn usesCoffDecoration(self: *const PlatformProfile) bool {
        return self.object_format == .coff;
    }

    /// Free all allocator-owned strings in this profile.
    pub fn deinit(self: *PlatformProfile, allocator: std.mem.Allocator) void {
        allocator.free(self.target_triple);
        allocator.free(self.datalayout);
        allocator.free(self.arch);
        allocator.free(self.vendor);
        self.* = undefined;
    }
};

// ============================================================================
// Internal parsing helpers
// ============================================================================

/// Parse PlatformKind from LLVM target triple string.
///
/// Target triple format: `<arch>-<vendor>-<sys>-<abi>`
///
/// Examples:
///   - "aarch64-apple-macosx15.7.3-unknown" → .macos
///   - "x86_64-pc-linux-gnu" → .linux
///   - "x86_64-pc-windows-msvc" → .windows
///   - "wasm32-wasi" → .wasi
fn parsePlatformKind(triple: []const u8) PlatformKind {
    // Convert to lowercase for case-insensitive matching
    var lower_buf: [256]u8 = undefined;
    const lower = if (triple.len < lower_buf.len) blk: {
        for (triple, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z')
                @as(u8, ch + 32)
            else
                ch;
        }
        break :blk lower_buf[0..triple.len];
    } else triple; // Fallback: use original if too long

    // Check for macOS / Darwin patterns (including iOS, tvOS, watchOS - all Darwin family)
    if (std.mem.indexOf(u8, lower, "macos") != null or
        std.mem.indexOf(u8, lower, "darwin") != null or
        std.mem.indexOf(u8, lower, "ios") != null or
        std.mem.indexOf(u8, lower, "tvos") != null or
        std.mem.indexOf(u8, lower, "watchos") != null)
    {
        return .macos;
    }

    // Check for Linux patterns (includes android, freebsd, netbsd for ELF compatibility)
    if (std.mem.indexOf(u8, lower, "linux") != null or
        std.mem.indexOf(u8, lower, "android") != null or
        std.mem.indexOf(u8, lower, "freebsd") != null or
        std.mem.indexOf(u8, lower, "netbsd") != null)
    {
        return .linux;
    }

    // Check for Windows patterns
    if (std.mem.indexOf(u8, lower, "windows") != null or
        std.mem.indexOf(u8, lower, "win32") != null or
        std.mem.indexOf(u8, lower, "mingw") != null)
    {
        return .windows;
    }

    // Check for WASI
    if (std.mem.indexOf(u8, lower, "wasi") != null) {
        return .wasi;
    }

    return .unknown;
}

/// Parse ObjectFormat from target triple (or infer from platform).
///
/// Mapping:
///   - macOS/Darwin → .macho
///   - Linux/BSD/Android → .elf
///   - Windows/MinGW → .coff
///   - WASI → .wasm
fn parseObjectFormat(triple: []const u8, platform: PlatformKind) ObjectFormat {
    // If we already know the platform, infer the format
    if (platform != .unknown) {
        return switch (platform) {
            .macos => .macho,
            .linux => .elf,
            .windows => .coff,
            .wasi => .wasm,
            .unknown => .unknown,
        };
    }

    // Fallback: check triple for format-specific keywords
    var lower_buf: [256]u8 = undefined;
    const lower = if (triple.len < lower_buf.len) blk: {
        for (triple, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z')
                @as(u8, ch + 32)
            else
                ch;
        }
        break :blk lower_buf[0..triple.len];
    } else triple;

    if (std.mem.indexOf(u8, lower, "macos") != null or
        std.mem.indexOf(u8, lower, "darwin") != null or
        std.mem.indexOf(u8, lower, "ios") != null or
        std.mem.indexOf(u8, lower, "tvos") != null or
        std.mem.indexOf(u8, lower, "watchos") != null)
    {
        return .macho;
    }

    if (std.mem.indexOf(u8, lower, "linux") != null or
        std.mem.indexOf(u8, lower, "gnu") != null or
        std.mem.indexOf(u8, lower, "android") != null)
    {
        return .elf;
    }

    if (std.mem.indexOf(u8, lower, "windows") != null or
        std.mem.indexOf(u8, lower, "msvc") != null or
        std.mem.indexOf(u8, lower, "mingw") != null)
    {
        return .coff;
    }

    if (std.mem.indexOf(u8, lower, "wasi") != null) {
        return .wasm;
    }

    return .unknown;
}

/// Extract architecture component from target triple (first dash-separated segment).
fn extractArchComponent(triple: []const u8, allocator: std.mem.Allocator) []const u8 {
    const dash_idx = std.mem.indexOf(u8, triple, "-") orelse return "";
    return allocator.dupe(u8, triple[0..dash_idx]) catch "";
}

/// Extract vendor component from target triple (second dash-separated segment).
fn extractVendorComponent(triple: []const u8, allocator: std.mem.Allocator) []const u8 {
    const first_dash = std.mem.indexOf(u8, triple, "-") orelse return "";
    const rest = triple[first_dash + 1 ..];
    const second_dash = std.mem.indexOf(u8, rest, "-") orelse return "";
    return allocator.dupe(u8, rest[0..second_dash]) catch "";
}

/// Parse Windows ABI variant from target triple.
///
/// Detection rules:
///   - Triple ends with `-gnu` or contains `mingw` → MinGW (GNU ABI)
///   - Triple ends with `-msvc` or contains `msvc` → MSVC
///   - Otherwise → .unknown
///
/// Examples:
///   "x86_64-pc-windows-gnu"      → .gnu (MinGW)
///   "x86_64-w64-windows-gnu"     → .gnu (MinGW-w64)
///   "i686-pc-windows-msvc"       → .msvc
///   "x86_64-pc-windows-msvc"     → .msvc
fn parseWindowsAbi(triple: []const u8) WindowsAbi {
    var lower_buf: [256]u8 = undefined;
    const lower = if (triple.len < lower_buf.len) blk: {
        for (triple, 0..) |ch, i| {
            lower_buf[i] = if (ch >= 'A' and ch <= 'Z')
                @as(u8, ch + 32)
            else
                ch;
        }
        break :blk lower_buf[0..triple.len];
    } else triple;

    // Check for MinGW indicators: -gnu suffix or mingw in vendor
    // Only match if the triple contains "windows" to avoid false positives on Linux triples
    if (std.mem.indexOf(u8, lower, "mingw") != null) return .gnu;
    if (std.mem.indexOf(u8, lower, "windows") != null and std.mem.endsWith(u8, lower, "-gnu")) return .gnu;

    // Check for MSVC indicators: -msvc suffix
    if (std.mem.endsWith(u8, lower, "-msvc")) return .msvc;
    if (std.mem.indexOf(u8, lower, "-msvc") != null) return .msvc;

    return .unknown;
}

// ============================================================================
// Tests
// ============================================================================

test "PlatformKind displayName" {
    try std.testing.expectEqualStrings("macOS", PlatformKind.macos.displayName());
    try std.testing.expectEqualStrings("Linux", PlatformKind.linux.displayName());
    try std.testing.expectEqualStrings("Windows", PlatformKind.windows.displayName());
    try std.testing.expectEqualStrings("WASI", PlatformKind.wasi.displayName());
    try std.testing.expectEqualStrings("Unknown", PlatformKind.unknown.displayName());
}

test "ObjectFormat displayName" {
    try std.testing.expectEqualStrings("Mach-O", ObjectFormat.macho.displayName());
    try std.testing.expectEqualStrings("ELF", ObjectFormat.elf.displayName());
    try std.testing.expectEqualStrings("COFF", ObjectFormat.coff.displayName());
    try std.testing.expectEqualStrings("WASM", ObjectFormat.wasm.displayName());
    try std.testing.expectEqualStrings("Unknown", ObjectFormat.unknown.displayName());
}

test "parsePlatformKind - macOS variants" {
    try std.testing.expectEqual(.macos, parsePlatformKind("aarch64-apple-macosx15.7.3-unknown"));
    try std.testing.expectEqual(.macos, parsePlatformKind("arm64-apple-darwin23.0.0"));
    try std.testing.expectEqual(.macos, parsePlatformKind("x86_64-apple-macosx14.0"));
}

test "parsePlatformKind - Linux variants" {
    try std.testing.expectEqual(.linux, parsePlatformKind("x86_64-pc-linux-gnu"));
    try std.testing.expectEqual(.linux, parsePlatformKind("aarch64-unknown-linux-android"));
    try std.testing.expectEqual(.linux, parsePlatformKind("x86_64-unknown-freebsd14.0"));
}

test "parsePlatformKind - Windows variants" {
    try std.testing.expectEqual(.windows, parsePlatformKind("x86_64-pc-windows-msvc"));
    try std.testing.expectEqual(.windows, parsePlatformKind("i686-w64-mingw32"));
}

test "parsePlatformKind - WASI" {
    try std.testing.expectEqual(.wasi, parsePlatformKind("wasm32-wasi"));
    try std.testing.expectEqual(.wasi, parsePlatformKind("wasm64-wasi"));
}

test "parsePlatformKind - unknown" {
    try std.testing.expectEqual(.unknown, parsePlatformKind(""));
    try std.testing.expectEqual(.unknown, parsePlatformKind("invalid-triple"));
}

test "parseObjectFormat - inferred from platform" {
    try std.testing.expectEqual(.macho, parseObjectFormat("", .macos));
    try std.testing.expectEqual(.elf, parseObjectFormat("", .linux));
    try std.testing.expectEqual(.coff, parseObjectFormat("", .windows));
    try std.testing.expectEqual(.wasm, parseObjectFormat("", .wasi));
}

test "isAppleDarwin - macOS returns true" {
    var profile = PlatformProfile{
        .platform = .macos,
        .object_format = .macho,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };
    try std.testing.expect(profile.isAppleDarwin());
    try std.testing.expect(profile.isUnixLike());
    try std.testing.expect(profile.usesMachoUnderscore());
    try std.testing.expect(!profile.usesCoffDecoration());
}

test "isUnixLike - Linux returns true" {
    var profile = PlatformProfile{
        .platform = .linux,
        .object_format = .elf,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };
    try std.testing.expect(!profile.isAppleDarwin());
    try std.testing.expect(profile.isUnixLike());
    try std.testing.expect(!profile.usesMachoUnderscore());
    try std.testing.expect(!profile.usesCoffDecoration());
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "parsePlatformKind - empty string returns unknown" {
    try std.testing.expectEqual(.unknown, parsePlatformKind(""));
}

test "parsePlatformKind - garbage string returns unknown" {
    try std.testing.expectEqual(.unknown, parsePlatformKind("not-a-valid-triple"));
    try std.testing.expectEqual(.unknown, parsePlatformKind("!!!"));
    try std.testing.expectEqual(.unknown, parsePlatformKind("12345"));
}

test "parsePlatformKind - case insensitive" {
    // Uppercase should still match
    try std.testing.expectEqual(.macos, parsePlatformKind("MACOS"));
    try std.testing.expectEqual(.linux, parsePlatformKind("LINUX"));
    try std.testing.expectEqual(.windows, parsePlatformKind("WINDOWS"));
}

test "parsePlatformKind - mixed case" {
    try std.testing.expectEqual(.macos, parsePlatformKind("MacOS"));
    try std.testing.expectEqual(.linux, parsePlatformKind("Linux-gnu"));
    try std.testing.expectEqual(.windows, parsePlatformKind("Windows-msvc"));
}

test "parseObjectFormat - empty triple returns unknown" {
    try std.testing.expectEqual(.unknown, parseObjectFormat("", .unknown));
}

test "parsePlatformKind - iOS/tvOS/watchOS map to macos (Darwin family)" {
    try std.testing.expectEqual(.macos, parsePlatformKind("arm64-apple-ios15.0"));
    try std.testing.expectEqual(.macos, parsePlatformKind("arm64-apple-tvos14.0"));
    try std.testing.expectEqual(.macos, parsePlatformKind("arm64-apple-watchos8.0"));
}

test "parsePlatformKind - Android maps to linux (ELF family)" {
    try std.testing.expectEqual(.linux, parsePlatformKind("aarch64-linux-android29"));
    try std.testing.expectEqual(.linux, parsePlatformKind("x86_64-linux-android"));
}

test "isUnixLike - Windows is NOT Unix-like" {
    var profile = PlatformProfile{
        .platform = .windows,
        .object_format = .coff,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };
    try std.testing.expect(!profile.isUnixLike());
}

test "isUnixLike - WASI is NOT Unix-like" {
    var profile = PlatformProfile{
        .platform = .wasi,
        .object_format = .wasm,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
    };
    try std.testing.expect(!profile.isUnixLike());
}

test "isAppleDarwin - non-Darwin platforms return false" {
    var linux_profile = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    var win_profile = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    try std.testing.expect(!linux_profile.isAppleDarwin());
    try std.testing.expect(!win_profile.isAppleDarwin());
}

// ============================================================================
// Comprehensive Edge Case Tests
// ============================================================================

test "parsePlatformKind - FreeBSD/NetBSD map to linux (ELF family)" {
    try std.testing.expectEqual(.linux, parsePlatformKind("x86_64-pc-freebsd13.0"));
    try std.testing.expectEqual(.linux, parsePlatformKind("x86_64-pc-netbsd9.0"));
}

test "parsePlatformKind - long triple string" {
    const long_triple = "aarch64-unknown-linux-gnu5.4.0-clang-18.0.0-with-some-extra-info";
    try std.testing.expectEqual(.linux, parsePlatformKind(long_triple));
}

test "parsePlatformKind - minimal valid triples" {
    try std.testing.expectEqual(.linux, parsePlatformKind("linux"));
    try std.testing.expectEqual(.macos, parsePlatformKind("darwin"));
    try std.testing.expectEqual(.windows, parsePlatformKind("windows"));
}

test "parseObjectFormat - gnu keyword implies ELF" {
    try std.testing.expectEqual(.elf, parseObjectFormat("x86_64-pc-gnu", .unknown));
}

test "parseObjectFormat - msvc keyword implies COFF" {
    try std.testing.expectEqual(.coff, parseObjectFormat("x86_64-msvc", .unknown));
}

test "usesMachoUnderscore - only Mach-O returns true" {
    var macho_prof = PlatformProfile{ .platform = .macos, .object_format = .macho, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    var elf_prof = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    var coff_prof = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    var wasm_prof = PlatformProfile{ .platform = .wasi, .object_format = .wasm, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expect(macho_prof.usesMachoUnderscore());
    try std.testing.expect(!elf_prof.usesMachoUnderscore());
    try std.testing.expect(!coff_prof.usesMachoUnderscore());
    try std.testing.expect(!wasm_prof.usesMachoUnderscore());
}

test "usesCoffDecoration - only COFF returns true" {
    var coff_prof = PlatformProfile{ .platform = .windows, .object_format = .coff, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };
    var elf_prof = PlatformProfile{ .platform = .linux, .object_format = .elf, .target_triple = "", .datalayout = "", .arch = "", .vendor = "" };

    try std.testing.expect(coff_prof.usesCoffDecoration());
    try std.testing.expect(!elf_prof.usesCoffDecoration());
}

test "parsePlatformKind - embedded targets" {
    // arm-none-eabi is typically bare-metal/embedded with no OS
    try std.testing.expectEqual(.unknown, parsePlatformKind("arm-none-eabi"));
    try std.testing.expectEqual(.unknown, parsePlatformKind("riscv32-unknown-unknown"));
}

test "PlatformKind enum completeness" {
    // Ensure all variants have display names without panicking
    const kinds = [_]PlatformKind{ .macos, .linux, .windows, .wasi, .unknown };
    for (kinds) |kind| {
        const name = kind.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "ObjectFormat enum completeness" {
    const formats = [_]ObjectFormat{ .macho, .elf, .coff, .wasm, .unknown };
    for (formats) |fmt| {
        const name = fmt.displayName();
        try std.testing.expect(name.len > 0);
    }
}

// ============================================================================
// P0: Windows ABI Sub-type Tests
// ============================================================================

test "WindowsAbi enum completeness" {
    const abis = [_]WindowsAbi{ .gnu, .msvc, .unknown };
    for (abis) |abi| {
        const name = abi.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "parseWindowsAbi - MinGW variants" {
    try std.testing.expectEqual(.gnu, parseWindowsAbi("x86_64-pc-windows-gnu"));
    try std.testing.expectEqual(.gnu, parseWindowsAbi("x86_64-w64-mingw32"));
    try std.testing.expectEqual(.gnu, parseWindowsAbi("i686-pc-mingw32"));
    try std.testing.expectEqual(.gnu, parseWindowsAbi("aarch64-w64-mingw32-ucrt"));
}

test "parseWindowsAbi - MSVC variants" {
    try std.testing.expectEqual(.msvc, parseWindowsAbi("x86_64-pc-windows-msvc"));
    try std.testing.expectEqual(.msvc, parseWindowsAbi("i686-pc-windows-msvc"));
    try std.testing.expectEqual(.msvc, parseWindowsAbi("x86_64-pc-win32-msvc"));
}

test "parseWindowsAbi - non-Windows returns unknown" {
    try std.testing.expectEqual(.unknown, parseWindowsAbi("aarch64-apple-macosx"));
    try std.testing.expectEqual(.unknown, parseWindowsAbi("x86_64-pc-linux-gnu"));
    try std.testing.expectEqual(.unknown, parseWindowsAbi(""));
    try std.testing.expectEqual(.unknown, parseWindowsAbi("wasm32-wasi"));
}

test "parseWindowsAbi - case insensitive" {
    try std.testing.expectEqual(.gnu, parseWindowsAbi("x86_64-pc-windows-GNU"));
    try std.testing.expectEqual(.msvc, parseWindowsAbi("x86_64-pc-windows-MSVC"));
    try std.testing.expectEqual(.gnu, parseWindowsAbi("x86_64-w64-MingW32"));
}

test "WindowsAbi usesItaniumMangling / usesMsvcMangling" {
    try std.testing.expect(WindowsAbi.gnu.usesItaniumMangling());
    try std.testing.expect(!WindowsAbi.gnu.usesMsvcMangling());
    try std.testing.expect(!WindowsAbi.msvc.usesItaniumMangling());
    try std.testing.expect(WindowsAbi.msvc.usesMsvcMangling());
    try std.testing.expect(!WindowsAbi.unknown.usesItaniumMangling());
    try std.testing.expect(!WindowsAbi.unknown.usesMsvcMangling());
}
