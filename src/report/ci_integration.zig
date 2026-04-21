//! OmniScope CI/CD Integration Examples
//!
//! This module demonstrates how to integrate OmniScope into various
//! CI/CD pipelines for automated security analysis.

const std = @import("std");
const Issue = @import("../diag/issue.zig").Issue;
const generateSarif = @import("../report/sarif.zig").generateSarif;
const writeSarifToFile = @import("../report/sarif.zig").writeSarifToFile;
const ToolInfo = @import("../report/sarif.zig").ToolInfo;

/// CI/CD platform types
pub const CIPlatform = enum {
    github_actions,
    gitlab_ci,
    azure_pipelines,
    jenkins,
    circleci,
    travis_ci,
    local,
};

/// CI configuration for running OmniScope
pub const CIConfig = struct {
    /// Platform type
    platform: CIPlatform,
    /// Output format (sarif, json, text)
    output_format: OutputFormat,
    /// Output file path
    output_file: []const u8,
    /// Fail build on critical issues
    fail_on_critical: bool,
    /// Fail build on high issues
    fail_on_high: bool,
    /// Maximum issues before failure
    max_issues: ?usize,
    /// Include source code snippets
    include_snippets: bool,
    /// Tool information for SARIF
    tool_info: ToolInfo,

    pub const OutputFormat = enum {
        sarif,
        json,
        text,
    };

    /// Default configuration for GitHub Actions
    pub fn githubDefault() CIConfig {
        return .{
            .platform = .github_actions,
            .output_format = .sarif,
            .output_file = "omniscope-results.sarif",
            .fail_on_critical = true,
            .fail_on_high = false,
            .max_issues = null,
            .include_snippets = true,
            .tool_info = .{
                .name = "OmniScope",
                .version = "0.1.0",
                .information_uri = "https://github.com/omniscope/omniscope",
            },
        };
    }

    /// Default configuration for local development
    pub fn localDefault() CIConfig {
        return .{
            .platform = .local,
            .output_format = .text,
            .output_file = "omniscope-report.txt",
            .fail_on_critical = false,
            .fail_on_high = false,
            .max_issues = null,
            .include_snippets = true,
            .tool_info = .{
                .name = "OmniScope",
                .version = "0.1.0",
                .information_uri = "https://github.com/omniscope/omniscope",
            },
        };
    }
};

/// CI runner for executing OmniScope analysis
pub const CIRunner = struct {
    allocator: std.mem.Allocator,
    config: CIConfig,
    issues: std.ArrayList(Issue),

    /// Initialize CI runner
    pub fn init(allocator: std.mem.Allocator, config: CIConfig) !CIRunner {
        return .{
            .allocator = allocator,
            .config = config,
            .issues = try std.ArrayList(Issue).initCapacity(allocator, 0),
        };
    }

    /// Deinitialize runner
    pub fn deinit(self: *CIRunner) void {
        for (self.issues.items) |*issue| {
            issue.deinit(self.allocator);
        }
        self.issues.deinit(self.allocator);
    }

    /// Add an issue
    pub fn addIssue(self: *CIRunner, issue: Issue) !void {
        try self.issues.append(self.allocator, issue);
    }

    /// Run analysis and generate output
    pub fn run(self: *CIRunner) !CIResult {
        const issues = self.issues.items;

        // Generate output based on format
        switch (self.config.output_format) {
            .sarif => try self.generateSarifOutput(issues),
            .json => try self.generateJsonOutput(issues),
            .text => try self.generateTextOutput(issues),
        }

        // Calculate statistics
        var critical_count: usize = 0;
        var high_count: usize = 0;
        var medium_count: usize = 0;
        var low_count: usize = 0;

        for (issues) |issue| {
            switch (issue.severity) {
                .critical => critical_count += 1,
                .high => high_count += 1,
                .medium => medium_count += 1,
                .low => low_count += 1,
            }
        }

        // Determine if build should fail
        const should_fail = self.shouldFail(critical_count, high_count, issues.len);

        return .{
            .total_issues = issues.len,
            .critical_count = critical_count,
            .high_count = high_count,
            .medium_count = medium_count,
            .low_count = low_count,
            .should_fail = should_fail,
            .output_file = self.config.output_file,
        };
    }

    /// Generate SARIF output
    fn generateSarifOutput(self: *CIRunner, issues: []const Issue) !void {
        try writeSarifToFile(self.allocator, self.config.output_file, issues, self.config.tool_info);
    }

    /// Generate JSON output
    fn generateJsonOutput(self: *CIRunner, issues: []const Issue) !void {
        var output = std.ArrayList(u8).initCapacity(self.allocator, 8192) catch return error.OutOfMemory;
        defer output.deinit(self.allocator);

        try output.appendSlice("{\n");
        try output.writer().print("  \"tool\": \"{s}\",\n", .{self.config.tool_info.name});
        try output.writer().print("  \"version\": \"{s}\",\n", .{self.config.tool_info.version});
        try output.appendSlice("  \"issues\": [\n");

        for (issues, 0..) |issue, i| {
            if (i > 0) try output.appendSlice(",\n");

            // Escape JSON strings properly
            const escaped_message = std.json.stringEncode(self.allocator, issue.message) catch {
                // If encoding fails, write unescaped message to avoid crash
                try output.writer().print("    {{\"kind\": \"{s}\", \"severity\": \"{s}\", \"message\": \"{s}\"}}", .{
                    issue.kind.toString(),
                    issue.severity.toString(),
                    issue.message,
                });
                continue;
            };
            defer self.allocator.free(escaped_message);

            try output.writer().print("    {{\"kind\": \"{s}\", \"severity\": \"{s}\", \"message\": {s}}}", .{
                issue.kind.toString(),
                issue.severity.toString(),
                escaped_message,
            });
        }

        try output.appendSlice("\n  ]\n");
        try output.appendSlice("}\n");

        const file = try std.fs.cwd().createFile(self.config.output_file, .{});
        defer file.close();
        try file.writeAll(output.items);
    }

    /// Generate text output
    fn generateTextOutput(self: *CIRunner, issues: []const Issue) !void {
        var output = std.ArrayList(u8).initCapacity(self.allocator, 4096) catch return error.OutOfMemory;
        defer output.deinit(self.allocator);

        try output.appendSlice("=== OmniScope Security Analysis ===\n\n");

        if (issues.len == 0) {
            try output.appendSlice("No issues found.\n");
        } else {
            try output.writer().print("Found {d} issue(s):\n\n", .{issues.len});

            for (issues, 0..) |issue, i| {
                try output.writer().print("[{d}] {s} ({s})\n", .{
                    i + 1,
                    issue.kind.toString(),
                    issue.severity.toString(),
                });
                try output.writer().print("    {s}\n\n", .{issue.message});
            }
        }

        const file = try std.fs.cwd().createFile(self.config.output_file, .{});
        defer file.close();
        try file.writeAll(output.items);
    }

    /// Determine if build should fail
    fn shouldFail(self: *CIRunner, critical_count: usize, high_count: usize, total: usize) bool {
        if (self.config.fail_on_critical and critical_count > 0) return true;
        if (self.config.fail_on_high and high_count > 0) return true;
        if (self.config.max_issues) |max| {
            if (total > max) return true;
        }
        return false;
    }
};

/// CI analysis result
pub const CIResult = struct {
    total_issues: usize,
    critical_count: usize,
    high_count: usize,
    medium_count: usize,
    low_count: usize,
    should_fail: bool,
    output_file: []const u8,

    /// Print summary to stdout
    pub fn printSummary(self: *const CIResult) void {
        std.log.info("=== OmniScope Analysis Summary ===", .{});
        std.log.info("Total issues: {d}", .{self.total_issues});
        std.log.info("  Critical: {d}", .{self.critical_count});
        std.log.info("  High: {d}", .{self.high_count});
        std.log.info("  Medium: {d}", .{self.medium_count});
        std.log.info("  Low: {d}", .{self.low_count});
        std.log.info("Output: {s}", .{self.output_file});

        if (self.should_fail) {
            std.log.err("Build should fail due to security issues!", .{});
        } else {
            std.log.info("Build passed security checks.", .{});
        }
    }

    /// Get exit code
    pub fn exitCode(self: *const CIResult) u8 {
        return if (self.should_fail) 1 else 0;
    }
};

pub fn generateGitHubWorkflow(allocator: std.mem.Allocator) ![]const u8 {
    var output = std.ArrayList(u8).initCapacity(allocator, 4096) catch return error.OutOfMemory;
    defer output.deinit();

    try output.appendSlice(
        \\name: OmniScope Security Analysis
        \\
        \\on:
        \\  push:
        \\    branches: [main, develop]
        \\  pull_request:
        \\    branches: [main]
        \\
        \\jobs:
        \\  security-analysis:
        \\    runs-on: ubuntu-latest
        \\    permissions:
        \\      security-events: write
        \\      contents: read
        \\
        \\    steps:
        \\      - name: Checkout code
        \\        uses: actions/checkout@v4
        \\
        \\      - name: Setup Zig
        \\        uses: mlugg/setup-zig@v1
        \\        with:
        \\          zig-version: 0.15.2
        \\
        \\      - name: Build OmniScope
        \\        run: |
        \\          git clone https://github.com/omniscope/omniscope.git
        \\          cd omniscope
        \\          zig build -Doptimize=ReleaseSafe
        \\
        \\      - name: Build target project
        \\        run: |
        \\          # Build your project and generate LLVM IR
        \\          # Example for Rust:
        \\          # cargo build --release
        \\          # Example for C:
        \\          # clang -emit-llvm -c -o output.bc input.c
        \\          echo "Build your project here"
        \\
        \\      - name: Run OmniScope analysis
        \\        run: |
        \\          ./omniscope/zig-out/bin/OmniSope \
        \\            --output-format sarif \
        \\            --output-file results.sarif \
        \\            build/*.bc 2>/dev/null || true
        \\
        \\      - name: Upload SARIF to GitHub Security
        \\        uses: github/codeql-action/upload-sarif@v3
        \\        with:
        \\          sarif_file: results.sarif
        \\          category: omniscope-security
        \\
        \\      - name: Check for critical vulnerabilities
        \\        run: |
        \\          if [ -f results.sarif ]; then
        \\            CRITICAL=$(grep -c '"level": "error"' results.sarif || echo "0")
        \\            if [ "$CRITICAL" -gt 0 ]; then
        \\              echo "::error::Found $CRITICAL critical security issues!"
        \\              exit 1
        \\            fi
        \\          fi
        \\
    );

    return output.toOwnedSlice(allocator);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "CIConfig - githubDefault" {
    const config = CIConfig.githubDefault();
    try std.testing.expectEqual(CIPlatform.github_actions, config.platform);
    try std.testing.expectEqual(CIConfig.OutputFormat.sarif, config.output_format);
    try std.testing.expect(config.fail_on_critical);
}

test "CIConfig - localDefault" {
    const config = CIConfig.localDefault();
    try std.testing.expectEqual(CIPlatform.local, config.platform);
    try std.testing.expectEqual(CIConfig.OutputFormat.text, config.output_format);
    try std.testing.expect(!config.fail_on_critical);
}

test "CIRunner - init and deinit" {
    var runner = try CIRunner.init(std.testing.allocator, CIConfig.localDefault());
    defer runner.deinit();
    try std.testing.expectEqual(@as(usize, 0), runner.issues.items.len);
}

test "CIRunner - add issue" {
    var runner = try CIRunner.init(std.testing.allocator, CIConfig.localDefault());
    defer runner.deinit();

    const Location = @import("../diag/issue.zig").Location;

    const issue = Issue.init(
        .command_injection,
        "Test issue",
        Location.init("test_func"),
        .critical,
        0.9,
    );

    try runner.addIssue(issue);
    try std.testing.expectEqual(@as(usize, 1), runner.issues.items.len);
}

test "CIResult - exit code" {
    const result_pass = CIResult{
        .total_issues = 0,
        .critical_count = 0,
        .high_count = 0,
        .medium_count = 0,
        .low_count = 0,
        .should_fail = false,
        .output_file = "test.sarif",
    };
    try std.testing.expectEqual(@as(u8, 0), result_pass.exitCode());

    const result_fail = CIResult{
        .total_issues = 1,
        .critical_count = 1,
        .high_count = 0,
        .medium_count = 0,
        .low_count = 0,
        .should_fail = true,
        .output_file = "test.sarif",
    };
    try std.testing.expectEqual(@as(u8, 1), result_fail.exitCode());
}

test "generateGitHubWorkflow" {
    const workflow = try generateGitHubWorkflow(std.testing.allocator);
    defer std.testing.allocator.free(workflow);

    try std.testing.expect(std.mem.indexOf(u8, workflow, "OmniScope Security Analysis") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "upload-sarif") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "security-events") != null);
}
