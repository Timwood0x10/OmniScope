//! FFI analysis module
//!
//! Provides tools for cross-language FFI analysis and vulnerability detection.

pub const ffi_matcher = @import("ffi_matcher.zig");
pub const symbol_graph = @import("symbol_graph.zig");
