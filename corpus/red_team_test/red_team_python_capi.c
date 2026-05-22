/**
 * OmniScope Red Team — Python C Extension Bug Test Cases
 *
 * Simulates bugs that occur in Python C extensions using CPython C API.
 * Based on patterns from PYTHON_IR_SPEC.md:
 *   - Reference counting errors (over-decref, under-decref)
 *   - Borrowed reference escape
 *   - Buffer protocol violations
 *   - GIL safety issues
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Simulated CPython types and macros */
typedef long Py_ssize_t;
typedef struct _object {
    Py_ssize_t ob_refcnt;
    struct _typeobject *ob_type;
} PyObject;

typedef struct _typeobject {
    const char *tp_name;
    void (*tp_dealloc)(PyObject*);
    Py_ssize_t tp_basicsize;
} PyTypeObject;

typedef struct {
    PyObject ob_base;
    char *ob_buf;
    Py_ssize_t ob_len;
    Py_ssize_t ob_alloc;
} PyBytesObject;

/* Simulated reference counting */
static Py_ssize_t g_live_objects = 0;

static PyObject* _Py_NewObject(PyTypeObject *type) {
    PyObject *obj = (PyObject*)malloc(type->tp_basicsize);
    obj->ob_refcnt = 1;
    obj->ob_type = type;
    g_live_objects++;
    return obj;
}

static void _Py_INCREF(PyObject *obj) {
    obj->ob_refcnt++;
}

static void _Py_DECREF(PyObject *obj) {
    obj->ob_refcnt--;
    if (obj->ob_refcnt == 0) {
        g_live_objects--;
        free(obj);
    }
}

static PyTypeObject PyBytes_Type = {"bytes", NULL, sizeof(PyBytesObject)};

/* ================================================================
 * PY-BUG-01: Missing Py_DECREF — Memory Leak
 *
 * C extension creates a Python object but forgets to DECREF it
 * when done. The object leaks.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
void py_bug_01_missing_decref(void) {
    PyObject *obj = _Py_NewObject(&PyBytes_Type);
    _Py_INCREF(obj);  /* refcount = 1 */

    /* Use the object... */
    printf("PY-BUG-01: object created, refcount=%ld\n", obj->ob_refcnt);

    /* [BUG] Forgot _Py_DECREF(obj) — memory leak! */
    /* Should have: _Py_DECREF(obj); */
}

/* ================================================================
 * PY-BUG-02: Double Py_DECREF — Use After Free
 *
 * C extension decrements refcount twice. Second DECREF may
 * free the object, then later code uses it.
 *
 * Expected: use_after_free / double_free (CWE-416)
 * ================================================================ */
void py_bug_02_double_decref(void) {
    PyObject *obj = _Py_NewObject(&PyBytes_Type);
    /* refcount = 1 */

    _Py_DECREF(obj);
    /* refcount = 0, object freed */

    /* [BUG] Double DECREF on freed object */
    _Py_DECREF(obj);  /* UAF: obj was just freed */

    /* Use after double-free */
    printf("PY-BUG-02: type = %s\n", obj->ob_type->tp_name);  /* UAF */
}

/* ================================================================
 * PY-BUG-03: Borrowed reference stored beyond call lifetime
 *
 * A function returns a "borrowed" reference (not incref'd).
 * The caller stores it and uses it after the owning reference
 * is released.
 *
 * Expected: borrow_escape / use_after_free (CWE-416)
 * ================================================================ */
static PyObject* g_borrowed_ref = NULL;

/* Returns a borrowed reference — caller must NOT store it */
static PyObject* get_borrowed_item(PyObject *container) {
    /* In real CPython, this would be PyList_GET_ITEM */
    return container;  /* Returns same pointer, no incref */
}

void py_bug_03_borrowed_escape(void) {
    PyObject *list = _Py_NewObject(&PyBytes_Type);

    /* Get borrowed reference */
    PyObject *item = get_borrowed_item(list);
    g_borrowed_ref = item;  /* [BUG] Storing borrowed reference */

    /* Release the owning reference */
    _Py_DECREF(list);  /* list freed, g_borrowed_ref is dangling */

    /* Use the dangling borrowed reference */
    printf("PY-BUG-03: %s\n", g_borrowed_ref->ob_type->tp_name);  /* UAF */
}

/* ================================================================
 * PY-BUG-04: Py_DECREF on NULL pointer
 *
 * C extension calls DECREF without NULL check.
 * Py_XDECREF is the safe version that checks for NULL.
 *
 * Expected: null_dereference (CWE-476)
 * ================================================================ */
void py_bug_04_decref_null(void) {
    PyObject *obj = NULL;

    /* Some code path that may return NULL (e.g., failed allocation) */

    /* [BUG] Should use Py_XDECREF (null-safe) */
    _Py_DECREF(obj);  /* NULL deref: obj is NULL */
}

/* ================================================================
 * PY-BUG-05: Buffer use after release
 *
 * C extension gets a buffer from a Python object, releases it,
 * then continues to use the buffer pointer.
 *
 * Expected: use_after_free (CWE-416)
 * ================================================================ */
typedef struct {
    void *buf;
    Py_ssize_t len;
} Py_buffer;

void py_bug_05_buffer_uaf(void) {
    char *internal_buf = (char*)malloc(128);
    strcpy(internal_buf, "buffer data for testing");

    Py_buffer view;
    view.buf = internal_buf;
    view.len = 23;

    /* "Release" the buffer — simulates PyBuffer_Release */
    free(internal_buf);
    view.buf = NULL;

    /* [BUG] Use buffer after release */
    printf("PY-BUG-05: %s\n", (char*)view.buf);  /* UAF: buf was freed */
}

/* ================================================================
 * PY-BUG-06: Return stolen reference without incref
 *
 * A C function returns a reference it doesn't own.
 * The caller expects an owned reference and will DECREF it.
 * This causes the original owner's reference to be over-decremented.
 *
 * Expected: use_after_free (CWE-416)
 * ================================================================ */
static PyObject* steal_reference_bug(PyObject *owner) {
    /* [BUG] Returns borrowed ref as if it were owned.
     * Caller will DECREF it, but we never INCREF'd it. */
    return owner;  /* Should be: _Py_INCREF(owner); return owner; */
}

void py_bug_06_stolen_ref(void) {
    PyObject *owner = _Py_NewObject(&PyBytes_Type);

    PyObject *stolen = steal_reference_bug(owner);
    /* Caller thinks it owns 'stolen' (which is same as 'owner') */

    _Py_DECREF(stolen);  /* Caller releases what it thinks is its ref */
    /* owner->ob_refcnt = 0, object freed */

    /* Original owner still tries to use it */
    printf("PY-BUG-06: %s\n", owner->ob_type->tp_name);  /* UAF */
}

/* ================================================================
 * PY-BUG-07: GC-tracked object cycle with missing tp_traverse
 *
 * Object creates a reference cycle but doesn't implement tp_traverse.
 * GC cannot detect the cycle, causing a leak.
 *
 * Expected: memory_leak (CWE-401)
 * ================================================================ */
typedef struct _cyclic {
    PyObject ob_base;
    struct _cyclic *next;
} CyclicObject;

void py_bug_07_gc_cycle_leak(void) {
    CyclicObject *a = (CyclicObject*)_Py_NewObject(&PyBytes_Type);
    CyclicObject *b = (CyclicObject*)_Py_NewObject(&PyBytes_Type);

    /* Create cycle: a -> b -> a */
    a->next = b;
    b->next = a;

    /* Both have refcount = 1 from creation.
     * The cycle means refcounts never reach 0 even when
     * no external references exist. Without tp_traverse,
     * GC cannot break the cycle. */

    /* [BUG] No way to collect a and b — they reference each other */
    /* This is a memory leak */
}

/* ================================================================
 * Entry point
 * ================================================================ */
int main(void) {
    py_bug_01_missing_decref();
    py_bug_02_double_decref();
    py_bug_03_borrowed_escape();
    py_bug_04_decref_null();
    py_bug_05_buffer_uaf();
    py_bug_06_stolen_ref();
    py_bug_07_gc_cycle_leak();
    return 0;
}
