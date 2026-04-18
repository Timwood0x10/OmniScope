# 更新日志

OmniScope 的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## \[0.2.0] - 2026-04-17

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

