# OmniScope FFI 代码审查报告 - 终版

**审查日期**: 2026-06-09
**审查范围**: 全部核心源码、测试、脚本、CI/CD、构建系统
**审查类型**: 静态代码分析（dead code、潜在bug、不准确注释、架构问题）

---

## 1. CRITICAL BUGS

### 1.1 `/src/ffi_precision.zig` — 子串匹配导致白名单绕过

**文件**: `/Users/scc/code/zigcode/OmniScope/src/ffi_precision.zig`

**描述**: 使用 `std.mem.indexOf` 做子串匹配导致 "safe" 能匹配 "unsafe"、"lock" 能匹配 "deadlock"。应将精确匹配改为整词匹配。

**严重程度**: 🔴 CRITICAL

**建议**: 将子串匹配改为整词匹配（如使用 `std.mem.eql` 或在前后添加分隔符检查）。

---

### 1.2 `/src/pass/analysis/rust_ffi/rust_ffi_rules_basic.zig` — Rule 3 完全失效

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/rust_ffi/rust_ffi_rules_basic.zig`

**描述**: `extract_unsafe_impl` 总是返回 `skip`，导致整个规则从未触发任何检测。关键的安全检测通道处于死状态。

**严重程度**: 🔴 CRITICAL

**建议**: 修复 `extract_unsafe_impl` 的实现，使其正确提取 unsafe 实现并返回有效数据。

---

### 1.3 `/src/semantics/zig_allocator_tracker.zig:81,164` — 悬挂指针

**文件**: `/Users/scc/code/zigcode/OmniScope/src/semantics/zig_allocator_tracker.zig`

```zig
// 行81: 在函数栈上分配缓冲区
var reason_buf: [256]u8 = undefined;
var reason: []const u8 = "";

// 行164: reason 指向栈上缓冲区
reason = std.fmt.bufPrint(&reason_buf, "Zig container ({s})", .{@tagName(container)}) catch reason;

// 函数返回 LeakConfidence 结构体包含 reason 切片
return .{
    .score = score,
    .reason = if (reason.len > 0) reason else "unknown",
};
```

**描述**: `reason_buf` 是函数栈上的局部变量，`reason` 切片通过 `bufPrint` 指向此缓冲区。但返回的 `LeakConfidence` 结构体包含 `reason` 字段，在函数返回后 `reason_buf` 会随栈帧释放，使 `reason` 变为悬挂指针。

**严重程度**: 🔴 CRITICAL

**建议**: 将 `reason` 改为使用 `self.allocator` 分配的堆内存；或将 `reason_buf` 改为 `LeakConfidence` 的固定大小字段而非切片。

---

### 1.4 `/src/pass/analysis/ffi/ffi_unsafe.zig:120` — isDangerous 无条件返回 false

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_unsafe.zig`

```zig
pub fn isDangerous(func_name: []const u8, store: ?*const SummaryStore) bool {
    const clean = if (func_name.len > 0 and func_name[0] < 32) func_name[1..] else func_name;
    if (store) |s| {
        if (s.lookup(clean)) |summary| { ... return true; }
    }
    return false; // 当 store 为 null 时，所有函数都返回 false！
}
```

**描述**: 当没有 `SummaryStore` 时对所有函数返回 false。旧版的 fallback 危险函数列表已被移除且未提供替代方案。整个检测模块静默失效。`system`、`strcpy`、`setjmp` 等函数在没有 SummaryStore 时将完全不被检测。

**严重程度**: 🔴 CRITICAL

**建议**: 恢复 fallback 危险函数列表，或在 SummaryStore 未加载时发出编译时/运行时警告。

---

### 1.5 `scripts/stability_test.sh:92-94` — 反斜杠续行语法错误

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/stability_test.sh`

**描述**: `timeout 30 ./zig-out/bin/OmniScope "$large_ir" \` 后的 `log_fail` 被当作命令行参数传给 OmniScope，而非独立的错误处理。OmniScope 收到错误参数。

**严重程度**: 🔴 CRITICAL

**建议**: 确保反斜杠续行正确，将 `log_fail` 放在新的命令行中，而非续行之后。

---

### 1.6 `scripts/stability_test.sh:113-118` — output 变量从未传递给 OmniScope

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/stability_test.sh`

**描述**: `local output="/tmp/e2e_output_..."` 定义了但从未通过 `-o` 参数传给 OmniScope。E2E Pipeline 测试始终报告 `0 files processed`。

**严重程度**: 🔴 CRITICAL

**建议**: 将 `-o "$output"` 添加到 OmniScope 调用参数中。

---

### 1.7 `scripts/regression_test.sh:108-109` — Go IR 编译使用 -S 输出汇编

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/regression_test.sh`

**描述**: `go tool compile -S` 输出 plan9 汇编，不是 LLVM IR。通过 `llvm-as` 会产生垃圾或空 bitcode。`|| true` 和 `2>/dev/null` 静默吞噬了所有错误。

**严重程度**: 🔴 CRITICAL

**建议**: 使用 `go tool compile -o output.o file.go` 生成对象文件，再通过 LLVM 工具提取 IR。

---

### 1.8 `corpus_verify.sh:66` — timeout 在 macOS 上不可用

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/corpus_verify.sh`

**描述**: `timeout` 是 GNU coreutils 命令，macOS 默认不提供。整个超时机制在 macOS 上静默失效。

**严重程度**: 🔴 CRITICAL

**建议**: 使用 `gtimeout`（brew install coreutils）或使用 `perl -e alarm` 实现跨平台超时。

---

### 1.9 `build.zig:8,16` — LLVM 22 不存在

**文件**: `/Users/scc/code/zigcode/OmniScope/build.zig`

**描述**: `getDefaultLLVMPath()` 返回 `/usr/lib/llvm-22`，`getDefaultLLVMVersion()` 返回 `"22"`。截至 2026 年中，LLVM 最新版本为 19-20。

**严重程度**: 🔴 CRITICAL

**建议**: 更新为实际可用的 LLVM 版本（如 19）。

## 2. HIGH SEVERITY BUGS

### 2.1 `/src/visual/graph_visualizer.zig` — Zig API 误用导致编译错误

**文件**: `/Users/scc/code/zigcode/OmniScope/src/visual/graph_visualizer.zig`

**描述**: 在 Zig 0.13+ 中，`append` 和 `deinit` 等函数已不再接受 `allocator` 参数。`toOwnedSlice` 返回 `[]u8` 而非 `[:0]u8`。`@memcpy` 浅拷贝导致 use-after-free。

**严重程度**: 🟠 HIGH

**建议**: 按照 Zig 0.13+ 的新 API 规范更新调用方式。

---

### 2.2 `/src/analysis/escape_analysis.zig` — 完全存根

**文件**: `/Users/scc/code/zigcode/OmniScope/src/analysis/escape_analysis.zig`

**描述**: `analyzeAlloc` 总是返回 `EscapeStatus.unknown`，`analyzeFunction` 不做任何分析。整个逃逸分析通道是空壳。

**严重程度**: 🟠 HIGH

**建议**: 实现实际的逃逸分析算法，或明确标记为 TODO 并移除未使用的调用路径。

---

### 2.3 `/src/analysis/raii_detector.zig` — shouldSuppressLeakDueToRAII 总是返回 false

**文件**: `/Users/scc/code/zigcode/OmniScope/src/analysis/raii_detector.zig`

**描述**: 从未实际检测 RAII 模式。

**严重程度**: 🟠 HIGH

**建议**: 实现 RAII 模式检测逻辑，或移除该函数及其调用者。

---

### 2.4 `/src/resource/ffi_contract_db.zig` — getAllAllocFuncs 返回空切片

**文件**: `/Users/scc/code/zigcode/OmniScope/src/resource/ffi_contract_db.zig`

**描述**: 在 `getAllocFuncs` 内部填充数据后，`getAllAllocFuncs` 返回空结果。

**严重程度**: 🟠 HIGH

**建议**: 检查 `getAllAllocFuncs` 与 `getAllocFuncs` 之间的数据传递逻辑。

---

### 2.5 `/src/resource/ffi_contract_db_data.zig` — TLS_method 被误分类为 SSL_CTX 分配函数

**文件**: `/Users/scc/code/zigcode/OmniScope/src/resource/ffi_contract_db_data.zig`

**描述**: TLS_method 是 SSL/TLS 上下文创建函数，被归入 SSL_CTX 分配类别。

**严重程度**: 🟠 HIGH

**建议**: 将 TLS_method 正确分类。

---

### 2.6 `/src/output_formatter.zig` — Vulnerability 结构体版本兼容性问题

**文件**: `/Users/scc/code/zigcode/OmniScope/src/output_formatter.zig`

**描述**: Vulnerability 结构体通过新字段扩展时，不兼容的旧版本反序列化。

**严重程度**: 🟠 HIGH

**建议**: 添加版本控制和后向兼容的序列化/反序列化逻辑。

---

### 2.7 `tests/main.zig` vs `tests/regression.zig` — RiskKind 变体计数冲突

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/main.zig` 和 `/Users/scc/code/zigcode/OmniScope/tests/regression.zig`

**描述**: `main.zig` 期望恰好 21 个变体，`regression.zig` 期望恰好 13 个。至少一个严重过时。

**严重程度**: 🟠 HIGH

**建议**: 统一两个测试文件中的期望计数，或改为根据实际枚举字段动态计算。

---

### 2.8 `tests/ffi_boundary_check_test.zig:16-17` — 使用 GPA 绕过泄漏检测

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/ffi_boundary_check_test.zig`

**描述**: 使用 `std.heap.GeneralPurposeAllocator(.{}){}` 而非 `std.testing.allocator`，绕过内存泄漏检测。

**严重程度**: 🟠 HIGH

**建议**: 替换为 `std.testing.allocator` 并修复泄漏问题。

---

### 2.9 `tests/buffer_overflow_test.zig:16-18` — 同样使用 GPA 绕过泄漏检测

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/buffer_overflow_test.zig`

**描述**: 使用 `std.heap.GeneralPurposeAllocator(.{}){}` 而非 `std.testing.allocator`，绕过内存泄漏检测。

**严重程度**: 🟠 HIGH

**建议**: 替换为 `std.testing.allocator` 并修复泄漏问题。

---

### 2.10 `tests/verify_leak_confidence.zig` — 所有测试验证硬编码值

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/verify_leak_confidence.zig`

**描述**: 手工数学运算的浮点值被硬编码，不调用任何生产代码。测试验证的是预期而非实际逻辑。

**严重程度**: 🟠 HIGH

**建议**: 重写测试使其调用实际的生产代码路径。

---

### 2.11 `.github/workflows/test.yml:6-7` — 分支触发器不存在

**文件**: `/Users/scc/code/zigcode/OmniScope/.github/workflows/test.yml`

**描述**: `[main, develop, master]` 在当前仓库中均不存在。实际开发分支是 `dev`，`ci.yml` 使用的是 `[master, improve, dev]`。

**严重程度**: 🟠 HIGH

**建议**: 将分支触发器更新为实际存在的分支名。

---

### 2.12 `scripts/test.sh:33` — ELAPED 拼写错误

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/test.sh`

**描述**: `${ELAPED}` 扩展为空字符串，测试时长信息静默丢失。

**严重程度**: 🟠 HIGH

**建议**: 修正为 `ELAPSED`。

---

### 2.13 `corpus/README.md:12-19` — 完全虚构的目录结构

**文件**: `/Users/scc/code/zigcode/OmniScope/corpus/README.md`

**描述**: 声称存在 `small/`、`medium/`、`large/`、`ffi-dense/` 目录，但实际语料库结构完全不同。

**严重程度**: 🟠 HIGH

**建议**: 更新 README.md 以反映实际的语料库目录结构。

---

### 2.14 `scripts/install_deps.sh:137` — brew install llvm@22 不存在

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/install_deps.sh`

**描述**: `brew install llvm@22` 的 LLVM 22 版本不存在。

**严重程度**: 🟠 HIGH

**建议**: 更新为实际可用的 LLVM 版本。

## 3. MEDIUM SEVERITY BUGS

### 3.1 `/src/pass/analysis/buffer_overflow.zig` — 越界检查符号反转

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/buffer_overflow.zig`

**描述**: 使用 `>=` 而非 `>`（或反之），导致数组越界漏报。

**严重程度**: 🟡 MEDIUM

**建议**: 审查越界条件逻辑，确保比较运算符正确。

---

### 3.2 `/src/pass/analysis/danger_surface.zig` — 全局缓冲区变量遗留为 0

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/danger_surface.zig`

**描述**: 调试重构后全局变量保持为 `0`，未正确设置。

**严重程度**: 🟡 MEDIUM

**建议**: 恢复正确的全局变量初始化逻辑。

---

### 3.3 `/src/pass/analysis/noise/noise_reduction.zig` — 自引用规则导致无限合并循环

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/noise/noise_reduction.zig`

**描述**: 某条规则能匹配自身输出，在合并阶段造成无限循环。

**严重程度**: 🟡 MEDIUM

**建议**: 添加规则输出与输入的循环依赖检测，或限制合并迭代次数。

---

### 3.4 `/src/pass/analysis/ffi/ffi_analysis.zig:188` — 死代码：ptr_arg orelse continue

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_analysis.zig`

**描述**: `ptr_arg` 已在前面做了 null 检查，`orelse continue` 永远不会触发。

```zig
const ptr_arg = c.LLVMGetOperand(inst, 0);
if (ptr_arg == null) {         // 已检查 null
    diag.warn("...");
    continue;                   // 已跳出的路径
}
const ptr_value_id: u64 = @intFromPtr(ptr_arg orelse continue);  // 死代码！ptr_arg 此时不可能为 null
```

**严重程度**: 🟡 MEDIUM

**建议**: 移除 `orelse continue`。

---

### 3.5 `/src/pass/analysis/ffi/ffi_boundary.zig` — detectLanguageSignal 只识别 _ZN4core/5alloc/3std

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_boundary.zig`

**描述**: 白名单只识别 Rust stdlib，遗漏非 stdlib Rust crate（如 `_ZN12my_external_crate` 会被错误归类为 C++）。

**严重程度**: 🟡 MEDIUM

**建议**: 使用 `hasRustLegacySuffix` 函数（在 `symbol_graph.zig` 中定义）来更全面地识别 Rust 函数。

---

### 3.6 `/src/pass/analysis/ffi/ffi_type_mismatch.zig` — basicBlockComesBefore 近似错误

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_type_mismatch.zig`

**描述**: 在循环上下文中不正确。注释声称"对结构化代码安全"是误导——在循环结构中，循环体内的 BB 在顺序上早于循环后的 BB，但循环体内的指令并不支配循环后的指令。

**严重程度**: 🟡 MEDIUM

**建议**: 改用 LLVM 的 DominatorTree 分析或限制此函数的使用范围为非循环上下文。

---

### 3.7 `/src/pass/analysis/issue/malloc_check.zig` — 只检测直接 malloc 调用

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/issue/malloc_check.zig`

**描述**: 函数只检查 `LLVMGetCalledValue`（直接调用），不处理通过函数指针的间接调用（indirect call）。如果 `malloc` 通过函数指针被调用，则不会被检测到。

**严重程度**: 🟡 MEDIUM

**建议**: 添加对间接调用的检测支持，或文档化此限制。

---

### 3.8 `/src/registry/semantic_registry.zig:96,100` — OOM 静默吞掉

**文件**: `/Users/scc/code/zigcode/OmniScope/src/registry/semantic_registry.zig`

**描述**: `catch continue` 和 `catch &.{}` 在 `ensureLookupTables` 中静默忽略 OOM。可能导致部分函数语义未注册但无任何告警，且丢失的条目永不会被恢复。

**严重程度**: 🟡 MEDIUM

**建议**: 至少添加 `std.log.warn` 日志记录丢失的条目数，或在失败时设置重试标志。

---

### 3.9 `/src/ffi/ffi_matcher.zig` — getUnmatchedDeclares 和 getUnmatchedDefines 完全重复

**文件**: `/Users/scc/code/zigcode/OmniScope/src/ffi/ffi_matcher.zig`

**描述**: `getUnmatchedDeclares` 和 `getUnmatchedDefines` 两个函数有完全相同的实现逻辑，仅遍历的列表不同（`declare_functions` vs `define_functions`）。DRY 违反。

**严重程度**: 🟡 MEDIUM

**建议**: 提取为接受函数列表参数的通用函数。

---

### 3.10 `/src/ffi/symbol_graph.zig` — classifySymbol 的 module 参数未使用，buildLanguageIndex 的 allocator 参数未使用

**文件**: `/Users/scc/code/zigcode/OmniScope/src/ffi/symbol_graph.zig`

**描述**: `classifySymbol` 的 `module` 参数被 `_ = module` 丢弃。`buildLanguageIndex` 的 `allocator` 参数未使用，函数内部使用 `symbols.allocator`。

**严重程度**: 🟡 MEDIUM

**建议**: 删除未使用的参数以减少混淆。

---

### 3.11 `/src/filter/filter_context.zig` — 10 层 FilterContext 有 22 个字段，部分字段未被所有层使用

**文件**: `/Users/scc/code/zigcode/OmniScope/src/filter/filter_context.zig`

**描述**: 有 3-4 个字段仅由单层使用但存在于所有层中。

**严重程度**: 🟡 MEDIUM

**建议**: 将层特定字段移到对应层的子结构体中，或使用联合类型。

---

### 3.12 `/src/lang/adapter_registry.zig` — MAX_ADAPTERS=16 但只预注册了 4 个

**文件**: `/Users/scc/code/zigcode/OmniScope/src/lang/adapter_registry.zig`

**描述**: `MAX_ADAPTERS=16` 但只预注册了 4 个。如果增加更多语言，可能达到限制。

**严重程度**: 🟡 MEDIUM

**建议**: 改为动态分配或增加 MAX_ADAPTERS 的值。

## 4. LOW SEVERITY / DEAD CODE / INACCURATE COMMENTS

### 4.1 `/src/pass/analysis/ptr_lifetime/ptr_lifetime.zig:655-668` — 14 个重导出无人使用

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ptr_lifetime/ptr_lifetime.zig`

**描述**: 所有 14 个 `pub const` 报告函数重导出没有外部导入者。`root.zig` 只导入 6 个符号，`pipeline_deps_test.zig` 只导入 `PtrLifetimePass`。

**严重程度**: 🔵 LOW

**建议**: 删除未使用的重导出。

---

### 4.2 `/src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig` — 3 个未使用的导入/变量

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig`

**描述**: `reportReturnHeapPtr`（行62）和 `classifyAllocLanguageEnum`（行34）被导入但从未使用。`_ = stats`（行84）未使用参数抑制。

**严重程度**: 🔵 LOW

**建议**: 移除未使用的导入；若 `stats` 参数确实不需要，从函数签名中移除。

---

### 4.3 `/src/pass/analysis/rust_ffi/rust_ffi_helpers.zig` — 函数指针兼容性问题

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/rust_ffi/rust_ffi_helpers.zig`

**描述**: 函数指针兼容性问题。

**严重程度**: 🔵 LOW

---

### 4.4 `/src/perf/` — 所有 5 个分析器函数是存根

**文件**: `/Users/scc/code/zigcode/OmniScope/src/perf/`

**描述**: `sampleRss`、`sampleHeapAllocs` 等都返回 0。

**严重程度**: 🔵 LOW

**建议**: 实现实际的性能采样逻辑，或移除存根函数。

---

### 4.5 `/src/whitelists/rust_internal.zig` — 标记为 DEPRECATED 但有活跃代码

**文件**: `/Users/scc/code/zigcode/OmniScope/src/whitelists/rust_internal.zig`

**描述**: 文件标记为 DEPRECATED 但包含活跃代码，且有零个外部调用者。

**严重程度**: 🔵 LOW

**建议**: 清理废弃代码或移除 DEPRECATED 标记。

---

### 4.6 `/src/ffi/ffi_boundary.zig:4-6` — 文件头声称"已重构为<200行"，实际 1126 行

**文件**: `/Users/scc/code/zigcode/OmniScope/src/ffi/ffi_boundary.zig`

**描述**: 文件头注释明确指出该文件已被重构到"不到200行"，但实际上文件有 **1126 行**。注释可能是重构过程中的中间状态，未及时更新的严重误导性信息。

**严重程度**: 🔵 LOW

**建议**: 更新文件头注释以反映实际行数。

---

### 4.7 `tests/integration_ir_test.zig:11-14` — getTestIRPath 有无用 allocator 参数

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/integration_ir_test.zig`

**描述**: `getTestIRPath` 的 allocator 参数未使用。

**严重程度**: 🔵 LOW

---

### 4.8 `tests/e2e_ir_test.zig:35` — 未使用的导入：PassContext、Diagnostic、LoaderError

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/e2e_ir_test.zig`

**描述**: `PassContext`、`Diagnostic`、`LoaderError` 被导入但未使用。

**严重程度**: 🔵 LOW

---

### 4.9 `tests/integration.zig` — 使用相对导入路径绕过模块系统

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/integration.zig`

**描述**: 使用相对导入路径绕过模块系统。

**严重程度**: 🔵 LOW

---

### 4.10 `scripts/bench_perf.sh` — BUILD_DIR 指向 build/ 而非 zig-out/bin/

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/bench_perf.sh`

**描述**: `BUILD_DIR` 指向 `build/` 而非 `zig-out/bin/`。

**严重程度**: 🔵 LOW

---

### 4.11 `scripts/benchmark.sh` — JSON 报告可能为空

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/benchmark.sh`

**描述**: JSON 报告可能为空。

**严重程度**: 🔵 LOW

---

### 4.12 `scripts/release.sh` — 相对干净但缺少 dry-run 模式

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/release.sh`

**描述**: 相对干净但缺少 dry-run 模式。

**严重程度**: 🔵 LOW

---

### 4.13 `scripts/test.sh` — ELAPED 拼写错误已在 HIGH 中记录

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/test.sh`

**描述**: 已在 2.12 中记载。

**严重程度**: 🔵 LOW

---

### 4.14 `scripts/stability_test.sh:20` — 过时的 DC-C12 FIX 开发注释未移除

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/stability_test.sh`

**描述**: 过时的 `DC-C12 FIX` 开发注释未移除。

**严重程度**: 🔵 LOW

---

### 4.15 `scripts/regression_test.sh:22` — 过时的 DC-C11 FIX 开发注释未移除

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/regression_test.sh`

**描述**: 过时的 `DC-C11 FIX` 开发注释未移除。

**严重程度**: 🔵 LOW

---

### 4.16 `scripts/run_audit.py:5` — 版本号 v0.1.7 vs v0.1.8 漂移

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/run_audit.py`

**描述**: 版本号 v0.1.7 与 v0.1.8 漂移。

**严重程度**: 🔵 LOW

---

### 4.17 `scripts/benchmark.sh:253,347` — 版本号 v0.1.8 可能与 VERSION 文件不符

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/benchmark.sh`

**描述**: 版本号 v0.1.8 可能与 VERSION 文件不符。

**严重程度**: 🔵 LOW

---

### 4.18 `tests/cross_lang_test.zig` — 许多测试只做平凡断言，不测试实际跨语言分析逻辑

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/cross_lang_test.zig`

**描述**: 许多测试只做平凡断言，不测试实际跨语言分析逻辑。

**严重程度**: 🔵 LOW

---

### 4.19 `tests/semantic_resolution_test.zig` — 节点计数测试可能因内部节点创建而不准确

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/semantic_resolution_test.zig`

**描述**: 节点计数测试可能因内部节点创建而不准确。

**严重程度**: 🔵 LOW

---

### 4.20 `tests/into_raw_gate_test.zig` — 测试名称暗示 allow 是预期但可能过时

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/into_raw_gate_test.zig`

**描述**: 测试名称暗示 `allow` 是预期但可能过时。

**严重程度**: 🔵 LOW

---

### 4.21 `Makefile` — 多处 2>/dev/null || true 静默掩盖编译错误

**文件**: `/Users/scc/code/zigcode/OmniScope/Makefile`

**描述**: 多处 `2>/dev/null || true` 静默掩盖编译错误。

**严重程度**: 🔵 LOW

---

### 4.22 `Makefile:~578` — 孤立的 @echo "%" 打印无意义的 %

**文件**: `/Users/scc/code/zigcode/OmniScope/Makefile`

**描述**: 孤立的 `@echo "%"` 打印无意义的 %。

**严重程度**: 🔵 LOW

---

### 4.23 `.github/workflows/ci.yml` — zvm i vs zvm install 不一致

**文件**: `/Users/scc/code/zigcode/OmniScope/.github/workflows/ci.yml`

**描述**: `zvm i` vs `zvm install` 不一致。

**严重程度**: 🔵 LOW

---

### 4.24 `.github/workflows/release.yml` — 同样 zvm i vs zvm install 不一致

**文件**: `/Users/scc/code/zigcode/OmniScope/.github/workflows/release.yml`

**描述**: 与 ci.yml 同样的问题。

**严重程度**: 🔵 LOW

---

### 4.25 `.github/workflows/test.yml` — 与 ci.yml 高度重叠，造成混淆

**文件**: `/Users/scc/code/zigcode/OmniScope/.github/workflows/test.yml`

**描述**: 与 ci.yml 高度重叠，造成混淆。

**严重程度**: 🔵 LOW

---

### 4.26 `/src/pass/analysis/ffi/ffi_analysis.zig` — errdefer 只覆盖首次插入 + 多余 _ = &list

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_analysis.zig`

**描述**: `collectFreeSites` 中如果已存在列表的 `list_ptr.append()` 失败（OOM），没有 errdefer 清理该列表。errdefer 只覆盖新创建的列表路径。此外 `_ = &list;` 是多余语句。

**严重程度**: 🔵 LOW

---

### 4.27 `/src/pass/analysis/ffi/ffi_analysis.zig` — 行106-108 和 行224-226 注释完全重复

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_analysis.zig`

**描述**: "v0.2.0: Skip compiler-generated..." 5行注释在 `collectAllocationSites` 和 `collectFreeSites` 中完全相同。

**严重程度**: 🔵 LOW

---

### 4.28 `/src/pass/analysis/ffi/ffi_analysis.zig` — catch return 静默吞掉 OOM

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_analysis.zig`

**描述**: `catch return` 在行328-349静默吞掉 OutOfMemory 错误，返回类型是 `!void`，应传播错误。

**严重程度**: 🔵 LOW

---

### 4.29 `/src/pass/analysis/ffi/ffi_boundary.zig` — functionHasMatchingPair 不检查配对相关性

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_boundary.zig`

**描述**: `functionHasMatchingPair` 只检查函数中是否同时存在 allocator 和 deallocator 调用，而不验证它们是否匹配同一个指针。

**严重程度**: 🔵 LOW

---

### 4.30 `/src/pass/analysis/ffi/ffi_type_mismatch.zig` — LLVM API 调用链脆弱

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_type_mismatch.zig`

**描述**: 通过 instruction → BB → function → module → dataLayout 的5步链来获取类型大小。每一步都可能失败，在常量表达式中的调用场景下中间值可能无效。

**严重程度**: 🔵 LOW

---

### 4.31 `/src/pass/analysis/ffi/ffi_type_mismatch.zig` — checkGoPointerEscape 扫描窗口太小

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_type_mismatch.zig`

**描述**: Go 的 `runtime.KeepAlive` 必须在变量最后一次使用之后调用，但距离 C 调用可能有一定距离。10条指令的窗口可能不够，且只扫描同一个基本块。

**严重程度**: 🔵 LOW

---

### 4.32 `/src/pass/analysis/issue/malloc_check.zig` — null 检查只处理最直接的模式

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/issue/malloc_check.zig`

**描述**: 编译器可能将 null 比较优化为其他形式（如 `@llvm.expect` 或 `select`），或者在比较之前将指针转换为整数。当前的 `LLVMIsNull` 检查只处理最直接的 `icmp eq/ne ptr, null` 模式。

**严重程度**: 🔵 LOW

---

### 4.33 `/src/pass/analysis/issue/malloc_check.zig` — trace 内存管理风险 / 未使用的导入

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/issue/malloc_check.zig`

**描述**: 需要确认 `Issue.deinit` 是否会释放 trace。`IssueKind` 被导入但从未使用。

**严重程度**: 🔵 LOW

---

### 4.34 `/src/pass/analysis/ffi/ffi_unsafe.zig` — 文件头声称"4层过滤"但第4层已被移除

**文件**: `/Users/scc/code/zigcode/OmniScope/src/pass/analysis/ffi/ffi_unsafe.zig`

**描述**: 文件头声明"4层过滤"但第4层（去重）已被移除。`DedupKey` 结构体是残留物。

**严重程度**: 🔵 LOW

---

### 4.35 `/src/semantics/zig_allocator_tracker.zig` — 未使用的 log 导入

**文件**: `/Users/scc/code/zigcode/OmniScope/src/semantics/zig_allocator_tracker.zig`

**描述**: `const log = std.log.scoped(.zig_allocator_tracker);` 在文件中的任何位置都未被引用。

**严重程度**: 🔵 LOW

---

### 4.36 `/src/semantics/zig_allocator_tracker.zig` — 注释只提到 ArrayList

**文件**: `/Users/scc/code/zigcode/OmniScope/src/semantics/zig_allocator_tracker.zig`

**描述**: 注释只说 "ArrayList = managed by container"，但代码实际处理了多个容器类型（`.zig_arraylist`、`.zig_hashmap`、`.zig_buffer`、`.zig_multiarraylist`）。

**严重程度**: 🔵 LOW

---

### 4.37 `/src/registry/semantic_registry.zig` — "15层数组"实际是16层

**文件**: `/Users/scc/code/zigcode/OmniScope/src/registry/semantic_registry.zig`

**描述**: 注释说 "15 layer arrays"，但 `all_layers` 数组包含16个条目。

**严重程度**: 🔵 LOW

---

### 4.38 `/src/registry/semantic_registry.zig` — RiskKind 枚举字段数测试脆弱

**文件**: `/Users/scc/code/zigcode/OmniScope/src/registry/semantic_registry.zig`

**描述**: 测试精确检查 RiskKind 枚举有21个字段。添加或删除任何变体时，此测试将静默失败。

**严重程度**: 🔵 LOW

---

### 4.39 `/src/registry/semantic_registry.zig` — Spinlock 模式未处理线程竞态

**文件**: `/Users/scc/code/zigcode/OmniScope/src/registry/semantic_registry.zig`

**描述**: 在 fast path 的 `if (exact_map != null) return;` 和锁获取之间没有内存屏障。建议使用 `@atomicLoad` 进行读取。

**严重程度**: 🔵 LOW

---

### 4.40 `corpus/EXPECTED_RESULTS.md:14` — null_dereference 计数 2 但列出 3 个用例

**文件**: `/Users/corpus/EXPECTED_RESULTS.md`

**描述**: null_dereference 计数为 2 但列出 3 个用例，数据不一致。

**严重程度**: 🔵 LOW

---

### 4.41 `corpus/EXPECTED_RESULTS.md:405-407` — 检测率目标与 benchmark.sh 不匹配

**文件**: `/Users/corpus/EXPECTED_RESULTS.md`

**描述**: 文档说 Precision>=95%, Recall>=90%, F1>=92%，但 benchmark.sh 使用 TARGET_PRECISION=0.40, TARGET_RECALL=0.70, TARGET_F1=0.54。

**严重程度**: 🔵 LOW

---

### 4.42 `scripts/run_audit.py:44-57` — JSON 输出在 returncode != 0 时丢失

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/run_audit.py`

**描述**: stderr 被保存但 stdout/JSON 从未被保存。后续尝试打开不存在的 JSON 文件。

**严重程度**: 🔵 LOW

---

### 4.43 `scripts/baseline_check.sh:72-76` — issue 提取逻辑复杂且易出错

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/baseline_check.sh`

**描述**: grep -c 计数与 awk 提取值可能不一致。硬编码的 IR 文件路径与语料库实际路径不匹配。

**严重程度**: 🔵 LOW

---

### 4.44 `scripts/run-all-tests.sh` — xargs + awk 分割潜在问题

**文件**: `/Users/scc/code/zigcode/OmniScope/scripts/run-all-tests.sh`

**描述**: xargs + awk 分割潜在问题。

**严重程度**: 🔵 LOW

---

### 4.45 `build.zig` — configureCppBridge() 定义但从未被调用

**文件**: `/Users/scc/code/zigcode/OmniScope/build.zig`

**描述**: configureCppBridge() 定义但从未被调用。

**严重程度**: 🔵 LOW

---

### 4.46 `tests/ffi_integration_test.zig:164` — "a" ** 2000 字符串乘法

**文件**: `/Users/scc/code/zigcode/OmniScope/tests/ffi_integration_test.zig`

**描述**: 编译时类型为 `*const [2000]u8` 而非 `[]const u8`。

**严重程度**: 🔵 LOW

---

## 5. 总结统计

| 严重程度 | 数量 | 说明 |
|----------|------|------|
| 🔴 CRITICAL | 9 | 安全检测失效、悬挂指针、语法错误、LLVM 版本错误 |
| 🟠 HIGH | 14 | 全存根检测通道、测试绕过泄漏检测、分支配置错误、文档与事实严重不符 |
| 🟡 MEDIUM | 12 | 逻辑错误、死代码、OOM 静默吞掉、未使用参数、架构缺陷 |
| 🔵 LOW | 46 | 死代码重导出、注释不准确、未使用导入、开发残留注释、版本号漂移 |

**总计: 81 个问题**

### 按类别统计

| 类别 | 数量 |
|------|------|
| potential_bug（潜在 Bug） | ~25 |
| dead_code（死代码） | ~20 |
| inaccurate_comment（不准确注释） | ~18 |
| fragile_test（脆弱测试） | ~5 |
| architecture（架构问题） | ~8 |
| config/ci（配置/CI 问题） | ~5 |

### 按文件区域统计

| 区域 | 问题数 | 关键问题 |
|------|--------|----------|
| `src/`（核心源码） | ~40 | 悬挂指针、死代码、检测失效、OOM 静默吞掉 |
| `tests/`（测试文件） | ~12 | GPA 绕过泄漏检测、硬编码值、版本号漂移 |
| `scripts/`（脚本） | ~15 | 语法错误、变量未传递、macOS 兼容性、版本号漂移 |
| `.github/`（CI/CD） | ~4 | 分支不存在、zvm 命令不一致、工作流重叠 |
| `corpus/`（语料库） | ~4 | README 虚构结构、数据不一致、目标不匹配 |
| `build.zig` / `Makefile` | ~4 | LLVM 版本错误、死函数、隐藏编译错误 |

---

## 6. 最关键的发现 Top 10

| 排名 | 问题 | 严重程度 | 影响 |
|------|------|----------|------|
| 1 | **`ffi_precision.zig` 子串匹配导致白名单绕过** | 🔴 CRITICAL | "safe" 匹配 "unsafe"，安全检测可被绕过 |
| 2 | **`rust_ffi_rules_basic.zig` Rule 3 完全失效** | 🔴 CRITICAL | Rust unsafe 检测从未触发 |
| 3 | **`zig_allocator_tracker.zig` 悬挂指针** | 🔴 CRITICAL | 返回指向栈内存的切片，导致未定义行为 |
| 4 | **`ffi_unsafe.zig` isDangerous 无条件返回 false** | 🔴 CRITICAL | 无 SummaryStore 时所有危险函数不被检测 |
| 5 | **`stability_test.sh` 反斜杠续行语法错误** | 🔴 CRITICAL | 错误参数传入 OmniScope |
| 6 | **`stability_test.sh` output 变量从未传递** | 🔴 CRITICAL | E2E Pipeline 测试始终报告 0 files processed |
| 7 | **`regression_test.sh` Go IR 编译使用 -S 输出汇编** | 🔴 CRITICAL | Go IR 测试产生垃圾 bitcode |
| 8 | **`build.zig` LLVM 22 不存在** | 🔴 CRITICAL | 构建系统指向不存在的版本 |
| 9 | **`escape_analysis.zig` 完全存根 / `raii_detector.zig` 始终返回 false** | 🟠 HIGH | 两个重要分析通道是空壳 |
| 10 | **`ffi_boundary.zig` 文件头声称<200行实际1126行** | 🔵 LOW(注释) | 严重误导性文档，反映重构文档管理问题 |

---

## 7. 建议修复优先级

### P0 — 立即修复（安全与正确性）
1. `ffi_precision.zig` — 子串匹配改为整词匹配
2. `rust_ffi_rules_basic.zig` — 修复 Rule 3 的实现
3. `zig_allocator_tracker.zig` — 修复悬挂指针
4. `ffi_unsafe.zig` — 恢复 fallback 危险函数列表
5. `build.zig` — 修正 LLVM 版本到实际可用版本

### P1 — 尽快修复（测试与脚本正确性）
6. `stability_test.sh` — 修复续行语法和 output 参数传递
7. `regression_test.sh` — 修复 Go IR 编译命令
8. `corpus_verify.sh` — 修复 macOS 下的 timeout 问题
9. `tests/main.zig` vs `regression.zig` — 统一 RiskKind 计数
10. `ffi_analysis.zig` — 移除死代码 `orelse continue`

### P2 — 后续修复（代码质量与维护性）
11. 移除所有 `src/` 中的死代码重导出和未使用的导入
12. 更新所有不准确的注释（`ffi_boundary.zig` 文件头、`semantic_registry.zig` 层数等）
13. 将测试中的 GPA 替换为 `std.testing.allocator`
14. 修复 `escape_analysis.zig` 和 `raii_detector.zig` 的存根实现
15. 统一 CI/CD 工作流配置

---

*审查日期: 2026-06-09 | 审查范围: 全部核心源码、测试、脚本、CI/CD、构建系统 | 总问题数: 81*
