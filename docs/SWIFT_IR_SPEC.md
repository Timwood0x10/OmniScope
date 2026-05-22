# Swift LLVM IR Specification: Compiler-Reserved vs User-Defined

**Source**: `/Users/scc/code/researcher/swift` (main branch)
**Date**: 2026-05-22
**Purpose**: Distinguish compiler-reserved IR patterns from user-defined symbols for static analysis tools (e.g., OmniScope)

---

## 1. Symbol Naming / Mangling Rules

### 1.1 Mangling Prefixes

Swift uses a mangling scheme to encode type information and module context into symbol names. The mangling prefix identifies a symbol as a Swift-mangled name.

| Prefix | Swift Version | Source Evidence |
|--------|---------------|-----------------|
| `$s` | Swift 5+ | `include/swift/Demangling/ManglingMacros.h:24` |
| `_$s` | Swift 5+ (with underscore prefix) | `lib/Demangling/Demangler.cpp:188` |
| `$S` / `_$S` | Swift 4.x | `lib/Demangling/Demangler.cpp:187` |
| `_T0` | Swift 4 | `lib/Demangling/Demangler.cpp:186` |
| `$e` / `_$e` | Embedded Swift | `include/swift/Demangling/ManglingMacros.h:25`, `lib/Demangling/Demangler.cpp:189` |
| `@__swiftmacro_` | Swift macro filenames | `lib/Demangling/Demangler.cpp:190` |

**Source**: `lib/Demangling/Demangler.cpp:182-200` — `getManglingPrefixLength()`

### 1.2 Mangling Grammar (Operator Characters)

The mangling scheme uses single-character operators to encode different entity types. After the prefix, the first character identifies the entity kind.

| Character | Entity Kind | Source Evidence |
|-----------|-------------|-----------------|
| `C` | Class | `lib/Demangling/Demangler.cpp:1054` |
| `V` | Structure (value type) | `lib/Demangling/Demangler.cpp:1105` |
| `O` | Enum | `lib/Demangling/Demangler.cpp:1099` |
| `P` | Protocol | `lib/Demangling/Demangler.cpp:1100` |
| `E` | Extension | `lib/Demangling/Demangler.cpp:1056` |
| `F` | Function | `lib/Demangling/Demangler.cpp:1057` |
| `G` | Bound generic type | `lib/Demangling/Demangler.cpp:1058` |
| `I` | Implementation function type | `lib/Demangling/Demangler.cpp:1093` |
| `M` | Metatype | `lib/Demangling/Demangler.cpp:1096` |
| `N` | Type metadata | `lib/Demangling/Demangler.cpp:1097` |
| `Q` | Archetype | `lib/Demangling/Demangler.cpp:1101` |
| `R` | Generic requirement | `lib/Demangling/Demangler.cpp:1102` |
| `S` | Standard substitution | `lib/Demangling/Demangler.cpp:1103` |
| `T` | Thunk or specialization | `lib/Demangling/Demangler.cpp:1104` |
| `W` | Witness | `lib/Demangling/Demangler.cpp:1106` |
| `X` | Special type | `lib/Demangling/Demangler.cpp:1107` |
| `Y` | Type annotation | `lib/Demangling/Demangler.cpp:1108` |
| `Z` | Static | `lib/Demangling/Demangler.cpp:1109` |
| `a` | Type alias | `lib/Demangling/Demangler.cpp:1110` |
| `c` | Function type | `lib/Demangling/Demangler.cpp:1111` |
| `f` | Function entity | `lib/Demangling/Demangler.cpp:1113` |
| `i` | Subscript | `lib/Demangling/Demangler.cpp:1117` |
| `m` | Metatype type | `lib/Demangling/Demangler.cpp:1119` |
| `v` | Variable | `lib/Demangling/Demangler.cpp:1131` |
| `w` | Value witness | `lib/Demangling/Demangler.cpp:1132` |

### 1.3 Operator Character Encoding

Operators are encoded to avoid ambiguity in mangled names.

| Operator | Encoded As | Source Evidence |
|----------|------------|-----------------|
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

**Source**: `lib/Demangling/ManglingUtils.cpp:46-67` — `translateOperatorChar()`

### 1.4 Standard Type Substitutions

Common standard library types have abbreviated mangling forms.

| Type | Mangling | Source Evidence |
|------|----------|-----------------|
| `Swift` (module) | `s` | `lib/Demangling/Demangler.cpp:1128` |
| `Any` | `yp` | `include/swift/Demangling/ManglingMacros.h:46` |
| `AnyObject` | `yXl` | `include/swift/Demangling/ManglingMacros.h:47` |
| `()` (empty tuple) | `yt` | `include/swift/Demangling/ManglingMacros.h:45` |

**Source**: `include/swift/Demangling/ManglingMacros.h:43-48`, `lib/Demangling/ManglingUtils.cpp:77-93`

### 1.5 Symbolic References

Swift 5+ supports symbolic references in mangled names for protocol conformance and type descriptors.

| Raw Kind | Symbolic Reference Kind | Source Evidence |
|----------|------------------------|-----------------|
| `0x01` | Context (direct) | `lib/Demangling/Demangler.cpp:947` |
| `0x02` | Context (indirect) | `lib/Demangling/Demangler.cpp:951` |
| `0x09` | Accessor function reference | `lib/Demangling/Demangler.cpp:955` |
| `0x0a` | Unique extended existential type shape | `lib/Demangling/Demangler.cpp:959` |
| `0x0b` | Non-unique extended existential type shape | `lib/Demangling/Demangler.cpp:963` |
| `0x0c` | Objective-C protocol | `lib/Demangling/Demangler.cpp:967` |

**Source**: `lib/Demangling/Demangler.cpp:932-999` — `demangleSymbolicReference()`

---

## 2. ARC (Automatic Reference Counting) in IR

### 2.1 Strong Reference Counting

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_retain` | `(ptr) → ptr` | Increment strong reference count | `include/swift/Runtime/RuntimeFunctions.def:216-221` |
| `swift_release` | `(ptr)` | Decrement strong reference count, dealloc if zero | `include/swift/Runtime/RuntimeFunctions.def:224-229` |
| `swift_retain_n` | `(ptr, n) → ptr` | Increment strong reference count by n | `include/swift/Runtime/RuntimeFunctions.def:256-261` |
| `swift_release_n` | `(ptr, n)` | Decrement strong reference count by n | `include/swift/Runtime/RuntimeFunctions.def:264-269` |
| `swift_nonatomic_retain` | `(ptr) → ptr` | Non-atomic strong retain | `include/swift/Runtime/RuntimeFunctions.def:369-375` |
| `swift_nonatomic_release` | `(ptr)` | Non-atomic strong release | `include/swift/Runtime/RuntimeFunctions.def:378-384` |
| `swift_nonatomic_retain_n` | `(ptr, n) → ptr` | Non-atomic bulk retain | `include/swift/Runtime/RuntimeFunctions.def:281-286` |
| `swift_nonatomic_release_n` | `(ptr, n)` | Non-atomic bulk release | `include/swift/Runtime/RuntimeFunctions.def:289-294` |
| `swift_retainDirect` | `(ptr) → ptr` | Direct calling convention retain | `include/swift/Runtime/RuntimeFunctions.def:232-237` |
| `swift_releaseDirect` | `(ptr)` | Direct calling convention release | `include/swift/Runtime/RuntimeFunctions.def:240-245` |
| `swift_tryRetain` | `(ptr) → ptr` | Conditional retain (returns null if deallocating) | `include/swift/Runtime/RuntimeFunctions.def:387-392` |
| `swift_setDeallocating` | `(ptr)` | Mark object as deallocating | `include/swift/Runtime/RuntimeFunctions.def:272-278` |
| `swift_isDeallocating` | `(ptr) → bool` | Check if object is deallocating | `include/swift/Runtime/RuntimeFunctions.def:395-400` |

### 2.2 Unknown Object Reference Counting

For Objective-C interop and existential types where the refcounting strategy is unknown at compile time.

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_unknownObjectRetain` | `(ptr) → ptr` | Retain unknown refcounted object | `include/swift/Runtime/RuntimeFunctions.def:403-408` |
| `swift_unknownObjectRelease` | `(ptr)` | Release unknown refcounted object | `include/swift/Runtime/RuntimeFunctions.def:411-417` |
| `swift_unknownObjectRetain_n` | `(ptr, n) → ptr` | Bulk unknown retain | `include/swift/Runtime/RuntimeFunctions.def:297-303` |
| `swift_unknownObjectRelease_n` | `(ptr, n)` | Bulk unknown release | `include/swift/Runtime/RuntimeFunctions.def:306-312` |
| `swift_nonatomic_unknownObjectRetain` | `(ptr) → ptr` | Non-atomic unknown retain | `include/swift/Runtime/RuntimeFunctions.def:420-426` |
| `swift_nonatomic_unknownObjectRelease` | `(ptr)` | Non-atomic unknown release | `include/swift/Runtime/RuntimeFunctions.def:429-435` |

### 2.3 Bridge Object Reference Counting

For bridged types between Swift and Objective-C (e.g., `String` ↔ `NSString`).

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_bridgeObjectRetain` | `(ptr) → ptr` | Retain bridge object | `include/swift/Runtime/RuntimeFunctions.def:438-444` |
| `swift_bridgeObjectRelease` | `(ptr)` | Release bridge object | `include/swift/Runtime/RuntimeFunctions.def:447-453` |
| `swift_bridgeObjectRetain_n` | `(ptr, n) → ptr` | Bulk bridge retain | `include/swift/Runtime/RuntimeFunctions.def:333-339` |
| `swift_bridgeObjectRelease_n` | `(ptr, n)` | Bulk bridge release | `include/swift/Runtime/RuntimeFunctions.def:342-348` |
| `swift_bridgeObjectRetainDirect` | `(ptr) → ptr` | Direct CC bridge retain | `include/swift/Runtime/RuntimeFunctions.def:456-462` |
| `swift_bridgeObjectReleaseDirect` | `(ptr)` | Direct CC bridge release | `include/swift/Runtime/RuntimeFunctions.def:465-471` |
| `swift_nonatomic_bridgeObjectRetain` | `(ptr) → ptr` | Non-atomic bridge retain | `include/swift/Runtime/RuntimeFunctions.def:474-480` |
| `swift_nonatomic_bridgeObjectRelease` | `(ptr)` | Non-atomic bridge release | `include/swift/Runtime/RuntimeFunctions.def:483-490` |

### 2.4 Error Reference Counting

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_errorRetain` | `(ptr) → ptr` | Retain error object | `include/swift/Runtime/RuntimeFunctions.def:494-500` |
| `swift_errorRelease` | `(ptr)` | Release error object | `include/swift/Runtime/RuntimeFunctions.def:503-509` |

### 2.5 Weak and Unowned References

Weak and unowned references are generated via macro expansion from `ReferenceStorage.def`. The runtime functions follow the pattern `swift_<kind>Init`, `swift_<kind>Destroy`, `swift_<kind>LoadStrong`, etc.

| Reference Kind | IR Symbols | Source Evidence |
|----------------|------------|-----------------|
| `weak` (native) | `swift_weakInit`, `swift_weakDestroy`, `swift_weakLoadStrong`, `swift_weakTakeStrong`, `swift_weakCopyInit`, `swift_weakTakeInit`, `swift_weakCopyAssign`, `swift_weakTakeAssign` | `include/swift/Runtime/RuntimeFunctions.def:511-583` (macro expansion) |
| `weak` (unknown) | `swift_unknownObjectWeakInit`, `swift_unknownObjectWeakDestroy`, `swift_unknownObjectWeakLoadStrong`, etc. | Same macro expansion |
| `unowned` (native) | `swift_unownedRetain`, `swift_unownedRelease`, `swift_unownedRetainStrong`, `swift_unownedRetainStrongAndRelease` | `include/swift/Runtime/RuntimeFunctions.def:588-621` (macro expansion) |
| `unowned` (unknown) | `swift_unknownObjectUnownedRetain`, `swift_unknownObjectUnownedRelease`, etc. | Same macro expansion |

**Source**: `include/swift/AST/ReferenceStorage.def` — defines `WEAK`, `UNOWNED`, `UNMANAGED` storage kinds; `include/swift/Runtime/RuntimeFunctions.def:511-629` — macro-generated functions

### 2.6 Heap Allocation

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_allocObject` | `(metadata, size, alignMask) → ptr` | Allocate heap object | `include/swift/Runtime/RuntimeFunctions.def:92-97` |
| `swift_allocObjectTyped` | `(metadata, size, alignMask, typeId) → ptr` | Allocate typed heap object | `include/swift/Runtime/RuntimeFunctions.def:100-105` |
| `swift_deallocObject` | `(obj, size, alignMask)` | Deallocate heap object | `include/swift/Runtime/RuntimeFunctions.def:134-139` |
| `swift_deallocUninitializedObject` | `(obj, size, alignMask)` | Deallocate uninitialized object | `include/swift/Runtime/RuntimeFunctions.def:142-148` |
| `swift_deallocClassInstance` | `(obj, size, alignMask)` | Deallocate class instance | `include/swift/Runtime/RuntimeFunctions.def:151-156` |
| `swift_deallocPartialClassInstance` | `(obj, metadata, size, alignMask)` | Deallocate partially initialized class | `include/swift/Runtime/RuntimeFunctions.def:159-165` |
| `swift_initStackObject` | `(metadata, object) → ptr` | Initialize stack-allocated object | `include/swift/Runtime/RuntimeFunctions.def:109-114` |
| `swift_initStaticObject` | `(metadata, object) → ptr` | Initialize static object | `include/swift/Runtime/RuntimeFunctions.def:118-123` |
| `swift_allocBox` | `(metadata) → (refPtr, boxPtr)` | Allocate box for existential/protocol | `include/swift/Runtime/RuntimeFunctions.def:52-57` |
| `swift_deallocBox` | `(refPtr)` | Deallocate box | `include/swift/Runtime/RuntimeFunctions.def:69-74` |
| `swift_projectBox` | `(refPtr) → ptr` | Project value pointer from box | `include/swift/Runtime/RuntimeFunctions.def:77-82` |
| `swift_makeBoxUnique` | `(buffer, metadata, alignMask) → (refPtr, boxPtr)` | Make box unique (COW) | `include/swift/Runtime/RuntimeFunctions.def:60-67` |
| `swift_allocEmptyBox` | `() → ptr` | Allocate empty box | `include/swift/Runtime/RuntimeFunctions.def:84-89` |
| `swift_slowAlloc` | `(size, alignMask) → ptr` | Slow path allocation | `include/swift/Runtime/RuntimeFunctions.def:168-173` |
| `swift_slowDealloc` | `(ptr, size, alignMask)` | Slow path deallocation | `include/swift/Runtime/RuntimeFunctions.def:176-181` |

### 2.7 Uniqueness Checking (COW)

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_isUniquelyReferencedNonObjC` | `(ptr) → bool` | Check unique reference (non-ObjC) | `include/swift/Runtime/RuntimeFunctions.def:634-640` |
| `swift_isUniquelyReferencedNonObjC_nonNull` | `(ptr) → bool` | Non-null variant | `include/swift/Runtime/RuntimeFunctions.def:643-650` |
| `swift_isUniquelyReferenced_nonNull_native` | `(ptr) → bool` | Native non-null unique check | `include/swift/Runtime/RuntimeFunctions.def:703-710` |
| `swift_isUniquelyReferenced_native` | `(ptr) → bool` | Native unique check | `include/swift/Runtime/RuntimeFunctions.def:694-700` |
| `swift_isEscapingClosureAtFileLocation` | `(object, filename, len, line, col, type) → bool` | Closure escape check | `include/swift/Runtime/RuntimeFunctions.def:718-724` |

### 2.8 Array Value Operations

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_arrayInitWithCopy` | `(dest, src, count, metadata)` | Copy-initialize array | `include/swift/Runtime/RuntimeFunctions.def:727-733` |
| `swift_arrayInitWithTakeNoAlias` | `(dest, src, count, metadata)` | Take-initialize array (no alias) | `include/swift/Runtime/RuntimeFunctions.def:736-742` |
| `swift_arrayInitWithTakeFrontToBack` | `(dest, src, count, metadata)` | Take front-to-back | `include/swift/Runtime/RuntimeFunctions.def:745-751` |
| `swift_arrayInitWithTakeBackToFront` | `(dest, src, count, metadata)` | Take back-to-front | `include/swift/Runtime/RuntimeFunctions.def:754-760` |
| `swift_arrayAssignWithCopyNoAlias` | `(dest, src, count, metadata)` | Copy-assign (no alias) | `include/swift/Runtime/RuntimeFunctions.def:763-769` |
| `swift_arrayAssignWithCopyFrontToBack` | `(dest, src, count, metadata)` | Copy-assign front-to-back | `include/swift/Runtime/RuntimeFunctions.def:772-778` |
| `swift_arrayAssignWithCopyBackToFront` | `(dest, src, count, metadata)` | Copy-assign back-to-front | `include/swift/Runtime/RuntimeFunctions.def:781-787` |
| `swift_arrayAssignWithTake` | `(dest, src, count, metadata)` | Take-assign array | `include/swift/Runtime/RuntimeFunctions.def:790-795` |
| `swift_arrayDestroy` | `(ptr, count, metadata)` | Destroy array elements | `include/swift/Runtime/RuntimeFunctions.def:798-803` |

---

## 3. Runtime Functions — Dynamic Casting

### 3.1 General Dynamic Cast

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_dynamicCast` | `(dest, src, srcMetadata, targetMetadata, flags) → bool` | General dynamic cast | `include/swift/Runtime/RuntimeFunctions.def:1801-1807` |
| `swift_dynamicCastClass` | `(object, targetMetadata) → ptr` | Class downcast (returns null on failure) | `include/swift/Runtime/RuntimeFunctions.def:1709-1714` |
| `swift_dynamicCastClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | Unconditional class downcast (trap on failure) | `include/swift/Runtime/RuntimeFunctions.def:1717-1723` |
| `swift_dynamicCastObjCClass` | `(object, targetMetadata) → ptr` | ObjC class downcast | `include/swift/Runtime/RuntimeFunctions.def:1726-1732` |
| `swift_dynamicCastObjCClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | Unconditional ObjC class downcast | `include/swift/Runtime/RuntimeFunctions.def:1735-1741` |
| `swift_dynamicCastUnknownClass` | `(object, targetMetadata) → ptr` | Unknown class downcast | `include/swift/Runtime/RuntimeFunctions.def:1744-1750` |
| `swift_dynamicCastUnknownClassUnconditional` | `(object, targetMetadata, filename, line, col) → ptr` | Unconditional unknown class downcast | `include/swift/Runtime/RuntimeFunctions.def:1753-1760` |

**Source**: `lib/IRGen/GenCast.cpp:45-69` — `getDynamicCastFlags()`

### 3.2 Metatype Casting

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_dynamicCastMetatype` | `(src, target) → ptr` | Metatype cast | `include/swift/Runtime/RuntimeFunctions.def:1763-1769` |
| `swift_dynamicCastMetatypeUnconditional` | `(src, target, filename, line, col) → ptr` | Unconditional metatype cast | `include/swift/Runtime/RuntimeFunctions.def:1772-1779` |
| `swift_dynamicCastObjCClassMetatype` | `(src, target) → ptr` | ObjC metatype cast | `include/swift/Runtime/RuntimeFunctions.def:1782-1788` |
| `swift_dynamicCastObjCClassMetatypeUnconditional` | `(src, target, filename, line, col) → ptr` | Unconditional ObjC metatype cast | `include/swift/Runtime/RuntimeFunctions.def:1791-1798` |

### 3.3 Protocol Conformance Checking

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_conformsToProtocol` | `(metadata, protocolDescriptor) → witnessTable` | Check protocol conformance | `include/swift/Runtime/RuntimeFunctions.def:1874-1880` |
| `swift_conformsToProtocol2` | `(metadata, protocolDescriptor) → witnessTable` | Protocol conformance (signed descriptors) | `include/swift/Runtime/RuntimeFunctions.def:1883-1889` |
| `swift_isClassType` | `(metadata) → bool` | Check if type is a class | `include/swift/Runtime/RuntimeFunctions.def:1892-1898` |
| `swift_isOptionalType` | `(metadata) → bool` | Check if type is Optional | `include/swift/Runtime/RuntimeFunctions.def:1901-1907` |

**Source**: `lib/IRGen/GenProto.cpp:807-815` — `swift_conformsToProtocol()` usage

### 3.4 ObjC Protocol Casting

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_dynamicCastTypeToObjCProtocolUnconditional` | `(type, numProtocols, protocols, filename, line, col) → ptr` | Type to ObjC protocol cast | `include/swift/Runtime/RuntimeFunctions.def:1812-1819` |
| `swift_dynamicCastTypeToObjCProtocolConditional` | `(type, numProtocols, protocols) → ptr` | Conditional type to ObjC protocol | `include/swift/Runtime/RuntimeFunctions.def:1824-1831` |
| `swift_dynamicCastObjCProtocolUnconditional` | `(object, numProtocols, protocols, filename, line, col) → ptr` | ObjC protocol cast | `include/swift/Runtime/RuntimeFunctions.def:1836-1842` |
| `swift_dynamicCastObjCProtocolConditional` | `(object, numProtocols, protocols) → ptr` | Conditional ObjC protocol cast | `include/swift/Runtime/RuntimeFunctions.def:1847-1853` |

---

## 4. Runtime Functions — Metadata

### 4.1 Metadata Access

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getSingletonMetadata` | `(request, descriptor) → response` | Get singleton type metadata | `include/swift/Runtime/RuntimeFunctions.def:971-977` |
| `swift_getGenericMetadata` | `(request, arguments, descriptor) → response` | Get generic type metadata | `include/swift/Runtime/RuntimeFunctions.def:982-988` |
| `swift_getCanonicalSpecializedMetadata` | `(request, candidate, cache) → response` | Get canonical specialized metadata | `include/swift/Runtime/RuntimeFunctions.def:992-998` |
| `swift_checkMetadataState` | `(request, metadata) → response` | Check/complete metadata state | `include/swift/Runtime/RuntimeFunctions.def:1114-1120` |
| `swift_getForeignTypeMetadata` | `(size, nonUnique) → response` | Get foreign type metadata | `include/swift/Runtime/RuntimeFunctions.def:947-953` |

**Source**: `lib/IRGen/GenMeta.cpp:89-100` — metadata slot addressing

### 4.2 Metadata Initialization

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_initClassMetadata` | `(self, flags, numFields, fieldTypes, fieldOffsets)` | Initialize class metadata | `include/swift/Runtime/RuntimeFunctions.def:1427-1433` |
| `swift_initClassMetadata2` | `(self, flags, numFields, fieldTypes, fieldOffsets) → dependency` | Initialize class metadata (v2) | `include/swift/Runtime/RuntimeFunctions.def:1453-1459` |
| `swift_updateClassMetadata` | `(self, flags, numFields, fieldTypes, fieldOffsets)` | Update class metadata | `include/swift/Runtime/RuntimeFunctions.def:1440-1446` |
| `swift_initStructMetadata` | `(structType, flags, numFields, fieldTypes, fieldOffsets)` | Initialize struct metadata | `include/swift/Runtime/RuntimeFunctions.def:1503-1509` |
| `swift_initEnumMetadataSingleCase` | `(enumType, flags, payload)` | Initialize single-case enum | `include/swift/Runtime/RuntimeFunctions.def:1528-1535` |
| `swift_initEnumMetadataSinglePayload` | `(enumType, flags, payload, numEmptyCases)` | Initialize single-payload enum | `include/swift/Runtime/RuntimeFunctions.def:1553-1560` |
| `swift_initEnumMetadataMultiPayload` | `(enumType, flags, numPayloads, payloadTypes)` | Initialize multi-payload enum | `include/swift/Runtime/RuntimeFunctions.def:1579-1586` |
| `swift_allocateGenericClassMetadata` | `(descriptor, arguments, template) → ptr` | Allocate generic class metadata | `include/swift/Runtime/RuntimeFunctions.def:1065-1071` |
| `swift_allocateGenericValueMetadata` | `(descriptor, arguments, template, extraSize) → ptr` | Allocate generic value metadata | `include/swift/Runtime/RuntimeFunctions.def:1090-1096` |
| `swift_relocateClassMetadata` | `(descriptor, pattern) → ptr` | Relocate class metadata | `include/swift/Runtime/RuntimeFunctions.def:1414-1420` |

### 4.3 Function Type Metadata

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getFunctionTypeMetadata` | `(flags, parameters, parameterFlags, result) → ptr` | Get function type metadata | `include/swift/Runtime/RuntimeFunctions.def:809-815` |
| `swift_getFunctionTypeMetadata0` | `(flags, result) → ptr` | 0-parameter function metadata | `include/swift/Runtime/RuntimeFunctions.def:901-907` |
| `swift_getFunctionTypeMetadata1` | `(flags, arg0, result) → ptr` | 1-parameter function metadata | `include/swift/Runtime/RuntimeFunctions.def:912-918` |
| `swift_getFunctionTypeMetadata2` | `(flags, arg0, arg1, result) → ptr` | 2-parameter function metadata | `include/swift/Runtime/RuntimeFunctions.def:924-930` |
| `swift_getFunctionTypeMetadata3` | `(flags, arg0, arg1, arg2, result) → ptr` | 3-parameter function metadata | `include/swift/Runtime/RuntimeFunctions.def:937-944` |
| `swift_getExtendedFunctionTypeMetadata` | `(flags, diffKind, params, paramFlags, result, globalActor, extFlags, thrownError) → ptr` | Extended function metadata | `include/swift/Runtime/RuntimeFunctions.def:841-855` |

### 4.4 Tuple Metadata

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getTupleTypeMetadata` | `(request, flags, elements, labels, proposed) → response` | Get tuple metadata | `include/swift/Runtime/RuntimeFunctions.def:1284-1289` |
| `swift_getTupleTypeMetadata2` | `(request, elt0, elt1, labels, proposed) → response` | 2-element tuple metadata | `include/swift/Runtime/RuntimeFunctions.def:1295-1301` |
| `swift_getTupleTypeMetadata3` | `(request, elt0, elt1, elt2, labels, proposed) → response` | 3-element tuple metadata | `include/swift/Runtime/RuntimeFunctions.def:1308-1314` |
| `swift_getTupleTypeLayout` | `(result, offsets, flags, elements)` | Get tuple layout | `include/swift/Runtime/RuntimeFunctions.def:1320-1325` |

### 4.5 Other Metadata

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getMetatypeMetadata` | `(instanceType) → ptr` | Get metatype metadata | `include/swift/Runtime/RuntimeFunctions.def:1235-1240` |
| `swift_getExistentialMetatypeMetadata` | `(instanceType) → ptr` | Get existential metatype | `include/swift/Runtime/RuntimeFunctions.def:1243-1249` |
| `swift_getExistentialTypeMetadata` | `(classConstraint, superclass, numProtocols, protocols) → ptr` | Get existential metadata | `include/swift/Runtime/RuntimeFunctions.def:1366-1373` |
| `swift_getFixedArrayTypeMetadata` | `(request, size, element) → response` | Get fixed array metadata | `include/swift/Runtime/RuntimeFunctions.def:1351-1357` |
| `swift_getObjCClassMetadata` | `(objcClass) → ptr` | Get Swift metadata from ObjC class | `include/swift/Runtime/RuntimeFunctions.def:1252-1258` |
| `swift_getObjCClassFromMetadata` | `(metadata) → ptr` | Get ObjC class from metadata | `include/swift/Runtime/RuntimeFunctions.def:1261-1267` |
| `swift_getObjCClassFromObject` | `(object) → ptr` | Get ObjC class from object | `include/swift/Runtime/RuntimeFunctions.def:1271-1277` |
| `swift_getObjectType` | `(object) → ptr` | Get type metadata from object | `include/swift/Runtime/RuntimeFunctions.def:1693-1698` |
| `swift_getDynamicType` | `(object, self, isMetatype) → ptr` | Get dynamic type | `include/swift/Runtime/RuntimeFunctions.def:1701-1706` |

### 4.6 Type Lookup by Mangled Name

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getTypeByMangledNameInContext` | `(name, length, context, genericArgs) → ptr` | Lookup type by mangled name | `include/swift/Runtime/RuntimeFunctions.def:2275-2281` |
| `swift_getTypeByMangledNameInContext2` | `(name, length, context, genericArgs) → ptr` | Lookup type (signed descriptors) | `include/swift/Runtime/RuntimeFunctions.def:2288-2294` |
| `swift_getTypeByMangledNameInContextInMetadataState` | `(state, name, length, context, genericArgs) → ptr` | Lookup in metadata state | `include/swift/Runtime/RuntimeFunctions.def:2302-2310` |

---

## 5. Protocol Witness Tables

### 5.1 Witness Table Access

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getWitnessTable` | `(conformanceDescriptor, type, instantiationArgs) → ptr` | Get/lazy-instantiate witness table | `include/swift/Runtime/RuntimeFunctions.def:1127-1134` |
| `swift_getWitnessTableRelative` | `(conformanceDescriptor, type, instantiationArgs) → ptr` | Get witness table (relative references) | `include/swift/Runtime/RuntimeFunctions.def:1136-1143` |

**Source**: `lib/IRGen/GenProto.cpp:1300` — `getWitnessTableLazyAccessFunction()`, `lib/IRGen/GenProto.cpp:1283` — conditional witness table instantiation

### 5.2 Associated Type Witnesses

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getAssociatedTypeWitness` | `(request, witnessTable, conformingType, reqBase, assocType) → response` | Get associated type witness | `include/swift/Runtime/RuntimeFunctions.def:1151-1157` |
| `swift_getAssociatedTypeWitnessRelative` | `(request, witnessTable, conformingType, reqBase, assocType) → response` | Associated type (relative refs) | `include/swift/Runtime/RuntimeFunctions.def:1158-1164` |
| `swift_getAssociatedConformanceWitness` | `(witnessTable, conformingType, assocType, reqBase, assocConformance) → ptr` | Get associated conformance witness | `include/swift/Runtime/RuntimeFunctions.def:1173-1183` |
| `swift_getAssociatedConformanceWitnessRelative` | `(witnessTable, conformingType, assocType, reqBase, assocConformance) → ptr` | Associated conformance (relative refs) | `include/swift/Runtime/RuntimeFunctions.def:1184-1194` |

### 5.3 Opaque Type Conformance

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getOpaqueTypeMetadata` | `(request, arguments, descriptor, index) → response` | Get opaque type metadata | `include/swift/Runtime/RuntimeFunctions.def:1018-1024` |
| `swift_getOpaqueTypeMetadata2` | `(request, arguments, descriptor, index) → response` | Opaque type metadata (v2) | `include/swift/Runtime/RuntimeFunctions.def:1031-1037` |
| `swift_getOpaqueTypeConformance` | `(arguments, descriptor, index) → ptr` | Get opaque type conformance | `include/swift/Runtime/RuntimeFunctions.def:1043-1049` |
| `swift_getOpaqueTypeConformance2` | `(arguments, descriptor, index) → ptr` | Opaque type conformance (v2) | `include/swift/Runtime/RuntimeFunctions.def:1054-1060` |

### 5.4 Pack Metadata and Witness Tables

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_allocateMetadataPack` | `(ptr, count) → ptr` | Allocate metadata pack | `include/swift/Runtime/RuntimeFunctions.def:1213-1220` |
| `swift_allocateWitnessTablePack` | `(ptr, count) → ptr` | Allocate witness table pack | `include/swift/Runtime/RuntimeFunctions.def:1225-1232` |

---

## 6. Value Witness Tables

### 6.1 Value Witness Functions

Value witnesses implement basic operations for copying, moving, and destroying values. The witness table is part of type metadata.

| Value Witness | Description | Source Evidence |
|---------------|-------------|-----------------|
| `AssignWithCopy` | Copy-assign value | `lib/IRGen/GenValueWitness.cpp:62` |
| `AssignWithTake` | Take-assign (move) value | `lib/IRGen/GenValueWitness.cpp:63` |
| `Destroy` | Destroy value | `lib/IRGen/GenValueWitness.cpp:64` |
| `InitializeBufferWithCopyOfBuffer` | Initialize buffer from another buffer | `lib/IRGen/GenValueWitness.cpp:65` |
| `InitializeWithCopy` | Copy-initialize value | `lib/IRGen/GenValueWitness.cpp:66` |
| `InitializeWithTake` | Take-initialize (move) value | `lib/IRGen/GenValueWitness.cpp:67` |
| `GetEnumTag` | Get enum case tag | `lib/IRGen/GenValueWitness.cpp:68` |
| `DestructiveProjectEnumData` | Project enum payload (destructive) | `lib/IRGen/GenValueWitness.cpp:69` |
| `DestructiveInjectEnumTag` | Inject enum tag (destructive) | `lib/IRGen/GenValueWitness.cpp:70` |
| `Size` | Type size | `lib/IRGen/GenValueWitness.cpp:71` |
| `Flags` | Type flags | `lib/IRGen/GenValueWitness.cpp:72` |
| `ExtraInhabitantCount` | Number of extra inhabitants | `lib/IRGen/GenValueWitness.cpp:73` |
| `Stride` | Type stride | `lib/IRGen/GenValueWitness.cpp:74` |
| `GetEnumTagSinglePayload` | Get tag for single-payload enum | `lib/IRGen/GenValueWitness.cpp:75` |
| `StoreEnumTagSinglePayload` | Store tag for single-payload enum | `lib/IRGen/GenValueWitness.cpp:76` |

### 6.2 Generic CVW (Compact Value Witness) Functions

These are runtime-implemented generic value witnesses for types with layout strings.

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_cvw_destroy` | `(ptr, metadata)` | Generic destroy | `include/swift/Runtime/RuntimeFunctions.def:2833-2840` |
| `swift_cvw_assignWithCopy` | `(dest, src, metadata) → ptr` | Generic copy-assign | `include/swift/Runtime/RuntimeFunctions.def:2844-2851` |
| `swift_cvw_assignWithTake` | `(dest, src, metadata) → ptr` | Generic take-assign | `include/swift/Runtime/RuntimeFunctions.def:2854-2861` |
| `swift_cvw_initWithCopy` | `(dest, src, metadata) → ptr` | Generic copy-init | `include/swift/Runtime/RuntimeFunctions.def:2864-2871` |
| `swift_cvw_initWithTake` | `(dest, src, metadata) → ptr` | Generic take-init | `include/swift/Runtime/RuntimeFunctions.def:2874-2881` |
| `swift_cvw_initializeBufferWithCopyOfBuffer` | `(dest, src, metadata) → ptr` | Generic buffer copy-init | `include/swift/Runtime/RuntimeFunctions.def:2884-2891` |

---

## 7. Enum Operations

### 7.1 Enum Tag Operations

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_getEnumCaseMultiPayload` | `(obj, enumType) → int32` | Get multi-payload enum case | `include/swift/Runtime/RuntimeFunctions.def:1603-1610` |
| `swift_getEnumTagSinglePayloadGeneric` | `(obj, numEmptyCases, payloadType, getExtraInhabitantIndex) → int32` | Get single-payload enum tag | `include/swift/Runtime/RuntimeFunctions.def:1618-1625` |
| `swift_storeEnumTagSinglePayloadGeneric` | `(obj, caseIndex, numEmptyCases, payloadType, storeExtraInhabitant)` | Store single-payload enum tag | `include/swift/Runtime/RuntimeFunctions.def:1636-1643` |
| `swift_storeEnumTagMultiPayload` | `(obj, enumType, caseIndex)` | Store multi-payload enum tag | `include/swift/Runtime/RuntimeFunctions.def:1647-1654` |
| `swift_getMultiPayloadEnumTagSinglePayload` | `(value, numExtraCases, enumType) → int32` | Multi-payload enum single-payload tag | `include/swift/Runtime/RuntimeFunctions.def:2809-2816` |
| `swift_storeMultiPayloadEnumTagSinglePayload` | `(value, index, numExtraCases, enumType)` | Store multi-payload enum single-payload tag | `include/swift/Runtime/RuntimeFunctions.def:2823-2830` |

---

## 8. Exception Handling / Error Handling

### 8.1 Error Allocation and Lifecycle

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_allocError` | `(metadata, witnessTable, errorType, isUnconditionalThrow) → (errorPtr, valuePtr)` | Allocate error existential | `include/swift/Runtime/RuntimeFunctions.def:2152-2157` |
| `swift_deallocError` | `(errorPtr, metadata)` | Deallocate error | `include/swift/Runtime/RuntimeFunctions.def:2158-2163` |
| `swift_getErrorValue` | `(errorPtr, namePtr, outTriple)` | Get error value | `include/swift/Runtime/RuntimeFunctions.def:2164-2169` |
| `swift_willThrow` | `(errorPtr, context)` | Called before throw | `include/swift/Runtime/RuntimeFunctions.def:184-189` |
| `swift_errorInMain` | `(errorPtr)` | Error in main | `include/swift/Runtime/RuntimeFunctions.def:192-197` |
| `swift_unexpectedError` | `(errorPtr)` | Unexpected error (noreturn) | `include/swift/Runtime/RuntimeFunctions.def:200-205` |
| `_swift_exceptionPersonality` | `(version, actions, exceptionClass, exceptionObject, context) → int32` | Exception personality function | `include/swift/Runtime/RuntimeFunctions.def:3100-3111` |

**Source**: `lib/IRGen/IRGenModule.cpp:1176-1185` — `swift_willThrow` special attribute handling

### 8.2 Error Reference Counting

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_errorRetain` | `(ptr) → ptr` | Retain error object | `include/swift/Runtime/RuntimeFunctions.def:494-500` |
| `swift_errorRelease` | `(ptr)` | Release error object | `include/swift/Runtime/RuntimeFunctions.def:503-509` |

---

## 9. FFI / Interop Patterns

### 9.1 Objective-C Runtime

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `objc_msgSend` | `(receiver, selector, ...)` | ObjC message send | `include/swift/Runtime/RuntimeFunctions.def:1991-1993` |
| `objc_msgSend_stret` | `(receiver, selector, ...)` | ObjC message send (struct return) | `include/swift/Runtime/RuntimeFunctions.def:1994-1997` |
| `objc_msgSendSuper` | `(super, selector, ...)` | ObjC super message send | `include/swift/Runtime/RuntimeFunctions.def:1998-2001` |
| `objc_msgSendSuper2` | `(super, selector, ...)` | ObjC super2 message send | `include/swift/Runtime/RuntimeFunctions.def:2006-2009` |
| `objc_allocWithZone` | `(class) → ptr` | Allocate ObjC object | `include/swift/Runtime/RuntimeFunctions.def:1985-1989` |
| `objc_getClass` | `(name) → ptr` | Get ObjC class by name | `include/swift/Runtime/RuntimeFunctions.def:2033-2038` |
| `objc_getRequiredClass` | `(name) → ptr` | Get required ObjC class | `include/swift/Runtime/RuntimeFunctions.def:2039-2044` |
| `objc_getMetaClass` | `(name) → ptr` | Get ObjC metaclass | `include/swift/Runtime/RuntimeFunctions.def:2045-2050` |
| `objc_getProtocol` | `(name) → ptr` | Get ObjC protocol | `include/swift/Runtime/RuntimeFunctions.def:2058-2063` |
| `objc_allocateProtocol` | `(name) → ptr` | Allocate ObjC protocol | `include/swift/Runtime/RuntimeFunctions.def:2064-2069` |
| `objc_registerProtocol` | `(protocol)` | Register ObjC protocol | `include/swift/Runtime/RuntimeFunctions.def:2070-2075` |
| `objc_opt_self` | `(class) → ptr` | Optimized self call | `include/swift/Runtime/RuntimeFunctions.def:2092-2098` |
| `object_getClass` | `(object) → ptr` | Get class of ObjC object | `include/swift/Runtime/RuntimeFunctions.def:1660-1665` |
| `object_dispose` | `(object) → ptr` | Dispose ObjC object | `include/swift/Runtime/RuntimeFunctions.def:1669-1674` |
| `sel_registerName` | `(name) → ptr` | Register selector | `include/swift/Runtime/RuntimeFunctions.def:2014-2018` |
| `class_replaceMethod` | `(class, selector, imp, types) → ptr` | Replace class method | `include/swift/Runtime/RuntimeFunctions.def:2019-2025` |
| `class_addProtocol` | `(class, protocol)` | Add protocol to class | `include/swift/Runtime/RuntimeFunctions.def:2026-2032` |
| `class_getName` | `(class) → ptr` | Get class name | `include/swift/Runtime/RuntimeFunctions.def:2051-2056` |

**Source**: `lib/IRGen/GenObjC.cpp:169` — `objc_msgSend` stub generation, `lib/IRGen/SwiftTargetInfo.h:102` — architecture-specific `objc_msgSend` variants

### 9.2 Objective-C Blocks

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `_Block_copy` | `(block) → ptr` | Copy ObjC block to heap | `include/swift/Runtime/RuntimeFunctions.def:2121-2126` |
| `_Block_release` | `(block)` | Release ObjC block | `include/swift/Runtime/RuntimeFunctions.def:2128-2133` |

### 9.3 ObjC Bridging Runtime

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_instantiateObjCClass` | `(metadata)` | Instantiate ObjC class | `include/swift/Runtime/RuntimeFunctions.def:1978-1984` |
| `swift_getInitializedObjCClass` | `(class) → ptr` | Get initialized ObjC class | `include/swift/Runtime/RuntimeFunctions.def:2230-2236` |
| `swift_objc_swift3ImplicitObjCEntrypoint` | `(self, selector, filename, line, col, col, message)` | Swift 3 implicit ObjC entrypoint | `include/swift/Runtime/RuntimeFunctions.def:2239-2245` |

---

## 10. Calling Conventions

### 10.1 Swift Calling Convention (`swiftcc`)

Swift uses a custom calling convention (`llvm::CallingConv::Swift`) for Swift-to-Swift calls.

**Key characteristics:**
- `swiftself` parameter attribute for the `self` parameter
- `swifterror` parameter attribute for error return
- Indirect return via `sret` attribute when needed
- Context parameter for thick function pointers

**Source**: `lib/IRGen/IRGenModule.cpp:556` — `SwiftCC = llvm::CallingConv::Swift`, `lib/IRGen/GenCall.cpp:374` — calling convention selection

### 10.2 Parameter Attributes

| Attribute | Description | Source Evidence |
|-----------|-------------|-----------------|
| `swiftself` | Self parameter in method calls | `lib/IRGen/GenCall.cpp:528-531` |
| `swifterror` | Error return parameter | `lib/IRGen/GenCall.cpp:5461-5472` |
| `sret` | Indirect return pointer | `lib/IRGen/GenCall.cpp:709, 755` |
| `swiftasync` | Async context parameter | `lib/IRGen/GenCall.cpp:3541` |

### 10.3 Calling Convention Variants

| Convention | Usage | Source Evidence |
|------------|-------|-----------------|
| `C_CC` | C calling convention (default for runtime) | `include/swift/Runtime/RuntimeFunctions.def:69` |
| `SwiftCC` | Swift calling convention | `include/swift/Runtime/RuntimeFunctions.def:52` |
| `SwiftDirectRR_CC` | Swift direct reference counting | `include/swift/Runtime/RuntimeFunctions.def:232` |
| `SwiftAsyncCC` | Swift async calling convention | `include/swift/Runtime/RuntimeFunctions.def:2144` |

---

## 11. Concurrency

### 11.1 Task Management

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_task_create` | `(flags, options, resultType, entry, context) → (task, context)` | Create async task | `include/swift/Runtime/RuntimeFunctions.def:2383-2394` |
| `swift_task_switch` | `(resumeContext, resumeFunction, newExecutor)` | Switch task execution | `include/swift/Runtime/RuntimeFunctions.def:2399-2406` |
| `swift_task_cancel` | `(task)` | Cancel task | `include/swift/Runtime/RuntimeFunctions.def:2370-2376` |
| `swift_task_getCurrent` | `() → task` | Get current task | `include/swift/Runtime/RuntimeFunctions.def:2329-2336` |
| `swift_task_alloc` | `(size) → ptr` | Allocate task-local memory | `include/swift/Runtime/RuntimeFunctions.def:2339-2346` |
| `swift_task_dealloc` | `(ptr)` | Deallocate task-local memory | `include/swift/Runtime/RuntimeFunctions.def:2349-2356` |
| `swift_task_getCurrentExecutor` | `() → executor` | Get current executor | `include/swift/Runtime/RuntimeFunctions.def:2487-2494` |
| `swift_task_getMainExecutor` | `() → executor` | Get main executor | `include/swift/Runtime/RuntimeFunctions.def:2497-2504` |

### 11.2 Actor Operations

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_defaultActor_initialize` | `(actor)` | Initialize default actor | `include/swift/Runtime/RuntimeFunctions.def:2507-2514` |
| `swift_defaultActor_destroy` | `(actor)` | Destroy default actor | `include/swift/Runtime/RuntimeFunctions.def:2517-2524` |
| `swift_defaultActor_deallocate` | `(actor)` | Deallocate default actor | `include/swift/Runtime/RuntimeFunctions.def:2527-2534` |

### 11.3 Continuations

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_continuation_init` | `(context, flags) → task` | Initialize continuation | `include/swift/Runtime/RuntimeFunctions.def:2436-2443` |
| `swift_continuation_await` | `(context)` | Await continuation | `include/swift/Runtime/RuntimeFunctions.def:2446-2453` |
| `swift_continuation_resume` | `(task)` | Resume continuation | `include/swift/Runtime/RuntimeFunctions.def:2456-2463` |
| `swift_continuation_throwingResume` | `(task)` | Resume throwing continuation | `include/swift/Runtime/RuntimeFunctions.def:2466-2473` |
| `swift_continuation_throwingResumeWithError` | `(task, error)` | Resume with error | `include/swift/Runtime/RuntimeFunctions.def:2477-2484` |

### 11.4 Task Groups

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_taskGroup_initialize` | `(group, type)` | Initialize task group | `include/swift/Runtime/RuntimeFunctions.def:2633-2640` |
| `swift_taskGroup_destroy` | `(group)` | Destroy task group | `include/swift/Runtime/RuntimeFunctions.def:2670-2677` |

---

## 12. Exclusivity Checking

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_beginAccess` | `(pointer, scratch, flags, pc)` | Begin memory access | `include/swift/Runtime/RuntimeFunctions.def:1947-1952` |
| `swift_endAccess` | `(scratch)` | End memory access | `include/swift/Runtime/RuntimeFunctions.def:1955-1960` |

---

## 13. Standard Library Registration

| IR Symbol | Args | Description | Source Evidence |
|-----------|------|-------------|-----------------|
| `swift_once` | `(predicate, function, context)` | Dispatch once (lazy initialization) | `include/swift/Runtime/RuntimeFunctions.def:1912-1917` |
| `swift_registerProtocols` | `(begin, end)` | Register protocols | `include/swift/Runtime/RuntimeFunctions.def:1921-1927` |
| `swift_registerProtocolConformances` | `(begin, end)` | Register protocol conformances | `include/swift/Runtime/RuntimeFunctions.def:1931-1937` |
| `swift_registerTypeMetadataRecords` | `(begin, end)` | Register type metadata records | `include/swift/Runtime/RuntimeFunctions.def:1938-1944` |
| `swift_lookUpClassMethod` | `(metadata, description, method) → ptr` | Look up class method | `include/swift/Runtime/RuntimeFunctions.def:1490-1496` |

---

## 14. Key Takeaways for Static Analysis

### What's User Code (Analyze These)

- **Mangled symbols**: Any symbol starting with `$s`, `_$s`, `$S`, `_$S`, `_T0`, `$e`, or `_$e` is a Swift-mangled user symbol. Demangle to recover module, type, and function names.
- **Unmangled C/ObjC symbols**: Functions imported via `@objc`, `@_cdecl`, or `@convention(c)` appear with their original C names.
- **Protocol witnesses**: User-defined protocol implementations appear in witness tables.

### What's Compiler Runtime (Filter/Skip These)

- **ARC operations** (~50+ functions): `swift_retain*`, `swift_release*`, `swift_allocObject*`, `swift_deallocObject*`, `swift_bridgeObjectRetain*`, `swift_errorRetain*`, `swift_weak*`, `swift_unowned*`, `swift_unknownObject*`
- **Metadata operations** (~40+ functions): `swift_get*Metadata*`, `swift_init*Metadata*`, `swift_checkMetadataState`, `swift_allocateGeneric*`
- **Casting operations** (~20+ functions): `swift_dynamicCast*`, `swift_conformsToProtocol*`
- **Witness table operations**: `swift_getWitnessTable*`, `swift_getAssociatedTypeWitness*`, `swift_getAssociatedConformanceWitness*`
- **Value witness operations**: `swift_cvw_*`
- **Enum tag operations**: `swift_getEnumTag*`, `swift_storeEnumTag*`
- **Concurrency operations**: `swift_task*`, `swift_defaultActor*`, `swift_continuation*`, `swift_taskGroup*`, `swift_asyncLet*`
- **Exclusivity checking**: `swift_beginAccess`, `swift_endAccess`
- **Error lifecycle**: `swift_allocError`, `swift_deallocError`, `swift_willThrow`, `swift_errorRetain`, `swift_errorRelease`
- **Registration**: `swift_once`, `swift_register*`
- **C runtime**: `malloc`, `free`, `memset_s`
- **Blocks runtime**: `_Block_copy`, `_Block_release`
- **LLVM intrinsics**: `@llvm.*`

### What's FFI Boundary (Classify Separately)

- **Objective-C runtime**: `objc_msgSend*`, `objc_allocWithZone`, `objc_getClass*`, `object_getClass`, `sel_registerName`, `class_*`, `protocol_*`
- **Bridged types**: `swift_bridgeObjectRetain*` / `swift_bridgeObjectRelease*` indicate Swift-ObjC bridging
- **Unknown object operations**: `swift_unknownObjectRetain*` / `swift_unknownObjectRelease*` indicate existential or ObjC-typed references
- **Block operations**: `_Block_copy`, `_Block_release` indicate ObjC block interop
- **`@convention(c)` functions**: Functions with C calling convention
- **`@convention(block)` functions**: ObjC block callbacks

### ARC Safety Analysis Points

1. **Retain/release balance**: Every `swift_retain` should have a matching `swift_release` on all paths
2. **Retain cycles**: Detect cycles in strong reference graphs (especially closures capturing `self`)
3. **Use-after-release**: Detect access to objects after `swift_release` when refcount reaches zero
4. **Weak reference safety**: `swift_weakLoadStrong` can return null; code must handle nil case
5. **Unowned reference safety**: Accessing unowned references after deallocation is undefined behavior
6. **Bridge object lifecycle**: Bridge objects have dual refcounting (Swift + ObjC)
7. **Error object lifecycle**: Errors are reference-counted and must be balanced

### Metadata Safety Analysis Points

1. **Metadata initialization order**: Metadata must be fully initialized before use
2. **Generic metadata instantiation**: `swift_getGenericMetadata` may trigger lazy initialization
3. **Protocol conformance validity**: `swift_conformsToProtocol` returns null if no conformance
4. **Dynamic cast safety**: `swift_dynamicCastClass` returns null on failure; unconditional variants trap
