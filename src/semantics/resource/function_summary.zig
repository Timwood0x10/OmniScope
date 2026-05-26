//! Resource Function Summary — Unified callee semantics for all analysis passes.
//!
//! Replaces per-pass callee-name guessing with a single shared summary.
//! Every pass (memory_graph, ptr_lifetime, ffi_boundary, pointer_ownership)
//! reads from the same SummaryStore instead of independently classifying functions.
//!
//! Design goals:
//!   - Single source of truth: one lookup → consistent behavior across all passes.
//!   - Evidence trail: every summary carries source and confidence.
//!   - Unknown-safe: missing summary never causes crash or high-confidence FP.

const std = @import("std");

const effect_mod = @import("effect.zig");
pub const Effect = effect_mod.Effect;
pub const EffectSet = effect_mod.EffectSet;
pub const SummarySource = effect_mod.SummarySource;
pub const Confidence = effect_mod.Confidence;

const family = @import("family.zig");
pub const FamilyId = family.FamilyId;
pub const LookupContext = family.LookupContext;

// ============================================================================
// ResourceFunctionSummary — One summary per function
// ============================================================================

/// Complete semantic summary of a single function's resource behavior.
/// This is the shared data structure that all heavy passes read from.
pub const ResourceFunctionSummary = struct {
    /// Canonical function name (e.g., "malloc", "PyObject_New", "_Znwm").
    name: []const u8,
    /// Where this summary came from.
    source: SummarySource,
    /// Confidence [0.0, 1.0] in this summary's accuracy.
    confidence: f32,
    /// Set of all effects this function performs.
    effects: EffectSet,
    /// Which resource family this function operates on (if applicable).
    /// null = unknown or multi-family / N/A.
    family: ?FamilyId = null,
    /// Which parameter index is consumed/transferred/released (if applicable).
    /// null = not applicable or unknown.
    target_param_index: ?u8 = null,
    /// Whether this function is a known FFI boundary export/import.
    is_ffi_boundary: bool = false,
    /// Human-readable explanation of why this summary was assigned.
    evidence: ?[]const u8 = null,

    /// Check if this summary has a specific effect.
    pub fn hasEffect(self: *const ResourceFunctionSummary, effect: Effect) bool {
        return self.effects.has(effect);
    }

    /// Check if this summary is reliable enough for high-trust decisions.
    pub fn isHighConfidence(self: *const ResourceFunctionSummary) bool {
        return self.confidence >= Confidence.high;
    }

    /// Check if this summary is reliable enough for medium-trust decisions.
    pub fn isMediumConfidence(self: *const ResourceFunctionSummary) bool {
        return self.confidence >= Confidence.medium;
    }
};

// ============================================================================
// SummaryEntry — Internal storage format (name-keyed)
// ============================================================================

/// Internal entry in the SummaryStore hashmap.
/// Separates the key (name) from the value (summary) for efficient lookup.
const SummaryEntry = struct {
    summary: ResourceFunctionSummary,

    pub fn init(name: []const u8, source: SummarySource, confidence: f32) SummaryEntry {
        return .{
            .summary = .{
                .name = name,
                .source = source,
                .confidence = confidence,
                .effects = EffectSet.empty,
            },
        };
    }

    pub fn withEffect(self: *SummaryEntry, effect: Effect) void {
        self.summary.effects.add(effect);
    }

    pub fn withFamily(self: *SummaryEntry, fam: FamilyId) void {
        self.summary.family = fam;
    }

    pub fn withTargetParam(self: *SummaryEntry, idx: u8) void {
        self.summary.target_param_index = idx;
    }

    pub fn withEvidence(self: *SummaryEntry, ev: []const u8) void {
        self.summary.evidence = ev;
    }

    pub fn withFFIBoundary(self: *SummaryEntry) void {
        self.summary.is_ffi_boundary = true;
    }
};

// ============================================================================
// SummaryStore — Query API for all passes
// ============================================================================

/// Central store for function summaries. Initialized once at analysis start,
/// shared read-only by all passes during analysis.
pub const SummaryStore = struct {
    allocator: std.mem.Allocator,
    /// Map from canonical function name → summary entry.
    entries: std.StringHashMapUnmanaged(SummaryEntry),

    pub fn init(allocator: std.mem.Allocator) SummaryStore {
        return .{
            .allocator = allocator,
            .entries = .{},
        };
    }

    pub fn deinit(self: *SummaryStore) void {
        self.entries.deinit(self.allocator);
    }

    // ========================================================================
    // Query API — called by all passes
    // ========================================================================

    /// Look up summary by canonical function name.
    /// Returns null if no summary exists (safe default: treat as unknown).
    pub fn lookup(self: *const SummaryStore, name: []const u8) ?*const ResourceFunctionSummary {
        if (self.entries.get(name)) |entry| {
            return &entry.summary;
        }
        return null;
    }

    /// Check if a function has a specific effect.
    /// Convenience shorthand for `lookup(name).?.hasEffect(effect)`.
    pub fn hasEffect(self: *const SummaryStore, name: []const u8, effect: Effect) bool {
        if (self.lookup(name)) |summary| {
            return summary.hasEffect(effect);
        }
        return false;
    }

    /// Check if a function is a known resource acquirer (allocator).
    pub fn isAcquirer(self: *const SummaryStore, name: []const u8) bool {
        return self.hasEffect(name, .acquires) or self.hasEffect(name, .returns_owned);
    }

    /// Check if a function is a known resource releaser (deallocator).
    pub fn isReleaser(self: *const SummaryStore, name: []const u8) bool {
        return self.hasEffect(name, .releases) or
            self.hasEffect(name, .conditional_release) or
            self.hasEffect(name, .consumes_arg);
    }

    /// Check if a function is a known retain (refcount increment).
    pub fn isRetain(self: *const SummaryStore, name: []const u8) bool {
        return self.hasEffect(name, .retains);
    }

    /// Check if a function returns a borrowed pointer (not owned).
    pub fn returnsBorrowed(self: *const SummaryStore, name: []const u8) bool {
        return self.hasEffect(name, .returns_borrowed) or self.hasEffect(name, .borrows);
    }

    /// Get total number of registered summaries.
    pub fn count(self: *const SummaryStore) usize {
        return self.entries.count();
    }

    // ========================================================================
    // Registration API — called during init / model loading
    // ========================================================================

    /// Register a new summary entry. If the name already exists, updates
    /// only if the new source has equal or higher confidence.
    pub fn register(self: *SummaryStore, name: []const u8, source: SummarySource, confidence: f32) !void {
        const gop = try self.entries.getOrPut(self.allocator, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = SummaryEntry.init(name, source, confidence);
        } else {
            // Update only if new source is more confident
            if (confidence >= gop.value_ptr.summary.confidence) {
                gop.value_ptr.* = SummaryEntry.init(name, source, confidence);
            }
        }
    }

    /// Register with builder pattern for fluent setup.
    pub fn registerBuilder(self: *SummaryStore, name: []const u8, source: SummarySource, confidence: f32) !SummaryBuilder {
        try self.register(name, source, confidence);
        return SummaryBuilder{
            .store = self,
            .name = name,
        };
    }

    /// Iterate over all registered summaries.
    pub fn iterate(self: *const SummaryStore, context: anytype, comptime visitor_fn: fn (context: @TypeOf(context), summary: *const ResourceFunctionSummary) bool) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (!visitor_fn(context, &entry.value_ptr.summary)) break;
        }
    }
};

// ============================================================================
// SummaryBuilder — Fluent API for constructing summaries
// ============================================================================

/// Builder for registering summaries with multiple attributes.
/// Usage: try store.registerBuilder("malloc", .builtin_registry, 1.0)
///             .withFamily(.c_heap)
///             .withEffect(.acquires);
pub const SummaryBuilder = struct {
    store: *SummaryStore,
    name: []const u8,

    pub fn withEffect(self: SummaryBuilder, effect: Effect) SummaryBuilder {
        if (self.store.entries.get(self.name)) |entry| {
            const mutable = @constCast(entry);
            mutable.withEffect(effect);
        }
        return self;
    }

    pub fn withFamily(self: SummaryBuilder, fam: FamilyId) SummaryBuilder {
        if (self.store.entries.get(self.name)) |entry| {
            const mutable = @constCast(entry);
            mutable.withFamily(fam);
        }
        return self;
    }

    pub fn withTargetParam(self: SummaryBuilder, idx: u8) SummaryBuilder {
        if (self.store.entries.get(self.name)) |entry| {
            const mutable = @constCast(entry);
            mutable.withTargetParam(idx);
        }
        return self;
    }

    pub fn withEvidence(self: SummaryBuilder, ev: []const u8) SummaryBuilder {
        if (self.store.entries.get(self.name)) |entry| {
            const mutable = @constCast(entry);
            mutable.withEvidence(ev);
        }
        return self;
    }

    pub fn withFFIBoundary(self: SummaryBuilder) SummaryBuilder {
        if (self.store.entries.get(self.name)) |entry| {
            const mutable = @constCast(entry);
            mutable.withFFIBoundary();
        }
        return self;
    }
};
