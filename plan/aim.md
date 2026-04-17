好，这里我不给你“泛泛路线图”，而是给一条**能落地、能逐步产出价值、并且紧扣你定位（FFI/unsafe 边界）**的开发路线。

先把一句话目标钉死：

OmniScope = 专注 FFI 边界的静态分析器（runtime 是增强，而不是核心）

⸻

🧭 总体路线（3 个阶段，不要跳）

Phase 1：能跑 + 有结果（单机静态分析工具）
Phase 2：跨语言 FFI 深度分析（核心竞争力）
Phase 3：runtime + instrumentation（增强，不是基础）


⸻

🥇 Phase 1：最小可用工具（你现在必须完成）

目标非常明确：

OmniScope test.bc
→ 输出 JSON issue


⸻

🎯 1.1 核心 Pipeline（必须先做）

目录结构建议👇

src/
  pipeline/
    pipeline.zig        ← 总调度
    loader.zig          ← IR/BC 加载
    static.zig          ← 静态分析入口
  analysis/
    ffi_boundary.zig    ← 你的第一个 pass（重点）
  diag/
    issue.zig           ← 核心数据结构
  output/
    json.zig            ← 最简单输出


⸻

🎯 1.2 数据模型（必须先稳定）

pub const Issue = struct {
    kind: Kind,
    message: []const u8,
    location: Location,
};

pub const Kind = enum {
    ffi_unsafe_call,
    ffi_missing_check,
    ffi_type_mismatch,
};

pub const Location = struct {
    function: []const u8,
    file: []const u8,
    line: u32,
};

👉 关键原则：
	•	不要一开始搞复杂（trace / graph / lifetime）
	•	先能表达问题

⸻

🎯 1.3 第一个“有价值”的分析（很关键）

你不要写泛分析，直接打你的定位：

FFI 边界检测

⸻

✅ Pass #1：识别 FFI 调用点

检测：

call i32 @printf(...)
call ptr @malloc(...)
call void @external_func(...)

规则：
	•	declare 的函数 = 外部函数（FFI）
	•	标记所有 callsite

⸻

✅ 输出：

{
  "issues": [
    {
      "kind": "ffi_unsafe_call",
      "message": "Call to external function without safety validation",
      "function": "main"
    }
  ]
}

👉 这一步就已经有产品价值了

⸻

🎯 1.4 第二个 pass（立刻加）

✅ Pass #2：未检查返回值（超高价值）

检测：

ptr = malloc(...)

但没有：

if (ptr == NULL)

👉 这是 FFI 最典型 bug

⸻

🎯 1.5 输出（先别碰 SARIF）

先做：

output/json.zig

简单 print：

{ "issues": [...] }

👉 SARIF 放后面（否则你会被 schema 拖死）

⸻

🥈 Phase 2：FFI 深度分析（你的护城河）

这才是 OmniScope 真正的价值。

⸻

🎯 2.1 FFI 边界模型（核心突破点）

你要建立：

[ Language A ] → C ABI → [ Language B ]

比如：
	•	Rust → C
	•	Zig → C
	•	Swift → C

⸻

🎯 2.2 类型一致性检查（很重要）

检测：

// C side
int foo(int*);

// Rust side
extern "C" fn foo(ptr: *const i32)

👉 mismatch：
	•	const vs mut
	•	pointer depth
	•	struct layout

⸻

🎯 2.3 Ownership / Lifetime（开始有深度）

检测：
	•	谁分配？
	•	谁释放？
	•	是否跨语言释放？

典型 bug：

Rust alloc → C free ❌


⸻

🎯 2.4 ABI 规则检查

比如：
	•	struct padding
	•	alignment
	•	calling convention

⸻

🎯 2.5 引入 “FFI Summary”

每个函数：

pub const FFISummary = struct {
    params: []Type,
    returns: Type,
    ownership: Ownership,
};

👉 后面所有分析基于这个

⸻

🥉 Phase 3：Runtime / Instrumentation（增强）

注意：

❗ 这不是核心，是加分项

⸻

🎯 3.1 插桩（instrumentation）

在 IR 中插入：

call @__omniscope_trace(...)


⸻

🎯 3.2 runtime collector

收集：
	•	allocation
	•	free
	•	pointer flow

⸻

🎯 3.3 static + runtime merge

静态推断
   +
运行时验证

👉 提高准确率（减少 false positive）

⸻

🚧 你现在不该做的（我直接帮你砍掉）

❌ plugin 系统

现在做 = 100% 过度设计

⸻

❌ runtime 优先

你现在连 static pipeline 都没跑通

⸻

❌ SARIF 优先

会拖慢你 2–3 倍开发速度

⸻

❌ 全 pass 框架

你现在只需要：

fn run(module) []Issue


⸻

🧠 关键战略（很重要）

你这个项目要避免一个坑：

❌ “通用静态分析工具”

你应该是：

✅ FFI 安全专家工具

⸻

🎯 你的差异化（帮你总结清楚）

现有工具：

工具	能力
ASan	内存错误
Valgrind	runtime
Clang SA	通用分析
Miri	Rust 内存


⸻

👉 你的位置：

FFI 边界安全（没人做好的领域）


⸻

🚀 6 周落地路线（现实可执行）

⸻

Week 1
	•	✅ pipeline.run()
	•	✅ IR loader
	•	✅ JSON output

⸻

Week 2
	•	✅ FFI call detection
	•	✅ malloc check

⸻

Week 3
	•	✅ basic dataflow（变量是否检查）
	•	✅ 多函数分析（简单版）

⸻

Week 4
	•	✅ type mismatch（基础）
	•	✅ better diagnostics

⸻

Week 5
	•	✅ 引入 FFI summary
	•	✅ ownership 检测（初版）

⸻

Week 6
	•	✅ 输出 SARIF
	•	✅ CLI polish
	•	✅ demo + README

⸻

🧾 最后一句话（定方向用）

OmniScope 的核心不是“分析 LLVM IR”，
而是：
让跨语言边界变得可验证、可推理、可诊断。

⸻
