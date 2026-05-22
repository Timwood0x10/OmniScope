# CPython C Extension & Runtime Patterns for Static Analysis (OmniScope)

**Source**: `/Users/scc/code/researcher/cpython/` (main branch, CPython 3.15-dev)
**Date**: 2026-05-22
**Purpose**: Distinguish CPython runtime internals, C extension FFI boundaries, and user-defined code for static analysis tools (e.g., OmniScope)

---

## 1. PyObject Layout & Reference Counting

### 1.1 Core Object Structures

| Structure | Fields | Source Evidence |
|-----------|--------|-----------------|
| `struct _object` (PyObject) | `ob_refcnt`, `ob_type` | `Include/object.h:127-149` |
| `struct _object` (Py_GIL_DISABLED) | `ob_tid`, `ob_flags`, `ob_mutex`, `ob_gc_bits`, `ob_ref_local`, `ob_ref_shared`, `ob_type` | `Include/object.h:156-167` |
| `struct PyVarObject` | `ob_base` (PyObject), `ob_size` | `Include/object.h:174-177` |
| `PyHeapTypeObject` | `ht_type` (PyTypeObject), `as_async`, `as_number`, `as_mapping`, `as_sequence`, `as_buffer`, `ht_name`, `ht_slots`, `ht_qualname`, `ht_cached_keys`, `ht_module`, `_ht_tpname`, `ht_token`, `_spec_cache` | `Include/cpython/object.h:273-296` |

### 1.2 Reference Count Macros

| Macro/Function | Behavior | Source Evidence |
|----------------|----------|-----------------|
| `Py_REFCNT(ob)` | Returns current refcount; uses atomic loads for `Py_GIL_DISABLED` | `Include/refcount.h:105-122` |
| `Py_INCREF(op)` | Increments refcount; no-op for immortal objects | `Include/refcount.h:255-311` |
| `Py_DECREF(op)` | Decrements refcount; calls `_Py_Dealloc(op)` when refcount reaches 0 | `Include/refcount.h:417-431` |
| `Py_XINCREF(op)` | NULL-safe version of Py_INCREF | `Include/refcount.h:507-515` |
| `Py_XDECREF(op)` | NULL-safe version of Py_DECREF | `Include/refcount.h:517-525` |
| `Py_NewRef(obj)` | Increments refcount and returns the object (new owned reference) | `Include/refcount.h:529, 534-538` |
| `Py_XNewRef(obj)` | NULL-safe version of Py_NewRef | `Include/refcount.h:532, 540-544` |
| `Py_CLEAR(op)` | Sets `op` to NULL before decref (prevents re-entrance bugs) | `Include/refcount.h:483-503` |
| `Py_SET_REFCNT(ob, refcnt)` | Directly sets refcount (no-op for immortal objects) | `Include/refcount.h:154-202` |

### 1.3 Immortal Objects (Python 3.12+)

| Pattern | Value/Check | Source Evidence |
|---------|-------------|-----------------|
| `_Py_IMMORTAL_INITIAL_REFCNT` (64-bit) | `3ULL << 30` | `Include/refcount.h:47` |
| `_Py_IMMORTAL_MINIMUM_REFCNT` (64-bit) | `1ULL << 31` | `Include/refcount.h:48` |
| `_Py_IMMORTAL_REFCNT_LOCAL` (Py_GIL_DISABLED) | `UINT32_MAX` | `Include/refcount.h:74` |
| `_Py_IsImmortal(op)` (64-bit) | `(_Py_CAST(int32_t, op->ob_refcnt) < 0)` | `Include/refcount.h:132` |
| `_Py_IsStaticImmortal(op)` | Checks `ob_flags & _Py_STATICALLY_ALLOCATED_FLAG` | `Include/refcount.h:140-148` |

Static analysis note: `Py_INCREF` and `Py_DECREF` are no-ops for immortal objects. Singletons (`Py_None`, `Py_True`, `Py_False`, `Py_NotImplemented`) and statically allocated type objects are immortal.

### 1.4 Free-Threaded Build (Py_GIL_DISABLED) Reference Counting

| Pattern | Description | Source Evidence |
|---------|-------------|-----------------|
| `ob_ref_local` | Thread-local (fast) reference count, 32-bit | `Include/object.h:164` |
| `ob_ref_shared` | Atomic shared reference count (shifted by 2 bits for flags) | `Include/object.h:165` |
| `_Py_REF_SHARED_SHIFT` | 2 (low 2 bits are flags) | `Include/refcount.h:81` |
| `_Py_REF_MAYBE_WEAKREF` | Flag `0x1` | `Include/refcount.h:86` |
| `_Py_REF_QUEUED` | Flag `0x2` (queued for merge by owning thread) | `Include/refcount.h:87` |
| `_Py_REF_MERGED` | Flag `0x3` (local+shared merged) | `Include/refcount.h:88` |
| `_Py_MergeZeroLocalRefcount(op)` | Called when local refcount reaches 0; merges or deallocates | `Objects/object.c:437-465` |
| `_Py_DecRefShared(o)` | Decrements shared refcount from non-owning thread | `Objects/object.c:431-434` |

### 1.5 Stack References (`_PyStackRef`)

| Pattern | Description | Source Evidence |
|---------|-------------|-----------------|
| `_PyStackRef` | Union: `bits` (uintptr_t) or `index` (uint64_t, debug) | `Include/internal/pycore_structs.h:66-72` |
| `PyStackRef_NULL` | Null stackref constant | `Include/internal/pycore_stackref.h:70` |
| `PyStackRef_ERROR` | Error stackref constant | `Include/internal/pycore_stackref.h:71` |
| `Py_INT_TAG` | Tag value `3` for tagged integers | `Include/internal/pycore_stackref.h:53` |
| `Py_TAG_REFCNT` | Tag `1` indicating refcounted reference | `Include/internal/pycore_stackref.h:55` |
| `Py_TAG_INVALID` | Tag `2` for debug invalidation | `Include/internal/pycore_stackref.h:54` |

---

## 2. Type System / Object Protocol

### 2.1 PyTypeObject Structure

Key slots in `PyTypeObject` (`Include/cpython/object.h:148-249`):

| Slot | Type | Purpose | Lifecycle Role |
|------|------|---------|----------------|
| `tp_name` | `const char *` | Type name (format: `<module>.<name>`) | Identification |
| `tp_basicsize` | `Py_ssize_t` | Base allocation size | Allocation |
| `tp_itemsize` | `Py_ssize_t` | Item size for variable-length objects | Allocation |
| `tp_dealloc` | `destructor` | Called when refcount reaches 0 | Deallocation |
| `tp_alloc` | `allocfunc` | Memory allocator | Allocation |
| `tp_new` | `newfunc` | Constructor (`__new__`) | Creation |
| `tp_init` | `initproc` | Initializer (`__init__`) | Initialization |
| `tp_free` | `freefunc` | Low-level memory free | Deallocation |
| `tp_traverse` | `traverseproc` | GC cycle detection traversal | GC |
| `tp_clear` | `inquiry` | Break reference cycles | GC |
| `tp_finalize` | `destructor` | Finalizer (PEP 442) | Finalization |
| `tp_del` | `destructor` | Legacy finalizer | Finalization |
| `tp_flags` | `unsigned long` | Feature flags | Type metadata |
| `tp_methods` | `PyMethodDef *` | Method table | Method binding |
| `tp_members` | `PyMemberDef *` | Member table | Attribute access |
| `tp_getset` | `PyGetSetDef *` | Descriptor table | Attribute access |
| `tp_base` | `PyTypeObject *` | Base type (strong ref for heap, borrowed for static) | Inheritance |
| `tp_dict` | `PyObject *` | Type dictionary | Attribute access |
| `tp_vectorcall` | `vectorcallfunc` | Fast call protocol | Calling |
| `tp_is_gc` | `inquiry` | Custom GC check | GC |

### 2.2 Type Flags (Py_TPFLAGS_*)

| Flag | Value | Meaning | Source Evidence |
|------|-------|---------|-----------------|
| `Py_TPFLAGS_HAVE_GC` | `1UL << 14` | Objects support garbage collection | `Include/object.h:524` |
| `Py_TPFLAGS_HEAPTYPE` | `1UL << 9` | Dynamically allocated type | `Include/object.h:503` |
| `Py_TPFLAGS_BASETYPE` | `1UL << 10` | Allows subclassing | `Include/object.h:506` |
| `Py_TPFLAGS_IMMUTABLETYPE` | `1UL << 8` | Type attributes cannot be set/deleted | `Include/object.h:500` |
| `Py_TPFLAGS_DISALLOW_INSTANTIATION` | `1UL << 7` | Cannot create instances | `Include/object.h:497` |
| `Py_TPFLAGS_HAVE_VECTORCALL` | `1UL << 11` | Implements vectorcall protocol | `Include/object.h:510` |
| `Py_TPFLAGS_MANAGED_WEAKREF` | `1UL << 3` | VM-managed weakref pointers | `Include/object.h:477` |
| `Py_TPFLAGS_MANAGED_DICT` | `1UL << 4` | VM-managed dict pointers | `Include/object.h:482` |
| `Py_TPFLAGS_INLINE_VALUES` | `1UL << 2` | Values stored inline after object | `Include/object.h:472` |
| `Py_TPFLAGS_READY` | `1UL << 12` | Type fully initialized | `Include/object.h:518` |
| `Py_TPFLAGS_IS_ABSTRACT` | `1UL << 20` | Abstract type, cannot instantiate | `Include/object.h:540` |
| `Py_TPFLAGS_METHOD_DESCRIPTOR` | `1UL << 17` | Behaves like unbound method | `Include/object.h:534` |
| `Py_TPFLAGS_ITEMS_AT_END` | `1UL << 23` | Variable items at end of instance | `Include/object.h:548` |
| `_Py_TPFLAGS_STATIC_BUILTIN` | `1UL << 1` | Initialized via `_PyStaticType_InitBuiltin()` | `Include/object.h:467` |
| `Py_TPFLAGS_SEQUENCE` | `1UL << 5` | Treated as sequence for pattern matching | `Include/object.h:490` |
| `Py_TPFLAGS_MAPPING` | `1UL << 6` | Treated as mapping for pattern matching | `Include/object.h:492` |

Fast subclass flags (`Include/object.h:551-558`):
`Py_TPFLAGS_LONG_SUBCLASS` (24), `Py_TPFLAGS_LIST_SUBCLASS` (25), `Py_TPFLAGS_TUPLE_SUBCLASS` (26), `Py_TPFLAGS_BYTES_SUBCLASS` (27), `Py_TPFLAGS_UNICODE_SUBCLASS` (28), `Py_TPFLAGS_DICT_SUBCLASS` (29), `Py_TPFLAGS_BASE_EXC_SUBCLASS` (30), `Py_TPFLAGS_TYPE_SUBCLASS` (31).

### 2.3 Type Slot Protocols

| Protocol | Struct | Slots | Source Evidence |
|----------|--------|-------|-----------------|
| Number | `PyNumberMethods` | `nb_add`, `nb_subtract`, `nb_multiply`, `nb_remainder`, `nb_divmod`, `nb_power`, `nb_negative`, `nb_positive`, `nb_absolute`, `nb_bool`, `nb_invert`, `nb_lshift`, `nb_rshift`, `nb_and`, `nb_xor`, `nb_or`, `nb_int`, `nb_float`, `nb_inplace_*`, `nb_floor_divide`, `nb_true_divide`, `nb_index`, `nb_matrix_multiply` | `Include/cpython/object.h:61-106` |
| Sequence | `PySequenceMethods` | `sq_length`, `sq_concat`, `sq_repeat`, `sq_item`, `sq_ass_item`, `sq_contains`, `sq_inplace_concat`, `sq_inplace_repeat` | `Include/cpython/object.h:108-120` |
| Mapping | `PyMappingMethods` | `mp_length`, `mp_subscript`, `mp_ass_subscript` | `Include/cpython/object.h:122-126` |
| Async | `PyAsyncMethods` | `am_await`, `am_aiter`, `am_anext`, `am_send` | `Include/cpython/object.h:130-135` |
| Buffer | `PyBufferProcs` | `bf_getbuffer`, `bf_releasebuffer` | `Include/cpython/object.h:137-140` |

---

## 3. Memory Allocation

### 3.1 Allocation API Tiers

| API | Function | Purpose | Source Evidence |
|-----|----------|---------|-----------------|
| Raw | `PyMem_RawMalloc/Calloc/Realloc/Free` | GIL-free, wraps platform malloc | `Include/pymem.h:95-98` |
| PyMem | `PyMem_Malloc/Calloc/Realloc/Free` | GIL-required, general purpose | `Include/pymem.h:48-51` |
| PyObject | `PyObject_Malloc/Calloc/Realloc/Free` | GIL-required, object allocator (optimized for small objects) | `Include/objimpl.h:93-98` |
| Typed | `PyObject_New(type, typeobj)` | Allocate+initialize typed object | `Include/objimpl.h:130` |
| Typed Var | `PyObject_NewVar(type, typeobj, n)` | Allocate+initialize variable-size typed object | `Include/objimpl.h:136-137` |
| Init | `PyObject_Init(op, typeobj)` | Initialize existing allocation with type info | `Include/objimpl.h:117` |
| InitVar | `PyObject_InitVar(op, typeobj, size)` | Initialize variable-size object | `Include/objimpl.h:118-119` |
| Typed Mem | `PyMem_New(type, n)` | Type-safe PyMem allocation with overflow check | `Include/pymem.h:63-65` |

### 3.2 GC-Tracked Allocation

| API | Purpose | Source Evidence |
|-----|---------|-----------------|
| `_PyObject_GC_New(typeobj)` | Allocate GC-tracked object | `Include/objimpl.h:165` |
| `_PyObject_GC_NewVar(typeobj, n)` | Allocate variable-size GC-tracked object | `Include/objimpl.h:166` |
| `PyObject_GC_New(type, typeobj)` | Macro wrapping `_PyObject_GC_New` | `Include/objimpl.h:180-181` |
| `PyObject_GC_NewVar(type, typeobj, n)` | Macro wrapping `_PyObject_GC_NewVar` | `Include/objimpl.h:182-183` |
| `PyObject_GC_Track(op)` | Tell GC to track this object | `Include/objimpl.h:171` |
| `PyObject_GC_UnTrack(op)` | Stop GC tracking | `Include/objimpl.h:176` |
| `PyObject_GC_Del(op)` | Free GC-tracked object | `Include/objimpl.h:178` |
| `PyObject_GC_IsTracked(op)` | Check if object is tracked | `Include/objimpl.h:185` |
| `PyObject_GC_IsFinalized(op)` | Check if object was finalized | `Include/objimpl.h:186` |

### 3.3 GC Header Layout

| Pattern | Description | Source Evidence |
|---------|-------------|-----------------|
| `PyGC_Head` | Prepended before GC-tracked objects | `Include/internal/pycore_gc.h:17-26` |
| `_Py_AS_GC(op)` | `(char*)op - sizeof(PyGC_Head)` | `Include/internal/pycore_gc.h:17-20` |
| `_Py_FROM_GC(gc)` | `(char*)gc + sizeof(PyGC_Head)` | `Include/internal/pycore_gc.h:23-26` |
| `_gc_next` | 0 = untracked; non-zero = pointer to next in GC list | `Python/gc.c:184-191` |
| `_gc_prev` | Used for doubly-linked list; also holds `gc_refs` during collection | `Python/gc.c:156-178` |

### 3.4 Free Lists

Objects of common types use free lists for fast allocation (`Objects/object.c:926-958`):
- Floats, complexes, tuples, lists, list_iters, tuple_iters, dicts, dictkeys, slices, ranges, range_iters, contexts, async_gens, unicode_writers, bytes_writers, ints, pycfunctionobject, pycmethodobject, pymethodobjects, object_stack_chunks.

---

## 4. Garbage Collector

### 4.1 Generational GC Structure

| Component | Description | Source Evidence |
|-----------|-------------|-----------------|
| `NUM_GENERATIONS` | 3 generations | `Python/gc.c:101` (GEN_HEAD macro) |
| `generation0` | Youngest generation (collected most frequently) | `Python/gc.c:125` |
| `permanent_generation` | Objects that are never collected | `Python/gc.c:126` |
| `gc_collect_main()` | Main collection function | `Python/gc.c:1422-1650` |

### 4.2 GC Collection Algorithm

1. **update_refs()** (`Python/gc.c:396-436`): Copies `ob_refcnt` to `gc_prev` for each object in the generation being collected. Skips immortal objects (untracks them).
2. **subtract_refs()** (`Python/gc.c:489-501`): Calls `tp_traverse` on each object; for each referenced object in the same generation, decrements its `gc_refs`.
3. **move_unreachable()** (`Python/gc.c:578-650`): Identifies unreachable objects (gc_refs == 0) and moves them to unreachable list. Uses `NEXT_MASK_UNREACHABLE` flag.
4. **handle_weakref_callbacks()** (`Python/gc.c:807-952`): Processes weakrefs to unreachable objects, invoking callbacks for external weakrefs.
5. **finalize_garbage()** (`Python/gc.c:1045-1076`): Calls `tp_finalize` on objects that have it.
6. **handle_resurrected_objects()** (`Python/gc.c:1234-1251`): Handles objects resurrected by finalizers.
7. **delete_garbage()** (`Python/gc.c:1082-1119`): Calls `tp_clear` on unreachable objects to break cycles.

### 4.3 GC Visit Protocol

| Pattern | Usage | Source Evidence |
|---------|-------|-----------------|
| `Py_VISIT(op)` | Call `visit(op, arg)` in `tp_traverse` | `Include/objimpl.h:193-200` |
| `_Py_VISIT_STACKREF(ref)` | Visit a stackref (handles deferred refcounting) | `Include/internal/pycore_stackref.h:841` |
| `_PyGC_VisitStackRef(ref, visit, arg)` | Visit stackref during GC traversal | `Python/gc.c:458-470` |
| `_PyGC_VisitFrameStack(frame, visit, arg)` | Visit all stackrefs in a frame | `Python/gc.c:472-483` |
| `visit_decref(op, parent)` | GC traversal callback to decrement gc_refs | `Python/gc.c:440-456` |
| `visit_reachable(op, arg)` | GC callback marking reachable objects | `Python/gc.c:503-564` |
| `visit_move(op, arg)` | GC callback moving objects between lists | `Python/gc.c:736-749` |

### 4.4 GC Bits (Py_GIL_DISABLED)

| Bit | Value | Meaning | Source Evidence |
|-----|-------|---------|-----------------|
| `_PyGC_BITS_TRACKED` | `1<<0` | Tracked by GC | `Include/internal/pycore_gc.h:39` |
| `_PyGC_BITS_FINALIZED` | `1<<1` | tp_finalize was called | `Include/internal/pycore_gc.h:40` |
| `_PyGC_BITS_UNREACHABLE` | `1<<2` | Unreachable | `Include/internal/pycore_gc.h:41` |
| `_PyGC_BITS_FROZEN` | `1<<3` | Frozen (not collected) | `Include/internal/pycore_gc.h:42` |
| `_PyGC_BITS_SHARED` | `1<<4` | Shared between threads | `Include/internal/pycore_gc.h:43` |
| `_PyGC_BITS_ALIVE` | `1<<5` | Reachable from known root | `Include/internal/pycore_gc.h:44` |
| `_PyGC_BITS_DEFERRED` | `1<<6` | Uses deferred reference counting | `Include/internal/pycore_gc.h:45` |

### 4.5 GC State Flags During Collection

| Flag | Location | Purpose | Source Evidence |
|------|----------|---------|-----------------|
| `PREV_MASK_COLLECTING` | `_gc_prev` lowest bit | Marks objects in current collection generation | `Python/gc.c:39` |
| `NEXT_MASK_UNREACHABLE` | `_gc_next` lowest bit | Marks unreachable objects | `Python/gc.c:50` |

---

## 5. C Extension Module Patterns

### 5.1 Module Definition

| Pattern | Structure/Function | Source Evidence |
|---------|-------------------|-----------------|
| `PyModuleDef` | `m_base`, `m_name`, `m_doc`, `m_size`, `m_methods`, `m_slots`, `m_traverse`, `m_clear`, `m_free` | `Include/moduleobject.h:108-118` |
| `PyModuleDef_Base` | `m_init`, `m_index`, `m_copy` | `Include/moduleobject.h:40-59` |
| `PyModuleDef_HEAD_INIT` | Static initializer for `PyModuleDef_Base` | `Include/moduleobject.h:61-66` |
| `PyModule_Create(def)` | Create single-phase module | `Include/modsupport.h:65-66` |
| `PyModule_Create2(def, apiver)` | Create module with API version check | `Include/modsupport.h:59` |
| `PyModule_FromDefAndSpec2(def, spec, ver)` | Create multi-phase module | `Include/modsupport.h:71` |
| `PyModule_ExecDef(module, def)` | Execute module definition (multi-phase) | `Include/modsupport.h:54` |

### 5.2 Module Init Function Signatures

| Pattern | Signature | Source Evidence |
|---------|-----------|-----------------|
| `PyMODINIT_FUNC` | Return type for module init functions | `Include/exports.h` (typical) |
| `PyInit_<modname>` | Module entry point name convention | Python import system convention |
| Single-phase init | `PyObject* PyInit_modname(void)` returns module object | Common C extension pattern |
| Multi-phase init | `PyObject* PyInit_modname(void)` returns `PyModuleDef` | `Include/moduleobject.h:71-74` |

### 5.3 Method Definition

| Structure | Fields | Source Evidence |
|-----------|--------|-----------------|
| `PyMethodDef` | `ml_name`, `ml_meth` (PyCFunction), `ml_flags`, `ml_doc` | `Include/methodobject.h:68-74` |

### 5.4 C Function Pointer Types

| Type | Signature | Source Evidence |
|------|-----------|-----------------|
| `PyCFunction` | `(PyObject *, PyObject *) -> PyObject *` | `Include/methodobject.h:19` |
| `PyCFunctionFast` | `(PyObject *, PyObject *const *, Py_ssize_t) -> PyObject *` | `Include/methodobject.h:20` |
| `PyCFunctionWithKeywords` | `(PyObject *, PyObject *, PyObject *) -> PyObject *` | `Include/methodobject.h:21-22` |
| `PyCFunctionFastWithKeywords` | `(PyObject *, PyObject *const *, Py_ssize_t, PyObject *) -> PyObject *` | `Include/methodobject.h:23-25` |
| `PyCMethod` | `(PyObject *, PyTypeObject *, PyObject *const *, Py_ssize_t, PyObject *) -> PyObject *` | `Include/methodobject.h:26-27` |

### 5.5 Method Flags (METH_*)

| Flag | Value | Meaning | Source Evidence |
|------|-------|---------|-----------------|
| `METH_VARARGS` | `0x0001` | Takes `(self, args)` tuple | `Include/methodobject.h:95` |
| `METH_KEYWORDS` | `0x0002` | Takes `(self, args, kwargs)` dict | `Include/methodobject.h:96` |
| `METH_NOARGS` | `0x0004` | Takes `(self, NULL)` | `Include/methodobject.h:98` |
| `METH_O` | `0x0008` | Takes `(self, single_arg)` | `Include/methodobject.h:99` |
| `METH_CLASS` | `0x0010` | Class method | `Include/methodobject.h:104` |
| `METH_STATIC` | `0x0020` | Static method | `Include/methodobject.h:105` |
| `METH_COEXIST` | `0x0040` | Coexist with slot method | `Include/methodobject.h:112` |
| `METH_FASTCALL` | `0x0080` | Fast call convention | `Include/methodobject.h:115` |
| `METH_METHOD` | `0x0200` | Bound method with class | `Include/methodobject.h:133` |

### 5.6 Argument Parsing

| Function | Signature | Source Evidence |
|----------|-----------|-----------------|
| `PyArg_Parse(args, format, ...)` | Parse positional args | `Include/modsupport.h:9` |
| `PyArg_ParseTuple(args, format, ...)` | Parse tuple args | `Include/modsupport.h:10` |
| `PyArg_ParseTupleAndKeywords(args, kw, format, keywords, ...)` | Parse args + kwargs | `Include/modsupport.h:11-12` |
| `Py_BuildValue(format, ...)` | Build Python objects from C values | `Include/modsupport.h:19` |

---

## 6. Buffer Protocol

### 6.1 Py_buffer Structure

| Field | Type | Description | Source Evidence |
|-------|------|-------------|-----------------|
| `buf` | `void *` | Pointer to buffer data | `Include/pybuffer.h:21` |
| `obj` | `PyObject *` | Owning reference | `Include/pybuffer.h:22` |
| `len` | `Py_ssize_t` | Total bytes in buffer | `Include/pybuffer.h:23` |
| `itemsize` | `Py_ssize_t` | Element size in bytes | `Include/pybuffer.h:24` |
| `readonly` | `int` | 1 if readonly, 0 if writable | `Include/pybuffer.h:26` |
| `ndim` | `int` | Number of dimensions | `Include/pybuffer.h:27` |
| `format` | `char *` | Format string (struct module style) | `Include/pybuffer.h:28` |
| `shape` | `Py_ssize_t *` | Shape array | `Include/pybuffer.h:29` |
| `strides` | `Py_ssize_t *` | Stride array | `Include/pybuffer.h:30` |
| `suboffsets` | `Py_ssize_t *` | Suboffset array (for pointers) | `Include/pybuffer.h:31` |
| `internal` | `void *` | Internal use | `Include/pybuffer.h:32` |

### 6.2 Buffer API Functions

| Function | Purpose | Source Evidence |
|----------|---------|-----------------|
| `PyObject_CheckBuffer(obj)` | Check if object supports buffer protocol | `Include/pybuffer.h:39` |
| `PyObject_GetBuffer(obj, view, flags)` | Acquire buffer (increments refcount on `obj`) | `Include/pybuffer.h:46-47` |
| `PyBuffer_Release(view)` | Release buffer (decrements refcount on `view->obj`) | Standard API |
| `PyBuffer_IsContiguous(view, order)` | Check if buffer is contiguous | `Include/pybuffer.h:80` |
| `PyBuffer_FillInfo(view, o, buf, len, readonly, flags)` | Fill buffer info for simple contiguous buffer | `Include/pybuffer.h:97-99` |

### 6.3 Buffer Request Flags

| Flag | Purpose |
|------|---------|
| `PyBUF_SIMPLE` | Simple contiguous buffer |
| `PyBUF_WRITABLE` | Writable buffer |
| `PyBUF_FORMAT` | Request format string |
| `PyBUF_ND` | Request shape array |
| `PyBUF_STRIDES` | Request strides array |
| `PyBUF_C_CONTIGUOUS` | C-contiguous |
| `PyBUF_F_CONTIGUOUS` | Fortran-contiguous |
| `PyBUF_ANY_CONTIGUOUS` | Any contiguous |
| `PyBUF_INDIRECT` | Indirect (pointer-based) buffer |

---

## 7. PyCapsule API

| Function | Purpose | Source Evidence |
|----------|---------|-----------------|
| `PyCapsule_New(pointer, name, destructor)` | Wrap C void* in Python object | `Include/pycapsule.h:28-31` |
| `PyCapsule_GetPointer(capsule, name)` | Extract pointer (validates name) | `Include/pycapsule.h:33` |
| `PyCapsule_GetDestructor(capsule)` | Get destructor | `Include/pycapsule.h:35` |
| `PyCapsule_GetName(capsule)` | Get capsule name | `Include/pycapsule.h:37` |
| `PyCapsule_GetContext(capsule)` | Get context pointer | `Include/pycapsule.h:39` |
| `PyCapsule_IsValid(capsule, name)` | Validate capsule | `Include/pycapsule.h:41` |
| `PyCapsule_Import(name, no_block)` | Import capsule from module | `Include/pycapsule.h:51-53` |

---

## 8. CPython Internal / Runtime Structures

### 8.1 Runtime State

| Structure | Purpose | Source Evidence |
|-----------|---------|-----------------|
| `_PyRuntimeState` | Global runtime state (process-wide) | `Include/internal/pycore_runtime.h:19` |
| `_PyRuntime` | The single global instance | `Include/internal/pycore_runtime.h:19` |
| `_pymem_allocators` | Memory allocator state (raw, mem, obj + debug variants) | `Include/internal/pycore_runtime_structs.h:21-36` |

### 8.2 Interpreter Frame

| Structure | Key Fields | Source Evidence |
|-----------|------------|-----------------|
| `_PyInterpreterFrame` | `f_executable` (_PyStackRef), `previous`, `f_funcobj` (_PyStackRef), `f_globals`, `f_builtins`, `f_locals`, `frame_obj`, `instr_ptr`, `stackpointer`, `tlbc_index` (Py_GIL_DISABLED), `return_offset`, `owner`, `localsplus[1]` | `Include/internal/pycore_interpframe_structs.h:29-53` |
| `PyFrameObject` | `f_back`, `f_frame`, `f_trace`, `f_lineno`, `f_trace_lines`, `f_trace_opcodes`, `f_extra_locals`, `f_locals_cache`, `f_overwritten_fast_locals`, `_f_frame_data[1]` | `Include/internal/pycore_frame.h:18-39` |

Frame owners (`Include/internal/pycore_interpframe_structs.h:22-27`):
- `FRAME_OWNED_BY_THREAD` (0)
- `FRAME_OWNED_BY_GENERATOR` (1)
- `FRAME_OWNED_BY_FRAME_OBJECT` (2)
- `FRAME_OWNED_BY_INTERPRETER` (3)

### 8.3 Bytecode Unit

| Structure | Layout | Source Evidence |
|-----------|--------|-----------------|
| `_Py_CODEUNIT` | Union: `cache` (uint16_t), `op.code` (uint8_t) + `op.arg` (uint8_t), `counter` (_Py_BackoffCounter) | `Include/internal/pycore_structs.h:25-32` |
| `_Py_OPCODE(word)` | Extract opcode: `word.op.code` | `Include/internal/pycore_code.h:21` |
| `_Py_OPARG(word)` | Extract oparg: `word.op.arg` | `Include/internal/pycore_code.h:22` |

### 8.4 String Internals (PEP 393)

| Structure | Fields | Source Evidence |
|-----------|--------|-----------------|
| `PyASCIIObject` | `PyObject_HEAD`, `length`, `hash`, `state` (interned:2, kind:3, compact:1, ascii:1, statically_allocated:1) | `Include/cpython/unicodeobject.h:111-161` |
| `PyCompactUnicodeObject` | `PyASCIIObject _base`, `utf8_length`, `utf8` | `Include/cpython/unicodeobject.h:166-171` |
| `PyUnicodeObject` | `PyCompactUnicodeObject _base`, `data` (union: any/latin1/ucs2/ucs4) | `Include/cpython/unicodeobject.h:174-182` |

String kinds: `PyUnicode_1BYTE_KIND` (1), `PyUnicode_2BYTE_KIND` (2), `PyUnicode_4BYTE_KIND` (4) (`Include/cpython/unicodeobject.h:70-88`).

### 8.5 Identifier Caching

| Pattern | Description | Source Evidence |
|---------|-------------|-----------------|
| `_Py_Identifier` | `{ const char* string; Py_ssize_t index; struct { uint8_t v; } mutex; }` | `Include/cpython/object.h:39-48` |
| `_Py_IDENTIFIER(varname)` | Declares `static _Py_Identifier PyId_##varname` | `Include/cpython/object.h:56` |
| `_Py_static_string(varname, value)` | Declares static string identifier | `Include/cpython/object.h:55` |

---

## 9. Object Lifecycle Patterns

### 9.1 Allocation-Deallocation Path

```
PyObject_New(type, typeobj)
  -> _PyObject_New(typeobj)
    -> PyObject_Malloc(_PyObject_SIZE(tp))
    -> _PyObject_Init(op, tp)   [sets ob_refcnt=1, ob_type=tp]

Py_DECREF(op) when refcount reaches 0:
  -> _Py_Dealloc(op)            [Objects/object.c:3283-3339]
    -> type->tp_dealloc(op)     [user-defined destructor]
```

### 9.2 Trashcan Mechanism

When recursive deallocation depth exceeds threshold, objects are deferred:
```
_Py_Dealloc(op):
  if margin < 2 && gc_flag:
    _PyTrash_thread_deposit_object(tstate, op)  // defer
    return
  (*dealloc)(op)  // normal deallocation
  if tstate->delete_later && margin >= 4:
    _PyTrash_thread_destroy_chain(tstate)  // process deferred
```
Source: `Objects/object.c:3289-3338`

### 9.3 Object Finalization (PEP 442)

```
tp_finalize(op):
  Called once per object (guarded by _PyGC_FINALIZED flag)
  Can resurrect object (increment refcount)
  If resurrected, object survives collection

tp_del(op):
  Legacy finalizer (pre-PEP 442)
  Objects with tp_del are uncollectable if in cycles
```
Source: `Python/gc.c:678-683`, `Python/gc.c:1045-1076`

---

## 10. Key Takeaways for Static Analysis

### What's user C extension code (analyze these):
- Functions registered via `PyMethodDef` tables with `ml_meth` pointing to user-defined C functions
- `PyInit_*` module init functions
- Custom `tp_dealloc`, `tp_traverse`, `tp_clear`, `tp_init`, `tp_new` implementations
- `PyCFunction` / `PyCFunctionWithKeywords` implementations
- Any code using `PyArg_ParseTuple*` / `Py_BuildValue`
- Buffer protocol implementations (`bf_getbuffer`, `bf_releasebuffer`)

### What's CPython internal runtime (filter/skip these):
- `_Py_*` prefixed functions (internal API)
- `PyAPI_FUNC` declarations in `Include/internal/` headers
- `_PyRuntimeState`, `_PyInterpreterState`, `_PyThreadState` fields
- `_Py_CODEUNIT` / bytecode manipulation
- `_PyStackRef` operations (eval loop internals)
- `_PyDealloc` and the trashcan mechanism internals
- GC internals: `update_refs`, `subtract_refs`, `move_unreachable`, etc.
- `_Py_IDENTIFIER` / `_Py_static_string` infrastructure
- Free list management (`_PyObject_ClearFreeLists`)
- Runtime state initialization (`_PyRuntimeState_Init`, `_PyGC_Init`)

### What's the FFI boundary (analyze for safety):
- `PyObject *` crossing between C extension and Python
- Reference count ownership transfer patterns:
  - **Owned reference**: Caller must `Py_DECREF` (e.g., `Py_NewRef`, `PyObject_New`)
  - **Borrowed reference**: Caller must NOT `Py_DECREF` (e.g., `PyTuple_GetItem`, `PyDict_GetItemString`)
  - **Stolen reference**: Ownership transferred (e.g., `PyTuple_SetItem`, `PyList_SetItem`)
- `PyCapsule` usage (opaque pointer wrapping)
- Buffer protocol (`PyObject_GetBuffer` / `PyBuffer_Release`)
- `tp_traverse` / `tp_clear` implementations (GC safety)
- `tp_dealloc` implementations (must handle partially-initialized objects)

### Common Reference Counting Bugs to Detect:
1. **Double DECREF**: Calling `Py_DECREF` twice on same reference without intervening `Py_INCREF`
2. **Missing DECREF**: Failing to `Py_DECREF` an owned reference before returning (memory leak)
3. **Borrowed reference escape**: Returning or storing a borrowed reference beyond its lifetime
4. **Stolen reference misuse**: `Py_DECREF`-ing a reference already stolen by `PyTuple_SetItem`
5. **NULL dereference**: Not checking for `NULL` return from allocation/API functions
6. **Use after DECREF**: Accessing object after `Py_DECREF` when refcount may reach 0
7. **Missing GC visit**: Failing to visit all contained objects in `tp_traverse` (causes missed cycles)
8. **Buffer release omission**: Failing to call `PyBuffer_Release` after `PyObject_GetBuffer`

### What to filter vs what to analyze:

| Category | Action | Rationale |
|----------|--------|-----------|
| `Py_INCREF` / `Py_DECREF` / `Py_XDECREF` | Analyze | Core memory safety |
| `PyObject_New` / `PyObject_GC_New` | Analyze | Allocation tracking |
| `tp_dealloc` / `tp_traverse` / `tp_clear` | Analyze | GC and lifecycle safety |
| `PyBuffer_*` / `PyObject_GetBuffer` | Analyze | Buffer safety |
| `PyCapsule_*` | Analyze | Opaque pointer safety |
| `PyArg_ParseTuple*` | Analyze | Argument validation |
| `_Py_Dealloc` internals | Filter | Runtime plumbing |
| `_PyStackRef` operations | Filter | Eval loop internals |
| GC algorithm internals | Filter | Runtime GC machinery |
| `_PyRuntimeState` / `_PyInterpreterState` | Filter | Runtime state management |
| Free list operations | Filter | Allocator internals |
| Immortal object checks | Filter | Optimizations, always safe |

---

## 11. Complete _Py_Dealloc Path

Source: `Objects/object.c:3283-3339`

```
_Py_Dealloc(PyObject *op):
    type = Py_TYPE(op)
    gc_flag = type->tp_flags & Py_TPFLAGS_HAVE_GC
    dealloc = type->tp_dealloc

    // Trashcan: defer if recursion depth is too low
    if recursion_margin < 2 and gc_flag:
        _PyTrash_thread_deposit_object(op)
        return

    // Debug: save current exception, incref type
    old_exc = tstate->current_exception
    Py_XINCREF(old_exc)
    Py_INCREF(type)

    // Forget reference (Py_TRACE_REFS build)
    _Py_ForgetReference(op)

    // Track destruction
    _PyReftracerTrack(op, PyRefTracer_DESTROY)

    // Call the actual destructor
    (*dealloc)(op)

    // Debug: verify exception is unchanged
    assert(tstate->current_exception == old_exc)

    // Process deferred trashcan objects
    if tstate->delete_later and margin >= 4 and gc_flag:
        _PyTrash_thread_destroy_chain(tstate)
```

---

## 12. Deferred Reference Counting (Py_GIL_DISABLED)

Source: `Include/internal/pycore_object.h:28`

| Pattern | Description |
|---------|-------------|
| `_Py_REF_DEFERRED` | `PY_SSIZE_T_MAX / 8` — added to `ob_ref_shared` for deferred objects |
| `_PyGC_BITS_DEFERRED` | GC bit flag indicating deferred refcounting |
| `_PyObject_HasDeferredRefcount()` | Check if object uses deferred refcounting |

Deferred reference counting avoids atomic operations for objects accessed primarily from one thread (e.g., module globals). The shared refcount is biased upward so it never reaches zero from non-deferred decrefs alone.
