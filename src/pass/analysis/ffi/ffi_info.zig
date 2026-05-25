//! FFI Boundary Information
//!
//! Defines FFI kinds, boundary information, and the FFI boundary detector
//! for identifying cross-language transitions in the call graph.

const std = @import("std");
const Allocator = std.mem.Allocator;
const call_graph = @import("../call_graph.zig");
const ffi_language_classifier = @import("ffi_language_classifier.zig");

/// FFI boundary type classification
pub const FFIKind = enum {
    /// Not an FFI call
    none,
    /// C FFI call
    c_call,
    /// Rust FFI
    rust_ffi,
    /// Go CGO
    go_cgo,
    /// Other language FFI
    other,
};

/// FFI boundary information
pub const FFIBoundaryInfo = struct {
    /// Edge ID in the call graph
    edge_id: u32,
    /// Caller function ID
    caller: u32,
    /// Callee function ID
    callee: u32,
    /// Type of FFI boundary
    kind: FFIKind,
    /// Target language name
    target_language: []const u8,
    /// Whether function is exported to other language
    is_exported: bool,
    /// Whether function is imported from other language
    is_imported: bool,
};

/// FFI boundary detector
pub const FFIBoundaryDetector = struct {
    allocator: Allocator,
    /// Detected FFI boundaries
    boundaries: std.ArrayList(FFIBoundaryInfo),
    /// Language patterns for FFI detection
    language_patterns: std.StringHashMap(FFIKind),

    /// Initialize a new FFI boundary detector
    pub fn init(allocator: Allocator) FFIBoundaryDetector {
        var self_val: FFIBoundaryDetector = .{
            .allocator = allocator,
            .boundaries = std.ArrayList(FFIBoundaryInfo).init(allocator),
            .language_patterns = std.StringHashMap(FFIKind).init(allocator),
        };
        self_val.initPatterns();
        return self_val;
    }

    /// Initialize language patterns
    fn initPatterns(self: *FFIBoundaryDetector) void {
        self.language_patterns.put("rust_", .rust_ffi) catch return;
        self.language_patterns.put("_rust_", .rust_ffi) catch return;
        self.language_patterns.put("cgo_", .go_cgo) catch return;
        self.language_patterns.put("_cgo_", .go_cgo) catch return;
        self.language_patterns.put("go_", .go_cgo) catch return;
        self.language_patterns.put("Java_", .other) catch return;
        self.language_patterns.put("JNI_", .other) catch return;
        self.language_patterns.put("Py_", .other) catch return;
        self.language_patterns.put("python_", .other) catch return;
    }

    /// Deinitialize the detector
    pub fn deinit(self: *FFIBoundaryDetector) void {
        self.boundaries.deinit(self.allocator);
        self.language_patterns.deinit();
    }

    /// Check if a function is an FFI call
    pub fn isFFICall(self: *const FFIBoundaryDetector, func_name: []const u8) bool {
        if (self.classifyFFIKind(func_name) != .none) {
            return true;
        }

        if (call_graph.isLibC(func_name)) {
            return false;
        }

        if (std.mem.startsWith(u8, func_name, "_Z") or
            std.mem.startsWith(u8, func_name, "__"))
        {
            return true;
        }

        return false;
    }

    /// Classify the FFI kind for a function name
    pub fn classifyFFIKind(_: *const FFIBoundaryDetector, func_name: []const u8) FFIKind {
        if (func_name.len == 0) return .none;

        const first_3 = if (func_name.len >= 3) func_name[0..3] else func_name;
        const first_4 = if (func_name.len >= 4) func_name[0..4] else func_name;
        const first_5 = if (func_name.len >= 5) func_name[0..5] else func_name;
        const first_7 = if (func_name.len >= 7) func_name[0..7] else func_name;

        if (std.mem.startsWith(u8, first_4, "rust")) return .rust_ffi;
        if (std.mem.startsWith(u8, first_4, "cgo_")) return .go_cgo;
        if (std.mem.startsWith(u8, first_5, "go_")) return .go_cgo;
        if (std.mem.startsWith(u8, first_5, "Java")) return .other;
        if (std.mem.startsWith(u8, first_4, "JNI_")) return .other;
        if (std.mem.startsWith(u8, first_3, "Py_")) return .other;
        if (std.mem.startsWith(u8, first_7, "python_")) return .other;

        if (std.mem.startsWith(u8, func_name, "_R")) return .rust_ffi;
        if (std.mem.startsWith(u8, func_name, "_ZN") and
            ffi_language_classifier.isRustMangledName(func_name)) return .rust_ffi;
        if (std.mem.startsWith(u8, func_name, "crossbeam_") or
            std.mem.startsWith(u8, func_name, "tokio_") or
            std.mem.startsWith(u8, func_name, "std_"))
        {
            return .rust_ffi;
        }

        return .none;
    }

    /// Add a detected FFI boundary
    pub fn addBoundary(self: *FFIBoundaryDetector, info: FFIBoundaryInfo) !void {
        try self.boundaries.append(info);
    }

    /// Get all detected boundaries
    pub fn getBoundaries(self: *const FFIBoundaryDetector) []const FFIBoundaryInfo {
        return self.boundaries.items;
    }

    /// Clear all detected boundaries
    pub fn clear(self: *FFIBoundaryDetector) void {
        self.boundaries.clearRetainingCapacity();
    }

    /// Get count of detected boundaries
    pub fn boundaryCount(self: *const FFIBoundaryDetector) usize {
        return self.boundaries.items.len;
    }

    /// Get boundaries by kind
    pub fn getBoundariesByKind(self: *const FFIBoundaryDetector, allocator: Allocator, kind: FFIKind) ![]FFIBoundaryInfo {
        var result = std.ArrayList(FFIBoundaryInfo).init(allocator);
        errdefer result.deinit();

        for (self.boundaries.items) |boundary| {
            if (boundary.kind == kind) {
                try result.append(boundary);
            }
        }

        return result.toOwnedSlice();
    }
};

test "FFIKind - enum values" {
    try std.testing.expectEqual(FFIKind.none, .none);
    try std.testing.expectEqual(FFIKind.c_call, .c_call);
    try std.testing.expectEqual(FFIKind.rust_ffi, .rust_ffi);
    try std.testing.expectEqual(FFIKind.go_cgo, .go_cgo);
    try std.testing.expectEqual(FFIKind.other, .other);
}

test "FFIBoundaryInfo - structure" {
    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 100,
        .callee = 200,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };
    try std.testing.expectEqual(@as(u32, 1), info.edge_id);
    try std.testing.expectEqual(@as(u32, 100), info.caller);
    try std.testing.expectEqual(@as(u32, 200), info.callee);
    try std.testing.expectEqual(FFIKind.rust_ffi, info.kind);
    try std.testing.expect(info.is_exported);
    try std.testing.expect(!info.is_imported);
}

test "FFIBoundaryDetector - init and deinit" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();
    try std.testing.expectEqual(@as(usize, 0), detector.boundaries.items.len);
}

test "FFIBoundaryDetector - isFFICall" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expect(detector.isFFICall("rust_function"));
    try std.testing.expect(detector.isFFICall("_Z3fooi"));
    try std.testing.expect(!detector.isFFICall("malloc"));
    try std.testing.expect(!detector.isFFICall("my_function"));
}

test "FFIBoundaryDetector - classifyFFIKind" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expectEqual(FFIKind.rust_ffi, detector.classifyFFIKind("rust_function"));
    try std.testing.expectEqual(FFIKind.go_cgo, detector.classifyFFIKind("cgo_wrapper"));
    try std.testing.expectEqual(FFIKind.none, detector.classifyFFIKind("normal_function"));
}

test "FFIBoundaryDetector - addBoundary" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 10,
        .callee = 20,
        .kind = .c_call,
        .target_language = "C",
        .is_exported = false,
        .is_imported = true,
    };

    try detector.addBoundary(info);
    try std.testing.expectEqual(@as(usize, 1), detector.boundaryCount());
}

test "FFIBoundaryDetector - getBoundaries" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    const info1 = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 10,
        .callee = 20,
        .kind = .c_call,
        .target_language = "C",
        .is_exported = false,
        .is_imported = true,
    };

    const info2 = FFIBoundaryInfo{
        .edge_id = 2,
        .caller = 30,
        .callee = 40,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };

    try detector.addBoundary(info1);
    try detector.addBoundary(info2);

    const boundaries = detector.getBoundaries();
    try std.testing.expectEqual(@as(usize, 2), boundaries.len);
}

test "FFIBoundaryDetector - clear" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 10,
        .callee = 20,
        .kind = .c_call,
        .target_language = "C",
        .is_exported = false,
        .is_imported = true,
    };

    try detector.addBoundary(info);
    try std.testing.expectEqual(@as(usize, 1), detector.boundaryCount());

    detector.clear();
    try std.testing.expectEqual(@as(usize, 0), detector.boundaryCount());
}

test "FFIBoundaryDetector - getBoundariesByKind" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    const info1 = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 10,
        .callee = 20,
        .kind = .c_call,
        .target_language = "C",
        .is_exported = false,
        .is_imported = true,
    };

    const info2 = FFIBoundaryInfo{
        .edge_id = 2,
        .caller = 30,
        .callee = 40,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };

    try detector.addBoundary(info1);
    try detector.addBoundary(info2);

    const rust_boundaries = try detector.getBoundariesByKind(std.testing.allocator, .rust_ffi);
    defer std.testing.allocator.free(rust_boundaries);
    try std.testing.expectEqual(@as(usize, 1), rust_boundaries.len);
}

test "FFIBoundaryInfo - all fields" {
    const info = FFIBoundaryInfo{
        .edge_id = 42,
        .caller = 100,
        .callee = 200,
        .kind = .go_cgo,
        .target_language = "Go",
        .is_exported = true,
        .is_imported = true,
    };

    try std.testing.expectEqual(@as(u32, 42), info.edge_id);
    try std.testing.expectEqual(@as(u32, 100), info.caller);
    try std.testing.expectEqual(@as(u32, 200), info.callee);
    try std.testing.expectEqual(FFIKind.go_cgo, info.kind);
    try std.testing.expectEqualStrings("Go", info.target_language);
    try std.testing.expect(info.is_exported);
    try std.testing.expect(info.is_imported);
}

test "FFIBoundaryDetector - language patterns initialized" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expect(detector.language_patterns.count() > 0);
}

test "FFIBoundaryDetector - detect rust mangled names" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expectEqual(FFIKind.rust_ffi, detector.classifyFFIKind("_ZN4core3str21_$LT$impl$GT$4new17h"));
}

test "FFIBoundaryDetector - detect std rust patterns" {
    var detector = FFIBoundaryDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expectEqual(FFIKind.rust_ffi, detector.classifyFFIKind("std_io_read"));
    try std.testing.expectEqual(FFIKind.rust_ffi, detector.classifyFFIKind("tokio_runtime_start"));
}
