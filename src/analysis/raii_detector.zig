//! RAII (Resource Acquisition Is Initialization) pattern detector
//!
//! Identifies C++ destructors, Rust Drop implementations, and other
//! automatic cleanup mechanisms that prevent memory leaks.

const std = @import("std");

pub const RAIIDetector = struct {
    allocator: std.mem.Allocator,

    raii_patterns: std.ArrayList(RAIITypePattern),

    pub const RAIIType = enum {
        cpp_destructor,
        rust_drop,
        smart_ptr,
        scope_guard,
        defer_cleanup,
    };

    pub const RAIITypePattern = struct {
        type_name_pattern: []const u8,
        cleanup_method: []const u8,
        kind: RAIIType,
        confidence: f32,
    };

    pub fn init(allocator: std.mem.Allocator) !RAIIDetector {
        var self = RAIIDetector{
            .allocator = allocator,
            .raii_patterns = undefined,
        };
        self.raii_patterns = try std.ArrayList(RAIITypePattern).initCapacity(self.allocator, 6);

        try self.registerBuiltinPatterns();

        return self;
    }

    pub fn deinit(self: *RAIIDetector) void {
        self.raii_patterns.deinit(self.allocator);
    }

    fn registerBuiltinPatterns(self: *RAIIDetector) !void {
        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "std::unique_ptr",
            .cleanup_method = "~unique_ptr",
            .kind = .smart_ptr,
            .confidence = 0.98,
        });

        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "std::shared_ptr",
            .cleanup_method = "~shared_ptr",
            .kind = .smart_ptr,
            .confidence = 0.97,
        });

        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "Box<",
            .cleanup_method = "drop",
            .kind = .rust_drop,
            .confidence = 0.99,
        });

        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "Vec<",
            .cleanup_method = "drop",
            .kind = .rust_drop,
            .confidence = 0.99,
        });

        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "String",
            .cleanup_method = "drop",
            .kind = .rust_drop,
            .confidence = 0.99,
        });

        try self.raii_patterns.append(self.allocator, .{
            .type_name_pattern = "*go.defer",
            .cleanup_method = "defer",
            .kind = .defer_cleanup,
            .confidence = 0.90,
        });
    }

    pub fn isRAIIType(self: *RAIIDetector, type_name: []const u8) ?RAIITypePattern {
        for (self.raii_patterns.items) |pattern| {
            if (std.mem.indexOf(u8, type_name, pattern.type_name_pattern)) |_| {
                return pattern;
            }
        }
        return null;
    }

    pub fn detectRAIIWrapper(
        self: *RAIIDetector,
        alloc_inst: u64,
        type_info: ?[]const u8,
    ) ?RAIITypePattern {
        _ = alloc_inst;

        if (type_info) |name| {
            return self.isRAIIType(name);
        }

        return null;
    }

    pub fn shouldSuppressLeakDueToRAII(
        self: *RAIIDetector,
        alloc_node: *const anyopaque,
    ) bool {
        _ = self;
        _ = alloc_node;
        return false;
    }
};

test "RAIIDetector - detects standard patterns" {
    var detector = try RAIIDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expectNotNull(detector.isRAIIType("std::unique_ptr<int>"));
    try std.testing.expectNotNull(detector.isRAIIType("std::shared_ptr<MyClass>"));

    try std.testing.expectNotNull(detector.isRAIIType("Box<i32>"));
    try std.testing.expectNotNull(detector.isRAIIType("Vec<u8>"));

    try std.testing.expectNull(detector.isRAIIType("int*"));
    try std.testing.expectNull(detector.isRAIIType("void*"));
}
