//! Memory tracking module for performance measurement and leak detection
//!
//! This module provides utilities for tracking memory allocations and
//! collecting statistics for performance analysis.

pub const allocator = @import("allocator.zig");
pub const MemoryStats = allocator.MemoryStats;
pub const TrackedAllocator = allocator.TrackedAllocator;
