//! Semantic Registry for FFI Boundary Analysis
//!
//! This module provides a knowledge base for FFI boundary function semantics.
//! It is NOT a simple "dangerous function blacklist" - instead, it captures
//! the semantic properties of functions that are relevant when crossing
//! language boundaries.
//!
//! Key insight: The same function has different risk levels depending on context:
//! - `strcpy` in pure C code = medium risk
//! - `strcpy` crossing Rust→C boundary = HIGH risk (length constraint broken, lifetime broken)
//!
//! Layers:
//! - Layer 1: FFI high-risk functions (C standard library)
//! - Layer 2: Rust ownership patterns (into_raw, from_raw, as_ptr)
//! - Layer 3: Go cgo allocator patterns
//! - Layer 4: Swift FFI patterns
//! - Layer 5: Zig Standard Library patterns
//! - Layer 6: C++ Standard Library patterns
//!
//! Additional modules:
//! - JNI functions
//! - Python C API functions
//! - POSIX I/O functions
//! - POSIX thread/signal/process management

const std = @import("std");
const types = @import("types.zig");

// Import language/function-specific registries
const layer1_reg = @import("layer1_reg.zig");
const layer2_reg = @import("layer2_reg.zig");
const layer3_reg = @import("layer3_reg.zig");
const layer4_reg = @import("layer4_reg.zig");
const layer5_reg = @import("layer5_reg.zig");
const layer6_reg = @import("layer6_reg.zig");
const jni_reg = @import("jni_reg.zig");
const python_c_api_reg = @import("python_c_api_reg.zig");
const posix_io_reg = @import("posix_io_reg.zig");
const posix_thread_reg = @import("posix_thread_reg.zig");
const dynamic_loading_reg = @import("dynamic_loading_reg.zig");

pub const RiskKind = types.RiskKind;
pub const Severity = types.Severity;
pub const MatchType = types.MatchType;
pub const FunctionSemantics = types.FunctionSemantics;

/// The semantic registry containing all known function semantics.
pub const SemanticRegistry = struct {
    /// Layer 1: FFI high-risk functions (C standard library)
    const layer1 = layer1_reg.layer1_functions;

    /// Layer 2: Rust ownership patterns
    const layer2 = layer2_reg.layer2_functions;

    /// Layer 3: Go cgo allocator patterns
    const layer3 = layer3_reg.layer3_functions;

    /// Layer 4: Swift FFI patterns
    const layer4 = layer4_reg.layer4_functions;

    /// Layer 5: Zig Standard Library patterns
    const layer5 = layer5_reg.layer5_functions;

    /// Layer 6: C++ Standard Library patterns
    const layer6 = layer6_reg.layer6_functions;

    /// JNI functions
    const jni = jni_reg.jni_functions;

    /// Python C API functions
    const python_c_api = python_c_api_reg.python_c_api_functions;

    /// POSIX I/O functions
    const file_io = posix_io_reg.file_io_functions;
    const network_io = posix_io_reg.network_io_functions;

    /// POSIX thread/signal/process management
    const signal_handler = posix_thread_reg.signal_handler_functions;
    const thread_mgmt = posix_thread_reg.thread_mgmt_functions;
    const process_mgmt = posix_thread_reg.process_mgmt_functions;

    /// Dynamic loading functions
    const dynamic_loading = dynamic_loading_reg.dynamic_loading_functions;

    /// Lookup function semantics by name.
    /// Searches all layers in order.
    pub fn lookup(func_name: []const u8) ?FunctionSemantics {
        for (layer1) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer2) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer3) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer4) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer5) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (layer6) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (jni) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (python_c_api) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (file_io) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (network_io) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (signal_handler) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (thread_mgmt) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (process_mgmt) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        for (dynamic_loading) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) return sem;
        }
        return null;
    }

    fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
        return switch (match_type) {
            .exact => std.mem.eql(u8, func_name, pattern),
            .contains => std.mem.indexOf(u8, func_name, pattern) != null,
            .suffix => std.mem.endsWith(u8, func_name, pattern),
        };
    }

    pub fn isKnown(func_name: []const u8) bool {
        return lookup(func_name) != null;
    }

    pub fn getRiskKind(func_name: []const u8) ?RiskKind {
        const sem = lookup(func_name) orelse return null;
        return sem.kind;
    }

    pub fn getSeverity(func_name: []const u8) ?Severity {
        const sem = lookup(func_name) orelse return null;
        return sem.severity;
    }

    pub fn consumesOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.consumes_ownership;
    }

    pub fn transfersOwnership(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.transfers_ownership;
    }

    pub fn requiresNullCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_null_check;
    }

    pub fn requiresTaintCheck(func_name: []const u8) bool {
        const sem = lookup(func_name) orelse return false;
        return sem.requires_taint_check;
    }

    pub fn getDescription(func_name: []const u8) ?[]const u8 {
        const sem = lookup(func_name) orelse return null;
        return sem.description;
    }

    pub fn layer1Count() usize {
        return layer1.len;
    }

    pub fn layer2Count() usize {
        return layer2.len;
    }

    pub fn layer3Count() usize {
        return layer3.len;
    }

    pub fn layer4Count() usize {
        return layer4.len;
    }

    pub fn layer5Count() usize {
        return layer5.len;
    }

    pub fn layer6Count() usize {
        return layer6.len;
    }

    pub fn totalCount() usize {
        return layer1.len + layer2.len + layer3.len + layer4.len + layer5.len + layer6.len +
            jni.len + python_c_api.len + file_io.len + network_io.len +
            signal_handler.len + thread_mgmt.len + process_mgmt.len + dynamic_loading.len;
    }

    // ========================================================================
    // Hook System (Phase 3)
    // ========================================================================

    /// Registered analysis hooks (comptime-initialized for zero runtime cost).
    var hooks: [MAX_HOOKS]?types.AnalysisHook = [_]?types.AnalysisHook{null} ** MAX_HOOKS;
    var hook_count: usize = 0;

    const MAX_HOOKS = 16;

    /// Register an analysis hook. Returns error if hook table is full.
    pub fn registerHook(hook: types.AnalysisHook) !void {
        if (hook_count >= MAX_HOOKS) return error.HookTableFull;
        hooks[hook_count] = hook;
        hook_count += 1;
    }

    /// Run all registered hooks against the given context.
    /// Stops at first hook that returns .issue_found or .suppressed.
    pub fn runHooks(ctx: *types.HookContext) types.HookResult {
        for (hooks[0..hook_count]) |opt_hook| {
            if (opt_hook) |hook| {
                const result = hook.run(ctx);
                if (result != .none) return result;
            }
        }
        return .none;
    }

    /// Get number of registered hooks.
    pub fn hookCount() usize {
        return hook_count;
    }
};

test "SemanticRegistry - RiskKind enum" {
    try std.testing.expectEqual(@as(usize, 20), @typeInfo(RiskKind).@"enum".fields.len);
}

test "SemanticRegistry - Severity enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Severity.low));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Severity.medium));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(Severity.high));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(Severity.critical));
}

test "SemanticRegistry - lookup exact match" {
    const sem = SemanticRegistry.lookup("malloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
    try std.testing.expectEqual(Severity.medium, sem.severity);
}

test "SemanticRegistry - lookup unknown function" {
    try std.testing.expect(SemanticRegistry.lookup("unknown_func") == null);
}

test "SemanticRegistry - isKnown" {
    try std.testing.expect(SemanticRegistry.isKnown("free"));
    try std.testing.expect(SemanticRegistry.isKnown("into_raw"));
    try std.testing.expect(!SemanticRegistry.isKnown("unknown_func"));
}

test "SemanticRegistry - getRiskKind" {
    try std.testing.expectEqual(RiskKind.command_exec, SemanticRegistry.getRiskKind("system").?);
    try std.testing.expectEqual(RiskKind.deallocator, SemanticRegistry.getRiskKind("free").?);
}

test "SemanticRegistry - getSeverity" {
    try std.testing.expectEqual(Severity.critical, SemanticRegistry.getSeverity("system").?);
    try std.testing.expectEqual(Severity.high, SemanticRegistry.getSeverity("free").?);
}

test "SemanticRegistry - totalCount" {
    try std.testing.expect(SemanticRegistry.totalCount() > 0);
}
