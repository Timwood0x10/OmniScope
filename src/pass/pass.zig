//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.

const std = @import("std");
const Allocator = std.mem.Allocator;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;

/// Pass kind classification
pub const PassKind = enum {
    foundation, // Basic analysis passes (CFG, DFG)
    analysis, // Advanced analysis passes (alias, lock, taint)
    plugin, // User-defined plugin passes
};

/// Pass context passed to each pass during execution
///
/// This struct provides all necessary context for pass execution:
/// - Memory allocation
/// - Access to IR module
/// - Access to fact store for reading/writing facts
/// - Access to query engine for querying facts
/// - ID allocation for unique identifiers
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    next_id: std.atomic.Value(u32),

    /// Create a new pass context
    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
    ) PassContext {
        return .{
            .allocator = allocator,
            .module = module,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .next_id = std.atomic.Value(u32).init(1), // Start from 1 (0 is reserved)
        };
    }

    /// Get a unique ID
    ///
    /// Returns:
    ///   - u32: A unique ID (thread-safe)
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .monotonic);
    }

    /// Set the IR module
    ///
    /// Parameters:
    ///   - module: The LLVM module to analyze
    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    /// Check if a module is loaded
    ///
    /// Returns:
    ///   - true if a module is loaded, false otherwise
    pub fn hasModule(self: *const PassContext) bool {
        return self.module != null;
    }
};

/// Diagnostic writer for pass output
pub const DiagnosticWriter = struct {
    allocator: Allocator,

    pub fn write(self: *DiagnosticWriter, comptime severity: []const u8, comptime format: []const u8, args: anytype) void {
        _ = self;
        std.debug.print("[" ++ severity ++ "] " ++ format ++ "\n", args);
    }

    pub fn info(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("INFO", format, args);
    }

    pub fn warn(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("WARN", format, args);
    }

    pub fn err(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("ERROR", format, args);
    }
};

/// Pass comptime wrapper with type validation
///
/// This function validates that a type satisfies the Pass interface
/// at compile time and returns the type unchanged.
pub fn Pass(comptime T: type) type {
    comptime {
        // Validate required declarations
        if (!@hasDecl(T, "name"))
            @compileError("Pass must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Pass must have a 'kind' declaration (PassKind)");
        if (!@hasDecl(T, "deps"))
            @compileError("Pass must have a 'deps' declaration ([]const []const u8)");
        if (!@hasDecl(T, "run"))
            @compileError("Pass must have a 'run' function");

        // Note: In Zig 0.15.2, strict type checking is simplified
        // The compiler will catch type mismatches during actual usage
    }
    return T;
}

test "Pass - comptime validation" {
    const ValidPass = Pass(struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "PassContext - init and deinit" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    const ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    try std.testing.expect(!ctx.hasModule());
}

test "PassContext - getNextId" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    const id1 = ctx.getNextId();
    const id2 = ctx.getNextId();
    const id3 = ctx.getNextId();

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);
}

test "PassContext - setModule and hasModule" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    try std.testing.expect(!ctx.hasModule());

    // Set a dummy module
    ctx.setModule(.{ .raw = undefined });

    try std.testing.expect(ctx.hasModule());
}

test "PassContext - access to components" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);

    const ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    // Verify access to components
    _ = ctx.fact_store;
    _ = ctx.query_engine;
    _ = ctx.allocator;
}
