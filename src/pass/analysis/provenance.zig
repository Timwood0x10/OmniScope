//! Provenance Tracker — Unified value source tracing for precise issue messages.
//!
//! This module provides a centralized service for determining the origin/provenance
//! of LLVM values. It enables all issue reporting functions to generate messages that
//! include WHERE a value came from (code section, heap allocation, stack, global, etc.)
//! instead of generic descriptions.
//!
//! Design goals:
//!   1. Eliminate project-specific hardcoding in suppression patterns
//!   2. Enable generic semantic matching (Pattern B/D) instead of name-based matching
//!   3. Provide consistent provenance descriptions across all analysis passes
//!
//! Usage:
//!   var prov = Provenance.init(allocator, mem_graph);
//!   const desc = prov.describeValue(ptr_val);  // => "heap pointer from malloc()"
//!   const desc = prov.describeAllocaContent(alloca_val);  // => "storing code section pointer"
//!
//! Provenance categories:
//!   - "code section pointer"     — Global constant, function reference, string literal
//!   - "heap pointer from X()"    — Result of known allocator (malloc, _cgo_allocate, etc.)
//!   - "stack allocation"         — Alloca instruction (local variable)
//!   - "global variable"          — Address of global/static storage
//!   - "function parameter"       — Incoming argument to current function
//!   - "call result from X()"     — Return value of unknown/tracked function
//!   - "unknown source"           — Fallback when provenance cannot be determined

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
pub const memory_graph = @import("../../semantics/memory_graph.zig");

pub const Provenance = struct {
    allocator: std.mem.Allocator,
    mem_graph: ?*memory_graph.MemoryGraph,

    pub fn init(allocator: std.mem.Allocator, mg: ?*memory_graph.MemoryGraph) Provenance {
        return .{
            .allocator = allocator,
            .mem_graph = mg,
        };
    }

    /// Describe the provenance of an LLVM value.
    /// Returns a human-readable string describing where this value originated.
    ///
    /// Examples:
    ///   - Global @str.1027       => "code section pointer (string literal)"
    ///   - malloc() result        => "heap pointer from malloc()"
    ///   - alloca instruction     => "stack allocation"
    ///   - function parameter %arg => "function parameter"
    ///   - call result            => "call result from func()"
    pub fn describeValue(self: *const Provenance, val: c.LLVMValueRef) []const u8 {
        if (@intFromPtr(val) == 0) return "null value";

        // Check MemoryGraph first (most accurate)
        if (self.mem_graph) |mg| {
            const val_ptr = @as(u64, @intFromPtr(val));
            const kind = mg.getSourceKind(val_ptr);
            if (kind != .unknown) {
                return self.kindToDescription(kind, val);
            }
        }

        // Fallback: infer from LLVM value type
        return self.inferFromLLVMType(val);
    }

    /// Describe what content is stored in an alloca (stack variable).
    /// This is the key function for STACK-ESCAPE message improvement.
    ///
    /// Returns:
    ///   - "storing code section pointer"  — Global/constant stored into alloca
    ///   - "storing heap pointer"          — malloc/calloc result stored into alloca
    ///   - "storing call result"           — Function return value stored into alloca
    ///   - "storing parameter"             — Function arg stored into alloca
    ///   - "empty/uninitialized"           — No store detected
    ///   - "unknown content"              — Cannot determine
    pub fn describeAllocaContent(self: *const Provenance, alloca_val: c.LLVMValueRef) []const u8 {
        if (@intFromPtr(alloca_val) == 0) return "unknown content";

        if (self.mem_graph) |mg| {
            const ptr_val = @as(u64, @intFromPtr(alloca_val));
            const content_kind = mg.getContentSource(ptr_val);

            return switch (content_kind) {
                .alloca => "stack-local copy",
                .heap_alloc => "storing heap pointer",
                .resource_alloc => "storing code section pointer",
                .call_result => "storing call result",
                .unknown => "unknown content",
            };
        }

        return "unknown content";
    }

    /// Describe the provenance of a value that was passed to an extern function.
    /// Used for FFI-related issues (cross_language_free, use_after_free, etc.).
    ///
    /// Enhanced version that includes both the alloc site and the specific allocator.
    pub fn describeFFIValue(self: *const Provenance, val: c.LLVMValueRef, callee_name: ?[]const u8) []const u8 {
        const base_desc = self.describeValue(val);

        // If we have the callee name and it's a known free/alloc function, enhance description
        if (callee_name) |name| {
            if (self.isKnownAllocator(name)) {
                // Value came from a known allocator — enhance with allocator name
                if (std.mem.indexOf(u8, base_desc, "heap pointer") != null) {
                    // Already says "heap pointer", add allocator name
                    return std.fmt.allocPrint(
                        self.allocator,
                        "heap pointer from {s}()",
                        .{name},
                    ) catch base_desc;
                }
            }
        }

        return base_desc;
    }

    /// Convert a MemoryGraph SourceKind to a human-readable description.
    fn kindToDescription(self: *const Provenance, kind: memory_graph.SourceKind, val: c.LLVMValueRef) []const u8 {
        return switch (kind) {
            .alloca => "stack allocation",
            .heap_alloc => self.enrichHeapDesc(val),
            .resource_alloc => "code section pointer",
            .call_result => self.enrichCallResultDesc(val),
            .unknown => "unknown source",
        };
    }

    /// Enrich heap allocation description with allocator function name.
    fn enrichHeapDesc(self: *const Provenance, val: c.LLVMValueRef) []const u8 {
        // Try to find which allocator created this value by looking at the instruction
        const opcode = c.LLVMGetInstructionOpcode(val);
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(val);
            if (@intFromPtr(called) != 0) {
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) != 0) {
                    const callee_name = std.mem.span(name_ptr);
                    return std.fmt.allocPrint(
                        self.allocator,
                        "heap pointer from {s}()",
                        .{callee_name},
                    ) catch "heap pointer";
                }
            }
        }

        return "heap pointer";
    }

    /// Enrich call result description with callee function name.
    fn enrichCallResultDesc(self: *const Provenance, val: c.LLVMValueRef) []const u8 {
        const opcode = c.LLVMGetInstructionOpcode(val);
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(val);
            if (@intFromPtr(called) != 0) {
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) != 0) {
                    const callee_name = std.mem.span(name_ptr);
                    return std.fmt.allocPrint(
                        self.allocator,
                        "call result from {s}()",
                        .{callee_name},
                    ) catch "call result";
                }
            }
        }

        return "call result";
    }

    /// Infer provenance from LLVM value type when MemoryGraph is unavailable.
    fn inferFromLLVMType(self: *const Provenance, val: c.LLVMValueRef) []const u8 {
        // Global variable
        if (c.LLVMIsAGlobalValue(val) != null) {
            const name_ptr = c.LLVMGetValueName(val);
            if (@intFromPtr(name_ptr) != 0) {
                const name = std.mem.span(name_ptr);
                // String literals typically start with @.str or @.const
                if (std.mem.indexOf(u8, name, ".str") != null or
                    std.mem.indexOf(u8, name, ".const") != null)
                {
                    return "code section pointer (string literal)";
                }
                return "global variable";
            }
            return "code section pointer";
        }

        // Function pointer
        if (c.LLVMIsAFunction(val) != null) {
            return "code section pointer (function)";
        }

        // Constant expression (null, inttoptr, etc.)
        if (c.LLVMIsAConstant(val) != null) {
            return "constant value";
        }

        // Alloca instruction
        if (c.LLVMGetInstructionOpcode(val) == c.LLVMAlloca) {
            return "stack allocation";
        }

        // Call/invoke instruction
        const opcode = c.LLVMGetInstructionOpcode(val);
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(val);
            if (@intFromPtr(called) != 0) {
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) != 0) {
                    const callee_name = std.mem.span(name_ptr);
                    return std.fmt.allocPrint(
                        self.allocator,
                        "call result from {s}()",
                        .{callee_name},
                    ) catch "call result";
                }
            }
            return "call result";
        }

        // Argument (function parameter)
        if (c.LLVMIsAArgument(val) != null) {
            return "function parameter";
        }

        return "unknown source";
    }

    /// Check if a function name is a known allocator.
    fn isKnownAllocator(self: *const Provenance, func_name: []const u8) bool {
        _ = self;

        // Common allocator patterns across languages
        const allocators = [_][]const u8{
            "malloc",             "calloc",              "realloc",
            "_cgo_allocate",      "_cgo_allocate_local", "_Cfunc_GoMalloc",
            "_Cfunc_GoAlloc",     "__rust_alloc",        "__rust_realloc",
            "PyMem_Malloc",       "PyMalloc",            "JNIEnv_NewStringUTF",
            "napi_create_object", "napi_create_array",
        };

        for (allocators) |alloc| {
            if (std.mem.indexOf(u8, func_name, alloc) != null) {
                return true;
            }
        }

        return false;
    }

    /// Generate a suppression-friendly provenance tag for use in issue messages.
    /// This tag is designed to be matched by generic suppression patterns
    /// without requiring project-specific names.
    ///
    /// Returns one of:
    ///   - "[code-section]"      — Safe: compiler-generated or constant data
    ///   - "[heap-known]"        — Known allocator (may need ownership tracking)
    ///   - "[heap-unknown]"      — Unknown heap source (needs investigation)
    ///   - "[stack-param]"       — Stack var storing a parameter (usually safe)
    ///   - "[stack-empty]"       — Uninitialized stack var (suspicious)
    ///   - "[global]"            — Global variable (long lifetime)
    ///   - "[call-result]"       — Function return value (ambiguous)
    ///   - "[unknown]"           — Cannot determine
    pub fn getSuppressionTag(self: *const Provenance, val: c.LLVMValueRef) []const u8 {
        if (self.mem_graph) |mg| {
            const val_ptr = @as(u64, @intFromPtr(val));
            const kind = mg.getSourceKind(val_ptr);

            return switch (kind) {
                .resource_alloc => "[code-section]",
                .heap_alloc => "[heap-known]",
                .alloca => {
                    // Check if alloca stores something safe
                    const content = mg.getContentSource(val_ptr);
                    return switch (content) {
                        .resource_alloc => "[code-section]",
                        .heap_alloc => "[heap-in-alloca]",
                        .alloca => "[stack-local-copy]",
                        .call_result => "[call-in-alloca]",
                        .unknown => "[stack-empty]",
                    };
                },
                .call_result => "[call-result]",
                .unknown => "[unknown]",
            };
        }

        return "[unknown]";
    }
};
