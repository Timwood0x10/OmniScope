//! Return Value Check Pass
//!
//! Detects unchecked return values from dangerous functions

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

/// Return value check pass
pub const ReturnCheckPass = struct {
    pub const name = "return-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Functions whose return values need to be checked
    const DangerousFunctions = &[_][]const u8{
        "malloc", "open", "read", "write", "system", "exec", "popen",
    };

    /// Functions whose return values don't need to be checked (safe to ignore)
    /// These functions either return void or have no meaningful error information
    const SafeReturnFunctions = &[_][]const u8{
        "free", // void return, no error checking needed
        "close", // return value rarely needs checking in practice
        "fflush", // void return
        "fclose", // return value rarely needs checking
    };

    /// Internal/library helper functions whose return values are often intentionally unchecked
    /// These are common in C libraries like sqlite3, pthread, etc.
    const InternalHelperFunctions = &[_][]const u8{
        // pthread internal functions - return values often ignored in library code
        "pthread_mutex_",
        "pthread_mutexattr_",
        // sqlite3 internal helpers
        "readCoord",
        "writeInt16",
        "nodeGetCell",
        "nodeOverwriteCell",
        "pager_write_",
        "vdbeSorter",
        "vdbeIncr",
        "selectWindow",
        "propagateConstant",
        // General utility patterns (suffixes/prefixes that indicate internal use)
        "Coord",
        "MergerSet",
    };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const noise_filter = @import("../../../semantics/noise_filter.zig");

        var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
        if (@intFromPtr(func) == 0) return;

        var issue_count: usize = 0;
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            // Skip safe zone / runtime internal functions
            const func_name_raw = c.LLVMGetValueName(func);
            const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "";
            if (func_name.len > 0) {
                const classification = noise_filter.classifyFunctionFull(func_name, null, null, null);
                if (!classification.origin.shouldReportByDefault()) continue;
            }

            // Function-level error isolation
            const count = analyzeFunction(ctx, func, diag) catch |err| {
                const err_name = if (func_name.len > 0) func_name else "unknown";
                diag.warn("ReturnCheck: skipped function due to error: {} ({s})", .{ err, err_name });
                ctx.recordDegradedFunction();
                continue;
            };
            issue_count += count;
        }

        diag.info("ReturnCheck: Analyzed functions, found {} unchecked return values", .{issue_count});
    }

    fn analyzeFunction(ctx: *PassContext, func: c.LLVMValueRef, diag: *DiagnosticWriter) !usize {
        var issue_count: usize = 0;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (@intFromPtr(c.LLVMIsACallInst(inst)) != 0) {
                    if (try checkCallForUncheck(ctx, inst, func, diag)) {
                        issue_count += 1;
                    }
                }
            }
        }
        return issue_count;
    }

    fn checkCallForUncheck(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        caller_func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) !bool {
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        const called_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(called_name_ptr) == 0) return false;
        const called_name = std.mem.span(called_name_ptr);

        // Remove leading \x01_ prefix if present (LLVM uses \x01 for private/extern linkage flags)
        const clean_name = if (called_name.len >= 4 and called_name[0] == '\x01' and called_name[1] == '_')
            called_name[2..]
        else
            called_name;

        if (!isDangerousFunction(clean_name)) {
            return false;
        }

        // Check if return value is used by manually counting uses
        var num_uses: usize = 0;
        var use = c.LLVMGetFirstUse(inst);
        while (@intFromPtr(use) != 0) : (use = c.LLVMGetNextUse(use)) {
            num_uses += 1;
        }

        if (num_uses > 0) {
            return false; // Return value is used
        }

        // Get caller function name
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        // Calculate confidence based on function type
        const confidence = calculateReturnCheckConfidence(clean_name);

        // Calculate severity based on confidence
        const severity: Severity = blk: {
            if (confidence >= 0.8) break :blk .high;
            if (confidence >= 0.6) break :blk .medium;
            break :blk .low;
        };

        // Create issue
        const location = Location.init(caller_name);
        const issue_message = try std.fmt.allocPrint(
            ctx.allocator,
            "Unchecked return value from dangerous function '{s}' (confidence: {d:.2}%)",
            .{ clean_name, confidence * 100.0 },
        );

        const issue = Issue.init(
            .unchecked_return,
            issue_message,
            location,
            severity,
            confidence,
        );

        try ctx.addIssue(&issue);
        ctx.allocator.free(issue_message);

        diag.warn("Unchecked return value: {s} -> {s}", .{ caller_name, clean_name });
        return true;
    }

    pub fn isDangerousFunction(func_name: []const u8) bool {
        // First check if it's a safe function (return value doesn't need checking)
        for (SafeReturnFunctions) |safe_func| {
            if (std.mem.eql(u8, func_name, safe_func)) {
                return false; // It's safe, not dangerous
            }
        }

        // Check if it's an internal helper function (library-internal, often unchecked)
        for (InternalHelperFunctions) |helper| {
            if (std.mem.indexOf(u8, func_name, helper) != null) {
                return false; // Internal helper, skip
            }
        }

        // Then check if it's a dangerous function (exact match preferred, then prefix)
        for (DangerousFunctions) |dangerous_func| {
            // Prefer exact match to avoid false positives like readCoord matching "read"
            if (std.mem.eql(u8, func_name, dangerous_func)) {
                return true;
            }
        }

        // Only do substring match for well-known prefixes that are unlikely to be internal
        const safe_prefixes = &[_][]const u8{ "malloc", "calloc", "realloc", "open", "read", "write" };
        for (safe_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) {
                // But exclude known internal variants
                const known_safe = &[_][]const u8{
                    "mallocWithAlarm",  "malloc_size",        "malloc_usable_size",
                    "malloc_zone_free", "malloc_zone_malloc", "malloc_set_zone_name",
                    "readCoord",        "readData",           "openStatTable",
                    "openDatabase",
                };
                var is_known_safe = false;
                for (known_safe) |safe| {
                    if (std.mem.eql(u8, func_name, safe)) {
                        is_known_safe = true;
                        break;
                    }
                }
                if (!is_known_safe) return true;
            }
        }

        return false;
    }

    /// Calculate confidence for return value check
    ///
    /// Factors:
    /// - Function type (system calls = higher confidence)
    /// - Function specificity
    ///
    /// Parameters:
    ///   - func_name: Name of the function
    ///
    /// Returns:
    ///   - Confidence score (0.0 - 1.0)
    fn calculateReturnCheckConfidence(func_name: []const u8) f32 {
        var confidence: f32 = 0.6; // Base confidence

        // Critical functions that always need return value checking
        const critical_functions = &[_][]const u8{
            "malloc", "system", "exec", "popen", "open", "read", "write",
        };

        for (critical_functions) |critical| {
            if (std.mem.eql(u8, func_name, critical)) {
                confidence += 0.3; // Exact match to critical function = +30%
                break;
            } else if (std.mem.indexOf(u8, func_name, critical) != null) {
                confidence += 0.15; // Partial match = +15%
            }
        }

        // Cap at 1.0
        if (confidence > 1.0) {
            confidence = 1.0;
        }

        return confidence;
    }
};

test "ReturnCheckPass - dangerous function detection" {
    try std.testing.expect(ReturnCheckPass.isDangerousFunction("malloc"));
    try std.testing.expect(ReturnCheckPass.isDangerousFunction("system"));
    try std.testing.expect(!ReturnCheckPass.isDangerousFunction("safe_func"));
}
