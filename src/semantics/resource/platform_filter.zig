//! P12: Platform-specific filtering — Platform-aware symbol normalization.
//!
//! Provides platform-aware symbol normalization and confidence adjustment.
//! Rules here only affect origin/evidence/confidence — never suppress FFI
//! boundary issues.

const std = @import("std");

/// Supported platform kinds for symbol classification.
pub const PlatformKind = enum(u8) {
    unknown,
    macos,
    linux,
    windows,
    elf,
    mach_o,
    coff,
};

/// Platform-specific filtering rules for symbol normalization and confidence.
pub const PlatformFilter = struct {
    /// Normalize a symbol name for platform-independent comparison.
    /// Handles Mach-O leading underscores, Windows @@ mangling, etc.
    pub fn normalizeSymbol(sym: []const u8, platform: PlatformKind) []const u8 {
        // Mach-O: strip leading underscore (_main → main)
        if (platform == .macos or platform == .mach_o) {
            if (sym.len > 0 and sym[0] == '_') {
                return sym[1..];
            }
        }
        // Windows MSVC / COFF: strip @@ decoration (func@@YA -> func)
        if (platform == .windows or platform == .coff) {
            if (std.mem.indexOf(u8, sym, "@@")) |idx| {
                return sym[0..idx];
            }
        }
        return sym;
    }

    /// Get platform hint from symbol naming conventions.
    pub fn detectPlatformHint(sym: []const u8) ?PlatformKind {
        // Mach-O: symbols often start with _
        if (sym.len > 0 and sym[0] == '_') return .mach_o;
        // Windows: symbols contain @@ for stdcall/fastcall
        if (std.mem.indexOf(u8, sym, "@@") != null) return .coff;
        // ELF: no special prefix (default)
        return null;
    }

    /// Apply platform-specific confidence adjustment.
    /// Returns adjusted confidence (same or slightly lower than input).
    pub fn adjustConfidence(confidence: f32, is_cross_platform: bool, is_known_runtime: bool) f32 {
        var adj = confidence;
        if (is_cross_platform) adj -= 0.05;
        if (!is_known_runtime) adj -= 0.03;
        if (adj < 0.0) adj = 0.0;
        if (adj > 1.0) adj = 1.0;
        return adj;
    }
};
