# OmniScope HTML 面板集成设计方案

> 设计日期: 2026-04-16
> 目标: 为 OmniScope 添加交互式 Web 可视化面板

---

## 一、总体架构

### 1.1 设计原则

- **职责分离** — Zig 端只负责数据生成（JSON），前端只负责可视化
- **复用现有功能** — 使用已有的 `--output-format json`，无需修改 Zig 代码
- **前端独立** — HTML 文件可独立分发，不依赖 Zig 编译
- **可离线使用** — 所有资源内嵌，无需外部网络

### 1.2 数据流架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    OmniScope 分析流程                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  OutputFormatter.format(OutputFormat.json)                        │
│  （已有功能，无需修改）                                            │
│  输出: report.json                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  用户用浏览器打开 viewer.html（独立前端文件）                      │
│  - 选择或拖入 report.json                                         │
│  - JS 解析 JSON 并渲染                                            │
│  - D3.js / ECharts 可视化                                         │
└─────────────────────────────────────────────────────────────────┘
```

**优势**:
- Zig 端零改动，只扩展 JSON 字段即可
- 前端可独立迭代，不依赖 Zig 编译
- 用户可用任何工具处理 JSON（Python、jq 等）
- 符合 Unix 哲学：数据与展示分离

---

## 二、数据结构设计

### 2.1 扩展 `AnalysisResult`（Zig 端）

当前 `AnalysisResult` 已有基础字段，需要扩展以支持可视化：

```zig
pub const AnalysisResult = struct {
    // 现有字段
    vulnerabilities: []const Vulnerability,
    total_files: u32,
    total_functions: u32,
    ffi_matches: u32,

    // 新增字段（用于可视化）
    execution_time_ns: u64,           // 分析耗时
    metadata: Metadata,               // 元数据
    call_graph: ?[]const CallGraphNode, // 可选：调用图数据
    taint_paths: ?[]const TaintPath,   // 可选：污点路径
};

pub const Metadata = struct {
    timestamp: i64,                   // Unix 时间戳
    omniscope_version: []const u8,    // 版本号
    llvm_version: []const u8,         // LLVM 版本
    scan_id: []const u8,              // 唯一扫描 ID（UUID）
};

pub const CallGraphNode = struct {
    id: u32,
    name: []const u8,
    kind: []const u8,                 // "internal" | "libc" | "external_unknown"
    is_external: bool,
    is_tainted: bool,
    callers: []const u32,             // 调用者 ID 列表
    callees: []const u32,             // 被调用者 ID 列表
};

pub const TaintPath = struct {
    source_id: u32,
    sink_id: u32,
    path: []const u32,                // 节点 ID 序列
    risk_level: []const u8,           // "critical" | "high" | "medium" | "low"
};
```

### 2.2 JSON Schema（传输格式）

```json
{
  "metadata": {
    "timestamp": 1713225600,
    "version": "1.0.0",
    "llvm_version": "22.1.3",
    "scan_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "summary": {
    "total_files": 3,
    "total_functions": 127,
    "vulnerabilities_count": 5,
    "ffi_matches": 12,
    "execution_time_ms": 1234
  },
  "vulnerabilities": [
    {
      "id": 0,
      "type": "command_injection",
      "severity": "critical",
      "cwe_id": 78,
      "description": "Command injection: tainted data reaches dangerous function",
      "source_location": {
        "function": "process_user_input",
        "file": "rust.bc",
        "line": null
      },
      "sink_location": {
        "function": "system_wrapper",
        "file": "c.bc",
        "line": null
      },
      "taint_path": [10, 25, 42, 89],
      "risk_level": "critical"
    }
  ],
  "call_graph": {
    "nodes": [
      {
        "id": 0,
        "name": "main",
        "kind": "internal",
        "is_external": false,
        "is_tainted": true
      }
    ],
    "edges": [
      {
        "caller": 0,
        "callee": 1,
        "is_ffi": false
      }
    ]
  },
  "ffi_boundaries": [
    {
      "id": 0,
      "caller": "rust_func",
      "callee": "c_func",
      "kind": "rust_ffi"
    }
  ]
}
```

---

## 三、集成方式选择

### 3.1 方案对比

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **静态 HTML + JSON** | 零依赖、可离线、易分享 | 无实时更新、交互受限 | ⭐⭐⭐⭐⭐ |
| **嵌入式 HTTP 服务器** | 可实时刷新、支持多用户 | 需要维护后端、增加复杂度 | ⭐⭐⭐ |
| **VS Code 扩展** | 深度集成 IDE、无需浏览器 | 仅限 VS Code 用户 | ⭐⭐⭐⭐ |

**推荐**: 采用 **静态 HTML + JSON** 作为第一阶段实现，原因：
1. 当前项目已有 `--output-file` 支持，自然扩展
2. 无需额外依赖，符合 Zig 的零哲学
3. 可直接拖入浏览器查看，降低使用门槛
4. 后续可轻松升级为动态服务

### 3.2 实现方式

**Zig 端**:
- 新增 `OutputFormat.html` 枚举值
- 实现 `HTMLFormatter` 模块
- 输出单文件 HTML（内嵌 JSON 数据作为 `<script type="application/json">`）

**前端技术栈**:
- **D3.js** (v7) — 用于调用图、污点路径可视化
- **ECharts** (可选) — 用于统计图表（饼图、柱状图）
- **原生 JS** — 无框架，保持轻量

---

## 四、文件结构

```
# Zig 端（仅需扩展 JSON 字段）
src/output/
└── formatter.zig          # 现有格式化器，扩展 AnalysisResult 字段

# 前端（独立项目，可放在 web/ 或 docs/ 目录）
web/
├── viewer.html            # 主文件（内嵌 CSS/JS）
├── README.md              # 使用说明
└── examples/              # 示例 JSON 文件
    └── sample_report.json
```

**输出目录**（运行时生成）:
```
# OmniScope 输出
zig-out/
└── report.json            # Zig 端生成的 JSON（已有功能）

# 用户使用
./omniscope target.bc --output-format json --output-file report.json
# 然后用浏览器打开 viewer.html，选择 report.json
```

---

## 五、实施步骤

### Phase 1: Zig 端扩展 JSON 字段（0.5 天）

**目标**: 扩展 `AnalysisResult` 结构以支持可视化

1. **扩展 `AnalysisResult` 结构**
   ```zig
   pub const AnalysisResult = struct {
       // 现有字段
       vulnerabilities: []const Vulnerability,
       total_files: u32,
       total_functions: u32,
       ffi_matches: u32,

       // 新增字段
       execution_time_ns: u64,
       metadata: Metadata,
       call_graph: ?[]const CallGraphNode,
       taint_paths: ?[]const TaintPath,
   };
   ```

2. **验证 JSON 输出**
   ```bash
   ./omniscope target.bc --output-format json --output-file report.json
   cat report.json | jq .  # 验证格式正确
   ```

### Phase 2: 前端基础框架（2-3 天）

**目标**: 创建独立的 viewer.html，支持加载 JSON

1. **创建 viewer.html**
   ```html
   <!DOCTYPE html>
   <html>
   <head>
       <title>OmniScope Report Viewer</title>
       <style>
           /* 内嵌 CSS */
       </style>
   </head>
   <body>
       <input type="file" id="json-file" accept=".json">
       <div id="app"></div>
       <script>
           // 内嵌 JS
           document.getElementById('json-file').addEventListener('change', loadJSON);
           function loadJSON(e) {
               const file = e.target.files[0];
               const reader = new FileReader();
               reader.onload = (e) => {
                   const data = JSON.parse(e.target.result);
                   renderApp(data);
               };
               reader.readAsText(file);
           }
       </script>
   </body>
   </html>
   ```

2. **测试加载功能**
   - 用浏览器打开 viewer.html
   - 选择 report.json
   - 验证数据正确解析

### Phase 3: 可视化组件（3-4 天）

**目标**: 添加交互式图表

1. **概览仪表板**
   - 漏洞总数（按严重程度分色）
   - FFI 边界数量
   - 分析耗时
   - 文件/函数统计

2. **漏洞列表**
   - 表格形式展示
   - 可按严重程度、类型筛选
   - 点击展开详情

3. **调用图可视化** (D3.js)
   - 力导向图布局
   - 节点着色（内部/外部/FFI）
   - 污染节点高亮
   - 点击节点查看详情

4. **污点路径可视化**
   - 路径动画展示
   - 源 → ... → 汇
   - 跨语言边界标记

### Phase 4: 高级功能（可选，3-4 天）

**目标**: 增强交互性和实用性

1. **对比模式**
   - 支持加载多个报告
   - 对比不同时间的扫描结果
   - 高亮新增/修复的漏洞

2. **导出功能**
   - 导出为 PDF
   - 导出为 CSV（用于 Excel 分析）

3. **注释系统**
   - 允许用户添加注释
   - 保存到 LocalStorage

---

## 六、代码示例

### 6.1 Zig 端：扩展 AnalysisResult

```zig
// src/output/formatter.zig

pub const AnalysisResult = struct {
    // 现有字段
    vulnerabilities: []const Vulnerability,
    total_files: u32,
    total_functions: u32,
    ffi_matches: u32,

    // 新增字段
    execution_time_ns: u64,
    metadata: Metadata,
    call_graph: ?[]const CallGraphNode,
    taint_paths: ?[]const TaintPath,
};

pub const Metadata = struct {
    timestamp: i64,
    omniscope_version: []const u8,
    llvm_version: []const u8,
    scan_id: []const u8,
};

pub const CallGraphNode = struct {
    id: u32,
    name: []const u8,
    kind: []const u8,
    is_external: bool,
    is_tainted: bool,
    callers: []const u32,
    callees: []const u32,
};
```

### 6.2 前端：D3.js 调用图示例

```javascript
// src/output/html/scripts.js

function renderCallGraph(data) {
    const width = 800;
    const height = 600;

    const simulation = d3.forceSimulation(data.call_graph.nodes)
        .force("link", d3.forceLink(data.call_graph.edges)
            .id(d => d.id)
            .distance(100))
        .force("charge", d3.forceManyBody().strength(-300))
        .force("center", d3.forceCenter(width / 2, height / 2));

    const svg = d3.select("#call-graph")
        .append("svg")
        .attr("width", width)
        .attr("height", height);

    // 绘制边
    const link = svg.append("g")
        .selectAll("line")
        .data(data.call_graph.edges)
        .enter().append("line")
        .attr("stroke", "#999")
        .attr("stroke-opacity", 0.6)
        .attr("stroke-width", d => d.is_ffi ? 3 : 1);

    // 绘制节点
    const node = svg.append("g")
        .selectAll("circle")
        .data(data.call_graph.nodes)
        .enter().append("circle")
        .attr("r", 8)
        .attr("fill", d => {
            if (d.is_tainted) return "#ff6b6b";  // 红色：污染
            if (d.kind === "external_unknown") return "#ffd93d";  // 黄色：FFI
            if (d.kind === "libc") return "#6bcb77";  // 绿色：可信
            return "#4d96ff";  // 蓝色：内部
        })
        .call(d3.drag()
            .on("start", dragstarted)
            .on("drag", dragged)
            .on("end", dragended));

    simulation.on("tick", () => {
        link
            .attr("x1", d => d.source.x)
            .attr("y1", d => d.source.y)
            .attr("x2", d => d.target.x)
            .attr("y2", d => d.target.y);

        node
            .attr("cx", d => d.x)
            .attr("cy", d => d.y);
    });
}
```

---

## 七、使用流程

### 7.1 命令行使用

```bash
# 步骤 1: 生成 JSON 报告
./omniscope rust.bc c.bc --output-format json --output-file report.json

# 步骤 2: 用浏览器打开 viewer.html，选择 report.json
open web/viewer.html  # macOS
# 或直接用浏览器打开 web/viewer.html
```

### 7.2 CI/CD 集成

```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build OmniScope
        run: zig build
      - name: Run analysis
        run: ./zig-out/bin/OmniScope target.bc --output-format json --output-file report.json
      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: security-report
          path: report.json
```

---

## 八、后续扩展方向

1. **实时模式** — 添加 `omniscope serve` 命令，启动 HTTP 服务器
2. **VS Code 扩展** — 直接在 IDE 中查看结果
3. **LSP 集成** — 实时显示漏洞标记（已有 `src/output/lsp.zig`）
4. **数据库存储** — 将历史扫描结果存入 SQLite，支持趋势分析
5. **协作功能** — 添加注释、指派责任人、追踪修复状态

---

## 九、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 前端性能问题（大 IR） | 中 | 使用虚拟滚动、分页加载 |
| JSON 序列化失败 | 低 | 添加错误处理，降级为 text 输出 |
| 浏览器兼容性 | 低 | 使用现代浏览器 API，添加 Polyfill |
| XSS 攻击（注入数据） | 低 | JSON 序列化自动转义，避免 innerHTML |

---

## 十、总结

**推荐路线图**:
1. **Week 1**: 实现 Phase 1（扩展 JSON 字段）+ Phase 2（前端基础框架）
2. **Week 2**: 实现 Phase 3（可视化组件）
3. **Week 3+**: 根据反馈决定是否实现 Phase 4

**预期收益**:
- Zig 端零改动（只需扩展 JSON 字段）
- 前端独立迭代，不依赖 Zig 编译
- 提升漏洞分析效率 50%+（交互式探索 vs 文本阅读）
- 降低团队协作成本（共享 JSON + viewer.html）
- 符合 Unix 哲学：数据与展示分离
