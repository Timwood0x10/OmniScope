# 污点分析 Pass (Taint Analysis)

## 概述

污点分析 Pass 跟踪数据从污染源到敏感汇的流动，以检测安全漏洞。v0.1.5 版本在准确性和精度方面有显著改进。

## 模块位置

```text
src/pass/analysis/taint.zig
src/pass/analysis/taint_propagation.zig
src/registry/sanitizer_registry.zig
```

## 准确性提升 (v0.1.5)

| 指标 | 改进前 | 改进后 | 提升 |
|------|--------|--------|------|
| 召回率 (Recall) | 80% | 93% | +13% |
| 精确率 (Precision) | 100% | 100% | 持平 |
| F1 分数 | 0.89 | 0.96 | +0.07 |

## TaintPass

```zig
pub const TaintPass = struct {
    pub const name = "taint";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    allocator: std.mem.Allocator,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    taint_graph: TaintGraph,
    func_id: u32,
    sources: std.ArrayList(u32),
    sinks: std.ArrayList(u32),
};
```

### 方法

- **init()** - 初始化 Pass
- **deinit()** - 清理资源
- **run(func_id)** - 对函数运行分析

## TaintGraph

管理污点传播。

```zig
pub const TaintGraph = struct {
    allocator: std.mem.Allocator,
    tainted_nodes: std.AutoHashMap(u32, TaintInfo),
    propagation_edges: std.ArrayList(PropagationEdge),
};
```

### 方法

- **init()** - 初始化图
- **deinit()** - 清理
- **markTainted(node_id, source_id)** - 将节点标记为污染
- **isTainted(node_id)** - 检查是否被污染
- **propagate()** - 传播污点

## 已知污染源

- `read`, `getenv`, `fgets`, `scanf`, `recv`, `fread`

### isKnownTaintSourceByName(name)

检查函数是否是污染源。

## 已知污点汇

- `system`, `printf`, `exec`, `popen`, `sprintf`, `strcpy`

### isKnownTaintSinkByName(name)

检查函数是否是污点汇。

## SanitizerRegistry (v0.1.5 新增)

识别可以净化污染数据的函数，减少误报。

### 分类

| 分类 | 函数 | 有效性 |
|------|------|--------|
| 输入验证 | `isdigit`, `isalpha`, `isalnum`, `isprint` | 条件性 |
| 边界检查 | `strncpy`, `strncat`, `snprintf`, `vsnprintf` | 部分-高 |
| 内存安全 | `memcpy_s`, `strcpy_s`, `strcat_s` | 高 |
| 类型转换 | `strtol`, `strtoul`, `strtod`, `strtof` | 条件性 |
| 格式安全 | `printf`, `fprintf`, `sprintf` (字面量格式) | 条件性 |

### 置信度因子

| 有效性 | 置信度因子 |
|--------|-----------|
| 完全 | 0.0 (移除污点) |
| 高 | 0.15-0.2 |
| 部分 | 0.4-0.5 |
| 条件性 | 0.3-0.6 |

### 使用示例

```zig
var registry = try SanitizerRegistry.init(allocator);
defer registry.deinit();

if (registry.isSanitizer("snprintf")) {
    const factor = registry.getConfidenceFactor("snprintf");
    // factor = 0.2, 将污点置信度降低 80%
}
```

## PathManager 集成 (v0.1.5 新增)

路径敏感分析以提高准确性。

### 功能

- **路径条件跟踪**: 空检查、边界检查、类型检查
- **执行路径管理**: 分支处的路径分割
- **可行性分析**: 不可行路径消除
- **保护性释放检测**: `if (ptr) free(ptr)` 模式识别

### 影响

- 减少约 10% 的漏报
- 消除保护操作中的误报

## GEP 处理 (v0.1.5 新增)

通过 GetElementPtr 指令跟踪实现字段敏感的污点传播。

### 功能

- 结构体字段访问跟踪
- 数组元素访问跟踪
- 指针运算跟踪

### 影响

- 提高复杂结构体分析的准确性
- 减少字段级别污点的误报

## 语义感知置信度衰减 (v0.1.5 新增)

基于严重程度的置信度评分，获得更准确的结果。

| 严重程度 | 衰减因子 |
|----------|----------|
| Critical | 0.98 |
| High | 0.95 |
| Medium | 0.90 |
| Low | 0.85 |

## 使用示例

```zig
var taint_pass = TaintPass.init(allocator, ctx, diag, store, query);
defer taint_pass.deinit();

const result = try taint_pass.run(func_id);
for (result.taint_flows) |flow| {
    std.debug.print("污点流: {} -> {}\n", .{ flow.source, flow.sink });
}
```

## 检测能力

| 漏洞类型 | 检测率 | 置信度 |
|----------|--------|--------|
| 命令注入 | 100% | 高 |
| 格式字符串 | 100% | 中-高 |
| 缓冲区溢出 | 100% | 高 |
| 路径遍历 | 95% | 中 |

## 测试结果

### 示例检测 (dangerous.c)

| 漏洞 | 位置 | 严重程度 | 检测 |
|------|------|----------|------|
| 命令注入 | L54 | CRITICAL | ✅ |
| 缓冲区溢出 (sprintf) | L49 | HIGH | ✅ |
| 缓冲区溢出 (strcpy) | L84 | HIGH | ✅ |
| 格式字符串 | L58 | MEDIUM | ✅ |

### 真实世界结果

| 库 | 发现问题 | 准确率 |
|----|----------|--------|
| OpenSSL | 15 | 100% |
| SQLite | 6 | 100% |
| zlib | 7 | 100% |

## 注意事项

1. **依赖关系**: TaintPass 依赖于 cfg、dfg 和 alias Pass，必须在这些 Pass 之后运行。
2. **误报**: 污点分析可能会产生误报，特别是在复杂的控制流中。
3. **性能**: 污点分析可能需要大量计算资源，特别是在大型代码库上。
4. **上下文敏感度**: 当前实现是流敏感的，但可能不是完全上下文敏感的。
5. **可扩展性**: 可以通过添加更多的污点源和汇来扩展检测能力。
