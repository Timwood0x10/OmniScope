//! Lightweight Inter-Procedural FFI Analysis (V1)
//!
//! Cross-function reasoning LIMITED to FFI boundary neighborhoods.
//! Does NOT build full call graphs or do whole-program analysis.
//!
//! What we CAN see across function boundaries:
//!   1. Caller's NULL/return-value check on FFI callee result
//!   2. Ownership transfer direction (caller → callee vs callee → caller)
//!   3. Callback data lifetime (does callback outlive stack frame?)
//!   4. Resource lifecycle pairing hint (open/close across functions)
//!   5. Alias-aware acquisition: ptr from other func → FFI arg (V2)
//!
//! What we explicitly do NOT do (deferred to v0.2.x):
//!   - Full call graph construction
//!   - Full data flow through complex control flow
//!
//! Reference: plan/v0.1.8.md P0-2, plan/rules/skills.md (surgical changes)

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const word_boundary = @import("../../utils/word_boundary.zig");

const NULL_GUARD_MAX_SCAN: u32 = 15;

/// Ownership transfer direction observed at an FFI call site.
pub const OwnershipTransfer = enum(u8) {
    /// No ownership transfer detected
    none,
    /// Caller passes owned resource to callee (e.g., free(handle))
    to_callee,
    /// Callee returns owned resource to caller (e.g., handle = dlopen())
    to_caller,
};

/// A single FFI call site with cross-function context.
///
/// Populated by scanning a caller function's instructions for
/// FFI boundary calls and their surrounding context.
pub const FFICallSite = struct {
    /// The caller function containing this call site
    caller_func: c.LLVMValueRef,
    /// The call instruction itself
    call_inst: c.LLVMValueRef,
    /// Name of the called FFI function
    callee_name: []const u8,
    /// Whether the return value is used (stored/passed/compared)
    result_used: bool,
    /// Whether caller checks return value against NULL before use
    has_null_guard: bool,
    /// Detected ownership transfer direction
    ownership_transfer: OwnershipTransfer,

    pub fn init(
        caller_func: c.LLVMValueRef,
        call_inst: c.LLVMValueRef,
        callee_name: []const u8,
    ) FFICallSite {
        return .{
            .caller_func = caller_func,
            .call_inst = call_inst,
            .callee_name = callee_name,
            .result_used = false,
            .has_null_guard = false,
            .ownership_transfer = .none,
        };
    }
};

/// Analyze all FFI boundary calls within a single function.
///
/// For each FFI call found, scans the surrounding basic blocks to determine:
/// - Is the return value used?
/// - Is there a NULL guard after the call?
/// - Is there an ownership transfer pattern?
///
/// Returns an array of analyzed call sites (caller owns the memory).
pub fn analyze_ffi_caller_context(
    allocator: std.mem.Allocator,
    func: c.LLVMValueRef,
    is_ffi_fn: *const fn ([]const u8) bool,
) ![]FFICallSite {
    var sites = std.ArrayList(FFICallSite).init(allocator);
    defer sites.deinit();

    // Scan all basic blocks in the function for call instructions
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            // Get called function name
            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) continue;
            const name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(name_ptr) == 0) continue;
            const func_name = std.mem.span(name_ptr);
            if (func_name.len == 0) continue;

            // Check if this is an FFI boundary function
            if (!is_ffi_fn(func_name)) continue;

            // Found an FFI call site — analyze its context
            var site = FFICallSite.init(func, inst, func_name);

            // Check if return value is used
            site.result_used = check_result_used(inst);

            // Check for NULL guard in subsequent instructions
            site.has_null_guard = check_null_guard_after(inst);

            // Detect ownership transfer patterns
            site.ownership_transfer = detect_ownership_transfer(inst, func_name);

            try sites.append(site);
        }
    }

    return try sites.toOwnedSlice();
}

/// Check if the return value of a call instruction is used anywhere.
///
/// Scans all uses of the instruction's result.
/// If any use exists (store, pass, compare, branch), returns true.
fn check_result_used(call_inst: c.LLVMValueRef) bool {
    var use = c.LLVMGetFirstUse(call_inst);
    while (@intFromPtr(use) != 0) : (use = c.LLVMGetNextUse(use)) {
        // Any use at all means the result is used
        return true;
    }
    return false;
}

/// Check if there's a NULL guard after the given call instruction.
///
/// Looks within the same basic block (and limited successor blocks)
/// for an ICMP equality comparison against NULL followed by a conditional branch.
///
/// This detects patterns like:
///   %ptr = call dlopen(...)
///   %cmp = icmp eq %ptr, null
///   br i1 %cmp, label %error, label %success
pub fn check_null_guard_after(call_inst: c.LLVMValueRef) bool {
    // Scan forward from the call instruction looking for ICMP + branch.
    //
    // IMPORTANT: NULL guard checks often span multiple basic blocks in LLVM IR:
    //   - Call instruction is in entry block
    //   - ICMP comparison may be in a successor block (after conditional branch)
    //   - Branch on that comparison is in the same or next block
    //
    // To handle this, we use a simple work-queue approach that follows terminator
    // instructions to successor blocks (limited by total instruction count).
    const max_scan: u32 = NULL_GUARD_MAX_SCAN;
    var total_scanned: u32 = 0;

    // Start with the current basic block's next instruction
    var inst = c.LLVMGetNextInstruction(call_inst);

    // Use a simple stack to track pending basic blocks to scan
    // (avoids recursion depth issues while keeping code simple)
    var bb_stack: [4]c.LLVMBasicBlockRef = undefined; // Max 4 successor levels deep
    var bb_stack_len: usize = 0;
    var visited_bbs: [8]c.LLVMBasicBlockRef = undefined; // Avoid re-scanning same BB
    var visited_bbs_len: usize = 0;

    // Helper to check if we've already queued/visited this BB (inlined for Zig compatibility)
    const isBBVisited = struct {
        fn check(bb: c.LLVMBasicBlockRef, list: []c.LLVMBasicBlockRef, len: usize) bool {
            for (list[0..len]) |visited| {
                if (@intFromPtr(visited) == @intFromPtr(bb)) return true;
            }
            return false;
        }
    }.check;

    while (@intFromPtr(inst) != 0 and total_scanned < max_scan) : ({
        // Move to next instruction in current block
        inst = c.LLVMGetNextInstruction(inst);
        total_scanned += 1;

        // If we've exhausted the current block, try to get next from stack
        if (@intFromPtr(inst) == 0 and bb_stack_len > 0) {
            bb_stack_len -= 1;
            const next_bb = bb_stack[bb_stack_len];
            inst = c.LLVMGetFirstInstruction(next_bb);
        }
    }) {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Look for ICMP comparison
        if (opcode == c.LLVMICmp) {
            // Check if one operand is our call result and other is NULL
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops >= 2) {
                const op0 = c.LLVMGetOperand(inst, 0);
                const op1 = c.LLVMGetOperand(inst, 1);

                // Check if either operand references our call result
                const refs_call_result = (@intFromPtr(op0) == @intFromPtr(call_inst)) or
                    (@intFromPtr(op1) == @intFromPtr(call_inst));

                if (refs_call_result) {
                    // Check if the other operand is NULL constant
                    const other_op = if (@intFromPtr(op0) == @intFromPtr(call_inst)) op1 else op0;
                    if (is_null_constant(other_op)) {
                        // Found ICMP against NULL — now look for branch
                        return has_branch_on_comparison(inst);
                    }
                }
            }
        }

        // At terminator instructions: follow successors (limited depth)
        const is_terminator = opcode == c.LLVMBr or
            opcode == c.LLVMSwitch or
            opcode == c.LLVMIndirectBr or
            opcode == c.LLVMRet or
            opcode == c.LLVMInvoke;

        if (is_terminator and bb_stack_len < bb_stack.len and total_scanned < max_scan) {
            // For conditional branches, follow both successors
            if (opcode == c.LLVMBr) {
                const then_bb = c.LLVMGetSuccessor(inst, 0);
                const else_bb = c.LLVMGetSuccessor(inst, 1);

                // Queue successor blocks that haven't been visited yet
                if (@intFromPtr(then_bb) != 0 and !isBBVisited(then_bb, &visited_bbs, visited_bbs_len)) {
                    bb_stack[bb_stack_len] = then_bb;
                    bb_stack_len += 1;
                    visited_bbs[visited_bbs_len] = then_bb;
                    visited_bbs_len += 1;
                }
                if (@intFromPtr(else_bb) != 0 and !isBBVisited(else_bb, &visited_bbs, visited_bbs_len)) {
                    bb_stack[bb_stack_len] = else_bb;
                    bb_stack_len += 1;
                    visited_bbs[visited_bbs_len] = else_bb;
                    visited_bbs_len += 1;
                }
            }
            // Don't break here — let the loop try to pop from stack first
        } else if (is_terminator) {
            // For non-branch terminators (ret, switch, etc.), stop scanning this path
            break;
        }
    }

    return false;
}

/// Check if an LLVM value is a NULL constant (null pointer or zero integer).
fn is_null_constant(val: c.LLVMValueRef) bool {
    if (@intFromPtr(val) == 0) return false;

    // Check for constant pointer null
    if (c.LLVMIsAConstantPointerNull(val) != null) return true;

    // Check for constant integer zero (NULL is often represented as i64 0 or i32 0)
    // IMPORTANT: Only treat as potential NULL if the width matches common pointer sizes.
    // This prevents false positives where small integers (i8 0, i16 0) used in
    // non-pointer contexts are incorrectly classified as NULL guards.
    if (c.LLVMIsAConstantInt(val) != null) {
        const width = c.LLVMGetIntTypeWidth(c.LLVMTypeOf(val));
        if (width > 4096) return false;

        // Only consider pointer-sized or near-pointer-sized widths as potential NULL:
        // - 32-bit: Common on 32-bit platforms and for some pointer comparisons
        // - 64-bit: Standard pointer size on 64-bit platforms
        // - Other widths (8, 16 bits): Too small, likely just integer zero, not NULL
        const is_pointer_width = (width == 32 or width == 64);
        if (is_pointer_width) {
            return true;
        }
        // For other widths, be conservative and don't treat as NULL
        // unless it's exactly pointer-sized (avoids FP from i8/i16 zeros)
    }

    return false;
}

/// Check if the result of a comparison instruction feeds into a branch.
/// Scans for users of the comparison that are branch instructions.
fn has_branch_on_comparison(cmp_inst: c.LLVMValueRef) bool {
    var use = c.LLVMGetFirstUse(cmp_inst);
    while (@intFromPtr(use) != 0) : (use = c.LLVMGetNextUse(use)) {
        const user = c.LLVMGetUser(use);
        if (@intFromPtr(user) == 0) continue;

        const user_opcode = c.LLVMGetInstructionOpcode(user);
        if (user_opcode == c.LLVMBr) {
            // Conditional branch on our comparison → NULL guard confirmed
            return true;
        }
    }
    return false;
}

/// Detect ownership transfer direction at an FFI call site.
///
/// Patterns detected:
///   - to_caller: return value of alloc function stored to local/global
///   - to_callee: local handle passed as argument to free/close function
fn detect_ownership_transfer(call_inst: c.LLVMValueRef, callee_name: []const u8) OwnershipTransfer {
    // Pattern 1: Callee returns resource to caller
    // Check if this looks like an allocation/acquisition function
    if (is_acquisition_function(callee_name)) {
        if (check_result_used(call_inst)) {
            return .to_caller;
        }
    }

    // Pattern 2: Caller passes resource to callee (free/close)
    // This would require checking arguments of the call instruction
    // For V1, we do a simple name-based heuristic on the callee
    if (is_release_function(callee_name)) {
        return .to_callee;
    }

    return .none;
}

/// Check if a function is a known resource acquisition function.
///
/// Acquisition functions return owned resources (memory handles, file descriptors,
/// sockets, etc.) that must be explicitly released by the caller. Detecting these
/// functions is crucial for:
/// - **Ownership tracking**: Knowing when ownership is transferred to the caller
/// - **Leak detection**: Identifying unreleased resources
/// - **False positive suppression**: Avoiding reporting heap returns in acquisition
///   functions as memory leaks (they're intentional ownership transfers)
///
/// **Supported categories:**
/// - Memory allocators: malloc, calloc, realloc, mmap
/// - File I/O: fopen, sqlite3_open
/// - Network: socket, accept
/// - Dynamic loading: dlopen, dlsym, LoadLibrary, GetProcAddress
/// - Crypto (OpenSSL): EVP_CIPHER_CTX_new, BIO_new, RSA_new
/// - Java (JNI): JNI_FindClass, NewGlobalRef
/// - Python (C API): PyGILState_Ensure, PyObject_Call
///
/// Parameters:
///   - name: Function name string to check (case-sensitive)
///
/// Returns:
///   - true if the function is a known resource acquisition function
///   - false otherwise (including unknown functions)
///
/// Example:
/// ```zig
/// if (is_acquisition_function("malloc")) {
///     // This function returns owned memory - intentional transfer, not a leak
///     diag.debug("Heap return in acquisition function", .{});
/// }
/// ```
pub fn is_acquisition_function(name: []const u8) bool {
    const acquisitions = [_][]const u8{
        "dlopen",       "dlsym",             "mmap",               "malloc",
        "calloc",       "realloc",           "socket",             "accept",
        "fopen",        "sqlite3_open",      "EVP_CIPHER_CTX_new", "BIO_new",
        "RSA_new",      "LoadLibrary",       "GetProcAddress",     "JNI_FindClass",
        "NewGlobalRef", "PyGILState_Ensure", "PyObject_Call",
    };
    for (acquisitions) |acq| {
        // Use word boundary matching to prevent false positives.
        // Example: "my_free_wrapper" should NOT match "free"
        if (word_boundary.isWordBoundaryMatch(name, acq)) return true;
    }
    return false;
}

/// Known release functions that consume owned resources.
fn is_release_function(name: []const u8) bool {
    const releases = [_][]const u8{
        "dlclose",   "munmap",        "free",                "close",
        "fclose",    "sqlite3_close", "EVP_CIPHER_CTX_free", "BIO_free",
        "RSA_free",  "FreeLibrary",   "DeleteGlobalRef",     "PyGILState_Release",
        "Py_DECREF",
    };
    for (releases) |rel| {
        // Use word boundary matching to prevent false positives.
        // Example: "unfreeze" should NOT match "free"
        if (word_boundary.isWordBoundaryMatch(name, rel)) return true;
    }
    return false;
}

/// Detects whether an FFI call has cross-function alias evidence.
///
/// When a pointer argument to an FFI call originates from:
///   - A function parameter (passed from caller's caller)
///   - A global variable load (shared state)
///   - A return value of another non-FFI function
///
/// This indicates the pointer may have aliases we can't see in the current
/// function scope. Such pointers are higher risk for use-after-free when
/// passed across language boundaries because their lifetime is not locally
/// controlled.
///
/// V2 ENHANCEMENT (2026-05-05): Now integrates CallGraph BFS traversal for cross-function
/// FFI reasoning. If call_graph is provided, checks whether the inner
/// callee can reach an FFI boundary, providing stronger evidence of cross-function risk.
///
/// Parameters:
///   - call_inst: The FFI call instruction to analyze
///   - call_graph: Optional semantics CallGraph for cross-function reachability analysis.
///                 If null, falls back to name-based heuristics (V1 behavior)
///
/// Returns true if any pointer argument shows cross-function alias evidence.
pub fn detect_cross_func_alias(
    call_inst: c.LLVMValueRef,
    call_graph: ?*@import("../../semantics/call_graph.zig").CallGraph,
) bool {
    const num_args = c.LLVMGetNumArgOperands(call_inst);
    for (0..@as(usize, @intCast(num_args))) |i| {
        const arg = c.LLVMGetOperand(call_inst, @intCast(i));
        if (@intFromPtr(arg) == 0) continue;

        // Pattern 1: Argument is a function parameter → came from caller
        if (c.LLVMIsAArgument(arg) != null) return true;

        // Pattern 2: Argument is a load from global address → shared state
        if (c.LLVMGetInstructionOpcode(arg) == c.LLVMLoad) {
            const ptr_op = c.LLVMGetOperand(arg, 0);
            if (@intFromPtr(ptr_op) != 0) {
                const ptr_name = c.LLVMGetValueName(ptr_op);
                if (@intFromPtr(ptr_name) != 0) {
                    const name = std.mem.span(ptr_name);
                    if (std.mem.startsWith(u8, name, "@") or
                        std.mem.indexOf(u8, name, "global") != null)
                    {
                        return true;
                    }
                }
            }
        }

        // Pattern 3: Argument is return value of another call → cross-func origin
        if (c.LLVMGetInstructionOpcode(arg) == c.LLVMCall or
            c.LLVMGetInstructionOpcode(arg) == c.LLVMInvoke)
        {
            const inner_callee = c.LLVMGetCalledValue(arg);
            if (@intFromPtr(inner_callee) != 0) {
                const inner_name_raw = c.LLVMGetValueName(inner_callee);
                if (@intFromPtr(inner_name_raw) != 0) {
                    const n = std.mem.span(inner_name_raw);
                    // Non-trivial inner call suggests cross-function data flow
                    if (!is_release_function(n) and !is_acquisition_function(n)) {
                        // V2: Check if inner callee reaches FFI boundary via CallGraph
                        // This provides stronger evidence than just name-based heuristics
                        if (call_graph) |sg| {
                            // Use CallGraph for precise cross-function reachability
                            if (reachesFFIBoundaryViaCallGraph(sg, n, 10)) {
                                return true;
                            }
                            // If CallGraph says no FFI reachability, don't flag it
                            // This reduces false positives compared to V1 heuristic
                        } else {
                            // V1 fallback: No CallGraph available, use conservative heuristic
                            return true;
                        }
                    }
                }
            }
        }
    }

    return false;
}

/// V2: Cross-function FFI reachability analysis using CallGraph.
///
/// Checks whether a given function can reach any FFI boundary through the call graph.
/// This enables inter-procedural reasoning about FFI safety:
/// - If func A calls func B, and B calls an FFI function, then A's data can reach FFI
/// - This is critical for detecting cross-language data leaks and use-after-free across FFI boundaries
///
/// Parameters:
///   - sg: The semantics CallGraph (built by CallGraphPass)
///        NOTE: Uses mutable pointer (*CallGraph) to match underlying API signatures.
///        The function does NOT modify CallGraph — this is a const-correctness limitation
///        in call_graph.zig's getNode/getNodeByName/reachesFFIBoundary methods which should
///        accept *const CallGraph but currently require *CallGraph.
///   - func_name: The function to check for FFI boundary reachability
///   - max_depth: Maximum BFS depth to prevent infinite loops (default: 10)
///
/// Returns: true if func_name can reach any FFI boundary within max_depth hops
pub fn reachesFFIBoundaryViaCallGraph(
    sg: *@import("../../semantics/call_graph.zig").CallGraph,
    func_name: []const u8,
    max_depth: u32,
) bool {
    const node_id = sg.getNodeByName(func_name) orelse return false;
    return sg.reachesFFIBoundary(node_id, max_depth);
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "FFICallSite init" {
    // Verify struct initializes correctly with defaults
    const site = FFICallSite.init(undefined, undefined, "test_func");
    try std.testing.expect(!site.result_used);
    try std.testing.expect(!site.has_null_guard);
    try std.testing.expectEqual(OwnershipTransfer.none, site.ownership_transfer);
}

test "OwnershipTransfer variants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipTransfer.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipTransfer.to_callee));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipTransfer.to_caller));
}

test "is_acquisition_function - known allocators" {
    try std.testing.expect(is_acquisition_function("dlopen"));
    try std.testing.expect(is_acquisition_function("malloc"));
    try std.testing.expect(is_acquisition_function("sqlite3_open"));
    try std.testing.expect(is_acquisition_function("EVP_CIPHER_CTX_new"));
    try std.testing.expect(is_acquisition_function("JNI_FindClass"));
}

test "is_acquisition_function - non-acquisitions rejected" {
    try std.testing.expect(!is_acquisition_function("printf"));
    try std.testing.expect(!is_acquisition_function("strlen"));
    try std.testing.expect(!is_acquisition_function("memcpy"));
    try std.testing.expect(!is_acquisition_function("my_function"));
}

test "is_release_function - known deallocators" {
    try std.testing.expect(is_release_function("dlclose"));
    try std.testing.expect(is_release_function("free"));
    try std.testing.expect(is_release_function("sqlite3_close"));
    try std.testing.expect(is_release_function("EVP_CIPHER_CTX_free"));
    try std.testing.expect(is_release_function("DeleteGlobalRef"));
}

test "is_release_function - non-releases rejected" {
    try std.testing.expect(!is_release_function("printf"));
    try std.testing.expect(!is_release_function("strlen"));
    try std.testing.expect(!is_release_function("my_cleanup"));
}

test "detect_cross_func_alias - stub" {
    // Full test requires LLVM IR context; this verifies compilation
    _ = detect_cross_func_alias;
}
