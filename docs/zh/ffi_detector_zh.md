# FFI Detector (FFI检测器)

## 概述

检测跨 FFI 边界的安全漏洞。匹配函数声明与实现，分析语言间数据流。

## 位置

```text
src/pass/analysis/ffi_detector.zig
```

## FFIDetector

```zig
pub const FFIDetector = struct {
    pub const name = "ffi-detector";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "taint" };

    allocator: Allocator,
    store: *FactStore,
    vulnerability_count: u32,
    vulnerabilities: std.ArrayList(FFIVulnerability),
};
```

### 方法

- **init()** - 初始化
- **deinit()** - 清理资源
- **run(ctx, diag)** - 运行检测

## 检测的漏洞

- **命令注入**: system, exec, popen (CWE-78)
- **缓冲区溢出**: strcpy, strcat, gets (CWE-120)
- **格式字符串**: printf, sprintf (CWE-134)
- **释放后使用**: free, delete (CWE-416)
- **整数溢出**: 算术运算 (CWE-190)

## FFIVulnerability

```zig
pub const FFIVulnerability = struct {
    id: u32,
    vuln_type: FFIVulnerabilityType,
    severity: FFISeverity,
    ffi_match: *const FFIMatch,
    description: []const u8,
    source_location: ?[]const u8,
    sink_location: ?[]const u8,
    dangerous_function: ?[]const u8,
};
```

## 使用示例

```zig
var detector = FFIDetector.init(allocator, &store);
defer detector.deinit();

try detector.run(ctx, diag);
for (detector.vulnerabilities.items) |vuln| {
    std.debug.print("Vuln #{}: {}\n", .{ vuln.id, vuln.description });
}
```

## 注意事项

- 依赖 cfg, dfg, taint Pass
- 使用 FFIMatcher 进行函数匹配
- 检查污点数据流
