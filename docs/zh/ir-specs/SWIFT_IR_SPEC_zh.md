# Swift LLVM IR 规范：编译器保留 vs 用户定义

**来源**: `/Users/scc/code/researcher/swift` (主分支)
**日期**: 2026-05-22
**用途**: 为静态分析工具（如 OmniScope）区分编译器保留的 IR 模式与用户定义的符号

---

## 1. 符号命名 / 名称修饰规则

### 1.1 修饰前缀

Swift 使用名称修饰（mangling）方案将类型信息和模块上下文编码到符号名称中。修饰前缀用于标识一个符号是否为 Swift 修饰名称。

| 前缀 | Swift 版本 | 源码证据 |
|------|-----------|----------|
| `$s` | Swift 5+ | `include/swift/Demangling/ManglingMacros.h:24` |
| `_$s` | Swift 5+（带下划线前缀） | `lib/Demangling/Demangler.cpp:188` |
| `$S` / `_$S` | Swift 4.x | `lib/Demangling/Demangler.cpp:187` |
| `_T0` | Swift 4 | `lib/Demangling/Demangler.cpp:186` |
| `$e` / `_$e` | 嵌入式 Swift | `include/swift/Demangling/ManglingMacros.h:25`, `lib/Demangling/Demangler.cpp:189` |
| `@__swiftmacro_` | Swift 宏文件名 | `lib/Demangling/Demangler.cpp:190` |

**源码**: `lib/Demangling/Demangler.cpp:182-200` — `getManglingPrefixLength()`

### 1.2 修饰语法（运算符字符）

修饰方案使用单字符运算符来编码不同的实体类型。前缀之后的第一个字符标识实体种类。

| 字符 | 实体种类 | 源码证据 |
|------|---------|----------|
| `C` | 类 (Class) | `lib/Demangling/Demangler.cpp:1054` |
| `V` | 结构体 (Structure) | `lib/Demangling/Demangler.cpp:1105` |
| `O` | 枚举 (Enum) | `lib/Demangling/Demangler.cpp:1099` |
| `P` | 协议 (Protocol) | `lib/Demangling/Demangler.cpp:1100` |
| `E` | 扩展 (Extension) | `lib/Demangling/Demangler.cpp:1056` |
| `F` | 函数 (Function) | `lib/Demangling/Demangler.cpp:1057` |
| `G` | 绑定泛型类型 (Bound generic type) | `lib/Demangling/Demangler.cpp:1058` |
| `I` | 实现函数类型 (Implementation function type) | `lib/Demangling/Demangler.cpp:1093` |
| `M` | 元类型 (Metatype) | `lib/Demangling/Demangler.cpp:1096` |
| `N` | 类型元数据 (Type metadata) | `lib/Demangling/Demangler.cpp:1097` |
| `Q` | 原型 (Archetype) | `lib/Demangling/Demangler.cpp:1101` |
| `R` | 泛型约束 (Generic requirement) | `lib/Demangling/Demangler.cpp:1102` |
| `S` | 标准替换 (Standard substitution) | `lib/Demangling/Demangler.cpp:1103` |
| `T` | 桩或特化 (Thunk or specialization) | `lib/Demangling/Demangler.cpp:1104` |
| `W` | 见证 (Witness) | `lib/Demangling/Demangler.cpp:1106` |
| `X` | 特殊类型 (Special type) | `lib/Demangling/Demangler.cpp:1107` |
| `Y` | 类型注解 (Type annotation) | `lib/Demangling/Demangler.cpp:1108` |
| `Z` | 静态 (Static) | `lib/Demangling/Demangler.cpp:1109` |
| `a` | 类型别名 (Type alias) | `lib/Demangling/Demangler.cpp:1110` |
| `c` | 函数类型 (Function type) | `lib/Demangling/Demangler.cpp:1111` |
| `f` | 函数实体 (Function entity) | `lib/Demangling/Demangler.cpp:1113` |
| `i` | 下标 (Subscript) | `lib/Demangling/Demangler.cpp:1117` |
| `m` | 元类型类型 (Metatype type) | `lib/Demangling/Demangler.cpp:1119` |
| `v` | 变量 (Variable) | `lib/Demangling/Demangler.cpp:1131` |
| `w` | 值见证 (Value witness) | `lib/Demangling/Demangler.cpp:1132` |

### 1.3 运算符字符编码

运算符被编码以避免修饰名称中的歧义。

| 运算符 | 编码为 | 源码证据 |
|--------|--------|----------|
| `&` | `a` (and) | `lib/Demangling/ManglingUtils.cpp:48` |
| `@` | `c` (commercial at) | `lib/Demangling/ManglingUtils.cpp:49` |
| `/` | `d` (divide) | `lib/Demangling/ManglingUtils.cpp:50` |
| `=` | `e` (equal) | `lib/Demangling/ManglingUtils.cpp:51` |
| `>` | `g` (greater) | `lib/Demangling/ManglingUtils.cpp:52` |
| `<` | `l` (less) | `lib/Demangling/ManglingUtils.cpp:53` |
| `*` | `m` (multiply) | `lib/Demangling/ManglingUtils.cpp:54` |
| `!` | `n` (negate) | `lib/Demangling/ManglingUtils.cpp:55` |
| `\|` | `o` (or) | `lib/Demangling/ManglingUtils.cpp:56` |
| `+` | `p` (plus) | `lib/Demangling/ManglingUtils.cpp:57` |
| `?` | `q` (question) | `lib/Demangling/ManglingUtils.cpp:58` |
| `%` | `r` (remainder) | `lib/Demangling/ManglingUtils.cpp:59` |
| `-` | `s` (subtract) | `lib/Demangling/ManglingUtils.cpp:60` |
| `~` | `t` (tilde) | `lib/Demangling/ManglingUtils.cpp:61` |
| `^` | `x` (xor) | `lib/Demangling/ManglingUtils.cpp:62` |
| `.` | `z` (zperiod) | `lib/Demangling/ManglingUtils.cpp:63` |

**源码**: `lib/Demangling/ManglingUtils.cpp:46-67` — `translateOperatorChar()`

### 1.4 标准类型替换

常用标准库类型有缩写的修饰形式。

| 类型 | 修饰形式 | 源码证据 |
|------|---------|----------|
| `Swift`（模块） | `s` | `lib/Demangling/Demangler.cpp:1128` |
| `Any` | `yp` | `include/swift/Demangling/ManglingMacros.h:46` |
| `AnyObject` | `yXl` | `include/swift/Demangling/ManglingMacros.h:47` |
| `()`（空元组） | `yt` | `include/swift/Demangling/ManglingMacros.h:45` |

**源码**: `include/swift/Demangling/ManglingMacros.h:43-48`, `lib/Demangling/ManglingUtils.cpp:77-93`

### 1.5 符号引用

Swift 5+ 在修饰名称中支持符号引用，用于协议一致性和类型描述符。

| 原始种类 | 符号引用种类 | 源码证据 |
|---------|-------------|----------|
| `0x01` | 上下文（直接） | `lib/Demangling/Demangler.cpp:947` |
| `0x02` | 上下文（间接） | `lib/Demangling/Demangler.cpp:951` |
| `0x09` | 访问器函数引用 | `lib/Demangling/Demangler.cpp:955` |
| `0x0a` | 唯一扩展存在类型形状 | `lib/Demangling/Demangler.cpp:959` |
| `0x0b` | 非唯一扩展存在类型形状 | `lib/Demangling/Demangler.cpp:963` |
| `0x0c` | Objective-C 协议 | `lib/Demangling/Demangler.cpp:967` |

**源码**: `lib/Demangling/Demangler.cpp:932-999` — `demangleSymbolicReference()`

---

## 2. ARC（自动引用计数）在 IR 中的表示

### 2.1 强引用计数

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_retain` | `(ptr) → ptr` | 增加强引用计数 | `include/swift/Runtime/RuntimeFunctions.def:216-221` |
| `swift_release` | `(ptr)` | 减少强引用计数，为零时释放 | `include/swift/Runtime/RuntimeFunctions.def:224-229` |
| `swift_retain_n` | `(ptr, n) → ptr` | 批量增加强引用计数 | `include/swift/Runtime/RuntimeFunctions.def:256-261` |
| `swift_release_n` | `(ptr, n)` | 批量减少强引用计数 | `include/swift/Runtime/RuntimeFunctions.def:264-269` |
| `swift_nonatomic_retain` | `(ptr) → ptr` | 非原子强引用保留 | `include/swift/Runtime/RuntimeFunctions.def:369-375` |
| `swift_nonatomic_release` | `(ptr)` | 非原子强引用释放 | `include/swift/Runtime/RuntimeFunctions.def:378-384` |
| `swift_nonatomic_retain_n` | `(ptr, n) → ptr` | 非原子批量保留 | `include/swift/Runtime/RuntimeFunctions.def:281-286` |
| `swift_nonatomic_release_n` | `(ptr, n)` | 非原子批量释放 | `include/swift/Runtime/RuntimeFunctions.def:289-294` |
| `swift_retainDirect` | `(ptr) → ptr` | 直接调用约定保留 | `include/swift/Runtime/RuntimeFunctions.def:232-237` |
| `swift_releaseDirect` | `(ptr)` | 直接调用约定释放 | `include/swift/Runtime/RuntimeFunctions.def:240-245` |
| `swift_tryRetain` | `(ptr) → ptr` | 条件保留（正在释放时返回 null） | `include/swift/Runtime/RuntimeFunctions.def:387-392` |
| `swift_setDeallocating` | `(ptr)` | 标记对象为正在释放 | `include/swift/Runtime/RuntimeFunctions.def:272-278` |
| `swift_isDeallocating` | `(ptr) → bool` | 检查对象是否正在释放 | `include/swift/Runtime/RuntimeFunctions.def:395-400` |

### 2.2 未知对象引用计数

用于 Objective-C 互操作和编译时引用计数策略未知的存在类型。

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_unknownObjectRetain` | `(ptr) → ptr` | 保留未知引用计数对象 | `include/swift/Runtime/RuntimeFunctions.def:403-408` |
| `swift_unknownObjectRelease` | `(ptr)` | 释放未知引用计数对象 | `include/swift/Runtime/RuntimeFunctions.def:411-417` |
| `swift_unknownObjectRetain_n` | `(ptr, n) → ptr` | 批量未知保留 | `include/swift/Runtime/RuntimeFunctions.def:297-303` |
| `swift_unknownObjectRelease_n` | `(ptr, n)` | 批量未知释放 | `include/swift/Runtime/RuntimeFunctions.def:306-312` |
| `swift_nonatomic_unknownObjectRetain` | `(ptr) → ptr` | 非原子未知保留 | `include/swift/Runtime/RuntimeFunctions.def:420-426` |
| `swift_nonatomic_unknownObjectRelease` | `(ptr)` | 非原子未知释放 | `include/swift/Runtime/RuntimeFunctions.def:429-435` |

### 2.3 桥接对象引用计数

用于 Swift 和 Objective-C 之间的桥接类型（例如 `String` ↔ `NSString`）。

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_bridgeObjectRetain` | `(ptr) → ptr` | 保留桥接对象 | `include/swift/Runtime/RuntimeFunctions.def:438-444` |
| `swift_bridgeObjectRelease` | `(ptr)` | 释放桥接对象 | `include/swift/Runtime/RuntimeFunctions.def:447-453` |
| `swift_bridgeObjectRetain_n` | `(ptr, n) → ptr` | 批量桥接保留 | `include/swift/Runtime/RuntimeFunctions.def:333-339` |
| `swift_bridgeObjectRelease_n` | `(ptr, n)` | 批量桥接释放 | `include/swift/Runtime/RuntimeFunctions.def:342-348` |
| `swift_bridgeObjectRetainDirect` | `(ptr) → ptr` | 直接调用约定桥接保留 | `include/swift/Runtime/RuntimeFunctions.def:456-462` |
| `swift_bridgeObjectReleaseDirect` | `(ptr)` | 直接调用约定桥接释放 | `include/swift/Runtime/RuntimeFunctions.def:465-471` |
| `swift_nonatomic_bridgeObjectRetain` | `(ptr) → ptr` | 非原子桥接保留 | `include/swift/Runtime/RuntimeFunctions.def:474-480` |
| `swift_nonatomic_bridgeObjectRelease` | `(ptr)` | 非原子桥接释放 | `include/swift/Runtime/RuntimeFunctions.def:483-490` |

### 2.4 错误引用计数

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_errorRetain` | `(ptr) → ptr` | 保留错误对象 | `include/swift/Runtime/RuntimeFunctions.def:494-500` |
| `swift_errorRelease` | `(ptr)` | 释放错误对象 | `include/swift/Runtime/RuntimeFunctions.def:503-509` |

### 2.5 弱引用和无主引用

弱引用和无主引用通过 `ReferenceStorage.def` 的宏展开生成。运行时函数遵循 `swift_<kind>Init`、`swift_<kind>Destroy`、`swift_<kind>LoadStrong` 等模式。

| 引用种类 | IR 符号 | 源码证据 |
|---------|---------|----------|
| `weak`（原生） | `swift_weakInit`, `swift_weakDestroy`, `swift_weakLoadStrong`, `swift_weakTakeStrong`, `swift_weakCopyInit`, `swift_weakTakeInit`, `swift_weakCopyAssign`, `swift_weakTakeAssign` | `include/swift/Runtime/RuntimeFunctions.def:511-583`（宏展开） |
| `weak`（未知） | `swift_unknownObjectWeakInit`, `swift_unknownObjectWeakDestroy`, `swift_unknownObjectWeakLoadStrong` 等 | 同上宏展开 |
| `unowned`（原生） | `swift_unownedRetain`, `swift_unownedRelease`, `swift_unownedRetainStrong`, `swift_unownedRetainStrongAndRelease` | `include/swift/Runtime/RuntimeFunctions.def:588-621`（宏展开） |
| `unowned`（未知） | `swift_unknownObjectUnownedRetain`, `swift_unknownObjectUnownedRelease` 等 | 同上宏展开 |

**源码**: `include/swift/AST/ReferenceStorage.def` — 定义 `WEAK`、`UNOWNED`、`UNMANAGED` 存储种类；`include/swift/Runtime/RuntimeFunctions.def:511-629` — 宏生成的函数

### 2.6 堆分配

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_allocObject` | `(metadata, size, alignMask) → ptr` | 分配堆对象 | `include/swift/Runtime/RuntimeFunctions.def:92-97` |
| `swift_allocObjectTyped` | `(metadata, size, alignMask, typeId) → ptr` | 分配类型化堆对象 | `include/swift/Runtime/RuntimeFunctions.def:100-105` |
| `swift_deallocObject` | `(obj, size, alignMask)` | 释放堆对象 | `include/swift/Runtime/RuntimeFunctions.def:134-139` |
| `swift_deallocUninitializedObject` | `(obj, size, alignMask)` | 释放未初始化对象 | `include/swift/Runtime/RuntimeFunctions.def:142-148` |
| `swift_deallocClassInstance` | `(obj, size, alignMask)` | 释放类实例 | `include/swift/Runtime/RuntimeFunctions.def:151-156` |
| `swift_deallocPartialClassInstance` | `(obj, metadata, size, alignMask)` | 释放部分初始化的类 | `include/swift/Runtime/RuntimeFunctions.def:159-165` |
| `swift_initStackObject` | `(metadata, object) → ptr` | 初始化栈分配对象 | `include/swift/Runtime/RuntimeFunctions.def:109-114` |
| `swift_initStaticObject` | `(metadata, object) → ptr` | 初始化静态对象 | `include/swift/Runtime/RuntimeFunctions.def:118-123` |
| `swift_allocBox` | `(metadata) → (refPtr, boxPtr)` | 为存在类型/协议分配装箱 | `include/swift/Runtime/RuntimeFunctions.def:52-57` |
| `swift_deallocBox` | `(refPtr)` | 释放装箱 | `include/swift/Runtime/RuntimeFunctions.def:69-74` |
| `swift_projectBox` | `(refPtr) → ptr` | 从装箱投影值指针 | `include/swift/Runtime/RuntimeFunctions.def:77-82` |
| `swift_makeBoxUnique` | `(buffer, metadata, alignMask) → (refPtr, boxPtr)` | 使装箱唯一（COW） | `include/swift/Runtime/RuntimeFunctions.def:60-67` |
| `swift_allocEmptyBox` | `() → ptr` | 分配空装箱 | `include/swift/Runtime/RuntimeFunctions.def:84-89` |
| `swift_slowAlloc` | `(size, alignMask) → ptr` | 慢路径分配 | `include/swift/Runtime/RuntimeFunctions.def:168-173` |
| `swift_slowDealloc` | `(ptr, size, alignMask)` | 慢路径释放 | `include/swift/Runtime/RuntimeFunctions.def:176-181` |

### 2.7 唯一性检查（写时复制）

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_isUniquelyReferencedNonObjC` | `(ptr) → bool` | 检查唯一引用（非 ObjC） | `include/swift/Runtime/RuntimeFunctions.def:634-640` |
| `swift_isUniquelyReferencedNonObjC_nonNull` | `(ptr) → bool` | 非空变体 | `include/swift/Runtime/RuntimeFunctions.def:643-650` |
| `swift_isUniquelyReferenced_nonNull_native` | `(ptr) → bool` | 原生非空唯一性检查 | `include/swift/Runtime/RuntimeFunctions.def:703-710` |
| `swift_isUniquelyReferenced_native` | `(ptr) → bool` | 原生唯一性检查 | `include/swift/Runtime/RuntimeFunctions.def:694-700` |
| `swift_isEscapingClosureAtFileLocation` | `(object, filename, len, line, col, type) → bool` | 闭包逃逸检查 | `include/swift/Runtime/RuntimeFunctions.def:718-724` |

### 2.8 数组值操作

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_arrayInitWithCopy` | `(dest, src, count, metadata)` | 复制初始化数组 | `include/swift/Runtime/RuntimeFunctions.def:727-733` |
| `swift_arrayInitWithTakeNoAlias` | `(dest, src, count, metadata)` | 移动初始化数组（无别名） | `include/swift/Runtime/RuntimeFunctions.def:736-742` |
| `swift_arrayInitWithTakeFrontToBack` | `(dest, src, count, metadata)` | 从前向后移动 | `include/swift/Runtime/RuntimeFunctions.def:745-751` |
| `swift_arrayInitWithTakeBackToFront` | `(dest, src, count, metadata)` | 从后向前移动 | `include/swift/Runtime/RuntimeFunctions.def:754-760` |
| `swift_arrayAssignWithCopyNoAlias` | `(dest, src, count, metadata)` | 复制赋值（无别名） | `include/swift/Runtime/RuntimeFunctions.def:763-769` |
| `swift_arrayAssignWithCopyFrontToBack` | `(dest, src, count, metadata)` | 从前向后复制赋值 | `include/swift/Runtime/RuntimeFunctions.def:772-778` |
| `swift_arrayAssignWithCopyBackToFront` | `(dest, src, count, metadata)` | 从后向前复制赋值 | `include/swift/Runtime/RuntimeFunctions.def:781-787` |
| `swift_arrayAssignWithTake` | `(dest, src, count, metadata)` | 移动赋值数组 | `include/swift/Runtime/RuntimeFunctions.def:790-795` |
| `swift_arrayDestroy` | `(ptr, count, metadata)` | 销毁数组元素 | `include/swift/Runtime/RuntimeFunctions.def:798-803` |

---

## 3. 运行时函数 — 动态类型转换

### 3.1 通用动态转换

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_dynamicCast` | `(dest, src, srcMetadata, targetMetadata, flags) → bool` | 通用动态转换 | `include/swift/Runtime/RuntimeFunctions.def:1801-1807` |
| `swift_dynamicCastClass` | `(object, targetMetadata) → ptr` | 类向下转换（失败返回 null） | `include/swift/Runtime/RuntimeFunctions.def:1709-1714` |
| `swift_dynamicCastClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | 无条件类向下转换（失败时陷入） | `include/swift/Runtime/RuntimeFunctions.def:1717-1723` |
| `swift_dynamicCastObjCClass` | `(object, targetMetadata) → ptr` | ObjC 类向下转换 | `include/swift/Runtime/RuntimeFunctions.def:1726-1732` |
| `swift_dynamicCastObjCClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | 无条件 ObjC 类向下转换 | `include/swift/Runtime/RuntimeFunctions.def:1735-1741` |
| `swift_dynamicCastUnknownClass` | `(object, targetMetadata) → ptr` | 未知类向下转换 | `include/swift/Runtime/RuntimeFunctions.def:1744-1750` |
| `swift_dynamicCastUnknownClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | 无条件未知类向下转换 | `include/swift/Runtime/RuntimeFunctions.def:1753-1760` |

**源码**: `lib/IRGen/GenCast.cpp:45-69` — `getDynamicCastFlags()`

### 3.2 元类型转换

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_dynamicCastMetatype` | `(src, target) → ptr` | 元类型转换 | `include/swift/Runtime/RuntimeFunctions.def:1763-1769` |
| `swift_dynamicCastMetatypeUnconditional` | `(src, target, filename, line, col) → ptr` | 无条件元类型转换 | `include/swift/Runtime/RuntimeFunctions.def:1772-1779` |
| `swift_dynamicCastObjCClassMetatype` | `(src, target) → ptr` | ObjC 元类型转换 | `include/swift/Runtime/RuntimeFunctions.def:1782-1788` |
| `swift_dynamicCastObjCClassMetatypeUnconditional` | `(src, target, filename, line, col) → ptr` | 无条件 ObjC 元类型转换 | `include/swift/Runtime/RuntimeFunctions.def:1791-1798` |

### 3.3 协议一致性检查

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_conformsToProtocol` | `(metadata, protocolDescriptor) → witnessTable` | 检查协议一致性 | `include/swift/Runtime/RuntimeFunctions.def:1874-1880` |
| `swift_conformsToProtocol2` | `(metadata, protocolDescriptor) → witnessTable` | 协议一致性（签名描述符） | `include/swift/Runtime/RuntimeFunctions.def:1883-1889` |
| `swift_isClassType` | `(metadata) → bool` | 检查类型是否为类 | `include/swift/Runtime/RuntimeFunctions.def:1892-1898` |
| `swift_isOptionalType` | `(metadata) → bool` | 检查类型是否为 Optional | `include/swift/Runtime/RuntimeFunctions.def:1901-1907` |

**源码**: `lib/IRGen/GenProto.cpp:807-815` — `swift_conformsToProtocol()` 使用

### 3.4 ObjC 协议转换

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_dynamicCastTypeToObjCProtocolUnconditional` | `(type, numProtocols, protocols, filename, line, col) → ptr` | 类型到 ObjC 协议转换 | `include/swift/Runtime/RuntimeFunctions.def:1812-1819` |
| `swift_dynamicCastTypeToObjCProtocolConditional` | `(type, numProtocols, protocols) → ptr` | 条件类型到 ObjC 协议 | `include/swift/Runtime/RuntimeFunctions.def:1824-1831` |
| `swift_dynamicCastObjCProtocolUnconditional` | `(object, numProtocols, protocols, filename, line, col) → ptr` | ObjC 协议转换 | `include/swift/Runtime/RuntimeFunctions.def:1836-1842` |
| `swift_dynamicCastObjCProtocolConditional` | `(object, numProtocols, protocols) → ptr` | 条件 ObjC 协议转换 | `include/swift/Runtime/RuntimeFunctions.def:1847-1853` |

---

## 4. 运行时函数 — 元数据

### 4.1 元数据访问

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getSingletonMetadata` | `(request, descriptor) → response` | 获取单例类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:971-977` |
| `swift_getGenericMetadata` | `(request, arguments, descriptor) → response` | 获取泛型类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:982-988` |
| `swift_getCanonicalSpecializedMetadata` | `(request, candidate, cache) → response` | 获取规范特化元数据 | `include/swift/Runtime/RuntimeFunctions.def:992-998` |
| `swift_checkMetadataState` | `(request, metadata) → response` | 检查/完成元数据状态 | `include/swift/Runtime/RuntimeFunctions.def:1114-1120` |
| `swift_getForeignTypeMetadata` | `(size, nonUnique) → response` | 获取外部类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:947-953` |

**源码**: `lib/IRGen/GenMeta.cpp:89-100` — 元数据槽寻址

### 4.2 元数据初始化

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_initClassMetadata` | `(self, flags, numFields, fieldTypes, fieldOffsets)` | 初始化类元数据 | `include/swift/Runtime/RuntimeFunctions.def:1427-1433` |
| `swift_initClassMetadata2` | `(self, flags, numFields, fieldTypes, fieldOffsets) → dependency` | 初始化类元数据（v2） | `include/swift/Runtime/RuntimeFunctions.def:1453-1459` |
| `swift_updateClassMetadata` | `(self, flags, numFields, fieldTypes, fieldOffsets)` | 更新类元数据 | `include/swift/Runtime/RuntimeFunctions.def:1440-1446` |
| `swift_initStructMetadata` | `(structType, flags, numFields, fieldTypes, fieldOffsets)` | 初始化结构体元数据 | `include/swift/Runtime/RuntimeFunctions.def:1503-1509` |
| `swift_initEnumMetadataSingleCase` | `(enumType, flags, payload)` | 初始化单 case 枚举 | `include/swift/Runtime/RuntimeFunctions.def:1528-1535` |
| `swift_initEnumMetadataSinglePayload` | `(enumType, flags, payload, numEmptyCases)` | 初始化单载荷枚举 | `include/swift/Runtime/RuntimeFunctions.def:1553-1560` |
| `swift_initEnumMetadataMultiPayload` | `(enumType, flags, numPayloads, payloadTypes)` | 初始化多载荷枚举 | `include/swift/Runtime/RuntimeFunctions.def:1579-1586` |
| `swift_allocateGenericClassMetadata` | `(descriptor, arguments, template) → ptr` | 分配泛型类元数据 | `include/swift/Runtime/RuntimeFunctions.def:1065-1071` |
| `swift_allocateGenericValueMetadata` | `(descriptor, arguments, template, extraSize) → ptr` | 分配泛型值元数据 | `include/swift/Runtime/RuntimeFunctions.def:1090-1096` |
| `swift_relocateClassMetadata` | `(descriptor, pattern) → ptr` | 重定位类元数据 | `include/swift/Runtime/RuntimeFunctions.def:1414-1420` |

### 4.3 函数类型元数据

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getFunctionTypeMetadata` | `(flags, parameters, parameterFlags, result) → ptr` | 获取函数类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:809-815` |
| `swift_getFunctionTypeMetadata0` | `(flags, result) → ptr` | 0 参数函数元数据 | `include/swift/Runtime/RuntimeFunctions.def:901-907` |
| `swift_getFunctionTypeMetadata1` | `(flags, arg0, result) → ptr` | 1 参数函数元数据 | `include/swift/Runtime/RuntimeFunctions.def:912-918` |
| `swift_getFunctionTypeMetadata2` | `(flags, arg0, arg1, result) → ptr` | 2 参数函数元数据 | `include/swift/Runtime/RuntimeFunctions.def:924-930` |
| `swift_getFunctionTypeMetadata3` | `(flags, arg0, arg1, arg2, result) → ptr` | 3 参数函数元数据 | `include/swift/Runtime/RuntimeFunctions.def:937-944` |
| `swift_getExtendedFunctionTypeMetadata` | `(flags, diffKind, params, paramFlags, result, globalActor, extFlags, thrownError) → ptr` | 扩展函数元数据 | `include/swift/Runtime/RuntimeFunctions.def:841-855` |

### 4.4 元组元数据

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getTupleTypeMetadata` | `(request, flags, elements, labels, proposed) → response` | 获取元组元数据 | `include/swift/Runtime/RuntimeFunctions.def:1284-1289` |
| `swift_getTupleTypeMetadata2` | `(request, elt0, elt1, labels, proposed) → response` | 2 元素元组元数据 | `include/swift/Runtime/RuntimeFunctions.def:1295-1301` |
| `swift_getTupleTypeMetadata3` | `(request, elt0, elt1, elt2, labels, proposed) → response` | 3 元素元组元数据 | `include/swift/Runtime/RuntimeFunctions.def:1308-1314` |
| `swift_getTupleTypeLayout` | `(result, offsets, flags, elements)` | 获取元组布局 | `include/swift/Runtime/RuntimeFunctions.def:1320-1325` |

### 4.5 其他元数据

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getMetatypeMetadata` | `(instanceType) → ptr` | 获取元类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:1235-1240` |
| `swift_getExistentialMetatypeMetadata` | `(instanceType) → ptr` | 获取存在元类型 | `include/swift/Runtime/RuntimeFunctions.def:1243-1249` |
| `swift_getExistentialTypeMetadata` | `(classConstraint, superclass, numProtocols, protocols) → ptr` | 获取存在类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:1366-1373` |
| `swift_getFixedArrayTypeMetadata` | `(request, size, element) → response` | 获取固定数组元数据 | `include/swift/Runtime/RuntimeFunctions.def:1351-1357` |
| `swift_getObjCClassMetadata` | `(objcClass) → ptr` | 从 ObjC 类获取 Swift 元数据 | `include/swift/Runtime/RuntimeFunctions.def:1252-1258` |
| `swift_getObjCClassFromMetadata` | `(metadata) → ptr` | 从元数据获取 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:1261-1267` |
| `swift_getObjCClassFromObject` | `(object) → ptr` | 从对象获取 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:1271-1277` |
| `swift_getObjectType` | `(object) → ptr` | 从对象获取类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:1693-1698` |
| `swift_getDynamicType` | `(object, self, isMetatype) → ptr` | 获取动态类型 | `include/swift/Runtime/RuntimeFunctions.def:1701-1706` |

### 4.6 通过修饰名称查找类型

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getTypeByMangledNameInContext` | `(name, length, context, genericArgs) → ptr` | 通过修饰名称查找类型 | `include/swift/Runtime/RuntimeFunctions.def:2275-2281` |
| `swift_getTypeByMangledNameInContext2` | `(name, length, context, genericArgs) → ptr` | 查找类型（签名描述符） | `include/swift/Runtime/RuntimeFunctions.def:2288-2294` |
| `swift_getTypeByMangledNameInContextInMetadataState` | `(state, name, length, context, genericArgs) → ptr` | 在元数据状态中查找 | `include/swift/Runtime/RuntimeFunctions.def:2302-2310` |

---

## 5. 协议见证表

### 5.1 见证表访问

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getWitnessTable` | `(conformanceDescriptor, type, instantiationArgs) → ptr` | 获取/惰性实例化见证表 | `include/swift/Runtime/RuntimeFunctions.def:1127-1134` |
| `swift_getWitnessTableRelative` | `(conformanceDescriptor, type, instantiationArgs) → ptr` | 获取见证表（相对引用） | `include/swift/Runtime/RuntimeFunctions.def:1136-1143` |

**源码**: `lib/IRGen/GenProto.cpp:1300` — `getWitnessTableLazyAccessFunction()`, `lib/IRGen/GenProto.cpp:1283` — 条件见证表实例化

### 5.2 关联类型见证

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getAssociatedTypeWitness` | `(request, witnessTable, conformingType, reqBase, assocType) → response` | 获取关联类型见证 | `include/swift/Runtime/RuntimeFunctions.def:1151-1157` |
| `swift_getAssociatedTypeWitnessRelative` | `(request, witnessTable, conformingType, reqBase, assocType) → response` | 关联类型（相对引用） | `include/swift/Runtime/RuntimeFunctions.def:1158-1164` |
| `swift_getAssociatedConformanceWitness` | `(witnessTable, conformingType, assocType, reqBase, assocConformance) → ptr` | 获取关联一致性见证 | `include/swift/Runtime/RuntimeFunctions.def:1173-1183` |
| `swift_getAssociatedConformanceWitnessRelative` | `(witnessTable, conformingType, assocType, reqBase, assocConformance) → ptr` | 关联一致性（相对引用） | `include/swift/Runtime/RuntimeFunctions.def:1184-1194` |

### 5.3 不透明类型一致性

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getOpaqueTypeMetadata` | `(request, arguments, descriptor, index) → response` | 获取不透明类型元数据 | `include/swift/Runtime/RuntimeFunctions.def:1018-1024` |
| `swift_getOpaqueTypeMetadata2` | `(request, arguments, descriptor, index) → response` | 不透明类型元数据（v2） | `include/swift/Runtime/RuntimeFunctions.def:1031-1037` |
| `swift_getOpaqueTypeConformance` | `(arguments, descriptor, index) → ptr` | 获取不透明类型一致性 | `include/swift/Runtime/RuntimeFunctions.def:1043-1049` |
| `swift_getOpaqueTypeConformance2` | `(arguments, descriptor, index) → ptr` | 不透明类型一致性（v2） | `include/swift/Runtime/RuntimeFunctions.def:1054-1060` |

### 5.4 包元数据和见证表

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_allocateMetadataPack` | `(ptr, count) → ptr` | 分配元数据包 | `include/swift/Runtime/RuntimeFunctions.def:1213-1220` |
| `swift_allocateWitnessTablePack` | `(ptr, count) → ptr` | 分配见证表包 | `include/swift/Runtime/RuntimeFunctions.def:1225-1232` |

---

## 6. 值见证表

### 6.1 值见证函数

值见证实现值的复制、移动和销毁的基本操作。见证表是类型元数据的一部分。

| 值见证 | 描述 | 源码证据 |
|--------|------|----------|
| `AssignWithCopy` | 复制赋值 | `lib/IRGen/GenValueWitness.cpp:62` |
| `AssignWithTake` | 移动赋值 | `lib/IRGen/GenValueWitness.cpp:63` |
| `Destroy` | 销毁值 | `lib/IRGen/GenValueWitness.cpp:64` |
| `InitializeBufferWithCopyOfBuffer` | 从另一个缓冲区初始化 | `lib/IRGen/GenValueWitness.cpp:65` |
| `InitializeWithCopy` | 复制初始化 | `lib/IRGen/GenValueWitness.cpp:66` |
| `InitializeWithTake` | 移动初始化 | `lib/IRGen/GenValueWitness.cpp:67` |
| `GetEnumTag` | 获取枚举 case 标签 | `lib/IRGen/GenValueWitness.cpp:68` |
| `DestructiveProjectEnumData` | 投影枚举载荷（破坏性） | `lib/IRGen/GenValueWitness.cpp:69` |
| `DestructiveInjectEnumTag` | 注入枚举标签（破坏性） | `lib/IRGen/GenValueWitness.cpp:70` |
| `Size` | 类型大小 | `lib/IRGen/GenValueWitness.cpp:71` |
| `Flags` | 类型标志 | `lib/IRGen/GenValueWitness.cpp:72` |
| `ExtraInhabitantCount` | 额外居民数量 | `lib/IRGen/GenValueWitness.cpp:73` |
| `Stride` | 类型步长 | `lib/IRGen/GenValueWitness.cpp:74` |
| `GetEnumTagSinglePayload` | 获取单载荷枚举标签 | `lib/IRGen/GenValueWitness.cpp:75` |
| `StoreEnumTagSinglePayload` | 存储单载荷枚举标签 | `lib/IRGen/GenValueWitness.cpp:76` |

### 6.2 通用 CVW（紧凑值见证）函数

这些是为具有布局字符串的类型实现的运行时通用值见证。

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_cvw_destroy` | `(ptr, metadata)` | 通用销毁 | `include/swift/Runtime/RuntimeFunctions.def:2833-2840` |
| `swift_cvw_assignWithCopy` | `(dest, src, metadata) → ptr` | 通用复制赋值 | `include/swift/Runtime/RuntimeFunctions.def:2844-2851` |
| `swift_cvw_assignWithTake` | `(dest, src, metadata) → ptr` | 通用移动赋值 | `include/swift/Runtime/RuntimeFunctions.def:2854-2861` |
| `swift_cvw_initWithCopy` | `(dest, src, metadata) → ptr` | 通用复制初始化 | `include/swift/Runtime/RuntimeFunctions.def:2864-2871` |
| `swift_cvw_initWithTake` | `(dest, src, metadata) → ptr` | 通用移动初始化 | `include/swift/Runtime/RuntimeFunctions.def:2874-2881` |
| `swift_cvw_initializeBufferWithCopyOfBuffer` | `(dest, src, metadata) → ptr` | 通用缓冲区复制初始化 | `include/swift/Runtime/RuntimeFunctions.def:2884-2891` |

---

## 7. 枚举操作

### 7.1 枚举标签操作

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_getEnumCaseMultiPayload` | `(obj, enumType) → int32` | 获取多载荷枚举 case | `include/swift/Runtime/RuntimeFunctions.def:1603-1610` |
| `swift_getEnumTagSinglePayloadGeneric` | `(obj, numEmptyCases, payloadType, getExtraInhabitantIndex) → int32` | 获取单载荷枚举标签 | `include/swift/Runtime/RuntimeFunctions.def:1618-1625` |
| `swift_storeEnumTagSinglePayloadGeneric` | `(obj, caseIndex, numEmptyCases, payloadType, storeExtraInhabitant)` | 存储单载荷枚举标签 | `include/swift/Runtime/RuntimeFunctions.def:1636-1643` |
| `swift_storeEnumTagMultiPayload` | `(obj, enumType, caseIndex)` | 存储多载荷枚举标签 | `include/swift/Runtime/RuntimeFunctions.def:1647-1654` |
| `swift_getMultiPayloadEnumTagSinglePayload` | `(value, numExtraCases, enumType) → int32` | 多载荷枚举单载荷标签 | `include/swift/Runtime/RuntimeFunctions.def:2809-2816` |
| `swift_storeMultiPayloadEnumTagSinglePayload` | `(value, index, numExtraCases, enumType)` | 存储多载荷枚举单载荷标签 | `include/swift/Runtime/RuntimeFunctions.def:2823-2830` |

---

## 8. 异常处理 / 错误处理

### 8.1 错误分配和生命周期

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_allocError` | `(metadata, witnessTable, errorType, isUnconditionalThrow) → (errorPtr, valuePtr)` | 分配错误存在类型 | `include/swift/Runtime/RuntimeFunctions.def:2152-2157` |
| `swift_deallocError` | `(errorPtr, metadata)` | 释放错误 | `include/swift/Runtime/RuntimeFunctions.def:2158-2163` |
| `swift_getErrorValue` | `(errorPtr, namePtr, outTriple)` | 获取错误值 | `include/swift/Runtime/RuntimeFunctions.def:2164-2169` |
| `swift_willThrow` | `(errorPtr, context)` | 抛出前调用 | `include/swift/Runtime/RuntimeFunctions.def:184-189` |
| `swift_errorInMain` | `(errorPtr)` | main 中的错误 | `include/swift/Runtime/RuntimeFunctions.def:192-197` |
| `swift_unexpectedError` | `(errorPtr)` | 意外错误（不返回） | `include/swift/Runtime/RuntimeFunctions.def:200-205` |
| `_swift_exceptionPersonality` | `(version, actions, exceptionClass, exceptionObject, context) → int32` | 异常个性函数 | `include/swift/Runtime/RuntimeFunctions.def:3100-3111` |

**源码**: `lib/IRGen/IRGenModule.cpp:1176-1185` — `swift_willThrow` 特殊属性处理

### 8.2 错误引用计数

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_errorRetain` | `(ptr) → ptr` | 保留错误对象 | `include/swift/Runtime/RuntimeFunctions.def:494-500` |
| `swift_errorRelease` | `(ptr)` | 释放错误对象 | `include/swift/Runtime/RuntimeFunctions.def:503-509` |

---

## 9. FFI / 互操作模式

### 9.1 Objective-C 运行时

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `objc_msgSend` | `(receiver, selector, ...)` | ObjC 消息发送 | `include/swift/Runtime/RuntimeFunctions.def:1991-1993` |
| `objc_msgSend_stret` | `(receiver, selector, ...)` | ObjC 消息发送（结构体返回） | `include/swift/Runtime/RuntimeFunctions.def:1994-1997` |
| `objc_msgSendSuper` | `(super, selector, ...)` | ObjC super 消息发送 | `include/swift/Runtime/RuntimeFunctions.def:1998-2001` |
| `objc_msgSendSuper2` | `(super, selector, ...)` | ObjC super2 消息发送 | `include/swift/Runtime/RuntimeFunctions.def:2006-2009` |
| `objc_allocWithZone` | `(class) → ptr` | 分配 ObjC 对象 | `include/swift/Runtime/RuntimeFunctions.def:1985-1989` |
| `objc_getClass` | `(name) → ptr` | 按名称获取 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:2033-2038` |
| `objc_getRequiredClass` | `(name) → ptr` | 获取必需的 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:2039-2044` |
| `objc_getMetaClass` | `(name) → ptr` | 获取 ObjC 元类 | `include/swift/Runtime/RuntimeFunctions.def:2045-2050` |
| `objc_getProtocol` | `(name) → ptr` | 获取 ObjC 协议 | `include/swift/Runtime/RuntimeFunctions.def:2058-2063` |
| `objc_allocateProtocol` | `(name) → ptr` | 分配 ObjC 协议 | `include/swift/Runtime/RuntimeFunctions.def:2064-2069` |
| `objc_registerProtocol` | `(protocol)` | 注册 ObjC 协议 | `include/swift/Runtime/RuntimeFunctions.def:2070-2075` |
| `objc_opt_self` | `(class) → ptr` | 优化的 self 调用 | `include/swift/Runtime/RuntimeFunctions.def:2092-2098` |
| `object_getClass` | `(object) → ptr` | 获取 ObjC 对象的类 | `include/swift/Runtime/RuntimeFunctions.def:1660-1665` |
| `object_dispose` | `(object) → ptr` | 释放 ObjC 对象 | `include/swift/Runtime/RuntimeFunctions.def:1669-1674` |
| `sel_registerName` | `(name) → ptr` | 注册选择器 | `include/swift/Runtime/RuntimeFunctions.def:2014-2018` |
| `class_replaceMethod` | `(class, selector, imp, types) → ptr` | 替换类方法 | `include/swift/Runtime/RuntimeFunctions.def:2019-2025` |
| `class_addProtocol` | `(class, protocol)` | 为类添加协议 | `include/swift/Runtime/RuntimeFunctions.def:2026-2032` |
| `class_getName` | `(class) → ptr` | 获取类名 | `include/swift/Runtime/RuntimeFunctions.def:2051-2056` |

**源码**: `lib/IRGen/GenObjC.cpp:169` — `objc_msgSend` 桩生成, `lib/IRGen/SwiftTargetInfo.h:102` — 架构特定的 `objc_msgSend` 变体

### 9.2 Objective-C 块

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `_Block_copy` | `(block) → ptr` | 将 ObjC 块复制到堆 | `include/swift/Runtime/RuntimeFunctions.def:2121-2126` |
| `_Block_release` | `(block)` | 释放 ObjC 块 | `include/swift/Runtime/RuntimeFunctions.def:2128-2133` |

### 9.3 ObjC 桥接运行时

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_instantiateObjCClass` | `(metadata)` | 实例化 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:1978-1984` |
| `swift_getInitializedObjCClass` | `(class) → ptr` | 获取已初始化的 ObjC 类 | `include/swift/Runtime/RuntimeFunctions.def:2230-2236` |
| `swift_objc_swift3ImplicitObjCEntrypoint` | `(self, selector, filename, line, col, col, message)` | Swift 3 隐式 ObjC 入口点 | `include/swift/Runtime/RuntimeFunctions.def:2239-2245` |

---

## 10. 调用约定

### 10.1 Swift 调用约定（`swiftcc`）

Swift 使用自定义调用约定（`llvm::CallingConv::Swift`）进行 Swift 到 Swift 的调用。

**关键特征：**
- `swiftself` 参数属性用于 `self` 参数
- `swifterror` 参数属性用于错误返回
- 需要时通过 `sret` 属性间接返回
- 厚函数指针的上下文参数

**源码**: `lib/IRGen/IRGenModule.cpp:556` — `SwiftCC = llvm::CallingConv::Swift`, `lib/IRGen/GenCall.cpp:374` — 调用约定选择

### 10.2 参数属性

| 属性 | 描述 | 源码证据 |
|------|------|----------|
| `swiftself` | 方法调用中的 self 参数 | `lib/IRGen/GenCall.cpp:528-531` |
| `swifterror` | 错误返回参数 | `lib/IRGen/GenCall.cpp:5461-5472` |
| `sret` | 间接返回指针 | `lib/IRGen/GenCall.cpp:709, 755` |
| `swiftasync` | 异步上下文参数 | `lib/IRGen/GenCall.cpp:3541` |

### 10.3 调用约定变体

| 约定 | 用途 | 源码证据 |
|------|------|----------|
| `C_CC` | C 调用约定（运行时默认） | `include/swift/Runtime/RuntimeFunctions.def:69` |
| `SwiftCC` | Swift 调用约定 | `include/swift/Runtime/RuntimeFunctions.def:52` |
| `SwiftDirectRR_CC` | Swift 直接引用计数 | `include/swift/Runtime/RuntimeFunctions.def:232` |
| `SwiftAsyncCC` | Swift 异步调用约定 | `include/swift/Runtime/RuntimeFunctions.def:2144` |

---

## 11. 并发

### 11.1 任务管理

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_task_create` | `(flags, options, resultType, entry, context) → (task, context)` | 创建异步任务 | `include/swift/Runtime/RuntimeFunctions.def:2383-2394` |
| `swift_task_switch` | `(resumeContext, resumeFunction, newExecutor)` | 切换任务执行 | `include/swift/Runtime/RuntimeFunctions.def:2399-2406` |
| `swift_task_cancel` | `(task)` | 取消任务 | `include/swift/Runtime/RuntimeFunctions.def:2370-2376` |
| `swift_task_getCurrent` | `() → task` | 获取当前任务 | `include/swift/Runtime/RuntimeFunctions.def:2329-2336` |
| `swift_task_alloc` | `(size) → ptr` | 分配任务本地内存 | `include/swift/Runtime/RuntimeFunctions.def:2339-2346` |
| `swift_task_dealloc` | `(ptr)` | 释放任务本地内存 | `include/swift/Runtime/RuntimeFunctions.def:2349-2356` |
| `swift_task_getCurrentExecutor` | `() → executor` | 获取当前执行器 | `include/swift/Runtime/RuntimeFunctions.def:2487-2494` |
| `swift_task_getMainExecutor` | `() → executor` | 获取主执行器 | `include/swift/Runtime/RuntimeFunctions.def:2497-2504` |

### 11.2 Actor 操作

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_defaultActor_initialize` | `(actor)` | 初始化默认 actor | `include/swift/Runtime/RuntimeFunctions.def:2507-2514` |
| `swift_defaultActor_destroy` | `(actor)` | 销毁默认 actor | `include/swift/Runtime/RuntimeFunctions.def:2517-2524` |
| `swift_defaultActor_deallocate` | `(actor)` | 释放默认 actor | `include/swift/Runtime/RuntimeFunctions.def:2527-2534` |

### 11.3 延续

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_continuation_init` | `(context, flags) → task` | 初始化延续 | `include/swift/Runtime/RuntimeFunctions.def:2436-2443` |
| `swift_continuation_await` | `(context)` | 等待延续 | `include/swift/Runtime/RuntimeFunctions.def:2446-2453` |
| `swift_continuation_resume` | `(task)` | 恢复延续 | `include/swift/Runtime/RuntimeFunctions.def:2456-2463` |
| `swift_continuation_throwingResume` | `(task)` | 恢复抛出延续 | `include/swift/Runtime/RuntimeFunctions.def:2466-2473` |
| `swift_continuation_throwingResumeWithError` | `(task, error)` | 带错误恢复 | `include/swift/Runtime/RuntimeFunctions.def:2477-2484` |

### 11.4 任务组

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_taskGroup_initialize` | `(group, type)` | 初始化任务组 | `include/swift/Runtime/RuntimeFunctions.def:2633-2640` |
| `swift_taskGroup_destroy` | `(group)` | 销毁任务组 | `include/swift/Runtime/RuntimeFunctions.def:2670-2677` |

---

## 12. 排他性检查

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_beginAccess` | `(pointer, scratch, flags, pc)` | 开始内存访问 | `include/swift/Runtime/RuntimeFunctions.def:1947-1952` |
| `swift_endAccess` | `(scratch)` | 结束内存访问 | `include/swift/Runtime/RuntimeFunctions.def:1955-1960` |

---

## 13. 标准库注册

| IR 符号 | 参数 | 描述 | 源码证据 |
|---------|------|------|----------|
| `swift_once` | `(predicate, function, context)` | 一次性分发（惰性初始化） | `include/swift/Runtime/RuntimeFunctions.def:1912-1917` |
| `swift_registerProtocols` | `(begin, end)` | 注册协议 | `include/swift/Runtime/RuntimeFunctions.def:1921-1927` |
| `swift_registerProtocolConformances` | `(begin, end)` | 注册协议一致性 | `include/swift/Runtime/RuntimeFunctions.def:1931-1937` |
| `swift_registerTypeMetadataRecords` | `(begin, end)` | 注册类型元数据记录 | `include/swift/Runtime/RuntimeFunctions.def:1938-1944` |
| `swift_lookUpClassMethod` | `(metadata, description, method) → ptr` | 查找类方法 | `include/swift/Runtime/RuntimeFunctions.def:1490-1496` |

---

## 14. 静态分析关键要点

### 用户代码（需要分析）

- **修饰符号**: 任何以 `$s`、`_$s`、`$S`、`_$S`、`_T0`、`$e` 或 `_$e` 开头的符号都是 Swift 修饰的用户符号。反修饰可恢复模块、类型和函数名。
- **未修饰的 C/ObjC 符号**: 通过 `@objc`、`@_cdecl` 或 `@convention(c)` 导入的函数以其原始 C 名称出现。
- **协议见证**: 用户定义的协议实现出现在见证表中。

### 编译器运行时（过滤/跳过）

- **ARC 操作**（约 50+ 个函数）: `swift_retain*`、`swift_release*`、`swift_allocObject*`、`swift_deallocObject*`、`swift_bridgeObjectRetain*`、`swift_errorRetain*`、`swift_weak*`、`swift_unowned*`、`swift_unknownObject*`
- **元数据操作**（约 40+ 个函数）: `swift_get*Metadata*`、`swift_init*Metadata*`、`swift_checkMetadataState`、`swift_allocateGeneric*`
- **类型转换操作**（约 20+ 个函数）: `swift_dynamicCast*`、`swift_conformsToProtocol*`
- **见证表操作**: `swift_getWitnessTable*`、`swift_getAssociatedTypeWitness*`、`swift_getAssociatedConformanceWitness*`
- **值见证操作**: `swift_cvw_*`
- **枚举标签操作**: `swift_getEnumTag*`、`swift_storeEnumTag*`
- **并发操作**: `swift_task*`、`swift_defaultActor*`、`swift_continuation*`、`swift_taskGroup*`、`swift_asyncLet*`
- **排他性检查**: `swift_beginAccess`、`swift_endAccess`
- **错误生命周期**: `swift_allocError`、`swift_deallocError`、`swift_willThrow`、`swift_errorRetain`、`swift_errorRelease`
- **注册**: `swift_once`、`swift_register*`
- **C 运行时**: `malloc`、`free`、`memset_s`
- **块运行时**: `_Block_copy`、`_Block_release`
- **LLVM 内建函数**: `@llvm.*`

### FFI 边界（单独分类）

- **Objective-C 运行时**: `objc_msgSend*`、`objc_allocWithZone`、`objc_getClass*`、`object_getClass`、`sel_registerName`、`class_*`、`protocol_*`
- **桥接类型**: `swift_bridgeObjectRetain*` / `swift_bridgeObjectRelease*` 表示 Swift-ObjC 桥接
- **未知对象操作**: `swift_unknownObjectRetain*` / `swift_unknownObjectRelease*` 表示存在类型或 ObjC 类型引用
- **块操作**: `_Block_copy`、`_Block_release` 表示 ObjC 块互操作
- **`@convention(c)` 函数**: 使用 C 调用约定的函数
- **`@convention(block)` 函数**: ObjC 块回调

### ARC 安全分析要点

1. **保留/释放平衡**: 每个 `swift_retain` 在所有路径上都应有匹配的 `swift_release`
2. **保留循环**: 检测强引用图中的循环（特别是闭包捕获 `self`）
3. **释放后使用**: 检测在 `swift_release` 后（引用计数降为零时）访问对象
4. **弱引用安全**: `swift_weakLoadStrong` 可以返回 null；代码必须处理 nil 情况
5. **无主引用安全**: 在释放后访问无主引用是未定义行为
6. **桥接对象生命周期**: 桥接对象有双重引用计数（Swift + ObjC）
7. **错误对象生命周期**: 错误是引用计数的，必须保持平衡

### 元数据安全分析要点

1. **元数据初始化顺序**: 元数据必须在使用前完全初始化
2. **泛型元数据实例化**: `swift_getGenericMetadata` 可能触发惰性初始化
3. **协议一致性有效性**: `swift_conformsToProtocol` 在无一致性时返回 null
4. **动态转换安全**: `swift_dynamicCastClass` 失败时返回 null；无条件变体会陷入
