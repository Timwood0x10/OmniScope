# OmniScope API 参考

OmniScope 库函数、类型和模块的完整 API 参考。

## 目录

1. [日志模块](#日志模块)
2. [IR 模块](#ir-模块)
3. [Pass 模块](#pass-模块)
4. [Fact 模块](#fact-模块)
5. [Pipeline 模块](#pipeline-模块)
6. [Engine 模块](#engine-模块)
7. [跨语言分析](#跨语言分析)
8. [错误类型](#错误类型)

---

## 日志模块

### LogLevel

日志级别枚举。

```zig
pub const LogLevel = enum(u3) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};
```

### Config

日志配置。

```zig
pub const Config = struct {
    level: LogLevel = .info,
    enable_colors: bool = true,
    enable_timestamps: bool = true,
    enable_module_prefix: bool = true,
};
```

### 函数

#### `init`

初始化日志系统。

```zig
pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config: Config) void
```

**参数：**
- `allocator`: 日志操作的内存分配器
- `writer`: 日志消息的输出写入器
- `config`: 日志配置

#### `deinit`

清理日志资源。

```zig
pub fn deinit() void
```

#### `debug`

记录调试消息。

```zig
pub fn debug(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

**参数：**
- `module`: 日志前缀的模块名称
- `format`: 格式字符串
- `args`: 格式参数

#### `info`

记录信息消息。

```zig
pub fn info(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `warn`

记录警告消息。

```zig
pub fn warn(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `err`

记录错误消息。

```zig
pub fn err(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `setLevel`

设置当前日志级别。

```zig
pub fn setLevel(level: LogLevel) void
```

#### `getLevel`

获取当前日志级别。

```zig
pub fn getLevel() LogLevel
```

---

## IR 模块

### ContextRef

LLVM 上下文的不透明引用。

```zig
pub const ContextRef = struct {
    raw: *opaque {},
};
```

### ModuleRef

LLVM 模块的不透明引用。

```zig
pub const ModuleRef = struct {
    raw: *opaque {},
};
```

### FunctionRef

LLVM 函数的不透明引用。

```zig
pub const FunctionRef = struct {
    raw: *opaque {},
};
```

### LLVM-C API 绑定

#### 上下文管理

```zig
pub extern fn LLVMContextCreate() LLVMContextRef;
pub extern fn LLVMContextDispose(ctx: LLVMContextRef) void;
```

#### 模块操作

```zig
pub extern fn LLVMParseBitcodeInContext2(
    ctx: LLVMContextRef,
    mem_buf: LLVMMemoryBufferRef,
    out_module: *LLVMModuleRef,
) c_int;

pub extern fn LLVMDisposeModule(module: LLVMModuleRef) void;
```

#### 值操作

```zig
pub extern fn LLVMGetValueName(value: LLVMValueRef) [*:0]const u8;
pub extern fn LLVMGetInstructionOpcode(inst: LLVMValueRef) c_uint;
pub extern fn LLVMGetNextInstruction(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetPreviousInstruction(inst: LLVMValueRef) LLVMValueRef;
```

#### 函数操作

```zig
pub extern fn LLVMGetFirstFunction(module: LLVMModuleRef) LLVMValueRef;
pub extern fn LLVMGetNextFunction(func: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMIsAFunction(val: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMCountBasicBlocks(func_val: LLVMValueRef) c_uint;
```

#### 基本块操作

```zig
pub extern fn LLVMGetFirstBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;
pub extern fn LLVMGetNextBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
pub extern fn LLVMGetFirstInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
```

#### 指令操作

```zig
pub extern fn LLVMGetOperand(inst: LLVMValueRef, index: c_uint) LLVMValueRef;
pub extern fn LLVMGetNumOperands(inst: LLVMValueRef) c_uint;
pub extern fn LLVMIsACallInst(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetCalledValue(call: LLVMValueRef) LLVMValueRef;
```

---

## Pass 模块

### PassKind

Pass 类型枚举。

```zig
pub const PassKind = enum {
    foundation,  // 基础分析 pass
    analysis,    // 高级分析 pass
    plugin,      // 用户定义的插件 pass
};
```

### PassContext

在执行期间传递给每个 pass 的上下文。

```zig
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    next_id: std.atomic.Value(u32),

    /// 创建新的 pass 上下文
    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
    ) PassContext;

    /// 获取唯一 ID（线程安全）
    pub fn getNextId(self: *PassContext) u32;

    /// 设置 IR 模块
    pub fn setModule(self: *PassContext, module: ModuleRef) void;

    /// 检查是否加载了模块
    pub fn hasModule(self: *const PassContext) bool;
};
```

### DiagnosticWriter

Pass 输出的写入器。

```zig
pub const DiagnosticWriter = struct {
    allocator: Allocator,

    pub fn write(self: *DiagnosticWriter, comptime severity: []const u8, comptime format: []const u8, args: anytype) void;
    pub fn info(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void;
    pub fn warn(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void;
    pub fn err(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void;
};
```

### Pass

用于 pass 验证的编译时包装器。

```zig
pub fn Pass(comptime T: type) type;
```

**Pass 类型要求：**
- 必须有 `name: []const u8` 声明
- 必须有 `kind: PassKind` 声明
- 必须有 `deps: []const []const u8` 声明
- 必须有 `run(ctx: *PassContext, diag: *DiagnosticWriter) !void` 函数

---

## Fact 模块

### FactKind

事实类型枚举。

```zig
pub const FactKind = enum {
    cfg_edge,
    dfg_edge,
    alias,
    lock,
    taint,
    ffi_boundary,
    custom,
};
```

### Fact

表示单个事实。

```zig
pub const Fact = struct {
    kind: FactKind,
    subject: u32,
    object: u32,
    context: u32,
};
```

### FactStore

SoA（结构数组）事实存储。

```zig
pub const FactStore = struct {
    kinds: []FactKind,
    subjects: []u32,
    objects: []u32,
    contexts: []u32,

    /// 初始化事实存储
    pub fn init(allocator: Allocator) FactStore;

    /// 清理事实存储
    pub fn deinit(self: *FactStore) void;

    /// 插入事实
    pub fn insert(self: *FactStore, kind: FactKind, subject: u32, object: u32, context: u32) !void;

    /// 按类型查询事实
    pub fn queryByKind(self: *FactStore, kind: FactKind, allocator: Allocator) ![]Fact;

    /// 按主体查询事实
    pub fn queryBySubject(self: *FactStore, subject: u32, allocator: Allocator) ![]Fact;

    /// 按对象查询事实
    pub fn queryByObject(self: *FactStore, object: u32, allocator: Allocator) ![]Fact;

    /// 获取事实数量
    pub fn count(self: *FactStore) usize;
};
```

### QueryEngine

用于查询事实的引擎。

```zig
pub const QueryEngine = struct {
    store: *FactStore,

    /// 初始化查询引擎
    pub fn init(store: *FactStore) QueryEngine;

    /// 按类型查询事实
    pub fn queryByKind(self: *QueryEngine, kind: FactKind, allocator: Allocator) ![]Fact;

    /// 按主体查询事实
    pub fn queryBySubject(self: *QueryEngine, subject: u32, allocator: Allocator) ![]Fact;

    /// 按对象查询事实
    pub fn queryByObject(self: *QueryEngine, object: u32, allocator: Allocator) ![]Fact;

    /// 使用多个条件查询事实
    pub fn query(self: *QueryEngine, criteria: QueryCriteria, allocator: Allocator) ![]Fact;
};
```

### QueryCriteria

事实查询的条件。

```zig
pub const QueryCriteria = struct {
    kind: ?FactKind = null,
    subject: ?u32 = null,
    object: ?u32 = null,
    context: ?u32 = null,
};
```

---

## Pipeline 模块

### StageKind

Pipeline 阶段类型枚举。

```zig
pub const StageKind = enum {
    static,          // 静态分析阶段
    instrumentation,  // 插桩阶段
    runtime,         // 运行时监控阶段
    merge,           // 合并阶段
};
```

### StageContext

Pipeline 阶段的上下文。

```zig
pub const StageContext = struct {
    allocator: Allocator,
    config: *const Config,
    fact_store: *FactStore,
    query_engine: *QueryEngine,

    /// 初始化阶段上下文
    pub fn init(
        allocator: Allocator,
        config: *const Config,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
    ) StageContext;
};
```

### StageResult

Pipeline 阶段执行的结果。

```zig
pub const StageResult = union(enum) {
    success,
    failed: []const u8,
};
```

### Stage

Pipeline 阶段的基础接口。

```zig
pub const Stage = struct {
    kind: StageKind,

    /// 运行阶段
    pub fn run(self: *Stage, ctx: *StageContext) StageResult;
};
```

### Pipeline

主分析 pipeline。

```zig
pub const Pipeline = struct {
    allocator: Allocator,
    stages: std.ArrayList(*Stage),
    fact_store: FactStore,
    query_engine: QueryEngine,

    /// 初始化 pipeline
    pub fn init(allocator: Allocator) Pipeline;

    /// 清理 pipeline
    pub fn deinit(self: *Pipeline) void;

    /// 向 pipeline 添加阶段
    pub fn addStage(self: *Pipeline, stage: *Stage) !void;

    /// 运行 pipeline
    pub fn run(self: *Pipeline) !PipelineResult;

    /// 获取事实存储
    pub fn getFactStore(self: *Pipeline) *FactStore;

    /// 获取查询引擎
    pub fn getQueryEngine(self: *Pipeline) *QueryEngine;
};
```

### PipelineResult

Pipeline 执行的结果。

```zig
pub const PipelineResult = struct {
    success: bool,
    error_message: ?[]const u8,
    diagnostics: []Diagnostic,
};
```

---

## Engine 模块

### LoaderError

IR 加载器的错误集。

```zig
pub const LoaderError = error{
    FileNotFound,
    InvalidIR,
    LLVMContextCreationFailed,
    ModuleParseFailed,
    OutOfMemory,
};
```

### IRLoader

LLVM IR 加载器。

```zig
pub const IRLoader = struct {
    allocator: Allocator,
    llvm_ctx: ContextRef,
    module: ?ModuleRef,
    alive: bool = false,

    /// 从磁盘加载 .bc 文件
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader;

    /// 获取模块引用
    pub fn getModule(self: *IRLoader) ?ModuleRef;

    /// 获取 LLVM 上下文
    pub fn getContext(self: *IRLoader) ContextRef;

    /// 遍历所有函数
    pub fn iterateFunctions(
        self: *IRLoader,
        callback: fn (FunctionRef) anyerror!void,
    ) !void;

    /// 按名称获取函数
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef;

    /// 获取函数数量
    pub fn getFunctionCount(self: *IRLoader) usize;

    /// 检查是否加载了模块
    pub fn hasModule(self: *IRLoader) bool;

    /// 清理资源
    pub fn deinit(self: *IRLoader) void;
};
```

---

## 跨语言分析

### FunctionKind

函数类型枚举。

```zig
pub const FunctionKind = enum {
    internal,
    libc,
    external_unknown,
};
```

### Node

表示调用图中的节点。

```zig
pub const Node = struct {
    id: u32,
    name: []const u8,
    func_ref: llvm.LLVMValueRef,
    kind: FunctionKind,
    isExternal: bool,
    isTainted: bool,
    taintedBy: ?u32,
};
```

### Edge

表示调用图中的边。

```zig
pub const Edge = struct {
    caller: u32,
    callee: u32,
};
```

### CallGraphPass

从 LLVM IR 构建调用图。

```zig
pub const CallGraphPass = struct {
    pub const name = "call-graph";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void;
};
```

### TaintPropagationPass

执行前向污点传播。

```zig
pub const TaintPropagationPass = struct {
    pub const name = "taint-propagation";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) TaintError!void;
};
```

### FFIBoundaryPass

标记跨语言转换。

```zig
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void;
};
```

### SinkTracerPass

追踪污点数据流到汇点。

```zig
pub const SinkTracerPass = struct {
    pub const name = "sink-tracer";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FlowPathError!void;
};
```

---

## 错误类型

### Error

基础错误集。

```zig
pub const Error = error{
    OutOfMemory,
    InvalidInput,
    InvalidState,
};
```

### IRLoadError

IR 加载错误。

```zig
pub const IRLoadError = error{
    FileNotFound,
    InvalidIR,
    LLVMContextCreationFailed,
    ModuleParseFailed,
};
```

### IRViewError

IR 视图错误。

```zig
pub const IRViewError = error{
    InvalidValue,
    InvalidType,
    NullPointer,
};
```

### PassError

Pass 执行错误。

```zig
pub const PassError = error{
    PassNotFound,
    DependencyNotMet,
    PassFailed,
};
```

### AnalysisError

分析错误。

```zig
pub const AnalysisError = error{
    AnalysisFailed,
    Timeout,
    OutOfMemory,
};
```

### InstrumentationError

插桩错误。

```zig
pub const InstrumentationError = error{
    InstrumentationFailed,
    InvalidInsertionPoint,
    CodeGenerationError,
};
```

### RuntimeError

运行时错误。

```zig
pub const RuntimeError = error{
    EventBufferFull,
    EventCorrupted,
    CollectorError,
};
```

### ConfigError

配置错误。

```zig
pub const ConfigError = error{
    InvalidConfig,
    MissingRequiredField,
    InvalidValue,
};
```

---

## 使用示例

### 基本事实存储

```zig
const OmniScope = @import("OmniScope");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化事实存储
    var store = OmniScope.fact.FactStore.init(allocator);
    defer store.deinit();

    // 插入事实
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.cfg_edge, 2, 3, 0);

    // 查询事实
    var engine = OmniScope.fact.QueryEngine.init(&store);
    const facts = try engine.queryByKind(.cfg_edge, allocator);
    defer allocator.free(facts);

    std.debug.print("找到 {} 个事实\n", .{facts.len});
}
```

### 自定义 Pass

```zig
const OmniScope = @import("OmniScope");

pub const MyCustomPass = struct {
    pub const name = "my-custom-pass";
    pub const kind = OmniScope.pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg"};

    pub fn run(ctx: *OmniScope.pass.PassContext, diag: *OmniScope.pass.DiagnosticWriter) !void {
        diag.info("开始自定义分析", .{});

        // 获取下一个 ID
        const id = ctx.getNextId();

        // 查询事实
        const cfg_edges = try ctx.query_engine.queryByKind(.cfg_edge, ctx.allocator);
        defer ctx.allocator.free(cfg_edges);

        // 执行分析
        for (cfg_edges) |edge| {
            // 处理每条边
            _ = edge;
        }

        diag.info("分析完成，找到 {} 条边", .{cfg_edges.len});
    }
};

// 验证 pass
const ValidatedPass = OmniScope.pass.Pass(MyCustomPass);
```

### 加载 LLVM IR

```zig
const OmniScope = @import("OmniScope");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载 LLVM IR
    var loader = try OmniScope.engine.IRLoader.loadFile(allocator, "program.bc");
    defer loader.deinit();

    // 检查是否加载
    if (!loader.hasModule()) {
        std.debug.print("加载模块失败\n", .{});
        return;
    }

    // 获取函数数量
    const func_count = loader.getFunctionCount();
    std.debug.print("加载了 {} 个函数\n", .{func_count});

    // 遍历函数
    try loader.iterateFunctions(funcCallback);
}

fn funcCallback(func: OmniScope.ir.FunctionRef) !void {
    // 处理每个函数
    _ = func;
}
```

---

**最后更新**: 2026-04-14  
**版本**: 1.0.0