# Diag 模块

## 概述

Diag 模块定义了分析过程中使用的核心问题类型和诊断聚合功能。该模块用于表示检测到的安全问题或代码质量问题，并从各种来源（静态分析、运行时验证、合并引擎）聚合诊断信息以生成统一报告。

## 模块结构

```text
src/diag/
├── aggregator.zig  # 诊断聚合器
└── issue.zig      # 问题类型定义
```

## IssueKind

问题类型枚举，定义了可以检测的安全问题类别。

### IssueKind 枚举定义

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

### IssueKind 类型

- **ffi_unsafe_call**: 没有适当安全验证的 FFI 调用
- **unchecked_return**: 函数调用后未检查返回值
- **type_mismatch**: 跨 FFI 边界的类型不匹配
- **cross_language_leak**: 跨语言边界的内存泄漏
- **use_after_free**: 跨语言边界的释放后使用
- **command_injection**: 命令注入漏洞
- **buffer_overflow**: 缓冲区溢出漏洞
- **double_free**: 跨语言边界的双重释放
- **format_string**: 格式字符串漏洞
- **unknown**: 未知问题类型

## Severity

严重性级别枚举，定义问题的严重性等级。

### Severity 枚举定义

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

### Severity 级别

- **low**: 低严重性问题
- **medium**: 中等严重性问题
- **high**: 高严重性问题
- **critical**: 严重性问题

## Issue

表示检测到的安全问题的结构，包含问题的类型、位置、严重性和可选的 FFI 边界上下文信息。

### Issue 结构定义

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

### Issue 字段

- **kind**: `IssueKind` - 问题的类型
- **message**: `[]const u8` - 问题的人类可读描述
- **location**: `Location` - 检测到问题的位置
- **severity**: `Severity` - 问题的严重性级别
- **confidence**: `f32` - 置信度分数（0.0 - 1.0）
- **ffi_boundary**: `?FFIBoundary` - 相关的 FFI 边界（如果适用）

### Issue 方法

#### init()

创建新问题。

**参数:**

- `kind`: 问题类型
- `message`: 问题描述
- `location`: 检测位置
- `severity`: 严重性级别
- `confidence`: 置信度分数（0.0 - 1.0）

**返回值:** 新的 Issue 实例

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

为此问题设置 FFI 边界。

**参数:**

- `boundary`: 与此问题相关的 FFI 边界

```zig
const boundary = FFIBoundary.init(1, .rust_to_c, .rust, .c, "func", location);
issue.setFFIBoundary(boundary);
```

#### hasFFIBoundary()

检查问题是否有关联的 FFI 边界。

**返回值:** 如果问题有关联的 FFI 边界则返回 true

```zig
if (issue.hasFFIBoundary()) {
    // 处理 FFI 相关问题
}
```

## Location

问题的位置信息，包含函数、文件、行和列信息。

### Location 结构定义

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

### Location 字段

- **function**: `[]const u8` - 检测到问题的函数名
- **file**: `?[]const u8` - 文件名（可选，可能不可用）
- **line**: `?u32` - 行号（可选，可能不可用）
- **column**: `?u32` - 列号（可选，可能不可用）

### Location 方法

#### init()

使用最少信息创建新位置。

**参数:**

- `function`: 函数名

**返回值:** 新的 Location 实例

```zig
const location = Location.init("test_func");
```

#### initFull()

使用完整信息创建新位置。

**参数:**

- `function`: 函数名
- `file`: 文件名
- `line`: 行号
- `column`: 列号

**返回值:** 新的 Location 实例

```zig
const location = Location.initFull("test_func", "test.zig", 42, 10);
```

#### format()

将位置格式化为字符串。

**返回值:** 位置的字符串表示

```zig
const formatted = try location.format(allocator);
defer allocator.free(formatted);
std.debug.print("Location: {s}\n", .{formatted});
```

## FFIBoundary

FFI 边界信息，包含数据跨越语言边界的 Foreign Function Interface 边界信息。

### FFIBoundary 结构定义

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

### FFIBoundary 字段

- **id**: `u32` - 边界的唯一标识符
- **kind**: `BoundaryKind` - FFI 边界类型
- **caller_language**: `Language` - 调用者的语言
- **callee_language**: `Language` - 被调用者的语言
- **function_name**: `[]const u8` - 边界处的函数名
- **location**: `Location` - 边界的位置

### FFIBoundary.BoundaryKind 类型

- **rust_to_c**: Rust 调用 C
- **zig_to_c**: Zig 调用 C
- **c_to_rust**: C 调用 Rust
- **c_to_zig**: C 调用 Zig
- **external_unknown**: 未知的外部调用

### FFIBoundary.Language 类型

- **c**: C 语言
- **rust**: Rust 语言
- **zig**: Zig 语言
- **unknown**: 未知语言

### FFIBoundary 方法

#### init()

创建新的 FFI 边界。

**参数:**

- `id`: 唯一标识符
- `kind`: 边界类型
- `caller_language`: 调用者语言
- `callee_language`: 被调用者语言
- `function_name`: 边界处的函数名
- `location`: 边界位置

**返回值:** 新的 FFIBoundary 实例

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

检查这是否是跨语言边界。

**返回值:** 如果调用者和被调用者语言不同则返回 true

```zig
if (boundary.isCrossLanguage()) {
    // 处理跨语言边界
}
```

## DiagnosticAggregator

诊断聚合器，从各种来源（静态分析、运行时验证、合并引擎）聚合诊断信息并生成统一报告。

### DiagnosticAggregator 结构定义

```zig
/// Diagnostic aggregator
pub const DiagnosticAggregator = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),
};
```

### DiagnosticAggregator 字段

- **allocator**: `std.mem.Allocator` - 内存分配器
- **diagnostics**: `std.ArrayList(Diagnostic)` - 诊断列表

### DiagnosticAggregator 方法

#### init()

创建新的诊断聚合器。

**参数:**

- `allocator`: 内存分配器

**返回值:** 新的 DiagnosticAggregator 实例

```zig
var aggregator = DiagnosticAggregator.init(allocator);
defer aggregator.deinit();
```

#### deinit()

释放聚合器资源。

```zig
aggregator.deinit();
```

#### add()

添加诊断。

**参数:**

- `diag`: 要添加的诊断

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

获取所有诊断。

**返回值:** 诊断切片

```zig
const all = aggregator.getAll();
```

#### getBySeverity()

按严重性获取诊断。

**参数:**

- `severity`: 严重性级别
- `allocator`: 内存分配器

**返回值:** 新分配的诊断切片，调用者拥有所有权，必须释放

```zig
const errors = try aggregator.getBySeverity(.err, allocator);
defer freeDiagnosticsSlice(allocator, errors);
```

#### getByKind()

按类型获取诊断。

**参数:**

- `kind`: 诊断类型
- `allocator`: 内存分配器

**返回值:** 新分配的诊断切片，调用者拥有所有权，必须释放

```zig
const static_issues = try aggregator.getByKind(.static_issue, allocator);
defer freeDiagnosticsSlice(allocator, static_issues);
```

#### aggregateFromEvents()

从合并事件聚合诊断。

**参数:**

- `events`: 合并事件数组

```zig
try aggregator.aggregateFromEvents(events);
```

#### generateSummary()

生成摘要报告。

**参数:**

- `allocator`: 内存分配器

**返回值:** SummaryReport 结构

```zig
const summary = try aggregator.generateSummary(allocator);
std.debug.print("Total: {}, Errors: {}, Warnings: {}\n", .{
    summary.total,
    summary.error_count,
    summary.warning_count,
});
```

#### clear()

清除所有诊断。

```zig
aggregator.clear();
```

## 使用示例

### 创建问题

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

### 创建 FFI 边界

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

### 使用诊断聚合器

```zig
pub fn aggregateDiagnostics() !void {
    var aggregator = diag.DiagnosticAggregator.init(allocator);
    defer aggregator.deinit();

    // 添加诊断
    const location = diag.Location.init("test_func");
    try aggregator.add(diag.Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 42,
        .message = "Potential buffer overflow",
        .confidence = 0.8,
    });

    // 按严重性过滤
    const errors = try aggregator.getBySeverity(.err, allocator);
    defer diag.freeDiagnosticsSlice(allocator, errors);

    for (errors) |err| {
        std.debug.print("Error: {}\n", .{err.message});
    }

    // 生成摘要
    const summary = try aggregator.generateSummary(allocator);
    std.debug.print("Summary: {} total, {} errors, {} warnings\n", .{
        summary.total,
        summary.error_count,
        summary.warning_count,
    });
}
```

## 注意事项

1. **内存管理**: DiagnosticAggregator 拥有其内部诊断消息的所有权。调用 `getBySeverity` 或 `getByKind` 返回的切片由调用者拥有，必须使用 `freeDiagnosticsSlice` 释放。
2. **置信度**: 置信度分数范围是 0.0 到 1.0，用于表示检测结果的可靠性。
3. **位置信息**: 文件、行和列信息是可选的，可能在某些情况下不可用（例如分析 LLVM IR 时）。
4. **FFI 边界**: FFIBoundary 主要用于跨语言分析，帮助识别数据跨越语言边界的潜在安全问题。
5. **严重性颜色**: `Severity.toColorCode()` 提供终端输出的颜色代码，用于改善可读性。
