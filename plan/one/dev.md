# OmniScope 开发计划 (Development Plan)

本文档提供详细的开发任务清单，精确到结构体设计、字段定义和实现细节。

---

## 📋 任务优先级

- **P0 (Critical)**: 核心基础设施，必须优先完成
- **P1 (High)**: 主要功能实现
- **P2 (Medium)**: 次要功能和优化
- **P3 (Low)**: 可选功能和插件系统

---

## 🔧 Phase 1: 核心基础设施 (P0)

### Task 1.1: IR Loader 实现

**文件**: `src/engine/loader.zig`

**目标**: 加载 LLVM IR (.bc) 文件并创建 IR View

**数据结构**:

```zig
/// LLVM IR 加载器
pub const IRLoader = struct {
    allocator: Allocator,
    llvm_ctx: ContextRef,
    module: ?ModuleRef,

    /// 加载 .bc 文件
    pub fn loadFile(allocator: Allocator, path: []const u8) !IRLoader;

    /// 获取模块引用
    pub fn getModule(self: *IRLoader) ?ModuleRef;

    /// 迭代所有函数
    pub fn iterateFunctions(self: *IRLoader, callback: fn (FunctionRef) anyerror!void) !void;

    /// 释放资源
    pub fn deinit(self: *IRLoader) void;
};
```

**关键函数签名**:

```zig
// 从文件路径加载 LLVM IR
pub fn loadFile(allocator: Allocator, path: []const u8) !IRLoader {
    // 1. 创建 LLVM Context
    // 2. 创建 Memory Buffer
    // 3. 解析 IR 到 Module
    // 4. 返回 IRLoader
}

// 获取指定名称的函数
pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef {
    // 1. 遍历模块中的所有函数
    // 2. 比较函数名
    // 3. 返回匹配的 FunctionRef
}
```

**依赖**: `src/ir/llvm_c.zig`, `src/ir/view.zig`

**测试要求**:
- 测试加载简单的 LLVM IR 文件
- 测试获取函数列表
- 测试错误处理（文件不存在、无效 IR）

---

### Task 1.2: Pass Manager 依赖解析

**文件**: `src/pass/manager.zig` (修改)

**目标**: 实现拓扑排序和依赖解析

**数据结构扩展**:

```zig
pub const PassManager = struct {
    allocator: Allocator,
    passes: std.ArrayList(PassEntry),
    // 新增字段
    pass_map: std.StringHashMap(usize), // name -> index
    resolved_order: ?[]usize,

    const PassEntry = struct {
        name: []const u8,
        kind: PassKind,
        deps: []const []const u8,
        run_fn: *const fn (ctx: *PassContext, diag: *DiagnosticWriter) anyerror!void,
    };

    // 新增方法
    pub fn resolveDependencies(self: *PassManager) !void;
    pub fn getExecutionOrder(self: *PassManager) []const []const u8;
};
```

**依赖解析算法**:

```zig
pub fn resolveDependencies(self: *PassManager) !void {
    // 使用 Kahn's 算法进行拓扑排序
    // 1. 计算每个 pass 的入度
    // 2. 找到入度为 0 的 pass
    // 3. 添加到执行顺序
    // 4. 减少邻居的入度
    // 5. 重复直到所有 pass 被处理
    // 6. 如果有环，返回错误
}
```

**测试要求**:
- 测试简单依赖链 A -> B -> C
- 测试复杂依赖图
- 测试循环依赖检测
- 测试无依赖情况

---

### Task 1.3: PassContext 扩展

**文件**: `src/pass/pass.zig` (修改)

**目标**: 让 Pass 可以访问 IR 和 Fact Store

**数据结构扩展**:

```zig
pub const PassContext = struct {
    allocator: Allocator,
    // 新增字段
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    // ID 分配器
    next_id: std.atomic.Value(u32),

    pub fn getNextId(self: *PassContext) u32;
    pub fn setModule(self: *PassContext, module: ModuleRef) void;
};
```

---

## 🧩 Phase 2: Foundation Passes 实现 (P0)

### Task 2.1: CFG Pass 完整实现

**文件**: `src/pass/foundation/cfg.zig` (修改)

**目标**: 构建实际的控制流图

**数据结构**:

```zig
pub const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    ctx: *PassContext,
    diag: *DiagnosticWriter,

    // 需要扩展 LLVM-C 绑定
    pub fn run(self: *CFGPass) !void {
        // 1. 遍历所有函数
        // 2. 对每个函数，遍历基本块
        // 3. 分析每个基本块的终止指令
        // 4. 发出 cfg_edge facts
    }

    fn analyzeBasicBlock(self: *CFGPass, bb: BasicBlockRef, bb_id: u32, func_id: u32) !void {
        // 获取终止指令
        // 根据指令类型确定后继
        // 发出 cfg_edge facts
    }
};
```

**需要的 LLVM-C 绑定** (添加到 `src/ir/llvm_c.zig`):

```zig
// 基本块操作
extern fn LLVMGetFirstBasicBlock(fn_val: LLVMValueRef) LLVMBasicBlockRef;
extern fn LLVMGetLastBasicBlock(fn_val: LLVMValueRef) LLVMBasicBlockRef;
extern fn LLVMGetNextBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
extern fn LLVMGetPreviousBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;

// 指令操作
extern fn LLVMGetFirstInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
extern fn LLVMGetLastInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
extern fn LLVMGetNextInstruction(inst: LLVMValueRef) LLVMValueRef;
extern fn LLVMGetPreviousInstruction(inst: LLVMValueRef) LLVMValueRef;
extern fn LLVMGetBasicBlockTerminator(bb: LLVMBasicBlockRef) LLVMValueRef;

// Branch 操作
extern fn LLVMGetNumSuccessors(term: LLVMValueRef) c_uint;
extern fn LLVMGetSuccessor(term: LLVMValueRef, i: c_uint) LLVMBasicBlockRef;
```

**Fact 格式**:
- `cfg_edge`: subject=source_bb_id, object=target_bb_id, context=function_id

---

### Task 2.2: DFG Pass 完整实现

**文件**: `src/pass/foundation/dfg.zig` (修改)

**目标**: 构建实际的数据流图

**数据结构**:

```zig
pub const DFGPass = struct {
    pub const name = "dfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"cfg"};

    ctx: *PassContext,
    diag: *DiagnosticWriter,

    pub fn run(self: *DFGPass) !void {
        // 1. 遍历所有函数
        // 2. 对每个函数，遍历所有指令
        // 3. 分析指令的操作数
        // 4. 发出 dfg_edge facts
    }

    fn analyzeInstruction(self: *DFGPass, inst: ValueRef, inst_id: u32, func_id: u32) !void {
        // 获取操作数数量
        // 遍历操作数
        // 发出 dfg_edge: operand_id -> inst_id
    }
};
```

**Fact 格式**:
- `dfg_edge`: subject=operand_id, object=inst_id, context=function_id

---

## 🔍 Phase 3: Analysis Passes 实现 (P1)

### Task 3.1: Alias Pass 完整实现

**文件**: `src/pass/analysis/alias.zig` (修改)

**目标**: 基于 TBAA 的别名分析

**数据结构**:

```zig
pub const AliasPass = struct {
    pub const name = "alias";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    // 类型信息缓存
    type_cache: std.AutoHashMap(LLVMTypeRef, u32),

    pub fn run(self: *AliasPass) !void {
        // 1. 收集所有指针值
        // 2. 按类型分组
        // 3. 分析内存操作
        // 4. 发出 alias facts
    }

    fn getTypeId(self: *AliasPass, type_ref: LLVMTypeRef) !u32 {
        // 使用 TBAA 元数据获取类型 ID
        // 如果没有元数据，使用类型指针地址
    }

    fn analyzeMemoryOperation(self: *AliasPass, inst: ValueRef) !void {
        // 检查是否是 load/store
        // 获取指针操作数
        // 确定类型
        // 与其他内存操作比较
    }
};
```

**需要的 LLVM-C 绑定**:

```zig
// 类型操作
extern fn LLVMTypeOf(val: LLVMValueRef) LLVMTypeRef;
extern fn LLVMGetElementType(ptr_type: LLVMTypeRef) LLVMTypeRef;
extern fn LLVMGetPointerAddressSpace(ptr_type: LLVMTypeRef) c_uint;

// 元数据操作
extern fn LLVMGetMDKindIDInContext(ctx: LLVMContextRef, name: [*:0]const u8, slen: c_uint) c_uint;
extern fn LLVMGetMetadata(val: LLVMValueRef, kind_id: c_uint) LLVMMetadataRef;
```

**Fact 格式**:
- `alias_may`: subject=ptr1_id, object=ptr2_id, context=function_id
- `alias_must`: subject=ptr1_id, object=ptr2_id, context=function_id

---

### Task 3.2: Lock Pass 完整实现

**文件**: `src/pass/analysis/lock.zig` (修改)

**目标**: 死锁检测

**数据结构**:

```zig
pub const LockPass = struct {
    pub const name = "lock";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    // 锁图
    lock_graph: LockGraph,

    pub fn run(self: *LockPass) !void {
        // 1. 查找所有锁操作（pthread_mutex_lock/unlock）
        // 2. 构建锁获取图
        // 3. 使用 Tarjan SCC 检测环
        // 4. 发出 lock facts 和警告
    }

    fn isLockOperation(inst: ValueRef) bool {
        // 检查是否是已知的锁函数调用
    }

    fn buildLockGraph(self: *LockPass) !void {
        // 从 cfg_edge 和 alias_may facts 构建锁图
    }

    fn detectDeadlocks(self: *LockPass) ![]DeadlockCandidate {
        // 使用 Tarjan SCC 算法
    }
};

pub const DeadlockCandidate = struct {
    cycle: []u32,  // 锁 ID 的环
    locations: []Location,  // 每个锁的位置
    confidence: f32,
};
```

**Fact 格式**:
- `lock_acquire`: subject=lock_id, object=location_id, context=function_id
- `lock_release`: subject=lock_id, object=location_id, context=function_id

---

### Task 3.3: Taint Pass 完整实现

**文件**: `src/pass/analysis/taint.zig` (修改)

**目标**: 污点分析

**数据结构**:

```zig
pub const TaintPass = struct {
    pub const name = "taint";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    // 污点源和汇配置
    sources: []TaintSource,
    sinks: []TaintSink,

    pub fn run(self: *TaintPass) !void {
        // 1. 识别污点源
        // 2. 通过 DFG 传播污点
        // 3. 检测污点到达汇
        // 4. 发出 taint facts
    }
};

pub const TaintSource = struct {
    function_name: []const u8,
    arg_index: u32,  // 哪个参数被污染
};

pub const TaintSink = struct {
    function_name: []const u8,
    arg_index: u32,
    severity: Severity,
};
```

**Fact 格式**:
- `taint`: subject=source_value_id, object=sink_value_id, context=path_id

---

## 📊 Phase 4: Pipeline 集成 (P0)

### Task 4.1: Pipeline 完整执行流程

**文件**: `src/pipeline/pipeline.zig` (修改)

**目标**: 整合所有组件，实现端到端流程

**数据结构**:

```zig
pub const Pipeline = struct {
    allocator: Allocator,
    // 组件
    loader: IRLoader,
    pass_manager: PassManager,
    fact_store: FactStore,
    query_engine: QueryEngine,
    instrumentation_planner: InstrumentationPlanner,
    diagnostic_aggregator: DiagnosticAggregator,
    // 阶段
    static_stage: StaticStage,
    instrumentation_stage: InstrumentationStage,
    runtime_stage: RuntimeStage,
    merge_stage: MergeStage,

    pub fn init(allocator: Allocator) !Pipeline;
    pub fn loadIR(self: *Pipeline, path: []const u8) !void;
    pub fn runStaticAnalysis(self: *Pipeline) !PipelineResult;
    pub fn runInstrumentation(self: *Pipeline) !PipelineResult;
    pub fn runRuntime(self: *Pipeline) !PipelineResult;
    pub fn runMerge(self: *Pipeline) !PipelineResult;
    pub fn runFullPipeline(self: *Pipeline) !FullPipelineResult;
};
```

**执行流程**:

```zig
pub fn runFullPipeline(self: *Pipeline, ir_path: []const u8) !FullPipelineResult {
    // 1. Load IR
    try self.loadIR(ir_path);

    // 2. Static Analysis
    const static_result = try self.runStaticAnalysis();

    // 3. Instrumentation Planning
    const inst_result = try self.runInstrumentation();

    // 4. Runtime Collection (if instrumented)
    var runtime_result: ?PipelineResult = null;
    if (self.instrumentation_planner.count() > 0) {
        runtime_result = try self.runRuntime();
    }

    // 5. Merge
    const merge_result = try self.runMerge();

    // 6. Generate diagnostics
    return .{
        .static_result = static_result,
        .instrumentation_result = inst_result,
        .runtime_result = runtime_result,
        .merge_result = merge_result,
        .total_time_ns = 0,  // TODO: timing
    };
}

pub const FullPipelineResult = struct {
    static_result: PipelineResult,
    instrumentation_result: PipelineResult,
    runtime_result: ?PipelineResult,
    merge_result: PipelineResult,
    total_time_ns: u64,
};
```

---

## 🖨️ Phase 5: Output 层 (P1)

### Task 5.1: CLI 输出

**文件**: `src/output/cli.zig` (新建)

**目标**: 命令行输出格式

**数据结构**:

```zig
pub const CLIOutput = struct {
    allocator: Allocator,
    color_enabled: bool,
    verbose: bool,

    pub fn printDiagnostics(self: *CLIOutput, diagnostics: []Diagnostic) !void;
    pub fn printSummary(self: *CLIOutput, summary: SummaryReport) !void;
    pub fn printError(self: *CLIOutput, msg: []const u8) void;
    pub fn printWarning(self: *CLIOutput, msg: []const u8) void;
    pub fn printInfo(self: *CLIOutput, msg: []const u8) void;
};
```

---

### Task 5.2: SARIF 输出

**文件**: `src/output/sarif.zig` (新建)

**目标**: SARIF 格式输出（用于 IDE 集成）

**数据结构**:

```zig
pub const SarifOutput = struct {
    allocator: Allocator,
    version: []const u8 = "2.1.0",

    pub fn generate(self: *SarifOutput, diagnostics: []Diagnostic) ![]const u8;
    pub fn writeToFile(self: *SarifOutput, path: []const u8, diagnostics: []Diagnostic) !void;
};

// SARIF 结构（简化版）
pub const SarifLog = struct {
    version: []const u8,
    schema: []const u8,
    runs: []SarifRun,
};

pub const SarifRun = struct {
    tool: SarifTool,
    results: []SarifResult,
};
```

---

### Task 5.3: LSP 输出

**文件**: `src/output/lsp.zig` (新建)

**目标**: LSP 协议支持（用于 VS Code 等编辑器）

**数据结构**:

```zig
pub const LSPDiagnostic = struct {
    range: Range,
    severity: i32,
    code: ?[]const u8,
    source: []const u8 = "OmniScope",
    message: []const u8,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Position = struct {
    line: u32,  // 0-indexed
    character: u32,  // 0-indexed
};

pub const LSPOutput = struct {
    allocator: Allocator,

    pub fn convertDiagnostic(self: *LSPOutput, diag: Diagnostic, file_map: FileMap) !LSPDiagnostic;
};
```

---

## 🔌 Phase 6: Plugin 系统 (P2)

### Task 6.1: Plugin C ABI

**文件**: `src/plugin/abi.zig` (新建)

**目标**: 定义插件接口

**数据结构**:

```zig
/// C ABI 插件接口
pub const LsPlugin = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    
    // 插件生命周期
    init: ?*const fn () ?*anyopaque,
    deinit: ?*const fn (plugin: *anyopaque) void,
    
    // 查询接口
    query: ?*const fn (
        plugin: *anyopaque,
        query: *const LsFactQuery,
        result: *LsQueryResult,
    ) c_int,
    
    // 诊断接口
    report: ?*const fn (
        plugin: *anyopaque,
        diag: *LsDiagnostic,
    ) c_int,
};

/// 查询请求
pub const LsFactQuery = extern struct {
    kind: FactKind,
    subject: u32,
    object: u32,
    context: u32,
};

/// 查询结果
pub const LsQueryResult = extern struct {
    count: u32,
    facts: [*]LsFact,
};

/// Fact (C ABI)
pub const LsFact = extern struct {
    kind: u8,
    subject: u32,
    object: u32,
    context: u32,
};

/// 诊断 (C ABI)
pub const LsDiagnostic = extern struct {
    kind: u16,
    severity: u8,
    loc: u32,
    message: [*:0]const u8,
    confidence: f32,
};
```

**插件加载器**:

```zig
pub const PluginLoader = struct {
    allocator: Allocator,
    plugins: std.ArrayList(LoadedPlugin),

    const LoadedPlugin = struct {
        handle: *anyopaque,  // dlopen handle
        plugin: *LsPlugin,
        plugin_data: ?*anyopaque,
    };

    pub fn load(self: *PluginLoader, path: []const u8) !void;
    pub fn unload(self: *PluginLoader) void;
    pub fn queryAll(self: *PluginLoader, query: LsFactQuery) ![]Diagnostic;
};
```

---

## 📝 Phase 7: 测试和文档 (P1)

### Task 7.1: 集成测试

**文件**: `tests/integration.zig` (新建)

**测试场景**:

```zig
test "full pipeline - simple program" {
    // 1. 加载测试 IR 文件
    // 2. 运行完整 pipeline
    // 3. 验证结果
}

test "deadlock detection - simple cycle" {
    // 测试 A -> B -> A 死锁
}

test "deadlock detection - complex cycle" {
    // 测试复杂死锁场景
}

test "taint analysis - simple flow" {
    // 测试污点传播
}

test "alias analysis - must alias" {
    // 测试必然别名
}

test "alias analysis - may alias" {
    // 测试可能别名
}
```

---

## 🎯 实现顺序（按依赖关系）

1. **Week 1**: Task 1.1, 1.2, 1.3 (基础设施)
2. **Week 2**: Task 2.1, 2.2 (Foundation Passes)
3. **Week 3**: Task 3.1, 3.2, 3.3 (Analysis Passes)
4. **Week 4**: Task 4.1 (Pipeline 集成)
5. **Week 5**: Task 5.1, 5.2, 5.3 (Output 层)
6. **Week 6**: Task 6.1 (Plugin 系统)
7. **Week 7**: Task 7.1 (测试和修复)

---

## ✅ 验收标准

每个 Task 完成后必须满足：

1. **代码质量**:
   - `make check` 显示 0 errors
   - `make fmt` 通过
   - 单元测试覆盖率 > 80%

2. **性能要求**:
   - IR 加载 < 100ms (对于 1MB .bc 文件)
   - CFG Pass < 50ms (对于 1000 函数)
   - Alias Pass < 200ms (对于 1000 函数)
   - Lock Pass < 100ms (对于 1000 函数)

3. **正确性**:
   - 所有单元测试通过
   - 集成测试通过
   - 无内存泄漏

---

## 📊 当前进度

### Phase 1: 核心基础设施 (P0)
- [x] Task 1.1: IR Loader 实现 ✅ (需要修复 LLVM 链接问题)
- [x] Task 1.2: Pass Manager 依赖解析 ✅ (已完成，包括拓扑排序)
- [x] Task 1.3: PassContext 扩展 ✅ (已完成，支持模块、fact store、query engine)

### Phase 2: Foundation Passes 实现 (P0)
- [x] Task 2.1: CFG Pass 完整实现 ✅ (已完成，包括基本块分析和边生成)
- [x] Task 2.2: DFG Pass 完整实现 ✅ (已完成，包括数据流分析和 PHI 节点处理)

### Phase 3: Analysis Passes 实现 (P1)
- [x] Task 3.1: Alias Pass 完整实现 ✅ (已完成，包括 TBAA 和别名分析)
- [x] Task 3.2: Lock Pass 完整实现 ✅ (已完成，包括死锁检测和图构建)
- [x] Task 3.3: Taint Pass 完整实现 ✅ (已完成，包括污点传播和检测)

### Phase 4: Pipeline 集成 (P0)
- [x] Task 4.1: Pipeline 完整执行流程 ✅ (已完成框架实现)
- [x] Task 4.2: Instrumentation Planner 实现 ✅ (已完成，包括优先级系统、热点检测和智能选择)

### Phase 5: Output 层 (P1)
- [x] Task 5.1: CLI 输出 ✅ (已完成，包括彩色输出和格式化)
- [x] Task 5.2: SARIF 输出 ✅ (已完成，包括 JSON 生成和文件写入)
- [x] Task 5.3: LSP 输出 ✅ (已完成，包括位置映射和诊断转换)

### Phase 6: Plugin 系统 (P2)
- [x] Task 6.1: Plugin C ABI ✅ (已完成框架，包括数据结构定义)
- [x] Task 6.2: Plugin Loader 实现 ✅ (已完成动态库加载和查询功能)

### Phase 7: 测试和文档 (P1)
- [x] Task 7.1: 集成测试 ✅ (已完成基础集成测试)
- [x] Task 7.2: 完整端到端测试 ✅ (已完成，包括 6 种语言 IR 测试和 Pipeline 集成)

### Phase 8: 日志和调试系统 (P2)
- [x] Task 8.1: 日志系统 ✅ (src/log/log.zig - 多级别日志、带颜色和时间戳)
- [x] Task 8.2: 调试系统 ✅ (src/log/debug.zig - 断言、panic 上下文、stack trace)
- [x] Task 8.3: 错误系统 ✅ (src/log/error.zig - 统一错误层次结构)

### Phase 9: 编码规范 (P2)
- [x] Task 9.1: 编码规范文档 ✅ (plan/zig_coding_guide.md 已创建)

### 已知问题和待修复
1. ~~**LLVM 链接问题**: build.zig 需要添加 LLVM 库链接配置~~ ✅ 已修复
2. **ArrayList API 兼容性**: 已修复 Zig 0.15.2 的 ArrayList API 调用
3. **PassContext 初始化**: 已修复所有测试中的 PassContext 初始化问题
4. **内存泄漏警告**: PassManager 测试中有少量内存泄漏，需要修复（非关键）

### 编译状态
- ✅ `make check` 显示 0 errors (2026-04-12)
- ✅ `make test` 通过，但有内存泄漏警告 (LLVM 链接已修复)

---

## 🔄 持续优化

- **内存优化**: 使用 Arena Allocator 临时数据
- **SIMD 优化**: Fact Store 查询
- **并行化**: Pass 执行（无依赖的 Pass 可并行）
- **缓存优化**: IR View 避免重复解析

---

## 📚 参考资料

- [LLVM-C API](https://llvm.org/doxygen/group__LLVMC.html)
- [Zig Standard Library](https://ziglang.org/documentation/master/)
- [SARIF Format](https://sarifweb.azurewebsites.net/)
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)