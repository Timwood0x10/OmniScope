//! ABI Compatibility Checker
//!
//! Detects ABI (Application Binary Interface) incompatibilities across FFI boundaries.
//! Unlike FFITypeMismatch which focuses on runtime type mismatches, this module
//! checks for structural incompatibilities in function declarations:
//!   - Parameter count mismatches
//!   - Calling convention mismatches (cdecl vs stdcall vs fastcall)
//!   - Return type mismatches
//!   - Struct layout mismatches (padding, alignment)
//!   - Parameter type width mismatches
//!
//! ABI incompatibilities cause silent data corruption, stack corruption,
//! or crashes at runtime - making them critical to detect at analysis time.

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

const ffi_boundary = @import("ffi_boundary.zig");
const ffi_type_mismatch = @import("ffi_type_mismatch.zig");

/// Types of ABI incompatibilities detected.
pub const AbiMismatchKind = enum(u8) {
    /// Parameter count mismatch between caller and callee
    param_count_mismatch,
    /// Return type mismatch (void vs non-void, different widths)
    return_type_mismatch,
    /// Calling convention mismatch (cdecl vs stdcall vs fastcall)
    calling_convention_mismatch,
    /// Parameter type width mismatch (e.g., i32 vs i64 at same position)
    param_type_mismatch,
    /// Struct layout mismatch (padding/alignment differences)
    struct_layout_mismatch,
    /// Varargs mismatch (caller passes varargs but callee doesn't expect them)
    varargs_mismatch,
    /// Enum size mismatch (different sizes across languages)
    enum_size_mismatch,
    /// Function pointer signature mismatch
    function_pointer_mismatch,
    /// Struct field type mismatch
    struct_field_mismatch,
    /// Struct size mismatch
    struct_size_mismatch,
    /// Struct alignment mismatch
    struct_alignment_mismatch,
};

/// Information about a detected ABI incompatibility.
pub const AbiMismatchInfo = struct {
    kind: AbiMismatchKind,
    caller_name: []const u8,
    callee_name: []const u8,
    caller_lang: []const u8,
    callee_lang: []const u8,
    param_index: ?u32,
    expected: []const u8,
    actual: []const u8,
    description: []const u8,
};

/// Statistics for ABI compatibility checking.
pub const AbiCompatStats = struct {
    functions_analyzed: u32 = 0,
    ffi_boundaries_found: u32 = 0,
    param_count_mismatches: u32 = 0,
    return_type_mismatches: u32 = 0,
    calling_convention_mismatches: u32 = 0,
    param_type_mismatches: u32 = 0,
    struct_layout_mismatches: u32 = 0,
    varargs_mismatches: u32 = 0,
    enum_size_mismatches: u32 = 0,
    function_pointer_mismatches: u32 = 0,
    struct_field_mismatches: u32 = 0,
    struct_size_mismatches: u32 = 0,
    struct_alignment_mismatches: u32 = 0,

    pub fn formatSummary(self: AbiCompatStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   ABI COMPATIBILITY CHECKER          ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:       {d:>8}     ║\n", .{self.functions_analyzed});
        try writer.print("║  FFI boundaries:           {d:>8}     ║\n", .{self.ffi_boundaries_found});
        try writer.print("║  Param count mismatches:   {d:>8}     ║\n", .{self.param_count_mismatches});
        try writer.print("║  Return type mismatches:   {d:>8}     ║\n", .{self.return_type_mismatches});
        try writer.print("║  Calling convention:       {d:>8}     ║\n", .{self.calling_convention_mismatches});
        try writer.print("║  Param type mismatches:    {d:>8}     ║\n", .{self.param_type_mismatches});
        try writer.print("║  Struct layout mismatches: {d:>8}     ║\n", .{self.struct_layout_mismatches});
        try writer.print("║  Varargs mismatches:       {d:>8}     ║\n", .{self.varargs_mismatches});
        try writer.print("║  Enum size mismatches:     {d:>8}     ║\n", .{self.enum_size_mismatches});
        try writer.print("║  Func ptr mismatches:      {d:>8}     ║\n", .{self.function_pointer_mismatches});
        try writer.print("║  Struct field mismatches:  {d:>8}     ║\n", .{self.struct_field_mismatches});
        try writer.print("║  Struct size mismatches:   {d:>8}     ║\n", .{self.struct_size_mismatches});
        try writer.print("║  Struct align mismatches:  {d:>8}     ║\n", .{self.struct_alignment_mismatches});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

/// Main ABI compatibility checker pass.
pub const AbiCompatChecker = struct {
    pub const name = "abi-compat-checker";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "call-graph", "ffi-boundary" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var stats = AbiCompatStats{};

        // First pass: collect all function declarations and definitions
        var func_decls = std.StringHashMap(FunctionSignature).init(ctx.allocator);
        defer {
            var iter = func_decls.iterator();
            while (iter.next()) |entry| {
                ctx.allocator.free(entry.key_ptr.*);
                if (entry.value_ptr.param_types) |params| {
                    ctx.allocator.free(params);
                }
            }
            func_decls.deinit();
        }

        // Collect function signatures from the module
        var func = c.LLVMGetFirstFunction(ctx.module.?.raw);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ref = c.LLVMIsAFunction(func);
            if (@intFromPtr(func_ref) == 0) continue;

            try collectFunctionSignature(ctx, func_ref, &func_decls, &stats);
        }

        // Second pass: analyze call sites for ABI mismatches
        func = c.LLVMGetFirstFunction(ctx.module.?.raw);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_ref = c.LLVMIsAFunction(func);
            if (@intFromPtr(func_ref) == 0) continue;

            analyzeFunction(ctx, func_ref, &func_decls, diag, &stats) catch |err| {
                diag.warn("AbiCompat: skipped function due to error: {}", .{err});
                continue;
            };
        }

        diag.info("AbiCompat: analyzed {} functions, found {} FFI boundaries, {} issues", .{
            stats.functions_analyzed,
            stats.ffi_boundaries_found,
            stats.param_count_mismatches + stats.return_type_mismatches +
                stats.calling_convention_mismatches + stats.param_type_mismatches +
                stats.struct_layout_mismatches + stats.varargs_mismatches,
        });
    }

    /// Collect function signature from LLVM IR.
    fn collectFunctionSignature(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_decls: *std.StringHashMap(FunctionSignature),
        _: *AbiCompatStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return;
        const func_name = std.mem.span(func_name_ptr);

        // Skip LLVM intrinsics
        if (std.mem.startsWith(u8, func_name, "llvm.")) return;

        // Get function type: LLVMTypeOf returns a pointer type, not the function type.
        // Must call LLVMGetElementType to get the underlying function type.
        const func_ptr_type = c.LLVMTypeOf(func);
        if (@intFromPtr(func_ptr_type) == 0) return;
        const func_type = c.LLVMGetElementType(func_ptr_type);
        if (@intFromPtr(func_type) == 0) return;
        if (c.LLVMGetTypeKind(func_type) != c.LLVMFunctionTypeKind) return;

        // Get parameter count
        const param_count = c.LLVMCountParamTypes(func_type);

        // Get return type
        const ret_type = c.LLVMGetReturnType(func_type);
        const ret_type_kind = c.LLVMGetTypeKind(ret_type);
        const ret_type_name = getTypeName(ret_type);

        // Get parameter types
        var param_types: ?[]const c.LLVMTypeRef = null;
        if (param_count > 0) {
            const params = try ctx.allocator.alloc(c.LLVMTypeRef, param_count);
            c.LLVMGetParamTypes(func_type, params.ptr);
            param_types = params;
        }

        // Check if function is varargs
        const is_varargs = c.LLVMIsFunctionVarArg(func_type) != 0;

        // Check if function is declaration only (no body)
        const is_declaration = c.LLVMIsDeclaration(func) != 0;

        const signature = FunctionSignature{
            .name = func_name,
            .param_count = param_count,
            .param_types = param_types,
            .ret_type = ret_type,
            .ret_type_kind = ret_type_kind,
            .ret_type_name = ret_type_name,
            .is_varargs = is_varargs,
            .is_declaration = is_declaration,
            .calling_convention = c.LLVMGetFunctionCallConv(func),
        };

        // Store signature (key is heap-allocated copy of func_name)
        const key = try ctx.allocator.dupe(u8, func_name);
        try func_decls.put(key, signature);
    }

    /// Analyze a function for ABI compatibility issues.
    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        func_decls: *std.StringHashMap(FunctionSignature),
        diag: *DiagnosticWriter,
        stats: *AbiCompatStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_ptr) == 0) return;
        const func_name = std.mem.span(func_name_ptr);

        stats.functions_analyzed += 1;

        // Skip LLVM intrinsics
        if (std.mem.startsWith(u8, func_name, "llvm.")) return;

        // Use noise filter to skip stdlib and compiler-generated code
        const classification = ctx.classifyFunctionSurface(func_name, null);
        if (!classification.origin.shouldReportByDefault()) {
            diag.debug("[SUPPRESSED] AbiCompat: {s} ({s})", .{ func_name, classification.reason });
            return;
        }

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (llvm_safe.isCallOrInvoke(opcode)) {
                    try analyzeCallSite(ctx, func_name, inst, func_decls, diag, stats);
                }
            }
        }
    }

    /// Analyze a call site for ABI compatibility issues.
    fn analyzeCallSite(
        ctx: *PassContext,
        caller_name: []const u8,
        call_inst: c.LLVMValueRef,
        func_decls: *std.StringHashMap(FunctionSignature),
        diag: *DiagnosticWriter,
        stats: *AbiCompatStats,
    ) !void {
        const called_val = c.LLVMGetCalledValue(call_inst);
        if (@intFromPtr(called_val) == 0) return;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return;
        const callee_name = std.mem.span(callee_name_ptr);

        // Check if this is an FFI boundary.
        // Three ways to detect: explicit cross-lang edge, mangling-based heuristic,
        // or callee is a declaration-only external symbol (defined in another TU/library).
        const callee_func_val = c.LLVMGetCalledValue(call_inst);
        const callee_is_declaration = if (@intFromPtr(callee_func_val) != 0)
            c.LLVMIsDeclaration(callee_func_val) != 0
        else
            false;
        const is_ffi = ctx.getCrossEdgeByCallee(callee_name) != null or
            ffi_type_mismatch.FFITypeMismatchPass.isFFIBoundary(caller_name, callee_name) or
            callee_is_declaration;
        if (!is_ffi) return;

        stats.ffi_boundaries_found += 1;

        // Get caller and callee signatures
        const caller_sig = func_decls.get(caller_name);
        const callee_sig = func_decls.get(callee_name);

        // If we have both signatures, perform full ABI check
        if (caller_sig != null and callee_sig != null) {
            try checkAbiCompatibility(ctx, caller_name, callee_name, caller_sig.?, callee_sig.?, call_inst, diag, stats);
        } else {
            // Fallback: check what we can from the call instruction itself
            try checkCallSiteAbi(ctx, caller_name, callee_name, call_inst, diag, stats);
        }
    }

    /// Check ABI compatibility between two function signatures.
    fn checkAbiCompatibility(
        ctx: *PassContext,
        caller_name: []const u8,
        callee_name: []const u8,
        caller_sig: FunctionSignature,
        callee_sig: FunctionSignature,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *AbiCompatStats,
    ) !void {
        // Check 1: Parameter count mismatch
        if (!callee_sig.is_varargs and caller_sig.param_count != callee_sig.param_count) {
            stats.param_count_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .param_count_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{callee_sig.param_count}),
                .actual = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{caller_sig.param_count}),
                .description = "Parameter count mismatch between caller and callee declarations",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }

        // Check 2: Return type mismatch
        if (caller_sig.ret_type_kind != callee_sig.ret_type_kind) {
            stats.return_type_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .return_type_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = callee_sig.ret_type_name,
                .actual = caller_sig.ret_type_name,
                .description = "Return type mismatch between caller and callee declarations",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }

        // Check 3: Calling convention mismatch
        if (caller_sig.calling_convention != callee_sig.calling_convention) {
            stats.calling_convention_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .calling_convention_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = getCallingConventionName(callee_sig.calling_convention),
                .actual = getCallingConventionName(caller_sig.calling_convention),
                .description = "Calling convention mismatch between caller and callee",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }

        // Check 4: Parameter type mismatches and function pointer compatibility
        if (caller_sig.param_types != null and callee_sig.param_types != null) {
            const min_params = @min(caller_sig.param_count, callee_sig.param_count);
            var i: u32 = 0;
            while (i < min_params) : (i += 1) {
                const caller_type = caller_sig.param_types.?[i];
                const callee_type = callee_sig.param_types.?[i];

                if (!areTypesCompatible(caller_type, callee_type)) {
                    stats.param_type_mismatches += 1;
                    const mismatch = AbiMismatchInfo{
                        .kind = .param_type_mismatch,
                        .caller_name = caller_name,
                        .callee_name = callee_name,
                        .caller_lang = "unknown",
                        .callee_lang = "unknown",
                        .param_index = i,
                        .expected = getTypeName(callee_type),
                        .actual = getTypeName(caller_type),
                        .description = "Parameter type mismatch at position",
                    };
                    reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
                }

                // Check function pointer compatibility
                if (isFunctionPointerType(caller_type) and isFunctionPointerType(callee_type)) {
                    if (!checkFunctionPointerCompatibility(caller_type, callee_type)) {
                        stats.function_pointer_mismatches += 1;
                        const mismatch = AbiMismatchInfo{
                            .kind = .function_pointer_mismatch,
                            .caller_name = caller_name,
                            .callee_name = callee_name,
                            .caller_lang = "unknown",
                            .callee_lang = "unknown",
                            .param_index = i,
                            .expected = "compatible function pointer",
                            .actual = "incompatible function pointer",
                            .description = "Function pointer signature mismatch at position",
                        };
                        reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
                    }
                }
            }
        }

        // Check 5: Varargs mismatch
        if (caller_sig.is_varargs != callee_sig.is_varargs) {
            stats.varargs_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .varargs_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = if (callee_sig.is_varargs) "varargs" else "fixed args",
                .actual = if (caller_sig.is_varargs) "varargs" else "fixed args",
                .description = "Varargs mismatch between caller and callee",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }
    }

    /// Check struct layout compatibility between two types.
    /// Returns true if layouts are compatible, false otherwise.
    pub fn checkStructLayoutCompatibility(type1: c.LLVMTypeRef, type2: c.LLVMTypeRef) bool {
        const kind1 = c.LLVMGetTypeKind(type1);
        const kind2 = c.LLVMGetTypeKind(type2);

        if (kind1 != c.LLVMStructTypeKind or kind2 != c.LLVMStructTypeKind) {
            return false;
        }

        const num_elements1 = c.LLVMCountStructElementTypes(type1);
        const num_elements2 = c.LLVMCountStructElementTypes(type2);

        if (num_elements1 != num_elements2) {
            return false;
        }

        if (c.LLVMIsPackedStruct(type1) != c.LLVMIsPackedStruct(type2)) {
            return false;
        }

        var i: u32 = 0;
        while (i < num_elements1) : (i += 1) {
            if (!areTypesCompatible(
                c.LLVMStructGetTypeAtIndex(type1, i),
                c.LLVMStructGetTypeAtIndex(type2, i),
            )) {
                return false;
            }
        }

        return true;
    }

    /// Detailed struct layout compatibility check result.
    pub const StructLayoutCheckResult = struct {
        /// Whether the layouts are compatible
        compatible: bool,
        /// Number of fields
        field_count: u32,
        /// Whether packed status matches
        packed_matches: bool,
        /// Indices of incompatible fields
        incompatible_fields: []u32,
        /// Whether the structs have different sizes (if known)
        size_mismatch: bool = false,
        /// Whether the structs have different alignment (if known)
        alignment_mismatch: bool = false,
    };

    /// Check struct layout compatibility with detailed results.
    /// Returns a StructLayoutCheckResult with detailed information about mismatches.
    pub fn checkStructLayoutCompatibilityDetailed(
        allocator: std.mem.Allocator,
        type1: c.LLVMTypeRef,
        type2: c.LLVMTypeRef,
    ) !StructLayoutCheckResult {
        const kind1 = c.LLVMGetTypeKind(type1);
        const kind2 = c.LLVMGetTypeKind(type2);

        if (kind1 != c.LLVMStructTypeKind or kind2 != c.LLVMStructTypeKind) {
            return StructLayoutCheckResult{
                .compatible = false,
                .field_count = 0,
                .packed_matches = false,
                .incompatible_fields = try allocator.alloc(u32, 0),
            };
        }

        const num_elements1 = c.LLVMCountStructElementTypes(type1);
        const num_elements2 = c.LLVMCountStructElementTypes(type2);

        if (num_elements1 != num_elements2) {
            return StructLayoutCheckResult{
                .compatible = false,
                .field_count = @max(num_elements1, num_elements2),
                .packed_matches = c.LLVMIsPackedStruct(type1) == c.LLVMIsPackedStruct(type2),
                .incompatible_fields = try allocator.alloc(u32, 0),
            };
        }

        const packed_matches = c.LLVMIsPackedStruct(type1) == c.LLVMIsPackedStruct(type2);

        var incompatible_fields = std.ArrayList(u32).init(allocator);
        defer incompatible_fields.deinit();

        var i: u32 = 0;
        while (i < num_elements1) : (i += 1) {
            const elem1 = c.LLVMStructGetTypeAtIndex(type1, i);
            const elem2 = c.LLVMStructGetTypeAtIndex(type2, i);
            if (!areTypesCompatible(elem1, elem2)) {
                try incompatible_fields.append(i);
            }
        }

        return StructLayoutCheckResult{
            .compatible = incompatible_fields.items.len == 0 and packed_matches,
            .field_count = num_elements1,
            .packed_matches = packed_matches,
            .incompatible_fields = try incompatible_fields.toOwnedSlice(),
        };
    }

    /// Check if a type is a function pointer type.
    fn isFunctionPointerType(type_ref: c.LLVMTypeRef) bool {
        return c.LLVMGetTypeKind(type_ref) == c.LLVMPointerTypeKind;
    }

    /// Check if two function pointer types are compatible.
    fn checkFunctionPointerCompatibility(type1: c.LLVMTypeRef, type2: c.LLVMTypeRef) bool {
        return c.LLVMGetTypeKind(type1) == c.LLVMPointerTypeKind and
            c.LLVMGetTypeKind(type2) == c.LLVMPointerTypeKind;
    }

    /// Check enum size compatibility between two types.
    /// Returns true if sizes are compatible, false otherwise.
    pub fn checkEnumSizeCompatibility(type1: c.LLVMTypeRef, type2: c.LLVMTypeRef) bool {
        const kind1 = c.LLVMGetTypeKind(type1);
        const kind2 = c.LLVMGetTypeKind(type2);

        if (kind1 == c.LLVMIntegerTypeKind and kind2 == c.LLVMIntegerTypeKind) {
            return c.LLVMGetIntTypeWidth(type1) == c.LLVMGetIntTypeWidth(type2);
        }

        if (kind1 == c.LLVMIntegerTypeKind or kind2 == c.LLVMIntegerTypeKind) {
            return false;
        }

        return areTypesCompatible(type1, type2);
    }

    /// Check ABI from call instruction when full signatures are not available.
    fn checkCallSiteAbi(
        ctx: *PassContext,
        caller_name: []const u8,
        callee_name: []const u8,
        call_inst: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *AbiCompatStats,
    ) !void {
        const num_args = c.LLVMGetNumArgOperands(call_inst);
        const called_val = c.LLVMGetCalledValue(call_inst);
        if (@intFromPtr(called_val) == 0) return;

        // Get callee's function type for parameter-level analysis
        const func_type = c.LLVMGetCalledFunctionType(call_inst);
        if (@intFromPtr(func_type) == 0) return; // Indirect call — skip

        const expected_params = c.LLVMCountParamTypes(func_type);
        const is_varargs = c.LLVMIsFunctionVarArg(func_type) != 0;

        // Check 1: Parameter count mismatch
        if (!is_varargs and num_args != expected_params) {
            stats.param_count_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .param_count_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{expected_params}),
                .actual = try std.fmt.allocPrint(ctx.allocator, "{d} arguments", .{num_args}),
                .description = "Argument count mismatch at call site",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }

        // Check 2: Extra arguments to non-varargs function
        if (!is_varargs and num_args > expected_params) {
            stats.varargs_mismatches += 1;
            const mismatch = AbiMismatchInfo{
                .kind = .varargs_mismatch,
                .caller_name = caller_name,
                .callee_name = callee_name,
                .caller_lang = "unknown",
                .callee_lang = "unknown",
                .param_index = null,
                .expected = "fixed args",
                .actual = try std.fmt.allocPrint(ctx.allocator, "{d} args (extra {d})", .{ num_args, num_args - expected_params }),
                .description = "Extra arguments passed to non-varargs function",
            };
            reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
        }

        // Check 3: Parameter type compatibility at FFI boundary (cross-language safety net).
        // Catches Zig u64→C u32 truncation, struct padding differences, pointer confusion.
        var param_types_buf: ?[]c.LLVMTypeRef = null;
        defer if (param_types_buf) |buf| ctx.allocator.free(buf);

        if (expected_params > 0) {
            param_types_buf = try ctx.allocator.alloc(c.LLVMTypeRef, expected_params);
            c.LLVMGetParamTypes(func_type, param_types_buf.?.ptr);
        }

        const check_limit = @min(num_args, expected_params);
        var idx: c_uint = 0;
        while (idx < check_limit) : (idx += 1) {
            const arg_val = c.LLVMGetOperand(call_inst, idx);
            if (@intFromPtr(arg_val) == 0) continue;

            const arg_llvm_type = c.LLVMTypeOf(arg_val);
            if (@intFromPtr(arg_llvm_type) == 0) continue;

            const param_type = if (param_types_buf) |buf| buf[idx] else continue;

            // Integer width mismatch: e.g., Zig i64 → C i32 (silent truncation)
            if (c.LLVMGetTypeKind(arg_llvm_type) == c.LLVMIntegerTypeKind and
                c.LLVMGetTypeKind(param_type) == c.LLVMIntegerTypeKind)
            {
                const arg_width = c.LLVMGetIntTypeWidth(arg_llvm_type);
                const param_width = c.LLVMGetIntTypeWidth(param_type);
                if (arg_width != param_width) {
                    stats.param_type_mismatches += 1;
                    const mismatch = AbiMismatchInfo{
                        .kind = .param_type_mismatch,
                        .caller_name = caller_name,
                        .callee_name = callee_name,
                        .caller_lang = "unknown",
                        .callee_lang = "unknown",
                        .param_index = idx,
                        .expected = try std.fmt.allocPrint(ctx.allocator, "i{}", .{param_width}),
                        .actual = try std.fmt.allocPrint(ctx.allocator, "i{}", .{arg_width}),
                        .description = "Integer width mismatch at FFI boundary: caller passes wider integer than callee expects (truncation risk)",
                    };
                    reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
                    continue;
                }
            }

            // Struct layout mismatch at FFI boundary — only when both sides are structs
            if (c.LLVMGetTypeKind(arg_llvm_type) == c.LLVMStructTypeKind and
                c.LLVMGetTypeKind(param_type) == c.LLVMStructTypeKind and
                !checkStructLayoutCompatibility(arg_llvm_type, param_type))
            {
                stats.struct_layout_mismatches += 1;
                const mismatch = AbiMismatchInfo{
                    .kind = .struct_layout_mismatch,
                    .caller_name = caller_name,
                    .callee_name = callee_name,
                    .caller_lang = "unknown",
                    .callee_lang = "unknown",
                    .param_index = idx,
                    .expected = getTypeName(param_type),
                    .actual = getTypeName(arg_llvm_type),
                    .description = "Struct layout or field type mismatch at FFI boundary (padding/alignment difference between languages)",
                };
                reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
            }
        }
    }

    /// Get the size of a type in bytes (estimated from LLVM type).
    /// Returns null if size cannot be determined from type alone.
    pub fn getTypeSizeEstimate(type_ref: c.LLVMTypeRef) ?u32 {
        const type_kind = c.LLVMGetTypeKind(type_ref);
        return switch (type_kind) {
            c.LLVMVoidTypeKind => 0,
            c.LLVMHalfTypeKind => 2,
            c.LLVMFloatTypeKind => 4,
            c.LLVMDoubleTypeKind => 8,
            c.LLVMX86_FP80TypeKind => 10,
            c.LLVMFP128TypeKind, c.LLVMPPC_FP128TypeKind => 16,
            c.LLVMIntegerTypeKind => (c.LLVMGetIntTypeWidth(type_ref) + 7) / 8,
            c.LLVMPointerTypeTypeKind => 8, // Assume 64-bit pointers
            c.LLVMArrayTypeKind => {
                const elem_size = getTypeSizeEstimate(c.LLVMGetElementType(type_ref)) orelse return null;
                return elem_size * c.LLVMGetArrayLength(type_ref);
            },
            c.LLVMStructTypeKind => {
                // For structs, sum up field sizes (simplified - doesn't account for padding)
                const num_elements = c.LLVMCountStructElementTypes(type_ref);
                var total: u32 = 0;
                var i: u32 = 0;
                while (i < num_elements) : (i += 1) {
                    const field_size = getTypeSizeEstimate(c.LLVMStructGetTypeAtIndex(type_ref, i)) orelse return null;
                    total += field_size;
                }
                return total;
            },
            else => null,
        };
    }

    /// Check if two LLVM types are compatible for ABI purposes.
    fn areTypesCompatible(type1: c.LLVMTypeRef, type2: c.LLVMTypeRef) bool {
        // Same type is always compatible
        if (type1 == type2) return true;

        const kind1 = c.LLVMGetTypeKind(type1);
        const kind2 = c.LLVMGetTypeKind(type2);

        // Different type kinds are incompatible
        if (kind1 != kind2) return false;

        // For integer types, check width
        if (kind1 == c.LLVMIntegerTypeKind) {
            return c.LLVMGetIntTypeWidth(type1) == c.LLVMGetIntTypeWidth(type2);
        }

        // For pointer types, they're compatible (opaque pointers in LLVM 15+)
        if (kind1 == c.LLVMPointerTypeKind) {
            return true;
        }

        // For float types, check kind
        if (kind1 == c.LLVMFloatTypeKind or kind1 == c.LLVMDoubleTypeKind) {
            return kind1 == kind2;
        }

        // For struct types, check if they have the same layout
        if (kind1 == c.LLVMStructTypeKind) {
            const num_elements1 = c.LLVMCountStructElementTypes(type1);
            const num_elements2 = c.LLVMCountStructElementTypes(type2);
            if (num_elements1 != num_elements2) return false;

            var i: u32 = 0;
            while (i < num_elements1) : (i += 1) {
                const elem1 = c.LLVMStructGetTypeAtIndex(type1, i);
                const elem2 = c.LLVMStructGetTypeAtIndex(type2, i);
                if (!areTypesCompatible(elem1, elem2)) return false;
            }
            return true;
        }

        // For array types, check element type and count
        if (kind1 == c.LLVMArrayTypeKind) {
            const elem1 = c.LLVMGetElementType(type1);
            const elem2 = c.LLVMGetElementType(type2);
            return areTypesCompatible(elem1, elem2) and
                c.LLVMGetArrayLength(type1) == c.LLVMGetArrayLength(type2);
        }

        // For other types, assume incompatible
        return false;
    }

    /// Get human-readable type name.
    fn getTypeName(type_ref: c.LLVMTypeRef) []const u8 {
        const type_kind = c.LLVMGetTypeKind(type_ref);
        return switch (type_kind) {
            c.LLVMVoidTypeKind => "void",
            c.LLVMHalfTypeKind => "f16",
            c.LLVMFloatTypeKind => "f32",
            c.LLVMDoubleTypeKind => "f64",
            c.LLVMX86_FP80TypeKind => "f80",
            c.LLVMFP128TypeKind => "f128",
            c.LLVMPPC_FP128TypeKind => "ppc_f128",
            c.LLVMIntegerTypeKind => switch (c.LLVMGetIntTypeWidth(type_ref)) {
                1 => "i1",
                8 => "i8",
                16 => "i16",
                32 => "i32",
                64 => "i64",
                128 => "i128",
                else => "integer",
            },
            c.LLVMFunctionTypeKind => "function",
            c.LLVMStructTypeKind => "struct",
            c.LLVMArrayTypeKind => "array",
            c.LLVMPointerTypeKind => "ptr",
            c.LLVMVectorTypeKind => "vector",
            else => "unknown",
        };
    }

    /// Get human-readable calling convention name.
    fn getCallingConventionName(cc: c_uint) []const u8 {
        return switch (cc) {
            c.LLVMCCallConv => "cdecl",
            10 => "x86_64_sysv", // X86_64 SysV
            c.LLVMFastCallConv => "fastcall",
            c.LLVMX86StdcallCallConv => "stdcall",
            else => "unknown",
        };
    }

    /// Calculate confidence score based on mismatch type.
    /// Higher confidence means the mismatch is more likely to be a real issue.
    fn calculateConfidence(mismatch_kind: AbiMismatchKind) f64 {
        return switch (mismatch_kind) {
            // Critical mismatches - almost certainly bugs
            .calling_convention_mismatch => 0.95,
            .param_count_mismatch => 0.90,
            .return_type_mismatch => 0.90,

            // High confidence mismatches
            .param_type_mismatch => 0.85,
            .struct_layout_mismatch => 0.85,
            .struct_size_mismatch => 0.85,
            .struct_alignment_mismatch => 0.85,
            .struct_field_mismatch => 0.85,

            // Medium confidence mismatches
            .enum_size_mismatch => 0.80,
            .function_pointer_mismatch => 0.80,

            // Lower confidence mismatches
            .varargs_mismatch => 0.70,
        };
    }

    /// Report an ABI compatibility issue.
    fn reportAbiMismatch(
        ctx: *PassContext,
        call_inst: c.LLVMValueRef,
        mismatch: AbiMismatchInfo,
        diag: *DiagnosticWriter,
    ) !void {
        _ = call_inst;
        const location = Location.init(mismatch.caller_name);

        const trace = try ctx.allocator.alloc(TraceEntry, 4);
        trace[0] = try makeTrace(ctx.allocator, "ABI mismatch detected: {s}", .{@tagName(mismatch.kind)});
        trace[1] = try makeTrace(ctx.allocator, "Caller: {s} ({s})", .{ mismatch.caller_name, mismatch.caller_lang });
        trace[2] = try makeTrace(ctx.allocator, "Callee: {s} ({s})", .{ mismatch.callee_name, mismatch.callee_lang });
        trace[3] = try makeTrace(ctx.allocator, "Expected: {s}, Got: {s}", .{ mismatch.expected, mismatch.actual });

        // All ABI mismatches are reported as ffi_type_mismatch
        const issue_kind: IssueKind = .ffi_type_mismatch;

        // Determine severity based on mismatch type
        const severity: Severity = if (mismatch.kind == .calling_convention_mismatch)
            .critical
        else if (mismatch.kind == .varargs_mismatch)
            .medium
        else
            .high;

        const confidence = calculateConfidence(mismatch.kind);

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "ABI incompatibility: {s} - {s}",
            .{ @tagName(mismatch.kind), mismatch.description },
        );

        const issue = Issue.initWithTrace(
            issue_kind,
            message,
            location,
            severity,
            @floatCast(confidence),
            trace,
        );

        try ctx.addIssue(&issue);

        diag.warn("[ABI-COMPAT] {s} -> {s}: {s} (confidence: {d:.2})", .{
            mismatch.caller_name,
            mismatch.callee_name,
            mismatch.description,
            confidence,
        });
    }
};

/// Function signature information collected from LLVM IR.
const FunctionSignature = struct {
    name: []const u8,
    param_count: u32,
    param_types: ?[]const c.LLVMTypeRef,
    ret_type: c.LLVMTypeRef,
    ret_type_kind: c.LLVMTypeKind,
    ret_type_name: []const u8,
    is_varargs: bool,
    is_declaration: bool,
    calling_convention: c_uint,
};

fn makeTrace(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "areTypesCompatible - various cases" {
    const i32_type = c.LLVMInt32Type();
    const i64_type = c.LLVMInt64Type();
    const f32_type = c.LLVMFloatType();
    const f64_type = c.LLVMDoubleType();

    // Same types are compatible
    try std.testing.expect(AbiCompatChecker.areTypesCompatible(i32_type, i32_type));
    try std.testing.expect(AbiCompatChecker.areTypesCompatible(f64_type, f64_type));

    // Different integer widths are incompatible
    try std.testing.expect(!AbiCompatChecker.areTypesCompatible(i32_type, i64_type));

    // Different type kinds are incompatible
    try std.testing.expect(!AbiCompatChecker.areTypesCompatible(i32_type, f32_type));

    // Pointer types are compatible
    const ptr1 = c.LLVMPointerType(i32_type, 0);
    const ptr2 = c.LLVMPointerType(i32_type, 0);
    try std.testing.expect(AbiCompatChecker.areTypesCompatible(ptr1, ptr2));
}

test "checkStructLayoutCompatibilityDetailed - various cases" {
    const i32_type = c.LLVMInt32Type();
    const i64_type = c.LLVMInt64Type();
    const f32_type = c.LLVMFloatType();

    // Test compatible structs
    const fields1 = [_]c.LLVMTypeRef{ i32_type, i64_type };
    const fields2 = [_]c.LLVMTypeRef{ i32_type, i64_type };
    const struct1 = c.LLVMStructType(&fields1, 2, 0);
    const struct2 = c.LLVMStructType(&fields2, 2, 0);

    const result1 = try AbiCompatChecker.checkStructLayoutCompatibilityDetailed(std.testing.allocator, struct1, struct2);
    defer std.testing.allocator.free(result1.incompatible_fields);
    try std.testing.expect(result1.compatible);
    try std.testing.expectEqual(@as(u32, 2), result1.field_count);
    try std.testing.expect(result1.packed_matches);
    try std.testing.expectEqual(@as(usize, 0), result1.incompatible_fields.len);

    // Test incompatible field types
    const fields3 = [_]c.LLVMTypeRef{ f32_type, i64_type };
    const struct3 = c.LLVMStructType(&fields3, 2, 0);

    const result2 = try AbiCompatChecker.checkStructLayoutCompatibilityDetailed(std.testing.allocator, struct1, struct3);
    defer std.testing.allocator.free(result2.incompatible_fields);
    try std.testing.expect(!result2.compatible);
    try std.testing.expectEqual(@as(u32, 2), result2.field_count);
    try std.testing.expect(result2.packed_matches);
    try std.testing.expectEqual(@as(usize, 1), result2.incompatible_fields.len);
    try std.testing.expectEqual(@as(u32, 0), result2.incompatible_fields[0]);

    // Test different field counts
    const fields4 = [_]c.LLVMTypeRef{i32_type};
    const struct4 = c.LLVMStructType(&fields4, 1, 0);

    const result3 = try AbiCompatChecker.checkStructLayoutCompatibilityDetailed(std.testing.allocator, struct1, struct4);
    defer std.testing.allocator.free(result3.incompatible_fields);
    try std.testing.expect(!result3.compatible);
    try std.testing.expectEqual(@as(u32, 2), result3.field_count);

    // Test packed vs unpacked
    const struct5 = c.LLVMStructType(&fields2, 2, 1); // Packed

    const result4 = try AbiCompatChecker.checkStructLayoutCompatibilityDetailed(std.testing.allocator, struct1, struct5);
    defer std.testing.allocator.free(result4.incompatible_fields);
    try std.testing.expect(!result4.compatible);
    try std.testing.expect(!result4.packed_matches);
}
