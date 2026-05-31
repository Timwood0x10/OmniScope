//! Allocator Shim Detector - Identifies and suppresses false positives from
//! allocator vtable implementations (GlobalAlloc, SystemAllocator, etc.)
//!
//! These functions follow the pattern:
//!   - alloc/realloc: allocate and return pointer (caller or paired dealloc frees)
//!   - free/dealloc: receive and free pointer (not a leak)
//!
//! Reporting them as "orphan pointer" creates noise without security value.
//!
//! ## Problem Background
//!
//! When analyzing bun_alloc.bc, OmniScope reports false positive `cross_language_leak`
//! issues for mimalloc/system allocator vtable functions. The root cause:
//!
//! ```rust
//! unsafe impl GlobalAlloc for BunAlloc {
//!     fn alloc(&self, layout: Layout) -> *mut u8 {
//!         mi_malloc(layout.size())  // ← "orphan pointer" FP!
//!     }
//!     fn dealloc(&self, ptr: *mut u8, layout: Layout) {
//!         mi_free(ptr);  // Real free is here
//!     }
//! }
//! ```
//!
//! OmniScope only sees `mi_malloc` returning a pointer but never sees the free
//! → falsely reports as leak. This is actually normal **allocator vtable design**.

const std = @import("std");

/// Allocator shim detection result
pub const AllocShimResult = enum {
    /// Definitely an allocator shim (suppress reporting)
    confirmed_shim,
    /// Likely an allocator shim (lower confidence)
    likely_shim,
    /// Not an allocator shim (report normally)
    not_shim,
};

/// Classifies what type of allocator operation this is
pub const AllocOperation = enum {
    allocation,
    reallocation,
    deallocation,
};

/// Context for allocation function classification
pub const AllocContext = struct {
    /// Is this function inside a known GlobalAlloc impl?
    is_in_global_alloc_impl: bool = false,
    /// Does the function name match known allocator patterns?
    matches_allocator_pattern: bool = false,
    /// Is the return type a raw pointer (*mut u8)?
    returns_raw_pointer: bool = true,
    /// Is the first parameter a raw pointer (for free functions)?
    accepts_raw_pointer: bool = false,
};

/// Detects allocator shim functions to suppress false positive reports.
///
/// This detector identifies well-known allocator implementations (mimalloc,
/// jemalloc, rpmalloc, system allocators, Rust global alloc) that follow
/// the standard allocator vtable pattern where allocation and deallocation
/// are split across different functions.
pub const AllocatorShimDetector = struct {
    // ── Known allocator function patterns ──

    /// mimalloc allocator functions
    const MIMALLOC_PATTERNS = [_][]const u8{
        "mi_malloc",
        "mi_realloc",
        "mi_free",
        "mi_heap_malloc",
        "mi_heap_realloc",
        "mi_heap_free",
        "mi_malloc_aligned",
        "mi_realloc_aligned",
        "mi_malloc_small",
        "mi_calloc",
        "mi_heap_malloc_small",
        "mi_heap_calloc",
        "mi_stl_alloc",
        "mi_stl_delloc",
        "mi_expand_heap",
        "mi_zone_init",
        "mi_collect",
        "mi_stats_merge",
        "mi_register",
    };

    /// System allocator functions (malloc/free/calloc/realloc)
    const SYSTEM_ALLOC_PATTERNS = [_][]const u8{
        "malloc",
        "calloc",
        "realloc",
        "free",
        "aligned_alloc",
        "posix_memalign",
        "memalign",
        "valloc",
        "palloc",
        "strdup",
        "strndup",
    };

    /// Rust global allocator fallback patterns
    const RUST_FALLBACK_PATTERNS = [_][]const u8{
        "__rust_alloc",
        "__rust_dealloc",
        "__rust_realloc",
        "fallback::",
        "Z5alloc", // mangled "alloc"
        "Z7realloc", // mangled "realloc"
        "Z5free", // mangled "free"
    };

    /// jemalloc functions (if project uses jemalloc)
    const JEMALLOC_PATTERNS = [_][]const u8{
        "je_mallocx",
        "je_rallocx",
        "je_dallocx",
        "je_sdallocx",
        "je_free",
        "je_mallctl",
        "je_nallocx",
    };

    /// rpmalloc functions
    const RPMALLOC_PATTERNS = [_][]const u8{
        "rpmalloc",
        "rprealloc",
        "rpmemfree",
        "rpmalloc_initialize",
    };

    /// Check if function name matches any known allocator pattern.
    ///
    /// This is the primary detection method. It checks against all known
    /// allocator function name patterns with confidence levels:
    /// - `confirmed_shim`: High-confidence match (mimalloc, jemalloc, etc.)
    /// - `likely_shim`: Medium-confidence match (system allocators like malloc)
    /// - `not_shim`: No match found
    ///
    /// Arguments:
    ///   func_name - The function name to check
    ///
    /// Returns:
    ///   Detection result indicating confidence level
    pub fn isAllocatorShim(func_name: []const u8) AllocShimResult {
        // Fast path: exact match against mimalloc patterns (high confidence)
        if (matchAnyPattern(func_name, MIMALLOC_PATTERNS)) {
            return .confirmed_shim;
        }

        // Check Rust fallback patterns (high confidence)
        if (matchAnyPattern(func_name, RUST_FALLBACK_PATTERNS)) {
            return .confirmed_shim;
        }

        // Check jemalloc/rpmalloc (high confidence)
        if (matchAnyPattern(func_name, JEMALLOC_PATTERNS) or
            matchAnyPattern(func_name, RPMALLOC_PATTERNS))
        {
            return .confirmed_shim;
        }

        // System allocators need context (medium confidence)
        if (matchAnyPattern(func_name, SYSTEM_ALLOC_PATTERNS)) {
            return .likely_shim;
        }

        return .not_shim;
    }

    /// Enhanced check with call-site context for better accuracy.
    ///
    /// For system allocators (which have medium confidence by default),
    /// this function uses caller context to upgrade confidence when called
    /// from a known GlobalAlloc implementation.
    ///
    /// Arguments:
    ///   func_name - The callee function name to check
    ///   caller_func_name - Optional caller function name for context
    ///
    /// Returns:
    ///   Detection result with potential confidence upgrade
    pub fn isAllocatorShimWithContext(
        func_name: []const u8,
        caller_func_name: ?[]const u8,
    ) AllocShimResult {
        const base_result = isAllocatorShim(func_name);

        // If already confirmed, no need for context
        if (base_result == .confirmed_shim) return base_result;

        // For system allocators, check if called from GlobalAlloc impl
        if (base_result == .likely_shim) {
            if (caller_func_name) |caller| {
                // Heuristic: GlobalAlloc impls often contain "alloc"/"dealloc"
                // in their mangled names or are in specific modules
                if (isLikelyGlobalAllocImpl(caller)) {
                    return .confirmed_shim;
                }
            }
        }

        return base_result;
    }

    /// Classify what type of allocator operation this is.
    ///
    /// Arguments:
    ///   func_name - The function name to classify
    ///
    /// Returns:
    ///   Operation type (allocation/reallocation/deallocation) or null
    pub fn classifyAllocOperation(func_name: []const u8) ?AllocOperation {
        // Check realloc first (contains "alloc" as substring)
        if (containsAny(func_name, [_][]const u8{ "realloc", "expand" })) {
            return .reallocation;
        }
        // Then check allocation (but not realloc)
        if (containsAny(func_name, [_][]const u8{ "malloc", "calloc" }) or
            std.mem.indexOf(u8, func_name, "alloc") != null)
        {
            return .allocation;
        }
        // Finally check deallocation
        if (containsAny(func_name, [_][]const u8{ "free", "dealloc", "release" })) {
            return .deallocation;
        }
        return null;
    }

    // ── Internal helpers ──

    /// Check if haystack contains any of the needle patterns
    fn matchAnyPattern(haystack: []const u8, needles: anytype) bool {
        for (needles) |needle| {
            if (std.mem.indexOf(u8, haystack, needle) != null) return true;
        }
        return false;
    }

    /// Check if haystack contains any of the needle substrings
    fn containsAny(haystack: []const u8, needles: anytype) bool {
        for (needles) |needle| {
            if (std.mem.indexOf(u8, haystack, needle) != null) return true;
        }
        return false;
    }

    /// Heuristic check if caller is likely a GlobalAlloc implementation
    fn isLikelyGlobalAllocImpl(caller_name: []const u8) bool {
        // Common patterns in Rust GlobalAlloc implementations
        const GLOBAL_ALLOC_INDICATORS = [_][]const u8{
            "global_alloc",
            "GlobalAlloc",
            "System",
            "Allocator",
            "alloc::",
            "std::alloc",
        };

        return matchAnyPattern(caller_name, GLOBAL_ALLOC_INDICATORS);
    }
};

// ── Tests ──

test "isAllocatorShim - detects mimalloc functions" {
    // Test confirmed shims for mimalloc functions
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("mi_malloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("mi_free"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("mi_heap_malloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("mi_realloc"),
    );

    // Test edge cases with partial names
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("mi_calloc"),
    );
}

test "isAllocatorShim - detects system allocators as likely" {
    // System allocators should be classified as likely (need context)
    try std.testing.expectEqual(
        AllocShimResult.likely_shim,
        AllocatorShimDetector.isAllocatorShim("malloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.likely_shim,
        AllocatorShimDetector.isAllocatorShim("free"),
    );
    try std.testing.expectEqual(
        AllocShimResult.likely_shim,
        AllocatorShimDetector.isAllocatorShim("calloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.likely_shim,
        AllocatorShimDetector.isAllocatorShim("realloc"),
    );
}

test "isAllocatorShim - rejects non-allocator functions" {
    // Non-allocator functions should not match
    try std.testing.expectEqual(
        AllocShimResult.not_shim,
        AllocatorShimDetector.isAllocatorShim("SSL_CTX_new"),
    );
    try std.testing.expectEqual(
        AllocShimResult.not_shim,
        AllocatorShimDetector.isAllocatorShim("process_data"),
    );
    try std.testing.expectEqual(
        AllocShimResult.not_shim,
        AllocatorShimDetector.isAllocatorShim("open_file"),
    );
}

test "isAllocatorShim - detects Rust fallback patterns" {
    // Rust global allocator fallback functions
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("__rust_alloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("__rust_dealloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("__rust_realloc"),
    );
}

test "isAllocatorShim - detects jemalloc functions" {
    // jemalloc API functions
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("je_mallocx"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("je_free"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("je_dallocx"),
    );
}

test "isAllocatorShim - detects rpmalloc functions" {
    // rpmalloc API functions
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("rpmalloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("rprealloc"),
    );
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("rpmemfree"),
    );
}

test "isAllocatorShimWithContext - upgrades system alloc with GlobalAlloc caller" {
    // System allocator without context stays at likely
    try std.testing.expectEqual(
        AllocShimResult.likely_shim,
        AllocatorShimDetector.isAllocatorShimWithContext("malloc", null),
    );

    // System allocator with GlobalAlloc caller gets upgraded
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShimWithContext(
            "malloc",
            "global_alloc_impl",
        ),
    );

    // Confirmed shim doesn't need context upgrade
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShimWithContext(
            "mi_malloc",
            null,
        ),
    );
}

test "classifyAllocOperation - classifies allocation operations" {
    // Allocation functions
    try std.testing.expectEqual(
        AllocOperation.allocation,
        AllocatorShimDetector.classifyAllocOperation("mi_malloc"),
    );
    try std.testing.expectEqual(
        AllocOperation.allocation,
        AllocatorShimDetector.classifyAllocOperation("malloc"),
    );
    try std.testing.expectEqual(
        AllocOperation.allocation,
        AllocatorShimDetector.classifyAllocOperation("calloc"),
    );

    // Reallocation functions
    try std.testing.expectEqual(
        AllocOperation.reallocation,
        AllocatorShimDetector.classifyAllocOperation("mi_realloc"),
    );
    try std.testing.expectEqual(
        AllocOperation.reallocation,
        AllocatorShimDetector.classifyAllocOperation("realloc"),
    );

    // Deallocation functions
    try std.testing.expectEqual(
        AllocOperation.deallocation,
        AllocatorShimDetector.classifyAllocOperation("mi_free"),
    );
    try std.testing.expectEqual(
        AllocOperation.deallocation,
        AllocatorShimDetector.classifyAllocOperation("free"),
    );

    // Non-allocator function returns null
    try std.testing.expectEqual(
        @as(?AllocOperation, null),
        AllocatorShimDetector.classifyAllocOperation("process_data"),
    );
}

test "edge cases - empty and special strings" {
    // Empty string should not match
    try std.testing.expectEqual(
        AllocShimResult.not_shim,
        AllocatorShimDetector.isAllocatorShim(""),
    );

    // Very short strings
    try std.testing.expectEqual(
        AllocShimResult.not_shim,
        AllocatorShimDetector.isAllocatorShim("mi"),
    );

    // Partial matches within larger names
    try std.testing.expectEqual(
        AllocShimResult.confirmed_shim,
        AllocatorShimDetector.isAllocatorShim("custom_mi_malloc_wrapper"),
    );
}
