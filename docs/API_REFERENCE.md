# OmniScope API Reference

> **版本**: v0.1.7 | **语言**: Zig 0.15.2
> **目标读者**: 集成开发者、工具链工程师

---

## 📚 目录

1. [核心数据结构](#1-核心数据结构)
2. [分析引擎API](#2-分析引擎api)
3. [Pass系统](#3-pass系统)
4. [Issue类型](#4-issue类型)
5. [配置接口](#5-配置接口)
6. [输出格式](#6-输出格式)

---

## 1. 核心数据结构

### 1.1 Issue (问题报告)

**文件**: `src/diag/issue.zig`

```zig
/// 表示检测到的安全问题
pub const Issue = struct {
    id: []const u8,                    // 唯一标识符 "OMI-NNN"
    kind: Kind,                        // 问题类型枚举
    severity: Severity,                // 严重级别
    confidence: Confidence,            // 置信度等级
    confidence_score: f64,             // 置信度分数 0.0-1.0
    cwe_id: u16,                       // CWE编号
    message: []const u8,               // 问题描述
    location: Location,                // 位置信息
    trace: ?[]TraceEntry,              // 可选的调用栈/数据流追踪
    
    // 构造函数
    pub fn init(kind: Kind, message: []const u8, loc: Location, sev: Severity, conf: f64) Issue
    
    /// 带完整trace的构造（用于复杂问题）
    pub fn initWithTrace(
        kind: Kind,
        message: []const u8,
        loc: Location,
        sev: Severity,
        conf: f64,
        trace: []TraceEntry,
    ) Issue
    
    /// 资源清理
    pub fn deinit(self: *Issue, allocator: Allocator) void
};
```

#### Kind (Issue类型枚举)

| 值 | 说明 | CWE |
|----|------|-----|
| `memory_leak` | 内存泄漏 | CWE-401 |
| `use_after_free` | 使用已释放内存 | CWE-416 |
| `double_free` | 双重释放 | CWE-415 |
| `null_dereference` | 空指针解引用 | CWE-476 |
| `buffer_overflow_risk` | 缓冲区溢出风险 | CWE-120 |
| `stack_buffer_overflow` | 栈溢出 | CWE-121 |
| `invalid_free` | 无效释放 | CWE-763 |
| `borrow_escape` | Rust借用逃逸 | N/A (OmniScope特有) |
| `cross_language_free` | 跨语言释放 | CWE-416 |
| `cross_language_leak` | 跨语言泄漏 | CWE-401 |
| `ffi_unsafe_call` | 不安全FFI调用 | CWE-20 |
| `jni_type_mismatch` | JNI类型不匹配 | CWE-843 |
| `jni_unchecked_return` | JNI返回值未检查 | CWE-252 |
| `tainted_path_to_sink` | 污点传播到sink | CWE-502 |
| `command_injection` | 命令注入 | CWE-78 |
| `format_string` | 格式化字符串漏洞 | CWE-134 |
| `unsafe_deserialization` | 不安全反序列化 | CWE-502 |
| `data_race` | 数据竞争 | CWE-362 |
| `thread_safety_violation` | 线程安全问题 | CWE-667 |

#### Severity (严重级别)

```zig
pub const Severity = enum {
    critical,   // 可直接利用的漏洞
    high,       // 高概率真实问题
    medium,     // 可能存在问题，需人工确认
    low,        // 低风险，代码质量问题
};
```

#### Confidence (置信度)

```zig
pub const Confidence = enum {
    HIGH,       // >0.90 - 几乎确定是TP
    MEDIUM,     // 0.70-0.90 - 很可能是TP
    LOW,        // 0.50-0.70 - 可能是FP
    HEURISTIC,  // <0.50 - 启发式规则，高FP率
};
```

### 1.2 Location (位置信息)

```zig
pub const Location = struct {
    function: []const u8,      // 函数名
    file: ?[]const u8 = null,  // 源文件路径（可选）
    line: ?u32 = null,         // 行号（可选）
    
    pub fn init(func: []const u8) Location
};
```

### 1.3 TraceEntry (追踪条目)

```zig
/// 用于构建详细的数据流/调用栈追踪
pub const TraceEntry = struct {
    description: []const u8,
    owned_desc: ?[]const u8 = null,  // 拥有的字符串（需要free）
    
    pub fn init(desc: []const u8) TraceEntry
    pub fn initOwned(owned_desc: []const u8) TraceEntry
    pub fn deinit(self: *TraceEntry, allocator: Allocator) void
};
```

---

## 2. 分析引擎API

### 2.1 OmniScope 主入口

**文件**: `src/main.zig`, `src/app.zig`

```zig
/// OmniScope 分析引擎主结构
pub const App = struct {
    allocator: std.mem.Allocator,
    config: Config,
    diagnostics: Diagnostics,
    
    /// 创建新实例
    pub fn init(allocator: std.mem.Allocator, config: Config) !App
    
    /// 执行单文件分析
    pub fn run(self: *App, input_path: []const u8) !AnalysisResult
    
    /// 批量分析多个文件
    pub fn runBatch(self: *App, paths: [][]const u8) ![]AnalysisResult
    
    /// 清理资源
    pub fn deinit(self: *App) void
};
```

### 2.2 AnalysisResult (分析结果)

```zig
pub const AnalysisResult = struct {
    file_path: []const u8,
    summary: Summary,
    issues: []Issue,
    metadata: Metadata,
    
    /// 导出为JSON格式
    pub fn toJson(self: *const AnalysisResult, allocator: Allocator) ![]u8
    
    /// 导出为SARIF格式
    pub fn toSarif(self: *const AnalysisResult, allocator: Allocator) ![]u8
    
    /// 过滤issues
    pub fn filterBySeverity(self: *const AnalysisResult, sev: Severity) []Issue
    pub fn filterByKind(self: *const AnalysisResult, kind: Kind) []Issue
    pub fn filterByConfidence(self: *const AnalysisResult, min_score: f64) []Issue
};

pub const Summary = struct {
    functions: usize,
    issues: usize,
    time_ms: u64,
    ffi_boundaries: usize,
    cross_language_edges: usize,
};

pub const Metadata = struct {
    language_detected: []const u8,
    confidence: f64,
    llvm_version: []const u8,
    timestamp: i64,
};
```

### 2.3 使用示例

```zig
const omniscope = @import("omniscope");

// 示例1: 单文件分析
var app = try omniscope.App.init(allocator, config);
defer app.deinit();

var result = try app.run("example.bc");
defer result.deinit();

// 输出JSON
const json = try result.toJson(allocator);
defer allocator.free(json);
std.debug.print("{s}\n", .{json});

// 示例2: 只获取CRITICAL和HIGH issues
const critical_issues = result.filterBySeverity(.critical);
const high_issues = result.filterBySeverity(.high);

// 示例3: 导出到SARIF
const sarif = try result.toSarif(allocator);
// 写入文件...
```

---

## 3. Pass系统

### 3.1 Pass 接口定义

**文件**: `src/pass/pass.zig`

```zig
/// 所有分析Pass必须实现的接口
pub const Pass = struct {
    name: []const u8,
    description: []const u8,
    
    /// 运行分析并返回发现的问题
    pub fn run(
        self: *Pass,
        module: *const LLVMModule,
        ctx: *Context,
        diag: *Diagnostics,
    ) ![]Issue
    
    /// 重置状态（用于批量分析）
    pub fn reset(self: *Pass) void
    
    /// 获取统计信息
    pub fn getStats(self: *const Pass) PassStats
};

pub const PassStats = struct {
    functions_analyzed: usize,
    issues_found: usize,
    execution_time_ms: u64,
};
```

### 3.2 内置Pass列表

| Pass名称 | 文件 | 功能 | 默认启用 |
|----------|------|------|----------|
| **PtrLifetime** | `ptr_lifetime.zig` | 内存生命周期分析 | ✅ |
| **TaintAnalysis** | `taint.zig` | 污点传播分析 | ✅ |
| **FFIBoundary** | `ffi_boundary.zig` | FFI边界检测 | ✅ |
| **RustFFIAuditor** | `rust_ffi_auditor.zig` | Rust FFI专项审计 | ✅ |
| **DataFlowGraph** | `dataflow/graph.zig` | 数据流图构建 | ✅ |
| **CallGraph** | `callgraph.zig` | 调用图构建 | ✅ |

### 3.3 自定义Pass示例

```zig
const std = @import("std");
const omniscope = @import("omniscope");

/// 自定义Pass：检测未检查的返回值
pub const UncheckedReturnPass = struct {
    allocator: std.mem.Allocator,
    stats: omniscope.PassStats,
    
    pub fn init(allocator: std.mem.Allocator) UncheckedReturnPass {
        return .{
            .allocator = allocator,
            .stats = .{
                .functions_analyzed = 0,
                .issues_found = 0,
                .execution_time_ms = 0,
            },
        };
    }
    
    pub fn run(
        self: *UncheckedReturnPass,
        module: *const omniscope.LLVMModule,
        ctx: *omniscope.Context,
        diag: *omniscope.Diagnostics,
    ) ![]omniscope.Issue {
        var issues = std.ArrayList(omniscope.Issue).init(self.allocator);
        
        for (module.functions()) |func| {
            self.stats.functions_analyzed += 1;
            
            // 实现你的检测逻辑...
            // 例如：查找所有忽略返回值的函数调用
            
            if (found_issue) {
                try issues.append(omniscope.Issue.init(
                    .unchecked_return,
                    "Return value not checked",
                    omniscope.Location.init(func.name),
                    .medium,
                    0.75,
                ));
                self.stats.issues_found += 1;
            }
        }
        
        return issues.toOwnedSlice();
    }
    
    pub fn reset(self: *UncheckedReturnPass) void {
        self.stats = .{};
    }
    
    pub fn getStats(self: *const UncheckedReturnPass) omniscope.PassStats {
        return self.stats;
    }
};
```

---

## 4. 配置接口

### 4.1 Config 结构体

**文件**: `src/config.zig`

```zig
pub const Config = struct {
    // === 输入选项 ===
    input_format: InputFormat = .auto,         // auto / ll / bc
    max_file_size_mb: u32 = 100,              // 最大文件大小(MB)
    
    // === 分析选项 ===
    enable_passes: []const []const u8 = &.{},  // 启用的pass列表(空=全部)
    disable_passes: []const []const u8 = &.{}, // 禁用的pass列表
    taint_depth: u32 = 3,                      // 污点传播深度
    max_functions_per_module: u32 = 5000,       // 单模块最大函数数
    
    // === Rust FFI 特定选项 ===
    rust_ffi_auditor_enabled: bool = true,
    safe_zone_detection: bool = true,           // 自动识别Safe Zone
    ownership_transfer_detection: bool = true,  // 所有权转移检测
    
    // === 输出选项 ===
    output_formats: []OutputFormat = &.{.json}, // json / sarif / console
    verbose: bool = false,                       // 详细输出
    no_color: bool = false,                     // 禁用颜色
    
    // === 性能调优 ===
    parallelism: u32 = 0,                       // 0=自动检测CPU数
    memory_limit_mb: u32 = 4096,               // 内存限制(MB)
    
    // === 噪声过滤 ===
    min_confidence_threshold: f64 = 0.50,      // 最小置信度阈值
    suppress_stdlib: bool = true,               // 抑制标准库误报
    suppress_test_code: bool = true,            // 抑制测试代码
    
    /// 从JSON文件加载配置
    pub fn loadFromFile(path: []const u8) !Config
    
    /// 从命令行参数解析
    pub fn parseCommandLine(args: [][]const u8) !Config
    
    /// 验证配置有效性
    pub fn validate(self: *const Config) !void
};

pub const InputFormat = enum { auto, ll, bc };
pub const OutputFormat = enum { json, sarif, console };
```

### 4.2 配置文件示例 (`omniscope.config.json`)

```json
{
  "analysis": {
    "enable_passes": ["PtrLifetime", "TaintAnalysis"],
    "taint_depth": 5,
    "max_functions_per_module": 3000
  },
  "rust_ffi": {
    "safe_zone_detection": true,
    "ownership_transfer_detection": true
  },
  "output": {
    "formats": ["json", "sarif"],
    "verbose": true
  },
  "noise_filter": {
    "min_confidence_threshold": 0.70,
    "suppress_stdlib": true
  },
  "performance": {
    "parallelism": 4,
    "memory_limit_mb": 8192
  }
}
```

---

## 5. 输出格式

### 5.1 JSON Schema

完整的JSON schema位于: `docs/schemas/omniscope-output-schema.json`

**关键字段**:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "OmniScope Analysis Result",
  "type": "object",
  "required": ["schema_version", "tool", "summary", "issues"],
  "properties": {
    "schema_version": {"type": "string"},
    "tool": {"type": "string", "const": "omniscope"},
    "tool_version": {"type": "string"},
    "timestamp": {"type": "integer"},
    "input_file": {"type": "string"},
    "summary": {
      "$ref": "#/definitions/Summary"
    },
    "metadata": {
      "$ref": "#/definitions/Metadata"
    },
    "issues": {
      "type": "array",
      "items": { "$ref": "#/definitions/Issue" }
    }
  }
}
```

### 5.2 SARIF 格式

OmniScope支持[SARIF v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/)格式，可直接集成到：

- GitHub Code Scanning
- Azure DevOps
- SonarQube SARIF插件
- 其他支持SARIF的工具

**转换示例**:
```bash
./zig-out/bin/OmniScope input.bc --sarif > results.sarif
```

---

## 6. 错误处理

### 6.1 错误类型

```zig
pub const Error = error{
    // 文件I/O错误
    FileNotFound,
    FileTooLarge,
    FileCorrupted,
    
    // 解析错误
    ModuleParseFailed,
    InvalidIRVersion,
    
    // 分析错误
    AnalysisTimeout,
    OutOfMemory,
    InternalError,
    
    // 配置错误
    InvalidConfig,
    UnsupportedOption,
};
```

### 6.2 错误处理最佳实践

```zig
var app = try omniscope.App.init(allocator, config);
defer app.deinit();

var result = app.run(input_path) catch |err| switch (err) {
    error.FileNotFound => {
        std.log.err("File not found: {s}", .{input_path});
        return;
    },
    error.ModuleParseFailed => {
        std.log.err("Failed to parse IR file. Try converting with llvm-as");
        return;
    },
    error.AnalysisTimeout => {
        std.log.warn("Analysis timed out after {d}s", .{config.timeout_seconds});
        // 可以尝试降低分析深度或限制函数数量
        return;
    },
    else => return err,  // 重新抛出未知错误
};
defer result.deinit();
```

---

## 7. 性能指标

### 7.1 时间复杂度

| 操作 | 复杂度 | 说明 |
|------|--------|------|
| IR解析 | O(n) | n = IR指令数 |
| 调用图构建 | O(n log n) | 基于函数调用关系 |
| 污点传播 | O(d × e) | d=深度, e=边数 |
| Rust FFI审计 | O(f × c) | f=函数数, c=平均调用数 |

### 7.2 内存占用估算

| 规模 | Debug模式 | Release模式 |
|------|-----------|-------------|
| 100 functions | ~50MB | ~15MB |
| 500 functions | ~200MB | ~60MB |
| 1000 functions | ~400MB | ~120MB |
| 3000+ functions | ~1GB+ | ~300MB |

### 7.3 优化建议

1. **使用ReleaseFast构建** - 减少70%内存占用
2. **限制分析范围** - 只分析包含FFI边界的函数
3. **增加并行度** - 设置 `parallelism > 1`
4. **分批处理** - 大项目拆分为多个模块

---

## 8. 版本兼容性

### 8.1 Zig版本要求

| OmniScope | Zig最低 | 推荐Zig |
|-----------|---------|---------|
| v0.1.x | 0.13.0 | 0.15.2 |

### 8.2 LLVM版本要求

| OmniScope | 支持LLVM | 推荐工具链 |
|-----------|----------|------------|
| v0.1.7 | 17-22 | llvm-as-22 (Homebrew) |

### 8.3 API稳定性承诺

- **Public API** (`src/public/*.zig`) - 语义版本控制保证
- **Internal API** (`src/**/*.zig`) - 可能随时变更
- **Config结构** - 向后兼容（新字段有默认值）

---

*文档版本*: v0.1.7 | *最后更新*: 2026-05-07
*API稳定性*: Public API遵循Semantic Versioning
*反馈渠道*: [GitHub Issues](https://github.com/your-org/OmniScope/issues)
