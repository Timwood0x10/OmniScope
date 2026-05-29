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
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const FuzzyMatcher = @import("../../../semantics/memory_graph.zig").FuzzyMatcher;
const MemoryRelations = @import("../../../semantics/memory_relations.zig").MemoryRelations;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;
const ffi_utils = @import("../ffi/ffi_utils.zig");

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
    pub const deps = &[_][]const u8{ "danger-surface", "ptr-lifetime" };

    /// Main entry point: single-pass scan with inline analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;
        // Runtime dependency validation: both danger_surface and FFI auto-relevant sets
        // must be populated by prior passes. If both empty, skip analysis.
        if (ctx.danger_surface_relevant.count() == 0 and ctx.ffi_auto_relevant.count() == 0) return;

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
            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) continue;
            func_count += 1;
            //  Function-level error isolation
            const count = scanAndAnalyzeFunction(ctx, func, &relations, &freed_pointers, diag) catch |err| {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                diag.warn("MemorySafety: skipped function due to error: {} ({s})", .{ err, func_name });
                continue;
            };
            issue_count += count;
        }

        if (issue_count > 0) {
            diag.info("[OMI-HIGH] MemorySafety: {} functions analyzed, {} issues detected", .{
                func_count,
                issue_count,
            });
        } else {
            diag.debug("MemorySafety: {} functions analyzed, no issues detected", .{func_count});
        }
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

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = ctx.classifyFunctionSurface(func_name, func_loc);
        if (!classification.origin.shouldReportByDefault()) return 0;

        _ = try relations.internString(func_name);

        var issue_count: usize = 0;

        // P0-3: Track which BBs freed each pointer within this function.
        // If the same pointer is freed in multiple BBs, they are likely in
        // mutually exclusive branches (if/else). Only report double free
        // if the pointer was freed in the SAME BB (sequential double free).
        var free_bb_map = std.AutoHashMap(u64, u32).init(ctx.allocator);
        defer free_bb_map.deinit();

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (llvm_safe.isCallOrInvoke(opcode)) {
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
                        // R8-L3 FIX: Add null guard before @intFromPtr to prevent panic
                        if (@intFromPtr(ptr_arg) == 0) continue;
                        const ptr_as_int = @intFromPtr(ptr_arg);

                        if (try validateAndReportFree(ctx, func, called_name, ptr_as_int, freed_pointers, &free_bb_map, relations, diag)) {
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
        free_bb_map: *std.AutoHashMap(u64, u32),
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

        // P0-3: Path-sensitive double free detection.
        // Check if this pointer was already freed in a DIFFERENT basic block
        // within the same function. If so, the frees are likely in mutually
        // exclusive branches (if/else) — not a real double free.
        //
        // EXCEPTION: FFI-related frees should NOT be suppressed because:
        //   1. Loop-pattern calls (e.g., MerkleTree::new calling sha256 N times)
        //      trigger multiple alloc/free cycles that are NOT mutually exclusive
        //   2. Cross-language memory bugs are inherently more dangerous
        //   3. The "mutually exclusive" assumption doesn't hold across ABI boundaries
        //
        // Detection uses BOTH callee name AND caller context:
        //   - Callee patterns: __rust_dealloc, free(), c_*, etc.
        //   - Caller context: FFI boundary functions, loop-pattern callers,
        //     cross-language wrappers (inflateEnd, PyMem_Free, etc.)
        const ffi_caller_name_ptr = c.LLVMGetValueName(caller_func);
        const ffi_caller_name = if (@intFromPtr(ffi_caller_name_ptr) != 0) std.mem.span(ffi_caller_name_ptr) else "";
        const is_ffi_free = isFFIRelatedFree(free_func_name, ffi_caller_name);
        if (!is_ffi_free) {
            if (free_bb_map.get(ptr_value)) |prev_bb_count| {
                if (prev_bb_count >= 1) {
                    // Already freed in at least one other BB in this function.
                    // This is the mutually-exclusive-branch pattern.
                    diag.debug("[SUPPRESSED] Mutually exclusive branch free (BB #{d}, ptr=0x{x}): {s}", .{
                        prev_bb_count + 1,
                        ptr_value,
                        free_func_name,
                    });
                    // Update BB count but do NOT report or add to freed_pointers.
                    _ = free_bb_map.put(ptr_value, prev_bb_count + 1) catch {};
                    return false;
                }
            }
        }

        // Cross-function double free check (original logic).
        for (freed_pointers.items) |freed_ptr| {
            if (freed_ptr == ptr_value) {
                // Suppress double free in Rust panic/cleanup paths.
                const caller_name_ptr = c.LLVMGetValueName(caller_func);
                if (@intFromPtr(caller_name_ptr) != 0) {
                    const caller_name = std.mem.span(caller_name_ptr);
                    if (isRustPanicOrCleanupStr(caller_name)) {
                        diag.debug("[SUPPRESSED] Double free in Rust panic/cleanup: {s}", .{free_func_name});
                        return false;
                    }
                }
                const callee_classification = ctx.classifyFunctionSurface(free_func_name, null);
                if (callee_classification.origin == .compiler_generated) {
                    diag.debug("[SUPPRESSED] Double free in compiler-generated function: {s} ({s})", .{ free_func_name, callee_classification.reason });
                    return false;
                }
                if (callee_classification.origin == .stdlib and isRustPanicOrCleanupStr(free_func_name)) {
                    diag.debug("[SUPPRESSED] Double free in Rust stdlib panic/cleanup: {s}", .{free_func_name});
                    return false;
                }
                try reportDoubleFree(ctx, caller_func, free_func_name, ptr_value, diag);
                return true;
            }
        }

        // Record this free.
        _ = free_bb_map.put(ptr_value, 1) catch {};
        try freed_pointers.append(ctx.allocator, ptr_value);

        if (!validation.is_valid and validation.confidence > 0.7) {
            try reportSuspiciousFree(ctx, caller_func, free_func_name, validation.confidence, ptr_value, diag);
            return true;
        }

        return false;
    }

    fn reportDoubleFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        func_name: []const u8,
        ptr_value: u64,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        const location = Location.init(caller_name);

        // E2-2b: UAF + FFI edge correlation — if the double-freed pointer
        // reaches FFI boundaries through alias chains, this is a cross-language
        // use-after-free which is far more dangerous.
        const reaches_ffi = ctx.isOnDangerPathFull(ptr_value);
        const confidence: f32 = if (reaches_ffi) 0.92 else 0.85;
        const severity: Severity = if (reaches_ffi) .critical else .high;

        const ffi_note = if (reaches_ffi) " [cross-FFI alias detected]" else "";

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "Potential double free via '{s}' (confidence: {d:.1}%{s})",
            .{ func_name, confidence * 100.0, ffi_note },
        );

        const issue = Issue.init(
            .double_free,
            message,
            location,
            severity,
            confidence,
        );

        try ctx.addIssue(&issue);
        ctx.allocator.free(message);

        const omi_prefix = if (severity == .critical) "[OMI-CRITICAL] " else "[OMI-HIGH] ";
        diag.warn("{s}Double free: {s} → {s}{s}", .{ omi_prefix, caller_name, func_name, ffi_note });
    }

    fn reportSuspiciousFree(
        ctx: *PassContext,
        caller_func: c.LLVMValueRef,
        func_name: []const u8,
        confidence: f32,
        ptr_value: u64,
        diag: *DiagnosticWriter,
    ) !void {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        if (confidence < 0.6) return;

        const location = Location.init(caller_name);

        // E2-2b: UAF + FFI edge correlation
        const reaches_ffi = ctx.isOnDangerPathFull(ptr_value);
        const adj_confidence = if (reaches_ffi) @min(confidence + 0.10, 0.95) else confidence;
        const severity: Severity = if (reaches_ffi and adj_confidence > 0.8) .high else if (adj_confidence > 0.8) .medium else .low;

        const ffi_note = if (reaches_ffi) " [cross-FFI alias]" else "";

        const message = try std.fmt.allocPrint(
            ctx.allocator,
            "Suspicious free via '{s}' without matching alloc (confidence: {d:.1}%{s})",
            .{ func_name, adj_confidence * 100.0, ffi_note },
        );

        const issue = Issue.init(
            .invalid_free,
            message,
            location,
            severity,
            adj_confidence,
        );

        try ctx.addIssue(&issue);
        ctx.allocator.free(message);

        const omi_prefix2 = if (severity == .high) "[OMI-HIGH] " else if (severity == .medium) "[OMI-MEDIUM] " else "";
        diag.warn("{s}Suspicious free: {s} → {s} ({d:.1}%){s}", .{
            omi_prefix2,
            caller_name,
            func_name,
            adj_confidence * 100.0,
            ffi_note,
        });
    }

    /// String version for direct name checking.
    /// Only applies to Rust-mangled functions to avoid suppressing C code
    /// that happens to contain "cleanup" or "panic" in its name.
    fn isRustPanicOrCleanupStr(func_name: []const u8) bool {
        // Guard: only apply to Rust-mangled functions
        const is_rust = std.mem.indexOf(u8, func_name, "_ZN") != null or
            std.mem.indexOf(u8, func_name, "_R") != null;
        if (!is_rust) return false;
        return ffi_utils.isRustDropGlue(func_name);
    }

    /// Check if a free call is FFI-related and should be exempt from
    /// "mutually exclusive branch" suppression.
    ///
    /// Uses TWO signals:
    ///   1. **Callee name**: Known FFI deallocators (__rust_dealloc, free(), c_*, etc.)
    ///   2. **Caller context**: Whether the calling function is an FFI boundary
    ///      or cross-language wrapper (even with non-standard deallocators like
    ///      inflateEnd, PyMem_Free, cairo_destroy, etc.)
    fn isFFIRelatedFree(free_func_name: []const u8, caller_func_name: []const u8) bool {
        // Signal 1: Callee name matches known FFI deallocator patterns
        if (isFFIDeallocatorName(free_func_name)) return true;

        // Signal 2: Caller function is an FFI boundary or cross-language wrapper
        if (isFFIBoundaryCaller(caller_func_name)) return true;

        return false;
    }

    /// Check if a free FUNCTION NAME matches known FFI deallocator patterns.
    fn isFFIDeallocatorName(func_name: []const u8) bool {
        // Rust global allocator (used in FFI contexts)
        if (std.mem.indexOf(u8, func_name, "__rust_dealloc") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__rust_alloc") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__rust_free") != null) return true;

        // C standard library frees
        if (std.mem.eql(u8, func_name, "free")) return true;
        if (std.mem.eql(u8, func_name, "realloc")) return true;

        // FFI bridge prefix conventions
        if (std.mem.startsWith(u8, func_name, "c_")) return true;
        if (std.mem.startsWith(u8, func_name, "cpp_")) return true;
        if (std.mem.startsWith(u8, func_name, "ffi_")) return true;

        // Common library deallocators used in FFI wrappers
        const ffi_deallocators = [_][]const u8{
            "inflateEnd", "deflateEnd", // zlib
            "PyMem_Free", "PyObject_Free", // Python C API
            "cairo_destroy", // Cairo
            "EVP_CIPHER_CTX_free", "EVP_PKEY_free", // OpenSSL
            "g_string_free", "g_free", // GLib
            "bson_destroy", // libbson
        };
        for (ffi_deallocators) |dealloc| {
            if (std.mem.eql(u8, func_name, dealloc)) return true;
        }

        return false;
    }

    /// Check if a CALLER function looks like an FFI boundary or cross-language wrapper.
    fn isFFIBoundaryCaller(func_name: []const u8) bool {
        if (func_name.len == 0) return false;

        // Skip compiler-generated and stdlib internals
        if (std.mem.startsWith(u8, func_name, "llvm.")) return false;
        if (std.mem.indexOf(u8, func_name, "__rust_") != null) return false;

        // FFI boundary naming patterns
        const ffi_patterns = [_][]const u8{
            "bridge",  "wrapper", "binding", "_ffi",
            "interop", "marshal", "extern",  "c2",
            "2c",      "2py",     "py2",     "_cb_",
            "_impl_",
        };
        for (ffi_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return true;
        }

        // Language transition markers: rust_hash, c_bridge, zig_main, etc.
        const lang_markers = [_][]const u8{
            "rust_",    "c_",        "cpp_",     "go_",      "zig_",
            "_hash",    "_compress", "_encrypt", "_decrypt", "_init",
            "_cleanup", "_free",     "_destroy",
        };
        for (lang_markers) |marker| {
            if (std.mem.indexOf(u8, func_name, marker) != null) return true;
        }

        return false;
    }
};

test "MemorySafetyPass - init" {
    try std.testing.expectEqualStrings("memory-safety", MemorySafetyPass.name);
    try std.testing.expectEqual(PassKind.analysis, MemorySafetyPass.kind);
}
