# OmniScope 使用示例 (Examples)

> **版本**: v0.1.7 | **难度等级**: 🟢入门 → 🟡进阶 → 🔴高级
> **涵盖场景**: Rust FFI、C项目、CI/CD集成、自定义Pass

---

## 目录

1. [🟢 入门示例](#1-入门示例)
2. [🟡 进阶场景](#2-进阶场景)
3. [🔴 高级用法](#3-高级用法)
4. [🚀 CI/CD集成](#4-cicd集成)
5. [📊 结果解读](#5-结果解读)

---

## 1. 🟢 入门示例

### 1.1 分析单个Rust FFI文件

**目标**: 检测 ring 加密库中的Rust FFI安全问题

```bash
# Step 1: 准备输入文件（LLVM IR 或 bitcode）
cp corpus/real_world/other/ring.ll /tmp/ring.bc

# Step 2: 运行分析（基础模式）
./zig-out/bin/OmniScope /tmp/ring.bc

# 输出:
# [INFO] === OmniScope IR Analysis ===
# [INFO] File: /tmp/ring.bc
# [INFO] Loaded: 410 functions
# [INFO] LANG-DETECT: module language = rust, confidence = 95.0%
# ...
# [OMI-HIGH] PtrLifetime: analyzed 278 funcs, found 16 violations
# [PERF] Total time: 2136ms
```

**Step 3**: 获取结构化JSON输出

```bash
./zig-out/bin/OmniScope /tmp/ring.bc --json | jq '.summary'
```

```json
{
  "functions": 410,
  "issues": 16,
  "time_ms": 2136,
  "ffi_boundaries": 4252,
  "cross_language_edges": 5148
}
```

**Step 4**: 筛选特定类型的issue

```bash
# 只看 borrow_escape 类型（Rust特有）
./zig-out/bin/OmniScope /tmp/ring.bc --json \
  | jq '[.issues[] | select(.kind == "borrow_escape")]'

# 输出: 4 个 borrow_escape issues
```

### 1.2 分析C项目内存泄漏

**目标**: 检测 sqlite3 数据库引擎中的内存泄漏

```bash
# 准备文件
/opt/homebrew/opt/llvm@22/bin/llvm-as corpus/real_world/sqlite3.ll \
  -o /tmp/sqlite3.bc

# 运行分析
./zig-out/bin/OmniScope /tmp/sqlite3.bc --json > sqlite3_results.json

# 统计issue类型分布
cat sqlite3_results.json | jq '
{
  memory_leak: [.issues[] | select(.kind=="memory_leak")] | length,
  use_after_free: [.issues[] | select(.kind=="use_after_free")] | length,
  null_deref: [.issues[] | select(.kind=="null_dereference")] | length,
  tainted_path: [.issues[] | select(.kind=="tainted_path_to_sink")] | length
}'
```

```json
{
  "memory_leak": 69,
  "use_after_free": 0,
  "null_deref": 1,
  "tainted_path": 66
}
```

---

## 2. 🟡 进阶场景

### 2.1 批量分析整个语料库

**目标**: 自动化分析所有测试文件并生成汇总报告

```bash
#!/bin/bash
# batch_analysis.sh - 批量分析脚本

OUTPUT_DIR="outputs/batch_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

TOTAL_ISSUES=0
TOTAL_FUNCS=0

for ll in corpus/**/*.ll; do
  name=$(basename "$ll" .ll)
  
  # 转换为bitcode
  bcfile="/tmp/${name}.bc"
  /opt/homebrew/opt/llvm@22/bin/llvm-as "$ll" -o "$bcfile" 2>/dev/null
  
  if [ ! -f "$bcfile" ]; then
    echo "[SKIP] $name (conversion failed)"
    continue
  fi
  
  # 分析
  result=$(./zig-out/bin/OmniScope "$bcfile" --json 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    echo "$result" > "${OUTPUT_DIR}/${name}.json"
    
    issues=$(echo "$result" | jq -r '.summary.issues')
    funcs=$(echo "$result" | jq -r '.summary.functions')
    
    printf "[OK] %-30s funcs=%-6s issues=%s\n" "$name" "$funcs" "$issues"
    
    TOTAL_ISSUES=$((TOTAL_ISSUES + issues))
    TOTAL_FUNCS=$((TOTAL_FUNCS + funcs))
  else
    echo "[FAIL] $name"
  fi
done

echo ""
echo "========================================="
echo "  Batch Analysis Complete"
echo "  Total Functions: $TOTAL_FUNCS"
echo "  Total Issues:    $TOTAL_ISSUES"
echo "  Output:          $OUTPUT_DIR/"
echo "========================================="
```

运行：
```bash
chmod +x batch_analysis.sh && ./batch_analysis.sh
```

### 2.2 生成SARIF报告用于GitHub Code Scanning

```bash
# 分析并生成SARIF格式
./zig-out/bin/OmniScope /tmp/curl8.bc --sarif > curl8.sarif

# 查看SARIF内容（前50行）
head -50 curl8.sarif
```

创建GitHub Action工作流：

```yaml
# .github/workflows/omniscope-scan.yml
name: OmniScope Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  omniscope-analysis:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Zig
        uses: goto-bus-setup/setup-zig@v2
        with:
          version: 0.15.2
      
      - name: Build OmniScope
        run: |
          git clone https://github.com/your-org/OmniScope.git
          cd OmniScope
          zig build -Drelease-fast
      
      - name: Generate LLVM IR
        run: |
          # 示例：编译Rust项目为LLVM IR
          # cargo rustc --release -- --emit=llvm-ir -o target/lib.ll
          
          # 或者使用现有的 .ll 文件
          ls -la corpus/**/*.ll || echo "No .ll files found"
      
      - name: Run OmniScope Analysis
        id: analysis
        run: |
          cd OmniScope
          
          # 分析所有 .ll 文件
          for f in $(find ../corpus -name "*.ll"); do
            ./zig-out/bin/OmniScope "$f" --sarif >> results.sarif
          done
          
          # 统计结果
          TOTAL=$(jq '[.runs[].results[]] | length' results.sarif)
          echo "::notice title=OmniScope::Found $TOTAL security issues"
          
          # 上传artifact
          echo "total_issues=$TOTAL" >> $GITHUB_OUTPUT
      
      - name: Upload SARIF to GitHub Code Scanning
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif-file: OmniScope/results.sarif
        if: always()
      
      - name: Summary
        run: |
          echo "## 🔍 OmniScope Analysis Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "- **Total Issues Found**: ${{ steps.analysis.outputs.total_issues }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Analysis Time**: $(date)" >> $GITHUB_STEP_SUMMARY
          echo "- **Report Location**: \`results.sarif\`" >> $GITHUB_STEP_SUMMARY
```

### 2.3 自定义配置文件

创建 `omniscope.config.json`:

```json
{
  "analysis": {
    "enable_passes": ["PtrLifetime", "TaintAnalysis", "RustFFIAuditor"],
    "taint_depth": 5,
    "max_functions_per_module": 3000
  },
  "rust_ffi": {
    "safe_zone_detection": true,
    "ownership_transfer_detection": true,
    "borrow_escape_detection": true
  },
  "noise_filter": {
    "min_confidence_threshold": 0.70,
    "suppress_stdlib": true,
    "suppress_test_code": true
  },
  "output": {
    "formats": ["json", "console"],
    "verbose": true
  }
}
```

使用自定义配置：

```bash
./zig-out/bin/OmniScope input.bc --config omniscope.config.json
```

---

## 3. 🔴 高级用法

### 3.1 编写自定义Pass

**目标**: 创建一个检测未初始化变量使用的Pass

```zig
// src/pass/analysis/uninit_var.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Issue = @import("../../diag/issue.zig").Issue;

pub const UninitVarDetector = struct {
    allocator: Allocator,
    stats: Stats,

    const Stats = struct {
        functions_analyzed: usize = 0,
        issues_found: usize = 0,
    };

    pub fn init(allocator: Allocator) UninitVarDetector {
        return .{ .allocator = allocator, .stats = .{} };
    }

    pub fn run(
        self: *UninitVarDetector,
        module: anytype, // LLVMModule type
        ctx: anytype,   // Context type
        diag: anytype,  // Diagnostics type
    ) ![]Issue {
        var issues = std.ArrayList(Issue).init(self.allocator);
        
        // 遍历所有函数
        for (module.functions()) |func| {
            self.stats.functions_analyzed += 1;
            
            // 查找alloca指令（栈分配）
            for (func.instructions()) |inst| {
                if (inst.isAlloca() and inst.hasNoInit()) {
                    // 检查是否在使用前被赋值
                    if (!self.isInitializedBeforeUse(inst)) {
                        try issues.append(Issue.init(
                            .uninitialized_variable,
                            "Use of uninitialized variable",
                            Issue.Location.init(func.name),
                            .medium,
                            0.75,
                        ));
                        self.stats.issues_found += 1;
                    }
                }
            }
        }

        return issues.toOwnedSlice();
    }

    fn isInitializedBeforeUse(self: *UninitVarDetector, alloca_inst: anytype) bool {
        // 实现数据流分析逻辑...
        // 检查从alloca到use之间是否有store指令
        return false; // 简化实现
    }

    pub fn getStats(self: *const UninitVarDetector) Stats {
        return self.stats;
    }
};
```

注册到OmniScope：

```zig
// 在 main.zig 中注册新Pass
const uninit_detector = UninitVarDetector.init(allocator);

// 添加到pass列表
var passes = std.ArrayList(Pass).init(allocator);
try passes.append(.{
    .name = "UninitVarDetector",
    .description = "Detect uninitialized variable usage",
    .runFn = uninit_detector.run,
});
```

### 3.2 集成到构建系统

**Zig项目集成**:

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 主程序
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // 添加OmniScope分析步骤
    const omniscope_step = b.step("omniscope", "Run OmniScope static analysis");
    omniscope_step.dependOn(&exe.step);

    // 编译为LLVM IR
    const ll_file = exe.addAsmFile(.{
        .emit_llvm_ir = true,
    });

    // 运行Omnicope
    const analyze_cmd = b.addSystemCommand(&.{
        "./zig-out/bin/OmniScope",
    });
    analyze_cmd.addFileArg(ll_file.getOutput());
    analyze_cmd.addArg("--json");
    analyze_cmd.addArg(&.{"--output", "omniscope-results.json"});
    
    omniscope_step.dependOn(&analyze_cmd.step);
}
```

运行：

```bash
zig build omniscope
cat omniscope-results.json | jq '.issues'
```

### 3.3 与其他工具链集成

#### Clang + OmniScope 工作流

```bash
# 1. C/C++源码编译为LLVM IR
clang -S -emit-llvm -O0 -g my_program.c -o my_program.ll

# 2. 运行OmniScope分析
./zig-out/bin/OmniScope my_program.ll --json > analysis.json

# 3. 过滤CRITICAL和HIGH问题
jq '[.issues[] | select(.severity=="critical" or .severity=="high")]' \
  analysis.json > critical_issues.json

# 4. 可选：继续用Clang Static Analyzer对比
scan-build clang my_program.c
```

#### Rust + OmniScope 工作流

```bash
# 1. Rust源码编译为LLVM IR
cargo rustc --lib --release -- \
  --emit=llvm-ir \
  --crate-type=staticlib \
  -o my_rust_lib.ll

# 2. 运行OmniScope（重点检测FFI边界）
./zig-out/bin/OmniScope my_rust_lib.ll --json > rust_analysis.json

# 3. 提取Rust特有的borrow_escape问题
jq '[.issues[] | select(.kind=="borrow_escape")]' \
  rust_analysis.json > borrow_escapes.json

# 4. 可选：与Miri对比
cargo +nightly miri test
```

---

## 4. 📊 结果解读

### 4.1 理解Issue置信度

| 置信度范围 | 含义 | 建议操作 |
|-----------|------|----------|
| **HIGH (>0.90)** | 几乎确定是真实漏洞 | ⚠️ **立即修复** |
| **MEDIUM (0.70-0.90)** | 很可能是真实问题 | 🔍 **人工确认后修复** |
| **LOW (0.50-0.70)** | 可能是误报 | 📝 **记录并定期审查** |
| **HEURISTIC (<0.50)** | 启发式规则检出 | ℹ️ **了解即可，低优先级** |

### 4.2 典型误报模式及处理

#### 误报1: 错误路径中的泄漏

```c
// OmniScope报告: memory_leak in handle_request()
int handle_request(char* data) {
    char* buffer = malloc(1024);  // ← 报告此处可能泄漏
    
    if (!buffer) return -1;         // 正确：错误返回
    
    process(buffer);
    free(buffer);                  // 正常释放
    return 0;
}

// ✅ 实际上代码正确（错误路径会终止程序）
// 处理方式: 降低优先级或添加注释抑制
```

**解决方案**: 
- 如果错误路径会调用 `exit()` 或 `abort()`，可以忽略此警告
- 配置 `min_confidence_threshold: 0.80` 过滤掉低置信度报告

#### 误报2: Safe Zone中的借用检查

```rust
// OmniScope报告: borrow_escape in safe_function()
fn safe_function(data: &mut Vec<u8>) {
    let slice = &data[0..10];  // ← 报告借用逃逸
    
    process_slice(slice);       // 但process_slice是纯Rust函数！
}

// ✅ 这是Safe Zone内的正常借用，编译器已保证安全
// OmniScope应该跳过此类代码（Zone Classification）
```

**解决方案**: 确保 `safe_zone_detection` 配置开启（默认启用）

### 4.3 生成可执行报告

```python
#!/usr/bin/env python3
"""generate_html_report.py - 将JSON结果转换为HTML报告"""

import json
import sys
from datetime import datetime
from jinja2 import Template

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>OmniScope Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .critical { color: #d32f2f; background: #ffebee; padding: 5px; border-radius: 3px; }
        .high { color: #f57c00; background: #fff3e0; padding: 5px; border-radius: 3px; }
        .medium { color: #fbc02d; background: #fffde7; padding: 5px; border-radius: 3px; }
        .low { color: #388e3c; background: #e8f5e9; padding: 5px; border-radius: 3px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f5f5f5; }
        .summary { background: #e3f2fd; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>🔍 OmniScope Security Analysis Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Date:</strong> {{ date }}</p>
        <p><strong>File:</strong> {{ file }}</p>
        <p><strong>Total Issues:</strong> {{ total_issues }}</p>
        <table>
            <tr><th>Critical</th><th>High</th><th>Medium</th><th>Low</th></tr>
            <tr>
                <td>{{ critical_count }}</td>
                <td>{{ high_count }}</td>
                <td>{{ medium_count }}</td>
                <td>{{ low_count }}</td>
            </tr>
        </table>
    </div>

    <h2>Issues Detail</h2>
    <table>
        <tr>
            <th>ID</th>
            <th>Type</th>
            <th>Severity</th>
            <th>Confidence</th>
            <th>Function</th>
            <th>Message</th>
        </tr>
        {% for issue in issues %}
        <tr>
            <td>{{ issue.id }}</td>
            <td>{{ issue.kind }}</td>
            <td class="{{ issue.severity }}">{{ issue.severity }}</td>
            <td>{{ "%.2f"|format(issue.confidence_score) }}</td>
            <td>{{ issue.location.function }}</td>
            <td>{{ issue.message }}</td>
        </tr>
        {% endfor %}
    </table>
</body>
</html>
"""

def generate_report(json_file: str, output_html: str):
    with open(json_file) as f:
        data = json.load(f)

    issues = data.get('issues', [])
    
    severity_counts = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0}
    for issue in issues:
        sev = issue['severity']
        if sev in severity_counts:
            severity_counts[sev] += 1

    template = Template(HTML_TEMPLATE)
    html_content = template.render(
        date=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        file=data.get('input_file', 'unknown'),
        total_issues=len(issues),
        critical_counts=severity_counts['critical'],
        high_count=severity_counts['high'],
        medium_count=severity_counts['medium'],
        low_count=severity_counts['low'],
        issues=issues
    )

    with open(output_html, 'w') as f:
        f.write(html_content)

    print(f"✅ Report generated: {output_html}")
    print(f"   Total issues: {len(issues)}")
    print(f"   Critical: {severity_counts['critical']}, High: {severity_counts['high']}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.json> <output.html>")
        sys.exit(1)

    generate_report(sys.argv[1], sys.argv[2])
```

使用：

```bash
pip install jinja2
python generate_html_report.py sqlite3_results.html report.html
open report.html  # macOS/Linux
start report.html  # Windows
```

---

## 5. 最佳实践清单

### ✅ 推荐做法

- [ ] **在CI/CD中集成** - 每次PR自动运行
- [ ] **设置合理的阈值** - `min_confidence_threshold: 0.70`
- [ ] **关注CRITICAL/HIGH** - 优先修复高严重级别问题
- [ ] **结合人工审查** - MEDIUM级别需开发者确认
- [ ] **版本控制报告** - 保存每次分析的JSON结果
- [ ] **监控趋势** - 追踪issues数量变化
- [ ] **定期更新corpus** - 覆盖新的代码模式

### ❌ 常见错误

- ❌ 只依赖编译器警告（无法检测跨语言问题）
- ❌ 忽略所有LOW级别（可能隐藏真实风险）
- ❌ 在Debug模式下分析大型项目（使用ReleaseFast）
- ❌ 不配置噪声过滤器（产生大量FP）
- ❌ 手动审查所有误报（浪费精力，应优化规则）

---

*文档版本*: v0.1.7 | *最后更新*: 2026-05-07
*更多示例*: 查看 `corpus/` 目录下的42个真实世界测试文件
*反馈*: 请提交 [GitHub Issues](https://github.com/your-org/OmniScope/issues) 或 Discussions
