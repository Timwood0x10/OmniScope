//! Zone Classification — Type Definitions & Pattern Constants
//!
//! Extracted from zone_classifier.zig to reduce file size.
//! Shared types and pattern constants used by zone_classifier and other passes.

const std = @import("std");

const log = std.log.scoped(.zone_types);
const PatternRegistry = @import("../filter/pattern_registry.zig").PatternRegistry;

/// Zone classification for code regions.
pub const ZoneKind = enum(u8) {
    /// Safe zone - language guarantees apply.
    /// Skip or low priority analysis.
    safe,

    /// Unsafe zone - explicit escape from safety.
    /// High priority analysis.
    unsafe,

    /// FFI boundary - cross-language call.
    /// Critical analysis.
    ffi,

    /// Runtime internal - stdlib/runtime code.
    /// Skip analysis.
    runtime_internal,

    /// Unknown - needs classification.
    unknown,
};

/// Escape trigger for each language.
pub const EscapeTrigger = enum(u8) {
    // Rust escape triggers
    rust_unsafe_block,
    rust_unsafe_fn,
    rust_extern_c,
    rust_raw_pointer,
    rust_transmute,
    rust_maybe_uninit,
    rust_pin_misuse,
    rust_asm,

    // Zig escape triggers
    zig_ptr_cast,
    zig_int_to_ptr,
    zig_c_import,
    zig_extern_fn,
    zig_volatile_ptr,
    zig_packed_abi,

    // Go escape triggers
    go_cgo,
    go_unsafe_pointer,
    go_uintptr_tricks,

    // C++ escape triggers
    cpp_extern_c,
    cpp_reinterpret_cast,
    cpp_manual_alloc,
    cpp_thread_callback,

    // Generic
    unknown,
};

// Zone pattern arrays — delegated to PatternRegistry (single source of truth).
// See: src/filter/pattern_registry.zig
// These aliases preserve backward compatibility for callers that import
// zone_types.RUST_SAFE_PATTERNS, etc.

pub const RUST_SAFE_PATTERNS = PatternRegistry.rust_safe_patterns;
pub const RUST_ESCAPE_PATTERNS = PatternRegistry.rust_escape_patterns;
pub const ZIG_SAFE_PATTERNS = PatternRegistry.zig_safe_patterns;
pub const ZIG_ESCAPE_PATTERNS = PatternRegistry.zig_escape_patterns;
pub const GO_SAFE_PATTERNS = PatternRegistry.go_safe_patterns;
pub const GO_ESCAPE_PATTERNS = PatternRegistry.go_escape_patterns;
pub const CPP_SAFE_PATTERNS = PatternRegistry.cpp_safe_patterns;
pub const CPP_ESCAPE_PATTERNS = PatternRegistry.cpp_escape_patterns;
pub const C_ESCAPE_PATTERNS = PatternRegistry.c_escape_patterns;

/// Statistics for zone classification.
pub const ZoneStats = struct {
    safe_count: u32 = 0,
    unsafe_count: u32 = 0,
    ffi_count: u32 = 0,
    runtime_count: u32 = 0,
    unknown_count: u32 = 0,

    pub fn record(self: *ZoneStats, zone: ZoneKind) void {
        switch (zone) {
            .safe => self.safe_count += 1,
            .unsafe => self.unsafe_count += 1,
            .ffi => self.ffi_count += 1,
            .runtime_internal => self.runtime_count += 1,
            .unknown => self.unknown_count += 1,
        }
    }

    pub fn total(self: ZoneStats) u32 {
        return self.safe_count + self.unsafe_count + self.ffi_count + self.runtime_count + self.unknown_count;
    }

    pub fn skipRatio(self: ZoneStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.safe_count + self.runtime_count)) / @as(f64, @floatFromInt(t));
    }
};
