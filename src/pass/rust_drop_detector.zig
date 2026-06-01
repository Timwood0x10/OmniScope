//! Basic Rust Drop Trait Detector
//!
//! Identifies drop_in_place calls to mark allocations as RAII-managed.
//! This is a foundational component for Phase 2 ownership-aware analysis.
//!
//! ## Purpose
//! When Rust values leave scope, the compiler automatically inserts calls to
//! `drop_in_place<T>` (the "drop glue"). This module detects these implicit
//! destructor calls and registers them with MemoryGraph so that leak detection
//! passes can suppress false positives for RAII-managed allocations.
//!
//! ## Integration
//! This detector should be called after pointer_ownership pass has populated
//! MemoryGraph with allocation nodes. It scans LLVM IR for drop_in_place
//! patterns and calls trackRustDrop() on matching allocations.
//!
//! ## Future Enhancements
//! - Full LLVM IR traversal (currently placeholder)
//! - Cross-function drop glue tracking
//! - Drop scope modeling (when does drop run?)
//! - Interaction with into_raw/from_raw patterns

const std = @import("std");
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;
const MemoryGraph = @import("../semantics/memory_graph.zig").MemoryGraph;

/// Basic Rust Drop Trait Detector
///
/// Scans LLVM IR for drop_in_place calls and registers them with MemoryGraph.
/// This enables downstream leak detectors to suppress false positives for
/// allocations that are cleaned up by Rust's automatic Drop trait.
pub const RustDropDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RustDropDetector {
        return .{ .allocator = allocator };
    }

    /// Detect drop calls in a function and register them with MemoryGraph.
    ///
    /// This method scans all instructions in a function looking for:
    ///   - `drop_in_place<T>` calls (compiler-generated destructors)
    ///   - `__rust_dealloc` calls that are part of drop chains
    ///   - User-defined `Drop::drop` implementations
    ///
    /// Arguments:
    ///   func_opaque - Opaque pointer to the LLVM function value
    ///   graph_opaque - Opaque pointer to the MemoryGraph instance
    ///
    /// Returns:
    ///   Number of drop sites detected and registered
    pub fn detectDropsInFunction(
        self: *RustDropDetector,
        func_opaque: ?*anyopaque,
        graph_opaque: ?*anyopaque,
    ) !usize {
        _ = self;

        // Type-safe casting of opaque pointers
        const func = @as(?*c.LLVMValue, @ptrCast(@alignCast(func_opaque))) orelse return 0;
        const graph = @as(*MemoryGraph, @ptrCast(@alignCast(graph_opaque)));

        var drop_count: usize = 0;

        // Scan all basic blocks in the function
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check if this instruction is a call/invoke
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                // Get the called function's name
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;

                const name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(name_ptr) == 0) continue;

                const func_name = std.mem.span(name_ptr);

                // Check for drop_in_place patterns using rust_drop_semantics module
                const rust_drop = @import("../semantics/rust_drop_semantics.zig");
                if (rust_drop.isDropGlue(func_name)) {
                    // Found a drop_in_place call!
                    // Try to get the operand being dropped (first argument)
                    const num_operands = c.LLVMGetNumOperands(inst);
                    if (num_operands >= 1) {
                        const dropped_operand = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(dropped_operand) != 0) {
                            const operand_addr = @as(u64, @intFromPtr(dropped_operand));
                            const inst_addr = @as(u64, @intFromPtr(inst));

                            // Register this as RAII cleanup in MemoryGraph
                            graph.trackRustDrop(operand_addr, inst_addr) catch |err| {
                                log.warn("RUST-DROP: Failed to track drop at 0x{x}: {}", .{
                                    inst_addr, err,
                                });
                                continue;
                            };

                            drop_count += 1;

                            log.debug("RUST-DROP: Found {} at inst 0x{x} (operand 0x{x})", .{
                                func_name, inst_addr, operand_addr,
                            });
                        }
                    }
                }
            }
        }

        if (drop_count > 0) {
            log.info("RUST-DROP: Detected {} drop sites in function", .{drop_count});
        }

        return drop_count;
    }

    /// Detect drops across ALL functions in a module.
    ///
    /// Convenience wrapper that iterates over all functions in a module
    /// and runs detectDropsInFunction() on each one.
    ///
    /// Arguments:
    ///   mod_opaque - Opaque pointer to the LLVM module
    ///   graph_opaque - Opaque pointer to the MemoryGraph instance
    ///
    /// Returns:
    ///   Total number of drop sites detected across all functions
    pub fn detectDropsInModule(
        self: *RustDropDetector,
        mod_opaque: ?*anyopaque,
        graph_opaque: ?*anyopaque,
    ) !usize {
        const mod_val = @as(?*c.LLVMModule, @ptrCast(@alignCast(mod_opaque))) orelse return 0;

        var total_drops: usize = 0;
        var func = c.LLVMGetFirstFunction(mod_val);

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            // Skip declarations (no body)
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const drops = try self.detectDropsInFunction(
                @as(?*anyopaque, @ptrCast(func)),
                graph_opaque,
            );
            total_drops += drops;
        }

        return total_drops;
    }
};

// ════════════════════════════════════════════════════
// Unit Tests
// ════════════════════════════════════════════════════

const testing = std.testing;

test "RustDropDetector - basic initialization" {
    const detector = RustDropDetector.init(testing.allocator);
    // Just verify it can be created without errors
    _ = detector;
}

test "RustDropDetector - detectDropsInFunction with null inputs" {
    var detector = RustDropDetector.init(testing.allocator);

    // Should return 0 for null function (graceful handling)
    const count = detector.detectDropsInFunction(null, null) catch |err| {
        // Should not error on null input
        testing.expect(false) catch {};
        return err;
    };

    try testing.expectEqual(@as(usize, 0), count);
}

test "RustDropDetector - detectDropsInModule with null module" {
    var detector = RustDropDetector.init(testing.allocator);

    // Should return 0 for null module (graceful handling)
    const count = detector.detectDropsInModule(null, null) catch |err| {
        testing.expect(false) catch {};
        return err;
    };

    try testing.expectEqual(@as(usize, 0), count);
}
