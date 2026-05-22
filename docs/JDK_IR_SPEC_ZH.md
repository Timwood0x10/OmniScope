# OpenJDK HotSpot IR 规范: 编译器保留 vs 用户定义

**源码**: `/Users/scc/code/researcher/jdk` (主线)
**日期**: 2026-05-22
**目的**: 为静态分析工具 (如 OmniScope) 区分编译器保留的 IR 模式与用户定义的符号

---

## 1. 符号命名规则

### 1.1 JNI 名称修饰 (用户定义的本地方法)

JNI 规范定义了从 Java `native` 方法到 C 函数名的映射规则。

| 模式 | JNI 符号示例 | 源码证据 |
|------|-------------|----------|
| `Java_<类名>_<方法名>` (简单) | `Java_java_lang_Object_hashCode` | `prims/nativeLookup.cpp:169-183` -- `pure_jni_name()` |
| `Java_<类名>_<方法名>__<签名>` (重载) | `Java_pkg_Cls_method__II` | `prims/nativeLookup.cpp:185-199` -- `long_jni_name()` |
| 类名中 `/` -> `_` | `java/lang/Object` -> `java_lang_Object` | `prims/nativeLookup.cpp:150-151` |
| 名称中 `_` -> `_1` | `my_method` -> `my_1method` | `prims/nativeLookup.cpp:149` |
| `;` -> `_2` | 描述符 `;` -> `_2` | `prims/nativeLookup.cpp:155` |
| `[` -> `_3` | 描述符 `[` -> `_3` | `prims/nativeLookup.cpp:156` |
| 非 ASCII 字符 -> `_0wxyz` (十六进制) | U+ABCD -> `_0abcd` | `prims/nativeLookup.cpp:157` |

**特殊 JVM 注册的本地方法** (硬编码, 跳过常规查找):

| JNI 名称 | 目标 | 源码证据 |
|----------|------|----------|
| `Java_jdk_internal_misc_Unsafe_registerNatives` | `JVM_RegisterJDKInternalMiscUnsafeMethods` | `prims/nativeLookup.cpp:221` |
| `Java_java_lang_invoke_MethodHandleNatives_registerNatives` | `JVM_RegisterMethodHandleMethods` | `prims/nativeLookup.cpp:222` |
| `Java_jdk_internal_foreign_abi_UpcallStubs_registerNatives` | `JVM_RegisterUpcallHandlerMethods` | `prims/nativeLookup.cpp:223` |
| `Java_jdk_internal_foreign_abi_UpcallLinker_registerNatives` | `JVM_RegisterUpcallLinkerMethods` | `prims/nativeLookup.cpp:224` |
| `Java_jdk_internal_foreign_abi_NativeEntryPoint_registerNatives` | `JVM_RegisterNativeEntryPointMethods` | `prims/nativeLookup.cpp:225` |
| `Java_jdk_internal_vm_vector_VectorSupport_registerNatives` | `JVM_RegisterVectorSupportMethods` | `prims/nativeLookup.cpp:229` |
| `Java_jdk_vm_ci_hotspot_CompilerToVM_registerNatives` | `JVM_RegisterJVMCINatives` | `prims/nativeLookup.cpp:233` |
| `Java_jdk_jfr_internal_JVM_registerNatives` | `jfr_register_natives` | `prims/nativeLookup.cpp:236` |

### 1.2 VM 符号表 (编译器保留)

VM 维护一个全局符号表, 用于快速查找常用的类名、方法名和字段名。

| 模式 | 示例 | 源码证据 |
|------|------|----------|
| `java_lang_Object` | 类符号 | `classfile/vmSymbols.hpp:59` |
| `java_lang_String` | 类符号 | `classfile/vmSymbols.hpp:62` |
| `java_lang_Thread` | 类符号 | `classfile/vmSymbols.hpp:65` |
| `java_lang_Class` | 类符号 | `classfile/vmSymbols.hpp:60` |
| `jdk_internal_misc_Unsafe` | 类符号 | `classfile/vmIntrinsics.hpp:667` |
| `sun_misc_Unsafe` | 类符号 (旧版) | `classfile/vmIntrinsics.hpp:668` |
| `jdk_internal_misc_ScopedMemoryAccess` | 类符号 | `classfile/vmIntrinsics.hpp:669` |

### 1.3 Java 方法签名在 IR 中的表示

| 类型描述符 | JVM 内部形式 | 示例 |
|-----------|-------------|------|
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

## 2. C2 编译器 (HotSpot) -- Sea of Nodes IR

### 2.1 节点类型分类体系

C2 使用 "Sea of Nodes" IR。所有节点类型在 `classes.hpp` 中枚举。

#### 算术节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `AddI`, `AddL`, `AddF`, `AddD` | 整数/浮点加法 | `opto/classes.hpp:34-37` |
| `SubI`, `SubL`, `SubF`, `SubD` | 减法 | `opto/classes.hpp:374-377` |
| `MulI`, `MulL`, `MulF`, `MulD` | 乘法 | `opto/classes.hpp:271-272` |
| `DivI`, `DivL`, `DivF`, `DivD` | 除法 | `opto/classes.hpp:174-177` |
| `ModI`, `ModL`, `ModF`, `ModD` | 取模 | `opto/classes.hpp:254-257` |
| `NegI`, `NegL`, `NegF`, `NegD` | 取反 | `opto/classes.hpp:274-277` |
| `AbsI`, `AbsL`, `AbsF`, `AbsD` | 绝对值 | `opto/classes.hpp:30-33` |
| `MaxI`, `MaxL`, `MaxF`, `MaxD` | 最大值 | `opto/classes.hpp:229-233` |
| `MinI`, `MinL`, `MinF`, `MinD` | 最小值 | `opto/classes.hpp:247-250` |
| `SqrtD`, `SqrtF` | 平方根 | `opto/classes.hpp:351-352` |
| `PowD`, `ExpD` | 幂运算, 指数 | `opto/classes.hpp:289` |
| `LogD`, `Log10D` | 对数 | `opto/classes.hpp` |
| `SinD`, `CosD`, `TanD` | 三角函数 | `opto/classes.hpp` |
| `FmaD`, `FmaF`, `FmaHF` | 融合乘加 | `opto/classes.hpp:190-192` |
| `MulHiL`, `UMulHiL` | 乘法高位结果 | `opto/classes.hpp:269-270` |

#### 溢出检查算术节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `OverflowAddI`, `OverflowAddL` | 溢出检查加法 | `opto/classes.hpp:293-296` |
| `OverflowSubI`, `OverflowSubL` | 溢出检查减法 | `opto/classes.hpp:294-297` |
| `OverflowMulI`, `OverflowMulL` | 溢出检查乘法 | `opto/classes.hpp:295-298` |

#### 位运算 / 移位节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `AndI`, `AndL` | 按位与 | `opto/classes.hpp:42-43` |
| `OrI`, `OrL` | 按位或 | `opto/classes.hpp:291-292` |
| `XorI`, `XorL` | 按位异或 | `opto/classes.hpp:388-389` |
| `LShiftI`, `LShiftL` | 左移 | `opto/classes.hpp:205-206` |
| `RShiftI`, `RShiftL` | 算术右移 | `opto/classes.hpp:312-313` |
| `URShiftI`, `URShiftL` | 逻辑右移 | `opto/classes.hpp:386-387` |
| `RotateLeft`, `RotateRight` | 位旋转 | `opto/classes.hpp:323-326` |
| `ReverseI`, `ReverseL` | 位反转 | `opto/classes.hpp:317-318` |
| `ReverseBytesI`, `ReverseBytesL` | 字节交换 | `opto/classes.hpp:52-53` |
| `PopCountI`, `PopCountL` | 种群计数 | `opto/classes.hpp:305-306` |
| `CountLeadingZerosI`, `CountLeadingZerosL` | 前导零计数 | `opto/classes.hpp:164-165` |
| `CountTrailingZerosI`, `CountTrailingZerosL` | 尾部零计数 | `opto/classes.hpp:167-168` |
| `CompressBits`, `ExpandBits` | 位压缩/展开 | `opto/classes.hpp:82-83` |

#### 内存节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `LoadB`, `LoadUB` | 加载字节/无符号字节 | `opto/classes.hpp:207-208` |
| `LoadS`, `LoadUS` | 加载短整数/无符号短整数 | `opto/classes.hpp:210,221` |
| `LoadI`, `LoadL` | 加载整数/长整数 | `opto/classes.hpp:213,216` |
| `LoadF`, `LoadD` | 加载浮点/双精度 | `opto/classes.hpp:212,210` |
| `LoadP`, `LoadN` | 加载指针/窄 oop | `opto/classes.hpp:218-219` |
| `LoadKlass`, `LoadNKlass` | 加载类指针 | `opto/classes.hpp:214-215` |
| `LoadRange` | 加载数组长度 | `opto/classes.hpp:220` |
| `StoreB`, `StoreC` | 存储字节/字符 | `opto/classes.hpp:358-359` |
| `StoreI`, `StoreL` | 存储整数/长整数 | `opto/classes.hpp:361-362` |
| `StoreF`, `StoreD` | 存储浮点/双精度 | `opto/classes.hpp:360,359` |
| `StoreP`, `StoreN` | 存储指针/窄 oop | `opto/classes.hpp:364-365` |
| `ClearArray` | 内存清零 | `opto/classes.hpp:80` |
| `ArrayCopy` | 批量数组复制 | `opto/classes.hpp:44` |
| `Initialize` | 对象初始化 | `opto/classes.hpp:201` |
| `PrefetchAllocation` | 分配预取 | `opto/classes.hpp:310` |

#### 控制流节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `If`, `IfFalse`, `IfTrue` | 条件分支 | `opto/classes.hpp:197-200` |
| `Goto` | 无条件跳转 | `opto/classes.hpp:194` |
| `Return` | 方法返回 | `opto/classes.hpp:316` |
| `Halt` | 程序停止 | `opto/classes.hpp:195` |
| `Rethrow` | 异常重抛 | `opto/classes.hpp:315` |
| `Catch`, `CatchProj` | 异常捕获 | `opto/classes.hpp:77-78` |
| `Jump`, `JumpProj` | switch 跳转 | `opto/classes.hpp:203-204` |
| `PCTable` | PC 映射表 | `opto/classes.hpp:299` |
| `Region` | 控制流合并 | `opto/classes.hpp:314` |
| `Loop`, `CountedLoop` | 循环头 | `opto/classes.hpp:223,158` |
| `CountedLoopEnd` | 循环退出 | `opto/classes.hpp:159` |
| `SafePoint` | GC 安全点 | `opto/classes.hpp:327` |
| `Start`, `StartOSR` | 方法入口 | `opto/classes.hpp:356-357` |
| `Root` | 图根节点 | `opto/classes.hpp:320` |
| `Parm` | 方法参数 | `opto/classes.hpp:300` |
| `Phi` | SSA phi 节点 | `opto/classes.hpp:304` |
| `Mach` | 机器指令 | `opto/classes.hpp:225` |
| `MachProj` | 机器投影 | `opto/classes.hpp:227` |
| `MachNullCheck` | 空指针检查 | `opto/classes.hpp:226` |

#### 对象分配节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `Allocate` | 对象分配 | `opto/classes.hpp:40` |
| `AllocateArray` | 数组分配 | `opto/classes.hpp:41` |

#### 锁/监视器节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `FastLock` | 优化的监视器进入 | `opto/classes.hpp:188` |
| `FastUnlock` | 优化的监视器退出 | `opto/classes.hpp:189` |
| `Lock` | 监视器进入 | `opto/classes.hpp:222` |
| `Unlock` | 监视器退出 | `opto/classes.hpp:383` |

#### 原子/CAS 节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `CompareAndSwapB/S/I/L/P/N` | 比较并交换 | `opto/classes.hpp:106-111` |
| `WeakCompareAndSwapB/S/I/L/P/N` | 弱 CAS | `opto/classes.hpp:112-117` |
| `CompareAndExchangeB/S/I/L/P/N` | CAS 返回旧值 | `opto/classes.hpp:118-123` |
| `GetAndAddB/S/I/L` | 原子取并加 | `opto/classes.hpp:124-127` |
| `GetAndSetB/S/I/L/P/N` | 原子交换 | `opto/classes.hpp:128-133` |

#### 内存屏障节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `MemBarAcquire` | 加载屏障 | `opto/classes.hpp:234` |
| `MemBarRelease` | 存储屏障 | `opto/classes.hpp:238` |
| `MemBarVolatile` | 全屏障 (volatile) | `opto/classes.hpp:243` |
| `MemBarStoreLoad` | StoreLoad 屏障 | `opto/classes.hpp:242` |
| `MemBarStoreStore` | StoreStore 屏障 | `opto/classes.hpp:244` |
| `MemBarFull` | 完整内存屏障 | `opto/classes.hpp:245` |
| `MemBarCPUOrder` | CPU 排序屏障 | `opto/classes.hpp:237` |
| `MemBarAcquireLock` | 锁获取屏障 | `opto/classes.hpp:236` |
| `MemBarReleaseLock` | 锁释放屏障 | `opto/classes.hpp:241` |
| `LoadFence` | 加载屏障 (Unsafe) | `opto/classes.hpp:235` |
| `StoreFence` | 存储屏障 (Unsafe) | `opto/classes.hpp:239` |
| `StoreStoreFence` | StoreStore 屏障 | `opto/classes.hpp:240` |

#### 类型/转换节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `ConvI2L`, `ConvL2I` | 整数/长整数转换 | `opto/classes.hpp:152,155` |
| `ConvI2F`, `ConvI2D` | 整数转浮点/双精度 | `opto/classes.hpp:150-151` |
| `ConvF2I`, `ConvF2L` | 浮点转整数/长整数 | `opto/classes.hpp:148-149` |
| `ConvD2I`, `ConvD2L`, `ConvD2F` | 双精度转换 | `opto/classes.hpp:146-148` |
| `ConvL2D`, `ConvL2F` | 长整数转浮点/双精度 | `opto/classes.hpp:153-154` |
| `Conv2B` | 转换为布尔值 | `opto/classes.hpp:143` |
| `ConvF2HF`, `ConvHF2F` | Float16 转换 | `opto/classes.hpp:156-157` |
| `CastII`, `CastLL`, `CastFF`, `CastDD` | 类型收窄转换 | `opto/classes.hpp:71-74` |
| `CastPP` | 指针转换 | `opto/classes.hpp:76` |
| `CheckCastPP` | 带检查的指针转换 | `opto/classes.hpp:79` |
| `DecodeN`, `DecodeNKlass` | 解码窄 oop/类 | `opto/classes.hpp:171-172` |
| `EncodeP`, `EncodePKlass` | 编码指针/类 | `opto/classes.hpp:186-187` |
| `CastX2P`, `CastP2X` | 整数<->指针转换 | `opto/classes.hpp:75-76` |

#### 字符串内置节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `StrComp` | 字符串比较 | `opto/classes.hpp:367` |
| `StrEquals` | 字符串相等判断 | `opto/classes.hpp:369` |
| `StrIndexOf` | 字符串查找 | `opto/classes.hpp:370` |
| `StrIndexOfChar` | 字符串字符查找 | `opto/classes.hpp:371` |
| `StrCompressedCopy` | 压缩复制 | `opto/classes.hpp:368` |
| `StrInflatedCopy` | 膨胀复制 | `opto/classes.hpp:372` |
| `AryEq` | 数组相等判断 | `opto/classes.hpp:45` |
| `CountPositives` | 计数正字节 | `opto/classes.hpp:196` |
| `EncodeISOArray` | ISO 编码 | `opto/classes.hpp:185` |
| `Digit`, `UpperCase`, `LowerCase`, `Whitespace` | 字符分类 | `opto/classes.hpp:513-518` |

#### 调用节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `CallStaticJava` | 静态方法调用 | `opto/classes.hpp:67` |
| `CallDynamicJava` | 虚方法/接口调用 | `opto/classes.hpp:60` |
| `CallJava` | Java 方法调用 (基类) | `opto/classes.hpp:61` |
| `CallRuntime` | 运行时调用 | `opto/classes.hpp:66` |
| `CallLeaf` | 本地叶子调用 | `opto/classes.hpp:62` |
| `CallLeafNoFP` | 本地叶子调用 (无浮点) | `opto/classes.hpp:63` |
| `CallLeafPure` | 纯本地叶子调用 | `opto/classes.hpp:64` |
| `CallLeafVector` | 向量本地叶子调用 | `opto/classes.hpp:65` |
| `TailCall` | 尾调用 | `opto/classes.hpp:378` |
| `TailJump` | 尾跳转 | `opto/classes.hpp:379` |

### 2.2 GC 特定的 C2 节点

| 节点类 | GC | 用途 | 源码证据 |
|--------|-----|------|----------|
| `ShenandoahCompareAndExchangeP` | Shenandoah | oop 上的 CAS | `opto/classes.hpp:335` |
| `ShenandoahCompareAndExchangeN` | Shenandoah | 窄 oop 上的 CAS | `opto/classes.hpp:336` |
| `ShenandoahCompareAndSwapN` | Shenandoah | CAS 窄 oop | `opto/classes.hpp:337` |
| `ShenandoahCompareAndSwapP` | Shenandoah | CAS oop | `opto/classes.hpp:338` |
| `ShenandoahWeakCompareAndSwapN` | Shenandoah | 弱 CAS 窄 oop | `opto/classes.hpp:339` |
| `ShenandoahWeakCompareAndSwapP` | Shenandoah | 弱 CAS oop | `opto/classes.hpp:340` |
| `ShenandoahLoadReferenceBarrier` | Shenandoah | 加载引用屏障 | `opto/classes.hpp:341` |

### 2.3 向量/SIMD 节点

| 节点类 | 用途 | 源码证据 |
|--------|------|----------|
| `LoadVector`, `StoreVector` | 向量加载/存储 | `opto/classes.hpp:475,478` |
| `LoadVectorGather`, `StoreVectorScatter` | 聚集/分散 | `opto/classes.hpp:476,479` |
| `AddVI`, `AddVL`, `AddVF`, `AddVD` | 向量加法 | `opto/classes.hpp:393-401` |
| `MulVI`, `MulVL`, `MulVF`, `MulVD` | 向量乘法 | `opto/classes.hpp:412-419` |
| `DivVF`, `DivVD` | 向量除法 | `opto/classes.hpp:428-429` |
| `AndV`, `OrV`, `XorV` | 向量位运算 | `opto/classes.hpp:456-461` |
| `LShiftVI`, `RShiftVI` | 向量移位 | `opto/classes.hpp:444-455` |
| `MinV`, `MaxV` | 向量最小/最大值 | `opto/classes.hpp:462-471` |
| `FmaVD`, `FmaVF` | 向量 FMA | `opto/classes.hpp:423-425` |
| `VectorBox`, `VectorBoxAllocate` | 向量装箱 | `opto/classes.hpp:520-521` |
| `VectorUnbox` | 向量拆箱 | `opto/classes.hpp:522` |
| `VectorCastB2X`, `VectorCastI2X`, 等 | 向量类型转换 | `opto/classes.hpp:535-543` |
| `VectorReinterpret` | 向量重新解释 | `opto/classes.hpp:533` |
| `VectorMaskGen`, `VectorMaskCmp` | 掩码操作 | `opto/classes.hpp:485,524` |
| `PopCountVI`, `PopCountVL` | 向量种群计数 | `opto/classes.hpp:307-308` |

### 2.4 C2 访问修饰符 (内存访问元数据)

| 修饰符 | 值 | 用途 | 源码证据 |
|--------|-----|------|----------|
| `C2_MISMATCHED` | `DECORATOR_LAST << 1` | 类型不匹配的访问 | `gc/shared/c2/barrierSetC2.hpp:38` |
| `C2_UNALIGNED` | `DECORATOR_LAST << 2` | 非对齐访问 | `gc/shared/c2/barrierSetC2.hpp:40` |
| `C2_WEAK_CMPXCHG` | `DECORATOR_LAST << 3` | 弱比较并交换 | `gc/shared/c2/barrierSetC2.hpp:43` |
| `C2_CONTROL_DEPENDENT_LOAD` | `DECORATOR_LAST << 4` | 控制依赖的加载 | `gc/shared/c2/barrierSetC2.hpp:45` |
| `C2_UNKNOWN_CONTROL_LOAD` | `DECORATOR_LAST << 5` | 加载固定 (可在安全点上方浮动) | `gc/shared/c2/barrierSetC2.hpp:47` |
| `C2_UNSAFE_ACCESS` | `DECORATOR_LAST << 6` | 来自 Unsafe 内置方法 | `gc/shared/c2/barrierSetC2.hpp:49` |
| `C2_WRITE_ACCESS` | `DECORATOR_LAST << 7` | 写访问 | `gc/shared/c2/barrierSetC2.hpp:51` |
| `C2_READ_ACCESS` | `DECORATOR_LAST << 8` | 读访问 | `gc/shared/c2/barrierSetC2.hpp:53` |
| `C2_TIGHTLY_COUPLED_ALLOC` | `DECORATOR_LAST << 9` | 紧邻的分配 | `gc/shared/c2/barrierSetC2.hpp:55` |
| `C2_ARRAY_COPY` | `DECORATOR_LAST << 10` | 数组复制优化 | `gc/shared/c2/barrierSetC2.hpp:57` |
| `C2_IMMUTABLE_MEMORY` | `DECORATOR_LAST << 11` | 不可变内存 | `gc/shared/c2/barrierSetC2.hpp:59` |

---

## 3. C1 编译器 IR

### 3.1 指令类层次结构

C1 使用更简单的 HIR (高级 IR), 采用类层次结构。

| 指令类 | 用途 | 源码证据 |
|--------|------|----------|
| `Phi` | SSA phi 函数 | `c1/c1_Instruction.hpp:47` |
| `Local` | 局部变量 | `c1/c1_Instruction.hpp:48` |
| `Constant` | 常量值 | `c1/c1_Instruction.hpp:49` |
| `LoadField`, `StoreField` | 字段访问 | `c1/c1_Instruction.hpp:51-52` |
| `ArrayLength` | 数组长度 | `c1/c1_Instruction.hpp:54` |
| `LoadIndexed`, `StoreIndexed` | 数组元素访问 | `c1/c1_Instruction.hpp:56-57` |
| `ArithmeticOp`, `ShiftOp`, `LogicOp` | 算术/位运算 | `c1/c1_Instruction.hpp:60-62` |
| `CompareOp`, `IfOp` | 比较/条件 | `c1/c1_Instruction.hpp:63-64` |
| `Convert` | 类型转换 | `c1/c1_Instruction.hpp:65` |
| `NullCheck` | 空指针检查 | `c1/c1_Instruction.hpp:66` |
| `Invoke` | 方法调用 | `c1/c1_Instruction.hpp:71` |
| `NewInstance`, `NewArray` | 对象分配 | `c1/c1_Instruction.hpp:72-73` |
| `NewTypeArray`, `NewObjectArray`, `NewMultiArray` | 特化数组分配 | `c1/c1_Instruction.hpp:74-76` |
| `CheckCast`, `InstanceOf` | 类型检查 | `c1/c1_Instruction.hpp:78-79` |
| `MonitorEnter`, `MonitorExit` | 加锁/解锁 | `c1/c1_Instruction.hpp:81-82` |
| `Intrinsic` | 编译器内置方法调用 | `c1/c1_Instruction.hpp:83` |
| `Goto`, `If`, `Switch`, `Return`, `Throw` | 控制流 | `c1/c1_Instruction.hpp:86-93` |
| `UnsafeGet`, `UnsafePut`, `UnsafeGetAndSet` | Unsafe 内存访问 | `c1/c1_Instruction.hpp:95-97` |
| `MemBar` | 内存屏障 | `c1/c1_Instruction.hpp:102` |
| `RuntimeCall` | 运行时调用 | `c1/c1_Instruction.hpp:101` |
| `RangeCheckPredicate` | 范围检查消除 | `c1/c1_Instruction.hpp:103` |

---

## 4. GC 屏障模式

### 4.1 屏障集实现

| 屏障集 | GC | 源码证据 |
|--------|-----|----------|
| `CardTableBarrierSet` | Serial, Parallel | `gc/shared/barrierSetConfig.hpp:32` |
| `G1BarrierSet` | G1 | `gc/shared/barrierSetConfig.hpp:33` |
| `ShenandoahBarrierSet` | Shenandoah | `gc/shared/barrierSetConfig.hpp:34` |
| `ZBarrierSet` | ZGC | `gc/shared/barrierSetConfig.hpp:35` |
| `EpsilonBarrierSet` | Epsilon (空操作) | `gc/shared/barrierSetConfig.hpp:33` |

### 4.2 G1 GC 屏障

| 屏障类型 | 机制 | 源码证据 |
|----------|------|----------|
| **SATB 写屏障** | 开始时快照标记 | `gc/g1/g1BarrierSet.hpp:68` -- `_satb_mark_queue_set` |
| **卡表写屏障** | 跨区域引用的脏卡标记 | `gc/g1/g1BarrierSet.hpp:66` -- 继承 `CardTableBarrierSet` |
| **精炼表** | 双缓冲卡表用于并发精炼 | `gc/g1/g1BarrierSet.hpp:71` -- `_refinement_table` |

### 4.3 ZGC 屏障

| 屏障类型 | 机制 | 源码证据 |
|----------|------|----------|
| **加载屏障 (基于移位)** | 指针加载检查元数据位, 移位去除 | `gc/z/zBarrier.hpp:31-67` |
| **存储屏障** | 存储屏障缓冲 | `gc/z/zBarrierSet.hpp` |
| **NMethod 入口屏障** | 每个 GC 阶段修补加载屏障移位值 | `gc/z/zBarrier.hpp:45` |

ZGC 使用带颜色的指针和元数据位。加载屏障应用移位来去除元数据:
- 如果结果为 null: ZF 标志置位 (快速路径)
- 如果结果 CF 置位: 好指针 (快速路径)
- 否则: 慢速路径 (指针需要修复)

### 4.4 Shenandoah GC 屏障

| 屏障类型 | 机制 | 源码证据 |
|----------|------|----------|
| **加载引用屏障** | 解析加载时的转发指针 | `gc/shenandoah/shenandoahBarrierSet.hpp:61` |
| **SATB 写屏障** | 开始时快照标记 | `gc/shenandoah/shenandoahBarrierSet.hpp:57` -- `_satb_mark_queue_set` |
| **卡屏障** | 堆引用的卡标记 | `gc/shenandoah/shenandoahBarrierSet.hpp:64` |
| **保持存活屏障** | 防止过早回收 | `gc/shenandoah/shenandoahBarrierSet.hpp:62` |
| **强/弱/虚引用访问** | 基于修饰符的屏障选择 | `gc/shenandoah/shenandoahBarrierSet.hpp:66-80` |

### 4.5 卡表屏障

| 屏障类型 | 机制 | 源码证据 |
|----------|------|----------|
| **卡表写屏障** | 指针存储时标记脏卡 | `gc/shared/cardTableBarrierSet.hpp` |
| **C2 集成** | `CardTableBarrierSetC2` 生成 C2 IR | `gc/shared/c2/cardTableBarrierSetC2.hpp` |

---

## 5. VM 内置方法 (编译器替换的方法)

### 5.1 数学内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
| `_dabs`, `_fabs`, `_iabs`, `_labs` | `Math.abs` | `classfile/vmIntrinsics.hpp:154-157` |
| `_dsin`, `_dcos`, `_dtan` | `Math.sin/cos/tan` | `classfile/vmIntrinsics.hpp:158,162-163` |
| `_datan2` | `Math.atan2` | `classfile/vmIntrinsics.hpp:164` |
| `_dsqrt` | `Math.sqrt` | `classfile/vmIntrinsics.hpp:168` |
| `_dlog`, `_dlog10` | `Math.log/log10` | `classfile/vmIntrinsics.hpp:169-170` |
| `_dpow` | `Math.pow` | `classfile/vmIntrinsics.hpp:171` |
| `_dexp` | `Math.exp` | `classfile/vmIntrinsics.hpp:172` |
| `_floor`, `_ceil`, `_rint` | `Math.floor/ceil/rint` | `classfile/vmIntrinsics.hpp:159-161` |
| `_addExactI`, `_addExactL` | `Math.addExact` (溢出检查) | `classfile/vmIntrinsics.hpp:175-176` |
| `_multiplyExactI`, `_multiplyExactL` | `Math.multiplyExact` | `classfile/vmIntrinsics.hpp:181-182` |
| `_subtractExactI`, `_subtractExactL` | `Math.subtractExact` | `classfile/vmIntrinsics.hpp:187-188` |
| `_negateExactI`, `_negateExactL` | `Math.negateExact` | `classfile/vmIntrinsics.hpp:185-186` |
| `_fmaD`, `_fmaF` | `Math.fma` | `classfile/vmIntrinsics.hpp:189-190` |
| `_roundD`, `_roundF` | `Math.round` | `classfile/vmIntrinsics.hpp:197-198` |
| `_dcopySign`, `_fcopySign` | `Math.copySign` | `classfile/vmIntrinsics.hpp:199-200` |
| `_dsignum`, `_fsignum` | `Math.signum` | `classfile/vmIntrinsics.hpp:201-202` |

### 5.2 整数位操作内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
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

### 5.3 浮点位内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
| `_floatToRawIntBits` | `Float.floatToRawIntBits` | `classfile/vmIntrinsics.hpp:221` |
| `_floatToIntBits` | `Float.floatToIntBits` | `classfile/vmIntrinsics.hpp:223` |
| `_intBitsToFloat` | `Float.intBitsToFloat` | `classfile/vmIntrinsics.hpp:225` |
| `_doubleToRawLongBits` | `Double.doubleToRawLongBits` | `classfile/vmIntrinsics.hpp:227` |
| `_doubleToLongBits` | `Double.doubleToLongBits` | `classfile/vmIntrinsics.hpp:229` |
| `_longBitsToDouble` | `Double.longBitsToDouble` | `classfile/vmIntrinsics.hpp:231` |
| `_float16ToFloat` | `Float.float16ToFloat` | `classfile/vmIntrinsics.hpp:233` |
| `_floatToFloat16` | `Float.floatToFloat16` | `classfile/vmIntrinsics.hpp:236` |

### 5.4 系统/运行时内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
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
| `_blackhole` | `Object.blackhole` (Blackhole 节点) | `classfile/vmIntrinsics.hpp:715` |

### 5.5 字符串内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
| `_compressStringC/B` | `StringUTF16.compress0` | `classfile/vmIntrinsics.hpp:362-364` |
| `_inflateStringC/B` | `StringLatin1.inflate0` | `classfile/vmIntrinsics.hpp:365-369` |
| `_compareToL/U/LU/UL` | `StringLatin1/UTF16.compareTo0` | `classfile/vmIntrinsics.hpp:380-387` |
| `_indexOfL/U/UL/IL/IU/IUL` | `StringLatin1/UTF16.indexOf0` | `classfile/vmIntrinsics.hpp:388-398` |
| `_equalsL` | `StringLatin1.equals0` | `classfile/vmIntrinsics.hpp:401` |
| `_countPositives` | `StringCoding.countPositives0` | `classfile/vmIntrinsics.hpp:419` |
| `_encodeISOArray` | `ISO_8859_1$Encoder.encodeISOArray0` | `classfile/vmIntrinsics.hpp:424` |
| `_toBytesStringU` | `StringUTF16.toBytes0` | `classfile/vmIntrinsics.hpp:370` |
| `_getCharsStringU` | `StringUTF16.getChars0` | `classfile/vmIntrinsics.hpp:373` |

### 5.6 数组内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
| `_copyOf` | `Arrays.copyOf` | `classfile/vmIntrinsics.hpp:337` |
| `_copyOfRange` | `Arrays.copyOfRange` | `classfile/vmIntrinsics.hpp:349` |
| `_equalsC`, `_equalsB` | `Arrays.equals(char[], char[])` 等 | `classfile/vmIntrinsics.hpp:353-356` |
| `_arraySort` | `DualPivotQuicksort.sort` | `classfile/vmIntrinsics.hpp:341` |
| `_arrayPartition` | `DualPivotQuicksort.partition` | `classfile/vmIntrinsics.hpp:345` |
| `_vectorizedHashCode` | `ArraysSupport.vectorizedHashCode` | `classfile/vmIntrinsics.hpp:358` |
| `_vectorizedMismatch` | `ArraysSupport.vectorizedMismatch` | `classfile/vmIntrinsics.hpp:461` |

### 5.7 加密/哈希内置方法

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
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

### 5.8 后量子密码内置方法 (ML-KEM, ML-DSA)

| 内置 ID | Java 方法 | 源码证据 |
|---------|-----------|----------|
| `_kyberNtt` | `ML_KEM.implKyberNtt` | `classfile/vmIntrinsics.hpp:586` |
| `_kyberInverseNtt` | `ML_KEM.implKyberInverseNtt` | `classfile/vmIntrinsics.hpp:588` |
| `_kyberNttMult` | `ML_KEM.implKyberNttMult` | `classfile/vmIntrinsics.hpp:590` |
| `_dilithiumAlmostNtt` | `ML_DSA.implDilithiumAlmostNtt` | `classfile/vmIntrinsics.hpp:606` |
| `_dilithiumNttMult` | `ML_DSA.implDilithiumNttMult` | `classfile/vmIntrinsics.hpp:610` |

---

## 6. Unsafe 操作 (sun.misc.Unsafe / jdk.internal.misc.Unsafe)

### 6.1 对象字段访问 (普通)

| 内置 ID | 方法名 | 签名 | 源码证据 |
|---------|--------|------|----------|
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

### 6.2 Volatile 访问 (顺序一致性)

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_getReferenceVolatile` | `getReferenceVolatile` | `classfile/vmIntrinsics.hpp:776` |
| `_getIntVolatile` | `getIntVolatile` | `classfile/vmIntrinsics.hpp:781` |
| `_putReferenceVolatile` | `putReferenceVolatile` | `classfile/vmIntrinsics.hpp:785` |
| `_putIntVolatile` | `putIntVolatile` | `classfile/vmIntrinsics.hpp:790` |

### 6.3 Opaque 访问 (编译器不可优化)

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_getReferenceOpaque` | `getReferenceOpaque` | `classfile/vmIntrinsics.hpp:805` |
| `_getIntOpaque` | `getIntOpaque` | `classfile/vmIntrinsics.hpp:810` |
| `_putReferenceOpaque` | `putReferenceOpaque` | `classfile/vmIntrinsics.hpp:814` |
| `_putIntOpaque` | `putIntOpaque` | `classfile/vmIntrinsics.hpp:819` |

### 6.4 Acquire/Release 访问

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_getReferenceAcquire` | `getReferenceAcquire` | `classfile/vmIntrinsics.hpp:834` |
| `_putReferenceRelease` | `putReferenceRelease` | `classfile/vmIntrinsics.hpp:843` |
| `_getIntAcquire` | `getIntAcquire` | `classfile/vmIntrinsics.hpp:839` |
| `_putIntRelease` | `putIntRelease` | `classfile/vmIntrinsics.hpp:848` |

### 6.5 CAS 操作

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_compareAndSetReference` | `compareAndSetReference` | `classfile/vmIntrinsics.hpp:920` |
| `_compareAndExchangeReference` | `compareAndExchangeReference` | `classfile/vmIntrinsics.hpp:921` |
| `_compareAndSetInt` | `compareAndSetInt` | `classfile/vmIntrinsics.hpp:928` |
| `_compareAndExchangeLong` | `compareAndExchangeLong` | `classfile/vmIntrinsics.hpp:925` |
| `_weakCompareAndSetReferencePlain` | `weakCompareAndSetReferencePlain` | `classfile/vmIntrinsics.hpp:941` |
| `_weakCompareAndSetInt` | `weakCompareAndSetInt` | `classfile/vmIntrinsics.hpp:952` |

### 6.6 原子 RMW 操作

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_getAndAddInt` | `getAndAddInt` | `classfile/vmIntrinsics.hpp:962` |
| `_getAndAddLong` | `getAndAddLong` | `classfile/vmIntrinsics.hpp:965` |
| `_getAndSetInt` | `getAndSetInt` | `classfile/vmIntrinsics.hpp:974` |
| `_getAndSetLong` | `getAndSetLong` | `classfile/vmIntrinsics.hpp:977` |
| `_getAndSetReference` | `getAndSetReference` | `classfile/vmIntrinsics.hpp:986` |

### 6.7 内存操作

| 内置 ID | 方法名 | 源码证据 |
|---------|--------|----------|
| `_allocateInstance` | `allocateInstance` | `classfile/vmIntrinsics.hpp:677` |
| `_allocateUninitializedArray` | `allocateUninitializedArray0` | `classfile/vmIntrinsics.hpp:680` |
| `_copyMemory` | `copyMemory0` | `classfile/vmIntrinsics.hpp:682` |
| `_setMemory` | `setMemory0` | `classfile/vmIntrinsics.hpp:685` |
| `_loadFence` | `loadFence` | `classfile/vmIntrinsics.hpp:688` |
| `_storeFence` | `storeFence` | `classfile/vmIntrinsics.hpp:691` |
| `_storeStoreFence` | `storeStoreFence` | `classfile/vmIntrinsics.hpp:694` |
| `_fullFence` | `fullFence` | `classfile/vmIntrinsics.hpp:697` |

### 6.8 Unsafe 内存访问保护模式

| 模式 | 用途 | 源码证据 |
|------|------|----------|
| `GuardUnsafeAccess` | 在线程上设置 `doing_unsafe_access` 标志 | `prims/unsafe.cpp:153-167` |
| `MemoryAccess<T>` | 模板包装读写操作并添加保护 | `prims/unsafe.cpp:175-240` |
| `addr_from_java(jlong)` | 将 Java long 转换为本地指针 | `prims/unsafe.cpp:82-88` |
| `addr_to_java(void*)` | 将本地指针转换为 Java long | `prims/unsafe.cpp:90-93` |
| `HeapAccess<ON_UNKNOWN_OOP_REF>` | 针对 oop 引用的 GC 感知堆访问 | `prims/unsafe.cpp:248` |

---

## 7. FFI 模式 (JNI 和 Panama/FFM)

### 7.1 JNI 边界

| 模式 | 标记 | 源码证据 |
|------|------|----------|
| Java 本地方法声明 | Java 中的 `native` 关键字 | JNI 规范 |
| JNI 函数命名 | `Java_<包名>_<类名>_<方法名>` | `prims/nativeLookup.cpp:169-183` |
| JNI 函数类型 | `JNICALL` / 第一个参数为 `JNIEnv*` | `prims/jni.cpp:44` |
| JNI 句柄解析 | `JNIHandles::resolve(obj)` | `prims/unsafe.cpp:246` |
| JNI 局部句柄创建 | `JNIHandles::make_local(THREAD, v)` | `prims/unsafe.cpp:249` |
| Critical JNI | `@CriticalNative` 注解 | JDK 21+ Panama 集成 |

### 7.2 Panama / 外部函数与内存 API (FFM)

| 模式 | 源码证据 |
|------|----------|
| `DowncallLinker::make_downcall_stub` | Java 到本地调用桩生成 | `prims/downcallLinker.hpp:34-42` |
| `UpcallLinker::make_upcall_stub` | 本地到 Java 回调桩 | `prims/upcallLinker.hpp:40-44` |
| `UpcallLinker::on_entry` / `on_exit` | 上行调用的线程附加/分离 | `prims/upcallLinker.hpp:37-38` |
| `DowncallLinker::capture_state_pre/post` | 下行调用前后捕获线程状态 | `prims/downcallLinker.hpp:45-46` |
| `NativeEntryPoint` | JVM 注册的本地入口点 | `prims/nativeLookup.cpp:225` |
| `UpcallStubs` | JVM 注册的上行调用桩 | `prims/nativeLookup.cpp:223` |
| `ScopedMemoryAccess` | 带边界检查的作用域内存访问 | `classfile/vmIntrinsics.hpp:669` |
| `ForeignGlobals` / `ABIDescriptor` | FFI 的 ABI 规范 | `prims/foreignGlobals.hpp` |

### 7.3 FFI 类型映射

| Java 类型 | 本地类型 | JNI 类型 | 源码证据 |
|-----------|---------|----------|----------|
| `boolean` | `jboolean` (uint8_t) | `Z` | JNI 规范, `prims/jni.cpp` |
| `byte` | `jbyte` (int8_t) | `B` | JNI 规范 |
| `char` | `jchar` (uint16_t) | `C` | JNI 规范 |
| `short` | `jshort` (int16_t) | `S` | JNI 规范 |
| `int` | `jint` (int32_t) | `I` | JNI 规范 |
| `long` | `jlong` (int64_t) | `J` | JNI 规范 |
| `float` | `jfloat` | `F` | JNI 规范 |
| `double` | `jdouble` | `D` | JNI 规范 |
| `Object` | `jobject` (不透明句柄) | `L...;` | JNI 规范 |
| `String` | `jstring` | `Ljava/lang/String;` | JNI 规范 |
| `byte[]` | `jbyteArray` | `[B` | JNI 规范 |

---

## 8. 静态分析关键要点

### 用户代码 (需要分析):
- 未标注 `@IntrinsicCandidate` 的 Java 方法
- JNI 本地方法 (表现为 `Java_*` C 符号)
- Panama FFM 下行/上行调用目标
- 用户定义的 Unsafe 使用 (通过 `jdk.internal.misc.Unsafe`)

### 编译器保留 (应过滤/跳过):
- **C2 Sea-of-Nodes IR 节点** (约 300+ 种节点类型, 在 `classes.hpp` 中)
- **C1 指令类** (约 40 种指令类型)
- **VM 符号** (`vmSymbols.hpp` 中的类/方法/字段名)
- **VM 内置方法** (约 200+ 个被编译器生成代码替换的方法, 标记为 `@IntrinsicCandidate`)
- **GC 屏障节点** (Shenandoah 特定的 CAS/屏障节点)
- **内存屏障节点** (MemBar* 系列)
- **Opaque/Ctrl 节点** (Opaque1, OpaqueLoopInit 等, 用于优化控制)

### FFI 边界 (应分类并仔细分析):
- `Java_*` JNI 函数符号 (nativeLookup.cpp 命名规则)
- Panama FFM 下行调用桩 (`DowncallLinker::make_downcall_stub`)
- Panama FFM 上行调用桩 (`UpcallLinker::make_upcall_stub`)
- `Unsafe` 字段/内存访问内置方法 (60+ 个方法, 覆盖普通/volatile/opaque/acquire-release/CAS)
- `ScopedMemoryAccess` 操作 (带边界检查的内存访问)
- 本地内存操作 (`copyMemory0`, `setMemory0`, `allocateInstance`)

### 指示内存安全问题的模式:
- **Unsafe 字段偏移** -- 不透明的 cookie, IR 层面无边界检查
- **原始指针算术** -- `CastP2X` / `CastX2P` 节点
- **GC 屏障绕过** -- 内存操作上的 `C2_UNSAFE_ACCESS` 修饰符
- **堆外内存** -- `addr_from_java(jlong)` 将 long 转换为原始指针
- **对象固定** -- `Reference.reachabilityFence` 防止本地访问期间 GC 回收

---

## 9. 基于注解的内置标记

### 9.1 @IntrinsicCandidate

标注了 `jdk.internal.vm.annotation.IntrinsicCandidate` 的方法可能被编译器生成的代码替换。

| 属性 | 值 | 源码证据 |
|------|-----|----------|
| 完整注解 | `jdk.internal.vm.annotation.IntrinsicCandidate` | `classfile/vmIntrinsics.hpp:88` |
| 类加载时检查 | 是 (当 `CheckIntrinsics` 启用时) | `classfile/vmIntrinsics.hpp:89-101` |
| 生产构建行为 | 未标记的内置方法视为普通方法 | `classfile/vmIntrinsics.hpp:99` |

### 9.2 内置标志代码

| 标志 | 含义 | 源码证据 |
|------|------|----------|
| `F_S` | 静态方法 | `classfile/vmIntrinsics.hpp` (全文使用) |
| `F_R` | 非本地方法, 可被替换 | `classfile/vmIntrinsics.hpp` |
| `F_RN` | 本地方法, 可被替换 | `classfile/vmIntrinsics.hpp` |
| `F_SN` | 静态本地方法 | `classfile/vmIntrinsics.hpp` |
