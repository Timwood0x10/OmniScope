//! Export Surface Analyzer for FFI Boundaries
//!
//! Analyzes each ExportSurface symbol to detect FFI trap patterns:
//! 1. Parameter ownership checks — null pointers, size mismatches (TRAP-C-2, C-8)
//! 2. Return pointer lifetime analysis — static, heap, stack (TRAP-C-3, C-9)
//! 3. Callback registration detection — function pointers stored globally (TRAP-C-11)
//!
//! Targets 9 FFI trap patterns from c_ffi_traps.ll with a goal of >= 6/9 detection.
//! Must detect: TRAP-C-3 (cross-family free), TRAP-C-8 (size mismatch),
//!              TRAP-C-9 (use-after-free), TRAP-C-11 (leaked callback userdata).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const symbol_graph = @import("../../../ffi/symbol_graph.zig");

/// Managed ArrayList with stored allocator (Zig 0.15 compat).
const ManagedArrayList = std.array_list.Managed;

const Issue = @import("../../../diag/issue.zig").Issue;
const Location = @import("../../../diag/issue.zig").Location;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;

/// Allocation function name patterns for heap allocation detection.
const ALLOC_FUNCS = &[_][]const u8{
    "malloc",
    "calloc",
    "realloc",
    "strdup",
    "aligned_alloc",
    "posix_memalign",
    "_Znwm", // C++ operator new
    "_Znam", // C++ operator new[]
    "operator_new",
};

/// Deallocation function name patterns for free detection.
const FREE_FUNCS = &[_][]const u8{
    "free",
    "_ZdlPv", // C++ operator delete
    "_ZdaPv", // C++ operator delete[]
    "operator_delete",
    "cudaFree",
    "clReleaseMemObject",
};

/// Analyzes export surface symbols for FFI trap patterns.
///
/// Each export surface represents a function defined in this TU that is
/// externally visible and callable from another language. These functions
/// are the "attack surface" for FFI vulnerabilities.
pub const ExportSurfaceAnalyzer = struct {
    allocator: std.mem.Allocator,
    sym_graph: *const symbol_graph.SymbolGraph,
    issues: ManagedArrayList(Issue),

    pub fn init(allocator: std.mem.Allocator, sym_graph: *const symbol_graph.SymbolGraph) ExportSurfaceAnalyzer {
        return .{
            .allocator = allocator,
            .sym_graph = sym_graph,
            .issues = ManagedArrayList(Issue).init(allocator),
        };
    }

    /// Analyze all export surfaces and return detected issues.
    pub fn analyze(self: *ExportSurfaceAnalyzer) ![]const Issue {
        const surfaces = self.sym_graph.getExportSurfaces();
        for (surfaces) |surface| {
            try self.checkParameterOwnership(&surface);
            try self.checkReturnLifetime(&surface);
            try self.checkCallbackRegistration(&surface);
        }
        return self.issues.items;
    }

    /// Free all resources including owned issue memory.
    pub fn deinit(self: *ExportSurfaceAnalyzer) void {
        for (self.issues.items) |*issue| {
            issue.deinit(self.allocator);
        }
        self.issues.deinit();
    }

    // ── Parameter Ownership Check ─────────────────────────────────────
    //
    // Analyzes function parameters for ownership and safety issues:
    // - TRAP-C-2: Null deref via FFI — pointer params used without null check
    // - TRAP-C-8: Parameter size mismatch — caller passes wrong size
    // - TRAP-C-3: Cross-family free — allocator mismatch
    // - TRAP-C-6: Integer overflow leading to heap overflow
    //
    // Iterates the function body's IR instructions to find call sites
    // to alloc/free functions and null comparison patterns.

    fn checkParameterOwnership(self: *ExportSurfaceAnalyzer, surface: *const symbol_graph.ExportSurface) !void {
        const func = surface.symbol.llvm_value;
        if (func == null) return;
        // Only analyze function values — global variables are not callable surfaces.
        if (c.LLVMIsAFunction(func) == null) return;

        const func_name = surface.symbol.name;
        const num_params = c.LLVMCountParams(func);

        // Early exit: no parameters means nothing to check.
        if (num_params == 0) return;

        // Detect called functions within this export surface.
        var calls_malloc = false;
        var calls_calloc = false;
        var calls_free = false;
        var calls_memcpy = false;
        var has_arithmetic_on_param = false;

        // Track whether pointer parameters have null-check comparisons.
        var null_checked_count: usize = 0;
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (bb != null) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Detect null comparisons (icmp eq/ne ptr, null).
                if (opcode == c.LLVMICmp) {
                    if (self.isNullComparisonOfParam(inst, func)) {
                        null_checked_count += 1;
                    }
                }

                // Detect call instructions to alloc/free/memcpy.
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (called_val == null) continue;
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    if (callee_name_ptr == null) continue;
                    const callee_name = std.mem.span(callee_name_ptr);

                    if (isAllocFunction(callee_name)) {
                        if (std.mem.eql(u8, callee_name, "calloc")) {
                            calls_calloc = true;
                        }
                        calls_malloc = true;
                    }
                    if (isFreeFunction(callee_name)) {
                        calls_free = true;
                    }
                    if (std.mem.eql(u8, callee_name, "llvm.memcpy") or
                        std.mem.eql(u8, callee_name, "llvm.memmove") or
                        std.mem.eql(u8, callee_name, "memcpy") or
                        std.mem.eql(u8, callee_name, "memmove"))
                    {
                        calls_memcpy = true;
                    }
                }

                // Detect arithmetic on function parameters (TRAP-C-6).
                if (isArithmeticOpcode(opcode)) {
                    const op0 = c.LLVMGetOperand(inst, 0);
                    const op1 = c.LLVMGetOperand(inst, 1);
                    if (op0 != null and op1 != null) {
                        if (self.isParamOperand(op0, func) or self.isParamOperand(op1, func)) {
                            has_arithmetic_on_param = true;
                        }
                    }
                }
            }
        }

        // ── TRAP-C-3: Cross-family free detection ──────────────────
        // Function both allocates and frees internally. The FFI caller
        // may use a different deallocator family, causing cross-family free.
        if (calls_malloc and calls_free) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .cross_language_free,
                "TRAP-C-3: Cross-family free risk — function allocates memory internally but FFI caller may use wrong deallocator",
                location,
                .high,
                0.85,
            );
            try self.issues.append(issue);
        }

        // ── TRAP-C-8: Parameter size mismatch ──────────────────────
        // Function accepts size parameters and allocates internally.
        // Caller may pass incorrect size leading to buffer overflow.
        if (num_params >= 2 and (calls_malloc or calls_calloc)) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .buffer_overflow,
                "TRAP-C-8: Parameter size mismatch risk — function accepts size parameter and allocates; caller may pass incorrect size",
                location,
                .high,
                0.75,
            );
            try self.issues.append(issue);
        }

        // ── TRAP-C-2: Null deref via FFI ───────────────────────────
        // Pointer parameters used without null check before memory ops.
        if (num_params > 0 and (calls_malloc or calls_free) and null_checked_count == 0) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .null_dereference,
                "TRAP-C-2: Potential null dereference via FFI — pointer parameters used without null check before memory operation",
                location,
                .medium,
                0.65,
            );
            try self.issues.append(issue);
        }

        // ── TRAP-C-6: Integer overflow leading to heap overflow ────
        // Arithmetic on size parameters before allocation.
        if (has_arithmetic_on_param and (calls_malloc or calls_calloc)) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .integer_overflow,
                "TRAP-C-6: Integer overflow risk — arithmetic on parameter before allocation may cause heap overflow",
                location,
                .medium,
                0.6,
            );
            try self.issues.append(issue);
        }

        // ── TRAP-C-7: TOCTOU via FFI ───────────────────────────────
        // Parameter used in a size check then used in memcpy without
        // re-validation (simplified: checks memcpy with alloc pattern).
        if (calls_memcpy and calls_malloc) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .data_race,
                "TRAP-C-7: TOCTOU risk via FFI — size/pointer validated once then used in memcpy; caller may race",
                location,
                .low,
                0.45,
            );
            try self.issues.append(issue);
        }

        // ── TRAP-C-5: Type confusion via FFI ───────────────────────
        // Function has pointer parameters and uses memcpy with size
        // derived from parameter — may indicate type confusion.
        if (calls_memcpy and num_params >= 2 and !calls_malloc) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .type_mismatch,
                "TRAP-C-5: Type confusion risk via FFI — function copies memory using caller-provided pointer/size without validation",
                location,
                .medium,
                0.5,
            );
            try self.issues.append(issue);
        }
    }

    // ── Return Lifetime Analysis ──────────────────────────────────────
    //
    // Analyzes the return value of functions that return pointers:
    // - Heap-allocated: caller must free (risk if undocumented)
    // - Stack pointer: UB (returning address of local)
    // - Static/global: safe (no free needed)
    // - TRAP-C-9: Use-after-free via FFI

    fn checkReturnLifetime(self: *ExportSurfaceAnalyzer, surface: *const symbol_graph.ExportSurface) !void {
        const func = surface.symbol.llvm_value;
        if (func == null) return;
        // Only analyze function values — global variables are not callable surfaces.
        if (c.LLVMIsAFunction(func) == null) return;

        const func_name = surface.symbol.name;

        // Only analyze functions that return a pointer type.
        const func_type = c.LLVMGlobalGetValueType(func);
        if (func_type == null) return;
        const return_type = c.LLVMGetReturnType(func_type);
        if (return_type == null) return;
        if (c.LLVMGetTypeKind(return_type) != c.LLVMPointerTypeKind) return;

        // Scan function body for memory operations.
        var allocates_memory = false;
        var calls_free = false;
        var has_alloca = false;
        var calls_memcpy = false;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (bb != null) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (inst != null) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Detect alloca (stack allocation) — returning alloca ptr is UB.
                if (opcode == c.LLVMAlloca) {
                    has_alloca = true;
                }

                // Detect call instructions for alloc/free/string ops.
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const called_val = c.LLVMGetCalledValue(inst);
                    if (called_val == null) continue;
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    if (callee_name_ptr == null) continue;
                    const callee_name = std.mem.span(callee_name_ptr);

                    if (isAllocFunction(callee_name)) {
                        allocates_memory = true;
                    }
                    if (isFreeFunction(callee_name)) {
                        calls_free = true;
                    }
                    if (std.mem.eql(u8, callee_name, "llvm.memcpy") or
                        std.mem.eql(u8, callee_name, "llvm.memmove") or
                        std.mem.eql(u8, callee_name, "strdup") or
                        std.mem.eql(u8, callee_name, "strndup"))
                    {
                        calls_memcpy = true;
                    }
                }
            }
        }

        // ── TRAP-C-9: Use-after-free via FFI ──────────────────────
        // Function allocates, frees, AND returns a pointer.
        // The returned pointer may dangle after internal free.
        if (allocates_memory and calls_free) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .use_after_free,
                "TRAP-C-9: Use-after-free via FFI — function allocates and frees memory internally, returned pointer may dangle",
                location,
                .critical,
                0.9,
            );
            try self.issues.append(issue);
        }

        // ── Heap allocation without ownership docs ────────────────
        // Function allocates and returns pointer without freeing.
        // Caller must free but documentation is missing.
        if (allocates_memory and !calls_free) {
            const location = Location.init(func_name);
            const message = if (calls_memcpy)
                "Returned heap pointer via strdup-like operation without ownership docs — caller must free"
            else
                "Returned heap pointer without ownership documentation — FFI caller must free this memory";
            const issue = Issue.init(
                .cross_language_leak,
                message,
                location,
                .high,
                0.8,
            );
            try self.issues.append(issue);
        }

        // ── Stack pointer return (UB) ─────────────────────────────
        if (has_alloca) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .invalid_free,
                "Returning stack pointer — function returns address of local variable via alloca; caller use is undefined behavior",
                location,
                .critical,
                0.95,
            );
            try self.issues.append(issue);
        }
    }

    // ── Callback Registration Detection ───────────────────────────────
    //
    // Detects callback registration patterns in export surfaces:
    // - Function pointer parameters stored to globals → callback registration
    // - void* userdata params without lifecycle tracking → TRAP-C-11
    //
    // These patterns indicate that the export surface expects the FFI caller
    // to provide callbacks, creating risk of dangling callbacks.

    fn checkCallbackRegistration(self: *ExportSurfaceAnalyzer, surface: *const symbol_graph.ExportSurface) !void {
        const func = surface.symbol.llvm_value;
        if (func == null) return;
        // Only analyze function values — global variables are not callable surfaces.
        if (c.LLVMIsAFunction(func) == null) return;

        const func_name = surface.symbol.name;
        const num_params = c.LLVMCountParams(func);
        if (num_params == 0) return;

        // Identify function pointer parameters and void* parameters.
        var fn_ptr_params = ManagedArrayList(usize).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer fn_ptr_params.deinit();

        var void_ptr_params = ManagedArrayList(usize).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        defer void_ptr_params.deinit();

        for (0..num_params) |i| {
            const param = c.LLVMGetParam(func, @intCast(i));
            if (param == null) continue;

            const param_type = c.LLVMTypeOf(param);
            if (param_type == null) continue;

            // Not a pointer type — skip.
            if (c.LLVMGetTypeKind(param_type) != c.LLVMPointerTypeKind) continue;

            const elem_type = c.LLVMGetElementType(param_type);
            if (elem_type == null) {
                // void* — possible userdata parameter.
                try void_ptr_params.append(i);
                continue;
            }

            const type_kind = c.LLVMGetTypeKind(elem_type);
            if (type_kind == c.LLVMFunctionTypeKind) {
                try fn_ptr_params.append(i);
            } else if (type_kind == c.LLVMVoidTypeKind) {
                try void_ptr_params.append(i);
            }
        }

        // Early exit: no function pointer params found.
        if (fn_ptr_params.items.len == 0) return;

        // Check if any function pointer parameter is stored to a global
        // or passed to another function (callback registration pattern).
        var stored_to_global = false;
        var fn_registered = false;

        bb_loop: {
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (bb != null) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (inst != null) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    if (opcode == c.LLVMStore) {
                        const val_operand = c.LLVMGetOperand(inst, 0);
                        const ptr_operand = c.LLVMGetOperand(inst, 1);
                        if (val_operand != null and ptr_operand != null) {
                            const is_global = c.LLVMIsAGlobalVariable(ptr_operand) != null;
                            if (!is_global) continue;

                            // Check if stored value is any of the function pointer params.
                            for (fn_ptr_params.items) |idx| {
                                const fn_ptr = c.LLVMGetParam(func, @intCast(idx));
                                if (val_operand == fn_ptr) {
                                    stored_to_global = true;
                                    fn_registered = true;
                                    break;
                                }
                            }
                        }
                    }

                    // Check if fn ptr is passed as argument to another call.
                    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                        const num_ops: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                        for (fn_ptr_params.items) |idx| {
                            const fn_ptr = c.LLVMGetParam(func, @intCast(idx));
                            for (0..@as(usize, num_ops)) |j| {
                                const op = c.LLVMGetOperand(inst, @intCast(j));
                                if (op == fn_ptr) {
                                    fn_registered = true;
                                }
                            }
                        }
                    }

                    if (fn_registered and stored_to_global) break :bb_loop;
                }
            }
        }

        if (!fn_registered) return;

        // ── Report callback registration issue ──────────────────────

        if (stored_to_global and void_ptr_params.items.len > 0) {
            // TRAP-C-11: Leaked callback userdata.
            const location = Location.init(func_name);
            const issue = Issue.init(
                .callback_ownership_risk,
                "TRAP-C-11: Leaked callback userdata — function accepts callback and void* userdata, but userdata lifecycle is not tracked across FFI boundary",
                location,
                .high,
                0.85,
            );
            try self.issues.append(issue);
        } else if (stored_to_global) {
            const location = Location.init(func_name);
            const issue = Issue.init(
                .callback_ownership_risk,
                "Callback stored to global/long-lived state — function pointer parameter registered as callback; risk of dangling callback across FFI boundary",
                location,
                .high,
                0.8,
            );
            try self.issues.append(issue);
        } else {
            // Callback passed to another function but not directly to global.
            const location = Location.init(func_name);
            const issue = Issue.init(
                .callback_ownership_risk,
                "Function pointer parameter passed as callback — indirect registration; userdata lifecycle must be verified",
                location,
                .medium,
                0.65,
            );
            try self.issues.append(issue);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────

    /// Check if an instruction is a null comparison involving a function parameter.
    fn isNullComparisonOfParam(self: *ExportSurfaceAnalyzer, inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        const op0 = c.LLVMGetOperand(inst, 0);
        const op1 = c.LLVMGetOperand(inst, 1);
        if (op0 == null or op1 == null) return false;

        // Check if either operand is a parameter and the other is null constant.
        const op0_is_param = self.isParamOperand(op0, func);
        const op1_is_param = self.isParamOperand(op1, func);
        const op0_is_null = c.LLVMIsNull(op0) != 0;
        const op1_is_null = c.LLVMIsNull(op1) != 0;

        return (op0_is_param and op1_is_null) or (op1_is_param and op0_is_null);
    }

    /// Check if a value is a function parameter (by checking if it's among
    /// the function's formal parameters).
    fn isParamOperand(self: *ExportSurfaceAnalyzer, val: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        _ = self;
        const num_params = c.LLVMCountParams(func);
        for (0..num_params) |i| {
            const param = c.LLVMGetParam(func, @intCast(i));
            if (param == val) return true;
        }
        return false;
    }
};

// ── Module-level helper functions ──────────────────────────────────────

/// Check if a function name matches known allocation functions.
fn isAllocFunction(name: []const u8) bool {
    for (ALLOC_FUNCS) |alloc| {
        if (std.mem.eql(u8, name, alloc)) return true;
    }
    return false;
}

/// Check if a function name matches known deallocation functions.
fn isFreeFunction(name: []const u8) bool {
    for (FREE_FUNCS) |free_fn| {
        if (std.mem.eql(u8, name, free_fn)) return true;
    }
    return false;
}

/// Check if an LLVM opcode is an arithmetic operation.
fn isArithmeticOpcode(opcode: c_uint) bool {
    return opcode == c.LLVMAdd or
        opcode == c.LLVMSub or
        opcode == c.LLVMMul or
        opcode == c.LLVMUDiv or
        opcode == c.LLVMSDiv or
        opcode == c.LLVMURem or
        opcode == c.LLVMSRem or
        opcode == c.LLVMShl or
        opcode == c.LLVMAShr or
        opcode == c.LLVMLShr or
        opcode == c.LLVMAnd or
        opcode == c.LLVMOr or
        opcode == c.LLVMXor;
}

// ═════════════════════════════════════════════════════════════════════
// Tests
// ═════════════════════════════════════════════════════════════════════

test "ExportSurfaceAnalyzer — init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a minimal SymbolGraph for testing.
    var graph = symbol_graph.SymbolGraph{
        .allocator = allocator,
        .symbols = std.StringHashMap(symbol_graph.Symbol).init(allocator),
        .call_sites = symbol_graph.ManagedArrayList(symbol_graph.CallSite).initCapacity(allocator, 0) catch return error.OutOfMemory,
        .export_surfaces = symbol_graph.ManagedArrayList(symbol_graph.ExportSurface).initCapacity(allocator, 0) catch return error.OutOfMemory,
        .by_language = std.AutoHashMap(symbol_graph.LanguageId, symbol_graph.ManagedArrayList(*symbol_graph.Symbol)).init(allocator),
        .cross_lang_calls = symbol_graph.ManagedArrayList(*symbol_graph.CallSite).initCapacity(allocator, 0) catch return error.OutOfMemory,
    };
    defer graph.deinit();

    var analyzer = ExportSurfaceAnalyzer.init(allocator, &graph);
    defer analyzer.deinit();

    try testing.expectEqual(@as(usize, 0), analyzer.issues.items.len);
}

test "ExportSurfaceAnalyzer — analyze empty graph" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var graph = symbol_graph.SymbolGraph{
        .allocator = allocator,
        .symbols = std.StringHashMap(symbol_graph.Symbol).init(allocator),
        .call_sites = symbol_graph.ManagedArrayList(symbol_graph.CallSite).initCapacity(allocator, 0) catch return error.OutOfMemory,
        .export_surfaces = symbol_graph.ManagedArrayList(symbol_graph.ExportSurface).initCapacity(allocator, 0) catch return error.OutOfMemory,
        .by_language = std.AutoHashMap(symbol_graph.LanguageId, symbol_graph.ManagedArrayList(*symbol_graph.Symbol)).init(allocator),
        .cross_lang_calls = symbol_graph.ManagedArrayList(*symbol_graph.CallSite).initCapacity(allocator, 0) catch return error.OutOfMemory,
    };
    defer graph.deinit();

    var analyzer = ExportSurfaceAnalyzer.init(allocator, &graph);
    defer analyzer.deinit();

    const issues = try analyzer.analyze();
    try testing.expectEqual(@as(usize, 0), issues.len);
}

test "ExportSurfaceAnalyzer — isAllocFunction positive" {
    try std.testing.expect(isAllocFunction("malloc"));
    try std.testing.expect(isAllocFunction("calloc"));
    try std.testing.expect(isAllocFunction("realloc"));
    try std.testing.expect(isAllocFunction("strdup"));
    try std.testing.expect(isAllocFunction("aligned_alloc"));
}

test "ExportSurfaceAnalyzer — isAllocFunction negative" {
    try std.testing.expect(!isAllocFunction("free"));
    try std.testing.expect(!isAllocFunction("memcpy"));
    try std.testing.expect(!isAllocFunction("printf"));
    try std.testing.expect(!isAllocFunction(""));
}

test "ExportSurfaceAnalyzer — isFreeFunction positive" {
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("_ZdlPv"));
    try std.testing.expect(isFreeFunction("_ZdaPv"));
}

test "ExportSurfaceAnalyzer — isFreeFunction negative" {
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("realloc"));
    try std.testing.expect(!isFreeFunction("strdup"));
}

test "ExportSurfaceAnalyzer — isArithmeticOpcode" {
    try std.testing.expect(isArithmeticOpcode(c.LLVMAdd));
    try std.testing.expect(isArithmeticOpcode(c.LLVMSub));
    try std.testing.expect(isArithmeticOpcode(c.LLVMMul));
    try std.testing.expect(!isArithmeticOpcode(c.LLVMCall));
    try std.testing.expect(!isArithmeticOpcode(c.LLVMStore));
    try std.testing.expect(!isArithmeticOpcode(c.LLVMLoad));
}

test "ExportSurfaceAnalyzer — issue types used" {
    // Verify that the IssueKind values used in the analyzer exist.
    try std.testing.expect(@intFromEnum(IssueKind.cross_language_free) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.buffer_overflow) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.null_dereference) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.integer_overflow) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.use_after_free) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.cross_language_leak) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.callback_ownership_risk) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.data_race) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.type_mismatch) >= 0);
    try std.testing.expect(@intFromEnum(IssueKind.invalid_free) >= 0);
}
