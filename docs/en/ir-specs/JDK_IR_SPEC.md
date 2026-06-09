# OpenJDK HotSpot IR Specification: Compiler-Reserved vs User-Defined

**Source**: `~/code/researcher/jdk` (mainline)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming Rules

### 1.1 JNI Name Mangling (User-Defined Native Methods)

The JNI specification defines the mapping from a Java `native` method to a C function name.

| Pattern | Example JNI Symbol | Source Evidence |
|---------|-------------------|-----------------|
| `Java_<class>_<method>` (simple) | `Java_java_lang_Object_hashCode` | `prims/nativeLookup.cpp:169-183` -- `pure_jni_name()` |
| `Java_<class>_<method>__<sig>` (overloaded) | `Java_pkg_Cls_method__II` | `prims/nativeLookup.cpp:185-199` -- `long_jni_name()` |
| `/` in class name -> `_` | `java/lang/Object` -> `java_lang_Object` | `prims/nativeLookup.cpp:150-151` |
| `_` in name -> `_1` | `my_method` -> `my_1method` | `prims/nativeLookup.cpp:149` |
| `;` -> `_2` | descriptor `;` -> `_2` | `prims/nativeLookup.cpp:155` |
| `[` -> `_3` | descriptor `[` -> `_3` | `prims/nativeLookup.cpp:156` |
| Non-ASCII char -> `_0wxyz` (hex) | U+ABCD -> `_0abcd` | `prims/nativeLookup.cpp:157` |

**Special JVM-registered natives** (hardcoded, bypass normal lookup):

| JNI Name | Target | Source Evidence |
|----------|--------|-----------------|
| `Java_jdk_internal_misc_Unsafe_registerNatives` | `JVM_RegisterJDKInternalMiscUnsafeMethods` | `prims/nativeLookup.cpp:221` |
| `Java_java_lang_invoke_MethodHandleNatives_registerNatives` | `JVM_RegisterMethodHandleMethods` | `prims/nativeLookup.cpp:222` |
| `Java_jdk_internal_foreign_abi_UpcallStubs_registerNatives` | `JVM_RegisterUpcallHandlerMethods` | `prims/nativeLookup.cpp:223` |
| `Java_jdk_internal_foreign_abi_UpcallLinker_registerNatives` | `JVM_RegisterUpcallLinkerMethods` | `prims/nativeLookup.cpp:224` |
| `Java_jdk_internal_foreign_abi_NativeEntryPoint_registerNatives` | `JVM_RegisterNativeEntryPointMethods` | `prims/nativeLookup.cpp:225` |
| `Java_jdk_internal_vm_vector_VectorSupport_registerNatives` | `JVM_RegisterVectorSupportMethods` | `prims/nativeLookup.cpp:229` |
| `Java_jdk_vm_ci_hotspot_CompilerToVM_registerNatives` | `JVM_RegisterJVMCINatives` | `prims/nativeLookup.cpp:233` |
| `Java_jdk_jfr_internal_JVM_registerNatives` | `jfr_register_natives` | `prims/nativeLookup.cpp:236` |

### 1.2 VM Symbol Table (Compiler-Reserved)

The VM maintains a global symbol table used for fast lookup of well-known class, method, and field names.

| Pattern | Example | Source Evidence |
|---------|---------|-----------------|
| `java_lang_Object` | class symbol | `classfile/vmSymbols.hpp:59` |
| `java_lang_String` | class symbol | `classfile/vmSymbols.hpp:62` |
| `java_lang_Thread` | class symbol | `classfile/vmSymbols.hpp:65` |
| `java_lang_Class` | class symbol | `classfile/vmSymbols.hpp:60` |
| `jdk_internal_misc_Unsafe` | class symbol | `classfile/vmIntrinsics.hpp:667` |
| `sun_misc_Unsafe` | class symbol (legacy) | `classfile/vmIntrinsics.hpp:668` |
| `jdk_internal_misc_ScopedMemoryAccess` | class symbol | `classfile/vmIntrinsics.hpp:669` |

### 1.3 Java Method Signatures in IR

| Type Descriptor | JVM Internal Form | Example |
|----------------|-------------------|---------|
| `boolean` | `Z` | `(Z)V` |
| `byte` | `B` | `(B)V` |
| `char` | `C` | `(C)V` |
| `short` | `S` | `(S)V` |
| `int` | `I` | `(I)V` |
| `long` | `J` | `(J)V` |
| `float` | `F` | `(F)V` |
| `double` | `D` | `(D)V` |
| `void` | `V` | `()V` |
| `Object` | `Ljava/lang/Object;` | `(Ljava/lang/Object;)V` |
| `int[]` | `[I` | `([I)V` |

---

## 2. C2 Compiler (HotSpot) -- Sea of Nodes IR

### 2.1 Node Type Taxonomy

C2 uses a "Sea of Nodes" IR. All node types are enumerated in `classes.hpp`.

#### Arithmetic Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `AddI`, `AddL`, `AddF`, `AddD` | Integer/Float addition | `opto/classes.hpp:34-37` |
| `SubI`, `SubL`, `SubF`, `SubD` | Subtraction | `opto/classes.hpp:374-377` |
| `MulI`, `MulL`, `MulF`, `MulD` | Multiplication | `opto/classes.hpp:271-272` |
| `DivI`, `DivL`, `DivF`, `DivD` | Division | `opto/classes.hpp:174-177` |
| `ModI`, `ModL`, `ModF`, `ModD` | Modulo | `opto/classes.hpp:254-257` |
| `NegI`, `NegL`, `NegF`, `NegD` | Negation | `opto/classes.hpp:274-277` |
| `AbsI`, `AbsL`, `AbsF`, `AbsD` | Absolute value | `opto/classes.hpp:30-33` |
| `MaxI`, `MaxL`, `MaxF`, `MaxD` | Maximum | `opto/classes.hpp:229-233` |
| `MinI`, `MinL`, `MinF`, `MinD` | Minimum | `opto/classes.hpp:247-250` |
| `SqrtD`, `SqrtF` | Square root | `opto/classes.hpp:351-352` |
| `PowD`, `ExpD` | Power, Exponential | `opto/classes.hpp:289` |
| `LogD`, `Log10D` | Logarithm | `opto/classes.hpp` |
| `SinD`, `CosD`, `TanD` | Trigonometric | `opto/classes.hpp` |
| `FmaD`, `FmaF`, `FmaHF` | Fused multiply-add | `opto/classes.hpp:190-192` |
| `MulHiL`, `UMulHiL` | High bits of multiply | `opto/classes.hpp:269-270` |

#### Overflow-Checking Arithmetic

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `OverflowAddI`, `OverflowAddL` | Overflow-checked add | `opto/classes.hpp:293-296` |
| `OverflowSubI`, `OverflowSubL` | Overflow-checked subtract | `opto/classes.hpp:294-297` |
| `OverflowMulI`, `OverflowMulL` | Overflow-checked multiply | `opto/classes.hpp:295-298` |

#### Bitwise / Shift Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `AndI`, `AndL` | Bitwise AND | `opto/classes.hpp:42-43` |
| `OrI`, `OrL` | Bitwise OR | `opto/classes.hpp:291-292` |
| `XorI`, `XorL` | Bitwise XOR | `opto/classes.hpp:388-389` |
| `LShiftI`, `LShiftL` | Left shift | `opto/classes.hpp:205-206` |
| `RShiftI`, `RShiftL` | Arithmetic right shift | `opto/classes.hpp:312-313` |
| `URShiftI`, `URShiftL` | Logical right shift | `opto/classes.hpp:386-387` |
| `RotateLeft`, `RotateRight` | Bit rotation | `opto/classes.hpp:323-326` |
| `ReverseI`, `ReverseL` | Bit reversal | `opto/classes.hpp:317-318` |
| `ReverseBytesI`, `ReverseBytesL` | Byte swap | `opto/classes.hpp:52-53` |
| `PopCountI`, `PopCountL` | Population count | `opto/classes.hpp:305-306` |
| `CountLeadingZerosI`, `CountLeadingZerosL` | CLZ | `opto/classes.hpp:164-165` |
| `CountTrailingZerosI`, `CountTrailingZerosL` | CTZ | `opto/classes.hpp:167-168` |
| `CompressBits`, `ExpandBits` | Bit compress/expand | `opto/classes.hpp:82-83` |

#### Memory Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `LoadB`, `LoadUB` | Load byte / unsigned byte | `opto/classes.hpp:207-208` |
| `LoadS`, `LoadUS` | Load short / unsigned short | `opto/classes.hpp:210,221` |
| `LoadI`, `LoadL` | Load int / long | `opto/classes.hpp:213,216` |
| `LoadF`, `LoadD` | Load float / double | `opto/classes.hpp:212,210` |
| `LoadP`, `LoadN` | Load pointer / narrow oop | `opto/classes.hpp:218-219` |
| `LoadKlass`, `LoadNKlass` | Load klass pointer | `opto/classes.hpp:214-215` |
| `LoadRange` | Load array length | `opto/classes.hpp:220` |
| `StoreB`, `StoreC` | Store byte / char | `opto/classes.hpp:358-359` |
| `StoreI`, `StoreL` | Store int / long | `opto/classes.hpp:361-362` |
| `StoreF`, `StoreD` | Store float / double | `opto/classes.hpp:360,359` |
| `StoreP`, `StoreN` | Store pointer / narrow oop | `opto/classes.hpp:364-365` |
| `ClearArray` | Zero-fill memory | `opto/classes.hpp:80` |
| `ArrayCopy` | Bulk array copy | `opto/classes.hpp:44` |
| `Initialize` | Object initialization | `opto/classes.hpp:201` |
| `PrefetchAllocation` | Prefetch for allocation | `opto/classes.hpp:310` |

#### Control Flow Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `If`, `IfFalse`, `IfTrue` | Conditional branch | `opto/classes.hpp:197-200` |
| `Goto` | Unconditional branch | `opto/classes.hpp:194` |
| `Return` | Method return | `opto/classes.hpp:316` |
| `Halt` | Program halt | `opto/classes.hpp:195` |
| `Rethrow` | Exception rethrow | `opto/classes.hpp:315` |
| `Catch`, `CatchProj` | Exception catch | `opto/classes.hpp:77-78` |
| `Jump`, `JumpProj` | Switch jump | `opto/classes.hpp:203-204` |
| `PCTable` | PC mapping table | `opto/classes.hpp:299` |
| `Region` | Merge control | `opto/classes.hpp:314` |
| `Loop`, `CountedLoop` | Loop headers | `opto/classes.hpp:223,158` |
| `CountedLoopEnd` | Loop exit | `opto/classes.hpp:159` |
| `SafePoint` | GC safepoint | `opto/classes.hpp:327` |
| `Start`, `StartOSR` | Method entry | `opto/classes.hpp:356-357` |
| `Root` | Graph root | `opto/classes.hpp:320` |
| `Parm` | Method parameter | `opto/classes.hpp:300` |
| `Phi` | SSA phi node | `opto/classes.hpp:304` |
| `Mach` | Machine instruction | `opto/classes.hpp:225` |
| `MachProj` | Machine projection | `opto/classes.hpp:227` |
| `MachNullCheck` | Null check | `opto/classes.hpp:226` |

#### Object Allocation Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `Allocate` | Object allocation | `opto/classes.hpp:40` |
| `AllocateArray` | Array allocation | `opto/classes.hpp:41` |

#### Lock / Monitor Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `FastLock` | Optimized monitor enter | `opto/classes.hpp:188` |
| `FastUnlock` | Optimized monitor exit | `opto/classes.hpp:189` |
| `Lock` | Monitor enter | `opto/classes.hpp:222` |
| `Unlock` | Monitor exit | `opto/classes.hpp:383` |

#### Atomic / CAS Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `CompareAndSwapB/S/I/L/P/N` | Compare-and-swap | `opto/classes.hpp:106-111` |
| `WeakCompareAndSwapB/S/I/L/P/N` | Weak CAS | `opto/classes.hpp:112-117` |
| `CompareAndExchangeB/S/I/L/P/N` | CAS returning old value | `opto/classes.hpp:118-123` |
| `GetAndAddB/S/I/L` | Atomic fetch-and-add | `opto/classes.hpp:124-127` |
| `GetAndSetB/S/I/L/P/N` | Atomic swap | `opto/classes.hpp:128-133` |

#### Memory Barrier Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `MemBarAcquire` | Load fence | `opto/classes.hpp:234` |
| `MemBarRelease` | Store fence | `opto/classes.hpp:238` |
| `MemBarVolatile` | Full fence (volatile) | `opto/classes.hpp:243` |
| `MemBarStoreLoad` | StoreLoad barrier | `opto/classes.hpp:242` |
| `MemBarStoreStore` | StoreStore barrier | `opto/classes.hpp:244` |
| `MemBarFull` | Full memory barrier | `opto/classes.hpp:245` |
| `MemBarCPUOrder` | CPU ordering barrier | `opto/classes.hpp:237` |
| `MemBarAcquireLock` | Lock acquisition barrier | `opto/classes.hpp:236` |
| `MemBarReleaseLock` | Lock release barrier | `opto/classes.hpp:241` |
| `LoadFence` | Load fence (Unsafe) | `opto/classes.hpp:235` |
| `StoreFence` | Store fence (Unsafe) | `opto/classes.hpp:239` |
| `StoreStoreFence` | StoreStore fence | `opto/classes.hpp:240` |

#### Type / Conversion Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `ConvI2L`, `ConvL2I` | Int/Long conversion | `opto/classes.hpp:152,155` |
| `ConvI2F`, `ConvI2D` | Int to Float/Double | `opto/classes.hpp:150-151` |
| `ConvF2I`, `ConvF2L` | Float to Int/Long | `opto/classes.hpp:148-149` |
| `ConvD2I`, `ConvD2L`, `ConvD2F` | Double conversions | `opto/classes.hpp:146-148` |
| `ConvL2D`, `ConvL2F` | Long to Float/Double | `opto/classes.hpp:153-154` |
| `Conv2B` | Convert to boolean | `opto/classes.hpp:143` |
| `ConvF2HF`, `ConvHF2F` | Float16 conversions | `opto/classes.hpp:156-157` |
| `CastII`, `CastLL`, `CastFF`, `CastDD` | Type narrowing cast | `opto/classes.hpp:71-74` |
| `CastPP` | Pointer cast | `opto/classes.hpp:76` |
| `CheckCastPP` | Checked pointer cast | `opto/classes.hpp:79` |
| `DecodeN`, `DecodeNKlass` | Decode narrow oop/klass | `opto/classes.hpp:171-172` |
| `EncodeP`, `EncodePKlass` | Encode pointer/klass | `opto/classes.hpp:186-187` |
| `CastX2P`, `CastP2X` | Integer<->pointer cast | `opto/classes.hpp:75-76` |

#### String Intrinsics Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `StrComp` | String comparison | `opto/classes.hpp:367` |
| `StrEquals` | String equality | `opto/classes.hpp:369` |
| `StrIndexOf` | String indexOf | `opto/classes.hpp:370` |
| `StrIndexOfChar` | String indexOf char | `opto/classes.hpp:371` |
| `StrCompressedCopy` | Copy with compression | `opto/classes.hpp:368` |
| `StrInflatedCopy` | Copy with inflation | `opto/classes.hpp:372` |
| `AryEq` | Array equality | `opto/classes.hpp:45` |
| `CountPositives` | Count positive bytes | `opto/classes.hpp:196` |
| `EncodeISOArray` | ISO encoding | `opto/classes.hpp:185` |
| `Digit`, `UpperCase`, `LowerCase`, `Whitespace` | Character classification | `opto/classes.hpp:513-518` |

#### Call Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `CallStaticJava` | Static method call | `opto/classes.hpp:67` |
| `CallDynamicJava` | Virtual/interface call | `opto/classes.hpp:60` |
| `CallJava` | Java method call (base) | `opto/classes.hpp:61` |
| `CallRuntime` | Runtime call | `opto/classes.hpp:66` |
| `CallLeaf` | Native leaf call | `opto/classes.hpp:62` |
| `CallLeafNoFP` | Native leaf, no FP | `opto/classes.hpp:63` |
| `CallLeafPure` | Pure native leaf | `opto/classes.hpp:64` |
| `CallLeafVector` | Vector native leaf | `opto/classes.hpp:65` |
| `TailCall` | Tail call | `opto/classes.hpp:378` |
| `TailJump` | Tail jump | `opto/classes.hpp:379` |

### 2.2 GC-Specific C2 Nodes

| Node Class | GC | Purpose | Source Evidence |
|------------|-----|---------|-----------------|
| `ShenandoahCompareAndExchangeP` | Shenandoah | CAS on oop | `opto/classes.hpp:335` |
| `ShenandoahCompareAndExchangeN` | Shenandoah | CAS on narrow oop | `opto/classes.hpp:336` |
| `ShenandoahCompareAndSwapN` | Shenandoah | CAS narrow oop | `opto/classes.hpp:337` |
| `ShenandoahCompareAndSwapP` | Shenandoah | CAS oop | `opto/classes.hpp:338` |
| `ShenandoahWeakCompareAndSwapN` | Shenandoah | Weak CAS narrow | `opto/classes.hpp:339` |
| `ShenandoahWeakCompareAndSwapP` | Shenandoah | Weak CAS oop | `opto/classes.hpp:340` |
| `ShenandoahLoadReferenceBarrier` | Shenandoah | Load reference barrier | `opto/classes.hpp:341` |

### 2.3 Vector / SIMD Nodes

| Node Class | Purpose | Source Evidence |
|------------|---------|-----------------|
| `LoadVector`, `StoreVector` | Vector load/store | `opto/classes.hpp:475,478` |
| `LoadVectorGather`, `StoreVectorScatter` | Gather/scatter | `opto/classes.hpp:476,479` |
| `AddVI`, `AddVL`, `AddVF`, `AddVD` | Vector add | `opto/classes.hpp:393-401` |
| `MulVI`, `MulVL`, `MulVF`, `MulVD` | Vector multiply | `opto/classes.hpp:412-419` |
| `DivVF`, `DivVD` | Vector divide | `opto/classes.hpp:428-429` |
| `AndV`, `OrV`, `XorV` | Vector bitwise | `opto/classes.hpp:456-461` |
| `LShiftVI`, `RShiftVI` | Vector shift | `opto/classes.hpp:444-455` |
| `MinV`, `MaxV` | Vector min/max | `opto/classes.hpp:462-471` |
| `FmaVD`, `FmaVF` | Vector FMA | `opto/classes.hpp:423-425` |
| `VectorBox`, `VectorBoxAllocate` | Vector boxing | `opto/classes.hpp:520-521` |
| `VectorUnbox` | Vector unboxing | `opto/classes.hpp:522` |
| `VectorCastB2X`, `VectorCastI2X`, etc. | Vector type cast | `opto/classes.hpp:535-543` |
| `VectorReinterpret` | Vector reinterpret | `opto/classes.hpp:533` |
| `VectorMaskGen`, `VectorMaskCmp` | Mask operations | `opto/classes.hpp:485,524` |
| `PopCountVI`, `PopCountVL` | Vector popcount | `opto/classes.hpp:307-308` |

### 2.4 C2 Access Decorators (Memory Access Metadata)

| Decorator | Value | Purpose | Source Evidence |
|-----------|-------|---------|-----------------|
| `C2_MISMATCHED` | `DECORATOR_LAST << 1` | Mismatched type access | `gc/shared/c2/barrierSetC2.hpp:38` |
| `C2_UNALIGNED` | `DECORATOR_LAST << 2` | Unaligned access | `gc/shared/c2/barrierSetC2.hpp:40` |
| `C2_WEAK_CMPXCHG` | `DECORATOR_LAST << 3` | Weak compare-and-swap | `gc/shared/c2/barrierSetC2.hpp:43` |
| `C2_CONTROL_DEPENDENT_LOAD` | `DECORATOR_LAST << 4` | Control-dependent load | `gc/shared/c2/barrierSetC2.hpp:45` |
| `C2_UNKNOWN_CONTROL_LOAD` | `DECORATOR_LAST << 5` | Load pinning (may float above safepoints) | `gc/shared/c2/barrierSetC2.hpp:47` |
| `C2_UNSAFE_ACCESS` | `DECORATOR_LAST << 6` | From Unsafe intrinsic | `gc/shared/c2/barrierSetC2.hpp:49` |
| `C2_WRITE_ACCESS` | `DECORATOR_LAST << 7` | Write access | `gc/shared/c2/barrierSetC2.hpp:51` |
| `C2_READ_ACCESS` | `DECORATOR_LAST << 8` | Read access | `gc/shared/c2/barrierSetC2.hpp:53` |
| `C2_TIGHTLY_COUPLED_ALLOC` | `DECORATOR_LAST << 9` | Nearby allocation | `gc/shared/c2/barrierSetC2.hpp:55` |
| `C2_ARRAY_COPY` | `DECORATOR_LAST << 10` | Arraycopy optimization | `gc/shared/c2/barrierSetC2.hpp:57` |
| `C2_IMMUTABLE_MEMORY` | `DECORATOR_LAST << 11` | Immutable memory | `gc/shared/c2/barrierSetC2.hpp:59` |

---

## 3. C1 Compiler IR

### 3.1 Instruction Class Hierarchy

C1 uses a simpler HIR (High-level IR) with a class hierarchy.

| Instruction Class | Purpose | Source Evidence |
|-------------------|---------|-----------------|
| `Phi` | SSA phi function | `c1/c1_Instruction.hpp:47` |
| `Local` | Local variable | `c1/c1_Instruction.hpp:48` |
| `Constant` | Constant value | `c1/c1_Instruction.hpp:49` |
| `LoadField`, `StoreField` | Field access | `c1/c1_Instruction.hpp:51-52` |
| `ArrayLength` | Array length | `c1/c1_Instruction.hpp:54` |
| `LoadIndexed`, `StoreIndexed` | Array element access | `c1/c1_Instruction.hpp:56-57` |
| `ArithmeticOp`, `ShiftOp`, `LogicOp` | Arithmetic / bitwise | `c1/c1_Instruction.hpp:60-62` |
| `CompareOp`, `IfOp` | Comparison / conditional | `c1/c1_Instruction.hpp:63-64` |
| `Convert` | Type conversion | `c1/c1_Instruction.hpp:65` |
| `NullCheck` | Null pointer check | `c1/c1_Instruction.hpp:66` |
| `Invoke` | Method call | `c1/c1_Instruction.hpp:71` |
| `NewInstance`, `NewArray` | Object allocation | `c1/c1_Instruction.hpp:72-73` |
| `NewTypeArray`, `NewObjectArray`, `NewMultiArray` | Specialized array alloc | `c1/c1_Instruction.hpp:74-76` |
| `CheckCast`, `InstanceOf` | Type checks | `c1/c1_Instruction.hpp:78-79` |
| `MonitorEnter`, `MonitorExit` | Lock/unlock | `c1/c1_Instruction.hpp:81-82` |
| `Intrinsic` | Compiler intrinsic call | `c1/c1_Instruction.hpp:83` |
| `Goto`, `If`, `Switch`, `Return`, `Throw` | Control flow | `c1/c1_Instruction.hpp:86-93` |
| `UnsafeGet`, `UnsafePut`, `UnsafeGetAndSet` | Unsafe memory access | `c1/c1_Instruction.hpp:95-97` |
| `MemBar` | Memory barrier | `c1/c1_Instruction.hpp:102` |
| `RuntimeCall` | Runtime call | `c1/c1_Instruction.hpp:101` |
| `RangeCheckPredicate` | Range check elimination | `c1/c1_Instruction.hpp:103` |

---

## 4. GC Barrier Patterns

### 4.1 Barrier Set Implementations

| Barrier Set | GC | Source Evidence |
|-------------|-----|-----------------|
| `CardTableBarrierSet` | Serial, Parallel | `gc/shared/barrierSetConfig.hpp:32` |
| `G1BarrierSet` | G1 | `gc/shared/barrierSetConfig.hpp:33` |
| `ShenandoahBarrierSet` | Shenandoah | `gc/shared/barrierSetConfig.hpp:34` |
| `ZBarrierSet` | ZGC | `gc/shared/barrierSetConfig.hpp:35` |
| `EpsilonBarrierSet` | Epsilon (no-op) | `gc/shared/barrierSetConfig.hpp:33` |

### 4.2 G1 GC Barriers

| Barrier Type | Mechanism | Source Evidence |
|-------------|-----------|-----------------|
| **SATB write barrier** | Snapshot-At-The-Beginning marking | `gc/g1/g1BarrierSet.hpp:68` -- `_satb_mark_queue_set` |
| **Card table write barrier** | Dirty card marking for cross-region refs | `gc/g1/g1BarrierSet.hpp:66` -- extends `CardTableBarrierSet` |
| **Refinement table** | Double-buffered card table for concurrent refinement | `gc/g1/g1BarrierSet.hpp:71` -- `_refinement_table` |

### 4.3 ZGC Barriers

| Barrier Type | Mechanism | Source Evidence |
|-------------|-----------|-----------------|
| **Load barrier (shift-based)** | Pointer load checks metadata bits, shifts to remove them | `gc/z/zBarrier.hpp:31-67` |
| **Store barrier** | Store barrier buffering | `gc/z/zBarrierSet.hpp` |
| **NMethod entry barrier** | Patches load barrier shift values per GC phase | `gc/z/zBarrier.hpp:45` |

ZGC uses colored pointers with metadata bits. The load barrier applies a shift to strip metadata:
- If result is null: ZF flag set (fast path)
- If result has CF set: good pointer (fast path)
- Otherwise: slow path (pointer needs healing)

### 4.4 Shenandoah GC Barriers

| Barrier Type | Mechanism | Source Evidence |
|-------------|-----------|-----------------|
| **Load reference barrier** | Resolves forwarded pointers on load | `gc/shenandoah/shenandoahBarrierSet.hpp:61` |
| **SATB write barrier** | Snapshot-At-The-Beginning | `gc/shenandoah/shenandoahBarrierSet.hpp:57` -- `_satb_mark_queue_set` |
| **Card barrier** | Card marking for heap refs | `gc/shenandoah/shenandoahBarrierSet.hpp:64` |
| **Keep-alive barrier** | Prevents premature collection | `gc/shenandoah/shenandoahBarrierSet.hpp:62` |
| **Strong/Weak/Phantom access** | Decorator-based barrier selection | `gc/shenandoah/shenandoahBarrierSet.hpp:66-80` |

### 4.5 Card Table Barrier

| Barrier Type | Mechanism | Source Evidence |
|-------------|-----------|-----------------|
| **Card table write barrier** | Marks dirty cards on pointer stores | `gc/shared/cardTableBarrierSet.hpp` |
| **C2 integration** | `CardTableBarrierSetC2` generates C2 IR | `gc/shared/c2/cardTableBarrierSetC2.hpp` |

---

## 5. VM Intrinsics (Compiler-Replaced Methods)

### 5.1 Math Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_dabs`, `_fabs`, `_iabs`, `_labs` | `Math.abs` | `classfile/vmIntrinsics.hpp:154-157` |
| `_dsin`, `_dcos`, `_dtan` | `Math.sin/cos/tan` | `classfile/vmIntrinsics.hpp:158,162-163` |
| `_datan2` | `Math.atan2` | `classfile/vmIntrinsics.hpp:164` |
| `_dsqrt` | `Math.sqrt` | `classfile/vmIntrinsics.hpp:168` |
| `_dlog`, `_dlog10` | `Math.log/log10` | `classfile/vmIntrinsics.hpp:169-170` |
| `_dpow` | `Math.pow` | `classfile/vmIntrinsics.hpp:171` |
| `_dexp` | `Math.exp` | `classfile/vmIntrinsics.hpp:172` |
| `_floor`, `_ceil`, `_rint` | `Math.floor/ceil/rint` | `classfile/vmIntrinsics.hpp:159-161` |
| `_addExactI`, `_addExactL` | `Math.addExact` (overflow-checking) | `classfile/vmIntrinsics.hpp:175-176` |
| `_multiplyExactI`, `_multiplyExactL` | `Math.multiplyExact` | `classfile/vmIntrinsics.hpp:181-182` |
| `_subtractExactI`, `_subtractExactL` | `Math.subtractExact` | `classfile/vmIntrinsics.hpp:187-188` |
| `_negateExactI`, `_negateExactL` | `Math.negateExact` | `classfile/vmIntrinsics.hpp:185-186` |
| `_fmaD`, `_fmaF` | `Math.fma` | `classfile/vmIntrinsics.hpp:189-190` |
| `_roundD`, `_roundF` | `Math.round` | `classfile/vmIntrinsics.hpp:197-198` |
| `_dcopySign`, `_fcopySign` | `Math.copySign` | `classfile/vmIntrinsics.hpp:199-200` |
| `_dsignum`, `_fsignum` | `Math.signum` | `classfile/vmIntrinsics.hpp:201-202` |

### 5.2 Integer Bit-Manipulation Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_numberOfLeadingZeros_i/l` | `Integer/Long.numberOfLeadingZeros` | `classfile/vmIntrinsics.hpp:251-252` |
| `_numberOfTrailingZeros_i/l` | `Integer/Long.numberOfTrailingZeros` | `classfile/vmIntrinsics.hpp:254-255` |
| `_bitCount_i/l` | `Integer/Long.bitCount` | `classfile/vmIntrinsics.hpp:257-258` |
| `_reverse_i/l` | `Integer/Long.reverse` | `classfile/vmIntrinsics.hpp:265-267` |
| `_reverseBytes_i/l/c/s` | `Integer/Long/Character/Short.reverseBytes` | `classfile/vmIntrinsics.hpp:268-274` |
| `_compress_i/l` | `Integer/Long.compress` | `classfile/vmIntrinsics.hpp:259-261` |
| `_expand_i/l` | `Integer/Long.expand` | `classfile/vmIntrinsics.hpp:262-263` |
| `_compareUnsigned_i/l` | `Integer/Long.compareUnsigned` | `classfile/vmIntrinsics.hpp:240-241` |
| `_divideUnsigned_i/l` | `Integer/Long.divideUnsigned` | `classfile/vmIntrinsics.hpp:244,247` |
| `_remainderUnsigned_i/l` | `Integer/Long.remainderUnsigned` | `classfile/vmIntrinsics.hpp:245,248` |

### 5.3 Float/Double Bit Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_floatToRawIntBits` | `Float.floatToRawIntBits` | `classfile/vmIntrinsics.hpp:221` |
| `_floatToIntBits` | `Float.floatToIntBits` | `classfile/vmIntrinsics.hpp:223` |
| `_intBitsToFloat` | `Float.intBitsToFloat` | `classfile/vmIntrinsics.hpp:225` |
| `_doubleToRawLongBits` | `Double.doubleToRawLongBits` | `classfile/vmIntrinsics.hpp:227` |
| `_doubleToLongBits` | `Double.doubleToLongBits` | `classfile/vmIntrinsics.hpp:229` |
| `_longBitsToDouble` | `Double.longBitsToDouble` | `classfile/vmIntrinsics.hpp:231` |
| `_float16ToFloat` | `Float.float16ToFloat` | `classfile/vmIntrinsics.hpp:233` |
| `_floatToFloat16` | `Float.floatToFloat16` | `classfile/vmIntrinsics.hpp:236` |

### 5.4 System / Runtime Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_identityHashCode` | `System.identityHashCode` | `classfile/vmIntrinsics.hpp:277` |
| `_currentTimeMillis` | `System.currentTimeMillis` | `classfile/vmIntrinsics.hpp:279` |
| `_nanoTime` | `System.nanoTime` | `classfile/vmIntrinsics.hpp:282` |
| `_arraycopy` | `System.arraycopy` | `classfile/vmIntrinsics.hpp:287` |
| `_currentThread` | `Thread.currentThread` | `classfile/vmIntrinsics.hpp:293` |
| `_currentCarrierThread` | `Thread.currentCarrierThread` | `classfile/vmIntrinsics.hpp:291` |
| `_onSpinWait` | `Thread.onSpinWait` | `classfile/vmIntrinsics.hpp:330` |
| `_getCallerClass` | `Reflection.getCallerClass` | `classfile/vmIntrinsics.hpp:323` |
| `_Reference_get0` | `Reference.get0` | `classfile/vmIntrinsics.hpp:466` |
| `_Reference_refersTo0` | `Reference.refersTo0` | `classfile/vmIntrinsics.hpp:467` |
| `_Reference_reachabilityFence` | `Reference.reachabilityFence` | `classfile/vmIntrinsics.hpp:472` |
| `_blackhole` | `Object.blackhole` (Blackhole node) | `classfile/vmIntrinsics.hpp:715` |

### 5.5 String Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_compressStringC/B` | `StringUTF16.compress0` | `classfile/vmIntrinsics.hpp:362-364` |
| `_inflateStringC/B` | `StringLatin1.inflate0` | `classfile/vmIntrinsics.hpp:365-369` |
| `_compareToL/U/LU/UL` | `StringLatin1/UTF16.compareTo0` | `classfile/vmIntrinsics.hpp:380-387` |
| `_indexOfL/U/UL/IL/IU/IUL` | `StringLatin1/UTF16.indexOf0` | `classfile/vmIntrinsics.hpp:388-398` |
| `_equalsL` | `StringLatin1.equals0` | `classfile/vmIntrinsics.hpp:401` |
| `_countPositives` | `StringCoding.countPositives0` | `classfile/vmIntrinsics.hpp:419` |
| `_encodeISOArray` | `ISO_8859_1$Encoder.encodeISOArray0` | `classfile/vmIntrinsics.hpp:424` |
| `_toBytesStringU` | `StringUTF16.toBytes0` | `classfile/vmIntrinsics.hpp:370` |
| `_getCharsStringU` | `StringUTF16.getChars0` | `classfile/vmIntrinsics.hpp:373` |

### 5.6 Array Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_copyOf` | `Arrays.copyOf` | `classfile/vmIntrinsics.hpp:337` |
| `_copyOfRange` | `Arrays.copyOfRange` | `classfile/vmIntrinsics.hpp:349` |
| `_equalsC`, `_equalsB` | `Arrays.equals(char[], char[])` etc. | `classfile/vmIntrinsics.hpp:353-356` |
| `_arraySort` | `DualPivotQuicksort.sort` | `classfile/vmIntrinsics.hpp:341` |
| `_arrayPartition` | `DualPivotQuicksort.partition` | `classfile/vmIntrinsics.hpp:345` |
| `_vectorizedHashCode` | `ArraysSupport.vectorizedHashCode` | `classfile/vmIntrinsics.hpp:358` |
| `_vectorizedMismatch` | `ArraysSupport.vectorizedMismatch` | `classfile/vmIntrinsics.hpp:461` |

### 5.7 Crypto / Hash Intrinsics

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_aescrypt_encryptBlock/decryptBlock` | `AES_Crypt.implEncryptBlock/DecryptBlock` | `classfile/vmIntrinsics.hpp:477-478` |
| `_cipherBlockChaining_encryptAESCrypt/decryptAESCrypt` | `CipherBlockChaining.implEncrypt/Decrypt` | `classfile/vmIntrinsics.hpp:484-485` |
| `_counterMode_AESCrypt` | `CounterMode.implCrypt` | `classfile/vmIntrinsics.hpp:497` |
| `_galoisCounterMode_AESCrypt` | `GaloisCounterMode.implGCMCrypt0` | `classfile/vmIntrinsics.hpp:501` |
| `_md5_implCompress` | `MD5.implCompress0` | `classfile/vmIntrinsics.hpp:507` |
| `_sha_implCompress` | `SHA.implCompress0` | `classfile/vmIntrinsics.hpp:513` |
| `_sha2_implCompress` | `SHA2.implCompress0` | `classfile/vmIntrinsics.hpp:517` |
| `_sha5_implCompress` | `SHA5.implCompress0` | `classfile/vmIntrinsics.hpp:521` |
| `_sha3_implCompress` | `SHA3.implCompress0` | `classfile/vmIntrinsics.hpp:525` |
| `_updateCRC32` | `CRC32.update` | `classfile/vmIntrinsics.hpp:621` |
| `_updateBytesCRC32` | `CRC32.updateBytes0` | `classfile/vmIntrinsics.hpp:623` |
| `_poly1305_processBlocks` | `Poly1305.processMultipleBlocks` | `classfile/vmIntrinsics.hpp:569` |
| `_chacha20Block` | `ChaCha20Cipher.implChaCha20Block` | `classfile/vmIntrinsics.hpp:574` |

### 5.8 Post-Quantum Crypto Intrinsics (ML-KEM, ML-DSA)

| Intrinsic ID | Java Method | Source Evidence |
|-------------|-------------|-----------------|
| `_kyberNtt` | `ML_KEM.implKyberNtt` | `classfile/vmIntrinsics.hpp:586` |
| `_kyberInverseNtt` | `ML_KEM.implKyberInverseNtt` | `classfile/vmIntrinsics.hpp:588` |
| `_kyberNttMult` | `ML_KEM.implKyberNttMult` | `classfile/vmIntrinsics.hpp:590` |
| `_dilithiumAlmostNtt` | `ML_DSA.implDilithiumAlmostNtt` | `classfile/vmIntrinsics.hpp:606` |
| `_dilithiumNttMult` | `ML_DSA.implDilithiumNttMult` | `classfile/vmIntrinsics.hpp:610` |

---

## 6. Unsafe Operations (sun.misc.Unsafe / jdk.internal.misc.Unsafe)

### 6.1 Object Field Access (Plain)

| Intrinsic ID | Method Name | Signature | Source Evidence |
|-------------|-------------|-----------|-----------------|
| `_getReference` | `getReference` | `(Object, long) -> Object` | `classfile/vmIntrinsics.hpp:747` |
| `_getBoolean` | `getBoolean` | `(Object, long) -> boolean` | `classfile/vmIntrinsics.hpp:748` |
| `_getByte` | `getByte` | `(Object, long) -> byte` | `classfile/vmIntrinsics.hpp:749` |
| `_getShort` | `getShort` | `(Object, long) -> short` | `classfile/vmIntrinsics.hpp:750` |
| `_getChar` | `getChar` | `(Object, long) -> char` | `classfile/vmIntrinsics.hpp:751` |
| `_getInt` | `getInt` | `(Object, long) -> int` | `classfile/vmIntrinsics.hpp:752` |
| `_getLong` | `getLong` | `(Object, long) -> long` | `classfile/vmIntrinsics.hpp:753` |
| `_putReference` | `putReference` | `(Object, long, Object) -> void` | `classfile/vmIntrinsics.hpp:756` |
| `_putInt` | `putInt` | `(Object, long, int) -> void` | `classfile/vmIntrinsics.hpp:761` |
| `_putLong` | `putLong` | `(Object, long, long) -> void` | `classfile/vmIntrinsics.hpp:762` |

### 6.2 Volatile Access (Sequentially Consistent)

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_getReferenceVolatile` | `getReferenceVolatile` | `classfile/vmIntrinsics.hpp:776` |
| `_getIntVolatile` | `getIntVolatile` | `classfile/vmIntrinsics.hpp:781` |
| `_putReferenceVolatile` | `putReferenceVolatile` | `classfile/vmIntrinsics.hpp:785` |
| `_putIntVolatile` | `putIntVolatile` | `classfile/vmIntrinsics.hpp:790` |

### 6.3 Opaque Access (Compiler Cannot Optimize)

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_getReferenceOpaque` | `getReferenceOpaque` | `classfile/vmIntrinsics.hpp:805` |
| `_getIntOpaque` | `getIntOpaque` | `classfile/vmIntrinsics.hpp:810` |
| `_putReferenceOpaque` | `putReferenceOpaque` | `classfile/vmIntrinsics.hpp:814` |
| `_putIntOpaque` | `putIntOpaque` | `classfile/vmIntrinsics.hpp:819` |

### 6.4 Acquire/Release Access

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_getReferenceAcquire` | `getReferenceAcquire` | `classfile/vmIntrinsics.hpp:834` |
| `_putReferenceRelease` | `putReferenceRelease` | `classfile/vmIntrinsics.hpp:843` |
| `_getIntAcquire` | `getIntAcquire` | `classfile/vmIntrinsics.hpp:839` |
| `_putIntRelease` | `putIntRelease` | `classfile/vmIntrinsics.hpp:848` |

### 6.5 CAS Operations

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_compareAndSetReference` | `compareAndSetReference` | `classfile/vmIntrinsics.hpp:920` |
| `_compareAndExchangeReference` | `compareAndExchangeReference` | `classfile/vmIntrinsics.hpp:921` |
| `_compareAndSetInt` | `compareAndSetInt` | `classfile/vmIntrinsics.hpp:928` |
| `_compareAndExchangeLong` | `compareAndExchangeLong` | `classfile/vmIntrinsics.hpp:925` |
| `_weakCompareAndSetReferencePlain` | `weakCompareAndSetReferencePlain` | `classfile/vmIntrinsics.hpp:941` |
| `_weakCompareAndSetInt` | `weakCompareAndSetInt` | `classfile/vmIntrinsics.hpp:952` |

### 6.6 Atomic RMW Operations

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_getAndAddInt` | `getAndAddInt` | `classfile/vmIntrinsics.hpp:962` |
| `_getAndAddLong` | `getAndAddLong` | `classfile/vmIntrinsics.hpp:965` |
| `_getAndSetInt` | `getAndSetInt` | `classfile/vmIntrinsics.hpp:974` |
| `_getAndSetLong` | `getAndSetLong` | `classfile/vmIntrinsics.hpp:977` |
| `_getAndSetReference` | `getAndSetReference` | `classfile/vmIntrinsics.hpp:986` |

### 6.7 Memory Operations

| Intrinsic ID | Method Name | Source Evidence |
|-------------|-------------|-----------------|
| `_allocateInstance` | `allocateInstance` | `classfile/vmIntrinsics.hpp:677` |
| `_allocateUninitializedArray` | `allocateUninitializedArray0` | `classfile/vmIntrinsics.hpp:680` |
| `_copyMemory` | `copyMemory0` | `classfile/vmIntrinsics.hpp:682` |
| `_setMemory` | `setMemory0` | `classfile/vmIntrinsics.hpp:685` |
| `_loadFence` | `loadFence` | `classfile/vmIntrinsics.hpp:688` |
| `_storeFence` | `storeFence` | `classfile/vmIntrinsics.hpp:691` |
| `_storeStoreFence` | `storeStoreFence` | `classfile/vmIntrinsics.hpp:694` |
| `_fullFence` | `fullFence` | `classfile/vmIntrinsics.hpp:697` |

### 6.8 Unsafe Memory Access Guard Pattern

| Pattern | Purpose | Source Evidence |
|---------|---------|-----------------|
| `GuardUnsafeAccess` | Sets `doing_unsafe_access` flag on thread | `prims/unsafe.cpp:153-167` |
| `MemoryAccess<T>` | Template wrapping read/write with guard | `prims/unsafe.cpp:175-240` |
| `addr_from_java(jlong)` | Convert Java long to native pointer | `prims/unsafe.cpp:82-88` |
| `addr_to_java(void*)` | Convert native pointer to Java long | `prims/unsafe.cpp:90-93` |
| `HeapAccess<ON_UNKNOWN_OOP_REF>` | GC-aware heap access for oop refs | `prims/unsafe.cpp:248` |

---

## 7. FFI Patterns (JNI and Panama/FFM)

### 7.1 JNI Boundary

| Pattern | Marker | Source Evidence |
|---------|--------|-----------------|
| Java native method declaration | `native` keyword in Java | JNI spec |
| JNI function naming | `Java_<pkg>_<Class>_<method>` | `prims/nativeLookup.cpp:169-183` |
| JNI function type | `JNICALL` / `JNIEnv*` first arg | `prims/jni.cpp:44` |
| JNI handle resolution | `JNIHandles::resolve(obj)` | `prims/unsafe.cpp:246` |
| JNI local handle creation | `JNIHandles::make_local(THREAD, v)` | `prims/unsafe.cpp:249` |
| Critical JNI | `@CriticalNative` annotation | JDK 21+ Panama integration |

### 7.2 Panama / Foreign Function & Memory API (FFM)

| Pattern | Source Evidence |
|---------|-----------------|
| `DowncallLinker::make_downcall_stub` | Java-to-native call stub generation | `prims/downcallLinker.hpp:34-42` |
| `UpcallLinker::make_upcall_stub` | Native-to-Java callback stub | `prims/upcallLinker.hpp:40-44` |
| `UpcallLinker::on_entry` / `on_exit` | Thread attach/detach for upcalls | `prims/upcallLinker.hpp:37-38` |
| `DowncallLinker::capture_state_pre/post` | Capture thread state around downcalls | `prims/downcallLinker.hpp:45-46` |
| `NativeEntryPoint` | JVM-registered native entry point | `prims/nativeLookup.cpp:225` |
| `UpcallStubs` | JVM-registered upcall stubs | `prims/nativeLookup.cpp:223` |
| `ScopedMemoryAccess` | Scoped memory access with bounds | `classfile/vmIntrinsics.hpp:669` |
| `ForeignGlobals` / `ABIDescriptor` | ABI specification for FFI | `prims/foreignGlobals.hpp` |

### 7.3 FFI Type Mapping

| Java Type | Native Type | JNI Type | Source Evidence |
|-----------|-------------|----------|-----------------|
| `boolean` | `jboolean` (uint8_t) | `Z` | JNI spec, `prims/jni.cpp` |
| `byte` | `jbyte` (int8_t) | `B` | JNI spec |
| `char` | `jchar` (uint16_t) | `C` | JNI spec |
| `short` | `jshort` (int16_t) | `S` | JNI spec |
| `int` | `jint` (int32_t) | `I` | JNI spec |
| `long` | `jlong` (int64_t) | `J` | JNI spec |
| `float` | `jfloat` | `F` | JNI spec |
| `double` | `jdouble` | `D` | JNI spec |
| `Object` | `jobject` (opaque handle) | `L...;` | JNI spec |
| `String` | `jstring` | `Ljava/lang/String;` | JNI spec |
| `byte[]` | `jbyteArray` | `[B` | JNI spec |

---

## 8. Key Takeaways for Static Analysis

### What's user code (analyze these):
- Java methods not annotated with `@IntrinsicCandidate`
- JNI native methods (appearing as `Java_*` C symbols)
- Panama FFM downcall/upcall targets
- User-defined Unsafe usage (through `jdk.internal.misc.Unsafe`)

### What's compiler-reserved (filter/skip these):
- **C2 Sea-of-Nodes IR nodes** (~300+ node types in `classes.hpp`)
- **C1 Instruction classes** (~40 instruction types)
- **VM Symbols** (class/method/field names in `vmSymbols.hpp`)
- **VM Intrinsics** (~200+ methods replaced by compiler-generated code, marked with `@IntrinsicCandidate`)
- **GC barrier nodes** (Shenandoah-specific CAS/barrier nodes)
- **Memory barrier nodes** (MemBar* family)
- **Opaque/Ctrl nodes** (Opaque1, OpaqueLoopInit, etc. for optimization control)

### What's FFI boundary (classify and analyze carefully):
- `Java_*` JNI function symbols (nativeLookup.cpp naming rules)
- Panama FFM downcall stubs (`DowncallLinker::make_downcall_stub`)
- Panama FFM upcall stubs (`UpcallLinker::make_upcall_stub`)
- `Unsafe` field/memory access intrinsics (60+ methods covering plain/volatile/opaque/acquire-release/CAS)
- `ScopedMemoryAccess` operations (bounds-checked memory access)
- Native memory operations (`copyMemory0`, `setMemory0`, `allocateInstance`)

### What indicates memory safety concerns:
- **Unsafe field offsets** -- opaque cookie, no bounds checking at IR level
- **Raw pointer arithmetic** -- `CastP2X` / `CastX2P` nodes
- **GC barrier bypass** -- `C2_UNSAFE_ACCESS` decorator on memory operations
- **Off-heap memory** -- `addr_from_java(jlong)` converts long to raw pointer
- **Object pinning** -- `Reference.reachabilityFence` to prevent GC collection during native access

---

## 9. Annotation-Based Intrinsic Marking

### 9.1 @IntrinsicCandidate

Methods annotated with `jdk.internal.vm.annotation.IntrinsicCandidate` may be replaced by compiler-generated code.

| Property | Value | Source Evidence |
|----------|-------|-----------------|
| Full annotation | `jdk.internal.vm.annotation.IntrinsicCandidate` | `classfile/vmIntrinsics.hpp:88` |
| Checked at class load | Yes (when `CheckIntrinsics` enabled) | `classfile/vmIntrinsics.hpp:89-101` |
| Product build behavior | Unmarked intrinsics treated as ordinary methods | `classfile/vmIntrinsics.hpp:99` |

### 9.2 Intrinsic Flag Codes

| Flag | Meaning | Source Evidence |
|------|---------|-----------------|
| `F_S` | Static method | `classfile/vmIntrinsics.hpp` (used throughout) |
| `F_R` | Non-native, may be replaced | `classfile/vmIntrinsics.hpp` |
| `F_RN` | Native, may be replaced | `classfile/vmIntrinsics.hpp` |
| `F_SN` | Static native | `classfile/vmIntrinsics.hpp` |
