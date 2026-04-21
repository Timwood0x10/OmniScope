# FFI Analysis Pass (FFI分析)

## 概述

统一的 FFI 安全分析 Pass，集成 FFIMatcher、FFIBoundaryPass 和 FFIDetector。

## 位置

```text
src/pass/analysis/ffi_analysis.zig
```

## FFIAnalysisPass

```zig
pub const FFIAnalysisPass = struct {
    pub const name = "ffi-analysis";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "taint" };

    allocator: Allocator,
    store: *FactStore,
    matcher: ?FFIMatcher,
    vulnerabilities: std.ArrayList(FFIAnalysisVulnerability),
};
```

### 方法

- **init()** - 初始化
- **deinit()** - 清理资源
- **run(ctx, diag)** - 运行分析

## 分析流程

1. 初始化 FFIMatcher 并提取函数
2. 匹配 declare 和 define 函数
3. 创建 FFI 边界
4. 分析每个匹配的漏洞

## 检测的漏洞

- **命令注入**: system, exec, popen 等
- **缓冲区溢出**: strcpy, strcat, gets 等
- **格式字符串**: printf, sprintf 等

## FFIAnalysisResult

```zig
pub const FFIAnalysisResult = struct {
    match_count: usize,
    boundary_count: usize,
    vulnerability_count: usize,
    vulnerabilities: []const FFIAnalysisVulnerability,
};
```

## 使用示例

```zig
var ffi_analysis = FFIAnalysisPass.init(allocator, &store);
defer ffi_analysis.deinit();

try ffi_analysis.run(ctx, diag);
const results = ffi_analysis.getResults();
```

## 注意事项

- 依赖 cfg, dfg, taint Pass
- 需要 FFIMatcher 进行跨语言函数匹配
- 置信度 0.8-0.9
