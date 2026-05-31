//! Container Type Inference - Heuristic-based detection of container types
//! from allocation function names.
//!
//! This module provides Phase 2 ownership-aware analysis by identifying
//! smart containers (Box, Vec, unique_ptr, etc.) and their associated
//! memory management models. When a container type is inferred:
//!
//!   1. The AllocNode.container_type is set to the detected container
//!   2. The AllocNode.ownership_model is set based on the container's semantics:
//!      - Rust containers (Box, Vec, String) → .raii (Drop trait)
//!      - C++ smart pointers (unique_ptr, shared_ptr) → .raii (destructors)
//!      - Python containers (list, dict) → .refcount (Py_INCREF/DECREF)
//!      - Go containers (slice, map) → .gc (runtime GC)
//!
//! This enables downstream leak detectors to suppress false positives for
//! containers that manage their own memory lifecycle.

const std = @import("std");
const log = @import("../common/log.zig");
const memory_types = @import("../types/memory_graph_types.zig");

pub const ContainerInferer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ContainerInferer {
        return .{ .allocator = allocator };
    }

    /// Infer container type from allocation function name.
    ///
    /// Uses pattern matching on mangled/demangled names to identify
    /// well-known container allocation functions across languages:
    ///
    /// **Rust** (demangled LLVM names):
    ///   - "alloc::raw_vec::RawVec" → .rust_vec
    ///   - "alloc::string::String" → .rust_string
    ///   - "boxed::Box" → .rust_box
    ///
    /// **C++** (Itanium mangled names):
    ///   - "_ZNSt6vector" → .std_vector
    ///   - "_ZNSt7__cxx11" → .std_string
    ///   - "_ZNSt10unique_ptr" / "unique_ptr" → .cpp_unique_ptr
    ///   - "_ZNSt10shared_ptr" / "shared_ptr" → .cpp_shared_ptr
    ///
    /// **Python** (C API):
    ///   - "PyList_" → .python_list
    ///   - "PyDict_" → .python_dict
    ///
    /// **Go** (runtime functions):
    ///   - "runtime.makeslice" → .go_slice
    ///   - "runtime.makemap" → .go_map
    ///
    /// Arguments:
    ///   func_name - The allocation function name (mangled or demangled)
    ///
    /// Returns:
    ///   Inferred ContainerType, or null if unknown
    pub fn inferFromAllocName(self: *ContainerInferer, func_name: []const u8) ?memory_types.ContainerType {
        _ = self;

        // Rust standard library containers (demangled names)
        if (std.mem.indexOf(u8, func_name, "alloc::raw_vec::RawVec") != null) return .rust_vec;
        if (std.mem.indexOf(u8, func_name, "alloc::string::String") != null) return .rust_string;
        if (std.mem.indexOf(u8, func_name, "boxed::Box") != null) return .rust_box;

        // C++ STL (Itanium mangled names)
        if (std.mem.indexOf(u8, func_name, "_ZNSt6vector") != null) return .std_vector;
        if (std.mem.indexOf(u8, func_name, "_ZNSt7__cxx11") != null) return .std_string;
        if (std.mem.indexOf(u8, func_name, "unique_ptr") != null or
            std.mem.indexOf(u8, func_name, "_ZNSt10unique_ptr") != null)
        {
            return .cpp_unique_ptr;
        }
        if (std.mem.indexOf(u8, func_name, "shared_ptr") != null or
            std.mem.indexOf(u8, func_name, "_ZNSt10shared_ptr") != null)
        {
            return .cpp_shared_ptr;
        }

        // Python C API
        if (std.mem.indexOf(u8, func_name, "PyList_") != null) return .python_list;
        if (std.mem.indexOf(u8, func_name, "PyDict_") != null) return .python_dict;

        // Go runtime
        if (std.mem.indexOf(u8, func_name, "runtime.makeslice") != null or
            std.mem.indexOf(u8, func_name, "runtime.makemap") != null)
        {
            // Distinguish slice vs map
            if (std.mem.indexOf(u8, func_name, "makemap") != null) {
                return .go_map;
            }
            return .go_slice;
        }

        return null;
    }

    /// Apply inferred container type to an AllocNode.
    ///
    /// Sets both container_type and ownership_model based on the
    /// inferred container's memory management semantics.
    ///
    /// Arguments:
    ///   node            - The AllocNode to update
    ///   alloc_func_name - The allocation function name to analyze
    pub fn applyToNode(
        inferer: *ContainerInferer,
        node: *memory_types.AllocNode,
        alloc_func_name: []const u8,
    ) void {
        if (inferer.inferFromAllocName(alloc_func_name)) |container_type| {
            node.container_type = container_type;

            // Set ownership model based on container type
            node.ownership_model = switch (container_type) {
                .rust_box, .rust_vec, .rust_string => .raii,
                .cpp_unique_ptr, .cpp_shared_ptr, .std_vector, .std_string => .raii,
                .python_list, .python_dict => .refcount,
                .go_slice, .go_map => .gc,
                else => .manual,
            };

            log.debug("CONTAINER: Inferred {} for alloc '{}' → ownership={}", .{
                @tagName(container_type),
                alloc_func_name,
                @tagName(node.ownership_model),
            });
        }
    }
};

// ════════════════════════════════════════════════════
// Unit Tests
// ════════════════════════════════════════════════════

const testing = std.testing;

test "ContainerInferer - detects Rust types" {
    var inferer = ContainerInferer.init(testing.allocator);

    try testing.expectEqual(.rust_vec, inferer.inferFromAllocName("alloc::raw_vec::RawVec::<i32>::allocate_in"));
    try testing.expectEqual(.rust_box, inferer.inferFromAllocName("boxed::Box<i32>::new"));
    try testing.expectEqual(.rust_string, inferer.inferFromAllocName("alloc::string::String"));
}

test "ContainerInferer - detects C++ types" {
    var inferer = ContainerInferer.init(testing.allocator);

    try testing.expectEqual(.std_vector, inferer.inferFromAllocName("_ZNSt6vectorIiEC1Ev"));
    try testing.expectEqual(.cpp_unique_ptr, inferer.inferFromAllocName("_ZNSt10unique_ptrIiED1Ev"));
    try testing.expectEqual(.cpp_shared_ptr, inferer.inferFromAllocName("_ZNSt10shared_ptrIiEC1Ev"));
    try testing.expectEqual(.std_string, inferer.inferFromAllocName("_ZNSt7__cxx11basic_stringIcSt11char_traitsIcESaIcEE"));
}

test "ContainerInferer - detects Python types" {
    var inferer = ContainerInferer.init(testing.allocator);

    try testing.expectEqual(.python_list, inferer.inferFromAllocName("PyList_New"));
    try testing.expectEqual(.python_list, inferer.inferFromAllocName("PyList_Append"));
    try testing.expectEqual(.python_dict, inferer.inferFromAllocName("PyDict_New"));
}

test "ContainerInferer - detects Go types" {
    var inferer = ContainerInferer.init(testing.allocator);

    try testing.expectEqual(.go_slice, inferer.inferFromAllocName("runtime.makeslice"));
    try testing.expectEqual(.go_map, inferer.inferFromAllocName("runtime.makemap"));
    try testing.expectEqual(.go_map, inferer.inferFromAllocName("runtime.makemap64"));
}

test "ContainerInferer - returns null for unknown" {
    var inferer = ContainerInferer.init(testing.allocator);

    try testing.expectEqual(@as(?memory_types.ContainerType, null), inferer.inferFromAllocName("malloc"));
    try testing.expectEqual(@as(?memory_types.ContainerType, null), inferer.inferFromAllocName("custom_alloc"));
}
