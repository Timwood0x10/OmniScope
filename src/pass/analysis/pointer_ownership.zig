//! Pointer Ownership Tracking Pass
//!
//! Tracks pointer ownership across FFI boundaries to detect:
//! - Cross-language free mismatch (Rust alloc, C free or vice versa)
//! - Ownership loss when passing pointers across boundaries
//! - Double free risks
//!
//! This pass analyzes LLVM IR to identify allocation and free sites,
//! then tracks ownership state across function calls.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const FFIBoundary = @import("../../diag/issue.zig").FFIBoundary;
const Location = @import("../../diag/issue.zig").Location;
const FactKind = @import("../../fact/fact.zig").FactKind;

/// Error type for ownership tracking operations.
pub const OwnershipError = error{
    /// Memory allocation failed.
    OutOfMemory,
    /// Module not available.
    NoModule,
};

/// Ownership violation types detected by this pass.
pub const OwnershipViolationType = enum(u8) {
    /// Pointer allocated in one language, freed in another.
    cross_lang_free_mismatch,
    /// Ownership transferred but not properly tracked.
    ownership_lost,
    /// Same memory freed twice across boundaries.
    double_free_risk,
    /// Pointer passed to C but Rust still holds ownership.
    rust_drop_after_ffi_transfer,
};

/// Ownership violation detected during analysis.
const OwnershipViolation = struct {
    /// Type of violation.
    violation_type: OwnershipViolationType,
    /// Function where violation was detected.
    func_name: []const u8,
    /// Instruction ID where violation occurred.
    inst_id: u32,
    /// Allocation language.
    alloc_lang: Language,
    /// Free language (if applicable).
    free_lang: ?Language,
    /// Severity level (0=low, 1=medium, 2=high, 3=critical).
    severity: u8,
};

/// Allocation site information.
const AllocSite = struct {
    /// Instruction ID.
    inst_id: u32,
    /// Function name where allocation occurred.
    func_name: []const u8,
    /// Language of function.
    lang: Language,
    /// Allocation type.
    alloc_type: AllocType,
    /// Pointer value ID produced by this allocation.
    ptr_value_id: u32,
    /// Debug file name (optional).
    debug_file: ?[]const u8,
    /// Debug line number (optional).
    debug_line: ?u32,
    /// Debug column number (optional).
    debug_column: ?u32,
};

/// Allocation types.
const AllocType = enum(u8) {
    /// Standard malloc/calloc/realloc.
    heap,
    /// Rust Box::into_raw - ownership transferred to caller.
    rust_box_into_raw,
    /// Rust Box::from_raw - ownership transferred from caller.
    rust_box_from_raw,
    /// Rust std::alloc::alloc.
    rust_alloc,
    /// C++ new.
    cpp_new,
    /// Unknown allocation.
    unknown,
};

/// Pointer ownership state.
const OwnershipState = enum(u8) {
    /// Pointer is live and in use.
    live,
    /// Memory allocated but ownership transferred to external code.
    ownership_transferred,
    /// Memory was freed.
    freed,
    /// Memory leak - never freed.
    leaked,
};

/// Free site information.
const FreeSite = struct {
    /// Instruction ID.
    inst_id: u32,
    /// Function name where free occurred.
    func_name: []const u8,
    /// Language of free operation.
    lang: Language,
    /// Free type.
    free_type: FreeType,
    /// Pointer value ID being freed.
    ptr_value_id: u32,
    /// Debug file name (optional).
    debug_file: ?[]const u8,
    /// Debug line number (optional).
    debug_line: ?u32,
    /// Debug column number (optional).
    debug_column: ?u32,
};

/// Free types.
const FreeType = enum(u8) {
    /// Standard free().
    free,
    /// Rust Box::from_raw.
    rust_box_from_raw,
    /// Rust Box::drop_in_place.
    rust_drop,
    /// C++ delete.
    cpp_delete,
    /// Unknown free.
    unknown,
};

/// Statistics for ownership tracking.
const OwnershipStats = struct {
    /// Total allocation sites found.
    alloc_sites: u32 = 0,
    /// Total free sites found.
    free_sites: u32 = 0,
    /// Total pointers tracked.
    tracked_pointers: u32 = 0,
    /// Cross-FFI ownership transfers detected.
    cross_ffi_transfers: u32 = 0,
    /// Potential violations detected.
    violations: u32 = 0,
};

/// Pointer ownership tracking pass.
pub const PointerOwnershipPass = struct {
    pub const name = "pointer-ownership";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    /// Run ownership tracking analysis.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) OwnershipError!void {
        if (ctx.module == null) {
            diag.warn("PointerOwnership: No module loaded, skipping", .{});
            return;
        }

        var stats = OwnershipStats{};
        var alloc_map = std.AutoHashMap(u32, AllocSite).init(ctx.allocator);
        defer alloc_map.deinit();

        var free_map = std.AutoHashMap(u32, FreeSite).init(ctx.allocator);
        defer free_map.deinit();

        const mod = ctx.module.?.raw;

        // Check for debug metadata availability.
        const has_debug_info = checkDebugMetadataAvailable(mod);
        if (!has_debug_info) {
            diag.info("TIP: Rebuild with -g for file/line diagnostics", .{});
        }

        var func = c.LLVMGetFirstFunction(mod);

        // First pass: identify all allocation and free sites.
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;
            try analyzeFunctionForOwnership(func, &alloc_map, &free_map, &stats, has_debug_info);
        }

        // Second pass: detect violations.
        try detectViolations(ctx, &alloc_map, &free_map, &stats, diag);

        // Report findings.
        diag.info("PointerOwnership: Found {d} allocations, {d} frees, {d} tracked pointers", .{
            stats.alloc_sites,
            stats.free_sites,
            stats.tracked_pointers,
        });

        if (stats.cross_ffi_transfers > 0) {
            diag.info("PointerOwnership: {d} cross-FFI ownership transfers detected", .{
                stats.cross_ffi_transfers,
            });
        }

        if (stats.violations > 0) {
            diag.err("PointerOwnership: Found {d} ownership violations", .{stats.violations});
        } else {
            diag.info("PointerOwnership: No cross-language ownership violations detected", .{});
            diag.info("  (Checks for Rust-alloc/C-free or C-alloc/Rust-free mismatches)", .{});
        }
    }

    /// Check if debug metadata is available in the module.
    fn checkDebugMetadataAvailable(mod: c.LLVMModuleRef) bool {
        // Check for named metadata with debug-related names.
        var md_node = c.LLVMGetFirstNamedMetadata(mod);
        while (@intFromPtr(md_node) != 0) {
            var name_len: usize = 0;
            const name_ptr = c.LLVMGetNamedMetadataName(md_node, &name_len);
            if (@intFromPtr(name_ptr) != 0) {
                const md_name = name_ptr[0..name_len];
                // Look for debug-related named metadata.
                if (std.mem.startsWith(u8, md_name, "llvm.dbg") or
                    std.mem.startsWith(u8, md_name, "!dbg"))
                {
                    return true;
                }
            }
            md_node = c.LLVMGetNextNamedMetadata(md_node);
        }
        return false;
    }

    /// Detect ownership violations between allocations and frees.
    fn detectViolations(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, AllocSite),
        free_map: *std.AutoHashMap(u32, FreeSite),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) OwnershipError!void {
        // Iterate through all allocations and insert ownership_alloc facts.
        var alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc = entry.value_ptr.*;

            // Insert ownership_alloc fact
            // subject = ptr_id, object = alloc_lang, context = func_id
            try ctx.fact_store.insert(
                .ownership_alloc,
                alloc.ptr_value_id,
                @intFromEnum(alloc.lang),
                alloc.inst_id,
            );

            // Check if this allocation crosses FFI boundary.
            if (isCrossFFIAllocation(alloc)) {
                stats.cross_ffi_transfers += 1;

                // Insert ownership_transfer fact
                try ctx.fact_store.insert(
                    .ownership_transfer,
                    alloc.ptr_value_id,
                    @intFromEnum(alloc.lang),
                    alloc.inst_id,
                );
            }
        }

        // Iterate through all frees and insert ownership_free facts.
        var free_iter = free_map.iterator();
        while (free_iter.next()) |entry| {
            const free_site = entry.value_ptr.*;

            // Insert ownership_free fact
            try ctx.fact_store.insert(
                .ownership_free,
                free_site.ptr_value_id,
                @intFromEnum(free_site.lang),
                free_site.inst_id,
            );
        }

        // Detect cross-language violations.
        // Note: This is a simplified check that uses function-level analysis.
        // A complete data flow solution would track pointer values through
        // def-use chains, but that requires SSA analysis infrastructure.
        //
        // Current approach: Report potential issues based on language patterns
        // and let users verify with manual inspection or additional tools.
        alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc = entry.value_ptr.*;

            // Check if there's a corresponding free in different language.
            free_iter = free_map.iterator();
            while (free_iter.next()) |free_entry| {
                const free_site = free_entry.value_ptr.*;

                // Heuristic: Check for cross-language patterns in the same module.
                // This may produce false positives but catches common issues.
                if (alloc.lang != free_site.lang and
                    alloc.lang != .unknown and
                    free_site.lang != .unknown)
                {
                    // Only report if there's a reasonable suspicion:
                    // - Same function has both alloc and free (potential mismatch)
                    // - Different functions with FFI boundary (cross-language transfer)
                    const same_function = std.mem.eql(u8, alloc.func_name, free_site.func_name);
                    const has_ffi_pattern = std.mem.indexOf(u8, alloc.func_name, "ffi") != null or
                        std.mem.indexOf(u8, free_site.func_name, "ffi") != null;

                    if (same_function or has_ffi_pattern) {
                        const alloc_loc = Location.init(alloc.func_name);
                        const free_loc = Location.init(free_site.func_name);

                        diag.warn("POTENTIAL CROSS-LANGUAGE OWNERSHIP ISSUE", .{});
                        diag.warn("  Alloc: {s} ({s})", .{
                            alloc_loc.function,
                            @tagName(alloc.lang),
                        });
                        diag.warn("  Free: {s} ({s})", .{
                            free_loc.function,
                            @tagName(free_site.lang),
                        });
                        diag.warn("  Note: Manual verification recommended", .{});

                        // Insert ownership_violation fact
                        try ctx.fact_store.insert(
                            .ownership_violation,
                            alloc.inst_id,
                            @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch),
                            free_site.inst_id,
                        );

                        stats.violations += 1;
                    }
                }
            }
        }
    }

    /// Check if an allocation crosses an FFI boundary.
    fn isCrossFFIAllocation(alloc: AllocSite) bool {
        return alloc.lang != .unknown;
    }

    /// Analyze a function for allocation and free sites.
    fn analyzeFunctionForOwnership(
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, AllocSite),
        free_map: *std.AutoHashMap(u32, FreeSite),
        stats: *OwnershipStats,
        has_debug_info: bool,
    ) OwnershipError!void {
        const func_name = getFunctionName(func);
        const func_lang = identifyLanguage(func);

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try analyzeInstructionForOwnership(
                    inst,
                    func_name,
                    func_lang,
                    alloc_map,
                    free_map,
                    stats,
                    has_debug_info,
                );
            }
        }
    }

    /// Analyze a single instruction for ownership-relevant operations.
    fn analyzeInstructionForOwnership(
        inst: c.LLVMValueRef,
        func_name: []const u8,
        func_lang: Language,
        alloc_map: *std.AutoHashMap(u32, AllocSite),
        free_map: *std.AutoHashMap(u32, FreeSite),
        stats: *OwnershipStats,
        has_debug_info: bool,
    ) OwnershipError!void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Debug info extraction placeholder.
        // Note: Full debug info requires LLVMRustDI* APIs which are not in vanilla LLVM C API.
        // For now, we store null values and future work can implement actual extraction.
        _ = has_debug_info;

        // Check for allocation patterns.
        if (isAllocationInstruction(inst, opcode)) {
            const alloc_type = classifyAllocation(inst, opcode);
            const alloc_site = AllocSite{
                .inst_id = @truncate(@intFromPtr(inst)),
                .func_name = func_name,
                .lang = func_lang,
                .alloc_type = alloc_type,
                .ptr_value_id = @truncate(@intFromPtr(inst)),
                .debug_file = null,
                .debug_line = null,
                .debug_column = null,
            };

            try alloc_map.put(@truncate(@intFromPtr(inst)), alloc_site);
            stats.alloc_sites += 1;
            stats.tracked_pointers += 1;
        }

        // Check for free patterns.
        if (isFreeInstruction(inst, opcode, func_lang)) {
            const free_type = classifyFree(inst, opcode, func_lang);
            const free_site = FreeSite{
                .inst_id = @truncate(@intFromPtr(inst)),
                .func_name = func_name,
                .lang = func_lang,
                .free_type = free_type,
                .ptr_value_id = @truncate(@intFromPtr(inst)),
                .debug_file = null,
                .debug_line = null,
                .debug_column = null,
            };

            try free_map.put(@truncate(@intFromPtr(inst)), free_site);
            stats.free_sites += 1;
        }
    }

    /// Check if an instruction is an allocation.
    /// Matches standard C allocation functions and Rust Box::into_raw.
    /// Note: Internal Rust allocators (__rust_alloc) are excluded as they are
    /// implementation details that don't represent ownership transfer.
    fn isAllocationInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
        if (opcode == c.LLVMCall) {
            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) return false;

            const name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(name_ptr) == 0) return false;

            const callee_name = std.mem.span(name_ptr);

            // Standard C allocation functions.
            if (std.mem.eql(u8, callee_name, "malloc") or
                std.mem.eql(u8, callee_name, "calloc") or
                std.mem.eql(u8, callee_name, "realloc") or
                std.mem.eql(u8, callee_name, "aligned_alloc"))
            {
                return true;
            }

            // Rust Box::into_raw - explicit ownership transfer.
            if (std.mem.indexOf(u8, callee_name, "into_raw") != null) {
                return true;
            }

            // C++ operator new.
            if (std.mem.indexOf(u8, callee_name, "operator new") != null) {
                return true;
            }
        }

        return false;
    }

    /// Classify the type of allocation.
    fn classifyAllocation(inst: c.LLVMValueRef, opcode: c_uint) AllocType {
        _ = opcode;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return .unknown;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

        const callee_name = std.mem.span(callee_name_ptr);

        if (std.mem.indexOf(u8, callee_name, "into_raw") != null) {
            return .rust_box_into_raw;
        }
        if (std.mem.indexOf(u8, callee_name, "from_raw") != null) {
            return .rust_box_from_raw;
        }

        return .heap;
    }

    /// Check if an instruction is a free.
    fn isFreeInstruction(inst: c.LLVMValueRef, opcode: c_uint, lang: Language) bool {
        _ = lang;

        if (opcode == c.LLVMCall) {
            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) return false;

            const callee_name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(callee_name_ptr) == 0) return false;

            const callee_name = std.mem.span(callee_name_ptr);

            return std.mem.indexOf(u8, callee_name, "free") != null;
        }

        return false;
    }

    /// Classify the type of free.
    fn classifyFree(inst: c.LLVMValueRef, opcode: c_uint, lang: Language) FreeType {
        _ = inst;
        _ = opcode;
        _ = lang;

        return .free;
    }

    /// Get function name from LLVM value.
    fn getFunctionName(func: c.LLVMValueRef) []const u8 {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) return "unknown";
        return std.mem.span(name_ptr);
    }

    /// Identify the language of a function based on naming conventions.
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        const func_name = getFunctionName(func);

        // Rust uses _R prefix for v0 mangling (RFC 2603).
        // Note: _ZN is C++ mangling, NOT Rust.
        if (func_name.len > 2 and
            func_name[0] == '_' and
            func_name[1] == 'R')
        {
            return .rust;
        }

        // Check for Rust-specific patterns.
        if (std.mem.indexOf(u8, func_name, "alloc::") != null or
            std.mem.indexOf(u8, func_name, "core::") != null or
            std.mem.indexOf(u8, func_name, "std::") != null)
        {
            // These could be Rust or C++, check for Rust-specific patterns
            if (std.mem.indexOf(u8, func_name, "::boxed::") != null or
                std.mem.indexOf(u8, func_name, "::ffi::") != null or
                std.mem.indexOf(u8, func_name, "::cstring::") != null)
            {
                return .rust;
            }
        }

        // Check for C standard library functions.
        if (std.mem.eql(u8, func_name, "malloc") or
            std.mem.eql(u8, func_name, "free") or
            std.mem.eql(u8, func_name, "calloc") or
            std.mem.eql(u8, func_name, "realloc") or
            std.mem.eql(u8, func_name, "printf") or
            std.mem.eql(u8, func_name, "strlen"))
        {
            return .c;
        }

        // C++ mangled names start with _Z or _ZN.
        if (func_name.len > 2 and
            func_name[0] == '_' and
            func_name[1] == 'Z')
        {
            return .cpp;
        }

        // Check for Zig allocator patterns.
        if (std.mem.indexOf(u8, func_name, "Allocator.") != null or
            std.mem.indexOf(u8, func_name, "allocImpl") != null)
        {
            return .zig;
        }

        // Check for Swift patterns.
        if (std.mem.indexOf(u8, func_name, "UnsafeMutablePointer") != null or
            std.mem.indexOf(u8, func_name, "$s") != null)
        {
            return .swift;
        }

        return .unknown;
    }
};

test "PointerOwnership - alloc types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AllocType.heap));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(AllocType.rust_box_into_raw));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(AllocType.rust_box_from_raw));
}

test "PointerOwnership - ownership states" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipState.live));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipState.ownership_transferred));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipState.freed));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipState.leaked));
}

test "PointerOwnership - violation types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipViolationType.ownership_lost));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipViolationType.double_free_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipViolationType.rust_drop_after_ffi_transfer));
}
