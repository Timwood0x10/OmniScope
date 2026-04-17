# Diag Module

## Overview

The Diag module defines core issue types and diagnostic aggregation functionality used throughout the analysis. This module represents detected security problems or code quality issues and aggregates diagnostic information from various sources (static analysis, runtime verification, merge engine) to produce unified reports.

## Module Structure

```text
src/diag/
├── aggregator.zig  # Diagnostic aggregator
└── issue.zig      # Issue type definitions
```

## IssueKind

Issue type enumeration defining the categories of security issues that can be detected.

### IssueKind Enumeration Definition

```zig
/// Issue type enumeration
///
/// Defines the categories of security issues that can be detected.
pub const IssueKind = enum {
    /// FFI call without proper safety validation
    ffi_unsafe_call,
    /// Function return value not checked after call
    unchecked_return,
    /// Type mismatch across FFI boundary
    type_mismatch,
    /// Memory leak across language boundary
    cross_language_leak,
    /// Use after free across language boundary
    use_after_free,
    /// Command injection vulnerability
    command_injection,
    /// Buffer overflow vulnerability
    buffer_overflow,
    /// Double free across language boundary
    double_free,
    /// Format string vulnerability
    format_string,
    /// Unknown issue type
    unknown,

    /// Convert issue kind to string representation
    pub fn toString(self: IssueKind) []const u8 {
        return switch (self) {
            .ffi_unsafe_call => "ffi_unsafe_call",
            .unchecked_return => "unchecked_return",
            .type_mismatch => "type_mismatch",
            .cross_language_leak => "cross_language_leak",
            .use_after_free => "use_after_free",
            .command_injection => "command_injection",
            .buffer_overflow => "buffer_overflow",
            .double_free => "double_free",
            .format_string => "format_string",
            .unknown => "unknown",
        };
    }
};
```

### IssueKind Types

- **ffi_unsafe_call**: FFI call without proper safety validation
- **unchecked_return**: Function return value not checked after call
- **type_mismatch**: Type mismatch across FFI boundary
- **cross_language_leak**: Memory leak across language boundary
- **use_after_free**: Use after free across language boundary
- **command_injection**: Command injection vulnerability
- **buffer_overflow**: Buffer overflow vulnerability
- **double_free**: Double free across language boundary
- **format_string**: Format string vulnerability
- **unknown**: Unknown issue type

## Severity

Severity level enumeration defining the severity levels for issues.

### Severity Enumeration Definition

```zig
/// Severity level enumeration
///
/// Defines the severity levels for issues.
pub const Severity = enum(u8) {
    /// Low severity issue
    low = 0,
    /// Medium severity issue
    medium = 1,
    /// High severity issue
    high = 2,
    /// Critical severity issue
    critical = 3,

    /// Convert severity to string representation
    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
            .critical => "critical",
        };
    }

    /// Get severity color code for terminal output
    pub fn toColorCode(self: Severity) []const u8 {
        return switch (self) {
            .low => "\x1b[36m", // Cyan
            .medium => "\x1b[33m", // Yellow
            .high => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};
```

### Severity Levels

- **low**: Low severity issue
- **medium**: Medium severity issue
- **high**: High severity issue
- **critical**: Critical severity issue

## Issue

Structure representing a detected security problem, containing the issue type, location, severity, and optional FFI boundary context.

### Issue Structure Definition

```zig
/// Issue represents a detected security problem
///
/// This struct contains all information about a detected issue including
/// its type, location, severity, and optional context about FFI boundaries.
pub const Issue = struct {
    /// Type of the issue
    kind: IssueKind,
    /// Human-readable description of the issue
    message: []const u8,
    /// Location where the issue was detected
    location: Location,
    /// Severity level of the issue
    severity: Severity,
    /// Confidence score (0.0 - 1.0)
    confidence: f32,
    /// Related FFI boundary if applicable
    ffi_boundary: ?FFIBoundary,
};
```

### Issue Fields

- **kind**: `IssueKind` - Type of the issue
- **message**: `[]const u8` - Human-readable description of the issue
- **location**: `Location` - Location where the issue was detected
- **severity**: `Severity` - Severity level of the issue
- **confidence**: `f32` - Confidence score (0.0 - 1.0)
- **ffi_boundary**: `?FFIBoundary` - Related FFI boundary if applicable

### Issue Methods

#### init()

Create a new issue.

**Parameters:**

- `kind`: Type of the issue
- `message`: Description of the issue
- `location`: Location where issue was detected
- `severity`: Severity level
- `confidence`: Confidence score (0.0 - 1.0)

**Returns:** New Issue instance

```zig
const location = Location.init("test_func");
const issue = Issue.init(
    .ffi_unsafe_call,
    "Test message",
    location,
    .high,
    0.9,
);
```

#### setFFIBoundary()

Set FFI boundary for this issue.

**Parameters:**

- `boundary`: The FFI boundary related to this issue

```zig
const boundary = FFIBoundary.init(1, .rust_to_c, .rust, .c, "func", location);
issue.setFFIBoundary(boundary);
```

#### hasFFIBoundary()

Check if issue has associated FFI boundary.

**Returns:** `true` if issue has associated FFI boundary

```zig
if (issue.hasFFIBoundary()) {
    // Handle FFI-related issue
}
```

## Location

Location information for an issue, containing function, file, line, and column information.

### Location Structure Definition

```zig
/// Location information for an issue
///
/// Contains the location where an issue was detected, including function,
/// file, line, and column information.
pub const Location = struct {
    /// Function name where issue was detected
    function: []const u8,
    /// File name (optional, may not be available)
    file: ?[]const u8,
    /// Line number (optional, may not be available)
    line: ?u32,
    /// Column number (optional, may not be available)
    column: ?u32,
};
```

### Location Fields

- **function**: `[]const u8` - Function name where issue was detected
- **file**: `?[]const u8` - File name (optional, may not be available)
- **line**: `?u32` - Line number (optional, may not be available)
- **column**: `?u32` - Column number (optional, may not be available)

### Location Methods

#### init()

Create a new location with minimal information.

**Parameters:**

- `function`: Function name

**Returns:** New Location instance

```zig
const location = Location.init("test_func");
```

#### initFull()

Create a new location with full information.

**Parameters:**

- `function`: Function name
- `file`: File name
- `line`: Line number
- `column`: Column number

**Returns:** New Location instance

```zig
const location = Location.initFull("test_func", "test.zig", 42, 10);
```

#### format()

Format location as string.

**Returns:** String representation of location

```zig
const formatted = try location.format(allocator);
defer allocator.free(formatted);
std.debug.print("Location: {s}\n", .{formatted});
```

## FFIBoundary

FFI boundary information containing Foreign Function Interface boundary information where data crosses language boundaries.

### FFIBoundary Structure Definition

```zig
/// FFI boundary information
///
/// Contains information about a Foreign Function Interface boundary
/// where data crosses language boundaries.
pub const FFIBoundary = struct {
    /// Unique identifier for this boundary
    id: u32,
    /// Type of FFI boundary
    kind: BoundaryKind,
    /// Language of the caller
    caller_language: Language,
    /// Language of the callee
    callee_language: Language,
    /// Function name at the boundary
    function_name: []const u8,
    /// Location of the boundary
    location: Location,

    /// FFI boundary type enumeration
    pub const BoundaryKind = enum {
        /// Rust calling C
        rust_to_c,
        /// Zig calling C
        zig_to_c,
        /// C calling Rust
        c_to_rust,
        /// C calling Zig
        c_to_zig,
        /// Unknown external call
        external_unknown,
    };

    /// Language type enumeration
    pub const Language = enum {
        /// C language
        c,
        /// Rust language
        rust,
        /// Zig language
        zig,
        /// Unknown language
        unknown,
    };
};
```

### FFIBoundary Fields

- **id**: `u32` - Unique identifier for this boundary
- **kind**: `BoundaryKind` - Type of FFI boundary
- **caller_language**: `Language` - Language of the caller
- **callee_language**: `Language` - Language of the callee
- **function_name**: `[]const u8` - Function name at the boundary
- **location**: `Location` - Location of the boundary

### FFIBoundary.BoundaryKind Types

- **rust_to_c**: Rust calling C
- **zig_to_c**: Zig calling C
- **c_to_rust**: C calling Rust
- **c_to_zig**: C calling Zig
- **external_unknown**: Unknown external call

### FFIBoundary.Language Types

- **c**: C language
- **rust**: Rust language
- **zig**: Zig language
- **unknown**: Unknown language

### FFIBoundary Methods

#### init()

Create a new FFI boundary.

**Parameters:**

- `id`: Unique identifier
- `kind`: Type of boundary
- `caller_language`: Language of caller
- `callee_language`: Language of callee
- `function_name`: Function name at boundary
- `location`: Location of boundary

**Returns:** New FFIBoundary instance

```zig
const boundary = FFIBoundary.init(
    1,
    .rust_to_c,
    .rust,
    .c,
    "external_func",
    location,
);
```

#### isCrossLanguage()

Check if this is a cross-language boundary.

**Returns:** `true` if caller and callee languages are different

```zig
if (boundary.isCrossLanguage()) {
    // Handle cross-language boundary
}
```

## DiagnosticAggregator

Diagnostic aggregator that aggregates diagnostics from various sources (static analysis, runtime verification, merge engine) and produces unified reports.

### DiagnosticAggregator Structure Definition

```zig
/// Diagnostic aggregator
pub const DiagnosticAggregator = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),
};
```

### DiagnosticAggregator Fields

- **allocator**: `std.mem.Allocator` - Memory allocator
- **diagnostics**: `std.ArrayList(Diagnostic)` - List of diagnostics

### DiagnosticAggregator Methods

#### init()

Create a new diagnostic aggregator.

**Parameters:**

- `allocator`: Memory allocator

**Returns:** New DiagnosticAggregator instance

```zig
var aggregator = DiagnosticAggregator.init(allocator);
defer aggregator.deinit();
```

#### deinit()

Release aggregator resources.

```zig
aggregator.deinit();
```

#### add()

Add a diagnostic.

**Parameters:**

- `diag`: The diagnostic to add

```zig
const diag = Diagnostic{
    .kind = .static_issue,
    .severity = .warning,
    .loc = 42,
    .message = "Test diagnostic",
    .confidence = 0.8,
};
try aggregator.add(diag);
```

#### getAll()

Get all diagnostics.

**Returns:** Slice of diagnostics

```zig
const all = aggregator.getAll();
```

#### getBySeverity()

Get diagnostics by severity.

**Parameters:**

- `severity`: Severity level
- `allocator`: Memory allocator

**Returns:** Newly allocated slice of diagnostics owned by caller, must be freed

```zig
const errors = try aggregator.getBySeverity(.err, allocator);
defer freeDiagnosticsSlice(allocator, errors);
```

#### getByKind()

Get diagnostics by kind.

**Parameters:**

- `kind`: Diagnostic kind
- `allocator`: Memory allocator

**Returns:** Newly allocated slice of diagnostics owned by caller, must be freed

```zig
const static_issues = try aggregator.getByKind(.static_issue, allocator);
defer freeDiagnosticsSlice(allocator, static_issues);
```

#### aggregateFromEvents()

Aggregate diagnostics from merged events.

**Parameters:**

- `events`: Array of merged events

```zig
try aggregator.aggregateFromEvents(events);
```

#### generateSummary()

Generate a summary report.

**Parameters:**

- `allocator`: Memory allocator

**Returns:** SummaryReport structure

```zig
const summary = try aggregator.generateSummary(allocator);
std.debug.print("Total: {}, Errors: {}, Warnings: {}\n", .{
    summary.total,
    summary.error_count,
    summary.warning_count,
});
```

#### clear()

Clear all diagnostics.

```zig
aggregator.clear();
```

## Usage Examples

### Creating an Issue

```zig
const std = @import("std");
const diag = @import("diag");

pub fn createIssue() !void {
    const location = diag.Location.init("process_user_input");
    const issue = diag.Issue.init(
        .command_injection,
        "User input passed to system() without validation",
        location,
        .critical,
        0.95,
    );

    std.debug.print("Issue: {} (severity: {})\n", .{ issue.message, issue.severity });
}
```

### Creating an FFI Boundary

```zig
pub fn createFFIBoundary() !void {
    const location = diag.Location.initFull("external_call", "ffi.zig", 42, 10);
    const boundary = diag.FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );

    if (boundary.isCrossLanguage()) {
        std.debug.print("Cross-language FFI boundary detected: {} -> {}\n", .{
            boundary.caller_language,
            boundary.callee_language,
        });
    }
}
```

### Using Diagnostic Aggregator

```zig
pub fn aggregateDiagnostics() !void {
    var aggregator = diag.DiagnosticAggregator.init(allocator);
    defer aggregator.deinit();

    // Add diagnostics
    const location = diag.Location.init("test_func");
    try aggregator.add(diag.Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 42,
        .message = "Potential buffer overflow",
        .confidence = 0.8,
    });

    // Filter by severity
    const errors = try aggregator.getBySeverity(.err, allocator);
    defer diag.freeDiagnosticsSlice(allocator, errors);

    for (errors) |err| {
        std.debug.print("Error: {}\n", .{err.message});
    }

    // Generate summary
    const summary = try aggregator.generateSummary(allocator);
    std.debug.print("Summary: {} total, {} errors, {} warnings\n", .{
        summary.total,
        summary.error_count,
        summary.warning_count,
    });
}
```

## Notes

1. **Memory Management**: DiagnosticAggregator owns its internal diagnostic messages. Slices returned by `getBySeverity` or `getByKind` are owned by the caller and must be freed using `freeDiagnosticsSlice`.
2. **Confidence Scores**: Confidence scores range from 0.0 to 1.0, representing the reliability of detection results.
3. **Location Information**: File, line, and column information are optional and may not be available in certain scenarios (e.g., when analyzing LLVM IR).
4. **FFI Boundaries**: FFIBoundary is primarily used for cross-language analysis to help identify potential security issues where data crosses language boundaries.
5. **Severity Colors**: `Severity.toColorCode()` provides color codes for terminal output to improve readability.
