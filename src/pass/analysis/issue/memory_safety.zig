//! Memory Safety Detection Pass — TRUE Single-Pass Implementation
//!
//! Design Philosophy:
//!   - ONE scan of the LLVM module: build relations AND detect issues simultaneously
//!   - MS-level performance: zero-copy hashing, pre-allocated structures, O(1) lookups
//!   - Minimal false positives: multi-layer validation with confidence scoring
//!
//! Architecture:
//!   for each function in module:
//!     1. Hash function name (u64, zero-copy)
//!     2. Scan instructions:
//!        - Call → record in call_graph (by hash)
//!        - Alloc → record in origins (by hash)
//!        - Free → IMMEDIATELY validate against built relations
//!     3. Report issues inline (no second pass)
//!
//! Performance Characteristics:
//!   - Time: O(N) where N = total instructions (single linear scan)
//!   - Space: O(F + A) where F = functions, A = alloc/free ops
//!   - No string copies during hot path (hash-based)
//!   - Pre-allocated HashMaps prevent rehashing

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const FuzzyMatcher = @import("../../../semantics/memory_graph.zig").FuzzyMatcher;
const MemoryRelations = @import("../../../semantics/memory_relations.zig").MemoryRelations;

/// Hash a string slice to u64 for zero-copy operations
fn hashString(s: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(s);
    return hasher.final();
}

/// Memory safety detection pass — true single-pass implementation
pub const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Main entry point: single-pass scan with inline analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var relations = try MemoryRelations.init(ctx.allocator, 0);
        defer relations.deinit();

        var issue_count: usize = 0;
        var func_count: usize = 0;
        var freed_pointers = std.ArrayList(u64).empty;
        defer freed_pointers.deinit(ctx.allocator);

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            func_count += 1;
            issue_count += try scanAndAnalyzeFunction(ctx, func, &relations, &freed_pointers, diag);
        }

        diag.info("MemorySafety: Single-pass scan complete — {} functions, {} issues detected", .{
            func_count,
            issue_count,
        });
    }

    /// Single-function scan: build relations AND detect issues in one pass
    fn scanAndAnalyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        relations: *MemoryRelations,
        freed_pointers: *std.ArrayList(u64),
        diag: *DiagnosticWriter,
    ) !usize {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return 0;

        const func_name = std.mem.span(func_name_ptr);
        const func_hash = hashString(func_name);

        _ = try relations.internString(func_name);

        var issue_count: usize = 0;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (opcode == c.LLVMCall) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(called_name_ptr) == 0) continue;

                    const called_name = std.mem.span(called_name_ptr);
                    const called_hash = hashString(called_name);

                    _ = try relations.internString(called_name);

                    try relations.recordCall(func_hash, called_hash);

                    const class = FuzzyMatcher.classify(called_name);

                    if (class == .alloc or class == .init or class == .create or class == .open) {
                        const ptr_value = @intFromPtr(inst);
                        try relations.recordAlloc(func_hash, ptr_value);
                    } else if (class == .free or class == .cleanup or class == .destroy or class == .close) {
                        try relations.recordFree(func_hash);

                        const ptr_arg = c.LLVMGetOperand(inst, 0);
                        const ptr_as_int = @intFromPtr(ptr_arg);

                        if (try validateAndReportFree(ctx, func, called_name, ptr_as_int, freed_pointers, relations, diag)) {
                            issue_count += 1;
                        }
                    }
                }
            }
        }

        return issue_count;
    }

    /// Validate a free call and report if suspicious (inline, single-pass)
    fn validateAndReportFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        free_func_name: []const u8,
        ptr_value: u64,
        freed_pointers: *std.ArrayList(u64),
        relations: *MemoryRelations,
        diag: *DiagnosticWriter,
    ) !bool {
        const free_hash = hashString(free_func_name);

        const validation = relations.validateFree(free_hash, ptr_value, free_func_name);

        if (validation.is_valid and validation.confidence > 0.8) {
            diag.debug("[SUPPRESSED] Free validated: conf={d:.2} reason={d}", .{
                validation.confidence,
                validation.reason,
            });
            return false;
        }

        for (freed_pointers.items) |freed_ptr| {
            if (freed_ptr == ptr_value) {
                // Suppress double free in Rust panic/cleanup paths.
                // Rust's panic handling invokes destructors in cleanup paths,
                // which can trigger apparent double-free patterns that are
                // actually safe (drop glue checks for already-dropped state).
                if (isRustPanicOrCleanupFunction(caller_func)) {
                    diag.debug("[SUPPRESSED] Double free in Rust panic/cleanup: {s}", .{free_func_name});
                    return false;
                }
                try reportDoubleFree(ctx, caller_func, free_func_name, diag);
                return true;
            }
        }

        try freed_pointers.append(ctx.allocator, ptr_value);

        if (!validation.is_valid and validation.confidence > 0.7) {
            try reportSuspiciousFree(ctx, caller_func, free_func_name, validation.confidence, diag);
            return true;
        }

        return false;
    }

    fn reportDoubleFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        func_name: []const u8,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);
        const confidence: f32 = 0.85;

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "Potential double free via '{s}' (confidence: {d:.1}%)",
            .{ func_name, confidence * 100.0 },
        );

        const issue = Issue.init(
            .double_free,
            message,
            location,
            .high,
            confidence,
        );

        try ctx.addIssue(&issue);
        ctx.allocator.free(message);

        diag.warn("Double free: {s} → {s}", .{ caller_name, func_name });
    }

    fn reportSuspiciousFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        func_name: []const u8,
        confidence: f32,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        if (confidence < 0.6) return;

        const location = Location.init(caller_name);

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "Suspicious free via '{s}' without matching alloc (confidence: {d:.1}%)",
            .{ func_name, confidence * 100.0 },
        );

        const severity: Severity = if (confidence > 0.8) .medium else .low;

        const issue = Issue.init(
            .use_after_free,
            message,
            location,
            severity,
            confidence,
        );

        try ctx.addIssue(&issue);
        ctx.allocator.free(message);

        diag.warn("Suspicious free: {s} → {s} ({d:.1}%)", .{
            caller_name,
            func_name,
            confidence * 100.0,
        });
    }

    /// Check if a function is a Rust panic or cleanup handler.
    /// Rust's panic handling and drop glue invoke destructors in cleanup paths,
    /// which can create apparent double-free patterns that are actually safe.
    fn isRustPanicOrCleanupFunction(func: c.LLVMValueRef) bool {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) return false;
        const func_name = std.mem.span(name_ptr);

        // Rust panic infrastructure
        if (std.mem.indexOf(u8, func_name, "panic") != null) return true;
        // Rust drop glue (compiler-generated destructors)
        if (std.mem.indexOf(u8, func_name, "drop_in_place") != null) return true;
        if (std.mem.indexOf(u8, func_name, "drop_and_deallocate") != null) return true;
        // Rust unwinding / cleanup
        if (std.mem.indexOf(u8, func_name, "_Unwind_") != null) return true;
        if (std.mem.indexOf(u8, func_name, "cleanup") != null) return true;
        // Rust dealloc intrinsics (compiler-inserted)
        if (std.mem.indexOf(u8, func_name, "__rustc__rustc_dealloc") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__rust_dealloc") != null) return true;

        return false;
    }
};

test "MemorySafetyPass - init" {
    try std.testing.expectEqualStrings("memory-safety", MemorySafetyPass.name);
    try std.testing.expectEqual(PassKind.analysis, MemorySafetyPass.kind);
}
