# CPython C 扩展与运行时模式：静态分析规范 (OmniScope)

**来源**: `/Users/scc/code/researcher/cpython/` (主分支, CPython 3.15-dev)
**日期**: 2026-05-22
**用途**: 区分 CPython 运行时内部实现、C 扩展 FFI 边界和用户定义代码，供静态分析工具 (如 OmniScope) 使用

---

## 1. PyObject 布局与引用计数

### 1.1 核心对象结构

| 结构 | 字段 | 源码证据 |
|------|------|----------|
| `struct _object` (PyObject) | `ob_refcnt`, `ob_type` | `Include/object.h:127-149` |
| `struct _object` (Py_GIL_DISABLED) | `ob_tid`, `ob_flags`, `ob_mutex`, `ob_gc_bits`, `ob_ref_local`, `ob_ref_shared`, `ob_type` | `Include/object.h:156-167` |
| `struct PyVarObject` | `ob_base` (PyObject), `ob_size` | `Include/object.h:174-177` |
| `PyHeapTypeObject` | `ht_type` (PyTypeObject), `as_async`, `as_number`, `as_mapping`, `as_sequence`, `as_buffer`, `ht_name`, `ht_slots`, `ht_qualname`, `ht_cached_keys`, `ht_module`, `_ht_tpname`, `ht_token`, `_spec_cache` | `Include/cpython/object.h:273-296` |

### 1.2 引用计数宏

| 宏/函数 | 行为 | 源码证据 |
|---------|------|----------|
| `Py_REFCNT(ob)` | 返回当前引用计数；`Py_GIL_DISABLED` 下使用原子加载 | `Include/refcount.h:105-122` |
| `Py_INCREF(op)` | 增加引用计数；不朽对象为无操作 | `Include/refcount.h:255-311` |
| `Py_DECREF(op)` | 减少引用计数；引用计数降为 0 时调用 `_Py_Dealloc(op)` | `Include/refcount.h:417-431` |
| `Py_XINCREF(op)` | NULL 安全的 Py_INCREF | `Include/refcount.h:507-515` |
| `Py_XDECREF(op)` | NULL 安全的 Py_DECREF | `Include/refcount.h:517-525` |
| `Py_NewRef(obj)` | 增加引用计数并返回对象（新的拥有引用） | `Include/refcount.h:529, 534-538` |
| `Py_XNewRef(obj)` | NULL 安全的 Py_NewRef | `Include/refcount.h:532, 540-544` |
| `Py_CLEAR(op)` | 在 decref 前将 `op` 设为 NULL（防止重入 bug） | `Include/refcount.h:483-503` |
| `Py_SET_REFCNT(ob, refcnt)` | 直接设置引用计数（不朽对象为无操作） | `Include/refcount.h:154-202` |

### 1.3 不朽对象 (Python 3.12+)

| 模式 | 值/检查方式 | 源码证据 |
|------|-------------|----------|
| `_Py_IMMORTAL_INITIAL_REFCNT` (64位) | `3ULL << 30` | `Include/refcount.h:47` |
| `_Py_IMMORTAL_MINIMUM_REFCNT` (64位) | `1ULL << 31` | `Include/refcount.h:48` |
| `_Py_IMMORTAL_REFCNT_LOCAL` (Py_GIL_DISABLED) | `UINT32_MAX` | `Include/refcount.h:74` |
| `_Py_IsImmortal(op)` (64位) | `(_Py_CAST(int32_t, op->ob_refcnt) < 0)` | `Include/refcount.h:132` |
| `_Py_IsStaticImmortal(op)` | 检查 `ob_flags & _Py_STATICALLY_ALLOCATED_FLAG` | `Include/refcount.h:140-148` |

静态分析提示：`Py_INCREF` 和 `Py_DECREF` 对不朽对象是无操作。单例对象（`Py_None`、`Py_True`、`Py_False`、`Py_NotImplemented`）和静态分配的类型对象都是不朽的。

### 1.4 自由线程构建 (Py_GIL_DISABLED) 引用计数

| 模式 | 描述 | 源码证据 |
|------|------|----------|
| `ob_ref_local` | 线程本地（快速）引用计数，32位 | `Include/object.h:164` |
| `ob_ref_shared` | 原子共享引用计数（低2位为标志位） | `Include/object.h:165` |
| `_Py_REF_SHARED_SHIFT` | 2（低2位为标志） | `Include/refcount.h:81` |
| `_Py_REF_MAYBE_WEAKREF` | 标志 `0x1` | `Include/refcount.h:86` |
| `_Py_REF_QUEUED` | 标志 `0x2`（排队等待拥有线程合并） | `Include/refcount.h:87` |
| `_Py_REF_MERGED` | 标志 `0x3`（本地+共享已合并） | `Include/refcount.h:88` |
| `_Py_MergeZeroLocalRefcount(op)` | 本地引用计数降为 0 时调用；合并或释放 | `Objects/object.c:437-465` |
| `_Py_DecRefShared(o)` | 从非拥有线程减少共享引用计数 | `Objects/object.c:431-434` |

### 1.5 栈引用 (`_PyStackRef`)

| 模式 | 描述 | 源码证据 |
|------|------|----------|
| `_PyStackRef` | 联合体：`bits` (uintptr_t) 或 `index` (uint64_t, 调试模式) | `Include/internal/pycore_structs.h:66-72` |
| `PyStackRef_NULL` | 空栈引用常量 | `Include/internal/pycore_stackref.h:70` |
| `PyStackRef_ERROR` | 错误栈引用常量 | `Include/internal/pycore_stackref.h:71` |
| `Py_INT_TAG` | 标记值 `3`，用于标记整数 | `Include/internal/pycore_stackref.h:53` |
| `Py_TAG_REFCNT` | 标记 `1`，表示引用计数引用 | `Include/internal/pycore_stackref.h:55` |
| `Py_TAG_INVALID` | 标记 `2`，用于调试失效 | `Include/internal/pycore_stackref.h:54` |

---

## 2. 类型系统 / 对象协议

### 2.1 PyTypeObject 结构

`PyTypeObject` 中的关键槽位 (`Include/cpython/object.h:148-249`)：

| 槽位 | 类型 | 用途 | 生命周期角色 |
|------|------|------|-------------|
| `tp_name` | `const char *` | 类型名称（格式：`<module>.<name>`） | 标识 |
| `tp_basicsize` | `Py_ssize_t` | 基础分配大小 | 分配 |
| `tp_itemsize` | `Py_ssize_t` | 可变长度对象的元素大小 | 分配 |
| `tp_dealloc` | `destructor` | 引用计数降为 0 时调用 | 释放 |
| `tp_alloc` | `allocfunc` | 内存分配器 | 分配 |
| `tp_new` | `newfunc` | 构造函数 (`__new__`) | 创建 |
| `tp_init` | `initproc` | 初始化函数 (`__init__`) | 初始化 |
| `tp_free` | `freefunc` | 底层内存释放 | 释放 |
| `tp_traverse` | `traverseproc` | GC 循环检测遍历 | GC |
| `tp_clear` | `inquiry` | 打破引用循环 | GC |
| `tp_finalize` | `destructor` | 终结器 (PEP 442) | 终结 |
| `tp_del` | `destructor` | 旧式终结器 | 终结 |
| `tp_flags` | `unsigned long` | 特性标志 | 类型元数据 |
| `tp_methods` | `PyMethodDef *` | 方法表 | 方法绑定 |
| `tp_members` | `PyMemberDef *` | 成员表 | 属性访问 |
| `tp_getset` | `PyGetSetDef *` | 描述符表 | 属性访问 |
| `tp_base` | `PyTypeObject *` | 基类型（堆类型强引用，静态类型借用引用） | 继承 |
| `tp_dict` | `PyObject *` | 类型字典 | 属性访问 |
| `tp_vectorcall` | `vectorcallfunc` | 快速调用协议 | 调用 |
| `tp_is_gc` | `inquiry` | 自定义 GC 检查 | GC |

### 2.2 类型标志 (Py_TPFLAGS_*)

| 标志 | 值 | 含义 | 源码证据 |
|------|-----|------|----------|
| `Py_TPFLAGS_HAVE_GC` | `1UL << 14` | 对象支持垃圾回收 | `Include/object.h:524` |
| `Py_TPFLAGS_HEAPTYPE` | `1UL << 9` | 动态分配的类型 | `Include/object.h:503` |
| `Py_TPFLAGS_BASETYPE` | `1UL << 10` | 允许子类化 | `Include/object.h:506` |
| `Py_TPFLAGS_IMMUTABLETYPE` | `1UL << 8` | 类型属性不可设置/删除 | `Include/object.h:500` |
| `Py_TPFLAGS_DISALLOW_INSTANTIATION` | `1UL << 7` | 不能创建实例 | `Include/object.h:497` |
| `Py_TPFLAGS_HAVE_VECTORCALL` | `1UL << 11` | 实现 vectorcall 协议 | `Include/object.h:510` |
| `Py_TPFLAGS_MANAGED_WEAKREF` | `1UL << 3` | VM 管理的弱引用指针 | `Include/object.h:477` |
| `Py_TPFLAGS_MANAGED_DICT` | `1UL << 4` | VM 管理的字典指针 | `Include/object.h:482` |
| `Py_TPFLAGS_INLINE_VALUES` | `1UL << 2` | 值内联存储在对象之后 | `Include/object.h:472` |
| `Py_TPFLAGS_READY` | `1UL << 12` | 类型已完全初始化 | `Include/object.h:518` |
| `Py_TPFLAGS_IS_ABSTRACT` | `1UL << 20` | 抽象类型，不能实例化 | `Include/object.h:540` |
| `Py_TPFLAGS_METHOD_DESCRIPTOR` | `1UL << 17` | 行为类似未绑定方法 | `Include/object.h:534` |
| `Py_TPFLAGS_ITEMS_AT_END` | `1UL << 23` | 可变元素在实例末尾 | `Include/object.h:548` |
| `_Py_TPFLAGS_STATIC_BUILTIN` | `1UL << 1` | 通过 `_PyStaticType_InitBuiltin()` 初始化 | `Include/object.h:467` |
| `Py_TPFLAGS_SEQUENCE` | `1UL << 5` | 模式匹配中视为序列 | `Include/object.h:490` |
| `Py_TPFLAGS_MAPPING` | `1UL << 6` | 模式匹配中视为映射 | `Include/object.h:492` |

快速子类标志 (`Include/object.h:551-558`)：
`Py_TPFLAGS_LONG_SUBCLASS` (24), `Py_TPFLAGS_LIST_SUBCLASS` (25), `Py_TPFLAGS_TUPLE_SUBCLASS` (26), `Py_TPFLAGS_BYTES_SUBCLASS` (27), `Py_TPFLAGS_UNICODE_SUBCLASS` (28), `Py_TPFLAGS_DICT_SUBCLASS` (29), `Py_TPFLAGS_BASE_EXC_SUBCLASS` (30), `Py_TPFLAGS_TYPE_SUBCLASS` (31)。

### 2.3 类型槽位协议

| 协议 | 结构 | 槽位 | 源码证据 |
|------|------|------|----------|
| 数字 | `PyNumberMethods` | `nb_add`, `nb_subtract`, `nb_multiply`, `nb_remainder`, `nb_divmod`, `nb_power`, `nb_negative`, `nb_positive`, `nb_absolute`, `nb_bool`, `nb_invert`, `nb_lshift`, `nb_rshift`, `nb_and`, `nb_xor`, `nb_or`, `nb_int`, `nb_float`, `nb_inplace_*`, `nb_floor_divide`, `nb_true_divide`, `nb_index`, `nb_matrix_multiply` | `Include/cpython/object.h:61-106` |
| 序列 | `PySequenceMethods` | `sq_length`, `sq_concat`, `sq_repeat`, `sq_item`, `sq_ass_item`, `sq_contains`, `sq_inplace_concat`, `sq_inplace_repeat` | `Include/cpython/object.h:108-120` |
| 映射 | `PyMappingMethods` | `mp_length`, `mp_subscript`, `mp_ass_subscript` | `Include/cpython/object.h:122-126` |
| 异步 | `PyAsyncMethods` | `am_await`, `am_aiter`, `am_anext`, `am_send` | `Include/cpython/object.h:130-135` |
| 缓冲区 | `PyBufferProcs` | `bf_getbuffer`, `bf_releasebuffer` | `Include/cpython/object.h:137-140` |

---

## 3. 内存分配

### 3.1 分配 API 层级

| API | 函数 | 用途 | 源码证据 |
|-----|------|------|----------|
| 原始 | `PyMem_RawMalloc/Calloc/Realloc/Free` | 无需 GIL，包装平台 malloc | `Include/pymem.h:95-98` |
| PyMem | `PyMem_Malloc/Calloc/Realloc/Free` | 需要 GIL，通用 | `Include/pymem.h:48-51` |
| PyObject | `PyObject_Malloc/Calloc/Realloc/Free` | 需要 GIL，对象分配器（针对小对象优化） | `Include/objimpl.h:93-98` |
| 类型化 | `PyObject_New(type, typeobj)` | 分配+初始化类型化对象 | `Include/objimpl.h:130` |
| 类型化变长 | `PyObject_NewVar(type, typeobj, n)` | 分配+初始化可变大小类型化对象 | `Include/objimpl.h:136-137` |
| 初始化 | `PyObject_Init(op, typeobj)` | 用类型信息初始化已有分配 | `Include/objimpl.h:117` |
| 初始化变长 | `PyObject_InitVar(op, typeobj, size)` | 初始化可变大小对象 | `Include/objimpl.h:118-119` |
| 类型化内存 | `PyMem_New(type, n)` | 带溢出检查的类型安全 PyMem 分配 | `Include/pymem.h:63-65` |

### 3.2 GC 跟踪分配

| API | 用途 | 源码证据 |
|-----|------|----------|
| `_PyObject_GC_New(typeobj)` | 分配 GC 跟踪对象 | `Include/objimpl.h:165` |
| `_PyObject_GC_NewVar(typeobj, n)` | 分配可变大小 GC 跟踪对象 | `Include/objimpl.h:166` |
| `PyObject_GC_New(type, typeobj)` | 包装 `_PyObject_GC_New` 的宏 | `Include/objimpl.h:180-181` |
| `PyObject_GC_NewVar(type, typeobj, n)` | 包装 `_PyObject_GC_NewVar` 的宏 | `Include/objimpl.h:182-183` |
| `PyObject_GC_Track(op)` | 通知 GC 跟踪此对象 | `Include/objimpl.h:171` |
| `PyObject_GC_UnTrack(op)` | 停止 GC 跟踪 | `Include/objimpl.h:176` |
| `PyObject_GC_Del(op)` | 释放 GC 跟踪对象 | `Include/objimpl.h:178` |
| `PyObject_GC_IsTracked(op)` | 检查对象是否被跟踪 | `Include/objimpl.h:185` |
| `PyObject_GC_IsFinalized(op)` | 检查对象是否已终结 | `Include/objimpl.h:186` |

### 3.3 GC 头部布局

| 模式 | 描述 | 源码证据 |
|------|------|----------|
| `PyGC_Head` | 在 GC 跟踪对象之前预置 | `Include/internal/pycore_gc.h:17-26` |
| `_Py_AS_GC(op)` | `(char*)op - sizeof(PyGC_Head)` | `Include/internal/pycore_gc.h:17-20` |
| `_Py_FROM_GC(gc)` | `(char*)gc + sizeof(PyGC_Head)` | `Include/internal/pycore_gc.h:23-26` |
| `_gc_next` | 0 = 未跟踪；非零 = GC 列表中下一个的指针 | `Python/gc.c:184-191` |
| `_gc_prev` | 用于双向链表；收集期间也保存 `gc_refs` | `Python/gc.c:156-178` |

### 3.4 空闲列表

常见类型的对象使用空闲列表进行快速分配 (`Objects/object.c:926-958`)：
- 浮点数、复数、元组、列表、列表迭代器、元组迭代器、字典、字典键、切片、范围、范围迭代器、上下文、异步生成器、Unicode 写入器、字节写入器、整数、pycfunctionobject、pycmethodobject、pymethodobjects、对象栈块。

---

## 4. 垃圾回收器

### 4.1 分代 GC 结构

| 组件 | 描述 | 源码证据 |
|------|------|----------|
| `NUM_GENERATIONS` | 3 代 | `Python/gc.c:101` (GEN_HEAD 宏) |
| `generation0` | 最年轻一代（最频繁收集） | `Python/gc.c:125` |
| `permanent_generation` | 永不收集的对象 | `Python/gc.c:126` |
| `gc_collect_main()` | 主收集函数 | `Python/gc.c:1422-1650` |

### 4.2 GC 收集算法

1. **update_refs()** (`Python/gc.c:396-436`)：将 `ob_refcnt` 复制到 `gc_prev`（用于当前代中每个对象）。跳过不朽对象（取消跟踪）。
2. **subtract_refs()** (`Python/gc.c:489-501`)：对每个对象调用 `tp_traverse`；对同代中每个被引用对象，减少其 `gc_refs`。
3. **move_unreachable()** (`Python/gc.c:578-650`)：识别不可达对象（gc_refs == 0）并移至不可达列表。使用 `NEXT_MASK_UNREACHABLE` 标志。
4. **handle_weakref_callbacks()** (`Python/gc.c:807-952`)：处理指向不可达对象的弱引用，对来自外部的弱引用调用回调。
5. **finalize_garbage()** (`Python/gc.c:1045-1076`)：对有 `tp_finalize` 的对象调用终结器。
6. **handle_resurrected_objects()** (`Python/gc.c:1234-1251`)：处理被终结器复活的对象。
7. **delete_garbage()** (`Python/gc.c:1082-1119`)：对不可达对象调用 `tp_clear` 以打破循环。

### 4.3 GC 访问协议

| 模式 | 用法 | 源码证据 |
|------|------|----------|
| `Py_VISIT(op)` | 在 `tp_traverse` 中调用 `visit(op, arg)` | `Include/objimpl.h:193-200` |
| `_Py_VISIT_STACKREF(ref)` | 访问栈引用（处理延迟引用计数） | `Include/internal/pycore_stackref.h:841` |
| `_PyGC_VisitStackRef(ref, visit, arg)` | GC 遍历期间访问栈引用 | `Python/gc.c:458-470` |
| `_PyGC_VisitFrameStack(frame, visit, arg)` | 访问帧中的所有栈引用 | `Python/gc.c:472-483` |
| `visit_decref(op, parent)` | GC 遍历回调，减少 gc_refs | `Python/gc.c:440-456` |
| `visit_reachable(op, arg)` | 标记可达对象的 GC 回调 | `Python/gc.c:503-564` |
| `visit_move(op, arg)` | 在列表间移动对象的 GC 回调 | `Python/gc.c:736-749` |

### 4.4 GC 位 (Py_GIL_DISABLED)

| 位 | 值 | 含义 | 源码证据 |
|----|----|----|----------|
| `_PyGC_BITS_TRACKED` | `1<<0` | 被 GC 跟踪 | `Include/internal/pycore_gc.h:39` |
| `_PyGC_BITS_FINALIZED` | `1<<1` | tp_finalize 已调用 | `Include/internal/pycore_gc.h:40` |
| `_PyGC_BITS_UNREACHABLE` | `1<<2` | 不可达 | `Include/internal/pycore_gc.h:41` |
| `_PyGC_BITS_FROZEN` | `1<<3` | 冻结（不收集） | `Include/internal/pycore_gc.h:42` |
| `_PyGC_BITS_SHARED` | `1<<4` | 线程间共享 | `Include/internal/pycore_gc.h:43` |
| `_PyGC_BITS_ALIVE` | `1<<5` | 从已知根可达 | `Include/internal/pycore_gc.h:44` |
| `_PyGC_BITS_DEFERRED` | `1<<6` | 使用延迟引用计数 | `Include/internal/pycore_gc.h:45` |

### 4.5 收集期间的 GC 状态标志

| 标志 | 位置 | 用途 | 源码证据 |
|------|------|------|----------|
| `PREV_MASK_COLLECTING` | `_gc_prev` 最低位 | 标记当前收集代中的对象 | `Python/gc.c:39` |
| `NEXT_MASK_UNREACHABLE` | `_gc_next` 最低位 | 标记不可达对象 | `Python/gc.c:50` |

---

## 5. C 扩展模块模式

### 5.1 模块定义

| 模式 | 结构/函数 | 源码证据 |
|------|-----------|----------|
| `PyModuleDef` | `m_base`, `m_name`, `m_doc`, `m_size`, `m_methods`, `m_slots`, `m_traverse`, `m_clear`, `m_free` | `Include/moduleobject.h:108-118` |
| `PyModuleDef_Base` | `m_init`, `m_index`, `m_copy` | `Include/moduleobject.h:40-59` |
| `PyModuleDef_HEAD_INIT` | `PyModuleDef_Base` 的静态初始化器 | `Include/moduleobject.h:61-66` |
| `PyModule_Create(def)` | 创建单阶段模块 | `Include/modsupport.h:65-66` |
| `PyModule_Create2(def, apiver)` | 带 API 版本检查创建模块 | `Include/modsupport.h:59` |
| `PyModule_FromDefAndSpec2(def, spec, ver)` | 创建多阶段模块 | `Include/modsupport.h:71` |
| `PyModule_ExecDef(module, def)` | 执行模块定义（多阶段） | `Include/modsupport.h:54` |

### 5.2 模块初始化函数签名

| 模式 | 签名 | 源码证据 |
|------|------|----------|
| `PyMODINIT_FUNC` | 模块初始化函数的返回类型 | `Include/exports.h` (典型) |
| `PyInit_<modname>` | 模块入口点命名约定 | Python 导入系统约定 |
| 单阶段初始化 | `PyObject* PyInit_modname(void)` 返回模块对象 | 常见 C 扩展模式 |
| 多阶段初始化 | `PyObject* PyInit_modname(void)` 返回 `PyModuleDef` | `Include/moduleobject.h:71-74` |

### 5.3 方法定义

| 结构 | 字段 | 源码证据 |
|------|------|----------|
| `PyMethodDef` | `ml_name`, `ml_meth` (PyCFunction), `ml_flags`, `ml_doc` | `Include/methodobject.h:68-74` |

### 5.4 C 函数指针类型

| 类型 | 签名 | 源码证据 |
|------|------|----------|
| `PyCFunction` | `(PyObject *, PyObject *) -> PyObject *` | `Include/methodobject.h:19` |
| `PyCFunctionFast` | `(PyObject *, PyObject *const *, Py_ssize_t) -> PyObject *` | `Include/methodobject.h:20` |
| `PyCFunctionWithKeywords` | `(PyObject *, PyObject *, PyObject *) -> PyObject *` | `Include/methodobject.h:21-22` |
| `PyCFunctionFastWithKeywords` | `(PyObject *, PyObject *const *, Py_ssize_t, PyObject *) -> PyObject *` | `Include/methodobject.h:23-25` |
| `PyCMethod` | `(PyObject *, PyTypeObject *, PyObject *const *, Py_ssize_t, PyObject *) -> PyObject *` | `Include/methodobject.h:26-27` |

### 5.5 方法标志 (METH_*)

| 标志 | 值 | 含义 | 源码证据 |
|------|-----|------|----------|
| `METH_VARARGS` | `0x0001` | 接受 `(self, args)` 元组 | `Include/methodobject.h:95` |
| `METH_KEYWORDS` | `0x0002` | 接受 `(self, args, kwargs)` 字典 | `Include/methodobject.h:96` |
| `METH_NOARGS` | `0x0004` | 接受 `(self, NULL)` | `Include/methodobject.h:98` |
| `METH_O` | `0x0008` | 接受 `(self, single_arg)` | `Include/methodobject.h:99` |
| `METH_CLASS` | `0x0010` | 类方法 | `Include/methodobject.h:104` |
| `METH_STATIC` | `0x0020` | 静态方法 | `Include/methodobject.h:105` |
| `METH_COEXIST` | `0x0040` | 与槽方法共存 | `Include/methodobject.h:112` |
| `METH_FASTCALL` | `0x0080` | 快速调用约定 | `Include/methodobject.h:115` |
| `METH_METHOD` | `0x0200` | 带类的绑定方法 | `Include/methodobject.h:133` |

### 5.6 参数解析

| 函数 | 签名 | 源码证据 |
|------|------|----------|
| `PyArg_Parse(args, format, ...)` | 解析位置参数 | `Include/modsupport.h:9` |
| `PyArg_ParseTuple(args, format, ...)` | 解析元组参数 | `Include/modsupport.h:10` |
| `PyArg_ParseTupleAndKeywords(args, kw, format, keywords, ...)` | 解析参数 + 关键字参数 | `Include/modsupport.h:11-12` |
| `Py_BuildValue(format, ...)` | 从 C 值构建 Python 对象 | `Include/modsupport.h:19` |

---

## 6. 缓冲区协议

### 6.1 Py_buffer 结构

| 字段 | 类型 | 描述 | 源码证据 |
|------|------|------|----------|
| `buf` | `void *` | 缓冲区数据指针 | `Include/pybuffer.h:21` |
| `obj` | `PyObject *` | 拥有引用 | `Include/pybuffer.h:22` |
| `len` | `Py_ssize_t` | 缓冲区总字节数 | `Include/pybuffer.h:23` |
| `itemsize` | `Py_ssize_t` | 元素字节大小 | `Include/pybuffer.h:24` |
| `readonly` | `int` | 1 为只读，0 为可写 | `Include/pybuffer.h:26` |
| `ndim` | `int` | 维度数 | `Include/pybuffer.h:27` |
| `format` | `char *` | 格式字符串（struct 模块风格） | `Include/pybuffer.h:28` |
| `shape` | `Py_ssize_t *` | 形状数组 | `Include/pybuffer.h:29` |
| `strides` | `Py_ssize_t *` | 步长数组 | `Include/pybuffer.h:30` |
| `suboffsets` | `Py_ssize_t *` | 子偏移数组（用于指针） | `Include/pybuffer.h:31` |
| `internal` | `void *` | 内部使用 | `Include/pybuffer.h:32` |

### 6.2 缓冲区 API 函数

| 函数 | 用途 | 源码证据 |
|------|------|----------|
| `PyObject_CheckBuffer(obj)` | 检查对象是否支持缓冲区协议 | `Include/pybuffer.h:39` |
| `PyObject_GetBuffer(obj, view, flags)` | 获取缓冲区（增加 `obj` 的引用计数） | `Include/pybuffer.h:46-47` |
| `PyBuffer_Release(view)` | 释放缓冲区（减少 `view->obj` 的引用计数） | 标准 API |
| `PyBuffer_IsContiguous(view, order)` | 检查缓冲区是否连续 | `Include/pybuffer.h:80` |
| `PyBuffer_FillInfo(view, o, buf, len, readonly, flags)` | 为简单连续缓冲区填充缓冲区信息 | `Include/pybuffer.h:97-99` |

### 6.3 缓冲区请求标志

| 标志 | 用途 |
|------|------|
| `PyBUF_SIMPLE` | 简单连续缓冲区 |
| `PyBUF_WRITABLE` | 可写缓冲区 |
| `PyBUF_FORMAT` | 请求格式字符串 |
| `PyBUF_ND` | 请求形状数组 |
| `PyBUF_STRIDES` | 请求步长数组 |
| `PyBUF_C_CONTIGUOUS` | C 连续 |
| `PyBUF_F_CONTIGUOUS` | Fortran 连续 |
| `PyBUF_ANY_CONTIGUOUS` | 任意连续 |
| `PyBUF_INDIRECT` | 间接（基于指针）缓冲区 |

---

## 7. PyCapsule API

| 函数 | 用途 | 源码证据 |
|------|------|----------|
| `PyCapsule_New(pointer, name, destructor)` | 将 C void* 包装为 Python 对象 | `Include/pycapsule.h:28-31` |
| `PyCapsule_GetPointer(capsule, name)` | 提取指针（验证名称） | `Include/pycapsule.h:33` |
| `PyCapsule_GetDestructor(capsule)` | 获取析构函数 | `Include/pycapsule.h:35` |
| `PyCapsule_GetName(capsule)` | 获取 capsule 名称 | `Include/pycapsule.h:37` |
| `PyCapsule_GetContext(capsule)` | 获取上下文指针 | `Include/pycapsule.h:39` |
| `PyCapsule_IsValid(capsule, name)` | 验证 capsule | `Include/pycapsule.h:41` |
| `PyCapsule_Import(name, no_block)` | 从模块导入 capsule | `Include/pycapsule.h:51-53` |

---

## 8. CPython 内部 / 运行时结构

### 8.1 运行时状态

| 结构 | 用途 | 源码证据 |
|------|------|----------|
| `_PyRuntimeState` | 全局运行时状态（进程级） | `Include/internal/pycore_runtime.h:19` |
| `_PyRuntime` | 全局唯一实例 | `Include/internal/pycore_runtime.h:19` |
| `_pymem_allocators` | 内存分配器状态（raw, mem, obj + 调试变体） | `Include/internal/pycore_runtime_structs.h:21-36` |

### 8.2 解释器帧

| 结构 | 关键字段 | 源码证据 |
|------|----------|----------|
| `_PyInterpreterFrame` | `f_executable` (_PyStackRef), `previous`, `f_funcobj` (_PyStackRef), `f_globals`, `f_builtins`, `f_locals`, `frame_obj`, `instr_ptr`, `stackpointer`, `tlbc_index` (Py_GIL_DISABLED), `return_offset`, `owner`, `localsplus[1]` | `Include/internal/pycore_interpframe_structs.h:29-53` |
| `PyFrameObject` | `f_back`, `f_frame`, `f_trace`, `f_lineno`, `f_trace_lines`, `f_trace_opcodes`, `f_extra_locals`, `f_locals_cache`, `f_overwritten_fast_locals`, `_f_frame_data[1]` | `Include/internal/pycore_frame.h:18-39` |

帧所有者 (`Include/internal/pycore_interpframe_structs.h:22-27`)：
- `FRAME_OWNED_BY_THREAD` (0)
- `FRAME_OWNED_BY_GENERATOR` (1)
- `FRAME_OWNED_BY_FRAME_OBJECT` (2)
- `FRAME_OWNED_BY_INTERPRETER` (3)

### 8.3 字节码单元

| 结构 | 布局 | 源码证据 |
|------|------|----------|
| `_Py_CODEUNIT` | 联合体：`cache` (uint16_t), `op.code` (uint8_t) + `op.arg` (uint8_t), `counter` (_Py_BackoffCounter) | `Include/internal/pycore_structs.h:25-32` |
| `_Py_OPCODE(word)` | 提取操作码：`word.op.code` | `Include/internal/pycore_code.h:21` |
| `_Py_OPARG(word)` | 提取操作参数：`word.op.arg` | `Include/internal/pycore_code.h:22` |

### 8.4 字符串内部实现 (PEP 393)

| 结构 | 字段 | 源码证据 |
|------|------|----------|
| `PyASCIIObject` | `PyObject_HEAD`, `length`, `hash`, `state` (interned:2, kind:3, compact:1, ascii:1, statically_allocated:1) | `Include/cpython/unicodeobject.h:111-161` |
| `PyCompactUnicodeObject` | `PyASCIIObject _base`, `utf8_length`, `utf8` | `Include/cpython/unicodeobject.h:166-171` |
| `PyUnicodeObject` | `PyCompactUnicodeObject _base`, `data` (联合体: any/latin1/ucs2/ucs4) | `Include/cpython/unicodeobject.h:174-182` |

字符串种类：`PyUnicode_1BYTE_KIND` (1), `PyUnicode_2BYTE_KIND` (2), `PyUnicode_4BYTE_KIND` (4) (`Include/cpython/unicodeobject.h:70-88`)。

### 8.5 标识符缓存

| 模式 | 描述 | 源码证据 |
|------|------|----------|
| `_Py_Identifier` | `{ const char* string; Py_ssize_t index; struct { uint8_t v; } mutex; }` | `Include/cpython/object.h:39-48` |
| `_Py_IDENTIFIER(varname)` | 声明 `static _Py_Identifier PyId_##varname` | `Include/cpython/object.h:56` |
| `_Py_static_string(varname, value)` | 声明静态字符串标识符 | `Include/cpython/object.h:55` |

---

## 9. 对象生命周期模式

### 9.1 分配-释放路径

```
PyObject_New(type, typeobj)
  -> _PyObject_New(typeobj)
    -> PyObject_Malloc(_PyObject_SIZE(tp))
    -> _PyObject_Init(op, tp)   [设置 ob_refcnt=1, ob_type=tp]

Py_DECREF(op) 当引用计数降为 0 时：
  -> _Py_Dealloc(op)            [Objects/object.c:3283-3339]
    -> type->tp_dealloc(op)     [用户定义的析构函数]
```

### 9.2 垃圾桶机制

当递归释放深度超过阈值时，对象被延迟处理：
```
_Py_Dealloc(op):
  if margin < 2 and gc_flag:
    _PyTrash_thread_deposit_object(tstate, op)  // 延迟
    return
  (*dealloc)(op)  // 正常释放
  if tstate->delete_later and margin >= 4:
    _PyTrash_thread_destroy_chain(tstate)  // 处理延迟对象
```
来源：`Objects/object.c:3289-3338`

### 9.3 对象终结 (PEP 442)

```
tp_finalize(op):
  每个对象只调用一次（由 _PyGC_FINALIZED 标志保护）
  可以复活对象（增加引用计数）
  如果复活，对象在收集后存活

tp_del(op):
  旧式终结器（PEP 442 之前）
  有 tp_del 的对象如果在循环中则不可收集
```
来源：`Python/gc.c:678-683`, `Python/gc.c:1045-1076`

---

## 10. 静态分析关键要点

### 用户 C 扩展代码（分析这些）：
- 通过 `PyMethodDef` 表注册的函数，`ml_meth` 指向用户定义的 C 函数
- `PyInit_*` 模块初始化函数
- 自定义的 `tp_dealloc`、`tp_traverse`、`tp_clear`、`tp_init`、`tp_new` 实现
- `PyCFunction` / `PyCFunctionWithKeywords` 实现
- 使用 `PyArg_ParseTuple*` / `Py_BuildValue` 的代码
- 缓冲区协议实现（`bf_getbuffer`、`bf_releasebuffer`）

### CPython 内部运行时（过滤/跳过这些）：
- `_Py_*` 前缀函数（内部 API）
- `Include/internal/` 头文件中的 `PyAPI_FUNC` 声明
- `_PyRuntimeState`、`_PyInterpreterState`、`_PyThreadState` 字段
- `_Py_CODEUNIT` / 字节码操作
- `_PyStackRef` 操作（求值循环内部）
- `_PyDealloc` 和垃圾桶机制内部
- GC 内部：`update_refs`、`subtract_refs`、`move_unreachable` 等
- `_Py_IDENTIFIER` / `_Py_static_string` 基础设施
- 空闲列表管理（`_PyObject_ClearFreeLists`）
- 运行时状态初始化（`_PyRuntimeState_Init`、`_PyGC_Init`）

### FFI 边界（分析安全性）：
- `PyObject *` 在 C 扩展和 Python 之间传递
- 引用计数所有权转移模式：
  - **拥有引用**：调用者必须 `Py_DECREF`（如 `Py_NewRef`、`PyObject_New`）
  - **借用引用**：调用者不得 `Py_DECREF`（如 `PyTuple_GetItem`、`PyDict_GetItemString`）
  - **窃取引用**：所有权已转移（如 `PyTuple_SetItem`、`PyList_SetItem`）
- `PyCapsule` 使用（不透明指针包装）
- 缓冲区协议（`PyObject_GetBuffer` / `PyBuffer_Release`）
- `tp_traverse` / `tp_clear` 实现（GC 安全性）
- `tp_dealloc` 实现（必须处理部分初始化的对象）

### 常见引用计数 bug 检测：
1. **双重 DECREF**：在同一引用上两次调用 `Py_DECREF`，中间没有 `Py_INCREF`
2. **遗漏 DECREF**：返回前未对拥有引用调用 `Py_DECREF`（内存泄漏）
3. **借用引用逃逸**：返回或存储的借用引用超出其生命周期
4. **窃取引用误用**：对已被 `PyTuple_SetItem` 窃取的引用调用 `Py_DECREF`
5. **NULL 解引用**：未检查分配/API 函数的 `NULL` 返回值
6. **DECREF 后使用**：在引用计数可能降为 0 的 `Py_DECREF` 后访问对象
7. **遗漏 GC 访问**：在 `tp_traverse` 中未访问所有包含的对象（导致遗漏循环）
8. **遗漏缓冲区释放**：`PyObject_GetBuffer` 后未调用 `PyBuffer_Release`

### 过滤 vs 分析：

| 类别 | 操作 | 理由 |
|------|------|------|
| `Py_INCREF` / `Py_DECREF` / `Py_XDECREF` | 分析 | 核心内存安全 |
| `PyObject_New` / `PyObject_GC_New` | 分析 | 分配跟踪 |
| `tp_dealloc` / `tp_traverse` / `tp_clear` | 分析 | GC 和生命周期安全 |
| `PyBuffer_*` / `PyObject_GetBuffer` | 分析 | 缓冲区安全 |
| `PyCapsule_*` | 分析 | 不透明指针安全 |
| `PyArg_ParseTuple*` | 分析 | 参数验证 |
| `_Py_Dealloc` 内部 | 过滤 | 运行时管道 |
| `_PyStackRef` 操作 | 过滤 | 求值循环内部 |
| GC 算法内部 | 运行时 GC 机制 | 过滤 |
| `_PyRuntimeState` / `_PyInterpreterState` | 过滤 | 运行时状态管理 |
| 空闲列表操作 | 过滤 | 分配器内部 |
| 不朽对象检查 | 过滤 | 优化，始终安全 |

---

## 11. 完整 _Py_Dealloc 路径

来源：`Objects/object.c:3283-3339`

```
_Py_Dealloc(PyObject *op):
    type = Py_TYPE(op)
    gc_flag = type->tp_flags & Py_TPFLAGS_HAVE_GC
    dealloc = type->tp_dealloc

    // 垃圾桶：递归深度过低时延迟处理
    if recursion_margin < 2 and gc_flag:
        _PyTrash_thread_deposit_object(op)
        return

    // 调试：保存当前异常，增加 type 引用计数
    old_exc = tstate->current_exception
    Py_XINCREF(old_exc)
    Py_INCREF(type)

    // 遗忘引用（Py_TRACE_REFS 构建）
    _Py_ForgetReference(op)

    // 跟踪销毁
    _PyReftracerTrack(op, PyRefTracer_DESTROY)

    // 调用实际析构函数
    (*dealloc)(op)

    // 调试：验证异常未改变
    assert(tstate->current_exception == old_exc)

    // 处理延迟的垃圾桶对象
    if tstate->delete_later and margin >= 4 and gc_flag:
        _PyTrash_thread_destroy_chain(tstate)
```

---

## 12. 延迟引用计数 (Py_GIL_DISABLED)

来源：`Include/internal/pycore_object.h:28`

| 模式 | 描述 |
|------|------|
| `_Py_REF_DEFERRED` | `PY_SSIZE_T_MAX / 8` — 添加到延迟对象的 `ob_ref_shared` |
| `_PyGC_BITS_DEFERRED` | GC 位标志，表示延迟引用计数 |
| `_PyObject_HasDeferredRefcount()` | 检查对象是否使用延迟引用计数 |

延迟引用计数避免了主要从单线程访问的对象（如模块全局变量）的原子操作。共享引用计数向上偏置，因此永远不会仅因非延迟 decref 而降为零。
