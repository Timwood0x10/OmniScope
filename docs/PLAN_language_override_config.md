# Language Override Config — 实现方案

## 一、设计目标

用户对自己提交的 IR 文件中的符号有 **100% 正确的语言知识**。让用户告知工具"这个符号是什么语言"，比自动检测更可靠。

### 使用场景

```bash
# 场景 A：纯 C 项目里有外部 Rust allocator 符号
omniscope --default-lang c --lang __rust_alloc=rust sqlite3_combined.bc

# 场景 B：多文件 IR，每文件一种语言
omniscope --source-lang c:c_code.ll --source-lang rust:rust_lib.bc combined.bc

# 场景 C：项目长期使用，配置文件 commit 到 repo
omniscope --config omniscope.json combined.bc
```

---

## 二、配置文件格式

扩展现有的 `omniscope.json`，在 `analysis.language_detection` 下增加新字段：

```json
{
  "analysis": {
    "language_detection": {
      "auto_detect": true,

      "default_language": "c",

      "overrides": {
        "exact": {
          "__rust_alloc": "rust",
          "__rust_dealloc": "rust",
          "sqlite3_malloc": "c",
          "sqlite3_free": "c"
        },

        "prefix": {
          "sqlite3_": "c",
          "sqlite3Mem": "c",
          "sqlite3Db": "c",
          "__rust_": "rust",
          "_ZN": "rust",
          "_R": "rust",
          "_Z": "cpp"
        },

        "suffix": {
          "_rs": "rust",
          "_go": "go"
        }
      },

      "source_files": {
        "c_sqlite3.ll": "c",
        "rust_core.bc": "rust"
      }
    }
  }
}
```

### 命令行接口

```bash
# 精确符号
--lang __rust_alloc=rust
--lang sqlite3_malloc=c

# 前缀匹配
--lang-prefix sqlite3_=c
--lang-prefix __rust_=rust
--lang-prefix _ZN=rust

# 源文件级
--source-lang c:c_sqlite3.ll
--source-lang rust:rust_lib.bc

# 全局默认
--default-lang c

# 组合（纯 C 项目最简用法）
omniscope --default-lang c --lang __rust_alloc=rust combined.bc
```

---

## 三、新增模块：`LanguageOverrideRegistry`

**文件**: `src/config/language_override.zig`（新增，~250 行）

### 核心接口

```zig
pub const LanguageOverrideRegistry = struct {
    // (a) 精确匹配 HashMap: func_name → Language
    exact_map: std.StringHashMap(Language),

    // (b) 前缀匹配: 排序后存储在 ArrayList 中
    prefix_rules: std.ArrayList(PrefixRule),

    // (c) 后缀匹配
    suffix_rules: std.ArrayList(SuffixRule),

    // (d) 源文件级: filename → Language
    source_file_map: std.StringHashMap(Language),

    // (e) 全局默认
    default_lang: ?Language,

    /// 查找一个符号的语言（优先级：exact > prefix > suffix > auto_detect > default > unknown）
    pub fn lookup(self, func_name: []const u8) ?Language;

    /// 查找一个源文件的语言
    pub fn lookupSourceFile(self, filename: []const u8) ?Language;

    /// 从 JSON 配置加载
    pub fn loadFromJson(self, json_value: std.json.Value) !void;

    /// 从 CLI 参数加载
    pub fn loadFromCLI(self, cli_args: ...) !void;
};
```

### 查找优先级链

```
UserConfig.exact_match  ──────▶ ✅ 直接命中，最高优先级
UserConfig.prefix_match ──────▶ 最长的匹配前缀获胜（避免 `sqlite3` 和 `sqlite3Mem` 冲突）
UserConfig.suffix_match ──────▶ 最长的匹配后缀获胜
ffi_language_classifier ──────▶ 自动分类检测（现有）
classifyAllocLanguage   ──────▶ 现有的分配器语言分类（作为 fallback）
UserConfig.default_lang ──────▶ 用户指定的默认语言
unknown                 ──────▶ 最终 fallback
```

---

## 四、实施步骤

### Step 1: 创建 `LanguageOverrideRegistry`

**文件**: `src/config/language_override.zig`（新增，~250 行）

1.1 定义 PrefixRule / SuffixRule 结构体
1.2 实现 exact_map: `std.StringHashMap(Language)`——O(1) 查找
1.3 实现 prefix_rules 的插入与排序——按前缀长度降序（最长优先匹配）
1.4 实现 `lookup(func_name)`——按优先级链逐一尝试
1.5 实现 `loadFromJson(json_value)`——从 JSON value 解析
1.6 实现 `loadFromCLI(...)`——从 CLI args 解析
1.7 编写单元测试覆盖：
   - exact match 优先于 prefix
   - 最长 prefix 优先
   - JSON 与 CLI 合并（CLI 优先）
   - 未匹配返回 null
   - 默认语言 fallback

### Step 2: 扩展 `file_config.zig` 的 JSON 解析

**文件**: `src/types/file_config.zig`（修改，+50 行）

2.1 在 `AnalysisConfig.LanguageDetection` 中增加 `overrides` 字段
2.2 在 `FileConfig` 中增加 `LanguageOverrideRegistry` 实例字段
2.3 实现 `loadFromFile()` 的真正 JSON 解析（目前是 TODO stub → 用 `std.json.parseFromSlice` 解析全部字段）
2.4 初始化 `LanguageOverrideRegistry` 并从 JSON 填充
2.5 编写测试：加载含 language overrides 的 JSON 文件

### Step 3: 扩展 `main_config.zig` 的 CLI 参数

**文件**: `src/types/main_config.zig`（修改，+50 行）

3.1 增加 `--lang <name=language>` CLI 参数（可重复）
3.2 增加 `--lang-prefix <prefix=language>` CLI 参数（可重复）
3.3 增加 `--source-lang <filename:language>` CLI 参数（可重复）
3.4 增加 `--default-lang <language>` CLI 参数
3.5 在 `Config` 中增加 `LanguageOverrideRegistry` 实例
3.6 在 `parseArgs()` 中解析新增参数并填充 registry
3.7 编写测试：CLI 参数解析正确

### Step 4: 集成到 Pipeline

**文件**: `src/pipeline/pipeline.zig`（修改，+30 行）

4.1 Pipeline 新增 `language_overrides: ?*LanguageOverrideRegistry` 字段
4.2 `setModule()` 之外增加 `setLanguageOverrides(registry)` 方法
4.3 在 PassContext 初始化时传递 registry 引用

### Step 5: 集成到 PassContext

**文件**: `src/types/pass_types.zig`（修改，+20 行）

5.1 PassContext 新增 `language_overrides: ?*LanguageOverrideRegistry` 字段
5.2 新增 `lookupFunctionLanguage(func_name) Language` 方法——去 registry 查，查不到走原来的分类逻辑

### Step 6: 接入 `classifyAllocLanguage` 和 `classifyFreeLanguage`

**文件**: `src/pass/analysis/ffi/cross_lang_dataflow.zig`（修改，+20 行）

6.1 修改 `classifyAllocLanguage(callee_name, caller_lang)` 签名，增加可选 `registry` 参数
6.2 在函数开头加：`if (registry) |r| { if (r.lookup(callee_name)) |lang| return lang; }`
6.3 同样修改 `classifyFreeLanguage`
6.4 修改所有调用点传递 registry

### Step 7: 接入 `isAllocationFunction` / `isFreeFunction`

**文件**: `src/pass/analysis/ffi/cross_lang_dataflow.zig`（修改，+15 行）

7.1 所有调用点的 `isAllocationFunction(called_name)` 之前先查 registry
7.2 若 registry 声明了该符号的语言，跳过自动分配器/释放器判定
7.3 避免 sqlite3_malloc 被误判为跨语言分配器

### Step 8: 接入 `danger_surface.zig`

**文件**: `src/pass/analysis/danger_surface.zig`（修改，+15 行）

8.1 跨语言生命周期检查处（line 144）：先用 registry 确认 node.alloc_callee 的真实语言
8.2 若 registry 声明为同语言（如 sqlite3_malloc → C），不做跨语言标记

### Step 9: 接入 `ffi_unsafe.zig`

**文件**: `src/pass/analysis/issue/ffi_unsafe.zig`（修改，+15 行）

9.1 在 `isWhitelisted` 中增加 registry 查询
9.2 若调用者和被调用者都在 registry 中声明为同语言，跳过
9.3 若 default_lang=c 且无相反的 registry 声明，大量 sqlite3 内部调用被过滤

### Step 10: 接入 `ffi_language_classifier.zig`

**文件**: `src/pass/analysis/ffi/ffi_language_classifier.zig`（修改，+10 行）

10.1 在 per-function 语言分类入口先查 registry
10.2 registry 命中直接返回，不走自动检测

### Step 11: 接入 `language_detector.zig`

**文件**: `src/semantics/language_detector.zig`（修改，+10 行）

11.1 default_language 配置作为模块级检测的 fallback
11.2 当自动检测置信度 < 0.4 且 default_lang 不为 unknown 时，使用 default_lang

### Step 12: 集成到 `main.zig`

**文件**: `src/main.zig`（修改，+30 行）

12.1 `runSingleFileAnalysis` 中传递 config 中的 LanguageOverrideRegistry 到 pipeline
12.2 优先加载配置文件的 overrides，然后合并 CLI overrides（CLI 覆盖文件）

### Step 13: 编写示例配置

**文件**: `omniscope.example.json`（新增，~50 行）

13.1 包含 sqlite3 场景的完整配置
13.2 包含 Rust + C 混合场景的配置
13.3 包含跨语言的完整配置

### Step 14: 集成测试

**文件**: `tests/language_override_test.zig`（新增，~150 行）

14.1 测试 registry 查找优先级
14.2 测试 JSON 加载 + CLI 合并
14.3 测试集成到分类函数后的行为
14.4 测试 sqlite3 FP 消除
14.5 测试 TC6 Box::leak 抑制（registry 正确标注 __rust_alloc=rust）

---

## 五、文件改动汇总

| # | 文件 | 操作 | 行数 |
|---|------|------|------|
| 1 | `src/config/language_override.zig` | **新增** | ~250 |
| 2 | `src/types/file_config.zig` | 修改 | +50 |
| 3 | `src/types/main_config.zig` | 修改 | +50 |
| 4 | `src/pipeline/pipeline.zig` | 修改 | +30 |
| 5 | `src/types/pass_types.zig` | 修改 | +20 |
| 6 | `src/pass/analysis/ffi/cross_lang_dataflow.zig` | 修改 | +35 |
| 7 | `src/pass/analysis/danger_surface.zig` | 修改 | +15 |
| 8 | `src/pass/analysis/issue/ffi_unsafe.zig` | 修改 | +15 |
| 9 | `src/pass/analysis/ffi/ffi_language_classifier.zig` | 修改 | +10 |
| 10 | `src/semantics/language_detector.zig` | 修改 | +10 |
| 11 | `src/main.zig` | 修改 | +30 |
| 12 | `omniscope.example.json` | **新增** | ~50 |
| 13 | `tests/language_override_test.zig` | **新增** | ~150 |
| | **合计** | | **~715 行** |

---

## 六、为什么选 JSON 不是 TOML

| 因素 | JSON | TOML |
|------|------|------|
| 现有基础设施 | 已有 `std.json` + `file_config.zig` JSON 模板 | 无 |
| Zig 标准库支持 | 原生支持 `std.json` | 无 |
| 前例 | 已有 `config_loader.zig` JSON 加载 | 无 |
| 实现工作 | 扩充已有结构（+50 行） | 需编写 TOML 解析器（~500+ 行） |
| 给用户的格式 | 已有 `.omniscope.json` 约定 | 新引入 `.omniscope.toml` |

**结论**：先用 JSON 接入已有基础设施，扩展 `omniscope.json`。未来可加 TOML 作为第二种配置格式输入，内部统一转为 `LanguageOverrideRegistry` 结构。

---

## 七、P0 场景的最简使用路径

### sqlite3 纯 C 项目

```bash
# 只需 2 个参数
omniscope --default-lang c --lang __rust_alloc=rust sqlite3.bc

# 或用配置文件
omniscope --config sqlite3_config.json sqlite3.bc
```

`sqlite3_config.json`:
```json
{
  "analysis": {
    "language_detection": {
      "auto_detect": false,
      "default_language": "c",
      "overrides": {
        "exact": {
          "__rust_alloc": "rust",
          "__rust_dealloc": "rust",
          "__rust_realloc": "rust"
        }
      }
    }
  }
}
```

### Rust + C 混合项目

```json
{
  "analysis": {
    "language_detection": {
      "auto_detect": true,
      "overrides": {
        "prefix": {
          "sqlite3_": "c",
          "my_c_lib_": "c",
          "_ZN": "rust"
        }
      }
    }
  }
}
```

---

## 8. Language-Specific LLVM IR Symbol Pattern Reference

This section documents the naming conventions, mangling schemes, and well-known symbol patterns for each language that OmniScope encounters in LLVM IR bitcode. Use these patterns to configure `LanguageOverrideRegistry` entries.

### 8.1 Priority Chain (Recap)

When OmniScope resolves a symbol's language, the following chain is consulted in order:

```
1. Exact match (user override)     → O(1) HashMap lookup
2. Longest prefix match (override) → linear scan over sorted rules
3. Longest suffix match (override) → linear scan over sorted rules
4. ffi_language_classifier         → auto-detection (name heuristics)
5. classifyAllocLanguage           → allocator/deallocator heuristics
6. User default_language           → fallback from config/CLI
7. unknown                         → final fallback
```

### 8.2 Rust

Rust emits several mangling schemes depending on the compiler version and target.

#### Legacy mangling (`_ZN`) — Rust stable before 1.77 (2024)

Format: `_ZN<length><element>...E`
- Each path element is length-prefixed: `_ZN5alloc5boxed19Box$LT$T$GT$4leak17h<digest>E`
- Always ends with `17h<hash>E` or `E` for the hash suffix on the final element
- Contains special characters: `$LT$` (<), `$GT$` (>), `$LP$` ((), `$RP$` ())

Common prefixes:
```
_ZN5alloc          → alloc crate (allocators, Box, Vec)
_ZN4core          → core crate (mem, ptr, panic, result)
_ZN3std           → std crate
_ZN5compiler       → compiler_builtins
_ZN4test          → test harness
_ZN95              → backtrace crate
```

Allocation symbols (no mangling — C ABI exports):
```
__rust_alloc
__rust_dealloc
__rust_realloc
__rust_alloc_error_handler
__rust_alloc_zeroed
rust_begin_unwind
rust_eh_personality
```

#### v0 mangling (`_R`) — Rust 1.77+ (default since 2024)

Format: `_R<ident-start><crate-id><item-path><final-ident>`
- Begins with `_R`: `_RdNvYNv` for different ABI variants
- No trailing `E` like legacy mangling
- Crate ID is a hash, not a name — so `_R` prefix alone is sufficient for detection

```
_RdNv            → default calling convention, normal visibility
_RdNvYNv         → explicit ABI annotations
_RINv            → inherent method
_RNv             → free function
```

#### Detection strategy for Rust

For `LanguageOverrideRegistry`:
```json
{
  "exact": {
    "__rust_alloc": "rust",
    "__rust_dealloc": "rust",
    "__rust_realloc": "rust",
    "rust_begin_unwind": "rust"
  },
  "prefix": {
    "_ZN": "rust",
    "_R": "rust",
    "__rust_": "rust",
    "rust_eh_": "rust"
  }
}
```

Key observations:
- `_ZN` alone is ambiguous: both Rust (legacy) and C++ use `_ZN`. Disambiguate by checking for `$LT$`, `$GT$`, or the `17h` digest suffix in Rust vs C++ Itanium ABI.
- A more reliable multi-factor check: Rust `_ZN` always contains `E` at the end, and intermediate elements before `E` often contain `$` characters.
- For safety, prefer `exact` over `prefix` for `__rust_*` symbols — they are rare enough to enumerate.

### 8.3 C++

C++ uses the Itanium C++ ABI mangling scheme on all non-MSVC platforms (Linux, macOS, BSD, Android).

#### Itanium ABI (`_Z`)

Format: `_Z<qualified-name><type-string>`
- `_Z` followed by nested name lengths
- Common prefixes:

```
_ZTV             → vtable (Virtual Table)
_ZTI             → typeinfo (typeinfo object)
_ZTS             → typeinfo name (string)
_ZN              → nested name (namespace::Class::method)
_ZNK             → nested name, const method
_ZSt             → std:: namespace
_ZNSt            → std:: nested name
_ZNKSt           → const std:: method
_ZNS             → std::string
_ZNKS            → const std::string method
```

#### GCC/Clang builtins
```
___cxa_               → C++ ABI runtime (guard, throw, catch, rethrow, pure_virtual)
___dynamic_cast
___gxx_personality_v0
```

#### Microsoft ABI (`?`) — rare in LLVM IR but possible

MSVC-mangled symbols begin with `?` followed by:
```
?className@@       → class
?methodName@@      → method
?symbolName@@      → variable
```

Detection for `LanguageOverrideRegistry`:
```json
{
  "prefix": {
    "_Z": "cpp",
    "_ZN": "cpp",
    "_ZNK": "cpp",
    "_ZSt": "cpp",
    "_ZTV": "cpp",
    "_ZTI": "cpp",
    "_ZTS": "cpp",
    "__cxa_": "cpp",
    "__gxx_": "cpp"
  }
}
```

Note on `_ZN` ambiguity: When both Rust (legacy) and C++ are present, the registry will match whichever prefix rule is defined first (no tiebreaker by length since both use `_ZN`). **Always explicitly configure `_ZN` for the dominant language** in your project.

### 8.4 Go

Go's LLVM IR output (via `tinygo` or `llvm-go`) uses distinctive naming patterns.

#### Go function symbols
```
_go_               → top-level prefix for Go runtime functions
_go_free           → Go allocator free
_go_alloc          → Go allocator alloc
_go_assert         → runtime assertion
_go_panic          → runtime panic
_go_recover        → runtime recover
_go_slice          → slice operations
_go_map            → map operations
_go_chan           → channel operations
_go_string         → string operations
_go_interface      → interface dispatch
_go_type           → type metadata
_go_defer          → defer handling
_go_goroutine      → goroutine management
```

#### Go type descriptors
```
go..typeref        → type reference metadata
go.string.         → string literals
go.info.           → type info symbols
go.itab.           → interface table entries
```

#### Go ABI symbols
```
CrossCall2         → cgo cross-call trampoline
_x_cgo_            → cgo setup functions
_cgo_              → cgo bridge functions
_rt0_              → Go runtime startup
```

Detection:
```json
{
  "prefix": {
    "_go_": "go",
    "go.": "go",
    "_cgo_": "go",
    "_rt0_": "go"
  }
}
```

Go symbols are very reliable to detect by prefix — the `_go_` prefix is near-unique to Go.

### 8.5 Zig

Zig's LLVM IR output does not have a single universal mangling scheme. Zig uses the LLVM naming directly, and its symbols are less patterned than Rust or C++.

#### Zig export patterns
```
zig_               → Zig runtime exports
zig_eh_            → Zig exception handling
zig_panic          → Zig panic handler
zig_alloc          → Zig allocator interface
```

#### Zig function naming
- Zig preserves user-defined function names directly (no mangling)
- Generic function instantiations get appended type info:
  `ArrayList(i32).push`
  `HashMap([]const u8, i32).get`
- Compiler-generated symbols follow no single pattern

Because Zig has no mandatory mangling scheme, prefix-matching is less effective. Prefer `default_language` for Zig-dominant projects or `exact` overrides for specific exported symbols.

### 8.6 C (Standard Library and Common Projects)

C functions are unmangled — symbol names directly correspond to source names. This makes C the *default* language for unrecognized symbols.

#### Standard C library patterns
```
malloc, calloc, realloc, free, aligned_alloc
memcpy, memmove, memset, memcmp
strcpy, strncpy, strcat, strncat, strcmp, strncmp, strlen
printf, fprintf, sprintf, snprintf, vprintf, vsnprintf
scanf, fscanf, sscanf
fopen, fclose, fread, fwrite, fseek, ftell
socket, connect, bind, listen, accept, send, recv
pthread_create, pthread_mutex_lock, pthread_cond_wait
dlopen, dlsym, dlclose
```

#### Well-known project prefixes
```
sqlite3_           → SQLite
sqlite3Mem         → SQLite memory subsystem
sqlite3Db          → SQLite database-layer memory
ngx_               → Nginx
httpd_             → Apache httpd
apr_               → Apache Portable Runtime
curl_              → libcurl
SSL_               → OpenSSL
EVP_               → OpenSSL EVP
BIO_               → OpenSSL BIO
CRYPTO_            → OpenSSL crypto
ossl_              → OpenSSL 3.x
sk_                → OpenSSL stack
lh_                → OpenSSL lhash
z_                 → libz (zlib)
gz_                → libz gz*
png_               → libpng
jpeg_              → libjpeg
xml_               → libxml2
xmlTextReader      → libxml2
xmlSAX             → libxml2
xmlNew             → libxml2
xmlParse           → libxml2
Py_                → CPython
_Py_               → CPython internal
_PY_               → CPython
my_malloc          → Custom allocator wrapper
my_free            → Custom allocator wrapper
```

For sqlite3 specifically:
```
sqlite3_malloc     → NOT an allocator — it's a C utility wrapper
sqlite3_free       → NOT a deallocator — C utility wrapper
sqlite3MemMalloc   → The REAL allocator function within sqlite3
sqlite3MemFree     → The REAL deallocator within sqlite3
```

Detection:
```json
{
  "exact": {
    "sqlite3_malloc": "c",
    "sqlite3_free": "c",
    "sqlite3_realloc": "c"
  },
  "prefix": {
    "sqlite3_": "c",
    "ngx_": "c",
    "apr_": "c",
    "curl_": "c",
    "SSL_": "c"
  }
}
```

### 8.7 Java / JNI

JNI (Java Native Interface) symbols follow the `Java_` prefix convention.

#### JNI function naming

Format: `Java_<package>_<class>_<method>`
- Package separators `.` → `_`
- Package names use `_` for actual underscores → `_1`
- `Java_org_sqlite_NativeDB__1exec` → package `org.sqlite`, class `NativeDB`, method `_exec`

```
Java_              → ALL JNI entry points follow this prefix
JNI_OnLoad         → JNI library initialization
JNI_OnUnload       → JNI library teardown
```

#### JNI type signatures in comments/metadata
```
([BII)V            → (byte[], int, int) → void
(Ljava/lang/String;)I  → (String) → int
```

Detection:
```json
{
  "prefix": {
    "Java_": "java",
    "JNI_": "java"
  }
}
```

### 8.8 Swift

Swift uses a unique mangling scheme beginning with `$S` or `$s`.

#### Swift mangling (`$S` / `$s`)

Format: `$S<module-length><module><type><identifier><discriminator>`
- Swift 5.0+ uses `$s` (lowercase)
- Older Swift uses `$S` (uppercase)
- Symbols encode module names, type names, and function labels:
  `$s4main5hello33yyoSi_yF` → module `main`, function `hello`, calling convention

```
$s                → Swift 5+ mangling
$S                → Swift 4.x mangling
_s:               → Swift internal runtime symbols
_swift_           → Swift runtime support functions
swift_            → Swift runtime (alloc, retain, release)
```

#### Swift runtime symbols
```
swift_allocObject      → Swift heap allocation
swift_retain           → reference counting retain
swift_release          → reference counting release
swift_initStackObject  → stack promotion
swift_getTypeByMangledName  → type metadata
swift_getWitnessTable  → protocol witness table
swift_release_         → various release variants
```

Detection:
```json
{
  "prefix": {
    "$S": "swift",
    "$s": "swift",
    "swift_": "swift",
    "_swift_": "swift"
  }
}
```

### 8.9 Python / CPython

CPython extension modules export C-API symbols with distinctive prefixes.

```
PyInit_            → Module initialization entry point
PyModule_          → Module creation/management
PyObject_          → Object operations (getAttr, setAttr, call)
PyType_            → Type operations
PyUnicode_         → Unicode string operations
PyBytes_           → Bytes operations
PyList_            → List operations
PyDict_            → Dict operations
PyTuple_           → Tuple operations
PyLong_            → Integer (long) operations
PyFloat_           → Float operations
PyCFunction_       → C function wrapping
PyMem_             → Memory allocator (PyMem_Malloc, PyMem_Free)
PyMem_RawMalloc    → Raw allocator (bypasses GC)
_Py_               → Internal CPython API
_PyObject_         → Internal object API
```

Detection:
```json
{
  "prefix": {
    "PyInit_": "python",
    "PyModule_": "python",
    "PyObject_": "python",
    "PyMem_": "python",
    "PyType_": "python",
    "PyUnicode_": "python",
    "_Py_": "python"
  }
}
```

### 8.10 C# / .NET (via NativeAOT or Mono LLVM)

.NET NativeAOT output uses recognizable runtime prefixes.

```
Rhp              → Runtime native helper (RhpNewFast, RhpAssignRef)
RhpRareUse       → Rare-use runtime paths
S_P_CoreLib      → System.Private.CoreLib module
g_pGC            → GC globals
g_pObject        → Object globals
MDIL             → MDIL module references
___mono_         → Mono runtime
_mono_           → Mono runtime (alternate)
mono_            → Mono runtime functions
```

Detection:
```json
{
  "prefix": {
    "Rhp": "csharp",
    "RhpRare": "csharp",
    "S_P_": "csharp",
    "mono_": "csharp",
    "_mono_": "csharp"
  }
}
```

### 8.11 Cross-Language Signals

Certain symbols are strong indicators that a function is *cross-language* (an FFI boundary):

| Pattern | Meaning | Typical Boundary |
|---------|---------|------------------|
| `ffi_` | Explicit foreign function interface | Rust→C, C→any |
| `extern_` | extern-declared function | Any→any |
| `cb__` | Callback trampoline | C→Rust, Rust→C |
| `cabi_` | C ABI shim (Rust) | Rust→C |
| `C2Rust` | C2Rust-translated function | Rust/C hybrid |
| `__rust_calls_` | Rust→C trampoline | Rust→C |
| `_transitive_` | Transitive FFI bridge | Multi-language |
| `wasm_import_` | WASM import | WASM→host |

### 8.12 Quick-Reference Config Table

| Language | Prefix/Pattern | Priority | Ambiguity |
|----------|---------------|----------|-----------|
| Rust (v0) | `_R` | Highest (unique) | None |
| Rust (legacy) | `_ZN...$` or `_ZN...E` | High (check `$` or E-suffix) | Conflicts with C++ `_ZN` |
| Rust (ABI) | `__rust_` | Highest (unique) | None |
| C++ | `_Z` (not `_ZN`) | High | `_ZN` conflicts with Rust |
| C++ | `_ZSt`, `_ZTV`, `_ZTI` | Highest | Unique to C++ stdlib |
| C++ | `__cxa_` | Highest (unique) | None |
| Go | `_go_` | Highest (unique) | None |
| Swift | `$S`/`$s` | Highest (unique) | None |
| Swift | `swift_` | High | Could match user symbols |
| Java | `Java_` | Highest (unique) | None |
| Python | `PyInit_`, `PyMem_` | Highest (mostly) | Conflicts with C projects named `py_*` |
| Zig | `zig_` | Medium | Not comprehensive |
| C# | `Rhp` | High | Unlikely in C/C++ |
| C | no prefix | Lowest (default) | Everything |
| C | `sqlite3_`, `ngx_`, etc. | High (configure per-project) | None within context |

### 8.13 Recommended Default Config for Mixed Projects

```json
{
  "analysis": {
    "language_detection": {
      "auto_detect": true,
      "default_language": "c",
      "overrides": {
        "exact": {
          "__rust_alloc": "rust",
          "__rust_dealloc": "rust",
          "__rust_realloc": "rust",
          "sqlite3_malloc": "c",
          "sqlite3_free": "c",
          "sqlite3_realloc": "c"
        },
        "prefix": {
          "_R": "rust",
          "$S": "swift",
          "$s": "swift",
          "Java_": "java",
          "_go_": "go",
          "swift_": "swift",
          "Rhp": "csharp",
          "PyInit_": "python",
          "PyMem_": "python",
          "cpp_": "cpp",
          "ngx_": "c",
          "apr_": "c",
          "curl_": "c",
          "SSL_": "c",
          "sqlite3_": "c",
          "sqlite3Mem": "c",
          "sqlite3Db": "c",
          "_ZN": "rust"
        }
      }
    }
  }
}
```

**Important**: If your project contains both Rust (legacy mangling, `_ZN`) and C++ (`_ZN`), define `_ZN` as whichever language dominates. Then use `exact` overrides for the minority-language symbols.
