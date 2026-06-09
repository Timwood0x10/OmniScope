# Golden Output - Phase 2

## 用途

存放 **Phase 2（P2）完成后的** 分析结果 JSON 摘要，与 phase1 和 baseline 进行双重对比。

## Phase 2 目标范围

P2 阶段通常包含以下增强内容：
- FFI/Cross-language 分析能力提升
- 资源契约（Resource Contract）推断引擎
- 更精确的误报抑制机制
- SARIF 输出格式优化
- 性能优化（大文件分析速度提升）

## 文件内容

```
phase2/
├── crc32fast.json          # P2 后 crc32fast 结果
├── xxhash.json             # P2 后 python-xxhash 结果
├── zstd_rs.json            # P2 后 zstd-rs 结果（重点：FFI 改进）
├── go_sqlite3.json         # P2 后 go-sqlite3 结果（重点：CGO 改进）
└── fft_demo.json           # P2 后 fft-demo 结果（重点：跨语言改进）
```

## 对比基准

- **主要对比**: `../phase1/*.json`（直接前序阶段）
- **次要对比**: `../baseline/*.json`（原始基线）
- **预期变化**:
  - FFI 相关项目（zstd-rs, go-sqlite3）的 confirmed issue 准确率应提升 20%+
  - 跨语言 aliasing 误报（fft-demo）应显著减少
  - 整体误报率下降目标: 30%+

## 重点验证项

### FFI 分析改进 (zstd-rs, go-sqlite3)
- [ ] 内存所有权模型判断准确率 > 85%
- [ ] C 回调函数签名匹配不再产生误报
- [ ] 跨边界 buffer size 推断正确性提升

### 资源契约推断
- [ ] 生命周期相关的 use-after-free 误报减少
- [ ] 资源释放点识别准确率 > 90%
- [ ] 自定义 allocator 场景支持度提升

### 性能指标
- [ ] 大文件（go-sqlite3 ~40 issues）分析时间 < 30s
- [ ] 内存占用峰值 < 2GB

## 使用时机

- P2 开发完成后执行全量基线回归测试
- 包含自动化对比 + 人工关键 case review
- 作为发布候选版本的验证依据
