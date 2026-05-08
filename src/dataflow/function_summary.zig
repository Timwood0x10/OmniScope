//! Function Summary for Inter-procedural Analysis
//!
//! This module provides function summary data structures for tracking
//! data flow across function boundaries. It enables precise tracking
//! of pointer ownership through function calls.
//!
//! Key concepts:
//! - Parameter flow: which parameters flow to return value
//! - Side effects: whether function allocates/frees memory
//! - Ownership transfer: whether function consumes/transfers ownership

const std = @import("std");

const Allocator = std.mem.Allocator;

/// Parameter flow direction
pub const ParamFlow = enum(u8) {
    /// Parameter does not flow anywhere
    none,
    /// Parameter flows to return value
    to_return,
    /// Parameter flows to another parameter (output param)
    to_param,
    /// Parameter flows to both return and another param
    to_both,
};

/// Function side effects
pub const SideEffects = packed struct {
    /// Function allocates memory
    allocates: bool,
    /// Function frees memory
    frees: bool,
    /// Function writes to memory through pointer
    writes_memory: bool,
    /// Function reads from memory through pointer
    reads_memory: bool,
    /// Function may throw exceptions
    may_throw: bool,
    /// Function has external side effects (I/O, etc.)
    external: bool,
};

/// Ownership behavior for a parameter
pub const OwnershipBehavior = enum(u8) {
    /// Function does not affect ownership
    none,
    /// Function consumes ownership (takes responsibility)
    consumes,
    /// Function transfers ownership to caller
    transfers,
    /// Function borrows (does not take ownership)
    borrows,
};

/// Summary of a function's behavior for inter-procedural analysis
pub const FunctionSummary = struct {
    /// Function name
    name: []const u8,
    /// Number of parameters
    param_count: u8,
    /// Parameter flow relationships
    /// Maps param_index -> ParamFlow
    param_flows: []ParamFlow,
    /// Side effects of the function
    side_effects: SideEffects,
    /// Ownership behavior for each parameter
    ownership: []OwnershipBehavior,
    /// Whether this function is a known allocator
    is_allocator: bool,
    /// Whether this function is a known deallocator
    is_deallocator: bool,
    /// Confidence level (0.0 - 1.0)
    confidence: f32,

    /// Create a new function summary
    pub fn init(
        allocator: Allocator,
        name: []const u8,
        param_count: u8,
    ) !FunctionSummary {
        const param_flows = try allocator.alloc(ParamFlow, param_count);
        errdefer allocator.free(param_flows);
        @memset(param_flows, .none);

        const ownership = try allocator.alloc(OwnershipBehavior, param_count);
        @memset(ownership, .none);

        return .{
            .name = name,
            .param_count = param_count,
            .param_flows = param_flows,
            .side_effects = .{
                .allocates = false,
                .frees = false,
                .writes_memory = false,
                .reads_memory = false,
                .may_throw = false,
                .external = false,
            },
            .ownership = ownership,
            .is_allocator = false,
            .is_deallocator = false,
            .confidence = 1.0,
        };
    }

    /// Free resources
    pub fn deinit(self: *FunctionSummary, allocator: Allocator) void {
        allocator.free(self.param_flows);
        allocator.free(self.ownership);
    }

    /// Set parameter flow
    pub fn setParamFlow(self: *FunctionSummary, param_idx: u8, flow: ParamFlow) void {
        if (param_idx < self.param_count) {
            self.param_flows[param_idx] = flow;
        }
    }

    /// Set ownership behavior for a parameter
    pub fn setOwnership(self: *FunctionSummary, param_idx: u8, behavior: OwnershipBehavior) void {
        if (param_idx < self.param_count) {
            self.ownership[param_idx] = behavior;
        }
    }

    /// Check if parameter flows to return
    pub fn paramFlowsToReturn(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.param_flows[param_idx] == .to_return or
            self.param_flows[param_idx] == .to_both;
    }

    /// Check if function consumes ownership of parameter
    pub fn consumesOwnership(self: *const FunctionSummary, param_idx: usize) bool {
        if (param_idx >= self.param_count) return false;
        return self.ownership[param_idx] == .consumes;
    }

    /// Check if function transfers ownership through return
    pub fn transfersOwnership(self: *const FunctionSummary) bool {
        return self.is_allocator;
    }
};

/// Registry of known function summaries
pub const SummaryRegistry = struct {
    /// Map of function name to summary
    summaries: std.StringHashMap(FunctionSummary),
    /// Allocator
    allocator: Allocator,

    /// Create a new summary registry
    pub fn init(allocator: Allocator) SummaryRegistry {
        return .{
            .summaries = std.StringHashMap(FunctionSummary).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *SummaryRegistry) void {
        var iter = self.summaries.iterator();
        while (iter.next()) |entry| {
            var summary = entry.value_ptr.*;
            summary.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.summaries.deinit();
    }

    /// Register a function summary
    pub fn register(self: *SummaryRegistry, summary: FunctionSummary) !void {
        // M2 FIX v2: Free old entry on duplicate registration to prevent memory leak.
        // Ownership semantics:
        //   - entry.key:     heap string copy made by register()'s dupe() → must free
        //   - entry.value:   FunctionSummary with internal heap arrays (param_flows, ownership)
        //                     allocated by FunctionSummary.init() → must deinit to free them
        // Only the key is explicitly freed here; the value's internal arrays are freed by deinit().
        if (self.summaries.fetchRemove(summary.name)) |entry| {
            var old_value = entry.value;
            old_value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }
        const name_copy = try self.allocator.dupe(u8, summary.name);
        errdefer self.allocator.free(name_copy);
        try self.summaries.put(name_copy, summary);
    }

    /// Look up a function summary by name
    pub fn lookup(self: *const SummaryRegistry, name: []const u8) ?FunctionSummary {
        return self.summaries.get(name);
    }

    /// Check if a function is known
    pub fn isKnown(self: *const SummaryRegistry, name: []const u8) bool {
        return self.summaries.contains(name);
    }

    /// Initialize with built-in summaries for common functions
    pub fn initBuiltins(self: *SummaryRegistry) !void {
        // malloc: allocates, transfers ownership
        var malloc_summary = try FunctionSummary.init(self.allocator, "malloc", 1);
        errdefer malloc_summary.deinit(self.allocator);
        malloc_summary.side_effects.allocates = true;
        malloc_summary.is_allocator = true;
        malloc_summary.confidence = 1.0;
        try self.register(malloc_summary);

        // free: frees, consumes ownership
        var free_summary = try FunctionSummary.init(self.allocator, "free", 1);
        errdefer free_summary.deinit(self.allocator);
        free_summary.side_effects.frees = true;
        free_summary.setOwnership(0, .consumes);
        free_summary.is_deallocator = true;
        free_summary.confidence = 1.0;
        try self.register(free_summary);

        // calloc: allocates, transfers ownership
        var calloc_summary = try FunctionSummary.init(self.allocator, "calloc", 2);
        errdefer calloc_summary.deinit(self.allocator);
        calloc_summary.side_effects.allocates = true;
        calloc_summary.is_allocator = true;
        calloc_summary.confidence = 1.0;
        try self.register(calloc_summary);

        // realloc: allocates and frees, consumes old, transfers new
        var realloc_summary = try FunctionSummary.init(self.allocator, "realloc", 2);
        errdefer realloc_summary.deinit(self.allocator);
        realloc_summary.side_effects.allocates = true;
        realloc_summary.side_effects.frees = true;
        realloc_summary.setOwnership(0, .consumes);
        realloc_summary.setParamFlow(0, .to_return);
        realloc_summary.is_allocator = true;
        realloc_summary.confidence = 1.0;
        try self.register(realloc_summary);

        // memcpy: writes memory
        var memcpy_summary = try FunctionSummary.init(self.allocator, "memcpy", 3);
        errdefer memcpy_summary.deinit(self.allocator);
        memcpy_summary.side_effects.writes_memory = true;
        memcpy_summary.setParamFlow(0, .to_return);
        memcpy_summary.confidence = 1.0;
        try self.register(memcpy_summary);

        // strcpy: writes memory, dangerous
        var strcpy_summary = try FunctionSummary.init(self.allocator, "strcpy", 2);
        errdefer strcpy_summary.deinit(self.allocator);
        strcpy_summary.side_effects.writes_memory = true;
        strcpy_summary.setParamFlow(0, .to_return);
        strcpy_summary.confidence = 1.0;
        try self.register(strcpy_summary);
    }
};

// Unit tests

test "ParamFlow enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ParamFlow.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ParamFlow.to_return));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ParamFlow.to_param));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ParamFlow.to_both));
}

test "SideEffects packed struct" {
    const effects = SideEffects{
        .allocates = true,
        .frees = false,
        .writes_memory = true,
        .reads_memory = true,
        .may_throw = false,
        .external = false,
    };
    try std.testing.expect(effects.allocates);
    try std.testing.expect(!effects.frees);
    try std.testing.expect(effects.writes_memory);
    try std.testing.expect(effects.reads_memory);
}

test "OwnershipBehavior enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipBehavior.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipBehavior.consumes));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipBehavior.transfers));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipBehavior.borrows));
}

test "FunctionSummary - init and deinit" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test_func", 3);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("test_func", summary.name);
    try std.testing.expectEqual(@as(u8, 3), summary.param_count);
    try std.testing.expectEqual(@as(usize, 3), summary.param_flows.len);
}

test "FunctionSummary - setParamFlow" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setParamFlow(0, .to_return);
    summary.setParamFlow(1, .to_param);

    try std.testing.expectEqual(ParamFlow.to_return, summary.param_flows[0]);
    try std.testing.expectEqual(ParamFlow.to_param, summary.param_flows[1]);
}

test "FunctionSummary - setOwnership" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setOwnership(0, .consumes);
    summary.setOwnership(1, .borrows);

    try std.testing.expectEqual(OwnershipBehavior.consumes, summary.ownership[0]);
    try std.testing.expectEqual(OwnershipBehavior.borrows, summary.ownership[1]);
}

test "FunctionSummary - paramFlowsToReturn" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 2);
    defer summary.deinit(std.testing.allocator);

    summary.setParamFlow(0, .to_return);
    summary.setParamFlow(1, .none);

    try std.testing.expect(summary.paramFlowsToReturn(0));
    try std.testing.expect(!summary.paramFlowsToReturn(1));
}

test "FunctionSummary - consumesOwnership" {
    var summary = try FunctionSummary.init(std.testing.allocator, "test", 1);
    defer summary.deinit(std.testing.allocator);

    summary.setOwnership(0, .consumes);

    try std.testing.expect(summary.consumesOwnership(0));
    try std.testing.expect(!summary.consumesOwnership(1)); // out of bounds
}

test "SummaryRegistry - init and deinit" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.summaries.count());
}

test "SummaryRegistry - register and lookup" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var summary = try FunctionSummary.init(std.testing.allocator, "my_func", 2);
    summary.setParamFlow(0, .to_return);
    try registry.register(summary);

    const found = registry.lookup("my_func");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(ParamFlow.to_return, found.?.param_flows[0]);
}

test "SummaryRegistry - initBuiltins" {
    var registry = SummaryRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.initBuiltins();

    try std.testing.expect(registry.isKnown("malloc"));
    try std.testing.expect(registry.isKnown("free"));
    try std.testing.expect(registry.isKnown("calloc"));
    try std.testing.expect(registry.isKnown("realloc"));
    try std.testing.expect(registry.isKnown("memcpy"));
    try std.testing.expect(registry.isKnown("strcpy"));

    const malloc = registry.lookup("malloc").?;
    try std.testing.expect(malloc.is_allocator);
    try std.testing.expect(malloc.side_effects.allocates);

    const free = registry.lookup("free").?;
    try std.testing.expect(free.is_deallocator);
    try std.testing.expect(free.side_effects.frees);
    try std.testing.expect(free.consumesOwnership(0));
}
