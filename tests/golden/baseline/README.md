# Golden Output - Baseline (基线)

## 用途

存放 **重构前** 的分析结果 JSON 摘要，作为后续所有阶段的对比基准。

## 文件内容

每个基线项目对应一个 JSON 文件：

```
baseline/
├── crc32fast.json          # crc32fast 基线结果
├── xxhash.json             # python-xxhash 基线结果
├── zstd_rs.json            # zstd-rs 基线结果
├── go_sqlite3.json         # go-sqlite3 基线结果
└── fft_demo.json           # fft-demo 基线结果
```

## JSON 格式规范

```json
{
  "metadata": {
    "project": "crc32fast",
    "version": "1.0.0",
    "timestamp": "2026-05-26T00:00:00Z",
    "omniscope_version": "0.1.0",
    "analysis_options": {
      "input_file": "crc32fast.bc",
      "language": "rust",
      "ffi_mode": false,
      "cross_language": null
    }
  },
  "summary": {
    "total_issues": 12,
    "by_severity": {
      "critical": 2,
      "high": 4,
      "medium": 4,
      "low": 2
    },
    "by_category": {
      "buffer_overflow": 5,
      "use_after_free": 3,
      "null_deref": 2,
      "memory_leak": 2
    },
    "false_positive_estimate": 3
  },
  "issues": [
    {
      "id": "ISSUE-001",
      "type": "buffer_overflow",
      "severity": "high",
      "classification": "confirmed_issue",
      "location": {
        "file": "src/lib.rs",
        "line": 142,
        "function": "compute_table"
      },
      "description": "Potential buffer overflow in table computation loop",
      "confidence": 0.92
    }
  ]
}
```

## 使用说明

- **生成**: 在重构开始前，对 5 个基线项目执行分析并保存输出至此目录
- **对比**: 后续阶段（phase1, phase2...）的结果将与此目录中的文件进行 diff
- **更新规则**:
  - 仅在重大版本升级或分析方法根本性变更时才允许更新基线
  - 更新需在 PR 中明确说明变化原因，经 review 后合并

## 注意事项

⚠️ 此目录下的文件不应被日常开发修改，仅用于回归测试对比。
