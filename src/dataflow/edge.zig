//! Data Flow Edge Definitions
//!
//! This module defines the data flow edge types used in the data flow graph.
//! Edges represent data flow relationships between nodes.

const std = @import("std");

/// Edge type enumeration
///
/// Defines the types of data flow edges that can exist between nodes.
pub const EdgeType = enum {
    /// Direct assignment or flow
    direct,
    /// Flow through function call argument
    call_arg,
    /// Flow through function return value
    call_ret,
    /// Store operation (memory write)
    store,
    /// Load operation (memory read)
    load,
    /// Flow across FFI boundary
    ffi_boundary,
    /// GEP (GetElementPtr) - struct field or array element access
    gep,
    /// ExtractValue - extract from aggregate type
    extract_value,
    /// InsertValue - insert into aggregate type
    insert_value,
    /// Pointer arithmetic (ptr + offset)
    ptr_offset,
    /// BitCast/PtrToInt/IntToPtr - type conversion
    type_cast,
    /// PHI node merge
    phi_merge,
    /// Select instruction
    select,
    /// Unknown edge type
    unknown,

    /// Convert edge type to string representation
    pub fn toString(self: EdgeType) []const u8 {
        return switch (self) {
            .direct => "direct",
            .call_arg => "call_arg",
            .call_ret => "call_ret",
            .store => "store",
            .load => "load",
            .ffi_boundary => "ffi_boundary",
            .gep => "gep",
            .extract_value => "extract_value",
            .insert_value => "insert_value",
            .ptr_offset => "ptr_offset",
            .type_cast => "type_cast",
            .phi_merge => "phi_merge",
            .select => "select",
            .unknown => "unknown",
        };
    }
};

/// Data flow edge
///
/// Represents a data flow relationship between two nodes in the graph.
/// Edges are directed, showing the direction of data flow.
pub const DataEdge = struct {
    /// Source node ID (where data flows from)
    from: u32,
    /// Target node ID (where data flows to)
    to: u32,
    /// Type of the edge
    edge_type: EdgeType,
    /// Function name if edge is through a function call (optional)
    via_function: ?[]const u8,
    /// Additional metadata (optional)
    metadata: ?EdgeMetadata,

    /// Edge metadata
    ///
    /// Contains additional information about the edge.
    pub const EdgeMetadata = struct {
        /// Maximum number of GEP indices that can be stored inline.
        ///
        /// This limit is a design trade-off:
        /// - Most GEP operations have <= 4 indices (struct.field, array[i], ptr->field)
        /// - Inline storage avoids memory allocation overhead
        /// - Deeply nested accesses (>4 levels) are rare in practice
        ///
        /// If exceeded, excess indices are silently truncated. This is acceptable
        /// because the primary use case is tracking pointer flow, not exact offsets.
        pub const MAX_GEP_INDICES: usize = 4;

        /// Whether this edge represents a backward slice
        is_backward: bool,
        /// Edge weight or confidence (0.0 - 1.0)
        weight: f32,
        /// Whether this edge is a critical path
        is_critical: bool,
        /// GEP indices stored inline (avoids memory management issues)
        /// First element is always 0 (pointer deref), subsequent are field/array indices
        gep_indices: [MAX_GEP_INDICES]u64,
        /// Number of valid GEP indices (0 means no indices)
        gep_count: u8,
        /// Whether GEP indices are all constant
        gep_const_indices: bool,

        /// Create default metadata
        pub fn initDefault() EdgeMetadata {
            return .{
                .is_backward = false,
                .weight = 1.0,
                .is_critical = false,
                .gep_indices = [_]u64{0} ** MAX_GEP_INDICES,
                .gep_count = 0,
                .gep_const_indices = true,
            };
        }

        /// Create metadata with custom weight
        pub fn initWithWeight(weight: f32) EdgeMetadata {
            return .{
                .is_backward = false,
                .weight = weight,
                .is_critical = false,
                .gep_indices = [_]u64{0} ** MAX_GEP_INDICES,
                .gep_count = 0,
                .gep_const_indices = true,
            };
        }

        /// Create metadata for GEP edge
        /// Indices are copied into inline storage. If more than MAX_GEP_INDICES are provided,
        /// only the first MAX_GEP_INDICES are stored.
        pub fn initGEP(indices: []const u64, all_const: bool) EdgeMetadata {
            var meta = initDefault();
            meta.gep_const_indices = all_const;
            meta.gep_count = @min(@as(u8, @intCast(indices.len)), MAX_GEP_INDICES);
            for (0..meta.gep_count) |i| {
                meta.gep_indices[i] = indices[i];
            }
            return meta;
        }

        /// Check if this metadata has GEP indices
        pub fn hasGEPIndices(self: *const EdgeMetadata) bool {
            return self.gep_count > 0;
        }

        /// Check if this is a GEP edge with constant indices
        pub fn isConstGEP(self: *const EdgeMetadata) bool {
            return self.gep_count > 0 and self.gep_const_indices;
        }

        /// Get GEP indices as a slice
        pub fn getGEPIndices(self: *const EdgeMetadata) []const u64 {
            return self.gep_indices[0..self.gep_count];
        }
    };

    /// Create a new data edge
    ///
    /// Parameters:
    ///   - from: Source node ID
    ///   - to: Target node ID
    ///   - edge_type: Type of the edge
    ///
    /// Returns:
    ///   - A new DataEdge instance
    pub fn init(from: u32, to: u32, edge_type: EdgeType) DataEdge {
        return .{
            .from = from,
            .to = to,
            .edge_type = edge_type,
            .via_function = null,
            .metadata = null,
        };
    }

    /// Create a new data edge with function name
    ///
    /// Parameters:
    ///   - from: Source node ID
    ///   - to: Target node ID
    ///   - edge_type: Type of the edge
    ///   - via_function: Function name if edge is through a function call
    ///
    /// Returns:
    ///   - A new DataEdge instance
    pub fn initWithFunction(
        from: u32,
        to: u32,
        edge_type: EdgeType,
        via_function: []const u8,
    ) DataEdge {
        return .{
            .from = from,
            .to = to,
            .edge_type = edge_type,
            .via_function = via_function,
            .metadata = null,
        };
    }

    /// Create a new data edge with metadata
    ///
    /// Parameters:
    ///   - from: Source node ID
    ///   - to: Target node ID
    ///   - edge_type: Type of the edge
    ///   - metadata: Additional metadata
    ///
    /// Returns:
    ///   - A new DataEdge instance
    pub fn initWithMetadata(
        from: u32,
        to: u32,
        edge_type: EdgeType,
        metadata: EdgeMetadata,
    ) DataEdge {
        return .{
            .from = from,
            .to = to,
            .edge_type = edge_type,
            .via_function = null,
            .metadata = metadata,
        };
    }

    /// Set function name for this edge
    ///
    /// Parameters:
    ///   - via_function: Function name
    pub fn setFunction(self: *DataEdge, via_function: []const u8) void {
        self.via_function = via_function;
    }

    /// Set metadata for this edge
    ///
    /// Parameters:
    ///   - metadata: Edge metadata
    pub fn setMetadata(self: *DataEdge, metadata: EdgeMetadata) void {
        self.metadata = metadata;
    }

    /// Check if this edge is a function call edge
    ///
    /// Returns:
    ///   - true if edge is through a function call
    pub fn isCallEdge(self: *const DataEdge) bool {
        return self.edge_type == .call_arg or self.edge_type == .call_ret;
    }

    /// Check if this edge is an FFI boundary edge
    ///
    /// Returns:
    ///   - true if edge crosses FFI boundary
    pub fn isFFIBoundary(self: *const DataEdge) bool {
        return self.edge_type == .ffi_boundary;
    }

    /// Check if this edge is a memory operation edge
    ///
    /// Returns:
    ///   - true if edge represents a store or load operation
    pub fn isMemoryOperation(self: *const DataEdge) bool {
        return self.edge_type == .store or self.edge_type == .load;
    }

    /// Check if this edge is a pointer arithmetic edge
    ///
    /// Pointer arithmetic includes GEP (GetElementPtr), pointer offset,
    /// and type cast operations that manipulate pointer values.
    ///
    /// Returns:
    ///   - true if edge represents pointer arithmetic
    pub fn isPointerArithmetic(self: *const DataEdge) bool {
        return self.edge_type == .gep or
            self.edge_type == .ptr_offset or
            self.edge_type == .type_cast;
    }

    /// Check if this edge is a struct/aggregate access edge
    ///
    /// Aggregate access includes GEP, extract_value, and insert_value
    /// operations that access fields or elements of compound types.
    ///
    /// Returns:
    ///   - true if edge represents aggregate type access
    pub fn isAggregateAccess(self: *const DataEdge) bool {
        return self.edge_type == .gep or
            self.edge_type == .extract_value or
            self.edge_type == .insert_value;
    }

    /// Check if this edge is a control flow merge edge
    ///
    /// Control flow merge includes PHI nodes and select instructions
    /// that merge values from different execution paths.
    ///
    /// Returns:
    ///   - true if edge represents control flow merge
    pub fn isControlFlowMerge(self: *const DataEdge) bool {
        return self.edge_type == .phi_merge or self.edge_type == .select;
    }

    /// Get GEP indices if this is a GEP edge
    ///
    /// Returns an empty slice if this edge has no GEP indices.
    /// The returned slice is valid as long as this DataEdge exists.
    ///
    /// Returns:
    ///   - Slice of GEP indices (empty if not a GEP edge)
    pub fn getGEPIndices(self: *const DataEdge) []const u64 {
        if (self.metadata) |*meta| {
            return meta.getGEPIndices();
        }
        return &[_]u64{};
    }

    /// Check if this edge has GEP indices with all constant values
    ///
    /// Returns:
    ///   - true if this is a GEP edge with constant indices
    pub fn isConstGEP(self: *const DataEdge) bool {
        if (self.metadata) |meta| {
            return meta.isConstGEP();
        }
        return false;
    }

    /// Get edge weight if available
    ///
    /// Returns:
    ///   - Edge weight (0.0 - 1.0), or 1.0 if not specified
    pub fn getWeight(self: *const DataEdge) f32 {
        if (self.metadata) |meta| {
            return meta.weight;
        }
        return 1.0;
    }

    /// Check if this edge is marked as critical
    ///
    /// Returns:
    ///   - true if edge is on a critical path
    pub fn isCritical(self: *const DataEdge) bool {
        if (self.metadata) |meta| {
            return meta.is_critical;
        }
        return false;
    }

    /// Mark this edge as critical
    pub fn markCritical(self: *DataEdge) void {
        if (self.metadata) |*meta| {
            meta.is_critical = true;
        } else {
            var default_meta = EdgeMetadata.initDefault();
            default_meta.is_critical = true;
            self.metadata = default_meta;
        }
    }
};

// Unit tests

test "EdgeType - toString" {
    try std.testing.expectEqualStrings("direct", EdgeType.direct.toString());
    try std.testing.expectEqualStrings("call_arg", EdgeType.call_arg.toString());
    try std.testing.expectEqualStrings("ffi_boundary", EdgeType.ffi_boundary.toString());
    try std.testing.expectEqualStrings("unknown", EdgeType.unknown.toString());
}

test "DataEdge - init" {
    const edge = DataEdge.init(1, 2, .direct);

    try std.testing.expectEqual(@as(u32, 1), edge.from);
    try std.testing.expectEqual(@as(u32, 2), edge.to);
    try std.testing.expectEqual(EdgeType.direct, edge.edge_type);
    try std.testing.expect(edge.via_function == null);
}

test "DataEdge - initWithFunction" {
    const edge = DataEdge.initWithFunction(1, 2, .call_arg, "test_func");

    try std.testing.expectEqual(@as(u32, 1), edge.from);
    try std.testing.expectEqual(@as(u32, 2), edge.to);
    try std.testing.expectEqual(EdgeType.call_arg, edge.edge_type);
    try std.testing.expectEqualStrings("test_func", edge.via_function.?);
}

test "DataEdge - initWithMetadata" {
    const metadata = DataEdge.EdgeMetadata.initWithWeight(0.8);
    const edge = DataEdge.initWithMetadata(1, 2, .direct, metadata);

    try std.testing.expectEqual(@as(u32, 1), edge.from);
    try std.testing.expectEqual(@as(u32, 2), edge.to);
    try std.testing.expect(edge.metadata != null);
    try std.testing.expectEqual(@as(f32, 0.8), edge.getWeight());
}

test "DataEdge - setFunction" {
    var edge = DataEdge.init(1, 2, .call_arg);
    try std.testing.expect(edge.via_function == null);

    edge.setFunction("test_func");
    try std.testing.expectEqualStrings("test_func", edge.via_function.?);
}

test "DataEdge - setMetadata" {
    var edge = DataEdge.init(1, 2, .direct);
    try std.testing.expect(edge.metadata == null);

    const metadata = DataEdge.EdgeMetadata.initDefault();
    edge.setMetadata(metadata);
    try std.testing.expect(edge.metadata != null);
}

test "DataEdge - isCallEdge" {
    const call_arg_edge = DataEdge.init(1, 2, .call_arg);
    const call_ret_edge = DataEdge.init(1, 2, .call_ret);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(call_arg_edge.isCallEdge());
    try std.testing.expect(call_ret_edge.isCallEdge());
    try std.testing.expect(!direct_edge.isCallEdge());
}

test "DataEdge - isFFIBoundary" {
    const ffi_edge = DataEdge.init(1, 2, .ffi_boundary);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(ffi_edge.isFFIBoundary());
    try std.testing.expect(!direct_edge.isFFIBoundary());
}

test "DataEdge - isMemoryOperation" {
    const store_edge = DataEdge.init(1, 2, .store);
    const load_edge = DataEdge.init(1, 2, .load);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(store_edge.isMemoryOperation());
    try std.testing.expect(load_edge.isMemoryOperation());
    try std.testing.expect(!direct_edge.isMemoryOperation());
}

test "DataEdge - getWeight" {
    const edge1 = DataEdge.init(1, 2, .direct);
    try std.testing.expectEqual(@as(f32, 1.0), edge1.getWeight());

    const metadata = DataEdge.EdgeMetadata.initWithWeight(0.7);
    const edge2 = DataEdge.initWithMetadata(1, 2, .direct, metadata);
    try std.testing.expectEqual(@as(f32, 0.7), edge2.getWeight());
}

test "DataEdge - isCritical" {
    const edge1 = DataEdge.init(1, 2, .direct);
    try std.testing.expect(!edge1.isCritical());

    var metadata = DataEdge.EdgeMetadata.initDefault();
    metadata.is_critical = true;
    const edge2 = DataEdge.initWithMetadata(1, 2, .direct, metadata);
    try std.testing.expect(edge2.isCritical());
}

test "DataEdge - markCritical" {
    var edge = DataEdge.init(1, 2, .direct);
    try std.testing.expect(!edge.isCritical());

    edge.markCritical();
    try std.testing.expect(edge.isCritical());
}

test "EdgeMetadata - initDefault" {
    const metadata = DataEdge.EdgeMetadata.initDefault();

    try std.testing.expect(!metadata.is_backward);
    try std.testing.expectEqual(@as(f32, 1.0), metadata.weight);
    try std.testing.expect(!metadata.is_critical);
}

test "EdgeMetadata - initWithWeight" {
    const metadata = DataEdge.EdgeMetadata.initWithWeight(0.5);

    try std.testing.expect(!metadata.is_backward);
    try std.testing.expectEqual(@as(f32, 0.5), metadata.weight);
    try std.testing.expect(!metadata.is_critical);
}

test "EdgeType - new edge types toString" {
    try std.testing.expectEqualStrings("gep", EdgeType.gep.toString());
    try std.testing.expectEqualStrings("extract_value", EdgeType.extract_value.toString());
    try std.testing.expectEqualStrings("insert_value", EdgeType.insert_value.toString());
    try std.testing.expectEqualStrings("ptr_offset", EdgeType.ptr_offset.toString());
    try std.testing.expectEqualStrings("type_cast", EdgeType.type_cast.toString());
    try std.testing.expectEqualStrings("phi_merge", EdgeType.phi_merge.toString());
    try std.testing.expectEqualStrings("select", EdgeType.select.toString());
}

test "EdgeMetadata - initGEP with constant indices" {
    const indices = [_]u64{ 0, 2, 1 };
    const metadata = DataEdge.EdgeMetadata.initGEP(&indices, true);

    try std.testing.expect(metadata.hasGEPIndices());
    try std.testing.expect(metadata.gep_const_indices);
    try std.testing.expect(metadata.isConstGEP());
    const retrieved = metadata.getGEPIndices();
    try std.testing.expectEqual(@as(usize, 3), retrieved.len);
    try std.testing.expectEqual(@as(u64, 0), retrieved[0]);
    try std.testing.expectEqual(@as(u64, 2), retrieved[1]);
    try std.testing.expectEqual(@as(u64, 1), retrieved[2]);
}

test "EdgeMetadata - initGEP with variable indices" {
    const indices = [_]u64{ 0, 1 };
    const metadata = DataEdge.EdgeMetadata.initGEP(&indices, false);

    try std.testing.expect(metadata.hasGEPIndices());
    try std.testing.expect(!metadata.gep_const_indices);
    try std.testing.expect(!metadata.isConstGEP());
}

test "DataEdge - isPointerArithmetic" {
    const gep_edge = DataEdge.init(1, 2, .gep);
    const ptr_offset_edge = DataEdge.init(1, 2, .ptr_offset);
    const type_cast_edge = DataEdge.init(1, 2, .type_cast);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(gep_edge.isPointerArithmetic());
    try std.testing.expect(ptr_offset_edge.isPointerArithmetic());
    try std.testing.expect(type_cast_edge.isPointerArithmetic());
    try std.testing.expect(!direct_edge.isPointerArithmetic());
}

test "DataEdge - isAggregateAccess" {
    const gep_edge = DataEdge.init(1, 2, .gep);
    const extract_edge = DataEdge.init(1, 2, .extract_value);
    const insert_edge = DataEdge.init(1, 2, .insert_value);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(gep_edge.isAggregateAccess());
    try std.testing.expect(extract_edge.isAggregateAccess());
    try std.testing.expect(insert_edge.isAggregateAccess());
    try std.testing.expect(!direct_edge.isAggregateAccess());
}

test "DataEdge - isControlFlowMerge" {
    const phi_edge = DataEdge.init(1, 2, .phi_merge);
    const select_edge = DataEdge.init(1, 2, .select);
    const direct_edge = DataEdge.init(1, 2, .direct);

    try std.testing.expect(phi_edge.isControlFlowMerge());
    try std.testing.expect(select_edge.isControlFlowMerge());
    try std.testing.expect(!direct_edge.isControlFlowMerge());
}

test "DataEdge - getGEPIndices" {
    const indices = [_]u64{ 0, 1 };
    const metadata = DataEdge.EdgeMetadata.initGEP(&indices, true);
    const edge = DataEdge.initWithMetadata(1, 2, .gep, metadata);

    const retrieved = edge.getGEPIndices();
    try std.testing.expectEqual(@as(usize, 2), retrieved.len);
    try std.testing.expectEqual(@as(u64, 0), retrieved[0]);
    try std.testing.expectEqual(@as(u64, 1), retrieved[1]);

    // Edge without metadata returns empty slice
    const no_meta_edge = DataEdge.init(1, 2, .gep);
    try std.testing.expectEqual(@as(usize, 0), no_meta_edge.getGEPIndices().len);
}

test "DataEdge - isConstGEP" {
    const const_indices = [_]u64{ 0, 1 };
    const const_metadata = DataEdge.EdgeMetadata.initGEP(&const_indices, true);
    const const_edge = DataEdge.initWithMetadata(1, 2, .gep, const_metadata);
    try std.testing.expect(const_edge.isConstGEP());

    const var_indices = [_]u64{ 0, 1 };
    const var_metadata = DataEdge.EdgeMetadata.initGEP(&var_indices, false);
    const var_edge = DataEdge.initWithMetadata(1, 2, .gep, var_metadata);
    try std.testing.expect(!var_edge.isConstGEP());

    const no_meta_edge = DataEdge.init(1, 2, .gep);
    try std.testing.expect(!no_meta_edge.isConstGEP());
}
