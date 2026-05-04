//! Buffer Overflow Detection Pass
//!
//! Detects stack buffer overflows and array out-of-bounds accesses
//! using LLVM IR analysis (GEP + alloca size checking).
//!
//! This pass identifies two types of vulnerabilities:
//! 1. Stack buffer overflow: when GEP index exceeds alloca allocation size
//! 2. Array out-of-bounds: when GEP index exceeds static array length

const std = @import("std");

const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;

/// Buffer overflow detection pass.
/// Analyzes GEP (GetElementPtr) instructions against alloca sizes
/// and static array bounds to detect potential overflows.
pub const BufferOverflowPass = struct {
    pub const name = "buffer-overflow";
    pub const kind = .analysis;

    /// Run buffer overflow detection on the loaded module.
    /// This is an AUXILIARY pass (not core FFI/unsafe detection).
    /// For performance, it skips modules with >500 functions (large codebases).
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;

        // Performance guard: skip large modules (auxiliary feature, not core FFI)
        var func_count: u32 = 0;
        var count_func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(count_func) != 0) : (count_func = c.LLVMGetNextFunction(count_func)) {
            if (c.LLVMIsDeclaration(count_func) != 0) continue;
            func_count += 1;
        }
        if (func_count > 500) {
            diag.info("BufferOverflow: Skipped (module has {d} functions, >500 threshold)", .{func_count});
            return;
        }

        var overflow_count: u32 = 0;
        var oob_count: u32 = 0;

        // Iterate through all functions in the module
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // Check each basic block for dangerous memory accesses
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    // Check load/store operations for stack buffer overflow
                    if (opcode == c.LLVMLoad or opcode == c.LLVMStore) {
                        const ptr_operand = c.LLVMGetOperand(inst, if (opcode == c.LLVMLoad) 0 else 1);
                        if (@intFromPtr(ptr_operand) == 0) continue;

                        // If pointer comes from GEP, check bounds
                        if (c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr) {
                            if (checkStackBounds(ctx, func, ptr_operand, diag)) |vuln| {
                                overflow_count += 1;
                                try reportIssue(ctx, vuln, diag);
                            }
                        }
                    }

                    // Also check raw GEP instructions for array OOB
                    if (opcode == c.LLVMGetElementPtr) {
                        if (checkArrayBounds(ctx, func, inst, diag)) |vuln| {
                            oob_count += 1;
                            try reportIssue(ctx, vuln, diag);
                        }
                    }
                }
            }
        }

        // Report summary statistics
        if (overflow_count > 0) {
            diag.info("BufferOverflow: Found {d} potential stack buffer overflows", .{overflow_count});
        }
        if (oob_count > 0) {
            diag.info("BufferOverflow: Found {d} potential array out-of-bounds accesses", .{oob_count});
        }
        if (overflow_count == 0 and oob_count == 0) {
            diag.info("BufferOverflow: No buffer overflow issues detected", .{});
        }
    }

    /// Check if a GEP instruction accessing an alloca result exceeds bounds.
    /// Returns an issue if the last index is a constant exceeding allocation size.
    fn checkStackBounds(ctx: *PassContext, func: c.LLVMValueRef, gep: c.LLVMValueRef, diag: *DiagnosticWriter) ?Issue {
        const base_ptr = c.LLVMGetOperand(gep, 0);
        if (@intFromPtr(base_ptr) == 0) return null;

        // Only check alloca-based pointers (stack allocations)
        if (c.LLVMGetInstructionOpcode(base_ptr) != c.LLVMAlloca) return null;

        const alloc_type = c.LLVMGetAllocatedType(base_ptr);
        if (@intFromPtr(alloc_type) == 0) return null;

        // Get data layout to compute type size
        const base_func = c.LLVMGetBasicBlockParent(c.LLVMGetInstructionParent(base_ptr));
        const module = c.LLVMGetGlobalParent(base_func);
        const dl = c.LLVMGetModuleDataLayout(module);
        const type_size = c.LLVMABISizeOfType(dl, alloc_type);
        if (type_size <= 0) return null;

        // Get element size to calculate max element count
        const elem_type = c.LLVMGetElementType(alloc_type);
        if (@intFromPtr(elem_type) == 0) return null;
        const elem_size = c.LLVMABISizeOfType(dl, elem_type);
        if (elem_size <= 0) return null;

        // Calculate maximum number of elements that can be accessed
        const max_elements = type_size / elem_size;

        // Get number of GEP operands (indices)
        const num_operands = c.LLVMGetNumOperands(gep);
        if (num_operands < 2) return null; // Need at least base + 1 index

        // Extract and validate the last index (the element offset)
        var last_index_value: i64 = 0;
        var last_index_is_const = false;

        var i: c_uint = 1;
        while (i < num_operands) : (i += 1) {
            const index_val = c.LLVMGetOperand(gep, i);
            if (c.LLVMIsConstant(index_val) != 0 and c.LLVMIsAConstantInt(index_val) != null) {
                if (i == num_operands - 1) {
                    // Last index determines element offset
                    last_index_value = c.LLVMConstIntGetSExtValue(index_val);
                    last_index_is_const = true;
                }
            }
        }

        // Only flag constant indices that exceed allocation size
        if (!last_index_is_const) return null;

        if (last_index_value >= @as(i64, @intCast(max_elements))) {
            const func_name = c.LLVMGetValueName(func);
            const func_name_str = if (@intFromPtr(func_name) != 0)
                std.mem.span(func_name)
            else
                "unknown";

            diag.warn("STACK-OVERFLOW [HIGH]: GEP index {d} exceeds element count {d} in {s}", .{
                last_index_value, max_elements,
                func_name_str,
            });

            const msg = std.fmt.allocPrint(ctx.allocator, "Stack buffer overflow: element index {d} exceeds allocation of {d} elements", .{ last_index_value, max_elements }) catch "Stack buffer overflow detected";
            // E2-1d: MemoryGraph gate - only report stack overflows if the base pointer
            // (alloca result) flows into an FFI call (is on danger path).
            const base_ptr_val = @as(u64, @intFromPtr(base_ptr));
            if (!ctx.isRelevantAlloc(base_ptr_val)) {
                diag.debug("[STACK-OVERFLOW SUPPRESSED] Base pointer not on FFI danger path in {s}", .{func_name_str});
                return null;
            }
            return Issue.init(.buffer_overflow, msg, Location.init(func_name_str), .high, 0.85);
        }

        return null;
    }

    /// Check if a GEP instruction on a global/static array exceeds bounds.
    /// Returns an issue if index exceeds declared array length.
    fn checkArrayBounds(ctx: *PassContext, func: c.LLVMValueRef, gep: c.LLVMValueRef, diag: *DiagnosticWriter) ?Issue {
        const base_ptr = c.LLVMGetOperand(gep, 0);
        if (@intFromPtr(base_ptr) == 0) return null;

        // Get the base pointer's type to check if it's an array
        const base_type = c.LLVMTypeOf(base_ptr);
        if (@intFromPtr(base_type) == 0) return null;

        // Get the element type (what the pointer points to)
        const pointed_type = c.LLVMGetElementType(base_type);
        if (@intFromPtr(pointed_type) == 0) return null;

        // Check if the pointed-to type is an array
        const is_array = c.LLVMGetTypeKind(pointed_type) == c.LLVMArrayTypeKind;
        if (!is_array) return null;

        const array_size = c.LLVMGetArrayLength(pointed_type);
        if (array_size <= 0) return null;

        // Validate indices similar to stack bounds check
        const num_operands = c.LLVMGetNumOperands(gep);
        if (num_operands < 2) return null;

        var last_index_value: i64 = 0;
        var has_const_index = false;

        var i: c_uint = 1;
        while (i < num_operands) : (i += 1) {
            const index_val = c.LLVMGetOperand(gep, i);
            if (c.LLVMIsConstant(index_val) != 0 and c.LLVMIsAConstantInt(index_val) != null) {
                if (i == num_operands - 1) {
                    last_index_value = c.LLVMConstIntGetSExtValue(index_val);
                    has_const_index = true;
                }
            }
        }

        if (!has_const_index) return null;

        if (last_index_value >= @as(i64, @intCast(array_size))) {
            const func_name = c.LLVMGetValueName(func);
            const func_name_str = if (@intFromPtr(func_name) != 0)
                std.mem.span(func_name)
            else
                "unknown";

            diag.warn("ARRAY-OOB [HIGH]: Array index {d} exceeds array size {d}", .{
                last_index_value, array_size,
            });

            const msg = std.fmt.allocPrint(ctx.allocator, "Array out-of-bounds: index {d} exceeds array length {d}", .{ last_index_value, array_size }) catch "Array out-of-bounds detected";
            // E2-1d: MemoryGraph gate - only report array OOB if the base pointer
            // flows into an FFI call (is on danger path).
            const base_ptr_val = @as(u64, @intFromPtr(base_ptr));
            if (!ctx.isRelevantAlloc(base_ptr_val)) {
                diag.debug("[ARRAY-OOB SUPPRESSED] Base pointer not on FFI danger path in {s}", .{func_name_str});
                return null;
            }
            return Issue.init(.buffer_overflow, msg, Location.init(func_name_str), .high, 0.8);
        }

        return null;
    }

    /// Helper function to register a detected issue with the context.
    fn reportIssue(ctx: *PassContext, issue: Issue, diag: *DiagnosticWriter) !void {
        try ctx.addIssue(&issue);
        diag.err("[BUFFER-OVERFLOW] {s}: {s}", .{ @tagName(issue.kind), issue.message });
    }
};
