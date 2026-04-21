//! Data Flow Node Definitions
//!
//! This module defines the data flow node types used in the data flow graph.
//! Nodes represent values or variables in the analyzed program.

const std = @import("std");

const Location = @import("../diag/issue.zig").Location;

/// Value type enumeration
///
/// Defines the types of values that can be represented in the data flow graph.
pub const ValueType = enum {
    /// Pointer type
    pointer,
    /// Integer type
    integer,
    /// Struct type
    struct_,
    /// Array type
    array,
    /// Function type
    function,
    /// Unknown type
    unknown,

    /// Convert value type to string representation
    pub fn toString(self: ValueType) []const u8 {
        return switch (self) {
            .pointer => "pointer",
            .integer => "integer",
            .struct_ => "struct",
            .array => "array",
            .function => "function",
            .unknown => "unknown",
        };
    }
};

/// Data flow node
///
/// Represents a value or variable in the analyzed program.
/// Nodes are connected by edges to form the data flow graph.
pub const DataNode = struct {
    /// Unique identifier for this node
    id: u32,
    /// Type of the value represented by this node
    value_type: ValueType,
    /// Whether this node is tainted (influenced by dangerous input)
    is_tainted: bool,
    /// Location where this value was created
    location: Location,
    /// ID of the node that tainted this node (null if this is a source)
    taint_source: ?u32,
    /// Additional metadata (optional)
    metadata: ?NodeMetadata,

    /// Node metadata
    ///
    /// Contains additional information about the node.
    pub const NodeMetadata = struct {
        /// Size in bytes (if known)
        size: ?u64,
        /// Name of the value (if applicable)
        name: ?[]const u8,
        /// Whether this value is a function parameter
        is_parameter: bool,
        /// Whether this value is a function return value
        is_return_value: bool,

        /// Create empty metadata
        pub fn init() NodeMetadata {
            return .{
                .size = null,
                .name = null,
                .is_parameter = false,
                .is_return_value = false,
            };
        }
    };

    /// Create a new data node
    ///
    /// Parameters:
    ///   - id: Unique identifier
    ///   - value_type: Type of the value
    ///   - location: Location where value was created
    ///
    /// Returns:
    ///   - A new DataNode instance
    pub fn init(id: u32, value_type: ValueType, location: Location) DataNode {
        return .{
            .id = id,
            .value_type = value_type,
            .is_tainted = false,
            .location = location,
            .taint_source = null,
            .metadata = null,
        };
    }

    /// Create a new data node with metadata
    ///
    /// Parameters:
    ///   - id: Unique identifier
    ///   - value_type: Type of the value
    ///   - location: Location where value was created
    ///   - metadata: Additional metadata
    ///
    /// Returns:
    ///   - A new DataNode instance
    pub fn initWithMetadata(
        id: u32,
        value_type: ValueType,
        location: Location,
        metadata: NodeMetadata,
    ) DataNode {
        return .{
            .id = id,
            .value_type = value_type,
            .is_tainted = false,
            .location = location,
            .taint_source = null,
            .metadata = metadata,
        };
    }

    /// Mark this node as tainted
    ///
    /// Parameters:
    ///   - source_id: ID of the node that tainted this node
    pub fn setTainted(self: *DataNode, source_id: ?u32) void {
        self.is_tainted = true;
        self.taint_source = source_id;
    }

    /// Clear taint from this node
    pub fn clearTaint(self: *DataNode) void {
        self.is_tainted = false;
        self.taint_source = null;
    }

    /// Check if this node is a taint source
    ///
    /// Returns:
    ///   - true if this node is tainted and has no source (is a source)
    pub fn isTaintSource(self: *const DataNode) bool {
        return self.is_tainted and self.taint_source == null;
    }

    /// Check if this node is a pointer
    ///
    /// Returns:
    ///   - true if this node represents a pointer value
    pub fn isPointer(self: *const DataNode) bool {
        return self.value_type == .pointer;
    }

    /// Check if this node is a function
    ///
    /// Returns:
    ///   - true if this node represents a function value
    pub fn isFunction(self: *const DataNode) bool {
        return self.value_type == .function;
    }

    /// Get node size if available
    ///
    /// Returns:
    ///   - Size in bytes, or null if unknown
    pub fn getSize(self: *const DataNode) ?u64 {
        if (self.metadata) |meta| {
            return meta.size;
        }
        return null;
    }

    /// Get node name if available
    ///
    /// Returns:
    ///   - Name of the value, or null if unknown
    pub fn getName(self: *const DataNode) ?[]const u8 {
        if (self.metadata) |meta| {
            return meta.name;
        }
        return null;
    }
};

// Unit tests

test "ValueType - toString" {
    try std.testing.expectEqualStrings("pointer", ValueType.pointer.toString());
    try std.testing.expectEqualStrings("integer", ValueType.integer.toString());
    try std.testing.expectEqualStrings("unknown", ValueType.unknown.toString());
}

test "DataNode - init" {
    const location = Location.init("test_func");
    const node = DataNode.init(1, .pointer, location);

    try std.testing.expectEqual(@as(u32, 1), node.id);
    try std.testing.expectEqual(ValueType.pointer, node.value_type);
    try std.testing.expect(!node.is_tainted);
    try std.testing.expect(node.taint_source == null);
}

test "DataNode - initWithMetadata" {
    const location = Location.init("test_func");
    var metadata = DataNode.NodeMetadata.init();
    metadata.size = 64;
    metadata.name = "test_var";
    metadata.is_parameter = true;

    const node = DataNode.initWithMetadata(1, .pointer, location, metadata);

    try std.testing.expectEqual(@as(u32, 1), node.id);
    try std.testing.expect(node.metadata != null);
    try std.testing.expectEqual(@as(u64, 64), node.getSize().?);
    try std.testing.expectEqualStrings("test_var", node.getName().?);
}

test "DataNode - setTainted" {
    const location = Location.init("test_func");
    var node = DataNode.init(1, .pointer, location);

    try std.testing.expect(!node.is_tainted);

    node.setTainted(null);
    try std.testing.expect(node.is_tainted);
    try std.testing.expect(node.isTaintSource());

    node.setTainted(2);
    try std.testing.expect(node.is_tainted);
    try std.testing.expect(!node.isTaintSource());
}

test "DataNode - clearTaint" {
    const location = Location.init("test_func");
    var node = DataNode.init(1, .pointer, location);

    node.setTainted(null);
    try std.testing.expect(node.is_tainted);

    node.clearTaint();
    try std.testing.expect(!node.is_tainted);
    try std.testing.expect(node.taint_source == null);
}

test "DataNode - isTaintSource" {
    const location = Location.init("test_func");
    var node = DataNode.init(1, .pointer, location);

    try std.testing.expect(!node.isTaintSource());

    node.setTainted(null); // Source
    try std.testing.expect(node.isTaintSource());

    node.setTainted(2); // Not source
    try std.testing.expect(!node.isTaintSource());
}

test "DataNode - isPointer" {
    const location = Location.init("test_func");

    const pointer_node = DataNode.init(1, .pointer, location);
    try std.testing.expect(pointer_node.isPointer());

    const integer_node = DataNode.init(2, .integer, location);
    try std.testing.expect(!integer_node.isPointer());
}

test "DataNode - isFunction" {
    const location = Location.init("test_func");

    const function_node = DataNode.init(1, .function, location);
    try std.testing.expect(function_node.isFunction());

    const pointer_node = DataNode.init(2, .pointer, location);
    try std.testing.expect(!pointer_node.isFunction());
}

test "DataNode - getSize" {
    const location = Location.init("test_func");

    const node1 = DataNode.init(1, .pointer, location);
    try std.testing.expect(node1.getSize() == null);

    var metadata = DataNode.NodeMetadata.init();
    metadata.size = 64;
    const node2 = DataNode.initWithMetadata(2, .pointer, location, metadata);
    try std.testing.expectEqual(@as(u64, 64), node2.getSize().?);
}

test "DataNode - getName" {
    const location = Location.init("test_func");

    const node1 = DataNode.init(1, .pointer, location);
    try std.testing.expect(node1.getName() == null);

    var metadata = DataNode.NodeMetadata.init();
    metadata.name = "test_var";
    const node2 = DataNode.initWithMetadata(2, .pointer, location, metadata);
    try std.testing.expectEqualStrings("test_var", node2.getName().?);
}

test "NodeMetadata - init" {
    const metadata = DataNode.NodeMetadata.init();

    try std.testing.expect(metadata.size == null);
    try std.testing.expect(metadata.name == null);
    try std.testing.expect(!metadata.is_parameter);
    try std.testing.expect(!metadata.is_return_value);
}
