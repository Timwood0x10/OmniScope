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
        /// Whether this edge represents a backward slice
        is_backward: bool,
        /// Edge weight or confidence (0.0 - 1.0)
        weight: f32,
        /// Whether this edge is a critical path
        is_critical: bool,

        /// Create default metadata
        pub fn initDefault() EdgeMetadata {
            return .{
                .is_backward = false,
                .weight = 1.0,
                .is_critical = false,
            };
        }

        /// Create metadata with custom weight
        ///
        /// Parameters:
        ///   - weight: Edge weight (0.0 - 1.0)
        ///
        /// Returns:
        ///   - A new EdgeMetadata instance
        pub fn initWithWeight(weight: f32) EdgeMetadata {
            return .{
                .is_backward = false,
                .weight = weight,
                .is_critical = false,
            };
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
    ///   - true if edge represents a memory operation
    pub fn isMemoryOperation(self: *const DataEdge) bool {
        return self.edge_type == .store or self.edge_type == .load;
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
