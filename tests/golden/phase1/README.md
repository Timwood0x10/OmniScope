# Golden Output - Phase 1

## 用途

存放 **Phase 1（P1）完成后的** 分析结果 JSON 摘要，与 baseline 进行对比验证 P1 重构的正确性。

## Phase 1 目标范围

P1 阶段通常包含以下重构内容：
- 核心数据结构优化
- 分析引擎基础架构改进
- Issue 收集和报告机制重构
- 基础误报过滤逻辑增强

## 文件内容

```
phase1/
├── crc32fast.json          # P1 后 crc32fast 结果
├── xxhash.json             # P1 后 python-xxhash 结果
├── zstd_rs.json            # P1 后 zstd-rs 结果
├── go_sqlite3.json         # P1 后 go-sqlite3 结果
└── fft_demo.json           # P1 后 fft-demo 结果
```

## 对比基准

- **对比对象**: `../baseline/*.json`
- **预期变化**:
  - Issue 总数: 允许 ±15% 浮动
  - confirmed_issue 数量: 应保持稳定或减少
  - diagnostic 数量: 可能增加（更精细的分类）
  - 已知误报类型: 应有明显改善

## 验证标准

| 指标 | 通过条件 |
|------|----------|
| Issue 数量变化 | ≤ baseline × 1.15 且 ≥ baseline × 0.85 |
| Severity 分布 | Critical/High 级别不出现无解释的增长 |
| 新增 issue | 必须有合理的 root cause 说明 |
| 消失的 issue | 应记录为"误报消除"或"分析能力退化" |

## 使用时机

- P1 开发完成后、合并主分支前执行
- CI 中应包含自动化的 baseline ↔ phase1 对比检查
- 人工 review 差异报告
