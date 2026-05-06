//! Rust FFI Auditor - Independent Module for Rust↔C FFI Analysis
//!
//! This module provides dedicated analysis for Rust FFI boundary safety,
//! including ownership transfer pairing, borrow escape detection, and
//! cross-language allocation mismatch identification.
//!
//! Market positioning: The only static analysis tool focused on Rust FFI.
//!
//! Target scenarios:
//!   - sqlite bindings (rusqlite)
//!   - openssl bindings (rust-openssl)
//!   - tokio native deps
//!   - tauri plugins
//!   - napi-rs (Node.js)
//!   - pyo3 (Python)

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const CommonTypes = @import("../../common/types.zig");
const ptr_types = @import("ptr_lifetime_types.zig");

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Confidence = @import("../../diag/issue.zig").Confidence;
const Severity = @import("../../diag/issue.zig").Severity;
const Location = @import("../../diag/issue.zig").Location;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

/// Rust FFI issue types specific to this auditor
pub const RustFfiIssueType = enum {
    /// Box::into_raw without matching from_raw
    unpaired_into_raw,
    /// CString::into_raw without matching from_raw
    unpaired_cstring_into_raw,
    /// as_ptr result passed to FFI, may dangle after drop
    as_ptr_borrow_escape,
    /// Rust _Znwm allocation freed by C free()
    cross_lang_alloc_mismatch,
    /// Unsafe FFI call without proper validation
    unsafe_ffi_call,
    /// extern "C" function with potential type mismatch
    extern_c_type_mismatch,
    /// Stack address (alloca/local) escapes to FFI boundary
    stack_address_escape,
};

/// Rust FFI audit result for a single function
pub const RustFfiFinding = struct {
    func_name: []const u8,
    issue_type: RustFfiIssueType,
    severity: CommonTypes.Severity,
    confidence: f32,
    reason: []const u8,
    location: Location,
};

const FreeEntry = struct { val: c.LLVMValueRef, free_name: []const u8 };

/// Main Rust FFI Auditor struct
pub const RustFfiAuditor = struct {
    pub const name = "rust-ffi-filter";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    allocator: std.mem.Allocator,
    findings: std.ArrayList(RustFfiFinding),
    stats: AuditStats,

    pub const AuditStats = struct {
        total_functions_analyzed: usize = 0,
        into_raw_funcs: usize = 0,
        from_raw_funcs: usize = 0,
        as_ptr_escapes: usize = 0,
        cross_lang_mismatches: usize = 0,
        unsafe_ffi_calls: usize = 0,
        stack_escapes: usize = 0,
        unpaired_into_raw: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!RustFfiAuditor {
        return .{
            .allocator = allocator,
            .findings = try std.ArrayList(RustFfiFinding).initCapacity(allocator, 16),
            .stats = .{},
        };
    }

    pub fn deinit(self: *RustFfiAuditor) void {
        for (self.findings.items) |finding| {
            // func_name and reason are allocator-owned slices from allocPrint/Location.init
            self.allocator.free(finding.func_name);
            self.allocator.free(finding.reason);
        }
        self.findings.deinit(self.allocator);
    }

    /// Run full audit on an LLVM module (Pass interface)
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        const mod = ctx.module.?.raw;

        var auditor = try RustFfiAuditor.init(ctx.allocator);
        defer auditor.deinit();

        // audit() returns toOwnedSlice — must free it to avoid leak
        const findings = try auditor.audit(mod, ctx, diag);
        ctx.allocator.free(findings);

        diag.info("RustFfiFilter: analyzed {d} funcs, {d} findings ({d} stack escapes)", .{ auditor.stats.total_functions_analyzed, auditor.findings.items.len, auditor.stats.stack_escapes });
    }

    /// Run full audit on an LLVM module
    pub fn audit(self: *RustFfiAuditor, module: c.LLVMModuleRef, ctx: *PassContext, diag: *DiagnosticWriter) ![]const RustFfiFinding {
        self.findings.clearRetainingCapacity();
        self.stats = .{};

        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;
            self.stats.total_functions_analyzed += 1;

            try self.auditFunction(func, ctx, diag);
        }

        return try self.findings.toOwnedSlice(self.allocator);
    }

    /// Audit a single function for all Rust FFI patterns.
    /// Language gate: Rust-specific rules (1/2/3/6/7) only fire on Rust modules
    /// to prevent false positives on C/C++/Zig code (Rule 3 was producing 8 FP on C).
    fn auditFunction(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const func_name = getFunctionName(func);
        const is_rust = ctx.isRustModule();

        // ── Rust-specific rules (language-gated) ──
        // These detect Rust ownership/borrow patterns that don't apply to C/Zig

        if (is_rust) {
            // Rule 1: into_raw/from_raw pairing check
            if (ctx.rust_into_raw_set.contains(@intFromPtr(c.LLVMGetValueName(func)))) {
                if (ctx.rust_from_raw_set.count() == 0) {
                    try self.addFinding(.{
                        .func_name = func_name,
                        .issue_type = .unpaired_into_raw,
                        .severity = .high,
                        .confidence = 0.75,
                        .reason = "into_raw() called but no matching from_raw() in module",
                        .location = Location.init(func_name),
                    });
                    self.stats.into_raw_funcs += 1;
                }
            }

            // Rule 2: as_ptr borrow escape detection
            try self.detectAsPtrEscape(func, ctx, diag);

            // Rule 3: Cross-lang alloc mismatch (Rust _Znwm → C free)
            try self.detectCrossLangMismatch(func, ctx, diag);

            // Rule 6: Ownership transfer protocol (into_raw/from_raw pairing)
            try self.detectOwnershipTransferViolations(func, ctx, diag);

            // Rule 7: as_ptr dangling detection — borrowed ptr used after parent drop
            try self.detectAsPtrDangling(func, ctx, diag);
        }

        // ── Universal FFI boundary rules (run on ALL languages) ──
        // These detect real FFI/unsafe boundary issues regardless of source language

        // Rule 4: Unsafe block FFI call scan
        try self.detectUnsafeFfiCalls(func);

        // Rule 5: Stack address escape to FFI boundary (alloca/local → extern "C")
        try self.detectStackEscapeToFFI(func, ctx, diag);
    }

    /// Detect as_ptr borrow escape in function body
    fn detectAsPtrEscape(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (!isRustAsPtrCall(name_slice)) continue;

                self.stats.as_ptr_escapes += 1;
                const func_name = getFunctionName(func);

                try self.addFinding(.{
                    .func_name = func_name,
                    .issue_type = .as_ptr_borrow_escape,
                    .severity = .high,
                    .confidence = 0.80,
                    .reason = "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                    .location = Location.init(func_name),
                });

                const vuln_id = ctx.getNextVulnId();
                ctx.addIssue(&Issue.initWithReason(
                    .borrow_escape,
                    "Potential as_ptr borrow escape: local Rust value pointer passed to FFI",
                    Location.init(func_name),
                    .high,
                    0.8,
                    "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                )) catch |err| {
                    diag.warn("Failed to register borrow_escape issue: {any}", .{err});
                };
                diag.err("VULNERABILITY OMI-{d:0>3} [high] [Confidence: medium]", .{vuln_id});
                diag.err("Type: borrow_escape", .{});
                diag.err("Reason: as_ptr() on local value passed to FFI - may dangle", .{});
            }
        }
    }

    /// Detect cross-language allocation mismatch (Rust _Znwm → C free)
    fn detectCrossLangMismatch(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (!isCFreeCall(name_slice)) continue;

                const func_name = getFunctionName(func);
                self.stats.cross_lang_mismatches += 1;

                try self.addFinding(.{
                    .func_name = func_name,
                    .issue_type = .cross_lang_alloc_mismatch,
                    .severity = .high,
                    .confidence = 0.85,
                    .reason = "C free() may be freeing Rust-allocated memory (_Znwm)",
                    .location = Location.init(func_name),
                });

                const vuln_id = ctx.getNextVulnId();
                ctx.addIssue(&Issue.initWithReason(
                    .cross_language_leak,
                    "Cross-language alloc mismatch: Rust-alloc freed by C free()",
                    Location.init(func_name),
                    .high,
                    0.85,
                    "Rust _Znwm allocation freed by C free() - heap mismatch",
                )) catch |err| {
                    diag.warn("Failed to register cross_language_leak issue: {any}", .{err});
                };
                diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [high] [Confidence: high]", .{vuln_id});
                diag.err("Type: cross_language_alloc_mismatch", .{});
                diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
            }
        }
    }

    /// Detect unsafe FFI calls without validation
    fn detectUnsafeFfiCalls(self: *RustFfiAuditor, func: c.LLVMValueRef) !void {
        var has_unsafe_ffi = false;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands < 2) continue;

                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (isExternCCall(name_slice)) {
                    has_unsafe_ffi = true;
                }
            }
            if (has_unsafe_ffi) break;
        }

        if (has_unsafe_ffi) {
            self.stats.unsafe_ffi_calls += 1;
            const func_name = getFunctionName(func);

            try self.addFinding(.{
                .func_name = func_name,
                .issue_type = .unsafe_ffi_call,
                .severity = .medium,
                .confidence = 0.60,
                .reason = "Function contains extern \"C\" calls requiring manual review",
                .location = Location.init(func_name),
            });
        }
    }

    /// Detect stack address escape: alloca/local variable address passed to FFI boundary.
    /// This is a Rust-specific danger pattern where &local or local array is passed
    /// to an extern "C" function that may store the pointer beyond the caller's scope.
    fn detectStackEscapeToFFI(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;

                const callee_name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(callee_name_ptr) == 0) continue;
                const callee_name = std.mem.span(callee_name_ptr);

                // Must be FFI boundary (non-Rust-mangled)
                if (isRustMangledName(callee_name)) continue;
                if (std.mem.startsWith(u8, callee_name, "llvm.")) continue;

                // Skip pure consumption functions (memcpy, printf, etc.)
                if (isPureConsumptionFunction(callee_name)) continue;

                // Check each argument for alloca-derived pointers
                const num_args = c.LLVMGetNumArgOperands(inst);
                var arg_i: u32 = 0;
                while (arg_i < num_args) : (arg_i += 1) {
                    const arg = c.LLVMGetOperand(inst, arg_i);
                    if (@intFromPtr(arg) == 0) continue;

                    // Only check pointer-type arguments
                    const arg_type = c.LLVMTypeOf(arg);
                    if (@intFromPtr(arg_type) == 0) continue;
                    if (c.LLVMGetTypeKind(arg_type) != c.LLVMPointerTypeKind) continue;

                    if (isDerivedFromAlloca(arg)) {
                        // Confirm callee may retain the pointer
                        if (mayRetainPointer(callee_name)) {
                            self.stats.stack_escapes += 1;
                            const func_name = getFunctionName(func);

                            try self.addFinding(.{
                                .func_name = func_name,
                                .issue_type = .stack_address_escape,
                                .severity = .high,
                                .confidence = 0.80,
                                .reason = "Stack address (alloca/local) escapes to FFI function that may retain pointer",
                                .location = Location.init(func_name),
                            });

                            const trace = try self.allocator.alloc(TraceEntry, 3);
                            trace[0] = TraceEntry.init("Stack address escapes across FFI boundary");
                            trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
                                self.allocator,
                                "Argument {d} of {s} derived from alloca instruction",
                                .{ arg_i, callee_name },
                            ));
                            trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(
                                self.allocator,
                                "Callee may store pointer beyond caller's lifetime",
                                .{},
                            ));

                            const issue = Issue.initWithTrace(
                                .borrow_escape,
                                try std.fmt.allocPrint(
                                    self.allocator,
                                    "Stack address escapes to FFI: {s}() receives alloca-derived pointer",
                                    .{callee_name},
                                ),
                                Location.init(func_name),
                                .high,
                                0.80,
                                trace,
                            );
                            var mutable_issue = issue;
                            mutable_issue.owned = true;
                            try ctx.addIssue(&mutable_issue);

                            diag.warn("RustFfiFilter: stack escape in {s} → {s}() arg {d}", .{ func_name, callee_name, arg_i });
                        }
                    }
                }
            }
        }
    }

    /// Rule 6: Ownership Transfer Protocol — detect ownership violations.
    ///
    /// Core insight: Instead of trying to find into_raw (which Rust inlines away),
    /// directly detect the DATAFLOW pattern where the same pointer value is:
    ///   (A) passed to an FFI boundary function (ownership transfer OUT), AND
    ///   (B) later passed to free/dealloc (double-free risk), OR
    ///   (C) used after the transfer target may have freed it (UAF risk)
    fn detectOwnershipTransferViolations(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Collect all pointers passed to FFI boundary calls
        var ffi_transferred_ptrs = std.ArrayList(c.LLVMValueRef).initCapacity(self.allocator, 16) catch return;
        defer ffi_transferred_ptrs.deinit(self.allocator);

        // Collect all pointers passed to free/dealloc calls
        var freed_ptrs = std.ArrayList(FreeEntry).initCapacity(self.allocator, 8) catch return;
        defer freed_ptrs.deinit(self.allocator);

        const func_name = getFunctionName(func);

        // Single pass: categorize all call/invoke instructions
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;
                const name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(name_ptr) == 0) continue;
                const callee_name = std.mem.span(name_ptr);

                // Is this an FFI boundary call? (non-Rust-mangled, non-llvm intrinsic)
                const is_ffi_boundary = !isRustMangledName(callee_name) and
                    !std.mem.startsWith(u8, callee_name, "llvm.");

                // Is this a free-like call?
                const is_free_call = isFreeLikeFunction(callee_name);

                if (is_ffi_boundary) {
                    // Record pointer-type arguments that were transferred to FFI
                    const num_args = c.LLVMGetNumArgOperands(inst);
                    var arg_i: u32 = 0;
                    while (arg_i < num_args) : (arg_i += 1) {
                        const arg = c.LLVMGetOperand(inst, arg_i);
                        if (@intFromPtr(arg) == 0) continue;
                        const arg_type = c.LLVMTypeOf(arg);
                        if (@intFromPtr(arg_type) == 0) continue;
                        if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                            try ffi_transferred_ptrs.append(self.allocator, arg);
                        }
                    }
                }

                if (is_free_call) {
                    // Record the freed pointer
                    const num_args = c.LLVMGetNumArgOperands(inst);
                    if (num_args >= 1) {
                        const freed_arg = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(freed_arg) != 0) {
                            // Store callee_name as slice backed by LLVM string (no copy needed — used immediately below)
                            try freed_ptrs.append(self.allocator, .{ .val = freed_arg, .free_name = callee_name });
                        }
                    }
                }
            }
        }

        if (ffi_transferred_ptrs.items.len == 0 or freed_ptrs.items.len == 0) return;

        // Deduplication: track (freed_val, ffi_val) pairs we've already reported
        var reported = std.AutoHashMap(usize, void).init(self.allocator);
        defer reported.deinit();

        // Cross-check: does any freed_ptr match (via def-use chain) any ffi_transferred_ptr?
        // Only report each unique pair once
        for (freed_ptrs.items) |free_entry| {
            for (ffi_transferred_ptrs.items) |ffi_ptr| {
                // Strict check: require same base value, not just any alias
                const free_base = getBaseValue(free_entry.val) orelse continue;
                const ffi_base = getBaseValue(ffi_ptr) orelse continue;
                if (free_base != ffi_base) continue;

                // Compute dedup key from pointer addresses
                const key = @as(usize, @intFromPtr(free_entry.val)) * 31 + @as(usize, @intFromPtr(ffi_ptr));
                if (reported.contains(key)) continue;
                try reported.put(key, {});

                self.stats.unpaired_into_raw += 1;

                const trace = try self.allocator.alloc(TraceEntry, 3);
                trace[0] = TraceEntry.init("Ownership violation: pointer transferred to FFI then freed");
                trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
                    self.allocator,
                    "Pointer was passed to an FFI boundary call (ownership transfer out)",
                    .{},
                ));
                trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(
                    self.allocator,
                    "Same pointer also passed to {s}() — potential double-free or cross-allocator-free",
                    .{free_entry.free_name},
                ));

                const issue = Issue.initWithTrace(
                    .use_after_free,
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Ownership violation: FFI-transferred pointer freed by {s}()",
                        .{free_entry.free_name},
                    ),
                    Location.init(func_name),
                    .high,
                    0.72,
                    trace,
                );
                // Mark as owned so DataFlowGraph will free all allocated memory
                var mutable_issue = issue;
                mutable_issue.owned = true;
                try ctx.addIssue(&mutable_issue);

                diag.warn(
                    \\RustFfiFilter: ownership violation in {s}
                    \\  → pointer transferred to FFI, then freed by {s}()
                , .{ func_name, free_entry.free_name });
            }
        }
    }

    /// Check if two values may alias (be the same pointer or derived from same source).
    /// Broader than valueDependsOn — handles bitcast/GEP chains and direct equality.
    fn valuesMayAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        if (@intFromPtr(a) == 0 or @intFromPtr(b) == 0) return false;
        if (a == b) return true;

        // Follow one level of indirection for both
        const a_unwrapped = unwrapSingleLevel(a);
        const b_unwrapped = unwrapSingleLevel(b);

        if (a_unwrapped == b_unwrapped) return true;
        if (a_unwrapped != null and a_unwrapped.? == b) return true;
        if (b_unwrapped != null and b_unwrapped.? == a) return false; // already checked a==b

        // Check if both are pointers to globals or allocations
        if (isSameBasePointer(a, b)) return true;

        return false;
    }

    /// Unwrap one level of bitcast/GEP/ptrtoint/inttoptr
    fn unwrapSingleLevel(val: c.LLVMValueRef) ?c.LLVMValueRef {
        if (@intFromPtr(val) == 0) return null;
        const opcode = c.LLVMGetInstructionOpcode(val);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr or
            opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr)
        {
            return c.LLVMGetOperand(val, 0);
        }
        return null;
    }

    /// Check if two values may point to the same base allocation.
    /// Simple heuristic: both derive from the same alloca/global/call result.
    fn isSameBasePointer(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        // If both are from the same call instruction's result
        const a_base = getBaseValue(a);
        const b_base = getBaseValue(b);
        if (a_base) |ab| {
            if (b_base) |bb| return ab == bb;
        }
        return false;
    }

    /// Get the "base" value of a pointer chain (strip bitcast/GEP).
    fn getBaseValue(val: c.LLVMValueRef) ?c.LLVMValueRef {
        var current = val;
        var depth: u32 = 0;
        while (depth < 4) : (depth += 1) {
            if (@intFromPtr(current) == 0) return null;
            const opcode = c.LLVMGetInstructionOpcode(current);
            if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
                current = c.LLVMGetOperand(current, 0);
            } else {
                break;
            }
        }
        return current;
    }

    /// Find the call instruction that produces the parent value of an instruction.
    /// For extractvalue, this means finding the call that produced the aggregate struct.
    fn findParentCall(inst: c.LLVMValueRef) ?c.LLVMValueRef {
        if (@intFromPtr(inst) == 0) return null;
        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode != c.LLVMExtractValue and opcode != c.LLVMInsertValue) return null;
        const agg = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(agg) == 0) return null;
        // Only call GetInstructionOpcode on actual instructions
        if (c.LLVMGetValueKind(agg) != c.LLVMInstructionValueKind) return null;
        const agg_opcode = c.LLVMGetInstructionOpcode(agg);
        if (agg_opcode == c.LLVMCall or agg_opcode == c.LLVMInvoke) return agg;
        // Recurse one level for bitcast/insertvalue wrappers
        if (agg_opcode == c.LLVMBitCast) {
            const src = c.LLVMGetOperand(agg, 0);
            if (@intFromPtr(src) != 0 and c.LLVMGetValueKind(src) == c.LLVMInstructionValueKind) {
                const src_opcode = c.LLVMGetInstructionOpcode(src);
                if (src_opcode == c.LLVMCall or src_opcode == c.LLVMInvoke) return src;
            }
        }
        return null;
    }

    /// Check if function name looks like a free/dealloc (conservative).
    /// Uses canonical dealloc pattern list from ptr_types.RUST_ALLOC_INTRINSICS.dealloc_only.
    fn isFreeLikeFunction(func_name: []const u8) bool {
        const free_patterns = [_][]const u8{
            "free", "dealloc", "deallocate", "operator delete", "operator delete[]",
        };
        for (free_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return true;
        }
        for (ptr_types.RUST_ALLOC_INTRINSICS.dealloc_only) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return true;
        }
        return false;
    }

    /// Rule 7: Detect as_ptr dangling — borrowed pointer used after parent deallocation.
    ///
    /// Rust's Vec::as_ptr(), String::as_ptr(), CString::as_ptr() produce pointers
    /// into the backing buffer of the owner object. If the owner is dropped/freed
    /// while the borrowed pointer is still in use, we get a dangling reference.
    ///
    /// LLVM IR pattern:
    ///   %ptr = getelementptr {ptr,i64,i64}, %vec, i32 0, i32 0   ; as_ptr extraction
    ///   %raw = bitcast ptr %ptr to ptr                         ; usable ptr
    ///   ... later ...
    ///   call void @drop(%vec)                                   ; parent dropped!
    ///   call void @c_ffi_use(ptr %raw)                          ; DANGLING!
    fn detectAsPtrDangling(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // AsPtrEntry tracks one as_ptr-like extraction
        const AsPtrEntry = struct {
            as_ptr_value: c.LLVMValueRef, // The bitcast/GEP result (the borrowed ptr)
            parent_aggregate: c.LLVMValueRef, // The Vec/String/CString it came from
            extraction_inst: c.LLVMValueRef, // The instruction that created as_ptr_value
        };

        var as_ptrs = std.ArrayList(AsPtrEntry).initCapacity(self.allocator, 16) catch return;
        defer as_ptrs.deinit(self.allocator);

        // Collect all instructions ordered by position (for temporal analysis)
        var all_instructions = std.ArrayList(c.LLVMValueRef).initCapacity(self.allocator, 64) catch return;
        defer all_instructions.deinit(self.allocator);

        const func_name = getFunctionName(func);

        // Single pass: collect as_ptr patterns and build instruction ordering
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try all_instructions.append(self.allocator, inst);

                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Pattern: GEP extracting field 0 from a struct → likely as_ptr
                if (opcode == c.LLVMGetElementPtr) {
                    const result_type = c.LLVMTypeOf(inst);
                    if (@intFromPtr(result_type) == 0) continue;
                    if (c.LLVMGetTypeKind(result_type) != c.LLVMPointerTypeKind) continue;

                    const operand = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(operand) == 0) continue;
                    const operand_type = c.LLVMTypeOf(operand);
                    if (@intFromPtr(operand_type) == 0) continue;

                    // Parent must be a struct type (Vec = {ptr, len, cap}, String = {ptr, len})
                    if (c.LLVMGetTypeKind(operand_type) == c.LLVMStructTypeKind) {
                        try as_ptrs.append(self.allocator, .{
                            .as_ptr_value = inst,
                            .parent_aggregate = operand,
                            .extraction_inst = inst,
                        });
                    }
                }
            }
        }

        if (as_ptrs.items.len == 0) return;

        // For each as_ptr, check if parent is dropped before last use of as_ptr result
        for (as_ptrs.items) |entry| {
            var parent_dropped_at: ?usize = null;
            var last_use_at: ?usize = null;

            for (all_instructions.items, 0..) |inst_i, idx| {
                const opcode = c.LLVMGetInstructionOpcode(inst_i);

                // Check if this instruction drops/deallocates the parent
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called_val = c.LLVMGetCalledValue(inst_i);
                    if (@intFromPtr(called_val) != 0) {
                        const callee_name_ptr = c.LLVMGetValueName(called_val);
                        if (@intFromPtr(callee_name_ptr) != 0) {
                            const callee_name = std.mem.span(callee_name_ptr);
                            // Is this a drop/dealloc on the parent or something derived from it?
                            const is_drop = std.mem.indexOf(u8, callee_name, "drop") != null or
                                std.mem.indexOf(u8, callee_name, "dealloc") != null or
                                isFreeLikeFunction(callee_name);
                            if (is_drop) {
                                // Check if any argument derives from the parent
                                const num_args = c.LLVMGetNumArgOperands(inst_i);
                                var arg_j: u32 = 0;
                                while (arg_j < num_args) : (arg_j += 1) {
                                    const arg = c.LLVMGetOperand(inst_i, arg_j);
                                    if (@intFromPtr(arg) == 0) continue;
                                    const base = getBaseValue(arg) orelse continue;
                                    const parent_base = getBaseValue(entry.parent_aggregate) orelse continue;
                                    if (base == parent_base) {
                                        parent_dropped_at = idx;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }

                // Check if this instruction uses the as_ptr value (or derived from it)
                if (instructionUsesValue(inst_i, entry.as_ptr_value)) {
                    last_use_at = idx;
                }
            }

            // Report if parent was dropped before the last use
            if (parent_dropped_at) |drop_idx| {
                if (last_use_at) |use_idx| {
                    if (use_idx > drop_idx) {
                        self.stats.as_ptr_escapes += 1;

                        const trace = try self.allocator.alloc(TraceEntry, 3);
                        trace[0] = TraceEntry.init("Dangling reference via as_ptr");
                        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(
                            self.allocator,
                            "Borrowed pointer (as_ptr/GEP field 0) from aggregate still used after parent dropped",
                            .{},
                        ));
                        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(
                            self.allocator,
                            "Parent dropped at instruction {d}, but pointer used again at instruction {d}",
                            .{ drop_idx, use_idx },
                        ));

                        const issue = Issue.initWithTrace(
                            .borrow_escape,
                            try std.fmt.allocPrint(
                                self.allocator,
                                "Dangling as_ptr: borrowed pointer used after parent deallocation in {s}",
                                .{func_name},
                            ),
                            Location.init(func_name),
                            .high,
                            0.78,
                            trace,
                        );
                        var mutable_issue = issue;
                        mutable_issue.owned = true;
                        try ctx.addIssue(&mutable_issue);

                        diag.warn(
                            \\RustFfiFilter: dangling as_ptr in {s}
                            \\  → borrowed pointer used after parent was dropped
                        , .{func_name});
                    }
                }
            }
        }
    }

    /// Check if an instruction uses (or transitively uses) a given value.
    fn instructionUsesValue(inst: c.LLVMValueRef, target: c.LLVMValueRef) bool {
        if (@intFromPtr(inst) == 0 or @intFromPtr(target) == 0) return false;
        if (inst == target) return true;

        const num_operands = c.LLVMGetNumOperands(inst);
        var i: c_uint = 0;
        while (i < num_operands) : (i += 1) {
            const op = c.LLVMGetOperand(inst, i);
            if (@intFromPtr(op) == 0) continue;
            if (op == target) return true;
            // Follow bitcast/GEP one level
            const op_opcode = c.LLVMGetInstructionOpcode(op);
            if (op_opcode == c.LLVMBitCast or op_opcode == c.LLVMGetElementPtr) {
                if (c.LLVMGetOperand(op, 0) == target) return true;
            }
        }
        return false;
    }

    fn addFinding(self: *RustFfiAuditor, finding: RustFfiFinding) !void {
        try self.findings.append(self.allocator, finding);
    }

    /// Generate audit report as formatted text
    pub fn generateReport(self: *const RustFfiAuditor, writer: anytype) !void {
        try writer.writeAll(
            \\╔══════════════════════════════════════════════════════════╗
            \\║           Rust FFI Safety Audit Report                  ║
            \\╠══════════════════════════════════════════════════════════╣
        );

        try writer.print(
            \\║ Functions analyzed: {d:>8}                            ║
            \\║ Findings:           {d:>8}                            ║
            \\╚══════════════════════════════════════════════════════════╝
            \\
        , .{ self.stats.total_functions_analyzed, self.findings.items.len });

        for (self.findings.items, 0..) |finding, i| {
            try writer.writeAll("┌─────────────────────────────────────────\n");
            try writer.print("│ Finding #{d}: {s}\n", .{ i + 1, @tagName(finding.issue_type) });
            try writer.print("│ Function: {s}\n", .{finding.func_name});
            try writer.print("│ Severity: [{s}]\n", .{finding.severity.toString()});
            try writer.print("│ Confidence: {d:.0%}\n", .{finding.confidence});
            try writer.print("│ Reason: {s}\n", .{finding.reason});
            try writer.writeAll("└─────────────────────────────────────────\n");
        }
    }
};

// ============================================================================
// Detection Helpers
// ============================================================================

/// Extract function name from LLVM value reference
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "unknown";
    return std.mem.span(name_ptr);
}

/// Check if a callee name is a Rust into_raw (ownership transfer OUT) call
pub fn isRustIntoRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "into_raw",
        "8into_raw",
        "Box.*into_raw",
        "CString.*into_raw",
        "Vec.*leak",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust from_raw (ownership transfer IN) call
pub fn isRustFromRawCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "from_raw",
        "8from_raw",
        "Box.*from_raw",
        "CString.*from_raw",
        "from_raw_parts",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a Rust as_ptr (borrow escape) call
pub fn isRustAsPtrCall(callee_name: []const u8) bool {
    const patterns = [_][]const u8{
        "as_ptr",
        "as_mut_ptr",
        "slice::as_ptr",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name is a C free() call
pub fn isCFreeCall(callee_name: []const u8) bool {
    return std.mem.eql(u8, callee_name, "free") or
        std.mem.indexOf(u8, callee_name, "free@") != null;
}

/// Check if a callee name looks like an extern "C" function
pub fn isExternCCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;
    if (callee_name[0] == '_') return false;
    if (std.mem.startsWith(u8, callee_name, "_Z")) return false;
    if (std.mem.startsWith(u8, callee_name, "_R")) return false;
    return true;
}

/// Detect Rust FFI pairing functions (populates into_raw/from_raw sets)
pub fn detectRustFfiPairingFunctions(
    func: c.LLVMValueRef,
    into_raw_set: *std.AutoHashMap(usize, void),
    from_raw_set: *std.AutoHashMap(usize, void),
) void {
    var has_into_raw = false;
    var has_from_raw = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands == 0) continue;
            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (isRustIntoRawCall(name_slice)) has_into_raw = true;
            if (isRustFromRawCall(name_slice)) has_from_raw = true;
        }
        if (has_into_raw and has_from_raw) break;
    }

    if (has_into_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            into_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
        }
    }
    if (has_from_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            from_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
        }
    }
}

// ============================================================================
// Stack Escape Detection Helpers (Rule 5)
// ============================================================================

/// Check if function name has a Rust mangled name prefix (_ZN / _RNv / _R).
pub fn isRustMangledName(func_name: []const u8) bool {
    const rust_prefixes = [_][]const u8{ "_ZN", "_RNv", "_R" };
    for (rust_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    return false;
}

/// Check if an FFI callee may store/retain a pointer argument beyond the call.
/// Uses heuristic name patterns for retain/store/register callbacks.
pub fn mayRetainPointer(callee_name: []const u8) bool {
    const retain_indicators = [_][]const u8{
        "_store_",  "_save_", "_set_",  "_register_",
        "_retain_", "_keep_", "_hold_",
    };
    for (retain_indicators) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }
    // Callback registration patterns
    if (std.mem.indexOf(u8, callee_name, "callback") != null or
        std.mem.indexOf(u8, callee_name, "register") != null)
    {
        return true;
    }
    return false;
}

/// Check if a value is derived from an alloca instruction (stack allocation).
/// Walks through bitcast/GEP chains to find the ultimate source.
pub fn isDerivedFromAlloca(val: c.LLVMValueRef) bool {
    if (@intFromPtr(val) == 0) return false;
    const opcode = c.LLVMGetInstructionOpcode(val);
    if (opcode == c.LLVMAlloca) return true;
    // Follow bitcast/GEP chains recursively
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
        const src = c.LLVMGetOperand(val, 0);
        return isDerivedFromAlloca(src);
    }
    return false;
}

/// Pure-consumption functions that read pointers but don't store them.
/// Safe to pass stack addresses to — no escape risk.
pub fn isPureConsumptionFunction(callee_name: []const u8) bool {
    const safe_fns = [_][]const u8{
        "memcpy",  "memmove",  "printf",  "fprintf",
        "sprintf", "snprintf", "puts",    "fputs",
        "strlen",  "strcmp",   "strncmp",
    };
    for (safe_fns) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "RustFfiAuditor - init and deinit" {
    var auditor = try RustFfiAuditor.init(std.testing.allocator);
    defer auditor.deinit();
    try std.testing.expectEqual(@as(usize, 0), auditor.findings.items.len);
    try std.testing.expectEqual(@as(usize, 0), auditor.stats.total_functions_analyzed);
}

test "isRustIntoRawCall - detection" {
    try std.testing.expect(isRustIntoRawCall("_ZN5alloc3boxed3Box*.*8into_raw17h"));
    try std.testing.expect(isRustIntoRawCall("into_raw"));
    try std.testing.expect(!isRustIntoRawCall("from_raw"));
    try std.testing.expect(!isRustIntoRawCall("malloc"));
}

test "isRustFromRawCall - detection" {
    try std.testing.expect(isRustFromRawCall("_ZN5alloc3boxed3Box*.*8from_raw17h"));
    try std.testing.expect(isRustFromRawCall("from_raw"));
    try std.testing.expect(!isRustFromRawCall("into_raw"));
}

test "isRustAsPtrCall - detection" {
    try std.testing.expect(isRustAsPtrCall("as_ptr"));
    try std.testing.expect(isRustAsPtrCall("as_mut_ptr"));
    try std.testing.expect(!isRustAsPtrCall("from_raw"));
}

test "isCFreeCall - detection" {
    try std.testing.expect(isCFreeCall("free"));
    try std.testing.expect(isCFreeCall("free@GLIBC"));
    try std.testing.expect(!isCFreeCall("malloc"));
}

test "isExternCCall - detection" {
    try std.testing.expect(isExternCCall("sqlite3_exec"));
    try std.testing.expect(isExternCCall("printf"));
    try std.testing.expect(!isExternCCall("_Znwm"));
    try std.testing.expect(!isExternCCall("_RNvC"));
}

test "isRustMangledName - detection" {
    try std.testing.expect(isRustMangledName("_ZN9hello_world4mainE"));
    try std.testing.expect(isRustMangledName("_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc"));
    try std.testing.expect(isRustMangledName("_RINv"));
    try std.testing.expect(!isRustMangledName("c_ffi_process_buffer"));
    try std.testing.expect(!isRustMangledName("malloc"));
}

test "mayRetainPointer - detection" {
    try std.testing.expect(mayRetainPointer("c_ffi_store_pointer"));
    try std.testing.expect(mayRetainPointer("c_ffi_register_callback"));
    try std.testing.expect(mayRetainPointer("set_user_data"));
    try std.testing.expect(!mayRetainPointer("memcpy"));
    try std.testing.expect(!mayRetainPointer("c_ffi_process_buffer"));
}

test "isPureConsumptionFunction - safe functions" {
    try std.testing.expect(isPureConsumptionFunction("memcpy"));
    try std.testing.expect(isPureConsumptionFunction("printf"));
    try std.testing.expect(isPureConsumptionFunction("strlen"));
    try std.testing.expect(!isPureConsumptionFunction("c_ffi_store_pointer"));
    try std.testing.expect(!isPureConsumptionFunction("pthread_create"));
}
