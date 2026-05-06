# Pass 参考

> "13 个 pass，一条流水线，对内存 bug 零容忍。"

> 版本: v0.1.7 | 最后更新: 2026-05-06

OmniScope 的分析引擎由 13 个 pass 组成，分为 Foundation、Tier 1（透传）和 Tier 2（图驱动）三层。每个 pass 都是独立的分析单元，通过共享图数据结构进行通信。

## 数据流总览

```mermaid
flowchart TD
    LLVMIR["LLVM IR<br/>(.bc / .ll)"]

    subgraph Foundation["Foundation Passes"]
        cfg["cfg"]
        dfg["dfg"]
        cfg --> dfg
    end

    subgraph Tier1["Tier 1: Pass-Through<br/>(构建数据，不报 issue)"]
        call_graph["call-graph"]
        pointer_flow["pointer-flow"]
        pointer_own["pointer-ownership"]
        return_check["return-check"]
    end

    subgraph Tier2["Tier 2: Graph-Driven<br/>(所有 issue 经 isOnDangerPath 门控)"]
        ptr_lifetime["ptr-lifetime"]
        danger_surface["danger-surface"]
        ffi_boundary["ffi-boundary"]
        ffi_type_mismatch["ffi-type-mismatch"]
        ffi_body_check["ffi-body-check"]
        ffi_unsafe["ffi-unsafe"]
        callback_esc["callback-escape"]
        memory_safety["memory-safety"]
        free_validation["free-validation"]
    end

    subgraph OutputLayer["输出 & 报告<br/>Text / JSON / SARIF"]
    end

    LLVMIR --> Foundation
    Foundation --> Tier1
    Tier1 --> Tier2
    Tier2 --> OutputLayer

    call_graph -->|CrossLangEdge| ptr_lifetime
    ptr_lifetime -->|MemoryGraph| danger_surface
    danger_surface -->|DangerSurface markers| ffi_boundary
    danger_surface --> ffi_type_mismatch
    danger_surface --> ffi_body_check
    danger_surface --> ffi_unsafe
    danger_surface --> callback_esc
    danger_surface --> memory_safety
    danger_surface --> free_validation
```

## Foundation Passes

### `cfg` -- 控制流图

**一切的基础。**

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/foundation/cfg.zig` |
| Tier | Foundation |
| 依赖 | 无 |
| 产出 | `cfg_edge` fact |
| 报告 issue | 否 |

构建每个函数的控制流图（CFG）。遍历所有 BasicBlock，记录块间的跳转关系，输出 `cfg_edge` fact 到 FactStore。

没有这个 pass，其他什么都跑不起来。它是分析世界的 `main()`。

```zig
pub const name = "cfg";
pub const kind = PassKind.foundation;
pub const deps = &[_][]const u8{};
```

### `dfg` -- 数据流图

**一切的基础。**（没错，CFG 和 DFG 都是。）

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/foundation/dfg.zig` |
| Tier | Foundation |
| 依赖 | `cfg` |
| 产出 | `dfg_edge` fact |
| 报告 issue | 否 |

构建每个函数的数据流图（DFG）。追踪指令间的数据依赖关系（def-use chain），输出 `dfg_edge` fact。依赖 cfg 先完成。

```zig
pub const name = "dfg";
pub const kind = PassKind.foundation;
pub const deps = &[_][]const u8{"cfg"};
```

## Tier 1: Pass-Through Passes

Tier 1 pass 处理**纯 C/C++ 内部操作**。它们构建和丰富中间数据结构，但**不直接报告 issue**。它们的角色是信息收集和轻量级分类。

### `call-graph` -- 调用图

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/call_graph.zig` |
| Tier | Tier 1 |
| 依赖 | 无 |
| 产出 | `CrossLangEdge` 列表 |
| 报告 issue | 否 |

构建函数调用图，记录函数间的关系。将函数分类为 `internal`（模块内定义）、`libc`（标准 C 库，可信）、`external_unknown`（来源不明，可能是 FFI 边界）。

关键产出：为每个 FFI 调用点生成 `CrossLangEdge`，记录调用者/被调用者的语言、是否跨 FFI 边界、指针参数索引。下游 pass（ptr-lifetime、ffi-boundary、callback-escape、danger-surface）消费这些边。

```zig
pub const FunctionKind = enum {
    internal,          // 模块内定义
    libc,              // 标准 C 库（可信）
    external_unknown,  // 来源不明（潜在 FFI 边界）
};
```

### `pointer-flow` -- 指针流追踪

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/taint_propagation.zig` |
| Tier | Tier 1 |
| 依赖 | `call-graph` |
| 产出 | 指针流图 |
| 报告 issue | 否 |

追踪指针值在赋值、参数传递和返回值之间的流动。这是污点分析（taint analysis）的基础设施。

注意：在当前实现中，pointer-flow 的功能由 `taint_propagation.zig` 提供。

### `pointer-ownership` -- 指针所有权追踪

**绝对主力。**

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/pointer_ownership.zig` |
| Tier | Tier 1 |
| 依赖 | 无 |
| 产出 | `alloc_map` / `free_map` |
| 报告 issue | 否 |

追踪指针在 FFI 边界的所有权。检测跨语言 free 不匹配（Rust 分配、C 释放，或反之）、所有权丢失、double free 风险。

通过 def-use chain 追踪所有权状态。集成了过程间分析（函数摘要）和路径敏感分析（null check 追踪）。使用 MemoryPool 减少分配开销，Profiler 进行性能分析。

```zig
// v0.2: 过程间分析（函数摘要）
// v0.3: MemoryPool + Profiler + BoundaryAnalyzer
```

### `return-check` -- 返回值检查

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/issue/return_check.zig` |
| Tier | Tier 1 |
| 依赖 | 无 |
| 产出 | 无（直接验证） |
| 报告 issue | 否 |

验证危险函数的返回值是否被检查。`malloc`、`open`、`read` 等函数的返回值必须检查——忽略它们是经典的 bug 来源。

```zig
const DangerousFunctions = &[_][]const u8{
    "malloc", "open", "read", "write", "system", "exec", "popen",
};

const SafeReturnFunctions = &[_][]const u8{
    "free",    // void 返回，无需检查
    "close",   // 实践中很少需要检查
    "fflush",  // void 返回
    "fclose",  // 实践中很少需要检查
};
```

## Tier 2: Graph-Driven Passes

Tier 2 pass 执行 **FFI 和 unsafe 边界分析**。每个 issue 的报告都经过 `isOnDangerPath()` 门控——统一检查 `DangerSurface` 标记集。如果函数或指针不在危险路径上，pass 会静默跳过。

### `ptr-lifetime` -- 指针生命周期追踪

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/ptr_lifetime.zig` |
| Tier | Tier 2 |
| 依赖 | `call-graph` |
| 产出 | `MemoryGraph` |
| 消费 | `CrossLangEdge`, `DangerSurface` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

追踪 raw pointer 的生命周期，检测：
- 栈指针逃逸到 FFI callback（返回后悬垂）
- Use-after-scope（指针在分配作用域结束后使用）
- 返回栈地址（未定义行为）
- 堆指针传给 extern 但未转移所有权

设计原则：过程内分析 + def-use chain 追踪。仅基于 IR fact，不需要过程间别名分析。

```rust
// 检测示例：栈指针逃逸到 C callback
unsafe {
    let buf = [0u8; 256];
    c_callback(buf.as_ptr());  // BUG: buf 在作用域退出时被释放
}
```

```
// 检测示例：返回栈地址
fn getBuffer() [*]const u8 {
    var buf: [64]u8 = undefined;
    return &buf;  // BUG: 栈内存在返回时失效
}
```

### `danger-surface` -- 危险表面标记

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/danger_surface.zig` |
| Tier | Tier 2 |
| 依赖 | `call-graph` |
| 产出 | `DangerSurface` markers |
| 消费 | `CrossLangEdge`, `MemoryGraph` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

从"扫描一切"到"从危险表面向外追踪"的核心架构转变。这是 Tier 2（严格分析）的唯一入口。

算法（优化后 O(E x avg_args) 代替 O(N x B)）：
1. 收集所有危险表面（FFI 边界 `CrossLangEdge`）
2. 如果没有 FFI 边界 -> 提前返回（纯 C 项目快速路径）
3. 对每个表面，通过 call_arg/call_ret 边找到关联指针
4. 仅对这些指针执行 `isOnDangerPath` 检查
5. 回退：扫描所有节点查找 cross_lang_lifecycle + unsafe_alloc

没有这个 pass，其他什么都跑不起来。它是分析世界的 `main()`。

### `ffi-boundary` -- FFI 边界检测

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/ffi_boundary.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | `FFIBoundary` issue |
| 消费 | `CrossLangEdge` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

检测 FFI 调用边界。这是编排器（Orchestrator），将具体工作委托给：
- `ffi_zone_check.zig` -- Zone 分类
- `ffi_boundary_check.zig` -- 核心边界检查
- `ffi_noise_filter.zig` -- 噪声过滤

集成了类型检查器、语言分类器、安全检查器、噪声缩减等模块。

### `ffi-type-mismatch` -- FFI 类型不匹配检测

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/ffi_type_mismatch.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | 类型不匹配 issue |
| 消费 | `noise_filter` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

检测 FFI 边界的类型不匹配。支持所有语言：
- C/C++: extern 声明、API 边界
- Rust: `extern "C"`、unsafe FFI
- Go: cgo 调用（`C.CBytes`、`C.malloc` 等）
- Zig: extern 声明、`@cImport`
- Python: C API 调用（`Py*`、`PyObject*`）

FFI 边界是每个编译器的盲区，因此是 UB 的最危险来源。

```zig
pub const TypeMismatchKind = enum(u8) {
    size_mismatch,      // 大小不匹配（如 usize vs size_t on 32-bit）
    sign_mismatch,      // 符号不匹配（如 i32 vs u32）
    alignment_mismatch, // 对齐不匹配
    enum_mismatch,      // 枚举表示不匹配
    struct_layout,      // 结构体布局不匹配
    pointer_type,       // 指针类型不匹配
};
```

### `ffi-body-check` -- FFI 函数体审计

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/issue/ffi_body_check.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | 危险调用 issue |
| 消费 | `noise_filter`, `ffi_semantics` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

审计 FFI 边界函数的函数体，检测对危险函数的调用（如 `printf`、`system` 等）。使用语义模型进行噪声缩减和精确分析。

### `ffi-unsafe` -- FFI Unsafe 检测

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/issue/ffi_unsafe.zig` |
| Tier | Tier 2 |
| 依赖 | `ffi-boundary` |
| 产出 | unsafe 模式 issue |
| 消费 | 无 |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

检测 FFI 边界的 unsafe 模式。包括：
- 危险函数调用（`system`、`exec`、`popen`、`strcpy`、`gets` 等）
- 控制流违规（`setjmp`/`longjmp` 在 FFI 边界）
- 可变参数函数滥用（`vprintf`、`vsprintf` 等）
- 内存操作（`malloc`、`free`、`realloc`、`calloc`）

```zig
const DangerousPatterns = &[_][]const u8{
    "system", "popen", "exec", "execve", "execvp", "execv",
    "malloc", "free", "realloc", "calloc",
    "strcpy", "strcat", "gets", "sprintf",
    "setjmp", "longjmp", "sigsetjmp", "siglongjmp",
    "vprintf", "vfprintf", "vsprintf", "vsnprintf",
};
```

### `callback-escape` -- Callback 逃逸检测

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/callback_escape.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | callback 逃逸 issue |
| 消费 | `CrossLangEdge`, `DangerSurface` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

检测 callback 指针跨 FFI 逃逸。主要检测目标：
- Go 指针通过 `C.CBytes()` 传给 C 但没有 `runtime.KeepAlive`
- `unsafe.Pointer` 转换可能在 GC 后悬垂
- C 函数在调用作用域之外保留 Go 分配的指针
- cgo 代码中缺失 `C.free` / `C.malloc` 配对

```go
// 检测示例：C 保留指针，GC 可能回收
var buf []byte{1, 2, 3}
C.process(C.CBytes(string(buf)))  // C 保留指针，GC 可能回收 buf
```

### `memory-safety` -- 内存安全检测

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/issue/memory_safety.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | 内存安全问题 issue |
| 消费 | `DangerSurface` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

通用内存安全检测。真正的单遍实现：
1. 对每个函数：hash 函数名（u64，零拷贝）
2. 扫描指令：Call -> 记录 call_graph；Alloc -> 记录 origins；Free -> **立即**验证
3. 内联报告 issue（无第二遍）

性能特征：
- 时间：O(N)，N = 总指令数（单次线性扫描）
- 空间：O(F + A)，F = 函数数，A = alloc/free 操作数
- 热路径无字符串拷贝（基于 hash）
- 预分配 HashMap 防止 rehash

### `free-validation` -- Free 验证

| 属性 | 值 |
|------|-----|
| 文件 | `src/pass/analysis/issue/free_validation.zig` |
| Tier | Tier 2 |
| 依赖 | 无显式依赖 |
| 产出 | 无效 free issue |
| 消费 | `MemoryGraph`, `DangerSurface` |
| 报告 issue | 是（经 `isOnDangerPath` 门控） |

检测对非分配来源指针调用 `free()`。这会导致未定义行为。

设计原则：仅基于 IR fact，不猜测。追踪指针来源（`from_malloc`、`from_param`、`from_global`、`unknown`），检查 `free()` 调用的来源合法性。

```zig
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free", "dealloc", "deallocate",
    "operator delete", "operator delete[]",
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};
```

## Pass 依赖图

```mermaid
graph TD
    subgraph Tier1["Tier 1 (透传)"]
        call_graph["call-graph"]
        pointer_flow["pointer-flow"]
        pointer_ownership["pointer-ownership"]
        return_check["return-check"]
    end

    subgraph Tier2["Tier 2 (图驱动)"]
        ptr_lifetime["ptr-lifetime"]
        danger_surface["danger-surface"]
        ffi_boundary["ffi-boundary"]
        ffi_type_mismatch["ffi-type-mismatch"]
        ffi_body_check["ffi-body-check"]
        ffi_unsafe["ffi-unsafe"]
        callback_esc["callback-escape"]
        memory_safety["memory-safety"]
        free_validation["free-validation"]
    end

    call_graph -->|CrossLangEdge| ptr_lifetime
    pointer_flow --> call_graph
    ptr_lifetime --> danger_surface
    danger_surface --> ffi_boundary
    danger_surface --> ffi_type_mismatch
    danger_surface --> ffi_body_check
    ffi_boundary --> ffi_unsafe
    danger_surface --> callback_esc
    danger_surface --> memory_safety
    danger_surface --> free_validation
    call_graph -->|CrossLangEdge| ffi_boundary
```

## `isOnDangerPath` 门控

所有 Tier 2 pass 在报告 issue 之前都必须经过这个检查：

```zig
fn isOnDangerPath(fn_or_ptr: ID) bool {
    return dangerSurfaceMarkers.contains(fn_or_ptr);
}
```

不在危险路径上？直接跳过。这个单一门控防止了非 FFI 内部代码路径的噪声。

## 已知依赖 Bug（v0.1.7）

以下 Tier 2 pass 存在不正确的依赖声明，可能在所需输入图完全填充之前执行：

1. **free_validation**: 声明依赖 `ptr-lifetime` 但未声明依赖 `danger-surface`。可能在 `DangerSurface` 标记可用之前运行，导致 `isOnDangerPath()` 对所有 site 返回 false。
2. **memory_safety**: 未声明依赖 `danger-surface`。与 free_validation 相同的门控问题。
3. **danger_surface**: 未声明依赖 `ptr-lifetime`。可能在 `MemoryGraph` 填充之前运行，产生不完整的危险表面标记。

## Issue 检测分类

| 类别 | IssueKind | 严重度 | 置信度 |
|------|-----------|--------|--------|
| **内存** | memory_leak, use_after_free, double_free, invalid_free | Critical/High | 0.70-0.90 |
| **FFI** | ffi_unsafe_call, unchecked_return, type_mismatch | High | 0.65-0.80 |
| **Rust FFI** | borrow_escape, cross_language_leak, unpaired_into_raw | High | 0.75-0.85 |
| **安全** | command_injection, format_string, buffer_overflow | Critical | 0.75-0.90 |
| **解引用** | null_dereference | Critical | 0.85 |
| **并发** | (通过锁分析) | High | TBD |

## 输出格式

### 文本（默认）

```
VULNERABILITY OMI-001 [high] [Confidence: medium]
Type: borrow_escape
Reason: as_ptr() on local String/Vec passed to extern C - may dangle
```

### JSON（稳定 Schema v1）

```json
{
  "schema_version": "1.0.0",
  "tool": "omniscope",
  "tool_version 0.1.7",
  "summary": {"functions": 135, "issues": 6, "time_ms": 91},
  "issues": [{
    "id": "OMI-001",
    "kind": "borrow_escape",
    "severity": "high",
    "confidence": "MEDIUM",
    "confidence_score": 0.80,
    "cwe_id": 704,
    "reason": "as_ptr() on local String/Vec passed to extern C",
    "message": "Potential as_ptr borrow escape",
    "location": {"function": "leak_cstring"}
  }]
}
```

### SARIF v2.1.0

- 14 条规则定义（覆盖所有 IssueKind 变体）
- GitHub Code Scanning 兼容
- 属性：`confidence`、`confidenceLevel`、`reason`、`cwe`
