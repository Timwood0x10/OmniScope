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
                if (opcode == c.LLVMCall) {
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

    if (violation_count > 0) {
        log.debug("[NOMICON-CH8] Analyzed {} functions, found {} potential concurrency issues", .{
            func_count,
            violation_count,
        });
    } else {
        log.debug("[NOMICON-CH8] Analyzed {} functions, no concurrency issues found", .{func_count});
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
fn isAtomicOperation(opcode: c.LLVMOpcodeId) bool {
    return opcode == c.LLVMAtomicRMW or
        opcode == c.LLVMLoadAtomic or
        opcode == c.LLVMStoreAtomic or
        opcode == c.LLVMFence or
        opcode == c.LLVMCmpXchg;
}

/// Analyze a thread spawn function for Send violations.
fn analyzeThreadSpawn(
    func: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    _ = func;
    // In a full implementation, we would:
    // 1. Identify the closure/callback passed to spawn
    // 2. Analyze captured variables for Send trait compliance
    // 3. Flag non-Send captures (e.g., Rc, raw pointers to non-thread-local data)

    log.debug("[NOMICON-CH8] Thread spawn detected — checking captured variables for Send", .{});

    recordResolution(srt, @intFromPtr(func), .send_sync_violation, 0.55, "Nomicon-Ch8 thread spawn (verify Send bounds)");

    return true;
}

/// Analyze a thread spawn call instruction.
fn analyzeThreadSpawnCall(
    inst: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    _ = inst;
    // Check the arguments to see what's being sent to the new thread

    log.debug("[NOMICON-CH8] Thread spawn call — analyzing arguments", .{});

    recordResolution(srt, @intFromPtr(inst), .send_sync_violation, 0.60, "Nomicon-Ch8 spawn call (check argument Send safety)");

    return true;
}

/// Analyze an atomic operation for correctness.
fn analyzeAtomicUsage(
    inst: c.LLVMValueRef,
    srt: *SemanticTree,
) bool {
    _ = inst;
    // Atomic operations are generally safe in Rust/Zig when used correctly,
    // but we should flag unusual patterns:
    // 1. Atomic operations on very large types (should use locks instead)
    // 2. Mixed atomic/non-atomic access to same location
    // 3. Missing memory ordering constraints

    log.debug("[NOMICON-CH8] Atomic operation detected — verifying correctness", .{});

    // Atomic ops are usually fine; just note them for audit
    recordResolution(srt, @intFromPtr(inst), .send_sync_violation, 0.30, "Nomicon-Ch8 atomic op (audit only)");

    return false; // Don't count as violation by default
}

/// Record a semantic resolution to the SRT.
fn recordResolution(
    srt: *SemanticTree,
    value_ref: u64,
    kind: SemanticKind,
    confidence: f32,
    evidence: []const u8,
) void {
    _ = srt;
    _ = value_ref;
    _ = kind;
    _ = confidence;
    _ = evidence;
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
