//! Ownership Violation Analysis Pass
//!
//! This pass detects ownership violations across FFI boundaries:
//! - Double free: Same pointer freed multiple times
//! - Use after free: Pointer used after being freed
//! - Ownership mismatch: Cross-language free (e.g., Rust alloc, C free)
//!
//! This is a focused pass that only handles ownership-related issues.
//! Other vulnerability types are handled by SemanticRegistry.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommonTypes = @import("../../../common/types.zig");
const FFIBoundary = @import("../../../diag/issue.zig").FFIBoundary;
const Language = FFIBoundary.Language;

const Pass = @import("../../pass.zig").Pass;
const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const ffi_matcher = @import("../../../ffi/ffi_matcher.zig");
const FFIMatcher = ffi_matcher.FFIMatcher;
const FFIMatch = ffi_matcher.FFIMatch;

const llvm_safe = @import("../../../ir/llvm_safe.zig");
const c = @import("../../../ir/llvm_raw.zig").c;
const debug_info = @import("../../../ir/debug_info.zig");

const FactStore = @import("../../../fact/store.zig").FactStore;
const FactKind = @import("../../../fact/fact.zig").FactKind;

const SemanticRegistry = @import("../../../registry/semantic_registry.zig").SemanticRegistry;
const RiskKind = @import("../../../registry/semantic_registry.zig").RiskKind;

const NoiseReduction = @import("../noise/noise_reduction.zig");
const FPWhitelist = @import("../../filter/fp_whitelist.zig");
const hooks = @import("../../../registry/hooks.zig");
const ffi_language_classifier = @import("ffi_language_classifier.zig");

/// Error type for ownership analysis operations
pub const FFIAnalysisError = error{
    NoModule,
    MatcherInitFailed,
    OutOfMemory,
};

/// Ownership violation type
pub const ViolationType = enum {
    double_free,
    use_after_free,
    ownership_mismatch,
    leak,
};

/// Severity level (re-exported from common/types.zig).
/// Use common/types.zig.Severity directly in new code.
pub const Severity = CommonTypes.Severity;

/// Ownership violation result
pub const OwnershipViolation = struct {
    violation_type: ViolationType,
    severity: Severity,
    function_name: []const u8,
    description: []const u8,
    confidence: f32,
    owns_description: bool = false,

    pub fn deinit(self: *OwnershipViolation, allocator: Allocator) void {
        if (self.owns_description and self.description.len > 0) {
            allocator.free(self.description);
        }
    }
};

/// Analysis result
pub const FFIAnalysisResult = struct {
    match_count: usize,
    boundary_count: usize,
    violation_count: usize,
    violations: []const OwnershipViolation,
};

/// Ownership violation analysis pass
pub const FFIAnalysisPass = struct {
    pub const name = "ownership-violation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "pointer-flow" };

    allocator: Allocator,
    store: *FactStore,
    matcher: ?FFIMatcher,
    violations: std.ArrayList(OwnershipViolation),

    /// Track allocation sites: ptr_value_id -> allocation info
    allocation_sites: std.AutoHashMap(u64, AllocationInfo),

    /// Track free sites: ptr_value_id -> list of free info (allows tracking multiple frees per pointer)
    free_sites: std.AutoHashMap(u64, std.ArrayList(FreeInfo)),

    /// v0.1.6: Track which basic block each allocation/free is in (for path analysis)
    alloc_bb_map: std.AutoHashMap(u64, c.LLVMBasicBlockRef),
    free_bb_map: std.AutoHashMap(u64, std.ArrayList(c.LLVMBasicBlockRef)),

    const AllocationInfo = struct {
        func_name: []const u8,
        language: Language,
        value_id: u64,
        inst_ptr: c.LLVMValueRef,
    };

    const FreeInfo = struct {
        func_name: []const u8,
        language: Language,
        value_id: u64,
        inst_ptr: c.LLVMValueRef,
    };

    pub fn init(allocator: Allocator, store: *FactStore) FFIAnalysisPass {
        return .{
            .allocator = allocator,
            .store = store,
            .matcher = null,
            .violations = std.ArrayList(OwnershipViolation).init(allocator),
            .allocation_sites = std.AutoHashMap(u64, AllocationInfo).init(allocator),
            .free_sites = std.AutoHashMap(u64, std.ArrayList(FreeInfo)).init(allocator),
            .alloc_bb_map = std.AutoHashMap(u64, c.LLVMBasicBlockRef).init(allocator),
            .free_bb_map = std.AutoHashMap(u64, std.ArrayList(c.LLVMBasicBlockRef)).init(allocator),
        };
    }

    pub fn deinit(self: *FFIAnalysisPass) void {
        if (self.matcher) |*m| {
            m.deinit();
        }
        for (self.violations.items) |*v| {
            v.deinit(self.allocator);
        }
        self.violations.deinit();
        self.allocation_sites.deinit();
        {
            var iter = self.free_sites.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
            }
            self.free_sites.deinit();
        }
        self.alloc_bb_map.deinit();
        {
            var iter = self.free_bb_map.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
            }
            self.free_bb_map.deinit();
        }
    }

    pub fn run(self: *FFIAnalysisPass, ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) {
            diag.warn("OwnershipViolation: No module loaded, skipping analysis", .{});
            return;
        }

        const mod = ctx.module.?.raw;

        // Step 1: Initialize FFIMatcher and extract functions
        var matcher = try FFIMatcher.init(ctx.allocator);
        self.matcher = matcher;

        const safe_module = llvm_safe.Module{ .raw = mod };
        try matcher.extractFunctions(safe_module);
        try matcher.matchFunctions();
        diag.info("OwnershipViolation: Found {} FFI matches", .{matcher.getMatches().len});

        // Step 2: Set matcher in DataFlowGraph
        ctx.data_flow_graph.setFFIMatcher(&matcher);
        try ctx.data_flow_graph.createFFIBoundariesFromMatcher();

        // Phase R5.2: Initialize Hook system for cross-language ownership tracking.
        // Hooks detect Rust into_raw/from_raw pairing, Python refcount balance, Go escapes.
        try hooks.initHookStates(ctx.allocator);
        defer hooks.deinitHookStates();

        // Step 3: Collect allocation and free sites
        try self.collectAllocationSites(mod, diag);
        try self.collectFreeSites(mod, diag);

        // Step 4: Detect ownership violations
        try self.detectDoubleFree(diag);
        try self.detectOwnershipMismatch(diag);

        // v0.1.6: Enhanced detection
        try self.detectErrorPathLeaks(diag);
        try self.detectCrossPathDoubleFree(diag);

        // Phase R5.2: Check hook state for module-level ownership issues.
        // Rust unpaired transfers indicate potential cross-language leaks.
        if (hooks.rustUnpairedTransferCount() > 0) {
            diag.warn("OwnershipViolation: {} unpaired Rust ownership transfer(s) detected — potential cross-language leak", .{hooks.rustUnpairedTransferCount()});
        }
        if (hooks.pythonUnbalancedDecrefCount() > 0) {
            const count = hooks.pythonUnbalancedDecrefCount();
            const desc = std.fmt.allocPrint(ctx.allocator, "{d} unbalanced Py_DECREF(s) across FFI boundary", .{count}) catch null;
            try self.violations.append(.{
                .violation_type = .use_after_free,
                .severity = .high,
                .function_name = "python_ffi_boundary",
                .description = desc orelse "Python refcount imbalance",
                .confidence = 0.80,
                .owns_description = desc != null,
            });
        }

        // Step 5: Store results
        try self.storeResults(ctx);

        diag.info("OwnershipViolation: {} allocations, {} frees, {} violations", .{
            self.allocation_sites.count(),
            self.free_sites.count(),
            self.violations.items.len,
        });
    }

    fn collectAllocationSites(self: *FFIAnalysisPass, mod: c.LLVMModuleRef, diag: *DiagnosticWriter) !void {
        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };

        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

            // v0.1.7: Skip compiler-generated and stdlib functions via three-layer noise reduction
            const debug_file_path = extractDebugFilePath(func);
            const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // Defense-in-depth: known FP whitelist
            if (FPWhitelist.is_known_fp(func_name) != null) continue;

            const language = self.detectLanguageWithDwarf(func, func_name);

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (opcode != c.LLVMCall) continue;

                    const called = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(called_name_ptr) == 0) continue;
                    const called_name = std.mem.span(called_name_ptr);

                    // Check if this is an allocation function
                    if (SemanticRegistry.lookup(called_name)) |sem| {
                        if (sem.transfers_ownership) {
                            // Get the return value (the allocated pointer)
                            const ptr_value: c.LLVMValueRef = inst;
                            const ptr_value_id: u64 = @intFromPtr(ptr_value);
                            try self.allocation_sites.put(ptr_value_id, .{
                                .func_name = func_name,
                                .language = language,
                                .value_id = ptr_value_id,
                                .inst_ptr = inst,
                            });
                            // v0.1.6: Track which BB this alloc is in
                            try self.alloc_bb_map.put(ptr_value_id, bb);
                        }
                    }
                }
            }
        }

        if (self.allocation_sites.count() > 0) {
            diag.info("OwnershipViolation: Found {} allocation sites", .{self.allocation_sites.count()});
        }
    }

    fn collectFreeSites(self: *FFIAnalysisPass, mod: c.LLVMModuleRef, diag: *DiagnosticWriter) !void {
        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };

        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

            // v0.1.7: Skip compiler-generated and stdlib functions via three-layer noise reduction
            const debug_file_path = extractDebugFilePath(func);
            const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // Defense-in-depth: known FP whitelist
            if (FPWhitelist.is_known_fp(func_name) != null) continue;

            const language = self.detectLanguageWithDwarf(func, func_name);

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (opcode != c.LLVMCall) continue;
                    const called = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called) == 0) continue;

                    const called_name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(called_name_ptr) == 0) continue;
                    const called_name = std.mem.span(called_name_ptr);

                    if (SemanticRegistry.lookup(called_name)) |sem| {
                        if (sem.consumes_ownership) {
                            const ptr_arg = c.LLVMGetOperand(inst, 0);
                            if (ptr_arg == null) {
                                diag.warn("Free operation missing pointer argument at {s}", .{func_name});
                                continue;
                            }
                            const ptr_value_id: u64 = @intFromPtr(ptr_arg orelse continue);
                            const free_info = FreeInfo{
                                .func_name = func_name,
                                .language = language,
                                .value_id = ptr_value_id,
                                .inst_ptr = inst,
                            };
                            if (self.free_sites.getPtr(ptr_value_id)) |list_ptr| {
                                try list_ptr.append(free_info);
                            } else {
                                var list = std.ArrayList(FreeInfo).init(self.allocator);
                                errdefer list.deinit();
                                try list.append(free_info);
                                try self.free_sites.put(ptr_value_id, list);
                            }
                            // v0.1.6: Track which BB this free is in
                            if (self.free_bb_map.getPtr(ptr_value_id)) |bb_list_ptr| {
                                try bb_list_ptr.append(bb);
                            } else {
                                var bb_list = std.ArrayList(c.LLVMBasicBlockRef).init(self.allocator);
                                errdefer bb_list.deinit();
                                try bb_list.append(bb);
                                try self.free_bb_map.put(ptr_value_id, bb_list);
                            }
                        }
                    }
                }
            }
        }

        if (self.free_sites.count() > 0) {
            diag.info("OwnershipViolation: Found {} free sites", .{self.free_sites.count()});
        }
    }

    fn detectDoubleFree(self: *FFIAnalysisPass, _: *DiagnosticWriter) !void {
        // Check each pointer to see if it was freed multiple times
        var iter = self.free_sites.iterator();
        while (iter.next()) |entry| {
            const free_list = entry.value_ptr.*;

            // If a pointer was freed more than once, it's a double free
            if (free_list.items.len > 1) {
                const first_free = free_list.items[0];
                try self.violations.append(.{
                    .violation_type = .double_free,
                    .severity = .critical,
                    .function_name = first_free.func_name,
                    .description = "Potential double free detected: pointer freed multiple times",
                    .confidence = 0.9,
                });
            }
        }
    }

    fn detectOwnershipMismatch(self: *FFIAnalysisPass, _: *DiagnosticWriter) !void {
        // H21 FIX: Optimize from O(N×M) Cartesian product to O(N+M) using HashMap index.
        // Previous implementation nested loops over all allocations × all frees,
        // comparing every pair regardless of pointer identity.
        // New approach: Index free sites by pointer, only compare matching pairs.

        // Build index: ptr_value → []FreeInfo
        var free_index = std.AutoHashMap(u64, usize).init(self.allocator);
        defer free_index.deinit();

        {
            var free_iter = self.free_sites.iterator();
            var idx: usize = 0;
            while (free_iter.next()) |entry| {
                const ptr_val = entry.key_ptr.*;
                try free_index.put(ptr_val, idx);
                idx += 1;
            }
        }

        // Now iterate allocations and check only matching frees
        var alloc_iter = self.allocation_sites.iterator();
        while (alloc_iter.next()) |alloc_entry| {
            const ptr_val = alloc_entry.key_ptr.*;
            const alloc_info = alloc_entry.value_ptr.*;

            // Only check if this pointer has corresponding frees
            if (free_index.get(ptr_val)) |free_idx| {
                const free_list = self.free_sites.items[free_idx].value_ptr.*;

                for (free_list.items) |free_info| {
                    // Check if allocation and free are from different languages
                    if (alloc_info.language != free_info.language and
                        alloc_info.language != .unknown and
                        free_info.language != .unknown)
                    {
                        try self.violations.append(.{
                            .violation_type = .ownership_mismatch,
                            .severity = .high,
                            .function_name = free_info.func_name,
                            .description = try std.fmt.allocPrint(
                                self.allocator,
                                "Cross-language free: allocated in {s}, freed in {s}",
                                .{ @tagName(alloc_info.language), @tagName(free_info.language) },
                            ),
                            .confidence = 0.85,
                            .owns_description = true,
                        });
                    }
                }
            }
            // If no matching frees found, skip (no mismatch possible)
        }
    }

    /// v0.1.6: Detect error path leaks — allocations that can reach a function
    /// return without passing through a matching free.
    ///
    /// This is a lightweight path-sensitive check using basic block tracking:
    /// - If an allocation's BB has no successor BB containing a free of the same pointer
    ///   AND the function has a ret instruction → potential error path leak
    /// - This catches patterns like:
    ///   ```
    ///   ptr = malloc(size);
    ///   if (error_condition) return;  // ← leak! (error path)
    ///   free(ptr);
    ///   ```
    fn detectErrorPathLeaks(self: *FFIAnalysisPass, _: *DiagnosticWriter) !void {
        var alloc_iter = self.allocation_sites.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc_info = entry.value_ptr.*;
            const ptr_id = alloc_info.value_id;

            const has_any_free = self.free_sites.contains(ptr_id);

            if (!has_any_free) {
                try self.violations.append(.{
                    .violation_type = .leak,
                    .severity = .high,
                    .function_name = alloc_info.func_name,
                    .description = try std.fmt.allocPrint(
                        self.allocator,
                        "Potential memory leak: allocated pointer ({d}) never freed in {s}",
                        .{ ptr_id, alloc_info.func_name },
                    ),
                    .confidence = 0.72,
                    .owns_description = true,
                });
                continue;
            }

            if (self.alloc_bb_map.get(ptr_id)) |alloc_bb| {
                const terminator = c.LLVMGetBasicBlockTerminator(alloc_bb);
                if (terminator != null) {
                    const opcode = c.LLVMGetInstructionOpcode(terminator);
                    if (opcode == c.LLVMBr) {
                        const num_successors = c.LLVMGetNumSuccessors(terminator);
                        var succ_idx: c_uint = 0;
                        while (succ_idx < num_successors) : (succ_idx += 1) {
                            const succ_bb = c.LLVMGetSuccessor(terminator, succ_idx);
                            if (self.bbHasReturnWithoutFree(succ_bb, ptr_id)) {
                                try self.violations.append(.{
                                    .violation_type = .leak,
                                    .severity = .medium,
                                    .function_name = alloc_info.func_name,
                                    .description = try std.fmt.allocPrint(
                                        self.allocator,
                                        "Error path leak: pointer ({d}) may leak on error path in {s}",
                                        .{ ptr_id, alloc_info.func_name },
                                    ),
                                    .confidence = 0.65,
                                    .owns_description = true,
                                });
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    fn bbHasReturnWithoutFree(self: *FFIAnalysisPass, bb: c.LLVMBasicBlockRef, ptr_id: u64) bool {
        const terminator = c.LLVMGetBasicBlockTerminator(bb);
        if (terminator == null) return false;

        const opcode = c.LLVMGetInstructionOpcode(terminator);
        const has_return = (opcode == c.LLVMRet);

        if (!has_return) return false;

        if (self.free_bb_map.get(ptr_id)) |free_bb_list| {
            for (free_bb_list.items) |free_bb| {
                if (@intFromPtr(free_bb) == @intFromPtr(bb)) {
                    return false;
                }
            }
        }

        return true;
    }

    /// v0.1.6: Detect cross-path double free — when frees of the same pointer
    /// occur in different basic blocks (different control flow paths).
    ///
    /// Current detectDoubleFree only checks value identity. This enhancement adds
    /// BB-level analysis to catch:
    ///   ```
    ///   if (condition_a) {
    ///       free(ptr);  // BB_1
    ///   } else {
    ///       free(ptr);  // BB_2 — same pointer, different control flow!
    ///   }
    ///   ```
    fn detectCrossPathDoubleFree(self: *FFIAnalysisPass, diag: *DiagnosticWriter) !void {
        var iter = self.free_bb_map.iterator();
        while (iter.next()) |entry| {
            const bb_list = entry.value_ptr.*;

            // If frees happen in multiple distinct basic blocks → cross-path double free
            if (bb_list.items.len > 1) {
                // Deduplicate: check if all frees are in the SAME BB
                // (that would be normal sequential code like free(x); free(y);)
                var unique_bbs = std.AutoHashMap(c.LLVMBasicBlockRef, void).init(self.allocator);
                defer unique_bbs.deinit();

                for (bb_list.items) |bb_ref| {
                    _ = try unique_bbs.put(bb_ref, {});
                }

                // Only report if frees are in 2+ DIFFERENT basic blocks
                if (unique_bbs.count() > 1) {
                    // Get first free info for reporting
                    const ptr_id = entry.key_ptr.*;
                    if (self.free_sites.get(ptr_id)) |free_list| {
                        if (free_list.items.len > 0) {
                            const first_free = free_list.items[0];
                            try self.violations.append(.{
                                .violation_type = .double_free,
                                .severity = .critical,
                                .function_name = first_free.func_name,
                                .description = try std.fmt.allocPrint(
                                    self.allocator,
                                    "Cross-path double free detected: pointer freed in {} different basic blocks (potential conditional double-free)",
                                    .{unique_bbs.count()},
                                ),
                                .confidence = 0.82,
                                .owns_description = true,
                            });
                        }
                    }

                    diag.warn("[CROSS-PATH-DOUBLE-FREE] pointer freed in {} different BBs", .{unique_bbs.count()});
                }
            }
        }
    }

    fn detectLanguageFromDwarf(func: c.LLVMValueRef) ?Language {
        if (@intFromPtr(func) == 0) return null;
        const subprogram = debug_info.getFunctionSubprogram(func) orelse return null;
        const compile_unit = subprogram.getCompileUnit() orelse return null;
        const dwarf_lang = compile_unit.getLanguage();

        return switch (dwarf_lang) {
            .C => .c,
            .C_plus_plus, .C_plus_plus_03, .C_plus_plus_11, .C_plus_plus_14, .C_plus_plus_17, .C_plus_plus_20, .C_plus_plus_23 => .cpp,
            .Rust => .rust,
            .Zig => .zig,
            .C_Sharp => .csharp,
            .Go, .Go_language => .go,
            else => null,
        };
    }

    fn detectLanguage(func_name: []const u8) Language {
        if (func_name.len >= 2) {
            if (std.mem.startsWith(u8, func_name, "_R")) {
                return .rust;
            }

            // _ZN is C++ Itanium ABI prefix, but Rust legacy v0 also used it.
            // Use isRustMangledName to disambiguate.
            if (std.mem.startsWith(u8, func_name, "_ZN")) {
                if (ffi_language_classifier.isRustMangledName(func_name)) {
                    return .rust;
                }
                return .cpp;
            }

            if (std.mem.startsWith(u8, func_name, "_Z")) {
                return .cpp;
            }
        }

        if (std.mem.indexOf(u8, func_name, "std::") != null) {
            return .cpp;
        }
        if (std.mem.indexOf(u8, func_name, "alloc::") != null) {
            return .rust;
        }
        if (std.mem.indexOf(u8, func_name, "Allocator.") != null) {
            return .zig;
        }
        if (std.mem.indexOf(u8, func_name, "UnsafeMutablePointer") != null) {
            return .csharp;
        }

        return .c;
    }

    /// Extract debug file path from LLVM subprogram metadata.
    /// Used by NoiseReduction Layer 2 (path-based filter).
    fn extractDebugFilePath(func: c.LLVMValueRef) ?[]const u8 {
        const subprogram = c.LLVMGetSubprogram(func);
        if (@intFromPtr(subprogram) == 0) return null;

        const file_ref = c.LLVMDIScopeGetFile(subprogram);
        if (@intFromPtr(file_ref) == 0) return null;

        var filename_len: c_uint = undefined;
        const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
        if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

        // Sanity check on path length
        const max_path_len: c_uint = 4096;
        if (filename_len > max_path_len) return null;
        if (filename_ptr[0] == 0) return null;

        return filename_ptr[0..filename_len];
    }

    fn detectLanguageWithDwarf(_: *FFIAnalysisPass, func: c.LLVMValueRef, func_name: []const u8) Language {
        if (detectLanguageFromDwarf(func)) |lang| {
            return lang;
        }
        return detectLanguage(func_name);
    }

    fn storeResults(self: *FFIAnalysisPass, ctx: *PassContext) !void {
        for (self.violations.items, 0..) |violation, i| {
            try ctx.fact_store.insert(
                .ownership_violation,
                @intCast(i),
                @intFromEnum(violation.violation_type),
                @intFromEnum(violation.severity),
            );
        }
    }

    pub fn getResults(self: *const FFIAnalysisPass) FFIAnalysisResult {
        const match_count = if (self.matcher) |m| m.getMatches().len else 0;

        return .{
            .match_count = match_count,
            .boundary_count = 0,
            .violation_count = self.violations.items.len,
            .violations = self.violations.items,
        };
    }
};

comptime {
    _ = Pass(FFIAnalysisPass);
}

test "FFIAnalysisPass - pass interface" {
    comptime {
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "name"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "kind"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "deps"));
        try std.testing.expect(@hasDecl(FFIAnalysisPass, "run"));
    }
}

test "FFIAnalysisPass - init and deinit" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = FFIAnalysisPass.init(std.testing.allocator, &store);
    defer pass.deinit();

    try std.testing.expect(pass.matcher == null);
    try std.testing.expectEqual(@as(usize, 0), pass.violations.items.len);
}

test "FFIAnalysisPass - detectLanguage" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = FFIAnalysisPass.init(std.testing.allocator, &store);
    defer pass.deinit();

    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_ZN4core3ptr"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_R"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZN4Base1fEv"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZNSt3__110unique_ptr"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZSt"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.c, pass.detectLanguage("malloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.zig, pass.detectLanguage("Allocator.alloc"));
}

test "FFIAnalysisPass - name is ownership-violation" {
    try std.testing.expectEqualStrings("ownership-violation", FFIAnalysisPass.name);
}

test "FFIAnalysisPass - detectLanguage fallback" {
    var fact_store = @import("../../../fact/store.zig").FactStore.init(std.testing.allocator);
    defer fact_store.deinit();
    var pass = FFIAnalysisPass.init(std.testing.allocator, &fact_store);
    defer pass.deinit();

    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_ZN4core3ptr"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_R"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZN4Base1fEv"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZSt"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.c, pass.detectLanguage("malloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.zig, pass.detectLanguage("Allocator.alloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.csharp, pass.detectLanguage("UnsafeMutablePointer"));
}

test "FFIAnalysisPass - detectLanguageFromDwarf with null returns null" {
    const result = FFIAnalysisPass.detectLanguageFromDwarf(null);
    try std.testing.expect(result == null);
}
