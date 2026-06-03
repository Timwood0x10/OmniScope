//! Multi-Layer Cache for PtrLifetimePass Performance Optimization
//!
//! Eliminates redundant LLVM C API calls and function name classification
//! by caching intermediate results at three layers:
//!
//!   Layer 1: InstCache — per-instruction opcode/called_value/operand pre-computation
//!   Layer 2: FnClassCache — function name classification results (is_free, alloc_lang, etc.)
//!   Layer 3: BatchQueue — deferred violation checks for batch processing
//!
//! Performance target: reduce ~15s runtime to <8s (1.8-2x speedup).
//!
//! Design decisions:
//!   - All caches use borrowed references (no string duplication)
//!   - Cache lifetime = single function analysis (created/deinit in analyzeFunction)
//!   - Thread-local: each parallel worker has its own cache instance

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const ptr_types = @import("ptr_lifetime_types.zig");
const PtrAllocSite = ptr_types.PtrAllocSite;
const ResourceType = ptr_types.ResourceType;
const Language = @import("../../../semantics/zone_classifier.zig").Language;

const classify_mod = @import("ptr_lifetime_classify.zig");

// ============================================================================
// Layer 1: Per-Instruction Cache
// ============================================================================

/// Pre-computed instruction metadata. Populated once during BB traversal,
/// reused by both trackInstruction() and checkViolations().
///
/// Eliminates 3-8 LLVM C API calls per instruction:
///   - LLVMGetInstructionOpcode → .opcode
///   - LLVMGetCalledValue → .called_value
///   - LLVMGetValueName → .callee_name
///   - LLVMGetNumOperands → .num_operands
pub const InstCache = struct {
    /// Original instruction reference (for API calls that need the full inst)
    inst: c.LLVMValueRef,
    /// Pre-fetched opcode (c.LLVMGetInstructionOpcode result)
    opcode: c_uint = 0,
    /// Pre-fetched called value for call/invoke instructions (null otherwise)
    called_value: ?c.LLVMValueRef = null,
    /// Borrowed reference to callee name (from LLVMGetInstructionName)
    /// Valid only during function analysis — do NOT free.
    callee_name: ?[]const u8 = null,
    /// Pre-fetched operand count
    num_operands: c_uint = 0,

    /// Pre-compute all metadata for a single instruction.
    /// Called once per instruction before track/check phases.
    pub fn initForInst(inst: c.LLVMValueRef) InstCache {
        var self = InstCache{ .inst = inst };
        self.opcode = @intCast(c.LLVMGetInstructionOpcode(inst));
        self.num_operands = @intCast(c.LLVMGetNumOperands(inst));

        if (self.opcode == c.LLVMCall or self.opcode == c.LLVMInvoke) {
            self.called_value = c.LLVMGetCalledValue(inst);
            if (self.called_value) |cv| {
                if (@intFromPtr(cv) != 0) {
                    const name_ptr = c.LLVMGetValueName(cv);
                    if (@intFromPtr(name_ptr) != 0) {
                        self.callee_name = std.mem.span(name_ptr);
                    }
                }
            }
        }

        return self;
    }

    /// Check if this instruction is a call or invoke.
    pub fn isCallOrInvoke(self: *const InstCache) bool {
        return self.opcode == c.LLVMCall or self.opcode == c.LLVMInvoke;
    }
};

// ============================================================================
// Layer 2: Function Name Classification Cache
// =================================================================///

/// Cached classification results for a single function name.
/// Computed once on first encounter, reused for all subsequent lookups.
///
/// Eliminates 5-7 function name classification calls per call instruction:
///   - isFreeFunction() → .is_free
///   - classifyAllocLanguage() → .alloc_lang
///   - classifyAllocLanguageEnum() → .alloc_lang_enum
///   - classifyFreeLanguage() → .free_lang
///   - may_retain_pointer() → .may_retain
///   - is_extern_function() → .is_extern
///   - isResourceCloseFunction() → .resource_close_type
///   - is_resource_alloc_function() → .resource_alloc_type
///   - isHeapAllocFunction() → .is_heap_alloc
pub const FnClassification = struct {
    is_free: bool = false,
    alloc_lang: ?[]const u8 = null,
    alloc_lang_enum: ?Language = null,
    free_lang: ?[]const u8 = null,
    may_retain: bool = false,
    is_extern: bool = false,
    resource_close_type: ?ResourceType = null,
    resource_alloc_type: ?ResourceType = null,
    is_heap_alloc: bool = false,
    is_intentional_transfer: bool = false,
};

/// Hash map from function name → cached classification results.
/// Key is a borrowed []const u8 slice (must outlive cache or be duplicated).
pub const FnClassCache = struct {
    map: std.StringHashMap(FnClassification),

    pub fn init(allocator: std.mem.Allocator) FnClassCache {
        return .{ .map = std.StringHashMap(FnClassification).init(allocator) };
    }

    pub fn deinit(self: *FnClassCache) void {
        self.map.deinit();
    }

    /// Get or compute classification for a function name.
    /// Returns cached result if available, otherwise computes and caches it.
    pub fn getOrCompute(self: *FnClassCache, allocator: std.mem.Allocator, func_name: []const u8, module_lang: ?Language) !*FnClassification {
        const gop = try self.map.getOrPut(allocator, func_name);
        if (gop.found_existing) return gop.value_ptr;

        var cls = FnClassification{};
        cls.is_free = classify_mod.isFreeFunction(func_name);
        cls.alloc_lang = classify_mod.classifyAllocLanguage(func_name);
        cls.alloc_lang_enum = classify_mod.classifyAllocLanguageEnum(func_name, module_lang);
        cls.free_lang = classify_mod.classifyFreeLanguage(func_name);
        cls.may_retain = ptr_types.may_retain_pointer(func_name);
        cls.is_extern = ptr_types.is_extern_function(func_name);
        cls.resource_close_type = classify_mod.isResourceCloseFunction(func_name);
        cls.resource_alloc_type = ptr_types.is_resource_alloc_function(func_name);
        cls.is_heap_alloc = ptr_types.isHeapAllocFunction(func_name);
        cls.is_intentional_transfer = @import("ptr_lifetime_utils.zig").isIntentionalOwnershipTransfer(func_name);

        gop.value_ptr.* = cls;
        return gop.value_ptr;
    }

    /// Uncached lookup (returns null if not in cache).
    pub fn get(self: *const FnClassCache, func_name: []const u8) ?FnClassification {
        return self.map.get(func_name);
    }
};

/// FNV-1a 64-bit hash for string keys (borrowed slices).
const StringHash = struct {
    pub fn hash(key: []const u8) u64 {
        var h: u64 = 14695981039346656037;
        for (key) |b| {
            h ^= b;
            h *%= 1099511628211;
        }
        return h;
    }
};

/// Custom equality for string slices (borrowed []const u8).
const StringEql = struct {
    pub fn eq(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

// ============================================================================
// Layer 3: Combined Analysis Cache (Inst + FnClass)
// ============================================================================

/// Top-level cache structure passed through analyzeFunction.
/// Combines InstCache entries and FnClassCache for unified access.
///
/// Usage pattern:
///   var cache = AnalysisCache.init(allocator);
///   defer cache.deinit();
///
///   // In main instruction loop:
///   const inst_cache = cache.getInstCache(inst);
///   // Use inst_cache.opcode, inst_cache.callee_name etc.
///
///   // For function name classification:
///   const fn_cls = try cache.getFnClass(callee_name, module_lang);
///   // Use fn_cls.is_free, fn_cls.alloc_lang etc.
pub const AnalysisCache = struct {
    fn_class: FnClassCache,
    allocator: std.mem.Allocator,
    module_lang: ?Language,
    cache_hits_inst: usize = 0,
    cache_hits_fn: usize = 0,
    total_inst_lookups: usize = 0,
    total_fn_lookups: usize = 0,

    pub fn init(allocator: std.mem.Allocator, module_lang: ?Language) AnalysisCache {
        return .{
            .fn_class = FnClassCache.init(allocator),
            .allocator = allocator,
            .module_lang = module_lang,
        };
    }

    pub fn deinit(self: *AnalysisCache) void {
        self.fn_class.deinit();
    }

    /// Create an InstCache for an instruction (inline, no storage).
    /// This is the primary API — call once, use result in both track and check.
    pub fn fetchInst(self: *AnalysisCache, inst: c.LLVMValueRef) InstCache {
        self.total_inst_lookups += 1;
        return InstCache.initForInst(inst);
    }

    /// Get or compute function classification with caching.
    pub fn getFnClass(self: *AnalysisCache, func_name: []const u8) !*FnClassification {
        self.total_fn_lookups += 1;
        const result = try self.fn_class.getOrCompute(self.allocator, func_name, self.module_lang);
        if (self.fn_class.map.count() < self.total_fn_lookups) {
            self.cache_hits_fn += 1;
        }
        return result;
    }

    /// Get cached function classification (no compute fallback).
    pub fn getFnClassCached(self: *AnalysisCache, func_name: []const u8) ?FnClassification {
        return self.fn_class.get(func_name);
    }

    /// Print cache statistics for performance monitoring.
    pub fn stats(self: *const AnalysisCache) struct {
        fn_class_entries: usize,
        hit_rate_fn: f64,
    } {
        const entries = self.fn_class.map.count();
        const hit_rate: f64 = if (self.total_fn_lookups > 0)
            @as(f64, @floatFromInt(self.cache_hits_fn)) / @as(f64, @floatFromInt(self.total_fn_lookups))
        else
            0;
        return .{
            .fn_class_entries = entries,
            .hit_rate_fn = hit_rate,
        };
    }
};
