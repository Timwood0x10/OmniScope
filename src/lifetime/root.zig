//! Resource Lifetime Analysis Module
//!
//! A language-agnostic resource lifetime analysis framework.
//!
//! This module provides universal lifetime tracking for:
//! - Rust ↔ C
//! - Zig ↔ C
//! - Swift ↔ C
//! - C++ ↔ C ABI
//! - Any LLVM language ↔ Native boundary
//!
//! Architecture:
//! ```
//! Language Frontends (Rust/Zig/C/Swift symbol hints)
//!         ↓
//! Lifetime Engine (owner + state transitions)
//!         ↓
//! Boundary Analyzer (cross-language contract checker)
//!         ↓
//! Issue Detector (leak/UAF/double free/escape)
//! ```
//!
//! **DEPRECATED (2026-05-04):** The `SemanticMapper` sub-module has been removed
//! as it was unused dead code. See untodo.md DEAD-13 for details.
//!
//! Key insight: Lifetime is NOT Rust-specific borrow checking.
//! In the cross-language world, lifetime means:
//!   - Who owns this resource?
//!   - Is it still valid?
//!   - Has it escaped across boundaries?

pub const engine = @import("engine.zig");
pub const boundary = @import("boundary.zig");

// Re-export key types for convenience
pub const Owner = engine.Owner;
pub const LifetimeState = engine.LifetimeState;
pub const SemanticAction = engine.SemanticAction;
pub const ResourceFact = engine.ResourceFact;
pub const IssueType = engine.IssueType;
pub const Issue = engine.Issue;
pub const LifetimeEngine = engine.LifetimeEngine;
pub const EngineStats = engine.EngineStats;
pub const TransitionRule = engine.TransitionRule;
pub const TRANSITION_RULES = engine.TRANSITION_RULES;

// NOTE: SemanticMapper types removed (dead code, 2026-05-04)
// If re-implemented, add mapper import here

pub const BoundaryAnalyzer = boundary.BoundaryAnalyzer;
pub const FFIBoundary = boundary.FFIBoundary;
pub const BoundaryViolation = boundary.BoundaryViolation;
pub const BoundaryIssue = boundary.BoundaryIssue;
pub const BoundaryDirection = boundary.BoundaryDirection;
pub const AnalyzerStats = boundary.AnalyzerStats;

// Re-export types from engine
pub const LanguageHint = engine.LanguageHint;
pub const SourceLocation = engine.SourceLocation;
