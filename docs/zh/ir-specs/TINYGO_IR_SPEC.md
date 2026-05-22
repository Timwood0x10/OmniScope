# TinyGo LLVM IR 规范：编译器保留 vs 用户定义

**源码**: `~/code/researcher/tinygo` (main 分支)
**日期**: 2026-05-22
**目的**: 为静态分析工具（如 OmniScope）区分编译器保留的 IR 模式和用户定义的符号

---

## 1. 符号命名规则

### 1.1 用户定义的符号

| 模式 | IR 符号示例 | 源码证据 |
|------|------------|----------|
| 默认 Go 函数 | `main.foo`, `math.Sqrt` | `compiler/symbol.go:321` — `linkName: f.RelString(nil)` |
| `//export <name>` | `myFunc`（用户自选） | `compiler/symbol.go:387` — `info.linkName = parts[1]` |
| `//go:linkname` | `<target>`（用户自选） | `compiler/symbol.go:454` — `info.linkName = parts[2]` |
| `//go:extern <name>` 全局变量 | `<name>`（用户自选） | `compiler/symbol.go:761` — `info.linkName = parts[1]` |

### 1.2 编译器保留的符号

| 前缀/模式 | 示例 | 源码证据 |
|-----------|------|----------|
| `runtime.*` | `runtime.alloc`, `runtime._panic` | `compiler/calls.go:42-56` — `createRuntimeCall()` |
| `internal/task.*` | `internal/task.start` | `compiler/goroutine.go:121` |
| `_Cgo_*` | `_Cgo_foo`（Go 侧别名） | `cgo/libclang.go:222` — `Name: "_Cgo_" + name` |
| `_Cgo_static_<hash>_*` | `_Cgo_static_a1b2c3_foo` | `cgo/libclang.go:232` — 文件路径的 SHA256 |
| `_Cgo_*` + `//export <c_name>` | LLVM IR = 原始 C 名 | `cgo/libclang.go:250-256` |
| `reflect/types.type:*` | 类型描述符全局变量 | `transform/interface-lowering.go:153` |
| `gc.stackobject`（alloca 名） | 函数级 GC 栈槽 | `transform/gc.go:228` |
| `stackalloc`（alloca 名） | 逃逸分析提升的堆→栈分配 | `transform/allocs.go:118` |

### 1.3 CGo 特有模式

| 模式 | 示例 | 源码证据 |
|------|------|----------|
| `_Cgo_<c_func>` | `_Cgo_printf` | `cgo/libclang.go:222` |
| `_Cgo_<c_func>$funcaddr` | `_Cgo_printf$funcaddr` | `cgo/cgo.go:1262` — 函数指针引用 |
| `unionfield_<name>` | `unionfield_d` | `cgo/cgo.go:720` |
| `bitfield_<name>` / `set_bitfield_<name>` | `bitfield_b` | `cgo/cgo.go:835,988` |
| `struct_<name>` / `union_<name>` / `enum_<name>` | `struct_foo`, `enum_color` | `cgo/libclang.go:859-867` |
| `_Ctype_<prefix>__<N>` | `_Ctype_struct__0` | `cgo/libclang.go:869-873` — 匿名记录体 |
| `__bitfield_<N>` | `__bitfield_1` | `cgo/libclang.go:1094` — 位域存储 |
| `$union`（字段名） | 结构体字段 | `cgo/cgo.go:621` |
| `$<N>`（参数名） | `$0`, `$1` | `cgo/libclang.go:290-291` — 匿名参数 |
| `_type`（重命名字段） | C 结构体 `type` → `_type` | `cgo/cgo.go:1467-1487` |

---

## 2. 运行时函数（IR 中以 `@runtime.*` 调用形式出现）

### 2.1 内存分配

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.alloc` | `(size, layout) → ptr` | `compiler/compiler.go:2179`, `src/runtime/gc_leaking.go:35` |
| `runtime.free` | `(ptr)` | `src/runtime/gc_blocks.go:503` |
| `runtime.realloc` | `(ptr, size) → ptr` | `src/runtime/gc_blocks.go:481` |

### 2.2 GC / 指针追踪

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.trackPointer` | `(ptr, stackChain)` | `compiler/gc.go:84` |

### 2.3 Panic / Recover / Defer

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime._panic` | `(message)` | `compiler/compiler.go:1548`, `src/runtime/panic.go:54` |
| `runtime._recover` | `(useParentFrame)` | `compiler/compiler.go:1891`, `src/runtime/panic.go:150` |
| `runtime.setupDeferFrame` | `(frame, jumpSP)` | `compiler/defer.go:77`, `src/runtime/panic.go:117` |
| `runtime.destroyDeferFrame` | `(frame)` | `compiler/compiler.go:1552`, `src/runtime/panic.go:137` |
| `tinygo_longjmp` | `(frame)` | `src/runtime/panic.go:19` — `//export tinygo_longjmp` |
| `runtime.nilPanic` | `()` | `compiler/asserts.go:202`, `src/runtime/panic.go:183` |
| `runtime.nilMapPanic` | `()` | `src/runtime/panic.go:188` |
| `runtime.lookupPanic` | `()` | `compiler/asserts.go:34`, `src/runtime/panic.go:193` |
| `runtime.slicePanic` | `()` | `compiler/asserts.go:77`, `src/runtime/panic.go:198` |
| `runtime.sliceToArrayPointerPanic` | `()` | `compiler/asserts.go:89`, `src/runtime/panic.go:204` |
| `runtime.unsafeSlicePanic` | `()` | `compiler/asserts.go:121`, `src/runtime/panic.go:211` |
| `runtime.chanMakePanic` | `()` | `compiler/asserts.go:158`, `src/runtime/panic.go:216` |
| `runtime.negativeShiftPanic` | `()` | `compiler/asserts.go:215`, `src/runtime/panic.go:222` |
| `runtime.divideByZeroPanic` | `()` | `compiler/asserts.go:228`, `src/runtime/panic.go:226` |
| `runtime.blockingPanic` | `()` | `src/runtime/panic.go:230` |
| `runtime.runtimePanic` | `(msg)` | `src/runtime/panic.go:85` |

### 2.4 Channel 操作

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.chanMake` | `(elemSize, bufSize)` | `compiler/channel.go:26` |
| `runtime.chanSend` | `(ch, elem, blocked)` | `compiler/channel.go:51` |
| `runtime.chanRecv` | `(ch, elem, blocked)` | `compiler/channel.go:82` |
| `runtime.chanClose` | `(ch)` | `compiler/channel.go:104` |
| `runtime.chanSelect` | `(...)` | `compiler/channel.go:225` |
| `runtime.chanCap` | `(ch)` | `compiler/compiler.go:1621` |
| `runtime.chanLen` | `(ch)` | `compiler/compiler.go:1739` |

### 2.5 Map / HashMap 操作

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.hashmapMakeGeneric` | `(...)` | `compiler/map.go:54` |
| `runtime.hashmapStringGet` | `(m, key, value)` | `compiler/map.go:97` |
| `runtime.hashmapStringSet` | `(m, key, value)` | `compiler/map.go:136` |
| `runtime.hashmapStringDelete` | `(m, key)` | `compiler/map.go:159` |
| `runtime.hashmapClear` | `(m)` | `compiler/map.go:178` |
| `runtime.hashmapNext` | `(...)` | `compiler/map.go:197` |
| `runtime.hashmapLen` | `(m)` | `compiler/compiler.go:1741` |
| `runtime.hash32` | `(ptr, seed, len)` | `compiler/map.go:420` |
| `runtime.memequal` | `(a, b, size)` | `compiler/map.go:544` |

### 2.6 字符串操作

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.stringConcat` | `(...)` | `compiler/compiler.go:2908` |
| `runtime.stringEqual` | `(a, b)` | `compiler/compiler.go:2910` |
| `runtime.stringLess` | `(a, b)` | `compiler/compiler.go:2915` |
| `runtime.stringToBytes` | `(s)` | `compiler/compiler.go:3382` |
| `runtime.stringFromBytes` | `(b)` | `compiler/compiler.go:3227` |
| `runtime.stringToRunes` | `(s)` | `compiler/compiler.go:3384` |
| `runtime.stringFromRunes` | `(r)` | `compiler/compiler.go:3229` |
| `runtime.stringFromUnicode` | `(rune)` | `compiler/compiler.go:3223` |
| `runtime.stringNext` | `(s, i)` | `compiler/compiler.go:2440` |

### 2.7 Interface 操作

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.typeAssert` | `(actualType, assertedType)` | `compiler/interface.go:783` |
| `runtime.interfaceTypeAssert` | `(commaOk)` | `compiler/interface.go:831` |
| `runtime.interfaceEqual` | `(a, b)` | `compiler/compiler.go:2960` |

### 2.8 Slice / Complex / Print

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.sliceAppend` | `(...)` | `compiler/compiler.go:1607` |
| `runtime.complex64div` | `(...)` | `compiler/compiler.go:2875` |
| `runtime.complex128div` | `(...)` | `compiler/compiler.go:2877` |
| `runtime.printlock` | `()` | `compiler/compiler.go:1818` |
| `runtime.printunlock` | `()` | `compiler/compiler.go:1879` |
| `runtime.printstring` | `(s)` | `compiler/compiler.go:1828` |
| `runtime.printnl` | `()` | `compiler/compiler.go:1877` |
| `runtime.printitf` | `(itf)` | `compiler/compiler.go:1860` |

### 2.9 调度器 / 任务

| IR 符号 | 参数 | 源码证据 |
|---------|------|----------|
| `runtime.deadlock` | `()` | `src/runtime/scheduler_cooperative.go:51` |
| `runtime.Goexit` | `()` | `src/runtime/scheduler.go:56` |
| `internal/task.start` | `(fn, args, stackSize, stackAlloc)` | `compiler/goroutine.go:121` |
| `internal/task.getGoroutineStackSize` | `(fn, args)` | `compiler/goroutine.go:111` |

---

## 3. 编译器内联替换（替换为 LLVM 内置函数）

这些在最终 IR 中**不会**以 `@runtime.*` 调用形式出现。

| Go 函数 | LLVM IR | 源码证据 |
|---------|---------|----------|
| `runtime.memcpy` / `runtime.memmove` | `@llvm.memcpy.*` | `compiler/intrinsics.go:22` |
| `runtime.memzero` | `@llvm.memset.*` | `compiler/intrinsics.go:25` |
| `runtime.stacksave` | `@llvm.stacksave` | `compiler/intrinsics.go:26` |
| `runtime.KeepAlive` | 内联汇编 `"" : "r"(ptr)` | `compiler/intrinsics.go:28` |
| `runtime/volatile.Load*` | volatile load | `compiler/intrinsics.go:32` |
| `runtime/volatile.Store*` | volatile store | `compiler/intrinsics.go:34` |
| `sync/atomic.*` | `atomicrmw` / `cmpxchg` / `fence` | `compiler/intrinsics.go:36` |
| `math.Ceil` / `Floor` / `Sqrt` 等 | `@llvm.ceil.f64` 等 | `compiler/intrinsics.go:169-175` |
| `math/bits.LeadingZeros*` | `@llvm.ctlz.*` | `compiler/intrinsics.go:239` |
| `math/bits.TrailingZeros*` | `@llvm.cttz.*` | `compiler/intrinsics.go:240` |
| `math/bits.OnesCount*` | `@llvm.ctpop.*` | `compiler/intrinsics.go:286` |
| `math/bits.Reverse*` | `@llvm.bitreverse.*` | `compiler/intrinsics.go:300` |
| `math/bits.ReverseBytes*` | `@llvm.bswap.*` | `compiler/intrinsics.go:306` |
| `math/bits.RotateLeft*` | `@llvm.fshl.*` | `compiler/intrinsics.go:319` |

---

## 4. Transform Pass 引入的 IR 模式

| Pass | IR 模式 | 源码证据 |
|------|---------|----------|
| **MakeGCStackSlots** | `%gc.stackobject = alloca {parent, count, ptr0, ptr1, ...}` | `transform/gc.go:228` |
| **OptimizeAllocs** | `%stackalloc = alloca [N x i8]`（替换 `runtime.alloc`） | `transform/allocs.go:118` |
| **LowerInterfaces** | `icmp` 分发链（接口调用函数内） | `transform/interface-lowering.go:516-604` |
| **LowerInterrupts** | 直接 handler 调用（替换 `runtime/interrupt.callHandlers`） | `transform/interrupt.go:89-98` |
| **CreateStackSizeLoads** | `@internal/task.stackSizes` 全局变量，在 `.tinygo_stacksizes` section | `transform/stacksize.go:49` |
| **OptimizeStringToBytes** | 消除 `runtime.stringToBytes` 调用 | `transform/rtcalls.go:17` |
| **OptimizeStringEqual** | 用 `icmp` 替换 `runtime.stringEqual` | `transform/rtcalls.go:78` |
| **OptimizeMaps** | 消除死代码 `runtime.hashmap*` 调用 | `transform/maps.go:12-17` |

---

## 5. ABI 差异（导出函数 vs 内部函数）

| 属性 | 导出函数 | 内部函数 |
|------|----------|----------|
| 额外 context 参数 | 无 | 有（追加 `ptr`） |
| 源码 | `compiler/symbol.go:102-104` | 同上 |

内部 Go 函数的签名为 `f(args..., context ptr)`，而导出函数（通过 `//export`、CGo、WASM）省略 context 参数。

---

## 6. 静态分析关键要点

### 需要分析的用户代码：
- 匹配 `package.FunctionName` 模式的函数（如 `main.foo`、`crypto/sha256.Sum`）
- 带 `//export` 名称的函数（用户自选，无前缀）
- 通过 CGo 调用的 C 函数（在 IR 中以原始 C 名出现）

### 需要过滤/跳过的编译器运行时：
- 以 `runtime.` 开头的任何内容（约 65 个函数）
- 以 `internal/task.` 开头的任何内容
- 以 `_Cgo_` 开头的任何内容（CGo 桥接）
- 以 `reflect/types.type:` 开头的任何内容
- LLVM 内置函数（`@llvm.*`）
- 合成 alloca 名（`gc.stackobject`、`stackalloc`）

### CGo 桥接（分类为 FFI 边界）：
- 原始 C 函数名（通过 CGo 生成的 stub 中的 `//export`）
- `_Cgo_static_<hash>_<name>`（静态 C 函数）
- `_Cgo_<name>$funcaddr`（C 函数指针引用）
- `runtime.cgo_CString`、`runtime.cgo_GoString` 等（CGo 字符串转换）

---

## 7. 完整 IR 函数属性映射

源码: `compiler/symbol.go:155-243`

| IR 符号 | 属性 | 源码行 |
|---------|------|--------|
| `abort` | `noreturn` | 159 |
| `runtime.alloc` | `noalias`, `nonnull`, `allockind(alloc)`, `allocsize(0)` | 167-181 |
| `runtime.sliceAppend` | 参数 2: `nocapture`, `readonly` | 183-186 |
| `runtime.stringFromBytes` | 参数 1: `nocapture`, `readonly` | 187-189 |
| `runtime.stringFromRunes` | 参数 1: `nocapture`, `readonly` | 190-192 |
| `runtime.hashmapSet` | 参数 2,3: `nocapture` | 193-199 |
| `runtime.hashmapGet` | 参数 2,3: `nocapture` | 200-204 |
| `runtime.hashmapDelete` | 参数 2: `nocapture` | 205-207 |
| `runtime.trackPointer` | 参数 1: `nocapture`, `readonly` | 219-223 |
