//! Malloc Null Check Detection Pass
//!
//! Detects when malloc/calloc/realloc return values are used without
//! proper null checking. This is a critical memory safety issue.
//!
//! Design principle: Only based on IR facts, no guessing.
//! - Detect malloc/calloc/realloc calls
//! - Track where the result is used
//! - Check if null check exists before use

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const IssueCandidate = @import("../resource/issue_candidate_builder.zig").IssueCandidate;

// Delegate allocation function detection to the unified function catalog
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");

/// Malloc null check detection pass
///
/// This pass implements Rule 1 from go_noise.md:
/// Detect when malloc result is used without null check.
pub const MallocCheckPass = struct {
    pub const name = "malloc-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        // DEBUG: Count functions and list them
        {
            var f_count: usize = 0;
            var f_item = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(f_item) != 0) : (f_item = c.LLVMGetNextFunction(f_item)) {
                const fnp = c.LLVMGetValueName(f_item);
                const func_name = if (@intFromPtr(fnp) != 0) std.mem.span(fnp) else "?";
                const is_decl = c.LLVMIsDeclaration(f_item);
                std.debug.print("MALLOC_CHECK_MOD: {s} decl={d}\n", .{ func_name, @intFromBool(is_decl != 0) });
                f_count += 1;
            }
            std.debug.print("MALLOC_CHECK_MOD: total={d}\n", .{f_count});
        }

        var issue_count: usize = 0;
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            //Function-level error isolation
            const count = analyzeFunction(ctx, func, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("MallocCheck: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += count;
        }

        diag.info("MallocCheck: Analyzed functions, found {} unchecked allocations", .{issue_count});
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;

        // DEBUG: Print function being analyzed
        {
            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0) std.mem.span(func_name_ptr) else "unknown";
            const has_body = c.LLVMCountBasicBlocks(func);
            std.debug.print("MALLOC_CHECK_FUNC: {s} bbs={d}\n", .{ func_name, has_body });
        }

        // Track allocation results and their null check status
        var alloc_results = std.AutoHashMap(c.LLVMValueRef, AllocInfo).init(ctx.allocator);
        defer alloc_results.deinit();

        // First pass: find all allocation calls and null checks
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try recordAllocAndChecks(inst, &alloc_results);
            }
        }

        // Second pass: find uses without null check
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (try checkUncheckedUse(ctx, inst, &alloc_results, func, diag)) {
                    issue_count += 1;
                }
            }
        }

        return issue_count;
    }

    /// Information about an allocation result
    const AllocInfo = struct {
        /// The allocation call instruction
        alloc_inst: c.LLVMValueRef,
        /// Function name for reporting
        func_name: []const u8,
        /// Whether null check was found
        has_null_check: bool,
    };

    /// Record allocation calls and null checks
    fn recordAllocAndChecks(
        inst: c.LLVMValueRef,
        alloc_results: *std.AutoHashMap(c.LLVMValueRef, AllocInfo),
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Check for allocation call
        if (llvm_safe.isCallOrInvoke(opcode)) {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) != 0) {
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) != 0) {
                    const func_name = std.mem.span(name_ptr);
                    // DEBUG
                    const is_alloc = isAllocFunction(func_name);
                    std.debug.print("MALLOC_CHECK_DEBUG: func_name={s} isAlloc={}\n", .{ func_name, is_alloc });
                    if (is_alloc) {
                        // Record this allocation result
                        try alloc_results.put(inst, .{
                            .alloc_inst = inst,
                            .func_name = func_name,
                            .has_null_check = false,
                        });
                    }
                }
            }
        }

        // Check for null comparison (icmp eq/ne ptr, null)
        if (opcode == c.LLVMICmp) {
            const predicate = c.LLVMGetICmpPredicate(inst);
            // ICmpEq = 32, ICmpNe = 33
            if (predicate == 32 or predicate == 33) {
                const op1 = c.LLVMGetOperand(inst, 0);
                const op2 = c.LLVMGetOperand(inst, 1);

                // Check if comparing with null
                if (c.LLVMIsNull(op2) != 0) {
                    // Mark the allocation as checked
                    // The operand might be the allocation result or a copy
                    if (alloc_results.getPtr(op1)) |info| {
                        info.has_null_check = true;
                    }
                }
                if (c.LLVMIsNull(op1) != 0) {
                    if (alloc_results.getPtr(op2)) |info| {
                        info.has_null_check = true;
                    }
                }
            }
        }
    }

    /// Check if an instruction uses an unchecked allocation result
    fn checkUncheckedUse(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        alloc_results: *const std.AutoHashMap(c.LLVMValueRef, AllocInfo),
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Skip the allocation call itself, null checks, and ret instructions.
        // Reason: ret instruction = factory pattern (return malloc result to caller).
        // Caller is responsible for null checking, not this function.
        // Example: XXH32_createState() { return XXH_malloc(sizeof(...)); }
        // Reporting this as HIGH creates massive FPs on C API factory functions.
        if (llvm_safe.isCallOrInvoke(opcode) or opcode == c.LLVMICmp or opcode == c.LLVMRet) {
            return false;
        }

        // DEBUG: Print instruction details
        {
            const oc_name = switch (opcode) {
                c.LLVMStore => "Store",
                c.LLVMLoad => "Load",
                c.LLVMCall => "Call",
                c.LLVMRet => "Ret",
                c.LLVMGetElementPtr => "GEP",
                c.LLVMBitCast => "BitCast",
                else => "Other",
            };
            const num_ops = c.LLVMGetNumOperands(inst);
            std.debug.print("MALLOC_CHECK_USE: opcode={s} num_ops={d}\n", .{ oc_name, num_ops });
        }

        // Check all operands for unchecked allocation results
        const num_ops = c.LLVMGetNumOperands(inst);
        var i: u32 = 0;
        while (i < num_ops) : (i += 1) {
            const operand = c.LLVMGetOperand(inst, i);
            // DEBUG: Check if operand matches any allocation
            const in_alloc = alloc_results.contains(operand);
            if (in_alloc) {
                std.debug.print("MALLOC_CHECK_MATCH: operand[{d}] matches an allocation!\n", .{i});
            }

            if (alloc_results.get(operand)) |info| {
                if (!info.has_null_check) {
                    // Found unchecked use!
                    try reportUncheckedUse(ctx, caller_func, info.func_name, inst, diag);
                    return true;
                }
            }
        }

        return false;
    }

    /// Check if function is a memory allocation function
    fn isAllocFunction(func_name: []const u8) bool {
        return ptr_types.isHeapAllocFunction(func_name);
    }

    /// Report unchecked malloc use
    fn reportUncheckedUse(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        alloc_func_name: []const u8,
        use_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // Build trace for reasoning path
        const trace = try ctx.allocator.alloc(TraceEntry, 3);
        trace[0] = TraceEntry.init("Allocation function called without null check");
        trace[1] = try createAllocTraceEntry(ctx.allocator, alloc_func_name);
        trace[2] = try createUseTraceEntry(ctx.allocator, use_inst);

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}() result used without null check (confidence: {d:.2}%)",
            .{ alloc_func_name, 0.85 * 100.0 },
        );

        const severity: Severity = .high;
        const confidence: f32 = 0.85;

        // P20: Structured candidate for malloc unchecked
        var cand = IssueCandidate.init(ctx.allocator, .leak, confidence);
        cand.func_name = caller_name;
        cand.alloc_ptr = @as(u64, @intFromPtr(use_inst));
        cand.inst_addr = @as(u64, @intFromPtr(use_inst));
        cand.is_on_ffi_path = true;
        cand.addEvidence("malloc() result used without null check") catch {};
        cand.addEvidenceFmt("Function: {s}", .{caller_name}) catch {};

        var issue = Issue.initWithTrace(
            .malloc_unchecked,
            cand.reason orelse message,
            location,
            severity,
            cand.raw_score,
            trace,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);
        defer cand.deinit();

        diag.warn("Unchecked {s} result in function: {s}", .{ alloc_func_name, caller_name });
    }

    /// Create trace entry for allocation
    fn createAllocTraceEntry(allocator: std.mem.Allocator, func_name: []const u8) !TraceEntry {
        const desc = try std.fmt.allocPrint(
            allocator,
            "Allocation via {s}() returns nullable pointer",
            .{func_name},
        );
        return TraceEntry.initOwned(desc);
    }

    /// Create trace entry for use
    fn createUseTraceEntry(allocator: std.mem.Allocator, inst: c.LLVMValueRef) !TraceEntry {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const opcode_name = getOpcodeName(opcode);

        const desc = try std.fmt.allocPrint(
            allocator,
            "Pointer used in {s} instruction without prior null check",
            .{opcode_name},
        );
        return TraceEntry.initOwned(desc);
    }

    /// Get human-readable opcode name
    fn getOpcodeName(opcode: c.LLVMOpcode) []const u8 {
        return switch (opcode) {
            c.LLVMStore => "store",
            c.LLVMLoad => "load",
            c.LLVMGetElementPtr => "gep",
            c.LLVMCall => "call",
            c.LLVMBitCast => "bitcast",
            c.LLVMPtrToInt => "ptrtoint",
            else => "unknown",
        };
    }
};

test "MallocCheckPass - name and kind" {
    try std.testing.expectEqualStrings("malloc-check", MallocCheckPass.name);
    try std.testing.expectEqual(PassKind.analysis, MallocCheckPass.kind);
}

test "MallocCheckPass - isAllocFunction" {
    try std.testing.expect(MallocCheckPass.isAllocFunction("malloc"));
    try std.testing.expect(MallocCheckPass.isAllocFunction("calloc"));
    try std.testing.expect(MallocCheckPass.isAllocFunction("realloc"));
    try std.testing.expect(!MallocCheckPass.isAllocFunction("printf"));
    try std.testing.expect(!MallocCheckPass.isAllocFunction("free"));
}
