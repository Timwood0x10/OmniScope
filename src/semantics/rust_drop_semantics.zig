//! Rust Drop Semantics — Implicit Destructor Recognition
//!
//! Core problem: The tool does not understand Rust's Drop trait.
//! When a Rust object leaves scope, the compiler automatically inserts
//! a call to drop_in_place<T> (the "drop glue"). This is invisible in
//! source code but visible in LLVM IR as:
//!
//!   call void @_ZN4core3ptr13drop_in_place17h<hash>E(%T* %value)
//!   call void @__rust_dealloc(ptr, size, align)
//!
//! Without understanding this, the tool produces false positives:
//!   - Reports "double free" when drop glue + manual free both target same ptr
//!   - Reports "use after free" when as_ptr result is used before scope-end drop
//!   - Reports "leak" when drop glue at scope end handles cleanup
//!
//! This module provides:
//!   1. DropGlueDetector — recognize drop_in_place and related IR symbols
//!   2. DropScope — model Rust's implicit scope-end destructor calls
//!   3. DropAwareFreeCheck — determine if a free() is safe because it's
//!      compiler-inserted drop glue (not a manual double-free)

const std = @import("std");

/// Recognized drop glue function name patterns in LLVM IR.
///
/// These are compiler-generated functions that implement Rust's
/// automatic destructor calls at scope exit. They are NOT bugs.
///
/// Reference: RUST_IR_SPEC.md §1.4 — FutureDropPollShim
/// Reference: rustc_symbol_mangling/src/v0.rs:63
pub const DROP_GLUE_PATTERNS = [_][]const u8{
    // core::ptr::drop_in_place<T> — the universal drop glue dispatcher
    "drop_in_place",
    // Fully-qualified mangled forms (legacy Itanium ABI)
    "_ZN4core3ptr13drop_in_place",
    // v0 mangling: drop shim suffix (internal, never appears in actual IR)
    "drop-shim",
    // User-defined Drop::drop implementations
    "::drop",
    // Internal drop helpers
    "real_drop_in_place",
    "drop_and_deallocate",
    "glue_drop",
    "need_drop",
    "drop_glue",
    "impl_drop",
    "dyn_drop",
};

/// Rust allocator intrinsics that appear as part of drop glue chains.
///
/// When drop_in_place runs on a Vec/String/Box, it:
///   1. Calls the user's Drop::drop() if implemented
///   2. Calls drop_in_place on each element (for Vec)
///   3. Calls __rust_dealloc to free the backing buffer
///
/// Step 3 is NOT a separate "free" — it's part of the destructor.
pub const DROP_ALLOC_INTRINSICS = struct {
    // Allocation intrinsics that may appear in drop glue chains
    pub const alloc = [_][]const u8{
        "__rust_alloc",
        "__rust_alloc_zeroed",
    };

    /// Deallocation intrinsics that appear in drop glue chains
    pub const dealloc = [_][]const u8{
        "__rust_dealloc",
        "__rdl_dealloc",
        "__rg_dealloc",
    };
};

/// Classification of a function call's relationship to Rust drop semantics.
pub const DropClassification = enum(u8) {
    /// This call IS drop glue (e.g., drop_in_place<T>).
    /// It represents an implicit destructor call — NOT a bug.
    is_drop_glue,
    /// This call is a deallocation that is PART OF a drop glue chain.
    /// E.g., __rust_dealloc called from within drop_in_place.
    /// NOT a standalone free — it's compiler-generated cleanup.
    is_dealloc_in_drop_chain,
    /// This call is a manual free/dealloc by user code.
    /// This IS potentially dangerous — could be double-free if
    /// drop glue will also run on the same value.
    is_manual_free,
    /// This call is unrelated to drop semantics.
    unrelated,
};

/// Information about a detected drop glue call site.
pub const DropGlueInfo = struct {
    /// The function name that was identified as drop glue.
    callee_name: []const u8,
    /// The classification result.
    classification: DropClassification,
    /// The type being dropped (if extractable from mangled name).
    dropped_type: ?[]const u8,
    /// Confidence score (0.0-1.0) for this classification.
    confidence: f32,
};

/// A scope in which Rust values with Drop implementations live.
/// When the scope ends, drop glue is automatically inserted by the compiler.
pub const DropScope = struct {
    /// The function containing this scope.
    function_name: []const u8,
    /// Values tracked in this scope that have Drop implementations.
    /// When scope ends, drop_in_place is called on each.
    tracked_values: std.ArrayList(TrackedValue),
    /// Drop glue calls found in this function (by IR scan).
    drop_glue_calls: std.ArrayList(DropGlueInfo),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, function_name: []const u8) Self {
        return .{
            .function_name = function_name,
            .tracked_values = std.ArrayList(TrackedValue).init(allocator),
            .drop_glue_calls = std.ArrayList(DropGlueInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tracked_values.deinit();
        self.drop_glue_calls.deinit();
    }
};

/// A Rust value tracked for Drop semantics.
pub const TrackedValue = struct {
    /// LLVM value reference (the alloca or local holding the value).
    val_ref: u64,
    /// Whether this value has been explicitly moved (ownership transferred).
    /// Moved values do NOT get drop glue at scope end.
    is_moved: bool,
    /// Whether this value has had drop_in_place called on it already.
    /// Prevents false "double free" reports for explicit + implicit drops.
    is_dropped: bool,
    /// Whether ownership was transferred via into_raw or similar.
    ownership_transferred_out: bool,
};

// ═══════════════════════════════════════════════════════════════
// Drop Glue Detection API
// ═══════════════════════════════════════════════════════════════

/// Check if a function name is a Rust drop glue function.
///
/// Drop glue functions are compiler-generated and represent implicit
/// destructor calls at scope exit. They should NOT be reported as bugs.
pub fn isDropGlue(func_name: []const u8) bool {
    for (DROP_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a function name is a Rust deallocation intrinsic
/// that typically appears as part of a drop glue chain.
pub fn isDropChainDealloc(func_name: []const u8) bool {
    for (DROP_ALLOC_INTRINSICS.dealloc) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Classify a function call according to its relationship with Rust drop semantics.
///
/// This is the primary API for other passes to use when deciding whether
/// a free/dealloc call represents a real bug or compiler-generated cleanup.
pub fn classifyDropCall(func_name: []const u8) DropClassification {
    // Check drop glue first — these are always implicit destructors
    if (isDropGlue(func_name)) return .is_drop_glue;

    // Check if it's a Rust dealloc intrinsic (appears in drop chains)
    if (isDropChainDealloc(func_name)) return .is_dealloc_in_drop_chain;

    // Check if it's a C free() or other manual deallocation
    const manual_free_patterns = [_][]const u8{
        "free",            "dealloc",           "deallocate",
        "operator delete", "operator delete[]",
    };
    for (manual_free_patterns) |pat| {
        if (std.mem.eql(u8, func_name, pat) or
            std.mem.startsWith(u8, func_name, pat))
        {
            return .is_manual_free;
        }
    }

    return .unrelated;
}

/// Determine whether a free/dealloc call is safe because it is
/// part of Rust's implicit drop glue (not a user-caused double-free).
///
/// This function should be called by FreeValidationPass and
/// RustFfiAuditor before reporting double-free or invalid-free issues.
///
/// Returns true when the free is "safe" (compiler-generated cleanup).
pub fn isImplicitDropFree(
    callee_name: []const u8,
    is_rust_module: bool,
    /// Whether the freed pointer was previously passed to drop_in_place.
    /// If drop glue already ran, a subsequent __rust_dealloc in the same
    /// chain is expected (not a double-free).
    pointer_already_dropped: bool,
    /// Caller function name (for context validation).
    /// Used to distinguish compiler RAII from user unsafe code.
    caller_func_name: ?[]const u8,
) bool {
    // Non-Rust modules don't have implicit drop
    if (!is_rust_module) return false;

    const classification = classifyDropCall(callee_name);

    switch (classification) {
        .is_drop_glue => {
            // drop_in_place is ALWAYS safe — it's compiler-generated
            return true;
        },
        .is_dealloc_in_drop_chain => {
            // __rust_dealloc requires careful validation:
            // Case 1: Follows a drop_in_place → definitely RAII tail
            if (pointer_already_dropped) return true;

            // Case 2: Check caller context if available
            if (caller_func_name) |caller| {
                // First check: Is this user allocator code? (highest priority)
                // User allocators use __rust_dealloc but are NOT compiler RAII
                if (isUserAllocatorCode(caller)) {
                    return false;
                }

                // Second check: Is this compiler-generated internal function?
                if (isCompilerGeneratedRustFunction(caller)) {
                    return true;
                }
            }

            // Default conservative: don't trust __rust_dealloc without strong evidence
            // This prevents suppressing double-free/UAF in user unsafe code
            return false;
        },
        .is_manual_free => {
            // Manual C free() on a Rust value is ALWAYS dangerous
            // — it bypasses the Drop trait and may double-free
            // when the compiler also inserts drop glue at scope end.
            return false;
        },
        .unrelated => return false,
    }
}

/// Check if a function name looks like a compiler-generated internal Rust function.
///
/// IMPORTANT: This uses a PRECISE whitelist — only confirmed internal
/// patterns are matched. User functions (even when mangled) must NOT be
/// matched to avoid suppressing real memory safety bugs.
///
/// See: issue_suppression.zig isCompilerInternalFunction() for the
/// canonical implementation and detailed rationale.
fn isCompilerGeneratedRustFunction(func_name: []const u8) bool {
    // Precise whitelist of compiler-internal patterns only
    const internal_prefixes = [_][]const u8{
        // C++ standard library internals
        "_ZNSt", // std::
        "_ZN9__gnu_cxx", // __gnu_cxx::

        // Rust core/alloc internals (standard library only)
        "_ZN4core", // core::
        "_ZN5alloc", // alloc::

        // Rust v0 mangling for standard library
        "_RN4core", // _RNvC<crate>4core...
        "_RN5alloc", // _RNvC<crate>5alloc...

        // Global initialization guards (Itanium ABI)
        "_ZGV",
        "_ZZ",

        // Compiler builtins and intrinsics (always safe)
        "__rust_",
        "__rdl_",
        "__rg_",
        "__cxx_",

        // Global constructors/destructors
        "_GLOBAL__",

        // Swift runtime
        "$ss",
        "$sS",
    };

    for (internal_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }

    // Also check for known drop glue patterns (always safe)
    if (isDropGlue(func_name)) return true;

    return false;
}

/// Check if function appears to be user-level allocator code
/// that uses __rust_dealloc but is NOT compiler RAII.
fn isUserAllocatorCode(func_name: []const u8) bool {
    const user_patterns = [_][]const u8{
        "global_alloc",
        "GlobalAlloc",
        "allocator",
        "Allocator",
        "alloc::alloc::",
        "std::alloc::",
        // Box::from_raw pattern — user explicitly managing memory
        "from_raw",
        "into_raw",
    };

    for (user_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Determine if a value will have drop glue inserted at scope end.
///
/// In Rust, values that implement the Drop trait (directly or transitively)
/// will have drop_in_place called when they go out of scope. This includes:
///   - Types with explicit Drop impl (Box, Vec, String, File, etc.)
///   - Types containing Drop types (structs with Drop fields)
///   - Types with drop glue (even without explicit Drop)
///
/// At the LLVM IR level, we infer this from:
///   1. Whether drop_in_place<T> exists for this type
///   2. Whether __rust_dealloc is called on the value's backing buffer
///   3. Whether the value was moved (moved values don't get dropped)
pub fn valueNeedsDrop(
    /// The type name or mangled identifier of the value.
    type_name: []const u8,
    /// Whether the value has been moved (ownership transferred out).
    is_moved: bool,
    /// Whether ownership was transferred via into_raw.
    ownership_transferred_out: bool,
) bool {
    // Moved values do NOT get drop glue
    if (is_moved) return false;
    // Values transferred via into_raw do NOT get drop glue
    if (ownership_transferred_out) return false;

    // Types that are known to need drop
    const drop_types = [_][]const u8{
        // Standard library types with Drop
        "Vec<",     "String",     "Box<",      "CString",    "CStr",
        "File",     "BufReader",  "BufWriter", "Mutex",      "RwLock",
        "Condvar",  "JoinHandle", "Receiver",  "Sender",
        // Smart pointers
            "Rc<",
        "Arc<",     "Weak<",
        // Collections
             "HashMap",   "HashSet",    "BTreeMap",
        "BTreeSet", "LinkedList", "VecDeque",  "BinaryHeap",
    };

    for (drop_types) |pat| {
        if (std.mem.indexOf(u8, type_name, pat) != null) return true;
    }

    return false;
}

/// Check if a callee name is a Rust Drop::drop explicit implementation.
///
/// User-defined Drop::drop implementations are different from
/// drop_in_place — they contain the user's cleanup logic.
/// They are still part of the normal drop chain and should not
/// be flagged as bugs.
pub fn isExplicitDropImpl(func_name: []const u8) bool {
    // Patterns for explicit Drop::drop implementations
    const explicit_drop_patterns = [_][]const u8{
        // <T as core::ops::drop::Drop>::drop
        "core::ops::drop::Drop",
        // Legacy mangling for Drop::drop
        "ops::drop::Drop",
        // impl Drop for T
        "impl_drop",
    };
    for (explicit_drop_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "isDropGlue - recognizes drop_in_place patterns" {
    // Standard drop_in_place mangled forms
    try std.testing.expect(isDropGlue("_ZN4core3ptr13drop_in_place17h1234E"));
    try std.testing.expect(isDropGlue("drop_in_place"));
    try std.testing.expect(isDropGlue("glue_drop"));
    try std.testing.expect(isDropGlue("drop_glue"));
    try std.testing.expect(isDropGlue("real_drop_in_place"));
    try std.testing.expect(isDropGlue("drop_and_deallocate"));
    try std.testing.expect(isDropGlue("impl_drop"));
    try std.testing.expect(isDropGlue("dyn_drop"));

    // Non-drop-glue patterns
    try std.testing.expect(!isDropGlue("free"));
    try std.testing.expect(!isDropGlue("malloc"));
    try std.testing.expect(!isDropGlue("my_function"));
}

test "isDropChainDealloc - recognizes Rust deallocation intrinsics" {
    try std.testing.expect(isDropChainDealloc("__rust_dealloc"));
    try std.testing.expect(isDropChainDealloc("__rdl_dealloc"));
    try std.testing.expect(isDropChainDealloc("__rg_dealloc"));
    try std.testing.expect(!isDropChainDealloc("__rust_alloc"));
    try std.testing.expect(!isDropChainDealloc("free"));
    try std.testing.expect(!isDropChainDealloc("malloc"));
}

test "classifyDropCall - correct classification" {
    // Drop glue
    try std.testing.expect(classifyDropCall("drop_in_place") == .is_drop_glue);
    try std.testing.expect(classifyDropCall("_ZN4core3ptr13drop_in_place17hE") == .is_drop_glue);

    // Dealloc in drop chain
    try std.testing.expect(classifyDropCall("__rust_dealloc") == .is_dealloc_in_drop_chain);
    try std.testing.expect(classifyDropCall("__rdl_dealloc") == .is_dealloc_in_drop_chain);

    // Manual free
    try std.testing.expect(classifyDropCall("free") == .is_manual_free);
    try std.testing.expect(classifyDropCall("dealloc") == .is_manual_free);

    // Unrelated
    try std.testing.expect(classifyDropCall("malloc") == .unrelated);
    try std.testing.expect(classifyDropCall("my_function") == .unrelated);
}

test "isImplicitDropFree - safe vs dangerous frees" {
    // Rust module: drop glue is always safe (regardless of caller)
    try std.testing.expect(isImplicitDropFree("drop_in_place", true, false, null));
    try std.testing.expect(isImplicitDropFree("drop_in_place", true, true, null));

    // Rust module: __rust_dealloc in compiler-generated function → safe
    try std.testing.expect(isImplicitDropFree("__rust_dealloc", true, false, "_ZN4core3ptr13drop_in_place"));
    try std.testing.expect(isImplicitDropFree("__rust_dealloc", true, true, "_ZN4core3ptr13drop_in_place"));

    // Rust module: __rust_dealloc with preceding drop_in_place → always safe
    try std.testing.expect(isImplicitDropFree("__rust_dealloc", true, true, null));

    // Rust module: __rust_dealloc in user code WITHOUT context → NOT safe (conservative)
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, null));

    // Rust module: __rust_dealloc in user allocator impl → NOT safe
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "my_allocator"));
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "_ZN4alloc5alloc9global_alloc"));

    // Rust module: C free() is ALWAYS dangerous on Rust values
    try std.testing.expect(!isImplicitDropFree("free", true, false, null));
    try std.testing.expect(!isImplicitDropFree("free", true, true, null));

    // Non-Rust module: no implicit drop semantics
    try std.testing.expect(!isImplicitDropFree("drop_in_place", false, false, null));
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", false, false, null));
}

test "isImplicitDropFree - user unsafe code detection" {
    // User unsafe function using Box::from_raw + __rust_dealloc → should NOT be suppressed
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "process_data"));
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "handle_request"));

    // GlobalAlloc trait implementation → user code, not compiler RAII
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "global_alloc"));

    // Custom allocator → user code
    try std.testing.expect(!isImplicitDropFree("__rust_dealloc", true, false, "MyAllocator::dealloc"));
}

test "valueNeedsDrop - moved and transferred values don't need drop" {
    // Normal values need drop
    try std.testing.expect(valueNeedsDrop("Vec<u8>", false, false));
    try std.testing.expect(valueNeedsDrop("String", false, false));
    try std.testing.expect(valueNeedsDrop("Box<i32>", false, false));

    // Moved values don't need drop
    try std.testing.expect(!valueNeedsDrop("Vec<u8>", true, false));
    try std.testing.expect(!valueNeedsDrop("String", true, false));

    // into_raw transferred values don't need drop
    try std.testing.expect(!valueNeedsDrop("Box<i32>", false, true));

    // Types without Drop don't need drop
    try std.testing.expect(!valueNeedsDrop("i32", false, false));
    try std.testing.expect(!valueNeedsDrop("f64", false, false));
}

test "isExplicitDropImpl - recognizes user Drop implementations" {
    // Demangled forms
    try std.testing.expect(isExplicitDropImpl("core::ops::drop::Drop::drop"));
    try std.testing.expect(isExplicitDropImpl("impl_drop"));
    // Mangled form: _ZN4core3ops4drop4Drop — contains "4Drop" but not our patterns
    // (mangled names are handled by isDropGlue, not isExplicitDropImpl)
    try std.testing.expect(!isExplicitDropImpl("_ZN4core3ops4drop4Drop4drop17hE"));
    try std.testing.expect(!isExplicitDropImpl("free"));
    try std.testing.expect(!isExplicitDropImpl("drop_in_place"));
}

// ============================================================================
// FIX: Precise compiler-internal function detection (mangled name whitelist)
// ============================================================================

test "isCompilerGeneratedRustFunction - compiler internal functions are detected" {
    // C++ standard library
    try std.testing.expect(isCompilerGeneratedRustFunction("_ZNSt6vectorIiEE9push_backERKi"));
    try std.testing.expect(isCompilerGeneratedRustFunction("_ZNSt9basic_stringIcE"));

    // Rust core/alloc internals
    try std.testing.expect(isCompilerGeneratedRustFunction("_ZN4core3ptr13drop_in_place17hE"));
    try std.testing.expect(isCompilerGeneratedRustFunction("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(isCompilerGeneratedRustFunction("_RN4core3fmt::Formatter"));

    // Compiler intrinsics
    try std.testing.expect(isCompilerGeneratedRustFunction("__rust_alloc"));
    try std.testing.expect(isCompilerGeneratedRustFunction("__rdl_dealloc"));

    // Itanium ABI internals
    try std.testing.expect(isCompilerGeneratedRustFunction("_ZGVN3foo3barE"));
    try std.testing.expect(isCompilerGeneratedRustFunction("_GLOBAL__sub_I_main"));
}

test "isCompilerGeneratedRustFunction - user mangled functions are NOT detected" {
    // User C++ class methods should NOT be matched
    try std.testing.expect(!isCompilerGeneratedRustFunction("_ZN9my_app4mainE"));
    try std.testing.expect(!isCompilerGeneratedRustFunction("_ZN3app7my_class12do_somethingE"));
    try std.testing.expect(!isCompilerGeneratedRustFunction("_ZN6mylib4DataC1Ev"));

    // User Rust pub fn should NOT be matched
    try std.testing.expect(!isCompilerGeneratedRustFunction("_ZN6mycrate4func17process_dataEv"));
    try std.testing.expect(!isCompilerGeneratedRustFunction("_RNv6mycrate4func")); // Rust v0 user code

    // Non-mangled user functions
    try std.testing.expect(!isCompilerGeneratedRustFunction("my_function"));
    try std.testing.expect(!isCompilerGeneratedRustFunction("main"));
    try std.testing.expect(!isCompilerGeneratedRustFunction("handle_request"));
}
