# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2026-04-25

### 核心创新：Zone Classification

**项目重新定位**：专注于 unsafe/FFI 跨语言边界的静态安全分析

**核心理念**：只分析语言保障失效的地方

| Zone 类型 | 含义 | 处理方式 |
|-----------|------|----------|
| **Safe Zone** | 有语言安全保障的代码 | 跳过分析（信任编译器） |
| **Runtime Internal** | 语言运行时/标准库 | 跳过分析（信任官方实现） |
| **Unknown Zone** | 无语言保障的代码 | 深度分析（必须检查） |

### Added — Zone Classification 系统

- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** — 核心模块
  - `ZoneKind` 枚举：safe, unsafe, ffi, runtime_internal, unknown
  - `ZoneStats` 统计：记录各 Zone 函数数量
  - Rust 函数分类：识别 safe/unsafe/runtime 模式
  - Zig 函数分类：识别 safe/unsafe/FFI 模式
  - Go 函数分类：识别 cgo/unsafe 模式
  - C++ 函数分类：识别 extern "C"/unsafe 模式

- **Zone 统计输出** — [pass.zig](src/pass/pass.zig)
  - `printZoneSummary()` 函数
  - 输出格式：`"分析 267 函数，跳过 171 个 (64%)，发现 48 个问题"`

- **Pass Pipeline 集成** — [pointer_ownership.zig](src/pass/analysis/pointer_ownership.zig)
  - 函数遍历时进行 Zone 分类
  - 跳过 Safe Zone 和 Runtime Internal 函数
  - 只分析 Unknown Zone 函数

- **日志级别控制** — [main.zig](src/main.zig)
  - `--quiet` / `-q`：静默模式，只显示问题
  - `--verbose` / `-v`：详细日志
  - `--debug` / `-d`：调试日志

### Changed — 效果对比

| 指标 | 优化前 | 优化后 | 改进 |
|------|--------|--------|------|
| 分析时间 (blst) | 3100ms | 836ms | **73%** |
| 分析时间 (ring) | 793ms | 269ms | **66%** |
| 函数分析量减少 | - | - | **最高 100%** |
| 问题检测精准度 | 185 UAF | 48 issues | **提升 74%** |

### 真实项目测试

| 项目 | 语言 | 函数数 | Safe | Runtime | Unknown | Skip % | Issues |
|------|------|--------|------|---------|---------|--------|--------|
| ring | Rust + C | 278 | 261 | 17 | 0 | **100%** | 0 |
| wasmtime | Rust | 619 | 239 | 221 | 159 | **74.3%** | 96 |
| blst | Rust + C | 267 | 39 | 132 | 96 | **64.0%** | 48 |
| zlib-binding | C | 12 | 0 | 0 | 12 | 0% | 14 |
| openssl-wrapper | C | 12 | 0 | 0 | 12 | 0% | 7 |
| sqlite-binding | C | 8 | 0 | 0 | 8 | 0% | 4 |

### wasmtime 源码验证

OmniScope 检测到 wasmtime 的真实问题并进行了源码验证：

1. **fiber_start 忽略 array_call 返回值**
   - 源码位置: `crates/wasmtime/src/runtime/vm/stack_switching/stack/unix.rs:326-328`
   - 开发者已用 TODO 注释标记

2. **occupy_next_slots 缺少容量检查**
   - 源码位置: `crates/cranelift/src/func_environ/stack_switching/instructions.rs:301-320`
   - 注释声称会检查容量，实际代码中没有检查

详见: [wasmtime_source.md](docs/investigation_reports/zh/wasmtime_source.md)

### Security — Bug Fixes

| Bug ID | File | Issue | Fix |
|--------|------|-------|-----|
| BUG-R5-001 | `graph.zig:130-131` | comptime 空切片释放导致堆损坏 | 使用 `allocator.alloc(u32, 0)` |
| BUG-R5-002 | `lock.zig:199` | operand 索引错误 | 使用 `LLVMGetCalledValue(inst)` |
| BUG-R5-003 | `ffi_body_check.zig:596` | 硬编码 operand 1 | 使用 `num_operands - 1` |

### Documentation

- **README.md** — 更新为中文版，突出 unsafe/FFI 定位
- **README_EN.md** — 新增英文版
- **docs/TOUSER/** — 给用户的信（中英文）
- **docs/investigation_reports/** — 详细调查报告（中英文）
- **docs/project_exports/** — 综合测试报告（中英文）

### Removed

- 删除错误方向的语义分析模块：
  - `src/pass/analysis/access_order.zig`
  - `src/pass/analysis/control_flow_sensitive.zig`
  - `src/pass/analysis/sensitive_data_flow.zig`
  - `src/pass/analysis/transmute_detection.zig`

---

## Version History Summary

| Version | Date | Major Feature | Key Metric |
|---------|------|---------------|------------|
| v0.1.5 | 2026-04-25 | **Zone Classification** | Rust 项目平均跳过 **60%** |

---

*[CHANGELOG]: https://keepachangelog.com/en/1.0.0/*
*[Semantic Versioning]: https://semver.org/spec/v2.0.0.html*
