//! Performance Optimization Module
//!
//! This module provides performance optimization utilities:
//! - MemoryPool: Fixed-size memory pool for reduced allocation overhead
//! - ArenaAllocator: Batch allocation with single free
//! - Profiler: Performance profiling and hotspot detection
//! - AnalysisContext: Optimized context for analysis passes
//! - StringInterner: String deduplication for memory savings

pub const MemoryPool = @import("memory_pool.zig").MemoryPool;
pub const ArenaAllocator = @import("memory_pool.zig").ArenaAllocator;
pub const Profiler = @import("profiler.zig").Profiler;
pub const Timer = @import("profiler.zig").Timer;
pub const ScopedTimer = @import("profiler.zig").ScopedTimer;
pub const ProfileStats = @import("profiler.zig").ProfileStats;
pub const AnalysisContext = @import("analysis_context.zig").AnalysisContext;
pub const StringInterner = @import("analysis_context.zig").StringInterner;

test {
    _ = @import("memory_pool.zig");
    _ = @import("profiler.zig");
    _ = @import("analysis_context.zig");
}
