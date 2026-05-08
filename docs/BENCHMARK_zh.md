# OmniScope 基准测试报告 v0.1.7

> "除了上帝，其他人都必须拿数据说话。" — W. Edwards Deming

**最后更新**: 2026-05-07 | **二进制**: 4.9M | **测试**: 343/343 通过 | **Bug 修复**: 67 个 (Round 7+8)

## 测试环境

| 项目 | 值 |
|------|-----|
| 平台 | macOS (aarch64, Apple Silicon) |
| Zig 版本 | 0.15.2 |
| LLVM 版本 | 17 |
| 构建模式 | Debug（启用 GPA 泄漏检测） |
| 语料库 | 18 个 .ll 文件（7 红队 + 9 真实世界 + 2 扩展） |

## 红队测试结果 (v0.1.7 实测)

| 测试文件 | 函数数 | 问题数 | FFI 边界 | 跨语言边 | 追踪指针 | 耗时 |
|----------|--------|--------|----------|----------|----------|------|
| subtle_unsafe_rs | 68 | **6** | 128 | 158 | 38 | 197ms |
| ffi_boundary_bugs | 37 | **7** | 41 | 23 | 0 | 43ms |
| red_team_bugs | 38 | **11** | 64 | 34 | 0 | 35ms |
| posix_ffi_bugs | 48 | **8** | 35 | 31 | 49 | 33ms |
| python_c_api_bugs | 37 | — | 36 | 30 | 26 | 34ms |
| cross_lang_free_bugs | 22 | — | 42 | 15 | 0 | 28ms |
| jni_boundary_bugs_O0 | 13 | — | 2 | 2 | 41 | 26ms |

## 真实世界项目结果 (v0.1.7 实测)

| 项目 | 语言 | 函数数 | 问题数 | 泄漏 | UAF | FFI 边界 | 跨语言边 | 追踪指针 | 耗时 |
|------|------|--------|--------|------|-----|----------|----------|----------|------|
| sqlite3 | C | 3,346 | **77** | 69 | 0 | 1,717 | 1,548 | 20,192 | 13,547ms |
| curl8 | C | 1,245 | **46** | 36 | 0 | 1,567 | 1,506 | 4,948 | 2,297ms |
| libuv150 | C | 877 | **32** | 18 | 0 | 1,231 | 1,193 | 2,649 | 1,034ms |
| ring | Rust+C | 410 | **14** | 5 | 0 | 4,242 | 5,148 | 841 | 2,068ms |
| blst | Rust+C | 416 | **33** | 8 | 0 | 1,355 | 4,850 | 269 | 1,274ms |
| zkcrypto_bls12_381 | Rust | 302 | **2** | 1 | 0 | 6,787 | 8,520 | 0 | 3,219ms |
| jsoncpp195 | C++ | 2,070 | **5** | 5 | 0 | 4 | 888 | 0 | 1,939ms |
| ripgrep141 | Rust | 75 | **3** | 3 | 0 | 110 | 171 | 0 | 98ms |

## 检测能力矩阵

| 类别 | IssueKind | 严重度 | 置信度 | 覆盖范围 |
|------|-----------|--------|--------|----------|
| 内存安全 | memory_leak, use_after_free, double_free, invalid_free | Critical/High | 0.70-0.90 | 全语言 (C/Rust/Zig/Go) |
| FFI 边界 | ffi_unsafe_call, unchecked_return, type_mismatch | High | 0.65-0.80 | 跨语言调用 |
| Rust FFI | borrow_escape, cross_language_leak, cross_language_free | High | 0.75-0.85 | unsafe {} 块 |
| 注入攻击 | command_injection, format_string, buffer_overflow | Critical | 0.75-0.90 | FFI 处字符串操作 |
| 并发安全 | data_race, thread_safety_violation | High/Medium | 0.65-0.75 | 锁/线程分析 |

## 性能总结

| 文件规模 | 函数数 | 典型耗时 |
|----------|--------|----------|
| 小型 (<50 函数) | <50 | <50ms |
| 中型 (50-500) | 50-500 | 30-200ms |
| 大型 (500-3000) | 500-3000 | 1-3s |
| 超大型 (3000+) | 3000+ | ~13s (sqlite3) |

**FFI 边界检测总数**: ~16,000+
**跨语言边总数**: ~15,900+
**指针跟踪总数**: ~29,000+

## Rust FFI 检测: 修复前后对比

| 指标 | v0.1.5 (失明版) | v0.1.7 (Round 7+8) | 变化 |
|------|------------------|---------------------|------|
| Rust FFI TP 率 | 0% | ~90% | **+90pp** |
| subtle_unsafe_rs 问题 | 0 | 6 | +6 |
| ring 问题 | 0 | 14 | +14 |
| blst 问题 | 0 | 33 | +33 |
| Rust FFI 边界总数 | 0 | 11,604 | +11,604 |
| IssueKind 种类 | 14 | 20 | +6 (data_race, thread_safety_violation 等) |
| 语义函数注册数 | ~250 | 311 | +61 (含 14 static_buffer) |

## 备注

- **zkcrypto 仅 2 个问题**: 正确。纯 Rust 项目，100% 归入 Safe Zone，无 FFI 边界违规
- **curl/sqlite3 是纯 C 项目**: 贡献了大部分问题，但不在 OmniScope 核心 FFI 聚焦范围内，展示通用内存安全能力
- **精确度估计**: 基于 subtle_unsafe_rs 手动验证 (100%) + curl/sqlite3 抽样验证 (~85%)

## 复现

```bash
zig build                                    # 构建
./scripts/benchmark_real.sh                  # 收集实测指标
zig build test                               # 运行全部 343 测试
./zig-out/bin/OmniScope corpus/red_team_test/subtle_unsafe.rs.ll   # 单文件分析
```
