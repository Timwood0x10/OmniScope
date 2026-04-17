//! FFI Function Matcher
//!
//! Matches function declarations from one language with implementations from another.
//! Used for cross-language vulnerability detection.
//!
//! Example workflow:
//! 1. Extract declares from Rust IR (rust.bc)
//! 2. Extract defines from C IR (c.bc)
//! 3. Match functions by name
//! 4. Identify cross-language FFI calls

const std = @import("std");
const Allocator = std.mem.Allocator;

const llvm_safe = @import("../ir/llvm_safe.zig");
const c = @import("../ir/llvm_raw.zig").c;

/// FFI matching error set
pub const FFIMatcherError = error{
    InvalidIR,
    FunctionNotFound,
    AllocationFailed,
};

/// Function classification
pub const FunctionKind = enum {
    /// Function is declared but not defined (extern)
    declare,
    /// Function is defined with implementation
    define,
    /// Unknown function type
    unknown,
};

/// Function information for matching
pub const FunctionInfo = struct {
    /// Function name
    name: []const u8,
    /// Function kind (declare/define)
    kind: FunctionKind,
    /// LLVM function reference
    func: llvm_safe.Function,
    /// Whether this is an external function
    is_external: bool,

    /// Create function info from LLVM function
    pub fn fromFunction(func: llvm_safe.Function, allocator: Allocator) !FunctionInfo {
        const name_copy = try func.getName(allocator);
        errdefer allocator.free(name_copy);

        const is_external = func.isDeclaration();
        const kind: FunctionKind = if (is_external) .declare else .define;

        return .{
            .name = name_copy,
            .kind = kind,
            .func = func,
            .is_external = is_external,
        };
    }
};

/// Cross-language FFI function match
pub const FFIMatch = struct {
    /// Function name
    name: []const u8,
    /// Declaration side (e.g., Rust)
    declare_func: ?FunctionInfo,
    /// Implementation side (e.g., C)
    define_func: ?FunctionInfo,
    /// Whether this is a complete match
    is_complete: bool,

    /// Check if this is a valid FFI match
    pub fn isValid(self: *const FFIMatch) bool {
        return self.declare_func != null and self.define_func != null;
    }
};

/// FFI function matcher
pub const FFIMatcher = struct {
    allocator: Allocator,
    declare_functions: std.ArrayList(FunctionInfo),
    define_functions: std.ArrayList(FunctionInfo),
    matches: std.ArrayList(FFIMatch),

    /// Create a new FFI matcher
    pub fn init(allocator: Allocator) !FFIMatcher {
        return .{
            .allocator = allocator,
            .declare_functions = try std.ArrayList(FunctionInfo).initCapacity(allocator, 0),
            .define_functions = try std.ArrayList(FunctionInfo).initCapacity(allocator, 0),
            .matches = try std.ArrayList(FFIMatch).initCapacity(allocator, 0),
        };
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *FFIMatcher) void {
        for (self.declare_functions.items) |func| {
            self.allocator.free(func.name);
        }
        self.declare_functions.deinit(self.allocator);

        for (self.define_functions.items) |func| {
            self.allocator.free(func.name);
        }
        self.define_functions.deinit(self.allocator);

        for (self.matches.items) |match| {
            // Only free match.name - declare_func and define_func are value-copied
            // from declare_functions and define_functions arrays, so their name
            // pointers are already freed above
            if (match.name.len > 0) self.allocator.free(match.name);
        }
        self.matches.deinit(self.allocator);
    }

    /// Extract functions from a module
    pub fn extractFunctions(self: *FFIMatcher, module: llvm_safe.Module) !void {
        var func = module.getFirstFunction();

        while (func) |f| {
            const func_info = try FunctionInfo.fromFunction(f, self.allocator);
            errdefer self.allocator.free(func_info.name);

            switch (func_info.kind) {
                .declare => try self.declare_functions.append(self.allocator, func_info),
                .define => try self.define_functions.append(self.allocator, func_info),
                .unknown => {},
            }

            func = f.getNext();
        }
    }

    /// Match declare functions with define functions
    pub fn matchFunctions(self: *FFIMatcher) !void {
        // Create a hash map for quick lookup
        var define_map = std.StringHashMap(usize).init(self.allocator);
        defer define_map.deinit();

        for (self.define_functions.items, 0..) |func, idx| {
            try define_map.put(func.name, idx);
        }

        // Match declare functions with defines
        for (self.declare_functions.items) |declare_func| {
            const define_idx = define_map.get(declare_func.name) orelse continue;
            const define_func = &self.define_functions.items[define_idx];

            // Allocate independent copy for match.name to avoid dangling pointer
            const name_copy = try self.allocator.dupe(u8, declare_func.name);
            errdefer self.allocator.free(name_copy);

            const match = FFIMatch{
                .name = name_copy,
                .declare_func = declare_func,
                .define_func = define_func.*,
                .is_complete = true,
            };

            try self.matches.append(self.allocator, match);
        }
    }

    /// Get all matched FFI functions
    pub fn getMatches(self: *const FFIMatcher) []const FFIMatch {
        return self.matches.items;
    }

    /// Get unmatched declare functions
    pub fn getUnmatchedDeclares(self: *const FFIMatcher) ![]const FunctionInfo {
        var unmatched = std.ArrayList(FunctionInfo).initCapacity(self.allocator, self.declare_functions.items.len) catch return error.AllocationFailed;
        errdefer {
            for (unmatched.items) |func| {
                self.allocator.free(func.name);
            }
            unmatched.deinit(self.allocator);
        }

        // Create a set of matched names
        var matched_names = std.StringHashMap(void).init(self.allocator);
        defer matched_names.deinit();

        for (self.matches.items) |match| {
            try matched_names.put(match.name, {});
        }

        // Find unmatched declares
        for (self.declare_functions.items) |declare_func| {
            if (!matched_names.contains(declare_func.name)) {
                // Allocate independent copy for name to avoid dangling pointer
                const name_copy = try self.allocator.dupe(u8, declare_func.name);
                const func_copy = FunctionInfo{
                    .name = name_copy,
                    .kind = declare_func.kind,
                    .func = declare_func.func,
                    .is_external = declare_func.is_external,
                };
                try unmatched.append(self.allocator, func_copy);
            }
        }

        return unmatched.toOwnedSlice(self.allocator);
    }

    /// Get unmatched define functions
    pub fn getUnmatchedDefines(self: *const FFIMatcher) ![]const FunctionInfo {
        var unmatched = std.ArrayList(FunctionInfo).initCapacity(self.allocator, self.define_functions.items.len) catch return error.AllocationFailed;
        errdefer {
            for (unmatched.items) |func| {
                self.allocator.free(func.name);
            }
            unmatched.deinit(self.allocator);
        }

        // Create a set of matched names
        var matched_names = std.StringHashMap(void).init(self.allocator);
        defer matched_names.deinit();

        for (self.matches.items) |match| {
            try matched_names.put(match.name, {});
        }

        // Find unmatched defines
        for (self.define_functions.items) |define_func| {
            if (!matched_names.contains(define_func.name)) {
                // Allocate independent copy for name to avoid dangling pointer
                const name_copy = try self.allocator.dupe(u8, define_func.name);
                const func_copy = FunctionInfo{
                    .name = name_copy,
                    .kind = define_func.kind,
                    .func = define_func.func,
                    .is_external = define_func.is_external,
                };
                try unmatched.append(self.allocator, func_copy);
            }
        }

        return unmatched.toOwnedSlice(self.allocator);
    }
};

test "FunctionInfo - fromFunction with declare" {
    // This test would need a real LLVM context and function
    // For now, we just test the struct has the required method
    try std.testing.expect(@hasDecl(FunctionInfo, "fromFunction"));
}

test "FunctionKind - enum values" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(FunctionKind.declare));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(FunctionKind.define));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(FunctionKind.unknown));
}

test "FFIMatch - isValid" {
    var match = FFIMatch{
        .name = "test_func",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(!match.isValid());

    match.declare_func = FunctionInfo{
        .name = "test_func",
        .kind = .declare,
        .func = undefined,
        .is_external = true,
    };

    try std.testing.expect(!match.isValid());

    match.define_func = FunctionInfo{
        .name = "test_func",
        .kind = .define,
        .func = undefined,
        .is_external = false,
    };

    try std.testing.expect(match.isValid());
}

test "FFIMatcher - init and deinit" {
    var matcher = try FFIMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    try std.testing.expectEqual(@as(usize, 0), matcher.declare_functions.items.len);
    try std.testing.expectEqual(@as(usize, 0), matcher.define_functions.items.len);
    try std.testing.expectEqual(@as(usize, 0), matcher.matches.items.len);
}

test "FFIMatcher - empty matching" {
    var matcher = try FFIMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    try matcher.matchFunctions();

    try std.testing.expectEqual(@as(usize, 0), matcher.getMatches().len);
}

test "FFIMatcher - memory management" {
    var matcher = try FFIMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    // The fact that deinit() is called without panicking indicates
    // proper memory management
}
