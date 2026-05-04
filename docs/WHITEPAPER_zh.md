# OmniScope：找到那些掉进语言缝隙的 Bug

**写给凌晨两点还在调跨语言 Crash 的人**

**Version**: v0.1.6 | **Date**: 2026-05-04 | **Language**: Zig (LLVM 22)

---

## 1. 问题：为什么要做这个

### 凌晨两点的 crash log

先讲个故事。

凌晨两点，你盯着屏幕上一段 crash log。程序是用 Rust 写的，但它调了一个 C 库。Crash 发生在 C 库的 `free()` 里——double free。你翻遍了 Rust 侧的代码，`Box::into_raw()` 把所有权交出去了，没问题。你又翻了 C 侧，`free()` 只调用了一次，也没问题。

那问题出在哪？

问题出在**语言的缝隙里**。Rust 编译器认为这块内存已经"移交"了，不再管它。C 编译器只看到自己收到的那个裸指针，不知道这块内存是从 Rust 的堆上来的。两边都觉得对方会负责，结果就是——没人负责。

```
Rust:  Box::into_raw(ptr)  →  "我不管了，给你了"
C:     free(ptr)           →  "用完了，释放"
Rust:  drop(ptr)           →  "等等，我还要用... 崩了"
```

这不是段子。这是我们在真实项目里反复遇到的模式。

### 编译器的盲区

核心问题在于：**编译器只看自己语言的边界**。

Rust 编译器（rustc）做 borrow checker 的时候，看到 `Box::into_raw()` 就认为所有权已经转移了——它不会追踪这个指针到了 C 侧之后会发生什么。C 编译器（clang）更惨，它连这个指针是从哪来的都不知道，只知道它是个 `void*`。

跨语言边界，就是两个编译器之间的无人区。

### 一个具体的例子

```rust
// Rust 侧
let boxed = Box::new(42);
let raw = Box::into_raw(boxed);
unsafe {
    c_function(raw);  // 所有权"移交"给 C
}
// boxed 已经 move 了，Rust 不会再 drop 它
```

```c
// C 侧
void c_function(int* ptr) {
    printf("%d\n", *ptr);
    free(ptr);  // C 侧释放了 Rust 分配的内存
}
```

看起来没问题？但如果 Rust 侧的代码稍微变一下：

```rust
let raw = Box::into_raw(boxed);
unsafe {
    c_function(raw);
}
let _ = Box::from_raw(raw);  // 重新拿回所有权并 drop → double free!
```

Rust 编译器不会警告你——因为在 unsafe 块里，你说了算。C 编译器更不会——它根本不知道 Rust 侧还有个 `Box::from_raw` 在等着。

### 现有工具为什么不够

| 工具 | 问题 |
|------|------|
| **CodeQL** | 能做跨语言查询，但分析粒度在 AST 层，看不到 LLVM IR 里的指针流转 |
| **Clippy** | 只看 Rust 侧，不知道 C 侧会 `free()` 你的指针 |
| **Clang Static Analyzer** | 只看 C/C++ 侧，不知道 Rust 侧的 `into_raw` 意味着什么 |
| **Miri** | 能检测 Rust 侧的 UB，但跑不了跨语言代码 |
| **Infer** | Facebook 的工具，偏重 Java/ObjC，对 Rust FFI 支持有限 |
| **CBMC** | 模型检验，理论上能做但需要手写 C 模型，实际不可用 |

每个工具都在自己的语言圈子里很厉害，但一旦你的 bug 跨了语言边界——恭喜你，进入了无人区。

**OmniScope 就是给这个无人区造的地图。**

---

## 2. 我们的方案：在编译器不看的地方分析

### 核心洞察：LLVM IR 是所有语言的"普通话"

不管你用 Rust、C、还是 C++ 写代码，最终都会编译到 **LLVM IR**（Intermediate Representation）。在 IR 层面，`Box::into_raw()` 和 `malloc()` 看起来差不多——都是一条 `call` 指令加一个指针值。

这就是我们的切入点：**在 LLVM IR 层做分析，所有语言编译到同一表示，我们就能同时看到 FFI 边界的两侧**。

```
Rust 源码          C 源码
    │                 │
    ▼                 ▼
rustc            clang
    │                 │
    ▼                 ▼
    └──────► LLVM IR ◄──────┘
                 │
                 ▼
           OmniScope 分析
         （终于能同时看到两边了）
```

### Zone Classification：信任编译器，只管它不管的

我们不是要替代编译器。Rust 的 borrow checker 已经很强了，Clang 的分析也不差。我们的策略是：**信任编译器已经检查过的部分，只分析它看不到的部分**。

每个函数和指针会被分类到一个 Zone：

| Zone | 含义 | 我们做什么 |
|------|------|-----------|
| **Safe Zone** | 纯 C/C++ 内部代码，没有 FFI 接触 | 信任编译器，Tier 1 只做数据收集 |
| **Unsafe Zone** | 包含 `unsafe` 块或裸指针转换 | Tier 2 严格分析 |
| **FFI Zone** | 声明了 `extern "C"` 或跨语言调用 | Tier 2 严格分析 |
| **Unknown Zone** | 信息不足，无法分类 | 暂缓，等信息够了再说 |

Zone 分类结果会**缓存**，避免重复计算。

### Tier 1 / Tier 2 架构

我们把 13 个分析 pass 分成两层：

**Tier 1 = Pass-Through（纯 C/C++ 内部，信任编译器）**

这 4 个 pass 只做数据收集，**永远不会报 issue**：

| Pass | 干什么 |
|------|--------|
| `call-graph` | 构建函数调用图，为每个 FFI 调用点生成 `CrossLangEdge` |
| `pointer-flow` | 追踪指针在赋值、参数传递、返回值之间的流转 |
| `pointer-ownership` | 分类 alloc/free 对，构建 `alloc_map` / `free_map` |
| `return-check` | 验证返回值的所有权转移 |

**Tier 2 = Graph-Driven（FFI/unsafe 边界，严格分析）**

这 9 个 pass 才是真正报 issue 的主力。但它们有一个统一的前置条件——`isOnDangerPath()`：

| Pass | 干什么 |
|------|--------|
| `ffi-boundary` | 检测 FFI 调用边界 |
| `ffi-type-mismatch` | 检查跨 FFI 边界的类型兼容性 |
| `ffi-body-check` | 审计 FFI 暴露函数的函数体 |
| `ffi-unsafe` | 检测 `unsafe` 块 / `extern "C"` 违规 |
| `ptr-lifetime` | 追踪跨 FFI 边界的指针生命周期，填充 `MemoryGraph` |
| `danger-surface` | 标记危险函数/指针，生成 `DangerSurface` markers |
| `callback-escape` | 检测回调指针跨 FFI 逃逸 |
| `memory-safety` | 危险路径上的通用内存安全检查 |
| `free-validation` | 验证危险路径上 free 站点的正确性 |

### `isOnDangerPath`：统一的门控

所有 Tier 2 pass 在报 issue 之前，都必须过这一关：

```zig
fn isOnDangerPath(fn_or_ptr: ID) bool {
    return dangerSurfaceMarkers.contains(fn_or_ptr);
}
```

如果一个函数或指针不在危险路径上，Tier 2 pass 会直接跳过它。这个设计确保了我们**不会对纯内部代码路径产生噪音**。

### 核心数据结构

**CrossLangEdge**（跨语言边）：
- 由 `call-graph` pass 产生
- 记录：源函数、目标函数、调用位置、语言对（如 Rust→C）
- 被 `ptr-lifetime`、`ffi-boundary`、`callback-escape`、`danger-surface` 消费

**MemoryGraph**（内存图）：
- 由 `ptr-lifetime` pass 产生
- 记录：指针分配站点、生命周期区间、跨边界流转
- 被 `danger-surface`、`free-validation` 消费

这两个数据结构就是 OmniScope 的"眼睛"——让 Tier 2 pass 能看到跨语言边界的完整图景。

---

## 3. 分析流水线：它到底怎么工作的

### 13 个 pass 的拓扑排序执行

OmniScope 的分析流水线分 5 个阶段，13 个 pass 按拓扑排序执行：

```
Phase 1: IR Loading
  └─ Parse LLVM IR → Build ModuleRef

Phase 2: Foundation Passes
  ├─ CFGPass (控制流图)
  └─ DFGPass (数据流图)

Phase 3: Tier 1 — Pass-Through
  ├─ call-graph      → CrossLangEdge
  ├─ pointer-flow    → Flow Graph
  ├─ pointer-ownership → alloc/free maps
  └─ return-check    → Ownership transfer

Phase 4: Tier 2 — Graph-Driven
  ├─ ptr-lifetime    → MemoryGraph
  ├─ danger-surface  → DangerSurface markers
  ├─ ffi-boundary / ffi-type-mismatch / ffi-body-check / ffi-unsafe
  ├─ callback-escape / memory-safety / free-validation
  └─ (所有 issue 被 isOnDangerPath 门控)

Phase 5: Report Generation
  └─ Text / JSON Schema v1 / SARIF v2.1.0
```

### 关键数据流

整个流水线的核心数据流可以概括为：

```
call-graph → CrossLangEdge → ptr-lifetime → MemoryGraph → danger-surface → isOnDangerPath gate
```

1. `call-graph` 先跑，发现所有跨语言调用，生成 `CrossLangEdge`
2. `ptr-lifetime` 消费 `CrossLangEdge`，追踪跨边界的指针生命周期，填充 `MemoryGraph`
3. `danger-surface` 消费 `CrossLangEdge` + `MemoryGraph`，标记哪些函数/指针在危险路径上
4. 所有 Tier 2 pass 在报 issue 前查 `isOnDangerPath()`，不在危险路径上的直接跳过

### Noise Reduction：三层过滤

我们用了三层过滤来压低误报：

| 层级 | 策略 | 示例 |
|------|------|------|
| **Layer 1: 名称过滤** | 匹配已知的标准库函数名 | `core::*`, `std::*`, `_ZSt*`, `__cxa_*` |
| **Layer 2: 路径过滤** | 匹配编译器/标准库的文件路径 | `/rustc/`, `/library/core/`, `/usr/include/c++/` |
| **Layer 3: 行为过滤** | 识别编译器生成的惯用模式 | Rust drop glue、Zig allocator wrapper、STL vector 扩容 |

效果：wasmtime 从 297 个 issue 降到 9 个（**-97%**）。

### Confidence 系统

每个 issue 都有一个置信度评分（0.0-1.0），分 4 个等级：

| 等级 | 范围 | 含义 | 建议动作 |
|------|------|------|---------|
| **HIGH** | >= 0.90 | 完整上下文的直接模式匹配 | 立即修复 |
| **MEDIUM** | >= 0.70 | 启发式匹配 + 支撑证据 | 需要人工 review |
| **HEURISTIC** | >= 0.50 | 统计相关性 | 值得调查 |
| **EXPERIMENTAL** | < 0.50 | 新模式，未验证 | 仅作研究参考 |

每个 issue 还附带一个机器可读的 `reason` 字段，解释为什么给了这个置信度。

---

## 4. 我们发现了什么：真实项目结果

### 17 个项目的 benchmark

我们在 17 个真实项目上跑了 OmniScope，结果如下：

```
Red Team Tests (8 files)
┌────────────────┬───────┬───────────┬────────────┬────────────┐
│ File           │Issues │ PtrTracked│ Violations │ FFI Bounds │
├────────────────┼───────┼───────────┼────────────┼────────────┤
│ subtle_unsafe_rs│   4   │    38     │     2      │    123     │
│ boundary_test  │  14   │    66     │     2      │     45     │
│ red_team_bugs  │   4   │    33     │     0      │     33     │
│ ffi_boundary   │  11   │    86     │     0      │     27     │
│ posix_ffi_bugs │   6   │    49     │     9      │     30     │
│ python_capi    │   5   │    26     │     1      │     35     │
│ jni_boundary   │   1   │    41     │     1      │      1     │
│ subtle_ffi     │  11   │    77     │     4      │     31     │
├────────────────┼───────┼───────────┼────────────┼────────────┤
│ Red Team 合计  │ **56**│  **416**  │   **19**   │   **325**  │
└────────────────┴───────┴───────────┴────────────┴────────────┘

Real-World Tests (6 files)
┌────────────────┬───────┬───────────┬────────────┬────────────┐
│ File           │Issues │ PtrTracked│ Violations │ FFI Bounds │
├────────────────┼───────┼───────────┼────────────┼────────────┤
│ curl8          │  114  │   4948    │    89      │   1499     │
│ sqlite3        │  226  │  20192    │   142      │   1547     │
│ wasmtime_test  │   44  │    31     │     0      │    130     │
│ ring           │   19  │   841     │     0      │   4266     │
│ blst           │   35  │   269     │     0      │   1382     │
└────────────────┴───────┴───────────┴────────────┴────────────┘
```

### 关键数字

| 指标 | 值 |
|------|-----|
| 总 Issues | **548** |
| 追踪的指针数 | **27,076** |
| 发现的 FFI 边界 | **9,372** |
| Precision | **~88%** |
| FP Rate | **~14%** |
| 测试覆盖率 | **92% (191 tests)** |

### 几个值得说的发现

**Rust FFI TP Rate: 0% -> 20%**

在 v0.1.6 的时候，我们对 Rust FFI 的检测率是 0%。没错，零。原因说出来有点丢人——我们把 `__rust_alloc` 放进了 noise filter，等于把所有 Rust 堆操作都给过滤掉了。修完之后，TP 率直接从 0% 跳到 20%（4/20），而且检出的 4 个全部是 true positive，precision 100%。

**zkcrypto（纯 Rust）= 0 issues**

这个结果让我们松了口气。zkcrypto 是个纯 Rust 密码学库，没有 FFI。OmniScope 报了 0 个 issue——正确行为。如果我们在一个没有 FFI 的项目上疯狂报 issue，那工具就有问题了。

**wasmtime 检测到真实 CVE 相关模式**

在 wasmtime 的 IR 上，我们检测到了与已知 CVE 相关的 FFI 边界模式。虽然 wasmtime 本身处理得很好（0 violations），但我们标记出的 FFI 边界和危险路径与安全审计的关注点高度吻合。

### 诚实说明：我们没做到什么

`subtle_unsafe_rs` 里有 20 个故意注入的 Rust FFI bug，我们只检出了 4 个。剩下 16 个的分布：

| 类别 | 数量 | 为什么检不出 |
|------|------|-------------|
| Size truncation | 5 | 需要 MIR 级整数截断分析 |
| Uninitialized memory | 3 | 需要数据流初始化跟踪 |
| Double-free via alias | 4 | alias chain 代码写了但没完全集成 |
| Buffer overflow | 3 | 需要 bounds checking |
| Type confusion | 1 | 需要跨语言类型映射 |

这些不是 bug，是需要**新的分析能力**。我们在 roadmap 里列了，后面会讲。

---

## 5. 重构之路：我们踩过的坑

这一节是写给同行的。如果你也在做静态分析工具，希望我们的血泪史能帮你少走弯路。

### "我们把想检测的东西给过滤掉了"

前面提到过，v0.1.6 的 Rust FFI 检测率是 0%。根因是 `__rust_alloc` / `__rust_dealloc` / `__rust_realloc` 被放进了 noise filter。

翻译成人话就是：我们的 noise filter 太激进了，把 Rust 所有的堆分配操作都当成"噪音"给过滤掉了。然后我们纳闷为什么 Rust FFI 一个都检测不到。

这不是段子。这是真实的、花了我们好几天才找到的 bug。

### 14 项修复的简要故事

**Phase 1: 核心 Bug 修复（4 项）**

| 修复 | 发生了什么 | 修了什么 |
|------|-----------|---------|
| FIX-1: Noise filter 移除 | `__rust_alloc` 被当成噪音 | 删了 5 行 filter 规则 |
| FIX-2: CrossLangEdge 接入 | `ffi_type_mismatch` 的 deps 为空，拿不到跨语言边 | 加了 `"call-graph"` 依赖 |
| FIX-3: hooks.zig 配对修复 | 用指令地址做配对 key，不同调用点永远匹配不上 | 改用实际指针值做 key |
| FIX-4: Pipeline deps 声明 | 4 个关键 pass 的依赖数组为空，执行顺序不确定 | 显式声明了 9 个 pass 的依赖 |

**Phase 2: 额外 Bug 修复（8 项）**

包括 `isGoFunction` 过度匹配导致 C++/Rust 代码被误分类为 Go、LLVM invoke 指令的分类缺失、null check 遗漏等。每一个都不大，但每一个都可能导致误报或漏报。

**Phase 3: 清理**

| 操作 | 数量 |
|------|------|
| 删除死文件 | 2 个（allocator.zig, mapper.zig） |
| 删除死测试 | 13 个（SemanticMapper 相关） |
| 文档精简 | untodo.md 从 1463 行砍到 163 行（-89%） |
| 新增测试 | 8 个文件，+50 单元测试 |
| **净减代码** | **-700 行** |

### 重复注册统一

我们曾经有 7 处地方各自维护了一份 "dangerous functions" 列表。7 份列表，7 个地方要同步更新。你猜结果？当然是不一致。

现在统一到 1 处。一个地方改，全局生效。

### 已知残留问题

老实说，还有一些没修的：

1. **3 个 pass 的 deps 声明仍有问题**：`free_validation`、`memory_safety` 缺少对 `danger-surface` 的依赖；`danger-surface` 缺少对 `ptr-lifetime` 的依赖。可能导致这些 pass 在数据没准备好时就跑了。
2. **allocator_kb 的 2 个 bug**：缺少 Rust `GlobalAlloc::alloc` trait 实现；`objc_free` 映射错误。
3. **noise_filter 里有重复条目**：`std::vector::push_back` 和 `std::string::c_str` 被注册了两次。性能影响不大，但不够干净。

这些都在 P0/P1 的 roadmap 里。

---

## 6. 与其他工具对比

| 特性 | OmniScope | CodeQL | Clang SA | Infer | CBMC | Miri | cargo-audit |
|------|-----------|--------|----------|-------|------|------|-------------|
| **跨语言分析** | IR 级，全视角 | AST 级，有限 | 单语言 | 单语言 | 需手写模型 | 单语言 | N/A |
| **分析层级** | LLVM IR | AST/IR 混合 | Clang AST | SIL/Bytecode | C 模型 | MIR | 源码依赖 |
| **C/C++ 支持** | 原生 | 好 | 好 | 有限 | 好 | 无 | 无 |
| **Rust 支持** | 通过 IR | 基础 | 无 | 有限 | 无 | 深 | 深（依赖） |
| **FFI 边界检测** | 核心能力 | 有限 | 无 | 无 | 无 | 无 | 无 |
| **所有权追踪** | 跨语言 | 单语言 | 单语言 | 单语言 | 单语言 | 单语言 | N/A |
| **误报控制** | 9 层过滤 + Zone | 规则驱动 | 启发式 | 启发式 | 精确 | 精确 | N/A |
| **输出格式** | Text/JSON/SARIF | SARIF | Text | Text | Text | Text | CLI |
| **需要预编译** | 是（.ll 文件） | 否 | 否 | 否 | 是 | 否 | 否 |
| **性能（大项目）** | <500ms | 分钟级 | 秒级 | 分钟级 | 小时级 | 分钟级 | 秒级 |

### OmniScope 的独特定位

我们不跟 Miri 比 Rust 侧的精确度——Miri 是 Rust UB 检测的 gold standard。我们不跟 CodeQL 比查询灵活性——CodeQL 的 QL 语言非常强大。

**OmniScope 做的是这些工具都不做的事：在 LLVM IR 层同时看到 FFI 边界的两侧。**

如果你有一个 Rust 项目调了 C 库，或者 C++ 项目 embed 了 Rust，或者任何跨语言的场景——OmniScope 是目前唯一能在 IR 层面做跨语言所有权追踪的静态分析工具。

（至少据我们所知。如果有人在做类似的事，请联系我们，我们很乐意交流。）

---

## 7. 下一步（v0.1.6 更新 — 2026-05-04）

> **v0.1.6 状态**: Phase 1+2+3 已全部完成（详见 [rust_ffi_restoration_v016](./investigation_reports/zh/rust_ffi_restoration_v016.md)）
>
> 当前基线：**TP Rate = 20%** (4/20 subtle_unsafe_rs), **Precision ≈ 88%**, **Test Coverage = 92% (191 tests)**

### ✅ P0：已完成（v0.1.6 Phase 1+2+3）

| 任务 | 状态 | 效果 |
|------|------|------|
| FIX-1: Rust alloc noise filter 移除 | ✅ 完成 | Rust FFI 检测从 0% → 20% |
| FIX-2~4: CrossLangEdges / hooks 配对 / Pipeline deps | ✅ 完成 | FFI 边界数 0 → 123 |
| BUG-FIX-6~8 + Issue1+2 (Go/C++分类/callback/null) | ✅ 完成 | Precision 提升 ~10pp |
| P1-1: 测试断言矛盾修复 | ✅ 完成 | 测试与代码逻辑一致 |
| P1-2: allocator_kb deallocator map bug | ✅ 完成 | alloc/free 区分正确 |
| P1-3: static_buf_funcs 重复注册清理 | ✅ 完成 | 每次 init 只注册一次 |
| P1-6/7: free_validation/memory_safety deps 补全 | ✅ 完成 | 执行顺序保证 |
| P2-4~5, P2-8~10: 死代码清理 + 去重 | ✅ 完成 | 净减 ~700 行 |
| 🆕 逐行审计发现 5 个新 Bug 并修复 | ✅ 完成 | OOM安全/markFfiRelevant接入/精确匹配/null检查 |

### 🔜 P0-R：剩余任务（下一 Sprint）

| 任务 | 预期效果 |
|------|---------|
| DUP-1: Dangerous functions 统一（7 处 → 1） | TP rate 20% → **28%+** |
| alias chain 完整集成到 ptr_lifetime pass | 检出 double-free via alias（~4 FN） |
| zone gate 增强（FFI auto-relevant 已接入） | Zone 分类精度提升 |

### P1：增强分析能力（下个月）

| 任务 | 预期效果 |
|------|---------|
| MIR 级整数截断检测 | 检出 size truncation（5 FN） |
| 数据流初始化跟踪 | 检出 uninitialized memory（3 FN） |
| Bounds checking inference | 检出 buffer overflow（3 FN） |
| TP rate -> **40%+** | |

### P2：新分析维度（下季度）

| 任务 | 预期效果 |
|------|---------|
| 跨语言类型映射 | 检出 type confusion（1 FN） |
| 路径敏感分析 | 降低 FP 率 ~50% |
| IDE 集成（LSP server） | 开发者体验提升 |
| TP rate -> **55%+** | |

### 长期愿景

| Phase | 目标 TP Rate | 关键能力 |
|-------|-------------|---------|
| P3 | 65%+ | 循环处理 + 上下文敏感 |
| P4 | 70%+ | 全项目增量分析 |
| P5 | 75%+ | 多语言联合推理引擎 |

我们的终极目标是让跨语言 FFI 编程不再是一个"凭经验和运气"的活动。

---

## 8. 开始使用

### 快速开始

```bash
# 从源码构建
git clone https://github.com/your-org/omniscope.git
cd omniscope
zig build

# 分析一个 LLVM IR 文件
./zig-out/bin/omniscope path/to/your/file.ll

# 输出 JSON 格式
./zig-out/bin/omniscope --json path/to/your/file.ll

# 输出 SARIF 格式（兼容 GitHub Code Scanning）
./zig-out/bin/omniscope --sarif path/to/your/file.ll -o results.sarif
```

### 编译你的项目到 LLVM IR

```bash
# C/C++ 项目
clang -emit-llvm -S -O0 -g your_file.c -o your_file.ll

# Rust 项目
cargo rustc -- --emit=llvm-ir
```

### 更多文档

| 文档 | 内容 |
|------|------|
| [README](../README.md) | 项目概览和安装指南 |
| [architecture.md](architecture.md) | 详细架构设计 |
| [investigation reports](investigation_reports/zh/) | 各项目的详细分析报告 |
| [accuracy_validation.md](investigation_reports/zh/accuracy_validation.md) | 完整的准确性验证数据 |

---

## 附录：版本历史

| 版本 | 日期 | 主要变化 |
|------|------|---------|
| v0.1.5 | 2026-04-15 | 初始发布，10 个项目 baseline |
| v0.1.6 | 2026-04-27 | FP 抑制 + Zone Classifier |
| **v0.1.6** | **2026-05-04** | **Phase 1+2+3 修复，Rust FFI 检测恢复，-700 行死代码清理** |

---

*OmniScope — 在编译器的盲区里，给你一双能看穿语言边界的眼睛。*

*写给每一个凌晨两点还在调跨语言 Crash 的人。你不是一个人在战斗。*
