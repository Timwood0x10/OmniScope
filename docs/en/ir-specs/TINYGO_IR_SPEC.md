# TinyGo LLVM IR Specification: Compiler-Reserved vs User-Defined

**Source**: `~/code/researcher/tinygo` (main branch)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming Rules

### 1.1 User-Defined Symbols

| Pattern | Example IR Symbol | Source Evidence |
|---------|-------------------|-----------------|
| Default Go function | `main.foo`, `math.Sqrt` | `compiler/symbol.go:321` — `linkName: f.RelString(nil)` |
| `//export <name>` | `myFunc` (user-chosen) | `compiler/symbol.go:387` — `info.linkName = parts[1]` |
| `//go:linkname` | `<target>` (user-chosen) | `compiler/symbol.go:454` — `info.linkName = parts[2]` |
| `//go:extern <name>` on global | `<name>` (user-chosen) | `compiler/symbol.go:761` — `info.linkName = parts[1]` |

### 1.2 Compiler-Reserved Symbols

| Prefix/Pattern | Example | Source Evidence |
|----------------|---------|-----------------|
| `runtime.*` | `runtime.alloc`, `runtime._panic` | `compiler/calls.go:42-56` — `createRuntimeCall()` |
| `internal/task.*` | `internal/task.start` | `compiler/goroutine.go:121` |
| `_Cgo_*` | `_Cgo_foo` (Go-side alias) | `cgo/libclang.go:222` — `Name: "_Cgo_" + name` |
| `_Cgo_static_<hash>_*` | `_Cgo_static_a1b2c3_foo` | `cgo/libclang.go:232` — SHA256 of file path |
| `_Cgo_*` + `//export <c_name>` | LLVM IR = original C name | `cgo/libclang.go:250-256` |
| `reflect/types.type:*` | type descriptor globals | `transform/interface-lowering.go:153` |
| `gc.stackobject` (alloca name) | per-function GC stack slot | `transform/gc.go:228` |
| `stackalloc` (alloca name) | escape-promoted heap→stack | `transform/allocs.go:118` |

### 1.3 CGo-Specific Patterns

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `_Cgo_<c_func>` | `_Cgo_printf` | `cgo/libclang.go:222` |
| `_Cgo_<c_func>$funcaddr` | `_Cgo_printf$funcaddr` | `cgo/cgo.go:1262` — function pointer reference |
| `unionfield_<name>` | `unionfield_d` | `cgo/cgo.go:720` |
| `bitfield_<name>` / `set_bitfield_<name>` | `bitfield_b` | `cgo/cgo.go:835,988` |
| `struct_<name>` / `union_<name>` / `enum_<name>` | `struct_foo`, `enum_color` | `cgo/libclang.go:859-867` |
| `_Ctype_<prefix>__<N>` | `_Ctype_struct__0` | `cgo/libclang.go:869-873` — anonymous records |
| `__bitfield_<N>` | `__bitfield_1` | `cgo/libclang.go:1094` — bitfield storage |
| `$union` (field name) | struct field | `cgo/cgo.go:621` |
| `$<N>` (param name) | `$0`, `$1` | `cgo/libclang.go:290-291` — unnamed params |
| `_type` (renamed field) | C struct `type` → `_type` | `cgo/cgo.go:1467-1487` |

---

## 2. Runtime Functions (appear as `@runtime.*` calls in IR)

### 2.1 Allocation

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.alloc` | `(size, layout) → ptr` | `compiler/compiler.go:2179`, `src/runtime/gc_leaking.go:35` |
| `runtime.free` | `(ptr)` | `src/runtime/gc_blocks.go:503` |
| `runtime.realloc` | `(ptr, size) → ptr` | `src/runtime/gc_blocks.go:481` |

### 2.2 GC / Pointer Tracking

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.trackPointer` | `(ptr, stackChain)` | `compiler/gc.go:84` |

### 2.3 Panic / Recover / Defer

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
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

### 2.4 Channel Operations

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.chanMake` | `(elemSize, bufSize)` | `compiler/channel.go:26` |
| `runtime.chanSend` | `(ch, elem, blocked)` | `compiler/channel.go:51` |
| `runtime.chanRecv` | `(ch, elem, blocked)` | `compiler/channel.go:82` |
| `runtime.chanClose` | `(ch)` | `compiler/channel.go:104` |
| `runtime.chanSelect` | `(...)` | `compiler/channel.go:225` |
| `runtime.chanCap` | `(ch)` | `compiler/compiler.go:1621` |
| `runtime.chanLen` | `(ch)` | `compiler/compiler.go:1739` |

### 2.5 Map / HashMap Operations

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.hashmapMakeGeneric` | `(...)` | `compiler/map.go:54` |
| `runtime.hashmapStringGet` | `(m, key, value)` | `compiler/map.go:97` |
| `runtime.hashmapStringSet` | `(m, key, value)` | `compiler/map.go:136` |
| `runtime.hashmapStringDelete` | `(m, key)` | `compiler/map.go:159` |
| `runtime.hashmapClear` | `(m)` | `compiler/map.go:178` |
| `runtime.hashmapNext` | `(...)` | `compiler/map.go:197` |
| `runtime.hashmapLen` | `(m)` | `compiler/compiler.go:1741` |
| `runtime.hash32` | `(ptr, seed, len)` | `compiler/map.go:420` |
| `runtime.memequal` | `(a, b, size)` | `compiler/map.go:544` |

### 2.6 String Operations

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.stringConcat` | `(...)` | `compiler/compiler.go:2908` |
| `runtime.stringEqual` | `(a, b)` | `compiler/compiler.go:2910` |
| `runtime.stringLess` | `(a, b)` | `compiler/compiler.go:2915` |
| `runtime.stringToBytes` | `(s)` | `compiler/compiler.go:3382` |
| `runtime.stringFromBytes` | `(b)` | `compiler/compiler.go:3227` |
| `runtime.stringToRunes` | `(s)` | `compiler/compiler.go:3384` |
| `runtime.stringFromRunes` | `(r)` | `compiler/compiler.go:3229` |
| `runtime.stringFromUnicode` | `(rune)` | `compiler/compiler.go:3223` |
| `runtime.stringNext` | `(s, i)` | `compiler/compiler.go:2440` |

### 2.7 Interface Operations

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.typeAssert` | `(actualType, assertedType)` | `compiler/interface.go:783` |
| `runtime.interfaceTypeAssert` | `(commaOk)` | `compiler/interface.go:831` |
| `runtime.interfaceEqual` | `(a, b)` | `compiler/compiler.go:2960` |

### 2.8 Slice / Complex / Print

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.sliceAppend` | `(...)` | `compiler/compiler.go:1607` |
| `runtime.complex64div` | `(...)` | `compiler/compiler.go:2875` |
| `runtime.complex128div` | `(...)` | `compiler/compiler.go:2877` |
| `runtime.printlock` | `()` | `compiler/compiler.go:1818` |
| `runtime.printunlock` | `()` | `compiler/compiler.go:1879` |
| `runtime.printstring` | `(s)` | `compiler/compiler.go:1828` |
| `runtime.printnl` | `()` | `compiler/compiler.go:1877` |
| `runtime.printitf` | `(itf)` | `compiler/compiler.go:1860` |

### 2.9 Scheduler / Task

| IR Symbol | Args | Source Evidence |
|-----------|------|-----------------|
| `runtime.deadlock` | `()` | `src/runtime/scheduler_cooperative.go:51` |
| `runtime.Goexit` | `()` | `src/runtime/scheduler.go:56` |
| `internal/task.start` | `(fn, args, stackSize, stackAlloc)` | `compiler/goroutine.go:121` |
| `internal/task.getGoroutineStackSize` | `(fn, args)` | `compiler/goroutine.go:111` |

---

## 3. Compiler Intrinsics (replaced with LLVM builtins)

These never appear as `@runtime.*` calls in the final IR.

| Go Function | LLVM IR | Source Evidence |
|-------------|---------|-----------------|
| `runtime.memcpy` / `runtime.memmove` | `@llvm.memcpy.*` | `compiler/intrinsics.go:22` |
| `runtime.memzero` | `@llvm.memset.*` | `compiler/intrinsics.go:25` |
| `runtime.stacksave` | `@llvm.stacksave` | `compiler/intrinsics.go:26` |
| `runtime.KeepAlive` | inline asm `"" : "r"(ptr)` | `compiler/intrinsics.go:28` |
| `runtime/volatile.Load*` | volatile load | `compiler/intrinsics.go:32` |
| `runtime/volatile.Store*` | volatile store | `compiler/intrinsics.go:34` |
| `sync/atomic.*` | `atomicrmw` / `cmpxchg` / `fence` | `compiler/intrinsics.go:36` |
| `math.Ceil` / `Floor` / `Sqrt` / etc. | `@llvm.ceil.f64` / etc. | `compiler/intrinsics.go:169-175` |
| `math/bits.LeadingZeros*` | `@llvm.ctlz.*` | `compiler/intrinsics.go:239` |
| `math/bits.TrailingZeros*` | `@llvm.cttz.*` | `compiler/intrinsics.go:240` |
| `math/bits.OnesCount*` | `@llvm.ctpop.*` | `compiler/intrinsics.go:286` |
| `math/bits.Reverse*` | `@llvm.bitreverse.*` | `compiler/intrinsics.go:300` |
| `math/bits.ReverseBytes*` | `@llvm.bswap.*` | `compiler/intrinsics.go:306` |
| `math/bits.RotateLeft*` | `@llvm.fshl.*` | `compiler/intrinsics.go:319` |

---

## 4. Transform-Pass Introduced Patterns

| Pass | IR Pattern | Source Evidence |
|------|-----------|-----------------|
| **MakeGCStackSlots** | `%gc.stackobject = alloca {parent, count, ptr0, ptr1, ...}` | `transform/gc.go:228` |
| **OptimizeAllocs** | `%stackalloc = alloca [N x i8]` (replaces `runtime.alloc`) | `transform/allocs.go:118` |
| **LowerInterfaces** | `icmp` dispatch chains in interface invoke functions | `transform/interface-lowering.go:516-604` |
| **LowerInterrupts** | direct handler calls (replaces `runtime/interrupt.callHandlers`) | `transform/interrupt.go:89-98` |
| **CreateStackSizeLoads** | `@internal/task.stackSizes` global in `.tinygo_stacksizes` | `transform/stacksize.go:49` |
| **OptimizeStringToBytes** | eliminates `runtime.stringToBytes` calls | `transform/rtcalls.go:17` |
| **OptimizeStringEqual** | replaces `runtime.stringEqual` with `icmp` | `transform/rtcalls.go:78` |
| **OptimizeMaps** | eliminates dead `runtime.hashmap*` calls | `transform/maps.go:12-17` |

---

## 5. ABI Differences (Exported vs Internal)

| Property | Exported Function | Internal Function |
|----------|-------------------|-------------------|
| Extra context param | No | Yes (`ptr` appended) |
| Source | `compiler/symbol.go:102-104` | same |

Internal Go functions have signature `f(args..., context ptr)` while exported functions (via `//export`, CGo, WASM) omit the context parameter.

---

## 6. Key Takeaways for Static Analysis

### What's user code (analyze these):
- Functions matching `package.FunctionName` pattern (e.g., `main.foo`, `crypto/sha256.Sum`)
- Functions with `//export` names (user-chosen, no prefix)
- C functions called through CGo (appear as their original C names in IR)

### What's compiler runtime (filter/skip these):
- Anything starting with `runtime.` (~65 functions)
- Anything starting with `internal/task.`
- Anything starting with `_Cgo_` (CGo bridge)
- Anything starting with `reflect/types.type:`
- LLVM intrinsics (`@llvm.*`)
- Synthetic alloca names (`gc.stackobject`, `stackalloc`)

### What's CGo bridge (classify as FFI boundary):
- Original C function names (via `//export` in CGo-generated stubs)
- `_Cgo_static_<hash>_<name>` (static C functions)
- `_Cgo_<name>$funcaddr` (C function pointer references)
- `runtime.cgo_CString`, `runtime.cgo_GoString`, etc. (CGo string conversion)

---

## 7. Complete IR Function Attribute Map

Source: `compiler/symbol.go:155-243`

| IR Symbol | Attributes | Source Line |
|-----------|-----------|-------------|
| `abort` | `noreturn` | 159 |
| `runtime.alloc` | `noalias`, `nonnull`, `allockind(alloc)`, `allocsize(0)` | 167-181 |
| `runtime.sliceAppend` | param 2: `nocapture`, `readonly` | 183-186 |
| `runtime.stringFromBytes` | param 1: `nocapture`, `readonly` | 187-189 |
| `runtime.stringFromRunes` | param 1: `nocapture`, `readonly` | 190-192 |
| `runtime.hashmapSet` | params 2,3: `nocapture` | 193-199 |
| `runtime.hashmapGet` | params 2,3: `nocapture` | 200-204 |
| `runtime.hashmapDelete` | param 2: `nocapture` | 205-207 |
| `runtime.trackPointer` | param 1: `nocapture`, `readonly` | 219-223 |
