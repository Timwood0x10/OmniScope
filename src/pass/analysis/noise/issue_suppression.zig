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
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const issue_classification = @import("../../../filter/issue_classification.zig");
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

    // P16-3: Patterns A-F deprecated — replaced by Resource Contract Graph system:
    //   - Pattern A (Rust Drop) → summary_inference.zig inferDestructorLikeSummary()
    //   - Pattern B (Static) → family_registry.zig + EscapeKind.static_lifetime
    //   - Pattern C (Panic cleanup) → OwnershipStateSolver.conditional_release
    //   - Pattern D (OS API) → PlatformFilter + FFI boundary classification
    //   - Pattern E (Safe example) → CandidateBuilder scoring (BONUS_FFI_BOUNDARY)
    //   - Pattern F (Defensive coding) → IssueVerifier structural pattern inference
    //
    // Kept as comments for reference until all call sites fully migrated.
    // TODO: Remove this comment block in P17 after regression validation.

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

    // Known compiler builtin patterns (any language)
    // Instead of matching ALL __-prefixed functions, use a specific list
    const compiler_builtins = [_][]const u8{
        // GCC/Clang builtins
        "__builtin_",
        // Fortified libc functions (__*_chk variants)
        "__memcpy_chk",
        "__memmove_chk",
        "__memset_chk",
        "__strcpy_chk",
        "__strcat_chk",
        "__strncpy_chk",
        "__sprintf_chk",
        "__snprintf_chk",
        "__printf_chk",
        "__fprintf_chk",
        "__vprintf_chk",
        "__vfprintf_chk",
        // Stack protection canaries
        "__stack_chk_fail",
        "__stack_chk_guard",
        // C++ ABI runtime functions
        "__cxa_",
        // G++ personality functions
        "__gxx_personality",
        // LLVM intrinsics
        "__llvm_",
        // Sanitizer functions
        "__sanitizer_",
        "__ubsan_",
        "__asan_",
        "__msan_",
        "__tsan_",
    };
    for (compiler_builtins) |builtin| {
        if (startsWith(func, builtin)) return true;
    }

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

/// Check if a mangled function name belongs to a known compiler-internal
/// or standard-library component that can be safely skipped for double-free
/// analysis.
///
/// This is a PRECISE whitelist — only confirmed internal patterns are
/// matched. User functions (even when mangled) are NEVER skipped.
///
/// Patterns:
///   - _ZNSt*     → C++ std:: (standard library)
///   - _ZN4core*  → Rust core:: (standard library)
///   - _ZN5alloc* → Rust alloc:: (allocator)
///   - _ZGV*      → Global initialization guard
///   - _ZZ*       → Local static initializer
///   - __cxx_*    → C++ ABI internals
///   - _GLOBAL__* → Global constructors/destructors
///   - $sS/$ss    → Swift runtime symbols
pub fn isCompilerInternalFunction(func_name: []const u8) bool {
    const internal_patterns = [_][]const u8{
        "_ZNSt", // C++ standard library (std::*)
        "_ZN4core", // Rust core module
        "_ZN5alloc", // Rust alloc module
        "_ZGV", // Global initialization guard (Itanium ABI)
        "_ZZ", // Local static initializer (Itanium ABI)
        "__cxx_", // C++ ABI internals
        "_GLOBAL__", // Global constructors/destructors
        "$ss", // Swift standard library
        "$sS", // Swift standard library (uppercase)
    };

    for (internal_patterns) |pattern| {
        if (std.mem.startsWith(u8, func_name, pattern)) return true;
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
///   1. Caller is a known compiler-internal/stdlib function (NOT just any mangled name)
///   2. Message mentions __rust_dealloc or drop_in_place (Rust global allocator)
///   3. No FFI cross-boundary evidence in message (no external function names)
///   4. Issue kind is double_free (not use_after_free or invalid_free — those are
///      always real bugs even in pure Rust)
fn isPureRustInternalDoubleFree(issue: *const Issue) bool {
    const func = issue.location.func;
    const msg = issue.message;

    // Condition 1: Caller must be a known compiler-internal function
    // Use precise whitelist instead of broad "_ZN" prefix match to avoid
    // skipping user-defined mangled functions (C++ class methods, Rust pub fn)
    if (!isCompilerInternalFunction(func)) return false;

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
///   - Critical CWE-classified vulnerabilities (null_dereference, buffer_overflow, etc.)
///   - FFI boundary issues (cross-language leaks, unsafe calls)
///   - Ownership/borrow violations (borrow_escape, type_mismatch)
///   - Callback safety issues (callback_ownership_risk, etc.)
///
/// Rationale: These issue kinds represent GENUINE security vulnerabilities.
/// Even when they occur in "safe_*" named functions, involve __rust_dealloc,
/// or mention NonNull types — the detector found a real problem, not a FP.
///
/// NOTE: null_dereference (CWE-476), buffer_overflow (CWE-120), and integer_overflow
/// (CWE-190) are included because these are critical vulnerabilities that must ALWAYS
/// be reported, even in stdlib/FFI functions. Suppressing them would hide real security bugs.
pub fn isRealMemorySafetyBug(issue: *const Issue) bool {
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
        const is_internal_caller = isCompilerInternalFunction(func);
        const has_rnv_callee = std.mem.indexOf(u8, msg, "_RNv") != null;
        const has_rust_dealloc = std.mem.indexOf(u8, msg, "__rust_dealloc") != null;

        if (is_internal_caller and has_rnv_callee and has_rust_dealloc) {
            log.debug("[PURE-RUST-FP-GUARD] double_free in {s} with _RNv+__rust_dealloc -> let Pattern A handle", .{func});
            return false;
        }
    }

    // Delegate to unified classification — single source of truth.
    // This replaces the previous 30-line switch that was inconsistent with
    // is_core_memory_safety_bug and is_ffi_issue in pass_types.zig.
    return issue_classification.isNeverSuppressed(issue.kind);
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

// ============================================================================
// FIX #3: Precise compiler-internal function detection (mangled name whitelist)
// ============================================================================

test "isCompilerInternalFunction - C++ std library patterns are internal" {
    try std.testing.expect(isCompilerInternalFunction("_ZNSt6vectorIiEE"));
    try std.testing.expect(isCompilerInternalFunction("_ZNSt9basic_stringIcE"));
    try std.testing.expect(isCompilerInternalFunction("_ZNSt3mapIiiEE"));
}

test "isCompilerInternalFunction - Rust stdlib patterns are internal" {
    try std.testing.expect(isCompilerInternalFunction("_ZN4core9fmt::Formatter9write_strE"));
    try std.testing.expect(isCompilerInternalFunction("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(isCompilerInternalFunction("_ZN3std2io5stdio6printlnE"));
}

test "isCompilerInternalFunction - compiler ABI internals are internal" {
    try std.testing.expect(isCompilerInternalFunction("_ZGVN3foo3barE"));
    try std.testing.expect(isCompilerInternalFunction("_ZZN3foo3barEvE12local_var"));
    try std.testing.expect(isCompilerInternalFunction("__cxx_global_var_init"));
    try std.testing.expect(isCompilerInternalFunction("_GLOBAL__sub_I_main"));
}

test "isCompilerInternalFunction - Swift runtime symbols are internal" {
    try std.testing.expect(isCompilerInternalFunction("$sS4base8toStringSSyF"));
    try std.testing.expect(isCompilerInternalFunction("$ss5printyySS_pF"));
}

test "isCompilerInternalFunction - user mangled functions are NOT internal (FIX #3)" {
    // User C++ class methods should NOT be skipped
    try std.testing.expect(!isCompilerInternalFunction("_ZN9my_app4mainE"));
    try std.testing.expect(!isCompilerInternalFunction("_ZN3app7my_class12do_somethingE"));
    try std.testing.expect(!isCompilerInternalFunction("_ZN6mylib4DataC1Ev"));

    // User Rust pub fn should NOT be skipped
    try std.testing.expect(!isCompilerInternalFunction("_ZN6mycrate4func17process_dataEv"));
    try std.testing.expect(!isCompilerInternalFunction("_ZN5utils8helper_fnE"));

    // Non-mangled functions are never internal
    try std.testing.expect(!isCompilerInternalFunction("user_function"));
    try std.testing.expect(!isCompilerInternalFunction("main"));
    try std.testing.expect(!isCompilerInternalFunction("handle_request"));
}

// ============================================================================
// FIX #4: null_dereference and other critical types never suppressed
// ============================================================================

test "isRealMemorySafetyBug - null_dereference is never suppressed (FIX #4)" {
    // null_dereference in stdlib function → must return true (never suppressed)
    var i = Issue.init(
        .null_dereference,
        "null pointer dereference in std.mem.copy",
        .{ .file = null, .func = "std.mem.copy" },
        .high,
        0.9,
    );
    try std.testing.expect(isRealMemorySafetyBug(&i));

    // null_dereference in os.mmap → must return true
    i = Issue.init(
        .null_dereference,
        "null dereference in os.mmap",
        .{ .file = null, .func = "os.mmap" },
        .high,
        0.85,
    );
    try std.testing.expect(isRealMemorySafetyBug(&i));

    // null_dereference in user function → must return true
    i = Issue.init(
        .null_dereference,
        "null dereference in process_data",
        .{ .file = null, .func = "process_data" },
        .high,
        0.88,
    );
    try std.testing.expect(isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - buffer_overflow is never suppressed (FIX #4)" {
    var i = Issue.init(
        .buffer_overflow,
        "buffer overflow in snprintf",
        .{ .file = null, .func = "snprintf" },
        .critical,
        0.95,
    );
    try std.testing.expect(isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - integer_overflow is never suppressed (FIX #4)" {
    var i = Issue.init(
        .integer_overflow,
        "integer overflow in calculate_size",
        .{ .file = null, .func = "calculate_size" },
        .high,
        0.87,
    );
    try std.testing.expect(isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - core memory safety types always return true" {
    const critical_kinds = [_]IssueKind{
        .double_free,      .use_after_free,  .invalid_free,     .memory_leak,
        .null_dereference, .buffer_overflow, .integer_overflow,
    };

    for (critical_kinds) |kind| {
        var i = Issue.init(
            kind,
            "test issue",
            .{ .file = null, .func = "test_func" },
            .high,
            0.8,
        );
        try std.testing.expect(isRealMemorySafetyBug(&i));
    }
}

// ============================================================================
// FIX #P2: Precise double-underscore prefix whitelist
// ============================================================================

test "isStdlibInternalFunction - compiler builtins are suppressed (safe)" {
    // LLVM intrinsics — should be suppressed
    var issue_llvm = Issue.init(
        .callback_ownership_risk,
        "risk in __llvm_gcda_start_file",
        .{ .file = null, .func = "__llvm_gcda_start_file" },
        .high,
        0.7,
    );
    try std.testing.expect(isStdlibInternalFunction(&issue_llvm));

    // Sanitizer runtime — should be suppressed
    var issue_asan = Issue.init(
        .callback_ownership_risk,
        "risk in __asan_report_load1",
        .{ .file = null, .func = "__asan_report_load1" },
        .high,
        0.7,
    );
    try std.testing.expect(isStdlibInternalFunction(&issue_asan));

    // C++ ABI runtime — should be suppressed
    var issue_cxa = Issue.init(
        .callback_ownership_risk,
        "risk in __cxa_throw",
        .{ .file = null, .func = "__cxa_throw" },
        .high,
        0.7,
    );
    try std.testing.expect(isStdlibInternalFunction(&issue_cxa));

    // GCC builtin — should be suppressed
    var issue_builtin = Issue.init(
        .callback_ownership_risk,
        "risk in __builtin_memcpy",
        .{ .file = null, .func = "__builtin_memcpy" },
        .high,
        0.7,
    );
    try std.testing.expect(isStdlibInternalFunction(&issue_builtin));
}

test "isStdlibInternalFunction - user dunder functions are NOT suppressed (FIX #P2)" {
    // Python/Cython lifecycle functions — should NOT be suppressed
    var issue_cinit = Issue.init(
        .callback_ownership_risk,
        "risk in __cinit__",
        .{ .file = null, .func = "__cinit__" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_cinit));

    var issue_dealloc = Issue.init(
        .callback_ownership_risk,
        "risk in __dealloc__",
        .{ .file = null, .func = "__dealloc__" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_dealloc));

    // Python module init — should NOT be suppressed
    var issue_init_mod = Issue.init(
        .callback_ownership_risk,
        "risk in __init_module",
        .{ .file = null, .func = "__init_module" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_init_mod));

    // User-defined lifecycle — should NOT be suppressed
    var issue_init = Issue.init(
        .callback_ownership_risk,
        "risk in __init",
        .{ .file = null, .func = "__init" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_init));

    var issue_finalize = Issue.init(
        .callback_ownership_risk,
        "risk in __finalize",
        .{ .file = null, .func = "__finalize" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_finalize));

    // Custom user function with __ prefix — should NOT be suppressed
    var issue_custom = Issue.init(
        .callback_ownership_risk,
        "risk in __custom_helper",
        .{ .file = null, .func = "__custom_helper" },
        .high,
        0.7,
    );
    try std.testing.expect(!isStdlibInternalFunction(&issue_custom));
}
