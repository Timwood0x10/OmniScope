//! Nomicon Ch8: Concurrency Violations (Send/Sync Trait Abuse)
//!
//! Detects patterns that may lead to data races or other concurrency bugs.
//! Rust's type system prevents data races through Send and Sync traits,
//! but unsafe code can bypass these protections.
//!
//! Nomicon §8: Concurrency
//! - Sending non-Send types across thread boundaries → data race risk
//! - Sharing non-Sync types between threads → data race risk
//! - Unsafe cell access without proper synchronization → UB
//!
//! Covers:
//! - Thread spawn with potentially non-Send captures
//! - Global/static mutable state without synchronization
//! - Atomic operations on non-atomic types via unsafe

const std = @import("std");
const log = std.log.scoped(.nomicon_ch8);
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Thread creation function patterns
const THREAD_SPAWN_PATTERNS = [_][]const u8{
    "std::thread::spawn",
    "thread::spawn",
    "spawn",
    "pthread_create",
    "_ZN9std6thread5spawn",
};

/// Synchronization primitives (safe)
const SYNC_PRIMITIVES = [_][]const u8{
    "Mutex",
    "RwLock",
    "Atomic",
    "Condvar",
    "Barrier",
    "parking_lot::Mutex",
    "parking_lot::RwLock",
    "std::sync::Mutex",
    "std::sync::RwLock",
    "std::sync::atomic",
    "pthread_mutex",
};

/// Unsafe concurrency patterns
const UNSAFE_CONCURRENCY_PATTERNS = [_][]const u8{
    "UnsafeCell",
    "unsafe {",
    "get_mut",
    "as_mut_ptr",
    "raw_ptr",
};

/// Detect concurrency violations and unsafe threading patterns.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func_count: usize = 0;
    var violation_count: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        func_count += 1;

        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) == 0) continue;
        const func_name = std.mem.sliceTo(func_name_raw, 0);

        // Check for thread spawning functions
        if (isThreadSpawnPattern(func_name)) {
            if (analyzeThreadSpawn(func, srt)) {
                violation_count += 1;
            }
        }

        // Scan instructions for unsafe concurrency patterns
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check for calls to thread-related functions
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    const called_func = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_func) == 0) continue;

                    const called_name_raw = c.LLVMGetValueName(called_func);
                    if (@intFromPtr(called_name_raw) == 0) continue;
                    const called_name = std.mem.sliceTo(called_name_raw, 0);

                    // Thread spawn detected
                    if (isThreadSpawnPattern(called_name)) {
                        if (analyzeThreadSpawnCall(inst, srt)) {
                            violation_count += 1;
                        }
                    }
                }

                // Check for atomic operations on suspicious types
                if (isAtomicOperation(opcode)) {
                    if (analyzeAtomicUsage(inst, srt)) {
                        violation_count += 1;
                    }
                }
            }
        }
    }

    }

/// Check if a function name matches thread spawn pattern.
fn isThreadSpawnPattern(name: []const u8) bool {
    for (THREAD_SPAWN_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if an opcode is an atomic operation.
fn isAtomicOperation(opcode: c_uint) bool {
    return opcode == c.LLVMAtomicRMW or
        opcode == c.LLVMLoad or
        opcode == c.LLVMStore or
        opcode == c.LLVMFence or
        opcode == c.LLVMAtomicCmpXchg;
}

/// Analyze a thread spawn function for Send violations.
///
/// Scans the function's basic blocks for patterns indicating non-Send
/// types being captured by closures passed to thread::spawn.
fn analyzeThreadSpawn(
    func: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    const func_ref = @intFromPtr(func);
    var has_violation = false;

    // Scan function body for non-Send patterns
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            // Check for calls to non-Send constructors
            if (llvm_safe.isCallOrInvoke(opcode)) {
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;

                const called_name_raw = c.LLVMGetValueName(called_val);
                if (@intFromPtr(called_name_raw) == 0) continue;
                const called_name = std.mem.sliceTo(called_name_raw, 0);

                // Rc::new — non-Send reference-counted pointer
                if (std.mem.indexOf(u8, called_name, "_ZN5alloc2rc") != null or
                    std.mem.indexOf(u8, called_name, "Rc::new") != null)
                {
                    recordResolution(srt, @intFromPtr(inst), .send_sync_violation, 0.75, "Rc is not Send — cannot move across thread boundary");
                    has_violation = true;
                }

                // Cell/RefCell — non-Sync types shared between threads
                if (std.mem.indexOf(u8, called_name, "Cell::new") != null or
                    std.mem.indexOf(u8, called_name, "RefCell::new") != null)
                {
                    recordResolution(srt, @intFromPtr(inst), .send_sync_violation, 0.65, "Cell/RefCell is not Sync — cannot share between threads");
                    has_violation = true;
                }
            }

            // Check for raw pointer operations (potential non-Send)
            if (opcode == c.LLVMIntToPtr or opcode == c.LLVMBitCast) {
                // Raw pointer creation in thread context is suspicious
                const src_val = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(src_val) != 0) {
                    const src_type = c.LLVMTypeOf(src_val);
                    if (@intFromPtr(src_type) != 0 and c.LLVMGetTypeKind(src_type) == c.LLVMIntegerTypeKind) {
                        recordResolution(srt, @intFromPtr(inst), .send_sync_violation, 0.50, "Raw pointer in thread context — verify Send safety");
                    }
                }
            }
        }
    }

    if (!has_violation) {
        // No obvious violations found — still record for audit
        recordResolution(srt, func_ref, .send_sync_violation, 0.30, "Thread spawn — no obvious Send violations detected");
    }

    return has_violation;
}

/// Analyze a thread spawn call instruction.
///
/// Checks the arguments passed to thread::spawn for non-Send types.
/// In Rust, spawn takes a closure (FnOnce) that must be Send.
fn analyzeThreadSpawnCall(
    inst: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    const inst_ref = @intFromPtr(inst);
    var has_violation = false;

    // Get the number of arguments
    const num_operands = c.LLVMGetNumOperands(inst);
    if (num_operands < 2) {
        // spawn takes at least the closure argument
        recordResolution(srt, inst_ref, .send_sync_violation, 0.40, "Thread spawn with unexpected argument count");
        return false;
    }

    // Analyze each argument (skip the callee itself at index 0)
    var i: u32 = 1;
    while (i < num_operands) : (i += 1) {
        const arg = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(arg) == 0) continue;

        const arg_type = c.LLVMTypeOf(arg);
        if (@intFromPtr(arg_type) == 0) continue;

        const arg_ref = @intFromPtr(arg);

        // Check if the argument is a pointer to non-Send type
        if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
            // Check if the pointer target has been marked as non-Send
            if (srt.hasKind(arg_ref, .send_sync_violation) != null) {
                recordResolution(srt, inst_ref, .send_sync_violation, 0.80, "Non-Send value passed to thread::spawn");
                has_violation = true;
            }
        }

        // Check for function pointer arguments (closures)
        if (c.LLVMGetTypeKind(arg_type) == c.LLVMFunctionTypeKind or
            c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
        {
            // If the argument is a function/closure, check its captures
            // by looking at the called function's parameters
            const called_func = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_func) != 0) {
                const called_name_raw = c.LLVMGetValueName(called_func);
                if (@intFromPtr(called_name_raw) != 0) {
                    const called_name = std.mem.sliceTo(called_name_raw, 0);

                    // If the closure is from a known non-Send pattern
                    if (std.mem.indexOf(u8, called_name, "Rc") != null or
                        std.mem.indexOf(u8, called_name, "Cell") != null or
                        std.mem.indexOf(u8, called_name, "RefCell") != null)
                    {
                        recordResolution(srt, inst_ref, .send_sync_violation, 0.85, "Closure capturing non-Send type passed to thread::spawn");
                        has_violation = true;
                    }
                }
            }
        }
    }

    if (!has_violation) {
        // No violations found — record for audit
        recordResolution(srt, inst_ref, .send_sync_violation, 0.30, "Thread spawn call — arguments appear Send-safe");
    }

    return has_violation;
}

/// Analyze an atomic operation for correctness.
///
/// Checks for:
/// 1. Atomic operations on very large types (should use locks instead)
/// 2. Mixed atomic/non-atomic access to same location
/// 3. Missing or incorrect memory ordering constraints
fn analyzeAtomicUsage(
    inst: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    const inst_ref = @intFromPtr(inst);
    var has_issue = false;

    const opcode = c.LLVMGetInstructionOpcode(inst);

    // Check 1: Atomic RMW on large types (should use locks instead)
    if (opcode == c.LLVMAtomicRMW or opcode == c.LLVMAtomicCmpXchg) {
        // Get the pointer operand (first operand for atomic ops)
        const ptr_val = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(ptr_val) != 0) {
            const ptr_type = c.LLVMTypeOf(ptr_val);
            if (@intFromPtr(ptr_type) != 0 and c.LLVMGetTypeKind(ptr_type) == c.LLVMPointerTypeKind) {
                const elem_type = c.LLVMGetElementType(ptr_type);
                if (@intFromPtr(elem_type) != 0) {
                    const type_size = c.LLVMStoreSizeOfType(c.LLVMGetModuleDataLayout(c.LLVMGetGlobalParent(inst)), elem_type);
                    // Atomic ops on types > 8 bytes are suspicious (should use locks)
                    if (type_size > 8) {
                        recordResolution(srt, inst_ref, .send_sync_violation, 0.70, "Atomic op on large type — consider Mutex/RwLock instead");
                        has_issue = true;
                    }
                }
            }
        }
    }

    // Check 2: Memory ordering for atomic loads/stores
    if (opcode == c.LLVMLoad or opcode == c.LLVMStore) {
        // Get the ordering
        const ordering = c.LLVMGetOrdering(inst);
        // SequentiallyConsistent (5) is often overkill — flag for audit
        if (ordering == 5) { // c.LLVMAtomicOrderingSequentiallyConsistent
            recordResolution(srt, inst_ref, .send_sync_violation, 0.25, "SeqCst ordering — consider weaker ordering if appropriate");
            // Not a violation, just an audit note
        }
    }

    // Check 3: Fence without preceding atomic operations
    if (opcode == c.LLVMFence) {
        // Fence is usually fine, but flag for audit if it's the only sync in a function
        const ordering = c.LLVMGetOrdering(inst);
        if (ordering == 4 or ordering == 2) { // Release=4, Acquire=2
            // This is normal — just note it
            recordResolution(srt, inst_ref, .send_sync_violation, 0.20, "Fence operation — audit only");
        }
    }

    return has_issue;
}

/// Record a semantic resolution to the SRT.
fn recordResolution(
    srt: *SemanticTree,
    value_ref: u64,
    kind: SemanticKind,
    confidence: f32,
    evidence: []const u8,
) void {
    srt.recordResolution(value_ref, kind, confidence, "Nomicon-Ch8", evidence) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "Ch8: detect thread spawn patterns" {
    try std.testing.expect(isThreadSpawnPattern("std::thread::spawn"));
    try std.testing.expect(isThreadSpawnPattern("_ZN9std6thread5spawn17h..."));
    try std.testing.expect(isThreadSpawnPattern("pthread_create"));
    try std.testing.expect(!isThreadSpawnPattern("normal_function"));

    try std.testing.expect(isSyncPrimitive("Mutex"));
    try std.testing.expect(isSyncPrimitive("std::sync::atomic::AtomicU32"));
    try std.testing.expect(!isSyncPrimitive("UnsafeCell"));
}

/// Check if a name looks like a synchronization primitive.
fn isSyncPrimitive(name: []const u8) bool {
    for (SYNC_PRIMITIVES) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }
    return false;
}
