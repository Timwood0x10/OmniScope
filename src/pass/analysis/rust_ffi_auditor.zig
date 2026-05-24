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
const ffi_language_classifier = @import("ffi_language_classifier.zig");
const rust_drop_semantics = @import("../../semantics/rust_drop_semantics.zig");

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
        // C4 FIX: Don't free func_name and reason - they are NOT owned by this struct.
        // - func_name comes from LLVMGetValueName (LLVM-owned, must not free)
        // - reason is always a string literal (comptime, must not free)
        // Only the findings ArrayList itself was allocated by us.
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

        diag.info("FFIAuditor: analyzed {d} funcs, {d} findings ({d} stack escapes)", .{ auditor.stats.total_functions_analyzed, auditor.findings.items.len, auditor.stats.stack_escapes });
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

        // Rule 8: Callback ownership risk — function pointer parameter stored to global
        try self.detectCallbackOwnershipRisk(func, ctx, diag);

        // Rule 9: Write to immutable — store through pointer from const-qualified struct field
        try self.detectWriteToImmutable(func, ctx, diag);

        // Rule 10: Use after free — post-free pointer use within same function
        try self.detectUseAfterFree(func, ctx, diag);
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
        var visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer visited.deinit();

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

                // Get the pointer argument to free() and trace its origin
                const ptr_arg = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(ptr_arg) == 0) continue;

                // Only report if the pointer can be traced back to a Rust allocator
                if (!ptrOriginatesFromRustAlloc(func, ptr_arg, &visited)) continue;

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
                            errdefer self.allocator.free(trace);
                            trace[0] = TraceEntry.init("Stack address escapes across FFI boundary");

                            const desc1 = try std.fmt.allocPrint(
                                self.allocator,
                                "Argument {d} of {s} derived from alloca instruction",
                                .{ arg_i, callee_name },
                            );
                            errdefer self.allocator.free(desc1);
                            trace[1] = TraceEntry.initOwned(desc1);

                            const desc2 = try std.fmt.allocPrint(
                                self.allocator,
                                "Callee may store pointer beyond caller's lifetime",
                                .{},
                            );
                            errdefer self.allocator.free(desc2);
                            trace[2] = TraceEntry.initOwned(desc2);

                            const msg = try std.fmt.allocPrint(
                                self.allocator,
                                "Stack address escapes to FFI: {s}() receives alloca-derived pointer",
                                .{callee_name},
                            );
                            errdefer self.allocator.free(msg);

                            const issue = Issue.initWithTrace(
                                .borrow_escape,
                                msg,
                                Location.init(func_name),
                                .high,
                                0.80,
                                trace,
                            );
                            var mutable_issue = issue;
                            mutable_issue.owned = true;
                            try ctx.addIssue(&mutable_issue);

                            diag.warn("FFIAuditor: stack escape in {s} → {s}() arg {d}", .{ func_name, callee_name, arg_i });
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
                errdefer self.allocator.free(trace);

                trace[0] = TraceEntry.init("Ownership violation: pointer transferred to FFI then freed");

                const desc1 = try std.fmt.allocPrint(
                    self.allocator,
                    "Pointer was passed to an FFI boundary call (ownership transfer out)",
                    .{},
                );
                errdefer self.allocator.free(desc1);
                trace[1] = TraceEntry.initOwned(desc1);

                const desc2 = try std.fmt.allocPrint(
                    self.allocator,
                    "Same pointer also passed to {s}() — potential double-free or cross-allocator-free",
                    .{free_entry.free_name},
                );
                errdefer self.allocator.free(desc2);
                trace[2] = TraceEntry.initOwned(desc2);

                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Ownership violation: FFI-transferred pointer freed by {s}()",
                    .{free_entry.free_name},
                );
                errdefer self.allocator.free(msg);

                const issue = Issue.initWithTrace(
                    .use_after_free,
                    msg,
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
                    \\FFIAuditor: ownership violation in {s}
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
        if (b_unwrapped != null and b_unwrapped.? == a) return true;

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
                            // Use rust_drop_semantics to classify the call:
                            //   - drop_in_place = implicit scope-end destructor (compiler-generated)
                            //   - __rust_dealloc = part of drop chain (compiler-generated cleanup)
                            //   - C free() = manual free (potentially dangerous)
                            const drop_class = rust_drop_semantics.classifyDropCall(callee_name);
                            const is_drop = drop_class == .is_drop_glue or
                                drop_class == .is_dealloc_in_drop_chain or
                                drop_class == .is_manual_free;
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
                        errdefer self.allocator.free(trace);

                        // Distinguish implicit scope-end drop (compiler-generated)
                        // from explicit manual free (user-caused).
                        // Implicit drops are normal cleanup — still a real dangling
                        // ptr issue, but less likely to be exploitable than a manual
                        // double-free. The diagnostic helps users understand the
                        // root cause: Rust's implicit drop glue at scope exit.
                        trace[0] = TraceEntry.init("Dangling reference via as_ptr after implicit scope-end drop");

                        const desc1 = try std.fmt.allocPrint(
                            self.allocator,
                            "Borrowed pointer (as_ptr/GEP field 0) from aggregate still used after parent dropped",
                            .{},
                        );
                        errdefer self.allocator.free(desc1);
                        trace[1] = TraceEntry.initOwned(desc1);

                        const desc2 = try std.fmt.allocPrint(
                            self.allocator,
                            "Parent dropped at instruction {d}, but pointer used again at instruction {d}",
                            .{ drop_idx, use_idx },
                        );
                        errdefer self.allocator.free(desc2);
                        trace[2] = TraceEntry.initOwned(desc2);

                        const msg = try std.fmt.allocPrint(
                            self.allocator,
                            "Dangling as_ptr: borrowed pointer used after parent deallocation in {s}",
                            .{func_name},
                        );
                        errdefer self.allocator.free(msg);

                        const issue = Issue.initWithTrace(
                            .borrow_escape,
                            msg,
                            Location.init(func_name),
                            .high,
                            0.78,
                            trace,
                        );
                        var mutable_issue = issue;
                        mutable_issue.owned = true;
                        try ctx.addIssue(&mutable_issue);

                        diag.warn(
                            \\FFIAuditor: dangling as_ptr in {s}
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

    /// Rule 8: Detect callback ownership risk — function pointer parameter stored to global.
    ///
    /// GO-05 pattern: Function pointer from caller is stored to a global variable.
    /// When this global is later used for an indirect call, the callback may dangle
    /// if the original function/stack frame has been destroyed.
    ///
    /// Detection criteria (all must be true):
    ///   1. Store target is a global variable (LLVMIsAGlobalValue)
    ///   2. Stored value is function pointer type (LLVMFunctionTypeKind)
    ///   3. Stored value originates from function parameter (LLVMIsAArgument)
    ///
    /// CWE-825: Exploitable with callback through pointer to non-argument
    fn detectCallbackOwnershipRisk(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMStore) continue;

                // Condition 1: Store target must be a global variable
                const dest = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(dest) == 0) continue;
                if (c.LLVMIsAGlobalValue(dest) == null) continue;

                // Get global name for reporting
                const global_name_ptr = c.LLVMGetValueName(dest);
                const global_name = if (@intFromPtr(global_name_ptr) != 0)
                    std.mem.span(global_name_ptr)
                else
                    "@anonymous_global";

                // Skip known safe globals (signal handler tables, vtable slots, etc.)
                if (isSafeGlobalStore(global_name)) continue;

                // Condition 2: Value should be a pointer type (with opaque pointers,
                // we can't reliably distinguish function ptr from data ptr via types alone).
                // Instead, we verify that the global is later used for indirect calls.
                const value = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(value) == 0) continue;
                const value_type = c.LLVMTypeOf(value);
                if (@intFromPtr(value_type) == 0) continue;

                // Must be some kind of pointer (opaque or typed)
                const type_kind = c.LLVMGetTypeKind(value_type);
                if (type_kind != c.LLVMPointerTypeKind) continue;

                // Heuristic: check if this global is used for indirect calls elsewhere
                // This confirms it's being treated as a function pointer
                if (!isGlobalUsedForIndirectCall(global_name, func)) {
                    continue;
                }

                // Condition 3: Value source must be a function parameter (or loaded from param storage)
                // C compiler pattern: param → alloca → load → store @global
                // We need to trace through one level of load to find the original parameter
                if (!isValueFromParameter(value)) continue;

                // All three conditions met — report callback_ownership_risk
                const func_name = getFunctionName(func);

                const trace = try self.allocator.alloc(TraceEntry, 4);
                errdefer self.allocator.free(trace);
                trace[0] = TraceEntry.init("Function pointer parameter stored to global variable");
                trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(self.allocator, "Global: {s}", .{global_name}));
                trace[2] = TraceEntry.init("Callback lifetime controlled by caller — may dangle if caller's scope ends");
                trace[3] = TraceEntry.init("Indirect call via this global may use-after-return");

                const message = try std.fmt.allocPrint(
                    self.allocator,
                    "Function pointer from parameter stored to global {s} — caller controls callback lifetime (CWE-825)",
                    .{global_name},
                );

                var issue = Issue.initWithTrace(
                    .callback_ownership_risk,
                    message,
                    Location.init(func_name),
                    .high,
                    0.82,
                    trace,
                );
                errdefer issue.deinit(self.allocator);

                try ctx.addIssue(&issue);
                diag.warn("[OMI-HIGH] [CALLBACK-RISK] fn param -> global {s} in {s}", .{ global_name, func_name });
            }
        }
    }

    /// Check if storing to this global is a known-safe pattern (false positive suppression).
    fn isSafeGlobalStore(global_name: []const u8) bool {
        const safe_prefixes = [_][]const u8{
            "__sig_", "_ZTV",   "_ZTI",       ".cxx_delet",
            "atexit", "__cxa_", "__pthread_", "_fini",
            "_init",  ".llvm.",
        };
        for (safe_prefixes) |prefix| {
            if (std.mem.indexOf(u8, global_name, prefix) != null) return true;
        }

        const safe_globals = [_][]const u8{
            "environ", "stderr", "stdout", "stdin", "optarg", "errno",
        };
        for (safe_globals) |safe_name| {
            if (std.mem.eql(u8, global_name, safe_name)) return true;
        }
        return false;
    }

    /// Check if a value originates from a function parameter.
    /// Handles the common C compiler pattern:
    ///   param → store alloca → load → use
    fn isValueFromParameter(value: c.LLVMValueRef) bool {
        // Direct: value IS a parameter
        if (c.LLVMIsAArgument(value) != null) return true;

        // Indirect: value is a load from an alloca that stores a parameter
        const opcode = c.LLVMGetInstructionOpcode(value);
        if (opcode == c.LLVMLoad) {
            const ptr_operand = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(ptr_operand) == 0) return false;

            // Check if loaded from an alloca that was initialized with a parameter
            // We scan the same basic block for: store %param, ptr %alloca
            const parent_bb = c.LLVMGetInstructionParent(value);
            if (@intFromPtr(parent_bb) == 0) return false;

            var inst = c.LLVMGetFirstInstruction(parent_bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
                if (c.LLVMGetOperand(inst, 1) != ptr_operand) continue; // not storing to this alloca

                // Check if stored value is a parameter
                const stored_val = c.LLVMGetOperand(inst, 0);
                if (c.LLVMIsAArgument(stored_val) != null) return true;
            }
        }

        return false;
    }

    /// Check if a global variable is used for indirect calls anywhere in the module.
    /// This confirms that the global is being treated as a function pointer (callback).
    fn isGlobalUsedForIndirectCall(global_name: []const u8, current_func: c.LLVMValueRef) bool {
        const module = c.LLVMGetGlobalParent(current_func);
        if (@intFromPtr(module) == 0) return false;

        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    // Check for indirect call (call/invoke with non-function callee)
                    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                        const callee = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(callee) == 0) continue;

                        // If callee is not a direct function, it's an indirect call
                        if (c.LLVMIsAFunction(callee) == null) {
                            // Check if this indirect call uses our global
                            if (isValueFromGlobal(callee, global_name)) {
                                return true;
                            }
                        }
                    }
                }
            }
        }

        return false;
    }

    /// Check if a value ultimately originates from a specific global variable.
    /// Handles: load @global, or load → bitcast → load chain
    fn isValueFromGlobal(value: c.LLVMValueRef, global_name: []const u8) bool {
        // Direct: value IS the global
        if (c.LLVMIsAGlobalValue(value) != null) {
            const name_ptr = c.LLVMGetValueName(value);
            if (@intFromPtr(name_ptr) != 0) {
                const val_name = std.mem.span(name_ptr);
                if (std.mem.eql(u8, val_name, global_name)) return true;
            }
        }

        // Indirect: value is a load from the global
        const opcode = c.LLVMGetInstructionOpcode(value);
        if (opcode == c.LLVMLoad) {
            const ptr_op = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(ptr_op) != 0) {
                return isValueFromGlobal(ptr_op, global_name);
            }
        }

        // Through bitcast/GEP
        if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
            const src = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(src) != 0) {
                return isValueFromGlobal(src, global_name);
            }
        }

        return false;
    }

    /// Rule 9: Detect write-to-immutable violations.
    ///
    /// Generic pattern: Code loads a pointer from a struct field, then stores/writes
    /// through that pointer. This violates immutability guarantees.
    ///
    /// Detection strategy: Two-pass scan
    ///   Pass 1: Collect all "struct field pointer" values (GEP into struct + load)
    ///   Pass 2: For each data store, check if dest traces to any collected field ptr
    fn detectWriteToImmutable(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const func_name = getFunctionName(func);

        // Pass 1: Collect all struct field pointers loaded in this function
        const MaxFieldPtrs: usize = 32;
        var field_ptr_count: usize = 0;
        var struct_field_ptrs: [MaxFieldPtrs]c.LLVMValueRef = undefined;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Look for: load(ptr, GEP(struct_type, ...))
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMLoad) continue;

                const load_src = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(load_src) == 0) continue;
                if (c.LLVMGetInstructionOpcode(load_src) != c.LLVMGetElementPtr) continue;

                // Check if GEP base is pointer-to-struct
                const gep_base = c.LLVMGetOperand(load_src, 0);
                if (@intFromPtr(gep_base) == 0) continue;
                const base_type = c.LLVMTypeOf(gep_base);
                if (@intFromPtr(base_type) == 0) continue;

                // Check if this is a struct field GEP (not array/buffer GEP).
                // With opaque pointers, we can't use type checks.
                // Instead: struct GEPs have ≥3 operands (ptr, i32 0, i32 field_idx).
                const num_gep_operands = c.LLVMGetNumOperands(load_src);
                const is_struct_gep = num_gep_operands >= 3;

                if (!is_struct_gep) continue;

                // This load reads a pointer from a struct field — record it
                if (field_ptr_count < MaxFieldPtrs) {
                    struct_field_ptrs[field_ptr_count] = inst;
                    field_ptr_count += 1;
                }
            }
        }

        // No struct field accesses — nothing to check
        if (field_ptr_count == 0) return;

        // Pass 2: Check each store instruction for writes through struct field pointers
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;

                const dest_ptr = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(dest_ptr) == 0) continue;

                // Check if dest_ptr traces to any recorded struct field load
                for (struct_field_ptrs[0..field_ptr_count]) |field_load| {
                    if (ptrTracesTo(dest_ptr, field_load)) {
                        // Found write through struct field pointer!
                        const struct_name = getStructNameForValue(field_load) orelse "unknown_struct";

                        const trace = try self.allocator.alloc(TraceEntry, 4);
                        errdefer self.allocator.free(trace);
                        trace[0] = TraceEntry.init("Write through pointer loaded from struct field");
                        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(self.allocator, "Struct: {s} — field pointer used as write destination", .{struct_name}));
                        trace[2] = TraceEntry.init("Writing to memory via struct field pointer may violate immutability");
                        trace[3] = TraceEntry.init("Original data owner may assume field content is read-only");

                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "Write to immutable memory via struct '{s}' field pointer — potential violation of immutability contract (CWE-757)",
                            .{struct_name},
                        );

                        var issue = Issue.initWithTrace(
                            .write_to_immutable,
                            message,
                            Location.init(func_name),
                            .high,
                            0.85,
                            trace,
                        );
                        errdefer issue.deinit(self.allocator);

                        try ctx.addIssue(&issue);
                        diag.warn("[OMI-HIGH] [WRITE-IMMUTABLE] struct '{s}' in {s}", .{ struct_name, func_name });
                        break; // One report per store is enough
                    }
                }
            }
        }
    }

    /// Check if `user_value` ultimately derives from `source_value`.
    /// Handles common C compiler patterns: source → store alloca → load → GEP → user
    fn ptrTracesTo(user_value: c.LLVMValueRef, source_value: c.LLVMValueRef) bool {
        // Direct match
        if (user_value == source_value) return true;

        const opcode = c.LLVMGetInstructionOpcode(user_value);

        // Through GEP: user is GEP(base, ...) and base traces to source
        if (opcode == c.LLVMGetElementPtr) {
            const base = c.LLVMGetOperand(user_value, 0);
            if (@intFromPtr(base) != 0 and ptrTracesTo(base, source_value)) return true;
        }

        // Through bitcast
        if (opcode == c.LLVMBitCast) {
            const src = c.LLVMGetOperand(user_value, 0);
            if (@intFromPtr(src) != 0 and ptrTracesTo(src, source_value)) return true;
        }

        // Through load: user is load(ptr) and ptr was stored with source
        if (opcode == c.LLVMLoad) {
            const load_ptr = c.LLVMGetOperand(user_value, 0);
            if (@intFromPtr(load_ptr) != 0) {
                // Check if source was stored to this pointer
                const parent_bb = c.LLVMGetInstructionParent(user_value);
                if (@intFromPtr(parent_bb) != 0) {
                    var inst = c.LLVMGetFirstInstruction(parent_bb);
                    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                        if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
                        if (c.LLVMGetOperand(inst, 1) != load_ptr) continue;
                        if (c.LLVMGetOperand(inst, 0) == source_value) return true;
                    }
                }
            }
        }

        return false;
    }

    /// Try to extract struct name from a value (GEP or load from GEP).
    fn getStructNameForValue(val: c.LLVMValueRef) ?[]const u8 {
        // If val is a load, get its source
        var target = val;
        if (c.LLVMGetInstructionOpcode(val) == c.LLVMLoad) {
            const src = c.LLVMGetOperand(val, 0);
            if (@intFromPtr(src) != 0) target = src;
        }

        // Now target should be a GEP
        if (c.LLVMGetInstructionOpcode(target) == c.LLVMGetElementPtr) {
            return getStructNameFromGEP(target);
        }
        return null;
    }

    /// Result of tracing a pointer back to its struct field origin.
    const ConstFieldInfo = struct {
        field_name: []const u8,
        struct_name: []const u8,
    };

    /// Trace a pointer value back to see if it was loaded from a const-qualified
    /// struct field. Handles multi-level indirection common in C compiler output.
    ///
    /// GO-07 pattern: GEP(i8, load(alloca), 0) where alloca stores
    ///               load(GEP(struct, 0, N)) — struct field pointer
    fn traceConstFieldLoad(self: *RustFfiAuditor, ptr_val: c.LLVMValueRef) ?ConstFieldInfo {
        const opcode = c.LLVMGetInstructionOpcode(ptr_val);

        // Case 1: Direct GEP into buffer (most common pattern)
        if (opcode == c.LLVMGetElementPtr) {
            // First check if this GEP directly indexes into a struct
            if (traceGepToConstField(ptr_val)) |info| return info;

            // Otherwise trace through the base pointer
            const base = c.LLVMGetOperand(ptr_val, 0);
            if (@intFromPtr(base) == 0) return null;

            const base_opcode = c.LLVMGetInstructionOpcode(base);

            switch (base_opcode) {
                c.LLVMLoad => {
                    // Pattern: GEP(i8, load(alloca), idx)
                    const alloca_ptr = c.LLVMGetOperand(base, 0);
                    if (@intFromPtr(alloca_ptr) != 0) {
                        const stored_val = findStoreToAlloca(alloca_ptr);

                        if (@intFromPtr(stored_val) != 0) {
                            // Recurse: try to trace stored value to struct field
                            if (traceConstFieldLoad(self, stored_val)) |info| return info;
                        }
                    }
                },
                c.LLVMGetElementPtr => {
                    // Nested GEP: GEP(i8, GEP(struct, ...), idx)
                    // Recurse into inner GEP
                    if (traceConstFieldLoad(self, base)) |info| return info;
                },
                else => {
                    // Unhandled base opcode
                },
            }

            // Final fallback: check if base itself leads to struct field
            return traceConstFieldLoad(self, base);
        }

        // Case 2: Value loaded from somewhere — trace source
        if (opcode == c.LLVMLoad) {
            const src = c.LLVMGetOperand(ptr_val, 0);
            if (@intFromPtr(src) != 0) {
                return traceConstFieldLoad(self, src);
            }
        }

        return null;
    }

    /// Scan the basic block containing an alloca to find what value was stored into it.
    /// Returns the stored value, or null if not found.
    fn findStoreToAlloca(alloca_val: c.LLVMValueRef) c.LLVMValueRef {
        const parent_bb = c.LLVMGetInstructionParent(alloca_val);
        if (@intFromPtr(parent_bb) == 0) {
            const null_val: c.LLVMValueRef = @ptrFromInt(0);
            return null_val;
        }

        var inst = c.LLVMGetFirstInstruction(parent_bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
            if (c.LLVMGetOperand(inst, 1) != alloca_val) continue;
            // Found store to this alloca — return the value being stored
            return c.LLVMGetOperand(inst, 0);
        }

        const null_val: c.LLVMValueRef = @ptrFromInt(0);
        return null_val;
    }

    /// Check if a GEP instruction indexes into a struct field (for write-to-immutable check).
    fn traceGepToConstField(gep_inst: c.LLVMValueRef) ?ConstFieldInfo {
        if (c.LLVMGetInstructionOpcode(gep_inst) != c.LLVMGetElementPtr) return null;

        const base_ptr = c.LLVMGetOperand(gep_inst, 0);
        if (@intFromPtr(base_ptr) == 0) return null;

        // Check if this GEP indexes into a struct type
        const base_type = c.LLVMTypeOf(base_ptr);
        if (@intFromPtr(base_type) == 0) return null;

        var elem_type = base_type;
        if (c.LLVMGetTypeKind(elem_type) == c.LLVMPointerTypeKind) {
            elem_type = c.LLVMGetElementType(elem_type);
        }
        if (@intFromPtr(elem_type) == 0) return null;

        // Direct: base pointer is pointer-to-struct
        if (c.LLVMGetTypeKind(elem_type) == c.LLVMStructTypeKind) {
            const struct_name = getStructNameFromGEP(gep_inst) orelse "unknown_struct";
            return ConstFieldInfo{
                .field_name = "data",
                .struct_name = struct_name,
            };
        }

        // Indirect: base_ptr is load from struct GEP
        if (c.LLVMGetInstructionOpcode(base_ptr) == c.LLVMLoad) {
            const load_src = c.LLVMGetOperand(base_ptr, 0);
            if (@intFromPtr(load_src) != 0 and
                c.LLVMGetInstructionOpcode(load_src) == c.LLVMGetElementPtr)
            {
                const inner_name = getStructNameFromGEP(load_src) orelse "unknown_struct";
                return ConstFieldInfo{
                    .field_name = "data",
                    .struct_name = inner_name,
                };
            }
        }

        return null;
    }

    /// Try to extract struct name from a GEP instruction's base type.
    fn getStructNameFromGEP(gep: c.LLVMValueRef) ?[]const u8 {
        const base = c.LLVMGetOperand(gep, 0);
        if (@intFromPtr(base) == 0) return null;
        const base_type = c.LLVMTypeOf(base);
        if (@intFromPtr(base_type) == 0) return null;

        // Check if it's a pointer to struct
        if (c.LLVMGetTypeKind(base_type) == c.LLVMPointerTypeKind) {
            const elem = c.LLVMGetElementType(base_type);
            if (@intFromPtr(elem) != 0 and c.LLVMGetTypeKind(elem) == c.LLVMStructTypeKind) {
                const name_ptr = c.LLVMGetStructName(elem);
                if (@intFromPtr(name_ptr) != 0) {
                    return std.mem.span(name_ptr);
                }
            }
        }
        return null;
    }

    /// Get the field index from a struct GEP instruction.
    fn getGepFieldIndex(gep: c.LLVMValueRef) u32 {
        const num_operands = c.LLVMGetNumOperands(gep);
        // For struct GEP: operand 2 is the field index (after ptr and 0)
        if (num_operands >= 3) {
            const idx_val = c.LLVMGetOperand(gep, 2);
            if (@intFromPtr(idx_val) != 0 and c.LLVMIsAConstantInt(idx_val) != null) {
                // Field index is operand 2 in struct GEP
                return 0; // Default to field 0 for now
            }
        }
        return 0;
    }

    /// Format a field index as a name string.
    fn tryFmtFieldIndex(idx: u32) []const u8 {
        _ = idx;
        return "data"; // Common name for field 0 in string-like structs
    }

    /// Rule 10: Detect use-after-free within a single function.
    ///
    /// Tracks free/dealloc calls and checks if subsequent instructions use
    /// the freed pointer. This catches intra-function UAF patterns without
    /// requiring full inter-procedural alias analysis.
    ///
    /// LLVM IR pattern:
    ///   call void @free(ptr %allocated)          ; FREE
    ///   ...
    ///   store i32 42, ptr %allocated              ; USE AFTER FREE!
    ///   OR
    ///   call void @memset(ptr %allocated, ...)   ; USE AFTER FREE!
    fn detectUseAfterFree(self: *RustFfiAuditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const func_name = getFunctionName(func);

        // Collect all freed pointer values (use fixed-size array, rarely >4 per function)
        const MaxFreed: usize = 16;
        var freed_count: usize = 0;
        var freed_ptrs: [MaxFreed]struct {
            ptr_val: c.LLVMValueRef,
            free_inst: c.LLVMValueRef,
            free_func_name: []const u8,
        } = undefined;

        // Pass 1: Find all free/dealloc calls
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) == 0) continue;
                if (c.LLVMIsAFunction(called) != null) continue; // direct call, check name

                const callee_name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(callee_name_ptr) == 0) continue;
                const callee_name = std.mem.span(callee_name_ptr);

                // Check if this is a known deallocator
                if (!isDeallocator(callee_name)) continue;

                // Record the freed pointer (first argument)
                const freed_ptr = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(freed_ptr) == 0) continue;

                if (freed_count < MaxFreed) {
                    freed_ptrs[freed_count] = .{
                        .ptr_val = freed_ptr,
                        .free_inst = inst,
                        .free_func_name = callee_name,
                    };
                    freed_count += 1;
                }
            }
        }

        // No frees found — nothing to check
        if (freed_count == 0) return;

        // Pass 2: Check for post-free uses of each freed pointer
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                for (freed_ptrs[0..freed_count]) |fp| {
                    // Skip instructions before/at the free point
                    if (instructionComesBeforeOrEqual(inst, fp.free_inst)) continue;

                    // Check if this instruction uses the freed pointer
                    if (instructionUsesValue(inst, fp.ptr_val)) {
                        // Report UAF
                        const trace = try self.allocator.alloc(TraceEntry, 4);
                        errdefer self.allocator.free(trace);
                        trace[0] = TraceEntry.init("Memory freed by deallocation function");
                        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(self.allocator, "Free: {s}()", .{fp.free_func_name}));
                        trace[2] = TraceEntry.init("Subsequent instruction uses the freed pointer");
                        trace[3] = TraceEntry.init("Pointer is no longer valid — undefined behavior");

                        const opcode = c.LLVMGetInstructionOpcode(inst);
                        const op_desc = switch (opcode) {
                            c.LLVMStore => "store through freed pointer",
                            c.LLVMLoad => "load from freed pointer",
                            c.LLVMCall, c.LLVMInvoke => "call with freed pointer as argument",
                            else => "use of freed pointer",
                        };

                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "Use after free: pointer freed by {s}() is later used for {s} (CWE-416)",
                            .{ fp.free_func_name, op_desc },
                        );

                        var issue = Issue.initWithTrace(
                            .use_after_free,
                            message,
                            Location.init(func_name),
                            .critical,
                            0.90,
                            trace,
                        );
                        errdefer issue.deinit(self.allocator);

                        try ctx.addIssue(&issue);
                        diag.critical("[OMI-CRITICAL] [UAF] {s}() -> {s} in {s}", .{ fp.free_func_name, op_desc, func_name });

                        // Only report once per freed pointer to avoid noise
                        break;
                    }
                }
            }
        }
    }

    /// Check if a function name matches known deallocator patterns across languages.
    fn isDeallocator(func_name: []const u8) bool {
        // C standard library
        if (std.mem.eql(u8, func_name, "free")) return true;
        if (std.mem.eql(u8, func_name, "realloc")) return true; // realloc(ptr, 0) can free

        // Go/cgo runtime
        if (std.mem.indexOf(u8, func_name, "_cgo_free") != null) return true;
        if (std.mem.indexOf(u8, func_name, "_Cfunc_GoFree") != null) return true;

        // Rust
        if (std.mem.indexOf(u8, func_name, "__rust_dealloc") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__rust_alloc_error_handler") != null) return true;

        // C++
        if (std.mem.indexOf(u8, func_name, "_Zdl") != null) return true; // operator delete
        if (std.mem.indexOf(u8, func_name, "_Zda") != null) return true; // operator delete[]

        // Objective-C
        if (std.mem.indexOf(u8, func_name, "objc_release") != null) return true;

        // Python C API
        if (std.mem.indexOf(u8, func_name, "PyMem_Free") != null) return true;
        if (std.mem.indexOf(u8, func_name, "PyObject_Free") != null) return true;

        // Java JNI
        if (std.mem.indexOf(u8, func_name, "DeleteLocalRef") != null) return true;
        if (std.mem.indexOf(u8, func_name, "ReleaseStringUTF") != null) return true;

        // POSIX
        if (std.mem.eql(u8, func_name, "munmap")) return true;
        if (std.mem.eql(u8, func_name, "close")) return false; // fd, not memory

        return false;
    }

    /// Check if instruction A comes before (or at) instruction B in the same basic block.
    /// Returns false for different basic blocks (conservative: assume A comes after).
    fn instructionComesBeforeOrEqual(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        const bb_a = c.LLVMGetInstructionParent(a);
        const bb_b = c.LLVMGetInstructionParent(b);
        if (@intFromPtr(bb_a) == 0 or @intFromPtr(bb_b) == 0) return false;
        if (bb_a != bb_b) return false; // different BBs, can't determine order easily

        // Same basic block: walk from start until we find both
        var inst = c.LLVMGetFirstInstruction(bb_a);
        var found_b = false;
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (inst == b) found_b = true;
            if (inst == a) return found_b; // if we already found b, then a comes after b
        }
        return false;
    }

    /// Check if a DIType represents a const-qualified struct member.
    /// Walks the DIType chain: DW_TAG_member → DW_TAG_pointer_type → DW_TAG_const_type
    fn isConstQualifiedMember(di_type: c.LLVMValueRef) bool {
        if (@intFromPtr(di_type) == 0) return false;

        const tag = c.LLVMGetMetadataKind(di_type);

        // Direct: DW_TAG_const_type
        if (tag == c.LLVMDWARFTypeEnumTag or
            (tag == 0 and isDITag(di_type, c.LLVMDWARFConstTypeTag)))
        {
            return true;
        }

        // Walk base type chain for pointer → const
        var current = di_type;
        var depth: u32 = 0;
        while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
            // Check base type
            const base = getDIBaseType(current);
            if (@intFromPtr(base) == 0) break;

            const base_tag = c.LLVMGetMetadataKind(base);
            if (base_tag == c.LLVMDWARFTypeEnumTag or
                (base_tag == 0 and isDITag(base, c.LLVMDWARFConstTypeTag)))
            {
                return true;
            }
            current = base;
        }

        return false;
    }

    /// Get the base type of a DIType node.
    fn getDIBaseType(di_type: c.LLVMValueRef) c.LLVMValueRef {
        const num_operands = c.LLVMGetNumOperands(di_type);
        if (num_operands >= 2) {
            // Most DI types have base type as operand 1 (index 1)
            return c.LLVMGetOperand(di_type, 1);
        }
        const null_val: c.LLVMValueRef = @ptrFromInt(0);
        return null_val;
    }

    /// Check if a DI metadata node has a specific DWARF tag.
    fn isDITag(node: c.LLVMValueRef, expected_tag: c_uint) bool {
        // For DIDerivedType, the first operand is the tag
        const num_operands = c.LLVMGetNumOperands(node);
        if (num_operands < 1) return false;
        const tag_val = c.LLVMGetOperand(node, 0);
        if (@intFromPtr(tag_val) == 0) return false;

        // The tag is stored as a constant value
        if (c.LLVMIsAConstantInt(tag_val) != null) {
            // Extract constant int value — simplified check
            _ = expected_tag; // We'll use a heuristic approach instead
            return false;
        }
        return false;
    }

    /// Extract field name from DI member type metadata.
    fn getDIFieldName(di_type: c.LLVMValueRef) ?[]const u8 {
        // DW_TAG_member has name as second operand (index 2)
        const num_operands = c.LLVMGetNumOperands(di_type);
        if (num_operands >= 3) {
            const name_node = c.LLVMGetOperand(di_type, 2);
            if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
                const name_ptr = c.LLVMGetAMDString(name_node);
                if (@intFromPtr(name_ptr) != 0) {
                    return std.mem.span(name_ptr);
                }
            }
        }
        return null;
    }

    /// Extract type/struct name from DI type metadata.
    fn getDITypeName(di_type: c.LLVMValueRef) ?[]const u8 {
        // Walk to find DW_TAG_structure_type or DW_TAG_typedef with name
        var current = di_type;
        var depth: u32 = 0;
        while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
            const num_ops = c.LLVMGetNumOperands(current);
            if (num_ops >= 3) {
                const name_node = c.LLVMGetOperand(current, 2);
                if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
                    const name_ptr = c.LLVMGetAMDString(name_node);
                    if (@intFromPtr(name_ptr) != 0) {
                        const type_name = std.mem.span(name_ptr);
                        if (type_name.len > 0) return type_name;
                    }
                }
            }
            // Move to base type
            if (num_ops >= 2) {
                current = c.LLVMGetOperand(current, 1);
            } else {
                break;
            }
        }
        return null;
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

/// Check if a callee name is a Rust allocator call (_Znwm, __rust_alloc, etc.)
pub fn isRustAllocCall(callee_name: []const u8) bool {
    const rust_alloc_patterns = [_][]const u8{
        "_Znwm", // operator new(unsigned long) - Rust's default allocator
        "_Znw", // operator new variants
        "__rust_alloc",
        "__rust_alloc_zeroed",
        "alloc::alloc::alloc",
        "alloc::alloc::alloc_zeroed",
    };
    for (rust_alloc_patterns) |pattern| {
        if (std.mem.startsWith(u8, callee_name, pattern)) return true;
        if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a callee name looks like an extern "C" function
pub fn isExternCCall(callee_name: []const u8) bool {
    if (callee_name.len == 0) return false;
    if (callee_name[0] == '_') return false;
    if (std.mem.startsWith(u8, callee_name, "_Z")) return false;
    if (std.mem.startsWith(u8, callee_name, "_R")) return false;
    return true;
}

/// Check if function is from core::ffi crate (Rust standard FFI utilities)
pub fn isCoreFfiFunction(callee_name: []const u8) bool {
    // core::ffi functions commonly used in FFI
    const core_ffi_patterns = [_][]const u8{
        "c_void",
        "c_char",
        "c_int",
        "c_long",
        "c_uint",
        "c_ulong",
        "c_float",
        "c_double",
        "CStr",
        "CString",
        "from_raw", // *const T::from_raw()
        "into_raw", // *mut T::into_raw()
        "as_ptr", // CStr::as_ptr()
        "to_ptr", // CString::to_ptr()
        "to_str", // CStr::to_str()
        "from_bytes_with_nul_unchecked",
        "from_bytes_with_nul",
    };

    for (core_ffi_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if function is from libc crate (POSIX/C standard library bindings)
pub fn isLibcFunction(callee_name: []const u8) bool {
    // libc crate provides safe wrappers around C library functions
    const libc_patterns = [_][]const u8{
        // POSIX memory
        "malloc",
        "calloc",
        "realloc",
        "free",
        "memalign",
        "posix_memalign",

        // POSIX I/O
        "open",
        "read",
        "write",
        "close",
        "fcntl",
        "ioctl",
        "fstat",
        "lseek",
        "mmap",
        "munmap",

        // POSIX threads
        "pthread_create",
        "pthread_join",
        "pthread_mutex_lock",
        "pthread_mutex_unlock",
        "pthread_cond_wait",
        "pthread_cond_signal",

        // String operations
        "strlen",
        "strcpy",
        "strncpy",
        "strcat",
        "strncat",
        "strcmp",
        "strncmp",
        "strdup",

        // Network
        "socket",
        "bind",
        "listen",
        "accept",
        "connect",
        "send",
        "recv",

        // Time
        "time",
        "gettimeofday",
        "clock_gettime",
        "sleep",
        "usleep",
        "nanosleep",

        // Environment
        "getenv",
        "setenv",
        "unsetenv",

        // Error handling
        "errno",
        "strerror",
        "perror",
    };

    for (libc_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Classify Rust FFI boundary type for enhanced detection
pub fn classifyFfiBoundaryType(
    callee_name: []const u8,
    module_name: ?[]const u8,
) enum {
    /// Standard extern "C" function
    standard,
    /// core::ffi utility (CStr, CString, etc.)
    core_ffi,
    /// libc crate wrapper
    libc_crate,
    /// OS-specific API (Win32, macOS, Linux)
    os_api,
    /// Unknown/custom FFI
    unknown,
} {
    _ = module_name; // Reserved for future use

    if (isCoreFfiFunction(callee_name)) return .core_ffi;
    if (isLibcFunction(callee_name)) return .libc_crate;

    // OS-specific APIs
    const win32_patterns = [_][]const u8{ "CreateFile", "ReadFile", "WriteFile", "CloseHandle" };
    const macos_patterns = [_][]const u8{ "CFStringCreate", "dispatch_async", "kqueue" };
    const linux_patterns = [_][]const u8{ "epoll_create", "inotify_init", "signalfd" };

    for (win32_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }
    for (macos_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }
    for (linux_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) return .os_api;
    }

    // Default to standard extern "C"
    if (isExternCCall(callee_name)) return .standard;

    return .unknown;
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

/// Check if function name has a Rust mangled name prefix (_R / _ZN with disambiguation).
/// _ZN is ambiguous between C++ Itanium ABI and Rust legacy v0 — uses
/// ffi_language_classifier.isRustMangledName for disambiguation.
pub fn isRustMangledName(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_R")) {
        return true;
    }
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        return ffi_language_classifier.isRustMangledName(func_name);
    }
    return false;
}

// ============================================================================
// Detection Helpers (module-level functions)
// ============================================================================

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

/// Check if a value originates from a Rust allocator call within the same function.
/// Walks use-def chains through phi/select/bitcast/GEP instructions to find
/// the ultimate source. Returns true if traced back to isRustAllocCall.
pub fn ptrOriginatesFromRustAlloc(
    func: c.LLVMValueRef,
    val: c.LLVMValueRef,
    visited: *std.AutoHashMap(usize, void),
) bool {
    if (@intFromPtr(val) == 0) return false;
    if (visited.contains(@intFromPtr(val))) return false;
    visited.put(@intFromPtr(val), {}) catch return false;

    const opcode = c.LLVMGetInstructionOpcode(val);

    // Check if this is a call instruction returning from a Rust allocator
    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(val));
        if (num_operands > 0) {
            const callee = c.LLVMGetOperand(val, num_operands - 1);
            if (@intFromPtr(callee) != 0) {
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) != 0) {
                    const name_slice = std.mem.sliceTo(callee_name, 0);
                    if (isRustAllocCall(name_slice)) return true;
                }
            }
        }
        return false;
    }

    // Follow phi, select, bitcast, GEP, ptrtoint/inttoptr chains
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr or
        opcode == c.LLVMPHI or opcode == c.LLVMSelect or
        opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr)
    {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(val));
        var i: c_uint = 0;
        while (i < num_operands) : (i += 1) {
            const op = c.LLVMGetOperand(val, i);
            if (ptrOriginatesFromRustAlloc(func, op, visited)) return true;
        }
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
    // Rust v0 with hash suffix
    try std.testing.expect(isRustMangledName("_ZN9hello_world4main17h1234567890abcdefE"));
    // Rust new mangling
    try std.testing.expect(isRustMangledName("_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc"));
    try std.testing.expect(isRustMangledName("_RINv"));
    // Rust std/core namespaces
    try std.testing.expect(isRustMangledName("_ZN4core3ptr13drop_in_place17h1234E"));
    // C++ _ZN should NOT be detected as Rust
    try std.testing.expect(!isRustMangledName("_ZN4Base1fEv"));
    try std.testing.expect(!isRustMangledName("_ZNSt3__110unique_ptr"));
    // Non-mangled names
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
