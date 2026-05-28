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
    pub const deps: []const []const u8 = &[_][]const u8{};

    /// Helper: Get safe UTF-8 function name from LLVM value
    /// Prevents garbled characters in terminal output when function names contain non-UTF-8
    fn getSafeFuncName(func: c.LLVMValueRef) []const u8 {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) return "unknown";

        const func_name_raw = std.mem.span(name_ptr);

        // Validate UTF-8 to prevent terminal display issues
        if (std.unicode.utf8ValidateSlice(func_name_raw)) {
            return func_name_raw;
        }

        // Return safe fallback for non-UTF-8 names (e.g., mangled C++ names)
        return "function_with_non_utf8_name";
    }

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

                    // Check __memcpy_chk / __memmove_chk for size > destination buffer.
                    // Pattern: __memcpy_chk(dest, src, size, limit) where size > limit = overflow.
                    if (opcode == c.LLVMCall) {
                        if (checkMemcpyChkOverflow(ctx, func, inst, diag)) |vuln| {
                            overflow_count += 1;
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

        // Get data layout to compute type size - validate each step
        const inst_parent = c.LLVMGetInstructionParent(base_ptr);
        if (@intFromPtr(inst_parent) == 0) return null;

        const base_func = c.LLVMGetBasicBlockParent(inst_parent);
        if (@intFromPtr(base_func) == 0) return null;

        const module = c.LLVMGetGlobalParent(base_func);
        if (@intFromPtr(module) == 0) return null;

        const dl = c.LLVMGetModuleDataLayout(module);
        if (@intFromPtr(dl) == 0) return null;

        const type_size = c.LLVMABISizeOfType(dl, alloc_type);
        if (type_size == 0) return null;

        // Calculate maximum number of elements that can be accessed
        // For safety, we skip element size calculation which can cause segfaults
        // and instead just use the total type size as a conservative estimate
        const max_elements = type_size; // Conservative: assume element size = 1 byte

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
            const func_name_str = getSafeFuncName(func);

            diag.warn("STACK-OVERFLOW [HIGH]: GEP index {d} exceeds element count {d} in {s}", .{
                last_index_value, max_elements,
                func_name_str,
            });

            const msg = std.fmt.allocPrint(ctx.allocator, "Stack buffer overflow: element index {d} exceeds allocation of {d} elements", .{ last_index_value, max_elements }) catch null;
            // E2-1d: MemoryGraph gate - only report stack overflows if the base pointer
            // (alloca result) flows into an FFI call (is on danger path).
            const base_ptr_val = @as(u64, @intFromPtr(base_ptr));
            if (!ctx.isRelevantAlloc(base_ptr_val)) {
                diag.debug("[STACK-OVERFLOW SUPPRESSED] Base pointer not on FFI danger path in {s}", .{func_name_str});
                if (msg) |m| {
                    ctx.allocator.free(m); // R8-M11 FIX: Free heap-allocated message on early return
                }
                return null;
            }
            // R8-M11 FIX: Set owned=true for heap-allocated message to prevent memory leak
            const final_msg = msg orelse "Stack buffer overflow detected";
            var issue = Issue.init(.buffer_overflow, final_msg, Location.init(func_name_str), .high, 0.85);
            issue.owned = msg != null;
            return issue;
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
        // R8-L2 FIX: array_size is unsigned (c_uint), so <= 0 is equivalent to == 0
        // Changed to == 0 to remove dead < 0 branch and clarify intent
        if (array_size == 0) return null;

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
            const func_name_str = getSafeFuncName(func);

            diag.warn("ARRAY-OOB [HIGH]: Array index {d} exceeds array size {d}", .{
                last_index_value, array_size,
            });

            const msg = std.fmt.allocPrint(ctx.allocator, "Array out-of-bounds: index {d} exceeds array length {d}", .{ last_index_value, array_size }) catch null;
            // E2-1d: MemoryGraph gate - only report array OOB if the base pointer
            // flows into an FFI call (is on danger path).
            const base_ptr_val = @as(u64, @intFromPtr(base_ptr));
            if (!ctx.isRelevantAlloc(base_ptr_val)) {
                diag.debug("[ARRAY-OOB SUPPRESSED] Base pointer not on FFI danger path in {s}", .{func_name_str});
                if (msg) |m| {
                    ctx.allocator.free(m); // R8-M11 FIX: Free heap-allocated message on early return
                }
                return null;
            }
            // R8-M11 FIX: Set owned=true for heap-allocated message
            const final_msg = msg orelse "Array out-of-bounds detected";
            var issue = Issue.init(.buffer_overflow, final_msg, Location.init(func_name_str), .high, 0.8);
            issue.owned = msg != null;
            return issue;
        }

        return null;
    }

    /// Check if a __memcpy_chk / __memmove_chk call has size > limit (buffer overflow).
    /// These functions take (dest, src, size, limit) where limit is the dest buffer size.
    /// If size > limit, it's a definite overflow (the chk variant would abort at runtime).
    fn checkMemcpyChkOverflow(ctx: *PassContext, func: c.LLVMValueRef, inst: c.LLVMValueRef, diag: *DiagnosticWriter) ?Issue {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return null;
        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return null;
        const callee_name = std.mem.span(name_ptr);

        // Only check __memcpy_chk and __memmove_chk variants
        const is_memcpy_chk = std.mem.indexOf(u8, callee_name, "__memcpy_chk") != null;
        const is_memmove_chk = std.mem.indexOf(u8, callee_name, "__memmove_chk") != null;
        if (!is_memcpy_chk and !is_memmove_chk) return null;

        // __memcpy_chk(dest, src, size, limit) has 4 args + callee = 5 operands
        // R8-H5 FIX: Changed from < 4 to < 5 to correctly check for all required operands
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops < 5) return null;

        // Operand 0 = dest, 1 = src, 2 = size, 3 = limit (dest buffer size), 4 = callee
        const size_val = c.LLVMGetOperand(inst, 2);
        const limit_val = c.LLVMGetOperand(inst, 3);
        if (@intFromPtr(size_val) == 0 or @intFromPtr(limit_val) == 0) return null;

        // Both must be constant integers for us to compare
        if (c.LLVMIsConstant(size_val) == 0 or c.LLVMIsAConstantInt(size_val) == null) return null;
        if (c.LLVMIsConstant(limit_val) == 0 or c.LLVMIsAConstantInt(limit_val) == null) return null;

        // LLVMConstIntGetZExtValue returns c_ulonglong (unsigned long long).
        // Use explicit @as() cast instead of @bitCast for type safety and portability:
        // c_ulonglong may differ from u64 on some platforms (e.g., LLP64 vs LP64).
        const size: u64 = @as(u64, c.LLVMConstIntGetZExtValue(size_val));
        const limit: u64 = @as(u64, c.LLVMConstIntGetZExtValue(limit_val));

        if (size <= limit) return null; // Safe: size fits within buffer

        // OVERFLOW: writing more bytes than destination can hold
        const func_name = getSafeFuncName(func);

        diag.warn("MEMCPY-CHK [HIGH]: {s} writes {d} bytes to {d}-byte buffer in {s}", .{
            callee_name, size, limit, func_name,
        });

        const msg = std.fmt.allocPrint(
            ctx.allocator,
            "{s} buffer overflow: copying {d} bytes exceeds destination buffer of {d} bytes",
            .{ callee_name, size, limit },
        ) catch {
            // Fallback to static message if allocation fails
            return Issue.init(.buffer_overflow, "memcpy_chk buffer overflow detected", Location.init(func_name), .high, 0.9);
        };
        var issue = Issue.init(.buffer_overflow, msg, Location.init(func_name), .high, 0.9);
        issue.owned = true; // msg is heap-allocated, will be freed on deinit
        return issue;
    }

    /// Helper function to register a detected issue with the context.
    fn reportIssue(ctx: *PassContext, issue: Issue, diag: *DiagnosticWriter) !void {
        try ctx.addIssue(&issue);

        // Fix: Ensure UTF-8 safe output to prevent garbled characters in terminal
        const safe_message = sanitizeUtf8String(issue.message);
        diag.err("[BUFFER-OVERFLOW] {s}: {s}", .{ @tagName(issue.kind), safe_message });
        // Note: DataFlowGraph.addIssue takes ownership and will free original memory
    }

    /// Sanitize string for safe UTF-8 output
    /// Replaces invalid UTF-8 sequences with '?' to prevent terminal display issues
    fn sanitizeUtf8String(input: []const u8) []const u8 {
        // Quick check: if string is valid UTF-8, return as-is
        if (std.unicode.utf8ValidateSlice(input)) {
            return input;
        }

        // For invalid UTF-8, return a safe fallback message
        // (In production, you might want to allocate and clean the string)
        return "buffer overflow detected (details contain non-UTF-8 characters)";
    }
};
