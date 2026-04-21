//! CLI Output Module
//!
//! This module provides command-line output formatting for diagnostics,
//! including color support for terminals and structured message display.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Diagnostic = @import("../diag/aggregator.zig").Diagnostic;
const DiagnosticKind = @import("../diag/aggregator.zig").DiagnosticKind;
const Severity = @import("../diag/aggregator.zig").Severity;
const SummaryReport = @import("../diag/aggregator.zig").SummaryReport;

/// CLI Output
pub const CLIOutput = struct {
    allocator: Allocator,
    color_enabled: bool,
    verbose: bool,
    stderr_writer: std.io.BufferedWriter(4096, std.fs.File.Writer),

    /// ANSI color codes
    const Color = struct {
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const magenta = "\x1b[35m";
        const cyan = "\x1b[36m";
        const white = "\x1b[37m";
        const dim = "\x1b[2m";
    };

    /// Create a new CLI output instance
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - color_enabled: Whether to enable colored output
    ///   - verbose: Whether to enable verbose output
    pub fn init(allocator: Allocator, color_enabled: bool, verbose: bool) CLIOutput {
        const stderr_file = std.io.getStdErr();
        return .{
            .allocator = allocator,
            .color_enabled = color_enabled,
            .verbose = verbose,
            .stderr_writer = std.io.bufferedWriter(stderr_file.writer()),
        };
    }

    /// Flush and cleanup
    pub fn deinit(self: *CLIOutput) void {
        self.stderr_writer.flush() catch {};
    }

    /// Print diagnostics to stderr
    ///
    /// Parameters:
    ///   - diagnostics: Array of diagnostics to print
    pub fn printDiagnostics(self: *CLIOutput, diagnostics: []Diagnostic) !void {
        const writer = self.stderr_writer.writer();

        for (diagnostics, 0..) |diag, i| {
            // Print separator between diagnostics
            if (i > 0) {
                try writer.writeAll("\n");
            }

            // Print diagnostic header
            try self.printDiagnosticHeader(writer, diag);

            // Print diagnostic message
            try self.printDiagnosticMessage(writer, diag);

            // Print confidence if verbose
            if (self.verbose) {
                try self.printConfidence(writer, diag);
            }

            // Print location
            try self.printLocation(writer, diag);

            // Flush after each diagnostic
            try self.stderr_writer.flush();
        }
    }

    /// Print a summary report
    ///
    /// Parameters:
    ///   - summary: Summary report to print
    pub fn printSummary(self: *CLIOutput, summary: SummaryReport) !void {
        const writer = self.stderr_writer.writer();

        // Print summary header
        try self.printColored(writer, Color.bold, "Summary");
        try writer.writeAll("\n");

        // Print total count
        try writer.print("  Total diagnostics: {d}\n", .{summary.total});

        // Print error count
        if (summary.error_count > 0) {
            try self.printColored(writer, Color.red, "  Errors: ");
            try writer.print("{d}\n", .{summary.error_count});
        }

        // Print warning count
        if (summary.warning_count > 0) {
            try self.printColored(writer, Color.yellow, "  Warnings: ");
            try writer.print("{d}\n", .{summary.warning_count});
        }

        // Print info count
        if (summary.info_count > 0) {
            try self.printColored(writer, Color.cyan, "  Info: ");
            try writer.print("{d}\n", .{summary.info_count});
        }

        // Print success message if no diagnostics
        if (summary.total == 0) {
            try self.printColored(writer, Color.green, "  ✅ No issues found\n");
        }

        try self.stderr_writer.flush();
    }

    /// Print an error message
    ///
    /// Parameters:
    ///   - msg: Error message to print
    pub fn printError(self: *CLIOutput, msg: []const u8) !void {
        const writer = self.stderr_writer.writer();
        try self.printColored(writer, Color.red, "error");
        try writer.print(": {s}\n", .{msg});
        try self.stderr_writer.flush();
    }

    /// Print a warning message
    ///
    /// Parameters:
    ///   - msg: Warning message to print
    pub fn printWarning(self: *CLIOutput, msg: []const u8) !void {
        const writer = self.stderr_writer.writer();
        try self.printColored(writer, Color.yellow, "warning");
        try writer.print(": {s}\n", .{msg});
        try self.stderr_writer.flush();
    }

    /// Print an info message
    ///
    /// Parameters:
    ///   - msg: Info message to print
    pub fn printInfo(self: *CLIOutput, msg: []const u8) !void {
        const writer = self.stderr_writer.writer();
        try self.printColored(writer, Color.cyan, "info");
        try writer.print(": {s}\n", .{msg});
        try self.stderr_writer.flush();
    }

    /// Print a success message
    ///
    /// Parameters:
    ///   - msg: Success message to print
    pub fn printSuccess(self: *CLIOutput, msg: []const u8) !void {
        const writer = self.stderr_writer.writer();
        try self.printColored(writer, Color.green, "✅");
        try writer.print(" {s}\n", .{msg});
        try self.stderr_writer.flush();
    }

    /// Print diagnostic header
    fn printDiagnosticHeader(self: *CLIOutput, writer: anytype, diag: Diagnostic) !void {
        // Print severity label with appropriate color
        switch (diag.severity) {
            .err => {
                try self.printColored(writer, Color.red, "error");
            },
            .warning => {
                try self.printColored(writer, Color.yellow, "warning");
            },
            .info => {
                try self.printColored(writer, Color.cyan, "info");
            },
        }

        // Print diagnostic kind
        try writer.writeAll(" [");
        try self.printDiagnosticKind(writer, diag.kind);
        try writer.writeAll("]\n");
    }

    /// Print diagnostic message
    fn printDiagnosticMessage(self: *CLIOutput, writer: anytype, diag: Diagnostic) !void {
        _ = self;
        try writer.writeAll("  ");
        try writer.writeAll(diag.message);
        try writer.writeAll("\n");
    }

    /// Print confidence score
    fn printConfidence(self: *CLIOutput, writer: anytype, diag: Diagnostic) !void {
        try writer.writeAll("  ");
        try self.printColored(writer, Color.dim, "confidence: ");
        try writer.print("{d:.2}\n", .{diag.confidence});
    }

    /// Print location
    fn printLocation(self: *CLIOutput, writer: anytype, diag: Diagnostic) !void {
        try writer.writeAll("  ");
        try self.printColored(writer, Color.dim, "location: ");
        try writer.print("{d}\n", .{diag.loc});
    }

    /// Print diagnostic kind
    fn printDiagnosticKind(self: *CLIOutput, writer: anytype, kind: DiagnosticKind) !void {
        _ = self;
        const kind_str = switch (kind) {
            .static_issue => "static",
            .runtime_issue => "runtime",
            .anomaly => "anomaly",
            .performance => "performance",
            .security => "security",
        };

        try writer.writeAll(kind_str);
    }

    /// Print colored text if color is enabled
    fn printColored(self: *CLIOutput, writer: anytype, color: []const u8, text: []const u8) !void {
        if (self.color_enabled) {
            try writer.writeAll(color);
            try writer.writeAll(text);
            try writer.writeAll(Color.reset);
        } else {
            try writer.writeAll(text);
        }
    }
};

test "CLIOutput - init" {
    const output = CLIOutput.init(std.testing.allocator, false, false);
    _ = output;
}

test "CLIOutput - print summary with no diagnostics" {
    var output = CLIOutput.init(std.testing.allocator, false, false);

    const summary = SummaryReport{
        .total = 0,
        .error_count = 0,
        .warning_count = 0,
        .info_count = 0,
    };

    // Note: This will print to stderr, not captured in tests
    // In real usage, this would display the summary
    _ = output.printSummary(summary);
}

test "CLIOutput - print summary with diagnostics" {
    var output = CLIOutput.init(std.testing.allocator, false, false);

    const summary = SummaryReport{
        .total = 5,
        .error_count = 2,
        .warning_count = 2,
        .info_count = 1,
    };

    // Note: This will print to stderr, not captured in tests
    _ = output.printSummary(summary);
}

test "CLIOutput - print error" {
    var output = CLIOutput.init(std.testing.allocator, false, false);
    _ = output.printError("Test error message");
}

test "CLIOutput - print warning" {
    var output = CLIOutput.init(std.testing.allocator, false, false);
    _ = output.printWarning("Test warning message");
}

test "CLIOutput - print info" {
    var output = CLIOutput.init(std.testing.allocator, false, false);
    _ = output.printInfo("Test info message");
}

test "CLIOutput - print success" {
    var output = CLIOutput.init(std.testing.allocator, false, false);
    _ = output.printSuccess("Test success message");
}

test "CLIOutput - print diagnostics" {
    var output = CLIOutput.init(std.testing.allocator, false, false);

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 42,
            .message = "Test error diagnostic",
            .confidence = 1.0,
        },
        .{
            .kind = .runtime_issue,
            .severity = .warning,
            .loc = 100,
            .message = "Test warning diagnostic",
            .confidence = 0.8,
        },
    };

    // Note: This will print to stderr, not captured in tests
    _ = output.printDiagnostics(&diagnostics);
}

test "CLIOutput - color codes" {
    // Verify color codes are defined
    try std.testing.expectEqualStrings("\x1b[0m", CLIOutput.Color.reset);
    try std.testing.expectEqualStrings("\x1b[1m", CLIOutput.Color.bold);
    try std.testing.expectEqualStrings("\x1b[31m", CLIOutput.Color.red);
    try std.testing.expectEqualStrings("\x1b[32m", CLIOutput.Color.green);
    try std.testing.expectEqualStrings("\x1b[33m", CLIOutput.Color.yellow);
    try std.testing.expectEqualStrings("\x1b[34m", CLIOutput.Color.blue);
    try std.testing.expectEqualStrings("\x1b[35m", CLIOutput.Color.magenta);
    try std.testing.expectEqualStrings("\x1b[36m", CLIOutput.Color.cyan);
    try std.testing.expectEqualStrings("\x1b[37m", CLIOutput.Color.white);
    try std.testing.expectEqualStrings("\x1b[2m", CLIOutput.Color.dim);
}

test "CLIOutput - diagnostic kind strings" {
    var output = CLIOutput.init(std.testing.allocator, false, false);
    const writer = std.io.null_writer;

    // Test all diagnostic kinds
    const kinds = [_]DiagnosticKind{
        .static_issue,
        .runtime_issue,
        .anomaly,
        .performance,
        .security,
    };

    for (kinds) |kind| {
        // This just ensures the function doesn't crash
        _ = output.printDiagnosticKind(writer, kind);
    }
}

test "CLIOutput - verbose mode" {
    const output_verbose = CLIOutput.init(std.testing.allocator, false, true);
    try std.testing.expect(output_verbose.verbose);

    const output_quiet = CLIOutput.init(std.testing.allocator, false, false);
    try std.testing.expect(!output_quiet.verbose);
}

test "CLIOutput - color mode" {
    const output_color = CLIOutput.init(std.testing.allocator, true, false);
    try std.testing.expect(output_color.color_enabled);

    const output_plain = CLIOutput.init(std.testing.allocator, false, false);
    try std.testing.expect(!output_plain.color_enabled);
}

test "CLIOutput - print diagnostics with all severities" {
    var output = CLIOutput.init(std.testing.allocator, false, false);

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 1,
            .message = "Error diagnostic",
            .confidence = 1.0,
        },
        .{
            .kind = .runtime_issue,
            .severity = .warning,
            .loc = 2,
            .message = "Warning diagnostic",
            .confidence = 0.8,
        },
        .{
            .kind = .anomaly,
            .severity = .info,
            .loc = 3,
            .message = "Info diagnostic",
            .confidence = 0.5,
        },
    };

    _ = output.printDiagnostics(&diagnostics);
}
