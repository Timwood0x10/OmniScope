# Timwood0x10 项目总结 (简历版)

> GitHub: [Timwood0x10](https://github.com/Timwood0x10)

---

## 一、原创项目 (Original Projects)

### 1. OmniScope — 跨语言 FFI 安全静态分析器
**技术栈**: Zig, LLVM IR, SARIF/JSON
**GitHub**: [Timwood0x10/OmniScope](https://github.com/Timwood0x10/OmniScope)

- 基于 LLVM IR 的跨语言 FFI 内存安全静态分析工具，检测 use-after-free、double-free、内存泄漏、空指针解引用、缓冲区溢出等
- 支持 **8 种语言族**：C, C++, Rust, Zig, Go, Python, Java, C#/.NET
- **Zone Classification** 系统跳过 64% 安全代码，聚焦危险 FFI 边界
- 5 层分析流水线，20 种检测类别
- 在 **42 个真实项目** (sqlite3, curl, ring, wasmtime 等) 上验证：分析 20,000+ 函数，发现 2,955+ 问题，成功率 95.2%，速度 ~150ms/1K 函数
- 输出 JSON / SARIF (GitHub Code Scanning) / 文本报告
- **50 commits**, Apache 2.0, v0.2.0

---

### 2. PolyScope — Zig/C 静态安全分析器
**技术栈**: Zig, AST/IR 双引擎, 控制流图, 污点追踪
**GitHub**: [Timwood0x10/PolyScope](https://github.com/Timwood0x10/PolyScope) (推测)

- 纯 Zig 实现、零依赖的 Zig 和 C 语言静态安全分析器
- 混合分析引擎：快速 AST 模式匹配 + 深度 IR 控制流分析 + 污点传播
- 检测 use-after-free、空指针解引用、double-free、内存泄漏、硬编码凭据
- **100% 精确率 (0 误报)**，跨 4 个真实项目 (含 Bun) 1,924 个文件验证
- 处理速度 582 文件/秒，150 个测试全部通过
- 自举能力 (分析自身代码库)
- **47 commits**, Apache 2.0

---

### 3. memscope-rs — Rust 运行时内存分析库
**技术栈**: Rust, GlobalAlloc hook, Tokio, DashMap, Handlebars, addr2line
**GitHub**: [Timwood0x10/memscope-rs](https://github.com/Timwood0x10/memscope-rs)

- 通过自定义 `GlobalAlloc` hook 实现堆分配插桩，检测内存泄漏、Arc/Rc 克隆模式、循环引用、异步任务内存使用
- **8 引擎模块化架构** (Capture, Analysis, Event Store, Render, Snapshot, Timeline, Query, Metadata)
- 三层对象模型 (HeapOwner/Container/Value/StackOwner) 实现语义级内存分类
- Arc/Rc 克隆检测 (通过栈指针追踪，Rust 内存工具中独有)
- **<5% 性能开销**，分配延迟 21-40ns
- 超线性并发效率 (4 线程 139% vs 单线程基线)
- v0.2.0 重构：**75% 代码量减少** (270K → 77K 行)
- 交互式 HTML Dashboard 报告输出
- **50 commits**, 独立开发者, v0.2.4

---

### 4. memscope-stress-test — memscope-rs 压力测试套件
**技术栈**: Rust, Tokio, Rayon, Serde
**GitHub**: [Timwood0x10/memscope-stress-test](https://github.com/Timwood0x10/memscope-stress-test)

- 4 个演示二进制文件：多线程 FFT、Tokio 异步系统、Unsafe/FFI 分配追踪、综合演示
- 展示 lockfree 追踪、泄漏检测、每任务内存画像、"护照"系统 FFI 泄漏检测
- TaskIdRegistry 任务层级、循环引用检测、Arc/Rc/Box 克隆追踪
- JSON 分析数据 + 交互式 HTML Dashboard 导出
- **4 commits**, 独立开发者

---

### 5. AlgoGPU (Rust 版) — GPU 任务调度器
**技术栈**: Rust, Tokio, Tonic/Prost (gRPC), Protobuf
**GitHub**: [Timwood0x10/AlgoGpuRust](https://github.com/Timwood0x10/AlgoGpuRust) (推测)

- 约 1,830 行代码，91 个单元测试的极简 GPU 任务调度器
- gRPC API 提交任务，支持优先级和内存需求
- **Best Fit** 内存分配算法 (最小化碎片)
- 优先级队列 + 老化机制防饥饿 (score = priority + 0.1 * age)
- 令牌桶限流、指数退避重试、优雅关停
- 单线程确定性调度循环 (可预测行为)
- **6 commits**, 独立开发者

---

### 6. BlinkSwap — 加密货币量化交易系统
**技术栈**: Rust, Tokio, Axum, Polars, Reqwest, Plotters
**GitHub**: 私有仓库

- Rust 异步量化交易平台，集成 CoinGecko 实时行情
- 回测引擎：手续费、滑点模拟、Sharpe Ratio / 最大回撤 / 胜率
- 技术指标库：SMA, EMA, RSI, MACD, Bollinger Bands
- 多策略实现：趋势跟踪、均值回归、复合策略、套利检测
- 实时 Web Dashboard (Axum/WebSocket, K 线图)
- 16+ 模块化架构 (策略, 回测, 指标, 执行, 优化, RL)
- **7 commits**, 独立开发者

---

### 7. System Alert — macOS 系统监控工具
**技术栈**: Rust, Tokio, TUI-rs/termion, sysinfo, clap
**GitHub**: [Marky-Shi/system_alert](https://github.com/Marky-Shi/system_alert)

- 高性能终端系统监控，专为 Apple Silicon 优化
- 四象限 TUI 布局：CPU / 内存 / 电池 / 网络实时指标
- Apple Silicon E-cluster/P-cluster 和每封装功耗监控 (CPU, GPU, Neural Engine)
- 阈值智能通知 + 可配置冷却时间
- TOML 配置 + CLI 覆盖，异步非阻塞数据采集
- **19 commits**, 独立开发者

---

### 8. gpu-for-mac — Apple Metal GPU 计算探索
**技术栈**: Rust, Apple Metal API, Metal Shading Language, MPS
**GitHub**: 私有仓库

- Rust 封装 Apple Metal GPU 编程模式
- GPU 能力探测、预编译 shader 库加载、并行计算内核
- MPS 光线-三角形相交 + 加速结构
- Argument Buffer 编码、GPU-CPU 异步同步 (Shared Events + GCD)
- Objective-C 互操作 (objc/block/dispatch crates)

---

### 9. Transformer & Mamba Architecture Explorer — 深度学习架构可视化
**技术栈**: Python, Streamlit, Manim, PyTorch, Plotly
**GitHub**: 私有仓库

- Manim 数学动画解析 Transformer 和 Mamba (SSM) 内部机制：多头注意力、位置编码、交叉注意力、BPE 分词、AdamW 优化器、RoPE、混合精度训练
- 交互式 Streamlit Web 应用，10+ 分析页面：注意力模式可视化、梯度流分析、Token 追踪、权重异常检测、初始化方法对比、FLOPs/内存分析
- Kimi Attention Residuals (AttnRes) 机制分析
- 训练优化实验：学习率调度、优化器基准测试、过拟合检测
- 双语支持 (中/英), 架构演化时间线 (RNN → Transformer → Mamba)
- **13 commits**, 独立开发者

---

### 10. Neural Network Math Explorer — 神经网络数学教育平台
**技术栈**: Python, PyTorch, Streamlit, Plotly, SymPy, NetworkX
**GitHub**: 私有仓库

- 交互式神经网络架构"计算解剖台"：追踪精确数值计算 (加权求和、激活、梯度)
- 8 种层类型 × 7 个生产网络 (ResNet-50, BERT-base, GPT-2, ViT-Base 等) 的参数/FLOPs/内存分析
- 架构对比：CNN vs ViT, RNN vs Transformer, GCN vs GAT
- 参数/FLOPs 计算器 + 优化建议 (剪枝、量化、蒸馏)
- 数值稳定性诊断 (梯度消失/爆炸检测)
- MoE 路由可视化、常见训练陷阱案例博物馆
- 18 功能模块, ~25K 行代码, **20 commits**, MIT

---

### 11. Multi-Agent Outfit Recommendation — 多智能体穿搭推荐系统
**技术栈**: Python 3.13, OpenAI-compatible LLM, PostgreSQL + pgvector, httpx, asyncio
**GitHub**: 私有仓库

- Leader Agent 解析用户画像 → AHP 协议分发 → 4 个 Sub Agent (头/上/下/鞋) 并行推荐
- 自定义 AHP (Agent HTTP-like Protocol)：TASK/RESULT/HEARTBEAT/ACK 方法
- 断路器 + 指数退避重试、会话记忆、用户画像持久化
- pgvector 向量相似度检索 (RAG)
- **20+ commits**, 2 contributors

---

### 12. GoAgent — Go 多智能体 AI 框架
**技术栈**: Go 1.26, PostgreSQL + pgvector, Redis, FastAPI, Ollama, SentenceTransformers
**GitHub**: [Timwood0x10/goagent](https://github.com/Timwood0x10/goagent)

- 通用多智能体协作框架，Leader/Sub-agent 架构编排复杂任务
- 自定义 AHP (Agent HTTP Protocol) 跨智能体通信协议
- **记忆蒸馏**机制：周期性压缩对话历史为长期记忆
- **DAG 工作流引擎**：有向无环图编排多步骤任务
- 工具注册/调用系统，pgvector 向量相似度 RAG 检索
- Redis 缓存嵌入，可插拔 LLM 后端 (OpenRouter/OpenAI/Ollama)
- 7 大核心子系统：Agent 系统、协议层、记忆系统、存储层、工具系统、工作流引擎、嵌入服务
- **141 commits**, 独立开发者, v0.2

---

### 13. CodeTribunal — AI 代码陪审团 (代码审查辩论系统)
**技术栈**: Go 1.26+, SQLite + sqlite-vec (向量搜索), WebSocket, 多 LLM (Ollama/OpenAI/Claude)
**GitHub**: [Timwood0x10/CodeTribunal](https://github.com/Timwood0x10/CodeTribunal)

- 多 LLM Agent 辩论式代码审查系统，8 个独特审查人角色 (架构师、安全卫士、性能大师等)
- **"捣乱者"游戏机制**：一个 Agent 暗中给出有害建议，用户需识别
- 交叉质询辩论阶段：Agent 互相指控并提供证据
- 基于 sqlite-vec 的向量检索经验回溯 (128 维关键词哈希嵌入)
- Web UI (localhost:8765) + CLI 双模式
- 双存储：零配置内存 或 持久化 SQLite
- 暂停/恢复会话支持
- **9 commits**, 独立开发者, Apache 2.0

---

### 14. AlgoGPU (Go 版) — AI 推理 GPU 任务调度器
**技术栈**: Go, gRPC, Python SDK, SQLite, Protobuf
**GitHub**: [Timwood0x10/go-scheduler](https://github.com/Timwood0x10/go-scheduler)

- 面向 AI Agent 和推理工作负载的极简 GPU 调度器
- 双部署模式：独立 gRPC 服务 或 嵌入式插件
- **数据驱动调度**：从历史执行数据学习，预测资源需求并优化决策
- 确定性 Channel 调度循环 (项目核心)
- Best Fit GPU 装箱 + 负载阈值
- 令牌桶限流 + 每用户日配额
- 任务老化防饥饿、策略引擎动态优先级调整
- 资源预测器 (基于历史指标)
- ~3,750 行目标代码 (工业级极简)
- **9 commits**, 独立开发者, MIT

---

## 二、研究/学习项目 (Research Forks)

| 项目 | 原作者 | 领域 | 说明 |
|------|--------|------|------|
| **FFmpeg** | ffmpeg.org | 多媒体 | 业界标准音视频处理框架，研究编解码和 filter graph |
| **Mamba** | Tri Dao & Albert Gu | AI 架构 | Selective SSM，线性复杂度序列建模，Transformer 替代方案 |
| **Demucs** | Meta Research | 音频 AI | ICASSP 2023，音乐源分离 SOTA，Sony MDX 冠军 |
| **Spleeter** | Deezer | 音频 AI | 音乐源分离库，100x 实时速度，JOSS 发表 |
| **Absolute-Zero-Reasoner** | 清华 LeapLab | AI 推理 | 零外部数据自博弈推理训练，arXiv 2505.03335 |
| **Mastra** | YC W25 | AI 框架 | TypeScript AI 应用框架，Agent/Workflow/RAG 全栈 |

---

## 三、技术能力画像 (简历用)

### 核心技能
- **系统编程**: Rust (内存安全/GPU/异步/量化), Zig (编译器/静态分析), Go (并发/调度/微服务), C/C++ (LLVM)
- **安全分析**: LLVM IR 静态分析, AST/IR 双引擎, 污点追踪, 控制流图, FFI 安全审计
- **AI/ML**: Transformer/Mamba 架构深入理解, 多智能体系统, 向量数据库 (pgvector), GPU 计算
- **GPU 编程**: Apple Metal, MPS, GPU 任务调度 (Rust + Go 双实现)
- **全栈能力**: gRPC/Axum/WebSocket, Streamlit, TUI, HTML Dashboard

### 项目亮点 (可直接用于简历)
1. **OmniScope**: LLVM IR 级跨语言 FFI 安全分析器，8 语言族支持，42 项目验证，2,955+ 问题发现
2. **PolyScope**: Zig/C 静态分析器，100% 精确率 (0 误报)，582 文件/秒
3. **memscope-rs**: Rust 运行时内存分析库，<5% 开销，Arc/Rc 克隆检测 (独有)，75% 代码精简重构
4. **GoAgent**: Go 多智能体框架，141 commits，DAG 工作流 + 记忆蒸馏 + AHP 协议
5. **CodeTribunal**: AI 代码陪审团，多 Agent 辩论审查 + "捣乱者"游戏机制
6. **AlgoGPU**: GPU 任务调度器 (Rust + Go 双实现)，数据驱动调度，Best Fit 装箱
7. **Transformer Explorer**: Manim 动画 + Streamlit 交互式深度学习架构分析平台

### 技术栈速查
```
Rust ████████████  (系统工具/量化/GPU/异步)
Zig  ████████████  (编译器/静态分析)
Go   ████████████  (多智能体/调度/微服务) ← 新增!
Python ████████    (AI/ML/可视化)
C/C++ ████████     (LLVM/FFI)
LLVM ████████      (IR 分析/优化)
```

---

*生成时间: 2026-05-28*
*扫描范围: ~/code/, ~/go/src/*
*筛选条件: git user = Timwood0x10 或 remote 含 timwood0x10*
*项目总数: 14 个原创 + 6 个研究 fork*
