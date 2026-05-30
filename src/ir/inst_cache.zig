//! Per-instruction cache for LLVM API results.
//!
//! Avoids repeated FFI calls for the same instruction by caching
//! frequently accessed information such as opcode, operand count,
//! and callee name.
//!
//! This cache is designed to be used within a single function analysis
//! pass. The cache is keyed by the instruction pointer (usize) and
//! stores commonly needed instruction metadata.

const std = @import("std");
const c = @import("llvm_raw.zig").c;
const inst_classifier = @import("inst_classifier.zig");

// Re-export commonly used types for convenience
pub const InstClass = inst_classifier.InstClass;
pub const FilterStats = inst_classifier.FilterStats;

/// Per-instruction cache for LLVM API results.
/// Avoids repeated FFI calls for the same instruction.
pub const InstCache = struct {
    /// Cached instruction information.
    pub const Entry = struct {
        opcode: c_uint,
        num_operands: c_uint,
        callee_name: ?[]const u8,
        type_kind: c_uint,

        // Classification fields (for fast filtering)
        class: InstClass = .other,
        is_relevant: bool = true,
    };

    /// Map from instruction pointer to cached entry.
    map: std.AutoHashMap(usize, Entry),
    /// Memory allocator for HashMap operations.
    allocator: std.mem.Allocator,

    // Cache performance statistics
    hits: u64 = 0,
    misses: u64 = 0,

    /// Initialize the cache with the given allocator.
    pub fn init(allocator: std.mem.Allocator) InstCache {
        return .{
            .map = std.AutoHashMap(usize, Entry).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the cache and free all resources.
    pub fn deinit(self: *InstCache) void {
        self.map.deinit();
    }

    /// Get the opcode for an instruction, using cache if available.
    /// This is the most frequently called LLVM API function.
    pub fn getOpcode(self: *InstCache, inst: c.LLVMValueRef) c_uint {
        const ptr = @intFromPtr(inst);
        if (self.map.get(ptr)) |entry| {
            self.hits += 1;
            return entry.opcode;
        }
        self.misses += 1;
        const opcode = c.LLVMGetInstructionOpcode(inst);
        self.map.put(ptr, .{
            .opcode = opcode,
            .num_operands = 0,
            .callee_name = null,
            .type_kind = 0,
        }) catch {};
        return opcode;
    }

    /// Get the number of operands for an instruction.
    /// Uses lazy initialization - only calls LLVM API if not cached.
    pub fn getNumOperands(self: *InstCache, inst: c.LLVMValueRef) c_uint {
        const ptr = @intFromPtr(inst);
        if (self.map.get(ptr)) |entry| {
            if (entry.num_operands > 0) {
                self.hits += 1;
                return entry.num_operands;
            }
        }
        self.misses += 1;
        const num = c.LLVMGetNumOperands(inst);
        if (self.map.getPtr(ptr)) |p| {
            p.num_operands = @intCast(num);
        } else {
            self.map.put(ptr, .{
                .opcode = c.LLVMGetInstructionOpcode(inst),
                .num_operands = @intCast(num),
                .callee_name = null,
                .type_kind = 0,
            }) catch {};
        }
        return @intCast(num);
    }

    /// Get the callee name for a call/invoke instruction.
    /// Returns null if the instruction is not a call/invoke.
    pub fn getCalleeName(self: *InstCache, inst: c.LLVMValueRef) ?[]const u8 {
        const ptr = @intFromPtr(inst);
        if (self.map.get(ptr)) |entry| {
            if (entry.callee_name) |name| {
                self.hits += 1;
                return name;
            }
        }
        self.misses += 1;
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return null;
        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return null;
        const name = std.mem.span(name_ptr);
        if (self.map.getPtr(ptr)) |p| {
            p.callee_name = name;
        } else {
            self.map.put(ptr, .{
                .opcode = c.LLVMGetInstructionOpcode(inst),
                .num_operands = @intCast(c.LLVMGetNumOperands(inst)),
                .callee_name = name,
                .type_kind = 0,
            }) catch {};
        }
        return name;
    }

    /// Get the type kind for an instruction.
    /// Useful for type-based analysis without repeated LLVM calls.
    pub fn getTypeKind(self: *InstCache, inst: c.LLVMValueRef) c_uint {
        const ptr = @intFromPtr(inst);
        if (self.map.get(ptr)) |entry| {
            if (entry.type_kind != 0) {
                self.hits += 1;
                return entry.type_kind;
            }
        }
        self.misses += 1;
        const type_ref = c.LLVMTypeOf(inst);
        if (@intFromPtr(type_ref) == 0) return 0;
        const type_kind = c.LLVMGetTypeKind(type_ref);
        if (self.map.getPtr(ptr)) |p| {
            p.type_kind = type_kind;
        } else {
            self.map.put(ptr, .{
                .opcode = c.LLVMGetInstructionOpcode(inst),
                .num_operands = @intCast(c.LLVMGetNumOperands(inst)),
                .callee_name = null,
                .type_kind = type_kind,
            }) catch {};
        }
        return type_kind;
    }

    /// Clear the cache while keeping allocated memory.
    /// Useful when analyzing multiple functions to avoid reallocation.
    pub fn clear(self: *InstCache) void {
        self.map.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    /// Get classified information for an instruction.
    /// This is the primary method for fast filtering - it returns cached
    /// classification info including whether the instruction is relevant
    /// for memory safety / FFI analysis.
    ///
    /// Performance: O(1) on cache hit (hot path), O(1) + 1 LLVM API call on miss.
    pub fn getClassifiedInfo(self: *InstCache, inst: c.LLVMValueRef) Entry {
        const ptr = @intFromPtr(inst);

        if (self.map.get(ptr)) |entry| {
            self.hits += 1;
            return entry;
        }

        // First access — classify and cache
        self.misses += 1;
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const class = inst_classifier.classifyOpcode(opcode);

        const entry = Entry{
            .opcode = opcode,
            .num_operands = @intCast(c.LLVMGetNumOperands(inst)),
            .callee_name = null,
            .type_kind = 0,
            .class = class,
            .is_relevant = class.isRelevantForAnalysis(),
        };

        self.map.put(ptr, entry) catch {};
        return entry;
    }

    /// Get cache hit rate as percentage (0.0 to 100.0).
    pub fn hitRate(self: *InstCache) f32 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total)) * 100.0;
    }
};

/// Safe helper functions for cache access with automatic fallback.
/// These functions provide a safe way to use InstCache from passes,
/// with automatic fallback to direct LLVM API calls when cache is unavailable.
/// Get instruction opcode with cache fallback.
pub fn getOpcodeSafe(cache: ?*InstCache, inst: c.LLVMValueRef) c_uint {
    if (cache) |cache_ptr| {
        return cache_ptr.getOpcode(inst);
    }
    return c.LLVMGetInstructionOpcode(inst);
}

/// Get number of operands with cache fallback.
pub fn getNumOperandsSafe(cache: ?*InstCache, inst: c.LLVMValueRef) c_uint {
    if (cache) |cache_ptr| {
        return cache_ptr.getNumOperands(inst);
    }
    return @intCast(c.LLVMGetNumOperands(inst));
}

/// Get callee name with cache fallback.
/// Returns null if not a call/invoke instruction or cache unavailable.
pub fn getCalleeNameSafe(cache: ?*InstCache, inst: c.LLVMValueRef) ?[]const u8 {
    if (cache) |cache_ptr| {
        return cache_ptr.getCalleeName(inst);
    }
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_ptr) == 0) return null;
    return std.mem.span(name_ptr);
}

/// Get type kind with cache fallback.
pub fn getTypeKindSafe(cache: ?*InstCache, inst: c.LLVMValueRef) c_uint {
    if (cache) |cache_ptr| {
        return cache_ptr.getTypeKind(inst);
    }
    const type_ref = c.LLVMTypeOf(inst);
    if (@intFromPtr(type_ref) == 0) return 0;
    return c.LLVMGetTypeKind(type_ref);
}
