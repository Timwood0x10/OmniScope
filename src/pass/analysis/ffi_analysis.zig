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
    pub const deps = &[_][]const u8{ "cfg", "dfg", "taint" };

    allocator: Allocator,
    store: *FactStore,
    matcher: ?FFIMatcher,
    violations: std.ArrayList(OwnershipViolation),

    /// Track allocation sites: ptr_value_id -> allocation info
    allocation_sites: std.AutoHashMap(u64, AllocationInfo),

    /// Track free sites: ptr_value_id -> free info
    free_sites: std.AutoHashMap(u64, FreeInfo),

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
    };

    pub fn init(allocator: Allocator, store: *FactStore) FFIAnalysisPass {
        return .{
            .allocator = allocator,
            .store = store,
            .matcher = null,
            .violations = std.ArrayList(OwnershipViolation).init(allocator),
            .allocation_sites = std.AutoHashMap(u64, AllocationInfo).init(allocator),
            .free_sites = std.AutoHashMap(u64, FreeInfo).init(allocator),
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
        self.free_sites.deinit();
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

            const language = self.detectLanguage(func_name);

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
                        if (sem.kind == .memory_alloc) {
                            const ptr_value_id = @as(u64, @truncate(@intFromPtr(inst)));
                            try self.allocation_sites.put(ptr_value_id, .{
                                .func_name = func_name,
                                .language = language,
                                .value_id = ptr_value_id,
                                .inst_ptr = inst,
                            });
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

            const language = self.detectLanguage(func_name);

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

                    // Check if this is a free function
                    if (SemanticRegistry.lookup(called_name)) |sem| {
                        if (sem.kind == .memory_free) {
                            const ptr_value_id = @as(u64, @truncate(@intFromPtr(inst)));
                            try self.free_sites.put(ptr_value_id, .{
                                .func_name = func_name,
                                .language = language,
                                .value_id = ptr_value_id,
                                .inst_ptr = inst,
                            });
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
        // Group free sites by the pointer they free
        // For simplicity, we track by function name patterns

        var iter = self.free_sites.iterator();
        while (iter.next()) |entry| {
            const free_info = entry.value_ptr.*;

            // Check if there's another free for the same allocation
            // This is a simplified check - real implementation would need data flow
            var inner_iter = self.free_sites.iterator();
            while (inner_iter.next()) |inner_entry| {
                if (entry.key_ptr.* == inner_entry.key_ptr.*) continue;

                const other_free = inner_entry.value_ptr.*;
                if (std.mem.eql(u8, free_info.func_name, other_free.func_name)) {
                    // Same function freeing multiple times - potential double free
                    try self.violations.append(.{
                        .violation_type = .double_free,
                        .severity = .critical,
                        .function_name = free_info.func_name,
                        .description = "Potential double free detected",
                        .confidence = 0.7,
                    });
                    break;
                }
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
                const free_info = free_entry.value_ptr.*;

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

    fn detectLanguage(_: *FFIAnalysisPass, func_name: []const u8) Language {
        // Rust mangled names start with _ZN or _R
        if (func_name.len >= 2) {
            if (std.mem.startsWith(u8, func_name, "_ZN") or
                std.mem.startsWith(u8, func_name, "_R"))
            {
                return .rust;
            }

            // C++ mangled names start with _Z
            if (std.mem.startsWith(u8, func_name, "_Z")) {
                return .cpp;
            }
        }

        // Check for language-specific patterns
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
