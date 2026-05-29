//! Shared Traversal Index for LLVM IR
//!
//! This module provides a single-pass traversal index that collects
//! functions, call sites, allocation sites, and free sites from LLVM IR.
//! By building these indexes once, we avoid O(p*n) redundant traversals
//! where p = number of passes and n = number of instructions.
//!
//! Usage:
//!   var index = try TraversalIndex.build(module, allocator);
//!   defer index.deinit();
//!   const func = index.getFunction("main");
//!   const calls = index.getCallSites("malloc");

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("../ir/llvm_raw.zig").c;
const llvm_safe = @import("../ir/llvm_safe.zig");

/// Shared traversal index for LLVM IR analysis
///
/// Collects function, call site, allocation, and free site indexes
/// in a single pass through the module, providing O(1) lookups
/// for all subsequent analysis passes.
pub const TraversalIndex = struct {
    /// Function index: function name -> LLVM function reference
    functions: std.StringHashMap(c.LLVMValueRef),

    /// Call site index: caller function name -> list of call records
    call_sites: std.StringHashMap(std.ArrayList(CallRecord)),

    /// Allocation sites: list of allocation instruction references
    alloc_sites: std.ArrayList(c.LLVMValueRef),

    /// Free sites: list of free instruction references
    free_sites: std.ArrayList(c.LLVMValueRef),

    /// Memory allocator
    allocator: Allocator,

    /// Build a shared traversal index from an LLVM module
    ///
    /// This performs a single O(n) traversal of all functions and instructions,
    /// collecting indexes for O(1) lookup by subsequent analysis passes.
    ///
    /// Parameters:
    ///   - module: LLVM module reference to index
    ///   - allocator: Memory allocator for internal data structures
    ///
    /// Returns: Initialized TraversalIndex
    pub fn build(module: c.LLVMModuleRef, allocator: Allocator) !TraversalIndex {
        var index = TraversalIndex{
            .functions = std.StringHashMap(c.LLVMValueRef).init(allocator),
            .call_sites = std.StringHashMap(std.ArrayList(CallRecord)).init(allocator),
            .alloc_sites = std.ArrayList(c.LLVMValueRef).empty,
            .free_sites = std.ArrayList(c.LLVMValueRef).empty,
            .allocator = allocator,
        };

        // Single pass through all functions
        var func = c.LLVMGetFirstFunction(module);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            // Skip declarations (external functions)
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // Index function by name
            const func_name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_ptr) != 0) {
                const func_name = std.mem.span(func_name_ptr);
                try index.functions.put(func_name, func);
            }

            // Traverse all basic blocks and instructions
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    try index.indexInstruction(inst, func);
                }
            }
        }

        return index;
    }

    /// Index a single instruction
    ///
    /// Checks if the instruction is a call, allocation, or free site
    /// and adds it to the appropriate index.
    fn indexInstruction(self: *TraversalIndex, inst: c.LLVMValueRef, func: c.LLVMValueRef) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Check for call/invoke instructions
        if (llvm_safe.isCallOrInvoke(opcode)) {
            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) return;

            const called_name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(called_name_ptr) == 0) return;

            const called_name = std.mem.span(called_name_ptr);

            // Get caller function name
            const caller_name_ptr = c.LLVMGetValueName(func);
            const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
                std.mem.span(caller_name_ptr)
            else
                "<unknown>";

            // Add to call sites index
            const gop = try self.call_sites.getOrPut(caller_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = try std.ArrayList(CallRecord).initCapacity(self.allocator, 8);
            }
            try gop.value_ptr.append(self.allocator, .{
                .callee = called_name,
                .inst = inst,
            });

            // Check if this is an allocation or free call
            if (isAllocFunction(called_name)) {
                try self.alloc_sites.append(self.allocator, inst);
            } else if (isFreeFunction(called_name)) {
                try self.free_sites.append(self.allocator, inst);
            }
        }
    }

    /// Get a function reference by name
    ///
    /// Returns the LLVM function reference if found, null otherwise.
    ///
    /// Parameters:
    ///   - name: Function name to look up
    ///
    /// Returns: LLVM function reference or null
    pub fn getFunction(self: *const TraversalIndex, name: []const u8) ?c.LLVMValueRef {
        return self.functions.get(name);
    }

    /// Get all functions in the module
    ///
    /// Returns an iterator over all indexed functions.
    pub fn getFunctions(self: *const TraversalIndex) std.StringHashMap(c.LLVMValueRef).Iterator {
        return self.functions.iterator();
    }

    /// Get call sites for a caller function
    ///
    /// Returns the list of call records for the specified caller function,
    /// or null if the function has no call sites.
    ///
    /// Parameters:
    ///   - caller: Caller function name
    ///
    /// Returns: Slice of call records or null
    pub fn getCallSites(self: *const TraversalIndex, caller: []const u8) ?[]const CallRecord {
        if (self.call_sites.get(caller)) |records| {
            return records.items;
        }
        return null;
    }

    /// Get all allocation sites
    ///
    /// Returns a slice of LLVM instruction references for allocation calls.
    pub fn getAllocSites(self: *const TraversalIndex) []const c.LLVMValueRef {
        return self.alloc_sites.items;
    }

    /// Get all free sites
    ///
    /// Returns a slice of LLVM instruction references for free calls.
    pub fn getFreeSites(self: *const TraversalIndex) []const c.LLVMValueRef {
        return self.free_sites.items;
    }

    /// Get the number of indexed functions
    pub fn functionCount(self: *const TraversalIndex) usize {
        return self.functions.count();
    }

    /// Get the number of indexed call sites
    pub fn callSiteCount(self: *const TraversalIndex) usize {
        var count: usize = 0;
        var iter = self.call_sites.iterator();
        while (iter.next()) |entry| {
            count += entry.value_ptr.items.len;
        }
        return count;
    }

    /// Get the number of indexed allocation sites
    pub fn allocSiteCount(self: *const TraversalIndex) usize {
        return self.alloc_sites.items.len;
    }

    /// Get the number of indexed free sites
    pub fn freeSiteCount(self: *const TraversalIndex) usize {
        return self.free_sites.items.len;
    }

    /// Deinitialize the traversal index and free all resources
    pub fn deinit(self: *TraversalIndex) void {
        self.functions.deinit();

        var call_iter = self.call_sites.iterator();
        while (call_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.call_sites.deinit();

        self.alloc_sites.deinit(self.allocator);
        self.free_sites.deinit(self.allocator);
    }
};

/// A single call site record
pub const CallRecord = struct {
    /// Callee function name
    callee: []const u8,
    /// LLVM instruction reference
    inst: c.LLVMValueRef,
};

/// Check if a function name represents a memory allocation function
fn isAllocFunction(name: []const u8) bool {
    // Common allocation functions across languages
    const alloc_functions = [_][]const u8{
        "malloc",         "calloc",   "realloc", "aligned_alloc",
        "posix_memalign", "memalign", "valloc",  "pvalloc",
        "_Znwm",        "_Znam",               "_ZnwmSt11align_val_t", "_ZnamSt11align_val_t", // C++ new/delete operators
        "__rust_alloc", "__rust_alloc_zeroed", "__rust_realloc",
        "jemalloc", "tc_malloc", "tc_new", // Custom allocators
        "GC_malloc", "GC_malloc_atomic", // Boehm GC
        "PyMem_Malloc", "PyObject_Malloc", // Python
        "rb_alloc", "ruby_xmalloc", // Ruby
        "lua_newuserdata", // Lua
    };

    for (alloc_functions) |alloc_func| {
        if (std.mem.eql(u8, name, alloc_func)) {
            return true;
        }
    }

    // Check for common patterns
    if (std.mem.indexOf(u8, name, "alloc") != null or
        std.mem.indexOf(u8, name, "Alloc") != null or
        std.mem.indexOf(u8, name, "ALLOC") != null)
    {
        return true;
    }

    return false;
}

/// Check if a function name represents a memory free function
fn isFreeFunction(name: []const u8) bool {
    // Common free functions across languages
    const free_functions = [_][]const u8{
        "free", "cfree",
        "_ZdlPv",         "_ZdaPv",              "_ZdlPvm", "_ZdaPvm", // C++ delete operators
        "__rust_dealloc", "__rust_alloc_zeroed",
        "jemalloc", "tc_free", "tc_delete", // Custom allocators
        "GC_free", // Boehm GC
        "PyMem_Free", "PyObject_Free", // Python
        "rb_free", "ruby_xfree", // Ruby
        "lua_setuserdata", // Lua (indirect free)
    };

    for (free_functions) |free_func| {
        if (std.mem.eql(u8, name, free_func)) {
            return true;
        }
    }

    // Check for common patterns
    if (std.mem.indexOf(u8, name, "free") != null or
        std.mem.indexOf(u8, name, "Free") != null or
        std.mem.indexOf(u8, name, "FREE") != null or
        std.mem.indexOf(u8, name, "dealloc") != null or
        std.mem.indexOf(u8, name, "Dealloc") != null)
    {
        return true;
    }

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "TraversalIndex - isAllocFunction" {
    // Test allocation function detection
    try std.testing.expect(isAllocFunction("malloc"));
    try std.testing.expect(isAllocFunction("calloc"));
    try std.testing.expect(isAllocFunction("realloc"));
    try std.testing.expect(isAllocFunction("_Znwm"));
    try std.testing.expect(isAllocFunction("__rust_alloc"));
    try std.testing.expect(isAllocFunction("PyMem_Malloc"));
    try std.testing.expect(isAllocFunction("custom_allocator"));
    try std.testing.expect(isAllocFunction("my_alloc_func"));

    // Test non-allocation functions
    try std.testing.expect(!isAllocFunction("free"));
    try std.testing.expect(!isAllocFunction("printf"));
    try std.testing.expect(!isAllocFunction("main"));
}

test "TraversalIndex - isFreeFunction" {
    // Test free function detection
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("cfree"));
    try std.testing.expect(isFreeFunction("_ZdlPv"));
    try std.testing.expect(isFreeFunction("__rust_dealloc"));
    try std.testing.expect(isFreeFunction("PyMem_Free"));
    try std.testing.expect(isFreeFunction("custom_dealloc"));
    try std.testing.expect(isFreeFunction("my_free_func"));

    // Test non-free functions
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("printf"));
    try std.testing.expect(!isFreeFunction("main"));
}

test "TraversalIndex - empty index" {
    // Test initialization and deinitialization
    var index = TraversalIndex{
        .functions = std.StringHashMap(c.LLVMValueRef).init(std.testing.allocator),
        .call_sites = std.StringHashMap(std.ArrayList(CallRecord)).init(std.testing.allocator),
        .alloc_sites = std.ArrayList(c.LLVMValueRef).empty,
        .free_sites = std.ArrayList(c.LLVMValueRef).empty,
        .allocator = std.testing.allocator,
    };
    defer index.deinit();

    // Verify empty state
    try std.testing.expectEqual(@as(usize, 0), index.functionCount());
    try std.testing.expectEqual(@as(usize, 0), index.callSiteCount());
    try std.testing.expectEqual(@as(usize, 0), index.allocSiteCount());
    try std.testing.expectEqual(@as(usize, 0), index.freeSiteCount());

    // Test lookups on empty index
    try std.testing.expect(index.getFunction("main") == null);
    try std.testing.expect(index.getCallSites("main") == null);
    try std.testing.expect(index.getAllocSites().len == 0);
    try std.testing.expect(index.getFreeSites().len == 0);
}

test "TraversalIndex - CallRecord" {
    // Test CallRecord structure
    const record = CallRecord{
        .callee = "malloc",
        .inst = null,
    };

    try std.testing.expectEqualStrings("malloc", record.callee);
    try std.testing.expect(record.inst == null);
}
