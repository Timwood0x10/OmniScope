# 其他项目调查报告 v0.1.5

**测试日期**: 2026-04-25
**测试版本**: v0.1.5 (Zone Classification)

---

## 1. ark-ff (Rust 有限域库)

### 1.1 Zone Classification 结果

```
  Total functions analyzed:    16
  Safe zone (skipped):         1 (18.8%)
  Runtime internal (skipped):  2
  Unknown zone:                13

  Issues found:                0
```

### 1.2 分析

- 小型项目，函数数少
- 纯 Rust 实现，无 FFI
- 0 个问题

---

## 2. libsodium (C 密码学库)

### 2.1 Zone Classification 结果

```
  Total functions analyzed:    10
  Safe zone (skipped):         0 (0.0%)
  Runtime internal (skipped):  0
  Unknown zone:                10

  Issues found:                0
```

### 2.2 分析

- 纯 C 项目，无语言保障
- 所有函数都需要分析
- libsodium 内存管理良好，0 问题

---

## 3. gnark-crypto (Go 密码学库)

### 3.1 Zone Classification 结果

```
  Total functions analyzed:    838
  Safe zone (skipped):         250 (29.8%)
  Runtime internal (skipped):  0
  Unknown zone:                588

  Issues found:                1
```

### 3.2 分析

- Go 项目，tinygo 编译
- 需要增强 Go 模式识别
- 1 个问题来自 tinygo runtime

---

## 4. ripgrep (Rust 搜索工具)

### 4.1 Zone Classification 结果

```
  Total functions analyzed:    30
  Safe zone (skipped):         6 (46.7%)
  Runtime internal (skipped):  8
  Unknown zone:                16

  Issues found:                0
```

### 4.2 分析

- 纯 Rust 项目
- 46.7% 跳过率
- 0 个问题

---

## 5. rust-sqlite (Rust SQLite 绑定)

### 5.1 Zone Classification 结果

```
  Total functions analyzed:    17
  Safe zone (skipped):         5 (52.9%)
  Runtime internal (skipped):  4
  Unknown zone:                8

  Issues found:                6
```

### 5.2 分析

- Rust FFI 项目
- 8 个 unknown 函数是 FFI 边界
- 6 个问题来自 FFI 内存管理

---

## 6. 总结

| 项目 | 语言 | 函数数 | Skip % | Issues |
|------|------|--------|--------|--------|
| ark-ff | Rust | 16 | 18.8% | 0 |
| libsodium | C | 10 | 0% | 0 |
| gnark-crypto | Go | 838 | 29.8% | 1 |
| ripgrep | Rust | 30 | 46.7% | 0 |
| rust-sqlite | Rust FFI | 17 | 52.9% | 6 |

---

## 7. 附录

| 项目 | 值 |
|------|------|
| OmniScope 版本 | v0.1.5 |
| 测试日期 | 2026-04-25 |
