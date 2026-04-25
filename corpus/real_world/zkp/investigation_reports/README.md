# OmniScope 密码学库调查报告索引

**测试日期**: 2026-04-25
**测试版本**: v0.1.6
**测试范围**: ZKP 领域典型项目 + 主流密码学库

---

## 0. 重要反思

### 0.1 之前走偏了

之前的改进方向是**错误的**：

| 走偏方向 | 问题 |
|----------|------|
| Rust 通道模式识别 | 试图做语义分析，不是我们的定位 |
| Arc/Mutex 模式识别 | 同上 |
| 栈/堆区分逻辑 | 扫描整个 IR，而不是只扫 Escape Zone |
| 释放前/后访问追踪 | 同上 |
| 控制流敏感分析 | 同上 |
| 敏感数据流检测 | 同上 |

### 0.2 正确的方向

**Analyze only where language guarantees stop.**

| 方向 | 描述 |
|------|------|
| Zone Classifier | 标记 Safe Zone / Escape Zone |
| 跳过 Safe Zone | 语言已保证安全，不需要分析 |
| 只分析 Escape Zone | unsafe/FFI 边界才是重点 |

### 0.3 为什么之前走偏

1. **试图做语义分析** - 试图理解 Rust 的所有权、借用、生命周期
2. **扫描整个 IR** - 而不是只扫描 Escape Zone
3. **噪音来源** - stdlib/runtime 代码产生了大量误报

### 0.4 正确的方法

1. **Zone Classification** - 先分类，再分析
2. **Selective Analysis** - 只分析 Escape Zone
3. **High-Value Output** - 输出真正有价值的 bug

---

## 1. 测试项目汇总

| # | 项目 | 语言 | 报告 | UAF | 误报率 |
|---|------|------|------|-----|--------|
| 1 | **blst** | Rust + C | [blst.md](blst.md) | 185 | ~65% |
| 2 | **zkcrypto/bls12_381** | Rust | [zkcrypto_bls12_381.md](zkcrypto_bls12_381.md) | 1 | 100% |
| 3 | **ark-ff** | Rust | [ark_ff.md](ark_ff.md) | 0 | - |
| 4 | **libsodium** | C | [libsodium.md](libsodium.md) | 0 | - |
| 5 | **gnark-crypto** | Go (tinygo) | [gnark_crypto.md](gnark_crypto.md) | 2 | 100% |
| 6 | **ring** | Rust + C/asm | [ring.md](ring.md) | 10 | 100% |
| 7 | **botan** | C++ | [botan.md](botan.md) | 0 | - |
| 8 | **mbedtls** | C | [mbedtls.md](mbedtls.md) | 7 | 100% |
| 9 | **boringssl** | C++ | [boringssl.md](boringssl.md) | 7 | 100% |

**总计**: 9 个项目，212 个 UAF 报告，约 75% 误报率

---

## 2. 误报原因分析

### 2.1 根本原因

**我们扫描了不该扫描的区域**：

| 区域 | 占比 | 是否应该扫描 |
|------|------|-------------|
| Safe Zone (Rust safe fn) | ~70% | ❌ 不应该 |
| Runtime Internal (stdlib) | ~15% | ❌ 不应该 |
| Escape Zone (unsafe/FFI) | ~15% | ✅ 应该 |

### 2.2 误报分布

| 误报来源 | 占比 | 原因 |
|----------|------|------|
| drop_in_place | 40% | Rust 析构函数链，语言保证安全 |
| stdlib 内部 | 25% | 标准库代码，已充分测试 |
| channel/Arc | 15% | 共享所有权，语言保证安全 |
| 其他 | 20% | 需要进一步分析 |

---

## 3. 新方向：Zone Classification

### 3.1 核心思想

```
Safe Zone (跳过)     Escape Zone (分析)
     ↓                      ↓
  计数/忽略              深度分析
     ↓                      ↓
  减少噪音              高价值输出
```

### 3.2 Zone 定义

| Zone | 定义 | 处理方式 |
|------|------|----------|
| **safe** | 语言保证安全的代码 | 跳过或计数 |
| **unsafe** | 显式 escape 的代码 | 深度分析 |
| **ffi** | 跨语言边界 | 重点分析 |
| **runtime_internal** | stdlib/runtime | 跳过 |

### 3.3 预期效果

| 项目 | 当前分析函数 | 预期分析函数 | 减少比例 |
|------|-------------|-------------|----------|
| blst | 416 | ~50 | ~88% |
| ring | 410 | ~30 | ~93% |

---

## 4. 下一步计划

详见 [DEV_PLAN.md](../../plan/DEV_PLAN.md)

### Phase 1: Zone Classifier (Week 1)

- [x] 创建 `zone_classifier.zig`
- [ ] 编写单元测试
- [ ] 验证编译通过

### Phase 2: 集成到 Pass Pipeline (Week 2)

- [ ] 修改 PassContext 支持 Zone 过滤
- [ ] 修改 detectUseAfterFree 跳过 Safe Zone
- [ ] 验证分析量减少 > 80%

### Phase 3: Escape Zone 深分析 (Week 3-4)

- [ ] 实现 raw ptr lifetime 追踪
- [ ] 实现 callback escaping 检测
- [ ] 实现 ABI mismatch 检测

### Phase 4: 回归测试 (Week 5)

- [ ] blst 回归测试
- [ ] ring 回归测试
- [ ] 验证误报率 < 20%

---

## 5. 附录

### 5.1 相关文件

| 文件 | 描述 |
|------|------|
| [DEV_PLAN.md](../../plan/DEV_PLAN.md) | 开发计划 |
| [rules.md](../../plan/rules/rules.md) | 编码规范 |
| [skills.md](../../plan/rules/skills.md) | 开发技能 |

### 5.2 测试环境

| 项目 | 值 |
|------|-----|
| OmniScope 版本 | v0.1.6 |
| Zig 版本 | 0.15.2 |
| LLVM 版本 | 22 |
| 测试日期 | 2026-04-25 |
