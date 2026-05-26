# OmniScope 重构设计与待办

编码风格与约束：严格遵循 `./plan/rules/*.*`，包括 `./plan/rules/rules.md` 与 `./plan/rules/skills.md`。

---

## 目标

把当前偏语言特化、偏名字匹配的噪声过滤逻辑，整理成一套**跨语言、可维护、可组合**的通用分析架构。

重点： CrossLangEdge + OwnershipGraph + Boundary Reachability

产品定位：

- OmniScope 是 LLVM IR 层跨语言 FFI 安全审计工具。
- OmniScope 不做通用静态检测器，不承诺证明所有漏洞。
- OmniScope 输出高置信风险和可追踪证据链。
- 重点问题是跨语言边界上的 ownership、lifetime、ABI、pointer flow 和 callback 风险。

核心输出证据：

- 哪个函数是 boundary。
- 哪个 pointer 跨过边界。
- 谁分配、谁释放。
- 为什么 ownership 不匹配。
- 哪条调用链让风险 reachable。

核心原则：

- 不依赖 crate 名白名单。
- 不依赖 per-function body 扫描来判断"是否值得分析"。
- 保留 FFI producer、boundary、unknown 场景。
- 让所有 heavy pass 共享同一份 surface 分类结果。
- 单文件保持在 1000 行以内，模块职责清晰。

---

## 待修复问题

以下任务来自 2026-05-26 对 ffi-demo + 4 个真实开源项目（crc32fast / python-xxhash / zstd-rs / go-sqlite3 C 桥）的实测。每个任务都有具体重现来源与影响范围。

---

### P0：OmniScope 在 Rust SIMD intrinsics 上崩溃 ⚠️

**重现**：克隆 `srijs/rust-crc32fast`，`RUSTFLAGS="--emit=llvm-bc -C opt-level=0" cargo build --release --lib`，对生成的 `crc32fast-*.bc` 跑 OmniScope。

**症状**：
```
Segmentation fault at address 0x100000000000005e
0x100734f03 in _pass.analysis.pointer_ownership.PointerOwnershipPass.run
```

**任务**：

- [ ] P0-1：在 `src/pass/analysis/pointer_ownership/` 内,加 LLVM intrinsic 检测，跳过 `llvm.x86.*` / `llvm.aarch64.*` / `core::arch::*` 调用的指针 op 分析。
- [ ] P0-2：用 `crc32fast.bc` 作为回归测试 fixture，加进 `corpus/`。
- [ ] P0-3：单文件最小重现脚本：写一个 Zig fixture 调用 `@cImport` 引入 `<immintrin.h>` 并用 `_mm_clmulepi64_si128`，确认 crash gone。

---

### P1：Python C API 所有权未建模（影响所有 Python C 扩展）

**重现**：克隆 `ifduyue/python-xxhash`，`clang -emit-llvm -c -O0 src/_xxhash.c`，对 `_xxhash.bc` 跑 OmniScope → 6 issues 全 FP。

**根因**：OmniScope 不识别 Python C API 的所有权语义。

**任务**：

- [ ] P1-1：在 `src/semantics/allocator_kb.zig`（或对应知识库）中注册以下 Python alloc 函数及其配对 free：
  - `PyObject_New` / `PyObject_NewVar` / `PyType_GenericAlloc` → `PyObject_Del` / `PyObject_Free`
  - `PyMem_Malloc` / `PyMem_Calloc` / `PyMem_Realloc` → `PyMem_Free`
  - `PyMem_RawMalloc` 等 raw 系列 → `PyMem_RawFree`
- [ ] P1-2：在 `src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig` 中,当 `alloc_lang == python` 且 `free_lang == python` 时**不报** `cross_language_free`。
- [ ] P1-3：注册 Python "返回 owned reference" 函数族（`PyLong_From*`、`PyUnicode_From*`、`PyTuple_New`、`PyList_New`、`PyDict_New`、`PyBytes_FromString*` 等），其调用结果的 `Py_DECREF` / `Py_XDECREF` 视为标准 release，**不报** refcount imbalance / use_after_free。
- [ ] P1-4：单元测试用 `python-xxhash` 的 `_xxhash.bc` 验证：6 FP → 0 FP。

---

### P2：Rust Drop trait + C free 配对未识别（影响 bindgen 风格 wrapper）

**重现**：克隆 `gyscos/zstd-rs`，build → `zstd_safe.bc` 报 4 个 `use_after_free` on Drop（CCtx/DCtx/CDict/DDict）。源码 `zstd-safe/src/lib.rs:859-866` 是标准 RAII，无 Clone/Copy。

**根因**：`impl Drop` 内调 `extern "C"` 的 free 被识别为"FFI-transferred pointer 被 free"。

**任务**：

- [ ] P2-1：在 `src/pass/analysis/ptr_lifetime/ptr_lifetime_violations.zig` 增加规则：当 caller 是 Rust 函数且函数名形如 `_ZN<...>4drop17h<hash>E`（Drop trait impl 的 demangled 形式）时，调用的 C free 是标准 RAII 移交，不报 use_after_free。
- [ ] P2-2：可选增强：检查 owner type 是否有 `impl Clone` / `impl Copy`。无 Clone+Copy 表示严格单一所有权，Drop 是唯一 release 路径，置信度更高。
- [ ] P2-3：单元测试 fixture：用 zstd-rs 的 `_ZN57_$LT$zstd_safe..CCtx$u20$as$u20$core..ops..drop..Drop$GT$4drop*` 作为正样本（不应报警）。

---

### P3：FFI helper 函数返回 raw ptr 被误判 borrow_escape

**重现**：zstd_safe.bc 中 `ptr_mut_void(&mut [u8]) -> *mut c_void` 和 `Vec<u8>::as_mut_ptr() -> *mut u8` 被报 borrow_escape。这些是 FFI 标准入口函数,**有意**返回 raw ptr。

**任务**：

- [ ] P3-1：在 `src/pass/analysis/callback_escape.zig`（或对应模块）的 borrow_escape 检测中，识别以下"FFI surface helper"模式并跳过：
  - 函数签名 `fn(&[T]) -> *const T` 或 `fn(&mut [T]) -> *mut T`
  - 函数体只有一条 `as_ptr()` / `as_mut_ptr()` 或等价 `getelementptr` + 返回
  - 函数名包含 `as_ptr` / `as_mut_ptr` / `ptr_mut_void` / `ptr_void` / `_ptr` 等模式
- [ ] P3-2：单元测试：zstd_safe `_ZN9zstd_safe12ptr_mut_void17h*E` 不应报警。

---

### P4：非指针返回值被识别为 ptr escape

**重现**：zstd_safe `ZSTD_CCtx_setParameter` 返回 `size_t`(错误码)，但被报 `borrow_escape "FFI return value escape: ZSTD_CCtx_setParameter result"`。

**任务**：

- [ ] P4-1：在 borrow_escape / FFI return escape 检测的入口加 return-type guard：通过 LLVM `LLVMGetReturnType()` 取 callee 返回类型，若是 integer（i8/i16/i32/i64/usize/isize）或 void，**不报** borrow_escape。
- [ ] P4-2：仅 pointer 类型（`PointerTypeKind`）和包含 pointer 的 aggregate 返回值才进入 escape 分析。
- [ ] P4-3：单元测试：用 `ZSTD_CCtx_setParameter` 调用（返回 size_t）和 `malloc` 调用（返回 ptr）做对比 fixture。

---

### P5：Rust stdlib `core::*` 函数 FP

**重现**：zstd.bc OMI-002 报 `integer_overflow` in `_ZN4core3cmp5impls50_$LT$impl$u20$core..cmp..Ord$u20$for$u20$usize$GT$3cmp*`。这是 Rust stdlib `core::cmp` 内部实现，不是用户代码。

**任务**：

- [ ] P5-1：在 `src/pass/analysis/noise/issue_suppression.zig` 的 `isStdlibInternalFunction()` 中,补充 Rust 分支：
  - 函数名以 `_ZN4core` / `_ZN5alloc` / `_ZN3std` / `_R{N,I}{...}4core` 等前缀开头视为 stdlib 内部
  - 已有 v0 mangling 检测,但 demangled 后包含 `core::` / `alloc::` / `std::` 的也归入此类
- [ ] P5-2：注意例外：用户代码可能有 `core::` namespace shadow（罕见）；保留 confidence 降级而非完全压制，让 verbose mode 仍能看见。
- [ ] P5-3：回归用 zstd.bc 验证 OMI-002 消失，但用户代码中真正的 integer_overflow 仍报。

---

### P6：C++ `_Znam` / `_Znwm` 未注册为堆 alloc

**重现**：ffi-demo `cpp_fft.bc` v3 仍有 1 个 hard FP——OMI-001 `invalid_free` "non-heap source pointer"。trace 自相矛盾："Pointer origin: from `_Znam()`" 然后 "Free called on non-heap pointer"。`_Znam` 就是 C++ `operator new[]`，明显是堆。

**任务**：

- [ ] P6-1：在 `src/pass/analysis/ptr_lifetime/ptr_lifetime_classify.zig` 的 alloc 函数集合中，注册：
  - `_Znwm` / `_Znwj` / `_Znw_` → C++ `operator new`
  - `_Znam` / `_Znaj` / `_Zna_` → C++ `operator new[]`
  - `_Znw*RKSt9nothrow_t` → `operator new(nothrow)` 变体
- [ ] P6-2：对应 free 端配对：`_ZdlPv` → `delete`，`_ZdaPv` → `delete[]`。
- [ ] P6-3：单元测试用 ffi-demo `cpp_fft.bc` 验证 OMI-001 消失（同时确保 OMI-002 InitTwiddle 的 TP 仍报）。

---

### P7：C++ 单对象 new + 静态 new[] 漏检

**重现**：ffi-demo `cpp_hash.bc` 只检出 BUG-4a，漏掉：
- BUG-4b：`Hash` 中 `new PadHelper()` 单对象漏 delete
- BUG-4c：`S0` 中 `static uint32_t* tbl = new uint32_t[1024]` 静态生命周期 leak

**任务**：

- [ ] P7-1（依赖 P6）：扩展 alloc tracking 到单对象 `new T`（`_Znwm` 返回值不仅是 `void*`,而是 specific type pointer 后会做 `bitcast`,要 follow 这条 chain）。
- [ ] P7-2：识别"静态变量首次初始化"模式 — alloc 结果存到 global / static 变量后,若该 global 没有 free 路径,**应报为 leak**（即使生命周期是进程级）。区分用户意图（"一次性分配,永不释放"）和真 leak（每次调用都 alloc）需要 trip-counting。
- [ ] P7-3：回归用 cpp_hash.bc 验证 BUG-4b / BUG-4c 命中。

---

### P8：路径敏感 leak 漏检

**重现**：
- ffi-demo `c_fft_c_bridge.bc` 漏检 FFT-LEAK-3：`real_copy` / `imag_copy` 仅在 success path free，error path leak。
- ffi-demo `cpp_fft.bc` 漏检 FFT-LEAK-2：`BitReverseTable` 返回 `new[]`,FFT 中只在 success path `delete[] rev`，error path leak。

**任务**：

- [ ] P8-1：在 leak detector 中加 path-sensitive 分析：枚举 alloc 后所有 reachable 的 free instructions，若存在一条 path 从 alloc 到 function return（或 throw）**不经过 free**，报 `conditional_leak`。
- [ ] P8-2：confidence 分级：
  - 所有 path 都 leak → HIGH leak
  - 部分 path leak → MEDIUM conditional_leak
  - 跨过程返回（无 caller 上下文）→ LOW boundary_leak
- [ ] P8-3：回归 FFT-LEAK-3 / FFT-LEAK-2 应至少报 MEDIUM。

---

### P9：已知遗留限制（不属任务，仅记录）

- ⚠️ C++ 跨函数 ownership / lifetime 追踪不完整：当 alloc 在 callee 而 free 在 caller 时,可能漏检或多报。需要完整 interprocedural alias analysis。
- ⚠️ Zig 0.16+ 项目无法用当前测试环境编译：`@Tuple` / `@Int` / `process.Init` 等新 builtin 在 0.15 不支持。如需测试更多真实 Zig 项目,升级 toolchain 或 stage 多版本 zig。
- ⚠️ Go cgo 项目无法走标准 `go build` 获取 LLVM IR；TinyGo 对 cgo 兼容性有限（build constraints 不支持）。当前只能扫 cgo 项目中的纯 C 桥文件。

---

## 平台特定 IR 信息过滤（设计仍在演进）

平台信息只作为 `PlatformProfile` / `PlatformHint`,不能单独决定漏洞是否存在。安全优先：无法确认的平台特征归为 `unknown`，继续保留分析。boundary 优先：FFI export/import、cross-language edge、extern callback 永远不能因平台 runtime 规则被过滤。

已有数据结构（`PlatformKind`、`ObjectFormat`、`PlatformProfile`、`WindowsAbi`）在 `src/semantics/platform_profile.zig`。

待补充任务：

- [ ] PF-1：当前 `PlatformProfile` 在 macOS target 上验证通过，但未在 Windows MSVC / Linux ELF 真实 bitcode 上做交叉验证。需要 stage 一份 `x86_64-pc-windows-msvc` triple + `?<sym>@@YA...` mangling 的 bitcode 来验证 MSVC `?` 前缀 -> cpp 识别走通。
- [ ] PF-2：`identifyCalleeLanguageWithContext` 的 Zig/Go 消歧已实现，但 Mach-O leading underscore (`_main`) 与 ELF/COFF 裸名 (`main`) 的归一化尚未统一进 `platform_normalizer.zig`。
- [ ] PF-3：跨平台 fixture：同一 C FFI 源码分别用 macOS / Linux / Windows toolchain 编译，验证 issue 数 / canonical symbol 一致。

---

## 文件大小控制

### 原则

- 单文件不超过 1000 行。
- 过长的枚举、长表、测试数据都要拆分。
- 大型分类规则应拆成多个小模块,不要堆在一个文件里。

### 当前超标文件

- [ ] FS-1：清点当前 src/ 下超过 1000 行的文件,逐个拆分。截至 2026-05-26 有 7 个文件超标（历史遗留）。

---

## 代码可维护性要求

### 必须满足

- 结构简单直接。
- 命名遵循项目规则。
- 所有注释使用英文。
- 公共 API 有 doc comments。
- 错误处理符合 Zig 风格。
- 内存所有权清晰。
- 改动尽量局部、外科手术式。

### 不建议的做法

- 不要继续扩展语言白名单。
- 不要在 surface 判断中做全函数 body 扫描。
- 不要把 debug provenance 和 issue suppression 混成一个模块。
- 不要维护两套互相冲突的 `FunctionOrigin` 体系。

---

## 测试要求

### 必测边界

- `unknown` surface 必须保留。
- `boundary` surface 必须保留。
- workspace path、stdlib path、dependency path 都要覆盖。
- missing debug info 要有降级策略。
- `CrossLangEdge` 参与时不能误杀。

### 回归样例

- 小型 Rust FFI 样例。
- `Box::into_raw` / `Box::from_raw` 场景。
- `extern "C" fn` producer 场景。
- 依赖 crate 的 boundary 场景。
- 编译器生成函数的噪声过滤场景。
- **新增**：上述 P0-P8 每个任务的修复都必须有对应单元 / 回归测试 fixture。

---

## 性能验收

基线参考：

| 文件 | init (ms) | detect (ms) | analysis (ms) | total (ms) |
|------|-----------|-------------|---------------|------------|
| wasmtime_test.bc | 17067 | 7441 | 11831 | 53407 |
| sqlite3.bc | 5942 | 3503 | 4647 | 20033 |

目标：

- `PointerOwnership init` 明显下降。
- `PointerOwnership analysis` 明显下降。
- recall 不下降,尤其不能漏掉 FFI producer 和 boundary 场景。

---

## 验收清单

- [ ] File is under 1000 lines
- [ ] Code is simple and straightforward
- [ ] All comments are in English
- [ ] Code-to-comment ratio is approximately 7:3
- [ ] Tests include boundary cases
- [ ] No files were deleted without permission
- [ ] Naming conventions are followed
- [ ] Code is formatted with `zig fmt`
- [ ] All tests pass
- [ ] Public APIs have doc comments
- [ ] Error handling is appropriate
- [ ] Memory management is correct
- [ ] Changes are surgical and minimal
