//! Semantic Analysis Hooks
//!
//! Language-specific and domain-specific analysis hooks for FFI boundary detection.
//! These hooks extend the generic pattern matching in SemanticRegistry with
//! deeper semantic understanding of language-specific patterns.
//!
//! Hooks:
//! - rustOwnershipHook: Detects unpaired into_raw/from_raw (ownership leak)
//! - goEscapeHook: Detects Go pointer escape to C (cgo safety)
//! - pythonRefcountHook: Detects unbalanced Py_INCREF/Py_DECREF
//!
//! State tracking:
//! - Rust ownership uses a transfer map to track paired into_raw/from_raw calls
//! - Python refcounting uses a balance map to track INCREF/DECREF per-pointer

const std = @import("std");
const types = @import("types.zig");

// ============================================================================
// Rust Ownership State Machine
// ============================================================================

/// Tracks ownership transfers across a function scope.
/// Each `into_raw` records the pointer as "transferred out".
/// Each `from_raw` clears the record. Unpaired transfers at end-of-function
/// are reported as potential leaks.
// SAFETY: These are lazily initialized via rustOwnershipStateInit()/
// pythonRefcountStateInit(). All access paths MUST check *_state_initialized
// before use. `undefined` is required because AutoHashMap cannot be
// initialized at comptime for threadlocal storage.
threadlocal var rust_transfer_map: std.AutoHashMap(u64, void) = undefined;
threadlocal var rust_state_initialized: bool = false;

pub fn rustOwnershipStateInit(allocator: std.mem.Allocator) !void {
    if (!rust_state_initialized) {
        rust_transfer_map = std.AutoHashMap(u64, void).init(allocator);
        rust_state_initialized = true;
    }
}

pub fn rustOwnershipStateDeinit() void {
    if (rust_state_initialized) {
        rust_transfer_map.deinit();
        rust_state_initialized = false;
    }
}

pub fn rustOwnershipStateReset() void {
    if (rust_state_initialized) {
        rust_transfer_map.clearRetainingCapacity();
    }
}

/// Get count of unpaired ownership transfers (for end-of-function reporting).
pub fn rustUnpairedTransferCount() usize {
    return if (rust_state_initialized) rust_transfer_map.count() else 0;
}

/// Rust ownership hook with stateful pairing tracking.
///
/// State machine:
///   IDLE ──into_raw(ptr)──→ TRANSFERRED_OUT(ptr)
///   TRANSFERRED_OUT ──from_raw(same_ptr)──→ IDLE (paired ✅)
///   TRANSFERRED_OUT at EOF → report potential leak ⚠️
/// Check if a pattern appears at a method boundary (after :: or .) in the function name.
/// This prevents false positives like "not_into_raw_helper" matching "into_raw".
fn isOwnershipMethodBoundary(name: []const u8, pat: []const u8) bool {
    const idx = std.mem.indexOf(u8, name, pat) orelse return false;
    if (idx == 0) return true; // Pattern at start is OK
    // Check character before pattern: must be :: or . (method boundary)
    const prev_char = name[idx - 1];
    return prev_char == ':' or prev_char == '.';
}

pub fn rustOwnershipHook(ctx: *types.HookContext) types.HookResult {
    const callee_name = ctx.callee_name;
    const ptr_key = ctx.first_arg_ptr_val;
    if (ptr_key == 0) return .none;

    // Transfer-out patterns (ownership leaves Rust)
    // NOTE: Specific variants (Box::/Rc::/Arc::) are subsumed by the generic
    // "into_raw" entry when using endsWith/suffix matching (L96-L98).
    // Kept here for documentation clarity and future-proofing if matching logic changes.
    const transfer_out_patterns = [_][]const u8{
        "into_raw",
        "Box::into_raw",
        "Rc::into_raw",
        "Arc::into_raw",
    };

    // Transfer-in patterns (ownership returns to Rust)
    const transfer_in_patterns = [_][]const u8{
        "from_raw",
        "Box::from_raw",
        "Rc::from_raw",
        "Arc::from_raw",
    };

    for (transfer_out_patterns) |pat| {
        // BUGFIX: Use precise matching instead of bare indexOf.
        // Old: indexOf matched "not_into_raw_helper" → false positive.
        // New: require exact match OR suffix match (ownership methods end with pattern).
        const is_match = std.mem.eql(u8, callee_name, pat) or
            std.mem.endsWith(u8, callee_name, pat) or
            (std.mem.indexOf(u8, callee_name, pat) != null and
                isOwnershipMethodBoundary(callee_name, pat));
        if (is_match) {
            if (rust_state_initialized) {
                rust_transfer_map.put(ptr_key, {}) catch {};
            }
            return .none; // Don't flag yet — wait to see if from_raw pairs it
        }
    }

    for (transfer_in_patterns) |pat| {
        // BUGFIX: Same precise matching as transfer_out_patterns.
        const is_match = std.mem.eql(u8, callee_name, pat) or
            std.mem.endsWith(u8, callee_name, pat) or
            (std.mem.indexOf(u8, callee_name, pat) != null and
                isOwnershipMethodBoundary(callee_name, pat));
        if (is_match) {
            // from_raw pairs with a prior into_raw — remove from tracked set
            if (rust_state_initialized) {
                _ = rust_transfer_map.remove(ptr_key);
            }
            return .suppressed; // Paired transfer is safe
        }
    }

    return .none;
}

// ============================================================================
// Go cgo Escape Hook
// ============================================================================

/// Go cgo escape hook: detects Go pointers escaping to C code.
///
/// In Go cgo, Go-managed memory should not be stored in C variables
/// or passed to C functions that may retain them beyond the Go call frame.
///
/// Distinguishes between:
/// - Runtime safety checks (cgoCheckPointer/cgoCheckResult) — these VERIFY
///   that pointers don't escape, they are NOT escapes themselves → .suppressed
/// - Actual escape patterns (_Cgo_ptr) — indicates a pointer crossing boundary → .issue_found
pub fn goEscapeHook(ctx: *types.HookContext) types.HookResult {
    const callee_name = ctx.callee_name;

    // Runtime safety checks — these verify pointers DON'T escape, suppress them
    const go_safety_checks = [_][]const u8{
        "runtime.cgoCheckPointer",
        "runtime.cgoCheckResult",
    };
    for (go_safety_checks) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) {
            return .suppressed; // Safety check, not an actual escape
        }
    }

    // Actual escape patterns — Go pointer crossing into C territory
    const go_escape_patterns = [_][]const u8{
        "_Cgo_ptr",
        "cgo_unsafe",
    };
    for (go_escape_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) {
            return .issue_found;
        }
    }

    return .none;
}

// ============================================================================
// Python Refcount State Machine
// ============================================================================

/// Tracks reference count balance per pointer across a function scope.
/// Py_INCREF → +1, Py_DECREF → -1. Negative net count indicates potential UAF.
threadlocal var python_refcount_map: std.AutoHashMap(u64, i32) = undefined;
threadlocal var python_state_initialized: bool = false;

pub fn pythonRefcountStateInit(allocator: std.mem.Allocator) !void {
    if (!python_state_initialized) {
        python_refcount_map = std.AutoHashMap(u64, i32).init(allocator);
        python_state_initialized = true;
    }
}

pub fn pythonRefcountStateDeinit() void {
    if (python_state_initialized) {
        python_refcount_map.deinit();
        python_state_initialized = false;
    }
}

pub fn pythonRefcountStateReset() void {
    if (python_state_initialized) {
        python_refcount_map.clearRetainingCapacity();
    }
}

/// Get pointers with negative refcount balance (potential use-after-free).
/// Returns number of unbalanced decrements found.
pub fn pythonUnbalancedDecrefCount() usize {
    if (!python_state_initialized) return 0;
    var count: usize = 0;
    var iter = python_refcount_map.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* < 0) count += 1;
    }
    return count;
}

/// Python reference count hook with stateful balance tracking.
///
/// State machine per pointer:
///   balance=0 ──Py_INCREF──→ balance=+1
///   balance=N ──Py_DECREF──→ balance=N-1
///   balance<0 → potential use-after-free ⚠️ (flag immediately)
///   balance≥0 at EOF → balanced ✅
pub fn pythonRefcountHook(ctx: *types.HookContext) types.HookResult {
    const callee_name = ctx.callee_name;
    const ptr_key = ctx.first_arg_ptr_val;
    if (ptr_key == 0) return .none;

    // Reference count increment (safe)
    const incref_patterns = [_][]const u8{
        "Py_INCREF",
        "Py_XINCREF",
    };

    // Reference count decrement (must be paired)
    const decref_patterns = [_][]const u8{
        "Py_DECREF",
        "Py_XDECREF",
    };

    for (incref_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) {
            if (python_state_initialized) {
                const gop = python_refcount_map.getOrPut(ptr_key) catch return .none;
                if (!gop.found_existing) {
                    gop.value_ptr.* = 0;
                }
                gop.value_ptr.* += 1;
            }
            return .suppressed; // INCREF is always safe
        }
    }

    for (decref_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) {
            if (python_state_initialized) {
                const gop = python_refcount_map.getOrPut(ptr_key) catch return .none;
                if (!gop.found_existing) {
                    gop.value_ptr.* = 0;
                }
                gop.value_ptr.* -= 1;
                // Flag immediately when balance goes negative — this DECREF
                // has no matching INCREF in this scope, indicating potential UAF
                if (gop.value_ptr.* < 0) {
                    return .issue_found;
                }
            } else {
                return .issue_found; // No state tracking available, flag conservatively
            }
            return .none; // Balance still ≥ 0, no issue yet
        }
    }

    return .none;
}

// ============================================================================
// Hook Registration & Lifecycle
// ============================================================================

/// Initialize all hook state machines. Call once before analysis begins.
pub fn initHookStates(allocator: std.mem.Allocator) !void {
    try rustOwnershipStateInit(allocator);
    try pythonRefcountStateInit(allocator);
}

/// Deinitialize all hook state machines. Call after analysis completes.
pub fn deinitHookStates() void {
    rustOwnershipStateDeinit();
    pythonRefcountStateDeinit();
}

/// Reset all hook states for a new function scope.
/// Call at start of each function analysis.
pub fn resetHookStatesForFunction() void {
    rustOwnershipStateReset();
    pythonRefcountStateReset();
}

/// Create the standard set of analysis hooks for registration.
/// Call this during initialization to register all built-in hooks.
pub fn registerStandardHooks(registry: anytype) !void {
    try registry.registerHook(.{
        .name = "rust_ownership",
        .target_languages = &[_][]const u8{"rust"},
        .fn_ptr = rustOwnershipHook,
    });

    try registry.registerHook(.{
        .name = "go_cgo_escape",
        .target_languages = &[_][]const u8{"go"},
        .fn_ptr = goEscapeHook,
    });

    try registry.registerHook(.{
        .name = "python_refcount",
        .target_languages = &[_][]const u8{"python"},
        .fn_ptr = pythonRefcountHook,
    });
}
