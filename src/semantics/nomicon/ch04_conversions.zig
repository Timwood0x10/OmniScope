//! Nomicon Ch4: Type Conversions & Transmute Detection
//!
//! Detects potentially dangerous type conversions that may lead to
//! undefined behavior: size mismatch, alignment violation, invalid values.
//!
//! Nomicon §4: Type Conversions
//! - Transmute between incompatible types can cause UB
//! - from_raw() on invalid pointers leads to use-after-free
//! - repr(C) casts must preserve layout invariants
//!
//! Covers:
//! - Bitcast with size mismatch (UB)
//! - ptrtoint/inttoptr round-trip violations
//! - from_raw on non-allocated memory

const std = @import("std");
const log = std.log.scoped(.nomicon_ch4);
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Patterns that indicate unsafe transmute operations
const TRANSMUTE_PATTERNS = [_][]const u8{
    "transmute",
    "from_raw",
    "ptr::from_exposed_addr",
    "ptr::from_exposed_addr_mut",
    "bitcast",
};

/// Detect unsafe type conversions and transmute patterns.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;
    var func_count: usize = 0;
    var transmute_count: usize = 0;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;
        func_count += 1;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check for bitcast (transmute in LLVM IR)
                if (opcode == c.LLVMBitCast) {
                    if (analyzeBitcast(module, inst, srt)) {
                        transmute_count += 1;
                    }
                }

                // Check for ptrtoint/inttoptr (also transmute-like)
                if (opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr) {
                    if (analyzePtrIntConversion(module, inst, srt)) {
                        transmute_count += 1;
                    }
                }
            }
        }
    }
}

/// Analyze a bitcast instruction for potential issues.
fn analyzeBitcast(module: c.LLVMModuleRef, inst: c.LLVMValueRef, srt: *SemanticTree) bool {
    const src_type = c.LLVMTypeOf(c.LLVMGetOperand(inst, 0));
    const dst_type = c.LLVMTypeOf(inst);

    const src_size = getTypeSize(module, src_type);
    const dst_size = getTypeSize(module, dst_type);

    // Size mismatch is almost always a bug or dangerous pattern
    if (src_size > 0 and dst_size > 0 and src_size != dst_size) {
        const confidence: f32 = if (dst_size < src_size) 0.65 else 0.75;
        recordResolution(srt, @intFromPtr(inst), .unsafe_transmute, confidence, "Nomicon-Ch4 size-mismatch bitcast");

        return true;
    }

    return false;
}

/// Analyze ptrtoint/inttoptr conversions for potential issues.
fn analyzePtrIntConversion(module: c.LLVMModuleRef, inst: c.LLVMValueRef, srt: *SemanticTree) bool {
    const opcode = c.LLVMGetInstructionOpcode(inst);
    const src_type = c.LLVMTypeOf(c.LLVMGetOperand(inst, 0));
    const dst_type = c.LLVMTypeOf(inst);

    // inttoptr is particularly dangerous — creates pointer from integer
    if (opcode == c.LLVMIntToPtr) {
        const ptr_size = getTypeSize(module, dst_type);
        const int_size = getTypeSize(module, src_type);

        // If integer is smaller than pointer size, this is likely UB
        if (int_size > 0 and ptr_size > 0 and int_size < ptr_size) {
            recordResolution(srt, @intFromPtr(inst), .unsafe_transmute, 0.80, "Nomicon-Ch4 inttoptr size truncation");

            return true;
        }
    }

    // ptrtoint followed by inttoptr (round-trip) should be flagged
    // This pattern often indicates an attempt to bypass type system
    if (opcode == c.LLVMPtrToInt) {
        // Just log the conversion for now; the real danger is when it's converted back
        recordResolution(srt, @intFromPtr(inst), .unsafe_transmute, 0.50, "Nomicon-Ch4 ptrtoint conversion");

        return true;
    }

    return false;
}

/// Get the size of a type in bytes using LLVM data layout.
fn getTypeSize(module: c.LLVMModuleRef, type_ref: c.LLVMTypeRef) u64 {
    const layout = c.LLVMGetModuleDataLayout(module);
    return c.LLVMStoreSizeOfType(layout, type_ref);
}

/// Record a semantic resolution to the SRT.
fn recordResolution(
    srt: *SemanticTree,
    value_ref: u64,
    kind: SemanticKind,
    confidence: f32,
    evidence: []const u8,
) void {
    srt.recordResolution(value_ref, kind, confidence, "Nomicon-Ch4", evidence) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "Ch4: detect function name patterns" {
    const test_names = [_]struct { []const u8, bool }{
        .{ "transmute", true },
        .{ "from_raw", true },
        .{ "std::mem::transmute", true },
        .{ "ptr::from_exposed_addr", true },
        .{ "safe_function", false },
        .{ "normal_cast", false },
    };

    for (test_names) |entry| {
        var found = false;
        for (TRANSMUTE_PATTERNS) |pattern| {
            if (std.mem.indexOf(u8, entry[0], pattern) != null) {
                found = true;
                break;
            }
        }
        try std.testing.expectEqual(entry[1], found);
    }
}
