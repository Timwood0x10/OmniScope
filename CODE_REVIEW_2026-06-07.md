# Code Review — 未提交改动（2026-06-07）

5 个文件改动，方向都对，但**有 4 处必须先修**。

## 改动概览

| 文件 | 主题 |
|---|---|
| `build.zig` + `src/ir/llvm_cpp_bridge.cpp` (新) + `src/ir/llvm_safe.zig` | C++ 桥替代 `llvm-as` |
| `src/diag/aggregator.zig` | 同 message 跨函数聚合 |
| `src/pass/analysis/ffi/cross_lang_dataflow.zig` | Orphan 抑制收紧 |
| `src/semantics/language_detector.zig` | metadata 优先的语言检测 |

## 🔴 必改 4 处

### 1. `aggregator.zig:307-352` — 聚合根本不聚合

原诊断仍走到 `return true` 入列，summary 只是**额外加一条**。结果：930 条噪音 → 931 条，比之前还多 1 条。

**修法**：改成延迟分桶——所有诊断先暂存，`flush()` 时按 `(kind+message)` 分桶，超阈值的折叠成 1 条 summary。

### 2. `aggregator.zig:336` — fold 文本是乱码

`"折叠前请款未变更，但是格式很有规律..."` 不是中文，模型幻觉。改成英文：

```
"[aggregated] {s} ×{d} (first: {s})"
```

### 3. `language_detector.zig:151, 157` — 两处栈缓冲区溢出

```zig
var cu_operands: [METADATA_MAX_CU]c.LLVMValueRef = undefined;  // 容量 4
c.LLVMGetNamedMetadataOperands(module, "llvm.dbg.cu", &cu_operands);
```

`LLVMGetNamedMetadataOperands` 不接受 buffer 大小，按 `LLVMGetNamedMetadataNumOperands` 实际个数写。`cu_count > 4`（LTO 模块常见）就**栈溢出**。同样的 bug 在 `LLVMGetMDNodeOperands` 那行——DICompileUnit 有 15-20 个字段，容易超 10。

**修法**：改堆分配，按 LLVM 给的 num 取 buffer 大小。

### 4. `cross_lang_dataflow.zig:530` — 同 bug 改了一半

文件里有两处 `funcs_with_frees.contains(alloc.alloc_func)` 用同一过宽启发式。这次只改了 line 953-973，**line 530 还是原样**。把新逻辑套用过去，或者抽成共用函数。

## 🟠 高优先级 4 处

| 位置 | 问题 |
|---|---|
| `language_detector.zig:171, 202` | `"rust"`/`"go"` 子串匹配过宽 —— `"go"` 两字符会误匹配 `"google"`、`"Lego"`。改成 `startsWith("rustc")` / `startsWith("Go cmd/compile")` |
| `llvm_safe.zig:183-189` | C++ 桥走 `.ll` 路径时仍然 `LLVMCreateMemoryBufferWithContentsOfFile` 多读一次文件，然后 dispose 掉。后缀判断提前到 buffer 创建之前 |
| `llvm_cpp_bridge.cpp:23-30` | `omni_create_llvm_context`/`destroy_llvm_context` 是死代码（Zig 端没调用）。删掉，或在桥里用 LLVM `unwrap()` 宏表达 C API ↔ C++ 的转换意图 |
| `llvm_cpp_bridge.cpp:38-50` | `omni_parse_ir_file` 完全没 null 检查（`path`/`context`/`module_out`），`strdup` OOM 失败时 caller 拿到 nullptr 会二次崩 |

## 🟡 中/低（合入后再清理）

- `llvm_safe.zig:188` 死赋值 `parse_result = 0`
- `aggregator.zig:325` `kind_tag` 是 `@tagName(...)` 的静态字符串，不需要 dup
- `build.zig:82` `linkSystemLibrary("c++")` 是 macOS 特定，Linux 上要 `stdc++`
- C++ 桥建议加 `-fno-exceptions -fno-rtti`，函数加 `noexcept`
- `DetectionMethod` 新增 `metadata`，grep 一下确保所有 switch 都覆盖

## 合入顺序

1. 修必改 4 处
2. 修高优先级 4 处
3. 重跑 `/tmp/bun_ll/*.ll`，看 `issue_count` 从 1327 真降到 ~400
4. 跑 noise 回归套件（`rust_ffi`/`gopyjava`/`cscpp`）防 cross_lang 改动回归
5. 拆 4 个 commit：llvm 解耦 / cross_lang 收紧 / metadata 语言检测 / 聚合重写

## C++ 单独回应

C++ 代码审过了，覆盖在高 #7、#8 和中低条目里：
- 死代码 + 隐性 C API/C++ ABI 耦合（依赖 `LLVMContextRef` typedef 巧合）
- 全函数缺 null 检查
- `strdup` OOM 无兜底
- `-std=c++17` 没和 LLVM 22 实际要求对齐
- `extern "C"` 不阻断 C++ 异常传播
