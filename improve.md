我觉得这思路比“大一统 MemoryGraph”更适合你当前阶段。

而且它有个很大的优点：

不污染 OmniScope 主图。

你其实在描述一种 双图（Dual-Graph）架构。

我帮你整理成一个能落地的设计。

⸻

OmniScope Dual-Graph Architecture

核心思想：

把“Rust 已知安全语义”与“跨语言风险分析”拆开。

不是一个图解决全部。

⸻

结构：

                LLVM IR Module
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
   RustSemanticGraph         CoreMemoryGraph
  (language adapter)        (cross-language)
        │                           │
        │ SAFE / RESOLVED           │ NEED ANALYSIS
        │ FILTERED                  │
        └─────────────┬─────────────┘
                      ▼
             RiskCandidateSet
                      ▼
          PointerOwnershipPass
          DangerSurfacePass
          FFIBoundaryPass

⸻

这个其实非常符合你现在的目标。

因为你真正想做的是：

Rust 原生行为优先“自证安全”。

证明不了，再交给 OmniScope 主引擎。

这和很多工业 analyzer 的思想非常接近。

⸻

1. Graph A — RustSemanticGraph

新目录：

src/
  semantics/
      rust_semantic_graph.zig

⸻

职责：

处理 Rust 原生 ownership 语义。

不是分析漏洞。

只是：

能解释掉多少解释多少。

⸻

输出：

pub const RustSemanticResult = enum {
    resolved_safe,
    resolved_release,
    unresolved,
};

⸻

图节点非常简单。

不要重建完整 MIR。

只做你当前痛点。

⸻

RustSemanticNode

pub const RustSemanticNode = struct {
    value: ValueRef,
    kind: Kind,
    source_lang: Language,
    confidence: u8,
};
pub const Kind = enum {
    box_alloc,
    vec_alloc,
    drop_call,
    drop_glue,
    dealloc,
    nonnull,
    slice,
    text_pointer,
    ownership_transfer,
    unknown,
};

⸻

注意：

这里只处理 Rust semantic artifacts。

不是全局 graph。

⸻

⸻

Example 1

Rust:

Vec::new()
drop(v)

⸻

子图：

VecAlloc
   ↓
Ownership
   ↓
DropGlue
   ↓
RustDealloc

⸻

结论：

resolved_release

⸻

主图：

跳过 leak analysis

⸻

⸻

Example 2

NonNull case.

⸻

Rust:

func_loc_to_pointer()

⸻

子图：

FunctionLoc
     ↓
text slice
     ↓
NonNull

⸻

结论：

resolved_safe

⸻

StackEscape 不进主分析。

⸻

⸻

Example 3

复杂 unsafe FFI.

⸻

找不到：

drop
ownership
source

⸻

结果：

unresolved

⸻

交给主图。

⸻

2. Graph B — CoreMemoryGraph

保留你现有的。

⸻

不要大改。

⸻

职责：

cross-language
alloc/free
alias
escape
ownership
FFI

⸻

只吃：

⸻

未解决对象。

⸻

⸻

过滤逻辑：

if(
rust_semantic_graph.resolve(ptr)
)
{
    skip();
}
else
{
    core_memory_graph.analyze();
}

⸻

非常干净。

⸻

3. RiskCandidateSet

这是关键层。

新增：

src/semantics/risk_candidate_set.zig

⸻

定义：

pub const RiskCandidate = struct {
    value: ValueRef,
    reason: []const u8,
    source: CandidateSource,
};
pub const CandidateSource = enum {
    unresolved_rust,
    ffi_boundary,
    unknown_provenance,
    ownership_conflict,
};

⸻

⸻

流程：

⸻

RustGraph：

⸻

resolved.

↓

suppress.

⸻

unresolved.

↓

candidate.

⸻

CoreGraph：

⸻

继续分析。

⸻

⸻

这样：

你不会：

⸻

分析整个 Rust stdlib.

⸻

只分析：

semantic failure points。

⸻

4. Pass Design

其实你想避免大量 pass。

可以。

只加一层。

⸻

Pipeline：

⸻

当前：

LanguageDetect
CallGraph
MemoryGraph
PointerOwnership

⸻

改：

LanguageDetect
RustSemanticResolver   ← NEW
MemoryGraph
PointerOwnership

⸻

⸻

RustSemanticResolver：

只做：

⸻

scan rust calls.

⸻

resolve obvious ownership.

⸻

mark safe nodes.

⸻

emit unresolved.

⸻

⸻

输出：

写 Context.

⸻

pub const SemanticResolution = struct {
    resolved_safe:
        std.AutoHashMap(ValueRef,bool),
    resolved_release:
        std.AutoHashMap(ValueRef,bool),
    unresolved:
        std.ArrayList(ValueRef),
};

⸻

⸻

CoreMemoryGraph consume。

⸻

5. File Layout

我给你完整目录。

⸻

src/
  semantics/
      memory_graph.zig
      rust_semantic_graph.zig
      risk_candidate_set.zig
  pass/
      analysis/
          rust_semantic_resolver.zig
          pointer_ownership.zig
          danger_surface.zig
  adapters/
      rust/
          rust_patterns.zig

⸻

⸻

rust_patterns.zig

非常小。

⸻

只存：

drop_in_place
Box::drop
Vec::drop
NonNull
slice
__rust_dealloc

⸻

不是 giant whitelist.

⸻

几十条足够。

⸻

6. Resolution Rules

核心。

⸻

Rule 1

Drop chain.

⸻

发现：

drop_in_place
→ dealloc

⸻

输出：

resolved_release

⸻

Rule 2

NonNull text provenance.

⸻

发现：

FunctionLoc
→ text slice
→ NonNull

⸻

输出：

resolved_safe

⸻

Rule 3

Box ownership.

⸻

发现：

Box alloc
→ move
→ drop

⸻

resolved.

⸻

Rule 4

Can’t prove.

⸻

输出：

unresolved

⸻

主图处理。

⸻

7. Why this is better for OmniScope

因为你是：

cross-language analyzer。

不是：

Rust compiler clone。

⸻

如果全塞主图。

MemoryGraph 会越来越 Rust-aware。

最终：

⸻

Rust.

⸻

Go.

⸻

Zig.

⸻

C++.

⸻

semantic soup.

⸻

不好维护。

⸻

Dual graph 更干净。

⸻

Rust adapter 负责：

“这部分 Rust 我能解释掉。”

⸻

OmniScope 负责：

“剩下跨语言风险我来。”

⸻

8. 最终一句话

你的新思路我觉得可以总结成：

Rust Semantic Pre-Resolution Layer

不是替换 MemoryGraph。

不是 MIR。

不是 Miri。

而是：

先让 Rust 自证安全。

解释不掉的，再进入 OmniScope 主分析。

这比直接硬啃 Rust ownership reconstruction 要现实得多。

-------

对，我明白你这次真正想说的了。

你现在已经从：

“给 Rust 单独做图”

开始转向：

“别做 Rust 特化，做一个通用 Semantic Tree / Semantic Resolution Tree。”

我觉得这个方向更好，更符合 OmniScope。

而且比我前面 Dual Graph 还更优雅。

⸻

你的思路本质上是：

不要：

RustGraph
GoGraph
ZigGraph
CppGraph

这种。

因为最后会爆炸。

而是：

Universal Semantic Resolution Tree (SRT)

语言适配器只是往树里注册规则。

⸻

架构：

LLVM IR
   ↓
Semantic Resolver Tree
   ↓
SAFE / RELEASED / RISKY / UNKNOWN
   ↓
Core MemoryGraph
   ↓
PointerOwnership
DangerSurface
FFIBoundary

这其实很漂亮。

⸻

为什么这比 “Rust-only graph” 更好？

因为你的问题根本不是：

“Rust drop 怎么办？”

真正问题是：

LLVM IR 丢失了部分高层语义。

这件事：

Rust 有。

C++ 也有。

Zig 也有。

Go 也有。

⸻

举例。

⸻

Rust:

drop(v)

IR看不出 ownership.

⸻

C++:

unique_ptr::~unique_ptr()

IR一样看不出。

⸻

Zig:

allocator.free(buf)
defer allocator.free(buf)

IR一样可能失真。

⸻

Go:

runtime.cgocall

IR一样有 runtime wrapper.

⸻

所以不要做：

Rust special case

做：

Semantic Resolution Tree

⸻

1. 新核心模型

新增：

src/semantics/semantic_tree.zig

⸻

Node:

pub const SemanticNode = struct {
    value: ValueRef,
    kind: SemanticKind,
    confidence: u8,
};

⸻

Kind：

pub const SemanticKind = enum {
    allocation,
    release,
    ownership_transfer,
    borrow,
    escape,
    provenance,
    runtime_wrapper,
    safe_pattern,
    unknown,
};

⸻

注意。

这里已经不是 Rust。

是通用语义。

⸻

2. Tree Resolution

核心函数。

⸻

pub fn resolve(
    value: ValueRef
) Resolution

⸻

Resolution：

pub const Resolution = enum {
    safe,
    released,
    risky,
    unresolved,
};

⸻

所有语言共用。

⸻

3. Language Adapters 只注册 Pattern

关键来了。

⸻

不要：

RustGraph implementation

⸻

做：

Pattern Registry

⸻

目录：

src/adapters/

⸻

Rust:

adapters/rust/patterns.zig

⸻

注册：

drop_in_place → release
Box::drop → release
NonNull(text) → safe
slice(text) → safe

⸻

C++:

adapters/cpp/patterns.zig

⸻

注册：

unique_ptr::~ → release
shared_ptr::~ → release

⸻

Zig:

adapters/zig/patterns.zig

⸻

注册：

allocator.free → release
defer-free chain → release

⸻

Go:

adapters/go/patterns.zig

⸻

注册：

cgo wrapper → boundary

⸻

这样不会变成巨额白名单。

因为你注册的是：

semantic motifs。

不是 crate names.

⸻

4. Resolution Pipeline

流程。

⸻

当前：

MemoryGraph
    ↓
everything analyzed

⸻

新：

SemanticTree
    ↓
SAFE
RELEASED
UNKNOWN
RISKY

⸻

SAFE：

skip.

⸻

RELEASED：

no leak.

⸻

UNKNOWN：

CoreMemoryGraph.

⸻

RISKY：

high-priority.

⸻

⸻

这就是你说的：

“先排除很多问题。”

完全正确。

⸻

5. 例子

Rust Drop

⸻

发现：

drop_in_place

Pattern:

release

Tree:

Allocation
    ↓
Release

Resolution:

released

⸻

Leak pass：

跳过。

⸻

⸻

Wasmtime NonNull

⸻

发现：

FunctionLoc
→ text slice
→ NonNull

Pattern:

safe provenance

Resolution:

safe

⸻

StackEscape：

跳过。

⸻

⸻

Unsafe extern flow

⸻

找不到 pattern。

⸻

Resolution:

unknown

⸻

进入 CoreMemoryGraph.

⸻

6. 和 MemoryGraph 的关系

不是替代。

是前置层。

⸻

SemanticTree
    ↓
prune solved cases
    ↓
MemoryGraph

⸻

MemoryGraph 负责：

heavy analysis。

⸻

SemanticTree 负责：

cheap semantic elimination。

⸻

这很像：

⸻

compiler fast path.

⸻

fallback analysis.

⸻

⸻

性能也会更好。

⸻

7. 文件设计

我给你最终目录。

⸻

src/
  semantics/
      semantic_tree.zig
      semantic_patterns.zig
      resolution_engine.zig
      memory_graph.zig
  adapters/
      rust/
          patterns.zig
      cpp/
          patterns.zig
      zig/
          patterns.zig
      go/
          patterns.zig
  pass/
      analysis/
          semantic_resolver_pass.zig

⸻

⸻

semantic_resolver_pass:

⸻

scan module.

⸻

apply patterns.

⸻

emit:

ResolutionDB

⸻

MemoryGraph consume.

⸻

8. 为什么这比“单独 Rust 图”更稳

因为未来：

你不会写：

RustNoisePass
CppNoisePass
GoNoisePass
ZigNoisePass

⸻

而是：

统一：

Semantic Resolution Layer

⸻

语言只加 pattern.

⸻

架构稳定。

⸻

一句话总结：

你的新想法我认为应该正式升级成：

Universal Semantic Resolution Tree

用通用语义树先消化“可证明安全/已释放/已解释”的高层模式。

剩余 unresolved case 再交给 OmniScope Core MemoryGraph。

这其实非常符合你“LLVM IR cross-language analyzer”的路线。