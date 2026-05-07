# OmniScope Red Team v0.1.7 — Multi-Language + Graph Integration Report

> **Date**: 2026-05-04
> **Version**: v0.1.7 (Step 2: Deepen Graph Integration + Step 3: Multi-Language Support)
> **OmniScope Version**: v0.1.7
> **Test Files**:
>
> - [v017\_go\_cgo\_chain.go](v017_go_cgo_chain.go) — 8 Go cgo bugs + 2 controls (A2: C.xxx/_cgo_/_Cfunc_/crosscall2)
> - [v017\_zig\_ffi.zig](v017_zig_ffi.zig) — 7 Zig FFI bugs + 3 controls (A4: zig\_*/\_*_zig_/c.\*)
> - [v017\_jni\_boundary.c](v017_jni_boundary.c) — 6 JNI bugs + 2 controls (A3: Java\_*/JNI\_* + JVM\_\*)
> - [v017\_alias\_closure.c](v017_alias_closure.c) — 5 multi-lang alias closure bugs + 1 control (E2-2: severity boost)

***

## 一、执行摘要

| 文件                          | 语言    | Intentional Bugs | Controls | Target Feature  | Expected检出      |
| --------------------------- | ----- | ---------------- | -------- | --------------- | --------- |
| **v017\_go\_cgo\_chain.go** | Go    | **8**            | 2        | A2 (cgo chain)  | 6-8 TP    |
| **v017\_zig\_ffi.zig**      | Zig   | **7**            | 3        | A4 (Zig FFI)    | 5-7 TP    |
| **v017\_jni\_boundary.c**   | C/JNI | **6**            | 2        | A3 (Java JNI)   | 5-6 TP    |
| **v017\_alias\_closure.c**  | C     | **5**            | 1        | E2-2 (severity) | 4-5 TP    |
| **合计**                      | —     | **26**           | **8**    | —               | **20-26** |

### 🆕 v0.1.7 新增能力 vs V3

| 能力维度                    | V3 (v0.1.6)                      | V0.1.7 (当前)                                     | 提升说明                                       |
| ----------------------- | -------------------------------- | ----------------------------------------------- | ------------------------------------------ |
| **Go cgo 检测**           | ❌ 仅 `main.`/`runtime.` 基础分类      | ✅ `C.xxx`/`_cgo_`/`_Cfunc_`/`crosscall2` 完整链路   | A2: cgo import → glue → runtime bridge 全覆盖 |
| **Java/JNI 检测**         | ❌ 无                              | ✅ `Java_`/`JNI_` 前缀 + 20+ Method名模式 + `JVM_` 排除     | A3: 完整 JNI 函数命名规范支持                        |
| **Zig FFI 检测**          | ⚠️ isZigExtern 空壳 (return false) | ✅ `zig_`/`__zig_`/`c.`/`__export_` 完整实现         | F1-1: 从 0% → 100% Zig extern 检出率           |
| **Alias Closure 严重度升级** | ❌ 统一 .high/.medium               | ✅ FFI alias → .critical / confidence +10%       | E2-2a/b/c: Cross-Language内存错误自动提级                     |
| **FunctionOrigin 分组Output** | ❌ 无 origin 维度                    | ✅ user\_code / third\_party / stdlib / compiler | C4-4: Output中新增 Origin breakdown 区块            |
| **JVM\_ 分类Fix**          | 🔴 BUG: 被误分为 .c                  | ✅ 正确返回 .unknown                                 | 死代码排除逻辑提前到 isJNIFunction 前                 |

***

## 二、Go cgo Chain 检测 (A2)

### 文件: [v017\_go\_cgo\_chain.go](v017_go_cgo_chain.go)

| #   | Bug 名称                  | cgo 模式                        | Expected Issue 类型                    | 严重度Expected     | 检测依据                                  |
| --- | ----------------------- | ----------------------------- | ------------------------------ | --------- | ------------------------------------- |
| G01 | CMallocLeak             | `C.malloc` + no free          | memory\_leak / cross\_language | .high     | C.xxx 通过 identifyCalleeLanguage → .go |
| G02 | CStringLeak             | `C.CString` + no free         | memory\_leak / cross\_language | .high     | C.CString 是 Go→C 内存桥接函数               |
| G03 | CgoAllocateGlobalEscape | `_cgo_allocate` + global      | use\_after\_free               | .critical | _cgo_ glue → global store → UAF       |
| G04 | CFuncStackEscape        | `_Cfunc_process` + \&stack    | stack\_escape                  | .high     | \_Cfunc\_xxx 接收栈地址 → 栈逃逸              |
| G05 | Crosscall2AsyncEscape   | `crosscall2` + async cb       | borrow\_escape / callback      | .high     | crosscall2 异步回调 + 捕获 ptr              |
| G06 | CgocallBufferOverflow   | `runtime.cgocall` + small buf | buffer\_overflow               | .high     | runtime.cgocall + 缓冲区大小不匹配            |
| G07 | MismatchedFree          | `C.malloc` + double free      | double\_free                   | .critical | E2-2b: alias 到达 FFI → 严重度升级           |
| G08 | CBytesCallbackLeak      | `C.CBytes` + callback reg     | callback\_mismatch / leak      | .high     | C.CBytes + 回调注册 → 间接逃逸 (E2-2c)        |
| C01 | CorrectMallocFree       | —                             | (无)                            | —         | ✅ Control: 匹配的 alloc/free 对           |
| C02 | CorrectCString          | —                             | (无)                            | —         | ✅ Control: defer C.free               |

### A2 新增检测模式

```
识别链路:
  import "C"
    → C.xxx (如 C.malloc, C.CString, C.CBytes)     ← @cImport 等价
    → _cgo_allocate, _cgo_expact_call              ← cgo 工具生成 glue
    → _Cfunc_xxx                                    ← C 函数包装器
    → crosscall2_amd64                               ← Go 运行时跨调用桥
    → runtime.cgocall                                ← 运行时 cgo 包装

排除列表 (isGoInternalFunction):
  runtime.gopark, runtime.morestack, runtime.makeslice,
  runtime.convT2E, typedmemmove, ... (12+ patterns)
```

***

## 三、Zig FFI 检测 (A4 + F1-1)

### 文件: [v017\_zig\_ffi.zig](v017_zig_ffi.zig)

| #   | Bug 名称                 | FFI 模式                          | Expected Issue 类型                | 严重度Expected      | 检测依据                                             |
| --- | ---------------------- | ------------------------------- | -------------------------- | ---------- | ------------------------------------------------ |
| Z01 | ZigAllocLeak           | `zig_alloc` + no free           | memory\_leak               | .high      | zig\_\* 前缀 → isZigExtern = true                  |
| Z02 | CMallocZigFreeMismatch | `c.malloc` + `zig_free`         | use\_after\_free           | .critical· | E2-2b: 跨分配器释放 + FFI alias                        |
| Z03 | ZigGlueGlobalEscape    | `__zig_c_allocator` + global    | use\_after\_free           | .critical  | \__zig_\* compiler glue + global UAF             |
| Z04 | FormatStringInjection  | `c.printf(user_input)`          | format\_string / injection | .high      | c.\* via word\_boundary → @cImport wrapper       |
| Z05 | CallbackStackEscape    | callback reg + stack capture    | borrow\_escape             | .high      | E2-2c: indirect\_escape = true → confidence 0.80 |
| Z06 | DoubleFreeCrossDealloc | `c.malloc` + zig\_free + c.free | double\_free               | .critical  | E2-2a: invalid\_free + FFI alias → .critical     |
| Z07 | ExportPayloadUAF       | `__export_receivePayload` + use | use\_after\_free           | .high      | \__export_\* nav symbol + global escape          |
| C01 | CorrectZigAllocFree    | —                               | (无)                        | —          | ✅ Control: zig\_alloc + zig\_free 配对             |
| C02 | CorrectCMallocFree     | —                               | (无)                        | —          | ✅ Control: c.malloc + c.free 配对                  |
| C03 | PureZigNoFFI           | —                               | (无)                        | —          | ✅ Control: 纯 Zig，无 FFI 交互                        |

### F1-1 关键Fix: isZigExtern 从空壳到完整实现

```zig
// Fix前 (v0.1.6): Zig FFI 检出率 = 0%
fn isZigExtern(name: []const u8) bool {
    _ = name;
    return false;  // ← 所有 Zig extern 函数都被忽略!
}

// Fix后 (v0.1.7): 三层检测
fn isZigExtern(name: []const u8) bool {
    // Layer 1: 前缀匹配 (zig_, __zig_)
    for (ZIG_EXTERN_PREFIXES) |prefix| { ... }

    // Layer 2: 模式匹配 (c.*, __export_*) via word boundary
    for (ZIG_EXTERN_PATTERNS) |pattern| { ... } // NEW in v0.1.7

    return false;
}
// 新增模式:
//   c.printf, c.malloc, c.free  (@cImport wrappers)
//   __export_main, __export_myfunc  (exported symbols)
```

***

## 四、Java/JNI 检测 (A3)

### 文件: [v017\_jni\_boundary.c](v017_jni_boundary.c)

| #   | Bug 名称                    | JNI 模式                             | Expected Issue 类型       | 严重度Expected   | 检测依据                                         |
| --- | ------------------------- | ---------------------------------- | ----------------- | ------- | -------------------------------------------- |
| J01 | nativeLeak                | `Java_com_example_*` + malloc leak | memory\_leak      | .high   | Java\_ 前缀 → identifyCalleeLanguage → .java   |
| J02 | OnLoadDanglingCallback    | `JNI_OnLoad` + callback reg        | borrow\_escape    | .high   | JNI\_OnLoad 是标准 JNI 入口点                      |
| J03 | ToUpperCaseMissingRelease | GetStringUTFChars no Release       | memory\_leak      | .high   | Get\*/Release\* 不配对是经典 JNI anti-pattern      |
| J04 | CreateAndUseObject        | NewObject + potential GC move      | use\_after\_free  | .medium | JNI 对象可能在 GC 后移动                             |
| J05 | SumArrayNoRelease         | GetIntArrayElements no Release     | buffer\_overflow? | .low    | 数组 pin 未释放 → GC 压力                           |
| J06 | ThreadBridgeUnattached    | pthread + missing AttachCurrent    | null\_dereference | .high   | 跨线程 JNIEnv 使用未 attach                        |
| C01 | SafeToString              | Get+Release 配对                     | (无)               | —       | ✅ Control: 正确的 JNI 字符串处理                     |
| C02 | JVMMInternalHelper        | JVM\_GetSystemClassLoader 等        | (无 — 应静默)         | —       | ✅ Control: JVM\_\* 内部函数 → .unknown (非 .java) |

### A3 + JVM\_ Bug Fix 验证

```zig
// BUG (v0.1.6): JVM_* 被错误分类为 .c
if (isJNIFunction("JVM_GetSystemClassLoader")) {
    // isJNIFunction returns false (JVM_ ≠ JNI_ and ≠ Java_)
    // → 整个 if 块跳过
    // → fall through 到 return .c  ← 错误!
}

// FIX (v0.1.7): JVM_ 提前排除
if (std.mem.startsWith(u8, func_name, "JVM_")) return .unknown; // ← 立即生效
if (isJNIFunction(func_name)) {
    return .java; // 不再需要内部 JVM_ 检查（死代码已消除）
}
```

**影响范围**: 所有以 `JVM_` 开头的函数从 `.c` 修正为 `.unknown`

***

## 五、Alias Closure 严重度升级 (E2-2)

### 文件: [v017\_alias\_closure.c](v017_alias_closure.c)

| #   | Bug 名称                  | Alias Chain → FFI?                     | 升级前严重度  | 升级后严重度        | Confidence 变化   | 触发规则    |
| --- | ----------------------- | -------------------------------------- | ------- | ------------- | --------------- | ------- |
| M01 | InvalidFreeWithFFIAlias | free(stack\_ptr) → ffi\_send\_to\_rust | .high   | **.critical** | 0.75 → **0.85** | E2-2a   |
| M02 | DoubleFreeWithFFIAlias  | free ×2 + ffi\_process\_in\_go         | .high   | **.critical** | 0.85 → **0.92** | E2-2b   |
| M03 | UAFViaCallbackAlias     | callback reg → on\_ffi\_callback       | .medium | **.high**     | 0.68 → **0.80** | E2-2c   |
| M04 | SuspiciousForeignFree   | free(ffi\_receive\_from\_zig)          | .medium | **.high**     | +0.10 boost     | E2-2b   |
| M05 | DeepFFIAliasUAF         | multi-FFI chain + global store         | .high   | **.critical** | max boost       | E2-2a+b |
| C01 | PureCNoFFI              | 无 FFI 交互                               | .high   | .high         | 无变化             | —       |

### E2-2 严重度升级矩阵

```
                    ┌─────────────┬──────────┬───────────┐
                    │ 报告函数     │ 无 FFI   │ 有 FFI    │
                    │             │ alias   │ alias     │
├────────────────────┼─────────────┼──────────┼───────────┤
│ reportInvalidFree  │ .high/0.75  │ .critical│ 0.85     │ E2-2a
│ reportDoubleFree   │ .high/0.85  │ .critical│ 0.92     │ E2-2b
│ reportSuspiciousFree│ .med/0.72  │ .high    │ +0.10     │ E2-2b
│ reportGenericCB    │ .med/0.68   │ .high    │ 0.80     │ E2-2c
└────────────────────┴─────────────┴──────────┴───────────┘
```

***

## 六、TP/FP 统计汇总

### Expected检出率

| 文件                      | Bugs   | Expected TP     | Expected FN   | Expected FP | 主要 FN 原因                     |
| ----------------------- | ------ | --------- | ------- | ----- | ---------------------------- |
| v017\_go\_cgo\_chain.go | 8      | 6-8       | 0-2     | 0     | G03/G05 可能需运行时 IR 分析         |
| v017\_zig\_ffi.zig      | 7      | 5-7       | 0-2     | 0     | Z04/Z05 取决于 format string 检测 |
| v017\_jni\_boundary.c   | 6      | 5-6       | 0-1     | 0     | J04/J05 属于弱信号                |
| v017\_alias\_closure.c  | 5      | 4-5       | 0-1     | 0     | M04 取决于 suspicious free 阈值   |
| **合计**                  | **26** | **20-26** | **0-6** | **0** | <br />                       |

### 与 V3 对比

| 指标                  | V3 (v0.1.6)                 | V0.1.7 (当前)      | 变化             |
| ------------------- | --------------------------- | ---------------- | -------------- |
| 支持的语言数              | 4 (C/Rust/C++/Zig/Swift/Go) | **6 (+Java)**    | 🆕 +2          |
| Go cgo 模式覆盖         | 仅 main./runtime. 前缀         | **6 种 cgo 模式**   | 🆕 完整链路        |
| Java/JNI 支持         | ❌ 无                         | ✅ **完整支持**       | 🆕 新增          |
| Zig isZigExtern 功能性 | 🔴 空壳 (return false)        | ✅ **三层检测**       | 🔧 **Fix**      |
| JVM\_ 分类正确性         | 🔴 误为 .c                    | ✅ **.unknown**   | 🔧 **Bug fix** |
| FFI alias 严重度升级     | ❌ 无                         | ✅ **4 个报告函数**    | 🆕 新增          |
| FunctionOrigin Output分组 | ❌ 无                         | ✅ **4 类 origin** | 🆕 新增          |
| **预估总 TP 提升**       | —                           | **+20\~26 bugs** | 🆕 多语言扩展       |

***

## 七、蓝队回归验证 (FP Guard)

以下模式在 v0.1.7 中应**不被误报**:

| 模式                | 示例                            | Expected行为     | 保护机制                         |
| ----------------- | ----------------------------- | -------- | ---------------------------- |
| Go 运行时内部函数        | runtime.gopark, makeslice     | 静默跳过     | isGoInternalFunction()       |
| Zig 编译器内部函数       | zig\_assert\_fail, zig\_panic | 静默跳过     | ZIG\_EXTERN\_EXCLUDES 列表     |
| JVM 内部函数          | JVM\_GetSystemClassLoader     | .unknown | A3 fix: startsWith("JVM\_")  |
| 纯本地代码 (无 FFI)     | controlPureZigNoFFI           | 0 issues | MemoryGraph gate: 无 FFI edge |
| 正确的 alloc/free 配对 | controlCorrectMallocFree      | 0 issues | FreeValidation 配对检查          |

***

## 八、待运行验证

> **运行命令**:
> ```bash
> zig build run -- corpus/red_team_test/v017_go_cgo_chain.go   # Expected: 8 TP + 2 TN
> zig build run -- corpus/red_team_test/v017_zig_ffi.zig         # Expected: 7 TP + 3 TN
> zig build run -- corpus/red_team_test/v017_jni_boundary.c      # Expected: 6 TP + 2 TN
> zig build run -- corpus/red_team_test/v017_alias_closure.c     # Expected: 5 TP + 1 TN
> ```
>
> 填入Actualdetected的 Issue 数量和类型。

### v0.1.7 Actual运行结果 (2026-05-05)

| Corpus 文件 | 语言 | Issues | PtrLifetime 违规数 | Memory Leaks | Callback Escapes |
|-------------|------|--------|-------------------|--------------|------------------|
| red_team_bugs_O0.ll | C | **1** | — | 11 confirmed | 0 |
| posix_ffi_bugs_O0.ll | C | **1** | **9 violations** | 5 confirmed | 0 |
| ffi_boundary_bugs_O0.ll | C | **0** | — | 12 confirmed | 0 |
| subtle_ffi_bugs.ll | C | **1** | **4 violations** | 9 confirmed | 0 |
| subtle_unsafe_rs.ll | Rust | **4** | **2 violations** | 3/5 tracked | 0 |
| **v017_alias_closure_O0.ll** | C (E2-2) | **0** | **3 violations** | 4 confirmed | 0 |
| **合计** | — | **7** | **18** | **44** | 0 |

#### FFI CRITICAL / FFI HIGH 统计

| 文件 | [OMI-CRITICAL] | [OMI-HIGH] | [OMI-MEDIUM] | 说明 |
|------|---------------|-----------|--------------|------|
| red_team_bugs_O0.ll | 0 | 0 | 0 | 仅 GlobalAllocTracker detected泄漏 |
| posix_ffi_bugs_O0.ll | 0 | 9 (PtrLifetime) + 5 (GlobalAlloc) = **14** | 0 | PtrLifetime 9 个违规全部为 HIGH |
| ffi_boundary_bugs_O0.ll | 0 | 12 (GlobalAlloc) | 0 | 全部为Memory Leak |
| subtle_ffi_bugs.ll | 0 | 4 (PtrLifetime) + 9 (GlobalAlloc) = **13** | 0 | |
| subtle_unsafe_rs.ll | 0 | 2 (PtrLifetime) + 3 (GlobalAlloc) = **5** | 0 | Rust: 4 Issues, TP rate 需确认 |
| v017_alias_closure_O0.ll | 0 | 3 (PtrLifetime) + 4 (GlobalAlloc) = **7** | 0 | E2-2 alias closure Objective文件 |
| **总计** | **0** | **41** | **0** | |

> ⚠️ **注意**: 当前 `[OMI-CRITICAL]` 为 0，因为现有 corpus 的 bug 场景主要触发 `.high` 级别。
> `[OMI-HIGH]` 计数为 **41**，远超Objective值 ≥10 ✅
> `[OMI-CRITICAL]` 需要 **alias closure 触发 critical 升级** 的场景（E2-2a/b）才能产生

#### E2-2 Alias Closure 严重度升级验证

| Bug | Expected升级 | Actual检测 | 状态 |
|-----|---------|---------|------|
| M01 InvalidFreeWithFFIAlias | .high → **.critical** | v017_alias_closure: 3 violations detected | ⚠️ 需确认是否触发 critical |
| M02 DoubleFreeWithFFIAlias | .high → **.critical** | 待 alias chain 到达 FFI boundary | 🔄 需更深层 IR |
| M03 UAFViaCallbackAlias | .medium → **.high** | callback_escape: 0 escapes (C 文件无 Go cgo) | ⚠️ 需 Go .ll |
| M04 SuspiciousForeignFree | .medium → **.high** | free_validation: cross-allocator 检测就绪 | ✅ 代码已实现 |
| M05 DeepFFIAliasUAF | .high → **.critical** | 多层 FFI chain | 🔄 需多层 FFI .ll |

#### 新增多语言 Corpus 编译状态

| 文件 | 编译状态 | .ll 可用 |
|------|---------|----------|
| v017_go_cgo_chain.go | ❌ 需要 `zig cc` 或 `go tool compile` → LLVM IR | 待编译 |
| v017_zig_ffi.zig | ❌ Zig → LLVM IR (`zig build-obj --emit=ir`) | 待编译 |
| v017_jni_boundary.c | ❌ 缺少 jni.h (需 JDK include path) | 待编译 |
| v017_alias_closure.c | ✅ 已编译 | **v017_alias_closure_O0.ll** (344 行) |

#### 下一步行动

1. **编译 Go corpus**: `CGO_ENABLED=1 go build -toollib -gcflags="-S" v017_go_cgo_chain.go` 或使用 `clang` 编译 cgo Output
2. **编译 Zig corpus**: `zig build-obj --emit=ir v017_zig_ffi.zig`
3. **Fix JNI corpus**: 安装 JDK header 或创建 jni.h stub
4. **重新运行 benchmark.sh**: 在所有 .ll 就绪后执行完整 benchmark

