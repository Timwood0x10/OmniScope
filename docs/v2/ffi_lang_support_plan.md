# FFI 语言支持扩展计划：Go / Python / Java

> **日期**: 2026-06-01  
> **范围**: 仅 FFI 边界检测，不涉及 GC/runtime 建模  
> **基准**: 当前代码库实际状态（非文档声称状态）

---

## 当前实际状态

| 组件 | 代码 | 真实状态 |
|------|------|---------|
| `go_adapter.zig` | 653 行 | `analyzeFunction` 仅分类 call，无 issue 输出 |
| `python_adapter.zig` | 716 行 | IR 遍历存在，有 GIL/refcount 追踪，无 issue 输出 |
| `jni_reg.zig` | ~80 行 | 27 个 JNI 函数语义定义，未接入任何 pass |
| `ffi_contract_db.zig` | JNI 节 | `NewGlobalRef/DeleteGlobalRef` 等规则已有 |
| `cross_lang_dataflow.zig` | 主 pass | 已接入 FFIContractDB，但不感知 Go/Python/JNI |

**关键缺口**：三个语言适配器都只做了分类（`classifyCall`），没有把结果转成
`Issue` 输出到诊断流。`jni_reg.zig` 完全孤立。

---

## 目标与范围

**做什么**：
- 在 FFI 边界（`cgo` call、`C.*` 调用、`Py_*` API、JNI `NewGlobalRef` 等）检测
  内存安全问题（leak、double-free、UAF、missing null check）
- 利用已有的 `FFIContractDB` + `cross_lang_dataflow` 基础设施

**不做什么**：
- Go goroutine 生命周期、GC 交互
- Python 纯 Python 代码分析
- Java 字节码分析（只看 JNI native side 的 C/C++ 代码）

---

## Phase 1：Go cgo FFI（1-2 天）

### 实际缺口

`go_adapter.analyzeFunction` 正确地遍历了 IR、识别了 `C.malloc`/`C.free`/
`_Cgo_*`，但最后只把 `FFICallInfo` 加入 `result.calls`，没有生成任何 `Issue`。

### 修复步骤

**Step 1**：在 `analyzeFunction` 内，对已分类的 call 做配对检测：

```
C.malloc / C.calloc / C.strdup → 必须有配对 C.free
C.CString                      → 必须有配对 C.free
CGO_CONVERSION_FUNCTIONS       → 标记需要追踪
```

追踪方式：单函数内的简单线性扫描足够（不需要跨函数）。
函数结束时若 `alloc_count > free_count`，生成 `leak` issue。

**Step 2**：将生成的 `AdapterIssue` 转为 `Issue`，在 pipeline 现有的
`adapter_registry.analyzeFunction` 调用点之后写入 `ctx.issues`。

**涉及文件**：
- `src/lang/go_adapter.zig` — 加配对逻辑
- `src/pipeline/pipeline.zig:~291` — 加 issue 转换

**成功标准**：cgo 代码中 `C.malloc` 无配对 `C.free` 被报告为 `leak`。

---

## Phase 2：Python C API FFI（1-2 天）

### 实际缺口

`python_adapter.analyzeFunction` 已有 `refcount_increments / refcount_decrements`
计数，GIL 状态追踪骨架也在。缺的是：
1. 不平衡的 refcount 没有转为 issue
2. GIL 违规（`Py_*` API 在 `PyGILState_Release` 之后调用）没有报告
3. borrowed ref 被 DECREF 没有检测

### 修复步骤

**Step 1**：函数扫描结束时：
```
if refcount_increments > refcount_decrements → leak (owned ref 未 DECREF)
if refcount_increments < refcount_decrements → potential double-decref / UAF
```

**Step 2**：GIL 违规检测（已有 `GILState` 追踪，补充报告逻辑即可）：
```
gil_state == .released 且遇到 Py_* API call → GIL_violation issue
```

**Step 3**：`BORROWED_REF_FUNCTIONS`（`PyList_GetItem` 等）返回值被 DECREF 的
检测——这需要简单的 def-use 追踪（`LLVMGetOperand` 即可，不需要完整 dataflow）。

**涉及文件**：
- `src/lang/python_adapter.zig` — 补充 issue 生成
- `src/pipeline/pipeline.zig:~291` — 同 Phase 1 的转换点复用

**成功标准**：`Py_BuildValue` 返回值未 `Py_DECREF` 被报告为 leak。

---

## Phase 3：Java JNI FFI（2-3 天）

### 实际缺口

`jni_reg.zig` 有 27 个函数的完整语义定义（`transfers_ownership`、
`consumes_ownership`、`requires_null_check`），但完全没有接入 `cross_lang_dataflow`
或任何 pass。`ffi_contract_db.zig` 里也有 JNI 规则节，同样孤立。

### 方案：复用 cross_lang_dataflow，不新建 pass

`cross_lang_dataflow` 已经有 `checkFreeCall` + `validateWithContractDBFromSource`
逻辑。JNI 的问题本质和 C 的 malloc/free 配对一样，只是函数名不同。

**Step 1**：在 `cross_lang_dataflow` 的函数识别逻辑里，增加 JNI 函数名匹配：

```
NewGlobalRef       → alloc side (must pair with DeleteGlobalRef)
DeleteGlobalRef    → free side
GetStringUTFChars  → alloc side (must pair with ReleaseStringUTFChars)
ReleaseStringUTFChars → free side
GetByteArrayElements  → alloc side
ReleaseByteArrayElements → free side
AttachCurrentThread → alloc side (must pair with DetachCurrentThread)
DetachCurrentThread → free side
```

**Step 2**：把 `jni_reg.zig` 的 `jni_functions` 数组接入 `FFIContractDB`（
`loadFromConfig` 已有机制，或直接在 `initBuiltinRules` 里调用）。

**Step 3**：`requires_null_check = true` 的函数调用，若返回值无 null check，
报告 `missing_null_check` issue（`FindClass`、`GetMethodID` 等）。

**涉及文件**：
- `src/resource/ffi_contract_db.zig` — 在 initBuiltinRules 引用 jni_reg
- `src/pass/analysis/ffi/cross_lang_dataflow.zig` — 加 JNI 函数名识别
- `src/registry/jni_reg.zig` — 不改，只是被引用

**成功标准**：`NewGlobalRef` 无 `DeleteGlobalRef` 被报告为 leak；
`FindClass` 返回值无 null check 被报告为 missing_null_check。

---

## 执行顺序与依赖

```
Phase 1 (Go)   ──→  pipeline issue 转换点建立（被 Phase 2 复用）
Phase 2 (Python)   ──→  依赖 Phase 1 的转换点
Phase 3 (JNI)  ──→  独立，直接接入 cross_lang_dataflow（无需等 Phase 1/2）

可并行：Phase 1 + Phase 3 同时做
Phase 2 串行在 Phase 1 之后
```

---

## 不在本计划内

| 项目 | 原因 |
|------|------|
| TinyGo | 无真实测试语料，优先级低 |
| Python ctypes（纯 Python） | 无 IR，OmniScope 架构不支持 |
| Java 字节码分析 | 超出 LLVM IR 分析范畴 |
| goroutine 生命周期 | GC 建模复杂度高，ROI 低 |
| C# P/Invoke | 无语料，无优先级 |

---

## 成功指标

| 指标 | 目标 |
|------|------|
| Go cgo leak 检出率 | > 60%（单函数内 malloc/free 不配对） |
| Python owned ref leak 检出率 | > 70% |
| JNI GlobalRef leak 检出率 | > 80%（规则库已完备） |
| 新增 FP 率 | < 10%（相对现有 baseline） |
| 编译零错误 | 必须 |
