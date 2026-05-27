//! Ownership State Solver — Unified state machine for resource lifecycles.
//!
//! Replaces scattered if/else state checks in memory_graph, ptr_lifetime,
//! and ffi_boundary passes with a single centralized state transition table.
//!
//! Every resource goes through states defined here. Passes call into the
//! solver rather than implementing their own state logic.

const std = @import("std");

const contract = @import("../../semantics/resource/contract.zig");
pub const PointerContract = contract.PointerContract;
pub const ContractTransition = contract.ContractTransition;
pub const ContractViolation = contract.ContractViolation;
pub const ViolationSeverity = contract.ViolationSeverity;

const family = @import("../../semantics/resource/family.zig");
pub const FamilyId = family.FamilyId;
pub const FamilyMatchResult = family.FamilyMatchResult;

const escape_mod = @import("../../semantics/resource/escape.zig");
pub const EscapeKind = escape_mod.EscapeKind;

// ============================================================================
// SolverResult — Output of a state transition attempt
// ============================================================================

/// Result of applying a state transition to a resource instance.
pub const SolverResult = enum(u8) {
    /// Transition succeeded — state changed as expected.
    ok,
    /// Transition would cause a violation (e.g., use-after-release).
    violation,
    /// Invalid transition — trigger not allowed from current state.
    invalid_transition,
    /// Unknown current state — cannot determine validity.
    unknown,
};

/// Detailed result including violation information when applicable.
pub const SolverDecision = struct {
    result: SolverResult,
    /// New state after transition (unchanged if failed).
    new_state: PointerContract,
    /// Violation type if result == .violation.
    violation: ?ContractViolation = null,
    /// Severity of the violation.
    severity: ViolationSeverity = .diagnostic,
    /// Human-readable explanation.
    explanation: ?[]const u8 = null,

    pub fn isOk(self: *const SolverDecision) bool {
        return self.result == .ok;
    }

    pub fn isViolation(self: *const SolverDecision) bool {
        return self.result == .violation;
    }
};

// ============================================================================
// OwnershipStateSolver — Centralized state machine
// ============================================================================

/// Solves ownership state transitions for resource instances.
/// All passes delegate state decisions here instead of implementing
/// their own logic.
pub const OwnershipStateSolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OwnershipStateSolver {
        return .{ .allocator = allocator };
    }

    // ====================================================================
    // Core transition API (P7-9 ~ P7-14)
    // ====================================================================

    /// Apply a state transition based on an observed operation.
    /// This is the primary entry point — all passes call this.
    ///
    /// Parameters:
    ///   current_state: The resource's current contract state
    ///   trigger: What operation was observed (acquire/release/retain/etc.)
    ///   alloc_family: The resource's allocation family (for mismatch detection)
    ///   release_family: The deallocation family (for cross-family check)
    ///   has_valid_escape: Whether the resource has a valid disposal escape
    ///
    /// Returns a SolverDecision with the outcome.
    pub fn applyTransition(
        self: *const OwnershipStateSolver,
        current_state: PointerContract,
        trigger: ContractTransition.Trigger,
        alloc_family: ?FamilyId,
        release_family: ?FamilyId,
        has_valid_escape: bool,
    ) SolverDecision {
        _ = self;

        // P7-10: Same-family release handling
        if (trigger == .release or trigger == .conditional_release) {
            if (alloc_family != null and release_family != null) {
                const match_result = compareFamiliesSimple(alloc_family.?, release_family.?);
                switch (match_result) {
                    .same_family, .compatible_family => {
                        // Valid same-family release
                        return .{
                            .result = .ok,
                            .new_state = if (trigger == .conditional_release) .retained else .released,
                            .explanation = "Same-family release: valid disposal",
                        };
                    },
                    .mismatch => {
                        // P7-11: Mismatch release → candidate, not immediate report
                        return .{
                            .result = .violation,
                            .new_state = current_state,
                            .violation = .cross_family_free,
                            .severity = .high,
                            .explanation = "Cross-family free detected",
                        };
                    },
                    .unknown_alloc, .unknown_release, .unknown_both => {},
                }
            }
        }

        // P7-12: Use-after-release detection
        if (current_state == .released) {
            switch (trigger) {
                .borrow, .return_to_caller, .out_param, .field_store, .callback, .thread, .consume => {
                    return .{
                        .result = .violation,
                        .new_state = .released,
                        .violation = .use_after_release,
                        .severity = .critical,
                        .explanation = "Use-after-release: resource already freed",
                    };
                },
                .release => {
                    return .{
                        .result = .violation,
                        .new_state = .released,
                        .violation = .double_release,
                        .severity = .critical,
                        .explanation = "Double release detected",
                    };
                },
                else => {},
            }
        }

        // Standard state transition table (P7-9)
        const new_state = ContractTransition.isValid(current_state, trigger) orelse {
            return .{
                .result = .invalid_transition,
                .new_state = current_state,
                .explanation = "Invalid state transition",
            };
        };

        // P7-13: Valid escape transitions
        switch (trigger) {
            .return_to_caller, .out_param, .field_store, .global_store => {
                if (has_valid_escape) {
                    return .{
                        .result = .ok,
                        .new_state = .transferred,
                        .explanation = "Valid escape via transfer",
                    };
                }
            },
            .conditional_release => {
                // P7-14: Refcount conditional release ≠ unconditional free
                if (current_state == .owned) {
                    return .{
                        .result = .ok,
                        .new_state = .retained,
                        .explanation = "Conditional release: refcount decremented (may not free)",
                    };
                }
            },
            else => {},
        }

        return .{
            .result = .ok,
            .new_state = new_state,
        };
    }

    /// Check if a resource in the given state should be reported as a leak.
    /// Implements: `owned && !released && !valid_escape && !transferred → leak`
    pub fn isLeakCandidate(
        self: *const OwnershipStateSolver,
        state: PointerContract,
        has_valid_escape: bool,
        has_free_sites: bool,
    ) bool {
        _ = self;
        if (state != .owned and state != .maybe_owned) return false;
        if (has_valid_escape) return false;
        if (has_free_sites) return false;
        return true;
    }

    /// Get leak confidence based on state and available evidence.
    pub fn getLeakConfidence(
        state: PointerContract,
        has_family_info: bool,
        has_escape_info: bool,
    ) f32 {
        var base: f32 = switch (state) {
            .owned => 0.85,
            .maybe_owned => 0.55,
            else => 0.3,
        };
        if (has_family_info) base += 0.08;
        if (has_escape_info) base -= 0.15;
        if (base > 1.0) base = 1.0;
        if (base < 0.0) base = 0.0;
        return base;
    }
};

/// Simplified family comparison (without full registry dependency).
fn compareFamiliesSimple(alloc: FamilyId, release: FamilyId) FamilyMatchResult {
    if (alloc == release) return .same_family;
    // Compatible families within Python ecosystem
    if ((alloc == .python_object or alloc == .python_mem or alloc == .python_mem_raw) and
        (release == .python_object or release == .python_mem or release == .python_mem_raw))
    {
        return .compatible_family;
    }
    if (alloc == .invalid or release == .invalid) {
        if (alloc == .invalid and release == .invalid) return .unknown_both;
        if (alloc == .invalid) return .unknown_alloc;
        return .unknown_release;
    }
    return .mismatch;
}
