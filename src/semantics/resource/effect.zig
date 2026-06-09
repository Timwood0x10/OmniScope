//! Effect — Semantic action classification for resource operations.
//!
//! Defines what a function does to resource ownership: acquire, release,
//! retain, borrow, transfer, escape, etc. This is the shared vocabulary
//! that replaces per-pass callee-name guessing.
//!
//! All heavy passes (memory_graph, ptr_lifetime, ffi_boundary) read from
//! the same Effect set rather than each maintaining their own classifier.

const std = @import("std");

const family = @import("family.zig");
pub const FamilyId = family.FamilyId;
pub const ResourceOpKind = family.ResourceOpKind;

// ============================================================================
// Effect — What does this function do to a resource?
// ============================================================================

/// Semantic effect of a function call on resource ownership.
/// Each effect describes ONE action on ONE resource. A function may have
/// multiple effects (e.g., "acquires + returns_owned" or "releases arg0").
///
/// Effects are composable: a function's full behavior is the set of its
/// individual effects. Passes query specific effect kinds they care about.
pub const Effect = enum(u8) {
    /// Allocates new resource and returns owned pointer to caller.
    /// Examples: malloc, PyObject_New, operator new.
    acquires,

    /// Releases/frees a resource passed as argument.
    /// Examples: free, PyObject_Del, operator delete.
    releases,

    /// Increments reference count without taking ownership.
    /// The resource is NOT freed when the caller is done with it.
    /// Examples: Py_INCREF, CFRetain, ARC.retain.
    retains,

    /// Borrows pointer without ownership change.
    /// Caller must not free; owner remains responsible.
    /// Examples: as_ptr, slice.as_ptr(), &ref.field.
    borrows,

    /// Transfers ownership from argument to return value or another output.
    /// The caller of THIS function receives ownership.
    /// Examples: Box::into_raw, std::move wrapper.
    transfers,

    /// Returns an owned resource to the caller (allocates internally).
    /// Distinct from .acquires: the allocation happens inside the callee,
    /// not via a direct allocator call visible at the call site.
    /// Examples: PyLong_FromLong, PyTuple_New, strdup.
    returns_owned,

    /// Returns a borrowed pointer (no ownership transfer).
    /// Caller must not free the returned value.
    /// Examples: PyList_GetItem, C string literal access.
    returns_borrowed,

    /// Consumes (takes ownership of) an argument pointer.
    /// The function becomes responsible for freeing it.
    /// Examples: cJSON_Delete, xmlFreeDoc.
    consumes_arg,

    /// Stores an argument pointer into an owner object's field.
    /// The owner's destructor will eventually release it.
    /// Examples: PyList_SetItem, vector.push_back(value).
    stores_arg_to_owner,

    /// Stores an argument pointer into a global/static variable.
    /// Lifetime extends to process exit unless explicitly cleaned up.
    /// Examples: global_cache[key] = value, singleton registration.
    stores_arg_to_global,

    /// Initializes an output parameter (pointer-to-pointer).
    /// Writes an owned or borrowed pointer through *out_param.
    /// Examples: PyObject_GetBuffer, GetModuleHandleEx.
    initializes_out_param,

    /// Escapes a pointer to a callback/closure.
    /// The pointer may be used after this function returns — lifetime risk.
    /// Examples: pthread_create, register_callback(handler).
    escapes_to_callback,

    /// Conditionally releases based on reference count.
    /// May or may not actually free; depends on runtime refcount.
    /// Examples: Py_DECREF, Arc::drop, CFRelease.
    conditional_release,

    /// No known resource effect on any argument or return value.
    none,
};

// ============================================================================
// EffectSet — Composable set of effects for a single function
// ============================================================================

/// A compact set of effects that a function may perform.
/// Uses a bitset for efficient membership testing on hot paths.
pub const EffectSet = packed struct(u16) {
    acquires: bool = false,
    releases: bool = false,
    retains: bool = false,
    borrows: bool = false,
    transfers: bool = false,
    returns_owned: bool = false,
    returns_borrowed: bool = false,
    consumes_arg: bool = false,
    stores_arg_to_owner: bool = false,
    stores_arg_to_global: bool = false,
    initializes_out_param: bool = false,
    escapes_to_callback: bool = false,
    conditional_release: bool = false,
    _padding: u3 = 0,

    pub const empty: EffectSet = @bitCast(@as(u16, 0));

    pub fn add(self: *EffectSet, effect: Effect) void {
        switch (effect) {
            .acquires => self.acquires = true,
            .releases => self.releases = true,
            .retains => self.retains = true,
            .borrows => self.borrows = true,
            .transfers => self.transfers = true,
            .returns_owned => self.returns_owned = true,
            .returns_borrowed => self.returns_borrowed = true,
            .consumes_arg => self.consumes_arg = true,
            .stores_arg_to_owner => self.stores_arg_to_owner = true,
            .stores_arg_to_global => self.stores_arg_to_global = true,
            .initializes_out_param => self.initializes_out_param = true,
            .escapes_to_callback => self.escapes_to_callback = true,
            .conditional_release => self.conditional_release = true,
            .none => {},
        }
    }

    pub fn has(self: *const EffectSet, effect: Effect) bool {
        return switch (effect) {
            .acquires => self.acquires,
            .releases => self.releases,
            .retains => self.retains,
            .borrows => self.borrows,
            .transfers => self.transfers,
            .returns_owned => self.returns_owned,
            .returns_borrowed => self.returns_borrowed,
            .consumes_arg => self.consumes_arg,
            .stores_arg_to_owner => self.stores_arg_to_owner,
            .stores_arg_to_global => self.stores_arg_to_global,
            .initializes_out_param => self.initializes_out_param,
            .escapes_to_callback => self.escapes_to_callback,
            .conditional_release => self.conditional_release,
            .none => false,
        };
    }

    pub fn isEmpty(self: *const EffectSet) bool {
        return @as(u16, @bitCast(self.*)) == 0;
    }

    pub fn count(self: *const EffectSet) u32 {
        var c: u32 = 0;
        if (self.acquires) c += 1;
        if (self.releases) c += 1;
        if (self.retains) c += 1;
        if (self.borrows) c += 1;
        if (self.transfers) c += 1;
        if (self.returns_owned) c += 1;
        if (self.returns_borrowed) c += 1;
        if (self.consumes_arg) c += 1;
        if (self.stores_arg_to_owner) c += 1;
        if (self.stores_arg_to_global) c += 1;
        if (self.initializes_out_param) c += 1;
        if (self.escapes_to_callback) c += 1;
        if (self.conditional_release) c += 1;
        return c;
    }
};

// ============================================================================
// SummarySource — Where did this summary come from?
// ============================================================================

/// Provenance of a function summary entry. Every summary carries evidence
/// so that downstream passes can weigh confidence appropriately.
pub const SummarySource = enum(u8) {
    /// Auto-generated from builtin ResourceFamilyRegistry entries.
    /// Highest confidence for well-known allocators/deallocators.
    builtin_registry,
    /// Inferred from structural IR patterns (destructor shape, bridge helper, etc.).
    structural_inference,
    /// Provided by user via --semantic-model project model file.
    project_model,
    /// Fallback heuristic when no better source available.
    fallback_heuristic,
    /// Completely unknown — no summary available.
    unknown,
};

// ============================================================================
// Confidence thresholds (centralized)
// ============================================================================

/// Centralized confidence thresholds for summary-based decisions.
/// All threshold comparisons MUST go through these constants to ensure
/// consistency across all passes.
pub const Confidence = struct {
    /// Minimum confidence to treat a summary as reliable enough for
    /// high-severity issue suppression (e.g., "this is definitely safe").
    pub const high: f32 = 0.85;

    /// Minimum confidence to use a summary for medium-severity decisions
    /// (e.g., "probably safe, downgrade to diagnostic").
    pub const medium: f32 = 0.65;

    /// Minimum confidence to use a summary at all (below this, ignore).
    pub const low: f32 = 0.40;

    /// Classify a confidence value into a tier.
    pub fn classify(confidence: f32) Tier {
        if (confidence >= high) return .high;
        if (confidence >= medium) return .medium;
        if (confidence >= low) return .low;
        return .unreliable;
    }

    pub const Tier = enum(u8) { high, medium, low, unreliable };
};
