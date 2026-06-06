//! Free Validation — Pointer Origin Tracking
//!
//! Extracted from free_validation.zig: trackPointerOrigin() state machine
//! and PointerInfo struct. Tracks how pointers flow through a function
//! to determine their origin (malloc, param, global, FFI call, etc.).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const mangling = @import("../../../ir/mangling.zig");
const ValueOrigin = @import("../ffi/ffi_semantics.zig").ValueOrigin;
const library_alloc_pairs = @import("../../../semantics/patterns/library_alloc_pairs.zig");
const safety = @import("free_validation_safety.zig");

const PassContext = @import("../../pass.zig").PassContext;

/// Information about a pointer's origin
pub const PointerInfo = struct {
    /// Origin of the pointer
    origin: ValueOrigin,
    /// Source instruction (if from allocation)
    source_inst: ?c.LLVMValueRef,
    /// Description for trace
    source_desc: []const u8,
    /// The exact allocation function name (e.g., "malloc", "_Znwm", "__rust_alloc").
    /// Populated at detection time to avoid fragile downstream string parsing.
    /// null if the pointer is not from a known allocation function.
    alloc_func_name: ?[]const u8 = null,
};

/// Check if a function is a known library-specific allocator from FFIContractDB.
/// Used by trackPointerOrigin to identify library allocators (e.g., SSL_new,
/// sqlite3_open, BIO_new) so their release functions can be validated later.
pub fn isContractDbAllocFunc(ctx: *PassContext, func_name: []const u8) bool {
    return ctx.contract_db.isKnownAllocator(func_name);
}

/// Track the origin of pointers through a function.
/// Iterates over all instructions and records pointer origins in the map.
pub fn trackPointerOrigin(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    pointer_origins: *std.AutoHashMap(c.LLVMValueRef, PointerInfo),
) !void {
    const allocator = ctx.allocator;
    const opcode = c.LLVMGetInstructionOpcode(inst);

    switch (opcode) {
        // Allocation calls - mark as from_malloc
        c.LLVMCall, c.LLVMInvoke => {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) != 0) {
                const func_name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(func_name_ptr) != 0) {
                    const func_name = std.mem.span(func_name_ptr);

                    if (safety.isAllocFunction(func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_malloc,
                            .source_inst = inst,
                            .source_desc = desc,
                            .alloc_func_name = func_name,
                        };
                    } else if (library_alloc_pairs.lookupTable(func_name)) |entry| {
                        if (entry.effect == .borrow) {
                            const desc = try std.fmt.allocPrint(
                                allocator,
                                "from borrowed library func {s}() [DO NOT FREE]",
                                .{func_name},
                            );
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_library_borrow,
                                .source_inst = inst,
                                .source_desc = desc,
                            };
                        } else if (entry.effect == .acquire) {
                            const desc = try std.fmt.allocPrint(
                                allocator,
                                "from library alloc {s}()",
                                .{func_name},
                            );
                            const gop = try pointer_origins.getOrPut(inst);
                            if (gop.found_existing) {
                                allocator.free(gop.value_ptr.source_desc);
                            }
                            gop.value_ptr.* = .{
                                .origin = .from_malloc,
                                .source_inst = inst,
                                .source_desc = desc,
                                .alloc_func_name = func_name,
                            };
                        }
                    } else if (safety.isFFIBoundaryCall(func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from FFI call {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_ffi_call,
                            .source_inst = inst,
                            .source_desc = desc,
                            .alloc_func_name = func_name,
                        };
                    } else if (mangling.isRustAllocCall(func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_malloc,
                            .source_inst = inst,
                            .source_desc = desc,
                            .alloc_func_name = func_name,
                        };
                    } else if (safety.isCppNewCall(func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_malloc,
                            .source_inst = inst,
                            .source_desc = desc,
                            .alloc_func_name = func_name,
                        };
                    } else if (isContractDbAllocFunc(ctx, func_name)) {
                        const desc = try std.fmt.allocPrint(allocator, "from {s}()", .{func_name});
                        const gop = try pointer_origins.getOrPut(inst);
                        if (gop.found_existing) {
                            allocator.free(gop.value_ptr.source_desc);
                        }
                        gop.value_ptr.* = .{
                            .origin = .from_ffi_call,
                            .source_inst = inst,
                            .source_desc = desc,
                            .alloc_func_name = func_name,
                        };
                    }
                }
            }
        },

        // Load/Store - propagate origin (copy source_desc)
        c.LLVMLoad => {
            const ptr = c.LLVMGetOperand(inst, 0);
            if (pointer_origins.get(ptr)) |info| {
                const desc = try allocator.dupe(u8, info.source_desc);
                const gop = try pointer_origins.getOrPut(inst);
                if (gop.found_existing) {
                    allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = .{
                    .origin = info.origin,
                    .source_inst = info.source_inst,
                    .source_desc = desc,
                    .alloc_func_name = info.alloc_func_name,
                };
            }
        },

        // GEP - propagate origin (copy source_desc)
        c.LLVMGetElementPtr => {
            const ptr = c.LLVMGetOperand(inst, 0);
            if (pointer_origins.get(ptr)) |info| {
                const desc = try allocator.dupe(u8, info.source_desc);
                const gop = try pointer_origins.getOrPut(inst);
                if (gop.found_existing) {
                    allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = .{
                    .origin = info.origin,
                    .source_inst = info.source_inst,
                    .source_desc = desc,
                    .alloc_func_name = info.alloc_func_name,
                };
            }
        },

        // BitCast - propagate origin (copy source_desc)
        c.LLVMBitCast => {
            const ptr = c.LLVMGetOperand(inst, 0);
            if (pointer_origins.get(ptr)) |info| {
                const desc = try allocator.dupe(u8, info.source_desc);
                const gop = try pointer_origins.getOrPut(inst);
                if (gop.found_existing) {
                    allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = .{
                    .origin = info.origin,
                    .source_inst = info.source_inst,
                    .source_desc = desc,
                    .alloc_func_name = info.alloc_func_name,
                };
            }
        },

        // PHI node - merge origins from all incoming values
        c.LLVMPHI => {
            const num_incoming = c.LLVMCountIncoming(inst);
            var best_origin: ?PointerInfo = null;
            var best_priority: i32 = -1;
            var i: c_uint = 0;
            while (i < num_incoming) : (i += 1) {
                const incoming_val = c.LLVMGetIncomingValue(inst, i);
                if (pointer_origins.get(incoming_val)) |info| {
                    const priority: i32 = switch (info.origin) {
                        .from_malloc => 5,
                        .from_ffi_call => 4,
                        .from_library_borrow => 6,
                        .from_param => 3,
                        .from_global => 2,
                        .from_constant => 1,
                        .unknown => 0,
                    };
                    if (priority > best_priority) {
                        if (best_origin) |prev| allocator.free(prev.source_desc);
                        const desc = try allocator.dupe(u8, info.source_desc);
                        best_origin = .{
                            .origin = info.origin,
                            .source_inst = info.source_inst,
                            .source_desc = desc,
                            .alloc_func_name = info.alloc_func_name,
                        };
                        best_priority = priority;
                    }
                }
            }
            if (best_origin) |origin| {
                const gop = try pointer_origins.getOrPut(inst);
                if (gop.found_existing) {
                    allocator.free(gop.value_ptr.source_desc);
                }
                gop.value_ptr.* = origin;
            }
        },

        else => {},
    }
}
