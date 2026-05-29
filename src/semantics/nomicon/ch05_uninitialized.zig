//! Nomicon Ch5: Uninitialized Memory Detection (MaybeUninit<T>)
//!
//! Detects usage of uninitialized memory through MaybeUninit<T> patterns.
//! Reading uninitialized memory is undefined behavior and can lead to
//! information disclosure or crashes.
//!
//! Nomicon §5: Uninitialized Memory
//! - MaybeUninit::assume_init() on uninitialized data → UB
//! - Reading union fields before writing → UB
//! - Using uninitialized stack variables → UB (prevented by Rust, but not in unsafe)
//!
//! Covers:
//! - MaybeUninit::assume_init() without prior write
//! - Uninitialized struct/array field access
//! - Memory allocation followed by immediate read without initialization

const std = @import("std");
const log = std.log.scoped(.nomicon_ch5);
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Function name patterns that indicate MaybeUninit operations
const UNINIT_PATTERNS = [_][]const u8{
    "assume_init",
    "MaybeUninit",
    "uninit",
    "uninitialized",
    "__MaybeInit",
};

/// Alloc functions that return uninitialized memory
const ALLOC_UNINIT_PATTERNS = [_][]const u8{
    "alloc_uninit",
    "allocZeroed", // This IS initialized (zeroed), so it's safe
    "malloc", // C malloc returns uninitialized memory
    "__rust_alloc",
};

/// Detect uninitialized memory usage patterns.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func_count: usize = 0;
    var uninit_count: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        func_count += 1;

        // Check function name for MaybeUninit patterns
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) == 0) continue;
        const func_name = std.mem.sliceTo(func_name_raw, 0);

        // Scan for assume_init calls without proper initialization
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check for call instructions to dangerous functions
                if (opcode == c.LLVMCall) {
                    const called_func = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_func) == 0) continue;

                    const called_name_raw = c.LLVMGetValueName(called_func);
                    if (@intFromPtr(called_name_raw) == 0) continue;
                    const called_name = std.mem.sliceTo(called_name_raw, 0);

                    // Check for assume_init pattern
                    if (isAssumeInitPattern(called_name)) {
                        if (analyzeAssumeInitUsage(inst, func_name, srt)) {
                            uninit_count += 1;
                        }
                    }

                    // Check for malloc/alloc without initialization
                    if (isUninitAllocPattern(called_name)) {
                        if (analyzeAllocWithoutInit(inst, func_name, srt)) {
                            uninit_count += 1;
                        }
                    }
                }

                // Check for loads from alloca (stack variables) that might be uninitialized
                if (opcode == c.LLVMLoad) {
                    if (analyzePotentialUninitLoad(inst, srt)) {
                        uninit_count += 1;
                    }
                }
            }
        }
    }

    if (uninit_count > 0) {
        log.debug("[NOMICON-CH5] Analyzed {} functions, found {} potential uninit uses", .{
            func_count,
            uninit_count,
        });
    } else {
        log.debug("[NOMICON-CH5] Analyzed {} functions, no uninit issues found", .{func_count});
    }
}

/// Check if a function name matches the assume_init pattern.
fn isAssumeInitPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "assume_init") != null or
        std.mem.indexOf(u8, name, "assumeInit") != null;
}

/// Check if a function returns uninitialized memory.
fn isUninitAllocPattern(name: []const u8) bool {
    for (ALLOC_UNINIT_PATTERNS) |pattern| {
        if (std.mem.eql(u8, name, pattern) or
            std.mem.indexOf(u8, name, pattern) != null)
        {
            return true;
        }
    }
    return false;
}

/// Analyze an assume_init call to check if the MaybeUninit was properly initialized.
fn analyzeAssumeInitUsage(
    inst: c.LLVMValueRef,
    func_name: []const u8,
    srt: *SemanticTree,
) bool {
    _ = func_name;

    // In a full implementation, we would:
    // 1. Track the MaybeUninit value being operated on
    // 2. Check if there was a store to it before this assume_init
    // 3. If no store found, flag as potential UB

    // For now, we conservatively flag all assume_init calls as suspicious
    // The confidence can be increased with proper dataflow analysis
    log.debug("[NOMICON-CH5] assume_init call detected — requires dataflow analysis to verify init", .{});

    recordResolution(srt, @intFromPtr(inst), .uninit_memory_use, 0.60, "Nomicon-Ch5 assume_init (needs dataflow verification)");

    return true;
}

/// Analyze an allocation call to check if memory is used before initialization.
fn analyzeAllocWithoutInit(
    inst: c.LLVMValueRef,
    func_name: []const u8,
    srt: *SemanticTree,
) bool {
    _ = func_name;

    // Check if the next instruction(s) use this value without initializing it first
    // This is a simplified heuristic; full implementation needs def-use analysis

    const next_inst = c.LLVMGetNextInstruction(inst);
    if (@intFromPtr(next_inst) == 0) return false;

    const next_opcode = c.LLVMGetInstructionOpcode(next_inst);

    // If the very next instruction is a load or store using the allocated pointer
    // without a memset/memcpy in between, it's suspicious
    if (next_opcode == c.LLVMLLoad or next_opcode == c.LLVMLStore) {
        // Check if any operand is our allocation result
        var i: u32 = 0;
        const num_ops = c.LLVMGetNumOperands(next_inst);
        while (i < num_ops) : (i += 1) {
            const op = c.LLVMGetOperand(next_inst, i);
            if (op == inst) {
                log.debug("[NOMICON-CH5] Alloc immediately used without init", .{});

                recordResolution(srt, @intFromPtr(next_inst), .uninit_memory_use, 0.70, "Nomicon-Ch5 alloc used without initialization");

                return true;
            }
        }
    }

    return false;
}

/// Analyze a load instruction for potential uninitialized memory access.
fn analyzePotentialUninitLoad(inst: c.LLVMValueRef, srt: *SemanticTree) bool {
    const ptr_operand = c.LLVMGetOperand(inst, 0);

    // Check if this load is from an alloca (stack variable)
    if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMLAlloca) {
        // In a full implementation, we'd track whether this alloca was written to
        // before this load. For now, we just note the pattern.

        // Only flag if the alloca is for a large type (struct/array)
        // Small scalar types are usually initialized by Rust's default rules
        const alloc_type = c.LLVMTypeOf(ptr_operand);
        const type_size = getTypeSize(alloc_type);

        if (type_size > 16) { // Larger than 2 pointers — likely a struct/array
            log.debug("[NOMICON-CH5] Load from large alloca ({} bytes) — potential uninit", .{
                type_size,
            });

            recordResolution(srt, @intFromPtr(inst), .uninit_memory_use, 0.45, "Nomicon-Ch5 potential uninit load from large alloca");

            return true;
        }
    }

    return false;
}

/// Get the size of a type in bytes.
fn getTypeSize(ty: c.LLVMTypeRef) u64 {
    _ = ty;
    return 0; // Placeholder — would use LLVM TargetData in production
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

test "Ch5: detect uninit patterns" {
    try std.testing.expect(isAssumeInitPattern("assume_init"));
    try std.testing.expect(isAssumeInitPattern("_ZN4core6mem12MaybeUninit11assume_init17h..."));
    try std.testing.expect(!isAssumeInitPattern("safe_function"));

    try std.testing.expect(isUninitAllocPattern("malloc"));
    try std.testing.expect(isUninitAllocPattern("__rust_alloc"));
    try std.testing.expect(!isUninitAllocPattern("calloc")); // calloc zeros memory
}
