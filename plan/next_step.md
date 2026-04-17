# OmniScope 实用化开发计划

## 项目定位

**OmniScope 是一个专注于 FFI 安全的静态分析工具**

- **核心价值**：检测所有 LLVM 语言（C/C++/Rust/Zig/Swift/Julia 等）与 C 之间的 FFI 边界安全问题
- **目标用户**：日常开发多语言混合项目的开发者
- **使用场景**：CI/CD 流程中的自动化安全检查
- **差异化**：弥补现有工具（CodeQL、Clang Analyzer、Rust Clippy）在跨语言分析上的短板

## 技术架构设计

### 1. 数据结构设计

#### 1.1 核心内存模型

```zig
// 表示一个分配的内存对象
pub const MemoryObject = struct {
    id: u32,
    alloc_site: u32,        // 分配位置（指令 ID）
    alloc_type: AllocType,  // 分配类型
    size: ?u64,             // 大小（如果可推断）
    is_cross_language: bool, // 是否跨语言边界
    escape_state: EscapeState,
};

pub const AllocType = enum {
    heap_malloc,    // malloc/new
    stack_alloca,   // alloca
    global,         // 全局变量
    unknown,
};

pub const EscapeState = enum {
    no_escape,      // 不逃逸
    to_c,          // 逃逸到 C
    from_c,        // 来自 C
    unknown,       // 未知
};
```

#### 1.2 FFI 边界表示

```zig
// FFI 边界节点
pub const FFIBoundary = struct {
    id: u32,
    boundary_type: BoundaryType,
    from_language: Language,
    to_language: Language,
    function_name: []const u8,
    location: Location,
    // 跨边界传递的参数
    parameters: []u32,  // ValueId 列表
};

pub const BoundaryType = enum {
    rust_to_c,      // Rust 调用 C 函数
    c_to_rust,      // C 回调到 Rust
    c_to_zig,       // C 调用 Zig
    zig_to_c,       // Zig 调用 C
    external,       // 未知外部调用
};

pub const Language = enum {
    c,
    cpp,
    rust,
    zig,
    swift,
    julia,
    unknown,
};
```

#### 1.3 数据流图

```zig
// 数据流边
pub const DataFlowEdge = struct {
    from: u32,      // 源 ValueId
    to: u32,        // 目标 ValueId
    edge_type: EdgeType,
    via_function: ?[]const u8,  // 通过的函数（跨函数时）
};

pub const EdgeType = enum {
    direct,         // 直接赋值/加载
    call_arg,       // 函数调用参数
    call_ret,       // 函数返回值
    store,          // 存储操作
    load,           // 加载操作
    ffi_boundary,   // FFI 边界
};

// 全局数据流图
pub const DataFlowGraph = struct {
    nodes: std.AutoHashMap(u32, DataFlowNode),
    edges: std.ArrayList(DataFlowEdge),
    // 快速查询索引
    outgoing: std.AutoHashMap(u32, []const u32),  // from -> [to]
    incoming: std.AutoHashMap(u32, []const u32),  // to -> [from]
};

pub const DataFlowNode = struct {
    id: u32,
    value_type: ValueType,
    taint_state: TaintState,
    // 内存对象（如果是指针）
    memory_obj: ?*MemoryObject,
    // 位置信息
    function: []const u8,
    location: Location,
};

pub const ValueType = enum {
    integer,
    pointer,
    struct_,
    array,
    function,
    unknown,
};
```

#### 1.4 污点状态

```zig
pub const TaintState = enum(u8) {
    none = 0,       // 无污点
    source = 1,     // 污点源
    tainted = 2,    // 被污染
    sanitized = 3,  // 已清洗
};

pub const TaintInfo = struct {
    state: TaintState,
    source_id: ?u32,        // 污点源 ID
    confidence: f32,        // 置信度
    // 污点来源信息
    source_type: ?SourceType,
    source_location: ?Location,
};

pub const SourceType = enum {
    user_input,     // 用户输入
    file_read,      // 文件读取
    network,        // 网络输入
    environment,    // 环境变量
    c_return,       // C 函数返回值
    unknown,
};
```

#### 1.5 漏洞报告

```zig
pub const VulnerabilityReport = struct {
    id: u32,
    vuln_type: VulnType,
    severity: Severity,
    // 路径信息
    source_location: Location,
    sink_location: Location,
    flow_path: FlowPath,
    // FFI 信息
    ffi_boundaries: []FFIBoundary,
    // 上下文
    description: []const u8,
    recommendation: []const u8,
};

pub const VulnType = enum {
    command_injection,      // 命令注入
    buffer_overflow,        // 缓冲区溢出
    use_after_free,         // 释放后使用
    double_free,            // 双重释放
    memory_leak,            // 内存泄漏
    null_dereference,       // 空指针解引用
    format_string,          // 格式化字符串
    integer_overflow,       // 整数溢出
    cross_language_free,    // 跨语言释放错误
    unknown,
};

pub const Severity = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    critical = 3,
};
```

### 2. 算法设计

#### 2.1 源点识别算法

```zig
// 识别污点源
pub fn identifySources(ir: *IR) ![]Source {
    var sources = std.ArrayList(Source).init(allocator);

    for (ir.functions) |func| {
        for (func.instructions) |inst| {
            // 1. 函数调用源点
            if (isSourceFunction(inst)) {
                try sources.append(Source{
                    .id = getNextId(),
                    .type = getSourceType(inst),
                    .value_id = inst.result_id,
                    .location = inst.location,
                    .function = func.name,
                });
            }

            // 2. 参数源点（main 函数参数）
            if (isMainFunction(func) and isArgument(inst)) {
                try sources.append(Source{
                    .id = getNextId(),
                    .type = .user_input,
                    .value_id = inst.result_id,
                    .location = inst.location,
                    .function = func.name,
                });
            }

            // 3. 全局变量源点
            if (isGlobalVariable(inst)) {
                try sources.append(Source{
                    .id = getNextId(),
                    .type = .unknown,
                    .value_id = inst.result_id,
                    .location = inst.location,
                    .function = func.name,
                });
            }
        }
    }

    return sources.toOwnedSlice();
}

// 判断是否为源点函数
fn isSourceFunction(inst: Instruction) bool {
    const source_functions = [_][]const u8{
        "read",      // C
        "fread",     // C
        "fgets",     // C
        "gets",      // C
        "scanf",     // C
        "recv",      // C
        "getenv",    // C
        "std::io::stdin",  // Rust
        "std::fs::read",   // Rust
    };

    for (source_functions) |name| {
        if (std.mem.eql(u8, inst.called_function, name)) {
            return true;
        }
    }
    return false;
}
```

#### 2.2 污点传播算法

```zig
// 污点传播（基于工作列表算法）
pub fn propagateTaint(
    dfg: *DataFlowGraph,
    sources: []Source,
) !void {
    var worklist = std.ArrayList(u32).init(allocator);

    // 初始化：将所有源点加入工作列表
    for (sources) |source| {
        try dfg.setTaintState(source.value_id, .source);
        try worklist.append(source.value_id);
    }

    // 工作列表算法
    while (worklist.popOrNull()) |value_id| {
        const current_taint = dfg.getTaintState(value_id);

        // 处理所有出边
        const outgoing = dfg.getOutgoing(value_id);
        for (outgoing) |target_id| {
            const target_taint = dfg.getTaintState(target_id);

            // 如果目标尚未被污染，且边类型允许传播
            if (target_taint.state == .none and shouldPropagate(value_id, target_id)) {
                try dfg.setTaintState(target_id, .tainted);
                try worklist.append(target_id);
            }
        }
    }
}

// 判断是否应该传播污点
fn shouldPropagate(from_id: u32, to_id: u32) bool {
    // 1. 直接赋值、加载、存储操作总是传播
    if (isDirectEdge(from_id, to_id)) {
        return true;
    }

    // 2. 函数调用参数传播
    if (isCallArgEdge(from_id, to_id)) {
        return true;
    }

    // 3. 函数返回值传播
    if (isCallRetEdge(from_id, to_id)) {
        return true;
    }

    // 4. FFI 边界传播（关键！）
    if (isFFIBoundary(from_id, to_id)) {
        return true;  // 跨语言边界也要追踪
    }

    return false;
}
```

#### 2.3 汇点检测算法

```zig
// 识别危险汇点
pub fn identifySinks(ir: *IR) ![]Sink {
    var sinks = std.ArrayList(Sink).init(allocator);

    for (ir.functions) |func| {
        for (func.instructions) |inst| {
            if (isSinkFunction(inst)) {
                try sinks.append(Sink{
                    .id = getNextId(),
                    .type = getSinkType(inst),
                    .value_id = getArgumentValueId(inst, 0),  // 第一个参数
                    .location = inst.location,
                    .function = func.name,
                });
            }
        }
    }

    return sinks.toOwnedSlice();
}

// 判断是否为汇点函数
fn isSinkFunction(inst: Instruction) bool {
    const sink_functions = [_][]const u8{
        "system",          // C - 命令执行
        "exec",            // C - 命令执行
        "popen",           // C - 命令执行
        "strcpy",          // C - 缓冲区溢出
        "strcat",          // C - 缓冲区溢出
        "sprintf",         // C - 格式化字符串
        "printf",          // C - 格式化字符串
        "free",            // C - 释放
        "std::process::Command::new",  // Rust - 命令执行
        "std::ptr::write",             // Rust - 写入
    };

    for (sink_functions) |name| {
        if (std.mem.eql(u8, inst.called_function, name)) {
            return true;
        }
    }
    return false;
}
```

#### 2.4 路径追踪算法

```zig
// 从源点到汇点的路径追踪
pub fn tracePath(
    dfg: *DataFlowGraph,
    source_id: u32,
    sink_id: u32,
) !?FlowPath {
    var path = FlowPath.init();
    errdefer path.deinit();

    // BFS 寻找路径
    var visited = std.AutoHashMap(u32, void).init(allocator);
    var queue = std.ArrayList(PathNode).init(allocator);

    try queue.append(PathNode{
        .value_id = source_id,
        .path = &[_]u32{},
    });

    while (queue.popOrNull()) |node| {
        if (node.value_id == sink_id) {
            // 找到路径
            for (node.path) |value_id| {
                try path.addStep(createStepFromValue(value_id));
            }
            return path;
        }

        if (visited.contains(node.value_id)) {
            continue;
        }
        try visited.put(node.value_id, {});

        // 扩展
        const outgoing = dfg.getOutgoing(node.value_id);
        for (outgoing) |next_id| {
            var new_path = try allocator.alloc(u32, node.path.len + 1);
            @memcpy(new_path[0..node.path.len], node.path);
            new_path[node.path.len] = next_id;

            try queue.append(PathNode{
                .value_id = next_id,
                .path = new_path,
            });
        }
    }

    return null;  // 没有找到路径
}

pub const PathNode = struct {
    value_id: u32,
    path: []const u32,
};
```

#### 2.5 FFI 边界检测算法

```zig
// 检测 FFI 边界
pub fn detectFFIBoundaries(
    ir: *IR,
    config: *FFIConfig,
) ![]FFIBoundary {
    var boundaries = std.ArrayList(FFIBoundary).init(allocator);

    for (ir.functions) |func| {
        const caller_lang = detectLanguage(func);

        for (func.instructions) |inst| {
            if (inst.opcode == .call) {
                const callee_lang = config.getLanguage(inst.called_function);

                // 如果调用方和被调用方语言不同，检测到 FFI 边界
                if (caller_lang != callee_lang and caller_lang != .unknown and callee_lang != .unknown) {
                    try boundaries.append(FFIBoundary{
                        .id = getNextId(),
                        .boundary_type = getBoundaryType(caller_lang, callee_lang),
                        .from_language = caller_lang,
                        .to_language = callee_lang,
                        .function_name = inst.called_function,
                        .location = inst.location,
                        .parameters = extractParameterIds(inst),
                    });
                }
            }
        }
    }

    return boundaries.toOwnedSlice();
}

// 检测函数的语言
fn detectLanguage(func: Function) Language {
    // 1. 基于命名约定
    if (isRustMangledName(func.name)) {
        return .rust;
    }
    if (isCppMangledName(func.name)) {
        return .cpp;
    }
    if (isZigFunction(func.name)) {
        return .zig;
    }

    // 2. 基于函数签名
    if (hasRustBorrowSignature(func)) {
        return .rust;
    }

    // 3. 默认为 C
    return .c;
}

// FFI 配置
pub const FFIConfig = struct {
    // 语言映射表
    language_map: std.StringHashMap(Language),

    // 边界规则
    boundary_rules: []BoundaryRule,

    pub fn init(allocator: Allocator) FFIConfig {
        var config = FFIConfig{
            .language_map = std.StringHashMap(Language).init(allocator),
            .boundary_rules = &[_]BoundaryRule{},
        };

        // 内置常见函数
        config.language_map.put("malloc", .c) catch {};
        config.language_map.put("free", .c) catch {};
        config.language_map.put("read", .c) catch {};
        config.language_map.put("write", .c) catch {};
        config.language_map.put("system", .c) catch {};
        config.language_map.put("exec", .c) catch {};

        return config;
    }

    pub fn getLanguage(self: *const FFIConfig, func_name: []const u8) Language {
        if (self.language_map.get(func_name)) |lang| {
            return lang;
        }

        // 基于命名约定推断
        if (isRustMangledName(func_name)) return .rust;
        if (isCppMangledName(func_name)) return .cpp;
        if (isZigFunction(func_name)) return .zig;

        return .c;  // 默认为 C
    }
};
```

### 3. 输出格式设计

#### 3.1 CLI 输出（人类可读）

```
=== OmniScope FFI Security Analysis ===

[*] Loading IR: target.bc
[*] IR loaded: 42 functions
[*] Running analysis...

[!] Found 3 vulnerabilities

--- Vulnerability #1: OMI-001 ---
Type:        Command Injection
Severity:    CRITICAL
Risk Score:  9.2/10

Flow Path:
  source: std::io::stdin().read_line() [Rust]
    → process_input() [Rust]
    → [FFI Boundary: Rust → C]
    → dangerous_c_func() [C]
    → system() [C]

Cross-Language: YES
FFI Boundaries: 1

Description:
  Unsanitized user input flows from Rust to C and is passed to system(),
  allowing arbitrary command execution.

Recommendation:
  - Add input validation before FFI call
  - Use whitelist instead of blacklist
  - Consider using safer alternatives like execve()

Location:
  File: src/main.rs:42:10
  Function: process_input

--- Vulnerability #2: OMI-002 ---
Type:        Buffer Overflow
Severity:    HIGH
Risk Score:  7.5/10

Flow Path:
  source: read() [C]
    → rust_wrapper() [Rust]
    → [FFI Boundary: Rust → C]
    → strcpy() [C]

Cross-Language: YES
FFI Boundaries: 1

Description:
  Data from C is passed to Rust without size checking, then flows back to C
  and is used in strcpy(), causing potential buffer overflow.

Recommendation:
  - Validate buffer size at FFI boundary
  - Use strncpy() or memcpy() with explicit size
  - Add bounds checking in Rust wrapper

Location:
  File: src/wrapper.rs:15:5
  Function: rust_wrapper

--- Vulnerability #3: OMI-003 ---
Type:        Cross-Language Free Error
Severity:    MEDIUM
Risk Score:  6.0/10

Flow Path:
  alloc: Box::new() [Rust]
    → [FFI Boundary: Rust → C]
    → free() [C]

Cross-Language: YES
FFI Boundaries: 1

Description:
  Memory allocated in Rust (using Box::new) is freed in C using free().
  This can cause undefined behavior due to allocator mismatch.

Recommendation:
  - Ensure consistent allocator across FFI boundary
  - Use Rust's dealloc API from C
  - Or allocate and free in same language

Location:
  File: src/ffi.rs:28:12
  Function: transfer_to_c

=== Summary ===
Total Functions Analyzed:    42
Total FFI Boundaries:        7
Vulnerabilities Found:       3
  - Critical:                 1
  - High:                     1
  - Medium:                   1
  - Low:                      0

Analysis Time:                0.23s
```

#### 3.2 JSON 输出（CI/CD 友好）

```json
{
  "version": "1.0.0",
  "tool": "omniscope",
  "analysis_time": "2026-04-15T10:30:00Z",
  "target": "target.bc",
  "statistics": {
    "total_functions": 42,
    "total_ffi_boundaries": 7,
    "vulnerabilities_found": 3,
    "by_severity": {
      "critical": 1,
      "high": 1,
      "medium": 1,
      "low": 0
    }
  },
  "vulnerabilities": [
    {
      "id": "OMI-001",
      "type": "command_injection",
      "severity": "critical",
      "risk_score": 9.2,
      "source_location": {
        "file": "src/main.rs",
        "line": 35,
        "column": 10,
        "function": "process_input"
      },
      "sink_location": {
        "file": "src/c_wrapper.c",
        "line": 42,
        "column": 5,
        "function": "dangerous_c_func"
      },
      "flow_path": [
        {
          "function": "std::io::stdin().read_line()",
          "language": "rust",
          "location": {"file": "src/main.rs", "line": 35, "column": 10}
        },
        {
          "function": "process_input()",
          "language": "rust",
          "location": {"file": "src/main.rs", "line": 38, "column": 5}
        },
        {
          "type": "ffi_boundary",
          "from": "rust",
          "to": "c",
          "function": "dangerous_c_func"
        },
        {
          "function": "system()",
          "language": "c",
          "location": {"file": "src/c_wrapper.c", "line": 42, "column": 5}
        }
      ],
      "cross_language": true,
      "ffi_boundaries_count": 1,
      "description": "Unsanitized user input flows from Rust to C and is passed to system(), allowing arbitrary command execution.",
      "recommendation": "Add input validation before FFI call. Use whitelist instead of blacklist. Consider using safer alternatives like execve().",
      "cwe": "CWE-78"
    }
  ],
  "ffi_boundaries": [
    {
      "id": 1,
      "from_language": "rust",
      "to_language": "c",
      "function": "dangerous_c_func",
      "location": {"file": "src/main.rs", "line": 40, "column": 8},
      "parameters_count": 2
    }
  ]
}
```

#### 3.3 SARIF 输出（GitHub Security 支持）

```json
{
  "version": "2.1.0",
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "OmniScope",
          "version": "1.0.0",
          "informationUri": "https://github.com/yourusername/omniscope",
          "rules": [
            {
              "id": "OMI-001",
              "name": "command-injection",
              "shortDescription": {
                "text": "Command Injection via FFI"
              },
              "fullDescription": {
                "text": "Unsanitized user input flows across FFI boundary to system() call"
              },
              "help": {
                "text": "Add input validation before FFI call. Use whitelist instead of blacklist."
              },
              "properties": {
                "tags": ["security", "injection", "cross-language"],
                "precision": "high",
                "severity": "critical"
              }
            }
          ]
        }
      },
      "results": [
        {
          "ruleId": "OMI-001",
          "ruleIndex": 0,
          "level": "error",
          "message": {
            "text": "Unsanitized user input flows across FFI boundary to system() call"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/main.rs"
                },
                "region": {
                  "startLine": 40,
                  "startColumn": 8
                }
              }
            }
          ],
          "codeFlows": [
            {
              "threadFlows": [
                {
                  "locations": [
                    {
                      "location": {
                        "physicalLocation": {
                          "artifactLocation": {"uri": "src/main.rs"},
                          "region": {"startLine": 35, "startColumn": 10}
                        },
                        "message": {"text": "Source: std::io::stdin().read_line() [Rust]"}
                      }
                    },
                    {
                      "location": {
                        "message": {"text": "FFI Boundary: Rust → C"}
                      }
                    },
                    {
                      "location": {
                        "physicalLocation": {
                          "artifactLocation": {"uri": "src/c_wrapper.c"},
                          "region": {"startLine": 42, "startColumn": 5}
                        },
                        "message": {"text": "Sink: system() [C]"}
                      }
                    }
                  ]
                }
              ]
            }
          ],
          "properties": {
            "cross_language": true,
            "ffi_boundaries": 1,
            "risk_score": 9.2,
            "cwe": "CWE-78"
          }
        }
      ]
    }
  ]
}
```

### 4. 数据流设计

```
┌─────────────────────────────────────────────────────────────┐
│                        用户输入                              │
│                 omniscope analyze target.bc                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    1. IR 加载阶段                            │
│  - 加载 LLVM IR 文件                                        │
│  - 解析函数、基本块、指令                                    │
│  - 构建符号表                                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    2. 基础分析 Pass                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ CFG Pass    │→ │ DFG Pass    │→ │ Alias Pass  │        │
│  │ 控制流图    │  │ 数据流图    │  │ 别名分析    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    3. FFI 分析 Pass                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ CallGraph   │→ │ FFIBoundary │→ │ TaintProp   │        │
│  │ 调用图      │  │ 边界检测    │  │ 污点传播    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    4. 漏洞检测 Pass                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ SourceIdent │→ │ SinkTracer  │→ │ PathFinder  │        │
│  │ 源点识别    │  │ 汇点追踪    │  │ 路径查找    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    5. 结果聚合阶段                          │
│  - 合并所有 Pass 的结果                                      │
│  - 去重和优先级排序                                          │
│  - 计算风险评分                                              │
│  - 生成漏洞报告                                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    6. 输出生成阶段                          │
│  - CLI 输出（人类可读）                                      │
│  - JSON 输出（CI/CD 友好）                                  │
│  - SARIF 输出（GitHub Security）                            │
│  - 设置退出码（有漏洞 = 1，无漏洞 = 0）                     │
└─────────────────────────────────────────────────────────────┘
```

### 5. CI/CD 集成方案

#### 5.1 GitHub Actions Workflow

```yaml
name: FFI Security Analysis

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Install Rust
      uses: actions-rs/toolchain@v1
      with:
        toolchain: stable

    - name: Install OmniScope
      run: |
        wget https://github.com/yourusername/omniscope/releases/latest/download/omniscope-linux-amd64
        chmod +x omniscope-linux-amd64
        sudo mv omniscope-linux-amd64 /usr/local/bin/omniscope

    - name: Build project to LLVM IR
      run: |
        # 编译到 LLVM IR
        cargo rustc -- --emit=llvm-ir -o target/ir/myproject.ll
        # 转换为 bitcode
        llvm-as target/ir/myproject.ll -o target/ir/myproject.bc

    - name: Run OmniScope analysis
      run: |
        omniscope analyze target/ir/myproject.bc \
          --output-format sarif \
          --output-file results.sarif \
          --fail-on critical,high

    - name: Upload SARIF results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: results.sarif

    - name: Comment PR with results
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v6
      with:
        script: |
          const fs = require('fs');
          const results = JSON.parse(fs.readFileSync('results.sarif', 'utf8'));
          const vulns = results.runs[0].results;

          if (vulns.length > 0) {
            const comment = `## 🔒 FFI Security Analysis Results\n\n` +
              `Found **${vulns.length}** potential vulnerabilities:\n\n` +
              vulns.map(v => `- [${v.level.toUpperCase()}] ${v.ruleId}: ${v.message.text}`).join('\n') +
              `\n\n[View full details](https://github.com/${context.repo.owner}/${context.repo.repo}/security/code-scanning)`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: comment
            });
          }
```

#### 5.2 GitLab CI 配置

```yaml
stages:
  - build
  - security

build:ir:
  stage: build
  script:
    - cargo rustc -- --emit=llvm-ir -o target/ir/project.ll
    - llvm-as target/ir/project.ll -o target/ir/project.bc
  artifacts:
    paths:
      - target/ir/project.bc
    expire_in: 1 week

security:ffi:
  stage: security
  needs:
    - build:ir
  script:
    - omniscope analyze target/ir/project.bc --output-format json --output-file security-report.json
    - |
      if [ $(jq '.statistics.vulnerabilities_found' security-report.json) -gt 0 ]; then
        echo "FFI vulnerabilities found!"
        jq '.vulnerabilities[]' security-report.json
        exit 1
      fi
  artifacts:
    reports:
      sast: security-report.json
    when: always
  allow_failure: false
```

#### 5.3 Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# 检查是否有修改的 Rust 文件
if git diff --cached --name-only | grep -q '\.rs$'; then
    echo "Running FFI security analysis..."

    # 编译到 LLVM IR
    cargo rustc -- --emit=llvm-ir -o /tmp/project.ll 2>/dev/null
    llvm-as /tmp/project.ll -o /tmp/project.bc 2>/dev/null

    # 运行分析
    omniscope analyze /tmp/project.bc --output-format json --output-file /tmp/omniscope.json

    # 检查是否有严重漏洞
    critical_count=$(jq '[.vulnerabilities[] | select(.severity == "critical")] | length' /tmp/omniscope.json)
    high_count=$(jq '[.vulnerabilities[] | select(.severity == "high")] | length' /tmp/omniscope.json)

    if [ "$critical_count" -gt 0 ] || [ "$high_count" -gt 0 ]; then
        echo "❌ Found $critical_count critical and $high_count high severity vulnerabilities!"
        echo "Run 'omniscope analyze target/ir/project.bc' for details"
        exit 1
    fi
fi

exit 0
```

### 6. 实现步骤和里程碑

#### 阶段 1：基础实现（Week 1-2）

**目标**：实现核心数据结构和基础算法

- [ ] 实现核心数据结构
  - [ ] MemoryObject、FFIBoundary、DataFlowGraph
  - [ ] TaintState、VulnerabilityReport
- [ ] 实现 IR 加载和解析
  - [ ] 函数、基本块、指令解析
  - [ ] 符号表构建
- [ ] 实现基础 Pass
  - [ ] CFG Pass
  - [ ] DFG Pass
- [ ] 实现源点识别
  - [ ] 识别常见源点函数
  - [ ] 识别 main 函数参数

**里程碑**：能够加载 IR 并识别污点源

#### 阶段 2：污点传播和 FFI 检测（Week 3-4）

**目标**：实现污点传播和 FFI 边界检测

- [ ] 实现污点传播算法
  - [ ] 工作列表算法
  - [ ] 跨函数传播
- [ ] 实现 FFI 边界检测
  - [ ] 语言检测（基于命名约定）
  - [ ] FFI 配置系统
  - [ ] 边界标记
- [ ] 实现汇点检测
  - [ ] 识别危险汇点函数
  - [ ] 汇点分类
- [ ] 实现路径追踪
  - [ ] BFS 路径查找
  - [ ] 路径构建

**里程碑**：能够追踪从源点到汇点的数据流，包括跨语言边界

#### 阶段 3：输出和 CI/CD 集成（Week 5-6）

**目标**：实现多格式输出和 CI/CD 集成

- [ ] 实现 CLI 输出
  - [ ] 人类可读格式
  - [ ] 彩色输出
  - [ ] 进度显示
- [ ] 实现 JSON 输出
  - [ ] 结构化数据
  - [ ] 统计信息
- [ ] 实现 SARIF 输出
  - [ ] 符合 SARIF 2.1.0
  - [ ] Code Flow 支持
  - [ ] GitHub Security 集成
- [ ] 实现 CI/CD 支持
  - [ ] 退出码设置
  - [ ] GitHub Actions 示例
  - [ ] GitLab CI 示例
  - [ ] Pre-commit hook 示例

**里程碑**：能够集成到 CI/CD 流程中，并在发现漏洞时阻止合并

#### 阶段 4：优化和文档（Week 7-8）

**目标**：性能优化和完善文档

- [ ] 性能优化
  - [ ] 增量分析
  - [ ] 并行化
  - [ ] 缓存优化
- [ ] 规则扩展
  - [ ] 更多源点/汇点规则
  - [ ] 自定义规则支持
  - [ ] 规则库
- [ ] 文档完善
  - [ ] 用户指南
  - [ ] CI/CD 集成指南
  - [ ] 规则编写指南
  - [ ] 示例和教程

**里程碑**：完整的、可用的 FFI 安全分析工具

### 7. 验证和测试

#### 7.1 测试用例

**测试用例 1：Rust → C 命令注入**

```rust
// main.rs
extern "C" {
    fn dangerous(cmd: *const i8);
}

fn main() {
    let input = std::io::stdin().lines().next().unwrap().unwrap();
    let c_str = std::ffi::CString::new(input).unwrap();
    unsafe {
        dangerous(c_str.as_ptr());
    }
}

// c_lib.c
#include <stdlib.h>

void dangerous(char* cmd) {
    system(cmd);  // 漏洞
}
```

**预期输出**：
- 类型：Command Injection
- 严重性：CRITICAL
- 路径：Rust stdin → dangerous → system
- 跨语言：YES

**测试用例 2：C → Rust → C 缓冲区溢出**

```c
// c_main.c
void process_data(char* data) {
    rust_wrapper(data);
}

// rust_wrapper.rs
#[no_mangle]
pub extern "C" fn rust_wrapper(data: *const i8) {
    let c_str = unsafe { std::ffi::CStr::from_ptr(data) };
    let str_slice = c_str.to_str().unwrap();
    unsafe { call_c(str_slice.as_ptr() as *const i8) };
}

extern "C" {
    fn call_c(data: *const i8);
}

// c_sink.c
void call_c(char* data) {
    char buf[64];
    strcpy(buf, data);  // 漏洞
}
```

**预期输出**：
- 类型：Buffer Overflow
- 严重性：HIGH
- 路径：C data → rust_wrapper → call_c → strcpy
- 跨语言：YES（两次）

#### 7.2 性能基准

| 项目规模 | 函数数 | FFI 边界数 | 分析时间 | 内存使用 |
|---------|-------|-----------|---------|---------|
| 小型     | <100  | <10       | <1s     | <100MB  |
| 中型     | 100-1K | 10-100    | 1-10s   | 100MB-1GB |
| 大型     | 1K-10K | 100-1K    | 10-60s  | 1GB-10GB |

#### 7.3 准确性指标

| 指标 | 目标值 |
|-----|--------|
| 真阳性率 | >80% |
| 假阳性率 | <20% |
| 漏报率 | <15% |
| 跨语言检测准确率 | >90% |

### 8. 风险和限制

#### 8.1 技术限制

- **指针别名**：不进行精确的指针别名分析
- **上下文敏感**：函数级污点传播，不是路径敏感
- **动态特性**：无法处理动态代码生成
- **间接调用**：间接调用的识别可能不准确

#### 8.2 误报和漏报

**误报原因**：
- 静态分析的保守性
- 缺少运行时信息
- 复杂的控制流

**漏报原因**：
- 静态分析的不完整性
- 隐式的数据流
- 第三方库代码

#### 8.3 缓解措施

- 提供误报反馈机制
- 支持自定义规则和例外
- 与运行时检测工具配合使用
- 持续更新规则库

## 总结

OmniScope 的目标是成为一个**实用的、CI/CD 可集成的 FFI 安全分析工具**，专注于**跨语言边界的污点传播和漏洞检测**。

**核心价值**：
1. 弥补现有工具在跨语言分析上的短板
2. 检测其他工具无法发现的跨语言安全漏洞
3. 易于集成到开发流程中

**差异化**：
- 支持**所有** LLVM 语言（不只是 Rust 和 C）
- 专注于**FFI 边界**安全问题
- **CI/CD 原生**支持

通过按照本计划实施，OmniScope 将成为一个真正有用的安全工具，帮助开发者及早发现和修复跨语言项目中的安全漏洞。