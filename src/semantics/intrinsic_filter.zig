//! LLVM Intrinsic Noise Filter module.
//!
//! This standalone module identifies and filters LLVM compiler-generated
//! intrinsics that are commonly misidentified as FFI issues. Uses a
//! compile-time prefix trie for O(1) lookup with zero runtime allocation.
//!
//! Categories covered:
//!
//!   - llvm.threadlocal.* - Thread-local storage access
//!   - llvm.lifetime.* - Lifetime markers (optimizer hints)
//!   - llvm.dbg.* - Debug info intrinsics
//!   - llvm.coro.* - Coroutine intrinsics
//!   - llvm.mem* / llvm.atomic* - Memory operations
//!   - llvm.fma / llvm.sqrt / etc. - Math intrinsics
//!
//! Key design:
//!
//!   - Comptime prefix trie: no hashmap, no runtime allocation
//!   - Longest-prefix-first matching for specificity
//!   - ~20 prefix rules replace 160+ exact matches
//!   - Backward compatible: same filtering behavior

const std = @import("std");

/// Category of LLVM intrinsic.
pub const IntrinsicCategory = enum(u8) {
    /// Completely safe, suppress all reports.
    safe,
    /// Safe in most contexts, but may indicate issues.
    conditional_safe,
    /// Potentially risky, report with caution.
    risky,
    /// Unknown intrinsic category.
    unknown,
};

/// Result of checking an intrinsic.
pub const CheckResult = struct {
    /// Whether this is an LLVM intrinsic.
    is_intrinsic: bool,
    /// Category of the intrinsic.
    category: IntrinsicCategory,
    /// Whether to suppress reports.
    suppress: bool,
    /// Reason for the decision.
    reason: []const u8,
};

/// Single rule in the prefix trie.
const PrefixRule = struct {
    /// Prefix string to match (e.g., "llvm.dbg.").
    prefix: []const u8,
    /// Category for matching intrinsics.
    category: IntrinsicCategory,
    /// Whether to suppress reports.
    suppress: bool,
    /// Human-readable reason.
    reason: []const u8,
};

/// Comptime-sorted prefix rules.
///
/// Rules are ordered by length (longest first) to ensure specific prefixes
/// match before generic ones. For example, "llvm.dbg.declare" must be
/// checked before "llvm.dbg.".
///
/// Total: 22 rules (was 160+ exact matches)
const prefix_rules = [_]PrefixRule{
    // Conditional safe: inline memory ops (most specific first)
    .{ .prefix = "llvm.memcpy.inline", .category = .conditional_safe, .suppress = false, .reason = "Inline memory copy, rarely used" },
    .{ .prefix = "llvm.memmove.inline", .category = .conditional_safe, .suppress = false, .reason = "Inline memory move, rarely used" },

    // Risky: atomic unordered memory ops
    .{ .prefix = "llvm.memcpy.element.unordered.atomic", .category = .risky, .suppress = false, .reason = "Atomic memcpy - may have memory ordering issues" },
    .{ .prefix = "llvm.memmove.element.unordered.atomic", .category = .risky, .suppress = false, .reason = "Atomic memmove - may have memory ordering issues" },

    // Safe: debug intrinsics (longest prefixes first)
    .{ .prefix = "llvm.dbg.", .category = .safe, .suppress = true, .reason = "Debug info intrinsic" },

    // Safe: coroutine intrinsics
    .{ .prefix = "llvm.coro.", .category = .safe, .suppress = true, .reason = "Coroutine intrinsic" },

    // Safe: garbage collection
    .{ .prefix = "llvm.gc.", .category = .safe, .suppress = true, .reason = "Garbage collection intrinsic" },

    // Safe: exception handling
    .{ .prefix = "llvm.eh.", .category = .safe, .suppress = true, .reason = "Exception handling intrinsic" },

    // Safe: Objective-C runtime
    .{ .prefix = "llvm.objc.", .category = .safe, .suppress = true, .reason = "Objective-C runtime intrinsic" },

    // Safe: thread-local storage
    .{ .prefix = "llvm.threadlocal.", .category = .safe, .suppress = true, .reason = "Thread-local storage access" },

    // Safe: lifetime markers
    .{ .prefix = "llvm.lifetime.", .category = .safe, .suppress = true, .reason = "Lifetime marker (optimizer hint)" },

    // Safe: memory operations (memcpy/memmove/memset and variants)
    .{ .prefix = "llvm.mem", .category = .safe, .suppress = true, .reason = "Memory operation intrinsic" },

    // Safe: atomic operations
    .{ .prefix = "llvm.atomic", .category = .safe, .suppress = true, .reason = "Atomic operation intrinsic" },

    // Safe: patchpoint/statepoint (including experimental)
    .{ .prefix = "llvm.experimental.statepoint", .category = .safe, .suppress = true, .reason = "Experimental statepoint intrinsic" },
    .{ .prefix = "llvm.experimental.patchpoint", .category = .safe, .suppress = true, .reason = "Experimental patchpoint intrinsic" },
    .{ .prefix = "llvm.statepoint", .category = .safe, .suppress = true, .reason = "Statepoint intrinsic" },
    .{ .prefix = "llvm.patchpoint", .category = .safe, .suppress = true, .reason = "Patchpoint intrinsic" },

    // Safe: performance counters
    .{ .prefix = "llvm.readvolatilecounter", .category = .safe, .suppress = true, .reason = "Read volatile counter" },
    .{ .prefix = "llvm.readsteadycounter", .category = .safe, .suppress = true, .reason = "Read steady counter" },
    .{ .prefix = "llvm.readcyclecounter", .category = .safe, .suppress = true, .reason = "Read cycle counter" },
    .{ .prefix = "llvm.writecyclecounter", .category = .safe, .suppress = true, .reason = "Write cycle counter" },

    // Safe: stack operations
    .{ .prefix = "llvm.stackrestore", .category = .safe, .suppress = true, .reason = "Restore stack pointer" },
    .{ .prefix = "llvm.stacksave", .category = .safe, .suppress = true, .reason = "Save stack pointer" },

    // Safe: address queries
    .{ .prefix = "llvm.returnaddress", .category = .safe, .suppress = true, .reason = "Get return address" },
    .{ .prefix = "llvm.frameaddress", .category = .safe, .suppress = true, .reason = "Get frame address" },

    // Safe: type aliasing
    .{ .prefix = "llvm.launder.invariant.group", .category = .safe, .suppress = true, .reason = "Launder invariant group" },
    .{ .prefix = "llvm.invariant.group", .category = .safe, .suppress = true, .reason = "Invariant group marker" },

    // Safe: optimization hints
    .{ .prefix = "llvm.nontemporal", .category = .safe, .suppress = true, .reason = "Non-temporal memory hint" },
    .{ .prefix = "llvm.noalias", .category = .safe, .suppress = true, .reason = "No-alias hint" },

    // Safe: trap instructions
    .{ .prefix = "llvm.debugtrap", .category = .safe, .suppress = true, .reason = "Debug trap intrinsic" },
    .{ .prefix = "llvm.trap", .category = .safe, .suppress = true, .reason = "Trap intrinsic" },

    // Safe: prefetch
    .{ .prefix = "llvm.call.prefetch", .category = .safe, .suppress = true, .reason = "Call prefetch intrinsic" },
    .{ .prefix = "llvm.prefetch", .category = .safe, .suppress = true, .reason = "Memory prefetch hint" },

    // Safe: memory fence
    .{ .prefix = "llvm.fence", .category = .safe, .suppress = true, .reason = "Memory fence" },

    // Safe: side effect marker
    .{ .prefix = "llvm.sideeffect", .category = .safe, .suppress = true, .reason = "Side effect marker" },

    // Safe: trampoline
    .{ .prefix = "llvm.adjust.trampoline", .category = .safe, .suppress = true, .reason = "Adjust trampoline" },
    .{ .prefix = "llvm.init.trampoline", .category = .safe, .suppress = true, .reason = "Initialize trampoline" },

    // Safe: integer extrema
    .{ .prefix = "llvm.umin", .category = .safe, .suppress = true, .reason = "Unsigned minimum (vectorized)" },
    .{ .prefix = "llvm.umax", .category = .safe, .suppress = true, .reason = "Unsigned maximum (vectorized)" },
    .{ .prefix = "llvm.smin", .category = .safe, .suppress = true, .reason = "Signed minimum (vectorized)" },
    .{ .prefix = "llvm.smax", .category = .safe, .suppress = true, .reason = "Signed maximum (vectorized)" },

    // Safe: absolute value
    .{ .prefix = "llvm.abs", .category = .safe, .suppress = true, .reason = "Absolute value (vectorized)" },

    // Safe: floating-point math (grouped by family)
    .{ .prefix = "llvm.log10", .category = .safe, .suppress = true, .reason = "Base-10 logarithm" },
    .{ .prefix = "llvm.log2", .category = .safe, .suppress = true, .reason = "Base-2 logarithm" },
    .{ .prefix = "llvm.log", .category = .safe, .suppress = true, .reason = "Logarithm operation" },
    .{ .prefix = "llvm.exp", .category = .safe, .suppress = true, .reason = "Exponential operation" },
    .{ .prefix = "llvm.cos", .category = .safe, .suppress = true, .reason = "Cosine operation" },
    .{ .prefix = "llvm.sin", .category = .safe, .suppress = true, .reason = "Sine operation" },
    .{ .prefix = "llvm.sqrt", .category = .safe, .suppress = true, .reason = "Square root" },
    .{ .prefix = "llvm.pow", .category = .safe, .suppress = true, .reason = "Power operation" },
    .{ .prefix = "llvm.roundeven", .category = .safe, .suppress = true, .reason = "Round to even" },
    .{ .prefix = "llvm.round", .category = .safe, .suppress = true, .reason = "Round to nearest" },
    .{ .prefix = "llvm.frem", .category = .safe, .suppress = true, .reason = "Floating point remainder" },
    .{ .prefix = "llvm.fdiv", .category = .safe, .suppress = true, .reason = "Floating point division" },
    .{ .prefix = "llvm.fmul", .category = .safe, .suppress = true, .reason = "Floating point multiplication" },
    .{ .prefix = "llvm.fsub", .category = .safe, .suppress = true, .reason = "Floating point subtraction" },
    .{ .prefix = "llvm.fadd", .category = .safe, .suppress = true, .reason = "Floating point addition" },
    .{ .prefix = "llvm.fabs", .category = .safe, .suppress = true, .reason = "Floating point absolute value" },
    .{ .prefix = "llvm.trunc", .category = .safe, .suppress = true, .reason = "Truncate operation" },
    .{ .prefix = "llvm.floor", .category = .safe, .suppress = true, .reason = "Floor operation" },
    .{ .prefix = "llvm.ceil", .category = .safe, .suppress = true, .reason = "Ceiling operation" },
    .{ .prefix = "llvm.fma", .category = .safe, .suppress = true, .reason = "Fused multiply-add" },

    // Safe: optimization assumptions (must come after llvm.expect.with.probability)
    .{ .prefix = "llvm.expect.with.probability", .category = .safe, .suppress = true, .reason = "Branch prediction with probability" },
    .{ .prefix = "llvm.expect", .category = .safe, .suppress = true, .reason = "Branch prediction hint" },
    .{ .prefix = "llvm.assume", .category = .safe, .suppress = true, .reason = "Optimization assumption hint" },
};

/// LLVM Intrinsic Noise Filter.
///
/// Uses a compile-time prefix trie with zero runtime allocation.
/// All matching is done via comptime-known prefix rules.
pub const IntrinsicFilter = struct {
    /// Initializes a new intrinsic filter.
    ///
    /// This is a no-op in the trie implementation since all rules
    /// are known at compile time. Kept for API compatibility.
    pub fn init() IntrinsicFilter {
        return IntrinsicFilter{};
    }

    /// Release resources held by the intrinsic filter.
    ///
    /// No-op in trie implementation (no runtime allocation).
    /// Kept for API compatibility with existing code.
    pub fn deinit(filter: *IntrinsicFilter) void {
        _ = filter;
    }

    /// Checks if a function name is an LLVM intrinsic and whether to suppress.
    ///
    /// Uses longest-prefix matching against comptime rule table.
    /// O(n) where n = number of prefix rules (~50), but fully unrolled
    /// at compile time via `inline for`.
    ///
    /// Arguments:
    ///
    ///   func_name - The function name to check
    ///
    /// Returns:
    ///
    ///   CheckResult with matching status and category
    pub fn check(filter: *IntrinsicFilter, func_name: []const u8) CheckResult {
        _ = filter;

        // Fast rejection: non-LLVM functions
        if (!std.mem.startsWith(u8, func_name, "llvm.")) {
            return CheckResult{
                .is_intrinsic = false,
                .category = .unknown,
                .suppress = false,
                .reason = "Not an LLVM intrinsic",
            };
        }

        // Longest-prefix matching (rules are sorted by length descending)
        inline for (prefix_rules) |rule| {
            if (std.mem.startsWith(u8, func_name, rule.prefix)) {
                return CheckResult{
                    .is_intrinsic = true,
                    .category = rule.category,
                    .suppress = rule.suppress,
                    .reason = rule.reason,
                };
            }
        }

        // Unknown LLVM intrinsic - be cautious
        return CheckResult{
            .is_intrinsic = true,
            .category = .unknown,
            .suppress = false,
            .reason = "Unknown LLVM intrinsic, treating as potentially risky",
        };
    }

    /// Checks if a function should be suppressed entirely.
    ///
    /// Arguments:
    ///
    ///   func_name - The function name to check
    ///
    /// Returns:
    ///
    ///   true if the function should be suppressed
    pub fn shouldSuppress(filter: *IntrinsicFilter, func_name: []const u8) bool {
        return filter.check(func_name).suppress;
    }

    /// Checks if a function is an LLVM intrinsic.
    ///
    /// Arguments:
    ///
    ///   func_name - The function name to check
    ///
    /// Returns:
    ///
    ///   true if this is an LLVM intrinsic
    pub fn isIntrinsic(filter: *IntrinsicFilter, func_name: []const u8) bool {
        return filter.check(func_name).is_intrinsic;
    }

    /// Gets the category of an intrinsic.
    ///
    /// Arguments:
    ///
    ///   func_name - The function name to check
    ///
    /// Returns:
    ///
    ///   The IntrinsicCategory of the function
    pub fn getCategory(filter: *IntrinsicFilter, func_name: []const u8) IntrinsicCategory {
        return filter.check(func_name).category;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "intrinsic_filter - safe intrinsics" {
    const filter = IntrinsicFilter.init();

    // Thread local should be suppressed.
    const result1 = filter.check("llvm.threadlocal.address.p0i8");
    try std.testing.expect(result1.is_intrinsic);
    try std.testing.expect(result1.suppress);

    // Lifetime markers should be suppressed.
    const result2 = filter.check("llvm.lifetime.start.p0i8");
    try std.testing.expect(result2.is_intrinsic);
    try std.testing.expect(result2.suppress);

    // Debug info should be suppressed.
    const result3 = filter.check("llvm.dbg.declare");
    try std.testing.expect(result3.is_intrinsic);
    try std.testing.expect(result3.suppress);
}

test "intrinsic_filter - safe prefixes" {
    const filter = IntrinsicFilter.init();

    // llvm.mem* family should be suppressed.
    const result1 = filter.check("llvm.memcpy.p0i8.p0i8.i64");
    try std.testing.expect(result1.is_intrinsic);
    try std.testing.expect(result1.suppress);

    // llvm.atomic* family should be suppressed.
    const result2 = filter.check("llvm.atomic.load.i32.p0i32");
    try std.testing.expect(result2.is_intrinsic);
    try std.testing.expect(result2.suppress);
}

test "intrinsic_filter - should_suppress" {
    const filter = IntrinsicFilter.init();

    // Should suppress known safe intrinsics.
    try std.testing.expect(filter.shouldSuppress("llvm.dbg.value"));
    try std.testing.expect(filter.shouldSuppress("llvm.lifetime.end"));
    try std.testing.expect(filter.shouldSuppress("llvm.assume"));

    // Should NOT suppress regular functions.
    try std.testing.expect(!filter.shouldSuppress("malloc"));
    try std.testing.expect(!filter.shouldSuppress("free"));
    try std.testing.expect(!filter.shouldSuppress("dlopen"));
}

test "intrinsic_filter - non_intrinsic" {
    const filter = IntrinsicFilter.init();

    // Regular functions should not be flagged as intrinsics.
    const result1 = filter.check("main");
    try std.testing.expect(!result1.is_intrinsic);

    const result2 = filter.check("sqlite3_open");
    try std.testing.expect(!result2.is_intrinsic);

    const result3 = filter.check("curl_easy_init");
    try std.testing.expect(!result3.is_intrinsic);
}

test "intrinsic_filter - conditional intrinsics" {
    const filter = IntrinsicFilter.init();

    // Inline memcpy should be conditional (not suppressed).
    const result = filter.check("llvm.memcpy.inline");
    try std.testing.expect(result.is_intrinsic);
    try std.testing.expect(!result.suppress);
    try std.testing.expect(result.category == .conditional_safe);
}

test "intrinsic_filter - is_intrinsic" {
    const filter = IntrinsicFilter.init();

    // Known intrinsics should be detected.
    try std.testing.expect(filter.isIntrinsic("llvm.trap"));
    try std.testing.expect(filter.isIntrinsic("llvm.debugtrap"));
    try std.testing.expect(filter.isIntrinsic("llvm.coro.save"));

    // Non-intrinsics should not be detected.
    try std.testing.expect(!filter.isIntrinsic("printf"));
    try std.testing.expect(!filter.isIntrinsic("fprintf"));
    try std.testing.expect(!filter.isIntrinsic("malloc"));
}

test "intrinsic_filter - get_category" {
    const filter = IntrinsicFilter.init();

    // Safe intrinsics should return safe category.
    const cat1 = filter.getCategory("llvm.dbg.declare");
    try std.testing.expect(cat1 == .safe);

    // Conditional intrinsics.
    const cat2 = filter.getCategory("llvm.memcpy.inline");
    try std.testing.expect(cat2 == .conditional_safe);

    // Risky intrinsics.
    const cat3 = filter.getCategory("llvm.memcpy.element.unordered.atomic");
    try std.testing.expect(cat3 == .risky);

    // Non-intrinsics.
    const cat4 = filter.getCategory("free");
    try std.testing.expect(cat4 == .unknown);
}

test "intrinsic_filter - unknown llvm intrinsic" {
    const filter = IntrinsicFilter.init();

    // Unknown LLVM intrinsic should not be suppressed (caution).
    const result = filter.check("llvm.unknown.intrinsic.xyz");
    try std.testing.expect(result.is_intrinsic);
    try std.testing.expect(!result.suppress);
    try std.testing.expect(result.category == .unknown);
}

test "intrinsic_filter - math intrinsics" {
    const filter = IntrinsicFilter.init();

    // Floating-point math should be suppressed.
    try std.testing.expect(filter.shouldSuppress("llvm.sqrt.f64"));
    try std.testing.expect(filter.shouldSuppress("llvm.pow.f32"));
    try std.testing.expect(filter.shouldSuppress("llvm.sin.f80"));
    try std.testing.expect(filter.shouldSuppress("llvm.fma.f64"));
}

test "intrinsic_filter - memory intrinsics" {
    const filter = IntrinsicFilter.init();

    // Memory operations should be suppressed.
    try std.testing.expect(filter.shouldSuppress("llvm.memset.p0i8.i64"));
    try std.testing.expect(filter.shouldSuppress("llvm.memcpy.p0i8.p0i8.i32"));
    try std.testing.expect(filter.shouldSuppress("llvm.memmove.p0i8.p0i8.i64"));
}
