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

**文件**: `src/config/language_override.zig`

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
