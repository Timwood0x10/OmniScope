Zig 这边做一个**真正通用、生产级的代码检测框架**，参考 memscope-rs 的模块化引擎思路，但面向 LLVM 全语言生态。让我给你出一套完整的架构方案。好，下面分三张图来完整呈现这套架构——先看整体分层，再看两个最核心的子系统。




**图一：整体分层架构（自顶向下的数据流）**

![](./llvmscope_overall_architecture.svg)


**图二：Pass Manager 内部调度机制**——这是参考 memscope-rs 模块化引擎最直接的对应物，所有检测逻辑都在这里编排。**图三：运行时管道——从插桩到事件消费**---
![](./llvmscope_pass_manager.svg)

## 完整架构文字方案

### 项目命名与定位

建议命名 **LLVMScope**——对标 memscope-rs 的命名风格，清晰传达"LLVM 层面的通用 scope 工具"。定位是：**面向所有 LLVM-target 语言的静态+运行时双模式代码检测框架，以 Zig 为核心实现，以 plugin ABI 为扩展点。**

---

### 目录结构设计

参考 memscope-rs 的引擎分层思路，每个子系统独立目录，职责边界清晰：

```
llvmscope/
├── build.zig
├── build.zig.zon
│
├── src/
│   ├── main.zig                  # CLI 入口
│   ├── lib.zig                   # 公共 API 出口（library 模式）
│   │
│   ├── ir/                       # Layer 1: IR 层
│   │   ├── loader.zig            # bitcode 加载，llvm-c bindings
│   │   ├── module.zig            # Module/Function/BB/Inst 抽象
│   │   ├── debug_info.zig        # DWARF/DILocation 解析
│   │   └── cache.zig             # 增量分析缓存
│   │
│   ├── engine/                   # Layer 2: 核心引擎
│   │   ├── pass_manager.zig      # comptime pass 注册 + DAG 调度
│   │   ├── pass_context.zig      # 传给每个 pass 的只读上下文
│   │   ├── scheduler.zig         # 并行化调度器（tier 分组）
│   │   └── config.zig            # 全局配置结构
│   │
│   ├── static/                   # Layer 3a: 静态分析 passes
│   │   ├── cfg_builder.zig       # 控制流图构建
│   │   ├── dfg_builder.zig       # 数据流图 + SSA
│   │   ├── alias.zig             # Anderson-style alias analysis
│   │   ├── type_state.zig        # 资源生命周期状态机
│   │   ├── lock_order.zig        # 锁顺序图 + ABBA 检测
│   │   ├── taint.zig             # 污点传播
│   │   └── invariant.zig         # 循环不变量检查
│   │
│   ├── runtime/                  # Layer 3b: 运行时子系统
│   │   ├── instrumentor.zig      # IR 插桩 pass（产出含 probe 的 .bc）
│   │   ├── rt_lib/               # libllvmscope_rt 源码
│   │   │   ├── probes.zig        # probe stub 实现
│   │   │   ├── ring_buffer.zig   # lock-free SPSC ring buffer
│   │   │   └── shadow_mem.zig    # shadow memory 表
│   │   ├── consumer.zig          # 外部进程事件消费者
│   │   ├── wait_for_graph.zig    # 死锁检测
│   │   ├── data_race.zig         # 数据竞争检测
│   │   ├── async_tracer.zig      # async task 追踪
│   │   └── correlator.zig        # 事件关联 + timeline 重建
│   │
│   ├── plugin/                   # Layer 4: 插件系统
│   │   ├── host.zig              # dlopen 加载 + C ABI 桥接
│   │   ├── interface.zig         # 插件接口定义（C-compatible）
│   │   └── sandbox.zig           # 插件隔离（capability 限制）
│   │
│   ├── diagnostic/               # 诊断总线
│   │   ├── types.zig             # Diagnostic, Severity, Location
│   │   ├── aggregator.zig        # 去重、排序、跨 pass 关联
│   │   └── suppression.zig       # 抑制规则 (.llvmscope.toml)
│   │
│   └── output/                   # Layer 5: 输出适配器
│       ├── lsp.zig               # LSP server (jsonrpc)
│       ├── sarif.zig             # SARIF 2.1 output
│       ├── json.zig              # 机器可读 JSON
│       ├── html.zig              # HTML dashboard
│       └── cli.zig               # 终端输出，颜色+位置
│
├── plugin-sdk/                   # 插件开发 SDK（独立发布）
│   ├── include/llvmscope.h       # C 头文件（跨语言插件）
│   └── zig/                      # Zig 插件辅助库
│
└── tests/
    ├── static/                   # 静态检测测试用例
    ├── runtime/                  # 运行时检测测试用例
    └── plugins/                  # 插件加载测试
```

---

### 核心接口设计（关键代码结构）

**Pass 接口**——参考 memscope-rs 的引擎 trait 思路，用 Zig comptime 实现零开销：

```zig
// src/engine/pass_manager.zig

pub const PassKind = enum { foundation, analysis, plugin };

pub fn Pass(comptime T: type) type {
    // comptime 验证 T 满足接口
    comptime {
        if (!@hasDecl(T, "name"))     @compileError("Pass must have .name");
        if (!@hasDecl(T, "kind"))     @compileError("Pass must have .kind");
        if (!@hasDecl(T, "deps"))     @compileError("Pass must have .deps []const []const u8");
        if (!@hasDecl(T, "run"))      @compileError("Pass must have .run fn");
    }
    return T;
}

// 使用示例
pub const LockOrderPass = Pass(struct {
    pub const name = "lock-order";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "alias" };

    pub fn run(ctx: *const PassContext, diag: *DiagnosticWriter) !void {
        // ctx 是只读 IR view，diag 是唯一写出点
        var graph = LockGraph.init(ctx.allocator);
        defer graph.deinit();
        try buildLockGraph(ctx, &graph);
        try graph.detectCycles(diag);
    }
});
```

**Plugin C ABI**——让 Rust、C、其他语言都可以写插件：

```c
// plugin-sdk/include/llvmscope.h

typedef struct LsPassContext LsPassContext;
typedef struct LsDiagWriter  LsDiagWriter;

typedef struct {
    const char* name;      // null-terminated
    const char* kind;      // "analysis" | "foundation"
    const char** deps;     // null-terminated array
    size_t       deps_len;
    int (*run)(const LsPassContext* ctx, LsDiagWriter* diag);
} LsPluginDescriptor;

// 每个插件 .so 导出这个符号
__attribute__((visibility("default")))
const LsPluginDescriptor* ls_plugin_descriptor(void);
```

**Runtime Event Schema**——借鉴 memscope-rs 的 EventStore 设计：

```zig
// src/runtime/rt_lib/probes.zig

pub const EventTag = enum(u8) {
    alloc, free, lock_acquire, lock_release,
    task_spawn, task_complete, mem_read, mem_write,
};

pub const Event = extern struct {
    tag:       EventTag,
    thread_id: u32,
    timestamp: u64,          // rdtsc
    ptr:       u64,          // 相关地址
    size:      u32,          // 对 alloc/free 有意义
    call_site: u32,          // 压缩的 IR location ID
};

// lock-free SPSC push（从 probe stub 调用，必须极轻量）
pub fn push(ev: Event) void {
    const slot = ring.head.fetchAdd(1, .monotonic) & MASK;
    ring.buf[slot] = ev;
    ring.committed.fetchAdd(1, .release);
}
```

---

### 关键设计决策说明

**为什么 Pass 用 comptime 而不是 interface/vtable？**
memscope-rs 最终走向了多引擎后端，但引擎间切换有运行时分派开销。LLVMScope 的 pass 数量固定在编译期已知，comptime 让编译器把整个 pass 调用链内联，分析工具自身的开销降到最低——用 Zig 做工具的核心优势就在这里。

**插件为什么走 C ABI + dlopen 而不是 comptime？**
内置 pass 走 comptime，追求极限性能。用户插件数量不可预测，dlopen 是唯一的运行时扩展点。C ABI 保证插件可以用任何语言写（Rust、Go、Python via cffi 都行），这正是"通用检测框架"的扩展性承诺。

**为什么 runtime 走 out-of-process 而不是 in-process？**
in-process 分析器（像 memscope-rs 那样）对 Rust 项目是合适的——Rust 的类型系统保证分析器自身不会出问题。但 LLVMScope 要检测 C/C++ 这类不安全语言，目标程序崩了不能带着分析器一起崩。out-of-process 通过 mmap 共享 ring buffer，目标进程只做极轻的 probe stub 写入，分析逻辑完全隔离。

**诊断总线的去重逻辑**：静态分析可能标记"可能死锁"，运行时随后真的触发了——这两个 diagnostic 要被关联成一条，而不是两条噪音。aggregator 按 `(location, kind)` 聚合，并在 runtime 事件到来时升级静态 diagnostic 的置信度。这是比 memscope-rs 单一分析路径更复杂的地方，但也是双模式检测的核心价值所在。

---

### 开发路线图建议

第一阶段（foundation）：IR loader + CFG/DFG builder + CLI + SARIF 输出。能在 Rust/C 项目上跑起来出报告，就是可用状态。

第二阶段（static depth）：alias analysis + type-state + lock ordering。这三个 pass 覆盖了绝大多数生产级静态检测需求。

第三阶段（runtime）：instrumentor pass + libllvmscope_rt + wait-for graph。先做死锁检测，这是最有差异化价值的能力。

第四阶段（ecosystem）：plugin SDK 发布 + LSP server + VS Code extension。让社区能贡献语言专属规则包。