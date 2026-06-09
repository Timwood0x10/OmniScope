//! PassContext method implementations
//!
//! Extracted from pass_types.zig to keep file under 600 lines.
//! Uses @This() pattern: when these functions are re-exported inside
//! the PassContext struct via pub const, Zig resolves @This() to the
//! enclosing PassContext type, allowing field access.

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const zone_classifier = @import("../semantics/zone_classifier.zig");
const noise_filter = @import("../semantics/noise_filter.zig");
const surface_classifier = @import("../semantics/surface_classifier/surface_classifier.zig");
const language_detector = @import("../semantics/language_detector.zig");
const ffi_enhancement = @import("../pass/analysis/ffi/ffi_enhancement.zig");
const ir_evidence = @import("../ir/ir_evidence.zig");
const issue_suppression = @import("../pass/analysis/noise/issue_suppression.zig");
const suppression_patterns = @import("../pass/analysis/noise/suppression_patterns.zig");
const issue_classification = @import("../filter/issue_classification.zig");
const filter_context_mod = @import("../filter/filter_context.zig");
const FilterContext = filter_context_mod.FilterContext;
const Issue = @import("../diag/issue.zig").Issue;
const DiagSeverity = @import("../diag/issue.zig").Severity;
const SemanticSurface = @import("../common/types.zig").SemanticSurface;
const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;
const language_override = @import("../config/language_override.zig");

const MemoryGraph = @import("../semantics/memory_graph.zig").MemoryGraph;
const DangerSurface = @import("../types/memory_graph_types.zig").DangerSurface;

const PassContext = @import("../types/pass_types.zig").PassContext;
const ChannelMode = @import("../types/pass_types.zig").ChannelMode;

pub fn getNextId(self: *PassContext) u32 {
    return self.next_id.fetchAdd(1, .seq_cst);
}

pub fn getValueId(self: *PassContext, ptr: usize) !u32 {
    return self.value_id_map.getOrPutId(ptr);
}

pub fn getNextVulnId(self: *PassContext) u32 {
    return self.vuln_id.fetchAdd(1, .seq_cst) + 1;
}

pub fn recordDegradedFunction(self: *PassContext) void {
    _ = self.degraded_functions.fetchAdd(1, .seq_cst);
}

pub fn getDegradedFunctionCount(self: *const PassContext) u32 {
    return self.degraded_functions.load(.seq_cst);
}

pub fn getFunctionSurface(self: *const PassContext, func_ptr: u64) ?surface_classifier.FunctionSurface {
    return self.function_surface.get(func_ptr);
}

pub fn lookupFunctionLanguage(self: *const PassContext, func_name: []const u8) ?language_override.Language {
    if (self.language_overrides) |reg| {
        return reg.lookup(func_name);
    }
    return null;
}

pub fn getDefaultLanguage(self: *const PassContext) ?language_override.Language {
    if (self.language_overrides) |reg| {
        return reg.getDefault();
    }
    return null;
}

pub fn shouldAnalyzeFunctionSurface(self: *const PassContext, func_ptr: u64) bool {
    const surf = self.getFunctionSurface(func_ptr) orelse return true;
    return surf.shouldAnalyze();
}

pub fn shouldAnalyzeFunctionSurfaceByName(self: *PassContext, func_name: []const u8, func_ptr: ?u64) bool {
    if (func_ptr) |ptr| {
        if (self.function_surface.get(ptr)) |surf| {
            return surf.shouldAnalyze();
        }
    }
    if (self.module) |mod| {
        const raw_mod = mod.raw;
        const func = c.LLVMGetNamedFunction(raw_mod, func_name.ptr);
        if (@intFromPtr(func) != 0) {
            const ptr = @as(u64, @intFromPtr(func));
            if (self.function_surface.get(ptr)) |surf| {
                return surf.shouldAnalyze();
            }
        }
    }
    return true;
}

pub fn classifyFunctionSurface(
    self: *PassContext,
    func_name: []const u8,
    source_location: ?@import("../ir/debug_info.zig").SourceLocation,
) noise_filter.ClassificationResult {
    _ = source_location;

    if (isZigStdlibFunctionImpl(func_name)) {
        return .{
            .origin = .stdlib,
            .risk_level = noise_filter.getRiskLevel(.stdlib, .medium),
            .reason = "Zig standard library (prefix match)",
        };
    }

    if (self.module) |mod| {
        const raw_mod = mod.raw;
        const func = c.LLVMGetNamedFunction(raw_mod, func_name.ptr);
        if (@intFromPtr(func) != 0) {
            const ptr = @as(u64, @intFromPtr(func));
            if (self.function_surface.get(ptr)) |surf| {
                const nf_origin = noise_filter.functionSurfaceToOrigin(surf);
                return .{
                    .origin = nf_origin,
                    .risk_level = noise_filter.getRiskLevel(nf_origin, .medium),
                    .reason = "surface-classifier cache",
                };
            }
        }
    }

    const fn_origin_heuristic = ffi_enhancement.classifyFunctionOrigin(func_name);
    const fn_origin: noise_filter.FunctionOrigin = switch (fn_origin_heuristic) {
        .user => .user,
        .stdlib => .stdlib,
        .compiler_generated => .compiler_generated,
        .third_party => .third_party,
        .unknown => .unknown,
    };
    if (fn_origin != .unknown) {
        return .{
            .origin = fn_origin,
            .risk_level = noise_filter.getRiskLevel(fn_origin, .medium),
            .reason = "name-based heuristic fallback",
        };
    }

    return .{
        .origin = .unknown,
        .risk_level = .medium,
        .reason = "unclassified (no cache hit, no name pattern match)",
    };
}

pub fn inferSemanticSurface(func_name: []const u8, origin: noise_filter.FunctionOrigin) ?SemanticSurface {
    const zone = zone_classifier.classifyFunction(func_name, null);

    const surface: SemanticSurface = switch (origin) {
        .user => .boundary,
        .stdlib => .internal_core,
        .compiler_generated => .runtime_internal,
        .third_party => .internal_core,
        .unknown => blk: {
            break :blk switch (zone) {
                .unsafe, .ffi => .boundary,
                .safe => .internal_core,
                .runtime_internal => .runtime_internal,
                .unknown => .unknown,
            };
        },
    };

    const is_ffi_producer = isFFIProducerPattern(func_name);
    if (is_ffi_producer and surface == .internal_core) {
        return .ffi_producer;
    }

    return surface;
}

fn isFFIProducerPattern(func_name: []const u8) bool {
    if (std.mem.indexOf(u8, func_name, "alloc") != null) return true;
    if (std.mem.indexOf(u8, func_name, "malloc") != null) return true;
    if (std.mem.indexOf(u8, func_name, "create") != null) return true;
    if (std.mem.indexOf(u8, func_name, "marshal") != null) return true;
    if (std.mem.indexOf(u8, func_name, "serialize") != null) return true;
    if (std.mem.indexOf(u8, func_name, "pack") != null) return true;
    return false;
}

pub fn setModule(self: *PassContext, module: ModuleRef) void {
    self.module = module;
}

pub fn hasModule(self: *const PassContext) bool {
    return self.module != null;
}

pub fn getDataFlowGraph(self: *const PassContext) *DataFlowGraph {
    return self.data_flow_graph;
}

pub fn addNode(self: *PassContext, node: anytype) !void {
    try self.data_flow_graph.addNode(node);
}

pub fn addEdge(self: *PassContext, edge: anytype) !void {
    try self.data_flow_graph.addEdge(edge);
}

pub fn addFFIBoundary(self: *PassContext, boundary: anytype) !void {
    try self.data_flow_graph.addFFIBoundary(boundary);
}

pub fn addIssue(self: *PassContext, issue: *const Issue) !void {
    const profile_ptr = if (self.platform_profile) |*p| p else null;
    if (issue_suppression.shouldSuppressWithProfile(issue, profile_ptr)) {
        if (suppression_patterns.isStdlibInternalFunction(issue)) {
            self.suppression_stats.record(.stdlib_internal);
        } else {
            self.suppression_stats.record(.drop_chain);
        }
        if (issue.owned) {
            var mutable_issue = issue.*;
            mutable_issue.deinit(self.allocator);
        }
        return;
    }

    var ctx = FilterContext.init(issue);
    ctx.is_pure_c_module = self.isCModule();

    const classification = self.classifyFunctionSurface(ctx.func_name, null);
    ctx.origin = classification.origin;
    ctx.computeRisk();

    ctx.surface = inferSemanticSurface(ctx.func_name, ctx.origin);

    ctx.has_boundary_evidence = ctx.has_ffi_boundary or switch (issue.kind) {
        .cross_language_free,
        .cross_language_leak,
        .ffi_unsafe_call,
        .ffi_type_mismatch,
        .borrow_escape,
        => true,
        else => false,
    };

    ctx.applySurfaceDowngrade();
    ctx.applyNoiseFilter();

    const dedup_key = dedupKey(self, issue);
    if (issue.severity != .critical) {
        const gop = try self.reported_keys.getOrPut(dedup_key);
        if (gop.found_existing) {
            ctx.is_duplicate = true;
        }
    }

    if (!ctx.shouldReport()) {
        if (issue.owned) {
            var mutable_issue = issue.*;
            mutable_issue.deinit(self.allocator);
        }
        return;
    }

    var final_issue = issue.*;
    final_issue.severity = ctx.getFinalSeverity();
    final_issue.semantic_surface = ctx.surface;
    final_issue.classification = ctx.deriveClassification();

    if (!final_issue.owned) {
        const cloned_msg = try self.allocator.dupe(u8, final_issue.message);
        final_issue.message = cloned_msg;
        final_issue.owned = true;
    }
    try self.data_flow_graph.addIssue(final_issue);
}

fn dedupKey(self: *PassContext, issue: *const Issue) u64 {
    _ = self;
    const loc = @field(issue, "location");
    const kind_tag = @tagName(@field(issue, "kind"));
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(loc.func);
    hasher.update(kind_tag);
    if (loc.file) |f| hasher.update(f);
    if (loc.line > 0) hasher.update(&std.mem.toBytes(loc.line));
    if (loc.column > 0) hasher.update(&std.mem.toBytes(loc.column));
    return hasher.final();
}

pub fn cachedRegistryLookup(self: *PassContext, func_name: []const u8) ?FunctionSemantics {
    if (self.registry_cache.get(func_name)) |sem| {
        return sem;
    }
    const sem = SemanticRegistry.lookup(func_name) orelse return null;
    self.registry_cache.put(func_name, sem) catch |err| {
        log.warn("[pass-types] registry_cache.put OOM for '{s}': {}", .{ func_name, err });
    };
    return sem;
}

pub fn cachedZoneLookup(self: *PassContext, func_name: []const u8) ?zone_classifier.ZoneKind {
    return self.zone_cache.get(func_name);
}

pub fn cacheZoneResult(self: *PassContext, func_name: []const u8, zone: zone_classifier.ZoneKind) void {
    self.zone_cache.put(func_name, zone) catch |err| {
        log.warn("[pass-types] zone_cache.put OOM for '{s}': {}", .{ func_name, err });
    };
}

pub fn getOrComputeZone(self: *PassContext, func: *anyopaque, func_name: []const u8) zone_classifier.ZoneKind {
    const func_addr = @intFromPtr(func);
    if (func_addr == 0) return .unknown;
    return self.cachedZoneLookup(func_name) orelse blk: {
        const z = zone_classifier.classifyFunctionFromLLVM(@ptrCast(func), func_name);
        self.cacheZoneResult(func_name, z);
        break :blk z;
    };
}

pub fn shouldAnalyzeZone(zone: zone_classifier.ZoneKind) bool {
    return switch (zone) {
        .safe => false,
        .runtime_internal => false,
        .unknown => true,
        .unsafe => true,
        .ffi => true,
    };
}

pub fn initModuleLanguage(self: *PassContext, module_ref: ?ModuleRef) void {
    if (self.language_detected) return;
    if (module_ref == null or self.module == null) {
        self.module_language = language_detector.LanguageProfile.initSingle(.unknown, 0.0, .unknown);
        self.language_detected = true;
        return;
    }

    const llvm_module = if (self.module) |m|
        m.raw
    else
        @as(c.LLVMModuleRef, @ptrFromInt(0));

    if (@intFromPtr(llvm_module) == 0) {
        self.module_language = language_detector.LanguageProfile.initSingle(.unknown, 0.0, .unknown);
        self.language_detected = true;
        return;
    }

    self.module_language = language_detector.detectModuleLanguage(llvm_module, self.allocator);
    self.language_detected = true;

    if (self.module_language.language == .unknown or self.module_language.confidence < 0.6) {
        if (self.getDefaultLanguage()) |default_lang| {
            if (default_lang != .unknown) {
                log.debug("[pass-types] LANG-OVERRIDE: Using default_lang={s} (auto-detection confidence too low)", .{
                    @tagName(default_lang),
                });
                self.module_language = language_detector.LanguageProfile.initSingle(default_lang, 0.8, .unknown);
            }
        }
    }

    if (self.evidence == null) {
        var evidence_collector = ir_evidence.EvidenceCollector.init(self.allocator, llvm_module) catch |err| {
            log.warn("[pass-types] Evidence collection failed: {}", .{err});
            return;
        };
        defer evidence_collector.deinit();
        self.evidence = evidence_collector.getEvidence().*;
    }

    // T8: Log secondary languages for multi-language modules
    const sec_count = self.module_language.secondary_languages.len;
    if (sec_count > 0) {
        log.debug("[pass-types] LANG-DETECT: module language = {s}, confidence = {d:.1}%, method = {s}, secondary_languages = {}", .{
            @tagName(self.module_language.language),
            self.module_language.confidence * 100,
            @tagName(self.module_language.method),
            sec_count,
        });
    } else {
        log.debug("[pass-types] LANG-DETECT: module language = {s}, confidence = {d:.1}%, method = {s}", .{
            @tagName(self.module_language.language),
            self.module_language.confidence * 100,
            @tagName(self.module_language.method),
        });
    }
}

pub fn getModuleLanguage(self: *const PassContext) language_detector.LanguageProfile {
    return self.module_language;
}

pub fn isGoModule(self: *const PassContext) bool {
    return self.module_language.language == .go;
}

pub fn isRustModule(self: *const PassContext) bool {
    return self.module_language.language == .rust;
}

pub fn isZigModule(self: *const PassContext) bool {
    return self.module_language.language == .zig;
}

/// T8: A "C module" check now returns false when the module has secondary languages.
/// This prevents skipping FFI boundary detection on mixed-language modules
/// (e.g., C module with C++ declares, or C bridge calling C++ symbols).
/// Use isCModuleStrict() for legacy behavior that ignores secondary languages.
pub fn isCModule(self: *const PassContext) bool {
    if (self.module_language.isMultiLanguage()) return false;
    return self.module_language.language == .c or self.module_language.language == .cpp;
}

/// Legacy C module check that ignores secondary languages (T8).
/// Use only for pure language identification, not FFI skip decisions.
pub fn isCModuleStrict(self: *const PassContext) bool {
    return self.module_language.language == .c or self.module_language.language == .cpp;
}

pub fn isUnknownModule(self: *const PassContext) bool {
    return self.module_language.language == .unknown;
}

pub fn getOrComputeZoneByName(self: *PassContext, func_name: []const u8) zone_classifier.ZoneKind {
    return self.cachedZoneLookup(func_name) orelse blk: {
        const z = zone_classifier.classifyFunction(func_name, null);
        self.cacheZoneResult(func_name, z);
        break :blk z;
    };
}

pub fn markTainted(self: *PassContext, node_id: u32, source_id: ?u32) !void {
    try self.data_flow_graph.markTainted(node_id, source_id);
}

pub fn isTainted(self: *const PassContext, node_id: u32) bool {
    return self.data_flow_graph.isTainted(node_id);
}

pub fn isRelevantAlloc(self: *const PassContext, ptr_val: u64) bool {
    if (self.danger_surface_relevant.contains(ptr_val)) return true;
    if (self.ffi_auto_relevant.count() == 0) return false;
    return self.ffi_auto_relevant.contains(ptr_val);
}

pub fn isOnDangerPathFull(self: *PassContext, ptr_val: u64) bool {
    const raw_ffis = self.getCrossLangEdges();
    if (raw_ffis.len == 0) return self.isRelevantAlloc(ptr_val);

    if (self.ffi_set_cache == null) {
        var ffi_set = std.StringHashMap(void).init(self.allocator);
        for (raw_ffis) |ffe| {
            if (ffe.is_ffi_boundary) {
                ffi_set.put(ffe.callee_name, {}) catch {
                    ffi_set.deinit();
                    return false;
                };
            }
        }
        self.ffi_set_cache = ffi_set;
    }

    if (self.danger_surfaces_cache == null) {
        const surfaces = self.allocator.alloc(DangerSurface, raw_ffis.len) catch return false;
        for (raw_ffis, 0..) |ffe, i| {
            surfaces[i] = .{
                .callee_name = ffe.callee_name,
                .is_ffi_boundary = ffe.is_ffi_boundary,
            };
        }
        self.danger_surfaces_cache = surfaces;
    }

    if (self.danger_path_visited_cache == null) {
        self.danger_path_visited_cache = std.AutoHashMap(u64, void).init(self.allocator);
    }
    self.danger_path_visited_cache.?.clearRetainingCapacity();

    const result = self.memory_graph.isOnDangerPath(ptr_val, self.danger_surfaces_cache.?, &self.danger_path_visited_cache.?, &self.ffi_set_cache.?);
    return result != .none;
}

pub fn markRelevantAlloc(self: *PassContext, ptr_val: u64) !void {
    try self.danger_surface_relevant.put(ptr_val, {});
}

pub fn markFfiRelevant(self: *PassContext, ptr_val: u64) !void {
    try self.ffi_auto_relevant.put(ptr_val, {});
}

pub fn isRelevantFunction(self: *const PassContext, func_ptr: u64) bool {
    return self.relevant_functions.contains(func_ptr);
}

pub fn markRelevantFunction(self: *PassContext, func_ptr: u64) !void {
    try self.relevant_functions.put(func_ptr, {});
}

pub fn markFunctionFromInst(self: *PassContext, inst_ptr: u64) !void {
    if (inst_ptr == 0) return;

    const inst = @as(c.LLVMValueRef, @ptrFromInt(inst_ptr));
    if (@intFromPtr(inst) == 0) return;

    const bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(bb) == 0) return;

    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return;

    const func_ptr = @as(u64, @intFromPtr(func));
    try self.relevant_functions.put(func_ptr, {});
}

pub fn internString(self: *PassContext, s: []const u8) ![]const u8 {
    if (self.interner) |*intr| {
        return intr.intern(s);
    }
    return self.allocator.dupe(u8, s);
}

pub fn enableInterning(self: *PassContext) !void {
    if (self.interner == null) {
        self.interner = @import("../common/string_interner.zig").StringInterner.init(self.allocator);
    }
}

pub fn enableArena(self: *PassContext) !void {
    if (self.arena == null) {
        self.arena = @import("../common/arena.zig").Arena.init(self.allocator);
    }
}

pub fn arenaAlloc(self: *PassContext) std.mem.Allocator {
    if (self.arena) |*a| {
        return @import("../common/arena.zig").arenaAllocator(a);
    }
    return self.allocator;
}

pub fn resetArena(self: *PassContext) void {
    if (self.arena) |*a| {
        a.reset();
    }
}

pub fn isZigStdlibFunction(self: *const PassContext, func_name: []const u8) bool {
    _ = self;
    return isZigStdlibFunctionImpl(func_name);
}

/// Check if a function name is a Zig stdlib function.
/// Uses prefix/substring matching against known stdlib patterns.
fn isZigStdlibFunctionImpl(func_name: []const u8) bool {
    const PrefixTrie = @import("../common/prefix_trie.zig").PrefixTrie;

    const stdlib_prefixes_group1 = [_][]const u8{
        "debug.",          "heap.",           "mem.",         "fmt.",          "io.",          "posix.",
        "hash_map.",       "array_hash_map.", "array_list.",  "sort.",         "bitmap.",      "crypto.",
        "log.",            "time.",           "fs.",          "net.",          "process.",     "async.",
        "event_loop.",     "unicode",         "math.",        "random",        "compress",     "hmac",
        "aead",            "aes",             "io.writer",    "io.reader",     "io.stream",    "debug.dwarf",
        "debug.info",      "debug.format",    "loop.",        "fs.file",       "fs.path",      "crypto.chacha",
        "crypto.salsa",    "math.big",        "math.complex", "compress.zlib", "compress.lz4", "unicode.utf8view",
        "unicode.utf16le",
    };

    const trie1 = comptime PrefixTrie.init(&stdlib_prefixes_group1, .substring);
    if (trie1.contains(func_name)) return true;

    const stdlib_prefixes_group2 = [_][]const u8{
        ".dwarf",          "crypto.curve",  "compress.xz",
        "unicode.utf16be", "unicode.ascii", ".buffer",
        ".queue",          ".stack",        ".allocator",
        ".arena",          ".gpa",
    };

    const trie2 = comptime PrefixTrie.init(&stdlib_prefixes_group2, .substring);
    if (trie2.contains(func_name)) return true;

    return looksLikeInternalZigFunction(func_name);
}

fn looksLikeInternalZigFunction(func_name: []const u8) bool {
    if (std.mem.indexOf(u8, func_name, ".") == null) return false;
    if (func_name.len < 15) return false;

    const internal_markers = [_][]const u8{
        ".debug.", ".dwarf", ".writer", ".reader",
        ".hash_",  ".alloc", ".format",
    };

    for (internal_markers) |marker| {
        if (std.mem.indexOf(u8, func_name, marker) != null) {
            if (!looksLikeUserCode(func_name)) {
                return true;
            }
        }
    }

    return false;
}

fn looksLikeUserCode(func_name: []const u8) bool {
    const user_prefixes = [_][]const u8{
        "main", "test", "my", "app", "user", "handle", "callback", "wrapper",
    };

    for (user_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            const dot_count = countChar(func_name, '.');
            if (dot_count <= 1) {
                return true;
            }
        }
    }

    return false;
}

fn countChar(s: []const u8, char: u8) usize {
    var count: usize = 0;
    for (s) |ch| {
        if (ch == char) count += 1;
    }
    return count;
}

// =====================================================================
// Channel mode gating (Wave 3: moved from pass_types.zig)
// =====================================================================

pub fn channelFFIBoundary(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .limited,
        .go => .limited,
        .c, .cpp => .limited,
        else => .full,
    };
}

pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .limited,
        .go => .limited,
        else => .full,
    };
}

pub fn channelCallbackEscape(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .limited,
        else => .full,
    };
}

pub fn channelPointerOwnership(self: *const PassContext) ChannelMode {
    return switch (self.module_language.language) {
        .zig => .limited,
        .go => .limited,
        else => .full,
    };
}

// =====================================================================
// Cross-language edge management (Wave 3: moved from pass_types.zig)
// =====================================================================

pub fn addCrossLangEdge(self: *PassContext, edge: @import("../types/pass_types.zig").CrossLangEdge) !void {
    const idx = @as(u32, @intCast(self.cross_lang_edges.items.len));
    try self.cross_lang_edges.append(self.allocator, edge);
    const gop = try self.cross_edge_by_callee.getOrPut(edge.callee_name);
    if (!gop.found_existing) {
        gop.value_ptr.* = try std.ArrayList(u32).initCapacity(self.allocator, 4);
    }
    try gop.value_ptr.*.append(self.allocator, idx);
}

pub fn getCrossLangEdges(self: *const PassContext) []const @import("../types/pass_types.zig").CrossLangEdge {
    return self.cross_lang_edges.items;
}

pub fn getCrossEdgeByCallee(self: *const PassContext, callee_name: []const u8) ?*const @import("../types/pass_types.zig").CrossLangEdge {
    if (self.cross_edge_by_callee.get(callee_name)) |indices| {
        if (indices.items.len > 0) {
            return &self.cross_lang_edges.items[indices.items[0]];
        }
    }
    return null;
}

pub fn getAllCrossEdgesByCallee(self: *const PassContext, callee_name: []const u8) ?[]const u32 {
    if (self.cross_edge_by_callee.get(callee_name)) |indices| {
        return indices.items;
    }
    return null;
}
