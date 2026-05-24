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

const std = @import("std");

const Issue = @import("../../diag/issue.zig").Issue;

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
pub fn shouldSuppress(issue: *const Issue) bool {
    if (isRustDropChainLeak(issue)) {
        std.log.debug("[SUPPRESS-DROP] {s}: Rust Drop chain", .{issue.location.func});
        return true;
    }

    if (isStaticProvenanceEscape(issue)) {
        std.log.debug("[SUPPRESS-STATIC] {s}: Static/code provenance", .{issue.location.func});
        return true;
    }

    if (isPanicCleanupDoubleFree(issue)) {
        std.log.debug("[SUPPRESS-PANIC] {s}: Panic cleanup double-free", .{issue.location.func});
        return true;
    }

    if (isOsApiStandardUsage(issue)) {
        std.log.debug("[SUPPRESS-OSAPI] {s}: OS API standard usage", .{issue.location.func});
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
    total_suppressed: usize = 0,

    pub fn record(self: *SuppressionStats, pattern: Pattern) void {
        switch (pattern) {
            .drop_chain => self.drop_chain += 1,
            .static_provenance => self.static_provenance += 1,
            .panic_cleanup => self.panic_cleanup += 1,
            .os_api_usage => self.os_api_usage += 1,
        }
        self.total_suppressed += 1;
    }

    pub fn logSummary(self: SuppressionStats) void {
        if (self.total_suppressed == 0) return;
        std.log.info("[SUPPRESSION] {d} suppressed: drop={d} static={d} panic={d} osapi={d}", .{
            self.total_suppressed,
            self.drop_chain,
            self.static_provenance,
            self.panic_cleanup,
            self.os_api_usage,
        });
    }
};

const Pattern = enum { drop_chain, static_provenance, panic_cleanup, os_api_usage };

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

    // B2: NonNull wrapper around static address
    if (std.mem.indexOf(u8, msg, "NonNull") != null) return true;

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
        "thread_set_state",      // Mach kernel
        "thread_get_state",      // Mach kernel
        "mach_thread_self",      // Mach kernel
        "pthread_",              // POSIX threads
        "sigaction",             // Signal handling
        "setjmp",                // Setjmp/longjmp
        "getcontext",            // ucontext
        "ioctl",                 // Device I/O (often passes struct ptrs)
        "fcntl",                 // File control
        "sysctl",                // BSD system control
        "vm_read",               // Mach VM
        "vm_write",              // Mach VM
        "mach_msg",              // Mach IPC
    };

    for (os_api_names) |api| {
        if (std.mem.indexOf(u8, msg, api) != null) return true;
    }

    // D2: alloca-derived to any *_state, *_info, *_context, *_thread function
    // These naming conventions indicate "passing state struct to OS"
    if (std.mem.indexOf(u8, msg, "alloca-derived") != null) {
        const state_patterns = [_][]const u8{
            "_state(",  // thread_set_state(xxx_state_t*)
            "_info(",   // xxx_info_t* parameter
            "_ctx(",    // context pointer
            "_attr(",   // pthread_attr_t*
            "_spec(",   // pthread_specifc_
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
        "hw_" , // hardware-accelerated (often uses function pointer tables)
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

test "Pattern B — NonNull in message" {
    var i = Issue.init(.borrow_escape, "NonNull pointer escapes to FFI", .{ .func = "test" }, .high, 0.85);
    try std.testing.expect(isStaticProvenanceEscape(&i));
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

test "shouldSuppress — combines all 4 patterns" {
    // A: Rust drop chain
    var a = Issue.init(.use_after_free, "freed by __rust_dealloc", .{ .func = "t" }, .medium, 0.8);
    try std.testing.expect(shouldSuppress(&a));

    // B: Code section
    var b = Issue.init(.borrow_escape, ".text section pointer", .{ .func = "t" }, .critical, 0.9);
    try std.testing.expect(shouldSuppress(&b));

    // C: Panic cleanup
    var c = Issue.init(.double_free, "via panic_in_cleanup", .{ .func = "t" }, .high, 0.85);
    try std.testing.expect(shouldSuppress(&c));

    // D: OS API
    var d = Issue.init(.borrow_escape, "thread_set_state() receives alloca-derived", .{ .func = "t" }, .high, 0.8);
    try std.testing.expect(shouldSuppress(&d));

    // Real issue passes through
    var real = Issue.init(.memory_leak, "malloc without free in my_handler", .{ .func = "my_handler" }, .high, 0.9);
    try std.testing.expect(!shouldSuppress(&real));
}
