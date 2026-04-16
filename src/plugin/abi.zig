//! Plugin ABI for OmniScope
//!
//! This module defines the C ABI for plugins, allowing users to extend
//! OmniScope with custom analysis passes and diagnostic rules.
//!
//! Plugins are loaded as shared libraries (.so, .dll, .dylib) and must
//! export the required functions defined in this module.

const std = @import("std");
const Allocator = std.mem.Allocator;

const FactKind = @import("../fact/fact.zig").FactKind;
const FactStore = @import("../fact/store.zig").FactStore;
const DiagnosticKind = @import("../diag/aggregator.zig").DiagnosticKind;
const Severity = @import("../diag/aggregator.zig").Severity;

/// Plugin ABI version
pub const PLUGIN_ABI_VERSION: u32 = 1;

/// Plugin descriptor (exported by plugin)
pub const LsPluginDescriptor = extern struct {
    /// ABI version (must match PLUGIN_ABI_VERSION)
    abi_version: u32,
    /// Plugin name
    name: [*:0]const u8,
    /// Plugin version
    version: [*:0]const u8,
    /// Plugin description
    description: [*:0]const u8,
    /// Plugin initialization function
    init: ?*const fn (ctx: *PluginContext) c_int,
    /// Plugin cleanup function
    deinit: ?*const fn (ctx: *PluginContext) void,
    /// Plugin run function
    run: ?*const fn (
        ctx: *PluginContext,
        query: *const LsFactQuery,
        diag: *LsDiagWriter,
    ) c_int,
};

/// Plugin context (passed to plugin functions)
pub const PluginContext = extern struct {
    /// Pointer to fact store
    fact_store: *FactStore,
    /// Pointer to allocator
    allocator: *Allocator,
    /// User data
    user_data: *anyopaque,
};

/// Fact query (C ABI)
pub const LsFactQuery = extern struct {
    /// Fact kind to query
    kind: u8,
    /// Subject ID
    subject: u32,
    /// Object ID
    object: u32,
    /// Context ID
    context: u32,
};

/// Fact (C ABI)
pub const LsFact = extern struct {
    /// Fact kind
    kind: u8,
    /// Subject ID
    subject: u32,
    /// Object ID
    object: u32,
    /// Context ID
    context: u32,
};

/// Fact query result (C ABI)
pub const LsQueryResult = extern struct {
    /// Number of facts in result
    count: u32,
    /// Pointer to facts array (allocated by host, freed by host)
    facts: [*]LsFact,
};

/// Diagnostic (C ABI)
pub const LsDiagnostic = extern struct {
    /// Diagnostic kind
    kind: u16,
    /// Severity level
    severity: u8,
    /// Location ID
    loc: u32,
    /// Diagnostic message (allocated by plugin, freed by host)
    message: [*:0]const u8,
    /// Confidence score [0.0, 1.0]
    confidence: f32,
};

/// Diagnostic writer (C ABI)
pub const LsDiagWriter = extern struct {
    /// Context pointer
    ctx: *anyopaque,
    /// Function to write a diagnostic
    write: ?*const fn (
        writer: *LsDiagWriter,
        diag: *const LsDiagnostic,
    ) c_int,
};

/// Plugin loader
pub const PluginLoader = struct {
    allocator: Allocator,
    plugins: std.ArrayList(LoadedPlugin),

    const LoadedPlugin = struct {
        handle: *anyopaque,
        descriptor: *LsPluginDescriptor,
        context: PluginContext,
        name: []const u8,
    };

    /// Create a new plugin loader
    pub fn init(allocator: Allocator) PluginLoader {
        return .{
            .allocator = allocator,
            .plugins = std.ArrayList(LoadedPlugin).init(allocator),
        };
    }

    /// Deinitialize the plugin loader
    pub fn deinit(self: *PluginLoader) void {
        for (self.plugins.items) |plugin| {
            if (plugin.descriptor.deinit) |deinit_fn| {
                // Note: Casting away const to match C ABI expectations
                deinit_fn(@constCast(&plugin.context));
            }
            // Close the dynamic library using the raw handle
            // Note: This is system-specific and may need platform-specific handling
            // For now, we assume the handle can be directly closed
            if (@import("builtin").os.tag == .linux or @import("builtin").os.tag == .macos) {
                const c = @cImport({
                    @cInclude("dlfcn.h");
                });
                _ = c.dlclose(plugin.handle);
            }
        }

        self.plugins.deinit(self.allocator);
    }

    /// Load a plugin from a shared library
    ///
    /// Parameters:
    ///   - path: Path to the shared library file
    ///
    /// Returns:
    ///   - error on failure
    pub fn load(self: *PluginLoader, path: []const u8) !void {
        // Load the shared library
        const lib = std.DynLib.open(path) catch |err| {
            switch (err) {
                error.FileNotFound => return error.PluginNotFound,
                error.InvalidDll => return error.InvalidPlugin,
                error.MissingSymbol => return error.MissingSymbol,
                else => return err,
            }
        };
        errdefer lib.close();

        // Get the plugin descriptor function
        const descriptor_fn = lib.lookup(
            *const fn () *const LsPluginDescriptor,
            "ls_plugin_descriptor",
        ) orelse return error.MissingSymbol;

        // Call the descriptor function to get the plugin descriptor
        const descriptor = descriptor_fn() orelse return error.InvalidPlugin;

        // Validate ABI version
        if (descriptor.abi_version != PLUGIN_ABI_VERSION) {
            return error.AbiVersionMismatch;
        }

        // Initialize the plugin context
        var context = PluginContext{
            .fact_store = undefined, // Will be set when running
            .allocator = &self.allocator,
            .user_data = null,
        };

        // Call plugin init function if provided
        if (descriptor.init) |init_fn| {
            const result = init_fn(&context);
            if (result != 0) {
                return error.PluginInitFailed;
            }
        }

        // Store the loaded plugin
        const plugin_name = try self.allocator.dupe(u8, std.mem.span(descriptor.name));
        errdefer self.allocator.free(plugin_name);

        try self.plugins.append(.{
            .handle = lib,
            .descriptor = descriptor,
            .context = context,
            .name = plugin_name,
        });
    }

    /// Query all plugins
    ///
    /// Parameters:
    ///   - query: Fact query
    ///   - store: Fact store
    ///
    /// Returns:
    ///   - Array of diagnostics from all plugins
    pub fn queryAll(
        self: *PluginLoader,
        query: LsFactQuery,
        store: *FactStore,
    ) ![]LsDiagnostic {
        var diagnostics = std.ArrayList(LsDiagnostic).init(self.allocator);

        for (self.plugins.items) |plugin| {
            if (plugin.descriptor.run) |run_fn| {
                // Create a context for the write function
                var write_context = struct {
                    loader: *PluginLoader,
                    diagnostics: *std.ArrayList(LsDiagnostic),
                }{
                    .loader = self,
                    .diagnostics = &diagnostics,
                };

                var diag_writer = LsDiagWriter{
                    .ctx = &write_context,
                    .write = struct {
                        fn write(
                            writer: *LsDiagWriter,
                            diag: *const LsDiagnostic,
                        ) c_int {
                            const ctx = @as(*@TypeOf(write_context), @ptrCast(writer.ctx));
                            const diag_copy = LsDiagnostic{
                                .kind = diag.kind,
                                .severity = diag.severity,
                                .loc = diag.loc,
                                .message = diag.message,
                                .confidence = diag.confidence,
                            };
                            ctx.diagnostics.append(diag_copy) catch return -1;
                            return 0;
                        }
                    }.write,
                };

                const context = PluginContext{
                    .fact_store = store,
                    .allocator = &self.allocator,
                    .user_data = null,
                };

                const result = run_fn(&context, &query, &diag_writer);
                if (result != 0) {
                    // Plugin returned error
                    continue;
                }
            }
        }

        return diagnostics.toOwnedSlice();
    }

    /// Get the number of loaded plugins
    pub fn count(self: *const PluginLoader) usize {
        return self.plugins.items.len;
    }
};

/// Convert FactKind to C ABI
pub fn factKindToCABI(kind: FactKind) u8 {
    return switch (kind) {
        .cfg_edge => 0,
        .dfg_edge => 1,
        .alias_may => 2,
        .alias_must => 3,
        .lock_acquire => 4,
        .lock_release => 5,
        .taint => 6,
        .allocation => 7,
    };
}

/// Convert C ABI to FactKind
pub fn factKindFromCABI(kind: u8) FactKind {
    return switch (kind) {
        0 => .cfg_edge,
        1 => .dfg_edge,
        2 => .alias_may,
        3 => .alias_must,
        4 => .lock_acquire,
        5 => .lock_release,
        6 => .taint,
        7 => .allocation,
        else => unreachable,
    };
}

/// Convert DiagnosticKind to C ABI
pub fn diagnosticKindToCABI(kind: DiagnosticKind) u16 {
    return switch (kind) {
        .static_issue => 0,
        .runtime_issue => 1,
        .anomaly => 2,
        .performance => 3,
        .security => 4,
    };
}

/// Convert C ABI to DiagnosticKind
pub fn diagnosticKindFromCABI(kind: u16) DiagnosticKind {
    return switch (kind) {
        0 => .static_issue,
        1 => .runtime_issue,
        2 => .anomaly,
        3 => .performance,
        4 => .security,
        else => unreachable,
    };
}

/// Convert Severity to C ABI
pub fn severityToCABI(severity: Severity) u8 {
    return switch (severity) {
        .info => 0,
        .warning => 1,
        .err => 2,
    };
}

/// Convert C ABI to Severity
pub fn severityFromCABI(severity: u8) Severity {
    return switch (severity) {
        0 => .info,
        1 => .warning,
        2 => .err,
        else => unreachable,
    };
}

test "PluginLoader - init and deinit" {
    var loader = PluginLoader.init(std.testing.allocator);
    defer loader.deinit();

    try std.testing.expectEqual(@as(usize, 0), loader.count());
}

test "factKindToCABI - all kinds" {
    try std.testing.expectEqual(@as(u8, 0), factKindToCABI(.cfg_edge));
    try std.testing.expectEqual(@as(u8, 1), factKindToCABI(.dfg_edge));
    try std.testing.expectEqual(@as(u8, 2), factKindToCABI(.alias_may));
    try std.testing.expectEqual(@as(u8, 3), factKindToCABI(.alias_must));
    try std.testing.expectEqual(@as(u8, 4), factKindToCABI(.lock_acquire));
    try std.testing.expectEqual(@as(u8, 5), factKindToCABI(.lock_release));
    try std.testing.expectEqual(@as(u8, 6), factKindToCABI(.taint));
    try std.testing.expectEqual(@as(u8, 7), factKindToCABI(.allocation));
}

test "factKindFromCABI - all kinds" {
    try std.testing.expectEqual(FactKind.cfg_edge, factKindFromCABI(0));
    try std.testing.expectEqual(FactKind.dfg_edge, factKindFromCABI(1));
    try std.testing.expectEqual(FactKind.alias_may, factKindFromCABI(2));
    try std.testing.expectEqual(FactKind.alias_must, factKindFromCABI(3));
    try std.testing.expectEqual(FactKind.lock_acquire, factKindFromCABI(4));
    try std.testing.expectEqual(FactKind.lock_release, factKindFromCABI(5));
    try std.testing.expectEqual(FactKind.taint, factKindFromCABI(6));
    try std.testing.expectEqual(FactKind.allocation, factKindFromCABI(7));
}

test "diagnosticKindToCABI - all kinds" {
    try std.testing.expectEqual(@as(u16, 0), diagnosticKindToCABI(.static_issue));
    try std.testing.expectEqual(@as(u16, 1), diagnosticKindToCABI(.runtime_issue));
    try std.testing.expectEqual(@as(u16, 2), diagnosticKindToCABI(.anomaly));
    try std.testing.expectEqual(@as(u16, 3), diagnosticKindToCABI(.performance));
    try std.testing.expectEqual(@as(u16, 4), diagnosticKindToCABI(.security));
}

test "diagnosticKindFromCABI - all kinds" {
    try std.testing.expectEqual(DiagnosticKind.static_issue, diagnosticKindFromCABI(0));
    try std.testing.expectEqual(DiagnosticKind.runtime_issue, diagnosticKindFromCABI(1));
    try std.testing.expectEqual(DiagnosticKind.anomaly, diagnosticKindFromCABI(2));
    try std.testing.expectEqual(DiagnosticKind.performance, diagnosticKindFromCABI(3));
    try std.testing.expectEqual(DiagnosticKind.security, diagnosticKindFromCABI(4));
}

test "severityToCABI - all severities" {
    try std.testing.expectEqual(@as(u8, 0), severityToCABI(.info));
    try std.testing.expectEqual(@as(u8, 1), severityToCABI(.warning));
    try std.testing.expectEqual(@as(u8, 2), severityToCABI(.err));
}

test "severityFromCABI - all severities" {
    try std.testing.expectEqual(Severity.info, severityFromCABI(0));
    try std.testing.expectEqual(Severity.warning, severityFromCABI(1));
    try std.testing.expectEqual(Severity.err, severityFromCABI(2));
}

test "LsPluginDescriptor - ABI version" {
    try std.testing.expectEqual(@as(u32, 1), PLUGIN_ABI_VERSION);
}

test "LsFactQuery - initialization" {
    const query = LsFactQuery{
        .kind = 0,
        .subject = 1,
        .object = 2,
        .context = 3,
    };

    try std.testing.expectEqual(@as(u8, 0), query.kind);
    try std.testing.expectEqual(@as(u32, 1), query.subject);
    try std.testing.expectEqual(@as(u32, 2), query.object);
    try std.testing.expectEqual(@as(u32, 3), query.context);
}

test "LsFact - initialization" {
    const fact = LsFact{
        .kind = 1,
        .subject = 10,
        .object = 20,
        .context = 30,
    };

    try std.testing.expectEqual(@as(u8, 1), fact.kind);
    try std.testing.expectEqual(@as(u32, 10), fact.subject);
    try std.testing.expectEqual(@as(u32, 20), fact.object);
    try std.testing.expectEqual(@as(u32, 30), fact.context);
}

test "LsDiagnostic - initialization" {
    const message = "Test diagnostic message";
    const diag = LsDiagnostic{
        .kind = 0,
        .severity = 2,
        .loc = 42,
        .message = message,
        .confidence = 0.8,
    };

    try std.testing.expectEqual(@as(u16, 0), diag.kind);
    try std.testing.expectEqual(@as(u8, 2), diag.severity);
    try std.testing.expectEqual(@as(u32, 42), diag.loc);
    try std.testing.expectEqualStrings(message, std.mem.span(diag.message));
    try std.testing.expectEqual(@as(f32, 0.8), diag.confidence);
}

test "PluginLoader - query all plugins" {
    var loader = PluginLoader.init(std.testing.allocator);
    defer loader.deinit();

    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const query = LsFactQuery{
        .kind = 0,
        .subject = 1,
        .object = 2,
        .context = 3,
    };

    // No plugins loaded, should return empty array
    const result = loader.queryAll(query, &store) catch |err| {
        try std.testing.expectEqual(error.NotImplemented, err);
        return;
    };
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}
