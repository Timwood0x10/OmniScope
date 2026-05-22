# OmniScope Documentation Index

## Structure

```
docs/
├── en/                          # English documentation
│   ├── QUICK_START.md           # Getting started guide
│   ├── API_REFERENCE.md         # API reference
│   ├── architecture.md          # Architecture overview
│   ├── WHITEPAPER.md            # Technical whitepaper
│   ├── developer_guide.md       # Contributor guide
│   ├── BENCHMARK.md             # Performance benchmarks
│   ├── modules.md               # Module documentation
│   ├── passes.md                # Analysis passes documentation
│   ├── RED_BLUE_TEAM_EN.md      # Red/Blue team testing guide
│   ├── ir-specs/                # IR specification (8 compilers)
│   │   ├── C_CPP_IR_SPEC.md
│   │   ├── RUST_IR_SPEC.md
│   │   ├── ZIG_IR_SPEC.md
│   │   ├── GO_GC_IR_SPEC.md
│   │   ├── TINYGO_IR_SPEC.md
│   │   ├── JDK_IR_SPEC.md
│   │   ├── PYTHON_IR_SPEC.md
│   │   └── SWIFT_IR_SPEC.md
│   └── reports/                 # Analysis reports
│       ├── CORPUS_ANALYSIS.md
│       ├── TEST_REPORT_v017.md
│       └── investigation/       # Detailed audit reports
│
├── zh/                          # 简体中文文档
│   ├── QUICK_START.md           # 快速入门
│   ├── API_REFERENCE.md         # API 参考
│   ├── architecture.md          # 架构概述
│   ├── WHITEPAPER.md            # 技术白皮书
│   ├── developer_guide.md       # 开发者指南
│   ├── BENCHMARK.md             # 性能基准
│   ├── modules.md               # 模块文档
│   ├── passes.md                # 分析 pass 文档
│   ├── RED_BLUE_TEAM.md         # 红蓝队测试指南
│   ├── ir-specs/                # IR 规范（8 个编译器）
│   │   ├── C_CPP_IR_SPEC.md
│   │   ├── RUST_IR_SPEC.md
│   │   ├── ZIG_IR_SPEC.md
│   │   ├── GO_GC_IR_SPEC.md
│   │   ├── TINYGO_IR_SPEC.md
│   │   ├── JDK_IR_SPEC.md
│   │   ├── PYTHON_IR_SPEC.md
│   │   └── SWIFT_IR_SPEC.md
│   └── reports/                 # 分析报告
│       ├── CORPUS_ANALYSIS.md
│       └── investigation/       # 详细审计报告
│
└── TOUSER/                      # User-facing letters (bilingual)
    ├── en.md
    └── zh.md
```

## IR Specifications

Compiler-level IR pattern analysis for OmniScope's static analysis engine.
Each document distinguishes **user-defined symbols** from **compiler-reserved symbols** with source code evidence.

| Compiler | Languages | Key Patterns |
|----------|-----------|-------------|
| **C/C++** (Clang) | C, C++ | Itanium mangling, vtable, exception handling, builtins |
| **Rust** (rustc) | Rust | v0/_ZN mangling, `__rust_alloc`, drop glue, panic/unwind |
| **Zig** | Zig | `__zig_*` builtins, allocator vtable, AIR→LLVM IR |
| **Go gc** | Go | SSA form, ~150 runtime functions, write barrier, ABI0/ABIInternal |
| **TinyGo** | Go | `runtime.*`, CGo `_Cgo_*`, transform passes |
| **JDK** (HotSpot) | Java | C2 Sea-of-Nodes, JNI, GC barriers, 200+ intrinsics |
| **CPython** | Python | PyObject refcount, GC, C API, buffer protocol |
| **Swift** | Swift | ARC, protocol/value witness tables, metadata, @objc interop |
