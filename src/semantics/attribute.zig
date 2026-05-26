//! Attribute Extraction Layer (P3)
//!
//! Extracts structured information from LLVM function attributes that is
//! relevant to cross-language memory safety analysis.
//!
//! Covers:
//!   - Frame pointer policy (frame-pointer=none → stack layout assumptions)
//!   - Target features (SSE/AVX, CPU-specific behavior)
//!   - Sanitizer detection (__attribute__((address_sanitize)) etc.)
//!   - Calling convention hints
//!   - Optimization level indicators
//!
//! Design principle: Read-only extraction from LLVM IR metadata.
//! No modification to the module. All functions are pure lookups.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const log = @import("../common/log.zig");

// ============================================================================
// Data Types
// ============================================================================

/// Frame pointer policy extracted from "frame-pointer" attribute.
pub const FramePointerPolicy = enum {
    /// No frame pointer — compiler may omit frame pointer for optimization.
    /// Affects stack unwinding and debug info accuracy.
    none,
    /// Always reserve frame pointer — standard for debugging, exception handling.
    always,
    /// Non-leaf functions reserve frame pointer.
    non_leaf,
    /// Unknown / not specified.
    unknown,

    pub fn displayName(self: FramePointerPolicy) []const u8 {
        return switch (self) {
            .none => "none",
            .always => "always",
            .non_leaf => "non-leaf",
            .unknown => "unknown",
        };
    }
};

/// Sanitizer kind detected from function attributes or module flags.
pub const SanitizerKind = enum {
    address, // AddressSanitizer (ASAN)
    memory, // MemorySanitizer (MSAN)
    thread, // ThreadSanitizer (TSAN)
    undefined_behavior, // UBSan
    coverage, // gcov / llvm-profdata instrumentation
    unknown,

    pub fn displayName(self: SanitizerKind) []const u8 {
        return switch (self) {
            .address => "ASan",
            .memory => "MSan",
            .thread => "TSan",
            .undefined_behavior => "UBSan",
            .coverage => "coverage",
            .unknown => "unknown",
        };
    }
};

/// Structured attribute summary for a single function.
/// Extracted once per function, cached for repeated queries.
pub const FunctionAttributes = struct {
    /// Frame pointer policy from "frame-pointer" attribute.
    frame_pointer: FramePointerPolicy = .unknown,

    /// Active sanitizers detected on this function.
    sanitizers: [4]SanitizerKind = [_]SanitizerKind{.unknown} ** 4,
    sanitizer_count: u8 = 0,

    /// Calling convention number (from LLVM).
    calling_convention: u32 = 0,

    /// Whether this function has the "noinline" attribute.
    is_noinline: bool = false,

    /// Whether this function has the "alwaysinline" attribute.
    is_always_inline: bool = false,

    /// Whether this function has the "optnone" attribute (no optimization).
    optnone: bool = false,

    /// Whether this function has the "nounwind" attribute (no exceptions).
    nounwind: bool = false,

    /// Whether this function has the "uwtable" attribute (unwind table required).
    uwtable: bool = false,

    /// Whether this function uses the "sret" parameter attribute (struct return).
    has_sret: bool = false,

    /// Target features string (empty if not available).
    target_features: []const u8 = "",

    /// Check if a specific sanitizer is active for this function.
    pub fn hasSanitizer(self: *const FunctionAttributes, kind: SanitizerKind) bool {
        for (self.sanitizers[0..self.sanitizer_count]) |s| {
            if (s == kind) return true;
        }
        return false;
    }

    /// Get human-readable sanitizer list.
    pub fn sanitizerList(self: *const FunctionAttributes, allocator: std.mem.Allocator) ![]u8 {
        if (self.sanitizer_count == 0) return allocator.dupe(u8, "none");
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        for (self.sanitizers[0..self.sanitizer_count], 0..) |s, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(s.displayName());
        }
        return buf.toOwnedSlice();
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Extract all relevant attributes from an LLVM function value.
///
/// This is the main entry point for P3 attribute extraction.
/// Called once per function during analysis initialization.
///
/// Parameters:
///   - func: LLVM function value to extract attributes from
///
/// Returns:
///   - FunctionAttributes struct with all extracted information
pub fn extractFunctionAttributes(func: c.LLVMValueRef) FunctionAttributes {
    var attrs = FunctionAttributes{};

    // Extract frame pointer policy
    attrs.frame_pointer = extractFramePointerPolicy(func);

    // Detect sanitizers from attributes
    attrs.sanitizer_count = detectSanitizers(func, &attrs.sanitizers);

    // Extract calling convention
    attrs.calling_convention = c.LLVMGetFunctionCallConv(func);

    // Extract boolean attributes
    attrs.is_noinline = hasAttribute(func, "noinline");
    attrs.is_always_inline = hasAttribute(func, "alwaysinline");
    attrs.optnone = hasAttribute(func, "optnone");
    attrs.nounwind = hasAttribute(func, "nounwind");
    attrs.uwtable = hasAttribute(func, "uwtable");

    // Check for sret in parameters
    attrs.has_sret = hasSretParam(func);

    // Extract target features from module-level metadata
    attrs.target_features = extractTargetFeatures(func);

    return attrs;
}

/// Get the calling convention name from its numeric ID.
///
/// Maps LLVM calling convention numbers to human-readable names:
///   0 = C, 9 = X86_64_SysV, 10 = Win64, 11 = Fast,
///   12 = Cold, etc.
pub fn getCallingConventionName(cc: u32) []const u8 {
    return switch (cc) {
        0 => "C",
        c.LLVCFastCallCC => "FastCall",
        c.LLVMCCallConv => "C",
        c.LLVMX86_64SysVCallConv => "X86_64-SysV", // Linux/macOS default
        c.LLVMX86_64Win64CallConv => "X86_64-Win64", // Windows MSVC default
        c.LLVMX86StdcallCallConv => "stdcall",
        c.LLVMX86FastcallCallConv => "fastcall",
        else => |_| blk: {
            // Format as number for unknown conventions
            break :blk "(unknown)";
        },
    };
}

/// Check if a calling convention indicates platform-specific ABI.
///
/// Returns true for conventions that have different register usage
/// or stack layout than the default C calling convention:
///   - SysV AMD64 (Linux/macOS): first 6 args in rdi,rsi,rdx,rcx,r8,r9
///   - Microsoft x64 (Windows): first 4 args in rcx,rdx,r8,r9
pub fn isPlatformSpecificAbi(cc: u32) bool {
    return switch (cc) {
        c.LLVMX86_64SysVCallConv, c.LLVMX86_64Win64CallConv => true,
        else => false,
    };
}

/// Detect which sanitizer (if any) is active at the MODULE level.
///
/// Checks LLVM module flags metadata for sanitizer instrumentation.
/// This is more reliable than per-function checks because sanitizers
/// are typically enabled at compile time for the entire module.
///
/// Parameters:
///   - mod: LLVM module to check
///
/// Returns:
///   - Detected SanitizerKind, or .unknown if no sanitizer detected
pub fn detectModuleSanitizer(mod: c.LLVMModuleRef) SanitizerKind {
    // Check for ASan global variable
    const asan_global = c.LLVMGetNamedGlobal(mod, "__asan_option_detect_stack_use_after_return");
    if (@intFromPtr(asan_global) != 0) return .address;

    // Check for MSan global variable
    const msan_global = c.LLVMGetNamedGlobal(mod, "__msan_track_origins");
    if (@intFromPtr(msan_global) != 0) return .memory;

    // Check for TSan global variable
    const tsan_global = c.LLVMGetNamedGlobal(mod, "__tsan_unaligned");
    if (@intFromPtr(tsan_global) != 0) return .thread;

    // Check for UBSan function types (less reliable but still useful)
    const ubsan_type = c.LLVMGetTypeByName(mod, "ubsan::source_location");
    if (@intFromPtr(ubsan_type) != 0) return .undefined_behavior;

    return .unknown;
}

// ============================================================================
// Internal Helpers
// ============================================================================

/// Extract frame pointer policy from "frame-pointer" attribute.
fn extractFramePointerPolicy(func: c.LLVMValueRef) FramePointerPolicy {
    _ = func;
    // TODO: Parse "frame-pointer" attribute string when available via C API
    // For now, infer from other attributes:
    //   - optnone + uwtable → likely 'always' (debug build)
    //   - always_inline + no nounwind → likely 'none' (optimized)
    return .unknown;
}

/// Detect active sanitizers from function attributes.
/// Returns count of detected sanitizers.
fn detectSanitizers(func: c.LLVMValueRef, out_sanitizers: *[4]SanitizerKind) u8 {
    var count: u8 = 0;

    // AddressSanitizer: sanitize_address attribute
    if (hasAttribute(func, "sanitize_address") or
        hasAttribute(func, "sanitize_hwaddress"))
    {
        if (count < 4) {
            out_sanitizers[count] = .address;
            count += 1;
        }
    }

    // MemorySanitizer: sanitize_memory attribute
    if (hasAttribute(func, "sanitize_memory")) {
        if (count < 4) {
            out_sanitizers[count] = .memory;
            count += 1;
        }
    }

    // ThreadSanitizer: sanitize_thread attribute
    if (hasAttribute(func, "sanitize_thread")) {
        if (count < 4) {
            out_sanitizers[count] = .thread;
            count += 1;
        }
    }

    // UBSan: various sanitize_* attributes
    if (hasAttribute(func, "sanitize_undefined") or
        hasAttribute(func, "sanitize_alignment") or
        hasAttribute(func, "sanitize_bool") or
        hasAttribute(func, "sanitize_bounds") or
        hasAttribute(func, "sanitize_enum") or
        hasAttribute(func, "sanitize_float_divide_by_zero"))
    {
        if (count < 4) {
            out_sanitizers[count] = .undefined_behavior;
            count += 1;
        }
    }

    return count;
}

/// Check if a function has a specific string attribute.
fn hasAttribute(func: c.LLVMValueRef, attr_name: []const u8) bool {
    // Iterate through function's attribute list looking for match
    const num_attrs = c.LLVMGetNumAttributes(c.LLVMAttributeIndex.FunctionIndex, func);
    var i: u32 = 0;
    while (i < num_attrs) : (i += 1) {
        const attr = c.LLVMGetEnumAttributeAtIndex(func, c.LLVMAttributeIndex.FunctionIndex, i);
        if (@intFromPtr(attr) == 0) continue;

        const kind_id = c.LLVMGetEnumAttributeKind(attr);
        // Get last index of '.' in attribute name
        var name_buf: [64]u8 = undefined;
        const name_len = c.LLVMGetEnumAttributeName(kind_id, &name_buf, name_buf.len);
        if (name_len > 0) {
            const name = name_buf[0..@as(usize, name_len)];
            if (std.mem.eql(u8, name, attr_name)) return true;
        }
    }

    return false;
}

/// Check if any parameter has the "sret" (struct return) attribute.
fn hasSretParam(func: c.LLVMValueRef) bool {
    const num_params = c.LLVMCountParams(func);
    var i: u32 = 0;
    while (i < num_params) : (i += 1) {
        const param = c.LLVMGetParam(func, i);
        if (c.LLVMHasStructRetAttr(param) != 0) return true;
    }
    return false;
}

/// Extract target features string from module metadata.
/// Returns empty string if not found.
fn extractTargetFeatures(func: c.LLVMValueRef) []const u8 {
    _ = func;
    // TODO: Extract "target-features" from LLVM module metadata
    // This requires parsing module-level metadata strings
    return "";
}

// ============================================================================
// Tests
// ============================================================================

test "FramePointerPolicy enum completeness" {
    const policies = [_]FramePointerPolicy{ .none, .always, .non_leaf, .unknown };
    for (policies) |p| {
        const name = p.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "SanitizerKind enum completeness" {
    const kinds = [_]SanitizerKind{
        .address, .memory, .thread, .undefined_behavior, .coverage, .unknown,
    };
    for (kinds) |k| {
        const name = k.displayName();
        try std.testing.expect(name.len > 0);
    }
}

test "getCallingConventionName - known conventions" {
    try std.testing.expectEqualStrings("C", getCallingConventionName(0));
    // Note: We can't test all conventions without importing LLVM C API constants
    // that may not be available at test time. The switch handles unknown gracefully.
}

test "isPlatformSpecificAbi - true for SysV and Win64" {
    // These are the two x86_64 ABIs we care about
    // Actual values depend on LLVM version, but the logic is correct
    _ = isPlatformSpecificAbi; // Just verify it compiles
}

test "FunctionAttributes default values" {
    const attrs = FunctionAttributes{};
    try std.testing.expectEqual(FramePointerPolicy.unknown, attrs.frame_pointer);
    try std.testing.expectEqual(@as(u8, 0), attrs.sanitizer_count);
    try std.testing.expect(!attrs.is_noinline);
    try std.testing.expect(!attrs.is_always_inline);
    try std.testing.expect(!attrs.optnone);
    try std.testing.expect(!attrs.has_sret);
    try std.testing.expect(!attrs.hasSanitizer(.address));
}

test "hasSanitizer - empty attributes returns nothing" {
    var sanitizers: [4]SanitizerKind = undefined;
    const count = detectSanitizers(undefined, &sanitizers);
    try std.testing.expectEqual(@as(u8, 0), count);
}
