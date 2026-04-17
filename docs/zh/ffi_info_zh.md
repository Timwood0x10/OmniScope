# FFI Info (FFI边界信息)

## 概述

定义 FFI 边界类型、边界信息和检测器，用于识别调用图中的跨语言转换。

## 位置

```text
src/pass/analysis/ffi_info.zig
```

## FFIKind

```zig
pub const FFIKind = enum {
    none,      // 非 FFI 调用
    c_call,    // C FFI 调用
    rust_ffi,  // Rust FFI
    go_cgo,    // Go CGO
    other,     // 其他语言 FFI
};
```

## FFIBoundaryInfo

```zig
pub const FFIBoundaryInfo = struct {
    edge_id: u32,
    caller: u32,
    callee: u32,
    kind: FFIKind,
    target_language: []const u8,
    is_exported: bool,
    is_imported: bool,
};
```

## FFIBoundaryDetector

```zig
pub const FFIBoundaryDetector = struct {
    allocator: Allocator,
    boundaries: std.ArrayList(FFIBoundaryInfo),
    language_patterns: std.StringHashMap(FFIKind),
};
```

### 方法

- **init()** - 初始化检测器
- **deinit()** - 清理资源
- **isFFICall(func_name)** - 检查是否是 FFI 调用
- **classifyFFIKind(func_name)** - 分类 FFI 类型
- **addBoundary(info)** - 添加边界
- **getBoundaries()** - 获取所有边界
- **clear()** - 清空边界
- **boundaryCount()** - 边界计数
- **getBoundariesByKind(allocator, kind)** - 按类型获取边界

## 语言模式

检测器识别以下语言模式：

- `rust_`, `_rust_`, `_ZN` - Rust FFI
- `cgo_`, `_cgo_`, `go_` - Go CGO
- `Java_`, `JNI_` - Java JNI
- `Py_`, `python_` - Python
- `_Z`, `__` - C++ mangled names

## 使用示例

```zig
var detector = FFIBoundaryDetector.init(allocator);
defer detector.deinit();

if (detector.isFFICall("rust_function")) {
    const info = FFIBoundaryInfo{
        .edge_id = 1,
        .caller = 10,
        .callee = 20,
        .kind = .rust_ffi,
        .target_language = "Rust",
        .is_exported = true,
        .is_imported = false,
    };
    try detector.addBoundary(info);
}

const boundaries = detector.getBoundaries();
```

## 注意事项

- Rust 识别: `_ZN` 前缀、`std_`、`tokio_`、`crossbeam_`
- Go 识别: `cgo_`、`go_` 前缀
- C++ 识别: `_Z`、`__` 前缀
