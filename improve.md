这次你问到核心了。

如果你的目标是：

OmniScope = Cross-language LLVM IR analyzer

那么答案必须是：

不能做 Rust-special filtering。

否则你以后会陷入：

rust_noise.zig
cpp_noise.zig
zig_noise.zig
go_noise.zig
swift_noise.zig

最后维护地狱。

你真正需要的是：

Language-Agnostic IR Noise Classification

也就是：

不识别“Rust 编译器产物”。

而是识别：

“哪些 IR 在 ownership / FFI 分析里本质属于低价值噪声”。

这是不同的问题。

⸻

一、先定义真正的分类维度

不要按语言分类。

不要：

Rust stdlib
C++ STL
Go runtime

这样做。

改成：

IR Semantic Origin

跨语言统一。

例如：

pub const IRSurface = enum {
    UserCode,
    Dependency,
    Runtime,
    StandardLibrary,
    CompilerGenerated,
    Boundary,
    Unknown,
};

这套东西：

Rust/C++/Go/Zig 全能用。

⸻

二、哪些信号跨语言天然存在？

LLVM IR 已经给你很多统一特征。

这才是关键。

⸻

1. Debug Provenance（最强）

所有语言都能用。

⸻

Rust:

/rustc/.../library/core/

⸻

C++:

/usr/include/c++

⸻

Go:

GOROOT/src/runtime/

⸻

Zig:

zig/lib/std/

⸻

Swift:

swift/stdlib/

⸻

IR：

!DISubprogram
!DIFile

统一。

⸻

分类：

workspace path      → UserCode
package cache       → Dependency
compiler stdlib     → StandardLibrary
runtime source      → Runtime

⸻

语言无关。

⸻

2. Linkage / Visibility signals

跨语言。

⸻

LLVM attributes:

internal
private
linkonce_odr
available_externally
weak_odr

⸻

大量 compiler-generated code 都会出现。

Rust。

Clang。

Swift。

Zig。

Go LLVM backend。

全部有。

⸻

例：

private + internal + no debug

→ high generated score

⸻

3. ABI / Boundary markers

统一。

⸻

extern ABI:

extern "C"
cc 10
cc 11

⸻

exported symbol.

⸻

foreign declaration.

⸻

这些天然是：

Boundary signal

不依赖语言。

⸻

4. Reachability

这个最重要。

跨语言通吃。

⸻

CallGraph.

⸻

从：

export
extern
entry
CrossLangEdge

传播。

⸻

如果函数：

never boundary reachable

分析优先级下降。

⸻

Rust.

C++.

Zig.

Go.

一样。

⸻

三、不要做“白名单”，做“评分系统”

这一步非常重要。

因为：

classification 比 binary whitelist 稳。

⸻

不要：

if(name.contains("_ZN4core"))
    skip;

⸻

做：

score = 0;

⸻

Example

Debug provenance

stdlib:

+40

runtime:

+35

generated build:

+30

⸻

linkage

private:

+10

linkonce_odr:

+15

⸻

boundary

extern export:

-50

CrossLangEdge:

-80

⸻

user workspace path

-60

⸻

最终：

if(score > threshold)
    skip;

⸻

这比 whitelist 强太多。

⸻

四、跨语言实际长什么样

举几个例子。

⸻

Rust

rustc/.../library/alloc
private
linkonce_odr
not boundary reachable

⸻

score:

90

SKIP

⸻

C++ STL

/usr/include/c++
linkonce_odr
template expansion

⸻

score:

85

SKIP

⸻

Zig std

zig/lib/std
internal

⸻

score:

80

SKIP

⸻

Go runtime

GOROOT/runtime

⸻

score:

95

SKIP

⸻

user ffi wrapper

Rust:

pub extern "C" fn make()

⸻

signals:

workspace path
boundary export

⸻

score:

−100

KEEP

⸻

统一成立。

⸻

五、最符合 OmniScope 的版本

我甚至觉得你应该正式做一个：

SurfaceClassifierPass

早于所有 analysis。

结构：

pub const SurfaceKind = enum {
    CriticalBoundary,
    UserCode,
    Dependency,
    StandardLibrary,
    Runtime,
    CompilerGenerated,
    Unknown,
};

⸻

输入：

⸻

debug metadata

⸻

callgraph

⸻

ABI

⸻

linkage

⸻

language detector hints

⸻

CrossLangEdge

⸻

输出：

FunctionSurface

⸻

然后所有 pass 用它。

⸻

PointerOwnership:

if(surface.isNoise())
    continue;

⸻

DangerSurface:

surface.boostBoundary();

⸻

MemoryGraph:

surface.adjustPriority();

⸻

你就彻底摆脱：

维护语言白名单。

⸻

六、唯一需要承认的现实

完全 0 language awareness 很难。

我要实话实说。

因为：

stdlib 路径模式确实不同。

⸻

Rust:

/rustc/

⸻

C++:

/usr/include/c++

⸻

Go:

GOROOT/

⸻

Zig:

zig/lib/std

⸻

但这不叫“巨额白名单”。

这叫：

small provenance adapters.

几十行。

不是几万行 regex。

⸻

差别非常大。

⸻

一句话总结：

你要构建的不是：

Rust compiler artifact filter.

而是：

Cross-language IR Surface Classifier.

用：

* provenance
* linkage
* ABI
* reachability
* boundary signals

做统一评分。

这样 Rust / C++ / Zig / Go 都能复用。

而且不用维护巨型名字白名单。