# 如何解读 OmniScope 分析结果

本文说明如何阅读 OmniScope 的分析结果，并把报告映射回源码。内容面向 0.2.0 的报告模型：语义解析与 Surface Classifier 会提供更多 FFI 边界、运行时归属和证据链信息。

## 排查流程

1. **先看严重级别**：优先处理 `critical` 和 `high`。
2. **再看置信度**：优先处理 `HIGH` 和 `MEDIUM`；`LOW` 需要人工确认。
3. **理解 issue 类型**：判断它属于所有权、生命周期、类型、污点还是并发问题。
4. **定位函数名**：必要时 demangle，或从 LLVM IR 映射回源码。
5. **确认边界**：确认指针、数据或所有权是否跨越语言/运行时边界。
6. **确认 allocator family**：分配和释放必须属于同一运行时/库族。

## 核心字段

| 字段 | 含义 | 如何使用 |
|------|------|----------|
| `kind` | 问题类别，例如 `borrow_escape`、`memory_leak`、`cross_lang_free_mismatch` | 判断 bug 类型和修复模式 |
| `severity` | `critical`、`high`、`medium`、`low` | 决定修复优先级 |
| `confidence` | `HIGH`、`MEDIUM`、`LOW` | 判断需要多少人工验证 |
| `confidence_score` | 0.0 到 1.0 的数值置信度 | 适合 CI 阈值和版本间 diff |
| `cwe_id` | CWE 映射 | 适合安全评审和 SARIF 集成 |
| `location.function` | 证据所在函数 | 源码/IR 导航入口 |
| `message` | 人类可读解释 | 概括所有权或边界问题 |

## 严重级别与置信度

| 严重级别 | 通常含义 | 示例 |
|----------|----------|------|
| `critical` | 很可能导致可利用 UB 或内存破坏 | 栈指针逃逸到 FFI、use-after-free |
| `high` | 跨运行时所有权违规或强内存安全风险 | Rust 分配的内存被 C `free()` |
| `medium` | 需要审核，可能是真实泄漏或所有权丢失 | owned pointer 跨 FFI 后无人释放 |
| `low` | 信息性或弱启发式信号 | 边界证据不完整但可疑 |

| 置信度 | 含义 | 排查动作 |
|--------|------|----------|
| `HIGH` | 语法和语义证据都很强 | 默认按真实问题处理，除非源码证伪 |
| `MEDIUM` | 很可能是真问题，但上下文重要 | 检查源码和 allocator 归属 |
| `LOW` | 启发式信号 | 作为 review 线索，不建议直接阻断发布 |

## 示例 1：Rust 分配，C 释放

源码示例：`corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_01_alloc_c_free(void) {
    void* ptr = _RZN4alloc5alloc17h_allocate(128);
    strcpy((char*)ptr, "allocated in Rust");
    free(ptr);  /* BUG: C free() on Rust-allocated memory */
}
```

如何解读：

- `kind` 通常会是 `cross_lang_free_mismatch`、`cross_language_free` 或相关所有权问题。
- `severity` 通常是 `high`，因为指针由 Rust allocator 分配，却由 C allocator family 释放。
- `location.function` 中的 `rust_01_alloc_c_free` 是源码定位入口。
- 需要确认的证据：分配符号像 Rust allocator，释放 sink 是 C `free()`。
- 修复方向：提供 Rust 侧释放 API，或者让 C 只把指针交还给 Rust 释放。

关键问题不是“这个指针有没有释放”，而是“释放它的运行时是否就是分配它的运行时”。

## 示例 2：`Box::into_raw` 交给 C 后被错误释放

源码示例：`corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_03_box_raw_c_free(void) {
    void* boxed = _RZN3std3box8into_rawE(NULL);
    free(boxed);  /* BUG: should use Box::from_raw to reclaim */
}
```

如何解读：

- `Box::into_raw` 会故意把指针移出 Rust 类型系统。
- C `free()` 不会执行 Rust drop glue，也可能使用错误 allocator。
- 正确设计通常需要一个成对的 Rust API，内部调用 `Box::from_raw` 且只调用一次。
- 如果报告同时提到 double free，要检查 C 和 Rust 是否都认为自己拥有该指针。

建议 review 问题：

- `Box::into_raw` 后是否只有一个明确 owner？
- 是否只有一条释放路径？
- 释放路径是否在 Rust 中实现，而不是普通 C `free()`？

## 示例 3：C 分配，Rust 释放

源码示例：`corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_02_c_alloc_rust_free(void) {
    void* ptr = malloc(256);
    strcpy((char*)ptr, "allocated in C");
    _RZN4alloc5alloc17h_deallocate(ptr);  /* BUG: Rust free on C memory */
}
```

如何解读：

- 分配点属于 C (`malloc`)。
- 释放点属于 Rust allocator 语义。
- 即使某个平台上两者最终都走系统 heap，这种写法也不具备可移植的契约安全性。
- 修复方式是使用匹配的 C 释放 API，或在 Rust 中为该指针封装自定义 C deallocator。

## 示例 4：跨 FFI 保存悬垂引用

源码示例：`corpus/red_team_test/rust_ffi_bugs.c`

```c
static void* g_stored_rust_ref = NULL;

void rust_04_store_rust_ref(void) {
    void* rust_obj = _RZN4alloc5alloc17h_allocate(64);
    g_stored_rust_ref = rust_obj;
    _RZN4alloc5alloc17h_deallocate(rust_obj);
    memset(g_stored_rust_ref, 0, 64);  /* UAF */
}
```

如何解读：

- 指针逃逸到生命周期更长的 C 全局状态 `g_stored_rust_ref`。
- 原运行时释放对象后，全局指针变成悬垂指针。
- 后续通过全局指针访问就是 use-after-free。
- Surface Classifier 会帮助区分普通局部指针流与“逃逸到全局/回调/延迟使用”的 FFI 风险。

修复模式包括复制数据、使用明确 release 规则的引用计数所有权，或者要求 C 在 Rust 释放前 unregister 指针。

## 示例 5：真实项目风格的 FFI wrapper

源码示例：`examples/real_world/sqlite_ffi.c`、`examples/real_world/openssl_ffi.c`、`examples/real_world/zlib_ffi.c`

这些文件模拟常见 wrapper 错误：未检查分配结果、错误路径缺少 cleanup、所有权契约不匹配。阅读这些报告时：

- 把 wrapper 入口视为边界函数。
- 判断返回指针是 owned、borrowed，还是只在下一次调用前有效。
- 检查所有 early return 是否释放已获得资源。
- 确认是否必须使用库专用 deallocator，而不是通用 `free()`。

## 阅读 mangled 函数名

OmniScope 在 LLVM IR 层工作，因此报告可能包含 mangled name。

| 前缀或模式 | 可能来源 | 含义 |
|------------|----------|------|
| `_Z...` | C++ Itanium ABI | C++ 函数或 operator 符号 |
| `_R...` 或 Rust legacy `_ZN...` | Rust | Rust 函数、allocator、drop glue、std/alloc 符号 |
| `Py...` | CPython | Python C API 或扩展边界 |
| `Java_...` 或 JNI 类型 | Java/JNI | Native method 或 JNI helper |
| `runtime.*`、`_Cgo_*` | Go/TinyGo | Runtime 或 CGo 边界 |

如果函数名看起来像运行时/编译器内部实现，需要看报告是否解释了它为什么仍然和用户风险相关。0.2.0 的语义解析和 Surface Classifier 目标之一就是过滤纯运行时噪音，保留和用户 FFI 边界相关的证据。

## CI 使用建议

```bash
./zig-out/bin/OmniScope target.bc --json > report.json
./zig-out/bin/OmniScope target.bc --sarif > results.sarif
```

建议默认策略：

- 对 `critical` 且 `HIGH`/`MEDIUM` 置信度的问题阻断构建。
- 在基线稳定前，对 `high` 问题先告警。
- 保存 JSON 报告，用于比较不同版本的 issue 数量和置信度变化。
- 使用 GitHub Code Scanning 时上传 SARIF。

## 误报审核清单

在 suppress 一个 finding 之前，确认：

- 报告函数确实是编译器/运行时内部实现，而不是用户 wrapper。
- allocator 和 deallocator 在所有支持平台上都有意兼容。
- 所有权转移有文档说明，并由 API 设计强制执行。
- 指针没有逃逸到全局状态、回调、后台线程或延迟 cleanup。
- 报告不是指向正常测试很少覆盖的错误路径。

只有在所有权契约被明确记录后再 suppress。大多数 FFI bug 是契约 bug，而不是局部语法 bug。
