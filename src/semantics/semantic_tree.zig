//! Semantic resolution tree - a unified data structure for cross-language
//! semantic analysis.
//!
//! This module provides a generic semantic tree that can store semantic
//! information about code constructs across different languages. It's designed
//! to be language-agnostic while supporting language-specific patterns through
//! the pattern registry system.

const std = @import("std");

/// Semantic kind — what the SRT needs to answer:
/// "Can this value be explained away by language semantics?"
///
/// Only three core kinds: allocation, release, provenance.
/// ownership_transfer / borrow / escape are DFG-level concerns,
/// not SRT-level. Keeping kinds minimal avoids over-complicating
/// pattern registration.
pub const SemanticKind = enum(u8) {
    /// Memory allocation (malloc, __rust_alloc, new, etc.)
    allocation,
    /// Memory release / deallocation (free, drop, delete, etc.)
    release,
    /// Pointer provenance / origin (into_raw, from_raw, etc.)
    provenance,
    /// Unknown semantic construct
    unknown,
};

/// A semantic resolution - the result of applying a pattern to a node
pub const Resolution = struct {
    /// What kind of resolution this is
    kind: SemanticKind,
    /// Confidence level (0.0 - 1.0)
    confidence: f32,
    /// Additional data about the resolution
    data: []const u8,
    /// Source pattern that produced this resolution
    pattern_id: ?usize,
};

/// Reference to a value (pointer, instruction, etc.)
pub const ValueRef = u64;

/// A node in the semantic tree
pub const SemanticNode = struct {
    /// Unique ID for this node
    id: usize,
    /// Kind of semantic construct this represents
    kind: SemanticKind,
    /// Name of the construct (function name, variable name, etc.)
    name: []const u8,
    /// Reference to the underlying value (LLVM instruction, etc.)
    value_ref: ValueRef,
    /// Line/column information
    location: Location,
    /// Resolutions applied to this node
    resolutions: std.ArrayListUnmanaged(Resolution),
    /// Child nodes
    children: std.ArrayListUnmanaged(usize),
    /// Parent node ID (optional)
    parent: ?usize,

    const Self = @This();

    /// Create a new semantic node
    pub fn init(
        allocator: std.mem.Allocator,
        id: usize,
        kind: SemanticKind,
        name: []const u8,
        value_ref: ValueRef,
        location: Location,
    ) !Self {
        return Self{
            .id = id,
            .kind = kind,
            .name = try allocator.dupe(u8, name),
            .value_ref = value_ref,
            .location = location,
            .resolutions = std.ArrayListUnmanaged(Resolution){},
            .children = std.ArrayListUnmanaged(usize){},
            .parent = null,
        };
    }

    /// Deinitialize this node
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.location.deinit(allocator);
        self.resolutions.deinit(allocator);
        self.children.deinit(allocator);
    }

    /// Add a resolution to this node
    pub fn addResolution(self: *Self, allocator: std.mem.Allocator, resolution: Resolution) !void {
        try self.resolutions.append(allocator, resolution);
    }

    /// Add a child node
    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child_id: usize) !void {
        try self.children.append(allocator, child_id);
    }
};

/// Source location information
pub const Location = struct {
    /// File name
    file: []const u8,
    /// Line number
    line: u32,
    /// Column number
    column: u32,

    const Self = @This();

    /// Create a new location
    pub fn init(allocator: std.mem.Allocator, file: []const u8, line: u32, column: u32) !Self {
        return Self{
            .file = try allocator.dupe(u8, file),
            .line = line,
            .column = column,
        };
    }

    /// Deinitialize this location
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.file);
    }
};

/// Semantic resolution tree - stores all semantic nodes
pub const SemanticTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(SemanticNode),
    value_to_node: std.AutoHashMap(ValueRef, usize), // value -> node index

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayListUnmanaged(SemanticNode){},
            .value_to_node = std.AutoHashMap(ValueRef, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.value_to_node.deinit();
    }

    /// Add a new node to the tree
    pub fn addNode(
        self: *Self,
        kind: SemanticKind,
        name: []const u8,
        value_ref: ValueRef,
        location_line: u32,
    ) !usize {
        const id = self.nodes.items.len;
        const location = try Location.init(self.allocator, "unknown", location_line, 0);
        const node = try SemanticNode.init(
            self.allocator,
            id,
            kind,
            name,
            value_ref,
            location,
        );
        try self.nodes.append(self.allocator, node);
        try self.value_to_node.put(value_ref, id);
        return id;
    }

    /// Get a node by ID
    pub fn getNode(self: *const Self, id: usize) ?*const SemanticNode {
        if (id < self.nodes.items.len) {
            return &self.nodes.items[id];
        }
        return null;
    }

    /// Get a node by value reference
    pub fn getNodeByValue(self: *const Self, value_ref: ValueRef) ?*const SemanticNode {
        const id = self.value_to_node.get(value_ref) orelse return null;
        return self.getNode(id);
    }

    /// Add a resolution to a node
    pub fn addResolution(self: *Self, node_id: usize, resolution: Resolution) !void {
        if (node_id < self.nodes.items.len) {
            try self.nodes.items[node_id].addResolution(self.allocator, resolution);
        }
    }

    /// Get resolutions for a node
    pub fn getResolutions(self: *const Self, node_id: usize) []const Resolution {
        if (node_id < self.nodes.items.len) {
            return self.nodes.items[node_id].resolutions.items;
        }
        return &.{};
    }

    /// Get all nodes
    pub fn getNodes(self: *const Self) []const SemanticNode {
        return self.nodes.items;
    }

    /// Find nodes by kind
    pub fn findNodesByKind(_self: *const Self, _kind: SemanticKind) []const SemanticNode {
        _ = _self;
        _ = _kind;
        return &.{};
    }

    /// Find nodes by name
    pub fn findNodesByName(_self: *const Self, _name: []const u8) []const SemanticNode {
        _ = _self;
        _ = _name;
        return &.{};
    }
};

test "Semantic tree basic functionality" {
    const allocator = std.testing.allocator;

    var tree = SemanticTree.init(allocator);
    defer tree.deinit();

    // Add an allocation node
    const alloc_id = try tree.addNode(.allocation, "malloc", 0x1000, 10);
    try std.testing.expect(alloc_id == 0);

    // Add a resolution
    try tree.addResolution(alloc_id, Resolution{
        .kind = .release,
        .confidence = 0.95,
        .data = "test_data",
        .pattern_id = 0,
    });

    // Get the node and check resolutions
    const node = tree.getNode(alloc_id);
    try std.testing.expect(node != null);
    try std.testing.expect(std.mem.eql(u8, node.?.name, "malloc"));

    const resolutions = tree.getResolutions(alloc_id);
    try std.testing.expect(resolutions.len == 1);
    try std.testing.expect(resolutions[0].kind == .release);
    try std.testing.expect(resolutions[0].confidence == 0.95);
}

test "Semantic tree node lookup" {
    const allocator = std.testing.allocator;

    var tree = SemanticTree.init(allocator);
    defer tree.deinit();

    // Add nodes with valid SemanticKind variants
    const alloc_id = try tree.addNode(.allocation, "malloc", 0x1000, 10);
    const release_id = try tree.addNode(.release, "free", 0x1001, 15);

    // Lookup by ID
    const alloc_node = tree.getNode(alloc_id);
    try std.testing.expect(alloc_node != null);
    try std.testing.expect(std.mem.eql(u8, alloc_node.?.name, "malloc"));

    const release_node = tree.getNode(release_id);
    try std.testing.expect(release_node != null);
    try std.testing.expect(std.mem.eql(u8, release_node.?.name, "free"));

    // Lookup by value reference
    const alloc_by_value = tree.getNodeByValue(0x1000);
    try std.testing.expect(alloc_by_value != null);
    try std.testing.expect(std.mem.eql(u8, alloc_by_value.?.name, "malloc"));
}
