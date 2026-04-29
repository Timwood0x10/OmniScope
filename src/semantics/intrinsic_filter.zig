//! LLVM Intrinsic Noise Filter module.
//!
//! This standalone module identifies and filters LLVM compiler-generated
//! intrinsics that are commonly misidentified as FFI issues. These include:
//!
//!   - llvm.threadlocal.address.* - Thread-local storage access
//!   - llvm.lifetime.* - Lifetime markers (optimizer hints)
//!   - llvm.dbg.* - Debug info intrinsics
//!   - llvm.assume - Optimization assumptions
//!   - llvm.expect.* - Branch prediction hints
//!   - llvm.coro.* - Coroutine intrinsics
//!   - llvm.gc.* - Garbage collection intrinsics
//!
//! Key Selling Points:
//!   - Standalone module, no dependencies
//!   - O(1) lookup via prefix matching
//!   - Distinguishes safe intrinsics from risky ones
//!   - Integration-ready with all analysis passes

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

/// Information about an LLVM intrinsic.
pub const IntrinsicInfo = struct {
    /// The full intrinsic name.
    name: []const u8,
    /// Category of this intrinsic.
    category: IntrinsicCategory,
    /// Whether to suppress reports for this intrinsic.
    suppress: bool,
    /// Reason for suppression (if applicable).
    reason: ?[]const u8,
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

/// LLVM Intrinsic Noise Filter.
pub const IntrinsicFilter = struct {
    /// Map of known intrinsics.
    intrinsics: std.StringHashMap(IntrinsicInfo),

    /// Initializes a new intrinsic filter with builtin knowledge.
    pub fn init() IntrinsicFilter {
        var filter = IntrinsicFilter{
            .intrinsics = std.StringHashMap(IntrinsicInfo).init(std.heap.page_allocator),
        };

        // Populate safe intrinsics - these never pose FFI risks.
        filter.addSafe("llvm.threadlocal.address", "Thread-local access, not real FFI");
        filter.addSafe("llvm.lifetime.start", "Lifetime marker, optimizer hint only");
        filter.addSafe("llvm.lifetime.end", "Lifetime marker, optimizer hint only");
        filter.addSafe("llvm.dbg.declare", "Debug info declaration");
        filter.addSafe("llvm.dbg.value", "Debug info value tracking");
        filter.addSafe("llvm.dbg.label", "Debug info label");
        filter.addSafe("llvm.assume", "Optimization assumption hint");
        filter.addSafe("llvm.expect", "Branch prediction hint");
        filter.addSafe("llvm.expect.with.probability", "Branch prediction with probability");
        filter.addSafe("llvm.gcroot", "Garbage collection root marker");
        filter.addSafe("llvm.gcread", "Garbage collection read barrier");
        filter.addSafe("llvm.gcwrite", "Garbage collection write barrier");
        filter.addSafe("llvm.coro.save", "Coroutine save state");
        filter.addSafe("llvm.coro.suspend", "Coroutine suspend");
        filter.addSafe("llvm.coro.resume", "Coroutine resume");
        filter.addSafe("llvm.coro.destroy", "Coroutine destroy");
        filter.addSafe("llvm.coro.free", "Coroutine free");
        filter.addSafe("llvm.coro.begin", "Coroutine begin");
        filter.addSafe("llvm.coro.end", "Coroutine end");
        filter.addSafe("llvm.coro.alloc", "Coroutine allocation");
        filter.addSafe("llvm.coro.id", "Coroutine ID creation");
        filter.addSafe("llvm.coro.size", "Coroutine size query");
        filter.addSafe("llvm.prefetch", "Memory prefetch hint");
        filter.addSafe("llvm.memset", "Memory set intrinsic");
        filter.addSafe("llvm.memset.p0", "Memory set with pointer alignment");
        filter.addSafe("llvm.memcpy", "Memory copy intrinsic");
        filter.addSafe("llvm.memcpy.p0", "Memory copy with pointer alignment");
        filter.addSafe("llvm.memmove", "Memory move intrinsic");
        filter.addSafe("llvm.memmove.p0", "Memory move with pointer alignment");
        filter.addSafe("llvm.trap", "Trap intrinsic (compiler generated)");
        filter.addSafe("llvm.debugtrap", "Debug trap intrinsic");
        filter.addSafe("llvm.sideeffect", "Side effect marker");
        filter.addSafe("llvm.fence", "Memory fence");
        filter.addSafe("llvm.atomic.load", "Atomic load operation");
        filter.addSafe("llvm.atomic.store", "Atomic store operation");
        filter.addSafe("llvm.atomic.rmw", "Atomic read-modify-write");
        filter.addSafe("llvm.cmpxchg", "Compare and exchange");
        filter.addSafe("llvm.invariant.group", "Invariant group marker");
        filter.addSafe("llvm.launder.invariant.group", "Launder invariant group");
        filter.addSafe("llvm.noalias", "No-alias hint");
        filter.addSafe("llvm.nontemporal", "Non-temporal memory hint");
        filter.addSafe("llvm.readcyclecounter", "Read cycle counter");
        filter.addSafe("llvm.readsteadycounter", "Read steady counter");
        filter.addSafe("llvm.readvolatilecounter", "Read volatile counter");
        filter.addSafe("llvm.writecyclecounter", "Write cycle counter");
        filter.addSafe("llvm.stacksave", "Save stack pointer");
        filter.addSafe("llvm.stackrestore", "Restore stack pointer");
        filter.addSafe("llvm.frameaddress", "Get frame address");
        filter.addSafe("llvm.returnaddress", "Get return address");
        filter.addSafe("llvm.smax", "Signed maximum (vectorized)");
        filter.addSafe("llvm.smin", "Signed minimum (vectorized)");
        filter.addSafe("llvm.umax", "Unsigned maximum (vectorized)");
        filter.addSafe("llvm.umin", "Unsigned minimum (vectorized)");
        filter.addSafe("llvm.abs", "Absolute value (vectorized)");
        filter.addSafe("llvm.ceil", "Ceiling operation");
        filter.addSafe("llvm.floor", "Floor operation");
        filter.addSafe("llvm.round", "Round to nearest");
        filter.addSafe("llvm.roundeven", "Round to even");
        filter.addSafe("llvm.trunc", "Truncate operation");
        filter.addSafe("llvm.fabs", "Floating point absolute value");
        filter.addSafe("llvm.fadd", "Floating point addition");
        filter.addSafe("llvm.fsub", "Floating point subtraction");
        filter.addSafe("llvm.fmul", "Floating point multiplication");
        filter.addSafe("llvm.fdiv", "Floating point division");
        filter.addSafe("llvm.frem", "Floating point remainder");
        filter.addSafe("llvm.fma", "Fused multiply-add");
        filter.addSafe("llvm.pow", "Power operation");
        filter.addSafe("llvm.sqrt", "Square root");
        filter.addSafe("llvm.sin", "Sine operation");
        filter.addSafe("llvm.cos", "Cosine operation");
        filter.addSafe("llvm.exp", "Exponential operation");
        filter.addSafe("llvm.log", "Logarithm operation");
        filter.addSafe("llvm.log2", "Base-2 logarithm");
        filter.addSafe("llvm.log10", "Base-10 logarithm");
        filter.addSafe("llvm.eh.typeidfor", "Exception type ID lookup");
        filter.addSafe("llvm.eh.return", "Exception return");
        filter.addSafe("llvm.eh.sjlj.longjmp", "SJLJ longjmp");
        filter.addSafe("llvm.eh.sjlj.setjmp", "SJLJ setjmp");
        filter.addSafe("llvm.eh.sjlj.dispatchsetup", "SJLJ dispatch setup");
        filter.addSafe("llvm.patchpoint", "Patch point intrinsic");
        filter.addSafe("llvm.statepoint", "Statepoint intrinsic");
        filter.addSafe("llvm.experimental.patchpoint", "Experimental patch point");
        filter.addSafe("llvm.experimental.statepoint", "Experimental statepoint");
        filter.addSafe("llvm.call.prefetch", "Call prefetch intrinsic");
        filter.addSafe("llvm.init.trampoline", "Initialize trampoline");
        filter.addSafe("llvm.adjust.trampoline", "Adjust trampoline");
        filter.addSafe("llvm.objc.retain", "Objective-C retain");
        filter.addSafe("llvm.objc.release", "Objective-C release");
        filter.addSafe("llvm.objc.autorelease", "Objective-C autorelease");
        filter.addSafe("llvm.objc.storeStrong", "Objective-C store strong");

        // Conditional safe intrinsics - may indicate issues in specific contexts.
        filter.addConditional("llvm.memcpy.inline", "Inline memory copy, rarely used");
        filter.addConditional("llvm.memmove.inline", "Inline memory move, rarely used");

        // Risky intrinsics - these may indicate real issues.
        filter.addRisky("llvm.memcpy.element.unordered.atomic", "Atomic memcpy - may have memory ordering issues");
        filter.addRisky("llvm.memmove.element.unordered.atomic", "Atomic memmove - may have memory ordering issues");

        return filter;
    }

    /// Release resources held by the intrinsic filter.
    ///
    /// Must be called when the filter is no longer needed to avoid
    /// leaking the internal hash table memory.
    pub fn deinit(filter: *IntrinsicFilter) void {
        filter.intrinsics.deinit();
    }

    /// Adds a safe intrinsic.
    ///
    /// NOTE: OOM is silently ignored because failing to register a single
    /// intrinsic filter rule is non-fatal - the worst case is one extra
    /// false positive report, which is acceptable for a best-effort filter.
    fn addSafe(filter: *IntrinsicFilter, name: []const u8, reason: []const u8) void {
        filter.intrinsics.put(name, IntrinsicInfo{
            .name = name,
            .category = .safe,
            .suppress = true,
            .reason = reason,
        }) catch return; // OOM: skip this rule (non-fatal)
    }

    /// Adds a conditional safe intrinsic.
    ///
    /// NOTE: See addSafe() for OOM handling rationale.
    fn addConditional(filter: *IntrinsicFilter, name: []const u8, reason: []const u8) void {
        filter.intrinsics.put(name, IntrinsicInfo{
            .name = name,
            .category = .conditional_safe,
            .suppress = false,
            .reason = reason,
        }) catch return; // OOM: skip this rule (non-fatal)
    }

    /// Adds a risky intrinsic.
    ///
    /// NOTE: See addSafe() for OOM handling rationale.
    fn addRisky(filter: *IntrinsicFilter, name: []const u8, reason: []const u8) void {
        filter.intrinsics.put(name, IntrinsicInfo{
            .name = name,
            .category = .risky,
            .suppress = false,
            .reason = reason,
        }) catch return; // OOM: skip this rule (non-fatal)
    }

    /// Checks if a function name is an LLVM intrinsic and whether to suppress.
    pub fn check(filter: *IntrinsicFilter, func_name: []const u8) CheckResult {
        // Check if it starts with "llvm." - it's an LLVM intrinsic.
        if (std.mem.startsWith(u8, func_name, "llvm.")) {
            // First check exact match.
            if (filter.intrinsics.get(func_name)) |info| {
                return CheckResult{
                    .is_intrinsic = true,
                    .category = info.category,
                    .suppress = info.suppress,
                    .reason = info.reason orelse "Known intrinsic",
                };
            }

            // Check prefix match for patterns.
            inline for (.{
                "llvm.threadlocal.",
                "llvm.lifetime.",
                "llvm.dbg.",
                "llvm.coro.",
                "llvm.gc.",
                "llvm.assume",
                "llvm.expect",
            }) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) {
                    return CheckResult{
                        .is_intrinsic = true,
                        .category = .safe,
                        .suppress = true,
                        .reason = "Known safe intrinsic prefix: " ++ prefix,
                    };
                }
            }

            // Check for other common safe prefixes.
            inline for (.{
                "llvm.mem",
                "llvm.atomic",
                "llvm.trap",
                "llvm.debugtrap",
                "llvm.prefetch",
                "llvm.fence",
                "llvm.sideeffect",
                "llvm.noalias",
                "llvm.nontemporal",
                "llvm.invariant",
                "llvm.launder",
                "llvm.patchpoint",
                "llvm.statepoint",
                "llvm.eh.",
                "llvm.objc.",
                "llvm.readcyclecounter",
                "llvm.writecyclecounter",
                "llvm.stacksave",
                "llvm.stackrestore",
                "llvm.frameaddress",
                "llvm.returnaddress",
                "llvm.smax",
                "llvm.smin",
                "llvm.umax",
                "llvm.umin",
                "llvm.abs",
                "llvm.ceil",
                "llvm.floor",
                "llvm.round",
                "llvm.roundeven",
                "llvm.trunc",
                "llvm.fabs",
                "llvm.fadd",
                "llvm.fsub",
                "llvm.fmul",
                "llvm.fdiv",
                "llvm.frem",
                "llvm.fma",
                "llvm.pow",
                "llvm.sqrt",
                "llvm.sin",
                "llvm.cos",
                "llvm.exp",
                "llvm.log",
                "llvm.log2",
                "llvm.log10",
            }) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) {
                    return CheckResult{
                        .is_intrinsic = true,
                        .category = .safe,
                        .suppress = true,
                        .reason = "Known safe intrinsic family: " ++ prefix,
                    };
                }
            }

            // Unknown LLVM intrinsic - be cautious.
            return CheckResult{
                .is_intrinsic = true,
                .category = .unknown,
                .suppress = false,
                .reason = "Unknown LLVM intrinsic, treating as potentially risky",
            };
        }

        // Not an LLVM intrinsic.
        return CheckResult{
            .is_intrinsic = false,
            .category = .unknown,
            .suppress = false,
            .reason = "Not an LLVM intrinsic",
        };
    }

    /// Checks if a function should be suppressed entirely.
    pub fn shouldSuppress(filter: *IntrinsicFilter, func_name: []const u8) bool {
        return filter.check(func_name).suppress;
    }

    /// Checks if a function is an LLVM intrinsic.
    pub fn isIntrinsic(filter: *IntrinsicFilter, func_name: []const u8) bool {
        return filter.check(func_name).is_intrinsic;
    }

    /// Gets the category of an intrinsic.
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
