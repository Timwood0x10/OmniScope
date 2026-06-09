//! PointerContract — Ownership contract state for a resource pointer.
//!
//! Tracks what kind of ownership a pointer has at any point in analysis.
//! Replaces implicit "allocated = must be freed" with a rich contract model
//! that distinguishes owned, borrowed, transferred, retained, and escaped pointers.
//!
//! Key insight: not every allocation needs a matching free in the same function.
//! A pointer that is returned to caller (returns_owned), stored into an owner
//! object's field (field_store), or passed to a callback is NOT leaked — it has
//! been transferred/escaped according to its contract.

const std = @import("std");

// ============================================================================
// PointerContract — What kind of ownership does this pointer have?
// ============================================================================

/// The ownership contract of a single resource pointer at a program point.
/// This is the central type that drives leak/borrow-escape/cross-free decisions.
pub const PointerContract = enum(u8) {
    /// Pointer was allocated by this function and we own it.
    /// Must be freed/transferred/escaped before function returns.
    /// Example: `int* p = malloc(...);` — p is owned.
    owned,

    /// Pointer was borrowed from somewhere else.
    /// Caller must NOT free it. Owner remains responsible.
    /// Example: `const int& r = vec[0];` — r is borrowed.
    borrowed,

    /// Uncertain whether this is owned or borrowed.
    /// Requires additional analysis to resolve.
    /// Default for pointers from unknown sources.
    maybe_owned,

    /// Ownership was transferred to another entity (caller, field, callback).
    /// No longer our responsibility to free.
    /// Example: `return p;` or `obj->field = p;` after transfer.
    transferred,

    /// Reference count was incremented (retain). Not an owner.
    /// Must eventually release (decrement refcount) but didn't allocate.
    /// Example: `Py_INCREF(obj);` — obj is retained by us.
    retained,

    /// Resource has been explicitly released/freed.
    /// Any subsequent use is use-after-free.
    /// Example: `free(p);` — p is released.
    released,

    /// Pointer is invalid (null, dangling, undefined).
    /// Should not appear in normal flow; indicates prior error.
    invalid,

    /// Contract could not be determined (insufficient information).
    /// Treated conservatively: assume maybe_owned.
    unknown,

    // ========================================================================
    // Query helpers
    // ========================================================================

    /// Check if this contract represents active ownership (needs cleanup).
    pub fn isActiveOwnership(self: PointerContract) bool {
        return switch (self) {
            .owned => true,
            .retained => true,
            .maybe_owned => true,
            .transferred, .borrowed, .released, .invalid, .unknown => false,
        };
    }

    /// Check if this pointer has been properly disposed of (not a leak).
    /// Returns true if released OR validly transferred/escaped.
    pub fn isDisposed(self: PointerContract) bool {
        return switch (self) {
            .released, .transferred => true,
            .owned, .borrowed, .retained, .maybe_owned, .invalid, .unknown => false,
        };
    }

    /// Check if accessing this pointer would be a use-after-release.
    pub fn isUseAfterRelease(self: PointerContract) bool {
        return self == .released;
    }

    /// Check if this pointer can be safely read (not released/invalid).
    pub fn isReadable(self: PointerContract) bool {
        return switch (self) {
            .released, .invalid => false,
            else => true,
        };
    }

    /// Get human-readable name for logging/debug output.
    pub fn name(self: PointerContract) []const u8 {
        return switch (self) {
            .owned => "owned",
            .borrowed => "borrowed",
            .maybe_owned => "maybe_owned",
            .transferred => "transferred",
            .retained => "retained",
            .released => "released",
            .invalid => "invalid",
            .unknown => "unknown",
        };
    }
};

// ============================================================================
// ContractTransition — Valid state transitions for PointerContract
// ============================================================================

/// A valid transition from one contract state to another, triggered by
/// a specific operation (effect).
pub const ContractTransition = struct {
    from: PointerContract,
    to: PointerContract,
    trigger: Trigger,
    evidence: []const u8,

    pub const Trigger = enum(u8) {
        /// Allocation operation (malloc, new, PyObject_New, etc.)
        acquire,
        /// Free/dealloc operation (free, delete, __rust_dealloc, etc.)
        release,
        /// Refcount increment (Py_INCREF, CFRetain, etc.)
        retain,
        /// Return to caller (ownership transfer via return value)
        return_to_caller,
        /// Store into out-parameter (*out = ptr)
        out_param_store,
        /// Store into owner object's field (obj->field = ptr)
        field_store,
        /// Store into global/static variable
        global_store,
        /// Pass to callback/closure
        callback_escape,
        /// Pass to spawned thread
        thread_escape,
        /// Borrow without ownership change (as_ptr, &ref)
        borrow,
        /// Consume/take ownership (cJSON_Delete takes responsibility)
        consume,
        /// Conditional release (Py_DECREF — may or may not free)
        conditional_release,
        /// Unknown operation
        unknown,
    };

    /// Check if a transition is valid given current state and trigger.
    pub fn isValid(from: PointerContract, trigger: Trigger) ?PointerContract {
        return switch (from) {
            .owned => switch (trigger) {
                .release => .released,
                .return_to_caller => .transferred,
                .out_param_store => .transferred,
                .field_store => .transferred,
                .global_store => .transferred,
                .callback_escape => .transferred,
                .thread_escape => .transferred,
                .borrow => .borrowed,
                .consume => .released,
                .conditional_release => .retained,
                .acquire, .retain, .unknown => null,
            },
            .borrowed => switch (trigger) {
                .return_to_caller => .transferred,
                .field_store => .transferred,
                .global_store => .transferred,
                .callback_escape => .transferred,
                .borrow => .borrowed,
                else => null,
            },
            .maybe_owned => switch (trigger) {
                .release => .released,
                .return_to_caller => .transferred,
                .field_store => .transferred,
                .global_store => .transferred,
                else => null,
            },
            .transferred => null,
            .retained => switch (trigger) {
                .release => .released,
                .conditional_release => .retained,
                .return_to_caller => .transferred,
                .field_store => .transferred,
                else => null,
            },
            .released => null,
            .invalid => null,
            .unknown => switch (trigger) {
                .acquire => .owned,
                .borrow => .borrowed,
                else => null,
            },
        };
    }
};

// ============================================================================
// ContractViolation — What went wrong with a contract?
// ============================================================================

/// Type of contract violation detected during analysis.
pub const ContractViolation = enum(u8) {
    /// Resource was allocated but never freed/transferred/escaped.
    leak,
    /// Resource was used after being released (use-after-free / double-free).
    use_after_release,
    /// Resource was released twice (double free).
    double_release,
    /// Resource was freed by wrong-family deallocator (malloc + delete[]).
    cross_family_free,
    /// Borrowed pointer was incorrectly treated as owned.
    borrowed_treated_as_owned,
    /// Retained pointer was released without matching retain count mismatch.
    retain_count_mismatch,
    /// Unknown violation type.
    unknown,

    pub fn name(v: ContractViolation) []const u8 {
        return switch (v) {
            .leak => "leak",
            .use_after_release => "use_after_release",
            .double_release => "double_release",
            .cross_family_free => "cross_family_free",
            .borrowed_treated_as_owned => "borrowed_treated_as_owned",
            .retain_count_mismatch => "retain_count_mismatch",
            .unknown => "unknown",
        };
    }
};

/// Severity level for contract violations.
pub const ViolationSeverity = enum(u4) {
    critical,
    high,
    medium,
    low,
    diagnostic,
    explained,
};
