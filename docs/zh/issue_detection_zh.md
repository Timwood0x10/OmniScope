# Issue Detection Passes (问题检测)

## 概述

Issue Detection Passes 模块包含多个专门的问题检测 Pass，用于检测各种安全问题和代码质量问题。每个 Pass 专注于特定类型的问题检测。

## 模块位置

```text
src/pass/analysis/issue/
├── ffi_body_check.zig      # FFI 函数体检查
├── ffi_unsafe.zig          # FFI 不安全调用检测
├── free_validation.zig     # Free 验证检测
├── integer_overflow.zig   # 整数溢出检测
├── malloc_check.zig        # Malloc 检查
├── memory_safety.zig       # 内存安全检测
└── return_check.zig        # 返回值检查
```

## FFIBodyCheckPass

FFI 函数体检查 Pass，检测 FFI 边界函数内部危险函数调用。

### FFIBodyCheckPass 结构定义

```zig
/// FFI body check pass
pub const FFIBodyCheckPass = struct {
    pub const name = "ffi-body-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};
};
```

### 检测的问题

FFIBodyCheckPass 检测以下问题：

1. **未检查的 malloc 结果**: malloc 返回值在使用前未检查 null
2. **非 malloc 指针的 free**: 对非 malloc 分配的指针调用 free
3. **双重释放**: 同一指针被释放两次
4. **未知 FFI 指针使用**: 将未验证的指针传递给未知 FFI 函数
5. **格式字符串漏洞**: 将用户数据用作格式字符串
6. **命令注入漏洞**: 将用户数据传递给 system() 等危险函数

### 使用示例

```zig
var ffi_body_check = FFIBodyCheckPass.init(ctx, diag, store, query);
defer ffi_body_check.deinit();

const result = try ffi_body_check.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Issue: {}\n", .{issue.message});
}
```

## FFIUnsafePass

FFI 不安全调用检测 Pass，识别不安全的 FFI 调用。

### FFIUnsafePass 结构定义

```zig
/// FFI unsafe detection pass
pub const FFIUnsafePass = struct {
    pub const name = "ffi-unsafe";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    const DangerousPatterns = &[_][]const u8{
        "system", "exec", "popen", "malloc", "free", "strcpy", "gets",
    };
};
```

### 危险函数模式

FFIUnsafePass 识别以下危险函数模式：

- `system` - 命令注入风险
- `exec` - 命令注入风险
- `popen` - 命令注入风险
- `malloc` - 内存安全问题
- `free` - 内存安全问题
- `strcpy` - 缓冲区溢出风险
- `gets` - 缓冲区溢出风险

### 使用示例

```zig
var ffi_unsafe = FFIUnsafePass.init(ctx, diag, store, query);
defer ffi_unsafe.deinit();

const result = try ffi_unsafe.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Unsafe FFI call: {}\n", .{issue.message});
}
```

## FreeValidationPass

Free 验证检测 Pass，检测对非 malloc 指针调用 free。

### FreeValidationPass 结构定义

```zig
/// Free validation detection pass
///
/// This pass implements Rule 2 from go_noise.md:
/// Detect when free is called on non-malloc pointers.
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **invalid_free**: 对非 malloc 分配的指针调用 free

### 指针来源追踪

FreeValidationPass 追踪指针的来源：

- `from_malloc` - 来自 malloc/calloc/realloc
- `from_param` - 来自函数参数
- `from_global` - 来自全局变量
- `unknown` - 来源未知

### 使用示例

```zig
var free_validation = FreeValidationPass.init(ctx, diag, store, query);
defer free_validation.deinit();

const result = try free_validation.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Invalid free: {}\n", .{issue.message});
}
```

## IntegerOverflowPass

整数溢出检测 Pass，识别潜在的整数溢出漏洞。

### IntegerOverflowPass 结构定义

```zig
/// Integer overflow detection pass
pub const IntegerOverflowPass = struct {
    pub const name = "integer-overflow";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的操作

IntegerOverflowPass 分析以下算术操作：

- `add` - 加法
- `sub` - 减法
- `mul` - 乘法

### 检测条件

当满足以下条件时报告潜在溢出：

- 操作涉及非常量值
- 操作涉及小位宽整数（如 i8, i16）
- 操作结果可能超出类型范围

### 使用示例

```zig
var int_overflow = IntegerOverflowPass.init(ctx, diag, store, query);
defer int_overflow.deinit();

const result = try int_overflow.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Integer overflow: {}\n", .{issue.message});
}
```

## MallocCheckPass

Malloc 检查 Pass，检测 malloc 返回值未检查 null。

### MallocCheckPass 结构定义

```zig
/// Malloc null check detection pass
///
/// This pass implements Rule 1 from go_noise.md:
/// Detect when malloc result is used without null check.
pub const MallocCheckPass = struct {
    pub const name = "malloc-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **malloc_unchecked**: malloc/calloc/realloc 返回值在使用前未检查 null

### 检测的函数

MallocCheckPass 检测以下内存分配函数：

- `malloc`
- `calloc`
- `realloc`
- `aligned_alloc`
- `reallocarray`

### 使用示例

```zig
var malloc_check = MallocCheckPass.init(ctx, diag, store, query);
defer malloc_check.deinit();

const result = try malloc_check.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Malloc unchecked: {}\n", .{issue.message});
}
```

## MemorySafetyPass

内存安全检测 Pass，检测内存安全问题。

### MemorySafetyPass 结构定义

```zig
/// Memory safety detection pass
pub const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **double_free**: 同一指针被释放两次

### 检测机制

MemorySafetyPass 在函数内跟踪已释放的指针，检测重复释放。

### 使用示例

```zig
var mem_safety = MemorySafetyPass.init(ctx, diag, store, query);
defer mem_safety.deinit();

const result = try mem_safety.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Memory safety issue: {}\n", .{issue.message});
}
```

## ReturnCheckPass

返回值检查 Pass，检测危险函数返回值未检查。

### ReturnCheckPass 结构定义

```zig
/// Return value check pass
pub const ReturnCheckPass = struct {
    pub const name = "return-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 危险函数

ReturnCheckPass 识别以下危险函数：

- `malloc` - 内存分配
- `open` - 文件打开
- `system` - 命令执行
- `fork` - 进程创建
- `pthread_create` - 线程创建

### 检测的问题

- **unchecked_return**: 危险函数的返回值未使用

### 安全返回函数

某些函数的返回值可以安全忽略：

- `printf` - 输出函数
- `fclose` - 文件关闭（通常忽略返回值）

### 使用示例

```zig
var return_check = ReturnCheckPass.init(ctx, diag, store, query);
defer return_check.deinit();

const result = try return_check.run(func_id);
for (result.issues) |issue| {
    std.debug.print("Unchecked return: {}\n", .{issue.message});
}
```

## 问题严重性级别

所有 Issue Detection Pass 使用以下严重性级别：

- **low**: 低严重性，可能不会导致安全问题
- **medium**: 中等严重性，可能导致问题
- **high**: 高严重性，很可能导致安全问题
- **critical**: 严重性，直接导致安全漏洞

## 置信度评分

每个检测到的问题都有置信度评分（0.0 - 1.0）：

- **0.0 - 0.3**: 低置信度，可能是误报
- **0.3 - 0.7**: 中等置信度，需要人工审查
- **0.7 - 1.0**: 高置信度，很可能是真实问题

## 使用建议

### Pass 运行顺序

建议按以下顺序运行 Issue Detection Pass：

1. MallocCheckPass - 检测 malloc 未检查
2. FreeValidationPass - 检测无效 free
3. MemorySafetyPass - 检测内存安全问题
4. IntegerOverflowPass - 检测整数溢出
5. ReturnCheckPass - 检测未检查返回值
6. FFIBodyCheckPass - 检测 FFI 函数体
7. FFIUnsafePass - 检测不安全 FFI 调用

### 集成示例

```zig
const std = @import("std");

pub fn runIssueDetection() !void {
    // 初始化各个 Pass
    var malloc_check = MallocCheckPass.init(ctx, diag, store, query);
    defer malloc_check.deinit();

    var free_validation = FreeValidationPass.init(ctx, diag, store, query);
    defer free_validation.deinit();

    var mem_safety = MemorySafetyPass.init(ctx, diag, store, query);
    defer mem_safety.deinit();

    // 运行所有 Pass
    const func_id = 1;

    const malloc_result = try malloc_check.run(func_id);
    const free_result = try free_validation.run(func_id);
    const mem_safety_result = try mem_safety.run(func_id);

    // 聚合所有问题
    var all_issues = std.ArrayList(Issue).init(allocator);
    defer all_issues.deinit();

    try all_issues.appendSlice(malloc_result.issues);
    try all_issues.appendSlice(free_result.issues);
    try all_issues.appendSlice(mem_safety_result.issues);

    // 按严重性排序
    std.sort.sort(Issue, all_issues.items, {}, struct {
        fn compare(_: void, a: Issue, b: Issue) bool {
            return @intFromEnum(a.severity) > @intFromEnum(b.severity);
        }
    }.compare);

    // 输出结果
    for (all_issues.items) |issue| {
        std.debug.print("[{}] {} (confidence: {:.2})\n", .{
            issue.severity,
            issue.message,
            issue.confidence,
        });
    }
}
```

## 注意事项

1. **误报**: 静态分析可能产生误报，需要人工审查
2. **上下文**: 某些检测可能需要更多上下文才能准确判断
3. **性能**: 运行所有 Pass 可能需要大量计算资源
4. **可配置性**: 可以根据项目需求调整检测规则
5. **持续集成**: 建议将 Issue Detection Pass 集成到 CI/CD 流程中
