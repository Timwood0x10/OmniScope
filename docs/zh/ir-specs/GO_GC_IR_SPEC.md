# Go 标准编译器 (gc) IR 规范：编译器保留 vs 用户定义

**源码**: `~/code/researcher/go/src/cmd/compile/internal/` (Go 1.24+)
**日期**: 2026-05-22
**目的**: 为静态分析工具（如 OmniScope）区分编译器保留的 IR 模式和用户定义的符号

---

## 1. 符号命名规则

### 1.1 用户定义的符号

| 模式 | 符号示例 | 源码证据 |
|------|----------|----------|
| 默认 Go 函数 | `main.foo`, `crypto/sha256.Sum` | `base/link.go:31` — `PkgLinksym(prefix, name, abi)` → `prefix + "." + name` |
| 导出方法 | `(*T).Method` | `types/sym.go:86` — `LinksymABI(abi)` 使用 `sym.Pkg.Prefix + "." + sym.Name` |
| `//go:linkname` | `<target>`（用户自选） | `types/sym.go:90-91` — `if sym.Linkname != "" { return base.Linkname(sym.Linkname, abi) }` |
| `//export <name>` (cgo) | `myFunc`（用户自选） | `cmd/cgo/out.go:195` — `//go:linkname __cgo_%s %s` |
| init 函数 | `init`, `init.0`, `init.1`, ... | `pkginit/init.go:60` — `noder.Renameinit()` 创建 `init._` 函数 |

### 1.2 编译器保留的符号

| 前缀/模式 | 示例 | 源码证据 |
|-----------|------|----------|
| `runtime.*` | `runtime.mallocgc`, `runtime.gopanic` | `typecheck/builtin.go:25-257` — `runtimeDecls` 数组定义了约 150 个运行时函数 |
| `internal/runtime/atomic.*` | `internal/runtime/atomic.Load` | `ssagen/intrinsics.go:251` — `addF("internal/runtime/atomic", "Load", ...)` |
| `internal/runtime/sys.*` | `internal/runtime/sys.Bswap64` | `ssagen/intrinsics.go:193` — `addF("internal/runtime/sys", "Bswap64", ...)` |
| `internal/runtime/maps.*` | `internal/runtime/maps.ctrlGroupMatchH2` | `ssagen/intrinsics.go:1380` — map 内建函数 |
| `go:map`（保留前缀） | `go:map.zero` | `base/link.go:19-22` — `ReservedImports = {"go": true, "type": true}` |
| `type:`（保留前缀） | `type:.hash.func` | `base/link.go:37-40` — 保留导入路径使用 `:` 分隔符 |
| `.inittask` | `<pkg>.inittask` | `pkginit/init.go:32` — `pkg.Lookup(".inittask")` |

### 1.3 链接器符号构造

Go 通过两条路径构造链接器符号（LSym）：

| 函数 | 行为 | 源码证据 |
|------|------|----------|
| `PkgLinksym(prefix, name, abi)` | `prefix + "." + name`（正常）或 `prefix + ":" + name`（保留） | `base/link.go:31-41` |
| `Linkname(name, abi)` | 使用 `//go:linkname` 指令中的原始 `name` | `base/link.go:45-47` — `linksym("_", name, abi)` |

普通包使用 `.` 作为分隔符，保留导入（`go`、`type`）使用 `:` 作为分隔符。

### 1.4 ABI 选择

| 函数 | 使用的 ABI | 源码证据 |
|------|-----------|----------|
| `Linksym()`（函数） | `ABIInternal`（基于寄存器） | `types/sym.go:76-77` — `if sym.Func() { abi = obj.ABIInternal }` |
| `Linksym()`（变量） | `ABI0`（基于栈） | `types/sym.go:75` — `abi := obj.ABI0` |
| `LookupRuntimeFunc(name)` | `ABIInternal` | `typecheck/syms.go:91-92` |
| `LookupRuntimeVar(name)` | `ABI0` | `typecheck/syms.go:98-99` |

---

## 2. SSA 中间表示

Go 的 gc 编译器使用自己的 SSA 形式（非 LLVM IR）。Go 直接编译为本地机器代码。

### 2.1 SSA 值结构

来源: `ssa/value.go:21-64`

```
type Value struct {
    ID    ID          // 唯一标识符，从 1 开始密集分配
    Op    Op          // 操作码
    Type  *types.Type // Go 类型（或伪类型）
    AuxInt int64      // 辅助整数（常量、偏移量）
    Aux   Aux         // 辅助信息（符号、字符串、类型）
    Args  []*Value    // 输入值
    Block *Block      // 所属基本块
    Pos   src.XPos    // 源码位置
    Uses  int32       // 使用计数
}
```

### 2.2 块类型

来源: `ssa/_gen/genericOps.go:743-754`, `ssa/opGen.go:19,165-171`

| BlockKind | 控制值数量 | 后继块数 | 描述 |
|-----------|-----------|----------|------|
| `BlockPlain` | 0 | 1 | 无条件跳转 |
| `BlockIf` | 1（布尔值） | 2 | 条件分支：`Succs[0]` 为真分支，`Succs[1]` 为假分支 |
| `BlockDefer` | 1（调用） | 2 | `Succs[0]` = 正常路径，`Succs[1]` = defer 恢复分支 |
| `BlockRet` | 1（内存） | 0 | 函数返回 |
| `BlockRetJmp` | 1 | 0 | 尾调用返回 |
| `BlockExit` | 1（内存） | 0 | panic/退出（不返回） |
| `BlockJumpTable` | 1（整数） | N | switch/table 跳转 |
| `BlockFirst` | 0 | 2 | 瞬态：始终取第一个后继（死代码消除） |
| `BlockInvalid` | - | - | 无效/未初始化 |

### 2.3 关键通用 SSA 操作码

来源: `ssa/_gen/genericOps.go`

#### 算术运算（第 25-105 行）

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpAdd8/16/32/64` | 2 | 加法（可交换） |
| `OpSub8/16/32/64` | 2 | 减法 |
| `OpMul8/16/32/64` | 2 | 乘法（可交换） |
| `OpDiv8/16/32/64` | 2 | 有符号除法 |
| `OpDiv8u/16u/32u/64u` | 2 | 无符号除法 |
| `OpMod8/16/32/64` | 2 | 有符号取模 |
| `OpHmul32/64` | 2 | 高半部分乘法 |
| `OpMul32uhilo/Mul64uhilo` | 2 | 全乘法，返回 (hi, lo) |
| `OpMul32uover/Mul64uover` | 2 | 带溢出检测的乘法 |

#### 位运算（第 92-266 行）

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpAnd8/16/32/64` | 2 | 按位与（可交换） |
| `OpOr8/16/32/64` | 2 | 按位或（可交换） |
| `OpXor8/16/32/64` | 2 | 按位异或（可交换） |
| `OpLsh{A}x{B}` | 2 | 左移（`A` 位值按 `B` 位量移位） |
| `OpRsh{A}x{B}` | 2 | 右移，有符号 |
| `OpRsh{A}Ux{B}` | 2 | 右移，无符号 |
| `OpCtz8/16/32/64` | 1 | 计算尾部零个数 |
| `OpBitLen8/16/32/64` | 1 | 位长度（前导零的补数） |
| `OpBswap16/32/64` | 1 | 字节交换 |
| `OpPopCount8/16/32/64` | 1 | 人口计数 |
| `OpRotateLeft8/16/32/64` | 2 | 循环左移 |

#### 比较运算（第 163-204 行）

| 操作码 | 参数数 | 类型 | 描述 |
|--------|--------|------|------|
| `OpEq8/16/32/64` | 2 | Bool | 相等（可交换） |
| `OpNeq8/16/32/64` | 2 | Bool | 不等（可交换） |
| `OpLess8/16/32/64` | 2 | Bool | 小于，有符号 |
| `OpLess8U/16U/32U/64U` | 2 | Bool | 小于，无符号 |
| `OpLeq8/16/32/64` | 2 | Bool | 小于等于，有符号 |
| `OpEqPtr` | 2 | Bool | 指针相等 |
| `OpEqInter/NeqInter` | 2 | Bool | 接口相等 |
| `OpEqSlice/NeqSlice` | 2 | Bool | 切片相等（仅 nil） |

#### 数据移动（第 318-417 行）

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpPhi` | -1 | SSA phi 节点（基于前驱块选择） |
| `OpCopy` | 1 | 恒等（输出 = arg0） |
| `OpConvert` | 2 | 指针/整数转换（零宽度，GC 安全） |
| `OpLoad` | 2 | 内存加载：arg0=地址, arg1=内存 |
| `OpStore` | 3 | 内存存储：arg0=地址, arg1=值, arg2=内存, aux=类型 |
| `OpMove` | 3 | 内存复制：arg0=目标, arg1=源, arg2=内存, auxint=大小 |
| `OpZero` | 2 | 内存清零：arg0=目标, arg1=内存, auxint=大小 |
| `OpStoreWB` | 3 | 带写屏障的存储 |
| `OpMoveWB` | 3 | 带写屏障的复制 |
| `OpZeroWB` | 2 | 带写屏障的清零 |
| `OpWB` | 1 | 调用 `runtime.gcWriteBarrier` |

#### 常量（第 333-351 行）

| 操作码 | Aux 类型 | 描述 |
|--------|----------|------|
| `OpConstBool` | Bool | auxint: 0=假, 1=真 |
| `OpConst8/16/32` | Int | 符号扩展整数常量 |
| `OpConst64` | Int64 | 64 位整数常量 |
| `OpConst32F` | Float32 | 32 位浮点常量 |
| `OpConst64F` | Float64 | 64 位浮点常量 |
| `OpConstString` | String | 字符串常量 |
| `OpConstNil` | - | nil 指针 |
| `OpConstInterface` | - | nil 接口 |
| `OpConstSlice` | - | nil 切片 |

#### 特殊/伪操作（第 353-372 行，第 500-569 行）

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpInitMem` | 0 | 函数的初始内存状态 |
| `OpArg` | 0 | 函数参数（aux=GCNode, auxint=偏移量） |
| `OpArgIntReg/ArgFloatReg` | 0 | 寄存器传递的参数 |
| `OpAddr` | 1 | 全局变量地址：arg0=SB, aux=LSym |
| `OpLocalAddr` | 2 | 局部变量地址：arg0=SP, arg1=内存 |
| `OpSP` | 0 | 栈指针（固定寄存器） |
| `OpSB` | 0 | 静态基址指针（固定寄存器） |
| `OpGetG` | 1 | 读取 goroutine 指针（arg0=内存） |
| `OpGetClosurePtr` | 0 | 从寄存器获取闭包指针 |
| `OpGetCallerPC` | 0 | 返回地址 |
| `OpGetCallerSP` | 1 | 调用者的栈指针 |
| `OpNilCheck` | 2 | nil 指针检查（arg0=指针, arg1=内存） |
| `OpIsNonNil` | 1 | 测试指针是否非 nil |
| `OpIsInBounds` | 2 | 边界检查：0 <= arg0 < arg1 |
| `OpIsSliceInBounds` | 2 | 切片边界检查：0 <= arg0 <= arg1 |
| `OpVarDef` | 1 | 变量即将初始化（GC 提示） |
| `OpVarLive` | 1 | 变量必须保持活跃 |
| `OpKeepAlive` | 2 | 保持值活跃直到此点 |
| `OpInlMark` | 1 | 内联函数体标记 |

#### 复合类型（第 516-548 行）

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpSliceMake` | 3 | 构造切片：arg0=指针, arg1=长度, arg2=容量 |
| `OpSlicePtr` | 1 | 提取切片指针 |
| `OpSliceLen` | 1 | 提取切片长度 |
| `OpSliceCap` | 1 | 提取切片容量 |
| `OpStringMake` | 2 | 构造字符串：arg0=指针, arg1=长度 |
| `OpStringPtr` | 1 | 提取字符串指针 |
| `OpStringLen` | 1 | 提取字符串长度 |
| `OpIMake` | 2 | 构造接口：arg0=itab, arg1=数据 |
| `OpITab` | 1 | 提取接口表指针 |
| `OpIData` | 1 | 提取接口数据指针 |
| `OpComplexMake` | 2 | 构造复数：arg0=实部, arg1=虚部 |
| `OpStructMake` | -1 | 从字段构造结构体 |
| `OpArrayMake1` | 1 | 构造单元素数组 |

#### 函数调用（第 428-462 行）

| 操作码 | Aux | 描述 |
|--------|-----|------|
| `OpStaticCall` | CallOff | 直接调用 `aux.(*obj.LSym)` |
| `OpClosureCall` | CallOff | 闭包调用：arg0=代码指针, arg1=上下文指针 |
| `OpInterCall` | CallOff | 接口方法调用：arg0=代码指针 |
| `OpTailCall` | CallOff | 尾调用（直接） |
| `OpTailCallInter` | CallOff | 尾调用（接口） |
| `OpStaticLECall` | CallOff | 延迟展开的静态调用 |
| `OpClosureLECall` | CallOff | 延迟展开的闭包调用 |
| `OpInterLECall` | CallOff | 延迟展开的接口调用 |

### 2.4 与 LLVM IR 的关键差异

| 属性 | Go gc SSA | LLVM IR |
|------|-----------|---------|
| 目标 | 直接本地代码（无 LLVM） | 需要 LLVM 后端 |
| 内存模型 | 显式 `Mem` 类型贯穿操作 | 通过 `load`/`store` 和地址空间 |
| Phi 节点 | `OpPhi`，基于前驱选择 | `phi` 指令 |
| 类型系统 | Go 类型（`*types.Type`） | LLVM 类型系统 |
| 调用 | `OpStaticCall`/`OpClosureCall`/`OpInterCall` | `call` 指令 |
| 写屏障 | `OpStoreWB`/`OpMoveWB`/`OpZeroWB` | 非内建 |
| nil 检查 | `OpNilCheck`（显式） | 非内建 |
| 边界检查 | `OpIsInBounds`/`OpIsSliceInBounds` | 非内建 |
| Goroutine | `OpGetG` 读取 g 指针 | 无等价物 |

---

## 3. 运行时函数

### 3.1 内存分配

来源: `typecheck/builtin.go:30-31`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.newobject` | `(type) → unsafe.Pointer` | `builtin.go:30` — `{"newobject", funcTag, 4}` |
| `runtime.mallocgc` | `(size uintptr, type *byte, needzero bool) → unsafe.Pointer` | `builtin.go:31` — `{"mallocgc", funcTag, 8}` |
| `runtime.makeslice` | `(elemtype, len, cap) → unsafe.Pointer` | `builtin.go:160` |
| `runtime.makeslice64` | `(elemtype, len64, cap64) → unsafe.Pointer` | `builtin.go:161` |
| `runtime.makeslicecopy` | `(elemtype, copylen, cap, srcptr) → unsafe.Pointer` | `builtin.go:162` |
| `runtime.growslice` | `(oldptr, newlen, oldcap, num, etype) → slice` | `builtin.go:163` |

### 3.2 Panic / Recover / Defer

来源: `typecheck/builtin.go:32-40`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.gopanic` | `(interface{})` | `builtin.go:38` |
| `runtime.gorecover` | `() → interface{}` | `builtin.go:39` |
| `runtime.panicdivide` | `()` | `builtin.go:32` |
| `runtime.panicshift` | `()` | `builtin.go:33` |
| `runtime.panicmakeslicelen` | `()` | `builtin.go:34` |
| `runtime.panicmakeslicecap` | `()` | `builtin.go:35` |
| `runtime.panicwrap` | `()` | `builtin.go:37` |
| `runtime.throwinit` | `()` | `builtin.go:36` |
| `runtime.goPanicIndex` | `(idx, len int)` | `builtin.go:41` |
| `runtime.goPanicIndexU` | `(idx uint, len int)` | `builtin.go:42` |
| `runtime.goPanicSliceAlen` | `(i, l int)` | `builtin.go:43` |
| `runtime.goPanicSliceAcap` | `(i, c int)` | `builtin.go:45` |
| `runtime.goPanicSliceB` | `(i, j int)` | `builtin.go:47` |
| `runtime.goPanicSlice3Alen` | `(i, l int)` | `builtin.go:49` |
| `runtime.goPanicSlice3Acap` | `(i, c int)` | `builtin.go:51` |
| `runtime.goPanicSlice3B` | `(i, j int)` | `builtin.go:53` |
| `runtime.goPanicSlice3C` | `(j, k int)` | `builtin.go:55` |
| `runtime.goPanicSliceConvert` | `(string)` | `builtin.go:57` |
| `runtime.goschedguarded` | `()` | `builtin.go:40` |
| `runtime.KeepAlive` | `(interface{})` | `builtin.go:256` |
| `runtime.deferrangefunc` | `() → interface{}` | `builtin.go:114` |

### 3.3 Channel 操作

来源: `typecheck/builtin.go:143-150`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.makechan64` | `(elemtype, hint64) → *hchan` | `builtin.go:143` |
| `runtime.makechan` | `(elemtype, hint int) → *hchan` | `builtin.go:144` |
| `runtime.chanrecv1` | `(chan, elem)` | `builtin.go:145` — 单值接收 |
| `runtime.chanrecv2` | `(chan, elem) → bool` | `builtin.go:146` — comma-ok 接收 |
| `runtime.chansend1` | `(chan, elem)` | `builtin.go:147` |
| `runtime.closechan` | `(chan)` | `builtin.go:148` |
| `runtime.chanlen` | `(chan) → int` | `builtin.go:149` |
| `runtime.chancap` | `(chan) → int` | `builtin.go:150` |
| `runtime.selectnbsend` | `(chan, elem) → bool` | `builtin.go:155` |
| `runtime.selectnbrecv` | `(elem, chan) → bool` | `builtin.go:156` |
| `runtime.selectsetpc` | `(pc *uintptr)` | `builtin.go:157` |
| `runtime.selectgo` | `(...) → int` | `builtin.go:158` |
| `runtime.block` | `()` | `builtin.go:159` |

### 3.4 Map 操作

来源: `typecheck/builtin.go:117-142`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.makemap64` | `(maptype, hint64, m) → *hmap` | `builtin.go:117` |
| `runtime.makemap` | `(maptype, hint int, m) → *hmap` | `builtin.go:118` |
| `runtime.makemap_small` | `() → *hmap` | `builtin.go:119` |
| `runtime.mapaccess1` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:120` |
| `runtime.mapaccess1_fast32` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:121` |
| `runtime.mapaccess1_fast64` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:122` |
| `runtime.mapaccess1_faststr` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:123` |
| `runtime.mapaccess1_fat` | `(maptype, m, key, zero) → unsafe.Pointer` | `builtin.go:124` |
| `runtime.mapaccess2` | `(maptype, m, key) → (unsafe.Pointer, bool)` | `builtin.go:125` |
| `runtime.mapassign` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:130` |
| `runtime.mapassign_fast32` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:131` |
| `runtime.mapassign_fast32ptr` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:132` |
| `runtime.mapassign_fast64` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:133` |
| `runtime.mapassign_faststr` | `(maptype, m, key) → unsafe.Pointer` | `builtin.go:135` |
| `runtime.mapdelete` | `(maptype, m, key)` | `builtin.go:137` |
| `runtime.mapdelete_fast32/fast64/faststr` | `(maptype, m, key)` | `builtin.go:138-140` |
| `runtime.mapIterStart` | `(maptype, m) → hiter` | `builtin.go:136` |
| `runtime.mapIterNext` | `(it) → bool` | `builtin.go:141` |
| `runtime.mapclear` | `(maptype, m)` | `builtin.go:142` |

### 3.5 字符串操作

来源: `typecheck/builtin.go:77-96`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.concatstring2` | `(buf *[32]byte, s0, s1 string) → string` | `builtin.go:77` |
| `runtime.concatstring3` | `(buf *[32]byte, s0, s1, s2 string) → string` | `builtin.go:78` |
| `runtime.concatstring4` | `(buf *[32]byte, s0..s3) → string` | `builtin.go:79` |
| `runtime.concatstring5` | `(buf *[32]byte, s0..s4) → string` | `builtin.go:80` |
| `runtime.concatstrings` | `(buf *[32]byte, sl []string) → string` | `builtin.go:81` |
| `runtime.concatbyte2/3/4/5` | `(buf, b0, b1, ...) → []byte` | `builtin.go:82-85` |
| `runtime.concatbytes` | `(buf, sl [][]byte) → []byte` | `builtin.go:86` |
| `runtime.cmpstring` | `(s0, s1 string) → int` | `builtin.go:87` |
| `runtime.intstring` | `(buf *[4]byte, v int64) → string` | `builtin.go:88` |
| `runtime.slicebytetostring` | `(buf *[32]byte, b []byte) → string` | `builtin.go:89` |
| `runtime.slicebytetostringtmp` | `(b []byte) → string` | `builtin.go:90` |
| `runtime.slicerunetostring` | `(buf *[32]byte, r []rune) → string` | `builtin.go:91` |
| `runtime.stringtoslicebyte` | `(buf *[32]byte, s string) → []byte` | `builtin.go:92` |
| `runtime.stringtoslicerune` | `(buf *[4]byte, s string) → []rune` | `builtin.go:93` |
| `runtime.decoderune` | `(s string, k int) → (rune, int)` | `builtin.go:95` |
| `runtime.countrunes` | `(s string) → int` | `builtin.go:96` |

### 3.6 切片操作

来源: `typecheck/builtin.go:94,160-176`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.slicecopy` | `(to, fm, width, tolen, fmlen int) → int` | `builtin.go:94` |
| `runtime.growslice` | `(old unsafe.Pointer, new, old, num int, et *_type) → slice` | `builtin.go:163` |
| `runtime.growsliceBuf` | `(et, old, new, num) → slice` | `builtin.go:164` |
| `runtime.growsliceNoAlias` | `(et, old, new, num) → slice` | `builtin.go:166` |
| `runtime.moveSlice` | `(et, dst, src, n) → int` | `builtin.go:173` |
| `runtime.moveSliceNoScan` | `(et, dst, src, n) → int` | `builtin.go:174` |

### 3.7 内存操作

来源: `typecheck/builtin.go:151-186`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.memmove` | `(dst, src, size)` | `builtin.go:177` |
| `runtime.memclrNoHeapPointers` | `(ptr, size)` | `builtin.go:178` |
| `runtime.memclrHasPointers` | `(ptr, size)` | `builtin.go:179` |
| `runtime.typedmemmove` | `(type, dst, src)` | `builtin.go:152` |
| `runtime.typedmemclr` | `(type, ptr)` | `builtin.go:153` |
| `runtime.typedslicecopy` | `(type, dst, src) → int` | `builtin.go:154` |
| `runtime.writeBarrier` | `(var) → struct{enabled, needed, cgo bool}` | `builtin.go:151` — 全局变量 |

### 3.8 接口 / 类型转换

来源: `typecheck/builtin.go:97-112`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.convT` | `(type, elem) → unsafe.Pointer` | `builtin.go:97` |
| `runtime.convTnoptr` | `(type, elem) → unsafe.Pointer` | `builtin.go:98` |
| `runtime.convT16` | `(v uint16) → unsafe.Pointer` | `builtin.go:99` |
| `runtime.convT32` | `(v uint32) → unsafe.Pointer` | `builtin.go:100` |
| `runtime.convT64` | `(v uint64) → unsafe.Pointer` | `builtin.go:101` |
| `runtime.convTstring` | `(v string) → unsafe.Pointer` | `builtin.go:102` |
| `runtime.convTslice` | `(v []byte) → unsafe.Pointer` | `builtin.go:103` |
| `runtime.assertE2I` | `(inter, e iface) → iface` | `builtin.go:104` |
| `runtime.assertE2I2` | `(inter, e iface) → (iface, bool)` | `builtin.go:105` |
| `runtime.typeAssert` | `(inter, e iface) → (iface, bool)` | `builtin.go:109` |
| `runtime.interfaceSwitch` | `(cases, iface) → (int, iface)` | `builtin.go:110` |
| `runtime.panicdottypeE` | `(have, want, iface)` | `builtin.go:106` |
| `runtime.panicdottypeI` | `(have, want, iface)` | `builtin.go:107` |
| `runtime.panicnildottype` | `(want)` | `builtin.go:108` |
| `runtime.ifaceeq` | `(f1, f2, x1, x2) → bool` | `builtin.go:111` |
| `runtime.efaceeq` | `(f1, f2, x1, x2) → bool` | `builtin.go:112` |

### 3.9 哈希 / 相等性

来源: `typecheck/builtin.go:180-207`

| 运行时符号 | 签名 | 源码证据 |
|-----------|------|----------|
| `runtime.memequal` | `(a, b, size) → bool` | `builtin.go:180` |
| `runtime.memequal0/8/16/32/64/128` | `(a, b) → bool` | `builtin.go:181-186` |
| `runtime.strequal` | `(a, b) → bool` | `builtin.go:191` |
| `runtime.interequal` | `(a, b) → bool` | `builtin.go:192` |
| `runtime.nilinterequal` | `(a, b) → bool` | `builtin.go:193` |
| `runtime.memhash` | `(p, seed, size) → uintptr` | `builtin.go:194` |
| `runtime.memhash0/8/16/32/64/128` | `(p, seed) → uintptr` | `builtin.go:195-200` |
| `runtime.strhash` | `(s, seed) → uintptr` | `builtin.go:205` |
| `runtime.interhash` | `(a, seed) → uintptr` | `builtin.go:206` |
| `runtime.nilinterhash` | `(a, seed) → uintptr` | `builtin.go:207` |

### 3.10 打印函数

来源: `typecheck/builtin.go:58-76`

| 运行时符号 | 源码证据 |
|-----------|----------|
| `runtime.printbool` | `builtin.go:58` |
| `runtime.printfloat64` | `builtin.go:59` |
| `runtime.printint` | `builtin.go:61` |
| `runtime.printhex` | `builtin.go:62` |
| `runtime.printuint` | `builtin.go:63` |
| `runtime.printcomplex128` | `builtin.go:64` |
| `runtime.printstring` | `builtin.go:66` |
| `runtime.printpointer` | `builtin.go:68` |
| `runtime.printiface` | `builtin.go:70` |
| `runtime.printnl` | `builtin.go:73` |
| `runtime.printsp` | `builtin.go:74` |
| `runtime.printlock` | `builtin.go:75` |
| `runtime.printunlock` | `builtin.go:76` |

### 3.11 竞态 / 消毒器检测

来源: `typecheck/builtin.go:221-234`

| 运行时符号 | 源码证据 |
|-----------|----------|
| `runtime.racefuncenter` | `builtin.go:221` |
| `runtime.racefuncexit` | `builtin.go:222` |
| `runtime.raceread` | `builtin.go:223` |
| `runtime.racewrite` | `builtin.go:224` |
| `runtime.racereadrange` | `builtin.go:225` |
| `runtime.racewriterange` | `builtin.go:226` |
| `runtime.msanread` | `builtin.go:227` |
| `runtime.msanwrite` | `builtin.go:228` |
| `runtime.asanread` | `builtin.go:230` |
| `runtime.asanwrite` | `builtin.go:231` |

---

## 4. CGo 模式

### 4.1 CGo 生成的符号

来源: `cmd/cgo/out.go:36-112`

| 模式 | 示例 | 源码证据 |
|------|------|----------|
| `_Cgo_ptr` | `_Cgo_ptr(ptr)` | `out.go:100` — 防止赋值的辅助函数 |
| `_Cgo_always_false` | `var _Cgo_always_false bool` | `out.go:103-104` — `//go:linkname _Cgo_always_false runtime.cgoAlwaysFalse` |
| `_Cgo_use` | `func _Cgo_use(interface{})` | `out.go:105-106` — `//go:linkname _Cgo_use runtime.cgoUse` |
| `_Cgo_keepalive` | `func _Cgo_keepalive(interface{})` | `out.go:107-109` — `//go:linkname _Cgo_keepalive runtime.cgoKeepAlive` |
| `_Cgo_no_callback` | `func _Cgo_no_callback(bool)` | `out.go:111-112` — `//go:linkname _Cgo_no_callback runtime.cgoNoCallback` |
| `__cgo_<C_name>` | `var __cgo_puts byte` | `out.go:195-197` — 静态 C 函数引用 |

### 4.2 CGo 编译指示

来源: `cmd/cgo/out.go:195-197,374-378`

| 编译指示 | 示例 | 源码证据 |
|----------|------|----------|
| `//go:cgo_import_static` | `//go:cgo_import_static puts` | `out.go:196` — 静态 C 函数导入 |
| `//go:cgo_import_dynamic` | `//go:cgo_import_dynamic puts puts "libc.so.6"` | `out.go:374` — 动态 C 函数导入 |
| `//go:cgo_ldflag` | `//go:cgo_ldflag "-lpthread"` | `out.go:50` — 链接器标志 |

### 4.3 CGo 运行时支持函数

来源: `cmd/cgo/out.go:63-77`, `runtime/proc.go`

| 符号 | 用途 | 源码证据 |
|------|------|----------|
| `crosscall2` | C 到 Go 调用跳板 | `out.go:64` |
| `_cgo_wait_runtime_init_done` | 等待 Go 运行时初始化 | `out.go:65` |
| `_cgo_release_context` | 释放 CGo 上下文 | `out.go:66` |
| `_cgo_topofstack` | CGo 栈顶 | `out.go:67` |
| `_cgo_allocate` | CGo 内存分配 | `out.go:75` |
| `_cgo_panic` | CGo panic 处理器 | `out.go:76` |
| `_cgo_reginit` | CGo 注册初始化 | `out.go:77` |
| `_cgo_init` | CGo 初始化 | `runtime/asm_*.s:32` |
| `_cgo_thread_start` | CGo 线程启动 | `runtime/proc.go:226` |
| `_cgo_pthread_key_created` | Pthread 键标志 | `runtime/proc.go:221` |
| `_cgo_notify_runtime_init_done` | 运行时初始化通知 | `runtime/proc.go:236` |
| `_cgo_setenv` / `_cgo_unsetenv` | 环境变量同步 | `runtime/proc.go:229-233` |

---

## 5. 编译器内建函数

### 5.1 原子操作 (sync/atomic)

来源: `ssagen/intrinsics.go:1263-1312`

这些从 `sync/atomic.*` 别名到 `internal/runtime/atomic.*`，然后降低为 SSA 原子操作：

| sync/atomic 函数 | 内部别名 | SSA 操作码 |
|------------------|----------|------------|
| `LoadInt32/Uint32` | `internal/runtime/atomic.Load` | `OpAtomicLoad32` |
| `LoadInt64/Uint64` | `internal/runtime/atomic.Load64` | `OpAtomicLoad64` |
| `LoadPointer` | `internal/runtime/atomic.Loadp` | `OpAtomicLoadPtr` |
| `StoreInt32/Uint32` | `internal/runtime/atomic.Store` | `OpAtomicStore32` |
| `StoreInt64/Uint64` | `internal/runtime/atomic.Store64` | `OpAtomicStore64` |
| `SwapInt32/Uint32` | `internal/runtime/atomic.Xchg` | `OpAtomicExchange32` |
| `SwapInt64/Uint64` | `internal/runtime/atomic.Xchg64` | `OpAtomicExchange64` |
| `CompareAndSwapInt32/Uint32` | `internal/runtime/atomic.Cas` | `OpAtomicCompareAndSwap32` |
| `CompareAndSwapInt64/Uint64` | `internal/runtime/atomic.Cas64` | `OpAtomicCompareAndSwap64` |
| `AddInt32/Uint32` | `internal/runtime/atomic.Xadd` | `OpAtomicAdd32` |
| `AddInt64/Uint64` | `internal/runtime/atomic.Xadd64` | `OpAtomicAdd64` |
| `AndInt32/Uint32` | `internal/runtime/atomic.And32` | `OpAtomicAnd32`（仅 ARM64/AMD64/Loong64） |
| `OrInt32/Uint32` | `internal/runtime/atomic.Or32` | `OpAtomicOr32`（仅 ARM64/AMD64/Loong64） |

**注意**: `sync/atomic.StorePointer` 不是内建函数——它需要写屏障。

来源: `ssagen/intrinsics.go:1276` — `// Note: not StorePointer, that needs a write barrier.`

### 5.2 math/bits 内建函数

来源: `ssagen/intrinsics.go:900-1000`

| math/bits 函数 | SSA 操作码 | 源码证据 |
|----------------|------------|----------|
| `TrailingZeros64` | `OpCtz64` | `intrinsics.go:901` |
| `TrailingZeros32` | `OpCtz32` | `intrinsics.go:913` |
| `TrailingZeros16` | `OpCtz16` | `intrinsics.go:918` |
| `TrailingZeros8` | `OpCtz8` | `intrinsics.go:923` |
| `LeadingZeros64` | `OpBitLen64`（通过减法） | `intrinsics.go:977` |
| `LeadingZeros32` | `OpBitLen32` | `intrinsics.go:982` |
| `OnesCount64` | `OpPopCount64` | `intrinsics.go`（AMD64/ARM64） |
| `ReverseBytes64` | `OpBswap64` | `intrinsics.go:953` — 别名到 `internal/runtime/sys.Bswap64` |
| `ReverseBytes32` | `OpBswap32` | `intrinsics.go:954` — 别名到 `internal/runtime/sys.Bswap32` |
| `ReverseBytes16` | `OpBswap16` | `intrinsics.go:956` |
| `Len64` | `OpBitLen64` | `intrinsics.go:977` |
| `RotateLeft64` | `OpRotateLeft64` | 架构相关 |

### 5.3 math 内建函数

来源: `ssagen/intrinsics.go`

| math 函数 | SSA 操作码 |
|-----------|------------|
| `math.Sqrt` | `OpSqrt` |
| `math.Sqrt32` | `OpSqrt32` |
| `math.Floor` | `OpFloor` |
| `math.Ceil` | `OpCeil` |
| `math.Trunc` | `OpTrunc` |
| `math.Abs` | `OpAbs` |
| `math.Copysign` | `OpCopysign` |

### 5.4 运行时内建函数

来源: `ssagen/intrinsics.go:136-167`

| 运行时函数 | 内建行为 | 源码证据 |
|-----------|----------|----------|
| `runtime.slicebytetostringtmp` | `OpStringMake`（无复制） | `intrinsics.go:137-144` |
| `runtime.KeepAlive` | `OpKeepAlive` | `intrinsics.go:154-160` |
| `runtime.publicationBarrier` | `OpPubBarrier` | `intrinsics.go:162-167` |
| `internal/runtime/sys.GetCallerPC` | `OpGetCallerPC` | `intrinsics.go:170-173` |
| `internal/runtime/sys.GetCallerSP` | `OpGetCallerSP` | `intrinsics.go:176-179` |
| `internal/runtime/sys.GetClosurePtr` | `OpGetClosurePtr` | `intrinsics.go:182-185` |
| `internal/runtime/sys.Bswap32` | `OpBswap32` | `intrinsics.go:188-192` |
| `internal/runtime/sys.Bswap64` | `OpBswap64` | `intrinsics.go:193-197` |
| `runtime.memequal` | `OpMemEq`（ARM64） | `intrinsics.go:199-203` |

---

## 6. 写屏障模式

### 6.1 写屏障机制

来源: `ssa/writebarrier.go:151-172`

写屏障遍历将指针存储重写为条件分支：

```
if writeBarrier.enabled {
    buf := gcWriteBarrier2()  // 非常规 Go 调用
    buf[0] = val
    buf[1] = *ptr
}
*ptr = val
```

关键运行时符号：
- `runtime.writeBarrier` — 全局变量，包含 `enabled`、`needed`、`cgo` 字段（`builtin.go:151`）
- `runtime.gcWriteBarrier{2..8}` — 写屏障缓冲函数（架构相关汇编）

来源: `ssa/writebarrier.go:171` — `const maxEntries = 8` — 匹配 `runtime.gcWriteBarrier{X}` 实例数。

### 6.2 写屏障 SSA 操作

来源: `ssa/_gen/genericOps.go:405-416`

| 操作码 | 参数数 | 描述 |
|--------|--------|------|
| `OpStoreWB` | 3 | 带写屏障的存储（arg0=地址, arg1=值, arg2=内存） |
| `OpMoveWB` | 3 | 带写屏障的复制（arg0=目标, arg1=源, arg2=内存） |
| `OpZeroWB` | 2 | 带写屏障的清零（arg0=目标, arg1=内存） |
| `OpWB` | 1 | 调用 `runtime.gcWriteBarrier`（返回缓冲区指针 + 内存） |
| `OpWBend` | 1 | 写屏障序列结束 |

---

## 7. 接口 / 类型系统

### 7.1 类型描述符

来源: `reflectdata/reflect.go:552-583`

类型描述符在链接器中使用 `type:` 前缀：

| 模式 | 示例 | 源码证据 |
|------|------|----------|
| `type:.<hash>` | `type:.hash.int` | `reflectdata/alg.go:95` — `TypeSymLookup(".hash." + sig)` |
| `type:.eqfunc.<sig>` | `type:.eqfunc.int` | `reflectdata/alg.go:296` |
| `type:.eq.<sig>` | `type:.eq.int` | `reflectdata/alg.go:330` |
| `type:.<full_type_name>` | `type:.int`, `type:.*os.File` | `reflectdata/reflect.go:559` — `types.TypeSym(t)` |

### 7.2 接口表 (itab)

来源: `reflectdata/reflect.go:591-616`

| 模式 | 示例 | 源码证据 |
|------|------|----------|
| `go:itab.<ConcreteType>,<InterfaceType>` | `go:itab.*os.File,io.Reader` | `reflectdata/reflect.go:603` — `typ.LinkString() + "," + iface.LinkString()` |

ITab 存储在 `go:itab` 包命名空间中。

### 7.3 类型转换函数

来源: `typecheck/builtin.go:97-103`

| 函数 | 使用场景 |
|------|----------|
| `runtime.convT` | 通用类型转换到接口 |
| `runtime.convTnoptr` | 类型转换（类型中无指针） |
| `runtime.convT16` | uint16 到接口 |
| `runtime.convT32` | uint32 到接口 |
| `runtime.convT64` | uint64 到接口 |
| `runtime.convTstring` | string 到接口 |
| `runtime.convTslice` | slice 到接口 |

---

## 8. ABI 差异

### 8.1 ABI0 vs ABIInternal

来源: `ssagen/abi.go`, `types/sym.go:74-93`

| 属性 | ABI0（基于栈） | ABIInternal（基于寄存器） |
|------|---------------|-------------------------|
| 参数传递 | 栈上传递 | 寄存器传递 |
| 返回值 | 栈上 | 寄存器中 |
| 使用场景 | 汇编函数、`//go:linkname` 目标 | 大多数 Go 函数 |
| 来源 | `ssagen/abi.go:165` — `fn.ABI = obj.ABI0` | `types/sym.go:77` — `abi = obj.ABIInternal` |

### 8.2 编译器编译指示

| 编译指示 | 效果 | 源码证据 |
|----------|------|----------|
| `//go:nosplit` | 跳过栈增长检查 | `ssa/func.go:48` — `NoSplit bool` |
| `//go:noescape` | 参数不逃逸到堆 | 标准编译器指令 |
| `//go:noinline` | 阻止函数内联 | 标准编译器指令 |
| `//go:linkname <local> <remote>` | 覆盖符号名 | `types/sym.go:90` — `sym.Linkname` |
| `//go:norace` | 禁用函数的竞态检测器 | 标准编译器指令 |
| `//go:nowritebarrier` | 禁用函数的写屏障 | 标准编译器指令 |
| `//go:nowritebarrierrec` | 禁用写屏障（递归） | 标准编译器指令 |
| `//go:uintptrescapes` | uintptr 参数逃逸 | 标准编译器指令 |
| `//go:registerparams` | 强制函数使用寄存器 ABI | ABI 包装器生成 |

### 8.3 ABI 包装器生成

来源: `ssagen/abi.go:236-289`

当函数从不同的 ABI 上下文调用时，编译器生成包装器：

```
fn.ABIRefs &^ obj.ABISetOf(fn.ABI)  // 需要其他 ABI 的包装器
```

- ABI0 到 ABIInternal 包装器：从栈加载参数到寄存器
- ABIInternal 到 ABI0 包装器：将寄存器参数存储到栈

来源: `ssagen/abi.go:283` — `// ABI0-to-ABIInternal wrappers will be mainly loading params from stack into registers`

---

## 9. Init 函数模式

来源: `pkginit/init.go:26-79`

### 9.1 初始化任务

Go 包有一个初始化记录（`initTask`），包含 3 个阶段：

1. 初始化所有依赖包
2. 初始化所有有初始化器的变量
3. 运行所有 init 函数

来源: `pkginit/init.go:22-25`

### 9.2 Init 函数命名

| 模式 | 描述 | 源码证据 |
|------|------|----------|
| `init` | 用户定义的 init 函数 | 标准 Go |
| `init.0`, `init.1`, ... | 每个包的多个 init 函数 | `pkginit/init.go:60` — `noder.Renameinit()` |
| `init._` | 编译器生成的 init（如 ASan） | `pkginit/init.go:60` |
| `<pkg>.inittask` | 包初始化任务记录 | `pkginit/init.go:32` |

---

## 10. 静态分析关键要点

### 用户代码（需要分析）：
- 匹配 `package.FunctionName` 模式的函数（如 `main.foo`、`crypto/sha256.Sum`）
- 带有 `//export` 名称的函数（用户自选，无前缀）
- 通过 CGo 调用的 C 函数（通过 `//go:cgo_import_*` 编译指示出现）

### 编译器运行时（过滤/跳过）：
- `runtime.*` 中的任何内容（约 150 个函数，在 `typecheck/builtin.go:25-257` 中声明）
- `internal/runtime/atomic.*` 中的任何内容（约 20 个原子操作）
- `internal/runtime/sys.*` 中的任何内容（约 10 个工具函数）
- `internal/runtime/maps.*` 中的任何内容（map 实现辅助函数）
- 保留前缀：`go:`、`type:`（链接器内部符号）
- 类型描述符：`type:.*`（如 `type:.hash.int`）

### CGo 桥接（分类为 FFI 边界）：
- `//go:cgo_import_static` — 静态 C 函数导入
- `//go:cgo_import_dynamic` — 动态 C 函数导入（共享库）
- `_Cgo_*` 函数 — CGo 辅助函数（生成的）
- `__cgo_*` 变量 — 静态 C 函数引用
- `crosscall2`、`_cgo_*` 运行时支持函数

### 内存安全关注点：
- `runtime.writeBarrier` — GC 写屏障状态
- `runtime.mallocgc` — 堆分配（逃逸分析目标）
- `runtime.growslice` — 切片增长（可能重新分配）
- `runtime.gopanic` — panic 点
- `runtime.memmove` / `runtime.memclrNoHeapPointers` — 原始内存操作
- `OpNilCheck` / `OpIsInBounds` / `OpIsSliceInBounds` — 安全检查

### 并发关注点：
- `sync/atomic.*` / `internal/runtime/atomic.*` — 原子操作
- `runtime.chanrecv1/2` / `runtime.chansend1` — channel 操作
- `runtime.selectgo` — select 语句
- `OpGetG` — goroutine 本地存储访问
- `runtime.raceread/write/readrange/writerange` — 竞态检测器钩子

---

## 11. 完整 SSA 块类型映射

来源: `ssa/_gen/genericOps.go:743-754`, `ssa/opGen.go:19,165-171,322-328`

| BlockKind | 字符串 | 控制值 | 后继块 | 描述 |
|-----------|--------|--------|--------|------|
| `BlockInvalid` | `"BlockInvalid"` | - | - | 无效/未初始化 |
| `BlockPlain` | `"Plain"` | 0 | 1 | 无条件跳转到 Succs[0] |
| `BlockIf` | `"If"` | 1（布尔） | 2 | Controls[0] 为真时 Succs[0]，否则 Succs[1] |
| `BlockDefer` | `"Defer"` | 1（调用） | 2 | Succs[0]=正常, Succs[1]=恢复 |
| `BlockRet` | `"Ret"` | 1（内存） | 0 | 函数返回 |
| `BlockRetJmp` | `"RetJmp"` | 1 | 0 | 尾调用返回 |
| `BlockExit` | `"Exit"` | 1（内存） | 0 | panic/退出 |
| `BlockJumpTable` | `"JumpTable"` | 1（整数） | N | 表驱动 switch |
| `BlockFirst` | `"First"` | 0 | 2 | 死代码消除（始终取第一个） |
