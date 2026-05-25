//! Steensgaard Types
//!
//! Type definitions for the Steensgaard points-to analysis algorithm.
//! Contains error types, constraints, and algorithm constants.

const std = @import("std");

pub const SteensgaardError = error{
    TooManyLambdaNodes,
    OutOfMemory,
};

/// Maximum ID for regular pointer nodes (lower 31 bits)
/// Lambda nodes use IDs from MAX_POINTER_ID + 1 to avoid collision
pub const MAX_POINTER_ID: u32 = 0x7FFFFFFF;

/// Lambda ID offset (upper bit set to distinguish from regular nodes)
pub const LAMBDA_ID_OFFSET: u32 = 0x80000000;

pub const Constraint = struct {
    lhs: u32,
    rhs: u32,
    kind: ConstraintKind,
};

pub const ConstraintKind = enum(u8) {
    address_of,
    assign,
    indirect,
};
