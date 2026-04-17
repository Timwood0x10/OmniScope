# OmniScope 统一数据流架构开发计划

> 创建日期: 2026-04-16
> 版本: v1.0
> 目标: 基于现有架构设计唯一的、统一的数据流模型

***

## 一、核心设计理念

### 1.1 当前架构分析

**现有组件：**

- `FactStore`: 事实存储（基于四元组：kind, subject, object, context）
- `QueryEngine`: 事实查询引擎
- `Pipeline`: 总调度
- `PassManager`: Pass管理
- 13个Analysis Pass

**存在的问题：**

1. Fact是底层原子事实，缺少高级语义
2. 各Pass直接操作Fact，缺少统一抽象
3. 数据流分散在多个Pass中，难以维护
4. FFI边界检测逻辑不明确

### 1.2 统一数据流设计目标

**唯一的数据流模型：**

```
IR Module → [Data Flow Graph] → [FFI Boundaries] → [Issues]
```

**设计原则：**

1. **单一数据源**: DataFlowGraph作为唯一的中心数据结构
2. **单向流动**: 数据流严格单向，从IR到Issues
3. **明确抽象**: 每层有明确的职责边界
4. **渐进式复杂度**: 先支持基础场景，再扩展
5. 编码风格严格按照./plan/rules.md 

***

## 二、数据结构设计

### 2.1 核心数据模型（简化版）

```zig
/// Issue - 最终输出的最小单元
pub const Issue = struct {
    /// 问题类型
    kind: IssueKind,
    /// 问题描述
    message: []const u8,
    /// 位置信息
    location: Location,
    /// 严重程度
    severity: Severity,
    /// 置信度 (0.0 - 1.0)
    confidence: f32,
    /// 相关的FFI边界（可选）
    ffi_boundary: ?FFIBoundary,

    /// 创建一个新的Issue
    pub fn init(
        kind: IssueKind,
        message: []const u8,
        location: Location,
        severity: Severity,
        confidence: f32,
    ) Issue {
        return .{
            .kind = kind,
            .message = message,
            .location = location,
            .severity = severity,
            .confidence = confidence,
            .ffi_boundary = null,
        };
    }
};

/// Issue类型
pub const IssueKind = enum {
    /// FFI不安全调用
    ffi_unsafe_call,
    /// 未检查的返回值
    unchecked_return,
    /// 类型不匹配
    type_mismatch,
    /// 内存泄漏（跨语言）
    cross_language_leak,
    /// 使用后释放
    use_after_free,
    /// 命令注入
    command_injection,
};

/// 严重程度
pub const Severity = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    critical = 3,
};

/// 位置信息
pub const Location = struct {
    /// 函数名
    function: []const u8,
    /// 文件名（可选）
    file: ?[]const u8,
    /// 行号（可选）
    line: ?u32,
    /// 列号（可选）
    column: ?u32,

    pub fn init(function: []const u8) Location {
        return .{
            .function = function,
            .file = null,
            .line = null,
            .column = null,
        };
    }
};
```

### 2.2 FFI边界模型

```zig
/// FFI边界
pub const FFIBoundary = struct {
    /// 边界ID
    id: u32,
    /// 边界类型
    kind: BoundaryKind,
    /// 调用者语言
    caller_language: Language,
    /// 被调用者语言
    callee_language: Language,
    /// 函数名
    function_name: []const u8,
    /// 位置
    location: Location,

    /// 边界类型
    pub const BoundaryKind = enum {
        /// Rust调用C
        rust_to_c,
        /// Zig调用C
        zig_to_c,
        /// C回调到Rust
        c_to_rust,
        /// 未知外部调用
        external_unknown,
    };

    /// 语言类型
    pub const Language = enum {
        c,
        rust,
        zig,
        unknown,
    };
};
```

### 2.3 统一数据流图

```zig
/// 统一数据流图（基于Fact Store，提供高级抽象）
pub const DataFlowGraph = struct {
    allocator: Allocator,
    fact_store: *FactStore,
    query_engine: *QueryEngine,

    /// 数据流节点
    nodes: std.AutoHashMap(u32, DataNode),
    /// 数据流边
    edges: std.ArrayList(DataEdge),
    /// FFI边界
    ffi_boundaries: std.ArrayList(FFIBoundary),
    /// 检测到的问题
    issues: std.ArrayList(Issue),

    /// 数据流节点
    pub const DataNode = struct {
        id: u32,
        value_type: ValueType,
        is_tainted: bool,
        location: Location,
        taint_source: ?u32,
    };

    /// 数据流边
    pub const DataEdge = struct {
        from: u32,
        to: u32,
        edge_type: EdgeType,
        via_function: ?[]const u8,
    };

    /// 值类型
    pub const ValueType = enum {
        pointer,
        integer,
        struct_,
        array,
        function,
        unknown,
    };

    /// 边类型
    pub const EdgeType = enum {
        /// 直接赋值
        direct,
        /// 函数调用参数
        call_arg,
        /// 函数返回值
        call_ret,
        /// 存储操作
        store,
        /// 加载操作
        load,
        /// FFI边界
        ffi_boundary,
    };

    /// 创建数据流图
    pub fn init(allocator: Allocator, fact_store: *FactStore, query_engine: *QueryEngine) DataFlowGraph {
        return .{
            .allocator = allocator,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .nodes = std.AutoHashMap(u32, DataNode).init(allocator),
            .edges = std.ArrayList(DataEdge).init(allocator),
            .ffi_boundaries = std.ArrayList(FFIBoundary).init(allocator),
            .issues = std.ArrayList(Issue).init(allocator),
        };
    }

    /// 销毁数据流图
    pub fn deinit(self: *DataFlowGraph) void {
        self.nodes.deinit();
        self.edges.deinit();
        self.ffi_boundaries.deinit();
        self.issues.deinit();
    }

    /// 添加节点
    pub fn addNode(self: *DataFlowGraph, node: DataNode) !void {
        try self.nodes.put(node.id, node);
    }

    /// 添加边
    pub fn addEdge(self: *DataFlowGraph, edge: DataEdge) !void {
        try self.edges.append(edge);
    }

    /// 添加FFI边界
    pub fn addFFIBoundary(self: *DataFlowGraph, boundary: FFIBoundary) !void {
        try self.ffi_boundaries.append(boundary);
    }

    /// 添加问题
    pub fn addIssue(self: *DataFlowGraph, issue: Issue) !void {
        try self.issues.append(issue);
    }
};
```

***

## 三、统一数据流架构

### 3.1 架构层次

```
┌─────────────────────────────────────────────────────────────┐
│                     输入层 (Input)                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  IR File     │  │  Config      │  │  Rules       │      │
│  │  .bc / .ll   │  │  Options     │  │  Custom      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  加载层 (Loader)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ IR Loader    │  │  IR View     │  │  Symbol Table│      │
│  │  Parse LLVM  │  │  Abstract    │  │  Functions   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              数据流构建层 (Data Flow Construction)          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ CFG Pass     │  │  DFG Pass    │  │  Alias Pass  │      │
│  │  控制流      │  │  数据流      │  │  别名分析    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Fact Store (Central Data Store)             │   │
│  │  cfg_edge | dfg_edge | alias_may | taint | ...      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              数据流分析层 (Data Flow Analysis)              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           DataFlowGraph (Unified Model)             │   │
│  │  nodes: DataNode[] | edges: DataEdge[]             │   │
│  │  ffi_boundaries: FFIBoundary[]                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ FFI Boundary │  │  Taint Prop. │  │  Sink Detect │      │
│  │  Pass        │  │  Pass        │  │  Pass        │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               问题检测层 (Issue Detection)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Return Check │  │  Type Match  │  │  Vuln Detect │      │
│  │  Pass        │  │  Pass        │  │  Pass        │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Issues: Issue[]                            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 输出层 (Output)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  JSON Output │  │  SARIF       │  │  CLI Display │      │
│  │  (Primary)   │  │  (Future)    │  │  (Debug)     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 数据流路径

**唯一的数据流路径：**

```
1. IR Loader → 加载LLVM IR
2. Foundation Passes → 构建基础事实（CFG, DFG, Alias）
3. Fact Store → 存储所有事实
4. DataFlowGraph → 基于Fact Store构建高级抽象
5. Analysis Passes → 分析数据流，填充FFI边界和Issues
6. Output → 生成JSON/SARIF输出
```

**关键原则：**

- 所有Pass都通过FactStore通信
- DataFlowGraph是唯一的高级抽象
- Issues是唯一的输出格式
- 严格单向流动，无反向依赖

***

## 四、模块集成方案

### 4.1 目录结构调整

```
src/
├── pipeline/
│   ├── pipeline.zig          # 总调度（保持不变）
│   └── loader.zig            # IR加载（保持不变）
├── fact/
│   ├── fact.zig              # Fact定义（保持不变）
│   ├── store.zig             # Fact存储（保持不变）
│   └── query.zig             # Fact查询（保持不变）
├── dataflow/
│   ├── graph.zig             # DataFlowGraph（新建）
│   ├── node.zig              # DataNode（新建）
│   └── edge.zig              # DataEdge（新建）
├── analysis/
│   ├── foundation/
│   │   ├── cfg.zig           # CFG Pass（保持）
│   │   └── dfg.zig           # DFG Pass（保持）
│   ├── ffi/
│   │   ├── boundary.zig      # FFI边界检测（重构）
│   │   └── type_check.zig    # 类型检查（新建）
│   ├── taint/
│   │   ├── propagation.zig   # 污点传播（重构）
│   │   └── sink.zig          # 汇点检测（重构）
│   └── issue/
│       ├── return_check.zig  # 返回值检查（新建）
│       └── detector.zig      # 问题检测（新建）
├── diag/
│   ├── issue.zig             # Issue定义（新建）
│   ├── location.zig          # Location定义（新建）
│   └── aggregator.zig        # 问题聚合（重构）
├── output/
│   ├── json.zig              # JSON输出（新建）
│   └── formatter.zig         # 格式化（新建）
└── main.zig                  # 入口（重构）
```

### 4.2 模块间接口

**Pipeline → Foundation Passes:**

```zig
// Pipeline 调用基础Pass
try pipeline.pass_manager.run(&ctx, &diag);

// Pass写入Fact到FactStore
try ctx.fact_store.insert(Fact.init(.cfg_edge, from_bb, to_bb, func_id));
```

**Foundation Passes → DataFlowGraph:**

```zig
// DataFlowGraph从FactStore构建
var dfg = try DataFlowGraph.init(allocator, fact_store, query_engine);

// 读取CFG边构建控制流
const cfg_edges = try query_engine.query(.cfg_edge, ...);
for (cfg_edges) |edge| {
    // 构建DataFlowGraph节点
}
```

**Analysis Passes → Issues:**

```zig
// Analysis Pass填充DataFlowGraph
// FFI边界检测
try dfg.addFFIBoundary(FFIBoundary{
    .id = next_id,
    .kind = .rust_to_c,
    .caller_language = .rust,
    .callee_language = .c,
    .function_name = "dangerous_func",
    .location = Location.init("main"),
});

// 问题检测
try dfg.addIssue(Issue{
    .kind = .ffi_unsafe_call,
    .message = "Call to external function without safety validation",
    .location = Location.init("main"),
    .severity = .high,
    .confidence = 0.85,
});
```

**Output → JSON:**

```zig
// 从DataFlowGraph生成JSON
const issues = dfg.issues.items;
const json = try formatJSON(allocator, issues);
```

***

## 五、开发计划（6周）

### Week 1: 基础架构

**目标：建立统一数据流框架**

- [ ] Day 1-2: 实现核心数据结构
  - [ ] `src/diag/issue.zig` - Issue, IssueKind, Severity
  - [ ] `src/diag/location.zig` - Location
  - [ ] `src/dataflow/graph.zig` - DataFlowGraph基础结构
  - [ ] `src/dataflow/node.zig` - DataNode
  - [ ] `src/dataflow/edge.zig` - DataEdge
- [ ] Day 3-4: 重构Pipeline
  - [ ] 修改 `src/pipeline/pipeline.zig` 集成DataFlowGraph
  - [ ] 更新PassContext支持DataFlowGraph
  - [ ] 确保FactStore → DataFlowGraph流程
- [ ] Day 5: 单元测试
  - [ ] DataFlowGraph基本操作测试
  - [ ] Issue/Location测试
  - [ ] Pipeline集成测试

### Week 2: FFI边界检测

**目标：实现FFI边界识别（核心功能）**

- [ ] Day 1-2: FFI边界Pass
  - [ ] `src/analysis/ffi/boundary.zig` - FFI边界检测
  - [ ] 语言识别（基于命名约定）
  - [ ] FFI边界标记
- [ ] Day 3: 数据流集成
  - [ ] 将FFI边界写入DataFlowGraph
  - [ ] 测试FFI边界检测准确性
- [ ] Day 4-5: Demo验证
  - [ ] 创建简单的FFI demo
  - [ ] 验证FFI边界输出

### Week 3: 返回值检查

**目标：实现未检查返回值检测（高价值功能）**

- [ ] Day 1-2: 返回值检查Pass
  - [ ] `src/analysis/issue/return_check.zig`
  - [ ] 识别危险函数调用（malloc, open等）
  - [ ] 检测返回值是否被检查
- [ ] Day 3: 数据流集成
  - [ ] 将返回值检查结果写入DataFlowGraph.issues
- [ ] Day 4-5: 测试和优化
  - [ ] 测试各种返回值检查场景
  - [ ] 优化误报率

### Week 4: 污点传播（简化版）

**目标：实现基础污点传播**

- [ ] Day 1-2: 污点传播Pass
  - [ ] 重构 `src/analysis/taint/propagation.zig`
  - [ ] 简化污点传播逻辑（只做函数级）
  - [ ] 标记污点节点
- [ ] Day 3: 汇点检测
  - [ ] 重构 `src/analysis/taint/sink.zig`
  - [ ] 识别危险汇点（system, exec等）
  - [ ] 检测污点路径
- [ ] Day 4-5: 集成测试
  - [ ] 测试污点传播准确性
  - [ ] 验证路径检测

### Week 5: JSON输出

**目标：实现结构化输出**

- [ ] Day 1-2: JSON输出模块
  - [ ] `src/output/json.zig` - JSON格式化
  - [ ] 从DataFlowGraph生成JSON
  - [ ] 输出格式验证
- [ ] Day 3-4: 完整流程测试
  - [ ] 端到端测试（IR → JSON）
  - [ ] Demo验证
  - [ ] 性能测试
- [ ] Day 5: CLI完善
  - [ ] 更新 `src/main.zig`
  - [ ] 命令行参数
  - [ ] 帮助信息

### Week 6: 优化和文档

**目标：打磨和完善**

- [ ] Day 1-2: 性能优化
  - [ ] DataFlowGraph优化
  - [ ] 内存使用优化
  - [ ] 并行化处理
- [ ] Day 3-4: 测试完善
  - [ ] 单元测试覆盖率≥85%
  - [ ] 集成测试
  - [ ] 边界测试
- [ ] Day 5: 文档
  - [ ] API文档
  - [ ] 用户手册
  - [ ] Demo说明

***

## 六、关键技术决策

### 6.1 为什么基于FactStore？

**优点：**

- 已有成熟的实现
- 灵活的事实存储和查询
- 解耦各Pass

**缺点：**

- 需要额外的抽象层
- 性能有额外开销

**结论：** 保留FactStore作为底层，在其上构建DataFlowGraph作为高级抽象。

### 6.2 DataFlowGraph vs 多个Pass

**决策：** 使用单一DataFlowGraph作为中心数据结构。

**理由：**

- 统一数据流，避免分散
- 简化调试和维护
- 易于扩展新功能

### 6.3 简化污点传播

**当前状态：** 有完整的污点传播系统（taint.zig, taint\_propagation.zig, taint\_state.zig）

**简化方案：**

- 只做函数级污点传播
- 使用简单的污点标记（tainted/not tainted）
- 路径追踪限制深度（最大64步）

**理由：**

- 精确污点传播过于复杂
- 函数级足以检测大部分FFI问题
- 可以逐步增强

### 6.4 渐进式实现

**策略：**

1. 先实现最小功能集（FFI边界 + 返回值检查）
2. 逐步添加高级功能（污点传播、类型检查）
3. 持续优化和重构

**好处：**

- 快速产出价值
- 降低实现风险
- 易于调整方向

***

## 七、验证标准

### 7.1 功能验证

**Week 1:**

- [ ] `zig build` 编译成功
- [ ] DataFlowGraph基础测试通过

**Week 2:**

- [ ] FFI边界检测准确率≥90%
- [ ] Demo输出正确

**Week 3:**

- [ ] 返回值检查准确率≥85%
- [ ] 误报率≤15%

**Week 4:**

- [ ] 污点传播检测基本路径
- [ ] 无崩溃或无限循环

**Week 5:**

- [ ] JSON输出符合规范
- [ ] 端到端测试通过

**Week 6:**

- [ ] 单元测试覆盖率≥85%
- [ ] 文档完善

### 7.2 质量标准

- 编码规范：严格遵循 `plan/rules.md`
- 代码审查：所有代码需经过审查
- 测试覆盖：≥85%
- 性能：中型项目分析时间≤30s
- 内存：≤2GB

***

## 八、风险评估

### 8.1 技术风险

| 风险            | 可能性 | 影响 | 缓解措施        |
| ------------- | --- | -- | ----------- |
| FactStore性能瓶颈 | 中   | 高  | 增加缓存、优化查询   |
| FFI边界识别不准     | 高   | 中  | 支持用户配置规则    |
| 污点传播复杂度爆炸     | 中   | 高  | 限制传播深度、简化逻辑 |
| 集成现有架构困难      | 中   | 中  | 逐步迁移、保持兼容   |

### 8.2 项目风险

| 风险     | 可能性 | 影响 | 缓解措施          |
| ------ | --- | -- | ------------- |
| 开发周期延长 | 中   | 中  | 严格按里程碑执行      |
| 范围蔓延   | 高   | 高  | 严格控制范围、专注核心功能 |
| 质量不达标  | 低   | 高  | 持续测试、代码审查     |

***

## 九、成功标准

**6周后的交付物：**

1. ✅ 可工作的静态分析工具
   ```
   ./zig-out/bin/OmniScope demo.bc
   → 输出JSON格式的Issues
   ```
2. ✅ 3个核心Pass
   - FFI边界检测
   - 返回值检查
   - 基础污点传播
3. ✅ 统一的数据流架构
   - DataFlowGraph作为中心数据结构
   - 所有Pass通过FactStore通信
   - Issues作为唯一输出格式
4. ✅ 完整的Demo
   - Rust + C FFI演示
   - 多个场景测试
5. ✅ 文档
   - API文档
   - 用户手册
   - 开发文档

***

## 十、下一步行动

**立即执行：**

1. 创建 `src/dataflow/` 目录
2. 创建 `src/diag/issue.zig`
3. 创建 `src/analysis/ffi/boundary.zig`
4. 开始Week 1任务

**持续跟踪：**

- 每周进度review
- 风险评估和调整
- 质量检查

***

*本计划将根据开发进度动态调整*
