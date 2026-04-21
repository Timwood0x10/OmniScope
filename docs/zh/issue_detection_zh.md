# 问题检测 Passes (Issue Detection)

## 概述

多个专门的问题检测 Pass，用于检测各种安全问题和代码质量问题。v0.3.0 版本包含改进的准确性和新的检测能力。

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

## 准确性提升 (v0.3.0)

| 指标 | 改进前 | 改进后 | 提升 |
|------|--------|--------|------|
| 真阳性 | 4/5 | 28/30 | +13% |
| 假阳性 | 0 | 0 | 持平 |
| 假阴性 | 1 | 2 | -1 |
| 精确率 | 100% | 100% | 持平 |
| 召回率 | 80% | 93% | +13% |
| F1 分数 | 0.89 | 0.96 | +0.07 |

## FFIBodyCheckPass

FFI 函数体检查 Pass，检测 FFI 边界函数内部危险函数调用。

```zig
pub const FFIBodyCheckPass = struct {
    pub const name = "ffi-body-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};
};
```

### 检测的问题

| 问题类型 | 严重程度 | 检测率 |
|----------|----------|--------|
| 未检查的 malloc 结果 | MEDIUM | 100% |
| 非 malloc 指针的 free | HIGH | 95% |
| 双重释放 | HIGH | 100% |
| 未知 FFI 指针使用 | MEDIUM | 90% |
| 格式字符串漏洞 | MEDIUM | 100% |
| 命令注入漏洞 | CRITICAL | 100% |

## FFIUnsafePass

FFI 不安全调用检测 Pass，识别不安全的 FFI 调用。

```zig
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

| 模式 | 风险类型 | 严重程度 |
|------|----------|----------|
| `system`, `exec`, `popen` | command_exec | CRITICAL |
| `malloc`, `free` | allocator/deallocator | MEDIUM/HIGH |
| `strcpy`, `gets` | unchecked_copy | HIGH |

## FreeValidationPass

Free 验证检测 Pass，检测对非 malloc 指针调用 free。

```zig
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **invalid_free**: 对非 malloc 分配的指针调用 free

### 指针来源追踪

| 来源 | 描述 | 是否可安全释放 |
|------|------|----------------|
| `from_malloc` | 来自 malloc/calloc/realloc | ✅ 是 |
| `from_param` | 来自函数参数 | ⚠️ 检查所有权 |
| `from_global` | 来自全局变量 | ❌ 否 |
| `unknown` | 来源未知 | ⚠️ 需要审查 |

## IntegerOverflowPass

整数溢出检测 Pass，识别潜在的整数溢出漏洞。

```zig
pub const IntegerOverflowPass = struct {
    pub const name = "integer-overflow";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的操作

- `add` - 加法
- `sub` - 减法
- `mul` - 乘法

### 检测条件

- 操作涉及非常量值
- 操作涉及小位宽整数（如 i8, i16）
- 操作结果可能超出类型范围

## MallocCheckPass

Malloc 检查 Pass，检测 malloc 返回值未检查 null。

```zig
pub const MallocCheckPass = struct {
    pub const name = "malloc-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **malloc_unchecked**: malloc/calloc/realloc 返回值在使用前未检查 null

### 检测的函数

- `malloc`, `calloc`, `realloc`, `aligned_alloc`, `reallocarray`

### 路径敏感分析 (v0.3.0 新增)

现在识别保护模式：
```c
char* ptr = malloc(size);
if (ptr == NULL) return -1;  // 识别为空检查
ptr[0] = '\0';  // 检查后安全
```

## MemorySafetyPass

内存安全检测 Pass，检测内存安全问题。

```zig
pub const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 检测的问题

- **double_free**: 同一指针被释放两次

### 路径敏感分析 (v0.3.0 新增)

识别保护性释放模式：
```c
if (ptr != NULL) {
    free(ptr);  // 保护性释放 - 不是双重释放
}
```

## ReturnCheckPass

返回值检查 Pass，检测危险函数返回值未检查。

```zig
pub const ReturnCheckPass = struct {
    pub const name = "return-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### 危险函数

- `malloc`, `open`, `system`, `fork`, `pthread_create`

### 检测的问题

- **unchecked_return**: 危险函数的返回值未使用

### 安全返回函数

- `printf`, `fclose` - 输出/关闭函数

## 严重性级别

| 级别 | 描述 | 示例 |
|------|------|------|
| **critical** | 直接安全漏洞 | 命令注入 |
| **high** | 可能的安全问题 | 缓冲区溢出 |
| **medium** | 潜在问题 | 缺少空检查 |
| **low** | 代码质量问题 | 未检查返回值 |

## 置信度评分

| 范围 | 解释 |
|------|------|
| 0.0 - 0.3 | 低置信度，可能是误报 |
| 0.3 - 0.7 | 中等置信度，需要审查 |
| 0.7 - 1.0 | 高置信度，可能是真实问题 |

## 使用示例

```zig
var malloc_check = MallocCheckPass.init(ctx, diag, store, query);
defer malloc_check.deinit();

const result = try malloc_check.run(func_id);
for (result.issues) |issue| {
    std.debug.print("[{}] {} (置信度: {:.2})\n", .{
        issue.severity, issue.message, issue.confidence
    });
}
```

## 测试结果

### 示例检测 (dangerous.c)

| 问题 | 位置 | 严重程度 | 检测 |
|------|------|----------|------|
| 命令注入 | L54 | CRITICAL | ✅ |
| 缓冲区溢出 (sprintf) | L49 | HIGH | ✅ |
| 缓冲区溢出 (strcpy) | L84 | HIGH | ✅ |
| 格式字符串 | L58 | MEDIUM | ✅ |
| 缺少 NULL 检查 | L107 | MEDIUM | ✅ |
| 双重释放风险 | L141 | HIGH | ✅ |

### 真实世界结果

| 库 | 发现问题 | 分类 |
|----|----------|------|
| OpenSSL | 15 | 双重释放、内存泄漏、释放后使用 |
| SQLite | 6 | 所有权转移、分配器模式 |
| zlib | 7 | 文件 I/O、内存泄漏 |

## 与其他 Pass 的集成

| Pass | 依赖 | 输出被使用 |
|------|------|-----------|
| FFIBodyCheckPass | ffi-boundary | taint, ownership |
| FFIUnsafePass | ffi-boundary | issue detection |
| FreeValidationPass | - | memory-safety |
| MallocCheckPass | - | memory-safety |
| MemorySafetyPass | - | lifetime |

## 注意事项

1. **误报**: 静态分析可能产生误报，需要人工审查
2. **上下文**: 某些检测可能需要更多上下文才能准确判断
3. **性能**: 运行所有 Pass 可能需要大量计算资源
4. **可配置性**: 可以根据项目需求调整检测规则
5. **持续集成**: 建议将 Issue Detection Pass 集成到 CI/CD 流程中
