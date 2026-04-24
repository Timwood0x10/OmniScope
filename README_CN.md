# OmniScope

**跨语言 FFI 与内存安全静态分析器（支持 C/C++/Rust）**

OmniScope 通过分析 LLVM IR 来检测内存安全问题、FFI 边界违规和所有权契约违规，支持 C/C++/Rust/Zig/Go 等语言。

---

## ✨ 最新版本：v0.2.1 (2026-04-23)

### 🎯 v0.2.1 新功能

| 功能 | 描述 |
|------|------|
| **红队对抗测试套件** | 17个故意注入的漏洞，**58.8% 命中率** (+17.6pp) |
| **Double-Free 检测** | BFS 别名分析 + 智能阈值逻辑 (`==2 → HIGH`, `>2 → MEDIUM`) |
| **缓冲区溢出检测** | 栈缓冲区溢出 + 数组越界检测 (GEP 分析) |
| **循环泄漏检测** | 启发式规则：≥3 次分配无匹配释放 |
| **格式化字符串分类** | 新增 `.format_string` IssueKind，覆盖 printf 系列 |
| **exec 家族全覆盖** | 新增 12 个危险函数 (execve, posix_spawn 等) |
| **C++ RAII 过滤** | wabt 误报减少 -22% |

---

## 🚀 快速开始

```bash
# 编译
zig build

# 分析 LLVM IR 文件
./zig-out/bin/OmniScope target.ll

# 输出格式：text (默认)、json、sarif
./zig-out/bin/OmniScope target.ll --format json --output report.json
```

### 环境要求

| 工具 | 版本 | 安装方式 |
|------|------|----------|
| Zig | 0.15.2+ | [zvm](https://www.zvm.app) |
| LLVM | 18+ (推荐 21) | `brew install llvm@21` / apt |

### Make 命令

```bash
make build          # 编译
make test-all       # 运行所有测试 (单元 + 集成 + 回归 + 压力)
make benchmark      # 语料库检测率指标
make baseline-check # 真实项目回归测试
make red-team-test  # 红队对抗测试套件 (v0.2.1+)
```

---

## 🏗️ 架构设计

### 三层架构

```
┌─────────────────────────────────────────┐
│  Layer 3: Boundary Analyzer            │  ← 跨语言边界分析
│  - FFI 安全检查                        │
│  - 所有权违规检测                      │
├─────────────────────────────────────────┤
│  Layer 2: Semantic Adapter             │  ← 语言适配层
│  - Rust Adapter                       │
│  - C/C++ Adapter (8层 FP 减少)        │
│  - Zig / Go Adapter                   │
├─────────────────────────────────────────┤
│  Layer 1: Core Engine                 │  ← 核心引擎
│  - Lifetime Engine                    │  ← 所有权 + 状态转换
│  - Data Flow Graph                    │  ← 数据流分析
└─────────────────────────────────────────┘
```

### 核心操作语义

| 操作 | 含义 |
|------|------|
| `alloc` | 分配资源 |
| `free` | 释放资源 |
| `borrow` | 临时借用 |
| `transfer` | 所有权转移 |
| `retain` | 引用计数 +1 |
| `release` | 引用计数 -1 |
| `escape` | 逃逸到未知作用域 |

---

## 🔍 检测能力

### 支持的问题类型

| 类型 | 严重度 | 示例 |
|------|--------|------|
| 内存泄漏 | MEDIUM | `malloc()` 无对应 `free()` |
| Use-After-Free | HIGH | 释放后解引用 |
| Double-Free | HIGH | 同一资源释放两次 |
| NULL 解引用 | MEDIUM | 未检查可空分配返回值 |
| 格式化字符串 | MEDIUM | 用户控制的 `%s` 传入 printf |
| 命令注入 | CRITICAL | `system()` 使用用户输入 |
| 跨语言违规 | HIGH | Rust Box 被 C 的 free() 释放 |
| 缓冲区溢出 | HIGH | GEP 索引超出分配大小 (v0.2.1+) |
| 循环泄漏 | MEDIUM | 循环内持续分配不释放 (v0.2.1+) |

### 支持的语言边界

| 边界 | 状态 | 说明 |
|------|------|------|
| C → C | ✅ 稳定 | 完整 libc/POSIX 注册表 |
| Rust ↔ C | ✅ 稳定 | `into_raw`/`from_raw`, `Box`, `CString` |
| Zig ↔ C | ✅ 稳定 | `Allocator.alloc` 模式 |
| Go → C | ⚠️ 实验性 | cgo `C.malloc`/`C.CString` |
| C++ → C | ✅ 稳定 | Itanium ABI, 8 层 FP 减少 |

---

## 📊 真实项目验证 (v0.2.1)

> **10 个生产级项目，6,937 个函数分析完成**

| 项目 | 语言 | 函数数 | Issues | 时间 |
|------|------|--------|--------|------|
| SQLite 3.47.2 | C | 3,237 | **2** | ~5s |
| libcurl 8.14.0 | C | 68 | **1** | ~1s |
| libuv 1.50.0 | C | 145 | **6** | ~0.6s |
| jsoncpp 1.9.5 | C++ | 1,537 | **37*** | ~2s |
| abseil-cpp 2024 | C++ | 193 | **0** ✅ | ~0.4s |
| ripgrep 14.1.1 | **Rust** | 75 | **0** ✅ | ~0.04s |
| rust_sqlite | Rust | 135 | **21** | ~0.09s |
| openssl_wrapper | C | 52 | **17** | ~0.03s |
| wasmtime_test | Rust | 974 | **4023*** | ~7s |
| wabt | C++ | 558 | **7** | ~2s |

\* 部分项目因增强检测灵敏度导致数量增加，需进一步调优

### C++ 8 层误报减少系统

| 层级 | 技术 | 目标 |
|------|------|------|
| L1 | STL 内部函数过滤 | `_ZNSt*` 模板展开 |
| L2 | C++ 特殊成员函数过滤 | 构造/析构/拷贝/移动赋值 |
| L3 | RAII 智能指针检测 | `unique_ptr::C1` / `shared_ptr::C1` |
| L4 | RAII 函数集 | 跳过含智能指针的整个函数 |
| L5 | C++ ABI 运行时过滤 | `__cxa_*` 异常/守卫/atexit |
| L6 | Meyers 单例检测 | `__cxa_guard_acquire` 模式 |
| L7 | C++ 运算符 FFI 过滤 | `_Znwm`/`_ZdlPv` 在 FFI 报告中跳过 |
| L8 | RC 容器检测 | `Ref()`/`Unref()`/CordRep 模式 |

---

## 🧪 红队对抗测试 (v0.2.1)

OmniScope 包含一个**故意注入漏洞的测试套件**，用于验证检测能力：

```bash
make red-team-test
```

### 测试结果 (O0 编译)

| Bug ID | 类型 | 状态 | 说明 |
|-------|------|------|------|
| BUG-01 | Memory Leak | ✅ 检测到 | `bug_memory_leak` |
| BUG-02 | UAF | ✅ 检测到 | `bug_use_after_free` |
| BUG-03 | Double-Free | ✅ **新增** | 4个别名组 × 2次释放 |
| BUG-04 | NULL 解引用 | ✅ 检测到 | VULNERABILITY OMI-002 |
| BUG-05 | system() | ✅ CRITICAL | FFI_RISK command_exec |
| BUG-07 | Format String | ✅ 增强 | 分类为 `.format_string` |
| BUG-12 | popen() | ✅ CRITICAL | FFI_RISK command_exec |
| BUG-15 | Loop Leak | ✅ **新增** | 5 次分配检测到 |
| BUG-16 | 条件泄漏 | ✅ 检测到 | 路径敏感 UAF |
| BUG-17 | execvp() | ✅ **新增** | Sink: execvp() |

**总 Issues: 10 | 命中率: 58.8%**

---

## 📁 项目结构

```
OmniScope/
├── src/
│   ├── pass/analysis/        # 分析 Pass
│   │   ├── pointer_ownership.zig   # 所有权追踪 (主入口)
│   │   ├── cpp_fp_reduction.zig    # C++ FP 减少 + Double-Free + Loop-Leak
│   │   ├── buffer_overflow.zig      # 缓冲区溢出检测 [NEW v0.2.1]
│   │   ├── ffi_detector.zig         # FFI 边界检测
│   │   └── call_graph.zig           # 调用图构建
│   ├── dataflow/             # 数据流分析
│   ├── diag/                  # 问题定义 & 输出
│   └── perf/                  # 性能分析
├── corpus/
│   ├── real_world/           # 真实项目基线 (10个项目)
│   └── red_team_test/        # 红队对抗测试 [NEW v0.2.1]
├── docs/
│   ├── SecurityAuditReport/  # 安全审计报告
│   └── WHITEPAPER.md         # 技术白皮书
├── plan/
│   ├── rules/rules.md        # 编码规范 ⚠️ 必读
│   └── TODOLIST.md           # 开发计划 [NEW v0.2.1]
├── scripts/
│   └── baseline_check.sh     # 回归测试脚本
├── CHANGELOG.md              # 变更日志
├── RELEASE_NOTES.md          # 发布说明 [NEW v0.2.1]
└── BASELINE.md               # 基线数据 (在 corpus/real_world/)
```

---

## 🛠️ 开发指南

### 编码规范

所有代码必须遵循 [`plan/rules/rules.md`](plan/rules/rules.md)：

- ✅ 单文件不超过 **1000 行**
- ✅ 注释必须使用**英文**
- ✅ 代码:注释比例 **7:3**
- ✅ 命名规范：函数 camelCase，变量 snake_case，类型 TitleCase
- ✅ Simplicity First — 最小化代码量
- ✅ Surgical Changes — 只改必要的

### 提交 PR 检查清单

- [ ] 代码符合 rules.md 规范
- [ ] 所有测试通过 (`zig build test && make baseline-check`)
- [ ] 红队测试通过 (`make red-team-test`)
- [ ] 更新 CHANGELOG.md
- [ ] 如有行为变更，更新 BASELINE.md

---

## 📚 文档

| 文档 | 说明 |
|------|------|
| [BASELINE.md](corpus/real_world/BASELINE.md) | 真实项目基线数据 (v0.2.0 格式) |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | v0.2.1 发布说明 |
| [CHANGELOG.md](CHANGELOG.md) | 完整变更历史 |
| [RED_TEAM_TEST_REPORT.md](corpus/red_team_test/RED_TEAM_TEST_REPORT.md) | 红队测试详细报告 |
| [TODOLIST.md](plan/TODOLIST.md) | 开发路线图 |
| [rules.md](plan/rules/rules.md) | 编码规范 (必读) |

---

## 🚀 下一步计划 (v0.3.0)

### 计划中的功能

- [ ] Def-Use 分析：未初始化变量检测
- [ ] 字段敏感分析：结构体成员泄漏检测
- [ ] O0/O1 双模式基线测试框架
- [ ] C++ 析构函数生命周期分析（进一步减少 FP）
- [ ] 大模块性能优化（wasmtime）

### 已知限制

1. **wasmtime_test 4023 issues**: 可能是 buffer_overflow pass 过度报告，需调查
2. **栈 OOB 检测**: 框架已就绪，可能需要针对真实场景调优
3. **资源泄漏检测器**: Flow graph 连通性限制了准确性

---

## 🙏 致谢

感谢开源社区提供真实项目用于基线测试：
- **SQLite**, **libcurl**, **libuv**, **jsoncpp**, **abseil-cpp**
- **ripgrep** (BurntSushi), **wasmtime** (Bytecode Alliance), **wabt** (WebAssembly)

---

## 📄 许可证

MIT License

---

*使用 Zig 0.15.2 构建于 macOS 15.0*
*OmniScope: 跨语言 FFI/Unsafe 边界分析器*
