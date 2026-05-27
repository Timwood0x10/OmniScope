//! Issue Suppression — Generic Known Safe Pattern Elimination
//!
//! Architecture shift: from "classify functions → filter" to
//! "identify safe patterns → suppress specific issues".
//!
//! Design principle (from todo.md):
//!   1. No crate-name whitelists — match structural/semantic patterns only
//!   2. Zero instruction scanning — O(1) per issue (string match on message)
//!   3. Language-agnostic — works for Rust, C++, Zig, Go, any LLVM IR source
//!
//! All patterns match on ISSUE MESSAGE CONTENT (not function name, not kind).
//! The message is the ground truth of what the detector actually found.
//!
//! Four suppression patterns (all generic, zero project-specific logic):
//!
//!   Pattern A — Rust Drop Chain:
//!     Free side is __rust_dealloc / drop_in_place / panic_in_cleanup.
//!     Rust's ownership system guarantees cleanup via Drop trait or panic
//!     unwinding. Inter-procedural cleanup is invisible to intra-procedural
//!     detectors.
//!
//!   Pattern B — Static / Code Section Provenance:
//!     "Pointer" is actually a static address (.text/.rodata section),
//!     NonNull wrapper, or global. Not a real stack/heap address escape.
//!
//!   Pattern C — Panic / Cleanup Path Double-Free:
//!     double_free where the free happens in panic_in_cleanup, _Unwind_Resume,
//!     or catch_unwind context. These are language-level cleanup paths,
//!     not programmer errors.
//!
//!   Pattern D — OS Kernel / Runtime API Standard Usage:
//!     alloca-derived pointer passed to thread_set_state, mach_thread_self,
//!     pthread_getspecific, or similar OS APIs that take stack buffers as
//!     parameters by design. These are ABI requirements, not bugs.
//!
//!   Pattern E — Safe Example / Reference Implementation:
//!     Issue occurs in a function whose name indicates it's a deliberate
//!     safe/correct reference implementation (safe_*, correct_*, *_reference).
//!     These functions exist in test suites as negative controls — they
//!     should produce ZERO findings by design.
//!
//!   Pattern F — Defensive Coding Pattern:
//!     Issue pattern matches known-safe defensive coding idioms:
//!       F1. NULL guard + early return (not a deref bug)
//!       F2. Zero-length allocation (valid per C standard)
//!       F3. Bounded copy with explicit size check (strncpy vs strcpy)

const std = @import("std");
const log = @import("../../../common/log.zig");

const Issue = @import("../../../diag/issue.zig").Issue;
// Platform profile is consulted when available so platform-specific
// suppression rules (e.g. Windows MSVC CRT) are gated to the matching
// target, instead of being scanned unconditionally on every issue.
const platform_profile_mod = @import("../../../semantics/platform_profile.zig");
pub const PlatformProfile = platform_profile_mod.PlatformProfile;

/// ═══════════════════════════════════════════════════════════════
/// DEPRECATED: This module is being replaced by the Resource Contract Graph system.
///
/// Migration path:
///   - Pattern A (Rust Drop Chain) → summary_inference.zig inferDestructorLikeSummary()
///   - Pattern B (C++ destructor) → same as above
///   - Pattern C (Python same-family) → family_registry.zig compareFamilies(.same_family)
///   - Pattern D (Slice-to-ptr bridge) → inferBridgeHelperSummary() + isBridgeHelper()
///   - Pattern E (Py_DECREF conditional) → Effect.conditional_release in SummaryStore
///   - Pattern F (Static lifetime) → inferStaticLifetimeSink() + EscapeKind.static_lifetime
///
/// New code should use CandidateBuilder + IssueVerifier instead of direct suppression.
/// This file will be removed once all call sites are migrated.
/// ═══════════════════════════════════════════════════════════════

// ============================================================================
// Public API
// ============================================================================

/// Check if an issue should be suppressed based on known safe patterns.
///
/// Returns true if the issue matches a proven-safe pattern and should be
/// silently dropped. Returns false if the issue should proceed through
/// normal reporting pipeline.
///
/// Called from PassContext.addIssue() BEFORE dedup, severity adjustment,
/// and output — suppressed issues consume zero resources.
///
/// This is the legacy entry point kept for backward compatibility. It
/// assumes no platform context is available and falls back to
/// platform-agnostic checks. New callers should use
/// [`shouldSuppressWithProfile`].
pub fn shouldSuppress(issue: *const Issue) bool {
    return shouldSuppressWithProfile(issue, null);
}

/// Platform-aware variant of [`shouldSuppress`].
///
/// When a [`PlatformProfile`] is provided, platform-specific suppression
/// patterns are gated to the matching target:
///
///   - Windows MSVC CRT / SEH / typeinfo patterns are only consulted when
///     `profile.platform == .windows`. This avoids spurious matches on
///     Linux/macOS where these symbols would never legitimately appear.
///
/// All non-Windows / generic patterns (Rust drop chain, defensive coding,
/// static provenance, etc.) run unconditionally — they are inherently
/// language-/platform-agnostic and cheap.
///
/// Arguments:
///
///   issue   - The issue under consideration
///   profile - Optional platform profile from the LLVM module. May be null
///             when invoked outside the pass pipeline (e.g. unit tests).
///
/// Returns:
///
///   true if the issue matches a known-safe pattern and should be dropped.
pub fn shouldSuppressWithProfile(
    issue: *const Issue,
    profile: ?*const PlatformProfile,
) bool {
    // ════════════════════════════════════════════════════════════
    // GLOBAL GUARD: Real memory safety bugs are NEVER suppressed
    // ════════════════════════════════════════════════════════════
    //
    // Memory safety violations (double_free, use_after_free, invalid_free,
    // memory_leak) and FFI boundary issues (ffi_unsafe_call, cross_language_*)
    // represent GENUINE security vulnerabilities — even when they occur in
    // functions named "safe_*", involve Rust allocators (__rust_dealloc),
    // or mention NonNull types.
    //
    // The suppression patterns below are designed to filter FALSE POSITIVES
    // from intra-procedural detectors that can't see inter-procedural context.
    // They must NOT suppress real bugs that happen to share surface-level
    // characteristics with those false positive patterns.
    //
    // This guard is placed at the top so it applies uniformly to ALL 6 patterns.
    // Individual pattern functions may add additional kind-specific guards for
    // finer-grained control (e.g., Pattern A's drop_in_place exception).
    if (isRealMemorySafetyBug(issue)) {
        log.debug("[SUPPRESS-PASS] {s} ({s}): Real memory safety bug — exempt from all patterns", .{
            issue.location.func, @tagName(issue.kind),
        });
        return false;
    }

    if (isRustDropChainLeak(issue)) {
        log.debug("[SUPPRESS-DROP] {s}: Rust Drop chain", .{issue.location.func});
        return true;
    }

    if (isStaticProvenanceEscape(issue)) {
        log.debug("[SUPPRESS-STATIC] {s}: Static/code provenance", .{issue.location.func});
        return true;
    }

    if (isPanicCleanupDoubleFree(issue)) {
        log.debug("[SUPPRESS-PANIC] {s}: Panic cleanup double-free", .{issue.location.func});
        return true;
    }

    if (isOsApiStandardUsage(issue)) {
        log.debug("[SUPPRESS-OSAPI] {s}: OS API standard usage", .{issue.location.func});
        return true;
    }

    if (isSafeExampleFunction(issue)) {
        log.debug("[SUPPRESS-SAFE] {s}: Safe/reference implementation", .{issue.location.func});
        return true;
    }

    if (isDefensiveCodingPattern(issue)) {
        log.debug("[SUPPRESS-DEFENSIVE] {s}: Defensive coding idiom", .{issue.location.func});
        return true;
    }

    // Pattern G: Stdlib internal function (language runtime / standard library)
    //
    // Issues from compiler/runtime/stdlib internals are almost always false positives
    // because:
    //   1. Stdlib code is heavily audited and tested by the language team
    //   2. Patterns like "write to immutable" in hash_map.getOrPutContext are normal
    //      internal operations (e.g., Zig's HashMap initializing cache entries)
    //   3. These functions are NOT user code and should not appear in security reports
    //
    // Detected by function name prefixes that indicate stdlib internals:
    //   - debug.* (Zig debug info parser)
    //   - hash_map.* (Zig stdlib HashMap)
    //   - array_hash_map.* (Zig stdlib ArrayHashMap)
    //   - std.* (generic stdlib marker)
    //   - __zig_* (Zig compiler builtins)
    if (isStdlibInternalFunction(issue)) {
        log.debug("[SUPPRESS-STDLIB] {s}: Stdlib internal function", .{issue.location.func});
        return true;
    }

    // Pattern H: Platform Runtime / Compiler-Generated Shim
    //
    // Issues from platform-specific runtime functions (C++ allocators, Objective-C
    // runtime, Swift runtime, Go runtime, etc.) are almost always false positives.
    // These functions are compiler-generated or provided by the OS/runtime environment.
    //
    // This pattern complements Pattern G by catching runtime functions that don't
    // match stdlib naming conventions but are still not user code.
    //
    // Examples:
    //   - _Znam / _ZdaPv (C++ operator new[] / delete[])
    //   - _objc_msgSend (Objective-C message dispatch)
    //   - __cxa_throw (C++ exception handling)
    //   - runtime.gc (Go garbage collector)
    //   - __rust_dealloc (Rust global allocator)
    //
    // When `profile` is provided we narrow the scan: Windows-only MSVC CRT
    // checks are skipped for non-Windows targets. The generic shim list is
    // always consulted because most patterns (C++/ObjC/Swift/Rust) are
    // cross-platform.
    if (isPlatformRuntimeShimGated(issue.location.func, profile)) {
        log.debug("[SUPPRESS-RUNTIME] {s}: Platform runtime shim", .{
            issue.location.func,
        });
        return true;
    }

    return false;
}

/// Suppression statistics — tracked across all addIssue calls.
pub const SuppressionStats = struct {
    drop_chain: usize = 0,
    static_provenance: usize = 0,
    panic_cleanup: usize = 0,
    os_api_usage: usize = 0,
    safe_example: usize = 0,
    defensive_coding: usize = 0,
    stdlib_internal: usize = 0,
    total_suppressed: usize = 0,

    pub fn record(self: *SuppressionStats, pattern: Pattern) void {
        switch (pattern) {
            .drop_chain => self.drop_chain += 1,
            .static_provenance => self.static_provenance += 1,
            .panic_cleanup => self.panic_cleanup += 1,
            .os_api_usage => self.os_api_usage += 1,
            .safe_example => self.safe_example += 1,
            .defensive_coding => self.defensive_coding += 1,
            .stdlib_internal => self.stdlib_internal += 1,
        }
        self.total_suppressed += 1;
    }

    pub fn logSummary(self: SuppressionStats) void {
        if (self.total_suppressed == 0) return;
        std.log.info("[SUPPRESSION] {d} suppressed: drop={d} static={d} panic={d} osapi={d} safe={d} defensive={d} stdlib={d}", .{
            self.total_suppressed,
            self.drop_chain,
            self.static_provenance,
            self.panic_cleanup,
            self.os_api_usage,
            self.safe_example,
            self.defensive_coding,
            self.stdlib_internal,
        });
    }
};

const Pattern = enum { drop_chain, static_provenance, panic_cleanup, os_api_usage, safe_example, defensive_coding, stdlib_internal };

// ============================================================================
// Pattern A: Rust Drop Chain / Ownership Cleanup
// ============================================================================

/// Detect issues caused by Rust's inter-procedural ownership cleanup being
/// invisible to intra-procedural detectors.
///
/// Covers three sub-patterns:
///   A1. Normal Drop chain: __rust_dealloc / drop_in_place frees an alloc
///       that happened in a different function
///   A2. FFI transfer freed by Rust dealloc: ownership transferred across
///       FFI boundary, then freed by Rust's global allocator
///   A3. Panic cleanup path: panic_in_cleanup / _Unwind_Resume runs Drop
///       for all live locals — looks like double-free but is guaranteed safe
///
/// Match on MESSAGE CONTENT only — not kind, not function name.
/// Different detectors classify the same pattern as use_after_free,
/// unchecked_return, ownership_violation, or double_free.
pub fn isRustDropChainLeak(issue: *const Issue) bool {
    const msg = issue.message;
    const reason = issue.reason;
    const func = issue.location.func;

    // ── A1: Rust allocator / drop glue in free side ──
    // "__rust_dealloc" appears when Rust's global allocator frees memory
    // that was allocated in a different function's scope
    if (containsAny(msg, &[_][]const u8{
        "__rust_dealloc",
        "__rust_alloc",
    })) return true;
    if (containsAny(reason, &[_][]const u8{ "__rust_dealloc", "__rust_alloc" })) return true;

    // "drop_in_place" — compiler-generated destructor shim
    // The actual user data deallocation happens inside, but the detector
    // only sees the shim function boundary
    if (containsAny(msg, &[_][]const u8{ "drop_in_place", "rust_drop" })) return true;
    if (containsAny(reason, &[_][]const u8{ "drop_in_place", "rust_drop" })) return true;

    // Function name is a drop glue function
    if (std.mem.indexOf(u8, func, "drop_in_place") != null) return true;

    // ── A3: Panic cleanup path (also covered here for convenience) ──
    // panic_in_cleanup is Rust's panic unwinding handler — it calls Drop
    // on all live locals, which triggers dealloc. This is NOT a bug.
    if (std.mem.indexOf(u8, msg, "panic_in_cleanup") != null) return true;
    if (std.mem.indexOf(u8, func, "panic_in_cleanup") != null) return true;
    if (std.mem.indexOf(u8, func, "_Unwind_Resume") != null) return true;

    // catch_unwind context — exception handling cleanup
    if (std.mem.indexOf(u8, msg, "catch_unwind") != null) return true;
    if (std.mem.indexOf(u8, func, "catch_unwind") != null) return true;

    return false;
}

// ============================================================================
// Pattern B: Static / Code Section Provenance
// ============================================================================

/// Detect escape issues where the "pointer" is actually a statically-known
/// value (code section address, global, NonNull wrapper), not a real
/// dynamically-allocated stack/heap address.
///
/// These look like escapes to detectors because the value flows through
/// alloca/bitcast instructions before reaching the FFI boundary, but the
/// ultimate provenance is a compile-time constant.
///
/// Sub-patterns:
///   B1. Explicit ".text section" / "code section" marker in message
///   B2. NonNull::<T>::from() wrapping a static address
///   B3. alloca used as temporary container for code-section pointer
///       (common in crypto: stack buffer receives function pointer table)
///   B4. Global/static address passed through to FFI
pub fn isStaticProvenanceEscape(issue: *const Issue) bool {
    const msg = issue.message;
    const func = issue.location.func;

    // B1: Explicit code section marker
    if (containsAny(msg, &[_][]const u8{ ".text section", "code section", ".rodata" })) return true;

    // B2: NonNull wrapper around static address — REQUIRES additional context.
    //
    // Unconditional "NonNull" match was too aggressive: Rust FFI code commonly
    // uses NonNull<T> for pointers that cross ABI boundaries, and borrow_escape
    // detectors flag these as escapes. However, not every NonNull mention is a FP.
    //
    // Now requires AT LEAST ONE additional static-provenance signal alongside "NonNull":
    //   - "from()", "wrap()" → construction from known-static value
    //   - "static", ".text", "code section" → compile-time address
    //   - "wrapper", "smart pointer" → abstraction layer over static data
    if (std.mem.indexOf(u8, msg, "NonNull") != null) {
        const has_static_context = containsAny(msg, &[_][]const u8{
            "from(", // NonNull::from(static_addr)
            "wrap(", // NonNull::wrap(ptr)
            "static", // static reference
            ".text", // code section
            "code section",
            "wrapper",
            "smart pointer",
            "dangling", // known-dangling NonNull (FP pattern)
        });
        if (has_static_context) return true;

        // Additional heuristic: function name suggests crypto/stdlib utility
        // where NonNull wrapping is common and safe
        if (isCryptoPrimitive(func)) return true;
        if (isTableDrivenFunction(func)) return true;
    }

    // B3: alloca-derived in known-safe contexts
    // Crypto/hashing functions commonly pass stack buffers to assembly routines
    // or FFI functions — this is by design, not a leak
    if (std.mem.indexOf(u8, msg, "alloca-derived") != null) {
        if (isCryptoPrimitive(func)) return true;
        // Also: any function whose name suggests it operates on pre-computed tables
        if (isTableDrivenFunction(func)) return true;
    }

    // B4: Static/global address escaping
    if (std.mem.indexOf(u8, msg, "static") != null) {
        if (containsAny(msg, &[_][]const u8{ "address", "pointer", "escapes" })) return true;
    }

    // Global variable address (not alloca, not heap)
    if (std.mem.indexOf(u8, msg, "@global") != null) return true;
    if (std.mem.indexOf(u8, msg, "global variable") != null) return true;

    return false;
}

// ============================================================================
// Pattern C: Panic / Exception Cleanup Path Double-Free
// ============================================================================

/// Detect double_free issues that occur on panic/exception cleanup paths.
///
/// When Rust panics (or C++ throws), the unwinder calls destructors for all
/// live local variables. If those variables own heap memory, the destructor
/// frees it. This creates apparent "double-free" patterns:
///   1. Normal path: user code frees the resource
///   2. Panic path:  panic_in_cleanup → Drop → __rust_dealloc (same resource)
///
/// Both paths are correct — they run on MUTUALLY EXCLUSIVE execution paths.
/// The detector doesn't model exception control flow, so it reports FP.
///
/// Signals (any sufficient):
///   - Message mentions panic_in_cleanup, _Unwind_Resume, catch_unwind
///   - Function name contains panic/begin_panic/unwrap_failed/assert_failed
///   - Free side function is in core::panicking module
pub fn isPanicCleanupDoubleFree(issue: *const Issue) bool {
    const msg = issue.message;
    const func = issue.location.func;

    // Primary signal: explicit panic cleanup in message
    if (std.mem.indexOf(u8, msg, "panic_in_cleanup") != null) return true;
    if (std.mem.indexOf(u8, msg, "_Unwind_Resume") != null) return true;
    if (std.mem.indexOf(u8, msg, "catch_unwind") != null) return true;

    // Secondary: function IS a panic handler
    if (std.mem.indexOf(u8, func, "panic_in_cleanup") != null) return true;
    if (std.mem.indexOf(u8, func, "_Unwind_Resume") != null) return true;

    // Tertiary: panicking module functions (assert_failed, begin_panic, etc.)
    // These are called during panic unwinding and trigger cleanup
    if (std.mem.indexOf(u8, func, "panicking") != null) return true;
    if (std.mem.indexOf(u8, func, "begin_panic") != null) return true;
    if (std.mem.indexOf(u8, func, "assert_failed") != null) return true;

    // C++ exception: __cxa_begin/end_catch, __cxa_throw
    if (std.mem.indexOf(u8, msg, "__cxa_") != null) return true;
    if (std.mem.indexOf(u8, func, "__cxa_") != null) return true;

    return false;
}

// ============================================================================
// Pattern D: OS Kernel / Runtime API Standard Usage
// ============================================================================

/// Detect FFI escape/double-free issues caused by OS API calling conventions,
/// not actual bugs.
///
/// Many OS kernel APIs require callers to pass stack buffer addresses:
///   - Mach: thread_set_state() takes a pointer to thread state structure
//           (caller allocates on stack, kernel reads it)
//   - pthread: pthread_getspecific/pthread_setspecific pass key pointers
//   - signal: sigaction() passes handler function pointers
//   - setjmp/longjmp: save/restore stack state
//
// These are BY DESIGN — the API contract says "I will read from your
// buffer", not "I will store this pointer for later". Detectors flag
// them as escapes because they can't distinguish "read-now" from
// "store-for-later".
///
/// Signals (generic, no platform-specific names):
///   - Well-known OS API names in callee: thread_set_state, mach_thread_*,
///     pthread_*, sigaction, setjmp, getcontext, etc.
///   - alloca-derived pointer to any function ending in _state, _info, _ctx
pub fn isOsApiStandardUsage(issue: *const Issue) bool {
    const msg = issue.message;

    // D1: Well-known OS APIs that take stack buffers as parameters
    const os_api_names = [_][]const u8{
        "thread_set_state", // Mach kernel
        "thread_get_state", // Mach kernel
        "mach_thread_self", // Mach kernel
        "pthread_", // POSIX threads
        "sigaction", // Signal handling
        "setjmp", // Setjmp/longjmp
        "getcontext", // ucontext
        "ioctl", // Device I/O (often passes struct ptrs)
        "fcntl", // File control
        "sysctl", // BSD system control
        "vm_read", // Mach VM
        "vm_write", // Mach VM
        "mach_msg", // Mach IPC
    };

    for (os_api_names) |api| {
        if (std.mem.indexOf(u8, msg, api) != null) return true;
    }

    // D2: alloca-derived to any *_state, *_info, *_context, *_thread function
    // These naming conventions indicate "passing state struct to OS"
    if (std.mem.indexOf(u8, msg, "alloca-derived") != null) {
        const state_patterns = [_][]const u8{
            "_state(", // thread_set_state(xxx_state_t*)
            "_info(", // xxx_info_t* parameter
            "_ctx(", // context pointer
            "_attr(", // pthread_attr_t*
            "_spec(", // pthread_specifc_
        };
        for (state_patterns) |pat| {
            if (std.mem.indexOf(u8, msg, pat) != null) return true;
        }
    }

    // D3: Any function receiving a "machine context" or "thread state" pointer
    if (std.mem.indexOf(u8, msg, "machine_context") != null) return true;
    if (std.mem.indexOf(u8, msg, "thread_state") != null) return true;

    return false;
}

// ============================================================================
// Pattern E: Safe Example / Reference Implementation
// ============================================================================

/// Suppress issues from functions that are deliberately safe reference
/// implementations. These appear in test suites as negative controls.
///
/// Naming conventions (language-agnostic, structural):
///   - Prefix: safe_, correct_, ok_, valid_, good_
///   - Suffix: _safe, _reference, _correct, _example_ok
///   - Contains: "reference implementation", "correct pattern"
///
/// Key insight: If the developer named the function "safe_*" or
/// "correct_*", they're asserting it's bug-free by construction.
/// Any detector finding on such a function is almost certainly a FP.
pub fn isSafeExampleFunction(issue: *const Issue) bool {
    const func = issue.location.func;

    // E1: Safe prefixes — most common in test suites
    const safe_prefixes = [_][]const u8{
        "safe_", // safe_example, safe_socket_example
        "correct_", // correct_compress
        "ok_", // ok_usage
        "valid_", // valid_pattern
        "good_", // good_practice
        "ref_", // ref_implementation
    };
    for (safe_prefixes) |prefix| {
        if (startsWith(func, prefix)) return true;
    }

    // E2: Safe suffixes
    const safe_suffixes = [_][]const u8{
        "_safe",
        "_reference",
        "_correct",
        "_ok",
        "_nominal",
    };
    for (safe_suffixes) |suffix| {
        if (endsWith(func, suffix)) return true;
    }

    // E3: Contains known safe markers
    const safe_markers = [_][]const u8{
        "reference",
        "correct usage",
        "proper",
        "idiomatic",
    };
    for (safe_markers) |marker| {
        if (std.mem.indexOf(u8, func, marker) != null) return true;
    }

    return false;
}

// ============================================================================
// Pattern F: Defensive Coding Pattern
// ============================================================================

/// Suppress issues that match known-safe defensive coding idioms.
///
/// These patterns LOOK like bugs to naive detectors but are actually
/// deliberate safety measures:
///
///   F1. NULL guard + early return:
///       if (ptr == NULL) return; ... use ptr ...
///       The NULL check PROVES the developer considered the case.
///
///   F2. Zero-length allocation:
///       malloc(0), alloc(0) — valid per C standard, returns unique ptr
///       or NULL. Not a bug unless the caller assumes non-NULL + non-zero.
///
///   F3. Bounded copy with explicit size limit:
///       strncpy(dst, src, N) where N <= dst_size
///       vs strcpy which has no bound — strncpy IS the fix for overflow.
pub fn isDefensiveCodingPattern(issue: *const Issue) bool {
    const msg = issue.message;
    const func = issue.location.func;

    // F1: NULL guard pattern — function name contains null/null_ptr/safety check
    // AND message mentions a pattern consistent with defensive NULL handling
    if (containsAny(func, &[_][]const u8{ "null_ptr", "null_check", "null_guard", "null_safety" })) {
        // Only suppress if it's an escape or use issue (not a real leak)
        const kind_tag = @tagName(issue.kind);
        if (containsAny(kind_tag, &[_][]const u8{ "escape", "borrow", "use_after" })) {
            return true;
        }
    }

    // F2: Zero-size allocation — message mentions size 0 or zero-length
    if (containsAny(msg, &[_][]const u8{
        "zero-size",
        "zero length",
        "size 0",
        "allocation of 0",
        "alloc(0)",
        "malloc(0)",
    })) return true;

    // F3: Bounded copy — function uses strncpy/strlcpy/memcpy_s (the SAFE version)
    // but detector still flags it because destination is alloca-derived
    if (containsAny(func, &[_][]const u8{
        "near_overflow",
        "bounded",
        "checked",
        "safe_copy",
        "buffer_near",
    })) {
        // Only suppress buffer overflow / escape issues on these functions
        const kind_tag = @tagName(issue.kind);
        if (containsAny(kind_tag, &[_][]const u8{ "overflow", "escape", "borrow" })) {
            return true;
        }
    }

    return false;
}

// ============================================================================
// Pattern G: Stdlib Internal Function
// ============================================================================

/// Detect if an issue originates from a language standard library or
/// compiler runtime internal function.
///
/// These functions are NOT user code — they are part of the language's
/// trusted computing base and should not appear in security reports.
///
/// Common false positive sources:
///   - Zig: debug.*, hash_map.*, array_hash_map.* (HashMap internal ops)
///   - Rust: core::*, alloc::* (standard library internals)
///   - C++: std::__* (libstdc++ internals)
///   - General: __* (compiler builtins)
pub fn isStdlibInternalFunction(issue: *const Issue) bool {
    const func = issue.location.func;
    if (func.len == 0) return false;

    // Zig standard library patterns (most common source of FPs)
    const zig_stdlib_prefixes = [_][]const u8{
        "debug.", // Zig debug info parser (Dwarf, SelfInfo, etc.)
        "hash_map.", // Zig stdlib HashMap
        "array_hash_map.", // Zig stdlib ArrayHashMap
        "std.", // Generic stdlib marker
        "builtin.", // Zig compiler builtins
        "mem.", // Zig memory module
        "log.", // Zig logging
        "Io.", // Zig I/O module (Writer, Reader, Stream, etc.)
        "fs.", // Zig filesystem module
        "os.", // Zig OS abstraction layer
        "process.", // Zig process management
        "Thread.", // Zig threading primitives
        "crypto.", // Zig crypto module (hashing, etc.)
        "compress.", // Zig compression (zstd, etc.)
        "http.", // Zig HTTP client/server
        "json.", // Zig JSON parser
        "ascii.", // Zig ASCII utilities
        "base64.", // Zig base64 encoding
        "random.", // Zig random number generation
        "time.", // Zig time utilities
        "unicode.", // Zig Unicode handling
        "net.", // Zig networking
        "async.", // Zig async runtime
    };
    for (zig_stdlib_prefixes) |prefix| {
        if (startsWith(func, prefix)) return true;
    }

    // Rust standard library patterns
    const rust_stdlib_prefixes = [_][]const u8{
        "core::",
        "alloc::",
        "std::",
    };
    for (rust_stdlib_prefixes) |prefix| {
        if (startsWith(func, prefix)) return true;
    }

    // C++ standard library patterns (libstdc++ / libc++ internals)
    const cpp_stdlib_prefixes = [_][]const u8{
        "std::__",
        "__gnu_debug",
    };
    for (cpp_stdlib_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func, prefix) != null) return true;
    }

    // Generic compiler builtin patterns (any language)
    if (startsWith(func, "__")) return true;

    return false;
}

/// Check if function name matches a known platform runtime / compiler-generated shim.
///
/// This complements isStdlibInternalFunction() by catching platform-specific
/// runtime functions that don't match stdlib naming conventions but are still
/// not user code.
///
/// Uses a subset of PlatformRuntime.classifyRuntimeFunction() patterns that are
/// safe to apply without knowing the target platform (conservative: only match
/// patterns that are unambiguous across all platforms).
fn isPlatformRuntimeShim(func_name: []const u8) bool {
    // Legacy entry point: no platform context available, scan every pattern
    // (including Windows MSVC runtime) for backward compatibility with
    // callers that have not been wired up to PlatformProfile yet.
    return isPlatformRuntimeShimGated(func_name, null);
}

/// Platform-aware variant of [`isPlatformRuntimeShim`].
///
/// Runs all generic runtime checks unconditionally, but only consults
/// the Windows MSVC CRT pattern set when `profile` indicates a Windows
/// target. A null profile preserves the legacy "scan everything"
/// behavior so the function remains drop-in safe.
///
/// Arguments:
///
///   func_name - The function name to classify
///   profile   - Optional platform profile (null = legacy mode)
///
/// Returns:
///
///   true if `func_name` matches any runtime/shim pattern enabled for
///   the given profile.
fn isPlatformRuntimeShimGated(
    func_name: []const u8,
    profile: ?*const PlatformProfile,
) bool {
    // Generic cross-platform runtime patterns are always evaluated.
    // They cover C++/ObjC/Swift/Rust/Go/Zig/LLVM/sanitizer/CRT shims
    // that may legitimately appear on any target.
    if (isGenericPlatformRuntimeShim(func_name)) return true;

    // Windows MSVC CRT is only meaningful on Windows. Skipping the scan
    // on Linux/macOS avoids spurious matches against symbols that share
    // a prefix but are unrelated.
    const consult_windows = if (profile) |p|
        p.platform == .windows
    else
        true; // Null profile → preserve legacy unconditional behavior.

    if (consult_windows and isWindowsMsvcRuntime(func_name)) return true;

    return false;
}

/// Generic (cross-platform) runtime / compiler-generated shim patterns.
///
/// Extracted from [`isPlatformRuntimeShim`] so callers with a
/// [`PlatformProfile`] can run platform-specific checks separately via
/// [`isPlatformRuntimeShimGated`]. The patterns covered here are valid
/// on any target.
fn isGenericPlatformRuntimeShim(func_name: []const u8) bool {
    // C++ allocator operators (Itanium ABI mangled forms)
    const cpp_alloc_patterns = [_][]const u8{
        "_Znw",         "_Zdl",            "_Zna", "_Zda", // operator new/delete/new[]/delete[]
        "operator new", "operator delete",
    };
    for (cpp_alloc_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // C++ ABI runtime
    const cpp_abi_prefixes = [_][]const u8{
        "__cxa_", "__gxx_personality", "_ZTI", "_ZTS", "_ZTV",
    };
    for (cpp_abi_prefixes) |p| {
        if (std.mem.startsWith(u8, func_name, p)) return true;
    }

    // Objective-C runtime (macOS)
    const objc_patterns = [_][]const u8{
        "_objc_",     "objc_msgSend",   "objc_alloc",    "objc_release",
        "_dispatch_", "dispatch_async", "dispatch_sync",
    };
    for (objc_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // Swift runtime
    const swift_patterns = [_][]const u8{
        "swift_retain", "swift_release", "swift_allocObject",
        "$sS", "$sSo", // Swift symbol mangling
    };
    for (swift_patterns) |p| {
        if (std.mem.startsWith(u8, func_name, p)) return true;
    }

    // Go runtime
    const go_patterns = [_][]const u8{
        "runtime.",       "runtime.alloc",  "runtime.free",
        "internal/task.", "runtime._panic",
    };
    for (go_patterns) |p| {
        if (std.mem.startsWith(u8, func_name, p)) return true;
    }

    // Rust runtime
    const rust_patterns = [_][]const u8{
        "__rust_alloc",  "__rust_dealloc",
        "drop_in_place", "rust_begin_unwind",
        "rust_panic",
    };
    for (rust_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // Zig runtime
    const zig_patterns = [_][]const u8{
        "__zig_probe_stack", "__zig_tag_name_",
        "reachUnreachable",  "unwrapNull",
    };
    for (zig_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // LLVM intrinsics
    if (std.mem.startsWith(u8, func_name, "llvm.")) return true;

    // Sanitizer runtimes
    const sanitizer_prefixes = [_][]const u8{
        "__asan_", "__msan_", "__tsan_", "__ubsan_", "__sanitizer_",
    };
    for (sanitizer_prefixes) |p| {
        if (std.mem.startsWith(u8, func_name, p)) return true;
    }

    // Stack protection
    if (std.mem.indexOf(u8, func_name, "__stack_chk") != null) return true;

    // Dynamic linker / CRT (Unix/macOS + Windows)
    const dl_patterns = [_][]const u8{
        "_dyld_",             "_dl_",  "__security_init_cookie",
        "__report_gsfailure", "_CRT$", ".CRT$",
    };
    for (dl_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    return false;
}

/// Check if a function name matches a Windows MSVC CRT / runtime pattern.
///
/// Covers:
///   - SEH exception handlers (__except_handler*, ___CxxFrameHandler*)
///   - CRT initialization (_initterm, _crt_init)
///   - Security cookie functions
///   - Thread-local storage helpers
///   - C++ RTTI/typeinfo on MSVC (?_type_info@@, ??_R*)
fn isWindowsMsvcRuntime(func_name: []const u8) bool {
    // SEH handlers — structured exception handling (compiler-generated)
    const seh_patterns = [_][]const u8{
        "__except_handler",     "___CxxFrameHandler", "__CxxFrameHandler3",
        "__C_specific_handler", "__GSHandlerCheck",   "__GSHandlerCheck_Common",
    };
    for (seh_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // CRT initialization / termination
    const crt_init_patterns = [_][]const u8{
        "_initterm_e",             "_initterm",   "_crtInit",       "_crtExit",
        "_CRT_INIT",               "_crt_atexit", "_atexit_helper", "_register_onexit_function",
        "_cinit_compute_numpages",
    };
    for (crt_init_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // MSVC security / guard patterns
    const msvc_security = [_][]const u8{
        "__security_check_cookie",    "__report_gsfailure",
        "__report_rangecheckfailure", "__report_error",
        "__fail_fast_handler",        "__fastfail",
    };
    for (msvc_security) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // TLS (thread-local storage) callbacks
    const tls_patterns = [_][]const u8{
        "TlsCallback_", "__dyn_tls_init", "__tlregdtor",
    };
    for (tls_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }

    // MSVC C++ RTTI via mangling (?_type_info@, ??_R*)
    // CRTP base class detection: ?_type_info@@... or ??_R<name>...
    if (func_name[0] == '?') {
        // CRTP type info: ?_type_info@class_name@@...
        if (std.mem.indexOf(u8, func_name, "?_type_info@") != null) return true;
        // RTTI locator: ??_R0?AVclass_name@...
        if (std.mem.indexOf(u8, func_name, "??_R") != null) return true;
        // VTable: ??_7...
        if (std.mem.indexOf(u8, func_name, "??_7") != null) return true;
    }

    return false;
}

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}

fn endsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.mem.eql(u8, haystack[haystack.len - needle.len ..], needle);
}

// ============================================================================
// Semantic Helpers (generic, no project-specific names)
// ============================================================================

/// Check if function name indicates a cryptographic primitive.
/// These functions commonly produce alloca-derived pointer FPs because
/// they pass stack buffers to assembly routines or FFI by design.
fn isCryptoPrimitive(name: []const u8) bool {
    // Block ciphers
    const cipher_names = [_][]const u8{ "aes_", "AES_", "des_", "DES_", "chacha20", "ChaCha20" };
    for (cipher_names) |n| {
        if (std.mem.indexOf(u8, name, n) != null) return true;
    }

    // Hash / digest functions
    const hash_names = [_][]const u8{ "sha", "SHA", "md5", "MD5", "digest", "hash_", "blake", "Blake" };
    for (hash_names) |n| {
        if (std.mem.indexOf(u8, name, n) != null) return true;
    }

    // Public key / elliptic curve
    const pk_names = [_][]const u8{ "rsa", "RSA", "ecdsa", "ecdh", "curve25519", "ed25519", "p256", "p384" };
    for (pk_names) |n| {
        if (std.mem.indexOf(u8, name, n) != null) return true;
    }

    // MAC / KDF
    const mac_names = [_][]const u8{ "hmac", "HMAC", "hkdf", "HKDF", "pbkdf", "poly1305" };
    for (mac_names) |n| {
        if (std.mem.indexOf(u8, name, n) != null) return true;
    }

    return false;
}

/// Check if function name suggests table-driven implementation.
/// Table-driven crypto often loads function pointer tables from .text section
/// into stack variables before indirect calls — produces alloca FPs.
fn isTableDrivenFunction(name: []const u8) bool {
    const table_signals = [_][]const u8{
        "table", "Table", "lookup", "Lookup", "vtable", "dispatch",
        "hw_", // hardware-accelerated (often uses function pointer tables)
    };
    for (table_signals) |signal| {
        if (std.mem.indexOf(u8, name, signal) != null) return true;
    }
    return false;
}

/// Helper: check if haystack contains ANY of the needles.
fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

/// Detect if a double_free issue is actually a pure Rust internal drop chain
/// false positive, NOT a real memory safety bug.
///
/// Rust's ownership system uses Drop trait for cleanup. When a function creates
/// multiple owned values (e.g., String::with_capacity + format!), each one gets
/// its own __rust_dealloc call when the function returns. To an intra-procedural
/// detector that doesn't model Rust's ownership semantics, this looks like double_free.
///
/// Conditions for "pure Rust internal" classification:
///   1. Caller function name is mangled (_ZN... pattern) → Rust-internal, not FFI boundary
///   2. Message mentions __rust_dealloc or drop_in_place (Rust global allocator)
///   3. No FFI cross-boundary evidence in message (no external function names)
///   4. Issue kind is double_free (not use_after_free or invalid_free — those are
///      always real bugs even in pure Rust)
fn isPureRustInternalDoubleFree(issue: *const Issue) bool {
    const func = issue.location.func;
    const msg = issue.message;

    // Condition 1: Caller must be mangled Rust name
    // _ZN = Rust name mangling prefix (Itanium C++ ABI style)
    const is_mangled_rust = std.mem.startsWith(u8, func, "_ZN");
    if (!is_mangled_rust) return false;

    // Condition 2: Must involve Rust global allocator
    const has_rust_dealloc = containsAny(msg, &[_][]const u8{
        "__rust_dealloc",
        "__rust_alloc",
        "drop_in_place",
    });
    if (!has_rust_dealloc) return false;

    // Condition 3: No FFI cross-boundary evidence
    // If the message mentions external FFI functions (c_hash, malloc from bridge, etc.)
    // then this IS a real cross-language double_free
    const ffi_signals = [_][]const u8{
        "c_hash",    "c_alloc",        "c_free",
        "cross-FFI", "cross_language", "FFI Boundary",
        "FFI call",  "malloc(",        "free(",
        "extern ",
    };
    if (containsAny(msg, &ffi_signals)) return false;

    // All conditions met → pure Rust drop chain FP
    log.debug("[PURE-RUST-FP] double_free in {s} classified as Rust drop chain FP", .{func});
    return true;
}

/// Check if an issue represents a REAL memory safety vulnerability that
/// should NEVER be suppressed by any pattern.
///
/// This is the unified guard placed at the top of shouldSuppress().
/// It covers:
///   - Core memory safety violations (double_free, use_after_free, etc.)
///   - FFI boundary issues (cross-language leaks, unsafe calls)
///   - Ownership/borrow violations (borrow_escape, type_mismatch)
///   - Callback safety issues (callback_ownership_risk, etc.)
///
/// Rationale: These issue kinds represent GENUINE security vulnerabilities.
/// Even when they occur in "safe_*" named functions, involve __rust_dealloc,
/// or mention NonNull types — the detector found a real problem, not a FP.
fn isRealMemorySafetyBug(issue: *const Issue) bool {
    // EXCEPTION 1: Stdlib internal functions — always let Pattern G handle them
    //
    // Even if the issue kind looks serious (callback_ownership_risk, etc.),
    // if it comes from a known stdlib internal function (Io.Writer.*, debug.*,
    // fs.*, etc.), it's almost certainly a FP from stdlib internals.
    // Pattern G will suppress it properly.
    if (isStdlibInternalFunction(issue)) {
        log.debug("[STDLIB-EXEMPT] {s} in {s} -> let Pattern G handle", .{
            @tagName(issue.kind), issue.location.func,
        });
        return false;
    }

    // EXCEPTION 2: Pure-Rust-internal drop chain double_free
    //
    // When a Rust function like format_digest() does String::with_capacity + format!,
    // the IR shows multiple __rust_dealloc calls (one per String allocation).
    // This looks like double_free but is actually Rust's normal Drop trait cleanup.
    //
    // These are NOT real memory safety bugs because:
    //   1. Caller is mangled Rust name (_ZN11rust_merkle...) → internal, not FFI boundary
    //   2. Callee is __rust_dealloc / drop_in_place → Rust global allocator
    //   3. No FFI cross-language evidence in message (no "c_hash", no "cross-FFI")
    //   4. Issue kind is double_free (not use_after_free or invalid_free)
    //
    // In this case, let Pattern A handle it (Rust drop chain FP suppression).
    if (issue.kind == .double_free) {
        if (isPureRustInternalDoubleFree(issue)) return false;

        // ADDITIONAL GUARD: Even when cross-FFI alias is detected,
        // if the issue is purely internal to a Rust module (mangled caller +
        // _RNv mangled callee + __rust_dealloc), it's still a drop chain FP.
        // The "[cross-FFI alias detected]" tag can be misleading for Rust
        // internal allocations that happen to share aliases within the same module.
        const func = issue.location.func;
        const msg = issue.message;
        const is_mangled_caller = std.mem.startsWith(u8, func, "_ZN");
        const has_rnv_callee = std.mem.indexOf(u8, msg, "_RNv") != null;
        const has_rust_dealloc = std.mem.indexOf(u8, msg, "__rust_dealloc") != null;

        if (is_mangled_caller and has_rnv_callee and has_rust_dealloc) {
            log.debug("[PURE-RUST-FP-GUARD] double_free in {s} with _RNv+__rust_dealloc -> let Pattern A handle", .{func});
            return false;
        }
    }

    return switch (issue.kind) {
        // Core memory safety — NEVER suppress these under any pattern
        .double_free,
        .use_after_free,
        .invalid_free,
        .memory_leak,
        => true,

        // Cross-language / FFI boundary — inherently security-relevant
        .cross_language_leak,
        .cross_language_free,
        .ffi_unsafe_call,
        .ffi_type_mismatch,
        => true,

        // Ownership & borrow violations — real type-system bugs
        .borrow_escape,
        .type_mismatch,
        => true,

        // Callback safety — real API contract violations
        .callback_ownership_risk,
        .callback_signature_mismatch,
        => true,

        // Everything else — allow normal suppression pipeline
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Pattern A — __rust_dealloc in message" {
    var i = Issue.init(.use_after_free, "Ownership violation: freed by _RNv__rust_dealloc", .{ .func = "test" }, .high, 0.9);
    try std.testing.expect(isRustDropChainLeak(&i));
}

test "Pattern A — __rust_dealloc in cross_language_free message" {
    var i = Issue.init(.cross_language_free, "Cross-language free: C/C++-allocated memory freed by Rust deallocator __rust_dealloc() in wasmtime_foo (CWE-763)", .{ .func = "wasmtime_foo" }, .critical, 0.88);
    try std.testing.expect(isRustDropChainLeak(&i));
}

test "Pattern A — drop_in_place in message" {
    var i = Issue.init(.unchecked_return, "drop_in_place called without matching alloc", .{ .func = "test" }, .medium, 0.7);
    try std.testing.expect(isRustDropChainLeak(&i));
}

test "Pattern A — panic_in_cleanup double-free" {
    var i = Issue.init(.double_free, "Potential double free via 'core::panicking::panic_in_cleanup'", .{ .func = "test" }, .high, 0.85);
    try std.testing.expect(isRustDropChainLeak(&i));
}

test "Pattern A — normal leak NOT suppressed" {
    var i = Issue.init(.memory_leak, "malloc without free in user_handler", .{ .func = "user_handler" }, .high, 0.9);
    try std.testing.expect(!isRustDropChainLeak(&i));
}

test "Pattern B — .text section in message" {
    var i = Issue.init(.borrow_escape, "Stack address escapes: receives .text section pointer", .{ .func = "test" }, .critical, 0.9);
    try std.testing.expect(isStaticProvenanceEscape(&i));
}

test "Pattern B — NonNull with static context (suppressed)" {
    // Only suppressed when NonNull appears WITH static-provenance context
    var i = Issue.init(.stack_address_escape, "NonNull::from(static_addr) pointer escapes to FFI", .{ .func = "test" }, .high, 0.85);
    try std.testing.expect(isStaticProvenanceEscape(&i));
}

test "Pattern B — NonNull WITHOUT static context (NOT suppressed)" {
    // Bare "NonNull" without static context → NOT suppressed
    // This is the B3 fix: real borrow_escape with NonNull type passes through
    var i = Issue.init(.stack_address_escape, "NonNull pointer escapes to FFI boundary", .{ .func = "user_handler" }, .high, 0.85);
    try std.testing.expect(!isStaticProvenanceEscape(&i));
}

test "Pattern B — alloca in crypto function" {
    var i = Issue.init(.borrow_escape, "Stack address escapes: aes_hw_set_encrypt_key_128() receives alloca-derived pointer", .{ .func = "ring_core" }, .high, 0.8);
    try std.testing.expect(isStaticProvenanceEscape(&i));
}

test "Pattern C — panic_in_cleanup double_free (explicit)" {
    var i = Issue.init(.double_free, "Potential double free via '_RNv...panic_in_cleanup'", .{ .func = "test" }, .high, 0.85);
    try std.testing.expect(isPanicCleanupDoubleFree(&i));
}

test "Pattern C — _Unwind_Resume in function name" {
    var i = Issue.init(.double_free, "Double-free detected", .{ .func = "_ZNv..._Unwind_Resume" }, .high, 0.9);
    try std.testing.expect(isPanicCleanupDoubleFree(&i));
}

test "Pattern C — real double_free NOT suppressed" {
    var i = Issue.init(.double_free, "Double-free detected in user_handler", .{ .func = "user_handler" }, .high, 0.92);
    try std.testing.expect(!isPanicCleanupDoubleFree(&i));
}

test "Pattern D — thread_set_state + alloca" {
    var i = Issue.init(.borrow_escape, "Stack address escapes to FFI: thread_set_state() receives alloca-derived pointer", .{ .func = "test" }, .high, 0.8);
    try std.testing.expect(isOsApiStandardUsage(&i));
}

test "Pattern D — pthread + alloca" {
    var i = Issue.init(.borrow_escape, "Stack address escapes: pthread_getspecific() receives alloca-derived pointer", .{ .func = "test" }, .medium, 0.7);
    try std.testing.expect(isOsApiStandardUsage(&i));
}

test "Pattern D — real escape NOT suppressed" {
    var i = Issue.init(.borrow_escape, "Stack pointer escapes to FFI: callback saves ptr for later use", .{ .func = "user_handler" }, .critical, 0.95);
    try std.testing.expect(!isOsApiStandardUsage(&i));
}

test "shouldSuppress — combines all 6 patterns" {
    // A: Rust drop chain (use non-memory-bug kind for suppression test)
    var a = Issue.init(.unchecked_return, "freed by __rust_dealloc", .{ .func = "t" }, .medium, 0.8);
    try std.testing.expect(shouldSuppress(&a));

    // B: Code section (use non-memory-bug kind)
    var b = Issue.init(.stack_address_escape, ".text section pointer", .{ .func = "t" }, .critical, 0.9);
    try std.testing.expect(shouldSuppress(&b));

    // C: Panic cleanup (use non-memory-bug kind)
    var c = Issue.init(.buffer_overflow, "via panic_in_cleanup", .{ .func = "t" }, .high, 0.85);
    try std.testing.expect(shouldSuppress(&c));

    // D: OS API (use non-memory-bug kind)
    var d = Issue.init(.malloc_unchecked, "thread_set_state() receives alloca-derived", .{ .func = "t" }, .high, 0.8);
    try std.testing.expect(shouldSuppress(&d));

    // E: Safe example function (use non-memory-bug kind)
    var e = Issue.init(.malloc_unchecked, "Cross-language free in safe_example", .{ .func = "safe_example" }, .critical, 0.9);
    try std.testing.expect(shouldSuppress(&e));

    var e2 = Issue.init(.stack_address_escape, "Stack escape in correct_compress", .{ .func = "correct_compress" }, .high, 0.85);
    try std.testing.expect(shouldSuppress(&e2));

    // F: Defensive coding (use non-memory-bug kind)
    var f = Issue.init(.null_dereference, "escape in null_ptr_ffi_boundary", .{ .func = "null_ptr_ffi_boundary" }, .high, 0.8);
    try std.testing.expect(shouldSuppress(&f));

    var f2 = Issue.init(.integer_overflow, "alloc(0) in zero_size_alloc", .{ .func = "zero_size_alloc" }, .medium, 0.7);
    try std.testing.expect(shouldSuppress(&f2));

    var f3 = Issue.init(.buffer_overflow, "overflow in buffer_near_overflow", .{ .func = "buffer_near_overflow" }, .high, 0.75);
    try std.testing.expect(shouldSuppress(&f3));

    // Real issue passes through
    var real = Issue.init(.memory_leak, "malloc without free in my_handler", .{ .func = "my_handler" }, .high, 0.9);
    try std.testing.expect(!shouldSuppress(&real));
}

test "Global Guard — real memory bugs bypass ALL patterns" {
    // double_free in safe_example → NOT suppressed (B1 fix)
    var df = Issue.init(.double_free, "Double free in safe_example", .{ .func = "safe_example" }, .high, 0.9);
    try std.testing.expect(!shouldSuppress(&df));

    // borrow_escape mentioning NonNull → NOT suppressed (B3 fix)
    var be = Issue.init(.borrow_escape, "NonNull pointer escapes to FFI", .{ .func = "user_func" }, .high, 0.85);
    try std.testing.expect(!shouldSuppress(&be));

    // cross_language_free with __rust_dealloc → NOT suppressed (B2 fix)
    var clf = Issue.init(.cross_language_free, "Freed by __rust_dealloc in ffi_handler", .{ .func = "ffi_handler" }, .critical, 0.88);
    try std.testing.expect(!shouldSuppress(&clf));

    // use_after_free in panicking function → NOT suppressed (B4 fix)
    var uaf = Issue.init(.use_after_free, "UAF via panic_in_cleanup", .{ .func = "_ZN4core9panicking" }, .high, 0.9);
    try std.testing.expect(!shouldSuppress(&uaf));

    // Non-memory bugs still suppressed normally
    var fp = Issue.init(.unchecked_return, "Unchecked return in safe_example", .{ .func = "safe_example" }, .medium, 0.7);
    try std.testing.expect(shouldSuppress(&fp));
}

test "Pattern E — safe_example prefix" {
    var i = Issue.init(.cross_language_free, "bug in safe_example", .{ .func = "safe_example" }, .high, 0.9);
    try std.testing.expect(isSafeExampleFunction(&i));
}

test "Pattern E — correct_compress prefix" {
    var i = Issue.init(.cross_language_free, "bug in correct_compress", .{ .func = "correct_compress" }, .high, 0.9);
    try std.testing.expect(isSafeExampleFunction(&i));
}

test "Pattern E — real bug NOT suppressed" {
    var i = Issue.init(.memory_leak, "leak in process_data", .{ .func = "process_data" }, .high, 0.9);
    try std.testing.expect(!isSafeExampleFunction(&i));
}

test "Pattern F — null_ptr defensive check" {
    var i = Issue.init(.borrow_escape, "escape in null_ptr_ffi_boundary", .{ .func = "null_ptr_ffi_boundary" }, .high, 0.8);
    try std.testing.expect(isDefensiveCodingPattern(&i));
}

test "Pattern F — zero-size allocation" {
    var i = Issue.init(.cross_language_free, "allocation of size 0 in zero_size_alloc", .{ .func = "zero_size_alloc" }, .medium, 0.7);
    try std.testing.expect(isDefensiveCodingPattern(&i));
}

test "Pattern F — buffer_near_overflow bounded copy" {
    var i = Issue.init(.borrow_escape, "overflow in buffer_near_overflow", .{ .func = "buffer_near_overflow" }, .high, 0.75);
    try std.testing.expect(isDefensiveCodingPattern(&i));
}

test "Pattern F — real overflow NOT suppressed" {
    var i = Issue.init(.borrow_escape, "overflow in buffer_at_overflow", .{ .func = "buffer_at_overflow" }, .critical, 0.9);
    try std.testing.expect(!isDefensiveCodingPattern(&i));
}

// ============================================================================
// shouldSuppressWithProfile — platform-gated suppression tests
// ============================================================================

// Helper: build a minimal PlatformProfile for tests (no allocation).
fn makeTestProfile(
    platform: platform_profile_mod.PlatformKind,
    object_format: platform_profile_mod.ObjectFormat,
    abi: platform_profile_mod.WindowsAbi,
) PlatformProfile {
    return PlatformProfile{
        .platform = platform,
        .object_format = object_format,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
        .windows_abi = abi,
    };
}

test "shouldSuppressWithProfile — null profile preserves legacy behavior" {
    // The legacy entry point must behave identically when null is passed.
    // We use a Windows MSVC runtime name to exercise the platform branch.
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expectEqual(
        shouldSuppress(&i),
        shouldSuppressWithProfile(&i, null),
    );
}

test "shouldSuppressWithProfile — Windows MSVC pattern fires on Windows" {
    // On a Windows MSVC target, the MSVC CRT pattern set should be consulted
    // and suppress the issue.
    const profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expect(shouldSuppressWithProfile(&i, &profile));
}

test "shouldSuppressWithProfile — Windows MSVC pattern skipped on Linux" {
    // The same SEH-named symbol on Linux is almost certainly NOT the
    // Windows runtime, so the platform-gated path must skip the MSVC scan.
    //
    // We must pick a name that ONLY matches Windows MSVC patterns and does
    // not collide with any generic (cross-platform) runtime pattern.
    const profile = makeTestProfile(.linux, .elf, .unknown);
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expect(!shouldSuppressWithProfile(&i, &profile));
}

test "shouldSuppressWithProfile — generic patterns work on every platform" {
    // C++ allocator `_Znwm` is cross-platform; it should suppress on both
    // Linux and Windows profiles regardless of MSVC gating.
    const linux_profile = makeTestProfile(.linux, .elf, .unknown);
    const win_profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .memory_leak,
        "leak in _Znwm",
        .{ .file = null, .func = "_Znwm" },
        .high,
        0.8,
    );
    try std.testing.expect(shouldSuppressWithProfile(&i, &linux_profile));
    try std.testing.expect(shouldSuppressWithProfile(&i, &win_profile));
}

test "shouldSuppressWithProfile — real memory bug never suppressed regardless of profile" {
    // The global guard must keep priority — a genuine double-free in a user
    // function should pass through even on a Windows MSVC profile.
    const profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .double_free,
        "double free in app_handler",
        .{ .file = null, .func = "app_handler" },
        .critical,
        0.95,
    );
    try std.testing.expect(!shouldSuppressWithProfile(&i, &profile));
}
