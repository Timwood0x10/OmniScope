# FFI 检测能力缺口与完善方案

**对象**：OmniScope 0.2.0 已知漏报
**测试基准**：`~/code/ffi-demo/output/*.ll`（10 文件）+ 对应源码 `~/code/ffi-demo/{c,rust_hash,zig,cpp}/`
**当前 F1 分数**：1/5 真实跨语言边界（仅 zig\_main 检测正确）

***

## 一、问题分类（按根因聚类，不按文件）

### 根因 R1: 单文件"导出函数"模式不识别

**现象**：`c_ffi_traps.ll` 包含 11 个 FFI 导出函数（`ffi_make_token`/`ffi_release_token`/.../`uaf_through_ffi`/`leaked_callback_userdata`），全部预设 9 个陷阱漏报。

**IR 层证据**（已确认）：

```llvm
define noundef ptr @ffi_make_token(ptr ..., i64 ...) local_unnamed_addr #0 { ... }
define void @ffi_release_token(ptr ...) local_unnamed_addr #3 { ... }
define void @ffi_register_callback(ptr ..., ptr ...) local_unnamed_addr #9 { ... }
define noundef ptr @cross_family_alloc() local_unnamed_addr #12 { ... }
```

所有这些 `define` 都是**外部链接 + C 命名**（`local_unnamed_addr` + 无 mangling），但**没有任何跨语言 caller 出现在本 TU 内**——它们都是被外部语言（Rust/Go/Zig）通过 FFI 调用。

**OmniScope 当前行为**：`cross_lang_dataflow.zig` 的边界识别只看"caller 和 callee 是否跨语言"。单 TU 场景下找不到 caller，整个文件被判定为"纯 C 单语言"，跳过所有 FFI-shape 分析。

**这是当前最大能力缺口**——OmniScope 把"被人调用"和"调用别人"做对称要求，但 FFI 导出库**只是被调用方**，没有进入 caller 视角的入口。

***

### 根因 R2: rustc IR 丢失 caller 端语言归属

**现象**：`rust_hash.ll` 源码明确 `extern "C" { fn c_hash(...); }` + `pub unsafe extern "C" fn rust_hash_compute(...) { c_hash(...) }`，但 OmniScope 判定为纯 Rust 单语言。

**IR 层证据**（已确认）：

```llvm
define noundef i32 @rust_hash_compute(ptr ..., i64 ..., ptr ...) unnamed_addr #0 { ... }
declare noundef i32 @c_hash(ptr ..., i64 ..., ptr ...) unnamed_addr #0    ← C 函数
declare noundef i32 @c_fft_forward(ptr ..., ptr ..., i64 ...) unnamed_addr #0
```

`@c_hash` 是 declare（不在本 TU 定义），命名是 C-style 非 Rust mangling（不带 `_RN...` / `_ZN...` 前缀）。这是 **rustc 把外部 C 函数声明发布出来的标准形式**——caller 是 Rust（`@rust_hash_compute` 是 `_RNvCs...` 风格 mangling），callee 是 C。

**OmniScope 当前行为**：`detectModuleLanguage` 把整个模块归到 Rust（统计 mangled 函数名占多数），单一语言模块直接走 same-language pass，**不进入 cross-lang 检测**。

**根因**：现在的判断是 module-level 的"主语言"，没有 per-function 的"调用方语言 vs 被调用方语言"判断。

***

### 根因 R3: C bridge "调用 C++ mangled 符号"只部分检出

**现象**：`c_hash_c_bridge.ll` / `c_fft_c_bridge.ll` 是 C 文件，但调用 C++ mangled 符号 `@_ZN8cpp_hash4HashEPKhmPh`，OmniScope 检测到混合迹象但最终判定单语言。

**IR 层证据**（已确认 c\_hash\_c\_bridge.ll）：

```llvm
define range(i32 -1, 1) i32 @c_hash(ptr ..., i64 ..., ptr ...) local_unnamed_addr #0 { ... }
declare void @_ZN8cpp_hash4HashEPKhmPh(ptr ..., i64 ..., ptr ...) ...    ← C++ mangled
```

主语言裁决（按 producer + 多数函数名）== C，但 `declare @_ZN8...` 是明确的 C++ ABI 调用。

**根因**：和 R2 同质——module-level 主语言赢者通吃，per-call-site 边界没有被独立保留。

***

## 二、方案：基于"符号视角"重构 FFI 边界识别

### 核心设计变更

把\*\*"模块属于某语言"**变成**"每个 declare / define 节点带语言归属，调用关系跨节点时即边界"\*\*。

```
旧模型（module-centric）：
  Module → Language → 对所有 function 应用同一套规则

新模型（symbol-centric）：
  Module → SymbolGraph
                ├─ Symbol{kind=define, name, lang, attrs, exported}
                └─ Symbol{kind=declare, name, lang, attrs}
                
  边 (Call) = caller.lang ≠ callee.lang → CrossLangCallSite
  孤立 define + exported + 外部 ABI → FFIExportSurface（无 caller 也算边界）
```

### 数据结构

```zig
// src/ffi/symbol_graph.zig (新文件)

pub const SymbolKind = enum {
    define,    // 本 TU 内有实现
    declare,   // 仅声明，实现在别处
};

pub const ABIClass = enum {
    c_abi,           // 无 mangling，extern "C" / 默认 C 函数
    cxx_itanium,     // _Z / _ZN... C++ Itanium mangling
    cxx_msvc,        // ?... MSVC mangling
    rust_v0,         // _R... Rust v0 mangling
    rust_legacy,     // _ZN..E + Rust hash 后缀 ($hash$)
    swift,           // _$s... Swift
    go,              // path.func 形式
    zig,             // namespace.func + zig_ prefix
    builtin,         // llvm.* intrinsic
    unknown,
};

pub const ExportClass = enum {
    not_exported,    // internal/private linkage
    weak_exported,   // weak/linkonce
    exported,        // external linkage
    constructor,     // appended in llvm.global_ctors
};

pub const Symbol = struct {
    name: []const u8,                 // 原始符号名
    demangled: ?[]const u8,           // 反向解析后的可读名（仅 mangled 才填）
    kind: SymbolKind,
    abi: ABIClass,                    // 根据 mangling/属性判定
    lang: LanguageId,                 // 推断的实现语言
    lang_confidence: f32,             // 0.0–1.0
    exported: ExportClass,
    has_definition: bool,             // == (kind == .define)
    address_taken: bool,              // 是否被 store/取地址（callback 候选）
    is_callback_param: bool,          // 是否作为函数参数类型出现
    source_file: ?[]const u8,         // 来自 DISubprogram 的源文件后缀
    llvm_value: c.LLVMValueRef,
};

pub const CallSite = struct {
    caller: *Symbol,                  // 必须是 define
    callee: *Symbol,                  // 可能是 declare 或 define
    call_inst: c.LLVMValueRef,
    is_indirect: bool,                // function pointer call
    crosses_language: bool,           // caller.lang != callee.lang
    crosses_abi: bool,                // caller.abi != callee.abi（C↔C++ 同语言可能跨 ABI）
};

pub const ExportSurface = struct {
    /// 单 TU 内某 define 是导出的、ABI 是外部可用的、本 TU 内没有 caller。
    /// 这种符号代表"被外部语言调用的接口"，需要独立分析其参数所有权/生命周期。
    symbol: *Symbol,
    exposure_reason: enum {
        c_abi_external_linkage,       // 普通 C 导出
        cxx_extern_c,                 // C++ 中的 extern "C" 函数
        constructor_export,           // __attribute__((constructor))
        callback_target,              // 地址被传入 register-style 函数
    },
};

pub const SymbolGraph = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(Symbol),
    call_sites: std.ArrayList(CallSite),
    export_surfaces: std.ArrayList(ExportSurface),
    
    // 索引：按语言分桶
    by_language: std.AutoHashMap(LanguageId, std.ArrayList(*Symbol)),
    // 索引：所有 cross-language call sites（caller-side 视角）
    cross_lang_calls: std.ArrayList(*CallSite),
    // 索引：所有 FFI export surfaces（被动暴露面）
    
    pub fn build(allocator: ..., module: c.LLVMModuleRef) !SymbolGraph;
    pub fn deinit(self: *SymbolGraph) void;
    pub fn getCrossLangSites(self: *const SymbolGraph) []const *CallSite;
    pub fn getExportSurfaces(self: *const SymbolGraph) []const ExportSurface;
};
```

### ABI/语言推断规则（per symbol）

| 输入                                                      | ABI 判定        | 语言判定                             |
| ------------------------------------------------------- | ------------- | -------------------------------- |
| `name` 以 `_R` 开头                                        | `rust_v0`     | `rust` 置信 0.99                   |
| `name` 以 `_ZN` 开头 + 含 `17h<16 hex>E` 后缀                 | `rust_legacy` | `rust` 置信 0.95                   |
| `name` 以 `_ZN`/`_Z` 开头（非上述）                             | `cxx_itanium` | `cpp` 置信 0.95                    |
| `name` 以 `?` 开头                                         | `cxx_msvc`    | `cpp` 置信 0.95                    |
| `name` 以 `_$s` 开头                                       | `swift`       | `swift` 置信 0.99                  |
| `name` 含 `.` 分隔的 path-style（`net/http.(*Server).Serve`） | `go`          | `go` 置信 0.95                     |
| `name` 是 `llvm.` 开头                                     | `builtin`     | 不参与边界                            |
| 其他无 mangling                                            | `c_abi`       | 从 DISubprogram → DIFile 后缀决定     |
| 无 mangling + 无 debug info                               | `c_abi`       | 从 module-level metadata fallback |

注意：**declare 节点同样跑这一套**，所以 `declare @c_hash` 会被判定为 `c_abi` / `c`，而调用它的 `define @rust_hash_compute`（`_RNv...`）会被判定为 `rust`——边界自动浮现。

***

## 三、Task List（按依赖顺序）

### Phase 1: 符号图基础（v0.20 主要工作量）

**T1**. `src/ffi/symbol_graph.zig` 新建。

- 定义上面所有数据结构。
- `Symbol` / `CallSite` / `ExportSurface` 字段完整。
- 不实现逻辑，只是结构 + `init`/`deinit`。
- **验收**：能编译；内存管理通过 std.testing.allocator 无泄漏。

**T2**. ABI/语言推断纯函数：`classifySymbol(name, attrs, debug_info) → (ABIClass, LanguageId, confidence)`。

- 抽自现有 `src/semantics/language_detector.zig` 的命名规则（已存在的 \_R/_ZN/zig_ 检测）。
- 加 swift/MSVC/Go 三类（当前没有）。
- 移除"统计多数函数名"逻辑——这一步只对单个 symbol 决策。
- **验收**：单元测试覆盖 12 类符号（每种 ABI 至少 2 例）。

**T3**. `SymbolGraph.build(module)` 实现。

- 遍历 `LLVMGetFirstGlobal` / `LLVMGetFirstFunction`，逐个 `classifySymbol` → 填入 `symbols` map。
- 遍历每个 define 的 BB → instruction，找 `LLVMCall`/`LLVMInvoke` → 解析 callee → 找 `symbols[name]` → 构造 `CallSite`。
- `crosses_language` / `crosses_abi` 在 build 时直接算好。
- **验收**：跑 10 个 ffi-demo .ll 文件，每个 module 的 symbols.count() 与 `llvm-objdump -t` 输出 symbol 数一致（±2%）。

**T4**. Export surface 检测：在 `SymbolGraph.build` 末尾扫一遍 symbols。

- 条件：`kind == .define` AND `exported in {.exported, .weak_exported, .constructor}` AND `abi in {c_abi, cxx_extern_c}` AND **本 TU 内没有 caller**（用 `call_sites` 反向索引检查）。
- 加 callback-target 启发：如果 symbol 的地址被 store 到了形如 `register*_callback` 的函数参数里，也算 export surface（即使有 caller）。
- **验收**：c\_ffi\_traps.ll 应识别出 11 个 export surface；c\_merkle\_tree.ll 应识别出 \~3 个。

***

### Phase 2: 替换现有检测路径

**T5**. `src/pass/analysis/ffi/ffi_detector.zig` 改造。

- 把现有"先 detectModuleLanguage 再判断是否进入 FFI 分析"的入口替换成"用 SymbolGraph.getCrossLangSites() 和 .getExportSurfaces()"。
- 保留 module language 字段（向后兼容），但不再作为是否分析的开关。
- **验收**：rust\_hash.ll 必须产出至少 2 个 `cross_language_call`（`rust_hash_compute → c_hash`、`rust_fft_forward → c_fft_forward`）。

**T6**. `cross_lang_dataflow.zig` 接入 SymbolGraph。

- 把当前用 `alloc.alloc_func` 字符串匹配的地方改成 `*Symbol` 指针。
- 这能解决 8 天前 memory 里记的 LLVM Value Identity 问题——`Symbol` 由 SymbolGraph 持有，指针稳定。
- **验收**：noise 测试套件回归不退化（rust\_ffi 15/25、gopyjava 27/36、cscpp 23/36）。

**T7**. Export surface 触发独立 pass：`src/pass/analysis/ffi/export_surface_analyzer.zig`（新）。

- 对每个 ExportSurface symbol 跑：
  - 参数所有权检查（caller 是否可能传 null、size 不一致）
  - 返回指针生命周期（caller 是否需要 free，是否标注了所有权）
  - 回调注册：参数中的 function pointer 是否被存到 global 或 long-lived 结构
- 这是回答"c\_ffi\_traps.ll 那 9 个陷阱"的 pass。
- **验收**：c\_ffi\_traps.ll 应至少检出 6 / 9 个预设陷阱（TRAP-C-8 cross-family free、TRAP-C-9 UAF、TRAP-C-11 leaked callback userdata 必检出）。

***

### Phase 3: 收尾

**T8**. 移除/降级 module-level language 强判定。

- `detectModuleLanguage` 改为"多语言 module" → 返回主导语言 + 第二语言列表。
- 调用方不再把"单语言"当作跳过 FFI 分析的理由。
- **验收**：c\_hash\_c\_bridge.ll / c\_fft\_c\_bridge.ll 输出里 cross-lang call sites 数 > 0。

**T9**. CLI 增加 `--report-surfaces` 开关，把 ExportSurface 列表打到 JSON 输出（独立字段，不混进 issues）。

- 用户可见"这个 .ll 暴露了 N 个 FFI 接口，独立分析了 M 个"。
- **验收**：JSON schema 新增 `export_surfaces: [...]` 数组，bun\_ll 跑通。

**T10**. 文档 + 回归。

- 更新 `docs/zh/REPORT_INTERPRETATION.md`：解释 export surface 和 cross-lang call site 的区别。
- 跑全部回归（noise 套件 + ffi-demo 10 文件 + bun\_ll 8 文件）→ 出对比表。
- **验收**：
  - ffi-demo 10 文件的 F1 从 1/5 提升到 ≥ 4/5
  - bun\_ll 总 issue 数不显著上升（< 20%）
  - noise 测试不退化

***

## 四、风险与回退点

| 风险                                                                | 应对                                         |
| ----------------------------------------------------------------- | ------------------------------------------ |
| Symbol graph 内存开销大（bun\_ll zig\_main 11MB IR → 估计 \~2000 symbols） | 流式构建，不全量加载 `Symbol.demangled`（按需 demangle） |
| Export surface 在 stdlib 上误报多（每个 libc 符号都是 export）                 | 配置黑名单：libc/libstdc++/CRT 符号默认排除            |
| 单文件分析改变 noise 基线                                                  | T5/T6 完成时立刻跑 noise 回归；超 5% 退化阻塞合入          |
| Rust legacy mangling 检测假阳性（`_ZN<n><name>17h<hash>E` 模式)           | 用正则严格匹配 `17h[0-9a-f]{16}E$` 后缀             |

**回退点**：每个 Phase 独立 commit。如果 T7 出问题，可以 revert 仅 T7，保留 T1-T6 已建好的 SymbolGraph 给下版用。

***

## 五、对应文件位置速查

| 测试场景                    | IR 文件                                                                                 | 源码                                                   |
| ----------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| C 单文件 FFI export（R1 主测） | `~/code/ffi-demo/output/c_ffi_traps.ll`                                               | `~/code/ffi-demo/c/ffi_traps.{c,h}`                  |
| Rust→C 调用（R2 主测）        | `~/code/ffi-demo/output/rust_hash.ll`                                                 | `~/code/ffi-demo/rust_hash/src/lib.rs`               |
| C→C++ 调用（R3 主测）         | `~/code/ffi-demo/output/c_hash_c_bridge.ll`、`c_fft_c_bridge.ll`                       | `~/code/ffi-demo/c/hash_c_bridge.c`、`fft_c_bridge.c` |
| Zig→C 调用（基线 OK）         | `~/code/ffi-demo/output/zig_main.ll`                                                  | `~/code/ffi-demo/zig/main.zig`                       |
| 单语言（不应误报 FFI）           | `~/code/ffi-demo/output/c_merkle_tree.ll`、`cpp_fft.ll`、`cpp_hash.ll`、`rust_merkle.ll` | 对应源码目录                                               |

***

## 六、可立刻验证的最小切片

如果不想等完整 v0.2.0，**T1+T2+T3+T5 是最小可工作切片**（\~3 天工作量），能立刻把 rust\_hash.ll 漏报修掉，但解决不了 c\_ffi\_traps.ll 的 export surface 问题（那需要 T4+T7）。

如果只想优先解决"用户能看见检测能力"，**优先级 T1→T2→T3→T4→T7**——T7 跑出 c\_ffi\_traps.ll 的 9 个陷阱比 T5 跑出 rust\_hash.ll 的 2 个 cross-lang call 更有展示价值。

**推荐**：按 T1→T10 顺序做，但在 T4 完成后**先发一个 v0.2.1 beta**（只有 SymbolGraph + ExportSurface 识别，不接入下游 pass），让用户能看到"OmniScope 现在识别出了哪些 FFI 接口"。下游分析（T6/T7）放 v0.2.0。

***

## 七、实施状态（2026-06-08）

### 已实施

| Task | 状态 | 说明 |
|------|------|------|
| **T1** `symbol_graph.zig` 数据结构 | ✅ 完成 | 所有数据结构完整（Symbol / CallSite / ExportSurface / SymbolGraph），含 `init`/`deinit`/`build` 框架已实现。单元测试覆盖 classifySymbol 的 12 类符号 |
| **T2** ABI/语言推断纯函数 | ✅ 完成 | `classifySymbol` 已实现，覆盖 Rust v0/Rust legacy/C++ Itanium/MSVC/Swift/Go/LLVM builtin/C fallback。含 debug-info 二次判定 |
| **T3** `SymbolGraph.build` | ✅ 完成 | Phase 1–4 完整（收集符号 → 构建 call sites → 语言索引 → export surface 检测） |
| **T4** Export surface 检测 | ✅ 完成 | `detectExportSurfaces` 实现，支持 3 种曝光原因（c_abi_external_linkage / cxx_extern_c / callback_target） |
| **T5** `ffi_detector.zig` 改造 | ✅ 完成 | 已接入 SymbolGraph + ExportSurfaceAnalyzer，替换了旧的 module-level 检测路径 |
| **T6** `cross_lang_dataflow.zig` 接入 | ✅ 完成 | `analyzeModuleUnified` 中 `func_lang` 改为 SymbolGraph per-symbol 语言（fallback module-level） |
| **T7** `export_surface_analyzer.zig` | ✅ 完成 | 已创建并接入，在 ffi_detector.zig 中调用 |
| **T8** 移除/降级 module-level 强判定 | ✅ 完成 | LanguageProfile 扩展 `secondary_languages` + `isMultiLanguage()`；`isCModule()` 多语言模块返回 false；`detectSecondaryLanguages()` 扫描 declare 符号 ABI 模式 |
| **T9** CLI `--report-surfaces` 开关 | ✅ 完成 | 已在 CLI 选项中实现 |
| **T10** 文档 + 回归 | 🔄 进行中 | 本文档更新 + 回归测试执行中 |

### 已知问题

1. **严重：符号图指针生命周期 Bug** — `processCallInstruction` 中 `cross_lang_calls` 存储指向 `call_sites` 内部缓冲区的 `*CallSite` 指针，但 `call_sites.append` 可能触发 reallocation，导致指针悬挂。表现为 `ffi_detector.zig:246` 处 `site.callee.name` 读取到 `0xaaaaaaaaaaaaaaaa`（释放后毒值）。影响范围：所有包含跨语言调用或有多个 call site 的模块。
2. **rust_hash.ll** 仅检出 `rust_fft_forward → c_fft_forward` 这一个跨语言调用，漏掉了 `rust_hash_compute → c_hash`（预期应检出 2 个 cross-lang call）。
3. **zig_main.ll** 在 ExportSurfaceAnalyzer 内部崩溃（`ffi_detector.zig:233`），与问题 1 同根因。
4. 所有 bun\_ll 8 文件全部因问题 1 崩溃，无法评估回归噪音。
5. `--force-analysis` 同样受问题 1 影响而崩溃。

### 回归测试结果速览

| 测试项 | 结果 |
|--------|------|
| `zig build` | ✅ 编译通过 |
| `zig build test` | ✅ 42 passed, 45 warnings, 0 failed, Total: 87 |
| ffi-demo rust\_hash.ll | ✅ 检出 1 issue（Rust → C boundary, 8ms） |
| ffi-demo 其余 9 文件 | ❌ 全部崩溃（同根因：指针悬挂） |
| bun\_ll 8 文件 | ❌ 全部崩溃 |
| `--force-analysis` | ❌ 崩溃 |

### 与验收标准对比

| 验收标准 | 目标 | 当前 | 差距 |
|---------|------|------|------|
| ffi-demo F1 分数 | ≥ 4/5 | ~0/5（9/10 文件崩溃） | 🔴 严重退化 |
| bun\_ll 总 issue 数不显著上升 | < 20% | 无法评估（全崩溃） | 🔴 阻塞 |
| noise 测试不退化 | 0 退化 | 42/87（与基线一致） | ✅ 通过 |
