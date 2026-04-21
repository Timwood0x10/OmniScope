//! Fact types for the fact graph
//!
//! This module defines the core fact types used throughout the analysis.
//! Facts are the primary communication mechanism between passes.

/// Fact kind enumeration
pub const FactKind = enum(u8) {
    /// Control flow edge
    cfg_edge,
    /// Data flow edge
    dfg_edge,
    /// May alias relationship
    alias_may,
    /// Must alias relationship
    alias_must,
    /// Lock acquire event
    lock_acquire,
    /// Lock release event
    lock_release,
    /// Taint propagation
    taint,
    /// Memory allocation
    allocation,
    /// FFI boundary crossing
    ffi_boundary,
    /// Detected vulnerability
    vulnerability,
    /// Ownership allocation event
    ownership_alloc,
    /// Ownership free event
    ownership_free,
    /// Ownership transfer across boundary
    ownership_transfer,
    /// Ownership violation detected
    ownership_violation,
    /// Function symbol mapping (func_id -> name_hash)
    func_symbol,
};

/// Fact represents a single analysis fact
pub const Fact = struct {
    /// Kind of fact
    kind: FactKind,
    /// Subject ID (e.g., instruction ID)
    subject: u32,
    /// Object ID (e.g., target of the fact)
    object: u32,
    /// Context ID (e.g., function or scope)
    context: u32,

    /// Create a new fact
    pub fn init(kind: FactKind, subject: u32, object: u32, context: u32) Fact {
        return .{
            .kind = kind,
            .subject = subject,
            .object = object,
            .context = context,
        };
    }
};

test "Fact - init" {
    const fact = Fact.init(.cfg_edge, 1, 2, 0);
    try std.testing.expectEqual(FactKind.cfg_edge, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 0), fact.context);
}

const std = @import("std");
