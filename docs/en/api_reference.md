# OmniScope API Reference

Complete API reference for OmniScope library functions, types, and modules.

## Table of Contents

1. [Logging Module](#logging-module)
2. [IR Module](#ir-module)
3. [Pass Module](#pass-module)
4. [Fact Module](#fact-module)
5. [Pipeline Module](#pipeline-module)
6. [Engine Module](#engine-module)
7. [Cross-Language Analysis](#cross-language-analysis)
8. [Error Types](#error-types)

---

## Logging Module

### LogLevel

Enumeration of log levels.

```zig
pub const LogLevel = enum(u3) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};
```

### Config

Logging configuration.

```zig
pub const Config = struct {
    level: LogLevel = .info,
    enable_colors: bool = true,
    enable_timestamps: bool = true,
    enable_module_prefix: bool = true,
};
```

### Functions

#### `init`

Initialize the logging system.

```zig
pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config: Config) void
```

**Parameters:**
- `allocator`: Memory allocator for logging operations
- `writer`: Output writer for log messages
- `config`: Logging configuration

#### `deinit`

Clean up logging resources.

```zig
pub fn deinit() void
```

#### `debug`

Log a debug message.

```zig
pub fn debug(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

**Parameters:**
- `module`: Module name for log prefix
- `format`: Format string
- `args`: Format arguments

#### `info`

Log an info message.

```zig
pub fn info(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `warn`

Log a warning message.

```zig
pub fn warn(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `err`

Log an error message.

```zig
pub fn err(comptime module: []const u8, comptime format: []const u8, args: anytype) void
```

#### `setLevel`

Set the current log level.

```zig
pub fn setLevel(level: LogLevel) void
```

#### `getLevel`

Get the current log level.

```zig
pub fn getLevel() LogLevel
```

---

## IR Module

### ContextRef

Opaque reference to LLVM context.

```zig
pub const ContextRef = struct {
    raw: *opaque {},
};
```

### ModuleRef

Opaque reference to LLVM module.

```zig
pub const ModuleRef = struct {
    raw: *opaque {},
};
```

### FunctionRef

Opaque reference to LLVM function.

```zig
pub const FunctionRef = struct {
    raw: *opaque {},
};
```

### LLVM-C API Bindings

#### Context Management

```zig
pub extern fn LLVMContextCreate() LLVMContextRef;
pub extern fn LLVMContextDispose(ctx: LLVMContextRef) void;
```

#### Module Operations

```zig
pub extern fn LLVMParseBitcodeInContext2(
    ctx: LLVMContextRef,
    mem_buf: LLVMMemoryBufferRef,
    out_module: *LLVMModuleRef,
) c_int;

pub extern fn LLVMDisposeModule(module: LLVMModuleRef) void;
```

#### Value Operations

```zig
pub extern fn LLVMGetValueName(value: LLVMValueRef) [*:0]const u8;
pub extern fn LLVMGetInstructionOpcode(inst: LLVMValueRef) c_uint;
pub extern fn LLVMGetNextInstruction(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetPreviousInstruction(inst: LLVMValueRef) LLVMValueRef;
```

#### Function Operations

```zig
pub extern fn LLVMGetFirstFunction(module: LLVMModuleRef) LLVMValueRef;
pub extern fn LLVMGetNextFunction(func: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMIsAFunction(val: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMCountBasicBlocks(func_val: LLVMValueRef) c_uint;
```

#### Basic Block Operations

```zig
pub extern fn LLVMGetFirstBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;
pub extern fn LLVMGetNextBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
pub extern fn LLVMGetFirstInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
```

#### Instruction Operations

```zig
pub extern fn LLVMGetOperand(inst: LLVMValueRef, index: c_uint) LLVMValueRef;
pub extern fn LLVMGetNumOperands(inst: LLVMValueRef) c_uint;
pub extern fn LLVMIsACallInst(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetCalledValue(call: LLVMValueRef) LLVMValueRef;
```

---

## Pass Module

### PassKind

Enumeration of pass types.

```zig
pub const PassKind = enum {
    foundation,  // Basic analysis passes
    analysis,    // Advanced analysis passes
    plugin,      // User-defined plugin passes
};
```

### PassContext

Context passed to each pass during execution.

```zig
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    next_id: std.atomic.Value(u32),

    /// Create a new pass context
    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
    ) PassContext;

    /// Get a unique ID (thread-safe)
    pub fn getNextId(self: *PassContext) u32;

    /// Set the IR module
    pub fn setModule(self: *PassContext, module: ModuleRef) void;

    /// Check if a module is loaded
    pub fn hasModule(self: *const PassContext) bool;
};
```

### DiagnosticWriter

Writer for pass output.

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

Comptime wrapper for pass validation.

```zig
pub fn Pass(comptime T: type) type;
```

**Requirements for Pass type:**
- Must have `name: []const u8` declaration
- Must have `kind: PassKind` declaration
- Must have `deps: []const []const u8` declaration
- Must have `run(ctx: *PassContext, diag: *DiagnosticWriter) !void` function

---

## Fact Module

### FactKind

Enumeration of fact types.

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

Represents a single fact.

```zig
pub const Fact = struct {
    kind: FactKind,
    subject: u32,
    object: u32,
    context: u32,
};
```

### FactStore

SoA (Structure of Arrays) fact storage.

```zig
pub const FactStore = struct {
    kinds: []FactKind,
    subjects: []u32,
    objects: []u32,
    contexts: []u32,

    /// Initialize fact store
    pub fn init(allocator: Allocator) FactStore;

    /// Clean up fact store
    pub fn deinit(self: *FactStore) void;

    /// Insert a fact
    pub fn insert(self: *FactStore, kind: FactKind, subject: u32, object: u32, context: u32) !void;

    /// Query facts by kind
    pub fn queryByKind(self: *FactStore, kind: FactKind, allocator: Allocator) ![]Fact;

    /// Query facts by subject
    pub fn queryBySubject(self: *FactStore, subject: u32, allocator: Allocator) ![]Fact;

    /// Query facts by object
    pub fn queryByObject(self: *FactStore, object: u32, allocator: Allocator) ![]Fact;

    /// Get fact count
    pub fn count(self: *FactStore) usize;
};
```

### QueryEngine

Engine for querying facts.

```zig
pub const QueryEngine = struct {
    store: *FactStore,

    /// Initialize query engine
    pub fn init(store: *FactStore) QueryEngine;

    /// Query facts by kind
    pub fn queryByKind(self: *QueryEngine, kind: FactKind, allocator: Allocator) ![]Fact;

    /// Query facts by subject
    pub fn queryBySubject(self: *QueryEngine, subject: u32, allocator: Allocator) ![]Fact;

    /// Query facts by object
    pub fn queryByObject(self: *QueryEngine, object: u32, allocator: Allocator) ![]Fact;

    /// Query facts with multiple criteria
    pub fn query(self: *QueryEngine, criteria: QueryCriteria, allocator: Allocator) ![]Fact;
};
```

### QueryCriteria

Criteria for fact queries.

```zig
pub const QueryCriteria = struct {
    kind: ?FactKind = null,
    subject: ?u32 = null,
    object: ?u32 = null,
    context: ?u32 = null,
};
```

---

## Pipeline Module

### StageKind

Enumeration of pipeline stage types.

```zig
pub const StageKind = enum {
    static,          // Static analysis stage
    instrumentation,  // Instrumentation stage
    runtime,         // Runtime monitoring stage
    merge,           // Merge stage
};
```

### StageContext

Context for pipeline stages.

```zig
pub const StageContext = struct {
    allocator: Allocator,
    config: *const Config,
    fact_store: *FactStore,
    query_engine: *QueryEngine,

    /// Initialize stage context
    pub fn init(
        allocator: Allocator,
        config: *const Config,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
    ) StageContext;
};
```

### StageResult

Result of pipeline stage execution.

```zig
pub const StageResult = union(enum) {
    success,
    failed: []const u8,
};
```

### Stage

Base interface for pipeline stages.

```zig
pub const Stage = struct {
    kind: StageKind,

    /// Run the stage
    pub fn run(self: *Stage, ctx: *StageContext) StageResult;
};
```

### Pipeline

Main analysis pipeline.

```zig
pub const Pipeline = struct {
    allocator: Allocator,
    stages: std.ArrayList(*Stage),
    fact_store: FactStore,
    query_engine: QueryEngine,

    /// Initialize pipeline
    pub fn init(allocator: Allocator) Pipeline;

    /// Clean up pipeline
    pub fn deinit(self: *Pipeline) void;

    /// Add a stage to the pipeline
    pub fn addStage(self: *Pipeline, stage: *Stage) !void;

    /// Run the pipeline
    pub fn run(self: *Pipeline) !PipelineResult;

    /// Get fact store
    pub fn getFactStore(self: *Pipeline) *FactStore;

    /// Get query engine
    pub fn getQueryEngine(self: *Pipeline) *QueryEngine;
};
```

### PipelineResult

Result of pipeline execution.

```zig
pub const PipelineResult = struct {
    success: bool,
    error_message: ?[]const u8,
    diagnostics: []Diagnostic,
};
```

---

## Engine Module

### LoaderError

Error set for IR loader.

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

LLVM IR loader.

```zig
pub const IRLoader = struct {
    allocator: Allocator,
    llvm_ctx: ContextRef,
    module: ?ModuleRef,
    alive: bool = false,

    /// Load a .bc file from disk
    pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader;

    /// Get the module reference
    pub fn getModule(self: *IRLoader) ?ModuleRef;

    /// Get the LLVM context
    pub fn getContext(self: *IRLoader) ContextRef;

    /// Iterate over all functions
    pub fn iterateFunctions(
        self: *IRLoader,
        callback: fn (FunctionRef) anyerror!void,
    ) !void;

    /// Get a function by name
    pub fn getFunction(self: *IRLoader, name: []const u8) ?FunctionRef;

    /// Get the number of functions
    pub fn getFunctionCount(self: *IRLoader) usize;

    /// Check if a module is loaded
    pub fn hasModule(self: *IRLoader) bool;

    /// Clean up resources
    pub fn deinit(self: *IRLoader) void;
};
```

---

## Cross-Language Analysis

### FunctionKind

Enumeration of function types.

```zig
pub const FunctionKind = enum {
    internal,
    libc,
    external_unknown,
};
```

### Node

Represents a node in the call graph.

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

Represents an edge in the call graph.

```zig
pub const Edge = struct {
    caller: u32,
    callee: u32,
};
```

### CallGraphPass

Builds call graph from LLVM IR.

```zig
pub const CallGraphPass = struct {
    pub const name = "call-graph";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void;
};
```

### TaintPropagationPass

Performs forward taint propagation.

```zig
pub const TaintPropagationPass = struct {
    pub const name = "taint-propagation";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) TaintError!void;
};
```

### FFIBoundaryPass

Marks cross-language transitions.

```zig
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIBoundaryError!void;
};
```

### PointerOwnershipPass

Tracks pointer ownership across FFI boundaries.

```zig
pub const PointerOwnershipPass = struct {
    pub const name = "pointer-ownership";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) OwnershipError!void;
};
```

### OwnershipViolationPass

Detects ownership violations across FFI boundaries.

```zig
pub const OwnershipViolationPass = struct {
    pub const name = "ownership-violation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg", "dfg", "taint"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) FFIAnalysisError!void;
};
```

---

## Error Types

### Error

Base error set.

```zig
pub const Error = error{
    OutOfMemory,
    InvalidInput,
    InvalidState,
};
```

### IRLoadError

IR loading errors.

```zig
pub const IRLoadError = error{
    FileNotFound,
    InvalidIR,
    LLVMContextCreationFailed,
    ModuleParseFailed,
};
```

### IRViewError

IR view errors.

```zig
pub const IRViewError = error{
    InvalidValue,
    InvalidType,
    NullPointer,
};
```

### PassError

Pass execution errors.

```zig
pub const PassError = error{
    PassNotFound,
    DependencyNotMet,
    PassFailed,
};
```

### AnalysisError

Analysis errors.

```zig
pub const AnalysisError = error{
    AnalysisFailed,
    Timeout,
    OutOfMemory,
};
```

### InstrumentationError

Instrumentation errors.

```zig
pub const InstrumentationError = error{
    InstrumentationFailed,
    InvalidInsertionPoint,
    CodeGenerationError,
};
```

### RuntimeError

Runtime errors.

```zig
pub const RuntimeError = error{
    EventBufferFull,
    EventCorrupted,
    CollectorError,
};
```

### ConfigError

Configuration errors.

```zig
pub const ConfigError = error{
    InvalidConfig,
    MissingRequiredField,
    InvalidValue,
};
```

---

## Usage Examples

### Basic Fact Storage

```zig
const OmniScope = @import("OmniScope");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize fact store
    var store = OmniScope.fact.FactStore.init(allocator);
    defer store.deinit();

    // Insert facts
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.cfg_edge, 2, 3, 0);

    // Query facts
    var engine = OmniScope.fact.QueryEngine.init(&store);
    const facts = try engine.queryByKind(.cfg_edge, allocator);
    defer allocator.free(facts);

    std.debug.print("Found {} facts\n", .{facts.len});
}
```

### Custom Pass

```zig
const OmniScope = @import("OmniScope");

pub const MyCustomPass = struct {
    pub const name = "my-custom-pass";
    pub const kind = OmniScope.pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg"};

    pub fn run(ctx: *OmniScope.pass.PassContext, diag: *OmniScope.pass.DiagnosticWriter) !void {
        diag.info("Starting custom analysis", .{});

        // Get next ID
        const id = ctx.getNextId();

        // Query facts
        const cfg_edges = try ctx.query_engine.queryByKind(.cfg_edge, ctx.allocator);
        defer ctx.allocator.free(cfg_edges);

        // Perform analysis
        for (cfg_edges) |edge| {
            // Process each edge
            _ = edge;
        }

        diag.info("Analysis complete, found {} edges", .{cfg_edges.len});
    }
};

// Validate the pass
const ValidatedPass = OmniScope.pass.Pass(MyCustomPass);
```

### Loading LLVM IR

```zig
const OmniScope = @import("OmniScope");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load LLVM IR
    var loader = try OmniScope.engine.IRLoader.loadFile(allocator, "program.bc");
    defer loader.deinit();

    // Check if loaded
    if (!loader.hasModule()) {
        std.debug.print("Failed to load module\n", .{});
        return;
    }

    // Get function count
    const func_count = loader.getFunctionCount();
    std.debug.print("Loaded {} functions\n", .{func_count});

    // Iterate functions
    try loader.iterateFunctions(funcCallback);
}

fn funcCallback(func: OmniScope.ir.FunctionRef) !void {
    // Process each function
    _ = func;
}
```

---

**Last Updated**: 2026-04-14  
**Version**: 1.0.0