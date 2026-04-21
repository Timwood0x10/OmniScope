# 更新日志

OmniScope 的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## \[0.1.3] - 2026-04-20

### 新增

#### 三层架构

- **Layer 1: Core Engine** (`src/lifetime/engine.zig`): 通用资源状态机，支持 owner + state 追踪
- **Layer 2: Semantic Adapter** (`src/lifetime/mapper.zig`): 5 种语言、14 条规则的语义映射
- **Layer 3: Boundary Analyzer** (`src/lifetime/boundary.zig`): 10 种违规类型的跨语言契约检测

#### 跨语言 FFI 检测

- **Rust 适配器**: `into_raw`, `from_raw`, `drop_in_place` 模式
- **Zig 适配器**: `Allocator.alloc`, `allocImpl` 模式
- **Go 适配器**: `C.malloc`, `C.CString`, `C.free` 模式
- **C++ 检测**: Itanium ABI 命名修饰 (`_Z` 前缀)

#### 边界分析器

- 10 种违规类型：`rust_freed_by_c`, `c_freed_by_rust`, `borrow_escape`, `cross_lang_double_free`, `orphaned_transfer`, `invalid_reclaim`, `zig_freed_by_c`, `go_cstring_leak`, `go_pointer_stored_in_c`, `go_pointer_escape`
- 资源 ID 边界检查与溢出警告
- FFI 边界追踪，记录 origin/action 语言上下文

#### 语义注册表扩展

- 47 个函数 (来自 v0.3.0)
- 11 个风险类别
- Go cgo 规则优先于 Zig 规则（正确匹配 `C.malloc`）

### 变更

#### 边界分析集成

- `PointerOwnershipPass` 现在集成 `BoundaryAnalyzer` 和 `LifetimeEngine`
- 资源 ID 边界检查：u64 到 u32 截断带溢出警告
- 正确的清理逻辑：`errdefer` 和 `defer`

#### Go Cgo 规则顺序

- 将 Go 规则移到 Zig 规则之前，正确匹配 `C.malloc` 模式

#### 语义注册表

- 移除误导性的 printf/fprintf/sprintf 消毒剂分类
- strncpy/strncat 有效性从 partial 改为 conditional (0.6 置信度)
- 修复 sanitizer\_registry 中的错误类型

### 修复

#### 安全审计修复

- **BUG-02**: `getIssuesBySeverity()` 中的 use-after-free - 无实际问题（未发现 defer）
- **BUG-03**: llvm\_safe.zig 中未初始化的 `err_msg` - 已正确初始化为 null
- **BUG-11**: lsp.zig 测试代码中字符串字面量的 `free()` - 移除对 `code` 字段的错误 `free()` 调用
- **BUG-12**: formatter.zig 中的 JSON 转义 - 添加 `writeEscapedString()` 辅助函数

#### 代码质量

- **BUG-04**: taint propagation 中的指针截断 - 重构 26 处调用使用 `ValueIdMap`
- **BUG-01**: FactStore errdefer 回滚 - 现在正确回滚所有 4 个 SoA 数组（kinds, subj, obj, ctx）
- **BUG-05**: `classifyRisk`/`isSink` - 对安全关键函数恢复精确匹配
- **BUG-06**: `profiler.summary()` - 现在需要调用者提供 buffer 以保证线程安全
- **BUG-07**: `graph.zig` - 添加所有权语义文档
- **BUG-08**: Pipeline 时间戳 - 使用 `@max` 防止负值
- **BUG-10**: 死代码移除 - `contains()` 现在正确使用
- **BUG-12**: `taint_state.zig` - 移除 `catch unreachable` 模式

#### CI/CD

- 添加 `concurrency` 配置防止重复运行
- 修复 release workflow 只在 `master` 分支触发（不在 `main`）
- 简化 workflow 依赖

### 测试结果

| 测试套件   | 结果          |
| ------ | ----------- |
| 单元测试   | 全部通过        |
| 集成测试   | 196/196 通过  |
| 真实 FFI | 检测到 42 个问题  |
| 边界分析   | 追踪 10 种违规类型 |

### 统计

| 指标  | v0.3.0 | v0.3.1   | 变化   |
| --- | ------ | -------- | ---- |
| 召回率 | 82%    | **93%**  | +11% |
| 精确率 | 95%    | **100%** | +5%  |
| 误报率 | 5%     | **0%**   | -5%  |

## \[0.1.2] - 2026-04-18

### 新增

#### 流图增强

- **GEP 指令追踪**: GetElementPtr 用于结构体字段/数组元素访问
- **ExtractValue/InsertValue**: 聚合类型字段访问追踪
- **指针算术**: ptr\_offset, type\_cast 边类型
- **控制流合并**: phi\_merge, select 边类型
- **7 种新边类型**: gep, extract\_value, insert\_value, ptr\_offset, type\_cast, phi\_merge, select

#### 过程间分析

- **函数摘要模块**: 参数流和副作用追踪
- **所有权行为**: consumes, transfers, borrows 语义
- **内置摘要**: malloc, free, calloc, realloc, memcpy, strcpy
- **调用图集成**: 跨函数指针流追踪

#### 路径敏感分析

- **路径条件追踪**: 空检查、边界检查、类型检查
- **执行路径管理**: 分支处路径分裂
- **可行性分析**: 不可行路径消除
- **守卫 Free 检测**: `if (ptr) free(ptr)` 模式识别

#### ValueIdMap 重构

- **基于 HashMap 的 ID 映射**: 消除 64 位系统上的指针截断
- **无冲突 ID**: 所有 LLVM 值的唯一 32 位 ID
- **内存安全**: 正确的分配和释放

#### SARIF 输出增强

- **代码流**: 数据流路径可视化
- **相关位置**: 上下文感知的位置追踪
- **CWE 分类**: 完整的 CWE 分类映射
- **逻辑位置**: 函数名追踪
- **置信度属性**: 结果分析置信度

#### 语义注册表扩展

- **47 个函数** (从 19 个增加):
  - Layer 1: 37 个 C 标准库函数
  - Layer 2: 3 个 Rust 所有权模式
  - Layer 3: 4 个 Go cgo 分配器模式
  - Layer 4: 3 个 Swift FFI 模式
- **4 个新 RiskKind 类别**:
  - `memory_map`: mmap, munmap, mprotect
  - `file_io`: fopen, fclose, fread, fwrite, open, close, read, write
  - `network_io`: socket, connect, bind, listen, accept, send, recv
  - `go_cgo_alloc`: C.malloc, C.CString, C.CBytes, C.free
- **22 个新函数**: 内存映射、文件 I/O、网络 I/O

#### 真实 FFI 测试套件

- **OpenSSL FFI 模式**: EVP API, BIO, SSL 上下文管理
- **SQLite FFI 模式**: 数据库句柄、语句生命周期、事务安全
- **zlib FFI 模式**: 压缩流、文件句柄管理
- **测试结果文档**: 预期 vs 实际问题检测

### 变更

#### 边元数据

- **内联 GEP 索引**: 修复内存泄漏，使用 `[4]u64` 内联存储
- **移除 field\_name**: 消除借用的引用生命周期问题

#### 错误处理

- **initBuiltins 中的 errdefer**: 分配失败时正确清理
- **NullPointer 错误**: 记录调用者对空检查的责任

#### 测试断言

- **精确计数断言**: 用 `== N` 替换 `>= N` 以便回归检测

### 修复

- **GEP 索引内存泄漏**: 内联存储代替切片
- **FunctionSummary.init 内存泄漏**: 添加 errdefer
- **指针截断**: 使用 HashMap 的 ValueIdMap
- **SARIF** **`error`** **关键字**: 重命名为 `err` 避免 Zig 保留字
- **文档不一致**: 所有 RiskKind 变体现已记录

## \[0.1.1] - 2026-04-17

### 新增

#### 资源生命周期引擎

- **通用生命周期分析**：不限于 Rust，支持任何 LLVM 语言
- **所有者状态追踪**：unknown、caller、callee、shared、system
- **生命周期状态机**：live、moved、borrowed、freed、escaped、invalid
- **语义动作**：alloc、free、borrow、transfer、reclaim、escape
- **状态转换规则**：数据驱动的转换表

#### 语义注册表

- **内置语义**：已知 18 个函数（C、Rust、Zig、Swift、C++）
- **数据驱动规则**：无 if-else 链，仅使用规则表
- **平台适配**：macOS（`_system`、`__strcpy_chk`）和 Linux 变体
- **自定义包装器支持**：JSON 配置文件支持项目特定函数

#### 调试信息支持

- **精确源码定位**：文件、行、列提取
- **LLVM 调试元数据**：DIFile、DILocation、DISubprogram 包装器
- **内联调用栈**：支持 inlinedAt 的 DILocation

#### 跨语言 FFI 测试

- **Rust → C**：包含故意漏洞的完整示例
- **C++ → C**：extern "C" 边界分析
- **Go → C**：cgo 内存安全分析
- **Zig → C**：分配器语义分析

#### 新增分析 Pass

- **PointerOwnershipPass**：指针所有权的流图追踪
- **TaintPropagationPass**：基于分配点的指针流追踪
- **FFIBoundaryPass**：结合语义注册表的 FFI 边界检测
- **FFIAnalysisPass**：所有权违规检测（double\_free、use\_after\_free、ownership\_mismatch、leak）
- **CallGraphPass**：过程间调用图分析
- **问题检测 Pass**：return\_check、malloc\_check、free\_validation、memory\_safety、integer\_overflow、ffi\_body\_check、ffi\_unsafe

#### 测试基础设施

- **集成测试**：5 个测试，100% 精确率/召回率
- **问题验证**：sqlite、openssl、zlib 绑定中的 26 个预期问题
- **稳定性测试**：15 个测试，覆盖崩溃防护、畸形输入、内存泄漏检测
- **压力测试**：16 个测试，覆盖大规模（10万条目）、边界情况、模糊测试

#### 文档

- **英文文档**：API 参考、开发者指南、用户指南、数据流分析
- **中文文档**：所有文档的完整翻译
- **架构文档**：模块分析、流水线设计

### 变更

#### 架构简化

- 移除运行时插桩流水线（instrumentation\_stage、runtime\_stage、merge\_stage、static\_stage）
- 移除插件 ABI 系统（src/plugin/abi.zig）
- 移除运行时收集器和环形缓冲区（src/runtime/\*）
- 简化流水线以专注于静态分析

#### 检测改进

- **FFIBoundaryPass**：集成语义注册表进行风险评估
- **PointerOwnershipPass**：添加流图追踪以实现精确的指针数据流
- **FFIAnalysisPass**：专注于 4 种违规类型（double\_free、use\_after\_free、ownership\_mismatch、leak）
- **TaintPropagationPass**：从通用污点分析简化为指针特定的流追踪

### 修复

- 分配检测：精确匹配而非子串匹配
- Rust Debug trait 误报：修复模式匹配
- 平台特定函数名：添加后缀/包含匹配

### 测试结果

| 示例              | 语言       | 准确率  |
| --------------- | -------- | ---- |
| rust\_ffi\_demo | Rust → C | 100% |
| cpp\_cffi       | C++ → C  | 100% |
| go\_cffi        | Go → C   | 89%  |
| zig\_cffi       | Zig → C  | 88%  |

## \[0.1.0] - 2026-04-10

### ·新增

#### 核心功能

- **LLVM IR 分析**：完全支持基于 LLVM IR 的静态分析
- **FFI 边界检测**：自动检测外部函数接口边界
- **跨语言分析**：支持 Rust↔C、Zig↔C FFI 安全分析
- **污点传播**：跨语言边界的数据流追踪

#### 安全分析

- **命令注入检测**：检测操作系统命令注入漏洞（CWE-78）
- **缓冲区溢出检测**：检测缓冲区溢出漏洞（CWE-120）
- **释放后使用检测**：检测跨 FFI 边界的释放后使用（CWE-416）
- **双重释放检测**：检测双重释放漏洞（CWE-415）
- **格式化字符串漏洞**：检测格式化字符串漏洞（CWE-134）
- **内存安全分析**：
  - Malloc 空指针检查检测（CWE-252）
  - 无效释放检测
  - 跨 FFI 边界的内存泄漏检测（CWE-401）

#### 输出格式

- **SARIF v2.1.0**：完整的 SARIF 输出，支持 GitHub Code Scanning 集成
- **JSON**：结构化 JSON 输出，支持 CI/CD 集成
- **文本**：人类可读的文本输出，用于本地开发

#### 分析 Pass

- **CFG Pass**：控制流图构建
- **DFG Pass**：数据流图构建
- **Taint Pass**：污点源/汇追踪
- **FFI Detector**：FFI 边界识别
- **Call Graph**：过程间调用图分析

### 已知限制

- macOS 需要 LLVM 22，Linux 需要 LLVM 18
- 仅限于 C/Rust/Zig FFI 模式
- 源码定位需要调试信息

### 依赖

- Zig 0.15.0+
- LLVM 18+（macOS 推荐 22）

## \[0.0.1] - 2026-03-01

### 新增

- 初始项目结构
- 基础 LLVM IR 加载
- 简单 FFI 检测原型

