核心围绕三件事：

1️⃣ 最小 libc 语义模型
2️⃣ 基于“真实可追踪数据”的分析方法
3️⃣ 降噪但不丢信号

而且严格遵守你说的：

大道至简 + 只基于真实能追踪到的事实

⸻

要求：编码风格必须按照./plan/rules.md 中的规则


📘 OmniScope FFI 语义分析最小设计（MVP）

⸻

🎯 0. 设计原则（必须统一认知）

1. 不恢复语言（Rust/C/Zig） ❌
2. 不做猜测（heuristic minimal） ⚠️
3. 只基于 IR 中“可验证事实” ✅
4. 所有结论必须可追溯（traceable） ✅


⸻

🧱 1. 核心抽象：语义边界（Semantic Boundary）

定义

当调用目标函数没有 IR body（declare）时 → 语义不可见 → FFI 边界


⸻

数据结构

pub const Visibility = enum {
    visible,   // define（可分析）
    opaque,    // declare（不可分析）
};

pub const Function = struct {
    name: []const u8,
    visibility: Visibility,
};


⸻

判定

fn isOpaque(fn: LLVMValueRef) bool {
    return LLVMCountBasicBlocks(fn) == 0;
}


⸻

🧠 2. 最小 libc 语义模型（核心）

👉 不做复杂建模，只描述最关键语义

⸻

2.1 统一语义结构

pub const Ownership = enum {
    none,
    returns_owned,   // malloc
    consumes,        // free
};

pub const Nullability = enum {
    unknown,
    nullable,
    nonnull,
};

pub const FFISemantics = struct {
    name: []const u8,

    // 返回值语义
    returns_ptr: bool,
    returns_nullability: Nullability,
    ownership: Ownership,

    // 参数语义
    consumes_arg_index: ?u32, // free(ptr)
};


⸻

2.2 最小 libc 表（MVP）

const libc_semantics = [_]FFISemantics{
    .{
        .name = "malloc",
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
    .{
        .name = "calloc",
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
    .{
        .name = "realloc",
        .returns_ptr = true,
        .returns_nullability = .nullable,
        .ownership = .returns_owned,
        .consumes_arg_index = null,
    },
    .{
        .name = "free",
        .returns_ptr = false,
        .returns_nullability = .unknown,
        .ownership = .consumes,
        .consumes_arg_index = 0,
    },
    .{
        .name = "strcpy",
        .returns_ptr = true,
        .returns_nullability = .nonnull,
        .ownership = .none,
        .consumes_arg_index = null,
    },
};


⸻

🔍 3. 核心分析：基于“真实数据流”（不是猜）

⸻

🧩 3.1 值追踪模型（最小版）

pub const ValueOrigin = enum {
    unknown,
    from_malloc,
    from_param,
    from_global,
};


⸻

构建方式（只用 IR 事实）

malloc → 标记为 from_malloc
函数参数 → from_param
global → from_global
其他 → unknown


⸻

🧩 3.2 使用点分析（谁用的谁）

你要回答的问题：

👉 “这个指针从哪来，被谁用，是否违反规则？”

⸻

示例：malloc

%p = call ptr @malloc(...)
call void @foo(%p)

你可以追踪：

p → from_malloc


⸻

示例：free

call void @free(%p)

检查：

p 是否来自 from_malloc？


⸻

⚠️ 4. 核心检测规则（只做高价值）

⸻

✅ Rule 1：malloc 未检查（核心）

IR pattern：

%p = call ptr @malloc(...)
; 没有检查


⸻

检测逻辑：

if (call == malloc) {
    if (!isNullChecked(result)) {
        report("malloc result not checked");
    }
}


⸻

isNullChecked（最小实现）

只检查：

icmp eq %p, null


⸻

⸻

✅ Rule 2：free 非 malloc 来源

if (call == free) {
    if (arg.origin != from_malloc) {
        report("free on non-malloc pointer");
    }
}


⸻

⸻

✅ Rule 3：double free（可选）

同一个 SSA value 被 free 两次


⸻

⸻

✅ Rule 4：FFI 未知函数使用 pointer（重点）

call void @unknown(ptr %p)

如果：

p 是 from_malloc 且未检查 / 未保护

👉 报：

pointer passed into unknown FFI without validation


⸻

🔇 5. 降噪策略（不丢信号）

⸻

🎯 原则

不删除信息
只减少“无意义路径”


⸻

✅ 策略 1：只分析 pointer

if (!isPointerType(value)) skip;

👉 去掉 70% 噪声

⸻

✅ 策略 2：只分析 external call

if (!isOpaque(callee)) skip;


⸻

✅ 策略 3：函数分类（轻量）

switch (classify(name)) {
    modeled => 强规则
    unknown => 保守规则
    low_risk => 忽略
}


⸻

✅ low risk（最小）

printf / puts / fprintf

👉 直接跳过

⸻

🔗 6. Traceable 输出（你这个项目的灵魂）

⸻

输出必须包含“路径”

{
  "issue": "free on non-malloc pointer",
  "trace": [
    "ptr from param",
    "passed to free"
  ]
}


⸻

或：

{
  "issue": "malloc not checked",
  "trace": [
    "malloc at line X",
    "used without null check"
  ]
}


⸻

👉 必须做到：用户能复现你的推理路径

⸻

🧪 7. MVP Pipeline

load bc
  ↓
scan functions
  ↓
identify FFI boundary（declare）
  ↓
apply libc semantics
  ↓
track pointer origin（最小）
  ↓
apply rules
  ↓
emit JSON（带 trace）


⸻

🚀 8. 第一阶段完成标准

你只要做到：
	•	✅ 能识别 malloc/free
	•	✅ 能追踪 pointer 来源（简单版）
	•	✅ 能输出 2 类 issue：
	•	malloc 未检查
	•	free 非法
	•	✅ 输出带 trace

👉 就已经是一个有实际价值的工具

⸻

🧠 最后帮你定一句“设计信条”

不做语言识别
不做复杂推断
只基于 IR 中“真实存在的因果关系”
构建最小但可信的 FFI 安全分析

⸻

