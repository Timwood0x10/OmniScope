//! Origin Classifier — Three-Layer Function Origin Analysis
//!
//! Replaces the name-based whitelist approach in noise_filter.zig with
//! a provenance-based classification system that is:
//!   - Language-agnostic (works for Rust, C++, Zig, Go, Swift, Python)
//!   - Maintainable (no crate name whitelists to update)
//!   - Accurate (L1 + L2 + L3 layered with fallback)
//!
//! Layer 1 — Linkage Heuristic:  O(1) per function, uses LLVMGetLinkage + hasDebugInfo
//! Layer 2 — Debug Origin:       O(1) per function, uses DISubprogram → DIFile path
//! Layer 3 — CallGraph Reachability: O(V+E) one-time, uses CallSiteIndex BFS
//!
//! Pipeline position: after ZoneClassifier, before all analysis passes.
//! Output: PassContext.function_origin map consumed by all downstream passes.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const debug_info = @import("../ir/debug_info.zig");

// ============================================================================
// Public Types
// ============================================================================

/// Canonical function origin classification.
/// Shared across all passes via PassContext.function_origin.
pub const FunctionOrigin = enum(u8) {
    /// User-written code — always analyze.
    user,
    /// Third-party dependency crate — analyze but lower priority.
    dependency,
    /// Standard library — skip by default.
    stdlib,
    /// Compiler-generated glue (drop glue, shims, panic) — skip.
    generated,
    /// Language runtime internals — skip.
    runtime,
    /// Cannot determine — keep for analysis (safe default).
    unknown,

    pub fn toString(self: FunctionOrigin) []const u8 {
        return switch (self) {
            .user => "USER",
            .dependency => "DEPENDENCY",
            .stdlib => "STDLIB",
            .generated => "GENERATED",
            .runtime => "RUNTIME",
            .unknown => "UNKNOWN",
        };
    }

    /// Should functions of this origin be analyzed by default?
    pub fn shouldAnalyze(self: FunctionOrigin) bool {
        return switch (self) {
            .user, .dependency, .unknown => true,
            .stdlib, .generated, .runtime => false,
        };
    }
};

/// Intermediate result from a single classification layer.
/// Each layer produces hints; the final decision merges all layers.
pub const LayerHint = struct {
    origin: FunctionOrigin,
    confidence: enum(u8) { low, medium, high },
    reason: []const u8,
};

// ============================================================================
// Layer 1: Linkage Heuristic
// ============================================================================

/// Classify function origin from LLVM linkage type and debug info presence.
///
/// Compiler-generated functions (drop glue, panic helpers, monomorphized
/// internals) typically have internal/linkonce_odr linkage AND lack debug
/// info. User code almost always has debug info when compiled with -g.
///
/// This is the cheapest layer: O(1) field reads, zero instruction scanning.
pub fn classifyLinkage(func: c.LLVMValueRef) ?LayerHint {
    const linkage = c.LLVMGetLinkage(func);
    const has_dbg = hasDebugSubprogram(func);

    // Strong signal: internal linkage without debug info
    if ((linkage == c.LLVMInternalLinkage or
        linkage == c.LLVMPrivateLinkage) and !has_dbg)
    {
        return .{
            .origin = .generated,
            .confidence = .high,
            .reason = "internal/private linkage without debug info",
        };
    }

    // Strong signal: linkonce_odr without debug info (template instantiations,
    // generic monomorphizations from compiler)
    if (linkage == c.LLVMLinkOnceODRLinkage and !has_dbg) {
        return .{
            .origin = .generated,
            .confidence = .high,
            .reason = "linkonce_odr without debug info",
        };
    }

    // Medium signal: available_externally without debug info
    if (linkage == c.LLVMAvailableExternallyLinkage and !has_dbg) {
        return .{
            .origin = .generated,
            .confidence = .medium,
            .reason = "available_externally without debug info",
        };
    }

    // External linkage declarations are runtime/library boundaries
    if (c.LLVMIsDeclaration(func) != 0) {
        if (linkage == c.LLVMExternalLinkage) {
            return .{
                .origin = .runtime,
                .confidence = .low,
                .reason = "external declaration",
            };
        }
    }

    // No strong linkage signal — defer to Layer 2
    return null;
}

/// Check if a function has a DISubprogram attached (has debug info).
fn hasDebugSubprogram(func: c.LLVMValueRef) bool {
    const sp = c.LLVMGetSubprogram(func);
    return @intFromPtr(sp) != 0;
}

// ============================================================================
// Layer 2: Debug Origin (Source Path Classification)
// ============================================================================

/// Source provenance determined from DIFile path.
const SourceProvenance = enum {
    /// workspace/src/... — user-written code
    user_code,
    /// /rustc/<hash>/library/... — standard library
    stdlib,
    /// .cargo/registry/... — third-party dependency
    dependency,
    /// target/build/... — build-generated code
    build_generated,
    /// Could not determine — fallback
    unknown,
};

/// Classify function origin from DISubprogram → DIFile source path.
///
/// This replaces name-based whitelisting with provenance matching.
/// Rust stdlib always lives at /rustc/<hash>/library/ regardless of
/// version or project. C++ STL is at /include/c++/. No crate names needed.
pub fn classifyDebugOrigin(func: c.LLVMValueRef) ?LayerHint {
    const sp = c.LLVMGetSubprogram(func);
    if (@intFromPtr(sp) == 0) return null;

    const file_ref = c.LLVMDIScopeGetFile(sp);
    if (@intFromPtr(file_ref) == 0) return null;

    var dir_len: c_uint = 0;
    const dir_ptr = c.LLVMDIFileGetDirectory(file_ref, &dir_len);
    const max_path_len: c_uint = 8192;
    if (@intFromPtr(dir_ptr) == 0 or dir_len == 0 or dir_len > max_path_len) return null;
    const dir = dir_ptr[0..dir_len];

    var name_len: c_uint = 0;
    const name_ptr = c.LLVMDIFileGetFilename(file_ref, &name_len);
    if (@intFromPtr(name_ptr) == 0 or name_len == 0 or name_len > max_path_len) return null;
    const filename = name_ptr[0..name_len];

    // Build full path for classification
    // Use dir as the primary classification signal (it contains the provenance)
    const provenance = classifySourcePath(dir, filename);

    return switch (provenance) {
        .user_code => .{
            .origin = .user,
            .confidence = .high,
            .reason = "source path in workspace",
        },
        .stdlib => .{
            .origin = .stdlib,
            .confidence = .high,
            .reason = "source path in standard library",
        },
        .dependency => .{
            .origin = .dependency,
            .confidence = .high,
            .reason = "source path in dependency registry",
        },
        .build_generated => .{
            .origin = .generated,
            .confidence = .medium,
            .reason = "source path in build output",
        },
        .unknown => null,
    };
}

/// Classify a source path into provenance categories.
///
/// Language-agnostic: matches path structure, not crate names.
/// Rust:  /rustc/<hash>/library/    → stdlib
/// C++:   /include/c++/             → stdlib
/// Zig:   /lib/zig/std/             → stdlib
/// Go:    /usr/local/go/src/        → stdlib
/// Deps:  .cargo/registry/          → dependency
pub fn classifySourcePath(dir: []const u8, filename: []const u8) SourceProvenance {
    _ = filename;

    // Rust standard library (provenance: compiler toolchain path)
    if (std.mem.indexOf(u8, dir, "/rustc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/.rustup/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/rustlib/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/core/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/alloc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "library/std/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/libcore/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/liballoc/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/src/libstd/") != null) return .stdlib;

    // C++ standard library (provenance: system include path)
    if (std.mem.indexOf(u8, dir, "/include/c++/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/usr/include/c++/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "/lib/gcc/") != null) return .stdlib;

    // Zig standard library
    if (std.mem.indexOf(u8, dir, "/lib/zig/") != null) return .stdlib;
    if (std.mem.indexOf(u8, dir, "zig/lib/std/") != null) return .stdlib;

    // Go standard library
    if (std.mem.indexOf(u8, dir, "/go/src/") != null) return .stdlib;

    // Swift standard library
    if (std.mem.indexOf(u8, dir, "/swift/lib/") != null) return .stdlib;

    // Python standard library
    if (std.mem.indexOf(u8, dir, "/lib/python") != null) return .stdlib;

    // Third-party dependencies (provenance: package manager registry)
    if (std.mem.indexOf(u8, dir, ".cargo/registry/") != null) return .dependency;
    if (std.mem.indexOf(u8, dir, "cargo/registry/") != null) return .dependency;

    // Build-generated code
    if (std.mem.indexOf(u8, dir, "/target/build/") != null) return .build_generated;
    if (std.mem.indexOf(u8, dir, "/build/out/") != null) return .build_generated;

    // User code (workspace paths — anything that doesn't match above)
    // This is the default if path looks like a normal project path
    if (std.mem.indexOf(u8, dir, "/src/") != null) return .user_code;

    return .unknown;
}

// ============================================================================
// Layer 3: CallGraph Reachability (implemented in OriginClassifierPass)
// ============================================================================

/// The reachability analysis is performed by OriginClassifierPass.run()
/// which has access to PassContext.CallSiteIndex for BFS traversal.
/// This module provides the merge logic for combining all three layers.

// ============================================================================
// Three-Layer Merge
// ============================================================================

/// Merge classification hints from all three layers into a final decision.
///
/// Decision logic (from todo.md §6):
///   - L1=generated + L3=not_reachable → generated (skip)
///   - L2=stdlib     + L3=not_reachable → stdlib (skip)
///   - L2=generated  + L3=not_reachable → generated (skip)
///   - L3=reachable  → keep L2 result (user/dependency)
///   - else          → unknown (conservative: keep for analysis)
///
/// Reachability overrides: if a function is reachable from roots,
/// it is always kept regardless of L1/L2 hints.
pub fn mergeLayers(
    l1: ?LayerHint,
    l2: ?LayerHint,
    is_reachable: ?bool,
) FunctionOrigin {
    const reachable = is_reachable orelse true; // default: keep if unknown

    // L3 reachable → override any skip signal from L1/L2
    if (reachable) {
        // If L2 says user or dependency, trust it
        if (l2) |hint| {
            if (hint.origin == .user or hint.origin == .dependency) {
                return hint.origin;
            }
        }
        // Reachable but no strong L2 signal → user
        return .user;
    }

    // Not reachable — apply L1/L2 suppression signals
    if (l2) |hint| {
        if (hint.origin == .stdlib or hint.origin == .generated or hint.origin == .runtime) {
            return hint.origin;
        }
    }

    if (l1) |hint| {
        if (hint.origin == .generated or hint.origin == .runtime) {
            return hint.origin;
        }
    }

    // No strong signal either way → conservative keep
    return .unknown;
}

// ============================================================================
// Convenience: Full Classification (without L3)
// ============================================================================

/// Classify a single function using L1 + L2 layers only.
/// Used when callgraph reachability is not yet available (early pipeline).
pub fn classifyFunction(func: c.LLVMValueRef) FunctionOrigin {
    const l1 = classifyLinkage(func);
    const l2 = classifyDebugOrigin(func);

    // Without L3, assume reachable (conservative: keep for analysis)
    return mergeLayers(l1, l2, true);
}
