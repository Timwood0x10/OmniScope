我明白你的真实目标了。

你现在其实不是在解决：

“如何检测 FFI crate”

你是在解决一个更底层的问题：

Rust LLVM IR 中，如何通用识别 compiler/runtime generated noise，并在 pipeline 最早阶段剪枝。

这个问题非常合理。

因为你说的规模是对的。

真实 Rust LLVM IR：

20M IR

里面通常：

core
alloc
std
panic runtime
drop glue
monomorphized iterator chains
serde derives
fmt machinery
compiler shims
lang items

可能占绝大部分。

如果不做早期 pruning：

后面的：

MemoryGraph
DangerSurface
Ownership
CrossLangEdge

都会被拖死。

所以：

必须 Early Skip。

这个方向没问题。

但重点来了：

⸻

你想要：

不靠 regex
不靠无限 whitelist

这是对的。

因为：

_ZN4core
_ZN5alloc
_ZN3std

最终一定变成：

tokio
serde
ring
cranelift
wasmtime
smallvec
hashbrown
...

无限维护。

不可做。

⸻

真正可扩展的做法：Origin-Based Classification

不是名字。

是：

编译来源（origin）分类。

LLVM IR 已经有线索。

⸻

方案1（我认为最靠谱）

Debug Origin Filtering

利用：

LLVM DISubprogram。

不是 DWARF 后处理。

是 IR metadata。

⸻

IR 里通常有：

define void @_ZN... !dbg !123

对应：

!123 = distinct !DISubprogram(
    file: !456
)

file:

/home/user/project/src/main.rs

或者：

/home/user/.cargo/registry/...

或者：

/rustc/<hash>/library/core/src/...

⸻

然后做：

SourceOrigin Classification

⸻

USER_CODE

workspace/src

⸻

STDLIB

rustc/.../library/

⸻

DEPENDENCY

.cargo/registry

⸻

BUILD_GENERATED

target/build

⸻

UNKNOWN

missing dbg.

⸻

得到：

FunctionOrigin

⸻

然后：

Rust pipeline 最开始：

switch(origin) {
    .USER_CODE => KEEP
    .STDLIB => SKIP
    .DEPENDENCY => LOWER_PRIORITY
    .BUILD_GENERATED => SKIP
}

⸻

这不是 whitelist。

也不是 regex 函数名。

这是：

provenance filtering.

非常稳。

⸻

而且语言无关。

C++：

STL。

Go：

generated bindings。

Zig：

std.

都能复用。

⸻

方案2（更 LLVM-native）

Linkage + COMDAT + internality heuristic

很多 compiler noise 有特征。

例如：

⸻

drop glue

panic helpers

monomorphized internals

⸻

通常：

internal
private
linkonce_odr
available_externally

⸻

你可以建立：

CompilerArtifactScore.

⸻

例：

internal + linkonce_odr + no user dbg
→ likely compiler artifact

⸻

这不是100%。

但能砍很多。

⸻

方案3（我觉得最符合你思路）

User-Reachable Analysis

这个可能最接近你想要的。

⸻

先定义：

User Root Functions

Rust 用户入口。

例如：

⸻

public API

⸻

extern exports

⸻

workspace source files

⸻

main/lib user module

⸻

然后：

CallGraph forward walk.

⸻

保留：

reachable_from_user

⸻

剪掉：

never touched compiler runtime islands

⸻

效果非常强。

⸻

比如：

保留：

wasmtime::runtime::*

⸻

丢掉：

core::fmt::Formatter
alloc::raw_vec
panic_unwind

⸻

无需名字。

⸻

为什么我不建议“只看用户函数”

这里有个坑。

你说：

只关心用户自定义函数。

这句话需要小心。

因为很多真实 ownership bug：

发生在 dependency crate。

举例：

⸻

用户：

myproj

依赖：

ring
openssl-sys
libsqlite3-sys

⸻

FFI boundary 很可能在：

*-sys crates

不是用户 crate。

⸻

如果：

workspace-only

过滤。

你会漏很多。

⸻

所以更安全的是：

⸻

KEEP：

USER_CODE
FFI_RELEVANT_DEPENDENCY
EXTERN_EXPORTS
BOUNDARY_REACHABLE

⸻

SKIP：

STDLIB
PANIC_RUNTIME
PURE_INTERNAL_GENERATED

⸻

这才比较稳。

⸻

我给你的最终建议

不要做：

名字过滤

不要做：

crate whitelist

不要做：

extern-scan-per-function

⸻

做一个统一系统：

Semantic Origin Filter

结构大概：

pub const FunctionOrigin = enum {
    user,
    dependency,
    stdlib,
    generated,
    runtime,
    unknown,
};

来源：

⸻

debug metadata

⸻

module path

⸻

linkage

⸻

ABI markers

⸻

callgraph reachability

⸻

然后：

pipeline very early:

if (lang == .rust) {
    if (origin == .stdlib)
        continue;
    if (origin == .generated)
        continue;
}

⸻

这就是你要的：

20M IR 开头直接砍掉 10M。

而且：

不靠巨量白名单。

不靠 crate 名。

不靠维护 regex。

⸻

我甚至觉得，这个东西可以成为 OmniScope 一个正式组件：

OriginClassifierPass

和：

LanguageDetector
DangerSurface
MemoryGraph

同级。

因为这不是 noise hack。

这是：

analysis scope reduction infrastructure。