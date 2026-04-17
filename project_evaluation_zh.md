# OmniSope 项目评估

## 概述

OmniSope 是一个基于 Zig 构建的 LLVM IR 分析框架，专注于通过 FFI 边界进行跨语言安全漏洞检测。

**当前状态**：具有核心分析 pass 和 FFI 检测功能的可用实现。

## 核心创新点

1. **事实图架构** - 结构数组（SoA）事实存储，实现高效的进程间通信
2. **跨语言 FFI 分析** - 检测 Rust ↔ C、Zig ↔ C 等跨语言边界的漏洞
3. **零成本抽象** - 利用 Zig 的 comptime 特性消除运行时开销
4. **严格通信边界** - Pass 仅通过事实存储进行通信
5. **三层 LLVM 绑定** - 原始 C API → 安全包装器 → 业务逻辑
6. **模块化 Pass 系统** - 编时验证的 Pass 接口，支持依赖跟踪

### 实现质量

1. **代码组织** - 结构良好的目录布局，与架构文档相匹配
2. **类型安全** - 强大地使用了 Zig 的类型系统，并具有全面的 comptime 验证
3. **测试** - 覆盖核心组件的广泛单元和集成测试
4. **文档** - README.md 和架构文档中有良好的文档
5. **构建系统** - 灵活的 build.zig，具有可配置选项（LTO、优化级别、目标）

## 最近发展

### 2026 年 4 月

- **FFI 检测**：多文件输入支持，FFIMatcher 函数匹配，FFIDetector 漏洞检测
- **LLVM 绑定**：三层架构（原始 → 安全 → 业务），消除手动 extern
- **Bug 修复**：修复 FFI matcher 内存泄漏，修正错误类型映射
- **文档**：双语文档（英文/中文）及 API 参考
- **输出**：JSON 格式，带 trace 信息和置信度评分
- **测试**：104/104 测试通过

### 代码清理

- 删除 61 个冗余文件，清理 4692 行代码
- 简化项目结构，移除过时示例
- QueryEngine 替代 IRLoader 提升性能
- 新增 7 个 issue 检测 pass（malloc check、free validation、memory safety、FFI body check、integer overflow、return check、FFI unsafe）

## 技术评估

### 事实存储

- 结构数组（SoA）布局，实现高效的进程间通信
- 独立的数组用于类型、主题、对象和上下文
- 仅追加设计，按事实类型高效查询

### Pass 系统

- 编时验证确保 Pass 实现所需接口
- 依赖关系跟踪和解析
- 线程安全的 ID 分配

### IR 层

- LLVM-C 指针的薄包装器
- 无缓存或计算

## 构建和依赖

### 当前问题

- LLVM 链接可能因系统配置而失败
- 硬编码的 LLVM 路径限制可移植性（可通过构建选项配置）
- LLVM 版本抽象有限

## 代码质量

### 优点

- 一致的编码风格
- 全面的测试
- 有意义的命名
- 正确的错误处理
- 显式传递分配器

### 改进领域

- 上下文敏感和路径敏感分析
- LLVM 链接可靠性
- 插件宿主完成
- 性能优化

## 实现状态

### 已完成

- 具有 SoA 布局的事实存储
- 编时验证的 Pass 系统
- 最小化的 IR 层（LLVM 包装器）
- 基础 Pass：CFG、DFG
- 分析 Pass：Alias、Lock、Taint、CallGraph
- Issue 检测 Pass：MallocCheck、FreeValidation、MemorySafety、FFIBodyCheck、IntegerOverflow、ReturnCheck、FFIUnsafe
- FFI 边界检测
- JSON 输出，带 trace 信息
- 双语文档

### 部分实现

- 插桩系统（规划器存在，IR 修改进行中）
- 合并系统（概念已定义，置信度评分待实现）

### 未实现

- 插件宿主系统
- 上下文敏感分析
- IDE 集成

## 建议

### 短期

- 改进格式字符串和 double free 检测
- 在实际项目上测试
- 优化大规模分析性能

### 中期

- 完成运行时集成
- 实现带置信度评分的合并引擎
- 完成插件宿主系统

### 长期

- 上下文敏感和路径敏感分析
- 扩展语言支持（Python、Java JNI、C# P/Invoke）
- IDE 集成

## 结论

OmniSope 是一个专注于跨语言安全漏洞检测的 LLVM IR 分析框架。核心创新包括事实图架构（SoA）、三层 LLVM 绑定和 Pass 之间的严格通信边界。该项目为 LLVM 生态系统中的静态分析提供了坚实基础，在高级分析功能和语言支持方面有扩展空间。