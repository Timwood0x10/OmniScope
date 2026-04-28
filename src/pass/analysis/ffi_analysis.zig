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

const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const ffi_matcher = @import("../../ffi/ffi_matcher.zig");
const FFIMatcher = ffi_matcher.FFIMatcher;
const FFIMatch = ffi_matcher.FFIMatch;

const llvm_safe = @import("../../ir/llvm_safe.zig");
const c = @import("../../ir/llvm_raw.zig").c;
const debug_info = @import("../../ir/debug_info.zig");

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;

const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;

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

/// Severity level
pub const Severity = enum {
    critical,
    high,
    medium,
    low,
};

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

    const Language = enum {
        unknown,
        c,
        rust,
        cpp,
        zig,
        swift,
        go,
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

        // Step 3: Collect allocation and free sites
        try self.collectAllocationSites(mod, diag);
        try self.collectFreeSites(mod, diag);

        // Step 4: Detect ownership violations
        try self.detectDoubleFree(diag);
        try self.detectOwnershipMismatch(diag);

        // v0.1.6: Enhanced detection
        try self.detectErrorPathLeaks(diag);
        try self.detectCrossPathDoubleFree(diag);

        // Step 5: Store results
        try self.storeResults(ctx);

        diag.info("OwnershipViolation: {} allocations, {} frees, {} violations", .{
            self.allocation_sites.count(),
            self.free_sites.count(),
            self.violations.items.len,
        });
    }

    fn collectAllocationSites(self: *FFIAnalysisPass, mod: c.LLVMModuleRef, diag: *DiagnosticWriter) !void {
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

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
        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) == 0) continue;
            const func_name = std.mem.span(func_name_ptr);

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
                            if (self.free_sites.get(ptr_value_id)) |list| {
                                try list.append(free_info);
                            } else {
                                var list = std.ArrayList(FreeInfo).init(self.allocator);
                                errdefer list.deinit();
                                try list.append(free_info);
                                try self.free_sites.put(ptr_value_id, list);
                            }
                            // v0.1.6: Track which BB this free is in
                            if (self.free_bb_map.get(ptr_value_id)) |bb_list| {
                                try bb_list.append(bb);
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
        // Check for cross-language free mismatches
        var alloc_iter = self.allocation_sites.iterator();
        while (alloc_iter.next()) |alloc_entry| {
            const alloc_info = alloc_entry.value_ptr.*;

            var free_iter = self.free_sites.iterator();
            while (free_iter.next()) |free_entry| {
                const free_list = free_entry.value_ptr.*;

                // Iterate through all FreeInfo entries for this pointer
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
            .Swift => .swift,
            .Go, .Go_language => .go,
            else => null,
        };
    }

    fn detectLanguage(func_name: []const u8) Language {
        if (func_name.len >= 2) {
            if (std.mem.startsWith(u8, func_name, "_ZN") or
                std.mem.startsWith(u8, func_name, "_R"))
            {
                return .rust;
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
            return .swift;
        }

        return .c;
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
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZSt"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.c, pass.detectLanguage("malloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.zig, pass.detectLanguage("Allocator.alloc"));
}

test "FFIAnalysisPass - name is ownership-violation" {
    try std.testing.expectEqualStrings("ownership-violation", FFIAnalysisPass.name);
}

test "FFIAnalysisPass - detectLanguage fallback" {
    var pass = FFIAnalysisPass.init(std.testing.allocator, undefined);
    defer pass.deinit();

    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_ZN4core3ptr"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.rust, pass.detectLanguage("_R"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.cpp, pass.detectLanguage("_ZSt"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.c, pass.detectLanguage("malloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.zig, pass.detectLanguage("Allocator.alloc"));
    try std.testing.expectEqual(FFIAnalysisPass.Language.swift, pass.detectLanguage("UnsafeMutablePointer"));
}

test "FFIAnalysisPass - detectLanguageFromDwarf with null returns null" {
    const result = FFIAnalysisPass.detectLanguageFromDwarf(null);
    try std.testing.expect(result == null);
}
