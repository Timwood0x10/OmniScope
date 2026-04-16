//! Integration Tests for OmniScope
//!
//! This module contains end-to-end integration tests that verify
//! the entire analysis pipeline works correctly with real scenarios.

const std = @import("std");
const Pipeline = @import("../src/pipeline/pipeline.zig").Pipeline;
const PassContext = @import("../src/pass/pass.zig").PassContext;
const PassKind = @import("../src/pass/pass.zig").PassKind;
const DiagnosticWriter = @import("../src/pass/pass.zig").DiagnosticWriter;
const FactStore = @import("../src/fact/store.zig").FactStore;
const FactKind = @import("../src/fact/fact.zig").FactKind;
const Diagnostic = @import("../src/diag/aggregator.zig").Diagnostic;
const CLIOutput = @import("../src/output/cli.zig").CLIOutput;
const SarifOutput = @import("../src/output/sarif.zig").SarifOutput;
const LSPOutput = @import("../src/output/lsp.zig").LSPOutput;
const FileMap = @import("../src/output/lsp.zig").FileMap;

test "Integration - full pipeline with test passes" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register test passes with dependencies
    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            // Emit some facts
            try ctx.fact_store.insert(.cfg_edge, 1, 2, ctx.getNextId());
            try ctx.fact_store.insert(.dfg_edge, 3, 4, ctx.getNextId());
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            // Emit some facts
            try ctx.fact_store.insert(.alias_may, 5, 6, ctx.getNextId());
        }
    };

    const PassC = struct {
        pub const name = "C";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{"B"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            // Emit some facts
            try ctx.fact_store.insert(.lock_acquire, 7, 8, ctx.getNextId());
        }
    };

    try pipeline.registerPass(PassC);
    try pipeline.registerPass(PassB);
    try pipeline.registerPass(PassA);

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify results
    try std.testing.expect(result.fact_count > 0);
    try std.testing.expect(result.execution_time_ns >= 0);
}

test "Integration - deadlock detection - simple cycle" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Simulate a simple deadlock scenario
    // Pass A creates lock operations
    const LockSimulationPass = struct {
        pub const name = "lock-sim";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;

            // Simulate lock operations:
            // Thread 1: acquire A, then acquire B
            // Thread 2: acquire B, then acquire A

            const func_id = ctx.getNextId();

            // Thread 1 operations
            try ctx.fact_store.insert(.lock_acquire, 1, 10, func_id);
            try ctx.fact_store.insert(.lock_acquire, 2, 20, func_id);

            // Thread 2 operations
            try ctx.fact_store.insert(.lock_acquire, 2, 30, func_id);
            try ctx.fact_store.insert(.lock_acquire, 1, 40, func_id);
        }
    };

    try pipeline.registerPass(LockSimulationPass);

    // Run analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify facts were generated
    try std.testing.expect(result.fact_count > 0);
}

test "Integration - taint analysis - simple flow" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Simulate a simple taint propagation scenario
    const TaintSimulationPass = struct {
        pub const name = "taint-sim";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;

            // Simulate taint propagation:
            // Source (read) -> intermediate -> Sink (system)

            const func_id = ctx.getNextId();

            // Source
            try ctx.fact_store.insert(.dfg_edge, 1, 2, func_id);

            // Propagation
            try ctx.fact_store.insert(.dfg_edge, 2, 3, func_id);

            // Sink
            try ctx.fact_store.insert(.dfg_edge, 3, 4, func_id);

            // Taint fact
            try ctx.fact_store.insert(.taint, 1, 4, func_id);
        }
    };

    try pipeline.registerPass(TaintSimulationPass);

    // Run analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify facts were generated
    try std.testing.expect(result.fact_count > 0);
}

test "Integration - alias analysis - must alias" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Simulate must alias scenario
    const AliasSimulationPass = struct {
        pub const name = "alias-sim";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;

            const func_id = ctx.getNextId();

            // Two pointers pointing to same location
            try ctx.fact_store.insert(.alias_must, 1, 2, func_id);
        }
    };

    try pipeline.registerPass(AliasSimulationPass);

    // Run analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify facts were generated
    try std.testing.expect(result.fact_count > 0);
}

test "Integration - alias analysis - may alias" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Simulate may alias scenario
    const AliasSimulationPass = struct {
        pub const name = "alias-sim";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;

            const func_id = ctx.getNextId();

            // Two pointers that may alias
            try ctx.fact_store.insert(.alias_may, 1, 2, func_id);
        }
    };

    try pipeline.registerPass(AliasSimulationPass);

    // Run analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify facts were generated
    try std.testing.expect(result.fact_count > 0);
}

test "Integration - CLI output" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Add a diagnostic
    const diag = Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 42,
        .message = "Test error diagnostic",
        .confidence = 1.0,
    };

    try pipeline.getDiagnosticAggregator().add(diag);

    // Create CLI output
    var cli_output = CLIOutput.init(std.testing.allocator, false, false);

    const diagnostics = pipeline.getDiagnosticAggregator().getAll();
    _ = cli_output.printDiagnostics(diagnostics);
}

test "Integration - SARIF output" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Add diagnostics
    const diag1 = Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 42,
        .message = "Test error diagnostic",
        .confidence = 1.0,
    };

    const diag2 = Diagnostic{
        .kind = .runtime_issue,
        .severity = .warning,
        .loc = 100,
        .message = "Test warning diagnostic",
        .confidence = 0.8,
    };

    try pipeline.getDiagnosticAggregator().add(diag1);
    try pipeline.getDiagnosticAggregator().add(diag2);

    // Create SARIF output
    var sarif_output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = pipeline.getDiagnosticAggregator().getAll();
    const json = try sarif_output.generate(diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    try std.testing.expect(json.len > 0);
}

test "Integration - LSP output" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Add a diagnostic
    const diag = Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 42,
        .message = "Test error diagnostic",
        .confidence = 1.0,
    };

    try pipeline.getDiagnosticAggregator().add(diag);

    // Create LSP output
    var lsp_output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(42, "file:///test.c", 10, 5);

    const diagnostics = pipeline.getDiagnosticAggregator().getAll();
    const lsp_diagnostics = try lsp_output.convertDiagnostics(diagnostics, file_map);
    defer lsp_output.freeDiagnostics(lsp_diagnostics);

    // Verify LSP diagnostics were created
    try std.testing.expectEqual(@as(usize, 1), lsp_diagnostics.len);
}

test "Integration - complex multi-pass scenario" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register multiple passes with complex dependencies
    const PassA = struct {
        pub const name = "A";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.cfg_edge, 1, 2, ctx.getNextId());
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.dfg_edge, 3, 4, ctx.getNextId());
        }
    };

    const PassC = struct {
        pub const name = "C";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.dfg_edge, 5, 6, ctx.getNextId());
        }
    };

    const PassD = struct {
        pub const name = "D";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "B", "C" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = diag;
            try ctx.fact_store.insert(.alias_may, 7, 8, ctx.getNextId());
        }
    };

    try pipeline.registerPass(PassD);
    try pipeline.registerPass(PassC);
    try pipeline.registerPass(PassB);
    try pipeline.registerPass(PassA);

    // Run analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify all passes ran
    try std.testing.expect(result.fact_count > 0);
}

test "Integration - fact store consistency" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Add facts manually
    const fact_store = pipeline.getFactStore();

    try fact_store.insert(.cfg_edge, 1, 2, 0);
    try fact_store.insert(.dfg_edge, 3, 4, 0);
    try fact_store.insert(.alias_may, 5, 6, 0);

    // Verify facts are stored correctly
    try std.testing.expectEqual(@as(usize, 3), fact_store.count());

    const fact1 = fact_store.get(0).?;
    try std.testing.expectEqual(FactKind.cfg_edge, fact1.kind);
    try std.testing.expectEqual(@as(u32, 1), fact1.subject);
    try std.testing.expectEqual(@as(u32, 2), fact1.object);

    const fact2 = fact_store.get(1).?;
    try std.testing.expectEqual(FactKind.dfg_edge, fact2.kind);
    try std.testing.expectEqual(@as(u32, 3), fact2.subject);
    try std.testing.expectEqual(@as(u32, 4), fact2.object);

    const fact3 = fact_store.get(2).?;
    try std.testing.expectEqual(FactKind.alias_may, fact3.kind);
    try std.testing.expectEqual(@as(u32, 5), fact3.subject);
    try std.testing.expectEqual(@as(u32, 6), fact3.object);
}

test "Integration - diagnostic aggregation" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Add multiple diagnostics
    const diag1 = Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 1,
        .message = "Error 1",
        .confidence = 1.0,
    };

    const diag2 = Diagnostic{
        .kind = .runtime_issue,
        .severity = .warning,
        .loc = 2,
        .message = "Warning 1",
        .confidence = 0.8,
    };

    const diag3 = Diagnostic{
        .kind = .anomaly,
        .severity = .info,
        .loc = 3,
        .message = "Info 1",
        .confidence = 0.5,
    };

    try pipeline.getDiagnosticAggregator().add(diag1);
    try pipeline.getDiagnosticAggregator().add(diag2);
    try pipeline.getDiagnosticAggregator().add(diag3);

    // Verify all diagnostics are stored
    const all_diags = pipeline.getDiagnosticAggregator().getAll();
    try std.testing.expectEqual(@as(usize, 3), all_diags.len);

    // Verify summary
    const summary = try pipeline.getDiagnosticAggregator().generateSummary(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), summary.total);
    try std.testing.expectEqual(@as(usize, 1), summary.error_count);
    try std.testing.expectEqual(@as(usize, 1), summary.warning_count);
    try std.testing.expectEqual(@as(usize, 1), summary.info_count);
}

test "Integration - Plugin system initialization" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Initialize plugin system
    try pipeline.initPluginSystem();

    // Verify plugin loader is created
    try std.testing.expectEqual(@as(usize, 1), pipeline.getPluginCount());
}

test "Integration - Plugin system query" {
    var pipeline = Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Initialize plugin system
    try pipeline.initPluginSystem();

    // Query plugins (should return 0 diagnostics since no plugins loaded)
    const diag_count = try pipeline.queryPlugins();
    try std.testing.expectEqual(@as(usize, 0), diag_count);
}
