# Go Standard Compiler (gc) IR Specification: Compiler-Reserved vs User-Defined

**Source**: `/Users/scc/code/researcher/go/src/cmd/compile/internal/` (Go 1.24+)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming Rules

### 1.1 User-Defined Symbols

| Pattern | Example Symbol | Source Evidence |
|---------|----------------|-----------------|
| Default Go function | `main.foo`, `crypto/sha256.Sum` | `base/link.go:31` — `PkgLinksym(prefix, name, abi)` → `prefix + "." + name` |
| Exported method | `(*T).Method` | `types/sym.go:86` — `LinksymABI(abi)` uses `sym.Pkg.Prefix + "." + sym.Name` |
| `//go:linkname` | `<target>` (user-chosen) | `types/sym.go:90-91` — `if sym.Linkname != "" { return base.Linkname(sym.Linkname, abi) }` |
| `//export <name>` (cgo) | `myFunc` (user-chosen) | `cmd/cgo/out.go:195` — `//go:linkname __cgo_%s %s` |
| Init function | `init`, `init.0`, `init.1`, ... | `pkginit/init.go:60` — `noder.Renameinit()` creates `init._` functions |

### 1.2 Compiler-Reserved Symbols

| Prefix/Pattern | Example | Source Evidence |
|----------------|---------|-----------------|
| `runtime.*` | `runtime.mallocgc`, `runtime.gopanic` | `typecheck/builtin.go:25-257` — `runtimeDecls` array defines ~150 runtime functions |
| `internal/runtime/atomic.*` | `internal/runtime/atomic.Load` | `ssagen/intrinsics.go:251` — `addF("internal/runtime/atomic", "Load", ...)` |
| `internal/runtime/sys.*` | `internal/runtime/sys.Bswap64` | `ssagen/intrinsics.go:193` — `addF("internal/runtime/sys", "Bswap64", ...)` |
| `internal/runtime/maps.*` | `internal/runtime/maps.ctrlGroupMatchH2` | `ssagen/intrinsics.go:1380` — map intrinsics |
| `go:map` (reserved prefix) | `go:map.zero` | `base/link.go:19-22` — `ReservedImports = {"go": true, "type": true}` |
| `type:` (reserved prefix) | `type:.hash.func` | `base/link.go:37-40` — separator is `:` for reserved imports |
| `.inittask` | `<pkg>.inittask` | `pkginit/init.go:32` — `pkg.Lookup(".inittask")` |

### 1.3 Linker Symbol Construction

Go constructs linker symbols (LSym) via two paths:

| Function | Behavior | Source Evidence |
|----------|----------|-----------------|
| `PkgLinksym(prefix, name, abi)` | `prefix + "." + name` (normal) or `prefix + ":" + name` (reserved) | `base/link.go:31-41` |
| `Linkname(name, abi)` | Uses the raw `name` from `//go:linkname` directive | `base/link.go:45-47` — `linksym("_", name, abi)` |

The separator is `.` for normal packages and `:` for reserved imports (`go`, `type`).

### 1.4 ABI Selection

| Function | ABI Used | Source Evidence |
|----------|----------|-----------------|
| `Linksym()` (for functions) | `ABIInternal` (register-based) | `types/sym.go:76-77` — `if sym.Func() { abi = obj.ABIInternal }` |
| `Linksym()` (for variables) | `ABI0` (stack-based) | `types/sym.go:75` — `abi := obj.ABI0` |
| `LookupRuntimeFunc(name)` | `ABIInternal` | `typecheck/syms.go:91-92` |
| `LookupRuntimeVar(name)` | `ABI0` | `typecheck/syms.go:98-99` |

---

## 2. SSA Intermediate Representation

Go's gc compiler uses its own SSA form (NOT LLVM IR). Go compiles directly to native machine code.

### 2.1 SSA Value Structure

Source: `ssa/value.go:21-64`

```
type Value struct {
    ID    ID          // unique identifier, densely allocated from 1
    Op    Op          // operation opcode
    Type  *types.Type // Go type (or pseudo-type)
    AuxInt int64      // auxiliary integer (constants, offsets)
    Aux   Aux         // auxiliary info (symbols, strings, types)
    Args  []*Value    // input values
    Block *Block      // containing basic block
    Pos   src.XPos    // source position
    Uses  int32       // use count
}
```

### 2.2 Block Kinds

Source: `ssa/_gen/genericOps.go:743-754`, `ssa/opGen.go:19,165-171`

| BlockKind | Control Values | Successors | Description |
|-----------|---------------|------------|-------------|
| `BlockPlain` | 0 | 1 | Unconditional jump |
| `BlockIf` | 1 (bool) | 2 | Conditional branch: `Succs[0]` if true, `Succs[1]` if false |
| `BlockDefer` | 1 (call) | 2 | `Succs[0]` = normal path, `Succs[1]` = defer recovery |
| `BlockRet` | 1 (mem) | 0 | Function return |
| `BlockRetJmp` | 1 | 0 | Tail call return |
| `BlockExit` | 1 (mem) | 0 | Panic/exit (no return) |
| `BlockJumpTable` | 1 (int) | N | Switch/table jump |
| `BlockFirst` | 0 | 2 | Transient: always takes first successor (dead code elimination) |
| `BlockInvalid` | - | - | Invalid/uninitialized |

### 2.3 Key Generic SSA Opcodes

Source: `ssa/_gen/genericOps.go`

#### Arithmetic (lines 25-105)

| Opcode | Args | Description |
|--------|------|-------------|
| `OpAdd8/16/32/64` | 2 | Addition (commutative) |
| `OpSub8/16/32/64` | 2 | Subtraction |
| `OpMul8/16/32/64` | 2 | Multiplication (commutative) |
| `OpDiv8/16/32/64` | 2 | Signed division |
| `OpDiv8u/16u/32u/64u` | 2 | Unsigned division |
| `OpMod8/16/32/64` | 2 | Signed modulo |
| `OpHmul32/64` | 2 | High-half multiply |
| `OpMul32uhilo/Mul64uhilo` | 2 | Full multiply returning (hi, lo) |
| `OpMul32uover/Mul64uover` | 2 | Multiply with overflow detection |

#### Bitwise (lines 92-266)

| Opcode | Args | Description |
|--------|------|-------------|
| `OpAnd8/16/32/64` | 2 | Bitwise AND (commutative) |
| `OpOr8/16/32/64` | 2 | Bitwise OR (commutative) |
| `OpXor8/16/32/64` | 2 | Bitwise XOR (commutative) |
| `OpLsh{A}x{B}` | 2 | Left shift (`A`-bit value by `B`-bit amount) |
| `OpRsh{A}x{B}` | 2 | Right shift, signed |
| `OpRsh{A}Ux{B}` | 2 | Right shift, unsigned |
| `OpCtz8/16/32/64` | 1 | Count trailing zeros |
| `OpBitLen8/16/32/64` | 1 | Number of bits (leading zeros complement) |
| `OpBswap16/32/64` | 1 | Byte swap |
| `OpPopCount8/16/32/64` | 1 | Population count |
| `OpRotateLeft8/16/32/64` | 2 | Rotate left |

#### Comparison (lines 163-204)

| Opcode | Args | Type | Description |
|--------|------|------|-------------|
| `OpEq8/16/32/64` | 2 | Bool | Equality (commutative) |
| `OpNeq8/16/32/64` | 2 | Bool | Inequality (commutative) |
| `OpLess8/16/32/64` | 2 | Bool | Less than, signed |
| `OpLess8U/16U/32U/64U` | 2 | Bool | Less than, unsigned |
| `OpLeq8/16/32/64` | 2 | Bool | Less or equal, signed |
| `OpEqPtr` | 2 | Bool | Pointer equality |
| `OpEqInter/NeqInter` | 2 | Bool | Interface equality |
| `OpEqSlice/NeqSlice` | 2 | Bool | Slice equality (nil only) |

#### Data Movement (lines 318-417)

| Opcode | Args | Description |
|--------|------|-------------|
| `OpPhi` | -1 | SSA phi node (select based on predecessor block) |
| `OpCopy` | 1 | Identity (output = arg0) |
| `OpConvert` | 2 | Pointer/int conversion (zero-width, GC-safe) |
| `OpLoad` | 2 | Memory load: arg0=addr, arg1=mem |
| `OpStore` | 3 | Memory store: arg0=addr, arg1=val, arg2=mem, aux=type |
| `OpMove` | 3 | Memory copy: arg0=dst, arg1=src, arg2=mem, auxint=size |
| `OpZero` | 2 | Memory zero: arg0=dst, arg1=mem, auxint=size |
| `OpStoreWB` | 3 | Store with write barrier |
| `OpMoveWB` | 3 | Move with write barrier |
| `OpZeroWB` | 2 | Zero with write barrier |
| `OpWB` | 1 | Invoke `runtime.gcWriteBarrier` |

#### Constants (lines 333-351)

| Opcode | Aux Type | Description |
|--------|----------|-------------|
| `OpConstBool` | Bool | auxint: 0=false, 1=true |
| `OpConst8/16/32` | Int | Sign-extended integer constant |
| `OpConst64` | Int64 | 64-bit integer constant |
| `OpConst32F` | Float32 | 32-bit float constant |
| `OpConst64F` | Float64 | 64-bit float constant |
| `OpConstString` | String | String constant |
| `OpConstNil` | - | Nil pointer |
| `OpConstInterface` | - | Nil interface |
| `OpConstSlice` | - | Nil slice |

#### Special/Pseudo (lines 353-372, 500-569)

| Opcode | Args | Description |
|--------|------|-------------|
| `OpInitMem` | 0 | Initial memory state for function |
| `OpArg` | 0 | Function argument (aux=GCNode, auxint=offset) |
| `OpArgIntReg/ArgFloatReg` | 0 | Register-passed argument |
| `OpAddr` | 1 | Address of global: arg0=SB, aux=LSym |
| `OpLocalAddr` | 2 | Address of local: arg0=SP, arg1=mem |
| `OpSP` | 0 | Stack pointer (fixed register) |
| `OpSB` | 0 | Static base pointer (fixed register) |
| `OpGetG` | 1 | Read goroutine pointer (arg0=mem) |
| `OpGetClosurePtr` | 0 | Get closure pointer from register |
| `OpGetCallerPC` | 0 | Return address |
| `OpGetCallerSP` | 1 | Caller's stack pointer |
| `OpNilCheck` | 2 | Nil pointer check (arg0=ptr, arg1=mem) |
| `OpIsNonNil` | 1 | Test if pointer is non-nil |
| `OpIsInBounds` | 2 | Bounds check: 0 <= arg0 < arg1 |
| `OpIsSliceInBounds` | 2 | Slice bounds check: 0 <= arg0 <= arg1 |
| `OpVarDef` | 1 | Variable about to be initialized (GC hint) |
| `OpVarLive` | 1 | Variable must be kept live |
| `OpKeepAlive` | 2 | Keep value alive until this point |
| `OpInlMark` | 1 | Inline function body marker |

#### Composite Types (lines 516-548)

| Opcode | Args | Description |
|--------|------|-------------|
| `OpSliceMake` | 3 | Construct slice: arg0=ptr, arg1=len, arg2=cap |
| `OpSlicePtr` | 1 | Extract slice pointer |
| `OpSliceLen` | 1 | Extract slice length |
| `OpSliceCap` | 1 | Extract slice capacity |
| `OpStringMake` | 2 | Construct string: arg0=ptr, arg1=len |
| `OpStringPtr` | 1 | Extract string pointer |
| `OpStringLen` | 1 | Extract string length |
| `OpIMake` | 2 | Construct interface: arg0=itab, arg1=data |
| `OpITab` | 1 | Extract interface table pointer |
| `OpIData` | 1 | Extract interface data pointer |
| `OpComplexMake` | 2 | Construct complex: arg0=real, arg1=imag |
| `OpStructMake` | -1 | Construct struct from fields |
| `OpArrayMake1` | 1 | Construct single-element array |

#### Function Calls (lines 428-462)

| Opcode | Aux | Description |
|--------|-----|-------------|
| `OpStaticCall` | CallOff | Direct call to `aux.(*obj.LSym)` |
| `OpClosureCall` | CallOff | Closure call: arg0=code ptr, arg1=context ptr |
| `OpInterCall` | CallOff | Interface method call: arg0=code ptr |
| `OpTailCall` | CallOff | Tail call (direct) |
| `OpTailCallInter` | CallOff | Tail call (interface) |
| `OpStaticLECall` | CallOff | Late-expanded static call |
| `OpClosureLECall` | CallOff | Late-expanded closure call |
| `OpInterLECall` | CallOff | Late-expanded interface call |

### 2.4 Key Differences from LLVM IR

| Property | Go gc SSA | LLVM IR |
|----------|-----------|---------|
| Target | Direct native code (no LLVM) | Requires LLVM backend |
| Memory model | Explicit `Mem` type threaded through ops | Memory via `load`/`store` with address spaces |
| Phi nodes | `OpPhi` with predecessor-based selection | `phi` instruction |
| Type system | Go types (`*types.Type`) | LLVM type system |
| Calls | `OpStaticCall`/`OpClosureCall`/`OpInterCall` | `call` instruction |
| Write barriers | `OpStoreWB`/`OpMoveWB`/`OpZeroWB` | Not built-in |
| Nil checks | `OpNilCheck` (explicit) | Not built-in |
| Bounds checks | `OpIsInBounds`/`OpIsSliceInBounds` | Not built-in |
| Goroutine | `OpGetG` reads g pointer | No equivalent |

---

## 3. Runtime Functions

### 3.1 Allocation

Source: `typecheck/builtin.go:30-31`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
| `runtime.newobject` | `(type) → unsafe.Pointer` | `builtin.go:30` — `{"newobject", funcTag, 4}` |
| `runtime.mallocgc` | `(size uintptr, type *byte, needzero bool) → unsafe.Pointer` | `builtin.go:31` — `{"mallocgc", funcTag, 8}` |
| `runtime.makeslice` | `(elemtype, len, cap) → unsafe.Pointer` | `builtin.go:160` |
| `runtime.makeslice64` | `(elemtype, len64, cap64) → unsafe.Pointer` | `builtin.go:161` |
| `runtime.makeslicecopy` | `(elemtype, copylen, cap, srcptr) → unsafe.Pointer` | `builtin.go:162` |
| `runtime.growslice` | `(oldptr, newlen, oldcap, num, etype) → slice` | `builtin.go:163` |

### 3.2 Panic / Recover / Defer

Source: `typecheck/builtin.go:32-40`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
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

### 3.3 Channel Operations

Source: `typecheck/builtin.go:143-150`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
| `runtime.makechan64` | `(elemtype, hint64) → *hchan` | `builtin.go:143` |
| `runtime.makechan` | `(elemtype, hint int) → *hchan` | `builtin.go:144` |
| `runtime.chanrecv1` | `(chan, elem)` | `builtin.go:145` — single-value receive |
| `runtime.chanrecv2` | `(chan, elem) → bool` | `builtin.go:146` — comma-ok receive |
| `runtime.chansend1` | `(chan, elem)` | `builtin.go:147` |
| `runtime.closechan` | `(chan)` | `builtin.go:148` |
| `runtime.chanlen` | `(chan) → int` | `builtin.go:149` |
| `runtime.chancap` | `(chan) → int` | `builtin.go:150` |
| `runtime.selectnbsend` | `(chan, elem) → bool` | `builtin.go:155` |
| `runtime.selectnbrecv` | `(elem, chan) → bool` | `builtin.go:156` |
| `runtime.selectsetpc` | `(pc *uintptr)` | `builtin.go:157` |
| `runtime.selectgo` | `(...) → int` | `builtin.go:158` |
| `runtime.block` | `()` | `builtin.go:159` |

### 3.4 Map Operations

Source: `typecheck/builtin.go:117-142`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
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

### 3.5 String Operations

Source: `typecheck/builtin.go:77-96`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
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

### 3.6 Slice Operations

Source: `typecheck/builtin.go:94,160-176`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
| `runtime.slicecopy` | `(to, fm, width, tolen, fmlen int) → int` | `builtin.go:94` |
| `runtime.growslice` | `(old unsafe.Pointer, new, old, num int, et *_type) → slice` | `builtin.go:163` |
| `runtime.growsliceBuf` | `(et, old, new, num) → slice` | `builtin.go:164` |
| `runtime.growsliceNoAlias` | `(et, old, new, num) → slice` | `builtin.go:166` |
| `runtime.moveSlice` | `(et, dst, src, n) → int` | `builtin.go:173` |
| `runtime.moveSliceNoScan` | `(et, dst, src, n) → int` | `builtin.go:174` |

### 3.7 Memory Operations

Source: `typecheck/builtin.go:151-186`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
| `runtime.memmove` | `(dst, src, size)` | `builtin.go:177` |
| `runtime.memclrNoHeapPointers` | `(ptr, size)` | `builtin.go:178` |
| `runtime.memclrHasPointers` | `(ptr, size)` | `builtin.go:179` |
| `runtime.typedmemmove` | `(type, dst, src)` | `builtin.go:152` |
| `runtime.typedmemclr` | `(type, ptr)` | `builtin.go:153` |
| `runtime.typedslicecopy` | `(type, dst, src) → int` | `builtin.go:154` |
| `runtime.writeBarrier` | `(var) → struct{enabled, needed, cgo bool}` | `builtin.go:151` — global variable |

### 3.8 Interface / Type Conversion

Source: `typecheck/builtin.go:97-112`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
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

### 3.9 Hash / Equality

Source: `typecheck/builtin.go:180-207`

| Runtime Symbol | Signature | Source Evidence |
|----------------|-----------|-----------------|
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

### 3.10 Print Functions

Source: `typecheck/builtin.go:58-76`

| Runtime Symbol | Source Evidence |
|----------------|-----------------|
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

### 3.11 Race / Sanitizer Instrumentation

Source: `typecheck/builtin.go:221-234`

| Runtime Symbol | Source Evidence |
|----------------|-----------------|
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

## 4. CGo Patterns

### 4.1 CGo-Generated Symbols

Source: `cmd/cgo/out.go:36-112`

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `_Cgo_ptr` | `_Cgo_ptr(ptr)` | `out.go:100` — helper to prevent assignments |
| `_Cgo_always_false` | `var _Cgo_always_false bool` | `out.go:103-104` — `//go:linkname _Cgo_always_false runtime.cgoAlwaysFalse` |
| `_Cgo_use` | `func _Cgo_use(interface{})` | `out.go:105-106` — `//go:linkname _Cgo_use runtime.cgoUse` |
| `_Cgo_keepalive` | `func _Cgo_keepalive(interface{})` | `out.go:107-109` — `//go:linkname _Cgo_keepalive runtime.cgoKeepAlive` |
| `_Cgo_no_callback` | `func _Cgo_no_callback(bool)` | `out.go:111-112` — `//go:linkname _Cgo_no_callback runtime.cgoNoCallback` |
| `__cgo_<C_name>` | `var __cgo_puts byte` | `out.go:195-197` — static C function reference |

### 4.2 CGo Pragmas

Source: `cmd/cgo/out.go:195-197,374-378`

| Pragma | Example | Source Evidence |
|--------|---------|-----------------|
| `//go:cgo_import_static` | `//go:cgo_import_static puts` | `out.go:196` — static C function import |
| `//go:cgo_import_dynamic` | `//go:cgo_import_dynamic puts puts "libc.so.6"` | `out.go:374` — dynamic C function import |
| `//go:cgo_ldflag` | `//go:cgo_ldflag "-lpthread"` | `out.go:50` — linker flags |

### 4.3 CGo Runtime Support Functions

Source: `cmd/cgo/out.go:63-77`, `runtime/proc.go`

| Symbol | Purpose | Source Evidence |
|--------|---------|-----------------|
| `crosscall2` | C-to-Go call trampoline | `out.go:64` |
| `_cgo_wait_runtime_init_done` | Wait for Go runtime init | `out.go:65` |
| `_cgo_release_context` | Release CGo context | `out.go:66` |
| `_cgo_topofstack` | Stack top for CGo | `out.go:67` |
| `_cgo_allocate` | CGo memory allocation | `out.go:75` |
| `_cgo_panic` | CGo panic handler | `out.go:76` |
| `_cgo_reginit` | CGo registration init | `out.go:77` |
| `_cgo_init` | CGo initialization | `runtime/asm_*.s:32` |
| `_cgo_thread_start` | CGo thread start | `runtime/proc.go:226` |
| `_cgo_pthread_key_created` | Pthread key flag | `runtime/proc.go:221` |
| `_cgo_notify_runtime_init_done` | Runtime init notification | `runtime/proc.go:236` |
| `_cgo_setenv` / `_cgo_unsetenv` | Environment variable sync | `runtime/proc.go:229-233` |

---

## 5. Compiler Intrinsics

### 5.1 Atomic Operations (sync/atomic)

Source: `ssagen/intrinsics.go:1263-1312`

These are aliased from `sync/atomic.*` to `internal/runtime/atomic.*`, then lowered to SSA atomic ops:

| sync/atomic Function | Internal Alias | SSA Opcode |
|----------------------|----------------|------------|
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
| `AndInt32/Uint32` | `internal/runtime/atomic.And32` | `OpAtomicAnd32` (ARM64/AMD64/Loong64 only) |
| `OrInt32/Uint32` | `internal/runtime/atomic.Or32` | `OpAtomicOr32` (ARM64/AMD64/Loong64 only) |

**Note**: `sync/atomic.StorePointer` is NOT intrinsic — it requires a write barrier.

Source: `ssagen/intrinsics.go:1276` — `// Note: not StorePointer, that needs a write barrier.`

### 5.2 math/bits Intrinsics

Source: `ssagen/intrinsics.go:900-1000`

| math/bits Function | SSA Opcode | Source Evidence |
|--------------------|------------|-----------------|
| `TrailingZeros64` | `OpCtz64` | `intrinsics.go:901` |
| `TrailingZeros32` | `OpCtz32` | `intrinsics.go:913` |
| `TrailingZeros16` | `OpCtz16` | `intrinsics.go:918` |
| `TrailingZeros8` | `OpCtz8` | `intrinsics.go:923` |
| `LeadingZeros64` | `OpBitLen64` (via subtraction) | `intrinsics.go:977` |
| `LeadingZeros32` | `OpBitLen32` | `intrinsics.go:982` |
| `OnesCount64` | `OpPopCount64` | `intrinsics.go` (AMD64/ARM64) |
| `ReverseBytes64` | `OpBswap64` | `intrinsics.go:953` — aliased to `internal/runtime/sys.Bswap64` |
| `ReverseBytes32` | `OpBswap32` | `intrinsics.go:954` — aliased to `internal/runtime/sys.Bswap32` |
| `ReverseBytes16` | `OpBswap16` | `intrinsics.go:956` |
| `Len64` | `OpBitLen64` | `intrinsics.go:977` |
| `RotateLeft64` | `OpRotateLeft64` | Architecture-specific |

### 5.3 math Intrinsics

Source: `ssagen/intrinsics.go`

| math Function | SSA Opcode |
|---------------|------------|
| `math.Sqrt` | `OpSqrt` |
| `math.Sqrt32` | `OpSqrt32` |
| `math.Floor` | `OpFloor` |
| `math.Ceil` | `OpCeil` |
| `math.Trunc` | `OpTrunc` |
| `math.Abs` | `OpAbs` |
| `math.Copysign` | `OpCopysign` |

### 5.4 Runtime Intrinsics

Source: `ssagen/intrinsics.go:136-167`

| Runtime Function | Intrinsic Behavior | Source Evidence |
|------------------|--------------------|--------------------|
| `runtime.slicebytetostringtmp` | `OpStringMake` (no copy) | `intrinsics.go:137-144` |
| `runtime.KeepAlive` | `OpKeepAlive` | `intrinsics.go:154-160` |
| `runtime.publicationBarrier` | `OpPubBarrier` | `intrinsics.go:162-167` |
| `internal/runtime/sys.GetCallerPC` | `OpGetCallerPC` | `intrinsics.go:170-173` |
| `internal/runtime/sys.GetCallerSP` | `OpGetCallerSP` | `intrinsics.go:176-179` |
| `internal/runtime/sys.GetClosurePtr` | `OpGetClosurePtr` | `intrinsics.go:182-185` |
| `internal/runtime/sys.Bswap32` | `OpBswap32` | `intrinsics.go:188-192` |
| `internal/runtime/sys.Bswap64` | `OpBswap64` | `intrinsics.go:193-197` |
| `runtime.memequal` | `OpMemEq` (ARM64) | `intrinsics.go:199-203` |

---

## 6. Write Barrier Patterns

### 6.1 Write Barrier Mechanism

Source: `ssa/writebarrier.go:151-172`

The write barrier pass rewrites pointer stores into conditional branches:

```
if writeBarrier.enabled {
    buf := gcWriteBarrier2()  // not a regular Go call
    buf[0] = val
    buf[1] = *ptr
}
*ptr = val
```

Key runtime symbols:
- `runtime.writeBarrier` — global variable with `enabled`, `needed`, `cgo` fields (`builtin.go:151`)
- `runtime.gcWriteBarrier{2..8}` — write barrier buffer functions (arch-specific assembly)

Source: `ssa/writebarrier.go:171` — `const maxEntries = 8` — matches `runtime.gcWriteBarrier{X}` instances.

### 6.2 Write Barrier SSA Ops

Source: `ssa/_gen/genericOps.go:405-416`

| Opcode | Args | Description |
|--------|------|-------------|
| `OpStoreWB` | 3 | Store with write barrier (arg0=addr, arg1=val, arg2=mem) |
| `OpMoveWB` | 3 | Move with write barrier (arg0=dst, arg1=src, arg2=mem) |
| `OpZeroWB` | 2 | Zero with write barrier (arg0=dst, arg1=mem) |
| `OpWB` | 1 | Invoke `runtime.gcWriteBarrier` (returns buffer ptr + mem) |
| `OpWBend` | 1 | End of write barrier sequence |

---

## 7. Interface / Type System

### 7.1 Type Descriptors

Source: `reflectdata/reflect.go:552-583`

Type descriptors use the `type:` prefix in the linker:

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `type:.<hash>` | `type:.hash.int` | `reflectdata/alg.go:95` — `TypeSymLookup(".hash." + sig)` |
| `type:.eqfunc.<sig>` | `type:.eqfunc.int` | `reflectdata/alg.go:296` |
| `type:.eq.<sig>` | `type:.eq.int` | `reflectdata/alg.go:330` |
| `type:.<full_type_name>` | `type:.int`, `type:.*os.File` | `reflectdata/reflect.go:559` — `types.TypeSym(t)` |

### 7.2 Interface Tables (itabs)

Source: `reflectdata/reflect.go:591-616`

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `go:itab.<ConcreteType>,<InterfaceType>` | `go:itab.*os.File,io.Reader` | `reflectdata/reflect.go:603` — `typ.LinkString() + "," + iface.LinkString()` |

ITabs are stored in the `go:itab` package namespace.

### 7.3 Type Conversion Functions

Source: `typecheck/builtin.go:97-103`

| Function | When Used |
|----------|-----------|
| `runtime.convT` | General type conversion to interface |
| `runtime.convTnoptr` | Type conversion (no pointers in type) |
| `runtime.convT16` | uint16 to interface |
| `runtime.convT32` | uint32 to interface |
| `runtime.convT64` | uint64 to interface |
| `runtime.convTstring` | string to interface |
| `runtime.convTslice` | slice to interface |

---

## 8. ABI Differences

### 8.1 ABI0 vs ABIInternal

Source: `ssagen/abi.go`, `types/sym.go:74-93`

| Property | ABI0 (Stack-based) | ABIInternal (Register-based) |
|----------|--------------------|-----------------------------|
| Arguments | Passed on stack | Passed in registers |
| Returns | On stack | In registers |
| Used for | Assembly functions, `//go:linkname` targets | Most Go functions |
| Source | `ssagen/abi.go:165` — `fn.ABI = obj.ABI0` | `types/sym.go:77` — `abi = obj.ABIInternal` |

### 8.2 Compiler Pragmas

| Pragma | Effect | Source Evidence |
|--------|--------|-----------------|
| `//go:nosplit` | Skip stack growth check | `ssa/func.go:48` — `NoSplit bool` |
| `//go:noescape` | Arguments don't escape to heap | Standard compiler directive |
| `//go:noinline` | Prevent function inlining | Standard compiler directive |
| `//go:linkname <local> <remote>` | Override symbol name | `types/sym.go:90` — `sym.Linkname` |
| `//go:norace` | Disable race detector for function | Standard compiler directive |
| `//go:nowritebarrier` | Disable write barriers for function | Standard compiler directive |
| `//go:nowritebarrierrec` | Disable write barriers (recursive) | Standard compiler directive |
| `//go:uintptrescapes` | uintptr arguments escape | Standard compiler directive |
| `//go:registerparams` | Force register ABI for function | ABI wrapper generation |

### 8.3 ABI Wrapper Generation

Source: `ssagen/abi.go:236-289`

When a function is called from a different ABI context, the compiler generates wrappers:

```
fn.ABIRefs &^ obj.ABISetOf(fn.ABI)  // need wrapper for other ABIs
```

- ABI0-to-ABIInternal wrappers load params from stack into registers
- ABIInternal-to-ABI0 wrappers store register params to stack

Source: `ssagen/abi.go:283` — `// ABI0-to-ABIInternal wrappers will be mainly loading params from stack into registers`

---

## 9. Init Function Pattern

Source: `pkginit/init.go:26-79`

### 9.1 Initialization Tasks

Go packages have an initialization record (`initTask`) with 3 phases:

1. Initialize all dependent packages
2. Initialize all variables with initializers
3. Run all init functions

Source: `pkginit/init.go:22-25`

### 9.2 Init Function Naming

| Pattern | Description | Source Evidence |
|---------|-------------|-----------------|
| `init` | User-defined init function | Standard Go |
| `init.0`, `init.1`, ... | Multiple init functions per package | `pkginit/init.go:60` — `noder.Renameinit()` |
| `init._` | Compiler-generated init (e.g., ASan) | `pkginit/init.go:60` |
| `<pkg>.inittask` | Package initialization task record | `pkginit/init.go:32` |

---

## 10. Key Takeaways for Static Analysis

### What's user code (analyze these):
- Functions matching `package.FunctionName` pattern (e.g., `main.foo`, `crypto/sha256.Sum`)
- Functions with `//export` names (user-chosen, no prefix)
- C functions called through CGo (appear via `//go:cgo_import_*` pragmas)

### What's compiler runtime (filter/skip these):
- Anything in `runtime.*` (~150 functions declared in `typecheck/builtin.go:25-257`)
- Anything in `internal/runtime/atomic.*` (~20 atomic operations)
- Anything in `internal/runtime/sys.*` (~10 utility functions)
- Anything in `internal/runtime/maps.*` (map implementation helpers)
- Reserved prefixes: `go:`, `type:` (linker internal symbols)
- Type descriptors: `type:.*` (e.g., `type:.hash.int`)

### What's CGo bridge (classify as FFI boundary):
- `//go:cgo_import_static` — static C function import
- `//go:cgo_import_dynamic` — dynamic C function import (shared library)
- `_Cgo_*` functions — CGo helper functions (generated)
- `__cgo_*` variables — static C function references
- `crosscall2`, `_cgo_*` runtime support functions

### What's a memory safety concern:
- `runtime.writeBarrier` — GC write barrier state
- `runtime.mallocgc` — heap allocation (escape analysis target)
- `runtime.growslice` — slice growth (may reallocate)
- `runtime.gopanic` — panic point
- `runtime.memmove` / `runtime.memclrNoHeapPointers` — raw memory operations
- `OpNilCheck` / `OpIsInBounds` / `OpIsSliceInBounds` — safety checks

### What's a concurrency concern:
- `sync/atomic.*` / `internal/runtime/atomic.*` — atomic operations
- `runtime.chanrecv1/2` / `runtime.chansend1` — channel operations
- `runtime.selectgo` — select statement
- `OpGetG` — goroutine-local storage access
- `runtime.raceread/write/readrange/writerange` — race detector hooks

---

## 11. Complete SSA Block Type Map

Source: `ssa/_gen/genericOps.go:743-754`, `ssa/opGen.go:19,165-171,322-328`

| BlockKind | String | Controls | Successors | Description |
|-----------|--------|----------|------------|-------------|
| `BlockInvalid` | `"BlockInvalid"` | - | - | Invalid/uninitialized |
| `BlockPlain` | `"Plain"` | 0 | 1 | Unconditional jump to Succs[0] |
| `BlockIf` | `"If"` | 1 (bool) | 2 | Succs[0] if Controls[0] true, Succs[1] otherwise |
| `BlockDefer` | `"Defer"` | 1 (call) | 2 | Succs[0]=normal, Succs[1]=recovery |
| `BlockRet` | `"Ret"` | 1 (mem) | 0 | Function return |
| `BlockRetJmp` | `"RetJmp"` | 1 | 0 | Tail call return |
| `BlockExit` | `"Exit"` | 1 (mem) | 0 | Panic/exit |
| `BlockJumpTable` | `"JumpTable"` | 1 (int) | N | Table-driven switch |
| `BlockFirst` | `"First"` | 0 | 2 | Dead code elimination (always takes first) |
