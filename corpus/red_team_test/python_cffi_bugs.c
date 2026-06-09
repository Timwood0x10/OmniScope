/**
 * Python → C (CPython API / ctypes / cffi) FFI Boundary Bugs
 *
 * Tests cross-language issues at the Python ↔ C boundary.
 * Python has GC + reference counting; C has manual memory.
 * Bugs arise from refcount errors, GC interaction, and type confusion.
 *
 * Uses Python C API naming (Py_, PyObject_, PyList_, etc.) for detection.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* Simulated Python C API types */
typedef struct _object { int ob_refcnt; void* ob_type; } PyObject;
typedef PyObject PyListObject;
typedef PyObject PyBytesObject;
typedef PyObject PyTupleObject;

/* Simulated Python C API functions */
extern PyObject*  PyList_New(int size);
extern PyObject*  PyList_GetItem(PyObject* list, int index);
extern void       Py_DECREF(PyObject* obj);
extern void       Py_INCREF(PyObject* obj);
extern PyObject*  PyBytes_FromStringAndSize(const char* v, int len);
extern char*      PyBytes_AsString(PyObject* bytes);
extern PyObject*  PyTuple_New(int size);
extern int        PyTuple_SetItem(PyObject* tuple, int pos, PyObject* item);
extern PyObject*  PyObject_GetAttrString(PyObject* obj, const char* name);
extern int        PyLong_AsLong(PyObject* obj);
extern PyObject*  PyLong_FromLong(long val);

/* ============================================================
 * PY-01: Py_DECREF without Py_INCREF (CWE-415 → double free)
 * C receives a borrowed reference from Python but DECREFs it.
 * Borrowed references are owned by Python — C should not DECREF.
 * Expected: double_free / refcount_violation
 * ============================================================ */
void py_01_borrowed_ref_decref(PyObject* list) {
    /* PyList_GetItem returns a borrowed reference */
    PyObject* item = PyList_GetItem(list, 0);
    /* BUG: DECREF on a borrowed reference — Python still owns it */
    Py_DECREF(item);  /* double free when Python GC runs */
}

/* ============================================================
 * PY-02: Missing Py_DECREF on new reference (CWE-401)
 * C creates a new reference via PyBytes_FromStringAndSize but
 * never DECREFs → Python object never freed → leak.
 * Expected: memory_leak / refcount_leak
 * ============================================================ */
void py_02_new_ref_leak(void) {
    PyObject* bytes = PyBytes_FromStringAndSize("hello", 5);
    char* data = PyBytes_AsString(bytes);
    printf("bytes: %s\n", data);
    /* BUG: never Py_DECREF(bytes) — new reference leaked */
}

/* ============================================================
 * PY-03: Use after Py_DECREF (CWE-416)
 * C DECREFs the object, then continues using the pointer.
 * If refcount hits 0, Python frees the object.
 * Expected: use_after_free
 * ============================================================ */
void py_03_use_after_decref(void) {
    PyObject* bytes = PyBytes_FromStringAndSize("temporary", 9);
    char* data = PyBytes_AsString(bytes);

    Py_DECREF(bytes);  /* may free the object */

    /* BUG: bytes may be freed, data pointer is dangling */
    printf("freed: %s\n", data);  /* UAF */
}

/* ============================================================
 * PY-04: PyTuple_SetItem steals reference, then C uses it (CWE-416)
 * PyTuple_SetItem steals the reference (does NOT incref).
 * After SetItem, Python owns the object. C must not use it.
 * Expected: use_after_free / ownership_violation
 * ============================================================ */
void py_04_steal_ref_misuse(void) {
    PyObject* tuple = PyTuple_New(2);
    PyObject* val1 = PyLong_FromLong(42);
    PyObject* val2 = PyLong_FromLong(99);

    PyTuple_SetItem(tuple, 0, val1);  /* steals val1 ref */
    PyTuple_SetItem(tuple, 1, val2);  /* steals val2 ref */

    /* BUG: val1 and val2 are now owned by tuple */
    /* Using them without INCREF is unsafe */
    long v = PyLong_AsLong(val1);  /* UAF if tuple is collected */
    printf("val1 = %ld\n", v);
}

/* ============================================================
 * PY-05: C stores Python object without INCREF (CWE-416)
 * C caches a Python object pointer but doesn't INCREF it.
 * Python GC may collect the object → C's cache is dangling.
 * Expected: use_after_free / gc_interaction
 * ============================================================ */
static PyObject* g_cached_py_obj = NULL;

void py_05_cache_no_incref(PyObject* obj) {
    /* BUG: storing without INCREF — Python may GC this object */
    g_cached_py_obj = obj;
}

void py_05_use_cached(void) {
    /* BUG: g_cached_py_obj may have been collected */
    if (g_cached_py_obj) {
        long val = PyLong_AsLong(g_cached_py_obj);  /* UAF */
        printf("cached: %ld\n", val);
    }
}

/* ============================================================
 * PY-06: C frees Python-managed memory (CWE-763)
 * Python allocates a bytes object. C gets the raw buffer pointer.
 * C frees it with free() instead of Py_DECREF.
 * Expected: cross_language_free
 * ============================================================ */
void py_06_free_python_memory(void) {
    PyObject* bytes = PyBytes_FromStringAndSize("data", 4);
    char* buf = PyBytes_AsString(bytes);

    /* BUG: freeing Python-managed memory with C's free() */
    free(buf);  /* cross-language free mismatch */
    /* Should be: Py_DECREF(bytes) */
}

/* ============================================================
 * PY-07: Reentrant Python call from C callback (CWE-662)
 * C callback is invoked by Python. The callback makes another
 * Python API call without holding the GIL → data race / crash.
 * Expected: gil_violation / concurrency
 * ============================================================ */
extern void PyGILState_Ensure(void);
extern void PyGILState_Release(void);

void py_07_callback_no_gil(PyObject* callback) {
    /* BUG: calling Python API from C callback without GIL */
    /* Should call PyGILState_Ensure() first */
    PyObject* result = PyObject_GetAttrString(callback, "__call__");
    Py_DECREF(result);
}

/* ============================================================
 * PY-08: Cross-language free in ctypes/cffi scenario (CWE-763)
 * Python's ctypes allocates a buffer via foreign allocator.
 * C receives it and frees with free().
 * Expected: cross_language_free
 * ============================================================ */
extern void* ctypes_alloc(int size);
extern void  ctypes_free(void* ptr);

void py_08_ctypes_wrong_free(void) {
    void* buf = ctypes_alloc(512);
    memset(buf, 0, 512);
    /* BUG: using C free() instead of ctypes_free() */
    free(buf);  /* cross-language free */
}
